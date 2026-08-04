-- Typed closure capture collection and layout methods.
local T = require("lalin.schema_v2")
local C = require("lalin.schema_v2.core")
local Ty = require("lalin.schema_v2.type")
local B = require("lalin.schema_v2.bind")
local Sem = require("lalin.schema_v2.sem")
local Tr = require("lalin.schema_v2.tree")
local asdl = require("lalin.asdl")
local TypeSizeAlign = require("lalin.type_size_align")

local function copy(xs)
  local out = {}
  for i = 1, #xs do out[i] = xs[i] end
  return out
end

local function collected(input) return Sem.ClosureCollected(input) end

function Sem.ClosureScopeStack:closure_push(frame)
  local frames = copy(self.frames)
  frames[#frames + 1] = frame
  return Sem.ClosureScopeStack(frames)
end

function Sem.ClosureScopeStack:closure_pop()
  local frames = {}
  for i = 1, #self.frames - 1 do frames[i] = self.frames[i] end
  return Sem.ClosureScopeStack(frames)
end

function Sem.ClosureScopeStack:closure_bind(binding)
  local frames = copy(self.frames)
  local top = frames[#frames] or Sem.ClosureScopeFrame({})
  local bindings = copy(top.bindings)
  bindings[#bindings + 1] = Sem.ClosureBinding(binding)
  frames[#frames > 0 and #frames or 1] = Sem.ClosureScopeFrame(bindings)
  return Sem.ClosureScopeStack(frames)
end

function Sem.ClosureScopeStack:closure_lookup_name(name)
  for i = #self.frames, 1, -1 do
    local bindings = self.frames[i].bindings
    for j = #bindings, 1, -1 do
      if bindings[j].binding.name == name then return Sem.ClosureLookupFound(bindings[j]) end
    end
  end
  return Sem.ClosureLookupMissing
end

function Sem.ClosureScopeStack:closure_lookup_capture(name)
  local local_frame = self.frames[#self.frames]
  if local_frame then
    for j = #local_frame.bindings, 1, -1 do
      if local_frame.bindings[j].binding.name == name then return Sem.ClosureLookupMissing end
    end
  end
  for i = #self.frames - 1, 1, -1 do
    local bindings = self.frames[i].bindings
    for j = #bindings, 1, -1 do
      if bindings[j].binding.name == name then return Sem.ClosureLookupFound(bindings[j]) end
    end
  end
  return Sem.ClosureLookupMissing
end

function Sem.ClosureCaptureSet:closure_add(binding)
  for i = 1, #self.candidates do
    if self.candidates[i].binding.binding == binding.binding then return self end
  end
  local candidates = copy(self.candidates)
  candidates[#candidates + 1] = Sem.ClosureCaptureCandidate(binding)
  return Sem.ClosureCaptureSet(candidates)
end

function Sem.ClosureCollected:closure_continue(node) return node:closure_collect(self.input) end
function Sem.ClosureCollectTransitioned:closure_continue(node) return node:closure_collect(self.input) end
function Sem.ClosureCollectUnsupported:closure_continue() return self end
function Sem.ClosureCollected:closure_input() return self.input end
function Sem.ClosureCollectTransitioned:closure_input() return self.input end
function Sem.ClosureCollectUnsupported:closure_input() return self.input end

local function collect_many(nodes, input)
  local result = collected(input)
  for i = 1, #nodes do result = result:closure_continue(nodes[i]) end
  return result
end

local function collect_exprs(nodes, input) return collect_many(nodes, input) end
local function collect_stmts(nodes, input) return collect_many(nodes, input) end

local function isolated_input(input, captures)
  return Sem.ClosureCollectInput(input.scopes, captures)
end
function Sem.ClosureCollected:closure_collect_isolated(nodes)
  local branch = collect_many(nodes, self.input)
  return branch:closure_restore_collect_scopes(self.input.scopes)
end
function Sem.ClosureCollectTransitioned:closure_collect_isolated(nodes)
  local branch = collect_many(nodes, self.input)
  return branch:closure_restore_collect_scopes(self.input.scopes)
end
function Sem.ClosureCollectUnsupported:closure_collect_isolated() return self end
function Sem.ClosureCollected:closure_collect_scoped(nodes,scopes) local branch=collect_many(nodes,Sem.ClosureCollectInput(scopes,self.input.captures)); return branch:closure_restore_collect_scopes(self.input.scopes) end
function Sem.ClosureCollectTransitioned:closure_collect_scoped(nodes,scopes) local branch=collect_many(nodes,Sem.ClosureCollectInput(scopes,self.input.captures)); return branch:closure_restore_collect_scopes(self.input.scopes) end
function Sem.ClosureCollectUnsupported:closure_collect_scoped() return self end
function Sem.ClosureCollected:closure_collect_default(stmts,expr) local outer=self.input.scopes; local result=collect_stmts(stmts,self.input):closure_continue(expr); return result:closure_restore_collect_scopes(outer) end
function Sem.ClosureCollectTransitioned:closure_collect_default(stmts,expr) local outer=self.input.scopes; local result=collect_stmts(stmts,self.input):closure_continue(expr); return result:closure_restore_collect_scopes(outer) end
function Sem.ClosureCollectUnsupported:closure_collect_default() return self end
function Sem.ClosureCollected:closure_restore_collect_scopes(scopes) return collected(isolated_input(Sem.ClosureCollectInput(scopes, self.input.captures), self.input.captures)) end
function Sem.ClosureCollectTransitioned:closure_restore_collect_scopes(scopes) return collected(Sem.ClosureCollectInput(scopes, self.input.captures)) end
function Sem.ClosureCollectUnsupported:closure_restore_collect_scopes() return self end

function B.ValueRefName:closure_lookup(input) return input.scopes:closure_lookup_capture(self.name) end
function B.ValueRefPath:closure_lookup() return Sem.ClosureLookupMissing end
function B.ValueRefBinding:closure_lookup() return Sem.ClosureLookupMissing end
function Sem.ClosureLookupMissing:closure_collect_reference(input) return collected(input) end
function Sem.ClosureLookupFound:closure_collect_reference(input)
  return collected(Sem.ClosureCollectInput(input.scopes, input.captures:closure_add(self.binding)))
end

function Tr.ExprLit:closure_collect(input) return collected(input) end
function Tr.ExprRef:closure_collect(input) return self.ref:closure_lookup(input):closure_collect_reference(input) end
function Tr.ExprDot:closure_collect(input) return self.base:closure_collect(input) end
function Tr.ExprUnary:closure_collect(input) return self.value:closure_collect(input) end
function Tr.ExprBinary:closure_collect(input) return self.lhs:closure_collect(input):closure_continue(self.rhs) end
function Tr.ExprCompare:closure_collect(input) return self.lhs:closure_collect(input):closure_continue(self.rhs) end
function Tr.ExprLogic:closure_collect(input) return self.lhs:closure_collect(input):closure_continue(self.rhs) end
function Tr.ExprCast:closure_collect(input) return self.value:closure_collect(input) end
function Tr.ExprMachineCast:closure_collect(input) return self.value:closure_collect(input) end
function Tr.ExprIntrinsic:closure_collect(input) return collect_exprs(self.args, input) end
function Tr.ExprAddrOf:closure_collect(input) return self.place:closure_collect(input) end
function Tr.ExprDeref:closure_collect(input) return self.value:closure_collect(input) end
function Tr.ExprCall:closure_collect(input) return self.callee:closure_collect(input):closure_continue_many(self.args) end
function Tr.ExprLen:closure_collect(input) return self.value:closure_collect(input) end
function Tr.ExprField:closure_collect(input) return self.base:closure_collect(input) end
function Tr.ExprIndex:closure_collect(input) return self.base:closure_collect(input):closure_continue(self.index) end
function Tr.ExprAgg:closure_collect(input) return collect_many(self.fields, input) end
function Tr.ExprArray:closure_collect(input) return collect_exprs(self.elems, input) end
function Tr.ExprIf:closure_collect(input) return self.cond:closure_collect(input):closure_continue(self.then_expr):closure_continue(self.else_expr) end
function Tr.ExprSelect:closure_collect(input) return self.cond:closure_collect(input):closure_continue(self.then_expr):closure_continue(self.else_expr) end
function Tr.ExprSwitch:closure_collect(input)
  local result = self.value:closure_collect(input)
  for i = 1, #self.arms do result = result:closure_collect_isolated({ self.arms[i] }) end
  for i = 1, #self.variant_arms do result = result:closure_collect_isolated({ self.variant_arms[i] }) end
  return result:closure_collect_default(self.default_body,self.default_expr)
end
function Tr.ExprControl:closure_collect(input) return self.region:closure_collect(input) end
function Tr.ExprDomainControl:closure_collect(input) return self.region:closure_collect(input) end
function Tr.ExprBlock:closure_collect(input) local result=collect_stmts(self.stmts,input):closure_continue(self.result); return result:closure_restore_collect_scopes(input.scopes) end
function Tr.ExprClosure:closure_collect(input) return Sem.ClosureCollectUnsupported(input, "nested ExprClosure capture collection is unsupported") end
function Tr.ExprView:closure_collect(input) return self.view:closure_collect(input) end
function Tr.ExprLoad:closure_collect(input) return self.addr:closure_collect(input) end
function Tr.ExprAtomicLoad:closure_collect(input) return self.addr:closure_collect(input) end
function Tr.ExprAtomicRmw:closure_collect(input) return self.addr:closure_collect(input):closure_continue(self.value) end
function Tr.ExprAtomicCas:closure_collect(input) return self.addr:closure_collect(input):closure_continue(self.expected):closure_continue(self.replacement) end
function Tr.ExprCtor:closure_collect(input) return collect_exprs(self.args, input) end
function Tr.ExprNull:closure_collect(input) return collected(input) end
function Tr.ExprSizeOf:closure_collect(input) return collected(input) end
function Tr.ExprAlignOf:closure_collect(input) return collected(input) end
function Tr.ExprIsNull:closure_collect(input) return self.value:closure_collect(input) end

function Sem.ClosureCollectResult:closure_continue_many(nodes)
  local result = self
  for i = 1, #nodes do result = result:closure_continue(nodes[i]) end
  return result
end

function Tr.FieldInit:closure_collect(input) return self.value:closure_collect(input) end
function Tr.SwitchKeyInt:closure_collect(input) return collected(input) end
function Tr.SwitchKeyBool:closure_collect(input) return collected(input) end
function Tr.SwitchKeyName:closure_collect(input) return collected(input) end
function Tr.SwitchKeyExpr:closure_collect(input) return self.expr:closure_collect(input) end
local function collect_bind_values(scopes,values,site)
  local bound=scopes
  for i=1,#values do local value=values[i]; bound=bound:closure_bind(B.Binding(C.Id("closure:"..site..":"..value.name..":"..tostring(i)),value.name,value.ty,B.BindingRoleLocalValue)) end
  return bound
end
function Tr.SwitchStmtArm:closure_collect(input) return self.key:closure_collect(input):closure_continue_many(self.body) end
function Tr.SwitchExprArm:closure_collect(input) return self.key:closure_collect(input):closure_continue_many(self.body):closure_continue(self.result) end
function Tr.SwitchVariantStmtArm:closure_collect(input) return collect_stmts(self.body,Sem.ClosureCollectInput(collect_bind_values(input.scopes,self.binds,"switch-stmt"),input.captures)) end
function Tr.SwitchVariantExprArm:closure_collect(input) return collect_stmts(self.body,Sem.ClosureCollectInput(collect_bind_values(input.scopes,self.binds,"switch-expr"),input.captures)):closure_continue(self.result) end

function Tr.PlaceRef:closure_collect(input) return self.ref:closure_lookup(input):closure_collect_reference(input) end
function Tr.PlaceDeref:closure_collect(input) return self.base:closure_collect(input) end
function Tr.PlaceDot:closure_collect(input) return self.base:closure_collect(input) end
function Tr.PlaceField:closure_collect(input) return self.base:closure_collect(input) end
function Tr.PlaceIndex:closure_collect(input) return self.base:closure_collect(input):closure_continue(self.index) end

function Tr.IndexBaseExpr:closure_collect(input) return self.base:closure_collect(input) end
function Tr.IndexBasePlace:closure_collect(input) return self.base:closure_collect(input) end
function Tr.IndexBaseView:closure_collect(input) return self.view:closure_collect(input) end

function Tr.ViewFromExpr:closure_collect(input) return self.base:closure_collect(input) end
function Tr.ViewContiguous:closure_collect(input) return self.data:closure_collect(input):closure_continue(self.len) end
function Tr.ViewStrided:closure_collect(input) return self.data:closure_collect(input):closure_continue(self.len):closure_continue(self.stride) end
function Tr.ViewRestrided:closure_collect(input) return self.base:closure_collect(input):closure_continue(self.stride) end
function Tr.ViewWindow:closure_collect(input) return self.base:closure_collect(input):closure_continue(self.start):closure_continue(self.len) end
function Tr.ViewRowBase:closure_collect(input) return self.base:closure_collect(input):closure_continue(self.row_offset) end
function Tr.ViewInterleaved:closure_collect(input) return self.data:closure_collect(input):closure_continue(self.len):closure_continue(self.stride):closure_continue(self.lane) end
function Tr.ViewInterleavedView:closure_collect(input) return self.base:closure_collect(input):closure_continue(self.stride):closure_continue(self.lane) end

local function bind_after_init(stmt, input)
  local init_result = stmt.init:closure_collect(input)
  local next_input = init_result:closure_input()
  local scopes = next_input.scopes:closure_bind(stmt.binding)
  local transitioned = Sem.ClosureCollectInput(scopes, next_input.captures)
  return Sem.ClosureCollectTransitioned(transitioned, Sem.ClosureScopeTransition(scopes))
end

function Tr.StmtLet:closure_collect(input) return bind_after_init(self, input) end
function Tr.StmtVar:closure_collect(input) return bind_after_init(self, input) end
function Tr.StmtSet:closure_collect(input) return self.place:closure_collect(input):closure_continue(self.value) end
function Tr.StmtAtomicStore:closure_collect(input) return self.addr:closure_collect(input):closure_continue(self.value) end
function Tr.StmtAtomicFence:closure_collect(input) return collected(input) end
function Tr.StmtExpr:closure_collect(input) return self.expr:closure_collect(input) end
function Tr.StmtAssert:closure_collect(input) return self.cond:closure_collect(input) end
function Tr.StmtIf:closure_collect(input)
  local result = self.cond:closure_collect(input)
  result = result:closure_collect_isolated(self.then_body)
  return result:closure_collect_isolated(self.else_body)
end
function Tr.StmtSwitch:closure_collect(input)
  local result = self.value:closure_collect(input)
  for i = 1, #self.arms do result = result:closure_collect_isolated({ self.arms[i] }) end
  for i = 1, #self.variant_arms do result = result:closure_collect_isolated({ self.variant_arms[i] }) end
  return result:closure_collect_isolated(self.default_body)
end
function Tr.StmtVariantSwitchSource:closure_collect(input)
  local result = self.value:closure_collect(input)
  for i = 1, #self.arms do result = result:closure_collect_isolated({ self.arms[i] }) end
  for i = 1, #self.variant_arms do result = result:closure_collect_isolated({ self.variant_arms[i] }) end
  return result:closure_collect_isolated(self.default_body)
end
function Tr.SwitchVariantSourceStmtArm:closure_collect(input)
  -- Source bind names shadow outer locals during capture analysis; types
  -- are unknown until typecheck resolves them to typed VariantBinds.
  local bound = input.scopes
  for i = 1, #(self.binds or {}) do
    local b = self.binds[i]
    bound = bound:closure_bind(B.Binding(C.Id("closure:switch-stmt:" .. b.name .. ":" .. tostring(i)), b.name, Ty.TScalar(C.ScalarVoid), B.BindingRoleLocalValue))
  end
  return collect_stmts(self.body, Sem.ClosureCollectInput(bound, input.captures))
end
function Tr.StmtJump:closure_collect(input) return collect_many(self.args, input) end
function Tr.StmtBranchJump:closure_collect(input)
  return self.cond:closure_collect(input):closure_continue_many(self.then_args)
    :closure_continue_many(self.else_args)
end
function Tr.StmtJumpCont:closure_collect(input) return collect_many(self.args, input) end
function Tr.StmtRegionEmit:closure_collect(input) return collect_exprs(self.args, input) end
function Tr.StmtRegionCall:closure_collect(input) return collect_exprs(self.args, input) end
function Tr.StmtYieldVoid:closure_collect(input) return collected(input) end
function Tr.StmtYieldValue:closure_collect(input) return self.value:closure_collect(input) end
function Tr.StmtReturnVoid:closure_collect(input) return collected(input) end
function Tr.StmtReturnValue:closure_collect(input) return self.value:closure_collect(input) end
function Tr.StmtControl:closure_collect(input) return self.region:closure_collect(input) end
function Tr.StmtDomainControl:closure_collect(input) return self.region:closure_collect(input) end
function Tr.StmtTrap:closure_collect(input) return collected(input) end

function Tr.JumpArg:closure_collect(input) return self.value:closure_collect(input) end
function Tr.EntryBlockParam:closure_collect(input) return self.init:closure_collect(input) end
local function collect_param_scopes(scopes,params,site) return collect_bind_values(scopes,params,site) end
function Tr.EntryControlBlock:closure_collect(input) local result=collect_many(self.params,input); return result:closure_collect_scoped(self.body,collect_param_scopes(input.scopes,self.params,"entry")) end
function Tr.ControlBlock:closure_collect(input) return collected(input):closure_collect_scoped(self.body,collect_param_scopes(input.scopes,self.params,"block")) end
local function collect_control(region,input)
  local result=region.entry:closure_collect(input)
  for i=1,#region.blocks do result=result:closure_collect_isolated({region.blocks[i]}) end
  return result
end
function Tr.ControlStmtRegion:closure_collect(input) return collect_control(self,input) end
function Tr.ControlExprRegion:closure_collect(input) return collect_control(self,input) end

local function type_capture_layout(ty, input)
  return TypeSizeAlign.result(ty, input.env, input.target):closure_capture_layout(input)
end
function Ty.TypeMemLayoutKnown:closure_capture_layout(input)
  local align = self.layout.align
  local offset = math.floor((input.offset + align - 1) / align) * align
  return Sem.ClosureCaptureLaidOut(Sem.ClosureCaptureSlot(input.candidate, offset, self.layout.size, align))
end
function Ty.TypeMemLayoutUnknown:closure_capture_layout(input)
  return Sem.ClosureCaptureLayoutUnsupported(input.candidate, "capture type has no known memory layout")
end
function Ty.TScalar:closure_capture_layout(input) return type_capture_layout(self, input) end
function Ty.TPtr:closure_capture_layout(input) return type_capture_layout(self, input) end
function Ty.TArray:closure_capture_layout(input) return type_capture_layout(self, input) end
function Ty.TSlice:closure_capture_layout(input) return type_capture_layout(self, input) end
function Ty.TView:closure_capture_layout(input) return type_capture_layout(self, input) end
function Ty.TLease:closure_capture_layout(input) return type_capture_layout(self, input) end
function Ty.TOwned:closure_capture_layout(input) return type_capture_layout(self, input) end
function Ty.TAccess:closure_capture_layout(input) return type_capture_layout(self, input) end
function Ty.THandle:closure_capture_layout(input) return type_capture_layout(self, input) end
function Ty.TFunc:closure_capture_layout(input) return type_capture_layout(self, input) end
function Ty.TClosure:closure_capture_layout(input) return type_capture_layout(self, input) end
function Ty.TNamed:closure_capture_layout(input) return type_capture_layout(self, input) end
function Ty.TCType:closure_capture_layout(input) return type_capture_layout(self, input) end
function Ty.TCFuncPtr:closure_capture_layout(input) return type_capture_layout(self, input) end

----------------------------------------------------------------------
-- Typed closure rewriting
----------------------------------------------------------------------
function Sem.ClosureRewriteReady:closure_merge(status) return status end
function Sem.ClosureRewriteBlocked:closure_merge() return self end
function Sem.ClosureRewriteReady:closure_expr_result(old, new, input)
  if old == new then return Sem.ClosureExprUnchanged(old, input) end
  return Sem.ClosureExprConverted(new, input)
end
function Sem.ClosureRewriteBlocked:closure_expr_result(old, new, input) return Sem.ClosureExprUnsupported(old, input, self.reason) end
function Sem.ClosureRewriteReady:closure_place_result(old, new, input)
  if old == new then return Sem.ClosurePlaceUnchanged(old, input) end
  return Sem.ClosurePlaceConverted(new, input)
end
function Sem.ClosureRewriteBlocked:closure_place_result(old, new, input) return Sem.ClosurePlaceUnsupported(old, input, self.reason) end
function Sem.ClosureRewriteReady:closure_index_result(old, new, input)
  if old == new then return Sem.ClosureIndexBaseUnchanged(old, input) end
  return Sem.ClosureIndexBaseConverted(new, input)
end
function Sem.ClosureRewriteBlocked:closure_index_result(old, new, input) return Sem.ClosureIndexBaseUnsupported(old, input, self.reason) end
function Sem.ClosureRewriteReady:closure_view_result(old, new, input)
  if old == new then return Sem.ClosureViewUnchanged(old, input) end
  return Sem.ClosureViewConverted(new, input)
end
function Sem.ClosureRewriteBlocked:closure_view_result(old, new, input) return Sem.ClosureViewUnsupported(old, input, self.reason) end
function Sem.ClosureRewriteReady:closure_stmt_result(old, new, input)
  if old == new then return Sem.ClosureStmtUnchanged(old, input) end
  return Sem.ClosureStmtConverted(new, input)
end
function Sem.ClosureRewriteBlocked:closure_stmt_result(old, new, input) return Sem.ClosureStmtUnsupported(old, input, self.reason) end

function Sem.ClosureExprRewriteResult:closure_value() return self.expr end
function Sem.ClosureExprRewriteResult:closure_status() return Sem.ClosureRewriteReady end
function Sem.ClosureExprUnsupported:closure_status() return Sem.ClosureRewriteBlocked(self.reason) end
function Sem.ClosurePlaceRewriteResult:closure_value() return self.place end
function Sem.ClosurePlaceRewriteResult:closure_status() return Sem.ClosureRewriteReady end
function Sem.ClosurePlaceUnsupported:closure_status() return Sem.ClosureRewriteBlocked(self.reason) end
function Sem.ClosureIndexBaseRewriteResult:closure_value() return self.base end
function Sem.ClosureIndexBaseRewriteResult:closure_status() return Sem.ClosureRewriteReady end
function Sem.ClosureIndexBaseUnsupported:closure_status() return Sem.ClosureRewriteBlocked(self.reason) end
function Sem.ClosureViewRewriteResult:closure_value() return self.view end
function Sem.ClosureViewRewriteResult:closure_status() return Sem.ClosureRewriteReady end
function Sem.ClosureViewUnsupported:closure_status() return Sem.ClosureRewriteBlocked(self.reason) end
function Sem.ClosureStmtRewriteResult:closure_value() return self.stmt end
function Sem.ClosureStmtRewriteResult:closure_status() return Sem.ClosureRewriteReady end
function Sem.ClosureStmtUnsupported:closure_status() return Sem.ClosureRewriteBlocked(self.reason) end

local function rewrite_exprs(exprs, input)
  local out, status, next_input = {}, Sem.ClosureRewriteReady, input
  for i = 1, #exprs do
    local result = exprs[i]:closure_rewrite(next_input)
    out[i] = result:closure_value()
    next_input = result.input
    status = status:closure_merge(result:closure_status())
  end
  return Sem.ClosureExprListRewriteResult(out, next_input, status)
end

local function rewrite_stmts(stmts, input)
  local out, status, next_input = {}, Sem.ClosureRewriteReady, input
  for i = 1, #stmts do
    local result = stmts[i]:closure_rewrite(next_input)
    out[i] = result:closure_value()
    next_input = result.input
    status = status:closure_merge(result:closure_status())
  end
  return Sem.ClosureStmtListRewriteResult(out, next_input, status)
end

local function rewrite_with_scopes(input, scopes)
  return Sem.ClosureRewriteInput(scopes, input.environment, input.supply, input.helpers, input.layouts, input.target)
end
local function rewrite_isolated(stmts, input, scopes)
  local result = rewrite_stmts(stmts, rewrite_with_scopes(input, scopes))
  return Sem.ClosureStmtListRewriteResult(result.stmts, rewrite_with_scopes(result.input, scopes), result.status)
end
local function local_frame(values, site)
  local bindings = {}
  for i = 1, #values do
    local value = values[i]
    bindings[i] = Sem.ClosureBinding(B.Binding(C.Id("closure:" .. site .. ":" .. value.name .. ":" .. tostring(i)), value.name, value.ty, B.BindingRoleLocalValue))
  end
  return Sem.ClosureScopeFrame(bindings)
end

function Sem.ClosureScopeStack:closure_lookup_local(name)
  local top = self.frames[#self.frames]
  if top then
    for i = #top.bindings, 1, -1 do
      if top.bindings[i].binding.name == name then return Sem.ClosureLookupFound(top.bindings[i]) end
    end
  end
  return Sem.ClosureLookupMissing
end
function Sem.ClosureEnvironment:closure_lookup_name(name)
  for i = #self.entries, 1, -1 do
    if self.entries[i].binding.binding.name == name then return Sem.ClosureEnvironmentFound(self.entries[i]) end
  end
  return Sem.ClosureEnvironmentMissing
end

local function captured_address(entry)
  local slot, ty = entry.slot, entry.binding.binding.ty
  local context = Tr.ExprRef(Tr.ExprSurface, B.ValueRefName("__lalin_ctx"))
  local address = context
  if slot.offset ~= 0 then address = Tr.ExprBinary(Tr.ExprSurface, C.BinAdd, context, Tr.ExprLit(Tr.ExprSurface, C.LitInt(tostring(slot.offset)))) end
  return Tr.ExprCast(Tr.ExprSurface, C.SurfaceCast, Ty.TPtr(ty), address)
end
local function captured_load(entry) return Tr.ExprLoad(Tr.ExprSurface, entry.binding.binding.ty, captured_address(entry)) end
function Sem.ClosureEnvironmentFound:closure_rewrite_reference(original, input) return Sem.ClosureExprConverted(captured_load(self.entry), input) end
function Sem.ClosureEnvironmentMissing:closure_rewrite_reference(original, input) return Sem.ClosureExprUnchanged(original, input) end
function Sem.ClosureLookupFound:closure_rewrite_reference(original, input) return Sem.ClosureExprUnchanged(original, input) end
function Sem.ClosureLookupMissing:closure_rewrite_reference(original, input, name)
  return input.environment:closure_lookup_name(name):closure_rewrite_reference(original, input)
end
function B.ValueRefName:closure_rewrite_reference(original, input)
  return input.scopes:closure_lookup_local(self.name):closure_rewrite_reference(original, input, self.name)
end
function B.ValueRefPath:closure_rewrite_reference(original, input) return Sem.ClosureExprUnchanged(original, input) end
function B.ValueRefBinding:closure_rewrite_reference(original, input) return Sem.ClosureExprUnchanged(original, input) end

local function unchanged_expr(self, input) return Sem.ClosureExprUnchanged(self, input) end
function Tr.ExprLit:closure_rewrite(input) return unchanged_expr(self, input) end
function Tr.ExprRef:closure_rewrite(input) return self.ref:closure_rewrite_reference(self, input) end
function Tr.ExprDot:closure_rewrite(input) local r=self.base:closure_rewrite(input); return r:closure_status():closure_expr_result(self, asdl.with(self,{base=r:closure_value()}), r.input) end
function Tr.ExprUnary:closure_rewrite(input) local r=self.value:closure_rewrite(input); return r:closure_status():closure_expr_result(self, asdl.with(self,{value=r:closure_value()}),r.input) end
local function rewrite_binary(self,input) local a=self.lhs:closure_rewrite(input); local b=self.rhs:closure_rewrite(a.input); local s=a:closure_status():closure_merge(b:closure_status()); return s:closure_expr_result(self,asdl.with(self,{lhs=a:closure_value(),rhs=b:closure_value()}),b.input) end
function Tr.ExprBinary:closure_rewrite(input) return rewrite_binary(self,input) end
function Tr.ExprCompare:closure_rewrite(input) return rewrite_binary(self,input) end
function Tr.ExprLogic:closure_rewrite(input) return rewrite_binary(self,input) end
function Tr.ExprCast:closure_rewrite(input) local r=self.value:closure_rewrite(input); return r:closure_status():closure_expr_result(self,asdl.with(self,{value=r:closure_value()}),r.input) end
function Tr.ExprMachineCast:closure_rewrite(input) local r=self.value:closure_rewrite(input); return r:closure_status():closure_expr_result(self,asdl.with(self,{value=r:closure_value()}),r.input) end
function Tr.ExprIntrinsic:closure_rewrite(input) local r=rewrite_exprs(self.args,input); return r.status:closure_expr_result(self,asdl.with(self,{args=r.exprs}),r.input) end
function Tr.ExprAddrOf:closure_rewrite(input) local r=self.place:closure_rewrite(input); return r:closure_status():closure_expr_result(self,asdl.with(self,{place=r:closure_value()}),r.input) end
function Tr.ExprDeref:closure_rewrite(input) local r=self.value:closure_rewrite(input); return r:closure_status():closure_expr_result(self,asdl.with(self,{value=r:closure_value()}),r.input) end
function Tr.ExprCall:closure_rewrite(input) local c=self.callee:closure_rewrite(input); local a=rewrite_exprs(self.args,c.input); return c:closure_status():closure_merge(a.status):closure_expr_result(self,asdl.with(self,{callee=c:closure_value(),args=a.exprs}),a.input) end
function Tr.ExprLen:closure_rewrite(input) local r=self.value:closure_rewrite(input); return r:closure_status():closure_expr_result(self,asdl.with(self,{value=r:closure_value()}),r.input) end
function Tr.ExprField:closure_rewrite(input) local r=self.base:closure_rewrite(input); return r:closure_status():closure_expr_result(self,asdl.with(self,{base=r:closure_value()}),r.input) end
function Tr.ExprIndex:closure_rewrite(input) local b=self.base:closure_rewrite(input); local i=self.index:closure_rewrite(b.input); return b:closure_status():closure_merge(i:closure_status()):closure_expr_result(self,asdl.with(self,{base=b:closure_value(),index=i:closure_value()}),i.input) end
function Tr.ExprAgg:closure_rewrite(input)
  local fields, status, next_input = {}, Sem.ClosureRewriteReady, input
  for i=1,#self.fields do local r=self.fields[i].value:closure_rewrite(next_input); fields[i]=asdl.with(self.fields[i],{value=r:closure_value()}); next_input=r.input; status=status:closure_merge(r:closure_status()) end
  return status:closure_expr_result(self,asdl.with(self,{fields=fields}),next_input)
end
function Tr.ExprArray:closure_rewrite(input) local r=rewrite_exprs(self.elems,input); return r.status:closure_expr_result(self,asdl.with(self,{elems=r.exprs}),r.input) end
local function rewrite_conditional(self,input) local c=self.cond:closure_rewrite(input); local a=self.then_expr:closure_rewrite(c.input); local b=self.else_expr:closure_rewrite(a.input); return c:closure_status():closure_merge(a:closure_status()):closure_merge(b:closure_status()):closure_expr_result(self,asdl.with(self,{cond=c:closure_value(),then_expr=a:closure_value(),else_expr=b:closure_value()}),b.input) end
function Tr.ExprIf:closure_rewrite(input) return rewrite_conditional(self,input) end
function Tr.ExprSelect:closure_rewrite(input) return rewrite_conditional(self,input) end
function Tr.SwitchKeyInt:closure_rewrite(input) return Sem.ClosureSwitchKeyRewriteResult(self,input,Sem.ClosureRewriteReady) end
function Tr.SwitchKeyBool:closure_rewrite(input) return Sem.ClosureSwitchKeyRewriteResult(self,input,Sem.ClosureRewriteReady) end
function Tr.SwitchKeyName:closure_rewrite(input) return Sem.ClosureSwitchKeyRewriteResult(self,input,Sem.ClosureRewriteReady) end
function Tr.SwitchKeyExpr:closure_rewrite(input) local r=self.expr:closure_rewrite(input); return Sem.ClosureSwitchKeyRewriteResult(asdl.with(self,{expr=r:closure_value()}),r.input,r:closure_status()) end
function Tr.ExprSwitch:closure_rewrite(input)
  local value=self.value:closure_rewrite(input); local next_input=value.input; local status=value:closure_status(); local scopes=next_input.scopes
  local arms={}
  for i=1,#self.arms do local arm=self.arms[i]; local key=arm.key:closure_rewrite(next_input); local branch_scopes=scopes:closure_push(Sem.ClosureScopeFrame({})); local body=rewrite_stmts(arm.body,rewrite_with_scopes(key.input,branch_scopes)); local result=arm.result:closure_rewrite(body.input); arms[i]=asdl.with(arm,{key=key.key,body=body.stmts,result=result:closure_value()}); next_input=rewrite_with_scopes(result.input,scopes); status=status:closure_merge(key.status):closure_merge(body.status):closure_merge(result:closure_status()) end
  local variant_arms={}
  for i=1,#self.variant_arms do local arm=self.variant_arms[i]; local arm_scopes=scopes:closure_push(local_frame(arm.binds,"switch-expr")); local body=rewrite_stmts(arm.body,rewrite_with_scopes(next_input,arm_scopes)); local result=arm.result:closure_rewrite(body.input); variant_arms[i]=asdl.with(arm,{body=body.stmts,result=result:closure_value()}); next_input=rewrite_with_scopes(result.input,scopes); status=status:closure_merge(body.status):closure_merge(result:closure_status()) end
  local default_scopes=scopes:closure_push(Sem.ClosureScopeFrame({})); local default_body=rewrite_stmts(self.default_body,rewrite_with_scopes(next_input,default_scopes)); local default_expr=self.default_expr:closure_rewrite(default_body.input); next_input=rewrite_with_scopes(default_expr.input,scopes); status=status:closure_merge(default_body.status):closure_merge(default_expr:closure_status())
  return status:closure_expr_result(self,asdl.with(self,{value=value:closure_value(),arms=arms,variant_arms=variant_arms,default_body=default_body.stmts,default_expr=default_expr:closure_value()}),next_input)
end
local function rewrite_control_children(region,input)
  local scopes=input.scopes; local params={} ; local next_input=input; local status=Sem.ClosureRewriteReady
  for i=1,#region.entry.params do local p=region.entry.params[i]; local r=p.init:closure_rewrite(next_input); params[i]=asdl.with(p,{init=r:closure_value()}); next_input=r.input; status=status:closure_merge(r:closure_status()) end
  local entry_scopes=scopes:closure_push(local_frame(region.entry.params,"control-entry")); local entry_body=rewrite_isolated(region.entry.body,next_input,entry_scopes); next_input=rewrite_with_scopes(entry_body.input,scopes); status=status:closure_merge(entry_body.status)
  local blocks={}
  for i=1,#region.blocks do local block=region.blocks[i]; local block_scopes=scopes:closure_push(local_frame(block.params,"control-block")); local body=rewrite_isolated(block.body,next_input,block_scopes); blocks[i]=asdl.with(block,{body=body.stmts}); next_input=rewrite_with_scopes(body.input,scopes); status=status:closure_merge(body.status) end
  return Sem.ClosureControlChildrenRewriteResult(asdl.with(region.entry,{params=params,body=entry_body.stmts}),blocks,next_input,status)
end
function Tr.ExprControl:closure_rewrite(input) local r=rewrite_control_children(self.region,input); return r.status:closure_expr_result(self,asdl.with(self,{region=asdl.with(self.region,{entry=r.entry,blocks=r.blocks})}),r.input) end
function Tr.ExprDomainControl:closure_rewrite(input) local r=rewrite_control_children(self.region,input); return r.status:closure_expr_result(self,asdl.with(self,{region=asdl.with(self.region,{entry=r.entry,blocks=r.blocks})}),r.input) end
function Tr.ExprBlock:closure_rewrite(input) local scopes=input.scopes:closure_push(Sem.ClosureScopeFrame({})); local s=rewrite_stmts(self.stmts,rewrite_with_scopes(input,scopes)); local r=self.result:closure_rewrite(s.input); return s.status:closure_merge(r:closure_status()):closure_expr_result(self,asdl.with(self,{stmts=s.stmts,result=r:closure_value()}),rewrite_with_scopes(r.input,input.scopes)) end
function Tr.ExprClosure:closure_rewrite(input) return self:closure_convert(input) end
function Tr.ExprView:closure_rewrite(input) local r=self.view:closure_rewrite(input); return r:closure_status():closure_expr_result(self,asdl.with(self,{view=r:closure_value()}),r.input) end
function Tr.ExprLoad:closure_rewrite(input) local r=self.addr:closure_rewrite(input); return r:closure_status():closure_expr_result(self,asdl.with(self,{addr=r:closure_value()}),r.input) end
function Tr.ExprAtomicLoad:closure_rewrite(input) local r=self.addr:closure_rewrite(input); return r:closure_status():closure_expr_result(self,asdl.with(self,{addr=r:closure_value()}),r.input) end
function Tr.ExprAtomicRmw:closure_rewrite(input) local a=self.addr:closure_rewrite(input); local v=self.value:closure_rewrite(a.input); return a:closure_status():closure_merge(v:closure_status()):closure_expr_result(self,asdl.with(self,{addr=a:closure_value(),value=v:closure_value()}),v.input) end
function Tr.ExprAtomicCas:closure_rewrite(input) local a=self.addr:closure_rewrite(input); local e=self.expected:closure_rewrite(a.input); local r=self.replacement:closure_rewrite(e.input); return a:closure_status():closure_merge(e:closure_status()):closure_merge(r:closure_status()):closure_expr_result(self,asdl.with(self,{addr=a:closure_value(),expected=e:closure_value(),replacement=r:closure_value()}),r.input) end
function Tr.ExprCtor:closure_rewrite(input) local r=rewrite_exprs(self.args,input); return r.status:closure_expr_result(self,asdl.with(self,{args=r.exprs}),r.input) end
function Tr.ExprNull:closure_rewrite(input) return unchanged_expr(self,input) end
function Tr.ExprSizeOf:closure_rewrite(input) return unchanged_expr(self,input) end
function Tr.ExprAlignOf:closure_rewrite(input) return unchanged_expr(self,input) end
function Tr.ExprIsNull:closure_rewrite(input) local r=self.value:closure_rewrite(input); return r:closure_status():closure_expr_result(self,asdl.with(self,{value=r:closure_value()}),r.input) end

function Sem.ClosureEnvironmentFound:closure_rewrite_place(original,input) return Sem.ClosurePlaceConverted(Tr.PlaceDeref(Tr.PlaceSurface,captured_address(self.entry)),input) end
function Sem.ClosureEnvironmentMissing:closure_rewrite_place(original,input) return Sem.ClosurePlaceUnchanged(original,input) end
function Sem.ClosureLookupFound:closure_rewrite_place(original,input) return Sem.ClosurePlaceUnchanged(original,input) end
function Sem.ClosureLookupMissing:closure_rewrite_place(original,input,name) return input.environment:closure_lookup_name(name):closure_rewrite_place(original,input) end
function B.ValueRefName:closure_rewrite_place(original,input) return input.scopes:closure_lookup_local(self.name):closure_rewrite_place(original,input,self.name) end
function B.ValueRefPath:closure_rewrite_place(original,input) return Sem.ClosurePlaceUnchanged(original,input) end
function B.ValueRefBinding:closure_rewrite_place(original,input) return Sem.ClosurePlaceUnchanged(original,input) end
function Tr.PlaceRef:closure_rewrite(input) return self.ref:closure_rewrite_place(self,input) end
function Tr.PlaceDeref:closure_rewrite(input) local r=self.base:closure_rewrite(input); return r:closure_status():closure_place_result(self,asdl.with(self,{base=r:closure_value()}),r.input) end
function Tr.PlaceDot:closure_rewrite(input) local r=self.base:closure_rewrite(input); return r:closure_status():closure_place_result(self,asdl.with(self,{base=r:closure_value()}),r.input) end
function Tr.PlaceField:closure_rewrite(input) local r=self.base:closure_rewrite(input); return r:closure_status():closure_place_result(self,asdl.with(self,{base=r:closure_value()}),r.input) end
function Tr.PlaceIndex:closure_rewrite(input) local b=self.base:closure_rewrite(input); local i=self.index:closure_rewrite(b.input); return b:closure_status():closure_merge(i:closure_status()):closure_place_result(self,asdl.with(self,{base=b:closure_value(),index=i:closure_value()}),i.input) end
function Tr.IndexBaseExpr:closure_rewrite(input) local r=self.base:closure_rewrite(input); return r:closure_status():closure_index_result(self,asdl.with(self,{base=r:closure_value()}),r.input) end
function Tr.IndexBasePlace:closure_rewrite(input) local r=self.base:closure_rewrite(input); return r:closure_status():closure_index_result(self,asdl.with(self,{base=r:closure_value()}),r.input) end
function Tr.IndexBaseView:closure_rewrite(input) local r=self.view:closure_rewrite(input); return r:closure_status():closure_index_result(self,asdl.with(self,{view=r:closure_value()}),r.input) end

function Tr.ViewFromExpr:closure_rewrite(input) local r=self.base:closure_rewrite(input); return r:closure_status():closure_view_result(self,asdl.with(self,{base=r:closure_value()}),r.input) end
function Tr.ViewContiguous:closure_rewrite(input) local d=self.data:closure_rewrite(input); local l=self.len:closure_rewrite(d.input); return d:closure_status():closure_merge(l:closure_status()):closure_view_result(self,asdl.with(self,{data=d:closure_value(),len=l:closure_value()}),l.input) end
function Tr.ViewStrided:closure_rewrite(input) local d=self.data:closure_rewrite(input); local l=self.len:closure_rewrite(d.input); local s=self.stride:closure_rewrite(l.input); return d:closure_status():closure_merge(l:closure_status()):closure_merge(s:closure_status()):closure_view_result(self,asdl.with(self,{data=d:closure_value(),len=l:closure_value(),stride=s:closure_value()}),s.input) end
function Tr.ViewRestrided:closure_rewrite(input) local b=self.base:closure_rewrite(input); local s=self.stride:closure_rewrite(b.input); return b:closure_status():closure_merge(s:closure_status()):closure_view_result(self,asdl.with(self,{base=b:closure_value(),stride=s:closure_value()}),s.input) end
function Tr.ViewWindow:closure_rewrite(input) local b=self.base:closure_rewrite(input); local s=self.start:closure_rewrite(b.input); local l=self.len:closure_rewrite(s.input); return b:closure_status():closure_merge(s:closure_status()):closure_merge(l:closure_status()):closure_view_result(self,asdl.with(self,{base=b:closure_value(),start=s:closure_value(),len=l:closure_value()}),l.input) end
function Tr.ViewRowBase:closure_rewrite(input) local b=self.base:closure_rewrite(input); local r=self.row_offset:closure_rewrite(b.input); return b:closure_status():closure_merge(r:closure_status()):closure_view_result(self,asdl.with(self,{base=b:closure_value(),row_offset=r:closure_value()}),r.input) end
function Tr.ViewInterleaved:closure_rewrite(input) local r=rewrite_exprs({self.data,self.len,self.stride,self.lane},input); return r.status:closure_view_result(self,asdl.with(self,{data=r.exprs[1],len=r.exprs[2],stride=r.exprs[3],lane=r.exprs[4]}),r.input) end
function Tr.ViewInterleavedView:closure_rewrite(input) local b=self.base:closure_rewrite(input); local r=rewrite_exprs({self.stride,self.lane},b.input); return b:closure_status():closure_merge(r.status):closure_view_result(self,asdl.with(self,{base=b:closure_value(),stride=r.exprs[1],lane=r.exprs[2]}),r.input) end

local function unchanged_stmt(self,input) return Sem.ClosureStmtUnchanged(self,input) end
function Tr.StmtLet:closure_rewrite(input) local r=self.init:closure_rewrite(input); local scopes=r.input.scopes:closure_bind(self.binding); local next_input=rewrite_with_scopes(r.input,scopes); return r:closure_status():closure_stmt_result(self,asdl.with(self,{init=r:closure_value()}),next_input) end
function Tr.StmtVar:closure_rewrite(input) local r=self.init:closure_rewrite(input); local scopes=r.input.scopes:closure_bind(self.binding); local next_input=rewrite_with_scopes(r.input,scopes); return r:closure_status():closure_stmt_result(self,asdl.with(self,{init=r:closure_value()}),next_input) end
function Tr.StmtSet:closure_rewrite(input) local p=self.place:closure_rewrite(input); local v=self.value:closure_rewrite(p.input); return p:closure_status():closure_merge(v:closure_status()):closure_stmt_result(self,asdl.with(self,{place=p:closure_value(),value=v:closure_value()}),v.input) end
function Tr.StmtAtomicStore:closure_rewrite(input) local a=self.addr:closure_rewrite(input); local v=self.value:closure_rewrite(a.input); return a:closure_status():closure_merge(v:closure_status()):closure_stmt_result(self,asdl.with(self,{addr=a:closure_value(),value=v:closure_value()}),v.input) end
function Tr.StmtAtomicFence:closure_rewrite(input) return unchanged_stmt(self,input) end
function Tr.StmtExpr:closure_rewrite(input) local r=self.expr:closure_rewrite(input); return r:closure_status():closure_stmt_result(self,asdl.with(self,{expr=r:closure_value()}),r.input) end
function Tr.StmtAssert:closure_rewrite(input) local r=self.cond:closure_rewrite(input); return r:closure_status():closure_stmt_result(self,asdl.with(self,{cond=r:closure_value()}),r.input) end
function Tr.StmtIf:closure_rewrite(input) local c=self.cond:closure_rewrite(input); local scopes=c.input.scopes; local a=rewrite_isolated(self.then_body,c.input,scopes); local b=rewrite_isolated(self.else_body,a.input,scopes); return c:closure_status():closure_merge(a.status):closure_merge(b.status):closure_stmt_result(self,asdl.with(self,{cond=c:closure_value(),then_body=a.stmts,else_body=b.stmts}),b.input) end
function Tr.StmtSwitch:closure_rewrite(input)
  local value=self.value:closure_rewrite(input); local next_input=value.input; local scopes=next_input.scopes; local status=value:closure_status(); local arms={}
  for i=1,#self.arms do local arm=self.arms[i]; local key=arm.key:closure_rewrite(next_input); local body=rewrite_isolated(arm.body,key.input,scopes); arms[i]=asdl.with(arm,{key=key.key,body=body.stmts}); next_input=body.input; status=status:closure_merge(key.status):closure_merge(body.status) end
  local variant_arms={}
  for i=1,#self.variant_arms do local arm=self.variant_arms[i]; local arm_scopes=scopes:closure_push(local_frame(arm.binds,"switch-stmt")); local body=rewrite_isolated(arm.body,next_input,arm_scopes); variant_arms[i]=asdl.with(arm,{body=body.stmts}); next_input=rewrite_with_scopes(body.input,scopes); status=status:closure_merge(body.status) end
  local default_body=rewrite_isolated(self.default_body,next_input,scopes); status=status:closure_merge(default_body.status)
  return status:closure_stmt_result(self,asdl.with(self,{value=value:closure_value(),arms=arms,variant_arms=variant_arms,default_body=default_body.stmts}),default_body.input)
end
function Tr.StmtVariantSwitchSource:closure_rewrite(input)
  local value=self.value:closure_rewrite(input); local next_input=value.input; local scopes=next_input.scopes; local status=value:closure_status(); local arms={}
  for i=1,#self.arms do local arm=self.arms[i]; local key=arm.key:closure_rewrite(next_input); local body=rewrite_isolated(arm.body,key.input,scopes); arms[i]=asdl.with(arm,{key=key.key,body=body.stmts}); next_input=body.input; status=status:closure_merge(key.status):closure_merge(body.status) end
  local variant_arms={}
  for i=1,#self.variant_arms do
    local arm=self.variant_arms[i]
    local source_binds={}
    for j=1,#arm.binds do local b=arm.binds[j]; source_binds[j]=Sem.ClosureBinding(B.Binding(C.Id("closure:switch-stmt:"..b.name..":"..tostring(j)),b.name,Ty.TScalar(C.ScalarVoid),B.BindingRoleLocalValue)) end
    local arm_scopes=scopes:closure_push(Sem.ClosureScopeFrame(source_binds))
    local body=rewrite_isolated(arm.body,next_input,arm_scopes)
    variant_arms[i]=asdl.with(arm,{body=body.stmts})
    next_input=rewrite_with_scopes(body.input,scopes)
    status=status:closure_merge(body.status)
  end
  local default_body=rewrite_isolated(self.default_body,next_input,scopes); status=status:closure_merge(default_body.status)
  return status:closure_stmt_result(self,asdl.with(self,{value=value:closure_value(),arms=arms,variant_arms=variant_arms,default_body=default_body.stmts}),default_body.input)
end
local function rewrite_jump_args(args,input)
  local out={}; local status=Sem.ClosureRewriteReady; local next_input=input
  for i=1,#args do local r=args[i].value:closure_rewrite(next_input); out[i]=asdl.with(args[i],{value=r:closure_value()}); next_input=r.input; status=status:closure_merge(r:closure_status()) end
  return Sem.ClosureJumpArgsRewriteResult(out,next_input,status)
end
function Tr.StmtJump:closure_rewrite(input) local r=rewrite_jump_args(self.args,input); return r.status:closure_stmt_result(self,asdl.with(self,{args=r.args}),r.input) end
function Tr.StmtBranchJump:closure_rewrite(input)
  local condition = self.cond:closure_rewrite(input)
  local then_result = rewrite_jump_args(self.then_args, condition.input)
  local else_result = rewrite_jump_args(self.else_args, then_result.input)
  local status = condition:closure_status():closure_merge(then_result.status)
    :closure_merge(else_result.status)
  return status:closure_stmt_result(self, asdl.with(self, {
    cond = condition:closure_value(), then_args = then_result.args,
    else_args = else_result.args,
  }), else_result.input)
end
function Tr.StmtJumpCont:closure_rewrite(input) local r=rewrite_jump_args(self.args,input); return r.status:closure_stmt_result(self,asdl.with(self,{args=r.args}),r.input) end
function Tr.StmtRegionEmit:closure_rewrite(input) local r=rewrite_exprs(self.args,input); return r.status:closure_stmt_result(self,asdl.with(self,{args=r.exprs}),r.input) end
function Tr.StmtRegionCall:closure_rewrite(input) local r=rewrite_exprs(self.args,input); return r.status:closure_stmt_result(self,asdl.with(self,{args=r.exprs}),r.input) end
function Tr.StmtYieldVoid:closure_rewrite(input) return unchanged_stmt(self,input) end
function Tr.StmtYieldValue:closure_rewrite(input) local r=self.value:closure_rewrite(input); return r:closure_status():closure_stmt_result(self,asdl.with(self,{value=r:closure_value()}),r.input) end
function Tr.StmtReturnVoid:closure_rewrite(input) return unchanged_stmt(self,input) end
function Tr.StmtReturnValue:closure_rewrite(input) local r=self.value:closure_rewrite(input); return r:closure_status():closure_stmt_result(self,asdl.with(self,{value=r:closure_value()}),r.input) end
function Tr.StmtControl:closure_rewrite(input) local r=rewrite_control_children(self.region,input); return r.status:closure_stmt_result(self,asdl.with(self,{region=asdl.with(self.region,{entry=r.entry,blocks=r.blocks})}),r.input) end
function Tr.StmtDomainControl:closure_rewrite(input) local r=rewrite_control_children(self.region,input); return r.status:closure_stmt_result(self,asdl.with(self,{region=asdl.with(self.region,{entry=r.entry,blocks=r.blocks})}),r.input) end
function Tr.StmtTrap:closure_rewrite(input) return unchanged_stmt(self,input) end

----------------------------------------------------------------------
-- Typed function/item/module transitions
----------------------------------------------------------------------
function Sem.ClosureNameSupply:closure_fresh()
  local name = "__lalin_closure_" .. self.module_name .. "_" .. self.owner_name .. "_" .. tostring(self.next_index)
  return Sem.ClosureFreshName(name, Sem.ClosureNameSupply(self.module_name, self.owner_name, self.next_index + 1))
end

function Sem.ClosureCaptureLaidOut:closure_build_advance(state)
  local slots = copy(state.slots)
  slots[#slots + 1] = self.slot
  local finish = self.slot.offset + self.slot.size
  local align = state.align
  if self.slot.align > align then align = self.slot.align end
  return Sem.ClosureLayoutBuilding(Sem.ClosureLayoutBuildState(slots, finish, align))
end
function Sem.ClosureCaptureLayoutUnsupported:closure_build_advance() return Sem.ClosureLayoutBuildFailed(self.reason) end
function Sem.ClosureLayoutBuilding:closure_add_candidate(candidate, input)
  local layout_input = Sem.ClosureCaptureLayoutInput(candidate, input.layouts, input.target, self.state.offset)
  return candidate.binding.binding.ty:closure_capture_layout(layout_input):closure_build_advance(self.state)
end
function Sem.ClosureLayoutBuildFailed:closure_add_candidate() return self end

local function params_frame(params)
  local bindings = {}
  for i = 1, #params do
    local p = params[i]
    bindings[i] = Sem.ClosureBinding(B.Binding(C.Id("closure:param:" .. p.name .. ":" .. tostring(i)), p.name, p.ty, B.BindingRoleArg(i)))
  end
  return Sem.ClosureScopeFrame(bindings)
end

local function same_list(a, b)
  if #a ~= #b then return false end
  for i = 1, #a do if a[i] ~= b[i] then return false end end
  return true
end

function Sem.ClosureRewriteReady:closure_func_body_result(original, body, rewrite_input)
  local rewritten = asdl.with(original, { body = body })
  if same_list(original.body, body) and #rewrite_input.helpers.items == 0 then return Sem.ClosureFuncUnchanged(original, rewrite_input.supply) end
  return Sem.ClosureFuncConverted(rewritten, rewrite_input.helpers, rewrite_input.supply)
end
function Sem.ClosureRewriteBlocked:closure_func_body_result(original, body, rewrite_input)
  return Sem.ClosureFuncUnsupported(original, rewrite_input.supply, self.reason)
end

local function append_helpers(input, items, supply)
  local helpers = copy(input.helpers.items)
  for i=1,#items do helpers[#helpers+1]=items[i] end
  return Sem.ClosureRewriteInput(input.scopes,input.environment,supply,Sem.ClosureHelperInsertion(helpers),input.layouts,input.target)
end
local function closure_param_types(params)
  local types={}
  for i=1,#params do types[i]=params[i].ty end
  return types
end
local function closure_entries(slots)
  local entries={}
  for i=1,#slots do entries[i]=Sem.ClosureEnvironmentEntry(slots[i].candidate.binding,slots[i]) end
  return Sem.ClosureEnvironment(entries)
end
local function closure_descriptor(expr, input, fresh, slots, helper_body)
  local u8=Ty.TScalar(C.ScalarU8); local ctx_ty=Ty.TPtr(u8); local helper_params={Ty.Param("__lalin_ctx",ctx_ty)}
  for i=1,#expr.params do helper_params[#helper_params+1]=expr.params[i] end
  local helper=Tr.ItemFunc(Tr.FuncLocal(fresh.name,helper_params,expr.result,helper_body))
  local helper_ref=Tr.ExprRef(Tr.ExprSurface,B.ValueRefName(fresh.name)); local ctx_expr; local items={}
  if #slots == 0 then
    ctx_expr=Tr.ExprNull(Tr.ExprSurface,u8)
  else
    local env_name=fresh.name .. "__env"; local env_local=env_name .. "__value"; local fields={}; local decl_fields={}
    for i=1,#slots do local slot=slots[i]; local name="__lalin_cap_" .. slot.candidate.binding.binding.name; fields[i]=Tr.FieldInit(name,Tr.ExprRef(Tr.ExprSurface,B.ValueRefName(slot.candidate.binding.binding.name)),slot.offset); decl_fields[i]=Ty.FieldDecl(name,slot.candidate.binding.binding.ty) end
    local env_ty=Ty.TNamed(Ty.TypeRefGlobal(input.supply.module_name,env_name)); local env_binding=B.Binding(C.Id("closure:environment:" .. fresh.name),env_local,env_ty,B.BindingRoleLocalValue)
    items[1]=Tr.ItemType(Tr.TypeDeclStruct(env_name,decl_fields))
    local init=Tr.ExprAgg(Tr.ExprSurface,env_ty,fields); local addr=Tr.ExprAddrOf(Tr.ExprSurface,Tr.PlaceRef(Tr.PlaceSurface,B.ValueRefName(env_local)))
    ctx_expr=Tr.ExprCast(Tr.ExprSurface,C.SurfaceCast,ctx_ty,addr)
    local closure_ty=Ty.TClosure(closure_param_types(expr.params),expr.result); local descriptor=Tr.ExprAgg(Tr.ExprSurface,closure_ty,{Tr.FieldInit("__lalin_fn",helper_ref,0),Tr.FieldInit("__lalin_ctx",ctx_expr,input.target.pointer_bits/8)})
    items[#items+1]=helper
    local next_input=append_helpers(input,items,input.supply)
    return Sem.ClosureExprConverted(Tr.ExprBlock(Tr.ExprSurface,{Tr.StmtLet(Tr.StmtSurface,env_binding,init)},descriptor),next_input)
  end
  items[1]=helper
  local closure_ty=Ty.TClosure(closure_param_types(expr.params),expr.result); local descriptor=Tr.ExprAgg(Tr.ExprSurface,closure_ty,{Tr.FieldInit("__lalin_fn",helper_ref,0),Tr.FieldInit("__lalin_ctx",ctx_expr,input.target.pointer_bits/8)})
  return Sem.ClosureExprConverted(descriptor,append_helpers(input,items,input.supply))
end
function Sem.ClosureLayoutBuildFailed:closure_materialize_expr(expr,input) return Sem.ClosureExprUnsupported(expr,input,self.reason) end
function Sem.ClosureLayoutBuilding:closure_materialize_expr(expr,input,body_scopes)
  local fresh=input.supply:closure_fresh(); local env=closure_entries(self.state.slots)
  local helper_input=Sem.ClosureRewriteInput(Sem.ClosureScopeStack({params_frame(expr.params)}),env,fresh.supply,input.helpers,input.layouts,input.target)
  local body=rewrite_stmts(expr.body,helper_input)
  return body.status:closure_finish_expr(expr,input,fresh,self.state.slots,body)
end
function Sem.ClosureRewriteBlocked:closure_finish_expr(expr,input,fresh,slots,body) return Sem.ClosureExprUnsupported(expr,rewrite_with_scopes(body.input,input.scopes),self.reason) end
function Sem.ClosureRewriteReady:closure_finish_expr(expr,input,fresh,slots,body)
  local state_input=rewrite_with_scopes(body.input,input.scopes)
  return closure_descriptor(expr,state_input,fresh,slots,body.stmts)
end
local function convert_collected_expr(result,expr,input)
  local build=Sem.ClosureLayoutBuilding(Sem.ClosureLayoutBuildState({},0,1))
  for i=1,#result.input.captures.candidates do build=build:closure_add_candidate(result.input.captures.candidates[i],input) end
  return build:closure_materialize_expr(expr,input,result.input.scopes)
end
function Sem.ClosureCollected:closure_convert_expr(expr,input) return convert_collected_expr(self,expr,input) end
function Sem.ClosureCollectTransitioned:closure_convert_expr(expr,input) return convert_collected_expr(self,expr,input) end
function Sem.ClosureCollectUnsupported:closure_convert_expr(expr,input) return Sem.ClosureExprUnsupported(expr,input,self.reason) end
function Tr.ExprClosure:closure_convert(input)
  local scopes=input.scopes:closure_push(params_frame(self.params)); local captures=collect_stmts(self.body,Sem.ClosureCollectInput(scopes,Sem.ClosureCaptureSet({})))
  return captures:closure_convert_expr(self,input)
end

local function convert_func(func, input)
  local scopes=input.outer_scopes:closure_push(params_frame(func.params))
  local rewrite_input=Sem.ClosureRewriteInput(scopes,Sem.ClosureEnvironment({}),input.supply,Sem.ClosureHelperInsertion({}),input.layouts,input.target)
  local body=rewrite_stmts(func.body,rewrite_input)
  return body.status:closure_func_body_result(func,body.stmts,body.input)
end
function Tr.FuncLocal:closure_convert(input) return convert_func(self, input) end
function Tr.FuncExport:closure_convert(input) return convert_func(self, input) end
function Tr.FuncLocalContract:closure_convert(input) return convert_func(self, input) end
function Tr.FuncExportContract:closure_convert(input) return convert_func(self, input) end
function Tr.FuncDecl:closure_convert(input) return Sem.ClosureFuncUnchanged(self, input.supply) end

function Sem.ClosureFuncConverted:closure_item_result()
  local items = copy(self.helpers.items)
  items[#items + 1] = Tr.ItemFunc(self.func)
  return Sem.ClosureItemConverted(items, self.supply)
end
function Sem.ClosureFuncUnchanged:closure_item_result(original) return Sem.ClosureItemUnchanged(original, self.supply) end
function Sem.ClosureFuncUnsupported:closure_item_result(original) return Sem.ClosureItemRejected(original, self.supply, self.reason) end
function Tr.ItemFunc:closure_convert_item(input)
  local finput = Sem.ClosureFuncInput(input.module_name, input.supply, input.scopes, input.layouts, input.target)
  return self.func:closure_convert(finput):closure_item_result(self)
end
function Tr.ItemExtern:closure_convert_item(input) return Sem.ClosureItemUnchanged(self, input.supply) end
function Tr.ItemConst:closure_convert_item(input) return Sem.ClosureItemUnchanged(self, input.supply) end
function Tr.ItemStatic:closure_convert_item(input) return Sem.ClosureItemUnchanged(self, input.supply) end
function Tr.ItemImport:closure_convert_item(input) return Sem.ClosureItemUnchanged(self, input.supply) end
function Tr.ItemType:closure_convert_item(input) return Sem.ClosureItemUnchanged(self, input.supply) end
function Tr.ItemRegion:closure_convert_item(input) return Sem.ClosureItemUnchanged(self, input.supply) end
function Tr.ItemData:closure_convert_item(input) return Sem.ClosureItemUnchanged(self, input.supply) end

function Sem.ClosureItemConverted:closure_compose(composition)
  local items = copy(composition.items)
  for i = 1, #self.items do items[#items + 1] = self.items[i] end
  return Sem.ClosureModuleComposing(Sem.ClosureModuleComposition(items, self.supply, composition.layouts, composition.target))
end
function Sem.ClosureItemUnchanged:closure_compose(composition)
  local items = copy(composition.items)
  items[#items + 1] = self.item
  return Sem.ClosureModuleComposing(Sem.ClosureModuleComposition(items, self.supply, composition.layouts, composition.target))
end
function Sem.ClosureItemRejected:closure_compose() return Sem.ClosureModuleRejected(self.reason) end
function Sem.ClosureModuleComposing:closure_continue_item(item, module_name)
  local c = self.composition
  local input = Sem.ClosureItemInput(module_name, c.supply, Sem.ClosureScopeStack({}), c.layouts, c.target)
  return item:closure_convert_item(input):closure_compose(c)
end
function Sem.ClosureModuleRejected:closure_continue_item() return self end
function Sem.ClosureModuleComposing:closure_finish(module)
  local rewritten = Tr.Module(module.h, self.composition.items)
  if same_list(module.items, self.composition.items) then return Sem.ClosureUnchanged(module) end
  return Sem.ClosureConverted(rewritten)
end
function Sem.ClosureModuleRejected:closure_finish(module) return Sem.ClosureUnsupported(module, self.reason) end

-- Explicit delegation for the generic frontend pipeline's next typed phase.
function Sem.ClosureConverted:typecheck(input) return self.module:typecheck(input) end
function Sem.ClosureUnchanged:typecheck(input) return self.module:typecheck(input) end
-- Shared typed phase composition (typecheck + region expansion + re-typecheck)
-- is delegated from closure results to the module, mirroring :typecheck.
function Sem.ClosureConverted:typecheck_region_expanded() return self.module:typecheck_region_expanded() end
function Sem.ClosureUnchanged:typecheck_region_expanded() return self.module:typecheck_region_expanded() end

function Tr.ModuleSurface:closure_module_name() return "module" end
function Tr.ModuleTyped:closure_module_name() return self.module_name end
function Tr.ModuleSem:closure_module_name() return self.module_name end
function Tr.ModuleCode:closure_module_name() return self.module_name end
function Tr.Module:closure_convert(input)
  local module_name = self.h:closure_module_name()
  local layouts = Sem.LayoutEnv(self:tree_module_env(input.target).layouts)
  local supply = Sem.ClosureNameSupply(module_name, "module", 1)
  local result = Sem.ClosureModuleComposing(Sem.ClosureModuleComposition({}, supply, layouts, input.target))
  for i = 1, #self.items do result = result:closure_continue_item(self.items[i], module_name) end
  return result:closure_finish(self)
end

return Sem
