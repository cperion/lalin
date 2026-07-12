package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local lalin = require("lalin")
local asdl = require("lalin.asdl")
local llbl = require("llbl")

local T = require("lalin.schema_v2")
require("lalin.impl.tree_check.init")
local Tr, Check = T.LalinTree, T.LalinCheck

local source = [=[
union MaybeI32
  None
  Some(value [i32])
end

fn payload_case() [i32] do
  let value [MaybeI32] = MaybeI32::Some(42)
  switch value do
    case variant Some(payload) then
      return payload
    case variant None then
      return 0
    default then
      return -1
  end
end
]=]

local decls = assert(lalin.loadstring(source, "@parsed-variant-surface.lln"))
local ctor_projection = decls[2].body[1].init.projection
assert(asdl.class_basename(ctor_projection) == "ParsedVariantConstructorCall",
  "`Union::Case(...)` must parse with the precise constructor-call projection leaf")
assert(decls[2].body[1].init.tag == "Call" and ctor_projection.type_name == "MaybeI32" and ctor_projection.variant_name == "Some",
  "constructor arguments must be owned by the typed call projection")
assert(decls[2].body[2].variant_arms[1].binds[1] == "payload", "payload arm bind must remain explicit")
assert(#decls[2].body[2].variant_arms[2].binds == 0, "nullary arm must carry no bind")

local module = lalin.syntax.to_module(decls, "parsed_variant_surface", T)
assert(asdl.classof(module.items[2].func.body[1].init) == Tr.ExprCtor, "parsed constructor must project to ExprCtor")
assert(asdl.classof(module.items[2].func.body[2]) == Tr.StmtSwitch, "parsed variant arms must project directly to the canonical switch")
local checked = require("lalin.frontend_pipeline")(T).typecheck_module(module, {})
assert(#checked.issues == 0, "valid nullary/payload constructors and binds must typecheck")

local function issues_for(body, name)
  local bad = [=[
union MaybeI32
  None
  Some(value [i32])
end

fn rejected() [i32] do
]=] .. body .. "\nend\n"
  local parsed = assert(lalin.loadstring(bad, "@" .. name .. ".lln"))
  local ok, result = pcall(function()
    return require("lalin.frontend_pipeline")(T).typecheck_module(lalin.syntax.to_module(parsed, name, T), {})
  end)
  return ok and result.issues or { tostring(result) }
end

local unknown_ctor = issues_for("  return MaybeI32::Missing()", "unknown-variant-constructor")
local saw_unknown_ctor = false
for _, issue in ipairs(unknown_ctor) do
  if asdl.classof(issue) == Check.TypeIssueUnknownVariant then
    saw_unknown_ctor = issue.type_name == "MaybeI32" and issue.variant_name == "Missing"
  end
end
assert(saw_unknown_ctor, "unknown constructor must produce exact TypeIssueUnknownVariant")

local invalid_bind = issues_for([=[
  let value [MaybeI32] = MaybeI32::None()
  switch value do
    case variant None(payload) then
      return 1
    default then
      return 0
  end
]=], "invalid-variant-bind")
local saw_bind_count = false
for _, issue in ipairs(invalid_bind) do
  if asdl.classof(issue) == Check.TypeIssueVariantBindCount then
    saw_bind_count = issue.variant_name == "None" and issue.expected == 0 and issue.actual == 1
  end
end
assert(saw_bind_count, "payload bind on a nullary case must produce exact TypeIssueVariantBindCount")

local unknown_arm = issues_for([=[
  let value [MaybeI32] = MaybeI32::None()
  switch value do
    case variant Missing then
      return 1
    default then
      return 0
  end
]=], "unknown-variant-arm")
local saw_unknown = false
for _, issue in ipairs(unknown_arm) do
  if asdl.classof(issue) == Check.TypeIssueUnknownVariant then saw_unknown = issue.variant_name == "Missing" end
end
assert(saw_unknown, "unknown arm must produce exact TypeIssueUnknownVariant")

local multi_source = [=[
union PairVariant
  Pair(left [i32], right [i32])
end

fn rejected() [i32] do
  let value [PairVariant] = PairVariant::Pair(1, 2)
  switch value do
    case variant Pair(left, right) then
      return 1
    default then
      return 0
  end
end
    ]=]
local multi_decls = assert(lalin.loadstring(multi_source, "@multi-field-variant.lln"))
local multi_issues = require("lalin.frontend_pipeline")(T).typecheck_module(lalin.syntax.to_module(multi_decls, "multi_field_variant", T), {}).issues
local unsupported_count = 0
for _, issue in ipairs(multi_issues) do
  if asdl.classof(issue) == Check.TypeIssueVariantPayloadUnsupported then
    assert(issue.type_name == "PairVariant" and issue.variant_name == "Pair" and issue.field_count == 2)
    unsupported_count = unsupported_count + 1
  end
end
assert(unsupported_count == 2, "multi-field constructor and arm must each return typed unsupported, never nullary")

local unique_decls, unique_issue = lalin.loadstring("unique union Token\n  Only\nend\n", "@unique-variant.lln")
assert(unique_decls == nil and llbl.is(unique_issue, "Diagnostic"), "unique must have a typed parser-boundary decision")
assert(unique_issue.code == "E_LALIN_UNSUPPORTED_UNIQUE")
assert(tostring(unique_issue.notes[1]):match("does not synthesize hidden identity maps"), "unique rejection must forbid hidden identity maps explicitly")

io.write("lalin parsed variant surface ok\n")
