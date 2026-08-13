local C = require("cblock")

local csrc, errors = C.compile(function()
    local Vec2 = struct {
        field: x (f64),
        field: y (f64),
    }

    Vec2: add (Vec2, cont(Vec2)) (function(self, other)
        return Vec2 { x = self.x + other.x, y = self.y + other.y }
    end)

    Vec2: scale (f64, cont(Vec2)) (function(self, a)
        return Vec2 { x = self.x * a, y = self.y * a }
    end)

    function Vec2:length_squared()
        return self.x * self.x + self.y * self.y
    end

    local Particle = struct {
        field: position (Vec2),
        field: velocity (Vec2),
        field: mass (f64),
    }

    Particle: step (f64, cont(Particle)) (function(self, dt)
        return Particle {
            position = self.position:add(self.velocity:scale(dt)),
            velocity = self.velocity,
            mass = self.mass,
        }
    end)

    function Particle:energy()
        return 0.5 * self.mass * self.velocity:length_squared()
    end

    local step_all = func(ptr(Particle), ptr(Particle), i64, f64, ret())
        (function(dst, src, n, dt)
            local each = range(0, n)
            return each:load(src):map(function(p)
                return p:step(dt)
            end):store(dst)
        end)

    local total_energy = func(ptr(Particle), i64, ret(f64))
        (function(particles, n)
            local each = range(0, n)
            return each:load(particles):map(function(p)
                return p:energy()
            end):reduce(add, 0.0)
        end)

    return {
        physics = {
            Vec2 = Vec2,
            Particle = Particle,
            step_all = step_all,
            total_energy = total_energy,
        },
    }
end)

if not csrc then error(table.concat(errors, "\n")) end

local f = assert(io.open("particles.c", "w"))
f:write(csrc, [[

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
]])
f:close()

assert(os.execute("cc -std=c99 -O3 -o particles particles.c && ./particles"))
