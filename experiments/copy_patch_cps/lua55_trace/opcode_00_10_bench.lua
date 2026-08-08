package.path = "./lua/?.lua;./lua/?/init.lua;./?.lua;./?/init.lua;" .. package.path

local Undump = require("experiments.lua55.undump55")
local Projection = require("experiments.copy_patch_cps.lua55_trace.opcode_00_10_projection")
local Native = require("experiments.copy_patch_cps.lua55_trace.opcode_00_08")
local bytes = require("experiments.copy_patch_cps.lua55_trace.opcode_00_10_fixture")

local main = Undump.undump(bytes)
local path = assert(Projection.project(main.protos[1], 0, 24))
local bank = dofile("target/copy_patch_cps/lua55_trace/opcode_00_08/bank.lua")
Native.extend_bank(bank, dofile("target/copy_patch_cps/lua55_trace/opcode_09_10/bank.lua"))

local function initialize(program)
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
    return frame
end

local cold_trials = tonumber(arg[1]) or 500
local build_seconds, install_seconds = 0, 0
for _ = 1, cold_trials do
    local before = os.clock()
    local program = path:new_program(24, bank)
    local after_build = os.clock()
    local frame = initialize(program)
    assert(program:execute(frame) == bank.status.completed)
    local after_install = os.clock()
    build_seconds = build_seconds + after_build - before
    install_seconds = install_seconds + after_install - after_build
    program:free()
end

local program = path:new_program(24, bank)
local frame = initialize(program)
assert(program:execute(frame) == bank.status.completed)
local iterations = tonumber(arg[2]) or 2000000

local function measure(loop)
    for _ = 1, 3 do loop(10000) end
    collectgarbage("collect")
    local before = os.clock()
    local checksum = loop(iterations)
    return (os.clock() - before) * 1e9 / iterations, checksum
end

local entry, raw_frame = program.residual.entry, frame.frame
local direct_ns = measure(function(count)
    for _ = 1, count do entry(raw_frame) end
    return tonumber(frame.values[8].payload.integer)
end)

local program_ns = measure(function(count)
    for _ = 1, count do program:execute(frame) end
    return tonumber(frame.values[8].payload.integer)
end)

local varying_ns, native_checksum = measure(function(count)
    local checksum = 0
    for index = 1, count do
        frame.values[0].payload.integer = index
        entry(raw_frame)
        checksum = checksum + tonumber(frame.values[8].payload.integer)
    end
    return checksum
end)

local u1, u2, u3, u4, u5 = 0, 0, false, true, nil
local function oracle(x)
    local m = x
    local i = 42
    local f = 3.0
    local k = 2.5
    local a, b, c = false, true, nil
    u1 = m; m = u1
    u2 = k; k = u2
    u3 = a; a = u3
    u4 = b; b = u4
    u5 = c; c = u5
    return m, i, f, k, a, b, c
end

local lua_ns, lua_checksum = measure(function(count)
    local checksum = 0
    for index = 1, count do
        local result = oracle(index)
        checksum = checksum + result
    end
    return checksum
end)

assert(native_checksum == lua_checksum)
print(("Lua55 decoded opcode 0-10 benchmark (%d-op path):"):format(#path.occurrences))
print(("  learner RX size       %d bytes"):format(program.learner.size))
print(("  residual RX size      %d bytes"):format(program.residual.size))
print(("  learner construction  %.3f us"):format(build_seconds * 1e6 / cold_trials))
print(("  first run + install   %.3f us"):format(install_seconds * 1e6 / cold_trials))
print(("  direct residual       %.3f ns/path  %.3f ns/op"):format(
    direct_ns, direct_ns / #path.occurrences))
print(("  Program:execute       %.3f ns/path"):format(program_ns))
print(("  varying native path   %.3f ns/path"):format(varying_ns))
print(("  equivalent Lua path   %.3f ns/path"):format(lua_ns))
program:free()
