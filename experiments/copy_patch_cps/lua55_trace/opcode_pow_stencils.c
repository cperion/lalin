#include "opcode_value_v1.h"
#include "opcode_value_v1.h"
#include "opcode_value_v2.h"
/* Batch 5: POW (38) and POWK (26) — exponentiation. Stock semantics are
   floats-only (lobject.c: luaO_rawarith LUA_OPPOW "operate only on
   floats"): both operands convert to double, the result is always a
   float. luai_numpow has a fast path: exponent == 2.0 computes a*a.
   Non-numeric operands take the __pow metamethod path (REJECT).
   pow() is an external libm symbol: the stencils call it through a
   patched absolute address (dlsym-resolved at extension time) — an
   immediate hole in the instruction stream, so the bank has no
   relocations to external symbols. */

#define ARITH_TARGET_INDEX UINT32_C(0x111)
#define ARITH_LEFT_INDEX   UINT32_C(0x222)
#define ARITH_RIGHT_INDEX  UINT32_C(0x333)

#define QUOTE_BASE_HOLE UINT32_C(0x0f1e2d3c)
#define RESUME_HOLE UINT32_C(0x66778899)
#define POW_ADDRESS_HOLE UINT64_C(0x5152535455565758)
#define CONST_TAG_HOLE UINT32_C(0x3c3b3a39)
#define CONST_INT_HOLE UINT64_C(0x2122232425262728)
#define CONST_FLT_HOLE UINT64_C(0x123456789abcdef0)

#define GUARD_FAILED(frame) do {            \
    (frame)->resume_pc = RESUME_HOLE;        \
    (frame)->status = LUA55_GUARD_FAILED;    \
} while (0)

#define REJECT(frame) do {                  \
    (frame)->resume_pc = RESUME_HOLE;        \
    (frame)->status = LUA55_REJECTED;        \
} while (0)

typedef double (*lua55_pow_fn)(double, double);

/* b == 2.0 via bit compare (no rodata constant -> no PC32 relocation). */
static inline int pow_exponent_is_two(double b)
{
    uint64_t bits;
    __builtin_memcpy(&bits, &b, sizeof(bits));
    return bits == UINT64_C(0x4000000000000000);
}

/* pow via the patched libm address; luai_numpow's b==2.0 fast path. */
static inline double lua55_pow(double a, double b)
{
    uint64_t addr = POW_ADDRESS_HOLE;
    __asm__ volatile ("" : "+r"(addr));
    lua55_pow_fn fn;
    __builtin_memcpy(&fn, &addr, sizeof(fn));
    if (pow_exponent_is_two(b)) return a * a;
    return fn(a, b);
}

/* ------------------------------------------------------------------ */
/* POW (38): register-register. Leaf 1=ii 2=if 3=fi 4=ff.               */

STENCIL(lua55_learn_pow)(Lua55LearnFrameV1 *frame)
{
    Lua55ValueV1 *target = &frame->values[ARITH_TARGET_INDEX];
    Lua55ValueV1 *left = &frame->values[ARITH_LEFT_INDEX];
    Lua55ValueV1 *right = &frame->values[ARITH_RIGHT_INDEX];
    Lua55RecordingSlotV1 *slot = next_slot(frame);
    uint32_t base = QUOTE_BASE_HOLE;
    __asm__ volatile ("" : "+r"(base));
    if (left->tag == LUA55_VALUE_INTEGER && right->tag == LUA55_VALUE_INTEGER) {
        SET_TAG(target, LUA55_VALUE_FLOAT);
        target->payload.floating = lua55_pow(
            (double)left->payload.integer, (double)right->payload.integer);
        slot->quote = base | 1;
    } else if (left->tag == LUA55_VALUE_INTEGER && right->tag == LUA55_VALUE_FLOAT) {
        SET_TAG(target, LUA55_VALUE_FLOAT);
        target->payload.floating = lua55_pow(
            (double)left->payload.integer, right->payload.floating);
        slot->quote = base | 2;
    } else if (left->tag == LUA55_VALUE_FLOAT && right->tag == LUA55_VALUE_INTEGER) {
        SET_TAG(target, LUA55_VALUE_FLOAT);
        target->payload.floating = lua55_pow(
            left->payload.floating, (double)right->payload.integer);
        slot->quote = base | 3;
    } else if (left->tag == LUA55_VALUE_FLOAT && right->tag == LUA55_VALUE_FLOAT) {
        SET_TAG(target, LUA55_VALUE_FLOAT);
        target->payload.floating = lua55_pow(left->payload.floating, right->payload.floating);
        slot->quote = base | 4;
    } else {
        slot->quote = LUA55_QUOTE_REJECTED; REJECT(frame); return;
    }
    lua55_learn_next(frame);
}

/* POWK (26): register-constant. Leaf by (reg, const) tag. */

STENCIL(lua55_learn_powk)(Lua55LearnFrameV1 *frame)
{
    Lua55ValueV1 *target = &frame->values[ARITH_TARGET_INDEX];
    Lua55ValueV1 *left = &frame->values[ARITH_LEFT_INDEX];
    Lua55RecordingSlotV1 *slot = next_slot(frame);
    uint32_t base = QUOTE_BASE_HOLE;
    __asm__ volatile ("" : "+r"(base));
    uint32_t ctag = CONST_TAG_HOLE;
    __asm__ volatile ("" : "+r"(ctag));
    int64_t cint = (int64_t)CONST_INT_HOLE;
    __asm__ volatile ("" : "+r"(cint));
    uint64_t cflt_bits = CONST_FLT_HOLE;
    __asm__ volatile ("" : "+r"(cflt_bits));
    double cflt;
    __builtin_memcpy(&cflt, &cflt_bits, sizeof(cflt));
    uint32_t leaf;
    if (left->tag == LUA55_VALUE_INTEGER && ctag == LUA55_VALUE_INTEGER) {
        SET_TAG(target, LUA55_VALUE_FLOAT);
        target->payload.floating = lua55_pow((double)left->payload.integer, (double)cint);
        leaf = 1;
    } else if (left->tag == LUA55_VALUE_INTEGER && ctag == LUA55_VALUE_FLOAT) {
        SET_TAG(target, LUA55_VALUE_FLOAT);
        target->payload.floating = lua55_pow((double)left->payload.integer, cflt);
        leaf = 2;
    } else if (left->tag == LUA55_VALUE_FLOAT && ctag == LUA55_VALUE_INTEGER) {
        SET_TAG(target, LUA55_VALUE_FLOAT);
        target->payload.floating = lua55_pow(left->payload.floating, (double)cint);
        leaf = 3;
    } else if (left->tag == LUA55_VALUE_FLOAT && ctag == LUA55_VALUE_FLOAT) {
        SET_TAG(target, LUA55_VALUE_FLOAT);
        target->payload.floating = lua55_pow(left->payload.floating, cflt);
        leaf = 4;
    } else {
        slot->quote = LUA55_QUOTE_REJECTED; REJECT(frame); return;
    }
    slot->quote = base | leaf;
    lua55_learn_next(frame);
}

/* ------------------------------------------------------------------ */
/* RESIDUALS                                                             */

#define RESIDUAL_POW(name, lt, rt)                                      \
STENCIL(name)(Lua55LearnFrameV1 *frame)                                 \
{                                                                       \
    Lua55ValueV1 *target = &frame->values[ARITH_TARGET_INDEX];          \
    Lua55ValueV1 *left = &frame->values[ARITH_LEFT_INDEX];              \
    Lua55ValueV1 *right = &frame->values[ARITH_RIGHT_INDEX];            \
    if (left->tag != (lt) || right->tag != (rt)) { GUARD_FAILED(frame); return; } \
    SET_TAG(target, LUA55_VALUE_FLOAT);                                 \
    if ((lt) == LUA55_VALUE_INTEGER && (rt) == LUA55_VALUE_INTEGER)     \
        target->payload.floating = lua55_pow((double)left->payload.integer, \
            (double)right->payload.integer);                            \
    else if ((lt) == LUA55_VALUE_INTEGER)                               \
        target->payload.floating = lua55_pow((double)left->payload.integer, \
            right->payload.floating);                                   \
    else if ((rt) == LUA55_VALUE_INTEGER)                               \
        target->payload.floating = lua55_pow(left->payload.floating,    \
            (double)right->payload.integer);                            \
    else                                                                \
        target->payload.floating = lua55_pow(left->payload.floating,    \
            right->payload.floating);                                   \
    lua55_residual_next(frame);                                         \
}

RESIDUAL_POW(lua55_residual_pow_ii, LUA55_VALUE_INTEGER, LUA55_VALUE_INTEGER)
RESIDUAL_POW(lua55_residual_pow_if, LUA55_VALUE_INTEGER, LUA55_VALUE_FLOAT)
RESIDUAL_POW(lua55_residual_pow_fi, LUA55_VALUE_FLOAT, LUA55_VALUE_INTEGER)
RESIDUAL_POW(lua55_residual_pow_ff, LUA55_VALUE_FLOAT, LUA55_VALUE_FLOAT)

#define RESIDUAL_POWK(name, lt, ctag_expect)                            \
STENCIL(name)(Lua55LearnFrameV1 *frame)                                 \
{                                                                       \
    Lua55ValueV1 *target = &frame->values[ARITH_TARGET_INDEX];          \
    Lua55ValueV1 *left = &frame->values[ARITH_LEFT_INDEX];              \
    if (left->tag != (lt)) { GUARD_FAILED(frame); return; }             \
    int64_t cint = (int64_t)CONST_INT_HOLE;                             \
    __asm__ volatile ("" : "+r"(cint));                                 \
    uint64_t cflt_bits = CONST_FLT_HOLE;                                \
    __asm__ volatile ("" : "+r"(cflt_bits));                            \
    double cflt;                                                        \
    __builtin_memcpy(&cflt, &cflt_bits, sizeof(cflt));                  \
    SET_TAG(target, LUA55_VALUE_FLOAT);                                 \
    if ((lt) == LUA55_VALUE_INTEGER && (ctag_expect) == LUA55_VALUE_INTEGER) \
        target->payload.floating = lua55_pow((double)left->payload.integer, \
            (double)cint);                                              \
    else if ((lt) == LUA55_VALUE_INTEGER)                               \
        target->payload.floating = lua55_pow((double)left->payload.integer, cflt); \
    else if ((ctag_expect) == LUA55_VALUE_INTEGER)                      \
        target->payload.floating = lua55_pow(left->payload.floating, (double)cint); \
    else                                                                \
        target->payload.floating = lua55_pow(left->payload.floating, cflt); \
    lua55_residual_next(frame);                                         \
}

RESIDUAL_POWK(lua55_residual_powk_ii, LUA55_VALUE_INTEGER, LUA55_VALUE_INTEGER)
RESIDUAL_POWK(lua55_residual_powk_if, LUA55_VALUE_INTEGER, LUA55_VALUE_FLOAT)
RESIDUAL_POWK(lua55_residual_powk_fi, LUA55_VALUE_FLOAT, LUA55_VALUE_INTEGER)
RESIDUAL_POWK(lua55_residual_powk_ff, LUA55_VALUE_FLOAT, LUA55_VALUE_FLOAT)

/* Self-selecting POW / POWK: floats-only exponentiation through the patched
   libm pow address; the tag dispatch IS the selection. */
#define POW_POLY_TARGET UINT32_C(0x111)
#define POW_POLY_LEFT UINT32_C(0x222)
#define POW_POLY_RIGHT UINT32_C(0x333)
#define POW_CONST_TAG UINT32_C(0x3c3b3a39)
#define POW_CONST_INT UINT64_C(0x2122232425262728)
#define POW_CONST_FLT UINT64_C(0x123456789abcdef0)

#define POLY_POW_BODY(right_init)                                          \
    uint32_t target_index = POW_POLY_TARGET;                               \
    __asm__ volatile ("" : "+r"(target_index));                            \
    uint32_t left_index = POW_POLY_LEFT;                                   \
    __asm__ volatile ("" : "+r"(left_index));                              \
    uint32_t right_index = POW_POLY_RIGHT;                                 \
    __asm__ volatile ("" : "+r"(right_index));                             \
    Lua55ValueV1 *target = &frame->values[target_index];                   \
    Lua55ValueV1 *left = &frame->values[left_index];                       \
    Lua55ValueV1 *right = &frame->values[right_index];                     \
    right_init;                                                            \
    if (left->tag == LUA55_VALUE_INTEGER && right->tag == LUA55_VALUE_INTEGER) { \
        SET_TAG(target, LUA55_VALUE_FLOAT);                                \
        target->payload.floating = lua55_pow(                              \
            (double)left->payload.integer, (double)right->payload.integer); \
    } else if (left->tag == LUA55_VALUE_INTEGER && right->tag == LUA55_VALUE_FLOAT) { \
        SET_TAG(target, LUA55_VALUE_FLOAT);                                \
        target->payload.floating = lua55_pow(                              \
            (double)left->payload.integer, right->payload.floating);       \
    } else if (left->tag == LUA55_VALUE_FLOAT && right->tag == LUA55_VALUE_INTEGER) { \
        SET_TAG(target, LUA55_VALUE_FLOAT);                                \
        target->payload.floating = lua55_pow(                              \
            left->payload.floating, (double)right->payload.integer);       \
    } else if (left->tag == LUA55_VALUE_FLOAT && right->tag == LUA55_VALUE_FLOAT) { \
        SET_TAG(target, LUA55_VALUE_FLOAT);                                \
        target->payload.floating = lua55_pow(left->payload.floating, right->payload.floating); \
    } else { REJECT(frame); LUA55_CPS_HOST_EXIT(frame); }                                      \
    lua55_residual_next(frame);

STENCIL(lua55_poly_pow)(Lua55LearnFrameV1 *frame)
{
    POLY_POW_BODY((void)0)
}

STENCIL(lua55_poly_powk)(Lua55LearnFrameV1 *frame)
{
    Lua55ValueV1 const_cell;
    /* runtime-guarded holes (see arith CONST_RIGHT) */
    uint32_t const_tag = POW_CONST_TAG;
    __asm__ volatile ("" : "+r"(const_tag));
    uint64_t const_int_bits = POW_CONST_INT;
    __asm__ volatile ("" : "+r"(const_int_bits));
    uint64_t const_flt_bits = POW_CONST_FLT;
    __asm__ volatile ("" : "+r"(const_flt_bits));
    const_cell.tag = const_tag;
    if (const_tag == LUA55_VALUE_INTEGER)
        const_cell.payload.integer = (int64_t)const_int_bits;
    else
        __builtin_memcpy(&const_cell.payload.floating, &const_flt_bits, 8);
    POLY_POW_BODY({ Lua55ValueV1 *right = &frame->values[right_index]; (void)right; right = &const_cell; })
}
