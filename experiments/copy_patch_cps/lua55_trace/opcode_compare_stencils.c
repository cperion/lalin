#include "opcode_value_v1.h"
#include "opcode_value_v1.h"
#include "opcode_value_v2.h"
/* Batch 1: comparisons and tests (opcodes 57-67) with their owned JMP.
   All numeric helpers are inline (no libc calls) so every extracted stencil
   is self-contained apart from the terminal learn/residual successor.
   NOTE: no_callee_saved_registers (VMIL'25) is NOT applied: every stencil
   returns to the LuaJIT FFI caller via `ret` (branch, guard, or finish
   exits), so SysV callee-saved preservation is mandatory at the entry. */
#define CMP_STENCIL(name)                                                            \
    __attribute__((section(".text." #name), aligned(1), noinline, noclone, used)) \
    void name
#define LEFT_INDEX TARGET_INDEX   /* 0x111 */
#define RIGHT_INDEX SOURCE_INDEX  /* 0x222 */

#define TARGET_PC_HOLE UINT32_C(0x10203040)      /* taken-branch resume pc */
#define QUOTE_BASE_HOLE UINT32_C(0x0f1e2d3c)     /* opcode << 16 */
#define INT_IMM_HOLE UINT64_C(0x1112131415161718)
#define CONST_INT_HOLE UINT64_C(0x2122232425262728)
#define CONST_FLT_HOLE UINT64_C(0x123456789abcdef0)
#define CONST_REF_HOLE UINT64_C(0x0abcdef012345679)
#define CONST_TAG_HOLE UINT32_C(0x3c3b3a39)

#define BRANCH_TAKEN(frame) do {                 \
    (frame)->resume_pc = TARGET_PC_HOLE;         \
    (frame)->status = LUA55_COMPLETED;           \
} while (0)

#define GUARD_FAILED(frame) do {                 \
    (frame)->resume_pc = RESUME_PC;              \
    (frame)->status = LUA55_GUARD_FAILED;        \
} while (0)

#define REJECT(frame) do {                       \
    (frame)->resume_pc = RESUME_PC;              \
    (frame)->status = LUA55_REJECTED;            \
} while (0)

/* --- exact numeric semantics (lvm.c: LTintfloat/LEintfloat/... F2I* modes) */

static inline int magnitude_at_least_2_63(double x)
{
    uint64_t bits;
    __builtin_memcpy(&bits, &x, sizeof(bits));
    return ((bits & UINT64_C(0x7ff0000000000000)) >> 52) >= UINT64_C(0x43e);
}

/* exact floor/ceil for |x| < 2^63 via integer truncation; no double constants */
static inline double lua55_floor(double x)
{
    if (magnitude_at_least_2_63(x)) return x;
    int64_t i = (int64_t)x;
    double t = (double)i;
    if (x < 0 && t != x) t = (double)(i - 1);
    return t;
}

static inline double lua55_ceil(double x)
{
    if (magnitude_at_least_2_63(x)) return x;
    int64_t i = (int64_t)x;
    double t = (double)i;
    if (x > 0 && t != x) t = (double)(i + 1);
    return t;
}

/* mode 0 = F2Ieq, 1 = F2Iceil, 2 = F2Ifloor; range check on the rounded value */
static inline int flt_to_int(double f, int64_t *out, int mode)
{
    if (f != f) return 0;                 /* NaN never converts */
    double v = lua55_floor(f);
    if (v != f) {
        if (mode == 0) return 0;          /* F2Ieq rejects non-integral */
        if (mode == 1) v = lua55_ceil(f); /* F2Iceil */
    }
    if (magnitude_at_least_2_63(v)) return 0;
    *out = (int64_t)v;
    return 1;
}

static inline int int_fits_float(int64_t i)
{
    return (-((int64_t)1 << 52) <= i && i <= ((int64_t)1 << 52));
}

static inline int eq_int_float(int64_t i, double f)
{
    int64_t fi;
    return flt_to_int(f, &fi, 0) && i == fi;
}

static inline int lt_int_float(int64_t i, double f)
{
    if (int_fits_float(i)) return (double)i < f;
    int64_t fi;
    if (flt_to_int(f, &fi, 1)) return i < fi;
    return f > 0;
}

static inline int le_int_float(int64_t i, double f)
{
    if (int_fits_float(i)) return (double)i <= f;
    int64_t fi;
    if (flt_to_int(f, &fi, 2)) return i <= fi;
    return f > 0;
}

static inline int lt_float_int(double f, int64_t i)
{
    if (int_fits_float(i)) return f < (double)i;
    int64_t fi;
    if (flt_to_int(f, &fi, 2)) return fi < i;
    return f < 0;
}

static inline int le_float_int(double f, int64_t i)
{
    if (int_fits_float(i)) return f <= (double)i;
    int64_t fi;
    if (flt_to_int(f, &fi, 1)) return fi <= i;
    return f < 0;
}

/* --- strings (byte order, embedded NULs are ordinary bytes) */

static inline Lua55GuestStringV1 *guest_string(uintptr_t reference)
{
    return (Lua55GuestStringV1 *)reference;
}

static inline int string_bytes_eq(uintptr_t ra, uintptr_t rb)
{
    Lua55GuestStringV1 *a = guest_string(ra);
    Lua55GuestStringV1 *b = guest_string(rb);
    uint32_t n = a->length;
    if (b->length != n) return 0;
    for (uint32_t i = 0; i < n; i++)
        if (a->bytes[i] != b->bytes[i]) return 0;
    return 1;
}

static inline int string_cmp(uintptr_t ra, uintptr_t rb)
{
    Lua55GuestStringV1 *a = guest_string(ra);
    Lua55GuestStringV1 *b = guest_string(rb);
    uint32_t n = a->length < b->length ? a->length : b->length;
    for (uint32_t i = 0; i < n; i++) {
        if (a->bytes[i] != b->bytes[i])
            return a->bytes[i] < b->bytes[i] ? -1 : 1;
    }
    return a->length < b->length ? -1 : (a->length > b->length ? 1 : 0);
}

static inline int is_string_tag(uint32_t tag)
{
    return tag == LUA55_VALUE_SHORT_STRING || tag == LUA55_VALUE_LONG_STRING;
}

static inline int truthy(uint32_t tag)
{
    return !(tag == LUA55_VALUE_NIL || tag == LUA55_VALUE_FALSE);
}

/* ------------------------------------------------------------------ */
/* LEARNERS: per opcode and accept bit; select the leaf by runtime tag. */

#define LEARN_REGRES(name, k)                                                \
CMP_STENCIL(lua55_learn_##name##_k##k)(Lua55LearnFrameV1 *frame)                 \
{                                                                            \
    Lua55ValueV1 *left = &frame->values[LEFT_INDEX];                         \
    Lua55ValueV1 *right = &frame->values[RIGHT_INDEX];                       \
    Lua55RecordingSlotV1 *slot = next_slot(frame);                           \
    uint32_t base = QUOTE_BASE_HOLE;                                         \
    __asm__ volatile ("" : "+r"(base));                                      \
    uint32_t leaf; int cond;                                                 \
    if (left->tag == LUA55_VALUE_INTEGER && right->tag == LUA55_VALUE_INTEGER) { \
        leaf = 1; cond = left->payload.integer < right->payload.integer;     \
    } else if (left->tag == LUA55_VALUE_INTEGER && right->tag == LUA55_VALUE_FLOAT) { \
        leaf = 2; cond = lt_int_float(left->payload.integer, right->payload.floating); \
    } else if (left->tag == LUA55_VALUE_FLOAT && right->tag == LUA55_VALUE_INTEGER) { \
        leaf = 3; cond = lt_float_int(left->payload.floating, right->payload.integer); \
    } else if (left->tag == LUA55_VALUE_FLOAT && right->tag == LUA55_VALUE_FLOAT) { \
        leaf = 4; cond = left->payload.floating < right->payload.floating;   \
    } else if (is_string_tag(left->tag) && is_string_tag(right->tag)) {      \
        leaf = 5 + ((left->tag == LUA55_VALUE_LONG_STRING) ? 1 : 0)          \
                 + ((right->tag == LUA55_VALUE_LONG_STRING) ? 2 : 0);        \
        cond = string_cmp(left->payload.reference, right->payload.reference) < 0; \
    } else {                                                                 \
        slot->quote = LUA55_QUOTE_REJECTED; REJECT(frame); return;           \
    }                                                                        \
    slot->quote = base | (leaf << 1) | (k);                                  \
    if (cond == (k)) { BRANCH_TAKEN(frame); return; }                        \
    lua55_learn_next(frame);                                                 \
}

#define LEARN_EQ_K(k)                                                        \
CMP_STENCIL(lua55_learn_eq_k##k)(Lua55LearnFrameV1 *frame)                       \
{                                                                            \
    Lua55ValueV1 *left = &frame->values[LEFT_INDEX];                         \
    Lua55ValueV1 *right = &frame->values[RIGHT_INDEX];                       \
    Lua55RecordingSlotV1 *slot = next_slot(frame);                           \
    uint32_t base = QUOTE_BASE_HOLE;                                         \
    __asm__ volatile ("" : "+r"(base));                                      \
    uint32_t leaf; int cond;                                                 \
    if (left->tag == LUA55_VALUE_INTEGER && right->tag == LUA55_VALUE_INTEGER) { \
        leaf = 1; cond = left->payload.integer == right->payload.integer;    \
    } else if (left->tag == LUA55_VALUE_INTEGER && right->tag == LUA55_VALUE_FLOAT) { \
        leaf = 2; cond = eq_int_float(left->payload.integer, right->payload.floating); \
    } else if (left->tag == LUA55_VALUE_FLOAT && right->tag == LUA55_VALUE_INTEGER) { \
        leaf = 3; cond = eq_int_float(right->payload.integer, left->payload.floating); \
    } else if (left->tag == LUA55_VALUE_FLOAT && right->tag == LUA55_VALUE_FLOAT) { \
        leaf = 4; cond = left->payload.floating == right->payload.floating;  \
    } else if (is_string_tag(left->tag) && is_string_tag(right->tag)) {      \
        leaf = 5 + ((left->tag == LUA55_VALUE_LONG_STRING) ? 1 : 0)          \
                 + ((right->tag == LUA55_VALUE_LONG_STRING) ? 2 : 0);        \
        cond = string_bytes_eq(left->payload.reference, right->payload.reference); \
    } else if (left->tag == LUA55_VALUE_NIL && right->tag == LUA55_VALUE_NIL) { \
        leaf = 9; cond = 1;                                                  \
    } else if (left->tag == LUA55_VALUE_FALSE && right->tag == LUA55_VALUE_FALSE) { \
        leaf = 10; cond = 1;                                                 \
    } else if (left->tag == LUA55_VALUE_TRUE && right->tag == LUA55_VALUE_TRUE) { \
        leaf = 11; cond = 1;                                                 \
    } else if (left->tag <= LUA55_VALUE_LONG_STRING &&                         \
               right->tag <= LUA55_VALUE_LONG_STRING) {                       \
        leaf = 12; cond = 0;   /* different supported tags are never equal */ \
    } else {                                                                 \
        slot->quote = LUA55_QUOTE_REJECTED; REJECT(frame); return;           \
    }                                                                        \
    slot->quote = base | (leaf << 1) | (k);                                  \
    if (cond == (k)) { BRANCH_TAKEN(frame); return; }                        \
    lua55_learn_next(frame);                                                 \
}

LEARN_EQ_K(0)
LEARN_EQ_K(1)
LEARN_REGRES(lt, 0)
LEARN_REGRES(lt, 1)

#define LEARN_LE_K(k)                                                        \
CMP_STENCIL(lua55_learn_le_k##k)(Lua55LearnFrameV1 *frame)                       \
{                                                                            \
    Lua55ValueV1 *left = &frame->values[LEFT_INDEX];                         \
    Lua55ValueV1 *right = &frame->values[RIGHT_INDEX];                       \
    Lua55RecordingSlotV1 *slot = next_slot(frame);                           \
    uint32_t base = QUOTE_BASE_HOLE;                                         \
    __asm__ volatile ("" : "+r"(base));                                      \
    uint32_t leaf; int cond;                                                 \
    if (left->tag == LUA55_VALUE_INTEGER && right->tag == LUA55_VALUE_INTEGER) { \
        leaf = 1; cond = left->payload.integer <= right->payload.integer;    \
    } else if (left->tag == LUA55_VALUE_INTEGER && right->tag == LUA55_VALUE_FLOAT) { \
        leaf = 2; cond = le_int_float(left->payload.integer, right->payload.floating); \
    } else if (left->tag == LUA55_VALUE_FLOAT && right->tag == LUA55_VALUE_INTEGER) { \
        leaf = 3; cond = le_float_int(left->payload.floating, right->payload.integer); \
    } else if (left->tag == LUA55_VALUE_FLOAT && right->tag == LUA55_VALUE_FLOAT) { \
        leaf = 4; cond = left->payload.floating <= right->payload.floating;  \
    } else if (is_string_tag(left->tag) && is_string_tag(right->tag)) {      \
        leaf = 5 + ((left->tag == LUA55_VALUE_LONG_STRING) ? 1 : 0)          \
                 + ((right->tag == LUA55_VALUE_LONG_STRING) ? 2 : 0);        \
        cond = string_cmp(left->payload.reference, right->payload.reference) <= 0; \
    } else {                                                                 \
        slot->quote = LUA55_QUOTE_REJECTED; REJECT(frame); return;           \
    }                                                                        \
    slot->quote = base | (leaf << 1) | (k);                                  \
    if (cond == (k)) { BRANCH_TAKEN(frame); return; }                        \
    lua55_learn_next(frame);                                                 \
}

LEARN_LE_K(0)
LEARN_LE_K(1)

#define LEARN_REG_IMM(name, k)                                               \
CMP_STENCIL(lua55_learn_##name##_k##k)(Lua55LearnFrameV1 *frame)                 \
{                                                                            \
    Lua55ValueV1 *left = &frame->values[LEFT_INDEX];                         \
    Lua55RecordingSlotV1 *slot = next_slot(frame);                           \
    uint32_t base = QUOTE_BASE_HOLE;                                         \
    __asm__ volatile ("" : "+r"(base));                                      \
    int64_t im = (int64_t)INT_IMM_HOLE;                                      \
    __asm__ volatile ("" : "+r"(im));                                        \
    uint32_t leaf; int cond;                                                 \
    if (left->tag == LUA55_VALUE_INTEGER) { leaf = 1; cond = left->payload.integer < im; } \
    else if (left->tag == LUA55_VALUE_FLOAT) { leaf = 2; cond = left->payload.floating < (double)im; } \
    else { slot->quote = LUA55_QUOTE_REJECTED; REJECT(frame); return; }      \
    slot->quote = base | (leaf << 1) | (k);                                  \
    if (cond == (k)) { BRANCH_TAKEN(frame); return; }                        \
    lua55_learn_next(frame);                                                 \
}

LEARN_REG_IMM(lti, 0)
LEARN_REG_IMM(lti, 1)

#define LEARN_REG_IMM_OP(name, op, k)                                        \
CMP_STENCIL(lua55_learn_##name##_k##k)(Lua55LearnFrameV1 *frame)                 \
{                                                                            \
    Lua55ValueV1 *left = &frame->values[LEFT_INDEX];                         \
    Lua55RecordingSlotV1 *slot = next_slot(frame);                           \
    uint32_t base = QUOTE_BASE_HOLE;                                         \
    __asm__ volatile ("" : "+r"(base));                                      \
    int64_t im = (int64_t)INT_IMM_HOLE;                                      \
    __asm__ volatile ("" : "+r"(im));                                        \
    uint32_t leaf; int cond;                                                 \
    if (left->tag == LUA55_VALUE_INTEGER) { leaf = 1; cond = left->payload.integer op im; } \
    else if (left->tag == LUA55_VALUE_FLOAT) { leaf = 2; cond = left->payload.floating op (double)im; } \
    else { slot->quote = LUA55_QUOTE_REJECTED; REJECT(frame); return; }      \
    slot->quote = base | (leaf << 1) | (k);                                  \
    if (cond == (k)) { BRANCH_TAKEN(frame); return; }                        \
    lua55_learn_next(frame);                                                 \
}

LEARN_REG_IMM_OP(eqi, ==, 0)
LEARN_REG_IMM_OP(eqi, ==, 1)
LEARN_REG_IMM_OP(lei, <=, 0)
LEARN_REG_IMM_OP(lei, <=, 1)
LEARN_REG_IMM_OP(gti, >, 0)
LEARN_REG_IMM_OP(gti, >, 1)
LEARN_REG_IMM_OP(gei, >=, 0)
LEARN_REG_IMM_OP(gei, >=, 1)

#define LEARN_EQK_K(k)                                                       \
CMP_STENCIL(lua55_learn_eqk_k##k)(Lua55LearnFrameV1 *frame)                      \
{                                                                            \
    Lua55ValueV1 *left = &frame->values[LEFT_INDEX];                         \
    Lua55RecordingSlotV1 *slot = next_slot(frame);                           \
    uint32_t base = QUOTE_BASE_HOLE;                                         \
    __asm__ volatile ("" : "+r"(base));                                      \
    uint32_t ctag = CONST_TAG_HOLE;                                          \
    __asm__ volatile ("" : "+r"(ctag));                                      \
    int64_t cint = (int64_t)CONST_INT_HOLE;                                  \
    __asm__ volatile ("" : "+r"(cint));                                      \
    uint64_t cflt_bits = CONST_FLT_HOLE;                                       \
    __asm__ volatile ("" : "+r"(cflt_bits));                                \
    double cflt;                                                              \
    __builtin_memcpy(&cflt, &cflt_bits, sizeof(cflt));                        \
    uintptr_t cref = (uintptr_t)CONST_REF_HOLE;                              \
    __asm__ volatile ("" : "+r"(cref));                                      \
    uint32_t leaf; int cond;                                                 \
    if (left->tag == LUA55_VALUE_INTEGER && ctag == LUA55_VALUE_INTEGER) {   \
        leaf = 1; cond = left->payload.integer == cint;                      \
    } else if (left->tag == LUA55_VALUE_FLOAT && ctag == LUA55_VALUE_FLOAT) { \
        leaf = 2; cond = left->payload.floating == cflt;                     \
    } else if (left->tag == LUA55_VALUE_INTEGER && ctag == LUA55_VALUE_FLOAT) { \
        leaf = 3; cond = eq_int_float(left->payload.integer, cflt);          \
    } else if (left->tag == LUA55_VALUE_FLOAT && ctag == LUA55_VALUE_INTEGER) { \
        leaf = 4; cond = eq_int_float(cint, left->payload.floating);         \
    } else if (is_string_tag(left->tag) && is_string_tag(ctag)) {            \
        leaf = 5 + ((left->tag == LUA55_VALUE_LONG_STRING) ? 1 : 0)          \
                 + ((ctag == LUA55_VALUE_LONG_STRING) ? 2 : 0);              \
        cond = string_bytes_eq(left->payload.reference, cref);               \
    } else if (left->tag == ctag && ctag <= LUA55_VALUE_TRUE) {              \
        leaf = 9 + ctag; cond = 1;                                           \
    } else {                                                                 \
        slot->quote = LUA55_QUOTE_REJECTED; REJECT(frame); return;           \
    }                                                                        \
    slot->quote = base | (leaf << 1) | (k);                                  \
    if (cond == (k)) { BRANCH_TAKEN(frame); return; }                        \
    lua55_learn_next(frame);                                                 \
}

LEARN_EQK_K(0)
LEARN_EQK_K(1)

#define LEARN_TRUTHY(name, k)                                                \
CMP_STENCIL(lua55_learn_##name##_k##k)(Lua55LearnFrameV1 *frame)                 \
{                                                                            \
    Lua55ValueV1 *left = &frame->values[LEFT_INDEX];                         \
    Lua55RecordingSlotV1 *slot = next_slot(frame);                           \
    uint32_t base = QUOTE_BASE_HOLE;                                         \
    __asm__ volatile ("" : "+r"(base));                                      \
    int cond = truthy(left->tag);                                            \
    slot->quote = base | (1 << 1) | (k);                                     \
    if (cond == (k)) { BRANCH_TAKEN(frame); return; }                        \
    lua55_learn_next(frame);                                                 \
}

LEARN_TRUTHY(test, 0)
LEARN_TRUTHY(test, 1)

#define LEARN_TESTSET_K(k)                                                   \
CMP_STENCIL(lua55_learn_teskset_k##k)(Lua55LearnFrameV1 *frame)                  \
{                                                                            \
    Lua55ValueV1 *left = &frame->values[LEFT_INDEX];                         \
    Lua55ValueV1 *right = &frame->values[RIGHT_INDEX];                       \
    Lua55RecordingSlotV1 *slot = next_slot(frame);                           \
    uint32_t base = QUOTE_BASE_HOLE;                                         \
    __asm__ volatile ("" : "+r"(base));                                      \
    int cond = truthy(right->tag);                                           \
    slot->quote = base | (1 << 1) | (k);                                     \
    if (cond == (k)) {                                                       \
        *left = *right;                                                      \
        BRANCH_TAKEN(frame); return;                                         \
    }                                                                        \
    lua55_learn_next(frame);                                                 \
}

LEARN_TESTSET_K(0)
LEARN_TESTSET_K(1)

/* ------------------------------------------------------------------ */
/* RESIDUALS: per (opcode, leaf, accept bit); guard tags, compute cond. */

#define RESIDUAL_K(name, k, guard, cond_expr)                                \
CMP_STENCIL(name)(Lua55LearnFrameV1 *frame)                                      \
{                                                                            \
    Lua55ValueV1 *left = &frame->values[LEFT_INDEX];                         \
    Lua55ValueV1 *right = &frame->values[RIGHT_INDEX];                       \
    if (!(guard)) { GUARD_FAILED(frame); return; }                           \
    if ((k) ? (cond_expr) : !(cond_expr)) { BRANCH_TAKEN(frame); return; }   \
    lua55_residual_next(frame);                                              \
}

#define TAG_PAIR_LT(lt, rt) ((left->tag == (lt)) && (right->tag == (rt)))

RESIDUAL_K(lua55_residual_lt_ii_k0, 0, TAG_PAIR_LT(LUA55_VALUE_INTEGER, LUA55_VALUE_INTEGER),
    left->payload.integer < right->payload.integer)
RESIDUAL_K(lua55_residual_lt_ii_k1, 1, TAG_PAIR_LT(LUA55_VALUE_INTEGER, LUA55_VALUE_INTEGER),
    left->payload.integer < right->payload.integer)
RESIDUAL_K(lua55_residual_lt_if_k0, 0, TAG_PAIR_LT(LUA55_VALUE_INTEGER, LUA55_VALUE_FLOAT),
    lt_int_float(left->payload.integer, right->payload.floating))
RESIDUAL_K(lua55_residual_lt_if_k1, 1, TAG_PAIR_LT(LUA55_VALUE_INTEGER, LUA55_VALUE_FLOAT),
    lt_int_float(left->payload.integer, right->payload.floating))
RESIDUAL_K(lua55_residual_lt_fi_k0, 0, TAG_PAIR_LT(LUA55_VALUE_FLOAT, LUA55_VALUE_INTEGER),
    lt_float_int(left->payload.floating, right->payload.integer))
RESIDUAL_K(lua55_residual_lt_fi_k1, 1, TAG_PAIR_LT(LUA55_VALUE_FLOAT, LUA55_VALUE_INTEGER),
    lt_float_int(left->payload.floating, right->payload.integer))
RESIDUAL_K(lua55_residual_lt_ff_k0, 0, TAG_PAIR_LT(LUA55_VALUE_FLOAT, LUA55_VALUE_FLOAT),
    left->payload.floating < right->payload.floating)
RESIDUAL_K(lua55_residual_lt_ff_k1, 1, TAG_PAIR_LT(LUA55_VALUE_FLOAT, LUA55_VALUE_FLOAT),
    left->payload.floating < right->payload.floating)

#define STRING_PAIR (is_string_tag(left->tag) && is_string_tag(right->tag))
#define LEFT_LONG (left->tag == LUA55_VALUE_LONG_STRING)
#define RIGHT_LONG (right->tag == LUA55_VALUE_LONG_STRING)

RESIDUAL_K(lua55_residual_lt_ss_k0, 0, STRING_PAIR && !LEFT_LONG && !RIGHT_LONG,
    string_cmp(left->payload.reference, right->payload.reference) < 0)
RESIDUAL_K(lua55_residual_lt_ss_k1, 1, STRING_PAIR && !LEFT_LONG && !RIGHT_LONG,
    string_cmp(left->payload.reference, right->payload.reference) < 0)
RESIDUAL_K(lua55_residual_lt_sl_k0, 0, STRING_PAIR && !LEFT_LONG && RIGHT_LONG,
    string_cmp(left->payload.reference, right->payload.reference) < 0)
RESIDUAL_K(lua55_residual_lt_sl_k1, 1, STRING_PAIR && !LEFT_LONG && RIGHT_LONG,
    string_cmp(left->payload.reference, right->payload.reference) < 0)
RESIDUAL_K(lua55_residual_lt_ls_k0, 0, STRING_PAIR && LEFT_LONG && !RIGHT_LONG,
    string_cmp(left->payload.reference, right->payload.reference) < 0)
RESIDUAL_K(lua55_residual_lt_ls_k1, 1, STRING_PAIR && LEFT_LONG && !RIGHT_LONG,
    string_cmp(left->payload.reference, right->payload.reference) < 0)
RESIDUAL_K(lua55_residual_lt_ll_k0, 0, STRING_PAIR && LEFT_LONG && RIGHT_LONG,
    string_cmp(left->payload.reference, right->payload.reference) < 0)
RESIDUAL_K(lua55_residual_lt_ll_k1, 1, STRING_PAIR && LEFT_LONG && RIGHT_LONG,
    string_cmp(left->payload.reference, right->payload.reference) < 0)

RESIDUAL_K(lua55_residual_le_ii_k0, 0, TAG_PAIR_LT(LUA55_VALUE_INTEGER, LUA55_VALUE_INTEGER),
    left->payload.integer <= right->payload.integer)
RESIDUAL_K(lua55_residual_le_ii_k1, 1, TAG_PAIR_LT(LUA55_VALUE_INTEGER, LUA55_VALUE_INTEGER),
    left->payload.integer <= right->payload.integer)
RESIDUAL_K(lua55_residual_le_if_k0, 0, TAG_PAIR_LT(LUA55_VALUE_INTEGER, LUA55_VALUE_FLOAT),
    le_int_float(left->payload.integer, right->payload.floating))
RESIDUAL_K(lua55_residual_le_if_k1, 1, TAG_PAIR_LT(LUA55_VALUE_INTEGER, LUA55_VALUE_FLOAT),
    le_int_float(left->payload.integer, right->payload.floating))
RESIDUAL_K(lua55_residual_le_fi_k0, 0, TAG_PAIR_LT(LUA55_VALUE_FLOAT, LUA55_VALUE_INTEGER),
    le_float_int(left->payload.floating, right->payload.integer))
RESIDUAL_K(lua55_residual_le_fi_k1, 1, TAG_PAIR_LT(LUA55_VALUE_FLOAT, LUA55_VALUE_INTEGER),
    le_float_int(left->payload.floating, right->payload.integer))
RESIDUAL_K(lua55_residual_le_ff_k0, 0, TAG_PAIR_LT(LUA55_VALUE_FLOAT, LUA55_VALUE_FLOAT),
    left->payload.floating <= right->payload.floating)
RESIDUAL_K(lua55_residual_le_ff_k1, 1, TAG_PAIR_LT(LUA55_VALUE_FLOAT, LUA55_VALUE_FLOAT),
    left->payload.floating <= right->payload.floating)

RESIDUAL_K(lua55_residual_le_ss_k0, 0, STRING_PAIR && !LEFT_LONG && !RIGHT_LONG,
    string_cmp(left->payload.reference, right->payload.reference) <= 0)
RESIDUAL_K(lua55_residual_le_ss_k1, 1, STRING_PAIR && !LEFT_LONG && !RIGHT_LONG,
    string_cmp(left->payload.reference, right->payload.reference) <= 0)
RESIDUAL_K(lua55_residual_le_sl_k0, 0, STRING_PAIR && !LEFT_LONG && RIGHT_LONG,
    string_cmp(left->payload.reference, right->payload.reference) <= 0)
RESIDUAL_K(lua55_residual_le_sl_k1, 1, STRING_PAIR && !LEFT_LONG && RIGHT_LONG,
    string_cmp(left->payload.reference, right->payload.reference) <= 0)
RESIDUAL_K(lua55_residual_le_ls_k0, 0, STRING_PAIR && LEFT_LONG && !RIGHT_LONG,
    string_cmp(left->payload.reference, right->payload.reference) <= 0)
RESIDUAL_K(lua55_residual_le_ls_k1, 1, STRING_PAIR && LEFT_LONG && !RIGHT_LONG,
    string_cmp(left->payload.reference, right->payload.reference) <= 0)
RESIDUAL_K(lua55_residual_le_ll_k0, 0, STRING_PAIR && LEFT_LONG && RIGHT_LONG,
    string_cmp(left->payload.reference, right->payload.reference) <= 0)
RESIDUAL_K(lua55_residual_le_ll_k1, 1, STRING_PAIR && LEFT_LONG && RIGHT_LONG,
    string_cmp(left->payload.reference, right->payload.reference) <= 0)

RESIDUAL_K(lua55_residual_eq_ii_k0, 0, TAG_PAIR_LT(LUA55_VALUE_INTEGER, LUA55_VALUE_INTEGER),
    left->payload.integer == right->payload.integer)
RESIDUAL_K(lua55_residual_eq_ii_k1, 1, TAG_PAIR_LT(LUA55_VALUE_INTEGER, LUA55_VALUE_INTEGER),
    left->payload.integer == right->payload.integer)
RESIDUAL_K(lua55_residual_eq_if_k0, 0, TAG_PAIR_LT(LUA55_VALUE_INTEGER, LUA55_VALUE_FLOAT),
    eq_int_float(left->payload.integer, right->payload.floating))
RESIDUAL_K(lua55_residual_eq_if_k1, 1, TAG_PAIR_LT(LUA55_VALUE_INTEGER, LUA55_VALUE_FLOAT),
    eq_int_float(left->payload.integer, right->payload.floating))
RESIDUAL_K(lua55_residual_eq_fi_k0, 0, TAG_PAIR_LT(LUA55_VALUE_FLOAT, LUA55_VALUE_INTEGER),
    eq_int_float(right->payload.integer, left->payload.floating))
RESIDUAL_K(lua55_residual_eq_fi_k1, 1, TAG_PAIR_LT(LUA55_VALUE_FLOAT, LUA55_VALUE_INTEGER),
    eq_int_float(right->payload.integer, left->payload.floating))
RESIDUAL_K(lua55_residual_eq_ff_k0, 0, TAG_PAIR_LT(LUA55_VALUE_FLOAT, LUA55_VALUE_FLOAT),
    left->payload.floating == right->payload.floating)
RESIDUAL_K(lua55_residual_eq_ff_k1, 1, TAG_PAIR_LT(LUA55_VALUE_FLOAT, LUA55_VALUE_FLOAT),
    left->payload.floating == right->payload.floating)

RESIDUAL_K(lua55_residual_eq_ss_k0, 0, STRING_PAIR && !LEFT_LONG && !RIGHT_LONG,
    string_bytes_eq(left->payload.reference, right->payload.reference))
RESIDUAL_K(lua55_residual_eq_ss_k1, 1, STRING_PAIR && !LEFT_LONG && !RIGHT_LONG,
    string_bytes_eq(left->payload.reference, right->payload.reference))
RESIDUAL_K(lua55_residual_eq_sl_k0, 0, STRING_PAIR && !LEFT_LONG && RIGHT_LONG,
    string_bytes_eq(left->payload.reference, right->payload.reference))
RESIDUAL_K(lua55_residual_eq_sl_k1, 1, STRING_PAIR && !LEFT_LONG && RIGHT_LONG,
    string_bytes_eq(left->payload.reference, right->payload.reference))
RESIDUAL_K(lua55_residual_eq_ls_k0, 0, STRING_PAIR && LEFT_LONG && !RIGHT_LONG,
    string_bytes_eq(left->payload.reference, right->payload.reference))
RESIDUAL_K(lua55_residual_eq_ls_k1, 1, STRING_PAIR && LEFT_LONG && !RIGHT_LONG,
    string_bytes_eq(left->payload.reference, right->payload.reference))
RESIDUAL_K(lua55_residual_eq_ll_k0, 0, STRING_PAIR && LEFT_LONG && RIGHT_LONG,
    string_bytes_eq(left->payload.reference, right->payload.reference))
RESIDUAL_K(lua55_residual_eq_ll_k1, 1, STRING_PAIR && LEFT_LONG && RIGHT_LONG,
    string_bytes_eq(left->payload.reference, right->payload.reference))

RESIDUAL_K(lua55_residual_eq_nn_k0, 0, TAG_PAIR_LT(LUA55_VALUE_NIL, LUA55_VALUE_NIL), 1)
RESIDUAL_K(lua55_residual_eq_nn_k1, 1, TAG_PAIR_LT(LUA55_VALUE_NIL, LUA55_VALUE_NIL), 1)
RESIDUAL_K(lua55_residual_eq_bb_k0, 0, TAG_PAIR_LT(LUA55_VALUE_FALSE, LUA55_VALUE_FALSE), 1)
RESIDUAL_K(lua55_residual_eq_bb_k1, 1, TAG_PAIR_LT(LUA55_VALUE_FALSE, LUA55_VALUE_FALSE), 1)
RESIDUAL_K(lua55_residual_eq_tt_k0, 0, TAG_PAIR_LT(LUA55_VALUE_TRUE, LUA55_VALUE_TRUE), 1)
RESIDUAL_K(lua55_residual_eq_tt_k1, 1, TAG_PAIR_LT(LUA55_VALUE_TRUE, LUA55_VALUE_TRUE), 1)
RESIDUAL_K(lua55_residual_eq_neq_k0, 0, left->tag <= LUA55_VALUE_LONG_STRING && right->tag <= LUA55_VALUE_LONG_STRING && left->tag != right->tag, 0)
RESIDUAL_K(lua55_residual_eq_neq_k1, 1, left->tag <= LUA55_VALUE_LONG_STRING && right->tag <= LUA55_VALUE_LONG_STRING && left->tag != right->tag, 0)

/* EQI/LTI/LEI/GTI/GEI: register vs patched integer immediate. */
#define RESIDUAL_REG_IMM(name, k, expected_tag, cond_expr)                             \
CMP_STENCIL(name)(Lua55LearnFrameV1 *frame)                                       \
{                                                                             \
    Lua55ValueV1 *left = &frame->values[LEFT_INDEX];                          \
    if (left->tag != (expected_tag)) { GUARD_FAILED(frame); return; }                  \
    int64_t im = (int64_t)INT_IMM_HOLE;                                       \
    __asm__ volatile ("" : "+r"(im));                                         \
    if ((k) ? (cond_expr) : !(cond_expr)) { BRANCH_TAKEN(frame); return; }    \
    lua55_residual_next(frame);                                               \
}

RESIDUAL_REG_IMM(lua55_residual_eqi_int_k0, 0, LUA55_VALUE_INTEGER, left->payload.integer == im)
RESIDUAL_REG_IMM(lua55_residual_eqi_int_k1, 1, LUA55_VALUE_INTEGER, left->payload.integer == im)
RESIDUAL_REG_IMM(lua55_residual_eqi_flt_k0, 0, LUA55_VALUE_FLOAT, left->payload.floating == (double)im)
RESIDUAL_REG_IMM(lua55_residual_eqi_flt_k1, 1, LUA55_VALUE_FLOAT, left->payload.floating == (double)im)
RESIDUAL_REG_IMM(lua55_residual_lti_int_k0, 0, LUA55_VALUE_INTEGER, left->payload.integer < im)
RESIDUAL_REG_IMM(lua55_residual_lti_int_k1, 1, LUA55_VALUE_INTEGER, left->payload.integer < im)
RESIDUAL_REG_IMM(lua55_residual_lti_flt_k0, 0, LUA55_VALUE_FLOAT, left->payload.floating < (double)im)
RESIDUAL_REG_IMM(lua55_residual_lti_flt_k1, 1, LUA55_VALUE_FLOAT, left->payload.floating < (double)im)
RESIDUAL_REG_IMM(lua55_residual_lei_int_k0, 0, LUA55_VALUE_INTEGER, left->payload.integer <= im)
RESIDUAL_REG_IMM(lua55_residual_lei_int_k1, 1, LUA55_VALUE_INTEGER, left->payload.integer <= im)
RESIDUAL_REG_IMM(lua55_residual_lei_flt_k0, 0, LUA55_VALUE_FLOAT, left->payload.floating <= (double)im)
RESIDUAL_REG_IMM(lua55_residual_lei_flt_k1, 1, LUA55_VALUE_FLOAT, left->payload.floating <= (double)im)
RESIDUAL_REG_IMM(lua55_residual_gti_int_k0, 0, LUA55_VALUE_INTEGER, left->payload.integer > im)
RESIDUAL_REG_IMM(lua55_residual_gti_int_k1, 1, LUA55_VALUE_INTEGER, left->payload.integer > im)
RESIDUAL_REG_IMM(lua55_residual_gti_flt_k0, 0, LUA55_VALUE_FLOAT, left->payload.floating > (double)im)
RESIDUAL_REG_IMM(lua55_residual_gti_flt_k1, 1, LUA55_VALUE_FLOAT, left->payload.floating > (double)im)
RESIDUAL_REG_IMM(lua55_residual_gei_int_k0, 0, LUA55_VALUE_INTEGER, left->payload.integer >= im)
RESIDUAL_REG_IMM(lua55_residual_gei_int_k1, 1, LUA55_VALUE_INTEGER, left->payload.integer >= im)
RESIDUAL_REG_IMM(lua55_residual_gei_flt_k0, 0, LUA55_VALUE_FLOAT, left->payload.floating >= (double)im)
RESIDUAL_REG_IMM(lua55_residual_gei_flt_k1, 1, LUA55_VALUE_FLOAT, left->payload.floating >= (double)im)

/* EQK: register vs patched constant (tag + payload). */
#define RESIDUAL_EQK(name, k, guard, cond_expr)                               \
CMP_STENCIL(name)(Lua55LearnFrameV1 *frame)                                       \
{                                                                             \
    Lua55ValueV1 *left = &frame->values[LEFT_INDEX];                          \
    if (!(guard)) { GUARD_FAILED(frame); return; }                            \
    int64_t cint = (int64_t)CONST_INT_HOLE;                                   \
    __asm__ volatile ("" : "+r"(cint));                                     \
    uint64_t cflt_bits = CONST_FLT_HOLE;                                      \
    __asm__ volatile ("" : "+r"(cflt_bits));                                \
    double cflt;                                                              \
    __builtin_memcpy(&cflt, &cflt_bits, sizeof(cflt));                        \
    uintptr_t cref = (uintptr_t)CONST_REF_HOLE;                               \
    __asm__ volatile ("" : "+r"(cref));                                     \
    if ((k) ? (cond_expr) : !(cond_expr)) { BRANCH_TAKEN(frame); return; }    \
    lua55_residual_next(frame);                                               \
}

RESIDUAL_EQK(lua55_residual_eqk_ii_k0, 0, left->tag == LUA55_VALUE_INTEGER,
    left->payload.integer == cint)
RESIDUAL_EQK(lua55_residual_eqk_ii_k1, 1, left->tag == LUA55_VALUE_INTEGER,
    left->payload.integer == cint)
RESIDUAL_EQK(lua55_residual_eqk_ff_k0, 0, left->tag == LUA55_VALUE_FLOAT,
    left->payload.floating == cflt)
RESIDUAL_EQK(lua55_residual_eqk_ff_k1, 1, left->tag == LUA55_VALUE_FLOAT,
    left->payload.floating == cflt)
RESIDUAL_EQK(lua55_residual_eqk_if_k0, 0, left->tag == LUA55_VALUE_INTEGER,
    eq_int_float(left->payload.integer, cflt))
RESIDUAL_EQK(lua55_residual_eqk_if_k1, 1, left->tag == LUA55_VALUE_INTEGER,
    eq_int_float(left->payload.integer, cflt))
RESIDUAL_EQK(lua55_residual_eqk_fi_k0, 0, left->tag == LUA55_VALUE_FLOAT,
    eq_int_float(cint, left->payload.floating))
RESIDUAL_EQK(lua55_residual_eqk_fi_k1, 1, left->tag == LUA55_VALUE_FLOAT,
    eq_int_float(cint, left->payload.floating))
RESIDUAL_EQK(lua55_residual_eqk_ss_k0, 0, is_string_tag(left->tag),
    string_bytes_eq(left->payload.reference, cref))
RESIDUAL_EQK(lua55_residual_eqk_ss_k1, 1, is_string_tag(left->tag),
    string_bytes_eq(left->payload.reference, cref))
RESIDUAL_EQK(lua55_residual_eqk_ls_k0, 0, is_string_tag(left->tag),
    string_bytes_eq(left->payload.reference, cref))
RESIDUAL_EQK(lua55_residual_eqk_ls_k1, 1, is_string_tag(left->tag),
    string_bytes_eq(left->payload.reference, cref))
RESIDUAL_EQK(lua55_residual_eqk_sl_k0, 0, is_string_tag(left->tag),
    string_bytes_eq(left->payload.reference, cref))
RESIDUAL_EQK(lua55_residual_eqk_sl_k1, 1, is_string_tag(left->tag),
    string_bytes_eq(left->payload.reference, cref))
RESIDUAL_EQK(lua55_residual_eqk_ll_k0, 0, is_string_tag(left->tag),
    string_bytes_eq(left->payload.reference, cref))
RESIDUAL_EQK(lua55_residual_eqk_ll_k1, 1, is_string_tag(left->tag),
    string_bytes_eq(left->payload.reference, cref))
RESIDUAL_EQK(lua55_residual_eqk_nn_k0, 0, left->tag == LUA55_VALUE_NIL, 1)
RESIDUAL_EQK(lua55_residual_eqk_nn_k1, 1, left->tag == LUA55_VALUE_NIL, 1)
RESIDUAL_EQK(lua55_residual_eqk_bb_k0, 0, left->tag == LUA55_VALUE_FALSE, 1)
RESIDUAL_EQK(lua55_residual_eqk_bb_k1, 1, left->tag == LUA55_VALUE_FALSE, 1)
RESIDUAL_EQK(lua55_residual_eqk_tt_k0, 0, left->tag == LUA55_VALUE_TRUE, 1)
RESIDUAL_EQK(lua55_residual_eqk_tt_k1, 1, left->tag == LUA55_VALUE_TRUE, 1)

/* TEST / TESTSET: total functions; no tag guard. */
#define RESIDUAL_TEST(name, k)                                                 \
CMP_STENCIL(name)(Lua55LearnFrameV1 *frame)                                       \
{                                                                             \
    Lua55ValueV1 *left = &frame->values[LEFT_INDEX];                          \
    int cond = truthy(left->tag);                                             \
    if ((k) ? cond : !cond) { BRANCH_TAKEN(frame); return; }                  \
    lua55_residual_next(frame);                                               \
}

#define RESIDUAL_TESTSET(name, k)                                             \
CMP_STENCIL(name)(Lua55LearnFrameV1 *frame)                                       \
{                                                                             \
    Lua55ValueV1 *left = &frame->values[LEFT_INDEX];                          \
    Lua55ValueV1 *right = &frame->values[RIGHT_INDEX];                        \
    int cond = truthy(right->tag);                                            \
    if ((k) ? cond : !cond) {                                                 \
        *left = *right;                                                       \
        BRANCH_TAKEN(frame); return;                                          \
    }                                                                         \
    lua55_residual_next(frame);                                               \
}

RESIDUAL_TEST(lua55_residual_test_k0, 0)
RESIDUAL_TEST(lua55_residual_test_k1, 1)
RESIDUAL_TESTSET(lua55_residual_teskset_k0, 0)
RESIDUAL_TESTSET(lua55_residual_teskset_k1, 1)

/* ---- Self-selecting (polymorphic) compare residuals ----------------------
   One residual per opcode; the tag dispatch IS the selection. The k (accept)
   bit is patched per occurrence; register indices are runtime holes. */

#define K_HOLE UINT32_C(0x71727374)
#define CMP_TARGET_HOLE UINT32_C(0x111)
#define CMP_RIGHT_HOLE UINT32_C(0x222)
#define CMP_IMM_HOLE UINT64_C(0x1112131415161718)
#define CMP_CTAG_HOLE UINT32_C(0x3c3b3a39)
#define CMP_CINT_HOLE UINT64_C(0x2122232425262728)
#define CMP_CFLT_HOLE UINT64_C(0x123456789abcdef0)
#define CMP_CREF_HOLE UINT64_C(0x0abcdef012345679)

#define POLY_CMP_PROLOGUE()                                                \
    uint32_t left_index = CMP_TARGET_HOLE;                                 \
    __asm__ volatile ("" : "+r"(left_index));                              \
    uint32_t right_index = CMP_RIGHT_HOLE;                                 \
    __asm__ volatile ("" : "+r"(right_index));                             \
    Lua55ValueV1 *left = &frame->values[left_index];                       \
    Lua55ValueV1 *right = &frame->values[right_index];

#define POLY_TAKEN_HOLE UINT64_C(0x0badf00dcafed00d)
#define POLY_BRANCH_TAKEN(frame) do {                                       \
    uintptr_t target = (uintptr_t)POLY_TAKEN_HOLE;                          \
    __asm__ volatile ("" : "+r"(target));                                  \
    ((Lua55OpcodeEntryV1)target)(frame);                                    \
    return;                                                                 \
} while (0)
#define POLY_EQ(name, right_init)                                          \
CMP_STENCIL(name)(Lua55LearnFrameV1 *frame)                                \
{                                                                          \
    POLY_CMP_PROLOGUE()                                                    \
    right_init;                                                            \
    uint32_t k = K_HOLE;                                                   \
    __asm__ volatile ("" : "+r"(k));                                       \
    int cond;                                                              \
    if (left->tag == LUA55_VALUE_INTEGER && right->tag == LUA55_VALUE_INTEGER) \
        cond = left->payload.integer == right->payload.integer;            \
    else if (left->tag == LUA55_VALUE_INTEGER && right->tag == LUA55_VALUE_FLOAT) \
        cond = eq_int_float(left->payload.integer, right->payload.floating); \
    else if (left->tag == LUA55_VALUE_FLOAT && right->tag == LUA55_VALUE_INTEGER) \
        cond = eq_int_float(right->payload.integer, left->payload.floating); \
    else if (left->tag == LUA55_VALUE_FLOAT && right->tag == LUA55_VALUE_FLOAT) \
        cond = left->payload.floating == right->payload.floating;          \
    else if (is_string_tag(left->tag) && is_string_tag(right->tag))        \
        cond = string_bytes_eq(left->payload.reference, right->payload.reference); \
    else if (left->tag == right->tag)                                      \
        cond = (left->tag == LUA55_VALUE_TABLE || left->tag == LUA55_VALUE_CLOSURE) \
            ? left->payload.reference == right->payload.reference : 1;     \
    else cond = 0;                                                         \
    if (k ? cond : !cond) { POLY_BRANCH_TAKEN(frame); }                    \
    lua55_residual_next(frame);                                            \
}

#define POLY_ORD(name, right_init)                                         \
CMP_STENCIL(name)(Lua55LearnFrameV1 *frame)                                \
{                                                                          \
    POLY_CMP_PROLOGUE()                                                    \
    right_init;                                                            \
    uint32_t k = K_HOLE;                                                   \
    __asm__ volatile ("" : "+r"(k));                                       \
    int cond;                                                              \
    if (left->tag == LUA55_VALUE_INTEGER && right->tag == LUA55_VALUE_INTEGER) \
        cond = left->payload.integer < right->payload.integer;             \
    else if (left->tag == LUA55_VALUE_INTEGER && right->tag == LUA55_VALUE_FLOAT) \
        cond = (double)left->payload.integer < right->payload.floating;    \
    else if (left->tag == LUA55_VALUE_FLOAT && right->tag == LUA55_VALUE_INTEGER) \
        cond = left->payload.floating < (double)right->payload.integer;    \
    else if (left->tag == LUA55_VALUE_FLOAT && right->tag == LUA55_VALUE_FLOAT) \
        cond = left->payload.floating < right->payload.floating;           \
    else if (is_string_tag(left->tag) && is_string_tag(right->tag))        \
        cond = string_cmp(left->payload.reference, right->payload.reference) < 0; \
    else { REJECT(frame); LUA55_CPS_HOST_EXIT(frame); }                                        \
    if (k ? cond : !cond) { POLY_BRANCH_TAKEN(frame); }                    \
    lua55_residual_next(frame);                                            \
}

#define POLY_LE(name, right_init)                                          \
CMP_STENCIL(name)(Lua55LearnFrameV1 *frame)                                \
{                                                                          \
    POLY_CMP_PROLOGUE()                                                    \
    right_init;                                                            \
    uint32_t k = K_HOLE;                                                   \
    __asm__ volatile ("" : "+r"(k));                                       \
    int cond;                                                              \
    if (left->tag == LUA55_VALUE_INTEGER && right->tag == LUA55_VALUE_INTEGER) \
        cond = left->payload.integer <= right->payload.integer;            \
    else if (left->tag == LUA55_VALUE_INTEGER && right->tag == LUA55_VALUE_FLOAT) \
        cond = (double)left->payload.integer <= right->payload.floating;   \
    else if (left->tag == LUA55_VALUE_FLOAT && right->tag == LUA55_VALUE_INTEGER) \
        cond = left->payload.floating <= (double)right->payload.integer;   \
    else if (left->tag == LUA55_VALUE_FLOAT && right->tag == LUA55_VALUE_FLOAT) \
        cond = left->payload.floating <= right->payload.floating;          \
    else if (is_string_tag(left->tag) && is_string_tag(right->tag))        \
        cond = string_cmp(left->payload.reference, right->payload.reference) <= 0; \
    else { REJECT(frame); LUA55_CPS_HOST_EXIT(frame); }                                        \
    if (k ? cond : !cond) { POLY_BRANCH_TAKEN(frame); }                    \
    lua55_residual_next(frame);                                            \
}

#define CMP_IMM_RIGHT                                                      \
    Lua55ValueV1 imm_cell;                                                 \
    uint64_t imm_bits = CMP_IMM_HOLE;                                      \
    __asm__ volatile ("" : "+r"(imm_bits));                               \
    SET_TAG(&imm_cell, LUA55_VALUE_INTEGER);                               \
    imm_cell.payload.integer = (int64_t)imm_bits;                          \
    right = &imm_cell;

#define CMP_CONST_RIGHT                                                    \
    Lua55ValueV1 const_cell;                                               \
    /* runtime-guarded holes (see arith CONST_RIGHT): without the asm      \
       guards GCC folds the tag test and erases the patchable patterns */  \
    uint32_t const_tag = CMP_CTAG_HOLE;                                    \
    __asm__ volatile ("" : "+r"(const_tag));                             \
    uint64_t const_int_bits = CMP_CINT_HOLE;                               \
    __asm__ volatile ("" : "+r"(const_int_bits));                        \
    uint64_t const_flt_bits = CMP_CFLT_HOLE;                               \
    __asm__ volatile ("" : "+r"(const_flt_bits));                        \
    uint64_t const_ref_bits = CMP_CREF_HOLE;                               \
    __asm__ volatile ("" : "+r"(const_ref_bits));                        \
    const_cell.tag = const_tag;                                            \
    /* union payload: fill the interpretation matching the tag */          \
    if (const_tag == LUA55_VALUE_INTEGER)                                  \
        const_cell.payload.integer = (int64_t)const_int_bits;              \
    else if (const_tag == LUA55_VALUE_FLOAT)                               \
        __builtin_memcpy(&const_cell.payload.floating, &const_flt_bits, 8); \
    else                                                                   \
        const_cell.payload.reference = (uintptr_t)const_ref_bits;          \
    right = &const_cell;                                                    \

POLY_EQ(lua55_poly_eq, (void)0)
POLY_EQ(lua55_poly_eqk, CMP_CONST_RIGHT)
POLY_EQ(lua55_poly_eqi, CMP_IMM_RIGHT)
POLY_ORD(lua55_poly_lt, (void)0)
POLY_ORD(lua55_poly_lti, CMP_IMM_RIGHT)
POLY_LE(lua55_poly_le, (void)0)
POLY_LE(lua55_poly_lei, CMP_IMM_RIGHT)
POLY_ORD(lua55_poly_gti, CMP_IMM_RIGHT)
POLY_LE(lua55_poly_gei, CMP_IMM_RIGHT)

#define POLY_TEST(name, set)                                               \
CMP_STENCIL(name)(Lua55LearnFrameV1 *frame)                                \
{                                                                          \
    uint32_t left_index = CMP_TARGET_HOLE;                                 \
    __asm__ volatile ("" : "+r"(left_index));                              \
    uint32_t target_index = CMP_TARGET_HOLE;                               \
    __asm__ volatile ("" : "+r"(target_index));                            \
    Lua55ValueV1 *left = &frame->values[left_index];                       \
    uint32_t k = K_HOLE;                                                   \
    __asm__ volatile ("" : "+r"(k));                                       \
    int cond = truthy(left->tag);                                          \
    if (set) {                                                             \
        Lua55ValueV1 *target = &frame->values[target_index];               \
        *target = *left;                                                   \
    }                                                                      \
    if (k ? cond : !cond) { POLY_BRANCH_TAKEN(frame); }                    \
    lua55_residual_next(frame);                                            \
}

POLY_TEST(lua55_poly_test, 0)
POLY_TEST(lua55_poly_testset, 1)
