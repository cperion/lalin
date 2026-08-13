#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

typedef struct fractal_Complex fractal_Complex;
typedef struct fractal_Orbit fractal_Orbit;

struct fractal_Complex {
  double re;
  double im;
};

struct fractal_Orbit {
  fractal_Complex z;
  fractal_Complex c;
  int32_t iteration;
};

static fractal_Orbit cblock_region_4(fractal_Orbit r1);
static fractal_Orbit cblock_region_5(fractal_Orbit r1);
void fractal_render(int32_t * r1, fractal_Complex * r2, int64_t r3);

static fractal_Orbit cblock_region_4(fractal_Orbit r1) {
  fractal_Orbit r2;
  fractal_Orbit r3;
  fractal_Orbit r4;
  fractal_Orbit r5;
  fractal_Orbit r6;
  fractal_Orbit r7;
  fractal_Orbit r8;
  fractal_Orbit r9;
  fractal_Orbit r10;
  fractal_Orbit r11;
  fractal_Orbit r12;
  fractal_Orbit r13;
  fractal_Orbit r14;
  fractal_Orbit r15;
  fractal_Orbit r16;
  fractal_Orbit r17;
  fractal_Orbit r18;
  fractal_Orbit r19;
  fractal_Orbit r20;
  fractal_Orbit r21;
  fractal_Orbit r22;
  fractal_Orbit r23;
  fractal_Orbit r24;
  fractal_Orbit r25;
  fractal_Orbit r26;
  fractal_Orbit r27;
  fractal_Orbit r28;
  fractal_Orbit r29;
  fractal_Orbit r30;
  fractal_Orbit r31;
  fractal_Orbit r32;
  fractal_Orbit r33;
  fractal_Orbit r34;
  fractal_Orbit r35;
  fractal_Orbit r36;
  fractal_Orbit r37;
  fractal_Orbit r38;
  fractal_Orbit r39;
  fractal_Orbit r40;
  fractal_Orbit r41;
  fractal_Orbit r42;
  fractal_Orbit r43;
  fractal_Orbit r44;
  fractal_Orbit r45;
  fractal_Orbit r46;
  fractal_Orbit r47;
  fractal_Orbit r48;
  fractal_Orbit r49;
B1: ;
  r2 = cblock_region_5(r1);
  r3 = cblock_region_5(r2);
  r4 = cblock_region_5(r3);
  r5 = cblock_region_5(r4);
  r6 = cblock_region_5(r5);
  r7 = cblock_region_5(r6);
  r8 = cblock_region_5(r7);
  r9 = cblock_region_5(r8);
  r10 = cblock_region_5(r9);
  r11 = cblock_region_5(r10);
  r12 = cblock_region_5(r11);
  r13 = cblock_region_5(r12);
  r14 = cblock_region_5(r13);
  r15 = cblock_region_5(r14);
  r16 = cblock_region_5(r15);
  r17 = cblock_region_5(r16);
  r18 = cblock_region_5(r17);
  r19 = cblock_region_5(r18);
  r20 = cblock_region_5(r19);
  r21 = cblock_region_5(r20);
  r22 = cblock_region_5(r21);
  r23 = cblock_region_5(r22);
  r24 = cblock_region_5(r23);
  r25 = cblock_region_5(r24);
  r26 = cblock_region_5(r25);
  r27 = cblock_region_5(r26);
  r28 = cblock_region_5(r27);
  r29 = cblock_region_5(r28);
  r30 = cblock_region_5(r29);
  r31 = cblock_region_5(r30);
  r32 = cblock_region_5(r31);
  r33 = cblock_region_5(r32);
  r34 = cblock_region_5(r33);
  r35 = cblock_region_5(r34);
  r36 = cblock_region_5(r35);
  r37 = cblock_region_5(r36);
  r38 = cblock_region_5(r37);
  r39 = cblock_region_5(r38);
  r40 = cblock_region_5(r39);
  r41 = cblock_region_5(r40);
  r42 = cblock_region_5(r41);
  r43 = cblock_region_5(r42);
  r44 = cblock_region_5(r43);
  r45 = cblock_region_5(r44);
  r46 = cblock_region_5(r45);
  r47 = cblock_region_5(r46);
  r48 = cblock_region_5(r47);
  r49 = cblock_region_5(r48);
  return r49;
}

static fractal_Orbit cblock_region_5(fractal_Orbit r1) {
  double r2;
  double r3;
  fractal_Complex r4;
  double r5;
  fractal_Complex r6;
  double r7;
  double r8;
  fractal_Complex r9;
  double r10;
  fractal_Complex r11;
  double r12;
  double r13;
  bool r14;
  fractal_Orbit r15;
  fractal_Orbit r16;
  fractal_Complex r17;
  double r18;
  fractal_Complex r19;
  double r20;
  fractal_Complex r21;
  double r22;
  double r23;
  fractal_Complex r24;
  double r25;
  fractal_Complex r26;
  double r27;
  double r28;
  double r29;
  fractal_Complex r30;
  double r31;
  double r32;
  double r33;
  fractal_Complex r34;
  double r35;
  double r36;
  fractal_Complex r37;
  double r38;
  double r39;
  fractal_Complex r40;
  double r41;
  fractal_Complex r42;
  int32_t r43;
  int32_t r44;
  int32_t r45;
B1: ;
  r2 = 4;
  r4 = r1.z;
  r3 = r4.re;
  r6 = r1.z;
  r5 = r6.re;
  r7 = r3 * r5;
  r9 = r1.z;
  r8 = r9.im;
  r11 = r1.z;
  r10 = r11.im;
  r12 = r8 * r10;
  r13 = r7 + r12;
  r14 = r2 < r13;
  if (r14) goto B2; else goto B3;
B2: ;
  r15 = r1;
  goto B4;
B3: ;
  r19 = r1.z;
  r18 = r19.re;
  r21 = r1.z;
  r20 = r21.re;
  r22 = r18 * r20;
  r24 = r1.z;
  r23 = r24.im;
  r26 = r1.z;
  r25 = r26.im;
  r27 = r23 * r25;
  r28 = r22 - r27;
  r30 = r1.c;
  r29 = r30.re;
  r31 = r28 + r29;
  r32 = 2;
  r34 = r1.z;
  r33 = r34.re;
  r35 = r32 * r33;
  r37 = r1.z;
  r36 = r37.im;
  r38 = r35 * r36;
  r40 = r1.c;
  r39 = r40.im;
  r41 = r38 + r39;
  r17 = (fractal_Complex){ .re = r31, .im = r41 };
  r42 = r1.c;
  r43 = r1.iteration;
  r44 = 1;
  r45 = r43 + r44;
  r16 = (fractal_Orbit){ .z = r17, .c = r42, .iteration = r45 };
  r15 = r16;
  goto B4;
B4: ;
  return r15;
}

void fractal_render(int32_t * r1, fractal_Complex * r2, int64_t r3) {
  int64_t r4;
  int64_t r5;
  bool r6;
  int32_t r7;
  fractal_Orbit r8;
  fractal_Complex r9;
  double r10;
  double r11;
  fractal_Complex r12;
  int32_t r13;
  fractal_Orbit r14;
  int64_t r15;
  int64_t r16;
B1: ;
  r4 = 0;
  r5 = r4;
  goto B2;
B2: ;
  r6 = r5 < r3;
  if (r6) goto B3; else goto B4;
B3: ;
  r10 = 0;
  r11 = 0;
  r9 = (fractal_Complex){ .re = r10, .im = r11 };
  r12 = r2[r5];
  r13 = 0;
  r8 = (fractal_Orbit){ .z = r9, .c = r12, .iteration = r13 };
  r14 = cblock_region_4(r8);
  r7 = r14.iteration;
  r1[r5] = r7;
  r15 = 1;
  r16 = r5 + r15;
  r5 = r16;
  goto B2;
B4: ;
  return;
}

#include <stdio.h>
#include <stdlib.h>
#include <time.h>

static double seconds(void) {
    return (double)clock() / (double)CLOCKS_PER_SEC;
}

int main(void) {
    enum { width = 1280, height = 720, max_iter = 48 };
    const int64_t count = (int64_t)width * height;
    fractal_Complex *points = malloc((size_t)count * sizeof(*points));
    int32_t *iterations = malloc((size_t)count * sizeof(*iterations));
    if (!points || !iterations) return 1;

    for (int y = 0; y < height; ++y) {
        for (int x = 0; x < width; ++x) {
            int64_t i = (int64_t)y * width + x;
            points[i].re = -2.1 + 3.2 * (double)x / (double)(width - 1);
            points[i].im = -1.2 + 2.4 * (double)y / (double)(height - 1);
        }
    }

    double begin = seconds();
    fractal_render(iterations, points, count);
    double elapsed = seconds() - begin;

    FILE *image = fopen("mandelbrot.pgm", "wb");
    if (!image) return 2;
    fprintf(image, "P5\n%d %d\n255\n", width, height);
    for (int64_t i = 0; i < count; ++i) {
        int value = iterations[i];
        unsigned char shade = value == max_iter ? 0 :
            (unsigned char)(255 - (value * 255 / max_iter));
        fwrite(&shade, 1, 1, image);
    }
    fclose(image);

    printf("%dx%d, %d transitions/pixel in %.3f ms (%.1f Mpixel/s)\n",
        width, height, max_iter, elapsed * 1000.0,
        (double)count / elapsed / 1000000.0);
    printf("wrote mandelbrot.pgm\n");

    free(iterations);
    free(points);
    return 0;
}
