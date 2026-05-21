package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local moon = require("moonlift")

local exits = moon.exits[[ ok(i32) | err(i64) ]]
assert(exits.kind == "exit_protocol")
assert(#exits.exits == 2)

local U = moon.union{ exits = exits }[[ union Result @{exits...} end ]]
assert(#U.decl.variants == 2)
assert(U.decl.variants[1].name == "ok")
assert(U.decl.variants[2].name == "err")

local R = moon.region{ exits = exits }[[
region parse(x: i32; @{exits...})
entry start()
    jump ok(arg1 = x)
end
end
]]
assert(#R.frag.conts == 2)
assert(R.frag.conts[1].pretty_name == "ok")
assert(R.frag.conts[1].params[1].name == "arg1")

local arms = moon.switch_arms[[
case 34 then return 1
case 91 then return 2
]]
assert(#arms == 2)
assert(arms[1].raw_key == "34")
assert(arms[2].raw_key == "91")

local arms2 = moon.switch_arms { {34, moon.stmts[[ return 1 ]]}, {91, moon.stmts[[ return 2 ]]} }
assert(#arms2 == 2)
assert(arms2[1].raw_key == "34")

print("moonlift exits/switch_arms ok")
