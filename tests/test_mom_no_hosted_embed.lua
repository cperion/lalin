-- Test that mom binary has no embedded hosted compiler modules
--
-- Verifies that the mom binary is a clean product binary, not embedding any
-- hosted Lua compiler infrastructure (hosted TypeChecker, hosted Lua runtime, etc.)

local function run_command(cmd)
    local p = assert(io.popen(cmd .. " 2>&1", "r"))
    local output = p:read("*a")
    local ok, _, code = p:close()
    return ok, code, output
end

print("Checking mom binary for absence of hosted compiler modules...")

-- Check that mom binary exists
local ok, code, out = run_command("test -f target/release/mom")
assert(ok, "target/release/mom does not exist. Build it with: make mom")

-- Check that no hosted tree_typecheck strings are embedded
ok, code, out = run_command("strings target/release/mom | grep 'moonlift\\.tree_typecheck' || true")
local has_tree_typecheck = code == 0 and out:len() > 0 and out ~= ""
assert(not has_tree_typecheck, "mom binary contains hosted moonlift.tree_typecheck module!")
print("  ✓ No hosted moonlift.tree_typecheck module embedded")

-- Check that no hosted mlua_run strings are embedded
ok, code, out = run_command("strings target/release/mom | grep 'moonlift\\.mlua_run' || true")
local has_mlua_run = code == 0 and out:len() > 0 and out ~= ""
assert(not has_mlua_run, "mom binary contains hosted moonlift.mlua_run module!")
print("  ✓ No hosted moonlift.mlua_run module embedded")

-- Check that no hosted mom_cli strings are embedded
ok, code, out = run_command("strings target/release/mom | grep 'moonlift\\.mom_cli' || true")
local has_mom_cli = code == 0 and out:len() > 0 and out ~= ""
assert(not has_mom_cli, "mom binary contains hosted moonlift.mom_cli module!")
print("  ✓ No hosted moonlift.mom_cli module embedded")

-- Check that no hosted host_mom strings are embedded
ok, code, out = run_command("strings target/release/mom | grep 'moonlift\\.host_mom' || true")
local has_host_mom = code == 0 and out:len() > 0 and out ~= ""
assert(not has_host_mom, "mom binary contains hosted moonlift.host_mom module!")
print("  ✓ No hosted moonlift.host_mom module embedded")

print("\n✓ mom binary is clean product binary (no hosted compiler modules)")
