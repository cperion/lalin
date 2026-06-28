-- llbl.syntax.pratt
-- Small Pratt parser helper used by dialect parsers.  It knows nothing about
-- Lalin; callbacks build dialect-specific values.

local Pratt = {}
Pratt.__index = Pratt

local function default_error(lex, msg)
  lex:error_at(lex:peek(), msg)
end

function Pratt.new(spec)
  spec = spec or {}
  local self = setmetatable({}, Pratt)
  self.atom = spec.atom
  self.prefix = spec.prefix or {}
  self.infix = spec.infix or {}
  self.postfix = spec.postfix or {}
  self.error = spec.error or default_error
  return self
end

function Pratt:parse(lex, ctx, min_bp)
  min_bp = min_bp or 0
  local t = lex:peek()
  local left

  local prefix = self.prefix[t.value]
  if prefix then
    local op = lex:next()
    local rhs = self:parse(lex, ctx, prefix.rbp or prefix.bp or 100)
    left = prefix.emit(op, rhs, ctx)
  else
    if not self.atom then self.error(lex, "no atom parser configured") end
    left = self.atom(lex, ctx, self)
  end

  while true do
    local op_t = lex:peek()
    local post = self.postfix[op_t.value]
    if post and (post.bp or 100) >= min_bp then
      local op = lex:next()
      left = post.emit(op, left, lex, ctx, self)
    else
      local inf = self.infix[op_t.value]
      if not inf then break end
      local lbp = inf.lbp or inf.bp or 0
      if lbp < min_bp then break end
      local op = lex:next()
      local rbp = inf.rbp or (lbp + (inf.right_assoc and 0 or 1))
      local right = self:parse(lex, ctx, rbp)
      left = inf.emit(op, left, right, ctx)
    end
  end

  return left
end

return Pratt
