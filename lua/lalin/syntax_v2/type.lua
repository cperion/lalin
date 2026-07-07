-- lalin.syntax_v2.type
-- Type position parser.  Type annotations like [i32] return the raw source
-- string (e.g. "i32") so that intermediate types can store it without
-- requiring HostEval in ASDL.  Product splices return HostEval for
-- generated field lists.

local Ast = require("lalin.syntax_v2.ast")

-- Load schema_v2 parse types
require("lalin.schema_v2")
local P = package.loaded["lalin.schema_v2.parse"]

local Type = {}

--- Parse a type annotation `[type_expr]` → raw source string (e.g. "i32", "f64")
function Type.parse(lex, ctx)
  local start = lex:peek()
  if start.value == "[" then
    local raw, open, close = Ast.consume_balanced_from_open(lex)
    local refs = Ast.extract_refs(raw)
    Ast.add_refs(ctx, refs)
    return raw  -- source string: "i32", "ptr [i32]", "Point", etc.
  end
  lex:error_at(start, "type positions evaluate Lua type values with `[ ... ]`")
end

--- Parse a named field `name [type]` or `_ [type]` (anonymous).
--- Returns LalinParse.ParsedField{ name, ty_source, anonymous, implicit }
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
  local ty_source = Type.parse(lex, ctx)
  return P.ParsedField(name, ty_source, anonymous, false)
end

--- Parse an anonymous field `[type]` (no name).
function Type.parse_anonymous_field(lex, ctx)
  local ty_source = Type.parse(lex, ctx)
  return P.ParsedField("", ty_source, true, false)
end

--- Parse a host-eval product splice `[lua-expr]` in a field list.
--- Returns HostEval for generated field list evaluation.
function Type.parse_product_splice(lex, ctx)
  local raw, open, close = Ast.consume_balanced_from_open(lex)
  local refs = Ast.extract_refs(raw)
  Ast.add_refs(ctx, refs)
  return Ast.host_eval(raw, refs, Ast.origin(lex, open, close, "parsed:host_eval"), "product")
end

--- Parse a parameter list `(name [type], name2 [type2], ..., [splice])`
--- Returns array of ParsedField + optional HostEval entries for splices.
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

--- Parse a field block (struct/union body fields) until stop_value or "end".
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
