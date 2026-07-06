package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local lalin = require("lalin")

local src = [=[
region SwapOnce(a [i32], b [i32], n [i32]; done(a [i32], b [i32]))
  entry start()
    jump loop(a = a, b = b, n = n)
  end

  block loop(a [i32], b [i32], n [i32])
    if n == 0 then
      jump loop(a = b, b = a, n = 1)
    end
    jump done(a = a, b = b)
  end
end

fn main() [i32]
  entry start()
    emit SwapOnce(1, 2, 0; done = done)
  end

  block done(a [i32], b [i32])
    return a - b
  end
end
]=]

local decls = assert(lalin.loadstring(src, "@parallel_copy_transfer.lln"))
local artifact = lalin.emit_c(decls, {
  name = "parallel_copy_transfer",
  c_path = "target/parallel_copy_transfer.c",
  h_path = "target/parallel_copy_transfer.h",
})
assert(artifact.source:match("__xfer_"), "cyclic block-param transfer should use a scratch temporary")
local ok = os.execute("gcc -std=c99 -O2 target/parallel_copy_transfer.c -o target/parallel_copy_transfer")
assert(ok == true or ok == 0, "gcc failed for parallel_copy_transfer")
ok = os.execute("target/parallel_copy_transfer")
local code = (type(ok) == "number") and ok or (ok == true and 0 or 1)
assert(code == 1, "expected swapped result 2 - 1 = exit code 1")

print("c backend parallel copy transfer ok")
