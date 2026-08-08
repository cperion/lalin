#include <stdint.h>

typedef union Lua55TraceNumericPayloadV1 {
    int64_t integer;
    double floating;
} Lua55TraceNumericPayloadV1;

typedef struct Lua55TraceNumericValueV1 {
    uint32_t tag;
    uint32_t reserved;
    Lua55TraceNumericPayloadV1 payload;
} Lua55TraceNumericValueV1;

typedef struct Lua55TraceNumericFrameV1 {
    Lua55TraceNumericValueV1 *values;
    uint32_t count;
    uint32_t top;
    uint32_t resume_pc;
    uint32_t generation;
    uint32_t learned;
} Lua55TraceNumericFrameV1;

#define STENCIL(name)                                                           \
    __attribute__((section(".text." #name), aligned(1), noinline, noclone, used)) \
    void name

#define TARGET_INDEX UINT32_C(0x111)
#define LIMIT_INDEX UINT32_C(0x444)
#define STEP_INDEX UINT32_C(0x555)
#define SUM_INDEX UINT32_C(0x666)

#define LEARNED_BACKEDGE  1u
#define LEARNED_COMPLETED 2u
#define LEARNED_REJECTED  3u

/* Native learner: execute the first fused backedge and record the outcome.
   The whole recording decision (tag guards, zero-trip, backedge) is C;
   Lua only links the residual quotation after this returns. */
STENCIL(lua55_trace_learn_integer_add_forloop)(Lua55TraceNumericFrameV1 *frame)
{
    Lua55TraceNumericValueV1 *sum = &frame->values[SUM_INDEX];
    Lua55TraceNumericValueV1 *index = &frame->values[TARGET_INDEX];
    Lua55TraceNumericValueV1 *limit = &frame->values[LIMIT_INDEX];
    Lua55TraceNumericValueV1 *step = &frame->values[STEP_INDEX];
    if (sum->tag != 1 || index->tag != 1 || limit->tag != 1 || step->tag != 1) {
        frame->learned = LEARNED_REJECTED;
        frame->resume_pc = UINT32_C(0x66778899);
        return;
    }
    int64_t s = sum->payload.integer;
    int64_t i = index->payload.integer;
    int64_t lim = limit->payload.integer;
    int64_t st = step->payload.integer;
    if (st == 0) {
        frame->learned = LEARNED_REJECTED;
        frame->resume_pc = UINT32_C(0x66778899);
        return;
    }
    /* zero-trip: FORPREP skips the body when the initial index is out of range */
    if ((st > 0 && i > lim) || (st < 0 && i < lim)) {
        frame->learned = LEARNED_COMPLETED;
        frame->resume_pc = UINT32_C(0x66778899);
        return;
    }
    s = (int64_t)((uint64_t)s + (uint64_t)i);
    i = (int64_t)((uint64_t)i + (uint64_t)st);
    sum->payload.integer = s;
    index->payload.integer = i;
    frame->learned = ((st > 0 && i <= lim) || (st < 0 && i >= lim))
        ? LEARNED_BACKEDGE : LEARNED_COMPLETED;
    frame->resume_pc = UINT32_C(0x66778899);
}

/* The residual recurrence: finish the loop after the learner's first backedge. */
STENCIL(lua55_trace_integer_add_forloop)(Lua55TraceNumericFrameV1 *frame)
{
    int64_t sum = frame->values[SUM_INDEX].payload.integer;
    int64_t index = frame->values[TARGET_INDEX].payload.integer;
    int64_t limit = frame->values[LIMIT_INDEX].payload.integer;
    int64_t step = frame->values[STEP_INDEX].payload.integer;
    /* zero-trip guard: FORPREP skips the body when the initial index is out
       of range. Complete without touching sum or index. */
    if ((step > 0 && index > limit) || (step < 0 && index < limit)) {
        frame->resume_pc = UINT32_C(0x66778899);
        return;
    }
    do {
        sum = (int64_t)((uint64_t)sum + (uint64_t)index);
        index = (int64_t)((uint64_t)index + (uint64_t)step);
    } while ((step > 0 && index <= limit) || (step < 0 && index >= limit));
    frame->values[SUM_INDEX].tag = 1;
    frame->values[SUM_INDEX].payload.integer = sum;
    frame->values[TARGET_INDEX].payload.integer = index;
    frame->resume_pc = UINT32_C(0x66778899);
}
