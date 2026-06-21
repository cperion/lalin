local asdl = require("llpvm.asdl")
local bytecode = require("llpvm.bytecode")
local ffi = require("ffi")

local M = {
    asdl = asdl,
    T = asdl.T,
    B = asdl.B,
}

local Vm = {}
Vm.__index = Vm

local Abi = {}
Abi.__index = Abi

local World = {}
World.__index = World

local Stream = {}
Stream.__index = Stream

local Phase = {}
Phase.__index = Phase

local Program = {}
Program.__index = Program

local Retained = {}
Retained.__index = Retained

local Type = {}
Type.__index = Type

local scalar_names = {
    void = "Void",
    bool = "Bool",
    i8 = "I8",
    i16 = "I16",
    i32 = "I32",
    i64 = "I64",
    u8 = "U8",
    u16 = "U16",
    u32 = "U32",
    u64 = "U64",
    f32 = "F32",
    f64 = "F64",
    index = "Index",
}

local function is_array(t)
    if type(t) ~= "table" then return false end
    local n = #t
    for k in pairs(t) do
        if type(k) ~= "number" or k < 1 or k > n or k % 1 ~= 0 then return false end
    end
    return true
end

local function sorted_string_keys(t)
    local keys = {}
    for k in pairs(t or {}) do
        if type(k) == "string" then keys[#keys + 1] = k end
    end
    table.sort(keys)
    return keys
end

local function list(v)
    if v == nil then return {} end
    if is_array(v) then return v end
    return { v }
end

local function unwrap(v)
    if getmetatable(v) == Retained then return unwrap(v.value) end
    return v
end

local function id_of(v, what)
    v = unwrap(v)
    assert(type(v) == "table" and v.id ~= nil, what .. " expected")
    return v.id
end

local function type_wrap(vm, kind, id, extra)
    extra = extra or {}
    extra.vm = vm
    extra.kind = kind
    extra.id = id
    return setmetatable(extra, Type)
end

local function scalar(name)
    return setmetatable({ scalar = name }, {
        __call = function(self, vm)
            return vm:_scalar_type(self.scalar)
        end,
    })
end

M.void = scalar("void")
M.bool = scalar("bool")
M.i8 = scalar("i8")
M.i16 = scalar("i16")
M.i32 = scalar("i32")
M.i64 = scalar("i64")
M.u8 = scalar("u8")
M.u16 = scalar("u16")
M.u32 = scalar("u32")
M.u64 = scalar("u64")
M.f32 = scalar("f32")
M.f64 = scalar("f64")
M.index = scalar("index")
M.node = { __llpvm_builtin = "node" }

local function resolve_type(vm, spec)
    spec = unwrap(spec)
    if getmetatable(spec) == Type then return spec end
    if type(spec) == "table" and spec.scalar then return vm:_scalar_type(spec.scalar) end
    if type(spec) == "table" and spec.__llpvm_builtin == "node" then return vm:_handle_type("node") end
    if type(spec) == "table" and spec.id then return spec end
    error("LLPVM type expected", 3)
end

function M.handle(name)
    return { __llpvm_type_form = "handle", name = tostring(name) }
end

function M.ptr(to)
    return { __llpvm_type_form = "ptr", to = to }
end

function M.view(item)
    return { __llpvm_type_form = "view", item = item }
end

function M.struct(name)
    return function(fields)
        return { __llpvm_type_form = "struct", name = tostring(name), fields = fields or {} }
    end
end

function Vm:_scalar_type(name)
    local key = "scalar:" .. name
    local cached = self.types[key]
    if cached then return cached end
    local id = self.builder:scalar(assert(scalar_names[name], "unknown scalar type: " .. tostring(name)))
    local t = type_wrap(self, "scalar", id, { name = name })
    self.types[key] = t
    return t
end

function Vm:_handle_type(name)
    local key = "handle:" .. name
    local cached = self.types[key]
    if cached then return cached end
    local id = self.builder:handle(name)
    local t = type_wrap(self, "handle", id, { name = name })
    self.types[key] = t
    return t
end

function Vm:_lower_type_form(spec)
    spec = unwrap(spec)
    if getmetatable(spec) == Type then return spec end
    if type(spec) == "table" and spec.scalar then return self:_scalar_type(spec.scalar) end
    if type(spec) == "table" and spec.__llpvm_builtin == "node" then return self:_handle_type("node") end
    if type(spec) ~= "table" then error("LLPVM type form expected", 3) end
    if spec.__llpvm_type_form == "handle" then return self:_handle_type(spec.name) end
    if spec.__llpvm_type_form == "ptr" then
        local to = resolve_type(self, self:_lower_type_form(spec.to))
        return type_wrap(self, "ptr", self.builder:pointer(to.id), { to = to })
    end
    if spec.__llpvm_type_form == "view" then
        local item = resolve_type(self, self:_lower_type_form(spec.item))
        return type_wrap(self, "view", self.builder:view(item.id), { item = item })
    end
    if spec.__llpvm_type_form == "struct" then
        local field_ids = {}
        local fields = spec.fields or {}
        if is_array(fields) then
            for i = 1, #fields do field_ids[i] = id_of(fields[i], "field") end
        else
            for i, k in ipairs(sorted_string_keys(fields)) do
                local ft = resolve_type(self, self:_lower_type_form(fields[k]))
                field_ids[i] = self.builder:field(k, ft.id)
            end
        end
        return type_wrap(self, "struct", self.builder:struct(spec.name, field_ids), { name = spec.name })
    end
    error("unknown LLPVM type form", 3)
end

function M.field(name, typ)
    return { __llpvm_field = true, name = tostring(name), type = typ }
end

local function payload_id(vm, v)
    v = unwrap(v)
    if type(v) == "table" and v.__llpvm_ref_payload then return vm.builder:ref_payload(v.value) end
    return vm.builder:payload(v)
end

local function arg_id(vm, v)
    v = unwrap(v)
    if type(v) == "table" and v.__llpvm_ref_arg then return vm.builder:ref_arg(v.value) end
    return vm.builder:arg(v)
end

function M.ref_payload(raw)
    return { __llpvm_ref_payload = true, value = raw }
end

function M.ref_arg(raw)
    return { __llpvm_ref_arg = true, value = raw }
end

function M.symbol(v)
    return tostring(v or "")
end

function M.cache(mode)
    return mode
end

local function stream_wrap(vm, id, kind, extra)
    extra = extra or {}
    extra.vm = vm
    extra.id = id
    extra.kind = kind
    return setmetatable(extra, Stream)
end

local function world_wrap(vm, abi, id, name)
    return setmetatable({ vm = vm, abi = abi, id = id, name = name }, World)
end

local function phase_wrap(vm, id, name)
    return setmetatable({ vm = vm, id = id, name = name }, Phase)
end

function Abi:_make_op(kind_name, payload_spec)
    payload_spec = payload_spec or {}
    local payload_ids = {}
    local payload_values = {}
    local fields = self.__op_fields[kind_name] or {}
    if is_array(payload_spec) then
        for i = 1, #payload_spec do
            payload_ids[i] = payload_id(self.vm, payload_spec[i])
            payload_values[i] = payload_spec[i]
        end
    else
        for i = 1, #fields do
            local name = fields[i]
            local v = payload_spec[name]
            payload_ids[i] = payload_id(self.vm, v)
            payload_values[i] = v
        end
    end
    local world = self:world()
    local id = self.vm.builder:op(world.id, kind_name, payload_ids)
    return { vm = self.vm, id = id, world = world, kind = kind_name, payload = payload_values }
end

function Abi:world(name)
    name = name or self.name
    if self.__worlds[name] == nil then
        local id = self.vm.builder:world(name, self.id)
        local world = world_wrap(self.vm, self, id, name)
        self.__worlds[name] = world
        self.vm.worlds[#self.vm.worlds + 1] = world
    end
    return self.__worlds[name]
end

function Vm:abi(name)
    return function(spec)
        spec = spec or {}
        local op_kind_ids = {}
        local op_fields = {}
        for _, k in ipairs(sorted_string_keys(spec)) do
            if k ~= "version" and k ~= "resource_type" then
                local field_ids = {}
                local field_names = {}
                local fields = spec[k] or {}
                for i, field_name in ipairs(sorted_string_keys(fields)) do
                    local ft = resolve_type(self, self:_lower_type_form(fields[field_name]))
                    field_ids[i] = self.builder:field(field_name, ft.id)
                    field_names[i] = field_name
                end
                op_kind_ids[#op_kind_ids + 1] = self.builder:op_kind(k, field_ids)
                op_fields[k] = field_names
            end
        end
        local resource = spec.resource_type and resolve_type(self, self:_lower_type_form(spec.resource_type)).id or 0
        local id = self.builder:abi(name, spec.version or 1, op_kind_ids, resource)
        local abi = setmetatable({ vm = self, id = id, name = name, __op_fields = op_fields, __worlds = {} }, Abi)
        for op_name in pairs(op_fields) do
            abi[op_name] = function(payload_spec) return abi:_make_op(op_name, payload_spec) end
        end
        self.abis[#self.abis + 1] = abi
        return abi
    end
end

function Vm:world(name)
    return function(spec)
        spec = spec or {}
        local abi = assert(spec.abi, "vm.world requires abi")
        local id = self.builder:world(name, id_of(abi, "abi"))
        local world = world_wrap(self, abi, id, name)
        self.worlds[#self.worlds + 1] = world
        return world
    end
end

function Vm:empty(world)
    local id = self.builder:empty(id_of(world, "world"))
    return stream_wrap(self, id, "empty", { world = world, ops = {} })
end

function Vm:once(op)
    op = unwrap(op)
    local id = self.builder:once(id_of(op, "op"))
    return stream_wrap(self, id, "once", { world = op.world, ops = { op } })
end

function Vm:seq(world)
    return function(ops)
        ops = list(ops)
        local op_ids = {}
        for i = 1, #ops do op_ids[i] = id_of(ops[i], "op") end
        local id = self.builder:seq(id_of(world, "world"), op_ids)
        return stream_wrap(self, id, "seq", { world = world, ops = ops })
    end
end

function Vm:concat(streams)
    streams = list(streams)
    local stream_ids = {}
    local ops = {}
    for i = 1, #streams do
        local s = unwrap(streams[i])
        stream_ids[i] = id_of(s, "stream")
        for j = 1, #(s.ops or {}) do ops[#ops + 1] = s.ops[j] end
    end
    local id = self.builder:concat(stream_ids)
    return stream_wrap(self, id, "concat", { ops = ops })
end

function Vm:machine(name)
    return function(spec)
        spec = spec or {}
        local input = assert(spec.from or spec.input, "machine requires input/from world")
        local output = assert(spec.to or spec.output, "machine requires output/to world")
        local id = self.builder:machine(name, id_of(input, "input world"), id_of(output, "output world"), spec.entry or spec.entry_symbol or name)
        local machine = { vm = self, id = id, name = name, input = input, output = output }
        self.machines[#self.machines + 1] = machine
        return machine
    end
end

function Vm:phase(name)
    return function(spec)
        spec = spec or {}
        local input = assert(spec.from or spec.input, "phase requires input/from world")
        local output = assert(spec.to or spec.output, "phase requires output/to world")
        local machine = assert(spec.machine, "phase requires machine")
        local cache_id = self.builder:cache(spec.cache)
        local id = self.builder:phase(name, id_of(input, "input world"), id_of(output, "output world"), id_of(machine, "machine"), cache_id)
        local phase = phase_wrap(self, id, name)
        self.phases[#self.phases + 1] = phase
        return phase
    end
end

function Phase:with_args(args)
    local values = {}
    args = args or {}
    if is_array(args) then
        for i = 1, #args do values[i] = arg_id(self.vm, args[i]) end
    else
        for i, k in ipairs(sorted_string_keys(args)) do values[i] = arg_id(self.vm, args[k]) end
    end
    local args_id = self.vm.builder:args(values)
    return setmetatable({ vm = self.vm, phase = self, args_id = args_id }, {
        __call = function(bound, input)
            local id = bound.vm.builder:phase_map(bound.phase.id, id_of(input, "input stream"), bound.args_id)
            return stream_wrap(bound.vm, id, "phase_map", { input = input, ops = { { id = id, kind = "phase_map" } } })
        end,
    })
end

function Phase:__call(arg)
    if getmetatable(arg) == Stream then return self:with_args({})(arg) end
    return self:with_args(arg or {})
end

function Stream:drain()
    local out = {}
    for i = 1, #(self.ops or {}) do out[i] = self.ops[i] end
    return out
end

function Stream:one()
    local ops = self:drain()
    assert(#ops == 1, "stream:one expected exactly one op, got " .. tostring(#ops))
    return ops[1]
end

function Stream:each(fn)
    local ops = self:drain()
    for i = 1, #ops do fn(ops[i], i) end
    return self
end

function Vm:program(roots)
    roots = list(roots)
    local root_ids = {}
    local root_ops = {}
    for i = 1, #roots do
        local s = unwrap(roots[i])
        root_ids[i] = id_of(s, "root stream")
        if i == 1 then
            for j = 1, #(s.ops or {}) do root_ops[j] = id_of(s.ops[j], "root op") end
        end
    end
    return setmetatable({ vm = self, root_ids = root_ids, root_ops = root_ops }, Program)
end

function Program:bytecode()
    return self.vm.builder:finish(self.root_ids, self.root_ops)
end

function Program:write(path)
    local f = assert(io.open(path, "wb"))
    local bytes = self:bytecode()
    f:write(bytes)
    f:close()
    return path, #bytes
end

function Vm:retain(value)
    local retained = setmetatable({ vm = self, value = value, generation = self.generation }, Retained)
    self.retained[#self.retained + 1] = retained
    return retained
end

function Vm:rebuild(fn)
    self.generation = self.generation + 1
    return fn(self)
end

function Retained:get()
    return self.value
end

function M.vm(config)
    config = config or {}
    local self = setmetatable({
        config = config,
        generation = 1,
        builder = bytecode.builder(),
        types = {},
        abis = {},
        worlds = {},
        machines = {},
        phases = {},
        retained = {},
    }, Vm)
    self.abi = function(name) return Vm.abi(self, name) end
    self.world = function(name) return Vm.world(self, name) end
    self.empty = function(world) return Vm.empty(self, world) end
    self.once = function(op) return Vm.once(self, op) end
    self.seq = function(world) return Vm.seq(self, world) end
    self.concat = function(streams) return Vm.concat(self, streams) end
    self.machine = function(name) return Vm.machine(self, name) end
    self.phase = function(name) return Vm.phase(self, name) end
    self.program = function(roots) return Vm.program(self, roots) end
    self.retain = function(value) return Vm.retain(self, value) end
    self.rebuild = function(fn) return Vm.rebuild(self, fn) end
    return self
end

function M.bytecode(program)
    if getmetatable(program) == Program then return program:bytecode() end
    return bytecode.encode(program)
end

function M.bytebuffer(bytes)
    assert(type(bytes) == "string", "llpvm.bytebuffer expects a string")
    local buf = ffi.new("uint8_t[?]", #bytes)
    ffi.copy(buf, bytes, #bytes)
    return buf, #bytes
end

return M
