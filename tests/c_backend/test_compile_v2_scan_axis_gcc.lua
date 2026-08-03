package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local lalin = require("lalin")

local session = lalin.compile_v2("v2_scan_axis_public", [=[
fn scan_rows(dst [ptr [i32]], xs [ptr [i32]], h [index], w [index]) [void] do
  loop i, j in grid(0 .. h, 0 .. w) do
    scan acc [i32] = 0 by add over j step xs[i * w + j] into dst[i * w + j]
  end
end

fn scan_columns(dst [ptr [i32]], xs [ptr [i32]], h [index], w [index]) [void] do
  loop i, j in grid(0 .. h, 0 .. w) do
    scan acc [i32] = 0 by add over i step xs[i * w + j] into dst[i * w + j]
  end
end

fn scan_tiled_rows(dst [ptr [i32]], xs [ptr [i32]], h [index], w [index]) [void] do
  loop i, j in tiled grid(0 .. h, 0 .. w) by 2, 2 do
    scan acc [i32] = 1 by mul over 2 step xs[i * w + j] into dst[i * w + j]
  end
end
]=], {
  gcc = true,
  opt = 3,
  out_dir = "target/test_compile_v2_scan_axis_gcc",
})

local src = ffi.new("int32_t[6]", { 1, 2, 3, 4, 5, 6 })
local rows = ffi.new("int32_t[6]")
local columns = ffi.new("int32_t[6]")
local tiled = ffi.new("int32_t[6]")
local function symbol(name)
  return assert(session:symbol(name,
    "void (*)(int32_t *, int32_t *, size_t, size_t)"))
end
symbol("scan_rows")(rows, src, 2, 3)
symbol("scan_columns")(columns, src, 2, 3)
symbol("scan_tiled_rows")(tiled, src, 2, 3)
local expected_rows = { 1, 3, 6, 4, 9, 15 }
local expected_columns = { 1, 2, 3, 5, 7, 9 }
local expected_tiled = { 1, 2, 6, 4, 20, 120 }
for i = 0, 5 do
  assert(rows[i] == expected_rows[i + 1], "row scan lane " .. i)
  assert(columns[i] == expected_columns[i + 1], "column scan lane " .. i)
  assert(tiled[i] == expected_tiled[i + 1], "tiled row scan lane " .. i)
end

session:free()
print("public schema-v2 multi-axis scan-axis GCC paths ok")
