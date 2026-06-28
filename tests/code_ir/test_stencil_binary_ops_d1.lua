package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local pvm = require("lalin.pvm")
local Schema = require("lalin.schema")

local T = pvm.context()
Schema(T)

local Code = T.LalinCode
local Stencil = T.LalinStencil
local Plan = require("lalin.stencil_artifact_plan")(T)
local ResidualLuaTrace = require("lalin.residual_luatrace")(T)
local MC = require("tests.code_ir.residual_mc_helper")

local i32 = Code.CodeTyInt(32, Code.CodeSigned)

local cases = {
    { name = "div", op = Stencil.StencilBinaryDiv, lhs = { 20, 21, 22, 23 }, rhs = { 5, 4, 3, 2 }, expect = { 4, 5, 7, 11 } },
    { name = "mod", op = Stencil.StencilBinaryMod, lhs = { 20, 21, 22, 23 }, rhs = { 5, 4, 3, 2 }, expect = { 0, 1, 1, 1 } },
    { name = "shl", op = Stencil.StencilBinaryShl, lhs = { 1, 2, 3, 4 }, rhs = { 1, 2, 3, 4 }, expect = { 2, 8, 24, 64 } },
    { name = "lshr", op = Stencil.StencilBinaryLShr, lhs = { 8, 16, 32, 64 }, rhs = { 1, 2, 3, 4 }, expect = { 4, 4, 4, 4 } },
    { name = "ashr", op = Stencil.StencilBinaryAShr, lhs = { -8, -16, 32, 64 }, rhs = { 1, 2, 3, 4 }, expect = { -4, -4, 4, 4 } },
}

local artifacts = {}
for _, case in ipairs(cases) do
    artifacts[#artifacts + 1] = Plan.zip_map_array_artifact(case.op, {
        lhs_ty = i32,
        rhs_ty = i32,
        result_ty = i32,
        step_num = 1,
    })
end

local function iarr(xs)
    return ffi.new("int32_t[?]", #xs, xs)
end

local function exercise(symbols, label)
    for i, case in ipairs(cases) do
        local lhs = iarr(case.lhs)
        local rhs = iarr(case.rhs)
        local out = ffi.new("int32_t[?]", #case.expect)
        local fn = assert(symbols[artifacts[i].symbol.text], label .. " missing " .. case.name)
        fn(out, lhs, rhs, 0, #case.expect)
        for j = 1, #case.expect do
            assert(out[j - 1] == case.expect[j], label .. " " .. case.name .. " lane " .. tostring(j))
        end
    end
end

local mc, mc_err, mc_src = MC.compile(T, artifacts, { stem = "test_stencil_binary_ops_d1" })
assert(mc ~= nil, tostring(mc_err) .. "\n" .. tostring(mc_src))
assert(mc_src:match("__builtin_trap%(%);"), "MC div/rem stencil should materialize trap guards")
assert(mc_src:match("<< __ml_s"), "MC shift-left stencil should materialize masked shift")
assert(mc_src:match(">> __ml_s"), "MC shift-right stencil should materialize masked shift")
exercise(mc.symbols, "mc")

local bc = assert(ResidualLuaTrace.realize_artifacts(artifacts, { stem = "test_stencil_binary_ops_d1_bc" }))
exercise(bc.symbols, "bc")

io.write("stencil D1 binary ops ok\n")
