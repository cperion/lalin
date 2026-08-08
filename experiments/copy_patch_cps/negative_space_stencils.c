#include <immintrin.h>
#include <stdint.h>

#define SUPERSTENCIL(name)                                                      \
    __attribute__((section(".text." #name), aligned(1), noinline, noclone, used)) \
    void name

typedef struct {
    const double *input;
    uint64_t count;
    double result;
} F64ReductionV1Frame;

SUPERSTENCIL(ns_f64_reduction)(F64ReductionV1Frame *frame)
{
    uint64_t index = 0;
    __m256d sum0 = _mm256_setzero_pd();
    __m256d sum1 = _mm256_setzero_pd();
    __m256d sum2 = _mm256_setzero_pd();
    __m256d sum3 = _mm256_setzero_pd();
    for (; index + 16 <= frame->count; index += 16) {
        sum0 = _mm256_add_pd(sum0, _mm256_loadu_pd(frame->input + index));
        sum1 = _mm256_add_pd(sum1, _mm256_loadu_pd(frame->input + index + 4));
        sum2 = _mm256_add_pd(sum2, _mm256_loadu_pd(frame->input + index + 8));
        sum3 = _mm256_add_pd(sum3, _mm256_loadu_pd(frame->input + index + 12));
    }
    __m256d sum = _mm256_add_pd(
        _mm256_add_pd(sum0, sum1), _mm256_add_pd(sum2, sum3));
    __m128d pair = _mm_add_pd(
        _mm256_castpd256_pd128(sum), _mm256_extractf128_pd(sum, 1));
    double result = _mm_cvtsd_f64(pair) + _mm_cvtsd_f64(_mm_unpackhi_pd(pair, pair));
    for (; index < frame->count; ++index) result += frame->input[index];
    frame->result = result;
    _mm256_zeroupper();
}

typedef struct {
    const uint8_t *input;
    uint64_t count;
    uint8_t needle;
    uint64_t found;
} U8ScanV1Frame;

SUPERSTENCIL(ns_u8_scan)(U8ScanV1Frame *frame)
{
    uint64_t index = 0;
    __m256i needle = _mm256_set1_epi8((char)frame->needle);
    for (; index + 32 <= frame->count; index += 32) {
        __m256i bytes = _mm256_loadu_si256((const __m256i *)(frame->input + index));
        uint32_t mask = (uint32_t)_mm256_movemask_epi8(_mm256_cmpeq_epi8(bytes, needle));
        if (mask != 0) {
            frame->found = index + (uint64_t)__builtin_ctz(mask);
            _mm256_zeroupper();
            return;
        }
    }
    for (; index < frame->count; ++index) {
        if (frame->input[index] == frame->needle) {
            frame->found = index;
            _mm256_zeroupper();
            return;
        }
    }
    frame->found = frame->count;
    _mm256_zeroupper();
}

typedef struct {
    const double *left;
    const double *right;
    double *output;
    uint64_t count;
    double scale;
} F64ZipMapV1Frame;

#define DEFINE_F64_ZIP(name, vector_expression, scalar_expression)               \
    SUPERSTENCIL(name)(F64ZipMapV1Frame *frame)                                  \
    {                                                                            \
        uint64_t index = 0;                                                       \
        for (; index + 4 <= frame->count; index += 4) {                          \
            __m256d left = _mm256_loadu_pd(frame->left + index);                 \
            __m256d right = _mm256_loadu_pd(frame->right + index);               \
            _mm256_storeu_pd(frame->output + index, (vector_expression));        \
        }                                                                        \
        for (; index < frame->count; ++index) {                                  \
            double left = frame->left[index], right = frame->right[index];       \
            frame->output[index] = (scalar_expression);                          \
        }                                                                        \
        _mm256_zeroupper();                                                       \
    }

DEFINE_F64_ZIP(ns_f64_zip_add, _mm256_add_pd(left, right), left + right)
DEFINE_F64_ZIP(ns_f64_zip_multiply, _mm256_mul_pd(left, right), left * right)

SUPERSTENCIL(ns_f64_zip_map)(F64ZipMapV1Frame *frame)
{
    uint64_t index = 0;
    __m256d scale = _mm256_broadcast_sd(&frame->scale);
    for (; index + 4 <= frame->count; index += 4) {
        __m256d left = _mm256_loadu_pd(frame->left + index);
        __m256d right = _mm256_loadu_pd(frame->right + index);
        _mm256_storeu_pd(frame->output + index,
            _mm256_add_pd(_mm256_mul_pd(left, scale), right));
    }
    for (; index < frame->count; ++index) {
        frame->output[index] = frame->left[index] * frame->scale + frame->right[index];
    }
    _mm256_zeroupper();
}

typedef struct {
    const float *input;
    float *output;
    uint64_t count;
    float scalar0;
    float scalar1;
    float scalar2;
    float scalar3;
} F32MapPipelineV1Frame;

SUPERSTENCIL(ns_f32_map)(F32MapPipelineV1Frame *frame)
{
    uint64_t index = 0;
    __m256 scalar0 = _mm256_broadcast_ss(&frame->scalar0);
    __m256 scalar1 = _mm256_broadcast_ss(&frame->scalar1);
    __m256 scalar2 = _mm256_broadcast_ss(&frame->scalar2);
    __m256 scalar3 = _mm256_broadcast_ss(&frame->scalar3);
    for (; index + 8 <= frame->count; index += 8) {
        __m256 value = _mm256_loadu_ps(frame->input + index);
        value = _mm256_add_ps(value, scalar0);
        value = _mm256_mul_ps(value, scalar1);
        value = _mm256_add_ps(value, scalar2);
        value = _mm256_mul_ps(value, scalar3);
        value = _mm256_mul_ps(value, value);
        _mm256_storeu_ps(frame->output + index, value);
    }
    for (; index < frame->count; ++index) {
        float value = frame->input[index];
        value += frame->scalar0;
        value *= frame->scalar1;
        value += frame->scalar2;
        value *= frame->scalar3;
        frame->output[index] = value * value;
    }
    _mm256_zeroupper();
}

typedef struct {
    const uint64_t *input;
    uint64_t *output;
    uint64_t count;
    uint64_t addend;
    uint64_t xor_value;
    uint64_t rotate;
} U64BulkV1Frame;

static inline uint64_t rotate_left_u64(uint64_t value, uint64_t count)
{
    count &= 63;
    return count == 0 ? value : (value << count) | (value >> (64 - count));
}

SUPERSTENCIL(ns_u64_bulk)(U64BulkV1Frame *frame)
{
    uint64_t index = 0;
    uint64_t rotate = frame->rotate & 63;
    __m256i addend = _mm256_set1_epi64x((int64_t)frame->addend);
    __m256i xor_value = _mm256_set1_epi64x((int64_t)frame->xor_value);
    __m256i left_count = _mm256_set1_epi64x((int64_t)rotate);
    __m256i right_count = _mm256_set1_epi64x((int64_t)(64 - rotate));
    for (; index + 4 <= frame->count; index += 4) {
        __m256i value = _mm256_loadu_si256((const __m256i *)(frame->input + index));
        value = _mm256_xor_si256(_mm256_add_epi64(value, addend), xor_value);
        value = _mm256_or_si256(
            _mm256_sllv_epi64(value, left_count), _mm256_srlv_epi64(value, right_count));
        _mm256_storeu_si256((__m256i *)(frame->output + index), value);
    }
    for (; index < frame->count; ++index) {
        uint64_t value = (frame->input[index] + frame->addend) ^ frame->xor_value;
        frame->output[index] = rotate_left_u64(value, rotate);
    }
    _mm256_zeroupper();
}

typedef union { double value; uint64_t bits; } F64Bits;

SUPERSTENCIL(ns_f64_min_number)(F64ReductionV1Frame *frame)
{
    F64Bits result = { .bits = 0 };
    int present = 0;
    for (uint64_t index = 0; index < frame->count; ++index) {
        F64Bits value = { .value = frame->input[index] };
        if (value.value == value.value) {
            if (!present || value.value < result.value ||
                (value.value == result.value && (value.bits >> 63) > (result.bits >> 63))) {
                result = value;
                present = 1;
            }
        }
    }
    if (present) frame->result = result.value;
    else {
        uint64_t nan_bits = UINT64_C(0x7ff8000000000000);
        __asm__ volatile ("" : "+r"(nan_bits));
        __builtin_memcpy(&frame->result, &nan_bits, sizeof(nan_bits));
    }
}

SUPERSTENCIL(ns_f64_max_number)(F64ReductionV1Frame *frame)
{
    F64Bits result = { .bits = 0 };
    int present = 0;
    for (uint64_t index = 0; index < frame->count; ++index) {
        F64Bits value = { .value = frame->input[index] };
        if (value.value == value.value) {
            if (!present || value.value > result.value ||
                (value.value == result.value && (value.bits >> 63) < (result.bits >> 63))) {
                result = value;
                present = 1;
            }
        }
    }
    if (present) frame->result = result.value;
    else {
        uint64_t nan_bits = UINT64_C(0x7ff8000000000000);
        __asm__ volatile ("" : "+r"(nan_bits));
        __builtin_memcpy(&frame->result, &nan_bits, sizeof(nan_bits));
    }
}

typedef struct {
    const uint8_t *input;
    uint64_t count;
    uint8_t needle0;
    uint8_t needle1;
    uint8_t needle2;
    uint8_t needle3;
    uint64_t result;
} U8ScanSetV1Frame;

#define U8_SET_MASK_2(bytes, needle0, needle1)                                   \
    ((uint32_t)_mm256_movemask_epi8(_mm256_or_si256(                            \
        _mm256_cmpeq_epi8(bytes, needle0), _mm256_cmpeq_epi8(bytes, needle1))))

#define U8_SET_MASK_4(bytes, needle0, needle1, needle2, needle3)                \
    ((uint32_t)_mm256_movemask_epi8(_mm256_or_si256(                            \
        _mm256_or_si256(_mm256_cmpeq_epi8(bytes, needle0),                      \
                         _mm256_cmpeq_epi8(bytes, needle1)),                     \
        _mm256_or_si256(_mm256_cmpeq_epi8(bytes, needle2),                      \
                         _mm256_cmpeq_epi8(bytes, needle3)))))

#define DEFINE_FIND_ANY(name, set_mask, scalar_match)                           \
    SUPERSTENCIL(name)(U8ScanSetV1Frame *frame)                                 \
    {                                                                            \
        uint64_t index = 0;                                                       \
        __m256i n0 = _mm256_set1_epi8((char)frame->needle0);                     \
        __m256i n1 = _mm256_set1_epi8((char)frame->needle1);                     \
        __m256i n2 = _mm256_set1_epi8((char)frame->needle2);                     \
        __m256i n3 = _mm256_set1_epi8((char)frame->needle3);                     \
        for (; index + 32 <= frame->count; index += 32) {                        \
            __m256i bytes = _mm256_loadu_si256(                                  \
                (const __m256i *)(frame->input + index));                        \
            uint32_t mask = set_mask;                                            \
            if (mask) { frame->result = index + __builtin_ctz(mask);             \
                _mm256_zeroupper(); return; }                                    \
        }                                                                        \
        for (; index < frame->count; ++index) {                                  \
            uint8_t value = frame->input[index];                                 \
            if (scalar_match) { frame->result = index; _mm256_zeroupper(); return; } \
        }                                                                        \
        frame->result = frame->count;                                            \
        _mm256_zeroupper();                                                       \
    }

DEFINE_FIND_ANY(ns_u8_find_any2, U8_SET_MASK_2(bytes, n0, n1),
    value == frame->needle0 || value == frame->needle1)
DEFINE_FIND_ANY(ns_u8_find_any4, U8_SET_MASK_4(bytes, n0, n1, n2, n3),
    value == frame->needle0 || value == frame->needle1 ||
    value == frame->needle2 || value == frame->needle3)

SUPERSTENCIL(ns_u8_count_byte)(U8ScanSetV1Frame *frame)
{
    uint64_t index = 0, result = 0;
    __m256i needle = _mm256_set1_epi8((char)frame->needle0);
    for (; index + 32 <= frame->count; index += 32) {
        __m256i bytes = _mm256_loadu_si256((const __m256i *)(frame->input + index));
        uint32_t mask = (uint32_t)_mm256_movemask_epi8(_mm256_cmpeq_epi8(bytes, needle));
        result += (uint64_t)__builtin_popcount(mask);
    }
    for (; index < frame->count; ++index) result += frame->input[index] == frame->needle0;
    frame->result = result;
    _mm256_zeroupper();
}

SUPERSTENCIL(ns_u8_all_equal)(U8ScanSetV1Frame *frame)
{
    uint64_t index = 0;
    __m256i needle = _mm256_set1_epi8((char)frame->needle0);
    for (; index + 32 <= frame->count; index += 32) {
        __m256i bytes = _mm256_loadu_si256((const __m256i *)(frame->input + index));
        uint32_t mask = (uint32_t)_mm256_movemask_epi8(_mm256_cmpeq_epi8(bytes, needle));
        if (mask != UINT32_MAX) { frame->result = 0; _mm256_zeroupper(); return; }
    }
    for (; index < frame->count; ++index) {
        if (frame->input[index] != frame->needle0) {
            frame->result = 0; _mm256_zeroupper(); return;
        }
    }
    frame->result = 1;
    _mm256_zeroupper();
}
