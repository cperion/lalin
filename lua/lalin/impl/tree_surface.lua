-- impl/tree_surface.lua
-- Surface type resolution — replaces local type names with global refs.
-- Ported from surface_resolve.lua.
-- impl/tree_surface.lua
-- Surface type resolution — replaces local type names with global refs.
-- Ported from surface_resolve.lua.

require("lalin.schema_v2")
local Ty   = require("lalin.schema_v2.type")
local Tr   = require("lalin.schema_v2.tree")
local B    = require("lalin.schema_v2.bind")
local Sem  = require("lalin.schema_v2.sem")
local asdl = require("lalin.asdl")
local asdl = require("lalin.asdl")

-- Module-level entry point — pipeline calls tree_module:surface_resolve()
function Tr.Module:surface_resolve()
  local mod_name = self.h and self.h.module_name or "module"
  local items = {}
  for i = 1, #(self.items or {}) do
    local item = self.items[i]
    local item_class = asdl.classof(item)
    if item_class == Tr.ItemFunc then
      items[i] = Tr.ItemFunc(item.func:surface_resolve_item(mod_name))
    elseif item_class == Tr.ItemExtern then
      items[i] = item  -- externs pass through
    elseif item_class == Tr.ItemType then
      items[i] = Tr.ItemType(item.t:tree_surface_resolve(mod_name))
    elseif item_class == Tr.ItemRegion then
      items[i] = item  -- regions pass through
    else
      items[i] = item
    end
  end
  return Tr.Module(self.h, items)
end

function Tr.FuncLocal:surface_resolve_item(mod_name)
  local params = {}
  for i = 1, #(self.params or {}) do
    local p = self.params[i]
    params[i] = Ty.Param(p.name, p.ty:tree_surface_resolve_ty(mod_name), p.attrs)
  end
  local result = self.result and self.result:tree_surface_resolve_ty(mod_name) or nil
  return Tr.FuncLocal(self.name, params, result, self.body, self.attrs)
end

function Tr.FuncExport:surface_resolve_item(mod_name)
  return Tr.FuncLocal:surface_resolve_item(self, mod_name)
end

-- Type resolution methods (below are unchanged)
function Tr.TypeDeclStruct:tree_surface_resolve(mod_name)
  local fields = {}
  for i = 1, #(self.fields or {}) do
    fields[i] = Ty.FieldDecl(self.fields[i].field_name, self.fields[i].ty:tree_surface_resolve_ty(mod_name))
  end
  return Tr.TypeDeclStruct(self.name, fields)
end

function Tr.TypeDeclUnion:tree_surface_resolve(mod_name)
  local fields = {}
  for i = 1, #(self.fields or {}) do
    fields[i] = Ty.FieldDecl(self.fields[i].field_name, self.fields[i].ty:tree_surface_resolve_ty(mod_name))
  end
  return Tr.TypeDeclUnion(self.name, fields)
end

function Tr.TypeDeclTaggedUnionSugar:tree_surface_resolve(mod_name) return self end
function Tr.TypeDeclHandle:tree_surface_resolve(mod_name) return self end

function Ty.Type:tree_surface_resolve_ty(mod_name) return self end
function Ty.TNamed:tree_surface_resolve_ty(mod_name)
  if self.ref:is_type_ref_path() then
    return Ty.TNamed(Ty.TypeRefGlobal(mod_name, self.ref.path.parts[1].text))
  end
  return self
end
function Ty.THandle:tree_surface_resolve_ty(mod_name)
  if self.ref:is_type_ref_path() then
    return Ty.THandle(Ty.TypeRefGlobal(mod_name, self.ref.path.parts[1].text), self.repr)
  end
  return self
end
function Ty.TPtr:tree_surface_resolve_ty(mod_name)
  return Ty.TPtr(self.elem:tree_surface_resolve_ty(mod_name))
end
function Ty.TArray:tree_surface_resolve_ty(mod_name)
  return Ty.TArray(self.count, self.elem:tree_surface_resolve_ty(mod_name))
end
function Ty.TSlice:tree_surface_resolve_ty(mod_name)
  return Ty.TSlice(self.elem:tree_surface_resolve_ty(mod_name))
end
function Ty.TView:tree_surface_resolve_ty(mod_name)
  return Ty.TView(self.elem:tree_surface_resolve_ty(mod_name))
end
function Ty.TLease:tree_surface_resolve_ty(mod_name)
  return Ty.TLease(self.base:tree_surface_resolve_ty(mod_name), self.origin)
end
function Ty.TOwned:tree_surface_resolve_ty(mod_name)
  return Ty.TOwned(self.base:tree_surface_resolve_ty(mod_name))
end
function Ty.TAccess:tree_surface_resolve_ty(mod_name)
  return Ty.TAccess(self.access, self.base:tree_surface_resolve_ty(mod_name))
end
function Ty.TFunc:tree_surface_resolve_ty(mod_name)
  local params = {}
  for i = 1, #(self.params or {}) do params[i] = self.params[i]:tree_surface_resolve_ty(mod_name) end
  return Ty.TFunc(params, self.result:tree_surface_resolve_ty(mod_name))
end
function Ty.TClosure:tree_surface_resolve_ty(mod_name)
  local params = {}
  for i = 1, #(self.params or {}) do params[i] = self.params[i]:tree_surface_resolve_ty(mod_name) end
  return Ty.TClosure(params, self.result:tree_surface_resolve_ty(mod_name))
end
