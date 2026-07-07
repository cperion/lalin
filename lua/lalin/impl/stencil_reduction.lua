-- impl/stencil_reduction.lua
-- Leaf methods on Value.ReductionOp — display names and artifact names.
-- Ported from lower_kernel_rewrite.lua (display_name) and
-- stencil_artifact_plan.lua (stencil_artifact_name).

require("lalin.schema_v2")

local Value = require("lalin.schema_v2.value")

-- display_name: human-readable reduction name (lower_kernel_rewrite.lua)
function Value.ReductionAdd:display_name() return "add" end
function Value.ReductionMul:display_name() return "mul" end
function Value.ReductionAnd:display_name() return "and" end
function Value.ReductionOr:display_name() return "or" end
function Value.ReductionXor:display_name() return "xor" end
function Value.ReductionMin:display_name() return "min" end
function Value.ReductionMax:display_name() return "max" end

-- stencil_artifact_name: reduction name for stencil artifact ids
-- (stencil_artifact_plan.lua).  Semantically identical to display_name;
-- kept as a separate method because callers use different contract names.
function Value.ReductionAdd:stencil_artifact_name() return "add" end
function Value.ReductionMul:stencil_artifact_name() return "mul" end
function Value.ReductionAnd:stencil_artifact_name() return "and" end
function Value.ReductionOr:stencil_artifact_name() return "or" end
function Value.ReductionXor:stencil_artifact_name() return "xor" end
function Value.ReductionMin:stencil_artifact_name() return "min" end
function Value.ReductionMax:stencil_artifact_name() return "max" end
