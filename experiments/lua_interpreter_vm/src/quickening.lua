-- Lua Interpreter VM — Quickening and inline caches

local moon = require("moonlift")
local host = require("moonlift.host")
local const = require("experiments.lua_interpreter_vm.src.constants")

local I = {}
for k, v in pairs(const.Tag) do I["TAG_" .. k] = moon.int(v) end
for k, v in pairs(const.Err) do I["ERR_" .. k] = moon.int(v) end
for k, v in pairs(const.Op) do I["OP_" .. k] = moon.int(v) end

local QUICKEN_WARMUP = tonumber(os.getenv("MOONLIFT_VM_QUICKEN_WARMUP")) or 64

-- probe_gettable_cache: check inline cache hit
local probe_gettable_cache = host.region [[
region probe_gettable_cache(t: ptr(Table), key: Value, cache: ptr(InlineCache);
                            hit: cont(slot: index), stale: cont(), miss: cont())
entry start()
    if cache.epoch ~= t.shape_epoch then
        jump stale()
    end
    if cache.key.tag == key.tag and cache.key.bits == key.bits then
        jump hit(slot = as(index, cache.aux0))
    end
    jump miss()
end
end
]]

-- quicken_instruction: patch a generic opcode to quickened form
local quicken_instruction = host.region {
    QUICKEN_WARMUP = moon.int(QUICKEN_WARMUP),
    OP_LOADK = I.OP_LOADK,
    OP_MOVE = I.OP_MOVE,
    OP_ADD = I.OP_ADD,
    OP_LOADK_FAST = I.OP_LOADK_FAST,
    OP_MOVE_FAST = I.OP_MOVE_FAST,
    OP_ADD_NUM = I.OP_ADD_NUM,
    TAG_NUM = I.TAG_NUM,
} [[
region quicken_instruction(L: ptr(LuaThread), proto: ptr(Proto), pc: index, observation_kind: u32, obj: Value, key: Value;
                           patched: cont(), keep_generic: cont(), oom: cont())
entry start()
    let ip: ptr(Instr) = proto.code + pc
    if ip.op ~= @{OP_LOADK} and ip.op ~= @{OP_MOVE} and ip.op ~= @{OP_ADD} then
        jump keep_generic()
    end

    if ip.sbx <= 0 then
        ip.sbx = @{QUICKEN_WARMUP}
        jump keep_generic()
    end
    if ip.sbx > 1 then
        ip.sbx = ip.sbx - 1
        jump keep_generic()
    end

    -- ip.sbx == 1: promote now if guards hold
    if ip.op == @{OP_LOADK} then
        ip.op = as(u16, @{OP_LOADK_FAST})
        ip.sbx = -1
        jump patched()
    end
    if ip.op == @{OP_MOVE} then
        ip.op = as(u16, @{OP_MOVE_FAST})
        ip.sbx = -1
        jump patched()
    end
    if ip.op == @{OP_ADD} then
        if obj.tag == @{TAG_NUM} and key.tag == @{TAG_NUM} then
            ip.op = as(u16, @{OP_ADD_NUM})
            ip.sbx = -1
            jump patched()
        end
        ip.sbx = @{QUICKEN_WARMUP}
        jump keep_generic()
    end

    jump keep_generic()
end
end
]]

-- deopt_instruction: revert to generic opcode
local deopt_instruction = host.region {
    QUICKEN_WARMUP = moon.int(QUICKEN_WARMUP),
    OP_LOADK = I.OP_LOADK,
    OP_MOVE = I.OP_MOVE,
    OP_ADD = I.OP_ADD,
    OP_LOADK_FAST = I.OP_LOADK_FAST,
    OP_MOVE_FAST = I.OP_MOVE_FAST,
    OP_ADD_NUM = I.OP_ADD_NUM,
} [[
region deopt_instruction(proto: ptr(Proto), pc: index; done: cont())
entry start()
    let ip: ptr(Instr) = proto.code + pc
    if ip.op == @{OP_LOADK_FAST} then
        ip.op = as(u16, @{OP_LOADK})
        ip.sbx = @{QUICKEN_WARMUP}
        jump done()
    end
    if ip.op == @{OP_MOVE_FAST} then
        ip.op = as(u16, @{OP_MOVE})
        ip.sbx = @{QUICKEN_WARMUP}
        jump done()
    end
    if ip.op == @{OP_ADD_NUM} then
        ip.op = as(u16, @{OP_ADD})
        ip.sbx = @{QUICKEN_WARMUP}
        jump done()
    end
    jump done()
end
end
]]

return {
    probe_gettable_cache = probe_gettable_cache,
    quicken_instruction = quicken_instruction,
    deopt_instruction = deopt_instruction,
}
