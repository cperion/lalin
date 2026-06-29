local function bind_context(T)
    local Code = T.LalinCode
    local Meta = require("lalin.stencil_metastencil")(T)

    local M = {}

    M.status = {
        supported = "supported",
        rejected = "rejected",
        partial = "partial",
        future = "future",
    }

    M.materializer_status = {
        materialized = "materialized",
        materialized_center_domain = "materialized_center_domain",
        typed_reject = "typed_reject",
        covered = "covered",
        partial = "partial",
        future = "future",
    }

    M.coverage_policy = {
        semantic_probe = "semantic_probe",
        fast_subset = "fast_subset",
        deployment_bank = "deployment_bank",
    }

    local sink_scopes = {
        StencilStore = "canonical StoreN generator for producer + N-input point body + store sink descriptors",
        StencilReduce = "primitive generator for folds plus generated count/find and generic reduce_n fusion artifacts",
        StencilScan = "primitive generator for axis-aware prefix reductions; residual_mc and LuaTrace materialize Range1D and RangeND axis scans",
        StencilScatterReduce = "primitive generator for indexed accumulation/reduce_by_index over an externally initialized destination",
    }

    M.sink_vocabs = {}
    for _, name in ipairs(Meta.vocabulary.sink_nodes) do
        M.sink_vocabs[name] = { status = "supported", scope = assert(sink_scopes[name], name) }
    end

    M.metastencil_vocabulary = {
        sink_nodes = Meta.vocabulary.sink_nodes,
        producers = Meta.vocabulary.producers,
        bodies = Meta.vocabulary.bodies,
        point_exprs = Meta.vocabulary.point_exprs,
        access_roles = Meta.vocabulary.access_roles,
        layouts = Meta.vocabulary.layouts,
        graph = Meta.vocabulary.graph,
        legality = Meta.vocabulary.legality,
    }

    M.layouts = {
        StencilLayoutScalar = { status = "supported", scope = "reduction accumulators/control values, not memory lanes" },
        StencilLayoutContiguous = { status = "supported", scope = "generated StoreN/ReduceN/ScanN basis layout" },
        StencilLayoutIndexed = { status = "supported", scope = "generated StoreN/ReduceN/ScanN basis layout with explicit index access reference" },
        StencilLayoutAffine1D = { status = "supported", scope = "generated StoreN/ReduceN/ScanN/ScatterReduceN basis layout for affine 1D access remapping" },
        StencilLayoutAffineND = { status = "partial", scope = "MC/C StoreN over RangeND with constant axis coefficients; dynamic coefficients and BC coverage remain open" },
        StencilLayoutFieldProjection = { status = "supported", scope = "generated StoreN/ReduceN/ScanN basis layout with record-pointer ABI projection" },
        StencilLayoutSoAComponent = { status = "supported", scope = "generated StoreN/ReduceN/ScanN basis layout over component buffers" },
        StencilLayoutSliceDescriptor = { status = "supported", scope = "generated StoreN/ReduceN/ScanN basis layout" },
        StencilLayoutByteSpanDescriptor = { status = "supported", scope = "generated StoreN/ReduceN/ScanN basis layout" },
        StencilLayoutViewDescriptor = { status = "supported", scope = "generated StoreN/ReduceN/ScanN basis layout with dynamic stride parameterization" },
    }

    M.producers = {
        StencilProduceRange1D = {
            status = "supported",
            scope = "shape-supported; positive forward ranges materialize in BC, MC, and emitted-bank cells",
            shape = "supported",
            residual_bc = "materialized",
            residual_mc = "materialized",
            bank = "covered",
        },
        StencilProduceRangeND = {
            status = "supported",
            scope = "shape-supported; forward ND ranges materialize in residual_bc and residual_mc generic StoreN/domain-ReduceN/axis-ReduceN/axis-ScanN plus emitted-bank cells",
            shape = "supported",
            residual_bc = "materialized",
            residual_mc = "materialized",
            bank = "covered",
        },
        StencilProduceWindowND = {
            status = "supported",
            scope = "shape-supported; center-domain WindowND materializes in residual_mc generic StoreN/domain-ReduceN/axis-ScanN, window-neighbor store, and window-local reduce; BC rejects with typed producer facts",
            shape = "supported",
            residual_bc = "typed_reject",
            residual_bc_gap = "semantic BC producer materializer does not yet execute WindowND loops or window-relative body inputs",
            residual_mc = "materialized_center_domain",
            bank = "covered",
        },
        StencilProduceTiledND = {
            status = "supported",
            scope = "shape-supported; forward tiled ND loops materialize in residual_mc generic StoreN/domain-ReduceN/axis-ScanN and emitted-bank cells; BC rejects with typed producer facts",
            shape = "supported",
            residual_bc = "typed_reject",
            residual_bc_gap = "semantic BC producer materializer does not yet execute tiled ND loops",
            residual_mc = "materialized",
            bank = "covered",
        },
    }

    M.predicates = {
        StencilPredNonZero = { status = "supported", scope = "numeric/bool scalar predicate" },
        StencilPredCompareConst = { status = "supported", scope = "typed scalar comparison against a literal constant" },
        StencilPredRange = { status = "supported", scope = "typed scalar lower/upper-bound predicate" },
        StencilPredAnd = { status = "supported", scope = "compound scalar predicate conjunction" },
        StencilPredOr = { status = "supported", scope = "compound scalar predicate disjunction" },
        StencilPredNot = { status = "supported", scope = "compound scalar predicate negation" },
        StencilPredIsNaN = { status = "supported", scope = "float scalar NaN classification" },
        StencilPredIsInf = { status = "supported", scope = "float scalar infinity classification" },
        StencilPredIsFinite = { status = "supported", scope = "float scalar finite classification" },
    }

    M.type_families = {
        CodeTyBool8 = { status = "supported", scope = "bool8 scalar cells" },
        CodeTyInt = { status = "supported", scope = "8/16/32/64 signed and unsigned scalar cells" },
        CodeTyFloat = { status = "supported", scope = "f32/f64 scalar cells; no bitwise reductions" },
        CodeTyIndex = { status = "supported", scope = "index scalar cells and index-lane classification" },
        CodeTyVoid = { status = "rejected", scope = "not an element type" },
        CodeTyDataPtr = { status = "supported", scope = "pointer-valued element lanes for StoreN identity/scalar/indexed bodies" },
        CodeTyCodePtr = { status = "supported", scope = "code-pointer element lanes for StoreN identity/scalar/indexed bodies" },
        CodeTyNamed = { status = "supported", scope = "whole-record element lanes for StoreN identity/scalar/indexed bodies" },
        CodeTyArray = { status = "supported", scope = "whole-array element lanes for StoreN identity/scalar/indexed bodies" },
        CodeTySlice = { status = "supported", scope = "descriptor-valued element lanes for StoreN identity/scalar/indexed bodies" },
        CodeTyView = { status = "supported", scope = "descriptor-valued element lanes for StoreN identity/scalar/indexed bodies" },
        CodeTyByteSpan = { status = "supported", scope = "descriptor-valued element lanes for StoreN identity/scalar/indexed bodies" },
        CodeTyHandle = { status = "supported", scope = "handle representation element lanes for StoreN identity/scalar/indexed bodies" },
        CodeTyLease = { status = "supported", scope = "lease representation element lanes for StoreN identity/scalar/indexed bodies" },
        CodeTyClosure = { status = "supported", scope = "closure descriptor element lanes for StoreN identity/scalar/indexed bodies" },
        CodeTyImportedC = { status = "supported", scope = "imported C element lanes for StoreN identity/scalar/indexed bodies" },
        CodeTyImportedCFuncPtr = { status = "supported", scope = "imported C function-pointer lanes for StoreN identity/scalar/indexed bodies" },
        CodeTyVector = { status = "supported", scope = "vector element lanes for StoreN identity/scalar/indexed bodies" },
    }

    M.materializers = {
        residual_bc = {
            status = "supported",
            policy = M.coverage_policy.semantic_probe,
            fallback_rank = 2,
            scope = "semantic LuaTrace bytecode materializer; it is the correctness probe and must either materialize a supported cell or expose an exact typed unsupported cell",
        },
        residual_mc = {
            status = "supported",
            policy = M.coverage_policy.fast_subset,
            scope = "fast machine-code subset from explicit compiled artifacts; missing fast cells are hard materialization diagnostics",
        },
        emitted_bank = {
            status = "supported",
            policy = M.coverage_policy.deployment_bank,
            scope = "deployment bank containing the intended interned MC artifacts; missing or stale entries must be visible diagnostics",
        },
    }

    function M.producer_materializer_status(producer_name, materializer)
        local row = M.producers[producer_name]
        if row == nil then return nil end
        if materializer == "residual_bc" then return row.residual_bc end
        if materializer == "residual_mc" then return row.residual_mc end
        if materializer == "emitted_bank" then return row.bank end
        return nil
    end

    function M.residual_bc_semantic_gap(producer_name)
        local row = M.producers[producer_name]
        if row == nil or row.shape ~= "supported" then return nil end
        if row.residual_bc == M.materializer_status.materialized then return nil end
        return row.residual_bc_gap or ("residual_bc does not materialize " .. tostring(producer_name))
    end

    function M.type_family_for(ty)
        local cls = require("lalin.asdl").classof(ty)
        if ty == Code.CodeTyBool8 then return "CodeTyBool8" end
        if ty == Code.CodeTyIndex then return "CodeTyIndex" end
        if cls == nil then return tostring(ty) end
        local name = tostring(cls):match("Class%((.-)%)") or tostring(cls)
        return name:match("%.([^%.]+)$") or name
    end

    function M.entry(table_name, key)
        local table_ = M[table_name]
        return table_ and table_[key] or nil
    end

    return M
end

return bind_context
