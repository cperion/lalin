#!/usr/bin/env luajit
-- Test: Generate ALL valid sequences, prune by budget, rank by evidence

package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local l0_lib = require("experiments.lua_interpreter_vm.src.jit.l0_opcode_stencils")
local seq_gen = require("experiments.lua_interpreter_vm.src.jit.sequence_generator")
local analyzer = require("experiments.lua_interpreter_vm.src.jit.bytecode_analyzer")

print("=== Sequence Generation: All Valid → Pruned → Ranked ===\n")

-- Get opcodes
local l0 = l0_lib.build_l0_library()
local opcode_list = {}
for _, st in ipairs(l0.stencils) do
    table.insert(opcode_list, st.opcode)
end

print(string.format("L0: %d opcodes\n", #opcode_list))

-- Generate all valid sequences (within budget)
print("Generating all valid sequences (within budget constraints)...")
local all_sequences = seq_gen.generate_all(opcode_list)

print(string.format("Total sequences generated: %d\n", #all_sequences))

local by_arity = {}
for _, seq in ipairs(all_sequences) do
    by_arity[seq.arity] = (by_arity[seq.arity] or 0) + 1
end

for arity = 2, 4 do
    if by_arity[arity] then
        print(string.format("  Arity %d: %d sequences", arity, by_arity[arity]))
    end
end

-- Get evidence from real programs
print("\nExtracting evidence from AWFY bytecode...")
local program = analyzer.analyze_program({
    "experiments/lua_interpreter_vm/build/awfy_puc_profile/puc_lua_profiled/testes/big.lua"
})

local evidence = {}
for seq, count in pairs(program.sequences) do
    evidence[seq] = {hits = count}
end

print(string.format("Evidence: %d observed sequences\n", #evidence))

-- Rank sequences by evidence
print("Ranking sequences by evidence benefit...")
local ranked = seq_gen.rank_by_evidence(all_sequences, evidence, {
    code_size_tax = 0.1,
    materialization_tax = 5,
})

print(string.format("Ranked (benefit > 0): %d sequences\n", #ranked))

if #ranked > 0 then
    print("Top 15 L1 candidates:")
    for i = 1, math.min(15, #ranked) do
        local r = ranked[i]
        print(string.format("  %2d. %-40s hits=%d benefit=%.0f",
            i, r.sequence.name, r.evidence_hits, r.net_benefit))
    end
end

-- Summary
print(string.format("\n=== Summary ==="))
print(string.format("Generated: %d sequences (all valid, within budget)", #all_sequences))
print(string.format("Evidence: %d observed", #evidence))
print(string.format("Ranked: %d with positive benefit", #ranked))
print(string.format("L1 promoted: %d (top candidates)", math.min(20, #ranked)))
