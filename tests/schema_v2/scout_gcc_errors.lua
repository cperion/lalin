#!/usr/bin/env luajit
-- Agent D / Pipeline Scout: GCC error diagnostic for emitted C
package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

require("lalin.schema_v2")
require("lalin.impl.compiler_api")
require("lalin.impl.cemit_emit")
require("lalin.impl.lower_emit_c")
require("lalin.impl.lower_emit_c.code_to_c")

local Compiler = require("lalin.schema_v2.compiler")
local Cemit    = require("lalin.schema_v2.cemit")
local C        = require("lalin.schema_v2.c")
local asdl     = require("lalin.asdl")

-- ============================================================
-- Build via CompilerSession (uses the real pipeline)
-- ============================================================
local src = [[
fn add(a [i32], b [i32]) [i32] do
  return a + b
end
]]

print("=== Step 1: Compile via CompilerSession ===")
local session = Compiler.CompilerSession(src, "test_add")
local result = session:compile()

if result == nil then
  print("ERROR: compile() returned nil")
  os.exit(1)
end
local cls = asdl.classof(result)
print("Result class: " .. tostring(cls))
if tostring(cls):match("Error") then
  print("ERROR: " .. tostring(result.message))
  os.exit(1)
end

local source = result.source
print(string.format("Emitted C source: %d bytes", #source))

-- ============================================================
-- Write emitted C to file
-- ============================================================
local c_path = "/tmp/test_add.c"
local f = io.open(c_path, "w")
f:write(source)
f:close()
print("Written to " .. c_path)

-- ============================================================
-- Print emitted C source
-- ============================================================
print("\n=== Step 2: Emitted C source ===")
print(source)
print("=== END SOURCE ===")

-- ============================================================
-- Compile with GCC
-- ============================================================
print("\n=== Step 3: GCC compilation ===")
local gcc_cmd = "gcc -c -std=c99 -Wall -Wextra " .. c_path .. " -o /tmp/test_add.o 2>&1"
local gcc_pipe = io.popen(gcc_cmd, "r")
local gcc_out = gcc_pipe:read("*a")
local gcc_ok, gcc_exit_type, gcc_exit_code = gcc_pipe:close()

print("GCC command: " .. gcc_cmd)
if gcc_out and #gcc_out > 0 then
  print("GCC output:")
  print(gcc_out)
else
  print("GCC output: (no output)")
end
print(string.format("GCC exit: ok=%s type=%s code=%s", tostring(gcc_ok), tostring(gcc_exit_type), tostring(gcc_exit_code)))

-- ============================================================
-- Step 3b: Compile with clang too for additional diagnostics
-- ============================================================
print("\n=== Step 3b: Clang compilation ===")
local clang_cmd = "clang -c -std=c99 -Wall -Wextra " .. c_path .. " -o /tmp/test_add_clang.o 2>&1"
local clang_pipe = io.popen(clang_cmd, "r")
local clang_out = clang_pipe:read("*a")
local clang_ok, clang_exit_type, clang_exit_code = clang_pipe:close()

print("Clang command: " .. clang_cmd)
if clang_out and #clang_out > 0 then
  print("Clang output:")
  print(clang_out)
else
  print("Clang output: (no output)")
end
print(string.format("Clang exit: ok=%s type=%s code=%s", tostring(clang_ok), tostring(clang_exit_type), tostring(clang_exit_code)))

-- ============================================================
-- Step 4: Inspect CBackendUnit from direct CEmit pipeline
-- ============================================================
print("\n=== Step 4: CBackendUnit inspection (via lower_emit_c) ===")

require("lalin.impl.cemit_emit")
require("lalin.impl.lower_emit_c")
require("lalin.impl.lower_emit_c.code_to_c")

local Code   = require("lalin.schema_v2.code")
local Core   = require("lalin.schema_v2.core")
local Lower  = require("lalin.schema_v2.lower")

-- Build a CodeModule the way the real pipeline does (via the frontend)
-- First, get the typechecked module from CompilerSession
local checked_module = session.mod
if checked_module then
  local mod_cls = asdl.classof(checked_module)
  print("Typechecked module class: " .. tostring(mod_cls))
  print("Typechecked module has items: " .. tostring(#checked_module.items))
end

-- Alternatively, build via LowerModule:emit_c on a handcrafted CodeModule
local function inspect_c_unit_via_emit_c()
  local Backend = require("lalin.schema_v2.backend")
  local Schedule = require("lalin.schema_v2.schedule")
  local Kernel = require("lalin.schema_v2.kernel")
  local Flow = require("lalin.schema_v2.flow")
  local Value = require("lalin.schema_v2.value")
  local Mem = require("lalin.schema_v2.mem")
  local Effect = require("lalin.schema_v2.effect")

  local mod_id = Code.CodeModuleId("scout_add")
  local i32_type = Code.CodeTyInt(32, Code.CodeSigned)
  local sig_id = Code.CodeSigId("add_sig")
  local sig = Code.CodeSig(sig_id, { i32_type, i32_type }, { i32_type })

  local value_a  = Code.CodeValueId("a")
  local value_b  = Code.CodeValueId("b")
  local value_r  = Code.CodeValueId("r")

  local param_a  = Code.CodeParam(value_a, "a", i32_type, Code.CodeOriginSource("param_a"))
  local param_b  = Code.CodeParam(value_b, "b", i32_type, Code.CodeOriginSource("param_b"))

  local int_sem  = Code.CodeIntSemantics(Code.CodeIntWrap, Code.CodeDivTrapOnZero, Code.CodeShiftMaskCount)
  local bin_op   = Code.CodeInstBinary(value_r, Core.BinAdd, i32_type, int_sem, value_a, value_b)
  local inst_add = Code.CodeInst(Code.CodeInstId("inst_add"), bin_op, Code.CodeOriginSource("add"))

  local ret_op   = Code.CodeTermReturn({ value_r })
  local term_ret = Code.CodeTerm(Code.CodeTermId("term_ret"), ret_op, Code.CodeOriginSource("ret"))

  local block_id = Code.CodeBlockId("entry")
  local block    = Code.CodeBlock(block_id, "entry", {}, { inst_add }, term_ret, Code.CodeOriginSource("entry_block"))

  local func = Code.CodeFunc(
    Code.CodeFuncId("add"), "add", Code.CodeLinkageExport,
    sig_id, { param_a, param_b }, {}, block_id,
    { block }, Code.CodeOriginSource("add_func")
  )

  local module = Code.CodeModule(
    mod_id, { sig }, {}, {}, {}, {},
    { func }, Code.CodeOriginSource("test")
  )

  -- Build minimal LowerModule
  local flow_set = Flow.FlowFactSet(mod_id, {}, {}, {}, {}, {}, {}, {}, {}, {}, {})
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
    {}, {}, {}, {}
  )

  return lower_module:emit_c(module)
end

local c_unit = inspect_c_unit_via_emit_c()
print(string.format("CBackendUnit module_name: %s", c_unit.module_name))
print(string.format("CBackendUnit funcs: %d", #c_unit.funcs))
print(string.format("CBackendUnit sigs: %d", #c_unit.sigs))
print(string.format("CBackendUnit helpers: %d", #c_unit.helpers))

print("\n--- CBackendUnit: func[1].params ---")
for i, param in ipairs(c_unit.funcs[1].params) do
  print(string.format("  param[%d] id=%s name.text=%s name_cls=%s",
    i, param.id.text, param.name.text, tostring(asdl.classof(param.name))))
end

print("\n--- CBackendUnit: func[1].locals ---")
for i, loc in ipairs(c_unit.funcs[1].locals) do
  print(string.format("  local[%d] id=%s name.text=%s name_cls=%s",
    i, loc.id.text, loc.name.text, tostring(asdl.classof(loc.name))))
end

print("\n--- CBackendUnit: func[1].body blocks ---")
local body = c_unit.funcs[1].body
print(string.format("  body class: %s", tostring(asdl.classof(body))))
print(string.format("  entry label: %s", body.entry.text))
for i, blk in ipairs(body.blocks) do
  print(string.format("  block[%d] label=%s stmts=%d term=%s",
    i, blk.label.text, #blk.stmts, tostring(asdl.classof(blk.term))))
  for j, stmt in ipairs(blk.stmts) do
    print(string.format("    stmt[%d]: %s", j, tostring(asdl.classof(stmt))))
    if asdl.classof(stmt) == C.CBackendHelperCall then
      print(string.format("      result=%s helper_id=%s", stmt.result.text, stmt.helper_id.text))
      for k, arg in ipairs(stmt.args) do
        print(string.format("      arg[%d] class=%s", k, tostring(asdl.classof(arg))))
        if asdl.classof(arg) == C.CBackendAtomLocal then
          print(string.format("        local_id.text=%s", arg.local_id.text))
        end
      end
    end
  end
end

print("\n--- CBackendUnit: helpers ---")
for i, h in ipairs(c_unit.helpers) do
  print(string.format("  helper[%d] id=%s spec_class=%s",
    i, h.id.text, tostring(asdl.classof(h.spec))))
  if asdl.classof(h.spec) == C.CBackendHelperIntBinary then
    print(string.format("    op=%s ty=%s wrap=%s",
      tostring(h.spec.op), tostring(h.spec.ty), tostring(h.spec.wrap)))
  end
end

-- ============================================================
-- Step 5: Emit C via CEmitMachine on this c_unit
-- ============================================================
print("\n=== Step 5: CEmitMachine output ===")
local target = c_unit.target

-- Build spine
local dummy_module_id = Code.CodeModuleId("scout_add")
local dummy_origin = Code.CodeOriginUnknown
local dummy_code_module = Code.CodeModule(dummy_module_id, {}, {}, {}, {}, {}, {}, dummy_origin)
local Graph = require("lalin.schema_v2.graph")
local dummy_graph = Graph.CodeGraph(dummy_module_id, {})
local spine = Lower.LowerBackSpine(dummy_code_module, dummy_graph, target)

local machine = Cemit.CEmitMachine(spine, {}, {}, {}, {})
local artifact = machine:emit_module(c_unit)

print("--- CEmitMachine source ---")
print(artifact.source)
print("--- END CEmitMachine ---")

-- Write it to a second file
local c_path2 = "/tmp/test_add_cemit.c"
local f2 = io.open(c_path2, "w")
f2:write(artifact.source)
f2:close()

-- ============================================================
-- Step 6: GCC compile the CEmitMachine output too
-- ============================================================
print("\n=== Step 6: GCC on CEmitMachine output ===")
local gcc_cmd2 = "gcc -c -std=c99 -Wall -Wextra " .. c_path2 .. " -o /tmp/test_add_cemit.o 2>&1"
local gcc_pipe2 = io.popen(gcc_cmd2, "r")
local gcc_out2 = gcc_pipe2:read("*a")
local gcc_ok2, _, gcc_code2 = gcc_pipe2:close()

print("GCC command: " .. gcc_cmd2)
if gcc_out2 and #gcc_out2 > 0 then
  print("GCC output:")
  print(gcc_out2)
else
  print("GCC output: (no output)")
end
print(string.format("GCC exit: ok=%s code=%s", tostring(gcc_ok2), tostring(gcc_code2)))

print("\n=== Scout complete ===")
