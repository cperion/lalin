package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local lalin = require("lalin")
local c_gcc = require("lalin.emit_c_compile")

local available, why = c_gcc.available()
if not available then
  assert(why.skip == true)
  io.write("Lalin emit environment GCC skipped\n")
  os.exit(0)
end

local ffi = require("ffi")
ffi.cdef[[
typedef struct { int32_t value; } EmitEnvironmentFrame;
 ]]

local source = [=[
struct EmitEnvironmentFrame
  value [i32]
end

-- Data params frame/delta and caller captures must cross the internal work
-- block as one explicit emitted CFG environment. The resolved direct field
-- store must be rebound by the post-expansion authoritative typecheck.
region EmitEnvironment.add(frame [ptr [EmitEnvironmentFrame]], delta [i32]; done(value [i32]))
  entry start()
    jump work(n = delta)
  end
  block work(n [i32])
    frame.value = frame.value + n
    jump done(value = frame.value)
  end
end

fn emit_environment_run(frame [ptr [EmitEnvironmentFrame]], delta [i32], bias [i32]) [i32]
  entry start()
    emit EmitEnvironment.add(frame, delta; done = finished(value, bias))
  end
  block finished(value [i32], bias [i32])
    return value + bias
  end
end

-- Two independent splices prove local/binding identities are invocation-owned.
fn emit_environment_twice(frame [ptr [EmitEnvironmentFrame]], a [i32], b [i32]) [i32]
  entry start()
    emit EmitEnvironment.add(frame, a; done = second(first = value))
  end
  block second(first [i32])
    emit EmitEnvironment.add(frame, b; done = finished(value, first))
  end
  block finished(value [i32], first [i32])
    return value + first
  end
end
]=]

local decls = assert(lalin.loadstring(source, "@emit-environment-gcc.lln"))
local session, emitted = lalin.compile_c_gcc("lalin_emit_environment_gcc", decls, {
  gcc_opts = { opt = 3, out_dir = "target/test_lalin_emit_environment_gcc" },
})

local run = assert(session:symbol("emit_environment_run",
  "int32_t (*)(EmitEnvironmentFrame*, int32_t, int32_t)"))
local twice = assert(session:symbol("emit_environment_twice",
  "int32_t (*)(EmitEnvironmentFrame*, int32_t, int32_t)"))

local frame = ffi.new("EmitEnvironmentFrame", { value = 10 })
assert(run(frame, 5, 7) == 22 and frame.value == 15)
frame.value = 10
assert(twice(frame, 3, 4) == 30 and frame.value == 17)

assert(emitted:match("= EmitEnvironment_add%(") == nil,
  "emit must splice the region rather than invoke its sealed callable")
assert(emitted:match("__lalin_region_result_EmitEnvironment_add"),
  "region item still owns an independently available sealed-call artifact")

session:free()
io.write("Lalin emit environment GCC ok: data+capture forwarding, direct store, two splices\n")
