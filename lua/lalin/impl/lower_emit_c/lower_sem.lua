-- Canonical LOWER semantic-fragment preparation and typed coverage resolution.
require("lalin.schema_v2")
require("lalin.impl.stencil_kernel")
require("lalin.impl.lower_emit_c.materialize")

local Lower = require("lalin.schema_v2.lower")
local Stencil = require("lalin.schema_v2.stencil")
local CMat = require("lalin.schema_v2.c_materialize")

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
function Lower.LowerCBlockParamSite:lower_cmat_value_contribution(input)
  return input.coverage:lower_c_block_coverage(self.block)
:lower_cmat_value_contribution(input)
end
function Lower.LowerCInstructionSite:lower_cmat_value_contribution(input)
  return input.coverage:lower_c_block_coverage(self.block)
:lower_cmat_value_contribution(input)
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

return Lower
