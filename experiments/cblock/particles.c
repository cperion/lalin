#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

typedef struct physics_Vec2 physics_Vec2;
typedef struct physics_Particle physics_Particle;

struct physics_Vec2 {
  double x;
  double y;
};

struct physics_Particle {
  physics_Vec2 position;
  physics_Vec2 velocity;
  double mass;
};

void physics_step_all(physics_Particle * r1, physics_Particle * r2, int64_t r3, double r4);
double physics_total_energy(physics_Particle * r1, int64_t r2);

void physics_step_all(physics_Particle * r1, physics_Particle * r2, int64_t r3, double r4) {
  int64_t r5;
  int64_t r6;
  bool r7;
  physics_Particle r8;
  physics_Vec2 r9;
  double r10;
  physics_Vec2 r11;
  physics_Particle r12;
  double r13;
  physics_Vec2 r14;
  double r15;
  physics_Vec2 r16;
  physics_Particle r17;
  double r18;
  double r19;
  physics_Vec2 r20;
  physics_Particle r21;
  double r22;
  double r23;
  double r24;
  physics_Vec2 r25;
  physics_Particle r26;
  double r27;
  physics_Vec2 r28;
  double r29;
  physics_Vec2 r30;
  physics_Particle r31;
  double r32;
  double r33;
  physics_Vec2 r34;
  physics_Particle r35;
  double r36;
  double r37;
  physics_Vec2 r38;
  physics_Particle r39;
  double r40;
  physics_Particle r41;
  int64_t r42;
  int64_t r43;
B1: ;
  r5 = 0;
  r6 = r5;
  goto B2;
B2: ;
  r7 = r6 < r3;
  if (r7) goto B3; else goto B4;
B3: ;
  r12 = r2[r6];
  r11 = r12.position;
  r10 = r11.x;
  r17 = r2[r6];
  r16 = r17.velocity;
  r15 = r16.x;
  r18 = r15 * r4;
  r21 = r2[r6];
  r20 = r21.velocity;
  r19 = r20.y;
  r22 = r19 * r4;
  r14 = (physics_Vec2){ .x = r18, .y = r22 };
  r13 = r14.x;
  r23 = r10 + r13;
  r26 = r2[r6];
  r25 = r26.position;
  r24 = r25.y;
  r31 = r2[r6];
  r30 = r31.velocity;
  r29 = r30.x;
  r32 = r29 * r4;
  r35 = r2[r6];
  r34 = r35.velocity;
  r33 = r34.y;
  r36 = r33 * r4;
  r28 = (physics_Vec2){ .x = r32, .y = r36 };
  r27 = r28.y;
  r37 = r24 + r27;
  r9 = (physics_Vec2){ .x = r23, .y = r37 };
  r39 = r2[r6];
  r38 = r39.velocity;
  r41 = r2[r6];
  r40 = r41.mass;
  r8 = (physics_Particle){ .position = r9, .velocity = r38, .mass = r40 };
  r1[r6] = r8;
  r42 = 1;
  r43 = r6 + r42;
  r6 = r43;
  goto B2;
B4: ;
  return;
}

double physics_total_energy(physics_Particle * r1, int64_t r2) {
  int64_t r3;
  double r4;
  int64_t r5;
  double r6;
  bool r7;
  double r8;
  double r9;
  physics_Particle r10;
  double r11;
  double r12;
  physics_Vec2 r13;
  physics_Particle r14;
  double r15;
  physics_Vec2 r16;
  physics_Particle r17;
  double r18;
  double r19;
  physics_Vec2 r20;
  physics_Particle r21;
  double r22;
  physics_Vec2 r23;
  physics_Particle r24;
  double r25;
  double r26;
  double r27;
  double r28;
  int64_t r29;
  int64_t r30;
B1: ;
  r3 = 0;
  r4 = 0;
  r5 = r3;
  r6 = r4;
  goto B2;
B2: ;
  r7 = r5 < r2;
  if (r7) goto B3; else goto B4;
B3: ;
  r8 = 0.5;
  r10 = r1[r5];
  r9 = r10.mass;
  r11 = r8 * r9;
  r14 = r1[r5];
  r13 = r14.velocity;
  r12 = r13.x;
  r17 = r1[r5];
  r16 = r17.velocity;
  r15 = r16.x;
  r18 = r12 * r15;
  r21 = r1[r5];
  r20 = r21.velocity;
  r19 = r20.y;
  r24 = r1[r5];
  r23 = r24.velocity;
  r22 = r23.y;
  r25 = r19 * r22;
  r26 = r18 + r25;
  r27 = r11 * r26;
  r28 = r6 + r27;
  r6 = r28;
  r29 = 1;
  r30 = r5 + r29;
  r5 = r30;
  goto B2;
B4: ;
  return r6;
}

#include <stdio.h>
int main(void) {
    physics_Particle src[3] = {
        { { 0.0, 0.0 }, { 1.0, 2.0 }, 2.0 },
        { { 5.0, 1.0 }, { -1.0, 0.5 }, 4.0 },
        { { 2.0, 3.0 }, { 0.0, -2.0 }, 1.5 },
    };
    physics_Particle dst[3];

    physics_step_all(dst, src, 3, 0.5);
    double energy = physics_total_energy(dst, 3);

    printf("p0 = (%g, %g)\n", dst[0].position.x, dst[0].position.y);
    printf("p1 = (%g, %g)\n", dst[1].position.x, dst[1].position.y);
    printf("p2 = (%g, %g)\n", dst[2].position.x, dst[2].position.y);
    printf("energy = %g\n", energy);

    if (dst[0].position.x != 0.5 || dst[0].position.y != 1.0) return 1;
    if (dst[1].position.x != 4.5 || dst[1].position.y != 1.25) return 2;
    if (dst[2].position.x != 2.0 || dst[2].position.y != 2.0) return 3;
    if (energy != 10.5) return 4;
    return 0;
}
