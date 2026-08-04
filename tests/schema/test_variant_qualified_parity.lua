package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

-- schema parity for the /tmp/probe2.lua `variant` and `qualified` cases.
-- Covers the two source surfaces end to end:
--   * `Type.Variant(args)` variant constructor expressions (ExprCtor)
--   * `case variant Name(bind...) then` switch arms resolved into typed
--     SwitchVariantStmtArm payload binds (StmtVariantSwitchSource)
--   * qualified `fn Owner.method(self ...)` declarations with explicit and
--     injected (`p:method()`) receivers, and field access through the
--     layout projection (ExprDot -> ExprField(FieldByOffset)).
-- Everything is driven through the public compile_source pipeline and the typed
-- schema leaves; no { kind = ... } tables anywhere.

local asdl = require("lalin.asdl")

local T = require("lalin.schema")
require("lalin.impl.compiler_api")
require("lalin.impl.tree_surface")
require("lalin.impl.tree_closure")
require("lalin.impl.tree_check.init")
require("lalin.impl.tree_region")
require("lalin.impl.tree_code")

local Compiler = T.LalinCompiler
local Tr = T.LalinTree
local Document = require("lalin.syntax.document")

local function full_typecheck(source, name)
  local doc = Document.parse(source, name)
  local m = Document.to_module(doc, name)
  local m2 = m:surface_resolve()
  local target = T.LalinHost.HostTargetModel(64, 64, T.LalinHost.HostEndianLittle)
  local m3 = m2:closure_convert(T.LalinSem.ClosureModuleInput(target)).module
  return m3:typecheck_region_expanded()
end

local function compile_artifact(source, name)
  local session = Compiler.CompilerSession(source, name)
  local ok, result = pcall(function() return session:compile() end)
  assert(ok, name .. ": compile_source pipeline crashed: " .. tostring(result))
  assert(asdl.classof(result) == Compiler.CompilerArtifactC,
    name .. ": expected CompilerArtifactC, got " .. tostring(asdl.classof(result))
      .. " (" .. tostring(result.message or "") .. ")")
  return result
end

local passed = 0

-- ============================================================
-- Variant surface: `.` constructor qualification + `case variant` switch
-- ============================================================
print("=== Variant surface parity ===")

local variant_source = [=[
union MaybeI32
  None
  Some(value [i32])
end
fn match_none() [i32] do
  let value [MaybeI32] = MaybeI32.None()
  switch value do
    case variant Some(payload) then
      return payload
    case variant None then
      return 10
    default then
      return -1
  end
end
fn use_some(x [i32]) [i32] do
  let value [MaybeI32] = MaybeI32.Some(x)
  switch value do
    case variant Some(payload) then
      return payload + 1
    case variant None then
      return 0
    default then
      return -1
  end
end
]=]

local vreg = full_typecheck(variant_source, "parity_variant")
assert(asdl.classof(vreg) == Tr.RegionModuleExpanded,
  "variant: expected RegionModuleExpanded, got " .. tostring(asdl.classof(vreg)))
assert(#(vreg:region_issues() or {}) == 0, "variant: region expansion reported issues")

-- The typechecked module must carry typed SwitchVariantStmtArm arms with the
-- payload bind resolved to the variant field type (i32), not the source form.
local vchecked = vreg:region_module()
local v_switches = 0
for i = 1, #vchecked.items do
  local item = vchecked.items[i]
  if asdl.classof(item) == Tr.ItemFunc then
    for j = 1, #(item.func.body or {}) do
      local stmt = item.func.body[j]
      if asdl.classof(stmt) == Tr.StmtSwitch then
        v_switches = v_switches + 1
        assert(#stmt.variant_arms == 2, "variant: expected 2 typed variant arms")
        local some_arm = stmt.variant_arms[1]
        assert(asdl.classof(some_arm) == Tr.SwitchVariantStmtArm,
          "variant: source arm must resolve to typed SwitchVariantStmtArm")
        assert(#some_arm.binds == 1 and some_arm.binds[1].name == "payload",
          "variant: payload bind not preserved")
        local payload_ty = some_arm.binds[1].ty
        assert(asdl.classof(payload_ty) == T.LalinType.TScalar
          and payload_ty.scalar == T.LalinCore.ScalarI32,
          "variant: payload bind must be the variant field type i32")
      end
    end
  end
end
assert(v_switches == 2, "variant: expected 2 typed switches, got " .. tostring(v_switches))
passed = passed + 1
print("  PASS: typed variant switch arms (SwitchVariantStmtArm + i32 payload bind)")

-- Full compile_source artifact parity: the probe expects OK-C source output.
local vc = compile_artifact(variant_source, "parity_variant")
-- The tagged union lowers to the flat __offset_N struct contract: the tag
-- lives at __offset_0 and the payload is extracted from the byte range
-- at the layout's payload offset (no nested __payload union).
assert(vc.source:find("switch %("), "variant: emitted C must contain the tag switch")
assert(vc.source:find("__offset_0", 1, true) and vc.source:find("unsigned char%*"),
  "variant: emitted C must extract the payload from the flat __offset_N struct")
passed = passed + 1
print("  PASS: compile_source variant artifact (tag switch + payload access)")

-- ============================================================
-- Qualified method surface: fn Owner.method + receivers
-- ============================================================
print("=== Qualified method parity ===")

local qualified_source = [=[
struct Point
  x [i32]
  y [i32]
end
fn Point.sum(self [ptr [Point]]) [i32] do
  return self.x + self.y
end
fn explicit_receiver(p [ptr [Point]]) [i32] do
  return sum(p)
end
fn injected_receiver(p [ptr [Point]]) [i32] do
  return p:sum()
end
]=]

local qreg = full_typecheck(qualified_source, "parity_qualified")
assert(asdl.classof(qreg) == Tr.RegionModuleExpanded,
  "qualified: expected RegionModuleExpanded, got " .. tostring(asdl.classof(qreg)))
assert(#(qreg:region_issues() or {}) == 0, "qualified: region expansion reported issues")

-- Field access must resolve through the layout projection to a lowered
-- FieldByOffset ref (the code phase requires it, no sem_layout_resolve pass).
local qchecked = qreg:region_module()
local saw_field_by_offset = false
for i = 1, #qchecked.items do
  local item = qchecked.items[i]
  if asdl.classof(item) == Tr.ItemFunc and item.func.name == "sum" then
    local body = item.func.body or {}
    assert(#body == 1 and asdl.classof(body[1]) == Tr.StmtReturnValue,
      "qualified: Point.sum body shape")
    local value = body[1].value
    assert(asdl.classof(value) == Tr.ExprBinary,
      "qualified: Point.sum returns a binary expression")
    local lhs = value.lhs
    assert(asdl.classof(lhs) == Tr.ExprField,
      "qualified: self.x must resolve to ExprField")
    assert(asdl.classof(lhs.field) == T.LalinSem.FieldByOffset,
      "qualified: field ref must be lowered FieldByOffset, got "
        .. tostring(asdl.classof(lhs.field)))
    assert(lhs.field.field_name == "x" and lhs.field.offset == 0,
      "qualified: field x at offset 0")
    saw_field_by_offset = true
  end
end
assert(saw_field_by_offset, "qualified: Point.sum field access not found")
passed = passed + 1
print("  PASS: qualified method field access resolves to FieldByOffset")

-- Full compile_source artifact parity: both receiver forms call the same method.
local qc = compile_artifact(qualified_source, "parity_qualified")
local sum_calls = 0
-- `sum(` also matches the definition line (`int32_t sum(module_Point* ...)`),
-- so count the call-site assignment pattern specifically.
local sum_calls = 0
for _ in qc.source:gmatch("= sum%(") do sum_calls = sum_calls + 1 end
assert(sum_calls == 2, "qualified: both receivers must lower to direct calls to sum, got "
  .. tostring(sum_calls))
assert(qc.source:find("explicit_receiver") and qc.source:find("injected_receiver"),
  "qualified: both receiver functions must be emitted")
passed = passed + 1
print("  PASS: compile_source qualified artifact (explicit + injected receiver calls)")

-- ============================================================
-- Cross-function direct call symbol resolution
-- ============================================================
-- Internal CodeFunc ids retain the deterministic fn_ CMat contract;
-- the lowering-phase projection maps each fn_ id to the public
-- CodeFunc.name so CBackend direct calls emit the exported symbol.
print("=== Cross-function direct call symbol resolution ===")

local Code = T.LalinCode
local Lower = T.LalinLower
local CBackend = T.LalinC

local direct_target = Code.CodeCallDirect(Code.CodeFuncId("fn_sum"))
assert(direct_target.func.text == "fn_sum",
  "internal func id must retain the deterministic fn_ contract")
local symbols = Lower.LowerCFuncSymbolProjection({
  Lower.LowerCFuncSymbolEntry(Code.CodeFuncId("fn_sum"), "sum"),
})
local found = symbols:lower_c_func_symbol_lookup(Code.CodeFuncId("fn_sum"))
assert(asdl.classof(found) == Lower.LowerCFuncSymbolFound,
  "fn_sum must resolve through the func-symbol projection")
assert(found:lower_c_func_symbol() == "sum",
  "projection must map the fn_ id to the public CodeFunc.name")
local missing = symbols:lower_c_func_symbol_lookup(Code.CodeFuncId("fn_other"))
assert(asdl.classof(missing) == Lower.LowerCFuncSymbolMissing,
  "unknown func ids must produce the typed Missing leaf")

local call_input = Lower.LowerCInstructionInput(
  Lower.LowerCSignatureProjection({}), Lower.LowerCValueTypeProjection({}), symbols, Lower.LowerCExternSymbolProjection({}))
local c_call = direct_target:lower_code_call_target_to_c(call_input)
assert(asdl.classof(c_call) == CBackend.CBackendCallDirect,
  "direct call must lower to CBackendCallDirect")
assert(c_call.func.text == "sum",
  "CBackend direct call must emit the public symbol, got " .. tostring(c_call.func.text))
passed = passed + 1
print("  PASS: fn_ id -> public symbol resolution for cross-function calls")


print(string.format("\nAll variant/qualified parity tests passed (%d)", passed))
