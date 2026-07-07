-- impl/lower_emit_c/materialize.lua
-- C value/place materialization helpers for stencil computations.
-- Ported from emit_c_materialize.lua.

require("lalin.schema_v2")

local Stencil = require("lalin.schema_v2.stencil")

----------------------------------------------------------------------
-- StencilAccessRole → cmat_mutability / cmat_const_eligible / cmat_restrict_eligible
----------------------------------------------------------------------

function Stencil.StencilAccessRole:cmat_mutability()
  -- parent default — not used, concrete leaves override
end

function Stencil.StencilAccessRead:cmat_mutability()
  return "readonly"
end

function Stencil.StencilAccessIndex:cmat_mutability()
  return "readonly"
end

function Stencil.StencilAccessWrite:cmat_mutability()
  return "writeonly"
end

function Stencil.StencilAccessReadWrite:cmat_mutability()
  return "readwrite"
end

function Stencil.StencilAccessReduce:cmat_mutability()
  return "reduce"
end

function Stencil.StencilAccessControlResult:cmat_mutability()
  return "writeonly"
end

function Stencil.StencilAccessRole:cmat_const_eligible()
  return false
end

function Stencil.StencilAccessRead:cmat_const_eligible()
  return true
end

function Stencil.StencilAccessIndex:cmat_const_eligible()
  return true
end

function Stencil.StencilAccessRole:cmat_restrict_eligible(layout)
  return false
end

function Stencil.StencilAccessRead:cmat_restrict_eligible(layout)
  return layout:cmat_is_pointer_like()
end

function Stencil.StencilAccessWrite:cmat_restrict_eligible(layout)
  return layout:cmat_is_pointer_like()
end

function Stencil.StencilAccessReadWrite:cmat_restrict_eligible(layout)
  return layout:cmat_is_pointer_like()
end

function Stencil.StencilAccessReduce:cmat_restrict_eligible(layout)
  return layout:cmat_is_pointer_like()
end

function Stencil.StencilAccessIndex:cmat_restrict_eligible(layout)
  return layout:cmat_is_pointer_like()
end

----------------------------------------------------------------------
-- StencilAccessLayout → cmat_is_pointer_like
----------------------------------------------------------------------

function Stencil.StencilAccessLayout:cmat_is_pointer_like()
  return true
end

function Stencil.StencilLayoutScalar:cmat_is_pointer_like()
  return false
end

----------------------------------------------------------------------
-- StencilAccess → cmat_binding
----------------------------------------------------------------------

function Stencil.StencilAccess:cmat_binding(_input)
  -- creates a CMat access binding from this stencil access descriptor
  return {
    name = self.name,
    ty = self.ty,
    layout = self.layout,
    mutability = self.role:cmat_mutability(),
    restrict = self.role:cmat_restrict_eligible(self.layout),
    const = self.role:cmat_const_eligible(),
  }
end

----------------------------------------------------------------------
-- StencilProducerOrder → cmat_loop_order
----------------------------------------------------------------------

function Stencil.StencilProducerOrder:cmat_loop_order()
  -- parent default
end

function Stencil.StencilProducerForward:cmat_loop_order()
  return "forward"
end

function Stencil.StencilProducerBackward:cmat_loop_order()
  return "backward"
end

----------------------------------------------------------------------
-- StencilProducerAxis → cmat_loop_axis
----------------------------------------------------------------------

function Stencil.StencilProducerAxis:cmat_loop_axis(i)
  return {
    axis = i,
    index_name = self.index_name or ("i" .. tostring(i)),
    index_ty = self.index_ty,
    step = self.step,
    order = self.order:cmat_loop_order(),
  }
end

----------------------------------------------------------------------
-- StencilProducerShape → cmat_loop_axes
----------------------------------------------------------------------

function Stencil.StencilProducerShape:cmat_loop_axes()
  error("c_materialize: unsupported producer shape", 2)
end

function Stencil.StencilProduceRange1D:cmat_loop_axes()
  return { Stencil.StencilProducerAxis:cmat_loop_axis(self.axes and self.axes[1] or self, 1) }
end

function Stencil.StencilProduceRangeND:cmat_loop_axes()
  local out = {}
  for i, axis in ipairs(self.axes or {}) do out[#out + 1] = axis:cmat_loop_axis(i) end
  return out
end

function Stencil.StencilProduceWindowND:cmat_loop_axes()
  local out = {}
  for i, axis in ipairs(self.axes or {}) do out[#out + 1] = axis:cmat_loop_axis(i) end
  return out
end

function Stencil.StencilProduceTiledND:cmat_loop_axes()
  local out = {}
  for i, axis in ipairs(self.axes or {}) do out[#out + 1] = axis:cmat_loop_axis(i) end
  return out
end

----------------------------------------------------------------------
-- StencilVectorTailPolicy → cmat_tail_policy
----------------------------------------------------------------------

function Stencil.StencilVectorTailPolicy:cmat_tail_policy()
  -- parent default
end

function Stencil.StencilVectorScalarTail:cmat_tail_policy()
  return "scalar"
end

function Stencil.StencilVectorMaskTail:cmat_tail_policy()
  return "mask"
end

function Stencil.StencilVectorOverreadProvenSafe:cmat_tail_policy()
  return "overread_proven_safe"
end

----------------------------------------------------------------------
-- StencilLanePolicy → cmat_lane_count
----------------------------------------------------------------------

function Stencil.StencilLanePolicy:cmat_lane_count()
  return nil
end

function Stencil.StencilLaneFixed:cmat_lane_count()
  return self.lanes
end

----------------------------------------------------------------------
-- StencilSchedule → cmat_vector_policy / cmat_unroll / cmat_interleave
----------------------------------------------------------------------

function Stencil.StencilSchedule:cmat_vector_policy()
  return "none"
end

function Stencil.StencilScheduleAutoVector:cmat_vector_policy()
  return { kind = "autovec", tail = "scalar" }
end

function Stencil.StencilScheduleVector:cmat_vector_policy()
  return {
    kind = "explicit",
    lanes = self.lane_policy and self.lane_policy:cmat_lane_count() or self.vector_unroll,
    tail = self.tail and self.tail:cmat_tail_policy() or "scalar",
  }
end

function Stencil.StencilSchedule:cmat_unroll()
  return 1
end

function Stencil.StencilScheduleUnrolled:cmat_unroll()
  return self.factor
end

function Stencil.StencilScheduleVector:cmat_unroll()
  return self.vector_unroll
end

function Stencil.StencilSchedule:cmat_interleave()
  return 1
end

function Stencil.StencilScheduleVector:cmat_interleave()
  return self.interleave
end

----------------------------------------------------------------------
-- StencilStreamDef → cmat_stream_materialization
----------------------------------------------------------------------

function Stencil.StencilStreamDef:cmat_stream_materialization(_input)
  return { kind = "inline", id = self.id, ty = self.ty }
end

----------------------------------------------------------------------
-- StencilSinkDef / StencilSinkOp → cmat_sink_materialization
----------------------------------------------------------------------

function Stencil.StencilSinkDef:cmat_sink_materialization(input)
  return self.op and self.op:cmat_sink_materialization(input, self.id)
end

function Stencil.StencilSinkOp:cmat_sink_materialization(_input, ref)
  return { kind = "inline", ref = ref }
end

function Stencil.StencilSinkOpAll:cmat_sink_materialization(_input, ref)
  return { kind = "control_result", ref = ref }
end

function Stencil.StencilSinkOpAny:cmat_sink_materialization(_input, ref)
  return { kind = "control_result", ref = ref }
end

function Stencil.StencilSinkOpFind:cmat_sink_materialization(_input, ref)
  return { kind = "control_result", ref = ref }
end

----------------------------------------------------------------------
-- StencilComputation → cmat_materialize
----------------------------------------------------------------------

function Stencil.StencilComputation:cmat_materialize(input)
  input = input or {}
  local bindings, streams, sinks = {}, {}, {}
  for _, access in ipairs(self.accesses or {}) do
    bindings[#bindings + 1] = access:cmat_binding(input)
  end
  for _, stream in ipairs(self.streams or {}) do
    streams[#streams + 1] = stream:cmat_stream_materialization(input)
  end
  for _, sink in ipairs(self.sinks or {}) do
    sinks[#sinks + 1] = sink:cmat_sink_materialization(input)
  end
  local schedule = self.schedule
  return {
    id = self.id,
    loop_nest = {
      axes = self.producer and self.producer.shape and self.producer.shape:cmat_loop_axes() or {},
      unroll = schedule and schedule:cmat_unroll() or 1,
      interleave = schedule and schedule:cmat_interleave() or 1,
      vector = schedule and schedule:cmat_vector_policy() or "none",
    },
    bindings = bindings,
    streams = streams,
    sinks = sinks,
    schedule = schedule,
    proofs = self.proofs or {},
  }
end
