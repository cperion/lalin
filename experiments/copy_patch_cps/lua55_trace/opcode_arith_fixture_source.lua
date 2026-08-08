-- Compiled with official Lua 5.5.0 luac for opcode_arith_fixture.lua.
return function(a, b)
    local r1 = a + b
    local r2 = a - b
    local r3 = a * b
    local r4 = a // b
    local r5 = a % b
    local r6 = a / b
    local r7 = a & b
    local r8 = a | b
    local r9 = a ~ b
    local r10 = a << 2
    local r11 = a >> 2
    local r12 = 2 << a
    local r13 = a + 5
    local r14 = a * 2.5
    return r1, r2, r3, r4, r5, r6, r7, r8, r9, r10, r11, r12, r13, r14
end
