#include "opcode_value_v1.h"

#define EXPECTED_GENERATION UINT32_C(0x44556677)

static inline Lua55ValueV1 *cell_value(Lua55UpvalueCellV1 *cell)
{
    return cell->state == LUA55_UPVALUE_OPEN ? cell->open_slot : &cell->closed_value;
}

static inline void reject(Lua55LearnFrameV1 *frame)
{
    frame->resume_pc = RESUME_PC;
    frame->status = LUA55_REJECTED;
}

static inline void guard_failed(Lua55LearnFrameV1 *frame)
{
    frame->resume_pc = RESUME_PC;
    frame->status = LUA55_GUARD_FAILED;
}

STENCIL(lua55_learn_getupval)(Lua55LearnFrameV1 *frame)
{
    Lua55UpvalueCellV1 *cell = &frame->upvalues[UPVALUE_INDEX];
    Lua55RecordingSlotV1 *slot = next_slot(frame);
    Lua55ValueV1 *value;
    uint32_t tag;
    if (cell->state != LUA55_UPVALUE_OPEN && cell->state != LUA55_UPVALUE_CLOSED) {
        slot->quote = LUA55_QUOTE_REJECTED;
        reject(frame);
        return;
    }
    value = cell_value(cell);
    tag = value->tag;
    slot->expected_tag = tag;
    slot->expected_state = cell->state;
    slot->expected_generation = cell->generation;
    if (tag == LUA55_VALUE_CLOSURE) {
        slot->quote = (cell->state == LUA55_UPVALUE_OPEN
            ? LUA55_QUOTE_GETUPVAL_OPEN_CLOSURE : LUA55_QUOTE_GETUPVAL_CLOSED_CLOSURE);
    } else if (tag > LUA55_VALUE_FLOAT) {
        slot->quote = LUA55_QUOTE_REJECTED;
        reject(frame);
        return;
    } else {
        slot->quote = (cell->state == LUA55_UPVALUE_OPEN
            ? LUA55_QUOTE_GETUPVAL_OPEN_NIL : LUA55_QUOTE_GETUPVAL_CLOSED_NIL) + tag;
    }
    frame->values[TARGET_INDEX] = *value;
    lua55_learn_next(frame);
}

STENCIL(lua55_learn_setupval)(Lua55LearnFrameV1 *frame)
{
    Lua55UpvalueCellV1 *cell = &frame->upvalues[UPVALUE_INDEX];
    Lua55RecordingSlotV1 *slot = next_slot(frame);
    Lua55ValueV1 *source = &frame->values[SOURCE_INDEX];
    uint32_t tag = source->tag;
    slot->expected_tag = tag;
    slot->expected_state = cell->state;
    slot->expected_generation = cell->generation;
    if ((cell->state != LUA55_UPVALUE_OPEN && cell->state != LUA55_UPVALUE_CLOSED)
            || tag > LUA55_VALUE_FLOAT) {
        slot->quote = LUA55_QUOTE_REJECTED;
        reject(frame);
        return;
    }
    slot->quote = (cell->state == LUA55_UPVALUE_OPEN
        ? LUA55_QUOTE_SETUPVAL_OPEN_NIL : LUA55_QUOTE_SETUPVAL_CLOSED_NIL) + tag;
    *cell_value(cell) = *source;
    lua55_learn_next(frame);
}

#define CHECK_CELL(frame, cell, expected_state) do {                 \
    uint32_t expected_generation = EXPECTED_GENERATION;              \
    __asm__ volatile ("" : "+r"(expected_generation));              \
    if ((cell)->state != (expected_state) ||                          \
            (cell)->generation != expected_generation) {             \
        guard_failed(frame);                                         \
        return;                                                       \
    }                                                                 \
} while (0)

#define GET_RESIDUAL(name, expected_state, expected_tag, copy_payload) \
STENCIL(name)(Lua55LearnFrameV1 *frame)                               \
{                                                                     \
    Lua55UpvalueCellV1 *cell = &frame->upvalues[UPVALUE_INDEX];       \
    Lua55ValueV1 *source;                                             \
    CHECK_CELL(frame, cell, expected_state);                          \
    source = (expected_state) == LUA55_UPVALUE_OPEN                   \
        ? cell->open_slot : &cell->closed_value;                      \
    if (source->tag != (expected_tag)) {                              \
        guard_failed(frame);                                         \
        return;                                                       \
    }                                                                 \
    SET_TAG(&frame->values[TARGET_INDEX], expected_tag);              \
    copy_payload;                                                     \
    lua55_residual_next(frame);                                       \
}

#define SET_RESIDUAL(name, expected_state, expected_tag, copy_payload) \
STENCIL(name)(Lua55LearnFrameV1 *frame)                               \
{                                                                     \
    Lua55UpvalueCellV1 *cell = &frame->upvalues[UPVALUE_INDEX];       \
    Lua55ValueV1 *target;                                             \
    Lua55ValueV1 *source = &frame->values[SOURCE_INDEX];              \
    CHECK_CELL(frame, cell, expected_state);                          \
    if (source->tag != (expected_tag)) {                              \
        guard_failed(frame);                                         \
        return;                                                       \
    }                                                                 \
    target = (expected_state) == LUA55_UPVALUE_OPEN                   \
        ? cell->open_slot : &cell->closed_value;                      \
    SET_TAG(target, expected_tag);                                    \
    copy_payload;                                                     \
    lua55_residual_next(frame);                                       \
}

GET_RESIDUAL(lua55_residual_getupval_open_nil, LUA55_UPVALUE_OPEN, LUA55_VALUE_NIL, (void)0)
GET_RESIDUAL(lua55_residual_getupval_open_false, LUA55_UPVALUE_OPEN, LUA55_VALUE_FALSE, (void)0)
GET_RESIDUAL(lua55_residual_getupval_open_true, LUA55_UPVALUE_OPEN, LUA55_VALUE_TRUE, (void)0)
GET_RESIDUAL(lua55_residual_getupval_open_integer, LUA55_UPVALUE_OPEN, LUA55_VALUE_INTEGER,
    frame->values[TARGET_INDEX].payload.integer = source->payload.integer)
GET_RESIDUAL(lua55_residual_getupval_open_float, LUA55_UPVALUE_OPEN, LUA55_VALUE_FLOAT,
    frame->values[TARGET_INDEX].payload.floating = source->payload.floating)

GET_RESIDUAL(lua55_residual_getupval_closed_nil, LUA55_UPVALUE_CLOSED, LUA55_VALUE_NIL, (void)0)
GET_RESIDUAL(lua55_residual_getupval_closed_false, LUA55_UPVALUE_CLOSED, LUA55_VALUE_FALSE, (void)0)
GET_RESIDUAL(lua55_residual_getupval_closed_true, LUA55_UPVALUE_CLOSED, LUA55_VALUE_TRUE, (void)0)
GET_RESIDUAL(lua55_residual_getupval_closed_integer, LUA55_UPVALUE_CLOSED, LUA55_VALUE_INTEGER,
    frame->values[TARGET_INDEX].payload.integer = source->payload.integer)
GET_RESIDUAL(lua55_residual_getupval_closed_float, LUA55_UPVALUE_CLOSED, LUA55_VALUE_FLOAT,
    frame->values[TARGET_INDEX].payload.floating = source->payload.floating)
GET_RESIDUAL(lua55_residual_getupval_open_closure, LUA55_UPVALUE_OPEN, LUA55_VALUE_CLOSURE,
    frame->values[TARGET_INDEX].payload.reference = source->payload.reference)
GET_RESIDUAL(lua55_residual_getupval_closed_closure, LUA55_UPVALUE_CLOSED, LUA55_VALUE_CLOSURE,
    frame->values[TARGET_INDEX].payload.reference = source->payload.reference)

SET_RESIDUAL(lua55_residual_setupval_open_nil, LUA55_UPVALUE_OPEN, LUA55_VALUE_NIL, (void)0)
SET_RESIDUAL(lua55_residual_setupval_open_false, LUA55_UPVALUE_OPEN, LUA55_VALUE_FALSE, (void)0)
SET_RESIDUAL(lua55_residual_setupval_open_true, LUA55_UPVALUE_OPEN, LUA55_VALUE_TRUE, (void)0)
SET_RESIDUAL(lua55_residual_setupval_open_integer, LUA55_UPVALUE_OPEN, LUA55_VALUE_INTEGER,
    target->payload.integer = source->payload.integer)
SET_RESIDUAL(lua55_residual_setupval_open_float, LUA55_UPVALUE_OPEN, LUA55_VALUE_FLOAT,
    target->payload.floating = source->payload.floating)

SET_RESIDUAL(lua55_residual_setupval_closed_nil, LUA55_UPVALUE_CLOSED, LUA55_VALUE_NIL, (void)0)
SET_RESIDUAL(lua55_residual_setupval_closed_false, LUA55_UPVALUE_CLOSED, LUA55_VALUE_FALSE, (void)0)
SET_RESIDUAL(lua55_residual_setupval_closed_true, LUA55_UPVALUE_CLOSED, LUA55_VALUE_TRUE, (void)0)
SET_RESIDUAL(lua55_residual_setupval_closed_integer, LUA55_UPVALUE_CLOSED, LUA55_VALUE_INTEGER,
    target->payload.integer = source->payload.integer)
SET_RESIDUAL(lua55_residual_setupval_closed_float, LUA55_UPVALUE_CLOSED, LUA55_VALUE_FLOAT,
    target->payload.floating = source->payload.floating)
