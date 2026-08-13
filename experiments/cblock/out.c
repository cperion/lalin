#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

int32_t fib(int32_t r1);
double max3(double r1, double r2, double r3);
int32_t demo(int32_t r1, int32_t r2);
int32_t clamp_called(int32_t r1);
int32_t divide(int32_t r1, int32_t r2);
static int32_t cblock_region_8(int32_t r1, int32_t r2, int32_t r3);

int32_t fib(int32_t r1) {
  int32_t r2;
  bool r3;
  int32_t r4;
  int32_t r5;
  int32_t r6;
  int32_t r7;
  int32_t r8;
  int32_t r9;
  int32_t r10;
  int32_t r11;
B1: ;
  r2 = 2;
  r3 = r1 < r2;
  if (r3) goto B2; else goto B3;
B2: ;
  r4 = r1;
  goto B4;
B3: ;
  r5 = 1;
  r6 = r1 - r5;
  r7 = fib(r6);
  r8 = 2;
  r9 = r1 - r8;
  r10 = fib(r9);
  r11 = r7 + r10;
  r4 = r11;
  goto B4;
B4: ;
  return r4;
}

double max3(double r1, double r2, double r3) {
  bool r4;
  double r5;
  bool r6;
  double r7;
  bool r8;
  double r9;
B1: ;
  r4 = r1 < r2;
  if (r4) goto B2; else goto B3;
B2: ;
  r5 = r2;
  goto B4;
B3: ;
  r5 = r1;
  goto B4;
B4: ;
  r6 = r5 < r3;
  if (r6) goto B5; else goto B6;
B5: ;
  r7 = r3;
  goto B7;
B6: ;
  r8 = r1 < r2;
  if (r8) goto B8; else goto B9;
B7: ;
  return r7;
B8: ;
  r9 = r2;
  goto B10;
B9: ;
  r9 = r1;
  goto B10;
B10: ;
  r7 = r9;
  goto B7;
}

int32_t demo(int32_t r1, int32_t r2) {
  int32_t r3;
  bool r4;
  int32_t r5;
  int32_t r6;
  bool r7;
  int32_t r8;
  int32_t r9;
  bool r10;
  int32_t r11;
  int32_t r12;
  int32_t r13;
  bool r14;
  int32_t r15;
  bool r16;
  int32_t r17;
  int32_t r18;
  bool r19;
  int32_t r20;
  int32_t r21;
  int32_t r22;
B1: ;
  r3 = 0;
  r4 = r2 == r3;
  if (r4) goto B2; else goto B3;
B2: ;
  r6 = -1;
  r5 = r6;
  goto B4;
B3: ;
  r7 = r1 < r2;
  if (r7) goto B5; else goto B6;
B4: ;
  return r5;
B5: ;
  r8 = r2;
  goto B7;
B6: ;
  r8 = r1;
  goto B7;
B7: ;
  r9 = 10;
  r10 = r8 < r9;
  if (r10) goto B8; else goto B9;
B8: ;
  r12 = 10;
  r11 = r12;
  goto B10;
B9: ;
  r13 = 100;
  r14 = r1 < r2;
  if (r14) goto B11; else goto B12;
B10: ;
  r21 = r1 / r2;
  r22 = r11 + r21;
  r5 = r22;
  goto B4;
B11: ;
  r15 = r2;
  goto B13;
B12: ;
  r15 = r1;
  goto B13;
B13: ;
  r16 = r13 < r15;
  if (r16) goto B14; else goto B15;
B14: ;
  r18 = 100;
  r17 = r18;
  goto B16;
B15: ;
  r19 = r1 < r2;
  if (r19) goto B17; else goto B18;
B16: ;
  r11 = r17;
  goto B10;
B17: ;
  r20 = r2;
  goto B19;
B18: ;
  r20 = r1;
  goto B19;
B19: ;
  r17 = r20;
  goto B16;
}

int32_t clamp_called(int32_t r1) {
  int32_t r2;
  int32_t r3;
  int32_t r4;
B1: ;
  r2 = 10;
  r3 = 100;
  r4 = cblock_region_8(r1, r2, r3);
  return r4;
}

int32_t divide(int32_t r1, int32_t r2) {
  int32_t r3;
  bool r4;
  int32_t r5;
  int32_t r6;
B1: ;
  r3 = 0;
  r4 = r2 == r3;
  if (r4) goto B2; else goto B3;
B2: ;
  r5 = -1;
  return r5;
B3: ;
  r6 = r1 / r2;
  return r6;
}

static int32_t cblock_region_8(int32_t r1, int32_t r2, int32_t r3) {
  bool r4;
  int32_t r5;
  bool r6;
  int32_t r7;
B1: ;
  r4 = r1 < r2;
  if (r4) goto B2; else goto B3;
B2: ;
  r5 = r2;
  goto B4;
B3: ;
  r6 = r3 < r1;
  if (r6) goto B5; else goto B6;
B4: ;
  return r5;
B5: ;
  r7 = r3;
  goto B7;
B6: ;
  r7 = r1;
  goto B7;
B7: ;
  r5 = r7;
  goto B4;
}

#include <stdio.h>
int main(void) {
    int32_t q = 0;
    printf("fib(25)      = %d\n", fib(25));
    printf("demo(7,3)    = %d\n", demo(7, 3));
    printf("demo(500,0)  = %d\n", demo(500, 0));
    printf("max3         = %g\n", max3(1.5, 9.25, 3.0));
    printf("clamp call   = %d\n", clamp_called(500));
    printf("checked div  = %d\n", divide(8, 2));
    printf("checked zero = %d\n", divide(8, 0));
    return 0;
}
