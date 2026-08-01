-- Immutable CMat-preserving function assembly: strategy leaves contribute
-- LowerCEmittedFragment; exactly covered blocks are replaced, baseline entry
-- params are injected into the CMat entry block, and retained predecessor
-- terminators retarget to the CMat entry preserving argument atoms. CMat
-- alignments/control stay inside the CMat fragment; plan and namespace
-- invariants are trusted; the first typed fragment rejection is returned.

require("lalin.schema_v2")
require("lalin.impl.lower_plan")
require("lalin.impl.lower_emit_c.lower_sem")
local Lower = require("lalin.schema_v2.lower")
local C = require("lalin.schema_v2.c")
local CMat = require("lalin.schema_v2.c_materialize")
local Code = require("lalin.schema_v2.code")

local function sanitize(s)
  s = tostring(s or "fragment"):gsub("[^%w_]", "_")
  if s:match("^%d") then s = "_" .. s end
  if s == "" then s = "fragment" end
  return s
end
local function append(target, source)
  for i = 1, #source do target[#target + 1] = source[i] end
end

function Lower.LowerStrategy:lower_c_contribute(input)
  return Lower.LowerCRejectedFragment(input.fragment.id,
    Lower.LowerIssueFragmentRejected(input.fragment.id, "unsupported lower strategy leaf"))
end
function Lower.LowerStrategyCode:lower_c_contribute(input)
  return Lower.LowerCCodeFragment(input.fragment, input.coverage)
end
function Lower.LowerStrategyClosedForm:lower_c_contribute(input)
  return Lower.LowerCRejectedFragment(input.fragment.id,
    Lower.LowerIssueClosedFormUnsupported(input.fragment.id))
end
function Lower.LowerStrategyKernel:lower_c_contribute(input)
  return input.materializations:lower_cmat_lookup(self.kernel):lower_c_kernel_contribute(input)
end
function Lower.LowerKernelCMatMissing:lower_c_kernel_contribute(input)
  return Lower.LowerCRejectedFragment(input.fragment.id,
    Lower.LowerIssueFragmentRejected(input.fragment.id, "kernel materialization is absent: " .. self.kernel.text))
end
function Lower.LowerKernelCMatAmbiguous:lower_c_kernel_contribute(input)
  return Lower.LowerCRejectedFragment(input.fragment.id,
    Lower.LowerIssueFragmentRejected(input.fragment.id, "kernel materialization is ambiguous: " .. self.kernel.text))
end
function Lower.LowerKernelCMatFound:lower_c_kernel_contribute(input)
  return self.entry.state:lower_c_cmat_state_contribute(input)
end
function Lower.LowerKernelCMatRejected:lower_c_cmat_state_contribute(input)
  return Lower.LowerCRejectedFragment(input.fragment.id,
    Lower.LowerIssueKernelRejected(input.fragment.cover, self.rejects))
end
function Lower.LowerKernelCMatUnavailable:lower_c_cmat_state_contribute(input)
  return Lower.LowerCRejectedFragment(input.fragment.id,
    Lower.LowerIssueFragmentRejected(input.fragment.id, self.reason))
end
function Lower.LowerKernelCMatReady:lower_c_cmat_state_contribute(input)
  return self.coordinates:lower_c_coordinate_contribute(
    Lower.LowerCMatCoordinateContributionInput(input, self.materialization))
end
function Lower.LowerCMatCoordinatesProjected:lower_c_coordinate_contribute(input)
  return input.materialization:lower_c_cmat_materialization_contribute(
    Lower.LowerCMatMaterializationContributionInput(
      input.assembly, self.facet))
end
function Lower.LowerCMatCoordinatesRejected:lower_c_coordinate_contribute(input)
  if #self.issues == 0 then
    return Lower.LowerCRejectedFragment(input.assembly.fragment.id,
      Lower.LowerIssueCMatCoordinateRejected(
        input.assembly.fragment.id,
        Lower.LowerCMatCoordinateMaterializationUnavailable(
          input.materialization)))
  end
  return Lower.LowerCRejectedFragment(input.assembly.fragment.id,
    Lower.LowerIssueCMatCoordinateRejected(
      input.assembly.fragment.id, self.issues[1]))
end
function CMat.CMatMaterializedKernelFragment:lower_c_cmat_materialization_contribute(input)
  local assembly = input.assembly
  local env = Lower.LowerCMatEnvironmentInput(
    assembly.fragment, self, input.coordinates, assembly.coverage,
    assembly.code_func, assembly.baseline, assembly.dominance,
    assembly.adapters, assembly.namespace, assembly.reserved_labels, assembly.target)
  return env:lower_cmat_environment():lower_c_environment_contribute(assembly)
end
function CMat.CMatRejectedKernelFragment:lower_c_cmat_materialization_contribute(input)
  local assembly = input.assembly
  if #self.issues == 0 then
    return Lower.LowerCRejectedFragment(assembly.fragment.id,
      Lower.LowerIssueFragmentRejected(assembly.fragment.id,
        "kernel materialization rejected without an issue"))
  end
  return Lower.LowerCRejectedFragment(assembly.fragment.id,
    Lower.LowerIssueCMatRejected(assembly.fragment.id,
      CMat.CMatCEmissionMaterializationIssue(self.issues[1])))
end
function CMat.CMatMaterializedFused:lower_c_cmat_materialization_contribute(input)
  local assembly = input.assembly
  return Lower.LowerCRejectedFragment(assembly.fragment.id,
    Lower.LowerIssueFragmentRejected(assembly.fragment.id,
      "authored standalone materialization has no canonical kernel provenance"))
end
function CMat.CMatRejectedComputation:lower_c_cmat_materialization_contribute(input)
  local assembly = input.assembly
  if #self.issues == 0 then
    return Lower.LowerCRejectedFragment(assembly.fragment.id,
      Lower.LowerIssueFragmentRejected(assembly.fragment.id,
        "computation materialization rejected without an issue"))
  end
  return Lower.LowerCRejectedFragment(assembly.fragment.id,
    Lower.LowerIssueCMatRejected(assembly.fragment.id,
      CMat.CMatCEmissionMaterializationIssue(self.issues[1])))
end
function Lower.LowerCMatEnvironmentRejected:lower_c_environment_contribute(input)
  return Lower.LowerCRejectedFragment(input.fragment.id, self.issue)
end
function Lower.LowerCMatEnvironmentReady:lower_c_environment_contribute(input)
  return self.request:emit_cmat_fragment():lower_c_cmat_emission_contribute(input)
end
function CMat.CMatCFragmentRejected:lower_c_cmat_emission_contribute(input)
  if #self.issues == 0 then
    return Lower.LowerCRejectedFragment(input.fragment.id,
      Lower.LowerIssueFragmentRejected(input.fragment.id, "CMat fragment emission rejected without an issue"))
  end
  return Lower.LowerCRejectedFragment(input.fragment.id,
    Lower.LowerIssueCMatRejected(input.fragment.id, self.issues[1]))
end
function CMat.CMatCFragmentEmitted:lower_c_cmat_emission_contribute(input)
  return Lower.LowerCKernelCMatFragment(input.fragment, input.coverage, self.fragment)
end

function Lower.LowerFragmentCoverageRejected:lower_c_fragment_contribution(input, fragment, _dominance)
  return Lower.LowerCRejectedFragment(fragment.id, self.issue)
end
function Lower.LowerFragmentCoverageResolved:lower_c_fragment_contribution(input, fragment, dominance)
  local adapters = Lower.LowerCReplacementEntryAdapterInput(
    input.code_func, input.baseline, self.coverage.replacement_source, dominance)
    :lower_c_entry_adapters()
  return adapters:lower_c_fragment_contribution(input, fragment, self.coverage, dominance)
end
function Lower.LowerCReplacementEntryAdapterRejected:lower_c_fragment_contribution(input, fragment, _coverage, _dominance)
  return Lower.LowerCRejectedFragment(fragment.id, self.issue)
end
function Lower.LowerCReplacementEntryAdapterReady:lower_c_fragment_contribution(input, fragment, coverage, dominance)
  return fragment.strategy:lower_c_contribute(Lower.LowerCFragmentAssemblyInput(
    fragment, coverage, input.code_func, input.baseline, input.materializations,
    dominance, self.projection,
    CMat.CMatCFragmentNamespace(sanitize(fragment.id.text)),
    input.baseline:lower_c_body_labels(), input.spine.target))
end

function Lower.LowerCEmittedFragment:lower_c_contribution_issue() return {} end
function Lower.LowerCRejectedFragment:lower_c_contribution_issue() return { self.issue } end
function Lower.LowerCEmittedFragment:lower_c_splice_blocks(_baseline) return {} end
function Lower.LowerCKernelCMatFragment:lower_c_splice_blocks(baseline)
  local cmat, entry = self.cmat, self.cmat.blocks[1]
  local blocks = { C.CBackendBlock(cmat.entry,
    baseline:lower_c_block_params(self.coverage.replacement_source), entry.stmts, entry.term) }
  for i = 2, #cmat.blocks do blocks[#blocks + 1] = cmat.blocks[i] end
  return blocks
end
function Lower.LowerCEmittedFragment:lower_c_splice_locals() return {} end
function Lower.LowerCKernelCMatFragment:lower_c_splice_locals() return self.cmat.locals end
function Lower.LowerCEmittedFragment:lower_c_splice_helpers() return {} end
function Lower.LowerCKernelCMatFragment:lower_c_splice_helpers() return self.cmat.helpers end
function Lower.LowerCEmittedFragment:lower_c_replacement_entries() return {} end
function Lower.LowerCEmittedFragment:lower_c_eliminated_entries() return {} end
function Lower.LowerCKernelCMatFragment:lower_c_replacement_entries()
  local out = {}
  for i = 1, #self.cmat.block_alignments do
    append(out, self.cmat.block_alignments[i]:lower_c_replacement_entries())
  end
  return out
end
function Lower.LowerCKernelCMatFragment:lower_c_eliminated_entries()
  local out = {}
  for i = 1, #self.cmat.block_alignments do
    append(out, self.cmat.block_alignments[i]:lower_c_eliminated_entries())
  end
  return out
end
function CMat.CMatCBlockEliminated:lower_c_replacement_entries() return {} end
function CMat.CMatCBlockReplacementEntry:lower_c_replacement_entries() return { self } end
function CMat.CMatCBlockEliminated:lower_c_eliminated_entries() return { self } end
function CMat.CMatCBlockReplacementEntry:lower_c_eliminated_entries() return {} end

function C.CBackendLabel:lower_c_retarget_label(replacements)
  for i = 1, #replacements do
    if replacements[i].source.text == self.text then return replacements[i].replacement end
  end
  return self
end
function C.CBackendTerminator:lower_c_retarget_covered(_replacements) return self end
function C.CBackendGoto:lower_c_retarget_covered(replacements)
  return C.CBackendGoto(self.dest:lower_c_retarget_label(replacements), self.args)
end
function C.CBackendIfGoto:lower_c_retarget_covered(replacements)
  return C.CBackendIfGoto(self.cond,
    self.then_dest:lower_c_retarget_label(replacements), self.then_args,
    self.else_dest:lower_c_retarget_label(replacements), self.else_args)
end
function C.CBackendSwitchGoto:lower_c_retarget_covered(replacements)
  local cases = {}
  for i = 1, #self.cases do
    cases[i] = C.CBackendSwitchCase(self.cases[i].value,
      self.cases[i].dest:lower_c_retarget_label(replacements), self.cases[i].args)
  end
  return C.CBackendSwitchGoto(self.value, cases,
    self.default_dest:lower_c_retarget_label(replacements), self.default_args)
end
function C.CBackendBlock:lower_c_retained_block(replacements, eliminated)
  for i = 1, #replacements do
    if replacements[i].source.text == self.label.text then return {} end
  end
  for i = 1, #eliminated do
    if eliminated[i].source.text == self.label.text then return {} end
  end
  return { C.CBackendBlock(self.label, self.params, self.stmts,
    self.term:lower_c_retarget_covered(replacements)) }
end

function Lower.LowerCFunctionEmission:lower_c_body_labels() return self.func.body:lower_c_body_labels() end
function C.CBackendBodyBlocks:lower_c_body_labels()
  local out = { self.entry }
  for i = 1, #self.blocks do out[#out + 1] = self.blocks[i].label end
  return out
end
function C.CBackendBodyMixed:lower_c_body_labels()
  local out = { self.entry }
  for i = 1, #self.blocks do out[#out + 1] = self.blocks[i].label end
  return out
end
function Lower.LowerCFunctionEmission:lower_c_body_blocks() return self.func.body:lower_c_body_blocks() end
function C.CBackendBodyBlocks:lower_c_body_blocks() return self.blocks end
function C.CBackendBodyMixed:lower_c_body_blocks() return self.blocks end
function Lower.LowerCFunctionEmission:lower_c_body_entry() return self.func.body:lower_c_body_entry() end
function C.CBackendBodyBlocks:lower_c_body_entry() return self.entry end
function C.CBackendBodyMixed:lower_c_body_entry() return self.entry end
function Lower.LowerCFunctionEmission:lower_c_block_params(block)
  local out = {}
  for i = 1, #self.block_params.entries do
    local entry = self.block_params.entries[i]
    if entry.block == block then out[#out + 1] = entry.parameter end
  end
  return out
end

function Lower.LowerCFunctionAssemblyInput:lower_c_function_assembly()
  return self.spine.graph:lower_func_lookup(self.code_func.id):lower_c_assembly_graph(self)
end
function Lower.LowerCodeFuncGraphMissing:lower_c_assembly_graph(input)
  return Lower.LowerCFunctionAssemblyRejected(input.code_func.id, {
    Lower.LowerIssueDominanceRejected(input.code_func.id, "function graph is absent from the lowering spine") })
end
function Lower.LowerCodeFuncGraphFound:lower_c_assembly_graph(input)
  return input:lower_c_assembly_dominance(self.graph)
end
function Lower.LowerCFunctionAssemblyInput:lower_c_assembly_dominance(graph)
  return Lower.LowerCDominanceConstructionInput(self.code_func, graph)
    :lower_c_dominance():lower_c_assembly_dominance(self, graph)
end
function Lower.LowerCDominanceRejected:lower_c_assembly_dominance(input, _graph)
  return Lower.LowerCFunctionAssemblyRejected(input.code_func.id, { self.issue })
end
function Lower.LowerCDominanceReady:lower_c_assembly_dominance(input, graph)
  local loops = {}
  for i = 1, #graph.loops do
    loops[#loops + 1] = Lower.LowerLoopByIdEntry(graph.loops[i].id, graph.loops[i])
  end
  local loops_projection = Lower.LowerLoopByIdProjection(loops)
  local fragments, splice_blocks, locals, helpers = {}, {}, {}, {}
  local replacements, eliminated = {}, {}

  for i = 1, #input.plan.fragments do
    local fragment = input.plan.fragments[i]
    local contribution = fragment.cover:lower_c_fragment_coverage(
      Lower.LowerFragmentCoverageInput(input.code_func, loops_projection))
      :lower_c_fragment_contribution(input, fragment, self.dominance)
    local rejection = contribution:lower_c_contribution_issue()
    if #rejection > 0 then
      return Lower.LowerCFunctionAssemblyRejected(input.code_func.id, rejection)
    end
    fragments[#fragments + 1] = contribution
    append(splice_blocks, contribution:lower_c_splice_blocks(input.baseline))
    append(locals, contribution:lower_c_splice_locals())
    append(helpers, contribution:lower_c_splice_helpers())
    append(replacements, contribution:lower_c_replacement_entries())
    append(eliminated, contribution:lower_c_eliminated_entries())
  end

  local blocks = {}
  append(blocks, splice_blocks)
  for i = 1, #input.baseline:lower_c_body_blocks() do
    append(blocks, input.baseline:lower_c_body_blocks()[i]:lower_c_retained_block(replacements, eliminated))
  end

  local entry = input.baseline:lower_c_body_entry()
  local entry_key = input.code_func.entry.text
  for i = 1, #replacements do
    if replacements[i].source.text == entry_key then entry = replacements[i].replacement end
  end

  local all_locals = {}
  append(all_locals, input.baseline.func.locals)
  append(all_locals, locals)
  local all_helpers = {}
  append(all_helpers, input.baseline.helpers)
  append(all_helpers, helpers)

  return Lower.LowerCFunctionAssemblyReady(Lower.LowerCFunctionAssembly(
    input.code_func, input.baseline, fragments, blocks, all_locals, all_helpers))
end

function Lower.LowerCFunctionAssembly:lower_c_function()
  local entry = self.baseline:lower_c_body_entry()
  local entry_key = self.code_func.entry.text
  for i = 1, #self.fragments do
    local r = self.fragments[i]:lower_c_replacement_entries()
    for j = 1, #r do
      if r[j].source.text == entry_key then entry = r[j].replacement end
    end
  end
  local func = C.CBackendFunc(self.baseline.func.name, self.baseline.func.symbol,
    self.baseline.func.visibility, self.baseline.func.sig, self.baseline.func.params,
    self.locals, C.CBackendBodyBlocks(entry, self.blocks))
  return Lower.LowerCFunctionEmission(func, self.helpers, self.baseline.value_types,
    self.baseline.value_sites, self.baseline.source, self.baseline.block_params)
end
function Lower.LowerCFunctionAssemblyReady:lower_c_module_functions()
  return { self.assembly:lower_c_function() }
end
function Lower.LowerCFunctionAssemblyRejected:lower_c_module_functions() return {} end
function Lower.LowerCFunctionAssemblyReady:lower_c_module_issues() return {} end
function Lower.LowerCFunctionAssemblyRejected:lower_c_module_issues() return self.issues end

return Lower
