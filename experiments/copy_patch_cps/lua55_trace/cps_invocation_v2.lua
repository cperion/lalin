-- cps_invocation_v2: the Native CPS Frame V2 runner.
--
-- One outer-invocation-owned mmap data region holds the invocation struct,
-- the immutable function descriptor array, and a bounded nonmoving frame
-- region. The root frame lives in that region; CALL bump-allocates exact
-- callee frames (fixed registers + vararg slice + TBC nodes), TAILCALL
-- replaces the top frame in place, and RETURN pops and jumps to the stored
-- continuation. Only the outer FFI entry and the per-arena host-exit stub
-- execute `ret`. See NATIVE_CPS_V2_COMPLETE_MIGRATION_DESIGN.md.
--
-- The V2 bank is opcode_v2/bank.lua: `lua55_v2_*` opcode residuals and
-- `lua55_cps_*` boundary sections compiled ONLY against opcode_value_v2.h.
-- No V1 poly/learner/residual section participates. LuaJIT stages, owns
-- the outer invocation, and executes explicit host/library calls between
-- typed suspension and re-entry.

local ffi = require("ffi")
local bit = require("bit")

package.path = "./lua/?.lua;./lua/?/init.lua;./?.lua;./?/init.lua;" .. package.path

local Undump = require("experiments.lua55.undump55")
local Native = require("experiments.copy_patch_cps.lua55_trace.opcode_00_08")
local Heap = require("experiments.copy_patch_cps.lua55_trace.guest_heap_v1")
local Run55 = require("experiments.copy_patch_cps.lua55_trace.run55")

ffi.cdef[[
typedef Lua55ValueV1 Lua55ValueV2;
typedef Lua55GuestObjectHeaderV1 Lua55GuestObjectHeaderV2;
typedef Lua55GuestStringV1 Lua55GuestStringV2;
typedef Lua55GuestHeapV1 Lua55GuestHeapV2;
typedef Lua55GuestBuiltinV1 Lua55GuestBuiltinV2;
typedef Lua55GuestTableV1 Lua55GuestTableV2;

typedef struct Lua55NativeFrameV2 Lua55NativeFrameV2;
typedef void (*Lua55NativeEntryV2)(Lua55NativeFrameV2 *);

typedef struct Lua55NativeFunctionDescriptorV2 {
    Lua55NativeEntryV2 entry;
    uint32_t maxstacksize;
    uint32_t numparams;
    uint32_t is_vararg;
    uint32_t upvalue_count;
    uint32_t tbc_capacity;
    uint32_t value_capacity;
} Lua55NativeFunctionDescriptorV2;

typedef struct Lua55NativeReturnLinkV2 {
    Lua55NativeEntryV2 entry;
    Lua55NativeFrameV2 *subject;
} Lua55NativeReturnLinkV2;

typedef struct Lua55NativeResultSinkV2 {
    Lua55ValueV2 *values;
    uint32_t *top;
    uint32_t base;
    int32_t count;
    uint32_t capacity;
} Lua55NativeResultSinkV2;

typedef struct Lua55TbcNodeV2 {
    uint32_t register_index;
    uint32_t state;
    Lua55ValueV2 value;
} Lua55TbcNodeV2;

typedef struct Lua55UpvalueCellV2 {
    Lua55ValueV2 *open_slot;
    Lua55ValueV2 closed_value;
    struct Lua55UpvalueCellV2 *next_open;
    uint32_t state;
    uint32_t generation;
} Lua55UpvalueCellV2;

typedef struct Lua55HostCallPayloadV2 {
    Lua55NativeEntryV2 resume_entry;
    uint32_t a;
    uint32_t b;
    uint32_t c;
    uint32_t pc;
    uint32_t host_id;
    uint32_t reserved;
} Lua55HostCallPayloadV2;

typedef struct Lua55HostTailCallPayloadV2 {
    Lua55NativeEntryV2 tail_return_entry;
    uint32_t a;
    uint32_t b;
    uint32_t pc;
    uint32_t host_id;
} Lua55HostTailCallPayloadV2;

typedef struct Lua55OverflowPayloadV2 {
    uint64_t required;
    uint64_t available;
    uint32_t pc;
    uint32_t reserved;
} Lua55OverflowPayloadV2;

typedef struct Lua55ErrorPayloadV2 {
    uint32_t error_kind;
    uint32_t pc;
    Lua55ValueV2 value;
} Lua55ErrorPayloadV2;

typedef struct Lua55RejectedPayloadV2 {
    uint32_t rejection_kind;
    uint32_t opcode;
    uint32_t pc;
    uint32_t expected_tag;
    uint32_t observed_tag;
} Lua55RejectedPayloadV2;

typedef struct Lua55TableLearnSlotV2 {
    uint32_t key_tag;
    uint32_t value_tag;
    uint64_t max_array_index;
    uint32_t max_field_count;
    uint32_t seen;
    uint32_t field_slot;
    uint32_t field_layout_capacity;
    uint32_t field_state;
    uint32_t field_site_id;
} Lua55TableLearnSlotV2;

typedef struct Lua55NativeBoundaryOutcomeV2 {
    uint32_t discriminant;
    uint32_t result_count;
    union {
        Lua55HostCallPayloadV2 host_call;
        Lua55HostTailCallPayloadV2 host_tail_call;
        Lua55OverflowPayloadV2 overflow;
        Lua55ErrorPayloadV2 error;
        Lua55RejectedPayloadV2 rejected;
    } u;
} Lua55NativeBoundaryOutcomeV2;

typedef struct Lua55PreparedCallV2 {
    Lua55NativeFrameV2 *callee;
    Lua55NativeEntryV2 entry;
    uint8_t *next_frame;
    uint32_t nparams;
    uint32_t nargs;
} Lua55PreparedCallV2;

typedef struct Lua55PreparedTailCallV2 {
    Lua55NativeEntryV2 entry;
    Lua55UpvalueCellV2 **upvalues;
    uint8_t *frame_end;
    uint32_t nparams;
    uint32_t nargs;
    uint32_t vararg_count;
    uint32_t maxstack;
    uint32_t value_capacity;
    uint32_t tbc_capacity;
} Lua55PreparedTailCallV2;

typedef struct Lua55PreparedConcatV2 {
    uint64_t total;
    Lua55GuestStringV2 *string;
    uint8_t *out;
} Lua55PreparedConcatV2;

typedef struct Lua55NativeInvocationV2 {
    uint8_t *frame_begin;
    uint8_t *frame_next;
    uint8_t *frame_end;
    Lua55NativeFrameV2 *current_frame;
    Lua55NativeFunctionDescriptorV2 *functions;
    uint32_t function_count;
    uint32_t open_value_capacity;
    Lua55GuestHeapV2 *heap;
    Lua55ValueV2 *result_values;
    uint32_t result_capacity;
    uint32_t result_count;
    uint8_t *learning;
    uint32_t learning_capacity;
    uint32_t learning_slots;
    Lua55NativeBoundaryOutcomeV2 outcome;
    Lua55PreparedCallV2 prepared_call;
    Lua55PreparedTailCallV2 prepared_tail_call;
    Lua55PreparedConcatV2 prepared_concat;
    struct {
        uint32_t pc;
        uint32_t expected_tag;
        uint32_t observed_tag;
        uint32_t reserved;
    } specialization_mismatch;
} Lua55NativeInvocationV2;

typedef struct Lua55NativeFrameV2 {
    Lua55NativeInvocationV2 *invocation;
    Lua55NativeFrameV2 *caller;
    Lua55NativeReturnLinkV2 return_link;
    Lua55NativeResultSinkV2 result_sink;
    Lua55UpvalueCellV2 **upvalues;
    Lua55UpvalueCellV2 *open_upvalues;
    Lua55TbcNodeV2 *tbc_nodes;
    Lua55ValueV2 *values;
    uint32_t value_count;
    uint32_t value_capacity;
    uint32_t top;
    uint32_t vararg_count;
    uint32_t tbc_count;
    uint32_t tbc_capacity;
} Lua55NativeFrameV2;
]]

local OUTCOME_EXECUTING = 0
local OUTCOME_RETURNED = 1
local OUTCOME_HOST_CALL = 2
local OUTCOME_HOST_TAIL_CALL = 3
local OUTCOME_STACK_OVERFLOW = 4
local OUTCOME_VALUE_OVERFLOW = 5
local OUTCOME_HEAP_OVERFLOW = 6
local OUTCOME_GUEST_ERROR = 7
local OUTCOME_REJECTED = 8

local TAG = {
    nil_value = 0, false_value = 1, true_value = 2,
    integer = 3, floating = 4, short_string = 5, long_string = 6,
    table_value = 7, closure_value = 8,
}

local PROT_READ, PROT_WRITE, PROT_EXEC = 1, 2, 4
local MAP_PRIVATE, MAP_ANONYMOUS = 0x02, 0x20
local MAP_FAILED = ffi.cast("void *", -1)

local FRAME_SIZE = ffi.sizeof("Lua55NativeFrameV2")
local VALUE_BYTES = ffi.sizeof("Lua55ValueV2")
local CELL_SIZE = ffi.sizeof("Lua55UpvalueCellV2")
local PTR_CELL_SIZE = ffi.sizeof("Lua55UpvalueCellV2 *")
local INV_SIZE = ffi.sizeof("Lua55NativeInvocationV2")

local function align16(n) return bit.band(n + 15, bit.bnot(15)) end

local function patch_i32(memory, offset, value)
    ffi.cast("int32_t *", memory + offset)[0] = value
end
local function patch_u64(memory, offset, value)
    ffi.cast("uint64_t *", memory + offset)[0] = value
end
local function patch_hole(arena, offset, holes, value, kind)
    if not holes then return end
    if kind == "u64" then
        for _, at in ipairs(holes) do patch_u64(arena.memory, offset + at, value) end
    else
        for _, at in ipairs(holes) do patch_i32(arena.memory, offset + at, value) end
    end
end

-- ---- the V2 bank --------------------------------------------------------

local V2_BANK = dofile("target/copy_patch_cps/lua55_trace/opcode_v2/bank.lua")

-- ---- the leaf-owned arena builder ---------------------------------------

-- The machine passed to every occurrence's append_v2. It owns the arena,
-- the bank, the plan (for closure proto facts and call boundaries), and the
-- deferred link/continuation patch lists. Emit product contract:
--   product[kind]       32-bit hole value
--   product["u64:"..k]  64-bit hole value
--   product["link:"..k] deferred absolute link to block start target
--   product["const"]    decoded constant facts {tag, int_bits, flt_bits, ref}
--   product["host_exit"]=true collects the record's host-exit holes
local V2Machine = {}
V2Machine.__index = V2Machine

function V2Machine.new(arena, bank, plan, mode, facts)
    local self = setmetatable({
        arena = arena, bank = bank, plan = plan,
        mode = mode or "residual",
        facts = facts or {},
        links = {}, continuations = {}, host_exits = {}, mismatch_exits = {},
        tail_returns = {}, table_data_exits = {}, base = 0,
        hole_sites = {}, emissions = {},
    }, V2Machine)
    return self
end

local function hole_site_key(at, width) return tostring(at) .. ":" .. tostring(width) end

function V2Machine:append_record(record)
    local offset = self.arena:append(record)
    self.emissions[#self.emissions + 1] = {
        offset = offset, size = #record.code, record = record.__name, pc = self.pc,
    }
    for _, site in ipairs(record.hole_sites or {}) do
        local absolute = offset + site.at
        local key = hole_site_key(absolute, site.width)
        assert(not self.hole_sites[key],
            "cps v2: duplicate physical hole site " .. key)
        self.hole_sites[key] = {
            at = absolute, width = site.width, kind = site.kind, role = site.role,
            record = record.__name, patched = false,
        }
    end
    return offset
end

function V2Machine:mark_patch(at, width)
    local key = hole_site_key(at, width)
    local site = self.hole_sites[key]
    assert(site, ("cps v2: patch does not name a declared physical hole at %s")
        :format(key))
    site.patched = true
end

function V2Machine:patch_holes(offset, holes, value, encoding, label)
    assert(holes and #holes > 0, ("cps v2: %s has no declared %s hole")
        :format(label.record, label.kind))
    local width = encoding == "u64" and 8 or 4
    patch_hole(self.arena, offset, holes, value, encoding)
    for _, at in ipairs(holes) do self:mark_patch(offset + at, width) end
end

function V2Machine:patch_at(at, value, encoding)
    local width = encoding == "u64" and 8 or 4
    if encoding == "u64" then patch_u64(self.arena.memory, at, value)
    else patch_i32(self.arena.memory, at, value) end
    self:mark_patch(at, width)
end

function V2Machine:validate_product(record, product)
    local holes = record.holes
    for kind, value in pairs(product) do
        local physical = kind
        if kind == "const" then
            assert(value ~= nil, "cps v2: nil constant product for " .. record.__name)
            assert(holes.const_tag or holes.const_int or holes.const_flt or holes.const_ref,
                "cps v2: " .. record.__name .. " has no constant holes")
        elseif kind == "host_exit" then
            assert(value == true and holes.host_exit and #holes.host_exit > 0,
                "cps v2: invalid host_exit product for " .. record.__name)
        else
            if kind:sub(1, 5) == "u64::" or kind:sub(1, 5) == "link:" then
                physical = kind:sub(6)
            end
            assert(holes[physical] and #holes[physical] > 0,
                ("cps v2: unknown product hole %s for %s")
                    :format(kind, record.__name))
        end
    end
end

function V2Machine:assert_all_holes_patched()
    local missing = {}
    for _, site in pairs(self.hole_sites) do
        if not site.patched then
            missing[#missing + 1] = ("%s.%s@%d+%d[%s]")
                :format(site.record, site.kind, site.at, site.width, site.role)
        end
    end
    table.sort(missing)
    assert(#missing == 0, "cps v2: unpatched executable holes: " .. table.concat(missing, ", "))
end

-- Capacity and field presence are mutable table data, not learned semantic
-- alternatives. These two exact publication leaves own the NeedGrow and
-- NeedCreate exits and append their operation-specific cold implementation.
local NeedGrowV2 = {}
NeedGrowV2.__index = NeedGrowV2

function NeedGrowV2.new(machine, hot_record, cold_name, product)
    local links = assert(hot_record.holes.need_grow_link,
        "cps v2: NeedGrow hot leaf has no need_grow_link")
    assert(#links == 1, "cps v2: NeedGrow hot leaf must own one data exit")
    local offset = machine:emit(hot_record, product)
    return setmetatable({
        exit_link_at = offset + links[1],
        resume_addr = machine.base + machine.arena.cursor,
        cold_name = cold_name, pc = machine.pc, product = product,
    }, NeedGrowV2), offset
end

function NeedGrowV2:append_cold(machine, base, bank)
    local cold = assert(bank.residual[self.cold_name],
        "cps v2: missing NeedGrow residual " .. tostring(self.cold_name))
    local resumes = assert(cold.holes.resume_link,
        "cps v2: NeedGrow cold leaf has no resume_link")
    assert(#resumes == 1, "cps v2: NeedGrow cold leaf must own one resume")
    local saved_pc = machine.pc
    machine.pc = self.pc
    local cold_offset = machine:emit(cold, self.product)
    machine.pc = saved_pc
    machine:patch_at(self.exit_link_at, base + cold_offset, "u64")
    machine:patch_at(cold_offset + resumes[1], self.resume_addr, "u64")
end

local NeedCreateV2 = {}
NeedCreateV2.__index = NeedCreateV2

function NeedCreateV2.new(machine, hot_record, cold_name, product)
    local links = assert(hot_record.holes.need_create_link,
        "cps v2: NeedCreate hot leaf has no need_create_link")
    assert(#links == 1, "cps v2: NeedCreate hot leaf must own one data exit")
    local offset = machine:emit(hot_record, product)
    return setmetatable({
        exit_link_at = offset + links[1],
        resume_addr = machine.base + machine.arena.cursor,
        cold_name = cold_name, pc = machine.pc, product = product,
    }, NeedCreateV2), offset
end

function NeedCreateV2:append_cold(machine, base, bank)
    local cold = assert(bank.residual[self.cold_name],
        "cps v2: missing NeedCreate residual " .. tostring(self.cold_name))
    local resumes = assert(cold.holes.resume_link,
        "cps v2: NeedCreate cold leaf has no resume_link")
    assert(#resumes == 1, "cps v2: NeedCreate cold leaf must own one resume")
    local saved_pc = machine.pc
    machine.pc = self.pc
    local cold_offset = machine:emit(cold, self.product)
    machine.pc = saved_pc
    machine:patch_at(self.exit_link_at, base + cold_offset, "u64")
    machine:patch_at(cold_offset + resumes[1], self.resume_addr, "u64")
end

function V2Machine:emit_need_grow(hot_record, cold_name, product)
    local data_exit, offset = NeedGrowV2.new(self, hot_record, cold_name, product)
    self.table_data_exits[#self.table_data_exits + 1] = data_exit
    return offset
end

function V2Machine:emit_need_create(hot_record, cold_name, product)
    local data_exit, offset = NeedCreateV2.new(self, hot_record, cold_name, product)
    self.table_data_exits[#self.table_data_exits + 1] = data_exit
    return offset
end

function V2Machine:emit_concat_fragment(record, product)
    local edges = assert(record.holes.fragment_next,
        "cps v2: CONCAT fragment has no fragment_next")
    assert(#edges == 1, "cps v2: CONCAT fragment must own one exact edge")
    local offset = self:emit(record, product)
    return offset + edges[1]
end

function V2Machine:compose_concat(chars, base, itoa_addr, dtoa_addr)
    assert(#chars >= 2 and #chars <= 5, "cps v2: invalid CONCAT shape width")
    local edge_at
    local function append(name, product, final)
        local record = assert(self.bank.residual[name],
            "cps v2: missing CONCAT fragment " .. name)
        local offset = self.arena.cursor
        if edge_at then self:patch_at(edge_at, self.base + offset, "u64") end
        if final then self:emit(record, product); edge_at = nil
        else edge_at = self:emit_concat_fragment(record, product) end
    end
    local kind_name = { s = "str", i = "int", f = "flt" }
    for index, char in ipairs(chars) do
        local product = { source_disp = (base + index - 1) * 16 }
        if char == "i" then product["u64::itoa_addr"] = itoa_addr
        elseif char == "f" then product["u64::dtoa_addr"] = dtoa_addr end
        append("concat_measure_" .. assert(kind_name[char]), product, false)
    end
    append("concat_allocate", {}, false)
    for index, char in ipairs(chars) do
        local product = { source_disp = (base + index - 1) * 16 }
        if char == "i" then product["u64::itoa_addr"] = itoa_addr
        elseif char == "f" then product["u64::dtoa_addr"] = dtoa_addr end
        append("concat_write_" .. assert(kind_name[char]), product, false)
    end
    append("concat_finish", { target_disp = base * 16 }, true)
    assert(edge_at == nil, "cps v2: CONCAT composition left an open edge")
end

function V2Machine:emit(record, product)
    self:validate_product(record, product)
    local offset = self:append_record(record)
    local holes = record.holes
    local label = function(kind) return { record = record.__name, kind = kind } end
    -- The reject/overflow pc hole carries the owning occurrence's bytecode pc.
    if self.pc and holes.resume then
        self:patch_holes(offset, holes.resume, self.pc, "i32", label("resume"))
    end
    -- Every record that can reach the boundary stub carries host_exit holes.
    for _, at in ipairs(holes.host_exit or {}) do
        self.host_exits[#self.host_exits + 1] = offset + at
    end
    for _, at in ipairs(holes.mismatch_exit or {}) do
        self.mismatch_exits[#self.mismatch_exits + 1] = offset + at
    end
    for kind, value in pairs(product) do
        if kind == "const" then
            -- Seed every physical constant hole. Family-specific patchers then
            -- overwrite the selected payload; unused learning alternatives are
            -- safe values rather than executable sentinels.
            if holes.const_tag then self:patch_holes(offset, holes.const_tag, 0, "i32", label("const_tag")) end
            if holes.const_int then self:patch_holes(offset, holes.const_int, 0, "u64", label("const_int")) end
            if holes.const_flt then self:patch_holes(offset, holes.const_flt, 0, "u64", label("const_flt")) end
            if holes.const_ref then self:patch_holes(offset, holes.const_ref, 0, "u64", label("const_ref")) end
            if value.patch_poly then
                value:patch_poly(self:const_patcher(offset, holes, record.__name))
            else
                if holes.const_tag then self:patch_holes(offset, holes.const_tag, value.tag or 0, "i32", label("const_tag")) end
                if holes.const_int then self:patch_holes(offset, holes.const_int, value.int_bits or 0, "u64", label("const_int")) end
                if holes.const_flt then self:patch_holes(offset, holes.const_flt, value.flt_bits or 0, "u64", label("const_flt")) end
                if holes.const_ref then self:patch_holes(offset, holes.const_ref, value.ref or 0, "u64", label("const_ref")) end
            end
        elseif kind == "host_exit" then
            -- Metadata only. The physical boundary address is linked after every
            -- arena record has been emitted.
        elseif kind:sub(1, 5) == "u64::" then
            local physical = kind:sub(6)
            self:patch_holes(offset, holes[physical], value, "u64", label(physical))
        elseif kind:sub(1, 5) == "link:" then
            local physical = kind:sub(6)
            for _, at in ipairs(holes[physical]) do
                self.links[#self.links + 1] = {
                    at = offset + at, target_start = value,
                }
            end
        else
            assert(value ~= nil, "cps v2: nil hole value for " .. kind)
            self:patch_holes(offset, holes[kind], value, "i32", label(kind))
        end
    end
    return offset
end

-- PolyConstantPatcher-compatible API bound to one strict record manifest.
function V2Machine:const_patcher(offset, holes, record_name)
    local function patch(hole, value, encoding)
        self:patch_holes(offset, holes[hole], value, encoding,
            { record = record_name, kind = hole })
    end
    return {
        patch = function(_, hole, value, encoding) patch(hole, value, encoding) end,
        tag = function(_, t) patch("const_tag", t, "i32") end,
        nil_value = function(p) p:tag(0) end,
        false_value = function(p) p:tag(1) end,
        true_value = function(p) p:tag(2) end,
        integer = function(p, v) p:tag(3); patch("const_int", ffi.cast("uint64_t", v), "u64") end,
        floating = function(p, v)
            local holder = ffi.new("double[1]", v)
            p:tag(4)
            patch("const_flt", ffi.cast("uint64_t *", holder)[0], "u64")
        end,
        short_string = function(p, owner) p:tag(5); patch("const_ref", owner:reference(), "u64") end,
        long_string = function(p, owner) p:tag(6); patch("const_ref", owner:reference(), "u64") end,
    }
end

local function call_facts(machine, slot)
    local f = machine.facts[assert(slot, "cps v2: call slot unassigned")]
    if not f or f.seen == 0 then
        error("cps v2: call-site slot " .. tostring(slot)
            .. " was never observed in the learning pass (cold path);"
            .. " refusing to publish a generic fallback", 0)
    end
    if f.key_tag == 0xFFFFFFFF then
        error("cps v2: call-site slot " .. tostring(slot)
            .. " observed conflicting callee shapes;"
            .. " refusing to publish a generic fallback", 0)
    end
    return f
end

function V2Machine:emit_call(call, pc)
    local tail = call.tail
    local function add_continuation(record, offset)
        for _, at in ipairs(record.holes.continuation or {}) do
            self.continuations[#self.continuations + 1] = { at = offset + at, pc = pc }
        end
    end
    local function add_tail_stub(record, offset)
        local stub = self.bank.cps.host_tail_return
        local stub_offset = self:emit(stub, { call_a = call.A, call_pc = pc })
        for _, at in ipairs(record.holes.tail_return or {}) do
            self:patch_at(offset + at,
                ffi.cast("uintptr_t", self.arena.memory) + stub_offset, "u64")
        end
    end

    if self.mode == "learning" then
        local record = self.bank.learning[tail and "tailcall" or "call"]
        local product = {
            call_a = call.A, call_b = call.B,
            call_pc = pc, host_exit = true,
            occ_slot = assert(call.learn_slot, "cps v2: call slot unassigned"),
        }
        if not tail then product.call_c = call.C end
        local offset = self:emit(record, product)
        if tail then add_tail_stub(record, offset) else add_continuation(record, offset) end
        return offset
    end

    local f = call_facts(self, call.learn_slot)
    local klass, varg = f.key_tag, f.value_tag
    if klass == 1 and varg == 0 and call.B == 2 then
        local record = assert(self.bank.residual.call_native_fixed_arg1,
            "cps v2: missing exact one-argument CALL residual")
        local offset = self:emit(record, {
            call_a = call.A, base_disp = call.A * VALUE_BYTES,
            source_disp = (call.A + 1) * VALUE_BYTES,
            result_count = call.C == 0 and -1 or call.C - 1,
            call_pc = pc, host_exit = true,
        })
        add_continuation(record, offset)
        return offset
    end
    if klass == 1 and call.B ~= 0 then
        local family = tail and "tailcall" or "call"
        local prepare = assert(self.bank.residual[family .. "_native_"
            .. (varg == 0 and "fixed" or "vararg") .. "_prepare"])
        local nargs = call.B - 1
        local product = {
            call_a = call.A,
            base_disp = call.A * VALUE_BYTES,
            arg_count = nargs,
            call_pc = pc,
            host_exit = true,
        }
        if not tail then
            product.result_count = call.C == 0 and -1 or call.C - 1
        end
        local offset = self:emit(prepare, product)
        if not tail then add_continuation(prepare, offset) end
        local slot_record = assert(self.bank.residual[family .. "_fixed_arg_slot"])
        for slot = 0, nargs - 1 do
            self:emit(slot_record, {
                source_disp = (call.A + 1 + slot) * VALUE_BYTES,
                target_disp = slot * VALUE_BYTES,
                span = slot,
            })
        end
        self:emit(assert(self.bank.residual[family .. "_fixed_finish"]), {})
        return offset
    end

    local family = tail and "tailcall" or "call"
    local name
    if klass == 1 then
        name = family .. "_native_" .. (varg == 0 and "fixed" or "vararg") .. "_open"
    elseif klass == 2 then
        name = family .. "_host"
    else
        error("cps v2: call-site slot " .. tostring(call.learn_slot)
            .. " observed an unsupported callee class " .. tostring(klass), 0)
    end
    local record = assert(self.bank.residual[name],
        "cps v2: missing residual " .. name)
    local product = {
        call_a = call.A, call_pc = pc, host_exit = true,
        base_disp = call.A * VALUE_BYTES,
    }
    if klass == 2 then product.call_b = call.B end
    if not tail then product.call_c = call.C end
    local offset = self:emit(record, product)
    if tail then
        if klass == 2 then add_tail_stub(record, offset) end
    else
        add_continuation(record, offset)
    end
    return offset
end

function V2Machine:emit_fused_call(record, call, pc, product)
    assert(not call.tail, "cps v2: fused tail calls are not in the closed vocabulary")
    local offset = self:emit(record, product)
    for _, at in ipairs(record.holes.continuation or {}) do
        self.continuations[#self.continuations + 1] = { at = offset + at, pc = pc }
    end
    return offset
end

-- ---- the invocation owner ------------------------------------------------

local InvocationV2 = {}
InvocationV2.__index = InvocationV2

function InvocationV2.new(plans, heap, opts, mode, learning_slots)
    opts = opts or {}
    mode = mode or "residual"
    local function_count = 0
    for index in pairs(plans) do function_count = math.max(function_count, index + 1) end
    local desc_bytes = align16(ffi.sizeof("Lua55NativeFunctionDescriptorV2") * function_count)
    local frame_region = opts.frame_region or (64 * 1024 * 1024)
    local learn_bytes = align16((learning_slots or 0)
        * ffi.sizeof("Lua55TableLearnSlotV2"))
    local mapping_size = align16(INV_SIZE) + desc_bytes + frame_region + learn_bytes
    local raw = ffi.C.mmap(nil, mapping_size, PROT_READ + PROT_WRITE,
        MAP_PRIVATE + MAP_ANONYMOUS, -1, 0)
    assert(raw ~= MAP_FAILED, "cps v2: invocation mmap failed")
    local base = ffi.cast("uint8_t *", raw)
    local invocation = ffi.cast("Lua55NativeInvocationV2 *", base)
    local functions = ffi.cast("Lua55NativeFunctionDescriptorV2 *",
        base + align16(INV_SIZE))
    local frame_begin = ffi.cast("uint8_t *", functions) + desc_bytes
    local frame_end = frame_begin + frame_region
    local learning = mode == "learning" and (frame_end) or ffi.cast("uint8_t *", 0)
    invocation[0].frame_begin = frame_begin
    invocation[0].frame_next = frame_begin
    invocation[0].frame_end = frame_end
    invocation[0].current_frame = ffi.cast("Lua55NativeFrameV2 *", 0)
    invocation[0].functions = functions
    invocation[0].function_count = function_count
    invocation[0].open_value_capacity = opts.open_value_capacity or 16
    invocation[0].heap = heap.heap
    invocation[0].result_values = ffi.cast("Lua55ValueV2 *", 0)
    invocation[0].result_capacity = 0
    invocation[0].result_count = 0
    invocation[0].learning = learning
    invocation[0].learning_capacity = learn_bytes
    invocation[0].learning_slots = learning_slots or 0
    invocation[0].outcome.discriminant = OUTCOME_EXECUTING
    local self = setmetatable({
        raw = raw, mapping_size = mapping_size,
        invocation = invocation, functions = functions,
        function_count = function_count,
        frame_begin = frame_begin, frame_end = frame_end,
        heap = heap, plans = plans, arenas = {}, opts = opts,
        mode = mode, keep_heap = mode == "learning",
    }, InvocationV2)
    return self
end

function InvocationV2:free()
    if self.raw == false then return end
    for _, item in pairs(self.arenas) do
        if item.code then item.code:free() end
    end
    if not self.keep_heap then self.heap:free() end
    assert(ffi.C.munmap(self.raw, self.mapping_size) == 0)
    self.raw, self.mapping_size, self.heap = false, false, false
    return self
end

function InvocationV2:heap_bump(size)
    local heap = self.invocation[0].heap[0]
    local next_ = heap.table_next
    local remainder = tonumber(next_ % 16)
    local aligned = remainder == 0 and next_ or next_ + (16 - remainder)
    assert(aligned + size <= heap.table_region_end,
        "cps v2: guest heap bump region exhausted")
    heap.table_next = aligned + size
    local storage = ffi.cast("uint8_t *", aligned)
    ffi.fill(storage, size, 0)
    return ffi.cast("uintptr_t", storage)
end

-- ---- V2 function arenas ---------------------------------------------------

-- Every arena starts with the host_exit stub at offset 0; each record's
-- host_exit hole patches to base + 0; straight successors are rel32-chained
-- by the Arena; compare taken links, forprep body/skip, forloop back/fall,
-- jmp links, and call continuations are absolute 64-bit patches resolved
-- after all appends.

local function build_function_arena_v2(inv, ctx, plan, mode, facts)
    local arena = Native.Arena.new(262144)
    arena:append(assert(V2_BANK.cps.host_exit, "host_exit stub absent"))
    local mismatch_stub = assert(V2_BANK.cps.specialization_mismatch,
        "specialization mismatch stub absent")
    local mismatch_offset = arena.cursor
    local stub_host_exit_at = {}
    arena:append(mismatch_stub)
    local base = tonumber(ffi.cast("uintptr_t", arena.memory))
    local machine = V2Machine.new(arena, V2_BANK, plan, mode, facts)
    machine.base = base
    for _, site in ipairs(mismatch_stub.hole_sites or {}) do
        local absolute = mismatch_offset + site.at
        local key = hole_site_key(absolute, site.width)
        assert(not machine.hole_sites[key],
            "cps v2: duplicate mismatch-stub hole site " .. key)
        machine.hole_sites[key] = {
            at = absolute, width = site.width, kind = site.kind, role = site.role,
            record = mismatch_stub.__name, patched = false,
        }
        if site.kind == "host_exit" then
            stub_host_exit_at[#stub_host_exit_at + 1] = absolute
        end
    end
    local entries = {}
    local pc = 0
    while pc < plan.n do
        local call = plan.calls[pc]
        if call and plan.call_superinstructions and plan.call_superinstructions[pc] then
            -- The preceding whole block emitted the fused call occurrence.
            pc = pc + 1
        elseif call then
            machine.pc = pc
            if call.kind == "tforcall" then
                entries[pc] = arena.cursor
                local record, product
                if machine.mode == "learning" then
                    record = machine.bank.learning.tforcall
                    product = {
                        call_a = call.A, call_c = call.C, call_pc = pc,
                        occ_slot = assert(call.learn_slot,
                            "cps v2: tforcall slot unassigned"),
                    }
                else
                    local f = call_facts(machine, call.learn_slot)
                    local name = f.key_tag == 1 and "tforcall_native"
                        or (f.key_tag == 2 and "tforcall_host" or nil)
                    assert(name, "cps v2: unsupported tforcall callee class "
                        .. tostring(f.key_tag))
                    record = assert(machine.bank.residual[name],
                        "cps v2: missing residual " .. name)
                    product = {
                        call_a = call.A, call_c = call.C, call_pc = pc,
                        base_disp = call.A * VALUE_BYTES,
                    }
                end
                local offset = machine:emit(record, product)
                for _, at in ipairs(record.holes.continuation or {}) do
                    machine.continuations[#machine.continuations + 1] = {
                        at = offset + at, pc = pc,
                    }
                end
            else
                entries[pc] = arena.cursor
                machine:emit_call(call, pc)
            end
            pc = pc + 1
        elseif plan.forpreps[pc] then
            local boundary = plan.forpreps[pc]
            local super = plan.superinstructions and plan.superinstructions[pc] or nil
            machine.pc = pc
            if super then
                entries[pc] = arena.cursor
                super:append_v2(machine)
                pc = super.skip_pc
            else
                if machine.mode == "learning" then
                    machine:emit(machine.bank.learning.forprep, {
                        base_disp = boundary.A * ffi.sizeof("Lua55ValueV2"),
                        ["link:body_link"] = boundary.body_pc,
                        ["link:skip_link"] = boundary.skip_pc,
                        occ_slot = assert(boundary.learn_slot,
                            "cps v2: forprep slot unassigned"),
                    })
                else
                    local f = machine.facts[assert(boundary.learn_slot,
                        "cps v2: forprep slot unassigned")]
                    local proto = f.key_tag == 3 and "int" or "flt"
                    local sign = f.value_tag == 0 and "_pos" or "_neg"
                    machine:emit(assert(machine.bank.residual["forprep_" .. proto .. sign],
                        "cps v2: missing forprep residual"), {
                        base_disp = boundary.A * ffi.sizeof("Lua55ValueV2"),
                        ["link:body_link"] = boundary.body_pc,
                        ["link:skip_link"] = boundary.skip_pc,
                    })
                end
                pc = pc + 1
            end
        else
            local block = plan.blocks[plan.block_at[pc]]
            if not block then
                pc = pc + 1
            else
                entries[block.start] = arena.cursor
                for _, occurrence in ipairs(block.path.occurrences) do
                    local append_v2 = occurrence and occurrence.append_v2
                    assert(append_v2,
                        "cps v2: occurrence has no V2 leaf ("
                        .. tostring(occurrence and occurrence.learner_name) .. ")")
                    machine.pc = occurrence.pc
                    append_v2(occurrence, machine)
                end
                pc = block.stop
            end
        end
    end
    -- Append mutable-table data exits after the authored blocks. Each concrete
    -- NeedGrow/NeedCreate publication value owns its exact cold leaf and resume.
    for _, data_exit in ipairs(machine.table_data_exits) do
        data_exit:append_cold(machine, base, V2_BANK)
    end
    -- Resolve deferred absolute links: block start -> published address.
    for _, item in ipairs(machine.links) do
        local target = assert(entries[item.target_start],
            "cps v2: link target is not a block start")
        machine:patch_at(item.at, base + target, "u64")
    end
    for _, item in ipairs(machine.continuations) do
        local target = assert(entries[item.pc + 1],
            "cps v2: call continuation is not a block start")
        machine:patch_at(item.at, base + target, "u64")
    end
    for _, at in ipairs(stub_host_exit_at) do
        machine:patch_at(at, base, "u64")
    end
    for _, at in ipairs(machine.host_exits) do
        machine:patch_at(at, base, "u64")
    end
    for _, at in ipairs(machine.mismatch_exits) do
        machine:patch_at(at, base + mismatch_offset, "u64")
    end
    machine:assert_all_holes_patched()
    local code = arena:seal()
    local block_entries = {}
    for start, at in pairs(entries) do
        block_entries[start] = ffi.cast("Lua55NativeEntryV2",
            ffi.cast("uintptr_t", code.memory) + at)
    end
    return {
        code = code, block_entries = block_entries, emissions = machine.emissions,
        entry = block_entries[plan.blocks[1].start],
        stub = ffi.cast("Lua55NativeEntryV2",
            ffi.cast("uintptr_t", code.memory)),
    }
end

-- ---- guest value conversion across the host boundary ----------------------

local function guest_to_host(value)
    local tag = tonumber(value.tag)
    if tag == TAG.nil_value then return nil
    elseif tag == TAG.false_value then return false
    elseif tag == TAG.true_value then return true
    elseif tag == TAG.integer then
        return tonumber(value.payload.integer)
    elseif tag == TAG.floating then
        return tonumber(value.payload.floating)
    elseif tag == TAG.short_string or tag == TAG.long_string then
        local str = ffi.cast("Lua55GuestStringV2 *", tonumber(value.payload.reference))
        if str == nil or str == ffi.cast("Lua55GuestStringV2 *", 0) then return nil end
        local bytes = ffi.string(str[0].bytes, tonumber(str[0].length))
        return bytes
    elseif tag == TAG.table_value then
        return "table: 0x" .. string.format("%x", tonumber(value.payload.reference))
    elseif tag == TAG.closure_value then
        return "function: 0x" .. string.format("%x", tonumber(value.payload.reference))
    end
    error("cps v2: unsupported guest value tag " .. tostring(tag), 0)
end

local function host_to_guest(frame, heap, index, host_value)
    local cell = frame[0].values + index
    if host_value == nil then
        cell[0].tag, cell[0].reserved = TAG.nil_value, 0
        cell[0].payload.reference = 0
    elseif host_value == false then
        cell[0].tag, cell[0].reserved = TAG.false_value, 0
        cell[0].payload.reference = 0
    elseif host_value == true then
        cell[0].tag, cell[0].reserved = TAG.true_value, 0
        cell[0].payload.reference = 0
    elseif type(host_value) == "number" then
        if host_value == math.floor(host_value)
            and host_value >= -9007199254740992 and host_value <= 9007199254740992 then
            cell[0].tag, cell[0].reserved = TAG.integer, 0
            cell[0].payload.integer = ffi.cast("int64_t", host_value)
        else
            cell[0].tag, cell[0].reserved = TAG.floating, 0
            cell[0].payload.floating = host_value
        end
    elseif type(host_value) == "string" then
        local owner = heap:short_string(host_value)
        cell[0].tag, cell[0].reserved = TAG.short_string, 0
        cell[0].payload.reference = owner:reference()
    else
        error("cps v2: unsupported host value " .. type(host_value), 0)
    end
end

-- ---- builtin / host callback dispatch -------------------------------------

local function builtin_id(value)
    if tonumber(value.tag) ~= TAG.closure_value then return nil end
    local ref = tonumber(value.payload.reference)
    if not ref or ref == 0 then return nil end
    local object = ffi.cast("Lua55GuestObjectHeaderV2 *", ref)
    if tonumber(object[0].kind) ~= 5 then return nil end
    return tonumber(ffi.cast("Lua55GuestBuiltinV2 *", ref)[0].builtin_id)
end

-- Run one suspended host CALL: execute the library function, write results
-- into R[A..] (bounded by value_capacity), then re-enter the exact patched
-- continuation. Native code never calls Lua.
local function dispatch_host_call(inv, frame, payload, dispatch, heap)
    local A = tonumber(payload.a)
    local B = tonumber(payload.b)
    local C = tonumber(payload.c)
    local callee = frame[0].values[A]
    local bid = builtin_id(callee)
    local nargs = B - 1
    if nargs < 0 then
        nargs = math.max(tonumber(frame[0].top) - (A + 1), 0)
    end
    local capacity = tonumber(frame[0].value_capacity)
    local count
    if bid == 5 then       -- select
        local sel = guest_to_host(frame[0].values[A + 1])
        if sel == "#" then
            count = math.max(nargs - 1, 0)
            frame[0].values[A].tag, frame[0].values[A].reserved = TAG.integer, 0
            frame[0].values[A].payload.integer = ffi.cast("int64_t", count)
        else
            local index = tonumber(sel)
            if index and index < 0 then index = nargs + index end
            if index and index >= 1 and index <= nargs - 1 then
                frame[0].values[A] = frame[0].values[A + 1 + index]
            else
                frame[0].values[A].tag, frame[0].values[A].reserved = TAG.nil_value, 0
                frame[0].values[A].payload.reference = 0
            end
            count = 1
        end
    elseif bid == 3 then   -- pairs(t) -> (next, t, nil)
        local t = frame[0].values[A + 1]
        assert(tonumber(t.tag) == TAG.table_value, "cps v2: pairs requires a table")
        frame[0].values[A].tag, frame[0].values[A].reserved = TAG.closure_value, 0
        frame[0].values[A].payload.reference = heap:builtin(1)
        frame[0].values[A + 1] = t
        local n = frame[0].values + A + 2
        n[0].tag, n[0].reserved = TAG.nil_value, 0
        n[0].payload.reference = 0
        count = 3
    elseif bid == 4 then   -- ipairs(t) -> (ipairs-iter, t, 0)
        local t = frame[0].values[A + 1]
        assert(tonumber(t.tag) == TAG.table_value, "cps v2: ipairs requires a table")
        frame[0].values[A].tag, frame[0].values[A].reserved = TAG.closure_value, 0
        frame[0].values[A].payload.reference = heap:builtin(2)
        frame[0].values[A + 1] = t
        local n = frame[0].values + A + 2
        n[0].tag, n[0].reserved = TAG.integer, 0
        n[0].payload.integer = ffi.cast("int64_t", 0)
        count = 3
    elseif bid == 6 then   -- rawget (Batch B: V2 table leaves)
        error("cps v2: rawget needs V2 table leaves (Batch B)", 0)
    elseif bid == 5 then
        -- select handled above; keep count set
    else
        local callback = assert(dispatch[bid or 0],
            "cps v2: unknown builtin " .. tostring(bid))
        local args = {}
        for i = 1, nargs do args[i] = guest_to_host(frame[0].values[A + i]) end
        local results = { callback(unpack(args)) }
        local want = C - 1
        count = want >= 0 and math.min(want, #results) or #results
        local needed = A + (want >= 0 and want or count)
        if needed > capacity then
            inv.invocation[0].outcome.discriminant = OUTCOME_VALUE_OVERFLOW
            inv.invocation[0].outcome.u.overflow.required = needed
            inv.invocation[0].outcome.u.overflow.available = capacity
            inv.invocation[0].outcome.u.overflow.pc = tonumber(payload.pc)
            error("cps v2: host results exceed caller value capacity", 0)
        end
        for i = 0, count - 1 do
            host_to_guest(frame, heap, A + i, results[i + 1])
        end
        for i = count, want - 1 do
            frame[0].values[A + i].tag, frame[0].values[A + i].reserved = TAG.nil_value, 0
            frame[0].values[A + i].payload.reference = 0
        end
        if want >= 0 then frame[0].top = A + want
        else frame[0].top = A + count end
    end
    if count then frame[0].top = A + count end
    inv.invocation[0].outcome.discriminant = OUTCOME_EXECUTING
    return payload.resume_entry(frame)
end

-- Run a suspended host TAILCALL: results at R[A..top), then enter the
-- occurrence-owned HostTailReturnV2 stub which performs the RETURN protocol.
local function dispatch_host_tail_call(inv, frame, payload, dispatch, heap)
    local A = tonumber(payload.a)
    local callee = frame[0].values[A]
    local bid = builtin_id(callee)
    local callback
    if bid and bid >= 1 and bid <= 7 then
        -- fixed protocol builtin in tail position: select/rawget/rawset
        if bid == 5 then
            callback = function(...)
                local args = { ... }
                local sel = args[1]
                if sel == "#" then return #args - 1 end
                local n = tonumber(sel)
                if n and n < 0 then n = #args + n end
                if n and n >= 1 and n <= #args - 1 then return args[n + 1] end
                return nil
            end
        else
            error("cps v2: unsupported fixed builtin " .. tostring(bid) .. " in tail position", 0)
        end
    else
        callback = assert(dispatch[bid or 0], "cps v2: unknown tail builtin " .. tostring(bid))
    end
    local B = tonumber(payload.b)
    local nargs = B - 1
    if nargs < 0 then
        nargs = math.max(tonumber(frame[0].top) - (A + 1), 0)
    end
    local args = {}
    for i = 1, nargs do args[i] = guest_to_host(frame[0].values[A + i]) end
    local results = { callback(unpack(args)) }
    local capacity = tonumber(frame[0].value_capacity)
    if A + #results > capacity then
        error("cps v2: host tail results exceed caller value capacity", 0)
    end
    for i = 0, #results - 1 do
        host_to_guest(frame, heap, A + i, results[i + 1])
    end
    frame[0].top = A + #results
    inv.invocation[0].outcome.discriminant = OUTCOME_EXECUTING
    return payload.tail_return_entry(frame)
end

-- ---- generic-for iterator leaves (host side) ------------------------------

-- exact next over a guest table: array keys first (1..capacity, non-nil),
-- then field keys in field order. Returns the guest (key, value) pair or
-- nil when exhausted. The host performs the scan; the TFOR back-edge is a
-- patched native link.
local function guest_next(heap, table_ref, key)
    local t = ffi.cast("Lua55GuestTableV2 *", table_ref)
    local ktag = tonumber(key[0].tag)
    if ktag == TAG.nil_value then
        local i
        for i = 1, tonumber(t[0].array_capacity) do
            local v = t[0].array_values[i - 1]
            if tonumber(v.tag) ~= TAG.nil_value then
                local k = ffi.cast("Lua55ValueV2 *", ffi.new("Lua55ValueV2[1]"))
                k[0].tag, k[0].reserved = TAG.integer, 0
                k[0].payload.integer = ffi.cast("int64_t", i)
                return k, t[0].array_values + (i - 1)
            end
        end
        local i
        for i = 1, tonumber(t[0].field_capacity) do
            local fld = t[0].field_values + (i - 1)
            if tonumber(fld[0].occupied) ~= 0 then
                local k = ffi.cast("Lua55ValueV2 *", ffi.new("Lua55ValueV2[1]"))
                k[0].tag, k[0].reserved = TAG.short_string, 0
                k[0].payload.reference = fld[0].key_reference
                return k, ffi.cast("Lua55ValueV2 *", ffi.cast("uintptr_t", fld) + 8)
            end
        end
        return nil
    elseif ktag == TAG.integer then
        local ki = tonumber(key[0].payload.integer)
        local i
        for i = ki + 1, tonumber(t[0].array_capacity) do
            local v = t[0].array_values[i - 1]
            if tonumber(v.tag) ~= TAG.nil_value then
                local k = ffi.cast("Lua55ValueV2 *", ffi.new("Lua55ValueV2[1]"))
                k[0].tag, k[0].reserved = TAG.integer, 0
                k[0].payload.integer = ffi.cast("int64_t", i)
                return k, t[0].array_values + (i - 1)
            end
        end
        local i
        for i = 1, tonumber(t[0].field_capacity) do
            local fld = t[0].field_values + (i - 1)
            if tonumber(fld[0].occupied) ~= 0 then
                local k = ffi.cast("Lua55ValueV2 *", ffi.new("Lua55ValueV2[1]"))
                k[0].tag, k[0].reserved = TAG.short_string, 0
                k[0].payload.reference = fld[0].key_reference
                return k, ffi.cast("Lua55ValueV2 *", ffi.cast("uintptr_t", fld) + 8)
            end
        end
        return nil
    elseif ktag == TAG.short_string or ktag == TAG.long_string then
        local kr = key[0].payload.reference
        local found = false
        local i
        for i = 1, tonumber(t[0].field_capacity) do
            local fld = t[0].field_values + (i - 1)
            if tonumber(fld[0].occupied) ~= 0 then
                if found then
                    local k = ffi.cast("Lua55ValueV2 *", ffi.new("Lua55ValueV2[1]"))
                    k[0].tag, k[0].reserved = TAG.short_string, 0
                    k[0].payload.reference = fld[0].key_reference
                    return k, ffi.cast("Lua55ValueV2 *", ffi.cast("uintptr_t", fld) + 8)
                end
                if fld[0].key_reference == kr then found = true end
            end
        end
        return nil
    end
    return nil
end

-- ipairs-iter(t, i): the next (i+1, t[i+1]) or nil.
local function guest_ipairs_iter(heap, table_ref, index)
    local t = ffi.cast("Lua55GuestTableV2 *", table_ref)
    local next_index = tonumber(index[0].payload.integer) + 1
    if next_index >= 1 and next_index <= tonumber(t[0].array_capacity) then
        local v = t[0].array_values + (next_index - 1)
        if tonumber(v[0].tag) ~= TAG.nil_value then
            local k = ffi.cast("Lua55ValueV2 *", ffi.new("Lua55ValueV2[1]"))
            k[0].tag, k[0].reserved = TAG.integer, 0
            k[0].payload.integer = ffi.cast("int64_t", next_index)
            return k, v
        end
    end
    return nil
end

local function write_guest_pair(frame, base, count, key, value)
    local cap = tonumber(frame[0].value_capacity)
    assert(base + count <= cap, "cps v2: iterator results exceed capacity")
    local kd = frame[0].values + base
    local vd = frame[0].values + base + 1
    if key == nil then
        kd[0].tag, kd[0].reserved = TAG.nil_value, 0
        kd[0].payload.reference = 0
        if count >= 2 then
            vd[0].tag, vd[0].reserved = TAG.nil_value, 0
            vd[0].payload.reference = 0
        end
    else
        kd[0] = key[0]
        if count >= 2 then vd[0] = value[0] end
    end
    if count > 2 then
        local i
        for i = 2, count - 1 do
            local c = frame[0].values + base + i
            c[0].tag, c[0].reserved = TAG.nil_value, 0
            c[0].payload.reference = 0
        end
    end
    frame[0].top = base + count
end

-- Run a suspended TFORCALL against a builtin iterator (next / ipairs-iter):
-- reads (state, control) from R[A+1] and R[A+3], writes C results to
-- R[A+3..], then re-enters the patched continuation (the TFORLOOP block).
local function dispatch_host_tforcall(inv, frame, payload, heap)
    local A = tonumber(payload.a)
    local C = tonumber(payload.c)
    local callee = frame[0].values[A]
    local bid = builtin_id(callee)
    local t = frame[0].values[A + 1]
    local key = frame[0].values + A + 3
    local k, v
    if bid == 1 then
        assert(tonumber(t.tag) == TAG.table_value, "cps v2: next requires a table")
        k, v = guest_next(heap, tonumber(t.payload.reference), key)
    elseif bid == 2 then
        assert(tonumber(t.tag) == TAG.table_value, "cps v2: ipairs requires a table")
        k, v = guest_ipairs_iter(heap, tonumber(t.payload.reference), key)
    else
        error("cps v2: unsupported iterator builtin " .. tostring(bid), 0)
    end
    write_guest_pair(frame, A + 3, C, k, v)
    inv.invocation[0].outcome.discriminant = OUTCOME_EXECUTING
    return payload.resume_entry(frame)
end

-- ---- env construction ------------------------------------------------------

local NEXT_ID = 8
local next_id_counter = NEXT_ID
local function next_id()
    local id = next_id_counter
    next_id_counter = next_id_counter + 1
    return id
end

-- The env is a guest table mapping names to builtin markers (closure-tagged
-- Lua55GuestBuiltinV2 objects). Fixed protocol ids occupy 1-7; user
-- callbacks receive generated ids >= 8. dispatch maps generated ids back to
-- the Lua functions owned by the outer Lua driver (never by native memory).
local function build_env(inv_heap, const_heap, user_callbacks, dispatch)
    -- The env table and its builtin markers live in the invocation heap; the
    -- name-string keys are interned in the const heap (the retained heap the
    -- prototype plans reference), so GETTABUP's patched key_ref matches the
    -- exact interned string identity the plan consts use.
    local env = inv_heap:table(0, 32)
    dispatch = dispatch or {}
    local fixed = { next = 1, pairs = 3, ipairs = 4, select = 5, rawget = 6, rawset = 7 }
    for name, id in pairs(fixed) do
        local field = env:field_value(const_heap:short_string(name), true)
        field.tag, field.reserved = 8, 0
        field.payload.reference = inv_heap:builtin(id)
    end
    for name, value in pairs(user_callbacks or {}) do
        local id = next_id()
        dispatch[id] = value
        local field = env:field_value(const_heap:short_string(name), true)
        field.tag, field.reserved = 8, 0
        field.payload.reference = inv_heap:builtin(id)
    end
    return env, dispatch
end

local function make_env_cells(inv, env_ref, count)
    local cells_ptr = ffi.cast("Lua55UpvalueCellV2 **",
        inv:heap_bump(PTR_CELL_SIZE * count))
    for i = 0, count - 1 do
        local cell = ffi.cast("Lua55UpvalueCellV2 *", inv:heap_bump(CELL_SIZE))
        cell[0].state = 2              -- closed
        cell[0].generation = 1
        cell[0].open_slot = ffi.cast("Lua55ValueV2 *", 0)
        cell[0].next_open = ffi.cast("Lua55UpvalueCellV2 *", 0)
        cell[0].closed_value.tag = 7   -- table (the _ENV)
        cell[0].closed_value.reserved = 0
        cell[0].closed_value.payload.reference = env_ref
        cells_ptr[i] = cell
    end
    return cells_ptr
end

-- ---- the driver -----------------------------------------------------------

local function root_frame_bytes(maxstack, value_capacity)
    return align16(FRAME_SIZE + value_capacity * VALUE_BYTES)
end

-- ---- learning slots -----------------------------------------------------
-- Slot ids are assigned once (deterministic order, cached on occurrences)
-- so the learning pass and the residual pass observe the same mapping.
-- Slot 0 is reserved (tables without a NEWTABLE site never write it).

local LEARNABLE_OCCURRENCE = {
    -- batch 1 tables
    gettable = true, settable = true, newtable = true,
    getfield = true, setfield = true, gettabup = true, settabup = true, self = true,
    -- batch 3 arithmetic
    add = true, sub = true, mul = true, addi = true,
    addk = true, subk = true, mulk = true, mod = true, idiv = true,
    modk = true, idivk = true, div = true, divk = true, pow = true, powk = true,
    band = true, bor = true, bxor = true, bandk = true, bork = true, bxork = true,
    shl = true, shr = true, shli = true, shri = true,
    -- batch 3 unary
    unm = true, bnot = true, len = true,
    -- batch 3 comparisons (learner_name carries a _k<n> suffix)
    eq = true, eqk = true, eqi = true, lt = true, lti = true,
    le = true, lei = true, gti = true, gei = true,
    -- batch 4 numeric-for
    forloop = true,
    -- batch 6 concat
    concat = true,
    -- batch 8 getvarg
    getvarg = true,
    -- corpus-derived read/modify/write, store-cycle, and accumulate superinstructions
    super_field_addi = true, super_table_addi = true, super_for_settable = true,
    super_accumulate_field = true,
    -- corpus-derived read/modify/write and store-cycle superinstructions
    super_field_addi = true, super_table_addi = true, super_for_settable = true,
    -- corpus-derived read/modify/write superinstructions
    super_field_addi = true, super_table_addi = true,
}

local function learnable_base(name)
    if type(name) ~= "string" then return false end
    local base = name:gsub("_k%d+$", "")
    return LEARNABLE_OCCURRENCE[base]
end

local function assign_learning_slots(plans)
    local next_slot = 1
    local indexes = {}
    for index in pairs(plans) do indexes[#indexes + 1] = index end
    table.sort(indexes)
    local function walk(occurrences)
        for _, occ in ipairs(occurrences) do
            if learnable_base(occ.learner_name) then
                occ.learn_slot = next_slot
                next_slot = next_slot + 1
            end
        end
    end
    for _, index in ipairs(indexes) do
        local plan = plans[index]
        -- call sites (CALL/TAILCALL/TFORCALL) get slots
        for pc, call in pairs(plan.calls or {}) do
            local super = plan.call_superinstructions and plan.call_superinstructions[pc] or nil
            call.learn_slot = next_slot
            if super then super.learn_slot = next_slot end
            next_slot = next_slot + 1
        end
        -- numeric-for boundaries (FORPREP) get slots
        -- numeric-for boundaries and projected superinstructions get one
        -- family-owned slot. A fused cycle replaces the component learners.
        local covered_blocks = {}
        for pc, boundary in pairs(plan.forpreps or {}) do
            local super = plan.superinstructions and plan.superinstructions[pc] or nil
            if super then
                super.learn_slot = next_slot
                boundary.learn_slot = next_slot
                covered_blocks[super.body_pc] = true
            else
                boundary.learn_slot = next_slot
            end
            next_slot = next_slot + 1
        end
        local blocks = {}
        for _, block in ipairs(plan.blocks) do blocks[#blocks + 1] = block end
        table.sort(blocks, function(a, b) return a.start < b.start end)
        for _, block in ipairs(blocks) do
            if not covered_blocks[block.start] then walk(block.path.occurrences) end
        end
    end
    return next_slot   -- slot count: indices 0 (reserved) .. last assigned
end

local function read_learning(inv)
    local facts = {}
    local learning = inv.invocation[0].learning
    if learning == nil or learning == ffi.cast("uint8_t *", 0) then return facts end
    local slots = tonumber(inv.invocation[0].learning_slots)
    local arr = ffi.cast("Lua55TableLearnSlotV2 *", learning)
    for i = 0, slots - 1 do
        facts[i] = {
            key_tag = tonumber(arr[i].key_tag),
            value_tag = tonumber(arr[i].value_tag),
            max_array_index = tonumber(arr[i].max_array_index),
            max_field_count = tonumber(arr[i].max_field_count),
            seen = tonumber(arr[i].seen),
            field_slot = tonumber(arr[i].field_slot),
            field_layout_capacity = tonumber(arr[i].field_layout_capacity),
            field_state = tonumber(arr[i].field_state),
            field_site_id = tonumber(arr[i].field_site_id),
        }
    end
    return facts
end

-- ---- invocation assembly and execution ----------------------------------

local function build_invocation(ctx, heap, opts, mode, facts)
    local inv = InvocationV2.new(ctx.plans, heap, opts, mode,
        mode == "learning" and facts.slot_count or 0)
    local build_errors = {}
    for index, plan in pairs(ctx.plans) do
        local ok, built = pcall(build_function_arena_v2, inv, ctx, plan, mode, facts)
        if ok then inv.arenas[plan] = built else build_errors[index] = built end
    end
    local failed = {}
    for index in pairs(build_errors) do failed[#failed + 1] = index end
    table.sort(failed)
    if #failed > 0 then
        local index = failed[1]
        error(("cps v2: prototype %d is outside the strict V2 subset (%s)")
            :format(index, tostring(build_errors[index])), 0)
    end
    local slack = tonumber(inv.invocation[0].open_value_capacity)
    for index, plan in pairs(ctx.plans) do
        local descriptor = inv.functions[index]
        local arena = inv.arenas[plan]
        descriptor.entry = arena and arena.entry or ffi.cast("Lua55NativeEntryV2", 0)
        descriptor.maxstacksize = plan.proto.maxstacksize
        descriptor.numparams = plan.proto.numparams or 0
        descriptor.is_vararg = (plan.proto.flag or 0) ~= 0 and 1 or 0
        descriptor.upvalue_count = #(plan.proto.upvals or {})
        descriptor.tbc_capacity = 0
        descriptor.value_capacity = plan.proto.maxstacksize + slack
    end
    inv.main_index = ctx.main_index
    local plan = assert(ctx.plans[ctx.main_index], "cps v2: main plan absent")
    local arena = inv.arenas[plan]
    assert(arena, "cps v2: the main plan is outside the V2 subset"
        .. (build_errors[ctx.main_index] and (" (" .. tostring(build_errors[ctx.main_index]) .. ")") or ""))
    local maxstack = plan.proto.maxstacksize
    local value_capacity = maxstack + slack
    local bytes = root_frame_bytes(maxstack, value_capacity)
    assert(inv.frame_begin + bytes <= inv.frame_end, "cps v2: root frame overflow")
    local frame = ffi.cast("Lua55NativeFrameV2 *", inv.frame_begin)
    inv.invocation[0].frame_next = inv.frame_begin + bytes
    inv.invocation[0].current_frame = frame
    frame[0].invocation = inv.invocation
    frame[0].caller = ffi.cast("Lua55NativeFrameV2 *", 0)
    frame[0].return_link.entry = arena.stub
    frame[0].return_link.subject = frame
    frame[0].upvalues = ffi.cast("Lua55UpvalueCellV2 **", 0)
    frame[0].open_upvalues = ffi.cast("Lua55UpvalueCellV2 *", 0)
    frame[0].tbc_nodes = ffi.cast("Lua55TbcNodeV2 *", 0)
    frame[0].values = ffi.cast("Lua55ValueV2 *", inv.frame_begin + FRAME_SIZE)
    frame[0].value_count = maxstack
    frame[0].value_capacity = value_capacity
    frame[0].top = 0
    frame[0].vararg_count = 0
    frame[0].tbc_count = 0
    frame[0].tbc_capacity = 0
    frame[0].result_sink.values = frame[0].values
    frame[0].result_sink.top = ffi.cast("uint32_t *",
        ffi.cast("uintptr_t", frame) + ffi.offsetof("Lua55NativeFrameV2", "top"))
    frame[0].result_sink.base = 0
    frame[0].result_sink.count = -1
    frame[0].result_sink.capacity = value_capacity
    local dispatch = {}
    local env = build_env(heap, ctx.const_heap, opts.callbacks, dispatch)
    if #(plan.proto.upvals or {}) > 0 then
        frame[0].upvalues = make_env_cells(inv, env:reference(), #(plan.proto.upvals or {}))
    end
    if opts.force_gc_before_entry then
        collectgarbage("collect")
        collectgarbage("collect")
        heap:assert_native_ownership()
    end
    return inv, frame, arena, dispatch
end

local function assert_scalar_plan(plans)
    for index, plan in pairs(plans) do
        assert(plan.scalar_only == true,
            "cps v2: scalar-only plan marker absent for prototype " .. tostring(index))
        assert(next(plan.superinstructions or {}) == nil,
            "cps v2: scalar-only plan retained numeric-for fusion")
        assert(next(plan.call_superinstructions or {}) == nil,
            "cps v2: scalar-only plan retained call fusion")
        for _, block in ipairs(plan.blocks) do
            for _, occurrence in ipairs(block.path.occurrences) do
                local name = occurrence.learner_name
                assert(type(name) ~= "string" or name:sub(1, 6) ~= "super_",
                    "cps v2: scalar-only plan retained " .. tostring(name))
            end
        end
    end
    return true
end
local function execute(inv, frame, arena, dispatch, heap, opts)
    arena.entry(frame)
    while true do
        local outcome = tonumber(inv.invocation[0].outcome.discriminant)
        if outcome == OUTCOME_EXECUTING then
            break
        elseif outcome == OUTCOME_RETURNED then
            break
        elseif outcome == OUTCOME_HOST_CALL then
            local payload = inv.invocation[0].outcome.u.host_call
            if tonumber(payload.reserved) == 1 then
                dispatch_host_tforcall(inv, frame, payload, heap)
            else
                dispatch_host_call(inv, frame, payload, dispatch, heap)
            end
        elseif outcome == OUTCOME_HOST_TAIL_CALL then
            local payload = inv.invocation[0].outcome.u.host_tail_call
            dispatch_host_tail_call(inv, frame, payload, dispatch, heap)
        elseif outcome == OUTCOME_STACK_OVERFLOW then
            local o = inv.invocation[0].outcome.u.overflow
            error(("cps v2: native frame stack overflow at pc %d (need %d have %d)")
                :format(tonumber(o.pc), tonumber(o.required), tonumber(o.available)), 0)
        elseif outcome == OUTCOME_VALUE_OVERFLOW then
            local o = inv.invocation[0].outcome.u.overflow
            local cf = inv.invocation[0].current_frame
            error(("cps v2: value capacity overflow at pc %d (need %d have %d); frame top=%d vc=%d vararg=%d")
                :format(tonumber(o.pc), tonumber(o.required), tonumber(o.available),
                    cf ~= ffi.cast("Lua55NativeFrameV2 *", 0) and tonumber(cf[0].top) or -1,
                    cf ~= ffi.cast("Lua55NativeFrameV2 *", 0) and tonumber(cf[0].value_capacity) or -1,
                    cf ~= ffi.cast("Lua55NativeFrameV2 *", 0) and tonumber(cf[0].vararg_count) or -1), 0)
        elseif outcome == OUTCOME_HEAP_OVERFLOW then
            local o = inv.invocation[0].outcome.u.overflow
            error(("cps v2: guest heap overflow at pc %d (need %d have %d)")
                :format(tonumber(o.pc), tonumber(o.required), tonumber(o.available)), 0)
        elseif outcome == OUTCOME_REJECTED then
            local o = inv.invocation[0].outcome.u.rejected
            local cf = inv.invocation[0].current_frame
            local dbg = {}
            if cf ~= ffi.cast("Lua55NativeFrameV2 *", 0) then
                for i = 0, 3 do
                    local v = cf[0].values[i]
                    dbg[#dbg+1] = ("R%d=%d/%d"):format(i, tonumber(v.tag), tonumber(v.payload.integer))
                end
            end
            if tonumber(o.rejection_kind) == 9 then
                error(("cps v2: specialization mismatch at pc %d (expected tag %d observed %d) %s")
                    :format(tonumber(o.pc), tonumber(o.expected_tag), tonumber(o.observed_tag),
                        table.concat(dbg, " ")), 0)
            end
            error(("cps v2: native reject kind %d at pc %d (opcode %d) %s")
                :format(tonumber(o.rejection_kind), tonumber(o.pc), tonumber(o.opcode), table.concat(dbg, " ")), 0)
        else
            error("cps v2: unknown boundary outcome " .. outcome, 0)
        end
    end
    assert(tonumber(inv.invocation[0].outcome.discriminant) == OUTCOME_RETURNED,
        "cps v2: the main did not return")
    local nres = tonumber(frame[0].top)
    local values = {}
    for i = 0, nres - 1 do
        values[i + 1] = guest_to_host(frame[0].values[i])
    end
    return values
end

local function run(source, opts)
    opts = opts or {}
    local bytes = opts.precompiled and source or Run55.compile(source, opts.luac)
    local main = Undump.undump(bytes)
    -- the retained heap: prototype plans and the residual owner reference it
    local heap = Heap.GuestHeap.new(opts.generation or 1, opts.region_size)
    local ctx = { bank = V2_BANK, plans = {}, const_heap = heap,
        scalar_only = opts.scalar_only == true }
    ctx.plans, ctx.main_index = Run55.build_plans(main, heap, {
        scalar_only = opts.scalar_only == true,
    })
    if opts.scalar_only then assert_scalar_plan(ctx.plans) end
    local slot_count = assign_learning_slots(ctx.plans)

    if opts.skip_learning then
        -- single-pass residual (used only by internal harnesses that already
        -- hold learned facts or programs without learned table occurrences)
        local inv, frame, arena, dispatch = build_invocation(ctx, heap, opts,
            "residual", {})
        local values = execute(inv, frame, arena, dispatch, heap, opts)
        if opts.return_invocation then return values, inv end
        inv:free()
        return values
    end

    -- learning pass: runs on the SAME retained heap so interned constants
    -- and the env name strings share one identity; it executes the program
    -- once with learner records and writes family-specific shape facts. Its
    -- garbage is bounded bump storage in the retained heap; the residual
    -- owner re-runs the program from a fresh root frame.
    local learn_inv, learn_frame, learn_arena, learn_dispatch = build_invocation(
        ctx, heap, opts, "learning", { slot_count = slot_count })
    local values = execute(learn_inv, learn_frame, learn_arena, learn_dispatch, heap, opts)
    local facts = read_learning(learn_inv)
    learn_inv:free()

    if not opts.return_invocation then
        -- one-shot: the learning pass already produced exact results; the
        -- residual image is only materialized for retained re-entry.
        heap:free()
        return values
    end

    -- residual pass: build the retained owner from the learned facts. It is
    -- returned unexecuted; retained re-entry executes it.
    local inv, frame, arena, dispatch = build_invocation(ctx, heap, opts, "residual", facts)
    inv.scalar_only = opts.scalar_only == true
    return values, inv
end

return {
    InvocationV2 = InvocationV2,
    build_function_arena_v2 = build_function_arena_v2,
    build_invocation = build_invocation,
    execute = execute,
    assign_learning_slots = assign_learning_slots,
    assert_scalar_plan = assert_scalar_plan,
    read_learning = read_learning,
    run = run,
    root_frame_bytes = root_frame_bytes,
    V2Machine = V2Machine,
    ffi = ffi,
}
