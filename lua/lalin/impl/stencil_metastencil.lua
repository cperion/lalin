-- Neutral stencil descriptor and metastencil projection methods.
require("lalin.schema_v2")
local Stencil = require("lalin.schema_v2.stencil")
local Descriptor = require("lalin.schema_v2.stencil_descriptor")

function Stencil.StencilDescriptor:metastencil_access(ref)
  for _, access in ipairs(self.accesses) do
    if access.name == ref.name then return Stencil.StencilAccessFound(access) end
  end
  return Stencil.StencilAccessMissing(ref, "descriptor has no access with that identity")
end
function Stencil.StencilReduceScopeDomain:metastencil_destination() return Stencil.StencilDestinationNone end
function Stencil.StencilReduceScopeAxes:metastencil_destination() return Stencil.StencilDestinationAccess(self.dst) end
function Stencil.StencilReduceScopeWindow:metastencil_destination() return Stencil.StencilDestinationAccess(self.dst) end

function Descriptor.StencilDescriptorValueResult:stencil_descriptor_validate_result() return Stencil.StencilValidationAccepted end
function Descriptor.StencilDescriptorStoreResult:stencil_descriptor_validate_result() return Stencil.StencilValidationAccepted end
function Descriptor.StencilDescriptorControlResult:stencil_descriptor_validate_result() return Stencil.StencilValidationAccepted end

local function projection_input(descriptor)
  local spine = descriptor.spine
  return Descriptor.StencilDescriptorProjectionInput(
    spine.id, spine.producer, spine.accesses, spine.streams, { descriptor.sink },
    spine.legality, spine.proofs)
end
function Descriptor.StencilDescriptorScheduled:stencil_project_schedule(input, descriptor)
  return Descriptor.StencilDescriptorProjected(Stencil.StencilComputation(
    input.id, input.producer, input.accesses, input.streams, input.sinks,
    input.legality, self.schedule, input.proofs))
end
function Descriptor.StencilDescriptorExplicitlyUnscheduled:stencil_project_schedule(input, descriptor)
  return Descriptor.StencilDescriptorProjectionRejected(descriptor, {
    Descriptor.StencilDescriptorProjectionUnscheduled(self.reason),
  })
end
local function project_descriptor(self)
  local contribution = self.result:stencil_descriptor_validate_result()
  local rejects = contribution:stencil_collect({})
  if #rejects > 0 then
    return Descriptor.StencilDescriptorProjectionRejected(self, {
      Descriptor.StencilDescriptorProjectionInvalidResult("descriptor result rejected"),
    })
  end
  return self.spine.schedule:stencil_project_schedule(projection_input(self), self)
end
function Descriptor.StencilDescriptorStore:stencil_project_computation() return project_descriptor(self) end
function Descriptor.StencilDescriptorReduce:stencil_project_computation() return project_descriptor(self) end
function Descriptor.StencilDescriptorScan:stencil_project_computation() return project_descriptor(self) end
function Descriptor.StencilDescriptorFind:stencil_project_computation() return project_descriptor(self) end
function Descriptor.StencilDescriptorPartition:stencil_project_computation() return project_descriptor(self) end
function Descriptor.StencilDescriptorCount:stencil_project_computation() return project_descriptor(self) end
function Descriptor.StencilDescriptorScatterReduce:stencil_project_computation() return project_descriptor(self) end
