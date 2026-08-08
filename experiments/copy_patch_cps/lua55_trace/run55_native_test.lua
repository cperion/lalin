package.path = "./lua/?.lua;./lua/?/init.lua;./?.lua;./?/init.lua;" .. package.path

local Native = require("experiments.copy_patch_cps.lua55_trace.run55_native")

local function run(source)
    local path = os.tmpname() .. ".lua"
    local file = assert(io.open(path, "wb"))
    file:write(source)
    file:close()
    local ok, result = pcall(Native.run, path)
    os.remove(path)
    assert(ok, result)
    return result
end

local fib = run([=[
local function fib(n)
  if n < 2 then return n end
  return fib(n - 1) + fib(n - 2)
end
return fib(20)
]=])
assert(#fib == 1 and fib[1] == 6765, "native fib result changed")

local captured = run([=[
local a, b = 7, 11
local function f(n)
  if n == 0 then return a + b end
  return f(n - 1)
end
return f(5)
]=])
assert(#captured == 1 and captured[1] == 18, "native closure capture changed")

local loops = run([=[
local function wh(n)
  local i, s = 0, 0
  while i < n do i = i + 1; s = s + i end
  return s
end
local function nf(n)
  local s = 0
  for i = 1, n do s = s + i end
  return s
end
return wh(100000), nf(100000)
]=])
assert(#loops == 2 and loops[1] == 5000050000 and loops[2] == 5000050000,
    "native loop results changed")

print("lua55 native self-selecting runner tests: ok")
