package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local asdl = require("lalin.asdl")
local T = require("lalin.schema_v2")
local Document = require("lalin.syntax_v2.document")
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
    generated_decls = { generated_decl },
    generated_fields = { field },
    generated_variants = { variant },
    generated_stmts = { generated_stmt },
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

print("schema-v2 LLBL role-directed bracket HostEval ok")
