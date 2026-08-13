#ifndef LUA55_OPCODE_VALUE_V1_H
#define LUA55_OPCODE_VALUE_V1_H

#include <stdint.h>
#include <string.h>
#include "opcode_value_tags.h"
enum {
    LUA55_QUOTE_REJECTED = 0,
    LUA55_QUOTE_MOVE_NIL = LUA55_QUOTE(0, 1),
    LUA55_QUOTE_MOVE_FALSE = LUA55_QUOTE(0, 2),
    LUA55_QUOTE_MOVE_TRUE = LUA55_QUOTE(0, 3),
    LUA55_QUOTE_MOVE_INTEGER = LUA55_QUOTE(0, 4),
    LUA55_QUOTE_MOVE_FLOAT = LUA55_QUOTE(0, 5),
    LUA55_QUOTE_MOVE_SHORT_STRING = LUA55_QUOTE(0, 6),
    LUA55_QUOTE_MOVE_LONG_STRING = LUA55_QUOTE(0, 7),
    LUA55_QUOTE_LOADI = LUA55_QUOTE(1, 1),
    LUA55_QUOTE_LOADF = LUA55_QUOTE(2, 1),
    LUA55_QUOTE_LOADK_NIL = LUA55_QUOTE(3, 1),
    LUA55_QUOTE_LOADK_FALSE = LUA55_QUOTE(3, 2),
    LUA55_QUOTE_LOADK_TRUE = LUA55_QUOTE(3, 3),
    LUA55_QUOTE_LOADK_INTEGER = LUA55_QUOTE(3, 4),
    LUA55_QUOTE_LOADK_FLOAT = LUA55_QUOTE(3, 5),
    LUA55_QUOTE_LOADK_SHORT_STRING = LUA55_QUOTE(3, 6),
    LUA55_QUOTE_LOADK_LONG_STRING = LUA55_QUOTE(3, 7),
    LUA55_QUOTE_LOADKX_NIL = LUA55_QUOTE(4, 1),
    LUA55_QUOTE_LOADKX_FALSE = LUA55_QUOTE(4, 2),
    LUA55_QUOTE_LOADKX_TRUE = LUA55_QUOTE(4, 3),
    LUA55_QUOTE_LOADKX_INTEGER = LUA55_QUOTE(4, 4),
    LUA55_QUOTE_LOADKX_FLOAT = LUA55_QUOTE(4, 5),
    LUA55_QUOTE_LOADKX_SHORT_STRING = LUA55_QUOTE(4, 6),
    LUA55_QUOTE_LOADKX_LONG_STRING = LUA55_QUOTE(4, 7),
    LUA55_QUOTE_LOADFALSE = LUA55_QUOTE(5, 1),
    LUA55_QUOTE_LFALSESKIP = LUA55_QUOTE(6, 1),
    LUA55_QUOTE_LOADTRUE = LUA55_QUOTE(7, 1),
    LUA55_QUOTE_LOADNIL_SPAN = LUA55_QUOTE(8, 1),
    LUA55_QUOTE_GETUPVAL_OPEN_NIL = LUA55_QUOTE(9, 1),
    LUA55_QUOTE_GETUPVAL_OPEN_FALSE = LUA55_QUOTE(9, 2),
    LUA55_QUOTE_GETUPVAL_OPEN_TRUE = LUA55_QUOTE(9, 3),
    LUA55_QUOTE_GETUPVAL_OPEN_INTEGER = LUA55_QUOTE(9, 4),
    LUA55_QUOTE_GETUPVAL_OPEN_FLOAT = LUA55_QUOTE(9, 5),
    LUA55_QUOTE_GETUPVAL_CLOSED_NIL = LUA55_QUOTE(9, 6),
    LUA55_QUOTE_GETUPVAL_CLOSED_FALSE = LUA55_QUOTE(9, 7),
    LUA55_QUOTE_GETUPVAL_CLOSED_TRUE = LUA55_QUOTE(9, 8),
    LUA55_QUOTE_GETUPVAL_CLOSED_INTEGER = LUA55_QUOTE(9, 9),
    LUA55_QUOTE_GETUPVAL_CLOSED_FLOAT = LUA55_QUOTE(9, 10),
    LUA55_QUOTE_GETUPVAL_OPEN_CLOSURE = LUA55_QUOTE(9, 11),
    LUA55_QUOTE_GETUPVAL_CLOSED_CLOSURE = LUA55_QUOTE(9, 12),
    LUA55_QUOTE_SETUPVAL_OPEN_NIL = LUA55_QUOTE(10, 1),
    LUA55_QUOTE_SETUPVAL_OPEN_FALSE = LUA55_QUOTE(10, 2),
    LUA55_QUOTE_SETUPVAL_OPEN_TRUE = LUA55_QUOTE(10, 3),
    LUA55_QUOTE_SETUPVAL_OPEN_INTEGER = LUA55_QUOTE(10, 4),
    LUA55_QUOTE_SETUPVAL_OPEN_FLOAT = LUA55_QUOTE(10, 5),
    LUA55_QUOTE_SETUPVAL_CLOSED_NIL = LUA55_QUOTE(10, 6),
    LUA55_QUOTE_SETUPVAL_CLOSED_FALSE = LUA55_QUOTE(10, 7),
    LUA55_QUOTE_SETUPVAL_CLOSED_TRUE = LUA55_QUOTE(10, 8),
    LUA55_QUOTE_SETUPVAL_CLOSED_INTEGER = LUA55_QUOTE(10, 9),
    LUA55_QUOTE_SETUPVAL_CLOSED_FLOAT = LUA55_QUOTE(10, 10),
};

enum {
    LUA55_EXECUTING = 0,
    LUA55_COMPLETED = 1,
    LUA55_GUARD_FAILED = 2,
    LUA55_REJECTED = 3,
};

/* upvalue states and object kinds moved to opcode_value_tags.h */

typedef union Lua55ValuePayloadV1 {
    int64_t integer;
    double floating;
    uintptr_t reference;
} Lua55ValuePayloadV1;

typedef struct Lua55ValueV1 {
    uint32_t tag;
    uint32_t reserved;
    Lua55ValuePayloadV1 payload;
} Lua55ValueV1;

/* object kinds moved to opcode_value_tags.h */

typedef struct Lua55GuestObjectHeaderV1 {
    uint32_t kind;
    uint32_t generation;
} Lua55GuestObjectHeaderV1;

typedef struct Lua55GuestStringV1 {
    Lua55GuestObjectHeaderV1 header;
    uint32_t length;
    uint32_t hash;
    const uint8_t *bytes;
} Lua55GuestStringV1;

typedef struct Lua55GuestHeapV1 {
    uint32_t generation;
    uint32_t collection_epoch;
    uint32_t object_count;
    uint32_t barrier_epoch;
    /* native table bump region (NEWTABLE): non-moving objects allocated by
       the stencils; collection is out of scope for the closed subset. */
    uintptr_t table_region;
    uintptr_t table_region_end;
    uintptr_t table_next;
} Lua55GuestHeapV1;

typedef struct Lua55GuestFieldV1 {
    uintptr_t key_reference;
    Lua55ValueV1 value;
    uint32_t occupied;
    uint32_t reserved;
} Lua55GuestFieldV1;

typedef struct Lua55GuestTableV1 {
    Lua55GuestObjectHeaderV1 header;
    uint32_t storage_generation;
    uint32_t array_capacity;
    uint32_t field_capacity;
    uint32_t barrier_count;
    uintptr_t metatable_reference;
    Lua55ValueV1 *array_values;
    Lua55GuestFieldV1 *field_values;
    Lua55GuestHeapV1 *heap;
    uint32_t site_id;            /* shared guest layout: NEWTABLE site identity (V2 learning) */
    uint32_t learn_reserved;
} Lua55GuestTableV1;

typedef struct Lua55RecordingSlotV1 {
    uint32_t quote;
    uint32_t expected_tag;         /* the value's tag (cell check) */
    uint32_t expected_state;       /* generic-table: the runtime key's tag */
    uint32_t expected_generation;
    uint64_t key_bits;             /* generic-table: the recorded key value */
} Lua55RecordingSlotV1;

typedef struct Lua55TableRecordingV1 {
    uint32_t expected_storage_generation;
    uint32_t expected_collection_epoch;
    uintptr_t expected_reference;
    uintptr_t slot_reference;
    uintptr_t expected_metatable;
} Lua55TableRecordingV1;

typedef struct Lua55UpvalueCellV1 {
    Lua55ValueV1 *open_slot;
    Lua55ValueV1 closed_value;
    uint32_t state;
    uint32_t generation;
} Lua55UpvalueCellV1;

typedef struct Lua55GuestBuiltinV1 {
    Lua55GuestObjectHeaderV1 header;
    uint32_t builtin_id;   /* 1=next 2=ipairs-iter 3=pairs 4=ipairs */
} Lua55GuestBuiltinV1;

typedef struct Lua55GuestClosureV1 {
    Lua55GuestObjectHeaderV1 header;
    uint32_t proto_index;
    uint32_t upvalue_count;
    uint32_t maxstacksize;   /* the callee frame size (native call transfer) */
    uint32_t numparams;
    uint32_t is_vararg;
    Lua55UpvalueCellV1 cells[];   /* flexible array */
} Lua55GuestClosureV1;

typedef struct Lua55LearnFrameV1 Lua55LearnFrameV1;
typedef void (*Lua55OpcodeEntryV1)(Lua55LearnFrameV1 *);

typedef struct Lua55LearnFrameV1 {
    Lua55ValueV1 *values;
    Lua55RecordingSlotV1 *slots;
    Lua55UpvalueCellV1 *upvalues;
    Lua55GuestHeapV1 *heap;
    uint32_t value_count;
    uint32_t slot_count;
    uint32_t slot_cursor;
    uint32_t resume_pc;
    uint32_t status;
    uint32_t upvalue_count;
    uint32_t vararg_count;   /* extra args beyond numparams (host-set) */
    /* native call transfer (the dest chain) */
    struct Lua55LearnFrameV1 *dest_frame;
    uint32_t dest_base;
    int32_t dest_count;       /* -1 = all results */
    uint32_t top;             /* the current register top (CALL B=0) */
    uint32_t result_count;    /* the RETURN's actual result count */
    Lua55OpcodeEntryV1 *function_table;   /* native entry per proto index */
} Lua55LearnFrameV1;

typedef struct Lua55TableLearnFrameV1 {
    Lua55LearnFrameV1 base;
    Lua55TableRecordingV1 *table_slots;
} Lua55TableLearnFrameV1;

typedef void Lua55OpcodeExitV1(Lua55LearnFrameV1 *);
extern Lua55OpcodeExitV1 lua55_learn_next;
extern Lua55OpcodeExitV1 lua55_residual_next;

#define STENCIL(name)                                                           \
    __attribute__((section(".text." #name), aligned(1), noinline, noclone, used)) \
    void name

#define TARGET_INDEX UINT32_C(0x111)
#define SOURCE_INDEX UINT32_C(0x222)
#define UPVALUE_INDEX UINT32_C(0x333)
#define RESUME_PC UINT32_C(0x66778899)
#define SPAN_COUNT UINT32_C(0x777)
#define INTEGER_BITS UINT64_C(0x1122334455667788)
#define FLOAT_BITS UINT64_C(0x8877665544332211)

static inline Lua55RecordingSlotV1 *next_slot(Lua55LearnFrameV1 *frame)
{
    return &frame->slots[frame->slot_cursor++];
}

#define RECORD_FIXED(frame, quote_id) do {         \
    Lua55RecordingSlotV1 *slot = next_slot(frame); \
    slot->quote = (quote_id);                       \
} while (0)

/* SET_TAG moved to opcode_value_tags.h */

#endif
