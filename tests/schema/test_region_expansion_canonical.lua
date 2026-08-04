package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local asdl = require("lalin.asdl")
local T = require("lalin.schema")
require("lalin.impl.tree_check.init")
require("lalin.impl.tree_region")

local Tr, Ty, C, B, Check = T.LalinTree, T.LalinType, T.LalinCore, T.LalinBind, T.LalinCheck
local i32 = Ty.TScalar(C.ScalarI32)
local function lit(n) return Tr.ExprLit(Tr.ExprTyped(i32), C.LitInt(tostring(n))) end
local function ref(name) return Tr.ExprRef(Tr.ExprTyped(i32), B.ValueRefName(name)) end
local function target(a, b) return Tr.RegionInvokeTarget(C.Path({ C.Name(a), C.Name(b) })) end
local function cont(name, param)
  return Tr.RegionCont(Tr.RegionProtocolKey(name), name, { Tr.BlockParam(param, i32) })
end

local inner_target = target("R", "Inner")
local inner_done = cont("done", "value")
local inner = Tr.Region("R.Inner", { Ty.Param("input", i32) }, { inner_done }, {},
  Tr.EntryControlBlock(Tr.BlockLabel("start"), {}, {
    Tr.StmtJumpCont(Tr.StmtSurface, inner_done, { Tr.JumpArg("value", ref("input")) }),
  }), {})

local outer_target = target("R", "Outer")
local outer_done = cont("done", "result")
local captured_wire = Tr.RegionContWire("done", Tr.RegionWireBlock(Tr.BlockLabel("after"), {
  Tr.JumpArg("result", lit(9)),
}))
local outer = Tr.Region("R.Outer", { Ty.Param("input", i32) }, { outer_done }, {},
  Tr.EntryControlBlock(Tr.BlockLabel("start"), {}, {
    Tr.StmtRegionEmit(Tr.StmtSurface, "inner", inner_target, { ref("input") }, { captured_wire }),
  }), {
    Tr.ControlBlock(Tr.BlockLabel("after"), { Tr.BlockParam("result", i32) }, {
      Tr.StmtJumpCont(Tr.StmtSurface, outer_done, { Tr.JumpArg("result", ref("result")) }),
    }),
  })

local module = Tr.Module(Tr.ModuleSurface, { Tr.ItemRegion(inner), Tr.ItemRegion(outer) })
local facts = module:region_fact_projection()
assert(asdl.isa(facts, Tr.RegionFactProjection))
assert(#facts.definitions.entries == 2 and #facts.protocols.entries == 2 and #facts.seals.entries == 2)

local state = Check.TypeStmtInput(
  Check.TypeValueScope("rgn", {}, {}, {}, Check.TypeModuleFacts({}, {}, {}, facts)),
  i32, Check.TypeYieldNone)
local expansion = Tr.RegionExpansionId("nested")
local input = Tr.RegionInvokeExpandInput(state, facts, expansion)

local nested = Tr.StmtRegionEmit(Tr.StmtSurface, "outer", outer_target, { lit(3) }, {
  Tr.RegionContWire("done", Tr.RegionWireBlock(Tr.BlockLabel("caller_done"), {})),
})
local accepted = nested:region_expand_invoke(input)
assert(asdl.isa(accepted, Tr.RegionInvokeExpanded))
assert(#accepted.splice.blocks >= 3, "nested region expansion must retain the inner splice blocks")
local pipeline_control = Tr.ControlStmtRegion("run",
  Tr.EntryControlBlock(Tr.BlockLabel("entry"), {}, { nested }),
  { Tr.ControlBlock(Tr.BlockLabel("caller_done"), { Tr.BlockParam("result", i32) },
      { Tr.StmtReturnValue(Tr.StmtSurface, ref("result")) }) })
local pipeline_module = Tr.Module(Tr.ModuleSurface, {
  Tr.ItemRegion(inner), Tr.ItemRegion(outer),
  Tr.ItemFunc(Tr.FuncLocal("run", {}, i32, { Tr.StmtControl(Tr.StmtSurface, pipeline_control) }))
})
local checked_pipeline = pipeline_module:typecheck({})
local pipeline_facts = checked_pipeline:region_fact_projection()
local pipeline_result = checked_pipeline:region_expand(Tr.RegionModuleExpansionInput(pipeline_facts))
assert(asdl.isa(pipeline_result, Tr.RegionModuleExpanded))
assert(#pipeline_result:region_issues() == 0)
-- Every region becomes a generated result type plus a sealed callable; the
-- authored region definition itself does not leak into Code lowering.
assert(#pipeline_result.module.items == 5, "two sealed regions must materialize two type/function pairs")
assert(asdl.isa(pipeline_result.module.items[1], Tr.ItemType))
assert(asdl.isa(pipeline_result.module.items[2], Tr.ItemFunc))
assert(asdl.isa(pipeline_result.module.items[3], Tr.ItemType))
assert(asdl.isa(pipeline_result.module.items[4], Tr.ItemFunc))
assert(#pipeline_result.module.items[5].func.body[1].region.blocks >= 3)

local inner_call = Tr.StmtRegionEmit(Tr.StmtSurface, "captured", inner_target, { lit(4) }, { captured_wire })
local captured = inner_call:region_expand_invoke(input)
assert(asdl.isa(captured, Tr.RegionInvokeExpanded))
assert(#captured.splice.captures.entries == 1, "wire expression must become a typed capture entry")
assert(captured.splice.captures.entries[1].ty == i32)
assert(captured.splice.next_state == state, "expansion state is immutable")

local missing = Tr.StmtRegionEmit(Tr.StmtSurface, "missing", target("R", "NoSuchRegion"), { lit(1) }, {})
local rejected = missing:region_expand_invoke(input)
assert(asdl.isa(rejected, Tr.RegionInvokeRejected))
local explanation = Check.TypeIssueRegionInvoke(rejected.reject):typecheck_tree_explanation()
assert(explanation.code == "E0408" and explanation.primary ~= "")

print("canonical region expansion leaves ok")
