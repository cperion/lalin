#include <immintrin.h>
#include <stdint.h>

typedef struct U64LearnedLoopFrame {
    const uint64_t *input;
    uint64_t *output;
    uint64_t count;
    uint64_t addend;
    uint64_t xor_value;
    uint64_t rotate;
} U64LearnedLoopFrame;

#define LEARNED_LOOP(name)                                                      \
    __attribute__((section(".text." #name), aligned(1), noinline, noclone, used)) \
    void name(U64LearnedLoopFrame *frame)

#define APPLY_ADD_0(value, addend) (value)
#define APPLY_ADD_1(value, addend) _mm256_add_epi64(value, addend)
#define APPLY_XOR_0(value, xor_value) (value)
#define APPLY_XOR_1(value, xor_value) _mm256_xor_si256(value, xor_value)
#define APPLY_ROTATE_0(value) (value)
#define APPLY_ROTATE_1(value) _mm256_or_si256(                                 \
    _mm256_slli_epi64(value, 0x11), _mm256_srli_epi64(value, 0x2f))

#define SCALAR_ADD_0(value, addend) (value)
#define SCALAR_ADD_1(value, addend) ((value) + (addend))
#define SCALAR_XOR_0(value, xor_value) (value)
#define SCALAR_XOR_1(value, xor_value) ((value) ^ (xor_value))

static inline uint64_t scalar_rotate(uint64_t value, uint64_t rotate)
{
    rotate &= 63;
    return rotate == 0 ? value : (value << rotate) | (value >> (64 - rotate));
}

#define DEFINE_LOOP(name, use_add, use_xor, use_rotate)                         \
    LEARNED_LOOP(name)                                                           \
    {                                                                            \
        uint64_t index = 0;                                                       \
        __m256i addend = _mm256_set1_epi64x((int64_t)frame->addend);             \
        __m256i xor_value = _mm256_set1_epi64x((int64_t)frame->xor_value);       \
        for (; index + 4 <= frame->count; index += 4) {                          \
            __m256i value = _mm256_loadu_si256(                                  \
                (const __m256i *)(frame->input + index));                        \
            value = APPLY_ADD_##use_add(value, addend);                          \
            value = APPLY_XOR_##use_xor(value, xor_value);                       \
            value = APPLY_ROTATE_##use_rotate(value);                            \
            _mm256_storeu_si256((__m256i *)(frame->output + index), value);      \
        }                                                                        \
        for (; index < frame->count; ++index) {                                  \
            uint64_t value = frame->input[index];                                \
            value = SCALAR_ADD_##use_add(value, frame->addend);                  \
            value = SCALAR_XOR_##use_xor(value, frame->xor_value);               \
            if (use_rotate) value = scalar_rotate(value, frame->rotate);          \
            frame->output[index] = value;                                        \
        }                                                                        \
        _mm256_zeroupper();                                                       \
    }

DEFINE_LOOP(u64_loop_copy, 0, 0, 0)
DEFINE_LOOP(u64_loop_add, 1, 0, 0)
DEFINE_LOOP(u64_loop_xor, 0, 1, 0)
DEFINE_LOOP(u64_loop_add_xor, 1, 1, 0)
DEFINE_LOOP(u64_loop_rotate_imm, 0, 0, 1)
DEFINE_LOOP(u64_loop_add_rotate_imm, 1, 0, 1)
DEFINE_LOOP(u64_loop_xor_rotate_imm, 0, 1, 1)
DEFINE_LOOP(u64_loop_add_xor_rotate_imm, 1, 1, 1)

#define SCALAR_TAIL_ELEMENT(offset, tail, use_add, use_xor, use_rotate)          \
    if ((tail) > (offset)) {                                                     \
        uint64_t value = frame->input[index + (offset)];                         \
        value = SCALAR_ADD_##use_add(value, frame->addend);                      \
        value = SCALAR_XOR_##use_xor(value, frame->xor_value);                   \
        if (use_rotate) value = scalar_rotate(value, frame->rotate);              \
        frame->output[index + (offset)] = value;                                 \
    }

#define DEFINE_TAIL_LOOP(name, use_add, use_xor, use_rotate, tail)              \
    LEARNED_LOOP(name)                                                           \
    {                                                                            \
        uint64_t index = 0;                                                       \
        uint64_t vector_count = frame->count - (tail);                           \
        __m256i addend = _mm256_set1_epi64x((int64_t)frame->addend);             \
        __m256i xor_value = _mm256_set1_epi64x((int64_t)frame->xor_value);       \
        for (; index < vector_count; index += 4) {                               \
            __m256i value = _mm256_loadu_si256(                                  \
                (const __m256i *)(frame->input + index));                        \
            value = APPLY_ADD_##use_add(value, addend);                          \
            value = APPLY_XOR_##use_xor(value, xor_value);                       \
            value = APPLY_ROTATE_##use_rotate(value);                            \
            _mm256_storeu_si256((__m256i *)(frame->output + index), value);      \
        }                                                                        \
        SCALAR_TAIL_ELEMENT(0, tail, use_add, use_xor, use_rotate)               \
        SCALAR_TAIL_ELEMENT(1, tail, use_add, use_xor, use_rotate)               \
        SCALAR_TAIL_ELEMENT(2, tail, use_add, use_xor, use_rotate)               \
        _mm256_zeroupper();                                                       \
    }

#define DEFINE_TAIL_FAMILY(base, use_add, use_xor, use_rotate)                  \
    DEFINE_TAIL_LOOP(base##_tail0, use_add, use_xor, use_rotate, 0)              \
    DEFINE_TAIL_LOOP(base##_tail1, use_add, use_xor, use_rotate, 1)              \
    DEFINE_TAIL_LOOP(base##_tail2, use_add, use_xor, use_rotate, 2)              \
    DEFINE_TAIL_LOOP(base##_tail3, use_add, use_xor, use_rotate, 3)

DEFINE_TAIL_FAMILY(u64_learn_copy, 0, 0, 0)
DEFINE_TAIL_FAMILY(u64_learn_add, 1, 0, 0)
DEFINE_TAIL_FAMILY(u64_learn_xor, 0, 1, 0)
DEFINE_TAIL_FAMILY(u64_learn_add_xor, 1, 1, 0)
DEFINE_TAIL_FAMILY(u64_learn_rotate_imm, 0, 0, 1)
DEFINE_TAIL_FAMILY(u64_learn_add_rotate_imm, 1, 0, 1)
DEFINE_TAIL_FAMILY(u64_learn_xor_rotate_imm, 0, 1, 1)
DEFINE_TAIL_FAMILY(u64_learn_add_xor_rotate_imm, 1, 1, 1)
