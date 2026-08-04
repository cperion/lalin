package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local lalin = require("lalin")
local c_gcc = require("lalin.emit_c_compile")
local Document = require("lalin.syntax_v2.document")

local available, why = c_gcc.available()
if not available then
    assert(why.skip == true)
    io.write("lalin extern/builder/HostEval GCC skipped\n")
    os.exit(0)
end

local generated_doc = Document.parse([=[
fn host_generated(x [i32]) [i32] do
  return x + 9
end
]=], "@host-generated-declaration.lln")

local parsed = assert(lalin.loadstring([=[
extern c_absolute(x [i32]) [i32] do
  symbol = "abs"
end

[generated_declarations]

fn run_abs(x [i32]) [i32] do
  return c_absolute(x)
end
]=], "@extern-hosteval-runtime.lln", {
    env = { generated_declarations = generated_doc.body },
}))

local parsed_session = lalin.compile_c_gcc("extern_hosteval_gcc", parsed, {
    gcc_opts = { opt = 3, out_dir = "target/test_lalin_extern_builder_hosteval_gcc", stem = "extern_hosteval_gcc" },
})
local run_abs = assert(parsed_session:symbol("run_abs", "int32_t (*)(int32_t)"))
local host_generated = assert(parsed_session:symbol("host_generated", "int32_t (*)(int32_t)"))
assert(run_abs(-37) == 37, "explicit extern symbol spelling must link to libc abs")
assert(host_generated(33) == 42, "HostEval-generated declaration must compile and run")
parsed_session:free()

local lln = lalin.lln
local x = lln.N.x
local builder_add = lln.fn. builder_add { x [lln.i32] } [lln.i32] {
    lln.ret(x + 5),
}
local builder_session = lalin.compile_c_gcc("builder_gcc", { builder_add }, {
    gcc_opts = { opt = 3, out_dir = "target/test_lalin_extern_builder_hosteval_gcc", stem = "builder_gcc" },
})
local add = assert(builder_session:symbol("builder_add", "int32_t (*)(int32_t)"))
assert(add(37) == 42, "builder declaration must compile through the canonical typed pipeline")
builder_session:free()

io.write("lalin extern/builder/HostEval GCC ok: abs(-37)=37 generated(33)=42 builder(37)=42\n")
