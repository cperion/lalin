-- run55_native: the public Native CPS Frame V2 facade.
--
-- `run` enters the invocation-owned V2 machine (cps_invocation_v2). LuaJIT
-- stages prototype plans and immutable RX arenas, then leaves the
-- recurrence. The legacy C-stack runner, the V1 poly/learner machinery, and
-- the V1 function table have been retired from this module: the V2
-- dependency closure contains no V1 runner, V1 poly sections, or learner
-- fallback. Historical V1 learner banks/tests remain as isolated fixtures
-- that no public V2 module imports, links, or dispatches to.

local ffi = require("ffi")

local function run(source, opts)
    return require("experiments.copy_patch_cps.lua55_trace.cps_invocation_v2")
        .run(source, opts)
end

return {
    run = run,
    ffi = ffi,
}
