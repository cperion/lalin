package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path
local asdl = require("lalin.asdl")
require("lalin.schema_v2")
require("lalin.impl.stencil_plan")
local Code = require("lalin.schema_v2.code")
local Stencil = require("lalin.schema_v2.stencil")
local i32 = Code.CodeTyInt(32, Code.CodeSigned)
local base = Stencil.StencilLayoutContiguous(4)
local direct = Stencil.StencilAccessDirect(base)
local described = Stencil.StencilAccessDescribed(base, Stencil.StencilLayoutViewDescriptor(
  Code.CodeValueId("view"), Code.CodeValueId("data"), Code.CodeValueId("len"),
  Code.CodeValueId("stride"), Stencil.StencilStrideKnown(4)))
assert(asdl.classof(direct) == Stencil.StencilAccessDirect)
assert(asdl.classof(described) == Stencil.StencilAccessDescribed)
local access = Stencil.StencilAccess("xs", Stencil.StencilAccessRead, i32, described)
assert(access:stencil_validate() == Stencil.StencilValidationAccepted)
local bad = Stencil.StencilAccess("bad", Stencil.StencilAccessRead, i32,
  Stencil.StencilAccessDescribed(base, Stencil.StencilLayoutViewDescriptor(
    Code.CodeValueId("v2"), Code.CodeValueId("d2"), Code.CodeValueId("n2"),
    Code.CodeValueId("s2"), Stencil.StencilStrideKnown(0))))
assert(asdl.classof(bad:stencil_validate()) == Stencil.StencilValidationRejected)
io.write("test_stencil_access_layout_alternatives: ok\n")
