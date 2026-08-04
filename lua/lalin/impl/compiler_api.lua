-- impl/compiler_api.lua
-- Root compiler API. CompilerSession:compile() is the public entry point.

local T = require("lalin.schema")
local Compiler = require("lalin.schema.compiler")
local Sem = require("lalin.schema.sem")
local Code = require("lalin.schema.code")
local Tr = require("lalin.schema.tree")
local Stencil = require("lalin.schema.stencil")
require("lalin.backend_target_model")(T) -- installs CBackendTarget:host_target_model for canonical target propagation
-- Ensure all phase methods are installed
require("lalin.impl.tree_surface")
require("lalin.impl.tree_closure")
require("lalin.impl.tree_check")
require("lalin.impl.tree_region")
require("lalin.impl.tree_code")
require("lalin.impl.code_graph")
require("lalin.impl.code_flow")
require("lalin.impl.code_value")
require("lalin.impl.code_mem")
require("lalin.impl.code_effect")
require("lalin.impl.kernel_plan")
require("lalin.impl.schedule_plan")
require("lalin.impl.stencil_kernel")
require("lalin.impl.lower_plan")
require("lalin.impl.lower_emit_c")
require("lalin.impl.cemit_emit")
require("lalin.impl.stencil_plan")
require("lalin.impl.stencil_reduction")
require("lalin.impl.stencil_c")
require("lalin.impl.exec_plan")

local CodeValidation = require("lalin.schema.code_validation")

function Compiler.CompilerCBackendRejected:compiler_emit_c_artifact()
  local issues = {}
  for i = 1, #self.issues do issues[i] = tostring(self.issues[i]) end
  return Compiler.CompilerArtifactError(
    "typed canonical C lowering rejected with " .. #issues
      .. " issue(s): " .. table.concat(issues, "; "))
end
function Compiler.CompilerCBackendEmitted:compiler_emit_c_artifact()
  local issues = self.backend.report.issues
  if #issues ~= 0 then
    local messages = {}
    for i = 1, #issues do messages[i] = tostring(issues[i]) end
    return Compiler.CompilerArtifactError(
      "c_backend_validate: " .. table.concat(messages, "; "))
  end
  local artifact = self.emitter:emit_module(self.backend.unit)
  return Compiler.CompilerArtifactC(artifact.source, artifact.header, self.backend.unit)
end

local function compile_validated(input)
  local code_module = input.module
  local contracts = input.contracts
  local code_result = Compiler.CodeResult(code_module, contracts, Sem.LayoutEnv({}))
  local request = Compiler.CompilerCCodegenRequest(
    code_result, input.target, Stencil.StencilCompilerPolicy(
      Stencil.StencilCompilerGcc, Stencil.StencilOptO3, {}))
  local backend = require("lalin.compiler_c_backend").code_result_to_c(request)
  return backend:compiler_emit_c_artifact()
end

function CodeValidation.CodeValidateOk:compiler_compile(input)
  return compile_validated(input)
end
function CodeValidation.CodeValidateFailed:compiler_compile(input)
  local msgs = {}
  for i = 1, #self.issues do msgs[#msgs + 1] = tostring(self.issues[i]) end
  return Compiler.CompilerArtifactError("code_validate: " .. #msgs .. " issue(s): " .. table.concat(msgs, "; "))
end

local function compile_after_closure(m, c_target)
  -- Public compile boundary: shared typed phase composition (typecheck +
  -- region facts + expansion + re-typecheck of the expanded module).  The
  -- pcall is a boundary guard only; failures become typed artifacts, never
  -- a fallback to an un-expanded or un-typed module.
  local ok, region_result = pcall(function() return m:typecheck_region_expanded() end)
  if not ok then return Compiler.CompilerArtifactError("typecheck: " .. tostring(region_result)) end
  if #(region_result:region_issues() or {}) > 0 then
    return Compiler.CompilerArtifactError("typecheck rejected with " .. tostring(#region_result:region_issues()) .. " issue(s)")
  end
  local checked = region_result:region_module()

  local host_target = c_target:host_target_model()
  local lower_ok, lowering = pcall(function()
    return checked:lower_tree_module_result_to_code({ target = host_target })
  end)
  if not lower_ok then return Compiler.CompilerArtifactError("lower_to_code: " .. tostring(lowering)) end
  local code_module = lowering.code_module
  local contracts = lowering.contracts

  local validate_mod = require("lalin.impl.code_validate")
  local validate_ok, validate_result = pcall(function() return validate_mod.validate(code_module) end)
  if not validate_ok then return Compiler.CompilerArtifactError("code_validate crashed: " .. tostring(validate_result)) end
  return validate_result:compiler_compile(Compiler.CompilerCodeGenerationInput(code_module, contracts, c_target))
end

function Sem.ClosureConverted:compiler_compile_after_closure(c_target) return compile_after_closure(self.module, c_target) end
function Sem.ClosureUnchanged:compiler_compile_after_closure(c_target) return compile_after_closure(self.module, c_target) end
function Sem.ClosureUnsupported:compiler_compile_after_closure(c_target)
  return Compiler.CompilerArtifactError("closure_convert: " .. self.reason)
end

-- Shared typed phase pipeline after a LalinTree.Module exists.  Both the
-- source session and the parsed/builder sessions converge here; failures
-- become typed artifacts, never a fallback to an un-typed module.
local function compile_tree_module(tree_module, source_name, c_target)
  -- Phase 1: Surface resolve
  local surface_ok, m = pcall(function() return tree_module:surface_resolve() end)
  if not surface_ok then
    return Compiler.CompilerArtifactError("surface_resolve: " .. tostring(m))
  end

  -- Phase 2: typed closure conversion with the selected C target's host projection.
  local host_target = c_target:host_target_model()
  local cc_ok, closure_result = pcall(function() return m:closure_convert(Sem.ClosureModuleInput(host_target)) end)
  if not cc_ok then return Compiler.CompilerArtifactError("closure_convert crashed: " .. tostring(closure_result)) end
  return closure_result:compiler_compile_after_closure(c_target)
end

function Compiler.CompilerModuleInputParsedDocument:compile_session_module()
  return require("lalin.syntax.document").to_module(self.document, self.source_name)
end
function Compiler.CompilerModuleInputParsedDecls:compile_session_module()
  return require("lalin.syntax.document").to_module(self.decls, self.source_name)
end
function Compiler.CompilerModuleInputTree:compile_session_module()
  return self.module
end

function Compiler.CompilerModuleInputParsedDocument:compile_session_source_name() return self.source_name end
function Compiler.CompilerModuleInputParsedDecls:compile_session_source_name() return self.source_name end
function Compiler.CompilerModuleInputTree:compile_session_source_name() return self.source_name end

-- Leaf-owned compile-input routing: the typed entry values produce their
-- own CompilerModuleInput leaf for the parsed session boundary.  The
-- public boundary calls these; there is no external class dispatch.
function T.LalinParse.ParsedDocument:compiler_module_input(name)
  return Compiler.CompilerModuleInputParsedDocument(self, name)
end
function Tr.Module:compiler_module_input(name)
  return Compiler.CompilerModuleInputTree(self, name)
end

function Compiler.CompilerArtifactC:compiler_require_c_artifact() return self end
function Compiler.CompilerArtifactError:compiler_require_c_artifact()
  error("emit_c: " .. tostring(self.message), 3)
end
function Compiler.CompilerSession:compile(c_target)
  local CodeType = require("lalin.impl.code_type")(T)
  c_target = CodeType.normalize_target(c_target)

  -- Parse source → LalinTree Module
  local Document = require("lalin.syntax.document")
  local parse_ok, doc = pcall(Document.parse, self.source_text, self.source_name)
  if not parse_ok then
    return Compiler.CompilerArtifactError("parse: " .. tostring(doc))
  end

  local module_ok, tree_module = pcall(Document.to_module, doc, self.source_name)
  if not module_ok then
    return Compiler.CompilerArtifactError("to_module: " .. tostring(tree_module))
  end
  return compile_tree_module(tree_module, self.source_name, c_target)
end

function Compiler.CompilerParsedSession:compile(c_target)
  local CodeType = require("lalin.impl.code_type")(T)
  c_target = CodeType.normalize_target(c_target)
  local module_ok, tree_module = pcall(function()
    return self.input:compile_session_module()
  end)
  if not module_ok then
    return Compiler.CompilerArtifactError("to_module: " .. tostring(tree_module))
  end
  return compile_tree_module(tree_module, self.input:compile_session_source_name(), c_target)
end



-- Compile a successful C artifact through the public IO boundary.
local function compile_c_artifact(result, opts, source_name, source_text)
  opts = opts or {}
  local source, header = result.source, result.header


  -- GCC path
  local ok, ffi = pcall(require, "ffi")
  if not ok or not ffi then
    return nil, "LuaJIT FFI not available; cannot dlopen shared object"
  end

  -- Ensure dlopen/dlsym/dlerror/dlclose cdef
  local ok_cdef, err_cdef = pcall(ffi.cdef, [[
void *dlopen(const char *filename, int flags);
void *dlsym(void *handle, const char *symbol);
int dlclose(void *handle);
char *dlerror(void);
]])
  if not ok_cdef then
    -- if redefinition, that's ok
    if not tostring(err_cdef):match("redefinition") then
      return nil, "FFI cdef failed: " .. tostring(err_cdef)
    end
  end

  -- Find compiler
  local cc = opts.cc or opts.compiler or os.getenv("LALIN_GCC") or os.getenv("CC") or "gcc"

  -- Check compiler availability
  local check_cmd = "'" .. cc .. "' --version >/dev/null 2>&1"
  local check_ok = os.execute(check_cmd)
  if check_ok ~= true and check_ok ~= 0 then
    -- Try finding vendored gcc
    local info = debug.getinfo(1, "S")
    local source_path = info and info.source
    if source_path and source_path:sub(1,1) == "@" then source_path = source_path:sub(2) end
    local repo_root = source_path and source_path:match("^(.-)/lua/lalin/impl/compiler_api%.lua$")
    if repo_root then
      local vendored = repo_root .. "/.vendor/gcc/.local/bin/gcc"
      local f = io.open(vendored, "r")
      if f then f:close(); cc = vendored end
    end
  end

  -- Write C files to temp dir
  local out_dir = opts.out_dir or opts.build_dir or "target/lalin_v2_gcc"
  os.execute("mkdir -p '" .. out_dir:gsub("'", "'\\''") .. "'")
  local stem = (opts.name or source_name or "lalin_v2"):gsub("[^%w_%-%.]", "_")
  if stem == "" then stem = "lalin_v2" end
  local suffix = tostring(os.time()) .. "_" .. tostring(math.random(1000000, 9999999))
  local c_path = out_dir .. "/" .. stem .. "_" .. suffix .. ".c"
  local so_path = out_dir .. "/" .. stem .. "_" .. suffix .. ".so"

  local f = io.open(c_path, "w")
  if not f then return nil, "cannot write " .. c_path end
  f:write(source)
  f:close()

  -- Build gcc command
  local opt_level = opts.opt or opts.O or 3
  local std = opts.std or "-std=c99"
  local gcc_cmd = table.concat({
    "'" .. cc .. "'",
    std,
    "-O" .. tostring(opt_level),
    "-fPIC", "-shared",
    "-o '" .. so_path:gsub("'", "'\\''") .. "'",
    "'" .. c_path:gsub("'", "'\\''") .. "'",
    "-lm",
  }, " ")

  -- Run gcc
  local pipe = io.popen(gcc_cmd .. " 2>&1", "r")
  if not pipe then return nil, "cannot spawn gcc" end
  local gcc_output = pipe:read("*a") or ""
  local gcc_ok, _, gcc_code = pipe:close()

  if not gcc_ok and not (gcc_code == 0) then
    return nil, "gcc compile failed (code=" .. tostring(gcc_code) .. "): " .. gcc_output
  end

  -- dlopen the shared object
  local handle = ffi.C.dlopen(so_path, 2) -- RTLD_NOW
  if handle == nil then
    local err = ffi.C.dlerror()
    return nil, "dlopen failed: " .. (err and ffi.string(err) or so_path)
  end

  -- Build session object
  local session = {
    _handle = handle,
    _freed = false,
    _source_text = source_text,
    _source_name = source_name,
    _c_path = c_path,
    _so_path = so_path,
    _cc = cc,
    _gcc_cmd = gcc_cmd,
    _gcc_output = gcc_output,
    _source = source,
    _header = header,
    -- Public runtime handle contract shared with the emit_c surface.
    c_path = c_path,
    so_path = so_path,
    artifact = {
      kind = "CBackendArtifact",
      source = source,
      header = header,
      combined = source,
      support = "",
    },
  }

  function session:symbol(name, ctype)
    assert(type(name) == "string" and name ~= "", "symbol name must be a non-empty string")
    if self._freed or self._handle == nil then
      return nil, "session has been freed"
    end
    ffi.C.dlerror()
    local ptr = ffi.C.dlsym(self._handle, name)
    if ptr == nil then
      local err = ffi.C.dlerror()
      return nil, err and ffi.string(err) or ("symbol not found: " .. name)
    end
    if ctype ~= nil then
      return ffi.cast(ctype, ptr)
    end
    return ptr
  end

  function session:free()
    if self._freed then return true end
    if self._handle ~= nil then
      ffi.C.dlclose(self._handle)
      self._handle = nil
    end
    self._freed = true
    return true
  end

  function session:get_source() return source end
  function session:get_header() return header end
  function session:get_c_path() return c_path end
  function session:get_so_path() return so_path end

  return session
end

function Compiler.CompilerArtifactC:compile_gcc_artifact(opts, source_name, source_text)
  return compile_c_artifact(self, opts, source_name, source_text)
end
function Compiler.CompilerArtifactError:compile_gcc_artifact(opts, source_name, source_text)
  return nil, self
end
function Compiler.CompilerSession:compile_gcc(opts)
  opts = opts or {}
  local CodeType = require("lalin.impl.code_type")(T)
  local target = CodeType.normalize_target(opts.c_target or opts.target or opts)
  return self:compile(target):compile_gcc_artifact(opts, self.source_name, self.source_text)
end

function Compiler.CompilerParsedSession:compile_gcc(opts)
  opts = opts or {}
  local CodeType = require("lalin.impl.code_type")(T)
  local target = CodeType.normalize_target(opts.c_target or opts.target or opts)
  local source_name = self.input:compile_session_source_name()
  -- No source text: the parsed input owns its typed module; the GCC artifact
  -- boundary only needs the source name for artifact stems.
  return self:compile(target):compile_gcc_artifact(opts, source_name, nil)
end

return Compiler
