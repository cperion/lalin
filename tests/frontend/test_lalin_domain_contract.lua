package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local lalin = require("lalin")
local asdl = require("lalin.asdl")

local T = require("lalin.schema_v2")
require("lalin.impl.tree_check.init")
local Tr = T.LalinTree

local Check = T.LalinCheck
local function check(src, name)
  local decls = assert(lalin.loadstring(src, "@" .. name .. ".lln"))
  local module = lalin.syntax.to_module(decls, name, T)
  return require("lalin.frontend_pipeline")(T).typecheck_module(module, {})
end

local store_ok = check([=[
struct Record
  value [i32]
end

struct Store
  records [ptr [Record]]
end

handle Store.Ref [u32]
  invalid = 0
  domain [Store]
  target [Record]
end

region Store.borrow(self [readonly [ptr [Store]]], ref [Store.Ref];
  borrowed(record [lease("self", ptr [Record])]),
  stale(ref [Store.Ref]),
  missing(ref [Store.Ref])
)
  entry start()
    jump missing(ref)
  end
end

fn Store.count(self [ptr [Store]]) [index]
  requires preserve(self)
  return 0
end
]=], "domain_store_ok")
assert(#store_ok.issues == 0, "Store domain should satisfy handle+region+lease contract")

local lua_ok = check([=[
extern lua_gettop(L [rawptr]) [i32]
end

struct LuaValueRecord
  ref [i32]
end

struct LuaState
  L [rawptr]
end

handle LuaState.Ref [u32]
  invalid = 0
  domain [LuaState]
  target [LuaValueRecord]
end

region LuaState.resolve(self [readonly [ptr [LuaState]]], ref [LuaState.Ref];
  granted(value [lease("self", ptr [LuaValueRecord])]),
  invalid(ref [LuaState.Ref])
)
  entry start()
    jump invalid(ref)
  end
end

fn LuaState.top(self [ptr [LuaState]]) [index]
  requires preserve(self)
  return 0
end
]=], "domain_lua_ok")
assert(#lua_ok.issues == 0, "LuaBridge-shaped domain should satisfy same Domain contract")

local resolver_ok = check([=[
struct Config
  flag [i32]
end

struct ConfigResolver
  records [ptr [Config]]
end

handle ConfigResolver.Ref [u32]
  invalid = 0
  domain [ConfigResolver]
  target [Config]
end

region ConfigResolver.resolve(self [readonly [ptr [ConfigResolver]]], ref [ConfigResolver.Ref];
  granted(config [lease("self", ptr [Config])]),
  invalid(ref [ConfigResolver.Ref]),
  busy
)
  entry start()
    jump busy
  end
end
]=], "domain_resolver_ok")
assert(#resolver_ok.issues == 0, "Resolver-shaped domain should satisfy Domain contract")

local missing = check([=[
struct MissingRecord
  value [i32]
end
struct MissingStore
  records [ptr [MissingRecord]]
end
handle MissingStore.Ref [u32]
  invalid = 0
  domain [MissingStore]
  target [MissingRecord]
end
]=], "domain_missing")
assert(#missing.issues == 1 and asdl.classof(missing.issues[1]) == Check.TypeIssueDomainContract, "domain handle without resolver should fail at declaration")

local no_lease = check([=[
struct NoLeaseRecord
  value [i32]
end
struct NoLeaseStore
  records [ptr [NoLeaseRecord]]
end
handle NoLeaseStore.Ref [u32]
  invalid = 0
  domain [NoLeaseStore]
  target [NoLeaseRecord]
end
region NoLeaseStore.resolve(self [readonly [ptr [NoLeaseStore]]], ref [NoLeaseStore.Ref];
  granted(record [ptr [NoLeaseRecord]]),
  missing(ref [NoLeaseStore.Ref])
)
  entry start()
    jump missing(ref)
  end
end
]=], "domain_no_lease")
assert(#no_lease.issues == 1 and asdl.classof(no_lease.issues[1]) == Check.TypeIssueDomainContract, "resolver without lease grant should fail")

io.write("lalin domain contract ok\n")
