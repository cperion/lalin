-- impl/tree_closure.lua
--
-- Closure conversion — free variable detection, capture layout, and
-- reference rewriting for scalar functions.  ExprClosure (nested lambdas)
-- is deferred as UNSUPPORTED until the full port is complete.
--
-- Ported from lua/lalin/closure_convert.lua (819 lines) — scalar subset.

require("lalin.schema_v2")
local C   = require("lalin.schema_v2.core")
local Ty  = require("lalin.schema_v2.type")
local B   = require("lalin.schema_v2.bind")
local Sem = require("lalin.schema_v2.sem")
local Tr  = require("lalin.schema_v2.tree")
local asdl = require("lalin.asdl")

----------------------------------------------------------------------
-- ValueRef closure helper methods (installed once on schema classes)
----------------------------------------------------------------------
function B.ValueRef:closure_is_name_ref() return false end
function B.ValueRefName:closure_is_name_ref() return true end
function B.ValueRefName:closure_captured_name() return self.name end

----------------------------------------------------------------------
-- Internal mutable input table (replaces old mutation-pattern input)
-- The schema ClosureRewriteInput is immutable; we track state here.
----------------------------------------------------------------------
local function new_input(module_name)
  return {
    module_name = module_name,
    owner = "module",
    counter = 0,
    helpers = {},
    scopes = {},
    capture_env = nil,
  }
end

local function fresh_helper_name(input)
  input.counter = input.counter + 1
  return "__lalin_closure_" .. (input.module_name or "mod")
    .. "_" .. (input.owner or "anon")
    .. "_" .. tostring(input.counter)
end

local function push_scope(input, entries)
  input.scopes[#input.scopes + 1] = entries or {}
end

local function pop_scope(input)
  input.scopes[#input.scopes] = nil
end

local function scope_get(input, name)
  for i = #input.scopes, 1, -1 do
    local ty = input.scopes[i][name]
    if ty ~= nil then return ty end
  end
  return nil
end

local function params_scope(params)
  local out = {}
  for _, p in ipairs(params or {}) do out[p.name] = p.ty end
  return out
end

----------------------------------------------------------------------
-- Capture layout: compute offsets for each captured variable
----------------------------------------------------------------------
local function compute_capture_layout(captures)
  local offset = 0
  for i = 1, #captures do
    local size = 8  -- all captures are ptr-sized in scalar impl
    captures[i].offset = offset
    captures[i].size = size
    offset = offset + size
  end
  return offset
end

----------------------------------------------------------------------
-- Helper: build a load expression for a captured variable via env ptr
----------------------------------------------------------------------
local function captured_load(cap)
  local ctx = Tr.ExprRef(Tr.ExprSurface, B.ValueRefName("__lalin_ctx"))
  local addr = ctx
  if cap.offset ~= 0 then
    addr = Tr.ExprBinary(Tr.ExprSurface, C.BinAdd, ctx,
      Tr.ExprLit(Tr.ExprSurface, C.LitInt(tostring(cap.offset))))
  end
  return Tr.ExprLoad(Tr.ExprSurface, cap.ty,
    Tr.ExprCast(Tr.ExprSurface, C.SurfaceCast, Ty.TPtr(cap.ty), addr))
end

----------------------------------------------------------------------
-- Free variable collection: walk body and collect names not in locals
----------------------------------------------------------------------
local _collect_stmts  -- forward

local function collect_expr(expr, input, locals, out, seen)
  local k = asdl.classof(expr)
  if k == Tr.ExprRef then
    if not expr.ref:closure_is_name_ref() then return end
    local name = expr.ref:closure_captured_name()
    if locals[name] or seen[name] then return end
    local ty = scope_get(input, name)
    if ty ~= nil then
      seen[name] = true
      out[#out + 1] = { name = name, ty = ty, offset = 0, size = 0 }
    end
  elseif k == Tr.ExprLit then
    -- no capture
  elseif k == Tr.ExprUnary or k == Tr.ExprCast or k == Tr.ExprMachineCast
    or k == Tr.ExprDeref or k == Tr.ExprLen
    or k == Tr.ExprAddrOf or k == Tr.ExprLoad then
    if expr.value then collect_expr(expr.value, input, locals, out, seen) end
    if expr.place then collect_place(expr.place, input, locals, out, seen) end
    if expr.addr then collect_expr(expr.addr, input, locals, out, seen) end
  elseif k == Tr.ExprBinary or k == Tr.ExprCompare or k == Tr.ExprLogic then
    if expr.lhs then collect_expr(expr.lhs, input, locals, out, seen) end
    if expr.rhs then collect_expr(expr.rhs, input, locals, out, seen) end
  elseif k == Tr.ExprIntrinsic then
    for _, a in ipairs(expr.args or {}) do collect_expr(a, input, locals, out, seen) end
  elseif k == Tr.ExprCall then
    collect_expr(expr.callee, input, locals, out, seen)
    for _, a in ipairs(expr.args or {}) do collect_expr(a, input, locals, out, seen) end
  elseif k == Tr.ExprField or k == Tr.ExprDot then
    if expr.base then collect_expr(expr.base, input, locals, out, seen) end
  elseif k == Tr.ExprIndex then
    if expr.base then collect_index_base(expr.base, input, locals, out, seen) end
    if expr.index then collect_expr(expr.index, input, locals, out, seen) end
  elseif k == Tr.ExprAgg then
    for _, f in ipairs(expr.fields or {}) do
      if f.value then collect_expr(f.value, input, locals, out, seen) end
    end
  elseif k == Tr.ExprCtor then
    for _, a in ipairs(expr.args or {}) do collect_expr(a, input, locals, out, seen) end
  elseif k == Tr.ExprArray then
    for _, e in ipairs(expr.elems or {}) do collect_expr(e, input, locals, out, seen) end
  elseif k == Tr.ExprIf or k == Tr.ExprSelect then
    if expr.cond then collect_expr(expr.cond, input, locals, out, seen) end
    if expr.then_expr then collect_expr(expr.then_expr, input, locals, out, seen) end
    if expr.else_expr then collect_expr(expr.else_expr, input, locals, out, seen) end
  elseif k == Tr.ExprSwitch then
    if expr.value then collect_expr(expr.value, input, locals, out, seen) end
    for _, arm in ipairs(expr.arms or {}) do
      local inner = {}; for kk, vv in pairs(locals) do inner[kk] = vv end
      _collect_stmts(arm.body, input, inner, out, seen)
      if arm.result then collect_expr(arm.result, input, inner, out, seen) end
    end
    if expr.default_body then
      local inner = {}; for kk, vv in pairs(locals) do inner[kk] = vv end
      _collect_stmts(expr.default_body, input, inner, out, seen)
    end
    if expr.default_expr then
      local inner = {}; for kk, vv in pairs(locals) do inner[kk] = vv end
      collect_expr(expr.default_expr, input, inner, out, seen)
    end
  elseif k == Tr.ExprBlock then
    local inner = {}; for kk, vv in pairs(locals) do inner[kk] = vv end
    _collect_stmts(expr.stmts, input, inner, out, seen)
    if expr.result then collect_expr(expr.result, input, inner, out, seen) end
  elseif k == Tr.ExprView then
    if expr.view then collect_view(expr.view, input, locals, out, seen) end
  elseif k == Tr.ExprAtomicLoad then
    if expr.addr then collect_expr(expr.addr, input, locals, out, seen) end
  elseif k == Tr.ExprAtomicRmw then
    if expr.addr then collect_expr(expr.addr, input, locals, out, seen) end
    if expr.value then collect_expr(expr.value, input, locals, out, seen) end
  elseif k == Tr.ExprAtomicCas then
    if expr.addr then collect_expr(expr.addr, input, locals, out, seen) end
    if expr.expected then collect_expr(expr.expected, input, locals, out, seen) end
    if expr.replacement then collect_expr(expr.replacement, input, locals, out, seen) end
  elseif k == Tr.ExprClosure then
    -- Nested closures: record as unsupported later
  elseif k == Tr.ExprNull or k == Tr.ExprSizeOf or k == Tr.ExprAlignOf or k == Tr.ExprIsNull then
    -- no captures
  end
end

local function collect_place(place, input, locals, out, seen)
  local k = asdl.classof(place)
  if k == Tr.PlaceRef then
    if place.ref:closure_is_name_ref() then
      local fake_expr = Tr.ExprRef(Tr.ExprSurface, place.ref)
      collect_expr(fake_expr, input, locals, out, seen)
    end
  elseif k == Tr.PlaceDeref or k == Tr.PlaceDot or k == Tr.PlaceField then
    if place.base then collect_place(place.base, input, locals, out, seen) end
  elseif k == Tr.PlaceIndex then
    if place.base then collect_index_base(place.base, input, locals, out, seen) end
    if place.index then collect_expr(place.index, input, locals, out, seen) end
  end
end

local function collect_index_base(ib, input, locals, out, seen)
  local k = asdl.classof(ib)
  if k == Tr.IndexBaseExpr then
    if ib.base then collect_expr(ib.base, input, locals, out, seen) end
  elseif k == Tr.IndexBasePlace then
    if ib.base then collect_place(ib.base, input, locals, out, seen) end
  elseif k == Tr.IndexBaseView then
    if ib.view then collect_view(ib.view, input, locals, out, seen) end
  end
end

local function collect_view(view, input, locals, out, seen)
  local k = asdl.classof(view)
  if k == Tr.ViewFromExpr then
    if view.base then collect_expr(view.base, input, locals, out, seen) end
  elseif k == Tr.ViewContiguous then
    if view.data then collect_expr(view.data, input, locals, out, seen) end
    if view.len then collect_expr(view.len, input, locals, out, seen) end
  elseif k == Tr.ViewStrided then
    if view.data then collect_expr(view.data, input, locals, out, seen) end
    if view.len then collect_expr(view.len, input, locals, out, seen) end
    if view.stride then collect_expr(view.stride, input, locals, out, seen) end
  elseif k == Tr.ViewRestrided or k == Tr.ViewRowBase then
    if view.base then collect_view(view.base, input, locals, out, seen) end
    if view.stride then collect_expr(view.stride, input, locals, out, seen) end
    if view.row_offset then collect_expr(view.row_offset, input, locals, out, seen) end
  elseif k == Tr.ViewWindow then
    if view.base then collect_view(view.base, input, locals, out, seen) end
    if view.start then collect_expr(view.start, input, locals, out, seen) end
    if view.len then collect_expr(view.len, input, locals, out, seen) end
  elseif k == Tr.ViewInterleaved then
    if view.data then collect_expr(view.data, input, locals, out, seen) end
    if view.len then collect_expr(view.len, input, locals, out, seen) end
    if view.stride then collect_expr(view.stride, input, locals, out, seen) end
    if view.lane then collect_expr(view.lane, input, locals, out, seen) end
  elseif k == Tr.ViewInterleavedView then
    if view.base then collect_view(view.base, input, locals, out, seen) end
    if view.stride then collect_expr(view.stride, input, locals, out, seen) end
    if view.lane then collect_expr(view.lane, input, locals, out, seen) end
  end
end

local function collect_stmt(stmt, input, locals, out, seen)
  local k = asdl.classof(stmt)
  if k == Tr.StmtLet or k == Tr.StmtVar then
    if stmt.init then collect_expr(stmt.init, input, locals, out, seen) end
    locals[stmt.binding.name] = stmt.binding.ty
  elseif k == Tr.StmtSet then
    if stmt.place then collect_place(stmt.place, input, locals, out, seen) end
    if stmt.value then collect_expr(stmt.value, input, locals, out, seen) end
  elseif k == Tr.StmtExpr then
    if stmt.expr then collect_expr(stmt.expr, input, locals, out, seen) end
  elseif k == Tr.StmtAssert then
    if stmt.cond then collect_expr(stmt.cond, input, locals, out, seen) end
  elseif k == Tr.StmtReturnValue then
    if stmt.value then collect_expr(stmt.value, input, locals, out, seen) end
  elseif k == Tr.StmtYieldValue then
    if stmt.value then collect_expr(stmt.value, input, locals, out, seen) end
  elseif k == Tr.StmtIf then
    if stmt.cond then collect_expr(stmt.cond, input, locals, out, seen) end
    local a = {}; for kk, vv in pairs(locals) do a[kk] = vv end
    _collect_stmts(stmt.then_body, input, a, out, seen)
    local b = {}; for kk, vv in pairs(locals) do b[kk] = vv end
    _collect_stmts(stmt.else_body, input, b, out, seen)
  elseif k == Tr.StmtSwitch then
    if stmt.value then collect_expr(stmt.value, input, locals, out, seen) end
    for _, arm in ipairs(stmt.arms or {}) do
      local inner = {}; for kk, vv in pairs(locals) do inner[kk] = vv end
      _collect_stmts(arm.body, input, inner, out, seen)
    end
    if stmt.default_body then
      local inner = {}; for kk, vv in pairs(locals) do inner[kk] = vv end
      _collect_stmts(stmt.default_body, input, inner, out, seen)
    end
  elseif k == Tr.StmtJump or k == Tr.StmtJumpCont then
    for _, a in ipairs(stmt.args or {}) do
      if a.value then collect_expr(a.value, input, locals, out, seen) end
    end
  elseif k == Tr.StmtAtomicStore then
    if stmt.addr then collect_expr(stmt.addr, input, locals, out, seen) end
    if stmt.value then collect_expr(stmt.value, input, locals, out, seen) end
  elseif k == Tr.StmtControl then
    if stmt.region then
      for _, blk in ipairs(stmt.region.blocks or {}) do
        local inner = {}; for kk, vv in pairs(locals) do inner[kk] = vv end
        _collect_stmts(blk.body, input, inner, out, seen)
      end
    end
  end
end

_collect_stmts = function(stmts, input, locals, out, seen)
  for _, s in ipairs(stmts or {}) do
    collect_stmt(s, input, locals, out, seen)
  end
end

----------------------------------------------------------------------
-- Rewrite helpers: produce new nodes with captured refs rewritten
----------------------------------------------------------------------
local _rewrite_stmts  -- forward

local function rewrite_expr(expr, input)
  local k = asdl.classof(expr)
  if k == Tr.ExprRef then
    if expr.ref:closure_is_name_ref() and input.capture_env ~= nil then
      local name = expr.ref:closure_captured_name()
      local cap = input.capture_env[name]
      if cap ~= nil and scope_get(input, name) == nil then
        return captured_load(cap)
      end
    end
    return expr
  elseif k == Tr.ExprLit or k == Tr.ExprNull
    or k == Tr.ExprSizeOf or k == Tr.ExprAlignOf or k == Tr.ExprIsNull then
    return expr
  elseif k == Tr.ExprUnary then
    local v = rewrite_expr(expr.value, input)
    if v == expr.value then return expr end
    return asdl.with(expr, { value = v })
  elseif k == Tr.ExprBinary or k == Tr.ExprCompare or k == Tr.ExprLogic then
    local lhs = rewrite_expr(expr.lhs, input)
    local rhs = rewrite_expr(expr.rhs, input)
    if lhs == expr.lhs and rhs == expr.rhs then return expr end
    return asdl.with(expr, { lhs = lhs, rhs = rhs })
  elseif k == Tr.ExprCast or k == Tr.ExprMachineCast
    or k == Tr.ExprDeref or k == Tr.ExprLen or k == Tr.ExprLoad then
    local v = rewrite_expr(expr.value or expr.addr, input)
    if v == (expr.value or expr.addr) then return expr end
    if expr.value ~= nil then return asdl.with(expr, { value = v }) end
    return asdl.with(expr, { addr = v })
  elseif k == Tr.ExprIntrinsic then
    local changed = false
    local args = {}
    for i, a in ipairs(expr.args or {}) do
      args[i] = rewrite_expr(a, input)
      if args[i] ~= expr.args[i] then changed = true end
    end
    if not changed then return expr end
    return asdl.with(expr, { args = args })
  elseif k == Tr.ExprCall then
    local callee = rewrite_expr(expr.callee, input)
    local changed = callee ~= expr.callee
    local args = {}
    for i, a in ipairs(expr.args or {}) do
      args[i] = rewrite_expr(a, input)
      if args[i] ~= expr.args[i] then changed = true end
    end
    if not changed then return expr end
    return asdl.with(expr, { callee = callee, args = args })
  elseif k == Tr.ExprField or k == Tr.ExprDot then
    local base = rewrite_expr(expr.base, input)
    if base == expr.base then return expr end
    return asdl.with(expr, { base = base })
  elseif k == Tr.ExprIndex then
    local base = rewrite_index_base(expr.base, input)
    local idx = rewrite_expr(expr.index, input)
    if base == expr.base and idx == expr.index then return expr end
    return asdl.with(expr, { base = base, index = idx })
  elseif k == Tr.ExprAgg then
    local changed = false
    local fields = {}
    for i, f in ipairs(expr.fields or {}) do
      local v = rewrite_expr(f.value, input)
      if v ~= f.value then changed = true end
      fields[i] = changed and asdl.with(f, { value = v }) or f
    end
    if not changed then return expr end
    return asdl.with(expr, { fields = fields })
  elseif k == Tr.ExprCtor then
    local changed = false
    local args = {}
    for i, a in ipairs(expr.args or {}) do
      args[i] = rewrite_expr(a, input)
      if args[i] ~= expr.args[i] then changed = true end
    end
    if not changed then return expr end
    return asdl.with(expr, { args = args })
  elseif k == Tr.ExprArray then
    local changed = false
    local elems = {}
    for i, e in ipairs(expr.elems or {}) do
      elems[i] = rewrite_expr(e, input)
      if elems[i] ~= expr.elems[i] then changed = true end
    end
    if not changed then return expr end
    return asdl.with(expr, { elems = elems })
  elseif k == Tr.ExprIf or k == Tr.ExprSelect then
    local cond = rewrite_expr(expr.cond, input)
    local then_e = rewrite_expr(expr.then_expr, input)
    local else_e = rewrite_expr(expr.else_expr, input)
    if cond == expr.cond and then_e == expr.then_expr and else_e == expr.else_expr then
      return expr
    end
    return asdl.with(expr, { cond = cond, then_expr = then_e, else_expr = else_e })
  elseif k == Tr.ExprSwitch then
    local val = rewrite_expr(expr.value, input)
    local arms = {}
    for i, arm in ipairs(expr.arms or {}) do
      local body, _ = _rewrite_stmts(arm.body, input)
      local r = arm.result and rewrite_expr(arm.result, input) or nil
      arms[i] = asdl.with(arm, { body = body, result = r })
    end
    local default_body, _ = _rewrite_stmts(expr.default_body or {}, input)
    local default_expr = expr.default_expr and rewrite_expr(expr.default_expr, input) or nil
    return asdl.with(expr, { value = val, arms = arms, default_body = default_body, default_expr = default_expr })
  elseif k == Tr.ExprBlock then
    local stmts, _ = _rewrite_stmts(expr.stmts, input)
    local result = rewrite_expr(expr.result, input)
    return asdl.with(expr, { stmts = stmts, result = result })
  elseif k == Tr.ExprView then
    local view = rewrite_view(expr.view, input)
    if view == expr.view then return expr end
    return asdl.with(expr, { view = view })
  elseif k == Tr.ExprAddrOf then
    local place = rewrite_place(expr.place, input)
    if place == expr.place then return expr end
    return asdl.with(expr, { place = place })
  elseif k == Tr.ExprAtomicLoad then
    local addr = rewrite_expr(expr.addr, input)
    if addr == expr.addr then return expr end
    return asdl.with(expr, { addr = addr })
  elseif k == Tr.ExprAtomicRmw then
    local addr = rewrite_expr(expr.addr, input)
    local val = rewrite_expr(expr.value, input)
    if addr == expr.addr and val == expr.value then return expr end
    return asdl.with(expr, { addr = addr, value = val })
  elseif k == Tr.ExprAtomicCas then
    local addr = rewrite_expr(expr.addr, input)
    local expected = rewrite_expr(expr.expected, input)
    local replacement = rewrite_expr(expr.replacement, input)
    if addr == expr.addr and expected == expr.expected and replacement == expr.replacement then
      return expr
    end
    return asdl.with(expr, { addr = addr, expected = expected, replacement = replacement })
  elseif k == Tr.ExprClosure then
    error("UNSUPPORTED: nested closures (ExprClosure) not yet implemented in closure_convert", 2)
  elseif k == Tr.ExprControl then
    local blocks = {}
    for i, blk in ipairs(expr.region.blocks or {}) do
      local body, _ = _rewrite_stmts(blk.body, input)
      blocks[i] = asdl.with(blk, { body = body })
    end
    return asdl.with(expr, { region = asdl.with(expr.region, { blocks = blocks }) })
  end
  return expr
end

local function rewrite_place(place, input)
  local k = asdl.classof(place)
  if k == Tr.PlaceRef then
    if place.ref:closure_is_name_ref() and input.capture_env ~= nil then
      local name = place.ref:closure_captured_name()
      local cap = input.capture_env[name]
      -- Places can't be captured as l-values in this scalar impl;
      -- we report via expr rewrite. For now pass-through.
    end
    return place
  elseif k == Tr.PlaceDeref or k == Tr.PlaceDot or k == Tr.PlaceField then
    local base = rewrite_place(place.base, input)
    if base == place.base then return place end
    return asdl.with(place, { base = base })
  elseif k == Tr.PlaceIndex then
    local base = rewrite_index_base(place.base, input)
    local idx = rewrite_expr(place.index, input)
    if base == place.base and idx == place.index then return place end
    return asdl.with(place, { base = base, index = idx })
  end
  return place
end

local function rewrite_index_base(ib, input)
  local k = asdl.classof(ib)
  if k == Tr.IndexBaseExpr then
    local base = rewrite_expr(ib.base, input)
    if base == ib.base then return ib end
    return asdl.with(ib, { base = base })
  elseif k == Tr.IndexBasePlace then
    local base = rewrite_place(ib.base, input)
    if base == ib.base then return ib end
    return asdl.with(ib, { base = base })
  elseif k == Tr.IndexBaseView then
    local view = rewrite_view(ib.view, input)
    if view == ib.view then return ib end
    return asdl.with(ib, { view = view })
  end
  return ib
end

local function rewrite_view(view, input)
  local k = asdl.classof(view)
  if k == Tr.ViewFromExpr then
    local base = rewrite_expr(view.base, input)
    if base == view.base then return view end
    return asdl.with(view, { base = base })
  elseif k == Tr.ViewContiguous then
    local data = rewrite_expr(view.data, input)
    local len = rewrite_expr(view.len, input)
    if data == view.data and len == view.len then return view end
    return asdl.with(view, { data = data, len = len })
  elseif k == Tr.ViewStrided then
    local data = rewrite_expr(view.data, input)
    local len = rewrite_expr(view.len, input)
    local stride = rewrite_expr(view.stride, input)
    if data == view.data and len == view.len and stride == view.stride then return view end
    return asdl.with(view, { data = data, len = len, stride = stride })
  elseif k == Tr.ViewRestrided or k == Tr.ViewRowBase then
    local base = rewrite_view(view.base, input)
    local extra = view.stride or view.row_offset
    local extra2 = rewrite_expr(extra, input)
    if base == view.base and extra2 == extra then return view end
    if view.stride then return asdl.with(view, { base = base, stride = extra2 }) end
    return asdl.with(view, { base = base, row_offset = extra2 })
  elseif k == Tr.ViewWindow then
    local base = rewrite_view(view.base, input)
    local start = rewrite_expr(view.start, input)
    local len = rewrite_expr(view.len, input)
    if base == view.base and start == view.start and len == view.len then return view end
    return asdl.with(view, { base = base, start = start, len = len })
  elseif k == Tr.ViewInterleaved then
    local data = rewrite_expr(view.data, input)
    local len = rewrite_expr(view.len, input)
    local stride = rewrite_expr(view.stride, input)
    local lane = rewrite_expr(view.lane, input)
    if data == view.data and len == view.len and stride == view.stride and lane == view.lane then
      return view
    end
    return asdl.with(view, { data = data, len = len, stride = stride, lane = lane })
  elseif k == Tr.ViewInterleavedView then
    local base = rewrite_view(view.base, input)
    local stride = rewrite_expr(view.stride, input)
    local lane = rewrite_expr(view.lane, input)
    if base == view.base and stride == view.stride and lane == view.lane then return view end
    return asdl.with(view, { base = base, stride = stride, lane = lane })
  end
  return view
end

local function rewrite_stmt(stmt, input)
  local k = asdl.classof(stmt)
  if k == Tr.StmtLet or k == Tr.StmtVar then
    local init = rewrite_expr(stmt.init, input)
    if #input.scopes > 0 then input.scopes[#input.scopes][stmt.binding.name] = stmt.binding.ty end
    if init == stmt.init then return stmt end
    return asdl.with(stmt, { init = init })
  elseif k == Tr.StmtSet then
    local place = rewrite_place(stmt.place, input)
    local val = rewrite_expr(stmt.value, input)
    if place == stmt.place and val == stmt.value then return stmt end
    return asdl.with(stmt, { place = place, value = val })
  elseif k == Tr.StmtExpr then
    local expr = rewrite_expr(stmt.expr, input)
    if expr == stmt.expr then return stmt end
    return asdl.with(stmt, { expr = expr })
  elseif k == Tr.StmtAssert then
    local cond = rewrite_expr(stmt.cond, input)
    if cond == stmt.cond then return stmt end
    return asdl.with(stmt, { cond = cond })
  elseif k == Tr.StmtReturnValue then
    local val = rewrite_expr(stmt.value, input)
    if val == stmt.value then return stmt end
    return asdl.with(stmt, { value = val })
  elseif k == Tr.StmtYieldValue then
    local val = rewrite_expr(stmt.value, input)
    if val == stmt.value then return stmt end
    return asdl.with(stmt, { value = val })
  elseif k == Tr.StmtIf then
    local cond = rewrite_expr(stmt.cond, input)
    local then_body, _ = _rewrite_stmts(stmt.then_body, input)
    local else_body, _ = _rewrite_stmts(stmt.else_body, input)
    return asdl.with(stmt, { cond = cond, then_body = then_body, else_body = else_body })
  elseif k == Tr.StmtSwitch then
    local val = rewrite_expr(stmt.value, input)
    local arms = {}
    for i, arm in ipairs(stmt.arms or {}) do
      local body, _ = _rewrite_stmts(arm.body, input)
      arms[i] = asdl.with(arm, { body = body })
    end
    local default_body, _ = _rewrite_stmts(stmt.default_body or {}, input)
    return asdl.with(stmt, { value = val, arms = arms, default_body = default_body })
  elseif k == Tr.StmtJump or k == Tr.StmtJumpCont then
    local changed = false
    local args = {}
    for i, a in ipairs(stmt.args or {}) do
      local v = rewrite_expr(a.value, input)
      if v ~= a.value then changed = true end
      args[i] = changed and asdl.with(a, { value = v }) or a
    end
    if not changed then return stmt end
    return asdl.with(stmt, { args = args })
  elseif k == Tr.StmtAtomicStore then
    local addr = rewrite_expr(stmt.addr, input)
    local val = rewrite_expr(stmt.value, input)
    if addr == stmt.addr and val == stmt.value then return stmt end
    return asdl.with(stmt, { addr = addr, value = val })
  elseif k == Tr.StmtControl then
    local blocks = {}
    for i, blk in ipairs(stmt.region.blocks or {}) do
      local body, _ = _rewrite_stmts(blk.body, input)
      blocks[i] = asdl.with(blk, { body = body })
    end
    return asdl.with(stmt, { region = asdl.with(stmt.region, { blocks = blocks }) })
  end
  return stmt
end

_rewrite_stmts = function(stmts, input)
  local out = {}
  for i, s in ipairs(stmts or {}) do
    out[i] = rewrite_stmt(s, input)
  end
  return out
end

----------------------------------------------------------------------
-- Closure conversion for a single function
----------------------------------------------------------------------
local function closure_convert_func(func, input)
  local saved_owner = input.owner
  input.owner = func.name
  push_scope(input, params_scope(func.params or {}))

  -- Phase A: detect free variables
  local locals = params_scope(func.params or {})
  local captures, seen = {}, {}
  _collect_stmts(func.body, input, locals, captures, seen)

  if #captures == 0 then
    -- No free vars: pass-through rewrite (identity)
    local body, _ = _rewrite_stmts(func.body, input)
    pop_scope(input)
    input.owner = saved_owner
    return asdl.with(func, { body = body }), input
  end

  -- Has free vars: create capture layout and helper
  local helper_name = fresh_helper_name(input)
  compute_capture_layout(captures)

  -- Build helper params: ctx ptr + original params
  local helper_params = {
    Ty.Param("__lalin_ctx", Ty.TPtr(Ty.TScalar(C.ScalarU8))),
  }
  for _, p in ipairs(func.params or {}) do
    helper_params[#helper_params + 1] = p
  end

  -- Build capture_env for rewrite
  local capture_env = {}
  for _, cap in ipairs(captures) do
    capture_env[cap.name] = cap
  end

  -- Rewrite body with capture_env active
  local saved_capture_env = input.capture_env
  local saved_scopes = input.scopes
  input.capture_env = capture_env
  input.scopes = {}
  input.owner = helper_name
  push_scope(input, params_scope(helper_params))
  local body, _ = _rewrite_stmts(func.body, input)
  pop_scope(input)
  input.scopes = saved_scopes
  input.capture_env = saved_capture_env

  -- Create helper function item
  local helper = Tr.FuncLocal(helper_name, helper_params, func.result, body)
  input.helpers[#input.helpers + 1] = Tr.ItemFunc(helper)

  -- Original function body becomes a call to the helper with captures loaded
  local call_args = { Tr.ExprRef(Tr.ExprSurface, B.ValueRefName("__lalin_ctx")) }
  for _, p in ipairs(func.params or {}) do
    call_args[#call_args + 1] = Tr.ExprRef(Tr.ExprSurface, B.ValueRefName(p.name))
  end
  local call = Tr.ExprCall(Tr.ExprSurface,
    Tr.ExprRef(Tr.ExprSurface, B.ValueRefName(helper_name)),
    call_args)

  pop_scope(input)
  input.owner = saved_owner

  if func.result and asdl.classof(func.result) == Ty.TScalar and func.result.scalar == C.ScalarVoid then
    local new_body = { Tr.StmtExpr(Tr.StmtSurface, call), Tr.StmtReturnVoid(Tr.StmtSurface) }
    return asdl.with(func, { body = new_body }), input
  end

  local new_body = { Tr.StmtReturnValue(Tr.StmtSurface, call) }
  return asdl.with(func, { body = new_body }), input
end

----------------------------------------------------------------------
-- Module-level entry point — the public API
----------------------------------------------------------------------
function Tr.Module:closure_convert()
  local input = new_input(self:tree_code_module_name())

  local items = {}
  for _, item in ipairs(self.items or {}) do
    local before = #input.helpers
    local rewritten
    rewritten, input = item:closure_convert_item(input)
    for j = before + 1, #input.helpers do
      items[#items + 1] = input.helpers[j]
    end
    items[#items + 1] = rewritten
  end

  return Tr.Module(self.h, items)
end

function Tr.Item:closure_convert_item(input)
  return self, input
end

function Tr.ItemFunc:closure_convert_item(input)
  local func, input = self.func:closure_convert(input)
  if func == self.func then return self, input end
  return Tr.ItemFunc(func), input
end

function Tr.ItemExtern:closure_convert_item(input)
  return self, input
end

function Tr.ItemType:closure_convert_item(input)
  return self, input
end

function Tr.ItemConst:closure_convert_item(input)
  return self, input
end

function Tr.ItemStatic:closure_convert_item(input)
  return self, input
end

function Tr.ItemImport:closure_convert_item(input)
  return self, input
end

function Tr.ItemRegion:closure_convert_item(input)
  return self, input
end

function Tr.ItemData:closure_convert_item(input)
  return self, input
end

----------------------------------------------------------------------
-- Func leaf methods
----------------------------------------------------------------------
function Tr.Func:closure_convert(input)
  local saved_owner = input.owner
  push_scope(input, params_scope(self.params or {}))
  local body, _ = _rewrite_stmts(self.body, input)
  pop_scope(input)
  input.owner = saved_owner
  return asdl.with(self, { body = body }), input
end

function Tr.FuncLocal:closure_convert(input)
  input.owner = self.name
  return closure_convert_func(self, input)
end

function Tr.FuncExport:closure_convert(input)
  input.owner = self.name
  return closure_convert_func(self, input)
end

function Tr.FuncLocalContract:closure_convert(input)
  input.owner = self.name
  return closure_convert_func(self, input)
end

function Tr.FuncExportContract:closure_convert(input)
  input.owner = self.name
  return closure_convert_func(self, input)
end

function Tr.FuncDecl:closure_convert(input)
  return self, input
end

----------------------------------------------------------------------
-- ExprClosure is deferred
----------------------------------------------------------------------
function Tr.ExprClosure:closure_convert(input)
  error("UNSUPPORTED: ExprClosure (nested closure) not yet implemented. "
    .. "Scalar closure conversion only; nested lambdas are deferred.", 2)
end

function Tr.ExprClosure:closure_convert_item(input)
  error("UNSUPPORTED: ExprClosure (nested closure) not yet implemented. "
    .. "Scalar closure conversion only; nested lambdas are deferred.", 2)
end
