package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local llbl = require("llbl")
local g = llbl.grammar

-- HostEval constructors and evaluation caching.
local calls = 0
local h = llbl.host_eval {
  kind = "parsed",
  channel = "parsed:host_eval",
  env = { x = 41 },
  thunk = function(env)
    calls = calls + 1
    return env.x + 1
  end,
}
assert(h:evaluate() == 42, "HostEval thunk should evaluate")
assert(h:evaluate() == 42 and calls == 1, "HostEval should cache evaluation")
local parsed = llbl.host_eval.parsed("x + 2", { "x" }, { x = 40 })
assert(parsed:evaluate() == 42, "parsed HostEval source should evaluate in env")

-- Lua index brackets enter heads as index:host and adapt through the expected role.
local D = llbl.dialect "HostEvalRoleTest" {
  g.role. type { kind = "type", adapter = function(_, v)
    if type(v) == "table" and v.tag == "Decl" then return llbl.type(v.name) end
    return v
  end },
  g.role. items { kind = "array", item = "name", splice_policy = { bare_fragment = true } },
  g.head. use {
    g.slot. name [g.name],
    g.slot. ty [g.type],
    emit = function(n, _lang, meta) return { ty = n.ty, raw = meta.raw.ty, event = meta.events.ty } end,
  },
  g.head. box {
    g.slot. items [g.items],
    emit = function(n) return n.items end,
  },
}
local env = llbl.use(D, { scope = "env" }).env
local decl = { tag = "Decl", name = "Pair" }
local used = env.use. thing [decl]
assert(used.ty.name == "Pair", "type role adapter should see non-type Lua index values")
assert(llbl.is(used.raw, "HostEval"), "index operand should be stored as HostEval")
assert(used.event.channel == llbl.channel.index_host, "index event should use index:host")
assert(used.event.legacy_channel == llbl.channel.index_value, "event should preserve legacy raw channel shape")

-- Qualified fragments and descriptor-controlled bare/HostEval splicing.
local frag = D:fragment("items", { "a", "b" })
assert(frag.role_id and llbl.role_id_display(frag.role_id) == "HostEvalRoleTest.items")
local boxed = env.box { frag, llbl.host_eval.lua(frag), "c" }
assert(#boxed == 5 and boxed[1].text == "a" and boxed[3].text == "a" and boxed[5].text == "c",
  "bare and HostEval fragments should splice under descriptor policy")

local bad = llbl.fragment("wrong", { llbl.name("x") })
local ok, err = pcall(function() return env.box { llbl._(bad) } end)
assert(not ok and tostring(err):match("E_SPREAD_ROLE"), "bad spread should report role diagnostic")

-- Optional slot ambiguity must account for index:host overlapping legacy index channels.
local ok_ambig, ambig_err = pcall(function()
  return llbl.dialect "HostEvalAmbiguous" {
    g.head. h {
      g.slot. a [g.type] { optional = true },
      g.slot. b [g.value] { channel = llbl.channel.index_value, optional = true },
      emit = function(n) return n end,
    },
  }
end)
assert(not ok_ambig and tostring(ambig_err):match("E_AMBIGUOUS_OPTIONAL_SLOTS"),
  "index:host should participate in optional-slot ambiguity checks")

io.write("llbl host_eval role_algebra ok\n")
