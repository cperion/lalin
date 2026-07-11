package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local asdl = require("lalin.asdl")
local A2 = require("lalin.schema_projection")
local ClosureConvert = require("lalin.closure_convert")
local T = asdl.context()
A2(T)
local C, Ty, B, Tr = T.LalinCore, T.LalinType, T.LalinBind, T.LalinTree
local i32 = Ty.TScalar(C.ScalarI32)

local function name_ref(name)
    return Tr.ExprRef(Tr.ExprSurface, B.ValueRefName(name))
end

local closure = Tr.ExprClosure(Tr.ExprSurface, { Ty.Param("x", i32) }, i32, {
    Tr.StmtReturnValue(Tr.StmtSurface,
        Tr.ExprBinary(Tr.ExprSurface, C.BinAdd, name_ref("x"), Tr.ExprLit(Tr.ExprSurface, C.LitInt("1"))))
})

local y_binding = B.Binding(C.Id("local:y"), "y", i32, B.BindingRoleLocalValue)
local capture_closure = Tr.ExprClosure(Tr.ExprSurface, { Ty.Param("x", i32) }, i32, {
    Tr.StmtReturnValue(Tr.StmtSurface, Tr.ExprBinary(Tr.ExprSurface, C.BinAdd, name_ref("x"), name_ref("y")))
})

-- Since CallTarget was removed from the schema, closure call detection
-- is now handled during typechecking rather than via explicit CallTarget markers.
-- This test verifies that closure conversion correctly hoists closures
-- into helper functions when they appear as callee expressions.
local main = Tr.FuncExport("closure_direct", {}, i32, {
    Tr.StmtReturnValue(Tr.StmtSurface,
        Tr.ExprCall(Tr.ExprSurface, closure, { Tr.ExprLit(Tr.ExprSurface, C.LitInt("41")) }))
})

local capture_main = Tr.FuncExport("closure_capture", {}, i32, {
    Tr.StmtLet(Tr.StmtSurface, y_binding, Tr.ExprLit(Tr.ExprSurface, C.LitInt("1"))),
    Tr.StmtReturnValue(Tr.StmtSurface,
        Tr.ExprCall(Tr.ExprSurface, capture_closure, { Tr.ExprLit(Tr.ExprSurface, C.LitInt("41")) }))
})

local module = Tr.Module(Tr.ModuleSurface, { Tr.ItemFunc(main), Tr.ItemFunc(capture_main) })
local closure_api = ClosureConvert(T)

-- Closure conversion installs the canonical backend-neutral module-name contract.
assert(Tr.ModuleSurface:tree_module_name() == "", "surface modules should have an empty module name")
assert(Tr.ModuleTyped("TypedClosure"):tree_module_name() == "TypedClosure", "typed modules should preserve their module name")

local converted = closure_api.module(module)
assert(#converted.items == 4, "closure conversion should hoist two helpers")

-- Helper names include the header name, owning function, and deterministic ordinal.
local helper_names = {}
for i = 1, #converted.items do
    local item = converted.items[i]
    if asdl.classof(item) == Tr.ItemFunc and asdl.classof(item.func) == Tr.FuncLocal then
        helper_names[#helper_names + 1] = item.func.name
    end
end
assert(helper_names[1] == "__lalin_closure__closure_direct_1", "unexpected surface helper name: " .. tostring(helper_names[1]))
assert(helper_names[2] == "__lalin_closure__closure_capture_2", "unexpected surface helper name: " .. tostring(helper_names[2]))

local typed_module = Tr.Module(Tr.ModuleTyped("TypedClosure"), module.items)
local typed_converted = closure_api.module(typed_module)
local typed_helper_names = {}
for i = 1, #typed_converted.items do
    local item = typed_converted.items[i]
    if asdl.classof(item) == Tr.ItemFunc and asdl.classof(item.func) == Tr.FuncLocal then
        typed_helper_names[#typed_helper_names + 1] = item.func.name
    end
end
assert(typed_helper_names[1] == "__lalin_closure_TypedClosure_closure_direct_1", "unexpected typed helper name: " .. tostring(typed_helper_names[1]))
assert(typed_helper_names[2] == "__lalin_closure_TypedClosure_closure_capture_2", "unexpected typed helper name: " .. tostring(typed_helper_names[2]))

-- Verify main function has descriptor references instead of closure expressions
for i = 1, #converted.items do
    local item = converted.items[i]
    local cls = asdl.classof(item)
    if cls == Tr.ItemFunc then
        local func_cls = asdl.classof(item.func)
        if func_cls == Tr.FuncExport and item.func.name == "closure_direct" then
            local body = item.func.body
            assert(#body > 0, "closure_direct should have body")
            local last = body[#body]
            local last_cls = asdl.classof(last)
            assert(last_cls == Tr.StmtReturnValue, "last stmt should be return")
            local ret_expr = last.value
            local expr_cls = asdl.classof(ret_expr)
            assert(expr_cls == Tr.ExprCall, "should have ExprCall")
            -- The callee should be a descriptor (ExprAgg), not the original closure
            assert(asdl.classof(ret_expr.callee) == Tr.ExprAgg, "callee should be converted to descriptor")
        end
    end
end

print("lalin closure conversion ok")
