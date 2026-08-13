#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

typedef struct vm_State vm_State;

struct vm_State {
  int64_t value;
  int64_t steps;
  int64_t budget;
};

int vm_hailstone(int64_t r1, int64_t *k1_out, int64_t *k2_out);

int vm_hailstone(int64_t r1, int64_t *k1_out, int64_t *k2_out) {
  vm_State r2;
  vm_State r3;
  vm_State r4;
  vm_State r5;
  int64_t r6;
  int64_t r7;
  int64_t r8;
  int64_t r9;
  bool r10;
  int64_t r11;
  int64_t r12;
  int64_t r13;
  bool r14;
  int64_t r15;
  int64_t r16;
  int64_t r17;
  bool r18;
  int64_t r19;
  int64_t r20;
  int64_t r21;
  int64_t r22;
  int64_t r23;
  bool r24;
  vm_State r25;
  int64_t r26;
  int64_t r27;
  int64_t r28;
  int64_t r29;
  int64_t r30;
  int64_t r31;
  int64_t r32;
  int64_t r33;
  int64_t r34;
  vm_State r35;
  int64_t r36;
  int64_t r37;
  int64_t r38;
  int64_t r39;
  int64_t r40;
  int64_t r41;
  int64_t r42;
  int64_t r43;
  int64_t r44;
  int64_t r45;
  int64_t r46;
B1: ;
  r6 = 0;
  r7 = 1024;
  r5 = (vm_State){ .value = r1, .steps = r6, .budget = r7 };
  r2 = r5;
  goto B2;
B2: ;
  r8 = r2.value;
  r9 = 0;
  r10 = r8 <= r9;
  if (r10) goto B5; else goto B6;
B3: ;
  r26 = r3.value;
  r27 = 2;
  r28 = r26 / r27;
  r29 = r3.steps;
  r30 = 1;
  r31 = r29 + r30;
  r32 = r3.budget;
  r33 = 1;
  r34 = r32 - r33;
  r25 = (vm_State){ .value = r28, .steps = r31, .budget = r34 };
  r2 = r25;
  goto B2;
B4: ;
  r36 = r4.value;
  r37 = 3;
  r38 = r36 * r37;
  r39 = 1;
  r40 = r38 + r39;
  r41 = r4.steps;
  r42 = 1;
  r43 = r41 + r42;
  r44 = r4.budget;
  r45 = 1;
  r46 = r44 - r45;
  r35 = (vm_State){ .value = r40, .steps = r43, .budget = r46 };
  r2 = r35;
  goto B2;
B5: ;
  r11 = r2.value;
  *k2_out = r11;
  return 2;
B6: ;
  r12 = r2.value;
  r13 = 1;
  r14 = r12 == r13;
  if (r14) goto B7; else goto B8;
B7: ;
  r15 = r2.steps;
  *k1_out = r15;
  return 1;
B8: ;
  r16 = r2.budget;
  r17 = 0;
  r18 = r16 <= r17;
  if (r18) goto B9; else goto B10;
B9: ;
  r19 = r2.value;
  *k2_out = r19;
  return 2;
B10: ;
  r20 = r2.value;
  r21 = 2;
  r22 = r20 % r21;
  r23 = 0;
  r24 = r22 == r23;
  if (r24) goto B11; else goto B12;
B11: ;
  r3 = r2;
  goto B3;
B12: ;
  r4 = r2;
  goto B4;
}

#include <stdio.h>
#include <stdint.h>
#include <time.h>

static int64_t native_hailstone(int64_t value) {
    int64_t steps = 0;
    while (value > 1) {
        value = value % 2 == 0 ? value / 2 : value * 3 + 1;
        ++steps;
    }
    return steps;
}

static double seconds(void) {
    return (double)clock() / (double)CLOCKS_PER_SEC;
}

int main(void) {
    int64_t result = 0;
    int64_t trapped = 0;

    for (int64_t input = 1; input <= 100000; ++input) {
        int exit = vm_hailstone(input, &result, &trapped);
        if (exit != 1 || result != native_hailstone(input)) {
            fprintf(stderr, "mismatch at %lld: exit=%d vm=%lld native=%lld\n",
                (long long)input, exit, (long long)result,
                (long long)native_hailstone(input));
            return 1;
        }
    }

    if (vm_hailstone(0, &result, &trapped) != 2 || trapped != 0) return 2;

    const int64_t runs = 1000000;
    int64_t checksum = 0;
    double begin = seconds();
    for (int64_t input = 1; input <= runs; ++input) {
        if (vm_hailstone(input, &result, &trapped) != 1) return 3;
        checksum += result;
    }
    double vm_elapsed = seconds() - begin;

    int64_t native_checksum = 0;
    begin = seconds();
    for (int64_t input = 1; input <= runs; ++input)
        native_checksum += native_hailstone(input);
    double native_elapsed = seconds() - begin;
    if (native_checksum != checksum) return 4;

    printf("direct-threaded hailstone VM\n");
    printf("  runs:         %lld\n", (long long)runs);
    printf("  transitions:  %lld\n", (long long)checksum);
    printf("  VM:           %.3f ms, %.1f M transitions/s\n",
        vm_elapsed * 1000.0, (double)checksum / vm_elapsed / 1000000.0);
    printf("  raw C:        %.3f ms, %.1f M transitions/s\n",
        native_elapsed * 1000.0,
        (double)checksum / native_elapsed / 1000000.0);
    printf("  VM / raw C:   %.3fx\n", vm_elapsed / native_elapsed);
    return 0;
}
