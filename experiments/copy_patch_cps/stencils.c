#include <stdint.h>

typedef struct CopyPatchCpsFrame {
    int64_t limit;
    int64_t result;
} CopyPatchCpsFrame;

/*
 * x86-64 SysV native CPS protocol:
 *   rdi = frame, rsi = accumulator, rdx = limit,
 *   rcx = step,  r8 = index,       r9 = reserved.
 *
 * Undefined successor functions are typed relocation identities. GCC must
 * lower each call in tail position to a direct jump with an ELF relocation.
 */
typedef void CopyPatchCpsExit(
    CopyPatchCpsFrame *, int64_t, int64_t, int64_t, int64_t);

extern CopyPatchCpsExit copy_patch_entry_next;
extern CopyPatchCpsExit copy_patch_loop_repeat;
extern CopyPatchCpsExit copy_patch_loop_exit;
extern CopyPatchCpsExit copy_patch_body_next;

#define STENCIL(name)                                                           \
    __attribute__((section(".text." #name), aligned(1), noinline, noclone, used)) \
    void name

STENCIL(copy_patch_stencil_entry)(CopyPatchCpsFrame *frame)
{
    copy_patch_entry_next(frame, 0, frame->limit, 1, 1);
}

STENCIL(copy_patch_stencil_loop)(
    CopyPatchCpsFrame *frame,
    int64_t accumulator,
    int64_t limit,
    int64_t step,
    int64_t index)
{
    if (index <= limit) {
        copy_patch_loop_repeat(frame, accumulator, limit, step, index);
    } else {
        copy_patch_loop_exit(frame, accumulator, limit, step, index);
    }
}

STENCIL(copy_patch_stencil_body)(
    CopyPatchCpsFrame *frame,
    int64_t accumulator,
    int64_t limit,
    int64_t step,
    int64_t index)
{
    copy_patch_body_next(
        frame, accumulator + index, limit, step, index + step);
}

STENCIL(copy_patch_stencil_finish)(
    CopyPatchCpsFrame *frame,
    int64_t accumulator,
    int64_t limit,
    int64_t step,
    int64_t index)
{
    (void)limit;
    (void)step;
    (void)index;
    frame->result = accumulator;
}
