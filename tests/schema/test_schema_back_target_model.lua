package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local asdl = require("lalin.asdl")
local Schema = require("lalin.schema")
local Target = require("lalin.back_target_model")

local T = asdl.context()
Schema(T)

local B = T.LalinBack
local H = T.LalinHost
local api = Target(T)

local model = api.default_native()
assert(asdl.classof(model) == B.BackTargetModel)
assert(model.target == B.BackTargetNative)
assert(#model.facts > 0)

local host = api.host_target(model)
assert(asdl.classof(host) == H.HostTargetModel)
assert(host.pointer_bits == 64)
assert(host.index_bits == 64)

io.write("lalin schema_back_target_model ok\n")
