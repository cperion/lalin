-- Compiled with official Lua 5.5.0 luac (Lua 5.5.0).
-- opcode_generic_table_gnew2_fixture_source.lua: NEWTABLE + EXTRAARG +
-- SETI + GETI + RETURN1 (value from a register, so the SETI uses a
-- plain register operand, not an RK constant).
local hex = table.concat({
    "1b4c7561550019930d0a1a0a0488a9ffff04785634120888a9ffffffffffff0800000000002877c00100000001020400",
    "530000004f00000046000201460001010001010000010105010003069300000054000000910001000d01010148010200",
    "4701010000000010402f746d702f676e6577332e6c756100060100010100010002027600000602740002060000010401",
    "040000000001055f454e5600",
})

return (hex:gsub("..", function(pair) return string.char(assert(tonumber(pair, 16))) end))
