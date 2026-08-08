/* opcode_v2_core_stencils.c — the standalone Native CPS Frame V2 core bank.
 *
 * Compiled ONLY against opcode_value_v2.h (no V1 vocabulary). Every section
 * is `lua55_v2_*` (self-selecting opcode residuals) or `lua55_cps_*` (the
 * proper-tail call family and boundary stubs). Guest CALL/TAILCALL/RETURN
 * contain no `call`; RETURN/host-tail-return contain no `ret`; only
 * lua55_cps_host_exit (and the outer FFI entry) execute `ret`.
 *
 * All exits are C tail calls (`return entry(subject);`) so GCC emits the
 * balanced callee-saved epilogue before the jmp. Reject/boundary paths
 * publish an exact invocation outcome and return through the patched
 * host-exit stub. Runtime register/constant indices are asm-guarded holes.
 */
#include "opcode_value_v2.h"
#include <string.h>

/* ---- patchable hole vocabulary (must match build_v2_bank.lua) ---------- */

#define V2_TARGET_HOLE UINT32_C(0x111)
#define V2_SOURCE_HOLE UINT32_C(0x222)
#define V2_LEFT_HOLE   UINT32_C(0x222)
#define V2_RIGHT_HOLE  UINT32_C(0x333)
#define V2_UPVALUE_HOLE UINT32_C(0x333)
#define V2_INTEGER_BITS UINT64_C(0x1122334455667788)
#define V2_FLOAT_BITS UINT64_C(0x8877665544332211)
#define V2_SPAN_HOLE UINT32_C(0x777)
#define V2_CONST_TAG UINT32_C(0x3c3b3a39)
#define V2_CONST_INT UINT64_C(0x2122232425262728)
#define V2_CONST_FLT UINT64_C(0x123456789abcdef0)
#define V2_CONST_REF UINT64_C(0x0abcdef012345679)
#define V2_INT_IMM_HOLE UINT64_C(0x1112131415161718)
#define V2_K_HOLE UINT32_C(0x71727374)
#define V2_LINK_HOLE UINT64_C(0x1122334455667788)
#define V2_TAKEN_HOLE UINT64_C(0x0badf00dcafed00d)
#define V2_TAIL_RETURN_HOLE UINT64_C(0xa1b2c3d4e5f60718)
#define V2_FALL_HOLE UINT64_C(0x0ddc0ffeebadf00d)
#define V2_BODY_HOLE UINT64_C(0x1234abcddcba4321)
#define V2_SKIP_HOLE UINT64_C(0x2345bcdeedcb5432)
#define V2_A_HOLE UINT32_C(0x01020304)
#define V2_B_HOLE UINT32_C(0x05060708)
#define V2_C_HOLE UINT32_C(0x09101112)
#define V2_PC_HOLE UINT32_C(0x13141516)
#define V2_CONTINUATION_HOLE UINT64_C(0x0e0f101112131415)
#define V2_PROTO_INDEX_HOLE UINT32_C(0x0d0e0f10)
#define V2_NUPVALS_HOLE UINT32_C(0x1d1e1f20)
#define V2_INSTACK_0 UINT32_C(0x2d2e2f30)
#define V2_IDX_0 UINT32_C(0x3d3e3f40)
#define V2_INSTACK_1 UINT32_C(0x4d4e4f50)
#define V2_IDX_1 UINT32_C(0x5d5e5f60)
#define V2_INSTACK_2 UINT32_C(0x6d6e6f70)
#define V2_IDX_2 UINT32_C(0x7d7e7f80)
#define V2_INSTACK_3 UINT32_C(0x8d8e8f90)
#define V2_IDX_3 UINT32_C(0x9d9e9fa0)
#define V2_POW_ADDRESS UINT64_C(0x5152535455565758)
#define V2_BASE_INDEX_HOLE UINT32_C(0x11223344)
#define V2_RECEIVER_HOLE UINT32_C(0x444)
#define V2_KEY_REG_HOLE UINT32_C(0x555)
#define V2_OBJECT_TARGET_HOLE UINT32_C(0x666)
#define V2_INT_KEY_HOLE UINT32_C(0x55667788)
#define V2_KEY_REF_HOLE UINT64_C(0x8172837485768778)
#define V2_ARRAY_CAP_HOLE UINT32_C(0x0a0b0c0d)
#define V2_FIELD_CAP_HOLE UINT32_C(0x1a1b1c1d)
#define V2_SETLIST_BASE_HOLE UINT32_C(0x999)
#define V2_SETLIST_COUNT_HOLE UINT32_C(0x0c0d0e0f)
#define V2_SETLIST_KEY_HOLE UINT32_C(0x1c1d1e1f)
#define V2_WANTED_HOLE UINT32_C(0x1d1e1f20)

#define FLT_ADD(a, b) ((a) + (b))
#define FLT_SUB(a, b) ((a) - (b))
#define FLT_MUL(a, b) ((a) * (b))

/* ---- exact numeric helpers (identical semantics to the shared bank) ---- */

static inline double v2_dbl_bits(uint64_t bits)
{
    double value;
    __builtin_memcpy(&value, &bits, sizeof(value));
    return value;
}

static inline int v2_magnitude_at_least_2_63(double x)
{
    uint64_t bits;
    __builtin_memcpy(&bits, &x, sizeof(bits));
    return ((bits & UINT64_C(0x7ff0000000000000)) >> 52) >= UINT64_C(0x43e);
}

static inline double v2_floor(double x)
{
    if (v2_magnitude_at_least_2_63(x)) return x;
    int64_t i = (int64_t)x;
    double t = (double)i;
    if (x < 0 && t != x) t = (double)(i - 1);
    return t;
}

static inline double v2_ceil(double x)
{
    if (v2_magnitude_at_least_2_63(x)) return x;
    int64_t i = (int64_t)x;
    double t = (double)i;
    if (x > 0 && t != x) t = (double)(i + 1);
    return t;
}

/* mode 0 = F2Ieq, 1 = F2Iceil, 2 = F2Ifloor */
static inline int v2_flt_to_int(double f, int64_t *out, int mode)
{
    if (f != f) return 0;
    double v = v2_floor(f);
    if (v != f) {
        if (mode == 0) return 0;
        if (mode == 1) v = v2_ceil(f);
    }
    if (v2_magnitude_at_least_2_63(v)) return 0;
    *out = (int64_t)v;
    return 1;
}

static inline int v2_flt_to_int_eq(double f, int64_t *out)
{
    return v2_flt_to_int(f, out, 0);
}

static inline int v2_int_fits_float(int64_t i)
{
    return (-((int64_t)1 << 52) <= i && i <= ((int64_t)1 << 52));
}

static inline int v2_eq_int_float(int64_t i, double f)
{
    int64_t fi;
    return v2_flt_to_int(f, &fi, 0) && i == fi;
}

static inline int v2_lt_int_float(int64_t i, double f)
{
    if (v2_int_fits_float(i)) return (double)i < f;
    int64_t fi;
    if (v2_flt_to_int(f, &fi, 1)) return i < fi;
    return f > 0;
}

static inline int v2_le_int_float(int64_t i, double f)
{
    if (v2_int_fits_float(i)) return (double)i <= f;
    int64_t fi;
    if (v2_flt_to_int(f, &fi, 2)) return i <= fi;
    return f > 0;
}

static inline int v2_lt_float_int(double f, int64_t i)
{
    if (v2_int_fits_float(i)) return f < (double)i;
    int64_t fi;
    if (v2_flt_to_int(f, &fi, 2)) return fi < i;
    return f < 0;
}

static inline int v2_le_float_int(double f, int64_t i)
{
    if (v2_int_fits_float(i)) return f <= (double)i;
    int64_t fi;
    if (v2_flt_to_int(f, &fi, 1)) return fi <= i;
    return f < 0;
}

static inline int64_t v2_int_add(int64_t a, int64_t b)
{ return (int64_t)((uint64_t)a + (uint64_t)b); }
static inline int64_t v2_int_sub(int64_t a, int64_t b)
{ return (int64_t)((uint64_t)a - (uint64_t)b); }
static inline int64_t v2_int_mul(int64_t a, int64_t b)
{ return (int64_t)((uint64_t)a * (uint64_t)b); }
static inline int64_t v2_int_band(int64_t a, int64_t b) { return a & b; }
static inline int64_t v2_int_bor(int64_t a, int64_t b)  { return a | b; }
static inline int64_t v2_int_bxor(int64_t a, int64_t b) { return a ^ b; }
static inline int64_t v2_int_unm(int64_t x)
{ return (int64_t)((uint64_t)0 - (uint64_t)x); }

static inline double v2_flt_unm(double x)
{
    uint64_t bits;
    double value;
    __builtin_memcpy(&bits, &x, sizeof(bits));
    bits ^= UINT64_C(0x8000000000000000);
    __builtin_memcpy(&value, &bits, sizeof(value));
    return value;
}

static inline int64_t v2_idiv(int64_t m, int64_t n)
{
    if ((uint64_t)n + 1u <= 1u)          /* n == -1 */
        return v2_int_sub(0, m);
    int64_t q = m / n;
    if ((m ^ n) < 0 && m % n != 0) q -= 1;
    return q;
}

static inline int64_t v2_mod(int64_t m, int64_t n)
{
    if ((uint64_t)n + 1u <= 1u)          /* n == -1 */
        return 0;
    int64_t r = m % n;
    if (r != 0 && (r ^ n) < 0) r += n;
    return r;
}

static inline double v2_flt_idiv(double a, double b)
{
    return v2_floor(a / b);
}

static inline double v2_fmod(double x, double y)
{
    if (y == 0) return 0.0 / 0.0;             /* fmod(x, 0) = NaN */
    double q = x / y;
    double r;
    if (v2_magnitude_at_least_2_63(q)) r = x;
    else {
        int64_t t = (int64_t)q;
        r = x - (double)t * y;
    }
    if ((r > 0) ? (y < 0) : (r < 0 && y > 0)) r += y;
    return r;
}

static inline int64_t v2_shiftl(int64_t x, int64_t y)
{
    if (y < 0) {
        if (y <= -64) return 0;
        return (int64_t)((uint64_t)x >> (uint64_t)(-y));
    } else {
        if (y >= 64) return 0;
        return (int64_t)((uint64_t)x << (uint64_t)y);
    }
}

static inline int v2_truthy(uint32_t tag)
{
    return !(tag == LUA55_VALUE_NIL || tag == LUA55_VALUE_FALSE);
}

/* ---- string helpers (V2 objects) -------------------------------------- */

static inline int v2_is_string_tag(uint32_t tag)
{
    return tag == LUA55_VALUE_SHORT_STRING || tag == LUA55_VALUE_LONG_STRING;
}

static inline int v2_string_bytes_eq(uintptr_t ra, uintptr_t rb)
{
    Lua55GuestStringV2 *a = (Lua55GuestStringV2 *)ra;
    Lua55GuestStringV2 *b = (Lua55GuestStringV2 *)rb;
    uint32_t n = a->length;
    if (b->length != n) return 0;
    uint32_t i;
    for (i = 0; i < n; i++)
        if (a->bytes[i] != b->bytes[i]) return 0;
    return 1;
}

static inline int v2_string_cmp(uintptr_t ra, uintptr_t rb)
{
    Lua55GuestStringV2 *a = (Lua55GuestStringV2 *)ra;
    Lua55GuestStringV2 *b = (Lua55GuestStringV2 *)rb;
    uint32_t n = a->length < b->length ? a->length : b->length;
    uint32_t i;
    for (i = 0; i < n; i++) {
        if (a->bytes[i] != b->bytes[i])
            return a->bytes[i] < b->bytes[i] ? -1 : 1;
    }
    return a->length < b->length ? -1 : (a->length > b->length ? 1 : 0);
}

/* ---- table helper for LEN (exact leading-run scan) --------------------- */

static inline int64_t v2_table_len(Lua55GuestTableV2 *table)
{
    uint32_t index;
    uint32_t capacity = table->array_capacity;
    Lua55ValueV2 *array = table->array_values;
    if (capacity == 0 || array == 0) return 0;
    for (index = 0; index < capacity; index++) {
        if (array[index].tag == LUA55_VALUE_NIL) break;
    }
    return (int64_t)index;
}

static inline Lua55GuestTableV2 *v2_primitive_len_table(
    Lua55NativeFrameV2 *frame, Lua55ValueV2 *source)
{
    Lua55GuestTableV2 *table;
    if (source->tag != LUA55_VALUE_TABLE || frame->invocation->heap == 0) return 0;
    table = (Lua55GuestTableV2 *)source->payload.reference;
    if (table == 0 || table->header.kind != LUA55_OBJECT_TABLE ||
        table->heap != frame->invocation->heap || table->metatable_reference != 0) return 0;
    return table;
}

/* ---- pow via the patched libm helper ----------------------------------- */

typedef double (*v2_pow_fn)(double, double);

static inline int v2_pow_exponent_is_two(double b)
{
    uint64_t bits;
    __builtin_memcpy(&bits, &b, sizeof(bits));
    return bits == UINT64_C(0x4000000000000000);
}

static inline double v2_pow(double a, double b)
{
    uint64_t addr = V2_POW_ADDRESS;
    __asm__ volatile ("" : "+r"(addr));
    v2_pow_fn fn;
    __builtin_memcpy(&fn, &addr, sizeof(fn));
    if (v2_pow_exponent_is_two(b)) return a * a;
    return fn(a, b);
}

/* ======================================================================= */
/* 0-8: movement and constants                                             */
/* ======================================================================= */

#define V2_VALUE(local, reg, hole)                                          \
    uint32_t reg = hole;                                                    \
    __asm__ volatile ("" : "+r"(reg));                                     \
    Lua55ValueV2 *local = &frame->values[reg];

STENCIL(lua55_v2_move)(Lua55NativeFrameV2 *frame)
{
    V2_VALUE(target, target_reg, V2_TARGET_HOLE)
    V2_VALUE(source, source_reg, V2_SOURCE_HOLE)
    *target = *source;
    LUA55_RESIDUAL_NEXT(frame);
}

STENCIL(lua55_v2_loadi)(Lua55NativeFrameV2 *frame)
{
    V2_VALUE(target, target_reg, V2_TARGET_HOLE)
    int64_t bits = (int64_t)V2_INTEGER_BITS;
    __asm__ volatile ("" : "+r"(bits));
    SET_TAG(target, LUA55_VALUE_INTEGER);
    target->payload.integer = bits;
    LUA55_RESIDUAL_NEXT(frame);
}

STENCIL(lua55_v2_loadf)(Lua55NativeFrameV2 *frame)
{
    V2_VALUE(target, target_reg, V2_TARGET_HOLE)
    uint64_t bits = V2_FLOAT_BITS;
    __asm__ volatile ("" : "+r"(bits));
    SET_TAG(target, LUA55_VALUE_FLOAT);
    memcpy(&target->payload.floating, &bits, sizeof(bits));
    LUA55_RESIDUAL_NEXT(frame);
}

#define V2_LOADK_BODY()                                                     \
    V2_VALUE(target, target_reg, V2_TARGET_HOLE)                            \
    uint32_t tag = V2_CONST_TAG;                                            \
    __asm__ volatile ("" : "+r"(tag));                                     \
    SET_TAG(target, tag);                                                   \
    if (tag == LUA55_VALUE_INTEGER) {                                       \
        target->payload.integer = (int64_t)V2_CONST_INT;                    \
    } else if (tag == LUA55_VALUE_FLOAT) {                                  \
        uint64_t bits = V2_CONST_FLT;                                       \
        __asm__ volatile ("" : "+r"(bits));                                \
        memcpy(&target->payload.floating, &bits, sizeof(bits));             \
    } else {                                                                \
        target->payload.reference = (uintptr_t)V2_CONST_REF;                \
    }                                                                       \
    LUA55_RESIDUAL_NEXT(frame);

STENCIL(lua55_v2_loadk)(Lua55NativeFrameV2 *frame)
{
    V2_LOADK_BODY()
}

STENCIL(lua55_v2_loadkx)(Lua55NativeFrameV2 *frame)
{
    V2_LOADK_BODY()
}

STENCIL(lua55_v2_loadfalse)(Lua55NativeFrameV2 *frame)
{
    V2_VALUE(target, target_reg, V2_TARGET_HOLE)
    SET_TAG(target, LUA55_VALUE_FALSE);
    LUA55_RESIDUAL_NEXT(frame);
}

STENCIL(lua55_v2_loadfalse_skip)(Lua55NativeFrameV2 *frame)
{
    V2_VALUE(target, target_reg, V2_TARGET_HOLE)
    SET_TAG(target, LUA55_VALUE_FALSE);
    LUA55_RESIDUAL_NEXT(frame);
}

STENCIL(lua55_v2_loadtrue)(Lua55NativeFrameV2 *frame)
{
    V2_VALUE(target, target_reg, V2_TARGET_HOLE)
    SET_TAG(target, LUA55_VALUE_TRUE);
    LUA55_RESIDUAL_NEXT(frame);
}

STENCIL(lua55_v2_loadnil)(Lua55NativeFrameV2 *frame)
{
    V2_VALUE(target, target_reg, V2_TARGET_HOLE)
    uint32_t span = V2_SPAN_HOLE;
    __asm__ volatile ("" : "+r"(span));
    uint32_t i;
    for (i = 0; i < span; i++)
        SET_TAG(&target[i], LUA55_VALUE_NIL);
    LUA55_RESIDUAL_NEXT(frame);
}

/* ======================================================================= */
/* 9-10: shared upvalue cells                                               */
/* ======================================================================= */

STENCIL(lua55_v2_getupval)(Lua55NativeFrameV2 *frame)
{
    V2_VALUE(target, target_reg, V2_TARGET_HOLE)
    V2_VALUE(upvalue, upvalue_reg, V2_UPVALUE_HOLE)
    Lua55UpvalueCellV2 *cell = frame->upvalues[upvalue_reg];
    *target = cell->state == LUA55_UPVALUE_OPEN
        ? cell->open_slot[0] : cell->closed_value;
    LUA55_RESIDUAL_NEXT(frame);
}

STENCIL(lua55_v2_setupval)(Lua55NativeFrameV2 *frame)
{
    V2_VALUE(upvalue, upvalue_reg, V2_UPVALUE_HOLE)
    V2_VALUE(source, source_reg, V2_SOURCE_HOLE)
    Lua55UpvalueCellV2 *cell = frame->upvalues[upvalue_reg];
    if (cell->state == LUA55_UPVALUE_OPEN) cell->open_slot[0] = *source;
    else cell->closed_value = *source;
    LUA55_RESIDUAL_NEXT(frame);
}

/* ======================================================================= */
/* 21-45: arithmetic, bitwise, and shifts                                   */
/* ======================================================================= */

#define V2_ARITH_RIGHT_INIT                                                 \
    Lua55ValueV2 imm_cell;                                                  \
    uint64_t imm_bits = V2_INT_IMM_HOLE;                                    \
    __asm__ volatile ("" : "+r"(imm_bits));                                \
    SET_TAG(&imm_cell, LUA55_VALUE_INTEGER);                                \
    imm_cell.payload.integer = (int64_t)imm_bits;                           \
    right = &imm_cell;

#define V2_ARITH_CONST_RIGHT                                                \
    Lua55ValueV2 const_cell;                                                \
    uint32_t const_tag = V2_CONST_TAG;                                      \
    __asm__ volatile ("" : "+r"(const_tag));                               \
    uint64_t const_int_bits = V2_CONST_INT;                                 \
    __asm__ volatile ("" : "+r"(const_int_bits));                          \
    uint64_t const_flt_bits = V2_CONST_FLT;                                 \
    __asm__ volatile ("" : "+r"(const_flt_bits));                          \
    const_cell.tag = const_tag;                                             \
    if (const_tag == LUA55_VALUE_INTEGER)                                   \
        const_cell.payload.integer = (int64_t)const_int_bits;               \
    else                                                                    \
        __builtin_memcpy(&const_cell.payload.floating, &const_flt_bits, 8); \
    right = &const_cell;

#define V2_ARITH_PROLOGUE(right_init)                                       \
    uint32_t target_index = V2_TARGET_HOLE;                                 \
    __asm__ volatile ("" : "+r"(target_index));                            \
    uint32_t left_index = V2_LEFT_HOLE;                                     \
    __asm__ volatile ("" : "+r"(left_index));                              \
    uint32_t right_index = V2_RIGHT_HOLE;                                   \
    __asm__ volatile ("" : "+r"(right_index));                             \
    Lua55ValueV2 *target = &frame->values[target_index];                    \
    Lua55ValueV2 *left = &frame->values[left_index];                        \
    Lua55ValueV2 *right = &frame->values[right_index];                      \
    right_init;

#define V2_BIN(name, intfn, flt_left, flt_right, flt_both, right_init)      \
STENCIL(lua55_v2_##name)(Lua55NativeFrameV2 *frame)                         \
{                                                                           \
    V2_ARITH_PROLOGUE(right_init)                                           \
    if (left->tag == LUA55_VALUE_INTEGER && right->tag == LUA55_VALUE_INTEGER) { \
        SET_TAG(target, LUA55_VALUE_INTEGER);                               \
        target->payload.integer = intfn(left->payload.integer, right->payload.integer); \
    } else if (left->tag == LUA55_VALUE_INTEGER && right->tag == LUA55_VALUE_FLOAT) { \
        SET_TAG(target, LUA55_VALUE_FLOAT);                                 \
        target->payload.floating = flt_left((double)left->payload.integer, right->payload.floating); \
    } else if (left->tag == LUA55_VALUE_FLOAT && right->tag == LUA55_VALUE_INTEGER) { \
        SET_TAG(target, LUA55_VALUE_FLOAT);                                 \
        target->payload.floating = flt_right(left->payload.floating, (double)right->payload.integer); \
    } else if (left->tag == LUA55_VALUE_FLOAT && right->tag == LUA55_VALUE_FLOAT) { \
        SET_TAG(target, LUA55_VALUE_FLOAT);                                 \
        target->payload.floating = flt_both(left->payload.floating, right->payload.floating); \
    } else { V2_REJECT(frame, LUA55_V2_REJECT_UNSUPPORTED_METAMETHOD);      \
             LUA55_CPS_HOST_EXIT(frame); }                                  \
    LUA55_RESIDUAL_NEXT(frame);                                             \
}

#define V2_DIVMOD(name, intfn, fltfn, right_init)                           \
STENCIL(lua55_v2_##name)(Lua55NativeFrameV2 *frame)                         \
{                                                                           \
    V2_ARITH_PROLOGUE(right_init)                                           \
    if (left->tag == LUA55_VALUE_INTEGER && right->tag == LUA55_VALUE_INTEGER) { \
        if (right->payload.integer == 0) { V2_REJECT(frame,                  \
            LUA55_V2_REJECT_UNSUPPORTED_METAMETHOD);                        \
            LUA55_CPS_HOST_EXIT(frame); }                                   \
        SET_TAG(target, LUA55_VALUE_INTEGER);                               \
        target->payload.integer = intfn(left->payload.integer, right->payload.integer); \
    } else if (left->tag == LUA55_VALUE_INTEGER && right->tag == LUA55_VALUE_FLOAT) { \
        SET_TAG(target, LUA55_VALUE_FLOAT);                                 \
        target->payload.floating = fltfn((double)left->payload.integer, right->payload.floating); \
    } else if (left->tag == LUA55_VALUE_FLOAT && right->tag == LUA55_VALUE_INTEGER) { \
        SET_TAG(target, LUA55_VALUE_FLOAT);                                 \
        target->payload.floating = fltfn(left->payload.floating, (double)right->payload.integer); \
    } else if (left->tag == LUA55_VALUE_FLOAT && right->tag == LUA55_VALUE_FLOAT) { \
        SET_TAG(target, LUA55_VALUE_FLOAT);                                 \
        target->payload.floating = fltfn(left->payload.floating, right->payload.floating); \
    } else { V2_REJECT(frame, LUA55_V2_REJECT_UNSUPPORTED_METAMETHOD);      \
             LUA55_CPS_HOST_EXIT(frame); }                                  \
    LUA55_RESIDUAL_NEXT(frame);                                             \
}

#define V2_BITWISE(name, intfn, right_init)                                 \
STENCIL(lua55_v2_##name)(Lua55NativeFrameV2 *frame)                         \
{                                                                           \
    V2_ARITH_PROLOGUE(right_init)                                           \
    int64_t i1 = 0, i2 = 0;                                                 \
    if (left->tag == LUA55_VALUE_INTEGER) i1 = left->payload.integer;       \
    else if (left->tag == LUA55_VALUE_FLOAT && !v2_flt_to_int_eq(left->payload.floating, &i1)) \
        { V2_REJECT(frame, LUA55_V2_REJECT_UNSUPPORTED_METAMETHOD);         \
          LUA55_CPS_HOST_EXIT(frame); }                                     \
    else if (left->tag != LUA55_VALUE_FLOAT) { V2_REJECT(frame,             \
        LUA55_V2_REJECT_UNSUPPORTED_METAMETHOD);                            \
        LUA55_CPS_HOST_EXIT(frame); }                                       \
    if (right->tag == LUA55_VALUE_INTEGER) i2 = right->payload.integer;     \
    else if (right->tag == LUA55_VALUE_FLOAT && !v2_flt_to_int_eq(right->payload.floating, &i2)) \
        { V2_REJECT(frame, LUA55_V2_REJECT_UNSUPPORTED_METAMETHOD);         \
          LUA55_CPS_HOST_EXIT(frame); }                                     \
    else if (right->tag != LUA55_VALUE_FLOAT) { V2_REJECT(frame,            \
        LUA55_V2_REJECT_UNSUPPORTED_METAMETHOD);                            \
        LUA55_CPS_HOST_EXIT(frame); }                                       \
    SET_TAG(target, LUA55_VALUE_INTEGER);                                   \
    target->payload.integer = intfn(i1, i2);                                \
    LUA55_RESIDUAL_NEXT(frame);                                             \
}

#define V2_SHIFT(name, flip, right_init)                                    \
STENCIL(lua55_v2_##name)(Lua55NativeFrameV2 *frame)                         \
{                                                                           \
    V2_ARITH_PROLOGUE(right_init)                                           \
    int64_t i1 = 0, i2 = 0;                                                 \
    if (left->tag == LUA55_VALUE_INTEGER) i1 = left->payload.integer;       \
    else if (left->tag == LUA55_VALUE_FLOAT && !v2_flt_to_int_eq(left->payload.floating, &i1)) \
        { V2_REJECT(frame, LUA55_V2_REJECT_UNSUPPORTED_METAMETHOD);         \
          LUA55_CPS_HOST_EXIT(frame); }                                     \
    else if (left->tag != LUA55_VALUE_FLOAT) { V2_REJECT(frame,             \
        LUA55_V2_REJECT_UNSUPPORTED_METAMETHOD);                            \
        LUA55_CPS_HOST_EXIT(frame); }                                       \
    if (right->tag == LUA55_VALUE_INTEGER) i2 = right->payload.integer;     \
    else if (right->tag == LUA55_VALUE_FLOAT && !v2_flt_to_int_eq(right->payload.floating, &i2)) \
        { V2_REJECT(frame, LUA55_V2_REJECT_UNSUPPORTED_METAMETHOD);         \
          LUA55_CPS_HOST_EXIT(frame); }                                     \
    else if (right->tag != LUA55_VALUE_FLOAT) { V2_REJECT(frame,            \
        LUA55_V2_REJECT_UNSUPPORTED_METAMETHOD);                            \
        LUA55_CPS_HOST_EXIT(frame); }                                       \
    SET_TAG(target, LUA55_VALUE_INTEGER);                                   \
    target->payload.integer = flip ? v2_shiftl(i2, i1) : v2_shiftl(i1, i2); \
    LUA55_RESIDUAL_NEXT(frame);                                             \
}

#define V2_DIV_BODY(right_init)                                             \
    V2_ARITH_PROLOGUE(right_init)                                           \
    if (left->tag == LUA55_VALUE_INTEGER && right->tag == LUA55_VALUE_INTEGER) { \
        if (right->payload.integer == 0) { V2_REJECT(frame,                  \
            LUA55_V2_REJECT_UNSUPPORTED_METAMETHOD);                        \
            LUA55_CPS_HOST_EXIT(frame); }                                   \
        SET_TAG(target, LUA55_VALUE_FLOAT);                                 \
        target->payload.floating = (double)left->payload.integer / (double)right->payload.integer; \
    } else if (left->tag == LUA55_VALUE_INTEGER && right->tag == LUA55_VALUE_FLOAT) { \
        SET_TAG(target, LUA55_VALUE_FLOAT);                                 \
        target->payload.floating = (double)left->payload.integer / right->payload.floating; \
    } else if (left->tag == LUA55_VALUE_FLOAT && right->tag == LUA55_VALUE_INTEGER) { \
        SET_TAG(target, LUA55_VALUE_FLOAT);                                 \
        target->payload.floating = left->payload.floating / (double)right->payload.integer; \
    } else if (left->tag == LUA55_VALUE_FLOAT && right->tag == LUA55_VALUE_FLOAT) { \
        SET_TAG(target, LUA55_VALUE_FLOAT);                                 \
        target->payload.floating = left->payload.floating / right->payload.floating; \
    } else { V2_REJECT(frame, LUA55_V2_REJECT_UNSUPPORTED_METAMETHOD);      \
             LUA55_CPS_HOST_EXIT(frame); }                                  \
    LUA55_RESIDUAL_NEXT(frame);

#define V2_POW_BODY(right_init)                                             \
    V2_ARITH_PROLOGUE(right_init)                                           \
    if (left->tag == LUA55_VALUE_INTEGER && right->tag == LUA55_VALUE_INTEGER) { \
        SET_TAG(target, LUA55_VALUE_FLOAT);                                 \
        target->payload.floating = v2_pow((double)left->payload.integer, (double)right->payload.integer); \
    } else if (left->tag == LUA55_VALUE_INTEGER && right->tag == LUA55_VALUE_FLOAT) { \
        SET_TAG(target, LUA55_VALUE_FLOAT);                                 \
        target->payload.floating = v2_pow((double)left->payload.integer, right->payload.floating); \
    } else if (left->tag == LUA55_VALUE_FLOAT && right->tag == LUA55_VALUE_INTEGER) { \
        SET_TAG(target, LUA55_VALUE_FLOAT);                                 \
        target->payload.floating = v2_pow(left->payload.floating, (double)right->payload.integer); \
    } else if (left->tag == LUA55_VALUE_FLOAT && right->tag == LUA55_VALUE_FLOAT) { \
        SET_TAG(target, LUA55_VALUE_FLOAT);                                 \
        target->payload.floating = v2_pow(left->payload.floating, right->payload.floating); \
    } else { V2_REJECT(frame, LUA55_V2_REJECT_UNSUPPORTED_METAMETHOD);      \
             LUA55_CPS_HOST_EXIT(frame); }                                  \
    LUA55_RESIDUAL_NEXT(frame);

V2_BIN(add, v2_int_add, FLT_ADD, FLT_ADD, FLT_ADD, (void)0)
V2_BIN(sub, v2_int_sub, FLT_SUB, FLT_SUB, FLT_SUB, (void)0)
V2_BIN(mul, v2_int_mul, FLT_MUL, FLT_MUL, FLT_MUL, (void)0)
V2_BIN(addi, v2_int_add, FLT_ADD, FLT_ADD, FLT_ADD, V2_ARITH_RIGHT_INIT)
V2_BIN(addk, v2_int_add, FLT_ADD, FLT_ADD, FLT_ADD, V2_ARITH_CONST_RIGHT)
V2_BIN(subk, v2_int_sub, FLT_SUB, FLT_SUB, FLT_SUB, V2_ARITH_CONST_RIGHT)
V2_BIN(mulk, v2_int_mul, FLT_MUL, FLT_MUL, FLT_MUL, V2_ARITH_CONST_RIGHT)
V2_DIVMOD(idiv, v2_idiv, v2_flt_idiv, (void)0)
V2_DIVMOD(mod, v2_mod, v2_fmod, (void)0)
V2_DIVMOD(idivk, v2_idiv, v2_flt_idiv, V2_ARITH_CONST_RIGHT)
V2_DIVMOD(modk, v2_mod, v2_fmod, V2_ARITH_CONST_RIGHT)
V2_BITWISE(band, v2_int_band, (void)0)
V2_BITWISE(bor, v2_int_bor, (void)0)
V2_BITWISE(bxor, v2_int_bxor, (void)0)
V2_BITWISE(bandk, v2_int_band, V2_ARITH_CONST_RIGHT)
V2_BITWISE(bork, v2_int_bor, V2_ARITH_CONST_RIGHT)
V2_BITWISE(bxork, v2_int_bxor, V2_ARITH_CONST_RIGHT)
V2_SHIFT(shl, 0, (void)0)
V2_SHIFT(shr, 0, (void)0)
V2_SHIFT(shli, 0, V2_ARITH_RIGHT_INIT)
V2_SHIFT(shri, 0, V2_ARITH_RIGHT_INIT)
STENCIL(lua55_v2_div)(Lua55NativeFrameV2 *frame) { V2_DIV_BODY((void)0) }
STENCIL(lua55_v2_divk)(Lua55NativeFrameV2 *frame) { V2_DIV_BODY(V2_ARITH_CONST_RIGHT) }
STENCIL(lua55_v2_pow)(Lua55NativeFrameV2 *frame) { V2_POW_BODY((void)0) }
STENCIL(lua55_v2_powk)(Lua55NativeFrameV2 *frame) { V2_POW_BODY(V2_ARITH_CONST_RIGHT) }

/* ======================================================================= */
/* 49-52: unary                                                             */
/* ======================================================================= */

#define V2_UNARY_PROLOGUE()                                                 \
    uint32_t target_index = V2_TARGET_HOLE;                                 \
    __asm__ volatile ("" : "+r"(target_index));                            \
    uint32_t source_index = V2_SOURCE_HOLE;                                 \
    __asm__ volatile ("" : "+r"(source_index));                            \
    Lua55ValueV2 *target = &frame->values[target_index];                    \
    Lua55ValueV2 *source = &frame->values[source_index];

STENCIL(lua55_v2_unm)(Lua55NativeFrameV2 *frame)
{
    V2_UNARY_PROLOGUE()
    if (source->tag == LUA55_VALUE_INTEGER) {
        SET_TAG(target, LUA55_VALUE_INTEGER);
        target->payload.integer = v2_int_unm(source->payload.integer);
    } else if (source->tag == LUA55_VALUE_FLOAT) {
        SET_TAG(target, LUA55_VALUE_FLOAT);
        target->payload.floating = v2_flt_unm(source->payload.floating);
    } else { V2_REJECT(frame, LUA55_V2_REJECT_UNSUPPORTED_METAMETHOD);
             LUA55_CPS_HOST_EXIT(frame); }
    LUA55_RESIDUAL_NEXT(frame);
}

STENCIL(lua55_v2_bnot)(Lua55NativeFrameV2 *frame)
{
    V2_UNARY_PROLOGUE()
    int64_t value = 0;
    if (source->tag == LUA55_VALUE_INTEGER) value = source->payload.integer;
    else if (source->tag == LUA55_VALUE_FLOAT &&
             v2_flt_to_int_eq(source->payload.floating, &value)) { }
    else { V2_REJECT(frame, LUA55_V2_REJECT_UNSUPPORTED_METAMETHOD);
           LUA55_CPS_HOST_EXIT(frame); }
    SET_TAG(target, LUA55_VALUE_INTEGER);
    target->payload.integer = ~value;
    LUA55_RESIDUAL_NEXT(frame);
}

STENCIL(lua55_v2_not)(Lua55NativeFrameV2 *frame)
{
    V2_UNARY_PROLOGUE()
    SET_TAG(target, (source->tag == LUA55_VALUE_NIL || source->tag == LUA55_VALUE_FALSE)
        ? LUA55_VALUE_TRUE : LUA55_VALUE_FALSE);
    LUA55_RESIDUAL_NEXT(frame);
}

STENCIL(lua55_v2_len)(Lua55NativeFrameV2 *frame)
{
    V2_UNARY_PROLOGUE()
    if (v2_is_string_tag(source->tag)) {
        Lua55GuestStringV2 *str = (Lua55GuestStringV2 *)source->payload.reference;
        SET_TAG(target, LUA55_VALUE_INTEGER);
        target->payload.integer = (str != 0) ? (int64_t)str->length : 0;
    } else if (v2_primitive_len_table(frame, source) != 0) {
        Lua55GuestTableV2 *table = (Lua55GuestTableV2 *)source->payload.reference;
        SET_TAG(target, LUA55_VALUE_INTEGER);
        target->payload.integer = v2_table_len(table);
    } else { V2_REJECT(frame, LUA55_V2_REJECT_UNSUPPORTED_METAMETHOD);
             LUA55_CPS_HOST_EXIT(frame); }
    LUA55_RESIDUAL_NEXT(frame);
}

/* ======================================================================= */
/* 56: JMP                                                                  */
/* ======================================================================= */

STENCIL(lua55_v2_jmp)(Lua55NativeFrameV2 *frame)
{
    uintptr_t link = (uintptr_t)V2_LINK_HOLE;
    __asm__ volatile ("" : "+r"(link));
    return ((Lua55NativeEntryV2)link)(frame);
}

/* ======================================================================= */
/* 57-67: comparisons and tests                                             */
/* ======================================================================= */

#define V2_CMP_PROLOGUE()                                                   \
    uint32_t left_index = V2_TARGET_HOLE;                                   \
    __asm__ volatile ("" : "+r"(left_index));                              \
    uint32_t right_index = V2_RIGHT_HOLE;                                   \
    __asm__ volatile ("" : "+r"(right_index));                             \
    Lua55ValueV2 *left = &frame->values[left_index];                        \
    Lua55ValueV2 *right = &frame->values[right_index];

#define V2_BRANCH_TAKEN(frame) do {                                         \
    uintptr_t target = (uintptr_t)V2_TAKEN_HOLE;                            \
    __asm__ volatile ("" : "+r"(target));                                  \
    return ((Lua55NativeEntryV2)target)(frame);                             \
} while (0)

#define V2_CMP_RIGHT_INIT                                                   \
    Lua55ValueV2 imm_cell;                                                  \
    uint64_t imm_bits = V2_INT_IMM_HOLE;                                    \
    __asm__ volatile ("" : "+r"(imm_bits));                                \
    SET_TAG(&imm_cell, LUA55_VALUE_INTEGER);                                \
    imm_cell.payload.integer = (int64_t)imm_bits;                           \
    right = &imm_cell;

#define V2_CMP_CONST_RIGHT                                                  \
    Lua55ValueV2 const_cell;                                                \
    uint32_t const_tag = V2_CONST_TAG;                                      \
    __asm__ volatile ("" : "+r"(const_tag));                               \
    uint64_t const_int_bits = V2_CONST_INT;                                 \
    __asm__ volatile ("" : "+r"(const_int_bits));                          \
    uint64_t const_flt_bits = V2_CONST_FLT;                                 \
    __asm__ volatile ("" : "+r"(const_flt_bits));                          \
    uint64_t const_ref_bits = V2_CONST_REF;                                 \
    __asm__ volatile ("" : "+r"(const_ref_bits));                          \
    const_cell.tag = const_tag;                                             \
    if (const_tag == LUA55_VALUE_INTEGER)                                   \
        const_cell.payload.integer = (int64_t)const_int_bits;               \
    else if (const_tag == LUA55_VALUE_FLOAT)                                \
        __builtin_memcpy(&const_cell.payload.floating, &const_flt_bits, 8); \
    else                                                                    \
        const_cell.payload.reference = (uintptr_t)const_ref_bits;           \
    right = &const_cell;

#define V2_EQ(name, right_init)                                             \
STENCIL(lua55_v2_##name)(Lua55NativeFrameV2 *frame)                         \
{                                                                           \
    V2_CMP_PROLOGUE()                                                       \
    right_init;                                                             \
    uint32_t k = V2_K_HOLE;                                                 \
    __asm__ volatile ("" : "+r"(k));                                       \
    int cond;                                                               \
    if (left->tag == LUA55_VALUE_INTEGER && right->tag == LUA55_VALUE_INTEGER) \
        cond = left->payload.integer == right->payload.integer;             \
    else if (left->tag == LUA55_VALUE_INTEGER && right->tag == LUA55_VALUE_FLOAT) \
        cond = v2_eq_int_float(left->payload.integer, right->payload.floating); \
    else if (left->tag == LUA55_VALUE_FLOAT && right->tag == LUA55_VALUE_INTEGER) \
        cond = v2_eq_int_float(right->payload.integer, left->payload.floating); \
    else if (left->tag == LUA55_VALUE_FLOAT && right->tag == LUA55_VALUE_FLOAT) \
        cond = left->payload.floating == right->payload.floating;           \
    else if (v2_is_string_tag(left->tag) && v2_is_string_tag(right->tag))   \
        cond = v2_string_bytes_eq(left->payload.reference, right->payload.reference); \
    else if (left->tag == right->tag)                                       \
        cond = (left->tag == LUA55_VALUE_TABLE || left->tag == LUA55_VALUE_CLOSURE) \
            ? left->payload.reference == right->payload.reference : 1;      \
    else cond = 0;                                                          \
    if (k ? cond : !cond) { V2_BRANCH_TAKEN(frame); }                       \
    LUA55_RESIDUAL_NEXT(frame);                                             \
}

#define V2_ORD(name, right_init, flip)                                     \
STENCIL(lua55_v2_##name)(Lua55NativeFrameV2 *frame)                         \
{                                                                           \
    V2_CMP_PROLOGUE()                                                       \
    right_init;                                                             \
    uint32_t k = V2_K_HOLE;                                                 \
    __asm__ volatile ("" : "+r"(k));                                       \
    int cond;                                                               \
    if (left->tag == LUA55_VALUE_INTEGER && right->tag == LUA55_VALUE_INTEGER) \
        cond = flip ? left->payload.integer > right->payload.integer        \
                    : left->payload.integer < right->payload.integer;       \
    else if (left->tag == LUA55_VALUE_INTEGER && right->tag == LUA55_VALUE_FLOAT) \
        cond = flip ? (double)left->payload.integer > right->payload.floating \
                    : (double)left->payload.integer < right->payload.floating; \
    else if (left->tag == LUA55_VALUE_FLOAT && right->tag == LUA55_VALUE_INTEGER) \
        cond = flip ? left->payload.floating > (double)right->payload.integer \
                    : left->payload.floating < (double)right->payload.integer; \
    else if (left->tag == LUA55_VALUE_FLOAT && right->tag == LUA55_VALUE_FLOAT) \
        cond = flip ? left->payload.floating > right->payload.floating     \
                    : left->payload.floating < right->payload.floating;    \
    else if (v2_is_string_tag(left->tag) && v2_is_string_tag(right->tag))   \
        cond = flip ? v2_string_cmp(left->payload.reference, right->payload.reference) > 0 \
                    : v2_string_cmp(left->payload.reference, right->payload.reference) < 0; \
    else { V2_REJECT(frame, LUA55_V2_REJECT_UNSUPPORTED_METAMETHOD);        \
           LUA55_CPS_HOST_EXIT(frame); }                                    \
    if (k ? cond : !cond) { V2_BRANCH_TAKEN(frame); }                       \
    LUA55_RESIDUAL_NEXT(frame);                                             \
}

#define V2_LE(name, right_init, flip)                                      \
STENCIL(lua55_v2_##name)(Lua55NativeFrameV2 *frame)                         \
{                                                                           \
    V2_CMP_PROLOGUE()                                                       \
    right_init;                                                             \
    uint32_t k = V2_K_HOLE;                                                 \
    __asm__ volatile ("" : "+r"(k));                                       \
    int cond;                                                               \
    if (left->tag == LUA55_VALUE_INTEGER && right->tag == LUA55_VALUE_INTEGER) \
        cond = flip ? left->payload.integer >= right->payload.integer       \
                    : left->payload.integer <= right->payload.integer;      \
    else if (left->tag == LUA55_VALUE_INTEGER && right->tag == LUA55_VALUE_FLOAT) \
        cond = flip ? (double)left->payload.integer >= right->payload.floating \
                    : (double)left->payload.integer <= right->payload.floating; \
    else if (left->tag == LUA55_VALUE_FLOAT && right->tag == LUA55_VALUE_INTEGER) \
        cond = flip ? left->payload.floating >= (double)right->payload.integer \
                    : left->payload.floating <= (double)right->payload.integer; \
    else if (left->tag == LUA55_VALUE_FLOAT && right->tag == LUA55_VALUE_FLOAT) \
        cond = flip ? left->payload.floating >= right->payload.floating    \
                    : left->payload.floating <= right->payload.floating;   \
    else if (v2_is_string_tag(left->tag) && v2_is_string_tag(right->tag))   \
        cond = flip ? v2_string_cmp(left->payload.reference, right->payload.reference) >= 0 \
                    : v2_string_cmp(left->payload.reference, right->payload.reference) <= 0; \
    else { V2_REJECT(frame, LUA55_V2_REJECT_UNSUPPORTED_METAMETHOD);        \
           LUA55_CPS_HOST_EXIT(frame); }                                    \
    if (k ? cond : !cond) { V2_BRANCH_TAKEN(frame); }                       \
    LUA55_RESIDUAL_NEXT(frame);                                             \
}

V2_EQ(eq, (void)0)
V2_EQ(eqk, V2_CMP_CONST_RIGHT)
V2_EQ(eqi, V2_CMP_RIGHT_INIT)
V2_ORD(lt, (void)0, 0)
V2_ORD(lti, V2_CMP_RIGHT_INIT, 0)
V2_LE(le, (void)0, 0)
V2_LE(lei, V2_CMP_RIGHT_INIT, 0)
V2_ORD(gti, V2_CMP_RIGHT_INIT, 1)
V2_LE(gei, V2_CMP_RIGHT_INIT, 1)

#define V2_TEST(name, set)                                                  \
STENCIL(lua55_v2_##name)(Lua55NativeFrameV2 *frame)                         \
{                                                                           \
    uint32_t left_index = V2_TARGET_HOLE;                                   \
    __asm__ volatile ("" : "+r"(left_index));                              \
    uint32_t target_index = V2_SOURCE_HOLE;                                 \
    __asm__ volatile ("" : "+r"(target_index));                            \
    Lua55ValueV2 *left = &frame->values[left_index];                        \
    uint32_t k = V2_K_HOLE;                                                 \
    __asm__ volatile ("" : "+r"(k));                                       \
    int cond = v2_truthy(left->tag);                                        \
    if (set) {                                                              \
        Lua55ValueV2 *target = &frame->values[target_index];                \
        *target = *left;                                                    \
    }                                                                       \
    if (k ? cond : !cond) { V2_BRANCH_TAKEN(frame); }                       \
    LUA55_RESIDUAL_NEXT(frame);                                             \
}

V2_TEST(test, 0)
V2_TEST(testset, 1)

/* ======================================================================= */
/* 68-72: proper-tail CPS calls, returns, and the host boundary            */
/* ======================================================================= */

STENCIL(lua55_cps_host_exit)(Lua55NativeFrameV2 *frame)
{
    (void)frame;
    return;
}

STENCIL(lua55_cps_call)(Lua55NativeFrameV2 *frame)
{
    uint32_t A = V2_A_HOLE;
    __asm__ volatile ("" : "+r"(A));
    uint32_t B = V2_B_HOLE;
    __asm__ volatile ("" : "+r"(B));
    uint32_t C = V2_C_HOLE;
    __asm__ volatile ("" : "+r"(C));
    uint32_t pc = V2_PC_HOLE;
    __asm__ volatile ("" : "+r"(pc));
    uint64_t cont = V2_CONTINUATION_HOLE;
    __asm__ volatile ("" : "+r"(cont));
    Lua55ValueV2 *callee_cell = &frame->values[A];
    if (callee_cell->tag == LUA55_VALUE_CLOSURE) {
        Lua55NativeClosureV2 *closure =
            (Lua55NativeClosureV2 *)callee_cell->payload.reference;
        Lua55NativeInvocationV2 *inv = frame->invocation;
        if (closure != 0 && closure->header.kind == LUA55_OBJECT_CLOSURE
            && closure->proto_index < inv->function_count) {
            Lua55NativeFunctionDescriptorV2 *desc =
                &inv->functions[closure->proto_index];
            Lua55NativeEntryV2 entry = desc->entry;
            if (entry != 0) {
                uint32_t nargs = B - 1;
                if (nargs >= 0xFFFFFFu) nargs = frame->top > A + 1
                    ? frame->top - (A + 1) : 0;
                uint32_t maxstack = desc->maxstacksize;
                uint32_t nparams = desc->numparams;
                uint32_t fixed = nargs < nparams ? nargs : nparams;
                uint32_t varargs = desc->is_vararg && nargs > nparams
                    ? nargs - nparams : 0;
                if ((uint32_t)(A + 1 + nargs) > frame->value_capacity) {
                    inv->outcome.discriminant = LUA55_V2_OUTCOME_VALUE_OVERFLOW;
                    inv->outcome.u.overflow.required = (uint64_t)(A + 1 + nargs);
                    inv->outcome.u.overflow.available = frame->value_capacity;
                    inv->outcome.u.overflow.pc = pc;
                    LUA55_CPS_HOST_EXIT(frame);
                }
                size_t frame_bytes = (sizeof(Lua55NativeFrameV2)
                    + (size_t)desc->value_capacity * sizeof(Lua55ValueV2)
                    + (size_t)varargs * sizeof(Lua55ValueV2)
                    + (size_t)desc->tbc_capacity * sizeof(Lua55TbcNodeV2) + 15)
                    & ~(size_t)15;
                uint8_t *next = inv->frame_next + frame_bytes;
                if (next > inv->frame_end) {
                    inv->outcome.discriminant = LUA55_V2_OUTCOME_STACK_OVERFLOW;
                    inv->outcome.u.overflow.required = (uint64_t)frame_bytes;
                    inv->outcome.u.overflow.available =
                        (uint64_t)(inv->frame_end - inv->frame_next);
                    inv->outcome.u.overflow.pc = pc;
                    LUA55_CPS_HOST_EXIT(frame);
                }
                Lua55NativeFrameV2 *cframe =
                    (Lua55NativeFrameV2 *)inv->frame_next;
                inv->frame_next = next;
                cframe->values = (Lua55ValueV2 *)
                    ((uint8_t *)cframe + sizeof(Lua55NativeFrameV2));
                cframe->tbc_nodes = (Lua55TbcNodeV2 *)
                    (cframe->values + desc->value_capacity + varargs);
                cframe->upvalues = closure->cells;
                cframe->value_count = maxstack;
                cframe->value_capacity = desc->value_capacity;
                cframe->top = nargs < desc->value_capacity
                    ? nargs : desc->value_capacity;
                cframe->vararg_count = varargs;
                cframe->tbc_count = 0;
                cframe->tbc_capacity = desc->tbc_capacity;
                cframe->invocation = inv;
                cframe->caller = frame;
                cframe->return_link.entry = (Lua55NativeEntryV2)cont;
                cframe->return_link.subject = frame;
                /* results replace the callee slot: sink base is A */
                cframe->result_sink.values = frame->values + A;
                cframe->result_sink.top = &frame->top;
                cframe->result_sink.base = A;
                cframe->result_sink.count = (int32_t)C - 1;
                cframe->result_sink.capacity = frame->value_capacity;
                cframe->open_upvalues = 0;
                uint32_t i;
                for (i = 0; i < fixed; i++)
                    cframe->values[i] = frame->values[A + 1 + i];
                for (i = fixed; i < nparams; i++)
                    SET_TAG(&cframe->values[i], LUA55_VALUE_NIL);
                if (varargs > 0) {
                    Lua55ValueV2 *vararg_slice = cframe->values
                        + cframe->value_capacity;
                    for (i = 0; i < varargs; i++)
                        vararg_slice[i] = frame->values[A + 1 + fixed + i];
                }
                inv->current_frame = cframe;
                return entry(cframe);
            }
        }
        if (closure != 0 && closure->header.kind == LUA55_OBJECT_BUILTIN) {
            /* declared host builtin: suspend with the exact continuation */
            inv->outcome.discriminant = LUA55_V2_OUTCOME_HOST_CALL;
            inv->outcome.u.host_call.resume_entry = (Lua55NativeEntryV2)cont;
            inv->outcome.u.host_call.a = A;
            inv->outcome.u.host_call.b = B;
            inv->outcome.u.host_call.c = C;
            inv->outcome.u.host_call.pc = pc;
            inv->outcome.u.host_call.host_id = 0;
            LUA55_CPS_HOST_EXIT(frame);
        }
        V2_REJECT(frame, LUA55_V2_REJECT_UNSUPPORTED_CALLEE);
        LUA55_CPS_HOST_EXIT(frame);
    }
    V2_REJECT(frame, LUA55_V2_REJECT_UNSUPPORTED_CALLEE);
    LUA55_CPS_HOST_EXIT(frame);
}

STENCIL(lua55_cps_tailcall)(Lua55NativeFrameV2 *frame)
{
    uint32_t A = V2_A_HOLE;
    __asm__ volatile ("" : "+r"(A));
    uint32_t B = V2_B_HOLE;
    __asm__ volatile ("" : "+r"(B));
    uint32_t pc = V2_PC_HOLE;
    __asm__ volatile ("" : "+r"(pc));
    uint64_t tail_ret = V2_TAIL_RETURN_HOLE;
    __asm__ volatile ("" : "+r"(tail_ret));
    Lua55ValueV2 *callee_cell = &frame->values[A];
    if (callee_cell->tag == LUA55_VALUE_CLOSURE) {
        Lua55NativeClosureV2 *closure =
            (Lua55NativeClosureV2 *)callee_cell->payload.reference;
        Lua55NativeInvocationV2 *inv = frame->invocation;
        if (closure != 0 && closure->header.kind == LUA55_OBJECT_CLOSURE
            && closure->proto_index < inv->function_count) {
            Lua55NativeFunctionDescriptorV2 *desc =
                &inv->functions[closure->proto_index];
            Lua55NativeEntryV2 entry = desc->entry;
            if (entry != 0) {
                uint32_t nargs = B - 1;
                if (nargs >= 0xFFFFFFu) nargs = frame->top > A + 1
                    ? frame->top - (A + 1) : 0;
                uint32_t maxstack = desc->maxstacksize;
                uint32_t nparams = desc->numparams;
                uint32_t fixed = nargs < nparams ? nargs : nparams;
                uint32_t varargs = desc->is_vararg && nargs > nparams
                    ? nargs - nparams : 0;
                if ((uint32_t)(A + 1 + nargs) > frame->value_capacity) {
                    inv->outcome.discriminant = LUA55_V2_OUTCOME_VALUE_OVERFLOW;
                    inv->outcome.u.overflow.required = (uint64_t)(A + 1 + nargs);
                    inv->outcome.u.overflow.available = frame->value_capacity;
                    inv->outcome.u.overflow.pc = pc;
                    LUA55_CPS_HOST_EXIT(frame);
                }
                size_t frame_bytes = (sizeof(Lua55NativeFrameV2)
                    + (size_t)desc->value_capacity * sizeof(Lua55ValueV2)
                    + (size_t)varargs * sizeof(Lua55ValueV2)
                    + (size_t)desc->tbc_capacity * sizeof(Lua55TbcNodeV2) + 15)
                    & ~(size_t)15;
                uint8_t *new_end = (uint8_t *)frame + frame_bytes;
                if (new_end > inv->frame_end) {
                    inv->outcome.discriminant = LUA55_V2_OUTCOME_STACK_OVERFLOW;
                    inv->outcome.u.overflow.required = (uint64_t)frame_bytes;
                    inv->outcome.u.overflow.available =
                        (uint64_t)(inv->frame_end - (uint8_t *)frame);
                    inv->outcome.u.overflow.pc = pc;
                    LUA55_CPS_HOST_EXIT(frame);
                }
                /* close frame-owned open cells before registers move */
                lua55_cps_close_open_upvalues(frame);
                uint32_t i;
                for (i = 0; i < fixed; i++)
                    frame->values[i] = frame->values[A + 1 + i];
                for (i = fixed; i < nparams; i++)
                    SET_TAG(&frame->values[i], LUA55_VALUE_NIL);
                if (varargs > 0) {
                    Lua55ValueV2 *vararg_slice = frame->values
                        + desc->value_capacity;
                    for (i = 0; i < varargs; i++)
                        vararg_slice[i] = frame->values[A + 1 + fixed + i];
                }
                frame->upvalues = closure->cells;
                frame->value_count = maxstack;
                frame->value_capacity = desc->value_capacity;
                frame->vararg_count = varargs;
                frame->top = nargs < desc->value_capacity
                    ? nargs : desc->value_capacity;
                frame->tbc_count = 0;
                frame->tbc_capacity = desc->tbc_capacity;
                frame->tbc_nodes = (Lua55TbcNodeV2 *)
                    (frame->values + desc->value_capacity + varargs);
                frame->open_upvalues = 0;
                inv->frame_next = new_end;
                inv->current_frame = frame;
                return entry(frame);
            }
        }
        if (closure != 0 && closure->header.kind == LUA55_OBJECT_BUILTIN) {
            /* host tail call: suspend through the occurrence tail-return */
            inv->outcome.discriminant = LUA55_V2_OUTCOME_HOST_TAIL_CALL;
            inv->outcome.u.host_tail_call.tail_return_entry =
                (Lua55NativeEntryV2)tail_ret;
            inv->outcome.u.host_tail_call.a = A;
            inv->outcome.u.host_tail_call.b = B;
            inv->outcome.u.host_tail_call.pc = pc;
            inv->outcome.u.host_tail_call.host_id = 0;
            LUA55_CPS_HOST_EXIT(frame);
        }
        V2_REJECT(frame, LUA55_V2_REJECT_UNSUPPORTED_CALLEE);
        LUA55_CPS_HOST_EXIT(frame);
    }
    V2_REJECT(frame, LUA55_V2_REJECT_UNSUPPORTED_CALLEE);
    LUA55_CPS_HOST_EXIT(frame);
}

#define V2_RETURN_IMPL(name, b_mode, fixed)                                 \
STENCIL(name)(Lua55NativeFrameV2 *frame)                                    \
{                                                                           \
    uint32_t A = V2_A_HOLE;                                                 \
    __asm__ volatile ("" : "+r"(A));                                       \
    uint32_t pc = V2_PC_HOLE;                                               \
    __asm__ volatile ("" : "+r"(pc));                                      \
    int32_t nres = (b_mode) ? (int32_t)((uint32_t)(fixed)) : 0;            \
    if (nres < 0) nres = 0;                                                 \
    Lua55NativeResultSinkV2 sink = frame->result_sink;                     \
    int32_t count = sink.count >= 0                                         \
        ? (sink.count < nres ? sink.count : nres) : nres;                   \
    if (sink.values != 0) {                                                 \
        uint32_t needed = sink.base + (uint32_t)(sink.count >= 0           \
            ? sink.count : count);                                          \
        if (needed > sink.capacity) {                                       \
            frame->invocation->outcome.discriminant =                       \
                LUA55_V2_OUTCOME_VALUE_OVERFLOW;                            \
            frame->invocation->outcome.u.overflow.required = needed;        \
            frame->invocation->outcome.u.overflow.available = sink.capacity; \
            frame->invocation->outcome.u.overflow.pc = pc;                  \
            LUA55_CPS_HOST_EXIT(frame);                                     \
        }                                                                   \
        int32_t i;                                                          \
        for (i = 0; i < count; i++)                                         \
            sink.values[i] = frame->values[A + i];                          \
        if (sink.count >= 0) {                                              \
            for (i = count; i < sink.count; i++)                            \
                SET_TAG(&sink.values[i], LUA55_VALUE_NIL);                  \
            *sink.top = sink.base + (uint32_t)sink.count;                   \
        } else {                                                            \
            *sink.top = sink.base + (uint32_t)count;                        \
        }                                                                   \
    }                                                                       \
    lua55_cps_close_open_upvalues(frame);                                   \
    Lua55NativeInvocationV2 *inv = frame->invocation;                       \
    inv->outcome.discriminant = LUA55_V2_OUTCOME_RETURNED;                  \
    inv->outcome.result_count = (uint32_t)(sink.count >= 0                 \
        ? (uint32_t)sink.count : (uint32_t)count);                          \
    if (inv->current_frame == frame) {                                      \
        inv->frame_next = (uint8_t *)frame;                                 \
        inv->current_frame = frame->caller;                                 \
    }                                                                       \
    Lua55NativeEntryV2 cont = frame->return_link.entry;                     \
    Lua55NativeFrameV2 *subject = frame->return_link.subject;               \
    return cont(subject);                                                   \
}

#define V2_RETURN_B(name)                                                   \
STENCIL(name)(Lua55NativeFrameV2 *frame)                                    \
{                                                                           \
    uint32_t A = V2_A_HOLE;                                                 \
    __asm__ volatile ("" : "+r"(A));                                       \
    uint32_t B = V2_B_HOLE;                                                 \
    __asm__ volatile ("" : "+r"(B));                                       \
    uint32_t pc = V2_PC_HOLE;                                               \
    __asm__ volatile ("" : "+r"(pc));                                      \
    int32_t nres = B == 0 ? (int32_t)frame->top - (int32_t)A              \
                          : (int32_t)B - 1;                                \
    if (nres < 0) nres = 0;                                                 \
    Lua55NativeResultSinkV2 sink = frame->result_sink;                     \
    int32_t count = sink.count >= 0                                         \
        ? (sink.count < nres ? sink.count : nres) : nres;                   \
    if (sink.values != 0) {                                                 \
        uint32_t needed = sink.base + (uint32_t)(sink.count >= 0           \
            ? sink.count : count);                                          \
        if (needed > sink.capacity) {                                       \
            frame->invocation->outcome.discriminant =                       \
                LUA55_V2_OUTCOME_VALUE_OVERFLOW;                            \
            frame->invocation->outcome.u.overflow.required = needed;        \
            frame->invocation->outcome.u.overflow.available = sink.capacity; \
            frame->invocation->outcome.u.overflow.pc = pc;                  \
            LUA55_CPS_HOST_EXIT(frame);                                     \
        }                                                                   \
        int32_t i;                                                          \
        for (i = 0; i < count; i++)                                         \
            sink.values[i] = frame->values[A + i];                          \
        if (sink.count >= 0) {                                              \
            for (i = count; i < sink.count; i++)                            \
                SET_TAG(&sink.values[i], LUA55_VALUE_NIL);                  \
            *sink.top = sink.base + (uint32_t)sink.count;                   \
        } else {                                                            \
            *sink.top = sink.base + (uint32_t)count;                        \
        }                                                                   \
    }                                                                       \
    lua55_cps_close_open_upvalues(frame);                                   \
    Lua55NativeInvocationV2 *inv = frame->invocation;                       \
    inv->outcome.discriminant = LUA55_V2_OUTCOME_RETURNED;                  \
    inv->outcome.result_count = (uint32_t)(sink.count >= 0                 \
        ? (uint32_t)sink.count : (uint32_t)count);                          \
    if (inv->current_frame == frame) {                                      \
        inv->frame_next = (uint8_t *)frame;                                 \
        inv->current_frame = frame->caller;                                 \
    }                                                                       \
    Lua55NativeEntryV2 cont = frame->return_link.entry;                     \
    Lua55NativeFrameV2 *subject = frame->return_link.subject;               \
    return cont(subject);                                                   \
}

V2_RETURN_IMPL(lua55_cps_return0, 1, 0)
V2_RETURN_IMPL(lua55_cps_return1, 1, 1)
V2_RETURN_B(lua55_cps_return)

/* The per-occurrence host tail-return entry: publishes results already at
   R[A..top) through the inherited sink, closes, pops, and jumps to the
   inherited return link — the ordinary V2 RETURN protocol. */
STENCIL(lua55_cps_host_tail_return)(Lua55NativeFrameV2 *frame)
{
    uint32_t A = V2_A_HOLE;
    __asm__ volatile ("" : "+r"(A));
    uint32_t pc = V2_PC_HOLE;
    __asm__ volatile ("" : "+r"(pc));
    int32_t nres = (int32_t)frame->top - (int32_t)A;
    if (nres < 0) nres = 0;
    Lua55NativeResultSinkV2 sink = frame->result_sink;
    int32_t count = sink.count >= 0
        ? (sink.count < nres ? sink.count : nres) : nres;
    if (sink.values != 0) {
        uint32_t needed = sink.base + (uint32_t)(sink.count >= 0
            ? sink.count : count);
        if (needed > sink.capacity) {
            frame->invocation->outcome.discriminant =
                LUA55_V2_OUTCOME_VALUE_OVERFLOW;
            frame->invocation->outcome.u.overflow.required = needed;
            frame->invocation->outcome.u.overflow.available = sink.capacity;
            frame->invocation->outcome.u.overflow.pc = pc;
            LUA55_CPS_HOST_EXIT(frame);
        }
        int32_t i;
        for (i = 0; i < count; i++)
            sink.values[i] = frame->values[A + i];
        if (sink.count >= 0) {
            for (i = count; i < sink.count; i++)
                SET_TAG(&sink.values[i], LUA55_VALUE_NIL);
            *sink.top = sink.base + (uint32_t)sink.count;
        } else {
            *sink.top = sink.base + (uint32_t)count;
        }
    }
    lua55_cps_close_open_upvalues(frame);
    Lua55NativeInvocationV2 *inv = frame->invocation;
    inv->outcome.discriminant = LUA55_V2_OUTCOME_RETURNED;
    inv->outcome.result_count = (uint32_t)(sink.count >= 0
        ? (uint32_t)sink.count : (uint32_t)count);
    if (inv->current_frame == frame) {
        inv->frame_next = (uint8_t *)frame;
        inv->current_frame = frame->caller;
    }
    Lua55NativeEntryV2 cont = frame->return_link.entry;
    Lua55NativeFrameV2 *subject = frame->return_link.subject;
    return cont(subject);
}

/* ======================================================================= */
/* 73-74: numeric for                                                       */
/* ======================================================================= */

STENCIL(lua55_v2_forprep)(Lua55NativeFrameV2 *frame)
{
    uint32_t A = V2_BASE_INDEX_HOLE;
    __asm__ volatile ("" : "+r"(A));
    Lua55ValueV2 *init = &frame->values[A];
    Lua55ValueV2 *limit = &frame->values[A + 1];
    Lua55ValueV2 *step = &frame->values[A + 2];
    uintptr_t target;
    if (init->tag == LUA55_VALUE_INTEGER &&
        limit->tag == LUA55_VALUE_INTEGER && step->tag == LUA55_VALUE_INTEGER) {
        int64_t iv = init->payload.integer;
        int64_t lv = limit->payload.integer;
        int64_t sv = step->payload.integer;
        if (sv == 0) { V2_REJECT(frame, LUA55_V2_REJECT_STEP_ZERO);
                       LUA55_CPS_HOST_EXIT(frame); }
        if ((sv > 0 && iv > lv) || (sv < 0 && iv < lv)) {
            target = (uintptr_t)V2_SKIP_HOLE;
        } else {
            uint64_t distance = sv > 0
                ? (uint64_t)lv - (uint64_t)iv
                : (uint64_t)iv - (uint64_t)lv;
            uint64_t stride = sv > 0 ? (uint64_t)sv
                : UINT64_C(0) - (uint64_t)sv;
            SET_TAG(init, LUA55_VALUE_INTEGER);
            init->payload.integer = (int64_t)(distance / stride);
            SET_TAG(limit, LUA55_VALUE_INTEGER);
            limit->payload.integer = sv;
            SET_TAG(step, LUA55_VALUE_INTEGER);
            step->payload.integer = iv;
            target = (uintptr_t)V2_BODY_HOLE;
        }
    } else if ((init->tag == LUA55_VALUE_INTEGER || init->tag == LUA55_VALUE_FLOAT) &&
               (limit->tag == LUA55_VALUE_INTEGER || limit->tag == LUA55_VALUE_FLOAT) &&
               (step->tag == LUA55_VALUE_INTEGER || step->tag == LUA55_VALUE_FLOAT)) {
        double iv = init->tag == LUA55_VALUE_INTEGER
            ? (double)init->payload.integer : init->payload.floating;
        double lv = limit->tag == LUA55_VALUE_INTEGER
            ? (double)limit->payload.integer : limit->payload.floating;
        double sv = step->tag == LUA55_VALUE_INTEGER
            ? (double)step->payload.integer : step->payload.floating;
        if (sv == 0.0) { V2_REJECT(frame, LUA55_V2_REJECT_STEP_ZERO);
                         LUA55_CPS_HOST_EXIT(frame); }
        if ((sv > 0.0 && lv < iv) || (sv < 0.0 && iv < lv)) {
            target = (uintptr_t)V2_SKIP_HOLE;
        } else {
            SET_TAG(init, LUA55_VALUE_FLOAT); init->payload.floating = lv;
            SET_TAG(limit, LUA55_VALUE_FLOAT); limit->payload.floating = sv;
            SET_TAG(step, LUA55_VALUE_FLOAT); step->payload.floating = iv;
            target = (uintptr_t)V2_BODY_HOLE;
        }
    } else { V2_REJECT(frame, LUA55_V2_REJECT_UNSUPPORTED_OPCODE);
             LUA55_CPS_HOST_EXIT(frame); }
    __asm__ volatile ("" : "+r"(target));
    return ((Lua55NativeEntryV2)target)(frame);
}

STENCIL(lua55_v2_forloop)(Lua55NativeFrameV2 *frame)
{
    uint32_t A = V2_BASE_INDEX_HOLE;
    __asm__ volatile ("" : "+r"(A));
    Lua55ValueV2 *count_cell = &frame->values[A];
    Lua55ValueV2 *step_cell = &frame->values[A + 1];
    Lua55ValueV2 *idx_cell = &frame->values[A + 2];
    uintptr_t target;
    if (step_cell->tag == LUA55_VALUE_INTEGER) {
        int64_t count = count_cell->payload.integer;
        if (count > 0) {
            count_cell->payload.integer = count - 1;
            idx_cell->payload.integer = v2_int_add(
                idx_cell->payload.integer, step_cell->payload.integer);
            target = (uintptr_t)V2_LINK_HOLE;
        } else target = (uintptr_t)V2_FALL_HOLE;
    } else {
        double idx = idx_cell->payload.floating;
        double sv = step_cell->payload.floating;
        double lv = count_cell->payload.floating;
        idx = idx + sv;
        if ((sv > 0.0 && idx <= lv) || (sv < 0.0 && lv <= idx)) {
            idx_cell->payload.floating = idx;
            target = (uintptr_t)V2_LINK_HOLE;
        } else target = (uintptr_t)V2_FALL_HOLE;
    }
    __asm__ volatile ("" : "+r"(target));
    return ((Lua55NativeEntryV2)target)(frame);
}

/* ======================================================================= */
/* 79: CLOSURE with heap-owned shared cells                                 */
/* ======================================================================= */

static inline uintptr_t v2_heap_bump(Lua55GuestHeapV2 *heap, size_t size)
{
    if (heap == 0 || heap->table_region == 0) return 0;
    uintptr_t next = heap->table_next;
    uintptr_t aligned = (next + 15) & ~(uintptr_t)15;
    if (aligned + size > heap->table_region_end) return 0;
    heap->table_next = aligned + size;
    return aligned;
}

static inline Lua55UpvalueCellV2 *v2_new_cell(Lua55GuestHeapV2 *heap)
{
    uintptr_t at = v2_heap_bump(heap, sizeof(Lua55UpvalueCellV2));
    if (at == 0) return 0;
    Lua55UpvalueCellV2 *cell = (Lua55UpvalueCellV2 *)at;
    cell->open_slot = 0;
    cell->closed_value.tag = 0;
    cell->closed_value.reserved = 0;
    cell->closed_value.payload.reference = 0;
    cell->next_open = 0;
    cell->state = 0;
    cell->generation = 1;
    return cell;
}

static inline Lua55NativeClosureV2 *v2_new_closure(
    Lua55GuestHeapV2 *heap, uint32_t proto_index, uint32_t nupvals)
{
    size_t cells_size = sizeof(Lua55UpvalueCellV2 *) * nupvals;
    size_t closure_size = sizeof(Lua55NativeClosureV2) + cells_size;
    uintptr_t at = v2_heap_bump(heap, closure_size);
    if (at == 0) return 0;
    Lua55NativeClosureV2 *closure = (Lua55NativeClosureV2 *)at;
    closure->header.kind = LUA55_OBJECT_CLOSURE;
    closure->header.generation = heap->object_count + 1;
    closure->proto_index = proto_index;
    closure->upvalue_count = nupvals;
    heap->object_count++;
    return closure;
}

static inline int v2_set_cell(Lua55NativeFrameV2 *frame,
    Lua55NativeClosureV2 *closure, uint32_t i, uint32_t isinstack,
    uint32_t idx)
{
    if (isinstack) {
        Lua55UpvalueCellV2 *cell;
        for (cell = frame->open_upvalues; cell != 0; cell = cell->next_open)
            if (cell->open_slot == &frame->values[idx]) break;
        if (cell == 0) {
            cell = v2_new_cell(frame->invocation->heap);
            if (cell == 0) return 0;
            cell->open_slot = &frame->values[idx];
            cell->state = LUA55_UPVALUE_OPEN;
            cell->generation = 1;
            cell->next_open = frame->open_upvalues;
            frame->open_upvalues = cell;
        }
        closure->cells[i] = cell;
    } else {
        closure->cells[i] = frame->upvalues[idx];
    }
    return 1;
}

STENCIL(lua55_cps_closure)(Lua55NativeFrameV2 *frame)
{
    uint32_t target_index = V2_TARGET_HOLE;
    __asm__ volatile ("" : "+r"(target_index));
    uint32_t proto_index = V2_PROTO_INDEX_HOLE;
    __asm__ volatile ("" : "+r"(proto_index));
    uint32_t nupvals = V2_NUPVALS_HOLE;
    __asm__ volatile ("" : "+r"(nupvals));
    uint32_t instack0 = V2_INSTACK_0, idx0 = V2_IDX_0;
    __asm__ volatile ("" : "+r"(instack0)); __asm__ volatile ("" : "+r"(idx0));
    uint32_t instack1 = V2_INSTACK_1, idx1 = V2_IDX_1;
    __asm__ volatile ("" : "+r"(instack1)); __asm__ volatile ("" : "+r"(idx1));
    uint32_t instack2 = V2_INSTACK_2, idx2 = V2_IDX_2;
    __asm__ volatile ("" : "+r"(instack2)); __asm__ volatile ("" : "+r"(idx2));
    uint32_t instack3 = V2_INSTACK_3, idx3 = V2_IDX_3;
    __asm__ volatile ("" : "+r"(instack3)); __asm__ volatile ("" : "+r"(idx3));
    Lua55ValueV2 *target = &frame->values[target_index];
    Lua55NativeClosureV2 *closure =
        v2_new_closure(frame->invocation->heap, proto_index, nupvals);
    if (closure == 0) { V2_PUBLISH_OVERFLOW(frame, LUA55_V2_OUTCOME_HEAP_OVERFLOW,
                        0, 0);
                        LUA55_CPS_HOST_EXIT(frame); }
    if (nupvals > 0 && v2_set_cell(frame, closure, 0, instack0, idx0) == 0)
        { V2_PUBLISH_OVERFLOW(frame, LUA55_V2_OUTCOME_HEAP_OVERFLOW, 0, 0);
            LUA55_CPS_HOST_EXIT(frame); }
    if (nupvals > 1 && v2_set_cell(frame, closure, 1, instack1, idx1) == 0)
        { V2_PUBLISH_OVERFLOW(frame, LUA55_V2_OUTCOME_HEAP_OVERFLOW, 0, 0);
            LUA55_CPS_HOST_EXIT(frame); }
    if (nupvals > 2 && v2_set_cell(frame, closure, 2, instack2, idx2) == 0)
        { V2_PUBLISH_OVERFLOW(frame, LUA55_V2_OUTCOME_HEAP_OVERFLOW, 0, 0);
            LUA55_CPS_HOST_EXIT(frame); }
    if (nupvals > 3 && v2_set_cell(frame, closure, 3, instack3, idx3) == 0)
        { V2_PUBLISH_OVERFLOW(frame, LUA55_V2_OUTCOME_HEAP_OVERFLOW, 0, 0);
            LUA55_CPS_HOST_EXIT(frame); }
    SET_TAG(target, LUA55_VALUE_CLOSURE);
    target->payload.reference = (uintptr_t)closure;
    LUA55_RESIDUAL_NEXT(frame);
}

/* ======================================================================= */
/* 11-20, 78: guest tables (array + field storage, no metatables)          */
/* ======================================================================= */

static inline Lua55GuestTableV2 *v2_learn_table(
    Lua55NativeFrameV2 *frame, Lua55ValueV2 *receiver)
{
    Lua55GuestTableV2 *table;
    if (receiver->tag != LUA55_VALUE_TABLE || frame->invocation->heap == 0) return 0;
    table = (Lua55GuestTableV2 *)receiver->payload.reference;
    if (table == 0 || table->header.kind != LUA55_OBJECT_TABLE ||
        table->heap != frame->invocation->heap || table->metatable_reference != 0) return 0;
    return table;
}

static inline Lua55ValueV2 *v2_find_field(
    Lua55GuestTableV2 *table, uintptr_t key, int create)
{
    for (;;) {
        uint32_t index;
        Lua55GuestFieldV2 *vacant = 0;
        for (index = 0; index < table->field_capacity; index++) {
            Lua55GuestFieldV2 *field = &table->field_values[index];
            if (field->occupied && field->key_reference == key) return &field->value;
            if (!field->occupied && vacant == 0) vacant = field;
        }
        if (vacant != 0) {
            if (!create) return 0;
            vacant->key_reference = key;
            vacant->occupied = 1;
            vacant->reserved = 0;
            SET_TAG(&vacant->value, LUA55_VALUE_NIL);
            vacant->value.payload.reference = 0;
            table->storage_generation++;
            return &vacant->value;
        }
        if (!create) return 0;
        /* grow the field part in place: fresh slice from the guest bump */
        Lua55GuestHeapV2 *heap = table->heap;
        uint32_t new_cap = table->field_capacity > 0 ? table->field_capacity : 1;
        new_cap *= 2;
        size_t bytes = sizeof(Lua55GuestFieldV2) * new_cap;
        uintptr_t at = v2_heap_bump(heap, bytes);
        if (at == 0) return 0;
        Lua55GuestFieldV2 *fields = (Lua55GuestFieldV2 *)at;
        for (index = 0; index < table->field_capacity; index++)
            fields[index] = table->field_values[index];
        for (index = table->field_capacity; index < new_cap; index++) {
            fields[index].key_reference = 0;
            fields[index].occupied = 0;
            fields[index].reserved = 0;
            fields[index].value.tag = 0;
            fields[index].value.reserved = 0;
            fields[index].value.payload.reference = 0;
        }
        table->field_values = fields;
        table->field_capacity = new_cap;
        table->storage_generation++;
        /* rescan the grown storage */
    }
}

static inline Lua55ValueV2 *v2_array_slot(Lua55GuestTableV2 *table, int64_t k)
{
    if (k < 1 || (uint64_t)k > table->array_capacity) return 0;
    return &table->array_values[k - 1];
}

static inline int v2_grow_array(Lua55NativeFrameV2 *frame,
    Lua55GuestTableV2 *table, uint64_t needed);

static inline void v2_table_set(Lua55GuestTableV2 *table,
    Lua55ValueV2 *cell, Lua55ValueV2 *value)
{
    *cell = *value;
    if (value->tag >= LUA55_VALUE_SHORT_STRING) {
        table->barrier_count++;
        if (table->heap != 0) table->heap->barrier_epoch++;
    }
}

static inline Lua55GuestTableV2 *v2_new_table(
    Lua55NativeFrameV2 *frame, uint32_t array_cap, uint32_t field_cap)
{
    Lua55GuestHeapV2 *heap = frame->invocation->heap;
    size_t table_size = sizeof(Lua55GuestTableV2);
    size_t array_size = sizeof(Lua55ValueV2) * (array_cap > 0 ? array_cap : 1);
    size_t field_size = sizeof(Lua55GuestFieldV2) * (field_cap > 0 ? field_cap : 1);
    uintptr_t at = v2_heap_bump(heap, table_size + array_size + field_size);
    if (at == 0) return 0;
    Lua55GuestTableV2 *table = (Lua55GuestTableV2 *)at;
    Lua55ValueV2 *arrays = (Lua55ValueV2 *)(at + table_size);
    Lua55GuestFieldV2 *fields = (Lua55GuestFieldV2 *)(at + table_size + array_size);
    uint32_t i;
    table->header.kind = LUA55_OBJECT_TABLE;
    table->header.generation = heap->object_count + 1;
    table->storage_generation = 1;
    table->array_capacity = array_cap > 0 ? array_cap : 1;
    table->field_capacity = field_cap > 0 ? field_cap : 1;
    table->barrier_count = 0;
    table->metatable_reference = 0;
    table->array_values = arrays;
    table->field_values = fields;
    table->heap = heap;
    for (i = 0; i < (array_cap > 0 ? array_cap : 1); i++) {
        arrays[i].tag = 0; arrays[i].reserved = 0; arrays[i].payload.reference = 0;
    }
    for (i = 0; i < (field_cap > 0 ? field_cap : 1); i++) {
        fields[i].key_reference = 0; fields[i].occupied = 0; fields[i].reserved = 0;
        fields[i].value.tag = 0; fields[i].value.reserved = 0;
        fields[i].value.payload.reference = 0;
    }
    heap->object_count++;
    return table;
}

#define V2_TABLE_TARGET()                                                   \
    uint32_t target_reg = V2_TARGET_HOLE;                                   \
    __asm__ volatile ("" : "+r"(target_reg));                              \
    uint32_t receiver_reg = V2_RECEIVER_HOLE;                               \
    __asm__ volatile ("" : "+r"(receiver_reg));

#define V2_TABLE_REJECT(frame, kind) do { V2_REJECT(frame, kind);           \
    LUA55_CPS_HOST_EXIT(frame); } while (0)

STENCIL(lua55_v2_geti)(Lua55NativeFrameV2 *frame)
{
    V2_TABLE_TARGET()
    int64_t key = (int64_t)V2_INT_KEY_HOLE;
    __asm__ volatile ("" : "+r"(key));
    Lua55ValueV2 *receiver = &frame->values[receiver_reg];
    Lua55GuestTableV2 *table = v2_learn_table(frame, receiver);
    if (table == 0) V2_TABLE_REJECT(frame, LUA55_V2_REJECT_INVALID_OBJECT);
    Lua55ValueV2 *target = &frame->values[target_reg];
    Lua55ValueV2 *cell = v2_array_slot(table, key);
    if (cell == 0) { SET_TAG(target, LUA55_VALUE_NIL); target->payload.reference = 0; }
    else *target = *cell;
    LUA55_RESIDUAL_NEXT(frame);
}

STENCIL(lua55_v2_getfield)(Lua55NativeFrameV2 *frame)
{
    V2_TABLE_TARGET()
    uint64_t key_ref = (uint64_t)V2_KEY_REF_HOLE;
    __asm__ volatile ("" : "+r"(key_ref));
    Lua55ValueV2 *receiver = &frame->values[receiver_reg];
    Lua55GuestTableV2 *table = v2_learn_table(frame, receiver);
    if (table == 0) V2_TABLE_REJECT(frame, LUA55_V2_REJECT_INVALID_OBJECT);
    Lua55ValueV2 *target = &frame->values[target_reg];
    Lua55ValueV2 *cell = v2_find_field(table, (uintptr_t)key_ref, 0);
    if (cell == 0) { SET_TAG(target, LUA55_VALUE_NIL); target->payload.reference = 0; }
    else *target = *cell;
    LUA55_RESIDUAL_NEXT(frame);
}

STENCIL(lua55_v2_gettabup)(Lua55NativeFrameV2 *frame)
{
    uint32_t target_reg = V2_TARGET_HOLE;
    __asm__ volatile ("" : "+r"(target_reg));
    uint32_t upvalue_reg = V2_UPVALUE_HOLE;
    __asm__ volatile ("" : "+r"(upvalue_reg));
    uint64_t key_ref = (uint64_t)V2_KEY_REF_HOLE;
    __asm__ volatile ("" : "+r"(key_ref));
    Lua55UpvalueCellV2 *cell0 = frame->upvalues[upvalue_reg];
    Lua55ValueV2 *value = cell0->state == LUA55_UPVALUE_OPEN
        ? cell0->open_slot : &cell0->closed_value;
    Lua55GuestTableV2 *table = v2_learn_table(frame, value);
    if (table == 0) V2_TABLE_REJECT(frame, LUA55_V2_REJECT_INVALID_OBJECT);
    Lua55ValueV2 *target = &frame->values[target_reg];
    Lua55ValueV2 *cell = v2_find_field(table, (uintptr_t)key_ref, 0);
    if (cell == 0) { SET_TAG(target, LUA55_VALUE_NIL); target->payload.reference = 0; }
    else *target = *cell;
    LUA55_RESIDUAL_NEXT(frame);
}

STENCIL(lua55_v2_gettable)(Lua55NativeFrameV2 *frame)
{
    V2_TABLE_TARGET()
    uint32_t key_reg = V2_KEY_REG_HOLE;
    __asm__ volatile ("" : "+r"(key_reg));
    Lua55ValueV2 *receiver = &frame->values[receiver_reg];
    Lua55GuestTableV2 *table = v2_learn_table(frame, receiver);
    if (table == 0) V2_TABLE_REJECT(frame, LUA55_V2_REJECT_INVALID_OBJECT);
    Lua55ValueV2 *target = &frame->values[target_reg];
    Lua55ValueV2 *key = &frame->values[key_reg];
    Lua55ValueV2 *cell;
    if (key->tag == LUA55_VALUE_INTEGER)
        cell = v2_array_slot(table, key->payload.integer);
    else if (v2_is_string_tag(key->tag))
        cell = v2_find_field(table, (uintptr_t)key->payload.reference, 0);
    else V2_TABLE_REJECT(frame, LUA55_V2_REJECT_UNSUPPORTED_METAMETHOD);
    if (cell == 0) { SET_TAG(target, LUA55_VALUE_NIL); target->payload.reference = 0; }
    else *target = *cell;
    LUA55_RESIDUAL_NEXT(frame);
}

#define V2_TABLE_WRITE()                                                    \
    uint32_t receiver_reg = V2_RECEIVER_HOLE;                               \
    __asm__ volatile ("" : "+r"(receiver_reg));                            \
    uint32_t source_reg = V2_SOURCE_HOLE;                                   \
    __asm__ volatile ("" : "+r"(source_reg));                              \
    Lua55ValueV2 *receiver = &frame->values[receiver_reg];                  \
    Lua55GuestTableV2 *table = v2_learn_table(frame, receiver);             \
    if (table == 0) V2_TABLE_REJECT(frame, LUA55_V2_REJECT_INVALID_OBJECT);\
    Lua55ValueV2 *value = &frame->values[source_reg];

STENCIL(lua55_v2_seti)(Lua55NativeFrameV2 *frame)
{
    V2_TABLE_WRITE()
    int64_t key = (int64_t)V2_INT_KEY_HOLE;
    __asm__ volatile ("" : "+r"(key));
    Lua55ValueV2 *cell = v2_array_slot(table, key);
    if (cell == 0) {
        if (key >= 1 && v2_grow_array(frame, table, (uint64_t)key))
            cell = v2_array_slot(table, key);
        else V2_TABLE_REJECT(frame, LUA55_V2_REJECT_INVALID_OBJECT);
    }
    v2_table_set(table, cell, value);
    LUA55_RESIDUAL_NEXT(frame);
}

STENCIL(lua55_v2_setfield)(Lua55NativeFrameV2 *frame)
{
    V2_TABLE_WRITE()
    uint64_t key_ref = (uint64_t)V2_KEY_REF_HOLE;
    __asm__ volatile ("" : "+r"(key_ref));
    Lua55ValueV2 *cell = v2_find_field(table, (uintptr_t)key_ref, 1);
    if (cell == 0) V2_TABLE_REJECT(frame, LUA55_V2_REJECT_INVALID_OBJECT);
    v2_table_set(table, cell, value);
    LUA55_RESIDUAL_NEXT(frame);
}

STENCIL(lua55_v2_settabup)(Lua55NativeFrameV2 *frame)
{
    uint32_t upvalue_reg = V2_UPVALUE_HOLE;
    __asm__ volatile ("" : "+r"(upvalue_reg));
    uint32_t source_reg = V2_SOURCE_HOLE;
    __asm__ volatile ("" : "+r"(source_reg));
    uint64_t key_ref = (uint64_t)V2_KEY_REF_HOLE;
    __asm__ volatile ("" : "+r"(key_ref));
    Lua55UpvalueCellV2 *cell0 = frame->upvalues[upvalue_reg];
    Lua55ValueV2 *value = cell0->state == LUA55_UPVALUE_OPEN
        ? cell0->open_slot : &cell0->closed_value;
    Lua55GuestTableV2 *table = v2_learn_table(frame, value);
    if (table == 0) V2_TABLE_REJECT(frame, LUA55_V2_REJECT_INVALID_OBJECT);
    Lua55ValueV2 *src = &frame->values[source_reg];
    Lua55ValueV2 *cell = v2_find_field(table, (uintptr_t)key_ref, 1);
    if (cell == 0) V2_TABLE_REJECT(frame, LUA55_V2_REJECT_INVALID_OBJECT);
    v2_table_set(table, cell, src);
    LUA55_RESIDUAL_NEXT(frame);
}

STENCIL(lua55_v2_settable)(Lua55NativeFrameV2 *frame)
{
    V2_TABLE_WRITE()
    uint32_t key_reg = V2_KEY_REG_HOLE;
    __asm__ volatile ("" : "+r"(key_reg));
    Lua55ValueV2 *key = &frame->values[key_reg];
    Lua55ValueV2 *cell;
    if (key->tag == LUA55_VALUE_INTEGER) {
        cell = v2_array_slot(table, key->payload.integer);
        if (cell == 0 && key->payload.integer >= 1
            && v2_grow_array(frame, table, (uint64_t)key->payload.integer))
            cell = v2_array_slot(table, key->payload.integer);
    } else if (v2_is_string_tag(key->tag))
        cell = v2_find_field(table, (uintptr_t)key->payload.reference, 1);
    else V2_TABLE_REJECT(frame, LUA55_V2_REJECT_UNSUPPORTED_METAMETHOD);
    if (cell == 0) V2_TABLE_REJECT(frame, LUA55_V2_REJECT_INVALID_OBJECT);
    v2_table_set(table, cell, value);
    LUA55_RESIDUAL_NEXT(frame);
}

STENCIL(lua55_v2_newtable)(Lua55NativeFrameV2 *frame)
{
    uint32_t target_reg = V2_TARGET_HOLE;
    __asm__ volatile ("" : "+r"(target_reg));
    uint32_t array_cap = V2_ARRAY_CAP_HOLE;
    __asm__ volatile ("" : "+r"(array_cap));
    uint32_t field_cap = V2_FIELD_CAP_HOLE;
    __asm__ volatile ("" : "+r"(field_cap));
    Lua55GuestTableV2 *table = v2_new_table(frame, array_cap, field_cap);
    if (table == 0) { V2_PUBLISH_OVERFLOW(frame, LUA55_V2_OUTCOME_HEAP_OVERFLOW, 0, 0);
                      LUA55_CPS_HOST_EXIT(frame); }
    Lua55ValueV2 *target = &frame->values[target_reg];
    SET_TAG(target, LUA55_VALUE_TABLE);
    target->payload.reference = (uintptr_t)table;
    LUA55_RESIDUAL_NEXT(frame);
}

STENCIL(lua55_v2_self)(Lua55NativeFrameV2 *frame)
{
    uint32_t target_reg = V2_TARGET_HOLE;
    __asm__ volatile ("" : "+r"(target_reg));
    uint32_t object_reg = V2_OBJECT_TARGET_HOLE;
    __asm__ volatile ("" : "+r"(object_reg));
    uint32_t receiver_reg = V2_RECEIVER_HOLE;
    __asm__ volatile ("" : "+r"(receiver_reg));
    uint64_t key_ref = (uint64_t)V2_KEY_REF_HOLE;
    __asm__ volatile ("" : "+r"(key_ref));
    Lua55ValueV2 *receiver = &frame->values[receiver_reg];
    Lua55GuestTableV2 *table = v2_learn_table(frame, receiver);
    if (table == 0) V2_TABLE_REJECT(frame, LUA55_V2_REJECT_INVALID_OBJECT);
    frame->values[object_reg] = *receiver;
    Lua55ValueV2 *cell = v2_find_field(table, (uintptr_t)key_ref, 0);
    Lua55ValueV2 *target = &frame->values[target_reg];
    if (cell == 0) { SET_TAG(target, LUA55_VALUE_NIL); target->payload.reference = 0; }
    else *target = *cell;
    LUA55_RESIDUAL_NEXT(frame);
}

#define V2_VALUE_CONST_CELL()                                               \
    Lua55ValueV2 const_cell;                                                \
    uint32_t const_tag = V2_CONST_TAG;                                      \
    __asm__ volatile ("" : "+r"(const_tag));                              \
    uint64_t const_int_bits = V2_CONST_INT;                                 \
    __asm__ volatile ("" : "+r"(const_int_bits));                          \
    uint64_t const_flt_bits = V2_CONST_FLT;                                 \
    __asm__ volatile ("" : "+r"(const_flt_bits));                          \
    uint64_t const_ref_bits = V2_CONST_REF;                                 \
    __asm__ volatile ("" : "+r"(const_ref_bits));                          \
    const_cell.tag = const_tag;                                             \
    const_cell.reserved = 0;                                                \
    if (const_tag == LUA55_VALUE_INTEGER)                                   \
        const_cell.payload.integer = (int64_t)const_int_bits;               \
    else if (const_tag == LUA55_VALUE_FLOAT)                                \
        __builtin_memcpy(&const_cell.payload.floating, &const_flt_bits, 8); \
    else                                                                    \
        const_cell.payload.reference = (uintptr_t)const_ref_bits;           \
    Lua55ValueV2 *value = &const_cell;

/* Grow the array part in place: allocate a fresh replacement slice from the
   guest bump region, copy the live prefix, and bump the storage generation.
   The stable table object header never moves. */
static inline int v2_grow_array(Lua55NativeFrameV2 *frame,
    Lua55GuestTableV2 *table, uint64_t needed)
{
    Lua55GuestHeapV2 *heap = frame->invocation->heap;
    uint32_t new_capacity = table->array_capacity > 0
        ? table->array_capacity : 1;
    while ((uint64_t)new_capacity < needed) new_capacity *= 2;
    size_t bytes = sizeof(Lua55ValueV2) * new_capacity;
    uintptr_t at = v2_heap_bump(heap, bytes);
    if (at == 0) return 0;
    Lua55ValueV2 *arrays = (Lua55ValueV2 *)at;
    uint32_t i;
    for (i = 0; i < table->array_capacity; i++) arrays[i] = table->array_values[i];
    for (i = table->array_capacity; i < new_capacity; i++) {
        arrays[i].tag = 0; arrays[i].reserved = 0; arrays[i].payload.reference = 0;
    }
    table->array_values = arrays;
    table->array_capacity = new_capacity;
    table->storage_generation++;
    return 1;
}

STENCIL(lua55_v2_setlist)(Lua55NativeFrameV2 *frame)
{
    uint32_t base_reg = V2_SETLIST_BASE_HOLE;
    __asm__ volatile ("" : "+r"(base_reg));
    uint32_t count = V2_SETLIST_COUNT_HOLE;
    __asm__ volatile ("" : "+r"(count));
    int64_t key_base = (int64_t)V2_SETLIST_KEY_HOLE;
    __asm__ volatile ("" : "+r"(key_base));
    Lua55ValueV2 *table_cell = &frame->values[base_reg];
    Lua55GuestTableV2 *table = v2_learn_table(frame, table_cell);
    if (table == 0) V2_TABLE_REJECT(frame, LUA55_V2_REJECT_INVALID_OBJECT);
    if (count == 0) V2_TABLE_REJECT(frame, LUA55_V2_REJECT_INVALID_OBJECT);
    if ((uint64_t)(key_base + count) > table->array_capacity) {
        if (!v2_grow_array(frame, table, (uint64_t)(key_base + count))) {
            V2_PUBLISH_OVERFLOW(frame, LUA55_V2_OUTCOME_HEAP_OVERFLOW, 0, 0);
            LUA55_CPS_HOST_EXIT(frame);
        }
    }
    uint32_t i;
    for (i = 1; i <= count; i++) {
        v2_table_set(table, &table->array_values[key_base + i - 1],
            &frame->values[base_reg + i]);
    }
    LUA55_RESIDUAL_NEXT(frame);
}

/* Constant-value variants of the table writes: the RK value is a constant
   (const_tag/const_int/const_flt/const_ref holes), not a register. */
STENCIL(lua55_v2_seti_const)(Lua55NativeFrameV2 *frame)
{
    uint32_t receiver_reg = V2_RECEIVER_HOLE;
    __asm__ volatile ("" : "+r"(receiver_reg));
    V2_VALUE_CONST_CELL()
    int64_t key = (int64_t)V2_INT_KEY_HOLE;
    __asm__ volatile ("" : "+r"(key));
    Lua55ValueV2 *receiver = &frame->values[receiver_reg];
    Lua55GuestTableV2 *table = v2_learn_table(frame, receiver);
    if (table == 0) V2_TABLE_REJECT(frame, LUA55_V2_REJECT_INVALID_OBJECT);
    Lua55ValueV2 *cell = v2_array_slot(table, key);
    if (cell == 0) {
        if (key >= 1 && v2_grow_array(frame, table, (uint64_t)key))
            cell = v2_array_slot(table, key);
        else V2_TABLE_REJECT(frame, LUA55_V2_REJECT_INVALID_OBJECT);
    }
    v2_table_set(table, cell, value);
    LUA55_RESIDUAL_NEXT(frame);
}

STENCIL(lua55_v2_setfield_const)(Lua55NativeFrameV2 *frame)
{
    uint32_t receiver_reg = V2_RECEIVER_HOLE;
    __asm__ volatile ("" : "+r"(receiver_reg));
    V2_VALUE_CONST_CELL()
    uint64_t key_ref = (uint64_t)V2_KEY_REF_HOLE;
    __asm__ volatile ("" : "+r"(key_ref));
    Lua55ValueV2 *receiver = &frame->values[receiver_reg];
    Lua55GuestTableV2 *table = v2_learn_table(frame, receiver);
    if (table == 0) V2_TABLE_REJECT(frame, LUA55_V2_REJECT_INVALID_OBJECT);
    Lua55ValueV2 *cell = v2_find_field(table, (uintptr_t)key_ref, 1);
    if (cell == 0) V2_TABLE_REJECT(frame, LUA55_V2_REJECT_INVALID_OBJECT);
    v2_table_set(table, cell, value);
    LUA55_RESIDUAL_NEXT(frame);
}

STENCIL(lua55_v2_settable_const)(Lua55NativeFrameV2 *frame)
{
    uint32_t receiver_reg = V2_RECEIVER_HOLE;
    __asm__ volatile ("" : "+r"(receiver_reg));
    uint32_t key_reg = V2_KEY_REG_HOLE;
    __asm__ volatile ("" : "+r"(key_reg));
    V2_VALUE_CONST_CELL()
    Lua55ValueV2 *receiver = &frame->values[receiver_reg];
    Lua55GuestTableV2 *table = v2_learn_table(frame, receiver);
    if (table == 0) V2_TABLE_REJECT(frame, LUA55_V2_REJECT_INVALID_OBJECT);
    Lua55ValueV2 *key = &frame->values[key_reg];
    Lua55ValueV2 *cell;
    if (key->tag == LUA55_VALUE_INTEGER) {
        cell = v2_array_slot(table, key->payload.integer);
        if (cell == 0 && key->payload.integer >= 1
            && v2_grow_array(frame, table, (uint64_t)key->payload.integer))
            cell = v2_array_slot(table, key->payload.integer);
    } else if (v2_is_string_tag(key->tag))
        cell = v2_find_field(table, (uintptr_t)key->payload.reference, 1);
    else V2_TABLE_REJECT(frame, LUA55_V2_REJECT_UNSUPPORTED_METAMETHOD);
    if (cell == 0) V2_TABLE_REJECT(frame, LUA55_V2_REJECT_INVALID_OBJECT);
    v2_table_set(table, cell, value);
    LUA55_RESIDUAL_NEXT(frame);
}

/* ======================================================================= */
/* 80-81: vararg family (83 VARARGPREP is a host-arranged boundary)        */
/* ======================================================================= */

STENCIL(lua55_v2_vararg)(Lua55NativeFrameV2 *frame)
{
    uint32_t target_reg = V2_TARGET_HOLE;
    __asm__ volatile ("" : "+r"(target_reg));
    int32_t wanted = (int32_t)V2_WANTED_HOLE;
    __asm__ volatile ("" : "+r"(wanted));
    uint32_t nargs = frame->vararg_count;
    uint32_t touse = (wanted == -1) ? nargs : (nargs > (uint32_t)wanted
        ? (uint32_t)wanted : nargs);
    Lua55ValueV2 *slice = frame->values + frame->value_capacity;
    uint32_t i;
    for (i = 0; i < touse; i++)
        frame->values[target_reg + i] = slice[i];
    if (wanted != -1) {
        for (i = touse; i < (uint32_t)wanted; i++)
            SET_TAG(&frame->values[target_reg + i], LUA55_VALUE_NIL);
        frame->top = target_reg + (uint32_t)wanted;
    } else {
        frame->top = target_reg + touse;
    }
    LUA55_RESIDUAL_NEXT(frame);
}

STENCIL(lua55_v2_getvarg)(Lua55NativeFrameV2 *frame)
{
    uint32_t target_reg = V2_TARGET_HOLE;
    __asm__ volatile ("" : "+r"(target_reg));
    uint32_t key_reg = V2_KEY_REG_HOLE;
    __asm__ volatile ("" : "+r"(key_reg));
    Lua55ValueV2 *target = &frame->values[target_reg];
    Lua55ValueV2 *key = &frame->values[key_reg];
    if (key->tag == LUA55_VALUE_INTEGER) {
        int64_t n = key->payload.integer;
        uint32_t nargs = frame->vararg_count;
        if (n >= 1 && (uint64_t)n <= nargs) {
            Lua55ValueV2 *slice = frame->values + frame->value_capacity;
            *target = slice[n - 1];
        } else {
            SET_TAG(target, LUA55_VALUE_NIL);
            target->payload.reference = 0;
        }
    } else if (v2_is_string_tag(key->tag)) {
        Lua55GuestStringV2 *str = (Lua55GuestStringV2 *)key->payload.reference;
        if (str != 0 && str->length == 1 && str->bytes[0] == 'n') {
            SET_TAG(target, LUA55_VALUE_INTEGER);
            target->payload.integer = (int64_t)frame->vararg_count;
        } else {
            SET_TAG(target, LUA55_VALUE_NIL);
            target->payload.reference = 0;
        }
    } else {
        SET_TAG(target, LUA55_VALUE_NIL);
        target->payload.reference = 0;
    }
    LUA55_RESIDUAL_NEXT(frame);
}

/* ======================================================================= */
/* 75-77: generic for (TFOR)                                               */
/* ======================================================================= */

STENCIL(lua55_v2_tforprep)(Lua55NativeFrameV2 *frame)
{
    uint32_t A = V2_BASE_INDEX_HOLE;
    __asm__ volatile ("" : "+r"(A));
    uintptr_t call_link = (uintptr_t)V2_TAKEN_HOLE;
    __asm__ volatile ("" : "+r"(call_link));
    Lua55ValueV2 *slot2 = &frame->values[A + 2];
    Lua55ValueV2 *slot3 = &frame->values[A + 3];
    Lua55ValueV2 temp = *slot3;
    *slot3 = *slot2;
    *slot2 = temp;
    /* the closing value now sits at R[A+2]; to-be-closed support rejects */
    if (slot2->tag != LUA55_VALUE_NIL) {
        V2_REJECT(frame, LUA55_V2_REJECT_UNSUPPORTED_METAMETHOD);
        LUA55_CPS_HOST_EXIT(frame);
    }
    return ((Lua55NativeEntryV2)call_link)(frame);
}

STENCIL(lua55_v2_tforcall)(Lua55NativeFrameV2 *frame)
{
    uint32_t A = V2_A_HOLE;
    __asm__ volatile ("" : "+r"(A));
    uint32_t C = V2_C_HOLE;
    __asm__ volatile ("" : "+r"(C));
    uint32_t pc = V2_PC_HOLE;
    __asm__ volatile ("" : "+r"(pc));
    uint64_t cont = V2_CONTINUATION_HOLE;
    __asm__ volatile ("" : "+r"(cont));
    Lua55ValueV2 *callee_cell = &frame->values[A];
    if (callee_cell->tag == LUA55_VALUE_CLOSURE) {
        Lua55NativeClosureV2 *closure =
            (Lua55NativeClosureV2 *)callee_cell->payload.reference;
        Lua55NativeInvocationV2 *inv = frame->invocation;
        if (closure != 0 && closure->header.kind == LUA55_OBJECT_CLOSURE
            && closure->proto_index < inv->function_count) {
            Lua55NativeFunctionDescriptorV2 *desc =
                &inv->functions[closure->proto_index];
            Lua55NativeEntryV2 entry = desc->entry;
            if (entry != 0) {
                uint32_t maxstack = desc->maxstacksize;
                uint32_t nparams = desc->numparams;
                if ((uint32_t)(A + 3 + C) > frame->value_capacity) {
                    inv->outcome.discriminant = LUA55_V2_OUTCOME_VALUE_OVERFLOW;
                    inv->outcome.u.overflow.required = (uint64_t)(A + 3 + C);
                    inv->outcome.u.overflow.available = frame->value_capacity;
                    inv->outcome.u.overflow.pc = pc;
                    LUA55_CPS_HOST_EXIT(frame);
                }
                size_t frame_bytes = (sizeof(Lua55NativeFrameV2)
                    + (size_t)desc->value_capacity * sizeof(Lua55ValueV2)
                    + (size_t)desc->tbc_capacity * sizeof(Lua55TbcNodeV2) + 15)
                    & ~(size_t)15;
                uint8_t *next = inv->frame_next + frame_bytes;
                if (next > inv->frame_end) {
                    inv->outcome.discriminant = LUA55_V2_OUTCOME_STACK_OVERFLOW;
                    inv->outcome.u.overflow.required = (uint64_t)frame_bytes;
                    inv->outcome.u.overflow.available =
                        (uint64_t)(inv->frame_end - inv->frame_next);
                    inv->outcome.u.overflow.pc = pc;
                    LUA55_CPS_HOST_EXIT(frame);
                }
                Lua55NativeFrameV2 *cframe =
                    (Lua55NativeFrameV2 *)inv->frame_next;
                inv->frame_next = next;
                cframe->values = (Lua55ValueV2 *)
                    ((uint8_t *)cframe + sizeof(Lua55NativeFrameV2));
                cframe->tbc_nodes = (Lua55TbcNodeV2 *)
                    (cframe->values + desc->value_capacity);
                cframe->upvalues = closure->cells;
                cframe->value_count = maxstack;
                cframe->value_capacity = desc->value_capacity;
                cframe->top = 2 < desc->value_capacity ? 2 : desc->value_capacity;
                cframe->vararg_count = 0;
                cframe->tbc_count = 0;
                cframe->tbc_capacity = desc->tbc_capacity;
                cframe->invocation = inv;
                cframe->caller = frame;
                cframe->return_link.entry = (Lua55NativeEntryV2)cont;
                cframe->return_link.subject = frame;
                /* results land at R[A+3..A+2+C] (the control + values) */
                cframe->result_sink.values = frame->values + A + 3;
                cframe->result_sink.top = &frame->top;
                cframe->result_sink.base = A + 3;
                cframe->result_sink.count = (int32_t)C;
                cframe->result_sink.capacity = frame->value_capacity;
                cframe->open_upvalues = 0;
                cframe->values[0] = frame->values[A + 1];   /* state */
                cframe->values[1] = frame->values[A + 3];   /* control */
                uint32_t i;
                for (i = 2; i < nparams; i++)
                    SET_TAG(&cframe->values[i], LUA55_VALUE_NIL);
                inv->current_frame = cframe;
                return entry(cframe);
            }
        }
        if (closure->header.kind == LUA55_OBJECT_BUILTIN) {
            inv->outcome.discriminant = LUA55_V2_OUTCOME_HOST_CALL;
            inv->outcome.u.host_call.resume_entry = (Lua55NativeEntryV2)cont;
            inv->outcome.u.host_call.a = A;
            inv->outcome.u.host_call.b = 3;
            inv->outcome.u.host_call.c = C;
            inv->outcome.u.host_call.pc = pc;
            inv->outcome.u.host_call.host_id = 0;
            inv->outcome.u.host_call.reserved = 1;   /* tforcall marker */
            LUA55_CPS_HOST_EXIT(frame);
        }
        V2_REJECT(frame, LUA55_V2_REJECT_UNSUPPORTED_CALLEE);
        LUA55_CPS_HOST_EXIT(frame);
    }
    V2_REJECT(frame, LUA55_V2_REJECT_UNSUPPORTED_CALLEE);
    LUA55_CPS_HOST_EXIT(frame);
}

STENCIL(lua55_v2_tforloop)(Lua55NativeFrameV2 *frame)
{
    uint32_t A = V2_BASE_INDEX_HOLE;
    __asm__ volatile ("" : "+r"(A));
    uintptr_t body = (uintptr_t)V2_BODY_HOLE;
    __asm__ volatile ("" : "+r"(body));
    Lua55ValueV2 *control = &frame->values[A + 3];
    if (control->tag != LUA55_VALUE_NIL) {
        return ((Lua55NativeEntryV2)body)(frame);
    }
    LUA55_RESIDUAL_NEXT(frame);
}

/* ======================================================================= */
/* 54-55: CLOSE and TBC (closed subset: open upvalues; nil/false TBC)      */
/* ======================================================================= */

STENCIL(lua55_v2_close)(Lua55NativeFrameV2 *frame)
{
    uint32_t A = V2_A_HOLE;
    __asm__ volatile ("" : "+r"(A));
    Lua55UpvalueCellV2 **cellp = &frame->open_upvalues;
    while (*cellp != 0) {
        Lua55UpvalueCellV2 *cell = *cellp;
        if (cell->open_slot >= &frame->values[A]) {
            cell->closed_value = cell->open_slot[0];
            cell->open_slot = 0;
            cell->state = LUA55_UPVALUE_CLOSED;
            cell->generation = cell->generation + 1;
            *cellp = cell->next_open;
            cell->next_open = 0;
        } else {
            cellp = &cell->next_open;
        }
    }
    LUA55_RESIDUAL_NEXT(frame);
}

STENCIL(lua55_v2_tbc)(Lua55NativeFrameV2 *frame)
{
    uint32_t A = V2_A_HOLE;
    __asm__ volatile ("" : "+r"(A));
    Lua55ValueV2 *value = &frame->values[A];
    if (value->tag != LUA55_VALUE_NIL && value->tag != LUA55_VALUE_FALSE) {
        V2_REJECT(frame, LUA55_V2_REJECT_UNSUPPORTED_METAMETHOD);
        LUA55_CPS_HOST_EXIT(frame);
    }
    LUA55_RESIDUAL_NEXT(frame);
}

/* ======================================================================= */
/* 53: CONCAT (exact Lua 5.5 formatting via the patched fmt helpers)       */
/* ======================================================================= */

#define V2_DTOA_ADDR UINT64_C(0x5152535455565758)
#define V2_ITOA_ADDR UINT64_C(0x6162636465666768)
#define V2_MINSTR 40

typedef int (*v2_fmt_fn)(double, char *);
typedef int (*v2_itoa_fn)(int64_t, char *);

static inline v2_fmt_fn v2_dtoa_fn(void)
{
    uint64_t addr = V2_DTOA_ADDR;
    __asm__ volatile ("" : "+r"(addr));
    union { uint64_t u; v2_fmt_fn fn; } u;
    u.u = addr;
    return u.fn;
}
static inline v2_itoa_fn v2_itoa_fn_get(void)
{
    uint64_t addr = V2_ITOA_ADDR;
    __asm__ volatile ("" : "+r"(addr));
    union { uint64_t u; v2_itoa_fn fn; } u;
    u.u = addr;
    return u.fn;
}

STENCIL(lua55_v2_concat)(Lua55NativeFrameV2 *frame)
{
    uint32_t target_reg = V2_TARGET_HOLE;
    __asm__ volatile ("" : "+r"(target_reg));
    uint32_t base_reg = V2_SETLIST_BASE_HOLE;
    __asm__ volatile ("" : "+r"(base_reg));
    uint32_t count = V2_SETLIST_COUNT_HOLE;
    __asm__ volatile ("" : "+r"(count));
    Lua55GuestHeapV2 *heap = frame->invocation->heap;
    if (heap == 0 || heap->table_region == 0) {
        V2_REJECT(frame, LUA55_V2_REJECT_INVALID_OBJECT);
        LUA55_CPS_HOST_EXIT(frame);
    }
    uint64_t total = 0;
    uint32_t i;
    for (i = 0; i < count; i++) {
        Lua55ValueV2 *val = &frame->values[base_reg + i];
        if (v2_is_string_tag(val->tag)) {
            Lua55GuestStringV2 *str = (Lua55GuestStringV2 *)val->payload.reference;
            if (str == 0) { V2_REJECT(frame, LUA55_V2_REJECT_INVALID_OBJECT);
                            LUA55_CPS_HOST_EXIT(frame); }
            total += str->length;
        } else if (val->tag == LUA55_VALUE_INTEGER) {
            char buf[24];
            total += (uint64_t)v2_itoa_fn_get()(val->payload.integer, buf);
        } else if (val->tag == LUA55_VALUE_FLOAT) {
            char buf[32];
            total += (uint64_t)v2_dtoa_fn()(val->payload.floating, buf);
        } else {
            V2_REJECT(frame, LUA55_V2_REJECT_UNSUPPORTED_METAMETHOD);
            LUA55_CPS_HOST_EXIT(frame);
        }
    }
    size_t bytes_size = total > 0 ? (size_t)total : 1;
    size_t alloc = sizeof(Lua55GuestStringV2) + bytes_size;
    uintptr_t at = v2_heap_bump(heap, alloc);
    if (at == 0) { V2_PUBLISH_OVERFLOW(frame, LUA55_V2_OUTCOME_HEAP_OVERFLOW, 0, 0);
                   LUA55_CPS_HOST_EXIT(frame); }
    Lua55GuestStringV2 *str = (Lua55GuestStringV2 *)at;
    uint8_t *bytes = (uint8_t *)(at + sizeof(Lua55GuestStringV2));
    str->header.kind = total <= V2_MINSTR
        ? LUA55_OBJECT_SHORT_STRING : LUA55_OBJECT_LONG_STRING;
    str->header.generation = heap->object_count + 1;
    str->length = (uint32_t)total;
    str->hash = 0;
    str->bytes = bytes;
    heap->object_count++;
    uint8_t *out = bytes;
    for (i = 0; i < count; i++) {
        Lua55ValueV2 *val = &frame->values[base_reg + i];
        if (v2_is_string_tag(val->tag)) {
            Lua55GuestStringV2 *s = (Lua55GuestStringV2 *)val->payload.reference;
            uint32_t n = s->length;
            uint32_t j;
            for (j = 0; j < n; j++) out[j] = s->bytes[j];
            out += n;
        } else if (val->tag == LUA55_VALUE_INTEGER) {
            char buf[24];
            int m = v2_itoa_fn_get()(val->payload.integer, buf);
            int j;
            for (j = 0; j < m; j++) out[j] = (uint8_t)buf[j];
            out += m;
        } else {
            char buf[32];
            int m = v2_dtoa_fn()(val->payload.floating, buf);
            int j;
            for (j = 0; j < m; j++) out[j] = (uint8_t)buf[j];
            out += m;
        }
    }
    Lua55ValueV2 *target = &frame->values[target_reg];
    SET_TAG(target, total <= V2_MINSTR
        ? LUA55_VALUE_SHORT_STRING : LUA55_VALUE_LONG_STRING);
    target->payload.reference = (uintptr_t)str;
    LUA55_RESIDUAL_NEXT(frame);
}

/* ======================================================================= */
/* 82: ERRNNIL (guest error when R[A] is not nil)                          */
/* ======================================================================= */

STENCIL(lua55_v2_errnnil)(Lua55NativeFrameV2 *frame)
{
    uint32_t A = V2_A_HOLE;
    __asm__ volatile ("" : "+r"(A));
    uint32_t pc = V2_PC_HOLE;
    __asm__ volatile ("" : "+r"(pc));
    Lua55ValueV2 *value = &frame->values[A];
    if (value->tag != LUA55_VALUE_NIL) {
        frame->invocation->outcome.discriminant = LUA55_V2_OUTCOME_GUEST_ERROR;
        frame->invocation->outcome.u.error.error_kind = 1;
        frame->invocation->outcome.u.error.pc = pc;
        frame->invocation->outcome.u.error.value = *value;
        LUA55_CPS_HOST_EXIT(frame);
    }
    LUA55_RESIDUAL_NEXT(frame);
}
