-- lalin.syntax.decl

local Ast = require("lalin.syntax.ast")
local Type = require("lalin.syntax.type")
local Stmt = require("lalin.syntax.stmt")
local Expr = require("lalin.syntax.expr")

local Decl = {}

local function optional_do(lex)
  lex:next_if("do")
end

-- Parse a possibly qualified name: returns name, qualifier
--   name       → name="name", qualifier=nil
--   A.B.name   → name="name", qualifier={"A","B"}
local function parse_qualified_name(lex, label)
  local name = lex:expect_name(label or "name").value
  local qualifier = nil
  if lex:peek().value == "." then
    qualifier = {}
    qualifier[#qualifier + 1] = name
    while lex:peek().value == "." do
      lex:next() -- consume "."
      local part = lex:expect_name(label or "qualified name part").value
      qualifier[#qualifier + 1] = part
    end
    name = table.remove(qualifier) -- last part is the bare name
  end
  return name, qualifier
end

-- Parse a function/region name. In addition to dot-qualified declarations,
-- this accepts Lua-style method definitions:
--   A.B.name   → qualifier={"A","B"}, name="name", implicit_self=false
--   A.B:name   → qualifier={"A","B"}, name="name", implicit_self=true
local function parse_callable_name(lex, label)
  local first = lex:expect_name(label or "name")
  local parts = { first.value }
  while lex:peek().value == "." do
    lex:next()
    parts[#parts + 1] = lex:expect_name(label or "qualified name part").value
  end
  if lex:peek().value == ":" then
    lex:next()
    local method = lex:expect_name(label or "method name").value
    return method, parts, true
  end
  local name = table.remove(parts)
  return name, (#parts > 0 and parts or nil), false
end

local function implicit_self_field(lex, start, qualifier)
  if qualifier == nil or #qualifier == 0 then
    lex:error_at(start, "implicit self method declaration requires an owning struct path")
  end
  local owner = table.concat(qualifier, ".")
  local source = "ptr [" .. owner .. "]"
  local origin = Ast.origin(lex, start, start, "parsed:implicit_self")
  local ty = Ast.host_eval(source, Ast.extract_refs(source), origin, "type")
  return Ast.node("Field", { name = "self", type = ty, anonymous = false, implicit = true }, origin)
end

function Decl.parse_host_eval(lex, ctx, role)
  local raw, open, close = lex:consume_balanced_from_open("[", "]")
  local refs = Ast.extract_refs(raw)
  Ast.add_refs(ctx, refs)
  return Ast.host_eval(raw, refs, Ast.origin(lex, open, close, "parsed:host_eval"), role or (ctx and ctx.expected_role) or "decls")
end

function Decl.parse_decl_stream(lex, ctx)
  return Decl.parse_host_eval(lex, ctx, (ctx and ctx.expected_role) or "decls")
end

function Decl.parse_meta_assign(lex, ctx, entry_start)
  local start = entry_start or lex:peek()
  local lhs = { lex:expect_name("meta assignment target").value }
  while lex:next_if(".") do
    lhs[#lhs + 1] = lex:expect_name("meta assignment target part").value
  end
  if #lhs < 2 then
    lex:error_at(start, "meta assignment target must be a field path such as `Type.metamethods.__methodmissing`")
  end
  lex:expect("=")
  local value
  if lex:peek().value == "[" then
    value = Decl.parse_host_eval(lex, ctx, "meta")
  else
    local first = lex:expect_name("meta assignment value").value
    local path = { first }
    while lex:next_if(".") do
      path[#path + 1] = lex:expect_name("meta assignment value part").value
    end
    value = Ast.node("MetaRef", { path = path }, Ast.origin(lex, start, lex.last, "parsed:meta_ref"))
  end
  return Ast.node("DeclMetaAssign", { target = lhs, value = value }, Ast.origin(lex, start, lex.last, "parsed:meta_assign"))
end

function Decl.parse_fn(lex, ctx, entry_start)
  local start = entry_start or ctx.entry_token
  local name = nil
  local qualifier = nil
  local implicit_self = false
  if lex:peek().kind == "name" and (lex:peek(1).value == "(" or lex:peek(1).value == "." or lex:peek(1).value == ":") then
    name, qualifier, implicit_self = parse_callable_name(lex, "function name")
  end
  if name == nil and lex:peek().value ~= "(" then
    lex:error_at(lex:peek(), "expected function name or parameter list")
  end
  local params = Type.parse_params(lex, ctx)
  if implicit_self then
    if params[1] and params[1].name == "self" then
      lex:error_at(start, "colon method declarations inject `self`; use dot syntax for an explicit receiver type")
    end
    table.insert(params, 1, implicit_self_field(lex, start, qualifier))
  end
  local result = nil
  if lex:peek().value == "[" then result = Type.parse(lex, ctx) end
  optional_do(lex)
  local body = Stmt.parse_block(lex, ctx, { "end" })
  lex:expect("end")
  return Ast.node("DeclFunc", {
    name = name,
    qualifier = qualifier,
    implicit_self = implicit_self,
    params = params,
    result = result,
    body = body,
  }, Ast.origin(lex, start, lex.last, "parsed:decl"))
end

function Decl.parse_struct(lex, ctx, entry_start)
  local start = entry_start or ctx.entry_token
  local name = lex:expect_name("struct name")
  optional_do(lex)
  local fields = Type.parse_field_block(lex, ctx, "end")
  lex:expect("end")
  return Ast.node("DeclStruct", { name = name.value, fields = fields }, Ast.origin(lex, start, lex.last, "parsed:decl"))
end

local function parse_extern_symbol_value(lex)
  local t = lex:peek()
  if t.kind == "string" then
    lex:next()
    local loader = loadstring or load
    local fn, err = loader("return " .. tostring(t.raw or t.value), lex and lex.name or "=(lalin extern symbol)")
    if not fn then lex:error_at(t, "invalid extern symbol string: " .. tostring(err)) end
    local ok, value = pcall(fn)
    if not ok or type(value) ~= "string" then lex:error_at(t, "invalid extern symbol string") end
    return value
  elseif t.kind == "name" then
    lex:next()
    return t.value
  end
  lex:error_at(t, "expected extern symbol string or name")
end

function Decl.parse_extern(lex, ctx, entry_start)
  local start = entry_start or ctx.entry_token
  local name, qualifier = parse_qualified_name(lex, "extern name")
  local params = Type.parse_params(lex, ctx)
  local result = nil
  if lex:peek().value == "[" then result = Type.parse(lex, ctx) end
  local symbol = nil

  optional_do(lex)
  lex:skip_separators()
  while not lex:at_eof() and lex:peek().value ~= "end" do
    local key = lex:expect_name("extern fact").value
    if key == "symbol" then
      lex:next_if("=")
      symbol = parse_extern_symbol_value(lex)
    else
      lex:error_at(lex.last, "expected extern fact `symbol`")
    end
    lex:skip_separators()
  end
  lex:expect("end")
  return Ast.node("DeclExtern", {
    name = name,
    qualifier = qualifier,
    params = params,
    result = result,
    symbol = symbol,
  }, Ast.origin(lex, start, lex.last, "parsed:decl"))
end

function Decl.parse_union(lex, ctx, entry_start)
  local start = entry_start or ctx.entry_token
  local name = lex:expect_name("union name")
  optional_do(lex)
  local variants = {}
  while not lex:at_eof() and lex:peek().value ~= "end" do
    if lex:peek().value == "[" then
      variants[#variants + 1] = Decl.parse_host_eval(lex, ctx, "variants")
    else
      local vstart = lex:expect_name("variant name")
      local fields = {}
      if lex:peek().value == "(" then fields = Type.parse_params(lex, ctx) end
      variants[#variants + 1] = Ast.node("Variant", { name = vstart.value, fields = fields }, Ast.origin(lex, vstart, lex.last or vstart, "parsed:variant"))
    end
    lex:skip_separators()
  end
  lex:expect("end")
  return Ast.node("DeclUnion", { name = name.value, variants = variants }, Ast.origin(lex, start, lex.last, "parsed:decl"))
end

local function parse_handle_type(lex, ctx, label)
  if lex:peek().value ~= "[" then
    lex:error_at(lex:peek(), "expected " .. (label or "handle type") .. " in `[type]` form")
  end
  return Type.parse(lex, ctx)
end

local function parse_handle_invalid(lex)
  local t = lex:peek()
  if t.kind == "number" or t.kind == "string" or t.kind == "name" then
    lex:next()
    return t.raw or t.value
  end
  lex:error_at(t, "expected handle invalid representation")
end

function Decl.parse_handle(lex, ctx, entry_start)
  local start = entry_start or ctx.entry_token
  local name, qualifier = parse_qualified_name(lex, "handle name")
  local repr = nil
  local invalid = nil
  local domain = nil
  local target = nil

  if lex:peek().value == "[" then
    repr = parse_handle_type(lex, ctx, "handle representation")
  end
  if lex:peek().value == "invalid" then
    lex:next()
    lex:next_if("=")
    invalid = parse_handle_invalid(lex)
  end

  optional_do(lex)
  lex:skip_separators()
  while not lex:at_eof() and lex:peek().value ~= "end" do
    local key = lex:expect_name("handle fact").value
    if key == "repr" then
      repr = parse_handle_type(lex, ctx, "handle representation")
    elseif key == "invalid" then
      lex:next_if("=")
      invalid = parse_handle_invalid(lex)
    elseif key == "domain" then
      domain = parse_handle_type(lex, ctx, "handle domain")
    elseif key == "target" then
      target = parse_handle_type(lex, ctx, "handle target")
    else
      lex:error_at(lex.last, "expected handle fact `repr`, `invalid`, `domain`, or `target`")
    end
    lex:skip_separators()
  end
  lex:expect("end")
  return Ast.node("DeclHandle", {
    name = name,
    qualifier = qualifier,
    repr = repr,
    invalid = invalid,
    domain = domain,
    target = target,
  }, Ast.origin(lex, start, lex.last, "parsed:decl"))
end

local function parse_entry_block(lex, ctx)
  local start = lex:next() -- entry or block
  local kind = start.value
  local name = lex:expect_name(kind .. " name")
  local state = {}
  if lex:peek().value == "(" then state = Type.parse_params(lex, ctx) end
  optional_do(lex)
  local body = Stmt.parse_block(lex, ctx, { "end" })
  lex:expect("end")
  return Ast.node(kind == "entry" and "RegionEntry" or "RegionBlock", {
    name = name.value,
    state = state,
    body = body,
  }, Ast.origin(lex, start, lex.last, "parsed:region_block"))
end

-- Parse a continuation exit entry:  name(fields)
-- The payload tuple may contain named fields (result [i32]) or bare types ([i32]).
local function parse_one_exit(lex, ctx)
  local name = lex:expect_name("continuation name")
  local fields = {}
  if lex:peek().value == "(" then
    lex:next() -- (
    if not lex:next_if(")") then
      repeat
        local t = lex:peek()
        local t1 = lex:peek(1)
        if t.kind == "name" and t1 and t1.value == "[" then
          fields[#fields + 1] = Type.parse_field(lex, ctx)
        elseif t.value == "[" then
          fields[#fields + 1] = Type.parse_product_splice(lex, ctx)
        else
          lex:error_at(t, "expected continuation field `name [type]` or anonymous `[type]`")
        end
      until not lex:next_if(",")
      lex:expect(")")
    end
  end
  return Ast.node("Exit", { name = name.value, fields = fields },
    Ast.origin(lex, name, lex.last or name, "parsed:exit"))
end

function Decl.parse_region(lex, ctx, entry_start)
  local start = entry_start or ctx.entry_token
  local name, qualifier, implicit_self = parse_callable_name(lex, "region name")

  -- Parse signature: (data_params ; continuation_params)
  -- Data params before `;` form the input product.
  -- Continuation params after `;` form the exit sum.
  -- If no `;`, everything is data params (no continuations).
  local inputs, exits
  lex:expect("(")
  inputs = {}
  exits = {}

  if lex:peek().value == ";" then
    -- No data params, only continuations
    lex:next() -- ;
    if not lex:next_if(")") then
      repeat
        if lex:peek().value == "[" then
          exits[#exits + 1] = Decl.parse_host_eval(lex, ctx, "conts")
        else
          exits[#exits + 1] = parse_one_exit(lex, ctx)
        end
      until not lex:next_if(",")
      lex:expect(")")
    end
  elseif lex:peek().value == ")" then
    -- Empty signature
    lex:next()
  else
    -- Parse data params (product), then optionally ; + continuations
    repeat
      if lex:peek().value == "[" then
        inputs[#inputs + 1] = Type.parse_product_splice(lex, ctx)
      else
        inputs[#inputs + 1] = Type.parse_field(lex, ctx)
      end
    until not lex:next_if(",") or lex:peek().value == ";"
    if lex:next_if(";") then
      if not lex:next_if(")") then
        repeat
          if lex:peek().value == "[" then
            exits[#exits + 1] = Decl.parse_host_eval(lex, ctx, "conts")
          else
            exits[#exits + 1] = parse_one_exit(lex, ctx)
          end
        until not lex:next_if(",")
        lex:expect(")")
      end
    else
      lex:expect(")")
    end
  end

  if implicit_self then
    if inputs[1] and inputs[1].name == "self" then
      lex:error_at(start, "colon region declarations inject `self`; use dot syntax for an explicit receiver type")
    end
    table.insert(inputs, 1, implicit_self_field(lex, start, qualifier))
  end

  local blocks = {}
  while not lex:at_eof() and lex:peek().value ~= "end" do
    if lex:peek().value ~= "entry" and lex:peek().value ~= "block" then
      lex:error_at(lex:peek(), "expected region entry/block or end")
    end
    blocks[#blocks + 1] = parse_entry_block(lex, ctx)
  end
  lex:expect("end")
  return Ast.node("DeclRegion", {
    name = name,
    qualifier = qualifier,
    implicit_self = implicit_self,
    inputs = inputs,
    exits = exits,
    blocks = blocks,
  }, Ast.origin(lex, start, lex.last, "parsed:decl"))
end

function Decl.parse_expr_fragment(lex, ctx)
  local start = ctx.entry_token
  local expr = Expr.parse(lex, ctx)
  lex:expect("end")
  return Ast.node("ExprFragment", { expr = expr }, Ast.origin(lex, start, lex.last, "parsed:expr"))
end

function Decl.parse_stmt_fragment(lex, ctx)
  local start = ctx.entry_token
  local body = Stmt.parse_block(lex, ctx, { "end" })
  lex:expect("end")
  return Ast.node("StmtFragment", { body = body }, Ast.origin(lex, start, lex.last, "parsed:stmt"))
end

return Decl
