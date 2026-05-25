#!/usr/bin/env luajit
-- Test Phase 3.1: Mine Real Lua Programs
-- Simulates running a real Lua program and mining opcode patterns

package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local jit = require("experiments.lua_interpreter_vm.src.jit")
local tracer = require("experiments.lua_interpreter_vm.src.jit.program_tracer")
local table_stencils = require("experiments.lua_interpreter_vm.src.jit.table_stencils")

print("=== Phase 3.1: Mine Real Lua Programs ===\n")

-- Simulate a typical Lua program's opcode execution pattern
print("TEST 1: Simulate Real Program Execution")
do
    local stats = tracer.new_op_stats()

    -- Simulate a loop that does table access and arithmetic
    -- for i = 1, 1000 do
    --   local t = some_table
    --   local x = t[i]
    --   local y = x + i
    --   t[i] = y
    -- end

    -- Inside loop (executed 1000 times):
    for _ = 1, 1000 do
        stats:record_op("FORLOOP")        -- 1000
        stats:record_op("GETI")           -- 1000 (t[i])
        stats:record_op("ADDK")           -- 1000 (x + 1)
        stats:record_op("SETI")           -- 1000 (t[i] = y)
    end

    -- Table construction and field access (executed less often)
    for _ = 1, 100 do
        stats:record_op("NEWTABLE")       -- 100
        stats:record_op("SETFIELD")       -- 500 (5 fields per table)
        stats:record_op("GETFIELD")       -- 200 (reading fields)
    end

    -- Function calls (executed occasionally)
    for _ = 1, 50 do
        stats:record_op("CALL")           -- 50
        stats:record_op("RETURN")         -- 50
    end

    print(string.format("  Recorded %d total operations", stats.total_ops))
    assert(stats.total_ops > 0, "No operations recorded")
    print("  ✓ Opcode execution pattern captured")
end

-- Test hot opcode detection
print("\nTEST 2: Identify Hot Opcodes")
do
    local stats = tracer.new_op_stats()

    -- Simulate loop-heavy program
    for _ = 1, 10000 do
        stats:record_op("FORLOOP")
        stats:record_op("GETI")
        stats:record_op("ADDK")
    end

    for _ = 1, 100 do
        stats:record_op("CALL")
        stats:record_op("RETURN")
    end

    local top = stats:top_ops(5)
    -- All three ops in the loop (FORLOOP, GETI, ADDK) are equally hot
    local hottest_count = top[1][2]
    assert(hottest_count > 9000, "Expected operations to be very hot")

    print("  Top 5 operations:")
    for i = 1, math.min(5, #top) do
        print(string.format("    %d. %s: %d hits", i, top[i][1], top[i][2]))
    end
    print("  ✓ Hot opcode detection working")
end

-- Test operation sequence analysis
print("\nTEST 3: Identify Hot Operation Sequences")
do
    local stats = tracer.new_op_stats()

    -- Simulate a typical loop pattern
    for _ = 1, 100 do
        stats:record_sequence({"FORLOOP", "GETI", "ADDK", "SETI"})
    end

    -- Alternative pattern
    for _ = 1, 50 do
        stats:record_sequence({"CALL", "RETURN"})
    end

    local top = stats:top_sequences(3)
    assert(#top > 0, "Expected sequences to be recorded")
    print("  Top sequences:")
    for i = 1, math.min(3, #top) do
        print(string.format("    %d. %s", i, top[i][1]))
    end
    print("  ✓ Operation sequence analysis working")
end

-- Test hot loop detection
print("\nTEST 4: Hot Loop Detection")
do
    local detector = tracer.new_hot_loop_detector(100)

    -- Simulate a loop header at PC 0x1000
    for _ = 1, 150 do
        detector:tick(0x1000)
    end

    -- Simulate another loop at PC 0x2000 (colder)
    for _ = 1, 50 do
        detector:tick(0x2000)
    end

    assert(detector:is_hot(0x1000), "Expected PC 0x1000 to be hot")
    assert(not detector:is_hot(0x2000), "Expected PC 0x2000 to be cold")

    print("  Detected hot loops:")
    print("    PC 0x1000: 150 entries (HOT)")
    print("    PC 0x2000: 50 entries (COLD)")
    print("  ✓ Hot loop detection working")
end

-- Test pattern evidence collection
print("\nTEST 5: Pattern Evidence Collection")
do
    local evidence = tracer.new_pattern_evidence()

    -- Record high-frequency patterns
    for _ = 1, 200 do
        evidence:record_pattern("FORLOOP|GETI|ADDK",
            {"FORLOOP", "GETI", "ADDK"}, 1, 3, 1)
    end

    for _ = 1, 150 do
        evidence:record_pattern("GETFIELD|ADDK",
            {"GETFIELD", "ADDK"}, 1, 2, 0)
    end

    for _ = 1, 50 do
        evidence:record_pattern("CALL|RETURN",
            {"CALL", "RETURN"}, 1, 0, 1)
    end

    local candidates = evidence:candidates_for_promotion(50)
    assert(#candidates == 3, "Expected 3 promotion candidates")
    print("  Promotion candidates (>= 50 hits):")
    for i, ev in ipairs(candidates) do
        print(string.format("    %d. %s: %d hits", i, ev.key, ev.hits))
    end
    print("  ✓ Pattern evidence collection working")
end

-- Test stencil recommendations
print("\nTEST 6: Stencil Recommendations for Real Programs")
do
    local program_evidence = {
        has_gettable = true,
        has_settable = true,
        has_call = true,
        has_forloop = true,
        has_getfield = true,
    }

    local candidates = table_stencils.candidates_for_program(program_evidence)
    print(string.format("  Recommended stencils: %d", #candidates))
    for i, c in ipairs(candidates) do
        print(string.format("    %d. %s (priority %d)", i, c.name, c.priority))
    end
    assert(#candidates > 0, "Expected stencil recommendations")
    print("  ✓ Stencil recommendations generated")
end

-- Test coverage gain estimation
print("\nTEST 7: Estimated Coverage Improvement")
do
    local program_evidence = {
        has_gettable = true,
        has_settable = false,
        has_call = true,
        has_forloop = true,
        has_getfield = true,
    }

    local gain = table_stencils.estimate_coverage_gain(program_evidence)
    print(string.format("  Current coverage: %.0f%%", gain.current_coverage * 100))
    print(string.format("  Estimated after: %.0f%%", gain.estimated_after * 100))
    assert(gain.estimated_after > gain.current_coverage,
        "Expected coverage to improve")
    print("  ✓ Coverage estimation working")
end

-- Test generation priorities
print("\nTEST 8: Stencil Generation Priorities")
do
    local recommendations = table_stencils.recommend_stencils()
    assert(#recommendations > 0, "Expected recommendations")
    print("  Top 3 priority stencils to generate:")
    for i = 1, math.min(3, #recommendations) do
        local r = recommendations[i]
        print(string.format("    %d. %s (%.0f%% coverage gain)",
            i, r.name, r.estimated_coverage_gain * 100))
    end
    print("  ✓ Generation priorities defined")
end

print("\n=== PHASE 3.1 COMPLETE ===")
print("Mining infrastructure ready:")
print("- Opcode statistics collection")
print("- Hot loop detection")
print("- Pattern evidence analysis")
print("- Stencil recommendation engine")
print("")
print("Next step (Phase 3.2):")
print("- Generate actual Moonlift code for recommended stencils")
print("- Compile to physical bytes")
print("- Add to stencil library")
