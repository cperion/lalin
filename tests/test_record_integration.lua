-- tests/test_record_integration.lua
-- Integration test for the trace recorder regions.
-- Tests trace_init, rec_sload (with type guard), and rec_arith
-- (constant folding + instruction emission + commutative norm).
package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local bit = require("bit")
local Run = require("moonlift.mlua_run")

local rec_mv = Run.dofile("mlua/luajitvm/jit/record.mlua")
local rec    = rec_mv:compile()

local trace_init_fn   = rec:get("trace_init_test")
local rec_sload_fn    = rec:get("rec_sload_test")
local rec_arith_fn    = rec:get("rec_arith_test")
local rec_cmp_fn      = rec:get("rec_cmp_test")
local rec_loop_fn     = rec:get("rec_loop_test")

-- =========================================================================
-- Allocate buffers
-- =========================================================================
local IR_SLOTS = 0x8000 + 256
local J_BUF    = ffi.new("uint8_t[?]", 32)
local TR_BUF   = ffi.new("uint8_t[?]", 104)
local IR_BUF   = ffi.new("uint8_t[?]", IR_SLOTS * 8)
local REFS_BUF = ffi.new("int32_t[?]", 32)   -- slot_refs: 32 stack slots
local STACK    = ffi.new("uint8_t[?]", 256 * 16)  -- fake Lua stack (16 bytes/TValue)

local J_ptr    = ffi.cast("void *", J_BUF)
local TR_ptr   = ffi.cast("void *", TR_BUF)
local IR_ptr   = ffi.cast("void *", IR_BUF)
local REFS_ptr = ffi.cast("void *", REFS_BUF)
local STACK_ptr= ffi.cast("void *", STACK)

local J_u64  = ffi.cast("uint64_t *", J_BUF)
local TR_u64 = ffi.cast("uint64_t *", TR_BUF)
local IR_u64 = ffi.cast("uint64_t *", IR_BUF)
local J_u32  = ffi.cast("uint32_t *", J_BUF)
local STACK_i32 = ffi.cast("int32_t *", STACK)

-- Wire: J.cur.trace → TR, TR.irbuf (offset 24) → IR
J_u64[0]  = ffi.cast("uintptr_t", TR_ptr)
TR_u64[3] = ffi.cast("uintptr_t", IR_ptr)

-- Helpers
local function fld_op(u)   return tonumber(bit.band(bit.rshift(u, 40), 0xFF)) end
local function fld_type(u) return tonumber(bit.band(bit.rshift(u, 32), 0xFF)) end
local function fld_op1(u)  return tonumber(bit.band(u, 0xFFFF)) end
local function fld_op2(u)  return tonumber(bit.band(bit.rshift(u, 16), 0xFFFF)) end

local passed, failed = 0, 0
local function check(name, expected, actual)
    local e = tonumber(expected); local a = tonumber(actual)
    if e == a then
        passed = passed + 1
        io.write(string.format("  OK   %-44s = %d\n", name, a))
    else
        failed = failed + 1
        io.write(string.format("  FAIL %-44s expected %d, got %d\n", name, e, a))
    end
end

-- =========================================================================
-- Test 1: trace_init
-- =========================================================================
print("--- trace_init ---")
local r = trace_init_fn(J_ptr)
check("trace_init returns 0", 0, r)
check("nins reset to 1",  1,      J_u64[1])
check("nk reset to 0x8000", 0x8000, J_u64[2])
check("nsnap reset to 0",   0,    J_u32[6])

-- =========================================================================
-- Test 2: rec_sload — emit SLOAD guard for integer slot
-- =========================================================================
print("\n--- rec_sload ---")

-- Place a fake TValue on the Lua stack at slot 0.
-- TValue layout: [tag:i32 at +0][pad:i32 at +4][payload:i64 at +8].
-- Stack slot 0 → byte offset 0. tag at byte 0 = i32 index 0.
STACK_i32[0] = 3   -- slot 0 tag = LUA_TINT

local ref0 = rec_sload_fn(J_ptr, REFS_ptr, STACK_ptr, 0)
print(string.format("  sload ref = 0x%x", ref0))
check("sload ref = 0x8001",  0x8001, ref0)
check("slot_refs[0] updated", 0x8001, REFS_BUF[0])
-- IRIns at slot 1: op=IR_SLOAD(31), t=IRT_INT|IRT_GUARD=0x99, op1=0, op2=0
local ir0 = IR_u64[1]
check("IR[1] op = IR_SLOAD",  31, fld_op(ir0))
check("IR[1] type has GUARD", 1,  bit.band(fld_type(ir0), 0x80) ~= 0 and 1 or 0)
check("IR[1] op1 = slot 0",   0,  fld_op1(ir0))
check("nins = 2 after sload", 2,  J_u64[1])

-- Emit sload for slot 1 too
STACK_i32[4] = 3  -- slot 1 tag (4 i32s per TValue, so slot 1 starts at index 4)
local ref1 = rec_sload_fn(J_ptr, REFS_ptr, STACK_ptr, 1)
check("sload slot1 ref = 0x8002", 0x8002, ref1)
check("slot_refs[1] updated",     0x8002, REFS_BUF[1])

-- =========================================================================
-- Test 3: rec_arith — ADD of two instruction refs
-- =========================================================================
print("\n--- rec_arith: ADD of two SLOADs ---")
local ref_add = rec_arith_fn(J_ptr, REFS_ptr, 0, 1, 0, 2, 10)  -- lhs=slot0, rhs=slot1, dst=slot2, op=IR_ADD
print(string.format("  add ref = 0x%x", ref_add))
check("add ref = 0x8003",     0x8003, ref_add)
check("slot_refs[2] updated", 0x8003, REFS_BUF[2])
local ir_add = IR_u64[3]
check("IR[3] op = IR_ADD",  10,     fld_op(ir_add))
check("IR[3] type = IRT_INT", 19,   fld_type(ir_add))
check("IR[3] op1 = 0x8001",  0x8001, fld_op1(ir_add))
check("IR[3] op2 = 0x8002",  0x8002, fld_op2(ir_add))

-- =========================================================================
-- Test 4: rec_arith — constant folding path (rhs is a constant literal)
-- =========================================================================
print("\n--- rec_arith: ADD with constant ---")
-- ADD slot0 + 100 → should allocate KINT(100) then fold? No: slot0 is instruction ref (0x8001)
-- so op1 is an instruction ref, op2 will be KINT(100). Not both constants → no fold, emit IR_ADD
local nk_before = tonumber(J_u64[2])
local ref_addk = rec_arith_fn(J_ptr, REFS_ptr, 0, -1, 100, 3, 10)  -- rhs_slot=-1 means constant 100
check("add_k ref >= 0x8000", 1, ref_addk >= 0x8000 and 1 or 0)
-- A KINT(100) was allocated below REF_BIAS
check("nk decremented", nk_before - 1, J_u64[2])
local kref = tonumber(J_u64[2])  -- slot of the new constant (nk after alloc)
local ir_k = IR_u64[kref]
check("KINT opcode = 60", 60, fld_op(ir_k))
check("KINT value = 100", 100, fld_op1(ir_k))
check("slot_refs[3] updated", ref_addk, REFS_BUF[3])

-- =========================================================================
-- Test 5: rec_arith — pure constant fold (two constants)
-- =========================================================================
print("\n--- rec_arith: constant fold ---")
-- First emit two KINT constants by calling rec_arith with rhs_slot=-1 for both operands
-- We need slot_refs[4] = a constant ref and slot_refs[5] = another constant ref
-- Manually set slot_refs to known constant refs (from previous alloc) and do ADD(k1, k2)
-- After test 4, nk is at some value. Let's alloc two more constants via rec_arith with
-- a dummy sload ref as lhs but rhs as constant, then do a fold test on two constant slots.
-- Simpler: set slot_refs[4] and [5] to manually allocated constant refs then call rec_arith.
-- Let's just allocate two KINT constants for 3 and 4 by setting slot_refs manually.
-- To do that we need the slot index. Let's read the current nk and decrement manually:
local nk1 = tonumber(J_u64[2])
-- Manually write KINT(3) at nk1-1 and KINT(4) at nk1-2
IR_u64[nk1 - 1] = ffi.cast("uint64_t", 3 + 19 * (2^32) + ffi.cast("uint64_t", 60) * (2^40))
IR_u64[nk1 - 2] = ffi.cast("uint64_t", 4 + 19 * (2^32) + ffi.cast("uint64_t", 60) * (2^40))
J_u64[2] = nk1 - 2   -- update nk to reflect manually allocated constants
REFS_BUF[4] = nk1 - 1  -- slot 4 = KINT(3)
REFS_BUF[5] = nk1 - 2  -- slot 5 = KINT(4)

local nins_before = tonumber(J_u64[1])
local ref_fold = rec_arith_fn(J_ptr, REFS_ptr, 4, 5, 0, 6, 10)  -- ADD(KINT(3), KINT(4))
-- Should constant-fold to KINT(7), nins should NOT change
check("nins unchanged after const fold", nins_before, J_u64[1])
check("fold result < REF_BIAS",          1, ref_fold < 0x8000 and 1 or 0)
local ir_fold = IR_u64[ref_fold]
check("folded KINT opcode = 60", 60, fld_op(ir_fold))
check("folded KINT value = 7",   7,  fld_op1(ir_fold))
check("slot_refs[6] = fold ref", ref_fold, REFS_BUF[6])

-- =========================================================================
-- Test 6: commutative normalization
-- =========================================================================
print("\n--- rec_arith: commutative normalization ---")
-- ADD(INSTR2, INSTR1): op1=0x8002 > op2=0x8001 → should swap to (0x8001, 0x8002)
REFS_BUF[7] = 0x8002
REFS_BUF[8] = 0x8001
local ref_norm = rec_arith_fn(J_ptr, REFS_ptr, 7, 8, 0, 9, 10)
check("norm ref emitted", 1, ref_norm >= 0x8000 and 1 or 0)
local ir_norm = IR_u64[ref_norm - 0x8000]
check("norm IR op1 = 0x8001 (smaller)", 0x8001, fld_op1(ir_norm))
check("norm IR op2 = 0x8002 (larger)",  0x8002, fld_op2(ir_norm))

-- =========================================================================
-- Test 7: comparison guard recording
-- =========================================================================
print("\n--- rec_cmp: LT guard ---")
local ref_cmp = rec_cmp_fn(J_ptr, REFS_ptr, 0, 1, 20) -- IR_LT(slot0, slot1)
check("cmp ref emitted", 1, ref_cmp >= 0x8000 and 1 or 0)
local ir_cmp = IR_u64[ref_cmp - 0x8000]
check("cmp IR op = IR_LT", 20, fld_op(ir_cmp))
check("cmp IR has GUARD", 1, bit.band(fld_type(ir_cmp), 0x80) ~= 0 and 1 or 0)
check("cmp IR op1 = slot0 ref", REFS_BUF[0], fld_op1(ir_cmp))
check("cmp IR op2 = slot1 ref", REFS_BUF[1], fld_op2(ir_cmp))

-- =========================================================================
-- Test 8: loop marker recording
-- =========================================================================
print("\n--- rec_loop: LOOP marker ---")
local ref_loop = rec_loop_fn(J_ptr)
check("loop ref emitted", 1, ref_loop >= 0x8000 and 1 or 0)
local ir_loop = IR_u64[ref_loop - 0x8000]
check("loop IR op = IR_LOOP", 80, fld_op(ir_loop))
check("loop IR op1 = 0", 0, fld_op1(ir_loop))

rec:free()
print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
print("All recorder integration tests passed")
