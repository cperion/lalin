package.path = "./lua/?.lua;./lua/?/init.lua;./?.lua;./?/init.lua;" .. package.path

local Undump = require("experiments.lua55.undump55")
local Projection = require("experiments.copy_patch_cps.lua55_trace.opcode_00_10_projection")
local Native = require("experiments.copy_patch_cps.lua55_trace.opcode_00_08")
local Heap = require("experiments.copy_patch_cps.lua55_trace.guest_heap_v1")
local Iter = require("experiments.copy_patch_cps.lua55_trace.opcode_iter")
local ffi = Native.ffi

local bank = dofile("target/copy_patch_cps/lua55_trace/opcode_00_08/bank.lua")
Native.extend_bank(bank, dofile("target/copy_patch_cps/lua55_trace/opcode_string/bank.lua"))
Native.extend_bank(bank, dofile("target/copy_patch_cps/lua55_trace/opcode_arith/bank.lua"))
Native.extend_bank(bank, dofile("target/copy_patch_cps/lua55_trace/opcode_compare/bank.lua"))
Native.extend_bank(bank, dofile("target/copy_patch_cps/lua55_trace/opcode_call/bank.lua"))
Native.extend_bank(bank, dofile("target/copy_patch_cps/lua55_trace/opcode_generic_table/bank.lua"))
Native.extend_bank(bank, dofile("target/copy_patch_cps/lua55_trace/opcode_tfor/bank.lua"))
Native.extend_bank(bank, dofile("target/copy_patch_cps/lua55_trace/opcode_close/bank.lua"))
Native.extend_bank(bank, dofile("target/copy_patch_cps/lua55_trace/opcode_iter/bank.lua"))

local heap = Heap.GuestHeap.new(23)

-- The builtin markers + the environment table (_ENV).
local NEXT = heap:builtin_value(1)
local IPAIRS_ITER = heap:builtin_value(2)
local PAIRS = heap:builtin_value(3)
local IPAIRS = heap:builtin_value(4)
local env = heap:table(0, 4)
local function set_builtin_field(key_text, builtin_owner)
    local value = env:field_value(heap:short_string(key_text), true)
    value.tag, value.reserved = 8, 0
    value.payload.reference = builtin_owner.reference
    env.object[0].barrier_count = env.object[0].barrier_count + 1
    env.heap_owner.heap[0].barrier_epoch = env.heap_owner.heap[0].barrier_epoch + 1
end
set_builtin_field("pairs", PAIRS)
set_builtin_field("ipairs", IPAIRS)
set_builtin_field("next", NEXT)

local function builtin_id(value)
    if tonumber(value.tag) ~= bank.tags.closure_value then return nil end
    local ref = tonumber(value.payload.reference)
    if not ref or ref == 0 then return nil end
    local obj = ffi.cast("Lua55GuestObjectHeaderV1 *", ref)
    if tonumber(obj[0].kind) ~= 5 then return nil end
    return tonumber(ffi.cast("Lua55GuestBuiltinV1 *", ref)[0].builtin_id)
end

local function set_closure(frame, index, reference)
    frame.values[index].tag, frame.values[index].reserved = 8, 0
    frame.values[index].payload.reference = reference
end

-- The native iterator programs (fixed registers R0=t, R1=k, R2=key, R3=value).
local next_program = Native.Program.new({ Iter.NextIterOccurrence.new(0) }, 4, 1, bank, 16384, 0, heap)
local ipairs_program = Native.Program.new({ Iter.IPairsIterOccurrence.new(0) }, 4, 1, bank, 16384, 0, heap)

local function native_next(t_ref, k_frame_value)
    local f = next_program:new_frame()
    f:set_table(0, t_ref)
    f.values[1] = k_frame_value
    assert(next_program:execute(f) == bank.status.completed)
    local result = { key = f.values[2], value = f.values[3] }
    return result
end

local function native_ipairs(t_ref, i)
    local f = ipairs_program:new_frame()
    f:set_table(0, t_ref)
    f:set_integer(1, i)
    assert(ipairs_program:execute(f) == bank.status.completed)
    return { key = f.values[2], value = f.values[3] }
end

-- ---------------------------------------------------------------------
-- The generic-for driver with the builtin dispatch.
local function frame_for(p)
    local slot_count = 0
    for _, block in ipairs(p.blocks) do
        slot_count = math.max(slot_count, #block.path.occurrences)
    end
    return Native.FrameOwner.new(p.proto.maxstacksize, slot_count, #p.proto.upvals, heap, true)
end

local function invoke(plan, frame, env_owner)
    local pc = 0
    local guard = 0
    while pc ~= nil and pc < plan.n do
        guard = guard + 1
        assert(guard < 100000, "driver did not converge")
        local call = plan.calls[pc]
        if call then
            local callee = builtin_id(frame.values[call.A])
            if call.kind == "tforcall" then
                local iter = builtin_id(frame.values[call.A])
                if iter == 1 then
                    local nf = next_program:new_frame()
                    nf.values[0] = frame.values[call.A + 1]   -- s (t)
                    nf.values[1] = frame.values[call.A + 3]   -- var (k)
                    assert(next_program:execute(nf) == bank.status.completed)
                    for i = 0, call.C - 1 do
                        frame.values[call.A + 3 + i] = nf.values[2 + i]
                    end
                elseif iter == 2 then
                    local nf = ipairs_program:new_frame()
                    nf.values[0] = frame.values[call.A + 1]   -- s (t)
                    nf.values[1] = frame.values[call.A + 3]   -- var (i)
                    assert(ipairs_program:execute(nf) == bank.status.completed)
                    for i = 0, call.C - 1 do
                        frame.values[call.A + 3 + i] = nf.values[2 + i]
                    end
                else
                    error("unhandled iterator")
                end
                pc = pc + 1
            elseif callee == 3 then   -- pairs(t) -> (next, t, nil)
                set_closure(frame, call.A, NEXT.reference)
                frame:set_nil(call.A + 2)
                pc = pc + 1
            elseif callee == 4 then   -- ipairs(t) -> (ipairs_iter, t, 0)
                set_closure(frame, call.A, IPAIRS_ITER.reference)
                frame:set_integer(call.A + 2, 0)
                pc = pc + 1
            elseif callee == 1 then   -- next(t, k) -> the native next
                local nf = next_program:new_frame()
                nf.values[0] = frame.values[call.A + 1]
                nf.values[1] = frame.values[call.A + 2]
                assert(next_program:execute(nf) == bank.status.completed)
                frame.values[call.A] = nf.values[2]
                frame.values[call.A + 1] = nf.values[3]
                pc = pc + 1
            else
                error("unhandled call kind")
            end
        else
            local block = plan.blocks[plan.block_at[pc]]
            if not block then
                pc = pc + 1
            else
                local program = block.path:new_program(block.stop, bank)
                local status = program:execute(frame)
                program:free()
                assert(status == bank.status.completed, "block did not complete")
                local rpc = frame.frame.resume_pc
                if rpc == block.stop then
                    pc = block.stop
                else
                    local ret = plan.returns[rpc]
                    if ret then return { fired = true, ret = ret, frame = frame } end
                    pc = rpc
                end
            end
        end
    end
    return { fired = false }
end

local function load(name)
    local main = Undump.undump(require("experiments.copy_patch_cps.lua55_trace." .. name))
    local proto = assert(main.protos[1])
    local plan = Projection.project_call_plan(proto, heap)
    return proto, plan
end

local pairs_proto, pairs_plan = load("opcode_iter_pairs_fixture")
local ipairs_proto, ipairs_plan = load("opcode_iter_ipairs_fixture")

local function run_plan(plan, proto, t_owner)
    local frame = frame_for(plan)
    -- the _ENV upvalue (index 0) is closed with the environment table
    frame:open_upvalue(0, proto.maxstacksize - 1, 1)
    frame:set_table(proto.maxstacksize - 1, env)
    frame:close_upvalue(0, 2)
    frame:set_table(0, t_owner)
    local result = invoke(plan, frame, env)
    assert(result.fired, "function did not return")
    return frame
end

-- pairs: sum the values over an array + field table.
do
    local t = heap:table(4, 2)
    t:set_array_integer(1, 10):set_array_integer(2, 20):set_array_integer(3, 30)
    t:set_field_integer(heap:short_string("a"), 5)
    t:set_field_integer(heap:short_string("b"), 7)
    local frame = run_plan(pairs_plan, pairs_proto, t)
    assert(tonumber(frame:integer(1)) == 72, ("pairs sum: %s"):format(tostring(frame:integer(1))))
end
do
    local t = heap:table(2, 0)
    t:set_array_integer(1, 2):set_array_integer(2, 3)
    local frame = run_plan(pairs_plan, pairs_proto, t)
    assert(tonumber(frame:integer(1)) == 5)
end

-- ipairs: sum the array prefix (stops at the first nil).
do
    local t = heap:table(4, 0)
    t:set_array_integer(1, 1):set_array_integer(2, 2):set_array_integer(3, 3)
    t:set_array_integer(4, 4)
    local frame = run_plan(ipairs_plan, ipairs_proto, t)
    assert(tonumber(frame:integer(1)) == 10)
end
do
    local t = heap:table(4, 0)
    t:set_array_integer(1, 1):set_array_integer(2, 2)
    t:set_array_nil(3):set_array_integer(4, 4)
    local frame = run_plan(ipairs_plan, ipairs_proto, t)
    assert(tonumber(frame:integer(1)) == 3)   -- stops at index 3 (nil)
end

-- ---------------------------------------------------------------------
-- Native next leaves: walk the array then the fields, then nil.
do
    local t = heap:table(3, 2)
    t:set_array_integer(1, 10):set_array_integer(2, 20)
    t:set_field_integer(heap:short_string("x"), 1)
    local nil_frame = ffi.new("Lua55ValueV1")
    nil_frame.tag = 0
    local r = native_next(t, nil_frame)
    assert(tonumber(r.key.payload.integer) == 1 and tonumber(r.value.payload.integer) == 10)
    local k = r.key
    r = native_next(t, k)
    assert(tonumber(r.key.payload.integer) == 2 and tonumber(r.value.payload.integer) == 20)
    k = r.key
    r = native_next(t, k)
    assert(tonumber(r.key.tag) == 5 and tonumber(r.value.payload.integer) == 1)  -- the "x" field
    k = r.key
    r = native_next(t, k)
    assert(tonumber(r.key.tag) == 0)   -- exhausted
end

-- Native ipairs leaf.
do
    local t = heap:table(3, 0)
    t:set_array_integer(1, 5):set_array_integer(2, 6)
    local r = native_ipairs(t, 0)
    assert(tonumber(r.key.payload.integer) == 1 and tonumber(r.value.payload.integer) == 5)
    r = native_ipairs(t, 1)
    assert(tonumber(r.key.payload.integer) == 2 and tonumber(r.value.payload.integer) == 6)
    r = native_ipairs(t, 2)
    assert(tonumber(r.key.tag) == 0)
end

-- ---------------------------------------------------------------------
-- Differential oracle vs stock Lua 5.5.
local STOCK_LUA = "/tmp/lua-5.5.0/src/lua"
local stock = io.open(STOCK_LUA, "r")
if not stock then print("Lua55 iter oracle: SKIPPED (stock lua missing)"); os.exit(0) end
stock:close()

local function stock_sum(kind, body)
    local script = table.concat({
        "local function f(t) local sum = 0",
        "  for k, v in ", kind, "(t) do sum = sum + v end",
        "  return sum",
        "end",
        "local t = ", body,
        "print(f(t))",
    }, "\n")
    local file = assert(io.open("target/copy_patch_cps/lua55_trace/oracle_iter.lua", "wb"))
    file:write(script); file:close()
    local pipe = assert(io.popen(([[%s target/copy_patch_cps/lua55_trace/oracle_iter.lua]]):format(STOCK_LUA), "r"))
    local out = pipe:read("*a"); pipe:close()
    return tonumber(out:match("(-?%d+)"))
end

do
    local t = heap:table(4, 2)
    t:set_array_integer(1, 10):set_array_integer(2, 20):set_array_integer(3, 30)
    t:set_field_integer(heap:short_string("a"), 5)
    t:set_field_integer(heap:short_string("b"), 7)
    local frame = run_plan(pairs_plan, pairs_proto, t)
    local native = tonumber(frame:integer(1))
    local expected = stock_sum("pairs", "{10, 20, 30, a = 5, b = 7}")
    assert(native == expected, ("pairs: native=%d stock=%d"):format(native, expected))
end
do
    local t = heap:table(4, 0)
    t:set_array_integer(1, 1):set_array_integer(2, 2):set_array_integer(3, 3):set_array_integer(4, 4)
    local frame = run_plan(ipairs_plan, ipairs_proto, t)
    local native = tonumber(frame:integer(1))
    local expected = stock_sum("ipairs", "{1, 2, 3, 4}")
    assert(native == expected, ("ipairs: native=%d stock=%d"):format(native, expected))
end

next_program:free()
ipairs_program:free()
heap:free()
print("Lua55 iter: ok native pairs/ipairs/next + 2 differential cases native == stock")
