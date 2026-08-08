-- Compiled with official Lua 5.5.0 luac for opcode_jmp_fixture_source.lua:
-- a while loop: LOADI, LT(owned JMP), ADDI(owned MMBINI), standalone back-edge JMP.
local hex = table.concat({
    "1b4c7561550019930d0a1a0a0488a9ffff04785634120888a9ffffffffffff0800000000002877c00100000001020400",
    "530000004f00000046000201460001010001010000010105010002088180ff7fba0000003801008095000180af008006",
    "38fdff7fc80002004701010000000010402f746d702f7768696c652e6c75610008010100000000010100020261000008",
    "02780001080000010401040000000001055f454e5600",
})

return (hex:gsub("..", function(pair) return string.char(assert(tonumber(pair, 16))) end))
