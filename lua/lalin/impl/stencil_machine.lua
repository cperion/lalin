-- impl/stencil_machine.lua
-- Leaf methods on LalinStencilMachine types.
-- Ported from stencil_methods.lua (StencilMachine.* methods only).
--
-- Also installs methods on some Code.*, Core.*, Value.*, and Kernel.* types
-- that are needed by StencilMachine internals.  The CRITICAL mandate sorts
-- each receiver to its correct impl file; this file absorbs the methods that
-- are tightly coupled to stencil-machine logic (classification, expression
-- lowering, selection, planning).

require("lalin.schema_v2")

local SM      = require("lalin.schema_v2.stencil_machine")
local Stencil = require("lalin.schema_v2.stencil")
local Code    = require("lalin.schema_v2.code")
local Value   = require("lalin.schema_v2.value")
local Core    = require("lalin.schema_v2.core")
local Kernel  = require("lalin.schema_v2.kernel")

----------------------------------------------------------------------
-- helpers (local helpers from stencil_methods.lua)
----------------------------------------------------------------------

local function access_ref(name)
  return Stencil.StencilAccessRef(name)
end

local function input_expr(name)
  return Stencil.StencilPointInput(access_ref(name))
end

local function const_expr(value, ty)
  return Stencil.StencilPointConst(value, ty)
end

local function point_unary_expr(op, arg, result_ty)
  return Stencil.StencilPointUnary(op, arg, result_ty, nil, nil)
end

local function point_binary_expr(op, left, right, result_ty, int_semantics)
  return Stencil.StencilPointBinary(op, left, right, result_ty, int_semantics, nil)
end

local function point_cast_expr(op, arg, from, to)
  return Stencil.StencilPointCast(op, arg, from, to)
end

local function point_predicate_expr(pred, arg, result_ty)
  return Stencil.StencilPointPredicate(pred, arg, result_ty)
end

local function point_compare_expr(cmp, left, right, result_ty)
  return Stencil.StencilPointCompare(cmp, left, right, result_ty)
end

local function point_select_expr(cond, then_expr, else_expr, result_ty)
  return Stencil.StencilPointSelect(Stencil.StencilPredNonZero, cond, then_expr, else_expr, result_ty)
end

local function scalar_input_expr(value, state)
  local name = "x" .. tostring(#state.inputs + 1)
  state.inputs[#state.inputs + 1] = SM.StencilMachinePointInput(
    name, nil, nil, value, nil, nil, nil, nil,
    Stencil.StencilLayoutScalar(value),
    Stencil.StencilAccessRead,
    true, nil, {}
  )
  return input_expr(name)
end

local function lane_key(lane, index)
  local id = lane and lane.id and lane.id.text or tostring(lane)
  return id .. "@" .. tostring(index)
end

local function point_input_for_load(expr, state)
  local key = lane_key(expr.lane, expr.index)
  local existing = state.by_key[key]
  if existing ~= nil then return input_expr(existing.name), existing:point_ty() end
  local name = "x" .. tostring(#state.inputs + 1)
  local input = SM.StencilMachinePointInputLane(
    name, expr.lane, expr.index, expr.lane.elem_ty
  )
  state.by_key[key] = input
  state.inputs[#state.inputs + 1] = input
  return input_expr(name), input:point_ty()
end

local function copy_inputs(inputs)
  local out = {}
  for i, input in ipairs(inputs or {}) do out[i] = input end
  return out
end

local function append_input_once(inputs, input)
  for _, existing in ipairs(inputs or {}) do
    if existing.name == input.name then return inputs end
  end
  inputs[#inputs + 1] = input
  return inputs
end

local function specialize_scalar_inputs(inputs, ty)
  local out = {}
  for i, input in ipairs(inputs or {}) do
    -- note: asdl.with removed — use raw constructor paths
    if input:point_scalar_value() ~= nil and input:point_ty() == nil then
      out[i] = SM.StencilMachinePointInputScalar(
        input.name, nil, nil, input.scalar_value, nil, nil, nil, nil,
        Stencil.StencilLayoutScalar(input.scalar_value),
        Stencil.StencilAccessRead, true, nil, {}
      )
    else
      out[i] = input
    end
  end
  return out
end

local function indexed_layout(parent, idx, step_num)
  return Stencil.StencilLayoutIndexed(parent, access_ref(idx.name), idx.ty or idx.elem_ty, step_num or 1)
end

local function predicate_from_cmp_const(op, operand_ty, cexpr, const_on_left)
  -- Dispatch through leaf method on ValueExprConst
  local result = cexpr:predicate_from_cmp_const(op, operand_ty, const_on_left)
  if result == nil then return nil end
  if const_on_left then
    op = result.op
    -- Swap: if const was on the left, the comparison direction flips
    if op == Core.CmpLt then op = Core.CmpGt
    elseif op == Core.CmpLe then op = Core.CmpGe
    elseif op == Core.CmpGt then op = Core.CmpLt
    elseif op == Core.CmpGe then op = Core.CmpLe end
  end
  if op == Core.CmpEq or op == Core.CmpNe or op == Core.CmpLt or op == Core.CmpLe or op == Core.CmpGt or op == Core.CmpGe then
    return Stencil.StencilPredCompareConst(op, operand_ty, result.cexpr)
  end
  return nil
end

----------------------------------------------------------------------
-- Value.ValueExpr → predicate_from_cmp_const (leaf dispatch)
----------------------------------------------------------------------

function Value.ValueExpr:predicate_from_cmp_const(op, operand_ty, const_on_left)
  return nil
end

function Value.ValueExprConst:predicate_from_cmp_const(op, operand_ty, const_on_left)
  return { op = op, cexpr = self }
end

----------------------------------------------------------------------
-- Code.CodeConst / Value.ValueExpr → const int / const ty
----------------------------------------------------------------------

function Core.Literal:stencil_const_int() return nil end
function Core.LitInt:stencil_const_int() return tonumber(self.raw) end

function Code.CodeConst:stencil_const_int() return nil end
function Code.CodeConstLiteral:stencil_const_int()
  return self.literal:stencil_const_int()
end

function Value.ValueExpr:stencil_const_int() return nil end
function Value.ValueExprConst:stencil_const_int() return self.const:stencil_const_int() end

function Value.ValueExpr:stencil_const_ty() return nil end
function Value.ValueExprConst:stencil_const_ty() return self.const.ty end

----------------------------------------------------------------------
-- StencilMachinePointExprFacts
----------------------------------------------------------------------

function SM.StencilMachinePointExprFacts:point_input_named(name)
  for _, input in ipairs(self.inputs or {}) do
    if input.name == name then return input end
  end
  return nil
end

function SM.StencilMachinePointExprFacts:single_point_input()
  if #(self.inputs or {}) ~= 1 then return nil end
  return self.inputs[1]
end

function SM.StencilMachinePointExprFacts:all_inputs_primary()
  for _, input in ipairs(self.inputs or {}) do
    if input:point_is_primary() ~= true then return false end
  end
  return true
end

----------------------------------------------------------------------
-- StencilMachineExprFact → to_stencil_point_expr
----------------------------------------------------------------------

function SM.StencilMachineExprFact:to_stencil_point_expr()
  return nil, nil, "unsupported store stencil expression"
end

function SM.StencilMachineExprFact:stencil_const_int()
  return nil
end

function SM.StencilMachineExprFact:stencil_compare_const_predicate()
  return nil
end

function SM.StencilMachineExprKernelValue:to_stencil_point_expr(state)
  return self.binding:to_stencil_point_expr(state)
end

function SM.StencilMachineExprLoad:to_stencil_point_expr(state)
  return point_input_for_load(self, state)
end

function SM.StencilMachineExprFill:to_stencil_point_expr(state)
  local ty = self.value:stencil_const_ty()
  if ty == nil then return scalar_input_expr(self.value, state), nil end
  return const_expr(self.value, ty), ty
end

function SM.StencilMachineExprFill:stencil_const_int()
  return self.value:stencil_const_int()
end

function SM.StencilMachineExprUnary:to_stencil_point_expr(state)
  if self.op == nil then return nil, nil, "unsupported unary stencil operator" end
  local arg, _, err = self.value:to_stencil_point_expr(state)
  if arg == nil then return nil, nil, err end
  return point_unary_expr(self.op, arg, self.result_ty), self.result_ty
end

function SM.StencilMachineExprCast:to_stencil_point_expr(state)
  local arg, _, err = self.value:to_stencil_point_expr(state)
  if arg == nil then return nil, nil, err end
  return point_cast_expr(self.op, arg, self.src_ty, self.result_ty), self.result_ty
end

function SM.StencilMachineExprBinary:to_stencil_point_expr(state)
  if self.op == nil then return nil, nil, "unsupported binary stencil operator" end
  local lhs, _, lhs_err = self.lhs:to_stencil_point_expr(state)
  if lhs == nil then return nil, nil, lhs_err end
  local rhs, _, rhs_err = self.rhs:to_stencil_point_expr(state)
  if rhs == nil then return nil, nil, rhs_err end
  return point_binary_expr(self.op, lhs, rhs, self.result_ty, self.int_semantics), self.result_ty
end

function SM.StencilMachineExprCmp:to_stencil_point_expr(state)
  local lhs, lhs_ty, lhs_err = self.lhs:to_stencil_point_expr(state)
  if lhs == nil then return nil, nil, lhs_err end
  local rhs, rhs_ty, rhs_err = self.rhs:to_stencil_point_expr(state)
  if rhs == nil then return nil, nil, rhs_err end
  local pred, arg = self.lhs:stencil_compare_const_predicate(self.op, lhs, lhs_ty, self.rhs, rhs, rhs_ty)
  if pred ~= nil then return point_predicate_expr(pred, arg, self.result_ty), self.result_ty end
  return point_compare_expr(self.op, lhs, rhs, self.result_ty), self.result_ty
end

function SM.StencilMachineExprSelect:to_stencil_point_expr(state)
  local cond, _, cond_err = self.cond:to_stencil_point_expr(state)
  if cond == nil then return nil, nil, cond_err end
  local t, result_ty, t_err = self.then_fact:to_stencil_point_expr(state)
  if t == nil then return nil, nil, t_err end
  local f, _, f_err = self.else_fact:to_stencil_point_expr(state)
  if f == nil then return nil, nil, f_err end
  return point_select_expr(cond, t, f, result_ty), result_ty
end

-- Compare-const predicate helpers
function SM.StencilMachineExprLoad:stencil_compare_const_predicate(op, lhs_expr, lhs_ty, rhs, rhs_expr, rhs_ty)
  return rhs:stencil_compare_const_predicate_from_left_load(op, lhs_expr, lhs_ty, rhs_expr, rhs_ty)
end

function SM.StencilMachineExprFact:stencil_compare_const_predicate_from_left_load()
  return nil
end

function SM.StencilMachineExprFill:stencil_compare_const_predicate_from_left_load(op, lhs_expr, lhs_ty)
  return predicate_from_cmp_const(op, lhs_ty, self.value, false), lhs_expr
end

function SM.StencilMachineExprFill:stencil_compare_const_predicate(op, op_expr, op_ty, rhs, rhs_expr, rhs_ty)
  return rhs:stencil_compare_const_predicate_from_left_fill(op, self.value, rhs_expr, rhs_ty)
end

function SM.StencilMachineExprFact:stencil_compare_const_predicate_from_left_fill()
  return nil
end

function SM.StencilMachineExprLoad:stencil_compare_const_predicate_from_left_fill(op, const_value, rhs_expr, rhs_ty)
  return predicate_from_cmp_const(op, rhs_ty, const_value, true), rhs_expr
end

----------------------------------------------------------------------
-- StencilMachinePointExprFacts:select_index_lane
----------------------------------------------------------------------

function SM.StencilMachinePointExprFacts:select_index_lane()
  local input = self.expr:stencil_index_input(self)
  if input ~= nil then return { lane = input:point_lane(), index = input:point_index() } end
  return nil
end

----------------------------------------------------------------------
-- Stencil.StencilPointExpr → index/const/single-input helpers
----------------------------------------------------------------------

function Stencil.StencilPointExpr:stencil_single_input_expr() return nil end
function Stencil.StencilPointInput:stencil_single_input_expr(point_facts)
  return point_facts:point_input_named(self.access.name)
end

function Stencil.StencilPointExpr:stencil_const_int() return nil end
function Stencil.StencilPointConst:stencil_const_int()
  return self.value:stencil_const_int()
end

function Stencil.StencilPointExpr:stencil_index_input() return nil end
function Stencil.StencilPointInput:stencil_index_input(point_facts)
  return point_facts:point_input_named(self.access.name)
end
function Stencil.StencilPointCast:stencil_index_input(point_facts)
  return self.arg:stencil_index_input(point_facts)
end
function Stencil.StencilPointBinary:stencil_index_input(point_facts)
  local lc, rc = self.left:stencil_const_int(), self.right:stencil_const_int()
  if (self.op == Stencil.StencilBinaryMul and rc == 1)
      or (self.op == Stencil.StencilBinaryAdd and rc == 0)
      or (self.op == Stencil.StencilBinarySub and rc == 0) then
    return self.left:stencil_index_input(point_facts)
  end
  if (self.op == Stencil.StencilBinaryMul and lc == 1)
      or (self.op == Stencil.StencilBinaryAdd and lc == 0) then
    return self.right:stencil_index_input(point_facts)
  end
  return nil
end

function Stencil.StencilPointExpr:stencil_predicate_operand() return nil, nil end
function Stencil.StencilPointPredicate:stencil_predicate_operand(point_facts)
  local input = self.arg:stencil_single_input_expr(point_facts)
  if input == nil then return nil, nil end
  return input, self.pred
end
function Stencil.StencilPointCompare:stencil_predicate_operand(point_facts)
  local input = self.left:stencil_single_input_expr(point_facts)
  if input == nil then return nil, nil end
  return self.right:stencil_compare_const_predicate_for_input(input, self.cmp)
end

function Stencil.StencilPointExpr:stencil_compare_const_predicate_for_input()
  return nil, nil
end
function Stencil.StencilPointConst:stencil_compare_const_predicate_for_input(input, cmp)
  return input, Stencil.StencilPredCompareConst(cmp, input:point_ty(), self.value)
end

----------------------------------------------------------------------
-- StencilMachineStoreSelectionFacts
----------------------------------------------------------------------

function SM.StencilMachineStoreSelectionFacts:store_n_descriptor(inputs, dst_layout, store_mode)
  local point_facts = self.point_facts
  inputs = inputs or point_facts.inputs
  store_mode = store_mode or self.store_mode
  if store_mode == nil and self.copy_semantics ~= nil then
    store_mode = Stencil.StencilStoreCopy(self.copy_semantics)
  end
  local result_ty = point_facts.result_ty or self.dst_elem_ty
  return SM.StencilMachineStoreNDescriptor(
    self.step_num, self.producer, result_ty, self.dst,
    dst_layout or self.dst_layout,
    specialize_scalar_inputs(inputs, result_ty),
    point_facts.expr, store_mode,
    "expr" .. tostring(#(inputs or {})),
    self.start_expr, self.stop_expr, nil, nil
  )
end

function SM.StencilMachineStoreSelectionFacts:select_store_stencil()
  local point_facts = self.point_facts
  if self.store_index_primary == true and (point_facts.result_ty == nil or point_facts.result_ty:stencil_same_type(self.dst_elem_ty))
      and point_facts:all_inputs_primary() and (point_facts.result_ty or self.dst_elem_ty):stencil_supported_type() and self.dst_elem_ty:stencil_supported_type() then
    return SM.StencilMachineSelectStoreN(self:store_n_descriptor(), {})
  end
  if self.store_index_primary == true and (point_facts.result_ty == nil or point_facts.result_ty:stencil_same_type(self.dst_elem_ty))
      and (point_facts.result_ty or self.dst_elem_ty):stencil_supported_type() and self.dst_elem_ty:stencil_supported_type() then
    local inputs, ok = copy_inputs(point_facts.inputs), true
    for i, input in ipairs(inputs) do
      if input:point_is_primary() ~= true then
        local idx = input:point_index_lane()
        if idx == nil or not idx.ty:stencil_is_index_data_type() then ok = false; break end
        -- reconstruct input with indexed layout
        inputs[i] = SM.StencilMachinePointInputIndex(
          input.name, nil, nil, input.ty, input.elem_ty,
          indexed_layout(input:point_layout(), idx, self.step_num),
          true, idx
        )
        append_input_once(inputs, idx)
      end
    end
    if ok then
      return SM.StencilMachineSelectStoreN(self:store_n_descriptor(inputs, nil, nil), {})
    end
  end
  if self.store_index_lane ~= nil
      and (point_facts.result_ty == nil or point_facts.result_ty:stencil_same_type(self.dst_elem_ty)) and point_facts:all_inputs_primary()
      and self.store_index_lane.elem_ty:stencil_is_index_data_type() and (point_facts.result_ty or self.dst_elem_ty):stencil_supported_type() and self.dst_elem_ty:stencil_supported_type() then
    local idx = SM.StencilMachinePointInputIndex(
      "dst_idx", self.store_index_lane.base, self.store_index_lane.base_expr,
      self.store_index_lane.elem_ty, self.store_index_lane.elem_ty,
      self.store_index_lane.layout, true, nil
    )
    local inputs = copy_inputs(point_facts.inputs)
    append_input_once(inputs, idx)
    return SM.StencilMachineSelectStoreN(
      self:store_n_descriptor(inputs, indexed_layout(self.dst_layout, idx, self.step_num),
        Stencil.StencilStoreScatter(self.scatter_conflicts or Stencil.StencilScatterUniqueIndices)),
      {}
    )
  end
  return nil, "unsupported store stencil shape"
end

----------------------------------------------------------------------
-- StencilMachineScanSelectionFacts
----------------------------------------------------------------------

function SM.StencilMachineScanSelectionFacts:select_scan_stencil()
  local input = self.point_facts:single_point_input()
  if input ~= nil and self.store_index_primary == true and input:point_is_primary() == true
      and self.result_ty:stencil_same_type(self.dst_elem_ty)
      and self.result_ty:stencil_reduction_supported(self.reduction_op, input:point_ty()) then
    return SM.StencilMachineSelectScan(self.reduction, SM.StencilMachineScanArrayDescriptor(
      self.step_num, self.producer, input:point_ty(), self.result_ty,
      self.init, self.mode, self.axis, self.dst,
      input:point_base(), self.dst_layout, input:point_layout(),
      self.start_expr, self.stop_expr, nil, nil
    ), { self.dst_expr, input:point_base_expr(), self.start_expr, self.stop_expr, self.init_expr })
  end
  return nil, "unsupported scan stencil shape"
end

----------------------------------------------------------------------
-- StencilMachineFindSelectionFacts
----------------------------------------------------------------------

function SM.StencilMachineFindSelectionFacts:select_find_stencil()
  local input = self.point_facts:single_point_input()
  if input ~= nil and input:point_is_primary() == true and self.not_found_minus_one == true and input:point_ty():stencil_supported_type() then
    return SM.StencilMachineSelectFind(self.pred, SM.StencilMachineFindArrayDescriptor(
      self.step_num, self.producer, input:point_ty(),
      input:point_base(), input:point_layout(),
      self.start_expr, self.stop_expr, nil, nil
    ), { input:point_base_expr(), self.start_expr, self.stop_expr })
  end
  return nil, "unsupported find stencil shape"
end

----------------------------------------------------------------------
-- StencilMachinePartitionSelectionFacts
----------------------------------------------------------------------

function SM.StencilMachinePartitionSelectionFacts:select_partition_stencil()
  local input = self.point_facts:single_point_input()
  if input ~= nil and self.store_index_primary == true and input:point_is_primary() == true
      and input:point_ty():stencil_same_type(self.dst_elem_ty) and input:point_ty():stencil_supported_type() and self.dst_elem_ty:stencil_supported_type() then
    return SM.StencilMachineSelectPartition(self.pred, SM.StencilMachinePartitionArrayDescriptor(
      self.step_num, self.producer, input:point_ty(),
      self.dst, input:point_base(), self.dst_layout, input:point_layout(),
      self.start_expr, self.stop_expr, self.semantics, nil, nil
    ), { self.dst_expr, input:point_base_expr(), self.start_expr, self.stop_expr })
  end
  return nil, "unsupported partition stencil shape"
end

----------------------------------------------------------------------
-- StencilMachineReduceSelectionFacts
----------------------------------------------------------------------

function SM.StencilMachineReduceSelectionFacts:select_reduce_stencil()
  local point_facts = self.point_facts
  if point_facts:all_inputs_primary()
      and self.result_ty:stencil_reduction_supported(self.reduction_op, point_facts.result_ty) then
    return SM.StencilMachineSelectReduceN(SM.StencilMachineReduceNDescriptor(
      self.step_num, self.producer, self.result_ty, point_facts.result_ty,
      self.init, point_facts.inputs, point_facts.expr,
      nil, "expr" .. tostring(#(point_facts.inputs or {})),
      self.start_expr, self.stop_expr, nil, nil
    ), {})
  end
  local pred_input, pred = point_facts.expr:stencil_predicate_operand(point_facts)
  if pred_input ~= nil and pred_input.index_primary == true and self.reduction_add == true
      and self.init_zero == true and self.result_i32 == true then
    return SM.StencilMachineSelectCount(pred, SM.StencilMachineCountArrayDescriptor(
      self.step_num, self.producer, pred_input:point_ty(),
      self.result_ty, self.init, pred_input.base, pred_input.layout,
      self.start_expr, self.stop_expr, nil, nil
    ), { pred_input.base_expr, self.start_expr, self.stop_expr })
  end
  return nil, "unsupported reduction stencil contribution"
end

----------------------------------------------------------------------
-- StencilMachineStorePlanInput / StencilMachineReducePlanInput
----------------------------------------------------------------------

function SM.StencilMachineStorePlanInput:reject_reason(suffix)
  return ("store stencil is not ready: planned=%s returns_void=%s counted_positive=%s single_store=%s dst_base_present=%s point_facts_ready=%s (%s)"):format(
    tostring(self.planned), tostring(self.returns_void), tostring(self.counted_positive),
    tostring(self.single_store), tostring(self.dst_base_present), tostring(self.point_facts_ready),
    tostring(suffix or "no matching plan")
  )
end

function SM.StencilMachineReducePlanInput:reject_reason(suffix)
  return ("reduction stencil is not ready: planned=%s result_reduction=%s returns_reduction=%s counted_positive=%s point_facts_ready=%s (%s)"):format(
    tostring(self.planned), tostring(self.result_reduction), tostring(self.returns_reduction),
    tostring(self.counted_positive), tostring(self.point_facts_ready), tostring(suffix or "no matching plan")
  )
end

function SM.StencilMachineStorePlanInput:plan_store_stencil()
  local plan_ready = self.planned == true
    and self.returns_void == true
    and self.counted_positive == true
    and self.single_store == true
    and self.dst_base_present == true
    and self.point_facts_ready == true
  if not plan_ready then return nil, self:reject_reason() end
  local selected, err = self.selection:select_store_stencil()
  if selected == nil then return nil, self:reject_reason(err) end
  return SM.StencilMachineStorePlan(selected), nil
end

function SM.StencilMachineReducePlanInput:plan_reduce_stencil()
  local plan_ready = self.planned == true
    and self.result_reduction == true
    and self.returns_reduction == true
    and self.counted_positive == true
    and self.point_facts_ready == true
  if not plan_ready then return nil, self:reject_reason() end
  local selected, err = self.selection:select_reduce_stencil()
  if selected == nil then return nil, self:reject_reason(err) end
  return SM.StencilMachineReducePlan(self.reduction, selected), nil
end

----------------------------------------------------------------------
-- StencilMachineSelected → artifact_op/descriptor/args
----------------------------------------------------------------------

function SM.StencilMachineSelected:stencil_artifact_op() return nil end
function SM.StencilMachineSelected:stencil_artifact_descriptor() return self.descriptor end
function SM.StencilMachineSelected:stencil_artifact_args() return self.args end

function SM.StencilMachineSelectFind:stencil_artifact_op() return self.op end
function SM.StencilMachineSelectPartition:stencil_artifact_op() return self.op end
function SM.StencilMachineSelectCount:stencil_artifact_op() return self.op end
