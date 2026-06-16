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

local Kernel = T.MoonKernel
local Back = T.MoonBack

local function semantic_sets_for(code, flow, contracts)
    local flow_semantics = CodeFlowFacts.semantic_facts(code, flow)
    local mem_semantics = CodeMemFacts.semantic_facts(code, flow, flow_semantics, contracts)
    return flow_semantics, mem_semantics
end

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

local code, contracts = lower([[
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
local flow = CodeFlowFacts.facts(code)
local flow_semantics, mem_semantics = semantic_sets_for(code, flow, contracts)
local mem = CodeMemFacts.facts(code, flow)
local plan = CodeKernelPlan.plan(code, flow, mem, contracts, flow_semantics, mem_semantics)
assert(plan.module == code.id)
assert(plan.flow == flow)
assert(plan.memory == mem)
assert(plan.flow_semantics == flow_semantics)
assert(plan.memory_semantics == mem_semantics)
assert(#plan.funcs == 1)
local kernel_plan = plan.funcs[1].plan
assert(kernel_plan.subject.func == code.funcs[1].id)
assert(pvm.classof(kernel_plan.subject) == Kernel.KernelSubjectFunc, "store+fold loop is a complete whole-function kernel")
assert(pvm.classof(kernel_plan) == Kernel.KernelPlanned, "contracted counted loop should produce a kernel plan")
assert(pvm.classof(kernel_plan.body) == Kernel.KernelBodyCounted, "planned kernel should carry unified counted body")
assert(#kernel_plan.body.streams == 2, "expected load/store streams")
assert(#kernel_plan.body.effects == 2, "expected store plus fold effects")
assert(pvm.classof(kernel_plan.body.effects[1]) == Kernel.KernelEffectStore, "expected store effect")
assert(pvm.classof(kernel_plan.body.effects[2]) == Kernel.KernelEffectFold, "expected fold effect")
assert(pvm.classof(kernel_plan.body.result) == Kernel.KernelResultFold, "expected fold return")
assert(pvm.classof(kernel_plan.body.safety) == Kernel.KernelSafetyProven, "contract facts should be normalized before kernel planning, not used as local assumptions")
assert(pvm.classof(kernel_plan.schedule) == Kernel.KernelScheduleVector, "contiguous contracted loop should be vector-eligible")
assert(kernel_plan.schedule.shape.lanes == 4, "default target model should drive i32 vector lane count")

local narrow_target = Back.BackTargetModel(Back.BackTargetNamed("i32x2-only"), {
    Back.BackTargetSupportsShape(Back.BackShapeVec(Back.BackVec(Back.BackI32, 2))),
    Back.BackTargetSupportsVectorOp(Back.BackVec(Back.BackI32, 2), "int_binary"),
    Back.BackTargetPrefersUnroll(Back.BackShapeVec(Back.BackVec(Back.BackI32, 2)), 2, 100),
})
local narrow_plan = CodeKernelPlan.plan(code, flow, mem, contracts, flow_semantics, mem_semantics, { target_model = narrow_target })
assert(pvm.classof(narrow_plan.funcs[1].plan.schedule) == Kernel.KernelScheduleVector)
assert(narrow_plan.funcs[1].plan.schedule.shape.lanes == 2, "kernel vector lane count should come from BackTargetModel")
assert(narrow_plan.funcs[1].plan.schedule.unroll == 2, "kernel vector unroll should come from BackTargetPrefersUnroll")

local scalar_only_target = Back.BackTargetModel(Back.BackTargetNamed("scalar-only"), {
    Back.BackTargetSupportsShape(Back.BackShapeScalar(Back.BackI32)),
})
local scalar_target_plan = CodeKernelPlan.plan(code, flow, mem, contracts, flow_semantics, mem_semantics, { target_model = scalar_only_target })
assert(pvm.classof(scalar_target_plan.funcs[1].plan.schedule) == Kernel.KernelScheduleScalarIndex, "missing vector target support should select scalar scheduling without changing semantic plan legality")

local reduce_code, reduce_contracts = lower([[
func sum_loop(n: i32): i32
    return block loop(i: i32 = 0, acc: i32 = 0): i32
        if i >= n then yield acc end
        jump loop(i = i + 1, acc = acc + i)
    end
end
]])
local reduce_flow = CodeFlowFacts.facts(reduce_code)
local reduce_mem = CodeMemFacts.facts(reduce_code, reduce_flow)
local reduce_plan = CodeKernelPlan.plan(reduce_code, reduce_flow, reduce_mem, reduce_contracts)
local reduce_kernel = reduce_plan.funcs[1].plan
assert(pvm.classof(reduce_kernel) == Kernel.KernelPlanned, "complete scalar reduction should plan")
assert(pvm.classof(reduce_kernel.subject) == Kernel.KernelSubjectFunc, "complete returned reduction is a whole-function kernel")
assert(pvm.classof(reduce_kernel.body) == Kernel.KernelBodyCounted)
assert(#reduce_kernel.body.effects == 1)
assert(pvm.classof(reduce_kernel.body.effects[1]) == Kernel.KernelEffectFold)
assert(reduce_kernel.body.effects[1].fold.identity == "0")
assert(pvm.classof(reduce_kernel.body.result) == Kernel.KernelResultClosedForm, "memory-free arithmetic-series reduction should expose first-class closed-form semantics")
assert(pvm.classof(reduce_kernel.body.result.closed_form.kind) == Kernel.KernelClosedFormArithmeticSeries, "closed-form result should identify the algebraic law")

local view_code, view_contracts = lower([[
func view_sum(p: ptr(i32), n: i32): i32
    let v: view(i32) = view(p, n)
    return block loop(i: i32 = 0, acc: i32 = 0): i32
        if i >= n then yield acc end
        let x: i32 = v[i]
        jump loop(i = i + 1, acc = acc + x)
    end
end
]])
local view_flow = CodeFlowFacts.facts(view_code)
local view_mem = CodeMemFacts.facts(view_code, view_flow)
local view_flow_semantics, view_sem = semantic_sets_for(view_code, view_flow, view_contracts)
local view_plan = CodeKernelPlan.plan(view_code, view_flow, view_mem, view_contracts, view_flow_semantics, view_sem)
local view_kernel = view_plan.funcs[1].plan
assert(pvm.classof(view_kernel) == Kernel.KernelPlanned, "bounded object + normalized safety facts should allow planning without contract shortcuts")
assert(pvm.classof(view_kernel.body.safety) == Kernel.KernelSafetyProven, "semantic memory proofs should be consumed as proven kernel safety")

local unsafe_code, unsafe_contracts = lower([[
func copy_sum_unsafe(dst: ptr(i32), src: ptr(i32), n: i32): i32
    return block loop(i: i32 = 0, acc: i32 = 0): i32
        if i >= n then yield acc end
        let x: i32 = src[i]
        dst[i] = x
        jump loop(i = i + 1, acc = acc + x)
    end
end
]])
local unsafe_flow = CodeFlowFacts.facts(unsafe_code)
local unsafe_mem = CodeMemFacts.facts(unsafe_code, unsafe_flow)
local unsafe_flow_semantics, unsafe_sem = semantic_sets_for(unsafe_code, unsafe_flow, unsafe_contracts)
local unsafe_plan = CodeKernelPlan.plan(unsafe_code, unsafe_flow, unsafe_mem, unsafe_contracts, unsafe_flow_semantics, unsafe_sem)
local no_plan = unsafe_plan.funcs[1].plan
assert(pvm.classof(no_plan) == Kernel.KernelNoPlan, "uncontracted pointer loop should reject rather than silently plan")
local saw_memory_reject, saw_alias_reject = false, false
for _, reject in ipairs(no_plan.rejects) do
    if pvm.classof(reject) == Kernel.KernelRejectUnsupportedMemory or pvm.classof(reject) == Kernel.KernelRejectTrap then saw_memory_reject = true end
    if pvm.classof(reject) == Kernel.KernelRejectAlias or pvm.classof(reject) == Kernel.KernelRejectDependence then saw_alias_reject = true end
end
assert(saw_memory_reject, "expected explicit memory/trap rejection")
assert(saw_alias_reject, "expected explicit alias/dependence rejection")

io.write("moonlift code_kernel_plan ok\n")
