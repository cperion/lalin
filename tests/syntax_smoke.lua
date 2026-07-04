package.path = "../lua/?.lua;../lua/?/init.lua;" .. package.path

local lalin = require("lalin")

local src = [=[
fn copy_scale(dst [ptr [i32]], src [ptr [i32]], n [index]) [void] do
  requires bounds(dst)(n), bounds(src)(n), disjoint(dst)(src)
  loop i in 0 .. n do
    dst[i] = src[i] * [scale]
  end
end
]=]

local decls, doc_or_err = lalin.loadstring(src, "@smoke.lln", { env = { scale = 4 } })
if not decls then
  error(tostring(doc_or_err))
end
assert(doc_or_err and doc_or_err.tag == "DeclDocument", "expected document metadata")
assert(#decls == 1, "expected one parsed declaration")
local f = decls[1]
assert(f.tag == "DeclFunc", "expected DeclFunc")
assert(f.name == "copy_scale", "wrong function name")
assert(f.body[1].tag == "StmtRequires", "requires statement missing")
assert(f.body[2].tag == "StmtForRange", "loop statement missing")
assert(f.body[2].body[1].tag == "StmtAssign", "assignment statement missing")
assert(f.body[2].body[1].value.right.resolved == true, "host escape should resolve")
assert(f.body[2].body[1].value.right.value == 4, "host escape resolved wrong value")
print("ok")
