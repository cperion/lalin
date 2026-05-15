package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local Host = require("moonlift.mlua_run")

local f = Host.eval [[
local params = { moon.param("a", moon.i32), moon.param("b", moon.i32) }
return func spread_params(@{params...}) -> i32
    return a + b
end
]]
assert(#f.func.params == 2)
assert(f.func.params[1].name == "a")
assert(f.func.params[2].name == "b")

local Pair = Host.eval [[
local fields = { moon.field("x", moon.i32), moon.field("y", moon.i32) }
return struct Pair
    @{fields...}
end
]]
assert(Pair.decl.fields[1].field_name == "x")
assert(Pair.decl.fields[2].field_name == "y")

local U = Host.eval [[
local variants = { moon.variant("a", moon.i32), moon.variant("b", moon.i64) }
return union U
    @{variants...}
end
]]
assert(#U.decl.variants == 2)
assert(U.decl.variants[1].name == "a")
assert(U.decl.variants[2].name == "b")

local M = Host.eval [[
local args = { 20, 22 }
local add = func add(a: i32, b: i32) -> i32
    return a + b
end
local main = func main() -> i32
    return add(@{args...})
end
local M = moon.module("spread_exprs")
M:add_func(add)
M:add_func(main)
return M
]]
local compiled = M:compile()
assert(compiled:get("main")() == 42)

print("moonlift spread splice lists ok")
