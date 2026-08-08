package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local State = require("experiments.gccjit_driver.machine")

assert(os.execute("mkdir -p target/gccjit_driver"))

local expected = 0
for value = 0, 999 do expected = expected + value * value end

local blocks = State.Driver()
assert(blocks:inspect_blocks(3) == blocks)
assert(blocks:succeeded(), blocks:diagnostic_text())
assert(blocks.types.runtime_size == ffi.sizeof("GccJitDriverV1_RuntimeState"))
local block_state = State.RuntimeStateArray()
block_state[0].limit = 1000
assert(blocks:invoke(block_state) == expected)
assert(block_state[0].cursor == 1000)
assert(block_state[0].accumulator == expected)

local tail = State.Driver()
assert(tail:inspect_tail(3) == tail)
assert(tail:succeeded(), tail:diagnostic_text())
local tail_state = State.RuntimeStateArray()
tail_state[0].limit = 1000
assert(tail:invoke(tail_state) == expected)
assert(tail_state[0].cursor == 1000)
assert(tail_state[0].accumulator == expected)

local major, minor, patch = blocks:version()
assert(major >= 16)
assert(blocks.metrics.compile_ns > 0 and tail.metrics.compile_ns > 0)
assert(ffi.sizeof(blocks) < 2048)
assert(blocks.acquire_machine.runs == 1 and blocks.type_machine.runs == 1)
assert(blocks.block_machine.runs == 1 and blocks.tail_machine.runs == 0)
assert(tail.tail_machine.runs == 1 and tail.block_machine.runs == 0)

blocks:free()
tail:free()
assert(blocks.status == State.constants.status.released)
assert(tail.status == State.constants.status.released)

print(("ok gccjit driver gcc=%d.%d.%d root=%d block_compile_us=%.3f tail_compile_us=%.3f"):format(
    major, minor, patch, ffi.sizeof(blocks),
    tonumber(blocks.metrics.compile_ns) / 1000, tonumber(tail.metrics.compile_ns) / 1000))
