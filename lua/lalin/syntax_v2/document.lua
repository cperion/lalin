-- lalin.syntax_v2.document
-- .lln document parser, materializer, and module builder.
-- Parses .lln → ParsedDocument; materialize binds names into env;
-- to_module converts ParsedDecl → Tree.Module with resolved types.

local llbl = require("llbl")
local Lexer = require("llbl.syntax.lexer")
local Ast = require("lalin.syntax_v2.ast")
local Decl = require("lalin.syntax_v2.decl")
local TypeSyntax = require("lalin.syntax_v2.type")

-- Load schema_v2
require("lalin.schema_v2")
local asdl = require("lalin.asdl")
local P   = package.loaded["lalin.schema_v2.parse"]
local Tr  = package.loaded["lalin.schema_v2.tree"]
local C   = package.loaded["lalin.schema_v2.core"]
local B   = package.loaded["lalin.schema_v2.bind"]
local Ty  = package.loaded["lalin.schema_v2.type"]
require("lalin.syntax_v2.for_to_loop")(require("lalin.schema_v2"))
require("lalin.impl.tree_region")

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
-- Parse
-- ═══════════════════════════════════════════════════════════

local function copy_opts(opts)
  local out = {}
  if opts then for k, v in pairs(opts) do out[k] = v end end
  return out
end
local function parsed_host_env(user_env)
  local base = {}
  TypeSyntax.extend_host_env(base)
  if user_env == nil then return base end
  local env = {}
  for k, v in pairs(base) do env[k] = v end
  for k, v in pairs(user_env) do env[k] = v end
  return env
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
    host_env = parsed_host_env(opts.env),
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

function P.ParsedDecl:bind_parsed_host_name(_env) end
local function bind_parsed_host_type(decl, env)
  env[decl.name] = TypeSyntax.named_symbol(decl.name)
end
function P.ParsedStruct:bind_parsed_host_name(env) bind_parsed_host_type(self, env) end
function P.ParsedUnion:bind_parsed_host_name(env) bind_parsed_host_type(self, env) end
function P.ParsedHandle:bind_parsed_host_name(env) bind_parsed_host_type(self, env) end
function P.ParsedDeclGroup:bind_parsed_host_name(env)
  for i = 1, #self.decls do self.decls[i]:bind_parsed_host_name(env) end
end

function Document.parse(source, chunkname, opts)
  opts = opts or {}
  local lex = Lexer.new(source or "", chunkname or "=(lalin .lln)", opts)
  local ctx = make_ctx(lex, opts)
  local body = {}
  lex:skip_separators()
  while not lex:at_eof() do
    local item = parse_root_item(lex, ctx)
    body[#body + 1] = item
    item:bind_parsed_host_name(ctx.host_env)
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
      for i, n in ipairs(q) do parts[i] = n.text end
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

function P.ParsedDecl:materialize_parsed_decl(env, decls)
  bind_named_decl(env, self)
  decls[#decls + 1] = self
end
function P.ParsedDeclGroup:materialize_parsed_decl(env, decls)
  for i = 1, #self.decls do self.decls[i]:materialize_parsed_decl(env, decls) end
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
    item:materialize_parsed_decl(env, decls)
  end
  return decls, env
end

-- ═══════════════════════════════════════════════════════════
-- to_module: convert ParsedDecl[] → Tree.Module
-- ═══════════════════════════════════════════════════════════

-- Contract lowering is leaf-owned: each typed ParsedContract leaf on the
-- requires statement produces its FuncContract via parsed_contract_value.

function P.StmtKnown:lower_parsed_stmt(_named_env)
  return P.ParsedStmtBodyResolved({ self.stmt })
end
function P.StmtLetParsed:lower_parsed_stmt(named_env)
  local binding = B.Binding(C.Id("parsed." .. self.name), self.name,
    self.ty, B.BindingRoleLocalValue)
  return P.ParsedStmtBodyResolved({ Tr.StmtLet(Tr.StmtSurface, binding, self.init) })
end
function P.StmtVarParsed:lower_parsed_stmt(named_env)
  local binding = B.Binding(C.Id("parsed." .. self.name), self.name,
    self.ty, B.BindingRoleLocalValue)
  return P.ParsedStmtBodyResolved({ Tr.StmtVar(Tr.StmtSurface, binding, self.init) })
end
function P.StmtRequiresParsed:lower_parsed_stmt(_named_env)
  return P.ParsedStmtBodyRejected("requires may only occur in a declaration contract prefix")
end
function P.ParsedLoopSink:resolve_parsed_loop_sink(_named_env)
  error("missing parsed loop sink resolution", 2)
end
function P.ParsedLoopNoSink:resolve_parsed_loop_sink(_named_env)
  return P.ParsedResolvedLoopNoSink
end
function P.ParsedLoopFoldSink:resolve_parsed_loop_sink(named_env)
  return P.ParsedResolvedLoopFoldSink(self.name,
    self.ty, self.init, self.reducer, self.step)
end
function P.ParsedLoopScanSink:resolve_parsed_loop_sink(named_env)
  return P.ParsedResolvedLoopScanSink(self.name,
    self.ty, self.init, self.reducer,
    self.axis, self.step, self.into)
end

local lower_stmts
function P.ParsedStmtGroup:lower_parsed_stmt(named_env)
  return lower_stmts(self.stmts, named_env)
end
function P.StmtLoopParsed:lower_parsed_stmt(named_env)
  return lower_stmts(self.body, named_env):parsed_loop_body_input(
    P.ParsedLoopLowerInput(self.loop_id, self.indexes, self.domain, {},
      self.sink:resolve_parsed_loop_sink(named_env)))
end
function P.ParsedStmtBodyResolved:parsed_loop_body_input(input)
  return P.ParsedLoopLowerInput(input.loop_id, input.indexes, input.domain, self.stmts, input.sink)
    :lower_parsed_loop():parsed_loop_stmt():parsed_loop_stmt_body()
end
function P.ParsedStmtBodyRejected:parsed_loop_body_input(_input)
  return self
end
function P.ParsedLoopStmtResolved:parsed_loop_stmt_body()
  return P.ParsedStmtBodyResolved({ self.stmt })
end
function P.ParsedLoopStmtRejected:parsed_loop_stmt_body()
  return P.ParsedStmtBodyRejected(self.reason)
end
function P.StmtFoldParsed:lower_parsed_stmt(_named_env)
  return P.ParsedStmtBodyRejected("fold may only appear directly inside a loop")
end
function P.StmtScanParsed:lower_parsed_stmt(_named_env)
  return P.ParsedStmtBodyRejected("scan may only appear directly inside a loop")
end

lower_stmts = function(stmts, named_env)
  local accumulated = P.ParsedStmtBodyResolved({})
  for _, s in ipairs(stmts or {}) do
    accumulated = s:lower_parsed_stmt(named_env):parsed_loop_body_continue(accumulated)
  end
  return accumulated
end
function P.ParsedStmtBodyResolved:parsed_loop_body_continue(accumulated)
  local stmts = {}
  for i = 1, #accumulated.stmts do stmts[i] = accumulated.stmts[i] end
  for i = 1, #self.stmts do stmts[#stmts + 1] = self.stmts[i] end
  return P.ParsedStmtBodyResolved(stmts)
end
function P.ParsedStmtBodyRejected:parsed_loop_body_continue(_accumulated)
  return self
end
function P.ParsedStmtBodyResolved:parsed_func_body(_fname)
  return self.stmts
end
function P.ParsedStmtBodyRejected:parsed_func_body(fname)
  error("to_module: function `" .. fname .. "` rejected: " .. self.reason, 2)
end

function P.ParsedStmtBodyResolved:parsed_region_body(_region_name) return self.stmts end
function P.ParsedStmtBodyRejected:parsed_region_body(region_name)
  error("to_module: region `" .. region_name .. "` rejected: " .. self.reason, 2)
end

-- The parse boundary materializes the prepared name environment as typed
-- entries (name -> ParsedDecl), deterministically ordered, so no loose
-- table crosses into the ASDL assembly methods.
local function parsed_region_body_env(named_env)
  local names = {}
  for name, decl in pairs(named_env or {}) do
    if type(name) == "string" and type(decl) == "table" and asdl.isa(decl, P.ParsedDecl) then
      names[#names + 1] = name
    end
  end
  table.sort(names)
  local entries = {}
  for i = 1, #names do entries[i] = P.ParsedNameEntry(names[i], named_env[names[i]]) end
  return P.ParsedRegionBodyEnv(entries)
end

local function lowered_region_body(body, input)
  return lower_stmts(body or {}, input.body_env):parsed_region_body(input.region_name)
end

local function retarget_region_body(stmts, retarget_input)
  local out = {}
  for i = 1, #(stmts or {}) do out[i] = stmts[i]:region_retarget_cont(retarget_input) end
  return out
end

local function append_control_block(blocks, block)
  local out = {}
  for i = 1, #(blocks or {}) do out[i] = blocks[i] end
  out[#out + 1] = block
  return out
end

-- ─────────────────────────────────────────────────────────────
-- ParsedFuncBody lowering: leaf-owned, typed partition and control form.
-- ─────────────────────────────────────────────────────────────
-- Each ParsedStmt leaf contributes either declaration contracts or a
-- body statement through a typed partition; the partition leaves own the
-- fold into ParsedFuncPartitionResult; the body leaf then lowers that
-- partition into the final ParsedFuncLowerResult.
function P.ParsedStmt:parsed_func_partition() return P.ParsedStmtFunctionBody(self) end
function P.StmtRequiresParsed:parsed_func_partition()
  return P.ParsedStmtFunctionContracts(self:parsed_contract_values())
end
function P.ParsedStmtFunctionContracts:parsed_func_partition_fold(result)
  local contracts = {}
  for i = 1, #(result.contracts or {}) do contracts[i] = result.contracts[i] end
  for i = 1, #(self.contracts or {}) do contracts[#contracts + 1] = self.contracts[i] end
  return P.ParsedFuncPartitionResult(contracts, result.body)
end
function P.ParsedStmtFunctionBody:parsed_func_partition_fold(result)
  local body = {}
  for i = 1, #(result.body or {}) do body[i] = result.body[i] end
  body[#body + 1] = self.stmt
  return P.ParsedFuncPartitionResult(result.contracts, body)
end

function P.ParsedFuncBody:parsed_func_lower(_input)
  error("missing parsed function body lowering", 2)
end
function P.ParsedFuncBodyLinear:parsed_func_lower(input)
  local result = P.ParsedFuncLowerResult({}, {})
  for i = 1, #(self.body or {}) do
    result = self.body[i]:parsed_func_partition():parsed_func_partition_fold(result)
  end
  local body_stmts = lower_stmts(result.body, input.body_env):parsed_func_body(input.fname)
  if #body_stmts == 0 then
    body_stmts = { Tr.StmtReturnVoid(Tr.StmtSurface) }
  end
  return P.ParsedFuncLowerResult(result.contracts, body_stmts)
end
function P.ParsedFuncBodyControl:parsed_func_lower(input)
  local entry = self.entry:parsed_func_control_entry(input)
  local blocks = {}
  for i = 1, #(self.blocks or {}) do
    blocks[i] = self.blocks[i]:parsed_func_control_block(input)
  end
  local control = Tr.StmtControl(Tr.StmtSurface, Tr.ControlStmtRegion(self.region_id, entry, blocks))
  return P.ParsedFuncLowerResult({}, { control })
end

-- Function control blocks reuse the typed region block shape and the
-- parsed field/param conversions; they do not retarget continuations
-- because functions carry no continuations.
function P.ParsedRegionEntryBlock:parsed_func_control_entry(input)
  local state = {}
  for i = 1, #(self.state or {}) do state[i] = self.state[i]:parsed_entry_block_param() end
  local body = lower_stmts(self.body or {}, input.body_env):parsed_func_body(input.fname)
  return Tr.EntryControlBlock(Tr.BlockLabel(self.name), state, body)
end
function P.ParsedRegionBodyBlock:parsed_func_control_block(input)
  local state = {}
  for i = 1, #(self.state or {}) do state[i] = self.state[i]:parsed_block_param() end
  local body = lower_stmts(self.body or {}, input.body_env):parsed_func_body(input.fname)
  return Tr.ControlBlock(Tr.BlockLabel(self.name), state, body)
end

-- Each ParsedRegionBlock leaf assembles itself into the typed assembly
-- state machine; the assembly leaves own the state transitions.
function P.ParsedRegionBlock:parsed_region_accumulate(_assembly, _input)
  error("missing parsed region block accumulation", 2)
end
function P.ParsedRegionEntryBlock:parsed_region_accumulate(assembly, input)
  return assembly:parsed_region_block_accept_entry(self:parsed_region_entry_block(input), input)
end
function P.ParsedRegionBodyBlock:parsed_region_accumulate(assembly, input)
  return assembly:parsed_region_block_accept_body(self:parsed_region_control_block(input), input)
end

function P.ParsedRegionEntryBlock:parsed_region_entry_block(input)
  local state = {}
  for i = 1, #(self.state or {}) do state[i] = self.state[i]:parsed_entry_block_param() end
  local body = lowered_region_body(self.body, input)
  return Tr.EntryControlBlock(Tr.BlockLabel(self.name), state, retarget_region_body(body, input.retarget))
end

function P.ParsedRegionBodyBlock:parsed_region_control_block(input)
  local state = {}
  for i = 1, #(self.state or {}) do state[i] = self.state[i]:parsed_block_param() end
  local body = lowered_region_body(self.body, input)
  return Tr.ControlBlock(Tr.BlockLabel(self.name), state, retarget_region_body(body, input.retarget))
end

function P.ParsedRegionBlockAssemblyWaiting:parsed_region_block_accept_entry(entry, _input)
  -- Body blocks seen before the entry are retained as region blocks.
  return P.ParsedRegionBlockAssemblyHasEntry(entry, self.blocks)
end
function P.ParsedRegionBlockAssemblyHasEntry:parsed_region_block_accept_entry(entry, _input)
  -- A second entry block is not the region entry; it assembles as a body
  -- control block so the control analyzer reports any duplicate label as
  -- a typed rejection.
  return P.ParsedRegionBlockAssemblyHasEntry(self.entry, append_control_block(self.blocks, entry:parsed_region_control_block_view()))
end
function P.ParsedRegionBlockAssemblyWaiting:parsed_region_block_accept_body(block, _input)
  return P.ParsedRegionBlockAssemblyWaiting(append_control_block(self.blocks, block))
end
function P.ParsedRegionBlockAssemblyHasEntry:parsed_region_block_accept_body(block, _input)
  return P.ParsedRegionBlockAssemblyHasEntry(self.entry, append_control_block(self.blocks, block))
end

-- Typed finalize: a region with no declared entry block receives the
-- canonical empty entry; HasEntry finalizes as itself.
function P.ParsedRegionBlockAssemblyWaiting:parsed_region_block_assembly_finalize(_input)
  return P.ParsedRegionBlockAssemblyHasEntry(Tr.EntryControlBlock(Tr.BlockLabel("entry"), {}, {}), self.blocks)
end
function P.ParsedRegionBlockAssemblyHasEntry:parsed_region_block_assembly_finalize(_input) return self end

function P.ParsedRegion:parsed_region_compiler_name(anon_counter)
  local parts = {}
  if self.qualifier then
    for i, n in ipairs(self.qualifier) do parts[#parts + 1] = n.text end
  end
  local nm = self.name
  if nm == nil or nm == "" then
    anon_counter[1] = anon_counter[1] + 1
    nm = "__lln_region_" .. tostring(anon_counter[1])
  end
  parts[#parts + 1] = nm
  return table.concat(parts, ".")
end

function P.ParsedRegion:region_to_item(input)
  local rname = input.region_name
  local params = {}
  for i = 1, #(self.inputs or {}) do
    local p = self.inputs[i]
    params[i] = Ty.Param(p.name, p.ty)
  end
  local conts = {}
  for i = 1, #(self.exits or {}) do
    conts[i] = self.exits[i]:parsed_region_cont(P.ParsedRegionContInput(rname, i))
  end
  local retarget = P.ParsedRegionRetargetInput(self:parsed_cont_projection(conts))
  local body_input = P.ParsedRegionBodyInput(rname, retarget, input.body_env)
  local assembly = P.ParsedRegionBlockAssemblyWaiting({})
  for i = 1, #(self.blocks or {}) do
    assembly = self.blocks[i]:parsed_region_accumulate(assembly, body_input)
  end
  local finalized = assembly:parsed_region_block_assembly_finalize(body_input)
  local contracts = {}
  for i = 1, #(self.contracts or {}) do
    local lowered = self.contracts[i]:parsed_contract_values()
    for j = 1, #lowered do contracts[#contracts + 1] = lowered[j] end
  end
  return Tr.ItemRegion(Tr.Region(rname, params, conts, contracts, finalized.entry, finalized.blocks))
end

-- Leaf-owned ParsedDecl lowering.  The remaining pre-existing decl kinds
-- are handled by the established classof chain in decl_to_item; ParsedRegion
-- owns its item lowering through this leaf method with a typed assembly
-- input instead of adding another dispatch branch.
function P.ParsedDecl:parsed_decl_to_item(_named_env, _anon_counter)
  error("to_module: unsupported ParsedDecl " .. tostring(asdl.classof(self)), 2)
end
function P.ParsedRegion:parsed_decl_to_item(named_env, anon_counter)
  local rname = self:parsed_region_compiler_name(anon_counter)
  return self:region_to_item(P.ParsedRegionAssemblyInput(rname, parsed_region_body_env(named_env)))
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
  if q then for i, n in ipairs(q) do parts[#parts + 1] = n.text end end
  parts[#parts + 1] = compiler_name(parsed, anon_counter)
  return table.concat(parts, ".")
end

function Ty.Type:parsed_handle_repr()
  error("handle repr must be a scalar type such as `[u32]`", 2)
end
function Ty.TScalar:parsed_handle_repr() return Ty.HandleReprScalar(self.scalar) end
local function handle_repr(ty)
  if ty == nil then return Ty.HandleReprScalar(C.ScalarU32) end
  return ty:parsed_handle_repr()
end

function Ty.Type:parsed_handle_type_ref(site)
  error("handle " .. (site or "fact") .. " must be a named type", 2)
end
function Ty.TNamed:parsed_handle_type_ref(_site) return self.ref end
function Ty.THandle:parsed_handle_type_ref(_site) return self.ref end
local function handle_type_ref(ty, site)
  if ty == nil then
    error("handle " .. (site or "fact")
      .. " requires a named type such as `[Store]`", 2)
  end
  return ty:parsed_handle_type_ref(site)
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
      params[i] = Ty.Param(p.name, p.ty)
    end
    local result_ty = parsed.result_ty
    local result_ty = parsed.result_ty
    local lowered = parsed.body:parsed_func_lower(
      P.ParsedFuncLowerInput(fname, parsed_region_body_env(named_env)))
    local func_spec = #lowered.contracts > 0
      and Tr.FuncLocalContract(fname, params, result_ty, lowered.contracts, lowered.body)
      or Tr.FuncLocal(fname, params, result_ty, lowered.body)
    return Tr.ItemFunc(func_spec)
  elseif cls == P.ParsedExtern then
    local ename = qualified_compiler_name(parsed, anon_counter)
    local params = {}
    for i, p in ipairs(parsed.params or {}) do
      params[i] = Ty.Param(p.name, p.ty)
    end
    return Tr.ItemExtern(Tr.ExternFunc(ename, parsed.symbol or ename, params, parsed.result_ty))
  elseif cls == P.ParsedStruct then
    local fields = {}
    for i, f in ipairs(parsed.fields or {}) do
      fields[i] = Ty.FieldDecl(f.name, f.ty)
    end
    return Tr.ItemType(Tr.TypeDeclStruct(parsed.name, fields))
  elseif cls == P.ParsedUnion then
    local variants = {}
    for _, v in ipairs(parsed.variants or {}) do
      local vfields = {}
      for i, f in ipairs(v.fields or {}) do
        vfields[i] = Ty.FieldDecl(f.name, f.ty)
      end
      variants[#variants + 1] = Ty.VariantDecl(v.name, Ty.TScalar(C.ScalarVoid), vfields)
    end
    return Tr.ItemType(Tr.TypeDeclTaggedUnionSugar(parsed.name, variants))
  elseif cls == P.ParsedHandle then
    local facts = {}
    if parsed.domain_ty ~= nil then
      facts[#facts + 1] = Ty.HandleDomain(
        handle_type_ref(parsed.domain_ty, "handle domain"))
    end
    if parsed.target_ty ~= nil then
      facts[#facts + 1] = Ty.HandleTarget(
        handle_type_ref(parsed.target_ty, "handle target"))
    end
    return Tr.ItemType(Tr.TypeDeclHandle(
      qualified_compiler_name(parsed, anon_counter),
      handle_repr(parsed.repr_ty),
      handle_invalid(parsed.invalid),
      facts))
  end
  -- Remaining ParsedDecl leaves own their item lowering.
  return parsed:parsed_decl_to_item(named_env, anon_counter)
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
