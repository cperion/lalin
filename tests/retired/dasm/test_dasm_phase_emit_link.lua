package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local asdl = require("lalin.asdl")
local A2 = require("lalin.schema_projection")
local E = require("back.dasm.phases.emit_dynasm")
local L = require("back.dasm.phases.link_encode")
local Mx = require("back.dasm.model")

local T = asdl.context()
A2(T)
Mx.set_context(T)
local D = T.LalinDasm

local payload = E.run({
    D.DFragment(0, {}, string.char(0x90)),
    D.DFragment(1, {}, string.char(0xC3)),
})

assert(asdl.classof(payload) == D.DEmitPlan)
assert(#payload.fragments == 2)

local linked = L.run(payload)
assert(asdl.classof(linked) == D.DEmitPlan)
assert(#linked.fragments == #payload.fragments)

print("dasm phase emit/link: ok")
