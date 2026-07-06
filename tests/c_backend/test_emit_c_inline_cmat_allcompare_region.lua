package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local lalin = require("lalin")

local LuaOP = { LOADK = 1, MOVE = 2, ADD = 3, LT = 4, JMP = 5, JMPZ = 6, LOADS = 7, EQ = 8, NEWTABLE = 9, SETI = 10, GETI = 12, SETS = 13, GETS = 14, RETURN = 11 }
local LuaTag = { SHIFT = 4, MASK = 15, INT = 1, NIL = 2, STRING = 3, FALSE = 4, TABLE = 5, TRUE = 20 }
local LuaErr = { EXPECT_TABLE = 101, EXPECT_INT_INDEX = 102, EXPECT_STRING_KEY = 103, INDEX_OOB = 104, HASH_FULL = 105 }

local src = assert(io.open("demo/lua_vm.lln", "r")):read("*a")
local decls = assert(lalin.loadstring(src, "@demo/lua_vm.lln", { env = { LuaOP = LuaOP, LuaTag = LuaTag, LuaErr = LuaErr } }))
local artifact = lalin.emit_c(decls, {
  name = "inline_cmat_allcompare_region",
  c_path = "target/test_emit_c_inline_cmat_allcompare_region/lua_vm.c",
  h_path = "target/test_emit_c_inline_cmat_allcompare_region/lua_vm.h",
})

assert(artifact.source:find("semantic scalar CMat kernel kernel:loop___lalin_region_call_LuaString_eq", 1, true), "LuaString.eq byte loop must lower through inline CMat")
assert(artifact.source:find("v___lalin_region_call_LuaString_eq_field10[v___lalin_region_call_LuaString_eq_control_param_region_seal_LuaString_eq_loop_i] == v___lalin_region_call_LuaString_eq_field12[v___lalin_region_call_LuaString_eq_control_param_region_seal_LuaString_eq_loop_i]", 1, true), "LuaString.eq all-compare sink must emit the byte predicate")

print("lalin emit_c inline CMat all-compare region ok")
