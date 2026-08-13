local C = require("cblock")

local csrc, errors = C.compile(function()
    local Vec2 = struct {
        field: x (f64),
        field: y (f64),
    }

    function Vec2:length_squared()
        return self.x * self.x + self.y * self.y
    end

    Vec2: add (Vec2, cont(Vec2)) (function(self, other)
        return Vec2 { x = self.x + other.x, y = self.y + other.y }
    end)

    local add = func(Vec2, Vec2, ret(Vec2))(function(a, b)
        return a:add(b)
    end)
    local add_called = func(Vec2, Vec2, ret(Vec2))(function(a, b)
        return call(Vec2.add)(a, b)
    end)

    local length_squared = func(Vec2, ret(f64))(function(v)
        return v:length_squared()
    end)

    return {
        geometry = { Vec2 = Vec2, add = add, add_called = add_called,
            length_squared = length_squared },
    }
end)

if not csrc then error(table.concat(errors, "\n")) end
assert(csrc:find("typedef struct geometry_Vec2 geometry_Vec2;", 1, true))
assert(csrc:find("r1.x", 1, true))

local base = os.tmpname()
os.remove(base)
local cpath, exe = base .. ".c", base .. ".out"
local f = assert(io.open(cpath, "w"))
f:write(csrc, [[

int main(void) {
    geometry_Vec2 a = { 1.0, 2.0 };
    geometry_Vec2 b = { 3.0, 4.0 };
    geometry_Vec2 c = geometry_add(a, b);
    geometry_Vec2 d = geometry_add_called(a, b);
    if (c.x != 4.0 || c.y != 6.0 || d.x != 4.0 || d.y != 6.0) return 1;
    if (geometry_length_squared(c) != 52.0) return 2;
    return 0;
}
]])
f:close()
local ok, why, code = os.execute(("cc -std=c99 -O2 -o %s %s && %s"):format(exe, cpath, exe))
os.remove(cpath) os.remove(exe)
assert(ok == true or ok == 0, ("struct test failed: %s %s"):format(why, code))
print("cblock structs + inline Lua methods: ok")
