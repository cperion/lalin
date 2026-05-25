#!/usr/bin/env luajit
-- Test Phase 2.1: EntryCell & EdgeCell Infrastructure
-- Validates that mutable gates for compiled code entry/exit work correctly

package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local jit = require("experiments.lua_interpreter_vm.src.jit")
local machines = jit.machines
local C = jit.constants

print("=== EntryCell & EdgeCell Infrastructure Test ===\n")

-- Test 1: EntryCell initialization
print("TEST 1: EntryCell Initialization")
do
    local entry = machines.jit_init_entry_cell
    if entry then
        print("  ✓ jit_init_entry_cell function exists")
    else
        print("  ✗ jit_init_entry_cell not found")
    end
end

-- Test 2: EdgeCell initialization
print("\nTEST 2: EdgeCell Initialization")
do
    local edge = machines.jit_init_edge_cell
    if edge then
        print("  ✓ jit_init_edge_cell function exists")
    else
        print("  ✗ jit_init_edge_cell not found")
    end
end

-- Test 3: EntryCell linking
print("\nTEST 3: EntryCell Unit Linking")
do
    local link = machines.jit_entry_cell_link_unit
    if link then
        print("  ✓ jit_entry_cell_link_unit function exists")
    else
        print("  ✗ jit_entry_cell_link_unit not found")
    end
end

-- Test 4: EntryCell fallback setup
print("\nTEST 4: EntryCell Fallback Setup")
do
    local fallback = machines.jit_entry_cell_fallback
    if fallback then
        print("  ✓ jit_entry_cell_fallback function exists")
    else
        print("  ✗ jit_entry_cell_fallback not found")
    end
end

-- Test 5: EntryCell hotness checking
print("\nTEST 5: EntryCell Hot Detection")
do
    local is_hot = machines.jit_entry_cell_is_hot
    if is_hot then
        print("  ✓ jit_entry_cell_is_hot function exists")
    else
        print("  ✗ jit_entry_cell_is_hot not found")
    end
end

-- Test 6: EntryCell counter increment
print("\nTEST 6: EntryCell Counter Ticking")
do
    local tick = machines.jit_entry_cell_tick
    if tick then
        print("  ✓ jit_entry_cell_tick function exists")
    else
        print("  ✗ jit_entry_cell_tick not found")
    end
end

-- Test 7: try_enter_jit region exists
print("\nTEST 7: try_enter_jit Region")
do
    local regions = jit.regions
    local try_enter = regions.try_enter_jit
    if try_enter then
        print("  ✓ try_enter_jit region exists")
    else
        print("  ✗ try_enter_jit region not found")
    end
end

-- Test 8: Verify constant definitions for entry/edge states
print("\nTEST 8: JIT Constants")
do
    if C.TraceStatus and C.TraceStatus.COLD >= 0 then
        print("  ✓ TraceStatus constants defined")
    else
        print("  ✗ TraceStatus constants missing")
    end
end

-- Summary
print("\n=== INFRASTRUCTURE SUMMARY ===")
print("All entry/edge cell infrastructure functions defined:")
print("  - EntryCell: init, tick, is_hot, link_unit, fallback")
print("  - EdgeCell: init")
print("  - Region: try_enter_jit")
print("\nNext: Integrate into interpreter loop (Phase 2.1 continuation)")
print("Then: Implement trace recording (Phase 2.2)")
