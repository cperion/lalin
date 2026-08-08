#include "opcode_value_v1.h"

/* Native loop-link terminals. The standard JMP/FORLOOP residuals return to
   the host (resume_pc + ret), forcing a host hop per loop iteration. The
   link variants end the back-edge path with `jmp *LINK_HOLE`: the runner
   patches the absolute code address of the loop target's block entry, so
   the back-edge stays inside the RX arena. The fallthrough/exits still
   `ret` (the host handles the loop exit once). */

#define TARGET_PC_HOLE UINT32_C(0x10203040)
#define BASE_INDEX_HOLE UINT32_C(0x11223344)
#define BACK_EDGE_HOLE UINT32_C(0x55667788)
#define FALLTHROUGH_HOLE UINT32_C(0x99aabbcc)
#define LINK_HOLE UINT64_C(0x1122334455667788)

static inline int64_t lua55_link_int_add(int64_t a, int64_t b)
{
    return (int64_t)((uint64_t)a + (uint64_t)b);   /* intop wrap */
}

STENCIL(lua55_residual_jmp_link)(Lua55LearnFrameV1 *frame)
{
    frame->resume_pc = TARGET_PC_HOLE;
    frame->status = LUA55_COMPLETED;
    uintptr_t link = (uintptr_t)LINK_HOLE;
    __asm__ volatile("" : "+r"(link));
    __asm__ volatile("jmp *%0" :: "r"(link));
    /* no lua55_residual_next, no ret: the patched jmp is the edge */
}

STENCIL(lua55_residual_forloop_link)(Lua55LearnFrameV1 *frame)
{
    uint32_t A = BASE_INDEX_HOLE;
    __asm__ volatile("" : "+r"(A));
    uint32_t back_edge = BACK_EDGE_HOLE;
    __asm__ volatile("" : "+r"(back_edge));
    uint32_t fallthrough = FALLTHROUGH_HOLE;
    __asm__ volatile("" : "+r"(fallthrough));
    Lua55ValueV1 *count_cell = &frame->values[A];
    Lua55ValueV1 *step_cell = &frame->values[A + 1];
    Lua55ValueV1 *idx_cell = &frame->values[A + 2];
    if (step_cell->tag == LUA55_VALUE_INTEGER) {
        int64_t count = count_cell->payload.integer;
        if (count > 0) {
            count_cell->payload.integer = count - 1;
            idx_cell->payload.integer =
                lua55_link_int_add(idx_cell->payload.integer, step_cell->payload.integer);
            frame->resume_pc = back_edge;
            frame->status = LUA55_COMPLETED;
            uintptr_t link = (uintptr_t)LINK_HOLE;
            __asm__ volatile("" : "+r"(link));
            __asm__ volatile("jmp *%0" :: "r"(link));
        }
        frame->resume_pc = fallthrough;
        frame->status = LUA55_COMPLETED;
        return;
    } else {
        double idx = idx_cell->payload.floating;
        double step = step_cell->payload.floating;
        double limit = count_cell->payload.floating;
        idx = idx + step;
        if ((step > 0.0 && idx <= limit) || (step < 0.0 && limit <= idx)) {
            idx_cell->payload.floating = idx;
            frame->resume_pc = back_edge;
            frame->status = LUA55_COMPLETED;
            uintptr_t link = (uintptr_t)LINK_HOLE;
            __asm__ volatile("" : "+r"(link));
            __asm__ volatile("jmp *%0" :: "r"(link));
        }
        frame->resume_pc = fallthrough;
        frame->status = LUA55_COMPLETED;
        return;
    }
}
