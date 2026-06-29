package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

assert(package.loaded["lalin.type_to_c"] == nil)
assert(package.loaded["lalin.tree_to_c"] == nil)

local asdl = require("lalin.asdl")
local Schema = require("lalin.schema")
local T = asdl.context()
Schema(T)

local CodeType = require("lalin.code_type")(T)
assert(package.loaded["lalin.type_to_c"] == nil)
assert(package.loaded["lalin.tree_to_c"] == nil)

local Core = T.LalinCore
local Ty = T.LalinType
local Code = T.LalinCode
local C = T.LalinC
local Tree = T.LalinTree

local i32 = Ty.TScalar(Core.ScalarI32)
local u8 = Ty.TScalar(Core.ScalarU8)
local f64 = Ty.TScalar(Core.ScalarF64)

local code_i32 = CodeType.type_to_code(i32, {})
assert(asdl.classof(code_i32) == Code.CodeTyInt)
assert(code_i32.bits == 32)
assert(code_i32.signedness == Code.CodeSigned)
assert(CodeType.code_type_to_c(code_i32, {}) == C.CBackendScalar(Core.ScalarI32))
assert(CodeType.code_type_to_c(CodeType.type_to_code(f64, {}), {}) == C.CBackendScalar(Core.ScalarF64))

local ptr = CodeType.type_to_code(Ty.TPtr(u8), {})
assert(asdl.classof(ptr) == Code.CodeTyDataPtr)
assert(asdl.classof(ptr.pointee) == Code.CodeTyInt)
local c_ptr = CodeType.code_type_to_c(ptr, {})
assert(asdl.classof(c_ptr) == C.CBackendDataPtr)
assert(c_ptr.pointee == C.CBackendScalar(Core.ScalarU8))

local ctx = {}
local fn_ty = Ty.TFunc({ i32, i32 }, i32)
local code_fn_ptr = CodeType.type_to_code(fn_ty, ctx)
assert(asdl.classof(code_fn_ptr) == Code.CodeTyCodePtr)
assert(ctx.code_sigs[code_fn_ptr.sig.text] ~= nil)
local c_fn_ptr = CodeType.code_type_to_c(code_fn_ptr, ctx)
assert(asdl.classof(c_fn_ptr) == C.CBackendCodePtr)
assert(ctx.sigs[c_fn_ptr.sig.text] ~= nil)
assert(#ctx.sigs[c_fn_ptr.sig.text].params == 2)
local void_fn = CodeType.type_to_code(Ty.TFunc({}, Ty.TScalar(Core.ScalarVoid)), ctx)
assert(#ctx.code_sigs[void_fn.sig.text].results == 0)
assert(CodeType.code_type_to_c(void_fn, ctx) == C.CBackendCodePtr(C.CBackendFuncSigId(void_fn.sig.text)))
assert(ctx.sigs[void_fn.sig.text].result == C.CBackendVoid)

local closure_ty = Ty.TClosure({ i32 }, i32)
local code_closure = CodeType.type_to_code(closure_ty, ctx)
assert(asdl.classof(code_closure) == Code.CodeTyClosure)
local c_closure = CodeType.code_type_to_c(code_closure, ctx)
assert(asdl.classof(c_closure) == C.CBackendClosureDescriptor)

local c_sig = C.CFuncSigId("host_sig")
local imported_cfn = CodeType.type_to_code(Ty.TCFuncPtr(c_sig), {})
assert(asdl.classof(imported_cfn) == Code.CodeTyImportedCFuncPtr)
assert(CodeType.code_type_to_c(imported_cfn, {}) == C.CBackendImportedCodePtr(c_sig))

local imported_named = CodeType.type_to_code(Ty.TCType(C.CTypeId("host", "uint128_t")), {})
assert(CodeType.code_type_to_c(imported_named, {}) == C.CBackendNamed(C.CTypeId("host", "uint128_t")))

local named = CodeType.type_to_code(Ty.TNamed(Ty.TypeRefGlobal("m", "Pair")), {})
assert(asdl.classof(named) == Code.CodeTyNamed)
assert(CodeType.code_type_to_c(named, {}) == C.CBackendNamed(C.CTypeId("m", "Pair")))

local path_named_ctx = { module_name = "Demo" }
local path_named = CodeType.type_to_code(Ty.TNamed(Ty.TypeRefPath(Core.Path({ Core.Name("__lalin_region_call_demo_result") }))), path_named_ctx)
assert(asdl.classof(path_named) == Code.CodeTyNamed)
assert(path_named.module_name == "Demo")
assert(path_named.type_name == "__lalin_region_call_demo_result")
assert(asdl.classof(path_named.source_ty.ref) == Ty.TypeRefGlobal)
assert(path_named.source_ty.ref.module_name == "Demo")
assert(path_named.source_ty.ref.type_name == "__lalin_region_call_demo_result")
assert(CodeType.code_type_to_c(path_named, {}) == C.CBackendNamed(C.CTypeId("Demo", "__lalin_region_call_demo_result")))

local arr = CodeType.type_to_code(Ty.TArray(Ty.ArrayLenConst(4), i32), {})
assert(CodeType.code_type_to_c(arr, {}) == C.CBackendArray(C.CBackendScalar(Core.ScalarI32), 4))
local slice = CodeType.type_to_c(Ty.TSlice(i32), {})
assert(asdl.classof(slice) == C.CBackendSliceDescriptor)
local view = CodeType.type_to_c(Ty.TView(i32), {})
assert(asdl.classof(view) == C.CBackendViewDescriptor)

local target = CodeType.default_target({ pointer_bits = 32, index_bits = 32, endian = "big" })
local facts = CodeType.target_facts(target)
assert(facts.pointer_bits == 32)
assert(facts.index_bits == 32)
assert(facts.endian == C.CBackendBigEndian)

local ok_arr, err_arr = pcall(function()
    CodeType.type_to_code(Ty.TArray(Ty.ArrayLenExpr(Tree.ExprLit(Tree.ExprTyped(i32), Core.LitInt("3"))), i32), {})
end)
assert(not ok_arr and tostring(err_arr):match("dynamic array length"))

io.write("lalin code_type ok\n")
