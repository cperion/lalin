#include "opcode_value_v1.h"

/* Batch 6: host-mediated calls. Native side: RETURN (70), RETURN0 (71),
   RETURN1 (72) are terminals — they record a quote, store the return pc
   (patched), complete, and return (no lua55_learn_next / residual_next).
   The host reads the return registers from the occurrence's (A, B) and
   copies results across the call boundary. CALL (68) / TAILCALL (69) are
   host-side dispatch boundaries: the projection splits straight-line
   segments at call pcs (project_call_plan) and the driver invokes the
   callee's own native plan, copying args in and results out. */

#define QUOTE_BASE_HOLE UINT32_C(0x0f1e2d3c)
#define RETURN_PC_HOLE UINT32_C(0x10203040)

STENCIL(lua55_learn_return)(Lua55LearnFrameV1 *frame)
{
    Lua55RecordingSlotV1 *slot = next_slot(frame);
    uint32_t base = QUOTE_BASE_HOLE;
    __asm__ volatile ("" : "+r"(base));
    slot->quote = base | 1;
    frame->resume_pc = RETURN_PC_HOLE;
    frame->status = LUA55_COMPLETED;
    /* terminal: no lua55_learn_next */
}

STENCIL(lua55_learn_return0)(Lua55LearnFrameV1 *frame)
{
    Lua55RecordingSlotV1 *slot = next_slot(frame);
    uint32_t base = QUOTE_BASE_HOLE;
    __asm__ volatile ("" : "+r"(base));
    slot->quote = base | 1;
    frame->resume_pc = RETURN_PC_HOLE;
    frame->status = LUA55_COMPLETED;
}

STENCIL(lua55_learn_return1)(Lua55LearnFrameV1 *frame)
{
    Lua55RecordingSlotV1 *slot = next_slot(frame);
    uint32_t base = QUOTE_BASE_HOLE;
    __asm__ volatile ("" : "+r"(base));
    slot->quote = base | 1;
    frame->resume_pc = RETURN_PC_HOLE;
    frame->status = LUA55_COMPLETED;
}

STENCIL(lua55_residual_return)(Lua55LearnFrameV1 *frame)
{
    frame->resume_pc = RETURN_PC_HOLE;
    frame->status = LUA55_COMPLETED;
}

STENCIL(lua55_residual_return0)(Lua55LearnFrameV1 *frame)
{
    frame->resume_pc = RETURN_PC_HOLE;
    frame->status = LUA55_COMPLETED;
}

STENCIL(lua55_residual_return1)(Lua55LearnFrameV1 *frame)
{
    frame->resume_pc = RETURN_PC_HOLE;
    frame->status = LUA55_COMPLETED;
}

/* ---- Self-selecting native call transfer -------------------------------
   The polymorphic CALL / TAILCALL / RETURN residuals. CALL allocates the
   callee frame on the C stack (alloca), copies the args and the closure's
   upvalue cells, sets the callee's result destination (the dest chain), and
   calls the callee's native entry directly. RETURN writes the results into
   the dest frame (the caller's register slots) and returns — the `ret`
   lands back in the caller's CALL stencil, which continues. TAILCALL
   forwards the caller's own dest to the callee and returns without copying
   (proper tail transfer). The host fallback (builtins / library calls /
   unsupported callees) rejects with the call pc so the driver dispatches. */

#define A_HOLE UINT32_C(0x01020304)
#define B_HOLE UINT32_C(0x05060708)
#define C_HOLE UINT32_C(0x09101112)
#define CALL_PC_HOLE UINT32_C(0x13141516)

static inline __attribute__((always_inline)) size_t native_frame_size(
    Lua55GuestClosureV1 *closure)
{
    size_t nupvals = closure->upvalue_count;
    return sizeof(Lua55LearnFrameV1) +
        (size_t)closure->maxstacksize * sizeof(Lua55ValueV1) +
        (nupvals > 0 ? nupvals : 1) * sizeof(Lua55UpvalueCellV1);
}

static inline __attribute__((always_inline)) Lua55LearnFrameV1 *init_native_frame(
    uint8_t *mem, Lua55LearnFrameV1 *frame, Lua55GuestClosureV1 *closure,
    uint32_t nargs, uint32_t A, int32_t dest_count,
    Lua55LearnFrameV1 *dest_frame, uint32_t dest_base)
{
    size_t nvalues = closure->maxstacksize;
    size_t nupvals = closure->upvalue_count;
    Lua55LearnFrameV1 *cframe = (Lua55LearnFrameV1 *)mem;
    cframe->values = (Lua55ValueV1 *)(mem + sizeof(Lua55LearnFrameV1));
    cframe->slots = 0;
    cframe->upvalues = (Lua55UpvalueCellV1 *)(cframe->values + nvalues);
    cframe->heap = frame->heap;
    cframe->value_count = (uint32_t)nvalues;
    cframe->slot_count = 0;
    cframe->slot_cursor = 0;
    cframe->resume_pc = 0;
    cframe->status = LUA55_EXECUTING;
    cframe->upvalue_count = (uint32_t)nupvals;
    cframe->vararg_count = closure->is_vararg
        ? (nargs > closure->numparams ? nargs - closure->numparams : 0) : 0;
    cframe->dest_frame = dest_frame;
    cframe->dest_base = dest_base;
    cframe->dest_count = dest_count;
    cframe->top = nargs;
    cframe->result_count = 0;
    cframe->function_table = frame->function_table;
    uint32_t i;
    for (i = 0; i < nargs; i++)
        cframe->values[i] = frame->values[A + 1 + i];
    for (i = 0; i < nupvals; i++) {
        Lua55UpvalueCellV1 *cell = &closure->cells[i];
        Lua55UpvalueCellV1 *dst = &cframe->upvalues[i];
        if (cell->state == LUA55_UPVALUE_OPEN) {
            dst->state = LUA55_UPVALUE_OPEN;
            dst->open_slot = cell->open_slot;
            dst->generation = cell->generation;
        } else {
            dst->state = LUA55_UPVALUE_CLOSED;
            dst->closed_value = cell->closed_value;
            dst->generation = cell->generation;
        }
    }
    return cframe;
}

STENCIL(lua55_poly_call)(Lua55LearnFrameV1 *frame)
{
    uint32_t A = A_HOLE;
    __asm__ volatile ("" : "+r"(A));
    uint32_t B = B_HOLE;
    __asm__ volatile ("" : "+r"(B));
    uint32_t C = C_HOLE;
    __asm__ volatile ("" : "+r"(C));
    uint32_t pc = CALL_PC_HOLE;
    __asm__ volatile ("" : "+r"(pc));
    Lua55ValueV1 *callee_cell = &frame->values[A];
    if (callee_cell->tag == LUA55_VALUE_CLOSURE
        && frame->function_table != 0) {
        Lua55GuestClosureV1 *closure =
            (Lua55GuestClosureV1 *)callee_cell->payload.reference;
        Lua55OpcodeEntryV1 entry =
            frame->function_table[closure->proto_index];
        if (closure->header.kind == LUA55_OBJECT_CLOSURE && entry != 0) {
            uint32_t nargs = B - 1;
            if (nargs >= 0xFFFFFFu) nargs = frame->top > A + 1
                ? frame->top - (A + 1) : 0;
            uint8_t *callee_mem = (uint8_t *)__builtin_alloca(
                native_frame_size(closure));
            Lua55LearnFrameV1 *cframe = init_native_frame(
                callee_mem, frame, closure, nargs, A, (int32_t)C - 1, frame, A);
            entry(cframe);
            frame->top = A + cframe->result_count;
            lua55_residual_next(frame);
            return;
        }
    }
    frame->resume_pc = pc;
    frame->status = LUA55_REJECTED;   /* host dispatch (builtin / library) */
}

STENCIL(lua55_poly_tailcall)(Lua55LearnFrameV1 *frame)
{
    uint32_t A = A_HOLE;
    __asm__ volatile ("" : "+r"(A));
    uint32_t B = B_HOLE;
    __asm__ volatile ("" : "+r"(B));
    uint32_t C = C_HOLE;
    __asm__ volatile ("" : "+r"(C));
    uint32_t pc = CALL_PC_HOLE;
    __asm__ volatile ("" : "+r"(pc));
    Lua55ValueV1 *callee_cell = &frame->values[A];
    if (callee_cell->tag == LUA55_VALUE_CLOSURE
        && frame->function_table != 0) {
        Lua55GuestClosureV1 *closure =
            (Lua55GuestClosureV1 *)callee_cell->payload.reference;
        Lua55OpcodeEntryV1 entry =
            frame->function_table[closure->proto_index];
        if (closure->header.kind == LUA55_OBJECT_CLOSURE && entry != 0) {
            uint32_t nargs = B - 1;
            if (nargs >= 0xFFFFFFu) nargs = frame->top > A + 1
                ? frame->top - (A + 1) : 0;
            uint8_t *callee_mem = (uint8_t *)__builtin_alloca(
                native_frame_size(closure));
            Lua55LearnFrameV1 *cframe = init_native_frame(
                callee_mem, frame, closure, nargs, A, frame->dest_count,
                frame->dest_frame, frame->dest_base);
            entry(cframe);
            /* the tail transfer is the caller's return: complete it */
            frame->status = LUA55_COMPLETED;
            return;   /* the caller's frame is dead */
        }
    }
    frame->resume_pc = pc;
    frame->status = LUA55_REJECTED;   /* host dispatch */
}

#define RETURN_POLY(name, b_mode, fixed)                                   \
STENCIL(name)(Lua55LearnFrameV1 *frame)                                     \
{                                                                           \
    uint32_t A = A_HOLE;                                                    \
    __asm__ volatile ("" : "+r"(A));                                        \
    uint32_t pc = CALL_PC_HOLE;                                             \
    __asm__ volatile ("" : "+r"(pc));                                       \
    int32_t nres = (b_mode) ? (int32_t)((uint32_t)(fixed)) : 0;             \
    if (nres < 0) nres = 0;                                                 \
    frame->result_count = (uint32_t)nres;                                   \
    Lua55LearnFrameV1 *dest = frame->dest_frame;                            \
    if (dest != 0) {                                                        \
        int32_t count = frame->dest_count >= 0                              \
            ? (frame->dest_count < nres ? frame->dest_count : nres) : nres; \
        int32_t i;                                                          \
        for (i = 0; i < count; i++)                                         \
            dest->values[frame->dest_base + i] = frame->values[A + i];      \
        dest->top = frame->dest_base + (uint32_t)count;                     \
    }                                                                       \
    frame->resume_pc = pc;                                                  \
    frame->status = LUA55_COMPLETED;                                        \
    return;                                                                 \
}

#define RETURN_B_POLY(name)                                                 \
STENCIL(name)(Lua55LearnFrameV1 *frame)                                     \
{                                                                           \
    uint32_t A = A_HOLE;                                                    \
    __asm__ volatile ("" : "+r"(A));                                        \
    uint32_t B = B_HOLE;                                                    \
    __asm__ volatile ("" : "+r"(B));                                        \
    uint32_t pc = CALL_PC_HOLE;                                             \
    __asm__ volatile ("" : "+r"(pc));                                       \
    int32_t nres = B == 0 ? (int32_t)frame->top - (int32_t)A              \
                           : (int32_t)B - 1;                               \
    if (nres < 0) nres = 0;                                                 \
    frame->result_count = (uint32_t)nres;                                   \
    Lua55LearnFrameV1 *dest = frame->dest_frame;                            \
    if (dest != 0) {                                                        \
        int32_t count = frame->dest_count >= 0                              \
            ? (frame->dest_count < nres ? frame->dest_count : nres) : nres; \
        int32_t i;                                                          \
        for (i = 0; i < count; i++)                                         \
            dest->values[frame->dest_base + i] = frame->values[A + i];      \
        dest->top = frame->dest_base + (uint32_t)count;                     \
    }                                                                       \
    frame->resume_pc = pc;                                                  \
    frame->status = LUA55_COMPLETED;                                        \
    return;                                                                 \
}

RETURN_B_POLY(lua55_poly_return)
RETURN_POLY(lua55_poly_return0, 1, 0)
RETURN_POLY(lua55_poly_return1, 1, 1)
