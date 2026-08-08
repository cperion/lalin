-- Concrete emitted-C cooker for one exotype family.
--
-- The compiler is staging state.  It writes C, invokes GCC, loads the shared
-- object, and then gets out of the way.  Runtime receives a cdata state value and
-- one exact FFI function pointer.

local ffi = require("ffi")
ffi.cdef "int getpid(void);"
local process_id = tonumber(ffi.C.getpid())
local P = require("experiments.exotype_c_emit.protocol")
local Pipeline = require("experiments.exotype_c_emit.pipeline")

local Compiler = {}
Compiler.__index = Compiler
local Program = {}
Program.__index = Program

local function shell_quote(value)
    return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function read_file(path)
    local file = io.open(path, "rb")
    if not file then return nil end
    local value = file:read("*a")
    file:close()
    return value
end

local function execute(command)
    local ok, _, status = os.execute(command)
    return ok == true or ok == 0, status
end

function Compiler.new(options)
    options = options or {}
    return setmetatable({
        active = {},
        stack = {},
        cc = options.cc or os.getenv("CC") or "gcc",
        out_dir = options.out_dir or "target/exotype_c_emit",
    }, Compiler)
end

function Compiler:query(owner, property) return P.query(self, owner, property) end

function Compiler:compile(owner)
    if owner.program ~= nil then return owner.program end
    local layout = self:query(owner, Pipeline.Layout)
    local module = self:query(owner, Pipeline.Module)

    ffi.cdef(layout:c_declaration() .. "\n" .. module:ffi_declaration())
    local ctype = ffi.typeof(layout.ctype_name)
    local stem = self.out_dir .. "/pipeline_" .. owner.artifact_key .. "_" .. process_id
    local c_path, so_path, log_path = stem .. ".c", stem .. ".so", stem .. ".log"
    assert(execute("mkdir -p " .. shell_quote(self.out_dir)))
    local file = assert(io.open(c_path, "wb"))
    file:write(module.source)
    file:close()

    local command = shell_quote(self.cc) .. " -O3 -fPIC -shared -o "
        .. shell_quote(so_path) .. " " .. shell_quote(c_path) .. " 2>" .. shell_quote(log_path)
    if not execute(command) then
        error("GCC cooking failed:\n" .. tostring(read_file(log_path)))
    end

    local library = ffi.load(so_path)
    local entry = library[module.symbol]
    local program = setmetatable({
        owner = owner,
        layout = layout,
        module = module,
        ctype = ctype,
        library = library,
        entry_function = entry,
        c_path = c_path,
        so_path = so_path,
    }, Program)
    owner.program = program
    return program
end

function Program:new() return ffi.new(self.ctype) end
function Program:entry() return self.entry_function end
function Program:run(state, input, rounds) return tonumber(self.entry_function(state, input, rounds)) end
function Program:sizeof() return ffi.sizeof(self.ctype) end

return Compiler
