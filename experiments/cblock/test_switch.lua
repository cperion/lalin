local C = require("cblock")

local csrc, errors = C.compile(function()
    local Opcode = enum {
        add = 0,
        sub = 1,
        halt = 2,
    }

    -- dispatch on an opcode to named blocks, threaded interpreter style
    local run = region(i32, cont(i64), cont())(function(opcode, done, trapped)
        local do_add, do_sub, do_halt, dispatch

        dispatch = block()(function()
            return switch_(opcode)
                :case_(Opcode.add):then_(do_add)
                :case_(Opcode.sub):then_(do_sub)
                :default(do_halt)
        end)

        do_add = block()(function() return done(10) end)
        do_sub = block()(function() return done(20) end)
        do_halt = block()(function() return trapped() end)

        return dispatch()
    end)

    local run_fn = call(run)
    return { machine = { run = run_fn } }
end)

if not csrc then error(table.concat(errors, "\n")) end

local base = os.tmpname()
os.remove(base)
local cpath, exe = base .. ".c", base .. ".out"
local f = assert(io.open(cpath, "w"))
f:write(csrc, [[
int main(void) {
    int64_t out = 0; int e = 0;
    e = machine_run(0, &out);
    if (e != 1 || out != 10) return 1;
    e = machine_run(1, &out);
    if (e != 1 || out != 20) return 2;
    e = machine_run(2, &out);
    if (e != 2) return 3;
    e = machine_run(99, &out);
    if (e != 2) return 4;      /* unknown opcode falls to default */
    return 0;
}
]])
f:close()
local ok, why, code = os.execute(("cc -std=c99 -O2 -o %s %s && %s"):format(exe, cpath, exe))
os.remove(cpath) os.remove(exe)
assert(ok == true or ok == 0, ("switch test failed: %s %s"):format(why, code))
print("cblock switch_ + enum (GCC): ok")

-- TCC path
local module, runtime = C.jit(function()
    local Opcode = enum { add = 0, sub = 1, halt = 2 }
    local run = region(i32, cont(i64), cont())(function(opcode, done, trapped)
        local do_add, do_sub, do_halt, dispatch
        dispatch = block()(function()
            return switch_(opcode)
                :case_(Opcode.add):then_(do_add)
                :case_(Opcode.sub):then_(do_sub)
                :default(do_halt)
        end)
        do_add = block()(function() return done(10) end)
        do_sub = block()(function() return done(20) end)
        do_halt = block()(function() return trapped() end)
        return dispatch()
    end)
    local run_fn = call(run)
    return { machine = { run = run_fn } }
end)
assert(module, runtime)

local exit, value = module.machine.run(0)
assert(exit == 1 and tonumber(value) == 10)
exit, value = module.machine.run(1)
assert(exit == 1 and tonumber(value) == 20)
exit, value = module.machine.run(2)
assert(exit == 2 and value == nil)
exit, value = module.machine.run(99)
assert(exit == 2 and value == nil)

module:free()
print("cblock switch_ + enum (TCC): ok")
