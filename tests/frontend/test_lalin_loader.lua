package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local lalin = require("lalin")

local function shell_quote(s)
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local function write(path, text)
    local f = assert(io.open(path, "wb"))
    f:write(text)
    f:close()
end

local chunk, err = lalin.loadstring([[
local scale = 4
local add = fn add(a: i32, b: i32): i32
  return a + b
end

return {
  add = add,
  scale = scale,
}
]], "@inline.lln")
assert(chunk ~= nil, tostring(err))

local inline = chunk()
assert(inline.scale == 4, ".lln chunks should return ordinary Lua values")
assert(inline.add.tag == "DeclFunc", "bare fn should be active in .lln chunks")
assert(inline.add.name == "add", "parsed function name should be preserved")

local compiled = lalin.compile("loader_inline", { inline.add }, { residual = "bc" })
assert(compiled.add(20, 22) == 42, "parsed .lln declarations should feed lalin.compile")

local ok, import_err = pcall(function()
    return lalin.loadstring([[import "lalin.syntax"]], "@bad.lln")
end)
assert(not ok and tostring(import_err):match("import"), ".lln chunks should reject parse-time import")

os.execute("rm -rf " .. shell_quote("target/test_lalin_loader"))
os.execute("mkdir -p " .. shell_quote("target/test_lalin_loader/pkg"))

write("target/test_lalin_loader/pkg/math.lln", [[
local add = fn add(a: i32, b: i32): i32
  return a + b
end

return {
  add = add,
  label = "math",
}
]])

write("target/test_lalin_loader/cli.lln", [[
local add = fn add(a: i32, b: i32): i32
  return a + b
end

assert(add.tag == "DeclFunc")
]])

lalin.path = "target/test_lalin_loader/?.lln;target/test_lalin_loader/?/init.lln"
package.loaded["pkg.math"] = nil

local math1 = lalin.require("pkg.math")
assert(math1.label == "math", "lalin.require should return the .lln chunk value")
assert(math1.add.tag == "DeclFunc", "required .lln values should preserve parsed declarations")
assert(lalin.require("pkg.math") == math1, "lalin.require should use package.loaded")

package.loaded["pkg.math"] = nil
assert(lalin.install_searcher(), "expected .lln searcher installation")
local math2 = require("pkg.math")
assert(math2.label == "math", "Lua require should discover .lln files after installing the searcher")
assert(package.loaded["pkg.math"] == math2, "Lua require should own package.loaded caching")
assert(lalin.remove_searcher(), "expected .lln searcher removal")

local cli = require("lalin.cli")
assert(cli.main({ "target/test_lalin_loader/cli.lln" }) == 0, "CLI should load .lln files through lalin.loadstring")

io.write("lalin loader ok\n")
