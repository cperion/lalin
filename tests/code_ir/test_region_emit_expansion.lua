package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local asdl = require("lalin.asdl")
local A2 = require("lalin.schema_projection")
local lalin = require("lalin")
local Typecheck = require("lalin.tree_typecheck")

local T = asdl.context()
A2(T)
local TC = Typecheck(T)
local C, Ty, B, Tr = T.LalinCore, T.LalinType, T.LalinBind, T.LalinTree

local i32 = Ty.TScalar(C.ScalarI32)
local function lit(raw) return Tr.ExprLit(Tr.ExprSurface, C.LitInt(raw)) end
local function name(n) return Tr.ExprRef(Tr.ExprSurface, B.ValueRefName(n)) end

local done_cont = Tr.RegionCont("cont:R.Target:done:1", "done", { Tr.BlockParam("v", i32) })
local target_region = Tr.Region(
  "R.Target",
  { Ty.Param("p", i32) },
  { done_cont },
  Tr.EntryControlBlock(Tr.BlockLabel("start"), {}, {
    Tr.StmtJumpCont(Tr.StmtSurface, done_cont, { Tr.JumpArg("v", name("p")) }),
  }),
  {})

local invoke_region = Tr.ControlStmtRegion(
  "control.invoke.emit",
  Tr.EntryControlBlock(Tr.BlockLabel("entry"), {}, {
    Tr.StmtRegionEmit(
      Tr.StmtSurface,
      "test.emit.1",
      Tr.RegionInvokeTarget(C.Path({ C.Name("R"), C.Name("Target") })),
      { lit("41") },
      { Tr.RegionContWire("done", Tr.RegionWireBlock(Tr.BlockLabel("done"))) }),
  }),
  {
    Tr.ControlBlock(Tr.BlockLabel("done"), { Tr.BlockParam("v", i32) }, {
      Tr.StmtReturnValue(Tr.StmtSurface, name("v")),
    }),
  })

local module = Tr.Module(Tr.ModuleSurface, {
  Tr.ItemRegion(target_region),
  Tr.ItemFunc(Tr.FuncExport("invoke_emit", {}, i32, { Tr.StmtControl(Tr.StmtSurface, invoke_region) })),
})

local checked = TC.check_module(module)
assert(#checked.issues == 0, "region emit expansion should typecheck")
local compiled = lalin.compile_luajit("RegionEmitExpansion", module, { bytecode = true })
assert(compiled.invoke_emit() == 41, "expanded emit should lower and execute")

print("lalin region emit expansion ok")
