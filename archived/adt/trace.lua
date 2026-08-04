-- Build with the JIT disabled, then trace only the requested hot operation.
package.path = "./?.lua;./?/init.lua;" .. package.path

local jit = require("jit")
local backend_name = assert(arg[1], "backend: arena | table_graph | table_bucket")
local mode = assert(arg[2],
  "mode: construct | direct | mutate | eval | eval_scalar | eval_vtable | walk")
local size = tonumber(arg[3]) or 300001
local reps = tonumber(arg[4]) or 4

local factory, indexed
if backend_name == "arena" then
  factory, indexed = require("experiments.adt.arena"), false
elseif backend_name == "table_graph" then
  factory, indexed = require("experiments.adt.table"), false
elseif backend_name == "table_bucket" then
  factory, indexed = require("experiments.adt.table"), true
else
  error("unknown backend: " .. backend_name)
end

jit.off()
local M = factory.new { indexed = indexed }
local root, actual
if mode ~= "construct" then
  if mode == "eval" or mode == "eval_scalar" or mode == "eval_vtable"
      or mode == "walk" then
    root, actual = M.build_tree(size)
  else
    root, actual = M.build_chain(size)
  end
end
collectgarbage("collect")
jit.flush()
jit.opt.start("hotloop=20", "hotexit=10")
jit.on()

local profile_mode = os.getenv("ADT_PROFILE")
local profiler
if profile_mode then
  -- Warm the requested operation so sampling excludes trace compilation and setup.
  if mode == "direct" then M.sum_nums()
  elseif mode == "mutate" then M.mutate_binops()
  elseif mode == "eval" then M.eval(root)
  elseif mode == "eval_scalar" then M.eval_scalar(root)
  elseif mode == "eval_vtable" then M.eval_vtable(root)
  elseif mode == "walk" then M.walk_num_sum(root) end
  profiler = require("jit.p")
  profiler.start(profile_mode)
end

local checksum = 0
if mode == "construct" then
  root, actual = M.build_chain(size)
  checksum = M.tag(root)
elseif mode == "direct" then
  for _ = 1, reps do checksum = checksum + M.sum_nums() end
elseif mode == "mutate" then
  for _ = 1, reps do checksum = checksum + M.mutate_binops() end
elseif mode == "eval" then
  for _ = 1, reps do checksum = checksum + M.eval(root) end
elseif mode == "eval_scalar" then
  for _ = 1, reps do checksum = checksum + M.eval_scalar(root) end
elseif mode == "eval_vtable" then
  for _ = 1, reps do checksum = checksum + M.eval_vtable(root) end
elseif mode == "walk" then
  for _ = 1, reps do checksum = checksum + M.walk_num_sum(root) end
else
  error("unknown trace mode: " .. mode)
end

if profiler then profiler.stop() end
jit.off()
io.stdout:write(string.format("backend=%s mode=%s nodes=%d checksum=%s\n",
  backend_name, mode, actual, tostring(checksum)))
M.release()
