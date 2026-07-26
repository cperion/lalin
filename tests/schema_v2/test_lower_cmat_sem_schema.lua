package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local asdl = require("lalin.asdl")
require("lalin.schema_v2")
require("lalin.impl.lower_plan")
require("lalin.impl.lower_emit_c.lower_sem")

local Code = require("lalin.schema_v2.code")
local Graph = require("lalin.schema_v2.graph")
local Kernel = require("lalin.schema_v2.kernel")
local Stencil = require("lalin.schema_v2.stencil")
local CMat = require("lalin.schema_v2.c_materialize")
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
