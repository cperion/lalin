-- lalin.syntax_v2.type
-- Every type-position `[]` is an LLBL parsed HostEval. The evaluated Lua value
-- is adapted into the active schema-v2 type vocabulary before it enters Parsed ASDL.

local Ast = require("lalin.syntax_v2.ast")
local llbl = require("llbl")

-- Load schema_v2 parse types
require("lalin.schema_v2")
local P = package.loaded["lalin.schema_v2.parse"]
local Ty = package.loaded["lalin.schema_v2.type"]
local C = package.loaded["lalin.schema_v2.core"]

local Type = {}
function Type.void() return Ty.TScalar(C.ScalarVoid) end

function Ty.Type:parsed_host_type_value() return self end

local function type_constructor(project)
  return setmetatable({}, {
    __index = function(_, value) return project(value:parsed_host_type_value()) end,
  })
end
function Type.extend_host_env(env)
  local scalars = {
    i8=C.ScalarI8, i16=C.ScalarI16, i32=C.ScalarI32, i64=C.ScalarI64,
    u8=C.ScalarU8, u16=C.ScalarU16, u32=C.ScalarU32, u64=C.ScalarU64,
    f32=C.ScalarF32, f64=C.ScalarF64, bool=C.ScalarBool,
    void=C.ScalarVoid, rawptr=C.ScalarRawPtr, index=C.ScalarIndex,
  }
  for name, scalar in pairs(scalars) do env[name] = Ty.TScalar(scalar) end
  env.ptr = type_constructor(function(ty) return Ty.TPtr(ty) end)
  env.view = type_constructor(function(ty) return Ty.TView(ty) end)
  env.slice = type_constructor(function(ty) return Ty.TSlice(ty) end)
  env.owned = type_constructor(function(ty) return Ty.TOwned(ty) end)
  env.array = type_constructor(function(ty)
    return setmetatable({}, { __index = function(_, count)
      return Ty.TArray(Ty.ArrayLenConst(tonumber(count)), ty)
    end })
  end)
  env.readonly = type_constructor(function(ty) return Ty.TAccess(Ty.TypeAccessReadonly, ty) end)
  env.writeonly = type_constructor(function(ty) return Ty.TAccess(Ty.TypeAccessWriteonly, ty) end)
  env.noalias = type_constructor(function(ty) return Ty.TAccess(Ty.TypeAccessNoAlias, ty) end)
  env.noescape = type_constructor(function(ty) return Ty.TAccess(Ty.TypeAccessNoEscape, ty) end)
  env.invalidate = type_constructor(function(ty) return Ty.TAccess(Ty.TypeAccessInvalidate, ty) end)
  env.preserve = type_constructor(function(ty) return Ty.TAccess(Ty.TypeAccessPreserve, ty) end)
  env.named = function(name)
    return Ty.TNamed(Ty.TypeRefPath(C.Path({ C.Name(tostring(name)) })))
  end
  env.lease = function(name, ty)
    return Ty.TLease(ty:parsed_host_type_value(), Ty.LeaseOriginParam(tostring(name)))
  end
  return env
end

local function adapt_host_type(value, event, lex, start)
  if type(value) == "table" and type(value.parsed_host_type_value) == "function" then
    return value:parsed_host_type_value()
  end
  lex:error_at(start, "host evaluation for type role produced unsupported value `"
    .. tostring(value) .. "` from " .. tostring(event.source))
end

function Type.parse(lex, ctx)
  local start = lex:peek()
  if start.value == "[" then
    local raw, open, close = Ast.consume_balanced_from_open(lex)
    local refs = Ast.extract_refs(raw)
    Ast.add_refs(ctx, refs)
    local event = Ast.host_eval(raw, refs,
      Ast.origin(lex, open, close, "parsed:host_eval"), "type")
    return adapt_host_type(llbl.host_eval.value(event, { env = ctx.host_env }),
      event, lex, start)
  end
  lex:error_at(start, "type positions evaluate Lua type values with `[ ... ]`")
end

--- Parse a named field `name [type]` or `_ [type]` (anonymous).
--- Returns a ParsedField carrying the evaluated type value.
function Type.parse_field(lex, ctx)
  local t = lex:peek()
  local name, anonymous
  if t.kind == "name" and t.value == "_" then
    lex:next()
    name = "_"
    anonymous = true
  else
    local start = lex:expect_name("field name")
    name = start.value
    anonymous = false
  end
  local ty = Type.parse(lex, ctx)
  return P.ParsedField(name, ty, anonymous, false)
end

--- Parse an anonymous field `[type]` (no name).
function Type.parse_anonymous_field(lex, ctx)
  local ty = Type.parse(lex, ctx)
  return P.ParsedField("", ty, true, false)
end

function P.ParsedField:parsed_host_product_item() return self end
function Type.parse_product_splice(lex, ctx)
  local start = lex:peek()
  local raw, open, close = Ast.consume_balanced_from_open(lex)
  local refs = Ast.extract_refs(raw)
  Ast.add_refs(ctx, refs)
  local event = Ast.host_eval(raw, refs,
    Ast.origin(lex, open, close, "parsed:host_eval"), "product")
  local value = llbl.host_eval.value(event, { env = ctx.host_env })
  local items = {}
  if type(value) == "table" and type(value.parsed_host_product_item) == "function" then
    items[1] = value:parsed_host_product_item()
    return items
  end
  if type(value) == "table" then
    for i = 1, #value do
      local item = value[i]
      if type(item) ~= "table" or type(item.parsed_host_product_item) ~= "function" then
        lex:error_at(start, "host evaluation for product role produced unsupported item `"
          .. tostring(item) .. "`")
      end
      items[i] = item:parsed_host_product_item()
    end
    return items
  end
  lex:error_at(start, "host evaluation for product role produced unsupported value `"
    .. tostring(value) .. "`")
end

--- Parse a parameter list `(name [type], name2 [type2], ..., [splice])`
--- Returns array of ParsedField + optional HostEval entries for splices.
function Type.parse_params(lex, ctx)
  local params = {}
  lex:expect("(")
  if not lex:next_if(")") then
    repeat
      if lex:peek().value == "[" then
        local spliced = Type.parse_product_splice(lex, ctx)
        for i = 1, #spliced do params[#params + 1] = spliced[i] end
      else
        params[#params + 1] = Type.parse_field(lex, ctx)
      end
    until not lex:next_if(",")
    lex:expect(")")
  end
  return params
end

--- Parse a field block (struct/union body fields) until stop_value or "end".
function Type.parse_field_block(lex, ctx, stop_value)
  local fields = {}
  while not lex:at_eof() and lex:peek().value ~= (stop_value or "end") do
    if lex:peek().value == "[" then
      local spliced = Type.parse_product_splice(lex, ctx)
      for i = 1, #spliced do fields[#fields + 1] = spliced[i] end
    else
      fields[#fields + 1] = Type.parse_field(lex, ctx)
    end
    lex:skip_separators()
  end
  return fields
end

return Type
