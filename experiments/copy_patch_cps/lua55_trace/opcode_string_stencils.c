#include "opcode_value_v1.h"

#define REFERENCE_BITS UINT64_C(0x1029384756abcdef)

#define LEARN_STRING(name, quote_id, value_tag)                 \
STENCIL(name)(Lua55LearnFrameV1 *frame)                         \
{                                                               \
    uint64_t reference = REFERENCE_BITS;                         \
    __asm__ volatile ("" : "+r"(reference));                   \
    RECORD_FIXED(frame, quote_id);                              \
    SET_TAG(&frame->values[TARGET_INDEX], value_tag);           \
    frame->values[TARGET_INDEX].payload.reference =             \
        (uintptr_t)reference;                                   \
    lua55_learn_next(frame);                                    \
}

LEARN_STRING(lua55_learn_loadk_short_string,
    LUA55_QUOTE_LOADK_SHORT_STRING, LUA55_VALUE_SHORT_STRING)
LEARN_STRING(lua55_learn_loadk_long_string,
    LUA55_QUOTE_LOADK_LONG_STRING, LUA55_VALUE_LONG_STRING)
LEARN_STRING(lua55_learn_loadkx_short_string,
    LUA55_QUOTE_LOADKX_SHORT_STRING, LUA55_VALUE_SHORT_STRING)
LEARN_STRING(lua55_learn_loadkx_long_string,
    LUA55_QUOTE_LOADKX_LONG_STRING, LUA55_VALUE_LONG_STRING)

#define RESIDUAL_STRING(name, value_tag)                        \
STENCIL(name)(Lua55LearnFrameV1 *frame)                         \
{                                                               \
    uint64_t reference = REFERENCE_BITS;                         \
    __asm__ volatile ("" : "+r"(reference));                   \
    SET_TAG(&frame->values[TARGET_INDEX], value_tag);           \
    frame->values[TARGET_INDEX].payload.reference =             \
        (uintptr_t)reference;                                   \
    lua55_residual_next(frame);                                 \
}

RESIDUAL_STRING(lua55_residual_loadk_short_string, LUA55_VALUE_SHORT_STRING)
RESIDUAL_STRING(lua55_residual_loadk_long_string, LUA55_VALUE_LONG_STRING)
RESIDUAL_STRING(lua55_residual_loadkx_short_string, LUA55_VALUE_SHORT_STRING)
RESIDUAL_STRING(lua55_residual_loadkx_long_string, LUA55_VALUE_LONG_STRING)

#define MOVE_STRING(name, expected_tag)                          \
STENCIL(name)(Lua55LearnFrameV1 *frame)                          \
{                                                                \
    Lua55ValueV1 *source = &frame->values[SOURCE_INDEX];         \
    if (source->tag != (expected_tag)) {                         \
        frame->resume_pc = RESUME_PC;                            \
        frame->status = LUA55_GUARD_FAILED;                      \
        return;                                                   \
    }                                                             \
    SET_TAG(&frame->values[TARGET_INDEX], expected_tag);         \
    frame->values[TARGET_INDEX].payload.reference =              \
        source->payload.reference;                               \
    lua55_residual_next(frame);                                  \
}

MOVE_STRING(lua55_residual_move_short_string, LUA55_VALUE_SHORT_STRING)
MOVE_STRING(lua55_residual_move_long_string, LUA55_VALUE_LONG_STRING)
