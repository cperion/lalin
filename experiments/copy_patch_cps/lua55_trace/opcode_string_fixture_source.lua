-- Compiled with official Lua 5.5.0 luac for opcode_string_fixture.lua.
return function()
    local short = "field"
    local long = "this string is deliberately longer than forty bytes for Lua 5.5"
    local a = short
    local b = long
    return a, b
end
