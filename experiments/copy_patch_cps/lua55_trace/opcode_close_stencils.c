#include "opcode_value_v1.h"

/* Batch 13: CLOSE (54), TBC (55), ERRNNIL (82).
   - CLOSE closes to-be-closed variables up to R[A]; the closed subset
     never creates them (TFORPREP rejects non-nil closings, TBC rejects),
     so CLOSE is a pass-through that records and advances.
   - TBC marks R[A] as to-be-closed (<close>); the __close contract is a
     visible boundary — the learner rejects (the host marks it).
   - ERRNNIL fires "global already defined" when R[A] is NOT nil; the
     learner passes through when nil and rejects when non-nil. */

#define TARGET_INDEX UINT32_C(0x111)
#define QUOTE_BASE_HOLE UINT32_C(0x0f1e2d3c)
#define RESUME_PC UINT32_C(0x66778899)

#define REJECT(frame) do {                  \
    (frame)->resume_pc = RESUME_PC;          \
    (frame)->status = LUA55_REJECTED;        \
} while (0)

STENCIL(lua55_learn_close)(Lua55LearnFrameV1 *frame)
{
    Lua55RecordingSlotV1 *slot = next_slot(frame);
    uint32_t base = QUOTE_BASE_HOLE;
    __asm__ volatile ("" : "+r"(base));
    slot->quote = base | 1;
    lua55_learn_next(frame);
}

STENCIL(lua55_residual_close)(Lua55LearnFrameV1 *frame)
{
    lua55_residual_next(frame);
}

STENCIL(lua55_learn_tbc)(Lua55LearnFrameV1 *frame)
{
    REJECT(frame);   /* <close> contract: the host marks the value */
}

STENCIL(lua55_learn_errnnil)(Lua55LearnFrameV1 *frame)
{
    Lua55ValueV1 *target = &frame->values[TARGET_INDEX];
    Lua55RecordingSlotV1 *slot = next_slot(frame);
    uint32_t base = QUOTE_BASE_HOLE;
    __asm__ volatile ("" : "+r"(base));
    slot->quote = base | 1;
    if (target->tag != LUA55_VALUE_NIL) {
        REJECT(frame);   /* "global already defined" */
        return;
    }
    lua55_learn_next(frame);
}

STENCIL(lua55_residual_errnnil)(Lua55LearnFrameV1 *frame)
{
    Lua55ValueV1 *target = &frame->values[TARGET_INDEX];
    if (target->tag != LUA55_VALUE_NIL) {
        frame->resume_pc = RESUME_PC;
        frame->status = LUA55_GUARD_FAILED;
        return;
    }
    lua55_residual_next(frame);
}
