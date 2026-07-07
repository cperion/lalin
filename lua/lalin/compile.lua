-- compile.lua
-- Public API entry point for the Lalin compiler.
-- Wires the pipeline to source loading and backend execution.

local pipeline = require("lalin.pipeline")

local function compile(source_text, opts)
  -- Load declarations from source text (lln document).
  -- In the full system this uses lalin.loadstring; here we return
  -- an artifact for the pipeline to consume.
  local decls = nil -- placeholder: requires lalin.loadstring integration
  return pipeline.compile_pipeline(decls, opts)
end

local function compile_c_gcc(name, decls, opts)
  -- Compile declarations to C, then GCC → shared object → dlopen/dlsym.
  local artifact = pipeline.compile_pipeline(decls, opts)

  -- The artifact should be compilable with GCC.
  -- In the full system, this delegates to emit_c_compile.lua.
  return artifact
end

return {
  compile = compile,
  compile_c_gcc = compile_c_gcc,
}
