package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local lalin = require("lalin")

local src = [=[
struct Holder
  data [ptr [i32]]
end

fn sum3(h [ptr [Holder]], i [index]) [i32]
  return h.data[i] + h.data[i] + h.data[i]
end

fn main() [i32]
  var xs [array [i32] [1]] = { 7 }
  var h [Holder] = Holder { data = &xs[0] }
  return sum3(&h, as [index](0))
end
]=]

local decls = assert(lalin.loadstring(src, "@field_load_hoist.lln"))
local artifact = lalin.emit_c(decls, {
  name = "field_load_hoist",
  c_path = "target/field_load_hoist.c",
  h_path = "target/field_load_hoist.h",
})
assert(artifact.source:match("__hoist_field_"), "expected repeated pointer-field load to be hoisted")
local _, data_loads = artifact.source:gsub("%(%*%(_Holder%*%)v_sum3_arg_sum3_h%)%.data", "")
assert(data_loads == 1, "expected one direct h.data load for hoist init, got " .. tostring(data_loads))
local ok = os.execute("gcc -std=c99 -O2 target/field_load_hoist.c -o target/field_load_hoist")
assert(ok == true or ok == 0, "gcc failed for field_load_hoist")
ok = os.execute("target/field_load_hoist; code=$?; test $code -eq 21")
assert(ok == true or ok == 0, "expected sum3 result exit code 21")

print("c backend field load hoist ok")
