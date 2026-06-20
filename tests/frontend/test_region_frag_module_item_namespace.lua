#!/usr/bin/env luajit
package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local A = require("moonlift.asdl")
local T = pvm.context()
A.Define(T)

local Pipeline = require("moonlift.frontend_pipeline").Define(T)
local Tr = T.MoonTree

local src = [[
region pass(x: i32; done(v: i32))
entry start()
    jump done(v = x)
end
end

func run(x: i32): i32
    return region: i32
    entry start()
        emit pass(x; done = out)
    end
    block out(v: i32)
        yield v
    end
    end
end
]]

local parsed = require("moonlift.parse").Define(T).parse_module(src)
local saw_frag = false
for i = 1, #parsed.module.items do
    if pvm.classof(parsed.module.items[i]) == Tr.ItemRegionFrag then saw_frag = true end
end
assert(saw_frag, "expected region fragment to be a MoonTree module item")

local result = Pipeline.parse_and_lower(src, { site = "module item fragment namespace" })
for i = 1, #result.checked.module.items do
    assert(pvm.classof(result.checked.module.items[i]) ~= Tr.ItemRegionFrag, "fragment item leaked past typecheck")
end

print("moonlift region fragment module item namespace ok")
