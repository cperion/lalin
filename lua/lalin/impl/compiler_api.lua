-- impl/compiler_api.lua
-- Root compiler API. CompilerSession:compile() is the public entry point.

local T = require("lalin.schema_v2")
local Compiler = require("lalin.schema_v2.compiler")
local Sem = require("lalin.schema_v2.sem")
local Code = require("lalin.schema_v2.code")
local Tr = require("lalin.schema_v2.tree")
-- Ensure all phase methods are installed
require("lalin.impl.tree_surface")
require("lalin.impl.tree_closure")
require("lalin.impl.tree_check.init")
require("lalin.impl.tree_region")
require("lalin.impl.tree_code")
require("lalin.impl.code_graph")
require("lalin.impl.code_flow")
require("lalin.impl.code_value")
require("lalin.impl.code_mem")
require("lalin.impl.code_effect")
require("lalin.impl.kernel_plan")
require("lalin.impl.schedule_plan")
require("lalin.impl.lower_plan")
require("lalin.impl.lower_emit_c")
require("lalin.impl.cemit_emit")
require("lalin.impl.stencil_plan")
require("lalin.impl.stencil_reduction")
require("lalin.impl.stencil_metastencil")
require("lalin.impl.stencil_c")
require("lalin.impl.exec_plan")

local CodeValidation = require("lalin.schema_v2.code_validation")

local function compile_validated(input)
  local code_module = input.module
  local contracts = Code.CodeContractFactSet(code_module.id, input.contracts)
  local graph_ok, graph = pcall(function() return code_module:build_graph() end)
  if not graph_ok then return Compiler.CompilerArtifactError("build_graph: " .. tostring(graph)) end
  local flow = graph:compute_flow(code_module)
  local values = graph:compute_values(code_module, flow)
  local mem = graph:compute_mem(code_module, flow, values, contracts)
  local effect_analysis = graph:compute_effect_analysis(code_module, mem, contracts)
  local effects = effect_analysis.facts
  local kernels = mem:plan_kernels(flow, values, mem, effects)
  local schedules = kernels:plan_schedules(code_module, flow, values, mem, effects)
  local lower_plan = code_module:plan_lowering(graph, kernels, schedules)
  local c_unit = lower_plan:emit_c(code_module)
  local Cemit = require("lalin.schema_v2.cemit")
  local C_schema = require("lalin.schema_v2.c")
  local Lower_schema = require("lalin.schema_v2.lower")
  local target = C_schema.CBackendTarget(C_schema.CBackendC99, C_schema.CBackendHostedNative, 64, 64, C_schema.CBackendLittleEndian, true)
  local spine = Lower_schema.LowerBackSpine(code_module, graph, target)
  local artifact = Cemit.CEmitMachine(spine, {}, {}, {}, {}):emit_module(c_unit)
  return Compiler.CompilerArtifactC(artifact.source, artifact.header)
end

function CodeValidation.CodeValidateOk:compiler_compile(input)
  return compile_validated(input)
end
function CodeValidation.CodeValidateFailed:compiler_compile(input)
  local msgs = {}
  for i = 1, #self.issues do msgs[#msgs + 1] = tostring(self.issues[i]) end
  return Compiler.CompilerArtifactError("code_validate: " .. #msgs .. " issue(s): " .. table.concat(msgs, "; "))
end

local function compile_after_closure(m)
  local check_ok, checked = pcall(function() return m:typecheck({}) end)
  if not check_ok then return Compiler.CompilerArtifactError("typecheck: " .. tostring(checked)) end
  local region_facts = checked:region_fact_projection()
  local region_result = checked:region_expand(Tr.RegionModuleExpansionInput(region_facts))
  if #(region_result:region_issues() or {}) > 0 then
    return Compiler.CompilerArtifactError("region expansion rejected: " .. tostring(#region_result:region_issues()) .. " issue(s)")
  end
  checked = region_result:region_module()

  local T = require("lalin.schema_v2")
  local backend_target = require("lalin.backend_target_model")(T)
  local back_target = backend_target.default_native()
  local host_target = backend_target.host_target(back_target)
  local lower_ok, lowering = pcall(function()
    return checked:lower_tree_module_result_to_code({ target = host_target })
  end)
  if not lower_ok then return Compiler.CompilerArtifactError("lower_to_code: " .. tostring(lowering)) end
  local code_module = lowering.code_module
  local contracts = lowering.contracts.facts

  local validate_mod = require("lalin.impl.code_validate")
  local validate_ok, validate_result = pcall(function() return validate_mod.validate(code_module) end)
  if not validate_ok then return Compiler.CompilerArtifactError("code_validate crashed: " .. tostring(validate_result)) end
  return validate_result:compiler_compile(Compiler.CompilerCodeGenerationInput(code_module, contracts))
end

function Sem.ClosureConverted:compiler_compile_after_closure() return compile_after_closure(self.module) end
function Sem.ClosureUnchanged:compiler_compile_after_closure() return compile_after_closure(self.module) end
function Sem.ClosureUnsupported:compiler_compile_after_closure()
  return Compiler.CompilerArtifactError("closure_convert: " .. self.reason)
end

function Compiler.CompilerSession:compile()

  -- Parse source → LalinTree Module
  local Document = require("lalin.syntax_v2.document")
  local parse_ok, doc = pcall(Document.parse, self.source_text, self.source_name)
  if not parse_ok then
    return Compiler.CompilerArtifactError("parse: " .. tostring(doc))
  end

  local module_ok, tree_module = pcall(Document.to_module, doc, self.source_name)
  if not module_ok then
    return Compiler.CompilerArtifactError("to_module: " .. tostring(tree_module))
  end

  -- Phase 1: Surface resolve
  local surface_ok, m = pcall(function() return tree_module:surface_resolve() end)
  if not surface_ok then
    return Compiler.CompilerArtifactError("surface_resolve: " .. tostring(m))
  end

  -- Phase 2: typed closure conversion with the selected host target.
  local backend_target = require("lalin.backend_target_model")(T)
  local host_target = backend_target.host_target(backend_target.default_native())
  local cc_ok, closure_result = pcall(function() return m:closure_convert(Sem.ClosureModuleInput(host_target)) end)
  if not cc_ok then return Compiler.CompilerArtifactError("closure_convert crashed: " .. tostring(closure_result)) end
  return closure_result:compiler_compile_after_closure()
end


-- Compile a successful C artifact through the public IO boundary.
local function compile_c_artifact(result, opts, source_name, source_text)
  opts = opts or {}
  local source, header = result.source, result.header

  -- Attempt TCC first if preferred
  local use_tcc = opts.use_tcc or opts.runner == "libtcc" or os.getenv("LALIN_V2_USE_TCC") == "1"
  if use_tcc then
    local ok_tcc, tcc_mod = pcall(require, "lalin.emit_c_tcc")
    if ok_tcc and tcc_mod and tcc_mod.compile then
      local session, err = tcc_mod.compile(source, opts.libtcc_opts or { libraries = { "m" } })
      if session then return session end
      -- TCC failed, fall through to GCC
    end
  end

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
  return self:compile():compile_gcc_artifact(opts, self.source_name, self.source_text)
end

return Compiler
