-- Phase 3.2: Table Operation Stencils
-- Generates Moonlift stencils for table access operations

local moon = require("moonlift")
local host = require("moonlift.host")

local M = {}

-- Metadata for table operation stencils
M.TableOperations = {
    GETTABLE = {
        name = "table.gettable_generic",
        description = "Generic table get with type guard",
        hotspot = true,
        variants = {
            "gettable_array_i64",     -- array access with integer key
            "gettable_hash_string",   -- hash table access with string key
            "gettable_shape_ic",      -- inline-cached shape lookup
        }
    },
    SETTABLE = {
        name = "table.settable_generic",
        description = "Generic table set with write barrier",
        hotspot = true,
        variants = {
            "settable_array_i64",
            "settable_hash_string",
            "settable_shape_ic",
        }
    },
    GETI = {
        name = "table.geti_array",
        description = "Integer-indexed array access",
        hotspot = true,
        variants = {
            "geti_array_bounds",      -- with bounds check
            "geti_array_unchecked",   -- fast path, no check
        }
    },
    GETFIELD = {
        name = "table.getfield_generic",
        description = "String field lookup in table",
        hotspot = true,
        variants = {
            "getfield_shape",         -- shape-based fast path
            "getfield_hash",          -- hash table lookup
        }
    },
    SETFIELD = {
        name = "table.setfield_generic",
        description = "String field assignment",
        hotspot = true,
        variants = {
            "setfield_shape",
            "setfield_hash",
        }
    }
}

-- Call operation stencils
M.CallOperations = {
    CALL = {
        name = "call.generic",
        description = "Function call with type dispatch",
        hotspot = true,
        variants = {
            "call_lclosure",          -- known Lua closure
            "call_cclosure",          -- known C function
            "call_monomorphic",       -- single observed target
        }
    },
    RETURN = {
        name = "call.return",
        description = "Return from function",
        hotspot = true,
    }
}

-- Loop operation stencils
M.LoopOperations = {
    FORLOOP = {
        name = "loop.forloop_generic",
        description = "Numeric for-loop iteration",
        hotspot = true,
        variants = {
            "forloop_i64_positive",   -- positive step, integer
            "forloop_f64_positive",   -- positive step, float
            "forloop_any",            -- generic numeric
        }
    },
    JFORPREP = {
        name = "loop.forprep",
        description = "For-loop initialization",
        hotspot = false,
    }
}

-- Generate candidate stencil names for real programs
function M.candidates_for_program(program_evidence)
    local candidates = {}

    -- If we see GETTABLE hotspot, add table access stencils
    if program_evidence.has_gettable then
        table.insert(candidates, {
            kind = "table_access",
            name = "table.gettable_array_i64_ic1",
            description = "Array access with IC",
            priority = 10,
        })
        table.insert(candidates, {
            kind = "table_access",
            name = "table.getfield_shape_ic1",
            description = "Field access with shape IC",
            priority = 9,
        })
    end

    if program_evidence.has_settable then
        table.insert(candidates, {
            kind = "table_write",
            name = "table.settable_array_i64_ic1",
            description = "Array write with IC",
            priority = 10,
        })
    end

    -- If we see CALL hotspot, add call stencils
    if program_evidence.has_call then
        table.insert(candidates, {
            kind = "call",
            name = "call.known_lclosure",
            description = "Call known Lua closure",
            priority = 10,
        })
    end

    -- If we see FORLOOP hotspot, add loop stencils
    if program_evidence.has_forloop then
        table.insert(candidates, {
            kind = "loop",
            name = "loop.forloop_i64_positive",
            description = "Integer for-loop, positive step",
            priority = 10,
        })
    end

    return candidates
end

-- Estimate what stencils will help
function M.estimate_coverage_gain(program_evidence)
    local gain = {
        current_coverage = 0.15,  -- we have ~15% from arithmetic + guards + basic memory
        estimated_after = 0.15,
    }

    local improvements = 0
    if program_evidence.has_gettable then improvements = improvements + 0.15 end
    if program_evidence.has_settable then improvements = improvements + 0.10 end
    if program_evidence.has_call then improvements = improvements + 0.20 end
    if program_evidence.has_forloop then improvements = improvements + 0.10 end
    if program_evidence.has_getfield then improvements = improvements + 0.10 end

    gain.estimated_after = math.min(0.90, gain.current_coverage + improvements)
    return gain
end

-- Next-to-generate recommendations
function M.recommend_stencils()
    return {
        {
            priority = 1,
            name = "table.gettable_array_i64_ic1",
            reason = "Table access with inline cache (most common in real Lua)",
            affected_opcodes = {"GETTABLE", "GETI"},
            estimated_coverage_gain = 0.15,
        },
        {
            priority = 2,
            name = "call.known_lclosure",
            reason = "Function call to known Lua closure",
            affected_opcodes = {"CALL"},
            estimated_coverage_gain = 0.20,
        },
        {
            priority = 3,
            name = "loop.forloop_i64_positive",
            reason = "Integer numeric for-loop (common pattern)",
            affected_opcodes = {"FORLOOP"},
            estimated_coverage_gain = 0.10,
        },
        {
            priority = 4,
            name = "table.getfield_shape_ic1",
            reason = "Object field access with shape cache",
            affected_opcodes = {"GETFIELD"},
            estimated_coverage_gain = 0.10,
        },
        {
            priority = 5,
            name = "table.settable_array_i64_ic1",
            reason = "Table write with inline cache",
            affected_opcodes = {"SETTABLE", "SETI"},
            estimated_coverage_gain = 0.10,
        },
    }
end

return M
