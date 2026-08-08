-- run55_test: run a real Lua 5.5 program through the native trace runner
-- and differential-compare its stdout against stock Lua 5.5.
package.path = "./lua/?.lua;./lua/?/init.lua;./?.lua;./?/init.lua;" .. package.path

local Run55 = require("experiments.copy_patch_cps.lua55_trace.run55")

local STOCK_LUA = "/tmp/lua-5.5.0/src/lua"
local stock = io.open(STOCK_LUA, "r")
if not stock then print("run55 oracle: SKIPPED (stock lua missing)"); os.exit(0) end
stock:close()

local DEMO = "experiments/copy_patch_cps/lua55_trace/run55_demo.lua"

local function stock_output()
    local pipe = assert(io.popen(([=[%s %s 2>&1]=]):format(STOCK_LUA, DEMO), "r"))
    local out = pipe:read("*a"); pipe:close()
    return out
end

-- Capture the native run's stdout: the demo prints through the host
-- callback, so pass a capturing print in the env and run in-process.
local function native_output()
    local lines = {}
    local capture = function(...)
        local parts = {}
        for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
        lines[#lines + 1] = table.concat(parts, "\t") .. "\n"
    end
    local results = Run55.run(DEMO, { callbacks = {
        print = capture,
        tostring = tostring,
        math = {
            floor = math.floor, sqrt = math.sqrt, abs = math.abs,
            max = math.max, min = math.min, ceil = math.ceil,
            huge = math.huge, pi = math.pi,
        },
    } })
    assert(#results == 3
        and tonumber(results[1]) == 3628800
        and tonumber(results[2]) == 5050
        and tonumber(results[3]) == 100,
        ("run55 main results differ: %s"):format(table.concat(results, ", ")))
    return table.concat(lines)
end

local expected = stock_output()
local got = native_output()
    if got ~= expected then
        for index = 1, math.max(#got, #expected) do
            if got:sub(index, index) ~= expected:sub(index, index) then
                error(("run55 stdout differs at byte %d: stock=%q native=%q"):format(
                    index, expected:sub(index, index), got:sub(index, index)), 0)
            end
        end
        error("run55 stdout length differs")
    end

print("run55: ok real Lua 5.5 program runs natively and matches stock stdout")
