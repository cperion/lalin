local ffi = require("ffi")
local Undump = require("experiments.lua55.undump55")
local Native = require("experiments.copy_patch_cps.lua55_trace.opcode_00_08")
local TableOps = require("experiments.copy_patch_cps.lua55_trace.opcode_table")
local Compare = require("experiments.copy_patch_cps.lua55_trace.opcode_compare")
local Arith = require("experiments.copy_patch_cps.lua55_trace.opcode_arith")
local Unary = require("experiments.copy_patch_cps.lua55_trace.opcode_unary")
local Jmp = require("experiments.copy_patch_cps.lua55_trace.opcode_jmp")
local Pow = require("experiments.copy_patch_cps.lua55_trace.opcode_pow")
local Call = require("experiments.copy_patch_cps.lua55_trace.opcode_call")
local GTable = require("experiments.copy_patch_cps.lua55_trace.opcode_generic_table")
local SetList = require("experiments.copy_patch_cps.lua55_trace.opcode_setlist")
local Closure = require("experiments.copy_patch_cps.lua55_trace.opcode_closure")
local Concat = require("experiments.copy_patch_cps.lua55_trace.opcode_concat")
local Vararg = require("experiments.copy_patch_cps.lua55_trace.opcode_vararg")
local TFor = require("experiments.copy_patch_cps.lua55_trace.opcode_tfor")
local Close = require("experiments.copy_patch_cps.lua55_trace.opcode_close")
local ForLoop = require("experiments.copy_patch_cps.lua55_trace.opcode_for")

local function product(name, fields)
    local class = { name = name }
    class.__index = class
    function class:is(value) return getmetatable(value) == self end
    return setmetatable(class, {
        __call = function(_, ...)
            local values = { ... }
            assert(#values == #fields, name .. " constructor arity changed")
            local instance = {}
            for index = 1, #fields do instance[fields[index]] = values[index] end
            return setmetatable(instance, class)
        end,
    })
end

local UnsupportedOpcode = product("UnsupportedOpcode", { "pc", "opcode" })
local MissingInstruction = product("MissingInstruction", { "pc" })
local MissingConstant = product("MissingConstant", { "pc", "index" })
local MalformedLoadKX = product("MalformedLoadKX", { "pc" })
local MalformedComparison = product("MalformedComparison", { "pc", "opcode" })
local UnsupportedConstant = product("UnsupportedConstant", { "pc", "constant" })
local UnsupportedRKConstant = product("UnsupportedRKConstant", { "pc", "opcode" })
local InvalidProjectionRange = product("InvalidProjectionRange", { "pc", "stop_pc" })
local ProjectionRejected = product("ProjectionRejected", { "failure" })

local DecodedPath = {}
DecodedPath.__index = DecodedPath
function DecodedPath.new(proto, start_pc, stop_pc, occurrences, heap_owner)
    return setmetatable({
        proto = proto, start_pc = start_pc, stop_pc = stop_pc, occurrences = occurrences,
        heap_owner = heap_owner,
    }, DecodedPath)
end
function DecodedPath:new_program(exit_pc, bank, capacity)
    return Native.Program.new(
        self.occurrences, self.proto.maxstacksize, exit_pc, bank, capacity,
        #self.proto.upvals, self.heap_owner)
end

local Projector = {}
Projector.__index = Projector

function Projector.new(proto, start_pc, stop_pc, heap_owner)
    return setmetatable({
        proto = proto, start_pc = start_pc, stop_pc = stop_pc, heap_owner = heap_owner,
        pc = start_pc, occurrences = {},
    }, Projector)
end

function Projector:project_current()
    if self.pc == self.stop_pc then
        return DecodedPath.new(
            self.proto, self.start_pc, self.stop_pc, self.occurrences, self.heap_owner)
    end
    if self.pc > self.stop_pc then
        return self:on_rejected(InvalidProjectionRange(self.pc, self.stop_pc))
    end
    local instruction = self.proto.code[self.pc + 1]
    if instruction == nil then return self:on_rejected(MissingInstruction(self.pc)) end
    return instruction:project_native_path(
        self.proto, self.pc, self, Projector.on_occurrence, Projector.on_rejected)
end

function Projector:on_occurrence(occurrence, next_pc)
    self.occurrences[#self.occurrences + 1] = occurrence
    self.pc = next_pc
    return self:project_current()
end

function Projector:on_rejected(failure) return ProjectionRejected(failure) end

local function unsupported_opcode(instruction, _proto, pc, cc, _on_occurrence, on_rejected)
    return on_rejected(cc, UnsupportedOpcode(pc, instruction.name))
end

local function malformed_loadkx(_instruction, _load, _proto, pc, cc, _on_occurrence, on_rejected)
    return on_rejected(cc, MalformedLoadKX(pc))
end

for opcode = 0, 84 do
    local class = assert(Undump.OPCODE_CLASSES[opcode])
    class.project_native_path = unsupported_opcode
    class.project_loadkx = malformed_loadkx
end

local classes = Undump.OPCODE_CLASSES

classes[0].project_native_path = function(self, _proto, pc, cc, on_occurrence, _on_rejected)
    return on_occurrence(cc, Native.MoveOccurrence.new(pc, self.A, self.B), pc + 1)
end

classes[1].project_native_path = function(self, _proto, pc, cc, on_occurrence, _on_rejected)
    return on_occurrence(cc, Native.LoadIOccurrence.new(pc, self.A, self.sBx), pc + 1)
end

classes[2].project_native_path = function(self, _proto, pc, cc, on_occurrence, _on_rejected)
    return on_occurrence(cc, Native.LoadFOccurrence.new(pc, self.A, self.sBx), pc + 1)
end

local constants = Undump.CONSTANT_CLASSES

function constants.Nil:project_loadk(pc, target, next_pc, cc, on_occurrence, _on_rejected)
    return on_occurrence(cc, Native.LoadKOccurrence.new(pc, target, Native.NilConstant.new()), next_pc)
end
function constants.False:project_loadk(pc, target, next_pc, cc, on_occurrence, _on_rejected)
    return on_occurrence(cc, Native.LoadKOccurrence.new(pc, target, Native.FalseConstant.new()), next_pc)
end
function constants.True:project_loadk(pc, target, next_pc, cc, on_occurrence, _on_rejected)
    return on_occurrence(cc, Native.LoadKOccurrence.new(pc, target, Native.TrueConstant.new()), next_pc)
end
function constants.Integer:project_loadk(pc, target, next_pc, cc, on_occurrence, _on_rejected)
    return on_occurrence(cc,
        Native.LoadKOccurrence.new(pc, target, Native.IntegerConstant.new(self.v)), next_pc)
end
function constants.Float:project_loadk(pc, target, next_pc, cc, on_occurrence, _on_rejected)
    return on_occurrence(cc,
        Native.LoadKOccurrence.new(pc, target, Native.FloatConstant.new(self.v)), next_pc)
end

function constants.ShortString:project_loadk(pc, target, next_pc, cc, on_occurrence, on_rejected)
    if cc.heap_owner == nil then return on_rejected(cc, UnsupportedConstant(pc, self)) end
    local owner = cc.heap_owner:short_string(self.v)
    return on_occurrence(cc,
        Native.LoadKOccurrence.new(pc, target, Native.ShortStringConstant.new(owner)), next_pc)
end
function constants.LongString:project_loadk(pc, target, next_pc, cc, on_occurrence, on_rejected)
    if cc.heap_owner == nil then return on_rejected(cc, UnsupportedConstant(pc, self)) end
    local owner = cc.heap_owner:long_string(self.v)
    return on_occurrence(cc,
        Native.LoadKOccurrence.new(pc, target, Native.LongStringConstant.new(owner)), next_pc)
end

function constants.Nil:project_loadkx(pc, target, next_pc, cc, on_occurrence, _on_rejected)
    return on_occurrence(cc, Native.LoadKXOccurrence.new(pc, target, Native.NilConstant.new()), next_pc)
end
function constants.False:project_loadkx(pc, target, next_pc, cc, on_occurrence, _on_rejected)
    return on_occurrence(cc, Native.LoadKXOccurrence.new(pc, target, Native.FalseConstant.new()), next_pc)
end
function constants.True:project_loadkx(pc, target, next_pc, cc, on_occurrence, _on_rejected)
    return on_occurrence(cc, Native.LoadKXOccurrence.new(pc, target, Native.TrueConstant.new()), next_pc)
end
function constants.Integer:project_loadkx(pc, target, next_pc, cc, on_occurrence, _on_rejected)
    return on_occurrence(cc,
        Native.LoadKXOccurrence.new(pc, target, Native.IntegerConstant.new(self.v)), next_pc)
end
function constants.Float:project_loadkx(pc, target, next_pc, cc, on_occurrence, _on_rejected)
    return on_occurrence(cc,
        Native.LoadKXOccurrence.new(pc, target, Native.FloatConstant.new(self.v)), next_pc)
end
function constants.ShortString:project_loadkx(pc, target, next_pc, cc, on_occurrence, on_rejected)
    if cc.heap_owner == nil then return on_rejected(cc, UnsupportedConstant(pc, self)) end
    local owner = cc.heap_owner:short_string(self.v)
    return on_occurrence(cc,
        Native.LoadKXOccurrence.new(pc, target, Native.ShortStringConstant.new(owner)), next_pc)
end
function constants.LongString:project_loadkx(pc, target, next_pc, cc, on_occurrence, on_rejected)
    if cc.heap_owner == nil then return on_rejected(cc, UnsupportedConstant(pc, self)) end
    local owner = cc.heap_owner:long_string(self.v)
    return on_occurrence(cc,
        Native.LoadKXOccurrence.new(pc, target, Native.LongStringConstant.new(owner)), next_pc)
end

local function constant_at(proto, pc, index, cc, on_ready, on_rejected)
    local constant = proto.k[index + 1]
    if constant == nil then return on_rejected(cc, MissingConstant(pc, index)) end
    return on_ready(constant, cc)
end

local function project_loadk_constant(constant, cc)
    local instruction, projector = cc.proto.code[cc.pc + 1], cc
    return constant:project_loadk(
        cc.pc, instruction.A, cc.pc + 1, projector, Projector.on_occurrence, Projector.on_rejected)
end

classes[3].project_native_path = function(self, proto, pc, cc, _on_occurrence, on_rejected)
    cc.proto, cc.pc = proto, pc
    return constant_at(proto, pc, self.Bx, cc, project_loadk_constant, on_rejected)
end

classes[4].project_native_path = function(self, proto, pc, cc, on_occurrence, on_rejected)
    local companion = proto.code[pc + 2]
    if companion == nil then return on_rejected(cc, MalformedLoadKX(pc)) end
    return companion:project_loadkx(self, proto, pc, cc, on_occurrence, on_rejected)
end

classes[84].project_loadkx = function(self, load, proto, pc, cc, _on_occurrence, on_rejected)
    local constant = proto.k[self.Ax + 1]
    if constant == nil then return on_rejected(cc, MissingConstant(pc, self.Ax)) end
    return constant:project_loadkx(
        pc, load.A, pc + 2, cc, Projector.on_occurrence, Projector.on_rejected)
end

classes[5].project_native_path = function(self, _proto, pc, cc, on_occurrence, _on_rejected)
    return on_occurrence(cc, Native.LoadFalseOccurrence.new(pc, self.A), pc + 1)
end

classes[6].project_native_path = function(self, _proto, pc, cc, on_occurrence, _on_rejected)
    return on_occurrence(cc, Native.LoadFalseSkipOccurrence.new(pc, self.A), pc + 2)
end

classes[7].project_native_path = function(self, _proto, pc, cc, on_occurrence, _on_rejected)
    return on_occurrence(cc, Native.LoadTrueOccurrence.new(pc, self.A), pc + 1)
end

classes[8].project_native_path = function(self, _proto, pc, cc, on_occurrence, _on_rejected)
    return on_occurrence(cc, Native.LoadNilOccurrence.new(pc, self.A, self.B + 1), pc + 1)
end

classes[9].project_native_path = function(self, _proto, pc, cc, on_occurrence, _on_rejected)
    return on_occurrence(cc, Native.GetUpvalueOccurrence.new(pc, self.A, self.B), pc + 1)
end

classes[10].project_native_path = function(self, _proto, pc, cc, on_occurrence, _on_rejected)
    return on_occurrence(cc, Native.SetUpvalueOccurrence.new(pc, self.A, self.B), pc + 1)
end

-- Resolve an RK operand (register or constant). Returns { reg = i } or
-- { const = facts } where facts is {tag, int_bits, flt_bits, ref}.
local function rk_value(proto, pc, cc, on_rejected, opcode, index, k)
    if k == 0 then return { reg = index } end
    local constant = proto.k[index + 1]
    if constant == nil then return on_rejected(cc, MissingConstant(pc, index)) end
    if constant.t == "int" then
        return { const = { tag = 3, int_bits = ffi.cast("uint64_t", ffi.new("int64_t", constant.v)), flt_bits = 0, ref = 0 } }
    elseif constant.t == "flt" then
        local holder = ffi.new("double[1]", constant.v)
        return { const = { tag = 4, int_bits = 0, flt_bits = ffi.cast("uint64_t *", holder)[0], ref = 0 } }
    elseif constant.t == "nil" then
        return { const = { tag = 0, int_bits = 0, flt_bits = 0, ref = 0 } }
    elseif constant.t == "false" then
        return { const = { tag = 1, int_bits = 0, flt_bits = 0, ref = 0 } }
    elseif constant.t == "true" then
        return { const = { tag = 2, int_bits = 0, flt_bits = 0, ref = 0 } }
    elseif constant.t == "str" then
        local heap_owner = cc.heap_owner
        if heap_owner == nil then return on_rejected(cc, UnsupportedConstant(pc, constant)) end
        local owner = heap_owner:short_string(constant.v)
        return { const = { tag = 5, int_bits = 0, flt_bits = 0, ref = owner:reference() } }
    end
    return on_rejected(cc, UnsupportedConstant(pc, constant))
end



classes[13].project_native_path = function(self, _proto, pc, cc, on_occurrence, _on_rejected)
    return on_occurrence(cc, TableOps.GetIOccurrence.new(pc, self.A, self.B, self.C), pc + 1)
end

local function unsupported_getfield_constant(constant, pc, _target, _receiver, cc, _on_occurrence, on_rejected)
    return on_rejected(cc, UnsupportedConstant(pc, constant))
end

local function unsupported_setfield_constant(constant, pc, _receiver, _source, cc, _on_occurrence, on_rejected)
    return on_rejected(cc, UnsupportedConstant(pc, constant))
end

for _, constant_class in pairs(constants) do
    constant_class.project_getfield = unsupported_getfield_constant
    constant_class.project_setfield = unsupported_setfield_constant
end

function constants.ShortString:project_getfield(pc, target, receiver, cc, on_occurrence, on_rejected)
    if cc.heap_owner == nil then return on_rejected(cc, UnsupportedConstant(pc, self)) end
    local key_owner = cc.heap_owner:short_string(self.v)
    return on_occurrence(cc, TableOps.GetFieldOccurrence.new(pc, target, receiver, key_owner), pc + 1)
end

function constants.ShortString:project_setfield(pc, receiver, source, cc, on_occurrence, on_rejected)
    if cc.heap_owner == nil then return on_rejected(cc, UnsupportedConstant(pc, self)) end
    local key_owner = cc.heap_owner:short_string(self.v)
    local occurrence = TableOps.SetFieldOccurrence.new(pc, receiver, key_owner,
        type(source) == "table" and (source.reg or 0) or source)
    if type(source) == "table" and source.const then occurrence.const_value = source.const end
    return on_occurrence(cc, occurrence, pc + 1)
end

classes[14].project_native_path = function(self, proto, pc, cc, on_occurrence, on_rejected)
    local key = proto.k[self.C + 1]
    if key == nil then return on_rejected(cc, MissingConstant(pc, self.C)) end
    return key:project_getfield(pc, self.A, self.B, cc, on_occurrence, on_rejected)
end

classes[17].project_native_path = function(self, proto, pc, cc, on_occurrence, on_rejected)
    local value = rk_value(proto, pc, cc, on_rejected, self.name, self.C, self.k)
    if value == nil then return value end
    local o = TableOps.SetIOccurrence.new(pc, self.A, self.B, value.reg or 0)
    if value.const then o.const_value = value.const end
    return on_occurrence(cc, o, pc + 1)
end

classes[18].project_native_path = function(self, proto, pc, cc, on_occurrence, on_rejected)
    local value = rk_value(proto, pc, cc, on_rejected, self.name, self.C, self.k)
    if value == nil then return value end
    local key = proto.k[self.B + 1]
    if key == nil then return on_rejected(cc, MissingConstant(pc, self.B)) end
    return key:project_setfield(pc, self.A, value, cc, on_occurrence, on_rejected)
end

-- Standalone JMP (56): an unconditional terminal. The projection resolves
-- target = pc + sJ + 1 (lvm.c:dojump); the occurrence stores it and the
-- host resumes there. Comparison/test opcodes consume their own following
-- JMP, so a standalone JMP is a loop back-edge or forward branch.
classes[56].project_native_path = function(self, _proto, pc, cc, on_occurrence, _on_rejected)
    return on_occurrence(cc, Jmp.JmpOccurrence.new(pc, pc + 1 + self.sJ), pc + 1)
end

-- Comparisons and tests (56-67) own their following JMP. The taken branch
-- exits at target = jmp_pc + sJ + 1; the not-taken path falls through to
-- the instruction after the JMP.
local function owned_jmp_target(proto, pc, cc, on_rejected, opcode)
    local jmp = proto.code[pc + 2]
    if jmp == nil or jmp.name ~= "JMP" then
        return on_rejected(cc, MalformedComparison(pc, opcode))
    end
    return pc + 2 + jmp.sJ
end

classes[57].project_native_path = function(self, _proto, pc, cc, on_occurrence, on_rejected)
    local target = owned_jmp_target(_proto, pc, cc, on_rejected, self.name)
    if target == nil then return target end
    return on_occurrence(cc, Compare.EqOccurrence.new(pc, self.A, self.B, self.k, target), pc + 2)
end

classes[58].project_native_path = function(self, _proto, pc, cc, on_occurrence, on_rejected)
    local target = owned_jmp_target(_proto, pc, cc, on_rejected, self.name)
    if target == nil then return target end
    return on_occurrence(cc, Compare.LtOccurrence.new(pc, self.A, self.B, self.k, target), pc + 2)
end

classes[59].project_native_path = function(self, _proto, pc, cc, on_occurrence, on_rejected)
    local target = owned_jmp_target(_proto, pc, cc, on_rejected, self.name)
    if target == nil then return target end
    return on_occurrence(cc, Compare.LeOccurrence.new(pc, self.A, self.B, self.k, target), pc + 2)
end

classes[60].project_native_path = function(self, proto, pc, cc, on_occurrence, on_rejected)
    local target = owned_jmp_target(proto, pc, cc, on_rejected, self.name)
    if target == nil then return target end
    local constant = proto.k[self.B + 1]
    if constant == nil then return on_rejected(cc, MissingConstant(pc, self.B)) end
    return on_occurrence(cc,
        Compare.EqKOccurrence.new(pc, self.A, constant, self.k, target, cc.heap_owner), pc + 2)
end

local function reg_imm_projection(proto, self, pc, cc, on_occurrence, on_rejected, klass)
    local target = owned_jmp_target(proto, pc, cc, on_rejected, self.name)
    if target == nil then return target end
    return on_occurrence(cc, klass.new(pc, self.A, self.sB, self.k, target), pc + 2)
end

classes[61].project_native_path = function(self, proto, pc, cc, on_occurrence, on_rejected)
    return reg_imm_projection(proto, self, pc, cc, on_occurrence, on_rejected, Compare.EqIOccurrence)
end

classes[62].project_native_path = function(self, proto, pc, cc, on_occurrence, on_rejected)
    return reg_imm_projection(proto, self, pc, cc, on_occurrence, on_rejected, Compare.LtIOccurrence)
end

classes[63].project_native_path = function(self, proto, pc, cc, on_occurrence, on_rejected)
    return reg_imm_projection(proto, self, pc, cc, on_occurrence, on_rejected, Compare.LeIOccurrence)
end

classes[64].project_native_path = function(self, proto, pc, cc, on_occurrence, on_rejected)
    return reg_imm_projection(proto, self, pc, cc, on_occurrence, on_rejected, Compare.GtIOccurrence)
end

classes[65].project_native_path = function(self, proto, pc, cc, on_occurrence, on_rejected)
    return reg_imm_projection(proto, self, pc, cc, on_occurrence, on_rejected, Compare.GeIOccurrence)
end

classes[66].project_native_path = function(self, _proto, pc, cc, on_occurrence, on_rejected)
    local target = owned_jmp_target(_proto, pc, cc, on_rejected, self.name)
    if target == nil then return target end
    return on_occurrence(cc, Compare.TestOccurrence.new(pc, self.A, self.k, target), pc + 2)
end

classes[67].project_native_path = function(self, _proto, pc, cc, on_occurrence, on_rejected)
    local target = owned_jmp_target(_proto, pc, cc, on_rejected, self.name)
    if target == nil then return target end
    return on_occurrence(cc, Compare.TestSetOccurrence.new(pc, self.A, self.B, self.k, target), pc + 2)
end

-- Arithmetic (21-45, POW deferred): the primitive owns its companion. A
-- numeric success skips the companion (advance by 2); a non-numeric operand
-- is the companion path (metamethod/error), rejected at learn time.
local function owned_companion(proto, pc, cc, on_rejected, opcode, companion_name)
    local companion = proto.code[pc + 2]
    if companion == nil or companion.name ~= companion_name then
        return on_rejected(cc, MalformedComparison(pc, opcode))
    end
    return true
end

local function const_number(proto, pc, cc, on_rejected, opcode, index)
    local constant = proto.k[index + 1]
    if constant == nil then return on_rejected(cc, MissingConstant(pc, index)) end
    if constant.t ~= "int" and constant.t ~= "flt" then
        return on_rejected(cc, UnsupportedConstant(pc, constant))
    end
    return constant
end

local arith_rr = {
    { 34, "MMBIN", Arith.AddOccurrence }, { 35, "MMBIN", Arith.SubOccurrence },
    { 36, "MMBIN", Arith.MulOccurrence }, { 37, "MMBIN", Arith.ModOccurrence },
    { 39, "MMBIN", Arith.DivOccurrence }, { 40, "MMBIN", Arith.IDivOccurrence },
    { 41, "MMBIN", Arith.BandOccurrence }, { 42, "MMBIN", Arith.BorOccurrence },
    { 43, "MMBIN", Arith.BXorOccurrence }, { 44, "MMBIN", Arith.ShlOccurrence },
    { 45, "MMBIN", Arith.ShrOccurrence },
}
for _, item in ipairs(arith_rr) do
    local opcode, companion, klass = item[1], item[2], item[3]
    classes[opcode].project_native_path = function(self, proto, pc, cc, on_occurrence, on_rejected)
        local ok = owned_companion(proto, pc, cc, on_rejected, self.name, companion)
        if ok ~= true then return ok end
        return on_occurrence(cc, klass.new(pc, self.A, self.B, self.C), pc + 2)
    end
end

local arith_ri = {
    { 21, "MMBINI", Arith.AddIOccurrence }, { 32, "MMBINI", Arith.ShlIOccurrence },
    { 33, "MMBINI", Arith.ShrIOccurrence },
}
for _, item in ipairs(arith_ri) do
    local opcode, companion, klass = item[1], item[2], item[3]
    classes[opcode].project_native_path = function(self, proto, pc, cc, on_occurrence, on_rejected)
        local ok = owned_companion(proto, pc, cc, on_rejected, self.name, companion)
        if ok ~= true then return ok end
        return on_occurrence(cc, klass.new(pc, self.A, self.B, self.sC), pc + 2)
    end
end

local arith_rk = {
    { 22, "MMBINK", Arith.AddKOccurrence }, { 23, "MMBINK", Arith.SubKOccurrence },
    { 24, "MMBINK", Arith.MulKOccurrence }, { 25, "MMBINK", Arith.ModKOccurrence },
    { 27, "MMBINK", Arith.DivKOccurrence }, { 28, "MMBINK", Arith.IDivKOccurrence },
    { 29, "MMBINK", Arith.BandKOccurrence }, { 30, "MMBINK", Arith.BorKOccurrence },
    { 31, "MMBINK", Arith.BXorKOccurrence },
}
for _, item in ipairs(arith_rk) do
    local opcode, companion, klass = item[1], item[2], item[3]
    classes[opcode].project_native_path = function(self, proto, pc, cc, on_occurrence, on_rejected)
        local ok = owned_companion(proto, pc, cc, on_rejected, self.name, companion)
        if ok ~= true then return ok end
        local constant = const_number(proto, pc, cc, on_rejected, self.name, self.C)
        if constant == nil then return constant end
        return on_occurrence(cc, klass.new(pc, self.A, self.B, constant), pc + 2)
    end
end

-- POW (38) / POWK (26): floats-only exponentiation through the patched
-- libm pow() address; the primitive owns its companion like the arith
-- family (numeric success skips it; non-numeric is the __pow path).
classes[38].project_native_path = function(self, proto, pc, cc, on_occurrence, on_rejected)
    local ok = owned_companion(proto, pc, cc, on_rejected, self.name, "MMBIN")
    if ok ~= true then return ok end
    return on_occurrence(cc, Pow.PowOccurrence.new(pc, self.A, self.B, self.C), pc + 2)
end

classes[26].project_native_path = function(self, proto, pc, cc, on_occurrence, on_rejected)
    local ok = owned_companion(proto, pc, cc, on_rejected, self.name, "MMBINK")
    if ok ~= true then return ok end
    local constant = const_number(proto, pc, cc, on_rejected, self.name, self.C)
    if constant == nil then return constant end
    return on_occurrence(cc, Pow.PowKOccurrence.new(pc, self.A, self.B, constant), pc + 2)
end

-- Unary family (49-52, UNM BNOT NOT LEN): standalone. Lua 5.5 emits no
-- MMBIN companion for unary ops; the native path falls through at pc + 1
-- and rejects the non-primitive shapes (metamethod/error) to the host.
local unary_ops = {
    { 49, Unary.UnmOccurrence }, { 50, Unary.BnotOccurrence },
    { 51, Unary.NotOccurrence }, { 52, Unary.LenOccurrence },
}
for _, item in ipairs(unary_ops) do
    local opcode, klass = item[1], item[2]
    classes[opcode].project_native_path = function(self, _proto, pc, cc, on_occurrence, _on_rejected)
        return on_occurrence(cc, klass.new(pc, self.A, self.B), pc + 1)
    end
end

-- Generic tables (11/12/15/16/19/20): metatable-absent fast path with
-- identity + shape + key guards. GETTABLE/SETTABLE use runtime register
-- keys; GETTABUP/SETTABUP read the receiver from an upvalue cell and the
-- key from a constant; SELF reads the receiver from a register and the
-- key from a constant; NEWTABLE bumps a fresh guest table each run.
classes[12].project_native_path = function(self, _proto, pc, cc, on_occurrence, _on_rejected)
    return on_occurrence(cc, GTable.GenericTableOccurrence.gettable(pc, self.A, self.B, self.C), pc + 1)
end


classes[16].project_native_path = function(self, proto, pc, cc, on_occurrence, on_rejected)
    local value = rk_value(proto, pc, cc, on_rejected, self.name, self.C, self.k)
    if value == nil then return value end
    local o = GTable.GenericTableOccurrence.settable(pc, self.A, self.B,
        value.reg or 0)
    if value.const then o.const_value = value.const end
    return on_occurrence(cc, o, pc + 1)
end

local function constant_key(proto, pc, cc, on_rejected, opcode, index)
    local constant = proto.k[index + 1]
    if constant == nil then return on_rejected(cc, MissingConstant(pc, index)) end
    if constant.t ~= "int" and constant.t ~= "str" then
        return on_rejected(cc, UnsupportedConstant(pc, constant))
    end
    if constant.t == "str" then
        -- resolve the interned reference through the guest heap
        local heap_owner = cc.heap_owner
        if heap_owner == nil then
            return on_rejected(cc, UnsupportedConstant(pc, constant))
        end
        local key_owner = heap_owner:short_string(constant.v)
        return { t = "short", v = constant.v, reference = key_owner:reference() }
    end
    return constant
end

classes[11].project_native_path = function(self, proto, pc, cc, on_occurrence, on_rejected)
    -- GETTABUP A B C: R[A] = UpValue[B][K[C]]
    local constant = constant_key(proto, pc, cc, on_rejected, self.name, self.C)
    if constant == nil then return constant end
    return on_occurrence(cc,
        GTable.GenericTableOccurrence.gettabup(pc, self.A, self.B, constant), pc + 1)
end

classes[15].project_native_path = function(self, proto, pc, cc, on_occurrence, on_rejected)
    -- SETTABUP A B C: UpValue[A][K[B]] = R[C]
    local constant = constant_key(proto, pc, cc, on_rejected, self.name, self.B)
    if constant == nil then return constant end
    return on_occurrence(cc,
        GTable.GenericTableOccurrence.settabup(pc, self.A, constant, self.C), pc + 1)
end

classes[20].project_native_path = function(self, proto, pc, cc, on_occurrence, on_rejected)
    local constant = constant_key(proto, pc, cc, on_rejected, self.name, self.C)
    if constant == nil then return constant end
    return on_occurrence(cc,
        GTable.GenericTableOccurrence.self(pc, self.A, self.B, constant), pc + 1)
end

classes[19].project_native_path = function(self, proto, pc, cc, on_occurrence, on_rejected)
    -- NEWTABLE A vB vC k: vB = log2(hash)+1 (6-bit), vC = array size
    -- (10-bit, ivABC layout); the next instruction is ALWAYS an EXTRAARG
    -- carrying the high array bits (each Ax unit = MAXARG_vC + 1 = 1024).
    local array_cap = self.vC
    local next_pc = pc + 1
    local extra = proto.code[pc + 2]
    if extra ~= nil and extra.name == "EXTRAARG" then
        array_cap = array_cap + extra.Ax * 1024
        next_pc = pc + 2
    end
    local hash_cap = self.vB > 0 and (2 ^ (self.vB - 1)) or 0
    return on_occurrence(cc,
        GTable.GenericTableOccurrence.newtable(pc, self.A, array_cap, hash_cap), next_pc)
end

-- CLOSE (54) is a pass-through (the closed subset has no to-be-closed
-- vars); TBC (55) rejects (the <close> contract); ERRNNIL (82) errors on
-- a non-nil register ("global already defined").
classes[54].project_native_path = function(self, _proto, pc, cc, on_occurrence, _on_rejected)
    return on_occurrence(cc, Close.CloseOccurrence.new(pc, self.A), pc + 1)
end

classes[55].project_native_path = function(self, _proto, pc, cc, on_occurrence, _on_rejected)
    return on_occurrence(cc, Close.TbcOccurrence.new(pc, self.A), pc + 1)
end

classes[82].project_native_path = function(self, _proto, pc, cc, on_occurrence, _on_rejected)
    return on_occurrence(cc, Close.ErrnnilOccurrence.new(pc, self.A), pc + 1)
end

-- Generic for (75-77): TFORPREP swaps the closing/control registers and is
-- a terminal to the TFORCALL pc; TFORCALL is a host iterator dispatch
-- boundary; TFORLOOP tests the control var and is a terminal to the body.
classes[75].project_native_path = function(self, _proto, pc, cc, on_occurrence, _on_rejected)
    return on_occurrence(cc,
        TFor.TForPrepOccurrence.new(pc, self.A, pc + self.Bx + 1), pc + 1)
end

classes[76].project_native_path = function(self, _proto, pc, cc, on_occurrence, _on_rejected)
    return on_occurrence(cc, TFor.TForCallOccurrence.new(pc, self.A, self.C), pc + 1)
end

classes[77].project_native_path = function(self, _proto, pc, cc, on_occurrence, _on_rejected)
    return on_occurrence(cc,
        TFor.TForLoopOccurrence.new(pc, self.A, pc - self.Bx + 1), pc + 1)
end

-- FORLOOP (73): the numeric-for terminal. The host FORPREP (74) boundary
-- prepared the cells (integer: R[A]=count, R[A+1]=step, R[A+2]=idx;
-- float: R[A]=limit, R[A+1]=step, R[A+2]=idx). The FORLOOP updates
-- the control variable and reports the back-edge (pc + 1 - Bx, the
-- body start) or the fallthrough (pc + 1).
classes[73].project_native_path = function(self, _proto, pc, cc, on_occurrence, _on_rejected)
    return on_occurrence(cc,
        ForLoop.ForLoopOccurrence.new(pc, self.A, pc + 1 - self.Bx), pc + 1)
end

-- VARARG (80): R[A..A+C-2] = the varargs (C-1 values; C=0 = all). The
-- VARARG (80): R[A..A+C-2] = the varargs (C-1 values; C=0 = all). The
-- host arranges the frame (extra args in R[numparams..], vararg_count set).
classes[80].project_native_path = function(self, _proto, pc, cc, on_occurrence, _on_rejected)
    local wanted = self.C - 1
    if self.C == 0 then wanted = 0xFFFFFFFF end
    return on_occurrence(cc,
        Vararg.VarargOccurrence.new(pc, self.A, cc.proto.numparams, wanted), pc + 1)
end

-- GETVARG (81): R[A] := R[B][R[C]] — the vararg at the runtime index R[C]
-- (integer) or the count (the "n" string).
classes[81].project_native_path = function(self, _proto, pc, cc, on_occurrence, _on_rejected)
    return on_occurrence(cc,
        Vararg.GetVargOccurrence.new(pc, self.A, cc.proto.numparams, self.C), pc + 1)
end

-- CONCAT (53): R[A] := R[A] .. R[A+1] .. ... .. R[A+B-1] (string operands).
classes[53].project_native_path = function(self, _proto, pc, cc, on_occurrence, _on_rejected)
    return on_occurrence(cc,
        Concat.ConcatOccurrence.new(pc, self.A, self.A, self.B), pc + 1)
end

-- CLOSURE (79): R[A] := closure(proto K[Bx], upvalues). The closure's
-- upvalue descriptors come from the target proto (bounded at 4).
classes[79].project_native_path = function(self, proto, pc, cc, on_occurrence, on_rejected)
    local target_proto = proto.protos[self.Bx + 1]
    if target_proto == nil then return on_rejected(cc, MissingInstruction(pc)) end
    local descriptors = target_proto.upvals or {}
    if #descriptors > 4 then
        return on_rejected(cc, UnsupportedOpcode(pc, self.name))
    end
    return on_occurrence(cc,
        Closure.ClosureOccurrence.new(pc, self.A, self.Bx, descriptors), pc + 1)
end

-- SETLIST (78): R[A][C+i] := R[A+i] for 1 <= i <= B. The k flag folds
-- the following EXTRAARG's high array bits into C. The B == 0 "up to", "top"
-- form and out-of-capacity writes reject (host resizes).
classes[78].project_native_path = function(self, proto, pc, cc, on_occurrence, on_rejected)
    -- SETLIST A vB vC k (ivABC layout): R[A][C+i] := R[A+i], 1 <= i <= B.
    local A, B, C, next_pc = self.A, self.vB, self.vC, pc + 1
    if self.k ~= 0 then
        local extra = proto.code[pc + 2]
        if extra ~= nil and extra.name == "EXTRAARG" then
            C = C + extra.Ax * 1024
            next_pc = pc + 2
        end
    end
    if B == 0 then
        return on_rejected(cc, UnsupportedOpcode(pc, self.name))
    end
    return on_occurrence(cc, SetList.SetListOccurrence.new(pc, A, B, C), next_pc)
end

-- Returns (70-72): native terminals. The host reads (A, B) from the
-- occurrence to extract results across the call boundary.
classes[70].project_native_path = function(self, _proto, pc, cc, on_occurrence, _on_rejected)
    return on_occurrence(cc, Call.ReturnOccurrence.new(pc, self.A, self.B), pc + 1)
end
classes[71].project_native_path = function(self, _proto, pc, cc, on_occurrence, _on_rejected)
    return on_occurrence(cc, Call.Return0Occurrence.new(pc), pc + 1)
end
classes[72].project_native_path = function(self, _proto, pc, cc, on_occurrence, _on_rejected)
    return on_occurrence(cc, Call.Return1Occurrence.new(pc, self.A), pc + 1)
end

local M = {}
-- Host-mediated calls: CALL (68) / TAILCALL (69) are host dispatch
-- boundaries, not native occurrences. project_call_plan splits the proto
-- into straight-line basic blocks at every control edge and call:
--   - a block ends before a CALL/TAILCALL pc (host dispatch boundary),
--     at a standalone JMP (included, terminal), at a compare+owned-JMP
--     (compare included; the owned JMP's target starts a block), or at a
--     RETURN/RETURN0/RETURN1 (included, terminal);
--   - every branch target starts a block.
-- The host driver walks pcs: run the block at pc, follow resume_pc to the
-- next block start, a call boundary (dispatch), or a return (copy results
-- into the caller's destination). TAILCALL passes the outer result
-- destination through, making the tail callee's results land directly in
-- the ultimate caller's registers.
local compare_names = {}
for _, name in ipairs({ "EQ", "LT", "LE", "EQK", "EQI", "LTI", "LEI", "GTI", "GEI", "TEST", "TESTSET" }) do
    compare_names[name] = true
end

-- The compiler only jumps to basic-block starts: the entry (pc 0) or a pc
-- immediately after a terminator (call, standalone JMP, return) or after
-- a compare's owned JMP. So every branch target coincides with a segment
-- start produced by the split walk below; the walk asserts this.
function M.project_call_plan(proto, heap_owner)
    local blocks, calls, returns, block_at, forpreps = {}, {}, {}, {}, {}
    local code = proto.code
    local n = #code
    local seg_start = 0
    local pc = 0
    local targets = {}
    local function close_block(start, stop)
        if stop <= start then return end
        local path = M.project(proto, start, stop, heap_owner)
        if M.ProjectionRejected:is(path) then
            error(("call plan segment [%d, %d) rejected: %s"):format(
                start, stop, tostring(path.failure and path.failure.name or "?")))
        end
        local index = #blocks + 1
        blocks[index] = { start = start, stop = stop, path = path }
        block_at[start] = index
        for _, occ in ipairs(path.occurrences) do
            local name = occ.learner_name
            if name == "return" or name == "return0" or name == "return1" then
                returns[occ.pc] = { A = occ.A, B = occ.B }
            end
        end
    end
    while pc < n do
        -- a branch target must start a block: split the current segment
        -- before handling an instruction that a branch lands on
        if targets[pc] and seg_start < pc then
            close_block(seg_start, pc)
            seg_start = pc
        end
        local ins = code[pc + 1]
        local name = ins.name
        if name == "VARARGPREP" then
            -- host-setup boundary: the frame is arranged before the first block
            pc = pc + 1
            seg_start = pc
        elseif name == "FORPREP" then
            -- host-setup boundary: the forprep decision (skip vs entry) is
            -- made by the host; the loop body starts at pc + 1
            close_block(seg_start, pc)
            forpreps[pc] = { A = ins.A, skip_pc = pc + ins.Bx + 2, body_pc = pc + 1 }
            pc = pc + 1
            seg_start = pc
        elseif name == "TFORPREP" then
            close_block(seg_start, pc + 1)   -- terminal to the TFORCALL pc
            pc = pc + 1
            seg_start = pc
        elseif name == "TFORCALL" then
            close_block(seg_start, pc)
            calls[pc] = { kind = "tforcall", A = ins.A, C = ins.C }
            pc = pc + 1
            seg_start = pc
        elseif name == "TFORLOOP" then
            close_block(seg_start, pc + 1)   -- terminal: taken back-edge / exit
            pc = pc + 1
            seg_start = pc
        elseif name == "CALL" or name == "TAILCALL" then
            close_block(seg_start, pc)            -- call excluded: host dispatch
            calls[pc] = { A = ins.A, B = ins.B, C = ins.C, tail = name == "TAILCALL" }
            pc = pc + 1
            seg_start = pc
        elseif name == "JMP" then
            close_block(seg_start, pc + 1)        -- the JMP is the last occurrence
            targets[pc + 1 + ins.sJ] = true
            pc = pc + 1
            seg_start = pc
        elseif compare_names[name] then
            -- The compare owns its following JMP and is a terminal (the taken
            -- branch exits). A loop back-edge can target the compare's own pc,
            -- so the compare starts its own block: the segment before it ends
            -- at pc, and the compare's block is [pc, pc + 2).
            close_block(seg_start, pc)
            close_block(pc, pc + 2)
            local jmp = code[pc + 2]
            if jmp ~= nil and jmp.name == "JMP" then
                targets[pc + 2 + jmp.sJ] = true
            end
            pc = pc + 2
            seg_start = pc
        elseif name == "FORLOOP" then
            close_block(seg_start, pc + 1)   -- terminal: the FORLOOP is the last occurrence
            targets[pc + 1 - ins.Bx] = true  -- the back-edge (the body start)
            pc = pc + 1
            seg_start = pc
        elseif name == "RETURN" or name == "RETURN0" or name == "RETURN1" then
            close_block(seg_start, pc + 1)        -- the return is the last occurrence
            pc = pc + 1
            seg_start = pc
        else
            pc = pc + 1
        end
    end
    close_block(seg_start, n)
    for target in pairs(targets) do
        assert(block_at[target] ~= nil,
            ("branch target %d is not a block start"):format(target))
    end
    return {
        proto = proto, n = n, blocks = blocks, calls = calls, returns = returns,
        block_at = block_at, forpreps = forpreps,
    }
end

function M.project(proto, start_pc, stop_pc, heap_owner)
    return Projector.new(proto, start_pc, stop_pc, heap_owner):project_current()
end

M.DecodedPath = DecodedPath
M.ProjectionRejected = ProjectionRejected
M.failures = {
    UnsupportedOpcode = UnsupportedOpcode, MissingInstruction = MissingInstruction,
    MissingConstant = MissingConstant, MalformedLoadKX = MalformedLoadKX,
    UnsupportedConstant = UnsupportedConstant, UnsupportedRKConstant = UnsupportedRKConstant,
    InvalidProjectionRange = InvalidProjectionRange,
}

return M
