-- Exact CMat memory-use coordinate projection. Gate 2 derives coordinates only;
-- executable C address selection and cursor emission belong to Gate 3.
require("lalin.schema_v2")
require("lalin.impl.code_mem")

local Flow = require("lalin.schema_v2.flow")
local Mem = require("lalin.schema_v2.mem")
local Stencil = require("lalin.schema_v2.stencil")
local CMat = require("lalin.schema_v2.c_materialize")
local Lower = require("lalin.schema_v2.lower")

local function append_one(values, value)
  local result = {}
  for i = 1, #values do result[i] = values[i] end
  result[#result + 1] = value
  return result
end

function CMat.CMatMemoryUse:lower_cmat_coordinate(input)
  local found = {}
  for i = 1, #input.provenance.entries do
    local entry = input.provenance.entries[i]
    if Stencil.StencilAccessRef(entry.access.name) == self.access then
      found[#found + 1] = entry
    end
  end
  if #found == 0 then
    return Lower.LowerCMatUseCoordinateRejected(
      Lower.LowerCMatCoordinateAccessMissing(self.id, self.access))
  end
  if #found > 1 then
    return Lower.LowerCMatUseCoordinateRejected(
      Lower.LowerCMatCoordinateAccessAmbiguous(
        self.id, self.access, #found))
  end
  return found[1]:lower_cmat_coordinate_memory(
    Lower.LowerCMatLaneCoordinateInput(self, input.iteration, input.memory))
end

function Stencil.StencilAccessByKernelLaneEntry:lower_cmat_coordinate_memory(input)
  local lane = self.lane
  if #lane.accesses == 0 then
    return Lower.LowerCMatUseCoordinateRejected(
      Lower.LowerCMatCoordinateLaneMemoryMissing(input.use.id, lane.id))
  end
  if #lane.accesses > 1 then
    return Lower.LowerCMatUseCoordinateRejected(
      Lower.LowerCMatCoordinateLaneMemoryAmbiguous(
        input.use.id, lane.id, #lane.accesses))
  end
  local access_id = lane.accesses[1]
  local found = {}
  for i = 1, #input.memory.access_by_id do
    local memory = input.memory.access_by_id[i].access
    if memory.id == access_id then found[#found + 1] = memory end
  end
  if #found == 0 then
    return Lower.LowerCMatUseCoordinateRejected(
      Lower.LowerCMatCoordinateMemoryFactMissing(input.use.id, access_id))
  end
  if #found > 1 then
    return Lower.LowerCMatUseCoordinateRejected(
      Lower.LowerCMatCoordinateMemoryFactAmbiguous(
        input.use.id, access_id, #found))
  end
  return Lower.LowerCMatUseMemoryFact(
    input.use, input.iteration, self, found[1]):lower_cmat_coordinate_fact()
end

function Lower.LowerCMatUseMemoryFact:lower_cmat_coordinate_fact()
  if self.provenance.lane.base ~= self.memory.base then
    return Lower.LowerCMatUseCoordinateRejected(
      Lower.LowerCMatCoordinateRootDisagreement(
        self.use.id, self.provenance.lane.base, self.memory.base))
  end
  return self.memory.index:lower_cmat_index_coordinate(
    Lower.LowerCMatIndexCoordinateInput(
      self.use, self.iteration, self.memory, self.memory.index))
end

function Mem.MemIndexNone:lower_cmat_index_coordinate(input)
  return Lower.LowerCMatUseCoordinateRejected(
    Lower.LowerCMatCoordinateIndexMissing(input.use.id))
end
function Mem.MemIndexValue:lower_cmat_index_coordinate(input)
  if self.elem_size <= 0 then
    return Lower.LowerCMatUseCoordinateRejected(
      Lower.LowerCMatCoordinateInvalidScale(input.use.id, self.elem_size))
  end
  return input.use.index:lower_cmat_value_coordinate(input)
end
function Mem.MemIndexInduction:lower_cmat_index_coordinate(input)
  if self.elem_size <= 0 then
    return Lower.LowerCMatUseCoordinateRejected(
      Lower.LowerCMatCoordinateInvalidScale(input.use.id, self.elem_size))
  end
  return input.use.index:lower_cmat_induction_coordinate(input)
end

function CMat.CMatMemoryWindowOffset:lower_cmat_value_coordinate(input)
  return Lower.LowerCMatUseCoordinateRejected(
    Lower.LowerCMatCoordinateInductionMissing(input.use.id, input.index))
end
function CMat.CMatMemorySelectedIndex:lower_cmat_value_coordinate(input)
  return self.selection:lower_cmat_value_coordinate(input)
end
function Stencil.StencilIndexProducer:lower_cmat_value_coordinate(input)
  return Lower.LowerCMatUseCoordinateRejected(
    Lower.LowerCMatCoordinateInductionMissing(input.use.id, input.index))
end
function Stencil.StencilIndexExplicit:lower_cmat_value_coordinate(input)
  return Lower.LowerCMatUseCoordinateProduced(
    Lower.LowerCMatUseCoordinateEntry(input.use.id,
      Lower.LowerCMatAbsoluteCoordinate(
        input.memory.base, self.index, input.index.elem_size,
        input.index.const_offset)))
end

function CMat.CMatMemoryWindowOffset:lower_cmat_induction_coordinate(input)
  if self.offset.axis.index ~= 1 then
    return Lower.LowerCMatUseCoordinateRejected(
      Lower.LowerCMatCoordinateWindowAxisDisagreement(
        input.use.id, self.offset))
  end
  local index = input.index
  return index.induction.role:lower_cmat_align_induction(
    Lower.LowerCMatInductionAlignmentInput(
      input.use, input.memory.base, input.iteration, index.induction,
      index.elem_size, index.const_offset + self.offset.offset * index.elem_size))
end
function CMat.CMatMemorySelectedIndex:lower_cmat_induction_coordinate(input)
  return self.selection:lower_cmat_induction_coordinate(input)
end
function Stencil.StencilIndexProducer:lower_cmat_induction_coordinate(input)
  local index = input.index
  return index.induction.role:lower_cmat_align_induction(
    Lower.LowerCMatInductionAlignmentInput(
      input.use, input.memory.base, input.iteration, index.induction,
      index.elem_size, index.const_offset))
end
function Stencil.StencilIndexExplicit:lower_cmat_induction_coordinate(input)
  return Lower.LowerCMatUseCoordinateProduced(
    Lower.LowerCMatUseCoordinateEntry(input.use.id,
      Lower.LowerCMatAbsoluteCoordinate(
        input.memory.base, self.index, input.index.elem_size,
        input.index.const_offset)))
end

local function induction_disagreement(input, axis)
  return Lower.LowerCMatUseCoordinateRejected(
    Lower.LowerCMatCoordinateInductionDisagreement(
      input.use.id, input.induction, input.iteration, axis))
end
function Flow.FlowPrimaryInduction:lower_cmat_align_induction(input)
  if input.induction.value ~= input.iteration.counter then
    return induction_disagreement(input, Lower.LowerCMatAlignmentCounter)
  end
  if input.induction.ty ~= input.iteration.index_ty then
    return induction_disagreement(input, Lower.LowerCMatAlignmentType)
  end
  if input.induction.init ~= input.iteration.start then
    return induction_disagreement(input, Lower.LowerCMatAlignmentInit)
  end
  if input.induction.step ~= input.iteration.step then
    return induction_disagreement(input, Lower.LowerCMatAlignmentStep)
  end
  local basis = Lower.LowerCMatAddressBasis(
    input.root, input.induction, input.index_scale_bytes)
  return Lower.LowerCMatUseCoordinateProduced(
    Lower.LowerCMatUseCoordinateEntry(input.use.id,
      Lower.LowerCMatIterationAffineCoordinate(
        basis, input.use_offset_bytes)))
end
function Flow.FlowDerivedInduction:lower_cmat_align_induction(input)
  return induction_disagreement(input, Lower.LowerCMatAlignmentRole)
end
function Flow.FlowPointerInduction:lower_cmat_align_induction(input)
  return induction_disagreement(input, Lower.LowerCMatAlignmentRole)
end

function Lower.LowerCMatUseCoordinateProduced:lower_cmat_collect_coordinates(state)
  return state:lower_cmat_add_coordinate(self.entry)
end
function Lower.LowerCMatUseCoordinateRejected:lower_cmat_collect_coordinates(state)
  return state:lower_cmat_add_coordinate_issue(self.issue)
end
function Lower.LowerCMatCoordinateCollecting:lower_cmat_add_coordinate(entry)
  return Lower.LowerCMatCoordinateCollecting(
    self.spine, append_one(self.entries, entry))
end
function Lower.LowerCMatCoordinateAssemblyRejected:lower_cmat_add_coordinate(_entry)
  return self
end
function Lower.LowerCMatCoordinateCollecting:lower_cmat_add_coordinate_issue(issue)
  return Lower.LowerCMatCoordinateAssemblyRejected(self.spine, { issue })
end
function Lower.LowerCMatCoordinateAssemblyRejected:lower_cmat_add_coordinate_issue(issue)
  return Lower.LowerCMatCoordinateAssemblyRejected(
    self.spine, append_one(self.issues, issue))
end
function Lower.LowerCMatCoordinateCollecting:lower_cmat_finish_coordinates()
  return Lower.LowerCMatCoordinatesProjected(
    Lower.LowerCMatCoordinateFacet(self.spine, self.entries))
end
function Lower.LowerCMatCoordinateAssemblyRejected:lower_cmat_finish_coordinates()
  return Lower.LowerCMatCoordinatesRejected(self.issues)
end

function CMat.CMatMemoryUseSpine:lower_coordinates(input)
  local state = Lower.LowerCMatCoordinateCollecting(self, {})
  for i = 1, #self.uses do
    state = self.uses[i]:lower_cmat_coordinate(input)
      :lower_cmat_collect_coordinates(state)
  end
  return state:lower_cmat_finish_coordinates()
end

function Lower.LowerCMatCoordinateFacet:lookup(use)
  local found = {}
  for i = 1, #self.entries do
    if self.entries[i].use == use then found[#found + 1] = self.entries[i] end
  end
  if #found == 0 then return Lower.LowerCMatUseCoordinateMissing(use) end
  if #found > 1 then
    return Lower.LowerCMatUseCoordinateAmbiguous(use, #found)
  end
  return Lower.LowerCMatUseCoordinateFound(found[1])
end

return Lower
