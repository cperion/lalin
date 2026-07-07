local asdl = require("lalin.asdl")
local bit = require("bit")

local function sanitize(s)
    s = tostring(s or "x"):gsub("[^%w_]", "_")
    if s == "" then s = "x" end
    if s:match("^%d") then s = "_" .. s end
    return s
end

local function stable_hash32(s)
    local h = 2166136261
    for i = 1, #s do h = (bit.bxor(h, s:byte(i)) * 16777619) % 4294967296 end
    return string.format("%08x", h)
end

local function stable_hash128(s)
    return table.concat({
        stable_hash32("lalin:0:" .. s),
        stable_hash32("lalin:1:" .. s),
        stable_hash32("lalin:2:" .. s),
        stable_hash32("lalin:3:" .. s),
    })
end

local function stable_repr(v, seen)
    local tv = type(v)
    if tv == "nil" then return "nil" end
    if tv == "boolean" or tv == "number" then return tostring(v) end
    if tv == "string" then return string.format("%q", v) end
    if tv ~= "table" then return tv .. ":" .. tostring(v) end
    -- GATING: stable_repr is a cross-cutting serialization utility for hashing/fingerprinting,
    -- not semantic dispatch. Uses classof to produce type-annotated stable strings for any ASDL value.
    local cls = asdl.classof(v)
    if tostring(cls) == "Class(LalinCode.CodeValueId)" then return tostring(cls) .. "{_}" end
    if tostring(cls):match("^Class%(LalinFlow%.FlowDomain") then return tostring(cls) .. "{_}" end
    if tostring(cls) == "Class(LalinGraph.GraphLoopId)" then return tostring(cls) .. "{_}" end
    if tostring(cls) == "Class(LalinCode.CodeFuncId)" then return tostring(cls) .. "{_}" end
    seen = seen or {}
    if seen[v] then return "<cycle>" end
    seen[v] = true
    local out = {}
    if cls then
        out[#out + 1] = tostring(cls)
        out[#out + 1] = "{"
        for i, field in ipairs(asdl.fields(cls) or {}) do
            if i > 1 then out[#out + 1] = "," end
            out[#out + 1] = field.name
            out[#out + 1] = "="
            out[#out + 1] = stable_repr(rawget(v, field.name), seen)
        end
        out[#out + 1] = "}"
    else
        local keys = {}
        for key in pairs(v) do keys[#keys + 1] = key end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
        out[#out + 1] = "{"
        for i, key in ipairs(keys) do
            if i > 1 then out[#out + 1] = "," end
            out[#out + 1] = stable_repr(key, seen)
            out[#out + 1] = "="
            out[#out + 1] = stable_repr(v[key], seen)
        end
        out[#out + 1] = "}"
    end
    seen[v] = nil
    return table.concat(out)
end

local function bind_context(T)
    T._lalin_api_cache = T._lalin_api_cache or {}
    if T._lalin_api_cache.stencil_artifact_plan ~= nil then return T._lalin_api_cache.stencil_artifact_plan end

    local Core = T.LalinCore
    local Code = T.LalinCode
    local Value = T.LalinValue
    local Kernel = T.LalinKernel
    local Stencil = T.LalinStencil
    local Schedule = T.LalinSchedule
    local CEm = T.LalinCEmit
    local CodeType = require("lalin.code_type")(T)
    local CEmit = require("lalin.emit_c_lower")(T)
    local ReductionAlgebra = require("lalin.reduction_algebra")(T)

    local api = {}

    -- CodeType leaf methods for stencil artifact naming
    function Code.CodeTyInt:stencil_artifact_type_name()
        return (self.signedness == Code.CodeSigned and "i" or "u") .. tostring(self.bits)
    end
    function Code.CodeTyFloat:stencil_artifact_type_name()
        return "f" .. tostring(self.bits)
    end
    function Code.CodeTyIndex:stencil_artifact_type_name() return "index" end
    function Code.CodeTyBool8:stencil_artifact_type_name() return "bool8" end
    function Code.CodeTyArray:stencil_artifact_type_name()
        return "ml_array_" .. tostring(self.count) .. "_" .. self.elem:stencil_artifact_type_name()
    end
    function Code.CodeTyVector:stencil_artifact_type_name()
        return "ml_vector_" .. tostring(self.lanes) .. "_" .. self.elem:stencil_artifact_type_name()
    end
    function Code.CodeTyClosure:stencil_artifact_type_name()
        return "ml_closure_" .. sanitize(self.sig.text)
    end
    function Code.CodeTyImportedCFuncPtr:stencil_artifact_type_name()
        return "ml_cfuncptr_" .. sanitize(self.sig.text)
    end
    function Code.CodeType:stencil_artifact_type_name()
        return sanitize(CodeType.code_type_key(self))
    end

    function Code.CodeType:stencil_artifact_c_type()
        return CEmit.emit_type(select(1, CodeType.code_type_to_c(CEm.CEmitMachine.dummy(), self)))
    end
    function Code.CodeTyArray:stencil_artifact_c_type() return self:stencil_artifact_type_name() end
    function Code.CodeTyClosure:stencil_artifact_c_type() return self:stencil_artifact_type_name() end
    function Code.CodeTyVector:stencil_artifact_c_type() return self:stencil_artifact_type_name() end
    function Code.CodeTyImportedCFuncPtr:stencil_artifact_c_type() return self:stencil_artifact_type_name() end

    function Code.CodeType:stencil_artifact_is_code_scalar() return false end
    function Code.CodeTyInt:stencil_artifact_is_code_scalar() return true end
    function Code.CodeTyFloat:stencil_artifact_is_code_scalar() return true end


    local function type_name(ty) return ty:stencil_artifact_type_name() end

    local function c_type(ty)
        return ty:stencil_artifact_c_type()
    end


    ----------------------------------------------------------------------
    -- StencilAccessLayout leaf methods
    function Stencil.StencilLayoutScalar:stencil_artifact_is_scalar() return true end
    function Stencil.StencilLayoutScalar:stencil_artifact_abi_ty(access_ty) return access_ty end
    function Stencil.StencilAccessLayout:stencil_artifact_is_scalar() return false end
    function Stencil.StencilAccessLayout:stencil_artifact_abi_ty(access_ty) return Code.CodeTyDataPtr(access_ty) end

    -- StencilSink leaf methods
    function Stencil.StencilSinkStore:stencil_artifact_is_reduce() return false end
    function Stencil.StencilSinkReduce:stencil_artifact_is_reduce() return true end
    function Stencil.StencilSinkScan:stencil_artifact_is_reduce() return false end
    function Stencil.StencilSink:stencil_artifact_is_reduce() return false end
    function Stencil.StencilSinkStore:stencil_artifact_is_store() return true end
    function Stencil.StencilSink:stencil_artifact_is_store() return false end

    -- StencilSink materializer and auto_vector leaf methods
    function Stencil.StencilSink:stencil_artifact_sink_materializer_reject_reason(producer)
        return "unknown stencil sink"
    end
    function Stencil.StencilSinkStore:stencil_artifact_sink_materializer_reject_reason(producer) return nil end
    function Stencil.StencilSinkReduce:stencil_artifact_sink_materializer_reject_reason(producer)
        return self.scope:stencil_artifact_materializer_reject_reason(producer)
    end
    function Stencil.StencilSinkScan:stencil_artifact_sink_materializer_reject_reason(producer)
        return axis_ref_invalid_reason(self.axis, producer, "scan axis")
    end
    function Stencil.StencilSinkScatterReduce:stencil_artifact_sink_materializer_reject_reason(producer)
        if self.conflicts == Stencil.StencilScatterReduceSequential or self.conflicts == Stencil.StencilScatterReduceUniqueIndices then return nil end
        if self.conflicts:stencil_artifact_is_atomic() then return "atomic scatter-reduce is represented but not materialized yet" end
        if self.conflicts == Stencil.StencilScatterReducePrivatized then return "privatized scatter-reduce is represented but not materialized yet" end
        return "unknown scatter-reduce conflict semantics"
    end

    function Stencil.StencilSink:stencil_artifact_is_auto_vector() return false end
    function Stencil.StencilSinkScan:stencil_artifact_is_auto_vector() return true end
    function Stencil.StencilSinkScatterReduce:stencil_artifact_is_auto_vector() return false end
    function Stencil.StencilSinkStore:stencil_artifact_is_auto_vector()
        return not self.semantics:stencil_artifact_is_partition()
    end
    function Stencil.StencilSinkReduce:stencil_artifact_is_auto_vector()
        return not self.semantics:stencil_artifact_is_find()
    end

    -- StencilReduceScope materializer and domain leaf methods
    function Stencil.StencilReduceScope:stencil_artifact_materializer_reject_reason(producer)
        return "unknown reduce sink scope"
    end
    function Stencil.StencilReduceScopeDomain:stencil_artifact_materializer_reject_reason(producer) return nil end
    function Stencil.StencilReduceScopeAxes:stencil_artifact_materializer_reject_reason(producer)
        local reason = axis_set_invalid_reason(self.axes, producer, "reduce axis scope")
        if reason ~= nil then return reason end
        return nil
    end
    function Stencil.StencilReduceScopeWindow:stencil_artifact_materializer_reject_reason(producer)
        local shape = producer_shape(producer)
        if not shape:stencil_artifact_is_window_nd() then return "window-local reduction requires a WindowND producer" end
        local reason = axis_set_invalid_reason(self.axes, producer, "window reduction scope")
        if reason ~= nil then return reason end
        return nil
    end

    function Stencil.StencilReduceScope:stencil_artifact_is_domain() return false end
    function Stencil.StencilReduceScopeDomain:stencil_artifact_is_domain() return true end

    -- StencilScatterReduceConflictSemantics leaf methods
    function Stencil.StencilScatterReduceAtomic:stencil_artifact_is_atomic() return true end
    function Stencil.StencilScatterReduceConflictSemantics:stencil_artifact_is_atomic() return false end

    -- StencilProducer leaf methods
    function Stencil.StencilProducer:stencil_artifact_is_producer() return true end
    function Stencil.StencilAccessLayout:stencil_artifact_is_producer() return false end

    -- StencilLanePolicy leaf methods
    function Stencil.StencilLaneFixed:stencil_artifact_is_fixed_lane() return true end
    function Stencil.StencilLanePolicy:stencil_artifact_is_fixed_lane() return false end
    -- StencilReduceSemantics / StencilSinkSemantics leaf methods
    function Stencil.StencilReduceFold:stencil_artifact_is_fold() return true end
    function Stencil.StencilReduceFold:stencil_artifact_is_partition() return false end
    function Stencil.StencilReduceFold:stencil_artifact_is_find() return false end
    function Stencil.StencilStorePartition:stencil_artifact_is_fold() return false end
    function Stencil.StencilStorePartition:stencil_artifact_is_partition() return true end
    function Stencil.StencilStorePartition:stencil_artifact_is_find() return false end
    function Stencil.StencilReduceFind:stencil_artifact_is_fold() return false end
    function Stencil.StencilReduceFind:stencil_artifact_is_partition() return false end
    function Stencil.StencilReduceFind:stencil_artifact_is_find() return true end
    function Stencil.StencilSinkSemantics:stencil_artifact_is_fold() return false end
    function Stencil.StencilSinkSemantics:stencil_artifact_is_partition() return false end
    function Stencil.StencilSinkSemantics:stencil_artifact_is_find() return false end

    -- StencilBody leaf methods
    function Stencil.StencilBodyPoint:stencil_artifact_is_point() return true end
    function Stencil.StencilBody:stencil_artifact_is_point() return false end

    -- StencilProducer / StencilProducerShape leaf methods
    function Stencil.StencilProducer:stencil_artifact_shape() return self.shape end
    function Stencil.StencilProduceRange1D:stencil_artifact_is_range_1d() return true end
    function Stencil.StencilProduceRange1D:stencil_artifact_is_window_nd() return false end
    function Stencil.StencilProduceRange1D:stencil_artifact_range_step() return tonumber(self.step) or 1 end
    function Stencil.StencilProduceRange1D:stencil_artifact_producer_tag() return (self.order == Stencil.StencilProducerBackward and "b" or "f") .. "s" .. tostring(self.step) end
    function Stencil.StencilProduceWindowND:stencil_artifact_is_range_1d() return false end
    function Stencil.StencilProduceWindowND:stencil_artifact_is_window_nd() return true end
    function Stencil.StencilProduceWindowND:stencil_artifact_range_step() return 1 end
    function Stencil.StencilProducerShape:stencil_artifact_is_range_1d() return false end
    function Stencil.StencilProducerShape:stencil_artifact_is_window_nd() return false end
    function Stencil.StencilProducerShape:stencil_artifact_range_step() return nil end
    function Stencil.StencilProducerShape:stencil_artifact_producer_tag() return "" end

    -- canonically normalize a producer shape into a fresh Producer
    function Stencil.StencilProducerShape:stencil_artifact_canonical_producer()
        return Stencil.StencilProducer(nil, self)
    end
    function Stencil.StencilProduceRange1D:stencil_artifact_canonical_producer()
        return Stencil.StencilProducer(
            nil,
            Stencil.StencilProduceRange1D(self.index_ty, nil, nil, self.step, self.order)
        )
    end
    function Stencil.StencilProduceRangeND:stencil_artifact_canonical_producer()
        local axes = {}
        for i, axis in ipairs(self.axes or {}) do axes[i] = canonical_axis(axis) end
        return Stencil.StencilProducer(nil, Stencil.StencilProduceRangeND(axes))
    end
    function Stencil.StencilProduceWindowND:stencil_artifact_canonical_producer()
        local axes = {}
        for i, axis in ipairs(self.axes or {}) do axes[i] = canonical_axis(axis) end
        return Stencil.StencilProducer(nil, Stencil.StencilProduceWindowND(axes, self.windows or {}))
    end
    function Stencil.StencilProduceTiledND:stencil_artifact_canonical_producer()
        local axes = {}
        for i, axis in ipairs(self.axes or {}) do axes[i] = canonical_axis(axis) end
        return Stencil.StencilProducer(nil, Stencil.StencilProduceTiledND(axes, self.tile_sizes or {}))
    end

    -- number of producer axes (rank)
    function Stencil.StencilProducerShape:stencil_artifact_producer_axis_count() return 0 end
    function Stencil.StencilProduceRange1D:stencil_artifact_producer_axis_count() return 1 end
    function Stencil.StencilProduceRangeND:stencil_artifact_producer_axis_count() return #(self.axes or {}) end
    function Stencil.StencilProduceWindowND:stencil_artifact_producer_axis_count() return #(self.axes or {}) end
    function Stencil.StencilProduceTiledND:stencil_artifact_producer_axis_count() return #(self.axes or {}) end

    -- validate producer shape; returns nil on success, error string on failure
    function Stencil.StencilProducerShape:stencil_artifact_producer_reject_reason()
        return "unknown stencil producer kind"
    end
    function Stencil.StencilProduceRange1D:stencil_artifact_producer_reject_reason()
        if (tonumber(self.step) or 0) <= 0 then return "1D stencil producer step must be a positive compile-time constant" end
        return nil
    end
    function Stencil.StencilProduceRangeND:stencil_artifact_producer_reject_reason()
        if #(self.axes or {}) == 0 then return "ND stencil producer requires at least one axis" end
        for i, axis in ipairs(self.axes or {}) do
            local reason = producer_axis_invalid_reason(axis, i)
            if reason ~= nil then return reason end
        end
        return nil
    end
    function Stencil.StencilProduceWindowND:stencil_artifact_producer_reject_reason()
        if #(self.axes or {}) == 0 then return "ND stencil producer requires at least one axis" end
        for i, axis in ipairs(self.axes or {}) do
            local reason = producer_axis_invalid_reason(axis, i)
            if reason ~= nil then return reason end
        end
        if #(self.windows or {}) ~= #(self.axes or {}) then
            return "windowed stencil producer requires one window per axis"
        end
        for i, window in ipairs(self.windows or {}) do
            local reason = producer_window_invalid_reason(window, i)
            if reason ~= nil then return reason end
        end
        return nil
    end
    function Stencil.StencilProduceTiledND:stencil_artifact_producer_reject_reason()
        if #(self.axes or {}) == 0 then return "ND stencil producer requires at least one axis" end
        for i, axis in ipairs(self.axes or {}) do
            local reason = producer_axis_invalid_reason(axis, i)
            if reason ~= nil then return reason end
        end
        if #(self.tile_sizes or {}) ~= #(self.axes or {}) then
            return "tiled stencil producer requires one tile size per axis"
        end
        for i, tile in ipairs(self.tile_sizes or {}) do
            if (tonumber(tile) or 0) <= 0 then
                return "tiled stencil producer tile size " .. tostring(i) .. " must be positive"
            end
        end
        return nil
    end

    -- whether the producer shape can be materialized (forward iteration only)
    function Stencil.StencilProducerShape:stencil_artifact_is_materialized() return false end
    function Stencil.StencilProduceRange1D:stencil_artifact_is_materialized() return true end
    function Stencil.StencilProduceRangeND:stencil_artifact_is_materialized()
        return producer_axes_forward(self.axes)
    end
    function Stencil.StencilProduceWindowND:stencil_artifact_is_materialized()
        return producer_axes_forward(self.axes)
    end
    function Stencil.StencilProduceTiledND:stencil_artifact_is_materialized()
        return producer_axes_forward(self.axes)
    end

    -- materializer reject reason (nil = ok)
    function Stencil.StencilProducerShape:stencil_artifact_materializer_reject_reason()
        return "unknown stencil producer kind"
    end
    function Stencil.StencilProduceRange1D:stencil_artifact_materializer_reject_reason() return nil end
    function Stencil.StencilProduceRangeND:stencil_artifact_materializer_reject_reason()
        if not producer_axes_forward(self.axes) then
            return "backward ND range axes are represented but not materialized yet"
        end
        return nil
    end
    function Stencil.StencilProduceWindowND:stencil_artifact_materializer_reject_reason()
        if not producer_axes_forward(self.axes) then
            return "backward windowed ND axes are represented but not materialized yet"
        end
        return nil
    end
    function Stencil.StencilProduceTiledND:stencil_artifact_materializer_reject_reason()
        if not producer_axes_forward(self.axes) then
            return "backward tiled ND axes are represented but not materialized yet"
        end
        return nil
    end

    -- producer tag (human-readable key suffix)
    function Stencil.StencilProduceRangeND:stencil_artifact_producer_tag()
        local axes = self.axes or {}
        local steps, non_unit = {}, false
        for i, axis in ipairs(axes) do
            local step = tonumber(axis.step) or 1
            steps[i] = tostring(step)
            if step ~= 1 then non_unit = true end
        end
        local suffix = non_unit and ("_s" .. table.concat(steps, "x")) or ""
        return "range_nd" .. tostring(#axes) .. suffix
    end
    function Stencil.StencilProduceWindowND:stencil_artifact_producer_tag()
        local axes = self.axes or {}
        local steps, non_unit = {}, false
        for i, axis in ipairs(axes) do
            local step = tonumber(axis.step) or 1
            steps[i] = tostring(step)
            if step ~= 1 then non_unit = true end
        end
        local suffix = non_unit and ("_s" .. table.concat(steps, "x")) or ""
        return "window_nd" .. tostring(#axes) .. suffix
    end
    function Stencil.StencilProduceTiledND:stencil_artifact_producer_tag()
        local axes = self.axes or {}
        local steps, non_unit = {}, false
        for i, axis in ipairs(axes) do
            local step = tonumber(axis.step) or 1
            steps[i] = tostring(step)
            if step ~= 1 then non_unit = true end
        end
        local suffix = non_unit and ("_s" .. table.concat(steps, "x")) or ""
        return "tiled_nd" .. tostring(#axes) .. suffix
    end

    -- append ABI types and C arg decls for a producer's shape
    function Stencil.StencilProducerShape:stencil_artifact_append_producer_params(abi, args)
        error("stencil_artifact_plan: unsupported producer ABI: unknown shape", 3)
    end
    function Stencil.StencilProduceRange1D:stencil_artifact_append_producer_params(abi, args)
        abi[#abi + 1] = i32_ty()
        abi[#abi + 1] = i32_ty()
        args[#args + 1] = "int32_t start"
        args[#args + 1] = "int32_t stop"
    end
    function Stencil.StencilProduceRangeND:stencil_artifact_append_producer_params(abi, args)
        for axis_index = 1, #(self.axes or {}) do
            abi[#abi + 1] = i32_ty()
            abi[#abi + 1] = i32_ty()
            args[#args + 1] = "int32_t " .. producer_param_name(axis_index, "start")
            args[#args + 1] = "int32_t " .. producer_param_name(axis_index, "stop")
        end
    end
    function Stencil.StencilProduceWindowND:stencil_artifact_append_producer_params(abi, args)
        for axis_index = 1, #(self.axes or {}) do
            abi[#abi + 1] = i32_ty()
            abi[#abi + 1] = i32_ty()
            args[#args + 1] = "int32_t " .. producer_param_name(axis_index, "start")
            args[#args + 1] = "int32_t " .. producer_param_name(axis_index, "stop")
        end
    end
    function Stencil.StencilProduceTiledND:stencil_artifact_append_producer_params(abi, args)
        for axis_index = 1, #(self.axes or {}) do
            abi[#abi + 1] = i32_ty()
            abi[#abi + 1] = i32_ty()
            args[#args + 1] = "int32_t " .. producer_param_name(axis_index, "start")
            args[#args + 1] = "int32_t " .. producer_param_name(axis_index, "stop")
        end
    end

    -- StencilSchedule leaf methods
    function Stencil.StencilScheduleVector:stencil_artifact_is_vector() return true end
    function Stencil.StencilScheduleVector:stencil_artifact_is_scalar() return false end
    function Stencil.StencilScheduleVector:stencil_artifact_lane_count()
        local policy = self.lane_policy
        if policy and policy and policy:stencil_artifact_is_fixed_lane() then return tonumber(policy.lanes) end
        return nil
    end
    function Stencil.StencilScheduleScalar:stencil_artifact_is_vector() return false end
    function Stencil.StencilScheduleScalar:stencil_artifact_is_scalar() return true end
    function Stencil.StencilScheduleScalar:stencil_artifact_lane_count() return nil end
    function Stencil.StencilSchedule:stencil_artifact_is_vector() return false end
    function Stencil.StencilSchedule:stencil_artifact_is_scalar() return false end
    function Stencil.StencilSchedule:stencil_artifact_lane_count() return nil end
    -- schedule key/suffix/name/cost leaf methods defined after helpers below

    -- StencilRealizedSchedule leaf methods
    function Stencil.StencilRealizedSchedule:stencil_artifact_is_realized_scalar() return false end
    function Stencil.StencilRealizedScalar:stencil_artifact_is_realized_scalar() return true end
    function Stencil.StencilRealizedSchedule:stencil_artifact_is_realized_vector() return false end
    function Stencil.StencilRealizedVector:stencil_artifact_is_realized_vector() return true end
    function Stencil.StencilRealizedUnrolled:stencil_artifact_is_realized_vector() return false end
    function Stencil.StencilRealizedSchedule:stencil_artifact_is_realized_unrolled_with_factor(factor) return false end
    function Stencil.StencilRealizedUnrolled:stencil_artifact_is_realized_unrolled_with_factor(factor)
        return tonumber(self.factor) == tonumber(factor)
    end

    -- StencilRealizedScheduleEvidence leaf methods
    function Stencil.StencilRealizedScheduleEvidence:stencil_artifact_append_diagnostic(out) end
    function Stencil.StencilRealizedByConstruction:stencil_artifact_append_diagnostic(out)
        out[#out + 1] = Stencil.StencilArtifactDiagnostic(
            Stencil.StencilArtifactDiagnosticNote,
            "realized-schedule",
            self.reason
        )
    end
    function Stencil.StencilRealizedCompilerRemark:stencil_artifact_append_diagnostic(out)
        out[#out + 1] = Stencil.StencilArtifactDiagnostic(
            Stencil.StencilArtifactDiagnosticRemark,
            "compiler",
            self.remark
        )
    end
    function Stencil.StencilRealizedDisassembly:stencil_artifact_append_diagnostic(out)
        out[#out + 1] = Stencil.StencilArtifactDiagnostic(
            Stencil.StencilArtifactDiagnosticRemark,
            "disassembly",
            self.classification
        )
    end

    -- StencilLayout leaf methods
    function Stencil.StencilLayoutIndexed:stencil_artifact_is_indexed() return true end
    function Stencil.StencilLayoutIndexed:stencil_artifact_is_field_or_soa() return false end
    function Stencil.StencilLayoutFieldProjection:stencil_artifact_is_indexed() return false end
    function Stencil.StencilLayoutFieldProjection:stencil_artifact_is_field_or_soa() return true end
    function Stencil.StencilLayoutFieldProjection:stencil_artifact_parent_layout() return self.parent end
    function Stencil.StencilLayoutSoAComponent:stencil_artifact_is_indexed() return false end
    function Stencil.StencilLayoutSoAComponent:stencil_artifact_is_field_or_soa() return true end
    function Stencil.StencilLayoutSoAComponent:stencil_artifact_parent_layout() return self.parent end
    function Stencil.StencilLayoutAffine1D:stencil_artifact_is_indexed() return false end
    function Stencil.StencilLayoutAffine1D:stencil_artifact_is_field_or_soa() return false end
    function Stencil.StencilLayoutAffine1D:stencil_artifact_scale() return tonumber(self.scale) or 0 end
    function Stencil.StencilLayoutAffine1D:stencil_artifact_parent_layout() return self.parent end
    function Stencil.StencilLayout:stencil_artifact_is_indexed() return false end
    function Stencil.StencilLayout:stencil_artifact_is_field_or_soa() return false end
    function Stencil.StencilLayout:stencil_artifact_parent_layout() return nil end
    function Stencil.StencilLayout:stencil_artifact_scale() return 0 end

    -- has_dynamic_stride: true if the layout depends on a non-constant stride
    function Stencil.StencilAccessLayout:stencil_artifact_has_dynamic_stride() return false end
    function Stencil.StencilLayoutFieldProjection:stencil_artifact_has_dynamic_stride()
        return self.parent:stencil_artifact_has_dynamic_stride()
    end
    function Stencil.StencilLayoutSoAComponent:stencil_artifact_has_dynamic_stride()
        return self.parent:stencil_artifact_has_dynamic_stride()
    end
    function Stencil.StencilLayoutAffine1D:stencil_artifact_has_dynamic_stride()
        return self.parent:stencil_artifact_has_dynamic_stride()
    end
    function Stencil.StencilLayoutAffineND:stencil_artifact_has_dynamic_stride()
        return self.parent:stencil_artifact_has_dynamic_stride()
    end
    function Stencil.StencilLayoutIndexed:stencil_artifact_has_dynamic_stride()
        return self.parent:stencil_artifact_has_dynamic_stride()
    end
    function Stencil.StencilLayoutViewDescriptor:stencil_artifact_has_dynamic_stride()
        return self.stride_const == nil
    end

    -- has_affine_offset: true if any ancestor is affine with a dynamic offset
    function Stencil.StencilAccessLayout:stencil_artifact_has_affine_offset() return false end
    function Stencil.StencilLayoutFieldProjection:stencil_artifact_has_affine_offset()
        return self.parent:stencil_artifact_has_affine_offset()
    end
    function Stencil.StencilLayoutSoAComponent:stencil_artifact_has_affine_offset()
        return self.parent:stencil_artifact_has_affine_offset()
    end
    function Stencil.StencilLayoutIndexed:stencil_artifact_has_affine_offset()
        return self.parent:stencil_artifact_has_affine_offset()
    end
    function Stencil.StencilLayoutAffine1D:stencil_artifact_has_affine_offset()
        return self.offset ~= nil or self.parent:stencil_artifact_has_affine_offset()
    end
    function Stencil.StencilLayoutAffineND:stencil_artifact_has_affine_offset()
        return self.offset ~= nil or self.parent:stencil_artifact_has_affine_offset()
    end

    -- field_layout: returns the innermost FieldProjection ancestor, or nil
    function Stencil.StencilAccessLayout:stencil_artifact_field_layout() return nil end
    function Stencil.StencilLayoutFieldProjection:stencil_artifact_field_layout() return self end
    function Stencil.StencilLayoutAffine1D:stencil_artifact_field_layout()
        return self.parent:stencil_artifact_field_layout()
    end
    function Stencil.StencilLayoutAffineND:stencil_artifact_field_layout()
        return self.parent:stencil_artifact_field_layout()
    end

    -- layout_suffix_for: build a stable suffix string from the layout tree
    function Stencil.StencilAccessLayout:stencil_artifact_layout_suffix_for(access) return "" end
    function Stencil.StencilLayoutViewDescriptor:stencil_artifact_layout_suffix_for(access)
        return "_view_" .. (self.stride_const ~= nil and ("s" .. tostring(self.stride_const)) or "sdyn")
    end
    function Stencil.StencilLayoutFieldProjection:stencil_artifact_layout_suffix_for(access)
        return self.parent:stencil_artifact_layout_suffix_for(access) .. "_field_" .. sanitize(self.field_name) .. "_o" .. tostring(self.field_offset or 0)
    end
    function Stencil.StencilLayoutSoAComponent:stencil_artifact_layout_suffix_for(access)
        return self.parent:stencil_artifact_layout_suffix_for(access) .. "_soa_" .. sanitize(self.field_name) .. "_c" .. tostring(self.component_index or 0)
    end
    function Stencil.StencilLayoutAffine1D:stencil_artifact_layout_suffix_for(access)
        local scale = tonumber(self.scale) or 1
        local scale_tag = scale < 0 and ("m" .. tostring(math.abs(scale))) or ("p" .. tostring(scale))
        local offset_tag = self.offset ~= nil and "odyn" or "o0"
        return self.parent:stencil_artifact_layout_suffix_for(access) .. "_aff1d_" .. scale_tag .. "_" .. offset_tag
    end
    function Stencil.StencilLayoutAffineND:stencil_artifact_layout_suffix_for(access)
        local parts = {}
        for _, term in ipairs(self.terms or {}) do
            parts[#parts + 1] = "a" .. tostring(term.axis.index)
        end
        local offset_tag = self.offset ~= nil and "odyn" or "o0"
        return self.parent:stencil_artifact_layout_suffix_for(access) .. "_affnd_" .. table.concat(parts, "x") .. "_" .. offset_tag
    end
    function Stencil.StencilLayoutSliceDescriptor:stencil_artifact_layout_suffix_for(access)
        return "_slice"
    end
    function Stencil.StencilLayoutByteSpanDescriptor:stencil_artifact_layout_suffix_for(access)
        return "_bytespan"
    end

    -- collect_layout_inputs: gather indexed access names from the layout tree
    function Stencil.StencilAccessLayout:stencil_artifact_collect_layout_inputs(seen, out) end
    function Stencil.StencilLayoutIndexed:stencil_artifact_collect_layout_inputs(seen, out)
        local name = self.index.name
        if not seen[name] then
            seen[name] = true
            out[#out + 1] = name
        end
        self.parent:stencil_artifact_collect_layout_inputs(seen, out)
    end
    function Stencil.StencilLayoutFieldProjection:stencil_artifact_collect_layout_inputs(seen, out)
        self.parent:stencil_artifact_collect_layout_inputs(seen, out)
    end
    function Stencil.StencilLayoutSoAComponent:stencil_artifact_collect_layout_inputs(seen, out)
        self.parent:stencil_artifact_collect_layout_inputs(seen, out)
    end

    -- StencilPointExpr leaf methods
    function Stencil.StencilPointInput:stencil_artifact_is_input() return true end
    function Stencil.StencilPointExpr:stencil_artifact_is_input() return false end

    -- predicate extraction: Predicate and Select carry a pred; others error
    function Stencil.StencilPointExpr:stencil_artifact_point_predicate()
        error("stencil_artifact_plan: descriptor mode requires a predicate point expression", 3)
    end
    function Stencil.StencilPointPredicate:stencil_artifact_point_predicate() return self.pred end
    function Stencil.StencilPointSelect:stencil_artifact_point_predicate() return self.pred end

    -- window input validation: returns nil on success, error string on failure
    function Stencil.StencilPointExpr:stencil_artifact_window_input_reason(producer) return nil end
    function Stencil.StencilPointWindowInput:stencil_artifact_window_input_reason(producer)
        local shape = producer_shape(producer)
        if not shape:stencil_artifact_is_window_nd() then return "window-relative point input requires a WindowND producer" end
        local seen = {}
        for i, offset in ipairs(self.offsets or {}) do
            local reason = axis_ref_invalid_reason(offset.axis, producer, "window input offset " .. tostring(i))
            if reason ~= nil then return reason end
            if seen[offset.axis.index] then return "window input repeats axis " .. tostring(offset.axis.index) end
            seen[offset.axis.index] = true
        end
        return nil
    end
    function Stencil.StencilPointUnary:stencil_artifact_window_input_reason(producer)
        return self.arg:stencil_artifact_window_input_reason(producer)
    end
    function Stencil.StencilPointCast:stencil_artifact_window_input_reason(producer)
        return self.arg:stencil_artifact_window_input_reason(producer)
    end
    function Stencil.StencilPointPredicate:stencil_artifact_window_input_reason(producer)
        return self.arg:stencil_artifact_window_input_reason(producer)
    end
    function Stencil.StencilPointBinary:stencil_artifact_window_input_reason(producer)
        return self.left:stencil_artifact_window_input_reason(producer) or self.right:stencil_artifact_window_input_reason(producer)
    end
    function Stencil.StencilPointCompare:stencil_artifact_window_input_reason(producer)
        return self.left:stencil_artifact_window_input_reason(producer) or self.right:stencil_artifact_window_input_reason(producer)
    end
    function Stencil.StencilPointSelect:stencil_artifact_window_input_reason(producer)
        return self.cond:stencil_artifact_window_input_reason(producer)
            or self.then_expr:stencil_artifact_window_input_reason(producer)
            or self.else_expr:stencil_artifact_window_input_reason(producer)
    end

    -- collect referenced access names
    function Stencil.StencilPointExpr:stencil_artifact_collect_inputs(seen, out) end
    function Stencil.StencilPointInput:stencil_artifact_collect_inputs(seen, out)
        local name = self.access.name
        if not seen[name] then
            seen[name] = true
            out[#out + 1] = name
        end
    end
    function Stencil.StencilPointWindowInput:stencil_artifact_collect_inputs(seen, out)
        local name = self.access.name
        if not seen[name] then
            seen[name] = true
            out[#out + 1] = name
        end
    end
    function Stencil.StencilPointUnary:stencil_artifact_collect_inputs(seen, out)
        self.arg:stencil_artifact_collect_inputs(seen, out)
    end
    function Stencil.StencilPointCast:stencil_artifact_collect_inputs(seen, out)
        self.arg:stencil_artifact_collect_inputs(seen, out)
    end
    function Stencil.StencilPointPredicate:stencil_artifact_collect_inputs(seen, out)
        self.arg:stencil_artifact_collect_inputs(seen, out)
    end
    function Stencil.StencilPointBinary:stencil_artifact_collect_inputs(seen, out)
        self.left:stencil_artifact_collect_inputs(seen, out)
        self.right:stencil_artifact_collect_inputs(seen, out)
    end
    function Stencil.StencilPointCompare:stencil_artifact_collect_inputs(seen, out)
        self.left:stencil_artifact_collect_inputs(seen, out)
        self.right:stencil_artifact_collect_inputs(seen, out)
    end
    function Stencil.StencilPointSelect:stencil_artifact_collect_inputs(seen, out)
        self.cond:stencil_artifact_collect_inputs(seen, out)
        self.then_expr:stencil_artifact_collect_inputs(seen, out)
        self.else_expr:stencil_artifact_collect_inputs(seen, out)
    end
    function Stencil.StencilPointConst:stencil_artifact_collect_inputs(seen, out) end

    -- CodeType leaf methods
    function Code.CodeTyDataPtr:stencil_artifact_is_data_ptr() return true end
    function Code.CodeType:stencil_artifact_is_data_ptr() return false end

    -- StencilAlignment leaf methods
    function Stencil.StencilAlignmentKnown:stencil_artifact_alignment_bytes() return tonumber(self.bytes) end
    function Stencil.StencilAlignment:stencil_artifact_alignment_bytes() return nil end

    -- StencilScheduleReject leaf methods
    function Stencil.StencilScheduleRejectCompilerMatrix:stencil_artifact_is_compiler_matrix() return true end
    function Stencil.StencilScheduleReject:stencil_artifact_is_compiler_matrix() return false end

    -- StencilReject leaf methods
    function Stencil.StencilRejectSchedule:stencil_artifact_is_schedule_reject() return true end
    function Stencil.StencilReject:stencil_artifact_is_schedule_reject() return false end

    -- Leaf methods for stencil artifact naming (eliminate string dispatch)

    -- ReductionOp
    function Value.ReductionAdd:stencil_artifact_name() return "add" end
    function Value.ReductionMul:stencil_artifact_name() return "mul" end
    function Value.ReductionAnd:stencil_artifact_name() return "and" end
    function Value.ReductionOr:stencil_artifact_name() return "or" end
    function Value.ReductionXor:stencil_artifact_name() return "xor" end
    function Value.ReductionMin:stencil_artifact_name() return "min" end
    function Value.ReductionMax:stencil_artifact_name() return "max" end

    -- StencilUnaryOp
    function Stencil.StencilUnaryIdentity:stencil_artifact_name() return "identity" end
    function Stencil.StencilUnaryNeg:stencil_artifact_name() return "neg" end
    function Stencil.StencilUnaryBitNot:stencil_artifact_name() return "bitnot" end
    function Stencil.StencilUnaryBoolNot:stencil_artifact_name() return "boolnot" end

    -- StencilBinaryOp
    function Stencil.StencilBinaryAdd:stencil_artifact_name() return "add" end
    function Stencil.StencilBinarySub:stencil_artifact_name() return "sub" end
    function Stencil.StencilBinaryMul:stencil_artifact_name() return "mul" end
    function Stencil.StencilBinaryDiv:stencil_artifact_name() return "div" end
    function Stencil.StencilBinaryMod:stencil_artifact_name() return "mod" end
    function Stencil.StencilBinaryAnd:stencil_artifact_name() return "and" end
    function Stencil.StencilBinaryOr:stencil_artifact_name() return "or" end
    function Stencil.StencilBinaryXor:stencil_artifact_name() return "xor" end
    function Stencil.StencilBinaryShl:stencil_artifact_name() return "shl" end
    function Stencil.StencilBinaryLShr:stencil_artifact_name() return "lshr" end
    function Stencil.StencilBinaryAShr:stencil_artifact_name() return "ashr" end
    function Stencil.StencilBinaryMin:stencil_artifact_name() return "min" end
    function Stencil.StencilBinaryMax:stencil_artifact_name() return "max" end

    -- CmpOp
    function Core.CmpEq:stencil_artifact_name() return "eq" end
    function Core.CmpNe:stencil_artifact_name() return "ne" end
    function Core.CmpLt:stencil_artifact_name() return "lt" end
    function Core.CmpLe:stencil_artifact_name() return "le" end
    function Core.CmpGt:stencil_artifact_name() return "gt" end
    function Core.CmpGe:stencil_artifact_name() return "ge" end

    -- StencilPredicate
    function Stencil.StencilPredNonZero:stencil_artifact_name() return "nonzero" end
    function Stencil.StencilPredCompareConst:stencil_artifact_name() return self.cmp:stencil_artifact_name() end
    function Stencil.StencilPredRange:stencil_artifact_name() return "range_" .. self.lower_cmp:stencil_artifact_name() .. "_" .. self.upper_cmp:stencil_artifact_name() end
    function Stencil.StencilPredAnd:stencil_artifact_name() return "and" .. tostring(#(self.terms or {})) end
    function Stencil.StencilPredOr:stencil_artifact_name() return "or" .. tostring(#(self.terms or {})) end
    function Stencil.StencilPredNot:stencil_artifact_name() return "not_" .. self.term:stencil_artifact_name() end
    function Stencil.StencilPredIsNaN:stencil_artifact_name() return "isnan" end
    function Stencil.StencilPredIsInf:stencil_artifact_name() return "isinf" end
    function Stencil.StencilPredIsFinite:stencil_artifact_name() return "isfinite" end

    -- MachineCastOp
    function Core.MachineCastIdentity:stencil_artifact_name() return "identity" end
    function Core.MachineCastBitcast:stencil_artifact_name() return "bitcast" end
    function Core.MachineCastIreduce:stencil_artifact_name() return "ireduce" end
    function Core.MachineCastSextend:stencil_artifact_name() return "sext" end
    function Core.MachineCastUextend:stencil_artifact_name() return "uext" end
    function Core.MachineCastFpromote:stencil_artifact_name() return "fpromote" end
    function Core.MachineCastFdemote:stencil_artifact_name() return "fdemote" end
    function Core.MachineCastSToF:stencil_artifact_name() return "stof" end
    function Core.MachineCastUToF:stencil_artifact_name() return "utof" end
    function Core.MachineCastFToS:stencil_artifact_name() return "ftos" end
    function Core.MachineCastFToU:stencil_artifact_name() return "ftou" end

    -- StencilScanMode
    function Stencil.StencilScanInclusive:stencil_artifact_name() return "inclusive" end
    function Stencil.StencilScanExclusive:stencil_artifact_name() return "exclusive" end

    -- StencilCopySemantics
    function Stencil.StencilCopyNoOverlap:stencil_artifact_name() return "nooverlap" end
    function Stencil.StencilCopyMayOverlapForward:stencil_artifact_name() return "forward" end
    function Stencil.StencilCopyMayOverlapBackward:stencil_artifact_name() return "backward" end
    function Stencil.StencilCopyMemMove:stencil_artifact_name() return "memmove" end

    -- StencilPartitionSemantics
    function Stencil.StencilPartitionStable:stencil_artifact_name() return "stable" end
    function Stencil.StencilPartitionUnstable:stencil_artifact_name() return "unstable" end

    -- StencilScatterConflictSemantics
    function Stencil.StencilScatterUniqueIndices:stencil_artifact_name() return "unique" end
    function Stencil.StencilScatterLastWriteWins:stencil_artifact_name() return "last" end
    function Stencil.StencilScatterConflictUndefined:stencil_artifact_name() return "undefined" end

    -- StencilScatterReduceConflictSemantics
    function Stencil.StencilScatterReduceSequential:stencil_artifact_name() return "seq" end
    function Stencil.StencilScatterReduceUniqueIndices:stencil_artifact_name() return "unique" end
    function Stencil.StencilScatterReduceAtomic:stencil_artifact_name() return "atomic" end
    function Stencil.StencilScatterReducePrivatized:stencil_artifact_name() return "privatized" end


    local function proof_list(plan)
        local eq = plan and plan.body and plan.body.equivalence
        return eq and eq:stencil_artifact_proofs() or {}
    end

    function Kernel.KernelEquivalenceProof:stencil_artifact_proofs() return self.proofs or {} end
    function Kernel.KernelEquivalenceRejected:stencil_artifact_proofs() return {} end

    local function reduce_instance_id(elem_ty, result_ty, reduction, stride)
        return Stencil.StencilInstanceId("stencil:reduce_array:" .. type_name(elem_ty) .. ":" .. reduction:stencil_artifact_name() .. ":to:" .. type_name(result_ty) .. ":stride" .. tostring(stride))
    end

    local function reduce_symbol_id(elem_ty, result_ty, reduction, stride)
        return Stencil.StencilSymbolId("ml_stencil_reduce_array_" .. type_name(elem_ty) .. "_" .. reduction:stencil_artifact_name() .. "_to_" .. type_name(result_ty) .. "_s" .. tostring(stride))
    end

    local function scalar_param_ty(ty)
        return c_type(ty)
    end

    local function const_elem_ptr_decl(ty, name)
        return c_type(ty) .. " const *" .. name
    end

    local function access_abi_ty(access)
        if access.layout:stencil_artifact_is_scalar() then return access.ty end
        return Code.CodeTyDataPtr(access.ty)
    end

    local function access_arg_decl(access, mutable)
        if access.layout:stencil_artifact_is_scalar() then return c_type(access.ty) .. " " .. access.name end
        if mutable then return c_type(access.ty) .. " *" .. access.name end
        return const_elem_ptr_decl(access.ty, access.name)
    end

    local function void_decl(symbol, args)
        return "void " .. symbol.text .. "(" .. table.concat(args, ", ") .. ");"
    end

    local function result_decl(symbol, result_ty, args)
        return c_type(result_ty) .. " " .. symbol.text .. "(" .. table.concat(args, ", ") .. ");"
    end

    local function int32_decl(symbol, args)
        return "int32_t " .. symbol.text .. "(" .. table.concat(args, ", ") .. ");"
    end

    -- Boolean type predicate leaf methods
    function Code.CodeTyInt:stencil_artifact_is_int() return true end
    function Code.CodeTyInt:stencil_artifact_is_integer_like() return true end
    function Code.CodeTyInt:stencil_artifact_is_float() return false end
    function Code.CodeTyIndex:stencil_artifact_is_int() return false end
    function Code.CodeTyIndex:stencil_artifact_is_integer_like() return true end
    function Code.CodeTyIndex:stencil_artifact_is_float() return false end
    function Code.CodeTyFloat:stencil_artifact_is_int() return false end
    function Code.CodeTyFloat:stencil_artifact_is_integer_like() return false end
    function Code.CodeTyFloat:stencil_artifact_is_float() return true end
    function Code.CodeTyBool8:stencil_artifact_is_int() return false end
    function Code.CodeTyBool8:stencil_artifact_is_integer_like() return true end
    function Code.CodeTyBool8:stencil_artifact_is_float() return false end
    function Code.CodeType:stencil_artifact_is_int() return false end
    function Code.CodeType:stencil_artifact_is_integer_like() return false end
    function Code.CodeType:stencil_artifact_is_float() return false end

    local function same_source_type(a, b)
        if a == b then return true end
        if a == nil or b == nil then return false end
        return tostring(a) == tostring(b)
    end

    local function same_type(a, b)
        if a == b then return true end
    -- GATING: same_type must check class equality first — comparing Int.bits against Float.bits is nonsense.
    -- The classof gate is a structural necessity, not behavioral dispatch.
        local ac, bc = asdl.classof(a), asdl.classof(b)
        if ac ~= bc then return false end
        if ac == Code.CodeTyInt then return a.bits == b.bits and a.signedness == b.signedness end
        if ac == Code.CodeTyFloat then return a.bits == b.bits end
        if ac == Code.CodeTyDataPtr then
            if a.pointee == nil or b.pointee == nil then return a.pointee == b.pointee end
            return same_type(a.pointee, b.pointee)
        end
        if ac == Code.CodeTyCodePtr then return a.sig == b.sig end
        if ac == Code.CodeTyNamed then return a.module_name == b.module_name and a.type_name == b.type_name end
        if ac == Code.CodeTyArray then return a.count == b.count and same_type(a.elem, b.elem) end
        if ac == Code.CodeTySlice or ac == Code.CodeTyView then return same_type(a.elem, b.elem) end
        if ac == Code.CodeTyHandle then return same_type(a.repr, b.repr) and same_source_type(a.source_ty, b.source_ty) end
        if ac == Code.CodeTyLease then return same_type(a.base, b.base) and same_source_type(a.source_ty, b.source_ty) end
        if ac == Code.CodeTyClosure then return a.sig == b.sig end
        if ac == Code.CodeTyImportedC then return a.id == b.id or (a.id.module_name == b.id.module_name and a.id.spelling == b.id.spelling) end
        if ac == Code.CodeTyImportedCFuncPtr then return a.sig == b.sig end
        if ac == Code.CodeTyVector then return a.lanes == b.lanes and same_type(a.elem, b.elem) end
        return false
    end

    local function is_scalar(ty)
        return ty:stencil_artifact_is_code_scalar()
    end

    local function default_int_semantics()
        return Code.CodeIntSemantics(Code.CodeIntWrap, Code.CodeDivTrapOnZeroOrOverflow, Code.CodeShiftMaskCount)
    end

    local function element_int_semantics(ty, info)
    -- GATING: element_int_semantics gates on type class — only integer-like types (Int, Index, Bool8)
    -- carry integer semantics. This is a type classification gate, not behavioral dispatch.
        local cls = asdl.classof(ty)
        if cls ~= Code.CodeTyInt and ty ~= Code.CodeTyIndex and ty ~= Code.CodeTyBool8 then return nil end
        return info and (info.int_semantics or info.semantics) or default_int_semantics()
    end

    local function element_float_mode(ty, info)
        if not ty:stencil_artifact_is_float() then return nil end
        return info and info.float_mode or Code.CodeFloatStrict
    end

    local function input_expr(name)
        return Stencil.StencilPointInput(Stencil.StencilAccessRef(name))
    end

    local function axis_ref(index)
        index = tonumber(index or 1) or 1
        return Stencil.StencilAxisRef(index)
    end

    local function domain_reduce_scope()
        return Stencil.StencilReduceScopeDomain
    end

    local function reduce_scope_from_attrs(attrs)
        attrs = attrs or {}
        return attrs.reduce_scope or attrs.scope or domain_reduce_scope()
    end

    local function scan_axis_from_attrs(attrs)
        attrs = attrs or {}
        return attrs.scan_axis or attrs.axis or axis_ref(1)
    end

    local function const_expr(value, ty)
        return Stencil.StencilPointConst(value, ty)
    end

    local function point_unary_expr(op, arg, result_ty, info)
        return Stencil.StencilPointUnary(op, arg, result_ty, element_int_semantics(result_ty, info), element_float_mode(result_ty, info))
    end

    local function point_binary_expr(op, left, right, result_ty, info)
        return Stencil.StencilPointBinary(op, left, right, result_ty, element_int_semantics(result_ty, info), element_float_mode(result_ty, info))
    end

    local function point_predicate_expr(pred, arg, result_ty)
        return Stencil.StencilPointPredicate(pred, arg, result_ty)
    end

    local function point_compare_expr(cmp, left, right, result_ty)
        return Stencil.StencilPointCompare(cmp, left, right, result_ty)
    end

    local function point_cast_expr(op, arg, from, to)
        return Stencil.StencilPointCast(op, arg, from, to)
    end

    local function point_select_expr(pred, cond, then_expr, else_expr, result_ty)
        return Stencil.StencilPointSelect(pred, cond, then_expr, else_expr, result_ty)
    end

    local function predicate_checked(pred, operand_ty)
        return pred:stencil_artifact_validate(operand_ty)
    end

    function Stencil.StencilPredNonZero:stencil_artifact_validate(operand_ty) return self end
    function Stencil.StencilPredCompareConst:stencil_artifact_validate(operand_ty)
        if not same_type(self.operand_ty, operand_ty) then error("stencil_artifact_plan: predicate operand type does not match stencil element type", 3) end
        return self
    end
    function Stencil.StencilPredRange:stencil_artifact_validate(operand_ty)
        if not same_type(self.operand_ty, operand_ty) then error("stencil_artifact_plan: predicate operand type does not match stencil element type", 3) end
        return self
    end
    function Stencil.StencilPredIsNaN:stencil_artifact_validate(operand_ty)
        if not same_type(self.operand_ty, operand_ty) then error("stencil_artifact_plan: predicate operand type does not match stencil element type", 3) end
        if not operand_ty:stencil_artifact_is_float() then error("stencil_artifact_plan: float-class predicate requires a float operand type", 3) end
        return self
    end
    function Stencil.StencilPredIsInf:stencil_artifact_validate(operand_ty)
        if not same_type(self.operand_ty, operand_ty) then error("stencil_artifact_plan: predicate operand type does not match stencil element type", 3) end
        if not operand_ty:stencil_artifact_is_float() then error("stencil_artifact_plan: float-class predicate requires a float operand type", 3) end
        return self
    end
    function Stencil.StencilPredIsFinite:stencil_artifact_validate(operand_ty)
        if not same_type(self.operand_ty, operand_ty) then error("stencil_artifact_plan: predicate operand type does not match stencil element type", 3) end
        if not operand_ty:stencil_artifact_is_float() then error("stencil_artifact_plan: float-class predicate requires a float operand type", 3) end
        return self
    end
    function Stencil.StencilPredAnd:stencil_artifact_validate(operand_ty)
        for _, term in ipairs(self.terms or {}) do term:stencil_artifact_validate(operand_ty) end
        return self
    end
    function Stencil.StencilPredOr:stencil_artifact_validate(operand_ty)
        for _, term in ipairs(self.terms or {}) do term:stencil_artifact_validate(operand_ty) end
        return self
    end
    function Stencil.StencilPredNot:stencil_artifact_validate(operand_ty)
        self.term:stencil_artifact_validate(operand_ty)
        return self
    end
    function Stencil.StencilPredicate:stencil_artifact_validate(operand_ty) return self end

    local function supports_bitwise_ty(ty)
        return ty:stencil_artifact_is_int() or ty:stencil_artifact_is_integer_like() and not ty:stencil_artifact_is_int() and not ty:stencil_artifact_is_float()
    end

    local function supports_div_ty(ty)
        return ty:stencil_artifact_is_int() or ty:stencil_artifact_is_float() or ty:stencil_artifact_is_integer_like() and not ty:stencil_artifact_is_int()
    end

    local function supports_integer_arithmetic_ty(ty)
        return ty:stencil_artifact_is_int() or ty:stencil_artifact_is_integer_like() and not ty:stencil_artifact_is_int()
    end

    function api.reduce_array_supported(reduction, info)
        local elem_ty = info and info.elem_ty or nil
        local result_ty = info and info.result_ty or nil
        if elem_ty == nil or result_ty == nil then return false, "reduce_array stencil requires elem_ty and result_ty" end
        if not same_type(elem_ty, result_ty) then return false, "reduce_array stencil currently requires matching element/result types" end
        local ok_type, err = pcall(function() c_type(elem_ty); c_type(result_ty) end)
        if not ok_type then return false, tostring(err) end
        local op = reduction.op
        if result_ty:stencil_artifact_is_integer_like() then
            if op == Value.ReductionAdd or op == Value.ReductionMul
                or op == Value.ReductionAnd or op == Value.ReductionOr or op == Value.ReductionXor
                or op == Value.ReductionMin or op == Value.ReductionMax then
                return true
            end
            return false, "unsupported integer reduction"
        end
        if result_ty == Code.CodeTyBool8 then
            if op == Value.ReductionAnd or op == Value.ReductionOr or op == Value.ReductionXor then
                return true
            end
            return false, "bool8 reduce_array stencil only supports and/or/xor"
        end
        if result_ty:stencil_artifact_is_float() then
            if op == Value.ReductionAdd or op == Value.ReductionMul
                or op == Value.ReductionMin or op == Value.ReductionMax then
                return true
            end
            return false, "float reduce_array stencil only supports add/mul/min/max"
        end
        return false, "reduce_array stencil only supports integer, index, bool8, and float scalar types"
    end

    local function binary_supported(op, ty)
        if op == Stencil.StencilBinaryAnd or op == Stencil.StencilBinaryOr or op == Stencil.StencilBinaryXor then return supports_bitwise_ty(ty) end
        if op == Stencil.StencilBinaryDiv then return supports_div_ty(ty) end
        if op == Stencil.StencilBinaryMod then return supports_integer_arithmetic_ty(ty) end
        if op == Stencil.StencilBinaryShl or op == Stencil.StencilBinaryLShr or op == Stencil.StencilBinaryAShr then return supports_bitwise_ty(ty) end
        return is_scalar(ty)
    end

    local function unary_supported(op, ty)
        if op == Stencil.StencilUnaryIdentity then return ty ~= Code.CodeTyVoid end
        if op == Stencil.StencilUnaryBitNot then return supports_bitwise_ty(ty) end
        return is_scalar(ty)
    end

    local artifact

    local function i32_ty()
        return Code.CodeTyInt(32, Code.CodeSigned)
    end

    local function range1d_producer(stride, origin)
        return Stencil.StencilProducer(
            origin,
            Stencil.StencilProduceRange1D(Code.CodeTyIndex, nil, nil, tonumber(stride) or 1, Stencil.StencilProducerForward)
        )
    end

    local function canonical_axis(axis)
        return Stencil.StencilProducerAxis(axis.index_ty, nil, nil, axis.step, axis.order, axis.index_name)
    end

    local function canonical_producer(producer)
        local shape = producer and producer.shape or nil
        if shape == nil then return producer end
        return shape:stencil_artifact_canonical_producer()
    end

    local function producer_from_attrs(stride, attrs)
        attrs = attrs or {}
        return canonical_producer(attrs.producer or range1d_producer(stride, attrs.origin))
    end

    local function memory(opts)
        return opts or {}
    end

    local function attrs(info, extra)
        local out = {}
        for k, v in pairs(info or {}) do out[k] = v end
        for k, v in pairs(extra or {}) do out[k] = v end
        return out
    end

    local function contig(name, role, ty, stride)
        return Stencil.StencilAccess(name, role, ty, Stencil.StencilLayoutContiguous(tonumber(stride) or 1))
    end

    local function shaped(name, role, ty, layout, stride)
        return Stencil.StencilAccess(name, role, ty, layout or Stencil.StencilLayoutContiguous(1))
    end

    local function indexed(name, role, ty, index_ref, index_ty, stride)
        return Stencil.StencilAccess(name, role, ty, Stencil.StencilLayoutIndexed(
            Stencil.StencilLayoutContiguous(1),
            Stencil.StencilAccessRef(index_ref),
            index_ty,
            tonumber(stride) or 1
        ))
    end

    local function scalar(name, role, ty, value)
        return Stencil.StencilAccess(name, role, ty, Stencil.StencilLayoutScalar(value))
    end

    local function reducer_identity(reduction, result_ty)
        local identity, reason = ReductionAlgebra.identity_expr(reduction.op, result_ty)
        if identity == nil then error("stencil_artifact_plan: reduction has no identity: " .. tostring(reason), 3) end
        return identity
    end

    local function reducer_desc(reduction, result_ty)
        return Stencil.StencilReducer(reduction.op, result_ty, reducer_identity(reduction, result_ty), reduction.int_semantics, reduction.float_mode)
    end

    local function predicate_expr_pred(expr)
        return expr:stencil_artifact_point_predicate()
    end

    local function descriptor(sink, stride, accesses, expr, attrs, result_ty)
        attrs = attrs or {}
        local producer = producer_from_attrs(stride, attrs)
        local body = Stencil.StencilBodyPoint(expr or input_expr("xs"))
        return sink:stencil_artifact_build_descriptor(producer, accesses, body, result_ty)
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
    function Stencil.StencilSink:stencil_artifact_build_descriptor(producer, accesses, body, result_ty)
        error("stencil_artifact_plan: unsupported sink type for build_descriptor", 3)
    end

    local function descriptor_reduction_semantics(desc)
        if desc == nil or not desc.sink:stencil_artifact_is_reduce() then return nil end
        return desc.sink.semantics
    end

    local function descriptor_reducer(desc)
        if desc == nil then return nil end
        return desc.sink and desc.sink:stencil_artifact_reducer() or nil
    end

    function Stencil.StencilSinkScan:stencil_artifact_reducer() return self.reducer end
    function Stencil.StencilSinkScatterReduce:stencil_artifact_reducer() return self.reducer end
    function Stencil.StencilSinkReduce:stencil_artifact_reducer()
        if self.semantics:stencil_artifact_is_fold() then return self.semantics.reducer end
        return nil
    end
    function Stencil.StencilSinkStore:stencil_artifact_reducer() return nil end
    function Stencil.StencilSink:stencil_artifact_reducer() return nil end

    local function descriptor_expr(desc)
        if desc == nil or not desc.body:stencil_artifact_is_point() then
            error("stencil_artifact_plan: descriptor body is not an apply expression", 3)
        end
        return desc.body.expr
    end

    local function descriptor_accesses(desc)
        return desc and desc.accesses or {}
    end

    local function descriptor_producer(desc)
        return desc and desc.producer or nil
    end

    local function descriptor_access_identity_map(desc)
        local map = {}
        local input_i, output_i = 0, 0
        for _, access in ipairs(descriptor_accesses(desc)) do
            local role = access.role
            if role == Stencil.StencilAccessWrite
                or role == Stencil.StencilAccessReadWrite
                or role == Stencil.StencilAccessReduce
                or role == Stencil.StencilAccessControlResult then
                output_i = output_i + 1
                map[access.name] = output_i == 1 and "dst" or ("dst" .. tostring(output_i))
            else
                input_i = input_i + 1
                map[access.name] = "x" .. tostring(input_i)
            end
        end
        return map
    end

    local function descriptor_identity_repr(desc)
        local access_map = descriptor_access_identity_map(desc)
        local function repr(v, seen, owner_cls, field_name)
            local tv = type(v)
            if tv == "nil" then return "nil" end
            if tv == "boolean" or tv == "number" then return tostring(v) end
            if tv == "string" then
                if owner_cls == Stencil.StencilAccess and field_name == "name" then
                    return string.format("%q", access_map[v] or v)
                end
                return string.format("%q", v)
            end
            if tv ~= "table" then return tv .. ":" .. tostring(v) end
    -- GATING: access_repr is a cross-cutting serialization utility for stable descriptor identity,
    -- not semantic dispatch. Uses classof to distinguish StencilAccessRef from other ASDL values.
            local cls = asdl.classof(v)
            if cls == Stencil.StencilAccessRef then
                return tostring(cls) .. "{name=" .. string.format("%q", access_map[v.name] or v.name) .. "}"
            end
            if tostring(cls) == "Class(LalinCode.CodeValueId)" then return tostring(cls) .. "{_}" end
            if tostring(cls):match("^Class%(LalinFlow%.FlowDomain") then return tostring(cls) .. "{_}" end
            if tostring(cls) == "Class(LalinGraph.GraphLoopId)" then return tostring(cls) .. "{_}" end
            if tostring(cls) == "Class(LalinCode.CodeFuncId)" then return tostring(cls) .. "{_}" end
            seen = seen or {}
            if seen[v] then return "<cycle>" end
            seen[v] = true
            local out = {}
            if cls then
                out[#out + 1] = tostring(cls)
                out[#out + 1] = "{"
                for i, field in ipairs(asdl.fields(cls) or {}) do
                    if i > 1 then out[#out + 1] = "," end
                    out[#out + 1] = field.name
                    out[#out + 1] = "="
                    out[#out + 1] = repr(rawget(v, field.name), seen, cls, field.name)
                end
                out[#out + 1] = "}"
            else
                local keys = {}
                for key in pairs(v) do keys[#keys + 1] = key end
                table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
                out[#out + 1] = "{"
                for i, key in ipairs(keys) do
                    if i > 1 then out[#out + 1] = "," end
                    out[#out + 1] = repr(key, seen)
                    out[#out + 1] = "="
                    out[#out + 1] = repr(v[key], seen)
                end
                out[#out + 1] = "}"
            end
            seen[v] = nil
            return table.concat(out)
        end
        return repr(desc)
    end

    local function producer_shape(producer)
        if producer == nil then return nil end
        if producer:stencil_artifact_is_producer() then return producer.shape end
        return producer
    end

    local function producer_axis_count(producer)
        local shape = producer_shape(producer)
        if shape == nil then return 0 end
        return shape:stencil_artifact_producer_axis_count()
    end

    local function axis_ref_invalid_reason(axis, producer, site)
        site = site or "stencil axis"
        local idx = tonumber(axis and axis.index)
        if idx == nil or idx < 1 or math.floor(idx) ~= idx then return site .. " must be a positive integer axis index" end
        local rank = producer_axis_count(producer)
        if idx > rank then return site .. " " .. tostring(idx) .. " is outside producer rank " .. tostring(rank) end
        return nil
    end

    local function axis_set_invalid_reason(axes, producer, site)
        if #(axes or {}) == 0 then return (site or "axis set") .. " requires at least one axis" end
        local seen = {}
        for i, axis in ipairs(axes or {}) do
            local reason = axis_ref_invalid_reason(axis, producer, (site or "axis set") .. " axis " .. tostring(i))
            if reason ~= nil then return reason end
            if seen[axis.index] then return (site or "axis set") .. " repeats axis " .. tostring(axis.index) end
            seen[axis.index] = true
        end
        return nil
    end

    local function producer_axis_invalid_reason(axis, index)
        if axis == nil then return "producer axis " .. tostring(index) .. " is missing" end
        if (tonumber(axis.step) or 0) <= 0 then return "producer axis " .. tostring(index) .. " step must be a positive compile-time constant" end
        return nil
    end

    local function producer_window_invalid_reason(window, index)
        if window == nil then return "producer window " .. tostring(index) .. " is missing" end
        if (tonumber(window.before) or -1) < 0 then return "producer window " .. tostring(index) .. " before extent must be nonnegative" end
        if (tonumber(window.after) or -1) < 0 then return "producer window " .. tostring(index) .. " after extent must be nonnegative" end
        return nil
    end

    local function producer_shape_reject_reason(producer)
        local shape = producer_shape(producer)
        if shape == nil then return nil end
        return shape:stencil_artifact_producer_reject_reason()
    end

    local function producer_shape_supported(producer)
        return producer_shape_reject_reason(producer) == nil
    end

    local function producer_axes_forward(axes)
        for _, axis in ipairs(axes or {}) do
            if axis.order ~= Stencil.StencilProducerForward then return false end
        end
        return true
    end

    local function producer_materialized(producer)
        local shape = producer_shape(producer)
        if not producer_shape_supported(producer) then return false end
        return shape:stencil_artifact_is_materialized()
    end

    local function producer_materializer_reject_reason(producer)
        local shape = producer_shape(producer)
        local shape_reason = producer_shape_reject_reason(producer)
        if shape_reason ~= nil then return shape_reason end
        return shape:stencil_artifact_materializer_reject_reason()
    end

    local function unsupported_producer_reject(producer)
        local reason = producer_materializer_reject_reason(producer)
        if reason == nil then return nil end
        return Stencil.StencilRejectUnsupportedProducer(producer, reason)
    end

    local function expr_window_input_reason(expr, producer)
        return expr:stencil_artifact_window_input_reason(producer)
    end

    local function reduce_scope_materializer_reject_reason(scope, producer)
        return scope:stencil_artifact_materializer_reject_reason(producer)
    end

    local function sink_materializer_reject_reason(desc)
        if desc == nil or desc.sink == nil then return "missing stencil sink" end
        local producer = descriptor_producer(desc)
        local body_reason = expr_window_input_reason(descriptor_expr(desc), producer)
        if body_reason ~= nil then return body_reason end
        return desc.sink:stencil_artifact_sink_materializer_reject_reason(producer)
    end

    local function unsupported_sink_reject(desc)
        local reason = sink_materializer_reject_reason(desc)
        if reason == nil then return nil end
        return Stencil.StencilRejectUnsupportedSink(desc.sink, reason)
    end

    local function schedule_lane_count(schedule)
        if not schedule:stencil_artifact_is_vector() then return nil end
        local policy = schedule.lane_policy
        if policy and policy:stencil_artifact_is_fixed_lane() then return tonumber(policy.lanes) end
        return nil
    end

    local function realized_matches_request(schedule, realized)
        return schedule:stencil_artifact_matches_realized(realized)
    end

    local function schedule_rejects_for_realized(schedule, realized)
        if realized == nil or realized_matches_request(schedule, realized) then return {} end
        return {
            Stencil.StencilScheduleRejectRequestedRealizedMismatch(
                schedule,
                realized,
                "requested stencil schedule did not match materialized schedule"
            ),
        }
    end

    local function compiler_matrix_rejects(schedule)
        if not schedule:stencil_artifact_is_vector() then return {} end
        local compiler = schedule.compiler
        local vector_compiler = schedule.vector_compiler
        local cc = compiler and compiler.compiler or nil
        local reason
        if vector_compiler == Stencil.StencilVectorCompilerGccAutovec and cc ~= Stencil.StencilCompilerGcc then
            reason = "gcc autovec vector compiler requires gcc"
        elseif vector_compiler == Stencil.StencilVectorCompilerHandwritten and cc == Stencil.StencilCompilerSystemC then
            reason = "handwritten C vector compiler requires a C compiler"
        elseif vector_compiler == Stencil.StencilVectorCompilerCompiledStencil and cc ~= Stencil.StencilCompilerGcc then
            reason = "copy+compile residual stencil vector compiler is currently built by gcc"
        end
        if reason == nil then return {} end
        return {
            Stencil.StencilScheduleRejectCompilerMatrix(
                compiler,
                vector_compiler,
                reason
            ),
        }
    end

    local function variant_name(value)
        if value == nil then return "nil" end
        if type(value) == "table" then
            local text = rawget(value, "text")
            if text ~= nil then return text end
        end
    -- GATING: variant_name is a cross-cutting utility that extracts human-readable names from
    -- tostring(ASDL class). Not semantic dispatch — it operates on the string representation.
        local cls = asdl.classof(value)
        local s = tostring(cls or value)
        return s:match("([%w_]+)%)$") or s:match("%.([%w_]+)$") or s
    end

    local function provider_key(provider)
        return variant_name(provider)
    end

    local function compiler_policy_key(policy)
        if policy == nil then return "compiler:nil" end
        local flags = {}
        for i, flag in ipairs(policy.flags or {}) do flags[i] = tostring(flag) end
        return table.concat({
            variant_name(policy.compiler),
            variant_name(policy.opt_level),
            variant_name(policy.machine),
            table.concat(flags, ","),
        }, "/")
    end

    -- StencilSchedule key / suffix / name / cost leaf methods
    -- (must be after variant_name, compiler_policy_key, schedule_lane_count)

    function Stencil.StencilSchedule:stencil_artifact_schedule_key()
        return "schedule:" .. variant_name(self)
    end
    function Stencil.StencilScheduleScalar:stencil_artifact_schedule_key()
        return "scalar:" .. compiler_policy_key(self.compiler)
    end
    function Stencil.StencilScheduleAutoVector:stencil_artifact_schedule_key()
        return "autovector:" .. compiler_policy_key(self.compiler)
    end
    function Stencil.StencilScheduleUnrolled:stencil_artifact_schedule_key()
        return "unrolled:" .. tostring(self.factor) .. ":" .. compiler_policy_key(self.compiler)
    end
    function Stencil.StencilScheduleVector:stencil_artifact_schedule_key()
        return table.concat({
            "vector",
            variant_name(self.feature),
            variant_name(self.lane_policy),
            tostring(schedule_lane_count(self) or "target"),
            variant_name(self.required_alignment),
            variant_name(self.tail),
            variant_name(self.reduction),
            variant_name(self.vector_compiler),
            tostring(self.vector_unroll),
            tostring(self.interleave),
            compiler_policy_key(self.compiler),
        }, ":")
    end

    function Stencil.StencilSchedule:stencil_artifact_schedule_suffix() return "", "" end
    function Stencil.StencilScheduleVector:stencil_artifact_schedule_suffix()
        local lanes = schedule_lane_count(self)
        local lane_suffix = lanes and tostring(lanes) or "target"
        local unroll = tonumber(self.vector_unroll) or 1
        local interleave = tonumber(self.interleave) or 1
        return ":v" .. lane_suffix .. (unroll > 1 and (":vu" .. tostring(unroll)) or "") .. (interleave > 1 and (":i" .. tostring(interleave)) or ""),
            "_v" .. lane_suffix .. (unroll > 1 and ("_vu" .. tostring(unroll)) or "") .. (interleave > 1 and ("_i" .. tostring(interleave)) or "")
    end
    function Stencil.StencilScheduleUnrolled:stencil_artifact_schedule_suffix()
        return ":u" .. tostring(self.factor), "_u" .. tostring(self.factor)
    end

    function Stencil.StencilSchedule:stencil_artifact_schedule_candidate_name() return "schedule" end
    function Stencil.StencilScheduleScalar:stencil_artifact_schedule_candidate_name() return "scalar" end
    function Stencil.StencilScheduleAutoVector:stencil_artifact_schedule_candidate_name() return "autovector" end
    function Stencil.StencilScheduleUnrolled:stencil_artifact_schedule_candidate_name()
        return "unrolled:" .. tostring(self.factor)
    end
    function Stencil.StencilScheduleVector:stencil_artifact_schedule_candidate_name()
        return "vector:" .. tostring(schedule_lane_count(self) or "target") .. ":u" .. tostring(self.vector_unroll or 1) .. ":i" .. tostring(self.interleave or 1)
    end

    function Stencil.StencilSchedule:stencil_artifact_schedule_candidate_cost() return 1000000 end
    function Stencil.StencilScheduleScalar:stencil_artifact_schedule_candidate_cost() return 100000 end
    function Stencil.StencilScheduleAutoVector:stencil_artifact_schedule_candidate_cost() return 25000 end
    function Stencil.StencilScheduleUnrolled:stencil_artifact_schedule_candidate_cost()
        return math.floor(60000 / math.max(1, tonumber(self.factor) or 1))
    end
    function Stencil.StencilScheduleVector:stencil_artifact_schedule_candidate_cost()
        local lanes = schedule_lane_count(self) or 4
        local unroll = tonumber(self.vector_unroll) or 1
        local interleave = tonumber(self.interleave) or 1
        return math.floor(100000 / math.max(1, lanes * unroll * interleave))
    end

    local function schedule_key(schedule)
        return schedule:stencil_artifact_schedule_key()
    end

    local function artifact_fingerprint(instance0, provider, symbol, signature)
        local source = table.concat({
            "stencil-artifact-v1",
            descriptor_identity_repr(instance0.descriptor),
            stable_repr(instance0.schedule),
            stable_repr(instance0.abi),
            provider_key(provider),
            symbol.text,
            signature,
        }, "\n")
        return Stencil.StencilArtifactFingerprint("stencil-artifact-v1:" .. stable_hash128(source))
    end

    local function append_realized_diagnostics(out, realized)
        if realized == nil then return end
        for _, evidence in ipairs(realized.evidence or {}) do
            evidence:stencil_artifact_append_diagnostic(out)
        end
    end

    local function artifact_with_realized(artifact, provider, realized, extra_rejects, extra_diagnostics)
        provider = provider or artifact.provider
        local rejects = {}
        local has_compiler_matrix_reject = false
        for _, reject in ipairs(artifact.schedule_rejects or {}) do
            rejects[#rejects + 1] = reject
            if reject:stencil_artifact_is_compiler_matrix() then has_compiler_matrix_reject = true end
        end
        if not has_compiler_matrix_reject then
            for _, reject in ipairs(compiler_matrix_rejects(artifact.instance.schedule)) do rejects[#rejects + 1] = reject end
        end
        for _, reject in ipairs(schedule_rejects_for_realized(artifact.instance.schedule, realized)) do rejects[#rejects + 1] = reject end
        for _, reject in ipairs(extra_rejects or {}) do rejects[#rejects + 1] = reject end
        local diagnostics = {}
        for _, diagnostic in ipairs(artifact.diagnostics or {}) do diagnostics[#diagnostics + 1] = diagnostic end
        append_realized_diagnostics(diagnostics, realized)
        for _, diagnostic in ipairs(extra_diagnostics or {}) do diagnostics[#diagnostics + 1] = diagnostic end
        return Stencil.StencilArtifact(
            artifact.instance,
            provider,
            artifact.symbol,
            artifact.c_signature,
            artifact_fingerprint(artifact.instance, provider, artifact.symbol, artifact.c_signature),
            realized,
            diagnostics,
            rejects
        )
    end

    local function default_compiler_policy()
        return Stencil.StencilCompilerPolicy(Stencil.StencilCompilerGcc, Stencil.StencilOptO3, Stencil.StencilMachineNative, {})
    end

    local function layout_unit_stride(layout)
        if layout:stencil_artifact_is_field_or_soa() and layout:stencil_artifact_parent_layout() then
            return layout_unit_stride(layout:stencil_artifact_parent_layout())
        end
        if not layout:stencil_artifact_is_indexed() and not layout:stencil_artifact_is_field_or_soa() then
            return math.abs(layout:stencil_artifact_scale()) == 1 and layout:stencil_artifact_parent_layout()
                and layout_unit_stride(layout:stencil_artifact_parent_layout())
        end
        return false
    end

    local function access_info_fact(info, access)
        if info == nil then return nil end
        local facts = info.access_facts or info.vector_facts
        if type(facts) ~= "table" then return nil end
        return facts[access.name]
    end

    local function access_alignment_fact(info, access)
        local fact = access_info_fact(info, access)
        local alignment = fact and (fact.alignment or fact.align)
        if alignment == nil and info ~= nil then alignment = info.alignment or info.align end
        if type(alignment) == "number" and alignment > 0 then return Stencil.StencilAlignmentKnown(alignment) end
        if alignment ~= nil then return alignment end
        return Stencil.StencilAlignmentUnknown
    end

    local function access_ref(name)
        return Stencil.StencilAccessRef(name)
    end

    local function access_ref_name(ref)
        return ref and ref.name or nil
    end

    local function access_vector_fact(access, info)
        return Stencil.StencilAccessVectorFact(
            access_ref(access.name),
            access_alignment_fact(info, access),
            access.role == Stencil.StencilAccessRead or access.role == Stencil.StencilAccessIndex,
            layout_unit_stride(access.layout)
        )
    end

    local function is_memory_access(access)
        return not access.layout:stencil_artifact_is_scalar()
    end

    local function proof_origin(origin, fallback)
        if origin == Stencil.StencilProofCheckerDerived
            or origin == Stencil.StencilProofBoundaryContract
            or origin == Stencil.StencilProofAuthorAsserted then
            return origin
        end
        return fallback or Stencil.StencilProofAuthorAsserted
    end

    local function global_proof_origin(info, field, fallback)
        if info == nil then return fallback or Stencil.StencilProofAuthorAsserted end
        return proof_origin(info[field] or info.proof_origin, fallback)
    end

    local function alias_pair_fact(left, right, relation)
        return Stencil.StencilAccessAliasFact(access_ref(left), access_ref(right), relation)
    end

    local function append_alias_fact(out, pair, default_relation)
        if pair == nil then return end
        local left = pair.left or pair[1]
        local right = pair.right or pair[2]
        local relation = pair.relation or pair[3] or default_relation
        if left == nil or right == nil then error("stencil_artifact_plan: alias pair requires left and right accesses", 3) end
        out[#out + 1] = alias_pair_fact(left, right, relation or Stencil.StencilAliasUnknown)
    end

    local function alias_facts(desc, info)
        local out = {}
        if info ~= nil and info.noalias == true then
            local accesses = {}
            for _, access in ipairs(descriptor_accesses(desc)) do
                if is_memory_access(access) then accesses[#accesses + 1] = access end
            end
            for i = 1, #accesses do
                for j = i + 1, #accesses do
                    out[#out + 1] = alias_pair_fact(accesses[i].name, accesses[j].name, Stencil.StencilAliasNoAlias)
                end
            end
        end
        if info ~= nil then
            for _, pair in ipairs(info.noalias_pairs or {}) do append_alias_fact(out, pair, Stencil.StencilAliasNoAlias) end
            for _, pair in ipairs(info.mayalias_pairs or {}) do append_alias_fact(out, pair, Stencil.StencilAliasMayAlias) end
            for _, pair in ipairs(info.alias_pairs or {}) do append_alias_fact(out, pair, nil) end
        end
        return out
    end

    local function access_alignment_origin(info, access)
        local fact = access_info_fact(info, access)
        if fact ~= nil then
            local origin = fact.alignment_proof_origin or fact.proof_origin or fact.origin
            if origin ~= nil then return proof_origin(origin, Stencil.StencilProofAuthorAsserted) end
        end
        return global_proof_origin(info, "alignment_proof_origin", Stencil.StencilProofAuthorAsserted)
    end

    local function add_proof_obligation(out, kind, origin, proof)
        out[#out + 1] = Stencil.StencilProofObligation(kind, origin, proof)
    end

    local function vector_proof_obligations(desc, info, access_facts, aliases, trip_count, arithmetic)
        local out = {}
        local function descriptor_access_named(name)
            for _, access in ipairs(descriptor_accesses(desc)) do
                if access.name == name then return access end
            end
            return nil
        end

        for _, fact in ipairs(access_facts) do
            local name = access_ref_name(fact.access)
            local access = descriptor_access_named(name)
            if fact.unit_stride then
                add_proof_obligation(
                    out,
                    Stencil.StencilProofUnitStride(fact.access),
                    Stencil.StencilProofCheckerDerived,
                    nil
                )
            end
            if fact.alignment:stencil_artifact_alignment_bytes() ~= nil then
                add_proof_obligation(
                    out,
                    Stencil.StencilProofAlignment(fact.access, fact.alignment),
                    access_alignment_origin(info, access or { name = name }),
                    nil
                )
            end
        end

        local alias_origin = global_proof_origin(info, "alias_proof_origin", Stencil.StencilProofAuthorAsserted)
        for _, fact in ipairs(aliases) do
            if fact.relation == Stencil.StencilAliasNoAlias then
                add_proof_obligation(
                    out,
                    Stencil.StencilProofNoAlias(fact.left, fact.right),
                    alias_origin,
                    nil
                )
            end
        end

    -- GATING: checks whether trip_count is already a StencilTripCountFact domain value.
    -- Classof distinguishes domain facts from raw info tables — a data classification gate.
        local trip_count_cls = asdl.classof(trip_count)
        if trip_count_cls == Stencil.StencilTripCountMultipleOf or trip_count_cls == Stencil.StencilTripCountExact then
            add_proof_obligation(
                out,
                Stencil.StencilProofTripCount(trip_count),
                global_proof_origin(info, "trip_count_proof_origin", Stencil.StencilProofAuthorAsserted),
                nil
            )
        end

        if arithmetic.reduction_reassociable and descriptor_reducer(desc) ~= nil then
            add_proof_obligation(
                out,
                Stencil.StencilProofReductionReassociable,
                Stencil.StencilProofCheckerDerived,
                nil
            )
        end

        return out
    end

    local function reduction_reassociable(reducer)
        if reducer == nil then return true end
        if reducer.float_mode == Code.CodeFloatStrict then return false end
        if reducer.float_mode ~= nil then return true end
        return true
    end

    local function trip_count_fact(info)
        if info == nil then return Stencil.StencilTripCountDynamic end
        local fact = info.trip_count or info.trip_count_fact
    -- GATING: checks whether fact is already a valid StencilTripCountFact. If so, return it directly.
    -- If not (raw info), convert from info fields. Classof distinguishes domain values from raw info.
        local cls = asdl.classof(fact)
        if cls == Stencil.StencilTripCountUnknown
            or cls == Stencil.StencilTripCountDynamic
            or cls == Stencil.StencilTripCountExact
            or cls == Stencil.StencilTripCountMultipleOf then
            return fact
        end
        local exact = info.exact_trip_count or info.trip_count_exact
        if exact ~= nil then return Stencil.StencilTripCountExact(tonumber(exact)) end
        local multiple = info.trip_count_multiple_of or info.multiple_of
        if multiple ~= nil then return Stencil.StencilTripCountMultipleOf(tonumber(multiple)) end
        return Stencil.StencilTripCountDynamic
    end

    local function vectorization_facts(desc, info)
        local access_facts = {}
        for i, access in ipairs(descriptor_accesses(desc)) do access_facts[i] = access_vector_fact(access, info) end
        local reducer = descriptor_reducer(desc)
        local aliases = alias_facts(desc, info)
        local trip_count = trip_count_fact(info)
        local arithmetic = Stencil.StencilArithmeticVectorFact(
            reduction_reassociable(reducer),
            reducer and reducer.int_semantics or nil,
            reducer and reducer.float_mode or nil
        )
        return Stencil.StencilVectorizationFacts(
            access_facts,
            aliases,
            trip_count,
            arithmetic,
            vector_proof_obligations(desc, info, access_facts, aliases, trip_count, arithmetic)
        )
    end

    local function auto_vector_descriptor(desc)
        if desc == nil or desc.sink == nil then return false end
        return desc.sink:stencil_artifact_is_auto_vector()
    end

    local function unroll_factor(info)
        local n = tonumber(info and (info.unroll or info.unroll_factor) or 1) or 1
        n = math.floor(n)
        if n < 1 then return 1 end
        if n > 16 then return 16 end
        return n
    end

    local function schedule_vector_lanes(kind)
        if Schedule == nil or not kind:stencil_artifact_is_vector() then return nil end
        if not kind.lanes:stencil_artifact_is_fixed_lane() then return nil end
        return tonumber(kind.lanes.lanes)
    end

    local function schedule_for_descriptor_with_info(desc, info)
        local policy = default_compiler_policy()
        local sched = info and info.schedule or nil
        if Schedule ~= nil and sched:stencil_artifact_is_vector() then
            local lanes = schedule_vector_lanes(sched)
            if lanes ~= nil and lanes > 1 then
                return Stencil.StencilScheduleVector(
                    Stencil.StencilVectorFeatureNative,
                    Stencil.StencilLaneFixed(lanes),
                    Stencil.StencilVectorUnaligned,
                    sched.tail == Schedule.TailMasked and Stencil.StencilVectorMaskTail or Stencil.StencilVectorScalarTail,
                    Stencil.StencilVectorReductionHorizontal,
                    Stencil.StencilVectorCompilerCompiledStencil,
                    tonumber(sched.unroll) or 1,
                    tonumber(sched.interleave) or 1,
                    policy,
                    vectorization_facts(desc, info)
                )
            end
        elseif Schedule ~= nil and (sched == Schedule.ScheduleScalarIndex or sched == Schedule.ScheduleScalarPointer or sched == Schedule.ScheduleClosedForm) then
            return Stencil.StencilScheduleScalar(policy)
        end
        local unroll = unroll_factor(info)
        if unroll > 1 and auto_vector_descriptor(desc) then return Stencil.StencilScheduleUnrolled(unroll, policy, vectorization_facts(desc, info)) end
        if auto_vector_descriptor(desc) then return Stencil.StencilScheduleAutoVector(policy, vectorization_facts(desc, info)) end
        return Stencil.StencilScheduleScalar(policy)
    end

    local function schedule_suffix(schedule)
        return schedule:stencil_artifact_schedule_suffix()
    end

    local function schedule_candidate_name(schedule)
        return schedule:stencil_artifact_schedule_candidate_name()
    end

    local function schedule_candidate_cost(schedule)
        return schedule:stencil_artifact_schedule_candidate_cost()
    end

    local function schedule_candidate(schedule, status, reason, rejects)
        return Stencil.StencilScheduleCandidate(
            schedule_candidate_name(schedule),
            schedule,
            schedule_candidate_cost(schedule),
            status,
            rejects or {},
            reason
        )
    end

    local function selection_provenance_for_artifact(artifact, reason)
        local schedule = artifact.instance.schedule
        local compiler = schedule.compiler or default_compiler_policy()
        local selected = schedule_candidate(
            schedule,
            Stencil.StencilScheduleCandidateSelected,
            reason or "selected stencil schedule has lowest estimated materialization cost among viable candidates",
            artifact.schedule_rejects or {}
        )
        local candidates = { selected }
        if not schedule:stencil_artifact_is_scalar() then
            candidates[#candidates + 1] = schedule_candidate(
                Stencil.StencilScheduleScalar(compiler),
                Stencil.StencilScheduleCandidateViable,
                "scalar fallback is viable but has higher estimated cost",
                {}
            )
        end
        return Stencil.StencilScheduleSelectionProvenance(
            Stencil.StencilScheduleSelectionHeuristic,
            selected.name,
            candidates,
            selected.reason
        )
    end

    local function no_selection_provenance(vocab, rejects, reason)
        local schedule_rejects = {}
        for _, reject in ipairs(rejects or {}) do
            if reject:stencil_artifact_is_schedule_reject() then schedule_rejects[#schedule_rejects + 1] = reject.reject end
        end
        local candidate = Stencil.StencilScheduleCandidate(
            "none:" .. tostring(vocab),
            nil,
            1000000,
            Stencil.StencilScheduleCandidateRejected,
            schedule_rejects,
            reason or "no stencil schedule candidate was selected"
        )
        return Stencil.StencilScheduleSelectionProvenance(
            Stencil.StencilScheduleSelectionFallback,
            "none",
            { candidate },
            candidate.reason
        )
    end

    local function instance(id, desc, abi, proofs, info)
        return Stencil.StencilInstance(id, desc, schedule_for_descriptor_with_info(desc, info), abi, proofs or {})
    end

    local function layout_has_dynamic_stride(layout)
        return layout:stencil_artifact_has_dynamic_stride()
    end

    local function layout_has_affine_offset(layout)
        return layout:stencil_artifact_has_affine_offset()
    end

    local function dynamic_stride_accesses(desc)
        local out = {}
        for _, access in ipairs(descriptor_accesses(desc)) do
            if layout_has_dynamic_stride(access.layout) then
                out[#out + 1] = access
            end
        end
        return out
    end

    local function dynamic_affine_offset_accesses(desc)
        local out = {}
        for _, access in ipairs(descriptor_accesses(desc)) do
            if layout_has_affine_offset(access.layout) then
                out[#out + 1] = access
            end
        end
        return out
    end

    local function stride_param_name(access)
        return sanitize(access.name) .. "_stride"
    end

    local function affine_offset_param_name(access)
        return sanitize(access.name) .. "_affine_offset"
    end

    local abi_params_with_layouts

    local function abi_with_dynamic_strides(desc, params, result)
        local out = {}
        params = abi_params_with_layouts(desc, params)
        for i = 1, #(params or {}) do out[i] = params[i] end
        for _, _access in ipairs(dynamic_stride_accesses(desc)) do
            out[#out + 1] = i32_ty()
        end
        for _, _access in ipairs(dynamic_affine_offset_accesses(desc)) do
            out[#out + 1] = i32_ty()
        end
        return Stencil.StencilAbi(out, result)
    end

    local function params_with_dynamic_strides(desc, params)
        local out = {}
        for i = 1, #(params or {}) do out[i] = params[i] end
        for _, access in ipairs(dynamic_stride_accesses(desc)) do
            out[#out + 1] = "int32_t " .. stride_param_name(access)
        end
        for _, access in ipairs(dynamic_affine_offset_accesses(desc)) do
            out[#out + 1] = "int32_t " .. affine_offset_param_name(access)
        end
        return out
    end

    local function field_layout(layout)
        return layout:stencil_artifact_field_layout()
    end

    local function pointer_accesses(desc)
        local out = {}
        for _, access in ipairs(descriptor_accesses(desc)) do
            if not access.layout:stencil_artifact_is_scalar() then out[#out + 1] = access end
        end
        return out
    end

    local function param_decl_for_access(access, default)
        local field = field_layout(access.layout)
        if field == nil then return default end
        local name = default:match("%*%s*([_%a][_%w]*)") or access.name
        local is_const = default:match("%f[%w]const%f[%W]") ~= nil
        return c_type(field.record_ty) .. (is_const and " const *" or " *") .. name
    end

    local function abi_param_type_for_access(access, default_ty)
        local field = field_layout(access.layout)
        if field == nil then return default_ty end
        return Code.CodeTyDataPtr(field.record_ty)
    end

    abi_params_with_layouts = function(desc, params)
        local out = {}
        local accesses = pointer_accesses(desc)
        local access_i = 1
        for i = 1, #(params or {}) do
            local p = params[i]
            if p:stencil_artifact_is_data_ptr() and accesses[access_i] ~= nil then
                out[i] = abi_param_type_for_access(accesses[access_i], p)
                access_i = access_i + 1
            else
                out[i] = p
            end
        end
        return out
    end

    local function layout_suffix_for(access, layout)
        return layout:stencil_artifact_layout_suffix_for(access)
    end

    local function layout_suffix(access, access_name)
        local suffix = layout_suffix_for(access, access.layout)
        if suffix == "" then return "" end
        return "_" .. sanitize(access_name or access.name) .. suffix
    end

    local function descriptor_symbol_suffix(desc)
        local out = {}
        local access_map = descriptor_access_identity_map(desc)
        for _, access in ipairs(descriptor_accesses(desc)) do
            local suffix = layout_suffix(access, access_map[access.name])
            if suffix ~= "" then out[#out + 1] = suffix end
        end
        if #out == 0 then return "" end
        return "_l" .. stable_hash128(table.concat(out, "|"))
    end

    local function scheduled_instance(id, symbol, desc, abi, proofs, info)
        local selected_schedule = schedule_for_descriptor_with_info(desc, info or {})
        local suffix, symbol_suffix = schedule_suffix(selected_schedule)
        if suffix ~= "" then id = Stencil.StencilInstanceId(id.text .. suffix) end
        if symbol_suffix ~= "" then symbol = Stencil.StencilSymbolId(symbol.text .. symbol_suffix) end
        return instance(id, desc, abi, proofs, info), symbol
    end

    local source_params

    function artifact(instance, symbol, signature)
        local suffix = descriptor_symbol_suffix(instance.descriptor)
        if suffix ~= "" then
            local old_symbol = symbol.text
            symbol = Stencil.StencilSymbolId(old_symbol .. suffix)
            signature = signature:gsub(old_symbol, symbol.text, 1)
            instance = Stencil.StencilInstance(
                Stencil.StencilInstanceId(instance.id.text .. suffix),
                instance.descriptor,
                instance.schedule,
                instance.abi,
                instance.proofs
            )
        end
        return Stencil.StencilArtifact(
            instance,
            Stencil.StencilProviderC,
            symbol,
            signature,
            artifact_fingerprint(instance, Stencil.StencilProviderC, symbol, signature),
            nil,
            {},
            compiler_matrix_rejects(instance.schedule)
        )
    end

    local function void_desc_decl(symbol, desc, args)
        return void_decl(symbol, source_params({ instance = { descriptor = desc } }, args))
    end

    local function result_desc_decl(symbol, result_ty, desc, args)
        return result_decl(symbol, result_ty, source_params({ instance = { descriptor = desc } }, args))
    end

    local function int32_desc_decl(symbol, desc, args)
        return int32_decl(symbol, source_params({ instance = { descriptor = desc } }, args))
    end

    local producer_tag
    local append_producer_params
    local descriptor_abi_args

    function api.reduce_array_artifact(reduction, plan, info)
        local elem_ty = assert(info.elem_ty, "stencil_artifact_plan.reduce_array_artifact requires elem_ty")
        local result_ty = assert(info.result_ty, "stencil_artifact_plan.reduce_array_artifact requires result_ty")
        local stride = assert(info.step_num, "stencil_artifact_plan.reduce_array_artifact requires step_num")
        local supported, reason = api.reduce_array_supported(reduction, info)
        if not supported then error("stencil_artifact_plan: unsupported reduce_array artifact: " .. tostring(reason), 2) end
        local desc = descriptor(Stencil.StencilSinkReduce(result_ty, info.reduce_scope or domain_reduce_scope(), Stencil.StencilReduceFold(reducer_desc(reduction, result_ty))), stride,
            {
                shaped("xs", Stencil.StencilAccessRead, elem_ty, info.array_layout, stride),
                scalar("acc", Stencil.StencilAccessReduce, result_ty, reducer_identity(reduction, result_ty)),
            },

            nil,
            info,
            result_ty
        )
        local selected_schedule = schedule_for_descriptor_with_info(desc, info)
        local suffix, symbol_suffix = schedule_suffix(selected_schedule)
        local id = Stencil.StencilInstanceId(reduce_instance_id(elem_ty, result_ty, reduction.op, stride).text .. suffix)
        local symbol = Stencil.StencilSymbolId(reduce_symbol_id(elem_ty, result_ty, reduction.op, stride).text .. symbol_suffix)
        local abi, args = descriptor_abi_args(desc, { { ty = result_ty, decl = c_type(result_ty) .. " init" } })
        local inst = instance(
            id,
            desc,
            abi_with_dynamic_strides(desc, abi, result_ty),
            (plan and plan.body and plan.body.equivalence and plan.body.equivalence:stencil_artifact_proofs() or {}),
            info
        )
        return artifact(inst, symbol, result_desc_decl(symbol, result_ty, desc, args))
    end

    function api.scan_array_artifact(reduction, plan, info)
        local elem_ty, result_ty, stride = assert(info.elem_ty), assert(info.result_ty), assert(info.step_num or info.stride or 1)
        local mode = info.mode or Stencil.StencilScanInclusive
        local producer = producer_from_attrs(stride, info)
        local producer_reason = producer_materializer_reject_reason(producer)
        if producer_reason ~= nil then error("stencil_artifact_plan: unsupported scan_array producer: " .. tostring(producer_reason), 2) end
        local ok, reason = api.reduce_array_supported(reduction, { elem_ty = elem_ty, result_ty = result_ty })
        if not ok then error("stencil_artifact_plan: unsupported scan_array artifact: " .. tostring(reason), 2) end
        local ptag = producer_tag(producer)
        local id = Stencil.StencilInstanceId("stencil:scan_array:" .. type_name(elem_ty) .. ":" .. reduction.op:stencil_artifact_name() .. ":to:" .. type_name(result_ty) .. ":" .. mode:stencil_artifact_name() .. ":" .. ptag)
        local symbol = Stencil.StencilSymbolId("ml_stencil_scan_array_" .. type_name(elem_ty) .. "_" .. reduction.op:stencil_artifact_name() .. "_to_" .. type_name(result_ty) .. "_" .. mode:stencil_artifact_name() .. "_" .. ptag)
        local desc = descriptor(Stencil.StencilSinkScan(Stencil.StencilAccessRef("dst"), info.axis or info.scan_axis, reducer_desc(reduction, result_ty), mode, result_ty), stride,
            {
                shaped("dst", Stencil.StencilAccessWrite, result_ty, info.dst_layout, stride),
                shaped("xs", Stencil.StencilAccessRead, elem_ty, info.array_layout or info.src_layout, stride),
                scalar("acc", Stencil.StencilAccessReduce, result_ty, reducer_identity(reduction, result_ty)),
            },
            nil,
            { mode = mode, producer = producer, axis = info.axis or info.scan_axis },
            result_ty
        )
        local sink_reason = sink_materializer_reject_reason(desc)
        if sink_reason ~= nil then error("stencil_artifact_plan: unsupported scan_array sink/body: " .. tostring(sink_reason), 2) end
        local abi = { Code.CodeTyDataPtr(result_ty), Code.CodeTyDataPtr(elem_ty) }
        local args = { c_type(result_ty) .. " *dst", const_elem_ptr_decl(elem_ty, "xs") }
        append_producer_params(producer, abi, args)
        abi[#abi + 1] = result_ty
        args[#args + 1] = c_type(result_ty) .. " init"
        local inst
        inst, symbol = scheduled_instance(id, symbol, desc, abi_with_dynamic_strides(desc, abi, result_ty), (plan and plan.body and plan.body.equivalence and plan.body.equivalence:stencil_artifact_proofs() or {}), info)
        return artifact(inst, symbol, result_desc_decl(symbol, result_ty, desc, args))
    end

    function api.find_array_artifact(pred, info)
        local elem_ty, stride = assert(info.elem_ty), assert(info.step_num or info.stride or 1)
        local id = Stencil.StencilInstanceId("stencil:find_array:" .. type_name(elem_ty) .. ":" .. pred:stencil_artifact_name() .. ":stride" .. tostring(stride))
        local symbol = Stencil.StencilSymbolId("ml_stencil_find_array_" .. type_name(elem_ty) .. "_" .. pred:stencil_artifact_name() .. "_s" .. tostring(stride))        local not_found = Value.ValueExprConst(Code.CodeConstLiteral(i32_ty(), Core.LitInt("-1")))
        local desc = descriptor(
            "find",
            stride,
            {
                shaped("xs", Stencil.StencilAccessRead, elem_ty, info.array_layout or info.src_layout, stride),
                scalar("index", Stencil.StencilAccessControlResult, i32_ty(), not_found),
            },
            point_predicate_expr(predicate_checked(pred, elem_ty), input_expr("xs"), i32_ty()),
            nil,
            attrs(info, { not_found = not_found }),
            i32_ty()
        )
        local abi, args = descriptor_abi_args(desc)
        local inst
        inst, symbol = scheduled_instance(id, symbol, desc, abi_with_dynamic_strides(desc, abi, i32_ty()), {}, info)
        return artifact(inst, symbol, int32_desc_decl(symbol, desc, args))
    end

    function api.partition_array_artifact(pred, info)
        local elem_ty, stride = assert(info.elem_ty), assert(info.step_num or info.stride or 1)
        local semantics = info.semantics or Stencil.StencilPartitionStable
        local id = Stencil.StencilInstanceId("stencil:partition_array:" .. type_name(elem_ty) .. ":" .. pred:stencil_artifact_name() .. ":" .. semantics:stencil_artifact_name() .. ":stride" .. tostring(stride))
        local symbol = Stencil.StencilSymbolId("ml_stencil_partition_array_" .. type_name(elem_ty) .. "_" .. pred:stencil_artifact_name() .. "_" .. semantics:stencil_artifact_name() .. "_s" .. tostring(stride))
        local desc = descriptor(
            "partition",
            stride,
            {
                shaped("dst", Stencil.StencilAccessWrite, elem_ty, info.dst_layout, stride),
                shaped("xs", Stencil.StencilAccessRead, elem_ty, info.array_layout or info.src_layout, stride),
                scalar("split", Stencil.StencilAccessControlResult, i32_ty(), nil),
            },
            point_predicate_expr(predicate_checked(pred, elem_ty), input_expr("xs"), i32_ty()),
            nil,
            attrs(info, { semantics = semantics }),
            memory({ partition = semantics }),
            i32_ty()
        )
        local abi, args = descriptor_abi_args(desc)
        local inst
        inst, symbol = scheduled_instance(id, symbol, desc, abi_with_dynamic_strides(desc, abi, i32_ty()), {}, info)
        return artifact(inst, symbol, int32_desc_decl(symbol, desc, args))
    end

    function api.scatter_reduce_n_artifact(reduction, plan, info)
        local result_ty = assert(info.result_ty or info.elem_ty, "stencil_artifact_plan.scatter_reduce_n_artifact requires result_ty")
        local item_ty = assert(info.item_ty or info.elem_ty or result_ty, "stencil_artifact_plan.scatter_reduce_n_artifact requires item_ty")
        local index_ty = assert(info.index_ty, "stencil_artifact_plan.scatter_reduce_n_artifact requires index_ty")
        local stride = assert(info.step_num or info.stride or 1)
        local inputs = assert(info.inputs, "stencil_artifact_plan.scatter_reduce_n_artifact requires inputs")
        local expr = info.expr or input_expr(inputs[1] and (inputs[1].name or "x1") or "xs")
        local producer = producer_from_attrs(stride, info)
        local producer_reason = producer_materializer_reject_reason(producer)
        if producer_reason ~= nil then error("stencil_artifact_plan: unsupported scatter_reduce_n producer: " .. tostring(producer_reason), 2) end
        local ok, reason = api.reduce_array_supported(reduction, { elem_ty = item_ty, result_ty = result_ty })
        if not ok then error("stencil_artifact_plan: unsupported scatter_reduce_n reduction: " .. tostring(reason), 2) end
        local dst_name = info.dst_name or "dst"
        local idx_name = info.index_name or "idx"
        local accesses = {
            shaped(dst_name, Stencil.StencilAccessReadWrite, result_ty, info.dst_layout or Stencil.StencilLayoutIndexed(Stencil.StencilLayoutContiguous(1), Stencil.StencilAccessRef(idx_name), index_ty, stride), stride),
        }
        for i, input in ipairs(inputs) do
            local name = input.name or ("x" .. tostring(i))
            accesses[#accesses + 1] = shaped(name, Stencil.StencilAccessRead, assert(input.ty, "scatter_reduce_n input requires ty"), input.layout, stride)
        end
        accesses[#accesses + 1] = shaped(idx_name, Stencil.StencilAccessIndex, index_ty, info.index_layout, stride)
        local tag = sanitize(info.tag or ("arity" .. tostring(#inputs)))
        local ptag = producer_tag(producer)
        local conflicts = info.conflicts or info.scatter_reduce_conflicts or Stencil.StencilScatterReduceSequential
        local conflict_tag = conflicts:stencil_artifact_name()
        local id = Stencil.StencilInstanceId("stencil:scatter_reduce_n:" .. type_name(item_ty) .. ":" .. reduction.op:stencil_artifact_name() .. ":to:" .. type_name(result_ty) .. ":" .. conflict_tag .. ":" .. tag .. ":" .. ptag)
        local symbol = Stencil.StencilSymbolId("ml_stencil_scatter_reduce_n_" .. type_name(item_ty) .. "_" .. reduction.op:stencil_artifact_name() .. "_to_" .. type_name(result_ty) .. "_" .. conflict_tag .. "_" .. tag .. "_" .. ptag)
        local reducer = reducer_desc(reduction, result_ty)
        local desc = descriptor(Stencil.StencilSinkScatterReduce(Stencil.StencilAccessRef(dst_name), reducer, conflicts or Stencil.StencilScatterReduceSequential, result_ty), stride, accesses, expr, { producer = producer }, result_ty)
        local sink_reason = sink_materializer_reject_reason(desc)
        if sink_reason ~= nil then error("stencil_artifact_plan: unsupported scatter_reduce_n sink/body: " .. tostring(sink_reason), 2) end
        local abi, args = descriptor_abi_args(desc)
        local inst
        inst, symbol = scheduled_instance(id, symbol, desc, abi_with_dynamic_strides(desc, abi, nil), (plan and plan.body and plan.body.equivalence and plan.body.equivalence:stencil_artifact_proofs() or {}), info)
        return artifact(inst, symbol, void_desc_decl(symbol, desc, args))
    end

    function api.count_array_artifact(pred, info)
        local elem_ty, stride = assert(info.elem_ty), assert(info.step_num or info.stride or 1)
        local id = Stencil.StencilInstanceId("stencil:count_array:" .. type_name(elem_ty) .. ":" .. pred:stencil_artifact_name() .. ":stride" .. tostring(stride))
        local symbol = Stencil.StencilSymbolId("ml_stencil_count_array_" .. type_name(elem_ty) .. "_" .. pred:stencil_artifact_name() .. "_s" .. tostring(stride))
        local desc = descriptor(Stencil.StencilSinkReduce(i32_ty(), domain_reduce_scope(), Stencil.StencilReduceCount(pred)),
            stride,
            {
                shaped("xs", Stencil.StencilAccessRead, elem_ty, info.array_layout or info.src_layout, stride),
                scalar("count", Stencil.StencilAccessReduce, i32_ty(), nil),
            },
            point_predicate_expr(predicate_checked(pred, elem_ty), input_expr("xs"), i32_ty()),
            nil,
            info,
            i32_ty()
        )
        local abi, args = descriptor_abi_args(desc)
        local inst
        inst, symbol = scheduled_instance(id, symbol, desc, abi_with_dynamic_strides(desc, abi, i32_ty()), {}, info)
        return artifact(inst, symbol, int32_desc_decl(symbol, desc, args))
    end

    local function producer_param_name(axis_index, suffix)
        return "axis" .. tostring(axis_index) .. "_" .. suffix
    end

    function producer_tag(producer)
        local shape = producer_shape(producer)
        if shape == nil then return "producer" end
        return shape:stencil_artifact_producer_tag()
    end

    function append_producer_params(producer, abi, args)
        local shape = producer_shape(producer)
        shape:stencil_artifact_append_producer_params(abi, args)
    end

    function descriptor_abi_args(desc, trailing)
        local abi, args = {}, {}
        for _, access in ipairs(descriptor_accesses(desc)) do
            if not access.layout:stencil_artifact_is_scalar() then
                local role = access.role
                if role == Stencil.StencilAccessRead or role == Stencil.StencilAccessWrite or role == Stencil.StencilAccessReadWrite or role == Stencil.StencilAccessIndex then
                    abi[#abi + 1] = access_abi_ty(access)
                    args[#args + 1] = access_arg_decl(access, role == Stencil.StencilAccessWrite or role == Stencil.StencilAccessReadWrite)
                end
            end
        end
        append_producer_params(desc.producer, abi, args)
        for _, item in ipairs(trailing or {}) do
            abi[#abi + 1] = item.ty
            args[#args + 1] = item.decl
        end
        return abi, args
    end

    local function store_n_inputs(info, stride, producer)
        local inputs = assert(info.inputs, "stencil_artifact_plan.store_n_artifact requires inputs")
        local accesses = { shaped("dst", Stencil.StencilAccessWrite, assert(info.result_ty), info.dst_layout, stride) }
        local abi = { Code.CodeTyDataPtr(info.result_ty) }
        local args = { c_type(info.result_ty) .. " *dst" }
        for i, input in ipairs(inputs) do
            local name = input.name or ("x" .. tostring(i))
            local ty = assert(input.ty, "stencil_artifact_plan.store_n input requires ty")
            local role = input.role or Stencil.StencilAccessRead
            accesses[#accesses + 1] = shaped(name, role, ty, input.layout, stride)
            local access = accesses[#accesses]
            abi[#abi + 1] = access_abi_ty(access)
            args[#args + 1] = access_arg_decl(access, role == Stencil.StencilAccessWrite or role == Stencil.StencilAccessReadWrite)
        end
        append_producer_params(producer, abi, args)
        return inputs, accesses, abi, args
    end

    function api.store_n_artifact(info)
        local result_ty, stride = assert(info.result_ty, "stencil_artifact_plan.store_n_artifact requires result_ty"), assert(info.step_num or info.stride or 1)
        local expr = assert(info.expr, "stencil_artifact_plan.store_n_artifact requires expr")
        local producer = producer_from_attrs(stride, info)
        local producer_reason = producer_materializer_reject_reason(producer)
        if producer_reason ~= nil then error("stencil_artifact_plan: unsupported store_n producer: " .. tostring(producer_reason), 2) end
        local inputs, accesses, abi, args = store_n_inputs(info, stride, producer)
        local desc = descriptor(Stencil.StencilSinkStore(Stencil.StencilAccessRef(info.store_dst or "dst"), info.store_mode or Stencil.StencilStoreElementwise), stride, accesses, expr, attrs(info, { producer = producer }), nil)
        local sink_reason = sink_materializer_reject_reason(desc)
        if sink_reason ~= nil then error("stencil_artifact_plan: unsupported store_n sink/body: " .. tostring(sink_reason), 2) end
        local tag = sanitize("d" .. stable_hash128(descriptor_identity_repr(desc)))
        local ptag = producer_tag(producer)
        local id = Stencil.StencilInstanceId("stencil:store_n:" .. type_name(result_ty) .. ":" .. tag .. ":" .. ptag)
        local symbol = Stencil.StencilSymbolId("ml_stencil_store_n_" .. type_name(result_ty) .. "_" .. tag .. "_" .. ptag)
        local inst
        inst, symbol = scheduled_instance(id, symbol, desc, abi_with_dynamic_strides(desc, abi, nil), {}, info)
        return artifact(inst, symbol, void_desc_decl(symbol, desc, args))
    end

    function api.reduce_n_artifact(reduction, plan, info)
        local result_ty, item_ty, stride = assert(info.result_ty, "stencil_artifact_plan.reduce_n_artifact requires result_ty"), assert(info.item_ty or info.mapped_ty or info.result_ty, "stencil_artifact_plan.reduce_n_artifact requires item_ty"), assert(info.step_num or info.stride or 1)
        local expr = assert(info.expr, "stencil_artifact_plan.reduce_n_artifact requires expr")
        local producer = producer_from_attrs(stride, info)
        local producer_reason = producer_materializer_reject_reason(producer)
        if producer_reason ~= nil then error("stencil_artifact_plan: unsupported reduce_n producer: " .. tostring(producer_reason), 2) end
        local ok, reason = api.reduce_array_supported(reduction, { elem_ty = item_ty, result_ty = result_ty })
        if not ok then error("stencil_artifact_plan: unsupported reduce_n reduction: " .. tostring(reason), 2) end
        local inputs = assert(info.inputs, "stencil_artifact_plan.reduce_n_artifact requires inputs")
        local scope = info.scope or info.reduce_scope or domain_reduce_scope()
        local scoped_output = not scope:stencil_artifact_is_domain()
        local accesses = {}
        local abi = {}
        local args = {}
        if scoped_output then
            local dst_name = assert(scope.dst and scope.dst.name, "stencil_artifact_plan.reduce_n scoped output requires scope dst")
            accesses[#accesses + 1] = shaped(dst_name, Stencil.StencilAccessWrite, result_ty, info.dst_layout, stride)
            local access = accesses[#accesses]
            abi[#abi + 1] = access_abi_ty(access)
            args[#args + 1] = access_arg_decl(access, true)
        end
        for i, input in ipairs(inputs) do
            local name = input.name or ("x" .. tostring(i))
            local ty = assert(input.ty, "stencil_artifact_plan.reduce_n input requires ty")
            local role = input.role or Stencil.StencilAccessRead
            accesses[#accesses + 1] = shaped(name, role, ty, input.layout, stride)
            local access = accesses[#accesses]
            abi[#abi + 1] = access_abi_ty(access)
            args[#args + 1] = access_arg_decl(access, role == Stencil.StencilAccessWrite or role == Stencil.StencilAccessReadWrite)
        end
        accesses[#accesses + 1] = scalar("acc", Stencil.StencilAccessReduce, result_ty, reducer_identity(reduction, result_ty))
        append_producer_params(producer, abi, args)
        if not scoped_output then
            abi[#abi + 1] = result_ty
            args[#args + 1] = c_type(result_ty) .. " init"
        end
        local desc = descriptor(Stencil.StencilSinkReduce(result_ty, scope, Stencil.StencilReduceFold(reducer_desc(reduction, result_ty))), stride, accesses, expr, { producer = producer }, result_ty)
        local sink_reason = sink_materializer_reject_reason(desc)
        if sink_reason ~= nil then error("stencil_artifact_plan: unsupported reduce_n sink/body: " .. tostring(sink_reason), 2) end
        local tag = sanitize((info.tag or ("arity" .. tostring(#inputs))) .. "_" .. stable_hash128(descriptor_identity_repr(desc)))
        local ptag = producer_tag(producer)
        local id = Stencil.StencilInstanceId("stencil:reduce_n:" .. type_name(item_ty) .. ":" .. reduction.op:stencil_artifact_name() .. ":to:" .. type_name(result_ty) .. ":" .. tag .. ":" .. ptag)
        local symbol = Stencil.StencilSymbolId("ml_stencil_reduce_n_" .. type_name(item_ty) .. "_" .. reduction.op:stencil_artifact_name() .. "_to_" .. type_name(result_ty) .. "_" .. tag .. "_" .. ptag)
        local inst
        inst, symbol = scheduled_instance(id, symbol, desc, abi_with_dynamic_strides(desc, abi, scoped_output and nil or result_ty), (plan and plan.body and plan.body.equivalence and plan.body.equivalence:stencil_artifact_proofs() or {}), info)
        if scoped_output then return artifact(inst, symbol, void_desc_decl(symbol, desc, args)) end
        return artifact(inst, symbol, result_desc_decl(symbol, result_ty, desc, args))
    end

    function api.scan_n_artifact(reduction, plan, info)
        local result_ty, item_ty, stride = assert(info.result_ty, "stencil_artifact_plan.scan_n_artifact requires result_ty"), assert(info.item_ty or info.mapped_ty or info.result_ty, "stencil_artifact_plan.scan_n_artifact requires item_ty"), assert(info.step_num or info.stride or 1)
        local expr = assert(info.expr, "stencil_artifact_plan.scan_n_artifact requires expr")
        local mode = info.mode or Stencil.StencilScanInclusive
        local producer = producer_from_attrs(stride, info)
        local producer_reason = producer_materializer_reject_reason(producer)
        if producer_reason ~= nil then error("stencil_artifact_plan: unsupported scan_n producer: " .. tostring(producer_reason), 2) end
        local ok, reason = api.reduce_array_supported(reduction, { elem_ty = item_ty, result_ty = result_ty })
        if not ok then error("stencil_artifact_plan: unsupported scan_n reduction: " .. tostring(reason), 2) end
        local inputs = assert(info.inputs, "stencil_artifact_plan.scan_n_artifact requires inputs")
        local accesses = { shaped("dst", Stencil.StencilAccessWrite, result_ty, info.dst_layout, stride) }
        local abi = { Code.CodeTyDataPtr(result_ty) }
        local args = { c_type(result_ty) .. " *dst" }
        for i, input in ipairs(inputs) do
            local name = input.name or ("x" .. tostring(i))
            local ty = assert(input.ty, "stencil_artifact_plan.scan_n input requires ty")
            local role = input.role or Stencil.StencilAccessRead
            accesses[#accesses + 1] = shaped(name, role, ty, input.layout, stride)
            local access = accesses[#accesses]
            abi[#abi + 1] = access_abi_ty(access)
            args[#args + 1] = access_arg_decl(access, role == Stencil.StencilAccessWrite or role == Stencil.StencilAccessReadWrite)
        end
        accesses[#accesses + 1] = scalar("acc", Stencil.StencilAccessReduce, result_ty, reducer_identity(reduction, result_ty))
        append_producer_params(producer, abi, args)
        abi[#abi + 1] = result_ty
        args[#args + 1] = c_type(result_ty) .. " init"
        local reducer = reducer_desc(reduction, result_ty)
        local desc = descriptor(Stencil.StencilSinkScan(Stencil.StencilAccessRef("dst"), info.axis or info.scan_axis, reducer, mode, result_ty), stride, accesses, expr, { producer = producer }, result_ty)
        local sink_reason = sink_materializer_reject_reason(desc)
        if sink_reason ~= nil then error("stencil_artifact_plan: unsupported scan_n sink/body: " .. tostring(sink_reason), 2) end
        local tag = sanitize((info.tag or ("arity" .. tostring(#inputs))) .. "_" .. stable_hash128(descriptor_identity_repr(desc)))
        local ptag = producer_tag(producer)
        local id = Stencil.StencilInstanceId("stencil:scan_n:" .. type_name(item_ty) .. ":" .. reduction.op:stencil_artifact_name() .. ":to:" .. type_name(result_ty) .. ":" .. mode:stencil_artifact_name() .. ":" .. tag .. ":" .. ptag)
        local symbol = Stencil.StencilSymbolId("ml_stencil_scan_n_" .. type_name(item_ty) .. "_" .. reduction.op:stencil_artifact_name() .. "_to_" .. type_name(result_ty) .. "_" .. mode:stencil_artifact_name() .. "_" .. tag .. "_" .. ptag)
        local inst
        inst, symbol = scheduled_instance(id, symbol, desc, abi_with_dynamic_strides(desc, abi, nil), (plan and plan.body and plan.body.equivalence and plan.body.equivalence:stencil_artifact_proofs() or {}), info)
        return artifact(inst, symbol, void_desc_decl(symbol, desc, args))
    end

    local function access_named(desc, name)
        for _, a in ipairs(descriptor_accesses(desc)) do
            if a.name == name then return a end
        end
        error("stencil_artifact_plan: descriptor missing access " .. tostring(name), 3)
    end

    local function layout_stride(access)
        local top = access.layout
        if top.stride ~= nil then return top.stride end
        return 1
    end

    local function producer_stride(desc)
        local producer = descriptor_producer(desc)
        local shape = producer_shape(producer)
        if shape:stencil_artifact_is_range_1d() and producer_materialized(producer) then return shape:stencil_artifact_range_step() end
        local reason = producer_materializer_reject_reason(producer)
        error("stencil_artifact_plan: unsupported stencil producer for artifact shape: " .. tostring(reason), 3)
    end

    function Stencil.StencilProducerExecution:artifact_shape_stride()
        return nil
    end

    function Stencil.StencilProducerExecRange1D:artifact_shape_stride()
        return self.stride
    end

    function Stencil.StencilProducerShape:artifact_execution_plan()
        error("stencil_artifact_plan: unsupported producer execution plan", 3)
    end

    function Stencil.StencilProduceRange1D:artifact_execution_plan()
        return Stencil.StencilProducerExecRange1D(
            tonumber(self.step) or 1,
            self.order
        )
    end

    local function nd_execution_axes(axes)
        local out = {}
        for i, axis in ipairs(axes or {}) do
            out[#out + 1] = Stencil.StencilProducerExecutionAxis(
                axis.index_ty,
                tonumber(axis.step) or 1,
                producer_param_name(i, "start"),
                producer_param_name(i, "stop")
            )
        end
        return out
    end

    function Stencil.StencilProduceRangeND:artifact_execution_plan()
        local axes = nd_execution_axes(self.axes)
        return Stencil.StencilProducerExecRangeND(#axes, axes)
    end

    function Stencil.StencilProduceWindowND:artifact_execution_plan()
        local axes = nd_execution_axes(self.axes)
        return Stencil.StencilProducerExecWindowND(#axes, axes, self.windows)
    end

    function Stencil.StencilProduceTiledND:artifact_execution_plan()
        local axes = nd_execution_axes(self.axes)
        return Stencil.StencilProducerExecTiledND(#axes, axes, self.tile_sizes)
    end

    local function producer_execution_plan(desc)
        local producer = descriptor_producer(desc)
        local reason = producer_materializer_reject_reason(producer)
        if reason ~= nil then error("stencil_artifact_plan: unsupported stencil producer for artifact shape: " .. tostring(reason), 3) end
        local shape = producer_shape(producer)
        return shape:artifact_execution_plan()
    end

    local function indexed_ty(access)
        local top = access.layout
        if not top:stencil_artifact_is_indexed() then
            error("stencil_artifact_plan: descriptor access is not indexed: " .. tostring(access.name), 3)
        end
        return top.index_ty
    end

    function Stencil.StencilReduceScope:artifact_reduce_execution_scope()
        error("stencil_artifact_plan: unsupported reduce execution scope", 3)
    end

    function Stencil.StencilReduceScopeDomain:artifact_reduce_execution_scope()
        return Stencil.StencilReduceExecDomain
    end

    function Stencil.StencilReduceExecDomain:artifact_reduce_init_mode()
        return Stencil.StencilReduceInitExternal
    end

    function Stencil.StencilReduceScopeAxes:artifact_reduce_execution_scope()
        return Stencil.StencilReduceExecAxes(self.dst.name, self.axes)
    end

    function Stencil.StencilReduceExecAxes:artifact_reduce_init_mode()
        return Stencil.StencilReduceInitIdentity
    end

    function Stencil.StencilReduceScopeWindow:artifact_reduce_execution_scope()
        return Stencil.StencilReduceExecWindow(self.dst.name, self.axes)
    end

    function Stencil.StencilReduceExecWindow:artifact_reduce_init_mode()
        return Stencil.StencilReduceInitIdentity
    end

    local function expr_input_name(expr)
        if expr:stencil_artifact_is_input() then return expr.access.name end
        return nil
    end

    local function expr_is_input(expr, name)
        return expr_input_name(expr) == name
    end

    local function collect_expr_inputs(expr, seen, out)
        seen = seen or {}
        out = out or {}
        expr:stencil_artifact_collect_inputs(seen, out)
        return out
    end

    local function collect_layout_inputs(layout, seen, out)
        layout:stencil_artifact_collect_layout_inputs(seen, out)
    end

    local function expr_inputs_for_shape(desc, expr)
        local seen, names = {}, {}
        collect_expr_inputs(expr, seen, names)
        for _, access in ipairs(descriptor_accesses(desc)) do
            collect_layout_inputs(access.layout, seen, names)
        end
        local out = {}
        for _, name in ipairs(names) do
            local access = access_named(desc, name)
            if access.role == Stencil.StencilAccessRead or access.role == Stencil.StencilAccessReadWrite or access.role == Stencil.StencilAccessIndex then
                out[#out + 1] = access
            end
        end
        return out
    end

    local function store_n_shape(desc, result_ty, dst_name, store_mode)
        local expr = descriptor_expr(desc)
        local inputs = expr_inputs_for_shape(desc, expr)
        local producer = producer_execution_plan(desc)
        return Stencil.StencilArtifactStoreN(inputs, result_ty, dst_name or "dst", store_mode, expr, producer, producer:artifact_shape_stride())
    end

    local function reduce_n_shape(desc, red, init_mode)
        local expr = descriptor_expr(desc)
        local inputs = expr_inputs_for_shape(desc, expr)
        local producer = producer_execution_plan(desc)
        local scope = desc.sink.scope
        local reduce_scope = scope:artifact_reduce_execution_scope()
        return Stencil.StencilArtifactReduceN(
            inputs,
            expr,
            desc.sink.result_ty,
            red.result_ty,
            red.reduction,
            red.int_semantics,
            red.float_mode,
            red.identity,
            scope,
            reduce_scope,
            init_mode or reduce_scope:artifact_reduce_init_mode(),
            producer,
            producer:artifact_shape_stride()
        )
    end

    local function count_reduce_shape(desc, mode)
        local red = Stencil.StencilReducer(
            Value.ReductionAdd,
            desc.sink.result_ty,
            reducer_identity({ op = Value.ReductionAdd }, desc.sink.result_ty),
            default_int_semantics(),
            nil
        )
        return reduce_n_shape(desc, red, Stencil.StencilReduceInitIdentity)
    end

    local function find_n_shape(desc, mode)
        local expr = descriptor_expr(desc)
        local inputs = expr_inputs_for_shape(desc, expr)
        local producer = producer_execution_plan(desc)
        return Stencil.StencilArtifactFindN(inputs, expr, desc.sink.result_ty, mode.pred, mode.not_found, producer, producer:artifact_shape_stride())
    end

    local function partition_n_shape(desc, sink)
        local expr = descriptor_expr(desc)
        local inputs = expr_inputs_for_shape(desc, expr)
        local producer = producer_execution_plan(desc)
        return Stencil.StencilArtifactPartitionN(inputs, expr, Code.CodeTyInt(32, Code.CodeSigned), sink.dst.name, sink.semantics, producer, producer:artifact_shape_stride())
    end

    local function scan_n_shape(desc, sink)
        local expr = descriptor_expr(desc)
        local inputs = expr_inputs_for_shape(desc, expr)
        local producer = producer_execution_plan(desc)
        local red = sink.reducer
        return Stencil.StencilArtifactScanN(
            inputs,
            expr,
            sink.result_ty,
            red.reduction,
            red.int_semantics,
            red.float_mode,
            red.identity,
            sink.mode,
            sink.axis,
            producer,
            producer:artifact_shape_stride()
        )
    end

    local function scatter_reduce_n_shape(desc, sink)
        local expr = descriptor_expr(desc)
        local inputs = expr_inputs_for_shape(desc, expr)
        local producer = producer_execution_plan(desc)
        local red = sink.reducer
        return Stencil.StencilArtifactScatterReduceN(
            inputs,
            expr,
            sink.result_ty,
            red.reduction,
            red.int_semantics,
            red.float_mode,
            red.identity,
            sink.dst.name,
            sink.conflicts,
            producer,
            producer:artifact_shape_stride()
        )
    end

    function Stencil.StencilArtifact:artifact_shape()
        return self.instance.descriptor:artifact_shape()
    end

    function Stencil.StencilDescriptor:artifact_shape()
        local sink_reason = sink_materializer_reject_reason(self)
        if sink_reason ~= nil then error("stencil_artifact_plan: unsupported stencil sink: " .. tostring(sink_reason), 3) end
        return self.sink:artifact_shape_for_descriptor(self)
    end

    function Stencil.StencilSink:artifact_shape_for_descriptor(_desc)
        error("stencil_artifact_plan: unsupported stencil descriptor", 3)
    end

    function Stencil.StencilReductionSemantics:artifact_reduce_shape(_desc)
        error("stencil_artifact_plan: unsupported reduce sink semantics", 3)
    end

    function Stencil.StencilReduceFold:artifact_reduce_shape(desc)
        return reduce_n_shape(desc, self.reducer)
    end

    function Stencil.StencilReduceCount:artifact_reduce_shape(desc)
        return count_reduce_shape(desc, self)
    end

    function Stencil.StencilReduceFind:artifact_reduce_shape(desc)
        return find_n_shape(desc, self)
    end

    function Stencil.StencilSinkReduce:artifact_shape_for_descriptor(desc)
        return self.semantics:artifact_reduce_shape(desc)
    end

    function Stencil.StencilStoreSemantics:artifact_store_shape(desc, sink)
        return store_n_shape(desc, access_named(desc, sink.dst.name).ty, sink.dst.name, self)
    end

    function Stencil.StencilStorePartition:artifact_store_shape(desc, sink)
        return partition_n_shape(desc, sink)
    end

    function Stencil.StencilSinkStore:artifact_shape_for_descriptor(desc)
        return self.semantics:artifact_store_shape(desc, self)
    end

    function Stencil.StencilSinkScan:artifact_shape_for_descriptor(desc)
        return scan_n_shape(desc, self)
    end

    function Stencil.StencilSinkScatterReduce:artifact_shape_for_descriptor(desc)
        return scatter_reduce_n_shape(desc, self)
    end

    local function artifact_shape(artifact)
        return artifact:artifact_shape()
    end

    source_params = function(artifact, params)
        local desc = artifact.instance.descriptor
        local accesses = pointer_accesses(desc)
        local access_i = 1
        local out = {}
        for i = 1, #(params or {}) do
            local p = params[i]
            if p:match("%*") and accesses[access_i] ~= nil then
                out[i] = param_decl_for_access(accesses[access_i], p)
                access_i = access_i + 1
            else
                out[i] = p
            end
        end
        return params_with_dynamic_strides(desc, out)
    end


    api.artifact_shape = artifact_shape
    api.source_params = source_params
    api.access_named = access_named
    api.input_expr = input_expr
    api.const_expr = const_expr
    api.point_unary_expr = point_unary_expr
    api.point_binary_expr = point_binary_expr
    api.point_predicate_expr = point_predicate_expr
    api.point_compare_expr = point_compare_expr
    api.point_cast_expr = point_cast_expr
    api.point_select_expr = point_select_expr
    api.descriptor_accesses = descriptor_accesses
    api.descriptor_producer = descriptor_producer
    api.producer_shape = producer_shape
    api.producer_axis_count = producer_axis_count
    api.producer_shape_reject_reason = producer_shape_reject_reason
    api.producer_shape_supported = producer_shape_supported
    api.producer_materialized = producer_materialized
    api.producer_materializer_reject_reason = producer_materializer_reject_reason
    api.unsupported_producer_reject = unsupported_producer_reject
    api.sink_materializer_reject_reason = sink_materializer_reject_reason
    api.unsupported_sink_reject = unsupported_sink_reject
    api.axis_ref = axis_ref
    api.domain_reduce_scope = domain_reduce_scope
    api.schedule_lane_count = schedule_lane_count
    api.selection_provenance_for_artifact = selection_provenance_for_artifact
    api.no_selection_provenance = no_selection_provenance
    api.schedule_rejects_for_realized = schedule_rejects_for_realized
    api.artifact_with_realized = artifact_with_realized
    api.stride_param_name = stride_param_name
    api.dynamic_stride_accesses = dynamic_stride_accesses
    api.affine_offset_param_name = affine_offset_param_name
    api.dynamic_affine_offset_accesses = dynamic_affine_offset_accesses

    T._lalin_api_cache.stencil_artifact_plan = api
    return api
end

return bind_context
