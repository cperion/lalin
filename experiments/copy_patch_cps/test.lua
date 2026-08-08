package.path = "./?.lua;./?/init.lua;" .. package.path

local bank = dofile("target/copy_patch_cps/bank.lua")
local program = bank:link()
local frame = program:new_frame()

local function expected(limit)
    if limit < 1 then return 0 end
    return limit * (limit + 1) / 2
end

for limit = -16, 10000 do
    program:execute(frame, limit)
    assert(tonumber(frame.result) == expected(limit), "wrong sum for " .. limit)
end

assert(program.layout.entry == 0)
assert(program.layout.loop > program.layout.entry)
assert(program.layout.body > program.layout.loop)
assert(program.layout.finish > program.layout.body)
assert(program.size < 256, "unexpectedly large linked native program")

collectgarbage("collect")
collectgarbage("stop")
local before = collectgarbage("count")
for _ = 1, 10000 do program:execute(frame, 100) end
local growth = collectgarbage("count") - before
collectgarbage("restart")
assert(growth < 4, ("recurring native calls allocated %.3f KiB"):format(growth))

local bytes = program.size
program:free()
local ok = pcall(function() program:execute(frame, 1) end)
assert(not ok, "released program remained callable")

print(("copy-patch native CPS: ok bytes=%d gcc=%s"):format(bytes, bank.gcc))
