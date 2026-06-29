package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local asdl = require("lalin.asdl")
local Schema = require("lalin.schema")

local T = asdl.context()
Schema(T)

local Code = T.LalinCode
local Core = T.LalinCore

local i32 = Code.CodeTyInt(32, Code.CodeSigned)
local origin = Code.CodeOriginGenerated("asdl runtime")
local id = Code.CodeValueId("v:a")
local param = Code.CodeParam(id, "a", i32, origin)

assert(asdl.classof(param) == Code.CodeParam)
assert(asdl.classof("not a node") == false)
assert(asdl.classof({}) == false)

local updated = asdl.with(param, { name = "b" })
assert(asdl.classof(updated) == Code.CodeParam)
assert(updated ~= param)
assert(updated.id == param.id)
assert(updated.ty == param.ty)
assert(updated.origin == param.origin)
assert(updated.name == "b")
assert(param.name == "a")

local ok, err = pcall(function()
    param.extra = "mutated"
end)
assert(not ok)
assert(tostring(err):match("ASDL nodes are immutable"))
assert(tostring(err):match("asdl%.with"))

print("lalin asdl runtime ok")
