package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local asdl = require("lalin.asdl")
require("lalin.schema_v2")
require("lalin.impl.lower_plan")
require("lalin.impl.lower_emit_c")

local Code = require("lalin.schema_v2.code")
local Graph = require("lalin.schema_v2.graph")
local Kernel = require("lalin.schema_v2.kernel")
local Stencil = require("lalin.schema_v2.stencil")
local CMat = require("lalin.schema_v2.c_materialize")
local C = require("lalin.schema_v2.c")
local Core = require("lalin.schema_v2.core")
local Mem = require("lalin.schema_v2.mem")
local Flow = require("lalin.schema_v2.flow")
local Lower = require("lalin.schema_v2.lower")

local origin = Code.CodeOriginUnknown
local func_id = Code.CodeFuncId("lower_cmat_sem")
local sig_id = Code.CodeSigId("lower_cmat_sem_sig")
local entry_id = Code.CodeBlockId("entry")
local body_id = Code.CodeBlockId("body")
local exit_id = Code.CodeBlockId("exit")
local term = Code.CodeTerm(
  Code.CodeTermId("return"), Code.CodeTermReturn({}), origin)
local function block(id)
  return Code.CodeBlock(id, id.text, {}, {}, term, origin)
end
local func = Code.CodeFunc(
  func_id, "lower_cmat_sem", Code.CodeLinkageLocal, sig_id, {}, {}, entry_id,
  { block(entry_id), Code.CodeBlock(
      body_id, body_id.text, {}, {}, Code.CodeTerm(
        Code.CodeTermId("jump_exit"), Code.CodeTermJump(exit_id, {}), origin),
      origin), block(exit_id) }, origin)
local loop_id = Graph.GraphLoopId("lower_cmat_sem_loop")
local loop = Graph.GraphLoop(
  loop_id, func_id, Graph.GraphBlockId(func_id, body_id),
  { Graph.GraphBlockId(func_id, body_id) }, {}, {
    Graph.GraphEdge(
      Graph.GraphBlockId(func_id, body_id),
      Graph.GraphBlockId(func_id, exit_id), Graph.EdgeKindJump),
  })
local loops = Lower.LowerLoopByIdProjection({
  Lower.LowerLoopByIdEntry(loop_id, loop),
})
local input = Lower.LowerFragmentCoverageInput(func, loops)

local loop_cover = Lower.LowerCoverLoop(loop_id):lower_c_fragment_coverage(input)
assert(asdl.classof(loop_cover) == Lower.LowerFragmentCoverageResolved)
assert(loop_cover.coverage.func == func_id)
assert(loop_cover.coverage.replacement_source == body_id)
assert(loop_cover.coverage.covered_blocks[1] == body_id)
assert(loop_cover.coverage.origin.loop == loop)
local normal_requirements = Stencil.StencilKernelResultVoid
:lower_cmat_exit_requirements(loop_cover.coverage)
assert(asdl.classof(normal_requirements) ==
  Lower.LowerCMatExitRequirementsReady)
local normal_exits = Lower.LowerCMatExitBuildReady(
  Lower.LowerCMatExitCollection({}))
:lower_cmat_continue_exits(Lower.LowerCMatExitFoldInput(
  normal_requirements.requirements, func, 1))
assert(asdl.classof(normal_exits) == Lower.LowerCMatExitsReady)
assert(normal_exits.exits.entries[1].role == CMat.CMatCExitNormal)
assert(normal_exits.exits.entries[1].destination == exit_id)
local i32 = Code.CodeTyInt(32, Code.CodeSigned)
local result_value = Code.CodeValueId("result")
local result_dest = Code.CodeBlockId("result_dest")
local result_func = Code.CodeFunc(
  func_id, "lower_cmat_result", Code.CodeLinkageLocal, sig_id, {}, {}, entry_id, {
    block(entry_id), Code.CodeBlock(
      result_dest, result_dest.text, {
        Code.CodeParam(result_value, "result", i32, origin),
      }, {}, term, origin),
  }, origin)
local function fold_exit(requirement, code_func)
  return Lower.LowerCMatExitBuildReady(Lower.LowerCMatExitCollection({}))
:lower_cmat_continue_exits(Lower.LowerCMatExitFoldInput(
    Lower.LowerCMatExitRequirementProjection({ requirement }), code_func, 1))
end
local control_exit = fold_exit(Lower.LowerCMatExitRequirement(
  CMat.CMatCExitFound, result_dest, Lower.LowerCMatExitControlValue), result_func)
assert(asdl.classof(control_exit) == Lower.LowerCMatExitsReady)
assert(control_exit.exits.entries[1].args[1] ==
  CMat.CMatCExitArgumentControlValue)
local no_argument_mismatch = fold_exit(Lower.LowerCMatExitRequirement(
  CMat.CMatCExitSuccess, result_dest, Lower.LowerCMatExitNoArguments), result_func)
assert(asdl.classof(no_argument_mismatch) == Lower.LowerCMatExitsRejected)
local source_arg_func = Code.CodeFunc(
  func_id, "lower_cmat_source_arg", Code.CodeLinkageLocal, sig_id, {
    Code.CodeParam(result_value, "result", i32, origin),
  }, {}, body_id, {
    Code.CodeBlock(body_id, body_id.text, {}, {}, Code.CodeTerm(
      Code.CodeTermId("jump_arg"),
      Code.CodeTermJump(exit_id, { result_value }), origin), origin),
    Code.CodeBlock(exit_id, exit_id.text, {
      Code.CodeParam(result_value, "result", i32, origin),
    }, {}, term, origin),
  }, origin)
local source_arg_rejected = fold_exit(Lower.LowerCMatExitRequirement(
  CMat.CMatCExitNormal, exit_id, Lower.LowerCMatExitSourceEdge(body_id)),
  source_arg_func)
assert(asdl.classof(source_arg_rejected) == Lower.LowerCMatExitsRejected)
local dom_param = Code.CodeValueId("dom_param")
local dom_block_param = Code.CodeValueId("dom_block_param")
local dom_entry_value = Code.CodeValueId("dom_entry_value")
local dom_body_value = Code.CodeValueId("dom_body_value")
local dom_late_value = Code.CodeValueId("dom_late_value")
local dom_entry = Code.CodeBlockId("dom_entry")
local dom_body = Code.CodeBlockId("dom_body")
local dom_exit = Code.CodeBlockId("dom_exit")
local dom_sig = Code.CodeSig(
  Code.CodeSigId("dom_sig"), { i32 }, {})
local dom_func = Code.CodeFunc(
  Code.CodeFuncId("dom_func"), "dom_func", Code.CodeLinkageLocal, dom_sig.id, {
    Code.CodeParam(dom_param, "param", i32, origin),
  }, {}, dom_entry, {
    Code.CodeBlock(dom_entry, "dom_entry", {}, {
      Code.CodeInst(Code.CodeInstId("entry_const"), Code.CodeInstConst(
        dom_entry_value, Code.CodeConstLiteral(i32, Core.LitInt("1"))), origin),
    }, Code.CodeTerm(Code.CodeTermId("entry_jump"),
      Code.CodeTermJump(dom_body, { dom_param }), origin), origin),
    Code.CodeBlock(dom_body, "dom_body", {
      Code.CodeParam(dom_block_param, "block_param", i32, origin),
    }, {
      Code.CodeInst(Code.CodeInstId("body_const"), Code.CodeInstConst(
        dom_body_value, Code.CodeConstLiteral(i32, Core.LitInt("3"))), origin),
    }, Code.CodeTerm(Code.CodeTermId("body_jump"),
      Code.CodeTermJump(dom_exit, {}), origin), origin),
    Code.CodeBlock(dom_exit, "dom_exit", {}, {
      Code.CodeInst(Code.CodeInstId("late_const"), Code.CodeInstConst(
        dom_late_value, Code.CodeConstLiteral(i32, Core.LitInt("2"))), origin),
    }, term, origin),
  }, origin)
local dom_graph = Graph.CodeFuncGraph(dom_func.id, {
  Graph.GraphEdge(Graph.GraphBlockId(dom_func.id, dom_entry),
    Graph.GraphBlockId(dom_func.id, dom_body), Graph.EdgeKindJump),
  Graph.GraphEdge(Graph.GraphBlockId(dom_func.id, dom_body),
    Graph.GraphBlockId(dom_func.id, dom_exit), Graph.EdgeKindJump),
}, {}, {}, {})
local dominance = Lower.LowerCDominanceConstructionInput(
  dom_func, dom_graph):lower_c_dominance()
assert(asdl.classof(dominance) == Lower.LowerCDominanceReady)
assert(dominance.dominance:lower_c_dominance_lookup(
  Lower.LowerCDominanceQuery(dom_entry, dom_body)) == Lower.LowerCDominates)
assert(dominance.dominance:lower_c_dominance_lookup(
  Lower.LowerCDominanceQuery(dom_exit, dom_body)) ==
  Lower.LowerCDoesNotDominate)
local dom_coverage = Lower.LowerCoverBlock(
  dom_func.id, dom_body):lower_c_fragment_coverage(
    Lower.LowerFragmentCoverageInput(
      dom_func, Lower.LowerLoopByIdProjection({})))
assert(asdl.classof(dom_coverage) == Lower.LowerFragmentCoverageResolved)
local dom_signatures = Lower.LowerCSignatureProjection({
  dom_sig:lower_c_signature_entry(),
})
local dom_baseline = dom_func:lower_c_function(
  Lower.LowerCFunctionInput(dom_signatures))
local dom_adapters = Lower.LowerCReplacementEntryAdapterInput(
  dom_func, dom_baseline, dom_body, dominance.dominance)
:lower_c_entry_adapters()
assert(asdl.classof(dom_adapters) ==
  Lower.LowerCReplacementEntryAdapterReady)
assert(#dom_adapters.projection.entries == 1)
assert(dom_adapters.projection.entries[1].incoming[1].value.value ==
  dom_param)
local bad_arg_func = Code.CodeFunc(
  dom_func.id, dom_func.name, dom_func.linkage, dom_func.sig, dom_func.params,
  dom_func.locals, dom_func.entry, {
    Code.CodeBlock(dom_entry, "dom_entry", {}, {
      Code.CodeInst(Code.CodeInstId("entry_const"), Code.CodeInstConst(
        dom_entry_value, Code.CodeConstLiteral(i32, Core.LitInt("1"))), origin),
    }, Code.CodeTerm(Code.CodeTermId("bad_entry_jump"),
      Code.CodeTermJump(dom_body, { dom_late_value }), origin), origin),
    dom_func.blocks[2], dom_func.blocks[3],
  }, origin)
assert(asdl.classof(Lower.LowerCReplacementEntryAdapterInput(
  bad_arg_func, dom_baseline, dom_body, dominance.dominance)
:lower_c_entry_adapters()) ==
  Lower.LowerCReplacementEntryAdapterRejected)
local entry_param_value = Code.CodeValueId("entry_param")
local entry_param_func = Code.CodeFunc(
  Code.CodeFuncId("entry_param_func"), "entry_param_func",
  Code.CodeLinkageLocal, Code.CodeSigId("entry_param_sig"), {}, {}, dom_entry, {
    Code.CodeBlock(dom_entry, "entry", {
      Code.CodeParam(entry_param_value, "entry_param", i32, origin),
    }, {}, term, origin),
  }, origin)
local entry_param_sig = Code.CodeSig(entry_param_func.sig, {}, {})
local entry_param_baseline = entry_param_func:lower_c_function(
  Lower.LowerCFunctionInput(Lower.LowerCSignatureProjection({
    entry_param_sig:lower_c_signature_entry(),
  })))
local entry_param_dominance = Lower.LowerCDominanceConstructionInput(
  entry_param_func, Graph.CodeFuncGraph(
    entry_param_func.id, {}, {}, {}, {})):lower_c_dominance()
assert(asdl.classof(entry_param_dominance) == Lower.LowerCDominanceReady)
assert(asdl.classof(Lower.LowerCReplacementEntryAdapterInput(
  entry_param_func, entry_param_baseline, dom_entry,
  entry_param_dominance.dominance):lower_c_entry_adapters()) ==
  Lower.LowerCReplacementEntryAdapterRejected)
local dom_values = Lower.LowerCMatValueEnvironmentInput(
  dom_func, dom_baseline, dom_coverage.coverage, dominance.dominance,
  dom_adapters.projection):lower_cmat_values()
assert(asdl.classof(dom_values) == Lower.LowerCMatValuesReady)
assert(#dom_values.values.entries == 3)
local source_classes = {}
local has_function_param = false
for i = 1, #dom_values.availability.entries do
  local source = dom_values.availability.entries[i].source
  if source == Lower.LowerCEntryFunctionParam then has_function_param = true end
  source_classes[asdl.classof(source)] = true
end
assert(has_function_param)
assert(source_classes[Lower.LowerCEntryReplacementBlockParam])
assert(source_classes[Lower.LowerCEntryDominatingInstruction])
local stale_dom_func = Code.CodeFunc(
  dom_func.id, "stale", dom_func.linkage, dom_func.sig, dom_func.params,
  dom_func.locals, dom_func.entry, { dom_func.blocks[1] }, origin)
assert(asdl.classof(Lower.LowerCMatValueEnvironmentInput(
  dom_func, dom_baseline, dom_coverage.coverage, Lower.LowerCDominanceProjection(
    stale_dom_func, dom_graph, dominance.dominance.entries),
  dom_adapters.projection):lower_cmat_values()) ==
  Lower.LowerCMatValuesRejected)
local malformed_graph = Graph.CodeFuncGraph(dom_func.id, {
  Graph.GraphEdge(Graph.GraphBlockId(dom_func.id, dom_entry),
    Graph.GraphBlockId(Code.CodeFuncId("other"), dom_body), Graph.EdgeKindJump),
}, {}, {}, {})
assert(asdl.classof(Lower.LowerCDominanceConstructionInput(
  dom_func, malformed_graph):lower_c_dominance()) ==
  Lower.LowerCDominanceRejected)
local omitted_graph = Graph.CodeFuncGraph(dom_func.id, {
  Graph.GraphEdge(Graph.GraphBlockId(dom_func.id, dom_body),
    Graph.GraphBlockId(dom_func.id, dom_exit), Graph.EdgeKindJump),
}, {}, {}, {})
assert(asdl.classof(Lower.LowerCDominanceConstructionInput(
  dom_func, omitted_graph):lower_c_dominance()) ==
  Lower.LowerCDominanceRejected)
local diamond_entry = Code.CodeBlockId("diamond_entry")
local diamond_left = Code.CodeBlockId("diamond_left")
local diamond_right = Code.CodeBlockId("diamond_right")
local diamond_join = Code.CodeBlockId("diamond_join")
local diamond_exit = Code.CodeBlockId("diamond_exit")
local diamond_func = Code.CodeFunc(
  Code.CodeFuncId("diamond"), "diamond", Code.CodeLinkageLocal, dom_sig.id, {
    Code.CodeParam(dom_param, "cond", i32, origin),
  }, {}, diamond_entry, {
    Code.CodeBlock(diamond_entry, "entry", {}, {}, Code.CodeTerm(
      Code.CodeTermId("diamond_branch"), Code.CodeTermBranch(
        dom_param, diamond_left, {}, diamond_right, {}), origin), origin),
    Code.CodeBlock(diamond_left, "left", {}, {}, Code.CodeTerm(
      Code.CodeTermId("left_jump"), Code.CodeTermJump(diamond_join, {}), origin), origin),
    Code.CodeBlock(diamond_right, "right", {}, {}, Code.CodeTerm(
      Code.CodeTermId("right_jump"), Code.CodeTermJump(diamond_join, {}), origin), origin),
    Code.CodeBlock(diamond_join, "join", {}, {}, Code.CodeTerm(
      Code.CodeTermId("join_jump"), Code.CodeTermJump(diamond_exit, {}), origin), origin),
    Code.CodeBlock(diamond_exit, "exit", {}, {}, term, origin),
  }, origin)
local diamond_graph = Graph.CodeFuncGraph(diamond_func.id, {
  Graph.GraphEdge(Graph.GraphBlockId(diamond_func.id, diamond_entry),
    Graph.GraphBlockId(diamond_func.id, diamond_left), Graph.EdgeKindJump),
  Graph.GraphEdge(Graph.GraphBlockId(diamond_func.id, diamond_entry),
    Graph.GraphBlockId(diamond_func.id, diamond_right), Graph.EdgeKindJump),
  Graph.GraphEdge(Graph.GraphBlockId(diamond_func.id, diamond_left),
    Graph.GraphBlockId(diamond_func.id, diamond_join), Graph.EdgeKindJump),
  Graph.GraphEdge(Graph.GraphBlockId(diamond_func.id, diamond_right),
    Graph.GraphBlockId(diamond_func.id, diamond_join), Graph.EdgeKindJump),
  Graph.GraphEdge(Graph.GraphBlockId(diamond_func.id, diamond_join),
    Graph.GraphBlockId(diamond_func.id, diamond_exit), Graph.EdgeKindJump),
}, {}, {}, {})
local diamond_dominance = Lower.LowerCDominanceConstructionInput(
  diamond_func, diamond_graph):lower_c_dominance()
assert(asdl.classof(diamond_dominance) == Lower.LowerCDominanceReady)
assert(diamond_dominance.dominance:lower_c_dominance_lookup(
  Lower.LowerCDominanceQuery(diamond_entry, diamond_join)) ==
  Lower.LowerCDominates)
assert(diamond_dominance.dominance:lower_c_dominance_lookup(
  Lower.LowerCDominanceQuery(diamond_left, diamond_join)) ==
  Lower.LowerCDoesNotDominate)
local loop_entry = Code.CodeBlockId("loop_entry")
local loop_header = Code.CodeBlockId("loop_header")
local loop_exit = Code.CodeBlockId("loop_exit")
local loop_func = Code.CodeFunc(
  Code.CodeFuncId("loop_dom"), "loop_dom", Code.CodeLinkageLocal, dom_sig.id, {
    Code.CodeParam(dom_param, "cond", i32, origin),
  }, {}, loop_entry, {
    Code.CodeBlock(loop_entry, "entry", {}, {}, Code.CodeTerm(
      Code.CodeTermId("to_header"), Code.CodeTermJump(loop_header, {}), origin), origin),
    Code.CodeBlock(loop_header, "header", {}, {}, Code.CodeTerm(
      Code.CodeTermId("loop_branch"), Code.CodeTermBranch(
        dom_param, loop_header, {}, loop_exit, {}), origin), origin),
    Code.CodeBlock(loop_exit, "exit", {}, {}, term, origin),
  }, origin)
local loop_graph = Graph.CodeFuncGraph(loop_func.id, {
  Graph.GraphEdge(Graph.GraphBlockId(loop_func.id, loop_entry),
    Graph.GraphBlockId(loop_func.id, loop_header), Graph.EdgeKindJump),
  Graph.GraphEdge(Graph.GraphBlockId(loop_func.id, loop_header),
    Graph.GraphBlockId(loop_func.id, loop_header), Graph.EdgeKindJump),
  Graph.GraphEdge(Graph.GraphBlockId(loop_func.id, loop_header),
    Graph.GraphBlockId(loop_func.id, loop_exit), Graph.EdgeKindJump),
}, {}, {}, {})
local loop_dominance = Lower.LowerCDominanceConstructionInput(
  loop_func, loop_graph):lower_c_dominance()
assert(asdl.classof(loop_dominance) == Lower.LowerCDominanceReady)
assert(loop_dominance.dominance:lower_c_dominance_lookup(
  Lower.LowerCDominanceQuery(loop_header, loop_exit)) ==
  Lower.LowerCDominates)
local base_value = Code.CodeValueId("base_ptr")
local mem_access = Mem.MemAccessId("access")
local access = Stencil.StencilAccess(
  "input", Stencil.StencilAccessRead, i32,
  Stencil.StencilAccessDirect(Stencil.StencilLayoutContiguous(4)))
local binding = access:cmat_canonical_binding(
  CMat.CMatAccessBindingInput(CMat.CMatLocalId("input")))
local lane = Kernel.KernelLane(
  Kernel.KernelLaneId("lane"), Mem.MemObjectId("object"), { mem_access },
  Mem.MemBaseValue(base_value), i32, Mem.MemAccessScalar, {
    Mem.MemBackendAccessInfo(
      mem_access, Mem.MemNonTrapping("fixture"), Mem.MemAlignKnown(4),
      Mem.MemBoundsInObject("fixture"), Mem.MemDerefBytesKnown(4),
      Mem.MemMovementMovable("fixture"), {}),
  })
local provenance_access = Stencil.StencilAccessByKernelLaneEntry(lane, access)
local fact = Lower.LowerCMatAccessFact(
  binding, provenance_access, mem_access, Mem.MemAlignKnown(4), 4, 4)
local c_i32 = i32:code_to_c_backend_type()
local base_local = C.CBackendLocal(
  C.CBackendLocalId("base_ptr"), C.CBackendName("base_ptr"),
  C.CBackendDataPtr(c_i32))
local direct_source = Lower.LowerCMatAccessSourceInput(
  fact, CMat.CMatCExternalValueBindingProjection({
    CMat.CMatCExternalValueBindingEntry(base_value, base_local),
  }), Lower.LowerAddressPlanProjection({})):lower_cmat_access_source()
assert(asdl.classof(direct_source) == Lower.LowerCMatAccessSourceReady)
assert(asdl.classof(direct_source.source) ==
  CMat.CMatCFragmentAccessDirect)
local address_id = Flow.FlowAddressId("address")
local carrier_id = Flow.FlowCarrierId("carrier")
local address_plan = Lower.LowerAddressPlan(
  address_id, carrier_id, Flow.FlowAddressBase(lane.base, i32, 4),
  Lower.LowerAddressCarryProjected, {
    Lower.LowerAddressBlockParam(
      address_id, Graph.GraphBlockId(func_id, body_id),
      C.CBackendLocalId("projected_base"), i32),
  }, {}, { Lower.LowerAddressLaneUse(address_id, lane.id) }, {}, {})
local projected_source = Lower.LowerCMatAccessSourceInput(
  fact, CMat.CMatCExternalValueBindingProjection({}),
  Lower.LowerAddressPlanProjection({ address_plan }))
:lower_cmat_access_source()
assert(asdl.classof(projected_source) ==
  Lower.LowerCMatAccessSourceRejected)
local forged_plan = Lower.LowerAddressPlan(
  address_id, carrier_id, Flow.FlowAddressBase(lane.base, i32, 4),
  Lower.LowerAddressCarryProjected, {}, {}, {
    Lower.LowerAddressLaneUse(Flow.FlowAddressId("other"), lane.id),
  }, {}, {})
assert(asdl.classof(Lower.LowerAddressPlanProjection({ forged_plan })
:lower_cmat_lane_lookup(lane.id)) ==
  Lower.LowerAddressByLaneInvalidRelation)
local wrong_base = C.CBackendLocal(
  C.CBackendLocalId("wrong"), C.CBackendName("wrong"), c_i32)
local wrong_direct = Lower.LowerCMatAccessSourceInput(
  fact, CMat.CMatCExternalValueBindingProjection({
    CMat.CMatCExternalValueBindingEntry(base_value, wrong_base),
  }), Lower.LowerAddressPlanProjection({})):lower_cmat_access_source()
assert(asdl.classof(wrong_direct) == Lower.LowerCMatAccessSourceRejected)
local target = C.CBackendTarget(
  C.CBackendC99, C.CBackendHostedNative, 64, 64,
  C.CBackendLittleEndian)
local exact_values = CMat.CMatCExternalValueBindingProjection({
  CMat.CMatCExternalValueBindingEntry(base_value, base_local),
})
local built_accesses = Lower.LowerCMatAccessBuildRequest(
  { binding }, Stencil.StencilAccessByKernelLaneProjection({
    provenance_access,
  }), exact_values,
  Lower.LowerAddressPlanProjection({}), target):lower_cmat_accesses()
assert(asdl.classof(built_accesses) == Lower.LowerCMatAccessesReady)
assert(#built_accesses.accesses.entries == 1)
assert(built_accesses.accesses.entries[1].mem_access == mem_access)
assert(asdl.classof(built_accesses.accesses.entries[1].source) ==
  CMat.CMatCFragmentAccessDirect)
local second_access = Mem.MemAccessId("access_second")
local ambiguous_lane = Kernel.KernelLane(
  lane.id, lane.object, { mem_access, second_access }, lane.base, lane.elem_ty,
  lane.pattern, lane.backend_info)
local ambiguous_accesses = Lower.LowerCMatAccessBuildRequest(
  { binding }, Stencil.StencilAccessByKernelLaneProjection({
    Stencil.StencilAccessByKernelLaneEntry(ambiguous_lane, access),
  }), exact_values,
  Lower.LowerAddressPlanProjection({}), target):lower_cmat_accesses()
assert(asdl.classof(ambiguous_accesses) ==
  Lower.LowerCMatAccessesRejected)
local duplicate_relation = Lower.LowerCMatAccessBuildRequest(
  { binding }, Stencil.StencilAccessByKernelLaneProjection({
    provenance_access, provenance_access,
  }), exact_values, Lower.LowerAddressPlanProjection({}), target)
:lower_cmat_accesses()
assert(asdl.classof(duplicate_relation) ==
  Lower.LowerCMatAccessesRejected)
local extra_backend_lane = Kernel.KernelLane(
  lane.id, lane.object, lane.accesses, lane.base, lane.elem_ty, lane.pattern,
  { lane.backend_info[1], lane.backend_info[1] })
local extra_backend = Lower.LowerCMatAccessBuildRequest(
  { binding }, Stencil.StencilAccessByKernelLaneProjection({
    Stencil.StencilAccessByKernelLaneEntry(extra_backend_lane, access),
  }), exact_values, Lower.LowerAddressPlanProjection({}), target)
:lower_cmat_accesses()
assert(asdl.classof(extra_backend) == Lower.LowerCMatAccessesRejected)
local gather_lane = Kernel.KernelLane(
  lane.id, lane.object, lane.accesses, lane.base, lane.elem_ty,
  Mem.MemAccessGather, lane.backend_info)
local gather_access = Lower.LowerCMatAccessBuildRequest(
  { binding }, Stencil.StencilAccessByKernelLaneProjection({
    Stencil.StencilAccessByKernelLaneEntry(gather_lane, access),
  }), exact_values, Lower.LowerAddressPlanProjection({}), target)
:lower_cmat_accesses()
assert(asdl.classof(gather_access) == Lower.LowerCMatAccessesRejected)
local narrow_backend = Mem.MemBackendAccessInfo(
  mem_access, Mem.MemNonTrapping("fixture"), Mem.MemAlignKnown(4),
  Mem.MemBoundsInObject("fixture"), Mem.MemDerefBytesKnown(2),
  Mem.MemMovementMovable("fixture"), {})
local narrow_lane = Kernel.KernelLane(
  lane.id, lane.object, lane.accesses, lane.base, lane.elem_ty, lane.pattern,
  { narrow_backend })
local narrow_access = Lower.LowerCMatAccessBuildRequest(
  { binding }, Stencil.StencilAccessByKernelLaneProjection({
    Stencil.StencilAccessByKernelLaneEntry(narrow_lane, access),
  }), exact_values, Lower.LowerAddressPlanProjection({}), target)
:lower_cmat_accesses()
assert(asdl.classof(narrow_access) == Lower.LowerCMatAccessesRejected)

local function_cover = Lower.LowerCoverFunction(func_id):lower_c_fragment_coverage(input)
assert(asdl.classof(function_cover) == Lower.LowerFragmentCoverageResolved)
assert(#function_cover.coverage.covered_blocks == 3)
assert(function_cover.coverage.replacement_source == entry_id)

local range_cover = Lower.LowerCoverBlockRange(
  func_id, body_id, exit_id):lower_c_fragment_coverage(input)
assert(asdl.classof(range_cover) == Lower.LowerFragmentCoverageResolved)
assert(#range_cover.coverage.covered_blocks == 2)

local missing = Lower.LowerCoverLoop(
  Graph.GraphLoopId("missing")):lower_c_fragment_coverage(input)
assert(asdl.classof(missing) == Lower.LowerFragmentCoverageRejected)
assert(asdl.classof(missing.issue) == Lower.LowerIssueCoverageRejected)

local kernel = Kernel.KernelId("kernel")
local projection = Lower.LowerKernelCMatProjection({
  Lower.LowerKernelCMatEntry(
    kernel, Lower.LowerKernelCMatUnavailable("fixture")),
})
assert(asdl.classof(projection:lower_cmat_lookup(kernel)) ==
  Lower.LowerKernelCMatFound)
assert(asdl.classof(projection:lower_cmat_lookup(
  Kernel.KernelId("absent"))) == Lower.LowerKernelCMatMissing)
local ambiguous = Lower.LowerKernelCMatProjection({
  projection.entries[1], projection.entries[1],
}):lower_cmat_lookup(kernel)
assert(asdl.classof(ambiguous) == Lower.LowerKernelCMatAmbiguous)
assert(ambiguous.count == 2)

assert(Lower.LowerCMatValuesReady)
assert(Lower.LowerCMatAccessesReady)
assert(Lower.LowerCMatExitsReady)
assert(Lower.LowerCCodeFragment)
assert(Lower.LowerCKernelCMatFragment)
assert(Lower.LowerCLocalSubstitutionFound)
assert(Lower.LowerCModuleResult)

print("schema_v2 LOWER CMat semantic gate ok")
