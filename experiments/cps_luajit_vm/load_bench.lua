local bit = require("bit")
local jit = require("jit")
local opt = require("jit.opt")
local codegen = require("experiments.cps_luajit_vm.codegen")

local MAX_DIAMONDS = tonumber(arg[1]) or 16
local REPETITIONS = tonumber(arg[2]) or 30
local SAMPLES = tonumber(arg[3]) or 5

opt.start("hotloop=20", "hotexit=2", "loopunroll=256")

local function median(values)
    local sorted = {}
    for i = 1, #values do sorted[i] = values[i] end
    table.sort(sorted)
    return sorted[math.floor((#sorted + 1) / 2)]
end

local function measure(operation)
    local samples = {}
    for sample = 1, SAMPLES do
        collectgarbage("collect")
        local t0 = os.clock()
        for _ = 1, REPETITIONS do operation() end
        samples[sample] = (os.clock() - t0) * 1e6 / REPETITIONS
    end
    return median(samples)
end
jit.off(measure, true)

local emitters = {
    { name = "direct", emit = codegen.emit_direct },
    { name = "cps", emit = codegen.emit_cps },
}
local scales = { 1, 2, 4, 8, 16, 24, 32, 48, 64 }

print(string.format("LuaJIT: %s %s/%s", jit.version, jit.arch, jit.os))
print(string.format("repetitions=%d samples=%d", REPETITIONS, SAMPLES))
print(string.format("%-7s %4s %9s %9s %11s %11s %8s %11s",
    "shape", "diam", "source B", "dump B", "source us", "binary us",
    "ratio", "factory us"))

for _, emitter in ipairs(emitters) do
    for _, diamonds in ipairs(scales) do
        if diamonds <= MAX_DIAMONDS then
            local source = emitter.emit(diamonds)
            local chunkname = "@cps-load-" .. emitter.name .. "-" .. diamonds
            local source_factory = codegen.compile(source, chunkname)
            local dumped = string.dump(source_factory)
            local binary_factory = assert(loadstring(dumped, chunkname .. "-dump"))

            local source_entry = source_factory(bit)
            local binary_entry = binary_factory(bit)
            local source_result = source_entry(2000)
            local binary_result = binary_entry(2000)
            assert(source_result == binary_result, "source/binary result mismatch")

            local source_us = measure(function()
                return assert(loadstring(source, chunkname))(bit)
            end)
            local binary_us = measure(function()
                return assert(loadstring(dumped, chunkname .. "-dump"))(bit)
            end)
            local factory_us = measure(function()
                return source_factory(bit)
            end)

            print(string.format("%-7s %4d %9d %9d %11.3f %11.3f %8.3f %11.3f",
                emitter.name, diamonds, #source, #dumped, source_us, binary_us,
                binary_us / source_us, factory_us))
        end
    end
end

