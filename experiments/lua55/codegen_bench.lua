package.path = "./?.lua;./?/init.lua;" .. package.path

local Exotyped = require("experiments.lua55.cps_exotype_codegen")

local count = tonumber(arg[1]) or 1000
local samples = tonumber(arg[2]) or 7

local base = debug.getinfo(1, "S").source:match("^@(.*/)") or ""
local file = assert(io.open(base .. "sample_5.5.luac", "rb"))
local bytes = file:read("*a")
file:close()

for _ = 1, 20 do
    local main = Exotyped.load(bytes, "warm")
    local sum, mixed = main()
    assert(sum(10) + mixed(10) == 137.5)
end

local function median(values)
    table.sort(values)
    return values[math.floor((#values + 1) / 2)]
end

local setup_elapsed, ready_elapsed = {}, {}
local checksum
for sample = 1, samples do
    collectgarbage()
    local last
    local start = os.clock()
    for index = 1, count do last = Exotyped.load(bytes, "setup" .. index) end
    setup_elapsed[sample] = os.clock() - start
    assert(last)

    collectgarbage()
    start = os.clock()
    for index = 1, count do
        local main = Exotyped.load(bytes, "ready" .. index)
        local sum, mixed = main()
        checksum = sum(10) + mixed(10)
    end
    ready_elapsed[sample] = os.clock() - start
end

local setup = median(setup_elapsed)
local ready = median(ready_elapsed)
print(("LuaJIT %s exotype-block modules=%d samples=%d"):format(
    jit.version:match("%d.*"), count, samples))
print(("setup=%8.3f us/module  setup+first-reach=%8.3f us/module  checksum=%.1f"):format(
    setup * 1e6 / count, ready * 1e6 / count, checksum))

