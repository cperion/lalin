-- impl/code_flow.lua — compute_flow methods on LalinCode and LalinGraph types
-- Produces LalinFlow.FlowFactSet and LalinFlow.FlowSemanticFactSet from a CodeGraph.
-- Leaf methods on CodeTermOp, CodeInstOp, and entry points on Graph.CodeGraph.

require("lalin.schema_v2")
local Core  = require("lalin.schema_v2.core")
local Code  = require("lalin.schema_v2.code")
local Graph = require("lalin.schema_v2.graph")
local Flow  = require("lalin.schema_v2.flow")
local Value = require("lalin.schema_v2.value")

----------------------------------------------------------------------
-- helpers
----------------------------------------------------------------------

local function sanitize(s)
  s = tostring(s or "x"):gsub("[^%w_]", "_")
  if s:match("^%d") then s = "_" .. s end
  if s == "" then s = "x" end
  return s
end

local function edge_args(dest_block, args)
  local out = {}
  local params = dest_block and dest_block.params or {}
  for i, arg in ipairs(args or {}) do
    local param = params[i]
    if param ~= nil then out[#out + 1] = Flow.FlowEdgeArg(arg, param.value) end
  end
  return out
end

----------------------------------------------------------------------
-- CodeTermOp leaf methods: code_flow_edge_args
----------------------------------------------------------------------

function Code.CodeTermOp:code_flow_edge_args(block_by_id)
  return {}
end

function Code.CodeTermJump:code_flow_edge_args(block_by_id)
  local out = {}
  if self.dest ~= nil then out[self.dest.text] = edge_args(block_by_id[self.dest.text], self.args or {}) end
  return out
end

function Code.CodeTermBranch:code_flow_edge_args(block_by_id)
  local out = {}
  if self.then_dest ~= nil then out[self.then_dest.text] = edge_args(block_by_id[self.then_dest.text], self.then_args or {}) end
  if self.else_dest ~= nil then out[self.else_dest.text] = edge_args(block_by_id[self.else_dest.text], self.else_args or {}) end
  return out
end

function Code.CodeTermSwitch:code_flow_edge_args(block_by_id)
  local out = {}
  for _, case in ipairs(self.cases or {}) do
    if case.dest ~= nil then out[case.dest.text] = edge_args(block_by_id[case.dest.text], case.args or {}) end
  end
  if self.default_dest ~= nil then out[self.default_dest.text] = edge_args(block_by_id[self.default_dest.text], self.default_args or {}) end
  return out
end

function Code.CodeTermVariantSwitch:code_flow_edge_args(block_by_id)
  local out = {}
  for _, case in ipairs(self.cases or {}) do
    if case.dest ~= nil then out[case.dest.text] = edge_args(block_by_id[case.dest.text], case.args or {}) end
  end
  if self.default_dest ~= nil then out[self.default_dest.text] = edge_args(block_by_id[self.default_dest.text], self.default_args or {}) end
  return out
end

----------------------------------------------------------------------
-- CodeInstOp leaf methods: code_flow_def_info
-- Returns (def_record, ty) or (nil, nil) for ops that don't produce a value.
-- Shared default for most ops uses the raw dst field.
----------------------------------------------------------------------

function Code.CodeInstOp:code_flow_def_dst()
  return rawget(self, "dst")
end

function Code.CodeInstOp:code_flow_def_ty(types_lookup)
  return self.ty or self.ptr_ty or self.tag_ty
end

-- Overrides for ops that compute their type differently
function Code.CodeInstViewMake:code_flow_def_ty(types_lookup)
  return Code.CodeTyView(self.elem_ty)
end

function Code.CodeInstViewData:code_flow_def_ty(types_lookup)
  if types_lookup == nil then return nil end
  local vty = types_lookup[self.view.text]
  if vty == nil then return nil end
  if vty:code_flow_is_lease() then vty = vty.base end
  if vty:code_flow_is_view() then return Code.CodeTyDataPtr(vty.elem) end
  return nil
end

function Code.CodeInstViewLen:code_flow_def_ty(types_lookup)
  return Code.CodeTyIndex
end

function Code.CodeInstViewStride:code_flow_def_ty(types_lookup)
  return Code.CodeTyIndex
end

function Code.CodeInstSliceMake:code_flow_def_ty(types_lookup)
  return Code.CodeTySlice(self.elem_ty)
end

function Code.CodeInstSliceData:code_flow_def_ty(types_lookup)
  if types_lookup == nil then return nil end
  local sty = types_lookup[self.slice.text]
  if sty == nil then return nil end
  if sty:code_flow_is_lease() then sty = sty.base end
  if sty:code_flow_is_slice() then return Code.CodeTyDataPtr(sty.elem) end
  return nil
end

function Code.CodeInstSliceLen:code_flow_def_ty(types_lookup)
  return Code.CodeTyIndex
end

function Code.CodeInstByteSpanMake:code_flow_def_ty(types_lookup)
  return Code.CodeTyByteSpan
end

function Code.CodeInstByteSpanData:code_flow_def_ty(types_lookup)
  return Code.CodeTyDataPtr(Code.CodeTyInt(8, Code.CodeUnsigned))
end

function Code.CodeInstByteSpanLen:code_flow_def_ty(types_lookup)
  return Code.CodeTyIndex
end

function Code.CodeInstLoad:code_flow_def_ty(types_lookup)
  return self.access.ty
end

----------------------------------------------------------------------
-- CodeType leaf methods: type classification helpers
----------------------------------------------------------------------

function Code.CodeType:code_flow_is_lease() return false end
function Code.CodeTyLease:code_flow_is_lease() return true end
function Code.CodeType:code_flow_is_view() return false end
function Code.CodeTyView:code_flow_is_view() return true end
function Code.CodeType:code_flow_is_slice() return false end
function Code.CodeTySlice:code_flow_is_slice() return true end

----------------------------------------------------------------------
-- internal lookup builders
----------------------------------------------------------------------

local function value_defs(func)
  local defs, types = {}, {}
  for _, param in ipairs(func.params or {}) do types[param.value.text] = param.ty end
  for _, block in ipairs(func.blocks or {}) do
    for _, param in ipairs(block.params or {}) do types[param.value.text] = param.ty end
    for _, inst in ipairs(block.insts or {}) do
      local k = inst.op
      local dst = k:code_flow_def_dst()
      if dst ~= nil then
        local ty = k:code_flow_def_ty(types)
        defs[dst.text] = k
        types[dst.text] = ty
      end
    end
  end
  return defs, types
end

local function const_values(defs)
  local out = {}
  for key, k in pairs(defs or {}) do
    -- Check if this is a CodeInstConst with a literal
    local const = rawget(k, "const")
    if const ~= nil then
      local lit = rawget(const, "literal")
      if lit ~= nil then
        local raw_val = rawget(lit, "raw") or nil
        local n = raw_val and tonumber(raw_val) or nil
        if n ~= nil then out[key] = n end
      end
    end
  end
  return out
end

local function const_ranges(defs)
  local ranges = {}
  local keys = {}
  for key in pairs(defs or {}) do keys[#keys + 1] = key end
  table.sort(keys)
  for _, key in ipairs(keys) do
    local k = defs[key]
    local const = rawget(k, "const")
    if const ~= nil then
      local lit = rawget(const, "literal")
      if lit ~= nil then
        local raw_val = rawget(lit, "raw") or nil
        if raw_val ~= nil then
          ranges[#ranges + 1] = Flow.FlowRangeExact(Code.CodeValueId(key), Flow.FlowBoundConst(raw_val))
        end
      end
    end
  end
  return ranges
end

local function edge_condition(block_by_id, edge)
  local block = edge and edge.from and edge.from.block and block_by_id[edge.from.block.text]
  local term = block and block.term and block.term.op or nil
  if term ~= nil and rawget(term, "cond") ~= nil then return term.cond end
  return nil
end

local function incoming_arg_for(edge_facts, header, param, skip_from)
  for _, fact in ipairs(edge_facts or {}) do
    local edge = fact.edge
    if edge.to.block == header and (skip_from == nil or edge.from.block ~= skip_from) then
      for _, arg in ipairs(fact.args or {}) do if arg.dst_param == param.value then return arg.src end end
    end
  end
  return nil
end

function Code.CodeLoopOrder:flow_domain_order()
  error("missing code-loop order projection", 2)
end
function Code.CodeLoopForward:flow_domain_order() return Flow.FlowDomainForward end
function Code.CodeLoopBackward:flow_domain_order() return Flow.FlowDomainBackward end
function Code.CodeWindowBoundary:flow_window_boundary()
  error("missing code-window boundary projection", 2)
end
function Code.CodeWindowReject:flow_window_boundary() return Flow.FlowWindowBoundaryReject end
function Code.CodeWindowClamp:flow_window_boundary() return Flow.FlowWindowBoundaryClamp end
function Code.CodeWindowWrap:flow_window_boundary() return Flow.FlowWindowBoundaryWrap end
function Code.CodeWindowZero:flow_window_boundary() return Flow.FlowWindowBoundaryZero end
function Code.CodeWindowAxisDeclaration:flow_window_axis()
  return Flow.FlowWindowAxis(self.before, self.after, self.boundary:flow_window_boundary())
end
function Code.CodeLoopShapeRangeND:flow_loop_shape(input)
  if #input.axes == 1 then
    local axis = input.axes[1]
    return Flow.FlowDomainShapeRange1D(
      axis.index_ty, axis.start, axis.stop, axis.step, axis.order)
  end
  return Flow.FlowDomainShapeRangeND(input.axes)
end
function Code.CodeLoopShapeWindowND:flow_loop_shape(input)
  local windows = {}
  for i = 1, #self.windows do windows[i] = self.windows[i]:flow_window_axis() end
  return Flow.FlowDomainShapeWindowND(input.axes, windows)
end
function Code.CodeLoopShapeTiledND:flow_loop_shape(input)
  return Flow.FlowDomainShapeTiledND(input.axes, self.tile_sizes)
end

local function code_param_by_value(header, value)
  for i = 1, #(header.params or {}) do
    if header.params[i].value == value then return header.params[i] end
  end
  return nil
end
function Code.CodeOrigin:flow_project_loop_domain(_input)
  return Flow.FlowLoopDomainAbsent
end
function Code.CodeOriginLoopDomain:flow_project_loop_domain(input)
  local latch = input.loop.latches and input.loop.latches[1] or nil
  local skip_from = latch and latch.from and latch.from.block or nil
  local axes = {}
  for i = 1, #self.declaration.axes do
    local axis = self.declaration.axes[i]
    local start_param = code_param_by_value(input.header, axis.start)
    local stop_param = code_param_by_value(input.header, axis.stop)
    if start_param == nil or stop_param == nil then
      return Flow.FlowLoopDomainRejected(
        input.domain, "declared loop axis parameter is absent from header")
    end
    local start = incoming_arg_for(input.edges, input.loop.header.block, start_param, skip_from)
    local stop = axis.stop
    if start == nil then
      return Flow.FlowLoopDomainRejected(
        input.domain, "declared loop axis has no unique entry argument")
    end
    axes[i] = Flow.FlowDomainAxis(axis.index_ty,
      Value.ValueExprValue(start), Value.ValueExprValue(stop), axis.step,
      axis.order:flow_domain_order(), axis.index_name)
  end
  local shape = self.declaration.shape:flow_loop_shape(
    Flow.FlowLoopShapeProjectionInput(axes))
  return Flow.FlowLoopDomainProjected(shape,
    Flow.FlowProofDomain(input.domain, "lln.loop authored an explicit typed domain"))
end

local function backedge_arg_for(edge_fact, param)
  for _, arg in ipairs(edge_fact and edge_fact.args or {}) do if arg.dst_param == param.value then return arg.src end end
  return nil
end

local function canonical_value(value, aliases)
  local seen = {}
  while value ~= nil and aliases ~= nil and aliases[value.text] ~= nil and not seen[value.text] do
    seen[value.text] = true
    value = aliases[value.text]
  end
  return value
end

local function same_canonical_value(a, b, aliases)
  a, b = canonical_value(a, aliases), canonical_value(b, aliases)
  return a ~= nil and b ~= nil and a == b
end

local numeric_const
local function recurrence_direction(step, defs, consts, positive, negative)
  local value = numeric_const(step, defs, consts)
  if value == nil or value == 0 then
    return Flow.FlowLoopDirectionUnknown, "induction step sign is not proven"
  end
  if value > 0 then return positive, nil end
  return negative, nil
end

local function induction_step(param_value, back_value, defs, aliases, consts)
  local k = back_value and defs[back_value.text] or nil
  if k == nil then
    return nil, "backedge value is not a binary recurrence", Flow.FlowLoopDirectionUnknown
  end
  -- Stage-0 flow discovery normalizes recurrence syntax and proven step sign.
  local op = rawget(k, "op")
  if op == nil then
    return nil, "backedge value is not a binary recurrence", Flow.FlowLoopDirectionUnknown
  end
  if op == Core.BinAdd then
    if same_canonical_value(k.lhs, param_value, aliases) then
      local direction, note = recurrence_direction(
        k.rhs, defs, consts, Flow.FlowLoopIncreasing, Flow.FlowLoopDecreasing)
      return k.rhs, note, direction
    end
    if same_canonical_value(k.rhs, param_value, aliases) then
      local direction, note = recurrence_direction(
        k.lhs, defs, consts, Flow.FlowLoopIncreasing, Flow.FlowLoopDecreasing)
      return k.lhs, note, direction
    end
  elseif op == Core.BinSub then
    if same_canonical_value(k.lhs, param_value, aliases) then
      local direction, note = recurrence_direction(
        k.rhs, defs, consts, Flow.FlowLoopDecreasing, Flow.FlowLoopIncreasing)
      return k.rhs, note, direction
    end
  end
  return nil, "binary recurrence does not reference the header parameter",
    Flow.FlowLoopDirectionUnknown
end

local function compare_stop(cond, induction_value, defs)
  local k = cond and defs[cond.text] or nil
  if k == nil then return nil, nil end
  local cmp_op = rawget(k, "op")
  if cmp_op == nil then return nil, nil end
  local lhs = rawget(k, "lhs")
  local rhs = rawget(k, "rhs")
  if lhs == nil or rhs == nil then return nil, nil end
  if lhs == induction_value then
    return rhs, (cmp_op == Core.CmpLt or cmp_op == Core.CmpGe)
  elseif rhs == induction_value then
    return lhs, (cmp_op == Core.CmpGt or cmp_op == Core.CmpLe)
  end
  return nil, nil
end
local function range_for_induction(value, init, stop, exclusive, consts)
  local min = consts[init.text] and Flow.FlowBoundConst(tostring(consts[init.text])) or Flow.FlowBoundValue(init)
  local max_val = stop and (consts[stop.text] and Flow.FlowBoundConst(tostring(consts[stop.text])) or Flow.FlowBoundValue(stop)) or Flow.FlowBoundUnknown
  return Flow.FlowRangeDerived(value, min, max_val, "recognized counted loop induction range"), min, max_val, exclusive == true
end

function Code.CodeInstOp:flow_numeric_const(_defs, _consts, _seen) return nil end
function Code.CodeInstAlias:flow_numeric_const(defs, consts, seen)
  return numeric_const(self.src, defs, consts, seen)
end
function Code.CodeInstCast:flow_numeric_const(defs, consts, seen)
  return numeric_const(self.value, defs, consts, seen)
end
numeric_const = function(value, defs, consts, seen)
  if value == nil then return nil end
  if consts[value.text] ~= nil then return consts[value.text] end
  seen = seen or {}
  if seen[value.text] then return nil end
  seen[value.text] = true
  local inst = defs[value.text]
  if inst == nil then return nil end
  return inst:flow_numeric_const(defs, consts, seen)
end


function Flow.FlowLoopDomainAbsent:append_native_loop_domain_facts()
  return self
end
function Flow.FlowLoopDomainProjected:append_native_loop_domain_facts(
    domain_shapes, domain_intents, loop_fact)
  local domain = loop_fact.domain
  domain_shapes[#domain_shapes + 1] = Flow.FlowDomainShapeFact(
    domain, self.shape, { self.proof }, Flow.FlowFactFrontendFact("lln.typed_domain"))
  domain_intents[#domain_intents + 1] = Flow.FlowDomainIntentFact(
    domain, Flow.FlowDomainIntentNativeLoop("lln.loop"),
    { self.proof }, Flow.FlowFactFrontendFact("lln.typed_domain"))
end
function Flow.FlowLoopDomainRejected:append_native_loop_domain_facts(
    _domain_shapes, _domain_intents, _loop_fact, _defs, _consts,
    _header_block, _edge_facts, _graph_loop, rejects)
  rejects[#rejects + 1] = Flow.FlowRejectDomainProjection(self.domain, self.reason)
  return self
end
local function append_native_loop_domain_facts(domain_shapes, domain_intents, loop_fact,
    defs, consts, header_block, edge_facts, graph_loop, rejects)
  local projection = header_block.origin:flow_project_loop_domain(
    Flow.FlowLoopDomainProjectionInput(
      loop_fact.domain, header_block, edge_facts, graph_loop))
  return projection:append_native_loop_domain_facts(
    domain_shapes, domain_intents, loop_fact, defs, consts,
    header_block, edge_facts, graph_loop, rejects)
end

----------------------------------------------------------------------
-- analyze_loop: core loop analysis
----------------------------------------------------------------------

local function analyze_loop(func, block_by_id, graph_loop, edge_facts, defs, types, consts)
  local rejects, inductions = {}, {}
  local latch = graph_loop.latches and graph_loop.latches[1] or nil
  if latch == nil then
    return Flow.FlowLoopFacts(graph_loop.id, Flow.FlowDomainLoop(graph_loop.id), nil, graph_loop.body or {}, {}, {}, { Flow.FlowRejectNotCounted(graph_loop.id, "loop has no latch edge") })
  end
  local header_block = block_by_id[graph_loop.header.block.text]
  local latch_fact = nil
  for _, fact in ipairs(edge_facts or {}) do if fact.edge == latch then latch_fact = fact; break end end
  if header_block == nil or latch_fact == nil then
    return Flow.FlowLoopFacts(graph_loop.id, Flow.FlowDomainLoop(graph_loop.id), nil, graph_loop.body or {}, {}, {}, { Flow.FlowRejectNotCounted(graph_loop.id, "loop header or latch edge is missing") })
  end

  local cond = edge_condition(block_by_id, latch)
  if cond == nil then
    for _, exit_edge in ipairs(graph_loop.exits or {}) do
      cond = cond or edge_condition(block_by_id, exit_edge)
    end
  end
  local loop_blocks = {}
  for _, block in ipairs(graph_loop.body or {}) do loop_blocks[block.block.text] = true end
  local aliases = {}
  local changed = true
  while changed do
    changed = false
    for _, fact in ipairs(edge_facts or {}) do
      local edge = fact.edge
      if edge ~= latch and loop_blocks[edge.from.block.text] and loop_blocks[edge.to.block.text] then
        for _, arg in ipairs(fact.args or {}) do
          local src = canonical_value(arg.src, aliases)
          if src ~= nil and src ~= arg.dst_param and aliases[arg.dst_param.text] == nil then
            aliases[arg.dst_param.text] = src
            changed = true
          end
        end
      end
    end
  end

  local counted = nil
  for _, param in ipairs(header_block.params or {}) do
    local init = incoming_arg_for(edge_facts, graph_loop.header.block, param, latch.from.block)
    local back = backedge_arg_for(latch_fact, param)
    if init ~= nil and back ~= nil then
      local step, note, direction = induction_step(
        param.value, back, defs, aliases, consts)
      if step ~= nil then
        local stop, exclusive = compare_stop(cond, param.value, defs)
        local range = Flow.FlowRangeUnknown(param.value)
        local role = Flow.FlowDerivedInduction(param.value)
        if stop ~= nil then
          local _, min, max_val, max_exclusive = range_for_induction(param.value, init, stop, exclusive, consts)
          range = Flow.FlowRangeDerived(param.value, min, max_val, "primary induction of counted loop")
          counted = counted or Flow.FlowCountedDomain(
            init, stop, step,
            exclusive == true and Flow.FlowStopExclusive or Flow.FlowStopInclusive,
            direction)
          role = Flow.FlowPrimaryInduction
        end
        inductions[#inductions + 1] = Flow.FlowInduction(param.value, types[param.value.text] or Code.CodeTyIndex, init, step, role, range)
        if note ~= nil then rejects[#rejects + 1] = Flow.FlowRejectUnsupportedInduction(graph_loop.id, param.value, note) end
      end
    end
  end
  if counted == nil then rejects[#rejects + 1] = Flow.FlowRejectNotCounted(graph_loop.id, "no header parameter matched a counted recurrence") end

  local exits = {}
  for _, edge in ipairs(graph_loop.exits or {}) do exits[#exits + 1] = Flow.FlowLoopExit(edge.from, edge.to, edge_condition(block_by_id, edge)) end
  return Flow.FlowLoopFacts(graph_loop.id, Flow.FlowDomainLoop(graph_loop.id), counted, graph_loop.body or {}, inductions, exits, rejects)
end

----------------------------------------------------------------------
-- edge_arg_facts: build edge argument facts for a function
----------------------------------------------------------------------

local function term_edge_args(func, block_by_id, block)
  local term = block.term and block.term.op or nil
  if term == nil then return {} end
  return term:code_flow_edge_args(block_by_id)
end

local function edge_arg_facts(func, graph_func, block_by_id)
  local by_from_to = {}
  for _, block in ipairs(func.blocks or {}) do
    local args_by_dest = term_edge_args(func, block_by_id, block)
    for dest, args in pairs(args_by_dest) do by_from_to[block.id.text .. "\0" .. dest] = args end
  end
  local out = {}
  for _, edge in ipairs(graph_func.edges or {}) do
    out[#out + 1] = Flow.FlowEdgeFact(edge, by_from_to[edge.from.block.text .. "\0" .. edge.to.block.text] or {})
  end
  return out
end

----------------------------------------------------------------------
-- block_index helper
----------------------------------------------------------------------

local function block_index(func)
  local by_id = {}
  for i, block in ipairs(func.blocks or {}) do by_id[block.id.text] = block end
  return by_id
end

----------------------------------------------------------------------
-- compute_flow: entry point — FlowFactSet from CodeModule + CodeGraph
----------------------------------------------------------------------

local function compute_flow_facts(module, graph)
  local graph_by_func = {}
  for _, fg in ipairs(graph.funcs or {}) do graph_by_func[fg.func.text] = fg end

  local domains, edge_facts, loops, ranges, domain_shapes, domain_intents, rejects = {}, {}, {}, {}, {}, {}, {}
  for _, func in ipairs(module.funcs or {}) do
    local graph_func = graph_by_func[func.id.text]
    if graph_func ~= nil then
      local block_by_id = block_index(func)
      domains[#domains + 1] = Flow.FlowDomainFunction(func.id)
      local func_edge_facts = edge_arg_facts(func, graph_func, block_by_id)
      for _, fact in ipairs(func_edge_facts) do edge_facts[#edge_facts + 1] = fact end

      local defs, types = value_defs(func)
      local consts = const_values(defs)
      for _, range in ipairs(const_ranges(defs)) do ranges[#ranges + 1] = range end

      for _, graph_loop in ipairs(graph_func.loops or {}) do
        domains[#domains + 1] = Flow.FlowDomainLoop(graph_loop.id)
        local lf = analyze_loop(func, block_by_id, graph_loop, func_edge_facts, defs, types, consts)
        loops[#loops + 1] = lf
        append_native_loop_domain_facts(domain_shapes, domain_intents, lf, defs, consts,
          block_by_id[graph_loop.header.block.text], func_edge_facts, graph_loop, rejects)
        for _, reject in ipairs(lf.rejects or {}) do rejects[#rejects + 1] = reject end
      end
    end
  end
  return Flow.FlowFactSet(
    module.id, domains, edge_facts, loops, ranges, domain_shapes, domain_intents, rejects)
end

function Graph.CodeGraph:compute_flow(module)
  return compute_flow_facts(module, self)
end

----------------------------------------------------------------------
-- compute_semantic_flow: FlowSemanticFactSet from FlowFactSet
----------------------------------------------------------------------


function Flow.FlowStopExclusive:flow_trip_expression(counted, diff_expr, step_is_one, idx_ty)
  if step_is_one then return diff_expr end
  return Value.ValueExprBinary(
    Core.BinDiv, diff_expr, Value.ValueExprValue(counted.step), idx_ty)
end

function Flow.FlowStopInclusive:flow_trip_expression(counted, diff_expr, step_is_one, idx_ty)
  local adj_step = Value.ValueExprValue(counted.step)
  local adj_expr = Value.ValueExprBinary(Core.BinAdd, diff_expr, adj_step, idx_ty)
  if step_is_one then return adj_expr end
  return Value.ValueExprBinary(Core.BinDiv, adj_expr, adj_step, idx_ty)
end

local function compute_trip_expr(counted, consts)
  if counted == nil or counted.start == nil or counted.stop == nil then return nil end
  local idx_ty = Code.CodeTyIndex
  local diff_expr = Value.ValueExprBinary(Core.BinSub,
    Value.ValueExprValue(counted.stop),
    Value.ValueExprValue(counted.start),
    idx_ty)
  local step_is_one = counted.step and consts[counted.step.text] == 1
  return counted.stop_convention:flow_trip_expression(counted, diff_expr, step_is_one, idx_ty)
end

function Flow.FlowStopConvention:flow_materialize_trip(counted, _defs, _consts, trip_expr, _trip_entry)
  return Flow.FlowTripCountRejected(
    Flow.FlowTripCountNotMaterialized(
      "trip-count expression has no materialized CodeValueId"), trip_expr)
end
function Flow.FlowStopExclusive:flow_materialize_trip(counted, defs, consts, trip_expr, trip_entry)
  local start = numeric_const(counted.start, defs, consts)
  local step = numeric_const(counted.step, defs, consts)
  if start == 0 and step == 1 then
    local value = trip_entry:flow_trip_value(counted.stop)
    return Flow.FlowTripCountExact(
      value, Value.ValueExprValue(value), nil)
  end
  return Flow.FlowTripCountRejected(
    Flow.FlowTripCountNotMaterialized(
      "only zero-based unit-stride trips are directly materialized"), trip_expr)
end

function Graph.CodeGraph:flow_graph_loop_projection()
  local entries = {}
  for i = 1, #self.funcs do
    for j = 1, #self.funcs[i].loops do
      entries[#entries + 1] = Flow.FlowGraphLoopEntry(self.funcs[i].loops[j])
    end
  end
  return Flow.FlowGraphLoopProjection(entries)
end
function Flow.FlowGraphLoopProjection:lookup(id)
  for i = 1, #self.entries do
    if self.entries[i].loop.id == id then return Flow.FlowGraphLoopFound(self.entries[i]) end
  end
  return Flow.FlowGraphLoopMissing(id)
end
function Flow.FlowGraphLoopMissing:flow_trip_entry(_input)
  return Flow.FlowTripEntryFallback
end
function Flow.FlowGraphLoopFound:flow_trip_entry(input)
  local graph_loop = self.entry.loop
  for i = 1, #input.module.funcs do
    for j = 1, #input.module.funcs[i].blocks do
      local header = input.module.funcs[i].blocks[j]
      if header.id == graph_loop.header.block then
        local param = code_param_by_value(header, input.counted.stop)
        if param == nil then return Flow.FlowTripEntryFallback end
        local latch = graph_loop.latches and graph_loop.latches[1] or nil
        local skip = latch and latch.from and latch.from.block or nil
        local value = incoming_arg_for(
          input.edges, graph_loop.header.block, param, skip)
        if value ~= nil then return Flow.FlowTripEntryFound(value) end
        return Flow.FlowTripEntryFallback
      end
    end
  end
  return Flow.FlowTripEntryFallback
end
function Flow.FlowTripEntryFound:flow_trip_value(_fallback) return self.value end
function Flow.FlowTripEntryFallback:flow_trip_value(fallback) return fallback end

function Flow.FlowFactSet:compute_semantic_flow(module, graph)
  local defs_by_func, consts_by_func = {}, {}
  for _, func in ipairs(module.funcs or {}) do
    local defs = value_defs(func)
    defs_by_func[func.id.text] = defs
    consts_by_func[func.id.text] = const_values(defs)
  end

  local graph_loops = graph and graph:flow_graph_loop_projection()
    or Flow.FlowGraphLoopProjection({})
  local graph_loop_func = {}
  if graph ~= nil then
    for _, fg in ipairs(graph.funcs or {}) do
      for _, loop in ipairs(fg.loops or {}) do
        graph_loop_func[loop.id.text] = fg.func
      end
    end
  end

  local out = {}
  for _, loop in ipairs(self.loops or {}) do
    if loop.counted ~= nil then
      local primary = nil
      for _, induction in ipairs(loop.inductions or {}) do
        if induction.role == Flow.FlowPrimaryInduction then primary = primary or induction end
      end
      local func_id = graph_loop_func[loop.loop.text]
      local defs = func_id and defs_by_func[func_id.text] or {}
      local consts = func_id and consts_by_func[func_id.text] or {}
      local direction = loop.counted.direction
      local trip_expr = compute_trip_expr(loop.counted, consts)
      local trip_entry = graph_loops:lookup(loop.loop):flow_trip_entry(
        Flow.FlowTripEntryInput(module, loop.counted, self.edges))
      local trip_count = loop.counted.stop_convention:flow_materialize_trip(
        loop.counted, defs, consts, trip_expr, trip_entry)
      out[#out + 1] = Flow.FlowLoopNormalizedCounted(loop.loop, loop.counted, direction, trip_count)
      if primary ~= nil and direction == Flow.FlowLoopIncreasing
          and loop.counted.stop_convention == Flow.FlowStopExclusive then
        local _, min, max_val = range_for_induction(
          primary.value, loop.counted.start, loop.counted.stop, true, consts)
        out[#out + 1] = Flow.FlowLoopInductionRange(Flow.FlowInductionRangeFact(
          loop.loop, primary.value, min, max_val, true,
          "primary induction of increasing exclusive counted loop stays within [start, stop) on executed iterations"))
      end
    end
  end
  return Flow.FlowSemanticFactSet(module.id, out)
end
