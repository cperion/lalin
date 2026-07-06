package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local lalin = require("lalin")

local src = [=[
struct Holder
  data [ptr [i32]]
end

region SumLoop(h [ptr [Holder]]; done(v [i32]))
  entry start()
    jump loop(h = h, i = as [index](0), acc = 0)
  end

  block loop(h [ptr [Holder]], i [index], acc [i32])
    if i == as [index](3) then
      jump done(v = acc)
    end
    let x [i32] = h.data[0] + h.data[0] + h.data[0]
    jump loop(h = h, i = i + as [index](1), acc = acc + x)
  end
end

fn sum_loop(h [ptr [Holder]]) [i32]
  entry start()
    emit SumLoop(h; done = done)
  end

  block done(v [i32])
    return v
  end
end

fn main() [i32]
  var xs [array [i32] [1]] = { 7 }
  var h [Holder] = Holder { data = &xs[0] }
  return sum_loop(&h)
end
]=]

local decls = assert(lalin.loadstring(src, "@field_load_hoist_block_param.lln"))
local artifact = lalin.emit_c(decls, {
  name = "field_load_hoist_block_param",
  c_path = "target/field_load_hoist_block_param.c",
  h_path = "target/field_load_hoist_block_param.h",
})
assert(artifact.source:match("__hoist_field_"), "expected repeated field load through block param to be hoisted")
local ok = os.execute("gcc -std=c99 -O2 target/field_load_hoist_block_param.c -o target/field_load_hoist_block_param")
assert(ok == true or ok == 0, "gcc failed for field_load_hoist_block_param")
ok = os.execute("target/field_load_hoist_block_param; code=$?; test $code -eq 63")
assert(ok == true or ok == 0, "expected SumLoop result exit code 63")

print("c backend field load hoist block param ok")
