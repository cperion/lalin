package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local lalin = require("lalin")
local asdl = require("lalin.asdl")

local function shell_quote(s)
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local function write(path, text)
    local f = assert(io.open(path, "wb"))
    f:write(text)
    f:close()
end

local parsed, doc = assert(lalin.loadstring([[
struct Pair
  x [i32]
end

fn add(a [i32], b [i32]) [i32] do
  return a + b
end

fn scaled(x [i32]) [i32] do
  return x * [scale]
end
]], "@inline.lln", { env = { scale = 4 } }))
assert(type(parsed) == "table" and type(parsed) ~= "function", ".lln loadstring returns a decl array, not a chunk")
assert(doc and doc.tag == "DeclDocument" and doc.decls == parsed, "loadstring should return document metadata")
assert(#parsed == 3 and parsed[1].name == "Pair" and parsed[2].name == "add" and parsed[3].name == "scaled",
  "root declarations should parse in document order")
assert(parsed[3].body[1].values[1].right.value == 4, "opts.env should feed document HostEval constants")

local inline_module = lalin.syntax.to_module(parsed, "loader_inline")
assert(tostring(asdl.classof(inline_module)):match("LalinTree%.Module"), "parsed document decls should lower to a module")
assert(#inline_module.items == 3, "all inline document decls should lower")

local named_decls = assert(lalin.loadstring([=[
struct Pair
  x [i32]
end

fn accept(p [Pair]) [void] do
  return
end
]=], "@named.lln"))
assert(named_decls[2].params[1].type.value == named_decls[1], "document names should bind for later type HostEvals")
local named_module = lalin.syntax.to_module(named_decls, "loader_named_type")
assert(tostring(asdl.classof(named_module)):match("LalinTree%.Module"), "named document declarations should lower")

local parsed_handle = assert(lalin.loadstring([=[
struct AudioBufferStore
  capacity [index]
end

struct AudioBufferRecord
  first [index]
end

handle AudioBuffer [u32] do
  invalid = 0
  domain [AudioBufferStore]
  target [AudioBufferRecord]
end
]=], "@handle.lln"))
assert(parsed_handle[3].tag == "DeclHandle", "parsed handle entrypoint should produce a handle declaration")
local handle_unit = lalin.syntax.to_module(parsed_handle, "loader_handle")
local handle_item = handle_unit.items[3]
assert(tostring(asdl.classof(handle_item.t)):match("TypeDeclHandle"), "parsed handles should lower to TypeDeclHandle")
assert(tostring(asdl.classof(handle_item.t.repr.scalar)):match("ScalarU32"), "parsed handle repr should use bracket type syntax")
assert(#handle_item.t.facts == 2, "parsed handle domain/target facts should lower")

local function rejects(src, needle)
    local result, err = lalin.loadstring(src, "@bad.lln")
    assert(result == nil, "invalid .lln document should not load")
    assert(tostring(err):match(needle), "expected " .. tostring(needle) .. " in " .. tostring(err))
end

rejects([[module Demo
end]], "module")
rejects([[import "lalin.syntax"]], "import")
rejects([[local x = 1]], "local")
rejects([[return {}]], "return")

os.execute("rm -rf " .. shell_quote("target/test_lalin_loader"))
os.execute("mkdir -p " .. shell_quote("target/test_lalin_loader/pkg"))

write("target/test_lalin_loader/pkg/math.lln", [[
fn add(a [i32], b [i32]) [i32] do
  return a + b
end
]])

write("target/test_lalin_loader/cli.lln", [[
fn add(a [i32], b [i32]) [i32] do
  return a + b
end
]])

lalin.path = "target/test_lalin_loader/?.lln;target/test_lalin_loader/?/init.lln"
package.loaded["pkg.math"] = nil

local math1 = lalin.require("pkg.math")
assert(type(math1) == "table" and math1[1].tag == "DeclFunc" and math1[1].name == "add",
  "lalin.require should return the parsed .lln decl array")
assert(lalin.require("pkg.math") == math1, "lalin.require should use package.loaded")

package.loaded["pkg.math"] = nil
assert(lalin.install_searcher(), "expected .lln searcher installation")
local math2 = require("pkg.math")
assert(type(math2) == "table" and math2[1].name == "add", "Lua require should discover .lln documents")
assert(package.loaded["pkg.math"] == math2, "Lua require should own package.loaded caching")
assert(lalin.remove_searcher(), "expected .lln searcher removal")

local dofile_decls = lalin.dofile("target/test_lalin_loader/cli.lln")
assert(type(dofile_decls) == "table" and dofile_decls[1].name == "add", "lalin.dofile should return decl arrays")

local cli = require("lalin.cli")
assert(cli.main({ "target/test_lalin_loader/cli.lln" }) == 0, "CLI should parse .lln documents through lalin.loadstring")

io.write("lalin loader ok\n")
