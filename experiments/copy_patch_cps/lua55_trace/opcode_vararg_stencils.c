#include "opcode_value_v1.h"

/* Batch 11: VARARG (80) and GETVARG (81).
   The host arranges vararg calls: the extra args live in the callee
   frame's registers R[numparams .. numparams+count-1] and the frame's
   vararg_count field carries the count. VARARGPREP (83) is a host-setup
   boundary (the plan builder skips it; the host sets the frame before the
   first block). VARARG copies the varargs into R[A..]; GETVARG reads the
   vararg at a runtime index (integer) or the count ("n" string). Both
   recompute from the current frame each run. */

#define TARGET_INDEX UINT32_C(0x111)
#define KEY_INDEX UINT32_C(0x555)
#define QUOTE_BASE_HOLE UINT32_C(0x0f1e2d3c)
#define RESUME_PC UINT32_C(0x66778899)
#define NFIX_HOLE UINT32_C(0x0d0e0f10)       /* numparams */
#define WANTED_HOLE UINT32_C(0x1d1e1f20)     /* VARARG: C-1; 0xFFFFFFFF = all */
#define BASE_REG_HOLE UINT32_C(0x999)        /* register A (target + copy base) */

#define REJECT(frame) do {                  \
    (frame)->resume_pc = RESUME_PC;          \
    (frame)->status = LUA55_REJECTED;        \
} while (0)

STENCIL(lua55_learn_vararg)(Lua55LearnFrameV1 *frame)
{
    Lua55RecordingSlotV1 *slot = next_slot(frame);
    uint32_t base = QUOTE_BASE_HOLE;
    __asm__ volatile ("" : "+r"(base));
    slot->quote = base | 1;
    uint32_t nfix = NFIX_HOLE;
    __asm__ volatile ("" : "+r"(nfix));
    uint32_t wanted = WANTED_HOLE;
    __asm__ volatile ("" : "+r"(wanted));
    uint32_t target_reg = BASE_REG_HOLE;
    __asm__ volatile ("" : "+r"(target_reg));
    uint32_t nargs = frame->vararg_count;
    uint32_t touse = (wanted == 0xFFFFFFFF) ? nargs : (nargs > wanted ? wanted : nargs);
    uint32_t i;
    /* backward copy: the destination may overlap the source registers */
    for (i = touse; i > 0; i--)
        frame->values[target_reg + i - 1] = frame->values[nfix + i - 1];
    lua55_learn_next(frame);
}

STENCIL(lua55_residual_vararg)(Lua55LearnFrameV1 *frame)
{
    uint32_t nfix = NFIX_HOLE;
    __asm__ volatile ("" : "+r"(nfix));
    uint32_t wanted = WANTED_HOLE;
    __asm__ volatile ("" : "+r"(wanted));
    uint32_t target_reg = BASE_REG_HOLE;
    __asm__ volatile ("" : "+r"(target_reg));
    uint32_t nargs = frame->vararg_count;
    uint32_t touse = (wanted == 0xFFFFFFFF) ? nargs : (nargs > wanted ? wanted : nargs);
    uint32_t i;
    for (i = touse; i > 0; i--)
        frame->values[target_reg + i - 1] = frame->values[nfix + i - 1];
    lua55_residual_next(frame);
}

STENCIL(lua55_learn_getvarg)(Lua55LearnFrameV1 *frame)
{
    Lua55ValueV1 *target = &frame->values[TARGET_INDEX];
    Lua55ValueV1 *key = &frame->values[KEY_INDEX];
    Lua55RecordingSlotV1 *slot = next_slot(frame);
    uint32_t base = QUOTE_BASE_HOLE;
    __asm__ volatile ("" : "+r"(base));
    slot->quote = base | 1;
    uint32_t nfix = NFIX_HOLE;
    __asm__ volatile ("" : "+r"(nfix));
    uint32_t nargs = frame->vararg_count;
    Lua55ValueV1 nil_value;
    SET_TAG(&nil_value, LUA55_VALUE_NIL);
    nil_value.payload.reference = 0;
    if (key->tag == LUA55_VALUE_INTEGER) {
        int64_t n = key->payload.integer;
        if (n >= 1 && (uint64_t)n <= nargs)
            *target = frame->values[nfix + (uint32_t)n - 1];
        else
            *target = nil_value;
    }
    else if (key->tag == LUA55_VALUE_SHORT_STRING ||
             key->tag == LUA55_VALUE_LONG_STRING) {
        Lua55GuestStringV1 *s = (Lua55GuestStringV1 *)key->payload.reference;
        if (s != 0 && s->length == 1 && s->bytes[0] == 'n') {
            SET_TAG(target, LUA55_VALUE_INTEGER);
            target->payload.integer = (int64_t)nargs;
        }
        else {
            *target = nil_value;
        }
    }
    else {
        *target = nil_value;
    }
    lua55_learn_next(frame);
}

STENCIL(lua55_residual_getvarg)(Lua55LearnFrameV1 *frame)
{
    Lua55ValueV1 *target = &frame->values[TARGET_INDEX];
    Lua55ValueV1 *key = &frame->values[KEY_INDEX];
    uint32_t nfix = NFIX_HOLE;
    __asm__ volatile ("" : "+r"(nfix));
    uint32_t nargs = frame->vararg_count;
    Lua55ValueV1 nil_value;
    SET_TAG(&nil_value, LUA55_VALUE_NIL);
    nil_value.payload.reference = 0;
    if (key->tag == LUA55_VALUE_INTEGER) {
        int64_t n = key->payload.integer;
        if (n >= 1 && (uint64_t)n <= nargs)
            *target = frame->values[nfix + (uint32_t)n - 1];
        else
            *target = nil_value;
    }
    else if (key->tag == LUA55_VALUE_SHORT_STRING ||
             key->tag == LUA55_VALUE_LONG_STRING) {
        Lua55GuestStringV1 *s = (Lua55GuestStringV1 *)key->payload.reference;
        if (s != 0 && s->length == 1 && s->bytes[0] == 'n') {
            SET_TAG(target, LUA55_VALUE_INTEGER);
            target->payload.integer = (int64_t)nargs;
        }
        else {
            *target = nil_value;
        }
    }
    else {
        *target = nil_value;
    }
    lua55_residual_next(frame);
}
