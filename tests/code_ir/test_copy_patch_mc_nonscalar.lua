package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local pvm = require("lalin.pvm")
local Schema = require("lalin.schema")

local T = pvm.context()
Schema(T)

local Code = T.LalinCode
local C = T.LalinC
local Stencil = T.LalinStencil
local Ty = T.LalinType
local Plan = require("lalin.stencil_artifact_plan")(T)
local StencilBinary = require("tests.code_ir.copy_patch_mc_helper")

local i32 = Code.CodeTyInt(32, Code.CodeSigned)
local ptr_i32 = Code.CodeTyDataPtr(i32)
local named_pair = Code.CodeTyNamed("Demo", "Pair", Ty.TNamed(Ty.TypeRefGlobal("Demo", "Pair")))
local imported_pair = Code.CodeTyImportedC(C.CTypeId("Host", "HostPair"))
local slice_i32 = Code.CodeTySlice(i32)
local view_i32 = Code.CodeTyView(i32)
local byte_span = Code.CodeTyByteSpan

local artifacts = {
    ptr_copy = Plan.copy_array_artifact({ elem_ty = ptr_i32, step_num = 1 }),
    ptr_move = Plan.copy_array_artifact({ elem_ty = ptr_i32, semantics = Stencil.StencilCopyMemMove, step_num = 1 }),
    ptr_gather = Plan.gather_array_artifact({ elem_ty = ptr_i32, index_ty = i32, step_num = 1 }),
    ptr_scatter = Plan.scatter_array_artifact({ elem_ty = ptr_i32, index_ty = i32, conflicts = Stencil.StencilScatterUniqueIndices, step_num = 1 }),
    ptr_identity = Plan.map_array_artifact(Stencil.StencilUnaryIdentity, { elem_ty = ptr_i32, result_ty = ptr_i32, step_num = 1 }),
    named_copy = Plan.copy_array_artifact({ elem_ty = named_pair, semantics = Stencil.StencilCopyMemMove, step_num = 1 }),
    named_identity = Plan.map_array_artifact(Stencil.StencilUnaryIdentity, { elem_ty = named_pair, result_ty = named_pair, step_num = 1 }),
    imported_copy = Plan.copy_array_artifact({ elem_ty = imported_pair, semantics = Stencil.StencilCopyMemMove, step_num = 1 }),
    slice_copy = Plan.copy_array_artifact({ elem_ty = slice_i32, semantics = Stencil.StencilCopyMemMove, step_num = 1 }),
    slice_identity = Plan.map_array_artifact(Stencil.StencilUnaryIdentity, { elem_ty = slice_i32, result_ty = slice_i32, step_num = 1 }),
    view_copy = Plan.copy_array_artifact({ elem_ty = view_i32, semantics = Stencil.StencilCopyMemMove, step_num = 1 }),
    bytespan_copy = Plan.copy_array_artifact({ elem_ty = byte_span, semantics = Stencil.StencilCopyMemMove, step_num = 1 }),
}

local ordered = {
    artifacts.ptr_copy,
    artifacts.ptr_move,
    artifacts.ptr_gather,
    artifacts.ptr_scatter,
    artifacts.ptr_identity,
    artifacts.named_copy,
    artifacts.named_identity,
    artifacts.imported_copy,
    artifacts.slice_copy,
    artifacts.slice_identity,
    artifacts.view_copy,
    artifacts.bytespan_copy,
}

local preamble = [[
typedef struct { int32_t left; int32_t right; } Demo_Pair;
typedef struct { int32_t left; int32_t right; } HostPair;
typedef HostPair Host_HostPair;
typedef struct { int32_t* data; intptr_t len; } ml_slice_CBackendScalar_ScalarI32;
typedef struct { int32_t* data; intptr_t len; intptr_t stride; } ml_view_CBackendScalar_ScalarI32;
typedef struct { uint8_t* data; intptr_t len; } ml_bytespan;
]]

ffi.cdef([[
typedef struct { int32_t left; int32_t right; } Demo_Pair;
typedef struct { int32_t left; int32_t right; } HostPair;
typedef HostPair Host_HostPair;
typedef struct { int32_t* data; intptr_t len; } ml_slice_CBackendScalar_ScalarI32;
typedef struct { int32_t* data; intptr_t len; intptr_t stride; } ml_view_CBackendScalar_ScalarI32;
typedef struct { uint8_t* data; intptr_t len; } ml_bytespan;
]])

local build, err, src = StencilBinary.compile(T, ordered, { stem = "test_copy_patch_mc_nonscalar", preamble = preamble })
assert(build ~= nil, tostring(err) .. "\n" .. tostring(src))
assert(artifacts.ptr_copy.symbol.text ~= artifacts.named_copy.symbol.text, "non-scalar artifact symbols must include structural type identity")

local function sym(artifact)
    return assert(build.symbols[artifact.symbol.text], artifact.symbol.text)
end

local values = ffi.new("int32_t[6]", { 10, 20, 30, 40, 50, 60 })
local xs = ffi.new("int32_t *[6]")
for i = 0, 5 do xs[i] = values + i end
local cxs = ffi.cast("int32_t * const *", xs)

local out = ffi.new("int32_t *[6]")
sym(artifacts.ptr_copy)(out, cxs, 0, 6)
for i = 0, 5 do assert(out[i] == xs[i] and out[i][0] == values[i], "pointer copy") end

local overlap = ffi.new("int32_t *[7]")
for i = 0, 6 do overlap[i] = values + math.min(i, 5) end
sym(artifacts.ptr_move)(overlap + 1, ffi.cast("int32_t * const *", overlap), 0, 6)
assert(overlap[0] == values and overlap[1] == values and overlap[2] == values + 1 and overlap[3] == values + 2, "pointer memmove")

local idx = ffi.new("int32_t[6]", { 2, 0, 5, 1, 4, 3 })
sym(artifacts.ptr_gather)(out, cxs, idx, 0, 6)
assert(out[0] == xs[2] and out[1] == xs[0] and out[2] == xs[5] and out[3] == xs[1] and out[4] == xs[4] and out[5] == xs[3], "pointer gather")

for i = 0, 5 do out[i] = nil end
sym(artifacts.ptr_scatter)(out, cxs, idx, 0, 6)
assert(out[0] == xs[1] and out[1] == xs[3] and out[2] == xs[0] and out[3] == xs[5] and out[4] == xs[4] and out[5] == xs[2], "pointer scatter")

sym(artifacts.ptr_identity)(out, cxs, 0, 6)
for i = 0, 5 do assert(out[i] == xs[i], "pointer identity map") end

do
    local src_pairs = ffi.new("Demo_Pair[3]", { { 1, 10 }, { 2, 20 }, { 3, 30 } })
    local out_pairs = ffi.new("Demo_Pair[3]")
    sym(artifacts.named_copy)(out_pairs, src_pairs, 0, 3)
    for i = 0, 2 do assert(out_pairs[i].left == src_pairs[i].left and out_pairs[i].right == src_pairs[i].right, "named struct copy") end
    local out_pairs2 = ffi.new("Demo_Pair[3]")
    sym(artifacts.named_identity)(out_pairs2, src_pairs, 0, 3)
    for i = 0, 2 do assert(out_pairs2[i].left == src_pairs[i].left and out_pairs2[i].right == src_pairs[i].right, "named struct identity") end
end

do
    local src_pairs = ffi.new("HostPair[2]", { { 7, 70 }, { 8, 80 } })
    local out_pairs = ffi.new("HostPair[2]")
    sym(artifacts.imported_copy)(out_pairs, src_pairs, 0, 2)
    assert(out_pairs[0].left == 7 and out_pairs[0].right == 70 and out_pairs[1].left == 8 and out_pairs[1].right == 80, "imported C struct copy")
end

do
    local data_a = ffi.new("int32_t[3]", { 1, 2, 3 })
    local data_b = ffi.new("int32_t[3]", { 4, 5, 6 })
    local slices = ffi.new("ml_slice_CBackendScalar_ScalarI32[2]")
    slices[0].data, slices[0].len = data_a, 3
    slices[1].data, slices[1].len = data_b, 3
    local out_slices = ffi.new("ml_slice_CBackendScalar_ScalarI32[2]")
    sym(artifacts.slice_copy)(out_slices, slices, 0, 2)
    assert(out_slices[0].data == data_a and out_slices[0].len == 3 and out_slices[1].data == data_b, "slice descriptor copy")
    local out_slices2 = ffi.new("ml_slice_CBackendScalar_ScalarI32[2]")
    sym(artifacts.slice_identity)(out_slices2, slices, 0, 2)
    assert(out_slices2[0].data == data_a and out_slices2[1].data == data_b, "slice descriptor identity")

    local views = ffi.new("ml_view_CBackendScalar_ScalarI32[1]")
    views[0].data, views[0].len, views[0].stride = data_a, 3, 1
    local out_views = ffi.new("ml_view_CBackendScalar_ScalarI32[1]")
    sym(artifacts.view_copy)(out_views, views, 0, 1)
    assert(out_views[0].data == data_a and out_views[0].len == 3 and out_views[0].stride == 1, "view descriptor copy")

    local bytes = ffi.new("uint8_t[4]", { 9, 8, 7, 6 })
    local spans = ffi.new("ml_bytespan[1]")
    spans[0].data, spans[0].len = bytes, 4
    local out_spans = ffi.new("ml_bytespan[1]")
    sym(artifacts.bytespan_copy)(out_spans, spans, 0, 1)
    assert(out_spans[0].data == bytes and out_spans[0].len == 4, "byte-span descriptor copy")
end

io.write("lalin copy_patch_mc nonscalar ok\n")
