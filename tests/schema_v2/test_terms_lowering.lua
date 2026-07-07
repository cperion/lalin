package.path = "tests/?.lua;./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

----------------------------------------------------------------------
-- test_terms_lowering.lua
-- Verifies Phase 1: CodeTermJump, CodeTermBranch, CodeTermSwitch,
-- CodeTermVariantSwitch lower to correct CBackendTerminator variants.
----------------------------------------------------------------------

require("lalin.schema_v2")
local Code   = require("lalin.schema_v2.code")
local Core   = require("lalin.schema_v2.core")
local C      = require("lalin.schema_v2.c")
local Lower  = require("lalin.schema_v2.lower")
local asdl   = require("lalin.asdl")

-- Load impl modules
require("lalin.impl.lower_emit_c")
require("lalin.impl.lower_emit_c.code_to_c")

----------------------------------------------------------------------
-- Helper: create a minimal LowerModule for lowering context
----------------------------------------------------------------------
local function make_lower_module()
  local Backend  = require("lalin.schema_v2.backend")
  local Schedule = require("lalin.schema_v2.schedule")
  local Kernel   = require("lalin.schema_v2.kernel")
  local Flow     = require("lalin.schema_v2.flow")
  local Value    = require("lalin.schema_v2.value")
  local Mem      = require("lalin.schema_v2.mem")
  local Effect   = require("lalin.schema_v2.effect")
  local mod_id   = Code.CodeModuleId("test_terms")
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
    {}, {}, {}, {}
  )
end

----------------------------------------------------------------------
-- Helper: build a CodeModule with a single func and given term op
----------------------------------------------------------------------
local function make_term_block(id_text, name)
  local trap_op = Code.CodeTermTrap("done")
  local trap_term = Code.CodeTerm(Code.CodeTermId("trm_" .. id_text), trap_op, Code.CodeOriginSource("trap"))
  return Code.CodeBlock(
    Code.CodeBlockId(id_text), name, {}, {}, trap_term,
    Code.CodeOriginSource("blk_" .. id_text)
  )
end

local function make_module_with_term(term_op, block_params, blocks_extra, extra_params)
  local module_id = Code.CodeModuleId("test_terms_mod")
  local func_id   = Code.CodeFuncId("test_fn")
  local sig_id    = Code.CodeSigId("test_sig")

  local i32_type = Code.CodeTyInt(32, Code.CodeSigned)

  local sig = Code.CodeSig(sig_id, {}, { i32_type })

  local block_id = Code.CodeBlockId("entry")
  local value_a = Code.CodeValueId("a")
  local value_b = Code.CodeValueId("b")

  local all_params = {
    Code.CodeParam(value_a, "a", i32_type, Code.CodeOriginSource("a")),
    Code.CodeParam(value_b, "b", i32_type, Code.CodeOriginSource("b")),
  }
  if extra_params then
    for _, p in ipairs(extra_params) do all_params[#all_params + 1] = p end
  end

  local term_id = Code.CodeTermId("term_main")
  local term = Code.CodeTerm(term_id, term_op, Code.CodeOriginSource("term"))

  local block = Code.CodeBlock(block_id, "entry", block_params, {}, term, Code.CodeOriginSource("entry"))
  local blocks = { block }
  if blocks_extra then
    for _, b in ipairs(blocks_extra) do blocks[#blocks + 1] = b end
  end

  local func = Code.CodeFunc(
    func_id, "test_fn", Code.CodeLinkageExport,
    sig_id, all_params, {}, block_id,
    blocks, Code.CodeOriginSource("test_fn")
  )

  return Code.CodeModule(
    module_id,
    { sig }, {}, {}, {}, {},
    { func },
    Code.CodeOriginSource("test")
  )
end

local i32_type = Code.CodeTyInt(32, Code.CodeSigned)
local lower_module = make_lower_module()

----------------------------------------------------------------------
-- Test 1: CodeTermJump → CBackendGoto
----------------------------------------------------------------------
print("Test 1: CodeTermJump → CBackendGoto")

local target_blk = make_term_block("target", "target")

local jump_op = Code.CodeTermJump(Code.CodeBlockId("target"), {})
local mod1 = make_module_with_term(jump_op, {}, { target_blk })

local unit1 = lower_module:emit_c(mod1)
assert(unit1 ~= nil, "emit_c returned nil")
assert(#unit1.funcs == 1, "expected 1 func")

local body1 = unit1.funcs[1].body
local blk1 = body1.blocks[1]
local term1 = blk1.term
assert(asdl.classof(term1) == C.CBackendGoto,
  "expected CBackendGoto, got " .. tostring(asdl.classof(term1)))
assert(term1.dest.text == "target", "got dest=" .. term1.dest.text)
print("  PASS: CBackendGoto to 'target'")

----------------------------------------------------------------------
-- Test 2: CodeTermBranch → CBackendIfGoto
----------------------------------------------------------------------
print("Test 2: CodeTermBranch → CBackendIfGoto")

local then_blk = make_term_block("then", "then")
local else_blk = make_term_block("else_", "else_")

local cond_val = Code.CodeValueId("cond")
local cond_param = Code.CodeParam(cond_val, "cond", i32_type, Code.CodeOriginSource("cond"))

local branch_op = Code.CodeTermBranch(cond_val,
  Code.CodeBlockId("then"), { cond_val },
  Code.CodeBlockId("else_"), { cond_val })

local mod2 = make_module_with_term(branch_op, { cond_param }, { then_blk, else_blk }, { cond_param })

local unit2 = lower_module:emit_c(mod2)
assert(unit2 ~= nil)
local blk2 = unit2.funcs[1].body.blocks[1]
local term2 = blk2.term
assert(asdl.classof(term2) == C.CBackendIfGoto,
  "expected CBackendIfGoto, got " .. tostring(asdl.classof(term2)))
assert(term2.then_dest.text == "then", "got then_dest=" .. term2.then_dest.text)
assert(term2.else_dest.text == "else_", "got else_dest=" .. term2.else_dest.text)
print("  PASS: CBackendIfGoto then='then' else='else_'")

----------------------------------------------------------------------
-- Test 3: CodeTermSwitch → CBackendSwitchGoto
----------------------------------------------------------------------
print("Test 3: CodeTermSwitch → CBackendSwitchGoto")

local case1_blk = make_term_block("case1", "case1")
local case2_blk = make_term_block("case2", "case2")
local def_blk   = make_term_block("default", "default")

local switch_val = Code.CodeValueId("sw")
local sw_param = Code.CodeParam(switch_val, "sw", i32_type, Code.CodeOriginSource("sw"))

local cases = {
  Code.CodeSwitchCase(Core.LitInt("1"), Code.CodeBlockId("case1"), {}),
  Code.CodeSwitchCase(Core.LitInt("2"), Code.CodeBlockId("case2"), {}),
}

local switch_op = Code.CodeTermSwitch(switch_val, cases, Code.CodeBlockId("default"), { switch_val })

local mod3 = make_module_with_term(switch_op, { sw_param }, { case1_blk, case2_blk, def_blk }, { sw_param })

local unit3 = lower_module:emit_c(mod3)
assert(unit3 ~= nil)
local blk3 = unit3.funcs[1].body.blocks[1]
local term3 = blk3.term
assert(asdl.classof(term3) == C.CBackendSwitchGoto,
  "expected CBackendSwitchGoto, got " .. tostring(asdl.classof(term3)))
assert(#term3.cases == 2, "expected 2 cases, got " .. #term3.cases)
assert(term3.cases[1].dest.text == "case1", "case1 got " .. term3.cases[1].dest.text)
assert(term3.cases[2].dest.text == "case2", "case2 got " .. term3.cases[2].dest.text)
assert(term3.default_dest.text == "default", "default got " .. term3.default_dest.text)
print("  PASS: CBackendSwitchGoto with 2 cases + default")

----------------------------------------------------------------------
-- Test 4: CodeTermVariantSwitch → CBackendSwitchGoto
----------------------------------------------------------------------
print("Test 4: CodeTermVariantSwitch → CBackendSwitchGoto")

local vcase1_blk = make_term_block("vcase1", "vcase1")
local vcase2_blk = make_term_block("vcase2", "vcase2")
local vdef_blk   = make_term_block("vdefault", "vdefault")

local tag_val = Code.CodeValueId("tag")
local tag_param = Code.CodeParam(tag_val, "tag", i32_type, Code.CodeOriginSource("tag"))

-- Create variant refs
local owner_ty = Code.CodeTyInt(32, Code.CodeSigned)  -- placeholder
local var1 = Code.CodeVariantRef(owner_ty, "Some", 0, Code.CodeTyInt(32, Code.CodeSigned))
local var2 = Code.CodeVariantRef(owner_ty, "None", 1, nil)

local vcases = {
  Code.CodeVariantCase(var1, Code.CodeBlockId("vcase1"), {}),
  Code.CodeVariantCase(var2, Code.CodeBlockId("vcase2"), {}),
}

local vswitch_op = Code.CodeTermVariantSwitch(tag_val, vcases, Code.CodeBlockId("vdefault"), { tag_val })

local mod4 = make_module_with_term(vswitch_op, { tag_param }, { vcase1_blk, vcase2_blk, vdef_blk }, { tag_param })

local unit4 = lower_module:emit_c(mod4)
assert(unit4 ~= nil)
local blk4 = unit4.funcs[1].body.blocks[1]
local term4 = blk4.term
assert(asdl.classof(term4) == C.CBackendSwitchGoto,
  "expected CBackendSwitchGoto for variant switch, got " .. tostring(asdl.classof(term4)))
assert(#term4.cases == 2, "expected 2 variant cases, got " .. #term4.cases)
assert(term4.cases[1].dest.text == "vcase1", "vcase1 got " .. term4.cases[1].dest.text)
assert(term4.cases[2].dest.text == "vcase2", "vcase2 got " .. term4.cases[2].dest.text)
assert(term4.default_dest.text == "vdefault", "vdefault got " .. term4.default_dest.text)
print("  PASS: CBackendSwitchGoto for variant dispatch with 2 cases + default")

print("\n=== All Phase 1 terminator tests passed ===")
