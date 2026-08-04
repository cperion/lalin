-- lalin.exotype
--
-- Host-side exotype/property protocol for staged Lalin generation.  Exotypes
-- are Lua/LLBL meta-layer values: property queries synthesize ordinary parsed
-- declarations/fragments/ASDL values before compiled Lalin runs.  They are not
-- runtime dynamic dispatch objects.

local llbl = require("llbl")
local Ast = require("lalin.impl.syntax_ast")

local Exotype = {}

local next_exotype_id = 0
local next_table_id = 0
local table_ids = setmetatable({}, { __mode = "k" })
local active_stack = {}
local active_set = {}

local ExotypeMT = {}
ExotypeMT.__index = ExotypeMT

local function is_name(s)
  return type(s) == "string" and s:match("^[_%a][_%w]*$") ~= nil
end

local function table_id(t)
  local id = table_ids[t]
  if id == nil then
    next_table_id = next_table_id + 1
    id = next_table_id
    table_ids[t] = id
  end
  return id
end

local function arg_key(v)
  local tv = type(v)
  if tv == "nil" or tv == "boolean" or tv == "number" or tv == "string" then
    return tv .. ":" .. tostring(v)
  elseif tv == "table" then
    local exo_id = rawget(v, "__lalin_exotype_id")
    if exo_id ~= nil then return "exotype:" .. tostring(exo_id) end
    if v.tag ~= nil and v.name ~= nil then return "parsed:" .. tostring(v.tag) .. ":" .. tostring(v.name) .. ":" .. tostring(table_id(v)) end
    return "table:" .. tostring(table_id(v))
  end
  return tv .. ":" .. tostring(v)
end

local function query_key(owner, property, args)
  local parts = { tostring(rawget(owner, "__lalin_exotype_id") or table_id(owner)), tostring(property) }
  for i = 1, #(args or {}) do parts[#parts + 1] = arg_key(args[i]) end
  return table.concat(parts, "|")
end

local function trace_with(key)
  local out = {}
  for i, q in ipairs(active_stack) do out[i] = q.label end
  out[#out + 1] = key
  return table.concat(out, " -> ")
end

local function fail(message, owner, property, key, level)
  local labels = {}
  for i, q in ipairs(active_stack) do labels[#labels + 1] = q.label end
  llbl.fail(message, {
    code = "E_LALIN_EXOTYPE_PROPERTY",
    owner = Exotype.typename(owner),
    property = tostring(property),
    query = key,
    active_queries = labels,
  }, (level or 1) + 1)
end

function Exotype.is(v)
  return type(v) == "table" and rawget(v, "__lalin_exotype") == true
end

function Exotype.ensure_owner(value)
  if Exotype.is(value) then return value end
  if type(value) ~= "table" then return nil end
  if value.tag ~= "DeclStruct" and value.tag ~= "DeclUnion" and value.tag ~= "DeclHandle" then return nil end
  next_exotype_id = next_exotype_id + 1
  value.__lalin_exotype = true
  value.__lalin_exotype_id = next_exotype_id
  value.__lalin_decl = value
  value.methods = value.methods or {}
  value.regions = value.regions or {}
  value.handles = value.handles or {}
  value.metamethods = value.metamethods or {}
  value._property_cache = value._property_cache or {}
  if value.tag == "DeclStruct" then value.entries = value.entries or value.fields end
  if getmetatable(value) == nil then setmetatable(value, ExotypeMT) end
  return value
end

function Exotype.typename(owner)
  if type(owner) ~= "table" then return tostring(owner) end
  local raw = rawget(owner, "name") or rawget(owner, "__name")
  if raw ~= nil then return tostring(raw) end
  local mm = rawget(owner, "metamethods")
  local tn = mm and rawget(mm, "__typename")
  if type(tn) == "function" then
    local ok, value = pcall(tn, owner)
    if ok and value ~= nil then return tostring(value) end
  elseif tn ~= nil then
    return tostring(tn)
  end
  return "Exotype" .. tostring(rawget(owner, "__lalin_exotype_id") or table_id(owner))
end

function Exotype.memoize(fn)
  local cache = {}
  return function(...)
    local args = { ... }
    local parts = {}
    for i = 1, #args do parts[i] = arg_key(args[i]) end
    local key = table.concat(parts, "|")
    local value = cache[key]
    if value == nil then
      value = fn(...)
      cache[key] = value
    end
    return value
  end
end

function Exotype.new(name_or_spec, maybe_spec)
  local spec
  if type(name_or_spec) == "table" then
    spec = name_or_spec
  else
    spec = maybe_spec or {}
    spec.name = name_or_spec or spec.name
  end
  next_exotype_id = next_exotype_id + 1
  local owner = {
    __lalin_exotype = true,
    __lalin_exotype_id = next_exotype_id,
    name = spec.name,
    origin = spec.origin,
    entries = spec.entries,
    methods = spec.methods or {},
    regions = spec.regions or {},
    handles = spec.handles or {},
    metamethods = spec.metamethods or {},
    _property_cache = {},
  }
  return setmetatable(owner, ExotypeMT)
end

function Exotype.query(owner, property, ...)
  if not Exotype.is(owner) then
    error("lalin.exotype.query expects an exotype owner", 2)
  end
  local args = { ... }
  local key = query_key(owner, property, args)
  local cache = rawget(owner, "_property_cache")
  if cache[key] ~= nil then return cache[key] end
  if active_set[key] then
    fail("cyclic exotype property query: " .. trace_with(key), owner, property, key, 2)
  end

  local mm = rawget(owner, "metamethods") or {}
  local prop = rawget(mm, property)
  if prop == nil then return nil end

  local label = Exotype.typename(owner) .. "." .. tostring(property)
  active_set[key] = true
  active_stack[#active_stack + 1] = { key = key, label = label }
  local ok, result
  if type(prop) == "function" then
    ok, result = pcall(prop, owner, ...)
  else
    ok, result = true, prop
  end
  active_stack[#active_stack] = nil
  active_set[key] = nil

  if not ok then
    fail("error in exotype property " .. label .. ": " .. tostring(result), owner, property, key, 2)
  end
  if result ~= nil then cache[key] = result end
  return result
end

local function type_value(v)
  if type(v) == "string" then
    return Ast.host_eval(v, Ast.extract_refs(v), nil, "type")
  end
  if llbl.is(v, "HostEval") or (type(v) == "table" and v.tag ~= nil) then return v end
  return llbl.host_eval.lua(v)
end

function Exotype.field(spec)
  if type(spec) == "table" and spec.tag == "Field" then return spec end
  if type(spec) ~= "table" then error("exotype field expects a field table", 2) end
  local name = spec.name or spec.field
  if not is_name(name) then error("exotype field requires an identifier name", 2) end
  local ty = spec.type or spec.ty
  if ty == nil then error("exotype field " .. tostring(name) .. " requires type/ty", 2) end
  return Ast.node("Field", {
    name = name,
    type = type_value(ty),
    anonymous = false,
    exotype = true,
  })
end

function Exotype.fields(entries)
  local out = {}
  for i, entry in ipairs(entries or {}) do out[i] = Exotype.field(entry) end
  return out
end

function Exotype.struct_decl(owner)
  local entries = Exotype.query(owner, "__getentries") or rawget(owner, "entries") or {}
  local name = Exotype.typename(owner)
  if not is_name(name) then error("exotype typename must be an identifier to synthesize a struct: " .. tostring(name), 2) end
  return Ast.node("DeclStruct", {
    name = name,
    fields = Exotype.fields(entries),
    exotype = true,
    __lalin_exotype_owner = owner,
  })
end

local function normalize_decl_result(value, owner, method_name)
  if value == nil then return nil end
  if type(value) == "table" and type(value.tag) == "string" and value.tag:match("^Decl") then
    if method_name ~= nil and value.name == nil then value.name = method_name end
    if method_name ~= nil and value.name == method_name and (value.qualifier == nil or #value.qualifier == 0) then
      value.qualifier = { Exotype.typename(owner) }
    end
    value.exotype = value.exotype or true
    value.__lalin_exotype_owner = value.__lalin_exotype_owner or owner
    return value
  end
  return value
end

function Exotype.getmethod(owner, name, ...)
  if rawget(owner, "methods") and rawget(owner, "methods")[name] ~= nil then
    return normalize_decl_result(rawget(owner, "methods")[name], owner, name)
  end
  local value = Exotype.query(owner, "__getmethod", name, ...)
  if value == nil then value = Exotype.query(owner, "__methodmissing", name, ...) end
  return normalize_decl_result(value, owner, name)
end

function Exotype.getregion(owner, name, ...)
  if rawget(owner, "regions") and rawget(owner, "regions")[name] ~= nil then return rawget(owner, "regions")[name] end
  local value = Exotype.query(owner, "__getregion", name, ...)
  if value == nil then value = Exotype.query(owner, "__regionmissing", name, ...) end
  return normalize_decl_result(value, owner, name)
end

function Exotype.gethandle(owner, name, ...)
  if rawget(owner, "handles") and rawget(owner, "handles")[name] ~= nil then return rawget(owner, "handles")[name] end
  return normalize_decl_result(Exotype.query(owner, "__gethandle", name, ...), owner, name)
end

function Exotype.entry(owner, name, ...)
  local value = Exotype.query(owner, "__getentry", name, ...)
  if value == nil then value = Exotype.query(owner, "__entrymissing", name, ...) end
  return value
end

function Exotype.apply(owner, ...)
  return Exotype.query(owner, "__apply", ...)
end

function Exotype.cast(owner, from_ty, to_ty, expr)
  return Exotype.query(owner, "__cast", from_ty, to_ty, expr)
end

function Exotype.operator(owner, op, ...)
  local property = tostring(op)
  if property:sub(1, 2) ~= "__" then property = "__" .. property end
  return Exotype.query(owner, property, ...)
end

local function sorted_string_keys(t)
  local keys = {}
  for k in pairs(t or {}) do if type(k) == "string" then keys[#keys + 1] = k end end
  table.sort(keys)
  return keys
end

function Exotype.decls(owner, opts)
  opts = opts or {}
  local custom = Exotype.query(owner, "__getdecls", opts)
  if custom ~= nil then return custom end

  local out = {}
  if opts.layout ~= false and rawget(owner, "__lalin_decl") == owner and (owner.tag == "DeclStruct" or owner.tag == "DeclUnion" or owner.tag == "DeclHandle") then
    out[#out + 1] = owner
  elseif opts.layout ~= false and (rawget(owner, "entries") ~= nil or rawget(rawget(owner, "metamethods") or {}, "__getentries") ~= nil) then
    out[#out + 1] = Exotype.struct_decl(owner)
  end
  local method_names = opts.methods or sorted_string_keys(rawget(owner, "methods"))
  for _, name in ipairs(method_names or {}) do
    local d = Exotype.getmethod(owner, name)
    if d ~= nil then out[#out + 1] = d end
  end
  local region_names = opts.regions or sorted_string_keys(rawget(owner, "regions"))
  for _, name in ipairs(region_names or {}) do
    local d = Exotype.getregion(owner, name)
    if d ~= nil then out[#out + 1] = d end
  end
  local handle_names = opts.handles or sorted_string_keys(rawget(owner, "handles"))
  for _, name in ipairs(handle_names or {}) do
    local d = Exotype.gethandle(owner, name)
    if d ~= nil then out[#out + 1] = d end
  end
  return out
end

function ExotypeMT:query(property, ...)
  return Exotype.query(self, property, ...)
end

function ExotypeMT:decls(opts)
  return Exotype.decls(self, opts)
end

function ExotypeMT:struct_decl()
  return Exotype.struct_decl(self)
end

function ExotypeMT:method(name, ...)
  return Exotype.getmethod(self, name, ...)
end

function ExotypeMT:region(name, ...)
  return Exotype.getregion(self, name, ...)
end

function ExotypeMT:handle(name, ...)
  return Exotype.gethandle(self, name, ...)
end

function ExotypeMT:entry(name, ...)
  return Exotype.entry(self, name, ...)
end

function ExotypeMT:apply(...)
  return Exotype.apply(self, ...)
end

function ExotypeMT:cast(from_ty, to_ty, expr)
  return Exotype.cast(self, from_ty, to_ty, expr)
end

function ExotypeMT:operator(op, ...)
  return Exotype.operator(self, op, ...)
end

function ExotypeMT:__tostring()
  return "<lalin.exotype " .. Exotype.typename(self) .. ">"
end

return Exotype
