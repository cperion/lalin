package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local asdl = require("lalin.asdl")
local A2 = require("lalin.schema_projection")
local Typecheck = require("lalin.tree_typecheck")

local T = asdl.context()
A2(T)
local TC = Typecheck(T)
local C, Ty, B, Tr = T.LalinCore, T.LalinType, T.LalinBind, T.LalinTree

local i32 = Ty.TScalar(C.ScalarI32)
local function lit(raw) return Tr.ExprLit(Tr.ExprSurface, C.LitInt(raw)) end
local function name(n) return Tr.ExprRef(Tr.ExprSurface, B.ValueRefName(n)) end
local function target(owner, member)
  return Tr.RegionInvokeTarget(C.Path({ C.Name(owner), C.Name(member) }))
end

local leaf_done = Tr.RegionCont("cont:R.Leaf:done:1", "done", { Tr.BlockParam("v", i32) })
local leaf = Tr.Region(
  "R.Leaf",
  { Ty.Param("p", i32) },
  { leaf_done },
  {},
  Tr.EntryControlBlock(Tr.BlockLabel("start"), {}, {
    Tr.StmtJumpCont(Tr.StmtSurface, leaf_done, { Tr.JumpArg("v", name("p")) }),
  }),
  {})

local outer_done = Tr.RegionCont("cont:R.Outer:done:1", "done", { Tr.BlockParam("v", i32) })
local outer = Tr.Region(
  "R.Outer",
  { Ty.Param("p", i32) },
  { outer_done },
  {},
  Tr.EntryControlBlock(Tr.BlockLabel("start"), {}, {
    Tr.StmtRegionEmit(
      Tr.StmtSurface,
      "inner",
      target("R", "Leaf"),
      { name("p") },
      { Tr.RegionContWire("done", Tr.RegionWireCont(outer_done, {})) }),
  }),
  {})

local emit_control = Tr.ControlStmtRegion(
  "control.helpers.emit",
  Tr.EntryControlBlock(Tr.BlockLabel("entry"), {
    Tr.EntryBlockParam("entry_value", i32, lit("40")),
  }, {
    Tr.StmtRegionEmit(
      Tr.StmtSurface,
      "outer",
      target("R", "Outer"),
      { name("entry_value") },
      { Tr.RegionContWire("done", Tr.RegionWireBlock(Tr.BlockLabel("after_entry"), {})) }),
  }),
  {
    Tr.ControlBlock(Tr.BlockLabel("after_entry"), { Tr.BlockParam("block_value", i32) }, {
      Tr.StmtRegionEmit(
        Tr.StmtSurface,
        "from_block",
        target("R", "Leaf"),
        { name("block_value") },
        { Tr.RegionContWire("done", Tr.RegionWireBlock(Tr.BlockLabel("done"), {})) }),
    }),
    Tr.ControlBlock(Tr.BlockLabel("done"), { Tr.BlockParam("result", i32) }, {
      Tr.StmtReturnValue(Tr.StmtSurface, name("result")),
    }),
  })

local call_control = Tr.ControlStmtRegion(
  "control.helpers.call",
  Tr.EntryControlBlock(Tr.BlockLabel("entry"), {
    Tr.EntryBlockParam("entry_value", i32, lit("41")),
  }, {
    Tr.StmtRegionCall(
      Tr.StmtSurface,
      "sealed",
      target("R", "Leaf"),
      { name("entry_value") },
      { Tr.RegionContWire("done", Tr.RegionWireBlock(Tr.BlockLabel("done"), {})) }),
  }),
  {
    Tr.ControlBlock(Tr.BlockLabel("done"), { Tr.BlockParam("result", i32) }, {
      Tr.StmtReturnValue(Tr.StmtSurface, name("result")),
    }),
  })

local module = Tr.Module(Tr.ModuleSurface, {
  Tr.ItemRegion(leaf),
  Tr.ItemRegion(outer),
  Tr.ItemFunc(Tr.FuncExport("expand_emit_helpers", {}, i32, { Tr.StmtControl(Tr.StmtSurface, emit_control) })),
  Tr.ItemFunc(Tr.FuncExport("expand_sealed_call", {}, i32, { Tr.StmtControl(Tr.StmtSurface, call_control) })),
})

local checked = TC.check_module(module)
assert(#checked.issues == 0, "parameterized and nested region expansion should typecheck")

local labels = {}
local emit_region = checked.module.items[1].func.body[1].region
for i = 1, #emit_region.blocks do labels[emit_region.blocks[i].label.name] = true end
assert(labels["outer.start"], "entry invocation should append the outer splice block")
assert(labels["outer.inner.start"], "nested invocation should append its splice block")
assert(labels["from_block.start"], "block-parameter invocation should append its splice block")

local call_region = checked.module.items[2].func.body[1].region
assert(call_region.entry.body[1].target.name == "sealed.call_dispatch", "sealed call should expand to its dispatch block")
assert(call_region.blocks[#call_region.blocks].label.name == "sealed.call_dispatch", "sealed call dispatch block should be appended")

print("lalin region expansion helpers ok")
