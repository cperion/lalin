package.path = "./lua/?.lua;./lua/?/init.lua;./?.lua;./?/init.lua;" .. package.path

local Undump = require("experiments.lua55.undump55")
local Projection = require("experiments.copy_patch_cps.lua55_trace.opcode_00_10_projection")
local Native = require("experiments.copy_patch_cps.lua55_trace.opcode_00_08")
local Heap = require("experiments.copy_patch_cps.lua55_trace.guest_heap_v1")
local ffi = Native.ffi

local bank = dofile("target/copy_patch_cps/lua55_trace/opcode_00_08/bank.lua")
Native.extend_bank(bank, dofile("target/copy_patch_cps/lua55_trace/opcode_arith/bank.lua"))
Native.extend_bank(bank, dofile("target/copy_patch_cps/lua55_trace/opcode_09_10/bank.lua"))
Native.extend_bank(bank, dofile("target/copy_patch_cps/lua55_trace/opcode_call/bank.lua"))
Native.extend_bank(bank, dofile("target/copy_patch_cps/lua55_trace/opcode_closure/bank.lua"))

local heap = Heap.GuestHeap.new(23)

-- ---------------------------------------------------------------------
-- Host-mediated invocation of a closure's own native plan. The callee
-- frame's upvalues are copied from the closure object's cells.
local function invoke_plan(plan, frame)
    local pc = 0
    while pc ~= nil and pc < plan.n do
        local call = plan.calls[pc]
        if call then
            error("nested calls not exercised by the closure fixtures")
        end
        local block = plan.blocks[plan.block_at[pc]]
        assert(block, "no block at pc " .. tostring(pc))
        local program = block.path:new_program(block.stop, bank)
        local status = program:execute(frame)
        program:free()
        assert(status == bank.status.completed, "callee block did not complete")
        local rpc = frame.frame.resume_pc
        if rpc == block.stop then
            pc = block.stop
        else
            local ret = plan.returns[rpc]
            if ret then
                return { fired = true, ret = ret, frame = frame }
            end
            pc = rpc
        end
    end
    return { fired = false }
end

-- Build the callee frame (value_count + upvalue_count from the plan's
-- proto), then copy the closure cells into the callee's upvalues.
local function callee_frame(plan, closure)
    local proto = plan.proto
    local frame = Native.FrameOwner.new(proto.maxstacksize,
        plan.blocks[1].path.occurrences and #plan.blocks[1].path.occurrences or 1,
        #proto.upvals, heap, true)
    for i = 0, tonumber(closure[0].upvalue_count) - 1 do
        local cell = closure[0].cells[i]
        local scratch = proto.maxstacksize - 1
        frame:open_upvalue(i, scratch, 1)
        if cell.state == 1 then
            -- OPEN: the cell points at the enclosing frame's register
            frame.values[scratch] = cell.open_slot[0]
        else
            frame.values[scratch] = cell.closed_value
        end
        frame:close_upvalue(i, 2)
    end
    return frame
end

-- ---------------------------------------------------------------------
-- clo0: CLOSURE + RETURN1 — a 0-upvalue closure; g(x) = x + 1.
local main0 = Undump.undump(require("experiments.copy_patch_cps.lua55_trace.opcode_closure_clo0_fixture"))
local outer0 = assert(main0.protos[1])
local g_proto0 = assert(outer0.protos[1])
assert(g_proto0.code[1].name == "ADDI" and #g_proto0.upvals == 0)
local outer_path0 = Projection.project(outer0, 0, 2, heap)
assert(#outer_path0.occurrences == 2)
local g_plan0 = Projection.project_call_plan(g_proto0, heap)

local function run_outer(path, stop)
    local program = path:new_program(stop, bank)
    local frame = Native.FrameOwner.new(outer0.maxstacksize, #path.occurrences,
        #outer0.upvals, heap, false)
    local status = program:execute(frame)
    program:free()
    assert(status == bank.status.completed)
    return frame
end

local refs = {}
for _ = 1, 3 do
    local frame = run_outer(outer_path0, 2)
    assert(frame:tag(0) == bank.tags.closure_value, "closure tag")
    local closure = ffi.cast("Lua55GuestClosureV1 *", tonumber(frame:reference(0)))
    assert(closure[0].header.kind == 4 and closure[0].upvalue_count == 0)
    assert(closure[0].proto_index == 0)
    local cref = tonumber(frame:reference(0))
    for _, seen in ipairs(refs) do assert(seen ~= cref, "closure reused") end
    refs[#refs + 1] = cref

    -- invoke g(10) natively through its own plan
    local cframe = callee_frame(g_plan0, closure)
    cframe:set_integer(0, 10)
    local result = invoke_plan(g_plan0, cframe)
    assert(result.fired and tonumber(cframe:integer(1)) == 11, "g(10)")
end
assert(#refs == 3)

-- ---------------------------------------------------------------------
-- clo1: MOVE + CLOSURE + RETURN — a 1-upvalue closure capturing 'offset'.
local main1 = Undump.undump(require("experiments.copy_patch_cps.lua55_trace.opcode_closure_clo1_fixture"))
local outer1 = assert(main1.protos[1])
local g_proto1 = assert(outer1.protos[1])
assert(g_proto1.code[1].name == "GETUPVAL" and #g_proto1.upvals == 1)
local desc0 = g_proto1.upvals[1]
assert(desc0.instack == 1, "offset is a local of the outer function")
local outer_path1 = Projection.project(outer1, 0, 4, heap)
assert(#outer_path1.occurrences == 4)
local g_plan1 = Projection.project_call_plan(g_proto1, heap)

for _, seed in ipairs({ 5, -3, 42 }) do
    local program = outer_path1:new_program(4, bank)
    local frame = Native.FrameOwner.new(outer1.maxstacksize, #outer_path1.occurrences,
        #outer1.upvals, heap, false)
    frame:set_integer(0, seed)
    assert(program:execute(frame) == bank.status.completed)
    program:free()
    -- the closure is R2; its upvalue 0 points at the outer's R1 (offset)
    local closure = ffi.cast("Lua55GuestClosureV1 *", tonumber(frame:reference(2)))
    assert(closure[0].upvalue_count == 1)
    local cell = closure[0].cells[0]
    assert(cell.state == 1 and tonumber(cell.open_slot[0].payload.integer) == seed,
        "closure upvalue captures offset")

    -- invoke g(10) natively: the callee frame gets the captured offset
    local cframe = callee_frame(g_plan1, closure)
    cframe:set_integer(0, 10)
    local result = invoke_plan(g_plan1, cframe)
    assert(result.fired and tonumber(cframe:integer(1)) == 10 + seed,
        ("g(10) with offset %d"):format(seed))
end

-- ---------------------------------------------------------------------
-- Differential oracle vs stock Lua 5.5.
local STOCK_LUA = "/tmp/lua-5.5.0/src/lua"
local stock = io.open(STOCK_LUA, "r")
if not stock then print("Lua55 closure oracle: SKIPPED (stock lua missing)"); os.exit(0) end
stock:close()

local function stock_closure(kind, args)
    local script
    if kind == "clo0" then
        script = "local function mk() local function g(x) return x + 1 end return g end"
            .. " print(mk()(" .. tostring(args) .. "))"
    else
        script = "local function mk(s) local offset = s local function g(x) return x + offset end return g end"
            .. " print(mk(" .. tostring(args) .. ")(10))"
    end
    local file = assert(io.open("target/copy_patch_cps/lua55_trace/oracle_closure.lua", "wb"))
    file:write(script); file:close()
    local pipe = assert(io.popen(([[%s target/copy_patch_cps/lua55_trace/oracle_closure.lua]]):format(STOCK_LUA), "r"))
    local out = pipe:read("*a"); pipe:close()
    return tonumber(out:match("(-?%d+)"))
end

do
    local frame = run_outer(outer_path0, 2)
    local closure = ffi.cast("Lua55GuestClosureV1 *", tonumber(frame:reference(0)))
    local cframe = callee_frame(g_plan0, closure)
    cframe:set_integer(0, 10)
    invoke_plan(g_plan0, cframe)
    local native = tonumber(cframe:integer(1))
    local expected = stock_closure("clo0", 10)
    assert(native == expected, ("clo0: native=%d stock=%d"):format(native, expected))
end
for _, seed in ipairs({ 5, -3, 42 }) do
    local program = outer_path1:new_program(4, bank)
    local frame = Native.FrameOwner.new(outer1.maxstacksize, #outer_path1.occurrences,
        #outer1.upvals, heap, false)
    frame:set_integer(0, seed)
    assert(program:execute(frame) == bank.status.completed)
    program:free()
    local closure = ffi.cast("Lua55GuestClosureV1 *", tonumber(frame:reference(2)))
    local cframe = callee_frame(g_plan1, closure)
    cframe:set_integer(0, 10)
    invoke_plan(g_plan1, cframe)
    local native = tonumber(cframe:integer(1))
    local expected = stock_closure("clo1", seed)
    assert(native == expected, ("clo1 seed=%d: native=%d stock=%d"):format(seed, native, expected))
end

heap:free()
print("Lua55 closure: ok bump-allocated closures + upvalue capture + 4 differential cases native == stock")
