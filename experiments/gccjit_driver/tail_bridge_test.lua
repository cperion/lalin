package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local bit = require("bit")
local ffi = require("ffi")
local util = require("jit.util")
local vmdef = require("jit.vmdef")
local State = require("experiments.gccjit_driver.tail_bridge_machine")

local function has_callt(fn)
    for pc = 1, 100 do
        local instruction = util.funcbc(fn, pc)
        if instruction == nil then break end
        local opcode = bit.band(instruction, 255)
        local name = vmdef.bcnames:sub(opcode * 6 + 1, opcode * 6 + 6)
        if name:match("CALLT") then return true end
    end
    return false
end

assert(has_callt(State.Driver.turn), "Driver:turn must tail-call the FFI entry")
assert(has_callt(State.Driver.callback_turn), "Driver:callback_turn must tail-call the FFI entry")

local driver = State.Driver()
driver:inspect(3)
assert(driver:succeeded(), driver:diagnostic_text())
assert(ffi.sizeof("TailBridgeV1_State") == 40)

local runtime = State.RuntimeStateArray()
runtime[0].limit = 1000
assert(driver:turn(runtime) == 332833500)
assert(runtime[0].cursor == 1000)
assert(runtime[0].accumulator == 332833500)
assert(runtime[0].native_transitions == 1000)
assert(runtime[0].exit_code == State.constants.exit.native_completed)

local callback_calls = 0
local callback = ffi.cast("TailBridgeV1_Callback", function(state)
    callback_calls = callback_calls + 1
    state[0].exit_code = State.constants.exit.lua_callback
    state[0].accumulator = state[0].accumulator + 7
    return state[0].accumulator
end)
runtime[0].accumulator = 35
runtime[0].exit_code = 0
local transitions = tonumber(runtime[0].native_transitions)
assert(driver:callback_turn(runtime, callback) == 42)
assert(callback_calls == 1)
assert(runtime[0].exit_code == State.constants.exit.lua_callback)
assert(runtime[0].native_transitions == transitions + 1)

local file = assert(io.open("target/gccjit_driver/bridge.s", "rb"))
local assembly = file:read("*a")
file:close()
assert(assembly:match("tail_bridge_entry:.-jmp%s+tail_bridge_run"))
assert(assembly:match("tail_bridge_run:.-jmp%s+tail_bridge_complete"))
assert(assembly:match("tail_bridge_callback:.-jmp%s+%*%%[a-z0-9]+"))

callback:free()
driver:free()
print(("ok ffi tail bridge root=%d state=%d compile_us=%.3f transitions=%d"):format(
    ffi.sizeof(driver), ffi.sizeof("TailBridgeV1_State"),
    tonumber(driver.metrics.compile_ns) / 1000, tonumber(runtime[0].native_transitions)))
