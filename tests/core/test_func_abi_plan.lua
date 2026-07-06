package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local asdl = require("lalin.asdl")
local A = require("lalin.schema_projection")
local Abi = require("lalin.func_abi_plan")

local T = asdl.context()
A(T)
local L = Abi(T)
local C = T.LalinCore
local Ty = T.LalinType
local B = T.LalinBind
local Back = T.LalinBackend

local i32 = Ty.TScalar(C.ScalarI32)
local view_i32 = Ty.TView(i32)
local void = Ty.TScalar(C.ScalarVoid)

local params = { Ty.Param("dst", view_i32), Ty.Param("n", Ty.TScalar(C.ScalarIndex)), Ty.Param("x", i32) }
local plan = L.plan("f", params, i32)
assert(asdl.classof(plan) == Ty.FuncAbiPlan)
assert(#plan.params == 3)

local dst = plan.params[1]
assert(asdl.classof(dst) == Ty.AbiParamView)
assert(dst.name == "dst")
assert(dst.data == Backend.BackValId("arg:f:dst:data"))
assert(dst.len == Backend.BackValId("arg:f:dst:len"))
assert(dst.stride == Backend.BackValId("arg:f:dst:stride"))
assert(asdl.classof(dst.binding.role) == B.BindingRoleArg)
assert(dst.binding.role.index == 0)

local n = plan.params[2]
assert(asdl.classof(n) == Ty.AbiParamScalar)
assert(n.scalar == Backend.BackIndex)
assert(n.value == Backend.BackValId("arg:f:n"))
assert(n.binding.role.index == 1)

local x = plan.params[3]
assert(asdl.classof(x) == Ty.AbiParamScalar)
assert(x.scalar == Backend.BackI32)
assert(x.binding.role.index == 2)
assert(asdl.classof(plan.result) == Ty.AbiResultScalar)
assert(plan.result.scalar == Backend.BackI32)

local void_plan = L.plan("g", {}, void)
assert(void_plan.result == Ty.AbiResultVoid)

local view_result_plan = L.plan("make", {}, view_i32)
assert(asdl.classof(view_result_plan.result) == Ty.AbiResultView)
assert(view_result_plan.result.elem == i32)
assert(view_result_plan.result.out == Backend.BackValId("arg:make:return:out"))

print("lalin func_abi_plan ok")
