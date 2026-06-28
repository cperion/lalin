-- lalin.syntax.type

local Ast = require("lalin.syntax.ast")

local Type = {}

local function parse_name_path(lex)
  local first = lex:expect_name("type name")
  local parts = { first.value }
  while lex:next_if(".") do
    parts[#parts + 1] = lex:expect_name("type path segment").value
  end
  return parts, first, lex.last
end

function Type.parse(lex, ctx)
  local start = lex:peek()
  local parts = parse_name_path(lex)
  local name = table.concat(parts, ".")
  local args = nil
  if lex:next_if("[") then
    args = {}
    if not lex:next_if("]") then
      repeat
        args[#args + 1] = Type.parse(lex, ctx)
      until not lex:next_if(",")
      lex:expect("]")
    end
  end
  return Ast.node(args and "TypeApply" or "TypeName", {
    name = name,
    args = args,
  }, Ast.origin(lex, start, lex.last, "parsed:type"))
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
  lex:expect(":")
  local ty = Type.parse(lex, ctx)
  return Ast.node("Field", { name = name, type = ty, anonymous = anonymous }, Ast.origin(lex, t, lex.last, "parsed:field"))
end

function Type.parse_params(lex, ctx)
  local params = {}
  lex:expect("(")
  if not lex:next_if(")") then
    repeat
      params[#params + 1] = Type.parse_field(lex, ctx)
    until not lex:next_if(",")
    lex:expect(")")
  end
  return params
end

function Type.parse_field_block(lex, ctx, stop_value)
  local fields = {}
  while not lex:at_eof() and lex:peek().value ~= (stop_value or "end") do
    fields[#fields + 1] = Type.parse_field(lex, ctx)
    lex:skip_separators()
  end
  return fields
end

return Type
