-- lalin.syntax.type

local Ast = require("lalin.syntax.ast")

local Type = {}

local function parse_host_eval(lex, ctx, role)
  local raw, open, close = lex:consume_balanced_from_open("[", "]")
  local refs = Ast.extract_refs(raw)
  Ast.add_refs(ctx, refs)
  return Ast.host_eval(raw, refs, Ast.origin(lex, open, close, "parsed:host_eval"), role)
end

function Type.parse(lex, ctx)
  local start = lex:peek()
  if start.value == "[" then
    return parse_host_eval(lex, ctx, "type")
  end
  lex:error_at(start, "type positions evaluate Lua type values with `[ ... ]`")
end

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
  return Ast.node("Field", { name = name, type = ty, anonymous = anonymous }, Ast.origin(lex, t, lex.last, "parsed:field"))
end

function Type.parse_anonymous_field(lex, ctx)
  local start = lex:peek()
  return Ast.node("Field", { name = "", type = Type.parse(lex, ctx), anonymous = true }, Ast.origin(lex, start, lex.last, "parsed:field"))
end

function Type.parse_product_splice(lex, ctx)
  return parse_host_eval(lex, ctx, "product")
end

function Type.parse_params(lex, ctx)
  local params = {}
  lex:expect("(")
  if not lex:next_if(")") then
    repeat
      if lex:peek().value == "[" then
        params[#params + 1] = Type.parse_product_splice(lex, ctx)
      else
        params[#params + 1] = Type.parse_field(lex, ctx)
      end
    until not lex:next_if(",")
    lex:expect(")")
  end
  return params
end

function Type.parse_field_block(lex, ctx, stop_value)
  local fields = {}
  while not lex:at_eof() and lex:peek().value ~= (stop_value or "end") do
    if lex:peek().value == "[" then
      fields[#fields + 1] = Type.parse_product_splice(lex, ctx)
    else
      fields[#fields + 1] = Type.parse_field(lex, ctx)
    end
    lex:skip_separators()
  end
  return fields
end

return Type
