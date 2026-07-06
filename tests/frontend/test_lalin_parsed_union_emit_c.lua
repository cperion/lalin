package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local lalin = require("lalin")

local src = [=[
union PairResult
  Done(a [i32], b [i32])
  Missing
end

fn main(argc [i32], argv [ptr [ptr [u8]]]) [i32]
  return 0
end
]=]

local decls = assert(lalin.loadstring(src, "@parsed-union-emit-c.lln"))
local artifact = lalin.emit_c(decls, {
  name = "parsed_union_emit_c",
  c_path = "target/test_parsed_union_emit_c/main.c",
  h_path = "target/test_parsed_union_emit_c/main.h",
})
assert(artifact.kind == "CBackendArtifact", "parsed union should lower through emit_c")
assert(artifact.source:match("PairResult"), "emitted C should mention parsed union type")

io.write("lalin parsed union emit_c ok\n")
