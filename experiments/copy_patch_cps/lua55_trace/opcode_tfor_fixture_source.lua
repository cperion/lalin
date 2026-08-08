-- Compiled with official Lua 5.5.0 luac for opcode_tfor_fixture.lua.
return function(n)
    local function it(s, var)
        var = var + 1
        if var > s then return nil end
        return var
    end
    local sum = 0
    for v in it, n, 0 do
        sum = sum + v
    end
    return sum
end
