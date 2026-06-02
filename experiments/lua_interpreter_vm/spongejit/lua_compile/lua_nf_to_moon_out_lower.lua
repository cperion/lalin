-- lua_nf_to_moon_out_lower.lua -- compatibility wrapper.
-- Accepted kernels are MoonCFG.Kernel; this old module name remains only while
-- public LuaCompile APIs migrate.

return require("lua_compile.lua_nf_to_moon_cfg_lower")
