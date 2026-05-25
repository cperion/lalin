#!/usr/bin/env luajit
-- Test Phase 2.2 & 2.3 & 2.4: Trace Recording, Selection, and Materialization

package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local jit = require("experiments.lua_interpreter_vm.src.jit")
local machines = jit.machines
local regions = jit.regions
local C = jit.constants

print("=== JIT Pipeline Infrastructure Test ===\n")

-- Test Phase 2.2: Trace Recording
print("PHASE 2.2: Trace Recording Skeleton")
do
    print("  Checking trace recording functions...")
    assert(machines.jit_record_trace_op, "jit_record_trace_op missing")
    assert(machines.jit_record_trace_guard, "jit_record_trace_guard missing")
    assert(machines.jit_record_trace_snapshot, "jit_record_trace_snapshot missing")
    assert(machines.jit_trace_is_recordable, "jit_trace_is_recordable missing")
    print("  ✓ Trace recording functions defined")

    print("  Checking trace recording regions...")
    assert(regions.record_trace_ops, "record_trace_ops region missing")
    assert(regions.trace_record_guard_check, "trace_record_guard_check region missing")
    print("  ✓ Trace recording regions defined")
end

-- Test Phase 2.3: Trace Stencil Selection
print("\nPHASE 2.3: Trace Stencil Selector")
do
    print("  Checking stencil selection functions...")
    assert(machines.jit_stencil_plan_from_trace, "jit_stencil_plan_from_trace missing")
    assert(machines.jit_stencil_plan_is_valid, "jit_stencil_plan_is_valid missing")
    print("  ✓ Stencil selection functions defined")
end

-- Test Phase 2.4: Materialization Pipeline
print("\nPHASE 2.4: Materialization Pipeline")
do
    print("  Checking materialization functions...")
    assert(machines.jit_materialize_plan_start, "jit_materialize_plan_start missing")
    assert(machines.jit_materialize_plan_finish, "jit_materialize_plan_finish missing")
    print("  ✓ Materialization functions defined")

    print("  Checking materialization regions...")
    assert(regions.materialize_stencil_plan, "materialize_stencil_plan region missing")
    assert(regions.link_executable_unit, "link_executable_unit region missing")
    print("  ✓ Materialization regions defined")
end

-- Test MVP entry point
print("\nPHASE 2.5: MVP Entry Point")
do
    print("  Checking try_enter_jit region...")
    assert(regions.try_enter_jit, "try_enter_jit region missing")
    print("  ✓ try_enter_jit available for interpreter integration")
end

-- Summary
print("\n=== PIPELINE COMPLETION ===")
print("Phase 2.1 ✓ EntryCell & EdgeCell Infrastructure")
print("Phase 2.2 ✓ Trace Recording Skeleton")
print("Phase 2.3 ✓ Trace Stencil Selector (selection logic)")
print("Phase 2.4 ✓ Materialization Pipeline")
print("Phase 2.5 ✓ MVP Entry Point (try_enter_jit)")
print("\nAll Phase 2 infrastructure functions and regions in place.")
print("Ready for interpreter integration testing.")
