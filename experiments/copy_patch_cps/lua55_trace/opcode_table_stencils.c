#include "opcode_value_v1.h"

#define RECEIVER_INDEX UINT32_C(0x444)
#define INTEGER_KEY UINT32_C(0x55667788)
#define KEY_REFERENCE UINT64_C(0x1234fedcba987650)
#define TABLE_REFERENCE UINT64_C(0x3141592653589793)
#define SLOT_REFERENCE UINT64_C(0x2718281828459045)
#define STORAGE_GENERATION UINT32_C(0x5a6b7c8d)
#define COLLECTION_EPOCH UINT32_C(0x4a5b6c7d)

static void reject_at(Lua55LearnFrameV1 *frame)
{
    frame->resume_pc = RESUME_PC;
    frame->status = LUA55_REJECTED;
}

static Lua55GuestTableV1 *learn_table(
    Lua55LearnFrameV1 *frame, Lua55ValueV1 *receiver)
{
    Lua55GuestTableV1 *table;
    if (receiver->tag != LUA55_VALUE_TABLE || frame->heap == 0) return 0;
    table = (Lua55GuestTableV1 *)receiver->payload.reference;
    if (table == 0 || table->header.kind != LUA55_OBJECT_TABLE ||
        table->heap != frame->heap || table->metatable_reference != 0) return 0;
    return table;
}

static Lua55ValueV1 *find_field(
    Lua55GuestTableV1 *table, uintptr_t key, int create)
{
    uint32_t index;
    Lua55GuestFieldV1 *vacant = 0;
    for (index = 0; index < table->field_capacity; index++) {
        Lua55GuestFieldV1 *field = &table->field_values[index];
        if (field->occupied && field->key_reference == key) return &field->value;
        if (!field->occupied && vacant == 0) vacant = field;
    }
    if (!create || vacant == 0) return 0;
    vacant->key_reference = key;
    vacant->occupied = 1;
    vacant->reserved = 0;
    SET_TAG(&vacant->value, LUA55_VALUE_NIL);
    vacant->value.payload.reference = 0;
    table->storage_generation++;
    return &vacant->value;
}

static void record_table_slot(
    Lua55LearnFrameV1 *frame, uint32_t opcode, uint32_t variant_bias, Lua55ValueV1 *value,
    Lua55GuestTableV1 *table, Lua55ValueV1 *cell)
{
    uint32_t index = frame->slot_cursor;
    Lua55RecordingSlotV1 *slot = next_slot(frame);
    Lua55TableRecordingV1 *table_slot =
        &((Lua55TableLearnFrameV1 *)frame)->table_slots[index];
    slot->quote = LUA55_QUOTE(opcode, value->tag + 1 + variant_bias);
    slot->expected_tag = value->tag;
    table_slot->expected_storage_generation = table->storage_generation;
    table_slot->expected_collection_epoch = frame->heap->collection_epoch;
    table_slot->expected_reference = (uintptr_t)table;
    table_slot->slot_reference = (uintptr_t)cell;
    table_slot->expected_metatable = table->metatable_reference;
}

static void stabilize_table_slots(Lua55LearnFrameV1 *frame, Lua55GuestTableV1 *table)
{
    uint32_t index;
    for (index = 0; index < frame->slot_cursor; index++) {
        Lua55TableRecordingV1 *slot =
            &((Lua55TableLearnFrameV1 *)frame)->table_slots[index];
        if (slot->expected_reference == (uintptr_t)table)
            slot->expected_storage_generation = table->storage_generation;
    }
}

STENCIL(lua55_learn_geti)(Lua55LearnFrameV1 *frame)
{
    Lua55GuestTableV1 *table = learn_table(frame, &frame->values[RECEIVER_INDEX]);
    Lua55ValueV1 *cell;
    uint32_t key = INTEGER_KEY;
    __asm__ volatile ("" : "+r"(key));
    if (table == 0 || key == 0 || key > table->array_capacity) {
        reject_at(frame); return;
    }
    cell = &table->array_values[key - 1];
    if (cell->tag > LUA55_VALUE_CLOSURE) { reject_at(frame); return; }
    record_table_slot(frame, 13, 0, cell, table, cell);
    frame->values[TARGET_INDEX] = *cell;
    lua55_learn_next(frame);
}

STENCIL(lua55_learn_getfield)(Lua55LearnFrameV1 *frame)
{
    Lua55GuestTableV1 *table = learn_table(frame, &frame->values[RECEIVER_INDEX]);
    Lua55ValueV1 *cell;
    uintptr_t key = (uintptr_t)KEY_REFERENCE;
    __asm__ volatile ("" : "+r"(key));
    if (table == 0) { reject_at(frame); return; }
    cell = find_field(table, key, 0);
    if (cell == 0) {
        Lua55ValueV1 nil_value;
        SET_TAG(&nil_value, LUA55_VALUE_NIL);
        nil_value.payload.reference = 0;
        record_table_slot(frame, 14, 0, &nil_value, table, 0);
        frame->values[TARGET_INDEX] = nil_value;
    }
    else {
        if (cell->tag > LUA55_VALUE_CLOSURE) { reject_at(frame); return; }
        record_table_slot(frame, 14, 1, cell, table, cell);
        frame->values[TARGET_INDEX] = *cell;
    }
    lua55_learn_next(frame);
}

static void learn_set(
    Lua55LearnFrameV1 *frame, uint32_t opcode, Lua55GuestTableV1 *table,
    Lua55ValueV1 *cell, Lua55ValueV1 *source)
{
    if (source->tag > LUA55_VALUE_CLOSURE) { reject_at(frame); return; }
    *cell = *source;
    if (source->tag >= LUA55_VALUE_SHORT_STRING) {
        table->barrier_count++;
        frame->heap->barrier_epoch++;
    }
    record_table_slot(frame, opcode, 0, source, table, cell);
    lua55_learn_next(frame);
}

STENCIL(lua55_learn_seti)(Lua55LearnFrameV1 *frame)
{
    Lua55GuestTableV1 *table = learn_table(frame, &frame->values[RECEIVER_INDEX]);
    uint32_t key = INTEGER_KEY;
    __asm__ volatile ("" : "+r"(key));
    if (table == 0 || key == 0 || key > table->array_capacity) {
        reject_at(frame); return;
    }
    learn_set(frame, 17, table, &table->array_values[key - 1],
        &frame->values[SOURCE_INDEX]);
}

STENCIL(lua55_learn_setfield)(Lua55LearnFrameV1 *frame)
{
    Lua55GuestTableV1 *table = learn_table(frame, &frame->values[RECEIVER_INDEX]);
    Lua55ValueV1 *cell;
    uintptr_t key = (uintptr_t)KEY_REFERENCE;
    __asm__ volatile ("" : "+r"(key));
    if (table == 0) { reject_at(frame); return; }
    cell = find_field(table, key, 1);
    if (cell == 0) { reject_at(frame); return; }
    stabilize_table_slots(frame, table);
    learn_set(frame, 18, table, cell, &frame->values[SOURCE_INDEX]);
}

static Lua55GuestTableV1 *guard_table(Lua55LearnFrameV1 *frame)
{
    Lua55ValueV1 *receiver = &frame->values[RECEIVER_INDEX];
    uintptr_t expected = (uintptr_t)TABLE_REFERENCE;
    Lua55GuestTableV1 *table = (Lua55GuestTableV1 *)expected;
    if (receiver->tag != LUA55_VALUE_TABLE || receiver->payload.reference != expected ||
        frame->heap == 0 || frame->heap->collection_epoch != COLLECTION_EPOCH ||
        table->header.kind != LUA55_OBJECT_TABLE || table->heap != frame->heap ||
        table->storage_generation != STORAGE_GENERATION ||
        table->metatable_reference != 0) return 0;
    return table;
}

#define GET_RESIDUAL(name, expected_tag, missing)                       \
STENCIL(name)(Lua55LearnFrameV1 *frame)                                \
{                                                                       \
    Lua55GuestTableV1 *table = guard_table(frame);                      \
    Lua55ValueV1 *target = &frame->values[TARGET_INDEX];                \
    Lua55ValueV1 *cell = (Lua55ValueV1 *)(uintptr_t)SLOT_REFERENCE;     \
    if (table == 0 || (!(missing) && cell->tag != (expected_tag))) {    \
        frame->resume_pc = RESUME_PC;                                   \
        frame->status = LUA55_GUARD_FAILED;                             \
        return;                                                         \
    }                                                                   \
    if (missing) { SET_TAG(target, LUA55_VALUE_NIL); target->payload.reference = 0; } \
    else *target = *cell;                                               \
    lua55_residual_next(frame);                                         \
}

GET_RESIDUAL(lua55_residual_geti_nil, LUA55_VALUE_NIL, 0)
GET_RESIDUAL(lua55_residual_geti_false, LUA55_VALUE_FALSE, 0)
GET_RESIDUAL(lua55_residual_geti_true, LUA55_VALUE_TRUE, 0)
GET_RESIDUAL(lua55_residual_geti_integer, LUA55_VALUE_INTEGER, 0)
GET_RESIDUAL(lua55_residual_geti_float, LUA55_VALUE_FLOAT, 0)
GET_RESIDUAL(lua55_residual_geti_short_string, LUA55_VALUE_SHORT_STRING, 0)
GET_RESIDUAL(lua55_residual_geti_long_string, LUA55_VALUE_LONG_STRING, 0)

GET_RESIDUAL(lua55_residual_getfield_missing, LUA55_VALUE_NIL, 1)
GET_RESIDUAL(lua55_residual_getfield_nil, LUA55_VALUE_NIL, 0)
GET_RESIDUAL(lua55_residual_getfield_false, LUA55_VALUE_FALSE, 0)
GET_RESIDUAL(lua55_residual_getfield_true, LUA55_VALUE_TRUE, 0)
GET_RESIDUAL(lua55_residual_getfield_integer, LUA55_VALUE_INTEGER, 0)
GET_RESIDUAL(lua55_residual_getfield_float, LUA55_VALUE_FLOAT, 0)
GET_RESIDUAL(lua55_residual_getfield_short_string, LUA55_VALUE_SHORT_STRING, 0)
GET_RESIDUAL(lua55_residual_getfield_long_string, LUA55_VALUE_LONG_STRING, 0)

#define SET_RESIDUAL(name, expected_tag)                                \
STENCIL(name)(Lua55LearnFrameV1 *frame)                                 \
{                                                                        \
    Lua55GuestTableV1 *table = guard_table(frame);                       \
    Lua55ValueV1 *source = &frame->values[SOURCE_INDEX];                 \
    Lua55ValueV1 *cell = (Lua55ValueV1 *)(uintptr_t)SLOT_REFERENCE;      \
    if (table == 0 || source->tag != (expected_tag)) {                   \
        frame->resume_pc = RESUME_PC;                                    \
        frame->status = LUA55_GUARD_FAILED;                              \
        return;                                                          \
    }                                                                    \
    *cell = *source;                                                     \
    if ((expected_tag) >= LUA55_VALUE_SHORT_STRING) {                    \
        table->barrier_count++; frame->heap->barrier_epoch++;            \
    }                                                                    \
    lua55_residual_next(frame);                                          \
}

SET_RESIDUAL(lua55_residual_seti_nil, LUA55_VALUE_NIL)
SET_RESIDUAL(lua55_residual_seti_false, LUA55_VALUE_FALSE)
SET_RESIDUAL(lua55_residual_seti_true, LUA55_VALUE_TRUE)
SET_RESIDUAL(lua55_residual_seti_integer, LUA55_VALUE_INTEGER)
SET_RESIDUAL(lua55_residual_seti_float, LUA55_VALUE_FLOAT)
SET_RESIDUAL(lua55_residual_seti_short_string, LUA55_VALUE_SHORT_STRING)
SET_RESIDUAL(lua55_residual_seti_long_string, LUA55_VALUE_LONG_STRING)

SET_RESIDUAL(lua55_residual_setfield_nil, LUA55_VALUE_NIL)
SET_RESIDUAL(lua55_residual_setfield_false, LUA55_VALUE_FALSE)
SET_RESIDUAL(lua55_residual_setfield_true, LUA55_VALUE_TRUE)
SET_RESIDUAL(lua55_residual_setfield_integer, LUA55_VALUE_INTEGER)
SET_RESIDUAL(lua55_residual_setfield_float, LUA55_VALUE_FLOAT)
SET_RESIDUAL(lua55_residual_setfield_short_string, LUA55_VALUE_SHORT_STRING)
SET_RESIDUAL(lua55_residual_setfield_long_string, LUA55_VALUE_LONG_STRING)
SET_RESIDUAL(lua55_residual_setfield_closure, LUA55_VALUE_CLOSURE)
SET_RESIDUAL(lua55_residual_seti_closure, LUA55_VALUE_CLOSURE)

GET_RESIDUAL(lua55_residual_getfield_closure, LUA55_VALUE_CLOSURE, 0)
GET_RESIDUAL(lua55_residual_geti_closure, LUA55_VALUE_CLOSURE, 0)
