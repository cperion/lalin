package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local llb = require("llb")
local stream = llb.stream

local env = llb.core_family():env().env
assert(rawget(env, "stream") == nil, "LLB family env should expose streams through llb.stream, not bare stream")
assert(llb.stream == stream, "LLB stream API remains available through llb.stream")

local mapped = stream.from.array({ 1, 2, 3 })
    :map(function(v) return v * 2 end)
    :filter(function(v) return v > 2 end)
    :to_array()
assert(#mapped == 2 and mapped[1] == 4 and mapped[2] == 6, "stream map/filter should preserve values")

local calls = 0
local filtered = stream.from.array({ 1, 2, 3, 4 })
    :filter_map(function(v)
        calls = calls + 1
        if v % 2 == 0 then return v, v * 10 end
        return nil
    end)
    :to_array()
assert(calls == 4, "filter_map callback must run once per source item")
assert(#filtered == 2 and filtered[1] == 2 and filtered[2] == 4, "collect_array keeps first filter_map payload value")

local drained = {}
local drain_result = stream.drain(function(v) drained[#drained + 1] = v end, stream.from.array({ "a", "b" }))
assert(drain_result == nil, "stream.drain returns nil after full consumption")
assert(#drained == 2 and drained[1] == "a" and drained[2] == "b", "stream.drain should consume every item")

local plan_array = stream.run(stream.plan {
    source = stream.spec.array({ 3, 4, 5 }),
    ops = {
        stream.op.drop(1),
        stream.op.map(function(v) return v + 1 end),
        stream.op.take(2),
    },
    sink = stream.sink.array(),
})
assert(#plan_array == 2 and plan_array[1] == 5 and plan_array[2] == 6, "stream plan array sink should run")

local any = stream.spec.any({ 7, 8 })
local any_array = stream.collect.array(any)
assert(#any_array == 2 and any_array[1] == 7 and any_array[2] == 8, "any_spec should preserve raw stream triple")

local seen = {}
local sink_result = stream.run(stream.plan {
    source = stream.spec.array({ "x", "y" }),
    sink = stream.sink.drain(function(v) seen[#seen + 1] = v end),
})
assert(sink_result == nil, "drain sink should return nil")
assert(#seen == 2 and seen[1] == "x" and seen[2] == "y", "drain sink should consume stream")

io.write("llb stream ok\n")
