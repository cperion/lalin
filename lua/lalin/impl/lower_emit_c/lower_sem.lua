-- Canonical LOWER semantic-fragment preparation and typed coverage resolution.
require("lalin.schema_v2")
require("lalin.impl.stencil_kernel")
require("lalin.impl.lower_emit_c.materialize")
require("lalin.impl.lower_emit_c.code_to_c")
require("lalin.impl.lower_emit_c.fragment")

local Lower = require("lalin.schema_v2.lower")
local Stencil = require("lalin.schema_v2.stencil")
local CMat = require("lalin.schema_v2.c_materialize")
local C = require("lalin.schema_v2.c")
local Code = require("lalin.schema_v2.code")
local Mem = require("lalin.schema_v2.mem")

local function copy(items)
  local out = {}
  for i = 1, #items do out[i] = items[i] end
  return out
end

function Lower.LowerKernelCMatProjection:lower_cmat_lookup(kernel)
  local found = {}
  for i = 1, #self.entries do
    if self.entries[i].kernel == kernel then
      found[#found + 1] = self.entries[i]
    end
  end
  if #found == 0 then return Lower.LowerKernelCMatMissing(kernel) end
  if #found > 1 then return Lower.LowerKernelCMatAmbiguous(kernel, #found) end
  return Lower.LowerKernelCMatFound(found[1])
end

function Stencil.StencilKernelProjected:lower_cmat_state(kernel)
  return Lower.LowerKernelCMatReady(
    self.projection,
    self.projection:cmat_materialize_kernel(
      CMat.CMatKernelMaterializationInput(CMat.CMatKernelId(kernel.text))))
end

function Stencil.StencilKernelProjectionRejected:lower_cmat_state(_kernel)
  return Lower.LowerKernelCMatRejected(self.rejects)
end

function Stencil.StencilKernelModuleProjectedEntry:lower_cmat_entries()
  return { Lower.LowerKernelCMatEntry(
    self.kernel, self.result:lower_cmat_state(self.kernel)) }
end
function Stencil.StencilKernelModuleRejectedEntry:lower_cmat_entries()
  return {}
end

function Stencil.StencilKernelModuleProjected:lower_cmat_prepare()
  local entries = {}
  for i = 1, #self.projection.entries do
    local additions = self.projection.entries[i]:lower_cmat_entries()
    for j = 1, #additions do entries[#entries + 1] = additions[j] end
  end
  return Lower.LowerKernelCMatPrepared(Lower.LowerKernelCMatProjection(entries))
end

function Stencil.StencilKernelModuleProjectionRejected:lower_cmat_prepare()
  return Lower.LowerKernelCMatPreparationRejected(self.expected, self.actual)
end

function Stencil.StencilKernelModuleFacetMismatch:lower_cmat_prepare()
  return Lower.LowerKernelCMatPreparationFacetRejected(self.reason)
end

function Lower.LowerKernelCMatPreparationInput:lower_prepare_cmat()
  return Stencil.StencilKernelModuleProjectionInput(
    self.module, self.graph, self.kernels.flow, self.semantics,
    self.kernels, self.schedules, self.compiler):project_kernel_module()
  :lower_cmat_prepare()
end

function Lower.LowerLoopByIdMissing:lower_resolve_coverage(input, cover)
  return Lower.LowerFragmentCoverageRejected(
    Lower.LowerIssueCoverageRejected(
      cover, "loop is absent from the owning function graph"))
end

function Lower.LowerLoopByIdFound:lower_resolve_coverage(input, cover)
  if self.entry.loop.func ~= input.code_func.id then
    return Lower.LowerFragmentCoverageRejected(
      Lower.LowerIssueCoverageRejected(
        cover, "loop belongs to a different function"))
  end
  local blocks = {}
  for i = 1, #self.entry.loop.body do
    blocks[i] = self.entry.loop.body[i].block
  end
  return Lower.LowerFragmentCoverageResolved(Lower.LowerFragmentCoverage(
    input.code_func.id, Lower.LowerCoverageLoop(self.entry.loop),
    blocks, self.entry.loop.header.block))
end

function Lower.LowerCoverLoop:lower_c_fragment_coverage(input)
  return input.loops:lookup(self.loop):lower_resolve_coverage(input, self)
end

function Lower.LowerCoverFunction:lower_c_fragment_coverage(input)
  if self.func ~= input.code_func.id then
    return Lower.LowerFragmentCoverageRejected(
      Lower.LowerIssueCoverageRejected(
        self, "function cover names a different function"))
  end
  local blocks = {}
  for i = 1, #input.code_func.blocks do blocks[i] = input.code_func.blocks[i].id end
  return Lower.LowerFragmentCoverageResolved(Lower.LowerFragmentCoverage(
    self.func, Lower.LowerCoverageFunction, blocks, input.code_func.entry))
end

function Lower.LowerCoverBlock:lower_c_fragment_coverage(input)
  if self.func ~= input.code_func.id then
    return Lower.LowerFragmentCoverageRejected(
      Lower.LowerIssueCoverageRejected(self, "block cover names a different function"))
  end
  local found = {}
  for i = 1, #input.code_func.blocks do
    if input.code_func.blocks[i].id == self.block then found[#found + 1] = self.block end
  end
  if #found ~= 1 then
    return Lower.LowerFragmentCoverageRejected(
      Lower.LowerIssueCoverageRejected(self, "block cover is absent or ambiguous"))
  end
  return Lower.LowerFragmentCoverageResolved(Lower.LowerFragmentCoverage(
    self.func, Lower.LowerCoverageBlock, found, self.block))
end

function Lower.LowerCoverBlockRange:lower_c_fragment_coverage(input)
  if self.func ~= input.code_func.id then
    return Lower.LowerFragmentCoverageRejected(
      Lower.LowerIssueCoverageRejected(self, "block-range cover names a different function"))
  end
  local blocks = {}
  local active = false
  local finished = false
  for i = 1, #input.code_func.blocks do
    local block = input.code_func.blocks[i]
    if block.id == self.entry then active = true end
    if active and not finished then blocks[#blocks + 1] = block.id end
    if active and block.id == self.exit then finished = true end
  end
  if #blocks == 0 or blocks[1] ~= self.entry or blocks[#blocks] ~= self.exit then
    return Lower.LowerFragmentCoverageRejected(
      Lower.LowerIssueCoverageRejected(self, "block range is absent or reversed"))
  end
  return Lower.LowerFragmentCoverageResolved(Lower.LowerFragmentCoverage(
    self.func, Lower.LowerCoverageBlockRange, copy(blocks), self.entry))
end
function Lower.LowerFragmentCoverage:lower_c_block_coverage(block)
  for i = 1, #self.covered_blocks do
    if self.covered_blocks[i] == block then return Lower.LowerCBlockCovered end
  end
  return Lower.LowerCBlockOutsideCoverage
end
function Lower.LowerCFunctionParamSite:lower_cmat_value_contribution(input)
  return Lower.LowerCValueAvailable(input.value)
end
function Lower.LowerCBlockCovered:lower_cmat_value_contribution(_input)
  return Lower.LowerCValueUnavailable
end
function Lower.LowerCBlockOutsideCoverage:lower_cmat_value_contribution(input)
  return Lower.LowerCValueAvailable(input.value)
end
function Lower.LowerCBlockParamSite:lower_cmat_value_contribution(_input)
  return Lower.LowerCValueUnavailable
end
function Lower.LowerCInstructionSite:lower_cmat_value_contribution(_input)
  return Lower.LowerCValueUnavailable
end
function Lower.LowerCValueAvailable:lower_cmat_collect_value(collection)
  local entries = copy(collection.entries)
  entries[#entries + 1] = CMat.CMatCExternalValueBindingEntry(
    self.value.value, self.value.c_local)
  return Lower.LowerCMatValueCollection(entries)
end
function Lower.LowerCValueUnavailable:lower_cmat_collect_value(collection)
  return collection
end
function Lower.LowerCMatValueEnvironmentInput:lower_cmat_values()
  local collection = Lower.LowerCMatValueCollection({})
  for i = 1, #self.baseline.value_types.entries do
    local value = self.baseline.value_types.entries[i]
    local sites = {}
    for j = 1, #self.baseline.value_sites.entries do
      if self.baseline.value_sites.entries[j].value == value.value then
        sites[#sites + 1] = self.baseline.value_sites.entries[j]
      end
    end
    if #sites ~= 1 then
      return Lower.LowerCMatValuesRejected(
        Lower.LowerIssueValueUnavailable(
          value.value, "value definition site is absent or ambiguous"))
    end
    collection = sites[1].site:lower_cmat_value_contribution(
      Lower.LowerCValueAvailabilityInput(self.coverage, value))
:lower_cmat_collect_value(collection)
  end
  return Lower.LowerCMatValuesReady(
    CMat.CMatCExternalValueBindingProjection(collection.entries))
end
function Lower.LowerCoverageLoop:lower_cmat_normal_exit(_coverage)
  if #self.loop.exits ~= 1 then
    return Lower.LowerCMatExitRequirementsRejected(
      Lower.LowerIssueExitShapeRejected(
        "counted kernel coverage requires one exact loop exit"))
  end
  return Lower.LowerCMatExitRequirementsReady(
    Lower.LowerCMatExitRequirementProjection({
      Lower.LowerCMatExitRequirement(
        CMat.CMatCExitNormal, self.loop.exits[1].to.block,
        Lower.LowerCMatExitSourceEdge(self.loop.exits[1].from.block))
    }))
end
function Lower.LowerCoverageFunction:lower_cmat_normal_exit(_coverage)
  return Lower.LowerCMatExitRequirementsRejected(
    Lower.LowerIssueExitShapeRejected(
      "whole-function CMat coverage has no normal continuation"))
end
function Lower.LowerCoverageBlock:lower_cmat_normal_exit(_coverage)
  return Lower.LowerCMatExitRequirementsRejected(
    Lower.LowerIssueExitShapeRejected(
      "standalone block CMat coverage is unsupported"))
end
function Lower.LowerCoverageBlockRange:lower_cmat_normal_exit(_coverage)
  return Lower.LowerCMatExitRequirementsRejected(
    Lower.LowerIssueExitShapeRejected(
      "standalone block-range CMat coverage is unsupported"))
end
function Stencil.StencilKernelResultVoid:lower_cmat_exit_requirements(coverage)
  return coverage.origin:lower_cmat_normal_exit(coverage)
end
function Stencil.StencilKernelResultReduction:lower_cmat_exit_requirements(coverage)
  if #coverage.origin.loop.exits ~= 1 then
    return Lower.LowerCMatExitRequirementsRejected(
      Lower.LowerIssueExitShapeRejected(
        "reduction coverage requires one exact loop exit"))
  end
  return Lower.LowerCMatExitRequirementsReady(
    Lower.LowerCMatExitRequirementProjection({
      Lower.LowerCMatExitRequirement(
        CMat.CMatCExitNormal, coverage.origin.loop.exits[1].to.block,
        Lower.LowerCMatExitControlValue),
    }))
end
local function binary_requirements(
    first_role, first, second_role, second, argument_plan)
  return Lower.LowerCMatExitRequirementsReady(
    Lower.LowerCMatExitRequirementProjection({
      Lower.LowerCMatExitRequirement(first_role, first, argument_plan),
      Lower.LowerCMatExitRequirement(second_role, second, argument_plan),
    }))
end
function Stencil.StencilKernelResultAll:lower_cmat_exit_requirements(_coverage)
  return binary_requirements(
    CMat.CMatCExitSuccess, self.success,
    CMat.CMatCExitFailure, self.failure, Lower.LowerCMatExitNoArguments)
end
function Stencil.StencilKernelResultAllCompare:lower_cmat_exit_requirements(_coverage)
  return binary_requirements(
    CMat.CMatCExitSuccess, self.success,
    CMat.CMatCExitFailure, self.failure, Lower.LowerCMatExitNoArguments)
end
function Stencil.StencilKernelResultAny:lower_cmat_exit_requirements(_coverage)
  return binary_requirements(
    CMat.CMatCExitSuccess, self.success,
    CMat.CMatCExitFailure, self.failure, Lower.LowerCMatExitNoArguments)
end
function Stencil.StencilKernelResultFind:lower_cmat_exit_requirements(_coverage)
  return binary_requirements(
    CMat.CMatCExitFound, self.found,
    CMat.CMatCExitNotFound, self.not_found, Lower.LowerCMatExitControlValue)
end
local function append_exit(requirement, collection, args)
  local entries = copy(collection.entries)
  entries[#entries + 1] = CMat.CMatCExitBindingEntry(
    requirement.role, requirement.destination,
    C.CBackendLabel(requirement.destination.text), args)
  return Lower.LowerCMatExitBuildReady(
    Lower.LowerCMatExitCollection(entries))
end
local function exit_rejected(requirement, reason)
  return Lower.LowerCMatExitBuildRejected(
    Lower.LowerIssueExitRejected(
      requirement.role, requirement.destination, reason))
end
function Code.CodeTermJump:lower_cmat_exit_arguments(input)
  if self.dest == input.destination then
    return Lower.LowerCMatExitArgumentsResolved(self.args)
  end
  return Lower.LowerCMatExitArgumentsRejected(
    "source jump does not target the required destination")
end
local function branch_exit_arguments(input, first_dest, first_args, second_dest, second_args)
  local matches = {}
  if first_dest == input.destination then matches[#matches + 1] = first_args end
  if second_dest == input.destination then matches[#matches + 1] = second_args end
  if #matches == 1 then return Lower.LowerCMatExitArgumentsResolved(matches[1]) end
  return Lower.LowerCMatExitArgumentsRejected(
    "source branch does not have one exact required edge")
end
function Code.CodeTermBranch:lower_cmat_exit_arguments(input)
  return branch_exit_arguments(
    input, self.then_dest, self.then_args, self.else_dest, self.else_args)
end
local function switch_exit_arguments(input, cases, default_dest, default_args)
  local matches = {}
  for i = 1, #cases do
    if cases[i].dest == input.destination then matches[#matches + 1] = cases[i].args end
  end
  if default_dest == input.destination then matches[#matches + 1] = default_args end
  if #matches == 1 then return Lower.LowerCMatExitArgumentsResolved(matches[1]) end
  return Lower.LowerCMatExitArgumentsRejected(
    "source switch does not have one exact required edge")
end
function Code.CodeTermSwitch:lower_cmat_exit_arguments(input)
  return switch_exit_arguments(input, self.cases, self.default_dest, self.default_args)
end
function Code.CodeTermVariantSwitch:lower_cmat_exit_arguments(input)
  return switch_exit_arguments(input, self.cases, self.default_dest, self.default_args)
end
function Code.CodeTermReturn:lower_cmat_exit_arguments(_input)
  return Lower.LowerCMatExitArgumentsRejected("return has no block destination")
end
function Code.CodeTermTrap:lower_cmat_exit_arguments(_input)
  return Lower.LowerCMatExitArgumentsRejected("trap has no block destination")
end
function Code.CodeTermUnreachable:lower_cmat_exit_arguments(_input)
  return Lower.LowerCMatExitArgumentsRejected("unreachable has no block destination")
end
function Lower.LowerCMatExitArgumentsResolved:lower_cmat_finish_source_exit(input)
  if #self.args ~= 0 then
    return exit_rejected(input.requirement,
      "initial normal CMat exit cannot preserve covered source arguments")
  end
  return append_exit(input.requirement, input.collection, {})
end
function Lower.LowerCMatExitArgumentsRejected:lower_cmat_finish_source_exit(input)
  return exit_rejected(input.requirement, self.reason)
end
function Lower.LowerCMatExitNoArguments:lower_cmat_build_exit(input, destination)
  if #destination.params ~= 0 then
    return exit_rejected(input.requirement,
      "control branch requires a zero-parameter destination")
  end
  return append_exit(input.requirement, input.collection, {})
end
function Lower.LowerCMatExitControlValue:lower_cmat_build_exit(input, destination)
  if #destination.params ~= 1 then
    return exit_rejected(input.requirement,
      "control result requires exactly one destination parameter")
  end
  return append_exit(input.requirement, input.collection, {
    CMat.CMatCExitArgumentControlValue,
  })
end
function Lower.LowerCMatExitSourceEdge:lower_cmat_build_exit(input, _destination)
  local sources = {}
  for i = 1, #input.code_func.blocks do
    if input.code_func.blocks[i].id == self.source then
      sources[#sources + 1] = input.code_func.blocks[i]
    end
  end
  if #sources ~= 1 then
    return exit_rejected(input.requirement,
      "normal exit source block is absent or ambiguous")
  end
  return sources[1].term.op:lower_cmat_exit_arguments(
    Lower.LowerCMatSourceExitInput(self.source, input.requirement.destination))
:lower_cmat_finish_source_exit(input)
end
function Lower.LowerCMatExitRequirement:lower_cmat_build_exit(input)
  local matches = {}
  for i = 1, #input.code_func.blocks do
    if input.code_func.blocks[i].id == self.destination then
      matches[#matches + 1] = input.code_func.blocks[i]
    end
  end
  if #matches ~= 1 then
    return exit_rejected(self, "control destination is absent or ambiguous")
  end
  return self.argument_plan:lower_cmat_build_exit(input, matches[1])
end
function Lower.LowerCMatExitBuildReady:lower_cmat_continue_exits(input)
  if input.index > #input.requirements.entries then
    return Lower.LowerCMatExitsReady(
      CMat.CMatCExitBindingProjection(self.collection.entries))
  end
  local requirement = input.requirements.entries[input.index]
  return requirement:lower_cmat_build_exit(
    Lower.LowerCMatExitBuildInput(
      requirement, input.code_func, self.collection))
:lower_cmat_continue_exits(Lower.LowerCMatExitFoldInput(
    input.requirements, input.code_func, input.index + 1))
end
function Lower.LowerCMatExitBuildRejected:lower_cmat_continue_exits(_input)
  return Lower.LowerCMatExitsRejected(self.issue)
end
function Lower.LowerCMatExitRequirementsReady:lower_cmat_build_exits(input)
  return Lower.LowerCMatExitBuildReady(Lower.LowerCMatExitCollection({}))
:lower_cmat_continue_exits(Lower.LowerCMatExitFoldInput(
    self.requirements, input.code_func, 1))
end
function Lower.LowerCMatExitRequirementsRejected:lower_cmat_build_exits(_input)
  return Lower.LowerCMatExitsRejected(self.issue)
end
function Lower.LowerCMatExitEnvironmentInput:lower_cmat_exits()
  return self.provenance.result:lower_cmat_exit_requirements(self.coverage)
:lower_cmat_build_exits(self)
end
local function access_issue(access, reason)
  return Lower.LowerIssueAccessRejected(access, reason)
end
function CMat.CMatCExternalValueBindingFound:lower_cmat_direct_access(input)
  if self.entry.c_local.ty ~= input.expected then
    return Lower.LowerCMatAccessSourceRejected(access_issue(
      input.access, "direct access base has the wrong projected pointer type"))
  end
  return Lower.LowerCMatAccessSourceReady(
    CMat.CMatCFragmentAccessDirect(self.entry.c_local))
end
function CMat.CMatCExternalValueBindingMissing:lower_cmat_direct_access(input)
  return Lower.LowerCMatAccessSourceRejected(access_issue(
    input.access, "direct access base is unavailable at fragment entry"))
end
function Mem.MemBaseValue:lower_cmat_direct_access(input)
  return input.values:cmat_fragment_lookup(self.value)
:lower_cmat_direct_access(input)
end
function Mem.MemBaseArgument:lower_cmat_direct_access(input)
  return input.values:cmat_fragment_lookup(self.value)
:lower_cmat_direct_access(input)
end
function Mem.MemBaseLocal:lower_cmat_direct_access(input)
  return Lower.LowerCMatAccessSourceRejected(access_issue(
    input.access, "local memory bases are not yet admitted to CMat fragments"))
end
function Mem.MemBaseGlobal:lower_cmat_direct_access(input)
  return Lower.LowerCMatAccessSourceRejected(access_issue(
    input.access, "global memory bases require an explicit C backend projection"))
end
function Mem.MemBaseData:lower_cmat_direct_access(input)
  return Lower.LowerCMatAccessSourceRejected(access_issue(
    input.access, "data memory bases require an explicit C backend projection"))
end
function Mem.MemBaseProjection:lower_cmat_direct_access(input)
  return Lower.LowerCMatAccessSourceRejected(access_issue(
    input.access, "projected memory bases require an explicit offset projection"))
end
function Mem.MemBaseUnknown:lower_cmat_direct_access(input)
  return Lower.LowerCMatAccessSourceRejected(access_issue(
    input.access, "unknown memory base: " .. self.reason))
end
function Lower.LowerAddressPlanProjection:lower_cmat_lane_lookup(lane)
  local entries = {}
  for i = 1, #self.plans do
    local plan = self.plans[i]
    for j = 1, #plan.lanes do
      local use = plan.lanes[j]
      if use.lane == lane then
        if use.address ~= plan.address then
          return Lower.LowerAddressByLaneInvalidRelation(
            lane, "lane use names a different address than its owning plan")
        end
        entries[#entries + 1] = Lower.LowerAddressByLaneEntry(
          lane, plan, use)
      end
    end
  end
  if #entries == 0 then return Lower.LowerAddressByLaneMissing(lane) end
  if #entries > 1 then
    return Lower.LowerAddressByLaneAmbiguous(lane, #entries)
  end
  return Lower.LowerAddressByLaneFound(entries[1])
end
function Lower.LowerAddressByLaneFound:lower_cmat_access_source(input)
  return Lower.LowerCMatAccessSourceRejected(access_issue(
    input.fact.binding.access,
    "address-projected lanes require relative-index and assembly semantics"))
end
function Lower.LowerAddressByLaneAmbiguous:lower_cmat_access_source(input)
  return Lower.LowerCMatAccessSourceRejected(access_issue(
    input.fact.binding.access, "multiple address relations serve the lane"))
end
function Lower.LowerAddressByLaneInvalidRelation:lower_cmat_access_source(input)
  return Lower.LowerCMatAccessSourceRejected(access_issue(
    input.fact.binding.access, "invalid address relation: " .. self.reason))
end
function Lower.LowerAddressByLaneMissing:lower_cmat_access_source(input)
  local expected = C.CBackendDataPtr(
    input.fact.binding.ty:code_to_c_backend_type())
  return input.fact.provenance.lane.base:lower_cmat_direct_access(
    Lower.LowerCMatDirectAccessInput(
      input.fact.binding.access, input.values, expected))
end
function Lower.LowerCMatAccessSourceInput:lower_cmat_access_source()
  return self.addresses:lower_cmat_lane_lookup(self.fact.provenance.lane.id)
:lower_cmat_access_source(self)
end
function Lower.LowerCMatAccessSourceReady:lower_cmat_finish_access(input)
  local entries = copy(input.collection.entries)
  entries[#entries + 1] = CMat.CMatCFragmentAccessBindingEntry(
    input.fact.binding.access, input.fact.provenance.lane.id,
    input.fact.mem_access, self.source, input.fact.elem_size,
    input.fact.stride, input.fact.alignment)
  return Lower.LowerCMatAccessBuildReady(
    Lower.LowerCMatAccessCollection(entries))
end
function Lower.LowerCMatAccessSourceRejected:lower_cmat_finish_access(_input)
  return Lower.LowerCMatAccessBuildRejected(self.issue)
end
function Lower.LowerCMatAccessBuildRejected:lower_cmat_continue_accesses(_input)
  return Lower.LowerCMatAccessesRejected(self.issue)
end
function Lower.LowerCMatAccessBuildRequest:lower_validate_access_relation()
  for i = 1, #self.bindings do
    local matches = 0
    for j = 1, #self.provenance.entries do
      if self.provenance.entries[j].access == self.bindings[i].source then
        matches = matches + 1
      end
    end
    if matches ~= 1 then
      return Lower.LowerCMatAccessRelationRejected(access_issue(
        self.bindings[i].access,
        "access binding does not have one exact provenance relation"))
    end
  end
  for i = 1, #self.provenance.entries do
    local matches = 0
    for j = 1, #self.bindings do
      if self.bindings[j].source == self.provenance.entries[i].access then
        matches = matches + 1
      end
    end
    if matches ~= 1 then
      return Lower.LowerCMatAccessRelationRejected(access_issue(
        Stencil.StencilAccessRef(self.provenance.entries[i].access.name),
        "access provenance does not have one exact materialized binding"))
    end
  end
  return Lower.LowerCMatAccessRelationValid
end
function Lower.LowerCMatAccessRelationValid:lower_cmat_build_accesses(request)
  return Lower.LowerCMatAccessBuildReady(
    Lower.LowerCMatAccessCollection({}))
:lower_cmat_continue_accesses(Lower.LowerCMatAccessFoldInput(request, 1))
end
function Lower.LowerCMatAccessRelationRejected:lower_cmat_build_accesses(_request)
  return Lower.LowerCMatAccessesRejected(self.issue)
end
function Mem.MemDerefBytesUnavailable:lower_cmat_admit_access_pattern(evidence)
  return Lower.LowerCMatAccessPatternRejected(access_issue(
    evidence.binding.access, "backend dereference width is unavailable"))
end
function Mem.MemDerefBytesKnown:lower_cmat_admit_access_pattern(evidence)
  if self.bytes ~= evidence.elem_size then
    return Lower.LowerCMatAccessPatternRejected(access_issue(
      evidence.binding.access,
      "backend dereference width disagrees with the element size"))
  end
  return evidence.provenance.lane.pattern:lower_cmat_admit_access_pattern(evidence)
end
function Mem.MemAccessScalar:lower_cmat_admit_access_pattern(evidence)
  if evidence.stride ~= evidence.elem_size then
    return Lower.LowerCMatAccessPatternRejected(access_issue(
      evidence.binding.access, "scalar access requires unit element stride"))
  end
  return Lower.LowerCMatAccessPatternAdmitted
end
function Mem.MemAccessContiguous:lower_cmat_admit_access_pattern(evidence)
  if evidence.stride ~= evidence.elem_size then
    return Lower.LowerCMatAccessPatternRejected(access_issue(
      evidence.binding.access, "contiguous access has invalid element stride"))
  end
  return Lower.LowerCMatAccessPatternAdmitted
end
function Mem.MemAccessStrided:lower_cmat_admit_access_pattern(evidence)
  if self.stride_elems <= 0
      or evidence.stride ~= self.stride_elems * evidence.elem_size then
    return Lower.LowerCMatAccessPatternRejected(access_issue(
      evidence.binding.access, "strided access disagrees with memory evidence"))
  end
  return Lower.LowerCMatAccessPatternAdmitted
end
function Mem.MemAccessGather:lower_cmat_admit_access_pattern(evidence)
  return Lower.LowerCMatAccessPatternRejected(access_issue(
    evidence.binding.access, "gather access is outside scalar direct scope"))
end
function Mem.MemAccessScatter:lower_cmat_admit_access_pattern(evidence)
  return Lower.LowerCMatAccessPatternRejected(access_issue(
    evidence.binding.access, "scatter access is outside scalar direct scope"))
end
function Mem.MemAccessUnknown:lower_cmat_admit_access_pattern(evidence)
  return Lower.LowerCMatAccessPatternRejected(access_issue(
    evidence.binding.access, "unknown access pattern is not admissible"))
end
function Lower.LowerCMatAccessPatternRejected:lower_cmat_continue_pattern(_evidence)
  return Lower.LowerCMatAccessesRejected(self.issue)
end
function Lower.LowerCMatAccessPatternAdmitted:lower_cmat_continue_pattern(evidence)
  local fact = Lower.LowerCMatAccessFact(
    evidence.binding, evidence.provenance, evidence.mem_access,
    evidence.backend.alignment, evidence.elem_size, evidence.stride)
  local source_input = Lower.LowerCMatAccessSourceInput(
    fact, evidence.request.values, evidence.request.addresses)
  return source_input:lower_cmat_access_source()
:lower_cmat_finish_access(Lower.LowerCMatAccessFinishInput(
    fact, evidence.collection))
:lower_cmat_continue_accesses(Lower.LowerCMatAccessFoldInput(
    evidence.request, evidence.next_index))
end
function Lower.LowerCMatAccessBuildReady:lower_cmat_continue_accesses(input)
  local request = input.request
  if input.index > #request.bindings then
    return Lower.LowerCMatAccessesReady(
      CMat.CMatCFragmentAccessBindingProjection(self.collection.entries))
  end
  local binding = request.bindings[input.index]
  local provenance = {}
  for i = 1, #request.provenance.entries do
    local entry = request.provenance.entries[i]
    if entry.access == binding.source then provenance[#provenance + 1] = entry end
  end
  local lane = provenance[1].lane
  if lane.elem_ty ~= binding.ty then
    return Lower.LowerCMatAccessesRejected(access_issue(
      binding.access, "lane element type disagrees with materialized access"))
  end
  if #lane.accesses ~= 1 then
    return Lower.LowerCMatAccessesRejected(access_issue(
      binding.access, "initial CMat access requires one exact lane MemAccessId"))
  end
  if #lane.backend_info ~= 1
      or lane.backend_info[1].access ~= lane.accesses[1] then
    return Lower.LowerCMatAccessesRejected(access_issue(
      binding.access, "lane requires one exact backend access fact"))
  end
  local elem_size = binding.ty:code_to_c_backend_type()
:cmat_fragment_size(request.target)
  local stride = binding.layout:cmat_fragment_direct_stride()
  if elem_size <= 0 or stride <= 0 or stride % elem_size ~= 0 then
    return Lower.LowerCMatAccessesRejected(access_issue(
      binding.access, "access layout is not direct scalar memory"))
  end
  local evidence = Lower.LowerCMatAccessEvidence(
    request, binding, provenance[1], lane.accesses[1], lane.backend_info[1],
    elem_size, stride, self.collection, input.index + 1)
  return lane.backend_info[1].deref_bytes
:lower_cmat_admit_access_pattern(evidence)
:lower_cmat_continue_pattern(evidence)
end
function Lower.LowerCMatAccessBuildRequest:lower_cmat_accesses()
  return self:lower_validate_access_relation():lower_cmat_build_accesses(self)
end
function Lower.LowerCMatAccessEnvironmentInput:lower_cmat_accesses()
  return Lower.LowerCMatAccessBuildRequest(
    self.materialization.kernel.accesses,
    self.materialization.provenance.accesses,
    self.values, self.addresses, self.target):lower_cmat_accesses()
end

return Lower
