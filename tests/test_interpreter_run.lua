-- tests/test_interpreter_run.lua
-- FFI-backed test harness: compiles the interpreter and runs bytecode programs.
package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local Run = require("moonlift.mlua_run")

-- Compile the interpreter module
local dispatch_mv = Run.dofile("mlua/luajitvm/runtime/dispatch.mlua")
local dispatch = dispatch_mv:compile()

-- Create test buffers with LuaJIT FFI
local STACK_SLOTS = 256
local TValueSize   = 16
local StackBytes   = STACK_SLOTS * TValueSize

-- ThreadState buffer (128 bytes, enough for lua_State layout)
local state_buf  = ffi.new("uint8_t[?]", 128)
local stack_buf  = ffi.new("uint8_t[?]", StackBytes)
local bc_buf     = ffi.new("uint32_t[?]", 64)
local state_ptr  = ffi.cast("void *", state_buf)
local stack_ptr  = ffi.cast("void *", stack_buf)
local bc_ptr     = ffi.cast("void *", bc_buf)

-- ThreadState layout offsets:
--   offset 32 = base  (ptr to TValue)
--   offset 40 = top   (ptr to TValue)
--   offset 56 = stack (ptr to TValue)
local state_u64 = ffi.cast("uint64_t *", state_buf)
local stack_uint = ffi.cast("uintptr_t", stack_ptr)
state_u64[4] = stack_uint                                    -- base = stack_ptr
state_u64[5] = stack_uint + StackBytes                       -- top = stack_ptr + StackBytes
state_u64[7] = stack_uint                                    -- stack = stack_ptr

local function run_program_with_setup(bc, nins, setup)
    -- Add RET1 at position nins to return slot 0
    bc[nins] = 76  -- RET1 with A=0
    ffi.fill(stack_buf, StackBytes, 0)
    if setup then setup() end
    local nresults = dispatch:get("vm_interp_run")(state_ptr, bc_ptr, 0, 0)
    local tv64 = ffi.cast("int64_t *", stack_buf)
    return tonumber(tv64[1])  -- payload at byte offset 8 = i64 index 1
end

local function run_program(bc, nins)
    return run_program_with_setup(bc, nins)
end

-- Test results
local passed, failed = 0, 0
local function check(name, expected, actual)
    if expected == actual then
        passed = passed + 1
        print(string.format("  OK   %-20s = %d", name, actual))
    else
        failed = failed + 1
        print(string.format("  FAIL %-20s expected %d, got %d", name, expected, actual))
    end
end

-- Test 1: KSHORT 42 → return
bc_buf[0] = 41 + (0 * 256) + (42 * 65536)  -- KSHORT A=0 D=42
check("kshort_ret", 42, run_program(bc_buf, 1))

-- Test 2: MOV copy
bc_buf[0] = 41 + (0 * 256) + (99 * 65536)   -- KSHORT A=0 D=99
bc_buf[1] = 18 + (1 * 256)                    -- MOV A=1 B=0
bc_buf[2] = 76 + (1 * 256)                    -- RET1 A=1
check("mov", 99, run_program(bc_buf, 3))

local function kshort(a, d) return 41 + (a * 256) + (d * 65536) end
local function addvv(a, b, c) return 32 + (a * 256) + (c * 65536) + (b * 16777216) end
local function tgetv(a, b, c) return 56 + (a * 256) + (c * 65536) + (b * 16777216) end
local function tgetb(a, b, c) return 58 + (a * 256) + (c * 65536) + (b * 16777216) end
local function tsetv(a, b, c) return 60 + (a * 256) + (c * 65536) + (b * 16777216) end
local function tsetb(a, b, c) return 62 + (a * 256) + (c * 65536) + (b * 16777216) end

-- Test 3: Arithmetic — (3+4)*2 = 14 (all through slot 0 and slot 1)
bc_buf[0] = kshort(0, 3)                              -- slot0 = 3
bc_buf[1] = kshort(1, 4)                              -- slot1 = 4
bc_buf[2] = addvv(0, 0, 1)                            -- slot0 = slot0 + slot1 = 7
bc_buf[3] = kshort(1, 2)                              -- slot1 = 2
bc_buf[4] = 34 + (0 * 256) + (1 * 65536)              -- MULVV A=0 B=0 C=1 → slot0 *= slot1 = 14
bc_buf[5] = 76                                         -- RET1 A=0
check("arithmetic", 14, run_program(bc_buf, 6))

-- Test 4: Sum 0+1+2+3+4+5 = 15
bc_buf[0]  = kshort(0, 0)
bc_buf[1]  = kshort(1, 1);  bc_buf[2]  = addvv(0, 0, 1)
bc_buf[3]  = kshort(1, 2);  bc_buf[4]  = addvv(0, 0, 1)
bc_buf[5]  = kshort(1, 3);  bc_buf[6]  = addvv(0, 0, 1)
bc_buf[7]  = kshort(1, 4);  bc_buf[8]  = addvv(0, 0, 1)
bc_buf[9]  = kshort(1, 5);  bc_buf[10] = addvv(0, 0, 1)
bc_buf[11] = 76  -- RET1 A=0
check("sum_0_to_5", 15, run_program(bc_buf, 12))

-- Test 5: JMP skip
bc_buf[0] = kshort(0, 10)
bc_buf[1] = 88 + (0 * 256) + (2 * 65536)     -- JMP D=2 (skip 1 insn → pc+3)
bc_buf[2] = kshort(0, 99)                     -- DEAD: should be skipped
bc_buf[3] = 76                                -- RET1 A=0 → should return 10
check("jmp_skip", 10, run_program(bc_buf, 4))

-- Test 6: LOOP D=0 (no-op back-edge, just advances)
bc_buf[0] = kshort(0, 7)
bc_buf[1] = 85 + (0 * 256) + (0 * 65536)     -- LOOP D=0: jump to pc+1
bc_buf[2] = 76                                -- RET1 A=0 → return 7
check("loop_d0", 7, run_program(bc_buf, 3))

-- Test 7: LOOP back-edge (finite: loop exactly once, then use counter)
-- Program:
--   pc=0: KSHORT A=0 D=1    slot0=1
--   pc=1: KSHORT A=1 D=-1   slot1=-1 (signed)
--   pc=2: ADDVV A=2 B=0 C=1  slot2 = 1 + (-1) = 0
--   pc=3: LOOP D=-1          back to pc=3 (self-loop, infinite...)
-- Better: explicit finite program with JMP.

-- Test 7: SUBVV (10 - 3 = 7)
bc_buf[0] = kshort(0, 10)
bc_buf[1] = kshort(1, 3)
bc_buf[2] = 33 + (0 * 256) + (1 * 65536)              -- SUBVV A=0 B=0 C=1 → slot0 = 10 - 3 = 7
bc_buf[3] = 76                                         -- RET1 A=0
check("subvv", 7, run_program(bc_buf, 4))

-- Test 8: MULVV (6 * 7 = 42)
bc_buf[0] = kshort(0, 6)
bc_buf[1] = kshort(1, 7)
bc_buf[2] = 34 + (0 * 256) + (1 * 65536)              -- MULVV A=0 B=0 C=1 → slot0 = 6 * 7 = 42
bc_buf[3] = 76                                         -- RET1 A=0
check("mulvv", 42, run_program(bc_buf, 4))

-- Test 9: ISLT — 3 < 5 → true, don't skip, return 1
bc_buf[0] = kshort(0, 3); bc_buf[1] = kshort(1, 5)
bc_buf[2] = 0 + (1 * 65536)                            -- ISLT B=0 C=1
bc_buf[3] = kshort(0, 1)                               -- executed
bc_buf[4] = 76
check("islt_true", 1, run_program(bc_buf, 5))

-- Test 10: ISLT — 5 < 3 → false, skip next, return 5
bc_buf[0] = kshort(0, 5); bc_buf[1] = kshort(1, 3)
bc_buf[2] = 0 + (1 * 65536)                            -- ISLT B=0 C=1
bc_buf[3] = kshort(0, 99)                              -- SKIPPED
bc_buf[4] = 76
check("islt_false", 5, run_program(bc_buf, 5))

-- Test 11: ISGE — 5 >= 3 → true, don't skip, return 1
bc_buf[0] = kshort(0, 5); bc_buf[1] = kshort(1, 3)
bc_buf[2] = 1 + (1 * 65536)
bc_buf[3] = kshort(0, 1)
bc_buf[4] = 76
check("isge_true", 1, run_program(bc_buf, 5))

-- Test 12: ISEQV — 7 == 7 → true, don't skip, return 1
bc_buf[0] = kshort(0, 7); bc_buf[1] = kshort(1, 7)
bc_buf[2] = 4 + (1 * 65536)
bc_buf[3] = kshort(0, 1)
bc_buf[4] = 76
check("iseqv_true", 1, run_program(bc_buf, 5))

-- Test 13: ISNEV — 7 != 3 → true, don't skip, return 1
bc_buf[0] = kshort(0, 7); bc_buf[1] = kshort(1, 3)
bc_buf[2] = 5 + (1 * 65536)
bc_buf[3] = kshort(0, 1)
bc_buf[4] = 76
check("isnev_true", 1, run_program(bc_buf, 5))

-- Test 14: ADDVN — slot0(=3) + lit(7) = 10
bc_buf[0] = kshort(0, 3)
bc_buf[1] = 22 + (0 * 256) + (7 * 65536)
bc_buf[2] = 76
check("addvn", 10, run_program(bc_buf, 3))

-- Test 15: ADDNV — lit(3) + slot0(=7) = 10
bc_buf[0] = kshort(0, 7)
bc_buf[1] = 27 + (0 * 256) + (3 * 65536)
bc_buf[2] = 76
check("addnv", 10, run_program(bc_buf, 3))

-- Test 16: KPRI nil — read tag from stack (LUA_TNIL = 0)
bc_buf[0] = 43 + (0 * 256)                              -- KPRI A=0 D=0 (nil)
bc_buf[1] = 76
ffi.fill(stack_buf, StackBytes, 0)
dispatch:get("vm_interp_run")(state_ptr, bc_ptr, 0, 0)
check("kpri_nil", 0, ffi.cast("int32_t *", stack_buf)[0])

-- Test 17: KPRI true — tag value (LUA_TTRUE = 2)
bc_buf[0] = 43 + (0 * 256) + (2 * 65536)               -- KPRI A=0 D=2 (true)
bc_buf[1] = 76
ffi.fill(stack_buf, StackBytes, 0)
dispatch:get("vm_interp_run")(state_ptr, bc_ptr, 0, 0)
check("kpri_true", 2, ffi.cast("int32_t *", stack_buf)[0])

-- Test 18: TGETV array hit. stack[1]=table, stack[2]=key 1, result in stack[0].
do
    local tab_buf = ffi.new("uint8_t[?]", 56)
    local arr_buf = ffi.new("uint8_t[?]", 16 * 4)
    local tab64 = ffi.cast("uint64_t *", tab_buf)
    local tab32 = ffi.cast("uint32_t *", tab_buf)
    local arr32 = ffi.cast("int32_t *", arr_buf)
    local arr64 = ffi.cast("int64_t *", arr_buf)
    tab64[2] = tonumber(ffi.cast("uintptr_t", arr_buf)) -- array ptr @ offset 16
    tab32[12] = 4                                      -- asize @ offset 48
    arr32[0] = 3; arr64[1] = 1234                      -- array[1] = int 1234
    bc_buf[0] = tgetv(0, 1, 2)
    local got = run_program_with_setup(bc_buf, 1, function()
        local st32 = ffi.cast("int32_t *", stack_buf)
        local st64 = ffi.cast("int64_t *", stack_buf)
        st32[4] = 8; st64[3] = tonumber(ffi.cast("uintptr_t", tab_buf)) -- slot1 table
        st32[8] = 3; st64[5] = 1                                      -- slot2 key int 1
    end)
    check("tgetv_array", 1234, got)
end

-- Test 19: TSETV array hit then TGETV reads the stored value.
do
    local tab_buf = ffi.new("uint8_t[?]", 56)
    local arr_buf = ffi.new("uint8_t[?]", 16 * 4)
    local tab64 = ffi.cast("uint64_t *", tab_buf)
    local tab32 = ffi.cast("uint32_t *", tab_buf)
    tab64[2] = tonumber(ffi.cast("uintptr_t", arr_buf))
    tab32[12] = 4
    bc_buf[0] = tsetv(3, 1, 2) -- value slot3, table slot1, key slot2
    bc_buf[1] = tgetv(0, 1, 2)
    local got = run_program_with_setup(bc_buf, 2, function()
        local st32 = ffi.cast("int32_t *", stack_buf)
        local st64 = ffi.cast("int64_t *", stack_buf)
        st32[4] = 8;  st64[3] = tonumber(ffi.cast("uintptr_t", tab_buf)) -- slot1 table
        st32[8] = 3;  st64[5] = 2                                      -- slot2 key int 2
        st32[12] = 3; st64[7] = 5678                                   -- slot3 value
    end)
    check("tsetv_then_get", 5678, got)
end

-- Test 20: TGETV array miss yields nil tag in destination.
do
    local tab_buf = ffi.new("uint8_t[?]", 56)
    local arr_buf = ffi.new("uint8_t[?]", 16 * 1)
    local tab64 = ffi.cast("uint64_t *", tab_buf)
    local tab32 = ffi.cast("uint32_t *", tab_buf)
    tab64[2] = tonumber(ffi.cast("uintptr_t", arr_buf))
    tab32[12] = 1
    bc_buf[0] = tgetv(0, 1, 2)
    run_program_with_setup(bc_buf, 1, function()
        local st32 = ffi.cast("int32_t *", stack_buf)
        local st64 = ffi.cast("int64_t *", stack_buf)
        st32[4] = 8; st64[3] = tonumber(ffi.cast("uintptr_t", tab_buf))
        st32[8] = 3; st64[5] = 2
    end)
    check("tgetv_miss_nil", 0, ffi.cast("int32_t *", stack_buf)[0])
end

-- Test 21: TGETV hash hit for an existing non-array integer key.
do
    local tab_buf = ffi.new("uint8_t[?]", 56)
    local node_buf = ffi.new("uint8_t[?]", 48)
    local tab64 = ffi.cast("uint64_t *", tab_buf)
    local tab32 = ffi.cast("uint32_t *", tab_buf)
    local node32 = ffi.cast("int32_t *", node_buf)
    local node64 = ffi.cast("int64_t *", node_buf)
    tab64[5] = tonumber(ffi.cast("uintptr_t", node_buf)) -- node ptr @ offset 40
    tab32[13] = 0                                      -- hmask 0: one bucket
    node32[0] = 3; node64[1] = 4321                    -- val int 4321
    node32[4] = 3; node64[3] = 99                      -- key int 99
    bc_buf[0] = tgetv(0, 1, 2)
    local got = run_program_with_setup(bc_buf, 1, function()
        local st32 = ffi.cast("int32_t *", stack_buf)
        local st64 = ffi.cast("int64_t *", stack_buf)
        st32[4] = 8; st64[3] = tonumber(ffi.cast("uintptr_t", tab_buf))
        st32[8] = 3; st64[5] = 99
    end)
    check("tgetv_hash", 4321, got)
end

-- Test 22: TSETV updates an existing hash node.
do
    local tab_buf = ffi.new("uint8_t[?]", 56)
    local node_buf = ffi.new("uint8_t[?]", 48)
    local tab64 = ffi.cast("uint64_t *", tab_buf)
    local tab32 = ffi.cast("uint32_t *", tab_buf)
    local node32 = ffi.cast("int32_t *", node_buf)
    local node64 = ffi.cast("int64_t *", node_buf)
    tab64[5] = tonumber(ffi.cast("uintptr_t", node_buf))
    tab32[13] = 0
    node32[0] = 3; node64[1] = 111
    node32[4] = 3; node64[3] = 99
    bc_buf[0] = tsetv(3, 1, 2)
    bc_buf[1] = tgetv(0, 1, 2)
    local got = run_program_with_setup(bc_buf, 2, function()
        local st32 = ffi.cast("int32_t *", stack_buf)
        local st64 = ffi.cast("int64_t *", stack_buf)
        st32[4] = 8;  st64[3] = tonumber(ffi.cast("uintptr_t", tab_buf))
        st32[8] = 3;  st64[5] = 99
        st32[12] = 3; st64[7] = 8765
    end)
    check("tsetv_hash", 8765, got)
end

-- Test 23: TGETB byte literal key.
do
    local tab_buf = ffi.new("uint8_t[?]", 56)
    local arr_buf = ffi.new("uint8_t[?]", 16 * 4)
    local tab64 = ffi.cast("uint64_t *", tab_buf)
    local tab32 = ffi.cast("uint32_t *", tab_buf)
    local arr32 = ffi.cast("int32_t *", arr_buf)
    local arr64 = ffi.cast("int64_t *", arr_buf)
    tab64[2] = tonumber(ffi.cast("uintptr_t", arr_buf))
    tab32[12] = 4
    arr32[4] = 3; arr64[3] = 2222 -- array key 2 -> slot 1
    bc_buf[0] = tgetb(0, 1, 2)
    local got = run_program_with_setup(bc_buf, 1, function()
        local st32 = ffi.cast("int32_t *", stack_buf)
        local st64 = ffi.cast("int64_t *", stack_buf)
        st32[4] = 8; st64[3] = tonumber(ffi.cast("uintptr_t", tab_buf))
    end)
    check("tgetb_array", 2222, got)
end

-- Test 24: TSETB byte literal key.
do
    local tab_buf = ffi.new("uint8_t[?]", 56)
    local arr_buf = ffi.new("uint8_t[?]", 16 * 4)
    local tab64 = ffi.cast("uint64_t *", tab_buf)
    local tab32 = ffi.cast("uint32_t *", tab_buf)
    tab64[2] = tonumber(ffi.cast("uintptr_t", arr_buf))
    tab32[12] = 4
    bc_buf[0] = tsetb(2, 1, 3) -- value slot2, table slot1, key literal 3
    bc_buf[1] = tgetb(0, 1, 3)
    local got = run_program_with_setup(bc_buf, 2, function()
        local st32 = ffi.cast("int32_t *", stack_buf)
        local st64 = ffi.cast("int64_t *", stack_buf)
        st32[4] = 8; st64[3] = tonumber(ffi.cast("uintptr_t", tab_buf))
        st32[8] = 3; st64[5] = 3333
    end)
    check("tsetb_then_get", 3333, got)
end

-- Cleanup
dispatch:free()

if failed > 0 then
    error(string.format("%d interpreter tests FAILED", failed))
end
print(string.format("\nAll %d interpreter smoke tests passed", passed))
