package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local asdl = require("lalin.asdl")
require("lalin.schema_v2")
require("lalin.impl.lower_emit_c")

local Code = require("lalin.schema_v2.code")
local Mem = require("lalin.schema_v2.mem")
local Kernel = require("lalin.schema_v2.kernel")
local Stencil = require("lalin.schema_v2.stencil")
local CMat = require("lalin.schema_v2.c_materialize")
local C = require("lalin.schema_v2.c")
local Lower = require("lalin.schema_v2.lower")

local i32 = Code.CodeTyInt(32, Code.CodeSigned)
local access_id = Mem.MemAccessId("fusion-contract-access")
local access = Stencil.StencilAccess(
  "xs", Stencil.StencilAccessRead, i32,
  Stencil.StencilAccessDirect(Stencil.StencilLayoutContiguous(4)))
local binding = CMat.CMatAccessBinding(
  Stencil.StencilAccessRef("xs"), access, CMat.CMatLocalId("xs"), i32,
  access.layout, CMat.CMatAccessReadOnly, CMat.CMatRestrictIneligible("fixture"),
  CMat.CMatConstEligible, Stencil.StencilAlignmentKnown(4))
local target = C.CBackendTarget(
  C.CBackendC99, C.CBackendHostedNative, 64, 64, C.CBackendLittleEndian)
local request = Lower.LowerCMatAccessBuildRequest(
  { binding }, Stencil.StencilAccessByKernelLaneProjection({}),
  CMat.CMatCExternalValueBindingProjection({}), target)

local function contract_evidence(backend)
  local lane = Kernel.KernelLane(
    Kernel.KernelLaneId("fusion-contract-lane"),
    Mem.MemObjectId("fusion-contract-object"), { access_id },
    Mem.MemBaseValue(Code.CodeValueId("xs")), i32,
    Mem.MemAccessContiguous, { backend })
  return Lower.LowerCMatAccessEvidence(
    request, binding, Stencil.StencilAccessByKernelLaneEntry(lane, access),
    access_id, backend, 4, 4, Lower.LowerCMatAccessCollection({}), 2)
end

local function backend(bounds, trap, movement)
  return Mem.MemBackendAccessInfo(
    access_id, trap, Mem.MemAlignKnown(4), bounds,
    Mem.MemDerefBytesKnown(4), movement, {})
end

local valid = contract_evidence(backend(
  Mem.MemBoundsInObject("declared object bounds"),
  Mem.MemNonTrapping("declared nontrapping"),
  Mem.MemMovementMovable("declared movable")))
assert(valid.backend.bounds:lower_cmat_admit_contract(valid) ==
  Lower.LowerCMatAccessContractAdmitted)

local unknown = contract_evidence(backend(
  Mem.MemBoundsUnknown("no bounds evidence"),
  Mem.MemNonTrapping("declared nontrapping"),
  Mem.MemMovementMovable("declared movable")))
assert(asdl.classof(unknown.backend.bounds:lower_cmat_admit_contract(unknown)) ==
  Lower.LowerCMatAccessContractRejected)

local trapping = contract_evidence(backend(
  Mem.MemBoundsInObject("declared object bounds"), Mem.MemMayTrap,
  Mem.MemMovementMovable("declared movable")))
assert(asdl.classof(trapping.backend.bounds:lower_cmat_admit_contract(trapping)) ==
  Lower.LowerCMatAccessContractRejected)

local pinned = contract_evidence(backend(
  Mem.MemBoundsInObject("declared object bounds"),
  Mem.MemNonTrapping("declared nontrapping"),
  Mem.MemMovementPinned("ordered access")))
assert(asdl.classof(pinned.backend.bounds:lower_cmat_admit_contract(pinned)) ==
  Lower.LowerCMatAccessContractRejected)

print("schema_v2 CMat fusion contract admission ok")
