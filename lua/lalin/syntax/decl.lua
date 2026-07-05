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

function Decl.parse_host_eval(lex, ctx, role)
  local raw, open, close = lex:consume_balanced_from_open("[", "]")
  local refs = Ast.extract_refs(raw)
  Ast.add_refs(ctx, refs)
  return Ast.host_eval(raw, refs, Ast.origin(lex, open, close, "parsed:host_eval"), role or (ctx and ctx.expected_role) or "decls")
end

function Decl.parse_decl_stream(lex, ctx)
  return Decl.parse_host_eval(lex, ctx, (ctx and ctx.expected_role) or "decls")
end

function Decl.parse_fn(lex, ctx, entry_start)
  local start = entry_start or ctx.entry_token
  local name = nil
  local qualifier = nil
  if lex:peek().kind == "name" and (lex:peek(1).value == "(" or lex:peek(1).value == ".") then
    name, qualifier = parse_qualified_name(lex, "function name")
  end
  if name == nil and lex:peek().value ~= "(" then
    lex:error_at(lex:peek(), "expected function name or parameter list")
  end
  local params = Type.parse_params(lex, ctx)
  local result = nil
  if lex:peek().value == "[" then result = Type.parse(lex, ctx) end
  optional_do(lex)
  local body = Stmt.parse_block(lex, ctx, { "end" })
  lex:expect("end")
  return Ast.node("DeclFunc", {
    name = name,
    qualifier = qualifier,
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
  local name, qualifier = parse_qualified_name(lex, "region name")

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
