package.path = "./lua/?.lua;./lua/?/init.lua;./?.lua;./?/init.lua;" .. package.path

local tests = {
    { name = "arithcmp2m", reps = 3, expected = -500655552779, source = [[
local x, s = 1, 0
for i = 1, 2000000 do
  x = (x * 3 + 7) % 1000003
  if x < 500000 then s = s + x else s = s - x end
end
return s
]] },
    { name = "fib25", reps = 5, expected = 75025, source = [[
local function fib(n)
  if n < 2 then return n end
  return fib(n - 1) + fib(n - 2)
end
return fib(25)
]] },
    { name = "tail1m", reps = 3, expected = 1000000, source = [[
local function loop(n, s)
  if n == 0 then return s end
  return loop(n - 1, s + 1)
end
return loop(1000000, 0)
]] },
    { name = "numfor10m", reps = 2, expected = 50000005000000, source = [[
local s = 0
for i = 1, 10000000 do s = s + i end
return s
]] },
    { name = "table5m", reps = 2, expected = 27500000, source = [[
local t = { 1, 2, 3, 4, 5, 6, 7, 8 }
local s = 0
for i = 1, 5000000 do
  local k = (i - 1) % 8 + 1
  t[k] = t[k] + 1
  s = s + t[k]
  t[k] = t[k] - 1
end
return s
]] },
    { name = "concat10k", reps = 5, expected = "n=10000", source = [[
local s = ""
for i = 1, 10000 do s = "n=" .. i end
return s
]] },
}

local function median(values)
    table.sort(values)
    return values[math.floor((#values + 1) / 2)]
end

local function measure(action, reps)
    action(); action(); action()
    local samples = {}
    for sample = 1, 7 do
        local started = os.clock()
        for _ = 1, reps do action() end
        samples[sample] = (os.clock() - started) / reps
    end
    return median(samples)
end

local worker, kind = arg[1] == "--worker", arg[2]
if worker and kind == "stock" then
    for _, test in ipairs(tests) do
        local chunk = assert(load(test.source, "@scalar-" .. test.name))
        local observed = chunk()
        assert(tostring(observed) == tostring(test.expected), test.name .. " stock result changed")
        local elapsed = measure(chunk, test.reps)
        print(("RESULT %s %.9f"):format(test.name, elapsed))
    end
    return
end

if worker and kind == "v2" then
    local ffi = require("ffi")
    local CPS = require("experiments.copy_patch_cps.lua55_trace.cps_invocation_v2")
    for _, test in ipairs(tests) do
        local path = os.tmpname() .. ".lua"
        local file = assert(io.open(path, "wb")); file:write(test.source); file:close()
        local values, invocation = CPS.run(path, {
            return_invocation = true, scalar_only = true,
            region_size = 512 * 1024 * 1024,
        })
        os.remove(path)
        assert(invocation.scalar_only == true, test.name .. " did not publish scalar-only image")
        assert(tostring(values[1]) == tostring(test.expected), test.name .. " V2 result changed")
        local frame = ffi.cast("Lua55NativeFrameV2 *", invocation.frame_begin)
        local frame_bytes = CPS.root_frame_bytes(
            tonumber(frame[0].value_count), tonumber(frame[0].value_capacity))
        local entry = invocation.functions[invocation.main_index].entry
        local function retained()
            invocation.invocation[0].frame_next = invocation.frame_begin + frame_bytes
            invocation.invocation[0].current_frame = frame
            invocation.invocation[0].outcome.discriminant = 0
            frame[0].top = 0
            entry(frame)
            assert(tonumber(invocation.invocation[0].outcome.discriminant) == 1,
                test.name .. " retained execution did not return")
        end
        local elapsed = measure(retained, test.reps)
        print(("RESULT %s %.9f"):format(test.name, elapsed))
        invocation:free()
    end
    return
end

assert(not worker, "unknown scalar performance worker")
local cpu = tonumber(os.getenv("LUA55_V2_GATE_CPU") or "2")
local stock = os.getenv("LUA55_STOCK") or "/tmp/lua-5.5.0/src/lua"
local jit_off = not require("jit").status()
local lua = os.getenv("LUAJIT") or "luajit"
local mode = jit_off and "-joff " or ""
local script = arg[0]
local function capture(command)
    local pipe = assert(io.popen(command, "r"))
    local output = pipe:read("*a")
    assert(pipe:close(), "scalar performance worker failed: " .. command .. "\n" .. output)
    return output
end
local function results(output)
    local parsed = {}
    for name, seconds in output:gmatch("RESULT%s+(%S+)%s+(%S+)") do
        parsed[name] = tonumber(seconds)
    end
    return parsed
end
local prefix = ("taskset -c %d "):format(cpu)
local warm = prefix .. lua .. " " .. mode .. script .. " --worker v2 >/dev/null && "
local v2 = results(capture(warm .. prefix .. lua .. " " .. mode .. script .. " --worker v2"))
local puc = results(capture(prefix .. stock .. " " .. script .. " --worker stock"))
local minimum = {
    arithcmp2m = 1.20, fib25 = 1.00, tail1m = 1.05,
    numfor10m = 1.50, table5m = 1.15, concat10k = 1.50,
}
for _, test in ipairs(tests) do
    local native_time = assert(v2[test.name], "missing V2 result " .. test.name)
    local stock_time = assert(puc[test.name], "missing stock result " .. test.name)
    local ratio = stock_time / native_time
    print(("%-12s scalar_ms=%8.3f stock_ms=%8.3f PUC/V2=%5.2fx floor=%4.2fx")
        :format(test.name, native_time * 1000, stock_time * 1000, ratio, minimum[test.name]))
    assert(ratio >= minimum[test.name],
        ("scalar performance regression for %s: %.3fx < %.3fx")
            :format(test.name, ratio, minimum[test.name]))
end
print("lua55 v2 scalar retained performance gate: ok ("
    .. (jit_off and "-joff" or "jit") .. ", cpu " .. cpu .. ")")
