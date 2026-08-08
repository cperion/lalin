#include "opcode_value_v1.h"

/* Batch 4: standalone JMP (56). An unconditional terminal: the occurrence
   records a quote, stores the exact target pc (patched), completes, and
   returns. The learner never calls lua55_learn_next and the residual never
   calls lua55_residual_next — the chain ends here, and the host resumes at
   the stored resume_pc (the loop back-edge or forward branch target).
   Stock semantics (lvm.c:dojump): pc += sJ with pc already past the
   instruction, so target = pc + sJ + 1; the projection resolves the target
   and it is patched into both the learner and the residual. */

#define TARGET_PC_HOLE UINT32_C(0x10203040)
#define QUOTE_BASE_HOLE UINT32_C(0x0f1e2d3c)

STENCIL(lua55_learn_jmp)(Lua55LearnFrameV1 *frame)
{
    Lua55RecordingSlotV1 *slot = next_slot(frame);
    uint32_t base = QUOTE_BASE_HOLE;
    __asm__ volatile ("" : "+r"(base));
    slot->quote = base | 1;
    frame->resume_pc = TARGET_PC_HOLE;
    frame->status = LUA55_COMPLETED;
    /* terminal: no lua55_learn_next */
}

STENCIL(lua55_residual_jmp)(Lua55LearnFrameV1 *frame)
{
    frame->resume_pc = TARGET_PC_HOLE;
    frame->status = LUA55_COMPLETED;
    /* terminal: no lua55_residual_next */
}

/* Self-selecting JMP: a terminal; the runner links the patched native jump
   (the loop back-edge) or the host resume. */
#define POLY_LINK_HOLE UINT64_C(0x1122334455667788)

STENCIL(lua55_poly_jmp)(Lua55LearnFrameV1 *frame)
{
    frame->resume_pc = TARGET_PC_HOLE;
    frame->status = LUA55_COMPLETED;
    uintptr_t link = (uintptr_t)POLY_LINK_HOLE;
    __asm__ volatile ("" : "+r"(link));
    __asm__ volatile ("jmp *%0" :: "r"(link));
}
