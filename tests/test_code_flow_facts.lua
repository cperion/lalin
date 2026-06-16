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

local Code = T.MoonCode
local Flow = T.MoonFlow

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
    local code = TreeToCode.module(resolved)
    assert_no_issues("code", CodeValidate.validate(code).issues)
    return code
end

local module = lower([[
func counted_loop(n: i32): i32
    return block loop(i: i32 = 0, acc: i32 = 0): i32
        if i >= n then yield acc else jump loop(i = i + 1, acc = acc + i) end
    end
end
]])

local facts = CodeFlowFacts.facts(module)
assert(facts.module == module.id)
assert(#facts.edges >= 3, "expected control-flow edges")
assert(#facts.loops == 1, "expected one natural loop")
local loop = facts.loops[1]
assert(pvm.classof(loop.source) == Flow.FlowLoopFromCode)
assert(pvm.classof(loop.domain) == Flow.FlowDomainCounted, "expected counted loop domain")
assert(#loop.inductions >= 1, "expected primary induction")
assert(#loop.exits >= 1, "expected loop exit edge")
local saw_backedge, saw_exit = false, false
for _, edge in ipairs(facts.edges) do
    for _, role in ipairs(edge.roles) do
        if pvm.classof(role) == Flow.FlowRoleBackedge then saw_backedge = true end
        if pvm.classof(role) == Flow.FlowRoleLoopExit then saw_exit = true end
    end
end
assert(saw_backedge, "expected a backedge role")
assert(saw_exit, "expected a loop-exit role")

local range_by_value = {}
for _, range in ipairs(facts.ranges) do
    if range.value ~= nil then range_by_value[range.value.text] = pvm.classof(range) end
end
assert(range_by_value[loop.inductions[1].value.text] == Flow.FlowRangeDerived, "expected derived induction range")

local semantic = CodeFlowFacts.semantic_facts(module, facts)
assert(semantic.module == module.id)
local normalized, induction_range, saw_nowrap = nil, nil, false
for _, fact in ipairs(semantic.facts) do
    local cls = pvm.classof(fact)
    if cls == Flow.FlowLoopNormalizedCounted then normalized = fact end
    if cls == Flow.FlowLoopInductionRange then induction_range = fact.range end
    if cls == Flow.FlowLoopInductionNoWrap then saw_nowrap = true end
end
assert(normalized ~= nil, "expected normalized counted semantic fact")
assert(normalized.loop == loop.id, "expected normalized fact for loop")
assert(normalized.direction == Flow.FlowLoopIncreasing, "expected increasing loop direction")
assert(pvm.classof(normalized.trip_count) == Flow.FlowTripCountNonNegative, "expected conservative non-negative trip count")
assert(induction_range ~= nil, "expected normalized induction range")
assert(induction_range.loop == loop.id, "expected range fact for loop")
assert(induction_range.value == loop.inductions[1].value, "expected range for primary induction")
assert(pvm.classof(induction_range.min) == Flow.FlowBoundConst and induction_range.min.raw == "0", "expected const zero lower bound")
assert(pvm.classof(induction_range.max) == Flow.FlowBoundValue, "expected value upper bound")
assert(induction_range.max_exclusive == true, "expected exclusive upper bound")
assert(not saw_nowrap, "default wrapping integer semantics must not invent no-wrap")

local inclusive_module = lower([[
func inclusive_loop(n: i32): i32
    return block loop(i: i32 = 0, acc: i32 = 0): i32
        if i > n then yield acc else jump loop(i = i + 1, acc = acc + i) end
    end
end
]])
local inclusive_facts = CodeFlowFacts.facts(inclusive_module)
local inclusive_semantic = CodeFlowFacts.semantic_facts(inclusive_module, inclusive_facts)
local inclusive_normalized, inclusive_range = nil, nil
for _, fact in ipairs(inclusive_semantic.facts) do
    local cls = pvm.classof(fact)
    if cls == Flow.FlowLoopNormalizedCounted then inclusive_normalized = fact end
    if cls == Flow.FlowLoopInductionRange then inclusive_range = fact.range end
end
assert(inclusive_normalized ~= nil, "expected normalized fact even for conservative counted loops")
assert(inclusive_normalized.direction == Flow.FlowLoopIncreasing, "expected direction for inclusive increasing loop")
assert(pvm.classof(inclusive_normalized.trip_count) == Flow.FlowTripCountUnknown, "inclusive stop keeps trip count conservative")
assert(inclusive_range == nil, "inclusive stop must not derive [start, stop) range")

local manual_origin = Code.CodeOriginGenerated("manual flow switch")
local i32 = Code.CodeTyInt(32, Code.CodeSigned)
local bool = Code.CodeTyBool8
local fn = Code.CodeFuncId("fn:switchy")
local sig = Code.CodeSigId("sig:switchy")
local entry = Code.CodeBlockId("block:entry")
local case1 = Code.CodeBlockId("block:case1")
local def = Code.CodeBlockId("block:def")
local value = Code.CodeValueId("v:x")
local manual = Code.CodeModule(Code.CodeModuleId("module:manual"), {
    Code.CodeSig(sig, { i32 }, { i32 }),
}, {}, {}, {}, {}, {
    Code.CodeFunc(fn, "switchy", Code.CodeLinkageLocal, sig, { Code.CodeParam(value, "x", i32, manual_origin) }, {}, entry, {
        Code.CodeBlock(entry, "entry", {}, {}, Code.CodeTerm(Code.CodeTermId("term:switch"), Code.CodeTermSwitch(value, {
            Code.CodeSwitchCase(T.MoonCore.LitInt("1"), case1, {}),
        }, def, {}), manual_origin), manual_origin),
        Code.CodeBlock(case1, "case1", {}, { Code.CodeInst(Code.CodeInstId("inst:c1"), Code.CodeInstConst(Code.CodeValueId("v:c1"), Code.CodeConstLiteral(i32, T.MoonCore.LitInt("1"))), manual_origin) }, Code.CodeTerm(Code.CodeTermId("term:r1"), Code.CodeTermReturn({ Code.CodeValueId("v:c1") }), manual_origin), manual_origin),
        Code.CodeBlock(def, "def", {}, { Code.CodeInst(Code.CodeInstId("inst:c0"), Code.CodeInstConst(Code.CodeValueId("v:c0"), Code.CodeConstLiteral(i32, T.MoonCore.LitInt("0"))), manual_origin) }, Code.CodeTerm(Code.CodeTermId("term:r0"), Code.CodeTermReturn({ Code.CodeValueId("v:c0") }), manual_origin), manual_origin),
    }, manual_origin),
}, manual_origin)
assert_no_issues("manual code", CodeValidate.validate(manual).issues)
local switch_facts = CodeFlowFacts.facts(manual)
local saw_case, saw_default, saw_const_range = false, false, false
for _, edge in ipairs(switch_facts.edges) do
    if pvm.classof(edge.kind) == Flow.FlowEdgeSwitchCase then saw_case = true end
    if edge.kind == Flow.FlowEdgeSwitchDefault then saw_default = true end
end
for _, range in ipairs(switch_facts.ranges) do
    if pvm.classof(range) == Flow.FlowRangeExact then saw_const_range = true end
end
assert(saw_case and saw_default, "expected switch case/default edges")
assert(saw_const_range, "expected literal const range fact")

io.write("moonlift code_flow_facts ok\n")
