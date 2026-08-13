local C = require("cblock")

-- 12.3 arrays/views, 12.4 unions, 12.5 globals/cstring, 12.6 opaque/fnptr
local csrc, errors = C.compile(function()
    local Vec4 = struct {
        field: data (array(f64, 4)),
    }

    local Value = union {
        field: integer (i64),
        field: floating (f64),
    }

    local Slice = view(f64)

    local File = opaque("File")

    local Binop = fnptr(i32, i32, i32)

    -- globals: table, string
    local lut = global(array(i32, 4), { 10, 20, 30, 40 })
    local greeting = cstring("hi")

    local host_apply = extern(Binop, i32, i32, ret(i32))
    local host_read = extern(ptr(File), ret(i32))

    local sum_array = region(ptr(Vec4), cont(f64), cont())(function(p, done, trapped)
        local v = var(Vec4, load(deref(p)))
        local acc = var(f64, 0.0)
        return store(acc, acc + at(v.data, 0)),
               store(acc, acc + at(v.data, 1)),
               store(acc, acc + at(v.data, 2)),
               store(acc, acc + at(v.data, 3)),
               done(acc)
    end)

    local classify = region(i64, cont(f64), cont(i64))(function(v, as_float, as_int)
        local f = Value { floating = cast(f64, v) }
        local i = Value { integer = v }
        return if_(eq(v, 7)):then_(as_float(f.floating)):else_(as_int(i.integer))
    end)

    local read_lut = region(i32, cont(i32), cont())(function(i, done, trapped)
        return done(load(at(lut, i)))
    end)

    local first_char = region(cont(i32), cont())(function(done, trapped)
        return done(cast(i32, load(at(greeting, 0))))
    end)

    local sum_view = region(ptr(Slice), cont(f64), cont())(function(p, done, trapped)
        local s = load(deref(p))
        local each = range(0, s.length)
        return done(each:load(s.ptr):reduce(add, 0.0))
    end)

    local add_two = func(i32, i32, ret(i32))(function(x, y)
        return x + y
    end)
    local apply = func(i32, i32, ret(i32))(function(x, y)
        return host_apply(address(add_two), x, y)
    end)

    local read_file = region(ptr(File), cont(i32), cont())(function(f, done, trapped)
        return done(host_read(f))
    end)

    local sum_array_fn = call(sum_array)
    local classify_fn = call(classify)
    local read_lut_fn = call(read_lut)
    local first_char_fn = call(first_char)
    local sum_view_fn = call(sum_view)
    local read_file_fn = call(read_file)

    return {
        machine = {
            Vec4 = Vec4, Value = Value, Slice = Slice,
            host_apply = host_apply, host_read = host_read,
            sum_array = sum_array_fn, classify = classify_fn,
            read_lut = read_lut_fn, first_char = first_char_fn,
            sum_view = sum_view_fn, apply = apply, read_file = read_file_fn,
        },
    }
end)

if not csrc then error(table.concat(errors, "\n")) end

local base = os.tmpname()
os.remove(base)
local cpath, exe = base .. ".c", base .. ".out"
local f = assert(io.open(cpath, "w"))
f:write(csrc, [[
struct File;

int32_t machine_host_apply(int32_t (*fn)(int32_t, int32_t), int32_t x, int32_t y) { return fn(x, y); }
int32_t machine_host_read(struct File *f) { return 42; }

int main(void) {
    double out = 0; int64_t iout = 0; int32_t ival = 0;
    machine_Vec4 v = { { 1.0, 2.0, 3.0, 4.0 } };
    if (machine_sum_array(&v, &out) != 1 || out != 10.0) return 1;

    if (machine_classify(7, &out, &iout) != 1 || out != 7.0) return 2;
    if (machine_classify(9, &out, &iout) != 2 || iout != 9) return 3;

    if (machine_read_lut(2, &ival) != 1 || ival != 30) return 4;
    if (machine_first_char(&ival) != 1 || ival != 'h') return 5;

    double xs[4] = { 1.0, 2.0, 3.0, 4.0 };
    machine_Slice slice = { xs, 4 };
    if (machine_sum_view(&slice, &out) != 1 || out != 10.0) return 6;

    if (machine_apply(20, 22) != 42) return 7;

    struct File *fake = 0;
    if (machine_read_file(fake, &ival) != 1 || ival != 42) return 8;
    return 0;
}
]])
f:close()
local ok, why, code = os.execute(("cc -std=c99 -O2 -o %s %s && %s"):format(exe, cpath, exe))
os.remove(cpath) os.remove(exe)
assert(ok == true or ok == 0, ("leftover test failed: %s %s"):format(why, code))
print("cblock arrays/views/unions/globals/fnptr (GCC): ok")

-- TCC path: same builder, host calls from Lua
local module, runtime = C.jit(function()
    local Vec4 = struct { field: data (array(f64, 4)) }
    local Value = union { field: integer (i64), field: floating (f64) }
    local Slice = view(f64)
    local File = opaque("File")
    local Binop = fnptr(i32, i32, i32)
    local lut = global(array(i32, 4), { 10, 20, 30, 40 })

    local classify = region(i64, cont(f64), cont(i64))(function(v, as_float, as_int)
        local f = Value { floating = cast(f64, v) }
        local i = Value { integer = v }
        return if_(eq(v, 7)):then_(as_float(f.floating)):else_(as_int(i.integer))
    end)
    local read_lut = region(i32, cont(i32), cont())(function(i, done, trapped)
        return done(load(at(lut, i)))
    end)
    local sum_view = region(ptr(Slice), cont(f64), cont())(function(p, done, trapped)
        local s = load(deref(p))
        local each = range(0, s.length)
        return done(each:load(s.ptr):reduce(add, 0.0))
    end)

    local classify_fn = call(classify)
    local read_lut_fn = call(read_lut)
    local sum_view_fn = call(sum_view)

    return {
        machine = {
            Vec4 = Vec4, Value = Value, Slice = Slice,
            classify = classify_fn, read_lut = read_lut_fn,
            sum_view = sum_view_fn,
        },
    }
end)
assert(module, runtime)

local ffi = require("ffi")
local exit, value = module.machine.classify(7)
assert(exit == 1 and tonumber(value) == 7.0)
exit, value = module.machine.classify(9)
assert(exit == 2 and tonumber(value) == 9)
exit, value = module.machine.read_lut(2)
assert(exit == 1 and tonumber(value) == 30)

local xs = ffi.new("double[4]", { 1.0, 2.0, 3.0, 4.0 })
local slice = module.machine.Slice { ptr = xs, length = 4 }
exit, value = module.machine.sum_view(ffi.cast("void *", slice))
assert(exit == 1 and math.abs(tonumber(value) - 10.0) < 1e-9)

module:free()
print("cblock arrays/views/unions/globals/fnptr (TCC): ok")
