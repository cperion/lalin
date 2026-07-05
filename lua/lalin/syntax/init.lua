-- lalin.syntax
-- Terra-like parsed-channel frontend for Lalin, registered as a generic LLBL
-- syntax language.  The parser returns first-class Lalin parsed AST values;
-- repository integration should lower these nodes to LalinTree ASDL or call the
-- existing DSL heads in one place.

local llbl_syntax = require("llbl.syntax")
local Constructor = require("llbl.syntax.constructor")
local Ast = require("lalin.syntax.ast")
local Decl = require("lalin.syntax.decl")
local Expr = require("lalin.syntax.expr")
local Stmt = require("lalin.syntax.stmt")
local Document = require("lalin.syntax.document")

local LalinSyntax = {}

local function wrap_ast(ast, ctx, opts)
  opts = opts or {}
  local refs = {}
  for _, r in ipairs(ctx.refs or {}) do refs[#refs + 1] = r end
  local outputs = {}
  if ast.name and (ast.tag == "DeclFunc" or ast.tag == "DeclStruct" or ast.tag == "DeclUnion" or ast.tag == "DeclHandle" or ast.tag == "DeclRegion") then
    outputs[1] = { name = ast.name }
  end
  local lua_binding = ctx.lua_binding
  return Constructor.new {
    owner = "lalin",
    kind = ast.tag,
    role = opts.role or "decl",
    channel = opts.channel or "parsed:lalin",
    refs = refs,
    outputs = outputs,
    lua_binding = lua_binding,
    origin = ast.origin,
    ast = ast,
    build = function(env)
      -- Resolve explicit host escapes at construction/evaluation time.  This is
      -- the exact point where Lua lexical values become Lalin constants,
      -- fragments, types, or diagnostics in a full Lalin adapter.
      local copy = ast -- AST is intentionally shared; callsites normally build once.
      if copy.name == nil and copy.tag == "DeclFunc" and lua_binding and lua_binding.name then
        copy.name = lua_binding.name
        copy.public_name = copy.public_name or lua_binding.name
        copy.debug_name = copy.debug_name or lua_binding.name
      end
      Ast.resolve_host_evals(copy, env)
      return copy
    end,
  }
end

function LalinSyntax.parse_entry(lex, entry, ctx)
  local ast
  if entry == "fn" then
    ast = Decl.parse_fn(lex, ctx, ctx.entry_token)
  elseif entry == "struct" then
    ast = Decl.parse_struct(lex, ctx, ctx.entry_token)
  elseif entry == "union" then
    ast = Decl.parse_union(lex, ctx, ctx.entry_token)
  elseif entry == "handle" then
    ast = Decl.parse_handle(lex, ctx, ctx.entry_token)
  elseif entry == "region" then
    ast = Decl.parse_region(lex, ctx, ctx.entry_token)
  elseif entry == "expr" then
    ast = Decl.parse_expr_fragment(lex, ctx)
  elseif entry == "stmt" or entry == "quote" then
    ast = Decl.parse_stmt_fragment(lex, ctx)
  elseif entry == "lalin" then
    lex:error_at(ctx.entry_token, "bare `lalin` entrypoint requires a following entry token")
  else
    lex:error_at(ctx.entry_token, "unsupported Lalin syntax entrypoint `" .. tostring(entry) .. "`")
  end
  return wrap_ast(ast, ctx, { role = ast.tag })
end

function LalinSyntax.parse_expression(lex, ctx)
  local ast = Expr.parse(lex, ctx)
  return wrap_ast(ast, ctx, { role = "expr", channel = "parsed:expr" })
end

function LalinSyntax.parse_statement(lex, ctx)
  local body = Stmt.parse_block(lex, ctx, { "end" })
  lex:expect("end")
  local ast = Ast.node("StmtFragment", { body = body }, ctx:origin(lex, ctx.entry_token, lex.last, "parsed:stmt"))
  return wrap_ast(ast, ctx, { role = "stmt", channel = "parsed:stmt" })
end

function LalinSyntax.parse_host_eval(lex, ctx, role)
  local ast = Decl.parse_host_eval(lex, ctx, role or (ctx and ctx.expected_role) or "decls")
  return wrap_ast(ast, ctx, { role = role or ast.expected_role or "decls", channel = "parsed:host_eval" })
end

function LalinSyntax.parse_decl_stream(lex, ctx)
  local ast = Decl.parse_decl_stream(lex, ctx)
  return wrap_ast(ast, ctx, { role = ast.expected_role or "decls", channel = "parsed:host_eval" })
end

function LalinSyntax.parse_document(source, chunkname, opts)
  return Document.parse(source, chunkname, opts)
end

function LalinSyntax.materialize_document(doc, opts)
  return Document.materialize(doc, opts)
end

function LalinSyntax.load_document(source, chunkname, opts)
  return Document.load(source, chunkname, opts)
end

function LalinSyntax.to_decls(value, opts)
  if type(value) == "table" and value.tag == "DeclDocument" then
    if value.decls ~= nil then return value.decls, value end
    return Document.materialize(value, opts)
  end
  return value
end

function LalinSyntax.register()
  local spec = {
    name = "lalin",
    owner = "lalin",
    entrypoints = { "fn", "struct", "union", "handle", "region", "quote", "expr", "stmt" },
    direct_entrypoints = nil, -- callers choose whether to activate bare entrypoints.
    keywords = {
      "fn", "region", "struct", "union", "handle", "requires", "ensures",
      "do", "end", "if", "then", "elseif", "else", "loop", "in",
      "grid", "tiled", "window", "return", "jump", "emit", "call", "entry", "block",
      "let", "var", "fold", "scan", "by", "over", "step", "into",
    },
    parse_entry = LalinSyntax.parse_entry,
    parse_host_eval = LalinSyntax.parse_host_eval,
    parse_decl_stream = LalinSyntax.parse_decl_stream,
    decl_stream_role = "decls",
    expression = LalinSyntax.parse_expression,
    statement = LalinSyntax.parse_statement,
  }
  LalinSyntax.language_spec = spec
  LalinSyntax.language_name = spec.name
  return llbl_syntax.register(spec)
end

-- ── Convert parsed AST to LalinTree for the compiler pipeline ──────────

function LalinSyntax.to_module(parsed_decls, name, T)
  parsed_decls = LalinSyntax.to_decls(parsed_decls)
  -- Use the caller's schema context, or create one at this public boundary.
  local asdl = require("lalin.asdl")
  T = T or asdl.context()
  if not T.LalinTree then
    require("lalin.schema_projection")(T)
  end
  local to_tree = require("lalin.syntax.to_tree")(T)
  local Tr, C, B, Ty = T.LalinTree, T.LalinCore, T.LalinBind, T.LalinType

  name = name or "parsed"
  local decls = {}
  local anon_id = 0

  local function sanitize_ident(s)
    s = tostring(s or ""):gsub("[^%w_]", "_")
    if s == "" then return nil end
    if s:match("^%d") then s = "_" .. s end
    return s
  end

  local function compiler_name(parsed)
    if parsed.name ~= nil and parsed.name ~= "" then return parsed.name end
    local public = sanitize_ident(parsed.public_name or parsed.debug_name)
    anon_id = anon_id + 1
    if public ~= nil then return "__lln_" .. public .. "_" .. tostring(anon_id) end
    return "__lln_fn_" .. tostring(anon_id)
  end

  local function qualified_compiler_name(parsed)
    local parts = {}
    for i, p in ipairs(parsed.qualifier or {}) do parts[#parts + 1] = p end
    parts[#parts + 1] = compiler_name(parsed)
    return table.concat(parts, ".")
  end

  local function parsed_type(ptype)
    return to_tree.parsed_type(ptype)
  end

  local function handle_repr(ptype)
    if ptype == nil then return Ty.HandleReprScalar(C.ScalarU32) end
    local ty = parsed_type(ptype)
    if asdl.classof(ty) ~= Ty.TScalar then
      error("parsed_to_module: handle repr must be a scalar type such as `[u32]`", 2)
    end
    return Ty.HandleReprScalar(ty.scalar)
  end

  local function handle_type_ref(ptype, site)
    local ty = parsed_type(ptype)
    local cls = asdl.classof(ty)
    if cls == Ty.TNamed or cls == Ty.THandle then return ty.ref end
    error("parsed_to_module: " .. (site or "handle fact") .. " must be a named type such as `[named(\"Store\")]`", 2)
  end

  local function handle_invalid(raw)
    if raw == nil then return Ty.HandleInvalidNone end
    return Ty.HandleInvalidInt(tostring(raw))
  end

  local function block_params(fields)
    local out = {}
    for i, f in ipairs(to_tree.product_fields(fields or {})) do
      out[i] = Tr.BlockParam(f.name, parsed_type(f.type))
    end
    return out
  end

  local function entry_params(fields)
    local out = {}
    for i, f in ipairs(to_tree.product_fields(fields or {})) do
      out[i] = Tr.EntryBlockParam(f.name, parsed_type(f.type), Tr.ExprRef(Tr.ExprSurface, B.ValueRefName(f.name)))
    end
    return out
  end

  local function region_conts(exits, region_name)
    local conts, by_name = {}, {}
    for i, exit in ipairs(to_tree.conts(exits or {})) do
      conts[i] = Tr.RegionCont("cont:" .. tostring(region_name) .. ":" .. tostring(exit.name) .. ":" .. tostring(i), exit.name, block_params(exit.fields or {}))
      by_name[exit.name] = conts[i]
    end
    return conts, by_name
  end

  local region_stmts

  local function retarget_region_stmt(stmt, cont_by_name)
    if stmt.tag == "StmtEmit" or stmt.tag == "StmtCall" then
      local lowered = to_tree.stmt(stmt)
      local wiring = {}
      for i, wire in ipairs(lowered.wiring or {}) do
        local cont = cont_by_name[wire.target.label.name]
        wiring[i] = cont and Tr.RegionContWire(wire.name, Tr.RegionWireCont(cont)) or wire
      end
      if stmt.tag == "StmtEmit" then
        return Tr.StmtRegionEmit(lowered.h, lowered.invoke_id, lowered.target, lowered.args, wiring)
      end
      return Tr.StmtRegionCall(lowered.h, lowered.invoke_id, lowered.target, lowered.args, wiring)
    elseif stmt.tag == "StmtJump" then
      local cont = cont_by_name[stmt.target]
      if cont then
        local args = {}
        for i, f in ipairs(stmt.payload or {}) do args[i] = Tr.JumpArg(f.key or "", to_tree.expr(f.value)) end
        return Tr.StmtJumpCont(Tr.StmtSurface, cont, args)
      end
    elseif stmt.tag == "StmtIf" then
      local then_body = region_stmts(stmt.then_body or {}, cont_by_name)
      local else_body = stmt.else_body and region_stmts(stmt.else_body, cont_by_name) or {}
      for _, elseif_block in ipairs(stmt.elseif_blocks or {}) do
        else_body = {
          Tr.StmtIf(Tr.StmtSurface, to_tree.expr(elseif_block.cond), region_stmts(elseif_block.body or {}, cont_by_name), else_body),
        }
      end
      return Tr.StmtIf(Tr.StmtSurface, to_tree.expr(stmt.cond), then_body, else_body)
    end
    return to_tree.stmt(stmt)
  end

  region_stmts = function(stmts, cont_by_name)
    local out = {}
    for i, stmt in ipairs(stmts or {}) do out[i] = retarget_region_stmt(stmt, cont_by_name) end
    return out
  end

  -- Helper: convert a single parsed decl to a Tr.Item for the module.
  -- The tree ASDL uses Tr.ItemFunc(FuncLocal/FuncExport) for functions,
  -- Tr.ItemType(TypeDeclStruct/TypeDeclTaggedUnionSugar) for structs/unions.
  local function call_name(expr)
    if expr and expr.tag == "Name" then return expr.name end
    return nil
  end

  local function contract_from_expr(expr)
    if not expr or expr.tag ~= "Call" then
      error("parsed requires expects contract calls such as bounds(ptr)(n), readonly(ptr), or disjoint(a)(b)", 2)
    end
    local name = call_name(expr.callee)
    if name == "readonly" then
      if #(expr.args or {}) ~= 1 then error("readonly contract expects one argument", 2) end
      return Tr.ContractReadonly(to_tree.expr(expr.args[1]))
    elseif name == "writeonly" then
      if #(expr.args or {}) ~= 1 then error("writeonly contract expects one argument", 2) end
      return Tr.ContractWriteonly(to_tree.expr(expr.args[1]))
    elseif name == "noalias" then
      if #(expr.args or {}) ~= 1 then error("noalias contract expects one argument", 2) end
      return Tr.ContractNoAlias(to_tree.expr(expr.args[1]))
    elseif name == "invalidate" then
      if #(expr.args or {}) ~= 1 then error("invalidate contract expects one argument", 2) end
      return Tr.ContractInvalidate(to_tree.expr(expr.args[1]))
    elseif name == "preserve" then
      if #(expr.args or {}) ~= 1 then error("preserve contract expects one argument", 2) end
      return Tr.ContractPreserve(to_tree.expr(expr.args[1]))
    end

    local callee = expr.callee
    if callee and callee.tag == "Call" then
      local outer_args = expr.args or {}
      local inner_args = callee.args or {}
      local inner_name = call_name(callee.callee)
      if inner_name == "bounds" then
        if #inner_args ~= 1 or #outer_args ~= 1 then error("bounds contract expects bounds(base)(len)", 2) end
        return Tr.ContractBounds(to_tree.expr(inner_args[1]), to_tree.expr(outer_args[1]))
      elseif inner_name == "disjoint" then
        if #inner_args ~= 1 or #outer_args ~= 1 then error("disjoint contract expects disjoint(a)(b)", 2) end
        return Tr.ContractDisjoint(to_tree.expr(inner_args[1]), to_tree.expr(outer_args[1]))
      elseif inner_name == "same_len" then
        if #inner_args ~= 1 or #outer_args ~= 1 then error("same_len contract expects same_len(a)(b)", 2) end
        return Tr.ContractSameLen(to_tree.expr(inner_args[1]), to_tree.expr(outer_args[1]))
      end
    end

    error("parsed requires: unsupported contract expression", 2)
  end

  local function decl_to_item(parsed)
    if not parsed then return nil end
    if parsed.tag == "DeclFunc" then
      local fname = compiler_name(parsed)
      local params = {}
      for i, p in ipairs(to_tree.product_fields(parsed.params or {})) do
        params[i] = T.LalinType.Param(p.name, parsed_type(p.type))
      end
      local result_ty = parsed_type(parsed.result)
      local body_src, contracts = {}, {}
      for _, stmt in ipairs(parsed.body or {}) do
        if stmt.tag == "StmtRequires" then
          for _, expr in ipairs(stmt.exprs or {}) do
            contracts[#contracts + 1] = contract_from_expr(expr)
          end
        else
          body_src[#body_src + 1] = stmt
        end
      end
      local body = to_tree.stmts(body_src)
      if #body == 0 then
        body = { Tr.StmtReturnVoid(Tr.StmtSurface) }
      end
      local func_spec = #contracts > 0
        and Tr.FuncLocalContract(fname, params, result_ty, contracts, body)
        or Tr.FuncLocal(fname, params, result_ty, body)
      return Tr.ItemFunc(func_spec)
    elseif parsed.tag == "DeclStruct" then
      local fields = {}
      for i, f in ipairs(to_tree.product_fields(parsed.fields or {})) do
        fields[i] = T.LalinType.FieldDecl(f.name, parsed_type(f.type))
      end
      return Tr.ItemType(Tr.TypeDeclStruct(parsed.name, fields))
    elseif parsed.tag == "DeclUnion" then
      local variants = {}
      for _, v in ipairs(to_tree.variants(parsed.variants or {})) do
        local fields = {}
        for i, f in ipairs(to_tree.product_fields(v.fields or {})) do
          fields[i] = T.LalinType.FieldDecl(f.name, parsed_type(f.type))
        end
        variants[#variants + 1] = Tr.VariantDecl(v.name, fields)
      end
      return Tr.ItemType(Tr.TypeDeclTaggedUnionSugar(parsed.name, variants))
    elseif parsed.tag == "DeclHandle" then
      local facts = {}
      if parsed.domain ~= nil then facts[#facts + 1] = Ty.HandleDomain(handle_type_ref(parsed.domain, "handle domain")) end
      if parsed.target ~= nil then facts[#facts + 1] = Ty.HandleTarget(handle_type_ref(parsed.target, "handle target")) end
      return Tr.ItemType(Tr.TypeDeclHandle(parsed.name, handle_repr(parsed.repr), handle_invalid(parsed.invalid), facts))
    elseif parsed.tag == "DeclRegion" then
      local rname = qualified_compiler_name(parsed)
      local params = {}
      for i, p in ipairs(to_tree.product_fields(parsed.inputs or {})) do
        params[i] = T.LalinType.Param(p.name, parsed_type(p.type))
      end
      local conts, cont_by_name = region_conts(parsed.exits or {}, rname)
      local entry_src, block_src = nil, {}
      for _, b in ipairs(parsed.blocks or {}) do
        if b.tag == "RegionEntry" and entry_src == nil then entry_src = b else block_src[#block_src + 1] = b end
      end
      entry_src = entry_src or { name = "entry", state = {}, body = {} }
      local blocks = {}
      for i, b in ipairs(block_src) do
        blocks[i] = Tr.ControlBlock(Tr.BlockLabel(b.name), block_params(b.state or {}), region_stmts(b.body or {}, cont_by_name))
      end
      return Tr.ItemRegion(Tr.Region(
        rname,
        params,
        conts,
        Tr.EntryControlBlock(Tr.BlockLabel(entry_src.name), entry_params(entry_src.state or {}), region_stmts(entry_src.body or {}, cont_by_name)),
        blocks))
    end
    error("parsed_to_module: unsupported decl tag " .. tostring(parsed.tag), 2)
  end

  for _, d in ipairs(to_tree.decls(parsed_decls)) do
    decls[#decls + 1] = decl_to_item(d)
  end

  return Tr.Module(Tr.ModuleSurface, decls)
end

-- Register on require.
LalinSyntax.register()

return LalinSyntax
