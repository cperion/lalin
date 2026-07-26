-- Typed stencil planning and validation leaf methods.
require("lalin.schema_v2")
local Stencil = require("lalin.schema_v2.stencil")
local CMat = require("lalin.schema_v2.c_materialize")

local function execution_axes(axes)
  local out = {}
  for _, axis in ipairs(axes) do
    out[#out + 1] = Stencil.StencilProducerExecutionAxis(
      axis.index_ty, axis.step, "start", "stop")
  end
  return out
end

function Stencil.StencilProduceRange1D:stencil_analyze_producer(input)
  return Stencil.StencilProducerAnalysisRange1D(
    Stencil.StencilProducerExecRange1D(self.step, self.order))
end
function Stencil.StencilProduceCountedRange1D:stencil_analyze_producer(input)
  return Stencil.StencilProducerAnalysisRange1D(
    Stencil.StencilProducerExecRange1D(self.step, self.order))
end
function Stencil.StencilProduceRangeND:stencil_analyze_producer(input)
  return Stencil.StencilProducerAnalysisRangeND(
    Stencil.StencilProducerExecRangeND(#self.axes, execution_axes(self.axes)))
end
function Stencil.StencilProduceWindowND:stencil_analyze_producer(input)
  return Stencil.StencilProducerAnalysisWindowND(
    Stencil.StencilProducerExecWindowND(#self.axes, execution_axes(self.axes), self.windows))
end
function Stencil.StencilProduceTiledND:stencil_analyze_producer(input)
  return Stencil.StencilProducerAnalysisTiledND(
    Stencil.StencilProducerExecTiledND(#self.axes, execution_axes(self.axes), self.tile_sizes))
end
function Stencil.StencilProducer:stencil_analyze(input)
  return self.shape:stencil_analyze_producer(input)
end

function Stencil.StencilValidationAccepted:stencil_combine(other) return other end
function Stencil.StencilValidationRejected:stencil_combine(other) return self end
function Stencil.StencilValidationAccepted:stencil_collect(rejects) return rejects end
function Stencil.StencilValidationRejected:stencil_collect(rejects)
  rejects[#rejects + 1] = self.reject
  return rejects
end

function Stencil.StencilStrideDynamic:stencil_validate_stride(input)
  return Stencil.StencilValidationAccepted
end
function Stencil.StencilStrideKnown:stencil_validate_stride(input)
  if self.bytes > 0 then return Stencil.StencilValidationAccepted end
  return Stencil.StencilValidationRejected(
    Stencil.StencilValidationInvalidStride(Stencil.StencilAccessRef(input.access.name), self.bytes))
end

function Stencil.StencilLayoutScalar:stencil_validate_base(input) return Stencil.StencilValidationAccepted end
function Stencil.StencilLayoutContiguous:stencil_validate_base(input)
  if self.stride > 0 then return Stencil.StencilValidationAccepted end
  return Stencil.StencilValidationRejected(
    Stencil.StencilValidationInvalidStride(Stencil.StencilAccessRef(input.access.name), self.stride))
end
function Stencil.StencilLayoutIndexed:stencil_validate_base(input) return self.parent:stencil_validate_base(input) end
function Stencil.StencilLayoutAffine1D:stencil_validate_base(input) return self.parent:stencil_validate_base(input) end
function Stencil.StencilLayoutAffineND:stencil_validate_base(input) return self.parent:stencil_validate_base(input) end
function Stencil.StencilLayoutFieldProjection:stencil_validate_base(input) return self.parent:stencil_validate_base(input) end
function Stencil.StencilLayoutSoAComponent:stencil_validate_base(input) return self.parent:stencil_validate_base(input) end

function Stencil.StencilLayoutSliceDescriptor:stencil_validate_descriptor(input) return Stencil.StencilValidationAccepted end
function Stencil.StencilLayoutByteSpanDescriptor:stencil_validate_descriptor(input) return Stencil.StencilValidationAccepted end
function Stencil.StencilLayoutForeignBuffer:stencil_validate_descriptor(input) return Stencil.StencilValidationAccepted end
function Stencil.StencilLayoutViewDescriptor:stencil_validate_descriptor(input)
  return self.stride_fact:stencil_validate_stride(input)
end
function Stencil.StencilAccessDirect:stencil_validate_access(input)
  return self.base:stencil_validate_base(input)
end
function Stencil.StencilAccessDescribed:stencil_validate_access(input)
  return self.base:stencil_validate_base(input):stencil_combine(
    self.descriptor:stencil_validate_descriptor(input))
end
function Stencil.StencilAccess:stencil_validate()
  return self.layout:stencil_validate_access(Stencil.StencilAccessValidationInput(self))
end

function Stencil.StencilSinkStore:stencil_validate_sink() return Stencil.StencilValidationAccepted end
function Stencil.StencilSinkReduce:stencil_validate_sink() return Stencil.StencilValidationAccepted end
function Stencil.StencilSinkScan:stencil_validate_sink() return Stencil.StencilValidationAccepted end
function Stencil.StencilSinkScatterReduce:stencil_validate_sink() return Stencil.StencilValidationAccepted end
function Stencil.StencilDescriptor:stencil_validate(input)
  local rejects = {}
  for _, access in ipairs(self.accesses) do access:stencil_validate():stencil_collect(rejects) end
  self.sink:stencil_validate_sink():stencil_collect(rejects)
  if #rejects == 0 then return Stencil.StencilDescriptorValid(self) end
  return Stencil.StencilDescriptorInvalid(self, rejects)
end

function Stencil.StencilSinkStore:stencil_build_descriptor(input)
  return Stencil.StencilDescriptorBuilt(Stencil.StencilDescriptor(input.producer, input.accesses, input.body, self))
end
function Stencil.StencilSinkReduce:stencil_build_descriptor(input)
  return Stencil.StencilDescriptorBuilt(Stencil.StencilDescriptor(input.producer, input.accesses, input.body, self))
end
function Stencil.StencilSinkScan:stencil_build_descriptor(input)
  return Stencil.StencilDescriptorBuilt(Stencil.StencilDescriptor(input.producer, input.accesses, input.body, self))
end
function Stencil.StencilSinkScatterReduce:stencil_build_descriptor(input)
  return Stencil.StencilDescriptorBuilt(Stencil.StencilDescriptor(input.producer, input.accesses, input.body, self))
end

function CMat.CMatMaterializedFused:stencil_codegen_plan() return Stencil.StencilCodegenCMat(self) end
function CMat.CMatRejectedComputation:stencil_codegen_plan() return Stencil.StencilCodegenCMat(self) end
function Stencil.StencilSelected:stencil_codegen(input)
  return input.computation:cmat_materialize(input.materialization):stencil_codegen_plan()
end
function Stencil.StencilNoSelection:stencil_codegen(input)
  return Stencil.StencilCodegenRejected(self.rejects)
end
