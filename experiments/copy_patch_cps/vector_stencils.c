#include <immintrin.h>
#include <stdint.h>

typedef struct CopyPatchF64MapFrameV1 {
    const double *input;
    double *output;
    uint64_t count;
    double scalar0;
    double scalar1;
    double scalar2;
    double scalar3;
} CopyPatchF64MapFrameV1;

typedef void CopyPatchF64MapExit(
    CopyPatchF64MapFrameV1 *,
    const double *,
    double *,
    uint64_t,
    __m256d,
    __m256d,
    __m256d,
    __m256d,
    __m256d);

extern CopyPatchF64MapExit cpv_entry_next;
extern CopyPatchF64MapExit cpv_vector_full;
extern CopyPatchF64MapExit cpv_vector_tail;
extern CopyPatchF64MapExit cpv_vector_load_next;
extern CopyPatchF64MapExit cpv_vector_store_next;
extern CopyPatchF64MapExit cpv_scalar_some;
extern CopyPatchF64MapExit cpv_scalar_done;
extern CopyPatchF64MapExit cpv_scalar_load_next;
extern CopyPatchF64MapExit cpv_scalar_store_next;
extern CopyPatchF64MapExit cpv_add0_next;
extern CopyPatchF64MapExit cpv_add1_next;
extern CopyPatchF64MapExit cpv_add2_next;
extern CopyPatchF64MapExit cpv_add3_next;
extern CopyPatchF64MapExit cpv_mul0_next;
extern CopyPatchF64MapExit cpv_mul1_next;
extern CopyPatchF64MapExit cpv_mul2_next;
extern CopyPatchF64MapExit cpv_mul3_next;
extern CopyPatchF64MapExit cpv_square_next;

#define VECTOR_STENCIL(name)                                                    \
    __attribute__((section(".text." #name), aligned(1), noinline, noclone, used)) \
    void name

#define VECTOR_ARGS                                                             \
    CopyPatchF64MapFrameV1 *frame, const double *input, double *output,          \
    uint64_t remaining, __m256d value, __m256d scalar0, __m256d scalar1,         \
    __m256d scalar2, __m256d scalar3

#define VECTOR_PASS(next, next_value)                                           \
    next(frame, input, output, remaining, next_value,                            \
         scalar0, scalar1, scalar2, scalar3)

VECTOR_STENCIL(cpv_stencil_entry)(CopyPatchF64MapFrameV1 *frame)
{
    __m256d zero = _mm256_setzero_pd();
    cpv_entry_next(
        frame, frame->input, frame->output, frame->count, zero,
        _mm256_broadcast_sd(&frame->scalar0),
        _mm256_broadcast_sd(&frame->scalar1),
        _mm256_broadcast_sd(&frame->scalar2),
        _mm256_broadcast_sd(&frame->scalar3));
}

VECTOR_STENCIL(cpv_stencil_vector_test)(VECTOR_ARGS)
{
    if (remaining >= 4) {
        cpv_vector_full(
            frame, input, output, remaining, value,
            scalar0, scalar1, scalar2, scalar3);
    } else {
        cpv_vector_tail(
            frame, input, output, remaining, value,
            scalar0, scalar1, scalar2, scalar3);
    }
}

VECTOR_STENCIL(cpv_stencil_vector_load)(VECTOR_ARGS)
{
    VECTOR_PASS(cpv_vector_load_next, _mm256_loadu_pd(input));
}

VECTOR_STENCIL(cpv_stencil_vector_store)(VECTOR_ARGS)
{
    _mm256_storeu_pd(output, value);
    cpv_vector_store_next(
        frame, input + 4, output + 4, remaining - 4, value,
        scalar0, scalar1, scalar2, scalar3);
}

VECTOR_STENCIL(cpv_stencil_scalar_test)(VECTOR_ARGS)
{
    if (remaining != 0) {
        cpv_scalar_some(
            frame, input, output, remaining, value,
            scalar0, scalar1, scalar2, scalar3);
    } else {
        cpv_scalar_done(
            frame, input, output, remaining, value,
            scalar0, scalar1, scalar2, scalar3);
    }
}

VECTOR_STENCIL(cpv_stencil_scalar_load)(VECTOR_ARGS)
{
    VECTOR_PASS(cpv_scalar_load_next, _mm256_broadcast_sd(input));
}

VECTOR_STENCIL(cpv_stencil_scalar_store)(VECTOR_ARGS)
{
    _mm_store_sd(output, _mm256_castpd256_pd128(value));
    cpv_scalar_store_next(
        frame, input + 1, output + 1, remaining - 1, value,
        scalar0, scalar1, scalar2, scalar3);
}

#define ADD_STENCIL(number)                                                     \
    VECTOR_STENCIL(cpv_stencil_add##number)(VECTOR_ARGS)                        \
    {                                                                            \
        VECTOR_PASS(cpv_add##number##_next, _mm256_add_pd(value, scalar##number)); \
    }

#define MUL_STENCIL(number)                                                     \
    VECTOR_STENCIL(cpv_stencil_mul##number)(VECTOR_ARGS)                        \
    {                                                                            \
        VECTOR_PASS(cpv_mul##number##_next, _mm256_mul_pd(value, scalar##number)); \
    }

ADD_STENCIL(0)
ADD_STENCIL(1)
ADD_STENCIL(2)
ADD_STENCIL(3)
MUL_STENCIL(0)
MUL_STENCIL(1)
MUL_STENCIL(2)
MUL_STENCIL(3)

VECTOR_STENCIL(cpv_stencil_square)(VECTOR_ARGS)
{
    VECTOR_PASS(cpv_square_next, _mm256_mul_pd(value, value));
}

VECTOR_STENCIL(cpv_stencil_finish)(VECTOR_ARGS)
{
    (void)frame;
    (void)input;
    (void)output;
    (void)remaining;
    (void)value;
    (void)scalar0;
    (void)scalar1;
    (void)scalar2;
    (void)scalar3;
    _mm256_zeroupper();
}
