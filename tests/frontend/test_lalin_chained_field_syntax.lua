package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local lalin = require("lalin")

local src = [=[
struct Inner
  x [i32]
end

struct Outer
  inner [Inner]
end

fn read_chain(o [Outer]) [i32]
  return o.inner.x
end

fn write_chain(o [ptr [Outer]]) [void]
  o.inner.x = 7
  return
end
]=]

local decls = assert(lalin.loadstring(src, "@chained-field.lln"))
assert(#decls == 4, "expected chained field source to parse")

io.write("lalin chained field syntax ok\n")
