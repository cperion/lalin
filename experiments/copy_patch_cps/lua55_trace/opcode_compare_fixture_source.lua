-- Compiled with official Lua 5.5.0 luac for opcode_compare_fixture.lua.
return function(x, y)
    local lt = x < y
    local le = x <= y
    local eq = x == y
    local ne = x ~= y
    return lt, le, eq, ne
end
