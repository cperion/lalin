package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local lalin = require("lalin")
local llbl = require("llbl")
local llisle = require("llisle")

local env = lalin.language.env { scope = "env", base = {} }
assert(env.llisle, "Lalin language installs llisle namespace")
assert(rawget(env, "relation") == nil and rawget(env, "rule") == nil, "language keeps llisle heads namespaced")
assert(llbl.describe(env.llisle).tag == "Namespace", "llisle export is an LLBL namespace")

local chunk = assert(loadstring([[
return llisle {
  llisle.relation. lower_expr {
    llisle.input { expr [lln.i32], ctx [LowerCtx] },
    llisle.output { value [BackValue] },
    llisle.effects { cmd [BackCmd], diagnostic [Diagnostic] },
    llisle.strategy {
      llisle.select. best_cost,
      llisle.ambiguity. error,
      llisle.coverage. complete,
    },
  },

  llisle.rule. add_i32 {
    llisle.lower_expr {
      expr = add { lhs = llisle.P. lhs, rhs = llisle.P. rhs } [lln.i32],
      ctx = llisle.P. ctx,
    },

    llisle.when {
      (llisle.P. lhs :has_type (lln.i32)) * (llisle.P. rhs :has_type (lln.i32)),
    },

    llisle.choose {
      llisle.alt. imm {
        llisle.when { (llisle.P. rhs :fits_imm32 ()) + (llisle.P. rhs :is_const ()) },
        llisle.cost (1),
        llisle.run {
          llisle.emit. cmd { add_i32_imm { dst = llisle.V. out, lhs = llisle.P. lhs, imm = llisle.P. rhs } },
          llisle.ret { value = llisle.V. out },
        },
      },

      llisle.alt. reg {
        llisle.cost (2),
        llisle.run {
          llisle.emit. cmd { add_i32 { dst = llisle.V. out, lhs = llisle.P. lhs, rhs = llisle.P. rhs } },
          llisle.ret { value = llisle.V. out },
        },
      },
    },
  },
}
]], "llisle_family.lua"))
setfenv(chunk, env)
local zone = chunk()

assert(zone.name == "llisle" and zone.member == "llisle.dsl", "llisle namespace creates a language zone")
assert(#zone.items == 2, "zone contains relation and rule")
assert(getmetatable(zone.items[1]) == llisle.RelationSpec, "relation head returns Lisle relation spec")
assert(getmetatable(zone.items[2]) == llisle.RuleSpec, "rule head returns Lisle rule spec")

local diagnostics = lalin.language.diagnostics(zone)
assert(not diagnostics:has_errors(), diagnostics.items[1] and diagnostics.items[1].message or "llisle diagnostics should accept coherent rules")

local index = lalin.language.index(zone)
local saw_relation, saw_rule, saw_alt = false, false, false
for _, sym in ipairs(index.symbols or {}) do
  saw_relation = saw_relation or sym.name == "lower_expr" and sym.kind == "llisle.relation"
  saw_rule = saw_rule or sym.name == "add_i32" and sym.kind == "llisle.rule"
  saw_alt = saw_alt or sym.name == "imm" and sym.kind == "llisle.alt"
end
assert(saw_relation and saw_rule and saw_alt, "language index includes llisle relations, rules, and alternatives")

local formatted = lalin.language.format(zone, { width = 100 })
assert(formatted:match("llisle%s*{"), "language formatter preserves llisle zone")
assert(formatted:match("relation%. lower_expr"), "llisle formatter renders relation heads")
assert(formatted:match("rule%. add_i32"), "llisle formatter renders rule heads")
assert(formatted:match("choose"), "llisle formatter renders local sum elimination")
assert(formatted:match("%*"), "llisle formatter renders product/and guard algebra")
assert(formatted:match("%+"), "llisle formatter renders sum/or guard algebra")

local bad = lalin.language.load([[
return llisle {
  llisle.rule. orphan {
    llisle.missing_relation { expr = llisle.P. expr },
    llisle.run { llisle.ret { value = llisle.V. out } },
  },
}
]], "llisle_bad.lua")
local bad_diagnostics = lalin.language.diagnostics(bad)
assert(bad_diagnostics:has_errors(), "llisle diagnostics reports unknown relations")
assert(bad_diagnostics.items[1].code == "E_LLISLE_UNKNOWN_RELATION", "llisle diagnostics use stable codes")

local md = lalin.markdown { title = "Lalin Language Reference" }
assert(md:match("## llisle%.dsl"), "language markdown includes llisle member docs")
assert(md:match("Llisle LLBL Surface"), "language markdown includes llisle language introspection")
assert(md:match("sum%-elimination"), "language markdown includes llisle semantic ownership")

io.write("llisle language ok\n")
