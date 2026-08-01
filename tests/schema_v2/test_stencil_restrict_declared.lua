package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local asdl = require("lalin.asdl")
require("lalin.schema_v2")
require("lalin.impl.lower_emit_c.materialize")
require("lalin.impl.lower_emit_c.stencil")

local Code = require("lalin.schema_v2.code")
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

io.write("schema_v2 declared noalias restrict decisions ok\n")
