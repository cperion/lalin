#ifndef LUA55_OPCODE_VALUE_V2_H
#define LUA55_OPCODE_VALUE_V2_H

#include <stdint.h>
#include <stddef.h>
#include "opcode_value_tags.h"

/* Native CPS Frame V2: the standalone physical vocabulary of the native
   runner. This header is self-contained: it shares only the neutral scalar
   tags with the legacy generation and contains no V1 frame, heap, closure,
   or ownership type. See NATIVE_CPS_V2_COMPLETE_MIGRATION_DESIGN.md. */

/* ---- boundary outcome discriminants ---------------------------------- */
enum {
    LUA55_V2_OUTCOME_EXECUTING = 0,
    LUA55_V2_OUTCOME_RETURNED = 1,
    LUA55_V2_OUTCOME_HOST_CALL = 2,
    LUA55_V2_OUTCOME_HOST_TAIL_CALL = 3,
    LUA55_V2_OUTCOME_STACK_OVERFLOW = 4,
    LUA55_V2_OUTCOME_VALUE_OVERFLOW = 5,
    LUA55_V2_OUTCOME_HEAP_OVERFLOW = 6,
    LUA55_V2_OUTCOME_GUEST_ERROR = 7,
    LUA55_V2_OUTCOME_REJECTED = 8,
};

/* closed rejection kinds */
enum {
    LUA55_V2_REJECT_UNSUPPORTED_OPCODE = 1,
    LUA55_V2_REJECT_UNSUPPORTED_METAMETHOD = 2,
    LUA55_V2_REJECT_INVALID_OBJECT = 3,
    LUA55_V2_REJECT_INVALID_BYTECODE = 4,
    LUA55_V2_REJECT_UNSUPPORTED_HELPER = 5,
    LUA55_V2_REJECT_RELEASED_OWNER = 6,
    LUA55_V2_REJECT_UNSUPPORTED_CALLEE = 7,
    LUA55_V2_REJECT_STEP_ZERO = 8,
    LUA55_V2_REJECT_SPECIALIZATION_MISMATCH = 9,
};

/* ---- guest values and objects (V2-owned physical layouts) ------------- */

typedef union Lua55ValuePayloadV2 {
    int64_t integer;
    double floating;
    uintptr_t reference;
} Lua55ValuePayloadV2;

typedef struct Lua55ValueV2 {
    uint32_t tag;
    uint32_t reserved;
    Lua55ValuePayloadV2 payload;
} Lua55ValueV2;

typedef struct Lua55GuestObjectHeaderV2 {
    uint32_t kind;
    uint32_t generation;
} Lua55GuestObjectHeaderV2;

typedef struct Lua55GuestStringV2 {
    Lua55GuestObjectHeaderV2 header;
    uint32_t length;
    uint32_t hash;
    const uint8_t *bytes;
} Lua55GuestStringV2;

typedef struct Lua55GuestHeapV2 {
    uint32_t generation;
    uint32_t collection_epoch;
    uint32_t object_count;
    uint32_t barrier_epoch;
    uintptr_t table_region;
    uintptr_t table_region_end;
    uintptr_t table_next;
} Lua55GuestHeapV2;

typedef struct Lua55GuestFieldV2 {
    uintptr_t key_reference;
    Lua55ValueV2 value;
    uint32_t occupied;
    uint32_t reserved;
} Lua55GuestFieldV2;

typedef struct Lua55GuestTableV2 {
    Lua55GuestObjectHeaderV2 header;
    uint32_t storage_generation;
    uint32_t array_capacity;
    uint32_t field_capacity;
    uint32_t barrier_count;
    uintptr_t metatable_reference;
    Lua55ValueV2 *array_values;
    Lua55GuestFieldV2 *field_values;
    struct Lua55GuestHeapV2 *heap;
    uint32_t site_id;            /* NEWTABLE allocation-site identity for capacity learning */
    uint32_t learn_reserved;
} Lua55GuestTableV2;

typedef struct Lua55GuestBuiltinV2 {
    Lua55GuestObjectHeaderV2 header;
    uint32_t builtin_id;   /* 1=next 2=ipairs-iter 3=pairs 4=ipairs, then host ids */
} Lua55GuestBuiltinV2;

/* ---- shared upvalue cells and closures -------------------------------- */

typedef struct Lua55UpvalueCellV2 {
    Lua55ValueV2 *open_slot;
    Lua55ValueV2 closed_value;
    struct Lua55UpvalueCellV2 *next_open;
    uint32_t state;
    uint32_t generation;
} Lua55UpvalueCellV2;

typedef struct Lua55NativeClosureV2 {
    Lua55GuestObjectHeaderV2 header;
    uint32_t proto_index;
    uint32_t upvalue_count;
    Lua55UpvalueCellV2 *cells[];   /* shared cell pointers (no per-call copy) */
} Lua55NativeClosureV2;

/* ---- frames, descriptors, links -------------------------------------- */

typedef struct Lua55NativeFrameV2 Lua55NativeFrameV2;
typedef void (*Lua55NativeEntryV2)(Lua55NativeFrameV2 *);

typedef struct Lua55NativeFunctionDescriptorV2 {
    Lua55NativeEntryV2 entry;
    uint32_t maxstacksize;
    uint32_t numparams;
    uint32_t is_vararg;
    uint32_t upvalue_count;
    uint32_t tbc_capacity;
    uint32_t value_capacity;   /* maxstack + bounded open-result slack */
} Lua55NativeFunctionDescriptorV2;

typedef struct Lua55NativeReturnLinkV2 {
    Lua55NativeEntryV2 entry;
    Lua55NativeFrameV2 *subject;
} Lua55NativeReturnLinkV2;

typedef struct Lua55NativeResultSinkV2 {
    Lua55ValueV2 *values;
    uint32_t *top;
    uint32_t base;
    int32_t count;          /* -1 means all actual results */
    uint32_t capacity;      /* destination value capacity (base+count bound) */
} Lua55NativeResultSinkV2;

typedef struct Lua55TbcNodeV2 {
    uint32_t register_index;
    uint32_t state;          /* 0 none, 1 to-be-closed, 2 closed */
    Lua55ValueV2 value;
} Lua55TbcNodeV2;

/* ---- family-specific learning products (separate learning image) ------- */
/* One slot per learnable occurrence / NEWTABLE site. Learners write these
   facts during the separate first invocation; Lua staging reads them and
   selects exact residual leaves for the retained image. */
typedef struct Lua55TableLearnSlotV2 {
    uint32_t key_tag;            /* 0 unseen, 3 int, 5|6 string, 0xFFFFFFFF conflict */
    uint32_t value_tag;          /* observed stored value tag (unused for reg copies) */
    uint64_t max_array_index;    /* observed high-water array key for the NEWTABLE site */
    uint32_t max_field_count;    /* observed high-water field count for the NEWTABLE site */
    uint32_t seen;
    uint32_t field_slot;          /* exact zero-based field slot when found */
    uint32_t field_layout_capacity; /* field-vector layout fact */
    uint32_t field_state;         /* 0 unseen, 1 found, 2 missing, 3 conflict */
    uint32_t field_site_id;       /* owning NEWTABLE site, or zero */
} Lua55TableLearnSlotV2;

/* ---- boundary outcome: discriminant + exact union --------------------- */

typedef struct Lua55HostCallPayloadV2 {
    Lua55NativeEntryV2 resume_entry;
    uint32_t a;
    uint32_t b;
    uint32_t c;
    uint32_t pc;
    uint32_t host_id;        /* resolved by the Lua driver from the callee cell */
    uint32_t reserved;
} Lua55HostCallPayloadV2;

typedef struct Lua55HostTailCallPayloadV2 {
    Lua55NativeEntryV2 tail_return_entry;
    uint32_t a;
    uint32_t b;
    uint32_t pc;
    uint32_t host_id;
} Lua55HostTailCallPayloadV2;

typedef struct Lua55OverflowPayloadV2 {
    uint64_t required;
    uint64_t available;
    uint32_t pc;
    uint32_t reserved;
} Lua55OverflowPayloadV2;

typedef struct Lua55ErrorPayloadV2 {
    uint32_t error_kind;
    uint32_t pc;
    Lua55ValueV2 value;
} Lua55ErrorPayloadV2;

typedef struct Lua55RejectedPayloadV2 {
    uint32_t rejection_kind;
    uint32_t opcode;
    uint32_t pc;
    uint32_t expected_tag;       /* specialization mismatch: selected shape */
    uint32_t observed_tag;       /* specialization mismatch: observed shape */
} Lua55RejectedPayloadV2;

typedef struct Lua55NativeBoundaryOutcomeV2 {
    uint32_t discriminant;
    uint32_t result_count;   /* RETURNED: actual root result count */
    union {
        Lua55HostCallPayloadV2 host_call;
        Lua55HostTailCallPayloadV2 host_tail_call;
        Lua55OverflowPayloadV2 overflow;
        Lua55ErrorPayloadV2 error;
        Lua55RejectedPayloadV2 rejected;
    } u;
} Lua55NativeBoundaryOutcomeV2;

/* Exact temporary state between mechanically composed CALL fragments. No guest
   transfer occurs while either product is live. */
typedef struct Lua55PreparedCallV2 {
    Lua55NativeFrameV2 *callee;
    Lua55NativeEntryV2 entry;
    uint8_t *next_frame;
    uint32_t nparams;
    uint32_t nargs;
} Lua55PreparedCallV2;

typedef struct Lua55PreparedTailCallV2 {
    Lua55NativeEntryV2 entry;
    Lua55UpvalueCellV2 **upvalues;
    uint8_t *frame_end;
    uint32_t nparams;
    uint32_t nargs;
    uint32_t vararg_count;
    uint32_t maxstack;
    uint32_t value_capacity;
    uint32_t tbc_capacity;
} Lua55PreparedTailCallV2;

typedef struct Lua55PreparedConcatV2 {
    uint64_t total;
    Lua55GuestStringV2 *string;
    uint8_t *out;
} Lua55PreparedConcatV2;

typedef struct Lua55NativeInvocationV2 {
    uint8_t *frame_begin;
    uint8_t *frame_next;
    uint8_t *frame_end;
    Lua55NativeFrameV2 *current_frame;
    Lua55NativeFunctionDescriptorV2 *functions;
    uint32_t function_count;
    uint32_t open_value_capacity;
    Lua55GuestHeapV2 *heap;
    Lua55ValueV2 *result_values;
    uint32_t result_capacity;
    uint32_t result_count;
    uint8_t *learning;           /* mmap learning region (0 in residual mode) */
    uint32_t learning_capacity;  /* bytes */
    uint32_t learning_slots;     /* slot count */
    Lua55NativeBoundaryOutcomeV2 outcome;
    Lua55PreparedCallV2 prepared_call;
    Lua55PreparedTailCallV2 prepared_tail_call;
    Lua55PreparedConcatV2 prepared_concat;
    struct {
        uint32_t pc;
        uint32_t expected_tag;
        uint32_t observed_tag;
        uint32_t reserved;
    } specialization_mismatch;
} Lua55NativeInvocationV2;

/* Final frame shape: no V1 prefix, no recording slots, no destination
   chain, no V1 status or function table. Boundary state lives in the
   invocation outcome. The value/vararg/TBC slices follow the header. */
typedef struct Lua55NativeFrameV2 {
    Lua55NativeInvocationV2 *invocation;   /*   0 */
    Lua55NativeFrameV2 *caller;            /*   8 */
    Lua55NativeReturnLinkV2 return_link;   /*  16 */
    Lua55NativeResultSinkV2 result_sink;   /*  32 */
    Lua55UpvalueCellV2 **upvalues;         /*  48 */
    Lua55UpvalueCellV2 *open_upvalues;     /*  56 */
    Lua55TbcNodeV2 *tbc_nodes;             /*  64 */
    Lua55ValueV2 *values;                  /*  72 */
    uint32_t value_count;                  /*  80 */
    uint32_t value_capacity;               /*  84 */
    uint32_t top;                          /*  88 */
    uint32_t vararg_count;                 /*  92 */
    uint32_t tbc_count;                    /*  96 */
    uint32_t tbc_capacity;                 /* 100 */
} Lua55NativeFrameV2;

/* ---- boundary exits ---------------------------------------------------- */

/* One function section per stencil: the bank builder extracts by name. */
#define STENCIL(name)                                                           \
__attribute__((section(".text." #name), aligned(1), noinline, noclone, used)) \
void name

/* Closed scalar-cycle stencils must not acquire compiler-created constant
   pools or SIMD side data outside their copied function section. */
#define STENCIL_NOVEC(name)                                                     \
__attribute__((section(".text." #name), aligned(1), noinline, noclone, used,   \
               optimize("no-tree-vectorize")))                                \
void name

/* Patchable sentinels shared by the V2 stencils and the bank builder. */
#define RESUME_HOLE UINT32_C(0x66778899)
#define HOST_EXIT_HOLE UINT64_C(0x1a2b3c4d5e6f7081)

/* The single declared host boundary stub. Only this and the outer FFI
   entry execute `ret`; every guest call/return/tailcall is a jmp. */
extern void lua55_cps_host_exit(Lua55NativeFrameV2 *frame);

/* Proper-tail transfer contract: every guest call/return/tailcall/boundary
   exit is a C tail call `return entry(subject);` so GCC emits the callee-
   saved-register epilogue (balanced stack) before the jmp. An inline-asm
   `jmp` would skip the epilogue and corrupt the C stack. */
#define LUA55_CPS_HOST_EXIT(frame) do {                                    \
    uintptr_t lua55_cps_stub = (uintptr_t)HOST_EXIT_HOLE;                  \
    __asm__ volatile ("" : "+r"(lua55_cps_stub));                        \
    return ((Lua55NativeEntryV2)lua55_cps_stub)((Lua55NativeFrameV2 *)(frame)); \
} while (0)

/* A V2-typed C identifier bound to the existing successor relocation
   symbol: preserves the bank's exact `lua55_residual_next` PLT32
   relocation without casting a V2 frame through the V1 control type. */
extern void lua55_residual_next_v2(Lua55NativeFrameV2 *)
    __asm__("lua55_residual_next");
/* Genuine tail call: GCC emits the balanced epilogue then `jmp` to the
   patched successor. A bare statement call would emit `call` + `ret` when a
   branch precedes it, corrupting the C stack across the arena chain. */
#define LUA55_RESIDUAL_NEXT(frame) \
    return lua55_residual_next_v2((frame))

/* close every open upvalue owned by this frame before its storage is
   reused: the persistent cell takes the final register value. */
static inline void lua55_cps_close_open_upvalues(Lua55NativeFrameV2 *frame)
{
    Lua55UpvalueCellV2 *cell = frame->open_upvalues;
    while (cell != 0) {
        Lua55UpvalueCellV2 *next = cell->next_open;
        cell->closed_value = cell->open_slot[0];
        cell->open_slot = 0;
        cell->state = LUA55_UPVALUE_CLOSED;
        cell->generation = cell->generation + 1;
        cell->next_open = 0;
        cell = next;
    }
    frame->open_upvalues = 0;
}

/* Reject/overflow exits publish an exact invocation outcome and return to
   the outer FFI boundary through the patched host stub. */

static inline void lua55_v2_publish_reject(Lua55NativeFrameV2 *frame,
    uint32_t kind, uint32_t pc)
{
    frame->invocation->outcome.discriminant = LUA55_V2_OUTCOME_REJECTED;
    frame->invocation->outcome.u.rejected.rejection_kind = kind;
    frame->invocation->outcome.u.rejected.opcode = 0;
    frame->invocation->outcome.u.rejected.pc = pc;
}

#define V2_REJECT(frame, kind) do {                                        \
    uint32_t v2_pc_hole = RESUME_HOLE;                                     \
    __asm__ volatile ("" : "+r"(v2_pc_hole));                          \
    lua55_v2_publish_reject((frame), (kind), v2_pc_hole);                  \
} while (0)

/* Publish a typed overflow outcome with an exact (required, available, pc)
   payload. The pc is a runtime-guarded hole patched by the arena builder. */
#define V2_PUBLISH_OVERFLOW(frame, kind, need, have) do {               \
    uint32_t v2_pc_hole = RESUME_HOLE;                                    \
    __asm__ volatile ("" : "+r"(v2_pc_hole));                         \
    (frame)->invocation->outcome.discriminant = (kind);                   \
    (frame)->invocation->outcome.u.overflow.required = (need);            \
    (frame)->invocation->outcome.u.overflow.available = (have);           \
    (frame)->invocation->outcome.u.overflow.pc = v2_pc_hole;              \
} while (0)

#endif
