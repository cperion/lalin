package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

-- String-equality hot-loop benchmark through the compiled Lua VM.
--
-- Evidence goal: LuaString.eq's sealed all-compare materialization must be
-- compiled from declared noalias contracts (noalias(lhs.bytes),
-- noalias(rhs.bytes) in demo/lua_vm.lln) into restrict-qualified byte-pointer
-- bases and cursors, and the VM must then chew through a deterministic hot
-- loop of string comparisons with a provable result.
--
-- bench_main runs 2,000,000 iterations; each iteration calls the sealed
-- LuaString.eq on two identical 48-byte strings (a fresh restrict-qualified
-- compare each time) and increments a counter.  bench_main returns
-- (matches - LIMIT), so a native status of 0 proves every comparison matched.

local lalin = require("lalin")

local LuaOP = { LOADK = 1, MOVE = 2, ADD = 3, LT = 4, JMP = 5, JMPZ = 6, LOADS = 7, EQ = 8, NEWTABLE = 9, SETI = 10, GETI = 12, SETS = 13, GETS = 14, RETURN = 11 }
local LuaTag = { SHIFT = 4, MASK = 15, INT = 1, NIL = 2, STRING = 3, FALSE = 4, TABLE = 5, TRUE = 20 }
local LuaErr = { EXPECT_TABLE = 101, EXPECT_INT_INDEX = 102, EXPECT_STRING_KEY = 103, INDEX_OOB = 104, HASH_FULL = 105 }

local LIMIT = 2000000
local STRING_LEN = 48

local src = assert(io.open("demo/lua_vm.lln", "r")):read("*a")
local decls = assert(lalin.loadstring(src, "@demo/lua_vm.lln", { env = { LuaOP = LuaOP, LuaTag = LuaTag, LuaErr = LuaErr } }))
local session, source = lalin.compile_c_gcc("lua_vm_string_bench", decls, {
  gcc_opts = { opt = 3, out_dir = "target/test_lalin_vm_string_bench_gcc" },
})

-- Restrict evidence: the LuaString.eq all-compare lane bases and cursors must
-- carry the restrict qualifier, derived solely from the declared noalias
-- contracts (never inferred).
local restrict_bases = 0
for line in source:gmatch("[^\n]*restrict[^\n]*") do
  if line:find("lane_access_LuaString_eq", 1, true) or line:find("cursor_", 1, true) then
    restrict_bases = restrict_bases + 1
  end
end
assert(restrict_bases >= 4,
  "LuaString.eq byte-pointer bases/cursors must be restrict-qualified (found " .. restrict_bases .. ")")

-- Correctness + hot-loop timing through the compiled artifact.
local bench_main = assert(session:symbol("bench_main", "int32_t (*)(void)"))
local t0 = os.clock()
local status = tonumber(bench_main())
local elapsed = os.clock() - t0
assert(status == 0,
  "bench_main must report all " .. LIMIT .. " comparisons matched (status=" .. tostring(status) .. ")")

local bytes_compared = LIMIT * STRING_LEN * 2
print(string.format(
  "lalin VM string-eq bench: %d comparisons x %d bytes in %.3fs (%.1f MB/s, %.1f ns/compare)",
  LIMIT, STRING_LEN, elapsed, (bytes_compared / 1048576) / math.max(elapsed, 1e-9),
  (elapsed * 1e9) / LIMIT))

session:free()
