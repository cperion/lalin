local C = require("cblock")

local csrc, errors = C.compile(function()
    local host_add = extern(i32, i32, ret(i32))
    local host_note = extern(i32, ret())

    local add_twice = func(i32, i32, ret(i32))(function(a, b)
        return host_add(a, b) * 2
    end)

    local note = func(i32, ret())(function(value)
        return host_note(value)
    end)

    return {
        host_add = host_add, host_note = host_note,
        add_twice = add_twice, note = note,
    }
end)

if not csrc then error(table.concat(errors, "\n")) end
assert(csrc:find("int32_t host_add(int32_t r1, int32_t r2);", 1, true))
assert(csrc:find("void host_note(int32_t r1);", 1, true))

local base = os.tmpname()
os.remove(base)
local cpath, exe = base .. ".c", base .. ".out"
local f = assert(io.open(cpath, "w"))
f:write(csrc, [[

static int seen;
int32_t host_add(int32_t a, int32_t b) { return a + b; }
void host_note(int32_t value) { seen = value; }
int main(void) {
    if (add_twice(3, 4) != 14) return 1;
    note(42);
    return seen == 42 ? 0 : 2;
}
]])
f:close()
local ok, why, code = os.execute(("cc -O2 -o %s %s && %s"):format(exe, cpath, exe))
os.remove(cpath) os.remove(exe)
assert(ok == true or ok == 0, ("extern test failed: %s %s"):format(why, code))
print("cblock extern direct C values: ok")
