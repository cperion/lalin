package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local llbl = require("llbl")
local g = llbl.grammar

local A = llbl.dialect "LangA" {
  -- Creates the A language head.
  g.head. a {
    emit = function() return "a" end,
  },
}

local B = llbl.dialect "LangB" {
  g.head. b {
    emit = function() return "b" end,
  },
}

assert(A:language():describe().tag == "Language", "language has singleton language")
assert(#llbl.core_language():describe().members == 1, "llbl is the smallest singleton language")
assert(llbl.core_language():describe().members[1].name == "llbl", "llbl singleton contains the llbl member")
assert(#A:language():describe().members == 2, "dialect language includes llbl plus the dialect")
assert((llbl.core_language() .. A:language()) == A:language(), "llbl core language is the left identity")
assert((A:language() .. llbl.core_language()) == A:language(), "llbl core language is the right identity")

local env = A:env()
assert(env.a ~= nil, "language env delegates through singleton language")
assert(env.llbl == llbl and env.N == llbl.N, "dialect language installs shared llbl substrate")
assert(env.shared == llbl.shared, "dialect language installs shared LLBL substrate services")
assert(env.shared.origins.here and env.shared.diagnostics.new and env.shared.regions.define, "shared substrate exposes origin/diagnostic/region services")
assert(env.shared.fragments.spread == llbl.spread and env.shared.formatting.format == llbl.format, "shared substrate exposes fragment and formatting services")
assert(env.shared.languages.identity():describe().members[1].name == "llbl", "shared language identity service returns core language")
assert(llbl.is(env.unknown_name, "Symbol"), "singleton language auto-names are generic symbols")
assert(env.unknown_name.generated == false and env.unknown_name.symbol_kind == "source", "auto-names are source symbols")
assert(llbl.N.generated_name.generated == true and llbl.N.generated_name.symbol_kind == "generated", "N creates generated symbols")
local scope = llbl.shared.symbols.scope("test")
local fresh1, fresh2 = scope:fresh("tmp"), scope:fresh("tmp")
assert(fresh1.generated and fresh2.generated and fresh1.text ~= fresh2.text, "symbol scopes create unique generated symbols")

local resolved_a = A:language():resolve_symbol(llbl.shared.symbols.source("a"))
assert(llbl.is(resolved_a, "Binding") and resolved_a.kind == "export" and resolved_a.owner == "LangA" and resolved_a.value == env.a, "language resolves exported symbols with owner")
local resolved_llb = A:language():resolve_symbol(llbl.shared.symbols.source("llbl"))
assert(resolved_llb.owner == "llbl" and resolved_llb.value == llbl, "language resolves shared llbl substrate binding")
local unresolved = A:language():resolve_symbol(llbl.shared.symbols.source("missing_name"))
assert(unresolved.kind == "unresolved" and unresolved.language == "LangA", "language resolver returns unresolved binding")
local regioned_binding
llbl.gps.each(function(binding) regioned_binding = binding end, A:language():symbol_region(llbl.shared.symbols.source("a")))
assert(regioned_binding and regioned_binding.owner == "LangA", "language symbol region yields binding")
assert(llbl.shared.symbols.resolve(A:language(), llbl.shared.symbols.source("a")).owner == "LangA", "shared symbol resolver delegates through language")
assert(llbl.shared.languages.resolve_symbol(A:language(), llbl.shared.symbols.source("a")).owner == "LangA", "shared language resolver delegates through language")

local a_head = A:describe_head("a")
assert(a_head.documentation == "Creates the A language head.", "head introspection captures leading Lua comments")

llbl.source.register("llbl_diag_context.lua", "-- Explains the failing value.\nfailing_value()\n")
local diag_origin = { __llbl_tag = "Origin", source = "llbl_diag_context.lua", file = "llbl_diag_context.lua", line = 2 }
diag_origin.leading_comment = llbl.source.leading_comment(diag_origin)
local rendered_diag = llbl.diagnostic { message = "bad value", primary = diag_origin }:render()
assert(rendered_diag:match("context: Explains the failing value%."), "diagnostic rendering includes leading comment context")

local parent_origin = { __llbl_tag = "Origin", source = "llbl_diag_context.lua", file = "llbl_diag_context.lua", line = 1, leading_comment = "Outer generated context." }
local child_origin = { __llbl_tag = "Origin", source = "llbl_diag_context.lua", file = "llbl_diag_context.lua", line = 2, leading_comment = "Inner generated context.", parent = parent_origin }
local stacked_diag = llbl.diagnostic { message = "nested bad value", primary = child_origin }:render()
assert(stacked_diag:match("Outer generated context%."), "diagnostic rendering includes parent origin context")
assert(stacked_diag:match("Inner generated context%."), "diagnostic rendering includes child origin context")

local direct = llbl.use(A, { scope = "env" })
assert(direct.language == A:language(), "llbl.use(Dialect) delegates to the dialect language")
assert(direct.env.llbl == llbl and direct.env.a ~= nil, "direct language use still installs the language substrate")

local AB = (A:language() .. B:language()).prefer {
  name = "LangA",
  type = "LangA",
  expr = "LangA",
  string = "LangA",
  number = "LangA",
  boolean = "LangA",
  value = "LangA",
  identity = "LangA",
}

local ab_env = AB.env { scope = "env" }
assert(ab_env.a ~= nil and ab_env.b ~= nil, "language composition merges language exports")

local AOnly = AB - "LangB"
local a_env = AOnly.env { scope = "env" }
assert(rawget(a_env, "a") ~= nil and rawget(a_env, "b") == nil, "language subtraction removes member exports")
assert(rawget(a_env, "llbl") == llbl, "language subtraction preserves llbl substrate")

local BOnly = AB.only { "LangB" }
local b_env = BOnly.env { scope = "env" }
assert(rawget(b_env, "a") == nil and rawget(b_env, "b") ~= nil, "language projection keeps selected member")
assert(rawget(b_env, "llbl") == llbl, "language projection preserves llbl substrate")

local md = AB.markdown { title = "AB Reference" }
assert(md:match("# AB Reference"), "language markdown uses requested title")
assert(md:match("## LLBL Syntax Model"), "language markdown includes shared syntax primer")
assert(md:match("head%. name"), "language markdown explains dot-head syntax")
assert(md:match("## Members"), "language markdown includes member table")
assert(md:match("LangA"), "language markdown includes first language")
assert(md:match("LangB"), "language markdown includes second language")
assert(md:match("### Heads"), "language markdown includes generic language heads")
assert(md:match("Capability axes"), "language markdown includes capability axes")
assert(md:match("resolves%.symbols"), "language markdown includes llbl symbol resolver capability")
assert(md:match("Creates the A language head%."), "language markdown includes captured Lua comments")
assert(md:match("a%s*```"), "language markdown emits syntax-shaped head forms")
assert(md:match("member%. LangA"), "language markdown emits syntax-shaped member forms")
assert(not md:match("|%-%-%-"), "language markdown avoids markdown tables")

io.write("llbl language_algebra ok\n")
