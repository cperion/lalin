local function bind_context(T)
    T._moonlift_api_cache = T._moonlift_api_cache or {}
    if T._moonlift_api_cache.tree_typecheck_rules ~= nil then return T._moonlift_api_cache.tree_typecheck_rules end

    local moon = require("moonlift")
    local llb = require("llb")
    local Llisle = require("llisle")
    local pvm = require("moonlift.pvm")
    local env = moon.family.env { scope = "env", base = _G }
    Llisle.use { scope = "env", target = env, base = env, global = false }
    local llisle = env.llisle

    local Candidate = llb.symbol("TreeTypecheckDispatchCandidate")
    local Selection = llb.symbol("TreeTypecheckDispatchSelection")
    local candidate = llb.symbol("candidate")
    local dispatch_selection = llb.symbol("dispatch_selection")

    local function build_selection(fields) return fields end

    local function build_rules()
    return llisle {
  constructor. dispatch_selection [build_selection],

  relation. select_stmt_typecheck {
    input { candidate [Candidate] },
    output { selection [Selection] },
    strategy { select. best_cost, ambiguity. error },
  },

  relation. select_expr_typecheck {
    input { candidate [Candidate] },
    output { selection [Selection] },
    strategy { select. best_cost, ambiguity. error },
  },

  relation. select_view_typecheck {
    input { candidate [Candidate] },
    output { selection [Selection] },
    strategy { select. best_cost, ambiguity. error },
  },

  relation. select_index_base_typecheck {
    input { candidate [Candidate] },
    output { selection [Selection] },
    strategy { select. best_cost, ambiguity. error },
  },

  relation. select_place_typecheck {
    input { candidate [Candidate] },
    output { selection [Selection] },
    strategy { select. best_cost, ambiguity. error },
  },

  relation. select_control_stmt_region_typecheck {
    input { candidate [Candidate] },
    output { selection [Selection] },
    strategy { select. best_cost, ambiguity. error },
  },

  relation. select_control_expr_region_typecheck {
    input { candidate [Candidate] },
    output { selection [Selection] },
    strategy { select. best_cost, ambiguity. error },
  },

  relation. select_func_typecheck {
    input { candidate [Candidate] },
    output { selection [Selection] },
    strategy { select. best_cost, ambiguity. error },
  },

  relation. select_item_typecheck {
    input { candidate [Candidate] },
    output { selection [Selection] },
    strategy { select. best_cost, ambiguity. error },
  },

  relation. select_module_typecheck {
    input { candidate [Candidate] },
    output { selection [Selection] },
    strategy { select. best_cost, ambiguity. error },
  },

  rule. stmt_let { llisle.select_stmt_typecheck { candidate = P. candidate }, when { P. candidate.kind :eq ("StmtLet") }, run { ret { selection = dispatch_selection { kind = "let" } } } },
  rule. stmt_var { llisle.select_stmt_typecheck { candidate = P. candidate }, when { P. candidate.kind :eq ("StmtVar") }, run { ret { selection = dispatch_selection { kind = "var" } } } },
  rule. stmt_set { llisle.select_stmt_typecheck { candidate = P. candidate }, when { P. candidate.kind :eq ("StmtSet") }, run { ret { selection = dispatch_selection { kind = "set" } } } },
  rule. stmt_atomic_store { llisle.select_stmt_typecheck { candidate = P. candidate }, when { P. candidate.kind :eq ("StmtAtomicStore") }, run { ret { selection = dispatch_selection { kind = "atomic_store" } } } },
  rule. stmt_atomic_fence { llisle.select_stmt_typecheck { candidate = P. candidate }, when { P. candidate.kind :eq ("StmtAtomicFence") }, run { ret { selection = dispatch_selection { kind = "atomic_fence" } } } },
  rule. stmt_expr { llisle.select_stmt_typecheck { candidate = P. candidate }, when { P. candidate.kind :eq ("StmtExpr") }, run { ret { selection = dispatch_selection { kind = "expr" } } } },
  rule. stmt_assert { llisle.select_stmt_typecheck { candidate = P. candidate }, when { P. candidate.kind :eq ("StmtAssert") }, run { ret { selection = dispatch_selection { kind = "assert" } } } },
  rule. stmt_return_void { llisle.select_stmt_typecheck { candidate = P. candidate }, when { P. candidate.kind :eq ("StmtReturnVoid") }, run { ret { selection = dispatch_selection { kind = "return_void" } } } },
  rule. stmt_return_value { llisle.select_stmt_typecheck { candidate = P. candidate }, when { P. candidate.kind :eq ("StmtReturnValue") }, run { ret { selection = dispatch_selection { kind = "return_value" } } } },
  rule. stmt_yield_void { llisle.select_stmt_typecheck { candidate = P. candidate }, when { P. candidate.kind :eq ("StmtYieldVoid") }, run { ret { selection = dispatch_selection { kind = "yield_void" } } } },
  rule. stmt_yield_value { llisle.select_stmt_typecheck { candidate = P. candidate }, when { P. candidate.kind :eq ("StmtYieldValue") }, run { ret { selection = dispatch_selection { kind = "yield_value" } } } },
  rule. stmt_if { llisle.select_stmt_typecheck { candidate = P. candidate }, when { P. candidate.kind :eq ("StmtIf") }, run { ret { selection = dispatch_selection { kind = "if" } } } },
  rule. stmt_jump { llisle.select_stmt_typecheck { candidate = P. candidate }, when { P. candidate.kind :eq ("StmtJump") }, run { ret { selection = dispatch_selection { kind = "jump" } } } },
  rule. stmt_jump_cont { llisle.select_stmt_typecheck { candidate = P. candidate }, when { P. candidate.kind :eq ("StmtJumpCont") }, run { ret { selection = dispatch_selection { kind = "jump_cont" } } } },
  rule. stmt_switch { llisle.select_stmt_typecheck { candidate = P. candidate }, when { P. candidate.kind :eq ("StmtSwitch") }, run { ret { selection = dispatch_selection { kind = "switch" } } } },
  rule. stmt_control { llisle.select_stmt_typecheck { candidate = P. candidate }, when { P. candidate.kind :eq ("StmtControl") }, run { ret { selection = dispatch_selection { kind = "control" } } } },
  rule. stmt_trap { llisle.select_stmt_typecheck { candidate = P. candidate }, when { P. candidate.kind :eq ("StmtTrap") }, run { ret { selection = dispatch_selection { kind = "trap" } } } },
  rule. stmt_use_region_slot { llisle.select_stmt_typecheck { candidate = P. candidate }, when { P. candidate.kind :eq ("StmtUseRegionSlot") }, run { ret { selection = dispatch_selection { kind = "use_region_slot" } } } },
  rule. stmt_use_region_frag { llisle.select_stmt_typecheck { candidate = P. candidate }, when { P. candidate.kind :eq ("StmtUseRegionFrag") }, run { ret { selection = dispatch_selection { kind = "use_region_frag" } } } },

  rule. expr_lit { llisle.select_expr_typecheck { candidate = P. candidate }, when { P. candidate.kind :eq ("ExprLit") }, run { ret { selection = dispatch_selection { kind = "lit" } } } },
  rule. expr_ref { llisle.select_expr_typecheck { candidate = P. candidate }, when { P. candidate.kind :eq ("ExprRef") }, run { ret { selection = dispatch_selection { kind = "ref" } } } },
  rule. expr_unary { llisle.select_expr_typecheck { candidate = P. candidate }, when { P. candidate.kind :eq ("ExprUnary") }, run { ret { selection = dispatch_selection { kind = "unary" } } } },
  rule. expr_binary { llisle.select_expr_typecheck { candidate = P. candidate }, when { P. candidate.kind :eq ("ExprBinary") }, run { ret { selection = dispatch_selection { kind = "binary" } } } },
  rule. expr_compare { llisle.select_expr_typecheck { candidate = P. candidate }, when { P. candidate.kind :eq ("ExprCompare") }, run { ret { selection = dispatch_selection { kind = "compare" } } } },
  rule. expr_logic { llisle.select_expr_typecheck { candidate = P. candidate }, when { P. candidate.kind :eq ("ExprLogic") }, run { ret { selection = dispatch_selection { kind = "logic" } } } },
  rule. expr_cast { llisle.select_expr_typecheck { candidate = P. candidate }, when { P. candidate.kind :eq ("ExprCast") }, run { ret { selection = dispatch_selection { kind = "cast" } } } },
  rule. expr_machine_cast { llisle.select_expr_typecheck { candidate = P. candidate }, when { P. candidate.kind :eq ("ExprMachineCast") }, run { ret { selection = dispatch_selection { kind = "machine_cast" } } } },
  rule. expr_len { llisle.select_expr_typecheck { candidate = P. candidate }, when { P. candidate.kind :eq ("ExprLen") }, run { ret { selection = dispatch_selection { kind = "len" } } } },
  rule. expr_call { llisle.select_expr_typecheck { candidate = P. candidate }, when { P. candidate.kind :eq ("ExprCall") }, run { ret { selection = dispatch_selection { kind = "call" } } } },
  rule. expr_field { llisle.select_expr_typecheck { candidate = P. candidate }, when { P. candidate.kind :eq ("ExprField") }, run { ret { selection = dispatch_selection { kind = "field" } } } },
  rule. expr_index { llisle.select_expr_typecheck { candidate = P. candidate }, when { P. candidate.kind :eq ("ExprIndex") }, run { ret { selection = dispatch_selection { kind = "index" } } } },
  rule. expr_if { llisle.select_expr_typecheck { candidate = P. candidate }, when { P. candidate.kind :eq ("ExprIf") }, run { ret { selection = dispatch_selection { kind = "if" } } } },
  rule. expr_select { llisle.select_expr_typecheck { candidate = P. candidate }, when { P. candidate.kind :eq ("ExprSelect") }, run { ret { selection = dispatch_selection { kind = "select" } } } },
  rule. expr_control { llisle.select_expr_typecheck { candidate = P. candidate }, when { P. candidate.kind :eq ("ExprControl") }, run { ret { selection = dispatch_selection { kind = "control" } } } },
  rule. expr_block { llisle.select_expr_typecheck { candidate = P. candidate }, when { P. candidate.kind :eq ("ExprBlock") }, run { ret { selection = dispatch_selection { kind = "block" } } } },
  rule. expr_array { llisle.select_expr_typecheck { candidate = P. candidate }, when { P. candidate.kind :eq ("ExprArray") }, run { ret { selection = dispatch_selection { kind = "array" } } } },
  rule. expr_agg { llisle.select_expr_typecheck { candidate = P. candidate }, when { P. candidate.kind :eq ("ExprAgg") }, run { ret { selection = dispatch_selection { kind = "agg" } } } },
  rule. expr_view { llisle.select_expr_typecheck { candidate = P. candidate }, when { P. candidate.kind :eq ("ExprView") }, run { ret { selection = dispatch_selection { kind = "view" } } } },
  rule. expr_load { llisle.select_expr_typecheck { candidate = P. candidate }, when { P. candidate.kind :eq ("ExprLoad") }, run { ret { selection = dispatch_selection { kind = "load" } } } },
  rule. expr_atomic_load { llisle.select_expr_typecheck { candidate = P. candidate }, when { P. candidate.kind :eq ("ExprAtomicLoad") }, run { ret { selection = dispatch_selection { kind = "atomic_load" } } } },
  rule. expr_atomic_rmw { llisle.select_expr_typecheck { candidate = P. candidate }, when { P. candidate.kind :eq ("ExprAtomicRmw") }, run { ret { selection = dispatch_selection { kind = "atomic_rmw" } } } },
  rule. expr_atomic_cas { llisle.select_expr_typecheck { candidate = P. candidate }, when { P. candidate.kind :eq ("ExprAtomicCas") }, run { ret { selection = dispatch_selection { kind = "atomic_cas" } } } },
  rule. expr_dot { llisle.select_expr_typecheck { candidate = P. candidate }, when { P. candidate.kind :eq ("ExprDot") }, run { ret { selection = dispatch_selection { kind = "dot" } } } },
  rule. expr_intrinsic { llisle.select_expr_typecheck { candidate = P. candidate }, when { P. candidate.kind :eq ("ExprIntrinsic") }, run { ret { selection = dispatch_selection { kind = "intrinsic" } } } },
  rule. expr_addr_of { llisle.select_expr_typecheck { candidate = P. candidate }, when { P. candidate.kind :eq ("ExprAddrOf") }, run { ret { selection = dispatch_selection { kind = "addr_of" } } } },
  rule. expr_deref { llisle.select_expr_typecheck { candidate = P. candidate }, when { P. candidate.kind :eq ("ExprDeref") }, run { ret { selection = dispatch_selection { kind = "deref" } } } },
  rule. expr_switch { llisle.select_expr_typecheck { candidate = P. candidate }, when { P. candidate.kind :eq ("ExprSwitch") }, run { ret { selection = dispatch_selection { kind = "switch" } } } },
  rule. expr_closure { llisle.select_expr_typecheck { candidate = P. candidate }, when { P. candidate.kind :eq ("ExprClosure") }, run { ret { selection = dispatch_selection { kind = "closure" } } } },
  rule. expr_ctor { llisle.select_expr_typecheck { candidate = P. candidate }, when { P. candidate.kind :eq ("ExprCtor") }, run { ret { selection = dispatch_selection { kind = "ctor" } } } },
  rule. expr_null { llisle.select_expr_typecheck { candidate = P. candidate }, when { P. candidate.kind :eq ("ExprNull") }, run { ret { selection = dispatch_selection { kind = "null" } } } },
  rule. expr_sizeof { llisle.select_expr_typecheck { candidate = P. candidate }, when { P. candidate.kind :eq ("ExprSizeOf") }, run { ret { selection = dispatch_selection { kind = "sizeof" } } } },
  rule. expr_alignof { llisle.select_expr_typecheck { candidate = P. candidate }, when { P. candidate.kind :eq ("ExprAlignOf") }, run { ret { selection = dispatch_selection { kind = "alignof" } } } },
  rule. expr_is_null { llisle.select_expr_typecheck { candidate = P. candidate }, when { P. candidate.kind :eq ("ExprIsNull") }, run { ret { selection = dispatch_selection { kind = "is_null" } } } },
  rule. expr_slot_value { llisle.select_expr_typecheck { candidate = P. candidate }, when { P. candidate.kind :eq ("ExprSlotValue") }, run { ret { selection = dispatch_selection { kind = "slot_value" } } } },
  rule. expr_use_expr_frag { llisle.select_expr_typecheck { candidate = P. candidate }, when { P. candidate.kind :eq ("ExprUseExprFrag") }, run { ret { selection = dispatch_selection { kind = "use_expr_frag" } } } },

  rule. view_from_expr { llisle.select_view_typecheck { candidate = P. candidate }, when { P. candidate.kind :eq ("ViewFromExpr") }, run { ret { selection = dispatch_selection { kind = "from_expr" } } } },
  rule. view_contiguous { llisle.select_view_typecheck { candidate = P. candidate }, when { P. candidate.kind :eq ("ViewContiguous") }, run { ret { selection = dispatch_selection { kind = "contiguous" } } } },
  rule. view_strided { llisle.select_view_typecheck { candidate = P. candidate }, when { P. candidate.kind :eq ("ViewStrided") }, run { ret { selection = dispatch_selection { kind = "strided" } } } },
  rule. view_restrided { llisle.select_view_typecheck { candidate = P. candidate }, when { P. candidate.kind :eq ("ViewRestrided") }, run { ret { selection = dispatch_selection { kind = "restrided" } } } },
  rule. view_window { llisle.select_view_typecheck { candidate = P. candidate }, when { P. candidate.kind :eq ("ViewWindow") }, run { ret { selection = dispatch_selection { kind = "window" } } } },
  rule. view_row_base { llisle.select_view_typecheck { candidate = P. candidate }, when { P. candidate.kind :eq ("ViewRowBase") }, run { ret { selection = dispatch_selection { kind = "row_base" } } } },
  rule. view_interleaved { llisle.select_view_typecheck { candidate = P. candidate }, when { P. candidate.kind :eq ("ViewInterleaved") }, run { ret { selection = dispatch_selection { kind = "interleaved" } } } },
  rule. view_interleaved_view { llisle.select_view_typecheck { candidate = P. candidate }, when { P. candidate.kind :eq ("ViewInterleavedView") }, run { ret { selection = dispatch_selection { kind = "interleaved_view" } } } },

  rule. index_base_expr { llisle.select_index_base_typecheck { candidate = P. candidate }, when { P. candidate.kind :eq ("IndexBaseExpr") }, run { ret { selection = dispatch_selection { kind = "expr" } } } },
  rule. index_base_view { llisle.select_index_base_typecheck { candidate = P. candidate }, when { P. candidate.kind :eq ("IndexBaseView") }, run { ret { selection = dispatch_selection { kind = "view" } } } },
  rule. index_base_place { llisle.select_index_base_typecheck { candidate = P. candidate }, when { P. candidate.kind :eq ("IndexBasePlace") }, run { ret { selection = dispatch_selection { kind = "place" } } } },

  rule. place_ref { llisle.select_place_typecheck { candidate = P. candidate }, when { P. candidate.kind :eq ("PlaceRef") }, run { ret { selection = dispatch_selection { kind = "ref" } } } },
  rule. place_deref { llisle.select_place_typecheck { candidate = P. candidate }, when { P. candidate.kind :eq ("PlaceDeref") }, run { ret { selection = dispatch_selection { kind = "deref" } } } },
  rule. place_dot { llisle.select_place_typecheck { candidate = P. candidate }, when { P. candidate.kind :eq ("PlaceDot") }, run { ret { selection = dispatch_selection { kind = "dot" } } } },
  rule. place_field { llisle.select_place_typecheck { candidate = P. candidate }, when { P. candidate.kind :eq ("PlaceField") }, run { ret { selection = dispatch_selection { kind = "field" } } } },
  rule. place_index { llisle.select_place_typecheck { candidate = P. candidate }, when { P. candidate.kind :eq ("PlaceIndex") }, run { ret { selection = dispatch_selection { kind = "index" } } } },
  rule. place_slot_value { llisle.select_place_typecheck { candidate = P. candidate }, when { P. candidate.kind :eq ("PlaceSlotValue") }, run { ret { selection = dispatch_selection { kind = "slot_value" } } } },

  rule. control_stmt_region { llisle.select_control_stmt_region_typecheck { candidate = P. candidate }, when { P. candidate.kind :eq ("ControlStmtRegion") }, run { ret { selection = dispatch_selection { kind = "stmt_region" } } } },
  rule. control_expr_region { llisle.select_control_expr_region_typecheck { candidate = P. candidate }, when { P. candidate.kind :eq ("ControlExprRegion") }, run { ret { selection = dispatch_selection { kind = "expr_region" } } } },

  rule. func_local { llisle.select_func_typecheck { candidate = P. candidate }, when { P. candidate.kind :eq ("FuncLocal") }, run { ret { selection = dispatch_selection { kind = "local" } } } },
  rule. func_export { llisle.select_func_typecheck { candidate = P. candidate }, when { P. candidate.kind :eq ("FuncExport") }, run { ret { selection = dispatch_selection { kind = "export" } } } },
  rule. func_local_contract { llisle.select_func_typecheck { candidate = P. candidate }, when { P. candidate.kind :eq ("FuncLocalContract") }, run { ret { selection = dispatch_selection { kind = "local_contract" } } } },
  rule. func_export_contract { llisle.select_func_typecheck { candidate = P. candidate }, when { P. candidate.kind :eq ("FuncExportContract") }, run { ret { selection = dispatch_selection { kind = "export_contract" } } } },
  rule. func_open { llisle.select_func_typecheck { candidate = P. candidate }, when { P. candidate.kind :eq ("FuncOpen") }, run { ret { selection = dispatch_selection { kind = "open" } } } },

  rule. item_func { llisle.select_item_typecheck { candidate = P. candidate }, when { P. candidate.kind :eq ("ItemFunc") }, run { ret { selection = dispatch_selection { kind = "func" } } } },
  rule. item_const { llisle.select_item_typecheck { candidate = P. candidate }, when { P. candidate.kind :eq ("ItemConst") }, run { ret { selection = dispatch_selection { kind = "const" } } } },
  rule. item_static { llisle.select_item_typecheck { candidate = P. candidate }, when { P. candidate.kind :eq ("ItemStatic") }, run { ret { selection = dispatch_selection { kind = "static" } } } },
  rule. item_extern { llisle.select_item_typecheck { candidate = P. candidate }, when { P. candidate.kind :eq ("ItemExtern") }, run { ret { selection = dispatch_selection { kind = "extern" } } } },
  rule. item_import { llisle.select_item_typecheck { candidate = P. candidate }, when { P. candidate.kind :eq ("ItemImport") }, run { ret { selection = dispatch_selection { kind = "import" } } } },
  rule. item_type { llisle.select_item_typecheck { candidate = P. candidate }, when { P. candidate.kind :eq ("ItemType") }, run { ret { selection = dispatch_selection { kind = "type" } } } },
  rule. item_use_type_decl_slot { llisle.select_item_typecheck { candidate = P. candidate }, when { P. candidate.kind :eq ("ItemUseTypeDeclSlot") }, run { ret { selection = dispatch_selection { kind = "use_type_decl_slot" } } } },
  rule. item_use_items_slot { llisle.select_item_typecheck { candidate = P. candidate }, when { P. candidate.kind :eq ("ItemUseItemsSlot") }, run { ret { selection = dispatch_selection { kind = "use_items_slot" } } } },
  rule. item_region_frag { llisle.select_item_typecheck { candidate = P. candidate }, when { P. candidate.kind :eq ("ItemRegionFrag") }, run { ret { selection = dispatch_selection { kind = "region_frag" } } } },
  rule. item_expr_frag { llisle.select_item_typecheck { candidate = P. candidate }, when { P. candidate.kind :eq ("ItemExprFrag") }, run { ret { selection = dispatch_selection { kind = "expr_frag" } } } },
  rule. item_use_module { llisle.select_item_typecheck { candidate = P. candidate }, when { P. candidate.kind :eq ("ItemUseModule") }, run { ret { selection = dispatch_selection { kind = "use_module" } } } },
  rule. item_use_module_slot { llisle.select_item_typecheck { candidate = P. candidate }, when { P. candidate.kind :eq ("ItemUseModuleSlot") }, run { ret { selection = dispatch_selection { kind = "use_module_slot" } } } },

  rule. module_module { llisle.select_module_typecheck { candidate = P. candidate }, when { P. candidate.kind :eq ("Module") }, run { ret { selection = dispatch_selection { kind = "module" } } } },
}
    end
    if setfenv then setfenv(build_rules, env) end
    local rules = build_rules()
    local engine = Llisle.compile(rules)

    local api = {}

    local function class_kind(node)
        local cls = pvm.classof(node)
        if cls and cls.kind then return cls.kind end
        local name = tostring(cls)
        return name:match("^Class%(MoonTree%.(.+)%)$") or name
    end

    function api.select_stmt(stmt)
        local result, err = engine:run("select_stmt_typecheck", { candidate = { kind = class_kind(stmt) } })
        if result == nil then return nil, err and err.message or "no tree typecheck statement dispatch" end
        return result.output.selection, nil
    end

    function api.select_expr(expr)
        local result, err = engine:run("select_expr_typecheck", { candidate = { kind = class_kind(expr) } })
        if result == nil then return nil, err and err.message or "no tree typecheck expression dispatch" end
        return result.output.selection, nil
    end

    local function select_one(relation, node, missing)
        local result, err = engine:run(relation, { candidate = { kind = class_kind(node) } })
        if result == nil then return nil, err and err.message or missing end
        return result.output.selection, nil
    end

    function api.select_view(node) return select_one("select_view_typecheck", node, "no tree typecheck view dispatch") end
    function api.select_index_base(node) return select_one("select_index_base_typecheck", node, "no tree typecheck index base dispatch") end
    function api.select_place(node) return select_one("select_place_typecheck", node, "no tree typecheck place dispatch") end
    function api.select_control_stmt_region(node) return select_one("select_control_stmt_region_typecheck", node, "no tree typecheck control statement region dispatch") end
    function api.select_control_expr_region(node) return select_one("select_control_expr_region_typecheck", node, "no tree typecheck control expression region dispatch") end
    function api.select_func(node) return select_one("select_func_typecheck", node, "no tree typecheck function dispatch") end
    function api.select_item(node) return select_one("select_item_typecheck", node, "no tree typecheck item dispatch") end
    function api.select_module(node) return select_one("select_module_typecheck", node, "no tree typecheck module dispatch") end

    api.rules = rules
    api.engine = engine

    T._moonlift_api_cache.tree_typecheck_rules = api
    return api
end

return bind_context
