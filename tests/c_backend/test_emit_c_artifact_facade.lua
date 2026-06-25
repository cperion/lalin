package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local lalin = require("lalin")

local add = lalin.loadstring([[
return fn. add { a [i32], b [i32] } [i32] {
  ret (a + b),
}
]], "test_emit_c_artifact_facade.lua")

local artifact = lalin.emit_c_artifact({ add }, {
    name = "emit_c_facade",
    c_path = "target/test_emit_c_artifact_facade/nested/add.c",
    h_path = "target/test_emit_c_artifact_facade/nested/add.h",
    combined_path = "target/test_emit_c_artifact_facade/nested/add_combined.c",
})

assert(type(artifact.source) == "string" and artifact.source:match("add"), "expected C source")
assert(assert(io.open("target/test_emit_c_artifact_facade/nested/add.c", "rb")):close() == true)
assert(assert(io.open("target/test_emit_c_artifact_facade/nested/add.h", "rb")):close() == true)
assert(assert(io.open("target/test_emit_c_artifact_facade/nested/add_combined.c", "rb")):close() == true)

io.write("lalin emit_c_artifact facade ok\n")
