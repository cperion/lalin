package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local pvm = require("lalin.pvm")
local Schema = require("lalin.schema")

local T = pvm.context()
Schema(T)

local Core = T.LalinCore
local Code = T.LalinCode
local Value = T.LalinValue
local Stencil = T.LalinStencil
local Plan = require("lalin.stencil_artifact_plan")(T)
local ResidualLuaTrace = require("lalin.residual_luatrace")(T)
local MC = require("tests.code_ir.residual_mc_helper")

local i32 = Code.CodeTyInt(32, Code.CodeSigned)
local bool8 = Code.CodeTyBool8

local function iconst(raw)
    return Value.ValueExprConst(Code.CodeConstLiteral(i32, Core.LitInt(tostring(raw))))
end

local artifacts = {
    Plan.select_array_artifact(Stencil.StencilPredNonZero, {
        cond_ty = bool8,
        elem_ty = i32,
        result_ty = i32,
        step_num = 1,
    }),
    Plan.select_array_artifact(Stencil.StencilPredCompareConst(Core.CmpGt, i32, iconst(0)), {
        cond_ty = i32,
        elem_ty = i32,
        result_ty = i32,
        step_num = 1,
    }),
}

local function exercise(symbols, label)
    local mask = ffi.new("uint8_t[6]", { 1, 0, 1, 0, 0, 1 })
    local cond = ffi.new("int32_t[6]", { 5, -1, 0, 7, -3, 9 })
    local then_xs = ffi.new("int32_t[6]", { 10, 20, 30, 40, 50, 60 })
    local else_xs = ffi.new("int32_t[6]", { -10, -20, -30, -40, -50, -60 })
    local out = ffi.new("int32_t[6]")

    local select_mask = assert(symbols[artifacts[1].symbol.text], label .. " missing bool8 select")
    select_mask(out, mask, then_xs, else_xs, 0, 6)
    assert(out[0] == 10 and out[1] == -20 and out[2] == 30 and out[3] == -40 and out[4] == -50 and out[5] == 60, label .. " bool8 select")

    local select_cmp = assert(symbols[artifacts[2].symbol.text], label .. " missing compare select")
    select_cmp(out, cond, then_xs, else_xs, 0, 6)
    assert(out[0] == 10 and out[1] == -20 and out[2] == -30 and out[3] == 40 and out[4] == -50 and out[5] == 60, label .. " compare select")
end

local mc, mc_err, mc_src = MC.compile(T, artifacts, { stem = "test_stencil_select_d2" })
assert(mc ~= nil, tostring(mc_err) .. "\n" .. tostring(mc_src))
assert(mc_src:match("%?"), "MC select should emit a C conditional expression")
exercise(mc.symbols, "mc")

local bc = assert(ResidualLuaTrace.realize_artifacts(artifacts, { stem = "test_stencil_select_d2_bc" }))
exercise(bc.symbols, "bc")

assert(ResidualLuaTrace.plan_artifact(artifacts[1]).shape.kind == "apply_n", "select should lower through generic apply_n artifact shape")
assert(ResidualLuaTrace.plan_artifact(artifacts[1]).kernel_plan.predicate_plan.kind == "lua_select", "BC select should expose predicate plan")

io.write("stencil D2 select ok\n")
