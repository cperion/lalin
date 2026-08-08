#include "opcode_value_v1.h"

/* Batch 12: generic-for protocol — TFORPREP (75) and TFORLOOP (77)
   natively; TFORCALL (76) is a host-mediated iterator dispatch boundary
   (like CALL). The 5-register layout at R[A..A+4]:
   R[A]=iterator f, R[A+1]=state s, R[A+2]=closing, R[A+3]=control var,
   R[A+4]=value.
   TFORPREP swaps R[A+2] and R[A+3] (closing/control), rejects a non-nil
   closing (<close> contract, TBC unsupported), and is a terminal that
   resumes at the TFORCALL pc (the first iteration runs the iterator).
   TFORLOOP is a terminal when the control var is non-nil (resumes at the
   body start) and falls through when nil (the loop exits). Both recompute
   each run. */

#define TFOR_BASE_HOLE UINT32_C(0x999)          /* register A */
#define TFOR_TARGET_HOLE UINT32_C(0x10203040)   /* the resume pc (patched) */
#define QUOTE_BASE_HOLE UINT32_C(0x0f1e2d3c)
#define RESUME_PC UINT32_C(0x66778899)

#define REJECT(frame) do {                  \
    (frame)->resume_pc = RESUME_PC;          \
    (frame)->status = LUA55_REJECTED;        \
} while (0)

STENCIL(lua55_learn_tforprep)(Lua55LearnFrameV1 *frame)
{
    Lua55RecordingSlotV1 *slot = next_slot(frame);
    uint32_t base = QUOTE_BASE_HOLE;
    __asm__ volatile ("" : "+r"(base));
    slot->quote = base | 1;
    uint32_t a = TFOR_BASE_HOLE;
    __asm__ volatile ("" : "+r"(a));
    Lua55ValueV1 *closing = &frame->values[a + 2];
    Lua55ValueV1 *control = &frame->values[a + 3];
    Lua55ValueV1 temp = *closing;
    *closing = *control;
    *control = temp;
    if (closing->tag != LUA55_VALUE_NIL) { REJECT(frame); return; }  /* <close> */
    frame->resume_pc = TFOR_TARGET_HOLE;   /* the TFORCALL pc */
    frame->status = LUA55_COMPLETED;
    /* terminal: no lua55_learn_next */
}

STENCIL(lua55_residual_tforprep)(Lua55LearnFrameV1 *frame)
{
    uint32_t a = TFOR_BASE_HOLE;
    __asm__ volatile ("" : "+r"(a));
    Lua55ValueV1 *closing = &frame->values[a + 2];
    Lua55ValueV1 *control = &frame->values[a + 3];
    Lua55ValueV1 temp = *closing;
    *closing = *control;
    *control = temp;
    if (closing->tag != LUA55_VALUE_NIL) {
        frame->resume_pc = RESUME_PC;
        frame->status = LUA55_GUARD_FAILED;
        return;
    }
    frame->resume_pc = TFOR_TARGET_HOLE;
    frame->status = LUA55_COMPLETED;
    /* terminal: no lua55_residual_next */
}

STENCIL(lua55_learn_tforloop)(Lua55LearnFrameV1 *frame)
{
    Lua55RecordingSlotV1 *slot = next_slot(frame);
    uint32_t base = QUOTE_BASE_HOLE;
    __asm__ volatile ("" : "+r"(base));
    slot->quote = base | 1;
    uint32_t a = TFOR_BASE_HOLE;
    __asm__ volatile ("" : "+r"(a));
    Lua55ValueV1 *control = &frame->values[a + 3];
    if (control->tag != LUA55_VALUE_NIL) {
        frame->resume_pc = TFOR_TARGET_HOLE;   /* the body start */
        frame->status = LUA55_COMPLETED;
        return;   /* terminal: taken back-edge */
    }
    lua55_learn_next(frame);   /* not-taken: the loop exits */
}

STENCIL(lua55_residual_tforloop)(Lua55LearnFrameV1 *frame)
{
    uint32_t a = TFOR_BASE_HOLE;
    __asm__ volatile ("" : "+r"(a));
    Lua55ValueV1 *control = &frame->values[a + 3];
    if (control->tag != LUA55_VALUE_NIL) {
        frame->resume_pc = TFOR_TARGET_HOLE;
        frame->status = LUA55_COMPLETED;
        return;   /* terminal: taken back-edge */
    }
    lua55_residual_next(frame);   /* not-taken: the loop exits */
}
