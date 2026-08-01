-- Typed CMat-to-CBackend emission for the closed scalar range-1D scope.
require("lalin.schema_v2")
require("lalin.impl.lower_emit_c.code_to_c")
require("lalin.impl.cemit_emit")

local T = require("lalin.schema_v2")
local CMat = require("lalin.schema_v2.c_materialize")
local Stencil = require("lalin.schema_v2.stencil")
local Value = require("lalin.schema_v2.value")
local Code = require("lalin.schema_v2.code")
local Core = require("lalin.schema_v2.core")
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

function CMat.CMatCFunctionState:cmat_c_allocate(stem, ty)
  local id = C.CBackendLocalId(stem .. tostring(self.next_local))
  local local_value = C.CBackendLocal(id, C.CBackendName(id.text), ty)
  return CMat.CMatCLocalAllocation(CMat.CMatCFunctionState(
    self.index, self.index_ty, self.accesses, self.stream_defs, self.sink_defs,
    self.values, append(self.locals, local_value), self.entry_stmts, self.body_stmts,
    self.helpers, self.next_local + 1), local_value)
end

function CMat.CMatCFunctionState:cmat_c_add_entry(stmt)
  return CMat.CMatCFunctionState(
    self.index, self.index_ty, self.accesses, self.stream_defs, self.sink_defs,
    self.values, self.locals, append(self.entry_stmts, stmt), self.body_stmts,
    self.helpers, self.next_local)
end

function CMat.CMatCFunctionState:cmat_c_add_body(stmt)
  return CMat.CMatCFunctionState(
    self.index, self.index_ty, self.accesses, self.stream_defs, self.sink_defs,
    self.values, self.locals, self.entry_stmts, append(self.body_stmts, stmt),
    self.helpers, self.next_local)
end

function CMat.CMatCFunctionState:cmat_c_add_value(entry)
  return CMat.CMatCFunctionState(
    self.index, self.index_ty, self.accesses, self.stream_defs, self.sink_defs,
    CMat.CMatCStreamValueProjection(append(self.values.entries, entry)),
    self.locals, self.entry_stmts, self.body_stmts, self.helpers, self.next_local)
end

function CMat.CMatCFunctionState:cmat_c_add_helper(spec)
  local id = spec:c_helper_id()
  for i = 1, #self.helpers do
    if self.helpers[i].id == id then return CMat.CMatCHelperAllocation(self, id) end
  end
  return CMat.CMatCHelperAllocation(CMat.CMatCFunctionState(
    self.index, self.index_ty, self.accesses, self.stream_defs, self.sink_defs,
    self.values, self.locals, self.entry_stmts, self.body_stmts,
    append(self.helpers, C.CBackendHelperUse(id, spec)), self.next_local), id)
end

function CMat.CMatCAccessCProjection:cmat_c_lookup(access)
  for i = 1, #self.entries do
    if self.entries[i].access == access then return CMat.CMatCAccessCFound(self.entries[i]) end
  end
  return CMat.CMatCAccessCMissing(access)
end

function CMat.CMatCStreamDefProjection:cmat_c_lookup(stream)
  for i = 1, #self.entries do
    if self.entries[i].stream == stream then return CMat.CMatCStreamDefFound(self.entries[i]) end
  end
  return CMat.CMatCStreamDefMissing(stream)
end

function CMat.CMatCSinkDefProjection:cmat_c_lookup(sink)
  for i = 1, #self.entries do
    if self.entries[i].sink == sink then return CMat.CMatCSinkDefFound(self.entries[i]) end
  end
  return CMat.CMatCSinkDefMissing(sink)
end

function CMat.CMatCStreamValueProjection:cmat_c_lookup_stream(stream)
  for i = 1, #self.entries do
    if self.entries[i].stream == stream then return CMat.CMatCStreamValueFound(self.entries[i]) end
  end
  return CMat.CMatCStreamValueMissing(stream.stream.text)
end

function CMat.CMatCStreamValueProjection:cmat_c_lookup_name(name)
  for i = #self.entries, 1, -1 do
    if self.entries[i].name == name then return CMat.CMatCStreamValueFound(self.entries[i]) end
  end
  return CMat.CMatCStreamValueMissing(name)
end

function Stencil.StencilAccessLayout:cmat_c_access_binding(binding)
  return CMat.CMatCAccessCBindingRejected(
    CMat.CMatCEmissionUnsupportedAccess(binding.source, "access layout is outside scalar contiguous C emission"))
end

function Stencil.StencilAccessDirect:cmat_c_access_binding(binding)
  return self.base:cmat_c_access_binding(binding)
end

function Stencil.StencilAccessDescribed:cmat_c_access_binding(binding)
  return CMat.CMatCAccessCBindingRejected(
    CMat.CMatCEmissionUnsupportedAccess(binding.source, "descriptor-backed access is outside scalar contiguous C emission"))
end

function CMat.CMatRestrictEligible:cmat_c_restrict_ptr() return true end
function CMat.CMatRestrictIneligible:cmat_c_restrict_ptr() return false end
function CMat.CMatConstEligible:cmat_c_const_ptr() return true end
function CMat.CMatConstIneligible:cmat_c_const_ptr() return false end

function CMat.CMatAccessBinding:cmat_c_access_ptr_type(elem)
  return C.CBackendQualifiedDataPtr(elem,
    self.const_capability:cmat_c_const_ptr(),
    self.restrict_capability:cmat_c_restrict_ptr(), false)
end

function Stencil.StencilLayoutContiguous:cmat_c_access_binding(binding)
  local elem = binding.ty:code_to_c_backend_type()
  local ptr = binding:cmat_c_access_ptr_type(elem)
  local id = C.CBackendLocalId(binding.local_id.text)
  return CMat.CMatCAccessCBindingReady(
    CMat.CMatCAccessCEntry(binding.access, binding, C.CBackendLocal(id, C.CBackendName(id.text), ptr), self.stride))
end

function CMat.CMatAccessBinding:cmat_c_access_binding()
  return self.layout:cmat_c_access_binding(self)
end

function CMat.CMatCAccessCBindingReady:cmat_c_collect(collection)
  return collection:cmat_c_add_entry(self.entry)
end

function CMat.CMatCAccessCBindingRejected:cmat_c_collect(collection)
  return collection:cmat_c_add_issue(self.issue)
end

function CMat.CMatCAccessCCollectionReady:cmat_c_add_entry(entry)
  return CMat.CMatCAccessCCollectionReady(append(self.entries, entry))
end

function CMat.CMatCAccessCCollectionReady:cmat_c_add_issue(issue)
  return CMat.CMatCAccessCCollectionRejected({ issue })
end

function CMat.CMatCAccessCCollectionRejected:cmat_c_add_entry(entry) return self end
function CMat.CMatCAccessCCollectionRejected:cmat_c_add_issue(issue)
  return CMat.CMatCAccessCCollectionRejected(append(self.issues, issue))
end

function Code.CodeConst:cmat_c_atom(value_expr)
  return CMat.CMatCAtomRejected(
    CMat.CMatCEmissionUnsupportedValue(value_expr, "value is not a scalar literal"))
end

function Code.CodeConstLiteral:cmat_c_atom(value_expr)
  return CMat.CMatCAtomEmitted(
    C.CBackendAtomLiteral(self.ty:code_to_c_backend_type(), self.literal),
    self.ty:code_to_c_backend_type())
end

function Value.ValueExpr:cmat_c_atom()
  return CMat.CMatCAtomRejected(
    CMat.CMatCEmissionUnsupportedValue(self, "only scalar literal values are supported by CMat C emission"))
end

function Value.ValueExprConst:cmat_c_atom() return self.const:cmat_c_atom(self) end

function Stencil.StencilBinaryOp:cmat_c_binary_selection(ty)
  return CMat.CMatCBinaryRejected("point binary operation is outside the closed C emission scope")
end
function Stencil.StencilBinaryAdd:cmat_c_binary_selection(ty) return CMat.CMatCBinarySelected(C.CBackendHelperIntBinary(Core.BinAdd, ty, C.CBackendIntWrap)) end
function Stencil.StencilBinarySub:cmat_c_binary_selection(ty) return CMat.CMatCBinarySelected(C.CBackendHelperIntBinary(Core.BinSub, ty, C.CBackendIntWrap)) end
function Stencil.StencilBinaryMul:cmat_c_binary_selection(ty) return CMat.CMatCBinarySelected(C.CBackendHelperIntBinary(Core.BinMul, ty, C.CBackendIntWrap)) end
function Stencil.StencilBinaryDiv:cmat_c_binary_selection(ty) return CMat.CMatCBinarySelected(C.CBackendHelperDivRem(Core.BinDiv, ty, C.CBackendDivTrapOnZeroOrOverflow)) end
function Stencil.StencilBinaryMod:cmat_c_binary_selection(ty) return CMat.CMatCBinarySelected(C.CBackendHelperDivRem(Core.BinRem, ty, C.CBackendDivTrapOnZeroOrOverflow)) end
function Stencil.StencilBinaryAnd:cmat_c_binary_selection(ty) return CMat.CMatCBinarySelected(C.CBackendHelperIntBinary(Core.BinBitAnd, ty, C.CBackendIntWrap)) end
function Stencil.StencilBinaryOr:cmat_c_binary_selection(ty) return CMat.CMatCBinarySelected(C.CBackendHelperIntBinary(Core.BinBitOr, ty, C.CBackendIntWrap)) end
function Stencil.StencilBinaryXor:cmat_c_binary_selection(ty) return CMat.CMatCBinarySelected(C.CBackendHelperIntBinary(Core.BinBitXor, ty, C.CBackendIntWrap)) end
function Stencil.StencilBinaryShl:cmat_c_binary_selection(ty) return CMat.CMatCBinarySelected(C.CBackendHelperShift(Core.BinShl, ty, C.CBackendShiftMaskCount)) end
function Stencil.StencilBinaryLShr:cmat_c_binary_selection(ty) return CMat.CMatCBinarySelected(C.CBackendHelperShift(Core.BinLShr, ty, C.CBackendShiftMaskCount)) end
function Stencil.StencilBinaryAShr:cmat_c_binary_selection(ty) return CMat.CMatCBinarySelected(C.CBackendHelperShift(Core.BinAShr, ty, C.CBackendShiftMaskCount)) end

function Value.ReductionOp:cmat_c_binary_selection(ty)
  return CMat.CMatCBinaryRejected("reduction operation is outside the closed domain-fold scope")
end
function Value.ReductionAdd:cmat_c_binary_selection(ty) return CMat.CMatCBinarySelected(C.CBackendHelperIntBinary(Core.BinAdd, ty, C.CBackendIntWrap)) end
function Value.ReductionMul:cmat_c_binary_selection(ty) return CMat.CMatCBinarySelected(C.CBackendHelperIntBinary(Core.BinMul, ty, C.CBackendIntWrap)) end
function Value.ReductionAnd:cmat_c_binary_selection(ty) return CMat.CMatCBinarySelected(C.CBackendHelperIntBinary(Core.BinBitAnd, ty, C.CBackendIntWrap)) end
function Value.ReductionOr:cmat_c_binary_selection(ty) return CMat.CMatCBinarySelected(C.CBackendHelperIntBinary(Core.BinBitOr, ty, C.CBackendIntWrap)) end
function Value.ReductionXor:cmat_c_binary_selection(ty) return CMat.CMatCBinarySelected(C.CBackendHelperIntBinary(Core.BinBitXor, ty, C.CBackendIntWrap)) end

function Stencil.StencilPointExpr:cmat_c_emit_point(state)
  return CMat.CMatCPointRejected({
    CMat.CMatCEmissionUnsupportedPoint(self, "point expression is outside the closed C emission scope")
  })
end

function Stencil.StencilPointInput:cmat_c_emit_point(state)
  return state.values:cmat_c_lookup_name(self.access.name):cmat_c_point_value(state, self)
end

function CMat.CMatCStreamValueFound:cmat_c_point_value(state, expr)
  return CMat.CMatCPointEmitted(state, C.CBackendAtomLocal(self.entry.local_id), self.entry.ty)
end

function CMat.CMatCStreamValueMissing:cmat_c_point_value(state, expr)
  return CMat.CMatCPointRejected({
    CMat.CMatCEmissionUnsupportedPoint(expr, "point input has no emitted stream binding: " .. self.name)
  })
end

function Stencil.StencilPointConst:cmat_c_emit_point(state)
  return self.value:cmat_c_atom():cmat_c_point_atom(state)
end

function CMat.CMatCAtomEmitted:cmat_c_point_atom(state)
  return CMat.CMatCPointEmitted(state, self.atom, self.ty)
end

function CMat.CMatCAtomRejected:cmat_c_point_atom(state)
  return CMat.CMatCPointRejected({ self.issue })
end

function Stencil.StencilPointBinary:cmat_c_emit_point(state)
  return self.left:cmat_c_emit_point(state):cmat_c_emit_binary_right(self)
end

function CMat.CMatCPointRejected:cmat_c_emit_binary_right(expr) return self end
function CMat.CMatCPointEmitted:cmat_c_emit_binary_right(expr)
  return expr.right:cmat_c_emit_point(self.state):cmat_c_finish_binary(self, expr)
end

function CMat.CMatCPointRejected:cmat_c_finish_binary(left, expr) return self end
function CMat.CMatCPointEmitted:cmat_c_finish_binary(left, expr)
  return expr.result:cmat_c_finish_binary_type(left, self, expr)
end
function Stencil.StencilPointResultInferred:cmat_c_finish_binary_type(left, right, expr)
  return CMat.CMatCPointRejected({
    CMat.CMatCEmissionUnsupportedPoint(expr, "point binary expression requires an explicit result type")
  })
end
function Stencil.StencilPointResultTyped:cmat_c_finish_binary_type(left, right, expr)
  local ty = self.ty:code_to_c_backend_type()
  return expr.op:cmat_c_binary_selection(ty):cmat_c_apply_binary(left, right, expr, ty)
end

function CMat.CMatCBinaryRejected:cmat_c_apply_binary(left, right, expr, ty)
  return CMat.CMatCPointRejected({ CMat.CMatCEmissionUnsupportedPoint(expr, self.reason) })
end

function CMat.CMatCBinarySelected:cmat_c_apply_binary(left, right, expr, ty)
  local allocation = right.state:cmat_c_allocate("point", ty)
  local helper_allocation = allocation.state:cmat_c_add_helper(self.spec)
  local next_state = helper_allocation.state:cmat_c_add_body(C.CBackendHelperCall(
    allocation.c_local.id, helper_allocation.helper, { left.atom, right.atom }))
  return CMat.CMatCPointEmitted(next_state, C.CBackendAtomLocal(allocation.c_local.id), ty)
end

function CMat.CMatCStateRejected:cmat_c_apply_stream(materialization, defs) return self end
function CMat.CMatCStateReady:cmat_c_apply_stream(materialization, defs)
  return materialization:cmat_c_emit_stream(self.state, defs)
end

function CMat.CMatStreamInline:cmat_c_emit_stream(state, defs)
  return defs:cmat_c_lookup(self.stream):cmat_c_emit_stream_def(state)
end
function CMat.CMatStreamLocal:cmat_c_emit_stream(state, defs)
  return defs:cmat_c_lookup(self.stream):cmat_c_emit_stream_def(state)
end

function CMat.CMatCStreamDefMissing:cmat_c_emit_stream_def(state)
  return CMat.CMatCStateRejected({ CMat.CMatCEmissionInvalidKernel(
    "materialized stream has no definition: " .. self.stream.stream.text) })
end
function CMat.CMatCStreamDefFound:cmat_c_emit_stream_def(state)
  return self.entry.def.op:cmat_c_emit_stream_op(state, self.entry.def)
end

function Stencil.StencilStreamOp:cmat_c_emit_stream_op(state, def)
  return CMat.CMatCStateRejected({
    CMat.CMatCEmissionUnsupportedStream(def, "stream operation is outside the closed C emission scope")
  })
end

function Stencil.StencilIndexProducer:cmat_c_emit_stream_access(state, def, access)
  return state.accesses:cmat_c_lookup(access.access):cmat_c_emit_access_stream(state, def)
end
function Stencil.StencilIndexExplicit:cmat_c_emit_stream_access(state, def, access)
  return CMat.CMatCStateRejected({
    CMat.CMatCEmissionUnsupportedStream(def, "explicit stream indexing is outside contiguous point access")
  })
end
function Stencil.StencilStreamAccess:cmat_c_emit_stream_op(state, def)
  return self.index:cmat_c_emit_stream_access(state, def, self)
end

function CMat.CMatCAccessCMissing:cmat_c_emit_access_stream(state, def)
  return CMat.CMatCStateRejected({ CMat.CMatCEmissionInvalidKernel(
    "stream references missing access: " .. self.access.name) })
end
function CMat.CMatCAccessCFound:cmat_c_emit_access_stream(state, def)
  local ty = self.entry.binding.ty:code_to_c_backend_type()
  local allocation = state:cmat_c_allocate("stream", ty)
  local place = C.CBackendPlacePtrIndex(
    C.CBackendAtomLocal(self.entry.param.id), C.CBackendAtomLocal(state.index),
    ty, self.entry.stride, nil)
  local next_state = allocation.state:cmat_c_add_body(C.CBackendPlaceLoad(allocation.c_local.id, place))
  next_state = next_state:cmat_c_add_value(CMat.CMatCStreamValueEntry(
    def.id.text, Stencil.StencilStreamRef(def.id), allocation.c_local.id, ty))
  return CMat.CMatCStateReady(next_state)
end

function Stencil.StencilStreamConst:cmat_c_emit_stream_op(state, def)
  return self.value:cmat_c_atom():cmat_c_emit_const_stream(state, def)
end
function CMat.CMatCAtomRejected:cmat_c_emit_const_stream(state, def)
  return CMat.CMatCStateRejected({ self.issue })
end
function CMat.CMatCAtomEmitted:cmat_c_emit_const_stream(state, def)
  local allocation = state:cmat_c_allocate("stream", self.ty)
  local next_state = allocation.state:cmat_c_add_body(
    C.CBackendAssign(allocation.c_local.id, C.CBackendRAtom(self.atom)))
  next_state = next_state:cmat_c_add_value(CMat.CMatCStreamValueEntry(
    def.id.text, Stencil.StencilStreamRef(def.id), allocation.c_local.id, self.ty))
  return CMat.CMatCStateReady(next_state)
end

function Stencil.StencilStreamMap:cmat_c_emit_stream_op(state, def)
  local step = CMat.CMatCStateReady(state)
  for i = 1, #self.inputs do
    step = step:cmat_c_alias_stream(self.inputs[i])
  end
  return step:cmat_c_emit_map_expr(def, self.expr)
end

function CMat.CMatCStateRejected:cmat_c_alias_stream(param) return self end
function CMat.CMatCStateReady:cmat_c_alias_stream(param)
  return self.state.values:cmat_c_lookup_stream(param.stream):cmat_c_add_alias(self.state, param)
end
function CMat.CMatCStreamValueMissing:cmat_c_add_alias(state, param)
  return CMat.CMatCStateRejected({ CMat.CMatCEmissionInvalidKernel(
    "map parameter references missing stream: " .. param.stream.stream.text) })
end
function CMat.CMatCStreamValueFound:cmat_c_add_alias(state, param)
  return CMat.CMatCStateReady(state:cmat_c_add_value(CMat.CMatCStreamValueEntry(
    param.name, param.stream, self.entry.local_id, self.entry.ty)))
end

function CMat.CMatCStateRejected:cmat_c_emit_map_expr(def, expr) return self end
function CMat.CMatCStateReady:cmat_c_emit_map_expr(def, expr)
  return expr:cmat_c_emit_point(self.state):cmat_c_bind_map_stream(def)
end
function CMat.CMatCPointRejected:cmat_c_bind_map_stream(def)
  return CMat.CMatCStateRejected(self.issues)
end
function CMat.CMatCPointEmitted:cmat_c_bind_map_stream(def)
  local allocation = self.state:cmat_c_allocate("stream", self.ty)
  local next_state = allocation.state:cmat_c_add_body(
    C.CBackendAssign(allocation.c_local.id, C.CBackendRAtom(self.atom)))
  next_state = next_state:cmat_c_add_value(CMat.CMatCStreamValueEntry(
    def.id.text, Stencil.StencilStreamRef(def.id), allocation.c_local.id, self.ty))
  return CMat.CMatCStateReady(next_state)
end

function CMat.CMatCStateRejected:cmat_c_apply_sink(materialization, defs)
  return CMat.CMatCSinkRejected(self.issues)
end
function CMat.CMatCStateReady:cmat_c_apply_sink(materialization, defs)
  return materialization:cmat_c_emit_sink(self.state, defs)
end

function CMat.CMatSinkInline:cmat_c_emit_sink(state, defs)
  return defs:cmat_c_lookup(self.sink):cmat_c_emit_sink_def(state)
end
function CMat.CMatSinkStoreResult:cmat_c_emit_sink(state, defs)
  return defs:cmat_c_lookup(self.sink):cmat_c_emit_sink_def(state)
end
function CMat.CMatSinkValueResult:cmat_c_emit_sink(state, defs)
  return defs:cmat_c_lookup(self.sink):cmat_c_emit_sink_def(state)
end
function CMat.CMatSinkControlResult:cmat_c_emit_sink(state, defs)
  return CMat.CMatCSinkRejected({ CMat.CMatCEmissionInvalidKernel(
    "control-result sink is outside store/domain-fold emission") })
end

function CMat.CMatCSinkDefMissing:cmat_c_emit_sink_def(state)
  return CMat.CMatCSinkRejected({ CMat.CMatCEmissionInvalidKernel(
    "materialized sink has no definition: " .. self.sink.sink.text) })
end
function CMat.CMatCSinkDefFound:cmat_c_emit_sink_def(state)
  return self.entry.def.op:cmat_c_emit_sink_op(state, self.entry.def)
end

function Stencil.StencilSinkOp:cmat_c_emit_sink_op(state, def)
  return CMat.CMatCSinkRejected({
    CMat.CMatCEmissionUnsupportedSink(def, "sink operation is outside store/domain-fold C emission")
  })
end

function Stencil.StencilSinkOpStore:cmat_c_emit_sink_op(state, def)
  return state.values:cmat_c_lookup_stream(self.value):cmat_c_store_value(state, def, self.dst)
end
function CMat.CMatCStreamValueMissing:cmat_c_store_value(state, def, dst)
  return CMat.CMatCSinkRejected({ CMat.CMatCEmissionInvalidKernel(
    "store references missing stream: " .. self.name) })
end
function CMat.CMatCStreamValueFound:cmat_c_store_value(state, def, dst)
  return state.accesses:cmat_c_lookup(dst):cmat_c_store_access(state, def, self.entry)
end
function CMat.CMatCAccessCMissing:cmat_c_store_access(state, def, value_entry)
  return CMat.CMatCSinkRejected({ CMat.CMatCEmissionInvalidKernel(
    "store references missing access: " .. self.access.name) })
end
function CMat.CMatCAccessCFound:cmat_c_store_access(state, def, value_entry)
  local ty = self.entry.binding.ty:code_to_c_backend_type()
  local place = C.CBackendPlacePtrIndex(
    C.CBackendAtomLocal(self.entry.param.id), C.CBackendAtomLocal(state.index),
    ty, self.entry.stride, nil)
  return CMat.CMatCSinkVoidEmitted(state:cmat_c_add_body(
    C.CBackendPlaceStore(place, C.CBackendAtomLocal(value_entry.local_id))))
end

function Stencil.StencilReduceInitExternal:cmat_c_emit_fold(state, def, sink, value_entry)
  return CMat.CMatCSinkRejected({
    CMat.CMatCEmissionUnsupportedSink(def, "external fold initialization is outside the closed ABI")
  })
end
function Stencil.StencilReduceInitIdentity:cmat_c_emit_fold(state, def, sink, value_entry)
  return sink.reducer.identity:cmat_c_atom():cmat_c_initialize_fold(state, def, sink, value_entry)
end
function Stencil.StencilSinkOpFold:cmat_c_emit_sink_op(state, def)
  return state.values:cmat_c_lookup_stream(self.value):cmat_c_fold_value(state, def, self)
end
function CMat.CMatCStreamValueMissing:cmat_c_fold_value(state, def, sink)
  return CMat.CMatCSinkRejected({ CMat.CMatCEmissionInvalidKernel(
    "fold references missing stream: " .. self.name) })
end
function CMat.CMatCStreamValueFound:cmat_c_fold_value(state, def, sink)
  if sink.dst ~= nil then
    return CMat.CMatCSinkRejected({
      CMat.CMatCEmissionUnsupportedSink(def, "domain fold with destination access is outside the closed scope")
    })
  end
  return sink.init:cmat_c_emit_fold(state, def, sink, self.entry)
end
function CMat.CMatCAtomRejected:cmat_c_initialize_fold(state, def, sink, value_entry)
  return CMat.CMatCSinkRejected({ self.issue })
end
function CMat.CMatCAtomEmitted:cmat_c_initialize_fold(state, def, sink, value_entry)
  local result_ty = sink.result_ty:code_to_c_backend_type()
  local allocation = state:cmat_c_allocate("fold", result_ty)
  local next_state = allocation.state:cmat_c_add_entry(
    C.CBackendAssign(allocation.c_local.id, C.CBackendRAtom(self.atom)))
  return sink.reducer.reduction:cmat_c_binary_selection(result_ty):cmat_c_update_fold(
    next_state, def, value_entry, allocation.c_local, result_ty)
end
function CMat.CMatCBinaryRejected:cmat_c_update_fold(state, def, value_entry, accumulator, ty)
  return CMat.CMatCSinkRejected({ CMat.CMatCEmissionUnsupportedSink(def, self.reason) })
end
function CMat.CMatCBinarySelected:cmat_c_update_fold(state, def, value_entry, accumulator, ty)
  local helper_allocation = state:cmat_c_add_helper(self.spec)
  local next_state = helper_allocation.state:cmat_c_add_body(C.CBackendHelperCall(
    accumulator.id, helper_allocation.helper, { C.CBackendAtomLocal(accumulator.id), C.CBackendAtomLocal(value_entry.local_id) }))
  return CMat.CMatCSinkValueEmitted(next_state, C.CBackendAtomLocal(accumulator.id), ty)
end

function Stencil.StencilProducerForward:cmat_c_loop_direction()
  return CMat.CMatCLoopDirectionPlan(Core.CmpLt, Core.BinAdd)
end
function Stencil.StencilProducerBackward:cmat_c_loop_direction()
  return CMat.CMatCLoopDirectionPlan(Core.CmpGt, Core.BinSub)
end

local function def_projections(computation)
  local streams, sinks = {}, {}
  for i = 1, #computation.streams do
    local def = computation.streams[i]
    streams[i] = CMat.CMatCStreamDefEntry(Stencil.StencilStreamRef(def.id), def)
  end
  for i = 1, #computation.sinks do
    local def = computation.sinks[i]
    sinks[i] = CMat.CMatCSinkDefEntry(Stencil.StencilSinkRef(def.id), def)
  end
  return CMat.CMatCDefProjections(
    CMat.CMatCStreamDefProjection(streams), CMat.CMatCSinkDefProjection(sinks))
end

function CMat.CMatCAccessCCollectionRejected:cmat_c_emit_kernel(kernel, input, shape, start_atom, stop_atom)
  return CMat.CMatCRejected(self.issues)
end
function CMat.CMatCAccessCCollectionReady:cmat_c_emit_kernel(kernel, input, shape, start_atom, stop_atom)
  if #kernel.sinks ~= 1 then
    return CMat.CMatCRejected({ CMat.CMatCEmissionInvalidKernel(
      "closed CMat C emission requires exactly one sink") })
  end
  local access_projection = CMat.CMatCAccessCProjection(self.entries)
  local defs = def_projections(kernel.computation)
  local index_ty = shape.index_ty:code_to_c_backend_type()
  local index = C.CBackendLocalId(kernel.loop.axes[1].index.text)
  local index_local = C.CBackendLocal(index, C.CBackendName(index.text), index_ty)
  local state = CMat.CMatCFunctionState(
    index, index_ty, access_projection, defs.streams, defs.sinks,
    CMat.CMatCStreamValueProjection({}), { index_local },
    { C.CBackendAssign(index, C.CBackendRAtom(start_atom)) }, {}, {}, 1)
  local step = CMat.CMatCStateReady(state)
  for i = 1, #kernel.streams do
    step = step:cmat_c_apply_stream(kernel.streams[i], defs.streams)
  end
  local sink_result = step:cmat_c_apply_sink(kernel.sinks[1], defs.sinks)
  return sink_result:cmat_c_finish_function(kernel, input, shape, stop_atom)
end

function CMat.CMatCSinkRejected:cmat_c_finish_function(kernel, input, shape, stop_atom)
  return CMat.CMatCRejected(self.issues)
end

local function finish_function(sink_result, kernel, input, shape, stop_atom, return_term, result_ty)
  local state = sink_result.state
  local direction = shape.order:cmat_c_loop_direction()
  local cond_alloc = state:cmat_c_allocate("cond", C.CBackendBool8)
  state = cond_alloc.state
  local step_spec = C.CBackendHelperIntBinary(direction.step_op, state.index_ty, C.CBackendIntWrap)
  local helper_allocation = state:cmat_c_add_helper(step_spec)
  state = helper_allocation.state:cmat_c_add_body(C.CBackendHelperCall(
    state.index, helper_allocation.helper, { C.CBackendAtomLocal(state.index),
      C.CBackendAtomLiteral(state.index_ty, Core.LitInt(tostring(shape.step))) }))
  local entry_label = C.CBackendLabel("entry")
  local test_label = C.CBackendLabel("loop_test")
  local body_label = C.CBackendLabel("loop_body")
  local exit_label = C.CBackendLabel("loop_exit")
  local test_stmt = C.CBackendAssign(cond_alloc.c_local.id, C.CBackendRCompare(
    direction.compare, state.index_ty, C.CBackendAtomLocal(state.index), stop_atom))
  local blocks = {
    C.CBackendBlock(entry_label, {}, state.entry_stmts, C.CBackendGoto(test_label, {})),
    C.CBackendBlock(test_label, {}, { test_stmt }, C.CBackendIfGoto(
      C.CBackendAtomLocal(cond_alloc.c_local.id), body_label, {}, exit_label, {})),
    C.CBackendBlock(body_label, {}, state.body_stmts, C.CBackendGoto(test_label, {})),
    C.CBackendBlock(exit_label, {}, {}, return_term),
  }
  local params, param_types = {}, {}
  for i = 1, #state.accesses.entries do
    params[i] = state.accesses.entries[i].param
    param_types[i] = params[i].ty
  end
  local sig_id = C.CBackendFuncSigId(input.symbol .. "_sig")
  local sig = C.CBackendFuncSig(sig_id, param_types, result_ty)
  local func = C.CBackendFunc(C.CBackendName(input.symbol), input.symbol, Core.VisibilityExport,
    sig_id, params, state.locals, C.CBackendBodyBlocks(entry_label, blocks))
  local unit = C.CBackendUnit(input.module_name, input.target, { sig }, {}, {}, {}, state.helpers, { func })
  local report = require("lalin.emit_c_validate")(T).validate(unit)
  if #report.issues ~= 0 then
    return CMat.CMatCRejected({ CMat.CMatCEmissionValidationRejected(report.issues) })
  end
  return CMat.CMatCEmitted(unit)
end

function CMat.CMatCSinkVoidEmitted:cmat_c_finish_function(kernel, input, shape, stop_atom)
  return finish_function(self, kernel, input, shape, stop_atom, C.CBackendReturnVoid, C.CBackendVoid)
end
function CMat.CMatCSinkValueEmitted:cmat_c_finish_function(kernel, input, shape, stop_atom)
  return finish_function(self, kernel, input, shape, stop_atom, C.CBackendReturn(self.atom), self.ty)
end

function CMat.CMatCAtomRejected:cmat_c_emit_range_stop(kernel, input, shape, start_atom)
  return CMat.CMatCRejected({ self.issue })
end
function CMat.CMatCAtomEmitted:cmat_c_emit_range_stop(kernel, input, shape, start_atom)
  local collection = CMat.CMatCAccessCCollectionReady({})
  for i = 1, #kernel.accesses do
    collection = kernel.accesses[i]:cmat_c_access_binding():cmat_c_collect(collection)
  end
  return collection:cmat_c_emit_kernel(kernel, input, shape, start_atom, self.atom)
end

function CMat.CMatCAtomRejected:cmat_c_emit_range(kernel, input, shape)
  return CMat.CMatCRejected({ self.issue })
end
function CMat.CMatCAtomEmitted:cmat_c_emit_range(kernel, input, shape)
  return shape.stop:cmat_c_emit_range_stop_bound(kernel, input, shape, self.atom)
end
function Stencil.StencilBoundDynamic:cmat_c_emit_range_stop_bound(kernel, input, shape, start_atom)
  return CMat.CMatCRejected({ CMat.CMatCEmissionUnsupportedProducer(
    shape, "range-1D C emission requires an explicit stop value") })
end
function Stencil.StencilBoundValue:cmat_c_emit_range_stop_bound(kernel, input, shape, start_atom)
  return self.value:cmat_c_atom():cmat_c_emit_range_stop(kernel, input, shape, start_atom)
end

function Stencil.StencilProducerShape:cmat_c_emit_kernel(kernel, input)
  return CMat.CMatCRejected({
    CMat.CMatCEmissionUnsupportedProducer(self, "producer is outside scalar range-1D C emission")
  })
end
function Stencil.StencilBoundDynamic:cmat_c_emit_range_start_bound(kernel, input, shape)
  return CMat.CMatCRejected({ CMat.CMatCEmissionUnsupportedProducer(
    shape, "range-1D C emission requires an explicit start value") })
end
function Stencil.StencilBoundValue:cmat_c_emit_range_start_bound(kernel, input, shape)
  return self.value:cmat_c_atom():cmat_c_emit_range(kernel, input, shape)
end
function Stencil.StencilProduceRange1D:cmat_c_emit_kernel(kernel, input)
  if self.step <= 0 then
    return CMat.CMatCRejected({ CMat.CMatCEmissionUnsupportedProducer(
      self, "range-1D C emission requires a positive step") })
  end
  return self.start:cmat_c_emit_range_start_bound(kernel, input, self)
end

function CMat.CMatMaterializedFused:cmat_emit_c(input)
  if #self.kernel.loop.axes ~= 1 then
    return CMat.CMatCRejected({ CMat.CMatCEmissionInvalidKernel(
      "closed CMat C emission requires one loop axis") })
  end
  return self.kernel.computation.producer.shape:cmat_c_emit_kernel(self.kernel, input)
end
function CMat.CMatRejectedComputation:cmat_emit_c(input)
  local issues = {}
  for i = 1, #self.issues do
    issues[i] = CMat.CMatCEmissionMaterializationIssue(self.issues[i])
  end
  return CMat.CMatCRejected(issues)
end

return CMat
