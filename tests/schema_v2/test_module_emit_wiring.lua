package.path = "tests/?.lua;./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

----------------------------------------------------------------------
-- test_module_emit_wiring.lua
-- Verifies Phase 3: LowerModule:emit_c populates externs, globals,
-- types, and datas from code_module.
----------------------------------------------------------------------

require("lalin.schema_v2")
local Code   = require("lalin.schema_v2.code")
local Core   = require("lalin.schema_v2.core")
local C      = require("lalin.schema_v2.c")
local Graph  = require("lalin.schema_v2.graph")
local Lower  = require("lalin.schema_v2.lower")
local Type   = require("lalin.schema_v2.type")
local asdl   = require("lalin.asdl")

require("lalin.impl.lower_emit_c")
require("lalin.impl.lower_emit_c.code_to_c")

----------------------------------------------------------------------
-- Helper: create a minimal LowerModule
----------------------------------------------------------------------
local function make_lower_module()
  local Backend  = require("lalin.schema_v2.backend")
  local Schedule = require("lalin.schema_v2.schedule")
  local Kernel   = require("lalin.schema_v2.kernel")
  local Flow     = require("lalin.schema_v2.flow")
  local Value    = require("lalin.schema_v2.value")
  local Mem      = require("lalin.schema_v2.mem")
  local Effect   = require("lalin.schema_v2.effect")
  local mod_id   = Code.CodeModuleId("test_wiring")
  local flow_set   = Flow.FlowFactSet(mod_id, {}, {}, {}, {}, {}, {}, {}, {}, {}, {})
  local value_set  = Value.ValueFactSet(mod_id, {}, {}, {})
  local mem_set    = Mem.MemSemanticFactSet(mod_id, {}, {}, {}, {}, {}, {}, {}, {}, {}, {})
  local effect_set = Effect.EffectFactSet(mod_id, {}, {}, {})
  local kernel_plan = Kernel.KernelModulePlan(mod_id, flow_set, value_set, mem_set, effect_set, {})
  local backend_target_model = Backend.BackTargetModel(Backend.BackTargetNative, {})
  local schedule_target = Schedule.ScheduleTarget(backend_target_model)
  local schedule_plan = Schedule.ScheduleModulePlan(mod_id, schedule_target, {})
  return Lower.LowerModule(
    mod_id,
    Lower.LowerTargetC,
    kernel_plan,
    schedule_plan,
    Lower.LowerCarrierPlanProjection({}), Lower.LowerAddressPlanProjection({}), Lower.LowerFunctionPlanProjection({}), {}
  )
end

local lower_module = make_lower_module()

----------------------------------------------------------------------
-- Build a CodeModule with externs, globals, types, and datas
----------------------------------------------------------------------

local module_id = Code.CodeModuleId("wired_module")
local i32_type = Code.CodeTyInt(32, Code.CodeSigned)

-- Func (minimal, just for emit_c to produce something)
local func_id = Code.CodeFuncId("dummy")
local sig_id  = Code.CodeSigId("dummy_sig")
local sig    = Code.CodeSig(sig_id, {}, { i32_type })
local ret_op = Code.CodeTermReturn({})
local ret_term = Code.CodeTerm(Code.CodeTermId("trm"), ret_op, Code.CodeOriginSource("ret"))
local block = Code.CodeBlock(Code.CodeBlockId("entry"), "entry", {}, {}, ret_term, Code.CodeOriginSource("entry"))
local func = Code.CodeFunc(func_id, "dummy", Code.CodeLinkageExport, sig_id, {}, {}, Code.CodeBlockId("entry"), { block }, Code.CodeOriginSource("fn"))

-- Extern: a C function
local ext = Code.CodeExtern(
  Code.CodeExternId("ext_puts"), "puts", "puts",
  sig_id, Code.CodeOriginSource("ext")
)

-- Global: a global variable
local glob_init = Code.CodeDataZero(0, 4)
local glob = Code.CodeGlobal(
  Code.CodeGlobalId("g_counter"), "g_counter", i32_type,
  Code.CodeLinkageExport, 4, 4,
  { glob_init }, Code.CodeOriginSource("global")
)

-- Type decl
local type_decl = Code.CodeTypeDecl(
  Code.CodeTypeId("MyType"),
  "MyType",
  Code.CodeTyNamed("wired_module", "MyType", Type.TScalar(Core.ScalarI32)),
  Code.CodeOriginSource("type")
)

-- Data segment
local data_init = Code.CodeDataBytes(0, "\x01\x02\x03\x04")
local data_seg = Code.CodeData(
  Code.CodeDataId("d_rodata"), "d_rodata",
  Code.CodeLinkageLocal, 4, 4,
  { data_init }, Code.CodeOriginSource("data")
)

local code_module = Code.CodeModule(
  module_id,
  { sig },               -- sigs
  { type_decl },         -- types
  { data_seg },          -- data
  { glob },              -- globals
  { ext },               -- externs
  { func },              -- funcs
  Code.CodeOriginSource("test")
)

----------------------------------------------------------------------
-- Run emit_c and verify fields
----------------------------------------------------------------------

local c_target = C.CBackendTarget(C.CBackendC99, C.CBackendHostedNative, 64, 64, C.CBackendLittleEndian, true)
local input = Lower.LowerCModuleInput(
  Lower.LowerBackSpine(code_module, Graph.CodeGraph(code_module.id, {}), c_target),
  lower_module, Lower.LowerKernelCMatProjection({}))
local emission = lower_module:lower_c_module(input)
assert(asdl.classof(emission) == Lower.LowerCModuleEmission, "module lowering must return typed emission")
local c_unit = emission.unit
assert(asdl.classof(c_unit) == C.CBackendUnit, "typed emission must own CBackendUnit")
assert(lower_module:emit_c(input) == c_unit, "public emit boundary must unwrap canonical typed result")
assert(c_unit.module_name == "wired_module", "bad module_name")

-- Test externs
assert(#c_unit.externs >= 1, "expected >=1 externs, got " .. #c_unit.externs)
local cext = c_unit.externs[1]
assert(asdl.classof(cext) == C.CBackendExtern,
  "expected CBackendExtern, got " .. tostring(asdl.classof(cext)))
assert(cext.name.text == "puts", "extern name: " .. cext.name.text)
assert(cext.symbol == "puts", "extern symbol: " .. cext.symbol)
assert(cext.sig.text == "dummy_sig", "extern sig: " .. cext.sig.text)
print("PASS: 1 extern wired (puts)")

-- Test globals (includes both CodeGlobal and CodeData)
assert(#c_unit.globals >= 2,
  "expected >=2 globals (1 global + 1 data), got " .. #c_unit.globals)

-- Find the global by name
local found_global = false
local found_data = false
for _, g in ipairs(c_unit.globals) do
  if g.name.text == "g_counter" then
    found_global = true
    assert(asdl.classof(g) == C.CBackendGlobal,
      "expected CBackendGlobal, got " .. tostring(asdl.classof(g)))
    assert(g.visibility == Core.VisibilityExport,
      "expected export visibility for global")
    assert(g.size == 4, "global size: " .. tostring(g.size))
    assert(g.align == 4, "global align: " .. tostring(g.align))
    assert(#g.inits == 1, "expected 1 init, got " .. #g.inits)
    assert(asdl.classof(g.inits[1]) == C.CBackendDataZero,
      "expected CBackendDataZero, got " .. tostring(asdl.classof(g.inits[1])))
  end
  if g.name.text == "d_rodata" then
    found_data = true
    assert(g.visibility == Core.VisibilityLocal,
      "expected local visibility for data")
    assert(g.size == 4, "data size: " .. tostring(g.size))
    assert(g.align == 4, "data align: " .. tostring(g.align))
    assert(#g.inits == 1, "expected 1 data init, got " .. #g.inits)
    assert(asdl.classof(g.inits[1]) == C.CBackendDataBytes,
      "expected CBackendDataBytes, got " .. tostring(asdl.classof(g.inits[1])))
  end
end
assert(found_global, "global 'g_counter' not found in c_unit.globals")
assert(found_data, "data 'd_rodata' not found in c_unit.globals")
print("PASS: global 'g_counter' (export, CBackendDataZero init)")
print("PASS: data 'd_rodata' (local, CBackendDataBytes init)")

-- Test types
assert(#c_unit.types >= 1, "expected >=1 types, got " .. #c_unit.types)
local ctype = c_unit.types[1]
assert(asdl.classof(ctype) == C.CBackendOpaqueDecl,
  "expected CBackendOpaqueDecl, got " .. tostring(asdl.classof(ctype)))
assert(ctype.id.module_name == "wired_module", "type ID module_name: " .. ctype.id.module_name)
assert(ctype.id.spelling == "MyType", "type ID spelling: " .. ctype.id.spelling)
print("PASS: 1 type decl (CBackendOpaqueDecl 'MyType')")

-- Test func still works
assert(#c_unit.funcs == 1, "expected 1 func")
assert(c_unit.funcs[1].name.text == "dummy")
print("PASS: func still lowers correctly")

-- Test sig still works
assert(#c_unit.sigs == 1, "expected 1 sig")
print("PASS: sig still lowers correctly")

print("\nAll module names:")
print(string.format("  module_name: %s", c_unit.module_name))
print(string.format("  sigs: %d", #c_unit.sigs))
print(string.format("  types: %d", #c_unit.types))
print(string.format("  globals: %d", #c_unit.globals))
for _, g in ipairs(c_unit.globals) do
  print(string.format("    %s (size=%d, align=%d, inits=%d)",
    g.name.text, g.size, g.align, #g.inits))
end
print(string.format("  externs: %d", #c_unit.externs))
for _, e in ipairs(c_unit.externs) do
  print(string.format("    %s (symbol=%s)", e.name.text, e.symbol))
end
print(string.format("  funcs: %d", #c_unit.funcs))

print("\n=== All Phase 3 module wiring tests passed ===")
