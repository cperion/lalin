local pvm = require("lalin.pvm")

local function safe_classof(value)
    if type(value) ~= "table" and type(value) ~= "userdata" then return nil end
    local ok, cls = pcall(pvm.classof, value)
    return ok and cls or nil
end

local function dispatch(kind) return { kind = kind } end

local function bind_context(T)
    T._lalin_api_cache = T._lalin_api_cache or {}
    if T._lalin_api_cache.tree_typecheck_rules ~= nil then return T._lalin_api_cache.tree_typecheck_rules end

    local Tr = T.LalinTree
    local relations = {
        select_stmt_typecheck = {
            field = "stmt",
            by_class = {
                [Tr.StmtLet] = "let",
                [Tr.StmtVar] = "var",
                [Tr.StmtSet] = "set",
                [Tr.StmtAtomicStore] = "atomic_store",
                [Tr.StmtAtomicFence] = "atomic_fence",
                [Tr.StmtExpr] = "expr",
                [Tr.StmtAssert] = "assert",
                [Tr.StmtReturnVoid] = "return_void",
                [Tr.StmtReturnValue] = "return_value",
                [Tr.StmtYieldVoid] = "yield_void",
                [Tr.StmtYieldValue] = "yield_value",
                [Tr.StmtIf] = "if",
                [Tr.StmtJump] = "jump",
                [Tr.StmtJumpCont] = "jump_cont",
                [Tr.StmtSwitch] = "switch",
                [Tr.StmtControl] = "control",
                [Tr.StmtTrap] = "trap",
            },
        },
        select_expr_typecheck = {
            field = "expr",
            by_class = {
                [Tr.ExprLit] = "lit",
                [Tr.ExprRef] = "ref",
                [Tr.ExprUnary] = "unary",
                [Tr.ExprBinary] = "binary",
                [Tr.ExprCompare] = "compare",
                [Tr.ExprLogic] = "logic",
                [Tr.ExprCast] = "cast",
                [Tr.ExprMachineCast] = "machine_cast",
                [Tr.ExprLen] = "len",
                [Tr.ExprCall] = "call",
                [Tr.ExprField] = "field",
                [Tr.ExprIndex] = "index",
                [Tr.ExprIf] = "if",
                [Tr.ExprSelect] = "select",
                [Tr.ExprControl] = "control",
                [Tr.ExprBlock] = "block",
                [Tr.ExprArray] = "array",
                [Tr.ExprAgg] = "agg",
                [Tr.ExprView] = "view",
                [Tr.ExprLoad] = "load",
                [Tr.ExprAtomicLoad] = "atomic_load",
                [Tr.ExprAtomicRmw] = "atomic_rmw",
                [Tr.ExprAtomicCas] = "atomic_cas",
                [Tr.ExprDot] = "dot",
                [Tr.ExprIntrinsic] = "intrinsic",
                [Tr.ExprAddrOf] = "addr_of",
                [Tr.ExprDeref] = "deref",
                [Tr.ExprSwitch] = "switch",
                [Tr.ExprClosure] = "closure",
                [Tr.ExprCtor] = "ctor",
                [Tr.ExprNull] = "null",
                [Tr.ExprSizeOf] = "sizeof",
                [Tr.ExprAlignOf] = "alignof",
                [Tr.ExprIsNull] = "is_null",
            },
        },
        select_view_typecheck = {
            field = "view",
            by_class = {
                [Tr.ViewFromExpr] = "from_expr",
                [Tr.ViewContiguous] = "contiguous",
                [Tr.ViewStrided] = "strided",
                [Tr.ViewRestrided] = "restrided",
                [Tr.ViewWindow] = "window",
                [Tr.ViewRowBase] = "row_base",
                [Tr.ViewInterleaved] = "interleaved",
                [Tr.ViewInterleavedView] = "interleaved_view",
            },
        },
        select_index_base_typecheck = {
            field = "index_base",
            by_class = {
                [Tr.IndexBaseExpr] = "expr",
                [Tr.IndexBaseView] = "view",
                [Tr.IndexBasePlace] = "place",
            },
        },
        select_place_typecheck = {
            field = "place",
            by_class = {
                [Tr.PlaceRef] = "ref",
                [Tr.PlaceDeref] = "deref",
                [Tr.PlaceDot] = "dot",
                [Tr.PlaceField] = "field",
                [Tr.PlaceIndex] = "index",
            },
        },
        select_control_stmt_region_typecheck = {
            field = "control_stmt_region",
            by_class = { [Tr.ControlStmtRegion] = "stmt_region" },
        },
        select_control_expr_region_typecheck = {
            field = "control_expr_region",
            by_class = { [Tr.ControlExprRegion] = "expr_region" },
        },
        select_func_typecheck = {
            field = "func",
            by_class = {
                [Tr.FuncLocal] = "local",
                [Tr.FuncExport] = "export",
                [Tr.FuncLocalContract] = "local_contract",
                [Tr.FuncExportContract] = "export_contract",
            },
        },
        select_item_typecheck = {
            field = "item",
            by_class = {
                [Tr.ItemFunc] = "func",
                [Tr.ItemConst] = "const",
                [Tr.ItemStatic] = "static",
                [Tr.ItemExtern] = "extern",
                [Tr.ItemImport] = "import",
                [Tr.ItemType] = "type",
                [Tr.ItemRegion] = "region",
            },
        },
        select_module_typecheck = {
            field = "module",
            by_class = { [Tr.Module] = "module" },
        },
    }

    local api = {}
    function api:run(relation, input, _output_key, missing)
        local spec = relations[relation]
        if spec == nil then return nil, missing or ("unknown tree typecheck dispatch " .. tostring(relation)) end
        local node = input and input[spec.field]
        local kind = spec.by_class[safe_classof(node)]
        if kind == nil then return nil, missing or ("no tree typecheck dispatch for " .. tostring(relation)) end
        return dispatch(kind)
    end

    T._lalin_api_cache.tree_typecheck_rules = api
    return api
end

return bind_context
