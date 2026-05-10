package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local Run = require("moonlift.mlua_run")

local opt_mv = Run.dofile("mlua/luajitvm/jit/opt_loop.mlua")
local opt = opt_mv:compile()
local opt_loop = opt:get("opt_loop_test")

local J_BUF = ffi.new("uint8_t[?]", 32)
local TR_BUF = ffi.new("uint8_t[?]", 104)
local IR_BUF = ffi.new("uint8_t[?]", 256 * 8)
local J_ptr = ffi.cast("void *", J_BUF)
local TR_ptr = ffi.cast("void *", TR_BUF)
local IR_ptr = ffi.cast("void *", IR_BUF)
local J_u64 = ffi.cast("uint64_t *", J_BUF)
local TR_u64 = ffi.cast("uint64_t *", TR_BUF)
local IR_u64 = ffi.cast("uint64_t *", IR_BUF)

J_u64[0] = ffi.cast("uintptr_t", TR_ptr)
TR_u64[3] = ffi.cast("uintptr_t", IR_ptr)

J_u64[1] = 1
assert(opt_loop(J_ptr, 0) == 0, "empty trace is not loop")

J_u64[1] = 3
IR_u64[2] = ffi.cast("uint64_t", 10) * 2^40
assert(opt_loop(J_ptr, 0) == 0, "trace ending in ADD is not loop")

IR_u64[2] = ffi.cast("uint64_t", 80) * 2^40
assert(opt_loop(J_ptr, 0) == 1, "trace ending in LOOP is loop")

opt:free()
print("opt loop ok")
