local C = require("cblock")
local ffi = require("ffi")

-- Phase 1/2: runtime values, places, complete scalars.
local csrc, errors = C.compile(function()
    local Frame = struct {
        field: pc (i32),
        field: acc (i64),
    }

    -- step: mutates a Frame through a pointer, using var/seq/let/places.
    local step = region(
        param: frame_ptr (ptr(Frame)),
        cont: done (i64),
        cont: trapped ()
    )
        (function(p, c)
            local frame_ptr = p.frame_ptr
            local done, trapped = c.done, c.trapped
            local self = var(Frame, load(deref(frame_ptr)))
            local pc = var(i32, self.pc)
            local acc = var(i64, self.acc)
            local twice = let(acc * 2)

            return pc:store(pc:load() + 1),
                   acc:store(twice + cast(i64, pc:load())),
                   self.pc:store(pc:load()),
                   self.acc:store(acc:load()),
                   frame_ptr:deref().pc:store(pc:load()),
                   frame_ptr:deref().acc:store(acc:load()),
                   done(self.acc:load())
        end)

    local bitwork = func
        (param: a (u32), param: b (u32))
        (u32)
        (function(p)
            return bit_or(shift_left(bit_and(p.a, 0xFF), 8), p.b)
        end)

    local typed = region(
        param: selector (i32),
        cont: unsigned (u64),
        cont: integer (i32),
        cont: floating (f64),
        cont: size (usize)
    )(function(p, c)
            local selector = p.selector
            local u, i, f, s = c.unsigned, c.integer, c.floating, c.size
            return if_(eq(selector, 0), u(cast(u64, 7)),
                if_(eq(selector, 1), i(cast(i32, 3)),
                    if_(eq(selector, 2), f(cast(f64, 2.5)),
                        s(sizeof(i32)))))
        end)

    local step_fn = call(step)
    local typed_fn = call(typed)

    return {
        machine = {
            Frame = Frame,
            step = step_fn, bitwork = bitwork, typed = typed_fn,
        },
    }
end)

if not csrc then error(table.concat(errors, "\n")) end

local base = os.tmpname()
os.remove(base)
local cpath, exe = base .. ".c", base .. ".out"
local f = assert(io.open(cpath, "w"))
f:write(csrc, [[

int main(void) {
    machine_Frame frame = { 10, 100 };
    int64_t acc = 0;
    if (machine_step(&frame, &acc) != 1) return 1;
    if (frame.pc != 11) return 2;
    if (frame.acc != 211) return 3;   /* 100*2 + 11 */
    if (acc != 211) return 4;

    uint32_t bits = 0;
    bits = machine_bitwork(0xAB, 0x12);
    if (bits != (((0xAB & 0xFF) << 8) | 0x12)) return 6;

    uint64_t u = 0; int32_t i = 0; double fv = 0; size_t s = 0;
    if (machine_typed(0, &u, &i, &fv, &s) != 1 || u != 7) return 7;
    if (machine_typed(1, &u, &i, &fv, &s) != 2 || i != 3) return 8;
    if (machine_typed(2, &u, &i, &fv, &s) != 3 || fv != 2.5) return 9;
    if (machine_typed(3, &u, &i, &fv, &s) != 4 || s != 4) return 10;
    return 0;
}
]])
f:close()
local ok, why, code = os.execute(("cc -std=c99 -O2 -o %s %s && %s"):format(exe, cpath, exe))
os.remove(cpath) os.remove(exe)
assert(ok == true or ok == 0, ("places test failed: %s %s"):format(why, code))
print("cblock places + scalars (GCC): ok")

-- Same surface through the lazy TCC path (host structs by value).
local module, runtime = C.jit(function()
    local Frame = struct {
        field: pc (i32),
        field: acc (i64),
    }

    local step = region(
        param: frame (Frame),
        cont: done (Frame),
        cont: trapped ()
    )
        (function(p, c)
            local frame = p.frame
            local done, trapped = c.done, c.trapped
            local self = var(Frame, frame)
            local pc = var(i32, self.pc)
            local acc = var(i64, self.acc)
            return store(pc, pc + 1),
                   store(acc, acc * 2 + cast(i64, pc)),
                   store(self.pc, pc),
                   store(self.acc, acc),
                   done(load(self))
        end)

    local bitwork = func
        (param: a (u32), param: b (u32))
        (u32)
        (function(p)
            return bit_or(shift_left(bit_and(p.a, 0xFF), 8), p.b)
        end)

    local step_fn = call(step)

    return {
        machine = { Frame = Frame, step = step_fn, bitwork = bitwork },
    }
end)
assert(module, runtime)

local frame = module.machine.Frame { pc = 10, acc = 100 }
local exit, stepped = module.machine.step(frame)
assert(exit == "done")
assert(tonumber(stepped.pc) == 11)
assert(tonumber(stepped.acc) == 211)

local bits = module.machine.bitwork(0xAB, 0x12)
assert(tonumber(bits) == 0xAB12)

module:free()
print("cblock places + scalars (TCC): ok")
