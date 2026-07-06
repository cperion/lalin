package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local lalin = require("lalin")

local function shell_quote(s)
  return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local function command_ok(cmd)
  local ok = os.execute(cmd)
  return ok == true or ok == 0
end

local OP = {
  LOADK = 1,
  MOVE = 2,
  ADD = 3,
  LT = 4,
  JMP = 5,
  JMPZ = 6,
  RETURN = 11,
}

local TAG = {
  INT = 1,
  BOOL = 2,
}


local src = assert(io.open("demo/vm.lln", "r")):read("*a")
local decls = assert(lalin.loadstring(src, "@demo/vm.lln", {
  env = { OP = OP, TAG = TAG },
}))

local artifact = lalin.emit_c(decls, {
  name = "vm_demo",
  c_path = "target/vm_demo.c",
  h_path = "target/vm_demo.h",
})

print(string.format("emitted %s (%d bytes)", artifact.kind, #artifact.source))

local _, dispatch_defs = artifact.source:gsub("__lalin_region_call_VM_dispatch%f[(]", "")
assert(dispatch_defs >= 2, "VM dispatch bundle declaration/definition missing")
assert(artifact.source:match("typedef struct _Value%s*{%s*uint64_t bits"), "VM Value must stay a compact one-word tagged payload")
assert(not artifact.source:match("typedef struct _Value%s*{[^}]*int64_t%s+i"), "VM Value must not regress to separate tag/int payload fields")
assert(not artifact.source:match("__lalin_region_call_VM_decode%f[(]"), "decode must be inlined into VM dispatch bundle")
assert(artifact.source:find("semantic_address_address_fn___lalin_region_call_VM_dispatch", 1, true), "VM dispatch instruction fetch must use carried generic LowerAddressPlan state")
assert(artifact.source:find("+ ((ml_index)0) * 1 + 12", 1, true), "VM ADD fallthrough must carry instruction address by byte stride")
assert(not artifact.source:find(")[v___lalin_region_call_VM_dispatch_control_param_region_bundle_VM_dispatch_lln_emit_69_read_pc]", 1, true), "VM dispatch instruction fetch must not regress to raw indexed pc access")
for _, op_name in ipairs({ "loadk", "move", "add", "lt", "jmp", "jmpz", "ret" }) do
  assert(not artifact.source:match("__lalin_region_call_VM_op_" .. op_name .. "%f[(]"), op_name .. " op must be inlined into VM dispatch bundle")
end
for _, source_leaf in ipairs({ "MiniLoadK", "MiniAdd", "MiniWhileLt", "MiniReturn", "Compiler" }) do
  assert(not artifact.source:match("__lalin_region_call_" .. source_leaf), source_leaf .. " compiler leaf/helper must be inlined into the MiniSumProgram compiler bundle")
end
assert(not artifact.source:match("MiniStmt"), "Mini compiler must not use opcode-style source statement records")

if command_ok("command -v gcc >/dev/null 2>&1") then
  assert(command_ok("gcc -std=c99 -O3 " .. shell_quote("target/vm_demo.c") .. " -o " .. shell_quote("target/vm_demo")))
  assert(command_ok(shell_quote("target/vm_demo")))
  print("vm demo executable returned success")
end
