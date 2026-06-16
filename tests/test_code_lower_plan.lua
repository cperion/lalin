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
local LowerToC = require("moonlift.lower_to_c").Define(T)
local BackValidate = require("moonlift.back_validate").Define(T)
local CValidate = require("moonlift.c_validate").Define(T)

local Kernel = T.MoonKernel
local Lower = T.MoonLower
local Mem = T.MoonMem
local Flow = T.MoonFlow
local Back = T.MoonBack

local function proven_semantics_for_accesses(code, mem)
    local objects, intervals, safety, proofs = {}, {}, {}, {}
    for i, access in ipairs(mem.accesses or {}) do
        local object = Mem.MemObjectFact(
            Mem.MemObjectId("obj:test:access:" .. tostring(i)),
            access.func,
            Mem.MemObjectUnknown,
            Mem.MemProvUnknown("test normalized object witness"),
            access.access.ty,
            Mem.MemExtentUnknown("test fixture supplies interval proof directly"),
            Mem.MemStrideUnit
        )
        objects[#objects + 1] = object
        local interval = Mem.MemAccessInterval(access.id, object.id, nil, access.index, Flow.FlowBoundConst("1"), access.access.align or 1, 0, "test normalized interval")
        intervals[#intervals + 1] = interval
        local proof = Mem.MemProofInterval(interval, "test normalized memory safety proof")
        proofs[#proofs + 1] = proof
        safety[#safety + 1] = Mem.MemAccessInBounds(interval, proof)
        safety[#safety + 1] = Mem.MemAccessNonTrap(access.id, proof)
        safety[#safety + 1] = Mem.MemAccessDerefBytes(access.id, access.access.align or 1, proof)
        safety[#safety + 1] = Mem.MemAccessAlignKnown(access.id, access.access.align or 1, proof)
        if access.kind == Mem.MemLoad then safety[#safety + 1] = Mem.MemAccessMovable(access.id, proof) end
    end
    return Mem.MemSemanticFactSet(code.id, objects, intervals, safety, {}, {}, {}, proofs)
end

local function assert_no_issues(label, issues)
    assert(#issues == 0, label .. " expected no issues, got " .. tostring(#issues))
end

local function lower_code(src)
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

local function lower(src)
    local code, contracts = lower_code(src)
    local flow = CodeFlowFacts.facts(code)
    local flow_semantics = CodeFlowFacts.semantic_facts(code, flow)
    local mem = CodeMemFacts.facts(code, flow)
    local mem_semantics = CodeMemFacts.semantic_facts(code, flow, flow_semantics, contracts)
    local kernels = CodeKernelPlan.plan(code, flow, mem, contracts, flow_semantics, mem_semantics)
    return code, kernels
end

local code, kernels = lower([[
func copy_sum(noalias dst: ptr(i32), readonly src: ptr(i32), n: i32): i32
    requires bounds(dst, n)
    requires bounds(src, n)
    requires disjoint(dst, src)
    return block loop(i: i32 = 0, acc: i32 = 0): i32
        if i >= n then yield acc end
        let x: i32 = src[i]
        dst[i] = x
        jump loop(i = i + 1, acc = acc + x)
    end
end
]])
local lowered = CodeLowerPlan.plan(code, kernels, { target = Lower.LowerTargetC })
assert(lowered.module == code.id)
assert(lowered.kernels == kernels)
assert(lowered.target == Lower.LowerTargetC)
assert(#lowered.funcs == #code.funcs)
assert(pvm.classof(kernels.funcs[1].plan.subject) == Kernel.KernelSubjectFunc)
assert(pvm.classof(lowered.funcs[1]) == Lower.LowerFuncKernel, "complete store+fold kernel should select kernel lowering")
local store_fold_program = LowerToBack.module(code, lowered, { validate = false })
assert(#BackValidate.validate(store_fold_program).issues == 0, "lower_to_back store+fold kernel projection should validate")
local saw_store, saw_vec_store_fold = false, false
for _, cmd in ipairs(store_fold_program.cmds or {}) do
    local cls = pvm.classof(cmd)
    if cls == T.MoonBack.CmdStoreInfo then saw_store = true end
    if cls == T.MoonBack.CmdStoreInfo or cls == T.MoonBack.CmdVecBinary or cls == T.MoonBack.CmdVecExtractLane or cls == T.MoonBack.CmdVecSplat then saw_vec_store_fold = true end
end
assert(saw_store, "store+fold kernel projection should emit stores")
assert(saw_vec_store_fold, "store+fold vector schedule should project to Back vector/store commands")
local store_fold_c_unit = LowerToC.module(code, lowered, { validate = false })
assert(#CValidate.validate(store_fold_c_unit).issues == 0, "lower_to_c should fall back to code projection for store+fold kernels until generic C kernel lowering exists")

local loop_plan = kernels.funcs[1].plan
local func_plan = Kernel.KernelPlanned(
    Kernel.KernelId("kernel:function-fixture"),
    Kernel.KernelSubjectFunc(code.funcs[1].id),
    loop_plan.body,
    loop_plan.schedule,
    {}
)
local func_kernels = Kernel.KernelModulePlan(code.id, kernels.flow, kernels.memory, { Kernel.KernelFuncPlan(code.funcs[1].id, func_plan) }, kernels.flow_semantics, kernels.memory_semantics)
local func_lowered = CodeLowerPlan.plan(code, func_kernels)
assert(pvm.classof(func_lowered.funcs[1]) == Lower.LowerFuncKernel, "function-subject kernel should lower as kernel")
assert(func_lowered.funcs[1].plan == func_plan)

local reduce_code, reduce_kernels = lower([[
func sum_loop(n: i32): i32
    return block loop(i: i32 = 0, acc: i32 = 0): i32
        if i >= n then yield acc end
        jump loop(i = i + 1, acc = acc + i)
    end
end
]])
local reduce_lowered = CodeLowerPlan.plan(reduce_code, reduce_kernels)
assert(pvm.classof(reduce_kernels.funcs[1].plan.subject) == Kernel.KernelSubjectFunc)
assert(pvm.classof(reduce_lowered.funcs[1]) == Lower.LowerFuncKernel, "complete reduction should lower as whole-function kernel")
local reduce_program = LowerToBack.module(reduce_code, reduce_lowered, { validate = false })
assert(#BackValidate.validate(reduce_program).issues == 0, "lower_to_back kernel projection should validate")
local saw_closed_select, saw_closed_loop = false, false
for _, cmd in ipairs(reduce_program.cmds or {}) do
    local cls = pvm.classof(cmd)
    if cls == Back.CmdSelect then saw_closed_select = true end
    if cls == Back.CmdBrIf or cls == Back.CmdJump then saw_closed_loop = true end
end
assert(saw_closed_select, "arithmetic-series reduction should lower to closed-form select arithmetic")
assert(not saw_closed_loop, "closed-form arithmetic-series reduction should not emit a loop")
local reduce_c_unit = LowerToC.module(reduce_code, reduce_lowered, { validate = false })
assert(#CValidate.validate(reduce_c_unit).issues == 0, "lower_to_c kernel projection should validate")

local ptr_reduce_code, ptr_reduce_kernels = lower([[
func ptr_sum(readonly p: ptr(i32), n: i32): i32
    requires bounds(p, n)
    return block loop(i: i32 = 0, acc: i32 = 0): i32
        if i >= n then yield acc end
        jump loop(i = i + 1, acc = acc + p[i])
    end
end
]])
local ptr_reduce_lowered = CodeLowerPlan.plan(ptr_reduce_code, ptr_reduce_kernels)
assert(pvm.classof(ptr_reduce_kernels.funcs[1].plan.subject) == Kernel.KernelSubjectFunc)
assert(pvm.classof(ptr_reduce_kernels.funcs[1].plan.schedule) == Kernel.KernelScheduleVector)
local ptr_reduce_program = LowerToBack.module(ptr_reduce_code, ptr_reduce_lowered, { validate = false })
assert(#BackValidate.validate(ptr_reduce_program).issues == 0, "lower_to_back vector reduction should validate")
local saw_vec, saw_contract_kernel_nontrap = false, false
for _, cmd in ipairs(ptr_reduce_program.cmds or {}) do
    local cls = pvm.classof(cmd)
    if cls == T.MoonBack.CmdVecBinary or cls == T.MoonBack.CmdVecExtractLane or cls == T.MoonBack.CmdVecSplat then saw_vec = true end
    if cls == T.MoonBack.CmdLoadInfo and pvm.classof(cmd.memory.trap) == Back.BackNonTrapping then saw_contract_kernel_nontrap = true end
end
assert(saw_vec, "KernelScheduleVector should project to Back vector commands")
assert(saw_contract_kernel_nontrap, "contract-normalized kernel Back loads should receive semantic nontrap facts through the ASDL kernel module")

local sem_code, sem_contracts = lower_code([[
func semantic_ptr_sum(readonly p: ptr(i32), n: i32): i32
    return block loop(i: i32 = 0, acc: i32 = 0): i32
        if i >= n then yield acc end
        jump loop(i = i + 1, acc = acc + p[i])
    end
end
]])
local sem_flow = CodeFlowFacts.facts(sem_code)
local sem_flow_semantics = CodeFlowFacts.semantic_facts(sem_code, sem_flow)
local sem_mem = CodeMemFacts.facts(sem_code, sem_flow)
local sem_mem_facts = proven_semantics_for_accesses(sem_code, sem_mem)
local sem_kernels = CodeKernelPlan.plan(sem_code, sem_flow, sem_mem, sem_contracts, sem_flow_semantics, sem_mem_facts)
assert(sem_kernels.memory_semantics == sem_mem_facts, "kernel module should carry semantic memory facts")
local sem_lowered = CodeLowerPlan.plan(sem_code, sem_kernels)
local sem_program = LowerToBack.module(sem_code, sem_lowered, { validate = false })
local saw_semantic_load_flags = false
for _, cmd in ipairs(sem_program.cmds or {}) do
    if pvm.classof(cmd) == Back.CmdLoadInfo then
        if pvm.classof(cmd.memory.trap) == Back.BackNonTrapping
            and pvm.classof(cmd.memory.motion) == Back.BackCanMove
            and pvm.classof(cmd.memory.alignment) == Back.BackAlignKnown then
            saw_semantic_load_flags = true
        end
    end
end
assert(saw_semantic_load_flags, "kernel Back loads should consume normalized nontrap/movable/alignment facts")

local select_code, select_kernels = lower([[
func clamp_store(noalias dst: ptr(i32), readonly src: ptr(i32), n: i32): i32
    requires bounds(dst, n)
    requires bounds(src, n)
    requires disjoint(dst, src)
    block loop(i: i32 = 0)
        if i >= n then return 0 end
        let x: i32 = src[i]
        dst[i] = select(x < 0, 0, x)
        jump loop(i = i + 1)
    end
end
]])
local select_lowered = CodeLowerPlan.plan(select_code, select_kernels)
assert(pvm.classof(select_lowered.funcs[1]) == Lower.LowerFuncKernel, "select store kernel should lower as whole-function kernel")
local select_program = LowerToBack.module(select_code, select_lowered, { validate = false })
assert(#BackValidate.validate(select_program).issues == 0, "lower_to_back compare/select kernel projection should validate")
local saw_vec_cmp, saw_vec_select = false, false
for _, cmd in ipairs(select_program.cmds or {}) do
    local cls = pvm.classof(cmd)
    if cls == T.MoonBack.CmdVecCompare then saw_vec_cmp = true end
    if cls == T.MoonBack.CmdVecSelect then saw_vec_select = true end
end
assert(saw_vec_cmp, "KernelExprCompare should project to Back vector compare")
assert(saw_vec_select, "KernelExprSelect should project to Back vector select")

local unsafe_code, unsafe_kernels = lower([[
func copy_sum_unsafe(dst: ptr(i32), src: ptr(i32), n: i32): i32
    return block loop(i: i32 = 0, acc: i32 = 0): i32
        if i >= n then yield acc end
        let x: i32 = src[i]
        dst[i] = x
        jump loop(i = i + 1, acc = acc + x)
    end
end
]])
local unsafe_lowered = CodeLowerPlan.plan(unsafe_code, unsafe_kernels)
assert(pvm.classof(unsafe_kernels.funcs[1].plan) == Kernel.KernelNoPlan)
assert(pvm.classof(unsafe_lowered.funcs[1]) == Lower.LowerFuncCode, "rejected kernel should fall back to Code lower")
assert(unsafe_lowered.funcs[1].func == unsafe_code.funcs[1].id)

io.write("moonlift code_lower_plan ok\n")
