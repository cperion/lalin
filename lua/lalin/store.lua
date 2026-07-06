-- lalin.store
--
-- Host-side store protocol policies.  These are ordinary Lua functions used by
-- parsed type meta-properties, e.g.:
--
--   TokenStore.store.target = Token
--   TokenStore.metamethods.__getdecls = arena_store
--
-- The policy returns parsed declarations.  The compiled Lalin artifact sees
-- explicit handles, regions, and functions; there is no runtime generic store.

local Ast = require("lalin.syntax.ast")
local Exotype = require("lalin.exotype")

local Store = {}

local function origin()
  return nil
end

local function type_host(source)
  return Ast.host_eval(source, Ast.extract_refs(source), origin(), "type")
end

local function name_expr(name)
  return Ast.node("Name", { name = name }, origin())
end

local function field_expr(base, name)
  return Ast.node("Field", { base = base, name = name }, origin())
end

local function bin_expr(op, left, right)
  return Ast.node("BinOp", { op = op, left = left, right = right }, origin())
end

local function lit_num(n)
  return Ast.node("Literal", { kind = "number", source = tostring(n), value = tonumber(n) }, origin())
end

local function stmt_return(expr)
  return Ast.node("StmtReturn", { values = expr and { expr } or {} }, origin())
end

local function stmt_requires_preserve_self()
  return Ast.node("StmtRequires", {
    exprs = {
      Ast.node("Call", {
        callee = Ast.node("Name", { name = "preserve" }, origin()),
        args = { name_expr("self") },
      }, origin()),
    },
  }, origin())
end

local function stmt_jump(target, fields)
  local payload = {}
  for i, name in ipairs(fields or {}) do
    payload[i] = { key = name, value = name_expr(name), shorthand = true }
  end
  return Ast.node("StmtJump", { target = target, payload = payload }, origin())
end

local function block(tag, name, state, body)
  return Ast.node(tag, { name = name, state = state or {}, body = body or {} }, origin())
end

local function field(name, ty)
  return Ast.node("Field", { name = name, type = type_host(ty), anonymous = false }, origin())
end

local function store_name(store)
  return Exotype.typename(store)
end

local function target_name(store)
  local spec = rawget(store, "store") or {}
  local target = spec.target or spec.record or spec.element or spec.value
  if target == nil then
    error("arena_store requires Store.store.target = Target", 2)
  end
  return Exotype.typename(target)
end

local function ref_type(sname)
  return 'named("' .. sname .. '.Ref")'
end

local function ptr_type(name)
  return "ptr [" .. name .. "]"
end

local function readonly_ptr_type(name)
  return "readonly [ptr [" .. name .. "]]"
end

local function invalidate_ptr_type(name)
  return "invalidate [ptr [" .. name .. "]]"
end

local function lease_ptr_type(origin_name, target)
  return 'lease("' .. origin_name .. '", ptr [' .. target .. '])'
end

local function handle_ref(store)
  local sname = store_name(store)
  local tname = target_name(store)
  return Ast.node("DeclHandle", {
    name = "Ref",
    qualifier = { sname },
    repr = type_host("u32"),
    invalid = "0",
    domain = type_host(sname),
    target = type_host(tname),
    exotype_generated = "arena_store",
  }, origin())
end

local function borrow_region(store)
  local sname = store_name(store)
  local tname = target_name(store)
  local ref = ref_type(sname)
  return Ast.node("DeclRegion", {
    name = "borrow",
    qualifier = { sname },
    inputs = {
      field("self", readonly_ptr_type(sname)),
      field("ref", ref),
    },
    exits = {
      Ast.node("Exit", { name = "borrowed", fields = { field("record", lease_ptr_type("self", tname)) } }, origin()),
      Ast.node("Exit", { name = "stale", fields = { field("ref", ref) } }, origin()),
      Ast.node("Exit", { name = "missing", fields = { field("ref", ref) } }, origin()),
    },
    blocks = {
      block("RegionEntry", "start", {}, { stmt_jump("missing", { "ref" }) }),
    },
    exotype_generated = "arena_store",
  }, origin())
end

local function compact_region(store)
  local sname = store_name(store)
  return Ast.node("DeclRegion", {
    name = "compact",
    qualifier = { sname },
    inputs = { field("self", invalidate_ptr_type(sname)) },
    exits = {
      Ast.node("Exit", { name = "done", fields = {} }, origin()),
      Ast.node("Exit", { name = "busy", fields = {} }, origin()),
    },
    blocks = {
      block("RegionEntry", "start", {}, { stmt_jump("done") }),
    },
    exotype_generated = "arena_store",
  }, origin())
end

local function capacity_left_func(store)
  local sname = store_name(store)
  local self = name_expr("self")
  local capacity = field_expr(self, "capacity")
  local count = field_expr(self, "count")
  return Ast.node("DeclFunc", {
    name = "capacity_left",
    qualifier = { sname },
    params = { field("self", ptr_type(sname)) },
    result = type_host("index"),
    body = { stmt_requires_preserve_self(), stmt_return(bin_expr("sub", capacity, count)) },
    exotype_generated = "arena_store",
  }, origin())
end

local function len_func(store)
  local sname = store_name(store)
  return Ast.node("DeclFunc", {
    name = "len",
    qualifier = { sname },
    params = { field("self", ptr_type(sname)) },
    result = type_host("index"),
    body = { stmt_requires_preserve_self(), stmt_return(field_expr(name_expr("self"), "count")) },
    exotype_generated = "arena_store",
  }, origin())
end

function Store.arena_store(store)
  Exotype.ensure_owner(store)
  store.store = store.store or {}
  store.handles = store.handles or {}
  store.regions = store.regions or {}
  store.methods = store.methods or {}

  local decls = {
    handle_ref(store),
    borrow_region(store),
    compact_region(store),
    capacity_left_func(store),
    len_func(store),
  }

  for _, decl in ipairs(decls) do
    if decl.tag == "DeclHandle" then store.handles[decl.name] = decl end
    if decl.tag == "DeclRegion" then store.regions[decl.name] = decl end
    if decl.tag == "DeclFunc" then store.methods[decl.name] = decl end
  end

  return decls
end

return Store
