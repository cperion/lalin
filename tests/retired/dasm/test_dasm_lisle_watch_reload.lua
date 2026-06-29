package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local asdl = require("lalin.asdl")
local A2 = require("lalin.schema_projection")
local dasm_init = require("back.dasm")

local T = asdl.context()
A2(T)
local api = dasm_init(T)
local jit = api.jit()

assert(jit:watch_rules(true) == true)
assert(jit:watch_rules(false) == false)
assert(jit:reload_rules() == true)

print("dasm lisle watch/reload: ok")
