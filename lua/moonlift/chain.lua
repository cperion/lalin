---moon.chain: the universal applicative API constructor.
---
---A chain is a callable table whose __call dispatches on argument type:
---  string          → parse ([[...]] quote)
---  string-keyed {} → binder (returns function(src))
---  array-keyed {}  → builder (calls table_fn)
---
---Each step returns another chain carrying accumulated state. The terminal
---is when an ASDL value is produced.
---
---Config fields:
---  name      – for error messages
---  parse     – function(T, src) → { value, issues, splice_slots }
---  wrap      – function(value, parsed, T, src, bindings?) → final value
---  expand    – function(e, value, env) → expanded value (binder+quote only)
---  table_fn  – function(arg) → value (array-keyed table call, builder form)
---
---Usage:
---  local chain = require("moonlift.chain")
---  local ch = chain.bind(session, callable_mt)
---  local my_api = ch.make { name = "my_api", parse = ..., wrap = ... }
---
---  -- Then:
---  my_api[[src]]            -- pure quote
---  my_api{key = val}[[src]] -- binder (susbes @{key})
---  my_api{array}            -- builder
---
---@module moonlift.chain

local M = {}

local function source_offset_from_line_col(src, line, col)
  src = src or ""
  line = math.max(1, tonumber(line) or 1)
  col = math.max(1, tonumber(col) or 1)
  local cur_line, cur_col = 1, 1
  for i = 1, #src do
    if cur_line == line and cur_col == col then
      return i
    end
    local b = string.byte(src, i)
    if b == 10 then
      if cur_line == line then return i end
      cur_line = cur_line + 1
      cur_col = 1
    else
      cur_col = cur_col + 1
    end
  end
  return #src + 1
end

local function render_parse_issue(T, issue, quote_src, origin)
  if not origin or not origin.__moonlift_source then
    return issue.message
  end

  local source = origin.__moonlift_source
  local source_text = source.source_text or source.text or ""
  local uri = source.uri or "?"
  local rel_line = math.max(1, tonumber(issue.line) or 1)
  local rel_col = math.max(1, tonumber(issue.col) or 1)
  local line = (tonumber(origin.start_line) or 1) + rel_line - 1
  local col = rel_col
  if rel_line == 1 then
    col = (tonumber(origin.start_col) or 1) + rel_col - 1
  end
  local offset_1 = source_offset_from_line_col(source_text, line, col)
  local remapped = {
    message = issue.message,
    offset = offset_1,
    line = line,
    col = col,
  }

  local ok, rendered = pcall(function()
    local Parse = require("moonlift.parse")
    local Errors = require("moonlift.error")
    local report = Parse.explain_parse_issue(remapped, {
      source_text = source_text,
      uri = uri,
    })
    return Errors.Terminal.render(report, source_text)
  end)
  if ok and rendered and rendered ~= "" then
    return rendered
  end
  return tostring(uri) .. ":" .. tostring(line) .. ":" .. tostring(col) .. ": " .. tostring(issue.message)
end

local function raise_parse_issue(T, parsed, src, level, origin)
  local issue = parsed and parsed.issues and parsed.issues[1]
  if not issue then
    error("parse failed", level or 2)
  end
  if origin then
    error(render_parse_issue(T, issue, src, origin), 0)
  end
  error(issue.message, level or 2)
end

---Bind a chain factory to a session context.
---@param session   table  Host session with `.T` ASDL context.
---@param callable_mt table? Optional metatable for CallableFunc detection.
---@return { make = fun(config), make_quote = fun(parse, wrap, expand, table_fn) }
function M.bind(session, callable_mt)
  assert(session and session.T, "chain.bind requires a session with .T context")

  local active_callable_mt = callable_mt

  ---The core chain constructor.
  ---@param config table
  ---@return table callable chain object
  local function make_chain(config)
    local name      = config.name or "?"
    local parse_fn  = config.parse
    local wrap_fn   = config.wrap
    local expand_fn = config.expand
    local table_fn  = config.table_fn

    return setmetatable({}, {
      __index = { _chain_config = config },

      __call = function(_, arg)
        -- (A) STRING → parse quote [[...]]
        if type(arg) == "string" then
          local T = session.T
          local parsed = parse_fn(T, arg)
          if #parsed.issues ~= 0 then
            raise_parse_issue(T, parsed, arg, 2)
          end
          if #parsed.splice_slots ~= 0 then
            error(
              "moon." .. name .. "[[]] requires bindings for @" .. tostring(parsed.splice_slots[1].splice_text or parsed.splice_slots[1].splice_id)
              .. " — use moon." .. name .. "{values}[[src]] instead", 2)
          end
          return wrap_fn(parsed.value, parsed, T, arg)
        end

        -- (B) TABLE → check for string keys
        if type(arg) == "table" then
          local has_str_keys = false
          for k in pairs(arg) do
            if type(k) == "string" then has_str_keys = true; break end
          end

          -- (B1) PURE ARRAY → builder (no string keys)
          if not has_str_keys then
            return table_fn and table_fn(arg) or arg
          end

          -- (B2) STRING-KEYED → values binder, return function(src)
          local bound_values = {}
          for k, v in pairs(arg) do
            bound_values[k] = v
          end

          return function(src)
            if type(src) ~= "string" then
              error(
                "moon." .. name .. "{...} expects a string [[]] body, got "
                .. type(src), 2)
            end
            local T = session.T
            local parse_opts = bound_values.__moonlift_parse_opts
            local origin = bound_values.__moonlift_source_origin
            local parsed = parse_fn(T, src, parse_opts)
            if #parsed.issues ~= 0 then
              raise_parse_issue(T, parsed, src, 2, origin)
            end

            -- No @{} splices → wrap directly
            if #parsed.splice_slots == 0 then
              return wrap_fn(parsed.value, parsed, T, src, bound_values)
            end

            -- Resolve @{key} from bound_values → host_splice
            local hs = require("moonlift.host_splice")
            local open_expand = require("moonlift.open_expand")

            local bindings = {}
            local used_values = {}
            for _, ss in ipairs(parsed.splice_slots) do
              local key = ss.splice_text or ss.splice_id
              local v = bound_values[key]
              if v == nil then
                error(
                  "no value bound for @" .. tostring(key)
                  .. " in values table", 2)
              end
              used_values[key] = v
              local binding = hs.fill(
                session, ss.slot, v,
                "splice " .. ss.splice_id, ss.role, ss.spread)
              bindings[#bindings + 1] = binding
            end

            -- Bound quotes are expanded outside the final module context.
            local expanded
            if expand_fn then
                local e = open_expand.Define(T, { defer_region_calls = true })
                local env = e.empty_env()
                env = e.env_with_fills(env, bindings)
                expanded = expand_fn(e, parsed.value, env)
            else
                -- No expander (e.g. func_impl / region_impl): pass filled
                -- bindings to wrap_fn for manual handling.
                expanded = parsed.value
            end
            local result = wrap_fn(expanded, parsed, T, src, bound_values)

            -- Tag quoted values with exactly the dependencies they used.
            -- The bundle layer recursively packs this explicit closure.  Do not
            -- store the whole values table: large tables often contain many
            -- unrelated funcs/regions and turn a tiny compile into a huge one.
            if type(result) == "table" then
              result._dep_values = used_values
              -- Some frontend expansions (notably region `call`) synthesize
              -- ordinary Tree items that belong to the quoted value's compile
              -- unit.  Preserve them explicitly so a quote expanded in isolation
              -- does not strand references to generated wrappers/result types.
              if e and e.generated_items then
                local generated = e.generated_items()
                if generated ~= nil and #generated > 0 then result._generated_items = generated end
              end
            end

            return result
          end
        end

        error("moon." .. name .. " expects a string [[]] or table {}", 2)
      end,
    })
  end

  ---Convenience positional wrapper.
  ---@return table callable chain object
  local function make_quote(parse_fn, wrap_fn, expand_fn, table_fn)
    return make_chain {
      name = nil, parse = parse_fn, wrap = wrap_fn,
      expand = expand_fn, table_fn = table_fn,
    }
  end

  return { make = make_chain, make_quote = make_quote, bind = M.bind }
end

return M
