-- Test: FlowTripCount trip_expr computation in semantic_facts
-- Verifies that compute_trip_expr produces correct ValueExpr
-- and that FlowTripCount variants carry trip_expr when available.

package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local asdl = require("lalin.asdl")
local Schema = require("lalin.schema")
local T = asdl.context()
Schema(T)

local Flow = T.LalinFlow
local Value = T.LalinValue
local Graph = T.LalinGraph
local Code = T.LalinCode
local Core = T.LalinCore

local CodeFlowFacts = require("lalin.code_flow_facts")(T)

local origin = Code.CodeOriginGenerated("test_code_flow_trip_count")

-- Helper: build a minimal module with a counted loop and value defs
local function make_loop_module(func_id, start_val, stop_val, step_val, stop_exclusive)
    local start_id = Code.CodeValueId("trip:start")
    local stop_id = Code.CodeValueId("trip:stop")
    local step_id = Code.CodeValueId("trip:step")

    local consts = {
        [start_id.text] = start_val,
        [stop_id.text] = stop_val,
        [step_id.text] = step_val,
    }

    local fid = Code.CodeFuncId(func_id or "func:test")
    local loop_id = Graph.GraphLoopId("loop:test")
    local code_block_id = Code.CodeBlockId("block:header")
    local graph_block_id = Graph.GraphBlockId(fid, code_block_id)

    -- Flow facts with counted domain
    local counted = Flow.FlowCountedDomain(start_id, stop_id, step_id, stop_exclusive)
    local domain = Flow.FlowDomainLoop(loop_id)

    local loop_facts = Flow.FlowLoopFacts(loop_id, domain, counted, { graph_block_id }, {}, {}, {})

    local flow_facts = Flow.FlowFactSet(
        Code.CodeModuleId("mod:test"),
        { domain },
        {},
        { loop_facts },
        {},
        {},
        {},
        {},
        {},
        {}
    )

    -- CodeGraph with one function and one loop
    local graph_loop = Graph.GraphLoop(loop_id, fid, graph_block_id, { graph_block_id }, {}, {})
    local func_graph = Graph.CodeFuncGraph(fid, {}, {}, {}, { graph_loop })
    local code_graph = Graph.CodeGraph(Code.CodeModuleId("mod:test"), { func_graph })

    -- Minimal CodeFunc with value defs so semantic_facts can look up consts
    local def_insts = {}
    local i32_ty = Code.CodeTyInt(32, Code.CodeSigned)
    local function add_const(value_id, literal_val)
        local lit = Core.LitInt(tostring(literal_val))
        def_insts[#def_insts + 1] = Code.CodeInst(
            Code.CodeInstId("inst:" .. value_id.text),
            Code.CodeInstConst(value_id, Code.CodeConstLiteral(i32_ty, lit)),
            origin
        )
    end
    add_const(start_id, start_val)
    add_const(stop_id, stop_val)
    add_const(step_id, step_val)

    local func = Code.CodeFunc(
        fid, "test_func", Code.CodeLinkageLocal,
        Code.CodeSigId("sig:test"),
        {}, {},
        code_block_id,
        { Code.CodeBlock(code_block_id, "header", {}, def_insts, Code.CodeTerm(Code.CodeTermId("term:ret"), Code.CodeTermReturn({}), origin), origin) },
        origin
    )

    local module = Code.CodeModule(Code.CodeModuleId("mod:test"), {}, {}, {}, {}, {}, { func }, origin)

    return module, code_graph, flow_facts, consts
end

-- Test 1: Exclusive loop, step=1
do
    local module, graph, facts, consts = make_loop_module("func:excl_step1", 0, 10, 1, true)
    local sem = CodeFlowFacts.semantic_facts(module, graph, facts)
    local normalized = nil
    for _, f in ipairs(sem.facts or {}) do
        if asdl.classof(f) == Flow.FlowLoopNormalizedCounted then
            normalized = f
            break
        end
    end
    assert(normalized ~= nil, "should produce FlowLoopNormalizedCounted")
    local tc = normalized.trip_count
    assert(tc.reason ~= nil, "should be FlowTripCountUnknown since find_matching_value returns nil")
    -- When trip_expr is available but not materialized, we get Unknown with trip_expr
    assert(tc.trip_expr ~= nil, "trip_expr should not be nil for counted loop")
    -- trip_expr should be (stop - start) = ValueExprBinary(sub, ...)
    assert(tc.trip_expr.op == Core.BinSub, "trip_expr should be subtraction for step=1 exclusive")
    assert(tc.reason:find("trip count expression not materialized"), "reason should mention not materialized, got: " .. tc.reason)
    print("OK: exclusive step=1 trip_expr is BinSub, reason mentions not materialized")
end

-- Test 2: Exclusive loop, step=2
do
    local module, graph, facts = make_loop_module("func:excl_step2", 0, 10, 2, true)
    local sem = CodeFlowFacts.semantic_facts(module, graph, facts)
    local normalized = nil
    for _, f in ipairs(sem.facts or {}) do
        if asdl.classof(f) == Flow.FlowLoopNormalizedCounted then
            normalized = f
            break
        end
    end
    assert(normalized ~= nil, "should produce FlowLoopNormalizedCounted")
    local tc = normalized.trip_count
    assert(tc.trip_expr ~= nil, "trip_expr should not be nil for counted loop")
    -- trip_expr should be (stop - start) / step = ValueExprBinary("div", ...)
    assert(tc.trip_expr.op == Core.BinDiv, "trip_expr should be division for step=2 exclusive")
    print("OK: exclusive step=2 trip_expr is div")
end

-- Test 3: Inclusive loop, step=1
do
    local module, graph, facts = make_loop_module("func:incl_step1", 0, 9, 1, false)
    local sem = CodeFlowFacts.semantic_facts(module, graph, facts)
    local normalized = nil
    for _, f in ipairs(sem.facts or {}) do
        if asdl.classof(f) == Flow.FlowLoopNormalizedCounted then
            normalized = f
            break
        end
    end
    assert(normalized ~= nil, "should produce FlowLoopNormalizedCounted")
    local tc = normalized.trip_count
    assert(tc.trip_expr ~= nil, "trip_expr should not be nil for counted loop")
    -- trip_expr should be (stop - start + step) = ValueExprBinary("add", ...)
    assert(tc.trip_expr.op == Core.BinAdd, "trip_expr should be addition for step=1 inclusive")
    print("OK: inclusive step=1 trip_expr is add")
end

-- Test 4: Inclusive loop, step=2
do
    local module, graph, facts = make_loop_module("func:incl_step2", 0, 10, 2, false)
    local sem = CodeFlowFacts.semantic_facts(module, graph, facts)
    local normalized = nil
    for _, f in ipairs(sem.facts or {}) do
        if asdl.classof(f) == Flow.FlowLoopNormalizedCounted then
            normalized = f
            break
        end
    end
    assert(normalized ~= nil, "should produce FlowLoopNormalizedCounted")
    local tc = normalized.trip_count
    assert(tc.trip_expr ~= nil, "trip_expr should not be nil for counted loop")
    -- trip_expr should be (stop - start + step) / step
    assert(tc.trip_expr.op == Core.BinDiv, "trip_expr should be division for step=2 inclusive")
    print("OK: inclusive step=2 trip_expr is div")
end

-- Test 5: Verify FlowTripCountUnknown without counted domain falls back to nil trip_expr
do
    local tc = Flow.FlowTripCountUnknown("no info", nil)
    assert(tc.trip_expr == nil, "trip_expr should be nil when explicitly passed nil")
    assert(tc.reason == "no info", "reason should be preserved")
    print("OK: explicit nil trip_expr works")
end

-- Test 6: Verify FlowTripCountExact constructor with trip_expr
do
    local count_id = Code.CodeValueId("test:count")
    local idx_ty2 = Code.CodeTyIndex
    local trip_expr = Value.ValueExprBinary(Core.BinSub, Value.ValueExprValue(count_id), Value.ValueExprValue(Code.CodeValueId("test:zero")), idx_ty2)
    local tc = Flow.FlowTripCountExact(count_id, trip_expr, nil)
    assert(tc.trip_expr ~= nil, "trip_expr should be preserved in Exact variant")
    assert(tc.trip_expr.op == Core.BinSub, "trip_expr should be the subtraction we passed")
    assert(tc.count.text == "test:count", "count should be preserved")
    print("OK: FlowTripCountExact carries trip_expr")
end

-- Test 7: Verify FlowTripCountNonNegative constructor with trip_expr
do
    local count_id = Code.CodeValueId("test:nncount")
    local idx_ty3 = Code.CodeTyIndex
    local trip_expr = Value.ValueExprBinary(Core.BinDiv, Value.ValueExprValue(count_id), Value.ValueExprValue(Code.CodeValueId("test:two")), idx_ty3)
    local tc = Flow.FlowTripCountNonNegative(count_id, trip_expr, nil)
    assert(tc.trip_expr ~= nil, "trip_expr should be preserved in NonNegative variant")
    assert(tc.trip_expr.op == Core.BinDiv, "trip_expr should be the division we passed")
    print("OK: FlowTripCountNonNegative carries trip_expr")
end

print("lalin code_flow_trip_count ok")
