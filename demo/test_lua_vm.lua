package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local lalin = require("lalin")

local function shell_quote(s)
  return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local function command_ok(cmd)
  local ok = os.execute(cmd)
  return ok == true or ok == 0
end

local LuaOP = {
  LOADK = 1,
  MOVE = 2,
  ADD = 3,
  LT = 4,
  JMP = 5,
  JMPZ = 6,
  LOADS = 7,
  EQ = 8,
  NEWTABLE = 9,
  SETI = 10,
  GETI = 12,
  SETS = 13,
  GETS = 14,
  RETURN = 11,
}

local LuaTag = {
  SHIFT = 4,
  MASK = 15,
  INT = 1,
  NIL = 2,
  STRING = 3,
  FALSE = 4,
  TABLE = 5,
  TRUE = 20,
}

local LuaErr = {
  EXPECT_TABLE = 101,
  EXPECT_INT_INDEX = 102,
  EXPECT_STRING_KEY = 103,
  INDEX_OOB = 104,
  HASH_FULL = 105,
}

local src = assert(io.open("demo/lua_vm.lln", "r")):read("*a")
local decls = assert(lalin.loadstring(src, "@demo/lua_vm.lln", {
  env = { LuaOP = LuaOP, LuaTag = LuaTag, LuaErr = LuaErr },
}))

local artifact = lalin.emit_c(decls, {
  name = "lua_vm_m3",
  c_path = "target/lua_vm_m3.c",
  h_path = "target/lua_vm_m3.h",
})

print(string.format("emitted %s (%d bytes)", artifact.kind, #artifact.source))

local _, dispatch_defs = artifact.source:gsub("__lalin_region_call_LuaVM_dispatch%f[(]", "")
assert(dispatch_defs >= 2, "LuaVM dispatch bundle declaration/definition missing")
assert(artifact.source:match("__lalin_region_call_LuaString_eq%f[(]"), "LuaString.eq sealed helper missing")
assert(artifact.source:match("= __lalin_region_call_LuaString_eq%f[(]"), "LuaVM EQ must call sealed LuaString.eq instead of open-splicing it into the bundle")
assert(artifact.source:match("typedef struct _LuaValue%s*{%s*uint64_t bits"), "LuaValue must stay a compact one-word tagged payload")
assert(artifact.source:find("semantic_address_address_fn___lalin_region_call_LuaVM_dispatch", 1, true), "LuaVM dispatch instruction fetch must use carried generic LowerAddressPlan state")
assert(artifact.source:find("+ ((ml_index)0) * 1 + 12", 1, true), "LuaVM ADD fallthrough must carry instruction address by byte stride")
assert(not artifact.source:find(")[v___lalin_region_call_LuaVM_dispatch_control_param_region_bundle_LuaVM_dispatch___bundle_entry_LuaVM_dispatch_pc]", 1, true), "LuaVM dispatch instruction fetch must not regress to raw indexed pc access")
for _, helper in ipairs({ "loadk", "move", "loads", "eq", "newtable", "seti", "geti", "sets", "gets", "add", "lt", "jmp", "jmpz", "ret" }) do
  assert(not artifact.source:match("__lalin_region_call_LuaVM_op_" .. helper .. "%f[(]"), "unexpected LuaVM op helper " .. helper)
end

if command_ok("command -v gcc >/dev/null 2>&1") then
  assert(command_ok("gcc -std=c99 -O3 " .. shell_quote("target/lua_vm_m3.c") .. " -o " .. shell_quote("target/lua_vm_m3")))
  assert(command_ok(shell_quote("target/lua_vm_m3")))
  print("lua vm m3 executable returned success")
end
