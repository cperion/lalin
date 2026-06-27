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
), "expected MC bank generator worker to emit one fixed-bank shard")

local log = read_file(dir .. "/generator.log")
local payload = tonumber(log:match("(%d+) payload bytes"))
local count = tonumber(read_file(shard_prefix .. ".count"):match("%d+"))
local arrays = read_file(shard_prefix .. ".arrays.cfrag")
local entries = read_file(shard_prefix .. ".entries.cfrag")

assert(count ~= nil and count > 0, "expected worker shard to contain fixed-bank cells")
assert(payload ~= nil and payload > 0, "expected worker shard to report compiled payload bytes")
assert(arrays:find("static const unsigned char lalin_mc_", 1, true), "expected generated MC byte arrays in worker fragment")
assert(entries:find("bank_o1_in1_", 1, true), "expected fixed bank shard to emit order-1 width-1 cells")
assert(not entries:find("bank_o2_", 1, true), "fixed bank shard must not include order-2 fusion cells")
assert(not entries:find("bank_o1_in2_", 1, true), "fixed bank shard must not include width-2 cells")

io.write("lalin mc bank generator ok\n")
