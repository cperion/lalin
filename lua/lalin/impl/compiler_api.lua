-- impl/compiler_api.lua
-- Root compiler API. CompilerSession:compile() is the public entry point.

require("lalin.schema_v2")
local Compiler = require("lalin.schema_v2.compiler")

-- Ensure all phase methods are installed
require("lalin.impl.tree_surface")
require("lalin.impl.tree_closure")
require("lalin.impl.tree_check.init")
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
require("lalin.impl.stencil_machine")
require("lalin.impl.stencil_metastencil")
require("lalin.impl.stencil_c")
require("lalin.impl.exec_plan")

function Compiler.CompilerSession:compile()
  -- Reset module-level state to prevent cross-compilation leaks
  require("lalin.schema_v2.tree_code").reset_module_sig_state()

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

  -- Phase 2: Closure convert
  local cc_ok, m2 = pcall(function() return m:closure_convert() end)
  if not cc_ok then
    return Compiler.CompilerArtifactError("closure_convert: " .. tostring(m2))
  end
  m = m2

  -- Phase 3: Typecheck
  local check_ok, checked = pcall(function() return m:typecheck({}) end)
  if not check_ok then
    return Compiler.CompilerArtifactError("typecheck: " .. tostring(checked))
  end

  -- Phase 4: Lower to code
  local T = require("lalin.schema_v2")
  local backend_target = require("lalin.backend_target_model")(T)
  local back_target = backend_target.default_native()
  local host_target = backend_target.host_target(back_target)
  local lower_ok, code_module, contracts = pcall(function()
    return checked:lower_tree_module_with_contracts_to_code({ target = host_target })
  end)
  if not lower_ok then
    return Compiler.CompilerArtifactError("lower_to_code: " .. tostring(code_module))
  end
  if contracts == nil then contracts = {} end

  -- Code validation gate
  local validate_mod = require("lalin.impl.code_validate")
  local validate_ok, validate_result = pcall(function()
    return validate_mod.validate(code_module)
  end)
  if not validate_ok then
    return Compiler.CompilerArtifactError("code_validate crashed: " .. tostring(validate_result))
  end
  -- validate_result is CodeValidateOk or CodeValidateFailed
  local CodeValidation_mod = require("lalin.schema_v2.code_validation")
  local asdl = require("lalin.asdl")
  if asdl.classof(validate_result) ~= CodeValidation_mod.CodeValidateOk then
    local issues = validate_result.issues or {}
    local msgs = {}
    for i = 1, #issues do msgs[#msgs+1] = tostring(issues[i]) end
    return Compiler.CompilerArtifactError("code_validate: " .. #msgs .. " issue(s): " .. table.concat(msgs, "; "))
  end


  -- Phase 5: Build CFG
  local graph_ok, graph = pcall(function() return code_module:build_graph() end)
  if not graph_ok then
    return Compiler.CompilerArtifactError("build_graph: " .. tostring(graph))
  end

  -- Phase 6: Facts
  local flow    = graph:compute_flow(code_module)
  local values  = graph:compute_values(code_module, flow)
  local mem     = graph:compute_mem(code_module, flow, values, contracts)
  local effects = graph:compute_effects(code_module, mem, contracts)

  -- Phase 7: Plans
  local kernels   = mem:plan_kernels(flow, values, mem, effects)
  local schedules = kernels:plan_schedules(code_module, flow, values, mem, effects)
  local lower_plan = code_module:plan_lowering(graph, kernels, schedules)

  -- Phase 8: Emit C
  local c_unit = lower_plan:emit_c(code_module)

  -- Phase 9: CEmit - convert to source/header text
  local Cemit = require("lalin.schema_v2.cemit")
  local C_schema = require("lalin.schema_v2.c")
  local Lower_schema = require("lalin.schema_v2.lower")
  local Graph_schema = require("lalin.schema_v2.graph")

  -- Create a spine for CEmitMachine
  local target = C_schema.CBackendTarget(
    C_schema.CBackendC99,
    C_schema.CBackendHostedNative,
    64, 64,
    C_schema.CBackendLittleEndian,
    true
  )
  local spine = Lower_schema.LowerBackSpine(
    code_module,
    graph,
    target
  )
  local cemit_machine = Cemit.CEmitMachine(spine, {}, {}, {}, {})
  local artifact = cemit_machine:emit_module(c_unit)

  -- Package as CompilerArtifact
  local Compiler = require("lalin.schema_v2.compiler")
  return Compiler.CompilerArtifactC(artifact.source, artifact.header)
end


-- Compile to C then build shared object via GCC (or TCC fallback)
-- Returns a session object with :symbol(name, ctype) and :free()
function Compiler.CompilerSession:compile_gcc(opts)
  opts = opts or {}
  local asdl = require("lalin.asdl")

  -- Run the full pipeline to get C source/header
  local result = self:compile()
  if result == nil then
    return nil, "compile returned nil"
  end
  if asdl.classof(result) ~= Compiler.CompilerArtifactC then
    return nil, result  -- return the error artifact as second value
  end

  local source = result.source
  local header = result.header

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
  local stem = (opts.name or self.source_name or "lalin_v2"):gsub("[^%w_%-%.]", "_")
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
    _source_text = self.source_text,
    _source_name = self.source_name,
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

return Compiler
