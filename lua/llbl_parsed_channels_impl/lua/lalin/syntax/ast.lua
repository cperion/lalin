-- lalin.syntax.ast
-- Lightweight parsed-channel AST used by the Lalin syntax frontend.  In a full
-- repository integration, these nodes are the handoff point to LalinTree ASDL
-- builders or existing DSL heads.

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
  for k, v in pairs(x) do
    if k ~= "origin" and type(v) == "table" then
      if is_array(v) then
        for i = 1, #v do v[i] = Ast.walk(v[i], fn, x, k) end
      elseif v.tag then
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
  local code = "return (" .. src .. ")"
  local loader = loadstring or load
  if loadstring or _VERSION == "Lua 5.1" then
    local f, err = loader(code, name or "=(llbl host escape)")
    if not f then error(err, 0) end
    if setfenv then setfenv(f, merge_env(env)) end
    return f()
  else
    local f, err = load(code, name or "=(llbl host escape)", "t", merge_env(env))
    if not f then error(err, 0) end
    return f()
  end
end

function Ast.resolve_host_escapes(root, env)
  return Ast.walk(root, function(n)
    if n.tag == "HostEscape" and not n.resolved then
      n.value = Ast.eval_lua_expr(n.source, env, n.origin and n.origin.source)
      n.resolved = true
      return n
    end
  end)
end

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
