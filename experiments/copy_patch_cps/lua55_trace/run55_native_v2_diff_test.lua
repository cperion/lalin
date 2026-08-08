package.path = "./lua/?.lua;./lua/?/init.lua;./?.lua;./?/init.lua;" .. package.path
local CPS = require("experiments.copy_patch_cps.lua55_trace.cps_invocation_v2")
local STOCK = "/tmp/lua-5.5.0/src/lua"
local function stock_capture(src)
  local path = os.tmpname() .. ".lua"
  local f = assert(io.open(path, "wb")); f:write(src); f:close()
  local cmd = STOCK .. " experiments/copy_patch_cps/lua55_trace/capture55.lua " .. path
  local pipe = assert(io.popen(cmd, "r"))
  local out = pipe:read("*a"); local ok_close = pipe:close()
  os.remove(path)
  assert(ok_close, "stock failed: " .. out)
  return out
end
local function native(src)
  local path = os.tmpname() .. ".lua"
  local f = assert(io.open(path, "wb")); f:write(src); f:close()
  local ok, values = pcall(CPS.run, path)
  os.remove(path)
  assert(ok, values)
  local parts = {}
  for _, v in ipairs(values) do parts[#parts+1] = tostring(v) end
  return table.concat(parts, "\t") .. "\n"
end
local function wrap(src)
  -- turn a trailing top-level `return a, b` into `print(a, b)`
  local lines = {}
  for line in src:gmatch("[^\n]+") do
    local m = line:match("^return%s+(.+)$")
    if m then lines[#lines+1] = "print(" .. m .. ")" else lines[#lines+1] = line end
  end
  return table.concat(lines, "\n")
end

local programs = {
  multi = [=[
local function f() return 1, 2, 3 end
local a, b, c = f()
return a + b + c
]=],
  b0 = [=[
local function f() return 10, 20 end
local function g()
  local x = f()
  return x
end
return g()
]=],
  nested = [=[
local function a(x) return x + 1 end
local function b(x) return a(x) * 2 end
local function c(x) return b(x) - 3 end
return c(10), c(20), c(30)
]=],
  tbl_fields = [=[
local t = {}
t.x = 1
t.y = 2
t.x = t.x + t.y
return t.x, t.y
]=],
  tbl_array = [=[
local t = {}
t[1] = 10
t[2] = 20
t[3] = t[1] + t[2]
return t[3]
]=],
  tbl_literal = [=[
local t = { 10, 20, 30 }
return t[1] + t[2] + t[3]
]=],
  tbl_field_literal = [=[
local t = { x = 5, y = 7 }
return t.x + t.y
]=],
  tbl_gettable = [=[
local t = { 1, 2, 3 }
local k = 2
return t[k], t["missing"]
]=],
  tbl_settable = [=[
local t = {}
local k = "a"
t[k] = 99
return t.a
]=],
  tbl_nested = [=[
local t = {}
t.inner = {}
t.inner.v = 42
return t.inner.v
]=],
  tbl_env_loop = [=[
local t = { 3, 1, 2 }
local s = t[1]
for i = 2, 3 do
  if t[i] < s then s = t[i] end
end
return s
]=],
  self_method = [=[
local obj = { v = 21 }
function obj:get() return self.v end
return obj:get()
]=],
  vararg_sum = [=[
local function f(...)
  local a, b, c = ...
  return a + b + c
end
return f(10, 20, 30)
]=],
  vararg_count = [=[
local function f(...)
  return select("#", ...)
end
return f(1, 2, 3, 4)
]=],
  vararg_mixed = [=[
local function f(x, ...)
  return x + select(1, ...)
end
return f(10, 20, 30)
]=],
  vararg_all = [=[
local function f(...)
  return ...
end
return f(1, 2, 3)
]=],
  vararg_forward = [=[
local function inner(...) return ... end
local function outer(...) return inner(...) end
return outer(7, 8, 9)
]=],
  getvarg_n = [=[
local function f(...)
  return select("#", ...), ...
end
return f("a", "b")
]=],
  pairs_sum = [=[
local t = { 1, 2, 3 }
local s = 0
for k, v in pairs(t) do s = s + v end
return s
]=],
  ipairs_sum = [=[
local t = { 10, 20, 30, 40 }
local s = 0
for i, v in ipairs(t) do s = s + i * v end
return s
]=],
  pairs_fields = [=[
local t = { x = 5, y = 7, z = 9 }
local s = 0
for k, v in pairs(t) do s = s + v end
return s
]=],
  closure_iter = [=[
local function gen(t)
  local i = 0
  return function()
    i = i + 1
    if i > 3 then return nil end
    return i, t[i]
  end
end
local t = { 5, 6, 7 }
local s = 0
for k, v in gen(t) do s = s + v end
return s
]=],
  next_direct = [=[
local t = { 1, 2, 3 }
local s = 0
for k, v in next, t, nil do s = s + v end
return s
]=],
  pairs_empty = [=[
local t = {}
local n = 0
for k, v in pairs(t) do n = n + 1 end
return n
]=],
  concat_str = [=[
local a = "hello"
local b = " "
local c = "world"
return a .. b .. c
]=],
  concat_int = [=[
local x = 42
return "value: " .. x
]=],
  concat_flt = [=[
local x = 3.14159
return "pi = " .. x
]=],
  concat_loop = [=[
local s = ""
local t = { "a", "b", "c", "d" }
for i = 1, 4 do s = s .. t[i] end
return s
]=],
  concat_long = [=[
local s = ""
for i = 1, 10 do s = s .. "0123456789" end
return s
]=],
  forcall = [=[
local function add(a, b) return a + b end
local s = 0
for i = 1, 10 do s = add(s, i) end
return s
]=],
  closure_counter = [=[
local function make(n)
  return function() n = n + 1 return n end
end
local c1, c2 = make(0), make(100)
return c1(), c1(), c2(), c1()
]=],
  swap = [=[
local function swap(a, b) return b, a end
local x, y = swap(1, 2)
return x * 10 + y
]=],
  tailacc = [=[
local function sum(n, acc)
  if n == 0 then return acc end
  return sum(n - 1, acc + n)
end
return sum(500000, 0)
]=],
  multi_closures = [=[
local function pair()
  local x = 1
  local f = function() x = x + 1 return x end
  local g = function() x = x * 2 return x end
  return f, g
end
local f, g = pair()
local r1 = f()
local r2 = g()
return r1, r2, f()
]=],
}
local failures = 0
for name, src in pairs(programs) do
  local s = stock_capture(src)
  local n = native(src)
  local ok = s == n
  if not ok then failures = failures + 1 end
  print(("  %-16s stock=%-24s native=%-24s %s"):format(name, s:gsub("\n",""), n:gsub("\n",""), ok and "OK" or "MISMATCH"))
end
print(failures == 0 and "lua55 v2 differential: ok, all cases match stock" or (failures .. " MISMATCHES"))
