package.path = "./lua/?.lua;./lua/?/init.lua;./?.lua;./?/init.lua;" .. package.path

-- Performance surface: native Lua 5.5 trace residuals vs stock Lua 5.5.
-- Usage: luajit perf_bench.lua [jit|joff] [iterations]
-- Reports ns per executed path (24-opcode fixture / table ops / string ops)
-- and ns per guest iteration (fused numeric loop).

local mode = arg[1] or "jit"
local iterations = tonumber(arg[2]) or 200000
if mode == "joff" then require("jit").off() end

local Undump = require("experiments.lua55.undump55")
local Projection = require("experiments.copy_patch_cps.lua55_trace.opcode_00_10_projection")
local Native = require("experiments.copy_patch_cps.lua55_trace.opcode_00_08")
local Heap = require("experiments.copy_patch_cps.lua55_trace.guest_heap_v1")
local Runtime = require("experiments.copy_patch_cps.lua55_trace.recorder")
local Emitter = require("experiments.copy_patch_cps.lua55_trace.emitter")
local T = Runtime.Trace
local ffi = Native.ffi

local function base_bank() return dofile("target/copy_patch_cps/lua55_trace/opcode_00_08/bank.lua") end
local bank9 = dofile("target/copy_patch_cps/lua55_trace/opcode_09_10/bank.lua")
local bank_string = dofile("target/copy_patch_cps/lua55_trace/opcode_string/bank.lua")
local bank_table = dofile("target/copy_patch_cps/lua55_trace/opcode_table/bank.lua")
local bank_unary = dofile("target/copy_patch_cps/lua55_trace/opcode_unary/bank.lua")
local bank_jmp = dofile("target/copy_patch_cps/lua55_trace/opcode_jmp/bank.lua")
local bank_loop = dofile("target/copy_patch_cps/lua55_trace/bank.lua")

local function median(values)
    table.sort(values)
    return values[math.floor((#values + 1) / 2)]
end

local function measure_ns(action)
    local samples = {}
    for sample = 1, 7 do
        local started = os.clock()
        local result = action()
        assert(result ~= nil)
        samples[sample] = os.clock() - started
    end
    return median(samples)
end

local results = {}

-- 1. Opcode 0-10 path (24-opcode fixture: moves, loads, 5 upvalue writes/reads)
do
    local bytes = require("experiments.copy_patch_cps.lua55_trace.opcode_00_10_fixture")
    local main = Undump.undump(bytes)
    local path = assert(Projection.project(main.protos[1], 0, 24))
    local bank = base_bank()
    Native.extend_bank(bank, bank9)
    local program = path:new_program(24, bank)
    local frame = program:new_frame()
    frame:set_integer(0, 12)
    for index = 0, 4 do
        local register = 8 + index
        if index < 2 then frame:set_integer(register, 0)
        elseif index == 2 then frame:set_false(register)
        elseif index == 3 then frame:set_true(register)
        else frame:set_nil(register) end
        frame:open_upvalue(index, register, 99 + index):close_upvalue(index, 100 + index)
    end
    assert(program:execute(frame) == bank.status.completed)  -- install once
    local entry, raw = program.residual.entry, frame.frame
    local function direct()
        for call = 1, iterations do
            frame.values[0].payload.integer = call
            entry(raw)
        end
        return frame.values[1].payload.integer
    end
    local function wrapped()
        for call = 1, iterations do
            frame:set_integer(0, call)
            assert(program:execute(frame) == bank.status.completed)
        end
        return frame.values[1].payload.integer
    end
    results.opcode_direct = measure_ns(direct) * 1e9 / iterations
    results.opcode_wrapped = measure_ns(wrapped) * 1e9 / iterations
    program:free()
end

-- 2. Table path (GETI + GETFIELD + SETI + SETFIELD + 2 MOVE)
do
    local heap = Heap.GuestHeap.new(41)
    local bytes = require("experiments.copy_patch_cps.lua55_trace.opcode_table_fixture")
    local main = Undump.undump(bytes)
    local path = Projection.project(main.protos[1], 0, 6, heap)
    local bank = base_bank()
    Native.extend_bank(bank, bank_table)
    Native.extend_bank(bank, bank_string)
    local table_owner = heap:table(2, 2)
    table_owner:set_array_integer(1, 41)
    table_owner:set_field_integer(heap:short_string("field"), 52)
    local program = path:new_program(6, bank)
    local frame = program:new_frame():set_table(0, table_owner):set_integer(1, 99)
    assert(program:execute(frame) == bank.status.completed)
    local entry, raw = program.residual.entry, frame.frame
    local function run()
        for call = 1, iterations do
            frame.values[1].payload.integer = call
            entry(raw)
        end
        return frame.values[2].payload.integer
    end
    results.table = measure_ns(run) * 1e9 / iterations
    program:free()
    heap:free()
end

    local bank = base_bank()
    Native.extend_bank(bank, bank_string)
do
    local heap = Heap.GuestHeap.new(43)
    local bytes = require("experiments.copy_patch_cps.lua55_trace.opcode_string_fixture")
    local main = Undump.undump(bytes)
    local path = Projection.project(main.protos[1], 0, 6, heap)
    local bank = base_bank()
    Native.extend_bank(bank, bank_string)
    local program = path:new_program(6, bank)
    local frame = program:new_frame()
    assert(program:execute(frame) == bank.status.completed)
    local entry, raw = program.residual.entry, frame.frame
    local function run()
        for _ = 1, iterations do entry(raw) end
        return frame.values[2].payload.reference
    end
    results.string = measure_ns(run) * 1e9 / iterations
    program:free()
    heap:free()
end

-- 2c. Unary path (UNM + BNOT + NOT + LEN(str) + LEN(table) + 5 MOVE)
do
    local heap = Heap.GuestHeap.new(47)
    local bytes = require("experiments.copy_patch_cps.lua55_trace.opcode_unary_fixture")
    local main = Undump.undump(bytes)
    local path = Projection.project(main.protos[1], 0, 10, heap)
    local bank = base_bank()
    Native.extend_bank(bank, bank_unary)
    local table_owner = heap:table(4, 0)
    table_owner:set_array_integer(1, 10):set_array_integer(2, 20):set_array_integer(3, 30)
    local str_owner = heap:short_string("hello")
    local program = path:new_program(10, bank)
    local frame = program:new_frame():set_integer(0, 7)
        :set_short_string(1, str_owner):set_table(2, table_owner)
    assert(program:execute(frame) == bank.status.completed)
    local entry, raw = program.residual.entry, frame.frame
    local function run()
        for call = 1, iterations do
            frame.values[0].payload.integer = call
            entry(raw)
        end
        return frame.values[3].payload.integer
    end
    results.unary = measure_ns(run) * 1e9 / iterations
    program:free()
    heap:free()
end

-- 3b. Comparison path (LT+LE+EQ(k1)+EQ(k0) with owned JMPs, int operands)
do
    local bytes = require("experiments.copy_patch_cps.lua55_trace.opcode_compare_fixture")
    local main = Undump.undump(bytes)
    local path = Projection.project(main.protos[1], 0, 16)
    local bank = base_bank()
    Native.extend_bank(bank, dofile("target/copy_patch_cps/lua55_trace/opcode_compare/bank.lua"))
    local program = path:new_program(16, bank)
    local frame = program:new_frame():set_integer(0, 5):set_integer(1, 3)
    assert(program:execute(frame) == bank.status.completed)
    local entry, raw = program.residual.entry, frame.frame
    local function run()
        for call = 1, iterations do
            frame.values[0].payload.integer = call
            frame.values[1].payload.integer = call - 2
            entry(raw)
        end
        return frame.values[2].payload.integer
    end
    results.compare = measure_ns(run) * 1e9 / iterations
    program:free()
end

-- 3c. Arithmetic path (ADD SUB MUL IDIV MOD DIV BAND BOR BXOR + shifts + ADDI + MULK)
do
    local bytes = require("experiments.copy_patch_cps.lua55_trace.opcode_arith_fixture")
    local main = Undump.undump(bytes)
    local path = Projection.project(main.protos[1], 0, 28)
    local bank = base_bank()
    Native.extend_bank(bank, dofile("target/copy_patch_cps/lua55_trace/opcode_arith/bank.lua"))
    local program = path:new_program(28, bank)
    local frame = program:new_frame():set_integer(0, 7):set_integer(1, 3)
    assert(program:execute(frame) == bank.status.completed)
    local entry, raw = program.residual.entry, frame.frame
    local function run()
        for call = 1, iterations do
            frame.values[0].payload.integer = call + 2
            frame.values[1].payload.integer = call
            entry(raw)
        end
        return frame.values[2].payload.integer
    end
    results.arith = measure_ns(run) * 1e9 / iterations
    program:free()
end

-- 3e. While loop path (LT + ADDI + back-edge JMP), ns per iteration.
-- The host drives the loop: each execute is one native pass; the back-edge
-- JMP returns COMPLETED at the LT pc and the driver re-enters.
do
    local bytes = require("experiments.copy_patch_cps.lua55_trace.opcode_jmp_fixture")
    local main = Undump.undump(bytes)
    local path = Projection.project(main.protos[1], 1, 6)
    local bank = base_bank()
    Native.extend_bank(bank, dofile("target/copy_patch_cps/lua55_trace/opcode_arith/bank.lua"))
    Native.extend_bank(bank, dofile("target/copy_patch_cps/lua55_trace/opcode_compare/bank.lua"))
    Native.extend_bank(bank, dofile("target/copy_patch_cps/lua55_trace/opcode_jmp/bank.lua"))
    local exit_pc = 6
    local program = path:new_program(exit_pc, bank)
    local frame = program:new_frame():set_integer(0, 1):set_integer(1, 0)
    assert(program:execute(frame) == bank.status.completed)
    local entry, raw = program.residual.entry, frame.frame
    local function run()
        for call = 1, iterations do
            frame.values[0].payload.integer = 1   -- fixed limit: one pass each
            frame.values[1].payload.integer = 0
            -- one native pass per iteration: LT not-taken, ADDI, JMP back-edge
            entry(raw)
        end
        return frame.values[1].payload.integer
    end
    results.while_loop = measure_ns(run) * 1e9 / iterations
    program:free()
end

-- 3f. Pow path (POW + POWK + 2 MOVE), ns per path.
do
    local bytes = require("experiments.copy_patch_cps.lua55_trace.opcode_pow_fixture")
    local main = Undump.undump(bytes)
    local path = Projection.project(main.protos[1], 0, 6)
    local bank = base_bank()
    Native.extend_bank(bank, dofile("target/copy_patch_cps/lua55_trace/opcode_pow/bank.lua"))
    local program = path:new_program(6, bank)
    local frame = program:new_frame():set_integer(0, 2):set_integer(1, 3)
    assert(program:execute(frame) == bank.status.completed)
    local entry, raw = program.residual.entry, frame.frame
    local function run()
        for call = 1, iterations do
            frame.values[0].payload.integer = call
            frame.values[1].payload.integer = 3
            entry(raw)
        end
        return frame.values[2].payload.integer
    end
    results.pow = measure_ns(run) * 1e9 / iterations
    program:free()
end

-- 4. Fused numeric loop (ns per guest iteration)
do
    local count = 1000
    local function reg(i) return T.RegisterIdentity(i) end
    local function pc(v) return T.InstructionIdentity(v) end
    local sum, limit, step, index = reg(0), reg(1), reg(2), reg(3)
    local plan = T.IntegerAddForLoopPlan(
        4, pc(10), pc(10), pc(11), pc(11), sum, index, limit, step, 12)
    local frame = Runtime.FrameOwner.new(4)
        :set_integer(0, 0):set_integer(1, count):set_integer(2, 1):set_integer(3, 1)
    local recorder = Runtime.Recorder.new_plan(
        plan, frame, Emitter.NativeArena.new(bank_loop, 4096))
    assert(T.TraceRecorded:is(recorder:record_plan()))
    local entry, raw = recorder.native.entry, frame.frame
    local function run()
        for call = 1, iterations do
            frame.values[0].payload.integer = 0
            frame.values[3].payload.integer = 1
            entry(raw)
        end
        return frame.values[0].payload.integer
    end
    results.loop_native = measure_ns(run) * 1e9 / (iterations * count)
    recorder.native:free()
end

-- Stock Lua 5.5 reference (separate process, same workloads)
local stock_script = [[
local iterations = %d
local count = 1000
local function median(t) table.sort(t); return t[math.floor((#t + 1) / 2)] end
local function measure(action)
  local samples = {}
  for s = 1, 7 do
    local start = os.clock()
    local r = action()
    samples[s] = os.clock() - start
  end
  return median(samples)
end

local u1, u2, u3, u4, u5 = 0, 0, false, true, nil
local function opcode_path(x)
  local m = x
  local i = 42
  local f = 3.0
  local k = 2.5
  local a = false
  local b = true
  local c = nil
  u1 = m; m = u1
  u2 = k; k = u2
  u3 = a; a = u3
  u4 = b; b = u4
  u5 = c; c = u5
  return m, i, f, k, a, b, c
end
local opcode_ns = measure(function()
  for call = 1, iterations do opcode_path(call) end
  return 1
end) * 1e9 / iterations

local function table_path(t, v)
  local a = t[1]
  local b = t.field
  t[2] = v
  t.other = v
  return a, b
end
local t = { [1] = 41, field = 52 }
local table_ns = measure(function()
  for call = 1, iterations do table_path(t, call) end
  return t[2]
end) * 1e9 / iterations

local function string_path()
  local short = "field"
  local long = "this string is deliberately longer than forty bytes for Lua 5.5"
  local a = short
  local b = long
  return a, b
end
local string_ns = measure(function()
  for _ = 1, iterations do string_path() end
  return 1
end) * 1e9 / iterations

local function arith_path(a, b)
  local r1 = a + b
  local r2 = a - b
  local r3 = a * b
  local r4 = a // b
  local r5 = a % b
  local r6 = a / b
  local r7 = a & b
  local r8 = a | b
  local r9 = a ~ b
  local r10 = a << 2
  local r11 = a >> 2
  local r13 = a + 5
  local r14 = a * 2.5
  return r1, r2, r3, r4, r5, r6, r7, r8, r9, r10, r11, r13, r14
end
local arith_ns = measure(function()
  for call = 1, iterations do arith_path(call + 2, call) end
  return 1
end) * 1e9 / iterations

local function unary_path(x, s, t)
  local u = -x
  local n = ~x
  local b = not x
  local l = #s
  local tl = #t
  return u, n, b, l, tl
end
local unary_t = {10, 20, 30}
local unary_ns = measure(function()
  for call = 1, iterations do unary_path(call, "hello", unary_t) end
  return 1
end) * 1e9 / iterations

local function pow_path(a, b)
  local p = a ^ b
  local q = a ^ 2
  return p, q
end
local pow_ns = measure(function()
  for call = 1, iterations do pow_path(call, 3) end
  return 1
end) * 1e9 / iterations

local function while_iter()
  local x = 0
  while x < 1 do x = x + 1 end   -- exactly one iteration per call
  return x
end
local while_ns = measure(function()
  for call = 1, iterations do while_iter() end
  return 1
end) * 1e9 / iterations

local function compare_path(x, y)
  local lt = x < y
  local le = x <= y
  local eq = x == y
  local ne = x ~= y
  return lt, le, eq, ne
end
local compare_ns = measure(function()
  for call = 1, iterations do compare_path(call, call - 2) end
  return 1
end) * 1e9 / iterations

local function loop_path()
  local s = 0
  for item = 1, count do s = s + item end
  return s
end
local loop_ns = measure(function()
  for _ = 1, iterations do loop_path() end
  return 1
end) * 1e9 / (iterations * count)

print("stock " .. opcode_ns .. " " .. table_ns .. " " .. string_ns .. " " .. unary_ns .. " " .. compare_ns .. " " .. arith_ns .. " " .. while_ns .. " " .. pow_ns .. " " .. loop_ns)
]]
local stock_path = "target/copy_patch_cps/lua55_trace/perf_stock.lua"
local file = assert(io.open(stock_path, "wb"))
file:write((stock_script:gsub("%%d", tostring(iterations))))
file:close()
local pipe = assert(io.popen(("/tmp/lua-5.5.0/src/lua %s"):format(stock_path), "r"))
local stock_text = assert(pipe:read("*a"))
pipe:close()
local so, st, ss, su, sc, sa, sw, sp, sl = stock_text:match("stock%s+([%d%.]+)%s+([%d%.]+)%s+([%d%.]+)%s+([%d%.]+)%s+([%d%.]+)%s+([%d%.]+)%s+([%d%.]+)%s+([%d%.]+)%s+([%d%.]+)")
local stock = { opcode = tonumber(so), table = tonumber(st), string = tonumber(ss), unary = tonumber(su), compare = tonumber(sc), arith = tonumber(sa), while_loop = tonumber(sw), pow = tonumber(sp), loop = tonumber(sl) }

local function row(name, native, stock_ns)
    local speed = stock_ns / native
    io.write(("%-16s %10.3f %12.3f %10.2fx\n"):format(name, native, stock_ns, speed))
end

print(("Lua55 trace perf [%s] iterations=%d"):format(mode, iterations))
print(("%-16s %14s %14s %10s"):format("path", "native ns", "stock 5.5 ns", "speedup"))
row("opcode direct", results.opcode_direct, stock.opcode)
row("opcode wrapped", results.opcode_wrapped, stock.opcode)
row("table ops", results.table, stock.table)
row("string ops", results.string, stock.string)
row("unary path", results.unary, stock.unary)
row("compare path", results.compare, stock.compare)
row("arith path", results.arith, stock.arith)
row("pow path", results.pow, stock.pow)
row("while-iter", results.while_loop, stock.while_loop)
row("loop/guest-iter", results.loop_native, stock.loop)
