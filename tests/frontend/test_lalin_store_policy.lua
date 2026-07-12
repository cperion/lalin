package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local lalin = require("lalin")
local asdl = require("lalin.asdl")

local T = require("lalin.schema_v2")
local Tr = T.LalinTree

local Check = T.LalinCheck
local decls, doc = assert(lalin.loadstring([=[
struct Token
  kind [u32]
  start [index]
  stop [index]
end

struct TokenStore
  storage [ptr [Token]]
  count [index]
  capacity [index]
  epoch [u32]
end

TokenStore.store.target = Token
TokenStore.metamethods.__getdecls = arena_store

fn use_store(s [ptr [TokenStore]]) [index]
  return s:capacity_left()
end
]=], "@store-policy.lln"))

local seen = {}
for _, d in ipairs(decls) do
  local q = d.qualifier and table.concat(d.qualifier, ".") or ""
  seen[d.tag .. ":" .. q .. ":" .. tostring(d.name)] = d
end

assert(seen["DeclStruct::Token"], "Token struct should remain explicit")
assert(seen["DeclStruct::TokenStore"], "TokenStore struct should remain explicit")
assert(seen["DeclHandle:TokenStore:Ref"], "arena_store should generate TokenStore.Ref")
assert(seen["DeclRegion:TokenStore:borrow"], "arena_store should generate TokenStore.borrow")
assert(seen["DeclRegion:TokenStore:compact"], "arena_store should generate TokenStore.compact")
assert(seen["DeclFunc:TokenStore:capacity_left"], "arena_store should generate TokenStore.capacity_left")
assert(seen["DeclFunc:TokenStore:len"], "arena_store should generate TokenStore.len")
assert(seen["DeclFunc::use_store"], "user function should remain explicit")

assert(doc.env.TokenStore.handles.Ref == seen["DeclHandle:TokenStore:Ref"], "generated handle should bind to owner")
assert(doc.env.TokenStore.regions.borrow == seen["DeclRegion:TokenStore:borrow"], "generated borrow should bind to owner")
assert(doc.env.TokenStore.methods.capacity_left == seen["DeclFunc:TokenStore:capacity_left"], "generated method should bind to owner")

local borrow = seen["DeclRegion:TokenStore:borrow"]
assert(borrow.blocks[1].body[1].payload[1].shorthand == true, "generated borrow should use jump shorthand")

local module = lalin.syntax.to_module(decls, "StorePolicy", T)
local item_kinds = {}
for _, item in ipairs(module.items) do item_kinds[tostring(asdl.classof(item))] = true end
assert(asdl.classof(module.items[1]) == Tr.ItemType, "first item lowers to type")
assert(asdl.classof(module.items[#module.items]) == Tr.ItemFunc, "last item lowers to function")
local checked = require("lalin.frontend_pipeline")(T).typecheck_module(module, {})
assert(#checked.issues == 0, "generated arena store should satisfy Domain contract")

local bad_decls = assert(lalin.loadstring([=[
struct BadRecord
  x [i32]
end

struct BadStore
  records [ptr [BadRecord]]
end

handle BadStore.Ref [u32]
  invalid = 0
  domain [BadStore]
  target [BadRecord]
end
]=], "@bad-domain.lln"))
local bad_module = lalin.syntax.to_module(bad_decls, "BadDomain", T)
local bad_checked = require("lalin.frontend_pipeline")(T).typecheck_module(bad_module, {})
assert(#bad_checked.issues == 1 and asdl.classof(bad_checked.issues[1]) == Check.TypeIssueDomainContract, "handle domain without resolver should fail at declaration")

io.write("lalin store policy ok\n")
