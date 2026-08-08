package.path = "./lua/?.lua;./lua/?/init.lua;./?.lua;./?/init.lua;" .. package.path

local Undump = require("experiments.lua55.undump55")
local Projection = require("experiments.copy_patch_cps.lua55_trace.opcode_00_10_projection")
local Native = require("experiments.copy_patch_cps.lua55_trace.opcode_00_08")

local function load_proto(name, nested)
    local main = Undump.undump(require("experiments.copy_patch_cps.lua55_trace." .. name))
    if nested then return assert(main.protos[1].protos[1]) end
    return assert(main.protos[1])
end

local caller_proto = load_proto("opcode_call_caller_fixture")
local callee_proto = load_proto("opcode_call_callee_fixture")
assert(caller_proto.code[4].name == "CALL")
assert(callee_proto.code[1].name == "ADD" and callee_proto.code[3].name == "RETURN1")

local bank = dofile("target/copy_patch_cps/lua55_trace/opcode_00_08/bank.lua")
Native.extend_bank(bank, dofile("target/copy_patch_cps/lua55_trace/opcode_arith/bank.lua"))
Native.extend_bank(bank, dofile("target/copy_patch_cps/lua55_trace/opcode_compare/bank.lua"))
Native.extend_bank(bank, dofile("target/copy_patch_cps/lua55_trace/opcode_09_10/bank.lua"))
Native.extend_bank(bank, dofile("target/copy_patch_cps/lua55_trace/opcode_call/bank.lua"))

-- ---------------------------------------------------------------------
-- Block-based call plans.
local caller_plan = Projection.project_call_plan(caller_proto)
assert(#caller_plan.blocks == 3)
assert(caller_plan.blocks[1].start == 0 and caller_plan.blocks[1].stop == 3)
assert(caller_plan.blocks[2].start == 4 and caller_plan.blocks[2].stop == 7)
assert(caller_plan.blocks[3].start == 7 and caller_plan.blocks[3].stop == 8)
local caller_call = caller_plan.calls[3]
assert(caller_call and caller_call.A == 2 and caller_call.B == 3 and caller_call.C == 2)
assert(caller_plan.returns[6] and caller_plan.returns[6].A == 3 and caller_plan.returns[6].B == 2)

local callee_plan = Projection.project_call_plan(callee_proto)
assert(#callee_plan.blocks == 2)
assert(callee_plan.blocks[1].start == 0 and callee_plan.blocks[1].stop == 3)
assert(callee_plan.returns[2] and callee_plan.returns[2].A == 2 and callee_plan.returns[2].B == 2)

-- ---------------------------------------------------------------------
-- Host-mediated call driver over the block graph. Runs the block at each
-- pc natively; resume_pc routes to the next block start, a call boundary
-- (dispatch, copying args/results across the boundary), or a return
-- (copy results into the caller's destination). TAILCALL passes the outer
-- destination through, so the tail callee's results land directly in the
-- ultimate caller's registers.
local function frame_for(plan)
    -- one frame per function invocation, sized for the largest block
    local slot_count = 0
    for _, block in ipairs(plan.blocks) do
        slot_count = math.max(slot_count, #block.path.occurrences)
    end
    local frame = Native.FrameOwner.new(plan.proto.maxstacksize, slot_count, #plan.proto.upvals, nil)
    -- recursion fixtures carry one self-reference upvalue; close it with a
    -- dummy reference (the host binds the callee; the native GETUPVAL just
    -- moves the payload).
    if plan.proto.upvals and #plan.proto.upvals > 0 then
        local reg = plan.proto.maxstacksize - 1
        frame:set_integer(reg, 0x7f000001)
        frame:open_upvalue(0, reg, 1)
        frame:close_upvalue(0, 2)
    end
    return frame
end

local function invoke(plan, frame, lookup, dest)
    local pc = 0
    local guard = 0
    while pc ~= nil and pc < plan.n do
        guard = guard + 1
        assert(guard < 100000, "call driver did not converge")
        local call = plan.calls[pc]
        if call then
            local callee_plan = lookup(plan, call)
            local cframe = frame_for(callee_plan)
            for i = 1, call.B - 1 do
                cframe.values[i - 1] = frame.values[call.A + i]
            end
            local expected = call.C - 1
            local dest2 = { frame = frame, base = call.A, count = expected >= 0 and expected or nil }
            if call.tail then dest2 = dest end
            local result = invoke(callee_plan, cframe, lookup, dest2)
            if call.tail then return result end
            pc = pc + 1
        else
            local block = plan.blocks[plan.block_at[pc]]
            assert(block, "no block at pc " .. tostring(pc))
            local program = block.path:new_program(block.stop, bank)
            local status = program:execute(frame)
            program:free()
            assert(status == bank.status.completed, "block did not complete at pc " .. pc)
            local rpc = frame.frame.resume_pc
            if rpc == block.stop then
                pc = block.stop
            else
                local ret = plan.returns[rpc]
                if ret then
                    local nres = ret.B - 1
                    if nres < 0 then nres = 0 end
                    if dest then
                        local count = dest.count or nres
                        for i = 0, math.min(count, nres) - 1 do
                            dest.frame.values[dest.base + i] = frame.values[ret.A + i]
                        end
                    end
                    return { fired = true, ret = ret, frame = frame }
                end
                pc = rpc
            end
        end
    end
    return { fired = false }
end

-- ---------------------------------------------------------------------
-- caller(f, x) = f(x, 1) + 2; callee add(a, b) = a + b.
local add_plan = callee_plan
local function simple_lookup(_plan, _call) return add_plan end

for _, x in ipairs({ 0, 1, 5, -3, 100 }) do
    local frame = frame_for(caller_plan)
    frame:set_integer(0, 0):set_integer(1, x)
    local result = invoke(caller_plan, frame, simple_lookup, nil)
    assert(result.fired and tonumber(frame:integer(3)) == x + 3,
        ("caller(add, %d) native=%s"):format(x, tostring(frame:integer(3))))
end

do
    local frame = frame_for(caller_plan)
    frame:set_integer(0, 0):set_float(1, 2.5)
    invoke(caller_plan, frame, simple_lookup, nil)
    assert(frame:tag(3) == bank.tags.floating and frame:floating(3) == 5.5)
end

-- ---------------------------------------------------------------------
local function lua_fact(n) if n <= 1 then return 1 else return n * lua_fact(n - 1) end end

-- Recursion: fact(n) = n * fact(n-1), base 1. Multi-return + branches
-- inside the block graph.
local fact_proto = load_proto("opcode_call_fact_fixture", true)
local fact_plan = Projection.project_call_plan(fact_proto)
assert(#fact_plan.blocks == 6)   -- [0,2) [2,4) [4,5) [5,8) call [9,12) [12,13)
assert(fact_plan.calls[8] and fact_plan.calls[8].A == 1)
assert(fact_plan.returns[3] and fact_plan.returns[11])
local function fact_lookup(_plan, _call) return fact_plan end

for _, n in ipairs({ 1, 2, 3, 5, 10 }) do
    local frame = frame_for(fact_plan)
    frame:set_integer(0, n)
    local result = invoke(fact_plan, frame, fact_lookup, nil)
    assert(result.fired, "fact did not return")
    assert(tonumber(frame:integer(1)) == lua_fact(n),
        ("fact(%d) native=%s"):format(n, tostring(frame:integer(1))))
end

-- ---------------------------------------------------------------------
-- Tail call: trec(n, acc) = trec(n-1, acc*n), base acc. The TAILCALL
-- passes the destination through; the final frame holds the result.
local trec_proto = load_proto("opcode_call_trec_fixture", true)
local trec_plan = Projection.project_call_plan(trec_proto)
assert(trec_plan.calls[9] and trec_plan.calls[9].tail)
local function trec_lookup(_plan, _call) return trec_plan end

for _, n in ipairs({ 1, 2, 5, 10 }) do
    local frame = frame_for(trec_plan)
    frame:set_integer(0, n):set_integer(1, 1)
    local result = invoke(trec_plan, frame, trec_lookup, nil)
    assert(result.fired, "trec did not return")
    assert(tonumber(result.frame:integer(1)) == lua_fact(n),
        ("trec(%d) native=%s"):format(n, tostring(result.frame:integer(1))))
end

-- ---------------------------------------------------------------------
-- Differential oracle vs stock Lua 5.5.
local STOCK_LUA = "/tmp/lua-5.5.0/src/lua"
local stock = io.open(STOCK_LUA, "r")
if not stock then print("Lua55 call oracle: SKIPPED (stock lua missing)"); os.exit(0) end
stock:close()

local function stock_eval(body)
    local script = table.concat({
        "local function fact(n) if n <= 1 then return 1 else return n * fact(n - 1) end end",
        "local function trec(n, acc) if n == 0 then return acc else return trec(n - 1, acc * n) end end",
        "local function add(a, b) return a + b end",
        "local function caller(f, x) local r = f(x, 1) return r + 2 end",
        body,
    }, "\n")
    local file = assert(io.open("target/copy_patch_cps/lua55_trace/oracle_call.lua", "wb"))
    file:write(script); file:close()
    local pipe = assert(io.popen(([[%s target/copy_patch_cps/lua55_trace/oracle_call.lua]]):format(STOCK_LUA), "r"))
    local out = pipe:read("*a"); pipe:close()
    return tonumber(out:match("(-?%d+)"))
end

local cases = 0
for _, x in ipairs({ 0, 1, 2, 7, -3, 42 }) do
    local frame = frame_for(caller_plan)
    frame:set_integer(0, 0):set_integer(1, x)
    invoke(caller_plan, frame, simple_lookup, nil)
    local native = tonumber(frame:integer(3))
    local expected = stock_eval(("print(caller(add, %d))"):format(x))
    assert(native == expected, ("caller(add, %d): native=%d stock=%d"):format(x, native, expected))
    cases = cases + 1
end
for _, n in ipairs({ 1, 2, 5, 10 }) do
    local frame = frame_for(fact_plan)
    frame:set_integer(0, n)
    invoke(fact_plan, frame, fact_lookup, nil)
    local native = tonumber(frame:integer(1))
    local expected = stock_eval(("print(fact(%d))"):format(n))
    assert(native == expected, ("fact(%d): native=%d stock=%d"):format(n, native, expected))
    cases = cases + 1
end
for _, n in ipairs({ 1, 2, 5, 10 }) do
    local frame = frame_for(trec_plan)
    frame:set_integer(0, n):set_integer(1, 1)
    local result = invoke(trec_plan, frame, trec_lookup, nil)
    local native = tonumber(result.frame:integer(1))
    local expected = stock_eval(("print(trec(%d, 1))"):format(n))
    assert(native == expected, ("trec(%d): native=%d stock=%d"):format(n, native, expected))
    cases = cases + 1
end

print(("Lua55 call: ok block-graph driver, %d blocks, %d differential cases native == stock"):format(
    #caller_plan.blocks + #callee_plan.blocks + #fact_plan.blocks + #trec_plan.blocks, cases))
