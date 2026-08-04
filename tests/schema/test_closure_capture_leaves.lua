package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local T = require("lalin.schema")
local asdl = require("lalin.asdl")
require("lalin.impl.tree_closure")
local C, Ty, B, Sem, Tr, H = T.LalinCore, T.LalinType, T.LalinBind, T.LalinSem, T.LalinTree, T.LalinHost

local expr_leaves = {
  "ExprLit", "ExprRef", "ExprDot", "ExprUnary", "ExprBinary", "ExprCompare", "ExprLogic",
  "ExprCast", "ExprMachineCast", "ExprIntrinsic", "ExprAddrOf", "ExprDeref", "ExprCall",
  "ExprLen", "ExprField", "ExprIndex", "ExprAgg", "ExprArray", "ExprIf", "ExprSelect",
  "ExprSwitch", "ExprControl", "ExprBlock", "ExprClosure", "ExprView", "ExprLoad",
  "ExprAtomicLoad", "ExprAtomicRmw", "ExprAtomicCas", "ExprCtor", "ExprNull", "ExprSizeOf",
  "ExprAlignOf", "ExprIsNull",
}
local place_leaves = { "PlaceRef", "PlaceDeref", "PlaceDot", "PlaceField", "PlaceIndex" }
local index_leaves = { "IndexBaseExpr", "IndexBasePlace", "IndexBaseView" }
local view_leaves = {
  "ViewFromExpr", "ViewContiguous", "ViewStrided", "ViewRestrided", "ViewWindow",
  "ViewRowBase", "ViewInterleaved", "ViewInterleavedView",
}
local stmt_leaves = {
  "StmtLet", "StmtVar", "StmtSet", "StmtAtomicStore", "StmtAtomicFence", "StmtExpr",
  "StmtAssert", "StmtIf", "StmtSwitch", "StmtJump", "StmtJumpCont", "StmtRegionEmit",
  "StmtRegionCall", "StmtYieldVoid", "StmtYieldValue", "StmtReturnVoid",
  "StmtReturnValue", "StmtControl", "StmtTrap",
}
local type_leaves = {
  "TScalar", "TPtr", "TArray", "TSlice", "TView", "TLease", "TOwned", "TAccess",
  "THandle", "TFunc", "TClosure", "TNamed", "TCType", "TCFuncPtr",
}

for _, name in ipairs(expr_leaves) do
  assert(type(Tr[name].closure_collect) == "function", name .. " missing closure_collect")
  assert(type(Tr[name].closure_rewrite) == "function", name .. " missing closure_rewrite")
end
for _, name in ipairs(place_leaves) do
  assert(type(Tr[name].closure_collect) == "function", name .. " missing closure_collect")
  assert(type(Tr[name].closure_rewrite) == "function", name .. " missing closure_rewrite")
end
for _, name in ipairs(index_leaves) do
  assert(type(Tr[name].closure_collect) == "function", name .. " missing closure_collect")
  assert(type(Tr[name].closure_rewrite) == "function", name .. " missing closure_rewrite")
end
for _, name in ipairs(view_leaves) do
  assert(type(Tr[name].closure_collect) == "function", name .. " missing closure_collect")
  assert(type(Tr[name].closure_rewrite) == "function", name .. " missing closure_rewrite")
end
for _, name in ipairs(stmt_leaves) do
  assert(type(Tr[name].closure_collect) == "function", name .. " missing closure_collect")
  assert(type(Tr[name].closure_rewrite) == "function", name .. " missing closure_rewrite")
end
for _, name in ipairs(type_leaves) do assert(type(Ty[name].closure_capture_layout) == "function", name .. " missing closure_capture_layout") end
for _, name in ipairs({ "FuncLocal", "FuncExport", "FuncLocalContract", "FuncExportContract", "FuncDecl" }) do
  assert(type(Tr[name].closure_convert) == "function", name .. " missing closure_convert")
end
for _, name in ipairs({ "ItemFunc", "ItemExtern", "ItemConst", "ItemStatic", "ItemImport", "ItemType", "ItemRegion", "ItemData" }) do
  assert(type(Tr[name].closure_convert_item) == "function", name .. " missing closure_convert_item")
end

local i32 = Ty.TScalar(C.ScalarI32)
local outer = B.Binding(C.Id("closure:outer:x"), "x", i32, B.BindingRoleLocalValue)
local inner = B.Binding(C.Id("closure:inner:y"), "y", i32, B.BindingRoleLocalValue)
local stack = Sem.ClosureScopeStack({
  Sem.ClosureScopeFrame({ Sem.ClosureBinding(outer) }),
  Sem.ClosureScopeFrame({}),
})
local input = Sem.ClosureCollectInput(stack, Sem.ClosureCaptureSet({}))
local result = Tr.ExprRef(Tr.ExprSurface, B.ValueRefName("x")):closure_collect(input)
assert(asdl.isa(result, Sem.ClosureCollected))
assert(#result.input.captures.candidates == 1)
assert(result.input.captures.candidates[1].binding.binding == outer)

local local_ref = Tr.ExprRef(Tr.ExprSurface, B.ValueRefName("y"))
local let = Tr.StmtLet(Tr.StmtSurface, inner, Tr.ExprLit(Tr.ExprSurface, C.LitInt("1")))
local transition = let:closure_collect(input)
assert(asdl.isa(transition, Sem.ClosureCollectTransitioned))
assert(#transition.transition.scopes.frames[2].bindings == 1)
assert(#input.scopes.frames[2].bindings == 0, "scope transition mutated its input")
local local_result = local_ref:closure_collect(transition.input)
assert(#local_result.input.captures.candidates == 0, "local binding was captured")

local candidate = result.input.captures.candidates[1]
local target32 = H.HostTargetModel(32, 32, H.HostEndianLittle)
local layout_input = Sem.ClosureCaptureLayoutInput(candidate, Sem.LayoutEnv({}), target32, 0)
local layout_result = i32:closure_capture_layout(layout_input)
assert(asdl.isa(layout_result, Sem.ClosureCaptureLaidOut))
assert(layout_result.slot.size == 4 and layout_result.slot.align == 4, "i32 capture layout")

local ptr_binding = B.Binding(C.Id("closure:ptr"), "p", Ty.TPtr(i32), B.BindingRoleLocalValue)
local ptr_candidate = Sem.ClosureCaptureCandidate(Sem.ClosureBinding(ptr_binding))
local ptr_layout = Ty.TPtr(i32):closure_capture_layout(Sem.ClosureCaptureLayoutInput(ptr_candidate, Sem.LayoutEnv({}), target32, 0))
assert(ptr_layout.slot.size == 4 and ptr_layout.slot.align == 4, "pointer capture must follow target pointer width")
local index_binding = B.Binding(C.Id("closure:index"), "n", Ty.TScalar(C.ScalarIndex), B.BindingRoleLocalValue)
local index_candidate = Sem.ClosureCaptureCandidate(Sem.ClosureBinding(index_binding))
local index_layout = Ty.TScalar(C.ScalarIndex):closure_capture_layout(Sem.ClosureCaptureLayoutInput(index_candidate, Sem.LayoutEnv({}), target32, 0))
assert(index_layout.slot.size == 4 and index_layout.slot.align == 4, "index capture must follow target index width")

local named_ty = Ty.TNamed(Ty.TypeRefGlobal("capture", "Pair"))
local named_layout = Sem.LayoutNamed("capture", "Pair", {}, 12, 4)
local named_binding = B.Binding(C.Id("closure:named"), "pair", named_ty, B.BindingRoleLocalValue)
local named_candidate = Sem.ClosureCaptureCandidate(Sem.ClosureBinding(named_binding))
local named_result = named_ty:closure_capture_layout(Sem.ClosureCaptureLayoutInput(named_candidate, Sem.LayoutEnv({ named_layout }), target32, 0))
assert(asdl.isa(named_result, Sem.ClosureCaptureLaidOut) and named_result.slot.size == 12, "named capture layout must resolve through LayoutEnv")
local missing_named = named_ty:closure_capture_layout(Sem.ClosureCaptureLayoutInput(named_candidate, Sem.LayoutEnv({}), target32, 0))
assert(asdl.isa(missing_named, Sem.ClosureCaptureLayoutUnsupported), "missing named layout must be typed unsupported")

local outer_y = B.Binding(C.Id("closure:outer:y"), "y", i32, B.BindingRoleLocalValue)
local branch_input = Sem.ClosureCollectInput(Sem.ClosureScopeStack({ Sem.ClosureScopeFrame({ Sem.ClosureBinding(outer_y) }), Sem.ClosureScopeFrame({}) }), Sem.ClosureCaptureSet({}))
local branch_local = B.Binding(C.Id("closure:branch:y"), "y", i32, B.BindingRoleLocalValue)
local switch = Tr.StmtSwitch(Tr.StmtSurface, Tr.ExprLit(Tr.ExprSurface, C.LitInt("0")), {
  Tr.SwitchStmtArm(Tr.SwitchKeyInt("0"), { Tr.StmtLet(Tr.StmtSurface, branch_local, Tr.ExprLit(Tr.ExprSurface, C.LitInt("1"))) }),
  Tr.SwitchStmtArm(Tr.SwitchKeyInt("1"), { Tr.StmtExpr(Tr.StmtSurface, Tr.ExprRef(Tr.ExprSurface, B.ValueRefName("y"))) }),
}, {}, {})
local branch_result = switch:closure_collect(branch_input)
assert(#branch_result.input.scopes.frames[2].bindings == 0, "switch arm binding leaked into sibling scope")
assert(#branch_result.input.captures.candidates == 1 and branch_result.input.captures.candidates[1].binding.binding == outer_y, "sibling arm did not capture lexical outer binding")

local outer_z = B.Binding(C.Id("closure:outer:z"), "z", i32, B.BindingRoleLocalValue)
local default_local = B.Binding(C.Id("closure:default:z"), "z", i32, B.BindingRoleLocalValue)
local default_input = Sem.ClosureCollectInput(Sem.ClosureScopeStack({ Sem.ClosureScopeFrame({ Sem.ClosureBinding(outer_z) }), Sem.ClosureScopeFrame({}) }), Sem.ClosureCaptureSet({}))
local default_switch = Tr.ExprSwitch(Tr.ExprSurface, Tr.ExprLit(Tr.ExprSurface, C.LitInt("0")), {}, {},
  { Tr.StmtLet(Tr.StmtSurface, default_local, Tr.ExprLit(Tr.ExprSurface, C.LitInt("2"))) },
  Tr.ExprRef(Tr.ExprSurface, B.ValueRefName("z")))
local default_result = default_switch:closure_collect(default_input)
assert(#default_result.input.captures.candidates == 0, "default result did not share the default body's lexical scope")

local outer_payload = B.Binding(C.Id("closure:outer:payload"), "payload", i32, B.BindingRoleLocalValue)
local variant_input = Sem.ClosureCollectInput(Sem.ClosureScopeStack({ Sem.ClosureScopeFrame({ Sem.ClosureBinding(outer_payload) }), Sem.ClosureScopeFrame({}) }), Sem.ClosureCaptureSet({}))
local variant_switch = Tr.ExprSwitch(Tr.ExprSurface, Tr.ExprLit(Tr.ExprSurface, C.LitInt("0")), {}, {
  Tr.SwitchVariantExprArm("Some", { Tr.VariantBind("payload", i32) }, {}, Tr.ExprRef(Tr.ExprSurface, B.ValueRefName("payload"))),
}, {}, Tr.ExprLit(Tr.ExprSurface, C.LitInt("0")))
local variant_result = variant_switch:closure_collect(variant_input)
assert(#variant_result.input.captures.candidates == 0, "variant-arm bind was not installed in its lexical scope")
local ok = pcall(function() Sem.ClosureCollectInput({ frames = {} }, Sem.ClosureCaptureSet({})) end)
assert(not ok, "ClosureCollectInput accepted a loose scope table")

print("test_closure_capture_leaves: ok")
