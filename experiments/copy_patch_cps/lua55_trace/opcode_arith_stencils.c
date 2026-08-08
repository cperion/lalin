#include "opcode_value_v1.h"
#include "opcode_value_v1.h"
#include "opcode_value_v2.h"
/* Batch 2: arithmetic, bitwise, and shifts (21-45, POW deferred).
   Every primitive owns its companion; a numeric success skips it. All math
   is inline (no libc calls): int ops wrap via unsigned arithmetic, float ops
   are plain doubles, F2Ieq coercion for bitwise/shifts, floor via integer
   truncation, fmod via trunc division. Integer MOD/IDIV zero-divisor exits
   to the host at the primitive PC (status COMPLETED, no state change). */

#define ARITH_TARGET_INDEX UINT32_C(0x111)
#define ARITH_LEFT_INDEX   UINT32_C(0x222)
#define ARITH_RIGHT_INDEX  UINT32_C(0x333)

#define QUOTE_BASE_HOLE UINT32_C(0x0f1e2d3c)
#define INT_IMM_HOLE UINT64_C(0x1112131415161718)
#define CONST_TAG_HOLE UINT32_C(0x3c3b3a39)
#define CONST_INT_HOLE UINT64_C(0x2122232425262728)
#define CONST_FLT_HOLE UINT64_C(0x123456789abcdef0)

#define RESUME_HOLE UINT32_C(0x66778899)

#define GUARD_FAILED(frame) do {            \
    (frame)->resume_pc = RESUME_HOLE;       \
    (frame)->status = LUA55_GUARD_FAILED;   \
} while (0)

#define REJECT(frame) do {                  \
    (frame)->resume_pc = RESUME_HOLE;       \
    (frame)->status = LUA55_REJECTED;       \
} while (0)

#define ZERO_EXIT(frame) do {               \
    (frame)->resume_pc = RESUME_HOLE;       \
    (frame)->status = LUA55_COMPLETED;      \
} while (0)

/* --- shared exact helpers (identical semantics to batch 1) --- */

static inline double dbl_bits(uint64_t bits)
{
    double value;
    __builtin_memcpy(&value, &bits, sizeof(value));
    return value;
}

static inline int magnitude_at_least_2_63(double x)
{
    uint64_t bits;
    __builtin_memcpy(&bits, &x, sizeof(bits));
    return ((bits & UINT64_C(0x7ff0000000000000)) >> 52) >= UINT64_C(0x43e);
}

static inline double lua55_floor(double x)
{
    if (magnitude_at_least_2_63(x)) return x;
    int64_t i = (int64_t)x;
    double t = (double)i;
    if (x < 0 && t != x) t = (double)(i - 1);
    return t;
}

/* F2Ieq: integral float in int64 range */
static inline int flt_to_int_eq(double f, int64_t *out)
{
    if (f != f) return 0;
    if (magnitude_at_least_2_63(f)) return 0;
    int64_t i = (int64_t)f;
    if ((double)i != f) return 0;
    *out = i;
    return 1;
}

/* --- integer wrap arithmetic (intop) --- */
static inline int64_t int_add(int64_t a, int64_t b) { return (int64_t)((uint64_t)a + (uint64_t)b); }
static inline int64_t int_sub(int64_t a, int64_t b) { return (int64_t)((uint64_t)a - (uint64_t)b); }
static inline int64_t int_mul(int64_t a, int64_t b) { return (int64_t)((uint64_t)a * (uint64_t)b); }
static inline int64_t int_band(int64_t a, int64_t b) { return a & b; }
static inline int64_t int_bor(int64_t a, int64_t b)  { return a | b; }
static inline int64_t int_bxor(int64_t a, int64_t b) { return a ^ b; }

/* --- luaV_idiv / luaV_mod (caller must handle divisor == 0) --- */
static inline int64_t lua55_idiv(int64_t m, int64_t n)
{
    if ((uint64_t)n + 1u <= 1u)          /* n == -1 */
        return int_sub(0, m);
    int64_t q = m / n;
    if ((m ^ n) < 0 && m % n != 0) q -= 1;
    return q;
}

static inline int64_t lua55_mod(int64_t m, int64_t n)
{
    if ((uint64_t)n + 1u <= 1u)          /* n == -1 */
        return 0;
    int64_t r = m % n;
    if (r != 0 && (r ^ n) < 0) r += n;
    return r;
}

/* --- float idiv (floor) and mod (fmod) --- */
static inline double lua55_flt_idiv(double a, double b)
{
    return lua55_floor(a / b);
}

static inline double lua55_fmod(double x, double y)
{
    if (y == 0) return 0.0 / 0.0;             /* fmod(x, 0) = NaN */
    double q = x / y;
    double r;
    if (magnitude_at_least_2_63(q)) r = x;      /* |q| huge: best-effort */
    else {
        int64_t t = (int64_t)q;
        r = x - (double)t * y;
    }
    /* luai_nummod: floor-mod adjust so the result has the sign of the divisor */
    if ((r > 0) ? (y < 0) : (r < 0 && y > 0)) r += y;
    return r;
}

/* Float MOD/IDIV are exact inline only when |a/b| < 2^53; beyond that the
   leaf rejects and the host computes the exact libm result. */
static inline int magnitude_at_least_2_53(double x)
{
    uint64_t bits;
    __builtin_memcpy(&bits, &x, sizeof(bits));
    return ((bits & UINT64_C(0x7ff0000000000000)) >> 52) >= UINT64_C(0x434);
}

static inline int flt_divmod_huge(double a, double b)
{
    double q = a / b;
    if (!(q * 0 == 0)) return 0;          /* NaN or infinite quotient: exact */
    return magnitude_at_least_2_53(q);
}

/* --- luaV_shiftl --- */
static inline int64_t lua55_shiftl(int64_t x, int64_t y)
{
    if (y < 0) {
        if (y <= -64) return 0;
        return (int64_t)((uint64_t)x >> (uint64_t)(-y));
    } else {
        if (y >= 64) return 0;
        return (int64_t)((uint64_t)x << (uint64_t)y);
    }
}
/* ------------------------------------------------------------------ */
/* LEARNERS: register-register family; leaf 1=ii 2=if 3=fi 4=ff.       */

#define LEARN_BINARY(name, intfn, flt_left, flt_right, flt_both)          \
STENCIL(name)(Lua55LearnFrameV1 *frame)                                   \
{                                                                         \
    Lua55ValueV1 *target = &frame->values[ARITH_TARGET_INDEX];            \
    Lua55ValueV1 *left = &frame->values[ARITH_LEFT_INDEX];                \
    Lua55ValueV1 *right = &frame->values[ARITH_RIGHT_INDEX];              \
    Lua55RecordingSlotV1 *slot = next_slot(frame);                        \
    uint32_t base = QUOTE_BASE_HOLE;                                      \
    __asm__ volatile ("" : "+r"(base));                                   \
    if (left->tag == LUA55_VALUE_INTEGER && right->tag == LUA55_VALUE_INTEGER) { \
        SET_TAG(target, LUA55_VALUE_INTEGER);                             \
        target->payload.integer = intfn(left->payload.integer, right->payload.integer); \
        slot->quote = base | 1;                                           \
    } else if (left->tag == LUA55_VALUE_INTEGER && right->tag == LUA55_VALUE_FLOAT) { \
        SET_TAG(target, LUA55_VALUE_FLOAT);                               \
        target->payload.floating = flt_left((double)left->payload.integer, right->payload.floating); \
        slot->quote = base | 2;                                           \
    } else if (left->tag == LUA55_VALUE_FLOAT && right->tag == LUA55_VALUE_INTEGER) { \
        SET_TAG(target, LUA55_VALUE_FLOAT);                               \
        target->payload.floating = flt_right(left->payload.floating, (double)right->payload.integer); \
        slot->quote = base | 3;                                           \
    } else if (left->tag == LUA55_VALUE_FLOAT && right->tag == LUA55_VALUE_FLOAT) { \
        SET_TAG(target, LUA55_VALUE_FLOAT);                               \
        target->payload.floating = flt_both(left->payload.floating, right->payload.floating); \
        slot->quote = base | 4;                                           \
    } else {                                                              \
        slot->quote = LUA55_QUOTE_REJECTED; REJECT(frame); return;        \
    }                                                                     \
    lua55_learn_next(frame);                                              \
}

#define FLT_ADD(a, b) ((a) + (b))
#define FLT_SUB(a, b) ((a) - (b))
#define FLT_MUL(a, b) ((a) * (b))
#define FLT_DIV(a, b) ((a) / (b))

LEARN_BINARY(lua55_learn_add, int_add, FLT_ADD, FLT_ADD, FLT_ADD)
LEARN_BINARY(lua55_learn_sub, int_sub, FLT_SUB, FLT_SUB, FLT_SUB)
LEARN_BINARY(lua55_learn_mul, int_mul, FLT_MUL, FLT_MUL, FLT_MUL)

/* DIV always yields float: int-int must route through the float leaf. */
STENCIL(lua55_learn_div)(Lua55LearnFrameV1 *frame)
{
    Lua55ValueV1 *target = &frame->values[ARITH_TARGET_INDEX];
    Lua55ValueV1 *left = &frame->values[ARITH_LEFT_INDEX];
    Lua55ValueV1 *right = &frame->values[ARITH_RIGHT_INDEX];
    Lua55RecordingSlotV1 *slot = next_slot(frame);
    uint32_t base = QUOTE_BASE_HOLE;
    __asm__ volatile ("" : "+r"(base));
    if (left->tag == LUA55_VALUE_INTEGER && right->tag == LUA55_VALUE_INTEGER) {
        SET_TAG(target, LUA55_VALUE_FLOAT);
        target->payload.floating = (double)left->payload.integer / (double)right->payload.integer;
        slot->quote = base | 1;
    } else if (left->tag == LUA55_VALUE_INTEGER && right->tag == LUA55_VALUE_FLOAT) {
        SET_TAG(target, LUA55_VALUE_FLOAT);
        target->payload.floating = (double)left->payload.integer / right->payload.floating;
        slot->quote = base | 2;
    } else if (left->tag == LUA55_VALUE_FLOAT && right->tag == LUA55_VALUE_INTEGER) {
        SET_TAG(target, LUA55_VALUE_FLOAT);
        target->payload.floating = left->payload.floating / (double)right->payload.integer;
        slot->quote = base | 3;
    } else if (left->tag == LUA55_VALUE_FLOAT && right->tag == LUA55_VALUE_FLOAT) {
        SET_TAG(target, LUA55_VALUE_FLOAT);
        target->payload.floating = left->payload.floating / right->payload.floating;
        slot->quote = base | 4;
    } else {
        slot->quote = LUA55_QUOTE_REJECTED; REJECT(frame); return;
    }
    lua55_learn_next(frame);
}

/* IDIV / MOD: integer leaves zero-exit; float leaves floor/fmod. */
#define LEARN_DIVMOD(name, intfn, zero_check)                              \
STENCIL(name)(Lua55LearnFrameV1 *frame)                                    \
{                                                                          \
    Lua55ValueV1 *target = &frame->values[ARITH_TARGET_INDEX];             \
    Lua55ValueV1 *left = &frame->values[ARITH_LEFT_INDEX];                 \
    Lua55ValueV1 *right = &frame->values[ARITH_RIGHT_INDEX];               \
    Lua55RecordingSlotV1 *slot = next_slot(frame);                         \
    uint32_t base = QUOTE_BASE_HOLE;                                       \
    __asm__ volatile ("" : "+r"(base));                                    \
    if (left->tag == LUA55_VALUE_INTEGER && right->tag == LUA55_VALUE_INTEGER) { \
        if (right->payload.integer == 0) {                                 \
            slot->quote = base | 1;   /* the residual zero-guards at runtime */ \
            ZERO_EXIT(frame); return;                                      \
        }                                                                  \
        SET_TAG(target, LUA55_VALUE_INTEGER);                              \
        target->payload.integer = intfn(left->payload.integer, right->payload.integer); \
        slot->quote = base | 1;                                            \
    } else if (left->tag == LUA55_VALUE_INTEGER && right->tag == LUA55_VALUE_FLOAT) { \
        if (flt_divmod_huge((double)left->payload.integer, right->payload.floating)) { \
            slot->quote = LUA55_QUOTE_REJECTED; REJECT(frame); return;     \
        }                                                                  \
        SET_TAG(target, LUA55_VALUE_FLOAT);                                \
        target->payload.floating = (zero_check)                            \
            ? lua55_fmod((double)left->payload.integer, right->payload.floating) \
            : lua55_flt_idiv((double)left->payload.integer, right->payload.floating); \
        slot->quote = base | 2;                                            \
    } else if (left->tag == LUA55_VALUE_FLOAT && right->tag == LUA55_VALUE_INTEGER) { \
        if (flt_divmod_huge(left->payload.floating, (double)right->payload.integer)) { \
            slot->quote = LUA55_QUOTE_REJECTED; REJECT(frame); return;     \
        }                                                                  \
        SET_TAG(target, LUA55_VALUE_FLOAT);                                \
        target->payload.floating = (zero_check)                            \
            ? lua55_fmod(left->payload.floating, (double)right->payload.integer) \
            : lua55_flt_idiv(left->payload.floating, (double)right->payload.integer); \
        slot->quote = base | 3;                                            \
    } else if (left->tag == LUA55_VALUE_FLOAT && right->tag == LUA55_VALUE_FLOAT) { \
        if (flt_divmod_huge(left->payload.floating, right->payload.floating)) { \
            slot->quote = LUA55_QUOTE_REJECTED; REJECT(frame); return;     \
        }                                                                  \
        SET_TAG(target, LUA55_VALUE_FLOAT);                                \
        target->payload.floating = (zero_check)                            \
            ? lua55_fmod(left->payload.floating, right->payload.floating)  \
            : lua55_flt_idiv(left->payload.floating, right->payload.floating); \
        slot->quote = base | 4;                                            \
    } else {                                                               \
        slot->quote = LUA55_QUOTE_REJECTED; REJECT(frame); return;         \
    }                                                                      \
    lua55_learn_next(frame);                                               \
}

LEARN_DIVMOD(lua55_learn_idiv, lua55_idiv, 0)
LEARN_DIVMOD(lua55_learn_mod, lua55_mod, 1)

/* BITWISE: both operands via F2Ieq coercion; non-coercible float rejects. */
#define LEARN_BITWISE(name, intfn)                                         \
STENCIL(name)(Lua55LearnFrameV1 *frame)                                    \
{                                                                          \
    Lua55ValueV1 *target = &frame->values[ARITH_TARGET_INDEX];             \
    Lua55ValueV1 *left = &frame->values[ARITH_LEFT_INDEX];                 \
    Lua55ValueV1 *right = &frame->values[ARITH_RIGHT_INDEX];               \
    Lua55RecordingSlotV1 *slot = next_slot(frame);                         \
    uint32_t base = QUOTE_BASE_HOLE;                                       \
    __asm__ volatile ("" : "+r"(base));                                    \
    int64_t i1, i2;                                                        \
    if (left->tag == LUA55_VALUE_INTEGER) { i1 = left->payload.integer; }  \
    else if (left->tag == LUA55_VALUE_FLOAT && flt_to_int_eq(left->payload.floating, &i1)) { } \
    else { slot->quote = LUA55_QUOTE_REJECTED; REJECT(frame); return; }    \
    if (right->tag == LUA55_VALUE_INTEGER) { i2 = right->payload.integer; } \
    else if (right->tag == LUA55_VALUE_FLOAT && flt_to_int_eq(right->payload.floating, &i2)) { } \
    else { slot->quote = LUA55_QUOTE_REJECTED; REJECT(frame); return; }    \
    uint32_t leaf = (left->tag == LUA55_VALUE_FLOAT ? 2 : 0) + (right->tag == LUA55_VALUE_FLOAT ? 1 : 0) + 1; \
    SET_TAG(target, LUA55_VALUE_INTEGER);                                  \
    target->payload.integer = intfn(i1, i2);                               \
    slot->quote = base | leaf;                                             \
    lua55_learn_next(frame);                                               \
}

LEARN_BITWISE(lua55_learn_band, int_band)
LEARN_BITWISE(lua55_learn_bor, int_bor)
LEARN_BITWISE(lua55_learn_bxor, int_bxor)

/* SHIFT: coerce both; SHL = shiftl(left, right), SHR = shiftl(left, -right). */
#define LEARN_SHIFT(name, flip)                                            \
STENCIL(name)(Lua55LearnFrameV1 *frame)                                    \
{                                                                          \
    Lua55ValueV1 *target = &frame->values[ARITH_TARGET_INDEX];             \
    Lua55ValueV1 *left = &frame->values[ARITH_LEFT_INDEX];                 \
    Lua55ValueV1 *right = &frame->values[ARITH_RIGHT_INDEX];               \
    Lua55RecordingSlotV1 *slot = next_slot(frame);                         \
    uint32_t base = QUOTE_BASE_HOLE;                                       \
    __asm__ volatile ("" : "+r"(base));                                    \
    int64_t i1, i2;                                                        \
    if (left->tag == LUA55_VALUE_INTEGER) { i1 = left->payload.integer; }  \
    else if (left->tag == LUA55_VALUE_FLOAT && flt_to_int_eq(left->payload.floating, &i1)) { } \
    else { slot->quote = LUA55_QUOTE_REJECTED; REJECT(frame); return; }    \
    if (right->tag == LUA55_VALUE_INTEGER) { i2 = right->payload.integer; } \
    else if (right->tag == LUA55_VALUE_FLOAT && flt_to_int_eq(right->payload.floating, &i2)) { } \
    else { slot->quote = LUA55_QUOTE_REJECTED; REJECT(frame); return; }    \
    uint32_t leaf = (left->tag == LUA55_VALUE_FLOAT ? 2 : 0) + (right->tag == LUA55_VALUE_FLOAT ? 1 : 0) + 1; \
    SET_TAG(target, LUA55_VALUE_INTEGER);                                  \
    target->payload.integer = (flip) ? lua55_shiftl(i1, -i2) : lua55_shiftl(i1, i2); \
    slot->quote = base | leaf;                                             \
    lua55_learn_next(frame);                                               \
}

LEARN_SHIFT(lua55_learn_shl, 0)
LEARN_SHIFT(lua55_learn_shr, 1)

/* ------------------------------------------------------------------ */
/* RESIDUALS: per (opcode, leaf). guard tags, compute, store, next.    */

#define RESIDUAL_BINARY(name, lt, rt, intfn, flt_left, flt_right, flt_both, zero, always_float) \
STENCIL(name)(Lua55LearnFrameV1 *frame)                                   \
{                                                                         \
    Lua55ValueV1 *target = &frame->values[ARITH_TARGET_INDEX];            \
    Lua55ValueV1 *left = &frame->values[ARITH_LEFT_INDEX];                \
    Lua55ValueV1 *right = &frame->values[ARITH_RIGHT_INDEX];              \
    if (left->tag != (lt) || right->tag != (rt)) { GUARD_FAILED(frame); return; } \
    if ((zero) && (rt) == LUA55_VALUE_INTEGER && right->payload.integer == 0) { \
        ZERO_EXIT(frame); return;                                         \
    }                                                                     \
    if (!(always_float) && (lt) == LUA55_VALUE_INTEGER && (rt) == LUA55_VALUE_INTEGER) { \
        SET_TAG(target, LUA55_VALUE_INTEGER);                             \
        target->payload.integer = intfn(left->payload.integer, right->payload.integer); \
    } else {                                                              \
        SET_TAG(target, LUA55_VALUE_FLOAT);                               \
        if ((lt) == LUA55_VALUE_INTEGER && (rt) == LUA55_VALUE_INTEGER)   \
            target->payload.floating = flt_left((double)left->payload.integer, (double)right->payload.integer); \
        else if ((lt) == LUA55_VALUE_INTEGER)                             \
            target->payload.floating = flt_left((double)left->payload.integer, right->payload.floating); \
        else if ((rt) == LUA55_VALUE_INTEGER)                             \
            target->payload.floating = flt_right(left->payload.floating, (double)right->payload.integer); \
        else                                                              \
            target->payload.floating = flt_both(left->payload.floating, right->payload.floating); \
    }                                                                     \
    lua55_residual_next(frame);                                           \
}

#define R_ADD(a, b) ((a) + (b))
#define R_SUB(a, b) ((a) - (b))
#define R_MUL(a, b) ((a) * (b))
#define R_DIV(a, b) ((a) / (b))

RESIDUAL_BINARY(lua55_residual_add_ii, LUA55_VALUE_INTEGER, LUA55_VALUE_INTEGER, int_add, R_ADD, R_ADD, R_ADD, 0, 0)
RESIDUAL_BINARY(lua55_residual_add_if, LUA55_VALUE_INTEGER, LUA55_VALUE_FLOAT, int_add, R_ADD, R_ADD, R_ADD, 0, 0)
RESIDUAL_BINARY(lua55_residual_add_fi, LUA55_VALUE_FLOAT, LUA55_VALUE_INTEGER, int_add, R_ADD, R_ADD, R_ADD, 0, 0)
RESIDUAL_BINARY(lua55_residual_add_ff, LUA55_VALUE_FLOAT, LUA55_VALUE_FLOAT, int_add, R_ADD, R_ADD, R_ADD, 0, 0)

RESIDUAL_BINARY(lua55_residual_sub_ii, LUA55_VALUE_INTEGER, LUA55_VALUE_INTEGER, int_sub, R_SUB, R_SUB, R_SUB, 0, 0)
RESIDUAL_BINARY(lua55_residual_sub_if, LUA55_VALUE_INTEGER, LUA55_VALUE_FLOAT, int_sub, R_SUB, R_SUB, R_SUB, 0, 0)
RESIDUAL_BINARY(lua55_residual_sub_fi, LUA55_VALUE_FLOAT, LUA55_VALUE_INTEGER, int_sub, R_SUB, R_SUB, R_SUB, 0, 0)
RESIDUAL_BINARY(lua55_residual_sub_ff, LUA55_VALUE_FLOAT, LUA55_VALUE_FLOAT, int_sub, R_SUB, R_SUB, R_SUB, 0, 0)

RESIDUAL_BINARY(lua55_residual_mul_ii, LUA55_VALUE_INTEGER, LUA55_VALUE_INTEGER, int_mul, R_MUL, R_MUL, R_MUL, 0, 0)
RESIDUAL_BINARY(lua55_residual_mul_if, LUA55_VALUE_INTEGER, LUA55_VALUE_FLOAT, int_mul, R_MUL, R_MUL, R_MUL, 0, 0)
RESIDUAL_BINARY(lua55_residual_mul_fi, LUA55_VALUE_FLOAT, LUA55_VALUE_INTEGER, int_mul, R_MUL, R_MUL, R_MUL, 0, 0)
RESIDUAL_BINARY(lua55_residual_mul_ff, LUA55_VALUE_FLOAT, LUA55_VALUE_FLOAT, int_mul, R_MUL, R_MUL, R_MUL, 0, 0)

RESIDUAL_BINARY(lua55_residual_div_ii, LUA55_VALUE_INTEGER, LUA55_VALUE_INTEGER, int_add, R_DIV, R_DIV, R_DIV, 0, 1)
RESIDUAL_BINARY(lua55_residual_div_if, LUA55_VALUE_INTEGER, LUA55_VALUE_FLOAT, int_add, R_DIV, R_DIV, R_DIV, 0, 1)
RESIDUAL_BINARY(lua55_residual_div_fi, LUA55_VALUE_FLOAT, LUA55_VALUE_INTEGER, int_add, R_DIV, R_DIV, R_DIV, 0, 1)
RESIDUAL_BINARY(lua55_residual_div_ff, LUA55_VALUE_FLOAT, LUA55_VALUE_FLOAT, int_add, R_DIV, R_DIV, R_DIV, 0, 1)

RESIDUAL_BINARY(lua55_residual_idiv_ii, LUA55_VALUE_INTEGER, LUA55_VALUE_INTEGER, lua55_idiv, lua55_flt_idiv, lua55_flt_idiv, lua55_flt_idiv, 1, 0)
RESIDUAL_BINARY(lua55_residual_idiv_if, LUA55_VALUE_INTEGER, LUA55_VALUE_FLOAT, lua55_idiv, lua55_flt_idiv, lua55_flt_idiv, lua55_flt_idiv, 0, 0)
RESIDUAL_BINARY(lua55_residual_idiv_fi, LUA55_VALUE_FLOAT, LUA55_VALUE_INTEGER, lua55_idiv, lua55_flt_idiv, lua55_flt_idiv, lua55_flt_idiv, 0, 0)
RESIDUAL_BINARY(lua55_residual_idiv_ff, LUA55_VALUE_FLOAT, LUA55_VALUE_FLOAT, lua55_idiv, lua55_flt_idiv, lua55_flt_idiv, lua55_flt_idiv, 0, 0)

RESIDUAL_BINARY(lua55_residual_mod_ii, LUA55_VALUE_INTEGER, LUA55_VALUE_INTEGER, lua55_mod, lua55_fmod, lua55_fmod, lua55_fmod, 1, 0)
RESIDUAL_BINARY(lua55_residual_mod_if, LUA55_VALUE_INTEGER, LUA55_VALUE_FLOAT, lua55_mod, lua55_fmod, lua55_fmod, lua55_fmod, 0, 0)
RESIDUAL_BINARY(lua55_residual_mod_fi, LUA55_VALUE_FLOAT, LUA55_VALUE_INTEGER, lua55_mod, lua55_fmod, lua55_fmod, lua55_fmod, 0, 0)
RESIDUAL_BINARY(lua55_residual_mod_ff, LUA55_VALUE_FLOAT, LUA55_VALUE_FLOAT, lua55_mod, lua55_fmod, lua55_fmod, lua55_fmod, 0, 0)

#define RESIDUAL_BITWISE(name, lt, rt, intfn)                              \
STENCIL(name)(Lua55LearnFrameV1 *frame)                                    \
{                                                                          \
    Lua55ValueV1 *target = &frame->values[ARITH_TARGET_INDEX];             \
    Lua55ValueV1 *left = &frame->values[ARITH_LEFT_INDEX];                 \
    Lua55ValueV1 *right = &frame->values[ARITH_RIGHT_INDEX];               \
    if (left->tag != (lt) || right->tag != (rt)) { GUARD_FAILED(frame); return; } \
    int64_t i1 = (lt) == LUA55_VALUE_INTEGER ? left->payload.integer : 0;  \
    int64_t i2 = (rt) == LUA55_VALUE_INTEGER ? right->payload.integer : 0; \
    if ((lt) == LUA55_VALUE_FLOAT && !flt_to_int_eq(left->payload.floating, &i1)) { GUARD_FAILED(frame); return; } \
    if ((rt) == LUA55_VALUE_FLOAT && !flt_to_int_eq(right->payload.floating, &i2)) { GUARD_FAILED(frame); return; } \
    SET_TAG(target, LUA55_VALUE_INTEGER);                                  \
    target->payload.integer = intfn(i1, i2);                               \
    lua55_residual_next(frame);                                            \
}

RESIDUAL_BITWISE(lua55_residual_band_ii, LUA55_VALUE_INTEGER, LUA55_VALUE_INTEGER, int_band)
RESIDUAL_BITWISE(lua55_residual_band_if, LUA55_VALUE_INTEGER, LUA55_VALUE_FLOAT, int_band)
RESIDUAL_BITWISE(lua55_residual_band_fi, LUA55_VALUE_FLOAT, LUA55_VALUE_INTEGER, int_band)
RESIDUAL_BITWISE(lua55_residual_band_ff, LUA55_VALUE_FLOAT, LUA55_VALUE_FLOAT, int_band)
RESIDUAL_BITWISE(lua55_residual_bor_ii, LUA55_VALUE_INTEGER, LUA55_VALUE_INTEGER, int_bor)
RESIDUAL_BITWISE(lua55_residual_bor_if, LUA55_VALUE_INTEGER, LUA55_VALUE_FLOAT, int_bor)
RESIDUAL_BITWISE(lua55_residual_bor_fi, LUA55_VALUE_FLOAT, LUA55_VALUE_INTEGER, int_bor)
RESIDUAL_BITWISE(lua55_residual_bor_ff, LUA55_VALUE_FLOAT, LUA55_VALUE_FLOAT, int_bor)
RESIDUAL_BITWISE(lua55_residual_bxor_ii, LUA55_VALUE_INTEGER, LUA55_VALUE_INTEGER, int_bxor)
RESIDUAL_BITWISE(lua55_residual_bxor_if, LUA55_VALUE_INTEGER, LUA55_VALUE_FLOAT, int_bxor)
RESIDUAL_BITWISE(lua55_residual_bxor_fi, LUA55_VALUE_FLOAT, LUA55_VALUE_INTEGER, int_bxor)
RESIDUAL_BITWISE(lua55_residual_bxor_ff, LUA55_VALUE_FLOAT, LUA55_VALUE_FLOAT, int_bxor)

#define RESIDUAL_SHIFT(name, lt, rt, flip)                                 \
STENCIL(name)(Lua55LearnFrameV1 *frame)                                    \
{                                                                          \
    Lua55ValueV1 *target = &frame->values[ARITH_TARGET_INDEX];             \
    Lua55ValueV1 *left = &frame->values[ARITH_LEFT_INDEX];                 \
    Lua55ValueV1 *right = &frame->values[ARITH_RIGHT_INDEX];               \
    if (left->tag != (lt) || right->tag != (rt)) { GUARD_FAILED(frame); return; } \
    int64_t i1 = (lt) == LUA55_VALUE_INTEGER ? left->payload.integer : 0;  \
    int64_t i2 = (rt) == LUA55_VALUE_INTEGER ? right->payload.integer : 0; \
    if ((lt) == LUA55_VALUE_FLOAT && !flt_to_int_eq(left->payload.floating, &i1)) { GUARD_FAILED(frame); return; } \
    if ((rt) == LUA55_VALUE_FLOAT && !flt_to_int_eq(right->payload.floating, &i2)) { GUARD_FAILED(frame); return; } \
    SET_TAG(target, LUA55_VALUE_INTEGER);                                  \
    target->payload.integer = (flip) ? lua55_shiftl(i1, -i2) : lua55_shiftl(i1, i2); \
    lua55_residual_next(frame);                                            \
}

RESIDUAL_SHIFT(lua55_residual_shl_ii, LUA55_VALUE_INTEGER, LUA55_VALUE_INTEGER, 0)
RESIDUAL_SHIFT(lua55_residual_shl_if, LUA55_VALUE_INTEGER, LUA55_VALUE_FLOAT, 0)
RESIDUAL_SHIFT(lua55_residual_shl_fi, LUA55_VALUE_FLOAT, LUA55_VALUE_INTEGER, 0)
RESIDUAL_SHIFT(lua55_residual_shl_ff, LUA55_VALUE_FLOAT, LUA55_VALUE_FLOAT, 0)
RESIDUAL_SHIFT(lua55_residual_shr_ii, LUA55_VALUE_INTEGER, LUA55_VALUE_INTEGER, 1)
RESIDUAL_SHIFT(lua55_residual_shr_if, LUA55_VALUE_INTEGER, LUA55_VALUE_FLOAT, 1)
RESIDUAL_SHIFT(lua55_residual_shr_fi, LUA55_VALUE_FLOAT, LUA55_VALUE_INTEGER, 1)
RESIDUAL_SHIFT(lua55_residual_shr_ff, LUA55_VALUE_FLOAT, LUA55_VALUE_FLOAT, 1)

/* ------------------------------------------------------------------ */
/* Register-immediate variants: ADDI(21) SHLI(32) SHRI(33).            */
/* Leaf 1 = int operand, 2 = float operand.                            */

#define LEARN_REG_IMM_ARITH(name, intfn, fltfn)                            \
STENCIL(name)(Lua55LearnFrameV1 *frame)                                    \
{                                                                          \
    Lua55ValueV1 *target = &frame->values[ARITH_TARGET_INDEX];             \
    Lua55ValueV1 *left = &frame->values[ARITH_LEFT_INDEX];                 \
    Lua55RecordingSlotV1 *slot = next_slot(frame);                         \
    uint32_t base = QUOTE_BASE_HOLE;                                       \
    __asm__ volatile ("" : "+r"(base));                                    \
    int64_t im = (int64_t)INT_IMM_HOLE;                                    \
    __asm__ volatile ("" : "+r"(im));                                      \
    if (left->tag == LUA55_VALUE_INTEGER) {                                \
        SET_TAG(target, LUA55_VALUE_INTEGER);                              \
        target->payload.integer = intfn(left->payload.integer, im);        \
        slot->quote = base | 1;                                            \
    } else if (left->tag == LUA55_VALUE_FLOAT) {                           \
        SET_TAG(target, LUA55_VALUE_FLOAT);                                \
        target->payload.floating = fltfn(left->payload.floating, (double)im); \
        slot->quote = base | 2;                                            \
    } else {                                                               \
        slot->quote = LUA55_QUOTE_REJECTED; REJECT(frame); return;         \
    }                                                                      \
    lua55_learn_next(frame);                                               \
}

LEARN_REG_IMM_ARITH(lua55_learn_addi, int_add, R_ADD)

STENCIL(lua55_learn_shli)(Lua55LearnFrameV1 *frame)
{
    Lua55ValueV1 *target = &frame->values[ARITH_TARGET_INDEX];
    Lua55ValueV1 *left = &frame->values[ARITH_LEFT_INDEX];
    Lua55RecordingSlotV1 *slot = next_slot(frame);
    uint32_t base = QUOTE_BASE_HOLE;
    __asm__ volatile ("" : "+r"(base));
    int64_t im = (int64_t)INT_IMM_HOLE;
    __asm__ volatile ("" : "+r"(im));
    int64_t count;
    if (left->tag == LUA55_VALUE_INTEGER) {
        count = left->payload.integer;
        SET_TAG(target, LUA55_VALUE_INTEGER);
        target->payload.integer = lua55_shiftl(im, count);
        slot->quote = base | 1;
    } else if (left->tag == LUA55_VALUE_FLOAT && flt_to_int_eq(left->payload.floating, &count)) {
        SET_TAG(target, LUA55_VALUE_INTEGER);
        target->payload.integer = lua55_shiftl(im, count);
        slot->quote = base | 2;
    } else {
        slot->quote = LUA55_QUOTE_REJECTED; REJECT(frame); return;
    }
    lua55_learn_next(frame);
}

STENCIL(lua55_learn_shri)(Lua55LearnFrameV1 *frame)
{
    Lua55ValueV1 *target = &frame->values[ARITH_TARGET_INDEX];
    Lua55ValueV1 *left = &frame->values[ARITH_LEFT_INDEX];
    Lua55RecordingSlotV1 *slot = next_slot(frame);
    uint32_t base = QUOTE_BASE_HOLE;
    __asm__ volatile ("" : "+r"(base));
    int64_t im = (int64_t)INT_IMM_HOLE;
    __asm__ volatile ("" : "+r"(im));
    int64_t value;
    if (left->tag == LUA55_VALUE_INTEGER) {
        value = left->payload.integer;
        SET_TAG(target, LUA55_VALUE_INTEGER);
        target->payload.integer = lua55_shiftl(value, -im);
        slot->quote = base | 1;
    } else if (left->tag == LUA55_VALUE_FLOAT && flt_to_int_eq(left->payload.floating, &value)) {
        SET_TAG(target, LUA55_VALUE_INTEGER);
        target->payload.integer = lua55_shiftl(value, -im);
        slot->quote = base | 2;
    } else {
        slot->quote = LUA55_QUOTE_REJECTED; REJECT(frame); return;
    }
    lua55_learn_next(frame);
}

#define RESIDUAL_REG_IMM_ARITH(name, lt, intfn, fltfn)                     \
STENCIL(name)(Lua55LearnFrameV1 *frame)                                    \
{                                                                          \
    Lua55ValueV1 *target = &frame->values[ARITH_TARGET_INDEX];             \
    Lua55ValueV1 *left = &frame->values[ARITH_LEFT_INDEX];                 \
    if (left->tag != (lt)) { GUARD_FAILED(frame); return; }                \
    int64_t im = (int64_t)INT_IMM_HOLE;                                    \
    __asm__ volatile ("" : "+r"(im));                                      \
    if ((lt) == LUA55_VALUE_INTEGER) {                                     \
        SET_TAG(target, LUA55_VALUE_INTEGER);                              \
        target->payload.integer = intfn(left->payload.integer, im);        \
    } else {                                                               \
        SET_TAG(target, LUA55_VALUE_FLOAT);                                \
        target->payload.floating = fltfn(left->payload.floating, (double)im); \
    }                                                                      \
    lua55_residual_next(frame);                                            \
}

RESIDUAL_REG_IMM_ARITH(lua55_residual_addi_int, LUA55_VALUE_INTEGER, int_add, R_ADD)
RESIDUAL_REG_IMM_ARITH(lua55_residual_addi_flt, LUA55_VALUE_FLOAT, int_add, R_ADD)

#define RESIDUAL_REG_IMM_SHIFT(name, lt, shift_expr)                       \
STENCIL(name)(Lua55LearnFrameV1 *frame)                                    \
{                                                                          \
    Lua55ValueV1 *target = &frame->values[ARITH_TARGET_INDEX];             \
    Lua55ValueV1 *left = &frame->values[ARITH_LEFT_INDEX];                 \
    if (left->tag != (lt)) { GUARD_FAILED(frame); return; }                \
    int64_t im = (int64_t)INT_IMM_HOLE;                                    \
    __asm__ volatile ("" : "+r"(im));                                      \
    int64_t v = (lt) == LUA55_VALUE_INTEGER ? left->payload.integer : 0;   \
    if ((lt) == LUA55_VALUE_FLOAT && !flt_to_int_eq(left->payload.floating, &v)) { GUARD_FAILED(frame); return; } \
    SET_TAG(target, LUA55_VALUE_INTEGER);                                  \
    target->payload.integer = shift_expr;                                  \
    lua55_residual_next(frame);                                            \
}

RESIDUAL_REG_IMM_SHIFT(lua55_residual_shli_int, LUA55_VALUE_INTEGER, lua55_shiftl(im, v))
RESIDUAL_REG_IMM_SHIFT(lua55_residual_shli_flt, LUA55_VALUE_FLOAT, lua55_shiftl(im, v))
RESIDUAL_REG_IMM_SHIFT(lua55_residual_shri_int, LUA55_VALUE_INTEGER, lua55_shiftl(v, -im))
RESIDUAL_REG_IMM_SHIFT(lua55_residual_shri_flt, LUA55_VALUE_FLOAT, lua55_shiftl(v, -im))

/* ------------------------------------------------------------------ */
/* Register-constant variants (22-25, 27-31). Leaf by (reg, const).    */

#define LEARN_CONST_ARITH(name, intfn, fltfn)                              \
STENCIL(name)(Lua55LearnFrameV1 *frame)                                    \
{                                                                          \
    Lua55ValueV1 *target = &frame->values[ARITH_TARGET_INDEX];             \
    Lua55ValueV1 *left = &frame->values[ARITH_LEFT_INDEX];                 \
    Lua55RecordingSlotV1 *slot = next_slot(frame);                         \
    uint32_t base = QUOTE_BASE_HOLE;                                       \
    __asm__ volatile ("" : "+r"(base));                                    \
    uint32_t ctag = CONST_TAG_HOLE;                                        \
    __asm__ volatile ("" : "+r"(ctag));                                    \
    int64_t cint = (int64_t)CONST_INT_HOLE;                                \
    __asm__ volatile ("" : "+r"(cint));                                    \
    uint64_t cflt_bits = CONST_FLT_HOLE;                                   \
    __asm__ volatile ("" : "+r"(cflt_bits));                               \
    double cflt;                                                           \
    __builtin_memcpy(&cflt, &cflt_bits, sizeof(cflt));                     \
    uint32_t leaf;                                                         \
    if (left->tag == LUA55_VALUE_INTEGER && ctag == LUA55_VALUE_INTEGER) { \
        SET_TAG(target, LUA55_VALUE_INTEGER);                              \
        target->payload.integer = intfn(left->payload.integer, cint);      \
        leaf = 1;                                                          \
    } else if (left->tag == LUA55_VALUE_INTEGER && ctag == LUA55_VALUE_FLOAT) { \
        SET_TAG(target, LUA55_VALUE_FLOAT);                                \
        target->payload.floating = fltfn((double)left->payload.integer, cflt); \
        leaf = 2;                                                          \
    } else if (left->tag == LUA55_VALUE_FLOAT && ctag == LUA55_VALUE_INTEGER) { \
        SET_TAG(target, LUA55_VALUE_FLOAT);                                \
        target->payload.floating = fltfn(left->payload.floating, (double)cint); \
        leaf = 3;                                                          \
    } else if (left->tag == LUA55_VALUE_FLOAT && ctag == LUA55_VALUE_FLOAT) { \
        SET_TAG(target, LUA55_VALUE_FLOAT);                                \
        target->payload.floating = fltfn(left->payload.floating, cflt);    \
        leaf = 4;                                                          \
    } else {                                                               \
        slot->quote = LUA55_QUOTE_REJECTED; REJECT(frame); return;         \
    }                                                                      \
    slot->quote = base | leaf;                                             \
    lua55_learn_next(frame);                                               \
}

LEARN_CONST_ARITH(lua55_learn_addk, int_add, R_ADD)
LEARN_CONST_ARITH(lua55_learn_subk, int_sub, R_SUB)
LEARN_CONST_ARITH(lua55_learn_mulk, int_mul, R_MUL)
LEARN_CONST_ARITH(lua55_learn_divk, int_add, R_DIV)

#define LEARN_CONST_DIVMOD(name, intfn, zero_check)                        \
STENCIL(name)(Lua55LearnFrameV1 *frame)                                    \
{                                                                          \
    Lua55ValueV1 *target = &frame->values[ARITH_TARGET_INDEX];             \
    Lua55ValueV1 *left = &frame->values[ARITH_LEFT_INDEX];                 \
    Lua55RecordingSlotV1 *slot = next_slot(frame);                         \
    uint32_t base = QUOTE_BASE_HOLE;                                       \
    __asm__ volatile ("" : "+r"(base));                                    \
    uint32_t ctag = CONST_TAG_HOLE;                                        \
    __asm__ volatile ("" : "+r"(ctag));                                    \
    int64_t cint = (int64_t)CONST_INT_HOLE;                                \
    __asm__ volatile ("" : "+r"(cint));                                    \
    uint64_t cflt_bits = CONST_FLT_HOLE;                                   \
    __asm__ volatile ("" : "+r"(cflt_bits));                               \
    double cflt;                                                           \
    __builtin_memcpy(&cflt, &cflt_bits, sizeof(cflt));                     \
    uint32_t leaf;                                                         \
    if (left->tag == LUA55_VALUE_INTEGER && ctag == LUA55_VALUE_INTEGER) { \
        if (cint == 0) { ZERO_EXIT(frame); return; }                       \
        SET_TAG(target, LUA55_VALUE_INTEGER);                              \
        target->payload.integer = intfn(left->payload.integer, cint);      \
        leaf = 1;                                                          \
    } else if (left->tag == LUA55_VALUE_INTEGER && ctag == LUA55_VALUE_FLOAT) { \
        if (flt_divmod_huge((double)left->payload.integer, cflt)) {        \
            slot->quote = LUA55_QUOTE_REJECTED; REJECT(frame); return;     \
        }                                                                  \
        SET_TAG(target, LUA55_VALUE_FLOAT);                                \
        target->payload.floating = (zero_check)                            \
            ? lua55_fmod((double)left->payload.integer, cflt)              \
            : lua55_flt_idiv((double)left->payload.integer, cflt);         \
        leaf = 2;                                                          \
    } else if (left->tag == LUA55_VALUE_FLOAT && ctag == LUA55_VALUE_INTEGER) { \
        if (flt_divmod_huge(left->payload.floating, (double)cint)) {       \
            slot->quote = LUA55_QUOTE_REJECTED; REJECT(frame); return;     \
        }                                                                  \
        SET_TAG(target, LUA55_VALUE_FLOAT);                                \
        target->payload.floating = (zero_check)                            \
            ? lua55_fmod(left->payload.floating, (double)cint)             \
            : lua55_flt_idiv(left->payload.floating, (double)cint);        \
        leaf = 3;                                                          \
    } else if (left->tag == LUA55_VALUE_FLOAT && ctag == LUA55_VALUE_FLOAT) { \
        if (flt_divmod_huge(left->payload.floating, cflt)) {               \
            slot->quote = LUA55_QUOTE_REJECTED; REJECT(frame); return;     \
        }                                                                  \
        SET_TAG(target, LUA55_VALUE_FLOAT);                                \
        target->payload.floating = (zero_check)                            \
            ? lua55_fmod(left->payload.floating, cflt)                     \
            : lua55_flt_idiv(left->payload.floating, cflt);                \
        leaf = 4;                                                          \
    } else {                                                               \
        slot->quote = LUA55_QUOTE_REJECTED; REJECT(frame); return;         \
    }                                                                      \
    slot->quote = base | leaf;                                             \
    lua55_learn_next(frame);                                               \
}

LEARN_CONST_DIVMOD(lua55_learn_idivk, lua55_idiv, 0)
LEARN_CONST_DIVMOD(lua55_learn_modk, lua55_mod, 1)

#define LEARN_CONST_BITWISE(name, intfn)                                   \
STENCIL(name)(Lua55LearnFrameV1 *frame)                                    \
{                                                                          \
    Lua55ValueV1 *target = &frame->values[ARITH_TARGET_INDEX];             \
    Lua55ValueV1 *left = &frame->values[ARITH_LEFT_INDEX];                 \
    Lua55RecordingSlotV1 *slot = next_slot(frame);                         \
    uint32_t base = QUOTE_BASE_HOLE;                                       \
    __asm__ volatile ("" : "+r"(base));                                    \
    int64_t cint = (int64_t)CONST_INT_HOLE;                                \
    __asm__ volatile ("" : "+r"(cint));                                    \
    int64_t i1;                                                            \
    if (left->tag == LUA55_VALUE_INTEGER) { i1 = left->payload.integer; }  \
    else if (left->tag == LUA55_VALUE_FLOAT && flt_to_int_eq(left->payload.floating, &i1)) { } \
    else { slot->quote = LUA55_QUOTE_REJECTED; REJECT(frame); return; }    \
    SET_TAG(target, LUA55_VALUE_INTEGER);                                  \
    target->payload.integer = intfn(i1, cint);                             \
    slot->quote = base | (left->tag == LUA55_VALUE_FLOAT ? 2 : 1);         \
    lua55_learn_next(frame);                                               \
}

LEARN_CONST_BITWISE(lua55_learn_bandk, int_band)
LEARN_CONST_BITWISE(lua55_learn_bork, int_bor)
LEARN_CONST_BITWISE(lua55_learn_bxork, int_bxor)

/* K-variant residuals: leaf 1=ii 2=if 3=fi 4=ff for binary;                 */
/* bitwise K leaves are 1 (reg int) / 2 (reg float).                        */

#define RESIDUAL_CONST_ARITH(name, lt, ctag_expect, intfn, fltfn, zero)    \
STENCIL(name)(Lua55LearnFrameV1 *frame)                                    \
{                                                                          \
    Lua55ValueV1 *target = &frame->values[ARITH_TARGET_INDEX];             \
    Lua55ValueV1 *left = &frame->values[ARITH_LEFT_INDEX];                 \
    if (left->tag != (lt)) { GUARD_FAILED(frame); return; }                \
    int64_t cint = (int64_t)CONST_INT_HOLE;                                \
    __asm__ volatile ("" : "+r"(cint));                                    \
    uint64_t cflt_bits = CONST_FLT_HOLE;                                   \
    __asm__ volatile ("" : "+r"(cflt_bits));                               \
    double cflt;                                                           \
    __builtin_memcpy(&cflt, &cflt_bits, sizeof(cflt));                     \
    if ((zero) && (ctag_expect) == LUA55_VALUE_INTEGER && cint == 0) {     \
        ZERO_EXIT(frame); return;                                          \
    }                                                                      \
    if ((lt) == LUA55_VALUE_INTEGER && (ctag_expect) == LUA55_VALUE_INTEGER) { \
        SET_TAG(target, LUA55_VALUE_INTEGER);                              \
        target->payload.integer = intfn(left->payload.integer, cint);      \
    } else {                                                               \
        SET_TAG(target, LUA55_VALUE_FLOAT);                                \
        if ((lt) == LUA55_VALUE_INTEGER)                                   \
            target->payload.floating = fltfn((double)left->payload.integer, cflt); \
        else if ((ctag_expect) == LUA55_VALUE_INTEGER)                     \
            target->payload.floating = fltfn(left->payload.floating, (double)cint); \
        else                                                               \
            target->payload.floating = fltfn(left->payload.floating, cflt); \
    }                                                                      \
    lua55_residual_next(frame);                                            \
}

RESIDUAL_CONST_ARITH(lua55_residual_addk_ii, LUA55_VALUE_INTEGER, LUA55_VALUE_INTEGER, int_add, R_ADD, 0)
RESIDUAL_CONST_ARITH(lua55_residual_addk_if, LUA55_VALUE_INTEGER, LUA55_VALUE_FLOAT, int_add, R_ADD, 0)
RESIDUAL_CONST_ARITH(lua55_residual_addk_fi, LUA55_VALUE_FLOAT, LUA55_VALUE_INTEGER, int_add, R_ADD, 0)
RESIDUAL_CONST_ARITH(lua55_residual_addk_ff, LUA55_VALUE_FLOAT, LUA55_VALUE_FLOAT, int_add, R_ADD, 0)
RESIDUAL_CONST_ARITH(lua55_residual_subk_ii, LUA55_VALUE_INTEGER, LUA55_VALUE_INTEGER, int_sub, R_SUB, 0)
RESIDUAL_CONST_ARITH(lua55_residual_subk_if, LUA55_VALUE_INTEGER, LUA55_VALUE_FLOAT, int_sub, R_SUB, 0)
RESIDUAL_CONST_ARITH(lua55_residual_subk_fi, LUA55_VALUE_FLOAT, LUA55_VALUE_INTEGER, int_sub, R_SUB, 0)
RESIDUAL_CONST_ARITH(lua55_residual_subk_ff, LUA55_VALUE_FLOAT, LUA55_VALUE_FLOAT, int_sub, R_SUB, 0)
RESIDUAL_CONST_ARITH(lua55_residual_mulk_ii, LUA55_VALUE_INTEGER, LUA55_VALUE_INTEGER, int_mul, R_MUL, 0)
RESIDUAL_CONST_ARITH(lua55_residual_mulk_if, LUA55_VALUE_INTEGER, LUA55_VALUE_FLOAT, int_mul, R_MUL, 0)
RESIDUAL_CONST_ARITH(lua55_residual_mulk_fi, LUA55_VALUE_FLOAT, LUA55_VALUE_INTEGER, int_mul, R_MUL, 0)
RESIDUAL_CONST_ARITH(lua55_residual_mulk_ff, LUA55_VALUE_FLOAT, LUA55_VALUE_FLOAT, int_mul, R_MUL, 0)
RESIDUAL_CONST_ARITH(lua55_residual_divk_ii, LUA55_VALUE_INTEGER, LUA55_VALUE_INTEGER, int_add, R_DIV, 0)
RESIDUAL_CONST_ARITH(lua55_residual_divk_if, LUA55_VALUE_INTEGER, LUA55_VALUE_FLOAT, int_add, R_DIV, 0)
RESIDUAL_CONST_ARITH(lua55_residual_divk_fi, LUA55_VALUE_FLOAT, LUA55_VALUE_INTEGER, int_add, R_DIV, 0)
RESIDUAL_CONST_ARITH(lua55_residual_divk_ff, LUA55_VALUE_FLOAT, LUA55_VALUE_FLOAT, int_add, R_DIV, 0)
RESIDUAL_CONST_ARITH(lua55_residual_idivk_ii, LUA55_VALUE_INTEGER, LUA55_VALUE_INTEGER, lua55_idiv, lua55_flt_idiv, 1)
RESIDUAL_CONST_ARITH(lua55_residual_idivk_if, LUA55_VALUE_INTEGER, LUA55_VALUE_FLOAT, lua55_idiv, lua55_flt_idiv, 0)
RESIDUAL_CONST_ARITH(lua55_residual_idivk_fi, LUA55_VALUE_FLOAT, LUA55_VALUE_INTEGER, lua55_idiv, lua55_flt_idiv, 0)
RESIDUAL_CONST_ARITH(lua55_residual_idivk_ff, LUA55_VALUE_FLOAT, LUA55_VALUE_FLOAT, lua55_idiv, lua55_flt_idiv, 0)
RESIDUAL_CONST_ARITH(lua55_residual_modk_ii, LUA55_VALUE_INTEGER, LUA55_VALUE_INTEGER, lua55_mod, lua55_fmod, 1)
RESIDUAL_CONST_ARITH(lua55_residual_modk_if, LUA55_VALUE_INTEGER, LUA55_VALUE_FLOAT, lua55_mod, lua55_fmod, 0)
RESIDUAL_CONST_ARITH(lua55_residual_modk_fi, LUA55_VALUE_FLOAT, LUA55_VALUE_INTEGER, lua55_mod, lua55_fmod, 0)
RESIDUAL_CONST_ARITH(lua55_residual_modk_ff, LUA55_VALUE_FLOAT, LUA55_VALUE_FLOAT, lua55_mod, lua55_fmod, 0)

#define RESIDUAL_CONST_BITWISE(name, lt, intfn)                             \
STENCIL(name)(Lua55LearnFrameV1 *frame)                                     \
{                                                                           \
    Lua55ValueV1 *target = &frame->values[ARITH_TARGET_INDEX];              \
    Lua55ValueV1 *left = &frame->values[ARITH_LEFT_INDEX];                  \
    if (left->tag != (lt)) { GUARD_FAILED(frame); return; }                 \
    int64_t cint = (int64_t)CONST_INT_HOLE;                                 \
    __asm__ volatile ("" : "+r"(cint));                                     \
    int64_t i1 = (lt) == LUA55_VALUE_INTEGER ? left->payload.integer : 0;   \
    if ((lt) == LUA55_VALUE_FLOAT && !flt_to_int_eq(left->payload.floating, &i1)) { GUARD_FAILED(frame); return; } \
    SET_TAG(target, LUA55_VALUE_INTEGER);                                   \
    target->payload.integer = intfn(i1, cint);                              \
    lua55_residual_next(frame);                                             \
}

RESIDUAL_CONST_BITWISE(lua55_residual_bandk_i, LUA55_VALUE_INTEGER, int_band)
RESIDUAL_CONST_BITWISE(lua55_residual_bandk_f, LUA55_VALUE_FLOAT, int_band)
RESIDUAL_CONST_BITWISE(lua55_residual_bork_i, LUA55_VALUE_INTEGER, int_bor)
RESIDUAL_CONST_BITWISE(lua55_residual_bork_f, LUA55_VALUE_FLOAT, int_bor)
RESIDUAL_CONST_BITWISE(lua55_residual_bxork_i, LUA55_VALUE_INTEGER, int_bxor)
RESIDUAL_CONST_BITWISE(lua55_residual_bxork_f, LUA55_VALUE_FLOAT, int_bxor)

/* ---- Self-selecting (polymorphic) residuals ------------------------------
   One residual per opcode; the operand-tag dispatch IS the selection (no
   quote recording, no Lua-side residual selection). Unhandled shapes
   (metamethods / errors) reject to the host. The register indices are
   runtime holes (like the learners): the compiler keeps them as patched
   immediates, so the bank builder can find them. */

#define POLY_TARGET_HOLE UINT32_C(0x111)
#define POLY_LEFT_HOLE UINT32_C(0x222)
#define POLY_RIGHT_HOLE UINT32_C(0x333)
#define POLY_IMM_HOLE UINT64_C(0x1112131415161718)
#define POLY_CTAG_HOLE UINT32_C(0x3c3b3a39)
#define POLY_CINT_HOLE UINT64_C(0x2122232425262728)
#define POLY_CFLT_HOLE UINT64_C(0x123456789abcdef0)

#define POLY_BIN(name, intfn, flt_left, flt_right, flt_both, right_init)   \
STENCIL(name)(Lua55LearnFrameV1 *frame)                                    \
{                                                                          \
    uint32_t target_index = POLY_TARGET_HOLE;                              \
    __asm__ volatile ("" : "+r"(target_index));                            \
    uint32_t left_index = POLY_LEFT_HOLE;                                  \
    __asm__ volatile ("" : "+r"(left_index));                              \
    uint32_t right_index = POLY_RIGHT_HOLE;                                \
    __asm__ volatile ("" : "+r"(right_index));                             \
    Lua55ValueV1 *target = &frame->values[target_index];                   \
    Lua55ValueV1 *left = &frame->values[left_index];                       \
    Lua55ValueV1 *right = &frame->values[right_index];                     \
    right_init;                                                            \
    if (left->tag == LUA55_VALUE_INTEGER && right->tag == LUA55_VALUE_INTEGER) { \
        SET_TAG(target, LUA55_VALUE_INTEGER);                              \
        target->payload.integer = intfn(left->payload.integer, right->payload.integer); \
    } else if (left->tag == LUA55_VALUE_INTEGER && right->tag == LUA55_VALUE_FLOAT) { \
        SET_TAG(target, LUA55_VALUE_FLOAT);                                \
        target->payload.floating = flt_left((double)left->payload.integer, right->payload.floating); \
    } else if (left->tag == LUA55_VALUE_FLOAT && right->tag == LUA55_VALUE_INTEGER) { \
        SET_TAG(target, LUA55_VALUE_FLOAT);                                \
        target->payload.floating = flt_right(left->payload.floating, (double)right->payload.integer); \
    } else if (left->tag == LUA55_VALUE_FLOAT && right->tag == LUA55_VALUE_FLOAT) { \
        SET_TAG(target, LUA55_VALUE_FLOAT);                                \
        target->payload.floating = flt_both(left->payload.floating, right->payload.floating); \
    } else { REJECT(frame); LUA55_CPS_HOST_EXIT(frame); }                                      \
    lua55_residual_next(frame);                                            \
}

#define POLY_DIVMOD(name, intfn, fltfn, right_init)                       \
STENCIL(name)(Lua55LearnFrameV1 *frame)                                    \
{                                                                          \
    uint32_t target_index = POLY_TARGET_HOLE;                              \
    __asm__ volatile ("" : "+r"(target_index));                            \
    uint32_t left_index = POLY_LEFT_HOLE;                                  \
    __asm__ volatile ("" : "+r"(left_index));                              \
    uint32_t right_index = POLY_RIGHT_HOLE;                                \
    __asm__ volatile ("" : "+r"(right_index));                             \
    Lua55ValueV1 *target = &frame->values[target_index];                   \
    Lua55ValueV1 *left = &frame->values[left_index];                       \
    Lua55ValueV1 *right = &frame->values[right_index];                     \
    right_init;                                                           \
    if (left->tag == LUA55_VALUE_INTEGER && right->tag == LUA55_VALUE_INTEGER) { \
        if (right->payload.integer == 0) { REJECT(frame); LUA55_CPS_HOST_EXIT(frame); }        \
        SET_TAG(target, LUA55_VALUE_INTEGER);                              \
        target->payload.integer = intfn(left->payload.integer, right->payload.integer); \
    } else if (left->tag == LUA55_VALUE_INTEGER && right->tag == LUA55_VALUE_FLOAT) { \
        SET_TAG(target, LUA55_VALUE_FLOAT);                                \
        target->payload.floating = fltfn((double)left->payload.integer, right->payload.floating); \
    } else if (left->tag == LUA55_VALUE_FLOAT && right->tag == LUA55_VALUE_INTEGER) { \
        SET_TAG(target, LUA55_VALUE_FLOAT);                                \
        target->payload.floating = fltfn(left->payload.floating, (double)right->payload.integer); \
    } else if (left->tag == LUA55_VALUE_FLOAT && right->tag == LUA55_VALUE_FLOAT) { \
        SET_TAG(target, LUA55_VALUE_FLOAT);                                \
        target->payload.floating = fltfn(left->payload.floating, right->payload.floating); \
    } else { REJECT(frame); LUA55_CPS_HOST_EXIT(frame); }                                      \
    lua55_residual_next(frame);                                            \
}

#define POLY_BITWISE(name, intfn, right_init)                              \
STENCIL(name)(Lua55LearnFrameV1 *frame)                                    \
{                                                                          \
    uint32_t target_index = POLY_TARGET_HOLE;                              \
    __asm__ volatile ("" : "+r"(target_index));                            \
    uint32_t left_index = POLY_LEFT_HOLE;                                  \
    __asm__ volatile ("" : "+r"(left_index));                              \
    uint32_t right_index = POLY_RIGHT_HOLE;                                \
    __asm__ volatile ("" : "+r"(right_index));                             \
    Lua55ValueV1 *target = &frame->values[target_index];                   \
    Lua55ValueV1 *left = &frame->values[left_index];                       \
    Lua55ValueV1 *right = &frame->values[right_index];                     \
    right_init;                                                            \
    int64_t i1 = 0, i2 = 0;                                                \
    if (left->tag == LUA55_VALUE_INTEGER) i1 = left->payload.integer;      \
    else if (left->tag == LUA55_VALUE_FLOAT && !flt_to_int_eq(left->payload.floating, &i1)) \
        { REJECT(frame); LUA55_CPS_HOST_EXIT(frame); }                                         \
    else if (left->tag != LUA55_VALUE_FLOAT) { REJECT(frame); LUA55_CPS_HOST_EXIT(frame); }    \
    if (right->tag == LUA55_VALUE_INTEGER) i2 = right->payload.integer;    \
    else if (right->tag == LUA55_VALUE_FLOAT && !flt_to_int_eq(right->payload.floating, &i2)) \
        { REJECT(frame); LUA55_CPS_HOST_EXIT(frame); }                                         \
    else if (right->tag != LUA55_VALUE_FLOAT) { REJECT(frame); LUA55_CPS_HOST_EXIT(frame); }   \
    SET_TAG(target, LUA55_VALUE_INTEGER);                                  \
    target->payload.integer = intfn(i1, i2);                               \
    lua55_residual_next(frame);                                            \
}

#define POLY_SHIFT(name, flip, right_init)                                 \
STENCIL(name)(Lua55LearnFrameV1 *frame)                                    \
{                                                                          \
    uint32_t target_index = POLY_TARGET_HOLE;                              \
    __asm__ volatile ("" : "+r"(target_index));                            \
    uint32_t left_index = POLY_LEFT_HOLE;                                  \
    __asm__ volatile ("" : "+r"(left_index));                              \
    uint32_t right_index = POLY_RIGHT_HOLE;                                \
    __asm__ volatile ("" : "+r"(right_index));                             \
    Lua55ValueV1 *target = &frame->values[target_index];                   \
    Lua55ValueV1 *left = &frame->values[left_index];                       \
    Lua55ValueV1 *right = &frame->values[right_index];                     \
    right_init;                                                            \
    int64_t i1 = 0, i2 = 0;                                                \
    if (left->tag == LUA55_VALUE_INTEGER) i1 = left->payload.integer;      \
    else if (left->tag == LUA55_VALUE_FLOAT && !flt_to_int_eq(left->payload.floating, &i1)) \
        { REJECT(frame); LUA55_CPS_HOST_EXIT(frame); }                                         \
    else if (left->tag != LUA55_VALUE_FLOAT) { REJECT(frame); LUA55_CPS_HOST_EXIT(frame); }    \
    if (right->tag == LUA55_VALUE_INTEGER) i2 = right->payload.integer;    \
    else if (right->tag == LUA55_VALUE_FLOAT && !flt_to_int_eq(right->payload.floating, &i2)) \
        { REJECT(frame); LUA55_CPS_HOST_EXIT(frame); }                                         \
    else if (right->tag != LUA55_VALUE_FLOAT) { REJECT(frame); LUA55_CPS_HOST_EXIT(frame); }   \
    SET_TAG(target, LUA55_VALUE_INTEGER);                                  \
    target->payload.integer = flip ? lua55_shiftl(i2, i1) : lua55_shiftl(i1, i2); \
    lua55_residual_next(frame);                                            \
}

#define IMM_RIGHT                                                          \
    Lua55ValueV1 imm_cell;                                                 \
    uint64_t imm_bits = POLY_IMM_HOLE;                                     \
    __asm__ volatile ("" : "+r"(imm_bits));                               \
    SET_TAG(&imm_cell, LUA55_VALUE_INTEGER);                               \
    imm_cell.payload.integer = (int64_t)imm_bits;                          \
    right = &imm_cell;

#define CONST_RIGHT                                                       \
    Lua55ValueV1 const_cell;                                               \
    /* runtime-guarded holes: direct constants let GCC fold the tag test   \
       and erase the patchable patterns (the -k variants had no const      \
       holes and always rejected) */                                      \
    uint32_t const_tag = POLY_CTAG_HOLE;                                   \
    __asm__ volatile ("" : "+r"(const_tag));                             \
    uint64_t const_int_bits = POLY_CINT_HOLE;                              \
    __asm__ volatile ("" : "+r"(const_int_bits));                        \
    uint64_t const_flt_bits = POLY_CFLT_HOLE;                              \
    __asm__ volatile ("" : "+r"(const_flt_bits));                        \
    const_cell.tag = const_tag;                                            \
    /* the payload is a union: fill the interpretation that matches the    \
       tag (a float fill would overwrite the integer bits with 0) */       \
    if (const_tag == LUA55_VALUE_INTEGER)                                  \
        const_cell.payload.integer = (int64_t)const_int_bits;              \
    else                                                                   \
        __builtin_memcpy(&const_cell.payload.floating, &const_flt_bits, 8); \
    right = &const_cell;                                                     \

POLY_BIN(lua55_poly_add, int_add, FLT_ADD, FLT_ADD, FLT_ADD, (void)0)
POLY_BIN(lua55_poly_sub, int_sub, FLT_SUB, FLT_SUB, FLT_SUB, (void)0)
POLY_BIN(lua55_poly_mul, int_mul, FLT_MUL, FLT_MUL, FLT_MUL, (void)0)
POLY_BIN(lua55_poly_addi, int_add, FLT_ADD, FLT_ADD, FLT_ADD, IMM_RIGHT)
POLY_BIN(lua55_poly_addk, int_add, FLT_ADD, FLT_ADD, FLT_ADD, CONST_RIGHT)
POLY_BIN(lua55_poly_subk, int_sub, FLT_SUB, FLT_SUB, FLT_SUB, CONST_RIGHT)
POLY_BIN(lua55_poly_mulk, int_mul, FLT_MUL, FLT_MUL, FLT_MUL, CONST_RIGHT)

#define POLY_DIV_BODY(right_init)                                          \
    uint32_t target_index = POLY_TARGET_HOLE;                              \
    __asm__ volatile ("" : "+r"(target_index));                            \
    uint32_t left_index = POLY_LEFT_HOLE;                                  \
    __asm__ volatile ("" : "+r"(left_index));                              \
    uint32_t right_index = POLY_RIGHT_HOLE;                                \
    __asm__ volatile ("" : "+r"(right_index));                             \
    Lua55ValueV1 *target = &frame->values[target_index];                   \
    Lua55ValueV1 *left = &frame->values[left_index];                       \
    Lua55ValueV1 *right = &frame->values[right_index];                     \
    right_init;                                                            \
    if (left->tag == LUA55_VALUE_INTEGER && right->tag == LUA55_VALUE_INTEGER) { \
        if (right->payload.integer == 0) { REJECT(frame); LUA55_CPS_HOST_EXIT(frame); }        \
        SET_TAG(target, LUA55_VALUE_FLOAT);                                \
        target->payload.floating = (double)left->payload.integer / (double)right->payload.integer; \
    } else if (left->tag == LUA55_VALUE_INTEGER && right->tag == LUA55_VALUE_FLOAT) { \
        SET_TAG(target, LUA55_VALUE_FLOAT);                                \
        target->payload.floating = (double)left->payload.integer / right->payload.floating; \
    } else if (left->tag == LUA55_VALUE_FLOAT && right->tag == LUA55_VALUE_INTEGER) { \
        SET_TAG(target, LUA55_VALUE_FLOAT);                                \
        target->payload.floating = left->payload.floating / (double)right->payload.integer; \
    } else if (left->tag == LUA55_VALUE_FLOAT && right->tag == LUA55_VALUE_FLOAT) { \
        SET_TAG(target, LUA55_VALUE_FLOAT);                                \
        target->payload.floating = left->payload.floating / right->payload.floating; \
    } else { REJECT(frame); LUA55_CPS_HOST_EXIT(frame); }                                      \
    lua55_residual_next(frame);


STENCIL(lua55_poly_div)(Lua55LearnFrameV1 *frame) { POLY_DIV_BODY((void)0) }
STENCIL(lua55_poly_divk)(Lua55LearnFrameV1 *frame) { POLY_DIV_BODY(CONST_RIGHT) }

POLY_DIVMOD(lua55_poly_idiv, lua55_idiv, lua55_flt_idiv, (void)0)
POLY_DIVMOD(lua55_poly_mod, lua55_mod, lua55_fmod, (void)0)
POLY_DIVMOD(lua55_poly_idivk, lua55_idiv, lua55_flt_idiv, CONST_RIGHT)
POLY_DIVMOD(lua55_poly_modk, lua55_mod, lua55_fmod, CONST_RIGHT)

POLY_BITWISE(lua55_poly_band, int_band, (void)0)
POLY_BITWISE(lua55_poly_bor, int_bor, (void)0)
POLY_BITWISE(lua55_poly_bxor, int_bxor, (void)0)
POLY_BITWISE(lua55_poly_bandk, int_band, CONST_RIGHT)
POLY_BITWISE(lua55_poly_bork, int_bor, CONST_RIGHT)
POLY_BITWISE(lua55_poly_bxork, int_bxor, CONST_RIGHT)

POLY_SHIFT(lua55_poly_shl, 0, (void)0)
POLY_SHIFT(lua55_poly_shr, 0, (void)0)
POLY_SHIFT(lua55_poly_shli, 0, IMM_RIGHT)
POLY_SHIFT(lua55_poly_shri, 0, IMM_RIGHT)
