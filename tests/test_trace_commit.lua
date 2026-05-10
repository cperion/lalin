package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local Run = require("moonlift.mlua_run")

local trace_mv = Run.dofile("mlua/luajitvm/jit/trace.mlua")
local trace = trace_mv:compile()

local J_BUF = ffi.new("uint8_t[?]", 32)
local TR_BUF = ffi.new("uint8_t[?]", 104)
local MC_BUF = ffi.new("uint8_t[?]", 16)
local J_ptr = ffi.cast("void *", J_BUF)
local TR_ptr = ffi.cast("void *", TR_BUF)
local MC_ptr = ffi.cast("void *", MC_BUF)
local J_u64 = ffi.cast("uint64_t *", J_BUF)
local TR_u64 = ffi.cast("uint64_t *", TR_BUF)

J_u64[0] = ffi.cast("uintptr_t", TR_ptr)
local rc = trace:get("trace_commit_test")(J_ptr, 7, MC_ptr)
assert(rc == 7, "trace_commit should root_patch trace 7")
assert(TR_u64[10] == ffi.cast("uintptr_t", MC_ptr), "trace mcode pointer patched")

trace:free()
print("trace commit ok")
