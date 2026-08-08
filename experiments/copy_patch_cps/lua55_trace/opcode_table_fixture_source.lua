-- Compiled with official Lua 5.5.0 luac for opcode_table_fixture.lua.
return function(t, v)
    local a = t[1]
    local b = t.field
    t[2] = v
    t.other = v
    return a, b
end
