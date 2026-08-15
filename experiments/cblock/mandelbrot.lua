local C = require("cblock")

local WIDTH, HEIGHT, MAX_ITER = 1280, 720, 48

local csrc, errors = C.compile(function()
    local Complex = struct {
        field: re (f64),
        field: im (f64),
    }

    Complex: square_add (param: addend (Complex)) (Complex) (function(p)
        local self, addend = p.self, p.addend
        return Complex {
            re = self.re * self.re - self.im * self.im + addend.re,
            im = 2.0 * self.re * self.im + addend.im,
        }
    end)

    function Complex:norm_squared()
        return self.re * self.re + self.im * self.im
    end

    local Orbit = struct {
        field: z (Complex),
        field: c (Complex),
        field: iteration (i32),
    }

    Orbit: advance () (Orbit) (function(p)
        local self = p.self
        local next_z = self.z:square_add(self.c)
        local next_orbit = Orbit {
            z = next_z,
            c = self.c,
            iteration = self.iteration + 1,
        }
        return if_(gt(self.z:norm_squared(), 4.0), self, next_orbit)
    end)

    local function repeated_transition(T, transition, count)
        return region(param: state (T))(T)(function(p)
            local state = p.state
            local framed_transition = call(transition)
            for _ = 1, count do state = framed_transition(state) end
            return state
        end)
    end

    Orbit.iterate = repeated_transition(Orbit, Orbit.advance, MAX_ITER)
    local run_orbit_frame = call(Orbit.iterate)

    local render = func
        (param: dst (ptr(i32)), param: points (ptr(Complex)), param: count (i64))
        (void)
        (function(p)
            local each = range(0, p.count)
            return each:load(p.points):map(function(c)
                local orbit = Orbit {
                    z = Complex { re = 0.0, im = 0.0 },
                    c = c,
                    iteration = 0,
                }
                return run_orbit_frame(orbit).iteration
            end):store(p.dst)
        end)

    return {
        fractal = {
            Complex = Complex,
            Orbit = Orbit,
            render = render,
        },
    }
end)

if not csrc then error(table.concat(errors, "\n")) end

local f = assert(io.open("mandelbrot.c", "w"))
f:write(csrc, ([=[

#include <stdio.h>
#include <stdlib.h>
#include <time.h>

static double seconds(void) {
    return (double)clock() / (double)CLOCKS_PER_SEC;
}

int main(void) {
    enum { width = %d, height = %d, max_iter = %d };
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
    fprintf(image, "P5\n%%d %%d\n255\n", width, height);
    for (int64_t i = 0; i < count; ++i) {
        int value = iterations[i];
        unsigned char shade = value == max_iter ? 0 :
            (unsigned char)(255 - (value * 255 / max_iter));
        fwrite(&shade, 1, 1, image);
    }
    fclose(image);

    printf("%%dx%%d, %%d transitions/pixel in %%.3f ms (%%.1f Mpixel/s)\n",
        width, height, max_iter, elapsed * 1000.0,
        (double)count / elapsed / 1000000.0);
    printf("wrote mandelbrot.pgm\n");

    free(iterations);
    free(points);
    return 0;
}
]=]):format(WIDTH, HEIGHT, MAX_ITER))
f:close()

if os.getenv("CBLOCK_EMIT_ONLY") then
    print(("generated mandelbrot.c: %d bytes"):format(#csrc))
    return
end

assert(os.execute("cc -std=c99 -O3 -ffast-math -o mandelbrot mandelbrot.c && ./mandelbrot"))
