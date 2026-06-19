package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

-- Test place/index values using .mlua eval
local Host = require("moonlift.mlua_run")
local ffi = require("ffi")

local store_first = Host.eval [[
local store_first = func(p: ptr(i32), v: i32): i32
    p[0] = v
    return p[0]
end
return store_first
]]
assert(store_first.kind == "func")
assert(store_first.name == "store_first")
assert(#store_first.func.body == 2)
print("OK: store_first constructed")

local compiled = store_first:compile()
local xs = ffi.new("int32_t[1]", { 0 })
assert(compiled(xs, 42) == 42)
assert(xs[0] == 42)
compiled:free()
print("OK: compiled")

-- Struct field access
local get_x = Host.eval [[
local Pair = struct x: i32, y: i32 end
local get_x = func(p: ptr(Pair)): i32 return (*p).x end
return get_x
]]
assert(get_x.name == "get_x")
print("OK: get_x constructed")
ffi.cdef("typedef struct { int32_t x; int32_t y; } HostPlacePair;")
local compiled2 = get_x:compile()
local pair = ffi.new("HostPlacePair", { 42, 99 })
assert(compiled2(pair) == 42)
compiled2:free()
print("OK: compiled")

print("moonlift host place values ok")
