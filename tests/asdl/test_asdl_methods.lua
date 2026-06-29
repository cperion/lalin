package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local asdl = require("lalin.asdl")
local Schema = require("lalin.schema")

local function new_context()
    local T = asdl.context()
    Schema(T)
    return T
end

local T1 = new_context()
local Code1 = T1.LalinCode
local Core1 = T1.LalinCore
local ty1 = Code1.CodeTyInt(32, Code1.CodeSigned)
local origin1 = Code1.CodeOriginGenerated("methods")
local param1 = Code1.CodeParam(Code1.CodeValueId("v:a"), "a", ty1, origin1)

assert(ty1:default_nil_sum_method_test() == nil)

function Code1.CodeParam:describe_test_method(ctx)
    return ctx.prefix .. ":" .. self.name
end

assert(param1:describe_test_method({ prefix = "param" }) == "param:a")

local replacement = function(self)
    return self.name .. ":replaced"
end
Code1.CodeParam.describe_test_method = replacement
assert(param1:describe_test_method({}) == "a:replaced")

local literal = Code1.CodeConstLiteral(ty1, Core1.LitInt("1"))
assert(literal:describe_test_method() == nil)

function Code1.CodeType:type_family_test_method()
    return "code-type"
end
assert(ty1:type_family_test_method() == "code-type")
assert(Code1.CodeTyInt.type_family_test_method == Code1.CodeType.type_family_test_method)

function Core1.LitNil:test_nullary_method()
    return "nil-literal"
end

assert(Core1.LitNil:test_nullary_method() == "nil-literal")
assert(T1:singleton(Core1.LitNil) == Core1.LitNil)
assert(asdl.singleton(T1, Core1.LitNil) == Core1.LitNil)

local T2 = new_context()
local Code2 = T2.LalinCode
local param2 = Code2.CodeParam(Code2.CodeValueId("v:b"), "b", Code2.CodeTyInt(32, Code2.CodeSigned), Code2.CodeOriginGenerated("methods2"))

assert(param2.describe_test_method == nil)

function Code2.CodeParam:describe_test_method(ctx)
    return ctx.prefix .. ":" .. self.name .. ":t2"
end
assert(param2:describe_test_method({ prefix = "param" }) == "param:b:t2")
assert(param1:describe_test_method({}) == "a:replaced")

print("lalin asdl methods ok")
