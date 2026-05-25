#!/usr/bin/env luajit
-- Test: Exhaustive L1 Generation and Evidence-Based Pruning
-- Generate ALL valid sequences, then prune by real program evidence

package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local l0_lib = require("experiments.lua_interpreter_vm.src.jit.l0_opcode_stencils")
local exhaustive = require("experiments.lua_interpreter_vm.src.jit.exhaustive_sequence_generator")
local analyzer = require("experiments.lua_interpreter_vm.src.jit.bytecode_analyzer")

print("=== Exhaustive L1 Generation: All Valid → Evidence-Pruned ===\n")

-- Step 1: Get L0 opcodes
print("Step 1: Load L0 (Lua 5.5 opcodes)")
local l0 = l0_lib.build_l0_library()
local opcode_list = {}
for _, st in ipairs(l0.stencils) do
    table.insert(opcode_list, st.opcode)
end
print(string.format("  L0: %d opcodes\n", #opcode_list))

-- Step 2: Generate ALL valid sequences
print("Step 2: Generate ALL valid sequences (exhaustively)")
local max_arity = 4
local all_candidates = exhaustive.generate_all_valid_sequences(opcode_list, max_arity, {150, 250, 350})

print(string.format("  Generated %d candidates", #all_candidates))
local by_arity = {}
for _, cand in ipairs(all_candidates) do
    by_arity[cand.arity] = (by_arity[cand.arity] or 0) + 1
end
for arity = 2, 4 do
    if by_arity[arity] then
        print(string.format("    Arity %d: %d candidates", arity, by_arity[arity]))
    end
end

-- Step 3: Collect evidence from real programs
print("\nStep 3: Collect evidence from AWFY bytecode")
local program = analyzer.analyze_program({
    "experiments/lua_interpreter_vm/build/awfy_puc_profile/puc_lua_profiled/testes/big.lua"
})

-- Build evidence map
local evidence = {}
for seq, count in pairs(program.sequences) do
    if count >= 1 then
        evidence[seq] = {hits = count}
    end
end

print(string.format("  Evidence: %d observed sequences\n", #evidence))

-- Show top observed
local evidence_sorted = {}
for seq, ev in pairs(evidence) do
    table.insert(evidence_sorted, {seq = seq, hits = ev.hits})
end
table.sort(evidence_sorted, function(a, b) return a.hits > b.hits end)

print("  Top observed sequences:")
for i = 1, math.min(5, #evidence_sorted) do
    print(string.format("    %s: %d hits", evidence_sorted[i].seq, evidence_sorted[i].hits))
end

-- Step 4: Prune candidates by evidence
print("\nStep 4: Prune candidates to those observed in real programs")
local pruned = exhaustive.prune_by_evidence(all_candidates, evidence, {min_frequency = 1})

print(string.format("  Pruned to: %d sequences", #pruned))
if #pruned > 0 then
    print("  Examples of promoted sequences:")
    for i = 1, math.min(5, #pruned) do
        print(string.format("    %s: %d hits", pruned[i].sequence.name, pruned[i].evidence_hits))
    end
end

-- Step 5: Score for promotion
print("\nStep 5: Score remaining sequences")
local scored = exhaustive.score_for_promotion(pruned, {
    size_penalty = 0.1,
    arity_penalty = 2.0,
})

print(string.format("  Scored: %d sequences", #scored))

if #scored > 0 then
    print("\n  Top 10 L1 candidates (by promotion score):")
    for i = 1, math.min(10, #scored) do
        local s = scored[i]
        print(string.format("    %d. %s (score=%.0f, freq=%d, arity=%d)",
            i, s.sequence.name, s.score, s.evidence_hits, s.sequence.arity))
    end
end

-- Step 6: Select top for L1
print("\nStep 6: Select top candidates for L1 library")
local max_l1 = 20
local l1_promoted = {}
for i = 1, math.min(max_l1, #scored) do
    table.insert(l1_promoted, scored[i].sequence)
end

print(string.format("  Promoted %d sequences to L1\n", #l1_promoted))

if #l1_promoted > 0 then
    print("L1 Library Composition:")
    local by_arity_l1 = {}
    for _, st in ipairs(l1_promoted) do
        by_arity_l1[st.arity] = (by_arity_l1[st.arity] or 0) + 1
    end
    for arity = 2, 4 do
        if by_arity_l1[arity] then
            print(string.format("  Arity %d: %d compounds", arity, by_arity_l1[arity]))
        end
    end
end

-- Summary
print("\n=== Generation Summary ===")
print(string.format("L0: %d opcodes", #opcode_list))
print(string.format("Generated: %d ALL-VALID sequences", #all_candidates))
print(string.format("Evidence: %d observed in real programs", #evidence))
print(string.format("Pruned: %d (only those actually used)", #pruned))
print(string.format("Promoted: %d to L1", #l1_promoted))

print("\nKey insight:")
print("  Exhaustive generation finds ALL valid compositions")
print("  Evidence pruning keeps only those OBSERVED in real programs")
print("  Result: L1 is evidence-driven but complete (no missing patterns)")
