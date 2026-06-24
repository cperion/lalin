package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local Schema = require("moonlift.schema")
local T = pvm.context()
Schema(T)

local Core = T.MoonCore
local Tr = T.MoonTree
local Ty = T.MoonType
local Bind = T.MoonBind
local Open = T.MoonOpen
local Rules = require("moonlift.tree_typecheck_rules")(T)

local i32 = Ty.TScalar(Core.ScalarI32)
local binding = Bind.Binding(Core.Id("b:x"), "x", i32, Bind.BindingClassLocalValue)
local expr = Tr.ExprLit(Tr.ExprSurface, Core.LitInt("1"))

local function assert_select(selector, node, family, kind)
    local selection, err = selector(node)
    assert(selection ~= nil, tostring(err))
    assert(selection.kind == kind, "expected " .. family .. " typecheck dispatch " .. kind .. ", got " .. tostring(selection.kind))
end

local function assert_expr(expr_node, kind)
    assert_select(Rules.select_expr, expr_node, "expr", kind)
end

local function assert_stmt(stmt, kind)
    assert_select(Rules.select_stmt, stmt, "stmt", kind)
end

assert_expr(expr, "lit")
assert_expr(Tr.ExprRef(Tr.ExprSurface, Bind.ValueRefBinding(binding)), "ref")
assert_expr(Tr.ExprBinary(Tr.ExprSurface, Core.BinAdd, expr, expr), "binary")
assert_expr(Tr.ExprCall(Tr.ExprSurface, Tr.ExprRef(Tr.ExprSurface, Bind.ValueRefBinding(binding)), {}), "call")
assert_expr(Tr.ExprNull(Tr.ExprSurface, Ty.TPtr(i32)), "null")

assert_stmt(Tr.StmtLet(Tr.StmtSurface, binding, expr), "let")
assert_stmt(Tr.StmtVar(Tr.StmtSurface, binding, expr), "var")
assert_stmt(Tr.StmtExpr(Tr.StmtSurface, expr), "expr")
assert_stmt(Tr.StmtReturnVoid(Tr.StmtSurface), "return_void")
assert_stmt(Tr.StmtTrap(Tr.StmtSurface), "trap")

assert_select(Rules.select_view, Tr.ViewFromExpr(expr, i32), "view", "from_expr")
assert_select(Rules.select_view, Tr.ViewContiguous(expr, i32, expr), "view", "contiguous")
assert_select(Rules.select_index_base, Tr.IndexBaseExpr(expr), "index_base", "expr")
assert_select(Rules.select_place, Tr.PlaceRef(Tr.PlaceSurface, Bind.ValueRefBinding(binding)), "place", "ref")
assert_select(Rules.select_place, Tr.PlaceDeref(Tr.PlaceSurface, expr), "place", "deref")
assert_select(Rules.select_control_stmt_region, Tr.ControlStmtRegion("r", Tr.EntryControlBlock(Tr.BlockLabel("entry"), {}, {}), {}), "control_stmt_region", "stmt_region")
assert_select(Rules.select_control_expr_region, Tr.ControlExprRegion("r", i32, Tr.EntryControlBlock(Tr.BlockLabel("entry"), {}, {}), {}), "control_expr_region", "expr_region")
assert_select(Rules.select_func, Tr.FuncLocal("f", {}, i32, {}), "func", "local")
assert_select(Rules.select_func, Tr.FuncOpen(Core.FuncSym("f", "f"), Core.VisibilityLocal, {}, Open.OpenSet({}, {}, {}, {}), i32, {}), "func", "open")
assert_select(Rules.select_item, Tr.ItemFunc(Tr.FuncLocal("f", {}, i32, {})), "item", "func")
assert_select(Rules.select_item, Tr.ItemUseItemsSlot(Open.ItemsSlot("items", "items")), "item", "use_items_slot")
assert_select(Rules.select_module, Tr.Module(Tr.ModuleSurface, {}), "module", "module")

io.write("moonlift tree_typecheck_rules ok\n")
