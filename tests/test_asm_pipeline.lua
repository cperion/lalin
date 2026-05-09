-- tests/test_asm_pipeline.lua
-- End-to-end JIT assembler pipeline test.
-- Builds synthetic IR traces, runs the backward-scan assembler,
-- and executes the generated x64 machine code via FFI.
package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi  = require("ffi")
local bit  = require("bit")
local Run  = require("moonlift.mlua_run")

local asm_mv  = Run.dofile("mlua/luajitvm/asm/asm_state.mlua")
local asm_mod = asm_mv:compile()
local asm_fn  = asm_mod:get("asm_trace_test")
local ra_fn   = asm_mod:get("ra_get_test")

-- =========================================================================
-- Setup: allocate RWX memory for generated code, JitState, AsmState
-- =========================================================================
ffi.cdef([[
void *mmap(void *a, size_t l, int p, int f, int fd, long o);
int   munmap(void *a, size_t l);
]])
local PROT_RWX = 0x7
local MAP_PRIVATE_ANON = 0x22

local function alloc_rwx(size)
    local p = ffi.C.mmap(nil, size, PROT_RWX, MAP_PRIVATE_ANON, -1, 0)
    assert(p ~= nil and p ~= ffi.cast("void*", -1))
    return p
end

local MCODE_SIZE = 4096
local MCODE = alloc_rwx(MCODE_SIZE)

-- JitState buffer (64 bytes): j64[4]=mctop, j64[5]=mcbot
local J_BUF = ffi.new("uint8_t[64]")
local J_ptr = ffi.cast("void *", J_BUF)
local J_u64 = ffi.cast("uint64_t *", J_BUF)

-- AsmState buffer (272 bytes, zeroed each test)
local A_BUF = ffi.new("uint8_t[272]")
local A_ptr = ffi.cast("void *", A_BUF)

-- IR buffer: slot-indexed u64 array (256 slots)
local IR_SLOTS = 256
local IR_BUF   = ffi.new("uint64_t[256]")
local IR_ptr   = ffi.cast("void *", IR_BUF)

-- =========================================================================
-- Helpers
-- =========================================================================
local REF_BIAS = 0x8000
local IR_KINT  = 60
local IR_ADD   = 10
local IR_SUB   = 11
local IR_MUL   = 12
local IR_NOP   = 90
local IR_RETF  = 82
local IRT_INT  = 19

local function pack_ir(o, t, op1, op2)
    local u1 = ffi.cast("uint64_t", op1 % 65536)
    local u2 = ffi.cast("uint64_t", op2 % 65536)
    local ut = ffi.cast("uint64_t", t  % 256)
    local uo = ffi.cast("uint64_t", o  % 256)
    return u1 + u2 * 65536 + ut * 2^32 + uo * 2^40
end

local function pack_kint(val)
    local lo = bit.band(val, 0xFFFF)
    local hi = bit.band(bit.rshift(val, 16), 0xFFFF)
    return pack_ir(IR_KINT, IRT_INT, lo, hi)
end

local function reset(nins)
    -- Zero JitState mcode pointers
    ffi.fill(J_BUF, 64, 0)
    -- mctop = MCODE + MCODE_SIZE, mcbot = MCODE
    J_u64[4] = ffi.cast("uint64_t", MCODE) + MCODE_SIZE
    J_u64[5] = ffi.cast("uint64_t", MCODE)
    -- Zero AsmState
    ffi.fill(A_BUF, 272, 0)
    -- Zero IR buffer slots
    for i = 0, nins do IR_BUF[i] = 0 end
end

local function mc_entry()
    return ffi.cast("uint8_t *", J_u64[4])
end

local passed, failed = 0, 0
local function check(name, exp, got)
    local e, g = tonumber(exp), tonumber(got)
    if e == g then
        passed = passed + 1
        io.write(string.format("  OK   %-44s = %s\n", name, g))
    else
        failed = failed + 1
        io.write(string.format("  FAIL %-44s expected %s got %s\n", name, e, g))
    end
end

-- =========================================================================
-- Test 1: KINT 42; RETF
--   slot 1: KINT(42)
--   slot 2: RETF(op1 = REF_BIAS+1)
-- Expected: function returns 42
-- =========================================================================
print("--- Test 1: KINT + RETF ---")
reset(3)
IR_BUF[1] = pack_kint(42)
IR_BUF[2] = pack_ir(IR_RETF, IRT_INT, REF_BIAS + 1, 0)

local entry = asm_fn(A_ptr, J_ptr, IR_ptr, 3)  -- nins=3 (slots 1,2 used)
assert(entry ~= nil and ffi.cast("uint64_t", entry) ~= 0, "assembly failed")

local fn1 = ffi.cast("int64_t (*)(void)", entry)
check("KINT(42); RETF → 42", 42, fn1())

-- =========================================================================
-- Test 2: KINT a; KINT b; ADD c=a+b; RETF c
-- =========================================================================
print("\n--- Test 2: ADD ---")
reset(5)
IR_BUF[1] = pack_kint(10)                                        -- slot 1 = 10
IR_BUF[2] = pack_kint(20)                                        -- slot 2 = 20
IR_BUF[3] = pack_ir(IR_ADD, IRT_INT, REF_BIAS+1, REF_BIAS+2)    -- slot 3 = 10+20
IR_BUF[4] = pack_ir(IR_RETF, IRT_INT, REF_BIAS+3, 0)

local entry2 = asm_fn(A_ptr, J_ptr, IR_ptr, 5)
assert(entry2 ~= nil and ffi.cast("uint64_t", entry2) ~= 0, "assembly failed")
local fn2 = ffi.cast("int64_t (*)(void)", entry2)
check("10 + 20 = 30", 30, fn2())

-- =========================================================================
-- Test 3: KINT a; KINT b; SUB c=a-b; RETF c
-- =========================================================================
print("\n--- Test 3: SUB ---")
reset(5)
IR_BUF[1] = pack_kint(100)
IR_BUF[2] = pack_kint(37)
IR_BUF[3] = pack_ir(IR_SUB, IRT_INT, REF_BIAS+1, REF_BIAS+2)    -- 100-37=63
IR_BUF[4] = pack_ir(IR_RETF, IRT_INT, REF_BIAS+3, 0)

local entry3 = asm_fn(A_ptr, J_ptr, IR_ptr, 5)
assert(entry3 ~= nil and ffi.cast("uint64_t", entry3) ~= 0, "assembly failed")
local fn3 = ffi.cast("int64_t (*)(void)", entry3)
check("100 - 37 = 63", 63, fn3())

-- =========================================================================
-- Test 4: KINT a; KINT b; MUL c=a*b; RETF c
-- =========================================================================
print("\n--- Test 4: MUL ---")
reset(5)
IR_BUF[1] = pack_kint(6)
IR_BUF[2] = pack_kint(7)
IR_BUF[3] = pack_ir(IR_MUL, IRT_INT, REF_BIAS+1, REF_BIAS+2)    -- 6*7=42
IR_BUF[4] = pack_ir(IR_RETF, IRT_INT, REF_BIAS+3, 0)

local entry4 = asm_fn(A_ptr, J_ptr, IR_ptr, 5)
assert(entry4 ~= nil and ffi.cast("uint64_t", entry4) ~= 0, "assembly failed")
local fn4 = ffi.cast("int64_t (*)(void)", entry4)
check("6 * 7 = 42", 42, fn4())

-- =========================================================================
-- Test 5: chained arithmetic: (a+b) * (c-d)
--   slot 1: KINT 3
--   slot 2: KINT 4
--   slot 3: KINT 10
--   slot 4: KINT 2
--   slot 5: ADD s3 = s1+s2     (3+4=7)
--   slot 6: SUB s4 = s3+s4-d  (10-2=8)
--   slot 7: MUL s7 = s5*s6    (7*8=56)
--   slot 8: RETF s7
-- =========================================================================
print("\n--- Test 5: chained (3+4)*(10-2)=56 ---")
reset(9)
IR_BUF[1] = pack_kint(3)
IR_BUF[2] = pack_kint(4)
IR_BUF[3] = pack_kint(10)
IR_BUF[4] = pack_kint(2)
IR_BUF[5] = pack_ir(IR_ADD, IRT_INT, REF_BIAS+1, REF_BIAS+2)
IR_BUF[6] = pack_ir(IR_SUB, IRT_INT, REF_BIAS+3, REF_BIAS+4)
IR_BUF[7] = pack_ir(IR_MUL, IRT_INT, REF_BIAS+5, REF_BIAS+6)
IR_BUF[8] = pack_ir(IR_RETF, IRT_INT, REF_BIAS+7, 0)

local entry5 = asm_fn(A_ptr, J_ptr, IR_ptr, 9)
assert(entry5 ~= nil and ffi.cast("uint64_t", entry5) ~= 0, "assembly failed")
local fn5 = ffi.cast("int64_t (*)(void)", entry5)
check("(3+4)*(10-2) = 56", 56, fn5())

-- =========================================================================
-- Test 6: NOP slots are skipped cleanly
-- =========================================================================
print("\n--- Test 6: NOP slots skipped ---")
reset(7)
IR_BUF[1] = pack_kint(99)
IR_BUF[2] = pack_ir(IR_NOP, 0, 0, 0)
IR_BUF[3] = pack_ir(IR_NOP, 0, 0, 0)
IR_BUF[4] = pack_kint(1)
IR_BUF[5] = pack_ir(IR_ADD, IRT_INT, REF_BIAS+1, REF_BIAS+4)
IR_BUF[6] = pack_ir(IR_RETF, IRT_INT, REF_BIAS+5, 0)

local entry6 = asm_fn(A_ptr, J_ptr, IR_ptr, 7)
assert(entry6 ~= nil and ffi.cast("uint64_t", entry6) ~= 0, "assembly failed")
local fn6 = ffi.cast("int64_t (*)(void)", entry6)
check("99+1 (with NOPs) = 100", 100, fn6())

-- Cleanup
ffi.C.munmap(MCODE, MCODE_SIZE)

-- =========================================================================
-- SLOAD tests: load values from a mock Lua stack
-- TValue layout: [tag:i32 @ 0][pad @ 4][payload:i64 @ 8]  = 16 bytes/slot
-- Trace calling convention: first arg (rdi) = base pointer
-- =========================================================================
print("\n--- SLOAD from Lua stack ---")

local TV_STRIDE  = 16
local TV_PAYLOAD = 8
local LUA_TINT   = 3
local IR_SLOAD   = 31

-- Allocate a fresh RWX block and reset J/A for SLOAD tests
local MCODE2 = alloc_rwx(MCODE_SIZE)

local function make_tval_stack(values)
    -- Allocate aligned i64 storage: N slots × 16 bytes
    local n = #values
    local buf = ffi.new("uint8_t[?]", n * 16 + 16)
    -- align to 16-byte boundary
    local base_int = tonumber(ffi.cast("uint64_t", buf)) + 15
    local aligned  = base_int - (base_int % 16)
    local base = ffi.cast("uint8_t *", ffi.cast("uint64_t", aligned))
    for i, v in ipairs(values) do
        local slot = i - 1
        local tag_ptr = ffi.cast("int32_t *", base + slot * 16)
        local pay_ptr = ffi.cast("int64_t *", base + slot * 16 + 8)
        tag_ptr[0] = LUA_TINT
        pay_ptr[0] = ffi.cast("int64_t", v)
    end
    return base, buf   -- return buf too to keep it alive
end

-- Test 7: SLOAD s0, RETF  → return stack[0]
ffi.fill(J_BUF, 64, 0); J_u64[4] = ffi.cast("uint64_t", MCODE2) + MCODE_SIZE; J_u64[5] = ffi.cast("uint64_t", MCODE2)
ffi.fill(A_BUF, 272, 0)
for i = 0, 5 do IR_BUF[i] = 0 end

IR_BUF[1] = pack_ir(IR_SLOAD, IRT_INT, 0, 0)               -- SLOAD stack slot 0
IR_BUF[2] = pack_ir(IR_RETF,  IRT_INT, REF_BIAS + 1, 0)

local entry7 = asm_fn(A_ptr, J_ptr, IR_ptr, 3)
assert(entry7 ~= nil and ffi.cast("uint64_t", entry7) ~= 0)
local fn7 = ffi.cast("int64_t (*)(void *)", entry7)
local stk7, _k7 = make_tval_stack({99})
check("SLOAD[0]=99", 99, fn7(ffi.cast("void *", stk7)))

-- Test 8: SLOAD s0, SLOAD s1, ADD, RETF  → stack[0]+stack[1]
ffi.fill(J_BUF, 64, 0); J_u64[4] = ffi.cast("uint64_t", MCODE2) + MCODE_SIZE; J_u64[5] = ffi.cast("uint64_t", MCODE2)
ffi.fill(A_BUF, 272, 0)
for i = 0, 6 do IR_BUF[i] = 0 end

IR_BUF[1] = pack_ir(IR_SLOAD, IRT_INT, 0, 0)              -- SLOAD slot 0
IR_BUF[2] = pack_ir(IR_SLOAD, IRT_INT, 1, 0)              -- SLOAD slot 1
IR_BUF[3] = pack_ir(IR_ADD,   IRT_INT, REF_BIAS+1, REF_BIAS+2)
IR_BUF[4] = pack_ir(IR_RETF,  IRT_INT, REF_BIAS+3, 0)

local entry8 = asm_fn(A_ptr, J_ptr, IR_ptr, 5)
assert(entry8 ~= nil and ffi.cast("uint64_t", entry8) ~= 0)
local fn8 = ffi.cast("int64_t (*)(void *)", entry8)
local stk8, _k8 = make_tval_stack({30, 12})
check("SLOAD[0]+SLOAD[1] = 30+12 = 42", 42, fn8(ffi.cast("void *", stk8)))

-- Test 9: mixed SLOAD + KINT: stack[0] * 10
ffi.fill(J_BUF, 64, 0); J_u64[4] = ffi.cast("uint64_t", MCODE2) + MCODE_SIZE; J_u64[5] = ffi.cast("uint64_t", MCODE2)
ffi.fill(A_BUF, 272, 0)
for i = 0, 6 do IR_BUF[i] = 0 end

IR_BUF[1] = pack_ir(IR_SLOAD, IRT_INT, 0, 0)              -- SLOAD slot 0
IR_BUF[2] = pack_kint(10)                                  -- KINT 10
IR_BUF[3] = pack_ir(IR_MUL,  IRT_INT, REF_BIAS+1, REF_BIAS+2)
IR_BUF[4] = pack_ir(IR_RETF, IRT_INT, REF_BIAS+3, 0)

local entry9 = asm_fn(A_ptr, J_ptr, IR_ptr, 5)
assert(entry9 ~= nil and ffi.cast("uint64_t", entry9) ~= 0)
local fn9 = ffi.cast("int64_t (*)(void *)", entry9)
local stk9, _k9 = make_tval_stack({7})
check("SLOAD[0]*10 = 7*10 = 70", 70, fn9(ffi.cast("void *", stk9)))

ffi.C.munmap(MCODE2, MCODE_SIZE)

-- =========================================================================
-- Guard tests: SLOAD with IRT_GUARD flag
-- IRT_GUARD = 0x80 OR'd into the type byte means a runtime type check.
-- Guard passes  → trace runs normally, returns computed result.
-- Guard fires   → trace returns DEOPT_SENTINEL (0xBAD = 2989).
-- =========================================================================
print("\n--- Guard tests (IRT_GUARD) ---")

local IRT_GUARD     = 0x80
local DEOPT_SENTINEL = 0xBAD   -- = 2989
local MCODE3 = alloc_rwx(MCODE_SIZE)

local IRT_INT_GUARD = bit.bor(IRT_INT, IRT_GUARD)

-- Test 10: SLOAD with guard, correct type (LUA_TINT=3) → guard passes, returns value
ffi.fill(J_BUF, 64, 0); J_u64[4] = ffi.cast("uint64_t", MCODE3) + MCODE_SIZE; J_u64[5] = ffi.cast("uint64_t", MCODE3)
ffi.fill(A_BUF, 272, 0)
for i = 0, 4 do IR_BUF[i] = 0 end

IR_BUF[1] = pack_ir(IR_SLOAD, IRT_INT_GUARD, 0, 0)
IR_BUF[2] = pack_ir(IR_RETF,  IRT_INT,       REF_BIAS + 1, 0)

local entry10 = asm_fn(A_ptr, J_ptr, IR_ptr, 3)
assert(entry10 ~= nil and ffi.cast("uint64_t", entry10) ~= 0, "guard assembly failed")
local fn10 = ffi.cast("int64_t (*)(void *)", entry10)
local stk10, _k10 = make_tval_stack({77})
check("guard pass: SLOAD[0]=77", 77, fn10(ffi.cast("void *", stk10)))

-- Test 11: guard fires — put wrong type tag (LUA_TSTR=6) in slot 0 → DEOPT_SENTINEL
local LUA_TSTR = 6
local function make_bad_stack(tag, val)
    local buf = ffi.new("uint8_t[48]")
    local base = ffi.cast("uint8_t *", buf)
    ffi.cast("int32_t *", base)[0] = tag    -- wrong tag
    ffi.cast("int64_t *", base + 8)[0] = ffi.cast("int64_t", val)
    return base, buf
end

ffi.fill(J_BUF, 64, 0); J_u64[4] = ffi.cast("uint64_t", MCODE3) + MCODE_SIZE; J_u64[5] = ffi.cast("uint64_t", MCODE3)
ffi.fill(A_BUF, 272, 0)
IR_BUF[1] = pack_ir(IR_SLOAD, IRT_INT_GUARD, 0, 0)
IR_BUF[2] = pack_ir(IR_RETF,  IRT_INT,       REF_BIAS + 1, 0)

local entry11 = asm_fn(A_ptr, J_ptr, IR_ptr, 3)
assert(entry11 ~= nil and ffi.cast("uint64_t", entry11) ~= 0)
local fn11 = ffi.cast("int64_t (*)(void *)", entry11)
local bad11, _b11 = make_bad_stack(LUA_TSTR, 99)
check("guard fire: wrong type → DEOPT_SENTINEL", DEOPT_SENTINEL, fn11(ffi.cast("void *", bad11)))

-- Test 12: guard with ADD: SLOAD[0](guarded) + SLOAD[1](unguarded) = a+b
ffi.fill(J_BUF, 64, 0); J_u64[4] = ffi.cast("uint64_t", MCODE3) + MCODE_SIZE; J_u64[5] = ffi.cast("uint64_t", MCODE3)
ffi.fill(A_BUF, 272, 0)
for i = 0, 6 do IR_BUF[i] = 0 end

IR_BUF[1] = pack_ir(IR_SLOAD, IRT_INT_GUARD, 0, 0)   -- guarded
IR_BUF[2] = pack_ir(IR_SLOAD, IRT_INT,       1, 0)   -- unguarded
IR_BUF[3] = pack_ir(IR_ADD,   IRT_INT, REF_BIAS+1, REF_BIAS+2)
IR_BUF[4] = pack_ir(IR_RETF,  IRT_INT, REF_BIAS+3, 0)

local entry12 = asm_fn(A_ptr, J_ptr, IR_ptr, 5)
assert(entry12 ~= nil and ffi.cast("uint64_t", entry12) ~= 0)
local fn12 = ffi.cast("int64_t (*)(void *)", entry12)
local stk12, _k12 = make_tval_stack({13, 29})
check("guard+ADD: 13+29=42", 42, fn12(ffi.cast("void *", stk12)))

-- Test 13: guard fires mid-trace on first SLOAD, second SLOAD never runs
ffi.fill(J_BUF, 64, 0); J_u64[4] = ffi.cast("uint64_t", MCODE3) + MCODE_SIZE; J_u64[5] = ffi.cast("uint64_t", MCODE3)
ffi.fill(A_BUF, 272, 0)
for i = 0, 6 do IR_BUF[i] = 0 end

IR_BUF[1] = pack_ir(IR_SLOAD, IRT_INT_GUARD, 0, 0)
IR_BUF[2] = pack_ir(IR_SLOAD, IRT_INT,       1, 0)
IR_BUF[3] = pack_ir(IR_ADD,   IRT_INT, REF_BIAS+1, REF_BIAS+2)
IR_BUF[4] = pack_ir(IR_RETF,  IRT_INT, REF_BIAS+3, 0)

local entry13 = asm_fn(A_ptr, J_ptr, IR_ptr, 5)
assert(entry13 ~= nil and ffi.cast("uint64_t", entry13) ~= 0)
local fn13 = ffi.cast("int64_t (*)(void *)", entry13)
local bad13, _b13 = make_bad_stack(LUA_TSTR, 999)
check("guard fire mid-trace → DEOPT_SENTINEL", DEOPT_SENTINEL, fn13(ffi.cast("void *", bad13)))

ffi.C.munmap(MCODE3, MCODE_SIZE)
asm_mod:free()

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
print("All assembler pipeline tests passed")
