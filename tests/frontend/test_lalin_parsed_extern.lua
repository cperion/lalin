package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local lalin = require("lalin")
local Document = require("lalin.syntax.document")
local asdl = require("lalin.asdl")

local T = asdl.context()
require("lalin.schema_projection")(T)
local Tr = T.LalinTree

local src = [=[
extern lua_gettop(L [rawptr]) [i32]
end

extern lua_pcall(L [rawptr], nargs [i32], nresults [i32], errfunc [i32]) [i32]
end

struct LuaState
  L [rawptr]
end

fn raw_top(L [rawptr]) [i32]
  return lua_gettop(L)
end

region LuaState.pcall(self [ptr [LuaState]], nargs [i32], nresults [i32];
  ok,
  error(status [i32])
)
  entry start()
    jump error(status = 1)
  end
end
]=]

local doc = Document.parse(src, "@lua-api-extern.lln")
assert(doc.body[1].tag == "DeclExtern" and doc.body[1].name == "lua_gettop", "lua_gettop extern parses")
assert(doc.body[1].symbol == nil, "extern symbol defaults to declaration name when omitted")
assert(#doc.body[2].params == 4 and doc.body[2].params[2].name == "nargs", "extern params parse")

local decls, mat = Document.materialize(doc)
assert(mat.env.lua_gettop ~= nil and mat.env.lua_pcall ~= nil, "externs bind in document env")
assert(decls[4].tag == "DeclFunc" and decls[4].name == "raw_top", "extern call wrapper parses")
assert(decls[5].tag == "DeclRegion" and decls[5].qualifier[1] == "LuaState", "bridge region parses after externs")

local module = lalin.syntax.to_module(decls, "LuaApiExtern", T)
require("lalin.tree_typecheck")(T)
assert(asdl.classof(module.items[1]) == Tr.ItemExtern, "first extern lowers to ItemExtern")
assert(module.items[1].func.name == "lua_gettop", "extern item keeps name")
assert(module.items[1].func.symbol == "lua_gettop", "extern item keeps C symbol")
assert(#module.items[2].func.params == 4, "lua_pcall params lower")
assert(asdl.classof(module.items[4]) == Tr.ItemFunc, "raw_top lowers to function")
assert(asdl.classof(module.items[5]) == Tr.ItemRegion, "LuaState.pcall lowers to region")

local checked = module:typecheck_tree_module()
assert(#checked.issues == 0, "extern declarations and bridge region should typecheck")

io.write("lalin parsed extern ok\n")
