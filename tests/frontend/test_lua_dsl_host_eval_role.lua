package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local asdl = require("lalin.asdl")

local T = require("lalin.schema")
local dsl = require("lalin.dsl")(T)
local llbl = require("llbl")


local env = dsl.make_env()

-- Lua head [] operands are routed as HostEval so a declaration value can adapt
-- in a result type slot under the Lalin type role.
local Pair = env.struct. Pair { env.N.x [env.i32] }
local make_pair = env.fn. make_pair {} [Pair] {
  env.ret(0),
}
local unit = dsl.to_unit("LuaDslHostEval", { Pair, make_pair })
local ast = unit:ast()
local fn = ast.items[2].func
assert(asdl.classof(fn.result) == T.LalinType.TNamed, "declaration value should adapt to result type slot")
assert(fn.result.ref.path.parts[1].text == "Pair", "adapted result should name Pair")

-- Lalin fragments are qualified and _/spread still splice into Lua DSL bodies.
local stmts = dsl.stmts { env.ret() }
assert(llbl.is(stmts, "Fragment"), "dsl.stmts should produce LLBL fragment")
assert(stmts.role_id and llbl.role_id_display(stmts.role_id) == "LalinDSL.stmt",
  "Lalin statement fragment should carry qualified role id")
local spread_fn = env.fn. spread_body {} [env.void] {
  env._(stmts),
}
local spread_ast = dsl.to_unit("SpreadBody", { spread_fn }):ast()
assert(#spread_ast.items[1].func.body == 1, "_(stmt fragment) should still splice into function body")
assert(asdl.classof(spread_ast.items[1].func.body[1]) == T.LalinTree.StmtReturnVoid,
  "spliced statement should lower to return void")

-- Explicit spread helper remains valid for declaration fragments.
local decls = dsl.decls { Pair }
local unit_with_spread = dsl.to_unit("DeclSpread", { env._(decls), make_pair }):ast()
assert(#unit_with_spread.items == 2, "_(decl fragment) should splice declarations")

-- Qualified fragment role IDs are verified above via LalinDSL stmts.

io.write("lua dsl host_eval role ok\n")
