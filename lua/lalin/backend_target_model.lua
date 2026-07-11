local function bind_context(T)
    local Backend = T.LalinBackend
    local Host = T.LalinHost
    local C = T.LalinC
    assert(Backend and Host and C,
        "lalin.backend_target_model(T) expects LalinBackend/LalinHost/LalinC in the context")

    local api = {}

    local function shape_scalar(s) return Backend.BackShapeScalar(s) end
    local function shape_vec(elem, lanes) return Backend.BackShapeVec(Backend.BackVec(elem, lanes)) end

    function api.default_native()
        return Backend.BackTargetModel(Backend.BackTargetNative, {
            Backend.BackTargetPointerBits(64),
            Backend.BackTargetIndexBits(64),
            Backend.BackTargetEndian(Backend.BackEndianLittle),
            Backend.BackTargetCacheLineBytes(64),
            Backend.BackTargetFeature(Backend.BackFeatureSSE2),
            Backend.BackTargetFeature(Backend.BackFeaturePOPCNT),
            -- Native vector lowering keeps 128-bit shapes as the portable floor.
            Backend.BackTargetSupportsShape(shape_scalar(Backend.BackI32)),
            Backend.BackTargetSupportsShape(shape_scalar(Backend.BackI64)),
            Backend.BackTargetSupportsShape(shape_scalar(Backend.BackU32)),
            Backend.BackTargetSupportsShape(shape_scalar(Backend.BackU64)),
            Backend.BackTargetSupportsShape(shape_scalar(Backend.BackF32)),
            Backend.BackTargetSupportsShape(shape_scalar(Backend.BackF64)),
            Backend.BackTargetSupportsShape(shape_vec(Backend.BackI32, 4)),
            Backend.BackTargetSupportsShape(shape_vec(Backend.BackU32, 4)),
            Backend.BackTargetSupportsShape(shape_vec(Backend.BackI64, 2)),
            Backend.BackTargetSupportsShape(shape_vec(Backend.BackU64, 2)),
            Backend.BackTargetSupportsVectorOp(Backend.BackVec(Backend.BackI32, 4), "int_binary"),
            Backend.BackTargetSupportsVectorOp(Backend.BackVec(Backend.BackU32, 4), "int_binary"),
            Backend.BackTargetSupportsVectorOp(Backend.BackVec(Backend.BackI64, 2), "int_binary"),
            Backend.BackTargetSupportsVectorOp(Backend.BackVec(Backend.BackU64, 2), "int_binary"),
            Backend.BackTargetSupportsVectorOp(Backend.BackVec(Backend.BackI32, 4), "bit_binary"),
            Backend.BackTargetSupportsVectorOp(Backend.BackVec(Backend.BackU32, 4), "bit_binary"),
            Backend.BackTargetSupportsVectorOp(Backend.BackVec(Backend.BackI64, 2), "bit_binary"),
            Backend.BackTargetSupportsVectorOp(Backend.BackVec(Backend.BackU64, 2), "bit_binary"),
            Backend.BackTargetSupportsVectorOp(Backend.BackVec(Backend.BackI32, 4), "compare_select"),
            Backend.BackTargetSupportsVectorOp(Backend.BackVec(Backend.BackU32, 4), "compare_select"),
            Backend.BackTargetSupportsVectorOp(Backend.BackVec(Backend.BackI64, 2), "compare_select"),
            Backend.BackTargetSupportsVectorOp(Backend.BackVec(Backend.BackU64, 2), "compare_select"),
            Backend.BackTargetPrefersUnroll(shape_vec(Backend.BackI32, 4), 1, 50, Backend.TargetHeuristicLoopSize(50)),
            Backend.BackTargetPrefersUnroll(shape_vec(Backend.BackU32, 4), 1, 50, Backend.TargetHeuristicLoopSize(50)),
            Backend.BackTargetPrefersUnroll(shape_vec(Backend.BackI64, 2), 1, 50, Backend.TargetHeuristicLoopSize(50)),
            Backend.BackTargetPrefersUnroll(shape_vec(Backend.BackU64, 2), 1, 50, Backend.TargetHeuristicLoopSize(50)),
        })
    end

    function Host.HostTargetModel:host_target_model()
        return self
    end

    function C.CBackendLittleEndian:host_endian()
        return Host.HostEndianLittle
    end

    function C.CBackendBigEndian:host_endian()
        return Host.HostEndianBig
    end

    function C.CBackendTarget:host_target_model()
        return Host.HostTargetModel(self.pointer_bits, self.index_bits, self.endian:host_endian())
    end

    function Backend.BackEndianLittle:host_endian()
        return Host.HostEndianLittle
    end

    function Backend.BackEndianBig:host_endian()
        return Host.HostEndianBig
    end

    function Backend.BackTargetFact:host_target_projection(projection)
        return projection
    end

    function Backend.BackTargetPointerBits:host_target_projection(projection)
        return Backend.BackHostTargetProjection(self.bits, projection.index_bits, projection.endian)
    end

    function Backend.BackTargetIndexBits:host_target_projection(projection)
        return Backend.BackHostTargetProjection(projection.pointer_bits, self.bits, projection.endian)
    end

    function Backend.BackTargetEndian:host_target_projection(projection)
        return Backend.BackHostTargetProjection(projection.pointer_bits, projection.index_bits, self.endian)
    end

    function Backend.BackTargetModel:host_target_model()
        local projection = Backend.BackHostTargetProjection(64, 64, Backend.BackEndianLittle)
        for i = 1, #self.facts do
            projection = self.facts[i]:host_target_projection(projection)
        end
        return Host.HostTargetModel(
            projection.pointer_bits,
            projection.index_bits,
            projection.endian:host_endian()
        )
    end

    function api.host_target(model)
        return model:host_target_model()
    end

    return api
end

return bind_context
