#include "opcode_value_v1.h"
#include "opcode_value_v2.h"

/* Batch 9: CLOSURE (79) — closure materialization.
   R[A] := closure(proto K[Bx], upvalues). The guest heap bumps a closure
   object (non-moving) with its upvalue cells inline. Each upvalue comes
   from the enclosing frame per the proto's descriptors (bounded at 4):
   isinstack -> the cell is OPEN, pointing at the enclosing frame's
   register; otherwise -> the cell is CLOSED with a copy of the enclosing
   frame's upvalue value. The learner materializes once; the residual
   re-materializes a FRESH closure each run (the isinstack cells keep
   pointing at the current frame registers; the closed cells re-copy). */

#define TARGET_INDEX UINT32_C(0x111)
#define QUOTE_BASE_HOLE UINT32_C(0x0f1e2d3c)
#define RESUME_PC UINT32_C(0x66778899)
#define PROTO_INDEX_HOLE UINT32_C(0x0d0e0f10)
#define NUPVALS_HOLE UINT32_C(0x1d1e1f20)
#define INSTACK_0 UINT32_C(0x2d2e2f30)
#define IDX_0 UINT32_C(0x3d3e3f40)
#define INSTACK_1 UINT32_C(0x4d4e4f50)
#define IDX_1 UINT32_C(0x5d5e5f60)
#define INSTACK_2 UINT32_C(0x6d6e6f70)
#define IDX_2 UINT32_C(0x7d7e7f80)
#define INSTACK_3 UINT32_C(0x8d8e8f90)
#define IDX_3 UINT32_C(0x9d9e9fa0)

#define GUARD_FAILED(frame) do {            \
    (frame)->resume_pc = RESUME_PC;          \
    (frame)->status = LUA55_GUARD_FAILED;    \
} while (0)

#define REJECT(frame) do {                  \
    (frame)->resume_pc = RESUME_PC;          \
    (frame)->status = LUA55_REJECTED;        \
} while (0)

/* the current value of an upvalue cell (open slot or closed cell) */
static Lua55ValueV1 *upvalue_value(
    Lua55LearnFrameV1 *frame, Lua55UpvalueCellV1 *cell)
{
    if (cell->state == LUA55_UPVALUE_OPEN) return cell->open_slot;
    return &cell->closed_value;
}

static inline __attribute__((always_inline)) Lua55GuestClosureV1 *new_closure(
    Lua55LearnFrameV1 *frame, uint32_t proto_index, uint32_t nupvals)
{
    Lua55GuestHeapV1 *heap = frame->heap;
    size_t cells_size = sizeof(Lua55UpvalueCellV1) * nupvals;
    size_t closure_size = sizeof(Lua55GuestClosureV1) + cells_size;
    uintptr_t next, aligned;
    Lua55GuestClosureV1 *closure;
    uint32_t i;
    if (heap == 0 || heap->table_region == 0) return 0;
    next = heap->table_next;
    aligned = (next + 15) & ~(uintptr_t)15;
    if (aligned + closure_size > heap->table_region_end) return 0;
    closure = (Lua55GuestClosureV1 *)aligned;
    for (i = 0; i < nupvals; i++) {
        Lua55UpvalueCellV1 *cell = &closure->cells[i];
        cell->open_slot = 0;
        cell->closed_value.tag = 0;
        cell->closed_value.reserved = 0;
        cell->closed_value.payload.reference = 0;
        cell->state = 0;
        cell->generation = 0;
    }
    closure->header.kind = LUA55_OBJECT_CLOSURE;
    closure->header.generation = heap->object_count + 1;
    closure->proto_index = proto_index;
    closure->upvalue_count = nupvals;
    heap->object_count++;
    heap->table_next = aligned + closure_size;
    return closure;
}

/* set closure cell i from the enclosing frame per (isinstack, idx) */
static inline __attribute__((always_inline)) void set_closure_cell(
    Lua55LearnFrameV1 *frame, Lua55GuestClosureV1 *closure,
    uint32_t i, uint32_t isinstack, uint32_t idx)
{
    Lua55UpvalueCellV1 *cell = &closure->cells[i];
    if (isinstack) {
        cell->state = LUA55_UPVALUE_OPEN;
        cell->open_slot = &frame->values[idx];
        cell->generation = 1;
    }
    else {
        cell->state = LUA55_UPVALUE_CLOSED;
        cell->closed_value = *upvalue_value(frame, &frame->upvalues[idx]);
        cell->generation = 2;
    }
}

#define CLOSURE_DESCRIPTOR_READS(frame, closure, nupvals)               \
    if ((nupvals) > 0) set_closure_cell((frame), (closure), 0, INSTACK_0, IDX_0); \
    if ((nupvals) > 1) set_closure_cell((frame), (closure), 1, INSTACK_1, IDX_1); \
    if ((nupvals) > 2) set_closure_cell((frame), (closure), 2, INSTACK_2, IDX_2); \
    if ((nupvals) > 3) set_closure_cell((frame), (closure), 3, INSTACK_3, IDX_3);

STENCIL(lua55_learn_closure)(Lua55LearnFrameV1 *frame)
{
    Lua55ValueV1 *target = &frame->values[TARGET_INDEX];
    Lua55RecordingSlotV1 *slot = next_slot(frame);
    uint32_t base = QUOTE_BASE_HOLE;
    __asm__ volatile ("" : "+r"(base));
    slot->quote = base | 1;
    uint32_t proto_index = PROTO_INDEX_HOLE;
    __asm__ volatile ("" : "+r"(proto_index));
    uint32_t nupvals = NUPVALS_HOLE;
    __asm__ volatile ("" : "+r"(nupvals));
    uint32_t instack0 = INSTACK_0, idx0 = IDX_0;
    __asm__ volatile ("" : "+r"(instack0)); __asm__ volatile ("" : "+r"(idx0));
    uint32_t instack1 = INSTACK_1, idx1 = IDX_1;
    __asm__ volatile ("" : "+r"(instack1)); __asm__ volatile ("" : "+r"(idx1));
    uint32_t instack2 = INSTACK_2, idx2 = IDX_2;
    __asm__ volatile ("" : "+r"(instack2)); __asm__ volatile ("" : "+r"(idx2));
    uint32_t instack3 = INSTACK_3, idx3 = IDX_3;
    __asm__ volatile ("" : "+r"(instack3)); __asm__ volatile ("" : "+r"(idx3));
    (void)instack0; (void)idx0; (void)instack1; (void)idx1;
    (void)instack2; (void)idx2; (void)instack3; (void)idx3;
    Lua55GuestClosureV1 *closure = new_closure(frame, proto_index, nupvals);
    if (closure == 0) { REJECT(frame); return; }
    if (nupvals > 0) set_closure_cell(frame, closure, 0, instack0, idx0);
    if (nupvals > 1) set_closure_cell(frame, closure, 1, instack1, idx1);
    if (nupvals > 2) set_closure_cell(frame, closure, 2, instack2, idx2);
    if (nupvals > 3) set_closure_cell(frame, closure, 3, instack3, idx3);
    SET_TAG(target, LUA55_VALUE_CLOSURE);
    target->payload.reference = (uintptr_t)closure;
    lua55_learn_next(frame);
}

STENCIL(lua55_residual_closure)(Lua55LearnFrameV1 *frame)
{
    Lua55ValueV1 *target = &frame->values[TARGET_INDEX];
    uint32_t proto_index = PROTO_INDEX_HOLE;
    __asm__ volatile ("" : "+r"(proto_index));
    uint32_t nupvals = NUPVALS_HOLE;
    __asm__ volatile ("" : "+r"(nupvals));
    uint32_t instack0 = INSTACK_0, idx0 = IDX_0;
    __asm__ volatile ("" : "+r"(instack0)); __asm__ volatile ("" : "+r"(idx0));
    uint32_t instack1 = INSTACK_1, idx1 = IDX_1;
    __asm__ volatile ("" : "+r"(instack1)); __asm__ volatile ("" : "+r"(idx1));
    uint32_t instack2 = INSTACK_2, idx2 = IDX_2;
    __asm__ volatile ("" : "+r"(instack2)); __asm__ volatile ("" : "+r"(idx2));
    uint32_t instack3 = INSTACK_3, idx3 = IDX_3;
    __asm__ volatile ("" : "+r"(instack3)); __asm__ volatile ("" : "+r"(idx3));
    (void)instack0; (void)idx0; (void)instack1; (void)idx1;
    (void)instack2; (void)idx2; (void)instack3; (void)idx3;
    Lua55GuestClosureV1 *closure = new_closure(frame, proto_index, nupvals);
    if (closure == 0) { GUARD_FAILED(frame); return; }
    if (nupvals > 0) set_closure_cell(frame, closure, 0, instack0, idx0);
    if (nupvals > 1) set_closure_cell(frame, closure, 1, instack1, idx1);
    if (nupvals > 2) set_closure_cell(frame, closure, 2, instack2, idx2);
    if (nupvals > 3) set_closure_cell(frame, closure, 3, instack3, idx3);
    SET_TAG(target, LUA55_VALUE_CLOSURE);
    target->payload.reference = (uintptr_t)closure;
    lua55_residual_next(frame);
}

/* Self-selecting CLOSURE records the callee frame facts used by native CALL
   and materializes the exact bounded upvalue descriptors. */
#define MAXSTACK_HOLE UINT32_C(0x5a6b7c8d)
#define NUMPARAMS_HOLE UINT32_C(0x6b7c8d9e)
#define IS_VARARG_HOLE UINT32_C(0x7c8d9eaf)
#define CLOSURE_TARGET UINT32_C(0x111)

STENCIL(lua55_poly_closure)(Lua55LearnFrameV1 *frame)
{
    uint32_t target_index = CLOSURE_TARGET;
    __asm__ volatile ("" : "+r"(target_index));
    Lua55ValueV1 *target = &frame->values[target_index];
    uint32_t proto_index = PROTO_INDEX_HOLE;
    __asm__ volatile ("" : "+r"(proto_index));
    uint32_t nupvals = NUPVALS_HOLE;
    __asm__ volatile ("" : "+r"(nupvals));
    uint32_t instack0 = INSTACK_0, idx0 = IDX_0;
    __asm__ volatile ("" : "+r"(instack0)); __asm__ volatile ("" : "+r"(idx0));
    uint32_t instack1 = INSTACK_1, idx1 = IDX_1;
    __asm__ volatile ("" : "+r"(instack1)); __asm__ volatile ("" : "+r"(idx1));
    uint32_t instack2 = INSTACK_2, idx2 = IDX_2;
    __asm__ volatile ("" : "+r"(instack2)); __asm__ volatile ("" : "+r"(idx2));
    uint32_t instack3 = INSTACK_3, idx3 = IDX_3;
    __asm__ volatile ("" : "+r"(instack3)); __asm__ volatile ("" : "+r"(idx3));
    uint32_t maxstack = MAXSTACK_HOLE;
    __asm__ volatile ("" : "+r"(maxstack));
    uint32_t numparams = NUMPARAMS_HOLE;
    __asm__ volatile ("" : "+r"(numparams));
    uint32_t is_vararg = IS_VARARG_HOLE;
    __asm__ volatile ("" : "+r"(is_vararg));
    Lua55GuestClosureV1 *closure = new_closure(frame, proto_index, nupvals);
    if (closure == 0) { REJECT(frame); LUA55_CPS_HOST_EXIT(frame); }
    closure->maxstacksize = maxstack;
    closure->numparams = numparams;
    closure->is_vararg = is_vararg;
    if (nupvals > 0) set_closure_cell(frame, closure, 0, instack0, idx0);
    if (nupvals > 1) set_closure_cell(frame, closure, 1, instack1, idx1);
    if (nupvals > 2) set_closure_cell(frame, closure, 2, instack2, idx2);
    if (nupvals > 3) set_closure_cell(frame, closure, 3, instack3, idx3);
    SET_TAG(target, LUA55_VALUE_CLOSURE);
    target->payload.reference = (uintptr_t)closure;
    lua55_residual_next(frame);
}
