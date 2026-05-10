package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local Run = require("moonlift.mlua_run")

local str_mv = Run.dofile("mlua/luajitvm/runtime/string.mlua")
local str = str_mv:compile()

local G_BUF = ffi.new("uint8_t[?]", 552)
local BUCKETS = ffi.new("uint64_t[?]", 4)
local DATA = ffi.new("uint8_t[?]", 8)
local OBJ1 = ffi.new("uint8_t[?]", 64)
local OBJ2 = ffi.new("uint8_t[?]", 64)
local G = ffi.cast("void *", G_BUF)
local G64 = ffi.cast("uint64_t *", G_BUF)
local G32 = ffi.cast("uint32_t *", G_BUF)

DATA[0] = string.byte("f"); DATA[1] = string.byte("o"); DATA[2] = string.byte("o")
G_BUF[32] = 1                  -- currentwhite
G64[19] = ffi.cast("uintptr_t", BUCKETS) -- str.tab @ 152
G32[40] = 3                    -- str.mask @ 160 (4 buckets)
G32[41] = 0                    -- str.num
G32[42] = 100                  -- str.id

local data_ptr = ffi.cast("void *", DATA)
local obj1_ptr = ffi.cast("void *", OBJ1)
local obj2_ptr = ffi.cast("void *", OBJ2)

local h1 = str:get("string_hash_test")(data_ptr, 3)
local h2 = str:get("string_hash_test")(data_ptr, 3)
assert(h1 == h2, "string hash stable")

local miss = str:get("intern_lookup_test")(G, data_ptr, 3)
assert(tonumber(ffi.cast("uintptr_t", miss)) == 0, "lookup before insert misses")

local ins = str:get("intern_insert_test")(G, data_ptr, 3, obj1_ptr)
assert(ins == obj1_ptr, "insert returns inserted object")
assert(OBJ1[8] == 1 and OBJ1[9] == 0, "GCstr header initialized")
assert(ffi.cast("uint32_t *", OBJ1)[3] == 100, "sid set")
assert(ffi.cast("int32_t *", OBJ1)[4] == h1, "hash set")
assert(ffi.cast("uint32_t *", OBJ1)[5] == 3, "len set")
assert(OBJ1[24] == DATA[0] and OBJ1[25] == DATA[1] and OBJ1[26] == DATA[2], "bytes copied")
assert(G32[41] == 1 and G32[42] == 101, "intern counters updated")

local hit = str:get("intern_lookup_test")(G, data_ptr, 3)
assert(hit == obj1_ptr, "lookup finds interned string")

local ins2 = str:get("intern_insert_test")(G, data_ptr, 3, obj2_ptr)
assert(ins2 == obj2_ptr, "manual insert can chain a second object")
local hit2 = str:get("intern_lookup_test")(G, data_ptr, 3)
assert(hit2 == obj2_ptr, "lookup returns newest bucket head match")

str:free()
print("string intern ok")
