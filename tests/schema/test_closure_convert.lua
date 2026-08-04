-- tests/schema/test_closure_convert.lua
-- Tests for the scalar closure conversion in impl/tree_closure.lua
--
-- Tests:
--  1. Scalar function without captures → pass-through
--  2. Scalar function with free variable capture → helper generated
--  3. Struct functions → pass-through (no captures)
--  4. Nested closures → UNSUPPORTED error

package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local T = require("lalin.schema")
require("lalin.impl.tree_surface")
require("lalin.impl.tree_closure")
require("lalin.impl.tree_check.init")
require("lalin.impl.tree_code")

local Tr, Sem, Ty, C, B, H = T.LalinTree, T.LalinSem, T.LalinType, T.LalinCore, T.LalinBind, T.LalinHost
local asdl = require("lalin.asdl")
local Document = require("lalin.syntax.document")
local target64 = H.HostTargetModel(64, 64, H.HostEndianLittle)
local function module_input(target) return Sem.ClosureModuleInput(target or target64) end

local passes, total = 0, 0
local failures = {}

local function assert_ok(label, ok, err)
  total = total + 1
  if ok then
    passes = passes + 1
    print(string.format("  %s -> OK", label))
  else
    failures[#failures + 1] = { label = label, err = tostring(err or "unknown") }
    print(string.format("  %s -> FAIL: %s", label, tostring(err or "unknown")))
  end
end

local function assert_error(label, ok, err, expected_msg)
  total = total + 1
  if not ok then
    local msg = tostring(err or "")
    if msg:find(expected_msg, 1, true) then
      passes = passes + 1
      print(string.format("  %s -> OK (got expected error: %s)", label, expected_msg))
    else
      failures[#failures + 1] = { label = label, err = "expected '" .. expected_msg .. "', got '" .. msg .. "'" }
      print(string.format("  %s -> FAIL: expected '%s', got '%s'", label, expected_msg, msg))
    end
  else
    failures[#failures + 1] = { label = label, err = "expected error but got success" }
    print(string.format("  %s -> FAIL: expected error but got success", label))
  end
end

----------------------------------------------------------------------
-- Test 1: Scalar function without captures → pass-through
----------------------------------------------------------------------
print("=== Test 1: Scalar function without captures ===")
do
  local source = [[
fn add(a [i32], b [i32]) [i32] do
  return a + b
end
]]
  local ok, doc = pcall(Document.parse, source, "test_no_captures")
  assert_ok("parse", ok, doc)

  local ok2, m = pcall(Document.to_module, doc, "test_no_captures")
  assert_ok("to_module", ok2, m)

  if ok2 then
    local ok3, m2 = pcall(function() return m:surface_resolve() end)
    assert_ok("surface_resolve", ok3, m2)

    if ok3 then
      local ok4, m3 = pcall(function() return m2:closure_convert(module_input()) end)
      assert_ok("closure_convert", ok4, m3)

      if ok4 then
        assert_ok("typed ClosureConvertResult", asdl.isa(m3, Sem.ClosureConvertResult), m3)
        local count = #(m3.module.items or {})
        assert_ok("item_count=1", count == 1, "got " .. tostring(count) .. " items, expected 1")
      end
    end
  end
end

----------------------------------------------------------------------
-- Test 2: Struct function → pass-through (structs resolved)
----------------------------------------------------------------------
print("\n=== Test 2: Struct functions ===")
do
  local source = [[
struct Point
  x [i32]
  y [i32]
end

fn make_point(x [i32], y [i32]) [Point] do
  return Point { x = x, y = y }
end
]]
  local ok, doc = pcall(Document.parse, source, "test_struct")
  assert_ok("parse", ok, doc)

  local ok2, m = pcall(Document.to_module, doc, "test_struct")
  assert_ok("to_module", ok2, m)

  if ok2 then
    local ok3, m2 = pcall(function() return m:surface_resolve() end)
    assert_ok("surface_resolve", ok3, m2)

    if ok3 then
      local ok4, m3 = pcall(function() return m2:closure_convert(module_input()) end)
      assert_ok("closure_convert", ok4, m3)

      if ok4 then
        local ok5, checked = pcall(function() return m3.module:typecheck({}) end)
        assert_ok("typecheck", ok5, checked)
      end
    end
  end
end

----------------------------------------------------------------------
-- Test 3: StmtIf with logic → pass-through
----------------------------------------------------------------------
print("\n=== Test 3: StmtIf with logic ===")
do
  local source = [[
fn test_if(x [i32]) [i32] do
  if x > 0 then
    return x
  else
    return 0
  end
end
]]
  local ok, doc = pcall(Document.parse, source, "test_if")
  assert_ok("parse", ok, doc)

  local ok2, m = pcall(Document.to_module, doc, "test_if")
  assert_ok("to_module", ok2, m)

  if ok2 then
    local ok3, m2 = pcall(function() return m:surface_resolve() end)
    assert_ok("surface_resolve", ok3, m2)

    if ok3 then
      local ok4, m3 = pcall(function() return m2:closure_convert(module_input()) end)
      assert_ok("closure_convert", ok4, m3)
    end
  end
end

----------------------------------------------------------------------
-- Test 4: closure environment materialization and call-site rewrite
----------------------------------------------------------------------
print("\n=== Test 4: Typed closure materialization ===")
do
  local i32 = Ty.TScalar(C.ScalarI32)
  local closure_ty = Ty.TClosure({}, i32)
  local outer = B.Binding(C.Id("closure:test:outer"), "outer", i32, B.BindingRoleLocalValue)
  local closure = Tr.ExprClosure(Tr.ExprSurface, {}, i32, {
    Tr.StmtReturnValue(Tr.StmtSurface, Tr.ExprRef(Tr.ExprSurface, B.ValueRefName("outer"))),
  })
  local call = Tr.ExprCall(Tr.ExprSurface, closure, {})
  local func = Tr.FuncLocal("invoke", {}, i32, {
    Tr.StmtLet(Tr.StmtSurface, outer, Tr.ExprLit(Tr.ExprSurface, C.LitInt("7"))),
    Tr.StmtReturnValue(Tr.StmtSurface, call),
  })
  local module = Tr.Module(Tr.ModuleSurface, { Tr.ItemFunc(func) }):surface_resolve()
  local converted = module:closure_convert(module_input())
  assert_ok("module closure converted", asdl.isa(converted, Sem.ClosureConverted), converted)
  assert_ok("environment type + helper + owner materialized", #converted.module.items == 3, #converted.module.items)
  local owner = converted.module.items[3].func
  local rewritten_call = owner.body[2].value
  assert_ok("call-site callee rewritten", asdl.isa(rewritten_call.callee, Tr.ExprBlock), rewritten_call.callee)
  assert_ok("environment aggregate materialized", asdl.isa(rewritten_call.callee.stmts[1].init, Tr.ExprAgg), rewritten_call.callee.stmts[1].init)
  assert_ok("descriptor carries fn and ctx", #rewritten_call.callee.result.fields == 2, #rewritten_call.callee.result.fields)
  local target32 = H.HostTargetModel(32, 32, H.HostEndianLittle)
  local converted32 = module:closure_convert(module_input(target32))
  local descriptor32 = converted32.module.items[3].func.body[2].value.callee.result
  assert_ok("selected target enters closure descriptor layout", descriptor32.fields[2].offset == 4, descriptor32.fields[2].offset)
  local checked_ok, checked = pcall(function() return converted.module:typecheck({}) end)
  assert_ok("materialized closure typechecks", checked_ok, checked)
  local lower_ok, lowered = pcall(function() return checked:lower_tree_module_result_to_code({ target = H.HostTargetModel(64, 64, H.HostEndianLittle) }) end)
  assert_ok("materialized closure lowers", lower_ok, lowered)
  if lower_ok then
    local closure_inst, closure_call
    for _, code_func in ipairs(lowered.code_module.funcs) do for _, block in ipairs(code_func.blocks) do for _, inst in ipairs(block.insts) do
      if asdl.isa(inst.op, T.LalinCode.CodeInstClosure) then closure_inst = inst.op end
      if asdl.isa(inst.op, T.LalinCode.CodeInstCall) and asdl.isa(inst.op.target, T.LalinCode.CodeCallClosure) then closure_call = inst.op end
    end end end
    assert_ok("typed environment becomes CodeInstClosure", closure_inst ~= nil, closure_inst)
    assert_ok("call-site becomes CodeCallClosure", closure_call ~= nil, closure_call)
  end
end

print("\n=== Test 5: switch/control/jump traversal ===")
do
  local i32 = Ty.TScalar(C.ScalarI32)
  local binding = B.Binding(C.Id("closure:traversal:x"), "x", i32, B.BindingRoleLocalValue)
  local candidate = Sem.ClosureCaptureCandidate(Sem.ClosureBinding(binding))
  local slot = Sem.ClosureCaptureSlot(candidate, 0, 4, 4)
  local input = Sem.ClosureRewriteInput(
    Sem.ClosureScopeStack({ Sem.ClosureScopeFrame({}) }),
    Sem.ClosureEnvironment({ Sem.ClosureEnvironmentEntry(Sem.ClosureBinding(binding), slot) }),
    Sem.ClosureNameSupply("traversal", "owner", 1), Sem.ClosureHelperInsertion({}), Sem.LayoutEnv({}),
    H.HostTargetModel(64, 64, H.HostEndianLittle))
  local ref = function() return Tr.ExprRef(Tr.ExprSurface, B.ValueRefName("x")) end
  local switch = Tr.ExprSwitch(Tr.ExprSurface, ref(), {
    Tr.SwitchExprArm(Tr.SwitchKeyExpr(ref()), { Tr.StmtExpr(Tr.StmtSurface, ref()) }, ref()),
  }, {}, { Tr.StmtExpr(Tr.StmtSurface, ref()) }, ref())
  local sr = switch:closure_rewrite(input)
  assert_ok("switch value captured", asdl.isa(sr.expr.value, Tr.ExprLoad), sr.expr.value)
  assert_ok("switch key/body/result captured", asdl.isa(sr.expr.arms[1].key.expr, Tr.ExprLoad) and asdl.isa(sr.expr.arms[1].body[1].expr, Tr.ExprLoad) and asdl.isa(sr.expr.arms[1].result, Tr.ExprLoad), sr.expr.arms[1])
  assert_ok("switch default captured", asdl.isa(sr.expr.default_body[1].expr, Tr.ExprLoad) and asdl.isa(sr.expr.default_expr, Tr.ExprLoad), sr.expr.default_expr)

  local label = Tr.BlockLabel("entry")
  local cont = Tr.RegionCont(Tr.RegionProtocolKey("done"), "done", {})
  local jump = Tr.StmtJump(Tr.StmtSurface, label, { Tr.JumpArg("x", ref()) })
  local jump_cont = Tr.StmtJumpCont(Tr.StmtSurface, cont, { Tr.JumpArg("x", ref()) })
  local region = Tr.ControlStmtRegion("r", Tr.EntryControlBlock(label, { Tr.EntryBlockParam("p", i32, ref()) }, { jump, jump_cont }), {})
  local cr = Tr.StmtControl(Tr.StmtSurface, region):closure_rewrite(input)
  assert_ok("control entry initializer captured", asdl.isa(cr.stmt.region.entry.params[1].init, Tr.ExprLoad), cr.stmt.region.entry.params[1].init)
  assert_ok("jump and continuation args captured", asdl.isa(cr.stmt.region.entry.body[1].args[1].value, Tr.ExprLoad) and asdl.isa(cr.stmt.region.entry.body[2].args[1].value, Tr.ExprLoad), cr.stmt.region.entry.body)
end

print("\n=== Test 6: nested closure rejection ===")
do
  local i32 = Ty.TScalar(C.ScalarI32)
  local nested = Tr.ExprClosure(Tr.ExprSurface, {}, i32, { Tr.StmtReturnValue(Tr.StmtSurface, Tr.ExprLit(Tr.ExprSurface, C.LitInt("1"))) })
  local outer = Tr.ExprClosure(Tr.ExprSurface, {}, i32, { Tr.StmtExpr(Tr.StmtSurface, nested), Tr.StmtReturnValue(Tr.StmtSurface, Tr.ExprLit(Tr.ExprSurface, C.LitInt("2"))) })
  local input = Sem.ClosureRewriteInput(Sem.ClosureScopeStack({ Sem.ClosureScopeFrame({}) }), Sem.ClosureEnvironment({}), Sem.ClosureNameSupply("nested", "owner", 1), Sem.ClosureHelperInsertion({}), Sem.LayoutEnv({}), target64)
  local direct = outer:closure_convert(input)
  assert_ok("nested closure is typed unsupported", asdl.isa(direct, Sem.ClosureExprUnsupported), direct)
  local func = Tr.FuncLocal("nested_owner", {}, i32, { Tr.StmtReturnValue(Tr.StmtSurface, outer) })
  local module = Tr.Module(Tr.ModuleSurface, { Tr.ItemFunc(func) }):surface_resolve()
  local converted = module:closure_convert(module_input())
  assert_ok("nested closure rejection reaches module", asdl.isa(converted, Sem.ClosureUnsupported), converted)
end

----------------------------------------------------------------------
-- Summary
----------------------------------------------------------------------
print(string.format("\n=== %d/%d closure conversion tests passed ===", passes, total))
if #failures > 0 then
  print("\nFailures:")
  for _, f in ipairs(failures) do
    print(string.format("  %s: %s", f.label, f.err))
  end
  os.exit(1)
end
