-- Canonical kernel CMat fragment emission for exact scalar counted loops.
require("lalin.schema_v2")
require("lalin.impl.lower_emit_c.code_to_c")
require("lalin.impl.lower_emit_c.materialize")

local Code = require("lalin.schema_v2.code")
local Core = require("lalin.schema_v2.core")
local Value = require("lalin.schema_v2.value")
local Mem = require("lalin.schema_v2.mem")
local Flow = require("lalin.schema_v2.flow")
local Kernel = require("lalin.schema_v2.kernel")
local Stencil = require("lalin.schema_v2.stencil")
local CMat = require("lalin.schema_v2.c_materialize")
local C = require("lalin.schema_v2.c")

local function copy(items)
  local out = {}
  for i = 1, #items do out[i] = items[i] end
  return out
end

local function append(items, item)
  local out = copy(items)
  out[#out + 1] = item
  return out
end

local function prefix(state)
  return state.request.namespace.prefix
end

function CMat.CMatCExternalValueBindingProjection:cmat_fragment_values()
  local entries = {}
  for i = 1, #self.entries do
    local source = self.entries[i]
    entries[i] = CMat.CMatCFragmentValueEntry(
      source.value, C.CBackendAtomLocal(source.c_local.id), source.c_local.ty)
  end
  return CMat.CMatCFragmentValueProjection(entries)
end

function CMat.CMatCExternalValueBindingProjection:cmat_fragment_lookup(value)
  for i = 1, #self.entries do
    if self.entries[i].value == value then
      return CMat.CMatCExternalValueBindingFound(self.entries[i])
    end
  end
  return CMat.CMatCExternalValueBindingMissing(value)
end

function CMat.CMatCFragmentValueProjection:cmat_fragment_lookup(value)
  for i = 1, #self.entries do
    if self.entries[i].value == value then
      return CMat.CMatCFragmentValueFound(self.entries[i])
    end
  end
  return CMat.CMatCFragmentValueMissing(value)
end

function CMat.CMatCFragmentStreamProjection:cmat_fragment_lookup(stream)
  for i = 1, #self.entries do
    if self.entries[i].stream == stream then
      return CMat.CMatCFragmentStreamFound(self.entries[i])
    end
  end
  return CMat.CMatCFragmentStreamMissing(stream)
end

function CMat.CMatCFragmentAccessBindingProjection:cmat_fragment_lookup(access)
  for i = 1, #self.entries do
    if self.entries[i].access == access then
      return CMat.CMatCFragmentAccessBindingFound(self.entries[i])
    end
  end
  return CMat.CMatCFragmentAccessBindingMissing(access)
end

function CMat.CMatCExitBindingProjection:cmat_fragment_lookup(role)
  local found = {}
  for i = 1, #self.entries do
    if self.entries[i].role == role then found[#found + 1] = self.entries[i] end
  end
  if #found == 0 then return CMat.CMatCExitBindingMissing(role) end
  if #found > 1 then return CMat.CMatCExitBindingAmbiguous(role, #found) end
  return CMat.CMatCExitBindingFound(found[1])
end
function Code.CodeFunc:cmat_fragment_block_lookup(block)
  for i = 1, #self.blocks do
    if self.blocks[i].id == block then return CMat.CMatCCodeBlockFound(self.blocks[i]) end
  end
  return CMat.CMatCCodeBlockMissing(block)
end

function Stencil.StencilStreamByKernelValueProjection:cmat_fragment_lookup_source(value)
  for i = 1, #self.entries do
    if self.entries[i].source == value then
      return Stencil.StencilStreamByKernelValueFound(self.entries[i])
    end
  end
  return Stencil.StencilStreamByKernelValueMissing(
    require("lalin.schema_v2.kernel").KernelValueId(value.text))
end

function CMat.CMatCFragmentCFG:cmat_fragment_append_stmt(stmt)
  return CMat.CMatCFragmentCFG(self.completed, CMat.CMatCOpenBlock(
    self.open.label, self.open.params, append(self.open.stmts, stmt)), self.next_block)
end
function CMat.CMatCFragmentCFGSealInput:cmat_fragment_seal()
  local state, cfg = self.state, self.state.cfg
  local block = C.CBackendBlock(
    cfg.open.label, cfg.open.params, cfg.open.stmts, self.term)
  local next_cfg = CMat.CMatCFragmentCFG(
    append(cfg.completed, block),
    CMat.CMatCOpenBlock(self.next_label, self.next_params, {}),
    cfg.next_block + 1)
  return CMat.CMatCFragmentState(
    state.request, state.provenance, state.index, state.ordinal,
    state.values, state.streams, state.window, state.locals,
    state.entry_stmts, next_cfg, state.helpers, state.next_local)
end
function CMat.CMatCFragmentState:cmat_fragment_with_window(window)
  return CMat.CMatCFragmentState(
    self.request, self.provenance, self.index, self.ordinal,
    self.values, self.streams, window, self.locals, self.entry_stmts,
    self.cfg, self.helpers, self.next_local)
end

function CMat.CMatCFragmentState:cmat_fragment_allocate(stem, ty)
  local id = C.CBackendLocalId(prefix(self) .. "_" .. stem .. tostring(self.next_local))
  local c_local = C.CBackendLocal(id, C.CBackendName(id.text), ty)
  return CMat.CMatCFragmentLocalAllocation(CMat.CMatCFragmentState(
    self.request, self.provenance, self.index, self.ordinal,
    self.values, self.streams, self.window, append(self.locals, c_local),
    self.entry_stmts, self.cfg, self.helpers, self.next_local + 1), c_local)
end

function CMat.CMatCFragmentState:cmat_fragment_add_planned_local(c_local)
  return CMat.CMatCFragmentState(
    self.request, self.provenance, self.index, self.ordinal,
    self.values, self.streams, self.window, append(self.locals, c_local),
    self.entry_stmts, self.cfg, self.helpers, self.next_local)
end
function CMat.CMatCAddressPlan:cmat_fragment_install(state)
  local next_state = state
  for i = 1, #self.cursors do
    local cursor = self.cursors[i]
    local starts = {}
    for j = 1, #state.request.values.entries do
      local entry = state.request.values.entries[j]
      if entry.value == cursor.start then starts[#starts + 1] = entry end
    end
    if #starts ~= 1 or starts[1].c_local.ty ~= state.index.ty then
      return CMat.CMatCFragmentStateRejected({
        CMat.CMatCEmissionInvalidKernel(
          "cursor initialization requires one exact start binding")
      })
    end
    next_state = next_state:cmat_fragment_add_planned_local(cursor.cursor_local)
    next_state = next_state:cmat_fragment_add_entry(C.CBackendAssign(
      cursor.cursor_local.id, C.CBackendRPtrOffset(
        C.CBackendAtomLocal(cursor.base.id),
        C.CBackendAtomLocal(starts[1].c_local.id),
        cursor.basis.index_scale_bytes, 0)))
  end
  return CMat.CMatCFragmentStateReady(next_state)
end
function CMat.CMatCAddressPlan:cmat_fragment_cursor_steps(index_ty)
  local stmts = {}
  local zero = C.CBackendAtomLiteral(index_ty, Core.LitInt("0"))
  for i = 1, #self.cursors do
    local cursor = self.cursors[i]
    stmts[#stmts + 1] = C.CBackendAssign(cursor.cursor_local.id,
      C.CBackendRPtrOffset(C.CBackendAtomLocal(cursor.cursor_local.id),
        zero, 1, cursor.step_bytes))
  end
  return CMat.CMatCCursorStatementProjection(stmts)
end

function CMat.CMatCFragmentState:cmat_fragment_add_entry(stmt)
  return CMat.CMatCFragmentState(
    self.request, self.provenance, self.index, self.ordinal,
    self.values, self.streams, self.window, self.locals,
    append(self.entry_stmts, stmt), self.cfg, self.helpers, self.next_local)
end

function CMat.CMatCFragmentState:cmat_fragment_add_body(stmt)
  return CMat.CMatCFragmentState(
    self.request, self.provenance, self.index, self.ordinal,
    self.values, self.streams, self.window, self.locals, self.entry_stmts,
    self.cfg:cmat_fragment_append_stmt(stmt), self.helpers, self.next_local)
end

function CMat.CMatCFragmentState:cmat_fragment_add_helper(spec)
  local id = spec:c_helper_id()
  for i = 1, #self.helpers do
    if self.helpers[i].id == id then
      return CMat.CMatCFragmentHelperAllocation(self, id)
    end
  end
  local use = C.CBackendHelperUse(id, spec)
  return CMat.CMatCFragmentHelperAllocation(CMat.CMatCFragmentState(
    self.request, self.provenance, self.index, self.ordinal,
    self.values, self.streams, self.window, self.locals, self.entry_stmts,
    self.cfg, append(self.helpers, use), self.next_local), id)
end

function CMat.CMatCFragmentState:cmat_fragment_bind_stream(source, stream, atom, ty)
  return CMat.CMatCFragmentState(
    self.request, self.provenance, self.index, self.ordinal,
    CMat.CMatCFragmentValueProjection(append(self.values.entries,
      CMat.CMatCFragmentValueEntry(source, atom, ty))),
    CMat.CMatCFragmentStreamProjection(append(self.streams.entries,
      CMat.CMatCFragmentStreamEntry(stream, source, atom, ty))),
    self.window, self.locals, self.entry_stmts, self.cfg, self.helpers, self.next_local)
end

function CMat.CMatCFragmentState:cmat_fragment_seed_counter()
  local iteration = self.provenance.iteration
  local ty = iteration.index_ty:code_to_c_backend_type()
  return CMat.CMatCFragmentState(
    self.request, self.provenance, self.index, self.ordinal,
    CMat.CMatCFragmentValueProjection(append(self.values.entries,
      CMat.CMatCFragmentValueEntry(
        iteration.counter, C.CBackendAtomLocal(self.index.id), ty))),
    self.streams, self.window, self.locals, self.entry_stmts, self.cfg,
    self.helpers, self.next_local)
end

function Code.CodeConst:cmat_fragment_expr(_state)
  return CMat.CMatCFragmentExprRejected({
    CMat.CMatCEmissionUnsupportedValue(
      Value.ValueExprConst(self), "constant is not materializable in a C fragment")
  })
end

function Code.CodeConstLiteral:cmat_fragment_expr(state)
  local ty = self.ty:code_to_c_backend_type()
  return CMat.CMatCFragmentExprEmitted(
    state, C.CBackendAtomLiteral(ty, self.literal), ty)
end

function Code.CodeConstNull:cmat_fragment_expr(state)
  local ty = self.ty:code_to_c_backend_type()
  return CMat.CMatCFragmentExprEmitted(state, C.CBackendAtomNull(ty), ty)
end

function Code.CodeConstUndef:cmat_fragment_expr(_state)
  return CMat.CMatCFragmentExprRejected({
    CMat.CMatCEmissionUnsupportedValue(
      Value.ValueExprConst(self), "undefined constant cannot enter a C fragment")
  })
end

function Value.ValueExpr:cmat_fragment_expr(_state)
  return CMat.CMatCFragmentExprRejected({
    CMat.CMatCEmissionUnsupportedValue(self, "value expression is outside scalar counted fragment emission")
  })
end

function Value.ValueExprConst:cmat_fragment_expr(state)
  return self.const:cmat_fragment_expr(state)
end

function Value.ValueExprValue:cmat_fragment_expr(state)
  return state.values:cmat_fragment_lookup(self.value):cmat_fragment_expr_value(state, self)
end
function Value.ValueExprCast:cmat_fragment_expr(state)
  return self.value:cmat_fragment_expr(state):cmat_fragment_apply_cast(self)
end
function CMat.CMatCFragmentExprRejected:cmat_fragment_apply_cast(_expr) return self end
function CMat.CMatCFragmentExprEmitted:cmat_fragment_apply_cast(expr)
  local from, to = expr.from:code_to_c_backend_type(), expr.to:code_to_c_backend_type()
  if self.ty ~= from then
    return CMat.CMatCFragmentExprRejected({
      CMat.CMatCEmissionTypeMismatch("cast operand", from, self.ty)
    })
  end
  local allocation = self.state:cmat_fragment_allocate("cast", to)
  local helper = allocation.state:cmat_fragment_add_helper(
    C.CBackendHelperCast(expr.op, from, to))
  local state = helper.state:cmat_fragment_add_body(C.CBackendHelperCall(
    allocation.c_local.id, helper.helper, { self.atom }))
  return CMat.CMatCFragmentExprEmitted(
    state, C.CBackendAtomLocal(allocation.c_local.id), to)
end
function Value.ValueExpr:cmat_fragment_entry_expr(_state)
  return CMat.CMatCFragmentExprRejected({
    CMat.CMatCEmissionUnsupportedValue(
      self, "computed expression cannot be consumed before the loop body")
  })
end
function Value.ValueExprConst:cmat_fragment_entry_expr(state)
  return self:cmat_fragment_expr(state)
end
function Value.ValueExprValue:cmat_fragment_entry_expr(state)
  return state.request.values:cmat_fragment_lookup(self.value)
:cmat_fragment_entry_value(state, self)
end
function Value.ValueExprUnary:cmat_fragment_entry_expr(state)
  return self.value:cmat_fragment_entry_expr(state)
    :cmat_fragment_apply_entry_unary(self)
end
function CMat.CMatCFragmentExprRejected:cmat_fragment_apply_entry_unary(_expr)
  return self
end
function CMat.CMatCFragmentExprEmitted:cmat_fragment_apply_entry_unary(expr)
  local ty = expr.ty:code_to_c_backend_type()
  local allocation = self.state:cmat_fragment_allocate("entry_unary", ty)
  local helper = allocation.state:cmat_fragment_add_helper(
    C.CBackendHelperUnary(expr.op, ty))
  local state = helper.state:cmat_fragment_add_entry(C.CBackendHelperCall(
    allocation.c_local.id, helper.helper, { self.atom }))
  return CMat.CMatCFragmentExprEmitted(
    state, C.CBackendAtomLocal(allocation.c_local.id), ty)
end
function CMat.CMatCExternalValueBindingFound:cmat_fragment_entry_value(state, _expr)
  return CMat.CMatCFragmentExprEmitted(
    state, C.CBackendAtomLocal(self.entry.c_local.id), self.entry.c_local.ty)
end
function CMat.CMatCExternalValueBindingMissing:cmat_fragment_entry_value(_state, expr)
  return CMat.CMatCFragmentExprRejected({
    CMat.CMatCEmissionMissingValue(expr.value)
  })
end

function CMat.CMatCFragmentValueFound:cmat_fragment_expr_value(state, _expr)
  return CMat.CMatCFragmentExprEmitted(state, self.entry.atom, self.entry.ty)
end

function CMat.CMatCFragmentValueMissing:cmat_fragment_expr_value(_state, expr)
  return CMat.CMatCFragmentExprRejected({ CMat.CMatCEmissionMissingValue(expr.value) })
end

function CMat.CMatCIntegerSemanticsMissing:cmat_fragment_integer_selection(_op, _ty)
  return CMat.CMatCBinaryRejected(self.reason)
end
function CMat.CMatCIntegerSemanticsExplicit:cmat_fragment_integer_selection(op, ty)
  return CMat.CMatCBinarySelected(op:cmat_fragment_integer_spec(ty, self))
end
function CMat.CMatCIntegerSemanticsExplicit:cmat_fragment_overflow()
  return self.semantics.overflow:cmat_fragment_overflow()
end
function CMat.CMatCIntegerSemanticsExplicit:cmat_fragment_division()
  return self.semantics.div:cmat_fragment_division()
end
function CMat.CMatCIntegerSemanticsExplicit:cmat_fragment_shift()
  return self.semantics.shift:cmat_fragment_shift()
end
function Code.CodeIntWrap:cmat_fragment_overflow() return C.CBackendIntWrap end
function Code.CodeIntTrapOnOverflow:cmat_fragment_overflow() return C.CBackendIntTrapOnOverflow end
function Code.CodeIntAssumeNoOverflow:cmat_fragment_overflow() return C.CBackendIntAssumeNoOverflow end
function Code.CodeDivTrapOnZero:cmat_fragment_division() return C.CBackendDivTrapOnZero end
function Code.CodeDivTrapOnZeroOrOverflow:cmat_fragment_division() return C.CBackendDivTrapOnZeroOrOverflow end
function Code.CodeShiftMaskCount:cmat_fragment_shift() return C.CBackendShiftMaskCount end
function Code.CodeShiftTrapOutOfRange:cmat_fragment_shift() return C.CBackendShiftTrapOutOfRange end

function Core.BinaryOp:cmat_fragment_integer_spec(ty, semantics)
  return C.CBackendHelperIntBinary(self, ty, semantics:cmat_fragment_overflow())
end
function Core.BinDiv:cmat_fragment_integer_spec(ty, semantics)
  return C.CBackendHelperDivRem(self, ty, semantics:cmat_fragment_division())
end
function Core.BinRem:cmat_fragment_integer_spec(ty, semantics)
  return C.CBackendHelperDivRem(self, ty, semantics:cmat_fragment_division())
end
function Core.BinShl:cmat_fragment_integer_spec(ty, semantics)
  return C.CBackendHelperShift(self, ty, semantics:cmat_fragment_shift())
end
function Core.BinLShr:cmat_fragment_integer_spec(ty, semantics)
  return C.CBackendHelperShift(self, ty, semantics:cmat_fragment_shift())
end
function Core.BinAShr:cmat_fragment_integer_spec(ty, semantics)
  return C.CBackendHelperShift(self, ty, semantics:cmat_fragment_shift())
end

function Code.CodeType:cmat_fragment_binary_spec(op, semantics)
  return CMat.CMatCBinaryRejected("binary result type is outside scalar C fragment emission")
end
function Code.CodeTyInt:cmat_fragment_binary_spec(op, semantics)
  return semantics:cmat_fragment_integer_selection(
    op, self:code_to_c_backend_type())
end
function Code.CodeTyIndex:cmat_fragment_binary_spec(op, semantics)
  return semantics:cmat_fragment_integer_selection(
    op, self:code_to_c_backend_type())
end
function Value.ReductionOp:cmat_fragment_integer_reduction_spec(_ty, _semantics)
  return CMat.CMatCBinaryRejected("integer reduction operation is unsupported")
end
function Value.ReductionAdd:cmat_fragment_integer_reduction_spec(ty, semantics)
  return CMat.CMatCBinarySelected(C.CBackendHelperIntBinary(
    Core.BinAdd, ty, semantics.overflow:cmat_fragment_overflow()))
end
function Value.ReductionMul:cmat_fragment_integer_reduction_spec(ty, semantics)
  return CMat.CMatCBinarySelected(C.CBackendHelperIntBinary(
    Core.BinMul, ty, semantics.overflow:cmat_fragment_overflow()))
end
function Value.ReductionAnd:cmat_fragment_integer_reduction_spec(ty, _semantics)
  return CMat.CMatCBinarySelected(
    C.CBackendHelperIntBinary(Core.BinBitAnd, ty, C.CBackendIntWrap))
end
function Value.ReductionOr:cmat_fragment_integer_reduction_spec(ty, _semantics)
  return CMat.CMatCBinarySelected(
    C.CBackendHelperIntBinary(Core.BinBitOr, ty, C.CBackendIntWrap))
end
function Value.ReductionXor:cmat_fragment_integer_reduction_spec(ty, _semantics)
  return CMat.CMatCBinarySelected(
    C.CBackendHelperIntBinary(Core.BinBitXor, ty, C.CBackendIntWrap))
end
function Value.ReductionMin:cmat_fragment_integer_reduction_spec(ty, _semantics)
  return CMat.CMatCBinarySelected(
    C.CBackendHelperCompareSelect(Core.CmpLe, ty))
end
function Value.ReductionMax:cmat_fragment_integer_reduction_spec(ty, _semantics)
  return CMat.CMatCBinarySelected(
    C.CBackendHelperCompareSelect(Core.CmpGe, ty))
end
function Value.ReductionOp:cmat_fragment_float_reduction_spec(_ty)
  return CMat.CMatCBinaryRejected("floating reduction operation is unsupported")
end
function Value.ReductionAdd:cmat_fragment_float_reduction_spec(ty)
  return CMat.CMatCBinarySelected(C.CBackendHelperFloatBinary(Core.BinAdd, ty))
end
function Value.ReductionMul:cmat_fragment_float_reduction_spec(ty)
  return CMat.CMatCBinarySelected(C.CBackendHelperFloatBinary(Core.BinMul, ty))
end
function Code.CodeType:cmat_fragment_integer_reduction(input)
  return CMat.CMatCBinaryRejected("integer reduction has a non-integer result type")
end
function Code.CodeTyInt:cmat_fragment_integer_reduction(input)
  return input.reduction:cmat_fragment_integer_reduction_spec(
    self:code_to_c_backend_type(), input.semantics)
end
function Code.CodeTyIndex:cmat_fragment_integer_reduction(input)
  return input.reduction:cmat_fragment_integer_reduction_spec(
    self:code_to_c_backend_type(), input.semantics)
end
function Code.CodeType:cmat_fragment_float_reduction(input)
  return CMat.CMatCBinaryRejected("floating reduction has a non-float result type")
end
function Code.CodeTyFloat:cmat_fragment_float_reduction(input)
  return input.mode:cmat_fragment_float_reduction_spec(
    input.reduction, self:code_to_c_backend_type())
end
function Code.CodeFloatStrict:cmat_fragment_float_reduction_spec(reduction, ty)
  return reduction:cmat_fragment_float_reduction_spec(ty)
end
function Code.CodeFloatReassoc:cmat_fragment_float_reduction_spec(_reduction, _ty)
  return CMat.CMatCBinaryRejected("reassociated float reduction is unsupported")
end
function Code.CodeFloatFastMath:cmat_fragment_float_reduction_spec(_reduction, _ty)
  return CMat.CMatCBinaryRejected("fast-math float reduction is unsupported")
end
function Value.ReductionOp:cmat_fragment_inferred_reduction_spec(_ty)
  return CMat.CMatCBinaryRejected("inferred reduction operation is unsupported")
end
function Value.ReductionMin:cmat_fragment_inferred_reduction_spec(ty)
  return CMat.CMatCBinarySelected(
    C.CBackendHelperCompareSelect(Core.CmpLe, ty))
end
function Value.ReductionMax:cmat_fragment_inferred_reduction_spec(ty)
  return CMat.CMatCBinarySelected(
    C.CBackendHelperCompareSelect(Core.CmpGe, ty))
end
function Code.CodeType:cmat_fragment_inferred_reduction(_input)
  return CMat.CMatCBinaryRejected("inferred reduction has an unsupported result type")
end
function Code.CodeTyInt:cmat_fragment_inferred_reduction(input)
  return input.reduction:cmat_fragment_inferred_reduction_spec(
    self:code_to_c_backend_type())
end
function Code.CodeTyIndex:cmat_fragment_inferred_reduction(input)
  return input.reduction:cmat_fragment_inferred_reduction_spec(
    self:code_to_c_backend_type())
end
function Code.CodeTyFloat:cmat_fragment_inferred_reduction(input)
  return input.reduction:cmat_fragment_inferred_reduction_spec(
    self:code_to_c_backend_type())
end
function Stencil.StencilArithmeticInferred:cmat_fragment_reduction_spec(input)
  return input.result_ty:cmat_fragment_inferred_reduction(input)
end
function Stencil.StencilArithmeticInteger:cmat_fragment_reduction_spec(input)
  return input.result_ty:cmat_fragment_integer_reduction(
    CMat.CMatCIntegerReductionInput(input.reduction, self.semantics))
end
function Stencil.StencilArithmeticFloat:cmat_fragment_reduction_spec(input)
  return input.result_ty:cmat_fragment_float_reduction(
    CMat.CMatCFloatReductionInput(input.reduction, self.mode))
end

function Core.BinaryOp:cmat_fragment_float_spec(_ty)
  return CMat.CMatCBinaryRejected("floating binary operation is unsupported")
end
function Core.BinAdd:cmat_fragment_float_spec(ty)
  return CMat.CMatCBinarySelected(C.CBackendHelperFloatBinary(self, ty))
end
function Core.BinSub:cmat_fragment_float_spec(ty)
  return CMat.CMatCBinarySelected(C.CBackendHelperFloatBinary(self, ty))
end
function Core.BinMul:cmat_fragment_float_spec(ty)
  return CMat.CMatCBinarySelected(C.CBackendHelperFloatBinary(self, ty))
end
function Core.BinDiv:cmat_fragment_float_spec(ty)
  return CMat.CMatCBinarySelected(C.CBackendHelperFloatBinary(self, ty))
end
function Code.CodeTyFloat:cmat_fragment_binary_spec(op, _semantics)
  return op:cmat_fragment_float_spec(self:code_to_c_backend_type())
end

function CMat.CMatCFragmentExprRejected:cmat_fragment_binary_right(_continuation)
  return self
end
function CMat.CMatCFragmentExprEmitted:cmat_fragment_binary_right(continuation)
  return continuation.right:cmat_fragment_expr(self.state)
    :cmat_fragment_apply_binary(CMat.CMatCFragmentBinaryApplyInput(self, continuation))
end
function CMat.CMatCFragmentExprRejected:cmat_fragment_apply_binary(_input)
  return self
end
function CMat.CMatCFragmentExprEmitted:cmat_fragment_apply_binary(input)
  local continuation = input.continuation
  return continuation.result_ty:cmat_fragment_binary_spec(
    continuation.op, continuation.semantics)
:cmat_fragment_emit_binary(CMat.CMatCFragmentBinaryEmissionInput(
  input.left, self, continuation.op, continuation.result_ty))
end
function CMat.CMatCBinaryRejected:cmat_fragment_emit_binary(input)
  return CMat.CMatCFragmentExprRejected({
    CMat.CMatCEmissionUnsupportedBinary(
      input.op, input.result_ty, self.reason)
  })
end
function CMat.CMatCBinarySelected:cmat_fragment_emit_binary(input)
  local ty = input.result_ty:code_to_c_backend_type()
  local allocation = input.right.state:cmat_fragment_allocate("expr", ty)
  local helper = allocation.state:cmat_fragment_add_helper(self.spec)
  local state = helper.state:cmat_fragment_add_body(C.CBackendHelperCall(
    allocation.c_local.id, helper.helper, { input.left.atom, input.right.atom }))
  return CMat.CMatCFragmentExprEmitted(
    state, C.CBackendAtomLocal(allocation.c_local.id), ty)
end

function Value.ValueExprBinary:cmat_fragment_integer_semantics()
  if self.sem == nil then
    return CMat.CMatCIntegerSemanticsMissing(
      "integer binary expression has no explicit semantics")
  end
  return CMat.CMatCIntegerSemanticsExplicit(self.sem)
end
function Value.ValueExprAdd:cmat_fragment_integer_semantics()
  if self.sem == nil then
    return CMat.CMatCIntegerSemanticsMissing(
      "integer addition has no explicit semantics")
  end
  return CMat.CMatCIntegerSemanticsExplicit(self.sem)
end
function Value.ValueExprSub:cmat_fragment_integer_semantics()
  if self.sem == nil then
    return CMat.CMatCIntegerSemanticsMissing(
      "integer subtraction has no explicit semantics")
  end
  return CMat.CMatCIntegerSemanticsExplicit(self.sem)
end
function Value.ValueExprMul:cmat_fragment_integer_semantics()
  if self.sem == nil then
    return CMat.CMatCIntegerSemanticsMissing(
      "integer multiplication has no explicit semantics")
  end
  return CMat.CMatCIntegerSemanticsExplicit(self.sem)
end
function Value.ValueExprDiv:cmat_fragment_integer_semantics()
  if self.sem == nil then
    return CMat.CMatCIntegerSemanticsMissing(
      "integer division has no explicit semantics")
  end
  return CMat.CMatCIntegerSemanticsExplicit(self.sem)
end
function Value.ValueExprRem:cmat_fragment_integer_semantics()
  if self.sem == nil then
    return CMat.CMatCIntegerSemanticsMissing(
      "integer remainder has no explicit semantics")
  end
  return CMat.CMatCIntegerSemanticsExplicit(self.sem)
end

function Value.ValueExprBinary:cmat_fragment_expr(state)
  return self.a:cmat_fragment_expr(state):cmat_fragment_binary_right(
    CMat.CMatCFragmentBinaryContinuation(
      self.b, self.op, self.ty, self:cmat_fragment_integer_semantics()))
end
function Value.ValueExprAdd:cmat_fragment_expr(state)
  return self.a:cmat_fragment_expr(state):cmat_fragment_binary_right(
    CMat.CMatCFragmentBinaryContinuation(
      self.b, Core.BinAdd, self.ty, self:cmat_fragment_integer_semantics()))
end
function Value.ValueExprSub:cmat_fragment_expr(state)
  return self.a:cmat_fragment_expr(state):cmat_fragment_binary_right(
    CMat.CMatCFragmentBinaryContinuation(
      self.b, Core.BinSub, self.ty, self:cmat_fragment_integer_semantics()))
end
function Value.ValueExprMul:cmat_fragment_expr(state)
  return self.a:cmat_fragment_expr(state):cmat_fragment_binary_right(
    CMat.CMatCFragmentBinaryContinuation(
      self.b, Core.BinMul, self.ty, self:cmat_fragment_integer_semantics()))
end
function Value.ValueExprDiv:cmat_fragment_expr(state)
  return self.a:cmat_fragment_expr(state):cmat_fragment_binary_right(
    CMat.CMatCFragmentBinaryContinuation(
      self.b, Core.BinDiv, self.ty, self:cmat_fragment_integer_semantics()))
end
function Value.ValueExprRem:cmat_fragment_expr(state)
  return self.a:cmat_fragment_expr(state):cmat_fragment_binary_right(
    CMat.CMatCFragmentBinaryContinuation(
      self.b, Core.BinRem, self.ty, self:cmat_fragment_integer_semantics()))
end

function CMat.CMatCFragmentExprRejected:cmat_fragment_bind_stream(_entry)
  return CMat.CMatCFragmentStateRejected(self.issues)
end
function CMat.CMatCFragmentExprEmitted:cmat_fragment_bind_stream(entry)
  return CMat.CMatCFragmentStateReady(self.state:cmat_fragment_bind_stream(
    entry.source, Stencil.StencilStreamRef(entry.definition.id), self.atom, self.ty))
end

function Stencil.StencilStreamOp:cmat_fragment_emit_stream(_state, entry)
  return CMat.CMatCFragmentStateRejected({
    CMat.CMatCEmissionUnsupportedStream(
      entry.definition, "stream operation is outside scalar counted fragment emission")
  })
end
function Stencil.StencilStreamValueExpr:cmat_fragment_emit_stream(state, entry)
  return self.value:cmat_fragment_expr(state):cmat_fragment_bind_stream(entry)
end
function Stencil.StencilStreamConst:cmat_fragment_emit_stream(state, entry)
  return self.value:cmat_fragment_expr(state):cmat_fragment_bind_stream(entry)
end
function Stencil.StencilStreamAlias:cmat_fragment_emit_stream(state, entry)
  return state.streams:cmat_fragment_lookup(self.source)
    :cmat_fragment_bind_alias(state, entry)
end
function CMat.CMatCFragmentStreamMissing:cmat_fragment_bind_alias(_state, _entry)
  return CMat.CMatCFragmentStateRejected({ CMat.CMatCEmissionMissingStream(self.stream) })
end
function CMat.CMatCFragmentStreamFound:cmat_fragment_bind_alias(state, entry)
  return CMat.CMatCFragmentStateReady(state:cmat_fragment_bind_stream(
    entry.source, Stencil.StencilStreamRef(entry.definition.id),
    self.entry.atom, self.entry.ty))
end

function Core.BinaryOp:cmat_window_binary_spec(ty)
  return C.CBackendHelperIntBinary(self, ty, C.CBackendIntWrap)
end
function Core.BinRem:cmat_window_binary_spec(ty)
  return C.CBackendHelperDivRem(
    self, ty, C.CBackendDivTrapOnZeroOrOverflow)
end
function CMat.CMatCFragmentState:cmat_window_binary(input)
  local allocation = self:cmat_fragment_allocate(input.stem, input.ty)
  local helper = allocation.state:cmat_fragment_add_helper(
    input.op:cmat_window_binary_spec(input.ty))
  local state = helper.state:cmat_fragment_add_body(C.CBackendHelperCall(
    allocation.c_local.id, helper.helper, { input.left, input.right }))
  return CMat.CMatCFragmentExprEmitted(
    state, C.CBackendAtomLocal(allocation.c_local.id), input.ty)
end
function CMat.CMatCFragmentState:cmat_window_compare(input)
  local allocation = self:cmat_fragment_allocate(input.stem, C.CBackendBool8)
  local state = allocation.state:cmat_fragment_add_body(C.CBackendAssign(
    allocation.c_local.id, C.CBackendRCompare(
      input.cmp, input.operand_ty, input.left, input.right)))
  return CMat.CMatCFragmentExprEmitted(
    state, C.CBackendAtomLocal(allocation.c_local.id), C.CBackendBool8)
end
function CMat.CMatCFragmentState:cmat_window_select(input)
  local allocation = self:cmat_fragment_allocate(input.stem, input.ty)
  local state = allocation.state:cmat_fragment_add_body(C.CBackendAssign(
    allocation.c_local.id, C.CBackendRSelect(
      input.ty, input.condition, input.then_value, input.else_value)))
  return CMat.CMatCFragmentExprEmitted(
    state, C.CBackendAtomLocal(allocation.c_local.id), input.ty)
end
function Stencil.StencilStreamWindowAccess:cmat_window_offset(entry)
  local distance = Stencil.StencilElementDistance(0)
  local found = 0
  for i = 1, #self.offsets do
    if self.offsets[i].axis.index == 1 then
      distance = self.offsets[i].distance
      found = found + 1
    else
      return CMat.CMatCWindowOffsetRejected(
        CMat.CMatCEmissionInvalidWindow(
          entry.definition, "window access references a non-primary axis"))
    end
  end
  if found > 1 then
    return CMat.CMatCWindowOffsetRejected(
      CMat.CMatCEmissionInvalidWindow(
        entry.definition, "window access repeats the primary axis"))
  end
  return CMat.CMatCWindowOffsetResolved(distance)
end
function CMat.CMatCWindowOffsetRejected:cmat_emit_window_load(_request)
  return CMat.CMatCFragmentStateRejected({ self.issue })
end
function CMat.CMatCWindowOffsetResolved:cmat_emit_window_load(request)
  return request.state.window:cmat_emit_window_load(CMat.CMatCWindowLoadInput(
    request.state, request.stream, request.access, self.distance))
end
function CMat.CMatCFragmentNoWindow:cmat_emit_window_load(input)
  return CMat.CMatCFragmentStateRejected({
    CMat.CMatCEmissionInvalidWindow(
      input.stream.definition, "window stream lacks a window producer")
  })
end

local function window_request_state(request, state)
  return CMat.CMatCWindowLoadInput(
    state, request.stream, request.access, request.distance)
end
local function window_positive_position(request, magnitude)
  local context, state = request.state.window, request.state
  local ty = context.index_ty
  local amount = C.CBackendAtomLiteral(ty, Core.LitInt(tostring(magnitude)))
  local target = state:cmat_window_binary(CMat.CMatCWindowBinaryInput(
    "window_target", Core.BinAdd, context.index, amount, ty))
  local inside = target.state:cmat_window_compare(CMat.CMatCWindowCompareInput(
    "window_inside", Core.CmpLe, target.atom, context.upper, ty))
  return CMat.CMatCWindowPosition(inside.state, inside.atom, target.atom)
end
local function window_negative_position(request, magnitude)
  local context, state = request.state.window, request.state
  local ty = context.index_ty
  local amount = C.CBackendAtomLiteral(ty, Core.LitInt(tostring(magnitude)))
  local target = state:cmat_window_binary(CMat.CMatCWindowBinaryInput(
    "window_target", Core.BinSub, context.index, amount, ty))
  local inside = target.state:cmat_window_compare(CMat.CMatCWindowCompareInput(
    "window_inside", Core.CmpGe, target.atom, context.lower, ty))
  return CMat.CMatCWindowPosition(inside.state, inside.atom, target.atom)
end
local function window_position(request)
  local distance = request.distance.elements
  if distance >= 0 then return window_positive_position(request, distance) end
  return window_negative_position(request, -distance)
end
local function window_actual(position, request)
  return CMat.CMatCWindowResolvedLoadInput(
    window_request_state(request, position.state), position.target_index)
end

local function validate_window_offset(request, limit)
  local distance = request.distance.elements
  if distance ~= distance or distance == math.huge or distance == -math.huge
      or distance ~= math.floor(distance) or math.abs(distance) > limit then
    return CMat.CMatCWindowOffsetInvalid(
      CMat.CMatCEmissionInvalidWindow(request.stream.definition,
        "window distance is not a finite representable element integer"))
  end
  return CMat.CMatCWindowOffsetValid(request)
end
function C.CBackendType:cmat_validate_window_offset(request)
  return CMat.CMatCWindowOffsetInvalid(
    CMat.CMatCEmissionInvalidWindow(request.stream.definition,
      "window index type cannot represent element distances"))
end
function C.CBackendScalar:cmat_validate_window_offset(request)
  return self.scalar:cmat_validate_window_offset(request)
end
function Core.Scalar:cmat_validate_window_offset(request)
  return CMat.CMatCWindowOffsetInvalid(
    CMat.CMatCEmissionInvalidWindow(request.stream.definition,
      "window index scalar cannot represent signed element distances"))
end
function Core.ScalarI8:cmat_validate_window_offset(request)
  return validate_window_offset(request, 127)
end
function Core.ScalarI16:cmat_validate_window_offset(request)
  return validate_window_offset(request, 32767)
end
function Core.ScalarI32:cmat_validate_window_offset(request)
  return validate_window_offset(request, 2147483647)
end
function Core.ScalarI64:cmat_validate_window_offset(request)
  return validate_window_offset(request, 9007199254740991)
end
function CMat.CMatCWindowOffsetInvalid:cmat_emit_validated_window_load(_window)
  return CMat.CMatCWindowLoadRejected({ self.issue })
end
function CMat.CMatCFragmentWindow1D:cmat_emit_window_load(input)
  return self.index_ty:cmat_validate_window_offset(input)
:cmat_emit_validated_window_load(self)
:cmat_bind_window_stream(input.stream)
end
function CMat.CMatCWindowOffsetValid:cmat_emit_validated_window_load(window)
  local input = self.request
  local distance = input.distance.elements
  if distance < -window.window.extent.before.elements
      or distance > window.window.extent.after.elements then
    return CMat.CMatCWindowLoadRejected({
      CMat.CMatCEmissionInvalidWindow(input.stream.definition,
        "window distance exceeds the declared element extent")
    })
  end
  return window.window.boundary:cmat_emit_window_boundary(input)
end
function Stencil.StencilWindowBoundaryReject:cmat_emit_window_boundary(request)
  if request.distance.elements ~= 0 then
    return CMat.CMatCWindowLoadRejected({
      CMat.CMatCEmissionInvalidWindow(request.stream.definition,
        "reject boundary permits only centered window access")
    })
  end
  return CMat.CMatCWindowResolvedLoadInput(
    request, request.state.window.index)
:cmat_emit_resolved_window_load()
end
function Stencil.StencilWindowBoundaryClamp:cmat_emit_window_boundary(request)
  local position = window_position(request)
  local context, ty = position.state.window, position.state.window.index_ty
  local edge = request.distance.elements >= 0 and context.upper or context.lower
  local selected = position.state:cmat_window_select(CMat.CMatCWindowSelectInput(
    "window_clamped", position.condition, position.target_index, edge, ty))
  return window_actual(
    CMat.CMatCWindowPosition(selected.state, position.condition, selected.atom),
    request):cmat_emit_resolved_window_load()
end

local function window_positive_wrapped_position(request, magnitude)
  local context, ty = request.state.window, request.state.window.index_ty
  local one = C.CBackendAtomLiteral(ty, Core.LitInt("1"))
  local amount = C.CBackendAtomLiteral(ty, Core.LitInt(tostring(magnitude)))
  local remainder = request.state:cmat_window_binary(CMat.CMatCWindowBinaryInput(
    "window_distance_rem", Core.BinRem, amount, context.extent, ty))
  local remaining = remainder.state:cmat_window_binary(CMat.CMatCWindowBinaryInput(
    "window_remaining", Core.BinSub, context.upper,
    context.index, ty))
  local direct_case = remaining.state:cmat_window_compare(CMat.CMatCWindowCompareInput(
    "window_direct", Core.CmpLe, remainder.atom, remaining.atom, ty))
  local direct = direct_case.state:cmat_window_binary(CMat.CMatCWindowBinaryInput(
    "window_direct_target", Core.BinAdd,
    context.index, remainder.atom, ty))
  local delta = direct.state:cmat_window_binary(CMat.CMatCWindowBinaryInput(
    "window_wrap_delta", Core.BinSub, remainder.atom, remaining.atom, ty))
  local past = delta.state:cmat_window_binary(CMat.CMatCWindowBinaryInput(
    "window_wrap_past", Core.BinSub, delta.atom, one, ty))
  local wrapped = past.state:cmat_window_binary(CMat.CMatCWindowBinaryInput(
    "window_wrapped_target", Core.BinAdd, context.lower, past.atom, ty))
  local target = wrapped.state:cmat_window_select(CMat.CMatCWindowSelectInput(
    "window_target", direct_case.atom, direct.atom, wrapped.atom, ty))
  return CMat.CMatCWindowPosition(target.state, direct_case.atom, target.atom)
end
local function window_negative_wrapped_position(request, magnitude)
  local context, ty = request.state.window, request.state.window.index_ty
  local one = C.CBackendAtomLiteral(ty, Core.LitInt("1"))
  local amount = C.CBackendAtomLiteral(ty, Core.LitInt(tostring(magnitude)))
  local remainder = request.state:cmat_window_binary(CMat.CMatCWindowBinaryInput(
    "window_distance_rem", Core.BinRem, amount, context.extent, ty))
  local available = remainder.state:cmat_window_binary(CMat.CMatCWindowBinaryInput(
    "window_available", Core.BinSub,
    context.index, context.lower, ty))
  local direct_case = available.state:cmat_window_compare(CMat.CMatCWindowCompareInput(
    "window_direct", Core.CmpLe, remainder.atom, available.atom, ty))
  local direct = direct_case.state:cmat_window_binary(CMat.CMatCWindowBinaryInput(
    "window_direct_target", Core.BinSub,
    context.index, remainder.atom, ty))
  local delta = direct.state:cmat_window_binary(CMat.CMatCWindowBinaryInput(
    "window_wrap_delta", Core.BinSub, remainder.atom, available.atom, ty))
  local past = delta.state:cmat_window_binary(CMat.CMatCWindowBinaryInput(
    "window_wrap_past", Core.BinSub, delta.atom, one, ty))
  local wrapped = past.state:cmat_window_binary(CMat.CMatCWindowBinaryInput(
    "window_wrapped_target", Core.BinSub, context.upper, past.atom, ty))
  local target = wrapped.state:cmat_window_select(CMat.CMatCWindowSelectInput(
    "window_target", direct_case.atom, direct.atom, wrapped.atom, ty))
  return CMat.CMatCWindowPosition(target.state, direct_case.atom, target.atom)
end
function Stencil.StencilWindowBoundaryWrap:cmat_emit_window_boundary(request)
  local distance = request.distance.elements
  local position
  if distance >= 0 then
    position = window_positive_wrapped_position(request, distance)
  else
    position = window_negative_wrapped_position(request, -distance)
  end
  return window_actual(position, request):cmat_emit_resolved_window_load()
end
function Stencil.StencilWindowBoundaryZero:cmat_emit_window_boundary(request)
  local position = window_position(request)
  local actual = window_actual(position, request)
  return CMat.CMatCWindowGuardedLoadInput(
    actual.request, actual.index, position.condition)
:cmat_emit_guarded_window_load()
end
function Stencil.StencilStreamWindowAccess:cmat_fragment_emit_stream(state, entry)
  return self:cmat_window_offset(entry):cmat_emit_window_load(
    CMat.CMatCWindowLoadRequest(state, entry, self.access))
end
function CMat.CMatCWindowLoadRejected:cmat_bind_window_stream(_stream)
  return CMat.CMatCFragmentStateRejected(self.issues)
end
function CMat.CMatCWindowLoadEmitted:cmat_bind_window_stream(stream)
  return CMat.CMatCFragmentStateReady(self.state:cmat_fragment_bind_stream(
    stream.source, Stencil.StencilStreamRef(stream.definition.id),
    self.atom, self.ty))
end
function CMat.CMatCFragmentAccessBindingMissing:cmat_resolved_window_load(_input)
  return CMat.CMatCWindowLoadRejected({
    CMat.CMatCEmissionMissingAccess(self.access)
  })
end
function CMat.CMatCFragmentPlaceRejected:cmat_finish_window_load(_input)
  return CMat.CMatCWindowLoadRejected(self.issues)
end
function CMat.CMatCFragmentPlaceEmitted:cmat_finish_window_load(input)
  local ty = input.request.stream.definition.ty:code_to_c_backend_type()
  local allocation = self.state:cmat_fragment_allocate("window_load", ty)
  local state = allocation.state:cmat_fragment_add_body(
    C.CBackendPlaceLoad(allocation.c_local.id, self.place))
  return CMat.CMatCWindowLoadEmitted(
    state, C.CBackendAtomLocal(allocation.c_local.id), ty)
end
function CMat.CMatCFragmentAccessBindingFound:cmat_resolved_window_load(input)
  local ty = input.request.stream.definition.ty:code_to_c_backend_type()
  return self:cmat_fragment_access_place(CMat.CMatCFragmentAccessPlaceInput(
    input.request.state, CMat.CMatWindowMemoryUse(
      Stencil.StencilStreamRef(input.request.stream.definition.id), 1),
    input.index, input.request.state.window.index_ty, ty))
:cmat_finish_window_load(input)
end
function CMat.CMatCWindowResolvedLoadInput:cmat_emit_resolved_window_load()
  return self.request.state.request.accesses:cmat_fragment_lookup(self.request.access)
:cmat_resolved_window_load(self)
end
function C.CBackendType:cmat_window_zero_atom()
  return CMat.CMatCAtomRejected(CMat.CMatCEmissionInvalidKernel(
    "window zero boundary cannot represent this element type"))
end
function C.CBackendScalar:cmat_window_zero_atom()
  return self.scalar:cmat_window_zero_scalar(self)
end
function Core.Scalar:cmat_window_zero_scalar(_ty)
  return CMat.CMatCAtomRejected(CMat.CMatCEmissionInvalidKernel(
    "window zero boundary requires a numeric scalar"))
end
function Core.ScalarBool:cmat_window_zero_scalar(ty)
  return CMat.CMatCAtomEmitted(C.CBackendAtomLiteral(ty, Core.LitBool(false)), ty)
end
function Core.ScalarI8:cmat_window_zero_scalar(ty) return CMat.CMatCAtomEmitted(C.CBackendAtomLiteral(ty, Core.LitInt("0")), ty) end
function Core.ScalarI16:cmat_window_zero_scalar(ty) return CMat.CMatCAtomEmitted(C.CBackendAtomLiteral(ty, Core.LitInt("0")), ty) end
function Core.ScalarI32:cmat_window_zero_scalar(ty) return CMat.CMatCAtomEmitted(C.CBackendAtomLiteral(ty, Core.LitInt("0")), ty) end
function Core.ScalarI64:cmat_window_zero_scalar(ty) return CMat.CMatCAtomEmitted(C.CBackendAtomLiteral(ty, Core.LitInt("0")), ty) end
function Core.ScalarU8:cmat_window_zero_scalar(ty) return CMat.CMatCAtomEmitted(C.CBackendAtomLiteral(ty, Core.LitInt("0")), ty) end
function Core.ScalarU16:cmat_window_zero_scalar(ty) return CMat.CMatCAtomEmitted(C.CBackendAtomLiteral(ty, Core.LitInt("0")), ty) end
function Core.ScalarU32:cmat_window_zero_scalar(ty) return CMat.CMatCAtomEmitted(C.CBackendAtomLiteral(ty, Core.LitInt("0")), ty) end
function Core.ScalarU64:cmat_window_zero_scalar(ty) return CMat.CMatCAtomEmitted(C.CBackendAtomLiteral(ty, Core.LitInt("0")), ty) end
function Core.ScalarIndex:cmat_window_zero_scalar(ty) return CMat.CMatCAtomEmitted(C.CBackendAtomLiteral(ty, Core.LitInt("0")), ty) end
function Core.ScalarF32:cmat_window_zero_scalar(ty) return CMat.CMatCAtomEmitted(C.CBackendAtomLiteral(ty, Core.LitFloat("0.0")), ty) end
function Core.ScalarF64:cmat_window_zero_scalar(ty) return CMat.CMatCAtomEmitted(C.CBackendAtomLiteral(ty, Core.LitFloat("0.0")), ty) end
function CMat.CMatCFragmentAccessBindingMissing:cmat_guarded_window_load(_input)
  return CMat.CMatCWindowLoadRejected({
    CMat.CMatCEmissionMissingAccess(self.access)
  })
end
function CMat.CMatCFragmentPlaceRejected:cmat_finish_guarded_window_load(_input)
  return CMat.CMatCWindowLoadRejected(self.issues)
end
function CMat.CMatCAtomRejected:cmat_finish_window_zero(_input)
  return CMat.CMatCWindowLoadRejected({ self.issue })
end
function CMat.CMatCAtomEmitted:cmat_finish_window_zero(input)
  local state = input.guarded.request.state
  state = state:cmat_fragment_add_body(
    C.CBackendAssign(input.result.id, C.CBackendRAtom(self.atom)))
  state = CMat.CMatCFragmentCFGSealInput(
    state, C.CBackendGoto(input.join_label, {}), input.join_label, {})
:cmat_fragment_seal()
  return CMat.CMatCWindowLoadEmitted(
    state, C.CBackendAtomLocal(input.result.id), input.result.ty)
end
function CMat.CMatCFragmentPlaceEmitted:cmat_finish_guarded_window_load(input)
  local state = self.state:cmat_fragment_add_body(
    C.CBackendPlaceLoad(input.result.id, self.place))
  state = CMat.CMatCFragmentCFGSealInput(
    state, C.CBackendGoto(input.join_label, {}), input.zero_label, {})
:cmat_fragment_seal()
  local exact = CMat.CMatCWindowGuardedPlaceInput(
    CMat.CMatCWindowGuardedLoadInput(
      CMat.CMatCWindowLoadInput(
        state, input.guarded.request.stream, input.guarded.request.access,
        input.guarded.request.distance),
      input.guarded.index, input.guarded.condition),
    input.result, input.zero_label, input.join_label)
  return input.result.ty:cmat_window_zero_atom():cmat_finish_window_zero(exact)
end
function CMat.CMatCFragmentAccessBindingFound:cmat_guarded_window_load(input)
  local ty = input.request.stream.definition.ty:code_to_c_backend_type()
  local allocation = input.request.state:cmat_fragment_allocate("window_load", ty)
  local state = allocation.state
  local ordinal = state.cfg.next_block
  local load_label = C.CBackendLabel(prefix(state) .. "_window_load_" .. ordinal)
  local zero_label = C.CBackendLabel(prefix(state) .. "_window_zero_" .. ordinal)
  local join_label = C.CBackendLabel(prefix(state) .. "_window_join_" .. ordinal)
  state = CMat.CMatCFragmentCFGSealInput(
    state, C.CBackendIfGoto(input.condition, load_label, {}, zero_label, {}),
    load_label, {}):cmat_fragment_seal()
  local request = CMat.CMatCWindowLoadInput(
    state, input.request.stream, input.request.access, input.request.distance)
  local guarded = CMat.CMatCWindowGuardedLoadInput(
    request, input.index, input.condition)
  return self:cmat_fragment_access_place(CMat.CMatCFragmentAccessPlaceInput(
    state, CMat.CMatWindowMemoryUse(
      Stencil.StencilStreamRef(input.request.stream.definition.id), 1),
    input.index, state.index.ty, ty))
:cmat_finish_guarded_window_load(CMat.CMatCWindowGuardedPlaceInput(
  guarded, allocation.c_local, zero_label, join_label))
end
function CMat.CMatCWindowGuardedLoadInput:cmat_emit_guarded_window_load()
  return self.request.state.request.accesses:cmat_fragment_lookup(self.request.access)
:cmat_guarded_window_load(self)
end
function Stencil.StencilIndexProducer:cmat_fragment_index(state, _def)
  return CMat.CMatCFragmentExprEmitted(
    state, C.CBackendAtomLocal(state.index.id), state.index.ty)
end
function Stencil.StencilIndexExplicit:cmat_fragment_index(state, def)
  return self.index:cmat_fragment_index_expr(state, def)
end
function Stencil.StencilIndexAxis:cmat_fragment_index_expr(state, def)
  if self.axis.index ~= 1 then
    return CMat.CMatCFragmentExprRejected({
      CMat.CMatCEmissionUnsupportedStream(
        def, "scalar counted fragment requires axis one")
    })
  end
  return CMat.CMatCFragmentExprEmitted(
    state, C.CBackendAtomLocal(state.index.id), state.index.ty)
end
function Stencil.StencilIndexStream:cmat_fragment_index_expr(state, _def)
  return state.streams:cmat_fragment_lookup(self.stream)
:cmat_fragment_index_stream(state)
end
function Stencil.StencilIndexPoint:cmat_fragment_index_expr(state, _def)
  return self.expr:cmat_fragment_expr(state)
end
function CMat.CMatCFragmentStreamMissing:cmat_fragment_index_stream(_state)
  return CMat.CMatCFragmentExprRejected({ CMat.CMatCEmissionMissingStream(self.stream) })
end
function CMat.CMatCFragmentStreamFound:cmat_fragment_index_stream(state)
  return CMat.CMatCFragmentExprEmitted(state, self.entry.atom, self.entry.ty)
end
function Stencil.StencilStreamAccess:cmat_fragment_emit_stream(state, entry)
  local index = self.index:cmat_fragment_index(state, entry.definition)
  return index:cmat_fragment_load_request(
    CMat.CMatCFragmentLoadRequest(entry, self.access))
end
function CMat.CMatCFragmentExprRejected:cmat_fragment_load_request(_request)
  return CMat.CMatCFragmentStateRejected(self.issues)
end
function CMat.CMatCFragmentExprEmitted:cmat_fragment_load_request(request)
  return self:cmat_fragment_load_access(
    CMat.CMatCFragmentLoadInput(self, request.stream, request.access))
end
function CMat.CMatCFragmentExprRejected:cmat_fragment_load_access(_input)
  return CMat.CMatCFragmentStateRejected(self.issues)
end
function CMat.CMatCFragmentExprEmitted:cmat_fragment_load_access(input)
  return self.state.request.accesses:cmat_fragment_lookup(input.access)
:cmat_fragment_load_bound(input)
end
function CMat.CMatCFragmentAccessBindingMissing:cmat_fragment_load_bound(_input)
  return CMat.CMatCFragmentStateRejected({ CMat.CMatCEmissionMissingAccess(self.access) })
end
function Mem.MemAlignUnknown:cmat_fragment_place(input)
  return C.CBackendPlacePtrIndex(input.base, input.index, input.ty, input.stride, nil)
end
function Mem.MemAlignKnown:cmat_fragment_place(input)
  return C.CBackendPlacePtrIndex(input.base, input.index, input.ty, input.stride, self.bytes)
end
function Mem.MemAlignAtLeast:cmat_fragment_place(input)
  return C.CBackendPlacePtrIndex(input.base, input.index, input.ty, input.stride, self.bytes)
end
function Mem.MemAlignAssumed:cmat_fragment_place(input)
  return C.CBackendPlacePtrIndex(input.base, input.index, input.ty, input.stride, self.bytes)
end
function Mem.MemAlignUnknown:cmat_fragment_deref(addr, ty)
  return C.CBackendPlaceDeref(addr, ty, nil)
end
function Mem.MemAlignKnown:cmat_fragment_deref(addr, ty)
  return C.CBackendPlaceDeref(addr, ty, self.bytes)
end
function Mem.MemAlignAtLeast:cmat_fragment_deref(addr, ty)
  return C.CBackendPlaceDeref(addr, ty, self.bytes)
end
function Mem.MemAlignAssumed:cmat_fragment_deref(addr, ty)
  return C.CBackendPlaceDeref(addr, ty, self.bytes)
end

local function cmat_fragment_offset_place(state, binding, base, index, scale, offset, ty)
  if offset == 0 and scale == binding.elem_size then
    local place = binding.alignment:cmat_fragment_place(
      CMat.CMatCFragmentPlaceInput(base, index, ty, binding.elem_size))
    return CMat.CMatCFragmentPlaceEmitted(state, place)
  end
  local allocation = state:cmat_fragment_allocate(
    "address", C.CBackendDataPtr(ty))
  state = allocation.state:cmat_fragment_add_body(C.CBackendAssign(
    allocation.c_local.id, C.CBackendRPtrOffset(base, index, scale, offset)))
  return CMat.CMatCFragmentPlaceEmitted(state,
    binding.alignment:cmat_fragment_deref(
      C.CBackendAtomLocal(allocation.c_local.id), ty))
end

function CMat.CMatCAddressingMissing:cmat_fragment_emit_place(_input, _binding)
  return CMat.CMatCFragmentPlaceRejected({
    CMat.CMatCEmissionInvalidKernel("C address plan is missing a memory use") })
end
function CMat.CMatCAddressingAmbiguous:cmat_fragment_emit_place(_input, _binding)
  return CMat.CMatCFragmentPlaceRejected({
    CMat.CMatCEmissionInvalidKernel("C address plan has an ambiguous memory use") })
end
function CMat.CMatCAddressingFound:cmat_fragment_emit_place(input, binding)
  return self.entry.addressing:cmat_fragment_emit_place(input, binding)
end
function CMat.CMatCAbsoluteAddressing:cmat_fragment_emit_place(input, binding)
  if self.index_scale_bytes ~= binding.stride then
    return CMat.CMatCFragmentPlaceRejected({
      CMat.CMatCEmissionInvalidKernel("absolute address scale disagrees with binding") })
  end
  return cmat_fragment_offset_place(input.state, binding,
    C.CBackendAtomLocal(self.base.id), input.index,
    self.index_scale_bytes, self.const_offset_bytes, input.ty)
end
function CMat.CMatCDynamicWindowAddressing:cmat_fragment_emit_place(input, binding)
  if self.index_scale_bytes ~= binding.stride then
    return CMat.CMatCFragmentPlaceRejected({
      CMat.CMatCEmissionInvalidKernel("window address scale disagrees with binding") })
  end
  return cmat_fragment_offset_place(input.state, binding,
    C.CBackendAtomLocal(self.base.id), input.index,
    self.index_scale_bytes, self.const_offset_bytes, input.ty)
end
function CMat.CMatCCursorAddressing:cmat_fragment_emit_place(input, binding)
  return input.state.request.address_plan:cursor(self.cursor)
    :cmat_fragment_cursor_place(input, binding, self.displacement_bytes)
end
function CMat.CMatCCursorMissing:cmat_fragment_cursor_place(_input, _binding, _displacement)
  return CMat.CMatCFragmentPlaceRejected({
    CMat.CMatCEmissionInvalidKernel("C address plan cursor is missing") })
end
function CMat.CMatCCursorAmbiguous:cmat_fragment_cursor_place(_input, _binding, _displacement)
  return CMat.CMatCFragmentPlaceRejected({
    CMat.CMatCEmissionInvalidKernel("C address plan cursor is ambiguous") })
end
function CMat.CMatCCursorFound:cmat_fragment_cursor_place(input, binding, displacement)
  if self.cursor.basis.index_scale_bytes ~= binding.stride then
    return CMat.CMatCFragmentPlaceRejected({
      CMat.CMatCEmissionInvalidKernel("cursor address scale disagrees with binding") })
  end
  if displacement == 0 then
    return CMat.CMatCFragmentPlaceEmitted(input.state,
      binding.alignment:cmat_fragment_deref(
        C.CBackendAtomLocal(self.cursor.cursor_local.id), input.ty))
  end
  local zero = C.CBackendAtomLiteral(input.index_ty, Core.LitInt("0"))
  return cmat_fragment_offset_place(input.state, binding,
    C.CBackendAtomLocal(self.cursor.cursor_local.id), zero, 1, displacement, input.ty)
end
function CMat.CMatCFragmentAccessBindingFound:cmat_fragment_access_place(input)
  return input.state.request.address_plan:lookup(input.use)
    :cmat_fragment_emit_place(input, self.entry)
end
function CMat.CMatCFragmentPlaceRejected:cmat_fragment_finish_load(_stream)
  return CMat.CMatCFragmentStateRejected(self.issues)
end
function CMat.CMatCFragmentPlaceEmitted:cmat_fragment_finish_load(stream)
  local ty = stream.definition.ty:code_to_c_backend_type()
  local allocation = self.state:cmat_fragment_allocate("load", ty)
  local state = allocation.state:cmat_fragment_add_body(
    C.CBackendPlaceLoad(allocation.c_local.id, self.place))
  return CMat.CMatCFragmentStateReady(state:cmat_fragment_bind_stream(
    stream.source, Stencil.StencilStreamRef(stream.definition.id),
    C.CBackendAtomLocal(allocation.c_local.id), ty))
end
function CMat.CMatCFragmentAccessBindingFound:cmat_fragment_load_bound(input)
  local ty = input.stream.definition.ty:code_to_c_backend_type()
  return self:cmat_fragment_access_place(CMat.CMatCFragmentAccessPlaceInput(
    input.index.state, CMat.CMatStreamMemoryUse(
      Stencil.StencilStreamRef(input.stream.definition.id)),
    input.index.atom, input.index.ty, ty))
:cmat_fragment_finish_load(input.stream)
end

function CMat.CMatCFragmentStateRejected:cmat_fragment_apply_stream(_entry) return self end
function CMat.CMatCFragmentStateReady:cmat_fragment_apply_stream(entry)
  return entry.definition.op:cmat_fragment_emit_stream(self.state, entry)
end
function CMat.CMatCFragmentStateRejected:cmat_fragment_apply_sink(_sink)
  return CMat.CMatCFragmentSinkRejected(self.issues)
end
function CMat.CMatCFragmentStateReady:cmat_fragment_apply_sink(sink)
  return sink.op:cmat_fragment_emit_sink(self.state, sink)
end
function Stencil.StencilPredicate:cmat_fragment_predicate(input)
  return CMat.CMatCFragmentPredicateRejected({
    CMat.CMatCEmissionUnsupportedPredicate(
      self, "predicate is outside scalar control fragment emission")
  })
end
function CMat.CMatCAtomRejected:cmat_fragment_nonzero_predicate(_input)
  return CMat.CMatCFragmentPredicateRejected({ self.issue })
end
function CMat.CMatCAtomEmitted:cmat_fragment_nonzero_predicate(input)
  local emitted = input.state:cmat_window_compare(CMat.CMatCWindowCompareInput(
    "predicate", Core.CmpNe, input.source, self.atom, input.source_ty))
  return CMat.CMatCFragmentPredicateEmitted(emitted.state, emitted.atom)
end
function Stencil.StencilPredNonZero:cmat_fragment_predicate(input)
  return input.source_ty:cmat_window_zero_atom()
:cmat_fragment_nonzero_predicate(input)
end
function CMat.CMatCFragmentExprRejected:cmat_fragment_compare_predicate(_input)
  return CMat.CMatCFragmentPredicateRejected(self.issues)
end
function CMat.CMatCFragmentExprEmitted:cmat_fragment_compare_predicate(input)
  if self.ty ~= input.source.source_ty then
    return CMat.CMatCFragmentPredicateRejected({
      CMat.CMatCEmissionTypeMismatch(
        "predicate constant", input.source.source_ty, self.ty)
    })
  end
  local emitted = self.state:cmat_window_compare(CMat.CMatCWindowCompareInput(
    "predicate", input.cmp, input.source.source, self.atom, self.ty))
  return CMat.CMatCFragmentPredicateEmitted(emitted.state, emitted.atom)
end
function Stencil.StencilPredCompareConst:cmat_fragment_predicate(input)
  return self.value:cmat_fragment_expr(input.state)
:cmat_fragment_compare_predicate(
  CMat.CMatCFragmentPredicateCompareInput(input, self.cmp))
end
function CMat.CMatCFragmentStreamMissing:cmat_control_predicate(_input)
  return CMat.CMatCFragmentSinkRejected({
    CMat.CMatCEmissionMissingStream(self.stream)
  })
end
function CMat.CMatCFragmentStreamFound:cmat_control_predicate(input)
  return input.pred:cmat_fragment_predicate(CMat.CMatCFragmentPredicateInput(
    input.control.state, self.entry.atom, self.entry.ty))
:cmat_finish_control_predicate(CMat.CMatCControlPredicateInput(
  input.control, self, input.pred))
end
function CMat.CMatCFragmentPredicateRejected:cmat_finish_control_predicate(_input)
  return CMat.CMatCFragmentSinkRejected(self.issues)
end
function CMat.CMatCFragmentPredicateEmitted:cmat_finish_control_predicate(input)
  return self.state.provenance.result:cmat_prepare_control_exits(
    CMat.CMatCControlExitInput(
      self.state, input.control.sink, self.condition,
      self.state.provenance.result))
end
function Stencil.StencilSinkOp:cmat_fragment_emit_sink(_state, sink)
  return CMat.CMatCFragmentSinkRejected({
    CMat.CMatCEmissionUnsupportedSink(
      sink, "sink operation is outside scalar counted fragment emission")
  })
end
function CMat.CMatCFragmentStreamMissing:cmat_control_all_compare_left(_input)
  return CMat.CMatCFragmentSinkRejected({
    CMat.CMatCEmissionMissingStream(self.stream)
  })
end
function CMat.CMatCFragmentStreamFound:cmat_control_all_compare_left(input)
  return input.control.state.streams:cmat_fragment_lookup(input.operation.right)
:cmat_control_all_compare_right(CMat.CMatCControlAllCompareInput(
  input.control, input.operation, self))
end
function CMat.CMatCFragmentStreamMissing:cmat_control_all_compare_right(_input)
  return CMat.CMatCFragmentSinkRejected({
    CMat.CMatCEmissionMissingStream(self.stream)
  })
end
function CMat.CMatCFragmentStreamFound:cmat_control_all_compare_right(input)
  if input.left.entry.ty ~= self.entry.ty then
    return CMat.CMatCFragmentSinkRejected({
      CMat.CMatCEmissionTypeMismatch(
        "all-compare operands", input.left.entry.ty, self.entry.ty)
    })
  end
  local emitted = input.control.state:cmat_window_compare(
    CMat.CMatCWindowCompareInput(
      "all_compare", input.operation.cmp, input.left.entry.atom,
      self.entry.atom, self.entry.ty))
  return emitted.state.provenance.result:cmat_prepare_control_exits(
    CMat.CMatCControlExitInput(
      emitted.state, input.control.sink, emitted.atom,
      emitted.state.provenance.result))
end
function Stencil.StencilSinkOpAllCompare:cmat_fragment_emit_sink(state, sink)
  return state.streams:cmat_fragment_lookup(self.left)
:cmat_control_all_compare_left(CMat.CMatCControlAllCompareRequest(
  CMat.CMatCControlSinkInput(state, sink), self))
end
function Stencil.StencilSinkOpAll:cmat_fragment_emit_sink(state, sink)
  return state.streams:cmat_fragment_lookup(self.src):cmat_control_predicate(
    CMat.CMatCControlPredicateRequest(
      CMat.CMatCControlSinkInput(state, sink), self.pred))
end
function Stencil.StencilSinkOpAny:cmat_fragment_emit_sink(state, sink)
  return state.streams:cmat_fragment_lookup(self.src):cmat_control_predicate(
    CMat.CMatCControlPredicateRequest(
      CMat.CMatCControlSinkInput(state, sink), self.pred))
end
function Stencil.StencilSinkOpFind:cmat_fragment_emit_sink(state, sink)
  return state.streams:cmat_fragment_lookup(self.src):cmat_control_predicate(
    CMat.CMatCControlPredicateRequest(
      CMat.CMatCControlSinkInput(state, sink), self.pred))
end
function Stencil.StencilKernelResultProvenance:cmat_prepare_control_exits(input)
  return CMat.CMatCFragmentSinkRejected({
    CMat.CMatCEmissionInvalidControl(
      input.sink, "control sink disagrees with result provenance")
  })
end
function CMat.CMatCExitBindingMissing:cmat_prepare_control_second(_input)
  return CMat.CMatCFragmentSinkRejected({
    CMat.CMatCEmissionMissingExit(self.role)
  })
end
function CMat.CMatCExitBindingAmbiguous:cmat_prepare_control_second(_input)
  return CMat.CMatCFragmentSinkRejected({
    CMat.CMatCEmissionInvalidKernel(
      "control exit role is ambiguous")
  })
end
function CMat.CMatCExitBindingFound:cmat_prepare_control_second(input)
  return input.provenance:cmat_prepare_second_control_exit(
    CMat.CMatCControlSecondExitInput(input, self))
end
function CMat.CMatCExitBindingMissing:cmat_finish_control_exits(_input)
  return CMat.CMatCFragmentSinkRejected({
    CMat.CMatCEmissionMissingExit(self.role)
  })
end
function CMat.CMatCExitBindingAmbiguous:cmat_finish_control_exits(_input)
  return CMat.CMatCFragmentSinkRejected({
    CMat.CMatCEmissionInvalidKernel(
      "control exit role is ambiguous")
  })
end
function CMat.CMatCExitBindingFound:cmat_finish_control_exits(input)
  return input.control.provenance:cmat_finish_control_exits(
    CMat.CMatCControlResolvedExitsInput(input.control, input.first, self))
end
function Stencil.StencilKernelResultAll:cmat_prepare_control_exits(input)
  local op = input.sink.op
  if input.sink.id ~= self.sink or op.src ~= self.src
      or op.pred ~= self.pred then
    return CMat.CMatCFragmentSinkRejected({
      CMat.CMatCEmissionInvalidControl(
        input.sink, "all sink identity disagrees with provenance")
    })
  end
  return input.state.request.exits:cmat_fragment_lookup(CMat.CMatCExitSuccess)
:cmat_prepare_control_second(input)
end
function Stencil.StencilKernelResultAll:cmat_prepare_second_control_exit(input)
  if input.first.entry.destination ~= self.success then
    return CMat.CMatCFragmentSinkRejected({
      CMat.CMatCEmissionInvalidExit(
        input.first.entry.destination, "all success destination mismatch")
    })
  end
  return input.control.state.request.exits:cmat_fragment_lookup(CMat.CMatCExitFailure)
:cmat_finish_control_exits(input)
end
function Stencil.StencilKernelResultAll:cmat_finish_control_exits(input)
  if input.second.entry.destination ~= self.failure then
    return CMat.CMatCFragmentSinkRejected({
      CMat.CMatCEmissionInvalidExit(
        input.second.entry.destination, "all failure destination mismatch")
    })
  end
  return CMat.CMatCFragmentControlSinkEmitted(CMat.CMatCFragmentBodyAll(
    input.control.state, input.control.condition, input.first, input.second))
end
function Stencil.StencilKernelResultAllCompare:cmat_prepare_control_exits(input)
  local op = input.sink.op
  if input.sink.id ~= self.sink or op.left ~= self.left
      or op.right ~= self.right or op.cmp ~= self.cmp then
    return CMat.CMatCFragmentSinkRejected({
      CMat.CMatCEmissionInvalidControl(
        input.sink, "all-compare sink identity disagrees with provenance")
    })
  end
  return input.state.request.exits:cmat_fragment_lookup(CMat.CMatCExitSuccess)
:cmat_prepare_control_second(input)
end
function Stencil.StencilKernelResultAllCompare:cmat_prepare_second_control_exit(input)
  if input.first.entry.destination ~= self.success then
    return CMat.CMatCFragmentSinkRejected({
      CMat.CMatCEmissionInvalidExit(
        input.first.entry.destination, "all-compare success destination mismatch")
    })
  end
  return input.control.state.request.exits:cmat_fragment_lookup(CMat.CMatCExitFailure)
:cmat_finish_control_exits(input)
end
function Stencil.StencilKernelResultAllCompare:cmat_finish_control_exits(input)
  if input.second.entry.destination ~= self.failure then
    return CMat.CMatCFragmentSinkRejected({
      CMat.CMatCEmissionInvalidExit(
        input.second.entry.destination, "all-compare failure destination mismatch")
    })
  end
  return CMat.CMatCFragmentControlSinkEmitted(
    CMat.CMatCFragmentBodyAllCompare(
      input.control.state, input.control.condition, input.first, input.second))
end
function Stencil.StencilKernelResultAny:cmat_prepare_control_exits(input)
  local op = input.sink.op
  if input.sink.id ~= self.sink or op.src ~= self.src
      or op.pred ~= self.pred then
    return CMat.CMatCFragmentSinkRejected({
      CMat.CMatCEmissionInvalidControl(
        input.sink, "any sink identity disagrees with provenance")
    })
  end
  return input.state.request.exits:cmat_fragment_lookup(CMat.CMatCExitSuccess)
:cmat_prepare_control_second(input)
end
function Stencil.StencilKernelResultAny:cmat_prepare_second_control_exit(input)
  if input.first.entry.destination ~= self.success then
    return CMat.CMatCFragmentSinkRejected({
      CMat.CMatCEmissionInvalidExit(
        input.first.entry.destination, "any success destination mismatch")
    })
  end
  return input.control.state.request.exits:cmat_fragment_lookup(CMat.CMatCExitFailure)
:cmat_finish_control_exits(input)
end
function Stencil.StencilKernelResultAny:cmat_finish_control_exits(input)
  if input.second.entry.destination ~= self.failure then
    return CMat.CMatCFragmentSinkRejected({
      CMat.CMatCEmissionInvalidExit(
        input.second.entry.destination, "any failure destination mismatch")
    })
  end
  return CMat.CMatCFragmentControlSinkEmitted(CMat.CMatCFragmentBodyAny(
    input.control.state, input.control.condition, input.first, input.second))
end
function Stencil.StencilKernelResultFind:cmat_prepare_control_exits(input)
  local op = input.sink.op
  if input.sink.id ~= self.sink or op.src ~= self.src
      or op.pred ~= self.pred or op.not_found ~= self.not_found_value
      or self.found_value ~= input.state.provenance.iteration.counter then
    return CMat.CMatCFragmentSinkRejected({
      CMat.CMatCEmissionInvalidControl(
        input.sink, "find sink identity disagrees with provenance")
    })
  end
  return input.state.request.exits:cmat_fragment_lookup(CMat.CMatCExitFound)
:cmat_prepare_control_second(input)
end
function Stencil.StencilKernelResultFind:cmat_prepare_second_control_exit(input)
  if input.first.entry.destination ~= self.found then
    return CMat.CMatCFragmentSinkRejected({
      CMat.CMatCEmissionInvalidExit(
        input.first.entry.destination, "find found destination mismatch")
    })
  end
  return input.control.state.request.exits:cmat_fragment_lookup(
    CMat.CMatCExitNotFound):cmat_finish_control_exits(input)
end
function Stencil.StencilKernelResultFind:cmat_finish_control_exits(input)
  if input.second.entry.destination ~= self.not_found then
    return CMat.CMatCFragmentSinkRejected({
      CMat.CMatCEmissionInvalidExit(
        input.second.entry.destination, "find not-found destination mismatch")
    })
  end
  return self.not_found_value:cmat_fragment_entry_expr(input.control.state)
:cmat_finish_find_control(CMat.CMatCControlFindValueInput(
  input.control, input.first, input.second))
end
function CMat.CMatCFragmentExprRejected:cmat_finish_find_control(_input)
  return CMat.CMatCFragmentSinkRejected(self.issues)
end
function CMat.CMatCFragmentExprEmitted:cmat_finish_find_control(input)
  if self.ty ~= self.state.index.ty then
    return CMat.CMatCFragmentSinkRejected({
      CMat.CMatCEmissionTypeMismatch(
        "find not-found value", self.state.index.ty, self.ty)
    })
  end
  return CMat.CMatCFragmentControlSinkEmitted(CMat.CMatCFragmentBodyFind(
    self.state, input.control.condition, input.found, input.not_found,
    C.CBackendAtomLocal(self.state.index.id), self.atom, self.ty))
end
function Stencil.StencilSinkOpStore:cmat_fragment_emit_sink(state, sink)
  return self.index:cmat_fragment_index(state, sink)
    :cmat_fragment_finish_store_index(sink, self)
end
function CMat.CMatCFragmentExprRejected:cmat_fragment_finish_store_index(_sink, _op)
  return CMat.CMatCFragmentSinkRejected(self.issues)
end
function CMat.CMatCFragmentExprEmitted:cmat_fragment_finish_store_index(sink, op)
  return self.state.streams:cmat_fragment_lookup(op.value)
    :cmat_fragment_store_stream(CMat.CMatCFragmentStoreRequest(
      self.state, sink, op.dst, self.atom, self.ty))
end
function CMat.CMatCFragmentStreamMissing:cmat_fragment_store_stream(_input)
  return CMat.CMatCFragmentSinkRejected({ CMat.CMatCEmissionMissingStream(self.stream) })
end
function CMat.CMatCFragmentStreamFound:cmat_fragment_store_stream(request)
  local input = CMat.CMatCFragmentStoreInput(
    request.state, request.sink, request.dst, request.index, request.index_ty,
    self.entry)
  return request.sink.op.semantics:cmat_fragment_store_semantics(input)
end
function Stencil.StencilStoreSemantics:cmat_fragment_store_semantics(input)
  return CMat.CMatCFragmentSinkRejected({
    CMat.CMatCEmissionUnsupportedSink(
      input.sink, "store semantics are outside elementwise fragment emission")
  })
end
function Stencil.StencilStoreElementwise:cmat_fragment_store_semantics(input)
  return input.state.request.accesses:cmat_fragment_lookup(input.dst)
:cmat_fragment_store_bound(input)
end
function CMat.CMatCFragmentAccessBindingMissing:cmat_fragment_store_bound(_input)
  return CMat.CMatCFragmentSinkRejected({ CMat.CMatCEmissionMissingAccess(self.access) })
end
function CMat.CMatCFragmentPlaceRejected:cmat_fragment_finish_store(_input)
  return CMat.CMatCFragmentSinkRejected(self.issues)
end
function CMat.CMatCFragmentPlaceEmitted:cmat_fragment_finish_store(input)
  local state = self.state:cmat_fragment_add_body(
    C.CBackendPlaceStore(self.place, input.stream.atom))
  return CMat.CMatCFragmentSinkEmitted(state, CMat.CMatCControlNone, {})
end
function CMat.CMatCFragmentAccessBindingFound:cmat_fragment_store_bound(input)
  return self:cmat_fragment_access_place(CMat.CMatCFragmentAccessPlaceInput(
    input.state, CMat.CMatSinkMemoryUse(Stencil.StencilSinkRef(input.sink.id)),
    input.index, input.index_ty, input.stream.ty))
:cmat_fragment_finish_store(input)
end

function Stencil.StencilSinkOpFold:cmat_fragment_emit_sink(state, sink)
  return state.streams:cmat_fragment_lookup(self.value)
:cmat_fragment_fold_stream(
  CMat.CMatCFragmentFoldRequest(state, sink, self))
end
function CMat.CMatCFragmentStreamMissing:cmat_fragment_fold_stream(_input)
  return CMat.CMatCFragmentSinkRejected({ CMat.CMatCEmissionMissingStream(self.stream) })
end
function CMat.CMatCFragmentStreamFound:cmat_fragment_fold_stream(request)
  local exact = CMat.CMatCFragmentFoldInput(
    request.state, request.sink, request.operation, self.entry)
  return request.operation.destination:cmat_fragment_fold_destination(exact)
end
function Stencil.StencilFoldDestination:cmat_fragment_fold_destination(input)
  return CMat.CMatCFragmentSinkRejected({
    CMat.CMatCEmissionUnsupportedSink(
      input.sink, "fold destination is outside value-result fragment emission")
  })
end
function Stencil.StencilFoldReturnsValue:cmat_fragment_fold_destination(input)
  return input.operation.reducer.identity:cmat_fragment_entry_expr(input.state)
:cmat_fragment_initialize_fold(input)
end
function CMat.CMatCFragmentExprRejected:cmat_fragment_initialize_fold(_input)
  return CMat.CMatCFragmentSinkRejected(self.issues)
end
function CMat.CMatCFragmentExprEmitted:cmat_fragment_initialize_fold(input)
  local ty = input.operation.result_ty:code_to_c_backend_type()
  if self.ty ~= ty then
    return CMat.CMatCFragmentSinkRejected({
      CMat.CMatCEmissionTypeMismatch("fold identity", ty, self.ty)
    })
  end
  local allocation = self.state:cmat_fragment_allocate("fold", ty)
  local state = allocation.state:cmat_fragment_add_entry(
    C.CBackendAssign(allocation.c_local.id, C.CBackendRAtom(self.atom)))
  return input.operation.reducer.arithmetic:cmat_fragment_reduction_spec(
    CMat.CMatCFragmentReductionSpecInput(
      input.operation.reducer.reduction, input.operation.result_ty))
:cmat_fragment_update_fold(CMat.CMatCFragmentFoldFinishInput(
  state, input.sink, input.operation, input.stream, allocation.c_local, ty))
end
function CMat.CMatCBinaryRejected:cmat_fragment_update_fold(input)
  return CMat.CMatCFragmentSinkRejected({
    CMat.CMatCEmissionUnsupportedSink(input.sink, self.reason)
  })
end
function CMat.CMatCBinarySelected:cmat_fragment_update_fold(input)
  local helper = input.state:cmat_fragment_add_helper(self.spec)
  local state = helper.state:cmat_fragment_add_body(C.CBackendHelperCall(
    input.accumulator.id, helper.helper, {
      C.CBackendAtomLocal(input.accumulator.id), input.stream.atom }))
  local finish = CMat.CMatCFragmentFoldFinishInput(
    state, input.sink, input.operation, input.stream, input.accumulator, input.ty)
  return state.provenance.result:cmat_fragment_finish_fold(finish)
end
function Stencil.StencilKernelResultProvenance:cmat_fragment_finish_fold(input)
  return CMat.CMatCFragmentSinkRejected({
    CMat.CMatCEmissionInvalidKernel("fold sink has no reduction kernel result")
  })
end
function Stencil.StencilKernelResultReduction:cmat_fragment_finish_fold(input)
  if self.reduction ~= input.operation.reducer.reduction then
    return CMat.CMatCFragmentSinkRejected({
      CMat.CMatCEmissionInvalidKernel("fold reducer does not match kernel result")
    })
  end
  local atom = C.CBackendAtomLocal(input.accumulator.id)
  return CMat.CMatCFragmentSinkEmitted(
    input.state, CMat.CMatCControlValue(atom, input.ty), {
      CMat.CMatCValueMapping(self.accumulator, input.accumulator),
    })
end

function Stencil.StencilSinkOpScan:cmat_fragment_emit_sink(state, sink)
  return state.streams:cmat_fragment_lookup(self.value):cmat_fragment_scan_stream(
    CMat.CMatCFragmentScanRequest(state, sink, self))
end
function CMat.CMatCFragmentStreamMissing:cmat_fragment_scan_stream(_request)
  return CMat.CMatCFragmentSinkRejected({
    CMat.CMatCEmissionMissingStream(self.stream)
  })
end
function CMat.CMatCFragmentStreamFound:cmat_fragment_scan_stream(request)
  local input = CMat.CMatCFragmentScanInput(
    request.state, request.sink, request.operation, self.entry)
  return request.operation.reducer.identity:cmat_fragment_entry_expr(request.state)
    :cmat_fragment_initialize_scan(input)
end
function CMat.CMatCFragmentExprRejected:cmat_fragment_initialize_scan(_input)
  return CMat.CMatCFragmentSinkRejected(self.issues)
end
function CMat.CMatCFragmentExprEmitted:cmat_fragment_initialize_scan(input)
  local ty = input.operation.reducer.result_ty:code_to_c_backend_type()
  if self.ty ~= ty then
    return CMat.CMatCFragmentSinkRejected({
      CMat.CMatCEmissionTypeMismatch("scan identity", ty, self.ty)
    })
  end
  local allocation = self.state:cmat_fragment_allocate("scan", ty)
  local state = allocation.state:cmat_fragment_add_entry(
    C.CBackendAssign(allocation.c_local.id, C.CBackendRAtom(self.atom)))
  return state.request.accesses:cmat_fragment_lookup(input.operation.dst)
    :cmat_fragment_scan_bound(CMat.CMatCFragmentScanBoundInput(
      CMat.CMatCFragmentScanInput(
        state, input.sink, input.operation, input.stream),
      allocation.c_local, ty))
end
function CMat.CMatCFragmentAccessBindingMissing:cmat_fragment_scan_bound(input)
  return CMat.CMatCFragmentSinkRejected({
    CMat.CMatCEmissionMissingAccess(input.scan.operation.dst)
  })
end
function CMat.CMatCFragmentAccessBindingFound:cmat_fragment_scan_bound(input)
  local scan = input.scan
  return self:cmat_fragment_access_place(CMat.CMatCFragmentAccessPlaceInput(
    scan.state, CMat.CMatSinkMemoryUse(Stencil.StencilSinkRef(scan.sink.id)),
    C.CBackendAtomLocal(scan.state.index.id), scan.state.index.ty, input.ty))
    :cmat_fragment_finish_scan_place(input)
end
function CMat.CMatCFragmentPlaceRejected:cmat_fragment_finish_scan_place(_input)
  return CMat.CMatCFragmentSinkRejected(self.issues)
end
function CMat.CMatCFragmentPlaceEmitted:cmat_fragment_finish_scan_place(input)
  local scan = input.scan
  local finish = CMat.CMatCFragmentScanFinishInput(
    self.state, scan.sink, scan.operation, scan.stream,
    input.accumulator, input.ty, self.place)
  return scan.operation.reducer.arithmetic:cmat_fragment_reduction_spec(
    CMat.CMatCFragmentReductionSpecInput(
      scan.operation.reducer.reduction, scan.operation.reducer.result_ty))
    :cmat_fragment_update_scan(finish)
end
function CMat.CMatCBinaryRejected:cmat_fragment_update_scan(input)
  return CMat.CMatCFragmentSinkRejected({
    CMat.CMatCEmissionUnsupportedSink(input.sink, self.reason)
  })
end
function CMat.CMatCBinarySelected:cmat_fragment_update_scan(input)
  local helper = input.state:cmat_fragment_add_helper(self.spec)
  local finish = CMat.CMatCFragmentScanFinishInput(
    helper.state, input.sink, input.operation, input.stream,
    input.accumulator, input.ty, input.place)
  return input.operation.mode:cmat_fragment_emit_scan(
    CMat.CMatCFragmentScanEmissionInput(finish, helper.helper))
end
local function cmat_fragment_scan_update(input)
  local finish = input.finish
  return C.CBackendHelperCall(finish.accumulator.id, input.helper, {
    C.CBackendAtomLocal(finish.accumulator.id), finish.stream.atom,
  })
end
local function cmat_fragment_scan_store(input)
  return C.CBackendPlaceStore(input.finish.place,
    C.CBackendAtomLocal(input.finish.accumulator.id))
end
function Stencil.StencilScanInclusive:cmat_fragment_emit_scan(input)
  local state = input.finish.state:cmat_fragment_add_body(
    cmat_fragment_scan_update(input))
  state = state:cmat_fragment_add_body(cmat_fragment_scan_store(
    CMat.CMatCFragmentScanEmissionInput(
      CMat.CMatCFragmentScanFinishInput(
        state, input.finish.sink, input.finish.operation, input.finish.stream,
        input.finish.accumulator, input.finish.ty, input.finish.place),
      input.helper)))
  return CMat.CMatCFragmentSinkEmitted(state, CMat.CMatCControlNone, {})
end
function Stencil.StencilScanExclusive:cmat_fragment_emit_scan(input)
  local state = input.finish.state:cmat_fragment_add_body(
    cmat_fragment_scan_store(input))
  local next_input = CMat.CMatCFragmentScanEmissionInput(
    CMat.CMatCFragmentScanFinishInput(
      state, input.finish.sink, input.finish.operation, input.finish.stream,
      input.finish.accumulator, input.finish.ty, input.finish.place),
    input.helper)
  state = state:cmat_fragment_add_body(cmat_fragment_scan_update(next_input))
  return CMat.CMatCFragmentSinkEmitted(state, CMat.CMatCControlNone, {})
end


function Stencil.StencilStreamByKernelValueFound:cmat_fragment_bound_source(state, expr)
  return self.entry.definition.op:cmat_fragment_emit_bound(state, expr)
end
function Stencil.StencilStreamByKernelValueMissing:cmat_fragment_bound_source(_state, _expr)
  return CMat.CMatCFragmentBoundRejected({
    CMat.CMatCEmissionMissingValue(Code.CodeValueId(self.value.text))
  })
end
function Stencil.StencilStreamOp:cmat_fragment_emit_bound(_state, expr)
  return CMat.CMatCFragmentBoundRejected({
    CMat.CMatCEmissionUnsupportedValue(expr, "loop bound is not an invariant scalar value")
  })
end
function Stencil.StencilStreamValueExpr:cmat_fragment_emit_bound(state, _expr)
  return self.value:cmat_fragment_entry_expr(state):cmat_fragment_bound_from_expr()
end
function CMat.CMatCFragmentExprRejected:cmat_fragment_bound_from_expr()
  return CMat.CMatCFragmentBoundRejected(self.issues)
end
function CMat.CMatCFragmentExprEmitted:cmat_fragment_bound_from_expr()
  return CMat.CMatCFragmentBoundEmitted(self.state, self.atom, self.ty)
end
function CMat.CMatCFragmentValueFound:cmat_fragment_bound_value(state, _expr)
  return CMat.CMatCFragmentBoundEmitted(state, self.entry.atom, self.entry.ty)
end
function CMat.CMatCFragmentValueMissing:cmat_fragment_bound_value(state, expr)
  return state.provenance.streams:cmat_fragment_lookup_source(expr.value)
    :cmat_fragment_bound_source(state, expr)
end
function CMat.CMatCExternalValueBindingFound:cmat_fragment_bound_value(state, _expr)
  return CMat.CMatCFragmentBoundEmitted(
    state, C.CBackendAtomLocal(self.entry.c_local.id), self.entry.c_local.ty)
end
function CMat.CMatCExternalValueBindingMissing:cmat_fragment_bound_value(state, expr)
  return state.provenance.streams:cmat_fragment_lookup_source(expr.value)
:cmat_fragment_bound_source(state, expr)
end
function Value.ValueExprValue:cmat_fragment_bound(state)
  return state.request.values:cmat_fragment_lookup(self.value)
:cmat_fragment_bound_value(state, self)
end
function Value.ValueExprConst:cmat_fragment_bound(state)
  return self:cmat_fragment_expr(state):cmat_fragment_bound_from_expr()
end
function Value.ValueExpr:cmat_fragment_bound(_state)
  return CMat.CMatCFragmentBoundRejected({
    CMat.CMatCEmissionUnsupportedValue(self, "loop bound expression is unavailable")
  })
end
function Stencil.StencilBoundDynamic:cmat_fragment_bound(_state)
  return CMat.CMatCFragmentBoundRejected({
    CMat.CMatCEmissionInvalidKernel("counted fragment has a dynamic start bound")
  })
end
function Stencil.StencilBoundValue:cmat_fragment_bound(state)
  return self.value:cmat_fragment_bound(state)
end

function Stencil.StencilKernelTripExact:cmat_fragment_trip(state)
  return Value.ValueExprValue(self.trip_count.count):cmat_fragment_bound(state)
    :cmat_fragment_trip_fallback(state, self)
end
function Stencil.StencilKernelTripNonNegative:cmat_fragment_trip(state)
  return Value.ValueExprValue(self.trip_count.count):cmat_fragment_bound(state)
    :cmat_fragment_trip_fallback(state, self)
end
function CMat.CMatCFragmentBoundEmitted:cmat_fragment_trip_fallback(_state, _trip)
  return self
end
function CMat.CMatCFragmentBoundRejected:cmat_fragment_trip_fallback(state, trip)
  local expression = trip.trip_count.trip_expr
  if expression == nil then
    return CMat.CMatCFragmentBoundRejected({ CMat.CMatCEmissionMissingTripCount(trip) })
  end
  return expression:cmat_fragment_bound(state)
end

function CMat.CMatCFragmentBoundRejected:cmat_fragment_continue_trip(_continuation)
  return CMat.CMatCFragmentRejected(self.issues)
end
function CMat.CMatCFragmentCountedPlan:cmat_fragment_materialization()
  return self.materialization
end
function Code.CodeType:cmat_fragment_validate_window_plan(_input)
  return CMat.CMatCFragmentStateRejected({
    CMat.CMatCEmissionInvalidKernel(
      "window index type is outside signed scalar emission")
  })
end
function Code.CodeTyInt:cmat_fragment_validate_window_plan(input)
  return self.signedness:cmat_fragment_validate_window_signedness(input)
end
function Code.CodeTyIndex:cmat_fragment_validate_window_plan(_input)
  return CMat.CMatCFragmentStateRejected({
    CMat.CMatCEmissionInvalidKernel(
      "initial window emission rejects unsigned CodeTyIndex offsets")
  })
end
function Code.CodeSigned:cmat_fragment_validate_window_signedness(input)
  return CMat.CMatCFragmentStateReady(input.state)
end
function Code.CodeUnsigned:cmat_fragment_validate_window_signedness(_input)
  return CMat.CMatCFragmentStateRejected({
    CMat.CMatCEmissionInvalidKernel(
      "initial window emission requires a signed index type")
  })
end
function CMat.CMatCFragmentWindowPlan:cmat_fragment_materialization()
  return self.materialization
end
function CMat.CMatCFragmentCountedPlan:cmat_fragment_prepare_body(input)
  return CMat.CMatCFragmentStateReady(input.state)
end
function CMat.CMatCFragmentStateRejected:cmat_fragment_compute_window_bounds(_input)
  return self
end
function CMat.CMatCFragmentStateReady:cmat_fragment_compute_window_bounds(input)
  return input.plan.axis.order:cmat_fragment_window_bounds(
    CMat.CMatCFragmentWindowBoundsInput(self.state, input.plan, input.body))
end

function Stencil.StencilProducerForward:cmat_fragment_window_bounds(input)
  local ty = input.body.start.ty
  local one = C.CBackendAtomLiteral(ty, Core.LitInt("1"))
  local step = C.CBackendAtomLiteral(
    ty, Core.LitInt(tostring(input.plan.axis.step)))
  local remaining = input.state:cmat_window_binary(CMat.CMatCWindowBinaryInput(
    "window_trip_minus_one", Core.BinSub, input.body.trip.atom, one,
    input.body.start.ty))
  local span = remaining.state:cmat_window_binary(CMat.CMatCWindowBinaryInput(
    "window_domain_span", Core.BinMul, remaining.atom, step, input.body.start.ty))
  local upper = span.state:cmat_window_binary(CMat.CMatCWindowBinaryInput(
    "window_domain_upper", Core.BinAdd, input.body.start.atom, span.atom,
    input.body.start.ty))
  local extent = upper.state:cmat_window_binary(CMat.CMatCWindowBinaryInput(
    "window_domain_extent", Core.BinAdd, span.atom, one, input.body.start.ty))
  local bounds = CMat.CMatCFragmentWindowBounds(
    extent.state, input.body.start.ty, input.body.iteration_index,
    input.body.start.atom, upper.atom, extent.atom)
  return bounds:cmat_fragment_install_window(
    CMat.CMatCFragmentWindowInstallInput(input.plan, bounds))
end
function Stencil.StencilProducerBackward:cmat_fragment_window_bounds(input)
  local ty = input.body.start.ty
  local one = C.CBackendAtomLiteral(ty, Core.LitInt("1"))
  local step = C.CBackendAtomLiteral(
    ty, Core.LitInt(tostring(input.plan.axis.step)))
  local remaining = input.state:cmat_window_binary(CMat.CMatCWindowBinaryInput(
    "window_trip_minus_one", Core.BinSub, input.body.trip.atom, one,
    input.body.start.ty))
  local span = remaining.state:cmat_window_binary(CMat.CMatCWindowBinaryInput(
    "window_domain_span", Core.BinMul, remaining.atom, step, input.body.start.ty))
  local lower = span.state:cmat_window_binary(CMat.CMatCWindowBinaryInput(
    "window_domain_lower", Core.BinSub, input.body.start.atom, span.atom,
    input.body.start.ty))
  local extent = lower.state:cmat_window_binary(CMat.CMatCWindowBinaryInput(
    "window_domain_extent", Core.BinAdd, span.atom, one, input.body.start.ty))
  local bounds = CMat.CMatCFragmentWindowBounds(
    extent.state, input.body.start.ty, input.body.iteration_index,
    lower.atom, input.body.start.atom, extent.atom)
  return bounds:cmat_fragment_install_window(
    CMat.CMatCFragmentWindowInstallInput(input.plan, bounds))
end
function CMat.CMatCFragmentWindowBounds:cmat_fragment_install_window(input)
  return CMat.CMatCFragmentStateReady(self.state:cmat_fragment_with_window(
    CMat.CMatCFragmentWindow1D(
      input.plan.axis, input.plan.window, self.lower, self.upper, self.extent,
      self.index, self.index_ty)))
end
function Code.CodeType:cmat_fragment_prepare_window_bounds(input)
  return self:cmat_fragment_validate_window_plan(input.body)
    :cmat_fragment_compute_window_bounds(input)
end
function Code.CodeTyIndex:cmat_fragment_prepare_window_bounds(input)
  local signed_ty = Code.CodeTyInt(64, Code.CodeSigned):code_to_c_backend_type()
  local start_alloc = input.state:cmat_fragment_allocate("window_start_signed", signed_ty)
  local state = start_alloc.state:cmat_fragment_add_body(C.CBackendAssign(
    start_alloc.c_local.id, C.CBackendRCast(
      Core.MachineCastIdentity, signed_ty, input.body.start.atom)))
  local trip_alloc = state:cmat_fragment_allocate("window_trip_signed", signed_ty)
  state = trip_alloc.state:cmat_fragment_add_body(C.CBackendAssign(
    trip_alloc.c_local.id, C.CBackendRCast(
      Core.MachineCastIdentity, signed_ty, input.body.trip.atom)))
  local index_alloc = state:cmat_fragment_allocate("window_index_signed", signed_ty)
  state = index_alloc.state:cmat_fragment_add_body(C.CBackendAssign(
    index_alloc.c_local.id, C.CBackendRCast(
      Core.MachineCastIdentity, signed_ty, C.CBackendAtomLocal(state.index.id))))
  local body = CMat.CMatCFragmentPlanBodyInput(state,
    CMat.CMatCFragmentBoundEmitted(state, C.CBackendAtomLocal(start_alloc.c_local.id), signed_ty),
    CMat.CMatCFragmentBoundEmitted(state, C.CBackendAtomLocal(trip_alloc.c_local.id), signed_ty),
    C.CBackendAtomLocal(index_alloc.c_local.id))
  return input.plan.axis.order:cmat_fragment_window_bounds(
    CMat.CMatCFragmentWindowBoundsInput(state, input.plan, body))
end
function CMat.CMatCFragmentWindowPlan:cmat_fragment_prepare_body(input)
  if input.start.ty ~= self.materialization.provenance.iteration.index_ty:code_to_c_backend_type()
      or input.trip.ty ~= input.start.ty then
    return CMat.CMatCFragmentStateRejected({
      CMat.CMatCEmissionInvalidKernel(
        "window start/trip types disagree with exact iteration")
    })
  end
  return self.axis.index_ty:cmat_fragment_prepare_window_bounds(
    CMat.CMatCFragmentWindowBoundsInput(input.state, self, input))
end
function CMat.CMatCFragmentBoundEmitted:cmat_fragment_continue_trip(continuation)
  local materialization = continuation.plan:cmat_fragment_materialization()
  local trip = materialization.provenance.iteration.trip:cmat_fragment_trip(self.state)
  return trip:cmat_fragment_continue_body(CMat.CMatCFragmentTripContinuation(
    continuation.plan, self, trip))
end
function CMat.CMatCFragmentBoundRejected:cmat_fragment_continue_body(_continuation)
  return CMat.CMatCFragmentRejected(self.issues)
end
function CMat.CMatCFragmentBoundEmitted:cmat_fragment_continue_body(continuation)
  return continuation.plan:cmat_fragment_prepare_body(
    CMat.CMatCFragmentPlanBodyInput(
      self.state, continuation.start, self,
      C.CBackendAtomLocal(self.state.index.id)))
:cmat_fragment_continue_prepared_body(continuation)
end
function CMat.CMatCFragmentStateRejected:cmat_fragment_continue_prepared_body(_continuation)
  return CMat.CMatCFragmentRejected(self.issues)
end
function CMat.CMatCFragmentStateReady:cmat_fragment_continue_prepared_body(continuation)
  local materialization = continuation.plan:cmat_fragment_materialization()
  local step = self
  for i = 1, #materialization.provenance.streams.entries do
    step = step:cmat_fragment_apply_stream(materialization.provenance.streams.entries[i])
  end
  local body = CMat.CMatCFragmentBodyInput(
    continuation.plan, self.state, continuation.start, continuation.trip)
  local sinks = materialization.kernel.computation.sinks
  if #sinks == 0 then
    return CMat.CMatCFragmentRejected({
      CMat.CMatCEmissionInvalidKernel(
        "scalar counted fragment requires at least one sink")
    })
  end
  return step:cmat_fragment_apply_sink(sinks[1])
    :cmat_fragment_continue_sinks(
      CMat.CMatCFragmentSinkFoldInput(sinks, 2, body))
end

function CMat.CMatCFragmentSinkRejected:cmat_fragment_continue_sinks(_input)
  return CMat.CMatCFragmentRejected(self.issues)
end
function CMat.CMatCFragmentSinkEmitted:cmat_fragment_continue_sinks(input)
  if input.next_index > #input.sinks then
    return CMat.CMatCFragmentBodyContinue(
      self.state, self.control, self.value_mappings)
:cmat_fragment_finish_body_plan(input.body)
  end
  local fold = CMat.CMatCFragmentSinkFoldInput(
    input.sinks, input.next_index + 1, input.body)
  return CMat.CMatCFragmentStateReady(self.state)
:cmat_fragment_apply_sink(input.sinks[input.next_index])
:cmat_fragment_merge_sink(CMat.CMatCFragmentSinkMergeInput(self, fold))
end
function CMat.CMatCFragmentControlSinkEmitted:cmat_fragment_continue_sinks(input)
  if input.next_index > #input.sinks then
    return self.body:cmat_fragment_finish_body_plan(input.body)
  end
  return CMat.CMatCFragmentRejected({
    CMat.CMatCEmissionInvalidKernel(
      "a control sink must be the last computation sink")
  })
end
function CMat.CMatCFragmentSinkRejected:cmat_fragment_merge_sink(_input)
  return CMat.CMatCFragmentRejected(self.issues)
end
function CMat.CMatCFragmentControlSinkEmitted:cmat_fragment_merge_sink(input)
  if input.fold.next_index > #input.fold.sinks then
    return self.body:cmat_fragment_finish_body_plan(input.fold.body)
  end
  return CMat.CMatCFragmentRejected({
    CMat.CMatCEmissionInvalidKernel(
      "a control sink must be the last computation sink")
  })
end
function CMat.CMatCFragmentSinkEmitted:cmat_fragment_merge_sink(input)
  return self.control:cmat_fragment_merge_sink_control(
    CMat.CMatCFragmentControlMergeInput(
      self, input.accumulated, input.fold))
end
function CMat.CMatCControlNone:cmat_fragment_merge_sink_control(input)
  return input:cmat_fragment_continue_merged_sink(input.accumulated.control)
end
function CMat.CMatCControlResult:cmat_fragment_merge_sink_control(input)
  return input.accumulated.control:cmat_fragment_accept_incoming_control(input)
end
function CMat.CMatCControlNone:cmat_fragment_accept_incoming_control(input)
  return input:cmat_fragment_continue_merged_sink(input.current.control)
end
function CMat.CMatCControlResult:cmat_fragment_accept_incoming_control(_input)
  return CMat.CMatCFragmentRejected({
    CMat.CMatCEmissionInvalidKernel(
      "multiple control-producing sinks in one counted fragment")
  })
end
function CMat.CMatCFragmentControlMergeInput:cmat_fragment_continue_merged_sink(control)
  local mappings = {}
  for i = 1, #self.accumulated.value_mappings do
    mappings[#mappings + 1] = self.accumulated.value_mappings[i]
  end
  for i = 1, #self.current.value_mappings do
    mappings[#mappings + 1] = self.current.value_mappings[i]
  end
  return CMat.CMatCFragmentSinkEmitted(self.current.state, control, mappings)
:cmat_fragment_continue_sinks(self.fold)
end
function CMat.CMatCFragmentBodyContinue:cmat_fragment_finish_body_plan(body)
  local loop = CMat.CMatCCountedLoopAssemblyInput(
    self.state, body.start, body.trip, self)
  return self.state.request.exits:cmat_fragment_lookup(CMat.CMatCExitNormal)
:cmat_fragment_finish_counted(loop)
end
function CMat.CMatCExitBindingFound:cmat_control_mapping()
  return CMat.CMatCControlExitMapping(
    self.entry.role, self.entry.destination, self.entry.label)
end
function CMat.CMatCFragmentBodyFind:cmat_fragment_finish_body_plan(body)
  local collection = CMat.CMatCExitArgumentCollectionReady({})
  local control = CMat.CMatCControlValue(self.found_value, self.ty)
  for i = 1, #self.found.entry.args do
    collection = self.found.entry.args[i]:cmat_fragment_exit_atom(
      CMat.CMatCExitArgumentInput(self.state, control))
:cmat_fragment_collect_exit(collection)
  end
  return collection:cmat_finish_find_found(
    CMat.CMatCFindExitCollectionInput(self, body.start, body.trip, collection))
end
function CMat.CMatCExitArgumentCollectionRejected:cmat_finish_find_found(_input)
  return CMat.CMatCFragmentRejected(self.issues)
end
function CMat.CMatCExitArgumentCollectionReady:cmat_finish_find_found(input)
  local collection = CMat.CMatCExitArgumentCollectionReady({})
  local control = CMat.CMatCControlValue(
    input.body.not_found_value, input.body.ty)
  for i = 1, #input.body.not_found.entry.args do
    collection = input.body.not_found.entry.args[i]:cmat_fragment_exit_atom(
      CMat.CMatCExitArgumentInput(input.body.state, control))
:cmat_fragment_collect_exit(collection)
  end
  return collection:cmat_finish_find_not_found(CMat.CMatCFindLoopAssemblyInput(
    input.body, input.start, input.trip, self, collection))
end
function CMat.CMatCExitArgumentCollectionRejected:cmat_finish_find_not_found(_input)
  return CMat.CMatCFragmentRejected(self.issues)
end
function CMat.CMatCExitArgumentCollectionReady:cmat_finish_find_not_found(input)
  local body = input.body
  local control = CMat.CMatCControlFind(
    body.condition, body.found:cmat_control_mapping(),
    body.not_found:cmat_control_mapping(), body.found_value,
    body.not_found_value, body.ty)
  return CMat.CMatCControlLoopAssemblyInput(
    body.state, input.start, input.trip, body.condition,
    CMat.CMatCControlContinueWhenFalse, body.found, body.not_found,
    input.found.values, self.values, control):cmat_fragment_assemble_control_loop()
end
function CMat.CMatCFragmentBodyAll:cmat_fragment_finish_body_plan(body)
  local control = CMat.CMatCControlAll(
    self.condition, self.success:cmat_control_mapping(),
    self.failure:cmat_control_mapping())
  return CMat.CMatCControlLoopAssemblyInput(
    self.state, body.start, body.trip, self.condition,
    CMat.CMatCControlContinueWhenTrue, self.failure, self.success, {}, {}, control)
:cmat_fragment_assemble_control_loop()
end
function CMat.CMatCFragmentBodyAllCompare:cmat_fragment_finish_body_plan(body)
  local control = CMat.CMatCControlAllCompare(
    self.condition, self.success:cmat_control_mapping(),
    self.failure:cmat_control_mapping())
  return CMat.CMatCControlLoopAssemblyInput(
    self.state, body.start, body.trip, self.condition,
    CMat.CMatCControlContinueWhenTrue, self.failure, self.success, {}, {}, control)
:cmat_fragment_assemble_control_loop()
end
function CMat.CMatCFragmentBodyAny:cmat_fragment_finish_body_plan(body)
  local control = CMat.CMatCControlAny(
    self.condition, self.success:cmat_control_mapping(),
    self.failure:cmat_control_mapping())
  return CMat.CMatCControlLoopAssemblyInput(
    self.state, body.start, body.trip, self.condition,
    CMat.CMatCControlContinueWhenFalse, self.success, self.failure, {}, {}, control)
:cmat_fragment_assemble_control_loop()
end
function CMat.CMatCControlContinueWhenTrue:cmat_control_body_term(input)
  return C.CBackendIfGoto(
    input.condition, input.advance, {}, input.early, input.early_args)
end
function CMat.CMatCControlContinueWhenFalse:cmat_control_body_term(input)
  return C.CBackendIfGoto(
    input.condition, input.early, input.early_args, input.advance, {})
end
function CMat.CMatCCodeBlockMissing:cmat_validate_control_exit(_input)
  return CMat.CMatCControlExitRejected(CMat.CMatCEmissionInvalidExit(
    self.block, "control exit destination is absent from the owning function"))
end
function CMat.CMatCCodeBlockFound:cmat_validate_control_exit(input)
  if #input.arguments ~= #self.block.params then
    return CMat.CMatCControlExitRejected(CMat.CMatCEmissionInvalidExit(
      self.block.id, "control exit argument count does not match block parameters"))
  end
  for i = 1, #input.arguments do
    local expected = self.block.params[i].ty:code_to_c_backend_type()
    if input.arguments[i].ty ~= expected then
      return CMat.CMatCControlExitRejected(CMat.CMatCEmissionTypeMismatch(
        "control exit argument", expected, input.arguments[i].ty))
    end
  end
  return CMat.CMatCControlExitValid
end
function CMat.CMatCControlExitRejected:cmat_validate_second_control_exit(_input)
  return CMat.CMatCControlAssemblyRejected({ self.issue })
end
function CMat.CMatCControlExitValid:cmat_validate_second_control_exit(input)
  return input.exhausted:cmat_finish_control_exit_validation(input.assembly)
end
function CMat.CMatCControlExitRejected:cmat_finish_control_exit_validation(_assembly)
  return CMat.CMatCControlAssemblyRejected({ self.issue })
end
function CMat.CMatCControlExitValid:cmat_finish_control_exit_validation(assembly)
  return CMat.CMatCControlAssemblyValid(assembly)
end
function CMat.CMatCControlLoopAssemblyInput:cmat_validate_control_assembly()
  local early = self.state.request.code_func
:cmat_fragment_block_lookup(self.early.entry.destination)
:cmat_validate_control_exit(CMat.CMatCControlExitValidationInput(self.early_args))
  local exhausted = self.state.request.code_func
:cmat_fragment_block_lookup(self.exhausted.entry.destination)
:cmat_validate_control_exit(CMat.CMatCControlExitValidationInput(self.exhausted_args))
  return early:cmat_validate_second_control_exit(
    CMat.CMatCControlExitPairValidationInput(self, exhausted))
end
function CMat.CMatCControlLoopAssemblyInput:cmat_fragment_assemble_control_loop()
  return self:cmat_validate_control_assembly()
:cmat_fragment_assemble_control_loop()
end
function CMat.CMatCControlAssemblyRejected:cmat_fragment_assemble_control_loop()
  return CMat.CMatCFragmentRejected(self.issues)
end
function CMat.CMatCControlAssemblyValid:cmat_fragment_assemble_control_loop()
  local self = self.assembly
  local early_atoms, exhausted_atoms = {}, {}
  for i = 1, #self.early_args do early_atoms[i] = self.early_args[i].atom end
  for i = 1, #self.exhausted_args do exhausted_atoms[i] = self.exhausted_args[i].atom end
  local state = self.state
  local iteration = state.provenance.iteration
  local index_ty = state.index.ty
  if self.start.ty ~= index_ty or self.trip.ty ~= index_ty then
    return CMat.CMatCFragmentRejected({
      CMat.CMatCEmissionTypeMismatch(
        "control loop bound", index_ty, self.start.ty)
    })
  end
  local test_cond = state:cmat_fragment_allocate("test", C.CBackendBool8)
  state = test_cond.state
  local advance_cond = state:cmat_fragment_allocate("advance", C.CBackendBool8)
  state = advance_cond.state
  local ordinal_add = state:cmat_fragment_add_helper(
    C.CBackendHelperIntBinary(Core.BinAdd, index_ty, C.CBackendIntWrap))
  state = ordinal_add.state
  local index_step = state:cmat_fragment_add_helper(
    C.CBackendHelperIntBinary(
      iteration.order:cmat_fragment_step_op(), index_ty, C.CBackendIntWrap))
  state = index_step.state
  local ns = state.request.namespace.prefix
  local entry_label = C.CBackendLabel(ns .. "_entry")
  local test_label = C.CBackendLabel(ns .. "_test")
  local body_label = C.CBackendLabel(ns .. "_body")
  local advance_label = C.CBackendLabel(ns .. "_advance")
  local step_label = C.CBackendLabel(ns .. "_step")
  local zero = C.CBackendAtomLiteral(index_ty, Core.LitInt("0"))
  local one = C.CBackendAtomLiteral(index_ty, Core.LitInt("1"))
  local magnitude = C.CBackendAtomLiteral(
    index_ty, Core.LitInt(tostring(iteration.step_magnitude)))
  local entry_stmts = copy(state.entry_stmts)
  entry_stmts[#entry_stmts + 1] = C.CBackendAssign(
    state.index.id, C.CBackendRAtom(self.start.atom))
  entry_stmts[#entry_stmts + 1] = C.CBackendAssign(
    state.ordinal.id, C.CBackendRAtom(zero))
  local test_stmts = { C.CBackendAssign(test_cond.c_local.id, C.CBackendRCompare(
    Core.CmpLt, index_ty, C.CBackendAtomLocal(state.ordinal.id), self.trip.atom)) }
  local advance_stmts = {
    C.CBackendHelperCall(state.ordinal.id, ordinal_add.helper,
      { C.CBackendAtomLocal(state.ordinal.id), one }),
    C.CBackendAssign(advance_cond.c_local.id, C.CBackendRCompare(
      Core.CmpLt, index_ty, C.CBackendAtomLocal(state.ordinal.id), self.trip.atom)),
  }
  local step_stmts = { C.CBackendHelperCall(state.index.id, index_step.helper,
    { C.CBackendAtomLocal(state.index.id), magnitude }) }
  local cursor_steps = state.request.address_plan:cmat_fragment_cursor_steps(index_ty)
  for i = 1, #cursor_steps.stmts do
    step_stmts[#step_stmts + 1] = cursor_steps.stmts[i]
  end
  local body_term = self.polarity:cmat_control_body_term(
    CMat.CMatCControlBodyTermInput(
      self.condition, advance_label, self.early.entry.label, early_atoms))
  local blocks = {
    C.CBackendBlock(entry_label, {}, entry_stmts, C.CBackendGoto(test_label, {})),
    C.CBackendBlock(test_label, {}, test_stmts, C.CBackendIfGoto(
      C.CBackendAtomLocal(test_cond.c_local.id), body_label, {},
      self.exhausted.entry.label, exhausted_atoms)),
  }
  for i = 1, #state.cfg.completed do blocks[#blocks + 1] = state.cfg.completed[i] end
  blocks[#blocks + 1] = C.CBackendBlock(
    state.cfg.open.label, state.cfg.open.params, state.cfg.open.stmts, body_term)
  blocks[#blocks + 1] = C.CBackendBlock(advance_label, {}, advance_stmts, C.CBackendIfGoto(
    C.CBackendAtomLocal(advance_cond.c_local.id), step_label, {},
    self.exhausted.entry.label, exhausted_atoms))
  blocks[#blocks + 1] = C.CBackendBlock(
    step_label, {}, step_stmts, C.CBackendGoto(body_label, {}))
  local alignments = {}
  for i = 1, #state.request.covered_blocks do
    local source = state.request.covered_blocks[i]
    if source == state.request.replacement_source then
      alignments[#alignments + 1] = CMat.CMatCBlockReplacementEntry(source, entry_label)
    else
      alignments[#alignments + 1] = CMat.CMatCBlockEliminated(source)
    end
  end
  return CMat.CMatCFragmentEmitted(CMat.CMatCFragment(
    entry_label, blocks, state.locals, state.helpers, alignments, {
      CMat.CMatCValueMapping(iteration.counter, state.index),
    }, self.control))
end
function Stencil.StencilProducerForward:cmat_fragment_step_op() return Core.BinAdd end
function Stencil.StencilProducerBackward:cmat_fragment_step_op() return Core.BinSub end

function C.CBackendAtom:cmat_fragment_exit_declared(input)
  return CMat.CMatCAtomRejected(CMat.CMatCEmissionInvalidKernel(
    "exit atom kind has no exact fragment type resolution"))
end
function C.CBackendAtomLiteral:cmat_fragment_exit_declared(input)
  if self.ty ~= input.declared then
    return CMat.CMatCAtomRejected(CMat.CMatCEmissionTypeMismatch(
      "exit atom annotation", self.ty, input.declared))
  end
  return CMat.CMatCAtomEmitted(self, self.ty)
end
function C.CBackendAtomNull:cmat_fragment_exit_declared(input)
  if self.ty ~= input.declared then
    return CMat.CMatCAtomRejected(CMat.CMatCEmissionTypeMismatch(
      "exit atom annotation", self.ty, input.declared))
  end
  return CMat.CMatCAtomEmitted(self, self.ty)
end
function C.CBackendLocal:cmat_fragment_exit_local(input)
  if self.ty ~= input.declared then
    return CMat.CMatCAtomRejected(CMat.CMatCEmissionTypeMismatch(
      "exit local annotation", self.ty, input.declared))
  end
  return CMat.CMatCAtomEmitted(input.atom, self.ty)
end
function C.CBackendAtomLocal:cmat_fragment_exit_declared(input)
  local state = input.state
  if state.index.id == self.local_id then
    return state.index:cmat_fragment_exit_local(input)
  end
  if state.ordinal.id == self.local_id then
    return state.ordinal:cmat_fragment_exit_local(input)
  end
  for i = 1, #state.locals do
    if state.locals[i].id == self.local_id then
      return state.locals[i]:cmat_fragment_exit_local(input)
    end
  end
  for i = 1, #state.request.values.entries do
    local c_local = state.request.values.entries[i].c_local
    if c_local.id == self.local_id then
      return c_local:cmat_fragment_exit_local(input)
    end
  end
  return CMat.CMatCAtomRejected(CMat.CMatCEmissionInvalidKernel(
    "exit local has no exact fragment type binding"))
end
function CMat.CMatCExitArgumentAtom:cmat_fragment_exit_atom(input)
  return self.atom:cmat_fragment_exit_declared(
    CMat.CMatCExitAtomInput(input.state, self.ty, self.atom))
end
function CMat.CMatCExitArgumentControlValue:cmat_fragment_exit_atom(input)
  return input.control:cmat_fragment_control_atom()
end
function CMat.CMatCControlNone:cmat_fragment_control_atom()
  return CMat.CMatCAtomRejected(CMat.CMatCEmissionInvalidKernel(
    "exit requests a control value from a void sink"))
end
function CMat.CMatCControlValue:cmat_fragment_control_atom()
  return CMat.CMatCAtomEmitted(self.atom, self.ty)
end
function CMat.CMatCControlResult:cmat_fragment_control_atom()
  return CMat.CMatCAtomRejected(CMat.CMatCEmissionInvalidKernel(
    "branch control cannot be used as a scalar exit argument"))
end

function CMat.CMatCExitBindingMissing:cmat_fragment_finish_counted(_input)
  return CMat.CMatCFragmentRejected({ CMat.CMatCEmissionMissingExit(self.role) })
end
function CMat.CMatCExitBindingAmbiguous:cmat_fragment_finish_counted(_input)
  return CMat.CMatCFragmentRejected({
    CMat.CMatCEmissionInvalidKernel(
      "multiple exits have the requested semantic role")
  })
end
function CMat.CMatCAtomEmitted:cmat_fragment_collect_exit(collection)
  return collection:cmat_fragment_add_exit_value(
    CMat.CMatCExitArgumentValue(self.atom, self.ty))
end
function CMat.CMatCAtomRejected:cmat_fragment_collect_exit(collection)
  return collection:cmat_fragment_add_exit_issue(self.issue)
end
function CMat.CMatCExitArgumentCollectionReady:cmat_fragment_add_exit_value(value)
  return CMat.CMatCExitArgumentCollectionReady(append(self.values, value))
end
function CMat.CMatCExitArgumentCollectionReady:cmat_fragment_add_exit_issue(issue)
  return CMat.CMatCExitArgumentCollectionRejected({ issue })
end
function CMat.CMatCExitArgumentCollectionRejected:cmat_fragment_add_exit_value(_value) return self end
function CMat.CMatCExitArgumentCollectionRejected:cmat_fragment_add_exit_issue(issue)
  return CMat.CMatCExitArgumentCollectionRejected(append(self.issues, issue))
end
function CMat.CMatCExitBindingFound:cmat_fragment_finish_counted(input)
  local collection = CMat.CMatCExitArgumentCollectionReady({})
  for i = 1, #self.entry.args do
    collection = self.entry.args[i]:cmat_fragment_exit_atom(
      CMat.CMatCExitArgumentInput(input.state, input.body.control))
:cmat_fragment_collect_exit(collection)
  end
  return collection:cmat_fragment_finish_exit(
    CMat.CMatCExitAssemblyInput(input, self))
end
function CMat.CMatCExitArgumentCollectionRejected:cmat_fragment_finish_exit(_context)
  return CMat.CMatCFragmentRejected(self.issues)
end
function CMat.CMatCExitArgumentCollectionReady:cmat_fragment_finish_exit(context)
  return context.loop.state.request.code_func
:cmat_fragment_block_lookup(context.exit.entry.destination)
:cmat_fragment_validate_exit(CMat.CMatCTypedExitAssemblyInput(context, self))
end
function CMat.CMatCCodeBlockMissing:cmat_fragment_validate_exit(_input)
  return CMat.CMatCFragmentRejected({
    CMat.CMatCEmissionInvalidExit(
      self.block, "exit block is absent from the owning function")
  })
end
function CMat.CMatCCodeBlockFound:cmat_fragment_validate_exit(input)
  local values = input.arguments.values
  if #values ~= #self.block.params then
    return CMat.CMatCFragmentRejected({
      CMat.CMatCEmissionInvalidExit(
        self.block.id, "exit argument count does not match block parameters")
    })
  end
  for i = 1, #values do
    local expected = self.block.params[i].ty:code_to_c_backend_type()
    if values[i].ty ~= expected then
      return CMat.CMatCFragmentRejected({
        CMat.CMatCEmissionTypeMismatch(
          "exit argument", expected, values[i].ty)
      })
    end
  end
  return input.arguments:cmat_fragment_build_exit(input.assembly)
end
function CMat.CMatCExitArgumentCollectionReady:cmat_fragment_build_exit(context)
  local input = context.loop
  local exit = context.exit.entry
  local state = input.state
  local iteration = state.provenance.iteration
  local index_ty = state.index.ty
  if input.start.ty ~= index_ty then
    return CMat.CMatCFragmentRejected({
      CMat.CMatCEmissionTypeMismatch(
        "counted start", index_ty, input.start.ty)
    })
  end
  if input.trip.ty ~= index_ty then
    return CMat.CMatCFragmentRejected({
      CMat.CMatCEmissionTypeMismatch(
        "counted trip", index_ty, input.trip.ty)
    })
  end
  local test_cond = state:cmat_fragment_allocate("test", C.CBackendBool8)
  state = test_cond.state
  local advance_cond = state:cmat_fragment_allocate("advance", C.CBackendBool8)
  state = advance_cond.state
  local ordinal_add = state:cmat_fragment_add_helper(
    C.CBackendHelperIntBinary(Core.BinAdd, index_ty, C.CBackendIntWrap))
  state = ordinal_add.state
  local index_step = state:cmat_fragment_add_helper(
    C.CBackendHelperIntBinary(
      iteration.order:cmat_fragment_step_op(), index_ty, C.CBackendIntWrap))
  state = index_step.state
  local ns = state.request.namespace.prefix
  local entry_label = C.CBackendLabel(ns .. "_entry")
  local test_label = C.CBackendLabel(ns .. "_test")
  local body_label = C.CBackendLabel(ns .. "_body")
  local advance_label = C.CBackendLabel(ns .. "_advance")
  local step_label = C.CBackendLabel(ns .. "_step")
  local exit_args = {}
  for i = 1, #self.values do exit_args[i] = self.values[i].atom end
  local zero = C.CBackendAtomLiteral(index_ty, Core.LitInt("0"))
  local one = C.CBackendAtomLiteral(index_ty, Core.LitInt("1"))
  local magnitude = C.CBackendAtomLiteral(
    index_ty, Core.LitInt(tostring(iteration.step_magnitude)))
  local entry_stmts = copy(state.entry_stmts)
  entry_stmts[#entry_stmts + 1] = C.CBackendAssign(
    state.index.id, C.CBackendRAtom(input.start.atom))
  entry_stmts[#entry_stmts + 1] = C.CBackendAssign(
    state.ordinal.id, C.CBackendRAtom(zero))
  local test_stmts = { C.CBackendAssign(test_cond.c_local.id, C.CBackendRCompare(
    Core.CmpLt, index_ty, C.CBackendAtomLocal(state.ordinal.id), input.trip.atom)) }
  local advance_stmts = {
    C.CBackendHelperCall(state.ordinal.id, ordinal_add.helper,
      { C.CBackendAtomLocal(state.ordinal.id), one }),
    C.CBackendAssign(advance_cond.c_local.id, C.CBackendRCompare(
      Core.CmpLt, index_ty, C.CBackendAtomLocal(state.ordinal.id), input.trip.atom)),
  }
  local step_stmts = { C.CBackendHelperCall(state.index.id, index_step.helper,
    { C.CBackendAtomLocal(state.index.id), magnitude }) }
  local cursor_steps = state.request.address_plan:cmat_fragment_cursor_steps(index_ty)
  for i = 1, #cursor_steps.stmts do
    step_stmts[#step_stmts + 1] = cursor_steps.stmts[i]
  end
  local blocks = {
    C.CBackendBlock(entry_label, {}, entry_stmts, C.CBackendGoto(test_label, {})),
    C.CBackendBlock(test_label, {}, test_stmts, C.CBackendIfGoto(
      C.CBackendAtomLocal(test_cond.c_local.id), body_label, {}, exit.label, exit_args)),
  }
  for i = 1, #state.cfg.completed do blocks[#blocks + 1] = state.cfg.completed[i] end
  blocks[#blocks + 1] = C.CBackendBlock(
    state.cfg.open.label, state.cfg.open.params, state.cfg.open.stmts,
    C.CBackendGoto(advance_label, {}))
  blocks[#blocks + 1] = C.CBackendBlock(advance_label, {}, advance_stmts, C.CBackendIfGoto(
    C.CBackendAtomLocal(advance_cond.c_local.id), step_label, {}, exit.label, exit_args))
  blocks[#blocks + 1] = C.CBackendBlock(
    step_label, {}, step_stmts, C.CBackendGoto(body_label, {}))
  local alignments = {}
  for i = 1, #state.request.covered_blocks do
    local source = state.request.covered_blocks[i]
    if source == state.request.replacement_source then
      alignments[#alignments + 1] = CMat.CMatCBlockReplacementEntry(source, entry_label)
    else
      alignments[#alignments + 1] = CMat.CMatCBlockEliminated(source)
    end
  end
  local mappings = copy(input.body.value_mappings)
  mappings[#mappings + 1] = CMat.CMatCValueMapping(iteration.counter, state.index)
  return CMat.CMatCFragmentEmitted(CMat.CMatCFragment(
    entry_label, blocks, state.locals, state.helpers, alignments,
    mappings, input.body.control))
end


function Stencil.StencilProducerShape:cmat_fragment_shape(_materialization, _state)
  return CMat.CMatCFragmentRejected({
    CMat.CMatCEmissionUnsupportedProducer(
      self, "producer is outside exact scalar counted fragment emission")
  })
end
function Stencil.StencilKernelCountedDomain1D:cmat_fragment_window_plan(input)
  return CMat.CMatCFragmentRejected({
    CMat.CMatCEmissionUnsupportedProducer(
      input.shape, "window producer lacks exact window provenance")
  })
end
function Stencil.StencilKernelCountedWindow1D:cmat_fragment_window_plan(input)
  local iteration = input.materialization.provenance.iteration
  if self.source.domain ~= Flow.FlowDomainLoop(iteration.loop)
      or self.window.extent.before.elements < 0
      or self.window.extent.after.elements < 0
      or self.window.extent.before.elements ~=
        math.floor(self.window.extent.before.elements)
      or self.window.extent.after.elements ~=
        math.floor(self.window.extent.after.elements) then
    return CMat.CMatCFragmentRejected({
      CMat.CMatCEmissionUnsupportedProducer(
        input.shape, "window provenance has an invalid domain or extent")
    })
  end
  if self.window ~= input.shape.window then
    return CMat.CMatCFragmentRejected({
      CMat.CMatCEmissionUnsupportedProducer(
        input.shape, "window producer disagrees with provenance")
    })
  end
  if input.shape.index_ty ~= iteration.index_ty
      or input.shape.step ~= iteration.step_magnitude
      or input.shape.order ~= iteration.order
      or input.shape.stop_convention ~= iteration.stop_convention
      or input.shape.trip ~= iteration.trip then
    return CMat.CMatCFragmentRejected({
      CMat.CMatCEmissionUnsupportedProducer(
        input.shape, "window producer disagrees with exact counted iteration")
    })
  end
  local axis = Stencil.StencilProducerAxis(
    input.shape.index_ty, input.shape.start, input.shape.stop,
    input.shape.step, input.shape.order, Stencil.StencilIndexAnonymous)
  local start = input.shape.start:cmat_fragment_bound(input.state)
  return start:cmat_fragment_continue_trip(
    CMat.CMatCFragmentStartContinuation(
      CMat.CMatCFragmentWindowPlan(
        input.materialization, axis, input.shape.window), start))
end
function Stencil.StencilProduceCountedWindow1D:cmat_fragment_shape(materialization, state)
  return materialization.provenance.domain:cmat_fragment_window_plan(
    CMat.CMatCFragmentWindowPlanInput(materialization, state, self))
end
function Stencil.StencilProduceCountedRange1D:cmat_fragment_shape(materialization, state)
  local start = self.start:cmat_fragment_bound(state)
  return start:cmat_fragment_continue_trip(
    CMat.CMatCFragmentStartContinuation(
      CMat.CMatCFragmentCountedPlan(materialization), start))
end
function Stencil.StencilKernelResultVoid:cmat_expected_result_sink()
  return CMat.CMatCResultSinkNotRequired
end
function Stencil.StencilKernelResultReduction:cmat_expected_result_sink()
  return CMat.CMatCResultSinkNotRequired
end
function Stencil.StencilKernelResultAll:cmat_expected_result_sink()
  return CMat.CMatCResultSinkRequired(Stencil.StencilSinkDef(
    self.sink, Stencil.StencilSinkOpAll(self.src, self.pred)))
end
function Stencil.StencilKernelResultAny:cmat_expected_result_sink()
  return CMat.CMatCResultSinkRequired(Stencil.StencilSinkDef(
    self.sink, Stencil.StencilSinkOpAny(self.src, self.pred)))
end
function Stencil.StencilKernelResultAllCompare:cmat_expected_result_sink()
  return CMat.CMatCResultSinkRequired(Stencil.StencilSinkDef(
    self.sink, Stencil.StencilSinkOpAllCompare(self.left, self.right, self.cmp)))
end
function Stencil.StencilKernelResultFind:cmat_expected_result_sink()
  return CMat.CMatCResultSinkRequired(Stencil.StencilSinkDef(
    self.sink, Stencil.StencilSinkOpFind(
      self.src, self.pred, self.not_found_value)))
end
function CMat.CMatCResultSinkNotRequired:cmat_validate_result_sink(input)
  return input.collection
end
function CMat.CMatCResultSinkRequired:cmat_validate_result_sink(input)
  local count = 0
  for i = 1, #input.computation.sinks do
    if input.computation.sinks[i] == self.sink then count = count + 1 end
  end
  if count == 1 then return input.collection end
  local issues = copy(input.collection.issues)
  issues[#issues + 1] = CMat.CMatCEmissionInvalidKernel(
    "control result provenance lacks one exact computation sink")
  return CMat.CMatCMaterializationIssueCollection(issues)
end
function CMat.CMatCFragmentStateRejected:cmat_fragment_continue_address_plan(_materialization)
  return CMat.CMatCFragmentRejected(self.issues)
end
function CMat.CMatCFragmentStateReady:cmat_fragment_continue_address_plan(materialization)
  return materialization.kernel.computation.producer.shape:cmat_fragment_shape(
    materialization, self.state)
end
local function validate_result_stream(input, stream, value)
  local count = 0
  for i = 1, #input.streams.entries do
    local entry = input.streams.entries[i]
    if entry.definition.id == stream.stream and entry.source == value then
      count = count + 1
    end
  end
  if count == 1 then return input.collection end
  local issues = copy(input.collection.issues)
  issues[#issues + 1] = CMat.CMatCEmissionInvalidKernel(
    "kernel result source lacks one exact provenance stream relation")
  return CMat.CMatCMaterializationIssueCollection(issues)
end
function Stencil.StencilKernelResultVoid:cmat_validate_result_streams(input)
  return input.collection
end
function Stencil.StencilKernelResultReduction:cmat_validate_result_streams(input)
  return validate_result_stream(input, self.stream, self.accumulator)
end
function Stencil.StencilKernelResultAll:cmat_validate_result_streams(input)
  return validate_result_stream(input, self.src, self.src_value)
end
function Stencil.StencilKernelResultAny:cmat_validate_result_streams(input)
  return validate_result_stream(input, self.src, self.src_value)
end
function Stencil.StencilKernelResultFind:cmat_validate_result_streams(input)
  return validate_result_stream(input, self.src, self.src_value)
end
function Stencil.StencilKernelResultAllCompare:cmat_validate_result_streams(input)
  local collection = validate_result_stream(input, self.left, self.left_value)
  return validate_result_stream(
    CMat.CMatCMaterializationStreamValidationInput(input.streams, collection),
    self.right, self.right_value)
end

function C.CBackendType:cmat_fragment_size(_target) return 0 end
function C.CBackendScalar:cmat_fragment_size(target)
  return self.scalar:cmat_fragment_size(target)
end
function C.CBackendDataPtr:cmat_fragment_size(target)
  return target.pointer_bits / 8
end
function Core.Scalar:cmat_fragment_size(_target) return 0 end
function Core.ScalarBool:cmat_fragment_size(_target) return 1 end
function Core.ScalarI8:cmat_fragment_size(_target) return 1 end
function Core.ScalarU8:cmat_fragment_size(_target) return 1 end
function Core.ScalarI16:cmat_fragment_size(_target) return 2 end
function Core.ScalarU16:cmat_fragment_size(_target) return 2 end
function Core.ScalarI32:cmat_fragment_size(_target) return 4 end
function Core.ScalarU32:cmat_fragment_size(_target) return 4 end
function Core.ScalarF32:cmat_fragment_size(_target) return 4 end
function Core.ScalarI64:cmat_fragment_size(_target) return 8 end
function Core.ScalarU64:cmat_fragment_size(_target) return 8 end
function Core.ScalarF64:cmat_fragment_size(_target) return 8 end
function Core.ScalarIndex:cmat_fragment_size(target)
  return target.index_bits / 8
end
function Stencil.StencilAccessLayout:cmat_fragment_direct_stride() return 0 end
function Stencil.StencilAccessDirect:cmat_fragment_direct_stride()
  return self.base:cmat_fragment_direct_stride()
end
function Stencil.StencilAccessLayoutBase:cmat_fragment_direct_stride() return 0 end
function Stencil.StencilLayoutContiguous:cmat_fragment_direct_stride()
  return self.stride
end

function CMat.CMatMaterializedKernelFragment:cmat_validate_fragment_materialization(request)
  local computation = self.kernel.computation
  local collection = self.provenance.result:cmat_expected_result_sink()
:cmat_validate_result_sink(CMat.CMatCMaterializationSinkValidationInput(
    computation, CMat.CMatCMaterializationIssueCollection({})))
  collection = self.provenance.result:cmat_validate_result_streams(
    CMat.CMatCMaterializationStreamValidationInput(
      self.provenance.streams, collection))
  local issues = copy(collection.issues)
  local iteration = self.provenance.iteration
  local expected_loop = CMat.CMatLoopNest({
    CMat.CMatLoopAxis(
      Stencil.StencilAxisRef(1), CMat.CMatLocalId("i1"),
      iteration.index_ty, iteration.step_magnitude,
      iteration.order:cmat_loop_order()),
  }, computation.schedule:cmat_schedule_policy())
  if self.kernel.loop ~= expected_loop
      or self.kernel.schedule ~= computation.schedule then
    issues[#issues + 1] = CMat.CMatCEmissionInvalidKernel(
      "CMat loop or schedule plan disagrees with exact kernel provenance")
  end
  if #self.kernel.proofs ~= #computation.proofs then
    issues[#issues + 1] = CMat.CMatCEmissionInvalidKernel(
      "CMat proof plan disagrees with the computation")
  else
    for i = 1, #self.kernel.proofs do
      if self.kernel.proofs[i] ~= computation.proofs[i] then
        issues[#issues + 1] = CMat.CMatCEmissionInvalidKernel(
          "CMat proof plan disagrees with the computation")
      end
    end
  end
  for i = 1, #computation.streams do
    local count = 0
    for j = 1, #self.provenance.streams.entries do
      if self.provenance.streams.entries[j].definition == computation.streams[i] then
        count = count + 1
      end
    end
    if count ~= 1 then
      issues[#issues + 1] = CMat.CMatCEmissionInvalidKernel(
        "computation stream lacks one exact provenance relation")
    end
  end
  for i = 1, #self.provenance.streams.entries do
    local count = 0
    for j = 1, #computation.streams do
      if computation.streams[j] == self.provenance.streams.entries[i].definition then
        count = count + 1
      end
    end
    if count ~= 1 then
      issues[#issues + 1] = CMat.CMatCEmissionInvalidKernel(
        "provenance stream is absent or duplicated in the computation")
    end
  end
  for i = 1, #computation.accesses do
    local count = 0
    for j = 1, #self.provenance.accesses.entries do
      if self.provenance.accesses.entries[j].access == computation.accesses[i] then
        count = count + 1
      end
    end
    if count ~= 1 then
      issues[#issues + 1] = CMat.CMatCEmissionInvalidKernel(
        "computation access lacks one exact lane provenance relation")
    end
  end
  for i = 1, #self.provenance.accesses.entries do
    local count = 0
    for j = 1, #computation.accesses do
      if computation.accesses[j] == self.provenance.accesses.entries[i].access then
        count = count + 1
      end
    end
    if count ~= 1 then
      issues[#issues + 1] = CMat.CMatCEmissionInvalidKernel(
        "lane provenance access is absent or duplicated in the computation")
    end
  end
  for i = 1, #computation.streams do
    local expected = computation.streams[i]:cmat_stream_materialization()
    local count = 0
    for j = 1, #self.kernel.streams do
      if self.kernel.streams[j] == expected then count = count + 1 end
    end
    if count ~= 1 then
      issues[#issues + 1] = CMat.CMatCEmissionInvalidKernel(
        "CMat stream plan lacks one exact computation stream")
    end
  end
  for i = 1, #self.kernel.streams do
    local count = 0
    for j = 1, #computation.streams do
      if self.kernel.streams[i] == computation.streams[j]:cmat_stream_materialization() then
        count = count + 1
      end
    end
    if count ~= 1 then
      issues[#issues + 1] = CMat.CMatCEmissionInvalidKernel(
        "CMat stream plan entry has no exact computation stream")
    end
  end
  for i = 1, #computation.sinks do
    local expected = computation.sinks[i]:cmat_sink_materialization()
    local count = 0
    for j = 1, #self.kernel.sinks do
      if self.kernel.sinks[j] == expected then count = count + 1 end
    end
    if count ~= 1 then
      issues[#issues + 1] = CMat.CMatCEmissionInvalidKernel(
        "CMat sink plan lacks one exact computation sink")
    end
  end
  for i = 1, #self.kernel.sinks do
    local count = 0
    for j = 1, #computation.sinks do
      if self.kernel.sinks[i] == computation.sinks[j]:cmat_sink_materialization() then
        count = count + 1
      end
    end
    if count ~= 1 then
      issues[#issues + 1] = CMat.CMatCEmissionInvalidKernel(
        "CMat sink plan entry has no exact computation sink")
    end
  end
  for i = 1, #computation.accesses do
    local expected = computation.accesses[i]:cmat_canonical_binding(
      computation:cmat_access_binding_input(computation.accesses[i]))
    local count = 0
    for j = 1, #self.kernel.accesses do
      if self.kernel.accesses[j] == expected then
        count = count + 1
      end
    end
    if count ~= 1 then
      issues[#issues + 1] = CMat.CMatCEmissionInvalidKernel(
        "CMat access plan lacks one exact computation access")
    end
  end
  for i = 1, #self.kernel.accesses do
    local count = 0
    for j = 1, #computation.accesses do
      local expected = computation.accesses[j]:cmat_canonical_binding(
        computation:cmat_access_binding_input(computation.accesses[j]))
      if expected == self.kernel.accesses[i] then
        count = count + 1
      end
    end
    if count ~= 1 then
      issues[#issues + 1] = CMat.CMatCEmissionInvalidKernel(
        "CMat access plan entry has no exact computation access")
    end
  end
  for i = 1, #request.accesses.entries do
    local binding = request.accesses.entries[i]
    local matches = 0
    for j = 1, #self.provenance.accesses.entries do
      local provenance = self.provenance.accesses.entries[j]
      local expected_ty = provenance.access.ty:code_to_c_backend_type()
      local expected_size = expected_ty:cmat_fragment_size(request.target)
      local expected_stride = provenance.access.layout:cmat_fragment_direct_stride()
      local contract_matches = 0
      for k = 1, #provenance.lane.backend_info do
        local info = provenance.lane.backend_info[k]
        if info.access == binding.mem_access
            and info.alignment == binding.alignment
            and info.bounds == binding.bounds
            and info.trap == binding.trap
            and info.movement == binding.movement then
          contract_matches = contract_matches + 1
        end
      end
      if provenance.lane.id == binding.lane
          and provenance.access.name == binding.access.name
          and binding.elem_size == expected_size
          and binding.stride == expected_stride
          and expected_size > 0 and expected_stride > 0
          and contract_matches == 1 then
        for k = 1, #provenance.lane.accesses do
          if provenance.lane.accesses[k] == binding.mem_access then
            matches = matches + 1
          end
        end
      end
    end
    if matches ~= 1 then
      issues[#issues + 1] = CMat.CMatCEmissionInvalidKernel(
        "fragment access disagrees with lane and memory provenance")
    end
  end
  if #issues ~= 0 then
    return CMat.CMatCFragmentMaterializationRejected(issues)
  end
  return CMat.CMatCFragmentMaterializationValid(self)
end
function CMat.CMatMaterializedKernelFragment:cmat_emit_fragment(request)
  return self:cmat_validate_fragment_materialization(request)
:cmat_emit_valid_fragment(request)
end
function CMat.CMatCFragmentMaterializationRejected:cmat_emit_valid_fragment(_request)
  return CMat.CMatCFragmentRejected(self.issues)
end
function CMat.CMatCFragmentMaterializationValid:cmat_emit_valid_fragment(request)
  local materialization = self.materialization
  local index_ty = materialization.provenance.iteration.index_ty:code_to_c_backend_type()
  local index_id = C.CBackendLocalId(request.namespace.prefix .. "_index")
  local ordinal_id = C.CBackendLocalId(request.namespace.prefix .. "_ordinal")
  local index = C.CBackendLocal(index_id, C.CBackendName(index_id.text), index_ty)
  local ordinal = C.CBackendLocal(ordinal_id, C.CBackendName(ordinal_id.text), index_ty)
  local state = CMat.CMatCFragmentState(
    request, materialization.provenance, index, ordinal,
    request.values:cmat_fragment_values(), CMat.CMatCFragmentStreamProjection({}),
    CMat.CMatCFragmentNoWindow, { index, ordinal }, {},
    CMat.CMatCFragmentCFG({}, CMat.CMatCOpenBlock(
      C.CBackendLabel(request.namespace.prefix .. "_body"), {}, {}), 1),
    {}, 1):cmat_fragment_seed_counter()
  return request.address_plan:cmat_fragment_install(state)
:cmat_fragment_continue_address_plan(materialization)
end
function CMat.CMatRejectedKernelFragment:cmat_emit_fragment(_request)
  local issues = {}
  for i = 1, #self.issues do
    issues[i] = CMat.CMatCEmissionMaterializationIssue(self.issues[i])
  end
  return CMat.CMatCFragmentRejected(issues)
end
function CMat.CMatMaterializedFused:cmat_emit_fragment(_request)
  return CMat.CMatCFragmentRejected({ CMat.CMatCEmissionInvalidKernel(
    "authored standalone materialization has no canonical kernel provenance") })
end
function CMat.CMatRejectedComputation:cmat_emit_fragment(_request)
  local issues = {}
  for i = 1, #self.issues do
    issues[i] = CMat.CMatCEmissionMaterializationIssue(self.issues[i])
  end
  return CMat.CMatCFragmentRejected(issues)
end
local function has_block(blocks, id)
  for i = 1, #blocks do if blocks[i].id == id then return true end end
  return false
end

local function has_id(ids, id)
  for i = 1, #ids do if ids[i] == id then return true end end
  return false
end
local function collides_with_generated_label(text, prefix)
  return text == prefix .. "_entry"
      or text == prefix .. "_test"
      or text == prefix .. "_body"
      or text == prefix .. "_advance"
      or text == prefix .. "_step"
      or text:sub(1, #prefix + 8) == prefix .. "_window_"
end

function CMat.CMatCFragmentInput:cmat_fragment_validate()
  local issues = {}
  if not has_id(self.covered_blocks, self.replacement_source) then
    issues[#issues + 1] = CMat.CMatCEmissionInvalidCoverage(
      self.replacement_source, "replacement source is not covered")
  end
  for i = 1, #self.covered_blocks do
    local block = self.covered_blocks[i]
    if not has_block(self.code_func.blocks, block) then
      issues[#issues + 1] = CMat.CMatCEmissionInvalidCoverage(
        block, "covered block is absent from the owning function")
    end
    for j = i + 1, #self.covered_blocks do
      if self.covered_blocks[j] == block then
        issues[#issues + 1] = CMat.CMatCEmissionInvalidCoverage(
          block, "covered block appears more than once")
      end
    end
  end
  for i = 1, #self.exits.entries do
    local destination = self.exits.entries[i].destination
    if not has_block(self.code_func.blocks, destination) then
      issues[#issues + 1] = CMat.CMatCEmissionInvalidExit(
        destination, "exit destination is absent from the owning function")
    elseif has_id(self.covered_blocks, destination) then
      issues[#issues + 1] = CMat.CMatCEmissionInvalidExit(
        destination, "exit destination is inside the replaced cover")
    end
  end
  local generated_prefix = self.namespace.prefix
  for i = 1, #self.reserved_labels do
    if collides_with_generated_label(
        self.reserved_labels[i].text, generated_prefix) then
      issues[#issues + 1] = CMat.CMatCEmissionInvalidKernel(
        "fragment namespace collides with a reserved function label")
    end
  end
  for i = 1, #self.exits.entries do
    local label = self.exits.entries[i].label.text
    if collides_with_generated_label(label, generated_prefix) then
      issues[#issues + 1] = CMat.CMatCEmissionInvalidKernel(
        "fragment namespace collides with an exit label")
    end
  end
  if #issues ~= 0 then return CMat.CMatCFragmentInputRejected(issues) end
  return CMat.CMatCFragmentInputValid(self)
end
function CMat.CMatCFragmentInputValid:emit_cmat_fragment()
  return self.input.materialization:cmat_emit_fragment(self.input)
end
function CMat.CMatCFragmentInputRejected:emit_cmat_fragment()
  return CMat.CMatCFragmentRejected(self.issues)
end
function CMat.CMatCFragmentInput:emit_cmat_fragment()
  return self:cmat_fragment_validate():emit_cmat_fragment()
end

return CMat
