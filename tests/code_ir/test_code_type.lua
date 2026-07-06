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

local dummy_sig_state = T.LalinTreeLower.TreeLowerModuleSigState("test", {}, {})
local dummy_spine = T.LalinLower.LowerBackSpine(
    T.LalinCode.CodeModule(T.LalinCode.CodeModuleId("_test"), {}, {}, {}, {}, {}, {}, T.LalinCode.CodeOriginUnknown),
    T.LalinGraph.CodeGraph(T.LalinCode.CodeModuleId("_test"), {}),
    T.LalinC.CBackendTarget(T.LalinC.CBackendC99, T.LalinC.CBackendHostedNative, 64, 64, T.LalinC.CBackendLittleEndian, true)
)
local dummy_machine = T.LalinCEmit.CEmitMachine(dummy_spine, {}, {}, {}, {})

local code_i32 = select(1, CodeType.type_to_code(dummy_sig_state, i32))
assert(asdl.classof(code_i32) == Code.CodeTyInt)
assert(code_i32.bits == 32)
assert(code_i32.signedness == Code.CodeSigned)
assert(select(1, CodeType.code_type_to_c(dummy_machine, code_i32)) == C.CBackendScalar(Core.ScalarI32))
local f64_code = select(1, CodeType.type_to_code(dummy_sig_state, f64))
assert(select(1, CodeType.code_type_to_c(dummy_machine, f64_code)) == C.CBackendScalar(Core.ScalarF64))

local ss = dummy_sig_state
local ptr, ss = CodeType.type_to_code(ss, Ty.TPtr(u8))
assert(asdl.classof(ptr) == Code.CodeTyDataPtr)
assert(asdl.classof(ptr.pointee) == Code.CodeTyInt)
local c_ptr = select(1, CodeType.code_type_to_c(dummy_machine, ptr))
assert(asdl.classof(c_ptr) == C.CBackendDataPtr)
assert(c_ptr.pointee == C.CBackendScalar(Core.ScalarU8))

local fn_ty = Ty.TFunc({ i32, i32 }, i32)
local code_fn_ptr, ss = CodeType.type_to_code(ss, fn_ty)
assert(asdl.classof(code_fn_ptr) == Code.CodeTyCodePtr)
assert(ss.code_sigs[1].sig.id.text == code_fn_ptr.sig.text)
local c_fn_ptr = select(1, CodeType.code_type_to_c(dummy_machine, code_fn_ptr))
assert(asdl.classof(c_fn_ptr) == C.CBackendCodePtr)
local void_fn, ss = CodeType.type_to_code(ss, Ty.TFunc({}, Ty.TScalar(Core.ScalarVoid)))
local void_code = select(1, CodeType.code_type_to_c(dummy_machine, void_fn))
assert(void_code == C.CBackendCodePtr(C.CBackendFuncSigId(void_fn.sig.text)))

local closure_ty = Ty.TClosure({ i32 }, i32)
local code_closure, ss = CodeType.type_to_code(ss, closure_ty)
assert(asdl.classof(code_closure) == Code.CodeTyClosure)

local c_sig = C.CFuncSigId("host_sig")
local imported_cfn, ss = CodeType.type_to_code(ss, Ty.TCFuncPtr(c_sig))
assert(asdl.classof(imported_cfn) == Code.CodeTyImportedCFuncPtr)
assert(select(1, CodeType.code_type_to_c(dummy_machine, imported_cfn)) == C.CBackendImportedCodePtr(c_sig))

local imported_named, ss = CodeType.type_to_code(ss, Ty.TCType(C.CTypeId("host", "uint128_t")))
assert(select(1, CodeType.code_type_to_c(dummy_machine, imported_named)) == C.CBackendNamed(C.CTypeId("host", "uint128_t")))

local named, ss = CodeType.type_to_code(ss, Ty.TNamed(Ty.TypeRefGlobal("m", "Pair")))
assert(asdl.classof(named) == Code.CodeTyNamed)
assert(select(1, CodeType.code_type_to_c(dummy_machine, named)) == C.CBackendNamed(C.CTypeId("m", "Pair")))

local path_sig_state = T.LalinTreeLower.TreeLowerModuleSigState("Demo", {}, {})
local path_named, _ = CodeType.type_to_code(path_sig_state, Ty.TNamed(Ty.TypeRefPath(Core.Path({ Core.Name("__lalin_region_call_demo_result") }))))
assert(asdl.classof(path_named) == Code.CodeTyNamed)
assert(path_named.module_name == "Demo")
assert(path_named.type_name == "__lalin_region_call_demo_result")
assert(asdl.classof(path_named.source_ty.ref) == Ty.TypeRefGlobal)
assert(path_named.source_ty.ref.module_name == "Demo")
assert(path_named.source_ty.ref.type_name == "__lalin_region_call_demo_result")
assert(select(1, CodeType.code_type_to_c(dummy_machine, path_named)) == C.CBackendNamed(C.CTypeId("Demo", "__lalin_region_call_demo_result")))

local arr, _ = CodeType.type_to_code(dummy_sig_state, Ty.TArray(Ty.ArrayLenConst(4), i32))
assert(select(1, CodeType.code_type_to_c(dummy_machine, arr)) == C.CBackendArray(C.CBackendScalar(Core.ScalarI32), 4))
local slice = select(1, CodeType.type_to_c(dummy_sig_state, Ty.TSlice(i32)))
assert(asdl.classof(slice) == C.CBackendSliceDescriptor)
local view = select(1, CodeType.type_to_c(dummy_sig_state, Ty.TView(i32)))
assert(asdl.classof(view) == C.CBackendViewDescriptor)

local target = CodeType.default_target({ pointer_bits = 32, index_bits = 32, endian = "big" })
local facts = CodeType.target_facts(target)
assert(facts.pointer_bits == 32)
assert(facts.index_bits == 32)
assert(facts.endian == C.CBackendBigEndian)

local ok_arr, err_arr = pcall(function()
    CodeType.type_to_code(dummy_sig_state, Ty.TArray(Ty.ArrayLenExpr(Tree.ExprLit(Tree.ExprTyped(i32), Core.LitInt("3"))), i32))
end)
assert(not ok_arr and tostring(err_arr):match("dynamic array length"))

io.write("lalin code_type ok\n")
