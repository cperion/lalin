-- lalin.syntax.ast
-- Lightweight parsed-channel AST used by the Lalin syntax frontend.  In a full
-- repository integration, these nodes are the handoff point to LalinTree ASDL
-- builders or existing DSL heads.

local llbl = require("llbl")

local Ast = {}

function Ast.node(tag, fields, origin)
  fields = fields or {}
  fields.tag = tag
  if origin then fields.origin = origin end
  return fields
end

function Ast.origin(lex, start_tok, end_tok, channel)
  local o = lex:span(start_tok, end_tok or lex.last or start_tok)
  o.channel = channel
  return o
end

local lua_keywords = {
  ["and"] = true, ["break"] = true, ["do"] = true, ["else"] = true,
  ["elseif"] = true, ["end"] = true, ["false"] = true, ["for"] = true,
  ["function"] = true, ["if"] = true, ["in"] = true, ["local"] = true,
  ["nil"] = true, ["not"] = true, ["or"] = true, ["repeat"] = true,
  ["return"] = true, ["then"] = true, ["true"] = true, ["until"] = true,
  ["while"] = true,
}

function Ast.extract_refs(src)
  local refs, seen = {}, {}
  for name in tostring(src):gmatch("[%a_][%w_]*") do
    if not lua_keywords[name] and not seen[name] then
      seen[name] = true
      refs[#refs + 1] = name
    end
  end
  return refs
end

function Ast.add_refs(ctx, refs)
  for _, r in ipairs(refs or {}) do if ctx and ctx.add_ref then ctx:add_ref(r) end end
end

function Ast.host_eval(source_text, refs, origin, role, spec)
  spec = spec or {}
  spec.role = spec.role or role
  spec.expected_role = spec.expected_role or role
  spec.channel = spec.channel or "parsed:host_eval"
  return llbl.host_eval.parsed(source_text, refs or {}, nil, origin, spec)
end

function Ast.list(tag, items, origin)
  return Ast.node(tag, { items = items or {} }, origin)
end

local function is_array(t)
  if type(t) ~= "table" then return false end
  local n = 0
  for k, _ in pairs(t) do
    if type(k) ~= "number" then return false end
    if k > n then n = k end
  end
  return true
end

function Ast.walk(x, fn, parent, key)
  if type(x) ~= "table" then return x end
  local replaced = fn(x, parent, key)
  if replaced ~= nil then x = replaced end
  if llbl.is(x, "HostEval") then return x end
  for k, v in pairs(x) do
    if k ~= "origin"
      and k ~= "__lalin_decl"
      and k ~= "__lalin_exotype_owner"
      and k ~= "methods"
      and k ~= "regions"
      and k ~= "handles"
      and k ~= "metamethods"
      and k ~= "_property_cache"
      and k ~= "entries"
      and type(v) == "table" then
      if is_array(v) then
        for i = 1, #v do v[i] = Ast.walk(v[i], fn, x, k) end
      elseif v.tag or llbl.is(v, "HostEval") then
        x[k] = Ast.walk(v, fn, x, k)
      end
    end
  end
  return x
end

local function merge_env(env)
  env = env or {}
  return setmetatable({}, {
    __index = function(_, k)
      local v = env[k]
      if v ~= nil then return v end
      return _G[k]
    end,
    __newindex = env,
  })
end

function Ast.eval_lua_expr(src, env, name)
  local origin = name and { source = name } or nil
  return llbl.host_eval.parsed(src, {}, env, origin):evaluate()
end

function Ast.resolve_host_evals(root, env)
  return Ast.walk(root, function(n)
    if llbl.is(n, "HostEval") then
      n:evaluate(env)
      n.resolved = true -- legacy parsed HostEscape compatibility during migration
      return n
    end
    -- Temporary compatibility while parser sites migrate from HostEscape to
    -- LLBL HostEval.  Adaptation remains in later lowering/role phases.
    if n.tag == "HostEscape" and not n.resolved then
      n.value = Ast.eval_lua_expr(n.source, env, n.origin and n.origin.source)
      n.resolved = true
      return n
    end
  end)
end

Ast.resolve_host_escapes = Ast.resolve_host_evals

function Ast.dump(x, indent, seen)
  indent = indent or ""
  seen = seen or {}
  if type(x) ~= "table" then return tostring(x) end
  if seen[x] then return "<cycle>" end
  seen[x] = true
  local parts = { "{" }
  local keys = {}
  for k in pairs(x) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  for _, k in ipairs(keys) do
    if k ~= "origin" then
      parts[#parts + 1] = "\n" .. indent .. "  " .. tostring(k) .. " = " .. Ast.dump(x[k], indent .. "  ", seen) .. ","
    end
  end
  parts[#parts + 1] = "\n" .. indent .. "}"
  return table.concat(parts)
end

return Ast
