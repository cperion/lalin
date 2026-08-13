local ffi = require("ffi")

ffi.cdef [[
typedef struct CBlockTCCState CBlockTCCState;
typedef void CBlockTCCErrorFunc(void *opaque, const char *message);
CBlockTCCState *tcc_new(void);
void tcc_delete(CBlockTCCState *state);
void tcc_set_error_func(CBlockTCCState *state, void *opaque,
    CBlockTCCErrorFunc *error_func);
int tcc_set_options(CBlockTCCState *state, const char *options);
int tcc_set_output_type(CBlockTCCState *state, int output_type);
int tcc_add_include_path(CBlockTCCState *state, const char *path);
int tcc_add_library_path(CBlockTCCState *state, const char *path);
int tcc_add_library(CBlockTCCState *state, const char *name);
int tcc_add_symbol(CBlockTCCState *state, const char *name, const void *value);
int tcc_compile_string(CBlockTCCState *state, const char *source);
int tcc_relocate(CBlockTCCState *state);
void *tcc_get_symbol(CBlockTCCState *state, const char *name);
]]

local function load_libtcc()
    local candidates = {
        "/usr/local/lib/libtcc.so",
        "tcc",
        "libtcc.so",
    }
    local failures = {}
    for _, candidate in ipairs(candidates) do
        local ok, library = pcall(ffi.load, candidate)
        if ok then return library end
        failures[#failures + 1] = tostring(library)
    end
    error("cannot load libtcc:\n" .. table.concat(failures, "\n"), 2)
end

local libtcc = load_libtcc()

local Session = {}
Session.__index = Session

function Session:symbol(name, ctype)
    assert(self.state ~= nil, "TCC session is freed")
    assert(type(name) == "string", "symbol name must be a string")
    local address = libtcc.tcc_get_symbol(self.state, name)
    if address == nil then return nil, "missing TCC symbol: " .. name end
    local pointer = ffi.cast(ctype, address)
    self.function_pointers[#self.function_pointers + 1] = pointer
    return pointer
end

function Session:free()
    if self.state == nil then return end
    ffi.gc(self.state, nil)
    libtcc.tcc_delete(self.state)
    self.state = nil
    self.function_pointers = nil
    self.host_symbols = nil
    self.error_callback:free()
    self.error_callback = nil
end

local M = {}

local function each_option(values, apply)
    if values == nil then return true end
    for _, value in ipairs(values) do
        if apply(value) < 0 then return false end
    end
    return true
end

function M.compile(source, options)
    assert(type(source) == "string", "TCC compile expects C source text")
    options = options or {}

    local state = libtcc.tcc_new()
    if state == nil then return nil, "tcc_new failed" end
    ffi.gc(state, libtcc.tcc_delete)

    local diagnostics = {}
    local error_callback = ffi.cast("CBlockTCCErrorFunc *", function(_, message)
        diagnostics[#diagnostics + 1] = ffi.string(message)
    end)
    libtcc.tcc_set_error_func(state, nil, error_callback)

    local function failed(message)
        ffi.gc(state, nil)
        libtcc.tcc_delete(state)
        error_callback:free()
        if #diagnostics > 0 then
            message = message .. ":\n" .. table.concat(diagnostics, "\n")
        end
        return nil, message
    end

    if libtcc.tcc_set_output_type(state, 1) < 0 then
        return failed("tcc_set_output_type failed")
    end
    if options.options and libtcc.tcc_set_options(state, options.options) < 0 then
        return failed("tcc_set_options failed")
    end
    if not each_option(options.include_paths,
        function(path) return libtcc.tcc_add_include_path(state, path) end) then
        return failed("tcc_add_include_path failed")
    end
    if not each_option(options.library_paths,
        function(path) return libtcc.tcc_add_library_path(state, path) end) then
        return failed("tcc_add_library_path failed")
    end
    if not each_option(options.libraries,
        function(name) return libtcc.tcc_add_library(state, name) end) then
        return failed("tcc_add_library failed")
    end

    local host_symbols = {}
    for name, value in pairs(options.symbols or {}) do
        local pointer = ffi.cast("const void *", value)
        if libtcc.tcc_add_symbol(state, name, pointer) < 0 then
            return failed("tcc_add_symbol failed for " .. name)
        end
        host_symbols[#host_symbols + 1] = value
    end

    if libtcc.tcc_compile_string(state, source) < 0 then
        return failed("tcc_compile_string failed")
    end
    if libtcc.tcc_relocate(state) < 0 then
        return failed("tcc_relocate failed")
    end

    return setmetatable({
        state = state,
        source = source,
        diagnostics = diagnostics,
        error_callback = error_callback,
        function_pointers = {},
        host_symbols = host_symbols,
    }, Session)
end

return M
