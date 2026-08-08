package.path = "./lua/?.lua;./lua/?/init.lua;./?.lua;./?/init.lua;" .. package.path

local Undump = require("experiments.lua55.undump55")
local Projection = require("experiments.copy_patch_cps.lua55_trace.opcode_00_10_projection")
local Native = require("experiments.copy_patch_cps.lua55_trace.opcode_00_08")
local Heap = require("experiments.copy_patch_cps.lua55_trace.guest_heap_v1")

local bank = dofile("target/copy_patch_cps/lua55_trace/opcode_00_08/bank.lua")
Native.extend_bank(bank, dofile("target/copy_patch_cps/lua55_trace/opcode_arith/bank.lua"))
Native.extend_bank(bank, dofile("target/copy_patch_cps/lua55_trace/opcode_compare/bank.lua"))
Native.extend_bank(bank, dofile("target/copy_patch_cps/lua55_trace/opcode_call/bank.lua"))
Native.extend_bank(bank, dofile("target/copy_patch_cps/lua55_trace/opcode_closure/bank.lua"))
Native.extend_bank(bank, dofile("target/copy_patch_cps/lua55_trace/opcode_tfor/bank.lua"))
Native.extend_bank(bank, dofile("target/copy_patch_cps/lua55_trace/opcode_close/bank.lua"))

local heap = Heap.GuestHeap.new(23)

local main = Undump.undump(require("experiments.copy_patch_cps.lua55_trace.opcode_tfor_fixture"))
local outer = assert(main.protos[1])
local it_proto = assert(outer.protos[1])
assert(outer.code[7].name == "TFORPREP" and outer.code[10].name == "TFORCALL")
assert(outer.code[11].name == "TFORLOOP")

local plan = Projection.project_call_plan(outer, heap)
assert(plan.calls[9] and plan.calls[9].kind == "tforcall")
-- blocks: [0,7) setup+TFORPREP, [7,9) body, [10,11) TFORLOOP,
-- [12,13) RETURN, [13,14) RETURN0
assert(#plan.blocks == 5)

local it_plan = Projection.project_call_plan(it_proto, heap)

local function frame_for(p)
    local slot_count = 0
    for _, block in ipairs(p.blocks) do
        slot_count = math.max(slot_count, #block.path.occurrences)
    end
    return Native.FrameOwner.new(p.proto.maxstacksize, slot_count, #p.proto.upvals, heap, true)
end

-- Host-mediated driver with the generic-for iterator dispatch.
local function invoke(plan, frame, lookup)
    local pc = 0
    local guard = 0
    while pc ~= nil and pc < plan.n do
        guard = guard + 1
        assert(guard < 100000, "driver did not converge")
        local call = plan.calls[pc]
        if call then
            assert(call.kind == "tforcall", "unhandled call kind")
            local callee_plan = lookup(plan, call)
            local cframe = frame_for(callee_plan)
            cframe.values[0] = frame.values[call.A + 1]   -- s
            cframe.values[1] = frame.values[call.A + 3]   -- var
            local ret = invoke(callee_plan, cframe, lookup)
            assert(ret.fired, "iterator did not return")
            for i = 0, call.C - 1 do
                frame.values[call.A + 3 + i] = cframe.values[ret.ret.A + i]
            end
            pc = pc + 1
        else
            local block = plan.blocks[plan.block_at[pc]]
            if not block then
                pc = pc + 1   -- skipped boundary (CLOSE)
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

local function iterator_lookup(_plan, _call) return it_plan end

-- The loop: v = 1..n, sum = n(n+1)/2.
for _, n in ipairs({ 1, 3, 5, 10 }) do
    local frame = frame_for(plan)
    frame:set_integer(0, n)
    local result = invoke(plan, frame, iterator_lookup)
    assert(result.fired, "function did not return")
    local expected = n * (n + 1) / 2
    assert(tonumber(frame:integer(2)) == expected,
        ("for n=%d: native=%s expected=%d"):format(n, tostring(frame:integer(2)), expected))
end

-- n = 0: the iterator immediately yields nil; the loop body never runs.
do
    local frame = frame_for(plan)
    frame:set_integer(0, 0)
    invoke(plan, frame, iterator_lookup)
    assert(tonumber(frame:integer(2)) == 0)
end

-- ---------------------------------------------------------------------
-- Differential oracle vs stock Lua 5.5.
local STOCK_LUA = "/tmp/lua-5.5.0/src/lua"
local stock = io.open(STOCK_LUA, "r")
if not stock then print("Lua55 tfor oracle: SKIPPED (stock lua missing)"); os.exit(0) end
stock:close()

local function stock_tfor(n)
    local script = table.concat({
        "local function f(n)",
        "  local function it(s, var) var = var + 1; if var > s then return nil end return var end",
        "  local sum = 0",
        "  for v in it, n, 0 do sum = sum + v end",
        "  return sum",
        "end",
        "print(f(", tostring(n), "))",
    }, "\n")
    local file = assert(io.open("target/copy_patch_cps/lua55_trace/oracle_tfor.lua", "wb"))
    file:write(script); file:close()
    local pipe = assert(io.popen(([[%s target/copy_patch_cps/lua55_trace/oracle_tfor.lua]]):format(STOCK_LUA), "r"))
    local out = pipe:read("*a"); pipe:close()
    return tonumber(out:match("(-?%d+)"))
end

for _, n in ipairs({ 1, 3, 5, 10, 0 }) do
    local frame = frame_for(plan)
    frame:set_integer(0, n)
    invoke(plan, frame, iterator_lookup)
    local native = tonumber(frame:integer(2))
    local expected = stock_tfor(n)
    assert(native == expected, ("tfor(%d): native=%d stock=%d"):format(n, native, expected))
end

heap:free()
print("Lua55 tfor: ok generic-for protocol + 5 differential cases native == stock")
