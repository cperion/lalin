package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ok_mod = pcall(require, "lalin." .. "pvm")
assert(not ok_mod, "removed PVM module must not be requireable")

local lalin = require("lalin")
assert(lalin["pvm"] == nil, "removed PVM public export must be absent")
assert(lalin.asdl == require("lalin.asdl"))

print("lalin no pvm surface ok")
