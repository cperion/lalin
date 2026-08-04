-- Hardcoded M1 benchmark: representation and trace shape, not generator code.
package.path = "./?.lua;./?/init.lua;" .. package.path

local backend_name = assert(arg[1], "backend: arena | table_graph | table_bucket")
local workload = assert(arg[2],
  "workload: construct | direct | mutate | eval | eval_scalar | eval_vtable | walk")
local size = tonumber(arg[3]) or 1000001
local reps = tonumber(arg[4]) or 5

local factory
local indexed = false
if backend_name == "arena" then
  factory = require("experiments.adt.arena")
elseif backend_name == "table_graph" then
  factory = require("experiments.adt.table")
elseif backend_name == "table_bucket" then
  factory = require("experiments.adt.table")
  indexed = true
else
  error("unknown backend: " .. backend_name)
end

local function rss_kb()
  local f = io.open("/proc/self/status", "r")
  if not f then return 0 end
  local text = f:read("*a")
  f:close()
  return tonumber(text:match("VmRSS:%s+(%d+)%s+kB")) or 0
end

local function now() return os.clock() end
local function timed(fn)
  local t0 = now()
  local result, aux = fn()
  return now() - t0, result, aux
end

collectgarbage("collect")
local lua0, rss0 = collectgarbage("count"), rss_kb()
local M = factory.new { indexed = indexed }
local elapsed, result, actual
local gc_elapsed = 0

if workload == "construct" then
  elapsed, result, actual = timed(function() return M.build_chain(size) end)
  local t0 = now()
  collectgarbage("collect")
  gc_elapsed = now() - t0
elseif workload == "direct" or workload == "mutate" then
  result, actual = M.build_chain(size)
  collectgarbage("collect")
  local fn = workload == "direct" and M.sum_nums or M.mutate_binops
  elapsed, result = timed(function()
    local checksum = 0
    for _ = 1, reps do checksum = checksum + fn() end
    return checksum
  end)
elseif workload == "eval" or workload == "eval_scalar"
    or workload == "eval_vtable" or workload == "walk" then
  local depth = size
  result, actual = M.build_tree(depth)
  collectgarbage("collect")
  local fn = workload == "eval" and M.eval
    or workload == "eval_scalar" and M.eval_scalar
    or workload == "eval_vtable" and M.eval_vtable
    or M.walk_num_sum
  local root = result
  elapsed, result = timed(function()
    local checksum = 0
    for _ = 1, reps do checksum = checksum + fn(root) end
    return checksum
  end)
else
  error("unknown workload: " .. workload)
end

local lua1, rss1 = collectgarbage("count"), rss_kb()
local num_n, binop_n = M.counts()
local visits
if workload == "direct" then visits = num_n * reps
elseif workload == "mutate" then visits = binop_n * reps
elseif workload == "eval" or workload == "eval_scalar"
    or workload == "eval_vtable" or workload == "walk" then
  visits = actual * reps
else visits = actual end

print(table.concat({
  "backend", "workload", "nodes", "reps", "seconds", "ns_per_visit",
  "gc_seconds", "lua_kb_delta", "rss_kb_delta", "arena_bytes", "checksum"
}, "\t"))
print(table.concat({
  backend_name, workload, actual, reps, string.format("%.6f", elapsed),
  string.format("%.3f", elapsed * 1e9 / visits),
  string.format("%.6f", gc_elapsed),
  string.format("%.0f", lua1 - lua0), tostring(rss1 - rss0),
  tostring(M.allocated_bytes()), tostring(result)
}, "\t"))

-- Keep result live through measurements, then release external arena memory.
if result == nil then error("benchmark result unexpectedly nil") end
M.release()
