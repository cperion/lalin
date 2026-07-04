package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local llbl = require("llbl")
local lalin = require("lalin")
local Ast = require("lalin.syntax.ast")

local source = [[
struct Pair
  x [i32]
end

union MaybePair
  None
  Some(value [Pair])
end

handle Store [u32] invalid 0 do
end

region Flow(input [i32]; done(result [i32]))
entry start do
  jump done(result = input)
end
end

fn accept(p [Pair]) [void] do
  return
end
]]

local decls, doc = assert(lalin.loadstring(source, "@document-root.lln"))
assert(type(decls) == "table" and type(decls) ~= "function", "lalin.loadstring must return decl array, not a callable chunk")
assert(doc and doc.tag == "DeclDocument" and doc.role_display == "Lalin.decls", "loadstring should return DeclDocument metadata")
assert(#decls == 5, "expected root declarations to parse directly")
assert(decls[1].tag == "DeclStruct" and decls[1].name == "Pair")
assert(decls[2].tag == "DeclUnion" and decls[2].name == "MaybePair")
assert(decls[3].tag == "DeclHandle" and decls[3].name == "Store")
assert(decls[4].tag == "DeclRegion" and decls[4].name == "Flow")
assert(decls[5].tag == "DeclFunc" and decls[5].name == "accept")
assert(llbl.is(decls[5].params[1].type, "HostEval") and decls[5].params[1].type.evaluated,
  "document-scope declaration names must be visible to later type HostEvals")
assert(decls[5].params[1].type.value == decls[1], "[Pair] should resolve to the earlier parsed declaration")

local generated_decls = {
  Ast.node("DeclStruct", { name = "Generated", fields = {} }),
}
local spliced, spliced_doc = assert(lalin.loadstring([[
[generated_decls]

fn scaled(x [Generated]) [i32] do
  return x * [scale]
end
]], "@document-splice.lln", {
  env = {
    generated_decls = generated_decls,
    scale = 7,
  },
}))
assert(#spliced == 2 and spliced[1].name == "Generated" and spliced[2].name == "scaled",
  "top-level [generated] should splice declarations through Lalin.decls")
assert(spliced_doc.materialized and spliced_doc.decls == spliced, "document metadata should record materialized decls")
local param_ty = spliced[2].params[1].type
assert(llbl.is(param_ty, "HostEval") and param_ty.evaluated and param_ty.value == spliced[1],
  "generated declarations should bind by name before later HostEvals")
local scale_expr = spliced[2].body[1].values[1].right
assert(llbl.is(scale_expr, "HostEval") and scale_expr.evaluated and scale_expr.value == 7,
  "opts.env should supply host constants to document HostEvals")

local function rejects(src, needle)
  local got, err = lalin.loadstring(src, "@bad.lln")
  assert(got == nil, "bad .lln document should not load: " .. tostring(src))
  assert(tostring(err):match(needle), "expected error matching " .. tostring(needle) .. ", got: " .. tostring(err))
end

rejects("local x = 1", "rooted at Lalin%.decls")
rejects("return {}", "return")
rejects("import \"lalin.syntax\"", "import")
rejects("module Demo", "module")

io.write("lalin .lln document root ok\n")
