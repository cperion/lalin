package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

-- Public loader fresh-process parity.
--
-- A fresh process must run the public loader (loadstring / loadfile / require
-- / searcher) on the canonical schema parsed ASDL exclusively.  The loader
-- owns the single parsing path (lalin.syntax); there is no legacy frontend.

local asdl = require("lalin.asdl")
require("lalin.schema")
local P = package.loaded["lalin.schema.parse"]
local Loader = require("lalin.loader")

local function shell_quote(s)
  return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

-- loadstring returns the typed ParsedDocument plus its ParsedDecl body.
local decls, doc = assert(Loader.loadstring([[
struct Pair
  x [i32]
end

fn add(a [i32], b [i32]) [i32] do
  return a + b
end
]], "@fresh.lln"))
assert(asdl.classof(doc) == P.ParsedDocument and doc.body == decls,
  "loadstring returns typed ParsedDocument + body")
assert(asdl.classof(decls[1]) == P.ParsedStruct and decls[1].name == "Pair", "typed struct decl")

-- loadfile reads a .lln file into the same typed contract.
os.execute("rm -rf " .. shell_quote("target/test_lalin_loader_fresh"))
os.execute("mkdir -p " .. shell_quote("target/test_lalin_loader_fresh/fresh"))
local f = assert(io.open("target/test_lalin_loader_fresh/fresh/math.lln", "wb"))
f:write("fn add(a [i32], b [i32]) [i32] do\n  return a + b\nend\n")
f:close()
local fdecls = assert(Loader.loadfile("target/test_lalin_loader_fresh/fresh/math.lln"))
assert(asdl.classof(fdecls[1]) == P.ParsedFunc and fdecls[1].name == "add", "typed loadfile decl")

-- require and the installed Lua searcher cache and return the typed decl array.
Loader.path = "target/test_lalin_loader_fresh/?.lln;target/test_lalin_loader_fresh/?/init.lln"
package.loaded["fresh.math"] = nil
local m1 = assert(Loader.require("fresh.math"))
assert(asdl.classof(m1[1]) == P.ParsedFunc and m1[1].name == "add", "typed require decl")
assert(Loader.install_searcher(), "expected .lln searcher installation")
package.loaded["fresh.math"] = nil
local m2 = require("fresh.math")
assert(m2 == m1 and asdl.classof(m2[1]) == P.ParsedFunc, "searcher should return the typed decl array")
assert(Loader.remove_searcher(), "expected .lln searcher removal")

assert(package.loaded["lalin.syntax.document"] ~= nil,
  "public loader should use lalin.syntax.document")

print("public loader fresh-process parity ok")
