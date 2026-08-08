#include "opcode_value_v1.h"

STENCIL(lua55_learn_move)(Lua55LearnFrameV1 *frame)
{
    Lua55ValueV1 *source = &frame->values[SOURCE_INDEX];
    Lua55RecordingSlotV1 *slot = next_slot(frame);
    uint32_t tag = source->tag;
    slot->expected_tag = tag;
    if (tag <= LUA55_VALUE_LONG_STRING || tag == LUA55_VALUE_TABLE ||
        tag == LUA55_VALUE_CLOSURE) {
        slot->quote = tag + LUA55_QUOTE_MOVE_NIL;
        frame->values[TARGET_INDEX] = *source;
        lua55_learn_next(frame);
    }
    else {
        slot->quote = LUA55_QUOTE_REJECTED;
        frame->resume_pc = RESUME_PC;
        frame->status = LUA55_REJECTED;
    }
}

STENCIL(lua55_learn_loadi)(Lua55LearnFrameV1 *frame)
{
    uint64_t bits = INTEGER_BITS;
    __asm__ volatile ("" : "+r"(bits));
    RECORD_FIXED(frame, LUA55_QUOTE_LOADI);
    SET_TAG(&frame->values[TARGET_INDEX], LUA55_VALUE_INTEGER);
    frame->values[TARGET_INDEX].payload.integer = (int64_t)bits;
    lua55_learn_next(frame);
}

STENCIL(lua55_learn_loadf)(Lua55LearnFrameV1 *frame)
{
    uint64_t bits = FLOAT_BITS;
    __asm__ volatile ("" : "+r"(bits));
    RECORD_FIXED(frame, LUA55_QUOTE_LOADF);
    SET_TAG(&frame->values[TARGET_INDEX], LUA55_VALUE_FLOAT);
    memcpy(&frame->values[TARGET_INDEX].payload.floating, &bits, sizeof(bits));
    lua55_learn_next(frame);
}

#define LEARN_TAGGED(name, quote_id, value_tag)           \
STENCIL(name)(Lua55LearnFrameV1 *frame)                   \
{                                                         \
    RECORD_FIXED(frame, quote_id);                        \
    SET_TAG(&frame->values[TARGET_INDEX], value_tag);     \
    lua55_learn_next(frame);                              \
}

#define LEARN_INTEGER(name, quote_id)                      \
STENCIL(name)(Lua55LearnFrameV1 *frame)                   \
{                                                         \
    uint64_t bits = INTEGER_BITS;                         \
    __asm__ volatile ("" : "+r"(bits));                  \
    RECORD_FIXED(frame, quote_id);                        \
    SET_TAG(&frame->values[TARGET_INDEX], LUA55_VALUE_INTEGER); \
    frame->values[TARGET_INDEX].payload.integer = (int64_t)bits; \
    lua55_learn_next(frame);                              \
}

#define LEARN_FLOAT(name, quote_id)                        \
STENCIL(name)(Lua55LearnFrameV1 *frame)                   \
{                                                         \
    uint64_t bits = FLOAT_BITS;                           \
    __asm__ volatile ("" : "+r"(bits));                  \
    RECORD_FIXED(frame, quote_id);                        \
    SET_TAG(&frame->values[TARGET_INDEX], LUA55_VALUE_FLOAT); \
    memcpy(&frame->values[TARGET_INDEX].payload.floating, &bits, sizeof(bits)); \
    lua55_learn_next(frame);                              \
}

LEARN_TAGGED(lua55_learn_loadk_nil, LUA55_QUOTE_LOADK_NIL, LUA55_VALUE_NIL)
LEARN_TAGGED(lua55_learn_loadk_false, LUA55_QUOTE_LOADK_FALSE, LUA55_VALUE_FALSE)
LEARN_TAGGED(lua55_learn_loadk_true, LUA55_QUOTE_LOADK_TRUE, LUA55_VALUE_TRUE)
LEARN_INTEGER(lua55_learn_loadk_integer, LUA55_QUOTE_LOADK_INTEGER)
LEARN_FLOAT(lua55_learn_loadk_float, LUA55_QUOTE_LOADK_FLOAT)

LEARN_TAGGED(lua55_learn_loadkx_nil, LUA55_QUOTE_LOADKX_NIL, LUA55_VALUE_NIL)
LEARN_TAGGED(lua55_learn_loadkx_false, LUA55_QUOTE_LOADKX_FALSE, LUA55_VALUE_FALSE)
LEARN_TAGGED(lua55_learn_loadkx_true, LUA55_QUOTE_LOADKX_TRUE, LUA55_VALUE_TRUE)
LEARN_INTEGER(lua55_learn_loadkx_integer, LUA55_QUOTE_LOADKX_INTEGER)
LEARN_FLOAT(lua55_learn_loadkx_float, LUA55_QUOTE_LOADKX_FLOAT)

LEARN_TAGGED(lua55_learn_loadfalse, LUA55_QUOTE_LOADFALSE, LUA55_VALUE_FALSE)
LEARN_TAGGED(lua55_learn_lfalseskip, LUA55_QUOTE_LFALSESKIP, LUA55_VALUE_FALSE)
LEARN_TAGGED(lua55_learn_loadtrue, LUA55_QUOTE_LOADTRUE, LUA55_VALUE_TRUE)

STENCIL(lua55_learn_loadnil)(Lua55LearnFrameV1 *frame)
{
    uint32_t span = SPAN_COUNT;
    uint32_t index;
    __asm__ volatile ("" : "+r"(span));
    RECORD_FIXED(frame, LUA55_QUOTE_LOADNIL_SPAN);
    for (index = 0; index < span; index++)
        SET_TAG(&frame->values[TARGET_INDEX + index], LUA55_VALUE_NIL);
    lua55_learn_next(frame);
}

#define MOVE_RESIDUAL(name, expected, copy_payload)              \
STENCIL(name)(Lua55LearnFrameV1 *frame)                          \
{                                                                \
    Lua55ValueV1 *source = &frame->values[SOURCE_INDEX];         \
    if (source->tag != (expected)) {                             \
        frame->resume_pc = RESUME_PC;                            \
        frame->status = LUA55_GUARD_FAILED;                      \
        return;                                                  \
    }                                                            \
    SET_TAG(&frame->values[TARGET_INDEX], expected);             \
    copy_payload;                                                \
    lua55_residual_next(frame);                                  \
}

MOVE_RESIDUAL(lua55_residual_move_nil, LUA55_VALUE_NIL, (void)0)
MOVE_RESIDUAL(lua55_residual_move_false, LUA55_VALUE_FALSE, (void)0)
MOVE_RESIDUAL(lua55_residual_move_true, LUA55_VALUE_TRUE, (void)0)
MOVE_RESIDUAL(lua55_residual_move_integer, LUA55_VALUE_INTEGER,
    frame->values[TARGET_INDEX].payload.integer = source->payload.integer)
MOVE_RESIDUAL(lua55_residual_move_float, LUA55_VALUE_FLOAT,
    frame->values[TARGET_INDEX].payload.floating = source->payload.floating)
MOVE_RESIDUAL(lua55_residual_move_table, LUA55_VALUE_TABLE,
    frame->values[TARGET_INDEX].payload.reference = source->payload.reference)
MOVE_RESIDUAL(lua55_residual_move_closure, LUA55_VALUE_CLOSURE,
    frame->values[TARGET_INDEX].payload.reference = source->payload.reference)

STENCIL(lua55_residual_loadi)(Lua55LearnFrameV1 *frame)
{
    uint64_t bits = INTEGER_BITS;
    __asm__ volatile ("" : "+r"(bits));
    SET_TAG(&frame->values[TARGET_INDEX], LUA55_VALUE_INTEGER);
    frame->values[TARGET_INDEX].payload.integer = (int64_t)bits;
    lua55_residual_next(frame);
}

STENCIL(lua55_residual_loadf)(Lua55LearnFrameV1 *frame)
{
    uint64_t bits = FLOAT_BITS;
    __asm__ volatile ("" : "+r"(bits));
    SET_TAG(&frame->values[TARGET_INDEX], LUA55_VALUE_FLOAT);
    memcpy(&frame->values[TARGET_INDEX].payload.floating, &bits, sizeof(bits));
    lua55_residual_next(frame);
}

#define RESIDUAL_TAGGED(name, value_tag)                  \
STENCIL(name)(Lua55LearnFrameV1 *frame)                   \
{                                                         \
    SET_TAG(&frame->values[TARGET_INDEX], value_tag);     \
    lua55_residual_next(frame);                           \
}

#define RESIDUAL_INTEGER(name)                            \
STENCIL(name)(Lua55LearnFrameV1 *frame)                   \
{                                                         \
    uint64_t bits = INTEGER_BITS;                         \
    __asm__ volatile ("" : "+r"(bits));                  \
    SET_TAG(&frame->values[TARGET_INDEX], LUA55_VALUE_INTEGER); \
    frame->values[TARGET_INDEX].payload.integer = (int64_t)bits; \
    lua55_residual_next(frame);                           \
}

#define RESIDUAL_FLOAT(name)                              \
STENCIL(name)(Lua55LearnFrameV1 *frame)                   \
{                                                         \
    uint64_t bits = FLOAT_BITS;                           \
    __asm__ volatile ("" : "+r"(bits));                  \
    SET_TAG(&frame->values[TARGET_INDEX], LUA55_VALUE_FLOAT); \
    memcpy(&frame->values[TARGET_INDEX].payload.floating, &bits, sizeof(bits)); \
    lua55_residual_next(frame);                           \
}

RESIDUAL_TAGGED(lua55_residual_loadk_nil, LUA55_VALUE_NIL)
RESIDUAL_TAGGED(lua55_residual_loadk_false, LUA55_VALUE_FALSE)
RESIDUAL_TAGGED(lua55_residual_loadk_true, LUA55_VALUE_TRUE)
RESIDUAL_INTEGER(lua55_residual_loadk_integer)
RESIDUAL_FLOAT(lua55_residual_loadk_float)

RESIDUAL_TAGGED(lua55_residual_loadkx_nil, LUA55_VALUE_NIL)
RESIDUAL_TAGGED(lua55_residual_loadkx_false, LUA55_VALUE_FALSE)
RESIDUAL_TAGGED(lua55_residual_loadkx_true, LUA55_VALUE_TRUE)
RESIDUAL_INTEGER(lua55_residual_loadkx_integer)
RESIDUAL_FLOAT(lua55_residual_loadkx_float)

RESIDUAL_TAGGED(lua55_residual_loadfalse, LUA55_VALUE_FALSE)
RESIDUAL_TAGGED(lua55_residual_lfalseskip, LUA55_VALUE_FALSE)
RESIDUAL_TAGGED(lua55_residual_loadtrue, LUA55_VALUE_TRUE)
RESIDUAL_TAGGED(lua55_residual_loadnil_one, LUA55_VALUE_NIL)

STENCIL(lua55_opcode_finish)(Lua55LearnFrameV1 *frame)
{
    frame->resume_pc = RESUME_PC;
    frame->status = LUA55_COMPLETED;
}

/* ---- Self-selecting (polymorphic) residuals ------------------------------
   The value-shape dispatch IS the selection; no quote recording. Register
   indices and constant payloads are runtime holes (patched immediates). */

#define POLY_TARGET UINT32_C(0x111)
#define POLY_SOURCE UINT32_C(0x222)
#define POLY_UPVALUE UINT32_C(0x333)
#define POLY_INTEGER_BITS UINT64_C(0x1112131415161718)
#define POLY_FLOAT_BITS UINT64_C(0x123456789abcdef0)
#define POLY_CONST_TAG UINT32_C(0x3c3b3a39)
#define POLY_CONST_INT UINT64_C(0x2122232425262728)
#define POLY_CONST_FLT UINT64_C(0x123456789abcdef0)
#define POLY_CONST_REF UINT64_C(0x0abcdef012345679)
#define POLY_SPAN UINT32_C(0x71727374)

#define POLY_VALUE(local, reg, hole)                                         \
    uint32_t reg = POLY_##hole;                                            \
    __asm__ volatile ("" : "+r"(reg));                                     \
    Lua55ValueV1 *local = &frame->values[reg];

STENCIL(lua55_poly_move)(Lua55LearnFrameV1 *frame)
{
    POLY_VALUE(target, target_reg, TARGET)
    POLY_VALUE(source, source_reg, SOURCE)
    *target = *source;
    lua55_residual_next(frame);
}

STENCIL(lua55_poly_loadi)(Lua55LearnFrameV1 *frame)
{
    POLY_VALUE(target, target_reg, TARGET)
    int64_t bits = (int64_t)POLY_INTEGER_BITS;
    __asm__ volatile ("" : "+r"(bits));
    SET_TAG(target, LUA55_VALUE_INTEGER);
    target->payload.integer = bits;
    lua55_residual_next(frame);
}

STENCIL(lua55_poly_loadf)(Lua55LearnFrameV1 *frame)
{
    POLY_VALUE(target, target_reg, TARGET)
    uint64_t bits = POLY_FLOAT_BITS;
    __asm__ volatile ("" : "+r"(bits));
    SET_TAG(target, LUA55_VALUE_FLOAT);
    memcpy(&target->payload.floating, &bits, sizeof(bits));
    lua55_residual_next(frame);
}

STENCIL(lua55_poly_loadk)(Lua55LearnFrameV1 *frame)
{
    POLY_VALUE(target, target_reg, TARGET)
    uint32_t tag = POLY_CONST_TAG;
    __asm__ volatile ("" : "+r"(tag));
    SET_TAG(target, tag);
    if (tag == LUA55_VALUE_INTEGER) {
        target->payload.integer = (int64_t)POLY_CONST_INT;
    } else if (tag == LUA55_VALUE_FLOAT) {
        uint64_t bits = POLY_CONST_FLT;
        __asm__ volatile ("" : "+r"(bits));
        memcpy(&target->payload.floating, &bits, sizeof(bits));
    } else {
        target->payload.reference = (uintptr_t)POLY_CONST_REF;
    }
    lua55_residual_next(frame);
}

STENCIL(lua55_poly_loadkx)(Lua55LearnFrameV1 *frame)
{
    POLY_VALUE(target, target_reg, TARGET)
    uint32_t tag = POLY_CONST_TAG;
    __asm__ volatile ("" : "+r"(tag));
    SET_TAG(target, tag);
    if (tag == LUA55_VALUE_INTEGER) {
        target->payload.integer = (int64_t)POLY_CONST_INT;
    } else if (tag == LUA55_VALUE_FLOAT) {
        uint64_t bits = POLY_CONST_FLT;
        __asm__ volatile ("" : "+r"(bits));
        memcpy(&target->payload.floating, &bits, sizeof(bits));
    } else {
        target->payload.reference = (uintptr_t)POLY_CONST_REF;
    }
    lua55_residual_next(frame);
}

STENCIL(lua55_poly_loadfalse)(Lua55LearnFrameV1 *frame)
{
    POLY_VALUE(target, target_reg, TARGET)
    SET_TAG(target, LUA55_VALUE_FALSE);
    lua55_residual_next(frame);
}

STENCIL(lua55_poly_loadfalse_skip)(Lua55LearnFrameV1 *frame)
{
    POLY_VALUE(target, target_reg, TARGET)
    SET_TAG(target, LUA55_VALUE_FALSE);
    lua55_residual_next(frame);
}

STENCIL(lua55_poly_loadtrue)(Lua55LearnFrameV1 *frame)
{
    POLY_VALUE(target, target_reg, TARGET)
    SET_TAG(target, LUA55_VALUE_TRUE);
    lua55_residual_next(frame);
}

STENCIL(lua55_poly_loadnil)(Lua55LearnFrameV1 *frame)
{
    POLY_VALUE(target, target_reg, TARGET)
    uint32_t span = POLY_SPAN;
    __asm__ volatile ("" : "+r"(span));
    uint32_t i;
    for (i = 0; i < span; i++)
        SET_TAG(&target[i], LUA55_VALUE_NIL);
    lua55_residual_next(frame);
}

STENCIL(lua55_poly_getupval)(Lua55LearnFrameV1 *frame)
{
    POLY_VALUE(target, target_reg, TARGET)
    POLY_VALUE(upvalue, upvalue_reg, UPVALUE)
    Lua55UpvalueCellV1 *cell = &frame->upvalues[upvalue_reg];
    *target = cell->state == LUA55_UPVALUE_OPEN ? cell->open_slot[0] : cell->closed_value;
    lua55_residual_next(frame);
}

STENCIL(lua55_poly_setupval)(Lua55LearnFrameV1 *frame)
{
    POLY_VALUE(upvalue, upvalue_reg, UPVALUE)
    POLY_VALUE(source, source_reg, SOURCE)
    Lua55UpvalueCellV1 *cell = &frame->upvalues[upvalue_reg];
    if (cell->state == LUA55_UPVALUE_OPEN) cell->open_slot[0] = *source;
    else cell->closed_value = *source;
    lua55_residual_next(frame);
}
