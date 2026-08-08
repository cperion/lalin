#include <stdint.h>
#include <string.h>
#include <sys/mman.h>

typedef struct U64LearnedLoopFrame {
    const uint64_t *input;
    uint64_t *output;
    uint64_t count;
    uint64_t addend;
    uint64_t xor_value;
    uint64_t rotate;
} U64LearnedLoopFrame;

typedef struct U64NativeVariant {
    const uint8_t *code;
    uint64_t size;
} U64NativeVariant;

typedef struct U64NativeLearner {
    U64LearnedLoopFrame frame;
    uint8_t *slot;
    uint64_t capacity;
    U64NativeVariant variants[8][4][64];
    uint64_t generation;
} U64NativeLearner;

typedef void U64LearnedLoopEntry(U64LearnedLoopFrame *);

int u64_native_learn_and_execute(U64NativeLearner *learner)
{
    uint64_t rotate = learner->frame.rotate & 63;
    unsigned kind = 0;
    if (learner->frame.addend != 0) kind |= 1;
    if (learner->frame.xor_value != 0) kind |= 2;
    if (rotate != 0) kind |= 4;
    unsigned remainder = (unsigned)(learner->frame.count & 3);

    U64NativeVariant variant = learner->variants[kind][remainder][rotate];
    if (variant.code == 0 || variant.size == 0 || variant.size > learner->capacity) return 1;
    if (mprotect(learner->slot, 4096, PROT_READ | PROT_WRITE) != 0) return 2;
    memset(learner->slot, 0x90, learner->capacity);
    memcpy(learner->slot, variant.code, variant.size);
    __builtin___clear_cache((char *)learner->slot, (char *)learner->slot + variant.size);
    if (mprotect(learner->slot, 4096, PROT_READ | PROT_EXEC) != 0) return 3;

    learner->generation += 1;
    ((U64LearnedLoopEntry *)learner->slot)(&learner->frame);
    return 0;
}
