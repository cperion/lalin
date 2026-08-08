#include <immintrin.h>
#include <stdint.h>

typedef void U64VariantExit(
    __m256i value, __m256i addend, __m256i xor_value,
    __m256i left_count, __m256i right_count);

#define DECLARE_EXIT(name) extern U64VariantExit name##_next
DECLARE_EXIT(u64_copy);
DECLARE_EXIT(u64_add);
DECLARE_EXIT(u64_xor);
DECLARE_EXIT(u64_add_xor);
DECLARE_EXIT(u64_rotate);
DECLARE_EXIT(u64_add_rotate);
DECLARE_EXIT(u64_xor_rotate);
DECLARE_EXIT(u64_add_xor_rotate);
DECLARE_EXIT(u64_rotate_imm);
DECLARE_EXIT(u64_add_rotate_imm);
DECLARE_EXIT(u64_xor_rotate_imm);
DECLARE_EXIT(u64_add_xor_rotate_imm);

#define VARIANT(name)                                                           \
    __attribute__((section(".text." #name), aligned(1), noinline, noclone, used)) \
    void name(__m256i value, __m256i addend, __m256i xor_value,                 \
              __m256i left_count, __m256i right_count)

#define PASS(name, result)                                                      \
    name##_next(result, addend, xor_value, left_count, right_count)

static inline __m256i rotate_u64(
    __m256i value, __m256i left_count, __m256i right_count)
{
    return _mm256_or_si256(
        _mm256_sllv_epi64(value, left_count),
        _mm256_srlv_epi64(value, right_count));
}

/* 0x11 and 0x2f are validated Immediate8 hole sentinels. */
static inline __m256i rotate_u64_immediate(__m256i value)
{
    return _mm256_or_si256(
        _mm256_slli_epi64(value, 0x11),
        _mm256_srli_epi64(value, 0x2f));
}

VARIANT(u64_copy)
{
    PASS(u64_copy, value);
}

VARIANT(u64_add)
{
    PASS(u64_add, _mm256_add_epi64(value, addend));
}

VARIANT(u64_xor)
{
    PASS(u64_xor, _mm256_xor_si256(value, xor_value));
}

VARIANT(u64_add_xor)
{
    PASS(u64_add_xor,
        _mm256_xor_si256(_mm256_add_epi64(value, addend), xor_value));
}

VARIANT(u64_rotate)
{
    PASS(u64_rotate, rotate_u64(value, left_count, right_count));
}

VARIANT(u64_add_rotate)
{
    PASS(u64_add_rotate,
        rotate_u64(_mm256_add_epi64(value, addend), left_count, right_count));
}

VARIANT(u64_xor_rotate)
{
    PASS(u64_xor_rotate,
        rotate_u64(_mm256_xor_si256(value, xor_value), left_count, right_count));
}

VARIANT(u64_add_xor_rotate)
{
    PASS(u64_add_xor_rotate, rotate_u64(
        _mm256_xor_si256(_mm256_add_epi64(value, addend), xor_value),
        left_count, right_count));
}

VARIANT(u64_rotate_imm)
{
    PASS(u64_rotate_imm, rotate_u64_immediate(value));
}

VARIANT(u64_add_rotate_imm)
{
    PASS(u64_add_rotate_imm,
        rotate_u64_immediate(_mm256_add_epi64(value, addend)));
}

VARIANT(u64_xor_rotate_imm)
{
    PASS(u64_xor_rotate_imm,
        rotate_u64_immediate(_mm256_xor_si256(value, xor_value)));
}

VARIANT(u64_add_xor_rotate_imm)
{
    PASS(u64_add_xor_rotate_imm, rotate_u64_immediate(
        _mm256_xor_si256(_mm256_add_epi64(value, addend), xor_value)));
}
