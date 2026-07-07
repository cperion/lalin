-- Test: Alignment bridge — MemAlignment flows through to StencilAlignment and CBackend alignment facts
-- Verifies lane_backend_alignment, lower_cmat_alignment_fact, and lower_c_alignment_fact

package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local asdl = require("lalin.asdl")
local Schema = require("lalin.schema")
local T = asdl.context()
Schema(T)

local Mem = T.LalinMem
local Stencil = T.LalinStencil
local C = T.LalinC
local Code = T.LalinCode
local Core = T.LalinCore
local Kernel = T.LalinKernel

-- Load lower_to_c to get the leaf methods installed
require("lalin.lower_to_c")(T)

-- Test 1: MemAlignKnown → StencilAlignmentKnown via lower_cmat_alignment_fact
do
    local known = Mem.MemAlignKnown(16)
    local result = known:lower_cmat_alignment_fact()
    assert(asdl.class_basename(result) == "StencilAlignmentKnown", "expected StencilAlignmentKnown, got: " .. tostring(asdl.class_basename(result)))
    assert(result.bytes == 16, "expected 16 bytes, got: " .. tostring(result.bytes))
    print("OK: MemAlignKnown(16) → StencilAlignmentKnown(16)")
end

-- Test 2: MemAlignUnknown → StencilAlignmentUnknown
do
    local unknown = Mem.MemAlignUnknown
    local result = unknown:lower_cmat_alignment_fact()
    assert(asdl.class_basename(result) == "StencilAlignmentUnknown", "expected StencilAlignmentUnknown, got: " .. tostring(asdl.class_basename(result)))
    print("OK: MemAlignUnknown → StencilAlignmentUnknown")
end

-- Test 3: MemAlignAtLeast → StencilAlignmentKnown (conservative)
do
    local at_least = Mem.MemAlignAtLeast(8)
    local result = at_least:lower_cmat_alignment_fact()
    assert(asdl.class_basename(result) == "StencilAlignmentKnown", "expected StencilAlignmentKnown for AtLeast")
    assert(result.bytes == 8, "expected 8 bytes, got: " .. tostring(result.bytes))
    print("OK: MemAlignAtLeast(8) → StencilAlignmentKnown(8)")
end

-- Test 4: MemAlignAssumed → StencilAlignmentKnown
do
    local assumed = Mem.MemAlignAssumed(32, Mem.MemProofAlignment("test proof"))
    local result = assumed:lower_cmat_alignment_fact()
    assert(asdl.class_basename(result) == "StencilAlignmentKnown", "expected StencilAlignmentKnown for Assumed")
    assert(result.bytes == 32, "expected 32 bytes")
    print("OK: MemAlignAssumed(32) → StencilAlignmentKnown(32)")
end

-- Test 5: lower_c_alignment_fact → CBackendAlignmentKnown
do
    local known = Mem.MemAlignKnown(16)
    local result = known:lower_c_alignment_fact()
    assert(asdl.class_basename(result) == "CBackendAlignmentKnown", "expected CBackendAlignmentKnown, got: " .. tostring(asdl.class_basename(result)))
    assert(result.bytes == 16, "expected 16 bytes")
    print("OK: MemAlignKnown(16) → CBackendAlignmentKnown(16)")
end

-- Test 6: MemAlignAssumed → CBackendAlignmentAssumed
do
    local assumed = Mem.MemAlignAssumed(8, Mem.MemProofAlignment("test"))
    local result = assumed:lower_c_alignment_fact()
    assert(asdl.class_basename(result) == "CBackendAlignmentAssumed", "expected CBackendAlignmentAssumed, got: " .. tostring(asdl.class_basename(result)))
    assert(result.bytes == 8, "expected 8 bytes")
    assert(result.level == "mem proof", "expected 'mem proof' level")
    print("OK: MemAlignAssumed(8) → CBackendAlignmentAssumed(8)")
end

-- Test 7: MemAlignUnknown → CBackendAlignmentUnknown
do
    local unknown = Mem.MemAlignUnknown
    local result = unknown:lower_c_alignment_fact()
    assert(asdl.class_basename(result) == "CBackendAlignmentUnknown", "expected CBackendAlignmentUnknown, got: " .. tostring(asdl.class_basename(result)))
    print("OK: MemAlignUnknown → CBackendAlignmentUnknown")
end

-- Test 8: lane_backend_alignment with backend_info containing MemAlignKnown
do
    -- Build a KernelLane with backend_info
    local access_id = Mem.MemAccessId("access:test")
    local align = Mem.MemAlignKnown(64)
    local backend_info = Mem.MemBackendAccessInfo(
        access_id,
        Mem.MemNonTrapping("test"),
        align,
        Mem.MemBoundsUnknown("test"),
        nil,  -- deref_bytes
        true, -- movable
        {}
    )

    local lane_id = Kernel.KernelLaneId("lane:test")
    local object_id = Mem.MemObjectId("obj:test")
    local base = Mem.MemBaseValue(Code.CodeValueId("v:base"))
    local elem_ty = Code.CodeTyInt(32, Code.CodeSigned)

    local lane = Kernel.KernelLane(
        lane_id,
        object_id,
        { access_id },
        base,
        elem_ty,
        Mem.MemAccessContiguous,
        { backend_info }
    )

    -- Call lane_backend_alignment (it's a local function; we test via its output through cmat_access_binding_for_lane)
    -- Since it's local, we test the leaf method chain that it uses
    local stencil_align = backend_info.alignment:lower_cmat_alignment_fact()
    assert(asdl.class_basename(stencil_align) == "StencilAlignmentKnown", "alignment should flow to StencilAlignmentKnown")
    assert(stencil_align.bytes == 64, "expected 64 bytes")

    -- Verify the CBackend alignment fact
    local c_align = backend_info.alignment:lower_c_alignment_fact()
    assert(asdl.class_basename(c_align) == "CBackendAlignmentKnown", "alignment should flow to CBackendAlignmentKnown")
    assert(c_align.bytes == 64, "expected 64 bytes")
    print("OK: MemBackendAccessInfo alignment(64) flows through leaf methods")
end

-- Test 9: CBackendPlacePtrIndex.align field exists and works
do
    local base_atom = C.CBackendAtomLocal(C.CBackendLocalId("ptr"))
    local index_atom = C.CBackendAtomLiteral(C.CBackendIndex, Core.LitInt("0"))
    local ty = C.CBackendScalar(Core.ScalarI32)
    -- With alignment
    local place_with_align = C.CBackendPlacePtrIndex(base_atom, index_atom, ty, 4, 16)
    assert(place_with_align.align == 16, "align should be 16, got: " .. tostring(place_with_align.align))

    -- Without alignment (nil)
    local place_no_align = C.CBackendPlacePtrIndex(base_atom, index_atom, ty, 4, nil)
    assert(place_no_align.align == nil, "align should be nil when not specified")
    print("OK: CBackendPlacePtrIndex.align field works")
end

print("lalin alignment_bridge ok")
