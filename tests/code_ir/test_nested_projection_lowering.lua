package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local lalin = require("lalin")

local src = [=[
struct S
  hash [u64]
  len [index]
end

struct P
  strings [ptr [S]]
end

region ReadHash(proto [ptr [P]], idx [index]; done(v [u64]))
  entry start()
    let h [u64] = proto.strings[idx].hash
    jump done(v = h)
  end
end

fn main() [i32]
  entry start()
    var ss [array [S] [1]] = { S { hash = as [u64](7), len = as [index](1) } }
    var p [P] = P { strings = &ss[0] }
    emit ReadHash(&p, as [index](0); done = done)
  end
  block done(v [u64])
    return as [i32](v)
  end
end
]=]

local decls = assert(lalin.loadstring(src, "@nested_projection_lowering.lln"))
local artifact = lalin.emit_c(decls, {
  name = "nested_projection_lowering",
  c_path = "target/nested_projection_lowering.c",
  h_path = "target/nested_projection_lowering.h",
})
assert(artifact.source:match("hash"), "expected emitted nested field load source")

print("nested projection lowering ok")
