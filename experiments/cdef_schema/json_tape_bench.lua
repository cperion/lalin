package.path = "./lua/?.lua;./lua/?/init.lua;./?.lua;./?/init.lua;" .. package.path

local jit = require("jit")
local Json = require("experiments.cdef_schema.json_tape")

local TARGET_BYTES = tonumber(arg[1]) or 1000000
local SAMPLES = tonumber(arg[2]) or 7
local MODE = arg[3] or "tape"
local SHAPE = arg[4] or "object"

local source, count
if SHAPE == "large_string" then
    source = '"' .. string.rep("a", math.max(0, TARGET_BYTES - 2)) .. '"'
    count = 1
else
    local item
    if SHAPE == "object" then
        item = [[{"id":12345,"name":"lalin","escaped":"line\nvalue",]]
            .. [["active":true,"missing":null,"score":-12.75e2,"tags":["a","b","c"]}]]
    elseif SHAPE == "number" then
        item = "-12345.75e2"
    elseif SHAPE == "literal" then
        item = "true"
    elseif SHAPE == "string" then
        item = '"abcdefghijk"'
    else
        error("unknown shape: " .. SHAPE)
    end
    count = math.max(1, math.floor((TARGET_BYTES - 2) / (#item + 1)))
    local items = {}
    for index = 1, count do items[index] = item end
    source = "[" .. table.concat(items, ",") .. "]"
end
local workspace = Json.workspace(#source, 128)
local DirectJson = MODE == "direct" and require("experiments.cdef_schema.json_direct") or nil
local direct_workspace = DirectJson and DirectJson.workspace(#source, 128) or nil

local function parse_tape()
    local report = workspace.decoder:decode(source, workspace.tape, workspace.tape_capacity,
        workspace.strings, workspace.string_capacity, workspace.stack, workspace.stack_capacity)
    assert(report:is_ok())
    return report
end

local function parse_result()
    local result = workspace:decode(source)
    assert(result:is_ok())
    return result
end

local parsed = parse_result()
local cjson = MODE == "cjson" and require("cjson") or nil

local operations = {
    tape = function() return parse_tape():tokens() end,
    materialize = function() return #parsed:materialize() end,
    combined = function() return #parse_result():materialize() end,
    direct = function() return #direct_workspace:decode(source):materialize() end,
    cjson = function() return #cjson.decode(source) end,
}
local operation = assert(operations[MODE], "unknown mode: " .. MODE)

local function median(values)
    table.sort(values)
    return values[math.floor((#values + 1) / 2)]
end

jit.flush()
for _ = 1, 10 do operation() end

local heap_growth = 0
if MODE == "tape" then
    collectgarbage()
    collectgarbage()
    collectgarbage("stop")
    local before = collectgarbage("count")
    operation()
    heap_growth = collectgarbage("count") - before
    collectgarbage("restart")
    collectgarbage()
end

local times = {}
for sample = 1, SAMPLES do
    collectgarbage()
    local t0 = os.clock()
    operation()
    times[sample] = os.clock() - t0
end

local seconds = median(times)
print(string.format(
    "%s %s/%s mode=%s shape=%s bytes=%d items=%d samples=%d",
    jit.version, jit.arch, jit.os, MODE, SHAPE, #source, count, SAMPLES))
print(string.format("%8.3f ms  %8.3f ns/byte  %8.1f MB/s  heap=%8.3f KB",
    seconds * 1e3, seconds * 1e9 / #source, #source / seconds / 1e6, heap_growth))

