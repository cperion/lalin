package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local asdl = require("lalin.asdl")
local Schema = require("lalin.schema")

local T = asdl.context()
Schema(T)

local Matrix = require("lalin.stencil_support_matrix")(T)
local InternSet = require("lalin.residual_mc_intern_set")(T)
local Bank = require("lalin.residual_mc")(T)
local Plan = require("lalin.stencil_artifact_plan")(T)
local Meta = require("lalin.stencil_metastencil")(T)
local Stencil = T.LalinStencil
local Value = T.LalinValue

local function set(xs)
    local out = {}
    for _, x in ipairs(xs or {}) do out[x] = true end
    return out
end

local function sorted_keys(t)
    local out = {}
    for k in pairs(t) do out[#out + 1] = k end
    table.sort(out)
    return out
end

local coverage_opts = { budget = { max_cells = 120000 } }
local smoke_opts = { shard_count = 1024, shard_index = 1, budget = { max_cells = 65536 } }
local smoke_cells = InternSet.cells(smoke_opts)
assert(#smoke_cells > 0, "MC intern smoke matrix must not be empty")
local coverage_cells = InternSet.cells(coverage_opts)
assert(#coverage_cells > #smoke_cells, "coverage MC intern saturation must be larger than one smoke shard")

local coverage_summary = InternSet.saturation_summary(coverage_opts)
assert(coverage_summary.budget.max_metastencil_nodes == 2, "MC intern saturation should admit two-node metastencils")
assert(coverage_summary.budget.point_input_max == 3, "MC intern saturation should stop at point arity 3")
assert(coverage_summary.budget.point_stage_max == 1, "MC intern saturation should stop at point stage 1")
assert(coverage_summary.budget.max_cells == coverage_opts.budget.max_cells, "test coverage should use an explicit cell budget")
assert(coverage_summary.composed_cells > 0, "MC intern saturation should include composed metastencil cells")
assert(coverage_summary.cells == #coverage_cells, "MC intern saturation summary should match the emitted matrix")

local function same_list(actual, expected, label)
    assert(#actual == #expected, label .. " length mismatch")
    for i = 1, #expected do
        assert(actual[i] == expected[i], label .. " mismatch at " .. tostring(i) .. ": " .. tostring(actual[i]))
    end
end

same_list(Meta.vocabulary.sink_nodes, {
    "StencilStore",
    "StencilReduce",
    "StencilScan",
    "StencilScatterReduce",
}, "metastencil sink vocabulary")
same_list(Meta.vocabulary.producers, {
    "StencilProduceRange1D",
    "StencilProduceRangeND",
    "StencilProduceWindowND",
    "StencilProduceTiledND",
}, "metastencil producer vocabulary")

local function merge_refs(out, refs)
    for name in pairs(refs or {}) do out[name] = true end
    return out
end

local function point_refs(expr)
    local cls = asdl.classof(expr)
    if cls == Stencil.StencilPointInput or cls == Stencil.StencilPointWindowInput then
        local name = expr.access.name
        if tostring(name):match("^x%d+$") then return { [name] = true } end
        return {}
    end
    if cls == Stencil.StencilPointConst then return {} end
    if cls == Stencil.StencilPointUnary or cls == Stencil.StencilPointCast or cls == Stencil.StencilPointPredicate then
        return point_refs(expr.arg)
    end
    if cls == Stencil.StencilPointBinary or cls == Stencil.StencilPointCompare then
        return merge_refs(point_refs(expr.left), point_refs(expr.right))
    end
    if cls == Stencil.StencilPointSelect then
        return merge_refs(merge_refs(point_refs(expr.cond), point_refs(expr.then_expr)), point_refs(expr.else_expr))
    end
    error("unknown point expression class " .. tostring(cls))
end

local function ref_count(refs)
    local n = 0
    for _ in pairs(refs or {}) do n = n + 1 end
    return n
end

local covered_sink_vocabs = {}
local covered_layouts = {}
local covered_groups = {}
local covered_producers = {}
local covered_result_types = {}
local same_type_reduce_variants = {}
for _, cell in ipairs(coverage_cells) do
    assert(type(cell.name) == "string" and cell.name ~= "", "MC intern cell needs a stable name")
    local vocab = Matrix.sink_vocabs[cell.vocab]
    assert(vocab ~= nil, "MC intern cell uses unknown vocab " .. tostring(cell.vocab))
    assert(vocab.status == Matrix.status.supported, "MC intern cell uses unsupported vocab " .. tostring(cell.vocab))
    local layout = Matrix.layouts[cell.layout]
    assert(layout ~= nil, "MC intern cell uses unknown layout " .. tostring(cell.layout))
    assert(layout.status == Matrix.status.supported, "MC intern cell uses unsupported layout " .. tostring(cell.layout))
    assert(ref_count(point_refs(cell.expr)) == cell.input_count, "MC intern cell point input count must match referenced inputs: " .. tostring(cell.name))
    covered_sink_vocabs[cell.vocab] = true
    covered_layouts[cell.layout] = true
    covered_groups[cell.group] = true
    covered_producers[cell.producer_group] = true
    local input_ty, result_ty = cell.name:match("%.ty_(.-)_to_(.-)%.o")
    if result_ty ~= nil then
        covered_result_types[result_ty] = true
        if cell.kind == "reduce_n" and cell.reduction ~= nil and input_ty == result_ty then
            same_type_reduce_variants[result_ty] = same_type_reduce_variants[result_ty] or {}
            same_type_reduce_variants[result_ty][cell.reduction.name] = cell
        end
    end
end

for _, ty in ipairs({ "i8", "u8", "i16", "u16", "i32", "u32", "i64", "u64", "index", "f32", "f64", "bool8" }) do
    assert(covered_result_types[ty], "MC intern saturation missing scalar result type " .. ty)
end

for _, ty in ipairs({ "i8", "u8", "i16", "u16", "i32", "u32", "i64", "u64", "index" }) do
    local variants = same_type_reduce_variants[ty] or {}
    for _, name in ipairs({ "add", "mul", "min", "max", "and", "or", "xor" }) do
        assert(variants[name] ~= nil, "MC intern saturation missing integer ReduceN " .. ty .. " " .. name)
    end
end

for _, ty in ipairs({ "f32", "f64" }) do
    local variants = same_type_reduce_variants[ty] or {}
    for _, name in ipairs({ "add", "mul", "min", "max" }) do
        assert(variants[name] ~= nil, "MC intern saturation missing float ReduceN " .. ty .. " " .. name)
    end
    assert(variants["and"] == nil and variants["or"] == nil and variants.xor == nil, "float ReduceN should not include bitwise reducers for " .. ty)
end

do
    local variants = same_type_reduce_variants.bool8 or {}
    for _, name in ipairs({ "and", "or", "xor" }) do
        assert(variants[name] ~= nil, "MC intern saturation missing bool8 ReduceN " .. name)
    end
    assert(variants.add == nil and variants.mul == nil and variants.min == nil and variants.max == nil, "bool8 ReduceN should not include numeric reducers")
end

local composed_reduce2
local composed_scan2
local composed_scatter2
local composed_stage1_arity3
local parsed_add_store
local reduce_variants = {}
local scan_variants = {}
local scatter_variants = {}
local required_cast_labels = {
    bool8_to_f32 = false,
    f32_to_u64 = false,
    f64_to_f32 = false,
    u64_to_f32 = false,
}

local function all_expected_late_cells_found()
    if composed_reduce2 == nil or composed_scan2 == nil or composed_scatter2 == nil then return false end
    if composed_stage1_arity3 == nil or parsed_add_store == nil then return false end
    for _, found in pairs(required_cast_labels) do
        if not found then return false end
    end
    for _, name in ipairs({ "add", "mul", "min", "max", "and", "or", "xor" }) do
        if reduce_variants[name] == nil or scan_variants[name] == nil or scatter_variants[name] == nil then
            return false
        end
    end
    return true
end

InternSet.each_cell({}, function(cell)
    local cast_label = cell.name:match("%.ty_(.-)%.o")
    if required_cast_labels[cast_label] == false then
        assert(InternSet.artifact_for_cell(cell) ~= nil, "MC intern saturation should materialize cast cell " .. tostring(cast_label))
        required_cast_labels[cast_label] = true
    end
    if cell.composition == "store_to_sink" and cell.kind == "reduce_n" and cell.input_count == 2 then
        composed_reduce2 = composed_reduce2 or cell
        if cell.reduction ~= nil then reduce_variants[cell.reduction.name] = reduce_variants[cell.reduction.name] or cell end
    end
    if cell.composition == "store_to_sink" and cell.kind == "scan_n" and cell.input_count == 2 then
        composed_scan2 = composed_scan2 or cell
        if cell.reduction ~= nil then scan_variants[cell.reduction.name] = scan_variants[cell.reduction.name] or cell end
    end
    if cell.composition == "store_to_sink" and cell.kind == "scatter_reduce_n" and cell.input_count == 2 then
        composed_scatter2 = composed_scatter2 or cell
        if cell.reduction ~= nil then scatter_variants[cell.reduction.name] = scatter_variants[cell.reduction.name] or cell end
    end
    if cell.composition == "store_to_sink" and cell.input_count == 3 and cell.point_stage_count == 1 then
        composed_stage1_arity3 = composed_stage1_arity3 or cell
    end
    if cell.composition == nil
        and cell.kind == "store_n"
        and cell.group == "contiguous"
        and cell.producer_group == "range1d"
        and cell.input_count == 2
        and cell.point_stage_count == 1
        and cell.expr_name == "add_x1_x2" then
        parsed_add_store = parsed_add_store or cell
    end
    return not all_expected_late_cells_found()
end)

assert(composed_reduce2 ~= nil, "MC intern saturation should compose two-input point bodies into ReduceN")
assert(composed_scan2 ~= nil, "MC intern saturation should compose two-input point bodies into ScanN")
assert(composed_scatter2 ~= nil, "MC intern saturation should compose two-input point bodies into ScatterReduceN")
assert(composed_stage1_arity3 ~= nil, "MC intern saturation should include stage-1 arity-3 composed point bodies")
assert(parsed_add_store ~= nil, "MC intern saturation should include parsed dst[i] = lhs[i] + rhs[i] StoreN")
for label, found in pairs(required_cast_labels) do
    assert(found, "MC intern saturation missing representative scalar cast " .. label)
end

local expected_reductions = {
    add = Value.ReductionAdd,
    mul = Value.ReductionMul,
    min = Value.ReductionMin,
    max = Value.ReductionMax,
    ["and"] = Value.ReductionAnd,
    ["or"] = Value.ReductionOr,
    xor = Value.ReductionXor,
}
for name, kind in pairs(expected_reductions) do
    assert(reduce_variants[name] ~= nil, "MC intern saturation missing composed ReduceN reducer " .. name)
    assert(scan_variants[name] ~= nil, "MC intern saturation missing composed ScanN reducer " .. name)
    assert(scatter_variants[name] ~= nil, "MC intern saturation missing composed ScatterReduceN reducer " .. name)

    local reduce_shape = Plan.artifact_shape(InternSet.artifact_for_cell(reduce_variants[name]))
    assert(reduce_shape.reduction == kind, "composed ReduceN materialized wrong reducer " .. name)
    local scan_shape = Plan.artifact_shape(InternSet.artifact_for_cell(scan_variants[name]))
    assert(scan_shape.reduction == kind, "composed ScanN materialized wrong reducer " .. name)
    local scatter_shape = Plan.artifact_shape(InternSet.artifact_for_cell(scatter_variants[name]))
    assert(scatter_shape.reduction == kind, "composed ScatterReduceN materialized wrong reducer " .. name)
end

local composed_reduce_artifact = InternSet.artifact_for_cell(composed_reduce2)
local composed_reduce_shape = Plan.artifact_shape(composed_reduce_artifact)
assert(composed_reduce_shape.kind == "reduce_n", "composed ReduceN cell should materialize as one ReduceN artifact")
assert(#composed_reduce_shape.inputs == 2, "composed ReduceN artifact should expose original two point inputs")

local composed_scan_artifact = InternSet.artifact_for_cell(composed_scan2)
local composed_scan_shape = Plan.artifact_shape(composed_scan_artifact)
assert(composed_scan_shape.kind == "scan_n", "composed ScanN cell should materialize as one ScanN artifact")
assert(#composed_scan_shape.inputs >= 2, "composed ScanN artifact should expose original point inputs")

local composed_scatter_artifact = InternSet.artifact_for_cell(composed_scatter2)
local composed_scatter_shape = Plan.artifact_shape(composed_scatter_artifact)
assert(composed_scatter_shape.kind == "scatter_reduce_n", "composed ScatterReduceN cell should materialize as one ScatterReduceN artifact")
assert(#composed_scatter_shape.inputs >= 3, "composed ScatterReduceN artifact should expose original point inputs plus destination index input")

for vocab, entry in pairs(Matrix.sink_vocabs) do
    if entry.status == Matrix.status.supported then
        assert(covered_sink_vocabs[vocab], "supported sink vocab missing from MC intern matrix: " .. vocab)
    end
end

for layout, entry in pairs(Matrix.layouts) do
    if entry.status == Matrix.status.supported then
        assert(covered_layouts[layout], "supported layout missing from MC intern matrix: " .. layout)
    end
end

for _, group in ipairs({
    "contiguous",
    "view",
    "slice",
    "bytespan",
    "field",
    "field_view",
    "field_slice",
    "soa",
    "soa_view",
    "soa_slice",
    "indexed_read",
    "indexed_view_read",
    "indexed_slice_read",
    "indexed_bytespan_read",
    "indexed_write",
    "indexed_view_write",
    "indexed_slice_write",
    "indexed_bytespan_write",
    "scalar_input",
}) do
    assert(covered_groups[group], "generated MC intern matrix missing layout group: " .. group)
end

for _, producer_group in ipairs({ "range1d", "range_nd2", "tiled_nd2", "window_nd1" }) do
    assert(covered_producers[producer_group], "generated MC intern matrix missing producer group: " .. producer_group)
end

local artifacts = InternSet.artifacts(smoke_opts)
assert(#artifacts == #smoke_cells, "MC intern matrix should build exactly one artifact per smoke cell")

local expected_symbols = InternSet.expected_symbols(smoke_opts)
assert(#expected_symbols > 0, "MC intern matrix should produce at least one canonical symbol")
assert(#expected_symbols <= #smoke_cells, "MC intern matrix canonical symbols should not exceed smoke cells")

local bank, err, source = Bank.build_mc_bank(artifacts, {
    stem = "test_residual_mc_intern_set",
    dir = "target/test_artifacts/test_residual_mc_intern_set",
    c_decls = InternSet.c_decls(),
    ffi_preamble = InternSet.ffi_preamble(),
})
assert(bank ~= nil, tostring(err) .. "\n" .. tostring(source))

local expected = set(expected_symbols)
local actual = {}
for _, entry in ipairs(bank.entries or {}) do actual[entry.symbol] = true end

for _, symbol in ipairs(expected_symbols) do
    assert(actual[symbol], "MC bank missing intern matrix symbol " .. symbol)
end
for _, symbol in ipairs(sorted_keys(actual)) do
    assert(expected[symbol], "MC bank produced symbol outside intern matrix " .. symbol)
end

io.write("lalin residual_mc intern set ok\n")
