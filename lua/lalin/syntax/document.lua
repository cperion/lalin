-- lalin.syntax.document
--
-- .lln source is a Lalin declaration document rooted at the Lalin.decls role.
-- It is not a Lua value chunk: root Lua statements such as `local`, `return`,
-- `import`, and `module` are rejected here instead of being compatibility-
-- wrapped or sent through the mixed Lua+parsed syntax driver.

local llbl = require("llbl")
local Lexer = require("llbl.syntax.lexer")
local Ast = require("lalin.syntax.ast")
local Decl = require("lalin.syntax.decl")
local Exotype = require("lalin.exotype")

local Document = {}

local ROOT_ROLE = "decls"
local ROOT_ROLE_DISPLAY = "Lalin.decls"

local root_entries = {
  fn = "parse_fn",
  struct = "parse_struct",
  union = "parse_union",
  handle = "parse_handle",
  region = "parse_region",
  extern = "parse_extern",
}

local rejected_lua_roots = {
  ["local"] = "Lua `local` is not allowed",
  ["return"] = "Lua `return` is not allowed",
  ["import"] = "parse-time `import` is not allowed",
  ["module"] = "Lua `module` is not allowed",
}

local function copy_opts(opts)
  local out = {}
  if opts then for k, v in pairs(opts) do out[k] = v end end
  return out
end

local function make_ctx(lex, opts)
  opts = opts or {}
  local ctx = {
    refs = {},
    ref_seen = {},
    lex = lex,
    opts = opts,
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
  if tok.value == "unique" then
    error(llbl.diagnostic {
      code = "E_LALIN_UNSUPPORTED_UNIQUE",
      message = "`unique` declarations are not supported by the compiled Lalin surface",
      primary = Ast.origin(lex, tok, tok, "parsed:unsupported_unique"),
      notes = { "identity must be modeled explicitly; the compiler does not synthesize hidden identity maps" },
    }, 0)
  end
  if tok.kind == "error" then lex:error_at(tok, tok.value) end
  if tok.value == "[" then
    return Decl.parse_decl_stream(lex, ctx)
  end
  if looks_like_meta_assign(lex) then
    return Decl.parse_meta_assign(lex, ctx, tok)
  end
  if rejected_lua_roots[tok.value] then reject_root(lex, tok) end
  local method_name = root_entries[tok.value]
  if method_name then
    local entry = lex:next()
    ctx.entry_token = entry
    return Decl[method_name](lex, ctx, entry)
  end
  lex:error_at(tok, ".lln documents are rooted at " .. ROOT_ROLE_DISPLAY .. "; expected root declaration (`fn`, `struct`, `union`, `handle`, `region`), meta assignment (`Type.metamethods.__name = hook`), or top-level `[generated]` declaration splice")
end

local function document_origin(lex, body)
  local start_tok = body[1] and body[1].origin and nil or lex.tokens[1]
  start_tok = start_tok or lex.tokens[1] or lex:peek()
  local end_tok = lex.last or start_tok
  return Ast.origin(lex, start_tok, end_tok, "parsed:decl_document")
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

  local doc = Ast.node("DeclDocument", {
    role = ROOT_ROLE,
    root_role = ROOT_ROLE,
    role_display = ROOT_ROLE_DISPLAY,
    role_id = llbl.role_id("Lalin", ROOT_ROLE),
    body = body,
    refs = ctx.refs,
    source = source or "",
    chunkname = chunkname or "=(lalin .lln)",
    materialized = false,
  }, document_origin(lex, body))
  return doc
end

local function default_env()
  local ok_lalin, lalin = pcall(require, "lalin")
  if ok_lalin and lalin and lalin.dsl and type(lalin.dsl.make_env) == "function" then
    local ok_env, env = pcall(lalin.dsl.make_env, { no_namespaces = true })
    if ok_env and type(env) == "table" then return env end
  end

  local ok_dsl, dsl = pcall(require, "lalin.dsl")
  if ok_dsl and dsl and type(dsl.make_env) == "function" then
    local ok_env, env = pcall(dsl.make_env, { no_namespaces = true })
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

local function projected_adapter()
  local asdl = require("lalin.asdl")
  local T = asdl.context()
  require("lalin.schema_projection")(T)
  return require("lalin.syntax.role_adapter")(T)
end

local function binding_name(decl)
  if type(decl) ~= "table" then return nil end
  if type(decl.tag) ~= "string" or decl.tag:match("^Decl") == nil then return nil end
  local name = decl.name or decl.public_name or decl.debug_name
  if type(name) == "string" and name:match("^[_%a][_%w]*$") then return name end
  return nil
end

local function bind_named_decl(env, decl)
  if type(decl) == "table" and (decl.tag == "DeclStruct" or decl.tag == "DeclUnion" or decl.tag == "DeclHandle") then
    Exotype.ensure_owner(decl)
  end
  local name = binding_name(decl)
  local binding_value = decl
  if type(decl) == "table" and Exotype.is(decl.__lalin_exotype_owner) then
    binding_value = decl.__lalin_exotype_owner
    binding_value.__lalin_decl = binding_value.__lalin_decl or decl
  end
  if name ~= nil then env[name] = binding_value end
  -- Qualified declaration: fn/region/handle Point.name(...) -> set Point.name = decl
  if type(decl) == "table" and decl.qualifier and #decl.qualifier > 0 and name ~= nil then
    local target = env
    for i = 1, #decl.qualifier do
      local key = decl.qualifier[i]
      target = target[key]
      if target == nil then break end
    end
    if target ~= nil then
      Exotype.ensure_owner(target)
      target[name] = decl
      if decl.tag == "DeclFunc" and Exotype.is(target) then target.methods[name] = decl end
      if decl.tag == "DeclRegion" and Exotype.is(target) then target.regions[name] = decl end
      if decl.tag == "DeclHandle" and Exotype.is(target) then target.handles[name] = decl end
    end
  end
end

local function resolve_decl(env, decl)
  if type(decl) == "table" then
    bind_named_decl(env, decl)
    Ast.resolve_host_evals(decl, env)
    bind_named_decl(env, decl)
  end
  return decl
end

local function host_value(v, env)
  if llbl.is(v, "HostEval") then return llbl.host_eval.value(v, { env = env }) end
  if type(v) == "table" and v.tag == "HostEscape" then return v.value end
  return v
end

local function type_exotype(ptype, env)
  local value = host_value(ptype, env)
  if Exotype.is(value) then return value end
  if type(value) == "table" and Exotype.is(value.__lalin_exotype_owner) then return value.__lalin_exotype_owner end
  if llbl.is(ptype, "HostEval") then
    local found = nil
    for _, ref in ipairs(ptype.refs or {}) do
      local candidate = env and env[ref]
      if Exotype.is(candidate) then
        if found ~= nil and found ~= candidate then return nil end
        found = candidate
      end
    end
    if found ~= nil then return found end
  end
  return nil
end

local function is_decl(value)
  return type(value) == "table" and type(value.tag) == "string" and value.tag:match("^Decl") ~= nil
end

local function decl_list_from_property(value, adapter, ctx)
  if value == nil then return {} end
  if is_decl(value) or llbl.is(value, "HostEval") or llbl.is(value, "Fragment") or (type(value) == "table" and value.tag == "DeclDocument") then
    return adapter:decls(value, ctx)
  end
  if type(value) == "table" and not value.tag then return adapter:decls(value, ctx) end
  return {}
end

local function resolve_meta_ref(env, ref)
  if llbl.is(ref, "HostEval") then return llbl.host_eval.value(ref, { env = env }) end
  if type(ref) == "table" and ref.tag == "MetaRef" then
    local value = env
    for _, part in ipairs(ref.path or {}) do
      if value == nil then break end
      value = value[part]
    end
    if value == nil then
      error("lalin meta assignment: unresolved value `" .. table.concat(ref.path or {}, ".") .. "`", 2)
    end
    return value
  end
  return ref
end

local function apply_meta_assign(env, assign, adapter, ctx)
  local target_path = assign.target or {}
  local owner = env[target_path[1]]
  if owner == nil then
    error("lalin meta assignment: unresolved target owner `" .. tostring(target_path[1]) .. "`", 2)
  end
  Exotype.ensure_owner(owner)
  local target = owner
  for i = 2, #target_path - 1 do
    local key = target_path[i]
    local next_value = target[key]
    if next_value == nil then
      next_value = {}
      target[key] = next_value
    end
    if type(next_value) ~= "table" then
      error("lalin meta assignment: target prefix `" .. table.concat(target_path, ".", 1, i) .. "` is not a table", 2)
    end
    target = next_value
  end
  local final = target_path[#target_path]
  target[final] = resolve_meta_ref(env, assign.value)
  if target_path[#target_path - 1] == "metamethods" and final == "__getdecls" and Exotype.is(owner) then
    return decl_list_from_property(owner:query("__getdecls"), adapter, ctx)
  end
  return nil
end

local function synthesize_exotype_dependencies(decl, env, adapter, ctx, seen)
  local generated = {}
  local function add_generated(value)
    for _, d in ipairs(decl_list_from_property(value, adapter, ctx)) do
      local key = tostring(d.tag) .. ":" .. tostring(d.name) .. ":" .. table.concat(d.qualifier or {}, ".")
      if not seen[key] then
        seen[key] = true
        generated[#generated + 1] = d
      end
    end
  end

  local function scan_expr(expr, locals)
    if type(expr) ~= "table" or llbl.is(expr, "HostEval") then return end
    if expr.tag == "MethodCall" then
      local receiver = expr.receiver
      if receiver and receiver.tag == "Name" then
        local owner = locals[receiver.name]
        if Exotype.is(owner) then add_generated(owner:method(expr.name)) end
      end
      scan_expr(expr.receiver, locals)
      for _, a in ipairs(expr.args or {}) do scan_expr(a, locals) end
      return
    end
    if expr.tag == "Call" then
      scan_expr(expr.callee, locals)
      for _, a in ipairs(expr.args or {}) do scan_expr(a, locals) end
    elseif expr.tag == "Field" then
      scan_expr(expr.base, locals)
    elseif expr.tag == "Index" then
      scan_expr(expr.base, locals); scan_expr(expr.index, locals)
    elseif expr.tag == "BinOp" or expr.tag == "Cmp" then
      scan_expr(expr.left, locals); scan_expr(expr.right, locals)
    elseif expr.tag == "UnOp" then
      scan_expr(expr.value, locals)
    elseif expr.tag == "Record" or expr.tag == "StructCtor" then
      scan_expr(expr.callee, locals)
      for _, f in ipairs(expr.fields or {}) do scan_expr(f.value, locals) end
    elseif expr.tag == "Paren" then
      scan_expr(expr.value, locals)
    elseif expr.tag == "Cast" then
      scan_expr(expr.value, locals)
    end
  end

  local function scan_stmts(stmts, locals)
    for _, stmt in ipairs(stmts or {}) do
      if type(stmt) == "table" and not llbl.is(stmt, "HostEval") then
        if stmt.tag == "StmtLet" or stmt.tag == "StmtVar" then
          if stmt.init then scan_expr(stmt.init, locals) end
          local owner = type_exotype(stmt.type, env)
          if owner then locals[stmt.name] = owner end
        elseif stmt.tag == "StmtReturn" then
          for _, v in ipairs(stmt.values or {}) do scan_expr(v, locals) end
        elseif stmt.tag == "StmtExpr" then
          scan_expr(stmt.expr, locals)
        elseif stmt.tag == "StmtAssign" then
          scan_expr(stmt.place, locals); scan_expr(stmt.value, locals)
        elseif stmt.tag == "StmtIf" then
          scan_expr(stmt.cond, locals)
          scan_stmts(stmt.then_body, setmetatable({}, { __index = locals }))
          for _, eb in ipairs(stmt.elseif_blocks or {}) do
            scan_expr(eb.cond, locals)
            scan_stmts(eb.body, setmetatable({}, { __index = locals }))
          end
          scan_stmts(stmt.else_body, setmetatable({}, { __index = locals }))
        elseif stmt.tag == "StmtForRange" then
          for _, a in ipairs(stmt.args or {}) do scan_expr(a, locals) end
          local nested = setmetatable({}, { __index = locals })
          scan_stmts(stmt.body, nested)
        elseif stmt.tag == "StmtRequires" then
          for _, e in ipairs(stmt.exprs or {}) do scan_expr(e, locals) end
        elseif stmt.tag == "StmtJump" then
          for _, p in ipairs(stmt.payload or {}) do scan_expr(p.value, locals) end
        elseif stmt.tag == "StmtCall" or stmt.tag == "StmtEmit" then
          for _, a in ipairs(stmt.data_args or {}) do scan_expr(a, locals) end
        end
      end
    end
  end

  if type(decl) == "table" and decl.tag == "DeclFunc" then
    local locals = {}
    for _, p in ipairs(decl.params or {}) do
      local owner = type_exotype(p.type, env)
      if owner then locals[p.name] = owner end
    end
    scan_stmts(decl.body, locals)
  elseif type(decl) == "table" and decl.tag == "DeclRegion" then
    local locals = {}
    for _, p in ipairs(decl.inputs or {}) do
      local owner = type_exotype(p.type, env)
      if owner then locals[p.name] = owner end
    end
    for _, b in ipairs(decl.blocks or {}) do
      local block_locals = setmetatable({}, { __index = locals })
      for _, p in ipairs(b.state or {}) do
        local owner = type_exotype(p.type, env)
        if owner then block_locals[p.name] = owner end
      end
      scan_stmts(b.body, block_locals)
    end
  end
  return generated
end

function Document.materialize(doc, opts)
  opts = copy_opts(opts)
  if type(doc) == "string" then doc = Document.parse(doc, opts.chunkname, opts) end
  if type(doc) ~= "table" or doc.tag ~= "DeclDocument" then
    error("lalin.syntax.document.materialize expects a DeclDocument", 2)
  end

  local env = merge_env(opts.env)
  local adapter = opts.adapter or projected_adapter()
  local decls = {}
  local ctx = { env = env, document = doc, role = ROOT_ROLE, expected_role = ROOT_ROLE }
  local generated_seen = {}

  local append_decl
  append_decl = function(decl)
    decl = resolve_decl(env, decl)
    if type(decl) == "table" and decl.tag == "DeclMetaAssign" then
      local generated = apply_meta_assign(env, decl, adapter, ctx)
      for _, g in ipairs(generated or {}) do append_decl(g) end
      return
    end
    decls[#decls + 1] = decl
    if type(decl) == "table" and decl.tag and decl.name then
      generated_seen[tostring(decl.tag) .. ":" .. tostring(decl.name) .. ":" .. table.concat(decl.qualifier or {}, ".")] = true
    end
    local generated = synthesize_exotype_dependencies(decl, env, adapter, ctx, generated_seen)
    for _, g in ipairs(generated or {}) do append_decl(g) end
  end

  for _, item in ipairs(doc.body or {}) do
    if llbl.is(item, "HostEval") then
      local produced = adapter:decls(item, ctx)
      for _, decl in ipairs(produced or {}) do append_decl(decl) end
    else
      append_decl(item)
    end
  end

  doc.decls = decls
  doc.env = env
  doc.materialized = true
  return decls, doc
end

function Document.load(source, chunkname, opts)
  local doc = Document.parse(source, chunkname, opts)
  return Document.materialize(doc, opts)
end

return Document
