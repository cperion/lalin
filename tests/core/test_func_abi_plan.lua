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
local index = Ty.TScalar(C.ScalarIndex)
local view_i32 = Ty.TView(i32)
local pair = Ty.TNamed(Ty.TypeRefGlobal("Demo", "Pair"))
local array_i32 = Ty.TArray(Ty.ArrayLenConst(4), i32)
local slice_i32 = Ty.TSlice(i32)
local void = Ty.TScalar(C.ScalarVoid)

local params = {
    Ty.Param("x", i32),
    Ty.Param("n", index),
    Ty.Param("dst", view_i32),
    Ty.Param("pair", pair),
    Ty.Param("items", array_i32),
    Ty.Param("slice", slice_i32),
}
local plan = L.plan("f", params, i32)
assert(asdl.classof(plan) == Ty.FuncAbiPlan)
assert(plan.func_name == "f")
assert(#plan.params == 6)

local x = plan.params[1]
assert(asdl.classof(x) == Ty.AbiParamScalar)
assert(x.name == "x")
assert(x.scalar == Back.BackI32)
assert(x.value == Back.BackValId("arg:f:x"))
assert(x.value.text == "arg:f:x")
assert(x.binding.ty == i32)
assert(asdl.classof(x.binding.role) == B.BindingRoleArg)
assert(x.binding.role.index == 0)

local n = plan.params[2]
assert(asdl.classof(n) == Ty.AbiParamScalar)
assert(n.name == "n")
assert(n.scalar == Back.BackIndex)
assert(n.value == Back.BackValId("arg:f:n"))
assert(n.value.text == "arg:f:n")
assert(n.binding.ty == index)
assert(asdl.classof(n.binding.role) == B.BindingRoleArg)
assert(n.binding.role.index == 1)

local dst = plan.params[3]
assert(asdl.classof(dst) == Ty.AbiParamView)
assert(dst.name == "dst")
assert(dst.data == Back.BackValId("arg:f:dst:data"))
assert(dst.data.text == "arg:f:dst:data")
assert(dst.len == Back.BackValId("arg:f:dst:len"))
assert(dst.len.text == "arg:f:dst:len")
assert(dst.stride == Back.BackValId("arg:f:dst:stride"))
assert(dst.stride.text == "arg:f:dst:stride")
assert(dst.binding.ty == view_i32)
assert(asdl.classof(dst.binding.role) == B.BindingRoleArg)
assert(dst.binding.role.index == 2)

local pair_param = plan.params[4]
assert(asdl.classof(pair_param) == Ty.AbiParamScalar)
assert(pair_param.name == "pair")
assert(pair_param.scalar == Back.BackPtr)
assert(pair_param.value == Back.BackValId("arg:f:pair"))
assert(pair_param.value.text == "arg:f:pair")
assert(pair_param.binding.ty == pair)
assert(asdl.classof(pair_param.binding.role) == B.BindingRoleArg)
assert(pair_param.binding.role.index == 3)

local array_param = plan.params[5]
assert(asdl.classof(array_param) == Ty.AbiParamScalar)
assert(array_param.name == "items")
assert(array_param.scalar == Back.BackPtr)
assert(array_param.value == Back.BackValId("arg:f:items"))
assert(array_param.value.text == "arg:f:items")
assert(array_param.binding.ty == array_i32)
assert(asdl.classof(array_param.binding.role) == B.BindingRoleArg)
assert(array_param.binding.role.index == 4)

local rejected_param = plan.params[6]
assert(asdl.classof(rejected_param) == Ty.AbiParamRejected)
assert(rejected_param.name == "slice")
assert(rejected_param.ty == slice_i32)
assert(rejected_param.reason == "parameter type has no direct executable ABI yet")

assert(asdl.classof(plan.result) == Ty.AbiResultScalar)
assert(plan.result.scalar == Back.BackI32)

local void_plan = L.plan("g", {}, void)
assert(void_plan.result == Ty.AbiResultVoid)

local view_result_plan = L.plan("make", {}, view_i32)
assert(asdl.classof(view_result_plan.result) == Ty.AbiResultView)
assert(view_result_plan.result.elem == i32)
assert(view_result_plan.result.out == Back.BackValId("arg:make:return:out"))
assert(view_result_plan.result.out.text == "arg:make:return:out")

local rejected_result_plan = L.plan("bad", {}, pair)
assert(asdl.classof(rejected_result_plan.result) == Ty.AbiResultRejected)
assert(rejected_result_plan.result.ty == pair)
assert(rejected_result_plan.result.reason == "result type has no direct executable ABI yet")

print("lalin func_abi_plan ok")
