package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local lalin = require("lalin")
local c_gcc = require("lalin.emit_c_compile")

local available, why = c_gcc.available()
if not available then
  assert(why.skip == true)
  io.write("schema parsed function control GCC skipped\n")
  os.exit(0)
end

-- Mirrors tests/c_backend/test_lalin_parsed_region_protocols_gcc.lua but
-- through the schema compile_source pipeline with authored function
-- entry/block control forms.
local source = [=[
region Protocol.leaf(x [i32]; done(value [i32]))
  entry start()
    jump done(value = x)
  end
end

region Protocol.outer(x [i32]; done(value [i32]))
  entry start()
    emit Protocol.leaf(x; done = done)
  end
end

region Protocol.pair(x [i32], y [i32]; done(left [i32], right [i32]))
  entry start()
    jump done(left = x, right = y)
  end
end

fn nested_protocol(x [i32]) [i32]
  entry start()
    emit Protocol.outer(x; done = finished)
  end
  block finished(value [i32])
    return value + 1
  end
end

fn target_application(x [i32], y [i32]) [i32]
  entry start()
    emit Protocol.pair(x, y; done = finished(extra = 7, left, right))
  end
  block finished(extra [i32], left [i32], right [i32])
    return extra + left + right
  end
end
]=]

local session = lalin.compile_source("parsed_func_control_gcc", source, {
  gcc = true,
  out_dir = "target/test_parsed_func_control_gcc",
})
local nested = assert(session:symbol("nested_protocol", "int32_t (*)(int32_t)"))
local applied = assert(session:symbol("target_application", "int32_t (*)(int32_t, int32_t)"))
assert(nested(41) == 42, "nested parameterized region must preserve its continuation value")
assert(applied(10, 25) == 42, "named/positional target application must preserve captured and continuation values")
session:free()

io.write("schema parsed function control GCC ok: nested(41)=42 target_application(10,25)=42\n")
