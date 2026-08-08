package.path = "./?.lua;./?/init.lua;" .. package.path

local Tcc = require("experiments.wasm_gcps.tcc_jit")

local modules = tonumber(arg[1]) or 500
local samples = tonumber(arg[2]) or 5

local function median(values)
    table.sort(values)
    return values[math.floor((#values + 1) / 2)]
end

local elapsed, checksum = {}, 0
for sample = 1, samples do
    collectgarbage()
    local start = os.clock()
    for _ = 1, modules do
        local session = Tcc.compile()
        checksum = checksum + tonumber(session.sum_region(10))
        session:free()
    end
    elapsed[sample] = os.clock() - start
end

local seconds = median(elapsed)
print(("libtcc modules=%d samples=%d"):format(modules, samples))
print(("%8.3f us/module  source=%d bytes  checksum=%.1f"):format(
    seconds * 1e6 / modules, #Tcc.source, checksum))

