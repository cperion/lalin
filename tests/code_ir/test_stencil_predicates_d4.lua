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
local f64 = Code.CodeTyFloat(64)
local bool8 = Code.CodeTyBool8

local function iconst(raw)
    return Value.ValueExprConst(Code.CodeConstLiteral(i32, Core.LitInt(tostring(raw))))
end

local nonzero_pred = Stencil.StencilPredNonZero
local cmp_gt_zero_pred = Stencil.StencilPredCompareConst(Core.CmpGt, i32, iconst(0))
local range_pred = Stencil.StencilPredRange(i32, Core.CmpGe, iconst(0), Core.CmpLe, iconst(10))
local and_pred = Stencil.StencilPredAnd({
    range_pred,
    Stencil.StencilPredNot(Stencil.StencilPredCompareConst(Core.CmpEq, i32, iconst(5))),
})
local or_pred = Stencil.StencilPredOr({
    Stencil.StencilPredCompareConst(Core.CmpLt, i32, iconst(0)),
    Stencil.StencilPredCompareConst(Core.CmpGt, i32, iconst(10)),
})
local not_pred = Stencil.StencilPredNot(Stencil.StencilPredCompareConst(Core.CmpEq, i32, iconst(5)))
local finite_pred = Stencil.StencilPredIsFinite(f64)
local nan_pred = Stencil.StencilPredIsNaN(f64)
local inf_pred = Stencil.StencilPredIsInf(f64)

local artifacts = {}
local function add(name, artifact)
    artifacts[#artifacts + 1] = artifact
    artifacts[name] = artifact
    return artifact
end

add("nonzero", Plan.compare_array_artifact(nonzero_pred, { elem_ty = i32, result_ty = bool8, step_num = 1 }))
add("cmp_gt_zero", Plan.compare_array_artifact(cmp_gt_zero_pred, { elem_ty = i32, result_ty = bool8, step_num = 1 }))
add("range", Plan.compare_array_artifact(range_pred, { elem_ty = i32, result_ty = bool8, step_num = 1 }))
add("and_pred", Plan.compare_array_artifact(and_pred, { elem_ty = i32, result_ty = bool8, step_num = 1 }))
add("or_pred", Plan.compare_array_artifact(or_pred, { elem_ty = i32, result_ty = bool8, step_num = 1 }))
add("not_pred", Plan.compare_array_artifact(not_pred, { elem_ty = i32, result_ty = bool8, step_num = 1 }))
add("finite", Plan.compare_array_artifact(finite_pred, { elem_ty = f64, result_ty = bool8, step_num = 1 }))
add("nan", Plan.compare_array_artifact(nan_pred, { elem_ty = f64, result_ty = bool8, step_num = 1 }))
add("inf", Plan.compare_array_artifact(inf_pred, { elem_ty = f64, result_ty = bool8, step_num = 1 }))

local cmp_cases = {
    { "eq", Core.CmpEq, { 0, 1, 0, 1, 0 } },
    { "ne", Core.CmpNe, { 1, 0, 1, 0, 1 } },
    { "lt", Core.CmpLt, { 1, 0, 0, 0, 1 } },
    { "le", Core.CmpLe, { 1, 1, 0, 1, 1 } },
    { "gt", Core.CmpGt, { 0, 0, 1, 0, 0 } },
    { "ge", Core.CmpGe, { 0, 1, 1, 1, 0 } },
}
for _, case in ipairs(cmp_cases) do
    add("cmp_" .. case[1], Plan.zip_compare_array_artifact(case[2], { lhs_ty = i32, rhs_ty = i32, result_ty = bool8, step_num = 1 }))
end

local function expect_u8(out, values, label)
    for i = 1, #values do
        assert(out[i - 1] == values[i], label .. " at " .. tostring(i))
    end
end

local function exercise(symbols, label)
    local xs = ffi.new("int32_t[5]", { -1, 0, 5, 10, 11 })
    local ys = ffi.new("int32_t[5]", { 0, 0, 4, 10, 12 })
    local out = ffi.new("uint8_t[5]")

    assert(symbols[artifacts.nonzero.symbol.text], label .. " missing nonzero predicate")(out, xs, 0, 5)
    expect_u8(out, { 1, 0, 1, 1, 1 }, label .. " nonzero")

    assert(symbols[artifacts.cmp_gt_zero.symbol.text], label .. " missing compare-const predicate")(out, xs, 0, 5)
    expect_u8(out, { 0, 0, 1, 1, 1 }, label .. " compare const")

    assert(symbols[artifacts.range.symbol.text], label .. " missing range predicate")(out, xs, 0, 5)
    expect_u8(out, { 0, 1, 1, 1, 0 }, label .. " range")

    assert(symbols[artifacts.and_pred.symbol.text], label .. " missing and predicate")(out, xs, 0, 5)
    expect_u8(out, { 0, 1, 0, 1, 0 }, label .. " and")

    assert(symbols[artifacts.or_pred.symbol.text], label .. " missing or predicate")(out, xs, 0, 5)
    expect_u8(out, { 1, 0, 0, 0, 1 }, label .. " or")

    assert(symbols[artifacts.not_pred.symbol.text], label .. " missing not predicate")(out, xs, 0, 5)
    expect_u8(out, { 1, 1, 0, 1, 1 }, label .. " not")

    for _, case in ipairs(cmp_cases) do
        assert(symbols[artifacts["cmp_" .. case[1]].symbol.text], label .. " missing compare op " .. case[1])(out, xs, ys, 0, 5)
        expect_u8(out, case[3], label .. " compare " .. case[1])
    end

    local inf = 1 / 0
    local nan = 0 / 0
    local fs = ffi.new("double[4]", { 0, inf, nan, -2.5 })
    local fout = ffi.new("uint8_t[4]")
    assert(symbols[artifacts.finite.symbol.text], label .. " missing finite predicate")(fout, fs, 0, 4)
    expect_u8(fout, { 1, 0, 0, 1 }, label .. " finite")

    assert(symbols[artifacts.nan.symbol.text], label .. " missing nan predicate")(fout, fs, 0, 4)
    expect_u8(fout, { 0, 0, 1, 0 }, label .. " nan")

    assert(symbols[artifacts.inf.symbol.text], label .. " missing inf predicate")(fout, fs, 0, 4)
    expect_u8(fout, { 0, 1, 0, 0 }, label .. " inf")
end

local mc, mc_err, mc_src = MC.compile(T, artifacts, { stem = "test_stencil_predicates_d4" })
assert(mc ~= nil, tostring(mc_err) .. "\n" .. tostring(mc_src))
assert(mc_src:match("isfinite"), "MC predicate source should emit float-class predicate")
exercise(mc.symbols, "mc")

local bc = assert(ResidualLuaTrace.realize_artifacts(artifacts, { stem = "test_stencil_predicates_d4_bc" }))
exercise(bc.symbols, "bc")

io.write("stencil D4 predicates ok\n")
