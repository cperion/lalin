package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local asdl = require("lalin.asdl")
require("lalin.schema_v2")
require("lalin.impl.lower_emit_c.materialize")
require("lalin.impl.lower_emit_c.stencil")
require("lalin.impl.stencil_kernel")

local Code = require("lalin.schema_v2.code")
local Graph = require("lalin.schema_v2.graph")
local Flow = require("lalin.schema_v2.flow")
local Value = require("lalin.schema_v2.value")
local Mem = require("lalin.schema_v2.mem")
local Kernel = require("lalin.schema_v2.kernel")
local Stencil = require("lalin.schema_v2.stencil")
local CMat = require("lalin.schema_v2.c_materialize")
local C = require("lalin.schema_v2.c")

local i32 = Code.CodeTyInt(32, Code.CodeSigned)
local function access(name, role)
  return Stencil.StencilAccess(name, role, i32,
    Stencil.StencilAccessDirect(Stencil.StencilLayoutContiguous(4)))
end
local a = access("a", Stencil.StencilAccessRead)
local b = access("b", Stencil.StencilAccessRead)
local c = access("c", Stencil.StencilAccessWrite)
local ar, br, cr = Stencil.StencilAccessRef("a"), Stencil.StencilAccessRef("b"), Stencil.StencilAccessRef("c")
local function relation(left, right, alias)
  return Stencil.StencilFusionAccessAliasRelation(left, right, alias)
end
local compiler = Stencil.StencilCompilerPolicy(
  Stencil.StencilCompilerGcc, Stencil.StencilOptO3, {})
local schedule = Stencil.StencilScheduleScalar(compiler)
local producer = Stencil.StencilProducer(
  Stencil.StencilProducerOriginNone,
  Stencil.StencilProduceRange1D(i32, Stencil.StencilBoundDynamic,
    Stencil.StencilBoundDynamic, 1, Stencil.StencilProducerForward))
local serial = 0
local function computation(accesses, facts)
  serial = serial + 1
  return Stencil.StencilComputation(
    Stencil.StencilComputationId("restrict:" .. serial), producer, accesses, {}, {},
    Stencil.StencilFusionLegality(facts, {}, {}), schedule, {})
end
local function decision(comp, ref)
  return comp:cmat_access_restrict_decision(ref)
end

local full = computation({ a, b, c }, {
  relation(ar, br, Stencil.StencilAliasNoAlias),
  relation(ar, cr, Stencil.StencilAliasNoAlias),
  relation(br, cr, Stencil.StencilAliasNoAlias),
})
assert(decision(full, ar) == Stencil.StencilAccessRestrictDerived)
assert(decision(full, br) == Stencil.StencilAccessRestrictDerived)
assert(decision(full, cr) == Stencil.StencilAccessRestrictDerived)

local partial = computation({ a, b, c }, {
  relation(ar, br, Stencil.StencilAliasNoAlias),
})
local missing = decision(partial, ar)
assert(asdl.classof(missing) == Stencil.StencilAccessRestrictMissing)
assert(missing.other == cr)

local may_alias = computation({ a, b }, {
  relation(ar, br, Stencil.StencilAliasMayAlias),
})
local contradicted = decision(may_alias, ar)
assert(asdl.classof(contradicted) == Stencil.StencilAccessRestrictContradicted)
assert(contradicted.relation == Stencil.StencilAliasMayAlias)

local unknown = computation({ a, b }, {
  relation(ar, br, Stencil.StencilAliasUnknown),
})
assert(asdl.classof(decision(unknown, ar)) ==
  Stencil.StencilAccessRestrictContradicted)

local ambiguous = computation({ a, b }, {
  relation(ar, br, Stencil.StencilAliasNoAlias),
  relation(ar, br, Stencil.StencilAliasMayAlias),
})
local ambiguity = decision(ambiguous, ar)
assert(asdl.classof(ambiguity) == Stencil.StencilAccessRestrictAmbiguous)
assert(ambiguity.count == 2)

local reversed = computation({ a, b }, {
  relation(br, ar, Stencil.StencilAliasNoAlias),
})
assert(decision(reversed, ar) == Stencil.StencilAccessRestrictDerived)
assert(decision(computation({ a }, {}), ar) ==
  Stencil.StencilAccessRestrictDerived)

local obligation = Stencil.StencilProofObligation(
  Stencil.StencilProofNoAlias(ar, br), Stencil.StencilProofAuthorAsserted,
  Stencil.StencilProofUnproven)
local obligation_only = computation({ a, b }, {
  Stencil.StencilFusionProofObligation(obligation),
})
assert(asdl.classof(decision(obligation_only, ar)) ==
  Stencil.StencilAccessRestrictMissing)
local obligation_fact_materialized = obligation_only:cmat_materialize(
  CMat.CMatMaterializationInput(CMat.CMatKernelId("restrict:obligation-fact")))
assert(asdl.classof(obligation_fact_materialized) == CMat.CMatMaterializedFused)
for i = 1, #obligation_fact_materialized.kernel.accesses do
  assert(asdl.classof(
    obligation_fact_materialized.kernel.accesses[i].restrict_capability) ==
    CMat.CMatRestrictIneligible)
end

local obligation_list_computation = Stencil.StencilComputation(
  Stencil.StencilComputationId("restrict:obligation-list"), producer, { a, b }, {}, {},
  Stencil.StencilFusionLegality({}, { obligation }, {}), schedule, {})
local obligation_list_materialized = obligation_list_computation:cmat_materialize(
  CMat.CMatMaterializationInput(CMat.CMatKernelId("restrict:obligation-list")))
assert(asdl.classof(obligation_list_materialized) == CMat.CMatMaterializedFused)
for i = 1, #obligation_list_materialized.kernel.accesses do
  assert(asdl.classof(
    obligation_list_materialized.kernel.accesses[i].restrict_capability) ==
    CMat.CMatRestrictIneligible)
end

local materialized = full:cmat_materialize(
  CMat.CMatMaterializationInput(CMat.CMatKernelId("restrict:full")))
assert(asdl.classof(materialized) == CMat.CMatMaterializedFused)
for i = 1, #materialized.kernel.accesses do
  local binding = materialized.kernel.accesses[i]
  assert(binding.restrict_capability == CMat.CMatRestrictEligible)
  local emitted = binding:cmat_c_access_binding()
  assert(asdl.classof(emitted) == CMat.CMatCAccessCBindingReady)
  assert(asdl.classof(emitted.entry.param.ty) == C.CBackendQualifiedDataPtr)
  assert(emitted.entry.param.ty.restrict_ptr == true)
end

local unproven = computation({ a, b }, {})
local unproven_materialized = unproven:cmat_materialize(
  CMat.CMatMaterializationInput(CMat.CMatKernelId("restrict:missing")))
assert(asdl.classof(unproven_materialized) == CMat.CMatMaterializedFused)
for i = 1, #unproven_materialized.kernel.accesses do
  assert(asdl.classof(unproven_materialized.kernel.accesses[i].restrict_capability) ==
    CMat.CMatRestrictIneligible)
end

-- Declared disjoint dependence facts populate kernel stencil legality; inferred
-- dependence proofs do not.
local func_id = Code.CodeFuncId("restrict:func")
local module_id = Code.CodeModuleId("restrict:module")
local loop_id = Graph.GraphLoopId("restrict:loop")
local start, stop, step, index, trip_value =
  Code.CodeValueId("start"), Code.CodeValueId("stop"), Code.CodeValueId("step"),
  Code.CodeValueId("index"), Code.CodeValueId("trip")
local trip = Flow.FlowTripCountExact(trip_value, nil, nil)
local domain = Flow.FlowDomainLoop(loop_id)
local lane_a = Kernel.KernelLane(
  Kernel.KernelLaneId("lane:a"), Mem.MemObjectId("object:a"), { Mem.MemAccessId("mem:a") },
  Mem.MemBaseValue(Code.CodeValueId("base:a")), i32, Mem.MemAccessScalar, {})
local lane_b = Kernel.KernelLane(
  Kernel.KernelLaneId("lane:b"), Mem.MemObjectId("object:b"), { Mem.MemAccessId("mem:b") },
  Mem.MemBaseValue(Code.CodeValueId("base:b")), i32, Mem.MemAccessScalar, {})
local planned = Kernel.KernelPlanned(
  Kernel.KernelId("restrict:kernel"), Kernel.KernelSubjectLoop(loop_id),
  Kernel.KernelBody(
    Kernel.KernelDomainFlow(domain, Kernel.KernelTripKnown(trip),
      Kernel.KernelCounterValue(index)),
    Kernel.KernelLaneProjection({
      Kernel.KernelLaneByAccessEntry(lane_a.accesses[1], lane_a),
      Kernel.KernelLaneByAccessEntry(lane_b.accesses[1], lane_b),
    }), Kernel.KernelBindingProjection({}), Kernel.KernelEffectProjection({}),
    Kernel.KernelResultVoid, Kernel.KernelEquivalenceProof({
      Kernel.KernelProofFunctionEquivalence("declared disjoint fixture"),
    })))
local iteration = Stencil.StencilKernelIteration(
  loop_id, index, i32, start, stop, step, 1,
  Stencil.StencilIterationStopInclusive, Stencil.StencilProducerForward,
  Stencil.StencilKernelTripExact(trip))
local source_shape = Flow.FlowDomainShapeFact(
  domain, Flow.FlowDomainShapeRange1D(i32, Value.ValueExprValue(start),
    Value.ValueExprValue(stop), 1, Flow.FlowDomainForward), {},
  Flow.FlowFactCheckerDerived)
local state = Stencil.StencilKernelConstructionState(
  planned, iteration, Stencil.StencilKernelCountedDomain1D(source_shape), producer,
  Stencil.StencilAccessByKernelLaneProjection({
    Stencil.StencilAccessByKernelLaneEntry(lane_a, a),
    Stencil.StencilAccessByKernelLaneEntry(lane_b, b),
  }), Stencil.StencilStreamByKernelValueProjection({}), {}, {}, {},
  Stencil.StencilFusionLegality({}, {}, {}), planned.body.equivalence.proofs, 1)
local contract = Code.CodeFuncContractFact(
  func_id, Code.CodeContractDisjoint(Code.CodeValueId("base:a"),
    Code.CodeValueId("base:b")), Code.CodeOriginUnknown)
local proof = Mem.MemProofContract(
  contract, Mem.MemContractNoAlias("disjoint", "base:a"))
local dependence = Mem.MemNoDependence(lane_a.accesses[1], lane_b.accesses[1], proof)
local mem = Mem.MemSemanticFactSet(
  module_id, {}, {}, {}, {}, {}, {}, { dependence }, {}, {}, { proof })
local projected_state = state:stencil_with_alias_legality(
  Stencil.StencilKernelAliasProjectionInput(mem))
assert(#projected_state.legality.facts == 1)
local projected_fact = projected_state.legality.facts[1]
assert(asdl.classof(projected_fact) == Stencil.StencilFusionAccessAliasRelation)
assert(projected_fact.left == ar and projected_fact.right == br)
assert(projected_fact.relation == Stencil.StencilAliasNoAlias)

local inferred = Mem.MemNoDependence(
  lane_a.accesses[1], lane_b.accesses[1],
  Mem.MemProofBackend(lane_a.accesses[1],
    Mem.MemBackendNoTrapOnAligned("inferred")))
local inferred_mem = Mem.MemSemanticFactSet(
  module_id, {}, {}, {}, {}, {}, {}, { inferred }, {}, {}, {})
local inferred_state = state:stencil_with_alias_legality(
  Stencil.StencilKernelAliasProjectionInput(inferred_mem))
assert(#inferred_state.legality.facts == 0)

io.write("schema_v2 declared noalias restrict decisions ok\n")
