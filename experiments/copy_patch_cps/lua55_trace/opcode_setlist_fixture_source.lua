-- Compiled with official Lua 5.5.0 luac for opcode_setlist_fixture.lua.
return function(v)
    local t = {1, 2, 3}
    t[4] = v
    return t
end
