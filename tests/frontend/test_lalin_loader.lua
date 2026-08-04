package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local lalin = require("lalin")
local asdl = require("lalin.asdl")
require("lalin.schema_v2")
local P = package.loaded["lalin.schema_v2.parse"]
local Tr = package.loaded["lalin.schema_v2.tree"]
local Ty = package.loaded["lalin.schema_v2.type"]
local C = package.loaded["lalin.schema_v2.core"]
local Document = require("lalin.syntax_v2.document")

local function shell_quote(s)
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local function write(path, text)
    local f = assert(io.open(path, "wb"))
    f:write(text)
    f:close()
end

-- loadstring returns the typed ParsedDocument plus its ordered ParsedDecl body.
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
assert(asdl.classof(doc) == P.ParsedDocument, "loadstring should return ParsedDocument ASDL metadata")
assert(doc.body == parsed, "ParsedDocument.body should be the returned decl array")
assert(#parsed == 3, "root declarations should parse in document order")
assert(asdl.classof(parsed[1]) == P.ParsedStruct and parsed[1].name == "Pair",
  "struct root should parse as a typed ParsedStruct")
assert(asdl.classof(parsed[2]) == P.ParsedFunc and parsed[2].name == "add",
  "fn root should parse as a typed ParsedFunc")
assert(asdl.classof(parsed[3]) == P.ParsedFunc and parsed[3].name == "scaled",
  "root declarations should parse in document order")

-- opts.env feeds bracket host evals: `x * [scale]` lowers to a typed binary
-- multiply with the host constant as an integer literal.
local ret = parsed[3].body.body[1].stmt
assert(asdl.classof(ret) == Tr.StmtReturnValue, "scaled body should lower to a typed return statement")
local expr = ret.value
assert(asdl.classof(expr) == Tr.ExprBinary and asdl.isa(expr.op, C.BinMul),
  "x * [scale] should lower to a typed binary multiply")
assert(asdl.classof(expr.lhs) == Tr.ExprRef, "left operand should be a typed ref")
assert(asdl.classof(expr.rhs) == Tr.ExprLit and asdl.classof(expr.rhs.value) == C.LitInt
  and expr.rhs.value.raw == "4", "opts.env should feed document HostEval constants")

-- The typed document lowers to a Tree.Module through syntax_v2.
local inline_module = Document.to_module(doc, "loader_inline")
assert(asdl.classof(inline_module) == Tr.Module, "ParsedDocument decls should lower to a module")
assert(#inline_module.items == 3, "all inline document decls should lower")

-- Document names bind into the bracket host env: `[Pair]` adapts to a typed
-- named type for later declarations.
local named_decls = assert(lalin.loadstring([=[
struct Pair
  x [i32]
end

fn accept(p [Pair]) [void] do
  return
end
]=], "@named.lln"))
local accept_ty = named_decls[2].params[1].ty
assert(asdl.classof(accept_ty) == Ty.TNamed, "document names should bind for later type HostEvals")
local named_module = Document.to_module(named_decls, "loader_named_type")
assert(asdl.classof(named_module) == Tr.Module, "named document declarations should lower")

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
assert(asdl.classof(parsed_handle[3]) == P.ParsedHandle and parsed_handle[3].name == "AudioBuffer",
  "parsed handle entrypoint should produce a typed handle declaration")
local handle_unit = Document.to_module(parsed_handle, "loader_handle")
local handle_item = handle_unit.items[3]
assert(asdl.classof(handle_item.t) == Tr.TypeDeclHandle, "parsed handles should lower to TypeDeclHandle")
assert(asdl.isa(handle_item.t.repr.scalar, C.ScalarU32), "parsed handle repr should use bracket type syntax")
assert(#handle_item.t.facts == 2, "parsed handle domain/target facts should lower")

-- Supported document-root rejections: .lln documents are rooted at Lalin.decls.
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
assert(type(math1) == "table" and asdl.classof(math1[1]) == P.ParsedFunc and math1[1].name == "add",
  "lalin.require should return the typed .lln decl array")
assert(lalin.require("pkg.math") == math1, "lalin.require should use package.loaded")

package.loaded["pkg.math"] = nil
assert(lalin.install_searcher(), "expected .lln searcher installation")
local math2 = require("pkg.math")
assert(type(math2) == "table" and asdl.classof(math2[1]) == P.ParsedFunc and math2[1].name == "add",
  "Lua require should discover .lln documents")
assert(package.loaded["pkg.math"] == math2, "Lua require should own package.loaded caching")
assert(lalin.remove_searcher(), "expected .lln searcher removal")

local dofile_decls = lalin.dofile("target/test_lalin_loader/cli.lln")
assert(type(dofile_decls) == "table" and asdl.classof(dofile_decls[1]) == P.ParsedFunc
  and dofile_decls[1].name == "add", "lalin.dofile should return typed decl arrays")

local cli = require("lalin.cli")
assert(cli.main({ "target/test_lalin_loader/cli.lln" }) == 0, "CLI should parse .lln documents through lalin.loadstring")

io.write("lalin loader ok\n")
