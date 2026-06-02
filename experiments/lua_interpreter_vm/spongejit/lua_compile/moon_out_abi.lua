-- moon_out_abi.lua -- compatibility wrapper.
-- Accepted kernels use moon_cfg_abi and have no out_tag protocol ABI.
return require("lua_compile.moon_cfg_abi")
