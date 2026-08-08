-- Compiled with official Lua 5.5.0 luac for opcode_00_10_fixture.lua.
local u1, u2, u3, u4, u5 = 0, 0, false, true, nil

return function(x)
    local m = x
    local i = 42
    local f = 3.0
    local k = 2.5
    local a = false
    local b = true
    local c = nil

    u1 = m
    m = u1
    u2 = k
    k = u2
    u3 = a
    a = u3
    u4 = b
    b = u4
    u5 = c
    c = u5

    return m, i, f, k, a, b, c
end
