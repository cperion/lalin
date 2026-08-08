package.path = "./?.lua;./?/init.lua;" .. package.path

local bit = require("bit")
local util = require("jit.util")
local vmdef = require("jit.vmdef")
local Exotyped = require("experiments.lua55.cps_exotype_codegen")

local function has_tail_call(fn)
    for pc = 1, 10000 do
        local instruction = util.funcbc(fn, pc)
        if instruction == nil then break end
        local opcode = bit.band(instruction, 255)
        local name = vmdef.bcnames:sub(opcode * 6 + 1, opcode * 6 + 6):match("^%s*(.-)%s*$")
        if name == "CALLT" then return true end
    end
    return false
end

local base = debug.getinfo(1, "S").source:match("^@(.*/)") or ""
local main, proto, program, stats = Exotyped.loadfile(base .. "sample_5.5.luac")
assert(#proto.protos == 2)
assert(stats.compiled_blocks == 0, "loading must create owners, not residual blocks")

local sum, mixed = main()
assert(stats.compiled_blocks > 0)
for n = 0, 1000 do
    assert(sum(n) == n * (n + 1) / 2)
    assert(mixed(n) == 1.5 * n * (n + 1) / 2)
end

local source = Exotyped.source(stats)
assert(source:find("local r = self.r", 1, true))
assert(source:find("return EDGE_", 1, true))
assert(not source:find("instruction.op", 1, true))
assert(not source:find("dispatch", 1, true))

local projection = Exotyped.projection(stats)
assert(#projection.blocks == stats.compiled_blocks)
assert(#projection.compile_order == stats.compiled_blocks)
assert(stats.fused_instructions > stats.compiled_blocks, "straight-line instructions were not fused")

local fused_block
local loop_block
for _, block in ipairs(projection.blocks) do
    if #block.instructions > 1 then fused_block = fused_block or block end
    for _, instruction in ipairs(block.instructions) do
        if instruction.opcode == "FORLOOP" then loop_block = block end
    end
end
assert(fused_block, "no fused exotype block was generated")
assert(loop_block and #loop_block.successors == 2)
assert(loop_block.successors[1].role == "repeat_target")
assert(loop_block.source:find("return EDGE_1", 1, true))

program:prepare()
assert(has_tail_call(program.root), "root residual block has no proper-tail edge")

print(("proper-exotype Lua 5.5 CPS: ok blocks=%d instructions=%d queries=%d bytes=%d"):format(
    stats.compiled_blocks, stats.fused_instructions, stats.property_queries, stats.generated_bytes))
