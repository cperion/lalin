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

/* Every logical hole has a unique byte pattern. The bank extractor rejects
   duplicate or overlapping patterns before publication; runtime publication
   then requires every physical hole site to be patched before mprotect. */
#define V2_TARGET_HOLE UINT32_C(0x6e7f8091)
#define V2_SOURCE_HOLE UINT32_C(0x6a6b6c6d)
#define V2_TARGET_DISP_HOLE INT32_C(0x34455667)
#define V2_RECEIVER_DISP_HOLE INT32_C(0x2b4d6f81)
#define V2_OBJECT_DISP_HOLE INT32_C(0x31537597)
#define V2_SOURCE_DISP_HOLE INT32_C(0x24354657)
#define V2_TOP_INDEX_HOLE UINT32_C(0x2547698b)
#define V2_BASE_DISP_HOLE INT32_C(0x1d3f5b79)
#define V2_ARRAY_DISP_HOLE INT32_C(0x3b5d7f91)
#define V2_KEY_DISP_HOLE INT32_C(0x13579bdf)
#define V2_LEFT_HOLE   UINT32_C(0x394a5b6c)
#define V2_RIGHT_HOLE  UINT32_C(0x5e5f6061)
#define V2_LEFT_DISP_HOLE INT32_C(0x14253647)
#define V2_RIGHT_DISP_HOLE INT32_C(0x45671829)
#define V2_UPVALUE_HOLE UINT32_C(0x28394a5b)
#define V2_INTEGER_BITS UINT64_C(0xb17c3e95d2a8640f)
#define V2_FLOAT_BITS UINT64_C(0x8877665544332211)
#define V2_SPAN_HOLE UINT32_C(0x777)
#define V2_CONST_TAG UINT32_C(0x3c3b3a39)
#define V2_CONST_INT UINT64_C(0x2122232425262728)
#define V2_CONST_FLT UINT64_C(0x123456789abcdef0)
#define V2_CONST_REF UINT64_C(0x0abcdef012345679)
#define V2_INT_IMM_HOLE UINT64_C(0xd41b8e63a7295c0f)
#define V2_K_HOLE UINT32_C(0x71727374)
#define V2_LINK_HOLE UINT64_C(0xc31f7a9d52e6840b)
#define V2_TAKEN_HOLE UINT64_C(0x0badf00dcafed00d)
#define V2_TAIL_RETURN_HOLE UINT64_C(0xa1b2c3d4e5f60718)
#define V2_FALL_HOLE UINT64_C(0x0ddc0ffeebadf00d)
#define V2_BODY_HOLE UINT64_C(0x1234abcddcba4321)
#define V2_SKIP_HOLE UINT64_C(0x2345bcdeedcb5432)
#define V2_A_HOLE UINT32_C(0x01020304)
#define V2_B_HOLE UINT32_C(0x05060708)
#define V2_C_HOLE UINT32_C(0x09101112)
#define V2_PC_HOLE UINT32_C(0x13141516)
#define V2_ARG_COUNT_HOLE UINT32_C(0x31425364)
#define V2_RESULT_COUNT_HOLE UINT32_C(0x72513019)
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
#define V2_RECEIVER_HOLE UINT32_C(0x4a4b4c4d)
#define V2_KEY_REG_HOLE UINT32_C(0x2e2f3031)
#define V2_OBJECT_TARGET_HOLE UINT32_C(0x666)
#define V2_INT_KEY_HOLE UINT32_C(0x55667788)
#define V2_KEY_REF_HOLE UINT64_C(0x8172837485768778)
#define V2_ARRAY_CAP_HOLE UINT32_C(0x0a0b0c0d)
#define V2_FIELD_CAP_HOLE UINT32_C(0x1a1b1c1d)
#define V2_FIELD_SLOT_HOLE UINT32_C(0x63748596)
#define V2_FIELD_LAYOUT_CAP_HOLE UINT32_C(0x96857463)
#define V2_OCC_SLOT_HOLE UINT32_C(0x2a3b4c5d)   /* learner per-occurrence slot */
#define V2_SITE_ID_HOLE UINT32_C(0x1f2e3d4c)    /* learner NEWTABLE site slot */
#define V2_NEED_GROW_LINK_HOLE UINT64_C(0xc8c9cacbcccdcecf) /* NeedGrow data exit */
#define V2_NEED_CREATE_LINK_HOLE UINT64_C(0xebeae9e8e7e6e5e4) /* NeedCreate data exit */
#define V2_FIELD_RECEIVER_HOLE UINT32_C(0x5a5b5c5d)     /* accumulate field table */
#define V2_SOURCE_KEY_REF_HOLE UINT64_C(0x0f1e2d3c4b5a6978) /* accumulate source field key */
#define V2_RESUME_LINK_HOLE UINT64_C(0xd2d3d4d5d6d7d8d9) /* data-exit resume */
#define V2_MISMATCH_EXIT_HOLE UINT64_C(0xb7b6b5b4b3b2b1b0) /* typed mismatch exit */
#define V2_FRAGMENT_NEXT_HOLE UINT64_C(0x9f8e7d6c5b4a3928) /* composed fragment edge */
#define V2_ACCUM_KEY2_HOLE UINT32_C(0x6e6f7071)         /* accumulate write-key copy */

#define V2_LEARN_SLOT()                                                     \
    V2_HOLE32(slot, V2_OCC_SLOT_HOLE);

static inline void v2_learn_pair(Lua55NativeFrameV2 *frame,
    uint32_t occ_slot, uint32_t ta, uint32_t tb);
static inline void v2_learn_key_tag(Lua55NativeFrameV2 *frame,
    uint32_t occ_slot, uint32_t tag);
static inline void v2_learn_callee(Lua55NativeFrameV2 *frame,
    uint32_t occ_slot, uint32_t klass, uint32_t is_vararg);
static inline void v2_learn_concat(Lua55NativeFrameV2 *frame,
    uint32_t occ_slot, uint32_t count, uint32_t t0, uint32_t t1, uint32_t t2,
    uint32_t t3, uint32_t t4);
static inline void v2_learn_super_for_addi(Lua55NativeFrameV2 *frame,
    uint32_t occ_slot, uint32_t init_tag, uint32_t limit_tag,
    uint32_t step_tag, uint32_t accumulator_tag, uint32_t sign);
#define V2_SETLIST_BASE_HOLE UINT32_C(0x999)
#define V2_SETLIST_COUNT_HOLE UINT32_C(0x0c0d0e0f)
#define V2_SETLIST_KEY_HOLE UINT32_C(0x1c1d1e1f)
#define V2_WANTED_HOLE UINT32_C(0x0b1c2d3e)

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

#define V2_HOLE32(name, hole)                                               \
    uint32_t name = (uint32_t)(hole);                                       \
    __asm__ volatile ("" : "+r"(name))

#define V2_VALUE(local, reg, hole)                                          \
    V2_HOLE32(reg, hole);                                                   \
    Lua55ValueV2 *local = &frame->values[reg];
#define V2_VALUE_DISP(local, hole)                                          \
    Lua55ValueV2 *local;                                                    \
    __asm__ volatile ("leaq %c1(%2), %0"                                  \
        : "=r"(local) : "i"((int32_t)(hole)), "r"(frame->values));
#define V2_VALUE_DISP_SET(local, hole)                                      \
    __asm__ volatile ("leaq %c1(%2), %0"                                  \
        : "=r"(local) : "i"((int32_t)(hole)), "r"(frame->values));
#define V2_VALUE_BASE_DISP(local, base, hole)                                \
    Lua55ValueV2 *local;                                                    \
    __asm__ volatile ("leaq %c1(%2), %0"                                  \
        : "=r"(local) : "i"((int32_t)(hole)), "r"(base));

STENCIL(lua55_v2_move)(Lua55NativeFrameV2 *frame)
{
    V2_VALUE_DISP(target, V2_TARGET_DISP_HOLE)
    V2_VALUE_DISP(source, V2_SOURCE_DISP_HOLE)
    *target = *source;
    LUA55_RESIDUAL_NEXT(frame);
}

STENCIL(lua55_v2_loadi)(Lua55NativeFrameV2 *frame)
{
    V2_VALUE_DISP(target, V2_TARGET_DISP_HOLE)
    int64_t bits = (int64_t)V2_INTEGER_BITS;
    __asm__ volatile ("" : "+r"(bits));
    SET_TAG(target, LUA55_VALUE_INTEGER);
    target->payload.integer = bits;
    LUA55_RESIDUAL_NEXT(frame);
}

STENCIL(lua55_v2_loadf)(Lua55NativeFrameV2 *frame)
{
    V2_VALUE_DISP(target, V2_TARGET_DISP_HOLE)
    uint64_t bits = V2_FLOAT_BITS;
    __asm__ volatile ("" : "+r"(bits));
    SET_TAG(target, LUA55_VALUE_FLOAT);
    memcpy(&target->payload.floating, &bits, sizeof(bits));
    LUA55_RESIDUAL_NEXT(frame);
}

#define V2_LOADK_BODY()                                                     \
    V2_VALUE_DISP(target, V2_TARGET_DISP_HOLE)                               \
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
    V2_VALUE_DISP(target, V2_TARGET_DISP_HOLE)
    SET_TAG(target, LUA55_VALUE_FALSE);
    LUA55_RESIDUAL_NEXT(frame);
}

STENCIL(lua55_v2_loadfalse_skip)(Lua55NativeFrameV2 *frame)
{
    V2_VALUE_DISP(target, V2_TARGET_DISP_HOLE)
    SET_TAG(target, LUA55_VALUE_FALSE);
    LUA55_RESIDUAL_NEXT(frame);
}

STENCIL(lua55_v2_loadtrue)(Lua55NativeFrameV2 *frame)
{
    V2_VALUE_DISP(target, V2_TARGET_DISP_HOLE)
    SET_TAG(target, LUA55_VALUE_TRUE);
    LUA55_RESIDUAL_NEXT(frame);
}

STENCIL(lua55_v2_loadnil)(Lua55NativeFrameV2 *frame)
{
    V2_VALUE(target, target_reg, V2_TARGET_HOLE)
    V2_HOLE32(span, V2_SPAN_HOLE);
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
    V2_VALUE_DISP(target, V2_TARGET_DISP_HOLE)
    V2_HOLE32(upvalue_reg, V2_UPVALUE_HOLE);
    Lua55UpvalueCellV2 *cell = frame->upvalues[upvalue_reg];
    *target = cell->state == LUA55_UPVALUE_OPEN
        ? cell->open_slot[0] : cell->closed_value;
    LUA55_RESIDUAL_NEXT(frame);
}

STENCIL(lua55_v2_setupval)(Lua55NativeFrameV2 *frame)
{
    V2_HOLE32(upvalue_reg, V2_UPVALUE_HOLE);
    V2_VALUE_DISP(source, V2_SOURCE_DISP_HOLE)
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

#define V2_ARITH_BASE()                                                      \
    V2_VALUE_DISP(target, V2_TARGET_DISP_HOLE)                              \
    V2_VALUE_DISP(left, V2_LEFT_DISP_HOLE)                                  \
    Lua55ValueV2 *right;
#define V2_ARITH_PROLOGUE_RR()                                              \
    V2_ARITH_BASE()                                                         \
    V2_VALUE_DISP_SET(right, V2_RIGHT_DISP_HOLE)
#define V2_ARITH_PROLOGUE_SYNTH(right_init)                                 \
    V2_ARITH_BASE()                                                         \
    right_init;

#define V2_BIN(name, intfn, flt_left, flt_right, flt_both, right_init)      \
STENCIL(lua55_v2l_##name)(Lua55NativeFrameV2 *frame)                        \
{                                                                           \
    right_init                                                              \
    V2_LEARN_SLOT()                                                         \
    v2_learn_pair(frame, slot, left->tag, right->tag);                      \
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
STENCIL(lua55_v2l_##name)(Lua55NativeFrameV2 *frame)                        \
{                                                                           \
    right_init                                                              \
    V2_LEARN_SLOT()                                                         \
    v2_learn_pair(frame, slot, left->tag, right->tag);                      \
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
STENCIL(lua55_v2l_##name)(Lua55NativeFrameV2 *frame)                        \
{                                                                           \
    right_init                                                              \
    V2_LEARN_SLOT()                                                         \
    v2_learn_pair(frame, slot, left->tag, right->tag);                      \
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

#define V2_SHIFT(name, shiftexpr, right_init)                               \
STENCIL(lua55_v2l_##name)(Lua55NativeFrameV2 *frame)                        \
{                                                                           \
    right_init                                                              \
    V2_LEARN_SLOT()                                                         \
    v2_learn_pair(frame, slot, left->tag, right->tag);                      \
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
    target->payload.integer = shiftexpr;                                    \
    LUA55_RESIDUAL_NEXT(frame);                                             \
}

#define V2_DIV_BODY(right_init)                                             \
    right_init                                                              \
    V2_LEARN_SLOT()                                                         \
    v2_learn_pair(frame, slot, left->tag, right->tag);                      \
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
    right_init                                                              \
    V2_LEARN_SLOT()                                                         \
    v2_learn_pair(frame, slot, left->tag, right->tag);                      \
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

V2_BIN(add, v2_int_add, FLT_ADD, FLT_ADD, FLT_ADD, V2_ARITH_PROLOGUE_RR())
V2_BIN(sub, v2_int_sub, FLT_SUB, FLT_SUB, FLT_SUB, V2_ARITH_PROLOGUE_RR())
V2_BIN(mul, v2_int_mul, FLT_MUL, FLT_MUL, FLT_MUL, V2_ARITH_PROLOGUE_RR())
V2_BIN(addi, v2_int_add, FLT_ADD, FLT_ADD, FLT_ADD, V2_ARITH_PROLOGUE_SYNTH(V2_ARITH_RIGHT_INIT))
V2_BIN(addk, v2_int_add, FLT_ADD, FLT_ADD, FLT_ADD, V2_ARITH_PROLOGUE_SYNTH(V2_ARITH_CONST_RIGHT))
V2_BIN(subk, v2_int_sub, FLT_SUB, FLT_SUB, FLT_SUB, V2_ARITH_PROLOGUE_SYNTH(V2_ARITH_CONST_RIGHT))
V2_BIN(mulk, v2_int_mul, FLT_MUL, FLT_MUL, FLT_MUL, V2_ARITH_PROLOGUE_SYNTH(V2_ARITH_CONST_RIGHT))
V2_DIVMOD(idiv, v2_idiv, v2_flt_idiv, V2_ARITH_PROLOGUE_RR())
V2_DIVMOD(mod, v2_mod, v2_fmod, V2_ARITH_PROLOGUE_RR())
V2_DIVMOD(idivk, v2_idiv, v2_flt_idiv, V2_ARITH_PROLOGUE_SYNTH(V2_ARITH_CONST_RIGHT))
V2_DIVMOD(modk, v2_mod, v2_fmod, V2_ARITH_PROLOGUE_SYNTH(V2_ARITH_CONST_RIGHT))
V2_BITWISE(band, v2_int_band, V2_ARITH_PROLOGUE_RR())
V2_BITWISE(bor, v2_int_bor, V2_ARITH_PROLOGUE_RR())
V2_BITWISE(bxor, v2_int_bxor, V2_ARITH_PROLOGUE_RR())
V2_BITWISE(bandk, v2_int_band, V2_ARITH_PROLOGUE_SYNTH(V2_ARITH_CONST_RIGHT))
V2_BITWISE(bork, v2_int_bor, V2_ARITH_PROLOGUE_SYNTH(V2_ARITH_CONST_RIGHT))
V2_BITWISE(bxork, v2_int_bxor, V2_ARITH_PROLOGUE_SYNTH(V2_ARITH_CONST_RIGHT))
V2_SHIFT(shl, v2_shiftl(i1, i2), V2_ARITH_PROLOGUE_RR())
V2_SHIFT(shr, v2_shiftl(i1, -i2), V2_ARITH_PROLOGUE_RR())
V2_SHIFT(shli, v2_shiftl(i2, i1), V2_ARITH_PROLOGUE_SYNTH(V2_ARITH_RIGHT_INIT))
V2_SHIFT(shri, v2_shiftl(i1, -i2), V2_ARITH_PROLOGUE_SYNTH(V2_ARITH_RIGHT_INIT))
STENCIL(lua55_v2l_div)(Lua55NativeFrameV2 *frame) { V2_DIV_BODY(V2_ARITH_PROLOGUE_RR()) }
STENCIL(lua55_v2l_divk)(Lua55NativeFrameV2 *frame) { V2_DIV_BODY(V2_ARITH_PROLOGUE_SYNTH(V2_ARITH_CONST_RIGHT)) }
STENCIL(lua55_v2l_pow)(Lua55NativeFrameV2 *frame) { V2_POW_BODY(V2_ARITH_PROLOGUE_RR()) }
STENCIL(lua55_v2l_powk)(Lua55NativeFrameV2 *frame) { V2_POW_BODY(V2_ARITH_PROLOGUE_SYNTH(V2_ARITH_CONST_RIGHT)) }

/* ======================================================================= */
/* 49-52: unary                                                             */
/* ======================================================================= */

#define V2_UNARY_PROLOGUE()                                                 \
    V2_VALUE_DISP(target, V2_TARGET_DISP_HOLE)                              \
    V2_VALUE_DISP(source, V2_SOURCE_DISP_HOLE)

STENCIL(lua55_v2l_unm)(Lua55NativeFrameV2 *frame)
{
    V2_UNARY_PROLOGUE()
    V2_LEARN_SLOT()
    v2_learn_key_tag(frame, slot, source->tag);
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

STENCIL(lua55_v2l_bnot)(Lua55NativeFrameV2 *frame)
{
    V2_UNARY_PROLOGUE()
    V2_LEARN_SLOT()
    v2_learn_key_tag(frame, slot, source->tag);
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

STENCIL(lua55_v2l_len)(Lua55NativeFrameV2 *frame)
{
    V2_UNARY_PROLOGUE()
    V2_LEARN_SLOT()
    v2_learn_key_tag(frame, slot, source->tag);
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

#define V2_CMP_BASE()                                                        \
    V2_VALUE_DISP(left, V2_LEFT_DISP_HOLE)                                  \
    Lua55ValueV2 *right;
#define V2_CMP_PROLOGUE_RR()                                                \
    V2_CMP_BASE()                                                           \
    V2_VALUE_DISP_SET(right, V2_RIGHT_DISP_HOLE)
#define V2_CMP_PROLOGUE_SYNTH(right_init)                                   \
    V2_CMP_BASE()                                                           \
    right_init;
#define V2_CMP_PROLOGUE_LEFT() V2_CMP_BASE()

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
STENCIL(lua55_v2l_##name)(Lua55NativeFrameV2 *frame)                        \
{                                                                           \
    right_init                                                              \
    V2_LEARN_SLOT()                                                         \
    v2_learn_pair(frame, slot, left->tag, right->tag);                      \
    V2_HOLE32(k, V2_K_HOLE);                                       \
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
STENCIL(lua55_v2l_##name)(Lua55NativeFrameV2 *frame)                        \
{                                                                           \
    right_init                                                              \
    V2_LEARN_SLOT()                                                         \
    v2_learn_pair(frame, slot, left->tag, right->tag);                      \
    V2_HOLE32(k, V2_K_HOLE);                                       \
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
STENCIL(lua55_v2l_##name)(Lua55NativeFrameV2 *frame)                        \
{                                                                           \
    right_init                                                              \
    V2_LEARN_SLOT()                                                         \
    v2_learn_pair(frame, slot, left->tag, right->tag);                      \
    V2_HOLE32(k, V2_K_HOLE);                                       \
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

V2_EQ(eq, V2_CMP_PROLOGUE_RR())
V2_EQ(eqk, V2_CMP_PROLOGUE_SYNTH(V2_CMP_CONST_RIGHT))
V2_EQ(eqi, V2_CMP_PROLOGUE_SYNTH(V2_CMP_RIGHT_INIT))
V2_ORD(lt, V2_CMP_PROLOGUE_RR(), 0)
V2_ORD(lti, V2_CMP_PROLOGUE_SYNTH(V2_CMP_RIGHT_INIT), 0)
V2_LE(le, V2_CMP_PROLOGUE_RR(), 0)
V2_LE(lei, V2_CMP_PROLOGUE_SYNTH(V2_CMP_RIGHT_INIT), 0)
V2_ORD(gti, V2_CMP_PROLOGUE_SYNTH(V2_CMP_RIGHT_INIT), 1)
V2_LE(gei, V2_CMP_PROLOGUE_SYNTH(V2_CMP_RIGHT_INIT), 1)

#define V2_TEST_LEAF(name, taken)                                           \
STENCIL(name)(Lua55NativeFrameV2 *frame)                                    \
{                                                                           \
    V2_VALUE_DISP(left, V2_LEFT_DISP_HOLE)                                  \
    int cond = v2_truthy(left->tag);                                        \
    taken;                                                                  \
    LUA55_RESIDUAL_NEXT(frame);                                             \
}
#define V2_TESTSET_LEAF(name, taken)                                        \
STENCIL(name)(Lua55NativeFrameV2 *frame)                                    \
{                                                                           \
    V2_VALUE_DISP(left, V2_LEFT_DISP_HOLE)                                  \
    V2_VALUE_DISP(target, V2_TARGET_DISP_HOLE)                              \
    int cond = v2_truthy(left->tag);                                        \
    *target = *left;                                                        \
    taken;                                                                  \
    LUA55_RESIDUAL_NEXT(frame);                                             \
}

V2_TEST_LEAF(lua55_v2r_test_k0, if (!cond) { V2_BRANCH_TAKEN(frame); })
V2_TEST_LEAF(lua55_v2r_test_k1, if (cond) { V2_BRANCH_TAKEN(frame); })
V2_TESTSET_LEAF(lua55_v2r_testset_k0, if (!cond) { V2_BRANCH_TAKEN(frame); })
V2_TESTSET_LEAF(lua55_v2r_testset_k1, if (cond) { V2_BRANCH_TAKEN(frame); })

/* ======================================================================= */
/* 68-72: proper-tail CPS calls, returns, and the host boundary            */
/* ======================================================================= */

STENCIL(lua55_cps_host_exit)(Lua55NativeFrameV2 *frame)
{
    (void)frame;
    return;
}

STENCIL(lua55_cps_specialization_mismatch)(Lua55NativeFrameV2 *frame)
{
    Lua55NativeInvocationV2 *inv = frame->invocation;
    inv->outcome.discriminant = LUA55_V2_OUTCOME_REJECTED;
    inv->outcome.u.rejected.rejection_kind =
        LUA55_V2_REJECT_SPECIALIZATION_MISMATCH;
    inv->outcome.u.rejected.opcode = 0;
    inv->outcome.u.rejected.pc = inv->specialization_mismatch.pc;
    inv->outcome.u.rejected.expected_tag =
        inv->specialization_mismatch.expected_tag;
    inv->outcome.u.rejected.observed_tag =
        inv->specialization_mismatch.observed_tag;
    LUA55_CPS_HOST_EXIT(frame);
}

STENCIL(lua55_v2l_call)(Lua55NativeFrameV2 *frame)
{
    uint32_t A = V2_A_HOLE;
    __asm__ volatile ("" : "+r"(A));
    uint32_t B = V2_B_HOLE;
    __asm__ volatile ("" : "+r"(B));
    uint32_t C = V2_C_HOLE;
    __asm__ volatile ("" : "+r"(C));
    V2_HOLE32(pc, V2_PC_HOLE);
    uint64_t cont = V2_CONTINUATION_HOLE;
    __asm__ volatile ("" : "+r"(cont));
    Lua55ValueV2 *callee_cell = &frame->values[A];

    V2_LEARN_SLOT()
    {
        Lua55NativeInvocationV2 *l_inv = frame->invocation;
        uint32_t klass = 3, varg = 0;
        if (callee_cell->tag == LUA55_VALUE_CLOSURE) {
            Lua55NativeClosureV2 *clo =
                (Lua55NativeClosureV2 *)callee_cell->payload.reference;
            if (clo != 0 && clo->header.kind == LUA55_OBJECT_BUILTIN) {
                klass = 2;
            } else if (clo != 0 && clo->header.kind == LUA55_OBJECT_CLOSURE
                       && clo->proto_index < l_inv->function_count) {
                Lua55NativeFunctionDescriptorV2 *d =
                    &l_inv->functions[clo->proto_index];
                if (d->entry != 0) { klass = 1; varg = d->is_vararg; }
            }
        }
        v2_learn_callee(frame, slot, klass, varg);
    }

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

STENCIL(lua55_v2l_tailcall)(Lua55NativeFrameV2 *frame)
{
    uint32_t A = V2_A_HOLE;
    __asm__ volatile ("" : "+r"(A));
    uint32_t B = V2_B_HOLE;
    __asm__ volatile ("" : "+r"(B));
    V2_HOLE32(pc, V2_PC_HOLE);
    uint64_t tail_ret = V2_TAIL_RETURN_HOLE;
    __asm__ volatile ("" : "+r"(tail_ret));
    Lua55ValueV2 *callee_cell = &frame->values[A];

    V2_LEARN_SLOT()
    {
        Lua55NativeInvocationV2 *l_inv = frame->invocation;
        uint32_t klass = 3, varg = 0;
        if (callee_cell->tag == LUA55_VALUE_CLOSURE) {
            Lua55NativeClosureV2 *clo =
                (Lua55NativeClosureV2 *)callee_cell->payload.reference;
            if (clo != 0 && clo->header.kind == LUA55_OBJECT_BUILTIN) {
                klass = 2;
            } else if (clo != 0 && clo->header.kind == LUA55_OBJECT_CLOSURE
                       && clo->proto_index < l_inv->function_count) {
                Lua55NativeFunctionDescriptorV2 *d =
                    &l_inv->functions[clo->proto_index];
                if (d->entry != 0) { klass = 1; varg = d->is_vararg; }
            }
        }
        v2_learn_callee(frame, slot, klass, varg);
    }

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
    V2_HOLE32(pc, V2_PC_HOLE);                                      \
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
    V2_HOLE32(pc, V2_PC_HOLE);                                      \
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
    V2_HOLE32(pc, V2_PC_HOLE);
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

STENCIL(lua55_v2l_forprep)(Lua55NativeFrameV2 *frame)
{
    V2_VALUE_DISP(base, V2_BASE_DISP_HOLE)
    Lua55ValueV2 *init = &base[0];
    Lua55ValueV2 *limit = &base[1];
    Lua55ValueV2 *step = &base[2];
    V2_LEARN_SLOT()
    {
        int proto_int = init->tag == LUA55_VALUE_INTEGER
            && limit->tag == LUA55_VALUE_INTEGER
            && step->tag == LUA55_VALUE_INTEGER;
        uint32_t proto = proto_int ? LUA55_VALUE_INTEGER : LUA55_VALUE_FLOAT;
        uint32_t sign = 0;
        if (step->tag == LUA55_VALUE_INTEGER) sign = step->payload.integer > 0 ? 0 : 1;
        else if (step->tag == LUA55_VALUE_FLOAT) sign = step->payload.floating > 0.0 ? 0 : 1;
        v2_learn_pair(frame, slot, proto, sign);
    }
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

STENCIL(lua55_v2l_forloop)(Lua55NativeFrameV2 *frame)
{
    V2_VALUE_DISP(base, V2_BASE_DISP_HOLE)
    Lua55ValueV2 *count_cell = &base[0];
    Lua55ValueV2 *step_cell = &base[1];
    Lua55ValueV2 *idx_cell = &base[2];
    V2_LEARN_SLOT()
    {
        uint32_t sign = 0;
        if (step_cell->tag == LUA55_VALUE_INTEGER) sign = step_cell->payload.integer > 0 ? 0 : 1;
        else if (step_cell->tag == LUA55_VALUE_FLOAT) sign = step_cell->payload.floating > 0.0 ? 0 : 1;
        v2_learn_pair(frame, slot, step_cell->tag, sign);
    }
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

/* Learning-only fused numeric-for cycle. It classifies the exact four-tag
   vector and step sign, executes the complete generic cycle once, and jumps
   directly to the bytecode after FORLOOP. It is never published as RX. */
STENCIL(lua55_v2l_super_for_addi)(Lua55NativeFrameV2 *frame)
{
    V2_HOLE32(A, V2_BASE_INDEX_HOLE);
    V2_HOLE32(accumulator_index, V2_TARGET_HOLE);
    uint64_t imm_bits = V2_INT_IMM_HOLE;
    __asm__ volatile ("" : "+r"(imm_bits));
    int64_t imm = (int64_t)imm_bits;
    V2_LEARN_SLOT()
    Lua55ValueV2 *init = &frame->values[A];
    Lua55ValueV2 *limit = &frame->values[A + 1];
    Lua55ValueV2 *step = &frame->values[A + 2];
    Lua55ValueV2 *accumulator = &frame->values[accumulator_index];
    if ((init->tag != LUA55_VALUE_INTEGER && init->tag != LUA55_VALUE_FLOAT) ||
        (limit->tag != LUA55_VALUE_INTEGER && limit->tag != LUA55_VALUE_FLOAT) ||
        (step->tag != LUA55_VALUE_INTEGER && step->tag != LUA55_VALUE_FLOAT) ||
        (accumulator->tag != LUA55_VALUE_INTEGER &&
         accumulator->tag != LUA55_VALUE_FLOAT)) {
        V2_REJECT(frame, LUA55_V2_REJECT_UNSUPPORTED_METAMETHOD);
        LUA55_CPS_HOST_EXIT(frame);
    }
    uint32_t sign = step->tag == LUA55_VALUE_INTEGER
        ? (step->payload.integer > 0 ? 0 : 1)
        : (step->payload.floating > 0.0 ? 0 : 1);
    v2_learn_super_for_addi(frame, slot, init->tag, limit->tag, step->tag,
        accumulator->tag, sign);
    if (init->tag == LUA55_VALUE_INTEGER && limit->tag == LUA55_VALUE_INTEGER
        && step->tag == LUA55_VALUE_INTEGER) {
        int64_t iv = init->payload.integer;
        int64_t lv = limit->payload.integer;
        int64_t sv = step->payload.integer;
        if (sv == 0) { V2_REJECT(frame, LUA55_V2_REJECT_STEP_ZERO);
                       LUA55_CPS_HOST_EXIT(frame); }
        if (!((sv > 0 && iv > lv) || (sv < 0 && iv < lv))) {
            uint64_t distance = sv > 0 ? (uint64_t)lv - (uint64_t)iv
                : (uint64_t)iv - (uint64_t)lv;
            uint64_t stride = sv > 0 ? (uint64_t)sv
                : UINT64_C(0) - (uint64_t)sv;
            int64_t count = (int64_t)(distance / stride);
            SET_TAG(init, LUA55_VALUE_INTEGER);
            SET_TAG(limit, LUA55_VALUE_INTEGER);
            SET_TAG(step, LUA55_VALUE_INTEGER);
            limit->payload.integer = sv;
            step->payload.integer = iv;
            if (accumulator->tag == LUA55_VALUE_INTEGER) {
                int64_t av = accumulator->payload.integer;
                for (;;) {
                    av = v2_int_add(av, imm);
                    if (count <= 0) break;
                    count--; iv = v2_int_add(iv, sv);
                    step->payload.integer = iv;
                }
                accumulator->payload.integer = av;
            } else {
                double av = accumulator->payload.floating;
                for (;;) {
                    av += (double)imm;
                    if (count <= 0) break;
                    count--; iv = v2_int_add(iv, sv);
                    step->payload.integer = iv;
                }
                accumulator->payload.floating = av;
            }
            init->payload.integer = count;
        }
    } else {
        double iv = init->tag == LUA55_VALUE_INTEGER
            ? (double)init->payload.integer : init->payload.floating;
        double lv = limit->tag == LUA55_VALUE_INTEGER
            ? (double)limit->payload.integer : limit->payload.floating;
        double sv = step->tag == LUA55_VALUE_INTEGER
            ? (double)step->payload.integer : step->payload.floating;
        if (sv == 0.0) { V2_REJECT(frame, LUA55_V2_REJECT_STEP_ZERO);
                         LUA55_CPS_HOST_EXIT(frame); }
        if (!((sv > 0.0 && lv < iv) || (sv < 0.0 && iv < lv))) {
            SET_TAG(init, LUA55_VALUE_FLOAT); init->payload.floating = lv;
            SET_TAG(limit, LUA55_VALUE_FLOAT); limit->payload.floating = sv;
            SET_TAG(step, LUA55_VALUE_FLOAT); step->payload.floating = iv;
            if (accumulator->tag == LUA55_VALUE_INTEGER) {
                int64_t av = accumulator->payload.integer;
                for (;;) {
                    av = v2_int_add(av, imm);
                    double next = iv + sv;
                    if (!((sv > 0.0 && next <= lv) ||
                          (sv < 0.0 && lv <= next))) break;
                    iv = next; step->payload.floating = iv;
                }
                accumulator->payload.integer = av;
            } else {
                double av = accumulator->payload.floating;
                for (;;) {
                    av += (double)imm;
                    double next = iv + sv;
                    if (!((sv > 0.0 && next <= lv) ||
                          (sv < 0.0 && lv <= next))) break;
                    iv = next; step->payload.floating = iv;
                }
                accumulator->payload.floating = av;
            }
        }
    }
    uintptr_t skip = (uintptr_t)V2_SKIP_HOLE;
    __asm__ volatile ("" : "+r"(skip));
    return ((Lua55NativeEntryV2)skip)(frame);
}

STENCIL_NOVEC(lua55_v2l_super_for_add)(Lua55NativeFrameV2 *frame)
{
    V2_HOLE32(A, V2_BASE_INDEX_HOLE);
    V2_HOLE32(accumulator_index, V2_TARGET_HOLE);
    V2_LEARN_SLOT()
    Lua55ValueV2 *init = &frame->values[A];
    Lua55ValueV2 *limit = &frame->values[A + 1];
    Lua55ValueV2 *step = &frame->values[A + 2];
    Lua55ValueV2 *accumulator = &frame->values[accumulator_index];
    if ((init->tag != LUA55_VALUE_INTEGER && init->tag != LUA55_VALUE_FLOAT) ||
        (limit->tag != LUA55_VALUE_INTEGER && limit->tag != LUA55_VALUE_FLOAT) ||
        (step->tag != LUA55_VALUE_INTEGER && step->tag != LUA55_VALUE_FLOAT) ||
        (accumulator->tag != LUA55_VALUE_INTEGER && accumulator->tag != LUA55_VALUE_FLOAT)) {
        V2_REJECT(frame, LUA55_V2_REJECT_UNSUPPORTED_METAMETHOD);
        LUA55_CPS_HOST_EXIT(frame);
    }
    uint32_t sign = step->tag == LUA55_VALUE_INTEGER
        ? (step->payload.integer > 0 ? 0 : 1)
        : (step->payload.floating > 0.0 ? 0 : 1);
    v2_learn_super_for_addi(frame, slot, init->tag, limit->tag, step->tag,
        accumulator->tag, sign);
    if (init->tag == LUA55_VALUE_INTEGER && limit->tag == LUA55_VALUE_INTEGER
        && step->tag == LUA55_VALUE_INTEGER) {
        int64_t iv = init->payload.integer, lv = limit->payload.integer;
        int64_t sv = step->payload.integer;
        if (sv == 0) { V2_REJECT(frame, LUA55_V2_REJECT_STEP_ZERO);
                       LUA55_CPS_HOST_EXIT(frame); }
        if (!((sv > 0 && iv > lv) || (sv < 0 && iv < lv))) {
            uint64_t distance = sv > 0 ? (uint64_t)lv - (uint64_t)iv
                : (uint64_t)iv - (uint64_t)lv;
            uint64_t stride = sv > 0 ? (uint64_t)sv : UINT64_C(0) - (uint64_t)sv;
            int64_t count = (int64_t)(distance / stride);
            if (accumulator->tag == LUA55_VALUE_INTEGER) {
                int64_t av = accumulator->payload.integer;
                for (;;) { av = v2_int_add(av, iv); if (count <= 0) break;
                    count--; iv = v2_int_add(iv, sv); }
                accumulator->payload.integer = av;
            } else {
                double av = accumulator->payload.floating;
                for (;;) { av += (double)iv; if (count <= 0) break;
                    count--; iv = v2_int_add(iv, sv); }
                accumulator->payload.floating = av;
            }
            SET_TAG(init, LUA55_VALUE_INTEGER); init->payload.integer = count;
            SET_TAG(limit, LUA55_VALUE_INTEGER); limit->payload.integer = sv;
            SET_TAG(step, LUA55_VALUE_INTEGER); step->payload.integer = iv;
        }
    } else {
        double iv = init->tag == LUA55_VALUE_INTEGER ? (double)init->payload.integer : init->payload.floating;
        double lv = limit->tag == LUA55_VALUE_INTEGER ? (double)limit->payload.integer : limit->payload.floating;
        double sv = step->tag == LUA55_VALUE_INTEGER ? (double)step->payload.integer : step->payload.floating;
        if (sv == 0.0) { V2_REJECT(frame, LUA55_V2_REJECT_STEP_ZERO);
                         LUA55_CPS_HOST_EXIT(frame); }
        if (!((sv > 0.0 && lv < iv) || (sv < 0.0 && iv < lv))) {
            double av = accumulator->tag == LUA55_VALUE_INTEGER
                ? (double)accumulator->payload.integer : accumulator->payload.floating;
            for (;;) { av += iv; double next = iv + sv;
                if (!((sv > 0.0 && next <= lv) || (sv < 0.0 && lv <= next))) break;
                iv = next; }
            SET_TAG(accumulator, LUA55_VALUE_FLOAT); accumulator->payload.floating = av;
            SET_TAG(init, LUA55_VALUE_FLOAT); init->payload.floating = lv;
            SET_TAG(limit, LUA55_VALUE_FLOAT); limit->payload.floating = sv;
            SET_TAG(step, LUA55_VALUE_FLOAT); step->payload.floating = iv;
        }
    }
    uintptr_t skip = (uintptr_t)V2_SKIP_HOLE;
    __asm__ volatile ("" : "+r"(skip));
    return ((Lua55NativeEntryV2)skip)(frame);
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

/* Batch 7: exact closure capture-vector leaves. The capture count and each
   instack/index pair are projection-proven from the bytecode, so the count
   is baked into the leaf (no runtime nupvals branch). Only the captures the
   leaf owns are holes. Capture counts above 4 reject visibly at staging. */
#define V2_CLOSURE_BODY(n)                                                  \
    V2_VALUE_DISP(target, V2_TARGET_DISP_HOLE)                              \
    V2_HOLE32(proto_index, V2_PROTO_INDEX_HOLE);                            \
    Lua55NativeClosureV2 *closure =                                         \
        v2_new_closure(frame->invocation->heap, proto_index, n);            \
    if (closure == 0) { V2_PUBLISH_OVERFLOW(frame,                          \
        LUA55_V2_OUTCOME_HEAP_OVERFLOW, 0, 0);                              \
        LUA55_CPS_HOST_EXIT(frame); }

STENCIL(lua55_v2r_closure_0)(Lua55NativeFrameV2 *frame)
{
    V2_CLOSURE_BODY(0)
    SET_TAG(target, LUA55_VALUE_CLOSURE);
    target->payload.reference = (uintptr_t)closure;
    LUA55_RESIDUAL_NEXT(frame);
}

STENCIL(lua55_v2r_closure_1)(Lua55NativeFrameV2 *frame)
{
    V2_CLOSURE_BODY(1)
    V2_HOLE32(instack0, V2_INSTACK_0); V2_HOLE32(idx0, V2_IDX_0);
    if (v2_set_cell(frame, closure, 0, instack0, idx0) == 0) {
        V2_PUBLISH_OVERFLOW(frame, LUA55_V2_OUTCOME_HEAP_OVERFLOW, 0, 0);
        LUA55_CPS_HOST_EXIT(frame);
    }
    SET_TAG(target, LUA55_VALUE_CLOSURE);
    target->payload.reference = (uintptr_t)closure;
    LUA55_RESIDUAL_NEXT(frame);
}

STENCIL(lua55_v2r_closure_2)(Lua55NativeFrameV2 *frame)
{
    V2_CLOSURE_BODY(2)
    V2_HOLE32(instack0, V2_INSTACK_0); V2_HOLE32(idx0, V2_IDX_0);
    V2_HOLE32(instack1, V2_INSTACK_1); V2_HOLE32(idx1, V2_IDX_1);
    if (v2_set_cell(frame, closure, 0, instack0, idx0) == 0 ||
        v2_set_cell(frame, closure, 1, instack1, idx1) == 0) {
        V2_PUBLISH_OVERFLOW(frame, LUA55_V2_OUTCOME_HEAP_OVERFLOW, 0, 0);
        LUA55_CPS_HOST_EXIT(frame);
    }
    SET_TAG(target, LUA55_VALUE_CLOSURE);
    target->payload.reference = (uintptr_t)closure;
    LUA55_RESIDUAL_NEXT(frame);
}

STENCIL(lua55_v2r_closure_3)(Lua55NativeFrameV2 *frame)
{
    V2_CLOSURE_BODY(3)
    V2_HOLE32(instack0, V2_INSTACK_0); V2_HOLE32(idx0, V2_IDX_0);
    V2_HOLE32(instack1, V2_INSTACK_1); V2_HOLE32(idx1, V2_IDX_1);
    V2_HOLE32(instack2, V2_INSTACK_2); V2_HOLE32(idx2, V2_IDX_2);
    if (v2_set_cell(frame, closure, 0, instack0, idx0) == 0 ||
        v2_set_cell(frame, closure, 1, instack1, idx1) == 0 ||
        v2_set_cell(frame, closure, 2, instack2, idx2) == 0) {
        V2_PUBLISH_OVERFLOW(frame, LUA55_V2_OUTCOME_HEAP_OVERFLOW, 0, 0);
        LUA55_CPS_HOST_EXIT(frame);
    }
    SET_TAG(target, LUA55_VALUE_CLOSURE);
    target->payload.reference = (uintptr_t)closure;
    LUA55_RESIDUAL_NEXT(frame);
}

STENCIL(lua55_v2r_closure_4)(Lua55NativeFrameV2 *frame)
{
    V2_CLOSURE_BODY(4)
    V2_HOLE32(instack0, V2_INSTACK_0); V2_HOLE32(idx0, V2_IDX_0);
    V2_HOLE32(instack1, V2_INSTACK_1); V2_HOLE32(idx1, V2_IDX_1);
    V2_HOLE32(instack2, V2_INSTACK_2); V2_HOLE32(idx2, V2_IDX_2);
    V2_HOLE32(instack3, V2_INSTACK_3); V2_HOLE32(idx3, V2_IDX_3);
    if (v2_set_cell(frame, closure, 0, instack0, idx0) == 0 ||
        v2_set_cell(frame, closure, 1, instack1, idx1) == 0 ||
        v2_set_cell(frame, closure, 2, instack2, idx2) == 0 ||
        v2_set_cell(frame, closure, 3, instack3, idx3) == 0) {
        V2_PUBLISH_OVERFLOW(frame, LUA55_V2_OUTCOME_HEAP_OVERFLOW, 0, 0);
        LUA55_CPS_HOST_EXIT(frame);
    }
    SET_TAG(target, LUA55_VALUE_CLOSURE);
    target->payload.reference = (uintptr_t)closure;
    LUA55_RESIDUAL_NEXT(frame);
}

/* ---- exact-shape guards and family-specific learning ------------------- */

#define V2_SPEC_MISMATCH(frame, expected, observed) do {                    \
    uint32_t v2_pc_hole = RESUME_HOLE;                                      \
    __asm__ volatile ("" : "+r"(v2_pc_hole));                               \
    uint32_t v2_expected = (uint32_t)(expected);                            \
    uint32_t v2_observed = (uint32_t)(observed);                            \
    (frame)->invocation->specialization_mismatch.pc = v2_pc_hole;           \
    (frame)->invocation->specialization_mismatch.expected_tag = v2_expected; \
    (frame)->invocation->specialization_mismatch.observed_tag = v2_observed; \
} while (0)

#define V2_SPECIALIZATION_MISMATCH_EXIT(frame) do {                          \
    uintptr_t v2_mismatch_exit = (uintptr_t)V2_MISMATCH_EXIT_HOLE;          \
    __asm__ volatile ("" : "+r"(v2_mismatch_exit));                          \
    return ((Lua55NativeEntryV2)v2_mismatch_exit)(frame);                   \
} while (0)

static inline void v2_learn_pair(Lua55NativeFrameV2 *frame,
    uint32_t occ_slot, uint32_t ta, uint32_t tb)
{
    Lua55NativeInvocationV2 *inv = frame->invocation;
    if (inv->learning == 0 || occ_slot >= inv->learning_slots) return;
    Lua55TableLearnSlotV2 *s =
        &((Lua55TableLearnSlotV2 *)inv->learning)[occ_slot];
    if (s->seen == 0) { s->key_tag = ta; s->value_tag = tb; s->seen = 1; return; }
    if (s->key_tag != ta || s->value_tag != tb) s->key_tag = UINT32_C(0xFFFFFFFF);
}

static inline void v2_learn_callee(Lua55NativeFrameV2 *frame,
    uint32_t occ_slot, uint32_t klass, uint32_t is_vararg)
{
    Lua55NativeInvocationV2 *inv = frame->invocation;
    if (inv->learning == 0 || occ_slot >= inv->learning_slots) return;
    Lua55TableLearnSlotV2 *s =
        &((Lua55TableLearnSlotV2 *)inv->learning)[occ_slot];
    if (s->seen == 0) { s->key_tag = klass; s->value_tag = is_vararg; s->seen = 1; return; }
    if (s->key_tag != klass || s->value_tag != is_vararg) s->key_tag = UINT32_C(0xFFFFFFFF);
}

static inline void v2_learn_concat(Lua55NativeFrameV2 *frame,
    uint32_t occ_slot, uint32_t count, uint32_t t0, uint32_t t1, uint32_t t2,
    uint32_t t3, uint32_t t4)
{
    Lua55NativeInvocationV2 *inv = frame->invocation;
    if (inv->learning == 0 || occ_slot >= inv->learning_slots) return;
    Lua55TableLearnSlotV2 *s =
        &((Lua55TableLearnSlotV2 *)inv->learning)[occ_slot];
    /* normalize short/long string tags: the concat shape is "string" */
    uint32_t n0 = v2_is_string_tag(t0) ? LUA55_VALUE_SHORT_STRING : t0;
    uint32_t n1 = v2_is_string_tag(t1) ? LUA55_VALUE_SHORT_STRING : t1;
    uint32_t n2 = v2_is_string_tag(t2) ? LUA55_VALUE_SHORT_STRING : t2;
    uint32_t n3 = v2_is_string_tag(t3) ? LUA55_VALUE_SHORT_STRING : t3;
    uint32_t n4 = v2_is_string_tag(t4) ? LUA55_VALUE_SHORT_STRING : t4;
    uint32_t e0 = count >= 1 ? n0 : 0;
    uint32_t e1 = count >= 2 ? n1 : 0;
    uint32_t e2 = count >= 3 ? n2 : 0;
    uint32_t e3 = count >= 4 ? n3 : 0;
    uint32_t e4 = count >= 5 ? n4 : 0;
    /* the slot carries up to five operand shapes: key/value tags, then t2
       in the low half of max_array_index, t3 in the high half, and t4 in
       max_field_count */
    uint64_t packed = (uint64_t)e2 | ((uint64_t)e3 << 32);
    if (s->seen == 0) {
        s->key_tag = e0; s->value_tag = e1;
        s->max_array_index = packed;
        s->max_field_count = e4;
        s->seen = 1; return;
    }
    if (s->key_tag != e0 || s->value_tag != e1 ||
        s->max_array_index != packed || s->max_field_count != e4)
        s->key_tag = UINT32_C(0xFFFFFFFF);
}

static inline void v2_learn_super_for_addi(Lua55NativeFrameV2 *frame,
    uint32_t occ_slot, uint32_t init_tag, uint32_t limit_tag,
    uint32_t step_tag, uint32_t accumulator_tag, uint32_t sign)
{
    Lua55NativeInvocationV2 *inv = frame->invocation;
    if (inv->learning == 0 || occ_slot >= inv->learning_slots) return;
    Lua55TableLearnSlotV2 *s =
        &((Lua55TableLearnSlotV2 *)inv->learning)[occ_slot];
    uint64_t packed = (uint64_t)step_tag | ((uint64_t)accumulator_tag << 32);
    if (s->seen == 0) {
        s->key_tag = init_tag; s->value_tag = limit_tag;
        s->max_array_index = packed; s->max_field_count = sign;
        s->seen = 1; return;
    }
    if (s->key_tag != init_tag || s->value_tag != limit_tag
        || s->max_array_index != packed || s->max_field_count != sign)
        s->key_tag = UINT32_C(0xFFFFFFFF);
}

static inline void v2_learn_key_tag(Lua55NativeFrameV2 *frame,
    uint32_t occ_slot, uint32_t tag)
{
    Lua55NativeInvocationV2 *inv = frame->invocation;
    if (inv->learning == 0 || occ_slot >= inv->learning_slots) return;
    Lua55TableLearnSlotV2 *slot =
        &((Lua55TableLearnSlotV2 *)inv->learning)[occ_slot];
    if (slot->key_tag == 0 || slot->key_tag == tag) slot->key_tag = tag;
    else slot->key_tag = UINT32_C(0xFFFFFFFF);
    slot->seen = 1;
}

static inline void v2_learn_write_site(Lua55NativeFrameV2 *frame,
    Lua55GuestTableV2 *table, int array_key, uint64_t key)
{
    Lua55NativeInvocationV2 *inv = frame->invocation;
    if (inv->learning == 0) return;
    uint32_t site = table->site_id;
    if (site == 0 || site >= inv->learning_slots) return;
    Lua55TableLearnSlotV2 *slot =
        &((Lua55TableLearnSlotV2 *)inv->learning)[site];
    if (array_key) {
        if (key > slot->max_array_index) slot->max_array_index = key;
    } else {
        if (key > slot->max_field_count) slot->max_field_count = (uint32_t)key;
    }
    slot->seen = 1;
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

enum {
    V2_FIELD_UNSEEN = 0, V2_FIELD_FOUND = 1,
    V2_FIELD_MISSING = 2, V2_FIELD_CONFLICT = 3
};

static inline void v2_learn_field_location(Lua55NativeFrameV2 *frame,
    uint32_t occ_slot, Lua55GuestTableV2 *table, Lua55ValueV2 *cell)
{
    Lua55NativeInvocationV2 *inv = frame->invocation;
    if (inv->learning == 0 || occ_slot >= inv->learning_slots) return;
    Lua55TableLearnSlotV2 *fact =
        &((Lua55TableLearnSlotV2 *)inv->learning)[occ_slot];
    uint32_t state = cell != 0 ? V2_FIELD_FOUND : V2_FIELD_MISSING;
    uint32_t field_slot = UINT32_MAX;
    if (cell != 0) {
        Lua55GuestFieldV2 *field = (Lua55GuestFieldV2 *)
            ((uint8_t *)cell - offsetof(Lua55GuestFieldV2, value));
        field_slot = (uint32_t)(field - table->field_values);
    }
    if (fact->field_state == V2_FIELD_UNSEEN) {
        fact->field_state = state;
        fact->field_slot = field_slot;
        fact->field_layout_capacity = table->field_capacity;
        fact->field_site_id = table->site_id;
        return;
    }
    if (fact->field_state != state || fact->field_slot != field_slot
        || fact->field_site_id != table->site_id) {
        fact->field_state = V2_FIELD_CONFLICT;
        return;
    }
    if (table->field_capacity > fact->field_layout_capacity)
        fact->field_layout_capacity = table->field_capacity;
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
    V2_HOLE32(target_reg, V2_TARGET_HOLE);                              \
    V2_HOLE32(receiver_reg, V2_RECEIVER_HOLE);

#define V2_TABLE_REJECT(frame, kind) do { V2_REJECT(frame, kind);           \
    LUA55_CPS_HOST_EXIT(frame); } while (0)

STENCIL(lua55_v2_geti)(Lua55NativeFrameV2 *frame)
{
    V2_VALUE_DISP(target, V2_TARGET_DISP_HOLE)
    V2_VALUE_DISP(receiver, V2_RECEIVER_DISP_HOLE)
    int64_t key = (int64_t)V2_INT_KEY_HOLE;
    __asm__ volatile ("" : "+r"(key));
    Lua55GuestTableV2 *table = v2_learn_table(frame, receiver);
    if (table == 0) V2_TABLE_REJECT(frame, LUA55_V2_REJECT_INVALID_OBJECT);
    Lua55ValueV2 *cell = v2_array_slot(table, key);
    if (cell == 0) { SET_TAG(target, LUA55_VALUE_NIL); target->payload.reference = 0; }
    else *target = *cell;
    LUA55_RESIDUAL_NEXT(frame);
}

STENCIL(lua55_v2_getfield)(Lua55NativeFrameV2 *frame)
{
    V2_VALUE_DISP(target, V2_TARGET_DISP_HOLE)
    V2_VALUE_DISP(receiver, V2_RECEIVER_DISP_HOLE)
    V2_LEARN_SLOT()
    uint64_t key_ref = (uint64_t)V2_KEY_REF_HOLE;
    __asm__ volatile ("" : "+r"(key_ref));
    Lua55GuestTableV2 *table = v2_learn_table(frame, receiver);
    if (table == 0) V2_TABLE_REJECT(frame, LUA55_V2_REJECT_INVALID_OBJECT);
    Lua55ValueV2 *cell = v2_find_field(table, (uintptr_t)key_ref, 0);
    v2_learn_field_location(frame, slot, table, cell);
    if (cell == 0) { SET_TAG(target, LUA55_VALUE_NIL); target->payload.reference = 0; }
    else *target = *cell;
    LUA55_RESIDUAL_NEXT(frame);
}

STENCIL(lua55_v2_gettabup)(Lua55NativeFrameV2 *frame)
{
    V2_VALUE_DISP(target, V2_TARGET_DISP_HOLE)
    V2_HOLE32(upvalue_reg, V2_UPVALUE_HOLE);
    V2_LEARN_SLOT()
    uint64_t key_ref = (uint64_t)V2_KEY_REF_HOLE;
    __asm__ volatile ("" : "+r"(key_ref));
    Lua55UpvalueCellV2 *cell0 = frame->upvalues[upvalue_reg];
    Lua55ValueV2 *value = cell0->state == LUA55_UPVALUE_OPEN
        ? cell0->open_slot : &cell0->closed_value;
    Lua55GuestTableV2 *table = v2_learn_table(frame, value);
    if (table == 0) V2_TABLE_REJECT(frame, LUA55_V2_REJECT_INVALID_OBJECT);
    Lua55ValueV2 *cell = v2_find_field(table, (uintptr_t)key_ref, 0);
    v2_learn_field_location(frame, slot, table, cell);
    if (cell == 0) { SET_TAG(target, LUA55_VALUE_NIL); target->payload.reference = 0; }
    else *target = *cell;
    LUA55_RESIDUAL_NEXT(frame);
}

STENCIL(lua55_v2l_gettable)(Lua55NativeFrameV2 *frame)
{
    V2_VALUE_DISP(target, V2_TARGET_DISP_HOLE)
    V2_VALUE_DISP(receiver, V2_RECEIVER_DISP_HOLE)
    V2_VALUE_DISP(key, V2_KEY_DISP_HOLE)
    V2_HOLE32(occ_slot, V2_OCC_SLOT_HOLE);
    Lua55GuestTableV2 *table = v2_learn_table(frame, receiver);
    if (table == 0) V2_TABLE_REJECT(frame, LUA55_V2_REJECT_INVALID_OBJECT);
    v2_learn_key_tag(frame, occ_slot, key->tag);
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
    V2_VALUE_DISP(receiver, V2_RECEIVER_DISP_HOLE)                          \
    V2_VALUE_DISP(value, V2_SOURCE_DISP_HOLE)                               \
    Lua55GuestTableV2 *table = v2_learn_table(frame, receiver);             \
    if (table == 0) V2_TABLE_REJECT(frame, LUA55_V2_REJECT_INVALID_OBJECT);

STENCIL(lua55_v2l_seti)(Lua55NativeFrameV2 *frame)
{
    V2_TABLE_WRITE()
    int64_t key = (int64_t)V2_INT_KEY_HOLE;
    __asm__ volatile ("" : "+r"(key));
    v2_learn_write_site(frame, table, 1, (uint64_t)key);
    Lua55ValueV2 *cell = v2_array_slot(table, key);
    if (cell == 0) {
        if (key >= 1 && v2_grow_array(frame, table, (uint64_t)key))
            cell = v2_array_slot(table, key);
        else V2_TABLE_REJECT(frame, LUA55_V2_REJECT_INVALID_OBJECT);
    }
    v2_table_set(table, cell, value);
    LUA55_RESIDUAL_NEXT(frame);
}

STENCIL(lua55_v2l_setfield)(Lua55NativeFrameV2 *frame)
{
    V2_TABLE_WRITE()
    V2_LEARN_SLOT()
    uint64_t key_ref = (uint64_t)V2_KEY_REF_HOLE;
    __asm__ volatile ("" : "+r"(key_ref));
    Lua55ValueV2 *cell = v2_find_field(table, (uintptr_t)key_ref, 1);
    if (cell == 0) V2_TABLE_REJECT(frame, LUA55_V2_REJECT_INVALID_OBJECT);
    v2_learn_field_location(frame, slot, table, cell);
    v2_learn_write_site(frame, table, 0, table->field_capacity);
    v2_table_set(table, cell, value);
    LUA55_RESIDUAL_NEXT(frame);
}

STENCIL(lua55_v2_settabup)(Lua55NativeFrameV2 *frame)
{
    V2_HOLE32(upvalue_reg, V2_UPVALUE_HOLE);
    V2_HOLE32(source_reg, V2_SOURCE_HOLE);
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

STENCIL(lua55_v2l_settable)(Lua55NativeFrameV2 *frame)
{
    V2_TABLE_WRITE()
    V2_VALUE_DISP(key, V2_KEY_DISP_HOLE)
    V2_HOLE32(occ_slot, V2_OCC_SLOT_HOLE);
    v2_learn_key_tag(frame, occ_slot, key->tag);
    Lua55ValueV2 *cell;
    if (key->tag == LUA55_VALUE_INTEGER) {
        cell = v2_array_slot(table, key->payload.integer);
        if (cell == 0 && key->payload.integer >= 1
            && v2_grow_array(frame, table, (uint64_t)key->payload.integer))
            cell = v2_array_slot(table, key->payload.integer);
        v2_learn_write_site(frame, table, 1, (uint64_t)key->payload.integer);
    } else if (v2_is_string_tag(key->tag)) {
        cell = v2_find_field(table, (uintptr_t)key->payload.reference, 1);
        v2_learn_write_site(frame, table, 0, table->field_capacity);
    } else V2_TABLE_REJECT(frame, LUA55_V2_REJECT_UNSUPPORTED_METAMETHOD);
    if (cell == 0) V2_TABLE_REJECT(frame, LUA55_V2_REJECT_INVALID_OBJECT);
    v2_table_set(table, cell, value);
    LUA55_RESIDUAL_NEXT(frame);
}

STENCIL(lua55_v2l_newtable)(Lua55NativeFrameV2 *frame)
{
    V2_VALUE_DISP(target, V2_TARGET_DISP_HOLE)
    V2_HOLE32(array_cap, V2_ARRAY_CAP_HOLE);
    V2_HOLE32(field_cap, V2_FIELD_CAP_HOLE);
    V2_HOLE32(site, V2_SITE_ID_HOLE);
    Lua55GuestTableV2 *table = v2_new_table(frame, array_cap, field_cap);
    if (table == 0) { V2_PUBLISH_OVERFLOW(frame, LUA55_V2_OUTCOME_HEAP_OVERFLOW, 0, 0);
                      LUA55_CPS_HOST_EXIT(frame); }
    table->site_id = site;
    SET_TAG(target, LUA55_VALUE_TABLE);
    target->payload.reference = (uintptr_t)table;
    LUA55_RESIDUAL_NEXT(frame);
}

STENCIL(lua55_v2r_newtable)(Lua55NativeFrameV2 *frame)
{
    V2_VALUE_DISP(target, V2_TARGET_DISP_HOLE)
    V2_HOLE32(array_cap, V2_ARRAY_CAP_HOLE);
    V2_HOLE32(field_cap, V2_FIELD_CAP_HOLE);
    Lua55GuestTableV2 *table = v2_new_table(frame, array_cap, field_cap);
    if (table == 0) { V2_PUBLISH_OVERFLOW(frame, LUA55_V2_OUTCOME_HEAP_OVERFLOW, 0, 0);
                      LUA55_CPS_HOST_EXIT(frame); }
    SET_TAG(target, LUA55_VALUE_TABLE);
    target->payload.reference = (uintptr_t)table;
    LUA55_RESIDUAL_NEXT(frame);
}

STENCIL(lua55_v2_self)(Lua55NativeFrameV2 *frame)
{
    V2_VALUE_DISP(target, V2_TARGET_DISP_HOLE)
    V2_VALUE_DISP(object, V2_OBJECT_DISP_HOLE)
    V2_VALUE_DISP(receiver, V2_RECEIVER_DISP_HOLE)
    V2_LEARN_SLOT()
    uint64_t key_ref = (uint64_t)V2_KEY_REF_HOLE;
    __asm__ volatile ("" : "+r"(key_ref));
    Lua55GuestTableV2 *table = v2_learn_table(frame, receiver);
    if (table == 0) V2_TABLE_REJECT(frame, LUA55_V2_REJECT_INVALID_OBJECT);
    *object = *receiver;
    Lua55ValueV2 *cell = v2_find_field(table, (uintptr_t)key_ref, 0);
    v2_learn_field_location(frame, slot, table, cell);
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
    V2_HOLE32(base_reg, V2_SETLIST_BASE_HOLE);
    V2_HOLE32(count, V2_SETLIST_COUNT_HOLE);
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
STENCIL(lua55_v2l_seti_const)(Lua55NativeFrameV2 *frame)
{
    V2_VALUE_DISP(receiver, V2_RECEIVER_DISP_HOLE)
    int64_t key = (int64_t)V2_INT_KEY_HOLE;
    __asm__ volatile ("" : "+r"(key));
    Lua55GuestTableV2 *table = v2_learn_table(frame, receiver);
    if (table == 0) V2_TABLE_REJECT(frame, LUA55_V2_REJECT_INVALID_OBJECT);
    v2_learn_write_site(frame, table, 1, (uint64_t)key);
    V2_VALUE_CONST_CELL()
    Lua55ValueV2 *cell = v2_array_slot(table, key);
    if (cell == 0) {
        if (key >= 1 && v2_grow_array(frame, table, (uint64_t)key))
            cell = v2_array_slot(table, key);
        else V2_TABLE_REJECT(frame, LUA55_V2_REJECT_INVALID_OBJECT);
    }
    v2_table_set(table, cell, value);
    LUA55_RESIDUAL_NEXT(frame);
}

STENCIL(lua55_v2l_setfield_const)(Lua55NativeFrameV2 *frame)
{
    V2_VALUE_DISP(receiver, V2_RECEIVER_DISP_HOLE)
    V2_LEARN_SLOT()
    V2_VALUE_CONST_CELL()
    uint64_t key_ref = (uint64_t)V2_KEY_REF_HOLE;
    __asm__ volatile ("" : "+r"(key_ref));
    Lua55GuestTableV2 *table = v2_learn_table(frame, receiver);
    if (table == 0) V2_TABLE_REJECT(frame, LUA55_V2_REJECT_INVALID_OBJECT);
    Lua55ValueV2 *cell = v2_find_field(table, (uintptr_t)key_ref, 1);
    if (cell == 0) V2_TABLE_REJECT(frame, LUA55_V2_REJECT_INVALID_OBJECT);
    v2_learn_field_location(frame, slot, table, cell);
    v2_learn_write_site(frame, table, 0, table->field_capacity);
    v2_table_set(table, cell, value);
    LUA55_RESIDUAL_NEXT(frame);
}

STENCIL(lua55_v2l_settable_const)(Lua55NativeFrameV2 *frame)
{
    V2_VALUE_DISP(receiver, V2_RECEIVER_DISP_HOLE)
    V2_VALUE_DISP(key, V2_KEY_DISP_HOLE)
    V2_HOLE32(occ_slot, V2_OCC_SLOT_HOLE);
    V2_VALUE_CONST_CELL()
    Lua55GuestTableV2 *table = v2_learn_table(frame, receiver);
    if (table == 0) V2_TABLE_REJECT(frame, LUA55_V2_REJECT_INVALID_OBJECT);
    v2_learn_key_tag(frame, occ_slot, key->tag);
    Lua55ValueV2 *cell;
    if (key->tag == LUA55_VALUE_INTEGER) {
        cell = v2_array_slot(table, key->payload.integer);
        if (cell == 0 && key->payload.integer >= 1
            && v2_grow_array(frame, table, (uint64_t)key->payload.integer))
            cell = v2_array_slot(table, key->payload.integer);
        v2_learn_write_site(frame, table, 1, (uint64_t)key->payload.integer);
    } else if (v2_is_string_tag(key->tag)) {
        cell = v2_find_field(table, (uintptr_t)key->payload.reference, 1);
        v2_learn_write_site(frame, table, 0, table->field_capacity);
    } else V2_TABLE_REJECT(frame, LUA55_V2_REJECT_UNSUPPORTED_METAMETHOD);
    if (cell == 0) V2_TABLE_REJECT(frame, LUA55_V2_REJECT_INVALID_OBJECT);
    v2_table_set(table, cell, value);
    LUA55_RESIDUAL_NEXT(frame);
}

/* ======================================================================= */
/* 80-81: vararg family (83 VARARGPREP is a host-arranged boundary)        */
/* ======================================================================= */

STENCIL(lua55_v2_vararg)(Lua55NativeFrameV2 *frame)
{
    V2_HOLE32(target_reg, V2_TARGET_HOLE);
    V2_VALUE_DISP(target, V2_TARGET_DISP_HOLE)
    int32_t wanted = (int32_t)V2_WANTED_HOLE;
    __asm__ volatile ("" : "+r"(wanted));
    uint32_t nargs = frame->vararg_count;
    uint32_t touse = (wanted == -1) ? nargs : (nargs > (uint32_t)wanted
        ? (uint32_t)wanted : nargs);
    Lua55ValueV2 *slice = frame->values + frame->value_capacity;
    uint32_t i;
    for (i = 0; i < touse; i++)
        target[i] = slice[i];
    if (wanted != -1) {
        for (i = touse; i < (uint32_t)wanted; i++)
            SET_TAG(&target[i], LUA55_VALUE_NIL);
        frame->top = target_reg + (uint32_t)wanted;
    } else {
        frame->top = target_reg + touse;
    }
    LUA55_RESIDUAL_NEXT(frame);
}

STENCIL(lua55_v2l_getvarg)(Lua55NativeFrameV2 *frame)
{
    V2_VALUE_DISP(target, V2_TARGET_DISP_HOLE)
    V2_VALUE_DISP(key, V2_KEY_DISP_HOLE)
    V2_LEARN_SLOT()
    {
        uint32_t kt = key->tag;
        if (v2_is_string_tag(kt)) {
            Lua55GuestStringV2 *ks = (Lua55GuestStringV2 *)key->payload.reference;
            if (ks == 0 || ks->length != 1 || ks->bytes[0] != 'n') kt = 0;
        }
        v2_learn_key_tag(frame, slot, kt);
    }
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
    V2_VALUE_DISP(base, V2_BASE_DISP_HOLE)
    uintptr_t call_link = (uintptr_t)V2_TAKEN_HOLE;
    __asm__ volatile ("" : "+r"(call_link));
    Lua55ValueV2 *slot2 = &base[2];
    Lua55ValueV2 *slot3 = &base[3];
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

STENCIL(lua55_v2l_tforcall)(Lua55NativeFrameV2 *frame)
{
    uint32_t A = V2_A_HOLE;
    __asm__ volatile ("" : "+r"(A));
    uint32_t C = V2_C_HOLE;
    __asm__ volatile ("" : "+r"(C));
    V2_HOLE32(pc, V2_PC_HOLE);
    uint64_t cont = V2_CONTINUATION_HOLE;
    __asm__ volatile ("" : "+r"(cont));
    Lua55ValueV2 *callee_cell = &frame->values[A];

    V2_LEARN_SLOT()
    {
        Lua55NativeInvocationV2 *l_inv = frame->invocation;
        uint32_t klass = 3, varg = 0;
        if (callee_cell->tag == LUA55_VALUE_CLOSURE) {
            Lua55NativeClosureV2 *clo =
                (Lua55NativeClosureV2 *)callee_cell->payload.reference;
            if (clo != 0 && clo->header.kind == LUA55_OBJECT_BUILTIN) {
                klass = 2;
            } else if (clo != 0 && clo->header.kind == LUA55_OBJECT_CLOSURE
                       && clo->proto_index < l_inv->function_count) {
                Lua55NativeFunctionDescriptorV2 *d =
                    &l_inv->functions[clo->proto_index];
                if (d->entry != 0) { klass = 1; varg = d->is_vararg; }
            }
        }
        v2_learn_callee(frame, slot, klass, varg);
    }

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
    V2_VALUE_DISP(base, V2_BASE_DISP_HOLE)
    uintptr_t body = (uintptr_t)V2_BODY_HOLE;
    __asm__ volatile ("" : "+r"(body));
    Lua55ValueV2 *control = &base[3];
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
    V2_VALUE_DISP(base, V2_BASE_DISP_HOLE)
    Lua55UpvalueCellV2 **cellp = &frame->open_upvalues;
    while (*cellp != 0) {
        Lua55UpvalueCellV2 *cell = *cellp;
        if (cell->open_slot >= base) {
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
    V2_VALUE_DISP(value, V2_BASE_DISP_HOLE)
    if (value->tag != LUA55_VALUE_NIL && value->tag != LUA55_VALUE_FALSE) {
        V2_REJECT(frame, LUA55_V2_REJECT_UNSUPPORTED_METAMETHOD);
        LUA55_CPS_HOST_EXIT(frame);
    }
    LUA55_RESIDUAL_NEXT(frame);
}

/* ======================================================================= */
/* 53: CONCAT (exact Lua 5.5 formatting via the patched fmt helpers)       */
/* ======================================================================= */

#define V2_DTOA_ADDR UINT64_C(0x4f5e6d7c8b9aa9b8)
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

STENCIL(lua55_v2l_concat)(Lua55NativeFrameV2 *frame)
{
    V2_HOLE32(target_reg, V2_TARGET_HOLE);
    V2_HOLE32(base_reg, V2_SETLIST_BASE_HOLE);
    V2_HOLE32(count, V2_SETLIST_COUNT_HOLE);
    V2_LEARN_SLOT()
    {
        uint32_t t0 = count >= 1 ? (&frame->values[base_reg + 0])->tag : 0;
        uint32_t t1 = count >= 2 ? (&frame->values[base_reg + 1])->tag : 0;
        uint32_t t2 = count >= 3 ? (&frame->values[base_reg + 2])->tag : 0;
        uint32_t t3 = count >= 4 ? (&frame->values[base_reg + 3])->tag : 0;
        uint32_t t4 = count >= 5 ? (&frame->values[base_reg + 4])->tag : 0;
        v2_learn_concat(frame, slot, count, t0, t1, t2, t3, t4);
    }
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
    V2_VALUE_DISP(value, V2_BASE_DISP_HOLE)
    V2_HOLE32(pc, V2_PC_HOLE);
    if (value->tag != LUA55_VALUE_NIL) {
        frame->invocation->outcome.discriminant = LUA55_V2_OUTCOME_GUEST_ERROR;
        frame->invocation->outcome.u.error.error_kind = 1;
        frame->invocation->outcome.u.error.pc = pc;
        frame->invocation->outcome.u.error.value = *value;
        LUA55_CPS_HOST_EXIT(frame);
    }
    LUA55_RESIDUAL_NEXT(frame);
}

STENCIL(lua55_v2l_settabup)(Lua55NativeFrameV2 *frame)
{
    V2_HOLE32(upvalue_reg, V2_UPVALUE_HOLE);
    V2_VALUE_DISP(src, V2_SOURCE_DISP_HOLE)
    V2_LEARN_SLOT()
    uint64_t key_ref = (uint64_t)V2_KEY_REF_HOLE;
    __asm__ volatile ("" : "+r"(key_ref));
    Lua55UpvalueCellV2 *cell0 = frame->upvalues[upvalue_reg];
    Lua55ValueV2 *value = cell0->state == LUA55_UPVALUE_OPEN
        ? cell0->open_slot : &cell0->closed_value;
    Lua55GuestTableV2 *table = v2_learn_table(frame, value);
    if (table == 0) V2_TABLE_REJECT(frame, LUA55_V2_REJECT_INVALID_OBJECT);
    Lua55ValueV2 *cell = v2_find_field(table, (uintptr_t)key_ref, 1);
    if (cell == 0) V2_TABLE_REJECT(frame, LUA55_V2_REJECT_INVALID_OBJECT);
    v2_learn_field_location(frame, slot, table, cell);
    v2_learn_write_site(frame, table, 0, table->field_capacity);
    v2_table_set(table, cell, src);
    LUA55_RESIDUAL_NEXT(frame);
}

STENCIL(lua55_v2l_settabup_const)(Lua55NativeFrameV2 *frame)
{
    V2_HOLE32(upvalue_reg, V2_UPVALUE_HOLE);
    V2_LEARN_SLOT()
    V2_VALUE_CONST_CELL()
    uint64_t key_ref = (uint64_t)V2_KEY_REF_HOLE;
    __asm__ volatile ("" : "+r"(key_ref));
    Lua55UpvalueCellV2 *cell0 = frame->upvalues[upvalue_reg];
    Lua55ValueV2 *upvalue = cell0->state == LUA55_UPVALUE_OPEN
        ? cell0->open_slot : &cell0->closed_value;
    Lua55GuestTableV2 *table = v2_learn_table(frame, upvalue);
    if (table == 0) V2_TABLE_REJECT(frame, LUA55_V2_REJECT_INVALID_OBJECT);
    Lua55ValueV2 *cell = v2_find_field(table, (uintptr_t)key_ref, 1);
    if (cell == 0) V2_TABLE_REJECT(frame, LUA55_V2_REJECT_INVALID_OBJECT);
    v2_learn_field_location(frame, slot, table, cell);
    v2_learn_write_site(frame, table, 0, table->field_capacity);
    v2_table_set(table, cell, value);
    LUA55_RESIDUAL_NEXT(frame);
}
STENCIL(lua55_v2l_setlist)(Lua55NativeFrameV2 *frame)
{
    V2_HOLE32(base_reg, V2_SETLIST_BASE_HOLE);
    V2_HOLE32(count, V2_SETLIST_COUNT_HOLE);
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
    v2_learn_write_site(frame, table, 1, (uint64_t)(key_base + count));
    LUA55_RESIDUAL_NEXT(frame);
}

/* Corpus-derived read/ADDI/write superinstructions. Learners classify only
   key/value domains and execute one fused semantic operation. Published
   residuals below guard one exact domain and never choose a sibling path. */
STENCIL(lua55_v2l_super_field_addi)(Lua55NativeFrameV2 *frame)
{
    V2_TABLE_TARGET()
    V2_LEARN_SLOT()
    uint64_t key_ref = (uint64_t)V2_KEY_REF_HOLE;
    uint64_t imm_bits = V2_INT_IMM_HOLE;
    __asm__ volatile ("" : "+r"(key_ref));
    __asm__ volatile ("" : "+r"(imm_bits));
    Lua55ValueV2 *receiver = &frame->values[receiver_reg];
    Lua55GuestTableV2 *table = v2_learn_table(frame, receiver);
    if (table == 0) V2_TABLE_REJECT(frame, LUA55_V2_REJECT_INVALID_OBJECT);
    Lua55ValueV2 *cell = v2_find_field(table, (uintptr_t)key_ref, 0);
    if (cell == 0 || (cell->tag != LUA55_VALUE_INTEGER
        && cell->tag != LUA55_VALUE_FLOAT)) {
        V2_REJECT(frame, LUA55_V2_REJECT_UNSUPPORTED_METAMETHOD);
        LUA55_CPS_HOST_EXIT(frame);
    }
    v2_learn_key_tag(frame, slot, cell->tag);
    if (cell->tag == LUA55_VALUE_INTEGER)
        cell->payload.integer = v2_int_add(cell->payload.integer, (int64_t)imm_bits);
    else cell->payload.floating += (double)(int64_t)imm_bits;
    frame->values[target_reg] = *cell;
    LUA55_RESIDUAL_NEXT(frame);
}

#define V2_SUPER_GUARD(cell, expected) do {                                  \
    if ((cell)->tag != (expected)) {                                         \
        V2_SPEC_MISMATCH(frame, (expected), (cell)->tag);                    \
        V2_SPECIALIZATION_MISMATCH_EXIT(frame);                                          \
    }                                                                        \
} while (0)
#define V2_SUPER_FIELD_ADDI(name, value_tag, is_int)                          \
STENCIL(name)(Lua55NativeFrameV2 *frame)                                    \
{                                                                           \
    V2_TABLE_TARGET()                                                       \
    uint64_t key_ref = (uint64_t)V2_KEY_REF_HOLE;                           \
    uint64_t imm_bits = V2_INT_IMM_HOLE;                                    \
    __asm__ volatile ("" : "+r"(key_ref));                                \
    __asm__ volatile ("" : "+r"(imm_bits));                               \
    Lua55ValueV2 *receiver = &frame->values[receiver_reg];                   \
    V2_SUPER_GUARD(receiver, LUA55_VALUE_TABLE);                             \
    Lua55GuestTableV2 *table = (Lua55GuestTableV2 *)receiver->payload.reference; \
    if (table == 0 || table->header.kind != LUA55_OBJECT_TABLE              \
        || table->heap != frame->invocation->heap                           \
        || table->metatable_reference != 0) {                               \
        V2_SPEC_MISMATCH(frame, LUA55_OBJECT_TABLE,                         \
            table != 0 ? table->header.kind : 0);                           \
        V2_SPECIALIZATION_MISMATCH_EXIT(frame); }                                        \
    Lua55ValueV2 *cell = v2_find_field(table, (uintptr_t)key_ref, 0);        \
    if (cell == 0) { V2_SPEC_MISMATCH(frame, value_tag, LUA55_VALUE_NIL);    \
                     V2_SPECIALIZATION_MISMATCH_EXIT(frame); }                           \
    V2_SUPER_GUARD(cell, value_tag);                                         \
    if (is_int) cell->payload.integer = v2_int_add(                          \
        cell->payload.integer, (int64_t)imm_bits);                           \
    else cell->payload.floating += (double)(int64_t)imm_bits;                \
    frame->values[target_reg] = *cell;                                      \
    LUA55_RESIDUAL_NEXT(frame);                                             \
}

V2_SUPER_FIELD_ADDI(lua55_v2r_super_field_addi_int, LUA55_VALUE_INTEGER, 1)
V2_SUPER_FIELD_ADDI(lua55_v2r_super_field_addi_flt, LUA55_VALUE_FLOAT, 0)

STENCIL(lua55_v2l_super_table_addi)(Lua55NativeFrameV2 *frame)
{
    V2_TABLE_TARGET()
    V2_HOLE32(key_reg, V2_KEY_REG_HOLE);
    V2_LEARN_SLOT()
    uint64_t imm_bits = V2_INT_IMM_HOLE;
    __asm__ volatile ("" : "+r"(imm_bits));
    Lua55ValueV2 *receiver = &frame->values[receiver_reg];
    Lua55ValueV2 *key = &frame->values[key_reg];
    Lua55GuestTableV2 *table = v2_learn_table(frame, receiver);
    if (table == 0) V2_TABLE_REJECT(frame, LUA55_V2_REJECT_INVALID_OBJECT);
    Lua55ValueV2 *cell = 0; uint32_t key_shape = key->tag;
    if (key->tag == LUA55_VALUE_INTEGER)
        cell = v2_array_slot(table, key->payload.integer);
    else if (v2_is_string_tag(key->tag)) {
        key_shape = LUA55_VALUE_SHORT_STRING;
        cell = v2_find_field(table, key->payload.reference, 0);
    } else {
        V2_REJECT(frame, LUA55_V2_REJECT_UNSUPPORTED_METAMETHOD);
        LUA55_CPS_HOST_EXIT(frame);
    }
    if (cell == 0 || (cell->tag != LUA55_VALUE_INTEGER
        && cell->tag != LUA55_VALUE_FLOAT)) {
        V2_REJECT(frame, LUA55_V2_REJECT_UNSUPPORTED_METAMETHOD);
        LUA55_CPS_HOST_EXIT(frame);
    }
    v2_learn_pair(frame, slot, key_shape, cell->tag);
    if (cell->tag == LUA55_VALUE_INTEGER)
        cell->payload.integer = v2_int_add(cell->payload.integer, (int64_t)imm_bits);
    else cell->payload.floating += (double)(int64_t)imm_bits;
    frame->values[target_reg] = *cell;
    LUA55_RESIDUAL_NEXT(frame);
}

#define V2_SUPER_TABLE_ADDI_INTKEY(name, value_tag, is_int)                   \
STENCIL(name)(Lua55NativeFrameV2 *frame)                                    \
{                                                                           \
    V2_TABLE_TARGET() V2_HOLE32(key_reg, V2_KEY_REG_HOLE);                   \
    uint64_t imm_bits = V2_INT_IMM_HOLE;                                    \
    __asm__ volatile ("" : "+r"(imm_bits));                               \
    Lua55ValueV2 *receiver = &frame->values[receiver_reg];                   \
    Lua55ValueV2 *key = &frame->values[key_reg];                             \
    V2_SUPER_GUARD(receiver, LUA55_VALUE_TABLE);                             \
    V2_SUPER_GUARD(key, LUA55_VALUE_INTEGER);                                \
    Lua55GuestTableV2 *table = (Lua55GuestTableV2 *)receiver->payload.reference; \
    if (table == 0 || table->header.kind != LUA55_OBJECT_TABLE              \
        || table->heap != frame->invocation->heap                           \
        || table->metatable_reference != 0) {                               \
        V2_SPEC_MISMATCH(frame, LUA55_OBJECT_TABLE,                         \
            table != 0 ? table->header.kind : 0);                           \
        V2_SPECIALIZATION_MISMATCH_EXIT(frame); }                                        \
    Lua55ValueV2 *cell = v2_array_slot(table, key->payload.integer);         \
    if (cell == 0) { V2_SPEC_MISMATCH(frame, value_tag, LUA55_VALUE_NIL);    \
                     V2_SPECIALIZATION_MISMATCH_EXIT(frame); }                           \
    V2_SUPER_GUARD(cell, value_tag);                                         \
    if (is_int) cell->payload.integer = v2_int_add(                          \
        cell->payload.integer, (int64_t)imm_bits);                           \
    else cell->payload.floating += (double)(int64_t)imm_bits;                \
    frame->values[target_reg] = *cell;                                      \
    LUA55_RESIDUAL_NEXT(frame);                                             \
}

#define V2_SUPER_TABLE_ADDI_STRKEY(name, value_tag, is_int)                   \
STENCIL(name)(Lua55NativeFrameV2 *frame)                                    \
{                                                                           \
    V2_TABLE_TARGET() V2_HOLE32(key_reg, V2_KEY_REG_HOLE);                   \
    uint64_t imm_bits = V2_INT_IMM_HOLE;                                    \
    __asm__ volatile ("" : "+r"(imm_bits));                               \
    Lua55ValueV2 *receiver = &frame->values[receiver_reg];                   \
    Lua55ValueV2 *key = &frame->values[key_reg];                             \
    V2_SUPER_GUARD(receiver, LUA55_VALUE_TABLE);                             \
    if (!v2_is_string_tag(key->tag)) {                                      \
        V2_SPEC_MISMATCH(frame, LUA55_VALUE_SHORT_STRING, key->tag);         \
        V2_SPECIALIZATION_MISMATCH_EXIT(frame); }                                        \
    Lua55GuestTableV2 *table = (Lua55GuestTableV2 *)receiver->payload.reference; \
    if (table == 0 || table->header.kind != LUA55_OBJECT_TABLE              \
        || table->heap != frame->invocation->heap                           \
        || table->metatable_reference != 0) {                               \
        V2_SPEC_MISMATCH(frame, LUA55_OBJECT_TABLE,                         \
            table != 0 ? table->header.kind : 0);                           \
        V2_SPECIALIZATION_MISMATCH_EXIT(frame); }                                        \
    Lua55ValueV2 *cell = v2_find_field(table, key->payload.reference, 0);    \
    if (cell == 0) { V2_SPEC_MISMATCH(frame, value_tag, LUA55_VALUE_NIL);    \
                     V2_SPECIALIZATION_MISMATCH_EXIT(frame); }                           \
    V2_SUPER_GUARD(cell, value_tag);                                         \
    if (is_int) cell->payload.integer = v2_int_add(                          \
        cell->payload.integer, (int64_t)imm_bits);                           \
    else cell->payload.floating += (double)(int64_t)imm_bits;                \
    frame->values[target_reg] = *cell;                                      \
    LUA55_RESIDUAL_NEXT(frame);                                             \
}

V2_SUPER_TABLE_ADDI_INTKEY(lua55_v2r_super_table_addi_int_int, LUA55_VALUE_INTEGER, 1)
V2_SUPER_TABLE_ADDI_INTKEY(lua55_v2r_super_table_addi_int_flt, LUA55_VALUE_FLOAT, 0)
V2_SUPER_TABLE_ADDI_STRKEY(lua55_v2r_super_table_addi_str_int, LUA55_VALUE_INTEGER, 1)
V2_SUPER_TABLE_ADDI_STRKEY(lua55_v2r_super_table_addi_str_flt, LUA55_VALUE_FLOAT, 0)
/* ======================================================================= */
/* Exact residual leaves (family-specific selection products)               */
/* ------------------------------------------------------------------------ */
/* Each residual implements exactly ONE semantic shape. Guards validate the */
/* selected shape; a mismatch publishes a typed specialization rejection.   */
/* Hot in-bounds leaves tail-transfer to separate cold grow/create leaves.  */
/* ======================================================================= */

#define V2_STORE_NIL(cell)      do { SET_TAG((cell), LUA55_VALUE_NIL); (cell)->payload.reference = 0; } while (0)
#define V2_STORE_FALSE(cell)    do { SET_TAG((cell), LUA55_VALUE_FALSE); (cell)->payload.reference = 0; } while (0)
#define V2_STORE_TRUE(cell)     do { SET_TAG((cell), LUA55_VALUE_TRUE); (cell)->payload.reference = 0; } while (0)
#define V2_STORE_INT(cell)      do { int64_t cv = (int64_t)V2_CONST_INT;  \
    __asm__ volatile ("" : "+r"(cv));                                     \
    SET_TAG((cell), LUA55_VALUE_INTEGER); (cell)->payload.integer = cv; } while (0)
#define V2_STORE_FLT(cell)      do { uint64_t cv = V2_CONST_FLT;          \
    __asm__ volatile ("" : "+r"(cv));                                     \
    SET_TAG((cell), LUA55_VALUE_FLOAT);                                   \
    __builtin_memcpy(&(cell)->payload.floating, &cv, 8); } while (0)
#define V2_STORE_STR(cell)      do { uint32_t ck = V2_CONST_TAG;          \
    uint64_t cr = (uint64_t)V2_CONST_REF;                                 \
    __asm__ volatile ("" : "+r"(ck)); __asm__ volatile ("" : "+r"(cr));   \
    SET_TAG((cell), ck); (cell)->payload.reference = (uintptr_t)cr; } while (0)
#define V2_STORE_REG(cell, value, table) do {                             \
    *(cell) = *(value);                                                   \
    if ((value)->tag >= LUA55_VALUE_SHORT_STRING) {                       \
        (table)->barrier_count++;                                         \
        if ((table)->heap != 0) (table)->heap->barrier_epoch++;           \
    } } while (0)

/* ---- loadk / loadkx: exact constant leaves ---------------------------- */
#define V2_LOADK_LEAF(name, store)                                          \
STENCIL(name)(Lua55NativeFrameV2 *frame)                                    \
{                                                                           \
    V2_VALUE_DISP(target, V2_TARGET_DISP_HOLE)                               \
    store(target);                                                          \
    LUA55_RESIDUAL_NEXT(frame);                                             \
}
V2_LOADK_LEAF(lua55_v2r_loadk_nil, V2_STORE_NIL)
V2_LOADK_LEAF(lua55_v2r_loadk_false, V2_STORE_FALSE)
V2_LOADK_LEAF(lua55_v2r_loadk_true, V2_STORE_TRUE)
V2_LOADK_LEAF(lua55_v2r_loadk_int, V2_STORE_INT)
V2_LOADK_LEAF(lua55_v2r_loadk_flt, V2_STORE_FLT)
V2_LOADK_LEAF(lua55_v2r_loadk_str, V2_STORE_STR)

/* ---- table receiver guard --------------------------------------------- */
#define V2_TABLE_RECEIVER()                                                 \
    V2_VALUE_DISP(receiver, V2_RECEIVER_DISP_HOLE)                          \
    Lua55GuestTableV2 *table = v2_learn_table(frame, receiver);             \
    if (table == 0) V2_TABLE_REJECT(frame, LUA55_V2_REJECT_INVALID_OBJECT)

#define V2_FIELD_CAPACITY_GUARD(table)                                      \
    V2_HOLE32(field_layout_capacity, V2_FIELD_LAYOUT_CAP_HOLE);              \
    if ((table)->field_capacity != field_layout_capacity) {                  \
        V2_SPEC_MISMATCH(frame, field_layout_capacity,                       \
            (table)->field_capacity);                                        \
        V2_SPECIALIZATION_MISMATCH_EXIT(frame);                                          \
    }
#define V2_FIELD_SLOT_LOCATION(table, key_ref, field)                        \
    V2_FIELD_CAPACITY_GUARD(table)                                           \
    V2_HOLE32(field_slot, V2_FIELD_SLOT_HOLE);                               \
    if (field_slot >= (table)->field_capacity) {                             \
        V2_SPEC_MISMATCH(frame, field_slot, (table)->field_capacity);        \
        V2_SPECIALIZATION_MISMATCH_EXIT(frame);                                          \
    }                                                                        \
    Lua55GuestFieldV2 *field = &(table)->field_values[field_slot];           \
    if ((field)->occupied && (field)->key_reference != (uintptr_t)(key_ref)) { \
        V2_SPEC_MISMATCH(frame, LUA55_VALUE_SHORT_STRING, LUA55_VALUE_NIL);  \
        V2_SPECIALIZATION_MISMATCH_EXIT(frame);                                          \
    }

#define V2_FIELD_READ_LEAF(name, receiver_setup, object_copy)                 \
STENCIL(name##_slot)(Lua55NativeFrameV2 *frame)                              \
{                                                                            \
    V2_VALUE_DISP(target, V2_TARGET_DISP_HOLE)                               \
    receiver_setup                                                           \
    uint64_t key_ref = (uint64_t)V2_KEY_REF_HOLE;                            \
    __asm__ volatile ("" : "+r"(key_ref));                                  \
    Lua55GuestTableV2 *table = v2_learn_table(frame, receiver);              \
    if (table == 0) V2_TABLE_REJECT(frame, LUA55_V2_REJECT_INVALID_OBJECT); \
    object_copy                                                              \
    V2_FIELD_SLOT_LOCATION(table, key_ref, field)                            \
    if (!field->occupied) { SET_TAG(target, LUA55_VALUE_NIL);                \
        target->payload.reference = 0; }                                     \
    else *target = field->value;                                             \
    LUA55_RESIDUAL_NEXT(frame);                                              \
}                                                                            \
STENCIL(name##_missing)(Lua55NativeFrameV2 *frame)                           \
{                                                                            \
    V2_VALUE_DISP(target, V2_TARGET_DISP_HOLE)                               \
    receiver_setup                                                           \
    uint64_t key_ref = (uint64_t)V2_KEY_REF_HOLE;                            \
    __asm__ volatile ("" : "+r"(key_ref));                                  \
    Lua55GuestTableV2 *table = v2_learn_table(frame, receiver);              \
    if (table == 0) V2_TABLE_REJECT(frame, LUA55_V2_REJECT_INVALID_OBJECT); \
    object_copy                                                              \
    V2_FIELD_CAPACITY_GUARD(table)                                           \
    Lua55ValueV2 *cell = v2_find_field(table, (uintptr_t)key_ref, 0);        \
    if (cell == 0) { SET_TAG(target, LUA55_VALUE_NIL);                       \
        target->payload.reference = 0; }                                     \
    else *target = *cell;                                                    \
    LUA55_RESIDUAL_NEXT(frame);                                              \
}

#define V2_FIELD_RECEIVER_SETUP V2_VALUE_DISP(receiver, V2_RECEIVER_DISP_HOLE)
#define V2_FIELD_NO_OBJECT() do { } while (0);
V2_FIELD_READ_LEAF(lua55_v2r_getfield, V2_FIELD_RECEIVER_SETUP, V2_FIELD_NO_OBJECT())

#define V2_FIELD_SELF_SETUP                                                  \
    V2_VALUE_DISP(object, V2_OBJECT_DISP_HOLE)                               \
    V2_VALUE_DISP(receiver, V2_RECEIVER_DISP_HOLE)
#define V2_FIELD_SELF_COPY() *object = *receiver;
V2_FIELD_READ_LEAF(lua55_v2r_self, V2_FIELD_SELF_SETUP, V2_FIELD_SELF_COPY())

#define V2_GETTABUP_SETUP                                                    \
    V2_HOLE32(upvalue_reg, V2_UPVALUE_HOLE);                                 \
    Lua55UpvalueCellV2 *cell0 = frame->upvalues[upvalue_reg];                \
    Lua55ValueV2 *receiver = cell0->state == LUA55_UPVALUE_OPEN             \
        ? cell0->open_slot : &cell0->closed_value;
#define V2_GETTABUP_NO_OBJECT() do { } while (0);
V2_FIELD_READ_LEAF(lua55_v2r_gettabup, V2_GETTABUP_SETUP, V2_GETTABUP_NO_OBJECT())

/* ---- GETTABLE: exact key-domain leaves --------------------------------- */
STENCIL(lua55_v2r_gettable_int)(Lua55NativeFrameV2 *frame)
{
    V2_VALUE_DISP(target, V2_TARGET_DISP_HOLE)
    V2_VALUE_DISP(receiver, V2_RECEIVER_DISP_HOLE)
    V2_VALUE_DISP(key, V2_KEY_DISP_HOLE)
    if (key->tag != LUA55_VALUE_INTEGER) {
        V2_SPEC_MISMATCH(frame, LUA55_VALUE_INTEGER, key->tag);
        V2_SPECIALIZATION_MISMATCH_EXIT(frame);
    }
    Lua55GuestTableV2 *table = v2_learn_table(frame, receiver);
    if (table == 0) V2_TABLE_REJECT(frame, LUA55_V2_REJECT_INVALID_OBJECT);
    Lua55ValueV2 *cell = v2_array_slot(table, key->payload.integer);
    if (cell == 0) { SET_TAG(target, LUA55_VALUE_NIL); target->payload.reference = 0; }
    else *target = *cell;
    LUA55_RESIDUAL_NEXT(frame);
}

STENCIL(lua55_v2r_gettable_str)(Lua55NativeFrameV2 *frame)
{
    V2_VALUE_DISP(target, V2_TARGET_DISP_HOLE)
    V2_VALUE_DISP(receiver, V2_RECEIVER_DISP_HOLE)
    V2_VALUE_DISP(key, V2_KEY_DISP_HOLE)
    if (!v2_is_string_tag(key->tag)) {
        V2_SPEC_MISMATCH(frame, LUA55_VALUE_SHORT_STRING, key->tag);
        V2_SPECIALIZATION_MISMATCH_EXIT(frame);
    }
    Lua55GuestTableV2 *table = v2_learn_table(frame, receiver);
    if (table == 0) V2_TABLE_REJECT(frame, LUA55_V2_REJECT_INVALID_OBJECT);
    Lua55ValueV2 *cell = v2_find_field(table, (uintptr_t)key->payload.reference, 0);
    if (cell == 0) { SET_TAG(target, LUA55_VALUE_NIL); target->payload.reference = 0; }
    else *target = *cell;
    LUA55_RESIDUAL_NEXT(frame);
}

/* ---- SETTABLE: exact int-key / str-key leaves with cold grow/create ---- */
#define V2_SETTABLE_INT_CONST(name, growname, store)                        \
STENCIL(name)(Lua55NativeFrameV2 *frame)                                    \
{                                                                           \
    V2_TABLE_RECEIVER();                                                     \
    V2_VALUE_DISP(key, V2_KEY_DISP_HOLE)                                   \
    uint64_t grow = V2_NEED_GROW_LINK_HOLE;                                 \
    __asm__ volatile ("" : "+r"(grow));                                     \
    if (key->tag != LUA55_VALUE_INTEGER) {                                  \
        V2_SPEC_MISMATCH(frame, LUA55_VALUE_INTEGER, key->tag);             \
        V2_SPECIALIZATION_MISMATCH_EXIT(frame);                                         \
    }                                                                       \
    Lua55ValueV2 *cell = v2_array_slot(table, key->payload.integer);        \
    if (cell != 0) {                                                        \
        store(cell);                                                        \
        LUA55_RESIDUAL_NEXT(frame);                                         \
    }                                                                       \
    return ((Lua55NativeEntryV2)grow)(frame);                               \
}                                                                           \
STENCIL(growname)(Lua55NativeFrameV2 *frame)                                \
{                                                                           \
    V2_TABLE_RECEIVER();                                                     \
    V2_VALUE_DISP(key, V2_KEY_DISP_HOLE)                                   \
    uint64_t succ = V2_RESUME_LINK_HOLE;                                    \
    __asm__ volatile ("" : "+r"(succ));                                     \
    if (key->tag != LUA55_VALUE_INTEGER) {                                  \
        V2_SPEC_MISMATCH(frame, LUA55_VALUE_INTEGER, key->tag);             \
        V2_SPECIALIZATION_MISMATCH_EXIT(frame);                                         \
    }                                                                       \
    if (key->payload.integer >= 1 &&                                        \
        v2_grow_array(frame, table, (uint64_t)key->payload.integer)) {      \
        Lua55ValueV2 *cell = v2_array_slot(table, key->payload.integer);    \
        if (cell != 0) { store(cell);                                       \
            return ((Lua55NativeEntryV2)succ)(frame); }                     \
    }                                                                       \
    V2_REJECT(frame, LUA55_V2_REJECT_INVALID_OBJECT);                       \
    LUA55_CPS_HOST_EXIT(frame);                                             \
}

V2_SETTABLE_INT_CONST(lua55_v2r_settable_int_const_nil_inbounds,
    lua55_v2r_settable_int_const_nil_grow, V2_STORE_NIL)
V2_SETTABLE_INT_CONST(lua55_v2r_settable_int_const_false_inbounds,
    lua55_v2r_settable_int_const_false_grow, V2_STORE_FALSE)
V2_SETTABLE_INT_CONST(lua55_v2r_settable_int_const_true_inbounds,
    lua55_v2r_settable_int_const_true_grow, V2_STORE_TRUE)
V2_SETTABLE_INT_CONST(lua55_v2r_settable_int_const_int_inbounds,
    lua55_v2r_settable_int_const_int_grow, V2_STORE_INT)
V2_SETTABLE_INT_CONST(lua55_v2r_settable_int_const_flt_inbounds,
    lua55_v2r_settable_int_const_flt_grow, V2_STORE_FLT)
V2_SETTABLE_INT_CONST(lua55_v2r_settable_int_const_str_inbounds,
    lua55_v2r_settable_int_const_str_grow, V2_STORE_STR)

STENCIL(lua55_v2r_settable_int_reg_inbounds)(Lua55NativeFrameV2 *frame)
{
    V2_TABLE_RECEIVER();
    V2_VALUE_DISP(key, V2_KEY_DISP_HOLE)
    V2_VALUE_DISP(source, V2_SOURCE_DISP_HOLE)
    uint64_t grow = V2_NEED_GROW_LINK_HOLE;
    __asm__ volatile ("" : "+r"(grow));
    if (key->tag != LUA55_VALUE_INTEGER) {
        V2_SPEC_MISMATCH(frame, LUA55_VALUE_INTEGER, key->tag);
        V2_SPECIALIZATION_MISMATCH_EXIT(frame);
    }
    Lua55ValueV2 *cell = v2_array_slot(table, key->payload.integer);
    if (cell != 0) {
        V2_STORE_REG(cell, source, table);
        LUA55_RESIDUAL_NEXT(frame);
    }
    return ((Lua55NativeEntryV2)grow)(frame);
}

STENCIL(lua55_v2r_settable_int_reg_grow)(Lua55NativeFrameV2 *frame)
{
    V2_TABLE_RECEIVER();
    V2_VALUE_DISP(key, V2_KEY_DISP_HOLE)
    V2_VALUE_DISP(source, V2_SOURCE_DISP_HOLE)
    uint64_t succ = V2_RESUME_LINK_HOLE;
    __asm__ volatile ("" : "+r"(succ));
    if (key->tag != LUA55_VALUE_INTEGER) {
        V2_SPEC_MISMATCH(frame, LUA55_VALUE_INTEGER, key->tag);
        V2_SPECIALIZATION_MISMATCH_EXIT(frame);
    }
    if (key->payload.integer >= 1 &&
        v2_grow_array(frame, table, (uint64_t)key->payload.integer)) {
        Lua55ValueV2 *cell = v2_array_slot(table, key->payload.integer);
        if (cell != 0) {
            V2_STORE_REG(cell, source, table);
            return ((Lua55NativeEntryV2)succ)(frame);
        }
    }
    V2_REJECT(frame, LUA55_V2_REJECT_INVALID_OBJECT);
    LUA55_CPS_HOST_EXIT(frame);
}

#define V2_SETTABLE_STR_CONST(name, createname, store)                      \
STENCIL(name)(Lua55NativeFrameV2 *frame)                                    \
{                                                                           \
    V2_TABLE_RECEIVER();                                                     \
    V2_VALUE_DISP(key, V2_KEY_DISP_HOLE)                                   \
    uint64_t create = V2_NEED_CREATE_LINK_HOLE;                             \
    __asm__ volatile ("" : "+r"(create));                                   \
    if (!v2_is_string_tag(key->tag)) {                                      \
        V2_SPEC_MISMATCH(frame, LUA55_VALUE_SHORT_STRING, key->tag);        \
        V2_SPECIALIZATION_MISMATCH_EXIT(frame);                                         \
    }                                                                       \
    Lua55ValueV2 *cell = v2_find_field(table,                               \
        (uintptr_t)key->payload.reference, 0);                              \
    if (cell != 0) {                                                        \
        store(cell);                                                        \
        LUA55_RESIDUAL_NEXT(frame);                                         \
    }                                                                       \
    return ((Lua55NativeEntryV2)create)(frame);                             \
}                                                                           \
STENCIL(createname)(Lua55NativeFrameV2 *frame)                              \
{                                                                           \
    V2_TABLE_RECEIVER();                                                     \
    V2_VALUE_DISP(key, V2_KEY_DISP_HOLE)                                   \
    uint64_t succ = V2_RESUME_LINK_HOLE;                                    \
    __asm__ volatile ("" : "+r"(succ));                                     \
    if (!v2_is_string_tag(key->tag)) {                                      \
        V2_SPEC_MISMATCH(frame, LUA55_VALUE_SHORT_STRING, key->tag);        \
        V2_SPECIALIZATION_MISMATCH_EXIT(frame);                                         \
    }                                                                       \
    Lua55ValueV2 *cell = v2_find_field(table,                               \
        (uintptr_t)key->payload.reference, 1);                              \
    if (cell != 0) {                                                        \
        store(cell);                                                        \
        return ((Lua55NativeEntryV2)succ)(frame);                           \
    }                                                                       \
    V2_REJECT(frame, LUA55_V2_REJECT_INVALID_OBJECT);                       \
    LUA55_CPS_HOST_EXIT(frame);                                             \
}

V2_SETTABLE_STR_CONST(lua55_v2r_settable_str_const_nil_existing,
    lua55_v2r_settable_str_const_nil_create, V2_STORE_NIL)
V2_SETTABLE_STR_CONST(lua55_v2r_settable_str_const_false_existing,
    lua55_v2r_settable_str_const_false_create, V2_STORE_FALSE)
V2_SETTABLE_STR_CONST(lua55_v2r_settable_str_const_true_existing,
    lua55_v2r_settable_str_const_true_create, V2_STORE_TRUE)
V2_SETTABLE_STR_CONST(lua55_v2r_settable_str_const_int_existing,
    lua55_v2r_settable_str_const_int_create, V2_STORE_INT)
V2_SETTABLE_STR_CONST(lua55_v2r_settable_str_const_flt_existing,
    lua55_v2r_settable_str_const_flt_create, V2_STORE_FLT)
V2_SETTABLE_STR_CONST(lua55_v2r_settable_str_const_str_existing,
    lua55_v2r_settable_str_const_str_create, V2_STORE_STR)

STENCIL(lua55_v2r_settable_str_reg_existing)(Lua55NativeFrameV2 *frame)
{
    V2_TABLE_RECEIVER();
    V2_VALUE_DISP(key, V2_KEY_DISP_HOLE)
    V2_VALUE_DISP(source, V2_SOURCE_DISP_HOLE)
    uint64_t create = V2_NEED_CREATE_LINK_HOLE;
    __asm__ volatile ("" : "+r"(create));
    if (!v2_is_string_tag(key->tag)) {
        V2_SPEC_MISMATCH(frame, LUA55_VALUE_SHORT_STRING, key->tag);
        V2_SPECIALIZATION_MISMATCH_EXIT(frame);
    }
    Lua55ValueV2 *cell = v2_find_field(table,
        (uintptr_t)key->payload.reference, 0);
    if (cell != 0) {
        V2_STORE_REG(cell, source, table);
        LUA55_RESIDUAL_NEXT(frame);
    }
    return ((Lua55NativeEntryV2)create)(frame);
}

STENCIL(lua55_v2r_settable_str_reg_create)(Lua55NativeFrameV2 *frame)
{
    V2_TABLE_RECEIVER();
    V2_VALUE_DISP(key, V2_KEY_DISP_HOLE)
    V2_VALUE_DISP(source, V2_SOURCE_DISP_HOLE)
    uint64_t succ = V2_RESUME_LINK_HOLE;
    __asm__ volatile ("" : "+r"(succ));
    if (!v2_is_string_tag(key->tag)) {
        V2_SPEC_MISMATCH(frame, LUA55_VALUE_SHORT_STRING, key->tag);
        V2_SPECIALIZATION_MISMATCH_EXIT(frame);
    }
    Lua55ValueV2 *cell = v2_find_field(table,
        (uintptr_t)key->payload.reference, 1);
    if (cell != 0) {
        V2_STORE_REG(cell, source, table);
        return ((Lua55NativeEntryV2)succ)(frame);
    }
    V2_REJECT(frame, LUA55_V2_REJECT_INVALID_OBJECT);
    LUA55_CPS_HOST_EXIT(frame);
}

/* ---- SETI: exact const/reg leaves with cold grow ----------------------- */
#define V2_SETI_CONST(name, growname, store)                                \
STENCIL(name)(Lua55NativeFrameV2 *frame)                                    \
{                                                                           \
    V2_TABLE_RECEIVER();                                                     \
    int64_t key = (int64_t)V2_INT_KEY_HOLE;                                 \
    __asm__ volatile ("" : "+r"(key));                                      \
    uint64_t grow = V2_NEED_GROW_LINK_HOLE;                                 \
    __asm__ volatile ("" : "+r"(grow));                                     \
    Lua55ValueV2 *cell = v2_array_slot(table, key);                         \
    if (cell != 0) {                                                        \
        store(cell);                                                        \
        LUA55_RESIDUAL_NEXT(frame);                                         \
    }                                                                       \
    return ((Lua55NativeEntryV2)grow)(frame);                               \
}                                                                           \
STENCIL(growname)(Lua55NativeFrameV2 *frame)                                \
{                                                                           \
    V2_TABLE_RECEIVER();                                                     \
    int64_t key = (int64_t)V2_INT_KEY_HOLE;                                 \
    __asm__ volatile ("" : "+r"(key));                                      \
    uint64_t succ = V2_RESUME_LINK_HOLE;                                    \
    __asm__ volatile ("" : "+r"(succ));                                     \
    if (key >= 1 && v2_grow_array(frame, table, (uint64_t)key)) {           \
        Lua55ValueV2 *cell = v2_array_slot(table, key);                     \
        if (cell != 0) { store(cell);                                       \
            return ((Lua55NativeEntryV2)succ)(frame); }                     \
    }                                                                       \
    V2_REJECT(frame, LUA55_V2_REJECT_INVALID_OBJECT);                       \
    LUA55_CPS_HOST_EXIT(frame);                                             \
}

V2_SETI_CONST(lua55_v2r_seti_const_nil_inbounds,
    lua55_v2r_seti_const_nil_grow, V2_STORE_NIL)
V2_SETI_CONST(lua55_v2r_seti_const_false_inbounds,
    lua55_v2r_seti_const_false_grow, V2_STORE_FALSE)
V2_SETI_CONST(lua55_v2r_seti_const_true_inbounds,
    lua55_v2r_seti_const_true_grow, V2_STORE_TRUE)
V2_SETI_CONST(lua55_v2r_seti_const_int_inbounds,
    lua55_v2r_seti_const_int_grow, V2_STORE_INT)
V2_SETI_CONST(lua55_v2r_seti_const_flt_inbounds,
    lua55_v2r_seti_const_flt_grow, V2_STORE_FLT)
V2_SETI_CONST(lua55_v2r_seti_const_str_inbounds,
    lua55_v2r_seti_const_str_grow, V2_STORE_STR)

STENCIL(lua55_v2r_seti_reg_inbounds)(Lua55NativeFrameV2 *frame)
{
    V2_TABLE_RECEIVER();
    int64_t key = (int64_t)V2_INT_KEY_HOLE;
    __asm__ volatile ("" : "+r"(key));
    V2_VALUE_DISP(source, V2_SOURCE_DISP_HOLE)
    uint64_t grow = V2_NEED_GROW_LINK_HOLE;
    __asm__ volatile ("" : "+r"(grow));
    Lua55ValueV2 *cell = v2_array_slot(table, key);
    if (cell != 0) {
        V2_STORE_REG(cell, source, table);
        LUA55_RESIDUAL_NEXT(frame);
    }
    return ((Lua55NativeEntryV2)grow)(frame);
}

STENCIL(lua55_v2r_seti_reg_grow)(Lua55NativeFrameV2 *frame)
{
    V2_TABLE_RECEIVER();
    int64_t key = (int64_t)V2_INT_KEY_HOLE;
    __asm__ volatile ("" : "+r"(key));
    V2_VALUE_DISP(source, V2_SOURCE_DISP_HOLE)
    uint64_t succ = V2_RESUME_LINK_HOLE;
    __asm__ volatile ("" : "+r"(succ));
    if (key >= 1 && v2_grow_array(frame, table, (uint64_t)key)) {
        Lua55ValueV2 *cell = v2_array_slot(table, key);
        if (cell != 0) {
            V2_STORE_REG(cell, source, table);
            return ((Lua55NativeEntryV2)succ)(frame);
        }
    }
    V2_REJECT(frame, LUA55_V2_REJECT_INVALID_OBJECT);
    LUA55_CPS_HOST_EXIT(frame);
}

/* ---- SETFIELD: exact const/reg leaves with cold create ----------------- */
#define V2_SETFIELD_CONST(name, createname, store)                          \
STENCIL(name)(Lua55NativeFrameV2 *frame)                                    \
{                                                                           \
    V2_TABLE_RECEIVER();                                                     \
    uint64_t key_ref = (uint64_t)V2_KEY_REF_HOLE;                           \
    __asm__ volatile ("" : "+r"(key_ref));                                  \
    uint64_t create = V2_NEED_CREATE_LINK_HOLE;                             \
    __asm__ volatile ("" : "+r"(create));                                   \
    V2_FIELD_SLOT_LOCATION(table, key_ref, field)                            \
    if (field->occupied) { store(&field->value); LUA55_RESIDUAL_NEXT(frame); } \
    return ((Lua55NativeEntryV2)create)(frame);                              \
}                                                                           \
STENCIL(createname)(Lua55NativeFrameV2 *frame)                              \
{                                                                           \
    V2_TABLE_RECEIVER();                                                     \
    uint64_t key_ref = (uint64_t)V2_KEY_REF_HOLE;                           \
    __asm__ volatile ("" : "+r"(key_ref));                                  \
    uint64_t succ = V2_RESUME_LINK_HOLE;                                    \
    __asm__ volatile ("" : "+r"(succ));                                     \
    V2_FIELD_SLOT_LOCATION(table, key_ref, field)                            \
    Lua55ValueV2 *cell = field->occupied ? &field->value                    \
        : v2_find_field(table, (uintptr_t)key_ref, 1);                       \
    if (cell == &field->value) { store(cell);                               \
        return ((Lua55NativeEntryV2)succ)(frame); }                         \
    V2_SPEC_MISMATCH(frame, field_slot, table->field_capacity);             \
    V2_SPECIALIZATION_MISMATCH_EXIT(frame);                                             \
}

V2_SETFIELD_CONST(lua55_v2r_setfield_const_nil_existing,
    lua55_v2r_setfield_const_nil_create, V2_STORE_NIL)
V2_SETFIELD_CONST(lua55_v2r_setfield_const_false_existing,
    lua55_v2r_setfield_const_false_create, V2_STORE_FALSE)
V2_SETFIELD_CONST(lua55_v2r_setfield_const_true_existing,
    lua55_v2r_setfield_const_true_create, V2_STORE_TRUE)
V2_SETFIELD_CONST(lua55_v2r_setfield_const_int_existing,
    lua55_v2r_setfield_const_int_create, V2_STORE_INT)
V2_SETFIELD_CONST(lua55_v2r_setfield_const_flt_existing,
    lua55_v2r_setfield_const_flt_create, V2_STORE_FLT)
V2_SETFIELD_CONST(lua55_v2r_setfield_const_str_existing,
    lua55_v2r_setfield_const_str_create, V2_STORE_STR)

STENCIL(lua55_v2r_setfield_reg_existing)(Lua55NativeFrameV2 *frame)
{
    V2_TABLE_RECEIVER();
    uint64_t key_ref = (uint64_t)V2_KEY_REF_HOLE;
    __asm__ volatile ("" : "+r"(key_ref));
    V2_VALUE_DISP(source, V2_SOURCE_DISP_HOLE)
    uint64_t create = V2_NEED_CREATE_LINK_HOLE;
    __asm__ volatile ("" : "+r"(create));
    V2_FIELD_SLOT_LOCATION(table, key_ref, field)
    if (field->occupied) {
        V2_STORE_REG(&field->value, source, table);
        LUA55_RESIDUAL_NEXT(frame);
    }
    return ((Lua55NativeEntryV2)create)(frame);
}

STENCIL(lua55_v2r_setfield_reg_create)(Lua55NativeFrameV2 *frame)
{
    V2_TABLE_RECEIVER();
    uint64_t key_ref = (uint64_t)V2_KEY_REF_HOLE;
    __asm__ volatile ("" : "+r"(key_ref));
    V2_VALUE_DISP(source, V2_SOURCE_DISP_HOLE)
    uint64_t succ = V2_RESUME_LINK_HOLE;
    __asm__ volatile ("" : "+r"(succ));
    V2_FIELD_SLOT_LOCATION(table, key_ref, field)
    Lua55ValueV2 *cell = field->occupied ? &field->value
        : v2_find_field(table, (uintptr_t)key_ref, 1);
    if (cell == &field->value) {
        V2_STORE_REG(cell, source, table);
        return ((Lua55NativeEntryV2)succ)(frame);
    }
    V2_SPEC_MISMATCH(frame, field_slot, table->field_capacity);
    V2_SPECIALIZATION_MISMATCH_EXIT(frame);
}

/* ======================================================================= */
/* Batch 3: exact arithmetic / unary / comparison operand-product leaves    */
/* ------------------------------------------------------------------------ */
/* One residual per exact operand product (IntegerInteger, IntegerFloat,    */
/* FloatInteger, FloatFloat; string-string; identity; mixed-false). Guards  */
/* validate the selected product; a mismatch publishes the typed            */
/* specialization rejection. The shift leaves mirror luaV_shiftl exactly    */
/* (SHRI negates the encoded shift count; SHL/SHR negate the runtime shift  */
/* operand).                                                                */
/* ======================================================================= */

#define V2_LEAF_GUARD(frame, value, expected) do {                          \
    if ((value)->tag != (expected)) {                                       \
        V2_SPEC_MISMATCH(frame, (expected), (value)->tag);                  \
        V2_SPECIALIZATION_MISMATCH_EXIT(frame);                                         \
    }                                                                       \
} while (0)

#define V2_LEAF_GUARD_STR(frame, value) do {                                \
    if (!v2_is_string_tag((value)->tag)) {                                  \
        V2_SPEC_MISMATCH(frame, LUA55_VALUE_SHORT_STRING, (value)->tag);    \
        V2_SPECIALIZATION_MISMATCH_EXIT(frame);                                         \
    }                                                                       \
} while (0)

#define V2_DIV_FLT(a, b) ((a) / (b))

#define V2_ARITH_CONST_INT_RIGHT                                            \
    Lua55ValueV2 const_cell;                                                \
    int64_t cv = (int64_t)V2_CONST_INT;                                     \
    __asm__ volatile ("" : "+r"(cv));                                      \
    SET_TAG(&const_cell, LUA55_VALUE_INTEGER);                              \
    const_cell.payload.integer = cv;                                        \
    right = &const_cell;

#define V2_ARITH_CONST_FLT_RIGHT                                            \
    Lua55ValueV2 const_cell;                                                \
    uint64_t cb = V2_CONST_FLT;                                             \
    __asm__ volatile ("" : "+r"(cb));                                      \
    SET_TAG(&const_cell, LUA55_VALUE_FLOAT);                                \
    __builtin_memcpy(&const_cell.payload.floating, &cb, 8);                 \
    right = &const_cell;

#define V2_PRO_RR()  V2_ARITH_PROLOGUE_RR()
#define V2_PRO_RI()  V2_ARITH_PROLOGUE_SYNTH(V2_ARITH_RIGHT_INIT)
#define V2_PRO_RK_INT() V2_ARITH_PROLOGUE_SYNTH(V2_ARITH_CONST_INT_RIGHT)
#define V2_PRO_RK_FLT() V2_ARITH_PROLOGUE_SYNTH(V2_ARITH_CONST_FLT_RIGHT)

#define V2_ARITH_II(name, intfn, prologue)                                  \
STENCIL(name)(Lua55NativeFrameV2 *frame)                                    \
{                                                                           \
    prologue;                                                               \
    V2_LEAF_GUARD(frame, left, LUA55_VALUE_INTEGER);                        \
    V2_LEAF_GUARD(frame, right, LUA55_VALUE_INTEGER);                       \
    SET_TAG(target, LUA55_VALUE_INTEGER);                                   \
    target->payload.integer = intfn(left->payload.integer, right->payload.integer); \
    LUA55_RESIDUAL_NEXT(frame);                                             \
}

#define V2_ARITH_II_Z(name, intfn, prologue)                                \
STENCIL(name)(Lua55NativeFrameV2 *frame)                                    \
{                                                                           \
    prologue;                                                               \
    V2_LEAF_GUARD(frame, left, LUA55_VALUE_INTEGER);                        \
    V2_LEAF_GUARD(frame, right, LUA55_VALUE_INTEGER);                       \
    if (right->payload.integer == 0) {                                      \
        V2_REJECT(frame, LUA55_V2_REJECT_UNSUPPORTED_METAMETHOD);           \
        LUA55_CPS_HOST_EXIT(frame);                                         \
    }                                                                       \
    SET_TAG(target, LUA55_VALUE_INTEGER);                                   \
    target->payload.integer = intfn(left->payload.integer, right->payload.integer); \
    LUA55_RESIDUAL_NEXT(frame);                                             \
}

#define V2_ARITH_IF(name, fltfn, prologue)                                  \
STENCIL(name)(Lua55NativeFrameV2 *frame)                                    \
{                                                                           \
    prologue;                                                               \
    V2_LEAF_GUARD(frame, left, LUA55_VALUE_INTEGER);                        \
    V2_LEAF_GUARD(frame, right, LUA55_VALUE_FLOAT);                         \
    SET_TAG(target, LUA55_VALUE_FLOAT);                                     \
    target->payload.floating = fltfn((double)left->payload.integer,         \
        right->payload.floating);                                           \
    LUA55_RESIDUAL_NEXT(frame);                                             \
}

#define V2_ARITH_FI(name, fltfn, prologue)                                  \
STENCIL(name)(Lua55NativeFrameV2 *frame)                                    \
{                                                                           \
    prologue;                                                               \
    V2_LEAF_GUARD(frame, left, LUA55_VALUE_FLOAT);                          \
    V2_LEAF_GUARD(frame, right, LUA55_VALUE_INTEGER);                       \
    SET_TAG(target, LUA55_VALUE_FLOAT);                                     \
    target->payload.floating = fltfn(left->payload.floating,                \
        (double)right->payload.integer);                                    \
    LUA55_RESIDUAL_NEXT(frame);                                             \
}

#define V2_ARITH_FF(name, fltfn, prologue)                                  \
STENCIL(name)(Lua55NativeFrameV2 *frame)                                    \
{                                                                           \
    prologue;                                                               \
    V2_LEAF_GUARD(frame, left, LUA55_VALUE_FLOAT);                          \
    V2_LEAF_GUARD(frame, right, LUA55_VALUE_FLOAT);                         \
    SET_TAG(target, LUA55_VALUE_FLOAT);                                     \
    target->payload.floating = fltfn(left->payload.floating,                \
        right->payload.floating);                                           \
    LUA55_RESIDUAL_NEXT(frame);                                             \
}

#define V2_ARITH_IF_C(name, intfn, prologue)                                \
STENCIL(name)(Lua55NativeFrameV2 *frame)                                    \
{                                                                           \
    prologue;                                                               \
    V2_LEAF_GUARD(frame, left, LUA55_VALUE_INTEGER);                        \
    V2_LEAF_GUARD(frame, right, LUA55_VALUE_FLOAT);                         \
    int64_t i2;                                                             \
    if (!v2_flt_to_int_eq(right->payload.floating, &i2)) {                  \
        V2_REJECT(frame, LUA55_V2_REJECT_UNSUPPORTED_METAMETHOD);           \
        LUA55_CPS_HOST_EXIT(frame); }                                       \
    SET_TAG(target, LUA55_VALUE_INTEGER);                                   \
    target->payload.integer = intfn(left->payload.integer, i2);             \
    LUA55_RESIDUAL_NEXT(frame);                                             \
}

#define V2_ARITH_FI_C(name, intfn, prologue)                                \
STENCIL(name)(Lua55NativeFrameV2 *frame)                                    \
{                                                                           \
    prologue;                                                               \
    V2_LEAF_GUARD(frame, left, LUA55_VALUE_FLOAT);                          \
    V2_LEAF_GUARD(frame, right, LUA55_VALUE_INTEGER);                       \
    int64_t i1;                                                             \
    if (!v2_flt_to_int_eq(left->payload.floating, &i1)) {                   \
        V2_REJECT(frame, LUA55_V2_REJECT_UNSUPPORTED_METAMETHOD);           \
        LUA55_CPS_HOST_EXIT(frame); }                                       \
    SET_TAG(target, LUA55_VALUE_INTEGER);                                   \
    target->payload.integer = intfn(i1, right->payload.integer);            \
    LUA55_RESIDUAL_NEXT(frame);                                             \
}

#define V2_ARITH_FF_C(name, intfn, prologue)                                \
STENCIL(name)(Lua55NativeFrameV2 *frame)                                    \
{                                                                           \
    prologue;                                                               \
    V2_LEAF_GUARD(frame, left, LUA55_VALUE_FLOAT);                          \
    V2_LEAF_GUARD(frame, right, LUA55_VALUE_FLOAT);                         \
    int64_t i1, i2;                                                         \
    if (!v2_flt_to_int_eq(left->payload.floating, &i1) ||                   \
        !v2_flt_to_int_eq(right->payload.floating, &i2)) {                  \
        V2_REJECT(frame, LUA55_V2_REJECT_UNSUPPORTED_METAMETHOD);           \
        LUA55_CPS_HOST_EXIT(frame); }                                       \
    SET_TAG(target, LUA55_VALUE_INTEGER);                                   \
    target->payload.integer = intfn(i1, i2);                                \
    LUA55_RESIDUAL_NEXT(frame);                                             \
}

#define V2_CMP_TAKE_K0() do { if (!cond) { V2_BRANCH_TAKEN(frame); } } while (0)
#define V2_CMP_TAKE_K1() do { if (cond) { V2_BRANCH_TAKEN(frame); } } while (0)

#define V2_CMP_LEAF_ONE(name, gl, gr, cond_expr, taken)                     \
STENCIL(name)(Lua55NativeFrameV2 *frame)                                    \
{                                                                           \
    V2_CMP_PROLOGUE_RR()                                                    \
    V2_LEAF_GUARD(frame, left, gl);                                         \
    V2_LEAF_GUARD(frame, right, gr);                                        \
    int cond = cond_expr;                                                   \
    taken;                                                                  \
    LUA55_RESIDUAL_NEXT(frame);                                             \
}
#define V2_CMP_LEAF(name, gl, gr, cond_expr)                                \
    V2_CMP_LEAF_ONE(name##_k0, gl, gr, cond_expr, V2_CMP_TAKE_K0())         \
    V2_CMP_LEAF_ONE(name##_k1, gl, gr, cond_expr, V2_CMP_TAKE_K1())

#define V2_CMP_SS_LEAF_ONE(name, cond_expr, taken)                          \
STENCIL(name)(Lua55NativeFrameV2 *frame)                                    \
{                                                                           \
    V2_CMP_PROLOGUE_RR()                                                    \
    V2_LEAF_GUARD_STR(frame, left);                                         \
    V2_LEAF_GUARD_STR(frame, right);                                        \
    int cond = cond_expr;                                                   \
    taken;                                                                  \
    LUA55_RESIDUAL_NEXT(frame);                                             \
}
#define V2_CMP_SS_LEAF(name, cond_expr)                                     \
    V2_CMP_SS_LEAF_ONE(name##_k0, cond_expr, V2_CMP_TAKE_K0())              \
    V2_CMP_SS_LEAF_ONE(name##_k1, cond_expr, V2_CMP_TAKE_K1())

/* ---- arithmetic instantiations ---------------------------------------- */

V2_ARITH_II(lua55_v2r_add_ii, v2_int_add, V2_PRO_RR())
V2_ARITH_IF(lua55_v2r_add_if, FLT_ADD, V2_PRO_RR())
V2_ARITH_FI(lua55_v2r_add_fi, FLT_ADD, V2_PRO_RR())
V2_ARITH_FF(lua55_v2r_add_ff, FLT_ADD, V2_PRO_RR())
V2_ARITH_II(lua55_v2r_sub_ii, v2_int_sub, V2_PRO_RR())
V2_ARITH_IF(lua55_v2r_sub_if, FLT_SUB, V2_PRO_RR())
V2_ARITH_FI(lua55_v2r_sub_fi, FLT_SUB, V2_PRO_RR())
V2_ARITH_FF(lua55_v2r_sub_ff, FLT_SUB, V2_PRO_RR())
V2_ARITH_II(lua55_v2r_mul_ii, v2_int_mul, V2_PRO_RR())
V2_ARITH_IF(lua55_v2r_mul_if, FLT_MUL, V2_PRO_RR())
V2_ARITH_FI(lua55_v2r_mul_fi, FLT_MUL, V2_PRO_RR())
V2_ARITH_FF(lua55_v2r_mul_ff, FLT_MUL, V2_PRO_RR())
V2_ARITH_II(lua55_v2r_addi_ii, v2_int_add, V2_PRO_RI())
V2_ARITH_FI(lua55_v2r_addi_fi, FLT_ADD, V2_PRO_RI())
V2_ARITH_II(lua55_v2r_addk_ii, v2_int_add, V2_PRO_RK_INT())
V2_ARITH_IF(lua55_v2r_addk_if, FLT_ADD, V2_PRO_RK_FLT())
V2_ARITH_FI(lua55_v2r_addk_fi, FLT_ADD, V2_PRO_RK_INT())
V2_ARITH_FF(lua55_v2r_addk_ff, FLT_ADD, V2_PRO_RK_FLT())
V2_ARITH_II(lua55_v2r_subk_ii, v2_int_sub, V2_PRO_RK_INT())
V2_ARITH_IF(lua55_v2r_subk_if, FLT_SUB, V2_PRO_RK_FLT())
V2_ARITH_FI(lua55_v2r_subk_fi, FLT_SUB, V2_PRO_RK_INT())
V2_ARITH_FF(lua55_v2r_subk_ff, FLT_SUB, V2_PRO_RK_FLT())
V2_ARITH_II(lua55_v2r_mulk_ii, v2_int_mul, V2_PRO_RK_INT())
V2_ARITH_IF(lua55_v2r_mulk_if, FLT_MUL, V2_PRO_RK_FLT())
V2_ARITH_FI(lua55_v2r_mulk_fi, FLT_MUL, V2_PRO_RK_INT())
V2_ARITH_FF(lua55_v2r_mulk_ff, FLT_MUL, V2_PRO_RK_FLT())

V2_ARITH_II_Z(lua55_v2r_mod_ii, v2_mod, V2_PRO_RR())
V2_ARITH_IF(lua55_v2r_mod_if, v2_fmod, V2_PRO_RR())
V2_ARITH_FI(lua55_v2r_mod_fi, v2_fmod, V2_PRO_RR())
V2_ARITH_FF(lua55_v2r_mod_ff, v2_fmod, V2_PRO_RR())
V2_ARITH_II_Z(lua55_v2r_idiv_ii, v2_idiv, V2_PRO_RR())
V2_ARITH_IF(lua55_v2r_idiv_if, v2_flt_idiv, V2_PRO_RR())
V2_ARITH_FI(lua55_v2r_idiv_fi, v2_flt_idiv, V2_PRO_RR())
V2_ARITH_FF(lua55_v2r_idiv_ff, v2_flt_idiv, V2_PRO_RR())
V2_ARITH_II_Z(lua55_v2r_modk_ii, v2_mod, V2_PRO_RK_INT())
V2_ARITH_IF(lua55_v2r_modk_if, v2_fmod, V2_PRO_RK_FLT())
V2_ARITH_FI(lua55_v2r_modk_fi, v2_fmod, V2_PRO_RK_INT())
V2_ARITH_FF(lua55_v2r_modk_ff, v2_fmod, V2_PRO_RK_FLT())
V2_ARITH_II_Z(lua55_v2r_idivk_ii, v2_idiv, V2_PRO_RK_INT())
V2_ARITH_IF(lua55_v2r_idivk_if, v2_flt_idiv, V2_PRO_RK_FLT())
V2_ARITH_FI(lua55_v2r_idivk_fi, v2_flt_idiv, V2_PRO_RK_INT())
V2_ARITH_FF(lua55_v2r_idivk_ff, v2_flt_idiv, V2_PRO_RK_FLT())

STENCIL(lua55_v2r_div_ii)(Lua55NativeFrameV2 *frame)
{
    V2_ARITH_PROLOGUE_RR()
    V2_LEAF_GUARD(frame, left, LUA55_VALUE_INTEGER);
    V2_LEAF_GUARD(frame, right, LUA55_VALUE_INTEGER);
    if (right->payload.integer == 0) {
        V2_REJECT(frame, LUA55_V2_REJECT_UNSUPPORTED_METAMETHOD);
        LUA55_CPS_HOST_EXIT(frame);
    }
    SET_TAG(target, LUA55_VALUE_FLOAT);
    target->payload.floating = (double)left->payload.integer
        / (double)right->payload.integer;
    LUA55_RESIDUAL_NEXT(frame);
}
V2_ARITH_IF(lua55_v2r_div_if, V2_DIV_FLT, V2_PRO_RR())
V2_ARITH_FI(lua55_v2r_div_fi, V2_DIV_FLT, V2_PRO_RR())
V2_ARITH_FF(lua55_v2r_div_ff, V2_DIV_FLT, V2_PRO_RR())
STENCIL(lua55_v2r_divk_ii)(Lua55NativeFrameV2 *frame)
{
    V2_ARITH_PROLOGUE_SYNTH(V2_ARITH_CONST_INT_RIGHT)
    V2_LEAF_GUARD(frame, left, LUA55_VALUE_INTEGER);
    V2_LEAF_GUARD(frame, right, LUA55_VALUE_INTEGER);
    if (right->payload.integer == 0) {
        V2_REJECT(frame, LUA55_V2_REJECT_UNSUPPORTED_METAMETHOD);
        LUA55_CPS_HOST_EXIT(frame);
    }
    SET_TAG(target, LUA55_VALUE_FLOAT);
    target->payload.floating = (double)left->payload.integer
        / (double)right->payload.integer;
    LUA55_RESIDUAL_NEXT(frame);
}
V2_ARITH_IF(lua55_v2r_divk_if, V2_DIV_FLT, V2_PRO_RK_FLT())
V2_ARITH_FI(lua55_v2r_divk_fi, V2_DIV_FLT, V2_PRO_RK_INT())
V2_ARITH_FF(lua55_v2r_divk_ff, V2_DIV_FLT, V2_PRO_RK_FLT())

V2_ARITH_II(lua55_v2r_pow_ii, v2_pow, V2_PRO_RR())
V2_ARITH_IF(lua55_v2r_pow_if, v2_pow, V2_PRO_RR())
V2_ARITH_FI(lua55_v2r_pow_fi, v2_pow, V2_PRO_RR())
V2_ARITH_FF(lua55_v2r_pow_ff, v2_pow, V2_PRO_RR())
V2_ARITH_II(lua55_v2r_powk_ii, v2_pow, V2_PRO_RK_INT())
V2_ARITH_IF(lua55_v2r_powk_if, v2_pow, V2_PRO_RK_FLT())
V2_ARITH_FI(lua55_v2r_powk_fi, v2_pow, V2_PRO_RK_INT())
V2_ARITH_FF(lua55_v2r_powk_ff, v2_pow, V2_PRO_RK_FLT())

V2_ARITH_II(lua55_v2r_band_ii, v2_int_band, V2_PRO_RR())
V2_ARITH_IF_C(lua55_v2r_band_if, v2_int_band, V2_PRO_RR())
V2_ARITH_FI_C(lua55_v2r_band_fi, v2_int_band, V2_PRO_RR())
V2_ARITH_FF_C(lua55_v2r_band_ff, v2_int_band, V2_PRO_RR())
V2_ARITH_II(lua55_v2r_bor_ii, v2_int_bor, V2_PRO_RR())
V2_ARITH_IF_C(lua55_v2r_bor_if, v2_int_bor, V2_PRO_RR())
V2_ARITH_FI_C(lua55_v2r_bor_fi, v2_int_bor, V2_PRO_RR())
V2_ARITH_FF_C(lua55_v2r_bor_ff, v2_int_bor, V2_PRO_RR())
V2_ARITH_II(lua55_v2r_bxor_ii, v2_int_bxor, V2_PRO_RR())
V2_ARITH_IF_C(lua55_v2r_bxor_if, v2_int_bxor, V2_PRO_RR())
V2_ARITH_FI_C(lua55_v2r_bxor_fi, v2_int_bxor, V2_PRO_RR())
V2_ARITH_FF_C(lua55_v2r_bxor_ff, v2_int_bxor, V2_PRO_RR())
V2_ARITH_II(lua55_v2r_bandk_ii, v2_int_band, V2_PRO_RK_INT())
V2_ARITH_IF_C(lua55_v2r_bandk_if, v2_int_band, V2_PRO_RK_FLT())
V2_ARITH_FI_C(lua55_v2r_bandk_fi, v2_int_band, V2_PRO_RK_INT())
V2_ARITH_FF_C(lua55_v2r_bandk_ff, v2_int_band, V2_PRO_RK_FLT())
V2_ARITH_II(lua55_v2r_bork_ii, v2_int_bor, V2_PRO_RK_INT())
V2_ARITH_IF_C(lua55_v2r_bork_if, v2_int_bor, V2_PRO_RK_FLT())
V2_ARITH_FI_C(lua55_v2r_bork_fi, v2_int_bor, V2_PRO_RK_INT())
V2_ARITH_FF_C(lua55_v2r_bork_ff, v2_int_bor, V2_PRO_RK_FLT())
V2_ARITH_II(lua55_v2r_bxork_ii, v2_int_bxor, V2_PRO_RK_INT())
V2_ARITH_IF_C(lua55_v2r_bxork_if, v2_int_bxor, V2_PRO_RK_FLT())
V2_ARITH_FI_C(lua55_v2r_bxork_fi, v2_int_bxor, V2_PRO_RK_INT())
V2_ARITH_FF_C(lua55_v2r_bxork_ff, v2_int_bxor, V2_PRO_RK_FLT())

#define V2_SHIFT_II(name, shiftexpr, prologue)                              \
STENCIL(name)(Lua55NativeFrameV2 *frame)                                    \
{                                                                           \
    prologue;                                                               \
    V2_LEAF_GUARD(frame, left, LUA55_VALUE_INTEGER);                        \
    V2_LEAF_GUARD(frame, right, LUA55_VALUE_INTEGER);                       \
    SET_TAG(target, LUA55_VALUE_INTEGER);                                   \
    target->payload.integer = shiftexpr;                                    \
    LUA55_RESIDUAL_NEXT(frame);                                             \
}
V2_SHIFT_II(lua55_v2r_shl_ii, v2_shiftl(left->payload.integer, right->payload.integer), V2_PRO_RR())
V2_SHIFT_II(lua55_v2r_shr_ii, v2_shiftl(left->payload.integer, -right->payload.integer), V2_PRO_RR())
V2_SHIFT_II(lua55_v2r_shri_ii, v2_shiftl(left->payload.integer, -right->payload.integer), V2_PRO_RI())
V2_SHIFT_II(lua55_v2r_shli_ii, v2_shiftl(right->payload.integer, left->payload.integer), V2_PRO_RI())

STENCIL(lua55_v2r_shl_if)(Lua55NativeFrameV2 *frame)
{
    V2_ARITH_PROLOGUE_RR()
    V2_LEAF_GUARD(frame, left, LUA55_VALUE_INTEGER);
    V2_LEAF_GUARD(frame, right, LUA55_VALUE_FLOAT);
    int64_t i2;
    if (!v2_flt_to_int_eq(right->payload.floating, &i2)) {
        V2_REJECT(frame, LUA55_V2_REJECT_UNSUPPORTED_METAMETHOD);
        LUA55_CPS_HOST_EXIT(frame);
    }
    SET_TAG(target, LUA55_VALUE_INTEGER);
    target->payload.integer = v2_shiftl(left->payload.integer, i2);
    LUA55_RESIDUAL_NEXT(frame);
}
STENCIL(lua55_v2r_shl_fi)(Lua55NativeFrameV2 *frame)
{
    V2_ARITH_PROLOGUE_RR()
    V2_LEAF_GUARD(frame, left, LUA55_VALUE_FLOAT);
    V2_LEAF_GUARD(frame, right, LUA55_VALUE_INTEGER);
    int64_t i1;
    if (!v2_flt_to_int_eq(left->payload.floating, &i1)) {
        V2_REJECT(frame, LUA55_V2_REJECT_UNSUPPORTED_METAMETHOD);
        LUA55_CPS_HOST_EXIT(frame);
    }
    SET_TAG(target, LUA55_VALUE_INTEGER);
    target->payload.integer = v2_shiftl(i1, right->payload.integer);
    LUA55_RESIDUAL_NEXT(frame);
}
STENCIL(lua55_v2r_shl_ff)(Lua55NativeFrameV2 *frame)
{
    V2_ARITH_PROLOGUE_RR()
    V2_LEAF_GUARD(frame, left, LUA55_VALUE_FLOAT);
    V2_LEAF_GUARD(frame, right, LUA55_VALUE_FLOAT);
    int64_t i1, i2;
    if (!v2_flt_to_int_eq(left->payload.floating, &i1) ||
        !v2_flt_to_int_eq(right->payload.floating, &i2)) {
        V2_REJECT(frame, LUA55_V2_REJECT_UNSUPPORTED_METAMETHOD);
        LUA55_CPS_HOST_EXIT(frame);
    }
    SET_TAG(target, LUA55_VALUE_INTEGER);
    target->payload.integer = v2_shiftl(i1, i2);
    LUA55_RESIDUAL_NEXT(frame);
}
STENCIL(lua55_v2r_shr_if)(Lua55NativeFrameV2 *frame)
{
    V2_ARITH_PROLOGUE_RR()
    V2_LEAF_GUARD(frame, left, LUA55_VALUE_INTEGER);
    V2_LEAF_GUARD(frame, right, LUA55_VALUE_FLOAT);
    int64_t i2;
    if (!v2_flt_to_int_eq(right->payload.floating, &i2)) {
        V2_REJECT(frame, LUA55_V2_REJECT_UNSUPPORTED_METAMETHOD);
        LUA55_CPS_HOST_EXIT(frame);
    }
    SET_TAG(target, LUA55_VALUE_INTEGER);
    target->payload.integer = v2_shiftl(left->payload.integer, -i2);
    LUA55_RESIDUAL_NEXT(frame);
}
STENCIL(lua55_v2r_shr_fi)(Lua55NativeFrameV2 *frame)
{
    V2_ARITH_PROLOGUE_RR()
    V2_LEAF_GUARD(frame, left, LUA55_VALUE_FLOAT);
    V2_LEAF_GUARD(frame, right, LUA55_VALUE_INTEGER);
    int64_t i1;
    if (!v2_flt_to_int_eq(left->payload.floating, &i1)) {
        V2_REJECT(frame, LUA55_V2_REJECT_UNSUPPORTED_METAMETHOD);
        LUA55_CPS_HOST_EXIT(frame);
    }
    SET_TAG(target, LUA55_VALUE_INTEGER);
    target->payload.integer = v2_shiftl(i1, -right->payload.integer);
    LUA55_RESIDUAL_NEXT(frame);
}
STENCIL(lua55_v2r_shr_ff)(Lua55NativeFrameV2 *frame)
{
    V2_ARITH_PROLOGUE_RR()
    V2_LEAF_GUARD(frame, left, LUA55_VALUE_FLOAT);
    V2_LEAF_GUARD(frame, right, LUA55_VALUE_FLOAT);
    int64_t i1, i2;
    if (!v2_flt_to_int_eq(left->payload.floating, &i1) ||
        !v2_flt_to_int_eq(right->payload.floating, &i2)) {
        V2_REJECT(frame, LUA55_V2_REJECT_UNSUPPORTED_METAMETHOD);
        LUA55_CPS_HOST_EXIT(frame);
    }
    SET_TAG(target, LUA55_VALUE_INTEGER);
    target->payload.integer = v2_shiftl(i1, -i2);
    LUA55_RESIDUAL_NEXT(frame);
}
STENCIL(lua55_v2r_shri_fi)(Lua55NativeFrameV2 *frame)
{
    V2_ARITH_PROLOGUE_SYNTH(V2_ARITH_RIGHT_INIT)
    V2_LEAF_GUARD(frame, left, LUA55_VALUE_FLOAT);
    V2_LEAF_GUARD(frame, right, LUA55_VALUE_INTEGER);
    int64_t i1;
    if (!v2_flt_to_int_eq(left->payload.floating, &i1)) {
        V2_REJECT(frame, LUA55_V2_REJECT_UNSUPPORTED_METAMETHOD);
        LUA55_CPS_HOST_EXIT(frame);
    }
    SET_TAG(target, LUA55_VALUE_INTEGER);
    target->payload.integer = v2_shiftl(i1, -right->payload.integer);
    LUA55_RESIDUAL_NEXT(frame);
}
STENCIL(lua55_v2r_shli_fi)(Lua55NativeFrameV2 *frame)
{
    V2_ARITH_PROLOGUE_SYNTH(V2_ARITH_RIGHT_INIT)
    V2_LEAF_GUARD(frame, left, LUA55_VALUE_FLOAT);
    V2_LEAF_GUARD(frame, right, LUA55_VALUE_INTEGER);
    int64_t i1;
    if (!v2_flt_to_int_eq(left->payload.floating, &i1)) {
        V2_REJECT(frame, LUA55_V2_REJECT_UNSUPPORTED_METAMETHOD);
        LUA55_CPS_HOST_EXIT(frame);
    }
    SET_TAG(target, LUA55_VALUE_INTEGER);
    target->payload.integer = v2_shiftl(right->payload.integer, i1);
    LUA55_RESIDUAL_NEXT(frame);
}

/* ---- unary: exact operand-product leaves ------------------------------- */
STENCIL(lua55_v2r_unm_int)(Lua55NativeFrameV2 *frame)
{
    V2_UNARY_PROLOGUE()
    V2_LEAF_GUARD(frame, source, LUA55_VALUE_INTEGER);
    SET_TAG(target, LUA55_VALUE_INTEGER);
    target->payload.integer = v2_int_unm(source->payload.integer);
    LUA55_RESIDUAL_NEXT(frame);
}
STENCIL(lua55_v2r_unm_flt)(Lua55NativeFrameV2 *frame)
{
    V2_UNARY_PROLOGUE()
    V2_LEAF_GUARD(frame, source, LUA55_VALUE_FLOAT);
    SET_TAG(target, LUA55_VALUE_FLOAT);
    target->payload.floating = v2_flt_unm(source->payload.floating);
    LUA55_RESIDUAL_NEXT(frame);
}
STENCIL(lua55_v2r_bnot_int)(Lua55NativeFrameV2 *frame)
{
    V2_UNARY_PROLOGUE()
    V2_LEAF_GUARD(frame, source, LUA55_VALUE_INTEGER);
    SET_TAG(target, LUA55_VALUE_INTEGER);
    target->payload.integer = ~source->payload.integer;
    LUA55_RESIDUAL_NEXT(frame);
}
STENCIL(lua55_v2r_bnot_flt)(Lua55NativeFrameV2 *frame)
{
    V2_UNARY_PROLOGUE()
    V2_LEAF_GUARD(frame, source, LUA55_VALUE_FLOAT);
    int64_t value;
    if (!v2_flt_to_int_eq(source->payload.floating, &value)) {
        V2_REJECT(frame, LUA55_V2_REJECT_UNSUPPORTED_METAMETHOD);
        LUA55_CPS_HOST_EXIT(frame);
    }
    SET_TAG(target, LUA55_VALUE_INTEGER);
    target->payload.integer = ~value;
    LUA55_RESIDUAL_NEXT(frame);
}
STENCIL(lua55_v2r_len_str)(Lua55NativeFrameV2 *frame)
{
    V2_UNARY_PROLOGUE()
    V2_LEAF_GUARD_STR(frame, source);
    Lua55GuestStringV2 *str = (Lua55GuestStringV2 *)source->payload.reference;
    SET_TAG(target, LUA55_VALUE_INTEGER);
    target->payload.integer = (str != 0) ? (int64_t)str->length : 0;
    LUA55_RESIDUAL_NEXT(frame);
}
STENCIL(lua55_v2r_len_table)(Lua55NativeFrameV2 *frame)
{
    V2_UNARY_PROLOGUE()
    Lua55GuestTableV2 *table = v2_primitive_len_table(frame, source);
    if (table == 0) V2_TABLE_REJECT(frame, LUA55_V2_REJECT_INVALID_OBJECT);
    SET_TAG(target, LUA55_VALUE_INTEGER);
    target->payload.integer = v2_table_len(table);
    LUA55_RESIDUAL_NEXT(frame);
}

/* ---- comparisons: exact operand-product leaves ------------------------- */

/* lt / le (reg-reg) */
V2_CMP_LEAF(lua55_v2r_lt_ii, LUA55_VALUE_INTEGER, LUA55_VALUE_INTEGER,
    left->payload.integer < right->payload.integer)
V2_CMP_LEAF(lua55_v2r_lt_if, LUA55_VALUE_INTEGER, LUA55_VALUE_FLOAT,
    (double)left->payload.integer < right->payload.floating)
V2_CMP_LEAF(lua55_v2r_lt_fi, LUA55_VALUE_FLOAT, LUA55_VALUE_INTEGER,
    left->payload.floating < (double)right->payload.integer)
V2_CMP_LEAF(lua55_v2r_lt_ff, LUA55_VALUE_FLOAT, LUA55_VALUE_FLOAT,
    left->payload.floating < right->payload.floating)
V2_CMP_SS_LEAF(lua55_v2r_lt_ss,
    v2_string_cmp(left->payload.reference, right->payload.reference) < 0)
V2_CMP_LEAF(lua55_v2r_le_ii, LUA55_VALUE_INTEGER, LUA55_VALUE_INTEGER,
    left->payload.integer <= right->payload.integer)
V2_CMP_LEAF(lua55_v2r_le_if, LUA55_VALUE_INTEGER, LUA55_VALUE_FLOAT,
    (double)left->payload.integer <= right->payload.floating)
V2_CMP_LEAF(lua55_v2r_le_fi, LUA55_VALUE_FLOAT, LUA55_VALUE_INTEGER,
    left->payload.floating <= (double)right->payload.integer)
V2_CMP_LEAF(lua55_v2r_le_ff, LUA55_VALUE_FLOAT, LUA55_VALUE_FLOAT,
    left->payload.floating <= right->payload.floating)
V2_CMP_SS_LEAF(lua55_v2r_le_ss,
    v2_string_cmp(left->payload.reference, right->payload.reference) <= 0)

/* immediate-right variants (right is always an integer immediate) */
#define V2_CMP_I_LEAF_ONE(name, gl, cond_expr, taken)                       \
STENCIL(name)(Lua55NativeFrameV2 *frame)                                    \
{                                                                           \
    V2_CMP_PROLOGUE_SYNTH(V2_CMP_RIGHT_INIT)                               \
    V2_LEAF_GUARD(frame, left, gl);                                         \
    int cond = cond_expr;                                                   \
    taken;                                                                  \
    LUA55_RESIDUAL_NEXT(frame);                                             \
}
#define V2_CMP_I_LEAF(name, gl, cond_expr)                                  \
    V2_CMP_I_LEAF_ONE(name##_k0, gl, cond_expr, V2_CMP_TAKE_K0())           \
    V2_CMP_I_LEAF_ONE(name##_k1, gl, cond_expr, V2_CMP_TAKE_K1())
V2_CMP_I_LEAF(lua55_v2r_lti_ii, LUA55_VALUE_INTEGER,
    left->payload.integer < right->payload.integer)
V2_CMP_I_LEAF(lua55_v2r_lti_fi, LUA55_VALUE_FLOAT,
    left->payload.floating < (double)right->payload.integer)
V2_CMP_I_LEAF(lua55_v2r_lei_ii, LUA55_VALUE_INTEGER,
    left->payload.integer <= right->payload.integer)
V2_CMP_I_LEAF(lua55_v2r_lei_fi, LUA55_VALUE_FLOAT,
    left->payload.floating <= (double)right->payload.integer)
V2_CMP_I_LEAF(lua55_v2r_gti_ii, LUA55_VALUE_INTEGER,
    left->payload.integer > right->payload.integer)
V2_CMP_I_LEAF(lua55_v2r_gti_fi, LUA55_VALUE_FLOAT,
    left->payload.floating > (double)right->payload.integer)
V2_CMP_I_LEAF(lua55_v2r_gei_ii, LUA55_VALUE_INTEGER,
    left->payload.integer >= right->payload.integer)
V2_CMP_I_LEAF(lua55_v2r_gei_fi, LUA55_VALUE_FLOAT,
    left->payload.floating >= (double)right->payload.integer)

/* eq (reg-reg): numeric products, string content, ref identity, same
   primitive, mixed-false */
V2_CMP_LEAF(lua55_v2r_eq_ii, LUA55_VALUE_INTEGER, LUA55_VALUE_INTEGER,
    left->payload.integer == right->payload.integer)
V2_CMP_LEAF(lua55_v2r_eq_if, LUA55_VALUE_INTEGER, LUA55_VALUE_FLOAT,
    v2_eq_int_float(left->payload.integer, right->payload.floating))
V2_CMP_LEAF(lua55_v2r_eq_fi, LUA55_VALUE_FLOAT, LUA55_VALUE_INTEGER,
    v2_eq_int_float(right->payload.integer, left->payload.floating))
V2_CMP_LEAF(lua55_v2r_eq_ff, LUA55_VALUE_FLOAT, LUA55_VALUE_FLOAT,
    left->payload.floating == right->payload.floating)
V2_CMP_SS_LEAF(lua55_v2r_eq_ss,
    v2_string_bytes_eq(left->payload.reference, right->payload.reference))

#define V2_EQ_RR_LEAF(name, taken)                                          \
STENCIL(name)(Lua55NativeFrameV2 *frame)                                    \
{                                                                           \
    V2_CMP_PROLOGUE_RR()                                                    \
    if (left->tag != right->tag ||                                          \
        (left->tag != LUA55_VALUE_TABLE && left->tag != LUA55_VALUE_CLOSURE)) { \
        V2_SPEC_MISMATCH(frame, left->tag, right->tag);                     \
        V2_SPECIALIZATION_MISMATCH_EXIT(frame); }                                       \
    int cond = left->payload.reference == right->payload.reference;         \
    taken;                                                                  \
    LUA55_RESIDUAL_NEXT(frame);                                             \
}
V2_EQ_RR_LEAF(lua55_v2r_eq_rr_k0, V2_CMP_TAKE_K0())
V2_EQ_RR_LEAF(lua55_v2r_eq_rr_k1, V2_CMP_TAKE_K1())

#define V2_EQ_SP_LEAF(name, taken)                                          \
STENCIL(name)(Lua55NativeFrameV2 *frame)                                    \
{                                                                           \
    V2_CMP_PROLOGUE_RR()                                                    \
    if (left->tag != right->tag || left->tag > LUA55_VALUE_TRUE) {          \
        V2_SPEC_MISMATCH(frame, left->tag, right->tag);                     \
        V2_SPECIALIZATION_MISMATCH_EXIT(frame); }                                       \
    int cond = 1;                                                           \
    taken;                                                                  \
    LUA55_RESIDUAL_NEXT(frame);                                             \
}
V2_EQ_SP_LEAF(lua55_v2r_eq_sp_k0, V2_CMP_TAKE_K0())
V2_EQ_SP_LEAF(lua55_v2r_eq_sp_k1, V2_CMP_TAKE_K1())

#define V2_EQ_MX_LEAF(name, taken)                                          \
STENCIL(name)(Lua55NativeFrameV2 *frame)                                    \
{                                                                           \
    V2_CMP_PROLOGUE_RR()                                                    \
    int ln = (left->tag == LUA55_VALUE_INTEGER || left->tag == LUA55_VALUE_FLOAT); \
    int rn = (right->tag == LUA55_VALUE_INTEGER || right->tag == LUA55_VALUE_FLOAT); \
    if (left->tag == right->tag || (ln && rn)) {                            \
        V2_SPEC_MISMATCH(frame, left->tag, right->tag);                     \
        V2_SPECIALIZATION_MISMATCH_EXIT(frame); }                                       \
    int cond = 0;                                                           \
    taken;                                                                  \
    LUA55_RESIDUAL_NEXT(frame);                                             \
}
V2_EQ_MX_LEAF(lua55_v2r_eq_mx_k0, V2_CMP_TAKE_K0())
V2_EQ_MX_LEAF(lua55_v2r_eq_mx_k1, V2_CMP_TAKE_K1())

/* eqi: immediate right is an integer; mixed left yields false */
V2_CMP_I_LEAF(lua55_v2r_eqi_ii, LUA55_VALUE_INTEGER,
    left->payload.integer == right->payload.integer)
V2_CMP_I_LEAF(lua55_v2r_eqi_fi, LUA55_VALUE_FLOAT,
    v2_eq_int_float(right->payload.integer, left->payload.floating))
#define V2_EQI_MX_LEAF(name, taken)                                        \
STENCIL(name)(Lua55NativeFrameV2 *frame)                                    \
{                                                                           \
    V2_CMP_PROLOGUE_SYNTH(V2_CMP_RIGHT_INIT)                               \
    int ln = (left->tag == LUA55_VALUE_INTEGER || left->tag == LUA55_VALUE_FLOAT); \
    if (ln) {                                                               \
        V2_SPEC_MISMATCH(frame, LUA55_VALUE_NIL, left->tag);                \
        V2_SPECIALIZATION_MISMATCH_EXIT(frame); }                                       \
    int cond = 0;                                                           \
    taken;                                                                  \
    LUA55_RESIDUAL_NEXT(frame);                                             \
}
V2_EQI_MX_LEAF(lua55_v2r_eqi_mx_k0, V2_CMP_TAKE_K0())
V2_EQI_MX_LEAF(lua55_v2r_eqi_mx_k1, V2_CMP_TAKE_K1())

/* eqk: the constant kind is projection-proven. */
#define V2_EQK_GUARDED_LEAF_ONE(name, prologue, guard, cond_expr, taken)    \
STENCIL(name)(Lua55NativeFrameV2 *frame)                                    \
{                                                                           \
    prologue                                                                \
    guard;                                                                  \
    int cond = cond_expr;                                                   \
    taken;                                                                  \
    LUA55_RESIDUAL_NEXT(frame);                                             \
}
#define V2_EQK_GUARDED_LEAF(name, prologue, guard, cond_expr)               \
    V2_EQK_GUARDED_LEAF_ONE(name##_k0, prologue, guard, cond_expr, V2_CMP_TAKE_K0()) \
    V2_EQK_GUARDED_LEAF_ONE(name##_k1, prologue, guard, cond_expr, V2_CMP_TAKE_K1())

V2_EQK_GUARDED_LEAF(lua55_v2r_eqk_int_ii,
    V2_CMP_PROLOGUE_SYNTH(V2_ARITH_CONST_INT_RIGHT),
    V2_LEAF_GUARD(frame, left, LUA55_VALUE_INTEGER),
    left->payload.integer == right->payload.integer)
V2_EQK_GUARDED_LEAF(lua55_v2r_eqk_int_fi,
    V2_CMP_PROLOGUE_SYNTH(V2_ARITH_CONST_INT_RIGHT),
    V2_LEAF_GUARD(frame, left, LUA55_VALUE_FLOAT),
    v2_eq_int_float(right->payload.integer, left->payload.floating))
V2_EQK_GUARDED_LEAF(lua55_v2r_eqk_flt_if,
    V2_CMP_PROLOGUE_SYNTH(V2_ARITH_CONST_FLT_RIGHT),
    V2_LEAF_GUARD(frame, left, LUA55_VALUE_INTEGER),
    v2_eq_int_float(left->payload.integer, right->payload.floating))
V2_EQK_GUARDED_LEAF(lua55_v2r_eqk_flt_ff,
    V2_CMP_PROLOGUE_SYNTH(V2_ARITH_CONST_FLT_RIGHT),
    V2_LEAF_GUARD(frame, left, LUA55_VALUE_FLOAT),
    left->payload.floating == right->payload.floating)
V2_EQK_GUARDED_LEAF(lua55_v2r_eqk_str_ss,
    V2_CMP_PROLOGUE_LEFT() uint64_t ref = (uint64_t)V2_CONST_REF; __asm__ volatile ("" : "+r"(ref));,
    V2_LEAF_GUARD_STR(frame, left),
    v2_string_bytes_eq(left->payload.reference, ref))

#define V2_EQK_MX_LEAF(name, prologue, reject_expr, taken)                  \
STENCIL(name)(Lua55NativeFrameV2 *frame)                                    \
{                                                                           \
    prologue                                                                \
    if (reject_expr) {                                                      \
        V2_SPEC_MISMATCH(frame, LUA55_VALUE_NIL, left->tag);                \
        V2_SPECIALIZATION_MISMATCH_EXIT(frame); }                                       \
    int cond = 0;                                                           \
    taken;                                                                  \
    LUA55_RESIDUAL_NEXT(frame);                                             \
}
#define V2_EQK_MX_PAIR(name, prologue, reject_expr)                         \
    V2_EQK_MX_LEAF(name##_k0, prologue, reject_expr, V2_CMP_TAKE_K0())      \
    V2_EQK_MX_LEAF(name##_k1, prologue, reject_expr, V2_CMP_TAKE_K1())
V2_EQK_MX_PAIR(lua55_v2r_eqk_int_mx,
    V2_CMP_PROLOGUE_SYNTH(V2_ARITH_CONST_INT_RIGHT),
    left->tag == LUA55_VALUE_INTEGER || left->tag == LUA55_VALUE_FLOAT)
V2_EQK_MX_PAIR(lua55_v2r_eqk_flt_mx,
    V2_CMP_PROLOGUE_SYNTH(V2_ARITH_CONST_FLT_RIGHT),
    left->tag == LUA55_VALUE_INTEGER || left->tag == LUA55_VALUE_FLOAT)
V2_EQK_MX_PAIR(lua55_v2r_eqk_str_mx, V2_CMP_PROLOGUE_LEFT(),
    v2_is_string_tag(left->tag))

#define V2_EQK_TAG_LEAF(name, expected, taken)                              \
STENCIL(name)(Lua55NativeFrameV2 *frame)                                    \
{                                                                           \
    V2_CMP_PROLOGUE_LEFT()                                                  \
    int cond = (left->tag == expected);                                     \
    taken;                                                                  \
    LUA55_RESIDUAL_NEXT(frame);                                             \
}
#define V2_EQK_TAG_PAIR(name, expected)                                     \
    V2_EQK_TAG_LEAF(name##_k0, expected, V2_CMP_TAKE_K0())                  \
    V2_EQK_TAG_LEAF(name##_k1, expected, V2_CMP_TAKE_K1())
V2_EQK_TAG_PAIR(lua55_v2r_eqk_nil, LUA55_VALUE_NIL)
V2_EQK_TAG_PAIR(lua55_v2r_eqk_false, LUA55_VALUE_FALSE)
V2_EQK_TAG_PAIR(lua55_v2r_eqk_true, LUA55_VALUE_TRUE)

/* ======================================================================= */
/* Batch 4: exact numeric-for leaves (integer/float protocol, step sign)    */
/* ------------------------------------------------------------------------ */
/* The learning invocation observes the loop protocol (all-integer or       */
/* float) and the step sign; the residual selects the exact forprep/        */
/* forloop pair. The sign guard is part of the selected shape; a changed    */
/* sign or protocol publishes a typed specialization rejection.             */
/* ======================================================================= */

#define V2_FORPREP_INT(name, pos)                                           \
STENCIL(name)(Lua55NativeFrameV2 *frame)                                    \
{                                                                           \
    V2_VALUE_DISP(base, V2_BASE_DISP_HOLE)                                  \
    Lua55ValueV2 *init = &base[0];                                         \
    Lua55ValueV2 *limit = &base[1];                                        \
    Lua55ValueV2 *step = &base[2];                                         \
    V2_LEAF_GUARD(frame, init, LUA55_VALUE_INTEGER);                        \
    V2_LEAF_GUARD(frame, limit, LUA55_VALUE_INTEGER);                       \
    V2_LEAF_GUARD(frame, step, LUA55_VALUE_INTEGER);                        \
    int64_t iv = init->payload.integer;                                     \
    int64_t lv = limit->payload.integer;                                    \
    int64_t sv = step->payload.integer;                                     \
    if ((pos && sv <= 0) || (!pos && sv >= 0)) {                            \
        V2_SPEC_MISMATCH(frame, LUA55_VALUE_INTEGER, 0);                    \
        V2_SPECIALIZATION_MISMATCH_EXIT(frame); }                                       \
    if (sv == 0) { V2_REJECT(frame, LUA55_V2_REJECT_STEP_ZERO);             \
                   LUA55_CPS_HOST_EXIT(frame); }                            \
    uintptr_t target;                                                       \
    if ((pos && iv > lv) || (!pos && iv < lv)) {                            \
        target = (uintptr_t)V2_SKIP_HOLE;                                   \
    } else {                                                                \
        uint64_t distance = pos ? (uint64_t)lv - (uint64_t)iv               \
                                : (uint64_t)iv - (uint64_t)lv;              \
        uint64_t stride = pos ? (uint64_t)sv                                \
                              : UINT64_C(0) - (uint64_t)sv;                 \
        SET_TAG(init, LUA55_VALUE_INTEGER);                                 \
        init->payload.integer = (int64_t)(distance / stride);               \
        SET_TAG(limit, LUA55_VALUE_INTEGER);                                \
        limit->payload.integer = sv;                                        \
        SET_TAG(step, LUA55_VALUE_INTEGER);                                 \
        step->payload.integer = iv;                                         \
        target = (uintptr_t)V2_BODY_HOLE;                                   \
    }                                                                       \
    __asm__ volatile ("" : "+r"(target));                                   \
    return ((Lua55NativeEntryV2)target)(frame);                             \
}

V2_FORPREP_INT(lua55_v2r_forprep_int_pos, 1)
V2_FORPREP_INT(lua55_v2r_forprep_int_neg, 0)

#define V2_FORPREP_FLT(name, pos)                                           \
STENCIL(name)(Lua55NativeFrameV2 *frame)                                    \
{                                                                           \
    V2_VALUE_DISP(base, V2_BASE_DISP_HOLE)                                  \
    Lua55ValueV2 *init = &base[0];                                         \
    Lua55ValueV2 *limit = &base[1];                                        \
    Lua55ValueV2 *step = &base[2];                                         \
    if (init->tag != LUA55_VALUE_INTEGER && init->tag != LUA55_VALUE_FLOAT) {\
        V2_SPEC_MISMATCH(frame, LUA55_VALUE_FLOAT, init->tag);              \
        V2_SPECIALIZATION_MISMATCH_EXIT(frame); }                                       \
    if (limit->tag != LUA55_VALUE_INTEGER && limit->tag != LUA55_VALUE_FLOAT) {\
        V2_SPEC_MISMATCH(frame, LUA55_VALUE_FLOAT, limit->tag);             \
        V2_SPECIALIZATION_MISMATCH_EXIT(frame); }                                       \
    if (step->tag != LUA55_VALUE_INTEGER && step->tag != LUA55_VALUE_FLOAT) {\
        V2_SPEC_MISMATCH(frame, LUA55_VALUE_FLOAT, step->tag);              \
        V2_SPECIALIZATION_MISMATCH_EXIT(frame); }                                       \
    if (init->tag == LUA55_VALUE_INTEGER && limit->tag == LUA55_VALUE_INTEGER \
        && step->tag == LUA55_VALUE_INTEGER) {                              \
        V2_SPEC_MISMATCH(frame, LUA55_VALUE_FLOAT, LUA55_VALUE_INTEGER);    \
        V2_SPECIALIZATION_MISMATCH_EXIT(frame); }                                       \
    double iv = init->tag == LUA55_VALUE_INTEGER                            \
        ? (double)init->payload.integer : init->payload.floating;           \
    double lv = limit->tag == LUA55_VALUE_INTEGER                           \
        ? (double)limit->payload.integer : limit->payload.floating;         \
    double sv = step->tag == LUA55_VALUE_INTEGER                            \
        ? (double)step->payload.integer : step->payload.floating;           \
    if ((pos && sv <= 0.0) || (!pos && sv >= 0.0)) {                        \
        V2_SPEC_MISMATCH(frame, LUA55_VALUE_FLOAT, 0);                      \
        V2_SPECIALIZATION_MISMATCH_EXIT(frame); }                                       \
    if (sv == 0.0) { V2_REJECT(frame, LUA55_V2_REJECT_STEP_ZERO);           \
                     LUA55_CPS_HOST_EXIT(frame); }                          \
    uintptr_t target;                                                       \
    if ((pos && lv < iv) || (!pos && iv < lv)) {                            \
        target = (uintptr_t)V2_SKIP_HOLE;                                   \
    } else {                                                                \
        SET_TAG(init, LUA55_VALUE_FLOAT); init->payload.floating = lv;      \
        SET_TAG(limit, LUA55_VALUE_FLOAT); limit->payload.floating = sv;    \
        SET_TAG(step, LUA55_VALUE_FLOAT); step->payload.floating = iv;      \
        target = (uintptr_t)V2_BODY_HOLE;                                   \
    }                                                                       \
    __asm__ volatile ("" : "+r"(target));                                   \
    return ((Lua55NativeEntryV2)target)(frame);                             \
}

V2_FORPREP_FLT(lua55_v2r_forprep_flt_pos, 1)
V2_FORPREP_FLT(lua55_v2r_forprep_flt_neg, 0)

STENCIL(lua55_v2r_forloop_int)(Lua55NativeFrameV2 *frame)
{
    V2_VALUE_DISP(base, V2_BASE_DISP_HOLE)
    Lua55ValueV2 *count_cell = &base[0];
    Lua55ValueV2 *step_cell = &base[1];
    Lua55ValueV2 *idx_cell = &base[2];
    V2_LEAF_GUARD(frame, step_cell, LUA55_VALUE_INTEGER);
    uintptr_t target;
    if (count_cell->payload.integer > 0) {
        count_cell->payload.integer = count_cell->payload.integer - 1;
        idx_cell->payload.integer = v2_int_add(
            idx_cell->payload.integer, step_cell->payload.integer);
        target = (uintptr_t)V2_LINK_HOLE;
    } else {
        target = (uintptr_t)V2_FALL_HOLE;
    }
    __asm__ volatile ("" : "+r"(target));
    return ((Lua55NativeEntryV2)target)(frame);
}

#define V2_FORLOOP_FLT(name, pos)                                           \
STENCIL(name)(Lua55NativeFrameV2 *frame)                                    \
{                                                                           \
    V2_VALUE_DISP(base, V2_BASE_DISP_HOLE)                                  \
    Lua55ValueV2 *count_cell = &base[0];                                   \
    Lua55ValueV2 *step_cell = &base[1];                                    \
    Lua55ValueV2 *idx_cell = &base[2];                                     \
    V2_LEAF_GUARD(frame, step_cell, LUA55_VALUE_FLOAT);                     \
    double idx = idx_cell->payload.floating;                                \
    double sv = step_cell->payload.floating;                                \
    double lv = count_cell->payload.floating;                               \
    if ((pos && sv <= 0.0) || (!pos && sv >= 0.0)) {                        \
        V2_SPEC_MISMATCH(frame, LUA55_VALUE_FLOAT, 0);                      \
        V2_SPECIALIZATION_MISMATCH_EXIT(frame); }                                       \
    idx = idx + sv;                                                         \
    uintptr_t target;                                                       \
    if ((pos && idx <= lv) || (!pos && lv <= idx)) {                        \
        idx_cell->payload.floating = idx;                                   \
        target = (uintptr_t)V2_LINK_HOLE;                                   \
    } else {                                                                \
        target = (uintptr_t)V2_FALL_HOLE;                                   \
    }                                                                       \
    __asm__ volatile ("" : "+r"(target));                                   \
    return ((Lua55NativeEntryV2)target)(frame);                             \
}

V2_FORLOOP_FLT(lua55_v2r_forloop_flt_pos, 1)
V2_FORLOOP_FLT(lua55_v2r_forloop_flt_neg, 0)

/* Exact learned numeric-for ADDI superinstructions. The learning product
   selects one leaf for the complete init/limit/step/accumulator tag vector
   and sign. Compile-time macro parameters remove all sibling classification
   from the published residual. */
/* Learning-only fused numeric-for SETTABLE cycle. Executes the complete
   cycle once, classifies (protocol, sign), and jumps past the FORLOOP. The
   const value comes from the patched const holes. Never published as RX. */
STENCIL_NOVEC(lua55_v2l_super_for_settable)(Lua55NativeFrameV2 *frame)
{
    V2_HOLE32(A, V2_BASE_INDEX_HOLE);
    V2_HOLE32(receiver_reg, V2_RECEIVER_HOLE);
    Lua55ValueV2 *init = &frame->values[A];
    Lua55ValueV2 *limit = &frame->values[A + 1];
    Lua55ValueV2 *step = &frame->values[A + 2];
    V2_LEARN_SLOT()
    {
        int proto_int = init->tag == LUA55_VALUE_INTEGER
            && limit->tag == LUA55_VALUE_INTEGER && step->tag == LUA55_VALUE_INTEGER;
        uint32_t proto = proto_int ? LUA55_VALUE_INTEGER : LUA55_VALUE_FLOAT;
        uint32_t sign = 0;
        if (step->tag == LUA55_VALUE_INTEGER) sign = step->payload.integer > 0 ? 0 : 1;
        else if (step->tag == LUA55_VALUE_FLOAT) sign = step->payload.floating > 0.0 ? 0 : 1;
        v2_learn_pair(frame, slot, proto, sign);
    }
    if (init->tag != LUA55_VALUE_INTEGER || limit->tag != LUA55_VALUE_INTEGER
        || step->tag != LUA55_VALUE_INTEGER) {
        V2_REJECT(frame, LUA55_V2_REJECT_UNSUPPORTED_OPCODE);
        LUA55_CPS_HOST_EXIT(frame);
    }
    int64_t iv = init->payload.integer, lv = limit->payload.integer;
    int64_t sv = step->payload.integer;
    if (sv == 0) { V2_REJECT(frame, LUA55_V2_REJECT_STEP_ZERO);
                   LUA55_CPS_HOST_EXIT(frame); }
    Lua55ValueV2 *receiver = &frame->values[receiver_reg];
    Lua55GuestTableV2 *table = v2_learn_table(frame, receiver);
    if (table == 0) V2_TABLE_REJECT(frame, LUA55_V2_REJECT_INVALID_OBJECT);
    uint32_t ck = V2_CONST_TAG;
    int64_t ci = (int64_t)V2_CONST_INT;
    uint64_t cf = V2_CONST_FLT;
    uint64_t cr = V2_CONST_REF;
    __asm__ volatile ("" : "+r"(ck)); __asm__ volatile ("" : "+r"(ci));
    __asm__ volatile ("" : "+r"(cf)); __asm__ volatile ("" : "+r"(cr));
    uintptr_t skip = (uintptr_t)V2_SKIP_HOLE;
    if (!((sv > 0 && iv > lv) || (sv < 0 && iv < lv))) {
        uint64_t distance = sv > 0 ? (uint64_t)lv - (uint64_t)iv
            : (uint64_t)iv - (uint64_t)lv;
        uint64_t stride = sv > 0 ? (uint64_t)sv : UINT64_C(0) - (uint64_t)sv;
        int64_t count = (int64_t)(distance / stride);
        for (;;) {
            Lua55ValueV2 *cell = v2_array_slot(table, iv);
            if (cell == 0) {
                if (iv >= 1 && v2_grow_array(frame, table, (uint64_t)iv))
                    cell = v2_array_slot(table, iv);
                else { V2_REJECT(frame, LUA55_V2_REJECT_INVALID_OBJECT);
                       LUA55_CPS_HOST_EXIT(frame); }
            }
            v2_learn_write_site(frame, table, 1, (uint64_t)iv);
            if (ck == LUA55_VALUE_INTEGER) {
                SET_TAG(cell, LUA55_VALUE_INTEGER); cell->payload.integer = ci;
            } else if (ck == LUA55_VALUE_FLOAT) {
                SET_TAG(cell, LUA55_VALUE_FLOAT);
                __builtin_memcpy(&cell->payload.floating, &cf, sizeof(cf));
            } else {
                SET_TAG(cell, ck); cell->payload.reference = (uintptr_t)cr;
            }
            if (count <= 0) break;
            count--; iv = v2_int_add(iv, sv);
        }
        SET_TAG(init, LUA55_VALUE_INTEGER); init->payload.integer = count;
        SET_TAG(limit, LUA55_VALUE_INTEGER); limit->payload.integer = sv;
        SET_TAG(step, LUA55_VALUE_INTEGER); step->payload.integer = iv;
    }
    __asm__ volatile ("" : "+r"(skip));
    return ((Lua55NativeEntryV2)skip)(frame);
}

static inline void v2_learn_accum(Lua55NativeFrameV2 *frame,
    uint32_t occ_slot, uint32_t key_tag, uint32_t acc_tag, uint32_t src_tag)
{
    Lua55NativeInvocationV2 *inv = frame->invocation;
    if (inv->learning == 0 || occ_slot >= inv->learning_slots) return;
    Lua55TableLearnSlotV2 *s =
        &((Lua55TableLearnSlotV2 *)inv->learning)[occ_slot];
    if (s->seen == 0) {
        s->key_tag = key_tag; s->value_tag = acc_tag;
        s->max_array_index = (uint64_t)src_tag;
        s->seen = 1; return;
    }
    if (s->key_tag != key_tag || s->value_tag != acc_tag
        || s->max_array_index != (uint64_t)src_tag)
        s->key_tag = UINT32_C(0xFFFFFFFF);
}

/* Learning-only fused dictionary accumulation. Classifies (key, acc, src)
   domains and executes the whole chain once. The source is either a live
   register (src_field 0) or a field read of the same table (src_field 1).
   Never published as RX. */
#define V2_ACCUM_LEARN(name, src_field)                                    \
STENCIL_NOVEC(name)(Lua55NativeFrameV2 *frame)                              \
{                                                                           \
    V2_HOLE32(field_receiver_reg, V2_FIELD_RECEIVER_HOLE);                  \
    V2_HOLE32(table_receiver_reg, V2_RECEIVER_HOLE);                        \
    V2_HOLE32(source_reg, V2_SOURCE_HOLE);                                  \
    V2_HOLE32(k1_reg, V2_KEY_REG_HOLE);                                     \
    V2_HOLE32(k2_reg, V2_ACCUM_KEY2_HOLE);                                  \
    V2_HOLE32(v_reg, V2_TARGET_HOLE);                                       \
    uint64_t field_key = (uint64_t)V2_KEY_REF_HOLE;                         \
    __asm__ volatile ("" : "+r"(field_key));                              \
    V2_LEARN_SLOT()                                                          \
    Lua55ValueV2 *field_receiver = &frame->values[field_receiver_reg];       \
    Lua55GuestTableV2 *ftable = v2_learn_table(frame, field_receiver);       \
    if (ftable == 0) V2_TABLE_REJECT(frame, LUA55_V2_REJECT_INVALID_OBJECT);\
    Lua55ValueV2 *key_cell = v2_find_field(ftable, (uintptr_t)field_key, 0);\
    if (key_cell == 0) { V2_REJECT(frame, LUA55_V2_REJECT_UNSUPPORTED_METAMETHOD); \
                        LUA55_CPS_HOST_EXIT(frame); }                        \
    Lua55ValueV2 *table_receiver = &frame->values[table_receiver_reg];       \
    Lua55GuestTableV2 *table = v2_learn_table(frame, table_receiver);        \
    if (table == 0) V2_TABLE_REJECT(frame, LUA55_V2_REJECT_INVALID_OBJECT);  \
    Lua55ValueV2 *cell = 0;                                                  \
    uint32_t key_shape = key_cell->tag;                                      \
    if (key_cell->tag == LUA55_VALUE_INTEGER)                                \
        cell = v2_array_slot(table, key_cell->payload.integer);              \
    else if (v2_is_string_tag(key_cell->tag)) {                              \
        key_shape = LUA55_VALUE_SHORT_STRING;                                \
        cell = v2_find_field(table, key_cell->payload.reference, 0);         \
    } else {                                                                 \
        V2_REJECT(frame, LUA55_V2_REJECT_UNSUPPORTED_METAMETHOD);            \
        LUA55_CPS_HOST_EXIT(frame);                                          \
    }                                                                        \
    if (cell == 0 || (cell->tag != LUA55_VALUE_INTEGER                      \
        && cell->tag != LUA55_VALUE_FLOAT)) {                                \
        V2_REJECT(frame, LUA55_V2_REJECT_UNSUPPORTED_METAMETHOD);            \
        LUA55_CPS_HOST_EXIT(frame);                                          \
    }                                                                        \
    Lua55ValueV2 *source;                                                    \
    if (src_field) {                                                         \
        uint64_t source_key = (uint64_t)V2_SOURCE_KEY_REF_HOLE;              \
        __asm__ volatile ("" : "+r"(source_key));                         \
        Lua55ValueV2 *source_cell = v2_find_field(ftable,                    \
            (uintptr_t)source_key, 0);                                       \
        if (source_cell == 0 || (source_cell->tag != LUA55_VALUE_INTEGER    \
            && source_cell->tag != LUA55_VALUE_FLOAT)) {                     \
            V2_REJECT(frame, LUA55_V2_REJECT_UNSUPPORTED_METAMETHOD);        \
            LUA55_CPS_HOST_EXIT(frame);                                      \
        }                                                                    \
        source = source_cell;                                                \
        frame->values[source_reg] = *source_cell;                            \
    } else {                                                                 \
        source = &frame->values[source_reg];                                 \
        if (source->tag != LUA55_VALUE_INTEGER                               \
            && source->tag != LUA55_VALUE_FLOAT) {                           \
            V2_REJECT(frame, LUA55_V2_REJECT_UNSUPPORTED_METAMETHOD);        \
            LUA55_CPS_HOST_EXIT(frame);                                      \
        }                                                                    \
    }                                                                        \
    v2_learn_accum(frame, slot, key_shape, cell->tag, source->tag);          \
    if (cell->tag == LUA55_VALUE_INTEGER) {                                  \
        if (source->tag == LUA55_VALUE_INTEGER)                              \
            cell->payload.integer = v2_int_add(cell->payload.integer,        \
                source->payload.integer);                                    \
        else {                                                               \
            double acc = (double)cell->payload.integer + source->payload.floating; \
            SET_TAG(cell, LUA55_VALUE_FLOAT); cell->payload.floating = acc;  \
        }                                                                    \
    } else {                                                                 \
        double acc = cell->payload.floating;                                 \
        acc += (source->tag == LUA55_VALUE_INTEGER)                           \
            ? (double)source->payload.integer : source->payload.floating;    \
        cell->payload.floating = acc;                                        \
    }                                                                        \
    frame->values[k1_reg] = *key_cell;                                       \
    frame->values[k2_reg] = *key_cell;                                       \
    frame->values[v_reg] = *cell;                                            \
    LUA55_RESIDUAL_NEXT(frame);                                              \
}

V2_ACCUM_LEARN(lua55_v2l_super_accumulate_field, 0)
V2_ACCUM_LEARN(lua55_v2l_super_accumulate_field_field, 1)

#define V2_SUPER_FOR_ADDI(name, init_tag, limit_tag, step_tag, acc_tag, pos, int_proto) \
STENCIL(name)(Lua55NativeFrameV2 *frame)                                    \
{                                                                           \
    V2_HOLE32(A, V2_BASE_INDEX_HOLE);                                       \
    V2_HOLE32(accumulator_index, V2_TARGET_HOLE);                            \
    uint64_t imm_bits = V2_INT_IMM_HOLE;                                    \
    __asm__ volatile ("" : "+r"(imm_bits));                               \
    int64_t imm = (int64_t)imm_bits;                                        \
    Lua55ValueV2 *init = &frame->values[A];                                 \
    Lua55ValueV2 *limit = &frame->values[A + 1];                            \
    Lua55ValueV2 *step = &frame->values[A + 2];                             \
    Lua55ValueV2 *accumulator = &frame->values[accumulator_index];           \
    V2_LEAF_GUARD(frame, init, init_tag);                                    \
    V2_LEAF_GUARD(frame, limit, limit_tag);                                  \
    V2_LEAF_GUARD(frame, step, step_tag);                                    \
    V2_LEAF_GUARD(frame, accumulator, acc_tag);                              \
    if (int_proto) {                                                         \
        int64_t iv = init->payload.integer;                                  \
        int64_t lv = limit->payload.integer;                                 \
        int64_t sv = step->payload.integer;                                  \
        if ((pos && sv <= 0) || (!(pos) && sv >= 0)) {                       \
            V2_SPEC_MISMATCH(frame, (pos), sv > 0 ? 1 : 0);                  \
            V2_SPECIALIZATION_MISMATCH_EXIT(frame); }                                    \
        if (sv == 0) { V2_REJECT(frame, LUA55_V2_REJECT_STEP_ZERO);          \
                       LUA55_CPS_HOST_EXIT(frame); }                          \
        if (!((pos && iv > lv) || (!(pos) && iv < lv))) {                    \
            uint64_t distance = (pos) ? (uint64_t)lv - (uint64_t)iv         \
                : (uint64_t)iv - (uint64_t)lv;                              \
            uint64_t stride = (pos) ? (uint64_t)sv                          \
                : UINT64_C(0) - (uint64_t)sv;                               \
            int64_t count = (int64_t)(distance / stride);                    \
            int64_t av_i = 0; double av_f = 0.0;                            \
            if ((acc_tag) == LUA55_VALUE_INTEGER) av_i = accumulator->payload.integer; \
            else av_f = accumulator->payload.floating;                      \
            for (;;) {                                                       \
                if ((acc_tag) == LUA55_VALUE_INTEGER) av_i = v2_int_add(av_i, imm); \
                else av_f += (double)imm;                                   \
                if (count <= 0) break;                                      \
                count--; iv = v2_int_add(iv, sv);                           \
            }                                                               \
            SET_TAG(init, LUA55_VALUE_INTEGER); init->payload.integer = count; \
            SET_TAG(limit, LUA55_VALUE_INTEGER); limit->payload.integer = sv; \
            SET_TAG(step, LUA55_VALUE_INTEGER); step->payload.integer = iv;  \
            if ((acc_tag) == LUA55_VALUE_INTEGER) accumulator->payload.integer = av_i; \
            else accumulator->payload.floating = av_f;                      \
        }                                                                   \
    } else {                                                                \
        double iv = (init_tag) == LUA55_VALUE_INTEGER                       \
            ? (double)init->payload.integer : init->payload.floating;        \
        double lv = (limit_tag) == LUA55_VALUE_INTEGER                      \
            ? (double)limit->payload.integer : limit->payload.floating;      \
        double sv = (step_tag) == LUA55_VALUE_INTEGER                       \
            ? (double)step->payload.integer : step->payload.floating;        \
        if ((pos && sv <= 0.0) || (!(pos) && sv >= 0.0)) {                   \
            V2_SPEC_MISMATCH(frame, (pos), sv > 0.0 ? 1 : 0);                \
            V2_SPECIALIZATION_MISMATCH_EXIT(frame); }                                    \
        if (sv == 0.0) { V2_REJECT(frame, LUA55_V2_REJECT_STEP_ZERO);        \
                         LUA55_CPS_HOST_EXIT(frame); }                        \
        if (!((pos && lv < iv) || (!(pos) && iv < lv))) {                    \
            int64_t av_i = 0; double av_f = 0.0;                            \
            if ((acc_tag) == LUA55_VALUE_INTEGER) av_i = accumulator->payload.integer; \
            else av_f = accumulator->payload.floating;                      \
            for (;;) {                                                       \
                if ((acc_tag) == LUA55_VALUE_INTEGER) av_i = v2_int_add(av_i, imm); \
                else av_f += (double)imm;                                   \
                double next = iv + sv;                                      \
                if (!((pos && next <= lv) || (!(pos) && lv <= next))) break; \
                iv = next;                                                   \
            }                                                               \
            SET_TAG(init, LUA55_VALUE_FLOAT); init->payload.floating = lv;   \
            SET_TAG(limit, LUA55_VALUE_FLOAT); limit->payload.floating = sv; \
            SET_TAG(step, LUA55_VALUE_FLOAT); step->payload.floating = iv;   \
            if ((acc_tag) == LUA55_VALUE_INTEGER) accumulator->payload.integer = av_i; \
            else accumulator->payload.floating = av_f;                      \
        }                                                                   \
    }                                                                       \
    uintptr_t skip = (uintptr_t)V2_SKIP_HOLE;                               \
    __asm__ volatile ("" : "+r"(skip));                                   \
    return ((Lua55NativeEntryV2)skip)(frame);                               \
}

#define V2_SUPER_FOR_ADDI_SHAPE(bits, init_tag, limit_tag, step_tag, int_proto) \
    V2_SUPER_FOR_ADDI(lua55_v2r_super_for_addi_##bits##_i_pos, init_tag, limit_tag, step_tag, LUA55_VALUE_INTEGER, 1, int_proto) \
    V2_SUPER_FOR_ADDI(lua55_v2r_super_for_addi_##bits##_i_neg, init_tag, limit_tag, step_tag, LUA55_VALUE_INTEGER, 0, int_proto) \
    V2_SUPER_FOR_ADDI(lua55_v2r_super_for_addi_##bits##_f_pos, init_tag, limit_tag, step_tag, LUA55_VALUE_FLOAT, 1, int_proto) \
    V2_SUPER_FOR_ADDI(lua55_v2r_super_for_addi_##bits##_f_neg, init_tag, limit_tag, step_tag, LUA55_VALUE_FLOAT, 0, int_proto)

V2_SUPER_FOR_ADDI_SHAPE(iii, LUA55_VALUE_INTEGER, LUA55_VALUE_INTEGER, LUA55_VALUE_INTEGER, 1)
V2_SUPER_FOR_ADDI_SHAPE(iif, LUA55_VALUE_INTEGER, LUA55_VALUE_INTEGER, LUA55_VALUE_FLOAT, 0)
V2_SUPER_FOR_ADDI_SHAPE(ifi, LUA55_VALUE_INTEGER, LUA55_VALUE_FLOAT, LUA55_VALUE_INTEGER, 0)
V2_SUPER_FOR_ADDI_SHAPE(iff, LUA55_VALUE_INTEGER, LUA55_VALUE_FLOAT, LUA55_VALUE_FLOAT, 0)
V2_SUPER_FOR_ADDI_SHAPE(fii, LUA55_VALUE_FLOAT, LUA55_VALUE_INTEGER, LUA55_VALUE_INTEGER, 0)
V2_SUPER_FOR_ADDI_SHAPE(fif, LUA55_VALUE_FLOAT, LUA55_VALUE_INTEGER, LUA55_VALUE_FLOAT, 0)
V2_SUPER_FOR_ADDI_SHAPE(ffi, LUA55_VALUE_FLOAT, LUA55_VALUE_FLOAT, LUA55_VALUE_INTEGER, 0)
V2_SUPER_FOR_ADDI_SHAPE(fff, LUA55_VALUE_FLOAT, LUA55_VALUE_FLOAT, LUA55_VALUE_FLOAT, 0)

#define V2_SUPER_FOR_ADD(name, init_tag, limit_tag, step_tag, acc_tag, pos, int_proto) \
STENCIL_NOVEC(name)(Lua55NativeFrameV2 *frame)                              \
{                                                                           \
    V2_HOLE32(A, V2_BASE_INDEX_HOLE);                                       \
    V2_HOLE32(accumulator_index, V2_TARGET_HOLE);                            \
    Lua55ValueV2 *init = &frame->values[A];                                 \
    Lua55ValueV2 *limit = &frame->values[A + 1];                            \
    Lua55ValueV2 *step = &frame->values[A + 2];                             \
    Lua55ValueV2 *accumulator = &frame->values[accumulator_index];           \
    V2_LEAF_GUARD(frame, init, init_tag); V2_LEAF_GUARD(frame, limit, limit_tag); \
    V2_LEAF_GUARD(frame, step, step_tag); V2_LEAF_GUARD(frame, accumulator, acc_tag); \
    if (int_proto) {                                                         \
        int64_t iv = init->payload.integer, lv = limit->payload.integer;     \
        int64_t sv = step->payload.integer;                                  \
        if ((pos && sv <= 0) || (!(pos) && sv >= 0)) {                       \
            V2_SPEC_MISMATCH(frame, (pos), sv > 0 ? 1 : 0); V2_SPECIALIZATION_MISMATCH_EXIT(frame); } \
        if (sv == 0) { V2_REJECT(frame, LUA55_V2_REJECT_STEP_ZERO); LUA55_CPS_HOST_EXIT(frame); } \
        if (!((pos && iv > lv) || (!(pos) && iv < lv))) {                    \
            uint64_t distance = (pos) ? (uint64_t)lv - (uint64_t)iv         \
                : (uint64_t)iv - (uint64_t)lv;                              \
            uint64_t stride = (pos) ? (uint64_t)sv : UINT64_C(0) - (uint64_t)sv; \
            int64_t count = (int64_t)(distance / stride);                    \
            int64_t av_i = 0; double av_f = 0.0;                            \
            if ((acc_tag) == LUA55_VALUE_INTEGER) av_i = accumulator->payload.integer; \
            else av_f = accumulator->payload.floating;                      \
            for (;;) {                                                       \
                if ((acc_tag) == LUA55_VALUE_INTEGER) av_i = v2_int_add(av_i, iv); \
                else av_f += (double)iv;                                    \
                if (count <= 0) break; count--; iv = v2_int_add(iv, sv);     \
            }                                                               \
            SET_TAG(init, LUA55_VALUE_INTEGER); init->payload.integer = count; \
            SET_TAG(limit, LUA55_VALUE_INTEGER); limit->payload.integer = sv; \
            SET_TAG(step, LUA55_VALUE_INTEGER); step->payload.integer = iv;  \
            if ((acc_tag) == LUA55_VALUE_INTEGER) accumulator->payload.integer = av_i; \
            else accumulator->payload.floating = av_f;                      \
        }                                                                   \
    } else {                                                                \
        double iv = (init_tag) == LUA55_VALUE_INTEGER ? (double)init->payload.integer : init->payload.floating; \
        double lv = (limit_tag) == LUA55_VALUE_INTEGER ? (double)limit->payload.integer : limit->payload.floating; \
        double sv = (step_tag) == LUA55_VALUE_INTEGER ? (double)step->payload.integer : step->payload.floating; \
        if ((pos && sv <= 0.0) || (!(pos) && sv >= 0.0)) {                   \
            V2_SPEC_MISMATCH(frame, (pos), sv > 0.0 ? 1 : 0); V2_SPECIALIZATION_MISMATCH_EXIT(frame); } \
        if (sv == 0.0) { V2_REJECT(frame, LUA55_V2_REJECT_STEP_ZERO); LUA55_CPS_HOST_EXIT(frame); } \
        if (!((pos && lv < iv) || (!(pos) && iv < lv))) {                    \
            double av = (acc_tag) == LUA55_VALUE_INTEGER ? (double)accumulator->payload.integer \
                : accumulator->payload.floating;                            \
            for (;;) { av += iv; double next = iv + sv;                     \
                if (!((pos && next <= lv) || (!(pos) && lv <= next))) break; \
                iv = next; }                                                \
            SET_TAG(accumulator, LUA55_VALUE_FLOAT); accumulator->payload.floating = av; \
            SET_TAG(init, LUA55_VALUE_FLOAT); init->payload.floating = lv;   \
            SET_TAG(limit, LUA55_VALUE_FLOAT); limit->payload.floating = sv; \
            SET_TAG(step, LUA55_VALUE_FLOAT); step->payload.floating = iv;   \
        }                                                                   \
    }                                                                       \
    uintptr_t skip = (uintptr_t)V2_SKIP_HOLE; __asm__ volatile ("" : "+r"(skip)); \
    return ((Lua55NativeEntryV2)skip)(frame);                               \
}

#define V2_SUPER_FOR_ADD_SHAPE(bits, init_tag, limit_tag, step_tag, int_proto) \
    V2_SUPER_FOR_ADD(lua55_v2r_super_for_add_##bits##_i_pos, init_tag, limit_tag, step_tag, LUA55_VALUE_INTEGER, 1, int_proto) \
    V2_SUPER_FOR_ADD(lua55_v2r_super_for_add_##bits##_i_neg, init_tag, limit_tag, step_tag, LUA55_VALUE_INTEGER, 0, int_proto) \
    V2_SUPER_FOR_ADD(lua55_v2r_super_for_add_##bits##_f_pos, init_tag, limit_tag, step_tag, LUA55_VALUE_FLOAT, 1, int_proto) \
    V2_SUPER_FOR_ADD(lua55_v2r_super_for_add_##bits##_f_neg, init_tag, limit_tag, step_tag, LUA55_VALUE_FLOAT, 0, int_proto)

V2_SUPER_FOR_ADD_SHAPE(iii, LUA55_VALUE_INTEGER, LUA55_VALUE_INTEGER, LUA55_VALUE_INTEGER, 1)
V2_SUPER_FOR_ADD_SHAPE(iif, LUA55_VALUE_INTEGER, LUA55_VALUE_INTEGER, LUA55_VALUE_FLOAT, 0)
V2_SUPER_FOR_ADD_SHAPE(ifi, LUA55_VALUE_INTEGER, LUA55_VALUE_FLOAT, LUA55_VALUE_INTEGER, 0)
V2_SUPER_FOR_ADD_SHAPE(iff, LUA55_VALUE_INTEGER, LUA55_VALUE_FLOAT, LUA55_VALUE_FLOAT, 0)
V2_SUPER_FOR_ADD_SHAPE(fii, LUA55_VALUE_FLOAT, LUA55_VALUE_INTEGER, LUA55_VALUE_INTEGER, 0)
V2_SUPER_FOR_ADD_SHAPE(fif, LUA55_VALUE_FLOAT, LUA55_VALUE_INTEGER, LUA55_VALUE_FLOAT, 0)
V2_SUPER_FOR_ADD_SHAPE(ffi, LUA55_VALUE_FLOAT, LUA55_VALUE_FLOAT, LUA55_VALUE_INTEGER, 0)
V2_SUPER_FOR_ADD_SHAPE(fff, LUA55_VALUE_FLOAT, LUA55_VALUE_FLOAT, LUA55_VALUE_FLOAT, 0)
/* Exact fused numeric-for SETTABLE cycle residuals. One leaf per const kind
   and sign; the count/index/step stay register-resident and the table store
   runs once per iteration. Growth is a bounded inline branch on capacity
   (program data); the learned NEWTABLE capacity floor keeps it cold. */
#define V2_SUPER_FOR_SETTABLE(name, pos, store)                             \
STENCIL_NOVEC(name)(Lua55NativeFrameV2 *frame)                              \
{                                                                           \
    V2_HOLE32(A, V2_BASE_INDEX_HOLE);                                       \
    V2_HOLE32(receiver_reg, V2_RECEIVER_HOLE);                              \
    Lua55ValueV2 *init = &frame->values[A];                                 \
    Lua55ValueV2 *limit = &frame->values[A + 1];                            \
    Lua55ValueV2 *step = &frame->values[A + 2];                             \
    V2_LEAF_GUARD(frame, init, LUA55_VALUE_INTEGER);                        \
    V2_LEAF_GUARD(frame, limit, LUA55_VALUE_INTEGER);                       \
    V2_LEAF_GUARD(frame, step, LUA55_VALUE_INTEGER);                        \
    int64_t iv = init->payload.integer, lv = limit->payload.integer;        \
    int64_t sv = step->payload.integer;                                     \
    if ((pos && sv <= 0) || (!(pos) && sv >= 0)) {                          \
        V2_SPEC_MISMATCH(frame, (pos), sv > 0 ? 1 : 0);                     \
        V2_SPECIALIZATION_MISMATCH_EXIT(frame); }                                        \
    if (sv == 0) { V2_REJECT(frame, LUA55_V2_REJECT_STEP_ZERO);             \
                   LUA55_CPS_HOST_EXIT(frame); }                             \
    Lua55ValueV2 *receiver = &frame->values[receiver_reg];                  \
    V2_SUPER_GUARD(receiver, LUA55_VALUE_TABLE);                            \
    Lua55GuestTableV2 *table =                                              \
        (Lua55GuestTableV2 *)receiver->payload.reference;                   \
    if (table == 0 || table->header.kind != LUA55_OBJECT_TABLE             \
        || table->heap != frame->invocation->heap                          \
        || table->metatable_reference != 0) {                               \
        V2_SPEC_MISMATCH(frame, LUA55_OBJECT_TABLE,                         \
            table != 0 ? table->header.kind : 0);                           \
        V2_SPECIALIZATION_MISMATCH_EXIT(frame); }                                        \
    uintptr_t skip = (uintptr_t)V2_SKIP_HOLE;                               \
    if (!((pos && iv > lv) || (!(pos) && iv < lv))) {                       \
        uint64_t distance = (pos) ? (uint64_t)lv - (uint64_t)iv            \
            : (uint64_t)iv - (uint64_t)lv;                                  \
        uint64_t stride = (pos) ? (uint64_t)sv : UINT64_C(0) - (uint64_t)sv; \
        int64_t count = (int64_t)(distance / stride);                        \
        for (;;) {                                                           \
            Lua55ValueV2 *cell = v2_array_slot(table, iv);                   \
            if (cell == 0) {                                                 \
                if (iv >= 1 && v2_grow_array(frame, table, (uint64_t)iv))    \
                    cell = v2_array_slot(table, iv);                         \
                else { V2_REJECT(frame, LUA55_V2_REJECT_INVALID_OBJECT);     \
                       LUA55_CPS_HOST_EXIT(frame); }                         \
            }                                                                \
            store(cell);                                                     \
            if (count <= 0) break;                                           \
            count--; iv = v2_int_add(iv, sv);                                \
        }                                                                    \
        SET_TAG(init, LUA55_VALUE_INTEGER); init->payload.integer = count;   \
        SET_TAG(limit, LUA55_VALUE_INTEGER); limit->payload.integer = sv;    \
        SET_TAG(step, LUA55_VALUE_INTEGER); step->payload.integer = iv;      \
    }                                                                        \
    __asm__ volatile ("" : "+r"(skip));                                     \
    return ((Lua55NativeEntryV2)skip)(frame);                                \
}

V2_SUPER_FOR_SETTABLE(lua55_v2r_super_for_settable_nil_pos, 1, V2_STORE_NIL)
V2_SUPER_FOR_SETTABLE(lua55_v2r_super_for_settable_nil_neg, 0, V2_STORE_NIL)
V2_SUPER_FOR_SETTABLE(lua55_v2r_super_for_settable_false_pos, 1, V2_STORE_FALSE)
V2_SUPER_FOR_SETTABLE(lua55_v2r_super_for_settable_false_neg, 0, V2_STORE_FALSE)
V2_SUPER_FOR_SETTABLE(lua55_v2r_super_for_settable_true_pos, 1, V2_STORE_TRUE)
V2_SUPER_FOR_SETTABLE(lua55_v2r_super_for_settable_true_neg, 0, V2_STORE_TRUE)
V2_SUPER_FOR_SETTABLE(lua55_v2r_super_for_settable_int_pos, 1, V2_STORE_INT)
V2_SUPER_FOR_SETTABLE(lua55_v2r_super_for_settable_int_neg, 0, V2_STORE_INT)
V2_SUPER_FOR_SETTABLE(lua55_v2r_super_for_settable_flt_pos, 1, V2_STORE_FLT)
V2_SUPER_FOR_SETTABLE(lua55_v2r_super_for_settable_flt_neg, 0, V2_STORE_FLT)
V2_SUPER_FOR_SETTABLE(lua55_v2r_super_for_settable_str_pos, 1, V2_STORE_STR)
V2_SUPER_FOR_SETTABLE(lua55_v2r_super_for_settable_str_neg, 0, V2_STORE_STR)

/* Exact fused five-leaf dictionary accumulation residuals: the key is read
   once from the field table and used for both the GETTABLE and the
   SETTABLE. One leaf per key/accumulator/source kind triple; the arithmetic
   is baked, so no runtime operand classification remains. */
#define V2_ACCUM_FIELD(name, key_is_int, acc_is_int, src_is_int, src_field) \
STENCIL_NOVEC(name)(Lua55NativeFrameV2 *frame)                              \
{                                                                           \
    V2_HOLE32(field_receiver_reg, V2_FIELD_RECEIVER_HOLE);                  \
    V2_HOLE32(table_receiver_reg, V2_RECEIVER_HOLE);                        \
    V2_HOLE32(source_reg, V2_SOURCE_HOLE);                                  \
    V2_HOLE32(k1_reg, V2_KEY_REG_HOLE);                                     \
    V2_HOLE32(k2_reg, V2_ACCUM_KEY2_HOLE);                                  \
    V2_HOLE32(v_reg, V2_TARGET_HOLE);                                       \
    uint64_t field_key = (uint64_t)V2_KEY_REF_HOLE;                         \
    __asm__ volatile ("" : "+r"(field_key));                              \
    Lua55ValueV2 *field_receiver = &frame->values[field_receiver_reg];       \
    V2_SUPER_GUARD(field_receiver, LUA55_VALUE_TABLE);                       \
    Lua55GuestTableV2 *ftable =                                              \
        (Lua55GuestTableV2 *)field_receiver->payload.reference;              \
    if (ftable == 0 || ftable->header.kind != LUA55_OBJECT_TABLE            \
        || ftable->heap != frame->invocation->heap                           \
        || ftable->metatable_reference != 0) {                               \
        V2_SPEC_MISMATCH(frame, LUA55_OBJECT_TABLE,                          \
            ftable != 0 ? ftable->header.kind : 0);                          \
        V2_SPECIALIZATION_MISMATCH_EXIT(frame); }                                        \
    Lua55ValueV2 *key_cell = v2_find_field(ftable, (uintptr_t)field_key, 0);\
    if (key_cell == 0) {                                                     \
        V2_SPEC_MISMATCH(frame, LUA55_VALUE_INTEGER, LUA55_VALUE_NIL);       \
        V2_SPECIALIZATION_MISMATCH_EXIT(frame); }                                        \
    if (key_is_int) V2_SUPER_GUARD(key_cell, LUA55_VALUE_INTEGER);           \
    else if (!v2_is_string_tag(key_cell->tag)) {                            \
        V2_SPEC_MISMATCH(frame, LUA55_VALUE_SHORT_STRING, key_cell->tag);    \
        V2_SPECIALIZATION_MISMATCH_EXIT(frame); }                                        \
    Lua55ValueV2 *table_receiver = &frame->values[table_receiver_reg];       \
    V2_SUPER_GUARD(table_receiver, LUA55_VALUE_TABLE);                       \
    Lua55GuestTableV2 *table =                                               \
        (Lua55GuestTableV2 *)table_receiver->payload.reference;              \
    if (table == 0 || table->header.kind != LUA55_OBJECT_TABLE              \
        || table->heap != frame->invocation->heap                            \
        || table->metatable_reference != 0) {                                \
        V2_SPEC_MISMATCH(frame, LUA55_OBJECT_TABLE,                          \
            table != 0 ? table->header.kind : 0);                            \
        V2_SPECIALIZATION_MISMATCH_EXIT(frame); }                                        \
    Lua55ValueV2 *cell;                                                      \
    if (key_is_int) cell = v2_array_slot(table, key_cell->payload.integer);  \
    else cell = v2_find_field(table, key_cell->payload.reference, 0);        \
    if (cell == 0) {                                                         \
        V2_SPEC_MISMATCH(frame, (acc_is_int) ? LUA55_VALUE_INTEGER           \
            : LUA55_VALUE_FLOAT, LUA55_VALUE_NIL);                           \
        V2_SPECIALIZATION_MISMATCH_EXIT(frame); }                                        \
    if (acc_is_int) V2_SUPER_GUARD(cell, LUA55_VALUE_INTEGER);               \
    else V2_SUPER_GUARD(cell, LUA55_VALUE_FLOAT);                            \
    Lua55ValueV2 *source;                                                   \
    if (src_field) {                                                        \
        uint64_t source_key = (uint64_t)V2_SOURCE_KEY_REF_HOLE;             \
        __asm__ volatile ("" : "+r"(source_key));                        \
        Lua55ValueV2 *source_cell = v2_find_field(ftable,                   \
            (uintptr_t)source_key, 0);                                      \
        if (source_cell == 0) {                                              \
            V2_SPEC_MISMATCH(frame, (src_is_int) ? LUA55_VALUE_INTEGER      \
                : LUA55_VALUE_FLOAT, LUA55_VALUE_NIL);                      \
            V2_SPECIALIZATION_MISMATCH_EXIT(frame); }                                    \
        if (src_is_int) V2_SUPER_GUARD(source_cell, LUA55_VALUE_INTEGER);   \
        else V2_SUPER_GUARD(source_cell, LUA55_VALUE_FLOAT);                \
        source = source_cell;                                                \
        frame->values[source_reg] = *source_cell;                            \
    } else {                                                                 \
        source = &frame->values[source_reg];                                \
        if (src_is_int) V2_SUPER_GUARD(source, LUA55_VALUE_INTEGER);        \
        else V2_SUPER_GUARD(source, LUA55_VALUE_FLOAT);                      \
    }                                                                        \
    if (acc_is_int && src_is_int)                                           \
        cell->payload.integer = v2_int_add(cell->payload.integer,            \
            source->payload.integer);                                        \
    else {                                                                   \
        double acc = (acc_is_int) ? (double)cell->payload.integer            \
            : cell->payload.floating;                                        \
        double s = (src_is_int) ? (double)source->payload.integer            \
            : source->payload.floating;                                      \
        acc = acc + s;                                                       \
        SET_TAG(cell, LUA55_VALUE_FLOAT); cell->payload.floating = acc;      \
    }                                                                        \
    frame->values[k1_reg] = *key_cell;                                       \
    frame->values[k2_reg] = *key_cell;                                       \
    frame->values[v_reg] = *cell;                                            \
    LUA55_RESIDUAL_NEXT(frame);                                              \
}

V2_ACCUM_FIELD(lua55_v2r_super_accumulate_field_r_int_int_int, 1, 1, 1, 0)
V2_ACCUM_FIELD(lua55_v2r_super_accumulate_field_r_int_int_flt, 1, 1, 0, 0)
V2_ACCUM_FIELD(lua55_v2r_super_accumulate_field_r_int_flt_int, 1, 0, 1, 0)
V2_ACCUM_FIELD(lua55_v2r_super_accumulate_field_r_int_flt_flt, 1, 0, 0, 0)
V2_ACCUM_FIELD(lua55_v2r_super_accumulate_field_r_str_int_int, 0, 1, 1, 0)
V2_ACCUM_FIELD(lua55_v2r_super_accumulate_field_r_str_int_flt, 0, 1, 0, 0)
V2_ACCUM_FIELD(lua55_v2r_super_accumulate_field_r_str_flt_int, 0, 0, 1, 0)
V2_ACCUM_FIELD(lua55_v2r_super_accumulate_field_r_str_flt_flt, 0, 0, 0, 0)
V2_ACCUM_FIELD(lua55_v2r_super_accumulate_field_f_int_int_int, 1, 1, 1, 1)
V2_ACCUM_FIELD(lua55_v2r_super_accumulate_field_f_int_int_flt, 1, 1, 0, 1)
V2_ACCUM_FIELD(lua55_v2r_super_accumulate_field_f_int_flt_int, 1, 0, 1, 1)
V2_ACCUM_FIELD(lua55_v2r_super_accumulate_field_f_int_flt_flt, 1, 0, 0, 1)
V2_ACCUM_FIELD(lua55_v2r_super_accumulate_field_f_str_int_int, 0, 1, 1, 1)
V2_ACCUM_FIELD(lua55_v2r_super_accumulate_field_f_str_int_flt, 0, 1, 0, 1)
V2_ACCUM_FIELD(lua55_v2r_super_accumulate_field_f_str_flt_int, 0, 0, 1, 1)
V2_ACCUM_FIELD(lua55_v2r_super_accumulate_field_f_str_flt_flt, 0, 0, 0, 1)

/* ======================================================================= */
/* Batch 5: exact call-site leaves                                          */
/* ------------------------------------------------------------------------ */
/* The learning invocation observes each call site's callee class (native   */
/* closure / host builtin / other) and the native callee's vararg flag.     */
/* The residual selects exact leaves: native-fixed (no vararg slice),       */
/* native-vararg (slice count is data), or host suspension. A changed       */
/* callee shape publishes a typed specialization rejection.                 */
/* ======================================================================= */

#define V2_CALL_GUARD_NATIVE_CELL(frame, callee, closure, desc, entry, is_varg) do { \
    if (callee->tag != LUA55_VALUE_CLOSURE) {                                \
        V2_SPEC_MISMATCH(frame, LUA55_VALUE_CLOSURE, callee->tag);           \
        V2_SPECIALIZATION_MISMATCH_EXIT(frame); }                                        \
    closure = (Lua55NativeClosureV2 *)callee->payload.reference;             \
    if (closure == 0 || closure->header.kind != LUA55_OBJECT_CLOSURE) {      \
        V2_SPEC_MISMATCH(frame, LUA55_OBJECT_CLOSURE,                        \
            closure != 0 ? closure->header.kind : 0);                        \
        V2_SPECIALIZATION_MISMATCH_EXIT(frame); }                                        \
    if (closure->proto_index >= frame->invocation->function_count) {         \
        V2_SPEC_MISMATCH(frame, 0, 0); V2_SPECIALIZATION_MISMATCH_EXIT(frame); }         \
    desc = &frame->invocation->functions[closure->proto_index];              \
    entry = desc->entry;                                                     \
    if (entry == 0) { V2_SPEC_MISMATCH(frame, 0, 0);                         \
                      V2_SPECIALIZATION_MISMATCH_EXIT(frame); }                          \
    if (desc->is_vararg != (is_varg)) {                                     \
        V2_SPEC_MISMATCH(frame, (uint32_t)(is_varg), desc->is_vararg);       \
        V2_SPECIALIZATION_MISMATCH_EXIT(frame); }                                        \
} while (0)
#define V2_CALL_GUARD_NATIVE(frame, A, callee, closure, desc, entry, is_varg) do { \
    callee = &frame->values[A];                                              \
    V2_CALL_GUARD_NATIVE_CELL(frame, callee, closure, desc, entry, is_varg); \
} while (0)

#define V2_CALL_GUARD_BUILTIN_CELL(frame, callee, closure) do {              \
    if (callee->tag != LUA55_VALUE_CLOSURE) {                                \
        V2_SPEC_MISMATCH(frame, LUA55_VALUE_CLOSURE, callee->tag);           \
        V2_SPECIALIZATION_MISMATCH_EXIT(frame); }                                        \
    closure = (Lua55NativeClosureV2 *)callee->payload.reference;             \
    if (closure == 0 || closure->header.kind != LUA55_OBJECT_BUILTIN) {      \
        V2_SPEC_MISMATCH(frame, LUA55_OBJECT_BUILTIN,                        \
            closure != 0 ? closure->header.kind : 0);                        \
        V2_SPECIALIZATION_MISMATCH_EXIT(frame); }                                        \
} while (0)
#define V2_CALL_GUARD_BUILTIN(frame, A, callee, closure) do {                \
    callee = &frame->values[A];                                              \
    V2_CALL_GUARD_BUILTIN_CELL(frame, callee, closure);                      \
} while (0)

#define V2_NO_CALL_PRELUDE() do { } while (0)
#define V2_SUPER_GLOBAL_FETCH() do {                                        \
    V2_HOLE32(global_upvalue, V2_UPVALUE_HOLE);                              \
    uint64_t global_key = (uint64_t)V2_KEY_REF_HOLE;                        \
    __asm__ volatile ("" : "+r"(global_key));                             \
    Lua55UpvalueCellV2 *global_cell = frame->upvalues[global_upvalue];       \
    Lua55ValueV2 *global_env = global_cell->state == LUA55_UPVALUE_OPEN      \
        ? global_cell->open_slot : &global_cell->closed_value;              \
    V2_SUPER_GUARD(global_env, LUA55_VALUE_TABLE);                           \
    Lua55GuestTableV2 *global_table =                                       \
        (Lua55GuestTableV2 *)global_env->payload.reference;                  \
    if (global_table == 0 || global_table->header.kind != LUA55_OBJECT_TABLE \
        || global_table->heap != frame->invocation->heap                    \
        || global_table->metatable_reference != 0) {                        \
        V2_SPEC_MISMATCH(frame, LUA55_OBJECT_TABLE,                         \
            global_table != 0 ? global_table->header.kind : 0);             \
        V2_SPECIALIZATION_MISMATCH_EXIT(frame); }                                        \
    Lua55ValueV2 *global_value = v2_find_field(                              \
        global_table, (uintptr_t)global_key, 0);                             \
    if (global_value == 0) SET_TAG(&frame->values[A], LUA55_VALUE_NIL);     \
    else frame->values[A] = *global_value;                                  \
} while (0)

#define V2_SUPER_GLOBAL_NIL() do { V2_SUPER_GLOBAL_FETCH(); V2_STORE_NIL(&frame->values[A + 1]); } while (0)
#define V2_SUPER_GLOBAL_FALSE() do { V2_SUPER_GLOBAL_FETCH(); V2_STORE_FALSE(&frame->values[A + 1]); } while (0)
#define V2_SUPER_GLOBAL_TRUE() do { V2_SUPER_GLOBAL_FETCH(); V2_STORE_TRUE(&frame->values[A + 1]); } while (0)
#define V2_SUPER_GLOBAL_INT() do { V2_SUPER_GLOBAL_FETCH(); V2_STORE_INT(&frame->values[A + 1]); } while (0)
#define V2_SUPER_GLOBAL_FLT() do { V2_SUPER_GLOBAL_FETCH(); V2_STORE_FLT(&frame->values[A + 1]); } while (0)
#define V2_SUPER_GLOBAL_STR() do { V2_SUPER_GLOBAL_FETCH(); V2_STORE_STR(&frame->values[A + 1]); } while (0)
#define V2_SUPER_GLOBAL_MOVE() do { V2_SUPER_GLOBAL_FETCH();                 \
    V2_HOLE32(global_source, V2_SOURCE_HOLE);                               \
    frame->values[A + 1] = frame->values[global_source];                    \
} while (0)

#define V2_SUPER_METHOD() do {                                               \
    V2_HOLE32(method_receiver, V2_RECEIVER_HOLE);                            \
    uint64_t method_key = (uint64_t)V2_KEY_REF_HOLE;                        \
    __asm__ volatile ("" : "+r"(method_key));                             \
    Lua55ValueV2 *method_object = &frame->values[method_receiver];           \
    V2_SUPER_GUARD(method_object, LUA55_VALUE_TABLE);                        \
    Lua55GuestTableV2 *method_table =                                       \
        (Lua55GuestTableV2 *)method_object->payload.reference;               \
    if (method_table == 0 || method_table->header.kind != LUA55_OBJECT_TABLE \
        || method_table->heap != frame->invocation->heap                    \
        || method_table->metatable_reference != 0) {                        \
        V2_SPEC_MISMATCH(frame, LUA55_OBJECT_TABLE,                         \
            method_table != 0 ? method_table->header.kind : 0);             \
        V2_SPECIALIZATION_MISMATCH_EXIT(frame); }                                        \
    Lua55ValueV2 *method_value = v2_find_field(                              \
        method_table, (uintptr_t)method_key, 0);                             \
    frame->values[A + 1] = *method_object;                                  \
    if (method_value == 0) SET_TAG(&frame->values[A], LUA55_VALUE_NIL);     \
    else frame->values[A] = *method_value;                                  \
} while (0)

/* ---- CALL: native fixed / native vararg / host builtin ------------------ */
#define V2_CALL_NARGS_GENERIC()                                              \
    V2_HOLE32(B, V2_B_HOLE);                                                \
    uint32_t nargs = B - 1;                                                  \
    if (nargs >= 0xFFFFFFu) nargs = frame->top > A + 1                       \
        ? frame->top - (A + 1) : 0;
#define V2_CALL_NARGS_OPEN()                                                 \
    uint32_t nargs = frame->top > A + 1 ? frame->top - (A + 1) : 0;
#define V2_CALL_BASE_GENERIC()                                               \
    Lua55ValueV2 *callee = &frame->values[A];
#define V2_CALL_BASE_DIRECT() V2_VALUE_DISP(callee, V2_BASE_DISP_HOLE)
#define V2_CALL_NATIVE_LEAF(name, is_varg, prelude, nargs_setup, base_setup) \
STENCIL(name)(Lua55NativeFrameV2 *frame)                                    \
{                                                                           \
    V2_HOLE32(A, V2_A_HOLE); V2_HOLE32(C, V2_C_HOLE);                       \
    V2_HOLE32(pc, V2_PC_HOLE);                                              \
    uint64_t cont = V2_CONTINUATION_HOLE;                                   \
    __asm__ volatile ("" : "+r"(cont));                                     \
    prelude;                                                                \
    base_setup                                                              \
    Lua55NativeClosureV2 *closure;                                          \
    Lua55NativeFunctionDescriptorV2 *desc; Lua55NativeEntryV2 entry;        \
    V2_CALL_GUARD_NATIVE_CELL(frame, callee, closure, desc, entry, is_varg); \
    nargs_setup                                                             \
    uint32_t maxstack = desc->maxstacksize;                                 \
    uint32_t nparams = desc->numparams;                                     \
    uint32_t fixed = nargs < nparams ? nargs : nparams;                     \
    uint32_t varargs = (is_varg) && nargs > nparams ? nargs - nparams : 0;  \
    if ((uint32_t)(A + 1 + nargs) > frame->value_capacity) {                \
        frame->invocation->outcome.discriminant = LUA55_V2_OUTCOME_VALUE_OVERFLOW; \
        frame->invocation->outcome.u.overflow.required = (uint64_t)(A + 1 + nargs); \
        frame->invocation->outcome.u.overflow.available = frame->value_capacity; \
        frame->invocation->outcome.u.overflow.pc = pc;                      \
        LUA55_CPS_HOST_EXIT(frame); }                                       \
    size_t frame_bytes = (sizeof(Lua55NativeFrameV2)                        \
        + (size_t)desc->value_capacity * sizeof(Lua55ValueV2)               \
        + (size_t)varargs * sizeof(Lua55ValueV2)                            \
        + (size_t)desc->tbc_capacity * sizeof(Lua55TbcNodeV2) + 15)         \
        & ~(size_t)15;                                                      \
    uint8_t *next = frame->invocation->frame_next + frame_bytes;            \
    if (next > frame->invocation->frame_end) {                              \
        frame->invocation->outcome.discriminant = LUA55_V2_OUTCOME_STACK_OVERFLOW; \
        frame->invocation->outcome.u.overflow.required = (uint64_t)frame_bytes; \
        frame->invocation->outcome.u.overflow.available =                   \
            (uint64_t)(frame->invocation->frame_end - frame->invocation->frame_next); \
        frame->invocation->outcome.u.overflow.pc = pc;                      \
        LUA55_CPS_HOST_EXIT(frame); }                                       \
    Lua55NativeFrameV2 *cframe =                                            \
        (Lua55NativeFrameV2 *)frame->invocation->frame_next;                \
    frame->invocation->frame_next = next;                                   \
    cframe->values = (Lua55ValueV2 *)((uint8_t *)cframe + sizeof(Lua55NativeFrameV2)); \
    cframe->tbc_nodes = (Lua55TbcNodeV2 *)                                  \
        (cframe->values + desc->value_capacity + varargs);                  \
    cframe->upvalues = closure->cells;                                      \
    cframe->value_count = maxstack;                                         \
    cframe->value_capacity = desc->value_capacity;                          \
    cframe->top = nargs < desc->value_capacity ? nargs : desc->value_capacity; \
    cframe->vararg_count = varargs;                                         \
    cframe->tbc_count = 0;                                                  \
    cframe->tbc_capacity = desc->tbc_capacity;                              \
    cframe->invocation = frame->invocation;                                 \
    cframe->caller = frame;                                                 \
    cframe->return_link.entry = (Lua55NativeEntryV2)cont;                   \
    cframe->return_link.subject = frame;                                    \
    cframe->result_sink.values = callee;                                    \
    cframe->result_sink.top = &frame->top;                                  \
    cframe->result_sink.base = A;                                           \
    cframe->result_sink.count = (int32_t)C - 1;                             \
    cframe->result_sink.capacity = frame->value_capacity;                   \
    cframe->open_upvalues = 0;                                              \
    uint32_t i;                                                             \
    for (i = 0; i < fixed; i++) cframe->values[i] = callee[1 + i];           \
    for (i = fixed; i < nparams; i++)                                       \
        SET_TAG(&cframe->values[i], LUA55_VALUE_NIL);                       \
    if (varargs > 0) {                                                      \
        Lua55ValueV2 *vararg_slice = cframe->values + cframe->value_capacity; \
        for (i = 0; i < varargs; i++)                                       \
            vararg_slice[i] = callee[1 + fixed + i];                         \
    }                                                                       \
    frame->invocation->current_frame = cframe;                              \
    return entry(cframe);                                                   \
}

#define V2_CALL_FIXED_PREPARE(name, is_varg)                                \
STENCIL(name)(Lua55NativeFrameV2 *frame)                                    \
{                                                                           \
    V2_HOLE32(A, V2_A_HOLE);                                                \
    V2_VALUE_DISP(callee, V2_BASE_DISP_HOLE)                                \
    V2_HOLE32(nargs, V2_ARG_COUNT_HOLE);                                    \
    int32_t result_count = (int32_t)V2_RESULT_COUNT_HOLE;                   \
    __asm__ volatile ("" : "+r"(result_count));                             \
    V2_HOLE32(pc, V2_PC_HOLE);                                              \
    uint64_t cont = V2_CONTINUATION_HOLE;                                   \
    __asm__ volatile ("" : "+r"(cont));                                     \
    Lua55NativeClosureV2 *closure; Lua55NativeFunctionDescriptorV2 *desc;   \
    Lua55NativeEntryV2 entry;                                               \
    V2_CALL_GUARD_NATIVE_CELL(frame, callee, closure, desc, entry, is_varg); \
    uint32_t nparams = desc->numparams;                                     \
    uint32_t varargs = (is_varg) && nargs > nparams ? nargs - nparams : 0;  \
    if ((uint32_t)(A + 1 + nargs) > frame->value_capacity) {                \
        frame->invocation->outcome.discriminant = LUA55_V2_OUTCOME_VALUE_OVERFLOW; \
        frame->invocation->outcome.u.overflow.required = (uint64_t)(A + 1 + nargs); \
        frame->invocation->outcome.u.overflow.available = frame->value_capacity; \
        frame->invocation->outcome.u.overflow.pc = pc;                      \
        LUA55_CPS_HOST_EXIT(frame); }                                       \
    size_t frame_bytes = (sizeof(Lua55NativeFrameV2)                        \
        + (size_t)desc->value_capacity * sizeof(Lua55ValueV2)               \
        + (size_t)varargs * sizeof(Lua55ValueV2)                            \
        + (size_t)desc->tbc_capacity * sizeof(Lua55TbcNodeV2) + 15)         \
        & ~(size_t)15;                                                      \
    Lua55NativeInvocationV2 *inv = frame->invocation;                       \
    uint8_t *next = inv->frame_next + frame_bytes;                          \
    if (next > inv->frame_end) {                                            \
        inv->outcome.discriminant = LUA55_V2_OUTCOME_STACK_OVERFLOW;       \
        inv->outcome.u.overflow.required = (uint64_t)frame_bytes;           \
        inv->outcome.u.overflow.available =                                \
            (uint64_t)(inv->frame_end - inv->frame_next);                   \
        inv->outcome.u.overflow.pc = pc;                                    \
        LUA55_CPS_HOST_EXIT(frame); }                                       \
    Lua55NativeFrameV2 *cframe = (Lua55NativeFrameV2 *)inv->frame_next;     \
    cframe->values = (Lua55ValueV2 *)                                      \
        ((uint8_t *)cframe + sizeof(Lua55NativeFrameV2));                   \
    cframe->tbc_nodes = (Lua55TbcNodeV2 *)                                 \
        (cframe->values + desc->value_capacity + varargs);                  \
    cframe->upvalues = closure->cells;                                      \
    cframe->value_count = desc->maxstacksize;                               \
    cframe->value_capacity = desc->value_capacity;                          \
    cframe->top = nargs < desc->value_capacity ? nargs : desc->value_capacity; \
    cframe->vararg_count = varargs;                                         \
    cframe->tbc_count = 0;                                                  \
    cframe->tbc_capacity = desc->tbc_capacity;                              \
    cframe->invocation = inv;                                               \
    cframe->caller = frame;                                                 \
    cframe->return_link.entry = (Lua55NativeEntryV2)cont;                   \
    cframe->return_link.subject = frame;                                    \
    cframe->result_sink.values = callee;                                    \
    cframe->result_sink.top = &frame->top;                                  \
    cframe->result_sink.base = A;                                           \
    cframe->result_sink.count = result_count;                               \
    cframe->result_sink.capacity = frame->value_capacity;                   \
    cframe->open_upvalues = 0;                                              \
    inv->prepared_call.callee = cframe;                                     \
    inv->prepared_call.entry = entry;                                       \
    inv->prepared_call.next_frame = next;                                   \
    inv->prepared_call.nparams = nparams;                                   \
    inv->prepared_call.nargs = nargs;                                       \
    LUA55_RESIDUAL_NEXT(frame);                                             \
}
V2_CALL_FIXED_PREPARE(lua55_v2r_call_native_fixed_prepare, 0)

/* Exact one-argument fixed-CALL leaf. This is the scalar CALL opcode for the
   common authored B=2 shape, not a multi-op superinstruction. It removes the
   prepare/slot/finish staging round-trip and contains no authored-count loop. */
STENCIL(lua55_v2r_call_native_fixed_arg1)(Lua55NativeFrameV2 *frame)
{
    V2_HOLE32(A, V2_A_HOLE);
    V2_VALUE_DISP(callee, V2_BASE_DISP_HOLE)
    V2_VALUE_DISP(argument, V2_SOURCE_DISP_HOLE)
    int32_t result_count = (int32_t)V2_RESULT_COUNT_HOLE;
    __asm__ volatile ("" : "+r"(result_count));
    V2_HOLE32(pc, V2_PC_HOLE);
    uint64_t cont = V2_CONTINUATION_HOLE;
    __asm__ volatile ("" : "+r"(cont));
    Lua55NativeClosureV2 *closure; Lua55NativeFunctionDescriptorV2 *desc;
    Lua55NativeEntryV2 entry;
    V2_CALL_GUARD_NATIVE_CELL(frame, callee, closure, desc, entry, 0);
    if ((uint32_t)(A + 2) > frame->value_capacity) {
        frame->invocation->outcome.discriminant = LUA55_V2_OUTCOME_VALUE_OVERFLOW;
        frame->invocation->outcome.u.overflow.required = (uint64_t)(A + 2);
        frame->invocation->outcome.u.overflow.available = frame->value_capacity;
        frame->invocation->outcome.u.overflow.pc = pc;
        LUA55_CPS_HOST_EXIT(frame);
    }
    size_t frame_bytes = (sizeof(Lua55NativeFrameV2)
        + (size_t)desc->value_capacity * sizeof(Lua55ValueV2)
        + (size_t)desc->tbc_capacity * sizeof(Lua55TbcNodeV2) + 15)
        & ~(size_t)15;
    Lua55NativeInvocationV2 *inv = frame->invocation;
    uint8_t *next = inv->frame_next + frame_bytes;
    if (next > inv->frame_end) {
        inv->outcome.discriminant = LUA55_V2_OUTCOME_STACK_OVERFLOW;
        inv->outcome.u.overflow.required = (uint64_t)frame_bytes;
        inv->outcome.u.overflow.available =
            (uint64_t)(inv->frame_end - inv->frame_next);
        inv->outcome.u.overflow.pc = pc;
        LUA55_CPS_HOST_EXIT(frame);
    }
    Lua55NativeFrameV2 *cframe = (Lua55NativeFrameV2 *)inv->frame_next;
    cframe->values = (Lua55ValueV2 *)
        ((uint8_t *)cframe + sizeof(Lua55NativeFrameV2));
    cframe->tbc_nodes = (Lua55TbcNodeV2 *)
        (cframe->values + desc->value_capacity);
    cframe->upvalues = closure->cells;
    cframe->value_count = desc->maxstacksize;
    cframe->value_capacity = desc->value_capacity;
    cframe->top = 1;
    cframe->vararg_count = 0;
    cframe->tbc_count = 0;
    cframe->tbc_capacity = desc->tbc_capacity;
    cframe->invocation = inv;
    cframe->caller = frame;
    cframe->return_link.entry = (Lua55NativeEntryV2)cont;
    cframe->return_link.subject = frame;
    cframe->result_sink.values = callee;
    cframe->result_sink.top = &frame->top;
    cframe->result_sink.base = A;
    cframe->result_sink.count = result_count;
    cframe->result_sink.capacity = frame->value_capacity;
    cframe->open_upvalues = 0;
    if (desc->numparams > 0) cframe->values[0] = *argument;
    uint32_t i;
    for (i = 1; i < desc->numparams; i++)
        SET_TAG(&cframe->values[i], LUA55_VALUE_NIL);
    inv->frame_next = next;
    inv->current_frame = cframe;
    return entry(cframe);
}
V2_CALL_FIXED_PREPARE(lua55_v2r_call_native_vararg_prepare, 1)

STENCIL(lua55_v2r_call_fixed_arg_slot)(Lua55NativeFrameV2 *frame)
{
    V2_VALUE_DISP(source, V2_SOURCE_DISP_HOLE)
    V2_HOLE32(slot, V2_SPAN_HOLE);
    Lua55PreparedCallV2 *prep = &frame->invocation->prepared_call;
    if (slot < prep->nparams) {
        V2_VALUE_BASE_DISP(target, prep->callee->values, V2_TARGET_DISP_HOLE)
        *target = *source;
    } else if (prep->callee->vararg_count > 0) {
        Lua55ValueV2 *slice = prep->callee->values
            + prep->callee->value_capacity;
        slice[slot - prep->nparams] = *source;
    }
    LUA55_RESIDUAL_NEXT(frame);
}

STENCIL(lua55_v2r_call_fixed_finish)(Lua55NativeFrameV2 *frame)
{
    Lua55NativeInvocationV2 *inv = frame->invocation;
    Lua55PreparedCallV2 *prep = &inv->prepared_call;
    uint32_t i;
    for (i = prep->nargs; i < prep->nparams; i++)
        SET_TAG(&prep->callee->values[i], LUA55_VALUE_NIL);
    inv->frame_next = prep->next_frame;
    inv->current_frame = prep->callee;
    return prep->entry(prep->callee);
}

V2_CALL_NATIVE_LEAF(lua55_v2r_call_native_fixed_open, 0,
    V2_NO_CALL_PRELUDE(), V2_CALL_NARGS_OPEN(), V2_CALL_BASE_DIRECT())
V2_CALL_NATIVE_LEAF(lua55_v2r_call_native_vararg_open, 1,
    V2_NO_CALL_PRELUDE(), V2_CALL_NARGS_OPEN(), V2_CALL_BASE_DIRECT())

#define V2_SUPER_NATIVE_PAIR(base, prelude)                                  \
    V2_CALL_NATIVE_LEAF(lua55_v2r_##base##_native_fixed, 0, prelude,         \
        V2_CALL_NARGS_GENERIC(), V2_CALL_BASE_GENERIC())                     \
    V2_CALL_NATIVE_LEAF(lua55_v2r_##base##_native_vararg, 1, prelude,        \
        V2_CALL_NARGS_GENERIC(), V2_CALL_BASE_GENERIC())

V2_SUPER_NATIVE_PAIR(super_global_nil, V2_SUPER_GLOBAL_NIL())
V2_SUPER_NATIVE_PAIR(super_global_false, V2_SUPER_GLOBAL_FALSE())
V2_SUPER_NATIVE_PAIR(super_global_true, V2_SUPER_GLOBAL_TRUE())
V2_SUPER_NATIVE_PAIR(super_global_int, V2_SUPER_GLOBAL_INT())
V2_SUPER_NATIVE_PAIR(super_global_flt, V2_SUPER_GLOBAL_FLT())
V2_SUPER_NATIVE_PAIR(super_global_str, V2_SUPER_GLOBAL_STR())
V2_SUPER_NATIVE_PAIR(super_global_move, V2_SUPER_GLOBAL_MOVE())
V2_SUPER_NATIVE_PAIR(super_method, V2_SUPER_METHOD())

STENCIL(lua55_v2r_call_host)(Lua55NativeFrameV2 *frame)
{
    V2_HOLE32(A, V2_A_HOLE); V2_HOLE32(B, V2_B_HOLE); V2_HOLE32(C, V2_C_HOLE);
    V2_VALUE_DISP(callee, V2_BASE_DISP_HOLE)
    V2_HOLE32(pc, V2_PC_HOLE);
    uint64_t cont = V2_CONTINUATION_HOLE;
    __asm__ volatile ("" : "+r"(cont));
    Lua55NativeClosureV2 *closure;
    V2_CALL_GUARD_BUILTIN_CELL(frame, callee, closure);
    Lua55NativeInvocationV2 *inv = frame->invocation;
    inv->outcome.discriminant = LUA55_V2_OUTCOME_HOST_CALL;
    inv->outcome.u.host_call.resume_entry = (Lua55NativeEntryV2)cont;
    inv->outcome.u.host_call.a = A;
    inv->outcome.u.host_call.b = B;
    inv->outcome.u.host_call.c = C;
    inv->outcome.u.host_call.pc = pc;
    inv->outcome.u.host_call.host_id = 0;
    inv->outcome.u.host_call.reserved = 0;
    LUA55_CPS_HOST_EXIT(frame);
}

#define V2_SUPER_CALL_HOST(name, prelude)                                    \
STENCIL(name)(Lua55NativeFrameV2 *frame)                                    \
{                                                                           \
    V2_HOLE32(A, V2_A_HOLE); V2_HOLE32(B, V2_B_HOLE); V2_HOLE32(C, V2_C_HOLE); \
    V2_HOLE32(pc, V2_PC_HOLE);                                              \
    uint64_t cont = V2_CONTINUATION_HOLE;                                   \
    __asm__ volatile ("" : "+r"(cont));                                   \
    prelude;                                                                \
    Lua55ValueV2 *callee; Lua55NativeClosureV2 *closure;                    \
    V2_CALL_GUARD_BUILTIN(frame, A, callee, closure);                       \
    Lua55NativeInvocationV2 *inv = frame->invocation;                       \
    inv->outcome.discriminant = LUA55_V2_OUTCOME_HOST_CALL;                 \
    inv->outcome.u.host_call.resume_entry = (Lua55NativeEntryV2)cont;       \
    inv->outcome.u.host_call.a = A; inv->outcome.u.host_call.b = B;         \
    inv->outcome.u.host_call.c = C; inv->outcome.u.host_call.pc = pc;       \
    inv->outcome.u.host_call.host_id = 0;                                   \
    inv->outcome.u.host_call.reserved = 0;                                  \
    LUA55_CPS_HOST_EXIT(frame);                                             \
}

V2_SUPER_CALL_HOST(lua55_v2r_super_global_nil_host, V2_SUPER_GLOBAL_NIL())
V2_SUPER_CALL_HOST(lua55_v2r_super_global_false_host, V2_SUPER_GLOBAL_FALSE())
V2_SUPER_CALL_HOST(lua55_v2r_super_global_true_host, V2_SUPER_GLOBAL_TRUE())
V2_SUPER_CALL_HOST(lua55_v2r_super_global_int_host, V2_SUPER_GLOBAL_INT())
V2_SUPER_CALL_HOST(lua55_v2r_super_global_flt_host, V2_SUPER_GLOBAL_FLT())
V2_SUPER_CALL_HOST(lua55_v2r_super_global_str_host, V2_SUPER_GLOBAL_STR())
V2_SUPER_CALL_HOST(lua55_v2r_super_global_move_host, V2_SUPER_GLOBAL_MOVE())
V2_SUPER_CALL_HOST(lua55_v2r_super_method_host, V2_SUPER_METHOD())

/* ---- TAILCALL: native fixed / native vararg / host builtin -------------- */
#define V2_TAIL_NARGS_GENERIC()                                              \
    V2_HOLE32(B, V2_B_HOLE);                                                \
    uint32_t nargs = B - 1;                                                  \
    if (nargs >= 0xFFFFFFu) nargs = frame->top > A + 1                       \
        ? frame->top - (A + 1) : 0;
#define V2_TAIL_NARGS_OPEN()                                                 \
    uint32_t nargs = frame->top > A + 1 ? frame->top - (A + 1) : 0;
#define V2_TAILCALL_NATIVE_LEAF(name, is_varg, nargs_setup)                  \
STENCIL(name)(Lua55NativeFrameV2 *frame)                                    \
{                                                                           \
    V2_HOLE32(A, V2_A_HOLE);                                                \
    V2_VALUE_DISP(callee, V2_BASE_DISP_HOLE)                                \
    V2_HOLE32(pc, V2_PC_HOLE);                                              \
    Lua55NativeClosureV2 *closure;                                          \
    Lua55NativeFunctionDescriptorV2 *desc; Lua55NativeEntryV2 entry;        \
    V2_CALL_GUARD_NATIVE_CELL(frame, callee, closure, desc, entry, is_varg); \
    nargs_setup                                                             \
    uint32_t maxstack = desc->maxstacksize;                                 \
    uint32_t nparams = desc->numparams;                                     \
    uint32_t fixed = nargs < nparams ? nargs : nparams;                     \
    uint32_t varargs = (is_varg) && nargs > nparams ? nargs - nparams : 0;  \
    if ((uint32_t)(A + 1 + nargs) > frame->value_capacity) {                \
        frame->invocation->outcome.discriminant = LUA55_V2_OUTCOME_VALUE_OVERFLOW; \
        frame->invocation->outcome.u.overflow.required = (uint64_t)(A + 1 + nargs); \
        frame->invocation->outcome.u.overflow.available = frame->value_capacity; \
        frame->invocation->outcome.u.overflow.pc = pc;                      \
        LUA55_CPS_HOST_EXIT(frame); }                                       \
    size_t frame_bytes = (sizeof(Lua55NativeFrameV2)                        \
        + (size_t)desc->value_capacity * sizeof(Lua55ValueV2)               \
        + (size_t)varargs * sizeof(Lua55ValueV2)                            \
        + (size_t)desc->tbc_capacity * sizeof(Lua55TbcNodeV2) + 15)         \
        & ~(size_t)15;                                                      \
    uint8_t *new_end = (uint8_t *)frame + frame_bytes;                      \
    if (new_end > frame->invocation->frame_end) {                           \
        frame->invocation->outcome.discriminant = LUA55_V2_OUTCOME_STACK_OVERFLOW; \
        frame->invocation->outcome.u.overflow.required = (uint64_t)frame_bytes; \
        frame->invocation->outcome.u.overflow.available =                   \
            (uint64_t)(frame->invocation->frame_end - (uint8_t *)frame);    \
        frame->invocation->outcome.u.overflow.pc = pc;                      \
        LUA55_CPS_HOST_EXIT(frame); }                                       \
    lua55_cps_close_open_upvalues(frame);                                   \
    uint32_t i;                                                             \
    for (i = 0; i < fixed; i++) frame->values[i] = callee[1 + i];            \
    for (i = fixed; i < nparams; i++)                                       \
        SET_TAG(&frame->values[i], LUA55_VALUE_NIL);                        \
    if (varargs > 0) {                                                      \
        Lua55ValueV2 *vararg_slice = frame->values + desc->value_capacity;  \
        for (i = 0; i < varargs; i++)                                       \
            vararg_slice[i] = callee[1 + fixed + i];                         \
    }                                                                       \
    frame->upvalues = closure->cells;                                       \
    frame->value_count = maxstack;                                          \
    frame->value_capacity = desc->value_capacity;                           \
    frame->vararg_count = varargs;                                          \
    frame->top = nargs < desc->value_capacity ? nargs : desc->value_capacity; \
    frame->tbc_count = 0;                                                   \
    frame->tbc_capacity = desc->tbc_capacity;                               \
    frame->tbc_nodes = (Lua55TbcNodeV2 *)                                  \
        (frame->values + desc->value_capacity + varargs);                   \
    frame->open_upvalues = 0;                                               \
    frame->invocation->frame_next = new_end;                                \
    frame->invocation->current_frame = frame;                               \
    return entry(frame);                                                    \
}

#define V2_TAIL_FIXED_PREPARE(name, is_varg)                                \
STENCIL(name)(Lua55NativeFrameV2 *frame)                                    \
{                                                                           \
    V2_HOLE32(A, V2_A_HOLE);                                                \
    V2_VALUE_DISP(callee, V2_BASE_DISP_HOLE)                                \
    V2_HOLE32(nargs, V2_ARG_COUNT_HOLE);                                    \
    V2_HOLE32(pc, V2_PC_HOLE);                                              \
    Lua55NativeClosureV2 *closure; Lua55NativeFunctionDescriptorV2 *desc;   \
    Lua55NativeEntryV2 entry;                                               \
    V2_CALL_GUARD_NATIVE_CELL(frame, callee, closure, desc, entry, is_varg); \
    uint32_t nparams = desc->numparams;                                     \
    uint32_t varargs = (is_varg) && nargs > nparams ? nargs - nparams : 0;  \
    if ((uint32_t)(A + 1 + nargs) > frame->value_capacity) {                \
        frame->invocation->outcome.discriminant = LUA55_V2_OUTCOME_VALUE_OVERFLOW; \
        frame->invocation->outcome.u.overflow.required = (uint64_t)(A + 1 + nargs); \
        frame->invocation->outcome.u.overflow.available = frame->value_capacity; \
        frame->invocation->outcome.u.overflow.pc = pc;                      \
        LUA55_CPS_HOST_EXIT(frame); }                                       \
    size_t frame_bytes = (sizeof(Lua55NativeFrameV2)                        \
        + (size_t)desc->value_capacity * sizeof(Lua55ValueV2)               \
        + (size_t)varargs * sizeof(Lua55ValueV2)                            \
        + (size_t)desc->tbc_capacity * sizeof(Lua55TbcNodeV2) + 15)         \
        & ~(size_t)15;                                                      \
    uint8_t *new_end = (uint8_t *)frame + frame_bytes;                      \
    if (new_end > frame->invocation->frame_end) {                           \
        frame->invocation->outcome.discriminant = LUA55_V2_OUTCOME_STACK_OVERFLOW; \
        frame->invocation->outcome.u.overflow.required = (uint64_t)frame_bytes; \
        frame->invocation->outcome.u.overflow.available =                   \
            (uint64_t)(frame->invocation->frame_end - (uint8_t *)frame);    \
        frame->invocation->outcome.u.overflow.pc = pc;                      \
        LUA55_CPS_HOST_EXIT(frame); }                                       \
    lua55_cps_close_open_upvalues(frame);                                   \
    Lua55PreparedTailCallV2 *prep = &frame->invocation->prepared_tail_call; \
    prep->entry = entry;                                                    \
    prep->upvalues = closure->cells;                                        \
    prep->frame_end = new_end;                                              \
    prep->nparams = nparams;                                                \
    prep->nargs = nargs;                                                    \
    prep->vararg_count = varargs;                                           \
    prep->maxstack = desc->maxstacksize;                                    \
    prep->value_capacity = desc->value_capacity;                            \
    prep->tbc_capacity = desc->tbc_capacity;                                \
    LUA55_RESIDUAL_NEXT(frame);                                             \
}
V2_TAIL_FIXED_PREPARE(lua55_v2r_tailcall_native_fixed_prepare, 0)
V2_TAIL_FIXED_PREPARE(lua55_v2r_tailcall_native_vararg_prepare, 1)

STENCIL(lua55_v2r_tailcall_fixed_arg_slot)(Lua55NativeFrameV2 *frame)
{
    V2_VALUE_DISP(source, V2_SOURCE_DISP_HOLE)
    V2_HOLE32(slot, V2_SPAN_HOLE);
    Lua55PreparedTailCallV2 *prep = &frame->invocation->prepared_tail_call;
    if (slot < prep->nparams) {
        V2_VALUE_DISP(target, V2_TARGET_DISP_HOLE)
        *target = *source;
    } else if (prep->vararg_count > 0) {
        Lua55ValueV2 *slice = frame->values + prep->value_capacity;
        slice[slot - prep->nparams] = *source;
    }
    LUA55_RESIDUAL_NEXT(frame);
}

STENCIL(lua55_v2r_tailcall_fixed_finish)(Lua55NativeFrameV2 *frame)
{
    Lua55NativeInvocationV2 *inv = frame->invocation;
    Lua55PreparedTailCallV2 *prep = &inv->prepared_tail_call;
    uint32_t i;
    for (i = prep->nargs; i < prep->nparams; i++)
        SET_TAG(&frame->values[i], LUA55_VALUE_NIL);
    frame->upvalues = prep->upvalues;
    frame->value_count = prep->maxstack;
    frame->value_capacity = prep->value_capacity;
    frame->vararg_count = prep->vararg_count;
    frame->top = prep->nargs < prep->value_capacity
        ? prep->nargs : prep->value_capacity;
    frame->tbc_count = 0;
    frame->tbc_capacity = prep->tbc_capacity;
    frame->tbc_nodes = (Lua55TbcNodeV2 *)
        (frame->values + prep->value_capacity + prep->vararg_count);
    frame->open_upvalues = 0;
    inv->frame_next = prep->frame_end;
    inv->current_frame = frame;
    return prep->entry(frame);
}

V2_TAILCALL_NATIVE_LEAF(lua55_v2r_tailcall_native_fixed_open, 0,
    V2_TAIL_NARGS_OPEN())
V2_TAILCALL_NATIVE_LEAF(lua55_v2r_tailcall_native_vararg_open, 1,
    V2_TAIL_NARGS_OPEN())

STENCIL(lua55_v2r_tailcall_host)(Lua55NativeFrameV2 *frame)
{
    V2_HOLE32(A, V2_A_HOLE); V2_HOLE32(B, V2_B_HOLE);
    V2_VALUE_DISP(callee, V2_BASE_DISP_HOLE)
    V2_HOLE32(pc, V2_PC_HOLE);
    uint64_t tail_ret = V2_TAIL_RETURN_HOLE;
    __asm__ volatile ("" : "+r"(tail_ret));
    Lua55NativeClosureV2 *closure;
    V2_CALL_GUARD_BUILTIN_CELL(frame, callee, closure);
    Lua55NativeInvocationV2 *inv = frame->invocation;
    inv->outcome.discriminant = LUA55_V2_OUTCOME_HOST_TAIL_CALL;
    inv->outcome.u.host_tail_call.tail_return_entry = (Lua55NativeEntryV2)tail_ret;
    inv->outcome.u.host_tail_call.a = A;
    inv->outcome.u.host_tail_call.b = B;
    inv->outcome.u.host_tail_call.pc = pc;
    inv->outcome.u.host_tail_call.host_id = 0;
    LUA55_CPS_HOST_EXIT(frame);
}

/* ---- TFORCALL: native iterator closure / host builtin iterator ---------- */
STENCIL(lua55_v2r_tforcall_native)(Lua55NativeFrameV2 *frame)
{
    V2_HOLE32(A, V2_A_HOLE); V2_HOLE32(C, V2_C_HOLE);
    V2_VALUE_DISP(callee, V2_BASE_DISP_HOLE)
    V2_HOLE32(pc, V2_PC_HOLE);
    uint64_t cont = V2_CONTINUATION_HOLE;
    __asm__ volatile ("" : "+r"(cont));
    Lua55NativeClosureV2 *closure;
    Lua55NativeFunctionDescriptorV2 *desc; Lua55NativeEntryV2 entry;
    V2_CALL_GUARD_NATIVE_CELL(frame, callee, closure, desc, entry, 0);
    Lua55NativeInvocationV2 *inv = frame->invocation;
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
    Lua55NativeFrameV2 *cframe = (Lua55NativeFrameV2 *)inv->frame_next;
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
    cframe->result_sink.values = callee + 3;
    cframe->result_sink.top = &frame->top;
    cframe->result_sink.base = A + 3;
    cframe->result_sink.count = (int32_t)C;
    cframe->result_sink.capacity = frame->value_capacity;
    cframe->open_upvalues = 0;
    cframe->values[0] = callee[1];
    cframe->values[1] = callee[3];
    uint32_t i;
    for (i = 2; i < nparams; i++)
        SET_TAG(&cframe->values[i], LUA55_VALUE_NIL);
    inv->current_frame = cframe;
    return entry(cframe);
}

STENCIL(lua55_v2r_tforcall_host)(Lua55NativeFrameV2 *frame)
{
    V2_HOLE32(A, V2_A_HOLE); V2_HOLE32(C, V2_C_HOLE);
    V2_VALUE_DISP(callee, V2_BASE_DISP_HOLE)
    V2_HOLE32(pc, V2_PC_HOLE);
    uint64_t cont = V2_CONTINUATION_HOLE;
    __asm__ volatile ("" : "+r"(cont));
    Lua55NativeClosureV2 *closure;
    V2_CALL_GUARD_BUILTIN_CELL(frame, callee, closure);
    Lua55NativeInvocationV2 *inv = frame->invocation;
    inv->outcome.discriminant = LUA55_V2_OUTCOME_HOST_CALL;
    inv->outcome.u.host_call.resume_entry = (Lua55NativeEntryV2)cont;
    inv->outcome.u.host_call.a = A;
    inv->outcome.u.host_call.b = 3;
    inv->outcome.u.host_call.c = C;
    inv->outcome.u.host_call.pc = pc;
    inv->outcome.u.host_call.host_id = 0;
    inv->outcome.u.host_call.reserved = 1;
    LUA55_CPS_HOST_EXIT(frame);
}

/* ======================================================================= */
/* Batch 6: exact CONCAT operand-vector leaves                              */
/* ------------------------------------------------------------------------ */
/* The learning invocation observes the operand-shape vector (B <= 3); the  */
/* residual selects the exact leaf with each position's measure/write baked */
/* in. The count is projection-proven (B), never a runtime classification.  */
/* ======================================================================= */

#define V2_CONCAT_GUARD_STR(cell) V2_LEAF_GUARD_STR(frame, cell)
#define V2_CONCAT_GUARD_INT(cell) V2_LEAF_GUARD(frame, cell, LUA55_VALUE_INTEGER)
#define V2_CONCAT_GUARD_FLT(cell) V2_LEAF_GUARD(frame, cell, LUA55_VALUE_FLOAT)

#define V2_CONCAT_MEASURE_STR(cell) do {                                    \
    Lua55GuestStringV2 *cs = (Lua55GuestStringV2 *)(cell)->payload.reference; \
    total += cs->length; } while (0)
#define V2_CONCAT_MEASURE_INT(cell) do {                                    \
    char buf[24];                                                           \
    total += (uint64_t)v2_itoa_fn_get()((cell)->payload.integer, buf);      \
} while (0)
#define V2_CONCAT_MEASURE_FLT(cell) do {                                    \
    char buf[32];                                                           \
    total += (uint64_t)v2_dtoa_fn()((cell)->payload.floating, buf);         \
} while (0)

#define V2_CONCAT_WRITE_STR(cell) do {                                      \
    Lua55GuestStringV2 *cs = (Lua55GuestStringV2 *)(cell)->payload.reference; \
    uint32_t n = cs->length; uint32_t j;                                    \
    for (j = 0; j < n; j++) out[j] = cs->bytes[j];                          \
    out += n; } while (0)
#define V2_CONCAT_WRITE_INT(cell) do {                                      \
    char buf[24]; int m = v2_itoa_fn_get()((cell)->payload.integer, buf);   \
    int j; for (j = 0; j < m; j++) out[j] = (uint8_t)buf[j]; out += m; } while (0)
#define V2_CONCAT_WRITE_FLT(cell) do {                                      \
    char buf[32]; int m = v2_dtoa_fn()((cell)->payload.floating, buf);      \
    int j; for (j = 0; j < m; j++) out[j] = (uint8_t)buf[j]; out += m; } while (0)

#define V2_CONCAT_ALLOC()                                                   \
    Lua55GuestHeapV2 *heap = frame->invocation->heap;                       \
    if (heap == 0 || heap->table_region == 0) {                             \
        V2_REJECT(frame, LUA55_V2_REJECT_INVALID_OBJECT);                   \
        LUA55_CPS_HOST_EXIT(frame); }                                       \
    size_t bytes_size = total > 0 ? (size_t)total : 1;                      \
    size_t alloc = sizeof(Lua55GuestStringV2) + bytes_size;                 \
    uintptr_t at = v2_heap_bump(heap, alloc);                               \
    if (at == 0) { V2_PUBLISH_OVERFLOW(frame, LUA55_V2_OUTCOME_HEAP_OVERFLOW, 0, 0); \
                    LUA55_CPS_HOST_EXIT(frame); }                           \
    Lua55GuestStringV2 *str = (Lua55GuestStringV2 *)at;                     \
    uint8_t *bytes = (uint8_t *)(at + sizeof(Lua55GuestStringV2));          \
    str->header.kind = total <= V2_MINSTR                                   \
        ? LUA55_OBJECT_SHORT_STRING : LUA55_OBJECT_LONG_STRING;             \
    str->header.generation = heap->object_count + 1;                        \
    str->length = (uint32_t)total;                                          \
    str->hash = 0;                                                          \
    str->bytes = bytes;                                                     \
    heap->object_count++;

#if 0 /* S10 retired Cartesian CONCAT width/vector leaves */
#define V2_CONCAT_LEAF_2(name, s0, s1)                                      \
STENCIL(name)(Lua55NativeFrameV2 *frame)                                    \
{                                                                           \
    V2_HOLE32(base, V2_SETLIST_BASE_HOLE);                                  \
    V2_CONCAT_GUARD_##s0(&frame->values[base + 0]);                         \
    V2_CONCAT_GUARD_##s1(&frame->values[base + 1]);                         \
    uint64_t total = 0;                                                     \
    V2_CONCAT_MEASURE_##s0(&frame->values[base + 0]);                       \
    V2_CONCAT_MEASURE_##s1(&frame->values[base + 1]);                       \
    V2_CONCAT_ALLOC()                                                       \
    uint8_t *out = bytes;                                                   \
    V2_CONCAT_WRITE_##s0(&frame->values[base + 0]);                         \
    V2_CONCAT_WRITE_##s1(&frame->values[base + 1]);                         \
    Lua55ValueV2 *target = &frame->values[base];                            \
    SET_TAG(target, total <= V2_MINSTR                                      \
        ? LUA55_VALUE_SHORT_STRING : LUA55_VALUE_LONG_STRING);              \
    target->payload.reference = (uintptr_t)str;                             \
    LUA55_RESIDUAL_NEXT(frame);                                             \
}

#define V2_CONCAT_LEAF_3(name, s0, s1, s2)                                  \
STENCIL(name)(Lua55NativeFrameV2 *frame)                                    \
{                                                                           \
    V2_HOLE32(base, V2_SETLIST_BASE_HOLE);                                  \
    V2_CONCAT_GUARD_##s0(&frame->values[base + 0]);                         \
    V2_CONCAT_GUARD_##s1(&frame->values[base + 1]);                         \
    V2_CONCAT_GUARD_##s2(&frame->values[base + 2]);                         \
    uint64_t total = 0;                                                     \
    V2_CONCAT_MEASURE_##s0(&frame->values[base + 0]);                       \
    V2_CONCAT_MEASURE_##s1(&frame->values[base + 1]);                       \
    V2_CONCAT_MEASURE_##s2(&frame->values[base + 2]);                       \
    V2_CONCAT_ALLOC()                                                       \
    uint8_t *out = bytes;                                                   \
    V2_CONCAT_WRITE_##s0(&frame->values[base + 0]);                         \
    V2_CONCAT_WRITE_##s1(&frame->values[base + 1]);                         \
    V2_CONCAT_WRITE_##s2(&frame->values[base + 2]);                         \
    Lua55ValueV2 *target = &frame->values[base];                            \
    SET_TAG(target, total <= V2_MINSTR                                      \
        ? LUA55_VALUE_SHORT_STRING : LUA55_VALUE_LONG_STRING);              \
    target->payload.reference = (uintptr_t)str;                             \
    LUA55_RESIDUAL_NEXT(frame);                                             \
}
V2_CONCAT_LEAF_2(lua55_v2r_concat_2_ss, STR, STR)
V2_CONCAT_LEAF_2(lua55_v2r_concat_2_si, STR, INT)
V2_CONCAT_LEAF_2(lua55_v2r_concat_2_sf, STR, FLT)
V2_CONCAT_LEAF_2(lua55_v2r_concat_2_is, INT, STR)
V2_CONCAT_LEAF_2(lua55_v2r_concat_2_ii, INT, INT)
V2_CONCAT_LEAF_2(lua55_v2r_concat_2_if, INT, FLT)
V2_CONCAT_LEAF_2(lua55_v2r_concat_2_fs, FLT, STR)
V2_CONCAT_LEAF_2(lua55_v2r_concat_2_fi, FLT, INT)
V2_CONCAT_LEAF_2(lua55_v2r_concat_2_ff, FLT, FLT)
V2_CONCAT_LEAF_3(lua55_v2r_concat_3_sss, STR, STR, STR)
V2_CONCAT_LEAF_3(lua55_v2r_concat_3_ssi, STR, STR, INT)
V2_CONCAT_LEAF_3(lua55_v2r_concat_3_ssf, STR, STR, FLT)
V2_CONCAT_LEAF_3(lua55_v2r_concat_3_sis, STR, INT, STR)
V2_CONCAT_LEAF_3(lua55_v2r_concat_3_sii, STR, INT, INT)
V2_CONCAT_LEAF_3(lua55_v2r_concat_3_sif, STR, INT, FLT)
V2_CONCAT_LEAF_3(lua55_v2r_concat_3_sfs, STR, FLT, STR)
V2_CONCAT_LEAF_3(lua55_v2r_concat_3_sfi, STR, FLT, INT)
V2_CONCAT_LEAF_3(lua55_v2r_concat_3_sff, STR, FLT, FLT)
V2_CONCAT_LEAF_3(lua55_v2r_concat_3_iss, INT, STR, STR)
V2_CONCAT_LEAF_3(lua55_v2r_concat_3_isi, INT, STR, INT)
V2_CONCAT_LEAF_3(lua55_v2r_concat_3_isf, INT, STR, FLT)
V2_CONCAT_LEAF_3(lua55_v2r_concat_3_iis, INT, INT, STR)
V2_CONCAT_LEAF_3(lua55_v2r_concat_3_iii, INT, INT, INT)
V2_CONCAT_LEAF_3(lua55_v2r_concat_3_iif, INT, INT, FLT)
V2_CONCAT_LEAF_3(lua55_v2r_concat_3_ifs, INT, FLT, STR)
V2_CONCAT_LEAF_3(lua55_v2r_concat_3_ifi, INT, FLT, INT)
V2_CONCAT_LEAF_3(lua55_v2r_concat_3_iff, INT, FLT, FLT)
V2_CONCAT_LEAF_3(lua55_v2r_concat_3_fss, FLT, STR, STR)
V2_CONCAT_LEAF_3(lua55_v2r_concat_3_fsi, FLT, STR, INT)
V2_CONCAT_LEAF_3(lua55_v2r_concat_3_fsf, FLT, STR, FLT)
V2_CONCAT_LEAF_3(lua55_v2r_concat_3_fis, FLT, INT, STR)
V2_CONCAT_LEAF_3(lua55_v2r_concat_3_fii, FLT, INT, INT)
V2_CONCAT_LEAF_3(lua55_v2r_concat_3_fif, FLT, INT, FLT)
V2_CONCAT_LEAF_3(lua55_v2r_concat_3_ffs, FLT, FLT, STR)
V2_CONCAT_LEAF_3(lua55_v2r_concat_3_ffi, FLT, FLT, INT)
V2_CONCAT_LEAF_3(lua55_v2r_concat_3_fff, FLT, FLT, FLT)
#endif

/* S10 fragment implementation is declared here; the width-4/5 Cartesian
   declarations below remain source-only compatibility material and are not
   extracted into the production bank. */
/* S10: exact CONCAT fragment vocabulary. The learned operand vector selects
   these leaves before publication; native execution contains no sibling
   classification. Fragments communicate only through prepared_concat and
   proper-tail fragment_next edges. */
#define V2_CONCAT_FRAGMENT_NEXT(frame) do {                                  \
    uintptr_t next = (uintptr_t)V2_FRAGMENT_NEXT_HOLE;                       \
    __asm__ volatile ("" : "+r"(next));                                      \
    return ((Lua55NativeEntryV2)next)(frame);                                \
} while (0)

#define V2_CONCAT_MEASURE_FRAGMENT(name, expected, body)                     \
STENCIL(name)(Lua55NativeFrameV2 *frame)                                     \
{                                                                            \
    V2_VALUE_DISP(cell, V2_SOURCE_DISP_HOLE)                                 \
    V2_LEAF_GUARD(frame, cell, expected);                                    \
    Lua55PreparedConcatV2 *prep = &frame->invocation->prepared_concat;       \
    body;                                                                    \
    V2_CONCAT_FRAGMENT_NEXT(frame);                                          \
}

STENCIL(lua55_v2r_concat_measure_str)(Lua55NativeFrameV2 *frame)
{
    V2_VALUE_DISP(cell, V2_SOURCE_DISP_HOLE)
    V2_LEAF_GUARD_STR(frame, cell);
    Lua55GuestStringV2 *string =
        (Lua55GuestStringV2 *)cell->payload.reference;
    frame->invocation->prepared_concat.total += string->length;
    V2_CONCAT_FRAGMENT_NEXT(frame);
}

V2_CONCAT_MEASURE_FRAGMENT(lua55_v2r_concat_measure_int,
    LUA55_VALUE_INTEGER, {
        char buffer[24];
        prep->total += (uint64_t)v2_itoa_fn_get()(cell->payload.integer, buffer);
    })
V2_CONCAT_MEASURE_FRAGMENT(lua55_v2r_concat_measure_flt,
    LUA55_VALUE_FLOAT, {
        char buffer[32];
        prep->total += (uint64_t)v2_dtoa_fn()(cell->payload.floating, buffer);
    })

STENCIL(lua55_v2r_concat_allocate)(Lua55NativeFrameV2 *frame)
{
    Lua55PreparedConcatV2 *prep = &frame->invocation->prepared_concat;
    Lua55GuestHeapV2 *heap = frame->invocation->heap;
    if (heap == 0 || heap->table_region == 0) {
        V2_REJECT(frame, LUA55_V2_REJECT_INVALID_OBJECT);
        LUA55_CPS_HOST_EXIT(frame);
    }
    size_t bytes_size = prep->total > 0 ? (size_t)prep->total : 1;
    size_t allocation = sizeof(Lua55GuestStringV2) + bytes_size;
    uintptr_t at = v2_heap_bump(heap, allocation);
    if (at == 0) {
        V2_PUBLISH_OVERFLOW(frame, LUA55_V2_OUTCOME_HEAP_OVERFLOW, 0, 0);
        LUA55_CPS_HOST_EXIT(frame);
    }
    Lua55GuestStringV2 *string = (Lua55GuestStringV2 *)at;
    uint8_t *bytes = (uint8_t *)(at + sizeof(Lua55GuestStringV2));
    string->header.kind = prep->total <= V2_MINSTR
        ? LUA55_OBJECT_SHORT_STRING : LUA55_OBJECT_LONG_STRING;
    string->header.generation = heap->object_count + 1;
    string->length = (uint32_t)prep->total;
    string->hash = 0;
    string->bytes = bytes;
    heap->object_count++;
    prep->string = string;
    prep->out = bytes;
    V2_CONCAT_FRAGMENT_NEXT(frame);
}

#define V2_CONCAT_WRITE_FRAGMENT(name, expected, body)                       \
STENCIL(name)(Lua55NativeFrameV2 *frame)                                     \
{                                                                            \
    V2_VALUE_DISP(cell, V2_SOURCE_DISP_HOLE)                                 \
    V2_LEAF_GUARD(frame, cell, expected);                                    \
    Lua55PreparedConcatV2 *prep = &frame->invocation->prepared_concat;       \
    body;                                                                    \
    V2_CONCAT_FRAGMENT_NEXT(frame);                                          \
}

STENCIL(lua55_v2r_concat_write_str)(Lua55NativeFrameV2 *frame)
{
    V2_VALUE_DISP(cell, V2_SOURCE_DISP_HOLE)
    V2_LEAF_GUARD_STR(frame, cell);
    Lua55PreparedConcatV2 *prep = &frame->invocation->prepared_concat;
    Lua55GuestStringV2 *string =
        (Lua55GuestStringV2 *)cell->payload.reference;
    uint32_t count = string->length;
    uint32_t index;
    for (index = 0; index < count; index++)
        prep->out[index] = string->bytes[index];
    prep->out += count;
    V2_CONCAT_FRAGMENT_NEXT(frame);
}

V2_CONCAT_WRITE_FRAGMENT(lua55_v2r_concat_write_int,
    LUA55_VALUE_INTEGER, {
        char buffer[24];
        int count = v2_itoa_fn_get()(cell->payload.integer, buffer);
        int index;
        for (index = 0; index < count; index++) prep->out[index] = (uint8_t)buffer[index];
        prep->out += count;
    })
V2_CONCAT_WRITE_FRAGMENT(lua55_v2r_concat_write_flt,
    LUA55_VALUE_FLOAT, {
        char buffer[32];
        int count = v2_dtoa_fn()(cell->payload.floating, buffer);
        int index;
        for (index = 0; index < count; index++) prep->out[index] = (uint8_t)buffer[index];
        prep->out += count;
    })

STENCIL(lua55_v2r_concat_finish)(Lua55NativeFrameV2 *frame)
{
    V2_VALUE_DISP(target, V2_TARGET_DISP_HOLE)
    Lua55PreparedConcatV2 *prep = &frame->invocation->prepared_concat;
    SET_TAG(target, prep->total <= V2_MINSTR
        ? LUA55_VALUE_SHORT_STRING : LUA55_VALUE_LONG_STRING);
    target->payload.reference = (uintptr_t)prep->string;
    prep->total = 0;
    prep->string = 0;
    prep->out = 0;
    LUA55_RESIDUAL_NEXT(frame);
}

/* ======================================================================= */
/* Batch 8: GETVARG key leaves, RETURN/VARARG static splits, unrolled       */
/* LOADNIL, SETTABUP existing/create, SETLIST in-bounds/grow                */
/* ======================================================================= */

/* ---- GETVARG: exact key-shape leaves ----------------------------------- */
STENCIL(lua55_v2r_getvarg_int)(Lua55NativeFrameV2 *frame)
{
    V2_VALUE_DISP(target, V2_TARGET_DISP_HOLE)
    V2_VALUE_DISP(key, V2_KEY_DISP_HOLE)
    V2_LEAF_GUARD(frame, key, LUA55_VALUE_INTEGER);
    int64_t n = key->payload.integer;
    uint32_t nargs = frame->vararg_count;
    if (n >= 1 && (uint64_t)n <= nargs) {
        Lua55ValueV2 *slice = frame->values + frame->value_capacity;
        *target = slice[n - 1];
    } else {
        SET_TAG(target, LUA55_VALUE_NIL);
        target->payload.reference = 0;
    }
    LUA55_RESIDUAL_NEXT(frame);
}

STENCIL(lua55_v2r_getvarg_n)(Lua55NativeFrameV2 *frame)
{
    V2_VALUE_DISP(target, V2_TARGET_DISP_HOLE)
    V2_VALUE_DISP(key, V2_KEY_DISP_HOLE)
    V2_LEAF_GUARD_STR(frame, key);
    Lua55GuestStringV2 *str = (Lua55GuestStringV2 *)key->payload.reference;
    if (str == 0 || str->length != 1 || str->bytes[0] != 'n') {
        V2_SPEC_MISMATCH(frame, LUA55_VALUE_SHORT_STRING, LUA55_VALUE_INTEGER);
        V2_SPECIALIZATION_MISMATCH_EXIT(frame);
    }
    SET_TAG(target, LUA55_VALUE_INTEGER);
    target->payload.integer = (int64_t)frame->vararg_count;
    LUA55_RESIDUAL_NEXT(frame);
}

STENCIL(lua55_v2r_getvarg_mx)(Lua55NativeFrameV2 *frame)
{
    V2_VALUE_DISP(target, V2_TARGET_DISP_HOLE)
    V2_VALUE_DISP(key, V2_KEY_DISP_HOLE)
    if (key->tag == LUA55_VALUE_INTEGER) {
        V2_SPEC_MISMATCH(frame, LUA55_VALUE_NIL, key->tag);
        V2_SPECIALIZATION_MISMATCH_EXIT(frame);
    }
    if (v2_is_string_tag(key->tag)) {
        Lua55GuestStringV2 *str = (Lua55GuestStringV2 *)key->payload.reference;
        if (str != 0 && str->length == 1 && str->bytes[0] == 'n') {
            V2_SPEC_MISMATCH(frame, LUA55_VALUE_NIL, key->tag);
            V2_SPECIALIZATION_MISMATCH_EXIT(frame);
        }
    }
    SET_TAG(target, LUA55_VALUE_NIL);
    target->payload.reference = 0;
    LUA55_RESIDUAL_NEXT(frame);
}

/* ---- RETURN: fixed (B >= 2, baked count) vs all (B == 0) --------------- */
#define V2_RETURN_SPLIT(name, nres_expr)                                    \
STENCIL(name)(Lua55NativeFrameV2 *frame)                                    \
{                                                                           \
    V2_HOLE32(A, V2_A_HOLE); V2_HOLE32(pc, V2_PC_HOLE);                     \
    V2_VALUE_DISP(source, V2_BASE_DISP_HOLE)                                 \
    int32_t nres = nres_expr;                                               \
    if (nres < 0) nres = 0;                                                 \
    Lua55NativeResultSinkV2 sink = frame->result_sink;                      \
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
            sink.values[i] = source[i];                                      \
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
    inv->outcome.result_count = (uint32_t)(sink.count >= 0                  \
        ? (uint32_t)sink.count : (uint32_t)count);                          \
    if (inv->current_frame == frame) {                                      \
        inv->frame_next = (uint8_t *)frame;                                 \
        inv->current_frame = frame->caller;                                 \
    }                                                                       \
    Lua55NativeEntryV2 cont = frame->return_link.entry;                     \
    Lua55NativeFrameV2 *subject = frame->return_link.subject;               \
    return cont(subject);                                                   \
}

STENCIL(lua55_v2r_ret_fixed_begin)(Lua55NativeFrameV2 *frame)
{
    V2_HOLE32(nres, V2_SPAN_HOLE);
    V2_HOLE32(pc, V2_PC_HOLE);
    Lua55NativeResultSinkV2 sink = frame->result_sink;
    int32_t count = sink.count >= 0
        ? (sink.count < (int32_t)nres ? sink.count : (int32_t)nres)
        : (int32_t)nres;
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
    }
    LUA55_RESIDUAL_NEXT(frame);
}

/* Exact one-result RETURN leaf with a narrow fixed-one sink hot path. Sink
   width and open-upvalue state are mutable call protocol data, not learned
   semantic siblings. */
STENCIL(lua55_v2r_ret_fixed_one)(Lua55NativeFrameV2 *frame)
{
    V2_VALUE_DISP(source, V2_SOURCE_DISP_HOLE)
    V2_HOLE32(pc, V2_PC_HOLE);
    Lua55NativeResultSinkV2 sink = frame->result_sink;
    if (__builtin_expect(sink.values != 0 && sink.count == 1
            && frame->open_upvalues == 0, 1)) {
        if (__builtin_expect(sink.base + 1 > sink.capacity, 0)) {
            frame->invocation->outcome.discriminant =
                LUA55_V2_OUTCOME_VALUE_OVERFLOW;
            frame->invocation->outcome.u.overflow.required = sink.base + 1;
            frame->invocation->outcome.u.overflow.available = sink.capacity;
            frame->invocation->outcome.u.overflow.pc = pc;
            LUA55_CPS_HOST_EXIT(frame);
        }
        sink.values[0] = *source;
        *sink.top = sink.base + 1;
        Lua55NativeInvocationV2 *inv = frame->invocation;
        inv->outcome.discriminant = LUA55_V2_OUTCOME_RETURNED;
        inv->outcome.result_count = 1;
        if (inv->current_frame == frame) {
            inv->frame_next = (uint8_t *)frame;
            inv->current_frame = frame->caller;
        }
        return frame->return_link.entry(frame->return_link.subject);
    }
    uint32_t needed = sink.base + (uint32_t)(sink.count >= 0 ? sink.count : 1);
    if (sink.values != 0 && needed > sink.capacity) {
        frame->invocation->outcome.discriminant = LUA55_V2_OUTCOME_VALUE_OVERFLOW;
        frame->invocation->outcome.u.overflow.required = needed;
        frame->invocation->outcome.u.overflow.available = sink.capacity;
        frame->invocation->outcome.u.overflow.pc = pc;
        LUA55_CPS_HOST_EXIT(frame);
    }
    if (sink.values != 0) {
        if (sink.count != 0) sink.values[0] = *source;
        if (sink.count > 1) {
            int32_t i;
            for (i = 1; i < sink.count; i++) SET_TAG(&sink.values[i], LUA55_VALUE_NIL);
        }
        *sink.top = needed;
    }
    lua55_cps_close_open_upvalues(frame);
    Lua55NativeInvocationV2 *inv = frame->invocation;
    inv->outcome.discriminant = LUA55_V2_OUTCOME_RETURNED;
    inv->outcome.result_count = sink.count >= 0 ? (uint32_t)sink.count : 1;
    if (inv->current_frame == frame) {
        inv->frame_next = (uint8_t *)frame;
        inv->current_frame = frame->caller;
    }
    return frame->return_link.entry(frame->return_link.subject);
}

STENCIL(lua55_v2r_ret_fixed_slot)(Lua55NativeFrameV2 *frame)
{
    V2_VALUE_DISP(source, V2_SOURCE_DISP_HOLE)
    V2_HOLE32(slot, V2_SPAN_HOLE);
    Lua55NativeResultSinkV2 sink = frame->result_sink;
    if (sink.values != 0 && (sink.count < 0 || slot < (uint32_t)sink.count))
        sink.values[slot] = *source;
    LUA55_RESIDUAL_NEXT(frame);
}

STENCIL(lua55_v2r_ret_fixed_finish)(Lua55NativeFrameV2 *frame)
{
    V2_HOLE32(nres, V2_SPAN_HOLE);
    Lua55NativeResultSinkV2 sink = frame->result_sink;
    if (sink.values != 0) {
        if (sink.count >= 0) {
            int32_t i;
            for (i = (int32_t)nres; i < sink.count; i++)
                SET_TAG(&sink.values[i], LUA55_VALUE_NIL);
            *sink.top = sink.base + (uint32_t)sink.count;
        } else {
            *sink.top = sink.base + nres;
        }
    }
    lua55_cps_close_open_upvalues(frame);
    Lua55NativeInvocationV2 *inv = frame->invocation;
    inv->outcome.discriminant = LUA55_V2_OUTCOME_RETURNED;
    inv->outcome.result_count = sink.count >= 0 ? (uint32_t)sink.count : nres;
    if (inv->current_frame == frame) {
        inv->frame_next = (uint8_t *)frame;
        inv->current_frame = frame->caller;
    }
    Lua55NativeEntryV2 cont = frame->return_link.entry;
    Lua55NativeFrameV2 *subject = frame->return_link.subject;
    return cont(subject);
}
V2_RETURN_SPLIT(lua55_v2r_ret_all, (int32_t)frame->top - (int32_t)A)

/* ---- VARARG: fixed (wanted >= 0) vs all (wanted == -1) ----------------- */
#define V2_VARARG_SPLIT(name, wanted_expr, is_all)                          \
STENCIL(name)(Lua55NativeFrameV2 *frame)                                    \
{                                                                           \
    V2_HOLE32(target_reg, V2_TARGET_HOLE);                                  \
    V2_VALUE_DISP(target, V2_TARGET_DISP_HOLE)                              \
    int32_t wanted = wanted_expr;                                           \
    __asm__ volatile ("" : "+r"(wanted));                                   \
    uint32_t nargs = frame->vararg_count;                                   \
    uint32_t touse = (is_all) ? nargs                                       \
        : (nargs > (uint32_t)wanted ? (uint32_t)wanted : nargs);            \
    Lua55ValueV2 *slice = frame->values + frame->value_capacity;            \
    uint32_t i;                                                             \
    for (i = 0; i < touse; i++)                                             \
        target[i] = slice[i];                                               \
    if (!(is_all)) {                                                        \
        for (i = touse; i < (uint32_t)wanted; i++)                          \
            SET_TAG(&target[i], LUA55_VALUE_NIL);                           \
        frame->top = target_reg + (uint32_t)wanted;                         \
    } else {                                                                \
        frame->top = target_reg + touse;                                    \
    }                                                                       \
    LUA55_RESIDUAL_NEXT(frame);                                             \
}

STENCIL(lua55_v2r_vararg_fixed_slot)(Lua55NativeFrameV2 *frame)
{
    V2_VALUE_DISP(target, V2_TARGET_DISP_HOLE)
    V2_HOLE32(slot, V2_SPAN_HOLE);
    if (slot < frame->vararg_count) {
        Lua55ValueV2 *slice = frame->values + frame->value_capacity;
        *target = slice[slot];
    } else {
        SET_TAG(target, LUA55_VALUE_NIL);
        target->payload.reference = 0;
    }
    LUA55_RESIDUAL_NEXT(frame);
}

STENCIL(lua55_v2r_vararg_fixed_finish)(Lua55NativeFrameV2 *frame)
{
    V2_HOLE32(top_index, V2_TOP_INDEX_HOLE);
    frame->top = top_index;
    LUA55_RESIDUAL_NEXT(frame);
}
V2_VARARG_SPLIT(lua55_v2r_vararg_all, (int32_t)(-1), 1)

/* ---- LOADNIL: exact unrolled span leaves (1..8) ------------------------ */
#define V2_NIL_1(target) SET_TAG(&(target)[0], LUA55_VALUE_NIL);
#define V2_NIL_2(target) V2_NIL_1(target) SET_TAG(&(target)[1], LUA55_VALUE_NIL);
#define V2_NIL_3(target) V2_NIL_2(target) SET_TAG(&(target)[2], LUA55_VALUE_NIL);
#define V2_NIL_4(target) V2_NIL_3(target) SET_TAG(&(target)[3], LUA55_VALUE_NIL);
#define V2_NIL_5(target) V2_NIL_4(target) SET_TAG(&(target)[4], LUA55_VALUE_NIL);
#define V2_NIL_6(target) V2_NIL_5(target) SET_TAG(&(target)[5], LUA55_VALUE_NIL);
#define V2_NIL_7(target) V2_NIL_6(target) SET_TAG(&(target)[6], LUA55_VALUE_NIL);
#define V2_NIL_8(target) V2_NIL_7(target) SET_TAG(&(target)[7], LUA55_VALUE_NIL);
#define V2_LOADNIL_UNROLL(name, stores)                                     \
STENCIL(name)(Lua55NativeFrameV2 *frame)                                    \
{                                                                           \
    V2_VALUE_DISP(target, V2_TARGET_DISP_HOLE)                              \
    stores(target)                                                          \
    LUA55_RESIDUAL_NEXT(frame);                                             \
}
V2_LOADNIL_UNROLL(lua55_v2r_loadnil_1, V2_NIL_1)
V2_LOADNIL_UNROLL(lua55_v2r_loadnil_2, V2_NIL_2)
V2_LOADNIL_UNROLL(lua55_v2r_loadnil_3, V2_NIL_3)
V2_LOADNIL_UNROLL(lua55_v2r_loadnil_4, V2_NIL_4)
V2_LOADNIL_UNROLL(lua55_v2r_loadnil_5, V2_NIL_5)
V2_LOADNIL_UNROLL(lua55_v2r_loadnil_6, V2_NIL_6)
V2_LOADNIL_UNROLL(lua55_v2r_loadnil_7, V2_NIL_7)
V2_LOADNIL_UNROLL(lua55_v2r_loadnil_8, V2_NIL_8)

/* ---- SETTABUP: exact key with mutable NeedCreate data exit -------------- */
STENCIL(lua55_v2r_settabup_existing)(Lua55NativeFrameV2 *frame)
{
    V2_HOLE32(upvalue_reg, V2_UPVALUE_HOLE);
    V2_VALUE_DISP(src, V2_SOURCE_DISP_HOLE)
    uint64_t key_ref = (uint64_t)V2_KEY_REF_HOLE;
    __asm__ volatile ("" : "+r"(key_ref));
    uint64_t create = V2_NEED_CREATE_LINK_HOLE;
    __asm__ volatile ("" : "+r"(create));
    Lua55UpvalueCellV2 *cell0 = frame->upvalues[upvalue_reg];
    Lua55ValueV2 *value = cell0->state == LUA55_UPVALUE_OPEN
        ? cell0->open_slot : &cell0->closed_value;
    Lua55GuestTableV2 *table = v2_learn_table(frame, value);
    if (table == 0) V2_TABLE_REJECT(frame, LUA55_V2_REJECT_INVALID_OBJECT);
    V2_FIELD_SLOT_LOCATION(table, key_ref, field)
    if (field->occupied) { v2_table_set(table, &field->value, src);
        LUA55_RESIDUAL_NEXT(frame); }
    return ((Lua55NativeEntryV2)create)(frame);
}

STENCIL(lua55_v2r_settabup_create)(Lua55NativeFrameV2 *frame)
{
    V2_HOLE32(upvalue_reg, V2_UPVALUE_HOLE);
    V2_VALUE_DISP(src, V2_SOURCE_DISP_HOLE)
    uint64_t key_ref = (uint64_t)V2_KEY_REF_HOLE;
    __asm__ volatile ("" : "+r"(key_ref));
    uint64_t succ = V2_RESUME_LINK_HOLE;
    __asm__ volatile ("" : "+r"(succ));
    Lua55UpvalueCellV2 *cell0 = frame->upvalues[upvalue_reg];
    Lua55ValueV2 *value = cell0->state == LUA55_UPVALUE_OPEN
        ? cell0->open_slot : &cell0->closed_value;
    Lua55GuestTableV2 *table = v2_learn_table(frame, value);
    if (table == 0) V2_TABLE_REJECT(frame, LUA55_V2_REJECT_INVALID_OBJECT);
    V2_FIELD_SLOT_LOCATION(table, key_ref, field)
    Lua55ValueV2 *cell = field->occupied ? &field->value
        : v2_find_field(table, (uintptr_t)key_ref, 1);
    if (cell == &field->value) { v2_table_set(table, cell, src);
        return ((Lua55NativeEntryV2)succ)(frame); }
    V2_SPEC_MISMATCH(frame, field_slot, table->field_capacity);
    V2_SPECIALIZATION_MISMATCH_EXIT(frame);
}

/* ---- SETLIST: exact values with mutable NeedGrow data exit -------------- */
STENCIL(lua55_v2r_setlist_inbounds)(Lua55NativeFrameV2 *frame)
{
    V2_VALUE_DISP(base, V2_BASE_DISP_HOLE)
    V2_HOLE32(count, V2_SETLIST_COUNT_HOLE);
    int64_t key_base = (int64_t)V2_SETLIST_KEY_HOLE;
    __asm__ volatile ("" : "+r"(key_base));
    uint64_t grow = V2_NEED_GROW_LINK_HOLE;
    __asm__ volatile ("" : "+r"(grow));
    Lua55ValueV2 *table_cell = &base[0];
    Lua55GuestTableV2 *table = v2_learn_table(frame, table_cell);
    if (table == 0) V2_TABLE_REJECT(frame, LUA55_V2_REJECT_INVALID_OBJECT);
    if (count == 0) V2_TABLE_REJECT(frame, LUA55_V2_REJECT_INVALID_OBJECT);
    if ((uint64_t)(key_base + count) > table->array_capacity)
        return ((Lua55NativeEntryV2)grow)(frame);
    LUA55_RESIDUAL_NEXT(frame);
}

STENCIL(lua55_v2r_setlist_grow)(Lua55NativeFrameV2 *frame)
{
    V2_VALUE_DISP(base, V2_BASE_DISP_HOLE)
    V2_HOLE32(count, V2_SETLIST_COUNT_HOLE);
    int64_t key_base = (int64_t)V2_SETLIST_KEY_HOLE;
    __asm__ volatile ("" : "+r"(key_base));
    uint64_t succ = V2_RESUME_LINK_HOLE;
    __asm__ volatile ("" : "+r"(succ));
    Lua55ValueV2 *table_cell = &base[0];
    Lua55GuestTableV2 *table = v2_learn_table(frame, table_cell);
    if (table == 0) V2_TABLE_REJECT(frame, LUA55_V2_REJECT_INVALID_OBJECT);
    if (count == 0) V2_TABLE_REJECT(frame, LUA55_V2_REJECT_INVALID_OBJECT);
    if (!v2_grow_array(frame, table, (uint64_t)(key_base + count))) {
        V2_PUBLISH_OVERFLOW(frame, LUA55_V2_OUTCOME_HEAP_OVERFLOW, 0, 0);
        LUA55_CPS_HOST_EXIT(frame);
    }
    return ((Lua55NativeEntryV2)succ)(frame);
}

STENCIL(lua55_v2r_setlist_slot)(Lua55NativeFrameV2 *frame)
{
    V2_VALUE_DISP(base, V2_BASE_DISP_HOLE)
    V2_VALUE_DISP(source, V2_SOURCE_DISP_HOLE)
    Lua55GuestTableV2 *table =
        (Lua55GuestTableV2 *)base->payload.reference;
    V2_VALUE_BASE_DISP(cell, table->array_values, V2_ARRAY_DISP_HOLE)
    v2_table_set(table, cell, source);
    LUA55_RESIDUAL_NEXT(frame);
}

/* ---- SETTABUP const-value leaves with mutable NeedCreate exit ----------- */
#define V2_SETTABUP_CONST_LEAF(name, store)                                 \
STENCIL(lua55_v2r_##name##_existing)(Lua55NativeFrameV2 *frame)             \
{                                                                           \
    V2_HOLE32(upvalue_reg, V2_UPVALUE_HOLE);                                \
    uint64_t key_ref = (uint64_t)V2_KEY_REF_HOLE;                           \
    __asm__ volatile ("" : "+r"(key_ref));                                  \
    uint64_t create = V2_NEED_CREATE_LINK_HOLE;                             \
    __asm__ volatile ("" : "+r"(create));                                   \
    Lua55UpvalueCellV2 *cell0 = frame->upvalues[upvalue_reg];               \
    Lua55ValueV2 *value = cell0->state == LUA55_UPVALUE_OPEN                \
        ? cell0->open_slot : &cell0->closed_value;                          \
    Lua55GuestTableV2 *table = v2_learn_table(frame, value);                \
    if (table == 0) V2_TABLE_REJECT(frame, LUA55_V2_REJECT_INVALID_OBJECT); \
    V2_FIELD_SLOT_LOCATION(table, key_ref, field)                            \
    if (field->occupied) { store(&field->value); LUA55_RESIDUAL_NEXT(frame); } \
    return ((Lua55NativeEntryV2)create)(frame);                             \
}                                                                           \
STENCIL(lua55_v2r_##name##_create)(Lua55NativeFrameV2 *frame)               \
{                                                                           \
    V2_HOLE32(upvalue_reg, V2_UPVALUE_HOLE);                                \
    uint64_t key_ref = (uint64_t)V2_KEY_REF_HOLE;                           \
    __asm__ volatile ("" : "+r"(key_ref));                                  \
    uint64_t succ = V2_RESUME_LINK_HOLE;                                    \
    __asm__ volatile ("" : "+r"(succ));                                     \
    Lua55UpvalueCellV2 *cell0 = frame->upvalues[upvalue_reg];               \
    Lua55ValueV2 *value = cell0->state == LUA55_UPVALUE_OPEN                \
        ? cell0->open_slot : &cell0->closed_value;                          \
    Lua55GuestTableV2 *table = v2_learn_table(frame, value);                \
    if (table == 0) V2_TABLE_REJECT(frame, LUA55_V2_REJECT_INVALID_OBJECT); \
    V2_FIELD_SLOT_LOCATION(table, key_ref, field)                            \
    Lua55ValueV2 *cell = field->occupied ? &field->value                    \
        : v2_find_field(table, (uintptr_t)key_ref, 1);                       \
    if (cell == &field->value) { store(cell);                               \
        return ((Lua55NativeEntryV2)succ)(frame); }                         \
    V2_SPEC_MISMATCH(frame, field_slot, table->field_capacity);             \
    V2_SPECIALIZATION_MISMATCH_EXIT(frame);                                             \
}

V2_SETTABUP_CONST_LEAF(settabup_const_nil, V2_STORE_NIL)
V2_SETTABUP_CONST_LEAF(settabup_const_false, V2_STORE_FALSE)
V2_SETTABUP_CONST_LEAF(settabup_const_true, V2_STORE_TRUE)
V2_SETTABUP_CONST_LEAF(settabup_const_int, V2_STORE_INT)
V2_SETTABUP_CONST_LEAF(settabup_const_flt, V2_STORE_FLT)
V2_SETTABUP_CONST_LEAF(settabup_const_str, V2_STORE_STR)
#if 0 /* S10 retired Cartesian CONCAT width/vector leaves */
#define V2_CONCAT_LEAF_4(name, s0, s1, s2, s3)                                      \
STENCIL(name)(Lua55NativeFrameV2 *frame)                                    \
{\
    V2_HOLE32(base, V2_SETLIST_BASE_HOLE);                                  \
    V2_CONCAT_GUARD_##s0(&frame->values[base + 0]); \
    V2_CONCAT_GUARD_##s1(&frame->values[base + 1]); \
    V2_CONCAT_GUARD_##s2(&frame->values[base + 2]); \
    V2_CONCAT_GUARD_##s3(&frame->values[base + 3]); \
    uint64_t total = 0;                                                     \
    V2_CONCAT_MEASURE_##s0(&frame->values[base + 0]); \
    V2_CONCAT_MEASURE_##s1(&frame->values[base + 1]); \
    V2_CONCAT_MEASURE_##s2(&frame->values[base + 2]); \
    V2_CONCAT_MEASURE_##s3(&frame->values[base + 3]); \
    V2_CONCAT_ALLOC()                                                       \
    uint8_t *out = bytes;                                                   \
    V2_CONCAT_WRITE_##s0(&frame->values[base + 0]); \
    V2_CONCAT_WRITE_##s1(&frame->values[base + 1]); \
    V2_CONCAT_WRITE_##s2(&frame->values[base + 2]); \
    V2_CONCAT_WRITE_##s3(&frame->values[base + 3]); \
    Lua55ValueV2 *target = &frame->values[base];                            \
    SET_TAG(target, total <= V2_MINSTR                                      \
        ? LUA55_VALUE_SHORT_STRING : LUA55_VALUE_LONG_STRING);              \
    target->payload.reference = (uintptr_t)str;                             \
    LUA55_RESIDUAL_NEXT(frame);                                             \
}

V2_CONCAT_LEAF_4(lua55_v2r_concat_4_ssss, STR, STR, STR, STR)
V2_CONCAT_LEAF_4(lua55_v2r_concat_4_sssi, STR, STR, STR, INT)
V2_CONCAT_LEAF_4(lua55_v2r_concat_4_sssf, STR, STR, STR, FLT)
V2_CONCAT_LEAF_4(lua55_v2r_concat_4_ssis, STR, STR, INT, STR)
V2_CONCAT_LEAF_4(lua55_v2r_concat_4_ssii, STR, STR, INT, INT)
V2_CONCAT_LEAF_4(lua55_v2r_concat_4_ssif, STR, STR, INT, FLT)
V2_CONCAT_LEAF_4(lua55_v2r_concat_4_ssfs, STR, STR, FLT, STR)
V2_CONCAT_LEAF_4(lua55_v2r_concat_4_ssfi, STR, STR, FLT, INT)
V2_CONCAT_LEAF_4(lua55_v2r_concat_4_ssff, STR, STR, FLT, FLT)
V2_CONCAT_LEAF_4(lua55_v2r_concat_4_siss, STR, INT, STR, STR)
V2_CONCAT_LEAF_4(lua55_v2r_concat_4_sisi, STR, INT, STR, INT)
V2_CONCAT_LEAF_4(lua55_v2r_concat_4_sisf, STR, INT, STR, FLT)
V2_CONCAT_LEAF_4(lua55_v2r_concat_4_siis, STR, INT, INT, STR)
V2_CONCAT_LEAF_4(lua55_v2r_concat_4_siii, STR, INT, INT, INT)
V2_CONCAT_LEAF_4(lua55_v2r_concat_4_siif, STR, INT, INT, FLT)
V2_CONCAT_LEAF_4(lua55_v2r_concat_4_sifs, STR, INT, FLT, STR)
V2_CONCAT_LEAF_4(lua55_v2r_concat_4_sifi, STR, INT, FLT, INT)
V2_CONCAT_LEAF_4(lua55_v2r_concat_4_siff, STR, INT, FLT, FLT)
V2_CONCAT_LEAF_4(lua55_v2r_concat_4_sfss, STR, FLT, STR, STR)
V2_CONCAT_LEAF_4(lua55_v2r_concat_4_sfsi, STR, FLT, STR, INT)
V2_CONCAT_LEAF_4(lua55_v2r_concat_4_sfsf, STR, FLT, STR, FLT)
V2_CONCAT_LEAF_4(lua55_v2r_concat_4_sfis, STR, FLT, INT, STR)
V2_CONCAT_LEAF_4(lua55_v2r_concat_4_sfii, STR, FLT, INT, INT)
V2_CONCAT_LEAF_4(lua55_v2r_concat_4_sfif, STR, FLT, INT, FLT)
V2_CONCAT_LEAF_4(lua55_v2r_concat_4_sffs, STR, FLT, FLT, STR)
V2_CONCAT_LEAF_4(lua55_v2r_concat_4_sffi, STR, FLT, FLT, INT)
V2_CONCAT_LEAF_4(lua55_v2r_concat_4_sfff, STR, FLT, FLT, FLT)
V2_CONCAT_LEAF_4(lua55_v2r_concat_4_isss, INT, STR, STR, STR)
V2_CONCAT_LEAF_4(lua55_v2r_concat_4_issi, INT, STR, STR, INT)
V2_CONCAT_LEAF_4(lua55_v2r_concat_4_issf, INT, STR, STR, FLT)
V2_CONCAT_LEAF_4(lua55_v2r_concat_4_isis, INT, STR, INT, STR)
V2_CONCAT_LEAF_4(lua55_v2r_concat_4_isii, INT, STR, INT, INT)
V2_CONCAT_LEAF_4(lua55_v2r_concat_4_isif, INT, STR, INT, FLT)
V2_CONCAT_LEAF_4(lua55_v2r_concat_4_isfs, INT, STR, FLT, STR)
V2_CONCAT_LEAF_4(lua55_v2r_concat_4_isfi, INT, STR, FLT, INT)
V2_CONCAT_LEAF_4(lua55_v2r_concat_4_isff, INT, STR, FLT, FLT)
V2_CONCAT_LEAF_4(lua55_v2r_concat_4_iiss, INT, INT, STR, STR)
V2_CONCAT_LEAF_4(lua55_v2r_concat_4_iisi, INT, INT, STR, INT)
V2_CONCAT_LEAF_4(lua55_v2r_concat_4_iisf, INT, INT, STR, FLT)
V2_CONCAT_LEAF_4(lua55_v2r_concat_4_iiis, INT, INT, INT, STR)
V2_CONCAT_LEAF_4(lua55_v2r_concat_4_iiii, INT, INT, INT, INT)
V2_CONCAT_LEAF_4(lua55_v2r_concat_4_iiif, INT, INT, INT, FLT)
V2_CONCAT_LEAF_4(lua55_v2r_concat_4_iifs, INT, INT, FLT, STR)
V2_CONCAT_LEAF_4(lua55_v2r_concat_4_iifi, INT, INT, FLT, INT)
V2_CONCAT_LEAF_4(lua55_v2r_concat_4_iiff, INT, INT, FLT, FLT)
V2_CONCAT_LEAF_4(lua55_v2r_concat_4_ifss, INT, FLT, STR, STR)
V2_CONCAT_LEAF_4(lua55_v2r_concat_4_ifsi, INT, FLT, STR, INT)
V2_CONCAT_LEAF_4(lua55_v2r_concat_4_ifsf, INT, FLT, STR, FLT)
V2_CONCAT_LEAF_4(lua55_v2r_concat_4_ifis, INT, FLT, INT, STR)
V2_CONCAT_LEAF_4(lua55_v2r_concat_4_ifii, INT, FLT, INT, INT)
V2_CONCAT_LEAF_4(lua55_v2r_concat_4_ifif, INT, FLT, INT, FLT)
V2_CONCAT_LEAF_4(lua55_v2r_concat_4_iffs, INT, FLT, FLT, STR)
V2_CONCAT_LEAF_4(lua55_v2r_concat_4_iffi, INT, FLT, FLT, INT)
V2_CONCAT_LEAF_4(lua55_v2r_concat_4_ifff, INT, FLT, FLT, FLT)
V2_CONCAT_LEAF_4(lua55_v2r_concat_4_fsss, FLT, STR, STR, STR)
V2_CONCAT_LEAF_4(lua55_v2r_concat_4_fssi, FLT, STR, STR, INT)
V2_CONCAT_LEAF_4(lua55_v2r_concat_4_fssf, FLT, STR, STR, FLT)
V2_CONCAT_LEAF_4(lua55_v2r_concat_4_fsis, FLT, STR, INT, STR)
V2_CONCAT_LEAF_4(lua55_v2r_concat_4_fsii, FLT, STR, INT, INT)
V2_CONCAT_LEAF_4(lua55_v2r_concat_4_fsif, FLT, STR, INT, FLT)
V2_CONCAT_LEAF_4(lua55_v2r_concat_4_fsfs, FLT, STR, FLT, STR)
V2_CONCAT_LEAF_4(lua55_v2r_concat_4_fsfi, FLT, STR, FLT, INT)
V2_CONCAT_LEAF_4(lua55_v2r_concat_4_fsff, FLT, STR, FLT, FLT)
V2_CONCAT_LEAF_4(lua55_v2r_concat_4_fiss, FLT, INT, STR, STR)
V2_CONCAT_LEAF_4(lua55_v2r_concat_4_fisi, FLT, INT, STR, INT)
V2_CONCAT_LEAF_4(lua55_v2r_concat_4_fisf, FLT, INT, STR, FLT)
V2_CONCAT_LEAF_4(lua55_v2r_concat_4_fiis, FLT, INT, INT, STR)
V2_CONCAT_LEAF_4(lua55_v2r_concat_4_fiii, FLT, INT, INT, INT)
V2_CONCAT_LEAF_4(lua55_v2r_concat_4_fiif, FLT, INT, INT, FLT)
V2_CONCAT_LEAF_4(lua55_v2r_concat_4_fifs, FLT, INT, FLT, STR)
V2_CONCAT_LEAF_4(lua55_v2r_concat_4_fifi, FLT, INT, FLT, INT)
V2_CONCAT_LEAF_4(lua55_v2r_concat_4_fiff, FLT, INT, FLT, FLT)
V2_CONCAT_LEAF_4(lua55_v2r_concat_4_ffss, FLT, FLT, STR, STR)
V2_CONCAT_LEAF_4(lua55_v2r_concat_4_ffsi, FLT, FLT, STR, INT)
V2_CONCAT_LEAF_4(lua55_v2r_concat_4_ffsf, FLT, FLT, STR, FLT)
V2_CONCAT_LEAF_4(lua55_v2r_concat_4_ffis, FLT, FLT, INT, STR)
V2_CONCAT_LEAF_4(lua55_v2r_concat_4_ffii, FLT, FLT, INT, INT)
V2_CONCAT_LEAF_4(lua55_v2r_concat_4_ffif, FLT, FLT, INT, FLT)
V2_CONCAT_LEAF_4(lua55_v2r_concat_4_fffs, FLT, FLT, FLT, STR)
V2_CONCAT_LEAF_4(lua55_v2r_concat_4_fffi, FLT, FLT, FLT, INT)
V2_CONCAT_LEAF_4(lua55_v2r_concat_4_ffff, FLT, FLT, FLT, FLT)
#define V2_CONCAT_LEAF_5(name, s0, s1, s2, s3, s4)                                      \
STENCIL(name)(Lua55NativeFrameV2 *frame)                                    \
{\
    V2_HOLE32(base, V2_SETLIST_BASE_HOLE);                                  \
    V2_CONCAT_GUARD_##s0(&frame->values[base + 0]); \
    V2_CONCAT_GUARD_##s1(&frame->values[base + 1]); \
    V2_CONCAT_GUARD_##s2(&frame->values[base + 2]); \
    V2_CONCAT_GUARD_##s3(&frame->values[base + 3]); \
    V2_CONCAT_GUARD_##s4(&frame->values[base + 4]); \
    uint64_t total = 0;                                                     \
    V2_CONCAT_MEASURE_##s0(&frame->values[base + 0]); \
    V2_CONCAT_MEASURE_##s1(&frame->values[base + 1]); \
    V2_CONCAT_MEASURE_##s2(&frame->values[base + 2]); \
    V2_CONCAT_MEASURE_##s3(&frame->values[base + 3]); \
    V2_CONCAT_MEASURE_##s4(&frame->values[base + 4]); \
    V2_CONCAT_ALLOC()                                                       \
    uint8_t *out = bytes;                                                   \
    V2_CONCAT_WRITE_##s0(&frame->values[base + 0]); \
    V2_CONCAT_WRITE_##s1(&frame->values[base + 1]); \
    V2_CONCAT_WRITE_##s2(&frame->values[base + 2]); \
    V2_CONCAT_WRITE_##s3(&frame->values[base + 3]); \
    V2_CONCAT_WRITE_##s4(&frame->values[base + 4]); \
    Lua55ValueV2 *target = &frame->values[base];                            \
    SET_TAG(target, total <= V2_MINSTR                                      \
        ? LUA55_VALUE_SHORT_STRING : LUA55_VALUE_LONG_STRING);              \
    target->payload.reference = (uintptr_t)str;                             \
    LUA55_RESIDUAL_NEXT(frame);                                             \
}

V2_CONCAT_LEAF_5(lua55_v2r_concat_5_sssss, STR, STR, STR, STR, STR)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_ssssi, STR, STR, STR, STR, INT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_ssssf, STR, STR, STR, STR, FLT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_sssis, STR, STR, STR, INT, STR)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_sssii, STR, STR, STR, INT, INT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_sssif, STR, STR, STR, INT, FLT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_sssfs, STR, STR, STR, FLT, STR)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_sssfi, STR, STR, STR, FLT, INT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_sssff, STR, STR, STR, FLT, FLT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_ssiss, STR, STR, INT, STR, STR)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_ssisi, STR, STR, INT, STR, INT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_ssisf, STR, STR, INT, STR, FLT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_ssiis, STR, STR, INT, INT, STR)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_ssiii, STR, STR, INT, INT, INT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_ssiif, STR, STR, INT, INT, FLT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_ssifs, STR, STR, INT, FLT, STR)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_ssifi, STR, STR, INT, FLT, INT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_ssiff, STR, STR, INT, FLT, FLT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_ssfss, STR, STR, FLT, STR, STR)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_ssfsi, STR, STR, FLT, STR, INT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_ssfsf, STR, STR, FLT, STR, FLT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_ssfis, STR, STR, FLT, INT, STR)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_ssfii, STR, STR, FLT, INT, INT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_ssfif, STR, STR, FLT, INT, FLT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_ssffs, STR, STR, FLT, FLT, STR)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_ssffi, STR, STR, FLT, FLT, INT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_ssfff, STR, STR, FLT, FLT, FLT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_sisss, STR, INT, STR, STR, STR)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_sissi, STR, INT, STR, STR, INT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_sissf, STR, INT, STR, STR, FLT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_sisis, STR, INT, STR, INT, STR)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_sisii, STR, INT, STR, INT, INT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_sisif, STR, INT, STR, INT, FLT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_sisfs, STR, INT, STR, FLT, STR)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_sisfi, STR, INT, STR, FLT, INT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_sisff, STR, INT, STR, FLT, FLT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_siiss, STR, INT, INT, STR, STR)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_siisi, STR, INT, INT, STR, INT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_siisf, STR, INT, INT, STR, FLT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_siiis, STR, INT, INT, INT, STR)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_siiii, STR, INT, INT, INT, INT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_siiif, STR, INT, INT, INT, FLT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_siifs, STR, INT, INT, FLT, STR)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_siifi, STR, INT, INT, FLT, INT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_siiff, STR, INT, INT, FLT, FLT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_sifss, STR, INT, FLT, STR, STR)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_sifsi, STR, INT, FLT, STR, INT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_sifsf, STR, INT, FLT, STR, FLT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_sifis, STR, INT, FLT, INT, STR)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_sifii, STR, INT, FLT, INT, INT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_sifif, STR, INT, FLT, INT, FLT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_siffs, STR, INT, FLT, FLT, STR)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_siffi, STR, INT, FLT, FLT, INT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_sifff, STR, INT, FLT, FLT, FLT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_sfsss, STR, FLT, STR, STR, STR)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_sfssi, STR, FLT, STR, STR, INT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_sfssf, STR, FLT, STR, STR, FLT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_sfsis, STR, FLT, STR, INT, STR)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_sfsii, STR, FLT, STR, INT, INT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_sfsif, STR, FLT, STR, INT, FLT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_sfsfs, STR, FLT, STR, FLT, STR)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_sfsfi, STR, FLT, STR, FLT, INT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_sfsff, STR, FLT, STR, FLT, FLT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_sfiss, STR, FLT, INT, STR, STR)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_sfisi, STR, FLT, INT, STR, INT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_sfisf, STR, FLT, INT, STR, FLT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_sfiis, STR, FLT, INT, INT, STR)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_sfiii, STR, FLT, INT, INT, INT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_sfiif, STR, FLT, INT, INT, FLT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_sfifs, STR, FLT, INT, FLT, STR)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_sfifi, STR, FLT, INT, FLT, INT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_sfiff, STR, FLT, INT, FLT, FLT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_sffss, STR, FLT, FLT, STR, STR)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_sffsi, STR, FLT, FLT, STR, INT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_sffsf, STR, FLT, FLT, STR, FLT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_sffis, STR, FLT, FLT, INT, STR)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_sffii, STR, FLT, FLT, INT, INT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_sffif, STR, FLT, FLT, INT, FLT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_sfffs, STR, FLT, FLT, FLT, STR)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_sfffi, STR, FLT, FLT, FLT, INT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_sffff, STR, FLT, FLT, FLT, FLT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_issss, INT, STR, STR, STR, STR)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_isssi, INT, STR, STR, STR, INT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_isssf, INT, STR, STR, STR, FLT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_issis, INT, STR, STR, INT, STR)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_issii, INT, STR, STR, INT, INT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_issif, INT, STR, STR, INT, FLT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_issfs, INT, STR, STR, FLT, STR)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_issfi, INT, STR, STR, FLT, INT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_issff, INT, STR, STR, FLT, FLT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_isiss, INT, STR, INT, STR, STR)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_isisi, INT, STR, INT, STR, INT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_isisf, INT, STR, INT, STR, FLT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_isiis, INT, STR, INT, INT, STR)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_isiii, INT, STR, INT, INT, INT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_isiif, INT, STR, INT, INT, FLT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_isifs, INT, STR, INT, FLT, STR)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_isifi, INT, STR, INT, FLT, INT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_isiff, INT, STR, INT, FLT, FLT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_isfss, INT, STR, FLT, STR, STR)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_isfsi, INT, STR, FLT, STR, INT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_isfsf, INT, STR, FLT, STR, FLT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_isfis, INT, STR, FLT, INT, STR)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_isfii, INT, STR, FLT, INT, INT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_isfif, INT, STR, FLT, INT, FLT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_isffs, INT, STR, FLT, FLT, STR)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_isffi, INT, STR, FLT, FLT, INT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_isfff, INT, STR, FLT, FLT, FLT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_iisss, INT, INT, STR, STR, STR)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_iissi, INT, INT, STR, STR, INT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_iissf, INT, INT, STR, STR, FLT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_iisis, INT, INT, STR, INT, STR)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_iisii, INT, INT, STR, INT, INT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_iisif, INT, INT, STR, INT, FLT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_iisfs, INT, INT, STR, FLT, STR)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_iisfi, INT, INT, STR, FLT, INT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_iisff, INT, INT, STR, FLT, FLT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_iiiss, INT, INT, INT, STR, STR)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_iiisi, INT, INT, INT, STR, INT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_iiisf, INT, INT, INT, STR, FLT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_iiiis, INT, INT, INT, INT, STR)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_iiiii, INT, INT, INT, INT, INT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_iiiif, INT, INT, INT, INT, FLT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_iiifs, INT, INT, INT, FLT, STR)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_iiifi, INT, INT, INT, FLT, INT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_iiiff, INT, INT, INT, FLT, FLT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_iifss, INT, INT, FLT, STR, STR)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_iifsi, INT, INT, FLT, STR, INT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_iifsf, INT, INT, FLT, STR, FLT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_iifis, INT, INT, FLT, INT, STR)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_iifii, INT, INT, FLT, INT, INT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_iifif, INT, INT, FLT, INT, FLT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_iiffs, INT, INT, FLT, FLT, STR)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_iiffi, INT, INT, FLT, FLT, INT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_iifff, INT, INT, FLT, FLT, FLT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_ifsss, INT, FLT, STR, STR, STR)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_ifssi, INT, FLT, STR, STR, INT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_ifssf, INT, FLT, STR, STR, FLT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_ifsis, INT, FLT, STR, INT, STR)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_ifsii, INT, FLT, STR, INT, INT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_ifsif, INT, FLT, STR, INT, FLT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_ifsfs, INT, FLT, STR, FLT, STR)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_ifsfi, INT, FLT, STR, FLT, INT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_ifsff, INT, FLT, STR, FLT, FLT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_ifiss, INT, FLT, INT, STR, STR)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_ifisi, INT, FLT, INT, STR, INT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_ifisf, INT, FLT, INT, STR, FLT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_ifiis, INT, FLT, INT, INT, STR)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_ifiii, INT, FLT, INT, INT, INT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_ifiif, INT, FLT, INT, INT, FLT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_ififs, INT, FLT, INT, FLT, STR)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_ififi, INT, FLT, INT, FLT, INT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_ififf, INT, FLT, INT, FLT, FLT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_iffss, INT, FLT, FLT, STR, STR)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_iffsi, INT, FLT, FLT, STR, INT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_iffsf, INT, FLT, FLT, STR, FLT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_iffis, INT, FLT, FLT, INT, STR)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_iffii, INT, FLT, FLT, INT, INT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_iffif, INT, FLT, FLT, INT, FLT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_ifffs, INT, FLT, FLT, FLT, STR)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_ifffi, INT, FLT, FLT, FLT, INT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_iffff, INT, FLT, FLT, FLT, FLT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_fssss, FLT, STR, STR, STR, STR)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_fsssi, FLT, STR, STR, STR, INT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_fsssf, FLT, STR, STR, STR, FLT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_fssis, FLT, STR, STR, INT, STR)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_fssii, FLT, STR, STR, INT, INT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_fssif, FLT, STR, STR, INT, FLT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_fssfs, FLT, STR, STR, FLT, STR)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_fssfi, FLT, STR, STR, FLT, INT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_fssff, FLT, STR, STR, FLT, FLT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_fsiss, FLT, STR, INT, STR, STR)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_fsisi, FLT, STR, INT, STR, INT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_fsisf, FLT, STR, INT, STR, FLT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_fsiis, FLT, STR, INT, INT, STR)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_fsiii, FLT, STR, INT, INT, INT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_fsiif, FLT, STR, INT, INT, FLT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_fsifs, FLT, STR, INT, FLT, STR)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_fsifi, FLT, STR, INT, FLT, INT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_fsiff, FLT, STR, INT, FLT, FLT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_fsfss, FLT, STR, FLT, STR, STR)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_fsfsi, FLT, STR, FLT, STR, INT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_fsfsf, FLT, STR, FLT, STR, FLT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_fsfis, FLT, STR, FLT, INT, STR)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_fsfii, FLT, STR, FLT, INT, INT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_fsfif, FLT, STR, FLT, INT, FLT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_fsffs, FLT, STR, FLT, FLT, STR)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_fsffi, FLT, STR, FLT, FLT, INT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_fsfff, FLT, STR, FLT, FLT, FLT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_fisss, FLT, INT, STR, STR, STR)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_fissi, FLT, INT, STR, STR, INT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_fissf, FLT, INT, STR, STR, FLT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_fisis, FLT, INT, STR, INT, STR)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_fisii, FLT, INT, STR, INT, INT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_fisif, FLT, INT, STR, INT, FLT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_fisfs, FLT, INT, STR, FLT, STR)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_fisfi, FLT, INT, STR, FLT, INT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_fisff, FLT, INT, STR, FLT, FLT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_fiiss, FLT, INT, INT, STR, STR)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_fiisi, FLT, INT, INT, STR, INT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_fiisf, FLT, INT, INT, STR, FLT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_fiiis, FLT, INT, INT, INT, STR)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_fiiii, FLT, INT, INT, INT, INT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_fiiif, FLT, INT, INT, INT, FLT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_fiifs, FLT, INT, INT, FLT, STR)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_fiifi, FLT, INT, INT, FLT, INT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_fiiff, FLT, INT, INT, FLT, FLT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_fifss, FLT, INT, FLT, STR, STR)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_fifsi, FLT, INT, FLT, STR, INT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_fifsf, FLT, INT, FLT, STR, FLT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_fifis, FLT, INT, FLT, INT, STR)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_fifii, FLT, INT, FLT, INT, INT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_fifif, FLT, INT, FLT, INT, FLT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_fiffs, FLT, INT, FLT, FLT, STR)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_fiffi, FLT, INT, FLT, FLT, INT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_fifff, FLT, INT, FLT, FLT, FLT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_ffsss, FLT, FLT, STR, STR, STR)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_ffssi, FLT, FLT, STR, STR, INT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_ffssf, FLT, FLT, STR, STR, FLT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_ffsis, FLT, FLT, STR, INT, STR)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_ffsii, FLT, FLT, STR, INT, INT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_ffsif, FLT, FLT, STR, INT, FLT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_ffsfs, FLT, FLT, STR, FLT, STR)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_ffsfi, FLT, FLT, STR, FLT, INT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_ffsff, FLT, FLT, STR, FLT, FLT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_ffiss, FLT, FLT, INT, STR, STR)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_ffisi, FLT, FLT, INT, STR, INT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_ffisf, FLT, FLT, INT, STR, FLT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_ffiis, FLT, FLT, INT, INT, STR)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_ffiii, FLT, FLT, INT, INT, INT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_ffiif, FLT, FLT, INT, INT, FLT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_ffifs, FLT, FLT, INT, FLT, STR)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_ffifi, FLT, FLT, INT, FLT, INT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_ffiff, FLT, FLT, INT, FLT, FLT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_fffss, FLT, FLT, FLT, STR, STR)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_fffsi, FLT, FLT, FLT, STR, INT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_fffsf, FLT, FLT, FLT, STR, FLT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_fffis, FLT, FLT, FLT, INT, STR)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_fffii, FLT, FLT, FLT, INT, INT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_fffif, FLT, FLT, FLT, INT, FLT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_ffffs, FLT, FLT, FLT, FLT, STR)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_ffffi, FLT, FLT, FLT, FLT, INT)
V2_CONCAT_LEAF_5(lua55_v2r_concat_5_fffff, FLT, FLT, FLT, FLT, FLT)
#endif
