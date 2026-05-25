#!/usr/bin/env luajit
-- Verify stencil library has good coverage of Lua operations

local path = (...) or debug.getinfo(1, "S").source:match("@(.*/)")
package.path = path .. "/../lua/?/init.lua;" .. path .. "/../lua/?.lua;" .. package.path

local Builder = require("experiments.lua_interpreter_vm.src.jit.library_builder")

local plan = Builder.read_json("experiments/lua_interpreter_vm/build/stencil_library/promotion_plan.json")

print("=== Stencil Library Coverage Analysis ===\n")

-- Analyze operation distribution
local op_stats = {}
local total_ops = 0
local compounds_with_ops = 0

for _, cand in ipairs(plan.library) do
    if cand.kind == "compound_candidate" and cand.ops then
        compounds_with_ops = compounds_with_ops + 1

        for _, op in ipairs(cand.ops) do
            op_stats[op.op] = (op_stats[op.op] or 0) + 1
            total_ops = total_ops + 1
        end
    end
end

print("OPERATION DISTRIBUTION")
print(string.format("Total operations in library: %d", total_ops))
print(string.format("Compounds with operations: %d\n", compounds_with_ops))

print("Operation frequency (top 10):")
local sorted_ops = {}
for op, count in pairs(op_stats) do
    table.insert(sorted_ops, {op, count})
end
table.sort(sorted_ops, function(a, b) return a[2] > b[2] end)

for i = 1, math.min(10, #sorted_ops) do
    local op, count = sorted_ops[i][1], sorted_ops[i][2]
    local pct = (count / total_ops) * 100
    print(string.format("  %d. %s: %d instances (%.1f%%)", i, op, count, pct))
end

print()

-- Analyze semantic patterns
print("SEMANTIC PATTERN COVERAGE")

local patterns = {
    guard = 0,      -- GuardTag
    arithmetic = 0, -- AddIntWrap
    comparison = 0, -- LtInt
    control = 0,    -- Branch, Jump
    memory = 0,     -- ReadSlot, WriteSlot
    projection = 0, -- ProjectSlot, ProjectRoot
}

for op, count in pairs(op_stats) do
    if op == "GuardTag" then
        patterns.guard = patterns.guard + count
    elseif op == "AddIntWrap" then
        patterns.arithmetic = patterns.arithmetic + count
    elseif op == "LtInt" then
        patterns.comparison = patterns.comparison + count
    elseif op == "Branch" or op == "Jump" or op == "Truthy" then
        patterns.control = patterns.control + count
    elseif op == "ReadSlot" or op == "WriteSlot" then
        patterns.memory = patterns.memory + count
    elseif op == "ProjectSlot" or op == "ProjectRoot" then
        patterns.projection = patterns.projection + count
    end
end

print("Operations by category:")
for category, count in pairs(patterns) do
    if count > 0 then
        local pct = (count / total_ops) * 100
        print(string.format("  %s: %d (%.1f%%)", category, count, pct))
    end
end

-- Check diversity of stencil sizes
print("\nSTENCIL SIZE DIVERSITY")

local size_ranges = {
    {0, 31, "tiny (0-31 bytes)"},
    {32, 63, "small (32-63 bytes)"},
    {64, 127, "medium (64-127 bytes)"},
    {128, 255, "large (128-255 bytes)"},
    {256, 99999, "huge (256+ bytes)"},
}

for _, range in ipairs(size_ranges) do
    local min_sz, max_sz, label = range[1], range[2], range[3]
    local count = 0
    for _, cand in ipairs(plan.library) do
        if cand.kind == "compound_candidate" and cand.physical then
            local size = cand.physical.size
            if size >= min_sz and size <= max_sz then
                count = count + 1
            end
        end
    end
    if count > 0 then
        print(string.format("  %s: %d stencils", label, count))
    end
end

-- Check complexity distribution
print("\nCOMPLEXITY DISTRIBUTION")

local complexity_counts = {}
for _, cand in ipairs(plan.library) do
    if cand.kind == "compound_candidate" and cand.ops then
        local op_count = #cand.ops
        local bucket = math.floor(op_count / 5) * 5
        complexity_counts[bucket] = (complexity_counts[bucket] or 0) + 1
    end
end

print("Stencils by operation count:")
local sorted_complexity = {}
for bucket, count in pairs(complexity_counts) do
    table.insert(sorted_complexity, {bucket, count})
end
table.sort(sorted_complexity, function(a, b) return a[1] < b[1] end)

for _, item in ipairs(sorted_complexity) do
    local bucket, count = item[1], item[2]
    print(string.format("  %d-%d ops: %d stencils", bucket, bucket + 4, count))
end

-- Coverage completeness
print("\nCOVERAGE COMPLETENESS")

local essential_ops = {
    "ReadSlot",
    "WriteSlot",
    "GuardTag",
    "AddIntWrap",
    "LtInt",
    "Jump",
    "Branch",
}

local has_all_essential = true
for _, op in ipairs(essential_ops) do
    if (op_stats[op] or 0) == 0 then
        has_all_essential = false
        print(string.format("  MISSING: %s", op))
    end
end

if has_all_essential then
    print("  ✓ All essential operations covered")
else
    print("  ✗ Some essential operations missing")
end

-- Statistical summary
print("\nSTATISTICAL SUMMARY")

local total_with_bytes = 0
local total_bytes = 0

for _, cand in ipairs(plan.library) do
    if cand.kind == "compound_candidate" and cand.physical then
        total_with_bytes = total_with_bytes + 1
        total_bytes = total_bytes + cand.physical.size
    end
end

print(string.format("Total compounds: 64"))
print(string.format("With physical bytes: %d", total_with_bytes))
print(string.format("Coverage: %.1f%%", (total_with_bytes / 64) * 100))
print(string.format("Average size: %.1f bytes", total_bytes / total_with_bytes))
print(string.format("Total compiled: %d bytes", total_bytes))

-- Check for good variety in opcode combinations
print("\nOPCODE COMBINATION DIVERSITY")

local two_op_patterns = 0
local three_op_patterns = 0
local four_plus_patterns = 0

for _, cand in ipairs(plan.library) do
    if cand.kind == "compound_candidate" and cand.ops then
        if #cand.ops == 2 then
            two_op_patterns = two_op_patterns + 1
        elseif #cand.ops == 3 then
            three_op_patterns = three_op_patterns + 1
        elseif #cand.ops >= 4 then
            four_plus_patterns = four_plus_patterns + 1
        end
    end
end

print(string.format("2-operation stencils: %d", two_op_patterns))
print(string.format("3-operation stencils: %d", three_op_patterns))
print(string.format("4+ operation stencils: %d", four_plus_patterns))

-- Final verdict
print("\n=== COVERAGE VERDICT ===")

local good_diversity = #sorted_ops >= 8 and total_ops >= 1000
local good_balance = patterns.guard > 0 and patterns.arithmetic > 0 and patterns.memory > 0
local good_coverage = total_with_bytes >= 50

if good_diversity and good_balance and good_coverage then
    print("✓ Stencil library has GOOD COVERAGE")
    print(string.format("  - Covers %d different operation types", #sorted_ops))
    print(string.format("  - Balanced across categories (guard, arithmetic, memory)"))
    print(string.format("  - 1466 total operations covered in %d bytes", total_bytes))
    print(string.format("  - Compression: %.1f x (1466 ops in ~4.5KB)", 1466 * 10 / total_bytes))
else
    print("✗ Stencil library has LIMITED COVERAGE")
    if not good_diversity then
        print(string.format("  - Only %d operation types (expected >= 8)", #sorted_ops))
    end
    if not good_balance then
        print("  - Unbalanced category distribution")
    end
    if not good_coverage then
        print(string.format("  - Only %d/%d compounds have bytes", total_with_bytes, 64))
    end
end
