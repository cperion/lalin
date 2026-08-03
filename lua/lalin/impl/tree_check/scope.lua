-- impl/tree_check/scope.lua
-- Type scope management leaf methods.

require("lalin.schema_v2")
local C      = require("lalin.schema_v2.core")
local B      = require("lalin.schema_v2.bind")
local LCheck = require("lalin.schema_v2.check")
local Sem    = require("lalin.schema_v2.sem")
local Ty     = require("lalin.schema_v2.type")
local Tr     = require("lalin.schema_v2.tree")
function LCheck.TypeValueScope:typecheck_tree_lookup_value(name)
  for i = #(self.values or {}), 1, -1 do
    local entry = self.values[i]
    if entry.name == name then return LCheck.TypeValueLookupFound(entry.binding) end
  end
  return LCheck.TypeValueLookupMissing(name)
end

function LCheck.TypeValueLookupFound:typecheck_tree_value_type_or(fallback) return self.binding.ty end
function LCheck.TypeValueLookupMissing:typecheck_tree_value_type_or(fallback) return fallback end

function LCheck.TypeModuleFacts:typecheck_tree_lookup_variant_name(type_name)
  for i = 1, #(self.variants or {}) do
    if self.variants[i].type_name == type_name then return LCheck.TypeVariantDefLookupFound(self.variants[i]) end
  end
  return LCheck.TypeVariantDefLookupMissing(type_name, Ty.TScalar(require("lalin.schema_v2.core").ScalarVoid))
end

function LCheck.TypeVariantDefLookupFound:typecheck_tree_lookup_variant_case(variant_name)
  for i = 1, #self.def.variants do
    if self.def.variants[i].name == variant_name then
      return LCheck.TypeVariantCaseLookupFound(self.def, self.def.variants[i])
    end
  end
  return LCheck.TypeVariantCaseLookupMissing(self.def.type_name, variant_name, self.def.ty)
end

function LCheck.TypeVariantDefLookupMissing:typecheck_tree_lookup_variant_case(variant_name)
  return LCheck.TypeVariantCaseLookupMissing(self.type_name, variant_name, self.ty)
end

function LCheck.TypeVariantCase:typecheck_tree_payload_lookup()
  if #self.fields == 1 then return LCheck.TypeVariantPayloadFound(self.fields[1].ty) end
  if #self.fields > 1 then return LCheck.TypeVariantPayloadUnsupported(#self.fields) end
  if self.payload:tree_check_is_void_type() then return LCheck.TypeVariantPayloadNone end
  return LCheck.TypeVariantPayloadFound(self.payload)
end

function LCheck.TypeValueScope:typecheck_tree_add_value(name, ty, binding)
  local values = {}
  for _, e in ipairs(self.values or {}) do values[#values+1] = e end
  local b = binding or B.Binding(C.Id("local:" .. name), name, ty, B.BindingRoleLocalValue)
  values[#values+1] = B.ValueEntry(name, b)
  local facts = self.facts or Tr.RegionFactProjection(Tr.RegionDefinitionProjection({}), Tr.RegionProtocolProjection({}), Tr.RegionSealProjection({}), Tr.RegionBundleProjection({}))
  return LCheck.TypeValueScope(self.module_name or "", values, self.types or {}, self.layouts or {},
    self.facts or LCheck.TypeModuleFacts({}, {}, {}, facts))
end

function LCheck.TypeValueScope:typecheck_tree_add_type(name, ty)
  local types = {}
  for _, e in ipairs(self.types or {}) do types[#types+1] = e end
  types[#types+1] = B.TypeEntry(name, ty)
  local facts = self.facts or Tr.RegionFactProjection(Tr.RegionDefinitionProjection({}), Tr.RegionProtocolProjection({}), Tr.RegionSealProjection({}), Tr.RegionBundleProjection({}))
  return LCheck.TypeValueScope(self.module_name or "", self.values or {}, types, self.layouts or {},
    self.facts or LCheck.TypeModuleFacts({}, {}, {}, facts))
end

function LCheck.TypeValueScope:typecheck_tree_add_type(name, ty) return self end

-- Variant source-arm resolution: the union payload lookup leaves own the
-- typed bind decision for each `case variant Name(binds...)` arm.
local function typecheck_source_variant_arm(lookup, source_arm, input, expected_binds, typed_binds)
  local issues = {}
  if #(source_arm.binds or {}) ~= expected_binds then
    issues[#issues + 1] = LCheck.TypeIssueVariantBindCount(
      lookup.def.type_name, source_arm.variant_name, expected_binds, #(source_arm.binds or {}))
  end
  local scope = input.scope
  for j = 1, #(typed_binds or {}) do
    local bnd = typed_binds[j]
    -- Match the code phase's variant_binding id so the arm body refs
    -- (ValueRefBinding) resolve to the bound payload in tree_code.
    scope = scope:typecheck_tree_add_value(bnd.name, bnd.ty,
      B.Binding(C.Id("variant:stmt_switch_" .. source_arm.variant_name .. "_" .. bnd.name), bnd.name, bnd.ty, B.BindingRoleLocalValue))
  end
  local arm_input = LCheck.TypeStmtInput(scope, input.return_ty, input.yield)
  local arm_body = arm_input:typecheck_tree_stmt_body(source_arm.body or {})
  if arm_body.issues then for _, iss in ipairs(arm_body.issues) do issues[#issues + 1] = iss end end
  return LCheck.TypeVariantArmResult(
    Tr.SwitchVariantStmtArm(source_arm.variant_name, typed_binds, arm_body.stmts), issues)
end

function LCheck.TypeVariantPayloadNone:typecheck_tree_source_variant_arm(lookup, source_arm, input)
  return typecheck_source_variant_arm(lookup, source_arm, input, 0, {})
end
function LCheck.TypeVariantPayloadFound:typecheck_tree_source_variant_arm(lookup, source_arm, input)
  local binds = {}
  if #(source_arm.binds or {}) >= 1 then binds[1] = Tr.VariantBind(source_arm.binds[1].name, self.ty) end
  return typecheck_source_variant_arm(lookup, source_arm, input, 1, binds)
end
function LCheck.TypeVariantPayloadUnsupported:typecheck_tree_source_variant_arm(lookup, source_arm, input)
  local issues = { LCheck.TypeIssueVariantPayloadUnsupported(lookup.def.type_name, source_arm.variant_name, self.field_count) }
  local arm_result = typecheck_source_variant_arm(lookup, source_arm, input, #(source_arm.binds or {}), {})
  for _, iss in ipairs(arm_result.issues or {}) do issues[#issues + 1] = iss end
  return LCheck.TypeVariantArmResult(arm_result.arm, issues)
end
function LCheck.TypeVariantCaseLookupFound:typecheck_tree_source_variant_arm(source_arm, input)
  return self.case:typecheck_tree_payload_lookup():typecheck_tree_source_variant_arm(self, source_arm, input)
end
function LCheck.TypeVariantCaseLookupMissing:typecheck_tree_source_variant_arm(source_arm, input)
  local issues = { LCheck.TypeIssueUnknownVariant(self.type_name, source_arm.variant_name) }
  if #(source_arm.binds or {}) ~= 0 then
    issues[#issues + 1] = LCheck.TypeIssueVariantBindCount(self.type_name, source_arm.variant_name, 0, #(source_arm.binds or {}))
  end
  local arm_input = LCheck.TypeStmtInput(input.scope, input.return_ty, input.yield)
  local arm_body = arm_input:typecheck_tree_stmt_body(source_arm.body or {})
  if arm_body.issues then for _, iss in ipairs(arm_body.issues) do issues[#issues + 1] = iss end end
  return LCheck.TypeVariantArmResult(Tr.SwitchVariantStmtArm(source_arm.variant_name, {}, arm_body.stmts), issues)
end

-- Type-name leaf projection for variant lookup: every TypeRef projects to
-- its last path segment; the lookup leaves own the found/missing decision
-- (no nil means unnamed).
function Ty.TypeRef:tree_check_type_ref_leaf_lookup()
  return LCheck.TypeRefLeafMissing(self)
end
function Ty.TypeRefGlobal:tree_check_type_ref_leaf_lookup()
  return LCheck.TypeRefLeafFound(self.type_name)
end
function Ty.TypeRefPath:tree_check_type_ref_leaf_lookup()
  local parts = self.path.parts or {}
  if #parts == 0 then return LCheck.TypeRefLeafMissing(self) end
  return LCheck.TypeRefLeafFound(parts[#parts].text)
end
function Ty.TypeRefLocal:tree_check_type_ref_leaf_lookup()
  return LCheck.TypeRefLeafFound(self.sym.name)
end

function Ty.Type:tree_check_lookup_variant(facts)
  return LCheck.TypeVariantDefLookupMissing("<non-variant>", self)
end
function Ty.TNamed:tree_check_lookup_variant(facts)
  return self.ref:tree_check_type_ref_leaf_lookup():tree_check_variant_lookup_in(facts, self)
end
function LCheck.TypeRefLeafFound:tree_check_variant_lookup_in(facts, ty)
  return facts:typecheck_tree_lookup_variant_name(self.name)
end
function LCheck.TypeRefLeafMissing:tree_check_variant_lookup_in(facts, ty)
  return LCheck.TypeVariantDefLookupMissing("<unnamed>", ty)
end
