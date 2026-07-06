local function sanitize(s)
    s = tostring(s or "x"):gsub("[^%w_]", "_")
    if s == "" then s = "x" end
    if s:match("^%d") then s = "_" .. s end
    return s
end

local function bind_context(T)
    T._lalin_api_cache = T._lalin_api_cache or {}
    if T._lalin_api_cache.c_materialize ~= nil then return T._lalin_api_cache.c_materialize end

    local Code = T.LalinCode
    local Stencil = T.LalinStencil
    local CMat = T.LalinCMat

    local api = {}

    local function local_id(name)
        return CMat.CMatLocalId(sanitize(name))
    end

    function Stencil.StencilAccessRole:cmat_mutability()
        return CMat.CMatAccessReadOnly
    end
    function Stencil.StencilAccessRead:cmat_mutability()
        return CMat.CMatAccessReadOnly
    end
    function Stencil.StencilAccessIndex:cmat_mutability()
        return CMat.CMatAccessReadOnly
    end
    function Stencil.StencilAccessWrite:cmat_mutability()
        return CMat.CMatAccessWriteOnly
    end
    function Stencil.StencilAccessReadWrite:cmat_mutability()
        return CMat.CMatAccessReadWrite
    end
    function Stencil.StencilAccessReduce:cmat_mutability()
        return CMat.CMatAccessReduce
    end
    function Stencil.StencilAccessControlResult:cmat_mutability()
        return CMat.CMatAccessWriteOnly
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

    function Stencil.StencilAccessRole:cmat_restrict_eligible(_layout)
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

    function Stencil.StencilAccessLayout:cmat_is_pointer_like()
        return true
    end
    function Stencil.StencilLayoutScalar:cmat_is_pointer_like()
        return false
    end

    function Stencil.StencilAccess:cmat_binding(_input)
        local ref = Stencil.StencilAccessRef(self.name)
        return CMat.CMatAccessBinding(
            ref,
            self,
            local_id(self.name),
            self.ty,
            self.layout,
            self.role:cmat_mutability(),
            self.role:cmat_restrict_eligible(self.layout),
            self.role:cmat_const_eligible(),
            Stencil.StencilAlignmentUnknown
        )
    end

    function Stencil.StencilProducerOrder:cmat_loop_order()
        return CMat.CMatLoopForward
    end
    function Stencil.StencilProducerForward:cmat_loop_order()
        return CMat.CMatLoopForward
    end
    function Stencil.StencilProducerBackward:cmat_loop_order()
        return CMat.CMatLoopBackward
    end

    function Stencil.StencilProducerAxis:cmat_loop_axis(i)
        return CMat.CMatLoopAxis(
            Stencil.StencilAxisRef(i),
            local_id(self.index_name or ("i" .. tostring(i))),
            self.index_ty,
            nil,
            nil,
            self.step,
            self.order:cmat_loop_order()
        )
    end

    function Stencil.StencilProducerShape:cmat_loop_axes()
        error("c_materialize: unsupported SOAC producer shape", 2)
    end
    function Stencil.StencilProduceRange1D:cmat_loop_axes()
        return {
            CMat.CMatLoopAxis(
                Stencil.StencilAxisRef(1),
                local_id("i"),
                self.index_ty,
                nil,
                nil,
                self.step,
                self.order:cmat_loop_order()
            ),
        }
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

    function Stencil.StencilVectorTailPolicy:cmat_tail_policy()
        return CMat.CMatTailScalar
    end
    function Stencil.StencilVectorScalarTail:cmat_tail_policy()
        return CMat.CMatTailScalar
    end
    function Stencil.StencilVectorMaskTail:cmat_tail_policy()
        return CMat.CMatTailMask
    end
    function Stencil.StencilVectorOverreadProvenSafe:cmat_tail_policy()
        return CMat.CMatTailOverreadProvenSafe
    end

    function Stencil.StencilLanePolicy:cmat_lane_count()
        return nil
    end
    function Stencil.StencilLaneFixed:cmat_lane_count()
        return self.lanes
    end

    function Stencil.StencilSchedule:cmat_vector_policy()
        return CMat.CMatVectorNone
    end
    function Stencil.StencilScheduleAutoVector:cmat_vector_policy()
        return CMat.CMatVectorAutovec(nil, CMat.CMatTailScalar)
    end
    function Stencil.StencilScheduleVector:cmat_vector_policy()
        return CMat.CMatVectorExplicit(self.lane_policy:cmat_lane_count() or self.vector_unroll, self.tail:cmat_tail_policy())
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

    function Stencil.StencilStreamDef:cmat_stream_materialization(_input)
        return CMat.CMatStreamInline(Stencil.StencilStreamRef(self.id), self.ty)
    end

    function Stencil.StencilSinkDef:cmat_sink_materialization(input)
        return self.op:cmat_sink_materialization(input, Stencil.StencilSinkRef(self.id))
    end

    function Stencil.StencilSinkOp:cmat_sink_materialization(_input, ref)
        return CMat.CMatSinkInline(ref)
    end
    function Stencil.StencilSinkOpAll:cmat_sink_materialization(_input, ref)
        return CMat.CMatSinkControlResult(ref)
    end
    function Stencil.StencilSinkOpAny:cmat_sink_materialization(_input, ref)
        return CMat.CMatSinkControlResult(ref)
    end
    function Stencil.StencilSinkOpFind:cmat_sink_materialization(_input, ref)
        return CMat.CMatSinkControlResult(ref)
    end

    local function computation_loop_nest(computation)
        local schedule = computation.schedule
        return CMat.CMatLoopNest(
            computation.producer.shape:cmat_loop_axes(),
            schedule:cmat_unroll(),
            schedule:cmat_interleave(),
            schedule:cmat_vector_policy()
        )
    end

    function Stencil.StencilComputation:cmat_materialize(input)
        input = input or {}
        local bindings, streams, sinks = {}, {}, {}
        for _, access in ipairs(self.accesses or {}) do bindings[#bindings + 1] = access:cmat_binding(input) end
        for _, stream in ipairs(self.streams or {}) do streams[#streams + 1] = stream:cmat_stream_materialization(input) end
        for _, sink in ipairs(self.sinks or {}) do sinks[#sinks + 1] = sink:cmat_sink_materialization(input) end
        return CMat.CMatMaterializedFused(CMat.CMatFusedKernel(
            CMat.CMatKernelId(self.id.text),
            self,
            computation_loop_nest(self),
            bindings,
            streams,
            sinks,
            self.schedule,
            self.proofs or {}
        ))
    end

    local function materialize_computations(module_id, computations, input)
        local kernels = {}
        for _, computation in ipairs(computations or {}) do
            kernels[#kernels + 1] = computation:cmat_materialize(input)
        end
        return CMat.CMatModule(module_id, kernels)
    end

    api.materialize_computations = materialize_computations

    T._lalin_api_cache.c_materialize = api
    return api
end

return bind_context
