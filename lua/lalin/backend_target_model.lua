local asdl = require("lalin.asdl")

local function bind_context(T)
    local Backend = T.LalinBackend
    local Host = T.LalinHost
    assert(Backend and Host, "lalin.backend_target_model(T) expects LalinBackend/LalinHost in the context")

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
            Backend.BackTargetPrefersUnroll(shape_vec(Backend.BackI32, 4), 1, 50),
            Backend.BackTargetPrefersUnroll(shape_vec(Backend.BackU32, 4), 1, 50),
            Backend.BackTargetPrefersUnroll(shape_vec(Backend.BackI64, 2), 1, 50),
            Backend.BackTargetPrefersUnroll(shape_vec(Backend.BackU64, 2), 1, 50),
        })
    end

    local function first_fact(model, cls)
        for i = 1, #model.facts do
            if asdl.classof(model.facts[i]) == cls then return model.facts[i] end
        end
        return nil
    end

    function api.host_target(model)
        local pointer = first_fact(model, Backend.BackTargetPointerBits)
        local index = first_fact(model, Backend.BackTargetIndexBits)
        local endian = first_fact(model, Backend.BackTargetEndian)
        local host_endian = Host.HostEndianLittle
        if endian ~= nil and endian.endian == Backend.BackEndianBig then host_endian = Host.HostEndianBig end
        return Host.HostTargetModel(pointer and pointer.bits or 64, index and index.bits or 64, host_endian)
    end

    return api
end

return bind_context
