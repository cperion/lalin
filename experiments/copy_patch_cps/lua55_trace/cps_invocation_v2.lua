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
    uint32_t reserved;
} Lua55RejectedPayloadV2;

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
    Lua55NativeBoundaryOutcomeV2 outcome;
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

function V2Machine.new(arena, bank, plan)
    local self = setmetatable({
        arena = arena, bank = bank, plan = plan,
        links = {}, continuations = {}, host_exits = {},
        tail_returns = {},
    }, V2Machine)
    return self
end

function V2Machine:emit(record, product)
    local offset = self.arena:append(record)
    local holes = record.holes
    -- the reject/overflow pc hole carries the owning occurrence's bytecode pc
    if self.pc and holes.resume then
        patch_hole(self.arena, offset, holes.resume, self.pc, "i32")
    end
    -- every record that can reach the boundary stub carries host_exit holes
    for _, at in ipairs(holes.host_exit or {}) do
        self.host_exits[#self.host_exits + 1] = offset + at
    end
    for kind, value in pairs(product) do
        if kind == "const" then
            if value then
                if value.patch_poly then
                    value:patch_poly(self:const_patcher(offset, holes))
                else
                    patch_hole(self.arena, offset, holes.const_tag, value.tag, "i32")
                    patch_hole(self.arena, offset, holes.const_int, value.int_bits, "u64")
                    patch_hole(self.arena, offset, holes.const_flt, value.flt_bits, "u64")
                    patch_hole(self.arena, offset, holes.const_ref, value.ref, "u64")
                end
            end
        elseif kind:sub(1, 5) == "u64::" then
            patch_hole(self.arena, offset, holes[kind:sub(6)], value, "u64")
        elseif kind:sub(1, 5) == "link:" then
            for _, at in ipairs(holes[kind:sub(6)] or {}) do
                self.links[#self.links + 1] = {
                    at = offset + at, target_start = value,
                }
            end
        else
            assert(value ~= nil, "cps v2: nil hole value for " .. kind)
            patch_hole(self.arena, offset, holes[kind], value, "i32")
        end
    end
    return offset
end

-- PolyConstantPatcher-compatible API bound to the current record's holes:
-- concrete constant leaves call cc:nil_value()/integer()/... to patch the
-- const_tag/const_int/const_flt/const_ref holes of the emitted record.
function V2Machine:const_patcher(offset, holes)
    local arena = self.arena
    local function patch(hole, value, encoding)
        patch_hole(arena, offset, holes[hole], value, encoding)
    end
    return {
        patch = function(_, hole, value, encoding)
            patch_hole(arena, offset, holes[hole], value, encoding)
        end,
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

function V2Machine:emit_call(call, pc)
    local record = self.bank.cps[call.tail and "tailcall" or "call"]
    local offset = self:emit(record, {
        call_a = call.A, call_b = call.B, call_c = call.C,
        call_pc = pc,
        host_exit = true,
    })
    if call.tail then
        -- the per-occurrence HostTailReturnV2 stub follows this record; its
        -- address is patched into the tailcall's tail_return hole
        local stub = self.bank.cps.host_tail_return
        local stub_offset = self.arena:append(stub)
        patch_hole(self.arena, stub_offset, stub.holes.call_a, call.A, "i32")
        patch_hole(self.arena, stub_offset, stub.holes.call_pc, pc, "i32")
        for _, at in ipairs(record.holes.tail_return or {}) do
            patch_u64(self.arena.memory, offset + at,
                ffi.cast("uintptr_t", self.arena.memory) + stub_offset)
        end
    else
        for _, at in ipairs(record.holes.continuation or {}) do
            self.continuations[#self.continuations + 1] = { at = offset + at, pc = pc }
        end
    end
    return offset
end

-- ---- the invocation owner ------------------------------------------------

local InvocationV2 = {}
InvocationV2.__index = InvocationV2

function InvocationV2.new(plans, heap, opts)
    opts = opts or {}
    local function_count = 0
    for index in pairs(plans) do function_count = math.max(function_count, index + 1) end
    local desc_bytes = align16(ffi.sizeof("Lua55NativeFunctionDescriptorV2") * function_count)
    local frame_region = opts.frame_region or (64 * 1024 * 1024)
    local mapping_size = align16(INV_SIZE) + desc_bytes + frame_region
    local raw = ffi.C.mmap(nil, mapping_size, PROT_READ + PROT_WRITE,
        MAP_PRIVATE + MAP_ANONYMOUS, -1, 0)
    assert(raw ~= MAP_FAILED, "cps v2: invocation mmap failed")
    local base = ffi.cast("uint8_t *", raw)
    local invocation = ffi.cast("Lua55NativeInvocationV2 *", base)
    local functions = ffi.cast("Lua55NativeFunctionDescriptorV2 *",
        base + align16(INV_SIZE))
    local frame_begin = ffi.cast("uint8_t *", functions) + desc_bytes
    local frame_end = frame_begin + frame_region
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
    invocation[0].outcome.discriminant = OUTCOME_EXECUTING
    local self = setmetatable({
        raw = raw, mapping_size = mapping_size,
        invocation = invocation, functions = functions,
        function_count = function_count,
        frame_begin = frame_begin, frame_end = frame_end,
        heap = heap, plans = plans, arenas = {}, opts = opts,
    }, InvocationV2)
    return self
end

function InvocationV2:free()
    if self.raw == false then return end
    for _, item in pairs(self.arenas) do
        if item.code then item.code:free() end
    end
    self.heap:free()
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

local function build_function_arena_v2(inv, ctx, plan)
    local arena = Native.Arena.new(131072)
    arena:append(assert(V2_BANK.cps.host_exit, "host_exit stub absent"))
    local base = tonumber(ffi.cast("uintptr_t", arena.memory))
    local machine = V2Machine.new(arena, V2_BANK, plan)
    local entries = {}
    local pc = 0
    while pc < plan.n do
        local call = plan.calls[pc]
        if call then
            machine.pc = pc
            if call.kind == "tforcall" then
                entries[pc] = arena.cursor
                local offset = machine:emit(
                    assert(V2_BANK.v2[76], "V2 TFORCALL absent"), {
                        call_a = call.A, call_c = call.C, call_pc = pc,
                    })
                for _, at in ipairs(V2_BANK.v2[76].holes.continuation or {}) do
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
            machine.pc = pc
            machine:emit(assert(V2_BANK.v2[74], "V2 FORPREP absent"), {
                base_index = boundary.A,
                ["link:body_link"] = boundary.body_pc,
                ["link:skip_link"] = boundary.skip_pc,
            })
            pc = pc + 1
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
    -- resolve deferred absolute links: block start -> published address
    for _, item in ipairs(machine.links) do
        local target = assert(entries[item.target_start],
            "cps v2: link target is not a block start")
        patch_u64(arena.memory, item.at, base + target)
    end
    for _, item in ipairs(machine.continuations) do
        local target = assert(entries[item.pc + 1],
            "cps v2: call continuation is not a block start")
        patch_u64(arena.memory, item.at, base + target)
    end
    for _, at in ipairs(machine.host_exits) do
        patch_u64(arena.memory, at, base)
    end
    local code = arena:seal()
    local block_entries = {}
    for start, at in pairs(entries) do
        block_entries[start] = ffi.cast("Lua55NativeEntryV2",
            ffi.cast("uintptr_t", code.memory) + at)
    end
    return {
        code = code, block_entries = block_entries,
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
local function build_env(heap, user_callbacks, dispatch)
    local env = heap:table(0, 32)
    dispatch = dispatch or {}
    local fixed = { next = 1, pairs = 3, ipairs = 4, select = 5, rawget = 6, rawset = 7 }
    for name, id in pairs(fixed) do
        local field = env:field_value(heap:short_string(name), true)
        field.tag, field.reserved = 8, 0
        field.payload.reference = heap:builtin(id)
    end
    for name, value in pairs(user_callbacks or {}) do
        local id = next_id()
        dispatch[id] = value
        local field = env:field_value(heap:short_string(name), true)
        field.tag, field.reserved = 8, 0
        field.payload.reference = heap:builtin(id)
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

local function run(source, opts)
    opts = opts or {}
    local bytes = opts.precompiled and source or Run55.compile(source, opts.luac)
    local main = Undump.undump(bytes)
    local heap = Heap.GuestHeap.new(opts.generation or 1, opts.region_size)
    local ctx = { bank = V2_BANK, plans = {} }
    ctx.plans, ctx.main_index = Run55.build_plans(main, heap)
    local inv = InvocationV2.new(ctx.plans, heap, opts)
    -- build V2 arenas only for plans whose every occurrence has a V2 leaf;
    -- a plan without a V2 leaf keeps entry == 0 (pre-publication rejection)
    local build_errors = {}
    for index, plan in pairs(ctx.plans) do
        local ok, built = pcall(build_function_arena_v2, inv, ctx, plan)
        if ok then inv.arenas[plan] = built else build_errors[index] = built end
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
    assert(arena, "cps v2: the main plan is outside the V2 poly subset"
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
    frame[0].values = ffi.cast("Lua55ValueV2 *",
        inv.frame_begin + FRAME_SIZE)
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
    local env = build_env(heap, opts.callbacks, dispatch)
    if #(plan.proto.upvals or {}) > 0 then
        frame[0].upvalues = make_env_cells(inv, env:reference(), #(plan.proto.upvals or {}))
    end
    if opts.force_gc_before_entry then
        collectgarbage("collect")
        collectgarbage("collect")
        heap:assert_native_ownership()
    end
    arena.entry(frame)
    -- boundary outcome loop: host calls suspend to Lua, then re-enter
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
    if opts.return_invocation then return values, inv end
    inv:free()
    return values
end

return {
    InvocationV2 = InvocationV2,
    build_function_arena_v2 = build_function_arena_v2,
    run = run,
    root_frame_bytes = root_frame_bytes,
    V2Machine = V2Machine,
    ffi = ffi,
}
