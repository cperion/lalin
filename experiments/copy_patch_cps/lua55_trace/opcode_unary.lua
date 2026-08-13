local Native = require("experiments.copy_patch_cps.lua55_trace.opcode_00_08")
local ffi = Native.ffi

local function patch_i32(memory, offset, value)
    assert(value >= -0x80000000 and value <= 0x7fffffff)
    ffi.cast("int32_t *", memory + offset)[0] = value
end

local function patch_many(arena, offset, holes, value, patch)
    if holes == nil then return end
    for index = 1, #holes do patch(arena.memory, offset + holes[index], value) end
end

local function patch_value_index(arena, offset, record, role, index)
    local base = index * ffi.sizeof("Lua55ValueV1")
    patch_many(arena, offset, record.holes[role .. "_tag"], base, patch_i32)
    patch_many(arena, offset, record.holes[role .. "_payload"], base + 8, patch_i32)
end

-- A unary occurrence is standalone: Lua 5.5 emits no MMBIN companion for
-- UNM/BNOT/NOT/LEN (lcode.c:codeunexpval), so the native path falls
-- through at pc + 1 and rejects the non-primitive shapes to the host.
local function append_occurrence(arena, record, occurrence)
    local offset = arena:append(record)
    patch_value_index(arena, offset, record, "target", occurrence.target)
    patch_value_index(arena, offset, record, "source", occurrence.source)
    patch_many(arena, offset, record.holes.target_reserved,
        occurrence.target * ffi.sizeof("Lua55ValueV1") + 4, patch_i32)
    patch_many(arena, offset, record.holes.resume, occurrence.pc, patch_i32)
    patch_many(arena, offset, record.holes.quote_base, occurrence.quote_base, patch_i32)
    return offset
end

local function class()
    local result = {}
    result.__index = result
    return result
end

local UnaryOccurrence = class()

function UnaryOccurrence:append_learner(bank, arena)
    append_occurrence(arena, bank.learners[self.learner_name], self)
end

function UnaryOccurrence:append_residual(bank, slot, arena)
    local quote = tonumber(slot.quote)
    local record = assert(bank.quotes[quote], "unary quotation is absent")
    append_occurrence(arena, record, self)
end

local function base_occurrence(klass, pc, target, source, opcode)
    return setmetatable({
        pc = pc, target = target, source = source,
        fallthrough_pc = pc + 1,   -- standalone: no owned companion
        quote_base = opcode * 65536, learner_name = nil,
    }, klass)
end

local function make_unary(name, opcode)
    local klass = class()
    function klass.new(pc, target, source)
        local occurrence = base_occurrence(klass, pc, target, source, opcode)
        occurrence.learner_name = name
        return occurrence
    end
    return klass
end

local UnmOccurrence = make_unary("unm", 49)
local BnotOccurrence = make_unary("bnot", 50)
local NotOccurrence = make_unary("not", 51)
local LenOccurrence = make_unary("len", 52)

for _, klass in ipairs({ UnmOccurrence, BnotOccurrence, NotOccurrence, LenOccurrence }) do
    klass.__index = klass
    setmetatable(klass, { __index = UnaryOccurrence })
end


-- ---- Native CPS Frame V2 leaves -----------------------------------------
-- Batch 3: exact operand-product leaves. The operand tag is learned in the
-- separate learning invocation; NOT stays green (truthiness is the result).

local function value_disp(index) return index * ffi.sizeof("Lua55ValueV2") end

local function unary_facts(machine, slot)
    local f = machine.facts[assert(slot, "cps v2: unary slot unassigned")]
    if not f or f.seen == 0 then
        error("cps v2: unary occurrence slot " .. tostring(slot)
            .. " was never observed in the learning pass (cold path);"
            .. " refusing to publish a generic fallback", 0)
    end
    if f.key_tag == 0xFFFFFFFF then
        error("cps v2: unary occurrence slot " .. tostring(slot)
            .. " observed conflicting operand tags;"
            .. " refusing to publish a generic fallback", 0)
    end
    return f
end

local function unary_leaf(klass, family, suffix_fn)
    function klass:append_v2(machine)
        if machine.mode == "learning" then
            machine:emit(machine.bank.learning[assert(self.learner_name,
                "cps v2: unary learner missing")], {
                target_disp = value_disp(self.target),
                source_disp = value_disp(self.source),
                occ_slot = assert(self.learn_slot, "cps v2: unary slot unassigned"),
            })
            return
        end
        local f = unary_facts(machine, self.learn_slot)
        local suffix = suffix_fn(f.key_tag)
        machine:emit(assert(machine.bank.residual[family .. "_" .. suffix],
            "cps v2: missing residual " .. family .. "_" .. suffix), {
            target_disp = value_disp(self.target),
            source_disp = value_disp(self.source),
        })
    end
end

unary_leaf(UnmOccurrence, "unm", function(t) return t == 3 and "int" or "flt" end)
unary_leaf(BnotOccurrence, "bnot", function(t) return t == 3 and "int" or "flt" end)
unary_leaf(LenOccurrence, "len", function(t)
    return (t == 5 or t == 6) and "str" or "table"
end)

-- NOT stays green: truthiness is the operation's data result.
function NotOccurrence:append_v2(machine)
    machine:emit(machine.bank.v2[51], {
        target_disp = value_disp(self.target),
        source_disp = value_disp(self.source),
    })
end

return {
    UnmOccurrence = UnmOccurrence,
    BnotOccurrence = BnotOccurrence,
    NotOccurrence = NotOccurrence,
    LenOccurrence = LenOccurrence,
    ffi = ffi,
}
