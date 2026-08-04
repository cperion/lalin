-- lalin.syntax.roles
-- Authoritative LLBL role descriptors for schema parsed HostEval values.

local llbl = require("llbl")
local T = require("lalin.schema")
local C, P, Tr, Ty = T.LalinCore, T.LalinParse, T.LalinTree, T.LalinType

function Ty.Type:parsed_host_type() return self end
function Tr.Expr:parsed_host_expr() return self end
function P.ParsedStmt:parsed_host_stmt() return self end
function Tr.Stmt:parsed_host_stmt() return P.StmtKnown(self) end
function P.ParsedDecl:parsed_host_decl() return self end
function P.ParsedField:parsed_host_product() return self end
function P.ParsedVariant:parsed_host_variant() return self end
function P.ParsedExit:parsed_host_cont() return self end

local function reject(role, value, origin)
  llbl.fail("host evaluation for " .. role .. " role produced unsupported value `"
    .. tostring(value) .. "`", {
      code = "E_LALIN_V2_ROLE_ADAPT",
      role = role,
      primary = origin or llbl.origin_of(value),
    }, 3)
end

local function one(role, method)
  return function(_, value, _, _, origin)
    if type(value) == "table" and type(value[method]) == "function" then
      return value[method](value)
    end
    reject(role, value, origin)
  end
end

local function many(role, method)
  return function(ctx, value, descriptor, _, origin)
    if llbl.is(value, "Fragment") then
      local expanded = {}
      local gen, param, state = llbl.role.splice(ctx, descriptor, value, origin)
      gen, param, state = llbl.gps.raw(gen, param, state)
      while true do
        local next_state, item = gen(param, state)
        if next_state == nil then break end
        state = next_state
        expanded[#expanded + 1] = item
      end
      value = expanded
    end
    if type(value) == "table" and type(value[method]) == "function" then
      return { value[method](value) }
    end
    if type(value) ~= "table" then reject(role, value, origin) end
    local out = {}
    for i = 1, #value do
      local item = value[i]
      if type(item) ~= "table" or type(item[method]) ~= "function" then
        reject(role, item, origin)
      end
      out[i] = item[method](item)
    end
    return out
  end
end

local function expr_adapter(_, value, _, _, origin)
  if type(value) == "table" and type(value.parsed_host_expr) == "function" then
    return value:parsed_host_expr()
  end
  if value == nil then return Tr.ExprLit(Tr.ExprSurface, C.LitNil) end
  local tv = type(value)
  if tv == "boolean" then return Tr.ExprLit(Tr.ExprSurface, C.LitBool(value)) end
  if tv == "string" then return Tr.ExprLit(Tr.ExprSurface, C.LitString(value)) end
  if tv == "number" then
    if value == value and value % 1 == 0 then
      return Tr.ExprLit(Tr.ExprSurface, C.LitInt(tostring(value)))
    end
    return Tr.ExprLit(Tr.ExprSurface, C.LitFloat(tostring(value)))
  end
  reject("expr", value, origin)
end

local function role_array(name, item, adapter)
  return { name = name, kind = "array", algebra = "list", item_role = item, adapter = adapter,
    splice_policy = { explicit = true, bare_fragment = true }, nil_policy = "reject" }
end

local Owner = require("lalin.dsl.init").language
local specs = {
  type = { kind = "type", adapter = one("type", "parsed_host_type"), nil_policy = "reject" },
  expr = { kind = "value", adapter = expr_adapter, nil_policy = "value" },
  value = { kind = "value", adapter = function(_, value) return value end, nil_policy = "value" },
  stmt = { kind = "value", adapter = one("stmt", "parsed_host_stmt"), nil_policy = "reject" },
  decl = { kind = "value", adapter = one("decl", "parsed_host_decl"), nil_policy = "reject" },
  product = { kind = "product", algebra = "product", adapter = many("product", "parsed_host_product"), nil_policy = "reject" },
  variant = { kind = "value", adapter = one("variant", "parsed_host_variant"), nil_policy = "reject" },
  cont = { kind = "value", adapter = one("cont", "parsed_host_cont"), nil_policy = "reject" },
  stmts = role_array("stmts", "stmt", many("stmts", "parsed_host_stmt")),
  decls = role_array("decls", "decl", many("decls", "parsed_host_decl")),
  variants = role_array("variants", "variant", many("variants", "parsed_host_variant")),
  conts = role_array("conts", "cont", many("conts", "parsed_host_cont")),
}
specs.variants.algebra = "sum"
specs.conts.algebra = "sum"

local descriptors = {}
for name, spec in pairs(specs) do
  descriptors[name] = llbl.role_descriptor(Owner, name, spec)
end

local M = { dialect = Owner, descriptors = descriptors }

function M.context(parse_ctx, event)
  return {
    dialect = Owner,
    env = parse_ctx and parse_ctx.host_env or nil,
    origin = event and event.origin or nil,
  }
end

function M.adapt(parse_ctx, role, event)
  local descriptor = assert(descriptors[role], "unknown schema LLBL role " .. tostring(role))
  return llbl.role.adapt(M.context(parse_ctx, event), descriptor, event,
    event and event.origin or nil)
end

return M
