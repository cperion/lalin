package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local asdl = require("lalin.asdl")
require("lalin.schema_v2")
require("lalin.impl.lower_emit_c.coordinates")

local Code = require("lalin.schema_v2.code")
local Graph = require("lalin.schema_v2.graph")
local Flow = require("lalin.schema_v2.flow")
local Mem = require("lalin.schema_v2.mem")
local Stencil = require("lalin.schema_v2.stencil")
local CMat = require("lalin.schema_v2.c_materialize")
local Lower = require("lalin.schema_v2.lower")

local module_id = Code.CodeModuleId("module:window-footprint")
local func = Code.CodeFuncId("fn:window-footprint")
local base = Code.CodeValueId("base")
local base_len = Code.CodeValueId("base_len")
local start = Code.CodeValueId("start")
local stop = Code.CodeValueId("stop")
local trip = Code.CodeValueId("trip")
local counter = Code.CodeValueId("counter")
local step_value = Code.CodeValueId("step")
local loop = Graph.GraphLoopId("loop:window-footprint")
local i32 = Code.CodeTyInt(32, Code.CodeSigned)
local origin = Code.CodeOriginGenerated("window footprint test")
local extent = Stencil.StencilWindowExtent(
  Stencil.StencilElementDistance(1), Stencil.StencilElementDistance(2))
local contract_extent = Code.CodeWindowFootprintExtent(
  Code.CodeWindowFootprintDistance(1), Code.CodeWindowFootprintDistance(2))

local function contract(order, step, contract_start, contract_trip, ext)
  return Code.CodeContractWindowFootprint(
    base, base_len, contract_start or start, contract_trip or trip,
    order, Code.CodeWindowFootprintStep(step), ext or contract_extent)
end

local function projection(entries)
  local facts = {}
  for i = 1, #entries do
    facts[i] = Code.CodeFuncContractFact(func, entries[i], origin)
  end
  return Code.CodeContractFactSet(module_id, facts):project_memory_contract()
:project_window_footprints()
end

local forward_iteration = Stencil.StencilKernelIteration(
  loop, counter, i32, start, stop, step_value, 2,
  Stencil.StencilIterationStopExclusive, Stencil.StencilProducerForward,
  Stencil.StencilKernelTripExact(Flow.FlowTripCountExact(trip, nil, nil)))
local use_id = CMat.CMatWindowMemoryUse(
  Stencil.StencilStreamRef(Stencil.StencilStreamId("window")), 1)
local validate_input = Lower.LowerCMatWindowFootprintValidateInput(
  use_id, forward_iteration, extent)
local contracts = projection({
  contract(Code.CodeWindowFootprintForward, 2),
})

local lookup = contracts:lookup_window_footprint(
  Mem.MemWindowFootprintLookupInput(func, Mem.MemBaseValue(base)))
assert(asdl.classof(lookup) == Mem.MemWindowFootprintFound)
local proven = lookup:lower_cmat_validate_window_footprint(validate_input)
assert(asdl.classof(proven) == Lower.LowerCMatWindowFootprintProven)
assert(proven.contract == contracts.entries[1])
assert(proven.contract.base_len == base_len)

local induction = Flow.FlowInduction(
  counter, i32, start, step_value, Flow.FlowPrimaryInduction,
  Flow.FlowRangeUnknown(counter))
local memory_use = CMat.CMatMemoryUse(
  use_id, Stencil.StencilAccessRef("xs"), CMat.CMatMemoryLoad,
  CMat.CMatMemoryWindowOffset(Stencil.StencilWindowOffset(
    Stencil.StencilAxisRef(1), Stencil.StencilElementDistance(-1))))
local provenance = Lower.LowerCMatWindowCoordinateProvenance(
  memory_use.index.offset, extent, Stencil.StencilWindowBoundaryClamp)
local basis = Lower.LowerCMatAddressBasis(Mem.MemBaseValue(base), induction, 4)
local relative = proven:lower_cmat_select_aligned_window(
  Lower.LowerCMatAlignedWindowCoordinateInput(
    memory_use, basis, 8, provenance))
assert(asdl.classof(relative) == Lower.LowerCMatUseCoordinateProduced)
assert(asdl.classof(relative.entry.coordinate) ==
  Lower.LowerCMatWindowRelativeCoordinate)
assert(relative.entry.coordinate.use_offset_bytes == 4,
  "declared footprint must permit exact signed element displacement")

local function rejected_axis(fact, iteration, stencil_extent, expected)
  local p = projection({ fact })
  local found = p:lookup_window_footprint(
    Mem.MemWindowFootprintLookupInput(func, Mem.MemBaseValue(base)))
  local result = found:lower_cmat_validate_window_footprint(
    Lower.LowerCMatWindowFootprintValidateInput(
      use_id, iteration or forward_iteration, stencil_extent or extent))
  assert(asdl.classof(result) == Lower.LowerCMatWindowFootprintRejected)
  assert(asdl.classof(result.issue) ==
    Lower.LowerCMatCoordinateWindowFootprintDisagreement)
  assert(result.issue.axis == expected)
end

rejected_axis(
  contract(Code.CodeWindowFootprintForward, 2, Code.CodeValueId("other_start")),
  nil, nil, Lower.LowerCMatWindowFootprintStart)
rejected_axis(
  contract(Code.CodeWindowFootprintForward, 3),
  nil, nil, Lower.LowerCMatWindowFootprintStep)
rejected_axis(
  contract(Code.CodeWindowFootprintForward, 2, nil, Code.CodeValueId("other_trip")),
  nil, nil, Lower.LowerCMatWindowFootprintTrip)
rejected_axis(
  contract(Code.CodeWindowFootprintBackward, 2),
  nil, nil, Lower.LowerCMatWindowFootprintOrder)
rejected_axis(
  contract(Code.CodeWindowFootprintForward, 2, nil, nil,
    Code.CodeWindowFootprintExtent(
      Code.CodeWindowFootprintDistance(2),
      Code.CodeWindowFootprintDistance(2))),
  nil, nil, Lower.LowerCMatWindowFootprintExtent)

local backward_iteration = Stencil.StencilKernelIteration(
  loop, counter, i32, start, stop, step_value, 3,
  Stencil.StencilIterationStopExclusive, Stencil.StencilProducerBackward,
  Stencil.StencilKernelTripNonNegative(
    Flow.FlowTripCountNonNegative(trip, nil, nil)))
local backward = projection({
  contract(Code.CodeWindowFootprintBackward, 3),
}):lookup_window_footprint(
  Mem.MemWindowFootprintLookupInput(func, Mem.MemBaseValue(base)))
:lower_cmat_validate_window_footprint(
  Lower.LowerCMatWindowFootprintValidateInput(
    use_id, backward_iteration, extent))
assert(asdl.classof(backward) == Lower.LowerCMatWindowFootprintProven,
  "backward non-unit authored footprints must validate exactly")

local missing = contracts:lookup_window_footprint(
  Mem.MemWindowFootprintLookupInput(func, Mem.MemBaseValue(
    Code.CodeValueId("other_base"))))
:lower_cmat_validate_window_footprint(validate_input)
assert(missing == Lower.LowerCMatWindowFootprintAbsent)

local ambiguous = projection({
  contract(Code.CodeWindowFootprintForward, 2),
  contract(Code.CodeWindowFootprintForward, 2),
}):lookup_window_footprint(
  Mem.MemWindowFootprintLookupInput(func, Mem.MemBaseValue(base)))
:lower_cmat_validate_window_footprint(validate_input)
assert(asdl.classof(ambiguous) == Lower.LowerCMatWindowFootprintRejected)
assert(asdl.classof(ambiguous.issue) ==
  Lower.LowerCMatCoordinateWindowFootprintAmbiguous)

print("schema_v2 CMat window footprint ok")
