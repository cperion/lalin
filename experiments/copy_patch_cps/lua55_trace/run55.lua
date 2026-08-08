-- run55: a minimal real-program runner for the Lua 5.5 native trace subset.
--
-- Pipeline: source -> stock luac bytecode -> undump55 -> per-proto call
-- plans -> native block execution with host-mediated boundaries. Library
-- functions (print, tostring, math.*, select/rawget/rawset) are guest
-- builtin markers dispatched to LuaJIT host callbacks; the user's own
-- functions run natively through their block-graph plans. Numeric for
-- loops are a host FORPREP boundary plus a native FORLOOP terminal; the
-- generic for dispatches native pairs/ipairs/next iterators and native
-- closure iterators.
--
-- Lua owns genericity: every call into a library function crosses the
-- FFI boundary into LuaJIT and returns converted values. The native core
-- stays monomorphic (integers/floats/strings/tables/closures).

local ffi = require("ffi")

package.path = "./lua/?.lua;./lua/?/init.lua;./?.lua;./?/init.lua;" .. package.path

local Undump = require("experiments.lua55.undump55")
local Projection = require("experiments.copy_patch_cps.lua55_trace.opcode_00_10_projection")
local Native = require("experiments.copy_patch_cps.lua55_trace.opcode_00_08")
local Heap = require("experiments.copy_patch_cps.lua55_trace.guest_heap_v1")
local GTable = require("experiments.copy_patch_cps.lua55_trace.opcode_generic_table")
require("experiments.copy_patch_cps.lua55_trace.opcode_concat")  -- loads liblua55fmt

local STOCK_LUAC = "/tmp/lua-5.5.0/src/luac"

-- ---------------------------------------------------------------------
-- Bank assembly.

local function assemble_bank()
    local bank = dofile("target/copy_patch_cps/lua55_trace/opcode_00_08/bank.lua")
    local extends = {
        "opcode_09_10", "opcode_string", "opcode_table", "opcode_compare",
        "opcode_arith", "opcode_unary", "opcode_jmp", "opcode_pow",
        "opcode_call", "opcode_generic_table", "opcode_setlist",
        "opcode_closure", "opcode_concat", "opcode_vararg", "opcode_tfor",
        "opcode_close", "opcode_iter", "opcode_for", "opcode_link",
    }
    for _, name in ipairs(extends) do
        Native.extend_bank(bank, dofile("target/copy_patch_cps/lua55_trace/" .. name .. "/bank.lua"))
    end
    return bank
end

local BANK = assemble_bank()

-- ---------------------------------------------------------------------
-- Compile a source file with the stock Lua 5.5 luac; return the bytes.

local function compile(source_path, luac)
    luac = luac or STOCK_LUAC
    local out = "target/copy_patch_cps/lua55_trace/run55_input.luac"
    local err = "target/copy_patch_cps/lua55_trace/run55_input.err"
    os.remove(out); os.remove(err)
    local ok, why, status = os.execute(([=[%s -o %s %s 2>%s]=]):format(luac, out, source_path, err))
    if not ok or status ~= 0 then
        local message = ""
        local handle = io.open(err, "rb")
        if handle then message = handle:read("*a"); handle:close() end
        os.remove(err)
        error(("run55: luac failed: %s"):format(message), 0)
    end
    os.remove(err)
    local handle = assert(io.open(out, "rb"), "run55: luac produced no output")
    local bytes = handle:read("*a"); handle:close()
    os.remove(out)
    return bytes
end

-- ---------------------------------------------------------------------
-- Protos -> global index -> call plan. Every proto gets a global index via
-- DFS; CLOSURE occurrences' relative proto indexes are patched to the
-- global index so the host can resolve a closure's plan from the guest
-- object (Lua55GuestClosureV1.proto_index).

local function build_plans(main, heap)
    local proto_global = {}
    local function assign(proto, next_index)
        proto_global[proto] = next_index
        local index = next_index + 1
        for _, sub in ipairs(proto.protos or {}) do
            index = assign(sub, index)
        end
        return index
    end
    assign(main, 0)
    local plans = {}
    for proto, global_index in pairs(proto_global) do
        local plan = Projection.project_call_plan(proto, heap)
        for _, block in ipairs(plan.blocks) do
            for _, occurrence in ipairs(block.path.occurrences) do
                if occurrence.learner_name == "closure" then
                    local target = proto.protos[occurrence.proto_index + 1]
                    assert(target ~= nil, "closure target proto is absent")
                    occurrence.proto_index = assert(proto_global[target],
                        "closure target has no global index")
                end
            end
        end
        plans[global_index] = plan
    end
    return plans, proto_global[main]
end

-- ---------------------------------------------------------------------
-- Guest value conversions across the host boundary.

local function guest_to_host(bank, value)
    local tag = tonumber(value.tag)
    if tag == bank.tags.nil_value then return nil
    elseif tag == bank.tags.false_value then return false
    elseif tag == bank.tags.true_value then return true
    elseif tag == bank.tags.integer then return tonumber(value.payload.integer)
    elseif tag == bank.tags.floating then return tonumber(value.payload.floating)
    elseif tag == bank.tags.short_string or tag == bank.tags.long_string then
        local string = ffi.cast("Lua55GuestStringV1 *", tonumber(value.payload.reference))
        return ffi.string(string[0].bytes, tonumber(string[0].length))
    elseif tag == bank.tags.table_value then
        return ("table: 0x%x"):format(tonumber(value.payload.reference))
    elseif tag == bank.tags.closure_value then
        return ("function: 0x%x"):format(tonumber(value.payload.reference))
    end
    error("run55: unsupported guest value tag " .. tostring(tag), 0)
end

local function host_to_guest(frame, heap, bank, index, value)
    local kind = type(value)
    if value == nil then
        frame:set_nil(index)
    elseif value == false then
        frame:set_false(index)
    elseif value == true then
        frame:set_true(index)
    elseif kind == "number" then
        if value == math.floor(value) and value >= -9223372036854775808.0
            and value <= 9223372036854775807.0 then
            frame:set_integer(index, ffi.new("int64_t", value))
        else
            frame:set_float(index, value)
        end
    elseif kind == "string" then
        frame:set_short_string(index, heap:short_string(value))
    else
        error("run55: unsupported host value " .. kind, 0)
    end
end

-- ---------------------------------------------------------------------
-- Builtin marker detection (Lua55GuestBuiltinV1, closure-tagged).

local function builtin_id(bank, value)
    if tonumber(value.tag) ~= bank.tags.closure_value then return nil end
    local ref = tonumber(value.payload.reference)
    if not ref or ref == 0 then return nil end
    local object = ffi.cast("Lua55GuestObjectHeaderV1 *", ref)
    if tonumber(object[0].kind) ~= 5 then return nil end
    return tonumber(ffi.cast("Lua55GuestBuiltinV1 *", ref)[0].builtin_id)
end

local function set_closure(frame, index, reference)
    frame.values[index].tag, frame.values[index].reserved = 8, 0
    frame.values[index].payload.reference = reference
end

-- ---------------------------------------------------------------------
-- The environment: a guest table mapping names to builtin markers. Host
-- callbacks get ids from NEXT_ID upward; iter markers use 1-4, and the
-- select/rawget/rawset builtins use 5-7.

local NEXT_ID = 8

local function build_env(ctx, callbacks)
    local env = ctx.heap:table(0, 16)
    local function bind(target, name, value)
        local field = target:field_value(ctx.heap:short_string(name), true)
        local kind = type(value)
        if kind == "function" then
            local id = ctx.next_id
            ctx.next_id = id + 1
            ctx.callbacks[id] = value
            field.tag, field.reserved = 8, 0
            field.payload.reference = ctx.heap:builtin(id)
        elseif kind == "table" then
            local sub = ctx.heap:table(0, 8)
            for subname, subvalue in pairs(value) do bind(sub, subname, subvalue) end
            field.tag, field.reserved = 7, 0
            field.payload.reference = sub:reference()
        elseif kind == "number" then
            if value == math.floor(value) and value >= -9223372036854775808.0
                and value <= 9223372036854775807.0 then
                field.tag, field.reserved = 3, 0
                field.payload.integer = ffi.new("int64_t", value)
            else
                field.tag, field.reserved = 4, 0
                field.payload.floating = value
            end
        else
            error("run55: unsupported env binding " .. kind, 0)
        end
    end
    for name, value in pairs(callbacks) do bind(env, name, value) end
    -- the native protocol markers: pairs/ipairs/next (1-4) and the
    -- select/rawget/rawset builtins (5-7); they override any host callbacks
    -- of the same name
    local markers = {
        next = 1, ["ipairs-iter"] = nil, pairs = 3, ipairs = 4,
        select = 5, rawget = 6, rawset = 7,
    }
    for name, id in pairs(markers) do
        if id ~= nil then
            local field = env:field_value(ctx.heap:short_string(name), true)
            field.tag, field.reserved = 8, 0
            field.payload.reference = ctx.heap:builtin(id)
        end
    end
    return env
end

-- ---------------------------------------------------------------------
-- Frames and driver.

local function frame_for(plan, ctx)
    local slot_count = 0
    for _, block in ipairs(plan.blocks) do
        slot_count = math.max(slot_count, #block.path.occurrences)
    end
    return Native.FrameOwner.new(
        plan.proto.maxstacksize, slot_count, #(plan.proto.upvals or {}), ctx.heap, true)
end

local function copy_cells(closure, cframe, plan)
    local proto = plan.proto
    for index = 0, tonumber(closure[0].upvalue_count) - 1 do
        local cell = closure[0].cells[index]
        local scratch = proto.maxstacksize - 1
        cframe:open_upvalue(index, scratch, 1)
        if cell.state == 1 then
            cframe.values[scratch] = cell.open_slot[0]
        else
            cframe.values[scratch] = cell.closed_value
        end
        cframe:close_upvalue(index, 2)
    end
end

-- The host FORPREP boundary: stock forprep (lvm.c). Returns the next pc
-- (skip_pc when the loop must not run, body_pc otherwise) and prepares the
-- three cells (integer: R[A]=count R[A+1]=step R[A+2]=idx; float:
-- R[A]=limit R[A+1]=step R[A+2]=idx).
local function host_forprep(frame, boundary)
    local A = boundary.A
    local init, limit, step = frame.values[A], frame.values[A + 1], frame.values[A + 2]
    local tag = { integer = 3, floating = 4 }
    local function number_of(value, role)
        if tonumber(value.tag) == tag.integer then return tonumber(value.payload.integer) end
        if tonumber(value.tag) == tag.floating then return tonumber(value.payload.floating) end
        error(("run55: 'for' %s is not a number"):format(role), 0)
    end
    if tonumber(init.tag) == tag.integer and tonumber(step.tag) == tag.integer then
        local iv, sv = tonumber(init.payload.integer), tonumber(step.payload.integer)
        if sv == 0 then error("run55: 'for' step is zero", 0) end
        local lv
        if tonumber(limit.tag) == tag.integer then
            lv = tonumber(limit.payload.integer)
        else
            local flim = tonumber(limit.payload.floating)
            lv = sv > 0 and math.floor(flim) or math.ceil(flim)
            -- (the out-of-int64 clipping cases stay out of the demo's range)
        end
        if (sv > 0 and iv > lv) or (sv < 0 and iv < lv) then return boundary.skip_pc end
        local count
        if sv > 0 then count = math.floor((lv - iv) / sv)
        else count = math.floor((iv - lv) / (-sv)) end
        frame:set_integer(A, count)
        frame:set_integer(A + 1, sv)   -- the limit cell becomes the step
        frame:set_integer(A + 2, iv)   -- the step cell becomes the control
        return boundary.body_pc
    else
        local ninit, nlimit, nstep =
            number_of(init, "initial value"), number_of(limit, "limit"), number_of(step, "step")
        if nstep == 0 then error("run55: 'for' step is zero", 0) end
        if (nstep > 0 and nlimit < ninit) or (nstep < 0 and ninit < nlimit) then
            return boundary.skip_pc
        end
        frame:set_float(A, nlimit)
        frame:set_float(A + 1, nstep)
        frame:set_float(A + 2, ninit)
        return boundary.body_pc
    end
end

-- ---- Loop SCC detection ------------------------------------------------
-- A loop SCC (the strongly connected block graph: terminal back-edges plus
-- sequential flow) executes as ONE native arena: the intra-SCC transfers are
-- patched native jumps (JMP/FORLOOP link terminals), so a loop iteration
-- never crosses into the Lua host. The exits (loop end, call boundaries,
-- returns) still `ret` to the host, which dispatches the next site.

local COMPARE_PREFIXES = {}
for _, name in ipairs({ "eq", "lt", "le", "eqk", "eqi", "lti", "lei", "gti", "gei", "test", "testset" }) do
    COMPARE_PREFIXES[name] = true
end

local function compare_prefix(name)
    local prefix = name and name:match("^([a-z]+)_k%d+$")
    if prefix and COMPARE_PREFIXES[prefix] then return prefix end
    return false
end

-- The native-branch target pc of a terminal occurrence (JMP / compare /
-- FORLOOP / TFORLOOP), or nil for the sequential/return/call boundaries.
local function terminal_edge(occurrence)
    local name = occurrence and occurrence.learner_name
    if name == "jmp" then return occurrence.target end
    if name == "forloop" then return occurrence.back_edge end
    if name == "tforloop" then return occurrence.target_pc end
    if compare_prefix(name) then return occurrence.target_pc end
    return nil
end

-- A terminal occurrence does not chain to the next record: it ends with the
-- patched link, the `ret`, or the sequential chain for the not-taken path.
local function is_terminal(occurrence)
    local name = occurrence and occurrence.learner_name
    if name == "jmp" or name == "forloop" or name == "tforloop" or name == "tforprep" then return true end
    if name == "return" or name == "return0" or name == "return1" then return true end
    return compare_prefix(name) ~= false
end

local function compute_loop_state(plan)
    local block_at = plan.block_at
    local adj = {}
    local function add(from_bi, to_pc)
        local to_bi = block_at[to_pc]
        if to_bi then
            local set = adj[from_bi] or {}
            set[to_bi] = true
            adj[from_bi] = set
        end
    end
    for bi, block in ipairs(plan.blocks) do
        add(bi, block.stop)   -- the sequential edge (the next block start)
        local last = block.path.occurrences[#block.path.occurrences]
        local target = terminal_edge(last)
        if target then add(bi, target) end
    end
    -- Tarjan SCCs
    local index, stack, on_stack = 0, {}, {}
    local low, indices, sccs = {}, {}, {}
    local function strongconnect(v)
        index = index + 1
        indices[v], low[v], on_stack[v] = index, index, true
        stack[#stack + 1] = v
        for w in pairs(adj[v] or {}) do
            if not indices[w] then
                strongconnect(w)
                low[v] = math.min(low[v], low[w])
            elseif on_stack[w] then
                low[v] = math.min(low[v], indices[w])
            end
        end
        if low[v] == indices[v] then
            local component = {}
            while true do
                local w = stack[#stack]; stack[#stack] = nil
                on_stack[w] = nil
                component[#component + 1] = w
                if w == v then break end
            end
            table.sort(component)
            sccs[#sccs + 1] = component
        end
    end
    for v = 1, #plan.blocks do if not indices[v] then strongconnect(v) end end
    -- keep only the real loops (>1 block, or a block with a terminal
    -- self-edge such as the numeric-for body)
    local scc_of = {}
    for _, component in ipairs(sccs) do
        local is_loop = #component > 1
        if #component == 1 then
            local bi = component[1]
            local last = plan.blocks[bi].path.occurrences[#plan.blocks[bi].path.occurrences]
            local target = terminal_edge(last)
            if target and block_at[target] == bi then is_loop = true end
        end
        if is_loop then
            local entry = { blocks = component, arena = false }
            for _, bi in ipairs(component) do
                scc_of[plan.blocks[bi].start] = entry
            end
        end
    end
    return { scc_of = scc_of }
end

-- ---- Loop arenas ------------------------------------------------------
-- One RX arena per loop SCC: the SCC's blocks appended sequentially (the
-- compare fallthrough and the sequential flow chain natively), the
-- intra-SCC JMP/FORLOOP back-edges patched to the target block's code
-- address, and a finish record at each call boundary. Built from the
-- recorded per-block slots once the SCC's blocks have all been seen.

local LINK_JMP_QUOTE, LINK_FORLOOP_QUOTE = 65000, 65001

local function patch_i32(memory, offset, value)
    ffi.cast("int32_t *", memory + offset)[0] = value
end
local function patch_u64(memory, offset, value)
    ffi.cast("uint64_t *", memory + offset)[0] = value
end

local function copy_block_slots(ctx, plan, block_start, frame)
    local per_plan = ctx.block_slots[plan] or {}
    ctx.block_slots[plan] = per_plan
    local count = tonumber(frame.frame.slot_cursor)
    local slots = ffi.new("Lua55RecordingSlotV1[?]", count)
    if count > 0 then
        ffi.copy(slots, frame.slots, count * ffi.sizeof("Lua55RecordingSlotV1"))
    end
    local table_slots = false
    if frame.table_slots then
        table_slots = ffi.new("Lua55TableRecordingV1[?]", count)
        if count > 0 then
            ffi.copy(table_slots, frame.table_slots, count * ffi.sizeof("Lua55TableRecordingV1"))
        end
    end
    per_plan[block_start] = { slots = slots, table_slots = table_slots, count = count }
end

local function invalidate_scc(ctx, plan, block_start)
    local state = ctx.loop_state[plan]
    local scc = state and state.scc_of[block_start]
    if scc and scc.arena then
        scc.arena.code:free()
        scc.arena = false
    end
end

local function build_loop_arena(ctx, plan, scc)
    local arena = Native.Arena.new(131072)
    local entries, link_patches = {}, {}
    local membership = {}
    for _, bi in ipairs(scc.blocks) do membership[bi] = true end
    local slots = ctx.block_slots[plan]
    for _, bi in ipairs(scc.blocks) do
        local block = plan.blocks[bi]
        entries[block.start] = arena.cursor
        local block_slots = slots[block.start]
        local occurrences = block.path.occurrences
        for i, occurrence in ipairs(occurrences) do
            local name = occurrence.learner_name
            local link_target = terminal_edge(occurrence)
            if (name == "jmp" or name == "forloop")
                and link_target and membership[plan.block_at[link_target]] then
                local record = ctx.bank.quotes[name == "jmp" and LINK_JMP_QUOTE or LINK_FORLOOP_QUOTE]
                assert(record, "loop link quotation is absent")
                local offset = arena:append(record)
                if name == "jmp" then
                    patch_i32(arena.memory, offset + record.holes.target_pc[1], occurrence.target)
                else
                    patch_i32(arena.memory, offset + record.holes.base_index[1], occurrence.A)
                    patch_i32(arena.memory, offset + record.holes.back_edge[1], occurrence.back_edge)
                    patch_i32(arena.memory, offset + record.holes.fallthrough[1], occurrence.fallthrough_pc)
                end
                for _, link_hole in ipairs(record.holes.link or {}) do
                    link_patches[#link_patches + 1] = {
                        at = offset + link_hole, target_start = link_target,
                    }
                end
            else
                local slot = block_slots.slots[i - 1]
                local table_slot = block_slots.table_slots and block_slots.table_slots[i - 1] or nil
                occurrence:append_residual(ctx.bank, slot, arena, table_slot)
            end
        end
        local last = occurrences[#occurrences]
        if not is_terminal(last) then
            -- the block ends at a call boundary: the chain must return to the
            -- host so the CALL/TFORCALL/forprep dispatch runs
            Native.append_finish(arena, ctx.bank, block.stop)
        end
    end
    local base = tonumber(ffi.cast("uintptr_t", arena.memory))
    for _, patch in ipairs(link_patches) do
        patch_u64(arena.memory, patch.at, base + entries[patch.target_start])
    end
    local code = arena:seal()
    local block_entries = {}
    for _, bi in ipairs(scc.blocks) do
        local block = plan.blocks[bi]
        block_entries[block.start] = ffi.cast("Lua55OpcodeEntryV1",
            ffi.cast("uintptr_t", code.memory) + entries[block.start])
    end
    return { code = code, block_entries = block_entries }
end

-- Cached per-(plan, block) native programs: the residual persists across
-- loop iterations (the learner runs once; re-running the residual is the
-- native fast path).
local function program_for(ctx, plan, block)
    local per_plan = ctx.programs[plan]
    if per_plan == nil then per_plan = {}; ctx.programs[plan] = per_plan end
    local program = per_plan[block.start]
    if program == nil then
        -- large literals produce long blocks (200+ occurrences); give the
        -- learner arena generous headroom (128 KiB)
        program = block.path:new_program(block.stop, ctx.bank, 131072)
        per_plan[block.start] = program
    end
    return program
end

-- Execute the site for a block: the loop arena's block entry (native, no
-- host re-entry) once built, otherwise the per-block program (which records
-- the block's slots on its first run).
local function execute_site(ctx, plan, block, frame)
    local state = ctx.loop_state[plan]
    local scc = state and state.scc_of[block.start]
    if scc then
        if not scc.arena then
            local all = true
            local slots = ctx.block_slots[plan]
            for _, bi in ipairs(scc.blocks) do
                if not (slots and slots[plan.blocks[bi].start]) then all = false break end
            end
            if all then scc.arena = build_loop_arena(ctx, plan, scc) end
        end
        if scc.arena then
            local f = frame.frame
            local f = frame.frame
            f.slot_cursor, f.resume_pc, f.status = 0, 0, 0
            scc.arena.block_entries[block.start](f)
            return tonumber(f.status)
        end
    end
    local program = program_for(ctx, plan, block)
    local before = program.recordings
    local status = program:execute(frame)
    if program.recordings > before then
        copy_block_slots(ctx, plan, block.start, frame)
        invalidate_scc(ctx, plan, block.start)
    end
    return status
end

-- ---- Host builtin dispatch ----------------------------------------------

local function dispatch_select(frame, call, ctx)
    local first = frame.values[call.A + 1]
    local count
    if tonumber(first.tag) == ctx.bank.tags.short_string
        and ffi.cast("Lua55GuestStringV1 *", tonumber(first.payload.reference))[0].length == 1
        and ffi.cast("Lua55GuestStringV1 *", tonumber(first.payload.reference))[0].bytes[0] == 35 then
        -- select("#", ...) -> the count (args after the "#")
        count = call.B - 2
        frame:set_integer(call.A, count)
    else
        assert(tonumber(first.tag) == ctx.bank.tags.integer, "run55: select index is not an integer")
        local i = tonumber(first.payload.integer)
        assert(i >= 1 and i <= call.B - 2, "run55: select index out of range")
        count = call.B - 1 - i   -- the varargs from the ith: R[A+1+i .. A+B-2]
        for k = 0, count - 1 do
            frame.values[call.A + k] = frame.values[call.A + 1 + i + k]
        end
    end
    frame.top = call.A + (call.C >= 1 and math.min(call.C - 1, count) or count)
end

local function dispatch_builtin(frame, call, ctx, bid)
    if bid == 1 then   -- next(t, k) as a plain call
        local nf = ctx.next_program:new_frame()
        nf.values[0] = frame.values[call.A + 1]
        nf.values[1] = frame.values[call.A + 2]
        assert(ctx.next_program:execute(nf) == ctx.bank.status.completed)
        frame.values[call.A] = nf.values[2]
        frame.values[call.A + 1] = nf.values[3]
        frame.top = call.A + 2
    elseif bid == 2 then
        error("run55: ipairs-iter is a TFORCALL-only iterator", 0)
    elseif bid == 3 then   -- pairs(t) -> (next, t, nil)
        set_closure(frame, call.A, ctx.NEXT.reference)
        frame:set_nil(call.A + 2)
        for i = 3, call.C - 2 do frame:set_nil(call.A + i) end   -- clear the rest
        frame.top = call.A + (call.C >= 1 and call.C - 1 or 3)
    elseif bid == 4 then   -- ipairs(t) -> (ipairs_iter, t, 0)
        set_closure(frame, call.A, ctx.IPAIRS_ITER.reference)
        frame:set_integer(call.A + 2, 0)
        for i = 3, call.C - 2 do frame:set_nil(call.A + i) end   -- clear the rest
        frame.top = call.A + (call.C >= 1 and call.C - 1 or 3)
    elseif bid == 5 then   -- select
        dispatch_select(frame, call, ctx)
    elseif bid == 6 then   -- rawget(t, k) via the native gettable leaf
        local program = Native.Program.new({
            GTable.GenericTableOccurrence.gettable(0, 2, 0, 1),
        }, 4, 1, ctx.bank, 16384, 0, ctx.heap)
        local rg = program:new_frame()
        rg.values[0] = frame.values[call.A + 1]
        rg.values[1] = frame.values[call.A + 2]
        assert(program:execute(rg) == ctx.bank.status.completed,
            "run55: rawget failed")
        frame.values[call.A] = rg.values[2]
        frame.top = call.A + 1
        program:free()
    elseif bid == 7 then   -- rawset(t, k, v) via the native settable leaf
        local program = Native.Program.new({
            GTable.GenericTableOccurrence.settable(0, 0, 1, 2),
        }, 4, 1, ctx.bank, 16384, 0, ctx.heap)
        local rs = program:new_frame()
        rs.values[0] = frame.values[call.A + 1]
        rs.values[1] = frame.values[call.A + 2]
        rs.values[2] = frame.values[call.A + 3]
        assert(program:execute(rs) == ctx.bank.status.completed,
            "run55: rawset failed")
        frame.top = call.A
        program:free()
    else
        -- a host library callback
        local callback = assert(ctx.callbacks[bid], "run55: unknown builtin " .. tostring(bid))
        local nargs = call.B - 1
        if nargs < 0 then
            -- B = 0: the args are the previous call's results up to the top
            nargs = math.max((frame.top or 0) - (call.A + 1), 0)
        end
        local args = {}
        for i = 1, nargs do args[i] = guest_to_host(ctx.bank, frame.values[call.A + i]) end
        local results = { callback(unpack(args)) }
        local want = call.C - 1
        local count = want >= 0 and math.min(want, #results) or #results
        for i = 0, count - 1 do
            host_to_guest(frame, ctx.heap, ctx.bank, call.A + i, results[i + 1])
        end
        for i = count, want - 1 do frame:set_nil(call.A + i) end
        if want >= 0 then frame.top = call.A + want
        else frame.top = call.A + count end
    end
end

-- ---- The CPS invoke machine -------------------------------------------
-- Named methods with strict tail calls as the edges (LuaJIT compiles
-- proper tail calls). The machine owns the computation state; methods name
-- their successors directly: at_pc -> block / call / tforcall / forprep ->
-- at_pc / returned. No mutable pc loop, no capturing continuations.

local InvokeMachine = {}
InvokeMachine.__index = InvokeMachine

function InvokeMachine.new(ctx, plan, frame, dest)
    return setmetatable({ ctx = ctx, plan = plan, frame = frame, dest = dest }, InvokeMachine)
end

function InvokeMachine:run()
    return self:at_pc(0)
end

function InvokeMachine:at_pc(pc)
    if pc == nil or pc >= self.plan.n then return { fired = false } end
    local call = self.plan.calls[pc]
    if call then
        if call.kind == "tforcall" then return self:tforcall(call, pc) end
        return self:call(call, pc)
    end
    local boundary = self.plan.forpreps[pc]
    if boundary then return self:forprep(boundary) end
    return self:block(pc)
end

function InvokeMachine:block(pc)
    local plan = self.plan
    local block = plan.blocks[plan.block_at[pc]]
    if not block then return self:at_pc(pc + 1) end
    local status = execute_site(self.ctx, plan, block, self.frame)
    if status == self.ctx.bank.status.guard_failed then
        -- the shape changed (a NEWTABLE bumped a fresh table): re-learn the
        -- per-block program against the new shape
        local program = program_for(self.ctx, plan, block)
        program:free()
        self.ctx.programs[plan][block.start] = nil
        program = block.path:new_program(block.stop, self.ctx.bank, 131072)
        self.ctx.programs[plan][block.start] = program
        local before = program.recordings
        status = program:execute(self.frame)
        if program.recordings > before then
            copy_block_slots(self.ctx, plan, block.start, self.frame)
        end
    end
    assert(status ~= self.ctx.bank.status.guard_failed,
        ("run55: block guard failed at pc %d (unstable shape)"):format(pc))
    assert(status == self.ctx.bank.status.completed,
        ("run55: block did not complete at pc %d (status %d resume %d)"):format(
            pc, tonumber(status), tonumber(self.frame.frame.resume_pc)))
    local rpc = self.frame.frame.resume_pc
    if rpc == block.stop then return self:at_pc(block.stop) end
    local ret = plan.returns[rpc]
    if ret then return self:returned(ret) end
    return self:at_pc(rpc)
end

function InvokeMachine:returned(ret)
    local dest = self.dest
    local nres = ret.B - 1
    if nres < 0 then nres = 0 end
    if dest then
        local count = dest.count or nres
        for i = 0, math.min(count, nres) - 1 do
            dest.frame.values[dest.base + i] = self.frame.values[ret.A + i]
        end
    end
    return { fired = true, ret = ret, frame = self.frame }
end

function InvokeMachine:forprep(boundary)
    return self:at_pc(host_forprep(self.frame, boundary))
end

function InvokeMachine:tforcall(call, pc)
    local ctx = self.ctx
    local frame = self.frame
    local iter = builtin_id(ctx.bank, frame.values[call.A])
    if iter == 1 then   -- next(t, k)
        local nf = ctx.next_program:new_frame()
        nf.values[0] = frame.values[call.A + 1]
        nf.values[1] = frame.values[call.A + 3]
        assert(ctx.next_program:execute(nf) == ctx.bank.status.completed)
        for i = 0, call.C - 1 do
            frame.values[call.A + 3 + i] = nf.values[2 + i]
        end
        return self:at_pc(pc + 1)
    elseif iter == 2 then   -- ipairs-iter(t, i)
        local nf = ctx.ipairs_program:new_frame()
        nf.values[0] = frame.values[call.A + 1]
        nf.values[1] = frame.values[call.A + 3]
        assert(ctx.ipairs_program:execute(nf) == ctx.bank.status.completed)
        for i = 0, call.C - 1 do
            frame.values[call.A + 3 + i] = nf.values[2 + i]
        end
        return self:at_pc(pc + 1)
    elseif iter ~= nil then
        error("run55: unhandled iterator builtin " .. tostring(iter), 0)
    end
    -- a native closure iterator: invoke it with (state, control)
    local ref = tonumber(frame.values[call.A].payload.reference)
    local closure = ffi.cast("Lua55GuestClosureV1 *", ref)
    local callee_plan = assert(ctx.plans[tonumber(closure[0].proto_index)],
        "run55: no plan for the iterator closure")
    local cframe = frame_for(callee_plan, ctx)
    cframe.values[0] = frame.values[call.A + 1]   -- state
    cframe.values[1] = frame.values[call.A + 3]   -- control
    copy_cells(closure, cframe, callee_plan)
    local result = InvokeMachine.new(ctx, callee_plan, cframe, nil):run()
    assert(result.fired, "run55: iterator did not return")
    for i = 0, call.C - 1 do
        frame.values[call.A + 3 + i] = cframe.values[result.ret.A + i]
    end
    return self:at_pc(pc + 1)
end

function InvokeMachine:call(call, pc)
    local ctx = self.ctx
    local frame = self.frame
    local callee = frame.values[call.A]
    local bid = builtin_id(ctx.bank, callee)
    if bid ~= nil then
        dispatch_builtin(frame, call, ctx, bid)
        return self:at_pc(pc + 1)
    end
    assert(tonumber(callee.tag) == ctx.bank.tags.closure_value,
        "run55: CALL target is not a closure or builtin")
    local ref = tonumber(callee.payload.reference)
    local closure = ffi.cast("Lua55GuestClosureV1 *", ref)
    assert(tonumber(closure[0].header.kind) == 4, "run55: CALL target is not a closure object")
    local callee_plan = assert(ctx.plans[tonumber(closure[0].proto_index)],
        "run55: no plan for the closure proto")
    local cframe = frame_for(callee_plan, ctx)
    local nargs = call.B - 1
    if nargs < 0 then
        nargs = math.max((frame.top or 0) - (call.A + 1), 0)
    end
    for i = 1, nargs do cframe.values[i - 1] = frame.values[call.A + i] end
    local nvar = (callee_plan.proto.flag or 0) ~= 0 and math.max(nargs - (callee_plan.proto.numparams or 0), 0) or 0
    if nvar > 0 then cframe:set_varargs(nvar) end
    copy_cells(closure, cframe, callee_plan)
    local expected = call.C - 1
    local dest2 = { frame = frame, base = call.A, count = expected >= 0 and expected or nil }
    if call.tail then dest2 = self.dest end
    local result = InvokeMachine.new(ctx, callee_plan, cframe, dest2):run()
    if call.tail then return result end
    if result.fired then
        local nres = math.max(result.ret.B - 1, 0)
        frame.top = call.A + (expected >= 0 and math.min(expected, nres) or nres)
    end
    return self:at_pc(pc + 1)
end

-- Public API.

local DEFAULT_CALLBACKS = {
    print = print,
    tostring = tostring,
    math = {
        floor = math.floor, sqrt = math.sqrt, abs = math.abs,
        max = math.max, min = math.min, ceil = math.ceil,
        huge = math.huge, pi = math.pi,
    },
}

local function new_context(heap, callbacks)
    local ctx = {
        heap = heap, bank = BANK, plans = {}, programs = {},
        callbacks = {}, next_id = NEXT_ID,
        block_slots = {}, loop_state = {},
    }
    ctx.env = build_env(ctx, callbacks or DEFAULT_CALLBACKS)
    ctx.NEXT = heap:builtin_value(1)
    ctx.IPAIRS_ITER = heap:builtin_value(2)
    ctx.next_program = Native.Program.new(
        { require("experiments.copy_patch_cps.lua55_trace.opcode_iter").NextIterOccurrence.new(0) },
        4, 1, BANK, 16384, 0, heap)
    ctx.ipairs_program = Native.Program.new(
        { require("experiments.copy_patch_cps.lua55_trace.opcode_iter").IPairsIterOccurrence.new(0) },
        4, 1, BANK, 16384, 0, heap)
    return ctx
end

-- Run a compiled chunk's bytes (or a source path) as a Lua 5.5 program.
-- Returns the main chunk's results as host values.
--
-- opts.luac        stock luac path (used only when a source path is given)
-- opts.generation  the guest heap generation
-- opts.callbacks   an env table (name -> host function | table | number)
-- opts.precompiled treat the input as compiled chunk bytes, not a path
local function run(source, opts)
    opts = opts or {}
    local bytes = opts.precompiled and source or compile(source, opts.luac)
    local main = Undump.undump(bytes)
    local heap = Heap.GuestHeap.new(opts.generation or 1, opts.region_size)
    local ctx = new_context(heap, opts.callbacks)
    ctx.plans, ctx.main_index = build_plans(main, heap)
    for index, plan in pairs(ctx.plans) do
        ctx.loop_state[plan] = compute_loop_state(plan)
    end
    local plan = assert(ctx.plans[ctx.main_index], "run55: main plan is absent")
    local frame = frame_for(plan, ctx)
    -- the main proto's one upvalue is the environment
    if #(plan.proto.upvals or {}) > 0 then
        local scratch = plan.proto.maxstacksize - 1
        frame:open_upvalue(0, scratch, 1)
        frame:set_table(scratch, ctx.env)
        frame:close_upvalue(0, 2)
    end
    local result = InvokeMachine.new(ctx, plan, frame, nil):run()
    assert(result.fired, "run55: main chunk did not return")
    local ret = result.ret
    local nres = math.max(ret.B - 1, 0)
    local values = {}
    for i = 0, nres - 1 do values[i + 1] = guest_to_host(BANK, result.frame.values[ret.A + i]) end
    if opts.raw then
        values = {}
        for i = 0, nres - 1 do values[i + 1] = result.frame.values[ret.A + i] end
    end
    -- release the native artifacts before the heap
    ctx.next_program:free()
    ctx.ipairs_program:free()
    for _, state in pairs(ctx.loop_state) do
        for _, scc in pairs(state.scc_of) do
            if scc.arena then scc.arena.code:free() end
        end
    end
    for _, per_plan in pairs(ctx.programs) do
        for _, program in pairs(per_plan) do program:free() end
    end
    heap:free()
    return values
end

return {
    run = run,
    compile = compile,
    build_plans = build_plans,
    assemble_bank = assemble_bank,
    guest_to_host = guest_to_host,
    ffi = ffi,
}
