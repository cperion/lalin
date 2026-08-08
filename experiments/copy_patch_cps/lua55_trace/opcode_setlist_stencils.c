#include "opcode_value_v1.h"

/* Batch 8: SETLIST (78) — table literal filling.
   Stock (lvm.c): R[A][C+i] := R[A+i] for 1 <= i <= B. The table is R[A];
   the elements R[A+1..A+B]. B == 0 (the "up to top" form) and any write
   beyond the fixed array capacity reject (host resizes). The k flag folds
   the following EXTRAARG's high array bits into C. The learner writes the
   elements once, records the table identity + storage generation, and the
   residual re-writes the CURRENT register values each run under the table
   guards (no recorded element assumptions — the write is self-consistent). */

#define SETLIST_BASE_HOLE UINT32_C(0x999)         /* register A (table base) */
#define SETLIST_COUNT_HOLE UINT32_C(0x0c0d0e0f)   /* B */
#define SETLIST_KEY_HOLE UINT32_C(0x1c1d1e1f)     /* C */
#define QUOTE_BASE_HOLE UINT32_C(0x0f1e2d3c)
#define RESUME_PC UINT32_C(0x66778899)
#define TABLE_REFERENCE UINT64_C(0x3141592653589793)
#define STORAGE_GENERATION UINT32_C(0x5a6b7c8d)
#define COLLECTION_EPOCH UINT32_C(0x4a5b6c7d)

#define GUARD_FAILED(frame) do {            \
    (frame)->resume_pc = RESUME_PC;          \
    (frame)->status = LUA55_GUARD_FAILED;    \
} while (0)

#define REJECT(frame) do {                  \
    (frame)->resume_pc = RESUME_PC;          \
    (frame)->status = LUA55_REJECTED;        \
} while (0)

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

static void record_setlist_slot(
    Lua55LearnFrameV1 *frame, Lua55GuestTableV1 *table)
{
    uint32_t index = frame->slot_cursor;
    Lua55RecordingSlotV1 *slot = next_slot(frame);
    Lua55TableRecordingV1 *table_slot =
        &((Lua55TableLearnFrameV1 *)frame)->table_slots[index];
    slot->quote = LUA55_QUOTE(78, 1);
    table_slot->expected_storage_generation = table->storage_generation;
    table_slot->expected_collection_epoch = frame->heap->collection_epoch;
    table_slot->expected_reference = (uintptr_t)table;
    table_slot->slot_reference = 0;
    table_slot->expected_metatable = table->metatable_reference;
}

/* write elements 1..n of R[base+1..] into the table at keys last+1..last+n */
static void write_elements(
    Lua55LearnFrameV1 *frame, Lua55GuestTableV1 *table,
    int base, int n, int last)
{
    int i;
    for (i = 1; i <= n; i++) {
        Lua55ValueV1 *cell = &table->array_values[last + i - 1];
        Lua55ValueV1 *val = &frame->values[base + i];
        *cell = *val;
        if (val->tag >= LUA55_VALUE_SHORT_STRING) {
            table->barrier_count++;
            frame->heap->barrier_epoch++;
        }
    }
}

STENCIL(lua55_learn_setlist)(Lua55LearnFrameV1 *frame)
{
    int base = (int)SETLIST_BASE_HOLE;
    __asm__ volatile ("" : "+r"(base));
    int n = (int)SETLIST_COUNT_HOLE;
    __asm__ volatile ("" : "+r"(n));
    int last = (int)SETLIST_KEY_HOLE;
    __asm__ volatile ("" : "+r"(last));
    Lua55GuestTableV1 *table = learn_table(frame, &frame->values[base]);
    if (table == 0) { REJECT(frame); return; }
    if (n == 0) { REJECT(frame); return; }                    /* up-to-top form */
    if (last + n > (int)table->array_capacity) { REJECT(frame); return; } /* fixed storage */
    {
        int i;
        for (i = 1; i <= n; i++) {
            Lua55ValueV1 *val = &frame->values[base + i];
            if (val->tag > LUA55_VALUE_LONG_STRING) { REJECT(frame); return; }
        }
    }
    write_elements(frame, table, base, n, last);
    record_setlist_slot(frame, table);
    lua55_learn_next(frame);
}

STENCIL(lua55_residual_setlist)(Lua55LearnFrameV1 *frame)
{
    int base = (int)SETLIST_BASE_HOLE;
    __asm__ volatile ("" : "+r"(base));
    int n = (int)SETLIST_COUNT_HOLE;
    __asm__ volatile ("" : "+r"(n));
    int last = (int)SETLIST_KEY_HOLE;
    __asm__ volatile ("" : "+r"(last));
    Lua55ValueV1 *receiver = &frame->values[base];
    uintptr_t expected = (uintptr_t)TABLE_REFERENCE;
    Lua55GuestTableV1 *table = (Lua55GuestTableV1 *)expected;
    if (receiver->tag != LUA55_VALUE_TABLE || receiver->payload.reference != expected ||
        frame->heap == 0 || frame->heap->collection_epoch != COLLECTION_EPOCH ||
        table->header.kind != LUA55_OBJECT_TABLE || table->heap != frame->heap ||
        table->storage_generation != STORAGE_GENERATION ||
        table->metatable_reference != 0) {
        GUARD_FAILED(frame); return;
    }
    write_elements(frame, table, base, n, last);
    lua55_residual_next(frame);
}
