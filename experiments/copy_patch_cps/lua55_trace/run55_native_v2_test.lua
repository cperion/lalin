package.path = "./lua/?.lua;./lua/?/init.lua;./?.lua;./?/init.lua;" .. package.path
package.path = "./lua/?.lua;./lua/?/init.lua;./?.lua;./?/init.lua;" .. package.path

local ffi = require("ffi")
local CPS = require("experiments.copy_patch_cps.lua55_trace.cps_invocation_v2")

local function run(source, opts)
    local path = os.tmpname() .. ".lua"
    local file = assert(io.open(path, "wb"))
    file:write(source)
    file:close()
    local ok, result, inv = pcall(CPS.run, path, opts)
    os.remove(path)
    assert(ok, result)
    return result, inv
end

-- 1. naive recursion: CALL bumps a callee frame, RETURN jumps to the caller's
-- continuation block (a patched absolute entry, not a C return address).
local fib = run([=[
local function fib(n)
  if n < 2 then return n end
  return fib(n - 1) + fib(n - 2)
end
return fib(20)
]=])
assert(#fib == 1 and fib[1] == 6765, "cps v2 fib result changed")

-- 2. recursive closure capturing three upvalues through shared cells.
local captured = run([=[
local a, b = 7, 11
local function f(n)
  if n == 0 then return a + b end
  return f(n - 1)
end
return f(5)
]=])
assert(#captured == 1 and captured[1] == 18, "cps v2 closure capture changed")

-- 3. while + numeric-for loops (native back-edges).
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
    "cps v2 loop results changed")

-- 4. proper-tail recursion: one million iterations must reuse ONE frame.
-- The frame region is sized to hold only the root frame (4 KiB): if a
-- tail call bumped a new frame, the millionth iteration would overflow.
-- After the run the RETURN pop leaves frame_next back at frame_begin.
local tail, tail_inv = run([=[
local function loop(n, acc)
  if n == 0 then return acc end
  return loop(n - 1, acc + n)
end
return loop(1000000, 0)
]=], { return_invocation = true, frame_region = 4096 })
assert(#tail == 1 and tail[1] == 500000500000, "cps v2 tail loop result changed")
assert(tonumber(ffi.cast("uintptr_t", tail_inv.invocation[0].frame_next))
    == tonumber(ffi.cast("uintptr_t", tail_inv.invocation[0].frame_begin)),
    "cps v2 tail recursion did not reuse a bounded frame")
tail_inv:free()

-- 5. sibling closures sharing one captured local, mutating after the defining
-- frame returned (close-on-pop keeps the shared cell identity).
local siblings = run([=[
local function make()
  local x = 5
  local function inc() x = x + 1 return x end
  local function get() return x end
  return inc, get
end
local inc, get = make()
inc(); inc()
return get()
]=])
assert(#siblings == 1 and siblings[1] == 7, "cps v2 sibling closure sharing changed")

-- 6. mutation through an OPEN cell while the defining frame is live.
local open_cells = run([=[
local function counter()
  local n = 0
  local function bump() n = n + 1 return n end
  local r1 = bump()
  local r2 = bump()
  return r1, r2
end
return counter()
]=])
assert(#open_cells == 2 and open_cells[1] == 1 and open_cells[2] == 2,
    "cps v2 open-cell mutation changed")

-- 7. bounded frame region: non-tail recursion overflows with a typed outcome.
local ok, why = pcall(run, [=[
local function f() return 1 + f() end
return f()
]=], { frame_region = 65536 })
assert(not ok and tostring(why):find("stack overflow", 1, true),
    "cps v2 bounded frame overflow did not reject: " .. tostring(why))

-- 8. tail-recursive fib through the self upvalue (GETUPVAL + TAILCALL).
local tail_fib = run([=[
local function fib(n, a, b)
  if n == 0 then return a end
  return fib(n - 1, b, a + b)
end
return fib(20, 0, 1)
]=])
assert(#tail_fib == 1 and tail_fib[1] == 6765, "cps v2 tail fib result changed")


-- 9. Every native-visible guest object survives forced LuaJIT collection
-- because its physical storage belongs to the mmap guest heap, not cdata.
local rooted, rooted_inv = run([=[
local text = "mmap-owned-v2"
return text
]=], { return_invocation = true, force_gc_before_entry = true })
assert(#rooted == 1 and rooted[1] == "mmap-owned-v2",
    "cps v2 forced-GC string changed")
rooted_inv.heap:assert_native_ownership()
assert(rooted_inv.heap:owns_native_span(rooted_inv.invocation[0].heap,
    ffi.sizeof("Lua55GuestHeapV1")),
    "cps v2 frame heap pointer is outside the mmap owner")
rooted_inv:free()

print("lua55 native CPS frame V2 runner tests: ok")
