-- impl/stencil_plan.lua
-- Leaf methods on LalinStencil types.
-- Ported from stencil_artifact_plan.lua (Stencil.* methods only).

local Stencil = require("lalin.schema_v2.stencil")
local Code    = require("lalin.schema_v2.code")

----------------------------------------------------------------------
-- StencilAccessLayout → is_scalar / abi_ty
----------------------------------------------------------------------

function Stencil.StencilAccessLayout:stencil_artifact_is_scalar()
  return false
end

function Stencil.StencilLayoutScalar:stencil_artifact_is_scalar()
  return true
end

function Stencil.StencilAccessLayout:stencil_artifact_abi_ty(access_ty)
  return Code.CodeTyDataPtr(access_ty)
end

function Stencil.StencilLayoutScalar:stencil_artifact_abi_ty(access_ty)
  return access_ty
end

----------------------------------------------------------------------
-- StencilSink → is_reduce / is_store
----------------------------------------------------------------------

function Stencil.StencilSink:stencil_artifact_is_reduce() return false end
function Stencil.StencilSinkStore:stencil_artifact_is_reduce() return false end
function Stencil.StencilSinkReduce:stencil_artifact_is_reduce() return true end
function Stencil.StencilSinkScan:stencil_artifact_is_reduce() return false end

function Stencil.StencilSink:stencil_artifact_is_store() return false end
function Stencil.StencilSinkStore:stencil_artifact_is_store() return true end

----------------------------------------------------------------------
-- StencilSink → is_auto_vector
----------------------------------------------------------------------

function Stencil.StencilSink:stencil_artifact_is_auto_vector() return false end
function Stencil.StencilSinkScan:stencil_artifact_is_auto_vector() return true end
function Stencil.StencilSinkScatterReduce:stencil_artifact_is_auto_vector() return false end
function Stencil.StencilSinkStore:stencil_artifact_is_auto_vector()
  return true
end
function Stencil.StencilSinkReduce:stencil_artifact_is_auto_vector()
  return true
end

----------------------------------------------------------------------
-- StencilSink → sink_materializer_reject_reason
----------------------------------------------------------------------

function Stencil.StencilSink:stencil_artifact_sink_materializer_reject_reason(producer)
  return "unsupported sink type: " .. tostring(self)
end

function Stencil.StencilSinkStore:stencil_artifact_sink_materializer_reject_reason(producer)
  return nil
end

function Stencil.StencilSinkReduce:stencil_artifact_sink_materializer_reject_reason(producer)
  return nil
end

function Stencil.StencilSinkScan:stencil_artifact_sink_materializer_reject_reason(producer)
  return nil
end

function Stencil.StencilSinkScatterReduce:stencil_artifact_sink_materializer_reject_reason(producer)
  return nil
end

----------------------------------------------------------------------
-- StencilReduceScope → materializer_reject_reason / is_domain
----------------------------------------------------------------------

function Stencil.StencilReduceScope:stencil_artifact_materializer_reject_reason(producer)
  return "unsupported reduce scope"
end

function Stencil.StencilReduceScopeDomain:stencil_artifact_materializer_reject_reason(producer)
  return nil
end

function Stencil.StencilReduceScopeAxes:stencil_artifact_materializer_reject_reason(producer)
  return nil
end

function Stencil.StencilReduceScopeWindow:stencil_artifact_materializer_reject_reason(producer)
  return nil
end

function Stencil.StencilReduceScope:stencil_artifact_is_domain() return false end
function Stencil.StencilReduceScopeDomain:stencil_artifact_is_domain() return true end

----------------------------------------------------------------------
-- StencilScatterReduce → is_atomic
----------------------------------------------------------------------

function Stencil.StencilScatterReduceAtomic:stencil_artifact_is_atomic() return true end
function Stencil.StencilScatterReduceConflictSemantics:stencil_artifact_is_atomic() return false end

----------------------------------------------------------------------
-- StencilProducer / StencilAccessLayout → is_producer
----------------------------------------------------------------------

function Stencil.StencilProducer:stencil_artifact_is_producer() return true end
function Stencil.StencilAccessLayout:stencil_artifact_is_producer() return false end

----------------------------------------------------------------------
-- StencilLanePolicy → is_fixed_lane
----------------------------------------------------------------------

function Stencil.StencilLaneFixed:stencil_artifact_is_fixed_lane() return true end
function Stencil.StencilLanePolicy:stencil_artifact_is_fixed_lane() return false end

----------------------------------------------------------------------
-- StencilReduce / StencilStore → semantic classification
----------------------------------------------------------------------

function Stencil.StencilReduceFold:stencil_artifact_is_fold() return true end
function Stencil.StencilReduceFold:stencil_artifact_is_partition() return false end
function Stencil.StencilReduceFold:stencil_artifact_is_find() return false end
function Stencil.StencilStorePartition:stencil_artifact_is_fold() return false end
function Stencil.StencilStorePartition:stencil_artifact_is_partition() return true end
function Stencil.StencilStorePartition:stencil_artifact_is_find() return false end
function Stencil.StencilReduceFind:stencil_artifact_is_fold() return false end
function Stencil.StencilReduceFind:stencil_artifact_is_partition() return false end
function Stencil.StencilReduceFind:stencil_artifact_is_find() return true end

----------------------------------------------------------------------
-- StencilSink → build_descriptor
----------------------------------------------------------------------

function Stencil.StencilSink:stencil_artifact_build_descriptor(producer, accesses, body, result_ty)
  error("stencil_artifact_plan: unsupported sink type for build_descriptor", 3)
end

function Stencil.StencilSinkScatterReduce:stencil_artifact_build_descriptor(producer, accesses, body, result_ty)
  return Stencil.StencilDescriptor(producer, accesses, body, self)
end

function Stencil.StencilSinkReduce:stencil_artifact_build_descriptor(producer, accesses, body, result_ty)
  return Stencil.StencilDescriptor(producer, accesses, body, self)
end

function Stencil.StencilSinkStore:stencil_artifact_build_descriptor(producer, accesses, body, result_ty)
  return Stencil.StencilDescriptor(producer, accesses, body, self)
end

function Stencil.StencilSinkScan:stencil_artifact_build_descriptor(producer, accesses, body, result_ty)
  return Stencil.StencilDescriptor(producer, accesses, body, self)
end

----------------------------------------------------------------------
-- StencilProducer → producer_analysis (stub)
----------------------------------------------------------------------

function Stencil.StencilProducer:stencil_producer_analysis(code, mem)
  -- Ported from stencil_artifact_plan — producer fact extraction.
  -- Full analysis requires code/mem facts wiring; here we return a
  -- placeholder that callers can refine.
  return { kind = "producer", shape = self.shape, order = self.order }
end

----------------------------------------------------------------------
-- StencilDescriptor → descriptor_validate (stub)
----------------------------------------------------------------------

function Stencil.StencilDescriptor:stencil_descriptor_validate(target)
  -- Validate that this stencil descriptor is supported on the given target.
  -- Full validation requires backend target facts.
  return { valid = true, issues = {} }
end

----------------------------------------------------------------------
-- StencilSelected → selected_codegen (stub)
----------------------------------------------------------------------

function Stencil.StencilSelected:stencil_selected_codegen(target, kernel)
  -- Generate a codegen plan for a selected stencil.
  -- Full codegen requires kernel/schedule facts wiring.
  return { kind = "codegen_plan", target = target, kernel = kernel }
end
