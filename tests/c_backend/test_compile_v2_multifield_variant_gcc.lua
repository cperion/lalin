package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local lalin = require("lalin")

local source = [[
union PairResult
  Empty
  Pair(left [i32], right [i32])
end

fn sum_pair(left [i32], right [i32]) [i32] do
  let value [PairResult] = PairResult.Pair(left, right)
  switch value do
    case variant Pair(a, b) then
      return a + b
    case variant Empty then
      return 0
    default then
      return -1
  end
end
]]

local decls = assert(lalin.loadstring(source, "@multifield_variant.lln"))
local session = lalin.compile_c_gcc("multifield_variant", decls, {
  gcc_opts = { opt = 3, out_dir = "target/test_compile_v2_multifield_variant_gcc" },
})
local sum_pair = assert(session:symbol("sum_pair", "int32_t (*)(int32_t, int32_t)"))
assert(sum_pair(19, 23) == 42)
session:free()
print("schema-v2 multi-field variant GCC ok")
