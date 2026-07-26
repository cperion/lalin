package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local asdl = require("lalin.asdl")
require("lalin.schema_v2")
require("lalin.impl.lower_plan")
require("lalin.impl.lower_emit_c.lower_sem")

local Code = require("lalin.schema_v2.code")
local Graph = require("lalin.schema_v2.graph")
local Kernel = require("lalin.schema_v2.kernel")
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
  { block(entry_id), block(body_id), block(exit_id) }, origin)
local loop_id = Graph.GraphLoopId("lower_cmat_sem_loop")
local loop = Graph.GraphLoop(
  loop_id, func_id, Graph.GraphBlockId(func_id, body_id),
  { Graph.GraphBlockId(func_id, body_id) }, {}, {})
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
