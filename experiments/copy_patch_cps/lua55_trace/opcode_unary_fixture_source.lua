-- Compiled with official Lua 5.5.0 luac for opcode_unary_fixture.lua.
return function(x, s, t)
    local u = -x
    local n = ~x
    local b = not x
    local l = #s
    local tl = #t
    return u, n, b, l, tl
end
