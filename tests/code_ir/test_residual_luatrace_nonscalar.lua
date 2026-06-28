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

local i32 = Code.CodeTyInt(32, Code.CodeSigned)
local ptr_i32 = Code.CodeTyDataPtr(i32)
local arr2_i32 = Code.CodeTyArray(i32, 2)
local slice_i32 = Code.CodeTySlice(i32)

local artifacts = {
    ptr_copy = Plan.copy_array_artifact({ elem_ty = ptr_i32, step_num = 1 }),
    ptr_gather = Plan.gather_array_artifact({ elem_ty = ptr_i32, index_ty = i32, step_num = 1 }),
    ptr_scatter = Plan.scatter_array_artifact({ elem_ty = ptr_i32, index_ty = i32, conflicts = Stencil.StencilScatterUniqueIndices, step_num = 1 }),
    ptr_identity = Plan.map_array_artifact(Stencil.StencilUnaryIdentity, { elem_ty = ptr_i32, result_ty = ptr_i32, step_num = 1 }),
    arr_copy = Plan.copy_array_artifact({ elem_ty = arr2_i32, semantics = Stencil.StencilCopyMemMove, step_num = 1 }),
    arr_identity = Plan.map_array_artifact(Stencil.StencilUnaryIdentity, { elem_ty = arr2_i32, result_ty = arr2_i32, step_num = 1 }),
    slice_copy = Plan.copy_array_artifact({ elem_ty = slice_i32, semantics = Stencil.StencilCopyMemMove, step_num = 1 }),
    slice_identity = Plan.map_array_artifact(Stencil.StencilUnaryIdentity, { elem_ty = slice_i32, result_ty = slice_i32, step_num = 1 }),
}

local ordered = {
    artifacts.ptr_copy,
    artifacts.ptr_gather,
    artifacts.ptr_scatter,
    artifacts.ptr_identity,
    artifacts.arr_copy,
    artifacts.arr_identity,
    artifacts.slice_copy,
    artifacts.slice_identity,
}

local realization = ResidualLuaTrace.realize_artifacts(ordered)
assert(realization.kind == "BCStencilBankRealization", "expected BC realization")

local function sym(artifact)
    return assert(realization.symbols[artifact.symbol.text], artifact.symbol.text)
end

do
    local values = ffi.new("int32_t[5]", { 10, 20, 30, 40, 50 })
    local src = ffi.new("int32_t *[5]")
    for i = 0, 4 do src[i] = values + i end

    local out = ffi.new("int32_t *[5]")
    sym(artifacts.ptr_copy)(out, src, 0, 5)
    for i = 0, 4 do assert(out[i] == src[i] and out[i][0] == values[i], "pointer copy") end

    local idx = ffi.new("int32_t[5]", { 2, 0, 4, 1, 3 })
    sym(artifacts.ptr_gather)(out, src, idx, 0, 5)
    assert(out[0] == src[2] and out[1] == src[0] and out[2] == src[4] and out[3] == src[1] and out[4] == src[3], "pointer gather")

    for i = 0, 4 do out[i] = nil end
    sym(artifacts.ptr_scatter)(out, src, idx, 0, 5)
    assert(out[0] == src[1] and out[1] == src[3] and out[2] == src[0] and out[3] == src[4] and out[4] == src[2], "pointer scatter")

    sym(artifacts.ptr_identity)(out, src, 0, 5)
    for i = 0, 4 do assert(out[i] == src[i], "pointer identity map") end
end

do
    local pair_arr_t = ffi.typeof("struct { int32_t v[2]; }[?]")
    local src = pair_arr_t(4)
    for i = 0, 3 do
        src[i].v[0] = i + 1
        src[i].v[1] = (i + 1) * 10
    end
    local out = pair_arr_t(4)

    sym(artifacts.arr_copy)(out, src, 0, 4)
    for i = 0, 3 do assert(out[i].v[0] == src[i].v[0] and out[i].v[1] == src[i].v[1], "array element copy") end

    local out2 = pair_arr_t(4)
    sym(artifacts.arr_identity)(out2, src, 0, 4)
    for i = 0, 3 do assert(out2[i].v[0] == src[i].v[0] and out2[i].v[1] == src[i].v[1], "array element identity map") end
end

do
    ffi.cdef([[
        typedef struct { int32_t *data; intptr_t len; } lalin_test_slice_i32;
    ]])
    local backing_a = ffi.new("int32_t[4]", { 1, 2, 3, 4 })
    local backing_b = ffi.new("int32_t[4]", { 5, 6, 7, 8 })
    local src = ffi.new("lalin_test_slice_i32[2]")
    src[0].data = backing_a
    src[0].len = 4
    src[1].data = backing_b
    src[1].len = 4
    local out = ffi.new("lalin_test_slice_i32[2]")

    sym(artifacts.slice_copy)(out, src, 0, 2)
    assert(out[0].data == backing_a and out[0].len == 4, "slice descriptor copy first")
    assert(out[1].data == backing_b and out[1].len == 4, "slice descriptor copy second")

    local out2 = ffi.new("lalin_test_slice_i32[2]")
    sym(artifacts.slice_identity)(out2, src, 0, 2)
    assert(out2[0].data == backing_a and out2[1].data == backing_b, "slice descriptor identity map")
end

local ptr_copy_plan = ResidualLuaTrace.plan_artifact(artifacts.ptr_copy)
assert(ptr_copy_plan.kernel_plan.primitive_plan.kind == "ffi_copy", "pointer copy should have byte-width primitive plan")

io.write("lalin residual_luatrace_nonscalar ok\n")
