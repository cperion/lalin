package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local Host = require("moonlift.mlua_run")
local T = require("moonlift.mom.back.back_tags")

local function compile(path)
    local chunk = Host.loadfile(path)
    local mod = chunk()
    local result = mod:compile()
    return result
end

-- ── Compile back_abi.mlua ─────────────────────────────────────────────
local abi_mod = compile("lua/moonlift/mom/back/back_abi.mlua")
local scalar_to_back = abi_mod:get("mb_core_scalar_to_back")
local abi_classify = abi_mod:get("mb_abi_classify")
local abi_param_classify = abi_mod:get("mb_abi_param_classify")
local abi_result_classify = abi_mod:get("mb_abi_result_classify")
local type_to_back_scalar = abi_mod:get("mb_abi_type_to_back_scalar")

local ok_count = 0
local fail_count = 0

local function check(cond, msg)
    if cond then
        ok_count = ok_count + 1
    else
        fail_count = fail_count + 1
        print("FAIL: " .. msg)
    end
end

-- ── mb_core_scalar_to_back ────────────────────────────────────────────

check(scalar_to_back(T.ScalarVoid) == T.BackVoid, "ScalarVoid → BackVoid")
check(scalar_to_back(T.ScalarBool) == T.BackBool, "ScalarBool → BackBool")
check(scalar_to_back(T.ScalarI8) == T.BackI8, "ScalarI8 → BackI8")
check(scalar_to_back(T.ScalarI16) == T.BackI16, "ScalarI16 → BackI16")
check(scalar_to_back(T.ScalarI32) == T.BackI32, "ScalarI32 → BackI32")
check(scalar_to_back(T.ScalarI64) == T.BackI64, "ScalarI64 → BackI64")
check(scalar_to_back(T.ScalarU8) == T.BackU8, "ScalarU8 → BackU8")
check(scalar_to_back(T.ScalarU16) == T.BackU16, "ScalarU16 → BackU16")
check(scalar_to_back(T.ScalarU32) == T.BackU32, "ScalarU32 → BackU32")
check(scalar_to_back(T.ScalarU64) == T.BackU64, "ScalarU64 → BackU64")
check(scalar_to_back(T.ScalarF32) == T.BackF32, "ScalarF32 → BackF32")
check(scalar_to_back(T.ScalarF64) == T.BackF64, "ScalarF64 → BackF64")
check(scalar_to_back(T.ScalarRawPtr) == T.BackPtr, "ScalarRawPtr → BackPtr")
check(scalar_to_back(T.ScalarIndex) == T.BackIndex, "ScalarIndex → BackIndex")
check(scalar_to_back(-1) == 0, "invalid scalar → 0")

-- ── mb_abi_classify ───────────────────────────────────────────────────

local bs = ffi.new("int32_t[1]")

-- TY_SCALAR(Void) → ABI_IGNORE
bs[0] = -1
local ac = abi_classify(T.TY_SCALAR, T.ScalarVoid, bs)
check(ac == T.ABI_IGNORE, "TY_SCALAR(ScalarVoid) → ABI_IGNORE")
check(bs[0] == -1, "ABI_IGNORE leaves out_bs unchanged")

-- TY_SCALAR(I32) → ABI_DIRECT(BackI32)
bs[0] = -1
ac = abi_classify(T.TY_SCALAR, T.ScalarI32, bs)
check(ac == T.ABI_DIRECT, "TY_SCALAR(ScalarI32) → ABI_DIRECT")
check(bs[0] == T.BackI32, "TY_SCALAR → BackI32")

-- TY_SCALAR(Bool) → ABI_DIRECT(BackBool)
bs[0] = -1
ac = abi_classify(T.TY_SCALAR, T.ScalarBool, bs)
check(ac == T.ABI_DIRECT, "TY_SCALAR(ScalarBool) → ABI_DIRECT")
check(bs[0] == T.BackBool, "TY_SCALAR → BackBool")

-- TY_PTR → ABI_DIRECT(BackPtr)
bs[0] = -1
ac = abi_classify(T.TY_PTR, 0, bs)
check(ac == T.ABI_DIRECT, "TY_PTR → ABI_DIRECT")
check(bs[0] == T.BackPtr, "TY_PTR → BackPtr")

-- TY_FUNC → ABI_DIRECT(BackPtr)
bs[0] = -1
ac = abi_classify(T.TY_FUNC, 0, bs)
check(ac == T.ABI_DIRECT, "TY_FUNC → ABI_DIRECT")
check(bs[0] == T.BackPtr, "TY_FUNC → BackPtr")

-- TY_CLOSURE → ABI_DIRECT(BackPtr)
bs[0] = -1
ac = abi_classify(T.TY_CLOSURE, 0, bs)
check(ac == T.ABI_DIRECT, "TY_CLOSURE → ABI_DIRECT")
check(bs[0] == T.BackPtr, "TY_CLOSURE → BackPtr")

-- TY_SLICE → ABI_DESCRIPTOR(BackPtr)
bs[0] = -1
ac = abi_classify(T.TY_SLICE, 0, bs)
check(ac == T.ABI_DESCRIPTOR, "TY_SLICE → ABI_DESCRIPTOR")
check(bs[0] == T.BackPtr, "TY_SLICE → BackPtr")

-- TY_VIEW → ABI_DESCRIPTOR(BackPtr)
bs[0] = -1
ac = abi_classify(T.TY_VIEW, 0, bs)
check(ac == T.ABI_DESCRIPTOR, "TY_VIEW → ABI_DESCRIPTOR")
check(bs[0] == T.BackPtr, "TY_VIEW → BackPtr")

-- TY_CFUNC_PTR → ABI_DIRECT(BackPtr)
bs[0] = -1
ac = abi_classify(T.TY_CFUNC_PTR, 0, bs)
check(ac == T.ABI_DIRECT, "TY_CFUNC_PTR → ABI_DIRECT")
check(bs[0] == T.BackPtr, "TY_CFUNC_PTR → BackPtr")

-- TY_ARRAY → ABI_INDIRECT
bs[0] = -1
ac = abi_classify(T.TY_ARRAY, 0, bs)
check(ac == T.ABI_INDIRECT, "TY_ARRAY → ABI_INDIRECT")
check(bs[0] == -1, "ABI_INDIRECT leaves out_bs unchanged")

-- TY_NAMED → ABI_UNKNOWN
bs[0] = -1
ac = abi_classify(T.TY_NAMED, 0, bs)
check(ac == T.ABI_UNKNOWN, "TY_NAMED → ABI_UNKNOWN")
check(bs[0] == -1, "ABI_UNKNOWN leaves out_bs unchanged")

-- TY_SLOT → ABI_UNKNOWN
ac = abi_classify(T.TY_SLOT, 0, bs)
check(ac == T.ABI_UNKNOWN, "TY_SLOT → ABI_UNKNOWN")

-- TY_CTYPE → ABI_UNKNOWN
ac = abi_classify(T.TY_CTYPE, 0, bs)
check(ac == T.ABI_UNKNOWN, "TY_CTYPE → ABI_UNKNOWN")

-- Invalid tag → ABI_UNKNOWN
ac = abi_classify(99, 0, bs)
check(ac == T.ABI_UNKNOWN, "invalid type tag → ABI_UNKNOWN")

-- ── mb_abi_param_classify ─────────────────────────────────────────────

-- TY_VIEW → ABI_PARAM_VIEW
bs[0] = -1
local pc = abi_param_classify(T.TY_VIEW, 0, bs)
check(pc == T.ABI_PARAM_VIEW, "TY_VIEW → ABI_PARAM_VIEW")
check(bs[0] == -1, "ABI_PARAM_VIEW leaves out_bs unchanged")

-- TY_SCALAR(Void) → ABI_PARAM_REJECTED
bs[0] = -1
pc = abi_param_classify(T.TY_SCALAR, T.ScalarVoid, bs)
check(pc == T.ABI_PARAM_REJECTED, "TY_SCALAR(Void) → ABI_PARAM_REJECTED")
check(bs[0] == -1, "ABI_PARAM_REJECTED leaves out_bs unchanged")

-- TY_SCALAR(I32) → ABI_PARAM_SCALAR(BackI32)
bs[0] = -1
pc = abi_param_classify(T.TY_SCALAR, T.ScalarI32, bs)
check(pc == T.ABI_PARAM_SCALAR, "TY_SCALAR(I32) → ABI_PARAM_SCALAR")
check(bs[0] == T.BackI32, "TY_SCALAR → BackI32")

-- TY_SCALAR(F64) → ABI_PARAM_SCALAR(BackF64)
bs[0] = -1
pc = abi_param_classify(T.TY_SCALAR, T.ScalarF64, bs)
check(pc == T.ABI_PARAM_SCALAR, "TY_SCALAR(F64) → ABI_PARAM_SCALAR")
check(bs[0] == T.BackF64, "TY_SCALAR(F64) → BackF64")

-- TY_PTR → ABI_PARAM_REJECTED (not a recognized param type)
bs[0] = -1
pc = abi_param_classify(T.TY_PTR, 0, bs)
check(pc == T.ABI_PARAM_REJECTED, "TY_PTR → ABI_PARAM_REJECTED")

-- TY_ARRAY → ABI_PARAM_REJECTED
pc = abi_param_classify(T.TY_ARRAY, 0, bs)
check(pc == T.ABI_PARAM_REJECTED, "TY_ARRAY → ABI_PARAM_REJECTED")

-- ── mb_abi_result_classify ────────────────────────────────────────────

-- TY_SCALAR(Void) → ABI_RESULT_VOID
bs[0] = -1
local rc = abi_result_classify(T.TY_SCALAR, T.ScalarVoid, bs)
check(rc == T.ABI_RESULT_VOID, "TY_SCALAR(Void) → ABI_RESULT_VOID")
check(bs[0] == -1, "ABI_RESULT_VOID leaves out_bs unchanged")

-- TY_SCALAR(I32) → ABI_RESULT_SCALAR(BackI32)
bs[0] = -1
rc = abi_result_classify(T.TY_SCALAR, T.ScalarI32, bs)
check(rc == T.ABI_RESULT_SCALAR, "TY_SCALAR(I32) → ABI_RESULT_SCALAR")
check(bs[0] == T.BackI32, "TY_SCALAR → BackI32")

-- TY_SCALAR(Bool) → ABI_RESULT_SCALAR(BackBool)
bs[0] = -1
rc = abi_result_classify(T.TY_SCALAR, T.ScalarBool, bs)
check(rc == T.ABI_RESULT_SCALAR, "TY_SCALAR(Bool) → ABI_RESULT_SCALAR")
check(bs[0] == T.BackBool, "TY_SCALAR(Bool) → BackBool")

-- TY_VIEW → ABI_RESULT_VIEW(BackPtr)
bs[0] = -1
rc = abi_result_classify(T.TY_VIEW, 0, bs)
check(rc == T.ABI_RESULT_VIEW, "TY_VIEW → ABI_RESULT_VIEW")
check(bs[0] == T.BackPtr, "TY_VIEW → BackPtr")

-- TY_PTR → ABI_RESULT_REJECTED
bs[0] = -1
rc = abi_result_classify(T.TY_PTR, 0, bs)
check(rc == T.ABI_RESULT_REJECTED, "TY_PTR → ABI_RESULT_REJECTED")

-- TY_ARRAY → ABI_RESULT_REJECTED
rc = abi_result_classify(T.TY_ARRAY, 0, bs)
check(rc == T.ABI_RESULT_REJECTED, "TY_ARRAY → ABI_RESULT_REJECTED")

-- Invalid → ABI_RESULT_REJECTED
rc = abi_result_classify(99, 0, bs)
check(rc == T.ABI_RESULT_REJECTED, "invalid type → ABI_RESULT_REJECTED")

-- ── mb_abi_type_to_back_scalar ────────────────────────────────────────

check(type_to_back_scalar(T.TY_SCALAR, T.ScalarI32) == T.BackI32, "TY_SCALAR(I32) → BackI32")
check(type_to_back_scalar(T.TY_SCALAR, T.ScalarF64) == T.BackF64, "TY_SCALAR(F64) → BackF64")
check(type_to_back_scalar(T.TY_SCALAR, T.ScalarVoid) == T.BackVoid, "TY_SCALAR(Void) → BackVoid")
check(type_to_back_scalar(T.TY_PTR, 0) == T.BackPtr, "TY_PTR → BackPtr")
check(type_to_back_scalar(T.TY_FUNC, 0) == T.BackPtr, "TY_FUNC → BackPtr")
check(type_to_back_scalar(T.TY_CFUNC_PTR, 0) == T.BackPtr, "TY_CFUNC_PTR → BackPtr")
check(type_to_back_scalar(T.TY_VIEW, 0) == 0, "TY_VIEW → 0")
check(type_to_back_scalar(T.TY_ARRAY, 0) == 0, "TY_ARRAY → 0")
check(type_to_back_scalar(T.TY_SLICE, 0) == 0, "TY_SLICE → 0")
check(type_to_back_scalar(T.TY_CLOSURE, 0) == 0, "TY_CLOSURE → 0")
check(type_to_back_scalar(T.TY_SLOT, 0) == 0, "TY_SLOT → 0")

-- ── Summary ───────────────────────────────────────────────────────────

abi_mod.artifact:free()

print(string.format("\nabi tests: %d passed, %d failed out of %d",
    ok_count, fail_count, ok_count + fail_count))
if fail_count > 0 then
    os.exit(1)
end
print("mom abi ok")
