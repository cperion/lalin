#!/usr/bin/env luajit
-- Test Phase 3.2 Full Pipeline: Library Loading → Selection → Closure → Indexing

package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local indexer = require("experiments.lua_interpreter_vm.src.jit.library_indexer")
local selector = require("experiments.lua_interpreter_vm.src.jit.evidence_selector")
local closer = require("experiments.lua_interpreter_vm.src.jit.closure_round_builder")

print("=== Phase 3.2: Complete Evidence-Driven Pipeline ===\n")

-- Step 1: Load Phase 1 library
print("STEP 1: Load Phase 1 Library")
local library = indexer.load_library()
print(string.format("  Loaded %d stencils (%d primitives, %d compounds)",
    #library.stencils,
    #(function()
        local prims = 0
        for _, st in ipairs(library.stencils) do
            if st.is_primitive then prims = prims + 1 end
        end
        return {} end)(),
    #(function()
        local comps = 0
        for _, st in ipairs(library.stencils) do
            if st.is_compound then comps = comps + 1 end
        end
        return {} end)()))

-- Step 2: Build runtime indexes
print("\nSTEP 2: Build Runtime Indexes")
local indexes = indexer.build_indexes(library)
local opcode_count = 0
for _ in pairs(indexes.by_first_op) do opcode_count = opcode_count + 1 end
print(string.format("  Built indexes: %d unique opcodes", opcode_count))

-- Step 3: Analyze Phase 3.1 evidence
print("\nSTEP 3: Analyze Mined Program Evidence")
local evidence = {
    ["add.int"] = {hits = 500, ops = {"add"}, guard_count = 2, exit_count = 0},
    ["load.imm"] = {hits = 800, ops = {"load"}, guard_count = 0, exit_count = 0},
    ["move.var"] = {hits = 600, ops = {"move"}, guard_count = 1, exit_count = 0},
    ["guard.int"] = {hits = 700, ops = {"guard"}, guard_count = 1, exit_count = 1},
    ["branch.test"] = {hits = 200, ops = {"branch"}, guard_count = 0, exit_count = 2},
    ["cmp.lt"] = {hits = 150, ops = {"cmp"}, guard_count = 1, exit_count = 1},
}
print(string.format("  Evidence patterns: %d", #evidence))

-- Step 4: Select stencils based on evidence
print("\nSTEP 4: Evidence-Driven Selection")
local selection_policy = {
    max_arity = 4,
    max_depth = 1,
    min_frequency = 50,
    min_benefit = 0,
}
local selected, matches = selector.select_candidates_for_evidence(evidence, indexes, selection_policy)
local frontier = selector.pareto_frontier(selected, {"net_benefit", "code_size_cost"})
print(string.format("  Candidates selected: %d", #selected))
print(string.format("  Pareto frontier: %d", #frontier))

-- Extract stencil atoms from frontier for closure
local frontier_stencils = {}
for _, scored in ipairs(frontier) do
    table.insert(frontier_stencils, scored.stencil)
end

-- For closure demonstration, use primitives (arity 1) as L0 atoms
-- In real workflow: L0 = all primitives, compose to L1, compose L1 to L2, etc.
local closure_atoms = {}
for _, st in ipairs(library.stencils) do
    if st.is_primitive or st.arity == 1 then
        table.insert(closure_atoms, st)
    end
end

-- Step 5: Generate closure candidates
print("\nSTEP 5: Generate Closure Round 1 Candidates (from L0 primitives)")
local closure_policy = {
    max_arity = 4,
    max_depth = 2,
    max_total_ops = 30,
    max_total_size = 350,
    max_holes = 20,
    max_relocs = 10,
}
local candidates = closer.generate_closure_candidates(closure_atoms, evidence, closure_policy)
print(string.format("  Generated candidates: %d", #candidates))

-- Step 6: Rank candidates by evidence relevance
print("\nSTEP 6: Rank Candidates by Evidence Relevance")
local ranked = closer.rank_candidates_by_evidence(candidates, evidence)
print(string.format("  Ranked candidates: %d", #ranked))
if #ranked > 0 then
    print("  Top 5 by potential benefit:")
    for i = 1, math.min(5, #ranked) do
        local r = ranked[i]
        print(string.format("    %d. %s: potential=%.0f, matches=%d",
            i, r.candidate.name, r.potential_benefit, r.evidence_matches))
    end
end

-- Step 7: Select top candidates for promotion
print("\nSTEP 7: Select for Promotion")
local promotion_threshold = 100  -- benefit threshold
local promoted = {}
for _, r in ipairs(ranked) do
    if r.potential_benefit >= promotion_threshold and #promoted < 10 then
        table.insert(promoted, r.candidate)
    end
end
print(string.format("  Promoted to library: %d candidates", #promoted))

-- Step 8: Build combined library for next round
print("\nSTEP 8: Build Combined Library for Next Round")
local next_round_atoms = {}
for _, st in ipairs(library.stencils) do
    table.insert(next_round_atoms, st)
end
for _, cand in ipairs(promoted) do
    table.insert(next_round_atoms, cand)
end
print(string.format("  L0 primitives: %d", #library.stencils))
print(string.format("  L1 promoted compounds: %d", #promoted))
print(string.format("  Next round atoms: %d", #next_round_atoms))

-- Step 9: Build StencilPattern library for runtime
print("\nSTEP 9: Build StencilPattern Library for Runtime")
local pattern_lib = closer.build_pattern_library(frontier_stencils)
print(string.format("  Pattern library size: %d patterns", #pattern_lib))
if #pattern_lib > 0 then
    print("  Top 5 by runtime score:")
    for i = 1, math.min(5, #pattern_lib) do
        local p = pattern_lib[i]
        print(string.format("    %d. %s (first_op=%s, score=%.0f)",
            i, p.name, p.first_op, p.score))
    end
end

-- Step 10: Summary report
print("\nSTEP 10: Summary Report")
closer.report_closure_round(1, frontier_stencils, candidates, ranked, closure_policy)

print("\n=== PHASE 3.2 PIPELINE COMPLETE ===")
print("Evidence-driven stencil selection and closure:")
print("✓ Phase 1 library loaded and indexed")
print("✓ Evidence patterns analyzed from mined programs")
print("✓ Stencils selected via Pareto frontier pruning")
print("✓ Closure round 1 candidates generated")
print("✓ Candidates ranked by evidence relevance")
print("✓ Top candidates promoted for next round")
print("✓ StencilPattern library built for runtime matching")
print("")
print("Next stages:")
print("- Round 2 closure with promoted candidates")
print("- Full hierarchy: L0 → L1 → L2 → L3")
print("- Runtime pattern matching using indexes")
print("- Materialization of selected stencils")
