package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local Host = require("moonlift.mlua_run")
local moon = require("moonlift")
local pvm = require("moonlift.pvm")
local T = moon.default_session.T
local C = T.MoonCore
local Tr = T.MoonTree

local f = Host.eval([=[
local params = moon.params[[ a: i32, b: i32 ]]
return func spread_params(@{params...}): i32
    return a + b
end
]=])
assert(f.kind == "func")
assert(#f.params == 2)
assert(f.params[1].name == "a")
assert(f.params[2].name == "b")

local s = Host.eval([=[
local fields = moon.fields{ T = moon.i32 }[[ x: @{T}, y: @{T} ]]
return struct Pair
    @{fields...}
end
]=])
assert(s.kind == "struct")
assert(s.name == "Pair")
assert(#s.fields == 2)
assert(s.fields[1].name == "x")
assert(s.fields[2].name == "y")

local u = Host.eval([=[
local variants = moon.variants{ A = moon.i32 }[[ a(@{A}) | b(i64) ]]
return union U
    @{variants...}
end
]=])
assert(u.kind == "union")
assert(u.name == "U")
assert(#u.decl.variants == 2)
assert(u.decl.variants[1].name == "a")
assert(u.decl.variants[2].name == "b")

local funcs = Host.eval([[
local args = { true, 20, 22 }
local pick = func pick(cond: bool, a: i32, b: i32): i32
    return select(cond, a, b)
end
local main = func main(): i32
    return pick(@{args...})
end
return { pick = pick, main = main }
]])
local bundle = moon.bundle("spread_expr_args")
bundle:pack(funcs.pick)
bundle:pack(funcs.main)
local artifact = bundle:jit()
assert(artifact:get("main")() == 20)
artifact:free()

local stmt_arms = moon.switch_arms {
    xs = moon.switch_arms { { 1, moon.stmts[[ return 11 ]] } },
} [[
@{xs...}
]]
assert(#stmt_arms == 1)
assert(stmt_arms[1].raw_key == "1")

local expr_arms = {
    Tr.SwitchExprArm("1", {}, Tr.ExprLit(Tr.ExprSurface, C.LitInt("11"))),
}
local expr = moon.expr { arms = expr_arms } [[
switch 1 do
@{arms...}
default then
    0
end
]]
assert(pvm.classof(expr.expr) == Tr.ExprSwitch)
assert(#expr.expr.arms == 1)
assert(expr.expr.arms[1].raw_key == "1")

print("moonlift spread splice lists ok")
