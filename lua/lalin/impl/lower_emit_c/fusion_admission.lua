-- Whole-fusion admission over already-typed CMat access and coordinate facts.
require("lalin.schema_v2")
require("lalin.impl.lower_emit_c.materialize")

local Stencil = require("lalin.schema_v2.stencil")
local CMat = require("lalin.schema_v2.c_materialize")
local Lower = require("lalin.schema_v2.lower")

local function append_one(values, value)
  local result = {}
  for i = 1, #values do result[i] = values[i] end
  result[#result + 1] = value
  return result
end

function Lower.LowerCMatAccessFactProjection:lookup(access)
  local found = {}
  for i = 1, #self.entries do
    if self.entries[i].binding.access == access then
      found[#found + 1] = self.entries[i]
    end
  end
  if #found == 0 then return Lower.LowerCMatAccessFactMissing(access) end
  if #found > 1 then
    return Lower.LowerCMatAccessFactAmbiguous(access, #found)
  end
  return Lower.LowerCMatAccessFactFound(found[1])
end

function CMat.CMatMemoryUse:lower_cmat_fusion_admit(input)
  local request = Lower.LowerCMatFusionUseInput(input, self)
  return input.accesses:lookup(self.access):lower_cmat_fusion_match(request)
end

function Lower.LowerCMatAccessFactMissing:lower_cmat_fusion_match(request)
  return Lower.LowerCMatFusionUseRejected(
    Lower.LowerCMatFusionUseAccessMissing(
      request.use.id, request.use.access))
end

function Lower.LowerCMatAccessFactAmbiguous:lower_cmat_fusion_match(request)
  return Lower.LowerCMatFusionUseRejected(
    Lower.LowerCMatFusionUseAccessAmbiguous(
      request.use.id, request.use.access, self.count))
end

function Lower.LowerCMatAccessFactFound:lower_cmat_fusion_match(request)
  local input = Lower.LowerCMatFusionUseMatchInput(request, self.fact)
  return request.admission.coordinates:lookup(request.use.id)
    :lower_cmat_fusion_coordinate(input)
end

function Lower.LowerCMatUseCoordinateMissing:lower_cmat_fusion_coordinate(input)
  return Lower.LowerCMatFusionUseRejected(
    Lower.LowerCMatFusionUseCoordinateMissing(input.request.use.id))
end

function Lower.LowerCMatUseCoordinateAmbiguous:lower_cmat_fusion_coordinate(input)
  return Lower.LowerCMatFusionUseRejected(
    Lower.LowerCMatFusionUseCoordinateAmbiguous(
      input.request.use.id, self.count))
end

function Lower.LowerCMatUseCoordinateFound:lower_cmat_fusion_coordinate(input)
  local role = Lower.LowerCMatFusionRoleInput(
    input.request.use, input.fact, self.entry)
  return input.request.use.role:lower_cmat_fusion_role(role)
end

local function admitted_use(input)
  return Lower.LowerCMatFusionUseAdmitted(
    Lower.LowerCMatFusionUseContract(
      input.use, input.fact, input.coordinate))
end

local function rejected_role(input)
  return Lower.LowerCMatFusionUseRejected(
    Lower.LowerCMatFusionUseRoleConflict(
      input.use, input.fact.binding.mutability))
end

function CMat.CMatMemoryLoad:lower_cmat_fusion_role(input)
  return input.fact.binding.mutability:lower_cmat_fusion_load(input)
end
function CMat.CMatMemoryStore:lower_cmat_fusion_role(input)
  return input.fact.binding.mutability:lower_cmat_fusion_store(input)
end

function CMat.CMatAccessReadOnly:lower_cmat_fusion_load(input)
  return admitted_use(input)
end
function CMat.CMatAccessWriteOnly:lower_cmat_fusion_load(input)
  return rejected_role(input)
end
function CMat.CMatAccessReadWrite:lower_cmat_fusion_load(input)
  return admitted_use(input)
end
function CMat.CMatAccessReduce:lower_cmat_fusion_load(input)
  return admitted_use(input)
end
function CMat.CMatAccessReadOnly:lower_cmat_fusion_store(input)
  return rejected_role(input)
end
function CMat.CMatAccessWriteOnly:lower_cmat_fusion_store(input)
  return admitted_use(input)
end
function CMat.CMatAccessReadWrite:lower_cmat_fusion_store(input)
  return admitted_use(input)
end
function CMat.CMatAccessReduce:lower_cmat_fusion_store(input)
  return admitted_use(input)
end

local function collecting_with(state, uses, aliases, writes, proofs)
  return Lower.LowerCMatFusionCollecting(
    state.input, uses, aliases, writes, proofs)
end

local function rejected_with(state, uses, aliases, writes, proofs, issues)
  return Lower.LowerCMatFusionAssemblyRejected(
    state.input, uses, aliases, writes, proofs, issues)
end

function Lower.LowerCMatFusionCollecting:lower_cmat_fusion_add_issue(issue)
  return rejected_with(self, self.uses, self.aliases, self.writes,
    self.proofs, { issue })
end
function Lower.LowerCMatFusionAssemblyRejected:lower_cmat_fusion_add_issue(issue)
  return rejected_with(self, self.uses, self.aliases, self.writes,
    self.proofs, append_one(self.issues, issue))
end
function Lower.LowerCMatFusionCollecting:lower_cmat_fusion_add_use(contract)
  return collecting_with(self, append_one(self.uses, contract),
    self.aliases, self.writes, self.proofs)
end
function Lower.LowerCMatFusionAssemblyRejected:lower_cmat_fusion_add_use(contract)
  return rejected_with(self, append_one(self.uses, contract),
    self.aliases, self.writes, self.proofs, self.issues)
end
function Lower.LowerCMatFusionCollecting:lower_cmat_fusion_add_alias(contract)
  return collecting_with(self, self.uses,
    append_one(self.aliases, contract), self.writes, self.proofs)
end
function Lower.LowerCMatFusionAssemblyRejected:lower_cmat_fusion_add_alias(contract)
  return rejected_with(self, self.uses,
    append_one(self.aliases, contract), self.writes, self.proofs, self.issues)
end
function Lower.LowerCMatFusionCollecting:lower_cmat_fusion_add_write(contract)
  return collecting_with(self, self.uses, self.aliases,
    append_one(self.writes, contract), self.proofs)
end
function Lower.LowerCMatFusionAssemblyRejected:lower_cmat_fusion_add_write(contract)
  return rejected_with(self, self.uses, self.aliases,
    append_one(self.writes, contract), self.proofs, self.issues)
end
function Lower.LowerCMatFusionCollecting:lower_cmat_fusion_add_proof(proof)
  return collecting_with(self, self.uses, self.aliases, self.writes,
    append_one(self.proofs, proof))
end
function Lower.LowerCMatFusionAssemblyRejected:lower_cmat_fusion_add_proof(proof)
  return rejected_with(self, self.uses, self.aliases, self.writes,
    append_one(self.proofs, proof), self.issues)
end

function Lower.LowerCMatFusionUseRejected:lower_cmat_fusion_collect(input)
  return input.assembly:lower_cmat_fusion_add_issue(self.issue)
end
function Lower.LowerCMatFusionUseAdmitted:lower_cmat_fusion_collect(input)
  local next_state = input.assembly:lower_cmat_fusion_add_use(self.contract)
  return self.contract.use.role:lower_cmat_fusion_write(
    Lower.LowerCMatFusionWriteInput(self.contract, input.ordinal))
    :lower_cmat_fusion_collect_write(next_state)
end

function CMat.CMatMemoryLoad:lower_cmat_fusion_write(_input)
  return Lower.LowerCMatFusionNoWrite
end
function CMat.CMatMemoryStore:lower_cmat_fusion_write(input)
  return input.contract.use.id:lower_cmat_fusion_store_use(input)
end
function CMat.CMatSinkMemoryUse:lower_cmat_fusion_store_use(input)
  return Lower.LowerCMatFusionWriteAdmitted(
    Lower.LowerCMatFusionWriteContract(
      input.ordinal, self.sink, input.contract.use.id,
      input.contract.access.binding.access, input.contract.coordinate))
end
function CMat.CMatStreamMemoryUse:lower_cmat_fusion_store_use(input)
  return Lower.LowerCMatFusionWriteRejected(
    Lower.LowerCMatFusionStoreUseNotSink(input.contract.use))
end
function CMat.CMatWindowMemoryUse:lower_cmat_fusion_store_use(input)
  return Lower.LowerCMatFusionWriteRejected(
    Lower.LowerCMatFusionStoreUseNotSink(input.contract.use))
end
function Lower.LowerCMatFusionNoWrite:lower_cmat_fusion_collect_write(state)
  return state
end
function Lower.LowerCMatFusionWriteAdmitted:lower_cmat_fusion_collect_write(state)
  return state:lower_cmat_fusion_add_write(self.contract)
end
function Lower.LowerCMatFusionWriteRejected:lower_cmat_fusion_collect_write(state)
  return state:lower_cmat_fusion_add_issue(self.issue)
end

function Stencil.StencilAccessAliasPairFound:lower_cmat_fusion_alias(input)
  return input.assembly:lower_cmat_fusion_add_alias(
    Lower.LowerCMatFusionAliasContract(
      input.left.binding.access, input.right.binding.access,
      Lower.LowerCMatFusionAliasDeclared(self.relation)))
end
function Stencil.StencilAccessAliasPairMissing:lower_cmat_fusion_alias(input)
  return input.assembly:lower_cmat_fusion_add_alias(
    Lower.LowerCMatFusionAliasContract(
      input.left.binding.access, input.right.binding.access,
      Lower.LowerCMatFusionAliasUnspecified))
end
function Stencil.StencilAccessAliasPairAmbiguous:lower_cmat_fusion_alias(input)
  return input.assembly:lower_cmat_fusion_add_issue(
    Lower.LowerCMatFusionAliasAmbiguous(
      input.left.binding.access, input.right.binding.access, self.count))
end

local function collect_aliases(state)
  local legality = state.input.materialization.kernel.computation.legality
  local facts = state.input.accesses.entries
  local result = state
  for i = 1, #facts do
    for j = i + 1, #facts do
      local left, right = facts[i], facts[j]
      local lookup = legality:cmat_alias_pair_lookup(
        Stencil.StencilAccessAliasPairInput(
          left.binding.access, right.binding.access))
      result = lookup:lower_cmat_fusion_alias(
        Lower.LowerCMatFusionAliasInput(result, left, right))
    end
  end
  return result
end

function Stencil.StencilProofUnproven:lower_cmat_fusion_proof(input)
  return input.assembly:lower_cmat_fusion_add_issue(
    Lower.LowerCMatFusionProofUnresolved(input.obligation))
end
function Stencil.StencilProofProvided:lower_cmat_fusion_proof(input)
  return input.assembly:lower_cmat_fusion_add_proof(input.obligation)
end

function Lower.LowerCMatFusionCollecting:lower_cmat_fusion_collect_aliases()
  return collect_aliases(self)
end
function Lower.LowerCMatFusionAssemblyRejected:lower_cmat_fusion_collect_aliases()
  return collect_aliases(self)
end

function Lower.LowerCMatFusionCollecting:lower_cmat_fusion_finish()
  return Lower.LowerCMatFusionAdmitted(Lower.LowerCMatFusionContract(
    self.input.materialization.kernel.id,
    self.input.materialization.kernel:cmat_memory_use_spine(),
    self.input.accesses, self.uses, self.aliases, self.writes, self.proofs))
end
function Lower.LowerCMatFusionAssemblyRejected:lower_cmat_fusion_finish()
  return Lower.LowerCMatFusionRejected(self.issues)
end

function Lower.LowerCMatFusionAdmissionInput:lower_cmat_admit_fusion()
  local spine = self.materialization.kernel:cmat_memory_use_spine()
  local state = Lower.LowerCMatFusionCollecting(self, {}, {}, {}, {})
  if spine ~= self.coordinates.spine then
    state = state:lower_cmat_fusion_add_issue(
      Lower.LowerCMatFusionSpineDisagreement(spine, self.coordinates.spine))
  end
  local legality = self.materialization.kernel.computation.legality
  for i = 1, #legality.rejects do
    state = state:lower_cmat_fusion_add_issue(
      Lower.LowerCMatFusionLegalityRejected(legality.rejects[i]))
  end
  for i = 1, #legality.proof_obligations do
    local obligation = legality.proof_obligations[i]
    state = obligation.evidence:lower_cmat_fusion_proof(
      Lower.LowerCMatFusionProofInput(state, obligation))
  end
  for i = 1, #spine.uses do
    state = spine.uses[i]:lower_cmat_fusion_admit(self)
      :lower_cmat_fusion_collect(
        Lower.LowerCMatFusionCollectInput(state, i))
  end
  return state:lower_cmat_fusion_collect_aliases()
    :lower_cmat_fusion_finish()
end

return Lower
