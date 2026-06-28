package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("lalin.pvm")
local Schema = require("lalin.schema")

local T = pvm.context()
Schema(T)

local Matrix = require("lalin.stencil_support_matrix")(T)
local InternSet = require("lalin.residual_mc_intern_set")(T)
local Bank = require("lalin.residual_mc")(T)

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

local smoke_opts = { shard_count = 1024, shard_index = 1 }
local smoke_cells = InternSet.cells(smoke_opts)
assert(#smoke_cells > 0, "MC intern smoke matrix must not be empty")
local coverage_cells = InternSet.cells()
assert(#coverage_cells > #smoke_cells, "fixed MC intern matrix must be larger than one smoke shard")

local default_profile = InternSet.bank_profile()
assert(default_profile.shape == "fixed_1x1", "default MC intern matrix should be the fixed 1x1 bank")
assert(default_profile.soac_order == 1, "fixed MC intern matrix should saturate SOAC order 1")
assert(default_profile.input_count == 1, "fixed MC intern matrix should use width 1")
assert(default_profile.cells == #coverage_cells, "fixed MC intern profile should match the emitted matrix")

local covered_vocabs = {}
local covered_layouts = {}
local covered_groups = {}
local covered_producers = {}
for _, cell in ipairs(coverage_cells) do
    assert(type(cell.name) == "string" and cell.name ~= "", "MC intern cell needs a stable name")
    local vocab = Matrix.vocabs[cell.vocab]
    assert(vocab ~= nil, "MC intern cell uses unknown vocab " .. tostring(cell.vocab))
    assert(vocab.status == Matrix.status.supported, "MC intern cell uses unsupported vocab " .. tostring(cell.vocab))
    local layout = Matrix.layouts[cell.layout]
    assert(layout ~= nil, "MC intern cell uses unknown layout " .. tostring(cell.layout))
    assert(layout.status == Matrix.status.supported, "MC intern cell uses unsupported layout " .. tostring(cell.layout))
    covered_vocabs[cell.vocab] = true
    covered_layouts[cell.layout] = true
    covered_groups[cell.group] = true
    covered_producers[cell.producer_group] = true
end

for vocab, entry in pairs(Matrix.vocabs) do
    if entry.status == Matrix.status.supported then
        assert(covered_vocabs[vocab], "supported vocab missing from MC intern matrix: " .. vocab)
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
assert(#expected_symbols == #smoke_cells, "MC intern matrix smoke cells should produce unique symbols")

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
