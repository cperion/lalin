-- impl/tree_check/scope.lua
-- Type scope management leaf methods.

require("lalin.schema_v2")
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
  local b = binding or B.Binding(nil, name, ty, B.BindingRoleLocalValue)
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
