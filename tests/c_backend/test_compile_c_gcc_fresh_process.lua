package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

-- Public compile_c_gcc fresh-process proof.
--
-- A fresh process must compile the public .lln surface through the typed
-- schema-v2 pipeline only: lalin.syntax_v2.document -> LalinTree Module ->
-- schema-v2 phases -> schema-v2 C backend -> GCC shared object.  The old
-- lower_to_c text lowering and the old driver chain that hosted it
-- (frontend_pipeline / compiler_canonical_c_backend / emit_c_materialize)
-- must not be pulled into the process by the public GCC path.
--
-- The emitted-C shape contract is asserted directly: public symbols are the
-- projected CodeFunc names (fn_ ids stay internal to the lower ASDL), and
-- the emitted source comes from the schema-v2 C backend.

local old_lowering_driver = {
  "lalin.lower_to_c",             -- old schema-projection C text lowering
  "lalin.emit_c_materialize",     -- old CMat materializer (lower_to_c driver)
  "lalin.frontend_pipeline",      -- old frontend-pipeline driver
  "lalin.compiler_canonical_c_backend", -- old canonical backend (requires lower_to_c)
  "lalin.tree_module_type",       -- legacy schema-bound module/layout projection
  "lalin.layout_resolve",         -- legacy schema-bound field/layout resolver
}

local function assert_no_old_lowering(where)
  for i = 1, #old_lowering_driver do
    assert(package.loaded[old_lowering_driver[i]] == nil,
      where .. " loaded old C lowering module " .. old_lowering_driver[i])
  end
end

assert_no_old_lowering("require(lalin)")

local lalin = require("lalin")

local src = [=[
struct Pair
  x [i32]
  y [i32]
end

fn add(a [i32], b [i32]) [i32] do
  return a + b
end

fn use_pair(p [ptr [Pair]]) [i32] do
  return p.x + p.y
end
]=]
local decls = assert(lalin.loadstring(src, "@compile_c_gcc_fresh.lln"))
assert_no_old_lowering("loadstring")

local session, c_src = lalin.compile_c_gcc("compile_c_gcc_fresh", decls, {
  gcc_opts = { opt = 3, out_dir = "target/test_compile_c_gcc_fresh" },
})
assert_no_old_lowering("compile_c_gcc")

-- The typed pipeline emitted the C text: public symbols are dlopen-visible.
assert(type(c_src) == "string" and c_src:find("int32_t add") ~= nil,
  "compile_c_gcc must return schema-v2 emitted C source")
assert(session.artifact and session.artifact.kind == "CBackendArtifact",
  "session must expose the typed CBackendArtifact")
assert(session.c_path and session.so_path, "session must expose cooked C/so paths")

local ffi = require("ffi")
local add = assert(session:symbol("add", "int32_t (*)(int32_t, int32_t)"))
assert(add(3, 4) == 7, "gcc-compiled schema-v2 emit_c symbol must execute")
local use_pair = assert(session:symbol("use_pair", "int32_t (*)(void *)"))
ffi.cdef("typedef struct { int32_t x; int32_t y; } lalin_fresh_pair;")
local pair = ffi.new("lalin_fresh_pair[1]")
pair[0].x, pair[0].y = 19, 23
assert(use_pair(pair) == 42, "typed struct field access must execute through GCC")
session:free()

-- The typed pipeline modules are the ones that ran.
assert(package.loaded["lalin.impl.compiler_api"] ~= nil, "typed compiler API must be loaded")
assert(package.loaded["lalin.schema_v2.compiler"] ~= nil, "schema-v2 compiler must be loaded")
assert(package.loaded["lalin.compiler_schema_v2_c_backend"] ~= nil, "schema-v2 C backend must be loaded")
assert(package.loaded["lalin.syntax_v2.document"] ~= nil, "syntax_v2 document must be loaded")
assert_no_old_lowering("final")

print("compile_c_gcc fresh-process typed pipeline proof ok")
