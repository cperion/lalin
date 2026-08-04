package.path = "tests/?.lua;./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

----------------------------------------------------------------------
-- test_cbackend_unit_nonempty.lua
-- Verifies that LowerModule:emit_c produces a non-empty CBackendUnit
-- with lowered funcs, blocks, stmts, and terminators for scalar add.
----------------------------------------------------------------------

require("lalin.schema")
local Code   = require("lalin.schema.code")
local Core   = require("lalin.schema.core")
local C      = require("lalin.schema.c")
local Graph  = require("lalin.schema.graph")
local Lower  = require("lalin.schema.lower")
local asdl   = require("lalin.asdl")

-- Load the impl modules
require("lalin.impl.lower_emit_c")
require("lalin.impl.lower_emit_c.code_to_c")

----------------------------------------------------------------------
-- Helper: handcraft a scalar CodeModule with an add function
--   fn add(a: i32, b: i32) -> i32 { return a + b }
----------------------------------------------------------------------

local function make_scalar_add_module()
  local module_id = Code.CodeModuleId("test_add_module")
  local func_id   = Code.CodeFuncId("add")
  local sig_id    = Code.CodeSigId("add_sig")

  -- Types
  local i32_type = Code.CodeTyInt(32, Code.CodeSigned)

  -- Signature
  local sig = Code.CodeSig(sig_id, { i32_type, i32_type }, { i32_type })

  -- Value IDs for params and results
  local value_a  = Code.CodeValueId("a")
  local value_b  = Code.CodeValueId("b")
  local value_r  = Code.CodeValueId("r")

  -- Params
  local param_a  = Code.CodeParam(value_a, "a", i32_type, Code.CodeOriginSource("param_a"))
  local param_b  = Code.CodeParam(value_b, "b", i32_type, Code.CodeOriginSource("param_b"))

  -- Instruction: r = a + b
  local int_sem  = Code.CodeIntSemantics(Code.CodeIntWrap, Code.CodeDivTrapOnZero, Code.CodeShiftMaskCount)
  local bin_op   = Code.CodeInstBinary(value_r, Core.BinAdd, i32_type, int_sem, value_a, value_b)
  local inst_add = Code.CodeInst(Code.CodeInstId("inst_add"), bin_op, Code.CodeOriginSource("add"))

  -- Terminator: return r
  local ret_op   = Code.CodeTermReturn({ value_r })
  local term_ret = Code.CodeTerm(Code.CodeTermId("term_ret"), ret_op, Code.CodeOriginSource("ret"))

  -- Block
  local block_id = Code.CodeBlockId("entry")
  local block    = Code.CodeBlock(block_id, "entry", {}, { inst_add }, term_ret, Code.CodeOriginSource("entry_block"))

  -- Func
  local func     = Code.CodeFunc(
    func_id, "add", Code.CodeLinkageExport,
    sig_id, { param_a, param_b }, {}, block_id,
    { block }, Code.CodeOriginSource("add_func")
  )

  -- Module
  local module = Code.CodeModule(
    module_id,
    { sig },                  -- sigs
    {},                       -- types
    {},                       -- data
    {},                       -- globals
    {},                       -- externs
    { func },                 -- funcs
    Code.CodeOriginSource("test")
  )

  return module
end

----------------------------------------------------------------------
-- Test: LowerModule:emit_c produces a non-empty CBackendUnit
----------------------------------------------------------------------

local code_module = make_scalar_add_module()

-- Create a minimal LowerModule
local Backend = require("lalin.schema.backend")
local Schedule = require("lalin.schema.schedule")
local Kernel = require("lalin.schema.kernel")
local Flow = require("lalin.schema.flow")
local Value = require("lalin.schema.value")
local Mem = require("lalin.schema.mem")
local Effect = require("lalin.schema.effect")
local mod_id = Code.CodeModuleId("kplan")
local flow_set = Flow.FlowFactSet(mod_id, {}, {}, {}, {}, {}, {}, {})
local value_set = Value.ValueFactSet(mod_id, {}, {}, {})
local mem_set = Mem.MemSemanticFactSet(mod_id, {}, {}, {}, {}, {}, {}, {}, {}, {}, {})
local effect_set = Effect.EffectFactSet(mod_id, {}, {}, {})
local kernel_plan = Kernel.KernelModulePlan(mod_id, flow_set, value_set, mem_set, effect_set, {})
local backend_target_model = Backend.BackTargetModel(Backend.BackTargetNative, {})
local schedule_target = Schedule.ScheduleTarget(backend_target_model)
local schedule_plan = Schedule.ScheduleModulePlan(mod_id, schedule_target, {})
local lower_module = Lower.LowerModule(
  mod_id,
  Lower.LowerTargetC,
  kernel_plan,
  schedule_plan,
  Lower.LowerFunctionPlanProjection({}),
  {}
)
local c_target = C.CBackendTarget(C.CBackendC99, C.CBackendHostedNative, 64, 64, C.CBackendLittleEndian, true)
local function lower_input(module)
  return Lower.LowerCModuleInput(
    Lower.LowerBackSpine(module, Graph.CodeGraph(module.id, {}), c_target),
    lower_module, Lower.LowerKernelCMatProjection({}))
end

local c_result = lower_module:lower_c_module(lower_input(code_module))
assert(asdl.classof(c_result) == Lower.LowerCModuleEmitted)
local c_unit = c_result.emission.unit

-- Assertions
assert(c_unit ~= nil, "emit_c returned nil")

-- Module structure
assert(c_unit.module_name == "test_add_module", "wrong module_name: " .. tostring(c_unit.module_name))
assert(#c_unit.funcs == 1, "expected 1 func, got " .. #c_unit.funcs)
assert(#c_unit.sigs >= 1, "expected at least 1 sig, got " .. #c_unit.sigs)

local cfunc = c_unit.funcs[1]
print(string.format("C function: %s", cfunc.name.text))
print(string.format("  symbol: %s", cfunc.symbol))
print(string.format("  params: %d", #cfunc.params))
print(string.format("  locals: %d", #cfunc.locals))

-- Verify params
assert(#cfunc.params >= 2, "expected at least 2 params, got " .. #cfunc.params)

-- Verify body is CBackendBodyBlocks
local body = cfunc.body
local body_cls = asdl.classof(body)
print(string.format("  body kind: %s", tostring(body_cls)))

-- Check that it's a CBackendBodyBlocks
assert(body.entry ~= nil, "body has no entry label")
assert(body.blocks ~= nil, "body has no blocks")
assert(#body.blocks >= 1, "body has no blocks")

local blk = body.blocks[1]
print(string.format("  block label: %s", blk.label.text))
print(string.format("  block stmts: %d", #blk.stmts))
print(string.format("  block term: %s", asdl.classof(blk.term)))

-- Verify stmts exist (at least the binary op stmt)
assert(#blk.stmts >= 1, "block has no stmts")

-- Print stmt kinds
for i, stmt in ipairs(blk.stmts) do
  print(string.format("    stmt[%d]: %s", i, asdl.classof(stmt)))
end

-- Verify terminator is not nil
assert(blk.term ~= nil, "block has no terminator")
local term_cls = asdl.classof(blk.term)
assert(term_cls == C.CBackendReturn or term_cls == C.CBackendReturnVoid,
  "expected return terminator, got " .. tostring(term_cls))

----------------------------------------------------------------------
-- Test: empty module still works (allowed but produces empty unit)
----------------------------------------------------------------------

local empty_module = Code.CodeModule(
  Code.CodeModuleId("empty"),
  {}, {}, {}, {}, {},
  {},  -- no funcs
  Code.CodeOriginSource("empty")
)
local empty_result = lower_module:lower_c_module(lower_input(empty_module))
assert(asdl.classof(empty_result) == Lower.LowerCModuleEmitted)
local empty_unit = empty_result.emission.unit
assert(empty_unit ~= nil, "emit_c empty module returned nil")
assert(#empty_unit.funcs == 0, "empty module should have 0 funcs")
print("\nEmpty module: OK")

----------------------------------------------------------------------
-- Test: CBackendUnit for add function has helpers
----------------------------------------------------------------------

if #c_unit.helpers > 0 then
  print(string.format("\nHelpers: %d", #c_unit.helpers))
  for i, h in ipairs(c_unit.helpers) do
    print(string.format("  helper[%d]: %s spec=%s", i, h.id.text, asdl.classof(h.spec)))
  end
end

print("\n=== All tests passed ===")
