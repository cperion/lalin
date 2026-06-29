package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local function shell_quote(s)
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local function command_ok(cmd)
    local ok = os.execute(cmd)
    return ok == true or ok == 0
end

local function read_file(path)
    local f = assert(io.open(path, "rb"))
    local s = f:read("*a")
    f:close()
    return s
end

local dir = "target/test_artifacts/test_lalin_mc_bank_generator"
local c_path = dir .. "/bank.c"
local h_path = dir .. "/bank.h"
local shard_prefix = dir .. "/worker_shard"

assert(command_ok("mkdir -p " .. shell_quote(dir)))
assert(command_ok(
    "LALIN_MC_BANK_WORKER=1 "
        .. "LALIN_MC_BANK_SHARD_INDEX=1 "
        .. "LALIN_MC_BANK_SHARD_COUNT=4096 "
        .. "LALIN_MC_BANK_SHARD_PREFIX=" .. shell_quote(shard_prefix) .. " "
        .. "luajit tools/gen_lalin_mc_bank.lua "
        .. shell_quote(c_path) .. " " .. shell_quote(h_path)
        .. " 2> " .. shell_quote(dir .. "/generator.log")
), "expected MC bank generator worker to emit one saturation shard")

local log = read_file(dir .. "/generator.log")
local payload = tonumber(log:match("(%d+) payload bytes"))
local count = tonumber(read_file(shard_prefix .. ".count"):match("%d+"))
local arrays = read_file(shard_prefix .. ".arrays.cfrag")
local entries = read_file(shard_prefix .. ".entries.cfrag")

assert(count ~= nil and count > 0, "expected worker shard to contain saturation cells")
assert(payload ~= nil and payload > 0, "expected worker shard to report compiled payload bytes")
assert(arrays:find("static const unsigned char lalin_mc_", 1, true), "expected generated MC byte arrays in worker fragment")
assert(
    entries:find("bank_o1_", 1, true) or entries:find("meta_", 1, true),
    "expected worker shard to emit primitive or composed saturation cells"
)

io.write("lalin mc bank generator ok\n")
