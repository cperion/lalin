local C = require("cblock")

local csrc, errors = C.compile(function()
    local Vec2 = struct {
        field: x (f64),
        field: y (f64),
    }

    function Vec2:length_squared()
        return self.x * self.x + self.y * self.y
    end

    Vec2: add (param: other (Vec2)) (Vec2) (function(p)
        return Vec2 {
            x = p.self.x + p.other.x, y = p.self.y + p.other.y,
        }
    end)

    local add = func
        (param: a (Vec2), param: b (Vec2))
        (Vec2)
        (function(p) return p.a:add(p.b) end)
    local add_called = func
        (param: a (Vec2), param: b (Vec2))
        (Vec2)
        (function(p) return call(Vec2.add)(p.a, p.b) end)

    local length_squared = func (param: v (Vec2)) (f64)
        (function(p) return p.v:length_squared() end)

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
