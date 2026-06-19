package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local Host = require("moonlift.mlua_run")

local fn = Host.eval [[
local Input = struct
    x: i32,
    y: i32,
end

local ParseExit = union
    ok(value: i32)
  | err(code: i32)
end

local add_or_err = region(Input; ParseExit)
entry start()
    if x < 0 then jump err(code = x) end
    jump ok(value = x + y)
end
end

return func(Input): i32
    return region: i32
    entry start()
        emit @{add_or_err}(x, y; ok = good, err = bad)
    end
    block good(value: i32)
        yield value
    end
    block bad(code: i32)
        yield code
    end
    end
end
]]

local c = fn:compile()
assert(c(20, 22) == 42)
assert(c(-7, 99) == -7)
c:free()

-- Inline single bare exit still means an exit unless a union of that name is known.
local single = Host.eval [[
local one = region(x: i32; done)
entry start()
    jump done()
end
end
return one
]]
assert(single.name == "one")
assert(#single.frag.conts == 1)
assert(single.frag.conts[1].pretty_name == "done")

print("moonlift named protocol/product sugar ok")
