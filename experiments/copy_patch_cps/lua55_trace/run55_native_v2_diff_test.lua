package.path = "./lua/?.lua;./lua/?/init.lua;./?.lua;./?/init.lua;" .. package.path
local CPS = require("experiments.copy_patch_cps.lua55_trace.cps_invocation_v2")
local STOCK = "/tmp/lua-5.5.0/src/lua"
local function stock_capture(src)
  local path = os.tmpname() .. ".lua"
  local f = assert(io.open(path, "wb")); f:write(src); f:close()
  local cmd = STOCK .. " experiments/copy_patch_cps/lua55_trace/capture55.lua " .. path
  local pipe = assert(io.popen(cmd, "r"))
  local out = pipe:read("*a"); local ok_close = pipe:close()
  if not ok_close then
    local dump = io.open(path, "rb")
    io.stderr:write("FAIL ", path, " :: ", out, "\nDUMP:\n", dump and dump:read("*a") or "", "\n")
    if dump then dump:close() end
  end
  os.remove(path)
  assert(ok_close, "stock failed: " .. out)
  return out
end
local SCALAR_ONLY = arg[1] == "scalar"
  or os.getenv("LUA55_V2_SCALAR_ONLY") == "1"
local function native(src)
  local path = os.tmpname() .. ".lua"
  local f = assert(io.open(path, "wb")); f:write(src); f:close()
  local ok, values = pcall(CPS.run, path, { scalar_only = SCALAR_ONLY })
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
  sieve_exact = [=[
local limit = 10000
local composite = {}
local count = 0
for p = 2, limit do
  if not composite[p] then
    count = count + 1
    if p * p <= limit then
      for multiple = p * p, limit, p do composite[multiple] = true end
    end
  end
end
return count
]=],
  table_init_false = [=[
local t = {}
for i = 1, 1000 do t[i] = false end
t[500] = true
return t[500], t[1], t[1001]
]=],
  table_float_values = [=[
local t = {}
for i = 1, 100 do t[i] = i * 0.5 end
return t[10] * 2 + 0.25, t[99] * 2 + 0.25
]=],
  table_string_keys = [=[
local t = {}
local k = "k50"
t[k] = 50
local k2 = "k100"
t[k2] = 100
return t[k], t[k2], t["k0"]
]=],
  table_dynamic_key = [=[
local t = { 1, 2, 3 }
local k = 2
t[k] = t[k] + 10
local s = "k1"
t[s] = 99
return t[2], t[s]
]=],
  shifts_exact = [=[
local x = 8
local y = 3
return (x >> 1), (x << 2), (y >> 1), (y << 4), (x >> y), (x << y)
]=],
  arith_mixed = [=[
local function f(a, b)
  return "" .. a + b .. "|" .. a * b .. "|" .. a - b .. "|" .. a / b
    .. "|" .. a % b .. "|" .. a // b
end
return f(10, 3) .. "#" .. f(10.5, 2) .. "#" .. f(7, 2.25)
]=],
  arith_k_ops = [=[
local x = 100
local y = 17
local z = x % 7 + x // 9 + y ^ 2 + 0.5
return z, x + 1000, y - 5
]=],
  compare_mixed = [=[
local function f(a, b, s, t)
  local r = 0
  if a < b then r = r + 1 end
  if a > 5 then r = r + 2 end
  if a <= b then r = r + 4 end
  if a == b then r = r + 8 end
  if s == "done" then r = r + 16 end
  if t == nil then r = r + 32 end
  if s ~= t then r = r + 64 end
  return r
end
return f(3, 7, "done", 1), f(9, 2, "x", nil), f(5, 5, "done", "done")
]=],
  unary_exact = [=[
local x = -42
local y = 3.5
local s = "hello"
local t = {1, 2, 3}
return -x, -y, ~x, #s, #t, not x, not nil, not false
]=],
  numfor_int_pos = [=[
local s = 0
for i = 1, 100 do s = s + i end
return s
]=],
  numfor_int_neg = [=[
local s = 0
for i = 100, 1, -2 do s = s + i end
return s
]=],
  numfor_flt = [=[
local s = 0
for x = 0.5, 10, 1.5 do s = s + x end
return "" .. s
]=],
  numfor_flt_mixed = [=[
local s = 0
for x = 1, 5.5, 0.5 do s = s + x end
return "" .. s
]=],
  numfor_skip = [=[
local n = 0
for i = 10, 1 do n = n + 1 end
for i = 1, 10, -1 do n = n + 1 end
return n
]=],
  numfor_big = [=[
local s = 0
for i = 1, 1000, 7 do s = s + i end
return s
]=],
  numfor_nested = [=[
local s = 0
for i = 1, 10 do
  for j = 10, 1, -1 do s = s + i * j end
end
return s
]=],
  calls_vararg_callee = [=[
local function f(a, ...)
  return a + select("#", ...)
end
local function g(b, ...)
  return f(b, ...)
end
return g(1, 2, 3, 4)
]=],
  calls_builtin_tail = [=[
local function f(n, ...)
  if n == 0 then return select(1, ...) end
  return f(n - 1, ...)
end
return f(3, 42)
]=],
  calls_select_tail = [=[
local function f(...)
  return select("#", ...)
end
return f(1, 2, 3)
]=],
  calls_mixed_arity = [=[
local function f(a, b) return a * 10 + b end
local function g(a, b, c) return a + b + c end
return f(1, 2), g(1, 2, 3), f(g(1, 2, 3), 4)
]=],
  concat_vec_3 = [=[
local a, b, c = "x", 7, 2.5
return a .. b .. c .. "|" .. 1 .. a .. 3.5 .. "|" .. 2 .. 3 .. a
]=],
  concat_vec_mixed = [=[
local t = { 1.5, "a", 2, "b", 3.25 }
return t[1] .. t[2] .. t[3] .. t[4] .. t[5]
]=],
  concat_vec_loop = [=[
local s = ""
for i = 1, 5 do s = s .. "n=" .. i .. ";" end
return s
]=],
  settabup_global = [=[
local x = 1
_ENV.x = 2
local y = _ENV.x
_ENV["z"] = 3
return y + x
]=],
  setlist_grow = [=[
local t = {}
for i = 1, 20 do t[i] = i * 2 end
return t[1], t[10], t[20], #t
]=],
  loadnil_span = [=[
local a, b, c, d
return a, b, c, d
]=],
  loadnil_preserves_higher_register = [=[
local a, b
local keep = 99
a, b = nil, nil
return keep, a, b
]=],
  ret_all = [=[
local function f()
  return 1, 2, 3
end
local function g()
  return f()
end
local a, b, c = g()
return a + b + c
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
  super_calls = [=[
function echo(x) return x end
function vecho(...) return ... end
local a = echo("ok")
local b = vecho("var")
local n = select("#")
local t = {}
local p = pairs(t)
local o = { x = 7 }
function o:get() return self.x end
function o:count(...) return 0 end
local c = o:get()
local d = o:count()
return a, b, n, c, d
]=],
  super_rmw = [=[
local t = { x = 0 }
for i = 1, 100 do t.x = t.x + 1 end
local k = "x"
for i = 1, 100 do t[k] = t[k] + 1 end
return t.x
]=],
  super_accum = [=[
local totals = { 0, 0, 0 }
local orders = {
  { customer = 1, amount = 10 }, { customer = 1, amount = 5 },
  { customer = 2, amount = 7 }, { customer = 3, amount = 2.5 },
}
for i = 1, #orders do
  local o = orders[i]
  totals[o.customer] = totals[o.customer] + o.amount
end
local k = "a"
local m = { k = 1, v = 3 }
local acc = { 0 }
acc[m.k] = acc[m.k] + m.v
return totals[1], totals[2], totals[3], acc[1], #orders
]=],
}
local failures = 0
for name, src in pairs(programs) do
  local s = stock_capture(src)
  local ok_native, why = pcall(native, src)
  assert(ok_native, ("%s: %s"):format(name, why))
  local n = why
  local ok = s == n
  if not ok then failures = failures + 1 end
  print(("  %-16s stock=%-24s native=%-24s %s"):format(name, s:gsub("\n",""), n:gsub("\n",""), ok and "OK" or "MISMATCH"))
end
print(failures == 0 and "lua55 v2 differential: ok, all cases match stock" or (failures .. " MISMATCHES"))
