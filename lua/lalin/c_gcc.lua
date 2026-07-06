-- GCC-backed runner for Lalin emit_c output.
--
-- This is not a second backend IR.  It takes the
-- C text produced by emit_c, compiles it as a shared object with gcc/cc, dlopens
-- that object, and returns function pointers through LuaJIT FFI.

local ok_ffi, ffi = pcall(require, "ffi")

local M = {}
local last_session = nil

local function diag(code, message, extra)
    local d = extra or {}
    d.ok = false
    d.code = code
    d.message = message
    return d
end

local function listify(v)
    if v == nil then return {} end
    if type(v) == "table" then return v end
    return { v }
end

local function shell_quote(s)
    s = tostring(s)
    return "'" .. s:gsub("'", "'\\''") .. "'"
end

local function file_exists(path)
    local f = io.open(path, "rb")
    if f == nil then return false end
    f:close()
    return true
end

local function mkdir_p(path)
    if path == nil or path == "" then return true end
    local ok = os.execute("mkdir -p " .. shell_quote(path))
    return ok == true or ok == 0
end

local function module_repo_root()
    local info = debug.getinfo(1, "S")
    local source = info and info.source
    if type(source) ~= "string" then return nil end
    if source:sub(1, 1) == "@" then source = source:sub(2) end
    return source:match("^(.*)/lua/lalin/c_gcc%.lua$")
end

local repo_root = module_repo_root()

local cdef_done = false
local function ensure_cdef()
    if cdef_done then return true end
    if not ok_ffi then return false end
    local ok, err = pcall(ffi.cdef, [[
void *dlopen(const char *filename, int flags);
void *dlsym(void *handle, const char *symbol);
int dlclose(void *handle);
char *dlerror(void);
]])
    cdef_done = true
    return ok or tostring(err):match("redefinition") ~= nil
end

local function first_nonempty(...)
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        if v ~= nil and tostring(v) ~= "" then return tostring(v) end
    end
    return nil
end

local function vendored_gcc_root()
    if repo_root == nil then return nil end
    local root = repo_root .. "/.vendor/gcc/.local"
    if file_exists(root .. "/bin/gcc") then return root end
    return nil
end

local function find_vendored_gcc_libdir(root)
    if root == nil then return nil end
    local pipe = io.popen("find " .. shell_quote(root .. "/lib/gcc") .. " -name crtbeginS.o -print 2>/dev/null | head -n 1", "r")
    if pipe == nil then return nil end
    local line = pipe:read("*l")
    pipe:close()
    if not line or line == "" then return nil end
    return line:match("^(.*)/crtbeginS%.o$")
end

local function compiler(opts)
    opts = opts or {}
    local explicit = first_nonempty(opts.cc, opts.gcc, opts.compiler, os.getenv("LALIN_GCC"))
    if explicit then return explicit end
    local vendored = vendored_gcc_root()
    if vendored then return vendored .. "/bin/gcc" end
    return first_nonempty(os.getenv("CC"), "gcc")
end

local function command_ok(cmd)
    local ok = os.execute(cmd)
    return ok == true or ok == 0
end

function M.available(opts)
    local cc = compiler(opts)
    if not command_ok(shell_quote(cc) .. " --version >/dev/null 2>&1") then
        return false, diag("gcc_unavailable", "gcc/cc compiler not available: " .. tostring(cc), { skip = true, compiler = cc })
    end
    if not ok_ffi or not ensure_cdef() then
        return false, diag("ffi_unavailable", "LuaJIT FFI/dlopen is unavailable; gcc C runner is disabled", { skip = true })
    end
    return true, nil
end

local function append_flags(out, values)
    for _, v in ipairs(listify(values)) do out[#out + 1] = tostring(v) end
end

local function default_out_dir(opts)
    return opts.out_dir or opts.build_dir or opts.dir or "target/lalin_gcc_jit"
end

local function stem_for(opts)
    local stem = tostring(opts.stem or opts.name or "lalin_c_jit"):gsub("[^%w_%-%.]", "_")
    if stem == "" then stem = "lalin_c_jit" end
    return stem
end

local function unique_suffix()
    math.randomseed(os.time() + tonumber(tostring({}):match("0x(%x+)") or "0", 16))
    return tostring(os.time()) .. "_" .. tostring(math.random(1000000, 9999999))
end

local function write_file(path, bytes)
    local dir = path:match("^(.*)/[^/]+$")
    if dir and dir ~= "" then assert(mkdir_p(dir), "failed to create " .. dir) end
    local f = assert(io.open(path, "wb"))
    f:write(bytes or "")
    f:close()
end

local function capture_command(cmd)
    local pipe = io.popen(cmd .. " 2>&1", "r")
    if pipe == nil then return false, "failed to spawn command" end
    local out = pipe:read("*a") or ""
    local ok, why, code = pipe:close()
    if ok == true or ok == 0 then return true, out end
    return false, out, why, code
end

local function compile_command(c_path, so_path, opts)
    opts = opts or {}
    local cc = compiler(opts)
    local args = { shell_quote(cc), opts.std or "-std=c99", opts.opt_flag or opts.O_flag or ("-O" .. tostring(opts.opt or opts.O or 3)), "-fPIC", "-shared" }
    append_flags(args, opts.cflags or opts.cflag)
    for _, p in ipairs(listify(opts.include_paths or opts.include_path)) do args[#args + 1] = "-I" .. shell_quote(p) end
    for _, p in ipairs(listify(opts.library_paths or opts.library_path)) do args[#args + 1] = "-L" .. shell_quote(p) end

    local vendored = vendored_gcc_root()
    if vendored and cc == vendored .. "/bin/gcc" then
        local gcc_lib = find_vendored_gcc_libdir(vendored)
        if gcc_lib then
            args[#args + 1] = "-B" .. shell_quote(gcc_lib .. "/")
            args[#args + 1] = "-L" .. shell_quote(gcc_lib)
        end
        if file_exists(vendored .. "/lib64/libgcc_s.so") or file_exists(vendored .. "/lib64/libatomic.a") then
            args[#args + 1] = "-L" .. shell_quote(vendored .. "/lib64")
        end
    end

    args[#args + 1] = shell_quote(c_path)
    append_flags(args, opts.ldflags or opts.ldflag)
    for _, lib in ipairs(listify(opts.libraries or opts.library_names or { "m" })) do args[#args + 1] = "-l" .. tostring(lib) end
    args[#args + 1] = "-o"
    args[#args + 1] = shell_quote(so_path)
    return table.concat(args, " ")
end

local Session = {}
Session.__index = Session

function Session:symbol(name, ctype)
    assert(type(name) == "string" and name ~= "", "gcc C runner symbol name must be a non-empty string")
    if self._freed or self._handle == nil then return nil, diag("session_freed", "gcc C runner session has been freed") end
    ffi.C.dlerror()
    local ptr = ffi.C.dlsym(self._handle, name)
    if ptr == nil then
        local err = ffi.C.dlerror()
        return nil, diag("symbol_not_found", err ~= nil and ffi.string(err) or ("symbol not found: " .. name))
    end
    if ctype ~= nil then return ffi.cast(ctype, ptr) end
    return ptr
end

function Session:free()
    if self._freed then return true end
    if self._handle ~= nil then ffi.C.dlclose(self._handle); self._handle = nil end
    self._freed = true
    if last_session == self then last_session = nil end
    return true
end

function M.compile(c_source, opts)
    opts = opts or {}
    assert(type(c_source) == "string", "lalin.c_gcc.compile expects emitted C source text")
    local ok, avail = M.available(opts)
    if not ok then return nil, avail end

    local out_dir = default_out_dir(opts)
    local stem = stem_for(opts)
    local suffix = opts.cache_key or unique_suffix()
    local c_path = opts.c_path or opts.source_path or (out_dir .. "/" .. stem .. "_" .. suffix .. ".c")
    local so_path = opts.so_path or opts.shared_object_path or (out_dir .. "/" .. stem .. "_" .. suffix .. ".so")
    assert(mkdir_p(out_dir), "failed to create " .. out_dir)
    write_file(c_path, c_source)

    local cmd = compile_command(c_path, so_path, opts)
    local compiled, output = capture_command(cmd)
    if not compiled then
        return nil, diag("gcc_compile_failed", "gcc compile failed", { command = cmd, output = output, c_path = c_path, so_path = so_path })
    end

    local handle = ffi.C.dlopen(so_path, 2) -- RTLD_NOW
    if handle == nil then
        local err = ffi.C.dlerror()
        return nil, diag("dlopen_failed", err ~= nil and ffi.string(err) or ("dlopen failed: " .. so_path), { so_path = so_path })
    end

    local session = setmetatable({
        _handle = handle,
        _freed = false,
        compiler = compiler(opts),
        command = cmd,
        output = output,
        c_path = c_path,
        so_path = so_path,
    }, Session)
    last_session = session
    return session
end

function M.symbol(name, ctype)
    if last_session == nil then return nil, diag("no_session", "no active gcc C runner session; call lalin.c_gcc.compile first") end
    return last_session:symbol(name, ctype)
end

function M.free()
    if last_session == nil then return true end
    return last_session:free()
end

M.Session = Session
M.compiler = compiler

return M
