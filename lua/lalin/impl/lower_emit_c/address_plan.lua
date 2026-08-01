-- Gate 3: materialize a closed executable C address plan from the exact
-- memory-use spine and coordinate facet.
require("lalin.schema_v2")
require("lalin.impl.lower_emit_c.coordinates")

local C = require("lalin.schema_v2.c")
local Stencil = require("lalin.schema_v2.stencil")
local CMat = require("lalin.schema_v2.c_materialize")
local Lower = require("lalin.schema_v2.lower")

local function append_one(values, value)
  local result = {}
  for i = 1, #values do result[i] = values[i] end
  result[#result + 1] = value
  return result
end

function CMat.CMatCAddressCollecting:cmat_address_add_use(entry)
  return CMat.CMatCAddressCollecting(
    self.spine, self.cursors, append_one(self.uses, entry), self.next_cursor)
end
function CMat.CMatCAddressAssemblyRejected:cmat_address_add_use(_entry)
  return self
end
function CMat.CMatCAddressCollecting:cmat_address_add_issue(issue)
  return CMat.CMatCAddressAssemblyRejected(self.spine, { issue })
end
function CMat.CMatCAddressAssemblyRejected:cmat_address_add_issue(issue)
  return CMat.CMatCAddressAssemblyRejected(
    self.spine, append_one(self.issues, issue))
end

function CMat.CMatCFragmentAccessDirect:cmat_address_base(_access)
  return CMat.CMatCCursorTypeReady(self.base.ty)
end
function C.CBackendDataPtr:cmat_cursor_type(_access)
  return CMat.CMatCCursorTypeReady(self)
end
function C.CBackendQualifiedDataPtr:cmat_cursor_type(_access)
  return CMat.CMatCCursorTypeReady(C.CBackendQualifiedDataPtr(
    self.pointee, self.const_pointee, false, self.volatile_pointee))
end
function C.CBackendType:cmat_cursor_type(access)
  return CMat.CMatCCursorTypeRejected(
    CMat.CMatCAddressInvalidPointerType(access, self))
end

function Stencil.StencilProducerForward:cmat_cursor_step_bytes(input)
  return input.plan.iteration.step_magnitude * input.coordinate.basis.index_scale_bytes
end
function Stencil.StencilProducerBackward:cmat_cursor_step_bytes(input)
  return -input.plan.iteration.step_magnitude * input.coordinate.basis.index_scale_bytes
end

function CMat.CMatCAddressCollecting:cmat_address_cursor_for_basis(input)
  local found = {}
  for i = 1, #self.cursors do
    if self.cursors[i].basis == input.coordinate.basis then
      found[#found + 1] = self.cursors[i]
    end
  end
  if #found > 1 then
    return self:cmat_address_add_issue(
      CMat.CMatCAddressCursorBaseDisagreement(input.coordinate.basis))
  end
  if #found == 1 then
    if found[1].base.id ~= input.binding.source.base.id then
      return self:cmat_address_add_issue(
        CMat.CMatCAddressCursorBaseDisagreement(input.coordinate.basis))
    end
    return self:cmat_address_add_use(CMat.CMatCUseAddressingEntry(
      input.use.id, CMat.CMatCCursorAddressing(
        found[1].id, input.coordinate.use_offset_bytes)))
  end
  return input.binding.source:cmat_address_base(input.use.access)
    :cmat_create_cursor(input)
end
function CMat.CMatCAddressAssemblyRejected:cmat_address_cursor_for_basis(_input)
  return self
end
function CMat.CMatCCursorTypeRejected:cmat_create_cursor(input)
  return input.assembly:cmat_address_add_issue(self.issue)
end
function CMat.CMatCCursorTypeReady:cmat_create_cursor(input)
  return self.ty:cmat_cursor_type(input.use.access):cmat_finish_cursor_type(input)
end
function CMat.CMatCCursorTypeRejected:cmat_finish_cursor_type(input)
  return input.assembly:cmat_address_add_issue(self.issue)
end
function CMat.CMatCCursorTypeReady:cmat_finish_cursor_type(input)
  local state = input.assembly
  local ordinal = state.next_cursor
  local text = input.plan.namespace.prefix .. "_cursor_" .. tostring(ordinal)
  local id = CMat.CMatCAddressCursorId(text)
  local local_id = C.CBackendLocalId(text)
  local cursor_local = C.CBackendLocal(local_id, C.CBackendName(text), self.ty)
  local cursor = CMat.CMatCAddressCursor(
    id, input.coordinate.basis, input.binding.source.base, cursor_local,
    input.coordinate.basis.induction.init,
    input.plan.iteration.order:cmat_cursor_step_bytes(input))
  local cursors = append_one(state.cursors, cursor)
  local uses = append_one(state.uses, CMat.CMatCUseAddressingEntry(
    input.use.id, CMat.CMatCCursorAddressing(
      id, input.coordinate.use_offset_bytes)))
  return CMat.CMatCAddressCollecting(
    state.spine, cursors, uses, ordinal + 1)
end

function Lower.LowerCMatAbsoluteCoordinate:cmat_materialize_addressing(input)
  if self.index_scale_bytes ~= input.binding.stride then
    return input.assembly:cmat_address_add_issue(
      CMat.CMatCAddressScaleDisagreement(input.use.access,
        self.index_scale_bytes, input.binding.stride))
  end
  return input.assembly:cmat_address_add_use(CMat.CMatCUseAddressingEntry(
    input.use.id, CMat.CMatCAbsoluteAddressing(
      input.binding.source.base, self.index, self.index_scale_bytes,
      self.const_offset_bytes)))
end
function Lower.LowerCMatIterationAffineCoordinate:cmat_materialize_addressing(input)
  if self.basis.index_scale_bytes ~= input.binding.stride then
    return input.assembly:cmat_address_add_issue(
      CMat.CMatCAddressScaleDisagreement(input.use.access,
        self.basis.index_scale_bytes, input.binding.stride))
  end
  return input.use.id:cmat_materialize_affine_addressing(input)
end
function CMat.CMatStreamMemoryUse:cmat_materialize_affine_addressing(input)
  return input.assembly:cmat_address_cursor_for_basis(input)
end
function CMat.CMatSinkMemoryUse:cmat_materialize_affine_addressing(input)
  return input.assembly:cmat_address_cursor_for_basis(input)
end
function CMat.CMatWindowMemoryUse:cmat_materialize_affine_addressing(input)
  return input.use.index:cmat_materialize_dynamic_window(input)
end
function CMat.CMatMemorySelectedIndex:cmat_materialize_dynamic_window(input)
  return input.assembly:cmat_address_add_issue(
    CMat.CMatCAddressInvalidUseIndex(input.use.id))
end
function CMat.CMatMemoryWindowOffset:cmat_materialize_dynamic_window(input)
  local scale = input.coordinate.basis.index_scale_bytes
  local const_offset = input.coordinate.use_offset_bytes - self.offset.offset * scale
  return input.assembly:cmat_address_add_use(CMat.CMatCUseAddressingEntry(
    input.use.id, CMat.CMatCDynamicWindowAddressing(
      input.binding.source.base, scale, const_offset)))
end

function CMat.CMatCAddressAssemblyRejected:cmat_finish_address_plan(_input)
  return CMat.CMatCAddressPlanRejected(self.issues)
end
function CMat.CMatCAddressCollecting:cmat_finish_address_plan(input)
  return CMat.CMatCAddressPlanReady(CMat.CMatCAddressPlan(
    self.spine, input.iteration, self.cursors, self.uses))
end

function Lower.LowerCMatCoordinateFacet:materialize_c_address_plan(input)
  if self.iteration ~= input.iteration then
    return CMat.CMatCAddressPlanRejected({
      CMat.CMatCAddressIterationDisagreement(self.iteration, input.iteration) })
  end
  local state = CMat.CMatCAddressCollecting(self.spine, {}, {}, 1)
  for i = 1, #self.spine.uses do
    local use = self.spine.uses[i]
    local coordinates = {}
    for j = 1, #self.entries do
      if self.entries[j].use == use.id then
        coordinates[#coordinates + 1] = self.entries[j].coordinate
      end
    end
    if #coordinates == 0 then
      state = state:cmat_address_add_issue(
        CMat.CMatCAddressMissingUse(use.id))
    elseif #coordinates > 1 then
      state = state:cmat_address_add_issue(
        CMat.CMatCAddressAmbiguousUse(use.id, #coordinates))
    else
      local bindings = {}
      for j = 1, #input.accesses.entries do
        if input.accesses.entries[j].access == use.access then
          bindings[#bindings + 1] = input.accesses.entries[j]
        end
      end
      if #bindings == 0 then
        state = state:cmat_address_add_issue(
          CMat.CMatCAddressMissingBinding(use.access))
      elseif #bindings > 1 then
        state = state:cmat_address_add_issue(
          CMat.CMatCAddressAmbiguousBinding(use.access, #bindings))
      else
        local use_input = CMat.CMatCAddressUseInput(
          use, bindings[1], coordinates[1], input, state)
        state = coordinates[1]:cmat_materialize_addressing(use_input)
      end
    end
  end
  return state:cmat_finish_address_plan(input)
end

function CMat.CMatCAddressPlan:lookup(use)
  local found = {}
  for i = 1, #self.uses do
    if self.uses[i].use == use then found[#found + 1] = self.uses[i] end
  end
  if #found == 0 then return CMat.CMatCAddressingMissing(use) end
  if #found > 1 then return CMat.CMatCAddressingAmbiguous(use, #found) end
  return CMat.CMatCAddressingFound(found[1])
end
function CMat.CMatCAddressPlan:cursor(cursor)
  local found = {}
  for i = 1, #self.cursors do
    if self.cursors[i].id == cursor then found[#found + 1] = self.cursors[i] end
  end
  if #found == 0 then return CMat.CMatCCursorMissing(cursor) end
  if #found > 1 then return CMat.CMatCCursorAmbiguous(cursor, #found) end
  return CMat.CMatCCursorFound(found[1])
end

return CMat
