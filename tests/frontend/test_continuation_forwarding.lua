package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local moon = require("moonlift")

local src = [[
local inner = region(x: i32; hit(value: i32) | fail(code: i32))
entry start()
    if x > 0 then jump hit(value = x) end
    jump fail(code = 1)
end
end

local outer = region(x: i32; ok(value: i32) | bad(code: i32))
entry start()
    emit @{inner}(x; hit = ok, fail = bad)
end
end

local main = func(x: i32): i32
    return region: i32
    entry start()
        emit @{outer}(x; ok = good, bad = nope)
    end
    block good(value: i32)
        yield value
    end
    block nope(code: i32)
        yield 0 - code
    end
    end
end

return main
]]

local fn = moon.loadstring(src, "test_continuation_forwarding.mlua")()
local compiled = fn:compile()
assert(compiled(7) == 7)
assert(compiled(-1) == -1)
compiled:free()

print("moonlift continuation forwarding ok")
