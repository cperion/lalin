-- lalin.syntax_v2.document
-- .lln document parser, materializer, and module builder.
-- Parses .lln → ParsedDocument; materialize binds names into env;
-- to_module converts ParsedDecl → Tree.Module with resolved types.

local llbl = require("llbl")
local Lexer = require("llbl.syntax.lexer")
local Ast = require("lalin.syntax_v2.ast")
local Decl = require("lalin.syntax_v2.decl")

-- Load schema_v2
require("lalin.schema_v2")
local asdl = require("lalin.asdl")
local P   = package.loaded["lalin.schema_v2.parse"]
local Tr  = package.loaded["lalin.schema_v2.tree"]
local C   = package.loaded["lalin.schema_v2.core"]
local B   = package.loaded["lalin.schema_v2.bind"]
local Ty  = package.loaded["lalin.schema_v2.type"]

local Document = {}

local ROOT_ROLE = "decls"
local ROOT_ROLE_DISPLAY = "Lalin.decls"

local root_entries = {
  fn = "parse_fn", struct = "parse_struct", union = "parse_union",
  handle = "parse_handle", region = "parse_region", extern = "parse_extern",
}

local rejected_lua_roots = {
  ["local"] = "Lua `local` is not allowed",
  ["return"] = "Lua `return` is not allowed",
  ["import"] = "parse-time `import` is not allowed",
  ["module"] = "Lua `module` is not allowed",
}

-- ═══════════════════════════════════════════════════════════
-- Type lookup table: maps type-source strings to Ty.Type
-- ═══════════════════════════════════════════════════════════

local scalar_lookup = {
  i8       = Ty.TScalar(C.ScalarI8),
  i16      = Ty.TScalar(C.ScalarI16),
  i32      = Ty.TScalar(C.ScalarI32),
  i64      = Ty.TScalar(C.ScalarI64),
  u8       = Ty.TScalar(C.ScalarU8),
  u16      = Ty.TScalar(C.ScalarU16),
  u32      = Ty.TScalar(C.ScalarU32),
  u64      = Ty.TScalar(C.ScalarU64),
  f32      = Ty.TScalar(C.ScalarF32),
  f64      = Ty.TScalar(C.ScalarF64),
  bool     = Ty.TScalar(C.ScalarBool),
  void     = Ty.TScalar(C.ScalarVoid),
  rawptr   = Ty.TScalar(C.ScalarRawPtr),
  index    = Ty.TScalar(C.ScalarIndex),
}

local function resolve_type_source(source, named_env)
  if source == nil or source == "" then
    return Ty.TScalar(C.ScalarVoid)
  end
  -- Strip whitespace
  source = source:match("^%s*(.-)%s*$")
  -- ptr [inner]
  local ptr_inner = source:match("^ptr %[(.+)%]$")
  if ptr_inner then
    return Ty.TPtr(resolve_type_source(ptr_inner, named_env))
  end
  -- view [inner]
  local view_inner = source:match("^view %[(.+)%]$")
  if view_inner then
    return Ty.TView(resolve_type_source(view_inner, named_env))
  end
  -- slice [inner]
  local slice_inner = source:match("^slice %[(.+)%]$")
  if slice_inner then
    return Ty.TSlice(resolve_type_source(slice_inner, named_env))
  end
  -- owned [inner]
  local owned_inner = source:match("^owned %[(.+)%]$")
  if owned_inner then
    return Ty.TOwned(resolve_type_source(owned_inner, named_env))
  end
  -- Scalar lookup
  if scalar_lookup[source] then
    return scalar_lookup[source]
  end
  -- Named type: look up in materialized env
  if named_env and named_env[source] then
    local decl = named_env[source]
    local cls = asdl.classof(decl)
    if cls == P.ParsedStruct or cls == P.ParsedUnion or cls == P.ParsedHandle then
      return Ty.TNamed(Ty.TypeRefPath(C.Path({ C.Name(source) })))
    end
  end
  -- Fallback: try as qualified name A.B.C
  if source:find("%.") then
    local parts = {}
    for part in source:gmatch("[^.]+") do
      parts[#parts + 1] = C.Name(part)
    end
    return Ty.TNamed(Ty.TypeRefPath(C.Path(parts)))
  end
  -- Assume it's a named type
  return Ty.TNamed(Ty.TypeRefPath(C.Path({ C.Name(source) })))
end

-- ═══════════════════════════════════════════════════════════
-- Parse
-- ═══════════════════════════════════════════════════════════

local function copy_opts(opts)
  local out = {}
  if opts then for k, v in pairs(opts) do out[k] = v end end
  return out
end

local function make_ctx(lex, opts)
  opts = opts or {}
  local ctx = {
    refs = {}, ref_seen = {},
    lex = lex, opts = opts,
    expected_role = opts.root_role or ROOT_ROLE,
    root_role = opts.root_role or ROOT_ROLE,
    role_display = ROOT_ROLE_DISPLAY,
    document = true,
  }
  function ctx:add_ref(name)
    name = tostring(name or "")
    if name == "" or self.ref_seen[name] then return end
    self.ref_seen[name] = true
    self.refs[#self.refs + 1] = name
  end
  function ctx:origin(lex_, start_tok, end_tok, channel)
    return Ast.origin(lex_ or lex, start_tok, end_tok, channel)
  end
  return ctx
end

local function reject_root(lex, tok)
  local detail = rejected_lua_roots[tok.value] or ("Lua chunk construct `" .. tostring(tok.value) .. "` is not allowed")
  lex:error_at(tok, ".lln documents are rooted at " .. ROOT_ROLE_DISPLAY .. "; " .. detail)
end

local function looks_like_meta_assign(lex)
  if lex:peek().kind ~= "name" then return false end
  local mark = lex:mark()
  lex:next()
  local saw_dot = false
  while lex:peek().value == "." do
    saw_dot = true
    lex:next()
    if lex:peek().kind ~= "name" then lex:restore(mark); return false end
    lex:next()
  end
  local is_assign = saw_dot and lex:peek().value == "="
  lex:restore(mark)
  return is_assign
end

local function parse_root_item(lex, ctx)
  local tok = lex:peek()
  if tok.kind == "error" then lex:error_at(tok, tok.value) end
  if tok.value == "[" then return Decl.parse_decl_stream(lex, ctx) end
  if looks_like_meta_assign(lex) then return Decl.parse_meta_assign(lex, ctx, tok) end
  if rejected_lua_roots[tok.value] then reject_root(lex, tok) end
  local method_name = root_entries[tok.value]
  if method_name then
    local entry = lex:next()
    ctx.entry_token = entry
    return Decl[method_name](lex, ctx, entry)
  end
  lex:error_at(tok, ".lln documents are rooted at " .. ROOT_ROLE_DISPLAY .. "; expected root declaration (`fn`, `struct`, `union`, `handle`, `region`), meta assignment (`Type.metamethods.__name = hook`), or top-level `[generated]` declaration splice")
end

function Document.parse(source, chunkname, opts)
  opts = opts or {}
  local lex = Lexer.new(source or "", chunkname or "=(lalin .lln)", opts)
  local ctx = make_ctx(lex, opts)
  local body = {}
  lex:skip_separators()
  while not lex:at_eof() do
    body[#body + 1] = parse_root_item(lex, ctx)
    lex:skip_separators()
  end
  return P.ParsedDocument(body, source or "", chunkname or "=(lalin .lln)")
end

-- ═══════════════════════════════════════════════════════════
-- Materialize (name binding into env)
-- ═══════════════════════════════════════════════════════════

local function default_env()
  local ok_lalin, lalin = pcall(require, "lalin")
  if ok_lalin and lalin and lalin.dsl and type(lalin.dsl.make_env) == "function" then
    local ok_env, env = pcall(lalin.dsl.make_env, { no_namespaces = true })
    if ok_env and type(env) == "table" then return env end
  end
  return {}
end

local function merge_env(user_env)
  local base = default_env()
  if user_env == nil then return base end
  local out = {}
  for k, v in pairs(base) do out[k] = v end
  for k, v in pairs(user_env) do out[k] = v end
  return out
end

local function decl_name(decl)
  local cls = asdl.classof(decl)
  if cls == P.ParsedFunc or cls == P.ParsedStruct or cls == P.ParsedExtern
    or cls == P.ParsedUnion or cls == P.ParsedHandle then
    local name = decl.name
    if type(name) == "string" and name:match("^[_%a][_%w]*$") then return name end
  end
  return nil
end

local function decl_qualifier(decl)
  local cls = asdl.classof(decl)
  if cls == P.ParsedFunc or cls == P.ParsedExtern or cls == P.ParsedHandle then
    local q = decl.qualifier
    if q and #q > 0 then
      local parts = {}
      for i, n in ipairs(q) do parts[i] = n.name end
      return parts
    end
  end
  return nil
end

local function bind_named_decl(env, decl)
  local name = decl_name(decl)
  if name ~= nil then env[name] = decl end
  local qual = decl_qualifier(decl)
  if qual and #qual > 0 and name ~= nil then
    local target = env
    for i = 1, #qual do
      local key = qual[i]
      target = target[key]
      if target == nil then break end
    end
    if target ~= nil and type(target) == "table" then
      target[name] = decl
    end
  end
end

function Document.materialize(doc, opts)
  opts = copy_opts(opts)
  if type(doc) == "string" then doc = Document.parse(doc, opts.chunkname, opts) end
  local cls = asdl.classof(doc)
  if cls ~= P.ParsedDocument then
    error("lalin.syntax_v2.document.materialize expects a ParsedDocument", 2)
  end
  local env = merge_env(opts.env)
  local decls = {}
  for _, item in ipairs(doc.body or {}) do
    if llbl.is(item, "HostEval") then
      item:evaluate(env)
      local produced = item.value
      if type(produced) == "table" then
        if asdl.classof(produced) then
          decls[#decls + 1] = produced
        elseif produced[1] then
          for _, d in ipairs(produced) do decls[#decls + 1] = d end
        end
      end
    elseif asdl.classof(item) == P.ParsedMetaAssign then
      -- skip for now
    else
      bind_named_decl(env, item)
      decls[#decls + 1] = item
    end
  end
  return decls, env
end

-- ═══════════════════════════════════════════════════════════
-- to_module: convert ParsedDecl[] → Tree.Module
-- ═══════════════════════════════════════════════════════════

local function call_name(e)
  local cls = asdl.classof(e)
  if cls == Tr.ExprRef then
    local rcls = asdl.classof(e.ref)
    if rcls == B.ValueRefName then return e.ref.name end
  end
  return nil
end

local function contract_from_expr(expr)
  if not expr or asdl.classof(expr) ~= Tr.ExprCall then
    error("contract calls expected", 2)
  end
  local cname = call_name(expr.callee)
  if cname == "readonly" then return Tr.ContractReadonly(expr.args[1])
  elseif cname == "writeonly" then return Tr.ContractWriteonly(expr.args[1])
  elseif cname == "noalias" then return Tr.ContractNoAlias(expr.args[1])
  elseif cname == "invalidate" then return Tr.ContractInvalidate(expr.args[1])
  elseif cname == "preserve" then return Tr.ContractPreserve(expr.args[1]) end
  local callee = expr.callee
  if callee and asdl.classof(callee) == Tr.ExprCall then
    local inner_name = call_name(callee.callee)
    local outer = expr.args or {}
    local inner = callee.args or {}
    if inner_name == "bounds" then return Tr.ContractBounds(inner[1], outer[1])
    elseif inner_name == "disjoint" then return Tr.ContractDisjoint(inner[1], outer[1])
    elseif inner_name == "same_len" then return Tr.ContractSameLen(inner[1], outer[1]) end
  end
  error("unsupported contract expression", 2)
end

local function lower_stmt(stmt, named_env)
  if type(stmt) ~= "table" then return stmt end
  local cls = asdl.classof(stmt)
  if cls then return stmt end
  if stmt.tag == "StmtLet" then
    local binding = B.Binding(C.Id("parsed." .. stmt.name), stmt.name,
      resolve_type_source(stmt.type, named_env), B.BindingRoleLocalValue)
    return Tr.StmtLet(Tr.StmtSurface, binding, stmt.init or Tr.ExprLit(Tr.ExprSurface, C.LitInt("0")))
  elseif stmt.tag == "StmtVar" then
    local binding = B.Binding(C.Id("parsed." .. stmt.name), stmt.name,
      resolve_type_source(stmt.type, named_env), B.BindingRoleLocalValue)
    return Tr.StmtVar(Tr.StmtSurface, binding, stmt.init or Tr.ExprLit(Tr.ExprSurface, C.LitInt("0")))
  elseif stmt.tag == "StmtForRange" then
    -- Lower loop via for_to_loop (needs T context)
    local ftl = require("lalin.syntax_v2.for_to_loop")(require("lalin.schema_v2"))
    return ftl.lower(stmt)
  elseif stmt.tag == "StmtFold" or stmt.tag == "StmtScan" then
    error("to_module: " .. stmt.tag .. " may only appear directly inside a loop", 2)
  end
  return stmt
end

local function lower_stmts(stmts, named_env)
  local out = {}
  for _, s in ipairs(stmts or {}) do out[#out + 1] = lower_stmt(s, named_env) end
  return out
end

local function compiler_name(parsed, anon_counter)
  local nm = parsed.name
  if nm ~= nil and nm ~= "" then return nm end
  anon_counter[1] = anon_counter[1] + 1
  return "__lln_fn_" .. tostring(anon_counter[1])
end

local function qualified_compiler_name(parsed, anon_counter)
  local parts = {}
  local q = parsed.qualifier
  if q then for i, n in ipairs(q) do parts[#parts + 1] = n.name end end
  parts[#parts + 1] = compiler_name(parsed, anon_counter)
  return table.concat(parts, ".")
end

local function handle_repr(source, named_env)
  if source == nil or source == "" then return Ty.HandleReprScalar(C.ScalarU32) end
  local ty = resolve_type_source(source, named_env)
  if asdl.classof(ty) ~= Ty.TScalar then
    error("handle repr must be a scalar type such as `[u32]`", 2)
  end
  return Ty.HandleReprScalar(ty.scalar)
end

local function handle_type_ref(source, site, named_env)
  if source == nil or source == "" then
    error("handle " .. (site or "fact") .. " requires a named type such as `[Store]`", 2)
  end
  local ty = resolve_type_source(source, named_env)
  local cls = asdl.classof(ty)
  if cls == Ty.TNamed or cls == Ty.THandle then return ty.ref end
  error("handle " .. (site or "fact") .. " must be a named type", 2)
end

local function handle_invalid(raw)
  if raw == nil or raw == "" then return Ty.HandleInvalidNone end
  return Ty.HandleInvalidInt(tostring(raw))
end

local function decl_to_item(parsed, named_env, anon_counter)
  if not parsed then return nil end
  local cls = asdl.classof(parsed)
  if cls == P.ParsedFunc then
    local fname = compiler_name(parsed, anon_counter)
    local params = {}
    for i, p in ipairs(parsed.params or {}) do
      params[i] = Ty.Param(p.name, resolve_type_source(p.ty_source, named_env))
    end
    local result_ty = resolve_type_source(parsed.result_source, named_env)
    local body_src, contracts = {}, {}
    for _, stmt in ipairs(parsed.body or {}) do
      if type(stmt) == "table" and stmt.is_requires then
        for _, expr in ipairs(stmt.exprs or {}) do
          contracts[#contracts + 1] = contract_from_expr(expr)
        end
      else
        body_src[#body_src + 1] = stmt
      end
    end
    body_src = lower_stmts(body_src, named_env)
    if #body_src == 0 then
      body_src = { Tr.StmtReturnVoid(Tr.StmtSurface) }
    end
    local func_spec = #contracts > 0
      and Tr.FuncLocalContract(fname, params, result_ty, contracts, body_src)
      or Tr.FuncLocal(fname, params, result_ty, body_src)
    return Tr.ItemFunc(func_spec)
  elseif cls == P.ParsedExtern then
    local ename = qualified_compiler_name(parsed, anon_counter)
    local params = {}
    for i, p in ipairs(parsed.params or {}) do
      params[i] = Ty.Param(p.name, resolve_type_source(p.ty_source, named_env))
    end
    return Tr.ItemExtern(Tr.ExternFunc(ename, parsed.symbol or ename, params, resolve_type_source(parsed.result_source, named_env)))
  elseif cls == P.ParsedStruct then
    local fields = {}
    for i, f in ipairs(parsed.fields or {}) do
      fields[i] = Ty.FieldDecl(f.name, resolve_type_source(f.ty_source, named_env))
    end
    return Tr.ItemType(Tr.TypeDeclStruct(parsed.name, fields))
  elseif cls == P.ParsedUnion then
    local variants = {}
    for _, v in ipairs(parsed.variants or {}) do
      local vfields = {}
      for i, f in ipairs(v.fields or {}) do
        vfields[i] = Ty.FieldDecl(f.name, resolve_type_source(f.ty_source, named_env))
      end
      variants[#variants + 1] = Ty.VariantDecl(v.name, Ty.TScalar(C.ScalarVoid), vfields)
    end
    return Tr.ItemType(Tr.TypeDeclTaggedUnionSugar(parsed.name, variants))
  elseif cls == P.ParsedHandle then
    local facts = {}
    if parsed.domain_source ~= "" then
      facts[#facts + 1] = Ty.HandleDomain(handle_type_ref(parsed.domain_source, "handle domain", named_env))
    end
    if parsed.target_source ~= "" then
      facts[#facts + 1] = Ty.HandleTarget(handle_type_ref(parsed.target_source, "handle target", named_env))
    end
    return Tr.ItemType(Tr.TypeDeclHandle(
      qualified_compiler_name(parsed, anon_counter),
      handle_repr(parsed.repr_source, named_env),
      handle_invalid(parsed.invalid),
      facts))
  end
  error("to_module: unsupported ParsedDecl " .. tostring(cls), 2)
end

function Document.to_module(doc_or_decls, name)
  local decls, named_env
  local cls = asdl.classof(doc_or_decls)
  if cls == P.ParsedDocument then
    decls, named_env = Document.materialize(doc_or_decls)
  elseif type(doc_or_decls) == "table" and doc_or_decls[1] then
    -- Already an array of decls; materialize them
    -- Build a synthetic env by scanning for ParsedStruct etc.
    named_env = {}
    for _, d in ipairs(doc_or_decls) do
      local dname = decl_name(d)
      if dname then named_env[dname] = d end
    end
    decls = doc_or_decls
  else
    error("Document.to_module expects ParsedDocument or decl array", 2)
  end

  name = name or "module"
  local items = {}
  local anon_counter = { 0 }

  for _, d in ipairs(decls or {}) do
    local item = decl_to_item(d, named_env, anon_counter)
    if item then items[#items + 1] = item end
  end

  return Tr.Module(Tr.ModuleSurface, items)
end

-- ═══════════════════════════════════════════════════════════
-- Public API
-- ═══════════════════════════════════════════════════════════

function Document.load(source, chunkname, opts)
  local doc = Document.parse(source, chunkname, opts)
  return Document.to_module(doc, chunkname)
end

return Document
