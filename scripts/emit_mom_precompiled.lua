-- Emit MOM precompiled object file
--
-- This must be run through the moonlift binary:
--   ./target/release/moonlift scripts/emit_mom_precompiled.lua
--
-- Loads all MOM compiler modules via build.assemble, combines them into a single
-- unified module, and emits to a single relocatable object file.

package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local output_path = os.getenv("MOM_OBJ_PATH") or "target/libmom_precompiled.o"

-- Ensure output directory exists
local output_dir = output_path:gsub("/[^/]+$", "")
if output_dir ~= "" then
    os.execute("mkdir -p " .. output_dir)
end

print("Loading MOM build assembler...")
local Assemble = require("moonlift.mom.build.assemble")

print("Assembling all MOM compiler modules into unified module...")
local artifact = Assemble.emit_object({
    name = "mom",
    module_name = "libmom_precompiled",
})

print("Writing: " .. output_path)
artifact:write(output_path)

print("\n✓ Success: MOM modules compiled to precompiled object")
print("  " .. output_path)
