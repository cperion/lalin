#!/usr/bin/env luajit
package.path = "./experiments/lua_interpreter_vm/spongejit/?.lua;./experiments/lua_interpreter_vm/spongejit/?/init.lua;./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local Collect = require("lua_compile.lua_src_window_collect")
local Recognize = require("lua_compile.lua_src_to_lua_region_recognize")
local Validate = require("lua_compile.lua_region_validate")

local w = Collect.collect({ { op="FORPREP", pc=1, a=4, bx=2 }, { op="LOADI", pc=2, a=8, b=1 }, { op="FORLOOP", pc=4, a=4, bx=3 } })
local rs = Recognize.recognize(w)
assert(#rs.regions == 1)
local r = rs.regions[1]
assert(r.kind == "NumericFor")
assert(r.slots.first.id == 4 and r.slots.last.id == 7)
assert(#r.edges == 4)
local ok, errs = Validate.validate(rs)
assert(ok, table.concat(errs, "\n"))
print("ok - SpongeJIT LuaCompile LuaRegion")
