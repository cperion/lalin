#include "opcode_value_v1.h"

/* Batch 7: generic table access (11/12/15/16/19/20). Metatable-absent
   fast path with identity + shape + key guards, consistent with the
   fixed-key table batch (13/14/17/18). The KEY is a runtime value:
   - GETTABLE/SETTABLE read it from a register,
   - GETTABUP/SETTABUP read the receiver from an upvalue cell and the key
     from a constant,
   - SELF reads the receiver from a register and the key from a constant.
   The learner records the key's tag in slot->expected_state and the key
   value in slot->key_bits; install patches them into the residual, which
   re-guards them every run. Non-int/string keys reject (__index /
   __newindex metamethod path). NEWTABLE bumps a fresh table from the
   guest heap's native region each run (non-moving). */

#define TARGET_INDEX      UINT32_C(0x111)
#define SOURCE_INDEX      UINT32_C(0x222)
#define UPVALUE_INDEX     UINT32_C(0x333)
#define RECEIVER_INDEX    UINT32_C(0x444)
#define KEY_INDEX         UINT32_C(0x555)
#define OBJECT_TARGET_INDEX UINT32_C(0x888)   /* SELF: R[A+1] (the object) */
#define RESUME_PC         UINT32_C(0x66778899)

#define INT_KEY_HOLE      UINT64_C(0x7172737475767778)
#define KEY_REF_HOLE      UINT64_C(0x8172837485768778)
#define TABLE_REFERENCE   UINT64_C(0x3141592653589793)
#define SLOT_REFERENCE    UINT64_C(0x2718281828459045)
#define STORAGE_GENERATION UINT32_C(0x5a6b7c8d)
#define COLLECTION_EPOCH  UINT32_C(0x4a5b6c7d)
#define QUOTE_BASE_HOLE   UINT32_C(0x0f1e2d3c)
#define CONST_TAG_HOLE    UINT32_C(0x3c3b3a39)
#define CONST_INT_HOLE    UINT64_C(0x2122232425262728)
#define CONST_REF_HOLE    UINT64_C(0x0abcdef012345679)
#define ARRAY_CAP_HOLE    UINT32_C(0x0a0b0c0d)
#define FIELD_CAP_HOLE    UINT32_C(0x1a1b1c1d)
#define UPVALUE_STATE_HOLE UINT32_C(0x2a2b2c2d)
#define UPVALUE_GEN_HOLE  UINT32_C(0x3a3b3c3d)

#define GUARD_FAILED(frame) do {            \
    (frame)->resume_pc = RESUME_PC;          \
    (frame)->status = LUA55_GUARD_FAILED;    \
} while (0)

#define REJECT(frame) do {                  \
    (frame)->resume_pc = RESUME_PC;          \
    (frame)->status = LUA55_REJECTED;        \
} while (0)

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
    Lua55LearnFrameV1 *frame, uint32_t opcode, uint32_t variant, Lua55ValueV1 *value,
    Lua55GuestTableV1 *table, Lua55ValueV1 *cell, uint32_t key_tag, uint64_t key_bits)
{
    uint32_t index = frame->slot_cursor;
    Lua55RecordingSlotV1 *slot = next_slot(frame);
    Lua55TableRecordingV1 *table_slot =
        &((Lua55TableLearnFrameV1 *)frame)->table_slots[index];
    slot->quote = LUA55_QUOTE(opcode, variant);
    slot->expected_tag = value->tag;
    slot->expected_state = key_tag;
    slot->key_bits = key_bits;
    table_slot->expected_storage_generation = table->storage_generation;
    table_slot->expected_collection_epoch = frame->heap->collection_epoch;
    table_slot->expected_reference = (uintptr_t)table;
    table_slot->slot_reference = (uintptr_t)cell;
    table_slot->expected_metatable = table->metatable_reference;
}

/* TABUP ops: the key is a patched constant, so the slot records the
   upvalue's state and generation (the residual re-guards them). */
static void record_tabup_slot(
    Lua55LearnFrameV1 *frame, uint32_t opcode, uint32_t variant, Lua55ValueV1 *value,
    Lua55GuestTableV1 *table, Lua55ValueV1 *cell, Lua55UpvalueCellV1 *upvalue)
{
    uint32_t index = frame->slot_cursor;
    Lua55RecordingSlotV1 *slot = next_slot(frame);
    Lua55TableRecordingV1 *table_slot =
        &((Lua55TableLearnFrameV1 *)frame)->table_slots[index];
    slot->quote = LUA55_QUOTE(opcode, variant);
    slot->expected_tag = value->tag;
    slot->expected_state = upvalue->state;
    slot->expected_generation = upvalue->generation;
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

/* Read the current value of an upvalue cell (open slot or closed cell). */
static Lua55ValueV1 *upvalue_value(
    Lua55LearnFrameV1 *frame, Lua55UpvalueCellV1 *cell)
{
    if (cell->state == LUA55_UPVALUE_OPEN) return cell->open_slot;
    return &cell->closed_value;
}

/* ------------------------------------------------------------------ */
/* Native table allocator: bump from the heap's region (non-moving).   */

static inline Lua55GuestTableV1 *new_table(
    Lua55LearnFrameV1 *frame, uint32_t array_cap, uint32_t field_cap)
{
    Lua55GuestHeapV1 *heap = frame->heap;
    uintptr_t next, aligned;
    size_t table_size = sizeof(Lua55GuestTableV1);
    size_t array_size = sizeof(Lua55ValueV1) * (array_cap > 0 ? array_cap : 1);
    size_t field_size = sizeof(Lua55GuestFieldV1) * (field_cap > 0 ? field_cap : 1);
    Lua55GuestTableV1 *table;
    Lua55ValueV1 *arrays;
    Lua55GuestFieldV1 *fields;
    if (heap == 0 || heap->table_region == 0) return 0;
    next = heap->table_next;
    aligned = (next + 15) & ~(uintptr_t)15;
    if (aligned + table_size + array_size + field_size > heap->table_region_end)
        return 0;
    table = (Lua55GuestTableV1 *)aligned;
    arrays = (Lua55ValueV1 *)(aligned + table_size);
    fields = (Lua55GuestFieldV1 *)(aligned + table_size + array_size);
    uint32_t i;
    table->header.kind = LUA55_OBJECT_TABLE;
    table->header.generation = heap->object_count + 1;
    table->storage_generation = 1;
    /* closed subset: a minimum capacity so `{}` followed by writes works */
    table->array_capacity = array_cap > 0 ? array_cap : 1;
    table->field_capacity = field_cap > 0 ? field_cap : 1;
    table->barrier_count = 0;
    table->metatable_reference = 0;
    table->array_values = arrays;
    table->field_values = fields;
    table->heap = heap;
    for (i = 0; i < (array_cap > 0 ? array_cap : 1); i++) {
        arrays[i].tag = 0;
        arrays[i].reserved = 0;
        arrays[i].payload.reference = 0;
    }
    for (i = 0; i < (field_cap > 0 ? field_cap : 1); i++) {
        fields[i].key_reference = 0;
        fields[i].occupied = 0;
        fields[i].reserved = 0;
        fields[i].value.tag = 0;
        fields[i].value.reserved = 0;
        fields[i].value.payload.reference = 0;
    }
    heap->object_count++;
    heap->table_next = aligned + table_size + array_size + field_size;
    return table;
}

/* ------------------------------------------------------------------ */
/* LEARNERS                                                             */

STENCIL(lua55_learn_gettable)(Lua55LearnFrameV1 *frame)
{
    Lua55ValueV1 *target = &frame->values[TARGET_INDEX];
    Lua55ValueV1 *receiver = &frame->values[RECEIVER_INDEX];
    Lua55ValueV1 *key = &frame->values[KEY_INDEX];
    Lua55GuestTableV1 *table = learn_table(frame, receiver);
    if (table == 0) { reject_at(frame); return; }
    uint32_t base = QUOTE_BASE_HOLE;
    __asm__ volatile ("" : "+r"(base));
    if (key->tag == LUA55_VALUE_INTEGER) {
        int64_t k = key->payload.integer;
        if (k >= 1 && (uint64_t)k <= table->array_capacity) {
            Lua55ValueV1 *cell = &table->array_values[k - 1];
            if (cell->tag > LUA55_VALUE_LONG_STRING) { reject_at(frame); return; }
            record_table_slot(frame, 12, (uint32_t)cell->tag + 1, cell, table, cell,
                LUA55_VALUE_INTEGER, (uint64_t)k);
            frame->values[TARGET_INDEX] = *cell;
        }
        else {
            Lua55ValueV1 nil_value;
            SET_TAG(&nil_value, LUA55_VALUE_NIL);
            nil_value.payload.reference = 0;
            record_table_slot(frame, 12, 8, &nil_value, table, 0,
                LUA55_VALUE_INTEGER, (uint64_t)k);
            frame->values[TARGET_INDEX] = nil_value;
        }
    }
    else if (key->tag == LUA55_VALUE_SHORT_STRING ||
             key->tag == LUA55_VALUE_LONG_STRING) {
        uintptr_t ref = key->payload.reference;
        Lua55ValueV1 *cell = find_field(table, ref, 0);
        if (cell == 0) {
            Lua55ValueV1 nil_value;
            SET_TAG(&nil_value, LUA55_VALUE_NIL);
            nil_value.payload.reference = 0;
            record_table_slot(frame, 12, 16, &nil_value, table, 0,
                key->tag, (uint64_t)ref);
            frame->values[TARGET_INDEX] = nil_value;
        }
        else {
            if (cell->tag > LUA55_VALUE_LONG_STRING) { reject_at(frame); return; }
            record_table_slot(frame, 12, (uint32_t)cell->tag + 9, cell, table, cell,
                key->tag, (uint64_t)ref);
            frame->values[TARGET_INDEX] = *cell;
        }
    }
    else {
        reject_at(frame); return;
    }
    lua55_learn_next(frame);
}

STENCIL(lua55_learn_settable)(Lua55LearnFrameV1 *frame)
{
    Lua55ValueV1 *receiver = &frame->values[RECEIVER_INDEX];
    Lua55ValueV1 *key = &frame->values[KEY_INDEX];
    Lua55ValueV1 *source = &frame->values[SOURCE_INDEX];
    Lua55GuestTableV1 *table = learn_table(frame, receiver);
    if (table == 0) { reject_at(frame); return; }
    if (source->tag > LUA55_VALUE_LONG_STRING) { reject_at(frame); return; }
    Lua55ValueV1 *cell;
    if (key->tag == LUA55_VALUE_INTEGER) {
        int64_t k = key->payload.integer;
        if (k < 1 || (uint64_t)k > table->array_capacity) { reject_at(frame); return; }
        cell = &table->array_values[k - 1];
        stabilize_table_slots(frame, table);
        *cell = *source;
        if (source->tag >= LUA55_VALUE_SHORT_STRING) {
            table->barrier_count++;
            frame->heap->barrier_epoch++;
        }
        record_table_slot(frame, 16, (uint32_t)source->tag + 1, source, table, cell,
            LUA55_VALUE_INTEGER, (uint64_t)k);
    }
    else if (key->tag == LUA55_VALUE_SHORT_STRING ||
             key->tag == LUA55_VALUE_LONG_STRING) {
        uintptr_t ref = key->payload.reference;
        cell = find_field(table, ref, 1);
        if (cell == 0) { reject_at(frame); return; }
        stabilize_table_slots(frame, table);
        *cell = *source;
        if (source->tag >= LUA55_VALUE_SHORT_STRING) {
            table->barrier_count++;
            frame->heap->barrier_epoch++;
        }
        record_table_slot(frame, 16, (uint32_t)source->tag + 9, source, table, cell,
            key->tag, (uint64_t)ref);
    }
    else {
        reject_at(frame); return;
    }
    lua55_learn_next(frame);
}

STENCIL(lua55_learn_gettabup)(Lua55LearnFrameV1 *frame)
{
    Lua55UpvalueCellV1 *upvalue = &frame->upvalues[UPVALUE_INDEX];
    Lua55ValueV1 *receiver_value = upvalue_value(frame, upvalue);
    Lua55GuestTableV1 *table = learn_table(frame, receiver_value);
    if (table == 0) { reject_at(frame); return; }
    uint32_t base = QUOTE_BASE_HOLE;
    __asm__ volatile ("" : "+r"(base));
    uint32_t ctag = (uint32_t)CONST_TAG_HOLE;
    __asm__ volatile ("" : "+r"(ctag));
    int64_t cint = (int64_t)CONST_INT_HOLE;
    __asm__ volatile ("" : "+r"(cint));
    uintptr_t cref = (uintptr_t)CONST_REF_HOLE;
    __asm__ volatile ("" : "+r"(cref));
    if (ctag == LUA55_VALUE_INTEGER) {
        Lua55ValueV1 *cell;
        if (cint >= 1 && (uint64_t)cint <= table->array_capacity) {
            cell = &table->array_values[cint - 1];
            if (cell->tag > LUA55_VALUE_LONG_STRING) { reject_at(frame); return; }
            record_tabup_slot(frame, 15, (uint32_t)cell->tag + 1, cell, table, cell, upvalue);
            frame->values[TARGET_INDEX] = *cell;
        }
        else {
            Lua55ValueV1 nil_value;
            SET_TAG(&nil_value, LUA55_VALUE_NIL);
            nil_value.payload.reference = 0;
            record_tabup_slot(frame, 15, 8, &nil_value, table, 0, upvalue);
            frame->values[TARGET_INDEX] = nil_value;
        }
    }
    else if (ctag == LUA55_VALUE_SHORT_STRING ||
             ctag == LUA55_VALUE_LONG_STRING) {
        Lua55ValueV1 *cell = find_field(table, cref, 0);
        if (cell == 0) {
            Lua55ValueV1 nil_value;
            SET_TAG(&nil_value, LUA55_VALUE_NIL);
            nil_value.payload.reference = 0;
            record_tabup_slot(frame, 15, 16, &nil_value, table, 0, upvalue);
            frame->values[TARGET_INDEX] = nil_value;
        }
        else {
            if (cell->tag > LUA55_VALUE_LONG_STRING &&
                cell->tag != LUA55_VALUE_CLOSURE && cell->tag != LUA55_VALUE_TABLE) {
                reject_at(frame); return;
            }
            record_tabup_slot(frame, 15,
                cell->tag == LUA55_VALUE_TABLE ? 18 : (uint32_t)cell->tag + 9,
                cell, table, cell, upvalue);
            frame->values[TARGET_INDEX] = *cell;
        }
    }
    else { reject_at(frame); return; }
    lua55_learn_next(frame);
}

STENCIL(lua55_learn_settabup)(Lua55LearnFrameV1 *frame)
{
    Lua55UpvalueCellV1 *upvalue = &frame->upvalues[UPVALUE_INDEX];
    Lua55ValueV1 *receiver_value = upvalue_value(frame, upvalue);
    Lua55ValueV1 *source = &frame->values[SOURCE_INDEX];
    Lua55GuestTableV1 *table = learn_table(frame, receiver_value);
    if (table == 0) { reject_at(frame); return; }
    if (source->tag > LUA55_VALUE_LONG_STRING) { reject_at(frame); return; }
    uint32_t ctag = (uint32_t)CONST_TAG_HOLE;
    __asm__ volatile ("" : "+r"(ctag));
    int64_t cint = (int64_t)CONST_INT_HOLE;
    __asm__ volatile ("" : "+r"(cint));
    uintptr_t cref = (uintptr_t)CONST_REF_HOLE;
    __asm__ volatile ("" : "+r"(cref));
    Lua55ValueV1 *cell;
    if (ctag == LUA55_VALUE_INTEGER) {
        if (cint < 1 || (uint64_t)cint > table->array_capacity) { reject_at(frame); return; }
        cell = &table->array_values[cint - 1];
        stabilize_table_slots(frame, table);
        *cell = *source;
        if (source->tag >= LUA55_VALUE_SHORT_STRING) {
            table->barrier_count++;
            frame->heap->barrier_epoch++;
        }
        record_tabup_slot(frame, 11, (uint32_t)source->tag + 1, source, table, cell, upvalue);
    }
    else if (ctag == LUA55_VALUE_SHORT_STRING ||
             ctag == LUA55_VALUE_LONG_STRING) {
        cell = find_field(table, cref, 1);
        if (cell == 0) { reject_at(frame); return; }
        stabilize_table_slots(frame, table);
        *cell = *source;
        if (source->tag >= LUA55_VALUE_SHORT_STRING) {
            table->barrier_count++;
            frame->heap->barrier_epoch++;
        }
        record_tabup_slot(frame, 11, (uint32_t)source->tag + 9, source, table, cell, upvalue);
    }
    else { reject_at(frame); return; }
    lua55_learn_next(frame);
}

STENCIL(lua55_learn_self)(Lua55LearnFrameV1 *frame)
{
    Lua55ValueV1 *receiver = &frame->values[RECEIVER_INDEX];
    Lua55GuestTableV1 *table = learn_table(frame, receiver);
    if (table == 0) { reject_at(frame); return; }
    uint32_t ctag = (uint32_t)CONST_TAG_HOLE;
    __asm__ volatile ("" : "+r"(ctag));
    uintptr_t cref = (uintptr_t)CONST_REF_HOLE;
    __asm__ volatile ("" : "+r"(cref));
    if (ctag != LUA55_VALUE_SHORT_STRING && ctag != LUA55_VALUE_LONG_STRING) {
        reject_at(frame); return;
    }
    Lua55ValueV1 *cell = find_field(table, cref, 0);
    Lua55ValueV1 nil_value;
    SET_TAG(&nil_value, LUA55_VALUE_NIL);
    nil_value.payload.reference = 0;
    frame->values[OBJECT_TARGET_INDEX] = *receiver;   /* R[A+1] = receiver */
    if (cell == 0) {
        record_table_slot(frame, 20, 16, &nil_value, table, 0,
            ctag, (uint64_t)cref);
        frame->values[TARGET_INDEX] = nil_value;
    }
    else {
        if (cell->tag > LUA55_VALUE_LONG_STRING) { reject_at(frame); return; }
        record_table_slot(frame, 20, (uint32_t)cell->tag + 9, cell, table, cell,
            ctag, (uint64_t)cref);
        frame->values[TARGET_INDEX] = *cell;
    }
    lua55_learn_next(frame);
}

STENCIL(lua55_learn_newtable)(Lua55LearnFrameV1 *frame)
{
    Lua55ValueV1 *target = &frame->values[TARGET_INDEX];
    Lua55RecordingSlotV1 *slot = next_slot(frame);
    uint32_t base = QUOTE_BASE_HOLE;
    __asm__ volatile ("" : "+r"(base));
    slot->quote = base | 1;
    uint32_t array_cap = ARRAY_CAP_HOLE;
    __asm__ volatile ("" : "+r"(array_cap));
    uint32_t field_cap = FIELD_CAP_HOLE;
    __asm__ volatile ("" : "+r"(field_cap));
    Lua55GuestTableV1 *table = new_table(frame, array_cap, field_cap);
    if (table == 0) { reject_at(frame); return; }
    {
        uint32_t index = frame->slot_cursor - 1;
        Lua55TableRecordingV1 *table_slot =
            &((Lua55TableLearnFrameV1 *)frame)->table_slots[index];
        table_slot->expected_storage_generation = table->storage_generation;
        table_slot->expected_collection_epoch = frame->heap->collection_epoch;
        table_slot->expected_reference = (uintptr_t)table;
        table_slot->slot_reference = 0;
        table_slot->expected_metatable = 0;
    }
    SET_TAG(target, LUA55_VALUE_TABLE);
    target->payload.reference = (uintptr_t)table;
    lua55_learn_next(frame);
}

/* ------------------------------------------------------------------ */
/* RESIDUALS: per (opcode leaf, value tag, key kind).                  */

/* key guard: current key matches the recorded tag and value */
#define KEY_GUARD_INT(key, hole) \
    ((key)->tag == LUA55_VALUE_INTEGER && (key)->payload.integer == (int64_t)(hole))
#define KEY_GUARD_STR(key, hole, kind) \
    ((key)->tag == (kind) && (key)->payload.reference == (uintptr_t)(hole))

static Lua55GuestTableV1 *guard_table(
    Lua55LearnFrameV1 *frame, Lua55ValueV1 *receiver)
{
    uintptr_t expected = (uintptr_t)TABLE_REFERENCE;
    Lua55GuestTableV1 *table = (Lua55GuestTableV1 *)expected;
    if (receiver->tag != LUA55_VALUE_TABLE || receiver->payload.reference != expected ||
        frame->heap == 0 || frame->heap->collection_epoch != COLLECTION_EPOCH ||
        table->header.kind != LUA55_OBJECT_TABLE || table->heap != frame->heap ||
        table->storage_generation != STORAGE_GENERATION ||
        table->metatable_reference != 0) return 0;
    return table;
}

/* GETTABLE residual family: table + key + cell guards, then read. */
#define GETTABLE_RESIDUAL(name, key_kind, value_tag, missing)           \
STENCIL(name)(Lua55LearnFrameV1 *frame)                                 \
{                                                                       \
    Lua55ValueV1 *receiver = &frame->values[RECEIVER_INDEX];            \
    Lua55ValueV1 *key = &frame->values[KEY_INDEX];                      \
    Lua55ValueV1 *target = &frame->values[TARGET_INDEX];                \
    Lua55GuestTableV1 *table = guard_table(frame, receiver);            \
    Lua55ValueV1 *cell = (Lua55ValueV1 *)(uintptr_t)SLOT_REFERENCE;     \
    int key_ok = (key_kind) == LUA55_VALUE_INTEGER                      \
        ? KEY_GUARD_INT(key, INT_KEY_HOLE)                              \
        : KEY_GUARD_STR(key, KEY_REF_HOLE, (key_kind));                 \
    if (table == 0 || !key_ok ||                                        \
        (!(missing) && cell->tag != (value_tag))) {                     \
        GUARD_FAILED(frame); return;                                    \
    }                                                                   \
    if (missing) { SET_TAG(target, LUA55_VALUE_NIL); target->payload.reference = 0; } \
    else *target = *cell;                                               \
    lua55_residual_next(frame);                                         \
}

#define GETTABLE_T(name, tag) \
    GETTABLE_RESIDUAL(lua55_residual_gettable_i_##name, LUA55_VALUE_INTEGER, tag, 0)
#define GETTABLE_S_T(name, tag) \
    GETTABLE_RESIDUAL(lua55_residual_gettable_s_##name, LUA55_VALUE_SHORT_STRING, tag, 0)

GETTABLE_T(nil, LUA55_VALUE_NIL) GETTABLE_T(false, LUA55_VALUE_FALSE)
GETTABLE_T(true, LUA55_VALUE_TRUE) GETTABLE_T(integer, LUA55_VALUE_INTEGER)
GETTABLE_T(float, LUA55_VALUE_FLOAT) GETTABLE_T(short_string, LUA55_VALUE_SHORT_STRING)
GETTABLE_T(long_string, LUA55_VALUE_LONG_STRING)
GETTABLE_RESIDUAL(lua55_residual_gettable_i_missing, LUA55_VALUE_INTEGER, LUA55_VALUE_NIL, 1)
GETTABLE_S_T(nil, LUA55_VALUE_NIL) GETTABLE_S_T(false, LUA55_VALUE_FALSE)
GETTABLE_S_T(true, LUA55_VALUE_TRUE) GETTABLE_S_T(integer, LUA55_VALUE_INTEGER)
GETTABLE_S_T(float, LUA55_VALUE_FLOAT) GETTABLE_S_T(short_string, LUA55_VALUE_SHORT_STRING)
GETTABLE_S_T(long_string, LUA55_VALUE_LONG_STRING)
GETTABLE_RESIDUAL(lua55_residual_gettable_s_missing, LUA55_VALUE_SHORT_STRING, LUA55_VALUE_NIL, 1)

/* SETTABLE residual family: table + key + source guards, then write. */
#define SETTABLE_RESIDUAL(name, key_kind, value_tag)                    \
STENCIL(name)(Lua55LearnFrameV1 *frame)                                 \
{                                                                       \
    Lua55ValueV1 *receiver = &frame->values[RECEIVER_INDEX];            \
    Lua55ValueV1 *key = &frame->values[KEY_INDEX];                      \
    Lua55ValueV1 *source = &frame->values[SOURCE_INDEX];                \
    Lua55GuestTableV1 *table = guard_table(frame, receiver);            \
    Lua55ValueV1 *cell = (Lua55ValueV1 *)(uintptr_t)SLOT_REFERENCE;     \
    int key_ok = (key_kind) == LUA55_VALUE_INTEGER                      \
        ? KEY_GUARD_INT(key, INT_KEY_HOLE)                              \
        : KEY_GUARD_STR(key, KEY_REF_HOLE, (key_kind));                 \
    if (table == 0 || !key_ok || source->tag != (value_tag)) {          \
        GUARD_FAILED(frame); return;                                    \
    }                                                                   \
    *cell = *source;                                                    \
    if ((value_tag) >= LUA55_VALUE_SHORT_STRING) {                      \
        table->barrier_count++; frame->heap->barrier_epoch++;           \
    }                                                                   \
    lua55_residual_next(frame);                                         \
}

#define SETTABLE_T(name, tag) \
    SETTABLE_RESIDUAL(lua55_residual_settable_i_##name, LUA55_VALUE_INTEGER, tag)
#define SETTABLE_S_T(name, tag) \
    SETTABLE_RESIDUAL(lua55_residual_settable_s_##name, LUA55_VALUE_SHORT_STRING, tag)

SETTABLE_T(nil, LUA55_VALUE_NIL) SETTABLE_T(false, LUA55_VALUE_FALSE)
SETTABLE_T(true, LUA55_VALUE_TRUE) SETTABLE_T(integer, LUA55_VALUE_INTEGER)
SETTABLE_T(float, LUA55_VALUE_FLOAT) SETTABLE_T(short_string, LUA55_VALUE_SHORT_STRING)
SETTABLE_T(long_string, LUA55_VALUE_LONG_STRING)
SETTABLE_S_T(nil, LUA55_VALUE_NIL) SETTABLE_S_T(false, LUA55_VALUE_FALSE)
SETTABLE_S_T(true, LUA55_VALUE_TRUE) SETTABLE_S_T(integer, LUA55_VALUE_INTEGER)
SETTABLE_S_T(float, LUA55_VALUE_FLOAT) SETTABLE_S_T(short_string, LUA55_VALUE_SHORT_STRING)
SETTABLE_S_T(long_string, LUA55_VALUE_LONG_STRING)

/* GETTABUP/SETTABUP: same bodies with the receiver from the upvalue and
   an upvalue state/generation guard. */
#define TABUP_READ_GUARD(frame)                                         \
    Lua55UpvalueCellV1 *upvalue = &frame->upvalues[UPVALUE_INDEX];      \
    Lua55ValueV1 *receiver = upvalue_value(frame, upvalue);             \
    if (upvalue->state != UPVALUE_STATE_HOLE ||                          \
        upvalue->generation != UPVALUE_GEN_HOLE) {                      \
        GUARD_FAILED(frame); return;                                    \
    }                                                                   \

#define GETTABUP_RESIDUAL(name, key_kind, value_tag, missing)           \
STENCIL(name)(Lua55LearnFrameV1 *frame)                                 \
{                                                                       \
    TABUP_READ_GUARD(frame)                                             \
    Lua55ValueV1 *target = &frame->values[TARGET_INDEX];                \
    Lua55GuestTableV1 *table = guard_table(frame, receiver);            \
    Lua55ValueV1 *cell = (Lua55ValueV1 *)(uintptr_t)SLOT_REFERENCE;     \
    if (table == 0 || (!(missing) && cell->tag != (value_tag))) {       \
        GUARD_FAILED(frame); return;                                    \
    }                                                                   \
    if (missing) { SET_TAG(target, LUA55_VALUE_NIL); target->payload.reference = 0; } \
    else *target = *cell;                                               \
    lua55_residual_next(frame);                                         \
}

#define GTU_T(name, tag) \
    GETTABUP_RESIDUAL(lua55_residual_gettabup_i_##name, LUA55_VALUE_INTEGER, tag, 0)
#define GTU_S_T(name, tag) \
    GETTABUP_RESIDUAL(lua55_residual_gettabup_s_##name, LUA55_VALUE_SHORT_STRING, tag, 0)

GTU_T(nil, LUA55_VALUE_NIL) GTU_T(false, LUA55_VALUE_FALSE)
GTU_T(true, LUA55_VALUE_TRUE) GTU_T(integer, LUA55_VALUE_INTEGER)
GTU_T(float, LUA55_VALUE_FLOAT) GTU_T(short_string, LUA55_VALUE_SHORT_STRING)
GTU_T(long_string, LUA55_VALUE_LONG_STRING)
GETTABUP_RESIDUAL(lua55_residual_gettabup_i_missing, LUA55_VALUE_INTEGER, LUA55_VALUE_NIL, 1)
GTU_S_T(nil, LUA55_VALUE_NIL) GTU_S_T(false, LUA55_VALUE_FALSE)
GTU_S_T(true, LUA55_VALUE_TRUE) GTU_S_T(integer, LUA55_VALUE_INTEGER)
GTU_S_T(float, LUA55_VALUE_FLOAT) GTU_S_T(short_string, LUA55_VALUE_SHORT_STRING)
GTU_S_T(long_string, LUA55_VALUE_LONG_STRING)
GETTABUP_RESIDUAL(lua55_residual_gettabup_s_missing, LUA55_VALUE_SHORT_STRING, LUA55_VALUE_NIL, 1)
GTU_S_T(table, LUA55_VALUE_TABLE)
GETTABUP_RESIDUAL(lua55_residual_gettabup_s_closure, LUA55_VALUE_SHORT_STRING, LUA55_VALUE_CLOSURE, 0)

#define SETTABUP_RESIDUAL(name, key_kind, value_tag)                    \
STENCIL(name)(Lua55LearnFrameV1 *frame)                                 \
{                                                                       \
    TABUP_READ_GUARD(frame)                                             \
    Lua55ValueV1 *source = &frame->values[SOURCE_INDEX];                \
    Lua55GuestTableV1 *table = guard_table(frame, receiver);            \
    Lua55ValueV1 *cell = (Lua55ValueV1 *)(uintptr_t)SLOT_REFERENCE;     \
    if (table == 0 || source->tag != (value_tag)) {                     \
        GUARD_FAILED(frame); return;                                    \
    }                                                                   \
    *cell = *source;                                                    \
    if ((value_tag) >= LUA55_VALUE_SHORT_STRING) {                      \
        table->barrier_count++; frame->heap->barrier_epoch++;           \
    }                                                                   \
    lua55_residual_next(frame);                                         \
}

#define STU_T(name, tag) \
    SETTABUP_RESIDUAL(lua55_residual_settabup_i_##name, LUA55_VALUE_INTEGER, tag)
#define STU_S_T(name, tag) \
    SETTABUP_RESIDUAL(lua55_residual_settabup_s_##name, LUA55_VALUE_SHORT_STRING, tag)

STU_T(nil, LUA55_VALUE_NIL) STU_T(false, LUA55_VALUE_FALSE)
STU_T(true, LUA55_VALUE_TRUE) STU_T(integer, LUA55_VALUE_INTEGER)
STU_T(float, LUA55_VALUE_FLOAT) STU_T(short_string, LUA55_VALUE_SHORT_STRING)
STU_T(long_string, LUA55_VALUE_LONG_STRING)
STU_S_T(nil, LUA55_VALUE_NIL) STU_S_T(false, LUA55_VALUE_FALSE)
STU_S_T(true, LUA55_VALUE_TRUE) STU_S_T(integer, LUA55_VALUE_INTEGER)
STU_S_T(float, LUA55_VALUE_FLOAT) STU_S_T(short_string, LUA55_VALUE_SHORT_STRING)
STU_S_T(long_string, LUA55_VALUE_LONG_STRING)

/* SELF (20): R[A+1] = receiver; R[A] = field. String key only. */
#define SELF_RESIDUAL(name, value_tag, missing)                         \
STENCIL(name)(Lua55LearnFrameV1 *frame)                                 \
{                                                                       \
    Lua55ValueV1 *receiver = &frame->values[RECEIVER_INDEX];            \
    Lua55ValueV1 *target = &frame->values[TARGET_INDEX];                \
    Lua55ValueV1 *object = &frame->values[OBJECT_TARGET_INDEX];         \
    Lua55GuestTableV1 *table = guard_table(frame, receiver);            \
    Lua55ValueV1 *cell = (Lua55ValueV1 *)(uintptr_t)SLOT_REFERENCE;     \
    if (table == 0 || (!(missing) && cell->tag != (value_tag))) {       \
        GUARD_FAILED(frame); return;                                    \
    }                                                                   \
    *object = *receiver;                                                \
    if (missing) { SET_TAG(target, LUA55_VALUE_NIL); target->payload.reference = 0; } \
    else *target = *cell;                                               \
    lua55_residual_next(frame);                                         \
}

SELF_RESIDUAL(lua55_residual_self_nil, LUA55_VALUE_NIL, 0)
SELF_RESIDUAL(lua55_residual_self_false, LUA55_VALUE_FALSE, 0)
SELF_RESIDUAL(lua55_residual_self_true, LUA55_VALUE_TRUE, 0)
SELF_RESIDUAL(lua55_residual_self_integer, LUA55_VALUE_INTEGER, 0)
SELF_RESIDUAL(lua55_residual_self_float, LUA55_VALUE_FLOAT, 0)
SELF_RESIDUAL(lua55_residual_self_short_string, LUA55_VALUE_SHORT_STRING, 0)
SELF_RESIDUAL(lua55_residual_self_long_string, LUA55_VALUE_LONG_STRING, 0)
SELF_RESIDUAL(lua55_residual_self_missing, LUA55_VALUE_NIL, 1)

/* NEWTABLE (19): bump a fresh table each run. */
STENCIL(lua55_residual_newtable)(Lua55LearnFrameV1 *frame)
{
    Lua55ValueV1 *target = &frame->values[TARGET_INDEX];
    uint32_t array_cap = ARRAY_CAP_HOLE;
    __asm__ volatile ("" : "+r"(array_cap));
    uint32_t field_cap = FIELD_CAP_HOLE;
    __asm__ volatile ("" : "+r"(field_cap));
    Lua55GuestTableV1 *table = new_table(frame, array_cap, field_cap);
    if (table == 0) { GUARD_FAILED(frame); return; }
    SET_TAG(target, LUA55_VALUE_TABLE);
    target->payload.reference = (uintptr_t)table;
    lua55_residual_next(frame);
}
