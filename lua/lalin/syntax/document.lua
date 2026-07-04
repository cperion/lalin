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

local Document = {}

local ROOT_ROLE = "decls"
local ROOT_ROLE_DISPLAY = "Lalin.decls"

local root_entries = {
  fn = "parse_fn",
  struct = "parse_struct",
  union = "parse_union",
  handle = "parse_handle",
  region = "parse_region",
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

local function parse_root_item(lex, ctx)
  local tok = lex:peek()
  if tok.kind == "error" then lex:error_at(tok, tok.value) end
  if tok.value == "[" then
    return Decl.parse_decl_stream(lex, ctx)
  end
  if rejected_lua_roots[tok.value] then reject_root(lex, tok) end
  local method_name = root_entries[tok.value]
  if method_name then
    local entry = lex:next()
    ctx.entry_token = entry
    return Decl[method_name](lex, ctx, entry)
  end
  lex:error_at(tok, ".lln documents are rooted at " .. ROOT_ROLE_DISPLAY .. "; expected root declaration (`fn`, `struct`, `union`, `handle`, `region`) or top-level `[generated]` declaration splice")
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
  local name = binding_name(decl)
  if name ~= nil then env[name] = decl end
end

local function resolve_decl(env, decl)
  if type(decl) == "table" then
    bind_named_decl(env, decl)
    Ast.resolve_host_evals(decl, env)
    bind_named_decl(env, decl)
  end
  return decl
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

  local function append_decl(decl)
    decl = resolve_decl(env, decl)
    decls[#decls + 1] = decl
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
