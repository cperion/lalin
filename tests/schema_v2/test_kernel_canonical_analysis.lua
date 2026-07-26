package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

require("lalin.schema_v2")
require("lalin.impl.kernel_plan")

local Code = require("lalin.schema_v2.code")
local Core = require("lalin.schema_v2.core")
local Graph = require("lalin.schema_v2.graph")
local Flow = require("lalin.schema_v2.flow")
local Value = require("lalin.schema_v2.value")
local Mem = require("lalin.schema_v2.mem")
local Effect = require("lalin.schema_v2.effect")
local Kernel = require("lalin.schema_v2.kernel")

local module_id = Code.CodeModuleId("kernel_canonical")
local func_id = Code.CodeFuncId("fn:kernel_canonical")
local sig_id = Code.CodeSigId("sig:kernel_canonical")
local block_id = Code.CodeBlockId("body")
local loop_id = Graph.GraphLoopId("loop:kernel_canonical")
local origin = Code.CodeOriginUnknown
local i32 = Code.CodeTyInt(32, Code.CodeSigned)
local ptr_ty = Code.CodeTyDataPtr(i32)
local ptr = Code.CodeValueId("ptr")
local index = Code.CodeValueId("i")
local stop = Code.CodeValueId("n")
local step = Code.CodeValueId("one")
local stored = Code.CodeValueId("stored")

local place = Code.CodePlaceDeref(ptr, i32, 4)
local memory_access = Code.CodeMemoryAccess(Code.CodeMemoryWrite, i32, 4, Code.CodeMustNotTrap, false, nil)
local const_inst = Code.CodeInst(
  Code.CodeInstId("const"),
  Code.CodeInstConst(stored, Code.CodeConstLiteral(i32, Core.LitInt("7"))),
  origin)
local store_inst = Code.CodeInst(
  Code.CodeInstId("store"),
  Code.CodeInstStore(place, stored, memory_access),
  origin)
local term = Code.CodeTerm(Code.CodeTermId("return"), Code.CodeTermReturn({}), origin)
local block = Code.CodeBlock(block_id, "body", {}, { const_inst, store_inst }, term, origin)
local func = Code.CodeFunc(
  func_id,
  "kernel_canonical",
  Code.CodeLinkageLocal,
  sig_id,
  { Code.CodeParam(ptr, "ptr", ptr_ty, origin) },
  {},
  block_id,
  { block },
  origin)
local module = Code.CodeModule(module_id, { Code.CodeSig(sig_id, { ptr_ty }, {}) }, {}, {}, {}, {}, { func }, origin)

local graph_block = Graph.GraphBlockId(func_id, block_id)
local graph_loop = Graph.GraphLoop(loop_id, func_id, graph_block, { graph_block }, {}, {})
local graph = Graph.CodeGraph(module_id, { Graph.CodeFuncGraph(func_id, {}, {}, {}, { graph_loop }) })

local domain = Flow.FlowDomainLoop(loop_id)
local counted = Flow.FlowCountedDomain(index, stop, step, Flow.FlowStopExclusive)
local flow = Flow.FlowFactSet(module_id, { domain }, {}, {
  Flow.FlowLoopFacts(loop_id, domain, counted, { graph_block }, {}, {}, {})
}, {}, {}, {}, {}, {}, {})
local trip = Flow.FlowTripCountExact(Code.CodeValueId("trip"), nil, nil)
local zero = Value.ValueExprConst(Code.CodeConstLiteral(i32, Core.LitInt("0")))
local seven = Value.ValueExprConst(Code.CodeConstLiteral(i32, Core.LitInt("7")))
local reduction = Value.ReductionFact(
  Value.AlgebraFactId("reduction"),
  domain,
  stored,
  Value.ReductionAdd,
  zero,
  seven,
  i32,
  nil,
  nil,
  Value.AlgebraProofFlow(domain, Value.AlgebraFlowCounted(trip)))
local closed = Value.ClosedFormFact(
  Value.AlgebraFactId("closed"),
  reduction,
  seven,
  Value.AlgebraProofComposite({}, "closed form fixture"))
local values = Value.ValueFactSet(module_id, {
  Value.ValueExprFact(stored, seven, Value.AlgebraProofComposite({}, "constant fixture"))
}, { reduction }, { closed })

local access_id = Mem.MemAccessId("access:kernel_canonical:body:store")
local object_id = Mem.MemObjectId("object:ptr")
local object = Mem.MemObjectFact(
  object_id,
  func_id,
  Mem.MemObjectParam,
  Mem.MemProvValue(ptr),
  i32,
  Mem.MemExtentElements(stop, i32, Mem.MemExtentByConstruction),
  Mem.MemStrideUnit)
local access = Mem.MemAccessFact(
  access_id,
  func_id,
  graph_block,
  store_inst.id,
  Mem.MemStore,
  place,
  memory_access,
  Mem.MemBaseValue(ptr),
  Mem.MemIndexValue(index, 4, 0),
  Mem.MemAccessContiguous,
  Mem.MemAlignKnown(4),
  Mem.MemBoundsInObject("counted loop access"),
  Mem.MemNonTrapping("counted loop access"))
local proof = Mem.MemProofBackend(access_id, Mem.MemBackendNoTrapOnAligned("counted loop access"))
local backend = Mem.MemBackendAccessInfo(
  access_id,
  Mem.MemNonTrapping("counted loop access"),
  Mem.MemAlignKnown(4),
  Mem.MemBoundsInObject("counted loop access"),
  Mem.MemDerefBytesKnown(4),
  Mem.MemMovementMovable("counted loop access"),
  { proof })
local mem = Mem.MemSemanticFactSet(module_id, { object }, {}, { access }, {}, {}, {}, {}, {}, { backend }, { proof })
local effects = Effect.EffectFactSet(module_id, {}, {
  Effect.InstEffect(store_inst.id, { Effect.EffectWrite(Effect.EffectObjectMem(object_id), Effect.EffectEvidenceMemory(proof)) })
}, {})

local plan = mem:plan_kernels(module, graph, flow, values, effects)
assert(#plan.plans == 1)
local planned = plan.plans[1]
assert(planned.body.domain.counter.value == index)
assert(#planned.body.lanes.entries == 1)
assert(planned.body.lanes.entries[1].lane.object == object_id)
assert(planned.body.lanes.entries[1].lane.accesses[1] == access_id)
assert(#planned.body.bindings.entries == 1)
assert(planned.body.bindings.entries[1].value == stored)
assert(#planned.body.effects.entries == 1)
assert(planned.body.effects.entries[1].inst.inst == store_inst.id)
assert(planned.body.effects.entries[1].effect.dst == planned.body.lanes.entries[1].lane)
assert(planned.body.result.closed_form == closed)
assert(#planned.body.equivalence.proofs >= 3)

local missing_graph = Graph.CodeGraph(module_id, {})
local rejected = mem:plan_kernels(module, missing_graph, flow, values, effects).plans[1]
assert(#rejected.rejects == 1)
assert(rejected.subject.loop == loop_id)

local volatile = Effect.EffectVolatile(Effect.EffectEvidenceDeclared("volatile fixture"))
local volatile_effects = Effect.EffectFactSet(module_id, {}, { Effect.InstEffect(const_inst.id, { volatile }) }, {})
local effect_rejected = mem:plan_kernels(module, graph, flow, values, volatile_effects).plans[1]
assert(#effect_rejected.rejects == 1)
assert(effect_rejected.rejects[1].effect == volatile)

print("canonical kernel analysis ok")
