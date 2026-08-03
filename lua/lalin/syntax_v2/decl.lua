-- lalin.syntax_v2.decl
-- Declaration parser producing LalinParse intermediate types directly.
-- Type annotations are evaluated LLBL HostEval values before Parsed ASDL construction.

local Ast = require("lalin.syntax_v2.ast")
local Roles = require("lalin.syntax_v2.roles")
local Type = require("lalin.syntax_v2.type")
local Stmt = require("lalin.syntax_v2.stmt")
local Expr = require("lalin.syntax_v2.expr")

-- Load schema_v2 types
require("lalin.schema_v2")
local P    = package.loaded["lalin.schema_v2.parse"]
local Tree = package.loaded["lalin.schema_v2.tree"]
local Core = package.loaded["lalin.schema_v2.core"]

local Decl = {}
local parse_entry_block

local function optional_do(lex)
  lex:next_if("do")
end

-- Parse a possibly qualified name: returns name, qualifier
local function parse_qualified_name(lex, label)
  local name = lex:expect_name(label or "name").value
  local qualifier = nil
  if lex:peek().value == "." then
    qualifier = {}
    qualifier[#qualifier + 1] = name
    while lex:peek().value == "." do
      lex:next()
      local part = lex:expect_name(label or "qualified name part").value
      qualifier[#qualifier + 1] = part
    end
    name = table.remove(qualifier)
  end
  return name, qualifier
end

-- Parse a function/region name with Lua-style method definitions (A.B:name)
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

local function implicit_self_field(lex, start, qualifier, ctx)
  if qualifier == nil or #qualifier == 0 then
    lex:error_at(start, "implicit self method declaration requires an owning struct path")
  end
  local owner = table.concat(qualifier, ".")
  local owner_ty = ctx.host_env.named(owner)
  return P.ParsedField("self", ctx.host_env.ptr[owner_ty], false, true)
end

function Decl.parse_host_eval(lex, ctx, role)
  local raw, open, close = Ast.consume_balanced_from_open(lex)
  local refs = Ast.extract_refs(raw)
  Ast.add_refs(ctx, refs)
  return Ast.host_eval(raw, refs, Ast.origin(lex, open, close, "parsed:host_eval"), role or (ctx and ctx.expected_role) or "decls")
end

function Decl.parse_decl_stream(lex, ctx)
  local event = Decl.parse_host_eval(lex, ctx, "decls")
  return P.ParsedDeclGroup(Roles.adapt(ctx, "decls", event))
end

local function host_path_value(path, ctx, lex, start)
  local value = ctx.host_env[path[1]]
  if value == nil then lex:error_at(start, "unknown host binding `" .. path[1] .. "`") end
  for i = 2, #path do
    if type(value) ~= "table" then
      lex:error_at(start, "host metadata path `" .. table.concat(path, ".", 1, i - 1)
        .. "` is not indexable")
    end
    value = value[path[i]]
    if value == nil then
      lex:error_at(start, "unknown host metadata path `" .. table.concat(path, ".", 1, i) .. "`")
    end
  end
  return value
end

function Decl.parse_meta_assign(lex, ctx, entry_start)
  local start = entry_start or lex:peek()
  local path = { lex:expect_name("metadata assignment target").value }
  while lex:next_if(".") do
    path[#path + 1] = lex:expect_name("metadata assignment target part").value
  end
  if #path < 2 then lex:error_at(start, "metadata assignment requires a qualified host path") end
  lex:expect("=")
  local value
  if lex:peek().value == "[" then
    value = Roles.adapt(ctx, "value", Decl.parse_host_eval(lex, ctx, "value"))
  else
    local rhs = { lex:expect_name("metadata assignment value").value }
    while lex:next_if(".") do
      rhs[#rhs + 1] = lex:expect_name("metadata assignment value part").value
    end
    value = host_path_value(rhs, ctx, lex, start)
  end
  local owner_path = {}
  for i = 1, #path - 1 do owner_path[i] = path[i] end
  local owner = host_path_value(owner_path, ctx, lex, start)
  owner[path[#path]] = value
  return P.ParsedDeclGroup({})
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
  local raw_params = Type.parse_params(lex, ctx)
  if implicit_self then
    local first_param = raw_params[1]
    if first_param and first_param.name == "self" then
      lex:error_at(start, "colon method declarations inject `self`; use dot syntax for an explicit receiver type")
    end
    table.insert(raw_params, 1, implicit_self_field(lex, start, qualifier, ctx))
  end
  local params = raw_params
  local result_ty = Type.void()
  if lex:peek().value == "[" then result_ty = Type.parse(lex, ctx) end
  optional_do(lex)
  local body
  if lex:peek().value == "entry" or lex:peek().value == "block" then
    -- Control form: preserve the authored entry/block structure as a typed
    -- ParsedFuncBodyControl with a deterministic source-site region id.
    local region_id = "lln.fn." .. tostring(start.start)
    local entry, blocks, saw_entry = nil, {}, false
    while not lex:at_eof() and lex:peek().value ~= "end" do
      local kind = lex:peek().value
      if kind ~= "entry" and kind ~= "block" then
        lex:error_at(lex:peek(), "expected function entry/block or end")
      end
      local blk = parse_entry_block(lex, ctx)
      if kind == "entry" then
        if saw_entry then
          lex:error_at(lex.last, "function control form allows a single entry block")
        end
        saw_entry = true
        entry = blk
      else
        blocks[#blocks + 1] = blk
      end
    end
    if entry == nil then
      lex:error_at(lex.last or lex:peek(), "function control form requires an entry block")
    end
    body = P.ParsedFuncBodyControl(region_id, entry, blocks)
  else
    body = P.ParsedFuncBodyLinear(Stmt.parse_block(lex, ctx, { "end" }))
  end
  lex:expect("end")
  local qual_names = {}
  if qualifier then for i, q in ipairs(qualifier) do qual_names[i] = Core.Name(q) end end
  return P.ParsedFunc(name or "", qual_names, implicit_self, params, result_ty, body)
end

function Decl.parse_struct(lex, ctx, entry_start)
  local start = entry_start or ctx.entry_token
  local name = lex:expect_name("struct name")
  optional_do(lex)
  local raw_fields = Type.parse_field_block(lex, ctx, "end")
  lex:expect("end")
  local fields = raw_fields
  return P.ParsedStruct(name.value, fields)
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
  local raw_params = Type.parse_params(lex, ctx)
  local result_ty = Type.void()
  if lex:peek().value == "[" then result_ty = Type.parse(lex, ctx) end
  local symbol = name

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
  local params = raw_params
  local qual_names = {}
  if qualifier then for i, q in ipairs(qualifier) do qual_names[i] = Core.Name(q) end end
  return P.ParsedExtern(name, qual_names, params, result_ty, symbol or "")
end


function Decl.parse_union(lex, ctx, entry_start)
  local start = entry_start or ctx.entry_token
  local name = lex:expect_name("union name")
  optional_do(lex)
  local variants = {}
  while not lex:at_eof() and lex:peek().value ~= "end" do
    if lex:peek().value == "[" then
      local event = Decl.parse_host_eval(lex, ctx, "variants")
      local spliced = Roles.adapt(ctx, "variants", event)
      for i = 1, #spliced do variants[#variants + 1] = spliced[i] end
    else
      local vstart = lex:expect_name("variant name")
      local raw_fields = {}
      if lex:peek().value == "(" then raw_fields = Type.parse_params(lex, ctx) end
      local fields = raw_fields
      variants[#variants + 1] = P.ParsedVariant(vstart.value, fields)
    end
    lex:skip_separators()
  end
  lex:expect("end")
  return P.ParsedUnion(name.value, variants)
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
  local repr_ty
  local invalid = ""
  local domain_ty
  local target_ty

  if lex:peek().value == "[" then
    repr_ty = parse_handle_type(lex, ctx, "handle representation")
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
      repr_ty = parse_handle_type(lex, ctx, "handle representation")
    elseif key == "invalid" then
      lex:next_if("=")
      invalid = parse_handle_invalid(lex)
    elseif key == "domain" then
      domain_ty = parse_handle_type(lex, ctx, "handle domain")
    elseif key == "target" then
      target_ty = parse_handle_type(lex, ctx, "handle target")
    else
      lex:error_at(lex.last, "expected handle fact `repr`, `invalid`, `domain`, or `target`")
    end
    lex:skip_separators()
  end
  lex:expect("end")
  local qual_names = {}
  if qualifier then for i, q in ipairs(qualifier) do qual_names[i] = Core.Name(q) end end
  return P.ParsedHandle(name, qual_names, repr_ty, invalid or "", domain_ty, target_ty)
end

parse_entry_block = function(lex, ctx)
  local start = lex:next() -- entry or block
  local kind = start.value
  local name = lex:expect_name(kind .. " name")
  local state = {}
  if lex:peek().value == "(" then state = Type.parse_params(lex, ctx) end
  optional_do(lex)
  local body = Stmt.parse_block(lex, ctx, { "end" })
  lex:expect("end")
  local fields = state
  if kind == "entry" then
    return P.ParsedRegionEntryBlock(name.value, fields, body)
  end
  return P.ParsedRegionBodyBlock(name.value, fields, body)
end

-- Parse a continuation exit entry: name(fields)
local function parse_one_exit(lex, ctx)
  local name = lex:expect_name("continuation name")
  local raw_fields = {}
  if lex:peek().value == "(" then
    lex:next() -- (
    if not lex:next_if(")") then
      repeat
        local t = lex:peek()
        local t1 = lex:peek(1)
        if t.kind == "name" and t1 and t1.value == "[" then
          raw_fields[#raw_fields + 1] = Type.parse_field(lex, ctx)
        elseif t.value == "[" then
          local spliced = Type.parse_product_splice(lex, ctx)
          for i = 1, #spliced do raw_fields[#raw_fields + 1] = spliced[i] end
        else
          lex:error_at(t, "expected continuation field `name [type]` or anonymous `[type]`")
        end
      until not lex:next_if(",")
      lex:expect(")")
    end
  end
  local fields = raw_fields
  return P.ParsedExit(name.value, fields)
end


function Decl.parse_region(lex, ctx, entry_start)
  local start = entry_start or ctx.entry_token
  local name, qualifier, implicit_self = parse_callable_name(lex, "region name")

  local inputs, exits
  lex:expect("(")
  inputs = {}
  exits = {}

  if lex:peek().value == ";" then
    lex:next() -- ;
    if not lex:next_if(")") then
      repeat
        if lex:peek().value == "[" then
          local event = Decl.parse_host_eval(lex, ctx, "conts")
          local spliced = Roles.adapt(ctx, "conts", event)
          for i = 1, #spliced do exits[#exits + 1] = spliced[i] end
        else
          exits[#exits + 1] = parse_one_exit(lex, ctx)
        end
      until not lex:next_if(",")
      lex:expect(")")
    end
  elseif lex:peek().value == ")" then
    lex:next()
  else
    repeat
      if lex:peek().value == "[" then
        local spliced = Type.parse_product_splice(lex, ctx)
        for i = 1, #spliced do inputs[#inputs + 1] = spliced[i] end
      else
        inputs[#inputs + 1] = Type.parse_field(lex, ctx)
      end
    until not lex:next_if(",") or lex:peek().value == ";"
    if lex:next_if(";") then
      if not lex:next_if(")") then
        repeat
          if lex:peek().value == "[" then
            local event = Decl.parse_host_eval(lex, ctx, "conts")
            local spliced = Roles.adapt(ctx, "conts", event)
            for i = 1, #spliced do exits[#exits + 1] = spliced[i] end
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
    local first_input = inputs[1]
    if first_input and first_input.name == "self" then
      lex:error_at(start, "colon region declarations inject `self`; use dot syntax for an explicit receiver type")
    end
    table.insert(inputs, 1, implicit_self_field(lex, start, qualifier, ctx))
  end

  local contracts = {}
  while not lex:at_eof() and lex:peek().value == "requires" do
    contracts[#contracts + 1] = Stmt.parse(lex, ctx)
  end

  local blocks = {}
  while not lex:at_eof() and lex:peek().value ~= "end" do
    if lex:peek().value ~= "entry" and lex:peek().value ~= "block" then
      lex:error_at(lex:peek(), "expected region requires/entry/block or end")
    end
    blocks[#blocks + 1] = parse_entry_block(lex, ctx)
  end
  lex:expect("end")
  local qual_names = {}
  if qualifier then for i, q in ipairs(qualifier) do qual_names[i] = Core.Name(q) end end
  return P.ParsedRegion(name or "", qual_names, implicit_self, inputs, exits, contracts, blocks)
end

function Decl.parse_expr_fragment(lex, ctx)
  local start = ctx.entry_token
  local expr = Expr.parse(lex, ctx)
  lex:expect("end")
  return P.ParsedExprFragment(expr)
end

function Decl.parse_stmt_fragment(lex, ctx)
  local start = ctx.entry_token
  local body = Stmt.parse_block(lex, ctx, { "end" })
  lex:expect("end")
  return P.ParsedStmtFragment(body)
end

return Decl
