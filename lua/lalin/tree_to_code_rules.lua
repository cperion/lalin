local pvm = require("lalin.pvm")

local function safe_classof(value)
    if type(value) ~= "table" and type(value) ~= "userdata" then return nil end
    local ok, cls = pcall(pvm.classof, value)
    return ok and cls or nil
end

local function dispatch(kind) return { kind = kind } end

local function bind_context(T)
    T._lalin_api_cache = T._lalin_api_cache or {}
    if T._lalin_api_cache.tree_to_code_rules ~= nil then return T._lalin_api_cache.tree_to_code_rules end

    local Tr = T.LalinTree
    local relations = {
        select_expr_lowering = {
            field = "expr",
            by_class = {
                [Tr.ExprLit] = "lit",
                [Tr.ExprRef] = "ref",
                [Tr.ExprUnary] = "unary",
                [Tr.ExprBinary] = "binary",
                [Tr.ExprCompare] = "compare",
                [Tr.ExprLogic] = "logic",
                [Tr.ExprIf] = "if",
                [Tr.ExprSwitch] = "switch",
                [Tr.ExprControl] = "control",
                [Tr.ExprBlock] = "block",
                [Tr.ExprMachineCast] = "machine_cast",
                [Tr.ExprCast] = "surface_cast",
                [Tr.ExprSelect] = "select",
                [Tr.ExprAddrOf] = "addr_of",
                [Tr.ExprIntrinsic] = "intrinsic",
                [Tr.ExprAgg] = "agg",
                [Tr.ExprArray] = "array",
                [Tr.ExprView] = "view",
                [Tr.ExprLen] = "len",
                [Tr.ExprSizeOf] = "sizeof",
                [Tr.ExprAlignOf] = "alignof",
                [Tr.ExprIsNull] = "is_null",
                [Tr.ExprCall] = "call",
                [Tr.ExprDeref] = "deref",
                [Tr.ExprField] = "field",
                [Tr.ExprIndex] = "index",
                [Tr.ExprLoad] = "load",
                [Tr.ExprAtomicLoad] = "atomic_load",
                [Tr.ExprAtomicRmw] = "atomic_rmw",
                [Tr.ExprAtomicCas] = "atomic_cas",
                [Tr.ExprCtor] = "ctor",
                [Tr.ExprNull] = "null",
            },
        },
        select_place_lowering = {
            field = "place",
            by_class = {
                [Tr.PlaceRef] = "ref",
                [Tr.PlaceDeref] = "deref",
                [Tr.PlaceField] = "field",
                [Tr.PlaceIndex] = "index",
                [Tr.PlaceDot] = "dot",
            },
        },
        select_stmt_lowering = {
            field = "stmt",
            by_class = {
                [Tr.StmtLet] = "let",
                [Tr.StmtVar] = "var",
                [Tr.StmtSet] = "set",
                [Tr.StmtAtomicStore] = "atomic_store",
                [Tr.StmtAtomicFence] = "atomic_fence",
                [Tr.StmtExpr] = "expr",
                [Tr.StmtIf] = "if",
                [Tr.StmtSwitch] = "switch",
                [Tr.StmtControl] = "control",
                [Tr.StmtJump] = "jump",
                [Tr.StmtJumpCont] = "jump_cont",
                [Tr.StmtYieldValue] = "yield_value",
                [Tr.StmtYieldVoid] = "yield_void",
                [Tr.StmtReturnValue] = "return_value",
                [Tr.StmtReturnVoid] = "return_void",
                [Tr.StmtTrap] = "trap",
                [Tr.StmtAssert] = "assert",
            },
        },
        select_func_lowering = {
            field = "func",
            by_class = {
                [Tr.FuncLocal] = "local",
                [Tr.FuncExport] = "export",
                [Tr.FuncLocalContract] = "local_contract",
                [Tr.FuncExportContract] = "export_contract",
            },
        },
        select_item_lowering = {
            field = "item",
            by_class = {
                [Tr.ItemFunc] = "func",
                [Tr.ItemData] = "data",
                [Tr.ItemConst] = "const",
                [Tr.ItemStatic] = "static",
                [Tr.ItemExtern] = "extern",
                [Tr.ItemType] = "type",
                [Tr.ItemImport] = "import",
                [Tr.ItemRegion] = "region",
            },
        },
        select_contract_fact_lowering = {
            field = "contract_fact",
            by_class = {
                [Tr.ContractFactBounds] = "bounds",
                [Tr.ContractFactWindowBounds] = "window_bounds",
                [Tr.ContractFactDisjoint] = "disjoint",
                [Tr.ContractFactSameLen] = "same_len",
                [Tr.ContractFactSoAComponent] = "soa_component",
                [Tr.ContractFactNoAlias] = "noalias",
                [Tr.ContractFactReadonly] = "readonly",
                [Tr.ContractFactWriteonly] = "writeonly",
                [Tr.ContractFactInvalidate] = "invalidate",
                [Tr.ContractFactPreserve] = "preserve",
                [Tr.ContractFactRejected] = "rejected",
            },
        },
    }

    local api = {}
    function api:run(relation, input, _output_key, missing)
        local spec = relations[relation]
        if spec == nil then return nil, missing or ("unknown tree-to-code dispatch " .. tostring(relation)) end
        local node = input and input[spec.field]
        local kind = spec.by_class[safe_classof(node)]
        if kind == nil then return nil, missing or ("no tree-to-code dispatch for " .. tostring(relation)) end
        return dispatch(kind)
    end

    T._lalin_api_cache.tree_to_code_rules = api
    return api
end

return bind_context
