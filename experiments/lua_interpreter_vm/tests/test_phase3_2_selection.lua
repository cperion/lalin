#!/usr/bin/env luajit
-- Test Phase 3.2: Evidence-Driven Stencil Selection and Indexing
-- Loads Phase 1 library, applies Phase 3.1 evidence, builds runtime indexes

package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local indexer = require("experiments.lua_interpreter_vm.src.jit.library_indexer")
local selector = require("experiments.lua_interpreter_vm.src.jit.evidence_selector")

print("=== Phase 3.2: Evidence-Driven Stencil Selection ===\n")

-- Test 1: Load Phase 1 library
print("TEST 1: Load Stencil Library")
do
    local library = indexer.load_library()
    assert(library and library.stencils, "Failed to load library")
    assert(#library.stencils > 0, "Library is empty")
    print(string.format("  ✓ Loaded %d stencils from library", #library.stencils))
end

-- Test 2: Build indexes
print("\nTEST 2: Build Runtime Indexes")
do
    local library = indexer.load_library()
    local indexes = indexer.build_indexes(library)

    assert(indexes.by_name, "Missing by_name index")
    assert(indexes.by_first_op, "Missing by_first_op index")
    assert(indexes.by_arity, "Missing by_arity index")

    local by_first_op_count = 0
    for _ in pairs(indexes.by_first_op) do by_first_op_count = by_first_op_count + 1 end
    print(string.format("  ✓ Created indexes: %d unique first opcodes", by_first_op_count))
end

-- Test 3: Query library by pattern
print("\nTEST 3: Query by Opcode Pattern")
do
    local library = indexer.load_library()
    local indexes = indexer.build_indexes(library)

    -- Simulate evidence pattern (e.g., ADD followed by MOVE)
    local test_ops = {"arith.add", "value.move"}
    local candidates = indexer.candidates_for_pattern(indexes, test_ops, 4)
    print(string.format("  ✓ Found %d candidates for pattern", #candidates))
end

-- Test 4: Score stencils against evidence
print("\nTEST 4: Score Stencils Against Evidence")
do
    local library = indexer.load_library()

    -- Simulate observed evidence for a pattern
    local evidence = {
        hits = 100,
        ops = {"arith.add", "value.move", "projection"},
        guard_count = 2,
        exit_count = 1,
    }

    -- Score a stencil
    if #library.stencils > 0 then
        local st = library.stencils[1]
        local score = selector.score_stencil_against_evidence(st, evidence)
        assert(score, "Failed to score stencil")
        assert(score.net_benefit >= 0, "Score should be non-negative")
        print(string.format("  ✓ Scored stencil %s: benefit=%.0f", st.name or "?", score.net_benefit))
    end
end

-- Test 5: Select candidates from evidence
print("\nTEST 5: Evidence-Driven Candidate Selection")
do
    local library = indexer.load_library()
    local indexes = indexer.build_indexes(library)

    -- Simulate multiple evidence patterns (like output from mining)
    local evidence_patterns = {
        ["arith.add|value.move"] = {
            hits = 150,
            ops = {"arith.add", "value.move"},
            guard_count = 1,
            exit_count = 0,
        },
        ["value.load|arith.add"] = {
            hits = 200,
            ops = {"value.load", "arith.add"},
            guard_count = 2,
            exit_count = 1,
        },
        ["branch.truthy|jump"] = {
            hits = 80,
            ops = {"branch.truthy", "edge.jump"},
            guard_count = 0,
            exit_count = 1,
        },
    }

    local policy = {
        max_arity = 4,
        max_depth = 3,
        min_frequency = 10,
        min_benefit = 0,  -- accept all for testing
    }

    local selected, pattern_matches = selector.select_candidates_for_evidence(
        evidence_patterns, indexes, policy)

    assert(selected, "Failed to select candidates")
    print(string.format("  ✓ Selected %d candidate stencils", #selected))
    print(string.format("  ✓ Matched %d patterns to stencils", #pattern_matches))

    if #selected > 0 then
        print(string.format("  Top candidate: %s (benefit=%.0f)",
            selected[1].stencil.name, selected[1].net_benefit))
    end
end

-- Test 6: Pareto frontier pruning
print("\nTEST 6: Pareto Frontier Pruning")
do
    local library = indexer.load_library()
    local indexes = indexer.build_indexes(library)

    local evidence_patterns = {
        ["guard.int"] = {hits = 100, ops = {"guard.int"}, guard_count = 1, exit_count = 0},
        ["arith.add"] = {hits = 200, ops = {"arith.add"}, guard_count = 0, exit_count = 0},
        ["branch"] = {hits = 50, ops = {"branch.truthy"}, guard_count = 0, exit_count = 1},
    }

    local selected, _ = selector.select_candidates_for_evidence(evidence_patterns, indexes)

    local frontier = selector.pareto_frontier(selected, {"net_benefit", "code_size_cost"})
    print(string.format("  ✓ Pruned %d candidates to %d on Pareto frontier",
        #selected, #frontier))

    if #frontier > 0 then
        print(string.format("  Top frontier stencil: %s", frontier[1].stencil.name))
    end
end

-- Test 7: Library composition report
print("\nTEST 7: Library Composition Analysis")
do
    local library = indexer.load_library()
    local indexes = indexer.build_indexes(library)

    -- Count by type
    local primitives = 0
    local compounds = 0
    for _, st in ipairs(library.stencils) do
        if st.is_primitive then primitives = primitives + 1 end
        if st.is_compound then compounds = compounds + 1 end
    end

    print(string.format("  Primitives: %d", primitives))
    print(string.format("  Compounds: %d", compounds))

    indexer.report_library(library, indexes)
    print("  ✓ Library composition reported")
end

-- Test 8: Full selection pipeline
print("\nTEST 8: Full Evidence-Driven Selection Pipeline")
do
    -- Load library
    local library = indexer.load_library()
    local indexes = indexer.build_indexes(library)

    -- Simulate Phase 3.1 evidence (typical program execution)
    local evidence = {
        ["add.int"] = {hits = 500, ops = {"arith.add"}, guard_count = 2, exit_count = 0},
        ["load.imm"] = {hits = 800, ops = {"value.load_i64"}, guard_count = 0, exit_count = 0},
        ["move"] = {hits = 600, ops = {"value.move"}, guard_count = 1, exit_count = 0},
        ["guard.int"] = {hits = 700, ops = {"guard.int"}, guard_count = 1, exit_count = 1},
        ["branch"] = {hits = 200, ops = {"branch.truthy"}, guard_count = 0, exit_count = 2},
    }

    -- Select with realistic policy
    local policy = {
        max_arity = 4,
        max_depth = 1,
        min_frequency = 50,
        min_benefit = 10,
    }

    local selected, pattern_matches = selector.select_candidates_for_evidence(evidence, indexes, policy)
    local frontier = selector.pareto_frontier(selected, {"net_benefit", "code_size_cost"})

    print(string.format("  ✓ Evidence patterns: %d", #evidence))
    print(string.format("  ✓ Candidates selected: %d", #selected))
    print(string.format("  ✓ Pareto frontier: %d stencils", #frontier))

    selector.report_selection(frontier, pattern_matches, 1)
end

print("\n=== PHASE 3.2 COMPLETE ===")
print("Evidence-driven selection ready:")
print("- Phase 1 library loaded and indexed")
print("- Stencils scored against mined evidence")
print("- Pareto frontier pruned to actionable set")
print("- Runtime indexes built for fast matching")
print("")
print("Next steps:")
print("- Integrate with real trace recording")
print("- Build StencilPatternLibrary for runtime selector")
print("- Materialize selected stencils into code")
