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
    patch_many(arena, offset, record.holes[role .. "_reserved"], base + 4, patch_i32)
end

-- VARARG (80) / GETVARG (81): the host arranges the frame (extra args in
-- R[numparams..], vararg_count set); the native recomputes each run.
local function append_occurrence(arena, record, occurrence, with_quote)
    local offset = arena:append(record)
    patch_value_index(arena, offset, record, "target", occurrence.target)
    if occurrence.key ~= nil then
        patch_value_index(arena, offset, record, "key", occurrence.key)
    end
    patch_many(arena, offset, record.holes.nfix, occurrence.nfix, patch_i32)
    patch_many(arena, offset, record.holes.wanted, occurrence.wanted, patch_i32)
    patch_many(arena, offset, record.holes.base_reg, occurrence.target, patch_i32)
    patch_many(arena, offset, record.holes.resume, occurrence.pc, patch_i32)
    if with_quote then
        patch_many(arena, offset, record.holes.quote_base, occurrence.quote_base, patch_i32)
    end
    return offset
end

local VarargOccurrence = {}
VarargOccurrence.__index = VarargOccurrence

-- VARARG: R[target..target+wanted-1] = the varargs (wanted = 0xFFFFFFFF = all).
function VarargOccurrence.new(pc, target, nfix, wanted)
    return setmetatable({
        pc = pc, target = target, nfix = nfix, wanted = wanted,
        fallthrough_pc = pc + 1, quote_base = 80 * 65536,
        learner_name = "vararg",
    }, VarargOccurrence)
end

function VarargOccurrence:append_learner(bank, arena)
    append_occurrence(arena, bank.learners.vararg, self, true)
end

function VarargOccurrence:append_residual(bank, slot, arena)
    local quote = tonumber(slot.quote)
    local record = assert(bank.quotes[quote], "vararg quotation is absent")
    append_occurrence(arena, record, self, false)
end

local GetVargOccurrence = {}
GetVargOccurrence.__index = GetVargOccurrence

-- GETVARG: R[target] = the vararg at the runtime index R[key].
function GetVargOccurrence.new(pc, target, nfix, key)
    return setmetatable({
        pc = pc, target = target, nfix = nfix, key = key,
        fallthrough_pc = pc + 1, quote_base = 81 * 65536,
        learner_name = "getvarg",
    }, GetVargOccurrence)
end

function GetVargOccurrence:append_learner(bank, arena)
    append_occurrence(arena, bank.learners.getvarg, self, true)
end

function GetVargOccurrence:append_residual(bank, slot, arena)
    local quote = tonumber(slot.quote)
    local record = assert(bank.quotes[quote], "getvarg quotation is absent")
    append_occurrence(arena, record, self, false)
end


local function value_disp(index) return index * ffi.sizeof("Lua55ValueV2") end

-- ---- Native CPS Frame V2 leaves ---------------------------------------
function VarargOccurrence:append_v2(machine)
    -- wanted is projection-proven (0xFFFFFFFF = all, otherwise a fixed count)
    local all = self.wanted == 0xFFFFFFFF or self.wanted == -1
    if all then
        machine:emit(assert(machine.bank.residual.vararg_all,
            "cps v2: missing residual vararg_all"), {
            target_index = self.target,
            target_disp = value_disp(self.target),
        })
        return
    end
    local wanted = tonumber(self.wanted)
    assert(wanted >= 0 and wanted <= 254,
        "cps v2: unsupported fixed VARARG count " .. tostring(wanted))
    for slot = 0, wanted - 1 do
        machine:emit(assert(machine.bank.residual.vararg_fixed_slot,
            "cps v2: missing residual vararg_fixed_slot"), {
            target_disp = value_disp(self.target + slot),
            span = slot,
        })
    end
    machine:emit(assert(machine.bank.residual.vararg_fixed_finish,
        "cps v2: missing residual vararg_fixed_finish"), {
        top_index = self.target + wanted,
    })
end
function GetVargOccurrence:append_v2(machine)
    if machine.mode == "learning" then
        machine:emit(machine.bank.learning.getvarg, {
            target_disp = value_disp(self.target),
            key_disp = value_disp(self.key),
            occ_slot = assert(self.learn_slot, "cps v2: getvarg slot unassigned"),
        })
        return
    end
    local f = machine.facts[assert(self.learn_slot,
        "cps v2: getvarg slot unassigned")]
    local name
    if f.key_tag == 3 then name = "getvarg_int"
    elseif f.key_tag == 5 or f.key_tag == 6 then name = "getvarg_n"
    else name = "getvarg_mx" end
    machine:emit(assert(machine.bank.residual[name],
        "cps v2: missing residual " .. name), {
        target_disp = value_disp(self.target),
        key_disp = value_disp(self.key),
    })
end

return {
    VarargOccurrence = VarargOccurrence,
    GetVargOccurrence = GetVargOccurrence,
    ffi = ffi,
}
