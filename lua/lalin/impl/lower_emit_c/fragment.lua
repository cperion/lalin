-- Canonical kernel CMat fragment emission for exact scalar counted loops.
require("lalin.schema_v2")
require("lalin.impl.lower_emit_c.code_to_c")

local Code = require("lalin.schema_v2.code")
local Core = require("lalin.schema_v2.core")
local Value = require("lalin.schema_v2.value")
local Mem = require("lalin.schema_v2.mem")
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

function CMat.CMatCFragmentState:cmat_fragment_allocate(stem, ty)
  local id = C.CBackendLocalId(prefix(self) .. "_" .. stem .. tostring(self.next_local))
  local c_local = C.CBackendLocal(id, C.CBackendName(id.text), ty)
  return CMat.CMatCFragmentLocalAllocation(CMat.CMatCFragmentState(
    self.request, self.provenance, self.index, self.ordinal,
    self.values, self.streams, append(self.locals, c_local),
    self.entry_stmts, self.body_stmts, self.helpers, self.next_local + 1), c_local)
end

function CMat.CMatCFragmentState:cmat_fragment_add_entry(stmt)
  return CMat.CMatCFragmentState(
    self.request, self.provenance, self.index, self.ordinal,
    self.values, self.streams, self.locals, append(self.entry_stmts, stmt),
    self.body_stmts, self.helpers, self.next_local)
end

function CMat.CMatCFragmentState:cmat_fragment_add_body(stmt)
  return CMat.CMatCFragmentState(
    self.request, self.provenance, self.index, self.ordinal,
    self.values, self.streams, self.locals, self.entry_stmts,
    append(self.body_stmts, stmt), self.helpers, self.next_local)
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
    self.values, self.streams, self.locals, self.entry_stmts,
    self.body_stmts, append(self.helpers, use), self.next_local), id)
end

function CMat.CMatCFragmentState:cmat_fragment_bind_stream(source, stream, atom, ty)
  return CMat.CMatCFragmentState(
    self.request, self.provenance, self.index, self.ordinal,
    CMat.CMatCFragmentValueProjection(append(self.values.entries,
      CMat.CMatCFragmentValueEntry(source, atom, ty))),
    CMat.CMatCFragmentStreamProjection(append(self.streams.entries,
      CMat.CMatCFragmentStreamEntry(stream, source, atom, ty))),
    self.locals, self.entry_stmts, self.body_stmts, self.helpers, self.next_local)
end

function CMat.CMatCFragmentState:cmat_fragment_seed_counter()
  local iteration = self.provenance.iteration
  local ty = iteration.index_ty:code_to_c_backend_type()
  return CMat.CMatCFragmentState(
    self.request, self.provenance, self.index, self.ordinal,
    CMat.CMatCFragmentValueProjection(append(self.values.entries,
      CMat.CMatCFragmentValueEntry(
        iteration.counter, C.CBackendAtomLocal(self.index.id), ty))),
    self.streams, self.locals, self.entry_stmts, self.body_stmts,
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
function Stencil.StencilArithmeticInferred:cmat_fragment_reduction_spec(_input)
  return CMat.CMatCBinaryRejected("reduction arithmetic mode is not explicit")
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
  return index:cmat_fragment_load_access(
    CMat.CMatCFragmentLoadInput(index, entry, self.access))
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
function CMat.CMatCFragmentAccessDirect:cmat_fragment_base_atom()
  return C.CBackendAtomLocal(self.base.id)
end
function CMat.CMatCFragmentAccessAddressProjected:cmat_fragment_base_atom()
  return C.CBackendAtomLocal(self.base.id)
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
function CMat.CMatCFragmentAccessBindingFound:cmat_fragment_access_place(input)
  if self.entry.elem_size <= 0 or self.entry.stride <= 0
      or self.entry.stride % self.entry.elem_size ~= 0 then
    return CMat.CMatCFragmentPlaceRejected({
      CMat.CMatCEmissionInvalidKernel(
        "fragment access stride must be a positive element-size multiple")
    })
  end
  if input.index_ty ~= input.state.index.ty then
    return CMat.CMatCFragmentPlaceRejected({
      CMat.CMatCEmissionTypeMismatch(
        "fragment access index", input.state.index.ty, input.index_ty)
    })
  end
  local state = input.state
  local index = input.index
  local factor = self.entry.stride / self.entry.elem_size
  if factor ~= 1 then
    local allocation = state:cmat_fragment_allocate("stride", input.index_ty)
    local helper = allocation.state:cmat_fragment_add_helper(
      C.CBackendHelperIntBinary(
        Core.BinMul, input.index_ty, C.CBackendIntWrap))
    state = helper.state:cmat_fragment_add_body(C.CBackendHelperCall(
      allocation.c_local.id, helper.helper, { index,
        C.CBackendAtomLiteral(input.index_ty, Core.LitInt(tostring(factor))) }))
    index = C.CBackendAtomLocal(allocation.c_local.id)
  end
  local place = self.entry.alignment:cmat_fragment_place(
    CMat.CMatCFragmentPlaceInput(
      self.entry.source:cmat_fragment_base_atom(), index,
      input.ty, self.entry.elem_size))
  return CMat.CMatCFragmentPlaceEmitted(state, place)
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
    input.index.state, input.index.atom, input.index.ty, ty))
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
function Stencil.StencilSinkOp:cmat_fragment_emit_sink(_state, sink)
  return CMat.CMatCFragmentSinkRejected({
    CMat.CMatCEmissionUnsupportedSink(
      sink, "sink operation is outside scalar counted fragment emission")
  })
end
function Stencil.StencilSinkOpStore:cmat_fragment_emit_sink(state, sink)
  return state.streams:cmat_fragment_lookup(self.value)
:cmat_fragment_store_stream(
  CMat.CMatCFragmentStoreRequest(state, sink, self.dst))
end
function CMat.CMatCFragmentStreamMissing:cmat_fragment_store_stream(_input)
  return CMat.CMatCFragmentSinkRejected({ CMat.CMatCEmissionMissingStream(self.stream) })
end
function CMat.CMatCFragmentStreamFound:cmat_fragment_store_stream(request)
  local input = CMat.CMatCFragmentStoreInput(
    request.state, request.sink, request.dst, self.entry)
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
    input.state, C.CBackendAtomLocal(input.state.index.id),
    input.state.index.ty, input.stream.ty))
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
function Kernel.KernelResult:cmat_fragment_finish_fold(input)
  return CMat.CMatCFragmentSinkRejected({
    CMat.CMatCEmissionInvalidKernel("fold sink has no reduction kernel result")
  })
end
function Kernel.KernelResultReduction:cmat_fragment_finish_fold(input)
  if self.reduction.op ~= input.operation.reducer.reduction then
    return CMat.CMatCFragmentSinkRejected({
      CMat.CMatCEmissionInvalidKernel("fold reducer does not match kernel result")
    })
  end
  local atom = C.CBackendAtomLocal(input.accumulator.id)
  return CMat.CMatCFragmentSinkEmitted(
    input.state, CMat.CMatCControlValue(atom, input.ty), {
      CMat.CMatCValueMapping(self.reduction.accumulator, input.accumulator),
    })
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
function CMat.CMatCFragmentBoundEmitted:cmat_fragment_continue_trip(continuation)
  local trip = continuation.materialization.provenance.iteration.trip
:cmat_fragment_trip(self.state)
  return trip:cmat_fragment_continue_body(CMat.CMatCFragmentTripContinuation(
    continuation.materialization, self, trip))
end
function CMat.CMatCFragmentBoundRejected:cmat_fragment_continue_body(_continuation)
  return CMat.CMatCFragmentRejected(self.issues)
end
function CMat.CMatCFragmentBoundEmitted:cmat_fragment_continue_body(continuation)
  local materialization = continuation.materialization
  local step = CMat.CMatCFragmentStateReady(self.state)
  for i = 1, #materialization.provenance.streams.entries do
    step = step:cmat_fragment_apply_stream(materialization.provenance.streams.entries[i])
  end
  if #materialization.kernel.computation.sinks ~= 1 then
    return CMat.CMatCFragmentRejected({
      CMat.CMatCEmissionInvalidKernel("scalar counted fragment requires exactly one sink")
    })
  end
  local body = CMat.CMatCFragmentBodyInput(
    materialization, self.state, continuation.start, self)
  return step:cmat_fragment_apply_sink(materialization.kernel.computation.sinks[1])
:cmat_fragment_finish_body(body)
end

function CMat.CMatCFragmentSinkRejected:cmat_fragment_finish_body(_body)
  return CMat.CMatCFragmentRejected(self.issues)
end
function CMat.CMatCFragmentSinkEmitted:cmat_fragment_finish_body(body)
  local loop = CMat.CMatCCountedLoopAssemblyInput(
    self.state, body.start, body.trip, self)
  return self.state.request.exits:cmat_fragment_lookup(CMat.CMatCExitNormal)
:cmat_fragment_finish_counted(loop)
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
function CMat.CMatCControlBranch:cmat_fragment_control_atom()
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
      CMat.CMatCExitArgumentInput(input.state, input.sink.control))
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
:cmat_fragment_block_lookup(context.exit.entry.source)
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
  local blocks = {
    C.CBackendBlock(entry_label, {}, entry_stmts, C.CBackendGoto(test_label, {})),
    C.CBackendBlock(test_label, {}, test_stmts, C.CBackendIfGoto(
      C.CBackendAtomLocal(test_cond.c_local.id), body_label, {}, exit.label, exit_args)),
    C.CBackendBlock(body_label, {}, state.body_stmts, C.CBackendGoto(advance_label, {})),
    C.CBackendBlock(advance_label, {}, advance_stmts, C.CBackendIfGoto(
      C.CBackendAtomLocal(advance_cond.c_local.id), step_label, {}, exit.label, exit_args)),
    C.CBackendBlock(step_label, {}, step_stmts, C.CBackendGoto(body_label, {})),
  }
  local alignments = {}
  for i = 1, #state.request.covered_blocks do
    local source = state.request.covered_blocks[i]
    if source == state.request.replacement_source then
      alignments[#alignments + 1] = CMat.CMatCBlockReplacementEntry(source, entry_label)
    else
      alignments[#alignments + 1] = CMat.CMatCBlockEliminated(source)
    end
  end
  local mappings = copy(input.sink.value_mappings)
  mappings[#mappings + 1] = CMat.CMatCValueMapping(iteration.counter, state.index)
  return CMat.CMatCFragmentEmitted(CMat.CMatCFragment(
    entry_label, blocks, state.locals, state.helpers, alignments,
    mappings, input.sink.control))
end


function Stencil.StencilProducerShape:cmat_fragment_shape(_materialization, _state)
  return CMat.CMatCFragmentRejected({
    CMat.CMatCEmissionUnsupportedProducer(
      self, "producer is outside exact scalar counted fragment emission")
  })
end
function Stencil.StencilProduceCountedRange1D:cmat_fragment_shape(materialization, state)
  local start = self.start:cmat_fragment_bound(state)
  return start:cmat_fragment_continue_trip(
    CMat.CMatCFragmentStartContinuation(materialization, start))
end

function CMat.CMatMaterializedKernelFragment:cmat_emit_fragment(request)
  local index_ty = self.provenance.iteration.index_ty:code_to_c_backend_type()
  local index_id = C.CBackendLocalId(request.namespace.prefix .. "_index")
  local ordinal_id = C.CBackendLocalId(request.namespace.prefix .. "_ordinal")
  local index = C.CBackendLocal(index_id, C.CBackendName(index_id.text), index_ty)
  local ordinal = C.CBackendLocal(ordinal_id, C.CBackendName(ordinal_id.text), index_ty)
  local state = CMat.CMatCFragmentState(
    request, self.provenance, index, ordinal,
    request.values:cmat_fragment_values(), CMat.CMatCFragmentStreamProjection({}),
    { index, ordinal }, {}, {}, {}, 1):cmat_fragment_seed_counter()
  return self.kernel.computation.producer.shape:cmat_fragment_shape(self, state)
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
    local source = self.exits.entries[i].source
    if not has_block(self.code_func.blocks, source) then
      issues[#issues + 1] = CMat.CMatCEmissionInvalidExit(
        source, "exit source is absent from the owning function")
    elseif has_id(self.covered_blocks, source) then
      issues[#issues + 1] = CMat.CMatCEmissionInvalidExit(
        source, "exit source is inside the replaced cover")
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
