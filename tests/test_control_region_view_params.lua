package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local moon = require("moonlift")

-- Regression: control-region block params may be view descriptors.  Emitting a
-- region with a view-valued runtime parameter must lower the descriptor as
-- (data, len, stride) block args, not as one scalar jump arg.
local scan = moon.loadstring([[
local scan = region scan(xs: view(i32); done(total: i32))
entry start()
    jump loop(i = as(index, 0), acc = 0)
end
block loop(i: index, acc: i32)
    if i >= len(xs) then jump done(total = acc) end
    jump loop(i = i + 1, acc = acc + xs[i])
end
end
return scan
]], "control_region_view_param_scan")()

local main = moon.func{ scan = scan }[[
func main(xs: ptr(i32), n: index): i32
    let v: view(i32) = view(xs, n)
    return region: i32
    entry start()
        emit @{scan}(v; done = got)
    end
    block got(total: i32)
        yield total
    end
    end
end
]]

local compiled = main:compile()
local xs = ffi.new("int32_t[4]", { 1, 2, 3, 4 })
assert(compiled(xs, 4) == 10)
compiled:free()

print("ok control region view params")
