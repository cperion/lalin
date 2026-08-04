-- lalin.syntax.ast
-- Lightweight utilities retained from the parsed-channel frontend.
-- Ast.node() is removed; parsers construct schema ASDL types directly.

local llbl = require("llbl")

local Ast = {}

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
  spec.channel = spec.channel or "parsed:host_eval"
  return llbl.host_eval.parsed(source_text, refs or {}, nil, origin, spec)
end

function Ast.consume_balanced_from_open(lex)
  -- Delegates to lex:consume_balanced_from_open("[", "]")
  return lex:consume_balanced_from_open("[", "]")
end

return Ast
