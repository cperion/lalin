#include "opcode_value_v1.h"

/* Batch: numeric for (FORLOOP 74). A terminal like the JMP: the host
   FORPREP boundary prepares the three cells (integer: R[A]=count,
   R[A+1]=step, R[A+2]=idx; float: R[A]=limit, R[A+1]=step, R[A+2]=idx),
   and the FORLOOP updates the control variable, tests the continuation,
   and reports the back-edge or fallthrough pc. The integer/float shapes
   are decided by FORPREP and stay fixed per loop, so a single residual
   branches internally on the step cell's tag (stock lvm.c: OP_FORLOOP
   integer count-down + floatforloop). */

#define BASE_INDEX_HOLE UINT32_C(0x11223344)
#define BACK_EDGE_HOLE  UINT32_C(0x55667788)
#define FALLTHROUGH_HOLE UINT32_C(0x99aabbcc)
#define QUOTE_BASE_HOLE UINT32_C(0x0f1e2d3c)

static inline int64_t lua55_int_add(int64_t a, int64_t b)
{
    return (int64_t)((uint64_t)a + (uint64_t)b);   /* intop wrap */
}

STENCIL(lua55_learn_forloop)(Lua55LearnFrameV1 *frame)
{
    Lua55RecordingSlotV1 *slot = next_slot(frame);
    uint32_t base = QUOTE_BASE_HOLE;
    __asm__ volatile ("" : "+r"(base));
    slot->quote = base | 1;
    uint32_t A = BASE_INDEX_HOLE;
    __asm__ volatile ("" : "+r"(A));
    uint32_t back_edge = BACK_EDGE_HOLE;
    __asm__ volatile ("" : "+r"(back_edge));
    uint32_t fallthrough = FALLTHROUGH_HOLE;
    __asm__ volatile ("" : "+r"(fallthrough));
    Lua55ValueV1 *count_cell = &frame->values[A];
    Lua55ValueV1 *step_cell = &frame->values[A + 1];
    Lua55ValueV1 *idx_cell = &frame->values[A + 2];
    if (step_cell->tag == LUA55_VALUE_INTEGER) {
        int64_t count = count_cell->payload.integer;
        if (count > 0) {
            count_cell->payload.integer = count - 1;
            idx_cell->payload.integer =
                lua55_int_add(idx_cell->payload.integer, step_cell->payload.integer);
            frame->resume_pc = back_edge;
        } else {
            frame->resume_pc = fallthrough;
        }
    } else {
        double idx = idx_cell->payload.floating;
        double step = step_cell->payload.floating;
        double limit = count_cell->payload.floating;
        idx = idx + step;
        if ((step > 0.0 && idx <= limit) || (step < 0.0 && limit <= idx)) {
            idx_cell->payload.floating = idx;
            frame->resume_pc = back_edge;
        } else {
            frame->resume_pc = fallthrough;
        }
    }
    frame->status = LUA55_COMPLETED;
    /* terminal: no lua55_learn_next */
}

STENCIL(lua55_residual_forloop)(Lua55LearnFrameV1 *frame)
{
    uint32_t A = BASE_INDEX_HOLE;
    __asm__ volatile ("" : "+r"(A));
    uint32_t back_edge = BACK_EDGE_HOLE;
    __asm__ volatile ("" : "+r"(back_edge));
    uint32_t fallthrough = FALLTHROUGH_HOLE;
    __asm__ volatile ("" : "+r"(fallthrough));
    Lua55ValueV1 *count_cell = &frame->values[A];
    Lua55ValueV1 *step_cell = &frame->values[A + 1];
    Lua55ValueV1 *idx_cell = &frame->values[A + 2];
    if (step_cell->tag == LUA55_VALUE_INTEGER) {
        int64_t count = count_cell->payload.integer;
        if (count > 0) {
            count_cell->payload.integer = count - 1;
            idx_cell->payload.integer =
                lua55_int_add(idx_cell->payload.integer, step_cell->payload.integer);
            frame->resume_pc = back_edge;
        } else {
            frame->resume_pc = fallthrough;
        }
    } else {
        double idx = idx_cell->payload.floating;
        double step = step_cell->payload.floating;
        double limit = count_cell->payload.floating;
        idx = idx + step;
        if ((step > 0.0 && idx <= limit) || (step < 0.0 && limit <= idx)) {
            idx_cell->payload.floating = idx;
            frame->resume_pc = back_edge;
        } else {
            frame->resume_pc = fallthrough;
        }
    }
    frame->status = LUA55_COMPLETED;
    /* terminal: no lua55_residual_next */
}

/* Self-selecting FORPREP. Both exits are native proper-tail edges. */
#include "opcode_value_v2.h"
#define FORPREP_BODY_LINK UINT64_C(0x1234abcddcba4321)
#define FORPREP_SKIP_LINK UINT64_C(0x2345bcdeedcb5432)

STENCIL(lua55_poly_forprep)(Lua55LearnFrameV1 *frame)
{
    uint32_t A = BASE_INDEX_HOLE;
    __asm__ volatile("" : "+r"(A));
    Lua55ValueV1 *init = &frame->values[A];
    Lua55ValueV1 *limit = &frame->values[A + 1];
    Lua55ValueV1 *step = &frame->values[A + 2];
    uintptr_t target;
    if (init->tag == LUA55_VALUE_INTEGER &&
        limit->tag == LUA55_VALUE_INTEGER && step->tag == LUA55_VALUE_INTEGER) {
        int64_t iv = init->payload.integer;
        int64_t lv = limit->payload.integer;
        int64_t sv = step->payload.integer;
        if (sv == 0) { frame->status = LUA55_REJECTED; LUA55_CPS_HOST_EXIT(frame); }
        if ((sv > 0 && iv > lv) || (sv < 0 && iv < lv)) {
            target = (uintptr_t)FORPREP_SKIP_LINK;
        } else {
            uint64_t distance = sv > 0
                ? (uint64_t)lv - (uint64_t)iv
                : (uint64_t)iv - (uint64_t)lv;
            uint64_t stride = sv > 0 ? (uint64_t)sv : UINT64_C(0) - (uint64_t)sv;
            SET_TAG(init, LUA55_VALUE_INTEGER);
            init->payload.integer = (int64_t)(distance / stride);
            SET_TAG(limit, LUA55_VALUE_INTEGER);
            limit->payload.integer = sv;
            SET_TAG(step, LUA55_VALUE_INTEGER);
            step->payload.integer = iv;
            target = (uintptr_t)FORPREP_BODY_LINK;
        }
    } else if ((init->tag == LUA55_VALUE_INTEGER || init->tag == LUA55_VALUE_FLOAT) &&
               (limit->tag == LUA55_VALUE_INTEGER || limit->tag == LUA55_VALUE_FLOAT) &&
               (step->tag == LUA55_VALUE_INTEGER || step->tag == LUA55_VALUE_FLOAT)) {
        double iv = init->tag == LUA55_VALUE_INTEGER
            ? (double)init->payload.integer : init->payload.floating;
        double lv = limit->tag == LUA55_VALUE_INTEGER
            ? (double)limit->payload.integer : limit->payload.floating;
        double sv = step->tag == LUA55_VALUE_INTEGER
            ? (double)step->payload.integer : step->payload.floating;
        if (sv == 0.0) { frame->status = LUA55_REJECTED; LUA55_CPS_HOST_EXIT(frame); }
        if ((sv > 0.0 && lv < iv) || (sv < 0.0 && iv < lv)) {
            target = (uintptr_t)FORPREP_SKIP_LINK;
        } else {
            SET_TAG(init, LUA55_VALUE_FLOAT); init->payload.floating = lv;
            SET_TAG(limit, LUA55_VALUE_FLOAT); limit->payload.floating = sv;
            SET_TAG(step, LUA55_VALUE_FLOAT); step->payload.floating = iv;
            target = (uintptr_t)FORPREP_BODY_LINK;
        }
    } else { frame->status = LUA55_REJECTED; LUA55_CPS_HOST_EXIT(frame); }
    __asm__ volatile("" : "+r"(target));
    ((Lua55OpcodeEntryV1)target)(frame);
}

#define FORLOOP_BACK_LINK UINT64_C(0x1122334455667788)
#define FORLOOP_FALL_LINK UINT64_C(0x0ddc0ffeebadf00d)

STENCIL(lua55_poly_forloop)(Lua55LearnFrameV1 *frame)
{
    uint32_t A = BASE_INDEX_HOLE;
    __asm__ volatile("" : "+r"(A));
    Lua55ValueV1 *count_cell = &frame->values[A];
    Lua55ValueV1 *step_cell = &frame->values[A + 1];
    Lua55ValueV1 *idx_cell = &frame->values[A + 2];
    uintptr_t target;
    if (step_cell->tag == LUA55_VALUE_INTEGER) {
        int64_t count = count_cell->payload.integer;
        if (count > 0) {
            count_cell->payload.integer = count - 1;
            idx_cell->payload.integer =
                lua55_int_add(idx_cell->payload.integer, step_cell->payload.integer);
            target = (uintptr_t)FORLOOP_BACK_LINK;
        } else target = (uintptr_t)FORLOOP_FALL_LINK;
    } else {
        double idx = idx_cell->payload.floating;
        double sv = step_cell->payload.floating;
        double lv = count_cell->payload.floating;
        idx = idx + sv;
        if ((sv > 0.0 && idx <= lv) || (sv < 0.0 && lv <= idx)) {
            idx_cell->payload.floating = idx;
            target = (uintptr_t)FORLOOP_BACK_LINK;
        } else target = (uintptr_t)FORLOOP_FALL_LINK;
    }
    __asm__ volatile("" : "+r"(target));
    ((Lua55OpcodeEntryV1)target)(frame);
}
