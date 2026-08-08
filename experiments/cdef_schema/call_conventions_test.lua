package.path = "./lua/?.lua;./lua/?/init.lua;./?.lua;./?/init.lua;" .. package.path

local Conventions = require("experiments.cdef_schema.call_conventions")

local depths = { 1, 2, 4, 8, 16, 32, 64, 90 }
for _, depth in ipairs(depths) do
    local machines = Conventions.build(depth)
    local cycles = 37

    local tail_result = machines.tail.run(cycles)
    assert(tonumber(tail_result) == depth * cycles)
    assert(tonumber(machines.tail.state.enters) == depth * cycles)
    assert(tonumber(machines.tail.state.unwinds) == 0)

    local host_enters, host_unwinds, host_result = machines.host.run(cycles)
    assert(tonumber(host_enters) == depth * cycles)
    assert(tonumber(host_unwinds) == (depth - 1) * cycles)
    assert(host_result == cycles)

    local explicit_result = machines.explicit.run(cycles)
    assert(tonumber(explicit_result) == depth * cycles)
    assert(tonumber(machines.explicit.state.enters) == depth * cycles)
    assert(tonumber(machines.explicit.state.unwinds) == depth * cycles)
    assert(machines.explicit.state.sp == 0)
    assert(machines.explicit.state.suspended == 0)

    local suspended_result = machines.explicit.start_suspended(cycles)
    assert(tonumber(suspended_result) == depth)
    assert(machines.explicit.state.sp == depth)
    assert(machines.explicit.state.suspended == 1)
    for operation = 1, cycles do
        local result = machines.explicit.resume()
        if operation < cycles then
            assert(tonumber(result) == depth)
            assert(machines.explicit.state.sp == depth)
            assert(machines.explicit.state.suspended == 1)
        else
            assert(tonumber(result) == depth * cycles)
            assert(machines.explicit.state.sp == 0)
            assert(machines.explicit.state.suspended == 0)
        end
    end
    assert(tonumber(machines.explicit.state.enters) == depth * cycles)
    assert(tonumber(machines.explicit.state.unwinds) == depth * cycles)
end

local shapes = Conventions.build(4)
assert(Conventions.has_bytecode(shapes.tail.first, "CALLT"),
    "tail convention must compile its successor as CALLT")
assert(Conventions.has_bytecode(shapes.host.first, "CALL"),
    "host-framed convention must retain an ordinary CALL")
assert(not Conventions.has_bytecode(shapes.host.first, "CALLT"),
    "host-framed successor must not become CALLT")
assert(Conventions.has_bytecode(shapes.explicit.first, "CALLT"),
    "explicit-frame entry must tail-call its successor")
assert(Conventions.has_bytecode(shapes.explicit.first_resume, "CALLT"),
    "explicit-frame resume must tail-call its successor")

print("tail, host-stack, and explicit-frame call conventions: ok")

