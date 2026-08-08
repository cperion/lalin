-- GCC cooker and FFI owner for the fused-array-kernel exotype.

local ffi = require("ffi")
ffi.cdef "int getpid(void);"
local process_id = tonumber(ffi.C.getpid())

local P = require("experiments.exotype_c_emit.protocol")
local Kernel = require("experiments.exotype_c_emit.array_kernel")

local Compiler = {}
Compiler.__index = Compiler
local Program = {}
Program.__index = Program

local function shell_quote(value)
    return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function read_file(path)
    local file = io.open(path, "rb")
    if not file then return "" end
    local value = file:read("*a")
    file:close()
    return value
end

local function execute(command)
    local ok = os.execute(command)
    return ok == true or ok == 0
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
    local abi = self:query(owner, Kernel.AbiProperty)
    local module = self:query(owner, Kernel.ModuleProperty)
    ffi.cdef(abi:ffi_declaration(module.symbol))

    local stem = self.out_dir .. "/array_" .. owner.artifact_key .. "_" .. process_id
    local c_path, so_path, log_path = stem .. ".c", stem .. ".so", stem .. ".log"
    assert(execute("mkdir -p " .. shell_quote(self.out_dir)))
    local file = assert(io.open(c_path, "wb"))
    file:write(module.source)
    file:close()

    local command = shell_quote(self.cc) .. " -std=c11 -O3 -fPIC -shared -o "
        .. shell_quote(so_path) .. " " .. shell_quote(c_path) .. " 2>" .. shell_quote(log_path)
    if not execute(command) then error("GCC kernel cooking failed:\n" .. read_file(log_path)) end

    local library = ffi.load(so_path)
    local program = setmetatable({
        owner = owner,
        abi = abi,
        module = module,
        library = library,
        entry_function = library[module.symbol],
        so_path = so_path,
    }, Program)
    owner.program = program
    return program
end

function Program:new_buffer(count)
    assert(type(count) == "number" and count >= 0 and count == math.floor(count),
        "buffer count must be a nonnegative integer")
    return ffi.new(self.abi.ffi_type .. "[?]", count)
end

function Program:new_parameters()
    return ffi.new(self.abi.ffi_type .. "[?]", math.max(self.abi.parameter_count, 1))
end

function Program:entry() return self.entry_function end
function Program:run(output, input, count, parameters)
    return self.entry_function(output, input, count, parameters)
end

return Compiler
