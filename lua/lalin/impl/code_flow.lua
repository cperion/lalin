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

local function recurrence_direction(step, consts, positive, negative)
  local value = step and consts[step.text] or nil
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
        k.rhs, consts, Flow.FlowLoopIncreasing, Flow.FlowLoopDecreasing)
      return k.rhs, note, direction
    end
    if same_canonical_value(k.rhs, param_value, aliases) then
      local direction, note = recurrence_direction(
        k.lhs, consts, Flow.FlowLoopIncreasing, Flow.FlowLoopDecreasing)
      return k.lhs, note, direction
    end
  elseif op == Core.BinSub then
    if same_canonical_value(k.lhs, param_value, aliases) then
      local direction, note = recurrence_direction(
        k.rhs, consts, Flow.FlowLoopDecreasing, Flow.FlowLoopIncreasing)
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

local function numeric_const(value, defs, consts, seen)
  if value == nil then return nil end
  if consts[value.text] ~= nil then return consts[value.text] end
  seen = seen or {}
  if seen[value.text] then return nil end
  seen[value.text] = true
  local k = defs[value.text]
  if k ~= nil and rawget(k, "value") ~= nil and rawget(k, "src") ~= nil then
    -- CodeInstAlias path
    return numeric_const(k.src, defs, consts, seen)
  end
  if k ~= nil and rawget(k, "from") ~= nil and rawget(k, "to") ~= nil then
    -- CodeInstCast path
    return numeric_const(k.value, defs, consts, seen)
  end
  return nil
end

local function native_window_boundary(name)
  if name == "clamp" then return Flow.FlowWindowBoundaryClamp end
  if name == "wrap" then return Flow.FlowWindowBoundaryWrap end
  if name == "zero" then return Flow.FlowWindowBoundaryZero end
  return Flow.FlowWindowBoundaryReject
end

local function native_nd_shape_from_header(header_name, axes)
  local stem = tostring(header_name or ""):gsub("_scan_axis_%d+$", "")
  local tiled = stem:match("_tiled_([%dx]+)$")
  if tiled ~= nil then
    local tile_sizes = {}
    for raw in tiled:gmatch("%d+") do tile_sizes[#tile_sizes + 1] = tonumber(raw) end
    if #tile_sizes == #axes then return Flow.FlowDomainShapeTiledND(axes, tile_sizes) end
  end
  local window = stem:match("_window_(.+)$")
  if window ~= nil then
    local windows = {}
    for boundary, before, after in window:gmatch("([a-z]+)_(%d+)_(%d+)") do
      windows[#windows + 1] = Flow.FlowWindowAxis(tonumber(before), tonumber(after), native_window_boundary(boundary))
    end
    if #windows == #axes then return Flow.FlowDomainShapeWindowND(axes, windows) end
  end
  return Flow.FlowDomainShapeRangeND(axes)
end

local function native_nd_axis_facts(header_block, edge_facts, graph_loop)
  if type(header_block and header_block.name) ~= "string" or header_block.name:match("^ctl%.lln_loop_nd_") == nil then return nil end
  local latch = graph_loop and graph_loop.latches and graph_loop.latches[1] or nil
  local skip_from = latch and latch.from and latch.from.block or nil
  local grouped = {}
  for _, param in ipairs(header_block.params or {}) do
    local axis_i, index_name, field, step, order = tostring(param.name or ""):match("^__lln_axis_[^_]+_(%d+)_idx_([_%a][_%w]*)_(%a+)_step_(%d+)_order_(%a+)$")
    if axis_i == nil then
      axis_i, field, step, order = tostring(param.name or ""):match("^__lln_axis_[^_]+_(%d+)_(%a+)_step_(%d+)_order_(%a+)$")
    end
    if axis_i ~= nil and (field == "start" or field == "stop" or field == "trip") then
      axis_i = tonumber(axis_i)
      grouped[axis_i] = grouped[axis_i] or { step = tonumber(step), order = order, ty = param.ty }
      grouped[axis_i][field] = incoming_arg_for(edge_facts, graph_loop.header.block, param, skip_from)
      grouped[axis_i].ty = grouped[axis_i].ty or param.ty
      grouped[axis_i].index_name = grouped[axis_i].index_name or index_name
    end
  end
  local axes = {}
  local i = 1
  while grouped[i] ~= nil do
    local axis = grouped[i]
    if axis.start == nil or axis.stop == nil or axis.step == nil then return nil end
    axes[#axes + 1] = Flow.FlowDomainAxis(
      axis.ty or Code.CodeTyIndex,
      Value.ValueExprValue(axis.start),
      Value.ValueExprValue(axis.stop),
      axis.step,
      axis.order == "backward" and Flow.FlowDomainBackward or Flow.FlowDomainForward,
      axis.index_name
    )
    i = i + 1
  end
  if #axes < 1 then return nil end
  return native_nd_shape_from_header(header_block.name, axes)
end

local function append_native_loop_domain_facts(domain_shapes, domain_intents, loop_fact, defs, consts, header_block, edge_facts, graph_loop)
  local domain = loop_fact and loop_fact.domain
  local nd_shape = native_nd_axis_facts(header_block, edge_facts, graph_loop)
  if nd_shape ~= nil then
    local proof = Flow.FlowProofDomain(domain, "lln.loop authored an explicit multi-axis producer")
    domain_shapes[#domain_shapes + 1] = Flow.FlowDomainShapeFact(
      domain, nd_shape, { proof }, Flow.FlowFactFrontendFact("lln.nd_producer"))
    domain_intents[#domain_intents + 1] = Flow.FlowDomainIntentFact(
      domain, Flow.FlowDomainIntentNativeLoop("lln.loop"),
      { Flow.FlowProofFrontendFact("lln.loop authored this loop domain") },
      Flow.FlowFactFrontendFact("lln.loop"))
    return
  end

  local counted = loop_fact and loop_fact.counted
  local primary = nil
  for _, induction in ipairs(loop_fact and loop_fact.inductions or {}) do
    if induction.role == Flow.FlowPrimaryInduction then primary = primary or induction end
  end
  if counted == nil or primary == nil then return end
  local step_num = numeric_const(counted.step, defs, consts)
  if step_num == nil or step_num == 0 then return end
  local order = step_num < 0 and Flow.FlowDomainBackward or Flow.FlowDomainForward
  local proof = Flow.FlowProofDomain(domain, "lln.loop authored a regular counted range")
  domain_shapes[#domain_shapes + 1] = Flow.FlowDomainShapeFact(
    domain,
    Flow.FlowDomainShapeRange1D(
      primary.ty or Code.CodeTyIndex,
      Value.ValueExprValue(counted.start),
      Value.ValueExprValue(counted.stop),
      math.abs(step_num),
      order
    ),
    { proof },
    Flow.FlowFactFrontendFact("lln.range")
  )
  domain_intents[#domain_intents + 1] = Flow.FlowDomainIntentFact(
    domain, Flow.FlowDomainIntentNativeLoop("lln.loop"),
    { Flow.FlowProofFrontendFact("lln.loop authored this loop domain") },
    Flow.FlowFactFrontendFact("lln.loop"))
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

local function is_native_loop_header(block_by_id, graph_loop)
  local header = graph_loop and graph_loop.header and block_by_id[graph_loop.header.block.text]
  return type(header and header.name) == "string" and header.name:match("^ctl%.lln_loop_") ~= nil
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
        if is_native_loop_header(block_by_id, graph_loop) then
          append_native_loop_domain_facts(domain_shapes, domain_intents, lf, defs, consts, block_by_id[graph_loop.header.block.text], func_edge_facts, graph_loop)
        end
        for _, reject in ipairs(lf.rejects or {}) do rejects[#rejects + 1] = reject end
      end
    end
  end
  return Flow.FlowFactSet(module.id, domains, edge_facts, loops, ranges, domain_shapes, domain_intents, {}, {}, rejects)
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

function Flow.FlowFactSet:compute_semantic_flow(module, graph)
  local defs_by_func, consts_by_func = {}, {}
  for _, func in ipairs(module.funcs or {}) do
    local defs = value_defs(func)
    defs_by_func[func.id.text] = defs
    consts_by_func[func.id.text] = const_values(defs)
  end

  local graph_loop_func = {}
  if graph ~= nil then
    for _, fg in ipairs(graph.funcs or {}) do
      for _, loop in ipairs(fg.loops or {}) do graph_loop_func[loop.id.text] = fg.func end
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
      local consts = func_id and consts_by_func[func_id.text] or {}
      local direction = loop.counted.direction
      local trip_expr = compute_trip_expr(loop.counted, consts)
      local trip_count
      if trip_expr ~= nil then
        trip_count = Flow.FlowTripCountRejected(
          Flow.FlowTripCountNotMaterialized("trip-count expression has no materialized CodeValueId"),
          trip_expr)
      else
        trip_count = Flow.FlowTripCountRejected(
          Flow.FlowTripCountNotMaterialized("no explicit trip-count CodeValueId is available"),
          nil)
      end
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
