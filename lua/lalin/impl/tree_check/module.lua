-- impl/tree_check/module.lua
-- Module environment construction: type canonicalization, layouts, value/type entries.
-- Ported from tree_module_type.lua.

require("lalin.schema_v2")
local C   = require("lalin.schema_v2.core")
local Ty  = require("lalin.schema_v2.type")
local B   = require("lalin.schema_v2.bind")
local Sem = require("lalin.schema_v2.sem")
local Tr  = require("lalin.schema_v2.tree")
local asdl = require("lalin.asdl")
local TypeSizeAlign = require("lalin.type_size_align")
local layout_api = TypeSizeAlign(require("lalin.schema_v2"))
-- Leaf methods for classof-free pattern matching
function Ty.TypeRef:is_type_ref_path() return false end
function Ty.TypeRefPath:is_type_ref_path() return true end

function Ty.TypeMemLayoutResult:is_layout_known() return false end
function Ty.TypeMemLayoutKnown:is_layout_known() return true end


function B.ValueEntry:is_value_entry() return true end
function B.TypeEntry:is_type_entry() return true end

local function is_value_entry(x) return type(x) == 'table' and x.is_value_entry and x:is_value_entry() end
local function is_type_entry(x) return type(x) == 'table' and x.is_type_entry and x:is_type_entry() end

local function path_type_name(path)
  if not path or not path.parts or #path.parts == 0 then return nil end
  return path.parts[1].text or path.parts[1].name
end

-- Module header name
function Tr.ModuleHeader:tree_module_name() return "" end
function Tr.ModuleSurface:tree_module_name() return "" end
function Tr.ModuleTyped:tree_module_name() return self.module_name end
function Tr.ModuleSem:tree_module_name() return self.module_name end
function Tr.ModuleCode:tree_module_name() return self.module_name end

function Tr.Module:tree_code_module_name() return self.h:tree_module_name() end

-- Type canonicalization
function Ty.Type:tree_module_canonicalize(mod_name) return self end
function Ty.TNamed:tree_module_canonicalize(mod_name)
  if self.ref:is_type_ref_path() then
    local name = path_type_name(self.ref.path)
    if name ~= nil then return Ty.TNamed(Ty.TypeRefGlobal(mod_name, name)) end
  end
  return self
end
function Ty.THandle:tree_module_canonicalize(mod_name)
  if self.ref:is_type_ref_path() then
    local name = path_type_name(self.ref.path)
    if name ~= nil then return Ty.THandle(Ty.TypeRefGlobal(mod_name, name), self.repr) end
  end
  return self
end
function Ty.TPtr:tree_module_canonicalize(mod_name)
  return Ty.TPtr(self.elem:tree_module_canonicalize(mod_name))
end
function Ty.TArray:tree_module_canonicalize(mod_name)
  return Ty.TArray(self.count, self.elem:tree_module_canonicalize(mod_name))
end
function Ty.TSlice:tree_module_canonicalize(mod_name)
  return Ty.TSlice(self.elem:tree_module_canonicalize(mod_name))
end
function Ty.TView:tree_module_canonicalize(mod_name)
  return Ty.TView(self.elem:tree_module_canonicalize(mod_name))
end
function Ty.TLease:tree_module_canonicalize(mod_name)
  return Ty.TLease(self.base:tree_module_canonicalize(mod_name), self.origin)
end
function Ty.TOwned:tree_module_canonicalize(mod_name)
  return Ty.TOwned(self.base:tree_module_canonicalize(mod_name))
end
function Ty.TAccess:tree_module_canonicalize(mod_name)
  return Ty.TAccess(self.access, self.base:tree_module_canonicalize(mod_name))
end
function Ty.TFunc:tree_module_canonicalize(mod_name)
  local params = {}
  for i = 1, #(self.params or {}) do params[i] = self.params[i]:tree_module_canonicalize(mod_name) end
  return Ty.TFunc(params, self.result:tree_module_canonicalize(mod_name))
end
function Ty.TClosure:tree_module_canonicalize(mod_name)
  local params = {}
  for i = 1, #(self.params or {}) do params[i] = self.params[i]:tree_module_canonicalize(mod_name) end
  return Ty.TClosure(params, self.result:tree_module_canonicalize(mod_name))
end

local function params_type(params, result, mod_name)
  local tys = {}
  for i = 1, #params do tys[#tys+1] = params[i].ty:tree_module_canonicalize(mod_name or "") end
  return Ty.TFunc(tys, result:tree_module_canonicalize(mod_name or ""))
end

-- Func/Extern/Const/Static entries
function Tr.Func:tree_module_func_entry(input) return {} end
function Tr.FuncLocal:tree_module_func_entry(input)
  local ty = params_type(self.params, self.result, input.mod_name)
  return {B.ValueEntry(self.name, B.Binding(C.Id("func_"..input.mod_name.."_"..self.name), self.name, ty, B.BindingRoleGlobalFunc(input.mod_name, self.name)))}
end
function Tr.FuncExport:tree_module_func_entry(input)
  local ty = params_type(self.params, self.result, input.mod_name)
  return {B.ValueEntry(self.name, B.Binding(C.Id("func_"..input.mod_name.."_"..self.name), self.name, ty, B.BindingRoleGlobalFunc(input.mod_name, self.name)))}
end
function Tr.FuncLocalContract:tree_module_func_entry(input)
  local ty = params_type(self.params, self.result, input.mod_name)
  return {B.ValueEntry(self.name, B.Binding(C.Id("func_"..input.mod_name.."_"..self.name), self.name, ty, B.BindingRoleGlobalFunc(input.mod_name, self.name)))}
end
function Tr.FuncExportContract:tree_module_func_entry(input)
  local ty = params_type(self.params, self.result, input.mod_name)
  return {B.ValueEntry(self.name, B.Binding(C.Id("func_"..input.mod_name.."_"..self.name), self.name, ty, B.BindingRoleGlobalFunc(input.mod_name, self.name)))}
end
function Tr.ExternFunc:tree_module_extern_entry()
  return {B.ValueEntry(self.name, B.Binding(C.Id("extern_"..self.name), self.name, params_type(self.params, self.result, ""), B.BindingRoleExtern(self.symbol)))}
end
function Tr.ConstItem:tree_module_const_entry(input)
  return {B.ValueEntry(self.name, B.Binding(C.Id("const_"..input.mod_name.."_"..self.name), self.name, self.ty, B.BindingRoleGlobalConst(input.mod_name, self.name)))}
end
function Tr.StaticItem:tree_module_static_entry(input)
  return {B.ValueEntry(self.name, B.Binding(C.Id("static_"..input.mod_name.."_"..self.name), self.name, self.ty, B.BindingRoleGlobalStatic(input.mod_name, self.name)))}
end

-- Type entries
function Tr.TypeDecl:tree_module_type_entry(input) return {} end
function Tr.TypeDeclStruct:tree_module_type_entry(input)
  return {B.TypeEntry(self.name, Ty.TNamed(Ty.TypeRefGlobal(input.mod_name, self.name)))}
end
function Tr.TypeDeclUnion:tree_module_type_entry(input)
  return {B.TypeEntry(self.name, Ty.TNamed(Ty.TypeRefGlobal(input.mod_name, self.name)))}
end
function Tr.TypeDeclEnumSugar:tree_module_type_entry(input)
  return {B.TypeEntry(self.name, Ty.TNamed(Ty.TypeRefGlobal(input.mod_name, self.name)))}
end
function Tr.TypeDeclTaggedUnionSugar:tree_module_type_entry(input)
  return {B.TypeEntry(self.name, Ty.TNamed(Ty.TypeRefGlobal(input.mod_name, self.name)))}
end
function Tr.TypeDeclHandle:tree_module_type_entry(input)
  return {B.TypeEntry(self.name, Ty.THandle(Ty.TypeRefGlobal(input.mod_name, self.name), self.repr))}
end

-- Layout computation
local function align_up(x, a)
  if a <= 1 then return x end
  return math.floor((x + a - 1) / a) * a
end

local function field_layout(fields, env, is_union, target)
  local out, offset, max_size, max_align = {}, 0, 0, 1
  for i = 1, #fields do
    local r = layout_api.result(fields[i].ty, env, target)
    local size, align = 0, 1
    if r:is_layout_known() then size, align = r.layout.size, r.layout.align end
    if is_union then
      out[#out+1] = Sem.FieldLayout(fields[i].field_name, 0, fields[i].ty)
      if size > max_size then max_size = size end; if align > max_align then max_align = align end
    else
      offset = align_up(offset, align)
      out[#out+1] = Sem.FieldLayout(fields[i].field_name, offset, fields[i].ty)
      offset = offset + size; if align > max_align then max_align = align end
    end
  end
  local size = is_union and max_size or offset
  return out, align_up(size, max_align), max_align
end

function Tr.Item:tree_module_item_layout(input) return {} end
function Tr.ItemType:tree_module_item_layout(input) return self.t:tree_module_type_layout(input) end
function Tr.TypeDecl:tree_module_type_layout(input) return {} end
function Tr.TypeDeclStruct:tree_module_type_layout(input)
  local fields, size, align = field_layout(self.fields, input.env, false, input.target)
  return {Sem.LayoutNamed(input.mod_name, self.name, fields, size, align)}
end
function Tr.TypeDeclUnion:tree_module_type_layout(input)
  local fields, size, align = field_layout(self.fields, input.env, true, input.target)
  return {Sem.LayoutNamed(input.mod_name, self.name, fields, size, align)}
end
function Tr.TypeDeclEnumSugar:tree_module_type_layout(input)
  local tag_ty = Ty.TScalar(C.ScalarU32)
  local tl = layout_api.result(tag_ty, input.env, input.target).layout
  return {Sem.LayoutNamed(input.mod_name, self.name, {Sem.FieldLayout("__tag", 0, tag_ty)}, tl.size, tl.align)}
end
function Tr.TypeDeclHandle:tree_module_type_layout(input)
  local rt = Ty.THandle(Ty.TypeRefGlobal(input.mod_name, self.name), self.repr)
  local layout = layout_api.result(rt, input.env, input.target).layout
  return {Sem.LayoutNamed(input.mod_name, self.name, {Sem.FieldLayout("__handle", 0, rt)}, layout.size, layout.align)}
end
function Tr.TypeDeclTaggedUnionSugar:tree_module_type_layout(input)
  local tag_ty = Ty.TScalar(C.ScalarU32)
  local tl = layout_api.result(tag_ty, input.env, input.target).layout
  local payload_size, payload_align = 0, 1
  for i = 1, #self.variants do
    local v = self.variants[i]
    local sz, al
    if #(v.fields or {}) > 0 then
      local _, fsz, fal = field_layout(v.fields, input.env, false, input.target)
      sz, al = fsz, fal
    else
      local r = layout_api.result(v.payload, input.env, input.target)
      local l = r:is_layout_known() and r.layout or Sem.MemLayout(0, 1)
      sz, al = l.size, l.align
    end
    if sz > payload_size then payload_size = sz end; if al > payload_align then payload_align = al end
  end
  local fields = {Sem.FieldLayout("__tag", 0, tag_ty)}
  local size, align = tl.size, tl.align
  if payload_size > 0 then
    local po = align_up(tl.size, payload_align)
    fields[#fields+1] = Sem.FieldLayout("__payload", po, Ty.TArray(Ty.ArrayLenConst(payload_size), Ty.TScalar(C.ScalarU8)))
    size = po + payload_size; if payload_align > align then align = payload_align end
  end
  return {Sem.LayoutNamed(input.mod_name, self.name, fields, align_up(size, align), align)}
end

-- Item env entries
function Tr.Item:tree_module_item_env_entries(input) return {} end
function Tr.ItemFunc:tree_module_item_env_entries(input) return self.func:tree_module_func_entry(input) end
function Tr.ItemExtern:tree_module_item_env_entries(input) return self.func:tree_module_extern_entry() end
function Tr.ItemConst:tree_module_item_env_entries(input) return self.c:tree_module_const_entry(input) end
function Tr.ItemStatic:tree_module_item_env_entries(input) return self.s:tree_module_static_entry(input) end
function Tr.ItemType:tree_module_item_env_entries(input) return self.t:tree_module_type_entry(input) end
function Tr.ItemImport:tree_module_item_env_entries(input) return {} end
function Tr.ItemRegion:tree_module_item_env_entries(input) return {} end
function Tr.ItemData:tree_module_item_env_entries(input) return {} end

-- Module env construction
function Tr.Module:tree_module_env(target)
  local mod_name = self.h:tree_module_name()
  local values, types, layouts = {}, {}, {}
  for i = 1, #self.items do
    local entries = self.items[i]:tree_module_item_env_entries(Sem.TreeModuleEntryInput(mod_name))
    for j = 1, #entries do
      if is_value_entry(entries[j]) then values[#values+1] = entries[j] end
      if is_type_entry(entries[j]) then types[#types+1] = entries[j] end
    end
  end
  for _ = 1, math.max(1, #self.items) do
    local pass_layouts = {}
    local layout_env = Sem.LayoutEnv(layouts)
    for i = 1, #self.items do
      local ls = self.items[i]:tree_module_item_layout(Sem.TreeModuleLayoutInput(mod_name, layout_env, target))
      for j = 1, #ls do pass_layouts[#pass_layouts+1] = ls[j] end
    end
    layouts = pass_layouts
  end
  return {B.Env(mod_name, values, types, layouts)}
end

-- Pipeline entry point: typecheck the module.
-- Traverses items, builds scopes, resolves ValueRefName -> ValueRefBinding,
-- and returns a new Module with ModuleTyped header containing typechecked items.
function Tr.Module:typecheck(input)
  local LCheck = require("lalin.schema_v2.check")
  local mod_name = self.h:tree_module_name()

  -- Build module-level scope from items (funcs, externs, consts, types)
  local values, types = {}, {}
  for i = 1, #self.items do
    local item = self.items[i]
    local item_class = asdl.classof(item)
    if item_class == Tr.ItemFunc then
      local func = item.func
      local ty = params_type(func.params, func.result, mod_name)
      local binding = B.Binding(C.Id("func_"..mod_name.."_"..func.name), func.name, ty,
        B.BindingRoleGlobalFunc(mod_name, func.name))
      values[#values+1] = B.ValueEntry(func.name, binding)
    elseif item_class == Tr.ItemExtern then
      local f = item.func
      values[#values+1] = B.ValueEntry(f.name,
        B.Binding(C.Id("extern_"..f.name), f.name, params_type(f.params, f.result, ""),
          B.BindingRoleExtern(f.symbol)))
    elseif item_class == Tr.ItemConst then
      local c = item.c
      values[#values+1] = B.ValueEntry(c.name,
        B.Binding(C.Id("const_"..mod_name.."_"..c.name), c.name, c.ty,
          B.BindingRoleGlobalConst(mod_name, c.name)))
    elseif item_class == Tr.ItemStatic then
      local s = item.s
      values[#values+1] = B.ValueEntry(s.name,
        B.Binding(C.Id("static_"..mod_name.."_"..s.name), s.name, s.ty,
          B.BindingRoleGlobalStatic(mod_name, s.name)))
    elseif item_class == Tr.ItemType then
      local t = item.t
      if t.name then
        types[#types+1] = B.TypeEntry(t.name, Ty.TNamed(Ty.TypeRefGlobal(mod_name, t.name)))
      end
    end
  end

  local module_scope = LCheck.TypeValueScope(mod_name, values, types, {},
    LCheck.TypeModuleFacts({}, {}, {}, {}, {}, {}, {}))

  -- Typecheck each item (inline, no helper functions)
  local checked_items = {}
  for i = 1, #self.items do
    local item = self.items[i]
    local item_class = asdl.classof(item)
    if item_class == Tr.ItemFunc then
      -- Typecheck a function item
      local func = item.func
      local func_class = asdl.classof(func)

      if func_class == Tr.FuncDecl then
        -- Declarations have no body, pass through
        checked_items[i] = item
      else
        -- Build local scope with params
        local scope = module_scope
        for j = 1, #(func.params or {}) do
          local p = func.params[j]
          local binding = B.Binding(C.Id("arg_" .. func.name .. "_" .. p.name), p.name, p.ty, B.BindingRoleArg(j - 1))
          scope = scope:typecheck_tree_add_value(p.name, p.ty, binding)
        end

        -- Typecheck body (inline loop)
        local stmt_input = LCheck.TypeStmtInput(scope, func.result, LCheck.TypeYieldNone)
        local cur_input = stmt_input
        local new_stmts = {}
        for bi = 1, #(func.body or {}) do
          local stmt = func.body[bi]
          local tc_result = stmt:typecheck_tree_stmt(cur_input)
          if tc_result.state ~= nil then
            cur_input = tc_result.state
          end
          if tc_result.stmts then
            for _, s in ipairs(tc_result.stmts) do
              new_stmts[#new_stmts+1] = s
            end
          end
        end

        -- Build new function
        local new_func
        if func_class == Tr.FuncExport then
          new_func = Tr.FuncExport(func.name, func.params, func.result, new_stmts)
        elseif func_class == Tr.FuncLocalContract then
          new_func = Tr.FuncLocalContract(func.name, func.params, func.result, func.contracts or {}, new_stmts)
        elseif func_class == Tr.FuncExportContract then
          new_func = Tr.FuncExportContract(func.name, func.params, func.result, func.contracts or {}, new_stmts)
        else
          new_func = Tr.FuncLocal(func.name, func.params, func.result, new_stmts)
        end
        checked_items[i] = Tr.ItemFunc(new_func)
      end
    elseif item_class == Tr.ItemConst then
      -- Typecheck const initializer
      local c = item.c
      local expr_input = LCheck.TypeExprInput(module_scope)
      local er = c.value:typecheck_tree_expr(expr_input)
      if er.ty ~= nil and er.expr then
        checked_items[i] = Tr.ItemConst(Tr.ConstItem(c.name, c.ty, er.expr))
      else
        checked_items[i] = item
      end
    elseif item_class == Tr.ItemStatic then
      -- Typecheck static initializer
      local s = item.s
      local expr_input = LCheck.TypeExprInput(module_scope)
      local er = s.value:typecheck_tree_expr(expr_input)
      if er.ty ~= nil and er.expr then
        checked_items[i] = Tr.ItemStatic(Tr.StaticItem(s.name, s.ty, er.expr))
      else
        checked_items[i] = item
      end
    else
      checked_items[i] = item
    end
  end

  return Tr.Module(Tr.ModuleTyped(mod_name), checked_items)
end
