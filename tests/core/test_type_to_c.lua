package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

assert(package.loaded["lalin.type_to_c"] == nil)

local asdl = require("lalin.asdl")
local T = require("lalin.schema")
require("lalin.impl.lower_emit_c.code_to_c")

local Core = T.LalinCore
local Ty = T.LalinType
local C = T.LalinC
local Code = T.LalinCode
local Tree = T.LalinTree
local CodeType = require("lalin.impl.code_type")(T)

local function assert_class(value, class, message)
    assert(asdl.classof(value) == class, message or ("expected " .. tostring(class) .. ", got " .. tostring(asdl.classof(value))))
end

local i32 = Ty.TScalar(Core.ScalarI32)
local u8 = Ty.TScalar(Core.ScalarU8)
local sig_state = T.LalinTreeCode.TreeCodeModuleSigState("test", {}, {})

-- Scalar and nullary CodeType leaves project directly when no C-emission
-- registration is required.
local scalar_cases = {
    { Code.CodeTyVoid, C.CBackendVoid },
    { Code.CodeTyBool8, C.CBackendBool8 },
    { Code.CodeTyIndex, C.CBackendIndex },
    { Code.CodeTyInt(8, Code.CodeSigned), C.CBackendScalar(Core.ScalarI8) },
    { Code.CodeTyInt(16, Code.CodeSigned), C.CBackendScalar(Core.ScalarI16) },
    { Code.CodeTyInt(32, Code.CodeSigned), C.CBackendScalar(Core.ScalarI32) },
    { Code.CodeTyInt(64, Code.CodeSigned), C.CBackendScalar(Core.ScalarI64) },
    { Code.CodeTyInt(8, Code.CodeUnsigned), C.CBackendScalar(Core.ScalarU8) },
    { Code.CodeTyInt(16, Code.CodeUnsigned), C.CBackendScalar(Core.ScalarU16) },
    { Code.CodeTyInt(32, Code.CodeUnsigned), C.CBackendScalar(Core.ScalarU32) },
    { Code.CodeTyInt(64, Code.CodeUnsigned), C.CBackendScalar(Core.ScalarU64) },
    { Code.CodeTyFloat(32), C.CBackendScalar(Core.ScalarF32) },
    { Code.CodeTyFloat(64), C.CBackendScalar(Core.ScalarF64) },
    { Code.CodeTyByteSpan, C.CBackendByteSpanDescriptor },
}
for i = 1, #scalar_cases do
    assert(scalar_cases[i][1]:code_to_c_backend_type() == scalar_cases[i][2])
end

local code_i32 = Code.CodeTyInt(32, Code.CodeSigned)
local code_u8 = Code.CodeTyInt(8, Code.CodeUnsigned)
local opaque_ptr = Code.CodeTyDataPtr(nil):code_to_c_backend_type()
assert_class(opaque_ptr, C.CBackendDataPtr)
assert(opaque_ptr.pointee == nil)
local data_ptr = Code.CodeTyDataPtr(code_u8):code_to_c_backend_type()
assert(data_ptr == C.CBackendDataPtr(C.CBackendScalar(Core.ScalarU8)))

local array = Code.CodeTyArray(code_i32, 4):code_to_c_backend_type()
assert(array == C.CBackendArray(C.CBackendScalar(Core.ScalarI32), 4))
assert(Code.CodeTySlice(code_i32):code_to_c_backend_type() == C.CBackendSliceDescriptor(C.CBackendScalar(Core.ScalarI32)))
assert(Code.CodeTyView(code_i32):code_to_c_backend_type() == C.CBackendViewDescriptor(C.CBackendScalar(Core.ScalarI32)))

local named_source = Ty.TNamed(Ty.TypeRefGlobal("m", "Pair"))
local named = Code.CodeTyNamed("m", "Pair", named_source):code_to_c_backend_type()
assert(named == C.CBackendNamed(C.CTypeId("m", "Pair")))
local imported_id = C.CTypeId("host", "uint128_t")
assert(Code.CodeTyImportedC(imported_id):code_to_c_backend_type() == C.CBackendNamed(imported_id))

local handle_source = Ty.THandle(
    Ty.TypeRefGlobal("m", "Handle"),
    Ty.HandleReprScalar(Core.ScalarU32)
)
local handle = Code.CodeTyHandle(Code.CodeTyInt(32, Code.CodeUnsigned), handle_source)
assert(handle:code_to_c_backend_type() == C.CBackendScalar(Core.ScalarU32))
local lease_source = Ty.TLease(i32, Ty.LeaseOriginParam("value"))
local lease = Code.CodeTyLease(code_i32, lease_source)
assert(lease:code_to_c_backend_type() == C.CBackendScalar(Core.ScalarI32))
local vector = Code.CodeTyVector(code_i32, 8):code_to_c_backend_type()
assert(vector == C.CBackendVector(C.CBackendScalar(Core.ScalarI32), 8))

local imported_sig = C.CFuncSigId("host_sig")
local imported_ptr = Code.CodeTyImportedCFuncPtr(imported_sig):code_to_c_backend_type()
assert(imported_ptr == C.CBackendImportedCodePtr(imported_sig))

-- Callable source types first project a typed CodeSig into the lowering state.
local fn_ty = Ty.TFunc({ i32, i32 }, i32)
local fn_code
fn_code, sig_state = CodeType.type_to_code(sig_state, fn_ty)
assert_class(fn_code, Code.CodeTyCodePtr)
local closure_ty = Ty.TClosure({ i32 }, i32)
local closure_code
closure_code, sig_state = CodeType.type_to_code(sig_state, closure_ty)
assert_class(closure_code, Code.CodeTyClosure)
assert(#sig_state.code_sig_order == 2)

local code_module = Code.CodeModule(
    Code.CodeModuleId("_test"),
    sig_state.code_sig_order,
    {},
    {},
    {},
    {},
    {},
    Code.CodeOriginUnknown
)
local target = C.CBackendTarget(
    C.CBackendC99,
    C.CBackendHostedNative,
    64,
    64,
    C.CBackendLittleEndian,
    true
)
local spine = T.LalinLower.LowerBackSpine(
    code_module,
    T.LalinGraph.CodeGraph(code_module.id, {}),
    target
)
local machine = T.LalinCEmit.CEmitMachine(spine, {}, {}, {}, {})

-- The canonical stateful contract is (machine, ty); it returns the projected
-- C type and a new typed machine containing any callable signature.
local code_ptr, machine_with_fn = CodeType.code_type_to_c(machine, fn_code)
assert(code_ptr == C.CBackendCodePtr(C.CBackendFuncSigId(fn_code.sig.text)))
assert_class(machine_with_fn, T.LalinCEmit.CEmitMachine)
assert(#machine_with_fn.c_sig_order == 1)
local fn_sig = machine_with_fn.c_sig_order[1]
assert(fn_sig.id == code_ptr.sig)
assert(#fn_sig.params == 2)
assert(fn_sig.params[1] == C.CBackendScalar(Core.ScalarI32))
assert(fn_sig.params[2] == C.CBackendScalar(Core.ScalarI32))
assert(fn_sig.result == C.CBackendScalar(Core.ScalarI32))

local code_ptr_again, same_machine = CodeType.code_type_to_c(machine_with_fn, fn_code)
assert(code_ptr_again == code_ptr)
assert(same_machine == machine_with_fn, "callable signature projection must deduplicate")

local closure, machine_with_closure = CodeType.code_type_to_c(machine_with_fn, closure_code)
assert_class(closure, C.CBackendClosureDescriptor)
assert(closure.sig == C.CBackendFuncSigId("closure_" .. closure_code.sig.text))
assert(closure.ctx == C.CBackendDataPtr(nil))
assert(#machine_with_closure.c_sig_order == 2)
local closure_sig = machine_with_closure.c_sig_order[2]
assert(closure_sig.id == closure.sig)
assert(#closure_sig.params == 2)
assert(closure_sig.params[1] == C.CBackendDataPtr(nil))
assert(closure_sig.params[2] == C.CBackendScalar(Core.ScalarI32))
assert(closure_sig.result == C.CBackendScalar(Core.ScalarI32))

-- Source Type projection covers the same canonical shapes and rejects dynamic
-- array lengths before CodeType/C backend lowering.
local projected_ptr = select(1, CodeType.type_to_code(sig_state, Ty.TPtr(u8)))
assert(projected_ptr:code_to_c_backend_type() == C.CBackendDataPtr(C.CBackendScalar(Core.ScalarU8)))
local projected_array = select(1, CodeType.type_to_code(sig_state, Ty.TArray(Ty.ArrayLenConst(4), i32)))
assert(projected_array:code_to_c_backend_type() == C.CBackendArray(C.CBackendScalar(Core.ScalarI32), 4))
assert_class(select(1, CodeType.type_to_code(sig_state, Ty.TSlice(i32))), Code.CodeTySlice)
assert_class(select(1, CodeType.type_to_code(sig_state, Ty.TView(i32))), Code.CodeTyView)
assert_class(select(1, CodeType.type_to_code(sig_state, handle_source)), Code.CodeTyHandle)
assert_class(select(1, CodeType.type_to_code(sig_state, lease_source)), Code.CodeTyLease)
assert_class(select(1, CodeType.type_to_code(sig_state, named_source)), Code.CodeTyNamed)
assert_class(select(1, CodeType.type_to_code(sig_state, Ty.TCType(imported_id))), Code.CodeTyImportedC)
assert_class(select(1, CodeType.type_to_code(sig_state, Ty.TCFuncPtr(imported_sig))), Code.CodeTyImportedCFuncPtr)

local dynamic_array = Ty.TArray(
    Ty.ArrayLenExpr(Tree.ExprLit(Tree.ExprTyped(i32), Core.LitInt("3"))),
    i32
)
local ok_array, err_array = pcall(function()
    CodeType.type_to_code(sig_state, dynamic_array)
end)
assert(not ok_array)
assert(tostring(err_array):match("typechecking must reject ArrayLenExpr"))

assert(package.loaded["lalin.type_to_c"] == nil)
io.write("lalin canonical CodeType C projection ok\n")
