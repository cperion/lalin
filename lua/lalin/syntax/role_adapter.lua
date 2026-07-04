-- lalin.syntax.role_adapter
-- Role-local adaptation for parsed HostEval values and parsed AST splices.
--
-- This module is deliberately bound to the active ASDL context.  Host Lua values
-- may carry ASDL objects from another context; type values are projected through
-- lalin.syntax.type_value before use.  Recursive lowering is supplied later by
-- the caller with adapter:set_lowering(ToTree) or by passing callbacks.

local llbl = require("llbl")
local asdl = require("lalin.asdl")

local function bind(T, callbacks)
  assert(T and T.LalinCore and T.LalinTree and T.LalinType and T.LalinBind,
    "lalin.syntax.role_adapter(T) expects a projected Lalin schema context")

  local C, Ty, Tr = T.LalinCore, T.LalinType, T.LalinTree
  local TypeValue = require("lalin.syntax.type_value")(T)

  local Adapter = {}
  Adapter.__index = Adapter

  local function origin_of(v)
    if llbl.origin_of then return llbl.origin_of(v) end
    return type(v) == "table" and rawget(v, "origin") or nil
  end

  local function role_error(role, message, value, host)
    llbl.fail(message, {
      code = "E_LALIN_ROLE_ADAPT",
      role = role,
      primary = origin_of(host) or origin_of(value),
      labels = host and value and origin_of(value) and {
        { origin = origin_of(value), message = "host-eval produced this value" },
      } or nil,
    }, 3)
  end

  local function is_parsed_decl(value)
    return type(value) == "table" and type(value.tag) == "string" and value.tag:match("^Decl") ~= nil
  end

  local function sorted_string_keys(t)
    local keys = {}
    for k in pairs(t or {}) do if type(k) == "string" then keys[#keys + 1] = k end end
    table.sort(keys)
    return keys
  end

  local function array_len(t)
    return type(t) == "table" and #t or 0
  end

  local function callback(self, name)
    if self.callbacks and self.callbacks[name] then return self.callbacks[name] end
    if self.lowering and self.lowering[name] then return self.lowering[name] end
    return nil
  end

  function Adapter:set_lowering(lowering)
    self.lowering = lowering
    return self
  end

  function Adapter:set_callbacks(cb)
    self.callbacks = cb or {}
    return self
  end

  function Adapter:value(value, role, ctx)
    local host = nil
    if llbl.is(value, "HostEval") then
      host = value
      value = llbl.host_eval.value(value, ctx or self.ctx)
    elseif type(value) == "table" and value.tag == "HostEscape" then
      host = value
      if not value.resolved then role_error(role or "host", "unresolved legacy host escape", value, host) end
      value = value.value
    end
    return value, host
  end

  function Adapter:handle_repr(ptype)
    if ptype == nil then return Ty.HandleReprScalar(C.ScalarU32) end
    local ty = self:type(ptype)
    if asdl.classof(ty) ~= Ty.TScalar then
      role_error("type", "handle repr must be a scalar type", ty, ptype)
    end
    return Ty.HandleReprScalar(ty.scalar)
  end

  function Adapter:type(value, ctx)
    local host
    value, host = self:value(value, "type", ctx)
    if value == nil then return Ty.TScalar(C.ScalarVoid) end

    local projected = TypeValue.type(value)
    if projected ~= nil then return projected end
    if asdl.classof(value) then return value end

    if type(value) == "table" and value.tag then
      if (value.tag == "DeclStruct" or value.tag == "DeclUnion") and value.name ~= nil then
        return Ty.TNamed(Ty.TypeRefPath(C.Path({ C.Name(value.name) })))
      elseif value.tag == "DeclHandle" and value.name ~= nil then
        return Ty.THandle(Ty.TypeRefPath(C.Path({ C.Name(value.name) })), self:handle_repr(value.repr))
      end
      local lower = callback(self, "parsed_type") or callback(self, "type")
      if lower then return lower(value) end
    end

    role_error("type", "type host-eval produced unsupported value " .. tostring(value), value, host)
  end

  function Adapter:literal(value)
    local lower = callback(self, "literal")
    if lower then return lower(value) end
    if value == nil then return Tr.ExprLit(Tr.ExprSurface, C.LitNil) end
    if type(value) == "number" then
      if value == value and value % 1 == 0 then return Tr.ExprLit(Tr.ExprSurface, C.LitInt(tostring(value))) end
      return Tr.ExprLit(Tr.ExprSurface, C.LitFloat(tostring(value)))
    end
    if type(value) == "boolean" then return Tr.ExprLit(Tr.ExprSurface, C.LitBool(value)) end
    if type(value) == "string" then return Tr.ExprLit(Tr.ExprSurface, C.LitString(value)) end
    role_error("expr", "cannot adapt value to expression literal: " .. tostring(value), value)
  end

  function Adapter:expr(value, ctx)
    local host
    value, host = self:value(value, "expr", ctx)
    if value == nil then return self:literal(nil) end
    if asdl.classof(value) then return value end
    if type(value) == "table" then
      if value.tag == "ExprFragment" then return self:expr(value.expr, ctx) end
      if value.tag then
        local lower = callback(self, "expr")
        if lower then return lower(value) end
      end
    end
    return self:literal(value, host)
  end

  function Adapter:place(value, ctx)
    local host
    value, host = self:value(value, "place", ctx)
    if asdl.classof(value) then return value end
    local lower = callback(self, "place")
    if lower then return lower(value) end
    role_error("place", "cannot adapt value to place: " .. tostring(value), value, host)
  end

  function Adapter:stmt_list(items)
    return { __lalin_role_adapter_stmt_list = true, items = items or {} }
  end

  function Adapter:is_stmt_list(value)
    return type(value) == "table" and value.__lalin_role_adapter_stmt_list == true
  end

  function Adapter:stmt(value, ctx)
    local host
    value, host = self:value(value, "stmt", ctx)
    if value == nil then role_error("stmt", "nil cannot adapt to a statement", value, host) end
    if asdl.classof(value) then return value end
    if llbl.is(value, "Fragment") or (type(value) == "table" and not value.tag and array_len(value) > 0) then
      return self:stmt_list(self:stmts(value, ctx))
    end
    if type(value) == "table" then
      if value.tag == "StmtFragment" then return self:stmt_list(self:stmts(value.body or {}, ctx)) end
      if value.tag then
        local lower = callback(self, "stmt")
        if lower then return lower(value) end
      end
    end
    role_error("stmt", "cannot adapt value to statement: " .. tostring(value), value, host)
  end

  function Adapter:stmts(value, ctx)
    local host
    value, host = self:value(value, "stmts", ctx)
    if value == nil then return {} end
    if llbl.is(value, "Fragment") then value = value.items or {} end
    if type(value) == "table" and value.tag == "StmtFragment" then value = value.body or {} end
    if type(value) == "table" and value.tag then
      local one = self:stmt(value, ctx)
      return self:is_stmt_list(one) and one.items or { one }
    end
    if type(value) ~= "table" then role_error("stmts", "statement list expected table/fragment", value, host) end
    local out = {}
    for i = 1, #value do
      local converted = self:stmt(value[i], ctx)
      if self:is_stmt_list(converted) then
        for _, item in ipairs(converted.items) do out[#out + 1] = item end
      else
        out[#out + 1] = converted
      end
    end
    return out
  end

  function Adapter:decl(value, ctx)
    local host
    value, host = self:value(value, "decl", ctx)
    if is_parsed_decl(value) then return value end
    role_error("decl", "expected parsed declaration, got " .. tostring(value), value, host)
  end

  function Adapter:decls(value, ctx)
    local host
    value, host = self:value(value, "decls", ctx)
    if value == nil then return {} end
    if llbl.is(value, "Fragment") then value = value.items or {} end
    if is_parsed_decl(value) then return { value } end
    if type(value) ~= "table" then role_error("decls", "declaration list expected table/fragment", value, host) end

    local out = {}
    for i = 1, #value do out[#out + 1] = self:decl(value[i], ctx) end
    for _, k in ipairs(sorted_string_keys(value)) do
      local v = value[k]
      if is_parsed_decl(v) then
        if v.name == nil then
          v.public_name = v.public_name or k
          v.debug_name = v.debug_name or k
          v.name = k
        end
        out[#out + 1] = v
      else
        role_error("decls", "keyed declaration entries must be parsed declarations", v, host)
      end
    end
    return out
  end

  local function parsed_item_list(self, value, role, tag_name, ctx)
    local host
    value, host = self:value(value, role, ctx)
    if value == nil then return {} end
    if llbl.is(value, "Fragment") then value = value.items or {} end
    if type(value) == "table" and value.tag == tag_name then return { value } end
    if type(value) ~= "table" then role_error(role, role .. " expected table/fragment", value, host) end
    local out = {}
    for i = 1, #value do
      local item = value[i]
      if llbl.is(item, "HostEval") or llbl.is(item, "Fragment") or (type(item) == "table" and not item.tag and #item > 0) then
        local nested = parsed_item_list(self, item, role, tag_name, ctx)
        for _, n in ipairs(nested) do out[#out + 1] = n end
      elseif type(item) == "table" and item.tag == tag_name then
        out[#out + 1] = item
      else
        role_error(role, "bad " .. role .. " item", item, host)
      end
    end
    return out
  end

  function Adapter:product_fields(value, ctx) return parsed_item_list(self, value, "product", "Field", ctx) end
  function Adapter:variants(value, ctx) return parsed_item_list(self, value, "variants", "Variant", ctx) end
  function Adapter:conts(value, ctx) return parsed_item_list(self, value, "conts", "Exit", ctx) end

  return setmetatable({ callbacks = callbacks or {}, ctx = nil }, Adapter)
end

return bind
