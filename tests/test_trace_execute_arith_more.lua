package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local bit = require("bit")
local Run = require("moonlift.mlua_run")

ffi.cdef[[
void *mmap(void *addr, size_t length, int prot, int flags, int fd, long offset);
int munmap(void *addr, size_t length);
]]

local PROT_READ, PROT_WRITE, PROT_EXEC = 1, 2, 4
local MAP_PRIVATE, MAP_ANON = 2, 0x20
local MAP_FAILED = ffi.cast("void *", -1)

local function exec_alloc(size)
  local p = ffi.C.mmap(nil, size, bit.bor(PROT_READ, PROT_WRITE, PROT_EXEC), bit.bor(MAP_PRIVATE, MAP_ANON), -1, 0)
  assert(p ~= MAP_FAILED, "mmap RWX mcode arena failed")
  return ffi.cast("uint8_t *", p)
end

local function bc_abc(op, a, b, c) return op + a * 256 + c * 65536 + b * 16777216 end

local trace_mv = Run.dofile("mlua/luajitvm/jit/trace.mlua")
local trace = trace_mv:compile()

local function one(name, op, x, y, expect)
  local MCODE_SIZE = 4096
  local MCODE = exec_alloc(MCODE_SIZE)
  local J = ffi.new("uint8_t[?]", 88)
  local TR = ffi.new("uint8_t[?]", 104)
  local IR = ffi.new("uint64_t[?]", 0x8000)
  local SNAP = ffi.new("uint8_t[?]", 16 * 16)
  local SMAP = ffi.new("int32_t[?]", 128)
  local REFS = ffi.new("int32_t[?]", 32)
  local A = ffi.new("uint8_t[?]", 280)
  local L = ffi.new("uint8_t[?]", 128)
  local STACK = ffi.new("uint8_t[?]", 16 * 16)
  local BC = ffi.new("uint32_t[?]", 4)
  local J64 = ffi.cast("uint64_t *", J)
  local TR64 = ffi.cast("uint64_t *", TR)
  local TR16 = ffi.cast("uint16_t *", TR)
  local L64 = ffi.cast("uint64_t *", L)
  local S32 = ffi.cast("int32_t *", STACK)
  local S64 = ffi.cast("int64_t *", STACK)

  J64[0] = tonumber(ffi.cast("uintptr_t", TR))
  J64[4] = tonumber(ffi.cast("uintptr_t", MCODE + MCODE_SIZE))
  J64[5] = tonumber(ffi.cast("uintptr_t", MCODE + 16))
  J64[6] = tonumber(ffi.cast("uintptr_t", MCODE))
  J64[7] = tonumber(ffi.cast("uintptr_t", REFS))
  J64[8] = tonumber(ffi.cast("uintptr_t", A))
  TR64[3] = tonumber(ffi.cast("uintptr_t", IR))
  TR64[5] = tonumber(ffi.cast("uintptr_t", SNAP))
  TR64[6] = tonumber(ffi.cast("uintptr_t", SMAP))
  TR16[47] = 21
  L64[4] = tonumber(ffi.cast("uintptr_t", STACK))
  S32[0] = 3; S64[1] = x
  S32[4] = 3; S64[3] = y
  BC[0] = bc_abc(op, 2, 0, 1)
  BC[1] = bc_abc(76, 2, 0, 0)
  local rc = trace:get("trace_record_root_test")(ffi.cast("void *", J), ffi.cast("void *", L), ffi.cast("void *", BC))
  assert(rc == 21, name .. " recorder should compile trace")
  local got = trace:get("trace_call_mcode_test")(ffi.cast("void *", TR), ffi.cast("void *", STACK))
  assert(got == expect, string.format("%s expected %d got %d", name, expect, got))
  ffi.C.munmap(MCODE, MCODE_SIZE)
end

one("subvv", 33, 30, 7, 23)
one("mulvv", 34, 6, 7, 42)
one("divvv", 35, 22, 5, 4)
one("modvv", 36, 22, 5, 2)

trace:free()
print("trace executable arithmetic variants ok")
