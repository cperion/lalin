package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path
local asdl = require("lalin.asdl")
require("lalin.schema_v2")
require("lalin.impl.stencil_plan")
require("lalin.impl.lower_emit_c.materialize")
require("lalin.impl.lower_emit_c.stencil")
local Code = require("lalin.schema_v2.code")
local Core = require("lalin.schema_v2.core")
local Stencil = require("lalin.schema_v2.stencil")
local CMat = require("lalin.schema_v2.c_materialize")
local C = require("lalin.schema_v2.c")

local i32 = Code.CodeTyInt(32, Code.CodeSigned)
local i32_backend = i32:code_to_c_backend_type()
assert(asdl.classof(i32_backend) == C.CBackendScalar)

-- Canonical bindings do not infer noalias from pointer-shaped layout.
local read_access = Stencil.StencilAccess("xs", Stencil.StencilAccessRead, i32,
  Stencil.StencilAccessDirect(Stencil.StencilLayoutContiguous(4)))
local read_binding = read_access:cmat_canonical_binding(
  CMat.CMatAccessBindingInput(CMat.CMatLocalId("xs")))
assert(asdl.classof(read_binding.restrict_capability) == CMat.CMatRestrictIneligible)
assert(read_binding.const_capability == CMat.CMatConstEligible)
local read_result = read_binding:cmat_c_access_binding()
assert(asdl.classof(read_result) == CMat.CMatCAccessCBindingReady)
local read_ptr = read_result.entry.param.ty
assert(asdl.classof(read_ptr) == C.CBackendQualifiedDataPtr)
assert(asdl.classof(read_ptr.pointee) == C.CBackendScalar)
assert(read_ptr.pointee.scalar == Core.ScalarI32)
assert(read_ptr.const_pointee == true)
assert(read_ptr.restrict_ptr == false)
assert(read_ptr.volatile_pointee == false)
assert(read_result.entry.stride == 4)

-- Canonical write access is neither const nor restrict without declared proof.
local write_access = Stencil.StencilAccess("out", Stencil.StencilAccessWrite, i32,
  Stencil.StencilAccessDirect(Stencil.StencilLayoutContiguous(4)))
local write_binding = write_access:cmat_canonical_binding(
  CMat.CMatAccessBindingInput(CMat.CMatLocalId("out")))
assert(asdl.classof(write_binding.const_capability) == CMat.CMatConstIneligible)
local write_result = write_binding:cmat_c_access_binding()
assert(asdl.classof(write_result) == CMat.CMatCAccessCBindingReady)
local write_ptr = write_result.entry.param.ty
assert(write_ptr.const_pointee == false)
assert(write_ptr.restrict_ptr == false)

-- A binding carrying explicit eligible capability emits restrict.
local crafted = CMat.CMatAccessBinding(
  Stencil.StencilAccessRef("crafted"), write_access, CMat.CMatLocalId("crafted"),
  i32, Stencil.StencilAccessDirect(Stencil.StencilLayoutContiguous(4)),
  CMat.CMatAccessReadOnly, CMat.CMatRestrictEligible,
  CMat.CMatConstEligible, Stencil.StencilAlignmentUnknown)
local crafted_result = crafted:cmat_c_access_binding()
assert(asdl.classof(crafted_result) == CMat.CMatCAccessCBindingReady)
local crafted_ptr = crafted_result.entry.param.ty
assert(crafted_ptr.restrict_ptr == true)
assert(crafted_ptr.const_pointee == true)

-- The qualified pointer composition is directly typed on the binding.
local direct = crafted:cmat_c_access_ptr_type(i32_backend)
assert(asdl.classof(direct) == C.CBackendQualifiedDataPtr)
assert(direct.const_pointee == true)
assert(direct.restrict_ptr == true)
assert(direct.volatile_pointee == false)

io.write("test_cmat_qualified_access_params: ok\n")
