package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local asdl = require("lalin.asdl")
local Schema = require("lalin.schema_projection")

local T = asdl.context()
Schema(T)

local dsl = require("lalin.dsl")(T)
local decl = dsl.to_unit("TargetProjection", dsl.loadstring([[
return {
  struct. Pair {
    x [i32],
    y [i32],
  },
  fn. add
    { a [i32], b [i32] }
    [i32]
    {
      ret (a + b),
    },
}
]], "typecheck-host-target-projection")())

local Pipeline = require("lalin.frontend_pipeline")(T)
local CodeType = require("lalin.code_type")(T)
local BackTarget = require("lalin.backend_target_model")(T)
local H, B = T.LalinHost, T.LalinBackend

local host_target = H.HostTargetModel(48, 24, H.HostEndianBig)
assert(host_target:host_target_model() == host_target)

local c_target = CodeType.default_target {
    dialect = "c11",
    pointer_bits = 32,
    index_bits = 16,
    endian = "big",
}
local c_host_target = c_target:host_target_model()
assert(c_host_target.pointer_bits == 32)
assert(c_host_target.index_bits == 16)
assert(c_host_target.endian == H.HostEndianBig)

local back_target = B.BackTargetModel(B.BackTargetNative, {
    B.BackTargetPointerBits(32),
    B.BackTargetIndexBits(16),
    B.BackTargetEndian(B.BackEndianBig),
})
local back_host_target = BackTarget.host_target(back_target)
assert(back_host_target.pointer_bits == 32)
assert(back_host_target.index_bits == 16)
assert(back_host_target.endian == H.HostEndianBig)

local checked = Pipeline.typecheck_module(decl:ast(), {
    c_target = {
        dialect = "c11",
        pointer_bits = 32,
        index_bits = 16,
        endian = "big",
    },
    site = "test_typecheck_host_target_projection",
})

assert(checked.module ~= nil)
assert(checked.target.pointer_bits == 32)
assert(checked.target.index_bits == 16)
assert(checked.target.endian == H.HostEndianBig)

local canonical_code = Pipeline.checked_to_code_result(checked, { root = "emit_c", c_target = c_target })
local canonical_outcome = Pipeline.code_result_to_c(canonical_code, { c_target = c_target })
assert(asdl.classof(canonical_outcome) == T.LalinCompiler.CompilerCBackendEmitted)
local canonical_c = canonical_outcome.backend
assert(asdl.classof(canonical_c) == T.LalinCompiler.CompilerCBackendResult)
assert(asdl.classof(canonical_c.unit) == T.LalinC.CBackendUnit)
assert(asdl.classof(canonical_c.report) == T.LalinC.CBackendValidationReport)

local lalin = require("lalin")
local public_decls = assert(lalin.loadstring([=[
struct Pair
  x [i32]
  y [i32]
end

fn add(a [i32], b [i32]) [i32] do
  return a + b
end
]=], "@public-target-projection.lln"))
local artifact = lalin.emit_c(public_decls, {
    name = "public_target_projection",
    c_target = {
        dialect = "c11",
        pointer_bits = 32,
        index_bits = 16,
        endian = "big",
    },
})
-- Typed artifact contract: emit_c exposes the normalized CBackendTarget and
-- the schema-v2 context so callers can inspect the host projection.
local public_target = artifact.target
local CB = package.loaded["lalin.schema_v2.c"]
assert(public_target.pointer_bits == 32)
assert(public_target.index_bits == 16)
assert(public_target.endian == CB.CBackendBigEndian)

io.write("lalin typecheck host target projection ok\n")
