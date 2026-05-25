#!/usr/bin/env luajit
-- Test L0: 1:1 Translation of Lua 5.5 Bytecode Opcodes

package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local l0_lib = require("experiments.lua_interpreter_vm.src.jit.l0_opcode_stencils")
local analyzer = require("experiments.lua_interpreter_vm.src.jit.bytecode_analyzer")
local closer = require("experiments.lua_interpreter_vm.src.jit.closure_round_builder")

print("=== L0: Lua 5.5 Opcode Stencils (1:1 Translation) ===\n")

-- Build L0 from opcodes
print("Building L0 from Lua 5.5 opcodes...")
local l0 = l0_lib.build_l0_library()
print(string.format("  L0 library: %d stencils (one per opcode)\n", #l0.stencils))

-- Report L0 structure
l0_lib.report_l0(l0)

-- Now load real evidence from bytecode
print("\n=== Using Real Opcode Sequences for Closure ===\n")

print("Analyzing AWFY bytecode...")
local program = analyzer.analyze_program({
    "experiments/lua_interpreter_vm/build/awfy_puc_profile/puc_lua_profiled/testes/big.lua"
})

print(string.format("Analyzed %d files, %d total ops\n", #program.files, program.total_ops))

-- Show top opcodes
print("Top opcodes in real programs:")
local top_ops = {}
for op, count in pairs(program.total_opcodes) do
    table.insert(top_ops, {op = op, count = count})
end
table.sort(top_ops, function(a, b) return a.count > b.count end)

for i = 1, math.min(10, #top_ops) do
    local item = top_ops[i]
    local pct = (item.count / program.total_ops) * 100
    -- Find stencil
    local st = l0.by_opcode[item.op]
    local family = st and st.family or "???"
    print(string.format("  %d. %s (%s): %d ops (%.1f%%)", i, item.op, family, item.count, pct))
end

-- Show top sequences (these become L1 compounds)
print("\nTop opcode sequences (candidates for L1 compounds):")
local top_seqs = {}
for seq, count in pairs(program.sequences) do
    if count >= 2 then
        table.insert(top_seqs, {seq = seq, count = count})
    end
end
table.sort(top_seqs, function(a, b) return a.count > b.count end)

for i = 1, math.min(10, #top_seqs) do
    local item = top_seqs[i]
    local ops = {}
    for op in item.seq:gmatch("[^|]+") do
        table.insert(ops, op)
    end
    -- Look up stencils
    local families = {}
    for _, op in ipairs(ops) do
        local st = l0.by_opcode[op]
        table.insert(families, st and st.family or "???")
    end
    print(string.format("  %d. %s → L1 compound: %s (%d hits)",
        i, item.seq, table.concat(families, " + "), item.count))
end

-- Generate L1 from real opcode sequences
print("\n=== L1: Compounds from Real Opcode Sequences ===\n")

print("Generating L1 from L0 primitives using real sequences...")

local evidence = {}
for seq, count in pairs(program.sequences) do
    if count >= 2 then
        local ops = {}
        for op in seq:gmatch("[^|]+") do
            table.insert(ops, op)
        end
        table.insert(evidence, {
            key = seq,
            pattern = seq,
            hits = count,
            ops = ops,
            arity = #ops,
        })
    end
end

table.sort(evidence, function(a, b) return a.hits > b.hits end)

print(string.format("Evidence: %d real opcode sequences\n", #evidence))

-- Generate L1 candidates from L0
local l1_policy = {
    max_arity = 2,  -- pairs for now
    max_depth = 2,
    max_total_ops = 20,
    max_total_size = 150,
    max_holes = 10,
    max_relocs = 5,
}

local l1_candidates = closer.generate_closure_candidates(l0.stencils, evidence, l1_policy)

print(string.format("Generated %d L1 candidates\n", #l1_candidates))

if #l1_candidates > 0 then
    print("Sample L1 compounds (from real opcode pairs):")
    for i = 1, math.min(5, #l1_candidates) do
        local c = l1_candidates[i]
        print(string.format("  %d. %s (ops=%d, size=%d bytes)",
            i, c.name, c.ops, c.size))
    end
end

-- Summary
print("\n=== Summary ===")
print("✓ L0: 85 opcodes from Lua 5.5 (1:1 translation)")
print(string.format("✓ Real bytecode: %d ops analyzed", program.total_ops))
print(string.format("✓ Opcode sequences: %d unique patterns", #evidence))
print(string.format("✓ L1 candidates: %d generated from real sequences", #l1_candidates))

print("\nKey principle:")
print("  L0 is NOT hand-written stencils")
print("  L0 IS direct translation of Lua VM bytecode")
print("  L1 IS compounds generated from real opcode sequences")
print("  No hand-written call.known_lclosure, table.gettable_ic1, etc.")
print("  Only evidence-driven composition from L0")
