package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local asdl = require("lalin.asdl")
require("lalin.schema_v2")
require("lalin.impl.lower_emit_c")
local Core = require("lalin.schema_v2.core")
local Code = require("lalin.schema_v2.code")
local Sem = require("lalin.schema_v2.sem")
local Type = require("lalin.schema_v2.type")
local C = require("lalin.schema_v2.c")
local Lower = require("lalin.schema_v2.lower")

local i32 = Code.CodeTyInt(32, Code.CodeSigned)
local function entry(value, ty)
  return Lower.LowerCValueTypeEntry(value, ty, C.CBackendLocal(C.CBackendLocalId(value.text), C.CBackendName(value.text), ty:code_to_c_backend_type()))
end
local v1, v2, v3 = Code.CodeValueId("v1"), Code.CodeValueId("v2"), Code.CodeValueId("v3")
local input = Lower.LowerCInstructionInput(Lower.LowerCSignatureProjection({}), Lower.LowerCExternProjection({}), Lower.LowerCValueTypeProjection({ entry(v1, i32), entry(v2, i32), entry(v3, i32) }))
local origin = Code.CodeOriginSource("aggregate-test")

local struct_ty = Code.CodeTyNamed("mymod", "MyStruct", Type.TScalar(Core.ScalarI32))
local fields = {
  Code.CodeFieldValue(Sem.FieldByName("x", Type.TScalar(Core.ScalarI32)), v1),
  Code.CodeFieldValue(Sem.FieldByName("y", Type.TScalar(Core.ScalarI32)), v2),
}
local aggregate = Code.CodeInst(Code.CodeInstId("aggregate"), Code.CodeInstAggregate(Code.CodeValueId("agg"), struct_ty, fields), origin):lower_to_c_backend(input)
assert(asdl.classof(aggregate) == Lower.LowerCInstEmission)
assert(asdl.classof(aggregate.stmts[1]) == C.CBackendAggregateInit)
assert(#aggregate.stmts[1].fields == 2 and aggregate.stmts[1].fields[1].field.text == "x")
assert(#aggregate.definitions == 1 and aggregate.definitions[1].code_ty == struct_ty)

local array_ty = Code.CodeTyArray(i32, 3)
local elems = { Code.CodeArrayValue(0, v1), Code.CodeArrayValue(1, v2), Code.CodeArrayValue(2, v3) }
local array = Code.CodeInst(Code.CodeInstId("array"), Code.CodeInstArray(Code.CodeValueId("arr"), array_ty, elems), origin):lower_to_c_backend(input)
assert(asdl.classof(array) == Lower.LowerCInstEmission)
assert(asdl.classof(array.stmts[1]) == C.CBackendArrayInit)
assert(#array.stmts[1].elems == 3 and array.stmts[1].elems[3].index == 2)

local empty = Code.CodeInst(Code.CodeInstId("empty"), Code.CodeInstAggregate(Code.CodeValueId("empty_agg"), struct_ty, {}), origin):lower_to_c_backend(input)
assert(asdl.classof(empty.stmts[1]) == C.CBackendAggregateInit and #empty.stmts[1].fields == 0)
io.write("schema_v2 typed aggregate C lowering ok\n")
