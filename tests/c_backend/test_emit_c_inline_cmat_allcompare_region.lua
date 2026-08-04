package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local lalin = require("lalin")

local LuaOP = { LOADK = 1, MOVE = 2, ADD = 3, LT = 4, JMP = 5, JMPZ = 6, LOADS = 7, EQ = 8, NEWTABLE = 9, SETI = 10, GETI = 12, SETS = 13, GETS = 14, RETURN = 11 }
local LuaTag = { SHIFT = 4, MASK = 15, INT = 1, NIL = 2, STRING = 3, FALSE = 4, TABLE = 5, TRUE = 20 }
local LuaErr = { EXPECT_TABLE = 101, EXPECT_INT_INDEX = 102, EXPECT_STRING_KEY = 103, INDEX_OOB = 104, HASH_FULL = 105 }

local src = assert(io.open("demo/lua_vm.lln", "r")):read("*a")
local decls = assert(lalin.loadstring(src, "@demo/lua_vm.lln", { env = { LuaOP = LuaOP, LuaTag = LuaTag, LuaErr = LuaErr } }))
local session, source = lalin.compile_c_gcc("sealed_recursive_lua_vm", decls, {
  gcc_opts = { opt = 3, out_dir = "target/test_emit_c_sealed_recursive_region" },
})

assert(source:find("LuaString_eq(", 1, true), "sealed LuaString.eq callable must be emitted")
local dispatch_start = assert(source:find("LuaVM_dispatch(", 1, true))
local dispatch_end = assert(source:find("LuaProgram_run(", dispatch_start + 1, true))
local dispatch_body = source:sub(dispatch_start, dispatch_end - 1)
assert(not dispatch_body:find("= LuaVM_dispatch(", 1, true),
  "bytecode machine transitions must not recursively consume native frames")
assert(source:find("= LuaVM_dispatch(", dispatch_end, true),
  "LuaProgram.run must invoke the sealed VM machine boundary")
assert(source:find("ml_memcmp(", 1, true),
  "LuaString.eq must materialize the memcmp all-compare predicate from declared noalias pair evidence")
local restrict_count = 0
for line in source:gmatch("[^\n]*restrict[^\n]*") do
  if line:find("lane_access_LuaString_eq", 1, true) or line:find("cursor_", 1, true) then restrict_count = restrict_count + 1 end
end
assert(restrict_count >= 4,
  "LuaString.eq byte-pointer bases/cursors must be restrict-qualified from declared noalias (found " .. restrict_count .. ")")
assert(not source:find("v_LuaString_eq_index9 == v_LuaString_eq_index11", 1, true),
  "CMat replacement must remove the baseline scalar byte predicate")
local main = assert(session:symbol("main", "int32_t (*)(void)"))
local status = tonumber(main())
assert(status == 0, "compiled Lua VM bytecode program must execute to 42 (status=" .. tostring(status) .. ")")
session:free()

print("lalin Lua VM machine executed bytecode to 42 with constant-stack dispatch and CMat memcmp all-compare")
