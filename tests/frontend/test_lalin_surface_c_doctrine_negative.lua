package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local asdl = require("lalin.asdl")
local T = asdl.context()
require("lalin.schema_projection")(T)
require("lalin.tree_typecheck")(T)

local Check, Ty, Core = T.LalinCheck, T.LalinType, T.LalinCore
local function source(path)
  local file = assert(io.open(path, "rb"))
  local text = file:read("*a")
  file:close()
  return text
end

local syntax_expr = source("lua/lalin/syntax/expr.lua")
local to_tree = source("lua/lalin/syntax/to_tree.lua")
local type_expr = source("lua/lalin/tree_typecheck_expr.lua")
local type_stmt = source("lua/lalin/tree_typecheck_stmt.lua")
local type_root = source("lua/lalin/tree_typecheck.lua")
local type_type = source("lua/lalin/tree_typecheck_type.lua")

assert(not syntax_expr:match("left%.tag"), "constructor parsing must not inspect ad hoc expression tags")
assert(not syntax_expr:match("Ast%.node%(%\"VariantCtor%\""), "constructor syntax must not create a VariantCtor tag")
assert(not to_tree:match("tag == %\"VariantCtor%\""), "constructor projection must dispatch through the parsed callee leaf")
assert(not type_expr:match("scope%.facts%.variants") and not type_stmt:match("scope%.facts%.variants")
  and not type_root:match("scope%.facts%.variants") and not type_type:match("facts%.variants"),
  "variant resolution must be owned by typed lookup methods")
assert(not type_expr:match("tostring%([^%)\n]-%.ty[^%)\n]*%)")
  and not type_stmt:match("tostring%([^%)\n]-%.ty[^%)\n]*%)"),
  "type equality must not use rendered strings")

local void = Ty.TScalar(Core.ScalarVoid)
local facts = Check.TypeModuleFacts({}, {}, {}, {}, {}, {}, {})
local scope = Check.TypeValueScope("negative", {}, {}, {}, facts)
local value_missing = scope:typecheck_tree_lookup_value("absent")
assert(asdl.classof(value_missing) == Check.TypeValueLookupMissing)
local def_missing = facts:typecheck_tree_lookup_variant_name("Absent")
assert(asdl.classof(def_missing) == Check.TypeVariantDefLookupMissing)
local case_missing = def_missing:typecheck_tree_lookup_variant_case("Case")
assert(asdl.classof(case_missing) == Check.TypeVariantCaseLookupMissing and case_missing.ty == void)

assert(Check.TypeVariantCaseLookupFound.typecheck_tree_ctor and Check.TypeVariantCaseLookupMissing.typecheck_tree_ctor,
  "both constructor lookup leaves must own constructor behavior")
assert(Check.TypeVariantCaseLookupFound.typecheck_tree_source_variant_arm
  and Check.TypeVariantCaseLookupMissing.typecheck_tree_source_variant_arm,
  "both switch lookup leaves must own source-arm behavior")

io.write("lalin surface-c doctrine negatives ok\n")
