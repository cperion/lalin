-- llbl.syntax.lexer
-- LuaJIT/Lua 5.1 compatible token stream for LLBL parsed channels.
-- It is intentionally a lexer, not a full Lua parser. Dialects consume tokens
-- only inside registered syntax islands.

local Lexer = {}
Lexer.__index = Lexer

local function char_at(s, i)
  if i < 1 or i > #s then return "" end
  return s:sub(i, i)
end

local function is_space(c)
  return c == " " or c == "\t" or c == "\r" or c == "\n" or c == "\f" or c == "\v"
end

local function is_alpha(c)
  return c:match("^[A-Za-z_]$") ~= nil
end

local function is_digit(c)
  return c:match("^[0-9]$") ~= nil
end

local function is_alnum(c)
  return c:match("^[A-Za-z0-9_]$") ~= nil
end

local function detect_long_bracket(s, i)
  if char_at(s, i) ~= "[" then return nil end
  local j = i + 1
  while char_at(s, j) == "=" do j = j + 1 end
  if char_at(s, j) ~= "[" then return nil end
  local eqs = j - i - 1
  return eqs, j + 1, "]" .. string.rep("=", eqs) .. "]"
end

local function update_pos(raw, line, col)
  for i = 1, #raw do
    local c = raw:sub(i, i)
    if c == "\n" then
      line = line + 1
      col = 1
    else
      col = col + 1
    end
  end
  return line, col
end

local function tok(kind, value, start_i, finish_i, raw, line, col, end_line, end_col)
  return {
    kind = kind,
    value = value,
    start = start_i,
    finish = finish_i,
    raw = raw,
    line = line,
    col = col,
    end_line = end_line,
    end_col = end_col,
  }
end

function Lexer.new(source, name, opts)
  local self = setmetatable({}, Lexer)
  self.source = source or ""
  self.name = name or "=(llbl syntax)"
  self.opts = opts or {}
  self.tokens = {}
  self.pos = 1
  self.last = nil
  self:tokenize()
  return self
end

function Lexer:error_at(t, msg)
  t = t or self:peek()
  error(string.format("%s:%d:%d: %s", self.name, t.line or 1, t.col or 1, msg), 0)
end

function Lexer:add_token(kind, value, start_i, finish_i, raw, start_line, start_col, end_line, end_col)
  self.tokens[#self.tokens + 1] = tok(kind, value, start_i, finish_i, raw, start_line, start_col, end_line, end_col)
end

function Lexer:tokenize()
  local s = self.source
  local i, line, col = 1, 1, 1
  local multi = {
    ["..."] = true,
    [".."] = true,
    ["::"] = true,
    ["=="] = true,
    ["~="] = true,
    ["<="] = true,
    [">="] = true,
    ["<<"] = true,
    [">>"] = true,
    ["//"] = true,
    ["=>"] = true,
    ["->"] = true,
    [":="] = true,
    ["+="] = true,
    ["-="] = true,
    ["*="] = true,
    ["/="] = true,
  }

  while i <= #s do
    local c = char_at(s, i)

    if is_space(c) then
      local start = i
      local sl, sc = line, col
      repeat
        i = i + 1
      until i > #s or not is_space(char_at(s, i))
      local raw = s:sub(start, i - 1)
      line, col = update_pos(raw, sl, sc)

    elseif c == "-" and char_at(s, i + 1) == "-" then
      local start = i
      local sl, sc = line, col
      i = i + 2
      local eqs, content_start, close_pat = detect_long_bracket(s, i)
      if eqs then
        local close_start = s:find(close_pat, content_start, true)
        if not close_start then
          self:add_token("error", "unterminated long comment", start, #s, s:sub(start), sl, sc, line, col)
          return
        end
        i = close_start + #close_pat
      else
        while i <= #s and char_at(s, i) ~= "\n" do i = i + 1 end
      end
      local raw = s:sub(start, i - 1)
      line, col = update_pos(raw, sl, sc)

    elseif c == '"' or c == "'" then
      local quote = c
      local start = i
      local sl, sc = line, col
      i = i + 1
      local escaped = false
      while i <= #s do
        local cc = char_at(s, i)
        if escaped then
          escaped = false
          i = i + 1
        elseif cc == "\\" then
          escaped = true
          i = i + 1
        elseif cc == quote then
          i = i + 1
          break
        else
          i = i + 1
        end
      end
      local raw = s:sub(start, i - 1)
      local el, ec = update_pos(raw, sl, sc)
      self:add_token("string", raw, start, i - 1, raw, sl, sc, el, ec)
      line, col = el, ec

    elseif c == "[" and detect_long_bracket(s, i) then
      local start = i
      local sl, sc = line, col
      local _, content_start, close_pat = detect_long_bracket(s, i)
      local close_start = s:find(close_pat, content_start, true)
      if not close_start then
        self:add_token("error", "unterminated long string", start, #s, s:sub(start), sl, sc, line, col)
        return
      end
      i = close_start + #close_pat
      local raw = s:sub(start, i - 1)
      local el, ec = update_pos(raw, sl, sc)
      self:add_token("string", raw, start, i - 1, raw, sl, sc, el, ec)
      line, col = el, ec

    elseif is_alpha(c) then
      local start = i
      local sl, sc = line, col
      i = i + 1
      while is_alnum(char_at(s, i)) do i = i + 1 end
      local raw = s:sub(start, i - 1)
      self:add_token("name", raw, start, i - 1, raw, sl, sc, line, col + #raw)
      col = col + #raw

    elseif is_digit(c) or (c == "." and is_digit(char_at(s, i + 1))) then
      local start = i
      local sl, sc = line, col
      if c == "0" and (char_at(s, i + 1) == "x" or char_at(s, i + 1) == "X") then
        i = i + 2
        while char_at(s, i):match("^[0-9A-Fa-f]$") do i = i + 1 end
      else
        while is_digit(char_at(s, i)) do i = i + 1 end
        if char_at(s, i) == "." and char_at(s, i + 1) ~= "." then
          i = i + 1
          while is_digit(char_at(s, i)) do i = i + 1 end
        end
        if char_at(s, i) == "e" or char_at(s, i) == "E" then
          local j = i + 1
          if char_at(s, j) == "+" or char_at(s, j) == "-" then j = j + 1 end
          if is_digit(char_at(s, j)) then
            i = j + 1
            while is_digit(char_at(s, i)) do i = i + 1 end
          end
        end
      end
      local raw = s:sub(start, i - 1)
      self:add_token("number", raw, start, i - 1, raw, sl, sc, line, col + #raw)
      col = col + #raw

    else
      local start = i
      local sl, sc = line, col
      local three = s:sub(i, i + 2)
      local two = s:sub(i, i + 1)
      local raw
      if multi[three] then
        raw = three
        i = i + 3
      elseif multi[two] then
        raw = two
        i = i + 2
      else
        raw = c
        i = i + 1
      end
      self:add_token("symbol", raw, start, i - 1, raw, sl, sc, line, col + #raw)
      col = col + #raw
    end
  end

  self.tokens[#self.tokens + 1] = tok("eof", "<eof>", #s + 1, #s + 1, "", line, col, line, col)
end

function Lexer:peek(n)
  n = n or 0
  return self.tokens[self.pos + n] or self.tokens[#self.tokens]
end

function Lexer:next()
  local t = self:peek(0)
  self.pos = self.pos + 1
  self.last = t
  return t
end

function Lexer:mark()
  return self.pos
end

function Lexer:restore(mark)
  self.pos = mark
  self.last = self.tokens[self.pos - 1]
end

function Lexer:is(value)
  return self:peek().value == value
end

function Lexer:is_name(value)
  local t = self:peek()
  return t.kind == "name" and (value == nil or t.value == value)
end

function Lexer:next_if(value)
  if self:peek().value == value then return self:next() end
  return nil
end

function Lexer:expect(value)
  local t = self:peek()
  if t.value ~= value then
    self:error_at(t, "expected `" .. tostring(value) .. "`, got `" .. tostring(t.value) .. "`")
  end
  return self:next()
end

function Lexer:expect_name(label)
  local t = self:peek()
  if t.kind ~= "name" then
    self:error_at(t, "expected " .. (label or "name") .. ", got `" .. tostring(t.value) .. "`")
  end
  return self:next()
end

function Lexer:span(start_tok, end_tok)
  end_tok = end_tok or start_tok
  return {
    source = self.name,
    start = start_tok.start,
    finish = end_tok.finish,
    line = start_tok.line,
    col = start_tok.col,
    end_line = end_tok.end_line,
    end_col = end_tok.end_col,
    text = self.source:sub(start_tok.start, end_tok.finish),
  }
end

function Lexer:raw(start_i, finish_i)
  return self.source:sub(start_i, finish_i)
end

function Lexer:consume_balanced_from_open(open_value, close_value)
  local open = self:expect(open_value)
  local depth = 1
  local content_start = open.finish + 1
  local close
  while depth > 0 do
    local t = self:next()
    if t.kind == "eof" then self:error_at(t, "unterminated balanced sequence") end
    if t.value == open_value then
      depth = depth + 1
    elseif t.value == close_value then
      depth = depth - 1
      if depth == 0 then close = t end
    end
  end
  return self.source:sub(content_start, close.start - 1), open, close
end

function Lexer:skip_separators()
  while self:next_if(",") or self:next_if(";") do end
end

function Lexer:at_eof()
  return self:peek().kind == "eof"
end

return Lexer
