#include "opcode_value_v1.h"

/* Batch 15: CONCAT (53) with exact number-to-string conversion.
   R[A] := R[A] .. R[A+1] .. ... .. R[A+B-1]. Every operand must be a
   string, an integer, or a float; integers format with the exact %lld
   digits and floats with exact %.14g (matching stock tostringbuff). The
   converters live in a shared fmt library (liblua55fmt.so) and are called
   through patched absolute addresses (like libm pow), keeping the stencils
   small and their codegen intact. The result is a fresh guest-heap string
   (bytes inline, short <= 40 / long otherwise), materialized each run;
   the residual recomputes from the current operands. __concat
   metamethods remain a visible rejection. */

#define CONCAT_TARGET_INDEX UINT32_C(0x111)
#define CONCAT_BASE_HOLE UINT32_C(0x999)         /* register A (first operand) */
#define CONCAT_COUNT_HOLE UINT32_C(0x0c0d0e0f)   /* B */
#define QUOTE_BASE_HOLE UINT32_C(0x0f1e2d3c)
#define RESUME_PC UINT32_C(0x66778899)
#define DTOA_ADDR_HOLE UINT64_C(0x5152535455565758)
#define ITOA_ADDR_HOLE UINT64_C(0x6162636465666768)
#define LUA55_MINSTR 40

#define GUARD_FAILED(frame) do {            \
    (frame)->resume_pc = RESUME_PC;          \
    (frame)->status = LUA55_GUARD_FAILED;    \
} while (0)

#define REJECT(frame) do {                  \
    (frame)->resume_pc = RESUME_PC;          \
    (frame)->status = LUA55_REJECTED;        \
} while (0)

static int is_string_tag(uint32_t tag)
{
    return tag == LUA55_VALUE_SHORT_STRING || tag == LUA55_VALUE_LONG_STRING;
}

typedef int (*fmt_fn)(double, char *);
typedef int (*itoa_fn)(int64_t, char *);

static inline fmt_fn dtoa_fn(void)
{
    uint64_t addr = DTOA_ADDR_HOLE;
    __asm__ volatile ("" : "+r"(addr));
    union { uint64_t u; fmt_fn fn; } u;
    u.u = addr;
    return u.fn;
}

static inline itoa_fn itoa_fn_get(void)
{
    uint64_t addr = ITOA_ADDR_HOLE;
    __asm__ volatile ("" : "+r"(addr));
    union { uint64_t u; itoa_fn fn; } u;
    u.u = addr;
    return u.fn;
}

/* ------------------------------------------------------------------ */
/* The concat result: a fresh guest string with the bytes inline.       */

static inline __attribute__((always_inline)) Lua55GuestStringV1 *new_concat_string(
    Lua55LearnFrameV1 *frame, uint64_t total_len)
{
    Lua55GuestHeapV1 *heap = frame->heap;
    size_t bytes_size = total_len > 0 ? (size_t)total_len : 1;
    size_t string_size = sizeof(Lua55GuestStringV1) + bytes_size;
    uintptr_t next, aligned;
    Lua55GuestStringV1 *string;
    uint8_t *bytes;
    if (heap == 0 || heap->table_region == 0) return 0;
    next = heap->table_next;
    aligned = (next + 15) & ~(uintptr_t)15;
    if (aligned + string_size > heap->table_region_end) return 0;
    string = (Lua55GuestStringV1 *)aligned;
    bytes = (uint8_t *)(aligned + sizeof(Lua55GuestStringV1));
    string->header.kind = (total_len <= LUA55_MINSTR)
        ? LUA55_OBJECT_SHORT_STRING : LUA55_OBJECT_LONG_STRING;
    string->header.generation = heap->object_count + 1;
    string->length = (uint32_t)total_len;
    string->hash = 0;
    string->bytes = bytes;
    heap->object_count++;
    heap->table_next = aligned + string_size;
    return string;
}

#define CONCAT_TOTAL(frame, base, n, total_out)                          \
    do {                                                                 \
        uint64_t concat_total = 0;                                        \
        int i;                                                           \
        for (i = 0; i < (n); i++) {                                      \
            Lua55ValueV1 *val = &(frame)->values[(base) + i];            \
            if (is_string_tag(val->tag)) {                               \
                concat_total += ((Lua55GuestStringV1 *)val->payload.reference)->length; \
            }                                                            \
            else if (val->tag == LUA55_VALUE_INTEGER) {                  \
                char buf[24];                                            \
                concat_total += (uint32_t)itoa_fn_get()(val->payload.integer, buf); \
            }                                                            \
            else if (val->tag == LUA55_VALUE_FLOAT) {                    \
                char buf[32];                                            \
                concat_total += (uint32_t)dtoa_fn()(val->payload.floating, buf); \
            }                                                            \
            else { REJECT(frame); return; }                              \
        }                                                                \
        total_out = concat_total;                                        \
    } while (0)

#define CONCAT_BUILD(frame, target, base, n, total, res)                 \
    do {                                                                 \
        (res) = new_concat_string(frame, total);                         \
        if ((res) == 0) { REJECT(frame); return; }                       \
        {                                                                \
            uint8_t *out = (uint8_t *)(res)->bytes;                      \
            int i;                                                       \
            for (i = 0; i < (n); i++) {                                  \
                Lua55ValueV1 *val = &(frame)->values[(base) + i];        \
                if (is_string_tag(val->tag)) {                           \
                    Lua55GuestStringV1 *s =                              \
                        (Lua55GuestStringV1 *)val->payload.reference;    \
                    volatile uint8_t *vout = out;                        \
                    uint32_t j;                                          \
                    for (j = 0; j < s->length; j++) vout[j] = s->bytes[j]; \
                    out += s->length;                                    \
                }                                                        \
                else if (val->tag == LUA55_VALUE_INTEGER) {              \
                    char buf[24];                                        \
                    int m = itoa_fn_get()(val->payload.integer, buf);    \
                    volatile uint8_t *vout = out;                        \
                    int j;                                               \
                    for (j = 0; j < m; j++) vout[j] = (uint8_t)buf[j];   \
                    out += m;                                            \
                }                                                        \
                else {                                                   \
                    char buf[32];                                        \
                    int m = dtoa_fn()(val->payload.floating, buf);       \
                    volatile uint8_t *vout = out;                        \
                    int j;                                               \
                    for (j = 0; j < m; j++) vout[j] = (uint8_t)buf[j];   \
                    out += m;                                            \
                }                                                        \
            }                                                            \
        }                                                                \
        SET_TAG((target), total <= LUA55_MINSTR                          \
            ? LUA55_VALUE_SHORT_STRING : LUA55_VALUE_LONG_STRING);       \
        (target)->payload.reference = (uintptr_t)(res);                  \
    } while (0)

STENCIL(lua55_learn_concat)(Lua55LearnFrameV1 *frame)
{
    Lua55ValueV1 *target = &frame->values[CONCAT_TARGET_INDEX];
    Lua55RecordingSlotV1 *slot = next_slot(frame);
    uint32_t base = QUOTE_BASE_HOLE;
    __asm__ volatile ("" : "+r"(base));
    slot->quote = base | 1;
    uint32_t a = CONCAT_BASE_HOLE;
    __asm__ volatile ("" : "+r"(a));
    uint32_t n = CONCAT_COUNT_HOLE;
    __asm__ volatile ("" : "+r"(n));
    uint64_t total;
    CONCAT_TOTAL(frame, a, n, total);
    Lua55GuestStringV1 *res;
    CONCAT_BUILD(frame, target, a, n, total, res);
    lua55_learn_next(frame);
}

STENCIL(lua55_residual_concat)(Lua55LearnFrameV1 *frame)
{
    Lua55ValueV1 *target = &frame->values[CONCAT_TARGET_INDEX];
    uint32_t a = CONCAT_BASE_HOLE;
    __asm__ volatile ("" : "+r"(a));
    uint32_t n = CONCAT_COUNT_HOLE;
    __asm__ volatile ("" : "+r"(n));
    if (frame->heap == 0) { GUARD_FAILED(frame); return; }
    uint64_t total;
    CONCAT_TOTAL(frame, a, n, total);
    Lua55GuestStringV1 *res;
    CONCAT_BUILD(frame, target, a, n, total, res);
    lua55_residual_next(frame);
}
