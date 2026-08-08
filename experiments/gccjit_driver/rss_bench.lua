package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local State = require("experiments.gccjit_driver.machine")

local iterations = tonumber(arg[1]) or 100
local interval = tonumber(arg[2]) or 25

local function resident_kb()
    local file = assert(io.open("/proc/self/status", "r"))
    local status = file:read("*a")
    file:close()
    return assert(tonumber(status:match("VmRSS:%s+(%d+)")))
end

local loaded_kb = resident_kb()
for index = 1, iterations do
    local driver = State.Driver()
    driver:cook_blocks(3)
    assert(driver:succeeded(), driver:diagnostic_text())
    driver:free()
    if index == 1 or index == iterations or index % interval == 0 then
        collectgarbage("collect")
        print(("compiles=%d resident_kb=%d"):format(index, resident_kb()))
    end
end
print(("loaded_kb=%d final_kb=%d"):format(loaded_kb, resident_kb()))
