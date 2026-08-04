-- Canonical LOWER semantic-fragment preparation and typed coverage resolution.
require("lalin.schema")
require("lalin.impl.stencil_kernel")
require("lalin.impl.lower_emit_c.materialize")
require("lalin.impl.lower_emit_c.coordinates")
require("lalin.impl.lower_emit_c.code_to_c")
require("lalin.impl.lower_emit_c.fragment")
require("lalin.impl.lower_emit_c.address_plan")

local Lower = require("lalin.schema.lower")
local Stencil = require("lalin.schema.stencil")
local CMat = require("lalin.schema.c_materialize")
local C = require("lalin.schema.c")
local Code = require("lalin.schema.code")
local Mem = require("lalin.schema.mem")
local Graph = require("lalin.schema.graph")
local Kernel = require("lalin.schema.kernel")

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

function CMat.CMatMaterializedKernelFragment:lower_cmat_state(input)
  local spine = self.kernel:cmat_memory_use_spine()
  local coordinates = spine:lower_coordinates(Lower.LowerCMatCoordinateInput(
    self.provenance.iteration, self.provenance.domain,
    self.provenance.accesses, input.memory))
  return Lower.LowerKernelCMatReady(
    input.projection, self, coordinates)
end
function CMat.CMatRejectedKernelFragment:lower_cmat_state(input)
  return Lower.LowerKernelCMatReady(
    input.projection, self, Lower.LowerCMatCoordinatesRejected({
      Lower.LowerCMatCoordinateMaterializationUnavailable(self),
    }))
end
function Stencil.StencilKernelProjected:lower_cmat_state(input)
  return self.projection:cmat_materialize_kernel(
    CMat.CMatKernelMaterializationInput(CMat.CMatKernelId(input.kernel.text)))
:lower_cmat_state(Lower.LowerKernelCMatMaterializationInput(
  self.projection, input.memory))
end

function Stencil.StencilKernelProjectionRejected:lower_cmat_state(_input)
  return Lower.LowerKernelCMatRejected(self.rejects)
end

function Stencil.StencilKernelModuleProjectedEntry:lower_cmat_entries(input)
  return Lower.LowerKernelCMatProjection({
    Lower.LowerKernelCMatEntry(
      self.kernel, self.result:lower_cmat_state(
        Lower.LowerKernelCMatStateInput(
          self.kernel, input.kernels.mem:project_accesses()))) })
end
function Stencil.StencilKernelModuleRejectedEntry:lower_cmat_entries(_input)
  return Lower.LowerKernelCMatProjection({})
end

function Stencil.StencilKernelModuleProjected:lower_cmat_prepare(input)
  local entries = {}
  for i = 1, #self.projection.entries do
    local additions = self.projection.entries[i]:lower_cmat_entries(input)
    for j = 1, #additions.entries do entries[#entries + 1] = additions.entries[j] end
  end
  return Lower.LowerKernelCMatPrepared(Lower.LowerKernelCMatProjection(entries))
end

function Stencil.StencilKernelModuleProjectionRejected:lower_cmat_prepare(_input)
  return Lower.LowerKernelCMatPreparationRejected(self.expected, self.actual)
end

function Stencil.StencilKernelModuleFacetMismatch:lower_cmat_prepare(_input)
  return Lower.LowerKernelCMatPreparationFacetRejected(self.reason)
end

function Lower.LowerKernelCMatPreparationInput:lower_prepare_cmat()
  return Stencil.StencilKernelModuleProjectionInput(
    self.module, self.graph, self.kernels.flow, self.semantics,
    self.kernels, self.schedules, self.compiler):project_kernel_module()
  :lower_cmat_prepare(self)
end
function Lower.LowerKernelCMatPrepared:lower_c_prepared_module(input)
  return input.plan:lower_c_module(Lower.LowerCModuleInput(
    input.spine, input.plan, self.projection))
end
function Lower.LowerKernelCMatPreparationRejected:lower_c_prepared_module(_input)
  return Lower.LowerCModuleRejected({
    Lower.LowerIssuePreparationModuleMismatch(self.expected, self.actual),
  })
end
function Lower.LowerKernelCMatPreparationFacetRejected:lower_c_prepared_module(_input)
  return Lower.LowerCModuleRejected({
    Lower.LowerIssuePreparationFacetRejected(self.reason),
  })
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
local function contains(items, value)
  for i = 1, #items do if items[i] == value then return true end end
  return false
end
local function find_dominators(entries, block)
  local found = {}
  for i = 1, #entries do
    if entries[i].block == block then found[#found + 1] = entries[i] end
  end
  return found
end
function Code.CodeTermJump:lower_c_incoming_edges(origin)
  return Lower.LowerCIncomingEdgeProjection({
    Lower.LowerCIncomingEdgeArguments(
      origin, Lower.LowerCTermEdgeOnly, self.dest, self.args) })
end
function Code.CodeTermBranch:lower_c_incoming_edges(origin)
  return Lower.LowerCIncomingEdgeProjection({
    Lower.LowerCIncomingEdgeArguments(
      origin, Lower.LowerCTermEdgeThen, self.then_dest, self.then_args),
    Lower.LowerCIncomingEdgeArguments(
      origin, Lower.LowerCTermEdgeElse, self.else_dest, self.else_args),
  })
end
local function switch_edges(origin, cases, default_dest, default_args)
  local entries = {}
  for i = 1, #cases do
    entries[#entries + 1] = Lower.LowerCIncomingEdgeArguments(
      origin, Lower.LowerCTermEdgeCase(i), cases[i].dest, cases[i].args)
  end
  entries[#entries + 1] = Lower.LowerCIncomingEdgeArguments(
    origin, Lower.LowerCTermEdgeDefault, default_dest, default_args)
  return Lower.LowerCIncomingEdgeProjection(entries)
end
function Code.CodeTermSwitch:lower_c_incoming_edges(origin)
  return switch_edges(origin, self.cases, self.default_dest, self.default_args)
end
function Code.CodeTermVariantSwitch:lower_c_incoming_edges(origin)
  return switch_edges(origin, self.cases, self.default_dest, self.default_args)
end
function Code.CodeTermReturn:lower_c_incoming_edges(_origin)
  return Lower.LowerCIncomingEdgeProjection({})
end
function Code.CodeTermTrap:lower_c_incoming_edges(_origin)
  return Lower.LowerCIncomingEdgeProjection({})
end
function Code.CodeTermUnreachable:lower_c_incoming_edges(_origin)
  return Lower.LowerCIncomingEdgeProjection({})
end
function Code.CodeFunc:lower_c_incoming_edges()
  local entries = {}
  for i = 1, #self.blocks do
    local block = self.blocks[i]
    local origin = Lower.LowerCTermEdgeOrigin(block.id, block.term.id)
    local additions = block.term.op:lower_c_incoming_edges(origin)
    for j = 1, #additions.entries do
      entries[#entries + 1] = additions.entries[j]
    end
  end
  return Lower.LowerCIncomingEdgeProjection(entries)
end
function Lower.LowerCDominanceConstructionInput:lower_c_dominance()
  if self.graph.func ~= self.code_func.id then
    return Lower.LowerCDominanceRejected(Lower.LowerIssueDominanceRejected(
      self.code_func.id, "function graph identity mismatch"))
  end
  local blocks = {}
  for i = 1, #self.code_func.blocks do
    local id = self.code_func.blocks[i].id
    if contains(blocks, id) then
      return Lower.LowerCDominanceRejected(Lower.LowerIssueDominanceRejected(
        self.code_func.id, "duplicate block identity"))
    end
    blocks[#blocks + 1] = id
  end
  if not contains(blocks, self.code_func.entry) then
    return Lower.LowerCDominanceRejected(Lower.LowerIssueDominanceRejected(
      self.code_func.id, "function entry block is absent"))
  end
  local edges = self.code_func:lower_c_incoming_edges().entries
  for i = 1, #self.graph.edges do
    local edge = self.graph.edges[i]
    if edge.from.func ~= self.code_func.id or edge.to.func ~= self.code_func.id
        or not contains(blocks, edge.from.block)
        or not contains(blocks, edge.to.block) then
      return Lower.LowerCDominanceRejected(Lower.LowerIssueDominanceRejected(
        self.code_func.id, "graph edge escapes the exact function block set"))
    end
  end
  for i = 1, #edges do
    if not contains(blocks, edges[i].origin.source)
        or not contains(blocks, edges[i].destination) then
      return Lower.LowerCDominanceRejected(Lower.LowerIssueDominanceRejected(
        self.code_func.id, "terminator edge names an absent block"))
    end
    local matches = 0
    local expected = 0
    for j = 1, #self.graph.edges do
      local edge = self.graph.edges[j]
      if edge.from.block == edges[i].origin.source
          and edge.to.block == edges[i].destination then
        matches = matches + 1
      end
    end
    for j = 1, #edges do
      if edges[j].origin.source == edges[i].origin.source
          and edges[j].destination == edges[i].destination then
        expected = expected + 1
      end
    end
    if matches ~= expected then
      return Lower.LowerCDominanceRejected(Lower.LowerIssueDominanceRejected(
        self.code_func.id, "graph omits or duplicates a terminator edge"))
    end
  end
  for i = 1, #self.graph.edges do
    local matches = 0
    for j = 1, #edges do
      if self.graph.edges[i].from.block == edges[j].origin.source
          and self.graph.edges[i].to.block == edges[j].destination then
        matches = matches + 1
      end
    end
    if matches == 0 then
      return Lower.LowerCDominanceRejected(Lower.LowerIssueDominanceRejected(
        self.code_func.id, "graph contains a non-terminator edge"))
    end
  end
  local reachable = { self.code_func.entry }
  for _ = 1, #blocks do
    local additions = {}
    for i = 1, #edges do
      local edge = edges[i]
      if contains(reachable, edge.origin.source)
          and not contains(reachable, edge.destination)
          and not contains(additions, edge.destination) then
        additions[#additions + 1] = edge.destination
      end
    end
    if #additions == 0 then break end
    for i = 1, #blocks do
      if contains(additions, blocks[i]) then reachable[#reachable + 1] = blocks[i] end
    end
  end
  local entries = {}
  for i = 1, #reachable do
    local dominators
    if reachable[i] == self.code_func.entry then dominators = { reachable[i] }
    else dominators = copy(reachable) end
    entries[i] = Lower.LowerCDominatorEntry(reachable[i], dominators)
  end
  local limit = #reachable * #reachable + 1
  for _ = 1, limit do
    local next_entries = {}
    local changes = 0
    for i = 1, #reachable do
      local block = reachable[i]
      local dominators
      if block == self.code_func.entry then
        dominators = { block }
      else
        local predecessors = {}
        for j = 1, #edges do
          local edge = edges[j]
          if edge.destination == block and contains(reachable, edge.origin.source)
              and not contains(predecessors, edge.origin.source) then
            predecessors[#predecessors + 1] = edge.origin.source
          end
        end
        dominators = { block }
        for j = 1, #reachable do
          local candidate = reachable[j]
          local in_every = #predecessors > 0
          for k = 1, #predecessors do
            local predecessor = find_dominators(entries, predecessors[k])
            if #predecessor ~= 1
                or not contains(predecessor[1].dominators, candidate) then
              in_every = false
            end
          end
          if in_every and candidate ~= block then
            dominators[#dominators + 1] = candidate
          end
        end
      end
      local previous = find_dominators(entries, block)
      if #previous ~= 1 or #previous[1].dominators ~= #dominators then
        changes = changes + 1
      else
        for j = 1, #dominators do
          if not contains(previous[1].dominators, dominators[j]) then
            changes = changes + 1
          end
        end
      end
      next_entries[i] = Lower.LowerCDominatorEntry(block, dominators)
    end
    entries = next_entries
    if changes == 0 then
      return Lower.LowerCDominanceReady(
        Lower.LowerCDominanceProjection(
          self.code_func, self.graph, entries))
    end
  end
  return Lower.LowerCDominanceRejected(Lower.LowerIssueDominanceRejected(
    self.code_func.id, "dominance fixed point did not converge"))
end
function Lower.LowerCDominanceProjection:lower_c_dominance_lookup(query)
  local blocks = find_dominators(self.entries, query.block)
  if #blocks ~= 1 then
    return Lower.LowerCDominanceMissing(
      "queried block is absent or ambiguous in dominance projection")
  end
  if contains(blocks[1].dominators, query.dominator) then
    return Lower.LowerCDominates
  end
  return Lower.LowerCDoesNotDominate
end
function Lower.LowerCFunctionParamSite:lower_c_resolve_incoming(input)
  return Lower.LowerCIncomingArgumentResolved(
    Lower.LowerCIncomingBlockArgument(
      input.edge, input.ordinal, input.value, self,
      Lower.LowerCSourceFunctionParam))
end
function Lower.LowerCBlockParamSite:lower_c_resolve_incoming(input)
  if self.block == input.edge.origin.source then
    return Lower.LowerCIncomingArgumentResolved(Lower.LowerCIncomingBlockArgument(
      input.edge, input.ordinal, input.value, self, Lower.LowerCSourceDominates(self.block, input.edge.origin.source)))
  end
  local continuation = Lower.LowerCDominatingIncomingArgumentInput(input, self.block)
  return input.dominance:lower_c_dominance_lookup(
    Lower.LowerCDominanceQuery(self.block, input.edge.origin.source))
:lower_c_resolve_incoming(continuation)
end
function Lower.LowerCInstructionSite:lower_c_resolve_incoming(input)
  if self.block == input.edge.origin.source then
    return Lower.LowerCIncomingArgumentResolved(Lower.LowerCIncomingBlockArgument(
      input.edge, input.ordinal, input.value, self, Lower.LowerCSourceDominates(self.block, input.edge.origin.source)))
  end
  local continuation = Lower.LowerCDominatingIncomingArgumentInput(input, self.block)
  return input.dominance:lower_c_dominance_lookup(
    Lower.LowerCDominanceQuery(self.block, input.edge.origin.source))
:lower_c_resolve_incoming(continuation)
end
function Lower.LowerCDominates:lower_c_resolve_incoming(input)
  return Lower.LowerCIncomingArgumentResolved(
    Lower.LowerCIncomingBlockArgument(
      input.request.edge, input.request.ordinal, input.request.value,
      input.request.definition, Lower.LowerCSourceDominates(
        input.dominator, input.request.edge.origin.source)))
end
function Lower.LowerCDoesNotDominate:lower_c_resolve_incoming(input)
  return Lower.LowerCIncomingArgumentRejected(
    Lower.LowerIssueEntryAdapterRejected(
      input.request.func, input.request.replacement,
      "incoming argument definition does not dominate its source edge"))
end
function Lower.LowerCDominanceMissing:lower_c_resolve_incoming(_input)
  return Lower.LowerCIncomingArgumentUnreachable
end
function Lower.LowerCIncomingArgumentResolved:lower_c_collect_incoming(collection)
  local entries = copy(collection.entries)
  entries[#entries + 1] = self.argument
  return Lower.LowerCIncomingArgumentsCollecting(entries)
end
function Lower.LowerCIncomingArgumentUnreachable:lower_c_collect_incoming(collection)
  return collection
end
function Lower.LowerCIncomingArgumentRejected:lower_c_collect_incoming(_collection)
  return Lower.LowerCIncomingArgumentsRejected(self.issue)
end
function Lower.LowerCIncomingArgumentsCollecting:lower_c_add_incoming(resolution)
  return resolution:lower_c_collect_incoming(self)
end
function Lower.LowerCIncomingArgumentsRejected:lower_c_add_incoming(_resolution)
  return self
end
function Lower.LowerCIncomingArgumentsRejected:lower_c_finish_adapters(_input)
  return Lower.LowerCReplacementEntryAdapterRejected(self.issue)
end
function Lower.LowerCIncomingArgumentsCollecting:lower_c_finish_adapters(input)
  local adapters = {}
  for i = 1, #input.parameters do
    local incoming = {}
    for j = 1, #self.entries do
      if self.entries[j].ordinal == input.parameters[i].ordinal then
        incoming[#incoming + 1] = self.entries[j]
      end
    end
    adapters[#adapters + 1] = Lower.LowerCReplacementParamAdapter(
      input.parameters[i], incoming)
  end
  return Lower.LowerCReplacementEntryAdapterReady(
    Lower.LowerCReplacementEntryProjection(
      input.request.code_func, input.request.replacement, adapters))
end
function Lower.LowerCReplacementEntryAdapterInput:lower_c_entry_adapters()
  if self.baseline.source ~= self.code_func
      or self.dominance.source ~= self.code_func then
    return Lower.LowerCReplacementEntryAdapterRejected(
      Lower.LowerIssueEntryAdapterRejected(
        self.code_func.id, self.replacement,
        "baseline function identity mismatch"))
  end
  local blocks = {}
  for i = 1, #self.code_func.blocks do
    if self.code_func.blocks[i].id == self.replacement then
      blocks[#blocks + 1] = self.code_func.blocks[i]
    end
  end
  if #blocks ~= 1 then
    return Lower.LowerCReplacementEntryAdapterRejected(
      Lower.LowerIssueEntryAdapterRejected(
        self.code_func.id, self.replacement,
        "replacement source block is absent or ambiguous"))
  end
  local incoming_edges = {}
  local edges = self.code_func:lower_c_incoming_edges().entries
  for i = 1, #edges do
    if edges[i].destination == self.replacement then
      incoming_edges[#incoming_edges + 1] = edges[i]
    end
  end
  if #blocks[1].params > 0 and self.replacement == self.code_func.entry then
    return Lower.LowerCReplacementEntryAdapterRejected(
      Lower.LowerIssueEntryAdapterRejected(
        self.code_func.id, self.replacement,
        "parameterized function-entry replacement lacks an initializer"))
  end
  for i = 1, #incoming_edges do
    if #incoming_edges[i].args ~= #blocks[1].params then
      return Lower.LowerCReplacementEntryAdapterRejected(
        Lower.LowerIssueEntryAdapterRejected(
          self.code_func.id, self.replacement,
          "incoming edge argument count disagrees with replacement parameters"))
    end
  end
  local baseline_parameters = {}
  for ordinal = 1, #blocks[1].params do
    local parameter = blocks[1].params[ordinal]
    local baseline_params = {}
    for i = 1, #self.baseline.block_params.entries do
      local entry = self.baseline.block_params.entries[i]
      if entry.block == self.replacement and entry.ordinal == ordinal
          and entry.value.value == parameter.value then
        baseline_params[#baseline_params + 1] = entry
      end
    end
    if #baseline_params ~= 1
        or baseline_params[1].value.code_ty ~= parameter.ty
        or baseline_params[1].parameter.ty ~=
          parameter.ty:code_to_c_backend_type() then
      return Lower.LowerCReplacementEntryAdapterRejected(
        Lower.LowerIssueEntryAdapterRejected(
          self.code_func.id, self.replacement,
          "replacement parameter lacks one exact baseline C parameter"))
    end
    baseline_parameters[#baseline_parameters + 1] = baseline_params[1]
  end
  local collection = Lower.LowerCIncomingArgumentsCollecting({})
  for i = 1, #incoming_edges do
    for ordinal = 1, #blocks[1].params do
      local parameter = blocks[1].params[ordinal]
      local values = {}
      for j = 1, #self.baseline.value_types.entries do
        if self.baseline.value_types.entries[j].value ==
            incoming_edges[i].args[ordinal] then
          values[#values + 1] = self.baseline.value_types.entries[j]
        end
      end
      local sites = {}
      if #values == 1 then
        for j = 1, #self.baseline.value_sites.entries do
          if self.baseline.value_sites.entries[j].value == values[1].value then
            sites[#sites + 1] = self.baseline.value_sites.entries[j]
          end
        end
      end
      if #values ~= 1 or #sites ~= 1 or values[1].code_ty ~= parameter.ty then
        return Lower.LowerCReplacementEntryAdapterRejected(
          Lower.LowerIssueEntryAdapterRejected(
            self.code_func.id, self.replacement,
            "incoming argument lacks one exact typed definition site"))
      end
      local request = Lower.LowerCIncomingArgumentInput(
        self.code_func.id, self.replacement, incoming_edges[i],
        ordinal, values[1], sites[1].site, self.dominance)
      collection = collection:lower_c_add_incoming(
        sites[1].site:lower_c_resolve_incoming(request))
    end
  end
  return collection:lower_c_finish_adapters(
    Lower.LowerCAdapterFinishInput(self, blocks[1], baseline_parameters))
end
function Lower.LowerCFunctionParamSite:lower_cmat_value_contribution(input)
  return Lower.LowerCValueAvailable(Lower.LowerCEntryValueBinding(
    input.value, Lower.LowerCEntryFunctionParam))
end
function Lower.LowerCBlockParamSite:lower_c_entry_value_source(candidate)
  if self.block == candidate.replacement then
    local adapters = {}
    for i = 1, #candidate.adapters.entries do
      if candidate.adapters.entries[i].parameter.value.value ==
          candidate.value.value then
        adapters[#adapters + 1] = candidate.adapters.entries[i]
      end
    end
    if #adapters ~= 1 then return Lower.LowerCValueUnavailable end
    return Lower.LowerCValueAvailable(Lower.LowerCEntryValueBinding(
      candidate.value, Lower.LowerCEntryReplacementBlockParam(adapters[1])))
  end
  return Lower.LowerCValueAvailable(Lower.LowerCEntryValueBinding(
    candidate.value, Lower.LowerCEntryDominatingBlockParam(self.block)))
end
function Lower.LowerCInstructionSite:lower_c_entry_value_source(candidate)
  if self.block == candidate.replacement then return Lower.LowerCValueUnavailable end
  return Lower.LowerCValueAvailable(Lower.LowerCEntryValueBinding(
    candidate.value, Lower.LowerCEntryDominatingInstruction(self.block, self.inst)))
end
function Lower.LowerCDominates:lower_cmat_value_contribution(candidate)
  return candidate.site:lower_c_entry_value_source(candidate)
end
function Lower.LowerCDoesNotDominate:lower_cmat_value_contribution(_candidate)
  return Lower.LowerCValueUnavailable
end
function Lower.LowerCDominanceMissing:lower_cmat_value_contribution(_candidate)
  return Lower.LowerCValueUnavailable
end
function Lower.LowerCBlockParamSite:lower_cmat_value_contribution(input)
  local candidate = Lower.LowerCEntryAvailabilityCandidate(
    input.value, self, input.coverage.replacement_source, input.adapters)
  return input.dominance:lower_c_dominance_lookup(Lower.LowerCDominanceQuery(
    self.block, input.coverage.replacement_source))
:lower_cmat_value_contribution(candidate)
end
function Lower.LowerCInstructionSite:lower_cmat_value_contribution(input)
  local candidate = Lower.LowerCEntryAvailabilityCandidate(
    input.value, self, input.coverage.replacement_source, input.adapters)
  return input.dominance:lower_c_dominance_lookup(Lower.LowerCDominanceQuery(
    self.block, input.coverage.replacement_source))
:lower_cmat_value_contribution(candidate)
end
function Lower.LowerCValueAvailable:lower_cmat_collect_value(collection)
  local entries = copy(collection.entries)
  local availability = copy(collection.availability)
  entries[#entries + 1] = CMat.CMatCExternalValueBindingEntry(
    self.binding.value.value, self.binding.value.c_local)
  availability[#availability + 1] = self.binding
  return Lower.LowerCMatValueCollection(entries, availability)
end
function Lower.LowerCValueUnavailable:lower_cmat_collect_value(collection)
  return collection
end
function Lower.LowerCMatValueEnvironmentInput:lower_cmat_values()
  if self.code_func.id ~= self.coverage.func
      or self.baseline.source ~= self.code_func
      or self.dominance.source ~= self.code_func
      or self.adapters.source ~= self.code_func
      or self.adapters.block ~= self.coverage.replacement_source then
    return Lower.LowerCMatValuesRejected(
      Lower.LowerIssueValueEnvironmentRejected(
        self.coverage.func,
        "value environment function or replacement identity mismatch"))
  end
  local replacement = find_dominators(
    self.dominance.entries, self.coverage.replacement_source)
  if #replacement ~= 1 then
    return Lower.LowerCMatValuesRejected(
      Lower.LowerIssueDominanceRejected(
        self.coverage.func,
        "replacement entry is absent or ambiguous in dominance projection"))
  end
  local replacement_params = {}
  for i = 1, #self.baseline.block_params.entries do
    if self.baseline.block_params.entries[i].block ==
        self.coverage.replacement_source then
      replacement_params[#replacement_params + 1] =
        self.baseline.block_params.entries[i]
    end
  end
  if #replacement_params ~= #self.adapters.entries then
    return Lower.LowerCMatValuesRejected(
      Lower.LowerIssueValueEnvironmentRejected(
        self.coverage.func,
        "replacement adapter cardinality disagrees with baseline parameters"))
  end
  for i = 1, #replacement_params do
    local matches = 0
    for j = 1, #self.adapters.entries do
      if self.adapters.entries[j].parameter == replacement_params[i] then
        matches = matches + 1
      end
    end
    if matches ~= 1 then
      return Lower.LowerCMatValuesRejected(
        Lower.LowerIssueValueUnavailable(
          replacement_params[i].value.value,
          "replacement parameter adapter is absent or ambiguous"))
    end
  end
  for i = 1, #self.adapters.entries do
    local matches = 0
    for j = 1, #replacement_params do
      if self.adapters.entries[i].parameter == replacement_params[j] then
        matches = matches + 1
      end
    end
    if matches ~= 1 then
      return Lower.LowerCMatValuesRejected(
        Lower.LowerIssueValueEnvironmentRejected(
          self.coverage.func,
          "replacement adapter does not belong to the baseline block"))
    end
  end
  local collection = Lower.LowerCMatValueCollection({}, {})
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
      Lower.LowerCValueAvailabilityInput(
        self.coverage, value, self.dominance, self.adapters))
:lower_cmat_collect_value(collection)
  end
  return Lower.LowerCMatValuesReady(
    CMat.CMatCExternalValueBindingProjection(collection.entries),
    Lower.LowerCEntryValueProjection(collection.availability))
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

-- LowerCMatEnvironmentInput → immutable composition of the three CMat
-- environments (values, accesses, exits) into one fragment request.
-- The chain threads the named environment input and each computed typed
-- result; no procedural state product is introduced.
function Lower.LowerCMatEnvironmentInput:lower_cmat_environment()
  if self.coverage.func ~= self.code_func.id
      or self.baseline.source ~= self.code_func
      or self.dominance.source ~= self.code_func
      or self.adapters.source ~= self.code_func
      or self.adapters.block ~= self.coverage.replacement_source then
    return Lower.LowerCMatEnvironmentRejected(
      Lower.LowerIssueValueEnvironmentRejected(
        self.coverage.func,
        "CMat environment function or replacement identity mismatch"))
  end
  return self.fragment.strategy:lower_cmat_environment_strategy(self)
end

function Lower.LowerStrategyKernel:lower_cmat_environment_strategy(input)
  if self.kernel ~= input.materialization.provenance.kernel.id then
    return Lower.LowerCMatEnvironmentRejected(
      Lower.LowerIssueFragmentRejected(
        input.fragment.id,
        "CMat materialization provenance kernel disagrees with fragment strategy"))
  end
  return input:lower_cmat_environment_chain()
end
function Lower.LowerStrategyCode:lower_cmat_environment_strategy(input)
  return Lower.LowerCMatEnvironmentRejected(
    Lower.LowerIssueFragmentRejected(
      input.fragment.id, "code strategy fragment has no CMat materialization"))
end
function Lower.LowerStrategyClosedForm:lower_cmat_environment_strategy(input)
  return Lower.LowerCMatEnvironmentRejected(
    Lower.LowerIssueFragmentRejected(
      input.fragment.id, "closed-form fragment has no CMat materialization"))
end

function Lower.LowerCMatEnvironmentInput:lower_cmat_environment_chain()
  local values = Lower.LowerCMatValueEnvironmentInput(
    self.code_func, self.baseline, self.coverage, self.dominance, self.adapters)
    :lower_cmat_values()
  return values:lower_cmat_compose_accesses(self)
end

function Lower.LowerCMatValuesReady:lower_cmat_compose_accesses(input)
  local accesses = Lower.LowerCMatAccessEnvironmentInput(
    input.materialization, self.values, input.target)
    :lower_cmat_accesses()
  return accesses:lower_cmat_compose_exits(input, self)
end
function Lower.LowerCMatValuesRejected:lower_cmat_compose_accesses(_input)
  return Lower.LowerCMatEnvironmentRejected(self.issue)
end

function Lower.LowerCMatAccessesReady:lower_cmat_compose_exits(input, values)
  local address_input = Lower.LowerCMatAddressEnvironmentInput(input, values, self)
  return input.coordinates:materialize_c_address_plan(
    CMat.CMatCAddressPlanInput(
      input.materialization.provenance.iteration, self.accesses, input.namespace))
:lower_cmat_compose_exits(address_input)
end
function CMat.CMatCAddressPlanRejected:lower_cmat_compose_exits(input)
  if #self.issues == 0 then
    return Lower.LowerCMatEnvironmentRejected(
      Lower.LowerIssueFragmentRejected(
        input.environment.fragment.id, "C address plan rejected without an issue"))
  end
  return Lower.LowerCMatEnvironmentRejected(
    Lower.LowerIssueCMatAddressPlanRejected(
      input.environment.fragment.id, self.issues[1]))
end
function CMat.CMatCAddressPlanReady:lower_cmat_compose_exits(input)
  local environment = input.environment
  local exits = Lower.LowerCMatExitEnvironmentInput(
    environment.materialization.provenance, environment.coverage,
    environment.code_func):lower_cmat_exits()
  return exits:lower_cmat_finish_environment(
    Lower.LowerCMatAddressPlanReadyInput(input, self.plan))
end
function Lower.LowerCMatAccessesRejected:lower_cmat_compose_exits(_input, _values)
  return Lower.LowerCMatEnvironmentRejected(self.issue)
end

function Lower.LowerCMatExitsReady:lower_cmat_finish_environment(input)
  local address_input = input.environment
  local environment = address_input.environment
  return Lower.LowerCMatEnvironmentReady(CMat.CMatCFragmentInput(
    environment.materialization, environment.code_func,
    environment.coverage.covered_blocks,
    environment.coverage.replacement_source, environment.target,
    address_input.values.values, address_input.accesses.accesses, input.plan,
    self.exits, environment.namespace, environment.reserved_labels))
end
function Lower.LowerCMatExitsRejected:lower_cmat_finish_environment(_input)
  return Lower.LowerCMatEnvironmentRejected(self.issue)
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
function Mem.MemObjectProvenance:lower_cmat_access_source(input)
  local expected = C.CBackendDataPtr(input.fact.binding.ty:code_to_c_backend_type())
  return input.fact.provenance.lane.base:lower_cmat_direct_access(
    Lower.LowerCMatDirectAccessInput(input.fact.binding.access, input.values, expected))
end
function Mem.MemProvFieldPointer:lower_cmat_access_source(input)
  local expected = input.fact.binding:cmat_fragment_expected_ptr()
  return input.values:cmat_fragment_lookup(self.owner_value)
    :lower_cmat_field_access(input, self.ptr_field, expected)
end
function CMat.CMatCExternalValueBindingMissing:lower_cmat_field_access(input, _field, _expected)
  return Lower.LowerCMatAccessSourceRejected(access_issue(input.fact.binding.access,
    "projected field owner is unavailable at fragment entry"))
end
function CMat.CMatCExternalValueBindingFound:lower_cmat_field_access(input, field, expected)
  local text = input.fact.binding.access.name .. "_base"
  local base = C.CBackendLocal(C.CBackendLocalId(text), C.CBackendName(text), expected)
  return Lower.LowerCMatAccessSourceReady(
    CMat.CMatCFragmentAccessField(base, self.entry.c_local, field, expected))
end
function Kernel.KernelLane:lower_cmat_access_source(input)
  if self.object_fact ~= nil then return self.object_fact.provenance:lower_cmat_access_source(input) end
  return Mem.MemObjectProvenance.lower_cmat_access_source(self, input)
end
function Lower.LowerCMatAccessSourceInput:lower_cmat_access_source()
  return self.fact.provenance.lane:lower_cmat_access_source(self)
end
function Lower.LowerCMatAccessSourceReady:lower_cmat_finish_access(input)
  local entries = copy(input.collection.entries)
  entries[#entries + 1] = CMat.CMatCFragmentAccessBindingEntry(
    input.fact.binding.access, input.fact.provenance.lane.id,
    input.fact.mem_access, self.source, input.fact.elem_size,
    input.fact.stride, input.fact.alignment, input.fact.bounds,
    input.fact.trap, input.fact.movement)
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
  return evidence.backend.bounds:lower_cmat_admit_contract(evidence)
:lower_cmat_continue_contract(evidence)
end

function Mem.MemBoundsUnknown:lower_cmat_admit_contract(evidence)
  return Lower.LowerCMatAccessContractRejected(access_issue(
    evidence.binding.access, "fused access requires exact bounds evidence"))
end
function Mem.MemBoundsInObject:lower_cmat_admit_contract(evidence)
  return evidence.backend.trap:lower_cmat_admit_contract(evidence)
end
function Mem.MemBoundsRange:lower_cmat_admit_contract(evidence)
  return evidence.backend.trap:lower_cmat_admit_contract(evidence)
end
function Mem.MemBoundsAssumed:lower_cmat_admit_contract(evidence)
  return evidence.backend.trap:lower_cmat_admit_contract(evidence)
end

function Mem.MemMayTrap:lower_cmat_admit_contract(evidence)
  return Lower.LowerCMatAccessContractRejected(access_issue(
    evidence.binding.access, "potentially trapping access cannot enter fused CMat"))
end
function Mem.MemCheckedTrap:lower_cmat_admit_contract(evidence)
  return Lower.LowerCMatAccessContractRejected(access_issue(
    evidence.binding.access, "checked trapping order cannot enter fused CMat"))
end
function Mem.MemNonTrapping:lower_cmat_admit_contract(evidence)
  return evidence.backend.movement:lower_cmat_admit_contract(evidence)
end

function Mem.MemMovementPinned:lower_cmat_admit_contract(evidence)
  return Lower.LowerCMatAccessContractRejected(access_issue(
    evidence.binding.access, "pinned access cannot enter fused CMat: " .. self.reason))
end
function Mem.MemMovementMovable:lower_cmat_admit_contract(_evidence)
  return Lower.LowerCMatAccessContractAdmitted
end

function Lower.LowerCMatAccessContractRejected:lower_cmat_continue_contract(_evidence)
  return Lower.LowerCMatAccessesRejected(self.issue)
end
function Lower.LowerCMatAccessContractAdmitted:lower_cmat_continue_contract(evidence)
  local fact = Lower.LowerCMatAccessFact(
    evidence.binding, evidence.provenance, evidence.mem_access,
    evidence.backend.alignment, evidence.backend.bounds, evidence.backend.trap,
    evidence.backend.movement, evidence.elem_size, evidence.stride)
  local source_input = Lower.LowerCMatAccessSourceInput(
    fact, evidence.request.values)
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
  local stride = binding.layout:cmat_fragment_direct_stride(elem_size)
  if elem_size <= 0 or stride <= 0 or stride % elem_size ~= 0 then
    return Lower.LowerCMatAccessesRejected(access_issue(
      binding.access, "access layout is not direct scalar memory: " .. tostring(binding.layout)
        .. ", ty=" .. tostring(binding.ty) .. ", elem_size=" .. tostring(elem_size) .. ", stride=" .. tostring(stride)))
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
    self.materialization.provenance.accesses, self.values, self.target)
:lower_cmat_accesses()
end

return Lower
