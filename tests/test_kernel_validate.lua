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
local KernelValidate = require("moonlift.kernel_validate").Define(T)

local Code = T.MoonCode
local Kernel = T.MoonKernel

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
    local flow = CodeFlowFacts.facts(code)
    local flow_semantics = CodeFlowFacts.semantic_facts(code, flow)
    local mem = CodeMemFacts.facts(code, flow)
    local mem_semantics = CodeMemFacts.semantic_facts(code, flow, flow_semantics, contracts)
    local plan = CodeKernelPlan.plan(code, flow, mem, contracts, flow_semantics, mem_semantics)
    return code, flow, mem, plan
end

local code, flow, mem, plan = lower([[
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
local report = KernelValidate.validate(code, flow, mem, plan)
assert_no_issues("kernel_validate", report.issues)

local bad_mem = CodeMemFacts.facts(code, flow)
bad_mem.accesses[1] = T.MoonMem.MemAccessFact(
    bad_mem.accesses[1].id,
    bad_mem.accesses[1].func,
    bad_mem.accesses[1].block,
    bad_mem.accesses[1].inst,
    bad_mem.accesses[1].kind,
    bad_mem.accesses[1].place,
    Code.CodeMemoryAccess(Code.CodeMemoryRead, bad_mem.accesses[1].access.ty, 1, Code.CodeMayTrap, false, nil),
    bad_mem.accesses[1].base,
    bad_mem.accesses[1].index,
    bad_mem.accesses[1].pattern,
    bad_mem.accesses[1].alignment,
    bad_mem.accesses[1].bounds,
    bad_mem.accesses[1].trap
)
-- Validate the bad memory against the original good plan to exercise direct contradiction checks.
report = KernelValidate.validate(code, flow, bad_mem, plan)
local saw_contradiction = false
for _, issue in ipairs(report.issues) do if issue.kind == "access-contradiction" or issue.kind == "memory-mismatch" then saw_contradiction = true end end
assert(saw_contradiction, "expected validator to catch CodeMemoryAccess contradiction/memory mismatch")

local no_reject_plan = Kernel.KernelModulePlan(code.id, flow, mem, {
    Kernel.KernelFuncPlan(code.funcs[1].id, Kernel.KernelNoPlan(Kernel.KernelSubjectLoop(code.funcs[1].id, flow.loops[1].id), {})),
})
report = KernelValidate.validate(code, flow, mem, no_reject_plan)
local saw_missing_rejection = false
for _, issue in ipairs(report.issues) do if issue.kind == "missing-rejection" then saw_missing_rejection = true end end
assert(saw_missing_rejection, "expected KernelNoPlan without rejects to fail validation")

io.write("moonlift kernel_validate ok\n")
