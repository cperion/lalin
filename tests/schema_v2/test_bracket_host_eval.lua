package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local asdl = require("lalin.asdl")
local llbl = require("llbl")
local T = require("lalin.schema_v2")
local Document = require("lalin.syntax_v2.document")
local HostAst = require("lalin.syntax_v2.ast")
local Roles = require("lalin.syntax_v2.roles")
local C, P, Tr, Ty = T.LalinCore, T.LalinParse, T.LalinTree, T.LalinType

local accesses = 0
local identity = setmetatable({}, {
  __index = function(_, value)
    accesses = accesses + 1
    return value
  end,
})
local custom = Ty.TScalar(C.ScalarU16)
local field = P.ParsedField("generated", Ty.TScalar(C.ScalarI32), false, false)
local variant = P.ParsedVariant("Generated", { field })
local generated_decl = P.ParsedStruct("GeneratedStruct", { field })
local generated_stmt = P.StmtKnown(Tr.StmtReturnValue(Tr.StmtSurface,
  Tr.ExprLit(Tr.ExprSurface, C.LitInt("42"))))

local doc = Document.parse([=[
[generated_decls]

struct Pair
  x [identity [custom]]
  [generated_fields]
end

union Maybe
  None
  [generated_variants]
end

fn answer(p [ptr [Pair]]) [identity [custom]] do
  [generated_stmts]
end

fn host_expr() [i32] do
  return [40 + 2]
end
]=], "@bracket-host-eval.lln", {
  env = {
    identity = identity,
    custom = custom,
    generated_decls = llbl.fragment("decls", { generated_decl }),
    generated_fields = llbl.fragment("product", { field }),
    generated_variants = llbl.fragment("variants", { variant }),
    generated_stmts = llbl.fragment("stmts", { generated_stmt }),
  },
})

assert(accesses == 2, "type brackets must execute Lua table access")
assert(#doc.body == 5)
assert(asdl.classof(doc.body[1]) == P.ParsedDeclGroup)
assert(doc.body[2].fields[1].ty == custom)
assert(doc.body[2].fields[2] == field)
assert(#doc.body[3].variants == 2 and doc.body[3].variants[2] == variant)
assert(asdl.classof(doc.body[4].params[1].ty) == Ty.TPtr)
assert(asdl.classof(doc.body[4].params[1].ty.elem) == Ty.TNamed)
assert(doc.body[4].result_ty == custom)

local module = Document.to_module(doc, "bracket_host_eval")
assert(#module.items == 5, "declaration HostEval must splice in source order")
local answer = module.items[4].func
assert(answer.result == custom)
assert(asdl.classof(answer.body[1]) == Tr.StmtReturnValue)
assert(asdl.classof(module.items[5].func.body[1].value) == Tr.ExprLit)
assert(module.items[5].func.body[1].value.value.raw == "42")

assert(Roles.descriptors.type.algebra == "single")
assert(Roles.descriptors.product.algebra == "product")
assert(Roles.descriptors.variants.algebra == "sum")
assert(Roles.descriptors.conts.algebra == "sum")
assert(Roles.descriptors.type.owner == Roles.dialect,
  "schema-v2 role projection must retain the canonical Lalin dialect identity")
local stamped = HostAst.host_eval("i32", { "i32" },
  { source = "@stamped-role.lln", line = 1 }, "type")
assert(Roles.adapt({ host_env = { i32 = custom } }, "type", stamped) == custom)
assert(llbl.is(stamped.expected_role, "RoleId"))
assert(llbl.role_id_equal(stamped.expected_role, Roles.descriptors.type.id))

local exit = P.ParsedExit("done", { field })
local region_doc = Document.parse([=[
region generated(; [generated_conts])
entry begin()
  return
end
end
]=], "@bracket-cont-host-eval.lln", {
  env = { generated_conts = llbl.fragment("conts", { exit }) },
})
assert(asdl.classof(region_doc.body[1]) == P.ParsedRegion)
assert(#region_doc.body[1].exits == 1 and region_doc.body[1].exits[1] == exit)

local ok, err = pcall(Document.parse, [[fn bad() ["i32"] do return end]],
  "@bad-bracket-role.lln")
assert(not ok and tostring(err):find("type role produced unsupported value", 1, true))
assert(tostring(err):find("@bad-bracket-role.lln:1", 1, true),
  "role diagnostics must retain the bracket origin")

print("schema-v2 LLBL role-directed bracket HostEval ok")
