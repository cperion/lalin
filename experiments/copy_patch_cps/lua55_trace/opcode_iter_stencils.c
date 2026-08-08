#include "opcode_value_v1.h"

/* Batch 14: native iterators — next and ipairs-iter over the closed
   guest tables. These are the builtin iterator functions behind the
   generic for: `next(t, k)` walks the array part (keys 1..capacity,
   skipping nil gaps) then the field part; `ipairs(t)`'s iterator
   increments the index and reads the array (nil → done). The stencils
   take (t, k) in R0/R1 and produce (key, value) in R2/R3 (or R2 = nil
   when exhausted). The host invokes them from the TFORCALL dispatch when
   the iterator is the matching builtin marker (Lua55GuestBuiltinV1). */

#define TABLE_INDEX 0
#define KEY_INDEX 1
#define RESULT_KEY_INDEX 2
#define RESULT_VALUE_INDEX 3
#define QUOTE_BASE_HOLE UINT32_C(0x0f1e2d3c)
#define RESUME_PC UINT32_C(0x66778899)

#define REJECT(frame) do {                  \
    (frame)->resume_pc = RESUME_PC;          \
    (frame)->status = LUA55_REJECTED;        \
} while (0)

static Lua55GuestTableV1 *iter_table(Lua55LearnFrameV1 *frame)
{
    Lua55ValueV1 *table = &frame->values[TABLE_INDEX];
    Lua55GuestTableV1 *t;
    if (table->tag != LUA55_VALUE_TABLE || frame->heap == 0) return 0;
    t = (Lua55GuestTableV1 *)table->payload.reference;
    if (t == 0 || t->header.kind != LUA55_OBJECT_TABLE ||
        t->heap != frame->heap || t->metatable_reference != 0) return 0;
    return t;
}

static void set_nil(Lua55ValueV1 *value)
{
    SET_TAG(value, LUA55_VALUE_NIL);
    value->payload.reference = 0;
}

static void set_integer_value(Lua55ValueV1 *value, int64_t n)
{
    SET_TAG(value, LUA55_VALUE_INTEGER);
    value->payload.integer = n;
}

/* return the key/value of the first occupied field starting at 'start' */
static int next_field(
    Lua55LearnFrameV1 *frame, Lua55GuestTableV1 *t, uint32_t start,
    Lua55ValueV1 *rkey, Lua55ValueV1 *rval)
{
    uint32_t i;
    for (i = start; i < t->field_capacity; i++) {
        Lua55GuestFieldV1 *field = &t->field_values[i];
        if (!field->occupied) continue;
        Lua55GuestStringV1 *s = (Lua55GuestStringV1 *)field->key_reference;
        SET_TAG(rkey, (s != 0 && s->header.kind == LUA55_OBJECT_LONG_STRING)
            ? LUA55_VALUE_LONG_STRING : LUA55_VALUE_SHORT_STRING);
        rkey->payload.reference = field->key_reference;
        *rval = field->value;
        return 1;
    }
    return 0;
}

STENCIL(lua55_learn_next_iter)(Lua55LearnFrameV1 *frame)
{
    Lua55ValueV1 *key = &frame->values[KEY_INDEX];
    Lua55ValueV1 *rkey = &frame->values[RESULT_KEY_INDEX];
    Lua55ValueV1 *rval = &frame->values[RESULT_VALUE_INDEX];
    Lua55RecordingSlotV1 *slot = next_slot(frame);
    uint32_t base = QUOTE_BASE_HOLE;
    __asm__ volatile ("" : "+r"(base));
    slot->quote = base | 1;
    Lua55GuestTableV1 *t = iter_table(frame);
    if (t == 0) { REJECT(frame); return; }
    uint32_t i;
    if (key->tag == LUA55_VALUE_NIL) {
        for (i = 1; i <= t->array_capacity; i++) {
            if (t->array_values[i - 1].tag == LUA55_VALUE_NIL) continue;
            set_integer_value(rkey, (int64_t)i);
            *rval = t->array_values[i - 1];
            lua55_learn_next(frame); return;
        }
        if (!next_field(frame, t, 0, rkey, rval)) set_nil(rkey);
        lua55_learn_next(frame); return;
    }
    else if (key->tag == LUA55_VALUE_INTEGER) {
        int64_t n = key->payload.integer;
        for (i = (uint32_t)(n + 1); (int64_t)i <= (int64_t)t->array_capacity; i++) {
            if (t->array_values[i - 1].tag == LUA55_VALUE_NIL) continue;
            set_integer_value(rkey, (int64_t)i);
            *rval = t->array_values[i - 1];
            lua55_learn_next(frame); return;
        }
        if (!next_field(frame, t, 0, rkey, rval)) set_nil(rkey);
        lua55_learn_next(frame); return;
    }
    else if (key->tag == LUA55_VALUE_SHORT_STRING ||
             key->tag == LUA55_VALUE_LONG_STRING) {
        uintptr_t ref = key->payload.reference;
        uint32_t found = 0;
        for (i = 0; i < t->field_capacity; i++) {
            if (t->field_values[i].occupied &&
                t->field_values[i].key_reference == ref) { found = i + 1; break; }
        }
        if (found == 0 || !next_field(frame, t, found, rkey, rval)) set_nil(rkey);
        lua55_learn_next(frame); return;
    }
    REJECT(frame);
}

STENCIL(lua55_residual_next_iter)(Lua55LearnFrameV1 *frame)
{
    Lua55ValueV1 *key = &frame->values[KEY_INDEX];
    Lua55ValueV1 *rkey = &frame->values[RESULT_KEY_INDEX];
    Lua55ValueV1 *rval = &frame->values[RESULT_VALUE_INDEX];
    Lua55GuestTableV1 *t = iter_table(frame);
    if (t == 0) {
        frame->resume_pc = RESUME_PC;
        frame->status = LUA55_GUARD_FAILED;
        return;
    }
    uint32_t i;
    if (key->tag == LUA55_VALUE_NIL) {
        for (i = 1; i <= t->array_capacity; i++) {
            if (t->array_values[i - 1].tag == LUA55_VALUE_NIL) continue;
            set_integer_value(rkey, (int64_t)i);
            *rval = t->array_values[i - 1];
            lua55_residual_next(frame); return;
        }
        if (!next_field(frame, t, 0, rkey, rval)) set_nil(rkey);
        lua55_residual_next(frame); return;
    }
    else if (key->tag == LUA55_VALUE_INTEGER) {
        int64_t n = key->payload.integer;
        for (i = (uint32_t)(n + 1); (int64_t)i <= (int64_t)t->array_capacity; i++) {
            if (t->array_values[i - 1].tag == LUA55_VALUE_NIL) continue;
            set_integer_value(rkey, (int64_t)i);
            *rval = t->array_values[i - 1];
            lua55_residual_next(frame); return;
        }
        if (!next_field(frame, t, 0, rkey, rval)) set_nil(rkey);
        lua55_residual_next(frame); return;
    }
    else if (key->tag == LUA55_VALUE_SHORT_STRING ||
             key->tag == LUA55_VALUE_LONG_STRING) {
        uintptr_t ref = key->payload.reference;
        uint32_t found = 0;
        for (i = 0; i < t->field_capacity; i++) {
            if (t->field_values[i].occupied &&
                t->field_values[i].key_reference == ref) { found = i + 1; break; }
        }
        if (found == 0 || !next_field(frame, t, found, rkey, rval)) set_nil(rkey);
        lua55_residual_next(frame); return;
    }
    frame->resume_pc = RESUME_PC;
    frame->status = LUA55_GUARD_FAILED;
}

STENCIL(lua55_learn_ipairs_iter)(Lua55LearnFrameV1 *frame)
{
    Lua55ValueV1 *key = &frame->values[KEY_INDEX];
    Lua55ValueV1 *rkey = &frame->values[RESULT_KEY_INDEX];
    Lua55ValueV1 *rval = &frame->values[RESULT_VALUE_INDEX];
    Lua55RecordingSlotV1 *slot = next_slot(frame);
    uint32_t base = QUOTE_BASE_HOLE;
    __asm__ volatile ("" : "+r"(base));
    slot->quote = base | 1;
    Lua55GuestTableV1 *t = iter_table(frame);
    if (t == 0) { REJECT(frame); return; }
    if (key->tag != LUA55_VALUE_INTEGER) { REJECT(frame); return; }
    int64_t n = key->payload.integer + 1;
    if (n >= 1 && (uint64_t)n <= t->array_capacity &&
        t->array_values[n - 1].tag != LUA55_VALUE_NIL) {
        set_integer_value(rkey, n);
        *rval = t->array_values[n - 1];
    }
    else {
        set_nil(rkey);
    }
    lua55_learn_next(frame);
}

STENCIL(lua55_residual_ipairs_iter)(Lua55LearnFrameV1 *frame)
{
    Lua55ValueV1 *key = &frame->values[KEY_INDEX];
    Lua55ValueV1 *rkey = &frame->values[RESULT_KEY_INDEX];
    Lua55ValueV1 *rval = &frame->values[RESULT_VALUE_INDEX];
    Lua55GuestTableV1 *t = iter_table(frame);
    if (t == 0 || key->tag != LUA55_VALUE_INTEGER) {
        frame->resume_pc = RESUME_PC;
        frame->status = LUA55_GUARD_FAILED;
        return;
    }
    int64_t n = key->payload.integer + 1;
    if (n >= 1 && (uint64_t)n <= t->array_capacity &&
        t->array_values[n - 1].tag != LUA55_VALUE_NIL) {
        set_integer_value(rkey, n);
        *rval = t->array_values[n - 1];
    }
    else {
        set_nil(rkey);
    }
    lua55_residual_next(frame);
}
