package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local asdl = require("lalin.asdl")
require("lalin.schema")
require("lalin.impl.lower_emit_c")
local Code = require("lalin.schema.code")
local Core = require("lalin.schema.core")
local C = require("lalin.schema.c")
local Graph = require("lalin.schema.graph")
local Lower = require("lalin.schema.lower")

local origin = Code.CodeOriginSource("lower-result-test")
local i32 = Code.CodeTyInt(32, Code.CodeSigned)
local sig_id = Code.CodeSigId("sig")
local sig = Code.CodeSig(sig_id, {}, { i32 })
local value = Code.CodeValueId("v")
local inst = Code.CodeInst(Code.CodeInstId("const"), Code.CodeInstConst(value, Code.CodeConstLiteral(i32, Core.LitInt("9"))), origin)
local block = Code.CodeBlock(Code.CodeBlockId("entry"), "entry", {}, { inst }, Code.CodeTerm(Code.CodeTermId("ret"), Code.CodeTermReturn({ value }), origin), origin)
local func = Code.CodeFunc(Code.CodeFuncId("nine"), "nine", Code.CodeLinkageExport, sig_id, {}, {}, block.id, { block }, origin)
local module = Code.CodeModule(Code.CodeModuleId("lower_results"), { sig }, {}, {}, {}, {}, { func }, origin)

local signatures = module:lower_c_signature_projection()
assert(asdl.classof(signatures) == Lower.LowerCSignatureProjection)
local function_result = func:lower_c_function(Lower.LowerCFunctionInput(signatures, module:lower_c_func_symbol_projection(), module:lower_c_extern_symbol_projection()))
assert(asdl.classof(function_result) == Lower.LowerCFunctionEmission)
assert(asdl.classof(function_result.func) == C.CBackendFunc)
assert(asdl.classof(function_result.value_types) == Lower.LowerCValueTypeProjection)
assert(function_result.value_types:lower_c_value_lookup(value).entry.code_ty == i32)

local Backend = require("lalin.schema.backend")
local Schedule = require("lalin.schema.schedule")
local Kernel = require("lalin.schema.kernel")
local Flow = require("lalin.schema.flow")
local Value = require("lalin.schema.value")
local Mem = require("lalin.schema.mem")
local Effect = require("lalin.schema.effect")
local id = module.id
local flow = Flow.FlowFactSet(id, {}, {}, {}, {}, {}, {}, {})
local values = Value.ValueFactSet(id, {}, {}, {})
local mem = Mem.MemSemanticFactSet(id, {}, {}, {}, {}, {}, {}, {}, {}, {}, {})
local effects = Effect.EffectFactSet(id, {}, {}, {})
local kernels = Kernel.KernelModulePlan(id, flow, values, mem, effects, {})
local target = Schedule.ScheduleTarget(Backend.BackTargetModel(Backend.BackTargetNative, {}))
local schedules = Schedule.ScheduleModulePlan(id, target, {})
local lower_module = Lower.LowerModule(
  id, Lower.LowerTargetC, kernels, schedules,
  Lower.LowerFunctionPlanProjection({}), {})
local c_target = C.CBackendTarget(C.CBackendC99, C.CBackendHostedNative, 64, 64, C.CBackendLittleEndian, true)
local input = Lower.LowerCModuleInput(
  Lower.LowerBackSpine(module, Graph.CodeGraph(id, {}), c_target), lower_module,
  Lower.LowerKernelCMatProjection({}))
local module_result = lower_module:lower_c_module(input)
assert(asdl.classof(module_result) == Lower.LowerCModuleEmitted)
local emission = module_result.emission
assert(asdl.classof(emission) == Lower.LowerCModuleEmission)
assert(asdl.classof(emission.unit) == C.CBackendUnit)
assert(#emission.functions == 1 and #emission.signatures.entries == 1)
io.write("schema typed C lowering results ok\n")
