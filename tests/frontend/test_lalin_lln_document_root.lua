package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local lalin = require("lalin")
local asdl = require("lalin.asdl")
require("lalin.schema_v2")
local P = package.loaded["lalin.schema_v2.parse"]
local Tr = package.loaded["lalin.schema_v2.tree"]
local Ty = package.loaded["lalin.schema_v2.type"]
local C = package.loaded["lalin.schema_v2.core"]

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
assert(asdl.classof(doc) == P.ParsedDocument and doc.chunkname == "@document-root.lln",
  "loadstring should return ParsedDocument metadata")
assert(doc.body == decls, "ParsedDocument.body should be the returned decl array")
assert(#decls == 5, "expected root declarations to parse directly")
assert(asdl.classof(decls[1]) == P.ParsedStruct and decls[1].name == "Pair")
assert(asdl.classof(decls[2]) == P.ParsedUnion and decls[2].name == "MaybePair")
assert(asdl.classof(decls[3]) == P.ParsedHandle and decls[3].name == "Store")
assert(asdl.classof(decls[4]) == P.ParsedRegion and decls[4].name == "Flow")
assert(asdl.classof(decls[5]) == P.ParsedFunc and decls[5].name == "accept")
assert(asdl.classof(decls[5].params[1].ty) == Ty.TNamed,
  "document-scope declaration names must be visible to later type HostEvals")

-- Top-level [generated] splices declarations through Lalin.decls as a typed
-- declaration group; authored decls after the splice still see the generated
-- names and host constants.
local generated = { P.ParsedStruct("Generated", {}) }
local spliced, spliced_doc = assert(lalin.loadstring([[
[generated_decls]

fn scaled(x [Generated]) [i32] do
  return x * [scale]
end
]], "@document-splice.lln", {
  env = {
    generated_decls = generated,
    scale = 7,
  },
}))
assert(asdl.classof(spliced_doc) == P.ParsedDocument, "spliced document should remain typed metadata")
assert(#spliced == 2, "top-level [generated] should splice declarations through Lalin.decls")
assert(asdl.classof(spliced[1]) == P.ParsedDeclGroup and spliced[1].decls[1] == generated[1],
  "generated declarations should arrive as a typed declaration group")
assert(asdl.classof(spliced[2]) == P.ParsedFunc and spliced[2].name == "scaled",
  "authored fn should follow the generated splice")
local param_ty = spliced[2].params[1].ty
assert(asdl.classof(param_ty) == Ty.TNamed,
  "generated declarations should bind by name before later HostEvals")
local scale_expr = spliced[2].body.body[1].stmt.value
assert(asdl.classof(scale_expr) == Tr.ExprBinary and asdl.classof(scale_expr.rhs.value) == C.LitInt
  and scale_expr.rhs.value.raw == "7",
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
