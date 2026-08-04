package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

-- Parsed union document through the schema-v2 frontend and C emission.
--
-- The frontend portion of the old emit_c coverage: a .lln union declaration
-- document parses through the public loader, lowers through the schema-v2
-- pipeline (compile_v2, C text only), and the emitted C names the parsed union
-- type.  No old emit_c path.

local lalin = require("lalin")

local src = [=[
union PairResult
  Done(a [i32], b [i32])
  Missing
end

fn main(argc [i32], argv [ptr [ptr [u8]]]) [i32]
  let r [PairResult] = PairResult.Missing()
  return 0
end
]=]

local result = lalin.compile_v2("parsed_union", src, { gcc = false })
assert(type(result) == "table" and type(result.source) == "string",
  "compile_v2 should return emitted C text")
assert(result.source:match("PairResult"),
  "emitted C should mention the parsed union type")
assert(result.source:match("main"),
  "emitted C should include the parsed function")

io.write("lalin parsed union emit_c ok\n")
