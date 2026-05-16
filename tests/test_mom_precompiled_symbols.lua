-- Test that mom binary has precompiled MOM symbols
--
-- Verifies that the mom binary successfully links the precompiled libmom_precompiled.o
-- object file by checking for key exported C ABI symbols.

local function run_command(cmd)
    local p = assert(io.popen(cmd .. " 2>&1", "r"))
    local output = p:read("*a")
    local ok, _, code = p:close()
    return ok, code, output
end

print("Checking mom binary for precompiled symbols...")

-- Check that mom binary exists
local ok, code, out = run_command("test -f target/release/mom")
assert(ok, "target/release/mom does not exist. Build it with: make mom")

-- Check for mom_compile_source_to_wire symbol (main entry point)
ok, code, out = run_command("nm -g target/release/mom | grep mom_compile_source_to_wire")
assert(ok, "mom_compile_source_to_wire symbol not found in mom binary")
print("  ✓ mom_compile_source_to_wire symbol found")

-- Check for mom_compile_source_to_object symbol
ok, code, out = run_command("nm -g target/release/mom | grep mom_compile_source_to_object")
assert(ok, "mom_compile_source_to_object symbol not found in mom binary")
print("  ✓ mom_compile_source_to_object symbol found")

-- Check for mom_compile_source_to_artifact symbol
ok, code, out = run_command("nm -g target/release/mom | grep mom_compile_source_to_artifact")
assert(ok, "mom_compile_source_to_artifact symbol not found in mom binary")
print("  ✓ mom_compile_source_to_artifact symbol found")

-- Check for mom_artifact_getpointer symbol
ok, code, out = run_command("nm -g target/release/mom | grep mom_artifact_getpointer")
assert(ok, "mom_artifact_getpointer symbol not found in mom binary")
print("  ✓ mom_artifact_getpointer symbol found")

-- Check for mom_artifact_free symbol
ok, code, out = run_command("nm -g target/release/mom | grep mom_artifact_free")
assert(ok, "mom_artifact_free symbol not found in mom binary")
print("  ✓ mom_artifact_free symbol found")

-- Check for mom_luaopen_moonlift symbol (Lua package initialization)
ok, code, out = run_command("nm -g target/release/mom | grep mom_luaopen_moonlift")
assert(ok, "mom_luaopen_moonlift symbol not found in mom binary")
print("  ✓ mom_luaopen_moonlift symbol found")

print("\n✓ All precompiled MOM symbols present in mom binary")
