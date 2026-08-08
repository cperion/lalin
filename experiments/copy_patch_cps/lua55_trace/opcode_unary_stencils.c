#include "opcode_value_v1.h"
#include "opcode_value_v1.h"
#include "opcode_value_v2.h"
/* Batch 3: unary family (49-52, UNM BNOT NOT LEN). Standalone: the Lua
   5.5 compiler emits no MMBIN companion for unary ops, so the primitive
   falls through at pc+1. UNM/BNOT reject non-numeric (host runs the
   metamethod); NOT is total (truthiness); LEN handles strings and
   metatable-free tables, rejecting everything else (host raises). */

#define UNARY_TARGET_INDEX UINT32_C(0x111)
#define UNARY_SOURCE_INDEX UINT32_C(0x222)

#define QUOTE_BASE_HOLE UINT32_C(0x0f1e2d3c)
#define RESUME_HOLE UINT32_C(0x66778899)

#define GUARD_FAILED(frame) do {            \
    (frame)->resume_pc = RESUME_HOLE;        \
    (frame)->status = LUA55_GUARD_FAILED;    \
} while (0)

#define REJECT(frame) do {                  \
    (frame)->resume_pc = RESUME_HOLE;        \
    (frame)->status = LUA55_REJECTED;        \
} while (0)

/* --- shared exact helpers (identical to prior batches) --- */

static inline int magnitude_at_least_2_63(double x)
{
    uint64_t bits;
    __builtin_memcpy(&bits, &x, sizeof(bits));
    return ((bits & UINT64_C(0x7ff0000000000000)) >> 52) >= UINT64_C(0x43e);
}

/* F2Ieq: integral float in int64 range (stock luaV_tointegerns floor2i) */
static inline int flt_to_int_eq(double f, int64_t *out)
{
    if (f != f) return 0;
    if (magnitude_at_least_2_63(f)) return 0;
    int64_t i = (int64_t)f;
    if ((double)i != f) return 0;
    *out = i;
    return 1;
}

/* Wrap negation: intop(-, 0, x) = (int64_t)((uint64_t)0 - (uint64_t)x). */
static inline int64_t int_unm(int64_t x)
{
    return (int64_t)((uint64_t)0 - (uint64_t)x);
}

/* Exact float negation without a rodata sign mask (keeps the stencil
   free of PC32 relocations): flip the sign bit inline. */
static inline double flt_unm(double x)
{
    uint64_t bits;
    double value;
    __builtin_memcpy(&bits, &x, sizeof(bits));
    bits ^= UINT64_C(0x8000000000000000);
    __builtin_memcpy(&value, &bits, sizeof(value));
    return value;
}

/* --- LEN: exact leading-run length of the guest table array part.
   Stock luaH_getn resolves (via the alimit invariant) to the number of
   leading non-nil entries: the first boundary position minus one. We do
   a linear scan; the closed-subset arrays are small and this is exact
   for every hole pattern. */
static inline int64_t table_len(Lua55GuestTableV1 *table)
{
    uint32_t index;
    uint32_t capacity = table->array_capacity;
    Lua55ValueV1 *array = table->array_values;
    if (capacity == 0 || array == 0) return 0;
    for (index = 0; index < capacity; index++) {
        if (array[index].tag == LUA55_VALUE_NIL) break;
    }
    return (int64_t)index;
}

/* Validate a table for the primitive LEN path: identity, heap
   ownership, and metatable absence (no __len metamethod). */
static inline Lua55GuestTableV1 *learn_len_table(
    Lua55LearnFrameV1 *frame, Lua55ValueV1 *source)
{
    Lua55GuestTableV1 *table;
    if (source->tag != LUA55_VALUE_TABLE || frame->heap == 0) return 0;
    table = (Lua55GuestTableV1 *)source->payload.reference;
    if (table == 0 || table->header.kind != LUA55_OBJECT_TABLE ||
        table->heap != frame->heap || table->metatable_reference != 0) return 0;
    return table;
}

/* ------------------------------------------------------------------ */
/* LEARNERS                                                             */

#define LEARN_UNARY(name, variant_expr)                            \
STENCIL(name)(Lua55LearnFrameV1 *frame)                             \
{                                                                   \
    Lua55ValueV1 *target = &frame->values[UNARY_TARGET_INDEX];      \
    Lua55ValueV1 *source = &frame->values[UNARY_SOURCE_INDEX];      \
    Lua55RecordingSlotV1 *slot = next_slot(frame);                  \
    uint32_t base = QUOTE_BASE_HOLE;                                \
    __asm__ volatile ("" : "+r"(base));                             \
    uint32_t variant = variant_expr;                                \
    if (variant == 0) { slot->quote = LUA55_QUOTE_REJECTED; REJECT(frame); return; } \
    SET_TAG(target, LUA55_VALUE_INTEGER);                           \
    target->payload.integer = 0;                                    \
    slot->quote = base | variant;                                   \
    lua55_learn_next(frame);                                        \
}

STENCIL(lua55_learn_unm)(Lua55LearnFrameV1 *frame)
{
    Lua55ValueV1 *target = &frame->values[UNARY_TARGET_INDEX];
    Lua55ValueV1 *source = &frame->values[UNARY_SOURCE_INDEX];
    Lua55RecordingSlotV1 *slot = next_slot(frame);
    uint32_t base = QUOTE_BASE_HOLE;
    __asm__ volatile ("" : "+r"(base));
    if (source->tag == LUA55_VALUE_INTEGER) {
        SET_TAG(target, LUA55_VALUE_INTEGER);
        target->payload.integer = int_unm(source->payload.integer);
        slot->quote = base | 1;
    } else if (source->tag == LUA55_VALUE_FLOAT) {
        SET_TAG(target, LUA55_VALUE_FLOAT);
        target->payload.floating = flt_unm(source->payload.floating);
        slot->quote = base | 2;
    } else {
        slot->quote = LUA55_QUOTE_REJECTED; REJECT(frame); return;
    }
    lua55_learn_next(frame);
}

STENCIL(lua55_learn_bnot)(Lua55LearnFrameV1 *frame)
{
    Lua55ValueV1 *target = &frame->values[UNARY_TARGET_INDEX];
    Lua55ValueV1 *source = &frame->values[UNARY_SOURCE_INDEX];
    Lua55RecordingSlotV1 *slot = next_slot(frame);
    uint32_t base = QUOTE_BASE_HOLE;
    __asm__ volatile ("" : "+r"(base));
    int64_t value;
    if (source->tag == LUA55_VALUE_INTEGER) {
        value = source->payload.integer;
        SET_TAG(target, LUA55_VALUE_INTEGER);
        target->payload.integer = ~value;
        slot->quote = base | 1;
    } else if (source->tag == LUA55_VALUE_FLOAT &&
               flt_to_int_eq(source->payload.floating, &value)) {
        SET_TAG(target, LUA55_VALUE_INTEGER);
        target->payload.integer = ~value;
        slot->quote = base | 2;
    } else {
        slot->quote = LUA55_QUOTE_REJECTED; REJECT(frame); return;
    }
    lua55_learn_next(frame);
}

STENCIL(lua55_learn_not)(Lua55LearnFrameV1 *frame)
{
    Lua55ValueV1 *target = &frame->values[UNARY_TARGET_INDEX];
    Lua55ValueV1 *source = &frame->values[UNARY_SOURCE_INDEX];
    Lua55RecordingSlotV1 *slot = next_slot(frame);
    uint32_t base = QUOTE_BASE_HOLE;
    __asm__ volatile ("" : "+r"(base));
    if (source->tag == LUA55_VALUE_NIL || source->tag == LUA55_VALUE_FALSE) {
        SET_TAG(target, LUA55_VALUE_TRUE);
        slot->quote = base | 1;
    } else {
        SET_TAG(target, LUA55_VALUE_FALSE);
        slot->quote = base | 2;
    }
    lua55_learn_next(frame);
}

STENCIL(lua55_learn_len)(Lua55LearnFrameV1 *frame)
{
    Lua55ValueV1 *target = &frame->values[UNARY_TARGET_INDEX];
    Lua55ValueV1 *source = &frame->values[UNARY_SOURCE_INDEX];
    Lua55RecordingSlotV1 *slot = next_slot(frame);
    uint32_t base = QUOTE_BASE_HOLE;
    __asm__ volatile ("" : "+r"(base));
    if (source->tag == LUA55_VALUE_SHORT_STRING ||
        source->tag == LUA55_VALUE_LONG_STRING) {
        Lua55GuestStringV1 *str =
            (Lua55GuestStringV1 *)source->payload.reference;
        SET_TAG(target, LUA55_VALUE_INTEGER);
        target->payload.integer = (str != 0) ? (int64_t)str->length : 0;
        slot->quote = base | (source->tag == LUA55_VALUE_SHORT_STRING ? 1 : 2);
    } else if (learn_len_table(frame, source) != 0) {
        Lua55GuestTableV1 *table =
            (Lua55GuestTableV1 *)source->payload.reference;
        SET_TAG(target, LUA55_VALUE_INTEGER);
        target->payload.integer = table_len(table);
        slot->quote = base | 3;
    } else {
        slot->quote = LUA55_QUOTE_REJECTED; REJECT(frame); return;
    }
    lua55_learn_next(frame);
}

/* ------------------------------------------------------------------ */
/* RESIDUALS                                                            */

#define RESIDUAL_UNM(name, expected_tag)                                \
STENCIL(name)(Lua55LearnFrameV1 *frame)                                 \
{                                                                       \
    Lua55ValueV1 *target = &frame->values[UNARY_TARGET_INDEX];          \
    Lua55ValueV1 *source = &frame->values[UNARY_SOURCE_INDEX];          \
    if (source->tag != (expected_tag)) { GUARD_FAILED(frame); return; } \
    if ((expected_tag) == LUA55_VALUE_INTEGER) {                        \
        SET_TAG(target, LUA55_VALUE_INTEGER);                           \
        target->payload.integer = int_unm(source->payload.integer);     \
    } else {                                                            \
        SET_TAG(target, LUA55_VALUE_FLOAT);                             \
        target->payload.floating = flt_unm(source->payload.floating);           \
    }                                                                   \
    lua55_residual_next(frame);                                         \
}

RESIDUAL_UNM(lua55_residual_unm_int, LUA55_VALUE_INTEGER)
RESIDUAL_UNM(lua55_residual_unm_flt, LUA55_VALUE_FLOAT)

#define RESIDUAL_BNOT(name, expected_tag)                               \
STENCIL(name)(Lua55LearnFrameV1 *frame)                                 \
{                                                                       \
    Lua55ValueV1 *target = &frame->values[UNARY_TARGET_INDEX];          \
    Lua55ValueV1 *source = &frame->values[UNARY_SOURCE_INDEX];          \
    if (source->tag != (expected_tag)) { GUARD_FAILED(frame); return; } \
    int64_t value = (expected_tag) == LUA55_VALUE_INTEGER               \
        ? source->payload.integer : 0;                                  \
    if ((expected_tag) == LUA55_VALUE_FLOAT &&                          \
        !flt_to_int_eq(source->payload.floating, &value)) { GUARD_FAILED(frame); return; } \
    SET_TAG(target, LUA55_VALUE_INTEGER);                               \
    target->payload.integer = ~value;                                   \
    lua55_residual_next(frame);                                         \
}

RESIDUAL_BNOT(lua55_residual_bnot_int, LUA55_VALUE_INTEGER)
RESIDUAL_BNOT(lua55_residual_bnot_flt, LUA55_VALUE_FLOAT)

#define RESIDUAL_NOT(name, falsy)                                       \
STENCIL(name)(Lua55LearnFrameV1 *frame)                                 \
{                                                                       \
    Lua55ValueV1 *target = &frame->values[UNARY_TARGET_INDEX];          \
    Lua55ValueV1 *source = &frame->values[UNARY_SOURCE_INDEX];          \
    uint32_t tag = source->tag;                                         \
    if ((falsy) ? (tag != LUA55_VALUE_NIL && tag != LUA55_VALUE_FALSE)  \
                : (tag == LUA55_VALUE_NIL || tag == LUA55_VALUE_FALSE)) { \
        GUARD_FAILED(frame); return;                                    \
    }                                                                   \
    SET_TAG(target, (falsy) ? LUA55_VALUE_TRUE : LUA55_VALUE_FALSE);    \
    lua55_residual_next(frame);                                         \
}

RESIDUAL_NOT(lua55_residual_not_falsy, 1)
RESIDUAL_NOT(lua55_residual_not_truthy, 0)

#define RESIDUAL_LEN_STRING(name, expected_tag)                         \
STENCIL(name)(Lua55LearnFrameV1 *frame)                                 \
{                                                                       \
    Lua55ValueV1 *target = &frame->values[UNARY_TARGET_INDEX];          \
    Lua55ValueV1 *source = &frame->values[UNARY_SOURCE_INDEX];          \
    if (source->tag != (expected_tag)) { GUARD_FAILED(frame); return; } \
    Lua55GuestStringV1 *str = (Lua55GuestStringV1 *)source->payload.reference; \
    SET_TAG(target, LUA55_VALUE_INTEGER);                               \
    target->payload.integer = (str != 0) ? (int64_t)str->length : 0;    \
    lua55_residual_next(frame);                                         \
}

RESIDUAL_LEN_STRING(lua55_residual_len_shrt, LUA55_VALUE_SHORT_STRING)
RESIDUAL_LEN_STRING(lua55_residual_len_lng, LUA55_VALUE_LONG_STRING)

STENCIL(lua55_residual_len_table)(Lua55LearnFrameV1 *frame)
{
    Lua55ValueV1 *target = &frame->values[UNARY_TARGET_INDEX];
    Lua55ValueV1 *source = &frame->values[UNARY_SOURCE_INDEX];
    Lua55GuestTableV1 *table;
    if (source->tag != LUA55_VALUE_TABLE || frame->heap == 0) {
        GUARD_FAILED(frame); return;
    }
    table = (Lua55GuestTableV1 *)source->payload.reference;
    if (table == 0 || table->header.kind != LUA55_OBJECT_TABLE ||
        table->heap != frame->heap || table->metatable_reference != 0) {
        GUARD_FAILED(frame); return;
    }
    SET_TAG(target, LUA55_VALUE_INTEGER);
    target->payload.integer = table_len(table);
    lua55_residual_next(frame);
}

/* ---- Self-selecting (polymorphic) unary residuals ------------------------ */

#define POLY_TARGET_HOLE UINT32_C(0x111)
#define POLY_SOURCE_HOLE UINT32_C(0x222)

STENCIL(lua55_poly_unm)(Lua55LearnFrameV1 *frame)
{
    uint32_t target_index = POLY_TARGET_HOLE;
    __asm__ volatile ("" : "+r"(target_index));
    uint32_t source_index = POLY_SOURCE_HOLE;
    __asm__ volatile ("" : "+r"(source_index));
    Lua55ValueV1 *target = &frame->values[target_index];
    Lua55ValueV1 *source = &frame->values[source_index];
    if (source->tag == LUA55_VALUE_INTEGER) {
        SET_TAG(target, LUA55_VALUE_INTEGER);
        target->payload.integer = int_unm(source->payload.integer);
    } else if (source->tag == LUA55_VALUE_FLOAT) {
        SET_TAG(target, LUA55_VALUE_FLOAT);
        target->payload.floating = flt_unm(source->payload.floating);
    } else { REJECT(frame); LUA55_CPS_HOST_EXIT(frame); }
    lua55_residual_next(frame);
}

STENCIL(lua55_poly_bnot)(Lua55LearnFrameV1 *frame)
{
    uint32_t target_index = POLY_TARGET_HOLE;
    __asm__ volatile ("" : "+r"(target_index));
    uint32_t source_index = POLY_SOURCE_HOLE;
    __asm__ volatile ("" : "+r"(source_index));
    Lua55ValueV1 *target = &frame->values[target_index];
    Lua55ValueV1 *source = &frame->values[source_index];
    int64_t value = 0;
    if (source->tag == LUA55_VALUE_INTEGER) value = source->payload.integer;
    else if (source->tag == LUA55_VALUE_FLOAT &&
             flt_to_int_eq(source->payload.floating, &value)) { }
    else { REJECT(frame); LUA55_CPS_HOST_EXIT(frame); }
    SET_TAG(target, LUA55_VALUE_INTEGER);
    target->payload.integer = ~value;
    lua55_residual_next(frame);
}

STENCIL(lua55_poly_not)(Lua55LearnFrameV1 *frame)
{
    uint32_t target_index = POLY_TARGET_HOLE;
    __asm__ volatile ("" : "+r"(target_index));
    uint32_t source_index = POLY_SOURCE_HOLE;
    __asm__ volatile ("" : "+r"(source_index));
    Lua55ValueV1 *target = &frame->values[target_index];
    Lua55ValueV1 *source = &frame->values[source_index];
    SET_TAG(target, (source->tag == LUA55_VALUE_NIL || source->tag == LUA55_VALUE_FALSE)
        ? LUA55_VALUE_TRUE : LUA55_VALUE_FALSE);
    lua55_residual_next(frame);
}

STENCIL(lua55_poly_len)(Lua55LearnFrameV1 *frame)
{
    uint32_t target_index = POLY_TARGET_HOLE;
    __asm__ volatile ("" : "+r"(target_index));
    uint32_t source_index = POLY_SOURCE_HOLE;
    __asm__ volatile ("" : "+r"(source_index));
    Lua55ValueV1 *target = &frame->values[target_index];
    Lua55ValueV1 *source = &frame->values[source_index];
    if (source->tag == LUA55_VALUE_SHORT_STRING ||
        source->tag == LUA55_VALUE_LONG_STRING) {
        Lua55GuestStringV1 *str =
            (Lua55GuestStringV1 *)source->payload.reference;
        SET_TAG(target, LUA55_VALUE_INTEGER);
        target->payload.integer = (str != 0) ? (int64_t)str->length : 0;
    } else if (learn_len_table(frame, source) != 0) {
        Lua55GuestTableV1 *table =
            (Lua55GuestTableV1 *)source->payload.reference;
        SET_TAG(target, LUA55_VALUE_INTEGER);
        target->payload.integer = table_len(table);
    } else { REJECT(frame); LUA55_CPS_HOST_EXIT(frame); }
    lua55_residual_next(frame);
}
