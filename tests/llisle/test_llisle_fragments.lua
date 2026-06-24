package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local moon = require("moonlift")
local llisle = require("llisle")

local env = moon.family.env { scope = "env", base = {} }
local chunk = assert(loadstring([[
local scalar_rules = llisle.rules {
  llisle.rule. lower_const_i32 {
    llisle.lower_expr { expr = llisle.P. expr, ctx = llisle.P. ctx },
    llisle.when { llisle.P. expr :is_const () },
    llisle.run { llisle.ret { value = llisle.V. out } },
  },
}

local arith_rules = llisle.rules {
  llisle.rule. lower_add_i32 {
    llisle.lower_expr { expr = add { lhs = llisle.P. lhs, rhs = llisle.P. rhs } [ml.i32], ctx = llisle.P. ctx },
    llisle.run { llisle.ret { value = llisle.V. out } },
  },
}

return llisle {
  llisle.relation. lower_expr {
    llisle.input { expr [ml.i32], ctx [LowerCtx] },
    llisle.output { value [BackValue] },
  },
  _(scalar_rules .. arith_rules),
}
]], "llisle_fragments.lua"))
setfenv(chunk, env)
local zone = chunk()

assert(#zone.items == 3, "llisle rule fragments splice into zones")
assert(getmetatable(zone.items[2]) == llisle.RuleSpec, "first spliced item is a rule")
assert(getmetatable(zone.items[3]) == llisle.RuleSpec, "second spliced item is a rule")
assert(not moon.family.diagnostics(zone):has_errors(), "spliced llisle rules validate")

io.write("llisle fragments ok\n")
