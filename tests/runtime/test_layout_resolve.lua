package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local asdl = require("lalin.asdl")
local A = require("lalin.schema_projection")
local Layout = require("lalin.layout_resolve")

local T = asdl.context()
A(T)
local L = Layout(T)
local C = T.LalinCore
local Ty = T.LalinType
local B = T.LalinBind
local Sem = T.LalinSem
local Tr = T.LalinTree
local H = T.LalinHost

local i32 = Ty.TScalar(C.ScalarI32)
local i32_rep = H.HostRepScalar(C.ScalarI32)
local pair = Ty.TNamed(Ty.TypeRefGlobal("Demo", "Pair"))
local named_layout = Sem.LayoutNamed("Demo", "Pair", {
    Sem.FieldLayout("left", 0, i32),
    Sem.FieldLayout("right", 4, i32),
}, 8, 4)
local local_layout = Sem.LayoutLocal(C.TypeSym("local-pair", "LocalPair"), {
    Sem.FieldLayout("right", 4, i32),
}, 8, 4)
local env = Sem.LayoutEnv({ named_layout })

assert(pair:sem_layout(env) == Sem.TypeLayoutFound(named_layout))
assert(Ty.TNamed(Ty.TypeRefGlobal("Demo", "Missing")):sem_layout(env) == Sem.TypeLayoutMissing)
assert(Ty.TNamed(Ty.TypeRefLocal(local_layout.sym)):sem_layout(Sem.LayoutEnv({ local_layout })) ==
    Sem.TypeLayoutFound(local_layout))

-- Field lookup returns a typed result owned by both concrete TypeLayout leaves.
assert(named_layout:sem_layout_field("right") == Sem.FieldLayoutFound(named_layout.fields[2]))
assert(local_layout:sem_layout_field("right") == Sem.FieldLayoutFound(local_layout.fields[1]))
assert(named_layout:sem_layout_field("missing") == Sem.FieldLayoutMissing)

local right_name = Sem.FieldByName("right", i32)
assert(L.field(right_name, pair, env) == Sem.FieldByOffset("right", 4, i32, i32_rep))
assert(L.field(Sem.FieldByOffset("left", 0, i32, i32_rep), pair, env) == Sem.FieldByOffset("left", 0, i32, i32_rep))
assert(L.field(Sem.FieldByName("missing", i32), pair, env) == Sem.FieldByName("missing", i32))

local binding = B.Binding(C.Id("p"), "p", pair, B.BindingRoleLocalValue)
local base_place = Tr.PlaceRef(Tr.PlaceTyped(pair), B.ValueRefBinding(binding))
local field_place = Tr.PlaceField(Tr.PlaceTyped(i32), base_place, right_name)
assert(L.place(field_place, env) == Tr.PlaceField(Tr.PlaceTyped(i32), base_place, Sem.FieldByOffset("right", 4, i32, i32_rep)))

local base_expr = Tr.ExprRef(Tr.ExprTyped(pair), B.ValueRefBinding(binding))
local field_expr = Tr.ExprField(Tr.ExprTyped(i32), base_expr, right_name)
assert(L.expr(field_expr, env) == Tr.ExprField(Tr.ExprTyped(i32), base_expr, Sem.FieldByOffset("right", 4, i32, i32_rep)))

-- IndexBase projection leaves preserve their complete values and own delegation.
local resolved_field = Sem.FieldByOffset("right", 4, i32, i32_rep)
local dot_expr = Tr.ExprDot(Tr.ExprTyped(i32), base_expr, "right")
local projected_expr = Tr.ExprField(Tr.ExprTyped(i32), base_expr, resolved_field)
local resolved_expr_base = Tr.IndexBaseExpr(dot_expr):sem_layout_resolve(env)
assert(resolved_expr_base == Tr.IndexBaseExpr(projected_expr))

local dot_place = Tr.PlaceDot(Tr.PlaceTyped(i32), base_place, "right")
local projected_place = Tr.PlaceField(Tr.PlaceTyped(i32), base_place, resolved_field)
local resolved_place_base = Tr.IndexBasePlace(dot_place, i32):sem_layout_resolve(env)
assert(resolved_place_base == Tr.IndexBasePlace(projected_place, i32))
assert(resolved_place_base.elem == i32)

local projected_view = Tr.ViewFromExpr(projected_expr, i32)
local resolved_view_base = Tr.IndexBaseView(Tr.ViewFromExpr(dot_expr, i32)):sem_layout_resolve(env)
assert(resolved_view_base == Tr.IndexBaseView(projected_view))

local index_ty = Ty.TScalar(C.ScalarIndex)
local index = Tr.ExprLit(Tr.ExprTyped(index_ty), C.LitInt("0"))
local indexed_place = Tr.PlaceIndex(Tr.PlaceTyped(i32), Tr.IndexBasePlace(dot_place, i32), index)
assert(L.place(indexed_place, env) ==
    Tr.PlaceIndex(Tr.PlaceTyped(i32), Tr.IndexBasePlace(projected_place, i32), index))
local indexed_expr = Tr.ExprIndex(Tr.ExprTyped(i32), Tr.IndexBaseExpr(dot_expr), index)
assert(L.expr(indexed_expr, env) ==
    Tr.ExprIndex(Tr.ExprTyped(i32), Tr.IndexBaseExpr(projected_expr), index))

local module = Tr.Module(Tr.ModuleTyped("Demo"), {
    Tr.ItemFunc(Tr.FuncLocal("get_right", {}, i32, {
        Tr.StmtReturnValue(Tr.StmtSurface, field_expr),
    })),
})
local resolved = L.module(module, env)
assert(resolved.items[1].func.body[1].value.field == Sem.FieldByOffset("right", 4, i32, i32_rep))

print("lalin layout_resolve ok")
