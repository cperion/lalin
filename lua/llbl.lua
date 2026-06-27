--[[
LLBL: Lua Language Builder
Version: 0.5.0 gps-vm atom/protocol model
Target: LuaJIT / Lua 5.1

LLBL is a parserless extensible language workbench:

  Lua syntax -> Lua values -> LLBL captures -> role normalization -> AST/IR

Lua is the meta-language. LLBL is the meaning layer: heads, slots, roles,
[] captures, fragments, source-aware diagnostics, semantic passes, scopes,
typechecking hooks, and LSP-friendly indexes.

Minimal grammar example:

  local llbl = require("llbl")
  local g = llbl.grammar

  local Mini = llbl.dialect "Mini" {
    g.role .decls   { kind = "array" },
    g.role .body    { kind = "array" },
    g.role .product { kind = "product" },

    g.scalar .void,
    g.scalar .i32,
    g.type_ctor .ptr { arity = 1 },

    g.head .unit {
      g.slot .name  [g.string],
      g.slot .decls [g.decls],
      emit = function(n) return { tag = "unit", name = n.name, decls = n.decls } end,
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

  return {
    fn. add { a [i32], b [i32] } [i32] { ret (a + b), },
  }
]]

-- This file is intentionally a single-file workbench. The public model is
-- small:
--
--   Lua values are the syntax tree.
--   Metatables provide the authoring protocol.
--   Roles give raw Lua shapes meaning.
--   The LLBL language makes dialects share one coherent environment.
--
-- The implementation is organized from low-level atoms upward:
--
--   utilities/source/diagnostics
--   gps VM/process event streams
--   symbols/expressions/captures
--   fragments/zones
--   grammar declarations
--   staged head runtime
--   environments/languages
--   analysis/formatting

local llbl = { _VERSION = "llbl-0.6.0-region-gps", VERSION = "llbl-0.6.0-region-gps" }

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
--
-- These helpers deliberately stay boring. LLBL relies on ordinary Lua tables as
-- semantic objects, so predictable shallow copying, array appending, sorting,
-- and small predicates are enough for most of the framework.

local NIL    = { __llbl_tag = "Sentinel", name = "nil" }
local UNIT   = { __llbl_tag = "Sentinel", name = "unit" }
local ABSENT = { __llbl_tag = "Sentinel", name = "absent" }
llbl.NIL, llbl.UNIT, llbl.ABSENT = NIL, UNIT, ABSENT

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
  if type(v) == "table" then return rawget(v, "__llbl_tag") end
  return nil
end

local function is_tag(v, tag)
  return tagof(v) == tag
end

llbl.tagof, llbl.is = tagof, is_tag

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

llbl.repr = repr

local function origin_of(v)
  if type(v) ~= "table" then return nil end
  return rawget(v, "origin") or (rawget(v, "__llbl") and rawget(v, "__llbl").origin) or nil
end

llbl.origin_of = origin_of

local function sorted_keys(t)
  local out = {}
  for k in pairs(t or {}) do out[#out + 1] = k end
  table.sort(out, function(a, b) return tostring(a) < tostring(b) end)
  return out
end

local function table_shape(v)
  local has_array, has_record = false, false
  for k in pairs(v) do
    if type(k) == "number" then has_array = true
    elseif k ~= "__llbl_tag" and k ~= "__llbl" and k ~= "origin" then has_record = true end
  end
  if has_array and has_record then return "mixed_table" end
  if has_array then return "array_table" end
  if has_record then return "record_table" end
  return "array_table"
end

function llbl.shape_of(value)
  if value == nil or value == NIL then return "nil" end
  local tv = type(value)
  if tv == "string" then return "literal:string" end
  if tv == "number" then return "literal:number" end
  if tv == "boolean" then return "literal:boolean" end
  if tv ~= "table" then return "literal:" .. tv end
  local tag = tagof(value)
  if tag == "Name" then return "name" end
  if tag == "Symbol" then return "symbol" end
  if tag == "Capture" then return "capture" end
  if tag == "CaptureInit" then return "capture_init" end
  if tag == "Expr" then return "expr" end
  if tag == "Fragment" then return "fragment" end
  if tag == "Spread" then return "spread" end
  if tag then return "llbl_node" end
  if getmetatable(value) ~= nil then return "foreign_table" end
  return table_shape(value)
end

function llbl.describe_shape(value)
  local d = {
    tag = "Shape",
    name = llbl.shape_of(value),
    lua_type = type(value),
    llbl_tag = tagof(value),
  }
  if type(value) == "table" then
    d.array_count = #value
    d.keys = sorted_keys(value)
  end
  return d
end

function llbl.is_shape(value, shape)
  return llbl.shape_of(value) == shape
end

-- ---------------------------------------------------------------------------
-- Source inspection
-- ---------------------------------------------------------------------------
--
-- LLBL does not parse DSL source, but it still tracks source text for
-- diagnostics. Source registration lets origins render useful excerpts even
-- though construction happened through normal Lua evaluation.

local source = { cache = {}, file_cache = {} }
llbl.source = source

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

-- ---------------------------------------------------------------------------
-- Codegen registry and debug metadata
-- ---------------------------------------------------------------------------
--
-- Generated workbench functions must stay explainable. The registry maps plain
-- Lua functions back to the semantic LLBL object that produced them. Source
-- emitted generators additionally register their generated source text, so
-- debug.getinfo(fn, "Sln") has a stable address that diagnostics can render.

llbl.codegen = {
  registry = {
    by_function = setmetatable({}, { __mode = "k" }),
    by_chunk = {},
    by_id = {},
  },
}

function llbl.codegen.register(fn, meta)
  local tv = type(fn)
  if tv ~= "function" and tv ~= "table" then return fn end
  meta = shallow_copy(meta or {})
  meta.fn = fn
  if meta.source_name and meta.source_text then source.register(meta.source_name, meta.source_text) end
  llbl.codegen.registry.by_function[fn] = meta
  if meta.source_name then llbl.codegen.registry.by_chunk[meta.source_name] = meta end
  if meta.id then llbl.codegen.registry.by_id[meta.id] = meta end
  return fn
end

function llbl.codegen.metadata(fn)
  local tv = type(fn)
  if tv == "function" or tv == "table" then
    local meta = llbl.codegen.registry.by_function[fn]
    if meta then return meta end
    if tv == "function" and debug and debug.getinfo then
      local info = debug.getinfo(fn, "S")
      if info and info.source then return llbl.codegen.registry.by_chunk[info.source] or llbl.codegen.registry.by_chunk[source.clean(info.source)] end
    end
  end
  return nil
end

function llbl.codegen.source(fn)
  local meta = llbl.codegen.metadata(fn)
  return meta and meta.source_text or nil, meta and meta.source_name or nil
end

function llbl.codegen.describe(fn)
  local meta = llbl.codegen.metadata(fn)
  if not meta then return nil end
  return {
    tag = "CodegenFunction",
    id = meta.id,
    kind = meta.kind,
    dialect = meta.dialect,
    language = meta.language,
    role = meta.role,
    head = meta.head,
    slot = meta.slot,
    process = meta.process,
    mode = meta.mode,
    source_name = meta.source_name,
    origin = meta.origin,
    generated = meta.generated and true or false,
    reflective = type(meta.reflective) == "function",
  }
end

function llbl.codegen.explain_stack(level)
  level = (level or 1) + 1
  if not (debug and debug.getinfo) then return nil end
  local info = debug.getinfo(level, "nSlu")
  if not info then return nil end
  local meta = nil
  if info.func then meta = llbl.codegen.metadata(info.func) end
  if not meta and info.source then meta = llbl.codegen.registry.by_chunk[info.source] or llbl.codegen.registry.by_chunk[source.clean(info.source)] end
  local line_meta = meta and meta.line_map and info.currentline and meta.line_map[info.currentline] or nil
  return {
    tag = "CodegenStackFrame",
    name = info.name or info.namewhat,
    source = info.source,
    currentline = info.currentline,
    linedefined = info.linedefined,
    what = info.what,
    metadata = meta,
    line = line_meta,
  }
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

local function trim_doc_line(s)
  s = tostring(s or "")
  s = s:gsub("^%s+", ""):gsub("%s+$", "")
  return s
end

local function line_comment_text(line)
  local text = line and line:match("^%s*%-%-%-?%s?(.*)$")
  if text == nil then return nil end
  if text:match("^%[=*%[") then return nil end
  return text:gsub("%s+$", "")
end

local function long_comment_close(line)
  return line and line:match("%](=*)%]%s*$")
end

local function long_comment_open(line)
  return line and line:match("^%s*%-%-%[(=*)%[")
end

local function strip_long_comment(lines, first, last, eqs)
  local out = {}
  for i = first, last do out[#out + 1] = lines[i] or "" end
  if #out == 0 then return nil end
  out[1] = out[1]:gsub("^%s*%-%-%[" .. eqs .. "%[", "", 1)
  out[#out] = out[#out]:gsub("%]" .. eqs .. "%]%s*$", "", 1)
  while #out > 0 and trim_doc_line(out[1]) == "" do table.remove(out, 1) end
  while #out > 0 and trim_doc_line(out[#out]) == "" do table.remove(out, #out) end
  if #out == 0 then return nil end
  return table.concat(out, "\n")
end

function source.leading_comment(origin)
  if not origin or not origin.line or origin.line <= 1 then return nil end
  local lines = source.lines(origin.source) or source.lines(origin.file)
  if not lines then return nil end

  local i = origin.line - 1
  local collected = {}
  while i >= 1 do
    local text = line_comment_text(lines[i])
    if text == nil then break end
    collected[#collected + 1] = text
    i = i - 1
  end
  if #collected > 0 then
    local out = {}
    for j = #collected, 1, -1 do out[#out + 1] = collected[j] end
    while #out > 0 and trim_doc_line(out[1]) == "" do table.remove(out, 1) end
    while #out > 0 and trim_doc_line(out[#out]) == "" do table.remove(out, #out) end
    if #out > 0 then return table.concat(out, "\n") end
  end

  local close_eqs = long_comment_close(lines[origin.line - 1])
  if not close_eqs then return nil end
  for first = origin.line - 1, 1, -1 do
    local open_eqs = long_comment_open(lines[first])
    if open_eqs and open_eqs == close_eqs then
      return strip_long_comment(lines, first, origin.line - 1, open_eqs)
    end
  end
  return nil
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
    return { __llbl_tag = "Origin", kind = kind or "unknown", source = "<unknown>", file = "<unknown>", line = -1 }
  end
  local o = {
    __llbl_tag = "Origin",
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
  o.leading_comment = source.leading_comment(o)
  return o
end

llbl.origin = source.capture

function llbl.here(kind, opts)
  opts = opts or {}
  opts.skip = (opts.skip or 0) + 1
  return source.capture(kind or "factory-call", opts)
end

function llbl.with_origin(origin, fn, ...)
  if type(fn) ~= "function" then llbl.fail("with_origin expects a function", { primary = origin }) end
  return fn(..., origin)
end

local function origin_label(origin)
  if not origin then return "<unknown>" end
  return tostring(origin.file or origin.short_src or origin.source or "<unknown>") .. ":" .. tostring(origin.line or -1)
end

llbl.origin_label = origin_label

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

function llbl.render_origin(origin)
  if not origin then return "<unknown>" end
  local kind = origin.kind and (" [" .. tostring(origin.kind) .. "]") or ""
  return origin_label(origin) .. kind
end

local function child_origin(parent, spec)
  spec = spec or {}
  local o = {}
  if parent then for k, v in pairs(parent) do o[k] = v end end
  o.__llbl_tag = "Origin"
  o.kind = spec.kind or o.kind or "derived"
  o.parent = parent
  for k, v in pairs(spec) do o[k] = v end
  return o
end

llbl.child_origin = child_origin

local function provenance_from_origin(origin, out, seen)
  if not origin or seen[origin] then return end
  seen[origin] = true
  out[#out + 1] = origin
  if origin.generated_by and origin.generated_by.origin then provenance_from_origin(origin.generated_by.origin, out, seen) end
  if origin.parent then provenance_from_origin(origin.parent, out, seen) end
end

function llbl.provenance(value)
  local origin = is_tag(value, "Origin") and value or origin_of(value)
  local out = {}
  provenance_from_origin(origin, out, {})
  return out
end

function llbl.render_provenance(value)
  local p = llbl.provenance(value)
  if #p == 0 then return "<no provenance>" end
  local out = {}
  for i = 1, #p do
    local o = p[i]
    local line = llbl.render_origin(o)
    if o.consumed_by then
      local c = o.consumed_by
      line = line .. " consumed by " .. tostring(c.head or "?") .. "." .. tostring(c.slot or "?") .. " [" .. tostring(c.role or "?") .. "] via " .. tostring(c.channel or "?")
    end
    if o.generated_by then
      local g = o.generated_by
      line = line .. " generated by " .. tostring(g.name or "?")
    end
    out[#out + 1] = line
  end
  return table.concat(out, "\n")
end

local function origin_comment_stack(origin)
  local provenance = llbl.provenance(origin)
  local out, seen = {}, {}
  for i = #provenance, 1, -1 do
    local comment = provenance[i] and provenance[i].leading_comment
    if comment and comment ~= "" and not seen[comment] then
      seen[comment] = true
      out[#out + 1] = comment
    end
  end
  if #out == 0 and origin and origin.leading_comment and origin.leading_comment ~= "" then
    out[#out + 1] = origin.leading_comment
  end
  return out
end

local function render_comment_stack(comments)
  if #(comments or {}) == 0 then return nil end
  if #comments == 1 then return "context: " .. tostring(comments[1]):gsub("\n", "\n         ") end
  local out = { "context:" }
  for i = 1, #comments do
    out[#out + 1] = "  - " .. tostring(comments[i]):gsub("\n", "\n    ")
  end
  return table.concat(out, "\n")
end

llbl.channel = {
  index_name = "index:name",
  index_type = "index:type",
  index_value = "index:value",
  call_none = "call:none",
  call_value = "call:value",
  call_table = "call:table",
  call_many = "call:many",
  operator_concat = "operator:concat",
  operator_choice = "operator:choice",
  operator_decorate = "operator:decorate",
  env_lookup = "env:lookup",
  env_write = "env:write",
}

llbl.modes = {
  fast = { provenance = "minimal", trace = false },
  debug = { provenance = "full", trace = false },
  lsp = { provenance = "full", index = true, keep_incomplete_stages = true },
  format = { provenance = "full", format = true },
  trace = { provenance = "full", trace = true },
}

local Event = {}
Event.__index = Event

function llbl.event(channel, value, opts)
  opts = opts or {}
  return setmetatable({
    __llbl_tag = "Event",
    channel = channel,
    value = value,
    argc = opts.argc,
    action = opts.action,
    origin = opts.origin or source.capture("event"),
    shape = opts.shape or llbl.shape_of(value),
  }, Event)
end

function llbl.describe_event(event)
  if not is_tag(event, "Event") then
    event = llbl.event("value", event, { origin = origin_of(event) })
  end
  return {
    tag = "Event",
    channel = event.channel,
    shape = event.shape or llbl.shape_of(event.value),
    argc = event.argc,
    action = event.action,
    origin = event.origin,
    value = event.value,
  }
end

local function event_label(event)
  if not event then return "<no event>" end
  return tostring(event.channel or "?") .. " with " .. tostring(event.shape or llbl.shape_of(event.value))
end

llbl.Event = Event

-- ---------------------------------------------------------------------------
-- Diagnostics
-- ---------------------------------------------------------------------------
--
-- Diagnostics are structured values, not strings. A diagnostic can carry an
-- origin, labels, notes, and event/head/slot/role context. That is what lets
-- errors keep useful blame even when values were created through Lua helpers.

local Diagnostic = {}
Diagnostic.__index = Diagnostic

function llbl.diagnostic(spec)
  spec = spec or {}
  return setmetatable({
    __llbl_tag = "Diagnostic",
    severity = spec.severity or "error",
    code = spec.code,
    message = spec.message or spec[1] or "diagnostic",
    primary = spec.primary or spec.origin or origin_of(spec.event),
    labels = spec.labels or {},
    related = spec.related or {},
    notes = spec.notes or {},
    event = spec.event,
    slot = spec.slot,
    role = spec.role,
    head = spec.head,
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
  if self.primary then
    local context = render_comment_stack(origin_comment_stack(self.primary))
    if context then out[#out + 1] = context end
  end
  for i = 1, #self.labels do
    local l = self.labels[i]
    out[#out + 1] = source.render_excerpt(l.origin or l.primary, opts.radius or 1, l.message)
  end
  for i = 1, #self.related do
    local r = self.related[i]
    out[#out + 1] = source.render_excerpt(r.origin or r.primary, opts.radius or 1, r.message)
  end
  if self.event then out[#out + 1] = "event: " .. event_label(self.event) end
  for i = 1, #self.notes do out[#out + 1] = "note: " .. tostring(self.notes[i]) end
  return table.concat(out, "\n")
end

Diagnostic.__tostring = Diagnostic.render
llbl.Diagnostic = Diagnostic

local DiagnosticBag = {}
DiagnosticBag.__index = DiagnosticBag

function llbl.diagnostics()
  return setmetatable({ __llbl_tag = "DiagnosticBag", items = {} }, DiagnosticBag)
end

function DiagnosticBag:add(d)
  if type(d) == "string" then d = llbl.diagnostic { message = d } end
  self.items[#self.items + 1] = d
  return d
end

function DiagnosticBag:error(spec)
  spec = spec or {}; spec.severity = "error"; return self:add(llbl.diagnostic(spec))
end

function DiagnosticBag:warning(spec)
  spec = spec or {}; spec.severity = "warning"; return self:add(llbl.diagnostic(spec))
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

llbl.DiagnosticBag = DiagnosticBag

function llbl.fail(message, spec, level)
  spec = spec or {}; spec.message = message
  error(llbl.diagnostic(spec), level or 0)
end

do
-- ---------------------------------------------------------------------------
-- Generic region algebra
-- ---------------------------------------------------------------------------
--
-- Region is the LLBL-owned control abstraction:
--
--   input product + state product + named exit protocol + transition body
--
-- Lalin native regions, LLPVM phases, process machines, parsers, and GPS
-- streams are lowerings/projections of this shared shape. LLBL owns the
-- semantics and the bare `region.` head; member dialects consume or lower
-- region descriptors through their own typed backends.

local Exit, Protocol, Region, RegionLowering, RegionMaterializer = {}, {}, {}, {}, {}
Exit.__index = Exit
Protocol.__index = Protocol
Region.__index = Region
RegionLowering.__index = RegionLowering
RegionMaterializer.__index = RegionMaterializer

llbl.exits = {}
llbl.protocols = {}
llbl.regions = {}
llbl.region_lowerings = {}
llbl.region_materializers = {}

local exit_classes = {
  resumable = true,
  terminal = true,
  failure = true,
  blocking = true,
  effect = true,
}

local function protocol_name(protocol)
  if protocol == nil then return nil end
  if is_tag(protocol, "Protocol") then return protocol.name end
  return tostring(protocol)
end
llbl.protocol_name = protocol_name

local function resolve_protocol(protocol)
  if protocol == nil then return nil end
  if is_tag(protocol, "Protocol") then return protocol end
  return llbl.protocols[tostring(protocol)]
end

local function normalize_exit_class(cls)
  cls = cls or "resumable"
  if cls == "done" or cls == "return" then cls = "terminal" end
  if cls == "error" or cls == "failed" then cls = "failure" end
  if not exit_classes[cls] then
    llbl.fail("unknown LLBL region exit class " .. tostring(cls), {
      code = "E_BAD_REGION_EXIT_CLASS",
    }, 2)
  end
  return cls
end

local function normalize_product_spec(v)
  if v == nil then return {} end
  if type(v) ~= "table" then return { v } end
  return shallow_copy(v)
end

local function normalize_exit(name, spec)
  if is_tag(spec, "Exit") then return spec end
  if type(spec) == "string" then spec = { class = spec } end
  spec = shallow_copy(spec or {})
  local cls = normalize_exit_class(spec.class or spec.kind)
  local e = setmetatable({
    __llbl_tag = "Exit",
    name = tostring(spec.name or name),
    class = cls,
    payload = normalize_product_spec(spec.payload or spec.product or spec.fields),
    next = normalize_product_spec(spec.next or spec.state),
    terminal = spec.terminal ~= nil and spec.terminal or cls == "terminal" or cls == "failure",
    resumable = spec.resumable ~= nil and spec.resumable or cls == "resumable" or cls == "blocking",
    effect = spec.effect ~= nil and spec.effect or cls == "effect",
    origin = spec.origin or source.capture("region-exit", { hint = name }),
    spec = spec,
  }, Exit)
  llbl.exits[e.name] = e
  return e
end

local function normalize_exits(spec)
  local exits = spec and spec.exits or nil
  local by_name, list = {}, {}
  if exits == nil then return by_name, list end
  if type(exits) ~= "table" then
    llbl.fail("protocol exits must be a table", { code = "E_BAD_PROTOCOL_EXITS", primary = origin_of(exits) }, 2)
  end
  if #exits > 0 then
    for i = 1, #exits do
      local raw = exits[i]
      local name = type(raw) == "table" and (raw.name or raw[1]) or raw
      local e = normalize_exit(name, raw)
      by_name[e.name] = e
      list[#list + 1] = e
    end
  else
    for name, raw in pairs(exits) do
      local e = normalize_exit(name, raw)
      by_name[e.name] = e
      list[#list + 1] = e
    end
  end
  table.sort(list, function(a, b) return a.name < b.name end)
  return by_name, list
end

function llbl.exit(name, spec)
  return normalize_exit(name, spec)
end

-- Protocols are public metadata for behavior/control languages. They still
-- manufacture Lua metatables for existing fragment/operator protocols, but
-- now also carry typed region exits.
local operator_metamethod = {
  concat = "__concat",
  choice = "__add",
  decorate = "__mul",
  len = "__len",
  tostring = "__tostring",
  call = "__call",
  index = "__index",
  newindex = "__newindex",
}

function llbl.protocol(name, spec)
  spec = shallow_copy(spec or {})
  local exits, exit_list = normalize_exits(spec)
  local p = setmetatable({
    __llbl_tag = "Protocol",
    name = tostring(name),
    exits = exits,
    exit_list = exit_list,
    spec = spec,
    origin = spec.origin or source.capture("protocol", { hint = name }),
  }, Protocol)
  llbl.protocols[p.name] = p
  return p
end

function Protocol:metatable(fields)
  fields = fields or {}
  local mt = {}
  for k, v in pairs(self.spec.metatable or {}) do mt[k] = v end
  for k, v in pairs(self.spec.metamethods or {}) do mt[k] = v end
  for op, fn in pairs(self.spec.operators or {}) do
    local mm = operator_metamethod[op] or op
    if type(mm) == "string" and mm:sub(1, 2) ~= "__" then mm = "__" .. mm end
    mt[mm] = fn
  end
  for k, v in pairs(fields) do mt[k] = v end
  mt.__llbl_protocol = self
  return mt
end

function llbl.validate_protocol(protocol)
  if type(protocol) == "string" then protocol = llbl.protocols[protocol] end
  if not is_tag(protocol, "Protocol") then
    llbl.fail("expected LLBL protocol", { code = "E_EXPECTED_PROTOCOL", primary = origin_of(protocol) })
  end
  local mt = protocol:metatable()
  for k, v in pairs(mt) do
    if type(k) == "string" and k:sub(1, 2) == "__" and k ~= "__llbl_protocol" and type(v) ~= "function" and k ~= "__index" then
      llbl.fail("protocol " .. tostring(protocol.name) .. " installs non-function metamethod " .. tostring(k), {
        code = "E_BAD_PROTOCOL_METAMETHOD",
        primary = protocol.origin,
      })
    end
  end
  return true
end

function llbl.describe_exit(exit)
  if not is_tag(exit, "Exit") then return nil end
  return {
    tag = "Exit",
    name = exit.name,
    class = exit.class,
    payload = shallow_copy(exit.payload or {}),
    next = shallow_copy(exit.next or {}),
    terminal = exit.terminal,
    resumable = exit.resumable,
    effect = exit.effect,
    origin = exit.origin,
  }
end

function llbl.describe_metatable(mt)
  local out = { tag = "Metatable", metamethods = {}, keys = {} }
  if type(mt) ~= "table" then out.kind = type(mt); return out end
  local p = rawget(mt, "__llbl_protocol")
  out.protocol = p and p.name or nil
  for _, k in ipairs(sorted_keys(mt)) do
    if type(k) == "string" and k:sub(1, 2) == "__" then out.metamethods[#out.metamethods + 1] = k
    else out.keys[#out.keys + 1] = k end
  end
  return out
end

function llbl.describe_protocol(protocol)
  if type(protocol) == "string" then protocol = llbl.protocols[protocol] end
  if not is_tag(protocol, "Protocol") then return nil end
  local spec = protocol.spec or {}
  local exits = {}
  for i = 1, #(protocol.exit_list or {}) do exits[i] = llbl.describe_exit(protocol.exit_list[i]) end
  return {
    tag = "Protocol",
    name = protocol.name,
    exits = exits,
    operators = sorted_keys(spec.operators or {}),
    metamethods = sorted_keys(spec.metamethods or spec.metatable or {}),
    origin = protocol.origin,
  }
end

local function normalize_region_lowering(region, target, spec)
  if is_tag(spec, "RegionLowering") then return spec end
  spec = shallow_copy(spec or {})
  local target_name = tostring(target or spec.target or spec.backend or "gps")
  return setmetatable({
    __llbl_tag = "RegionLowering",
    region = region,
    target = target_name,
    kind = spec.kind or spec.body_kind or target_name,
    body = spec.body or spec.fn or spec.gen or spec.plan,
    metadata = spec.metadata,
    origin = spec.origin or (region and region.origin) or source.capture("region-lowering", { hint = target_name }),
    spec = spec,
  }, RegionLowering)
end

local function normalize_region_materializer(region, name, spec)
  if is_tag(spec, "RegionMaterializer") then return spec end
  spec = shallow_copy(spec or {})
  local mat_name = tostring(name or spec.name or spec.kind or "collect")
  return setmetatable({
    __llbl_tag = "RegionMaterializer",
    region = region,
    name = mat_name,
    kind = spec.kind or mat_name,
    body = spec.body or spec.fn,
    metadata = spec.metadata,
    origin = spec.origin or (region and region.origin) or source.capture("region-materializer", { hint = mat_name }),
    spec = spec,
  }, RegionMaterializer)
end

local function region_construct(name, spec)
  spec = shallow_copy(spec or {})
  local protocol = resolve_protocol(spec.protocol or spec.protocol_name)
  local protocol_label = protocol and protocol.name or protocol_name(spec.protocol or spec.protocol_name)
  local owner = spec.owner or tostring(name):match("^([^%.]+)%.") or "llbl"
  local id = tostring(spec.id or ((spec.owner and (tostring(spec.owner) .. ".")) or "") .. tostring(name))
  local r = setmetatable({
    __llbl_tag = "Region",
    id = id,
    name = tostring(name),
    owner = owner,
    input = normalize_product_spec(spec.input or spec.params),
    state = normalize_product_spec(spec.state),
    protocol = protocol,
    protocol_name = protocol_label,
    body_kind = spec.body_kind or spec.kind or "descriptor",
    body = spec.body or spec.region or spec.fn,
    lowerings = {},
    materializers = {},
    metadata = spec.metadata,
    origin = spec.origin or source.capture("region", { hint = name }),
    spec = spec,
  }, Region)
  for target, lowering in pairs(spec.lowerings or {}) do
    r.lowerings[target] = normalize_region_lowering(r, target, lowering)
  end
  for mat_name, mat in pairs(spec.materializers or {}) do
    r.materializers[mat_name] = normalize_region_materializer(r, mat_name, mat)
  end
  llbl.regions[r.id] = r
  llbl.regions[r.name] = r
  return r
end

function Region:lowering(target, spec)
  local l = normalize_region_lowering(self, target, spec)
  self.lowerings[l.target] = l
  llbl.region_lowerings[self.id .. "." .. l.target] = l
  return l
end

function Region:materializer(name, spec)
  local m = normalize_region_materializer(self, name, spec)
  self.materializers[m.name] = m
  llbl.region_materializers[self.id .. "." .. m.name] = m
  return m
end

function Region:describe()
  return llbl.describe_region(self)
end

local function region_gps_body(region, target)
  local lowering = region.lowerings and region.lowerings[target or "gps"]
  return (lowering and lowering.body) or region.body
end

function Region:gps(...)
  if not llbl.gps then
    llbl.fail("GPS lowering requested before llbl.gps is initialized", {
      code = "E_REGION_GPS_UNAVAILABLE",
      primary = self.origin,
    }, 2)
  end
  local body = region_gps_body(self, "gps")
  if body == nil then
    llbl.fail("region " .. tostring(self.id or self.name) .. " has no GPS lowering", {
      code = "E_REGION_NO_GPS_LOWERING",
      primary = self.origin,
    }, 2)
  end
  if is_tag(body, "GpsPlan") then
    return llbl.gps.raw(body)
  end
  if is_tag(body, "Gps") or is_tag(body, "GpsSource") then
    return llbl.gps.raw(body)
  end
  if type(body) == "function" then
    local r = pack(body(...))
    if is_tag(r[1], "GpsPlan") then return llbl.gps.raw(r[1]) end
    return llbl.gps.raw(unpack(r, 1, r.n))
  end
  return llbl.gps.raw(body)
end

function Region:materialize(name, ...)
  name = name or "collect"
  local materializer = self.materializers and self.materializers[name]
  if not materializer then
    llbl.fail("region " .. tostring(self.id or self.name) .. " has no materializer " .. tostring(name), {
      code = "E_REGION_NO_MATERIALIZER",
      primary = self.origin,
    }, 2)
  end
  if type(materializer.body) == "function" then return materializer.body(...) end
  return materializer.body
end

function llbl.region_gps(region, ...)
  if type(region) == "string" then region = llbl.regions[region] end
  if not is_tag(region, "Region") then
    llbl.fail("llbl.region_gps expects a Region", { code = "E_EXPECTED_REGION", primary = origin_of(region) }, 2)
  end
  return region:gps(...)
end

function llbl.region_materialize(region, name, ...)
  if type(region) == "string" then region = llbl.regions[region] end
  if not is_tag(region, "Region") then
    llbl.fail("llbl.region_materialize expects a Region", { code = "E_EXPECTED_REGION", primary = origin_of(region) }, 2)
  end
  return region:materialize(name, ...)
end

function llbl.lowering(region, target, spec)
  if type(region) == "string" then region = llbl.regions[region] end
  if not is_tag(region, "Region") then
    llbl.fail("llbl.lowering expects a Region", { code = "E_EXPECTED_REGION", primary = origin_of(region) }, 2)
  end
  return region:lowering(target, spec)
end

function llbl.materializer(region, name, spec)
  if type(region) == "string" then region = llbl.regions[region] end
  if not is_tag(region, "Region") then
    llbl.fail("llbl.materializer expects a Region", { code = "E_EXPECTED_REGION", primary = origin_of(region) }, 2)
  end
  return region:materializer(name, spec)
end

function llbl.describe_region(region)
  if type(region) == "string" then region = llbl.regions[region] end
  if not is_tag(region, "Region") then return nil end
  local lowerings, materializers = {}, {}
  for _, name in ipairs(sorted_keys(region.lowerings or {})) do
    local l = region.lowerings[name]
    lowerings[#lowerings + 1] = { target = l.target, kind = l.kind, origin = l.origin }
  end
  for _, name in ipairs(sorted_keys(region.materializers or {})) do
    local m = region.materializers[name]
    materializers[#materializers + 1] = { name = m.name, kind = m.kind, origin = m.origin }
  end
  return {
    tag = "Region",
    id = region.id,
    name = region.name,
    owner = region.owner,
    input = shallow_copy(region.input or {}),
    state = shallow_copy(region.state or {}),
    protocol = region.protocol_name,
    body_kind = region.body_kind,
    lowerings = lowerings,
    materializers = materializers,
    origin = region.origin,
  }
end

local RegionFactory, RegionStage = {}, {}
local function looks_like_region_descriptor(spec)
  if type(spec) ~= "table" then return false end
  return rawget(spec, "input") ~= nil
    or rawget(spec, "params") ~= nil
    or rawget(spec, "state") ~= nil
    or rawget(spec, "protocol") ~= nil
    or rawget(spec, "protocol_name") ~= nil
    or rawget(spec, "exits") ~= nil
    or rawget(spec, "body") ~= nil
    or rawget(spec, "region") ~= nil
    or rawget(spec, "lowerings") ~= nil
    or rawget(spec, "materializers") ~= nil
    or rawget(spec, "owner") ~= nil
    or rawget(spec, "kind") ~= nil
    or rawget(spec, "body_kind") ~= nil
end

local function region_exit_name(raw, index)
  if is_tag(raw, "Symbol") or is_tag(raw, "Name") then return raw.text end
  if type(raw) == "table" then
    if raw.name ~= nil then
      if is_tag(raw.name, "Symbol") or is_tag(raw.name, "Name") then return raw.name.text end
      return tostring(raw.name)
    end
    local subject = raw.subject or raw[1]
    if is_tag(subject, "Symbol") or is_tag(subject, "Name") then return subject.text end
    if type(subject) == "string" then return subject end
  end
  if type(raw) == "string" then return raw end
  return "exit" .. tostring(index)
end

local function region_protocol_from_exits(region_name, exits, origin)
  if is_tag(exits, "Protocol") then return exits end
  if type(exits) == "string" then return exits end
  if type(exits) ~= "table" then return nil end
  local ps = {}
  if #exits > 0 then
    for i = 1, #exits do
      local raw = exits[i]
      ps[region_exit_name(raw, i)] = { class = "terminal", payload = raw, origin = origin_of(raw) }
    end
  else
    for name, raw in pairs(exits) do
      ps[tostring(name)] = { class = "terminal", payload = raw, origin = origin_of(raw) }
    end
  end
  return llbl.protocol(tostring(region_name) .. ".protocol", {
    exits = ps,
    origin = origin,
  })
end

RegionFactory.__index = function(_, key)
  if type(key) ~= "string" and llbl.symbol then
    return llbl.symbol("region")[key]
  end
  local name = tostring(key)
  return setmetatable({
    __llbl_tag = "RegionStage",
    name = name,
    stage = 0,
    origin = source.capture("region-head", { hint = name }),
  }, RegionStage)
end
RegionFactory.__call = function(_, name, spec)
  if spec == nil then
    return setmetatable({
      __llbl_tag = "RegionStage",
      name = tostring(name),
      stage = 0,
      origin = source.capture("region-head", { hint = name }),
    }, RegionStage)
  end
  return region_construct(name, spec)
end
RegionStage.__index = function(self, key)
  local method = rawget(RegionStage, key)
  if method then return method end
  local patch = shallow_copy(rawget(self, "spec") or {})
  patch.protocol = patch.protocol or key
  return setmetatable({
    __llbl_tag = "RegionStage",
    name = rawget(self, "name"),
    spec = patch,
    input = rawget(self, "input"),
    exits = rawget(self, "exits"),
    stage = rawget(self, "stage") or 0,
    origin = rawget(self, "origin"),
  }, RegionStage)
end
RegionStage.__call = function(self, spec)
  local stage = rawget(self, "stage") or 0
  if stage == 0 and looks_like_region_descriptor(spec) then
    spec = shallow_copy(spec or {})
    for k, v in pairs(rawget(self, "spec") or {}) do if spec[k] == nil then spec[k] = v end end
    spec.origin = spec.origin or rawget(self, "origin")
    return region_construct(rawget(self, "name"), spec)
  end
  if stage == 0 then
    return setmetatable({
      __llbl_tag = "RegionStage",
      name = rawget(self, "name"),
      spec = shallow_copy(rawget(self, "spec") or {}),
      input = spec,
      stage = 1,
      origin = rawget(self, "origin"),
    }, RegionStage)
  end
  if stage == 1 then
    if type(spec) == "function" or is_tag(spec, "GpsPlan") or is_tag(spec, "Gps") or is_tag(spec, "GpsSource") then
      local out = shallow_copy(rawget(self, "spec") or {})
      out.input = out.input or rawget(self, "input")
      out.body = out.body or spec
      out.body_kind = out.body_kind or "region-head"
      if type(spec) == "function" or is_tag(spec, "GpsPlan") or is_tag(spec, "Gps") or is_tag(spec, "GpsSource") then
        out.lowerings = out.lowerings or { gps = { kind = "gps", body = spec } }
      end
      out.origin = out.origin or rawget(self, "origin")
      return region_construct(rawget(self, "name"), out)
    end
    return setmetatable({
      __llbl_tag = "RegionStage",
      name = rawget(self, "name"),
      spec = shallow_copy(rawget(self, "spec") or {}),
      input = rawget(self, "input"),
      exits = spec,
      stage = 2,
      origin = rawget(self, "origin"),
    }, RegionStage)
  end
  local out = shallow_copy(rawget(self, "spec") or {})
  out.input = out.input or rawget(self, "input")
  out.exits = out.exits or rawget(self, "exits")
  out.protocol = out.protocol or region_protocol_from_exits(rawget(self, "name"), rawget(self, "exits"), rawget(self, "origin"))
  out.body = out.body or spec
  out.body_kind = out.body_kind or "region-head"
  if (type(spec) == "function" or is_tag(spec, "GpsPlan") or is_tag(spec, "Gps") or is_tag(spec, "GpsSource")) and out.lowerings == nil then
    out.lowerings = { gps = { kind = "gps", body = spec } }
  end
  out.origin = out.origin or rawget(self, "origin")
  return region_construct(rawget(self, "name"), out)
end

llbl.Region = Region
llbl.Exit = Exit
llbl.Protocol = Protocol
llbl.RegionLowering = RegionLowering
llbl.RegionMaterializer = RegionMaterializer
llbl.region = setmetatable({ __llbl_tag = "RegionFactory" }, RegionFactory)

local RoleRegionFactory, RoleRegionStage = {}, {}
local function role_region_construct(name, protocol, body)
  return llbl.region(tostring(name))[protocol or "role_value"] { "lang", "ctx", "value" } (body)
end
RoleRegionFactory.__index = function(_, key)
  return setmetatable({
    __llbl_tag = "RoleRegionStage",
    name = tostring(key),
    protocol = "role_value",
    origin = source.capture("role-region", { hint = key }),
  }, RoleRegionStage)
end
RoleRegionFactory.__call = function(_, name, body)
  if body ~= nil then return role_region_construct(name, "role_value", body) end
  return setmetatable({
    __llbl_tag = "RoleRegionStage",
    name = tostring(name),
    protocol = "role_value",
    origin = source.capture("role-region", { hint = name }),
  }, RoleRegionStage)
end
RoleRegionStage.__index = function(self, key)
  local method = rawget(RoleRegionStage, key)
  if method then return method end
  return setmetatable({
    __llbl_tag = "RoleRegionStage",
    name = rawget(self, "name"),
    protocol = tostring(key),
    origin = rawget(self, "origin"),
  }, RoleRegionStage)
end
RoleRegionStage.__call = function(self, body)
  return role_region_construct(rawget(self, "name"), rawget(self, "protocol") or "role_value", body)
end
llbl.role_region = setmetatable({ __llbl_tag = "RoleRegionFactory" }, RoleRegionFactory)

llbl.protocol("pull", {
  exits = {
    item = { class = "resumable", payload = { "value" }, next = { "state" } },
    done = { class = "terminal" },
  },
})
llbl.protocol("process", {
  exits = {
    event = { class = "resumable", payload = { "event" }, next = { "state" } },
    diagnostic = { class = "effect", resumable = true, payload = { "diagnostic" }, next = { "state" } },
    result = { class = "terminal", payload = { "result" } },
    failed = { class = "failure", payload = { "diagnostic" } },
    done = { class = "terminal" },
  },
})
llbl.protocol("role_value", {
  exits = {
    value = { class = "terminal", payload = { "value" } },
    failed = { class = "failure", payload = { "diagnostic" } },
  },
})
llbl.protocol("role_items", {
  exits = {
    item = { class = "resumable", payload = { "value" }, next = { "state" } },
    failed = { class = "failure", payload = { "diagnostic" } },
    done = { class = "terminal" },
  },
})
llbl.protocol("tool_events", {
  exits = {
    event = { class = "resumable", payload = { "event" }, next = { "state" } },
    diagnostic = { class = "effect", resumable = true, payload = { "diagnostic" }, next = { "state" } },
    done = { class = "terminal" },
  },
})

end

do
-- ---------------------------------------------------------------------------
-- Gps VM: LuaJIT gen,param,state substrate
-- ---------------------------------------------------------------------------
--
-- This is the low-level LLBL runtime shape extracted from Lua's generic-for
-- protocol and from the design lessons of fun.lua. It is not a functional
-- programming API. It is a tiny gps VM ABI:
--
--   gen(param, state) -> nil
--   gen(param, state) -> next_state, payload...
--
-- param is the machine closure: grammar constants, source generators,
-- functions, immutable source references. state is the explicit continuation:
-- cursor, counters, buffers, child states. payload is semantic data: events,
-- diagnostics, nodes, tokens, index records, etc.
--
-- The public LLBL process API is GPS-based: every process and compiled tooling
-- pass runs as gen,param,state.

local Gps, GpsPlan = {}, {}
Gps.__index = Gps
GpsPlan.__index = GpsPlan

local gps = { __llbl_tag = "GpsModule", VERSION = "llbl-gps-0.5.0" }
llbl.gps = gps

local function gps_is(v) return is_tag(v, "Gps") end
local function gps_source_is(v) return is_tag(v, "GpsSource") end
local function gps_op_is(v) return is_tag(v, "GpsOp") end
local function gps_plan_is(v) return is_tag(v, "GpsPlan") end

local function gps_unpack_payload(r, first)
  return unpack(r, first or 2, r.n)
end

local function gps_repack_return(r)
  return unpack(r, 1, r.n)
end

local function gps_as_state_table(state)
  if type(state) == "table" then return state end
  return { state }
end

local function gps_meta(meta)
  meta = meta or {}
  meta.origin = meta.origin or source.capture("gps")
  return meta
end

function gps.wrap(gen, param, state, meta)
  if type(gen) ~= "function" and not (type(gen) == "table" and getmetatable(gen) and getmetatable(gen).__call) then
    llbl.fail("gps.wrap expects a generator function/callable", {
      code = "E_GPS_GENERATOR",
      primary = meta and meta.origin,
      notes = { "A gps generator must implement gen(param, state) -> nil | next_state, payload..." },
    }, 2)
  end
  local s0 = setmetatable({
    __llbl_tag = "Gps",
    gen = gen,
    param = param,
    state = state,
    meta = gps_meta(meta),
  }, Gps)
  return s0, param, state
end

function gps.unwrap(s0)
  if gps_is(s0) then return s0.gen, s0.param, s0.state end
  return gps.raw(s0)
end

local function gps_empty_gen(_param, _state)
  return nil
end

local function gps_string_gen(param, state)
  state = (state or 0) + 1
  if state > #param then return nil end
  return state, string.sub(param, state, state)
end

local function gps_array_gen(param, state)
  state = (state or 0) + 1
  if state > #param then return nil end
  return state, param[state]
end

local function gps_record_gen(param, state)
  local k, v = next(param, state)
  if k == nil then return nil end
  return k, k, v
end

local function gps_once_gen(param, state)
  if state ~= nil then return nil end
  return true, unpack(param, 1, param.n)
end

local function gps_range_gen(param, state)
  local stop, step = param[2], param[3]
  local next_state = state + step
  if step > 0 then
    if next_state > stop then return nil end
  else
    if next_state < stop then return nil end
  end
  return next_state, next_state
end

local function gps_source_to_raw(src)
  if gps_source_is(src) then
    local kind = src.kind
    if kind == "empty" then return gps_empty_gen, nil, nil end
    if kind == "array" then return gps_array_gen, src.value or {}, 0 end
    if kind == "record" then return gps_record_gen, src.value or {}, nil end
    if kind == "string" then
      if src.value == nil or src.value == "" then return gps_empty_gen, nil, nil end
      return gps_string_gen, src.value, 0
    end
    if kind == "once" then return gps_once_gen, src.values or pack(), nil end
    if kind == "range" then
      local start = src.start or 1
      local stop = src.stop or 0
      local step = src.step or (start <= stop and 1 or -1)
      if step == 0 then llbl.fail("gps range step must not be zero", { code = "E_GPS_RANGE_STEP", primary = src.origin }, 2) end
      return gps_range_gen, { start, stop, step }, start - step
    end
    if kind == "raw" then return gps.raw(src.gen, src.param, src.state) end
    llbl.fail("unknown gps source kind " .. tostring(kind), { code = "E_GPS_SOURCE", primary = src.origin }, 2)
  end
  return nil
end

function gps.raw(obj, param, state)
  local g, p0, s0 = gps_source_to_raw(obj)
  if g then return g, p0, s0 end
  if gps_plan_is(obj) then return gps.unwrap(gps.interpret(obj)) end
  if gps_is(obj) then return obj.gen, obj.param, obj.state end
  if obj == nil then return gps_empty_gen, nil, nil end
  local tv = type(obj)
  if tv == "function" or (tv == "table" and getmetatable(obj) and getmetatable(obj).__call) then
    return obj, param, state
  end
  if tv == "string" then
    if obj == "" then return gps_empty_gen, nil, nil end
    return gps_string_gen, obj, 0
  end
  if tv == "table" then
    local mt = getmetatable(obj)
    if mt ~= nil then
      if mt == Gps then return obj.gen, obj.param, obj.state end
      if mt.__ipairs ~= nil then return mt.__ipairs(obj) end
      if mt.__pairs ~= nil then return mt.__pairs(obj) end
    end
    if #obj > 0 then return gps_array_gen, obj, 0 end
    return gps_record_gen, obj, nil
  end
  llbl.fail("object " .. repr(obj) .. " of type " .. type(obj) .. " cannot be lowered to GPS", {
    code = "E_GPS_RAW",
    primary = origin_of(obj),
  }, 2)
end

function gps.iter(obj, param, state)
  return gps.wrap(gps.raw(obj, param, state))
end

gps.from = {}

function gps.empty()
  return gps.wrap(gps_empty_gen, nil, nil, { kind = "empty" })
end

function gps.once(...)
  return gps.wrap(gps_once_gen, pack(...), nil, { kind = "once" })
end

function gps.from.empty()
  return gps.empty()
end

function gps.from.once(...)
  return gps.once(...)
end

function gps.from.array(t)
  return gps.wrap(gps_array_gen, t or {}, 0, { kind = "array" })
end

function gps.from.record(t)
  return gps.wrap(gps_record_gen, t or {}, nil, { kind = "record" })
end

function gps.from.string(s0)
  if s0 == nil or s0 == "" then return gps.empty() end
  return gps.wrap(gps_string_gen, s0, 0, { kind = "string" })
end

function gps.from.range(start, stop, step)
  if stop == nil then stop = start; start = stop > 0 and 1 or -1 end
  step = step or (start <= stop and 1 or -1)
  if step == 0 then llbl.fail("gps range step must not be zero", { code = "E_GPS_RANGE_STEP" }, 2) end
  return gps.wrap(gps_range_gen, { start, stop, step }, start - step, { kind = "range" })
end

gps.spec = {}
function gps.spec.empty() return { __llbl_tag = "GpsSource", kind = "empty", origin = source.capture("gps-source", { hint = "empty" }) } end
function gps.spec.array(t) return { __llbl_tag = "GpsSource", kind = "array", value = t or {}, origin = source.capture("gps-source", { hint = "array" }) } end
function gps.spec.record(t) return { __llbl_tag = "GpsSource", kind = "record", value = t or {}, origin = source.capture("gps-source", { hint = "record" }) } end
function gps.spec.string(s0) return { __llbl_tag = "GpsSource", kind = "string", value = s0 or "", origin = source.capture("gps-source", { hint = "string" }) } end
function gps.spec.once(...) return { __llbl_tag = "GpsSource", kind = "once", values = pack(...), origin = source.capture("gps-source", { hint = "once" }) } end
function gps.spec.range(start, stop, step) return { __llbl_tag = "GpsSource", kind = "range", start = start, stop = stop, step = step, origin = source.capture("gps-source", { hint = "range" }) } end
function gps.spec.raw(gen, param, state) return { __llbl_tag = "GpsSource", kind = "raw", gen = gen, param = param, state = state, origin = source.capture("gps-source", { hint = "raw" }) } end
function gps.spec.any(v, param, state)
  local gen, p0, s0 = gps.raw(v, param, state)
  return gps.spec.raw(gen, p0, s0)
end

local function gps_step(gen, param, state)
  return gen(param, state)
end
gps.step = gps_step

function gps.values(gen, param, state)
  gen, param, state = gps.raw(gen, param, state)
  return function()
    local r = pack(gen(param, state))
    if r[1] == nil then return nil end
    state = r[1]
    return unpack(r, 2, r.n)
  end
end

function gps.each(fn, gen, param, state)
  gen, param, state = gps.raw(gen, param, state)
  while true do
    local r = pack(gen(param, state))
    if r[1] == nil then return nil end
    state = r[1]
    fn(unpack(r, 2, r.n))
  end
end

local function gps_map_gen(param, state)
  local r = pack(param[1](param[2], state))
  if r[1] == nil then return nil end
  return r[1], param[3](unpack(r, 2, r.n))
end
function gps.map(fn, gen, param, state)
  gen, param, state = gps.raw(gen, param, state)
  return gps.wrap(gps_map_gen, { gen, param, fn }, state, { kind = "map" })
end

local function gps_tap_gen(param, state)
  local r = pack(param[1](param[2], state))
  if r[1] == nil then return nil end
  param[3](unpack(r, 2, r.n))
  return gps_repack_return(r)
end
function gps.tap(fn, gen, param, state)
  gen, param, state = gps.raw(gen, param, state)
  return gps.wrap(gps_tap_gen, { gen, param, fn }, state, { kind = "tap" })
end

local function gps_filter_gen(param, state)
  while true do
    local r = pack(param[1](param[2], state))
    if r[1] == nil then return nil end
    state = r[1]
    if param[3](unpack(r, 2, r.n)) then return gps_repack_return(r) end
  end
end
function gps.filter(pred, gen, param, state)
  gen, param, state = gps.raw(gen, param, state)
  return gps.wrap(gps_filter_gen, { gen, param, pred }, state, { kind = "filter" })
end

local function gps_filter_map_gen(param, state)
  while true do
    local r = pack(param[1](param[2], state))
    if r[1] == nil then return nil end
    state = r[1]
    local m = pack(param[3](unpack(r, 2, r.n)))
    if m.n > 0 and m[1] ~= nil then return r[1], unpack(m, 1, m.n) end
  end
end
function gps.filter_map(fn, gen, param, state)
  gen, param, state = gps.raw(gen, param, state)
  return gps.wrap(gps_filter_map_gen, { gen, param, fn }, state, { kind = "filter_map" })
end

local function gps_take_gen(param, state)
  local i, inner_state = state[1], state[2]
  if i >= param[1] then return nil end
  local r = pack(param[2](param[3], inner_state))
  if r[1] == nil then return nil end
  return { i + 1, r[1] }, unpack(r, 2, r.n)
end
function gps.take(n, gen, param, state)
  if type(n) ~= "number" or n < 0 then llbl.fail("gps.take expects a non-negative number", { code = "E_GPS_TAKE" }, 2) end
  if n == 0 then return gps.empty() end
  gen, param, state = gps.raw(gen, param, state)
  return gps.wrap(gps_take_gen, { n, gen, param }, { 0, state }, { kind = "take" })
end

function gps.drop(n, gen, param, state)
  if type(n) ~= "number" or n < 0 then llbl.fail("gps.drop expects a non-negative number", { code = "E_GPS_DROP" }, 2) end
  gen, param, state = gps.raw(gen, param, state)
  for _ = 1, n do
    local next_state = gen(param, state)
    if next_state == nil then return gps.empty() end
    state = next_state
  end
  return gps.wrap(gen, param, state, { kind = "drop" })
end

local function gps_enumerate_gen(param, state)
  local i, inner_state = state[1], state[2]
  local r = pack(param[1](param[2], inner_state))
  if r[1] == nil then return nil end
  return { i + 1, r[1] }, i, unpack(r, 2, r.n)
end
function gps.enumerate(gen, param, state)
  gen, param, state = gps.raw(gen, param, state)
  return gps.wrap(gps_enumerate_gen, { gen, param }, { 1, state }, { kind = "enumerate" })
end

local function gps_flatmap_gen(param, state)
  state = state or { outer = param[3] }
  while true do
    if state.inner_gen ~= nil then
      local r = pack(state.inner_gen(state.inner_param, state.inner_state))
      if r[1] ~= nil then
        state.inner_state = r[1]
        return { outer = state.outer, inner_gen = state.inner_gen, inner_param = state.inner_param, inner_state = state.inner_state }, unpack(r, 2, r.n)
      end
      state.inner_gen, state.inner_param, state.inner_state = nil, nil, nil
    end
    local outer = pack(param[1](param[2], state.outer))
    if outer[1] == nil then return nil end
    state.outer = outer[1]
    local made = pack(param[4](unpack(outer, 2, outer.n)))
    state.inner_gen, state.inner_param, state.inner_state = gps.raw(unpack(made, 1, made.n))
  end
end
function gps.flatmap(fn, gen, param, state)
  gen, param, state = gps.raw(gen, param, state)
  return gps.wrap(gps_flatmap_gen, { gen, param, state, fn }, { outer = state }, { kind = "flatmap" })
end

local function gps_numargs(...)
  local n = select("#", ...)
  if n >= 3 then
    local maybe_gps = select(n - 2, ...)
    if gps_is(maybe_gps) and maybe_gps.param == select(n - 1, ...) and maybe_gps.state == select(n, ...) then
      return n - 2
    end
  end
  return n
end

local function gps_zip_gen(param, state)
  local new_state, payload = {}, { n = 0 }
  for i = 1, param.n do
    local triple = param[i]
    local r = pack(triple.gen(triple.param, state[i]))
    if r[1] == nil then return nil end
    new_state[i] = r[1]
    for j = 2, r.n do payload.n = payload.n + 1; payload[payload.n] = r[j] end
  end
  return new_state, unpack(payload, 1, payload.n)
end
function gps.zip(...)
  local n = gps_numargs(...)
  if n == 0 then return gps.empty() end
  local param, state = { n = n }, {}
  for i = 1, n do
    local elem = select(i, ...)
    local g, p0, s0 = gps.raw(elem)
    param[i] = { gen = g, param = p0 }
    state[i] = s0
  end
  return gps.wrap(gps_zip_gen, param, state, { kind = "zip" })
end

local function gps_chain_gen(param, state)
  local i, inner_state = state[1], state[2]
  while i <= param.n do
    local triple = param[i]
    local r = pack(triple.gen(triple.param, inner_state))
    if r[1] ~= nil then return { i, r[1] }, unpack(r, 2, r.n) end
    i = i + 1
    triple = param[i]
    inner_state = triple and triple.state or nil
  end
  return nil
end
function gps.chain(...)
  local n = gps_numargs(...)
  if n == 0 then return gps.empty() end
  local param = { n = n }
  for i = 1, n do
    local elem = select(i, ...)
    local g, p0, s0 = gps.raw(elem)
    param[i] = { gen = g, param = p0, state = s0 }
  end
  return gps.wrap(gps_chain_gen, param, { 1, param[1].state }, { kind = "chain" })
end

function gps.fold(fn, acc, gen, param, state)
  gen, param, state = gps.raw(gen, param, state)
  while true do
    local r = pack(gen(param, state))
    if r[1] == nil then return acc end
    state = r[1]
    acc = fn(acc, unpack(r, 2, r.n))
  end
end

function gps.drain(fn, gen, param, state)
  gen, param, state = gps.raw(gen, param, state)
  while true do
    local r = pack(gen(param, state))
    if r[1] == nil then return nil end
    state = r[1]
    if fn then fn(unpack(r, 2, r.n)) end
  end
end

function gps.collect_array(gen, param, state)
  local out = {}
  gps.each(function(v) out[#out + 1] = v end, gen, param, state)
  return out
end

function gps.collect_map(gen, param, state)
  local out = {}
  gps.each(function(k, v) out[k] = v end, gen, param, state)
  return out
end

gps.collect = {}
function gps.collect.array(gen, param, state) return gps.collect_array(gen, param, state) end
function gps.collect.map(gen, param, state) return gps.collect_map(gen, param, state) end

gps.materializer = {}
function gps.materializer.array() return { __llbl_tag = "GpsMaterializer", tag = "array" } end
function gps.materializer.map() return { __llbl_tag = "GpsMaterializer", tag = "map" } end
function gps.materializer.fold(fn, init) return { __llbl_tag = "GpsMaterializer", tag = "fold", fn = fn, init = init } end
function gps.materializer.drain(fn) return { __llbl_tag = "GpsMaterializer", tag = "drain", fn = fn } end

local function gps_apply_materializer(materializer, gen, param, state)
  if materializer == nil then return gps.wrap(gen, param, state, { kind = "materializer:none" }) end
  local tag = type(materializer) == "table" and materializer.tag or nil
  if tag == "array" then return gps.collect_array(gen, param, state) end
  if tag == "map" then return gps.collect_map(gen, param, state) end
  if tag == "fold" then return gps.fold(materializer.fn, materializer.init, gen, param, state) end
  if tag == "drain" then return gps.drain(materializer.fn, gen, param, state) end
  if type(materializer) == "function" then return materializer(gen, param, state) end
  llbl.fail("unknown gps materializer " .. tostring(tag), { code = "E_GPS_MATERIALIZER", primary = origin_of(materializer) }, 2)
end

Gps.__call = function(self, param, state)
  if param == nil then param = self.param end
  if state == nil then state = self.state end
  return self.gen(param, state)
end
Gps.__tostring = function(self)
  local meta = rawget(self, "meta") or {}
  return "<llbl.gps:" .. tostring(meta.kind or "raw") .. ">"
end
function Gps:unwrap() return self.gen, self.param, self.state end
function Gps:values() return gps.values(self.gen, self.param, self.state) end
function Gps:each(fn) return gps.each(fn, self.gen, self.param, self.state) end
function Gps:map(fn) return gps.map(fn, self.gen, self.param, self.state) end
function Gps:tap(fn) return gps.tap(fn, self.gen, self.param, self.state) end
function Gps:filter(fn) return gps.filter(fn, self.gen, self.param, self.state) end
function Gps:filter_map(fn) return gps.filter_map(fn, self.gen, self.param, self.state) end
function Gps:flatmap(fn) return gps.flatmap(fn, self.gen, self.param, self.state) end
function Gps:take(n) return gps.take(n, self.gen, self.param, self.state) end
function Gps:drop(n) return gps.drop(n, self.gen, self.param, self.state) end
function Gps:enumerate() return gps.enumerate(self.gen, self.param, self.state) end
function Gps:fold(fn, acc) return gps.fold(fn, acc, self.gen, self.param, self.state) end
function Gps:collect_array() return gps.collect_array(self.gen, self.param, self.state) end
function Gps:collect_map() return gps.collect_map(self.gen, self.param, self.state) end
function Gps:to_array() return self:collect_array() end
function Gps:to_map() return self:collect_map() end
function Gps:totable() return self:collect_array() end
function Gps:tomap() return self:collect_map() end
function Gps:describe() return gps.describe(self) end

gps.Gps = Gps

gps.op = {}
local function gps_op(tag, spec)
  spec = shallow_copy(spec or {})
  spec.__llbl_tag = "GpsOp"
  spec.tag = tag
  spec.origin = spec.origin or source.capture("gps-op", { hint = tag })
  return spec
end
function gps.op.map(fn) return gps_op("map", { fn = fn }) end
function gps.op.tap(fn) return gps_op("tap", { fn = fn }) end
function gps.op.filter(fn) return gps_op("filter", { fn = fn }) end
function gps.op.filter_map(fn) return gps_op("filter_map", { fn = fn }) end
function gps.op.flatmap(fn) return gps_op("flatmap", { fn = fn }) end
function gps.op.take(n) return gps_op("take", { n = n }) end
function gps.op.drop(n) return gps_op("drop", { n = n }) end
function gps.op.enumerate() return gps_op("enumerate", {}) end
function gps.op.chain(...) return gps_op("chain", { sources = pack(...) }) end
function gps.op.zip(...) return gps_op("zip", { sources = pack(...) }) end

local function gps_apply_op(op, gen, param, state)
  if not gps_op_is(op) then llbl.fail("gps plan expected GpsOp, got " .. repr(op), { code = "E_GPS_PLAN_OP", primary = origin_of(op) }, 2) end
  local tag = op.tag
  if tag == "map" then return gps.raw(gps.map(op.fn, gen, param, state)) end
  if tag == "tap" then return gps.raw(gps.tap(op.fn, gen, param, state)) end
  if tag == "filter" then return gps.raw(gps.filter(op.fn, gen, param, state)) end
  if tag == "filter_map" then return gps.raw(gps.filter_map(op.fn, gen, param, state)) end
  if tag == "flatmap" then return gps.raw(gps.flatmap(op.fn, gen, param, state)) end
  if tag == "take" then return gps.raw(gps.take(op.n, gen, param, state)) end
  if tag == "drop" then return gps.raw(gps.drop(op.n, gen, param, state)) end
  if tag == "enumerate" then return gps.raw(gps.enumerate(gen, param, state)) end
  if tag == "chain" then
    local cur = gps.wrap(gen, param, state)
    local xs = { cur }
    for i = 1, op.sources.n do xs[#xs + 1] = op.sources[i] end
    return gps.raw(gps.chain(unpack(xs, 1, #xs)))
  end
  if tag == "zip" then
    local cur = gps.wrap(gen, param, state)
    local xs = { cur }
    for i = 1, op.sources.n do xs[#xs + 1] = op.sources[i] end
    return gps.raw(gps.zip(unpack(xs, 1, #xs)))
  end
  llbl.fail("unknown gps op " .. tostring(tag), { code = "E_GPS_OP", primary = op.origin }, 2)
end

function gps.plan(spec)
  if gps_plan_is(spec) then return spec end
  spec = spec or {}
  local ops = {}
  for i = 1, #(spec.ops or spec) do
    local op = (spec.ops or spec)[i]
    if not gps_op_is(op) then llbl.fail("gps plan op #" .. tostring(i) .. " is not a GpsOp", { code = "E_GPS_PLAN_OP", primary = origin_of(op) }, 2) end
    ops[#ops + 1] = op
  end
  return setmetatable({
    __llbl_tag = "GpsPlan",
    name = spec.name or "gps-plan",
    source = spec.source or gps.spec.empty(),
    ops = ops,
    protocol = llbl.protocol_name(spec.protocol) or "pull",
    region = spec.region,
    materializer = spec.materializer,
    metadata = spec.metadata,
    origin = spec.origin or source.capture("gps-plan", { hint = spec.name or "gps" }),
  }, GpsPlan)
end

function gps.interpret(plan)
  plan = gps.plan(plan)
  local gen, param, state = gps.raw(plan.source)
  for i = 1, #(plan.ops or {}) do
    gen, param, state = gps_apply_op(plan.ops[i], gen, param, state)
  end
  return gps.wrap(gen, param, state, { kind = "plan", plan = plan, backend = "interpret" })
end

function gps.fuse(plan)
  -- Reference fusion pass. It currently preserves semantics by interpreting the
  -- plan graph through raw machine primitives. The explicit object exists so
  -- future passes can collapse adjacent maps/filters without changing callers.
  local s0 = gps.interpret(plan)
  s0.meta.backend = "fuse"
  return s0, s0.param, s0.state
end

local function gps_compile_array_plan(plan, opts)
  opts = opts or {}
  local src = plan.source
  if not gps_source_is(src) or src.kind ~= "array" then return nil, "source is not a gps.spec.array spec" end
  local ops = plan.ops or {}
  for i = 1, #ops do
    local tag = ops[i].tag
    if tag ~= "map" and tag ~= "tap" and tag ~= "filter" and tag ~= "take" and tag ~= "drop" then
      return nil, "op " .. tostring(tag) .. " is not supported by the array codegen backend"
    end
  end

  local param = { src = src.value or {}, n = #(src.value or {}) }
  local lines = {
    "return function(p, state)",
    "  local src = p.src",
    "  local n = p.n",
    "  local i = state[1] or 0",
  }
  local counter_count = 0
  for i = 1, #ops do
    local tag = ops[i].tag
    if tag == "map" or tag == "filter" or tag == "tap" then
      local fname = "fn" .. tostring(i)
      param[fname] = ops[i].fn
    elseif tag == "take" or tag == "drop" then
      counter_count = counter_count + 1
      local cname = "c" .. tostring(counter_count)
      local kname = "k" .. tostring(counter_count)
      param[kname] = ops[i].n
      lines[#lines + 1] = "  local " .. cname .. " = state[" .. tostring(counter_count + 1) .. "] or 0"
      ops[i].__llbl_counter = counter_count
    end
  end
  lines[#lines + 1] = "  while true do"
  lines[#lines + 1] = "    i = i + 1"
  lines[#lines + 1] = "    if i > n then return nil end"
  lines[#lines + 1] = "    local v = src[i]"
  lines[#lines + 1] = "    local alive = true"
  for i = 1, #ops do
    local op = ops[i]
    local tag = op.tag
    if tag == "map" then
      lines[#lines + 1] = "    if alive then v = p.fn" .. tostring(i) .. "(v) end"
    elseif tag == "tap" then
      lines[#lines + 1] = "    if alive then p.fn" .. tostring(i) .. "(v) end"
    elseif tag == "filter" then
      lines[#lines + 1] = "    if alive and not p.fn" .. tostring(i) .. "(v) then alive = false end"
    elseif tag == "drop" then
      local idx = op.__llbl_counter
      lines[#lines + 1] = "    if alive then c" .. tostring(idx) .. " = c" .. tostring(idx) .. " + 1; if c" .. tostring(idx) .. " <= p.k" .. tostring(idx) .. " then alive = false end end"
    elseif tag == "take" then
      local idx = op.__llbl_counter
      lines[#lines + 1] = "    if alive then if c" .. tostring(idx) .. " >= p.k" .. tostring(idx) .. " then return nil end; c" .. tostring(idx) .. " = c" .. tostring(idx) .. " + 1 end"
    end
  end
  local state_parts = { "i" }
  for i = 1, counter_count do state_parts[#state_parts + 1] = "c" .. tostring(i) end
  lines[#lines + 1] = "    if alive then return { " .. table.concat(state_parts, ", ") .. " }, v end"
  lines[#lines + 1] = "  end"
  lines[#lines + 1] = "end"
  local src_code = table.concat(lines, "\n")
  local source_name = "@llbl.codegen/gps/" .. tostring(plan.name or "array")
  local chunk, err = compile_lua(src_code, source_name)
  if not chunk then return nil, err, src_code end
  local ok, gen_or_err = pcall(chunk)
  if not ok then return nil, gen_or_err, src_code end
  llbl.codegen.register(gen_or_err, {
    id = "llbl.gps." .. tostring(plan.name or "array"),
    kind = "gps",
    mode = "fast",
    source_name = source_name,
    source_text = src_code,
    line_map = {
      [1] = { kind = "gps-entry", plan = plan.name },
      [3] = { kind = "gps-source", source = "array" },
    },
    origin = plan.origin,
    generated = true,
  })
  local init_state = { 0 }
  for i = 1, counter_count do init_state[i + 1] = 0 end
  local s0 = gps.wrap(gen_or_err, param, init_state, { kind = "compiled-plan", plan = plan, backend = "array-codegen", source = src_code })
  return s0
end

function gps.compile(plan, opts)
  opts = opts or {}
  plan = gps.plan(plan)
  if opts.codegen == false then return gps.fuse(plan) end
  local s0, err, src_code = gps_compile_array_plan(plan, opts)
  if s0 then return s0, s0.param, s0.state end
  if opts.strict then
    llbl.fail("gps plan " .. tostring(plan.name) .. " cannot be codegenerated: " .. tostring(err), {
      code = "E_GPS_CODEGEN",
      primary = plan.origin,
      notes = src_code and { src_code } or nil,
    }, 2)
  end
  local fallback = gps.fuse(plan)
  fallback.meta.backend = "fallback-fuse"
  fallback.meta.codegen_error = err
  return fallback, fallback.param, fallback.state
end

function gps.run(plan, opts)
  plan = gps.plan(plan)
  local s0 = gps.compile(plan, opts)
  local gen, param, state = gps.raw(s0)
  return gps_apply_materializer(plan.materializer, gen, param, state)
end

function GpsPlan:run(opts) return gps.run(self, opts) end
function GpsPlan:interpret() return gps.interpret(self) end
function GpsPlan:fuse() return gps.fuse(self) end
function GpsPlan:compile(opts) return gps.compile(self, opts) end
function GpsPlan:describe() return gps.describe(self) end

function gps.describe(v)
  if gps_is(v) then
    return { tag = "Gps", kind = v.meta and v.meta.kind, backend = v.meta and v.meta.backend, origin = v.meta and v.meta.origin }
  end
  if gps_source_is(v) then
    return { tag = "GpsSource", kind = v.kind, origin = v.origin }
  end
  if gps_op_is(v) then
    return { tag = "GpsOp", op = v.tag, origin = v.origin }
  end
  if gps_plan_is(v) then
    local ops = {}
    for i = 1, #(v.ops or {}) do ops[i] = v.ops[i].tag end
    return {
      tag = "GpsPlan",
      name = v.name,
      protocol = v.protocol,
      region = is_tag(v.region, "Region") and v.region.id or v.region,
      source = gps.describe(v.source),
      ops = ops,
      origin = v.origin,
    }
  end
  return nil
end

gps.GpsPlan = GpsPlan

-- Process adapters. These helpers are defined here, but the process section
-- below installs the actual ProcessHandle implementation.
function gps.process_events(gen, param, state)
  gen, param, state = gps.raw(gen, param, state)
  return function()
    local r = pack(gen(param, state))
    if r[1] == nil then return nil end
    state = r[1]
    return unpack(r, 2, r.n)
  end
end
gps.events = gps.process_events


gps._is_gps = gps_is
gps._is_source = gps_source_is
gps._is_op = gps_op_is
gps._is_plan = gps_plan_is
llbl.Gps = Gps
llbl.GpsPlan = GpsPlan
end

do
local gps = llbl.gps
local gps_plan_is = gps._is_plan

-- ---------------------------------------------------------------------------
-- Processes: GPS-backed resumable protocols
-- ---------------------------------------------------------------------------
--
-- Processes are LLBL's operation model. Every process handle runs as a
-- gen,param,state machine. Process definitions provide a semantic `region`
-- factory or a GPS plan; there is no coroutine execution path.

local Process, ProcessStage, ProcessInputStage, ProcessHandle, ProcessContext = {}, {}, {}, {}, {}
Process.__index = Process
ProcessInputStage.__index = ProcessInputStage
ProcessHandle.__index = ProcessHandle

local function process_event(ctx, kind, payload, origin)
  ctx.seq = (ctx.seq or 0) + 1
  local ev = {
    __llbl_tag = "ProcessEvent",
    process = ctx.process.name,
    kind = tostring(kind),
    seq = ctx.seq,
    origin = origin or source.capture("process-event", { hint = kind, skip = 2 }),
  }
  if type(payload) == "table" then
    for k, v in pairs(payload) do ev[k] = v end
  elseif payload ~= nil then
    ev.value = payload
  end
  return ev
end

local function process_payload_event(ctx, a, b, c, d, e)
  if is_tag(a, "ProcessEvent") then return a end
  if type(a) == "string" then
    if b == nil then return process_event(ctx, a, nil, nil) end
    if type(b) == "table" and c == nil then return process_event(ctx, a, b, origin_of(b)) end
    return process_event(ctx, a, { value = b, extra = { c, d, e } }, origin_of(b))
  end
  if type(a) == "table" and rawget(a, "kind") then return process_event(ctx, a.kind, a, origin_of(a)) end
  return process_event(ctx, "event", { value = a, extra = { b, c, d, e } }, origin_of(a))
end

local ProcessContextMethods = {}

function ProcessContextMethods:yield(event)
  if not is_tag(event, "ProcessEvent") then
    local kind = type(event) == "table" and event.kind or "event"
    event = process_event(self, kind, event, origin_of(event))
  end
  return event
end

function ProcessContextMethods:make_event(kind, payload, origin)
  return process_event(self, kind, payload, origin or origin_of(payload))
end
ProcessContextMethods.emit = ProcessContextMethods.make_event

function ProcessContextMethods:event(kind, payload)
  return process_event(self, kind, payload, origin_of(payload))
end

function ProcessContextMethods:diagnostic_event(spec)
  spec = spec or {}
  local d = llbl.diagnostic(spec)
  if self.diagnostics then self.diagnostics:add(d) end
  return process_event(self, "diagnostic", { diagnostic = d, severity = d.severity, code = d.code, message = d.message }, d.primary)
end

function ProcessContextMethods:diagnostic(spec)
  return self:diagnostic_event(spec)
end

function ProcessContextMethods:here(kind)
  return source.capture(kind or "process", { skip = 1 })
end

function ProcessContextMethods:at(value, origin)
  return llbl.at(origin or self:here("process-at"), value)
end

function ProcessContextMethods:origin()
  return self.handle.origin
end

function ProcessContextMethods:budget()
  return self.handle.budget
end

function ProcessContextMethods:consume(n)
  n = n or 1
  local h = self.handle
  if h.budget == nil then return true end
  h.budget = h.budget - n
  if h.budget <= 0 then
    return self:event("budget_exhausted", { budget = 0 })
  end
  return true
end

function ProcessContextMethods:cancelled()
  return self.handle.cancelled and true or false
end

function ProcessContextMethods:gps(source0, ops)
  local plan = gps_plan_is(source0) and source0 or gps.plan { source = source0, ops = ops or {} }
  return gps.compile(plan)
end

ProcessContext.__index = function(ctx, key)
  if ProcessContextMethods[key] then return ProcessContextMethods[key] end
  return function(payload)
    if key == "error" or key == "warning" then
      payload = payload or {}
      payload.severity = key
      return ProcessContextMethods.diagnostic(ctx, payload)
    end
    return ProcessContextMethods.event(ctx, key, payload)
  end
end

local function process_context(handle)
  return setmetatable({
    __llbl_tag = "ProcessContext",
    process = handle.process,
    handle = handle,
    diagnostics = handle.diagnostics,
    seq = 0,
  }, ProcessContext)
end

local function normalize_process_spec(name, body, origin)
  if is_tag(body, "Region") then body = { region_descriptor = body } end
  local has_region_plan = gps_plan_is(body)
  if has_region_plan then body = { plan = body } end
  if type(body) ~= "table" then
    llbl.fail("process " .. tostring(name) .. " expects a Region or GPS plan", { code = "E_BAD_PROCESS", primary = origin })
  end
  if is_tag(body.region, "Region") and body.region_descriptor == nil then
    body.region_descriptor = body.region
    body.region = nil
  end
  local has_region = is_tag(body.region_descriptor, "Region") or gps_plan_is(body.plan) or body.plan ~= nil
  if not has_region then
    llbl.fail("process " .. tostring(name) .. " expects a Region or GPS plan", { code = "E_BAD_PROCESS", primary = origin })
  end
  local process_name = tostring(name)
  local region_descriptor = body.region_descriptor or body.descriptor
  if region_descriptor == nil then
    local region_body = body.plan ~= nil and gps.plan(body.plan) or body.plan
    region_descriptor = llbl.region("llbl.process." .. process_name)["process"] { "context", "args" } (region_body)
    region_descriptor.body_kind = "gps-plan"
    region_descriptor.origin = origin or region_descriptor.origin
    if region_descriptor.materializers.events == nil then
      region_descriptor:materializer("events", { kind = "process-events", origin = origin })
    end
  end
  return setmetatable({
    __llbl_tag = "Process",
    name = process_name,
    region = body.region,
    plan = body.plan,
    region_descriptor = region_descriptor,
    backend = "gps",
    spec = body,
    origin = origin or source.capture("process", { hint = name }),
  }, Process)
end

local function is_process_definition_spec(body)
  return type(body) == "table" and (
    is_tag(body, "Region")
    or gps_plan_is(body)
    or rawget(body, "region") ~= nil
    or rawget(body, "region_descriptor") ~= nil
    or rawget(body, "descriptor") ~= nil
    or rawget(body, "plan") ~= nil
  )
end

local function normalize_process_inputs(inputs)
  if inputs == nil then inputs = {}
  elseif type(inputs) ~= "table" then inputs = { inputs }
  else inputs = shallow_copy(inputs) end
  local out = { "ctx" }
  if inputs[1] == "ctx" or inputs[1] == "context" then
    out = {}
  end
  for i = 1, #inputs do out[#out + 1] = inputs[i] end
  return out
end

local function process_region_from_body(name, inputs, body, origin)
  local r = llbl.region("llbl.process." .. tostring(name))["process"] (normalize_process_inputs(inputs)) (body)
  r.body_kind = "process-region"
  r.origin = origin or r.origin
  if r.materializers.events == nil then
    r:materializer("events", { kind = "process-events", origin = origin })
  end
  return r
end

local function process_take_opts(args)
  local opts = {}
  if args.n > 0 and type(args[args.n]) == "table" and rawget(args[args.n], "__llbl_process_opts") then
    opts = args[args.n]
    args[args.n] = nil
    args.n = args.n - 1
  end
  return opts
end

local function process_region_raw(h, ctx, opts)
  local p = h.process
  local made
  if is_tag(p.region_descriptor, "Region") then
    made = pack(p.region_descriptor:gps(ctx, unpack(h.args, 1, h.args.n)))
  elseif gps_plan_is(p.plan) then
    made = pack(p.plan)
  elseif p.plan ~= nil then
    made = pack(gps.plan(p.plan))
  else
    llbl.fail("process " .. tostring(p.name) .. " has no region/GPS backend", { code = "E_PROCESS_NO_GPS", primary = p.origin }, 2)
  end

  local first = made[1]
  local gen, param, state
  if gps_plan_is(first) then
    local compiled = (opts.codegen == false) and gps.fuse(first) or gps.compile(first, opts.region or opts)
    gen, param, state = gps.raw(compiled)
  elseif type(first) ~= "function" and not is_tag(first, "Gps") and not gps._is_source(first) then
    llbl.fail("process " .. tostring(p.name) .. " region factory must return gen,param,state, Gps, GpsSource, or GpsPlan", {
      code = "E_PROCESS_GPS",
      primary = p.origin,
    }, 2)
  else
    gen, param, state = gps.raw(unpack(made, 1, made.n))
  end
  return gen, param, state
end

function Process:start(...)
  local args = pack(...)
  local opts = process_take_opts(args)
  local h = setmetatable({
    __llbl_tag = "ProcessHandle",
    process = self,
    status_value = "ready",
    args = args,
    diagnostics = opts.diagnostics or llbl.diagnostics(),
    budget = opts.budget,
    origin = opts.origin or self.origin,
    result_value = nil,
    error_value = nil,
    cancelled = false,
    backend = "gps",
  }, ProcessHandle)
  local ctx = process_context(h)
  h.context = ctx
  local ok, g, p0, s0 = pcall(process_region_raw, h, ctx, opts)
  if not ok then
    h.status_value = "failed"
    h.error_value = g
  else
    h.gps_gen, h.gps_param, h.gps_state = g, p0, s0
  end
  return h
end

function ProcessHandle:resume(opts)
  opts = opts or {}
  if opts.budget ~= nil then self.budget = opts.budget end
  if self.status_value == "done" then return nil end
  if self.status_value == "failed" then error(self.error_value, 2) end
  if self.cancelled then self.status_value = "done"; return nil end

  if self.budget ~= nil and self.budget <= 0 then
    self.status_value = "suspended"
    return process_event(self.context, "budget_exhausted", { budget = 0 }, self.origin)
  end

  self.status_value = "running"
  local ok, next_state, a, b, c, d, e = pcall(self.gps_gen, self.gps_param, self.gps_state)
  if not ok then
    self.status_value = "failed"
    self.error_value = next_state
    error(next_state, 2)
  end
  if next_state == nil then
    self.status_value = "done"
    return nil
  end
  self.gps_state = next_state
  if self.budget ~= nil then self.budget = self.budget - 1 end
  self.status_value = "suspended"
  local ev = process_payload_event(self.context, a, b, c, d, e)
  if is_tag(ev, "ProcessEvent") and ev.kind == "result" then
    self.result_value = ev.result ~= nil and ev.result or ev.value
  end
  return ev
end

function ProcessHandle:events()
  return function()
    if self:done() then return nil end
    return self:resume()
  end
end

ProcessHandle.__call = function(self, opts) return self:resume(opts) end
function ProcessHandle:status() return self.status_value end
function ProcessHandle:done() return self.status_value == "done" end
function ProcessHandle:failed() return self.status_value == "failed" end
function ProcessHandle:error() return self.error_value end
function ProcessHandle:result() return self.result_value end
function ProcessHandle:cancel() self.cancelled = true end
function ProcessHandle:gps()
  local function gen(param, state)
    local ev = param:resume()
    if ev == nil then return nil end
    return true, ev
  end
  return gps.wrap(gen, self, true, { kind = "process-handle", process = self.process.name })
end

function Process:each(...)
  local h = self:start(...)
  return h:events()
end

Process.__call = function(self, ...)
  return self:each(...)
end

local ProcessFactory = {}
ProcessFactory.__index = function(_, key)
  return setmetatable({ __llbl_tag = "ProcessStage", name = tostring(key), origin = source.capture("process", { hint = key }) }, ProcessStage)
end
ProcessFactory.__call = function(_, name, body)
  if body == nil then
    return setmetatable({ __llbl_tag = "ProcessStage", name = tostring(name), origin = source.capture("process", { hint = name }) }, ProcessStage)
  end
  return normalize_process_spec(name, body, source.capture("process", { hint = name }))
end
ProcessStage.__call = function(self, body)
  if type(body) == "table" and not is_process_definition_spec(body) then
    return setmetatable({
      __llbl_tag = "ProcessInputStage",
      name = self.name,
      inputs = body,
      origin = self.origin,
    }, ProcessInputStage)
  end
  local p = normalize_process_spec(self.name, body, self.origin)
  llbl.processes[p.name] = p
  return p
end
ProcessInputStage.__call = function(self, body)
  local descriptor = process_region_from_body(self.name, self.inputs, body, self.origin)
  local p = normalize_process_spec(self.name, descriptor, self.origin)
  llbl.processes[p.name] = p
  return p
end

llbl.processes = {}
llbl.process = setmetatable({ __llbl_tag = "ProcessFactory" }, ProcessFactory)
llbl.Process = Process
llbl.ProcessHandle = ProcessHandle
llbl.ProcessContext = ProcessContext

function llbl.describe_process(process)
  if type(process) == "string" then process = llbl.processes[process] end
  if not is_tag(process, "Process") then return nil end
  return {
    tag = "Process",
    name = process.name,
    origin = process.origin,
    backend = process.backend,
    region = llbl.describe_region(process.region_descriptor),
    has_region = is_tag(process.region_descriptor, "Region") or process.plan ~= nil,
  }
end

function llbl.process_opts(opts)
  opts = opts or {}
  opts.__llbl_process_opts = true
  return opts
end

end

-- ---------------------------------------------------------------------------
-- Node helpers
-- ---------------------------------------------------------------------------
--
-- Generic nodes are the default normalized AST form for languages that do not
-- provide their own ASDL layer. Lalin uses richer ASDL values, but the LLBL
-- core keeps this small node model for dialect authors and examples.

local Node = {}
Node.__index = Node

local function node(tag, fields, origin)
  fields = fields or {}
  fields.__llbl_tag = fields.__llbl_tag or "Node"
  fields.tag = fields.tag or tag
  fields.origin = fields.origin or origin or source.capture("node")
  if getmetatable(fields) == nil then setmetatable(fields, Node) end
  return fields
end

llbl.node = node

function Node:source_context(radius) return source.context(self.origin, radius) end
function Node:explain() return source.render_excerpt(self.origin, 2, self.tag or "node") end
llbl.Node = Node

local function attach_node_meta(v, tag, meta)
  if type(v) == "table" and getmetatable(v) ~= nil and rawget(v, "__llbl_tag") == nil then
    return v
  end
  if type(v) ~= "table" then v = { value = v } end
  v.__llbl_tag = v.__llbl_tag or "Node"
  v.tag = v.tag or tag
  v.__llbl = v.__llbl or {}
  for k, x in pairs(meta or {}) do if v.__llbl[k] == nil then v.__llbl[k] = x end end
  v.origin = v.origin or (meta and meta.origin) or v.__llbl.origin
  if getmetatable(v) == nil then setmetatable(v, Node) end
  return v
end

-- ---------------------------------------------------------------------------
-- Names, symbols, captures, expressions
-- ---------------------------------------------------------------------------
--
-- This is the parserless core:
--
--   unknown_name        -> llbl.Symbol
--   x [T]               -> Capture(subject=x, value=T)
--   a + b               -> Expr(kind="binop")
--   obj.field / obj[i]  -> Expr field/index forms
--
-- Lua syntax does the tokenization and precedence. LLBL only receives values.

local Name = {}; Name.__index = Name
function llbl.name(text, opts)
  opts = opts or {}
  return setmetatable({ __llbl_tag = "Name", text = tostring(text), computed = opts.computed and true or false, origin = opts.origin or source.capture("name", { hint = text }) }, Name)
end

local Expr, Symbol, Capture = {}, {}, {}

local function expr(kind, fields)
  fields = fields or {}
  fields.__llbl_tag = "Expr"; fields.kind = kind
  fields.origin = fields.origin or source.capture("expr", { hint = fields.hint })
  return setmetatable(fields, Expr)
end
llbl.expr = expr

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
llbl.type_like_predicates = type_like_predicates

function llbl.register_type_like(fn)
  if type(fn) ~= "function" then llbl.fail("type-like predicate must be a function") end
  type_like_predicates[#type_like_predicates + 1] = fn
  return fn
end

function llbl.is_type_like(v)
  if is_tag(v, "Type") then return true end
  for i = 1, #type_like_predicates do
    local ok, yes = pcall(type_like_predicates[i], v)
    if not ok then
      llbl.fail("type-like predicate #" .. tostring(i) .. " failed: " .. tostring(yes), {
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
  return { __llbl_tag = "CaptureInit", capture = self, init = init == nil and NIL or init, origin = source.capture("capture-init") }
end

Symbol.__index = function(self, key)
  if Symbol[key] then return Symbol[key] end
  if llbl.is_type_like(key) then return setmetatable({ __llbl_tag = "Capture", subject = self, value = key, origin = source.capture("capture", { hint = self.text }) }, Capture) end
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

function llbl.symbol(text, opts)
  opts = opts or {}
  return setmetatable({
    __llbl_tag = "Symbol",
    text = tostring(text),
    generated = opts.generated and true or false,
    symbol_kind = opts.kind or (opts.generated and "generated" or "source"),
    origin = opts.origin or source.capture(opts.generated and "generated-name" or "symbol", { hint = text }),
  }, Symbol)
end

llbl.N = setmetatable({ __llbl_tag = "NameFactory" }, {
  __index = function(_, key) return llbl.symbol(key, { generated = true, origin = source.capture("generated-name", { hint = key }) }) end,
  __call = function(_, key) return llbl.symbol(key, { generated = true, origin = source.capture("generated-name", { hint = key }) }) end,
})

llbl.Binding = llbl.Binding or {}
llbl.Binding.__index = llbl.Binding
function llbl.binding(spec)
  spec = spec or {}
  spec.__llbl_tag = "Binding"
  spec.name = tostring(spec.name or (spec.symbol and spec.symbol.text) or "")
  spec.kind = spec.kind or "export"
  spec.origin = spec.origin or origin_of(spec.symbol) or source.capture("binding", { hint = spec.name })
  return setmetatable(spec, llbl.Binding)
end

llbl.shared = llbl.shared or {}
llbl.shared.origins = llbl.shared.origins or {
  here = llbl.here,
  at = llbl.at,
  of = llbl.origin_of,
  render = llbl.render_origin,
  provenance = llbl.provenance,
}
llbl.shared.diagnostics = llbl.shared.diagnostics or {
  new = llbl.diagnostics,
  diagnostic = llbl.diagnostic,
  fail = llbl.fail,
}
llbl.shared.regions = llbl.shared.regions or {
  define = llbl.region,
  gps = llbl.region_gps,
  materialize = llbl.region_materialize,
  lowering = llbl.lowering,
  materializer = llbl.materializer,
  describe = llbl.describe_region,
}
llbl.shared.symbols = llbl.shared.symbols or {}
function llbl.shared.symbols.source(text, opts)
  opts = opts or {}
  opts.kind = opts.kind or "source"
  return llbl.symbol(text, opts)
end
function llbl.shared.symbols.generated(text, opts)
  opts = opts or {}
  opts.generated = true
  opts.kind = opts.kind or "generated"
  return llbl.symbol(text, opts)
end
function llbl.shared.symbols.scope(prefix, opts)
  opts = opts or {}
  local scope = {
    __llbl_tag = "SymbolScope",
    prefix = tostring(prefix or "g"),
    counter = tonumber(opts.start or 0) or 0,
    origin = opts.origin or source.capture("symbol-scope", { hint = prefix }),
  }
  function scope:fresh(stem)
    self.counter = self.counter + 1
    return llbl.shared.symbols.generated(tostring(self.prefix) .. "_" .. tostring(stem or "tmp") .. "_" .. tostring(self.counter), {
      origin = child_origin(self.origin, { kind = "fresh-symbol", stem = stem }),
    })
  end
  function scope:generated(stem) return self:fresh(stem) end
  function scope:source(name) return llbl.shared.symbols.source(name, { origin = child_origin(self.origin, { kind = "source-symbol", name = name }) }) end
  return scope
end
function llbl.shared.symbols.unresolved(text, opts)
  opts = opts or {}
  return llbl.binding {
    kind = "unresolved",
    name = text,
    symbol = opts.symbol or llbl.symbol(text, { origin = opts.origin, kind = opts.kind or "source" }),
    origin = opts.origin,
    language = opts.language,
    diagnostic = opts.diagnostic,
  }
end

-- ---------------------------------------------------------------------------
-- Types and fragments
-- ---------------------------------------------------------------------------
--
-- Fragments are reusable role-shaped values. They are the preferred
-- metaprogramming unit because they keep role information attached to the
-- generated items.
--
--   product { a [i32] } .. product { b [i32] }  -- append product/list roles
--   conts { ok {} } + conts { err {} }          -- compose sum/protocol roles
--
-- The short splice marker _(...) is a callable hole sentinel. As a value, `_`
-- marks a curried-form hole. As a call, `_(fragment)` is just llbl.spread(...).

local Type = {}; Type.__index = Type; Type.__tostring = function(self) return self.name or "<type>" end
function llbl.type(name, fields)
  fields = fields or {}; fields.__llbl_tag = "Type"; fields.name = tostring(name); fields.kind = fields.kind or "named"; fields.origin = fields.origin or source.capture("type", { hint = name })
  return setmetatable(fields, Type)
end

local TypeCtor = {}
TypeCtor.__index = function(self, key)
  if TypeCtor[key] then return TypeCtor[key] end
  local args = array_copy(rawget(self, "args")); args[#args + 1] = key
  local arity = rawget(self, "arity") or 1
  local name = rawget(self, "name")
  local emit = rawget(self, "emit")
  if #args < arity then return setmetatable({ __llbl_tag = "TypeCtor", name = name, arity = arity, args = args, emit = emit, origin = rawget(self, "origin") }, TypeCtor) end
  local produced = emit and emit(unpack(args)) or nil
  if llbl.is_type_like(produced) then return produced end
  return llbl.type(name, { kind = "app", ctor = name, args = args, value = produced, origin = source.capture("type-app", { hint = name }) })
end
TypeCtor.__call = function(self, ...)
  local p, cur = pack(...), self
  for i = 1, p.n do cur = TypeCtor.__index(cur, p[i]) end
  return cur
end
function llbl.type_ctor(name, spec)
  if type(spec) == "number" then spec = { arity = spec } end
  if type(spec) == "function" then spec = { emit = spec } end
  spec = spec or {}
  return setmetatable({ __llbl_tag = "TypeCtor", name = tostring(name), arity = spec.arity or 1, args = {}, emit = spec.emit, origin = spec.origin or source.capture("type-ctor", { hint = name }) }, TypeCtor)
end

local Fragment = {}; Fragment.__index = Fragment

local function fragment(role, items, origin, spec)
  items = items or {}
  local out = {
    __llbl_tag = "Fragment",
    role = tostring(role),
    items = items,
    origin = origin or source.capture("fragment", { hint = role }),
  }
  for k, v in pairs(spec or {}) do out[k] = v end
  for i = 1, #items do out[i] = items[i] end
  return setmetatable(out, Fragment)
end

function llbl.fragment(role, items, origin, spec) return fragment(role, items, origin, spec) end
function llbl.spread(value) return { __llbl_tag = "Spread", value = value, origin = source.capture("spread", { hint = "spread" }) } end
function llbl._install_curried_primitives()
  local Hole = {}
  Hole.__index = Hole
  Hole.__call = function(_, value) return llbl.spread(value) end
  Hole.__tostring = function(self) return tostring(rawget(self, "name") or "_") end
  llbl._ = setmetatable({ __llbl_tag = "Hole", name = "_" }, Hole)
  function llbl.hole(name) return setmetatable({ __llbl_tag = "Hole", name = tostring(name or "_"), origin = source.capture("hole", { hint = name or "_" }) }, Hole) end
  function llbl.is_hole(v) return is_tag(v, "Hole") end
  function llbl._curried_first_hole(args)
    for i = 1, #(args or {}) do if llbl.is_hole(args[i]) then return i end end
    return nil
  end

  local Curried = {}
  local function curried_finish(form, args)
    local arity = rawget(form, "arity") or 0
    if #args < arity or llbl._curried_first_hole(args) ~= nil then
      return setmetatable({
        __llbl_tag = "Curried",
        name = rawget(form, "name"),
        arity = arity,
        args = args,
        static = array_copy(rawget(form, "static") or {}),
        emit = rawget(form, "emit"),
        emit_meta = rawget(form, "emit_meta"),
        origin = rawget(form, "origin"),
      }, Curried)
    end
    local emit = rawget(form, "emit")
    if type(emit) ~= "function" then
      llbl.fail("curried form " .. tostring(rawget(form, "name")) .. " has no emitter", {
        code = "E_CURRIED_EMIT",
        primary = rawget(form, "origin"),
      }, 2)
    end
    if rawget(form, "emit_meta") then
      return emit(args, { name = rawget(form, "name"), arity = arity, static = array_copy(rawget(form, "static") or {}), origin = rawget(form, "origin") })
    end
    return emit(unpack(args, 1, arity))
  end

  Curried.__index = function(self, key)
    if Curried[key] then return Curried[key] end
    local static = array_copy(rawget(self, "static") or {})
    static[#static + 1] = key
    return setmetatable({
      __llbl_tag = "Curried",
      name = rawget(self, "name"),
      arity = rawget(self, "arity"),
      args = array_copy(rawget(self, "args") or {}),
      static = static,
      emit = rawget(self, "emit"),
      emit_meta = rawget(self, "emit_meta"),
      origin = rawget(self, "origin"),
    }, Curried)
  end
  Curried.__call = function(self, ...)
    local p = pack(...)
    if p.n ~= 1 then
      llbl.fail("curried form " .. tostring(rawget(self, "name")) .. " expects exactly one argument per call, got " .. tostring(p.n), {
        code = "E_CURRIED_UNARY_CALL",
        primary = rawget(self, "origin"),
      }, 2)
    end
    local args = array_copy(rawget(self, "args") or {})
    local arity = rawget(self, "arity") or 0
    if #args >= arity then
      local hole_i = llbl._curried_first_hole(args)
      if hole_i == nil then
        llbl.fail("too many arguments for curried form " .. tostring(rawget(self, "name")), {
          code = "E_CURRIED_TOO_MANY_ARGUMENTS",
          primary = rawget(self, "origin"),
        }, 2)
      end
      args[hole_i] = p[1]
    else
      args[#args + 1] = p[1]
    end
    return curried_finish(self, args)
  end
  Curried.__tostring = function(self)
    return "llbl.curried(" .. tostring(rawget(self, "name")) .. ", " .. tostring(#(rawget(self, "args") or {})) .. "/" .. tostring(rawget(self, "arity") or 0) .. ")"
  end
  function Curried:describe() return llbl.describe_curried(self) end

  function llbl.curried(name, arity, emit, opts)
    if type(arity) == "function" then opts, emit, arity = emit or {}, arity, nil end
    opts = opts or {}
    return curried_finish(setmetatable({
      __llbl_tag = "Curried",
      name = tostring(name or "form"),
      arity = arity or opts.arity or 1,
      args = {},
      static = {},
      emit = emit,
      emit_meta = opts.emit_meta,
      origin = opts.origin or source.capture("curried", { hint = name }),
    }, Curried), {})
  end
  llbl.curry = llbl.curried
  function llbl.is_curried(v) return is_tag(v, "Curried") end
end
llbl._install_curried_primitives()
llbl._install_curried_primitives = nil
llbl.shared.fragments = llbl.shared.fragments or {
  fragment = llbl.fragment,
  spread = llbl.spread,
  _ = llbl._,
  is_fragment = function(v) return is_tag(v, "Fragment") end,
  is_spread = function(v) return is_tag(v, "Spread") end,
  is_hole = llbl.is_hole,
}

-- Algebra nodes are the generic operator protocol for parserless DSL values.
--
--   a .. b  -> sequence composition
--   a + b   -> sum/choice composition
--   a * b   -> product/conjunction composition
--
-- LLBL owns the shape; roles own the meaning. In a guard role, sum is "or" and
-- product is "and". In a protocol role, sum is alternatives. In a product role,
-- product/sequence can mean field composition. This keeps operators algebraic
-- instead of hard-wiring boolean or backend-specific semantics into Lua syntax.
llbl.Algebra = {}
llbl.Algebra.__index = llbl.Algebra

llbl._algebra_op_name = {
  [".."] = "sequence",
  ["+"] = "sum",
  ["*"] = "product",
  sequence = "sequence",
  sum = "sum",
  product = "product",
}

function llbl._is_algebra(v)
  return is_tag(v, "Algebra")
end

function llbl._algebra_items_for(op, v)
  if llbl._is_algebra(v) and v.op == op then return v.items or {} end
  return { v }
end

function llbl.algebra(op, a, b, origin)
  op = llbl._algebra_op_name[op] or tostring(op)
  if op ~= "sequence" and op ~= "sum" and op ~= "product" then
    llbl.fail("unknown LLBL algebra operator " .. tostring(op), {
      code = "E_BAD_ALGEBRA_OPERATOR",
      primary = origin_of(a) or origin_of(b) or origin,
    }, 2)
  end
  local items = {}
  append(items, llbl._algebra_items_for(op, a))
  append(items, llbl._algebra_items_for(op, b))
  return setmetatable({
    __llbl_tag = "Algebra",
    op = op,
    items = items,
    origin = origin or origin_of(a) or origin_of(b) or source.capture("algebra", { hint = op }),
  }, llbl.Algebra)
end

function llbl.is_algebra(v, op)
  return llbl._is_algebra(v) and (op == nil or v.op == op)
end

function llbl.algebra_items(v)
  if not llbl._is_algebra(v) then return nil end
  return array_copy(v.items or {})
end

function llbl.enable_algebra(mt, opts)
  opts = opts or {}
  if type(mt) ~= "table" then llbl.fail("llbl.enable_algebra expects a metatable", { code = "E_BAD_ALGEBRA_TARGET" }) end
  if opts.concat ~= false and mt.__concat == nil then mt.__concat = function(a, b) return llbl.algebra("sequence", a, b) end end
  if opts.sum ~= false and mt.__add == nil then mt.__add = function(a, b) return llbl.algebra("sum", a, b) end end
  if opts.product ~= false and mt.__mul == nil then mt.__mul = function(a, b) return llbl.algebra("product", a, b) end end
  return mt
end

llbl.Algebra.__concat = function(a, b) return llbl.algebra("sequence", a, b) end
llbl.Algebra.__add = function(a, b) return llbl.algebra("sum", a, b) end
llbl.Algebra.__mul = function(a, b) return llbl.algebra("product", a, b) end
llbl.Algebra.__len = function(self) return #(self.items or {}) end
llbl.Algebra.__tostring = function(self) return "llbl.algebra(" .. tostring(self.op) .. ", " .. tostring(#(self.items or {})) .. ")" end


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
    dialect = rawget(f, "dialect"),
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
        llbl.fail("duplicate " .. what .. " '" .. tostring(name) .. "' in fragment algebra", {
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
    llbl.fail("operator " .. op .. " expects LLBL fragments, got " .. repr(v), {
      code = "E_FRAGMENT_OPERATOR",
      primary = origin_of(v),
    }, 2)
  end
end

function llbl.concat(a, b)
  assert_fragment(a, ".."); assert_fragment(b, "..")
  if a.role ~= b.role then
    llbl.fail("cannot concatenate " .. tostring(a.role) .. " fragment with " .. tostring(b.role) .. " fragment", {
      code = "E_CONCAT_ROLE_MISMATCH",
      primary = origin_of(b) or b.origin,
      labels = { { origin = origin_of(a) or a.origin, message = "left fragment role is " .. tostring(a.role) } },
    }, 2)
  end
  local algebra = fragment_algebra(a)
  if algebra ~= "product" and algebra ~= "list" and algebra ~= "array" then
    llbl.fail("operator .. is not valid for " .. tostring(algebra) .. " fragment role " .. tostring(a.role), {
      code = "E_BAD_FRAGMENT_OPERATOR",
      primary = origin_of(a) or a.origin,
    }, 2)
  end
  local items = array_copy(a.items)
  append(items, b.items)
  if algebra == "product" then check_unique(items, "field", origin_of(b) or b.origin) end
  return fragment_like(a, items, origin_of(a) or a.origin)
end

function llbl.choice(a, b)
  assert_fragment(a, "+"); assert_fragment(b, "+")
  if a.role ~= b.role then
    llbl.fail("cannot compose " .. tostring(a.role) .. " alternatives with " .. tostring(b.role) .. " alternatives", {
      code = "E_CHOICE_ROLE_MISMATCH",
      primary = origin_of(b) or b.origin,
      labels = { { origin = origin_of(a) or a.origin, message = "left fragment role is " .. tostring(a.role) } },
    }, 2)
  end
  local algebra = fragment_algebra(a)
  if algebra ~= "sum" and algebra ~= "protocol" then
    llbl.fail("operator + is only valid for sum/protocol fragments, got " .. tostring(algebra) .. " role " .. tostring(a.role), {
      code = "E_BAD_FRAGMENT_OPERATOR",
      primary = origin_of(a) or a.origin,
    }, 2)
  end
  local items = array_copy(a.items)
  append(items, b.items)
  check_unique(items, "variant", origin_of(b) or b.origin)
  return fragment_like(a, items, origin_of(a) or a.origin)
end

function llbl.decorate(sum, product)
  assert_fragment(sum, "*"); assert_fragment(product, "*")
  local sa, pa = fragment_algebra(sum), fragment_algebra(product)
  if not ((sa == "sum" or sa == "protocol") and pa == "product") then
    llbl.fail("operator * expects sum/protocol fragment and product fragment", {
      code = "E_DECORATE_ROLE_MISMATCH",
      primary = origin_of(product) or product.origin,
      labels = { { origin = origin_of(sum) or sum.origin, message = "left algebra is " .. tostring(sa) } },
    }, 2)
  end
  local items = {}
  for i = 1, #(sum.items or {}) do items[i] = decorate_variant(sum.items[i], product) end
  return fragment_like(sum, items, origin_of(sum) or sum.origin)
end

Fragment.__concat = function(a, b) return llbl.concat(a, b) end
Fragment.__add = function(a, b) return llbl.choice(a, b) end
Fragment.__mul = function(a, b)
  assert_fragment(a, "*"); assert_fragment(b, "*")
  local aa, ba = fragment_algebra(a), fragment_algebra(b)
  if (aa == "sum" or aa == "protocol") and ba == "product" then return llbl.decorate(a, b) end
  if aa == "product" and (ba == "sum" or ba == "protocol") then return llbl.decorate(b, a) end
  llbl.fail("operator * expects product * sum or sum * product fragments", {
    code = "E_DECORATE_ROLE_MISMATCH",
    primary = origin_of(b) or b.origin,
  }, 2)
end
Fragment.__len = function(self) return #(self.items or {}) end
Fragment.__tostring = function(self) return "llbl.fragment(" .. tostring(self.role) .. ", " .. tostring(#(self.items or {})) .. ")" end
function Fragment:describe() return llbl.describe_fragment(self) end
function Fragment:format(opts) return llbl.format(self, opts) end

local Zone = {}; Zone.__index = Zone
local LanguageBundle = {}; LanguageBundle.__index = LanguageBundle

-- Zones are semantic partitions inside a language value. They are not scopes and
-- do not mutate environments. They answer: "these items belong to this language
-- member dialect."
--
--   lalin { ... }  -> Zone(member="lalin.dsl")
--   llpvm    { ... }  -> Zone(member="llpvm.dsl")
--
-- Same-zone concatenation appends items. Mixed-zone concatenation creates a
-- LanguageBundle.
local function zone_items(value)
  if value == nil then return {} end
  if is_tag(value, "Fragment") then return array_copy(value.items or {}) end
  if is_tag(value, "Spread") then return zone_items(value.value) end
  if type(value) == "table" then
    local out = {}
    for i = 1, #value do
      local item = value[i]
      if is_tag(item, "Fragment") or is_tag(item, "Spread") then append(out, zone_items(item))
      else out[#out + 1] = item end
    end
    return out
  end
  return { value }
end

function llbl.zone(spec)
  spec = spec or {}
  local items = zone_items(spec.items or spec.body or {})
  local z = {
    __llbl_tag = "Zone",
    language = tostring(spec.language or ""),
    member = tostring(spec.member or spec.dialect or spec.name or ""),
    name = tostring(spec.name or spec.member or spec.dialect or ""),
    role = tostring(spec.role or "items"),
    items = items,
    metadata = spec.metadata,
    origin = spec.origin or source.capture("zone", { hint = spec.name or spec.member or spec.dialect }),
  }
  for i = 1, #items do z[i] = items[i] end
  return setmetatable(z, Zone)
end

local ZoneHead = {}; ZoneHead.__index = ZoneHead

function llbl.zone_head(spec)
  spec = shallow_copy(spec or {})
  return setmetatable({
    __llbl_tag = "ZoneHead",
    language = tostring(spec.language or ""),
    member = tostring(spec.member or spec.dialect or spec.name or ""),
    name = tostring(spec.name or spec.member or spec.dialect or ""),
    role = tostring(spec.role or "items"),
    metadata = spec.metadata,
    origin = spec.origin or source.capture("zone-head", { hint = spec.name or spec.member or spec.dialect }),
  }, ZoneHead)
end

function ZoneHead:__call(body)
  return llbl.zone {
    language = self.language,
    member = self.member,
    name = self.name,
    role = self.role,
    items = zone_items(body),
    metadata = self.metadata,
    origin = source.capture("zone", { hint = self.name }),
  }
end

function llbl.language_bundle(spec)
  if type(spec) ~= "table" or spec.__llbl_tag == "Zone" then spec = { zones = { spec } } end
  local zones = {}
  for i, z in ipairs(spec.zones or spec) do
    if not is_tag(z, "Zone") then
      llbl.fail("language bundle expects LLBL zones, got " .. repr(z), {
        code = "E_LANGUAGE_BUNDLE_ZONE",
        primary = origin_of(z),
      }, 2)
    end
    zones[#zones + 1] = z
  end
  local b = {
    __llbl_tag = "LanguageBundle",
    language = spec.language,
    zones = zones,
    origin = spec.origin or source.capture("language-bundle", { hint = spec.language or "bundle" }),
  }
  for i = 1, #zones do b[i] = zones[i] end
  return setmetatable(b, LanguageBundle)
end

local function bundle_parts(v)
  if is_tag(v, "Zone") then return { v } end
  if is_tag(v, "LanguageBundle") then return array_copy(v.zones or {}) end
  llbl.fail("language-zone composition expects zones or bundles, got " .. repr(v), {
    code = "E_ZONE_OPERATOR",
    primary = origin_of(v),
  }, 2)
end

local function same_zone(a, b)
  return a.language == b.language and a.member == b.member and a.role == b.role and a.name == b.name
end

function llbl.zone_concat(a, b)
  local az, bz = bundle_parts(a), bundle_parts(b)
  if #az == 1 and #bz == 1 and same_zone(az[1], bz[1]) then
    local items = array_copy(az[1].items or {})
    append(items, bz[1].items or {})
    return llbl.zone {
      language = az[1].language,
      member = az[1].member,
      name = az[1].name,
      role = az[1].role,
      items = items,
      metadata = az[1].metadata,
      origin = origin_of(a) or az[1].origin,
    }
  end
  local zones = {}
  append(zones, az)
  append(zones, bz)
  local language = nil
  for _, z in ipairs(zones) do
    if language == nil then language = z.language
    elseif z.language ~= language then language = "mixed" end
  end
  return llbl.language_bundle { language = language, zones = zones, origin = origin_of(a) or origin_of(b) }
end

Zone.__concat = function(a, b) return llbl.zone_concat(a, b) end
LanguageBundle.__concat = function(a, b) return llbl.zone_concat(a, b) end
Zone.__len = function(self) return #(self.items or {}) end
LanguageBundle.__len = function(self) return #(self.zones or {}) end
Zone.__tostring = function(self) return "llbl.zone(" .. tostring(self.name) .. ", " .. tostring(#(self.items or {})) .. ")" end
LanguageBundle.__tostring = function(self) return "llbl.language_bundle(" .. tostring(#(self.zones or {})) .. ")" end
function Zone:describe() return llbl.describe_zone(self) end
function LanguageBundle:describe() return llbl.describe_language_bundle(self) end

llbl.protocol("fragment", {
  operators = {
    concat = llbl.concat,
    choice = llbl.choice,
    decorate = llbl.decorate,
    len = Fragment.__len,
    tostring = Fragment.__tostring,
  },
})

local ExprCtor, ExprCtorStage = {}, {}
ExprCtor.__index = function(self, key)
  return setmetatable({ __llbl_tag = "ExprCtorStage", name = self.name, indexed = { key }, origin = source.capture("expr-ctor-index", { hint = self.name }) }, ExprCtorStage)
end
ExprCtor.__call = function(self, ...)
  return expr("ctor", { name = self.name, indexed = {}, args = pack(...), hint = self.name })
end
ExprCtorStage.__index = function(self, key)
  local indexed = array_copy(self.indexed); indexed[#indexed + 1] = key
  return setmetatable({ __llbl_tag = "ExprCtorStage", name = self.name, indexed = indexed, origin = self.origin }, ExprCtorStage)
end
ExprCtorStage.__call = function(self, ...)
  return expr("ctor", { name = self.name, indexed = self.indexed, args = pack(...), hint = self.name })
end
function llbl.expr_ctor(name)
  return setmetatable({ __llbl_tag = "ExprCtor", name = tostring(name) }, ExprCtor)
end

local DEFAULT_EXPORTS = {
  eq = llbl.curried("eq", 2, function(a, b) return expr("binop", { op = "==", a = a, b = b }) end),
  ne = llbl.curried("ne", 2, function(a, b) return expr("binop", { op = "~=", a = a, b = b }) end),
  lt = llbl.curried("lt", 2, function(a, b) return expr("binop", { op = "<", a = a, b = b }) end),
  le = llbl.curried("le", 2, function(a, b) return expr("binop", { op = "<=", a = a, b = b }) end),
  gt = llbl.curried("gt", 2, function(a, b) return expr("binop", { op = ">", a = a, b = b }) end),
  ge = llbl.curried("ge", 2, function(a, b) return expr("binop", { op = ">=", a = a, b = b }) end),
  And = llbl.curried("And", 2, function(a, b) return call_expr(llbl.symbol("And"), pack(a, b)) end),
  Or = llbl.curried("Or", 2, function(a, b) return call_expr(llbl.symbol("Or"), pack(a, b)) end),
  Not = llbl.curried("Not", 1, function(a) return call_expr(llbl.symbol("Not"), pack(a)) end),
  select = llbl.curried("select", 3, function(c, a, b) return call_expr(llbl.symbol("select"), pack(c, a, b)) end),
  as = llbl.expr_ctor("as"),
  bitcast = llbl.expr_ctor("bitcast"),
  null = llbl.expr_ctor("null"),
  sizeof = llbl.expr_ctor("sizeof"),
  alignof = llbl.expr_ctor("alignof"),
}
DEFAULT_EXPORTS.land = DEFAULT_EXPORTS.And
DEFAULT_EXPORTS.lor = DEFAULT_EXPORTS.Or

-- ---------------------------------------------------------------------------
-- Grammar bootstrap DSL
-- ---------------------------------------------------------------------------
--
-- The grammar API is itself an LLBL-style DSL. It builds declarations such as:
--
--   g.role .decls { kind = "array" }
--   g.head .fn { g.slot .name [g.name], ... }
--
-- The declarations are later compiled by llbl.dialect into runtime heads.

local boot_node
local RoleRef = {}; RoleRef.__index = RoleRef
local function role_ref(name) return setmetatable({ __llbl_tag = "RoleRef", name = tostring(name) }, RoleRef) end

local TraitRef = {}; TraitRef.__index = TraitRef
TraitRef.__call = function(self, spec)
  return boot_node("TraitDecl", { name = self.name, spec = spec or {}, origin = self.origin })
end
local function trait_ref(name) return setmetatable({ __llbl_tag = "TraitRef", name = tostring(name), origin = source.capture("grammar:trait", { hint = name }) }, TraitRef) end

local ProtocolRef = {}; ProtocolRef.__index = ProtocolRef
ProtocolRef.__call = function(self, spec)
  spec = spec or {}
  return boot_node("ProtocolDecl", { name = self.name, spec = spec, origin = self.origin })
end
local function protocol_ref(name) return setmetatable({ __llbl_tag = "ProtocolRef", name = tostring(name), origin = source.capture("grammar:protocol", { hint = name }) }, ProtocolRef) end

local BootNode = {}; BootNode.__index = BootNode
BootNode.__call = function(self, attrs)
  attrs = attrs or {}
  if type(attrs) ~= "table" then llbl.fail("grammar attributes must be a table", { primary = self.origin }) end
  local spec = rawget(self, "spec") or {}
  for k, v in pairs(attrs) do self[k] = v; spec[k] = v end
  self.spec = spec
  return self
end

function boot_node(tag, fields)
  fields = fields or {}; fields.__llbl_tag = tag; fields.origin = fields.origin or source.capture("grammar:" .. tag)
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
    local slots, traits = {}, {}
    for i = 1, #body do
      if is_tag(body[i], "SlotDecl") then slots[#slots + 1] = body[i]
      elseif is_tag(body[i], "TraitRef") or is_tag(body[i], "TraitDecl") then traits[#traits + 1] = body[i]
      else llbl.fail("head bodies accept slot declarations and trait refs", { primary = origin_of(body[i]) or self.origin }) end
    end
    return boot_node("HeadDecl", { name = self.name, slots = slots, traits = traits, tag = body.tag or self.name, emit = body.emit or body.build, check = body.check, lower = body.lower, lsp = body.lsp, format = body.format, spec = body, origin = self.origin })
  elseif self.kind == "phase" then
    return boot_node("PassDecl", { name = self.name, run = body.run or body[1], spec = body, origin = self.origin, phase = true })
  elseif self.kind == "pass" then
    return boot_node("PassDecl", { name = self.name, run = body.run or body[1], spec = body, origin = self.origin })
  elseif self.kind == "lsp" then
    return boot_node("LspDecl", { name = self.name, spec = body, origin = self.origin })
  elseif self.kind == "scalar" then
    return boot_node("ScalarDecl", { name = self.name, spec = body, origin = self.origin })
  end
  llbl.fail("unknown grammar kind " .. tostring(self.kind), { primary = self.origin })
end

local BootHead = {}
BootHead.__index = function(self, key)
  if self.kind == "scalar" then return boot_node("ScalarDecl", { name = tostring(key), spec = {}, origin = source.capture("grammar:scalar", { hint = key }) }) end
  if self.kind == "trait" then return trait_ref(key) end
  if self.kind == "protocol" then return protocol_ref(key) end
  return setmetatable({ __llbl_tag = "BootStage", kind = self.kind, name = tostring(key), origin = source.capture("grammar:" .. self.kind, { hint = key }) }, BootStage)
end
local function boot_head(kind) return setmetatable({ __llbl_tag = "BootHead", kind = kind }, BootHead) end

llbl.grammar = setmetatable({
  role = boot_head("role"), head = boot_head("head"), slot = boot_head("slot"), scalar = boot_head("scalar"),
  type_ctor = boot_head("type_ctor"), helper = boot_head("helper"), pass = boot_head("pass"), phase = boot_head("phase"), lsp = boot_head("lsp"),
  trait = boot_head("trait"), protocol = boot_head("protocol"),
  type_system = function(spec) return boot_node("TypeSystemDecl", { spec = spec or {}, origin = source.capture("grammar:type-system") }) end,
}, { __index = function(_, key) return role_ref(key) end })

-- ---------------------------------------------------------------------------
-- Normalization
-- ---------------------------------------------------------------------------
--
-- Normalization is where raw Lua values become dialect meaning. Slots decide
-- which channel they accept; roles decide how to interpret the value delivered
-- through that channel. This is the central replacement for parser productions.

local normalize_role, normalize_expr, role_region, collect_role, spread_region

local function norm_name(ctx, v)
  if is_tag(v, "Name") then return v end
  if is_tag(v, "Symbol") then return llbl.name(v.text, { origin = v.origin }) end
  if type(v) == "string" or type(v) == "number" then return llbl.name(v, { computed = true, origin = ctx and ctx.origin }) end
  llbl.fail("expected name, got " .. repr(v), { primary = origin_of(v) or (ctx and ctx.origin), code = "E_EXPECTED_NAME" })
end

local function norm_type(ctx, v)
  if llbl.is_type_like(v) then return v end
  if is_tag(v, "Symbol") then return llbl.type(v.text, { kind = "named", origin = v.origin }) end
  if type(v) == "string" then return llbl.type(v, { kind = "named", origin = ctx and ctx.origin }) end
  llbl.fail("expected type, got " .. repr(v), { primary = origin_of(v) or (ctx and ctx.origin), code = "E_EXPECTED_TYPE" })
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
    llbl.fail("unknown expression kind " .. tostring(v.kind), { primary = v.origin, code = "E_BAD_EXPR" })
  end
  if tv == "number" or tv == "string" or tv == "boolean" then return node("expr", { expr_kind = "literal", value = v, literal_type = tv }, ctx and ctx.origin) end
  if tv == "table" then
    local arr, rec = {}, {}
    for i = 1, #v do arr[i] = normalize_expr(ctx, v[i]) end
    for k, x in pairs(v) do if type(k) ~= "number" then rec[k] = normalize_expr(ctx, x) end end
    return node("expr", { expr_kind = "table", array = arr, record = rec }, origin_of(v) or (ctx and ctx.origin))
  end
  llbl.fail("expected expression, got " .. repr(v), { primary = origin_of(v) or (ctx and ctx.origin), code = "E_EXPECTED_EXPR" })
end

local normalize_role_reflective

local role_ops = (function()
local function role_context(ctx, role_name, spec)
  local subctx = shallow_copy(ctx or {})
  subctx.role = role_name
  subctx.role_spec = spec
  return subctx
end

local function gps_single_value(gen, param, state)
  local r = pack(gen(param, state))
  if r[1] == nil then return nil end
  return r[2]
end

local function append_gps_payloads(out, n, gen, param, state)
  gen, param, state = llbl.gps.raw(gen, param, state)
  while true do
    local r = pack(gen(param, state))
    if r[1] == nil then return n end
    state = r[1]
    n = n + 1
    out[n] = r[2]
  end
end

local function collect_role_region(kind, gen, param, state)
  if kind == "record" then return llbl.gps.collect.map(gen, param, state) end
  if kind == "array" or kind == "product" or kind == "sum" or kind == "protocol" then
    return llbl.gps.collect.array(gen, param, state)
  end
  return gps_single_value(gen, param, state)
end

local function ensure_table_for_role(ctx, role_name, code, label, v)
  if type(v) ~= "table" then
    llbl.fail("expected " .. label, { primary = ctx and ctx.origin, code = code, role = role_name })
  end
end

local function role_array_gen(param, state)
  state = state or { source_state = param.source_state }
  while true do
    if state.inner_gen then
      local r = pack(state.inner_gen(state.inner_param, state.inner_state))
      if r[1] ~= nil then
        state.inner_state = r[1]
        return state, r[2]
      end
      state.inner_gen, state.inner_param, state.inner_state = nil, nil, nil
    end

    local next_state, item = param.source_gen(param.source_param, state.source_state)
    if next_state == nil then return nil end
    state.source_state = next_state
    if is_tag(item, "Spread") then
      state.inner_gen, state.inner_param, state.inner_state = spread_region(param.ctx, param.role_name, item)
    elseif param.item_role then
      return state, collect_role(param.ctx, param.item_role, item)
    else
      return state, item
    end
  end
end

local function role_record_gen(param, state)
  state = state or param.source_state
  while true do
    local next_state, k, v = param.source_gen(param.source_param, state)
    if next_state == nil then return nil end
    state = next_state
    if type(k) ~= "number" then
      return state, k, param.value_role and collect_role(param.ctx, param.value_role, v) or v
    end
  end
end

local function check_product_field_unique(param, seen, f)
  if param.unique and seen[f.name] then
    llbl.fail("duplicate product field '" .. tostring(f.name) .. "'", {
      code = "E_DUPLICATE_FIELD",
      primary = f.origin,
      labels = { { origin = seen[f.name].origin, message = "first field is here" } },
    })
  end
  seen[f.name] = f
end

local function role_product_gen(param, state)
  state = state or { source_state = param.source_state, seen = {} }
  while true do
    if state.inner_gen then
      local r = pack(state.inner_gen(state.inner_param, state.inner_state))
      if r[1] ~= nil then
        state.inner_state = r[1]
        local f = r[2]
        check_product_field_unique(param, state.seen, f)
        return state, f
      end
      state.inner_gen, state.inner_param, state.inner_state = nil, nil, nil
    end

    local next_state, item = param.source_gen(param.source_param, state.source_state)
    if next_state == nil then return nil end
    state.source_state = next_state
    if is_tag(item, "Spread") then
      state.inner_gen, state.inner_param, state.inner_state = spread_region(param.ctx, param.role_name, item)
    elseif is_tag(item, "Capture") then
      if not is_tag(item.subject, "Symbol") then llbl.fail("product capture subject must be a symbol", { primary = item.origin }) end
      local f = { tag = "field", name = item.subject.text, type = collect_role(param.ctx, param.type_role, item.value), origin = item.origin }
      check_product_field_unique(param, state.seen, f)
      return state, f
    elseif is_tag(item, "CaptureInit") then
      local c = item.capture
      if not is_tag(c.subject, "Symbol") then llbl.fail("product initializer subject must be a symbol", { primary = item.origin }) end
      local f = { tag = "field", name = c.subject.text, type = collect_role(param.ctx, param.type_role, c.value), init = normalize_expr(param.ctx, item.init), origin = item.origin }
      check_product_field_unique(param, state.seen, f)
      return state, f
    else
      llbl.fail("product entries must be typed names or spreads, got " .. repr(item), {
        primary = origin_of(item) or (param.ctx and param.ctx.origin),
        code = "E_BAD_PRODUCT_ENTRY",
        notes = { "write x [T] for a typed field" },
      })
    end
  end
end

local function check_sum_variant_unique(seen, name, origin)
  if seen[name] then
    llbl.fail("duplicate variant '" .. tostring(name) .. "'", {
      code = "E_DUPLICATE_VARIANT",
      primary = origin,
      labels = { { origin = seen[name], message = "first variant is here" } },
    })
  end
  seen[name] = origin
end

local function role_sum_gen(param, state)
  state = state or { source_state = param.source_state, seen = {} }
  while true do
    if state.inner_gen then
      local r = pack(state.inner_gen(state.inner_param, state.inner_state))
      if r[1] ~= nil then
        state.inner_state = r[1]
        local variant = r[2]
        check_sum_variant_unique(state.seen, variant.name, variant.origin)
        return state, variant
      end
      state.inner_gen, state.inner_param, state.inner_state = nil, nil, nil
    end

    local next_state, item = param.source_gen(param.source_param, state.source_state)
    if next_state == nil then return nil end
    state.source_state = next_state
    if is_tag(item, "Spread") then
      state.inner_gen, state.inner_param, state.inner_state = spread_region(param.ctx, param.role_name, item)
    elseif is_tag(item, "Symbol") or is_tag(item, "Name") then
      check_sum_variant_unique(state.seen, item.text, item.origin)
      return state, { tag = "variant", name = item.text, payload = nil, origin = item.origin }
    elseif is_tag(item, "Expr") and item.kind == "call" and is_tag(item.callee, "Symbol") then
      if (item.args.n or #item.args) ~= 1 or type(item.args[1]) ~= "table" then
        llbl.fail("variant payload must be a single product table", { primary = item.origin })
      end
      check_sum_variant_unique(state.seen, item.callee.text, item.origin)
      return state, { tag = "variant", name = item.callee.text, payload = collect_role(param.ctx, param.payload_role, item.args[1]), origin = item.origin }
    else
      llbl.fail("sum entries must be variants or spreads, got " .. repr(item), {
        primary = origin_of(item) or (param.ctx and param.ctx.origin),
        code = "E_BAD_SUM_ENTRY",
      })
    end
  end
end

local function array_role_region(ctx, role_name, spec, v)
  ensure_table_for_role(ctx, role_name, "E_EXPECTED_TABLE", "table for " .. role_name .. " role", v)
  local gen, param, state = llbl.gps.raw(llbl.gps.from.array(v))
  return llbl.gps.raw(llbl.gps.wrap(role_array_gen, {
    ctx = ctx,
    role_name = role_name,
    item_role = spec.item_role or spec.item,
    source_gen = gen,
    source_param = param,
    source_state = state,
  }, nil, { kind = "role:array", role = role_name }))
end

local function record_role_region(ctx, role_name, spec, v)
  ensure_table_for_role(ctx, role_name, "E_EXPECTED_RECORD", "record table", v)
  local gen, param, state = llbl.gps.raw(llbl.gps.from.record(v))
  return llbl.gps.raw(llbl.gps.wrap(role_record_gen, {
    ctx = ctx,
    role_name = role_name,
    value_role = spec.value_role or spec.value,
    source_gen = gen,
    source_param = param,
    source_state = state,
  }, nil, { kind = "role:record", role = role_name }))
end

local function product_role_region(ctx, role_name, spec, v)
  ensure_table_for_role(ctx, role_name, "E_EXPECTED_PRODUCT", "product table", v)
  local unique = spec.unique_names
  if unique == nil then unique = true end
  local gen, param, state = llbl.gps.raw(llbl.gps.from.array(v))
  return llbl.gps.raw(llbl.gps.wrap(role_product_gen, {
    ctx = ctx,
    role_name = role_name,
    type_role = spec.type_role or "type",
    unique = unique,
    source_gen = gen,
    source_param = param,
    source_state = state,
  }, nil, { kind = "role:product", role = role_name }))
end

local function sum_role_region(ctx, role_name, spec, v)
  ensure_table_for_role(ctx, role_name, "E_EXPECTED_SUM", "sum/protocol table", v)
  local gen, param, state = llbl.gps.raw(llbl.gps.from.array(v))
  return llbl.gps.raw(llbl.gps.wrap(role_sum_gen, {
    ctx = ctx,
    role_name = role_name,
    payload_role = spec.payload_role or "product",
    source_gen = gen,
    source_param = param,
    source_state = state,
  }, nil, { kind = "role:sum", role = role_name }))
end

local function role_region_by_spec(ctx, role_name, spec, v)
  local kind = spec.kind or role_name
  if spec.region then
    if is_tag(spec.region, "Region") then return spec.region:gps(ctx.dialect, ctx, v) end
    llbl.fail("role " .. tostring(role_name) .. " custom region must be an LLBL Region descriptor", {
      code = "E_ROLE_REGION_DESCRIPTOR",
      primary = spec.origin or origin_of(spec.region),
    }, 2)
  end
  if kind == "name" then return llbl.gps.raw(llbl.gps.once(norm_name(ctx, v))) end
  if kind == "type" then return llbl.gps.raw(llbl.gps.once(norm_type(ctx, v))) end
  if kind == "expr" then return llbl.gps.raw(llbl.gps.once(normalize_expr(ctx, v))) end
  if kind == "array" then return array_role_region(ctx, role_name, spec, v) end
  if kind == "record" then return record_role_region(ctx, role_name, spec, v) end
  if kind == "product" then return product_role_region(ctx, role_name, spec, v) end
  if kind == "sum" or kind == "protocol" then return sum_role_region(ctx, role_name, spec, v) end
  if kind == "mixed" then return llbl.gps.raw(llbl.gps.once({
    array = collect_role_region("array", array_role_region(ctx, role_name, spec, v)),
    record = collect_role_region("record", record_role_region(ctx, role_name, spec, v)),
  })) end
  if kind == "string" then
    if type(v) ~= "string" then llbl.fail("expected string", { primary = ctx.origin }) end
    return llbl.gps.raw(llbl.gps.once(v))
  end
  if kind == "number" then
    if type(v) ~= "number" then llbl.fail("expected number", { primary = ctx.origin }) end
    return llbl.gps.raw(llbl.gps.once(v))
  end
  if kind == "boolean" then
    if type(v) ~= "boolean" then llbl.fail("expected boolean", { primary = ctx.origin }) end
    return llbl.gps.raw(llbl.gps.once(v))
  end
  if kind == "value" or kind == "identity" then return llbl.gps.raw(llbl.gps.once(v)) end
  llbl.fail("unknown role kind " .. tostring(kind), { primary = ctx.origin, code = "E_UNKNOWN_ROLE_KIND" })
end

local function role_region_reflective(ctx, role_name, v)
  ctx = ctx or {}
  local lang = ctx.dialect
  local spec = (lang and lang.roles and lang.roles[role_name]) or {}
  return role_region_by_spec(role_context(ctx, role_name, spec), role_name, spec, v)
end

local function collect_role_reflective(ctx, role_name, v)
  ctx = ctx or {}
  local lang = ctx.dialect
  local spec = (lang and lang.roles and lang.roles[role_name]) or {}
  local kind = spec.kind or role_name
  local subctx = role_context(ctx, role_name, spec)
  local out
  if kind == "mixed" and not spec.region then
    out = {
      array = collect_role_region("array", array_role_region(subctx, role_name, spec, v)),
      record = collect_role_region("record", record_role_region(subctx, role_name, spec, v)),
    }
  else
    out = collect_role_region(kind, role_region_by_spec(subctx, role_name, spec, v))
  end
  if spec.check then spec.check(subctx, out, v) end
  return out
end

spread_region = function(ctx, role_name, spread)
  if not is_tag(spread, "Spread") then
    llbl.fail("expected spread value", { primary = origin_of(spread) or (ctx and ctx.origin), code = "E_EXPECTED_SPREAD" })
  end
  local v = spread.value
  if is_tag(v, "Fragment") then
    if v.role ~= role_name then
      llbl.fail("cannot spread " .. tostring(v.role) .. " fragment into " .. tostring(role_name) .. " role", {
        code = "E_SPREAD_ROLE",
        primary = spread.origin,
        labels = { { origin = v.origin, message = "fragment created here as role " .. tostring(v.role) } },
      })
    end
    return llbl.gps.raw(llbl.gps.from.array(v.items or {}))
  end
  if type(v) == "table" then return role_region(ctx, role_name, v) end
  llbl.fail("cannot spread value " .. repr(v), { primary = spread.origin, code = "E_BAD_SPREAD" })
end

local function expand_spread(ctx, role_name, out, spread)
  append_gps_payloads(out, #(out or {}), spread_region(ctx, role_name, spread))
end

local function norm_array(ctx, role_name, spec, v)
  return collect_role_region("array", array_role_region(ctx, role_name, spec, v))
end

local function norm_record(ctx, role_name, spec, v)
  return collect_role_region("record", record_role_region(ctx, role_name, spec, v))
end

local function norm_product(ctx, role_name, spec, v)
  return collect_role_region("product", product_role_region(ctx, role_name, spec, v))
end

local function norm_sum(ctx, role_name, spec, v)
  return collect_role_region(spec.kind or role_name, sum_role_region(ctx, role_name, spec, v))
end

local RoleMachine = {}
RoleMachine.__index = RoleMachine
RoleMachine.__call = function(self, ctx, value) return self.collect(ctx, value) end

local SpreadMachine = {}
SpreadMachine.__index = SpreadMachine
SpreadMachine.__call = function(self, ctx, out, n, spread) return self.append(ctx, out, n, spread) end

local function role_protocol_for_kind(kind)
  kind = tostring(kind or "value")
  if kind == "array" or kind == "record" or kind == "product" or kind == "sum" or kind == "mixed" then
    return "role_items"
  end
  return "role_value"
end

local function compile_spread_expander(lang, role_name, spec)
  spec = spec or {}
  local function region_fn(ctx, spread)
    return spread_region(role_context(ctx, role_name, spec), role_name, spread)
  end
  local function append_fn(ctx, out, n, spread)
    out = out or {}
    n = n or #out
    return append_gps_payloads(out, n, region_fn(ctx, spread))
  end
  local descriptor = llbl.region(tostring(lang.name) .. ".spread." .. tostring(role_name))["role_items"] { "ctx", "spread" } (region_fn)
  descriptor.body_kind = "spread-expander"
  descriptor.origin = spec.origin or descriptor.origin
  if descriptor.materializers.append == nil then
    descriptor:materializer("append", { kind = "append-payloads", body = append_fn, origin = spec.origin })
  end
  local machine = setmetatable({
    __llbl_tag = "SpreadMachine",
    dialect = lang,
    role = role_name,
    role_kind = spec.kind or role_name,
    descriptor = descriptor,
    region = llbl.codegen.register(region_fn, {
      id = tostring(lang.name) .. ".spread." .. tostring(role_name) .. ".region",
      kind = "spread-region",
      dialect = lang.name,
      role = role_name,
      role_kind = spec.kind or role_name,
      mode = "fast",
      origin = spec.origin,
      generated = false,
    }),
    append = llbl.codegen.register(append_fn, {
      id = tostring(lang.name) .. ".spread." .. tostring(role_name) .. ".append",
      kind = "spread-materializer",
      dialect = lang.name,
      role = role_name,
      role_kind = spec.kind or role_name,
      mode = "fast",
      origin = spec.origin,
      generated = false,
    }),
    meta = { dialect = lang.name, role = role_name, role_kind = spec.kind or role_name, origin = spec.origin },
  }, SpreadMachine)
  return llbl.codegen.register(machine, {
    id = tostring(lang.name) .. ".spread." .. tostring(role_name),
    kind = "spread-machine",
    dialect = lang.name,
    role = role_name,
    role_kind = spec.kind or role_name,
    mode = "fast",
    origin = spec.origin,
    generated = false,
  })
end

local function compile_role_region(lang, role_name, spec)
  spec = spec or {}
  return function(ctx, value)
    local subctx = role_context(ctx, role_name, spec)
    subctx.dialect = subctx.dialect or lang
    return role_region_by_spec(subctx, role_name, spec, value)
  end
end

local function compile_role_collector(lang, role_name, spec, region_fn)
  spec = spec or {}
  local kind = spec.kind or role_name
  return function(ctx, value)
    local subctx = role_context(ctx, role_name, spec)
    subctx.dialect = subctx.dialect or lang
    local out
    if kind == "mixed" and not spec.region then
      out = {
        array = collect_role_region("array", array_role_region(subctx, role_name, spec, value)),
        record = collect_role_region("record", record_role_region(subctx, role_name, spec, value)),
      }
    else
      out = collect_role_region(kind, region_fn(subctx, value))
    end
    if spec.check then spec.check(subctx, out, value) end
    return out
  end
end

local function compile_role_normalizer(lang, role_name, spec)
  spec = spec or {}
  local region_fn = compile_role_region(lang, role_name, spec)
  local collect_fn = compile_role_collector(lang, role_name, spec, region_fn)
  local role_kind_name = spec.kind or role_name
  local descriptor
  if is_tag(spec.region, "Region") then
    descriptor = spec.region
    if descriptor.materializers.collect == nil then
      descriptor:materializer("collect", { kind = "role-collector", body = collect_fn, origin = spec.origin })
    end
  else
    descriptor = llbl.role_region(tostring(lang.name) .. ".role." .. tostring(role_name))[role_protocol_for_kind(role_kind_name)] (function(_, ctx, value)
      return region_fn(ctx, value)
    end)
    descriptor.body_kind = "role-normalizer"
    descriptor.origin = spec.origin or descriptor.origin
    if descriptor.materializers.collect == nil then
      descriptor:materializer("collect", { kind = "role-collector", body = collect_fn, origin = spec.origin })
    end
  end
  local machine = setmetatable({
    __llbl_tag = "RoleMachine",
    dialect = lang,
    role = role_name,
    role_kind = role_kind_name,
    descriptor = descriptor,
    region = llbl.codegen.register(region_fn, {
      id = tostring(lang.name) .. ".role." .. tostring(role_name) .. ".region",
      kind = "role-region",
      dialect = lang.name,
      role = role_name,
      role_kind = role_kind_name,
      mode = "fast",
      origin = spec.origin,
      reflective = role_region_reflective,
      generated = false,
    }),
    collect = llbl.codegen.register(collect_fn, {
      id = tostring(lang.name) .. ".role." .. tostring(role_name) .. ".collect",
      kind = "role-materializer",
      dialect = lang.name,
      role = role_name,
      role_kind = role_kind_name,
      mode = "fast",
      origin = spec.origin,
      reflective = normalize_role_reflective,
      generated = false,
    }),
    meta = { dialect = lang.name, role = role_name, role_kind = role_kind_name, origin = spec.origin },
  }, RoleMachine)
  return llbl.codegen.register(machine, {
    id = tostring(lang.name) .. ".role." .. tostring(role_name),
    kind = "role-machine",
    dialect = lang.name,
    role = role_name,
    role_kind = spec.kind or role_name,
    mode = "fast",
    origin = spec.origin,
    reflective = normalize_role_reflective,
    generated = false,
  })
end

return {
  compile_spread_expander = compile_spread_expander,
  compile_role_normalizer = compile_role_normalizer,
  role_region_reflective = role_region_reflective,
  collect_role_reflective = collect_role_reflective,
  spread_region = spread_region,
}
end)()

spread_region = role_ops.spread_region

function llbl.codegen.compile_dialect(lang, opts)
  opts = opts or {}
  local compiled = {
    __llbl_tag = "CompiledDialectRuntime",
    dialect = lang,
    mode = opts.mode or "fast",
    roles = {},
    spreads = {},
    metadata = {
      kind = "gps-codegen",
      diagnostics = "reflective-replay",
      source = "trusted-grammar",
    },
  }
  for role_name, spec in pairs(lang.roles or {}) do
    compiled.spreads[role_name] = role_ops.compile_spread_expander(lang, role_name, spec)
  end
  lang.compiled = compiled
  for role_name, spec in pairs(lang.roles or {}) do
    compiled.roles[role_name] = role_ops.compile_role_normalizer(lang, role_name, spec)
  end
  return compiled
end

normalize_role_reflective = function(ctx, role_name, v)
  return role_ops.collect_role_reflective(ctx, role_name, v)
end

role_region = function(ctx, role_name, v)
  ctx = ctx or {}
  local lang = ctx.dialect
  local compiled = lang and lang.compiled
  local role_machine = compiled and compiled.roles and compiled.roles[role_name]
  if role_machine and role_machine.region and ctx.codegen ~= false and ctx.reflective ~= true then
    return role_machine.region(ctx, v)
  end
  return role_ops.role_region_reflective(ctx, role_name, v)
end

collect_role = function(ctx, role_name, v)
  ctx = ctx or {}
  local lang = ctx.dialect
  local compiled = lang and lang.compiled
  local role_machine = compiled and compiled.roles and compiled.roles[role_name]
  if role_machine and role_machine.collect and ctx.codegen ~= false and ctx.reflective ~= true then
    return role_machine.collect(ctx, v)
  end
  return role_ops.collect_role_reflective(ctx, role_name, v)
end

normalize_role = collect_role
llbl.role_gps = role_region
llbl.collect_role = collect_role
llbl.spread_region = spread_region
llbl.normalize_role, llbl.normalize_expr = normalize_role, normalize_expr

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

function llbl.is_stage(v) return is_tag(v, "Stage") end
function llbl.stage_head(v) if is_tag(v, "Stage") and v.head then return v.head.name end; return nil end
function llbl.stage_missing_slots(v) return stage_missing_slots(v) end
function llbl.is_complete(v) return not is_tag(v, "Stage") or #stage_missing_slots(v) == 0 end

-- ---------------------------------------------------------------------------
-- Runtime heads
-- ---------------------------------------------------------------------------
--
-- Runtime heads are staged constructors. A head consumes Lua channels in order:
--
--   fn. add      -> index:name
--   { ... }      -> call:table
--   [i32]        -> index:type
--
-- When all required slots are filled, the head emits the normalized dialect
-- value. If optional slots remain, the incomplete stage is intentionally useful
-- for headers and progressive object construction.

local RuntimeHead, RuntimeStage = {}, {}
local function role_kind(lang, role) local s = lang.roles[role]; return (s and s.kind) or role end
local function slot_channels(lang, slot)
  if slot.channels then return slot.channels end
  if slot.channel then return { slot.channel } end
  local k = role_kind(lang, slot.role)
  if k == "name" then return { llbl.channel.index_name } end
  if k == "type" then return { llbl.channel.index_type } end
  if k == "string" or k == "number" or k == "boolean" then return { llbl.channel.call_value } end
  if k == "array" or k == "record" or k == "mixed" or k == "product" or k == "sum" or k == "protocol" then return { llbl.channel.call_table } end
  if k == "expr" or k == "value" or k == "identity" then return { "call:any" } end
  return { "call:any" }
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
      local ca, cb = slot_channels(lang, a), slot_channels(lang, b)
      local overlap
      for ai = 1, #ca do for bi = 1, #cb do if channels_overlap(ca[ai], cb[bi]) then overlap = ca[ai] == cb[bi] and ca[ai] or "call" end end end
      if overlap then
        llbl.fail("ambiguous optional slot sequence in head " .. tostring(head_name) .. ": slot " .. tostring(a.name) .. " [" .. tostring(a.role) .. "] and slot " .. tostring(b.name) .. " [" .. tostring(b.role) .. "] can both consume " .. tostring(overlap) .. " input", {
          code = "E_AMBIGUOUS_OPTIONAL_SLOTS",
          primary = b.origin or a.origin,
          labels = { { origin = a.origin, message = "first optional slot is here" } },
          notes = { "LLBL consumes slots greedily with no backtracking; adjacent optional slots must use disjoint syntactic channels." },
        }, 2)
      end
    end
  end
end
local function type_slot(lang, slot, value) return role_kind(lang, slot.role) == "type" and (llbl.is_type_like(value) or is_tag(value, "Symbol") or type(value) == "string") end
local function event_channel_fits(lang, slot, event)
  local channels = slot_channels(lang, slot)
  for i = 1, #channels do
    if channels_overlap(channels[i], event.channel) then return true end
  end
  return false
end
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
local function event_fits(lang, slot, event)
  if (slot.channels or slot.channel) and (role_kind(lang, slot.role) == "value" or role_kind(lang, slot.role) == "identity") then
    return event_channel_fits(lang, slot, event)
  end
  return event_channel_fits(lang, slot, event) and action_fits(lang, slot, event.action, event.value, event.argc or 0)
end
local function channel_for_action(action, value, argc)
  if action == "name" then return llbl.channel.index_name end
  if action == "index" then
    if llbl.is_type_like(value) or is_tag(value, "Symbol") or type(value) == "string" then return llbl.channel.index_type end
    return llbl.channel.index_value
  end
  if action == "call" then
    if argc == 0 then return llbl.channel.call_none end
    if argc and argc > 1 then return llbl.channel.call_many end
    if type(value) == "table" then return llbl.channel.call_table end
    return llbl.channel.call_value
  end
  return action
end
local function slot_channel_label(lang, slot)
  local channels = slot_channels(lang, slot)
  return table.concat(channels, "|")
end
local function remaining_optional(slots, i) for j = i, #slots do if not slots[j].optional then return false end end; return true end

local function stage_origin_from_value(value, fallback)
  if type(value) == "table" then
    return rawget(value, "__llbl_origin") or rawget(value, "origin") or origin_of(value) or fallback
  end
  return fallback
end

function llbl.at(origin, value)
  if type(value) == "table" then
    rawset(value, "__llbl_origin", origin)
    if rawget(value, "origin") == nil then rawset(value, "origin", origin) end
    local m = rawget(value, "__llbl")
    if m and m.origin == nil then m.origin = origin end
    return value
  end
  return { __llbl_tag = "OriginValue", value = value, __llbl_origin = origin, origin = origin }
end

local function unwrap_origin_value(v)
  if is_tag(v, "OriginValue") then return v.value, v.__llbl_origin or v.origin end
  return v, stage_origin_from_value(v)
end

local function normalize_stage_slots(stage)
  local fields, origins = {}, {}
  for i = 1, #stage.head.slots do
    local slot = stage.head.slots[i]
    if stage.seen[slot.name] then
      local raw = stage.raw[slot.name]
      local event = stage.events and stage.events[slot.name]
      origins[slot.name] = child_origin(stage.origins[slot.name], {
        kind = "slot-consume",
        consumed_by = {
          head = stage.head.name,
          slot = slot.name,
          role = slot.role,
          channel = event and event.channel or nil,
        },
      })
      fields[slot.name] = collect_role({ dialect = stage.dialect, head = stage.head.name, slot = slot, event = event, origin = origins[slot.name] }, slot.role, raw)
    elseif slot.optional then
      fields[slot.name] = slot.default
    else
      llbl.fail("missing slot " .. tostring(slot.name), { primary = stage.origin, code = "E_MISSING_SLOT" })
    end
  end
  return fields, origins
end

local function build_stage(stage)
  local fields, origins = normalize_stage_slots(stage)
  fields.origin = fields.origin or stage.origin
  fields.slot_origins = origins
  local out = stage.head.emit and stage.head.emit(fields, stage.dialect, { head = stage.head, raw = stage.raw, origins = origins, events = stage.events, stage = stage }) or { tag = stage.head.tag or stage.head.name, fields = fields }
  return attach_node_meta(out, stage.head.tag or stage.head.name, { dialect = stage.dialect.name, head = stage.head.name, head_spec = stage.head, fields = fields, slot_origins = origins, raw = stage.raw, events = stage.events, origin = stage.origin })
end
local function maybe_finish(stage) if remaining_optional(stage.head.slots, stage.next_index) then return build_stage(stage) end; return stage end
local function consume_event(stage, event)
  local value = event.value
  local origin = event.origin
  local slots, i = stage.head.slots, stage.next_index
  while i <= #slots do
    local slot = slots[i]
    if event_fits(stage.dialect, slot, event) then
      local ns = setmetatable({ __llbl_tag = "Stage", dialect = stage.dialect, head = stage.head, raw = shallow_copy(stage.raw), origins = shallow_copy(stage.origins), events = shallow_copy(stage.events), seen = shallow_copy(stage.seen), next_index = i + 1, origin = stage.origin }, RuntimeStage)
      ns.raw[slot.name], ns.origins[slot.name], ns.events[slot.name], ns.seen[slot.name] = value, origin or stage.origin, event, true
      return maybe_finish(ns)
    elseif slot.optional then i = i + 1
    else
      llbl.fail("expected slot " .. tostring(slot.name) .. " [" .. tostring(slot.role) .. "] via " .. slot_channel_label(stage.dialect, slot) .. ", got " .. event_label(event), {
        primary = origin or stage.origin,
        code = "E_BAD_SLOT",
        event = event,
        slot = slot,
        role = slot.role,
        head = stage.head,
      })
    end
  end
  llbl.fail("too many arguments for head " .. tostring(stage.head.name) .. ", got " .. event_label(event), { primary = origin or stage.origin, code = "E_TOO_MANY_ARGUMENTS", event = event, head = stage.head })
end
local function consume(stage, action, value, argc, origin)
  local override_origin
  value, override_origin = unwrap_origin_value(value)
  origin = override_origin or origin
  return consume_event(stage, llbl.event(channel_for_action(action, value, argc or 0), value, {
    action = action,
    argc = argc or 0,
    origin = origin or stage.origin,
  }))
end
local function head_origin(h)
  return rawget(h, "origin") or source.capture("head", { hint = h.spec.name })
end
local function start_stage(h) return setmetatable({ __llbl_tag = "Stage", dialect = h.dialect, head = h.spec, raw = {}, origins = {}, events = {}, seen = {}, next_index = 1, origin = head_origin(h) }, RuntimeStage) end
local function head_event_region_gen(param, state)
  state = state or { stage = param.start(), source_state = param.source_state }
  if state.done then return nil end
  while true do
    local next_state, event = param.source_gen(param.source_param, state.source_state)
    if next_state == nil then
      local out = param.finish(state.stage)
      state.done = true
      return state, out
    end
    state.source_state = next_state
    local out = param.consume(state.stage, event)
    if is_tag(out, "Stage") then
      state.stage = out
    else
      state.done = true
      return state, out
    end
  end
end
local function head_event_region(head, events, param, state, start_fn, consume_fn, finish_fn, kind)
  local gen, p0, s0 = llbl.gps.raw(events, param, state)
  return llbl.gps.raw(llbl.gps.wrap(head_event_region_gen, {
    head = head,
    source_gen = gen,
    source_param = p0,
    source_state = s0,
    start = function() return start_fn(head) end,
    consume = consume_fn,
    finish = finish_fn,
  }, nil, { kind = kind or "head:events", head = head.spec and head.spec.name }))
end
RuntimeHead.__index = function(self, key)
  if RuntimeHead[key] then return RuntimeHead[key] end
  local o = source.capture("head-name", { hint = key })
  local name_value, override_origin = unwrap_origin_value(key)
  o = override_origin or o
  if is_tag(name_value, "Name") then
    return consume(start_stage(self), "name", name_value, 1, o)
  end
  if is_tag(name_value, "Symbol") then
    return consume(start_stage(self), "name", llbl.name(name_value.text, { origin = o }), 1, o)
  end
  return consume(start_stage(self), "name", llbl.name(name_value, { origin = o }), 1, o)
end
RuntimeHead.__call = function(self, ...)
  local p, o = pack(...), source.capture("head-call", { hint = self.spec.name })
  if p.n > 0 and is_tag(p[1], "OriginValue") then o = p[1].__llbl_origin or p[1].origin or o end
  if p.n == 0 and #self.spec.slots == 0 then return build_stage(setmetatable({ __llbl_tag = "Stage", dialect = self.dialect, head = self.spec, raw = {}, origins = {}, events = {}, seen = {}, next_index = 1, origin = o }, RuntimeStage)) end
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
  local h = setmetatable({ __llbl_tag = "Head", dialect = self.head.dialect, spec = self.head.spec, origin = self.origin }, RuntimeHead)
  return RuntimeHead.__index(h, key)
end
HeadAt.__call = function(self, ...)
  local h = setmetatable({ __llbl_tag = "Head", dialect = self.head.dialect, spec = self.head.spec, origin = self.origin }, RuntimeHead)
  return RuntimeHead.__call(h, ...)
end

function RuntimeHead:at(origin)
  return setmetatable({ __llbl_tag = "HeadAt", head = self, origin = origin }, HeadAt)
end

function RuntimeHead:event_region(events, param, state)
  return head_event_region(self, events, param, state, start_stage, consume_event, build_stage, "head:reflective")
end

function RuntimeHead:collect_events(events, param, state)
  local gen, p0, s0 = self:event_region(events, param, state)
  local next_state, value = gen(p0, s0)
  if next_state == nil then return nil end
  return value
end

function llbl.head_event_region(head, events, param, state)
  if type(head) == "table" and type(head.event_region) == "function" then
    return head:event_region(events, param, state)
  end
  llbl.fail("llbl.head_event_region expects an LLBL head", { primary = origin_of(head), code = "E_EXPECTED_HEAD" }, 2)
end

function llbl.collect_head_events(head, events, param, state)
  if type(head) == "table" and type(head.collect_events) == "function" then
    return head:collect_events(events, param, state)
  end
  llbl.fail("llbl.collect_head_events expects an LLBL head", { primary = origin_of(head), code = "E_EXPECTED_HEAD" }, 2)
end

local function runtime_head(lang, spec) return setmetatable({ __llbl_tag = "Head", dialect = lang, spec = spec }, RuntimeHead) end

local function install_head_codegen()
local CompiledHead, CompiledStage = {}, {}

local function compiled_stage_origin(h)
  return rawget(h, "origin") or source.capture("head", { hint = h.spec.name })
end

local function compiled_build_stage(stage)
  local fields, origins = {}, {}
  for i = 1, #stage.head.slots do
    local slot = stage.head.slots[i]
    if stage.seen[slot.name] then
      local raw = stage.raw[slot.name]
      local event = stage.events and stage.events[slot.name]
      origins[slot.name] = child_origin(stage.origins[slot.name], {
        kind = "slot-consume",
        consumed_by = {
          head = stage.head.name,
          slot = slot.name,
          role = slot.role,
          channel = event and event.channel or nil,
        },
      })
      local role_machine = stage.compiled.roles and stage.compiled.roles[slot.role]
      local ctx = { dialect = stage.dialect, head = stage.head.name, slot = slot, event = event, origin = origins[slot.name] }
      fields[slot.name] = role_machine and role_machine.collect and role_machine.collect(ctx, raw) or collect_role(ctx, slot.role, raw)
    elseif slot.optional then
      fields[slot.name] = slot.default
    else
      llbl.fail("missing slot " .. tostring(slot.name), { primary = stage.origin, code = "E_MISSING_SLOT" })
    end
  end
  fields.origin = fields.origin or stage.origin
  fields.slot_origins = origins
  local out = stage.head.emit and stage.head.emit(fields, stage.dialect, { head = stage.head, raw = stage.raw, origins = origins, events = stage.events, stage = stage }) or { tag = stage.head.tag or stage.head.name, fields = fields }
  return attach_node_meta(out, stage.head.tag or stage.head.name, { dialect = stage.dialect.name, head = stage.head.name, head_spec = stage.head, fields = fields, slot_origins = origins, raw = stage.raw, events = stage.events, origin = stage.origin })
end

local function compiled_maybe_finish(stage)
  if remaining_optional(stage.head.slots, stage.next_index) then return compiled_build_stage(stage) end
  return stage
end

local function compiled_replay_stage(stage, event)
  return consume_event(setmetatable({
    __llbl_tag = "Stage",
    dialect = stage.dialect,
    head = stage.head,
    raw = shallow_copy(stage.raw),
    origins = shallow_copy(stage.origins),
    events = shallow_copy(stage.events),
    seen = shallow_copy(stage.seen),
    next_index = stage.next_index,
    origin = stage.origin,
  }, RuntimeStage), event)
end

local function compiled_consume_event(stage, event)
  local slots, i = stage.head.slots, stage.next_index
  while i <= #slots do
    local slot = slots[i]
    if event_fits(stage.dialect, slot, event) then
      local ns = setmetatable({
        __llbl_tag = "Stage",
        dialect = stage.dialect,
        head = stage.head,
        compiled = stage.compiled,
        raw = shallow_copy(stage.raw),
        origins = shallow_copy(stage.origins),
        events = shallow_copy(stage.events),
        seen = shallow_copy(stage.seen),
        next_index = i + 1,
        origin = stage.origin,
      }, CompiledStage)
      ns.raw[slot.name], ns.origins[slot.name], ns.events[slot.name], ns.seen[slot.name] = event.value, event.origin or stage.origin, event, true
      return compiled_maybe_finish(ns)
    elseif slot.optional then
      i = i + 1
    else
      return compiled_replay_stage(stage, event)
    end
  end
  return compiled_replay_stage(stage, event)
end

local function compiled_consume(stage, action, value, argc, origin)
  local override_origin
  value, override_origin = unwrap_origin_value(value)
  origin = override_origin or origin
  return compiled_consume_event(stage, llbl.event(channel_for_action(action, value, argc or 0), value, {
    action = action,
    argc = argc or 0,
    origin = origin or stage.origin,
  }))
end

local function compiled_start_stage(h)
  return setmetatable({
    __llbl_tag = "Stage",
    dialect = h.dialect,
    head = h.spec,
    compiled = h.compiled,
    raw = {},
    origins = {},
    events = {},
    seen = {},
    next_index = 1,
    origin = compiled_stage_origin(h),
  }, CompiledStage)
end

function CompiledHead:event_region(events, param, state)
  return head_event_region(self, events, param, state, compiled_start_stage, compiled_consume_event, compiled_build_stage, "head:compiled")
end

function CompiledHead:collect_events(events, param, state)
  local gen, p0, s0 = self:event_region(events, param, state)
  local next_state, value = gen(p0, s0)
  if next_state == nil then return nil end
  return value
end

CompiledHead.__index = function(self, key)
  if CompiledHead[key] then return CompiledHead[key] end
  local o = source.capture("head-name", { hint = key })
  local name_value, override_origin = unwrap_origin_value(key)
  o = override_origin or o
  if is_tag(name_value, "Name") then
    return compiled_consume(compiled_start_stage(self), "name", name_value, 1, o)
  end
  if is_tag(name_value, "Symbol") then
    return compiled_consume(compiled_start_stage(self), "name", llbl.name(name_value.text, { origin = o }), 1, o)
  end
  return compiled_consume(compiled_start_stage(self), "name", llbl.name(name_value, { origin = o }), 1, o)
end

CompiledHead.__call = function(self, ...)
  local p, o = pack(...), source.capture("head-call", { hint = self.spec.name })
  if p.n > 0 and is_tag(p[1], "OriginValue") then o = p[1].__llbl_origin or p[1].origin or o end
  if p.n == 0 and #self.spec.slots == 0 then return compiled_build_stage(setmetatable({ __llbl_tag = "Stage", dialect = self.dialect, head = self.spec, compiled = self.compiled, raw = {}, origins = {}, events = {}, seen = {}, next_index = 1, origin = o }, CompiledStage)) end
  local v = p.n == 0 and UNIT or p[1]
  if p.n == 1 and v == nil then v = NIL end
  if p.n <= 1 then return compiled_consume(compiled_start_stage(self), "call", v, p.n, o) end
  return compiled_consume(compiled_start_stage(self), "call", p, p.n, o)
end

CompiledStage.__index = function(self, key)
  if CompiledStage[key] then return CompiledStage[key] end
  return compiled_consume(self, "index", key, 1, source.capture("slot-index"))
end

CompiledStage.__call = function(self, ...)
  local p, o = pack(...), source.capture("slot-call")
  local v = p.n == 0 and UNIT or p[1]
  if p.n == 1 and v == nil then v = NIL end
  if p.n <= 1 then return compiled_consume(self, "call", v, p.n, o) end
  return compiled_consume(self, "call", p, p.n, o)
end

function CompiledHead:at(origin)
  return setmetatable({ __llbl_tag = "HeadAt", head = self, origin = origin }, HeadAt)
end

local function compiled_head(lang, spec, compiled)
  local h = setmetatable({ __llbl_tag = "Head", dialect = lang, spec = spec, compiled = compiled, backend = "compiled" }, CompiledHead)
  h.construct = h
  return llbl.codegen.register(h, {
    id = tostring(lang.name) .. ".head." .. tostring(spec.name),
    kind = "head",
    dialect = lang.name,
    head = spec.name,
    mode = "fast",
    origin = spec.origin,
    reflective = runtime_head(lang, spec),
    generated = false,
  })
end

function llbl.codegen.compile_heads(lang, opts)
  opts = opts or {}
  local compiled = lang.compiled or llbl.codegen.compile_dialect(lang, opts)
  compiled.heads = compiled.heads or {}
  for name, spec in pairs(lang.heads or {}) do
    compiled.heads[name] = compiled_head(lang, spec, compiled)
    if opts.install_exports ~= false then lang.exports[name] = compiled.heads[name] end
  end
  return compiled.heads
end
end
install_head_codegen()

-- ---------------------------------------------------------------------------
-- Context, scopes, passes, analysis
-- ---------------------------------------------------------------------------
--
-- Context is the common object passed to checks and phases. It owns diagnostic
-- collection, lexical scopes, symbol indexing, type hooks, and arbitrary phase
-- data. Dialect-specific compilers can extend behavior through hooks instead
-- of side channels.

local Context = {}; Context.__index = Context
function llbl.context(lang, opts)
  opts = opts or {}
  return setmetatable({ __llbl_tag = "Context", dialect = lang, opts = opts, mode = opts.mode or "fast", diagnostics = opts.diagnostics or llbl.diagnostics(), scopes = { {} }, current = {}, data = {}, fatal = opts.fatal }, Context)
end
function Context:error(spec) spec = spec or {}; spec.severity = "error"; local d = self.diagnostics:add(llbl.diagnostic(spec)); if self.fatal then error(d:render(), 2) end; return d end
function Context:warn(spec) spec = spec or {}; spec.severity = "warning"; return self.diagnostics:add(llbl.diagnostic(spec)) end
function Context:warning(spec) return self:warn(spec) end
function Context:push_scope(name) self.scopes[#self.scopes + 1] = { __name = name } end
function Context:pop_scope() if #self.scopes > 1 then self.scopes[#self.scopes] = nil end end
function Context:scope() return self.scopes[#self.scopes] end
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
function Context:resolve(name) return self:lookup(name) end
function Context:index_symbol(name, value, origin)
  self.index = self.index or { symbols = {} }
  local text = is_tag(name, "Name") and name.text or (is_tag(name, "Symbol") and name.text or tostring(name))
  local entry = { name = text, value = value, origin = origin or origin_of(value) }
  self.index.symbols[#self.index.symbols + 1] = entry
  return entry
end
function Context:emit(kind, value)
  self.emitted = self.emitted or {}
  local entry = { kind = kind, value = value, origin = origin_of(value) }
  self.emitted[#self.emitted + 1] = entry
  return entry
end
function Context:typeof(e, expected) local ts = self.dialect and self.dialect.type_system; return ts and ts.typeof and ts.typeof(self, e, expected) or nil end
function Context:assignable(got, expected, origin) local ts = self.dialect and self.dialect.type_system; if ts and ts.assignable then return ts.assignable(self, got, expected, origin) end; return got == expected end
function Context:format_type(T) local ts = self.dialect and self.dialect.type_system; if ts and ts.format then return ts.format(T) end; return is_tag(T, "Type") and T.name or tostring(T) end
llbl.Context = Context

local function walk(v, fn, parent, key, seen)
  if type(v) ~= "table" then return end
  seen = seen or {}; if seen[v] then return end; seen[v] = true
  if fn(v, parent, key) == false then return end
  for k, child in pairs(v) do if k ~= "__llbl" and k ~= "origin" and k ~= "__llbl_tag" and type(child) == "table" then walk(child, fn, v, k, seen) end end
end
llbl.walk = walk

local Analysis = {}; Analysis.__index = Analysis
function Analysis:has_errors() return self.diagnostics:has_errors() end
function Analysis:render_diagnostics(opts) return self.diagnostics:render(opts) end
function Analysis:format_diagnostics(opts) return self:render_diagnostics(opts) end
function Analysis:get_ast() return self.ast end
function Analysis:lsp_index()
  local idx = { __llbl_tag = "LspIndex", diagnostics = self.diagnostics.items, symbols = {}, definitions = {}, references = {}, hovers = {} }
  walk(self.ast, function(n)
    if not is_tag(n, "Node") then return end
    local m = n.__llbl or {}; local hs = m.head_spec
    if hs and hs.lsp and hs.lsp.symbol then
      local sym = hs.lsp.symbol(n, m, self); if sym then idx.symbols[#idx.symbols + 1] = sym end
    elseif self.dialect and self.dialect.lsp and self.dialect.lsp.symbols and self.dialect.lsp.symbols[n.tag] then
      local sym = self.dialect.lsp.symbols[n.tag](n, m, self); if sym then idx.symbols[#idx.symbols + 1] = sym end
    elseif m.fields and m.fields.name then
      local name = type(m.fields.name) == "table" and m.fields.name.text or m.fields.name
      if name then idx.symbols[#idx.symbols + 1] = { name = tostring(name), kind = m.head or "Object", origin = origin_of(m.fields.name) or n.origin, node = n } end
    end
  end)
  return idx
end
llbl.Analysis = Analysis

-- ---------------------------------------------------------------------------
-- Dialect definition and loading
-- ---------------------------------------------------------------------------
--
-- Important doctrine:
--
--   A Dialect is a grammar object.
--   A Language is the authoring/runtime environment.
--
-- Even one dialect is used through a singleton language: llbl + dialect. The
-- llbl singleton is always present, which makes symbols, origins, fragments,
-- process helpers, and spread semantics shared across all language members.

local Dialect = {}; Dialect.__index = Dialect
local BASE_ENV = { assert = assert, error = error, ipairs = ipairs, next = next, pairs = pairs, pcall = pcall, xpcall = xpcall, print = print, select = select, tonumber = tonumber, tostring = tostring, type = type, unpack = unpack, math = math, string = string, table = table, coroutine = coroutine, require = require }
local function builtin_roles() return { name = { kind = "name" }, type = { kind = "type" }, expr = { kind = "expr" }, string = { kind = "string" }, number = { kind = "number" }, boolean = { kind = "boolean" }, value = { kind = "value" }, identity = { kind = "identity" } } end
local function normalize_channels(spec)
  if spec.channels then return array_copy(spec.channels) end
  if spec.channel then return { spec.channel } end
  return nil
end
local function normalize_slot_decl(s)
  local spec = s.spec or {}
  return { name = s.name, role = s.role, channels = normalize_channels(spec), channel = spec.channel, optional = spec.optional or s.optional or false, default = spec.default, label = spec.label, origin = s.origin, spec = spec }
end

local PREV_NIL = {}
local UseSession = {}
UseSession.__index = UseSession
llbl.UseSession = UseSession

local Language = {}
Language.__index = Language
llbl.Language = Language

local function name_map(t)
  return setmetatable(t or {}, { __call = function(map) return sorted_keys(map) end })
end

local function list_to_set(xs)
  local out = {}
  for i = 1, #(xs or {}) do out[tostring(xs[i])] = true end
  return out
end

local function capability_map(target)
  local caps = rawget(target, "__llbl_capabilities")
  if caps == nil then
    caps = {}
    rawset(target, "__llbl_capabilities", caps)
  end
  return caps
end

local function scope_stack(target)
  local stack = rawget(target, "__llbl_scope_stack")
  if stack == nil then
    stack = {}
    rawset(target, "__llbl_scope_stack", stack)
  end
  return stack
end

function llbl.capabilities(target)
  return sorted_keys(rawget(target or _G, "__llbl_capabilities") or {})
end

function llbl.has_capability(target, cap)
  local caps = rawget(target or _G, "__llbl_capabilities") or {}
  return caps[cap] ~= nil
end

function llbl.scope_stack(target)
  return rawget(target or _G, "__llbl_scope_stack") or {}
end

local function check_requires(target, requires, origin)
  local caps = rawget(target, "__llbl_capabilities") or {}
  for i = 1, #(requires or {}) do
    local cap = tostring(requires[i])
    if caps[cap] == nil then
      llbl.fail("missing required LLBL scope capability " .. cap, {
        code = "E_MISSING_USE_SCOPE",
        primary = origin,
        notes = { "Install the required dialect scope before this use() call." },
      }, 2)
    end
  end
end

local function is_identifier(s)
  return type(s) == "string" and s:match("^[_%a][_%w]*$") ~= nil
end

local function copy_into(dst, src)
  for k, v in pairs(src or {}) do dst[k] = v end
  return dst
end

function llbl.base_env(kind)
  if type(kind) == "table" then return shallow_copy(kind) end
  if kind == "inherit" then return shallow_copy(_G) end
  return shallow_copy(BASE_ENV)
end

local function helper_exports()
  return {
    N = llbl.N,
    spread = llbl.spread,
    _ = llbl._,
    hole = llbl.hole,
    curried = llbl.curried,
    curry = llbl.curried,
    region = llbl.region,
    role_region = llbl.role_region,
    process = llbl.process,
    process_opts = llbl.process_opts,
    shared = llbl.shared,
    here = llbl.here,
    at_origin = llbl.at,
    with_origin = llbl.with_origin,
  }
end

local Namespace = {}

Namespace.__index = function(self, key)
  local method = Namespace[key]
  if method ~= nil then return method end
  local default_head = rawget(self, "default_head")
  if default_head ~= nil then return default_head[key] end
  return nil
end

function llbl.namespace(spec)
  spec = spec or {}
  local exports = shallow_copy(spec.exports or spec.items or {})
  exports.__llbl_tag = "Namespace"
  exports.language = tostring(spec.language or "")
  exports.member = tostring(spec.member or spec.dialect or "")
  exports.name = tostring(spec.name or spec.member or spec.dialect or "namespace")
  exports.origin = spec.origin or source.capture("namespace", { hint = exports.name })
  exports.metadata = spec.metadata
  exports.zone = spec.zone
  exports.default_head = spec.default_head or spec.default or spec.module
  return setmetatable(exports, Namespace)
end

function Namespace:__call(body)
  if self.zone then return self.zone(body) end
  llbl.fail("namespace `" .. tostring(self.name) .. "` is not callable", {
    code = "E_NAMESPACE_NOT_CALLABLE",
    primary = self.origin,
  }, 2)
end

function Namespace:describe()
  return llbl.describe_namespace(self)
end

local LLBL_CORE_MEMBER = "llbl"
local llbl_core_markdown

-- The root language member. It is intentionally small: expose the llbl singleton
-- and the shared authoring substrate, but avoid stealing generic names such as
-- "symbol" from member dialects.
local function llbl_core_exports()
  local exports = helper_exports()
  exports.llbl = llbl
  return exports
end

local function llbl_core_member()
  return {
    name = LLBL_CORE_MEMBER,
    exports = llbl_core_exports,
    markdown = function(member, opts, language) return llbl_core_markdown(member, opts, language) end,
    provides = {
      "llbl",
      "llbl.core",
      "llbl.shared.symbols",
      "llbl.shared.origins",
      "llbl.shared.diagnostics",
      "llbl.shared.formatting",
      "llbl.shared.fragments",
      "llbl.shared.regions",
      "llbl.shared.languages",
    },
    semantics = {
      owns = {
        "authoring-substrate",
        "diagnostics",
        "language-composition",
        "fragments",
        "generic-region",
        "namespaces",
        "origins",
        "symbol-creation",
        "symbol-resolution",
        "shared-formatting",
        "language-identity",
        "language-capability-algebra",
        "gps-vm",
      },
      resolves = { "symbols" },
      formats = { "doc-model" },
      indexes = { "language-index-events" },
      lowers = { "regions-to-gps" },
      materializes = { "regions", "diagnostics", "formatting" },
    },
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

function llbl.make_env(lang, opts)
  opts = opts or {}
  if is_tag(lang, "Dialect") then
    return lang:language():env(opts)
  end
  local env = llbl.base_env(opts.base or "safe")
  if opts.dialect_exports ~= false then copy_into(env, lang and lang.exports or {}) end
  if opts.helpers ~= false then copy_into(env, helper_exports()) end
  copy_into(env, opts.exports)
  if opts.unsafe then env.io, env.os, env.debug, env.package = io, os, debug, package end
  env._G = env
  return env
end

local function install_auto_names(target, session, opts)
  if opts.auto_names == false then return end
  local old_mt = getmetatable(target)
  if old_mt ~= nil and type(old_mt) ~= "table" then
    llbl.fail("cannot install LLBL auto-names on target with protected metatable", { code = "E_PROTECTED_ENV_METATABLE" })
  end
  local old_index = old_mt and old_mt.__index
  local old_newindex = old_mt and old_mt.__newindex
  local mt = {}
  if old_mt then for k, v in pairs(old_mt) do mt[k] = v end end
  mt.__llbl_session = session
  mt.__index = function(t, key)
    if is_identifier(key) then
      local origin = source.capture("auto-name", { hint = key, skip = 1 })
      local value = llbl.shared.symbols.source(key, { origin = origin })
      rawset(t, key, value)
      session.auto_installed[key] = true
      session.auto_values[key] = value
      return value
    end
    local old = old_index_value(old_index, t, key)
    if old ~= nil then return old end
    return nil
  end
  mt.__newindex = function(t, key, value)
    if opts.strict and rawget(t, key) == nil then
      local msg = opts.strict_message or "strict LLBL environment: assignment to unknown global "
      error(tostring(msg) .. tostring(key), 2)
    end
    old_newindex_set(old_newindex, t, key, value)
  end
  session.previous_mt = old_mt
  session.metatable_installed = true
  setmetatable(target, mt)
end

function llbl.install_env(env, target, opts, session)
  opts = opts or {}
  target = target or _G
  session = session or setmetatable({ __llbl_tag = "UseSession", env = env, target = target, installed = name_map(), previous = {}, skipped = name_map(), active = true, auto_installed = name_map(), auto_values = {} }, UseSession)
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

function llbl.use(lang, opts)
  -- Direct llbl.use(Dialect, ...) delegates to the dialect's language so the llbl root member is
  -- always installed and symbol sharing remains coherent.
  opts = opts or {}
  if is_tag(lang, "Dialect") then
    local language_opts = opts
    if opts.dialect_exports == false and opts.exports ~= nil then
      language_opts = shallow_copy(opts)
      language_opts.member_exports = shallow_copy(opts.member_exports or {})
      language_opts.member_exports[tostring(lang.name)] = opts.exports
      language_opts.exports = nil
    end
    return Language.use(lang:language(), language_opts)
  end
  local scope = opts.scope or (opts.global == false and "env" or "permanent")
  local env = llbl.make_env(lang, opts)
  local target = opts.target or _G
  if scope == "env" and opts.target == nil then target = env end
  local requires = opts.requires or (lang and lang.requires) or {}
  local provides = opts.provides or (lang and lang.provides) or {}
  check_requires(target, requires, lang and lang.origin)
  local session = setmetatable({
    __llbl_tag = "UseSession",
    dialect = lang,
    env = env,
    target = target,
    scope = scope,
    mode = opts.mode or "fast",
    requires_caps = array_copy(requires),
    provides_caps = array_copy(provides),
    capability_previous = {},
    scope_record = nil,
    installed = name_map(),
    previous = {},
    skipped = name_map(),
    auto_installed = name_map(),
    auto_values = {},
    active = true,
  }, UseSession)
  rawset(env, "__llbl_session", session)
  if scope ~= "env" then
    llbl.install_env(env, target, opts, session)
  else
    if target ~= env then
      for k, v in pairs(env or {}) do
        if k ~= "_G" and (rawget(target, k) == nil or opts.override) then rawset(target, k, v) end
      end
      env = target
      session.env = target
      rawset(env, "__llbl_session", session)
    end
    install_auto_names(env, session, opts)
  end
  local caps = capability_map(target)
  for i = 1, #provides do
    local cap = tostring(provides[i])
    session.capability_previous[cap] = caps[cap] or PREV_NIL
    caps[cap] = session
  end
  local stack = scope_stack(target)
  local rec = {
    dialect = lang and lang.name or nil,
    session = session,
    requires = array_copy(requires),
    provides = array_copy(provides),
    exports = sorted_keys(env),
    mode = session.mode,
  }
  session.scope_record = rec
  stack[#stack + 1] = rec
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
  if mt and mt.__llbl_session == self then setmetatable(target, self.previous_mt) end
  local caps = rawget(target, "__llbl_capabilities")
  if caps then
    for cap, prev in pairs(self.capability_previous or {}) do
      if caps[cap] == self then
        if prev == PREV_NIL then caps[cap] = nil else caps[cap] = prev end
      end
    end
  end
  local stack = rawget(target, "__llbl_scope_stack")
  if stack and self.scope_record then
    for i = #stack, 1, -1 do
      if stack[i] == self.scope_record then table.remove(stack, i); break end
    end
  end
  return true
end

local function map_names(m)
  return sorted_keys(m or {})
end

function UseSession:installed() return map_names(self.installed) end
function UseSession:skipped() return map_names(self.skipped) end
function UseSession:auto_created() return map_names(self.auto_installed) end
function UseSession:provides() return array_copy(self.provides_caps or {}) end
function UseSession:requires() return array_copy(self.requires_caps or {}) end
function UseSession:exports() return sorted_keys(self.env or {}) end
function UseSession:loadstring(src, chunkname, opts)
  opts = shallow_copy(opts or {})
  chunkname = chunkname or (self.dialect and self.dialect.name) or "=(llbl.use)"
  source.register(chunkname, src)
  local f, err = compile_lua(src, chunkname)
  if not f then error(err, 2) end
  setfenv0(f, self.env)
  return f
end
function UseSession:loadfile(path, opts)
  local f, err = io.open(path, "rb")
  if not f then error(err, 2) end
  local src = f:read("*a") or ""
  f:close()
  return self:loadstring(src, "@" .. path, opts)
end
function UseSession:dofile(path, ...)
  local chunk = self:loadfile(path)
  return chunk(...)
end
function UseSession:describe()
  return {
    tag = "UseSession",
    dialect = self.dialect and self.dialect.name or nil,
    scope = self.scope,
    mode = self.mode,
    active = self.active,
    requires = self:requires(),
    provides = self:provides(),
    exports = self:exports(),
    installed = self:installed(),
    skipped = self:skipped(),
    auto_created = self:auto_created(),
  }
end

function llbl.with_use(lang, opts, fn)
  opts = shallow_copy(opts or {})
  opts.scope = opts.scope or "scoped"
  local session = llbl.use(lang, opts)
  local ok, a, b, c = pcall(fn, session.env, session)
  session:close()
  if not ok then error(a, 0) end
  return a, b, c
end

local function language_member_exports(member, opts)
  local member_name = tostring(member.name or (member.dialect and member.dialect.name) or "?")
  if opts and opts.member_exports and opts.member_exports[member_name] ~= nil then
    return shallow_copy(opts.member_exports[member_name])
  end
  local exports = member.exports
  if type(exports) == "function" then return exports(opts or {}) end
  if type(exports) == "table" then return shallow_copy(exports) end
  return shallow_copy(member.dialect and member.dialect.exports or {})
end

local function language_member_from_dialect(lang)
  return {
    name = lang.name,
    dialect = lang,
    exports = function() return lang.exports end,
    provides = { lang.name },
  }
end

local function language_of(value)
  if is_tag(value, "Language") then return value end
  if is_tag(value, "Dialect") then return value.__llbl_language or llbl.language(tostring(value.name), { language_member_from_dialect(value) }) end
  llbl.fail("language algebra expects a Language or Dialect, got " .. repr(value), { code = "E_LANGUAGE_OPERAND" }, 2)
end

local function language_spec_from(base, patch)
  patch = patch or {}
  local spec = {}
  spec.members = patch.members or array_copy(base.members or {})
  spec.collision = patch.collision or base.collision
  spec.prefer = shallow_copy(base.preferences or {})
  for k, v in pairs(patch.prefer or {}) do spec.prefer[k] = v end
  spec.reserved = sorted_keys(base.reserved or {})
  if patch.reserved then append(spec.reserved, patch.reserved) end
  spec.shared = sorted_keys(base.shared or {})
  if patch.shared then append(spec.shared, patch.shared) end
  return spec
end

local function language_define(name, spec)
  -- All languages include the llbl root member. language_define also deduplicates
  -- members so composing languages cannot accidentally install llbl twice.
  spec = spec or {}
  local raw_members = {}
  for i = 1, #(spec.members or spec) do
    raw_members[#raw_members + 1] = spec.members and spec.members[i] or spec[i]
  end
  local members, seen = {}, {}
  local function member_name(member)
    return tostring(member.name or (member.dialect and member.dialect.name) or "?")
  end
  local function add_member(member)
    local n = member_name(member)
    if not seen[n] then
      seen[n] = true
      members[#members + 1] = member
    end
  end
  if tostring(name) == LLBL_CORE_MEMBER and #raw_members == 0 then
    add_member(llbl_core_member())
  else
    add_member(llbl_core_member())
    for i = 1, #raw_members do add_member(raw_members[i]) end
  end
  local provides = {}
  local requires = {}
  for _, member in ipairs(members) do
    append(provides, member.provides or (member.dialect and member.dialect.provides) or {})
    append(requires, member.requires or (member.dialect and member.dialect.requires) or {})
  end
  local language = setmetatable({
    __llbl_tag = "Language",
    name = tostring(name),
    members = members,
    collision = spec.collision or "error",
    preferences = spec.prefer or spec.collisions or {},
    reserved = list_to_set(spec.reserved or {}),
    shared = list_to_set(spec.shared or {}),
    provides = provides,
    requires = requires,
  }, Language)
  language.use = function(opts) return Language.use(language, opts) end
  language.env = function(opts) return Language.env(language, opts) end
  language.loadstring = function(src, chunkname, opts) return Language.loadstring(language, src, chunkname, opts) end
  language.load = function(src, chunkname, opts) return Language.loadstring(language, src, chunkname, opts)() end
  language.loadfile = function(path, opts) return Language.loadfile(language, path, opts) end
  language.describe = function() return Language.describe(language) end
  language.format_region = function(value, opts) return Language.format_region(language, value, opts) end
  language.format = function(value, opts) return Language.format(language, value, opts) end
  language.format_doc = function(value, opts) return Language.format_doc(language, value, opts) end
  language.diagnostics = function(value, opts) return Language.diagnostics(language, value, opts) end
  language.index = function(value, opts) return Language.index(language, value, opts) end
  language.audit = function() return Language.audit(language) end
  language.markdown = function(opts) return Language.markdown(language, opts) end
  language.write_markdown = function(path, opts) return Language.write_markdown(language, path, opts) end
  language.compose = function(other, opts) return Language.compose(language, other, opts) end
  language.subtract = function(member_or_name, opts) return Language.subtract(language, member_or_name, opts) end
  language.only = function(names, opts) return Language.only(language, names, opts) end
  language.prefer = function(map, opts) return Language.prefer(language, map, opts) end
  return language
end

llbl.language = setmetatable({}, {
  __call = function(_, name, spec) return language_define(name, spec) end,
  __index = function(_, name) return function(spec) return language_define(name, spec) end end,
})

function llbl.core_language()
  return language_define(LLBL_CORE_MEMBER, {})
end

function Language:compose_env(opts)
  -- Compose all member exports into one environment while tracking ownership.
  -- Collisions must be explicitly resolved with language.prefer unless both
  -- members export the exact same object or one member only inherited the base.
  opts = opts or {}
  local base = llbl.base_env(opts.base or opts.target or _G)
  local env = shallow_copy(base)
  local owners = {}
  local member_caps = {}
  local provided = {}
  for _, member in ipairs(self.members or {}) do
    for _, cap in ipairs(member.requires or {}) do
      if not provided[tostring(cap)] then
        llbl.fail("language " .. self.name .. " member " .. tostring(member.name or "?") .. " requires missing capability " .. tostring(cap), {
          code = "E_LANGUAGE_MISSING_MEMBER_CAPABILITY",
          notes = { "Declare the required dialect earlier in the language or remove the incompatible member." },
        }, 2)
      end
    end
    local exports = language_member_exports(member, opts)
    local member_name = tostring(member.name or (member.dialect and member.dialect.name) or "?")
    member_caps[#member_caps + 1] = {
      name = member_name,
      provides = array_copy(member.provides or {}),
      requires = array_copy(member.requires or {}),
    }
    for k, v in pairs(exports or {}) do
      if k ~= "_G" then
        local cur = rawget(env, k)
        local base_v = rawget(base, k)
        local owner = owners[k]
        if owner ~= nil and v == base_v then
          -- This member merely inherited the base binding. It does not
          -- participate in language ownership or collision decisions.
        elseif owner ~= nil and cur ~= v then
          local preferred = self.preferences[k]
          if preferred == member_name then
            env[k] = v
            owners[k] = member_name
          elseif preferred == owner or cur == v then
            -- keep current value
          else
            llbl.fail("LLBL language " .. self.name .. " export collision on `" .. tostring(k) .. "` between " .. tostring(owner) .. " and " .. member_name, {
              code = "E_LANGUAGE_EXPORT_COLLISION",
              notes = { "Declare language.prefer[`" .. tostring(k) .. "`] or make both languages export the same object." },
            }, 2)
          end
        else
          env[k] = v
          if v ~= base_v then owners[k] = member_name end
        end
      end
    end
    for _, cap in ipairs(member.provides or {}) do provided[tostring(cap)] = true end
  end
  env._G = env
  return env, member_caps, owners
end

function Language:use(opts)
  opts = opts or {}
  local exports, member_caps, owners = self:compose_env(opts)
  copy_into(exports, opts.exports)
  local session = llbl.use(self, {
    scope = opts.scope or (opts.global == false and "env" or "permanent"),
    target = opts.target,
    base = exports,
    exports = exports,
    dialect_exports = false,
    helpers = false,
    global = opts.global,
    strict = opts.strict,
    strict_message = opts.strict_message or ("unknown " .. self.name .. " language global "),
    override = opts.override,
    auto_names = opts.auto_names ~= false,
    mode = opts.mode,
    provides = opts.provides or self.provides,
    requires = opts.requires or {},
    searcher = opts.searcher,
  })
  session.language = self
  session.members = member_caps
  session.owners = owners or {}
  return session
end

function Language:env(opts)
  opts = shallow_copy(opts or {})
  opts.scope = opts.scope or "env"
  return Language.use(self, opts).env
end

function Language:loadstring(src, chunkname, opts)
  local session = Language.use(self, { scope = "env", target = opts and opts.env or nil, global = false, strict = opts and opts.strict, auto_names = opts == nil or opts.auto_names ~= false, base = opts and opts.base, mode = opts and opts.mode, override = opts and opts.override })
  return session:loadstring(src, chunkname or self.name)
end

function Language:load(src, chunkname, opts) return Language.loadstring(self, src, chunkname, opts)() end
function Language:loadfile(path, opts)
  local f, err = io.open(path, "rb")
  if not f then error(err, 2) end
  local src = f:read("*a") or ""
  f:close()
  return Language.loadstring(self, src, "@" .. path, opts)
end

function Language:resolve_symbol(symbol, opts)
  opts = opts or {}
  local name = (is_tag(symbol, "Symbol") or is_tag(symbol, "Name")) and symbol.text or tostring(symbol)
  local env, _, owners = self:compose_env(opts)
  local value = rawget(env, name)
  if value ~= nil then
    return llbl.binding {
      kind = "export",
      name = name,
      symbol = is_tag(symbol, "Symbol") and symbol or nil,
      value = value,
      owner = (owners and owners[name]) or "lua",
      language = self.name,
      generated = is_tag(symbol, "Symbol") and symbol.generated or false,
      origin = origin_of(symbol),
    }
  end
  local diag
  if opts.diagnostics then
    diag = llbl.diagnostic {
      code = "E_UNRESOLVED_SYMBOL",
      message = "unresolved symbol `" .. tostring(name) .. "` in language `" .. tostring(self.name) .. "`",
      primary = origin_of(symbol),
    }
    opts.diagnostics:add(diag)
  end
  return llbl.shared.symbols.unresolved(name, {
    symbol = is_tag(symbol, "Symbol") and symbol or nil,
    origin = origin_of(symbol),
    language = self.name,
    diagnostic = diag,
  })
end

function Language:symbol_region(symbol, opts)
  return llbl.gps.raw(llbl.gps.wrap(function(param, state)
    if state ~= nil then return nil end
    return true, param.language:resolve_symbol(param.symbol, param.opts or {})
  end, {
    language = self,
    symbol = symbol,
    opts = opts or {},
  }, nil, { kind = "language:symbol", language = self.name }))
end

function llbl.shared.symbols.resolve(language, symbol, opts)
  language = language_of(language)
  return language:resolve_symbol(symbol, opts or {})
end

llbl.shared.languages = llbl.shared.languages or {
  identity = llbl.core_language,
  core = llbl.core_language,
  compose = function(a, b, opts) return Language.compose(language_of(a), b, opts or {}) end,
  resolve_symbol = function(language, symbol, opts) return language_of(language):resolve_symbol(symbol, opts or {}) end,
}

local function language_member_name(member)
  return tostring(member.name or (member.dialect and member.dialect.name) or "?")
end

function Language:member(name)
  name = tostring(name)
  for _, member in ipairs(self.members or {}) do
    if language_member_name(member) == name then return member end
  end
  return nil
end

local function member_for_zone(language, zone)
  if not is_tag(zone, "Zone") then return nil end
  return Language.member(language, zone.member) or Language.member(language, zone.name)
end

local function is_array_table(t)
  if type(t) ~= "table" then return false end
  local n = #t
  for k in pairs(t) do
    if type(k) ~= "number" or k < 1 or k > n or k % 1 ~= 0 then return false end
  end
  return true
end

local language_region_ops = (function()
local function push_value(stack, value)
  if value ~= nil then stack[#stack + 1] = value end
end

local function push_table_children(stack, value)
  local record_values = {}
  for k, v in pairs(value) do
    if type(k) ~= "number" then record_values[#record_values + 1] = v end
  end
  for i = #record_values, 1, -1 do push_value(stack, record_values[i]) end
  for i = #value, 1, -1 do push_value(stack, value[i]) end
end

local function zone_region_gen(param, state)
  state = state or { stack = { param.value } }
  local stack = state.stack
  while #stack > 0 do
    local value = stack[#stack]
    stack[#stack] = nil
    if is_tag(value, "Zone") then
      if param.member_name == nil or value.member == param.member_name or value.name == param.member_name then
        return state, value
      end
    elseif is_tag(value, "LanguageBundle") then
      local zones = value.zones or {}
      for i = #zones, 1, -1 do push_value(stack, zones[i]) end
    elseif type(value) == "table" then
      push_table_children(stack, value)
    end
  end
  return nil
end

local function zone_region(language, value, member_name)
  return llbl.gps.raw(llbl.gps.wrap(zone_region_gen, {
    language = language,
    value = value,
    member_name = member_name,
  }, nil, { kind = "language:zones", language = language.name }))
end

local function push_diagnostic(buffer, d)
  if is_tag(d, "Diagnostic") then buffer[#buffer + 1] = d end
end

local function push_diagnostic_result(buffer, result)
  if is_tag(result, "Diagnostic") then push_diagnostic(buffer, result)
  elseif is_tag(result, "DiagnosticBag") then
    for i = 1, #(result.items or {}) do push_diagnostic(buffer, result.items[i]) end
  elseif type(result) == "table" and result.items then
    for i = 1, #(result.items or {}) do push_diagnostic(buffer, result.items[i]) end
  end
end

local function diagnostic_region_gen(param, state)
  state = state or { member_index = 1, buffer = {}, buffer_index = 1 }
  while true do
    if state.buffer_index <= #state.buffer then
      local d = state.buffer[state.buffer_index]
      state.buffer_index = state.buffer_index + 1
      return state, d
    end
    state.buffer, state.buffer_index = {}, 1
    local member = (param.language.members or {})[state.member_index]
    if member == nil then return nil end
    state.member_index = state.member_index + 1
    if type(member.diagnostics) == "function" then
      local bag = llbl.diagnostics()
      local opts = shallow_copy(param.opts or {})
      opts.diagnostics = bag
      local ok, result = pcall(member.diagnostics, param.value, bag, opts, param.language)
      if ok then
        push_diagnostic_result(state.buffer, bag)
        if result ~= bag then push_diagnostic_result(state.buffer, result) end
      else
        state.buffer[#state.buffer + 1] = llbl.diagnostic {
          code = "E_LANGUAGE_MEMBER_TOOL",
          message = tostring(result),
          primary = origin_of(param.value),
          notes = { "while running language tooling for " .. language_member_name(member) },
        }
      end
    end
  end
end

local function diagnostic_region(language, value, opts)
  return llbl.gps.raw(llbl.gps.wrap(diagnostic_region_gen, {
    language = language,
    value = value,
    opts = opts or {},
  }, nil, { kind = "language:diagnostics", language = language.name }))
end

local function push_index_result(buffer, result)
  if type(result) ~= "table" then return end
  for i = 1, #(result.symbols or {}) do buffer[#buffer + 1] = { kind = "symbol", value = result.symbols[i] } end
  for i = 1, #(result.hovers or {}) do buffer[#buffer + 1] = { kind = "hover", value = result.hovers[i] } end
  for i = 1, #(result.diagnostics or {}) do buffer[#buffer + 1] = { kind = "diagnostic", value = result.diagnostics[i] } end
end

local function index_region_gen(param, state)
  state = state or {
    phase = "zones",
    zone_gen = nil,
    zone_param = nil,
    zone_state = nil,
    member_index = 1,
    buffer = {},
    buffer_index = 1,
  }
  if state.phase == "zones" and state.zone_gen == nil then
    state.zone_gen, state.zone_param, state.zone_state = zone_region(param.language, param.value)
  end
  while true do
    if state.buffer_index <= #state.buffer then
      local ev = state.buffer[state.buffer_index]
      state.buffer_index = state.buffer_index + 1
      return state, ev
    end
    state.buffer, state.buffer_index = {}, 1
    if state.phase == "zones" then
      local next_state, z = state.zone_gen(state.zone_param, state.zone_state)
      if next_state ~= nil then
        state.zone_state = next_state
        return state, { kind = "zone", value = { name = z.name, member = z.member, role = z.role, count = #(z.items or {}) } }
      end
      state.phase = "members"
    end
    local member = (param.language.members or {})[state.member_index]
    if member == nil then return nil end
    state.member_index = state.member_index + 1
    if type(member.index) == "function" then
      local ok, result = pcall(member.index, param.value, param.opts or {}, param.language)
      if ok then
        push_index_result(state.buffer, result)
      else
        state.buffer[#state.buffer + 1] = {
          kind = "diagnostic",
          value = llbl.diagnostic {
            code = "E_LANGUAGE_INDEX",
            message = tostring(result),
            primary = origin_of(param.value),
          },
        }
      end
    end
  end
end

local function index_region(language, value, opts)
  return llbl.gps.raw(llbl.gps.wrap(index_region_gen, {
    language = language,
    value = value,
    opts = opts or {},
  }, nil, { kind = "language:index", language = language.name }))
end

return { zone_region = zone_region, diagnostic_region = diagnostic_region, index_region = index_region }
end)()

function Language:zone_region(value, member_name)
  return language_region_ops.zone_region(self, value, member_name)
end

function Language:owned_zones(value, member_name, out)
  out = out or {}
  llbl.gps.each(function(z) out[#out + 1] = z end, self:zone_region(value, member_name))
  return out
end

function Language:diagnostic_region(value, opts)
  return language_region_ops.diagnostic_region(self, value, opts)
end

function Language:index_region(value, opts)
  return language_region_ops.index_region(self, value, opts)
end

local function indent_text(text, indent)
  indent = indent or "  "
  return tostring(text):gsub("\n", "\n" .. indent)
end

local function language_format_value(language, value, opts)
  opts = opts or {}
  if is_tag(value, "Zone") then
    local member = member_for_zone(language, value)
    local item_text = {}
    for i, item in ipairs(value.items or {}) do
      if member and type(member.format) == "function" then
        item_text[i] = member.format(item, opts, language, value)
      else
        item_text[i] = language_format_value(language, item, opts)
      end
    end
    if #item_text == 0 then return tostring(value.name) .. " {}" end
    return tostring(value.name) .. " {\n  " .. indent_text(table.concat(item_text, ",\n"), "  ") .. ",\n}"
  end
  if is_tag(value, "LanguageBundle") then
    local parts = {}
    for i, z in ipairs(value.zones or {}) do parts[i] = language_format_value(language, z, opts) end
    return "{\n  " .. indent_text(table.concat(parts, ",\n"), "  ") .. ",\n}"
  end
  for _, member in ipairs(language.members or {}) do
    if type(member.match) == "function" and member.match(value, opts, language) and type(member.format) == "function" then
      return member.format(value, opts, language)
    end
  end
  if type(value) == "table" then
    opts.__language_seen = opts.__language_seen or {}
    if opts.__language_seen[value] then return "<cycle>" end
    opts.__language_seen[value] = true
    local parts = {}
    for i = 1, #value do parts[#parts + 1] = language_format_value(language, value[i], opts) end
    local keys = {}
    for k in pairs(value) do if type(k) ~= "number" and tostring(k):sub(1, 2) ~= "__" then keys[#keys + 1] = k end end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, k in ipairs(keys) do
      parts[#parts + 1] = tostring(k) .. " = " .. language_format_value(language, value[k], opts)
    end
    opts.__language_seen[value] = nil
    if is_array_table(value) and #parts == 1 then return parts[1] end
    if #parts == 0 then return "{}" end
    return "{\n  " .. indent_text(table.concat(parts, ",\n"), "  ") .. ",\n}"
  end
  return llbl.format(value, opts)
end

function Language:format_doc(value, opts)
  return llbl.doc.text(Language.format(self, value, opts))
end

local function language_format_region_gen(param, state)
  if state ~= nil then return nil end
  local format_opts = shallow_copy(param.opts or {})
  format_opts.__language_seen = nil
  return true, language_format_value(param.language, param.value, format_opts)
end

function Language:format_region(value, opts)
  -- Unified language formatting. The language walks the value and lets member
  -- Dialects format values they own. This keeps cross-dialect files coherent
  -- without forcing each dialect to know about every other dialect.
  return llbl.gps.raw(llbl.gps.wrap(language_format_region_gen, {
    language = self,
    value = value,
    opts = opts or {},
  }, nil, { kind = "language:format", language = self.name }))
end

function Language:format(value, opts)
  local chunks = {}
  llbl.gps.each(function(chunk) chunks[#chunks + 1] = chunk end, Language.format_region(self, value, opts))
  return table.concat(chunks)
end

function Language:diagnostics(value, opts)
  opts = opts or {}
  local bag = opts.diagnostics or llbl.diagnostics()
  llbl.gps.each(function(d) bag:add(d) end, self:diagnostic_region(value, opts))
  return bag
end

function Language:index(value, opts)
  opts = opts or {}
  local index = {
    __llbl_tag = "LanguageIndex",
    language = self.name,
    zones = {},
    symbols = {},
    hovers = {},
    diagnostics = {},
  }
  llbl.gps.each(function(ev)
    if ev.kind == "zone" then index.zones[#index.zones + 1] = ev.value
    elseif ev.kind == "symbol" then index.symbols[#index.symbols + 1] = ev.value
    elseif ev.kind == "hover" then index.hovers[#index.hovers + 1] = ev.value
    elseif ev.kind == "diagnostic" then index.diagnostics[#index.diagnostics + 1] = ev.value end
  end, self:index_region(value, opts))
  return index
end

local function member_semantics(member)
  return member.semantics or member.semantic or {}
end

local function semantic_list(member, field)
  return array_copy(member_semantics(member)[field] or {})
end

function Language:audit()
  local owners, users, members = {}, {}, {}
  local capabilities = { resolves = {}, formats = {}, indexes = {}, lowers = {}, materializes = {} }
  for _, member in ipairs(self.members or {}) do
    local name = language_member_name(member)
    local owns = semantic_list(member, "owns")
    local uses = semantic_list(member, "uses")
    local resolves = semantic_list(member, "resolves")
    local formats = semantic_list(member, "formats")
    local indexes = semantic_list(member, "indexes")
    local lowers = semantic_list(member, "lowers")
    local materializes = semantic_list(member, "materializes")
    members[#members + 1] = {
      name = name,
      owns = owns,
      uses = uses,
      resolves = resolves,
      formats = formats,
      indexes = indexes,
      lowers = lowers,
      materializes = materializes,
      notes = array_copy(member_semantics(member).notes or {}),
    }
    for _, semantic in ipairs(owns) do
      semantic = tostring(semantic)
      owners[semantic] = owners[semantic] or {}
      owners[semantic][#owners[semantic] + 1] = name
    end
    for _, semantic in ipairs(uses) do
      semantic = tostring(semantic)
      users[semantic] = users[semantic] or {}
      users[semantic][#users[semantic] + 1] = name
    end
    for _, field in ipairs({ "resolves", "formats", "indexes", "lowers", "materializes" }) do
      for _, item in ipairs(field == "resolves" and resolves or field == "formats" and formats or field == "indexes" and indexes or field == "lowers" and lowers or materializes) do
        item = tostring(item)
        capabilities[field][item] = capabilities[field][item] or {}
        capabilities[field][item][#capabilities[field][item] + 1] = name
      end
    end
  end

  local owner = {}
  local smells = {}
  for _, semantic in ipairs(sorted_keys(owners)) do
    local semantic_owners = owners[semantic]
    if #semantic_owners == 1 then
      owner[semantic] = semantic_owners[1]
    elseif #semantic_owners > 1 then
      smells[#smells + 1] = {
        code = "E_LANGUAGE_SEMANTIC_OVERLAP",
        kind = "overlap",
        semantic = semantic,
        owners = array_copy(semantic_owners),
        message = "semantic `" .. semantic .. "` has multiple owners: " .. table.concat(semantic_owners, ", "),
      }
    end
  end
  for _, semantic in ipairs(sorted_keys(users)) do
    if owners[semantic] == nil then
      smells[#smells + 1] = {
        code = "W_LANGUAGE_SEMANTIC_EXTERNAL",
        kind = "external",
        semantic = semantic,
        users = array_copy(users[semantic]),
        message = "semantic `" .. semantic .. "` is used by " .. table.concat(users[semantic], ", ") .. " but has no owner in this language",
      }
    end
  end

  return {
    tag = "LanguageAudit",
    language = self.name,
    members = members,
    owner = owner,
    owners = owners,
    users = users,
    capabilities = capabilities,
    smells = smells,
  }
end

local function md_escape(s)
  local escaped = tostring(s or ""):gsub("|", "\\|")
  return escaped
end

local function md_header(level, text)
  return string.rep("#", level) .. " " .. tostring(text)
end

local function sorted_pairs_keys(t)
  local keys = {}
  for k in pairs(t or {}) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  return keys
end

local function markdown_list(title, xs, out)
  out[#out + 1] = title
  out[#out + 1] = ""
  if #(xs or {}) == 0 then
    out[#out + 1] = "- none"
  else
    for _, x in ipairs(xs or {}) do out[#out + 1] = "- `" .. md_escape(x) .. "`" end
  end
  out[#out + 1] = ""
end

local function append_language_audit_markdown(language, out)
  local audit = Language.audit(language)
  out[#out + 1] = "## Language Extension Audit"
  out[#out + 1] = ""
  out[#out + 1] = "The extensible LLBL language has one owner for each semantic primitive. Dialects reuse that primitive through explicit dependencies instead of reimplementing the same meaning under another surface."
  out[#out + 1] = ""
  out[#out + 1] = "### Semantic owners"
  out[#out + 1] = ""
  local owner_keys = sorted_keys(audit.owners or {})
  if #owner_keys == 0 then
    out[#out + 1] = "- none"
  else
    for _, semantic in ipairs(owner_keys) do
      out[#out + 1] = "- `" .. md_escape(semantic) .. "`: `" .. md_escape(table.concat(audit.owners[semantic] or {}, "`, `")) .. "`"
    end
  end
  out[#out + 1] = ""

  out[#out + 1] = "### Semantic reuse"
  out[#out + 1] = ""
  local user_keys = sorted_keys(audit.users or {})
  if #user_keys == 0 then
    out[#out + 1] = "- none"
  else
    for _, semantic in ipairs(user_keys) do
      out[#out + 1] = "- `" .. md_escape(semantic) .. "` is used by `" .. md_escape(table.concat(audit.users[semantic] or {}, "`, `")) .. "`"
    end
  end
  out[#out + 1] = ""

  out[#out + 1] = "### Capability axes"
  out[#out + 1] = ""
  for _, field in ipairs({ "resolves", "formats", "indexes", "lowers", "materializes" }) do
    local entries = audit.capabilities and audit.capabilities[field] or {}
    local keys = sorted_keys(entries)
    if #keys == 0 then
      out[#out + 1] = "- `" .. field .. "`: none"
    else
      for _, item in ipairs(keys) do
        out[#out + 1] = "- `" .. field .. "." .. md_escape(item) .. "`: `" .. md_escape(table.concat(entries[item] or {}, "`, `")) .. "`"
      end
    end
  end
  out[#out + 1] = ""

  out[#out + 1] = "### Audit findings"
  out[#out + 1] = ""
  if #(audit.smells or {}) == 0 then
    out[#out + 1] = "- no semantic ownership overlaps"
  else
    for _, smell in ipairs(audit.smells or {}) do
      out[#out + 1] = "- `" .. md_escape(smell.code) .. "`: " .. md_escape(smell.message)
    end
  end
  out[#out + 1] = ""
end

function llbl_core_markdown(_, opts)
  opts = opts or {}
  local level = opts.level or 2
  local out = {}
  out[#out + 1] = md_header(level, "llbl")
  out[#out + 1] = ""
  out[#out + 1] = "Shared Lua Language Builder substrate installed into every language environment."
  out[#out + 1] = ""
  out[#out + 1] = md_header(level + 1, "Core Exports")
  out[#out + 1] = ""
  out[#out + 1] = "- `llbl`: the singleton workbench API for origins, diagnostics, fragments, languages, formatting, and markdown."
  out[#out + 1] = "- `shared`: substrate services for symbols, origins, diagnostics, formatting, and regions."
  out[#out + 1] = "- `_` / `spread`: splice a role-shaped fragment into a surrounding role."
  out[#out + 1] = "- `region`: generic LLBL control-machine descriptor head; member dialects consume/lower it."
  out[#out + 1] = "- `N`: explicit generated-name factory for metaprogrammed symbols."
  out[#out + 1] = "- `here`, `at_origin`, `with_origin`: provenance helpers for Lua factories."
  out[#out + 1] = "- `shared.symbols.resolve(language, symbol)`: resolve an LLBL symbol to a language binding without assigning dialect-specific meaning."
  out[#out + 1] = ""
  out[#out + 1] = md_header(level + 1, "Grammar Bootstrap")
  out[#out + 1] = ""
  out[#out + 1] = "- `llbl.grammar.role`: declares a named semantic role and its normalization contract."
  out[#out + 1] = "- `llbl.grammar.head`: declares a staged constructor head made from slots and traits."
  out[#out + 1] = "- `llbl.grammar.slot`: declares one consumed input position for a head."
  out[#out + 1] = "- `llbl.grammar.trait`: declares reusable behavior applied to heads."
  out[#out + 1] = "- `llbl.grammar.protocol`: declares a named protocol surface for dialect authors."
  out[#out + 1] = "- `llbl.grammar.scalar` and `llbl.grammar.type_ctor`: declare type-like exports."
  out[#out + 1] = "- `llbl.grammar.helper`: exposes a named Lua helper into a dialect environment."
  out[#out + 1] = "- `llbl.grammar.pass` / `llbl.grammar.phase`: declares semantic analysis passes."
  out[#out + 1] = "- `llbl.grammar.lsp`: declares dialect language-server integration hooks."
  if llbl.bootstrap and llbl.bootstrap.stage then
    out[#out + 1] = ""
    out[#out + 1] = md_header(level + 1, "Bootstrap")
    out[#out + 1] = ""
    out[#out + 1] = "- Stage: `" .. md_escape(llbl.bootstrap.stage) .. "`"
    out[#out + 1] = "- Public grammar facade: `llbl.grammar` from dialect `" .. md_escape(llbl.bootstrap.dialect and llbl.bootstrap.dialect.name or "llbl") .. "`"
    out[#out + 1] = "- Stage-0 kernel grammar: `llbl.kernel.grammar`"
    out[#out + 1] = "- Bootstrap machines: `normalize_role`, `render_doc`"
  end
  out[#out + 1] = ""
  return table.concat(out, "\n")
end

local function has_channel(slot, name)
  for _, ch in ipairs((slot and slot.channels) or {}) do
    if ch == name then return true end
  end
  return false
end

local function role_table_shape(role)
  role = tostring(role or "")
  if role == "params" or role == "fields" then return "{ name [Type], ... }" end
  if role == "conts" or role == "variants" then return "{ ok { ... }, err { ... } }" end
  if role == "decls" then return "{ decl, ... }" end
  if role == "stmts" then return "{ stmt, ... }" end
  if role:match("_body$") then return "{ ... }" end
  return "{ ... }"
end

local function slot_syntax(slot)
  if has_channel(slot, "index:name") then return ". name" end
  if has_channel(slot, "index:type") then return " [Type]" end
  if has_channel(slot, "index:value") then return " [value]" end
  if has_channel(slot, "call:table") then return " " .. role_table_shape(slot.role) end
  if has_channel(slot, "call:value") or has_channel(slot, "call:many") then return " (value)" end
  if has_channel(slot, "call:none") then return " ()" end
  return " <" .. tostring(slot.name or "slot") .. ">"
end

local function head_syntax(name, head)
  local parts = { tostring(name) }
  for _, slot in ipairs((head and head.slots) or {}) do
    parts[#parts + 1] = slot_syntax(slot)
  end
  return table.concat(parts)
end

local function role_syntax(name, role)
  local attrs = {}
  if role.kind and role.kind ~= "" then attrs[#attrs + 1] = "kind = " .. string.format("%q", tostring(role.kind)) end
  if role.algebra and role.algebra ~= "" then attrs[#attrs + 1] = "algebra = " .. string.format("%q", tostring(role.algebra)) end
  if role.item_role and role.item_role ~= "" then attrs[#attrs + 1] = "item = " .. string.format("%q", tostring(role.item_role)) end
  if role.payload_role and role.payload_role ~= "" then attrs[#attrs + 1] = "payload = " .. string.format("%q", tostring(role.payload_role)) end
  if #attrs == 0 then return "role. " .. tostring(name) end
  return "role. " .. tostring(name) .. " { " .. table.concat(attrs, ", ") .. " }"
end

local function slot_fact(slot)
  local channels = table.concat(slot.channels or {}, ",")
  local text = "`" .. md_escape(slot_syntax(slot)) .. "` -> `" .. md_escape(slot.name) .. "`"
    .. " role=`" .. md_escape(slot.role) .. "`"
  if channels ~= "" then text = text .. " channel=`" .. md_escape(channels) .. "`" end
  if slot.optional then text = text .. " optional" end
  return text
end

function llbl.markdown_dialect(lang, opts)
  opts = opts or {}
  local out = {}
  out[#out + 1] = md_header(opts.level or 2, opts.title or (lang and lang.name or "Dialect"))
  out[#out + 1] = ""
  if not is_tag(lang, "Dialect") then
    out[#out + 1] = "No LLBL dialect metadata is available."
    out[#out + 1] = ""
    return table.concat(out, "\n")
  end

  local exports = sorted_keys(lang.exports or {})
  markdown_list("### Exports", exports, out)

  out[#out + 1] = "### Roles"
  out[#out + 1] = ""
  local role_names = sorted_pairs_keys(lang.roles or {})
  if #role_names > 0 then
    out[#out + 1] = "```lua"
    for _, name in ipairs(role_names) do
      out[#out + 1] = role_syntax(name, llbl.describe_role(lang, name) or {})
    end
    out[#out + 1] = "```"
    out[#out + 1] = ""
  end
  for _, name in ipairs(role_names) do
    local r = llbl.describe_role(lang, name) or {}
    local line = "- `" .. md_escape(name) .. "`"
    local attrs = {}
    if r.kind and r.kind ~= "" then attrs[#attrs + 1] = "kind=" .. tostring(r.kind) end
    if r.algebra and r.algebra ~= "" then attrs[#attrs + 1] = "algebra=" .. tostring(r.algebra) end
    if r.item_role and r.item_role ~= "" then attrs[#attrs + 1] = "item=" .. tostring(r.item_role) end
    if r.payload_role and r.payload_role ~= "" then attrs[#attrs + 1] = "payload=" .. tostring(r.payload_role) end
    if #attrs > 0 then line = line .. " — " .. table.concat(attrs, ", ") end
    out[#out + 1] = line
  end
  if #role_names == 0 then out[#out + 1] = "- none" end
  out[#out + 1] = ""

  out[#out + 1] = "### Heads"
  out[#out + 1] = ""
  for _, name in ipairs(sorted_pairs_keys(lang.heads or {})) do
	    local h = llbl.describe_head(lang, name)
	    out[#out + 1] = "#### `" .. md_escape(name) .. "`"
	    out[#out + 1] = ""
	    if h and h.documentation and h.documentation ~= "" then
	      out[#out + 1] = h.documentation
	      out[#out + 1] = ""
	    end
	    out[#out + 1] = "```lua"
	    out[#out + 1] = head_syntax(name, h)
	    out[#out + 1] = "```"
    out[#out + 1] = ""
    local slots = (h and h.slots) or {}
    if #slots > 0 then
      out[#out + 1] = "Slots:"
      out[#out + 1] = ""
      for _, slot in ipairs(slots) do
        out[#out + 1] = "- " .. slot_fact(slot)
      end
    else
      out[#out + 1] = "Slots: none"
    end
    if h and #(h.traits or {}) > 0 then
      out[#out + 1] = ""
      out[#out + 1] = "Traits: `" .. table.concat(h.traits, "`, `") .. "`"
    end
    out[#out + 1] = ""
  end
  if next(lang.heads or {}) == nil then
    out[#out + 1] = "- none"
    out[#out + 1] = ""
  end

  local passes = {}
  for i = 1, #(lang.passes or {}) do passes[i] = lang.passes[i].name or ("pass" .. tostring(i)) end
  markdown_list("### Passes", passes, out)
  return table.concat(out, "\n")
end

function llbl.markdown(value, opts)
  opts = opts or {}
  if is_tag(value, "Language") then return Language.markdown(value, opts) end
  if is_tag(value, "Dialect") then return llbl.markdown_dialect(value, opts) end
  local desc = llbl.describe(value)
  return "```lua\n" .. repr(desc or value) .. "\n```\n"
end

local function member_tooling_names(member)
  local xs = {}
  for _, name in ipairs({ "format", "diagnostics", "index", "markdown", "match" }) do
    if type(member[name]) == "function" then xs[#xs + 1] = name end
  end
  return xs
end

local function append_llbl_syntax_primer(out)
  out[#out + 1] = "## LLBL Syntax Model"
  out[#out + 1] = ""
  out[#out + 1] = "All dialects in this language are ordinary Lua values built through the shared LLBL substrate. Lua provides the syntax; LLBL gives that syntax dialect meaning through heads, roles, slots, fragments, origins, environments, and language zones."
  out[#out + 1] = ""
  out[#out + 1] = "Core forms:"
  out[#out + 1] = ""
  out[#out + 1] = "- `namespace.head. name` uses Lua field lookup through an LLBL namespace to feed a name slot, for example `lalin.fn. add` or `llpvm.task. compile`."
  out[#out + 1] = "- `value [Type]` uses Lua indexing to attach a type or computed slot, for example `a [lalin.i32]`."
  out[#out + 1] = "- `head { ... }` uses Lua calls and tables to feed product, body, declaration, protocol, or record slots."
  out[#out + 1] = "- `name = value` inside a table remains native Lua record syntax and is used for record/fill/map-shaped data."
  out[#out + 1] = "- `_ (fragment)` splices a role-shaped fragment into the surrounding role."
  out[#out + 1] = "- `left .. right` concatenates compatible product/list fragments or language zones."
  out[#out + 1] = "- `left + right` composes compatible sum/protocol alternatives."
  out[#out + 1] = "- `left * right` decorates sum/protocol alternatives with product-shaped payloads when the dialect role supports it."
  out[#out + 1] = "- `lalin { ... }`, `llpvm { ... }`, `asdl { ... }`, and similar forms call LLBL namespace values to create language zones: explicit dialect scopes inside one Lua value."
  out[#out + 1] = ""
  out[#out + 1] = "In language environments, member DSLs are exposed through LLBL namespace values. The namespace is a semantic owner, not just a Lua table: tools can describe it, document it, and use its call form for zones."
  out[#out + 1] = ""
  out[#out + 1] = "The dot belongs visually to the keyword side. Canonical LLBL style is `lalin.fn. add`, not `lalin.fn .add`: the keyword/head is the syntactic operator, while the name stays clean."
  out[#out + 1] = ""
  out[#out + 1] = "There is no parser, tokenizer, antiquote layer, or string dialect hidden here. A source file evaluates as Lua; the resulting values already contain enough LLBL metadata for diagnostics, formatting, indexing, documentation, and dialect-specific lowering."
  out[#out + 1] = ""
end

function Language:markdown(opts)
  opts = opts or {}
  local out = {}
  out[#out + 1] = md_header(1, opts.title or (self.name .. " Language Reference"))
  out[#out + 1] = ""
  out[#out + 1] = "Generated from LLBL language introspection."
  out[#out + 1] = ""
  append_llbl_syntax_primer(out)
  out[#out + 1] = "## Language"
  out[#out + 1] = ""
  out[#out + 1] = "- Name: `" .. md_escape(self.name) .. "`"
  out[#out + 1] = "- Collision policy: `" .. md_escape(self.collision or "error") .. "`"
  out[#out + 1] = ""
  markdown_list("### Provides", array_copy(self.provides or {}), out)
  markdown_list("### Requires", array_copy(self.requires or {}), out)
  markdown_list("### Shared names", sorted_keys(self.shared or {}), out)
  markdown_list("### Reserved names", sorted_keys(self.reserved or {}), out)
  append_language_audit_markdown(self, out)

  out[#out + 1] = "## Members"
  out[#out + 1] = ""
  out[#out + 1] = "```lua"
  for _, member in ipairs(self.members or {}) do
    out[#out + 1] = "member. " .. language_member_name(member) .. " {"
    local provides = table.concat(member.provides or {}, ", ")
    local requires = table.concat(member.requires or {}, ", ")
    local tooling = table.concat(member_tooling_names(member), ", ")
    local owns = table.concat(semantic_list(member, "owns"), ", ")
    local uses = table.concat(semantic_list(member, "uses"), ", ")
    if provides ~= "" then out[#out + 1] = "  provides { " .. provides .. " }" end
    if requires ~= "" then out[#out + 1] = "  requires { " .. requires .. " }" end
    if owns ~= "" then out[#out + 1] = "  owns { " .. owns .. " }" end
    if uses ~= "" then out[#out + 1] = "  uses { " .. uses .. " }" end
    if tooling ~= "" then out[#out + 1] = "  tooling { " .. tooling .. " }" end
    out[#out + 1] = "}"
  end
  out[#out + 1] = "```"
  out[#out + 1] = ""

  out[#out + 1] = "## Zones"
  out[#out + 1] = ""
  out[#out + 1] = "Zones are semantic partitions inside language values. Each member may expose a zone head such as `lalin { ... }` or `llpvm { ... }`."
  out[#out + 1] = ""

  out[#out + 1] = "## Tooling"
  out[#out + 1] = ""
  out[#out + 1] = "- `language.format(value, opts)`"
  out[#out + 1] = "- `language.diagnostics(value, opts)`"
  out[#out + 1] = "- `language.index(value, opts)`"
  out[#out + 1] = "- `language.audit()`"
  out[#out + 1] = "- `language.markdown(opts)`"
  out[#out + 1] = ""

  out[#out + 1] = "## Member References"
  out[#out + 1] = ""
  for _, member in ipairs(self.members or {}) do
    if type(member.markdown) == "function" then
      local ok, text = pcall(member.markdown, member, opts, self)
      if ok then out[#out + 1] = tostring(text)
      else
        out[#out + 1] = md_header(2, language_member_name(member))
        out[#out + 1] = ""
        out[#out + 1] = "Documentation hook failed: `" .. md_escape(text) .. "`"
      end
    elseif member.dialect then
      out[#out + 1] = llbl.markdown_dialect(member.dialect, { level = 2, title = language_member_name(member) })
    else
      out[#out + 1] = md_header(2, language_member_name(member))
      out[#out + 1] = ""
      out[#out + 1] = "No dialect metadata is available."
      out[#out + 1] = ""
    end
  end
  return table.concat(out, "\n")
end

function Language:write_markdown(path, opts)
  local text = Language.markdown(self, opts)
  local f = assert(io.open(path, "wb"))
  f:write(text)
  f:close()
  return text
end

function Language:describe()
  local members = {}
  for i, member in ipairs(self.members or {}) do
    members[i] = {
      name = member.name or (member.dialect and member.dialect.name),
      provides = array_copy(member.provides or {}),
      requires = array_copy(member.requires or {}),
      semantics = {
        owns = semantic_list(member, "owns"),
        uses = semantic_list(member, "uses"),
        resolves = semantic_list(member, "resolves"),
        formats = semantic_list(member, "formats"),
        indexes = semantic_list(member, "indexes"),
        lowers = semantic_list(member, "lowers"),
        materializes = semantic_list(member, "materializes"),
        notes = array_copy(member_semantics(member).notes or {}),
      },
    }
  end
  return {
    tag = "Language",
    name = self.name,
    members = members,
    provides = array_copy(self.provides or {}),
    requires = array_copy(self.requires or {}),
    reserved = sorted_keys(self.reserved or {}),
    shared = sorted_keys(self.shared or {}),
    prefer = shallow_copy(self.preferences or {}),
    audit = Language.audit(self),
  }
end

function Language:compose(other, opts)
  other = language_of(other)
  opts = opts or {}
  if opts.name == nil and opts.prefer == nil then
    if #(self.members or {}) == 1 and tostring((self.members or {})[1].name or "") == LLBL_CORE_MEMBER then return other end
    if #(other.members or {}) == 1 and tostring((other.members or {})[1].name or "") == LLBL_CORE_MEMBER then return self end
  end
  local members = array_copy(self.members or {})
  append(members, other.members or {})
  local spec = language_spec_from(self, { members = members, prefer = opts.prefer })
  append(spec.reserved, sorted_keys(other.reserved or {}))
  append(spec.shared, sorted_keys(other.shared or {}))
  return language_define(opts.name or (self.name .. "+" .. other.name), spec)
end

function Language:subtract(member_or_name, opts)
  opts = opts or {}
  local remove = {}
  if is_tag(member_or_name, "Language") then
    for _, member in ipairs(member_or_name.members or {}) do remove[tostring(member.name or (member.dialect and member.dialect.name))] = true end
  elseif is_tag(member_or_name, "Dialect") then
    remove[tostring(member_or_name.name)] = true
  else
    remove[tostring(member_or_name)] = true
  end
  local members = {}
  for _, member in ipairs(self.members or {}) do
    local name = tostring(member.name or (member.dialect and member.dialect.name))
    if not remove[name] then members[#members + 1] = member end
  end
  return language_define(opts.name or (self.name .. "-projected"), language_spec_from(self, { members = members }))
end

function Language:only(names, opts)
  opts = opts or {}
  local keep = list_to_set(names or {})
  local members = {}
  for _, member in ipairs(self.members or {}) do
    local name = tostring(member.name or (member.dialect and member.dialect.name))
    local yes = keep[name]
    if not yes then
      for _, cap in ipairs(member.provides or {}) do if keep[tostring(cap)] then yes = true end end
    end
    if yes then members[#members + 1] = member end
  end
  return language_define(opts.name or (self.name .. ".only"), language_spec_from(self, { members = members }))
end

function Language:prefer(map, opts)
  opts = opts or {}
  return language_define(opts.name or (self.name .. ".prefer"), language_spec_from(self, { prefer = map or {} }))
end

Language.__concat = function(a, b) return Language.compose(language_of(a), b) end
Language.__add = Language.__concat
Language.__sub = function(a, b) return Language.subtract(language_of(a), b) end
Dialect.__concat = function(a, b) return Language.compose(language_of(a), b) end
Dialect.__add = Dialect.__concat
Dialect.__sub = function(a, b) return Language.subtract(language_of(a), b) end

function Dialect:fragment(role, value)
  local spec = self.roles and self.roles[role] or {}
  return llbl.fragment(role, normalize_role({ dialect = self, origin = source.capture("fragment-normalize") }, role, value), source.capture("fragment"), {
    dialect = self,
    role_spec = spec,
    algebra = spec.algebra,
    payload_role = spec.payload_role or spec.payload,
  })
end
function Dialect:env(opts)
  opts = shallow_copy(opts or {})
  if opts.env then opts.exports = opts.env end
  opts.scope = opts.scope or "env"
  opts.auto_names = opts.auto_names ~= false
  local session = Language.use(self:language(), opts)
  return session.env
end
function Dialect:language()
  -- A dialect's language is not optional. It is the singleton language containing
  -- the llbl root member plus this dialect member.
  if not self.__llbl_language then self.__llbl_language = language_define(self.name, { language_member_from_dialect(self) }) end
  return self.__llbl_language
end
function Dialect:use(opts) return Language.use(self:language(), opts or {}) end
function Dialect:with_use(opts, fn)
  opts = shallow_copy(opts or {})
  opts.scope = opts.scope or "scoped"
  local session = self:use(opts)
  local ok, a, b, c = pcall(fn, session.env, session)
  session:close()
  if not ok then error(a, 0) end
  return a, b, c
end
function Dialect:loadstring(src, chunkname, opts) return Language.loadstring(self:language(), src, chunkname or self.name, opts) end
function Dialect:loadfile(path, opts) local f, err = io.open(path, "rb"); if not f then error(err, 2) end; local src = f:read("*a") or ""; f:close(); return self:loadstring(src, "@" .. path, opts) end
function Dialect:analyze_string(src, chunkname, opts)
  opts = opts or {}; local bag = llbl.diagnostics(); source.register(chunkname or self.name, src)
  local f, err = compile_lua(src, chunkname or self.name)
  if not f then bag:error { code = "E_LUA_PARSE", message = tostring(err) }; return setmetatable({ __llbl_tag = "Analysis", dialect = self, ast = nil, diagnostics = bag, source = src, chunkname = chunkname }, Analysis) end
  setfenv0(f, self:env(opts)); local ok, ast = pcall(f)
  if not ok then
    if is_tag(ast, "Diagnostic") then bag:add(ast)
    else bag:error { code = "E_DSL_EXEC", message = tostring(ast) } end
    return setmetatable({ __llbl_tag = "Analysis", dialect = self, ast = nil, diagnostics = bag, source = src, chunkname = chunkname }, Analysis)
  end
  local analysis = setmetatable({ __llbl_tag = "Analysis", dialect = self, ast = ast, diagnostics = bag, source = src, chunkname = chunkname }, Analysis)
  local ctx = llbl.context(self, { diagnostics = bag, fatal = false, mode = opts.mode })
  for i = 1, #self.passes do
    local pass = self.passes[i]
    if pass.run then local okp, perr = pcall(pass.run, ctx, analysis); if not okp then bag:error { code = "E_PASS", message = "pass " .. tostring(pass.name) .. " failed: " .. tostring(perr), primary = origin_of(ast) } end end
  end
  return analysis
end
function Dialect:analyze_file(path, opts) local f, err = io.open(path, "rb"); if not f then local bag = llbl.diagnostics(); bag:error { code = "E_OPEN", message = tostring(err) }; return setmetatable({ __llbl_tag = "Analysis", dialect = self, ast = nil, diagnostics = bag }, Analysis) end; local src = f:read("*a") or ""; f:close(); return self:analyze_string(src, "@" .. path, opts) end

function llbl.describe_role(lang, name)
  if is_tag(lang, "Dialect") then
    local spec = lang.roles and lang.roles[name]
    if not spec then return nil end
    return {
      tag = "Role",
      name = name,
      kind = spec.kind or name,
      algebra = spec.algebra,
      item_role = spec.item_role or spec.item,
      payload_role = spec.payload_role or spec.payload,
      unique_names = spec.unique_names,
      region = is_tag(spec.region, "Region") and llbl.describe_region(spec.region) or nil,
      has_region = is_tag(spec.region, "Region"),
      has_check = type(spec.check) == "function",
      has_format = type(spec.format) == "function",
      origin = spec.origin,
    }
  end
  return nil
end

function llbl.describe_head(lang, name)
  if is_tag(lang, "Dialect") then
    local spec = lang.heads and lang.heads[name]
    if not spec then return nil end
    local slots = {}
    for i = 1, #(spec.slots or {}) do
      local s = spec.slots[i]
      slots[i] = {
        name = s.name,
        role = s.role,
        channels = slot_channels(lang, s),
        optional = s.optional,
        default = s.default,
        label = s.label,
        origin = s.origin,
      }
    end
    return {
      tag = "Head",
      name = spec.name,
      node_tag = spec.tag,
      protocol = "staged_head",
      slots = slots,
      traits = array_copy(spec.traits or {}),
      has_emit = type(spec.emit) == "function",
      has_check = type(spec.check) == "function",
      has_format = type(spec.format) == "function",
      origin = spec.origin,
      documentation = spec.origin and spec.origin.leading_comment or nil,
    }
  end
  return nil
end

function llbl.describe_fragment(fragment_value)
  if not is_tag(fragment_value, "Fragment") then return nil end
  return {
    tag = "Fragment",
    role = fragment_value.role,
    algebra = fragment_algebra(fragment_value),
    count = #(fragment_value.items or {}),
    items = fragment_value.items or {},
    origin = fragment_value.origin,
    role_spec = fragment_value.role_spec,
    payload_role = fragment_value.payload_role,
  }
end

function llbl.describe_curried(form)
  if not is_tag(form, "Curried") then return nil end
  local args = array_copy(form.args or {})
  return {
    tag = "Curried",
    name = form.name,
    arity = form.arity,
    applied = #args,
    holes = llbl._curried_first_hole(args) ~= nil,
    args = args,
    static = array_copy(form.static or {}),
    origin = form.origin,
  }
end

function llbl.describe_zone(zone)
  if not is_tag(zone, "Zone") then return nil end
  return {
    tag = "Zone",
    language = zone.language,
    member = zone.member,
    name = zone.name,
    role = zone.role,
    count = #(zone.items or {}),
    items = zone.items or {},
    origin = zone.origin,
    metadata = zone.metadata,
  }
end

function llbl.describe_language_bundle(bundle)
  if not is_tag(bundle, "LanguageBundle") then return nil end
  local zones = {}
  for i, z in ipairs(bundle.zones or {}) do zones[i] = llbl.describe_zone(z) end
  return {
    tag = "LanguageBundle",
    language = bundle.language,
    zones = zones,
    count = #(bundle.zones or {}),
    origin = bundle.origin,
  }
end

function llbl.describe_namespace(ns)
  if not is_tag(ns, "Namespace") then return nil end
  local exports = {}
  for k, v in pairs(ns) do
    if type(k) == "string" and k:sub(1, 2) ~= "__" and k ~= "language" and k ~= "member" and k ~= "name" and k ~= "origin" and k ~= "metadata" and k ~= "zone" and k ~= "default_head" then
      exports[#exports + 1] = k
    end
  end
  table.sort(exports)
  return {
    tag = "Namespace",
    language = ns.language,
    member = ns.member,
    name = ns.name,
    exports = exports,
    callable = ns.zone ~= nil,
    default_head = ns.default_head ~= nil,
    origin = ns.origin,
    metadata = ns.metadata,
  }
end

function llbl.describe(value)
  if is_tag(value, "Dialect") then
    local roles, heads, traits, protocols, passes = {}, {}, {}, {}, {}
    for name in pairs(value.roles or {}) do roles[#roles + 1] = name end
    for name in pairs(value.heads or {}) do heads[#heads + 1] = name end
    for name in pairs(value.traits or {}) do traits[#traits + 1] = name end
    for name in pairs(value.protocols or {}) do protocols[#protocols + 1] = name end
    for i = 1, #(value.passes or {}) do passes[i] = value.passes[i].name end
    table.sort(roles); table.sort(heads); table.sort(traits); table.sort(protocols)
    return { tag = "Dialect", name = value.name, roles = roles, heads = heads, traits = traits, protocols = protocols, passes = passes }
  end
  if is_tag(value, "Event") then return llbl.describe_event(value) end
  if is_tag(value, "Process") then return llbl.describe_process(value) end
  if is_tag(value, "Gps") and value.describe then return value:describe() end
  if is_tag(value, "GpsPlan") and value.describe then return value:describe() end
  if is_tag(value, "Gps") or is_tag(value, "GpsPlan") or is_tag(value, "GpsSource") or is_tag(value, "GpsOp") then return llbl.gps.describe(value) end
  if is_tag(value, "ProcessEvent") then return { tag = "ProcessEvent", process = value.process, kind = value.kind, seq = value.seq, origin = value.origin } end
  if is_tag(value, "Fragment") then return llbl.describe_fragment(value) end
  if is_tag(value, "Curried") then return llbl.describe_curried(value) end
  if is_tag(value, "Binding") then
    return {
      tag = "Binding",
      kind = value.kind,
      name = value.name,
      owner = value.owner,
      language = value.language,
      generated = value.generated and true or false,
      unresolved = value.kind == "unresolved",
      origin = value.origin,
    }
  end
  if is_tag(value, "Zone") then return llbl.describe_zone(value) end
  if is_tag(value, "LanguageBundle") then return llbl.describe_language_bundle(value) end
  if is_tag(value, "Namespace") then return llbl.describe_namespace(value) end
  if is_tag(value, "Exit") then return llbl.describe_exit(value) end
  if is_tag(value, "Protocol") then return llbl.describe_protocol(value) end
  if is_tag(value, "Region") then return llbl.describe_region(value) end
  if is_tag(value, "UseSession") and value.describe then return value:describe() end
  if is_tag(value, "Head") then return llbl.describe_head(value.dialect, value.spec and value.spec.name) end
  if is_tag(value, "Node") then
    local meta = rawget(value, "__llbl") or {}
    return {
      tag = "Node",
      node_tag = value.tag,
      head = meta.head,
      dialect = meta.dialect,
      fields = meta.fields or value.fields,
      events = meta.events,
      origin = value.origin,
    }
  end
  if is_tag(value, "Stage") then
    return {
      tag = "Stage",
      head = value.head and value.head.name or nil,
      next_index = value.next_index,
      missing = stage_missing_slots(value),
      events = value.events,
      origin = value.origin,
    }
  end
  return llbl.describe_shape(value)
end

function Dialect:describe() return llbl.describe(self) end
function Dialect:describe_head(name) return llbl.describe_head(self, name) end
function Dialect:describe_role(name) return llbl.describe_role(self, name) end

function Dialect:install_searcher(opts)
  opts = opts or {}
  local searchers = package.searchers or package.loaders
  if not searchers then return false end
  if self._llbl_searcher then
    for _, s in ipairs(searchers) do if s == self._llbl_searcher then return true end end
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
  self._llbl_searcher = searcher
  table.insert(searchers, searcher)
  return true
end

local function head_check_pass()
  return { name = "llbl.head_checks", run = function(ctx, analysis)
    walk(analysis.ast, function(n)
      if not is_tag(n, "Node") then return end
      local m = n.__llbl or {}; local hs = m.head_spec
      if hs and hs.check then local ok, err = pcall(hs.check, ctx, n, m.fields or {}, m); if not ok then ctx:error { code = "E_CHECK", message = tostring(err), primary = n.origin } end end
    end)
  end }
end

local function trait_name(t)
  return is_tag(t, "TraitRef") and t.name or (is_tag(t, "TraitDecl") and t.name or tostring(t))
end

local function define_dialect(name, decls)
  -- llbl.dialect compiles declarative grammar objects into a runtime Dialect.
  -- Runtime heads are ordinary Lua values with metatables that consume
  -- dot/index/call/table shapes through the slot machine above.
  local lang = setmetatable({ __llbl_tag = "Dialect", name = tostring(name), roles = builtin_roles(), heads = {}, traits = {}, protocols = {}, exports = { N = llbl.N, spread = llbl.spread, _ = llbl._, hole = llbl.hole, curried = llbl.curried, curry = llbl.curried }, passes = {}, lsp = {}, declarations = decls or {} }, Dialect)
  for i = 1, #(decls or {}) do
    local d = decls[i]
    if is_tag(d, "RoleDecl") then local spec = shallow_copy(d.spec or {}); spec.kind = d.kind or spec.kind or "array"; spec.origin = d.origin; lang.roles[d.name] = spec
    elseif is_tag(d, "TraitDecl") then local spec = shallow_copy(d.spec or {}); spec.origin = d.origin; lang.traits[d.name] = spec
    elseif is_tag(d, "ProtocolDecl") then local spec = shallow_copy(d.spec or {}); spec.origin = d.origin; lang.protocols[d.name] = llbl.protocol(d.name, spec)
    elseif is_tag(d, "ScalarDecl") then lang.exports[d.name] = llbl.type(d.name, { kind = "scalar", spec = d.spec or {}, origin = d.origin })
    elseif is_tag(d, "TypeCtorDecl") then lang.exports[d.name] = llbl.type_ctor(d.name, { arity = d.arity or 1, emit = d.emit, origin = d.origin })
    elseif is_tag(d, "HelperDecl") then lang.exports[d.name] = d.value
    elseif is_tag(d, "PassDecl") then lang.passes[#lang.passes + 1] = d
    elseif is_tag(d, "LspDecl") then lang.lsp[d.name] = d.spec or {}
    elseif is_tag(d, "TypeSystemDecl") then lang.type_system = d.spec or {} end
  end
  for role in pairs(lang.roles) do if not lang.exports[role] then lang.exports[role] = function(tbl) return lang:fragment(role, tbl) end end end
  for k, v in pairs(DEFAULT_EXPORTS) do lang.exports[k] = lang.exports[k] or v end
  for i = 1, #(decls or {}) do
    local d = decls[i]
    if is_tag(d, "HeadDecl") then
      local slots = {}; for j = 1, #d.slots do slots[j] = normalize_slot_decl(d.slots[j]) end
      validate_slot_ambiguity(lang, d.name, slots)
      local traits = {}
      for j = 1, #(d.traits or {}) do traits[j] = trait_name(d.traits[j]) end
      local spec = { name = d.name, tag = d.tag or d.name, slots = slots, traits = traits, emit = d.emit, check = d.check, lower = d.lower, lsp = d.lsp, format = d.format, origin = d.origin, raw = d }
      for j = 1, #traits do
        local ts = lang.traits[traits[j]]
        if ts and ts.apply then ts.apply(lang, spec, ts) end
      end
      lang.heads[d.name] = spec; lang.exports[d.name] = runtime_head(lang, spec)
    end
  end
  table.insert(lang.passes, 1, head_check_pass())
  llbl.codegen.compile_dialect(lang, { mode = "fast" })
  llbl.codegen.compile_heads(lang, { mode = "fast" })
  llbl.dialects = llbl.dialects or {}
  llbl.dialects[lang.name] = lang
  lang.__llbl_language = language_define(lang.name, { language_member_from_dialect(lang) })
  return lang
end
function llbl.dialect(name) return function(decls) return define_dialect(name, decls) end end
llbl.Dialect = Dialect

-- ---------------------------------------------------------------------------
-- Formatting
-- ---------------------------------------------------------------------------
--
-- Formatting is semantic, not source-preserving. LLBL formats evaluated values:
-- fragments, heads, expressions, tables, and dialect-specific nodes through
-- hooks. Origin-leading comments may be surfaced as documentation, but exact
-- original token layout is outside this layer; dialect formatters can add
-- richer behavior on top.

local doc = {}
llbl.doc = doc

local function is_doc(v)
  return type(v) == "table" and rawget(v, "__llbl_doc") ~= nil
end

local function doc_node(kind, fields)
  fields = fields or {}
  fields.__llbl_doc = kind
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
  local k = rawget(d, "__llbl_doc")
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
  local k = rawget(d, "__llbl_doc")
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

local function render_region_push(stack, frame)
  stack[#stack + 1] = frame
end

local function render_region_gen(param, state)
  state = state or {
    stack = {
      {
        doc = docify(param.doc),
        flat = false,
        indent = param.base_indent,
      },
    },
    col = param.base_indent,
  }
  local stack = state.stack
  while #stack > 0 do
    local frame = stack[#stack]
    stack[#stack] = nil
    local d = docify(frame.doc)
    local k = rawget(d, "__llbl_doc")
    local indent = frame.indent or param.base_indent
    local flat = frame.flat
    if k == "nil" then
      -- no payload
    elseif k == "text" then
      local s = d.text or ""
      state.col = state.col + #s
      return state, s
    elseif k == "line" or k == "softline" then
      if flat then
        state.col = state.col + 1
        return state, " "
      end
      state.col = indent
      return state, "\n" .. string.rep(" ", indent)
    elseif k == "hardline" then
      state.col = indent
      return state, "\n" .. string.rep(" ", indent)
    elseif k == "concat" then
      local parts = d.parts or {}
      for i = #parts, 1, -1 do
        render_region_push(stack, { doc = parts[i], flat = flat, indent = indent })
      end
    elseif k == "indent" then
      render_region_push(stack, {
        doc = d.doc,
        flat = flat,
        indent = indent + (d.amount or param.indent_width),
      })
    elseif k == "group" then
      local next_flat = flat or (state.col + flat_len(d.doc) <= param.width)
      render_region_push(stack, { doc = d.doc, flat = next_flat, indent = indent })
    end
  end
  return nil
end

function llbl.render_region(d, opts)
  opts = opts or {}
  return llbl.gps.raw(llbl.gps.wrap(render_region_gen, {
    doc = d,
    width = opts.width or 100,
    base_indent = opts.base_indent or 0,
    indent_width = opts.indent or 2,
  }, nil, { kind = "format:render" }))
end

function llbl.render(d, opts)
  opts = opts or {}
  local chunks = {}
  llbl.gps.each(function(chunk) chunks[#chunks + 1] = chunk end, llbl.render_region(d, opts))
  return table.concat(chunks)
end

local FormatContext = {}
FormatContext.__index = FormatContext
llbl.FormatContext = FormatContext

local function format_context(opts)
  opts = opts or {}
  local f = setmetatable({
    opts = opts,
    dialect = opts.dialect,
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
function FormatContext:format(v) return llbl.to_doc(v, self) end

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

local function dialect_format_spec(lang)
  if type(lang) ~= "table" then return nil end
  if type(lang.format) == "table" then return lang.format end
  return nil
end

local function formatting_dialect(f, meta)
  if type(f.dialect) == "table" then return f.dialect end
  local name = meta and meta.dialect
  return name and llbl.dialects and llbl.dialects[name] or nil
end

local function dialect_namespace(lang, meta)
  local fmt = dialect_format_spec(lang)
  if fmt and fmt.namespace then return tostring(fmt.namespace) end
  local name = (type(lang) == "table" and lang.name) or (meta and meta.dialect) or "llbl"
  name = tostring(name)
  return name:match("([^.]+)$") or name
end

local function dialect_slot_formatter(lang, meta, slot)
  local fmt = dialect_format_spec(lang)
  if not fmt then return nil end
  local by_head = fmt.head_slot_formatters and meta and meta.head and fmt.head_slot_formatters[meta.head]
  if by_head and by_head[slot.name] then return by_head[slot.name] end
  return fmt.slot_formatters and fmt.slot_formatters[slot.role] or nil
end

local function head_slot_value(meta, slot)
  local raw = meta.raw or {}
  local fields = meta.fields or {}
  if slot.role == "identity" or slot.role == "value" then return raw[slot.name] end
  return fields[slot.name]
end

local function default_slot_doc(f, slot, value, event)
  local action = event and event.action
  local role = slot.role
  if action == "index" then return doc.group { " [", f:format(value), "]" } end
  if action == "call" then
    if (event.argc or 0) == 0 then return doc.text("()") end
    if role == "string" then return doc.group { " ", f:format(value) } end
    if event.channel == llbl.channel.call_table then return doc.group { " ", f:format(value) } end
    return doc.group { " (", f:format(value), ")" }
  end
  return doc.group { " ", f:format(value) }
end

local function generic_head_doc(v, f, meta)
  local hs = meta and meta.head_spec
  if not hs then return nil end
  local lang = formatting_dialect(f, meta)
  local ns = dialect_namespace(lang, meta)
  local raw, events = meta.raw or {}, meta.events or {}
  local slots = hs.slots or {}
  local parts = { ns, ".", tostring(hs.name) }
  local skip = {}

  for i = 1, #slots do
    local slot = slots[i]
    if slot.name == "name" and raw[slot.name] ~= nil then
      skip[slot.name] = true
      local event = events[slot.name] or {}
      if event.action == "index" then
        parts[#parts + 1] = " ["
        parts[#parts + 1] = f:format(raw[slot.name])
        parts[#parts + 1] = "]"
      else
        parts[#parts + 1] = ". "
        parts[#parts + 1] = f:name(raw[slot.name])
      end
      break
    end
  end

  for i = 1, #slots do
    local slot = slots[i]
    if not skip[slot.name] then
      local event = events[slot.name]
      local value = head_slot_value(meta, slot)
      if value ~= nil then
        local hook = dialect_slot_formatter(lang, meta, slot)
        local rendered = hook and hook(value, f, slot, meta)
        rendered = rendered and docify(rendered) or f:format(value)
        if event and event.action == "index" then
          parts[#parts + 1] = " ["
          parts[#parts + 1] = rendered
          parts[#parts + 1] = "]"
        elseif event and event.action == "call" then
          if (event.argc or 0) == 0 then
            parts[#parts + 1] = "()"
          elseif slot.role == "string" or event.channel == llbl.channel.call_table then
            parts[#parts + 1] = " "
            parts[#parts + 1] = rendered
          else
            parts[#parts + 1] = " ("
            parts[#parts + 1] = rendered
            parts[#parts + 1] = ")"
          end
        else
          parts[#parts + 1] = default_slot_doc(f, slot, rendered, event)
        end
      end
    end
  end
  return doc.group(parts)
end

local function dialect_role_doc(v, f, meta)
  local fmt = dialect_format_spec(formatting_dialect(f, meta))
  if not fmt or not fmt.role_of or not fmt.role_formatters then return nil end
  local role_name = fmt.role_of(v, f, meta)
  local hook = role_name and fmt.role_formatters[role_name]
  if hook then return hook(v, f, meta) end
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
    local m = rawget(v, "__llbl") or {}
    local d = generic_head_doc(v, f, m)
    if d then return d end
    return doc.group { tostring(m.head or v.tag or "node"), " ", f:braced_list(m.fields or v.fields or {}) }
  end

  local keys = {}
  for k in pairs(v) do
    if k ~= "__llbl" and k ~= "__llbl_tag" and k ~= "origin" then keys[#keys + 1] = k end
  end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  local items = {}
  for i = 1, #keys do
    local k = keys[i]
    items[i] = doc.group { tostring(k), " = ", f:format(v[k]) }
  end
  return f:braced_list(items)
end

function llbl.to_doc(v, ctx)
  local f = getmetatable(ctx) == FormatContext and ctx or format_context(ctx or {})
  local lit = literal_doc(v)
  if lit then return lit end

  local tv = type(v)
  if tv ~= "table" then return doc.text(tostring(v)) end
  if f.seen[v] then return doc.text("<cycle>") end
  f.seen[v] = true

  local mt = getmetatable(v)
  local mt_format = mt and rawget(mt, "__llbl_format")
  if mt_format then
    local out = mt_format(v, f)
    f.seen[v] = nil
    return docify(out)
  end

  local meta = rawget(v, "__llbl") or {}
  local hs = meta.head_spec
  if hs and hs.format then
    local out = hs.format(v, f, meta)
    f.seen[v] = nil
    return docify(out)
  end

  if hs then
    local out = generic_head_doc(v, f, meta)
    if out then
      f.seen[v] = nil
      return docify(out)
    end
  end

  if tagof(v) == "Fragment" then
    local rs = rawget(v, "role_spec")
    if rs and rs.format then
      local out = rs.format(v, f)
      f.seen[v] = nil
      return docify(out)
    end
  end

  do
    local out = dialect_role_doc(v, f, meta)
    if out then
      f.seen[v] = nil
      return docify(out)
    end
  end

  local lang = f.dialect or meta.dialect
  if type(lang) == "table" then
    local formatters = lang.formatters or (type(lang.format) == "table" and lang.format.formatters or nil)
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

function llbl.format_doc(value, opts)
  return llbl.to_doc(value, format_context(opts or {}))
end

function llbl.format_region(value, opts)
  opts = opts or {}
  return llbl.render_region(llbl.format_doc(value, opts), opts)
end

function llbl.format(value, opts)
  opts = opts or {}
  local chunks = {}
  llbl.gps.each(function(chunk) chunks[#chunks + 1] = chunk end, llbl.format_region(value, opts))
  return table.concat(chunks)
end

llbl.shared.formatting = llbl.shared.formatting or {
  doc = llbl.doc,
  to_doc = llbl.format_doc,
  render_region = llbl.render_region,
  render = llbl.render,
  format_region = llbl.format_region,
  format = llbl.format,
}

function Dialect:format_doc(value, opts)
  opts = shallow_copy(opts or {})
  opts.dialect = opts.dialect or self
  return llbl.format_doc(value, opts)
end

function Dialect:format_region(value, opts)
  opts = shallow_copy(opts or {})
  opts.dialect = opts.dialect or self
  return llbl.format_region(value, opts)
end

function Dialect:format(value, opts)
  opts = shallow_copy(opts or {})
  opts.dialect = opts.dialect or self
  return llbl.format(value, opts)
end

function Analysis:format_doc(opts)
  opts = shallow_copy(opts or {})
  opts.dialect = opts.dialect or self.dialect
  return llbl.format_doc(self.ast, opts)
end

function Analysis:format_region(opts)
  opts = shallow_copy(opts or {})
  opts.dialect = opts.dialect or self.dialect
  return llbl.format_region(self.ast, opts)
end

function Analysis:format(opts)
  opts = shallow_copy(opts or {})
  opts.dialect = opts.dialect or self.dialect
  return llbl.format(self.ast, opts)
end

-- ---------------------------------------------------------------------------
-- Dumping and example dialect
-- ---------------------------------------------------------------------------

local function dump_value(v, indent, seen)
  indent = indent or ""; seen = seen or {}
  if v == NIL then return "nil" end; if v == UNIT then return "()" end; if v == ABSENT then return "<absent>" end
  local tv = type(v); if tv == "string" then return string.format("%q", v) end; if tv ~= "table" then return tostring(v) end; if seen[v] then return "<cycle>" end
  seen[v] = true
  local out, ni = { "{" }, indent .. "  "
  local tag = tagof(v); if tag then out[#out + 1] = ni .. "__tag = " .. string.format("%q", tostring(tag)) .. "," end
  local keys = {}; for k in pairs(v) do if k ~= "__llbl" and k ~= "origin" and k ~= "__llbl_tag" then keys[#keys + 1] = k end end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  for i = 1, #keys do local k = keys[i]; out[#out + 1] = ni .. tostring(k) .. " = " .. dump_value(v[k], ni, seen) .. "," end
  out[#out + 1] = indent .. "}"; seen[v] = nil; return table.concat(out, "\n")
end
function llbl.dump(v) return dump_value(v) end

function llbl.example_language()
  local g = llbl.grammar
  return llbl.dialect "Mini" {
    g.role .decls { kind = "array" },
    g.role .body { kind = "array" },
    g.role .product { kind = "product" },
    g.scalar .void, g.scalar .i32, g.scalar .u8, g.scalar .bool,
    g.type_ctor .ptr { arity = 1 },
    g.type_ctor .array { arity = 2 },
    g.head .unit { g.slot .name [g.string], g.slot .decls [g.decls], emit = function(n) return { tag = "unit", name = n.name, decls = n.decls } end },
    g.head .struct { g.slot .name [g.name], g.slot .fields [g.product], emit = function(n) return { tag = "struct", name = n.name.text, fields = n.fields } end },
    g.head .fn { g.slot .name [g.name], g.slot .params [g.product], g.slot .result [g.type] { optional = true }, g.slot .body [g.body], emit = function(n, lang) return { tag = "fn", name = n.name.text, params = n.params, result = n.result or lang.exports.void, body = n.body } end, lsp = { symbol = function(n) return { name = n.name, kind = "Function", origin = n.origin, node = n } end } },
    g.head .ret { g.slot .value [g.expr] { optional = true }, emit = function(n) return { tag = "ret", value = n.value } end },
  }
end

require("llbl.bootstrap").install(llbl)

return llbl
