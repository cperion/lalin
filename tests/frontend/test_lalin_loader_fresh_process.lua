package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

-- Public loader fresh-process parity.
--
-- A fresh process must run the public loader (loadstring / loadfile / require
-- / searcher) on schema-v2 parsed ASDL exclusively.  None of the old
-- lalin.syntax parsed-frontend modules (the old document parser, grammar, or
-- tree builder) may be pulled into the process by the loader path.
--
-- lalin.syntax.ast itself is intentionally not listed: it is a leaf helper
-- table shared through lalin.exotype, which syntax_v2's own role-dialect
-- dependency (lalin.dsl.init) loads.  No old *parser* ever runs.

local old_frontend = {
  "lalin.syntax",             -- old frontend driver / register
  "lalin.syntax.document",    -- old document parser
  "lalin.syntax.decl",        -- old root declaration grammar
  "lalin.syntax.expr",        -- old expression grammar
  "lalin.syntax.stmt",        -- old statement grammar
  "lalin.syntax.type",        -- old type grammar
  "lalin.syntax.for_to_loop",
  "lalin.syntax.parse_vocab", -- old parser-boundary vocabulary
  "lalin.syntax.role_adapter",
  "lalin.syntax.to_tree",     -- old parsed-to-tree builder
  "lalin.syntax.type_value",
}

local function assert_no_old_frontend(where)
  for i = 1, #old_frontend do
    assert(package.loaded[old_frontend[i]] == nil,
      where .. " loaded old parsed-frontend module " .. old_frontend[i])
  end
end

assert_no_old_frontend("require(lalin.loader)")

local asdl = require("lalin.asdl")
require("lalin.schema_v2")
local P = package.loaded["lalin.schema_v2.parse"]
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
assert_no_old_frontend("loadstring")

-- loadfile reads a .lln file into the same typed contract.
os.execute("rm -rf " .. shell_quote("target/test_lalin_loader_fresh"))
os.execute("mkdir -p " .. shell_quote("target/test_lalin_loader_fresh/fresh"))
local f = assert(io.open("target/test_lalin_loader_fresh/fresh/math.lln", "wb"))
f:write("fn add(a [i32], b [i32]) [i32] do\n  return a + b\nend\n")
f:close()
local fdecls = assert(Loader.loadfile("target/test_lalin_loader_fresh/fresh/math.lln"))
assert(asdl.classof(fdecls[1]) == P.ParsedFunc and fdecls[1].name == "add", "typed loadfile decl")
assert_no_old_frontend("loadfile")

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
assert_no_old_frontend("require/searcher")

assert(package.loaded["lalin.syntax_v2.document"] ~= nil,
  "public loader should use lalin.syntax_v2.document")

print("public loader fresh-process parity ok")
