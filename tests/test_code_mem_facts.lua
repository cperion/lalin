package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local Schema = require("moonlift.schema")
local T = pvm.context()
Schema.Define(T)

local Parse = require("moonlift.parse").Define(T)
local OpenFacts = require("moonlift.open_facts").Define(T)
local OpenValidate = require("moonlift.open_validate").Define(T)
local OpenExpand = require("moonlift.open_expand").Define(T)
local ClosureConvert = require("moonlift.closure_convert").Define(T)
local Typecheck = require("moonlift.tree_typecheck").Define(T)
local Layout = require("moonlift.sem_layout_resolve").Define(T)
local TreeToCode = require("moonlift.tree_to_code").Define(T)
local CodeValidate = require("moonlift.code_validate").Define(T)
local CodeFlowFacts = require("moonlift.code_flow_facts").Define(T)
local CodeMemFacts = require("moonlift.code_mem_facts").Define(T)
local CodeKernelPlan = require("moonlift.code_kernel_plan").Define(T)
local CodeLowerPlan = require("moonlift.code_lower_plan").Define(T)
local LowerToBack = require("moonlift.lower_to_back").Define(T)
local BackValidate = require("moonlift.back_validate").Define(T)

local Core = T.MoonCore
local Code = T.MoonCode
local Mem = T.MoonMem
local Kernel = T.MoonKernel
local Lower = T.MoonLower
local Back = T.MoonBack
local i32 = Code.CodeTyInt(32, Code.CodeSigned)

local function assert_no_issues(label, issues)
    assert(#issues == 0, label .. " expected no issues, got " .. tostring(#issues))
end

local function lower(src)
    local parsed = Parse.parse_module(src)
    assert_no_issues("parse", parsed.issues)
    local expanded = OpenExpand.module(parsed.module)
    assert_no_issues("open", OpenValidate.validate(OpenFacts.facts_of_module(expanded)).issues)
    local closed = ClosureConvert.module(expanded)
    local checked = Typecheck.check_module(closed)
    assert_no_issues("typecheck", checked.issues)
    local resolved = Layout.module(checked.module)
    local code, contracts = TreeToCode.module_with_contracts(resolved)
    assert_no_issues("code", CodeValidate.validate(code).issues)
    return code, contracts
end

local module = lower([[
func copy_sum(dst: ptr(i32), src: ptr(i32), n: i32): i32
    return block loop(i: i32 = 0, acc: i32 = 0): i32
        if i >= n then yield acc end
        let x: i32 = src[i]
        dst[i] = x
        jump loop(i = i + 1, acc = acc + x)
    end
end
]])
local flow = CodeFlowFacts.facts(module)
local mem = CodeMemFacts.facts(module, flow)
assert(mem.module == module.id)
assert(#mem.accesses == 2, "expected one load and one store")
assert(#mem.aliases == 1, "expected conservative pairwise alias fact")
assert(#mem.dependences == 1, "expected conservative write dependence fact")
local saw_load, saw_store, saw_induction = false, false, false
for _, access in ipairs(mem.accesses) do
    if access.kind == Mem.MemLoad then saw_load = true end
    if access.kind == Mem.MemStore then saw_store = true end
    assert(access.inst ~= nil, "memory facts should retain CodeInstId provenance")
    assert(access.alignment.bytes >= 1, "alignment should be copied from CodeMemoryAccess")
    assert(access.trap == Mem.MemMayTrap, "default scalar accesses should preserve may-trap semantics")
    if pvm.classof(access.index) == Mem.MemIndexInduction then
        saw_induction = true
        assert(access.pattern == Mem.MemAccessContiguous, "induction indexed access should be contiguous")
    end
end
assert(saw_load and saw_store)
assert(saw_induction, "expected loop induction to feed memory index facts")
assert(pvm.classof(mem.aliases[1]) == Mem.MemAliasUnknown)
assert(pvm.classof(mem.dependences[1]) == Mem.MemDependenceUnknown)

local flow_semantics = CodeFlowFacts.semantic_facts(module, flow)
local sem = CodeMemFacts.semantic_facts(module, flow, flow_semantics)
assert(sem.module == module.id)
local param_objects = 0
for _, object in ipairs(sem.objects) do
    if object.kind == Mem.MemObjectParam then
        param_objects = param_objects + 1
        assert(pvm.classof(object.provenance) == Mem.MemProvValue, "parameter objects should keep value provenance")
        assert(pvm.classof(object.extent) == Mem.MemExtentUnknown, "raw pointer params remain extent-unknown")
    end
end
assert(param_objects == 2, "copy_sum should expose two generic raw pointer parameter objects")
assert(#sem.intervals == 2, "raw pointer accesses still get object intervals for later diagnostics/planning")
for _, safety in ipairs(sem.safety) do
    assert(pvm.classof(safety) ~= Mem.MemAccessInBounds, "raw pointer + n must not imply in-bounds without a bounded object/contract")
end

local contracted_module, contracted_contracts = lower([[
func contracted_sum(readonly p: ptr(i32), n: i32): i32
    requires bounds(p, n)
    return block loop(i: i32 = 0, acc: i32 = 0): i32
        if i >= n then yield acc end
        jump loop(i = i + 1, acc = acc + p[i])
    end
end
]])
local contracted_flow = CodeFlowFacts.facts(contracted_module)
local contracted_flow_semantics = CodeFlowFacts.semantic_facts(contracted_module, contracted_flow)
local contracted_mem = CodeMemFacts.facts(contracted_module, contracted_flow)
local contracted_sem = CodeMemFacts.semantic_facts(contracted_module, contracted_flow, contracted_flow_semantics, contracted_contracts)
local saw_contract_object, saw_contract_inbounds, saw_contract_readonly = false, false, false
for _, object in ipairs(contracted_sem.objects) do
    if object.kind == Mem.MemObjectContract then
        saw_contract_object = true
        assert(pvm.classof(object.provenance) == Mem.MemProvContract)
        assert(pvm.classof(object.extent) == Mem.MemExtentElements)
    end
end
for _, safety in ipairs(contracted_sem.safety) do
    if pvm.classof(safety) == Mem.MemAccessInBounds then saw_contract_inbounds = true end
end
for _, effect in ipairs(contracted_sem.effects) do
    if pvm.classof(effect) == Mem.MemObjectReadonly then saw_contract_readonly = true end
end
assert(saw_contract_object and saw_contract_inbounds, "bounds contracts should become reusable object extent and in-bounds facts")
assert(saw_contract_readonly, "readonly contracts should become reusable object effect facts")
local contracted_kernels = CodeKernelPlan.plan(contracted_module, contracted_flow, contracted_mem, contracted_contracts, contracted_flow_semantics, contracted_sem)
assert(contracted_kernels.memory_semantics == contracted_sem, "kernel module should carry normalized memory semantics as ASDL")
assert(pvm.classof(contracted_kernels.funcs[1].plan) == Kernel.KernelPlanned, "contract-normalized pointer safety should feed kernel planning")
local contracted_lowered = CodeLowerPlan.plan(contracted_module, contracted_kernels)
local contracted_program = LowerToBack.module(contracted_module, contracted_lowered, { validate = false })
assert(#BackValidate.validate(contracted_program).issues == 0, "contract-normalized kernel lowering should validate")
local saw_contract_back_semantics = false
local saw_contract_back_readonly = false
for _, cmd in ipairs(contracted_program.cmds or {}) do
    if pvm.classof(cmd) == Back.CmdLoadInfo and pvm.classof(cmd.memory.trap) == Back.BackNonTrapping then saw_contract_back_semantics = true end
    if pvm.classof(cmd) == Back.CmdLoadInfo and cmd.memory.mode == Back.BackAccessReadonly then saw_contract_back_readonly = true end
end
assert(saw_contract_back_semantics, "contract-normalized pointer kernel should emit semantic Back metadata")
assert(saw_contract_back_readonly, "readonly object effects should reach Back load metadata")

local disjoint_module, disjoint_contracts = lower([[
func contracted_copy(writeonly dst: ptr(i32), readonly src: ptr(i32), n: i32): i32
    requires bounds(dst, n)
    requires bounds(src, n)
    requires disjoint(dst, src)
    block loop(i: i32 = 0)
        if i >= n then return 0 end
        dst[i] = src[i]
        jump loop(i = i + 1)
    end
end
]])
local disjoint_flow = CodeFlowFacts.facts(disjoint_module)
local disjoint_flow_semantics = CodeFlowFacts.semantic_facts(disjoint_module, disjoint_flow)
local disjoint_mem = CodeMemFacts.facts(disjoint_module, disjoint_flow)
local disjoint_sem = CodeMemFacts.semantic_facts(disjoint_module, disjoint_flow, disjoint_flow_semantics, disjoint_contracts)
local saw_no_dependence, saw_readonly_effect, saw_writeonly_effect = false, false, false
for _, dep in ipairs(disjoint_sem.dependences) do
    if pvm.classof(dep) == Mem.MemNoDependence then saw_no_dependence = true end
end
for _, effect in ipairs(disjoint_sem.effects) do
    local cls = pvm.classof(effect)
    if cls == Mem.MemObjectReadonly then saw_readonly_effect = true end
    if cls == Mem.MemObjectWriteonly then saw_writeonly_effect = true end
end
assert(saw_no_dependence, "disjoint/noalias contracts should normalize to reusable no-dependence facts")
assert(saw_readonly_effect and saw_writeonly_effect, "readonly/writeonly contracts should normalize to object effect facts without pretending they are disjointness proofs")

local relation_module, relation_contracts = lower([[
func view_contract_relations(dst: view(i32), src: view(i32), p: ptr(i32), n: i32, start: i32, m: i32): i32
    requires same_len(dst, src)
    requires window_bounds(p, n, start, m)
    return 0
end
]])
local relation_flow = CodeFlowFacts.facts(relation_module)
local relation_flow_semantics = CodeFlowFacts.semantic_facts(relation_module, relation_flow)
local relation_sem = CodeMemFacts.semantic_facts(relation_module, relation_flow, relation_flow_semantics, relation_contracts)
local saw_same_len_relation, saw_window_relation, saw_window_extent = false, false, false
local relation_objects_by_id = {}
for _, object in ipairs(relation_sem.objects) do
    relation_objects_by_id[object.id.text] = object
    if pvm.classof(object.extent) == Mem.MemExtentElements and tostring(object.extent.reason):match("WindowBounds") then
        saw_window_extent = true
    end
end
for _, relation in ipairs(relation_sem.relations or {}) do
    local cls = pvm.classof(relation)
    if cls == Mem.MemObjectsSameLen then saw_same_len_relation = true end
    if cls == Mem.MemObjectWindowBounds then
        saw_window_relation = true
        local object = relation_objects_by_id[relation.object.text]
        assert(object ~= nil and pvm.classof(object.extent) == Mem.MemExtentElements, "window_bounds relation should target a bounded object fact")
    end
end
assert(saw_same_len_relation, "same_len contracts should normalize to reusable object relation facts")
assert(saw_window_relation and saw_window_extent, "window_bounds should normalize to a bounded object plus window relation fact")

local view_module = lower([[
func view_sum(p: ptr(i32), n: i32): i32
    let v: view(i32) = view(p, n)
    return block loop(i: i32 = 0, acc: i32 = 0): i32
        if i >= n then yield acc end
        let x: i32 = v[i]
        jump loop(i = i + 1, acc = acc + x)
    end
end
]])
local view_flow = CodeFlowFacts.facts(view_module)
local view_flow_semantics = CodeFlowFacts.semantic_facts(view_module, view_flow)
local view_mem = CodeMemFacts.facts(view_module, view_flow)
for _, access in ipairs(view_mem.accesses) do
    if pvm.classof(access.base) == Mem.MemBaseDerived then
        assert(not tostring(access.base.reason):match("view data"), "view provenance must not be hidden in MemBaseDerived strings")
    end
end
local view_sem = CodeMemFacts.semantic_facts(view_module, view_flow, view_flow_semantics)
local saw_view_object = false
for _, object in ipairs(view_sem.objects) do
    if object.kind == Mem.MemObjectView then
        saw_view_object = true
        assert(pvm.classof(object.provenance) == Mem.MemProvView, "view objects need structured view provenance")
        assert(pvm.classof(object.extent) == Mem.MemExtentElements, "view objects should carry element extent")
        assert(object.elem_ty == i32, "view object element type should be reusable by later memory facts")
    end
end
assert(saw_view_object, "expected structured MemObjectView fact")
assert(#view_sem.intervals >= 1, "bounded view access should have normalized access interval")
local view_objects_by_id = {}
for _, object in ipairs(view_sem.objects) do view_objects_by_id[object.id.text] = object end
local view_access_ids = {}
for _, interval in ipairs(view_sem.intervals) do
    local object = view_objects_by_id[interval.object.text]
    if object ~= nil and object.kind == Mem.MemObjectView then view_access_ids[interval.access.text] = true end
end
local saw_inbounds, saw_nontrap, saw_deref, saw_align, saw_movable = false, false, false, false, false
for _, safety in ipairs(view_sem.safety) do
    local cls = pvm.classof(safety)
    if cls == Mem.MemAccessInBounds and view_access_ids[safety.interval.access.text] then saw_inbounds = true end
    if cls == Mem.MemAccessNonTrap and view_access_ids[safety.access.text] then saw_nontrap = true end
    if cls == Mem.MemAccessDerefBytes and view_access_ids[safety.access.text] then saw_deref = true end
    if cls == Mem.MemAccessAlignKnown and view_access_ids[safety.access.text] then saw_align = true end
    if cls == Mem.MemAccessMovable and view_access_ids[safety.access.text] then saw_movable = true end
end
assert(saw_inbounds and saw_nontrap and saw_deref and saw_align and saw_movable, "view loop range + object extent should normalize reusable safety facts")

local view_kernels = CodeKernelPlan.plan(view_module, view_flow, view_mem, nil, view_flow_semantics, view_sem)
local view_kernel = view_kernels.funcs[1].plan
assert(pvm.classof(view_kernel) == Kernel.KernelPlanned, "contiguous bounded object facts should produce a kernel plan")
assert(pvm.classof(view_kernel.subject) == Kernel.KernelSubjectFunc, "bounded returned reduction should be a whole-function kernel")
assert(pvm.classof(view_kernel.body.safety) == Kernel.KernelSafetyProven, "kernel safety should come from normalized memory facts")
local view_lowered = CodeLowerPlan.plan(view_module, view_kernels)
assert(pvm.classof(view_lowered.funcs[1]) == Lower.LowerFuncKernel, "semantic bounded object kernel should select kernel lowering")
local view_program = LowerToBack.module(view_module, view_lowered, { validate = false })
assert(#BackValidate.validate(view_program).issues == 0, "bounded object kernel lowering should validate")
local saw_back_semantics = false
for _, cmd in ipairs(view_program.cmds or {}) do
    if pvm.classof(cmd) == Back.CmdLoadInfo
        and pvm.classof(cmd.memory.trap) == Back.BackNonTrapping
        and pvm.classof(cmd.memory.motion) == Back.BackCanMove
        and pvm.classof(cmd.memory.alignment) == Back.BackAlignKnown then
        saw_back_semantics = true
    end
end
assert(saw_back_semantics, "semantic Back metadata should be emitted for bounded object kernel loads")

local strided_module = lower([[
func strided_view_sum(p: ptr(i32), n: i32): i32
    let v: view(i32) = view(p, n, 2)
    return block loop(i: i32 = 0, acc: i32 = 0): i32
        if i >= n then yield acc end
        let x: i32 = v[i]
        jump loop(i = i + 1, acc = acc + x)
    end
end
]])
local strided_flow = CodeFlowFacts.facts(strided_module)
local strided_mem = CodeMemFacts.facts(strided_module, strided_flow)
local strided_sem = CodeMemFacts.semantic_facts(strided_module, strided_flow, CodeFlowFacts.semantic_facts(strided_module, strided_flow))
local saw_stride_two, saw_strided_inbounds = false, false
local strided_objects_by_id = {}
for _, object in ipairs(strided_sem.objects) do
    strided_objects_by_id[object.id.text] = object
    if object.kind == Mem.MemObjectView and pvm.classof(object.stride) == Mem.MemStrideConstElems and object.stride.elems == 2 then
        saw_stride_two = true
    end
end
local strided_view_access = {}
for _, interval in ipairs(strided_sem.intervals) do
    local object = strided_objects_by_id[interval.object.text]
    if object ~= nil and object.kind == Mem.MemObjectView then strided_view_access[interval.access.text] = true end
end
for _, safety in ipairs(strided_sem.safety) do
    if pvm.classof(safety) == Mem.MemAccessInBounds and strided_view_access[safety.interval.access.text] then saw_strided_inbounds = true end
end
assert(saw_stride_two, "strided bounded objects should preserve structured stride facts")
assert(saw_strided_inbounds, "constant positive stride plus loop range should prove bounded strided access intervals")

local dynamic_stride_module = lower([[
func dynamic_strided_view_sum(p: ptr(i32), n: i32, s: i32): i32
    let v: view(i32) = view(p, n, s)
    return block loop(i: i32 = 0, acc: i32 = 0): i32
        if i >= n then yield acc end
        let x: i32 = v[i]
        jump loop(i = i + 1, acc = acc + x)
    end
end
]])
local dynamic_stride_flow = CodeFlowFacts.facts(dynamic_stride_module)
local dynamic_stride_sem = CodeMemFacts.semantic_facts(dynamic_stride_module, dynamic_stride_flow, CodeFlowFacts.semantic_facts(dynamic_stride_module, dynamic_stride_flow))
local dynamic_objects_by_id, dynamic_view_access, saw_dynamic_inbounds = {}, {}, false
for _, object in ipairs(dynamic_stride_sem.objects) do dynamic_objects_by_id[object.id.text] = object end
for _, interval in ipairs(dynamic_stride_sem.intervals) do
    local object = dynamic_objects_by_id[interval.object.text]
    if object ~= nil and object.kind == Mem.MemObjectView then dynamic_view_access[interval.access.text] = true end
end
for _, safety in ipairs(dynamic_stride_sem.safety) do
    if pvm.classof(safety) == Mem.MemAccessInBounds and dynamic_view_access[safety.interval.access.text] then saw_dynamic_inbounds = true end
end
assert(not saw_dynamic_inbounds, "dynamic/unknown stride should remain conservative without a stride interval proof")

local origin = Code.CodeOriginGenerated("manual atomic mem facts")
local ptr_i32 = Code.CodeTyDataPtr(i32)
local data_id = Code.CodeDataId("data:table")
local global_id = Code.CodeGlobalId("global:counter")
local object_module = Code.CodeModule(Code.CodeModuleId("module:objects"), {}, {}, {
    Code.CodeData(data_id, "table", Code.CodeLinkageLocal, 16, 4, {}, origin),
}, {
    Code.CodeGlobal(global_id, "counter", i32, Code.CodeLinkageLocal, 4, 4, {}, origin),
}, {}, {}, origin)
local object_sem = CodeMemFacts.semantic_facts(object_module, nil)
local saw_data_object, saw_global_object = false, false
for _, object in ipairs(object_sem.objects) do
    if object.kind == Mem.MemObjectData then
        saw_data_object = true
        assert(pvm.classof(object.provenance) == Mem.MemProvData)
        assert(pvm.classof(object.extent) == Mem.MemExtentBytes and object.extent.bytes == 16)
    elseif object.kind == Mem.MemObjectGlobal then
        saw_global_object = true
        assert(pvm.classof(object.provenance) == Mem.MemProvGlobal)
        assert(pvm.classof(object.extent) == Mem.MemExtentBytes and object.extent.bytes == 4)
    end
end
assert(saw_data_object and saw_global_object, "data/global objects are non-view witnesses for generic memory objects")

local fn = Code.CodeFuncId("fn:atomic")
local sig = Code.CodeSigId("sig:atomic")
local entry = Code.CodeBlockId("block:entry")
local p = Code.CodeValueId("v:p")
local old = Code.CodeValueId("v:old")
local access = Code.CodeMemoryAccess(Code.CodeMemoryReadWrite, i32, 4, Code.CodeMustNotTrap, true, Core.AtomicSeqCst)
local atomic_module = Code.CodeModule(Code.CodeModuleId("module:atomic"), {
    Code.CodeSig(sig, { ptr_i32 }, { i32 }),
}, {}, {}, {}, {}, {
    Code.CodeFunc(fn, "atomic", Code.CodeLinkageLocal, sig, { Code.CodeParam(p, "p", ptr_i32, origin) }, {}, entry, {
        Code.CodeBlock(entry, "entry", {}, {
            Code.CodeInst(Code.CodeInstId("inst:rmw"), Code.CodeInstAtomicRmw(old, Core.AtomicRmwAdd, Code.CodePlaceDeref(p, i32, 4), Code.CodeValueId("v:one"), access, Core.AtomicSeqCst), origin),
        }, Code.CodeTerm(Code.CodeTermId("term:return"), Code.CodeTermReturn({ old }), origin), origin),
    }, origin),
}, origin)
-- The manual module intentionally omits v:one because this test exercises memory fact extraction, not full Code validation.
local atomic_mem = CodeMemFacts.facts(atomic_module, nil)
assert(#atomic_mem.accesses == 1)
assert(atomic_mem.accesses[1].kind == Mem.MemAtomicRmw)
assert(atomic_mem.accesses[1].access.volatile == true)
assert(pvm.classof(atomic_mem.accesses[1].trap) == Mem.MemNonTrapping)

io.write("moonlift code_mem_facts ok\n")
