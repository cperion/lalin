local function bind_context(T)
    T._moonlift_api_cache = T._moonlift_api_cache or {}
    if T._moonlift_api_cache.tree_to_code_rules ~= nil then return T._moonlift_api_cache.tree_to_code_rules end

    local moon = require("moonlift")
    local llb = require("llb")
    local Llisle = require("llisle")
    local env = moon.family.env { scope = "env", base = _G }
    Llisle.use { scope = "env", target = env, base = env, global = false }
    local llisle = env.llisle

    local Candidate = llb.symbol("TreeToCodeDispatchCandidate")
    local Selection = llb.symbol("TreeToCodeDispatchSelection")
    local candidate = llb.symbol("candidate")
    local dispatch_selection = llb.symbol("dispatch_selection")

    local function build_selection(fields) return fields end

    local function build_rules()
    return llisle {
  constructor. dispatch_selection [build_selection],

  relation. select_expr_lowering {
    input { candidate [Candidate] },
    output { selection [Selection] },
    strategy { select. best_cost, ambiguity. error },
  },

  relation. select_place_lowering {
    input { candidate [Candidate] },
    output { selection [Selection] },
    strategy { select. best_cost, ambiguity. error },
  },

  relation. select_stmt_lowering {
    input { candidate [Candidate] },
    output { selection [Selection] },
    strategy { select. best_cost, ambiguity. error },
  },

  relation. select_func_lowering {
    input { candidate [Candidate] },
    output { selection [Selection] },
    strategy { select. best_cost, ambiguity. error },
  },

  relation. select_item_lowering {
    input { candidate [Candidate] },
    output { selection [Selection] },
    strategy { select. best_cost, ambiguity. error },
  },

  relation. select_contract_fact_lowering {
    input { candidate [Candidate] },
    output { selection [Selection] },
    strategy { select. best_cost, ambiguity. error },
  },

  rule. expr_lit { llisle.select_expr_lowering { candidate = P. candidate }, when { P. candidate.kind :eq ("ExprLit") }, run { ret { selection = dispatch_selection { kind = "lit" } } } },
  rule. expr_ref { llisle.select_expr_lowering { candidate = P. candidate }, when { P. candidate.kind :eq ("ExprRef") }, run { ret { selection = dispatch_selection { kind = "ref" } } } },
  rule. expr_unary { llisle.select_expr_lowering { candidate = P. candidate }, when { P. candidate.kind :eq ("ExprUnary") }, run { ret { selection = dispatch_selection { kind = "unary" } } } },
  rule. expr_binary { llisle.select_expr_lowering { candidate = P. candidate }, when { P. candidate.kind :eq ("ExprBinary") }, run { ret { selection = dispatch_selection { kind = "binary" } } } },
  rule. expr_compare { llisle.select_expr_lowering { candidate = P. candidate }, when { P. candidate.kind :eq ("ExprCompare") }, run { ret { selection = dispatch_selection { kind = "compare" } } } },
  rule. expr_logic { llisle.select_expr_lowering { candidate = P. candidate }, when { P. candidate.kind :eq ("ExprLogic") }, run { ret { selection = dispatch_selection { kind = "logic" } } } },
  rule. expr_if { llisle.select_expr_lowering { candidate = P. candidate }, when { P. candidate.kind :eq ("ExprIf") }, run { ret { selection = dispatch_selection { kind = "if" } } } },
  rule. expr_switch { llisle.select_expr_lowering { candidate = P. candidate }, when { P. candidate.kind :eq ("ExprSwitch") }, run { ret { selection = dispatch_selection { kind = "switch" } } } },
  rule. expr_control { llisle.select_expr_lowering { candidate = P. candidate }, when { P. candidate.kind :eq ("ExprControl") }, run { ret { selection = dispatch_selection { kind = "control" } } } },
  rule. expr_block { llisle.select_expr_lowering { candidate = P. candidate }, when { P. candidate.kind :eq ("ExprBlock") }, run { ret { selection = dispatch_selection { kind = "block" } } } },
  rule. expr_machine_cast { llisle.select_expr_lowering { candidate = P. candidate }, when { P. candidate.kind :eq ("ExprMachineCast") }, run { ret { selection = dispatch_selection { kind = "machine_cast" } } } },
  rule. expr_cast { llisle.select_expr_lowering { candidate = P. candidate }, when { P. candidate.kind :eq ("ExprCast") }, run { ret { selection = dispatch_selection { kind = "surface_cast" } } } },
  rule. expr_select { llisle.select_expr_lowering { candidate = P. candidate }, when { P. candidate.kind :eq ("ExprSelect") }, run { ret { selection = dispatch_selection { kind = "select" } } } },
  rule. expr_addr_of { llisle.select_expr_lowering { candidate = P. candidate }, when { P. candidate.kind :eq ("ExprAddrOf") }, run { ret { selection = dispatch_selection { kind = "addr_of" } } } },
  rule. expr_intrinsic { llisle.select_expr_lowering { candidate = P. candidate }, when { P. candidate.kind :eq ("ExprIntrinsic") }, run { ret { selection = dispatch_selection { kind = "intrinsic" } } } },
  rule. expr_agg { llisle.select_expr_lowering { candidate = P. candidate }, when { P. candidate.kind :eq ("ExprAgg") }, run { ret { selection = dispatch_selection { kind = "agg" } } } },
  rule. expr_array { llisle.select_expr_lowering { candidate = P. candidate }, when { P. candidate.kind :eq ("ExprArray") }, run { ret { selection = dispatch_selection { kind = "array" } } } },
  rule. expr_view { llisle.select_expr_lowering { candidate = P. candidate }, when { P. candidate.kind :eq ("ExprView") }, run { ret { selection = dispatch_selection { kind = "view" } } } },
  rule. expr_len { llisle.select_expr_lowering { candidate = P. candidate }, when { P. candidate.kind :eq ("ExprLen") }, run { ret { selection = dispatch_selection { kind = "len" } } } },
  rule. expr_sizeof { llisle.select_expr_lowering { candidate = P. candidate }, when { P. candidate.kind :eq ("ExprSizeOf") }, run { ret { selection = dispatch_selection { kind = "sizeof" } } } },
  rule. expr_alignof { llisle.select_expr_lowering { candidate = P. candidate }, when { P. candidate.kind :eq ("ExprAlignOf") }, run { ret { selection = dispatch_selection { kind = "alignof" } } } },
  rule. expr_is_null { llisle.select_expr_lowering { candidate = P. candidate }, when { P. candidate.kind :eq ("ExprIsNull") }, run { ret { selection = dispatch_selection { kind = "is_null" } } } },
  rule. expr_call { llisle.select_expr_lowering { candidate = P. candidate }, when { P. candidate.kind :eq ("ExprCall") }, run { ret { selection = dispatch_selection { kind = "call" } } } },
  rule. expr_deref { llisle.select_expr_lowering { candidate = P. candidate }, when { P. candidate.kind :eq ("ExprDeref") }, run { ret { selection = dispatch_selection { kind = "deref" } } } },
  rule. expr_field { llisle.select_expr_lowering { candidate = P. candidate }, when { P. candidate.kind :eq ("ExprField") }, run { ret { selection = dispatch_selection { kind = "field" } } } },
  rule. expr_index { llisle.select_expr_lowering { candidate = P. candidate }, when { P. candidate.kind :eq ("ExprIndex") }, run { ret { selection = dispatch_selection { kind = "index" } } } },
  rule. expr_load { llisle.select_expr_lowering { candidate = P. candidate }, when { P. candidate.kind :eq ("ExprLoad") }, run { ret { selection = dispatch_selection { kind = "load" } } } },
  rule. expr_atomic_load { llisle.select_expr_lowering { candidate = P. candidate }, when { P. candidate.kind :eq ("ExprAtomicLoad") }, run { ret { selection = dispatch_selection { kind = "atomic_load" } } } },
  rule. expr_atomic_rmw { llisle.select_expr_lowering { candidate = P. candidate }, when { P. candidate.kind :eq ("ExprAtomicRmw") }, run { ret { selection = dispatch_selection { kind = "atomic_rmw" } } } },
  rule. expr_atomic_cas { llisle.select_expr_lowering { candidate = P. candidate }, when { P. candidate.kind :eq ("ExprAtomicCas") }, run { ret { selection = dispatch_selection { kind = "atomic_cas" } } } },
  rule. expr_ctor { llisle.select_expr_lowering { candidate = P. candidate }, when { P. candidate.kind :eq ("ExprCtor") }, run { ret { selection = dispatch_selection { kind = "ctor" } } } },
  rule. expr_null { llisle.select_expr_lowering { candidate = P. candidate }, when { P. candidate.kind :eq ("ExprNull") }, run { ret { selection = dispatch_selection { kind = "null" } } } },

  rule. place_ref { llisle.select_place_lowering { candidate = P. candidate }, when { P. candidate.kind :eq ("PlaceRef") }, run { ret { selection = dispatch_selection { kind = "ref" } } } },
  rule. place_deref { llisle.select_place_lowering { candidate = P. candidate }, when { P. candidate.kind :eq ("PlaceDeref") }, run { ret { selection = dispatch_selection { kind = "deref" } } } },
  rule. place_field { llisle.select_place_lowering { candidate = P. candidate }, when { P. candidate.kind :eq ("PlaceField") }, run { ret { selection = dispatch_selection { kind = "field" } } } },
  rule. place_index { llisle.select_place_lowering { candidate = P. candidate }, when { P. candidate.kind :eq ("PlaceIndex") }, run { ret { selection = dispatch_selection { kind = "index" } } } },
  rule. place_dot { llisle.select_place_lowering { candidate = P. candidate }, when { P. candidate.kind :eq ("PlaceDot") }, run { ret { selection = dispatch_selection { kind = "dot" } } } },

  rule. stmt_let { llisle.select_stmt_lowering { candidate = P. candidate }, when { P. candidate.kind :eq ("StmtLet") }, run { ret { selection = dispatch_selection { kind = "let" } } } },
  rule. stmt_var { llisle.select_stmt_lowering { candidate = P. candidate }, when { P. candidate.kind :eq ("StmtVar") }, run { ret { selection = dispatch_selection { kind = "var" } } } },
  rule. stmt_set { llisle.select_stmt_lowering { candidate = P. candidate }, when { P. candidate.kind :eq ("StmtSet") }, run { ret { selection = dispatch_selection { kind = "set" } } } },
  rule. stmt_atomic_store { llisle.select_stmt_lowering { candidate = P. candidate }, when { P. candidate.kind :eq ("StmtAtomicStore") }, run { ret { selection = dispatch_selection { kind = "atomic_store" } } } },
  rule. stmt_atomic_fence { llisle.select_stmt_lowering { candidate = P. candidate }, when { P. candidate.kind :eq ("StmtAtomicFence") }, run { ret { selection = dispatch_selection { kind = "atomic_fence" } } } },
  rule. stmt_expr { llisle.select_stmt_lowering { candidate = P. candidate }, when { P. candidate.kind :eq ("StmtExpr") }, run { ret { selection = dispatch_selection { kind = "expr" } } } },
  rule. stmt_if { llisle.select_stmt_lowering { candidate = P. candidate }, when { P. candidate.kind :eq ("StmtIf") }, run { ret { selection = dispatch_selection { kind = "if" } } } },
  rule. stmt_switch { llisle.select_stmt_lowering { candidate = P. candidate }, when { P. candidate.kind :eq ("StmtSwitch") }, run { ret { selection = dispatch_selection { kind = "switch" } } } },
  rule. stmt_control { llisle.select_stmt_lowering { candidate = P. candidate }, when { P. candidate.kind :eq ("StmtControl") }, run { ret { selection = dispatch_selection { kind = "control" } } } },
  rule. stmt_jump { llisle.select_stmt_lowering { candidate = P. candidate }, when { P. candidate.kind :eq ("StmtJump") }, run { ret { selection = dispatch_selection { kind = "jump" } } } },
  rule. stmt_jump_cont { llisle.select_stmt_lowering { candidate = P. candidate }, when { P. candidate.kind :eq ("StmtJumpCont") }, run { ret { selection = dispatch_selection { kind = "jump_cont" } } } },
  rule. stmt_yield_value { llisle.select_stmt_lowering { candidate = P. candidate }, when { P. candidate.kind :eq ("StmtYieldValue") }, run { ret { selection = dispatch_selection { kind = "yield_value" } } } },
  rule. stmt_yield_void { llisle.select_stmt_lowering { candidate = P. candidate }, when { P. candidate.kind :eq ("StmtYieldVoid") }, run { ret { selection = dispatch_selection { kind = "yield_void" } } } },
  rule. stmt_return_value { llisle.select_stmt_lowering { candidate = P. candidate }, when { P. candidate.kind :eq ("StmtReturnValue") }, run { ret { selection = dispatch_selection { kind = "return_value" } } } },
  rule. stmt_return_void { llisle.select_stmt_lowering { candidate = P. candidate }, when { P. candidate.kind :eq ("StmtReturnVoid") }, run { ret { selection = dispatch_selection { kind = "return_void" } } } },
  rule. stmt_trap { llisle.select_stmt_lowering { candidate = P. candidate }, when { P. candidate.kind :eq ("StmtTrap") }, run { ret { selection = dispatch_selection { kind = "trap" } } } },
  rule. stmt_assert { llisle.select_stmt_lowering { candidate = P. candidate }, when { P. candidate.kind :eq ("StmtAssert") }, run { ret { selection = dispatch_selection { kind = "assert" } } } },

  rule. func_local { llisle.select_func_lowering { candidate = P. candidate }, when { P. candidate.kind :eq ("FuncLocal") }, run { ret { selection = dispatch_selection { kind = "local" } } } },
  rule. func_export { llisle.select_func_lowering { candidate = P. candidate }, when { P. candidate.kind :eq ("FuncExport") }, run { ret { selection = dispatch_selection { kind = "export" } } } },
  rule. func_local_contract { llisle.select_func_lowering { candidate = P. candidate }, when { P. candidate.kind :eq ("FuncLocalContract") }, run { ret { selection = dispatch_selection { kind = "local_contract" } } } },
  rule. func_export_contract { llisle.select_func_lowering { candidate = P. candidate }, when { P. candidate.kind :eq ("FuncExportContract") }, run { ret { selection = dispatch_selection { kind = "export_contract" } } } },

  rule. item_func { llisle.select_item_lowering { candidate = P. candidate }, when { P. candidate.kind :eq ("ItemFunc") }, run { ret { selection = dispatch_selection { kind = "func" } } } },
  rule. item_data { llisle.select_item_lowering { candidate = P. candidate }, when { P. candidate.kind :eq ("ItemData") }, run { ret { selection = dispatch_selection { kind = "data" } } } },
  rule. item_const { llisle.select_item_lowering { candidate = P. candidate }, when { P. candidate.kind :eq ("ItemConst") }, run { ret { selection = dispatch_selection { kind = "const" } } } },
  rule. item_static { llisle.select_item_lowering { candidate = P. candidate }, when { P. candidate.kind :eq ("ItemStatic") }, run { ret { selection = dispatch_selection { kind = "static" } } } },
  rule. item_extern { llisle.select_item_lowering { candidate = P. candidate }, when { P. candidate.kind :eq ("ItemExtern") }, run { ret { selection = dispatch_selection { kind = "extern" } } } },
  rule. item_type { llisle.select_item_lowering { candidate = P. candidate }, when { P. candidate.kind :eq ("ItemType") }, run { ret { selection = dispatch_selection { kind = "type" } } } },
  rule. item_import { llisle.select_item_lowering { candidate = P. candidate }, when { P. candidate.kind :eq ("ItemImport") }, run { ret { selection = dispatch_selection { kind = "import" } } } },
  rule. item_region_frag { llisle.select_item_lowering { candidate = P. candidate }, when { P. candidate.kind :eq ("ItemRegionFrag") }, run { ret { selection = dispatch_selection { kind = "region_frag" } } } },
  rule. item_expr_frag { llisle.select_item_lowering { candidate = P. candidate }, when { P. candidate.kind :eq ("ItemExprFrag") }, run { ret { selection = dispatch_selection { kind = "expr_frag" } } } },

  rule. contract_fact_bounds { llisle.select_contract_fact_lowering { candidate = P. candidate }, when { P. candidate.kind :eq ("ContractFactBounds") }, run { ret { selection = dispatch_selection { kind = "bounds" } } } },
  rule. contract_fact_window_bounds { llisle.select_contract_fact_lowering { candidate = P. candidate }, when { P. candidate.kind :eq ("ContractFactWindowBounds") }, run { ret { selection = dispatch_selection { kind = "window_bounds" } } } },
  rule. contract_fact_disjoint { llisle.select_contract_fact_lowering { candidate = P. candidate }, when { P. candidate.kind :eq ("ContractFactDisjoint") }, run { ret { selection = dispatch_selection { kind = "disjoint" } } } },
  rule. contract_fact_same_len { llisle.select_contract_fact_lowering { candidate = P. candidate }, when { P. candidate.kind :eq ("ContractFactSameLen") }, run { ret { selection = dispatch_selection { kind = "same_len" } } } },
  rule. contract_fact_soa_component { llisle.select_contract_fact_lowering { candidate = P. candidate }, when { P. candidate.kind :eq ("ContractFactSoAComponent") }, run { ret { selection = dispatch_selection { kind = "soa_component" } } } },
  rule. contract_fact_noalias { llisle.select_contract_fact_lowering { candidate = P. candidate }, when { P. candidate.kind :eq ("ContractFactNoAlias") }, run { ret { selection = dispatch_selection { kind = "noalias" } } } },
  rule. contract_fact_readonly { llisle.select_contract_fact_lowering { candidate = P. candidate }, when { P. candidate.kind :eq ("ContractFactReadonly") }, run { ret { selection = dispatch_selection { kind = "readonly" } } } },
  rule. contract_fact_writeonly { llisle.select_contract_fact_lowering { candidate = P. candidate }, when { P. candidate.kind :eq ("ContractFactWriteonly") }, run { ret { selection = dispatch_selection { kind = "writeonly" } } } },
  rule. contract_fact_invalidate { llisle.select_contract_fact_lowering { candidate = P. candidate }, when { P. candidate.kind :eq ("ContractFactInvalidate") }, run { ret { selection = dispatch_selection { kind = "invalidate" } } } },
  rule. contract_fact_preserve { llisle.select_contract_fact_lowering { candidate = P. candidate }, when { P. candidate.kind :eq ("ContractFactPreserve") }, run { ret { selection = dispatch_selection { kind = "preserve" } } } },
  rule. contract_fact_rejected { llisle.select_contract_fact_lowering { candidate = P. candidate }, when { P. candidate.kind :eq ("ContractFactRejected") }, run { ret { selection = dispatch_selection { kind = "rejected" } } } },
}
    end
    if setfenv then setfenv(build_rules, env) end
    local rules = build_rules()
    local engine = Llisle.compile(rules)

    local api = {}

    local function select_relation(name, node)
        local cls = require("moonlift.pvm").classof(node)
        local raw = cls and cls.kind or tostring(cls)
        local kind = raw:match("^Class%(MoonTree%.(.+)%)$") or raw
        local result, err = engine:run(name, { candidate = { kind = kind } })
        if result == nil then return nil, err and err.message or ("no tree_to_code dispatch for " .. tostring(kind)) end
        return result.output.selection, nil
    end

    function api.select_expr(expr) return select_relation("select_expr_lowering", expr) end
    function api.select_place(place) return select_relation("select_place_lowering", place) end
    function api.select_stmt(stmt) return select_relation("select_stmt_lowering", stmt) end
    function api.select_func(func) return select_relation("select_func_lowering", func) end
    function api.select_item(item) return select_relation("select_item_lowering", item) end
    function api.select_contract_fact(fact) return select_relation("select_contract_fact_lowering", fact) end

    api.rules = rules
    api.engine = engine

    T._moonlift_api_cache.tree_to_code_rules = api
    return api
end

return bind_context
