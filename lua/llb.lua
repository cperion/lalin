--[[
LLB: Lua Language Builder
Version: 0.3.0 single-file design cut
Target: LuaJIT / Lua 5.1

LLB is a parserless language workbench:

  Lua syntax -> Lua values -> LLB captures -> role normalization -> AST/IR

Lua is the meta-language. LLB is the meaning layer: heads, slots, roles,
[] captures, fragments, source-aware diagnostics, semantic passes, scopes,
typechecking hooks, and LSP-friendly indexes.

Minimal grammar example:

  local llb = require("llb")
  local g = llb.grammar

  local Mini = llb.define "Mini" {
    g.role .decls   { kind = "array" },
    g.role .body    { kind = "array" },
    g.role .product { kind = "product" },

    g.scalar .void,
    g.scalar .i32,
    g.type_ctor .ptr { arity = 1 },

    g.head .module {
      g.slot .name  [g.string],
      g.slot .decls [g.decls],
      emit = function(n) return { tag = "module", name = n.name, decls = n.decls } end,
    },

    g.head .fn {
      g.slot .name   [g.name],
      g.slot .params [g.product],
      g.slot .result [g.type] { optional = true },
      g.slot .body   [g.body],
      emit = function(n, lang)
        return { tag = "fn", name = n.name.text, params = n.params,
                 result = n.result or lang.exports.void, body = n.body }
      end,
    },
  }

User DSL:

  return module "Demo" {
    fn. add { a [i32], b [i32] } [i32] { ret (a + b), },
  }
]]

local llb = { _VERSION = "llb-0.3.0", VERSION = "llb-0.3.0" }

local unpack = unpack or table.unpack
local loadstring0 = loadstring or load
local setfenv0 = setfenv

if not setfenv0 then
  -- Lua 5.2+ compatibility for development/testing. LuaJIT already has setfenv.
  setfenv0 = function(fn, env)
    local i = 1
    while true do
      local name = debug.getupvalue(fn, i)
      if name == "_ENV" then debug.setupvalue(fn, i, env); return fn end
      if name == nil then return fn end
      i = i + 1
    end
  end
end

local function compile_lua(src, name)
  if loadstring then return loadstring(src, name) end
  return load(src, name, "t")
end

-- ---------------------------------------------------------------------------
-- Utilities
-- ---------------------------------------------------------------------------

local NIL    = { __llb_tag = "Sentinel", name = "nil" }
local UNIT   = { __llb_tag = "Sentinel", name = "unit" }
local ABSENT = { __llb_tag = "Sentinel", name = "absent" }
llb.NIL, llb.UNIT, llb.ABSENT = NIL, UNIT, ABSENT

local function pack(...)
  return { n = select("#", ...), ... }
end

local function shallow_copy(t)
  local out = {}
  if t then for k, v in pairs(t) do out[k] = v end end
  return out
end

local function array_copy(t)
  local out = {}
  if t then for i = 1, #t do out[i] = t[i] end end
  return out
end

local function append(dst, src)
  for i = 1, #(src or {}) do dst[#dst + 1] = src[i] end
  return dst
end

local function starts_with(s, p)
  return type(s) == "string" and s:sub(1, #p) == p
end

local function split_lines(src)
  src = (src or ""):gsub("\r\n", "\n"):gsub("\r", "\n")
  local lines = {}
  if src == "" then return lines end
  local pos = 1
  while true do
    local nl = src:find("\n", pos, true)
    if not nl then lines[#lines + 1] = src:sub(pos); break end
    lines[#lines + 1] = src:sub(pos, nl - 1)
    pos = nl + 1
  end
  return lines
end

local function tagof(v)
  if type(v) == "table" then return rawget(v, "__llb_tag") end
  return nil
end

local function is_tag(v, tag)
  return tagof(v) == tag
end

llb.tagof, llb.is = tagof, is_tag

local function repr(v)
  if v == NIL then return "nil" end
  if v == UNIT then return "()" end
  if v == ABSENT then return "<absent>" end
  local tv = type(v)
  if tv == "string" then return string.format("%q", v) end
  if tv ~= "table" then return tostring(v) end
  local tag = tagof(v)
  if tag then
    if rawget(v, "text") then return "<" .. tag .. ":" .. tostring(v.text) .. ">" end
    if rawget(v, "name") then return "<" .. tag .. ":" .. tostring(v.name) .. ">" end
    if rawget(v, "kind") then return "<" .. tag .. ":" .. tostring(v.kind) .. ">" end
    return "<" .. tag .. ">"
  end
  return "<table>"
end

llb.repr = repr

local function origin_of(v)
  if type(v) ~= "table" then return nil end
  return rawget(v, "origin") or (rawget(v, "__llb") and rawget(v, "__llb").origin) or nil
end

llb.origin_of = origin_of

-- ---------------------------------------------------------------------------
-- Source inspection
-- ---------------------------------------------------------------------------

local source = { cache = {}, file_cache = {} }
llb.source = source

local SELF_SOURCE = debug and debug.getinfo and debug.getinfo(1, "S").source or nil

local function source_aliases(name)
  local out = {}
  if not name then return out end
  out[#out + 1] = name
  if starts_with(name, "@") or starts_with(name, "=") then out[#out + 1] = name:sub(2) end
  if not starts_with(name, "@") then out[#out + 1] = "@" .. name end
  if not starts_with(name, "=") then out[#out + 1] = "=" .. name end
  return out
end

function source.register(name, text)
  if not name then return end
  local lines = split_lines(text)
  local aliases = source_aliases(tostring(name))
  for i = 1, #aliases do source.cache[aliases[i]] = lines end
end

function source.clean(src)
  if not src then return nil end
  if starts_with(src, "@") or starts_with(src, "=") then return src:sub(2) end
  return src
end

function source.read_file(path)
  if not path or path == "" then return nil end
  if source.file_cache[path] then return source.file_cache[path] end
  local f = io.open(path, "rb")
  if not f then return nil end
  local text = f:read("*a") or ""
  f:close()
  local lines = split_lines(text)
  source.file_cache[path] = lines
  source.cache[path], source.cache["@" .. path] = lines, lines
  return lines
end

function source.lines(src)
  if not src then return nil end
  if source.cache[src] then return source.cache[src] end
  local clean = source.clean(src)
  if clean and source.cache[clean] then return source.cache[clean] end
  if starts_with(src, "@") then return source.read_file(src:sub(2)) end
  return nil
end

function source.line(origin)
  if not origin then return nil end
  local lines = source.lines(origin.source) or source.lines(origin.file)
  if lines and origin.line and origin.line >= 1 then return lines[origin.line] end
  return origin.text
end

function source.capture(kind, opts)
  opts = opts or {}
  if opts.origin then return opts.origin end
  local skip = opts.skip or 0
  local chosen, fallback
  for level = 2 + skip, 20 + skip do
    local info = debug and debug.getinfo and debug.getinfo(level, "Sln") or nil
    if not info then break end
    if not fallback and info.currentline and info.currentline >= 0 then fallback = info end
    if info.source ~= SELF_SOURCE and info.currentline and info.currentline >= 0 then
      chosen = info; break
    end
  end
  local info = chosen or fallback
  if not info then
    return { __llb_tag = "Origin", kind = kind or "unknown", source = "<unknown>", file = "<unknown>", line = -1 }
  end
  local o = {
    __llb_tag = "Origin",
    kind = kind or "unknown",
    source = info.source,
    file = source.clean(info.source),
    short_src = info.short_src,
    line = info.currentline,
    name = info.name,
    namewhat = info.namewhat,
    what = info.what,
    hint = opts.hint,
  }
  o.text = source.line(o)
  return o
end

llb.origin = source.capture

function llb.here(kind, opts)
  opts = opts or {}
  opts.skip = (opts.skip or 0) + 1
  return source.capture(kind or "factory-call", opts)
end

function llb.with_origin(origin, fn, ...)
  if type(fn) ~= "function" then llb.fail("with_origin expects a function", { primary = origin }) end
  return fn(..., origin)
end

local function origin_label(origin)
  if not origin then return "<unknown>" end
  return tostring(origin.file or origin.short_src or origin.source or "<unknown>") .. ":" .. tostring(origin.line or -1)
end

llb.origin_label = origin_label

function source.context(origin, radius)
  radius = radius or 2
  if not origin or not origin.line or origin.line < 1 then return nil end
  local lines = source.lines(origin.source) or source.lines(origin.file)
  if not lines then return nil end
  local first = math.max(1, origin.line - radius)
  local last = math.min(#lines, origin.line + radius)
  local out = {}
  for line = first, last do out[#out + 1] = { line = line, text = lines[line], focus = line == origin.line } end
  return out
end

function source.render_excerpt(origin, radius, label)
  local ctx = source.context(origin, radius or 2)
  if not ctx then return origin_label(origin) .. (label and (": " .. label) or "") end
  local max_line = 0
  for i = 1, #ctx do if ctx[i].line > max_line then max_line = ctx[i].line end end
  local width = #tostring(max_line)
  local out = { origin_label(origin) .. (label and (": " .. label) or "") }
  for i = 1, #ctx do
    local row = ctx[i]
    local mark = row.focus and ">" or " "
    out[#out + 1] = string.format("%s %" .. width .. "d | %s", mark, row.line, row.text or "")
    if row.focus and origin.hint and row.text then
      local s, e = row.text:find(tostring(origin.hint), 1, true)
      if s then out[#out + 1] = string.format("  %" .. width .. "s | %s%s", "", string.rep(" ", s - 1), string.rep("^", math.max(1, e - s + 1))) end
    end
  end
  return table.concat(out, "\n")
end

-- ---------------------------------------------------------------------------
-- Diagnostics
-- ---------------------------------------------------------------------------

local Diagnostic = {}
Diagnostic.__index = Diagnostic

function llb.diagnostic(spec)
  spec = spec or {}
  return setmetatable({
    __llb_tag = "Diagnostic",
    severity = spec.severity or "error",
    code = spec.code,
    message = spec.message or spec[1] or "diagnostic",
    primary = spec.primary or spec.origin,
    labels = spec.labels or {},
    related = spec.related or {},
    notes = spec.notes or {},
  }, Diagnostic)
end

function Diagnostic:render(opts)
  opts = opts or {}
  local out = {}
  local head = ""
  if self.primary then head = origin_label(self.primary) .. ": " end
  head = head .. tostring(self.severity or "error") .. ": "
  if self.code then head = head .. tostring(self.code) .. ": " end
  head = head .. tostring(self.message)
  out[#out + 1] = head
  if self.primary then out[#out + 1] = source.render_excerpt(self.primary, opts.radius or 2, self.message) end
  for i = 1, #self.labels do
    local l = self.labels[i]
    out[#out + 1] = source.render_excerpt(l.origin or l.primary, opts.radius or 1, l.message)
  end
  for i = 1, #self.related do
    local r = self.related[i]
    out[#out + 1] = source.render_excerpt(r.origin or r.primary, opts.radius or 1, r.message)
  end
  for i = 1, #self.notes do out[#out + 1] = "note: " .. tostring(self.notes[i]) end
  return table.concat(out, "\n")
end

Diagnostic.__tostring = Diagnostic.render
llb.Diagnostic = Diagnostic

local DiagnosticBag = {}
DiagnosticBag.__index = DiagnosticBag

function llb.diagnostics()
  return setmetatable({ __llb_tag = "DiagnosticBag", items = {} }, DiagnosticBag)
end

function DiagnosticBag:add(d)
  if type(d) == "string" then d = llb.diagnostic { message = d } end
  self.items[#self.items + 1] = d
  return d
end

function DiagnosticBag:error(spec)
  spec = spec or {}; spec.severity = "error"; return self:add(llb.diagnostic(spec))
end

function DiagnosticBag:warning(spec)
  spec = spec or {}; spec.severity = "warning"; return self:add(llb.diagnostic(spec))
end

function DiagnosticBag:has_errors()
  for i = 1, #self.items do if self.items[i].severity == "error" or self.items[i].severity == "fatal" then return true end end
  return false
end

function DiagnosticBag:render(opts)
  local out = {}
  for i = 1, #self.items do out[#out + 1] = self.items[i]:render(opts) end
  return table.concat(out, "\n\n")
end

llb.DiagnosticBag = DiagnosticBag

function llb.fail(message, spec, level)
  spec = spec or {}; spec.message = message
  error(llb.diagnostic(spec), level or 0)
end

-- ---------------------------------------------------------------------------
-- Node helpers
-- ---------------------------------------------------------------------------

local Node = {}
Node.__index = Node

local function node(tag, fields, origin)
  fields = fields or {}
  fields.__llb_tag = fields.__llb_tag or "Node"
  fields.tag = fields.tag or tag
  fields.origin = fields.origin or origin or source.capture("node")
  if getmetatable(fields) == nil then setmetatable(fields, Node) end
  return fields
end

llb.node = node

function Node:source_context(radius) return source.context(self.origin, radius) end
function Node:explain() return source.render_excerpt(self.origin, 2, self.tag or "node") end
llb.Node = Node

local function attach_node_meta(v, tag, meta)
  if type(v) ~= "table" then v = { value = v } end
  v.__llb_tag = v.__llb_tag or "Node"
  v.tag = v.tag or tag
  v.__llb = v.__llb or {}
  for k, x in pairs(meta or {}) do if v.__llb[k] == nil then v.__llb[k] = x end end
  v.origin = v.origin or (meta and meta.origin) or v.__llb.origin
  if getmetatable(v) == nil then setmetatable(v, Node) end
  return v
end

-- ---------------------------------------------------------------------------
-- Names, symbols, captures, expressions
-- ---------------------------------------------------------------------------

local Name = {}; Name.__index = Name
function llb.name(text, opts)
  opts = opts or {}
  return setmetatable({ __llb_tag = "Name", text = tostring(text), computed = opts.computed and true or false, origin = opts.origin or source.capture("name", { hint = text }) }, Name)
end

local Expr, Symbol, Capture = {}, {}, {}

local function expr(kind, fields)
  fields = fields or {}
  fields.__llb_tag = "Expr"; fields.kind = kind
  fields.origin = fields.origin or source.capture("expr", { hint = fields.hint })
  return setmetatable(fields, Expr)
end
llb.expr = expr

local function binary(op) return function(a, b) return expr("binop", { op = op, a = a, b = b, hint = op }) end end
local function unary(op) return function(a) return expr("unop", { op = op, a = a, hint = op }) end end
local function call_expr(callee, args) return expr("call", { callee = callee, args = args or {} }) end

Expr.__index = function(self, key)
  if Expr[key] then return Expr[key] end
  if type(key) == "string" then return expr("field", { base = self, field = key, hint = key }) end
  return expr("index", { base = self, index = key })
end
Expr.__call = function(self, ...) return call_expr(self, pack(...)) end
Expr.__add, Expr.__sub, Expr.__mul, Expr.__div, Expr.__mod, Expr.__pow = binary("+"), binary("-"), binary("*"), binary("/"), binary("%"), binary("^")
Expr.__unm, Expr.__concat = unary("-"), binary("..")
function Expr:lt(x) return binary("<")(self, x) end
function Expr:le(x) return binary("<=")(self, x) end
function Expr:gt(x) return binary(">")(self, x) end
function Expr:ge(x) return binary(">=")(self, x) end
function Expr:eq(x) return binary("==")(self, x) end
function Expr:ne(x) return binary("~=")(self, x) end

local type_like_predicates = {}
llb.type_like_predicates = type_like_predicates

function llb.register_type_like(fn)
  if type(fn) ~= "function" then llb.fail("type-like predicate must be a function") end
  type_like_predicates[#type_like_predicates + 1] = fn
  return fn
end

function llb.is_type_like(v)
  if is_tag(v, "Type") then return true end
  for i = 1, #type_like_predicates do
    local ok, yes = pcall(type_like_predicates[i], v)
    if not ok then
      llb.fail("type-like predicate #" .. tostring(i) .. " failed: " .. tostring(yes), {
        code = "E_TYPE_LIKE_PREDICATE",
        primary = origin_of(v),
      }, 2)
    end
    if ok and yes then return true end
  end
  return false
end

Capture.__index = Capture
Capture.__call = function(self, init)
  return { __llb_tag = "CaptureInit", capture = self, init = init == nil and NIL or init, origin = source.capture("capture-init") }
end

Symbol.__index = function(self, key)
  if Symbol[key] then return Symbol[key] end
  if llb.is_type_like(key) then return setmetatable({ __llb_tag = "Capture", subject = self, value = key, origin = source.capture("capture", { hint = self.text }) }, Capture) end
  if type(key) == "string" then return expr("field", { base = self, field = key, hint = key }) end
  return expr("index", { base = self, index = key })
end
Symbol.__call = function(self, ...) return call_expr(self, pack(...)) end
Symbol.__add, Symbol.__sub, Symbol.__mul, Symbol.__div, Symbol.__mod, Symbol.__pow = binary("+"), binary("-"), binary("*"), binary("/"), binary("%"), binary("^")
Symbol.__unm, Symbol.__concat = unary("-"), binary("..")
Symbol.__tostring = function(self) return self.text end
function Symbol:lt(x) return binary("<")(self, x) end
function Symbol:le(x) return binary("<=")(self, x) end
function Symbol:gt(x) return binary(">")(self, x) end
function Symbol:ge(x) return binary(">=")(self, x) end
function Symbol:eq(x) return binary("==")(self, x) end
function Symbol:ne(x) return binary("~=")(self, x) end
Symbol.__lt, Symbol.__le = Symbol.lt, Symbol.le

function llb.symbol(text, opts)
  opts = opts or {}
  return setmetatable({ __llb_tag = "Symbol", text = tostring(text), origin = opts.origin or source.capture("symbol", { hint = text }) }, Symbol)
end

llb.N = setmetatable({ __llb_tag = "NameFactory" }, {
  __index = function(_, key) return llb.symbol(key, { origin = source.capture("generated-name", { hint = key }) }) end,
  __call = function(_, key) return llb.symbol(key, { origin = source.capture("generated-name", { hint = key }) }) end,
})

-- ---------------------------------------------------------------------------
-- Types and fragments
-- ---------------------------------------------------------------------------

local Type = {}; Type.__index = Type; Type.__tostring = function(self) return self.name or "<type>" end
function llb.type(name, fields)
  fields = fields or {}; fields.__llb_tag = "Type"; fields.name = tostring(name); fields.kind = fields.kind or "named"; fields.origin = fields.origin or source.capture("type", { hint = name })
  return setmetatable(fields, Type)
end

local TypeCtor = {}
TypeCtor.__index = function(self, key)
  if TypeCtor[key] then return TypeCtor[key] end
  local args = array_copy(rawget(self, "args")); args[#args + 1] = key
  local arity = rawget(self, "arity") or 1
  local name = rawget(self, "name")
  local emit = rawget(self, "emit")
  if #args < arity then return setmetatable({ __llb_tag = "TypeCtor", name = name, arity = arity, args = args, emit = emit, origin = rawget(self, "origin") }, TypeCtor) end
  local produced = emit and emit(unpack(args)) or nil
  if llb.is_type_like(produced) then return produced end
  return llb.type(name, { kind = "app", ctor = name, args = args, value = produced, origin = source.capture("type-app", { hint = name }) })
end
TypeCtor.__call = function(self, ...)
  local p, cur = pack(...), self
  for i = 1, p.n do cur = TypeCtor.__index(cur, p[i]) end
  return cur
end
function llb.type_ctor(name, spec)
  if type(spec) == "number" then spec = { arity = spec } end
  if type(spec) == "function" then spec = { emit = spec } end
  spec = spec or {}
  return setmetatable({ __llb_tag = "TypeCtor", name = tostring(name), arity = spec.arity or 1, args = {}, emit = spec.emit, origin = spec.origin or source.capture("type-ctor", { hint = name }) }, TypeCtor)
end

local Fragment = {}; Fragment.__index = Fragment

local function fragment(role, items, origin, spec)
  items = items or {}
  local out = {
    __llb_tag = "Fragment",
    role = tostring(role),
    items = items,
    origin = origin or source.capture("fragment", { hint = role }),
  }
  for k, v in pairs(spec or {}) do out[k] = v end
  for i = 1, #items do out[i] = items[i] end
  return setmetatable(out, Fragment)
end

function llb.fragment(role, items, origin, spec) return fragment(role, items, origin, spec) end
function llb.spread(value) return { __llb_tag = "Spread", value = value, origin = source.capture("spread", { hint = "spread" }) } end
llb._ = llb.spread

local function fragment_items(f)
  if is_tag(f, "Fragment") then return f.items or {} end
  return nil
end

local function fragment_algebra(f)
  local a = rawget(f, "algebra")
  if a then return a end
  local spec = rawget(f, "role_spec") or rawget(f, "spec")
  a = spec and spec.algebra
  if a then return a end
  local kind = (spec and spec.kind) or rawget(f, "kind") or rawget(f, "role")
  if kind == "product" then return "product" end
  if kind == "sum" or kind == "protocol" then return "sum" end
  if kind == "array" or kind == "list" or kind == "decl" or kind == "stmt" or kind == "expr" then return "list" end
  return "list"
end

local function fragment_like(f, items, origin)
  return fragment(f.role, items, origin or f.origin, {
    algebra = rawget(f, "algebra"),
    role_spec = rawget(f, "role_spec"),
    lang = rawget(f, "lang"),
    payload_role = rawget(f, "payload_role"),
  })
end

local function item_name(item)
  if type(item) ~= "table" then return nil end
  if rawget(item, "name") ~= nil then return tostring(item.name) end
  if rawget(item, "field_name") ~= nil then return tostring(item.field_name) end
  if rawget(item, "text") ~= nil then return tostring(item.text) end
  return nil
end

local function variant_name(item)
  if type(item) ~= "table" then return nil end
  if rawget(item, "name") ~= nil then return tostring(item.name) end
  if rawget(item, "text") ~= nil then return tostring(item.text) end
  if rawget(item, "variant_name") ~= nil then return tostring(item.variant_name) end
  return nil
end

local function check_unique(items, what, origin)
  local seen = {}
  for i = 1, #(items or {}) do
    local name = what == "variant" and variant_name(items[i]) or item_name(items[i])
    if name then
      if seen[name] then
        llb.fail("duplicate " .. what .. " '" .. tostring(name) .. "' in fragment algebra", {
          code = what == "variant" and "E_DUPLICATE_VARIANT" or "E_DUPLICATE_FIELD",
          primary = origin_of(items[i]) or origin,
          labels = { { origin = origin_of(seen[name]) or origin, message = "first " .. what .. " is here" } },
        }, 2)
      end
      seen[name] = items[i]
    end
  end
end

local function copy_item_with_payload(item, payload)
  local out = shallow_copy(item)
  out.payload = payload
  if getmetatable(item) ~= nil then setmetatable(out, getmetatable(item)) end
  return out
end

local function variant_payload(item)
  if type(item) ~= "table" then return {} end
  return rawget(item, "payload") or {}
end

local function decorate_variant(item, product)
  local payload = array_copy(variant_payload(item))
  append(payload, product.items or {})
  check_unique(payload, "field", origin_of(item) or product.origin)
  return copy_item_with_payload(item, payload)
end

local function assert_fragment(v, op)
  if not is_tag(v, "Fragment") then
    llb.fail("operator " .. op .. " expects LLB fragments, got " .. repr(v), {
      code = "E_FRAGMENT_OPERATOR",
      primary = origin_of(v),
    }, 2)
  end
end

function llb.concat(a, b)
  assert_fragment(a, ".."); assert_fragment(b, "..")
  if a.role ~= b.role then
    llb.fail("cannot concatenate " .. tostring(a.role) .. " fragment with " .. tostring(b.role) .. " fragment", {
      code = "E_CONCAT_ROLE_MISMATCH",
      primary = origin_of(b) or b.origin,
      labels = { { origin = origin_of(a) or a.origin, message = "left fragment role is " .. tostring(a.role) } },
    }, 2)
  end
  local algebra = fragment_algebra(a)
  if algebra ~= "product" and algebra ~= "list" and algebra ~= "array" then
    llb.fail("operator .. is not valid for " .. tostring(algebra) .. " fragment role " .. tostring(a.role), {
      code = "E_BAD_FRAGMENT_OPERATOR",
      primary = origin_of(a) or a.origin,
    }, 2)
  end
  local items = array_copy(a.items)
  append(items, b.items)
  if algebra == "product" then check_unique(items, "field", origin_of(b) or b.origin) end
  return fragment_like(a, items, origin_of(a) or a.origin)
end

function llb.choice(a, b)
  assert_fragment(a, "+"); assert_fragment(b, "+")
  if a.role ~= b.role then
    llb.fail("cannot compose " .. tostring(a.role) .. " alternatives with " .. tostring(b.role) .. " alternatives", {
      code = "E_CHOICE_ROLE_MISMATCH",
      primary = origin_of(b) or b.origin,
      labels = { { origin = origin_of(a) or a.origin, message = "left fragment role is " .. tostring(a.role) } },
    }, 2)
  end
  local algebra = fragment_algebra(a)
  if algebra ~= "sum" and algebra ~= "protocol" then
    llb.fail("operator + is only valid for sum/protocol fragments, got " .. tostring(algebra) .. " role " .. tostring(a.role), {
      code = "E_BAD_FRAGMENT_OPERATOR",
      primary = origin_of(a) or a.origin,
    }, 2)
  end
  local items = array_copy(a.items)
  append(items, b.items)
  check_unique(items, "variant", origin_of(b) or b.origin)
  return fragment_like(a, items, origin_of(a) or a.origin)
end

function llb.decorate(sum, product)
  assert_fragment(sum, "*"); assert_fragment(product, "*")
  local sa, pa = fragment_algebra(sum), fragment_algebra(product)
  if not ((sa == "sum" or sa == "protocol") and pa == "product") then
    llb.fail("operator * expects sum/protocol fragment and product fragment", {
      code = "E_DECORATE_ROLE_MISMATCH",
      primary = origin_of(product) or product.origin,
      labels = { { origin = origin_of(sum) or sum.origin, message = "left algebra is " .. tostring(sa) } },
    }, 2)
  end
  local items = {}
  for i = 1, #(sum.items or {}) do items[i] = decorate_variant(sum.items[i], product) end
  return fragment_like(sum, items, origin_of(sum) or sum.origin)
end

Fragment.__concat = function(a, b) return llb.concat(a, b) end
Fragment.__add = function(a, b) return llb.choice(a, b) end
Fragment.__mul = function(a, b)
  assert_fragment(a, "*"); assert_fragment(b, "*")
  local aa, ba = fragment_algebra(a), fragment_algebra(b)
  if (aa == "sum" or aa == "protocol") and ba == "product" then return llb.decorate(a, b) end
  if aa == "product" and (ba == "sum" or ba == "protocol") then return llb.decorate(b, a) end
  llb.fail("operator * expects product * sum or sum * product fragments", {
    code = "E_DECORATE_ROLE_MISMATCH",
    primary = origin_of(b) or b.origin,
  }, 2)
end
Fragment.__len = function(self) return #(self.items or {}) end
Fragment.__tostring = function(self) return "llb.fragment(" .. tostring(self.role) .. ", " .. tostring(#(self.items or {})) .. ")" end

local ExprCtor, ExprCtorStage = {}, {}
ExprCtor.__index = function(self, key)
  return setmetatable({ __llb_tag = "ExprCtorStage", name = self.name, indexed = { key }, origin = source.capture("expr-ctor-index", { hint = self.name }) }, ExprCtorStage)
end
ExprCtor.__call = function(self, ...)
  return expr("ctor", { name = self.name, indexed = {}, args = pack(...), hint = self.name })
end
ExprCtorStage.__index = function(self, key)
  local indexed = array_copy(self.indexed); indexed[#indexed + 1] = key
  return setmetatable({ __llb_tag = "ExprCtorStage", name = self.name, indexed = indexed, origin = self.origin }, ExprCtorStage)
end
ExprCtorStage.__call = function(self, ...)
  return expr("ctor", { name = self.name, indexed = self.indexed, args = pack(...), hint = self.name })
end
function llb.expr_ctor(name)
  return setmetatable({ __llb_tag = "ExprCtor", name = tostring(name) }, ExprCtor)
end

-- ---------------------------------------------------------------------------
-- Grammar bootstrap DSL
-- ---------------------------------------------------------------------------

local RoleRef = {}; RoleRef.__index = RoleRef
local function role_ref(name) return setmetatable({ __llb_tag = "RoleRef", name = tostring(name) }, RoleRef) end

local BootNode = {}; BootNode.__index = BootNode
BootNode.__call = function(self, attrs)
  attrs = attrs or {}
  if type(attrs) ~= "table" then llb.fail("grammar attributes must be a table", { primary = self.origin }) end
  local spec = rawget(self, "spec") or {}
  for k, v in pairs(attrs) do self[k] = v; spec[k] = v end
  self.spec = spec
  return self
end

local function boot_node(tag, fields)
  fields = fields or {}; fields.__llb_tag = tag; fields.origin = fields.origin or source.capture("grammar:" .. tag)
  return setmetatable(fields, BootNode)
end

local BootStage = {}
BootStage.__index = function(self, key)
  if BootStage[key] then return BootStage[key] end
  if self.kind == "slot" then
    local role = is_tag(key, "RoleRef") and key.name or key
    return boot_node("SlotDecl", { name = self.name, role = tostring(role), spec = {}, origin = source.capture("grammar:slot", { hint = self.name }) })
  end
  return nil
end
BootStage.__call = function(self, body)
  body = body or {}
  if self.kind == "role" then
    return boot_node("RoleDecl", { name = self.name, kind = body.kind or body[1] or "array", spec = body, origin = self.origin })
  elseif self.kind == "type_ctor" then
    return boot_node("TypeCtorDecl", { name = self.name, arity = body.arity or 1, emit = body.emit, spec = body, origin = self.origin })
  elseif self.kind == "helper" then
    return boot_node("HelperDecl", { name = self.name, value = body.value or body[1], spec = body, origin = self.origin })
  elseif self.kind == "head" then
    local slots = {}
    for i = 1, #body do
      if not is_tag(body[i], "SlotDecl") then llb.fail("head bodies accept only slot declarations", { primary = origin_of(body[i]) or self.origin }) end
      slots[#slots + 1] = body[i]
    end
    return boot_node("HeadDecl", { name = self.name, slots = slots, tag = body.tag or self.name, emit = body.emit or body.build, check = body.check, lower = body.lower, lsp = body.lsp, format = body.format, spec = body, origin = self.origin })
  elseif self.kind == "pass" then
    return boot_node("PassDecl", { name = self.name, run = body.run or body[1], spec = body, origin = self.origin })
  elseif self.kind == "lsp" then
    return boot_node("LspDecl", { name = self.name, spec = body, origin = self.origin })
  elseif self.kind == "scalar" then
    return boot_node("ScalarDecl", { name = self.name, spec = body, origin = self.origin })
  end
  llb.fail("unknown grammar kind " .. tostring(self.kind), { primary = self.origin })
end

local BootHead = {}
BootHead.__index = function(self, key)
  if self.kind == "scalar" then return boot_node("ScalarDecl", { name = tostring(key), spec = {}, origin = source.capture("grammar:scalar", { hint = key }) }) end
  return setmetatable({ __llb_tag = "BootStage", kind = self.kind, name = tostring(key), origin = source.capture("grammar:" .. self.kind, { hint = key }) }, BootStage)
end
local function boot_head(kind) return setmetatable({ __llb_tag = "BootHead", kind = kind }, BootHead) end

llb.grammar = setmetatable({
  role = boot_head("role"), head = boot_head("head"), slot = boot_head("slot"), scalar = boot_head("scalar"),
  type_ctor = boot_head("type_ctor"), helper = boot_head("helper"), pass = boot_head("pass"), lsp = boot_head("lsp"),
  type_system = function(spec) return boot_node("TypeSystemDecl", { spec = spec or {}, origin = source.capture("grammar:type-system") }) end,
}, { __index = function(_, key) return role_ref(key) end })

-- ---------------------------------------------------------------------------
-- Normalization
-- ---------------------------------------------------------------------------

local normalize_role, normalize_expr

local function norm_name(ctx, v)
  if is_tag(v, "Name") then return v end
  if is_tag(v, "Symbol") then return llb.name(v.text, { origin = v.origin }) end
  if type(v) == "string" or type(v) == "number" then return llb.name(v, { computed = true, origin = ctx and ctx.origin }) end
  llb.fail("expected name, got " .. repr(v), { primary = origin_of(v) or (ctx and ctx.origin), code = "E_EXPECTED_NAME" })
end

local function norm_type(ctx, v)
  if llb.is_type_like(v) then return v end
  if is_tag(v, "Symbol") then return llb.type(v.text, { kind = "named", origin = v.origin }) end
  if type(v) == "string" then return llb.type(v, { kind = "named", origin = ctx and ctx.origin }) end
  llb.fail("expected type, got " .. repr(v), { primary = origin_of(v) or (ctx and ctx.origin), code = "E_EXPECTED_TYPE" })
end

normalize_expr = function(ctx, v)
  if v == UNIT or v == ABSENT then return nil end
  if v == NIL then return node("expr", { expr_kind = "literal", value = nil }, ctx and ctx.origin) end
  local tv = type(v)
  if is_tag(v, "Node") then return v end
  if is_tag(v, "Symbol") then return node("expr", { expr_kind = "name", name = v.text }, v.origin) end
  if is_tag(v, "Name") then return node("expr", { expr_kind = "name", name = v.text }, v.origin) end
  if is_tag(v, "Expr") then
    if v.kind == "binop" then return node("expr", { expr_kind = "binop", op = v.op, left = normalize_expr(ctx, v.a), right = normalize_expr(ctx, v.b) }, v.origin) end
    if v.kind == "unop" then return node("expr", { expr_kind = "unop", op = v.op, value = normalize_expr(ctx, v.a) }, v.origin) end
    if v.kind == "field" then return node("expr", { expr_kind = "field", base = normalize_expr(ctx, v.base), field = v.field }, v.origin) end
    if v.kind == "index" then return node("expr", { expr_kind = "index", base = normalize_expr(ctx, v.base), index = normalize_expr(ctx, v.index) }, v.origin) end
    if v.kind == "call" then
      local args = {}; local n = v.args.n or #v.args
      for i = 1, n do args[i] = normalize_expr(ctx, v.args[i]) end
      return node("expr", { expr_kind = "call", callee = normalize_expr(ctx, v.callee), args = args }, v.origin)
    end
    if v.kind == "ctor" then
      local args = {}; local raw_args = v.args or {}; local n = raw_args.n or #raw_args
      for i = 1, n do args[i] = normalize_expr(ctx, raw_args[i]) end
      return node("expr", { expr_kind = "ctor", name = v.name, indexed = v.indexed or {}, args = args }, v.origin)
    end
    llb.fail("unknown expression kind " .. tostring(v.kind), { primary = v.origin, code = "E_BAD_EXPR" })
  end
  if tv == "number" or tv == "string" or tv == "boolean" then return node("expr", { expr_kind = "literal", value = v, literal_type = tv }, ctx and ctx.origin) end
  if tv == "table" then
    local arr, rec = {}, {}
    for i = 1, #v do arr[i] = normalize_expr(ctx, v[i]) end
    for k, x in pairs(v) do if type(k) ~= "number" then rec[k] = normalize_expr(ctx, x) end end
    return node("expr", { expr_kind = "table", array = arr, record = rec }, origin_of(v) or (ctx and ctx.origin))
  end
  llb.fail("expected expression, got " .. repr(v), { primary = origin_of(v) or (ctx and ctx.origin), code = "E_EXPECTED_EXPR" })
end

local function expand_spread(ctx, role_name, out, spread)
  local v = spread.value
  if is_tag(v, "Fragment") then
    if v.role ~= role_name then
      llb.fail("cannot spread " .. tostring(v.role) .. " fragment into " .. tostring(role_name) .. " role", {
        code = "E_SPREAD_ROLE", primary = spread.origin,
        labels = { { origin = v.origin, message = "fragment created here as role " .. tostring(v.role) } },
      })
    end
    for i = 1, #(v.items or {}) do out[#out + 1] = v.items[i] end
    return
  end
  if type(v) == "table" then
    local normalized = normalize_role(ctx, role_name, v)
    for i = 1, #(normalized or {}) do out[#out + 1] = normalized[i] end
    return
  end
  llb.fail("cannot spread value " .. repr(v), { primary = spread.origin, code = "E_BAD_SPREAD" })
end

local function norm_array(ctx, role_name, spec, v)
  if type(v) ~= "table" then llb.fail("expected table for " .. role_name .. " role", { primary = ctx and ctx.origin, code = "E_EXPECTED_TABLE" }) end
  local out, item_role = {}, spec.item_role or spec.item
  for i = 1, #v do
    local item = v[i]
    if is_tag(item, "Spread") then expand_spread(ctx, role_name, out, item)
    elseif item_role then out[#out + 1] = normalize_role(ctx, item_role, item)
    else out[#out + 1] = item end
  end
  return out
end

local function norm_record(ctx, role_name, spec, v)
  if type(v) ~= "table" then llb.fail("expected record table", { primary = ctx and ctx.origin, code = "E_EXPECTED_RECORD" }) end
  local out, value_role = {}, spec.value_role or spec.value
  for k, x in pairs(v) do if type(k) ~= "number" then out[k] = value_role and normalize_role(ctx, value_role, x) or x end end
  return out
end

local function norm_product(ctx, role_name, spec, v)
  if type(v) ~= "table" then llb.fail("expected product table", { primary = ctx and ctx.origin, code = "E_EXPECTED_PRODUCT" }) end
  local out, seen = {}, {}
  local type_role = spec.type_role or "type"
  local unique = spec.unique_names; if unique == nil then unique = true end
  local function add_field(f)
    if unique and seen[f.name] then
      llb.fail("duplicate product field '" .. tostring(f.name) .. "'", { code = "E_DUPLICATE_FIELD", primary = f.origin, labels = { { origin = seen[f.name].origin, message = "first field is here" } } })
    end
    seen[f.name] = f; out[#out + 1] = f
  end
  for i = 1, #v do
    local item = v[i]
    if is_tag(item, "Spread") then
      local tmp = {}
      expand_spread(ctx, role_name, tmp, item)
      for j = 1, #tmp do add_field(tmp[j]) end
    elseif is_tag(item, "Capture") then
      if not is_tag(item.subject, "Symbol") then llb.fail("product capture subject must be a symbol", { primary = item.origin }) end
      add_field({ tag = "field", name = item.subject.text, type = normalize_role(ctx, type_role, item.value), origin = item.origin })
    elseif is_tag(item, "CaptureInit") then
      local c = item.capture
      if not is_tag(c.subject, "Symbol") then llb.fail("product initializer subject must be a symbol", { primary = item.origin }) end
      add_field({ tag = "field", name = c.subject.text, type = normalize_role(ctx, type_role, c.value), init = normalize_expr(ctx, item.init), origin = item.origin })
    else
      llb.fail("product entries must be typed names or spreads, got " .. repr(item), { primary = origin_of(item) or (ctx and ctx.origin), code = "E_BAD_PRODUCT_ENTRY", notes = { "write x [T] for a typed field" } })
    end
  end
  return out
end

local function norm_sum(ctx, role_name, spec, v)
  if type(v) ~= "table" then llb.fail("expected sum/protocol table", { primary = ctx and ctx.origin, code = "E_EXPECTED_SUM" }) end
  local out, seen = {}, {}
  local payload_role = spec.payload_role or "product"
  local function add_variant(name, payload, origin)
    if seen[name] then llb.fail("duplicate variant '" .. tostring(name) .. "'", { code = "E_DUPLICATE_VARIANT", primary = origin, labels = { { origin = seen[name], message = "first variant is here" } } }) end
    seen[name] = origin; out[#out + 1] = { tag = "variant", name = name, payload = payload, origin = origin }
  end
  for i = 1, #v do
    local item = v[i]
    if is_tag(item, "Spread") then expand_spread(ctx, role_name, out, item)
    elseif is_tag(item, "Symbol") then add_variant(item.text, nil, item.origin)
    elseif is_tag(item, "Name") then add_variant(item.text, nil, item.origin)
    elseif is_tag(item, "Expr") and item.kind == "call" and is_tag(item.callee, "Symbol") then
      if (item.args.n or #item.args) ~= 1 or type(item.args[1]) ~= "table" then llb.fail("variant payload must be a single product table", { primary = item.origin }) end
      add_variant(item.callee.text, normalize_role(ctx, payload_role, item.args[1]), item.origin)
    else
      llb.fail("sum entries must be variants or spreads, got " .. repr(item), { primary = origin_of(item) or (ctx and ctx.origin), code = "E_BAD_SUM_ENTRY" })
    end
  end
  return out
end

normalize_role = function(ctx, role_name, v)
  ctx = ctx or {}
  local lang = ctx.lang
  local spec = (lang and lang.roles and lang.roles[role_name]) or {}
  local kind = spec.kind or role_name
  local subctx = shallow_copy(ctx); subctx.role = role_name; subctx.role_spec = spec
  if spec.normalize then return spec.normalize(lang, subctx, v) end
  if kind == "name" then return norm_name(subctx, v) end
  if kind == "type" then return norm_type(subctx, v) end
  if kind == "expr" then return normalize_expr(subctx, v) end
  if kind == "array" then return norm_array(subctx, role_name, spec, v) end
  if kind == "record" then return norm_record(subctx, role_name, spec, v) end
  if kind == "product" then return norm_product(subctx, role_name, spec, v) end
  if kind == "sum" or kind == "protocol" then return norm_sum(subctx, role_name, spec, v) end
  if kind == "mixed" then return { array = norm_array(subctx, role_name, spec, v), record = norm_record(subctx, role_name, spec, v) } end
  if kind == "string" then if type(v) == "string" then return v end; llb.fail("expected string", { primary = ctx.origin }) end
  if kind == "number" then if type(v) == "number" then return v end; llb.fail("expected number", { primary = ctx.origin }) end
  if kind == "boolean" then if type(v) == "boolean" then return v end; llb.fail("expected boolean", { primary = ctx.origin }) end
  if kind == "value" or kind == "identity" then return v end
  llb.fail("unknown role kind " .. tostring(kind), { primary = ctx.origin, code = "E_UNKNOWN_ROLE_KIND" })
end
llb.normalize_role, llb.normalize_expr = normalize_role, normalize_expr

local function stage_missing_slots(stage)
  local out = {}
  if not is_tag(stage, "Stage") then return out end
  local slots = stage.head and stage.head.slots or {}
  local seen = stage.seen or {}
  for i = 1, #slots do
    local slot = slots[i]
    if slot and not slot.optional and not seen[slot.name] then
      out[#out + 1] = slot
    end
  end
  return out
end

function llb.is_stage(v) return is_tag(v, "Stage") end
function llb.stage_head(v) if is_tag(v, "Stage") and v.head then return v.head.name end; return nil end
function llb.stage_missing_slots(v) return stage_missing_slots(v) end
function llb.is_complete(v) return not is_tag(v, "Stage") or #stage_missing_slots(v) == 0 end

-- ---------------------------------------------------------------------------
-- Runtime heads
-- ---------------------------------------------------------------------------

local RuntimeHead, RuntimeStage = {}, {}
local function role_kind(lang, role) local s = lang.roles[role]; return (s and s.kind) or role end
local function slot_channel(lang, slot)
  local k = role_kind(lang, slot.role)
  if k == "name" then return "name" end
  if k == "type" then return "index:type" end
  if k == "string" then return "call:string" end
  if k == "number" then return "call:number" end
  if k == "boolean" then return "call:boolean" end
  if k == "array" or k == "record" or k == "mixed" or k == "product" or k == "sum" or k == "protocol" then return "call:table" end
  if k == "expr" or k == "value" or k == "identity" then return "call:any" end
  return "call:any"
end
local function channels_overlap(a, b)
  if a == b then return true end
  if starts_with(a, "call:") and b == "call:any" then return true end
  if starts_with(b, "call:") and a == "call:any" then return true end
  return false
end
local function validate_slot_ambiguity(lang, head_name, slots)
  for i = 1, #slots - 1 do
    local a, b = slots[i], slots[i + 1]
    if a.optional and b.optional then
      local ca, cb = slot_channel(lang, a), slot_channel(lang, b)
      if channels_overlap(ca, cb) then
        llb.fail("ambiguous optional slot sequence in head " .. tostring(head_name) .. ": slot " .. tostring(a.name) .. " [" .. tostring(a.role) .. "] and slot " .. tostring(b.name) .. " [" .. tostring(b.role) .. "] can both consume " .. tostring(ca == cb and ca or "call") .. " input", {
          code = "E_AMBIGUOUS_OPTIONAL_SLOTS",
          primary = b.origin or a.origin,
          labels = { { origin = a.origin, message = "first optional slot is here" } },
          notes = { "LLB consumes slots greedily with no backtracking; adjacent optional slots must use disjoint syntactic channels." },
        }, 2)
      end
    end
  end
end
local function type_slot(lang, slot, value) return role_kind(lang, slot.role) == "type" and (llb.is_type_like(value) or is_tag(value, "Symbol") or type(value) == "string") end
local function action_fits(lang, slot, action, value, argc)
  local k = role_kind(lang, slot.role)
  if k == "name" then return action == "name" end
  if k == "type" then return action == "index" and type_slot(lang, slot, value) end
  if k == "string" then return action == "call" and argc == 1 and type(value) == "string" end
  if k == "number" then return action == "call" and argc == 1 and type(value) == "number" end
  if k == "boolean" then return action == "call" and argc == 1 and type(value) == "boolean" end
  if k == "expr" then return action == "call" and argc <= 1 end
  if k == "array" or k == "record" or k == "mixed" or k == "product" or k == "sum" or k == "protocol" then return action == "call" and argc == 1 and type(value) == "table" end
  return action == "call"
end
local function remaining_optional(slots, i) for j = i, #slots do if not slots[j].optional then return false end end; return true end

local function stage_origin_from_value(value, fallback)
  if type(value) == "table" then
    return rawget(value, "__llb_origin") or rawget(value, "origin") or origin_of(value) or fallback
  end
  return fallback
end

function llb.at(origin, value)
  if type(value) == "table" then
    rawset(value, "__llb_origin", origin)
    if rawget(value, "origin") == nil then rawset(value, "origin", origin) end
    local m = rawget(value, "__llb")
    if m and m.origin == nil then m.origin = origin end
    return value
  end
  return { __llb_tag = "OriginValue", value = value, __llb_origin = origin, origin = origin }
end

local function unwrap_origin_value(v)
  if is_tag(v, "OriginValue") then return v.value, v.__llb_origin or v.origin end
  return v, stage_origin_from_value(v)
end

local function normalize_stage_slots(stage)
  local fields, origins = {}, {}
  for i = 1, #stage.head.slots do
    local slot = stage.head.slots[i]
    if stage.seen[slot.name] then
      local raw = stage.raw[slot.name]
      origins[slot.name] = stage.origins[slot.name]
      fields[slot.name] = normalize_role({ lang = stage.lang, head = stage.head.name, origin = origins[slot.name] }, slot.role, raw)
    elseif slot.optional then
      fields[slot.name] = slot.default
    else
      llb.fail("missing slot " .. tostring(slot.name), { primary = stage.origin, code = "E_MISSING_SLOT" })
    end
  end
  return fields, origins
end

local function build_stage(stage)
  local fields, origins = normalize_stage_slots(stage)
  fields.origin = fields.origin or stage.origin
  fields.slot_origins = origins
  local out = stage.head.emit and stage.head.emit(fields, stage.lang, { head = stage.head, raw = stage.raw, origins = origins, stage = stage }) or { tag = stage.head.tag or stage.head.name, fields = fields }
  return attach_node_meta(out, stage.head.tag or stage.head.name, { language = stage.lang.name, head = stage.head.name, head_spec = stage.head, fields = fields, slot_origins = origins, raw = stage.raw, origin = stage.origin })
end
local function maybe_finish(stage) if remaining_optional(stage.head.slots, stage.next_index) then return build_stage(stage) end; return stage end
local function consume(stage, action, value, argc, origin)
  local override_origin
  value, override_origin = unwrap_origin_value(value)
  origin = override_origin or origin
  local slots, i = stage.head.slots, stage.next_index
  while i <= #slots do
    local slot = slots[i]
    if action_fits(stage.lang, slot, action, value, argc or 0) then
      local ns = setmetatable({ __llb_tag = "Stage", lang = stage.lang, head = stage.head, raw = shallow_copy(stage.raw), origins = shallow_copy(stage.origins), seen = shallow_copy(stage.seen), next_index = i + 1, origin = stage.origin }, RuntimeStage)
      ns.raw[slot.name], ns.origins[slot.name], ns.seen[slot.name] = value, origin or stage.origin, true
      return maybe_finish(ns)
    elseif slot.optional then i = i + 1
    else llb.fail("expected slot " .. tostring(slot.name) .. " [" .. tostring(slot.role) .. "], got " .. action .. " " .. repr(value), { primary = origin or stage.origin, code = "E_BAD_SLOT" }) end
  end
  llb.fail("too many arguments for head " .. tostring(stage.head.name), { primary = origin or stage.origin, code = "E_TOO_MANY_ARGUMENTS" })
end
local function head_origin(h)
  return h.origin or source.capture("head", { hint = h.spec.name })
end
local function start_stage(h) return setmetatable({ __llb_tag = "Stage", lang = h.lang, head = h.spec, raw = {}, origins = {}, seen = {}, next_index = 1, origin = head_origin(h) }, RuntimeStage) end
RuntimeHead.__index = function(self, key)
  if RuntimeHead[key] then return RuntimeHead[key] end
  local o = source.capture("head-name", { hint = key })
  local name_value, override_origin = unwrap_origin_value(key)
  o = override_origin or o
  if is_tag(name_value, "Name") then
    return consume(start_stage(self), "name", name_value, 1, o)
  end
  if is_tag(name_value, "Symbol") then
    return consume(start_stage(self), "name", llb.name(name_value.text, { origin = o }), 1, o)
  end
  return consume(start_stage(self), "name", llb.name(name_value, { origin = o }), 1, o)
end
RuntimeHead.__call = function(self, ...)
  local p, o = pack(...), source.capture("head-call", { hint = self.spec.name })
  if p.n > 0 and is_tag(p[1], "OriginValue") then o = p[1].__llb_origin or p[1].origin or o end
  if p.n == 0 and #self.spec.slots == 0 then return build_stage(setmetatable({ __llb_tag = "Stage", lang = self.lang, head = self.spec, raw = {}, origins = {}, seen = {}, next_index = 1, origin = o }, RuntimeStage)) end
  local v = p.n == 0 and UNIT or p[1]
  if p.n == 1 and v == nil then v = NIL end
  if p.n <= 1 then return consume(start_stage(self), "call", v, p.n, o) end
  return consume(start_stage(self), "call", p, p.n, o)
end
RuntimeStage.__index = function(self, key)
  if RuntimeStage[key] then return RuntimeStage[key] end
  local o = source.capture("slot-index")
  return consume(self, "index", key, 1, o)
end
RuntimeStage.__call = function(self, ...)
  local p, o = pack(...), source.capture("slot-call")
  local v = p.n == 0 and UNIT or p[1]
  if p.n == 1 and v == nil then v = NIL end
  if p.n <= 1 then return consume(self, "call", v, p.n, o) end
  return consume(self, "call", p, p.n, o)
end
local HeadAt = {}
HeadAt.__index = function(self, key)
  local h = setmetatable({ __llb_tag = "Head", lang = self.head.lang, spec = self.head.spec, origin = self.origin }, RuntimeHead)
  return RuntimeHead.__index(h, key)
end
HeadAt.__call = function(self, ...)
  local h = setmetatable({ __llb_tag = "Head", lang = self.head.lang, spec = self.head.spec, origin = self.origin }, RuntimeHead)
  return RuntimeHead.__call(h, ...)
end

function RuntimeHead:at(origin)
  return setmetatable({ __llb_tag = "HeadAt", head = self, origin = origin }, HeadAt)
end

local function runtime_head(lang, spec) return setmetatable({ __llb_tag = "Head", lang = lang, spec = spec }, RuntimeHead) end

-- ---------------------------------------------------------------------------
-- Context, scopes, passes, analysis
-- ---------------------------------------------------------------------------

local Context = {}; Context.__index = Context
function llb.context(lang, opts)
  opts = opts or {}
  return setmetatable({ __llb_tag = "Context", lang = lang, opts = opts, diagnostics = opts.diagnostics or llb.diagnostics(), scopes = { {} }, current = {}, data = {}, fatal = opts.fatal }, Context)
end
function Context:error(spec) spec = spec or {}; spec.severity = "error"; local d = self.diagnostics:add(llb.diagnostic(spec)); if self.fatal then error(d:render(), 2) end; return d end
function Context:warn(spec) spec = spec or {}; spec.severity = "warning"; return self.diagnostics:add(llb.diagnostic(spec)) end
function Context:push_scope(name) self.scopes[#self.scopes + 1] = { __name = name } end
function Context:pop_scope() if #self.scopes > 1 then self.scopes[#self.scopes] = nil end end
function Context:with_scope(name, fn) self:push_scope(name); local ok, a, b, c = pcall(fn); self:pop_scope(); if not ok then error(a, 0) end; return a, b, c end
function Context:define(name, value, origin)
  local text = is_tag(name, "Name") and name.text or (is_tag(name, "Symbol") and name.text or tostring(name))
  local top = self.scopes[#self.scopes]
  if top[text] then self:error { code = "E_DUPLICATE_SYMBOL", message = "duplicate symbol '" .. text .. "'", primary = origin or origin_of(value), labels = { { origin = origin_of(top[text]) or top[text].origin, message = "first definition is here" } } } end
  top[text] = value or { name = text, origin = origin }
  return top[text]
end
function Context:lookup(name)
  local text = is_tag(name, "Name") and name.text or (is_tag(name, "Symbol") and name.text or tostring(name))
  for i = #self.scopes, 1, -1 do if self.scopes[i][text] ~= nil then return self.scopes[i][text] end end
  return nil
end
function Context:typeof(e, expected) local ts = self.lang and self.lang.type_system; return ts and ts.typeof and ts.typeof(self, e, expected) or nil end
function Context:assignable(got, expected, origin) local ts = self.lang and self.lang.type_system; if ts and ts.assignable then return ts.assignable(self, got, expected, origin) end; return got == expected end
function Context:format_type(T) local ts = self.lang and self.lang.type_system; if ts and ts.format then return ts.format(T) end; return is_tag(T, "Type") and T.name or tostring(T) end
llb.Context = Context

local function walk(v, fn, parent, key, seen)
  if type(v) ~= "table" then return end
  seen = seen or {}; if seen[v] then return end; seen[v] = true
  if fn(v, parent, key) == false then return end
  for k, child in pairs(v) do if k ~= "__llb" and k ~= "origin" and k ~= "__llb_tag" and type(child) == "table" then walk(child, fn, v, k, seen) end end
end
llb.walk = walk

local Analysis = {}; Analysis.__index = Analysis
function Analysis:has_errors() return self.diagnostics:has_errors() end
function Analysis:render_diagnostics(opts) return self.diagnostics:render(opts) end
function Analysis:format_diagnostics(opts) return self:render_diagnostics(opts) end
function Analysis:get_ast() return self.ast end
function Analysis:lsp_index()
  local idx = { __llb_tag = "LspIndex", diagnostics = self.diagnostics.items, symbols = {}, definitions = {}, references = {}, hovers = {} }
  walk(self.ast, function(n)
    if not is_tag(n, "Node") then return end
    local m = n.__llb or {}; local hs = m.head_spec
    if hs and hs.lsp and hs.lsp.symbol then
      local sym = hs.lsp.symbol(n, m, self); if sym then idx.symbols[#idx.symbols + 1] = sym end
    elseif self.lang and self.lang.lsp and self.lang.lsp.symbols and self.lang.lsp.symbols[n.tag] then
      local sym = self.lang.lsp.symbols[n.tag](n, m, self); if sym then idx.symbols[#idx.symbols + 1] = sym end
    elseif m.fields and m.fields.name then
      local name = type(m.fields.name) == "table" and m.fields.name.text or m.fields.name
      if name then idx.symbols[#idx.symbols + 1] = { name = tostring(name), kind = m.head or "Object", origin = origin_of(m.fields.name) or n.origin, node = n } end
    end
  end)
  return idx
end
llb.Analysis = Analysis

-- ---------------------------------------------------------------------------
-- Language definition and loading
-- ---------------------------------------------------------------------------

local Language = {}; Language.__index = Language
local BASE_ENV = { assert = assert, error = error, ipairs = ipairs, next = next, pairs = pairs, pcall = pcall, xpcall = xpcall, print = print, select = select, tonumber = tonumber, tostring = tostring, type = type, unpack = unpack, math = math, string = string, table = table, coroutine = coroutine, require = require }
local function builtin_roles() return { name = { kind = "name" }, type = { kind = "type" }, expr = { kind = "expr" }, string = { kind = "string" }, number = { kind = "number" }, boolean = { kind = "boolean" }, value = { kind = "value" }, identity = { kind = "identity" } } end
local function normalize_slot_decl(s) local spec = s.spec or {}; return { name = s.name, role = s.role, optional = spec.optional or s.optional or false, default = spec.default, origin = s.origin, spec = spec } end

local PREV_NIL = {}
local UseSession = {}
UseSession.__index = UseSession
llb.UseSession = UseSession

local function is_identifier(s)
  return type(s) == "string" and s:match("^[_%a][_%w]*$") ~= nil
end

local function copy_into(dst, src)
  for k, v in pairs(src or {}) do dst[k] = v end
  return dst
end

function llb.base_env(kind)
  if type(kind) == "table" then return shallow_copy(kind) end
  if kind == "inherit" then return shallow_copy(_G) end
  return shallow_copy(BASE_ENV)
end

local function helper_exports()
  return {
    N = llb.N,
    spread = llb.spread,
    _ = llb.spread,
    here = llb.here,
    at_origin = llb.at,
    with_origin = llb.with_origin,
  }
end

local function old_index_value(old_index, target, key)
  if old_index == nil then return nil end
  if type(old_index) == "function" then return old_index(target, key) end
  return old_index[key]
end

local function old_newindex_set(old_newindex, target, key, value)
  if old_newindex == nil then rawset(target, key, value)
  elseif type(old_newindex) == "function" then old_newindex(target, key, value)
  else old_newindex[key] = value end
end

function llb.make_env(lang, opts)
  opts = opts or {}
  local env = llb.base_env(opts.base or "safe")
  copy_into(env, lang and lang.exports or {})
  if opts.helpers ~= false then copy_into(env, helper_exports()) end
  copy_into(env, opts.exports)
  if opts.unsafe then env.io, env.os, env.debug, env.package = io, os, debug, package end
  env._G = env
  return env
end

local function install_auto_names(target, session, opts)
  if opts.auto_names == false then return end
  local old_mt = getmetatable(target)
  local old_index = old_mt and old_mt.__index
  local old_newindex = old_mt and old_mt.__newindex
  local mt = {}
  if old_mt then for k, v in pairs(old_mt) do mt[k] = v end end
  mt.__llb_session = session
  mt.__index = function(t, key)
    local old = old_index_value(old_index, t, key)
    if old ~= nil then return old end
    if is_identifier(key) then
      local origin = source.capture("auto-name", { hint = key, skip = 1 })
      local maker = opts.auto_name or (session.lang and session.lang.auto_name)
      local value = maker and maker(key, origin) or llb.symbol(key, { origin = origin })
      rawset(t, key, value)
      session.auto_installed[key] = true
      session.auto_values[key] = value
      return value
    end
    return nil
  end
  mt.__newindex = function(t, key, value)
    if opts.strict and rawget(t, key) == nil then error("strict LLB environment: assignment to unknown global " .. tostring(key), 2) end
    old_newindex_set(old_newindex, t, key, value)
  end
  session.previous_mt = old_mt
  session.metatable_installed = true
  setmetatable(target, mt)
end

function llb.install_env(env, target, opts, session)
  opts = opts or {}
  target = target or _G
  session = session or setmetatable({ __llb_tag = "UseSession", env = env, target = target, installed = {}, previous = {}, skipped = {}, active = true, auto_installed = {}, auto_values = {} }, UseSession)
  for k, v in pairs(env or {}) do
    if k ~= "_G" then
      local cur = rawget(target, k)
      if cur == nil or opts.override then
        session.installed[k] = true
        session.previous[k] = cur == nil and PREV_NIL or cur
        rawset(target, k, v)
      else
        session.skipped[k] = true
      end
    end
  end
  install_auto_names(target, session, opts)
  return session
end

function llb.use(lang, opts)
  opts = opts or {}
  local scope = opts.scope or (opts.global == false and "env" or "permanent")
  local env = llb.make_env(lang, opts)
  local target = opts.target or _G
  local session = setmetatable({
    __llb_tag = "UseSession",
    lang = lang,
    env = env,
    target = target,
    scope = scope,
    installed = {},
    previous = {},
    skipped = {},
    auto_installed = {},
    auto_values = {},
    active = true,
  }, UseSession)
  rawset(env, "__llb_session", session)
  if scope == "env" then
    install_auto_names(env, session, opts)
  else
    llb.install_env(env, target, opts, session)
  end
  if opts.searcher and lang and lang.install_searcher then lang:install_searcher(opts) end
  return session
end

function UseSession:close()
  if not self.active then return false end
  self.active = false
  local target = self.scope == "env" and self.env or self.target
  for k, v in pairs(self.auto_values or {}) do
    if rawget(target, k) == v then rawset(target, k, nil) end
  end
  if self.scope ~= "env" then
    for k in pairs(self.installed or {}) do
      local prev = self.previous[k]
      if prev == PREV_NIL then rawset(target, k, nil)
      elseif prev ~= nil then rawset(target, k, prev) end
    end
  end
  local mt = getmetatable(target)
  if mt and mt.__llb_session == self then setmetatable(target, self.previous_mt) end
  return true
end

function llb.with_use(lang, opts, fn)
  opts = shallow_copy(opts or {})
  opts.scope = opts.scope or "scoped"
  local session = llb.use(lang, opts)
  local ok, a, b, c = pcall(fn, session.env, session)
  session:close()
  if not ok then error(a, 0) end
  return a, b, c
end

function Language:fragment(role, value)
  local spec = self.roles and self.roles[role] or {}
  return llb.fragment(role, normalize_role({ lang = self, origin = source.capture("fragment-normalize") }, role, value), source.capture("fragment"), {
    lang = self,
    role_spec = spec,
    algebra = spec.algebra,
    payload_role = spec.payload_role or spec.payload,
  })
end
function Language:env(opts)
  opts = shallow_copy(opts or {})
  if opts.env then opts.exports = opts.env end
  opts.scope = opts.scope or "env"
  opts.auto_names = opts.auto_names ~= false
  local session = llb.use(self, opts)
  return session.env
end
function Language:use(opts) return llb.use(self, opts) end
function Language:with_use(opts, fn) return llb.with_use(self, opts, fn) end
function Language:loadstring(src, chunkname, opts) chunkname = chunkname or self.name; source.register(chunkname, src); local f, err = compile_lua(src, chunkname); if not f then error(err, 2) end; setfenv0(f, self:env(opts)); return f end
function Language:loadfile(path, opts) local f, err = io.open(path, "rb"); if not f then error(err, 2) end; local src = f:read("*a") or ""; f:close(); return self:loadstring(src, "@" .. path, opts) end
function Language:analyze_string(src, chunkname, opts)
  opts = opts or {}; local bag = llb.diagnostics(); source.register(chunkname or self.name, src)
  local f, err = compile_lua(src, chunkname or self.name)
  if not f then bag:error { code = "E_LUA_PARSE", message = tostring(err) }; return setmetatable({ __llb_tag = "Analysis", lang = self, ast = nil, diagnostics = bag, source = src, chunkname = chunkname }, Analysis) end
  setfenv0(f, self:env(opts)); local ok, ast = pcall(f)
  if not ok then
    if is_tag(ast, "Diagnostic") then bag:add(ast)
    else bag:error { code = "E_DSL_EXEC", message = tostring(ast) } end
    return setmetatable({ __llb_tag = "Analysis", lang = self, ast = nil, diagnostics = bag, source = src, chunkname = chunkname }, Analysis)
  end
  local analysis = setmetatable({ __llb_tag = "Analysis", lang = self, ast = ast, diagnostics = bag, source = src, chunkname = chunkname }, Analysis)
  local ctx = llb.context(self, { diagnostics = bag, fatal = false })
  for i = 1, #self.passes do
    local pass = self.passes[i]
    if pass.run then local okp, perr = pcall(pass.run, ctx, analysis); if not okp then bag:error { code = "E_PASS", message = "pass " .. tostring(pass.name) .. " failed: " .. tostring(perr), primary = origin_of(ast) } end end
  end
  return analysis
end
function Language:analyze_file(path, opts) local f, err = io.open(path, "rb"); if not f then local bag = llb.diagnostics(); bag:error { code = "E_OPEN", message = tostring(err) }; return setmetatable({ __llb_tag = "Analysis", lang = self, ast = nil, diagnostics = bag }, Analysis) end; local src = f:read("*a") or ""; f:close(); return self:analyze_string(src, "@" .. path, opts) end

function Language:install_searcher(opts)
  opts = opts or {}
  local searchers = package.searchers or package.loaders
  if not searchers then return false end
  if self._llb_searcher then
    for _, s in ipairs(searchers) do if s == self._llb_searcher then return true end end
  end
  local paths = opts.search_paths or self.search_paths or { "./?.lua", "./?/init.lua", "lua/?.lua", "lua/?/init.lua" }
  local lang = self
  local function searcher(mod_name)
    local tried = {}
    for i = 1, #paths do
      local path = paths[i]:gsub("%?", mod_name)
      local f = io.open(path, "rb")
      if f then
        f:close()
        return function()
          local loader = opts.loader
          local chunk = loader and loader(lang, path, opts) or lang:loadfile(path, opts.load_opts or opts)
          return chunk()
        end
      end
      tried[#tried + 1] = path
    end
    return "\n\tno file found (tried: " .. table.concat(tried, ", ") .. ")"
  end
  self._llb_searcher = searcher
  table.insert(searchers, searcher)
  return true
end

local function head_check_pass()
  return { name = "llb.head_checks", run = function(ctx, analysis)
    walk(analysis.ast, function(n)
      if not is_tag(n, "Node") then return end
      local m = n.__llb or {}; local hs = m.head_spec
      if hs and hs.check then local ok, err = pcall(hs.check, ctx, n, m.fields or {}, m); if not ok then ctx:error { code = "E_CHECK", message = tostring(err), primary = n.origin } end end
    end)
  end }
end

local function define_language(name, decls)
  local lang = setmetatable({ __llb_tag = "Language", name = tostring(name), roles = builtin_roles(), heads = {}, exports = { N = llb.N, spread = llb.spread, _ = llb.spread }, passes = {}, lsp = {}, declarations = decls or {} }, Language)
  for i = 1, #(decls or {}) do
    local d = decls[i]
    if is_tag(d, "RoleDecl") then local spec = shallow_copy(d.spec or {}); spec.kind = d.kind or spec.kind or "array"; spec.origin = d.origin; lang.roles[d.name] = spec
    elseif is_tag(d, "ScalarDecl") then lang.exports[d.name] = llb.type(d.name, { kind = "scalar", spec = d.spec or {}, origin = d.origin })
    elseif is_tag(d, "TypeCtorDecl") then lang.exports[d.name] = llb.type_ctor(d.name, { arity = d.arity or 1, emit = d.emit, origin = d.origin })
    elseif is_tag(d, "HelperDecl") then lang.exports[d.name] = d.value
    elseif is_tag(d, "PassDecl") then lang.passes[#lang.passes + 1] = d
    elseif is_tag(d, "LspDecl") then lang.lsp[d.name] = d.spec or {}
    elseif is_tag(d, "TypeSystemDecl") then lang.type_system = d.spec or {} end
  end
  for role in pairs(lang.roles) do if not lang.exports[role] then lang.exports[role] = function(tbl) return lang:fragment(role, tbl) end end end
  lang.exports.eq = lang.exports.eq or function(a, b) return expr("binop", { op = "==", a = a, b = b }) end
  lang.exports.ne = lang.exports.ne or function(a, b) return expr("binop", { op = "~=", a = a, b = b }) end
  lang.exports.And = lang.exports.And or function(a, b) return call_expr(llb.symbol("And"), pack(a, b)) end
  lang.exports.Or  = lang.exports.Or  or function(a, b) return call_expr(llb.symbol("Or"),  pack(a, b)) end
  lang.exports.Not = lang.exports.Not or function(a) return call_expr(llb.symbol("Not"), pack(a)) end
  lang.exports.select = lang.exports.select or function(c, a, b) return call_expr(llb.symbol("select"), pack(c, a, b)) end
  lang.exports.as = lang.exports.as or llb.expr_ctor("as")
  lang.exports.bitcast = lang.exports.bitcast or llb.expr_ctor("bitcast")
  lang.exports.null = lang.exports.null or llb.expr_ctor("null")
  lang.exports.sizeof = lang.exports.sizeof or llb.expr_ctor("sizeof")
  lang.exports.alignof = lang.exports.alignof or llb.expr_ctor("alignof")
  for i = 1, #(decls or {}) do
    local d = decls[i]
    if is_tag(d, "HeadDecl") then
      local slots = {}; for j = 1, #d.slots do slots[j] = normalize_slot_decl(d.slots[j]) end
      validate_slot_ambiguity(lang, d.name, slots)
      local spec = { name = d.name, tag = d.tag or d.name, slots = slots, emit = d.emit, check = d.check, lower = d.lower, lsp = d.lsp, format = d.format, origin = d.origin, raw = d }
      lang.heads[d.name] = spec; lang.exports[d.name] = runtime_head(lang, spec)
    end
  end
  table.insert(lang.passes, 1, head_check_pass())
  return lang
end
function llb.define(name) return function(decls) return define_language(name, decls) end end
llb.Language = Language

-- ---------------------------------------------------------------------------
-- Formatting
-- ---------------------------------------------------------------------------

local doc = {}
llb.doc = doc

local function is_doc(v)
  return type(v) == "table" and rawget(v, "__llb_doc") ~= nil
end

local function doc_node(kind, fields)
  fields = fields or {}
  fields.__llb_doc = kind
  return fields
end

local function docify(v)
  if v == nil or v == ABSENT then return doc_node("nil") end
  if is_doc(v) then return v end
  if type(v) == "table" then
    local parts = {}
    for i = 1, #v do parts[i] = docify(v[i]) end
    return doc_node("concat", { parts = parts })
  end
  return doc_node("text", { text = tostring(v) })
end

function doc.nil_doc() return doc_node("nil") end
function doc.text(s) return doc_node("text", { text = tostring(s or "") }) end
function doc.space() return doc_node("text", { text = " " }) end
function doc.line() return doc_node("line") end
function doc.softline() return doc_node("softline") end
function doc.hardline() return doc_node("hardline") end
function doc.concat(parts) return docify(parts or {}) end
function doc.group(parts) return doc_node("group", { doc = docify(parts) }) end
function doc.indent(parts, amount) return doc_node("indent", { amount = amount, doc = docify(parts) }) end
doc.nest = doc.indent

function doc.join(sep, parts)
  parts = parts or {}
  sep = docify(sep or "")
  local out = {}
  for i = 1, #parts do
    if i > 1 then out[#out + 1] = sep end
    out[#out + 1] = parts[i]
  end
  return doc.concat(out)
end

function doc.parens(parts) return doc.concat { "(", parts, ")" } end
function doc.brackets(parts) return doc.concat { "[", parts, "]" } end
function doc.braces(parts) return doc.concat { "{", parts, "}" } end

local function flat_len(d)
  d = docify(d)
  local k = rawget(d, "__llb_doc")
  if k == "nil" then return 0 end
  if k == "text" then return #(d.text or "") end
  if k == "line" or k == "softline" then return 1 end
  if k == "hardline" then return math.huge end
  if k == "indent" or k == "group" then return flat_len(d.doc) end
  if k == "concat" then
    local n = 0
    for i = 1, #(d.parts or {}) do
      local m = flat_len(d.parts[i])
      if m == math.huge then return m end
      n = n + m
    end
    return n
  end
  return 0
end

local function render_doc(d, state, flat)
  d = docify(d)
  local k = rawget(d, "__llb_doc")
  if k == "nil" then
    return
  elseif k == "text" then
    local s = d.text or ""
    state.out[#state.out + 1] = s
    state.col = state.col + #s
  elseif k == "line" or k == "softline" then
    if flat then
      state.out[#state.out + 1] = " "
      state.col = state.col + 1
    else
      state.out[#state.out + 1] = "\n" .. string.rep(" ", state.indent)
      state.col = state.indent
    end
  elseif k == "hardline" then
    state.out[#state.out + 1] = "\n" .. string.rep(" ", state.indent)
    state.col = state.indent
  elseif k == "concat" then
    for i = 1, #(d.parts or {}) do render_doc(d.parts[i], state, flat) end
  elseif k == "indent" then
    local old = state.indent
    state.indent = state.indent + (d.amount or state.indent_width)
    render_doc(d.doc, state, flat)
    state.indent = old
  elseif k == "group" then
    local next_flat = flat or (state.col + flat_len(d.doc) <= state.width)
    render_doc(d.doc, state, next_flat)
  end
end

function llb.render(d, opts)
  opts = opts or {}
  local state = {
    out = {},
    width = opts.width or 100,
    indent = opts.base_indent or 0,
    indent_width = opts.indent or 2,
    col = opts.base_indent or 0,
  }
  render_doc(d, state, false)
  return table.concat(state.out)
end

local FormatContext = {}
FormatContext.__index = FormatContext
llb.FormatContext = FormatContext

local function format_context(opts)
  opts = opts or {}
  local f = setmetatable({
    opts = opts,
    lang = opts.lang,
    width = opts.width or 100,
    indent_width = opts.indent or 2,
    seen = opts.seen or {},
  }, FormatContext)
  return f
end

function FormatContext:text(s) return doc.text(s) end
function FormatContext:space() return doc.space() end
function FormatContext:line() return doc.line() end
function FormatContext:softline() return doc.softline() end
function FormatContext:hardline() return doc.hardline() end
function FormatContext:concat(parts) return doc.concat(parts) end
function FormatContext:group(parts) return doc.group(parts) end
function FormatContext:indent(parts, amount) return doc.indent(parts, amount or self.indent_width) end
function FormatContext:join(sep, parts) return doc.join(sep, parts) end
function FormatContext:parens(parts) return doc.parens(parts) end
function FormatContext:brackets(parts) return doc.brackets(parts) end
function FormatContext:braces(parts) return doc.braces(parts) end
function FormatContext:format(v) return llb.to_doc(v, self) end

function FormatContext:list(items, opts)
  opts = opts or {}
  local docs = {}
  for i = 1, #(items or {}) do docs[i] = opts.format and opts.format(items[i], self, i) or self:format(items[i]) end
  return doc.join(opts.sep or doc.concat { ",", doc.line() }, docs)
end

function FormatContext:braced_list(items, opts)
  opts = opts or {}
  if #(items or {}) == 0 then return doc.text("{}") end
  return doc.group {
    "{",
    doc.indent({
      doc.softline(),
      self:list(items, opts),
    }, opts.indent or self.indent_width),
    doc.softline(),
    "}",
  }
end

function FormatContext:block(items, opts)
  opts = opts or {}
  if #(items or {}) == 0 then return doc.text("{}") end
  local docs = {}
  for i = 1, #items do
    docs[#docs + 1] = opts.format and opts.format(items[i], self, i) or self:format(items[i])
    docs[#docs + 1] = ","
    if i < #items then docs[#docs + 1] = doc.line() end
  end
  return doc.concat {
    "{",
    doc.indent({ doc.line(), docs }, opts.indent or self.indent_width),
    doc.line(),
    "}",
  }
end

function FormatContext:name(v)
  if is_tag(v, "Name") or is_tag(v, "Symbol") then return doc.text(v.text) end
  if type(v) == "table" and rawget(v, "name") then return doc.text(tostring(v.name)) end
  return doc.text(tostring(v))
end

local function literal_doc(v)
  if v == NIL then return doc.text("nil") end
  if v == UNIT then return doc.text("()") end
  if v == ABSENT then return doc.text("<absent>") end
  local tv = type(v)
  if tv == "string" then return doc.text(string.format("%q", v)) end
  if tv == "number" or tv == "boolean" then return doc.text(tostring(v)) end
  if tv == "nil" then return doc.text("nil") end
  return nil
end

local function fallback_expr_doc(v, f)
  if v.kind == "binop" then return doc.group { f:format(v.a), " ", tostring(v.op), " ", f:format(v.b) } end
  if v.kind == "unop" then return doc.group { tostring(v.op), f:format(v.a) } end
  if v.kind == "field" then return doc.group { f:format(v.base), ".", tostring(v.field) } end
  if v.kind == "index" then return doc.group { f:format(v.base), "[", f:format(v.index), "]" } end
  if v.kind == "call" then
    local args = {}
    local raw_args, n = v.args or {}, (v.args and (v.args.n or #v.args)) or 0
    for i = 1, n do args[i] = raw_args[i] end
    return doc.group { f:format(v.callee), doc.parens(f:list(args, { sep = doc.concat { ",", doc.line() } })) }
  end
  if v.kind == "ctor" then
    local indexed = {}
    for i = 1, #(v.indexed or {}) do indexed[i] = doc.brackets(f:format(v.indexed[i])) end
    local args = {}
    local raw_args, n = v.args or {}, (v.args and (v.args.n or #v.args)) or 0
    for i = 1, n do args[i] = raw_args[i] end
    return doc.group { tostring(v.name), indexed, doc.parens(f:list(args, { sep = doc.concat { ",", doc.line() } })) }
  end
  return nil
end

local function generic_table_doc(v, f)
  local tag = tagof(v)
  if tag == "Expr" then
    local d = fallback_expr_doc(v, f)
    if d then return d end
  end
  if tag == "Name" or tag == "Symbol" then return doc.text(v.text) end
  if tag == "Type" then return doc.text(v.name) end
  if tag == "Capture" then return doc.group { f:format(v.subject), " [", f:format(v.value), "]" } end
  if tag == "CaptureInit" then return doc.group { f:format(v.capture), " (", f:format(v.init), ")" } end
  if tag == "Fragment" then return f:braced_list(v.items or {}) end
  if tag == "Node" then
    local m = rawget(v, "__llb") or {}
    return doc.group { tostring(m.head or v.tag or "node"), " ", f:braced_list(m.fields or v.fields or {}) }
  end

  local keys = {}
  for k in pairs(v) do
    if k ~= "__llb" and k ~= "__llb_tag" and k ~= "origin" then keys[#keys + 1] = k end
  end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  local items = {}
  for i = 1, #keys do
    local k = keys[i]
    items[i] = doc.group { tostring(k), " = ", f:format(v[k]) }
  end
  return f:braced_list(items)
end

function llb.to_doc(v, ctx)
  local f = getmetatable(ctx) == FormatContext and ctx or format_context(ctx or {})
  local lit = literal_doc(v)
  if lit then return lit end

  local tv = type(v)
  if tv ~= "table" then return doc.text(tostring(v)) end
  if f.seen[v] then return doc.text("<cycle>") end
  f.seen[v] = true

  local mt = getmetatable(v)
  local mt_format = mt and rawget(mt, "__llb_format")
  if mt_format then
    local out = mt_format(v, f)
    f.seen[v] = nil
    return docify(out)
  end

  local meta = rawget(v, "__llb") or {}
  local hs = meta.head_spec
  if hs and hs.format then
    local out = hs.format(v, f, meta)
    f.seen[v] = nil
    return docify(out)
  end

  local lang = f.lang or meta.language
  if type(lang) == "table" then
    local formatters = lang.formatters or (lang.format and lang.format.formatters)
    local key = meta.head or rawget(v, "tag") or tagof(v)
    local hook = formatters and key and formatters[key]
    if hook then
      local out = hook(v, f, meta)
      f.seen[v] = nil
      return docify(out)
    end
  end

  local out = generic_table_doc(v, f)
  f.seen[v] = nil
  return out
end

function llb.format_doc(value, opts)
  return llb.to_doc(value, format_context(opts or {}))
end

function llb.format(value, opts)
  opts = opts or {}
  return llb.render(llb.format_doc(value, opts), opts)
end

function Language:format_doc(value, opts)
  opts = shallow_copy(opts or {})
  opts.lang = opts.lang or self
  return llb.format_doc(value, opts)
end

function Language:format(value, opts)
  opts = shallow_copy(opts or {})
  opts.lang = opts.lang or self
  return llb.format(value, opts)
end

function Analysis:format_doc(opts)
  opts = shallow_copy(opts or {})
  opts.lang = opts.lang or self.lang
  return llb.format_doc(self.ast, opts)
end

function Analysis:format(opts)
  opts = shallow_copy(opts or {})
  opts.lang = opts.lang or self.lang
  return llb.format(self.ast, opts)
end

-- ---------------------------------------------------------------------------
-- Dumping and example language
-- ---------------------------------------------------------------------------

local function dump_value(v, indent, seen)
  indent = indent or ""; seen = seen or {}
  if v == NIL then return "nil" end; if v == UNIT then return "()" end; if v == ABSENT then return "<absent>" end
  local tv = type(v); if tv == "string" then return string.format("%q", v) end; if tv ~= "table" then return tostring(v) end; if seen[v] then return "<cycle>" end
  seen[v] = true
  local out, ni = { "{" }, indent .. "  "
  local tag = tagof(v); if tag then out[#out + 1] = ni .. "__tag = " .. string.format("%q", tostring(tag)) .. "," end
  local keys = {}; for k in pairs(v) do if k ~= "__llb" and k ~= "origin" and k ~= "__llb_tag" then keys[#keys + 1] = k end end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  for i = 1, #keys do local k = keys[i]; out[#out + 1] = ni .. tostring(k) .. " = " .. dump_value(v[k], ni, seen) .. "," end
  out[#out + 1] = indent .. "}"; seen[v] = nil; return table.concat(out, "\n")
end
function llb.dump(v) return dump_value(v) end

function llb.example_language()
  local g = llb.grammar
  return llb.define "Mini" {
    g.role .decls { kind = "array" },
    g.role .body { kind = "array" },
    g.role .product { kind = "product" },
    g.scalar .void, g.scalar .i32, g.scalar .u8, g.scalar .bool,
    g.type_ctor .ptr { arity = 1 },
    g.type_ctor .array { arity = 2 },
    g.head .module { g.slot .name [g.string], g.slot .decls [g.decls], emit = function(n) return { tag = "module", name = n.name, decls = n.decls } end },
    g.head .struct { g.slot .name [g.name], g.slot .fields [g.product], emit = function(n) return { tag = "struct", name = n.name.text, fields = n.fields } end },
    g.head .fn { g.slot .name [g.name], g.slot .params [g.product], g.slot .result [g.type] { optional = true }, g.slot .body [g.body], emit = function(n, lang) return { tag = "fn", name = n.name.text, params = n.params, result = n.result or lang.exports.void, body = n.body } end, lsp = { symbol = function(n) return { name = n.name, kind = "Function", origin = n.origin, node = n } end } },
    g.head .ret { g.slot .value [g.expr] { optional = true }, emit = function(n) return { tag = "ret", value = n.value } end },
  }
end

return llb
