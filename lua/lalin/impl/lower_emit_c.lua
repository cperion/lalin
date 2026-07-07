-- impl/lower_emit_c.lua
-- Entry point: LowerModule:emit_c(code_module) → CBackendUnit
-- Ported from lower_to_c.lua lower module emission logic.

require("lalin.schema_v2")
local Lower  = require("lalin.schema_v2.lower")
local Code   = require("lalin.schema_v2.code")
local C      = require("lalin.schema_v2.c")

-- Load sub-modules for schedule forms and code-to-c conversion
require("lalin.impl.lower_emit_c.schedule_form")
require("lalin.impl.lower_emit_c.code_to_c")
require("lalin.impl.lower_emit_c.materialize")
require("lalin.impl.lower_emit_c.validate")

-----------------------------------------------------------------------
-- LowerModule:emit_c(code_module) → CBackendUnit
-----------------------------------------------------------------------

function Lower.LowerModule:emit_c(code_module)
  -- For now, return a minimal stub CBackendUnit
  -- Full implementation needs to:
  -- 1. Convert lower plan fragments to C backend structures
  -- 2. Materialize schedules and kernels
  -- 3. Generate C function signatures, types, globals, helpers
  -- 4. Validate the C backend unit

  return C.CBackendUnit(
    code_module.id.text,      -- module_name: str
    C.CBackendTarget(         -- target
      C.CBackendC99,
      C.CBackendHostedNative,
      64,                     -- pointer_bits
      64,                     -- index_bits
      C.CBackendLittleEndian,
      true                    -- allow_inline
    ),
    {},                       -- sigs
    {},                       -- types
    {},                       -- globals
    {},                       -- externs
    {},                       -- helpers
    {}                        -- funcs
  )
end
