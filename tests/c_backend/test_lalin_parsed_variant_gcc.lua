package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local lalin = require("lalin")

local source = [=[
union MaybeI32
  None
  Some(value [i32])
end

fn match_none() [i32] do
  let value [MaybeI32] = MaybeI32::None()
  switch value do
    case variant Some(payload) then
      return payload
    case variant None then
      return 10
    default then
      return -1
  end
end

fn match_payload() [i32] do
  let value [MaybeI32] = MaybeI32::Some(42)
  switch value do
    case variant None then
      return 0
    case variant Some(payload) then
      return payload
    default then
      return -1
  end
end

fn match_default() [i32] do
  let value [MaybeI32] = MaybeI32::None()
  switch value do
    case variant Some(payload) then
      return payload
    default then
      return 77
  end
end
]=]

local decls = assert(lalin.loadstring(source, "@parsed-variant-gcc.lln"))
local session = lalin.compile_c_gcc("parsed_variant_gcc", decls, {
  gcc_opts = { opt = 3, out_dir = "target/test_lalin_parsed_variant_gcc" },
})
assert(session:symbol("match_none", "int32_t (*)(void)")() == 10, "nullary variant arm must execute")
assert(session:symbol("match_payload", "int32_t (*)(void)")() == 42, "payload bind must execute")
assert(session:symbol("match_default", "int32_t (*)(void)")() == 77, "variant default must execute")
session:free()

io.write("lalin parsed variant gcc ok\n")
