-- Canonical, schema-owned CBackend validation.
-- Every CBackend alternative validates itself; the root only builds typed relations
-- and composes the reports returned by those leaves.
require("lalin.schema_v2")
require("lalin.impl.cemit_emit")

local C = require("lalin.schema_v2.c")
local Core = require("lalin.schema_v2.core")

local function report(...)
  local issues = {}
  for i = 1, select("#", ...) do
    local r = select(i, ...)
    for j = 1, #r.issues do issues[#issues + 1] = r.issues[j] end
  end
  return C.CBackendValidationReport(issues)
end

local function issue(value) return C.CBackendValidationReport({ value }) end
local function clean() return C.CBackendValidationReport({}) end

local function valid_c_name(name)
  return name.text:match("^[A-Za-z_][A-Za-z0-9_]*$") ~= nil
end

local function valid_alignment(n)
  if n < 1 or n % 1 ~= 0 then return false end
  while n > 1 do
    if n % 2 ~= 0 then return false end
    n = n / 2
  end
  return true
end

-- Type equality is concrete-leaf double dispatch.
function C.CBackendType:c_validation_type_equal(other) return false end
function C.CBackendType:c_validation_equal_void() return false end
function C.CBackendType:c_validation_equal_bool8() return false end
function C.CBackendType:c_validation_equal_scalar() return false end
function C.CBackendType:c_validation_equal_index() return false end
function C.CBackendType:c_validation_equal_data_ptr() return false end
function C.CBackendType:c_validation_equal_qualified_data_ptr() return false end
function C.CBackendType:c_validation_equal_code_ptr() return false end
function C.CBackendType:c_validation_equal_imported_code_ptr() return false end
function C.CBackendType:c_validation_equal_named() return false end
function C.CBackendType:c_validation_equal_array() return false end
function C.CBackendType:c_validation_equal_slice() return false end
function C.CBackendType:c_validation_equal_bytespan() return false end
function C.CBackendType:c_validation_equal_view() return false end
function C.CBackendType:c_validation_equal_closure() return false end
function C.CBackendType:c_validation_equal_hidden_out() return false end
function C.CBackendType:c_validation_equal_vector() return false end
function C.CBackendVoid:c_validation_type_equal(other) return other:c_validation_equal_void(self) end
function C.CBackendVoid:c_validation_equal_void() return true end
function C.CBackendBool8:c_validation_type_equal(other) return other:c_validation_equal_bool8(self) end
function C.CBackendBool8:c_validation_equal_bool8() return true end
function C.CBackendIndex:c_validation_type_equal(other) return other:c_validation_equal_index(self) end
function C.CBackendIndex:c_validation_equal_index() return true end
function C.CBackendScalar:c_validation_type_equal(other) return other:c_validation_equal_scalar(self) end
function C.CBackendScalar:c_validation_equal_scalar(left) return self.scalar == left.scalar end
function C.CBackendDataPtr:c_validation_type_equal(other) return other:c_validation_equal_data_ptr(self) end
function C.CBackendDataPtr:c_validation_equal_data_ptr(left)
  if self.pointee == nil or left.pointee == nil then return true end
  return self.pointee:c_validation_type_equal(left.pointee)
end
function C.CBackendDataPtr:c_validation_equal_qualified_data_ptr(left) return self:c_validation_equal_data_ptr(left) end
function C.CBackendQualifiedDataPtr:c_validation_type_equal(other) return other:c_validation_equal_qualified_data_ptr(self) end
function C.CBackendQualifiedDataPtr:c_validation_equal_data_ptr(left)
  if self.pointee == nil or left.pointee == nil then return true end
  return self.pointee:c_validation_type_equal(left.pointee)
end
function C.CBackendQualifiedDataPtr:c_validation_equal_qualified_data_ptr(left) return self:c_validation_equal_data_ptr(left) end
function C.CBackendCodePtr:c_validation_type_equal(other) return other:c_validation_equal_code_ptr(self) end
function C.CBackendCodePtr:c_validation_equal_code_ptr(left) return self.sig == left.sig end
function C.CBackendImportedCodePtr:c_validation_type_equal(other) return other:c_validation_equal_imported_code_ptr(self) end
function C.CBackendImportedCodePtr:c_validation_equal_imported_code_ptr(left) return self.sig == left.sig end
function C.CBackendNamed:c_validation_type_equal(other) return other:c_validation_equal_named(self) end
function C.CBackendNamed:c_validation_equal_named(left) return self.id == left.id end
function C.CBackendArray:c_validation_type_equal(other) return other:c_validation_equal_array(self) end
function C.CBackendArray:c_validation_equal_array(left) return self.count == left.count and self.elem:c_validation_type_equal(left.elem) end
function C.CBackendSliceDescriptor:c_validation_type_equal(other) return other:c_validation_equal_slice(self) end
function C.CBackendSliceDescriptor:c_validation_equal_slice(left) return self.elem:c_validation_type_equal(left.elem) end
function C.CBackendByteSpanDescriptor:c_validation_type_equal(other) return other:c_validation_equal_bytespan(self) end
function C.CBackendByteSpanDescriptor:c_validation_equal_bytespan() return true end
function C.CBackendViewDescriptor:c_validation_type_equal(other) return other:c_validation_equal_view(self) end
function C.CBackendViewDescriptor:c_validation_equal_view(left) return self.elem:c_validation_type_equal(left.elem) end
function C.CBackendClosureDescriptor:c_validation_type_equal(other) return other:c_validation_equal_closure(self) end
function C.CBackendClosureDescriptor:c_validation_equal_closure(left)
  if self.sig ~= left.sig then return false end
  if self.ctx == nil or left.ctx == nil then return self.ctx == left.ctx end
  return self.ctx:c_validation_type_equal(left.ctx)
end
function C.CBackendAbiHiddenOutPtr:c_validation_type_equal(other) return other:c_validation_equal_hidden_out(self) end
function C.CBackendAbiHiddenOutPtr:c_validation_equal_hidden_out(left) return self.result:c_validation_type_equal(left.result) end
function C.CBackendVector:c_validation_type_equal(other) return other:c_validation_equal_vector(self) end
function C.CBackendVector:c_validation_equal_vector(left) return self.lanes == left.lanes and self.elem:c_validation_type_equal(left.elem) end

-- Typed keyed relations. Absence is represented by a lookup leaf, never nil.
function C.CBackendValidationSignatureRelation:c_validation_lookup(id)
  for i = 1, #self.entries do if self.entries[i].id == id then return C.CBackendValidationSignatureFound(self.entries[i]) end end
  return C.CBackendValidationSignatureMissing(id)
end
function C.CBackendValidationFunctionRelation:c_validation_lookup(name)
  for i = 1, #self.entries do if self.entries[i].name == name then return C.CBackendValidationFunctionFound(self.entries[i]) end end
  return C.CBackendValidationFunctionMissing(name)
end
function C.CBackendValidationGlobalRelation:c_validation_lookup(id)
  for i = 1, #self.entries do if self.entries[i].id == id then return C.CBackendValidationGlobalFound(self.entries[i]) end end
  return C.CBackendValidationGlobalMissing(id)
end
function C.CBackendValidationExternRelation:c_validation_lookup(name)
  for i = 1, #self.entries do if self.entries[i].name == name then return C.CBackendValidationExternFound(self.entries[i]) end end
  return C.CBackendValidationExternMissing(name)
end
function C.CBackendValidationHelperRelation:c_validation_lookup(id)
  for i = 1, #self.entries do if self.entries[i].id == id then return C.CBackendValidationHelperFound(self.entries[i]) end end
  return C.CBackendValidationHelperMissing(id)
end
function C.CBackendValidationLocalRelation:c_validation_lookup(id)
  for i = 1, #self.entries do if self.entries[i].id == id then return C.CBackendValidationLocalFound(self.entries[i]) end end
  return C.CBackendValidationLocalMissing(id)
end
function C.CBackendValidationLabelRelation:c_validation_lookup(label)
  for i = 1, #self.entries do if self.entries[i].label == label then return C.CBackendValidationLabelFound(self.entries[i]) end end
  return C.CBackendValidationLabelMissing(label)
end

function C.CBackendValidationSignatureFound:c_validation_report() return clean() end
function C.CBackendValidationSignatureMissing:c_validation_report() return issue(C.CBackendIssueMissingSig(self.id)) end
function C.CBackendValidationSignatureFound:c_validation_signature(fallback) return self.entry.signature end
function C.CBackendValidationSignatureMissing:c_validation_signature(fallback) return fallback end
function C.CBackendValidationFunctionFound:c_validation_report() return clean() end
function C.CBackendValidationFunctionMissing:c_validation_report() return issue(C.CBackendIssueMissingFunc(self.name)) end
function C.CBackendValidationGlobalFound:c_validation_report() return clean() end
function C.CBackendValidationGlobalMissing:c_validation_report() return issue(C.CBackendIssueMissingGlobal(self.id)) end
function C.CBackendValidationExternFound:c_validation_report() return clean() end
function C.CBackendValidationExternMissing:c_validation_report() return issue(C.CBackendIssueMissingExtern(self.name)) end
function C.CBackendValidationHelperFound:c_validation_report() return clean() end
function C.CBackendValidationHelperMissing:c_validation_report() return issue(C.CBackendIssueMissingHelper(self.id)) end
function C.CBackendValidationHelperFound:c_validation_signature(fallback) return self.entry.helper:c_helper_signature() end
function C.CBackendValidationHelperMissing:c_validation_signature(fallback) return fallback end
function C.CBackendValidationLabelFound:c_validation_report(func) return clean() end
function C.CBackendValidationLabelMissing:c_validation_report(func) return issue(C.CBackendIssueMissingLabel(func.name, self.label)) end
function C.CBackendValidationLabelFound:c_validation_block(fallback) return self.entry.block end
function C.CBackendValidationLabelMissing:c_validation_block(fallback) return fallback end
function C.CBackendValidationLocalFound:c_validation_typed(input)
  return C.CBackendValidationTypedResult(self.entry.ty, self.entry.init_state:c_validation_read_report(input.func, self.entry.id))
end
function C.CBackendValidationLocalMissing:c_validation_typed(input)
  return C.CBackendValidationTypedResult(C.CBackendVoid, issue(C.CBackendIssueMissingLocal(input.func.name, self.id)))
end
function C.CBackendValidationLocalFound:c_validation_type() return self.entry.ty end
function C.CBackendValidationLocalMissing:c_validation_type() return C.CBackendVoid end
function C.CBackendValidationLocalFound:c_validation_write_typed(input)
  return C.CBackendValidationTypedResult(self.entry.ty, clean())
end
function C.CBackendValidationLocalMissing:c_validation_write_typed(input)
  return C.CBackendValidationTypedResult(C.CBackendVoid, issue(C.CBackendIssueMissingLocal(input.func.name, self.id)))
end

function C.CBackendLocalUninitialized:c_validation_read_report(func, id) return issue(C.CBackendIssueUninitializedLocal(func.name, id)) end
function C.CBackendLocalZeroInitialized:c_validation_read_report() return clean() end
function C.CBackendLocalInitialized:c_validation_read_report() return clean() end
function C.CBackendResidenceValue:c_validation_address_report(func, entry)
  if entry.address_taken then return issue(C.CBackendIssueUnmaterializedAddressTakenValue(func.name, entry.id)) end
  return clean()
end
function C.CBackendResidenceAddressed:c_validation_address_report() return clean() end
function C.CBackendResidenceAggregate:c_validation_address_report() return clean() end
function C.CBackendResidenceDescriptor:c_validation_address_report() return clean() end

-- Every concrete type leaf owns recursive/reference validation.
function C.CBackendVoid:c_validate(input) return clean() end
function C.CBackendBool8:c_validate(input) return clean() end
function C.CBackendScalar:c_validate(input) return clean() end
function C.CBackendIndex:c_validate(input) return clean() end
function C.CBackendDataPtr:c_validate(input) return self.pointee and self.pointee:c_validate(input) or clean() end
function C.CBackendQualifiedDataPtr:c_validate(input) return self.pointee and self.pointee:c_validate(input) or clean() end
function C.CBackendCodePtr:c_validate(input) return input.relations.signatures:c_validation_lookup(self.sig):c_validation_report() end
function C.CBackendImportedCodePtr:c_validate(input) return clean() end
function C.CBackendNamed:c_validate(input) return clean() end
function C.CBackendArray:c_validate(input) return self.elem:c_validate(input) end
function C.CBackendSliceDescriptor:c_validate(input) return self.elem:c_validate(input) end
function C.CBackendByteSpanDescriptor:c_validate(input) return clean() end
function C.CBackendViewDescriptor:c_validate(input) return self.elem:c_validate(input) end
function C.CBackendClosureDescriptor:c_validate(input)
  local r = input.relations.signatures:c_validation_lookup(self.sig):c_validation_report()
  return self.ctx and report(r, self.ctx:c_validate(input)) or r
end
function C.CBackendAbiHiddenOutPtr:c_validate(input) return self.result:c_validate(input) end
function C.CBackendVector:c_validate(input) return self.elem:c_validate(input) end

-- Atoms and places return a typed result so type facts never escape in loose tuples.
function C.CBackendAtomLocal:c_validate(input) return input.locals:c_validation_lookup(self.local_id):c_validation_typed(input) end
function C.CBackendAtomGlobal:c_validate(input)
  local found = input.relations.globals:c_validation_lookup(self.global)
  return C.CBackendValidationTypedResult(found:c_validation_type(), found:c_validation_report())
end
function C.CBackendAtomLiteral:c_validate(input) return C.CBackendValidationTypedResult(self.ty, self.ty:c_validate(input)) end
function C.CBackendAtomNull:c_validate(input) return C.CBackendValidationTypedResult(self.ty, self.ty:c_validate(input)) end
function C.CBackendValidationGlobalFound:c_validation_type() return self.entry.global.ty end
function C.CBackendValidationGlobalMissing:c_validation_type() return C.CBackendVoid end

function C.CBackendPlaceLocal:c_validate(input) return input.locals:c_validation_lookup(self.local_id):c_validation_typed(input) end
function C.CBackendPlaceGlobal:c_validate(input)
  local found = input.relations.globals:c_validation_lookup(self.global)
  return C.CBackendValidationTypedResult(self.ty, found:c_validation_report())
end
function C.CBackendPlaceDeref:c_validate(input)
  local a = self.addr:c_validate(input)
  local r = a.report
  if self.align ~= nil and not valid_alignment(self.align) then r = report(r, issue(C.CBackendIssueInvalidAlignment("place-deref", self.align))) end
  return C.CBackendValidationTypedResult(self.ty, r)
end
function C.CBackendPlaceField:c_validate(input)
  local b = self.base:c_validate(input)
  local r = b.report
  if self.align ~= nil and not valid_alignment(self.align) then r = report(r, issue(C.CBackendIssueInvalidAlignment("place-field", self.align))) end
  return C.CBackendValidationTypedResult(self.ty, r)
end
function C.CBackendPlaceIndex:c_validate(input)
  local b, i = self.base:c_validate(input), self.index:c_validate(input)
  return C.CBackendValidationTypedResult(self.ty, report(b.report, i.report))
end
function C.CBackendPlacePtrIndex:c_validate(input)
  local b, i = self.base:c_validate(input), self.index:c_validate(input)
  return C.CBackendValidationTypedResult(self.ty, report(b.report, i.report))
end
function C.CBackendPlaceBytes:c_validate(input)
  local b = self.base:c_validate(input)
  local r = b.report
  if not valid_alignment(self.align) then r = report(r, issue(C.CBackendIssueInvalidAlignment("place-bytes", self.align))) end
  return C.CBackendValidationTypedResult(self.ty, r)
end

function C.CBackendRAtom:c_validate(input) return self.atom:c_validate(input) end
function C.CBackendRCompare:c_validate(input) local a,b=self.lhs:c_validate(input),self.rhs:c_validate(input); return C.CBackendValidationTypedResult(C.CBackendBool8, report(a.report,b.report,self.ty:c_validate(input))) end
function C.CBackendRCast:c_validate(input) local a=self.value:c_validate(input); return C.CBackendValidationTypedResult(self.to, report(a.report,self.to:c_validate(input))) end
function C.CBackendRSelect:c_validate(input) local c,t,e=self.cond:c_validate(input),self.then_value:c_validate(input),self.else_value:c_validate(input); return C.CBackendValidationTypedResult(self.ty,report(c.report,t.report,e.report)) end
function C.CBackendRFuncAddr:c_validate(input) return C.CBackendValidationTypedResult(C.CBackendCodePtr(self.sig),report(input.relations.functions:c_validation_lookup(self.func):c_validation_report(),input.relations.signatures:c_validation_lookup(self.sig):c_validation_report())) end
function C.CBackendRExternAddr:c_validate(input) return C.CBackendValidationTypedResult(C.CBackendCodePtr(self.sig),report(input.relations.externs:c_validation_lookup(self.extern):c_validation_report(),input.relations.signatures:c_validation_lookup(self.sig):c_validation_report())) end
function C.CBackendRPtrOffset:c_validate(input) local b,i=self.base:c_validate(input),self.index:c_validate(input); return C.CBackendValidationTypedResult(C.CBackendDataPtr(nil),report(b.report,i.report)) end
function C.CBackendRAddrOfPlace:c_validate(input) local p=self.place:c_validate(input); return C.CBackendValidationTypedResult(C.CBackendDataPtr(p.ty),p.report) end
function C.CBackendRValueBuiltin:c_validate(input)
  local rs={}; for i=1,#self.args do rs[#rs+1]=self.args[i]:c_validate(input).report end
  return C.CBackendValidationTypedResult(C.CBackendVoid, report(unpack(rs)))
end

local function typed_atoms(atoms, input)
  local rs={}; for i=1,#atoms do rs[#rs+1]=atoms[i]:c_validate(input).report end
  return report(unpack(rs))
end
local function destination_report(id, input)
  if id == nil then return clean() end
  return input.locals:c_validation_lookup(id):c_validation_write_typed(input).report
end
local function type_mismatch(site, place, expected, actual)
  if expected:c_validation_type_equal(actual) then return clean() end
  return issue(C.CBackendIssuePlaceTypeMismatch(site, place, expected, actual))
end

function C.CBackendAssign:c_validate(input)
  local rhs=self.rhs:c_validate(input); local dst=input.locals:c_validation_lookup(self.dst):c_validation_write_typed(input)
  local r=report(rhs.report,dst.report)
  if not dst.ty:c_validation_type_equal(rhs.ty) then r=report(r,issue(C.CBackendIssueCallResultType("assign",C.CBackendFuncSigId("validation.assign"),dst.ty,rhs.ty))) end
  return r
end
function C.CBackendHelperCall:c_validate(input)
  local found=input.relations.helpers:c_validation_lookup(self.helper)
  local fallback=C.CBackendHelperSignature({},C.CBackendVoid)
  local signature=found:c_validation_signature(fallback)
  local r=report(found:c_validation_report(),typed_atoms(self.args,input),destination_report(self.dst,input))
  local actual={}; for i=1,#self.args do actual[i]=self.args[i]:c_validate(input).ty end
  local mismatch=#actual~=#signature.params
  for i=1,math.min(#actual,#signature.params) do if not actual[i]:c_validation_type_equal(signature.params[i]) then mismatch=true end end
  if mismatch then r=report(r,issue(C.CBackendIssueHelperSignatureMismatch(self.helper,signature.params,actual))) end
  return r
end
function C.CBackendLoad:c_validate(input) local r=report(self.addr:c_validate(input).report,destination_report(self.dst,input)); if not valid_alignment(self.access.align) then r=report(r,issue(C.CBackendIssueInvalidAlignment("load",self.access.align))) end; return r end
function C.CBackendStore:c_validate(input) local r=typed_atoms({self.addr,self.value},input); if not valid_alignment(self.access.align) then r=report(r,issue(C.CBackendIssueInvalidAlignment("store",self.access.align))) end; return r end
function C.CBackendPlaceLoad:c_validate(input) local p=self.place:c_validate(input); local d=input.locals:c_validation_lookup(self.dst):c_validation_write_typed(input); return report(p.report,d.report,type_mismatch("place-load",self.place,d.ty,p.ty)) end
function C.CBackendPlaceStore:c_validate(input) local p,v=self.place:c_validate(input),self.value:c_validate(input); return report(p.report,v.report,type_mismatch("place-store",self.place,p.ty,v.ty)) end
function C.CBackendZeroInit:c_validate(input) local p=self.place:c_validate(input); return report(p.report,type_mismatch("zero-init",self.place,self.ty,p.ty)) end
function C.CBackendAggregateInit:c_validate(input) local p=self.place:c_validate(input); local atoms={}; for i=1,#self.fields do atoms[i]=self.fields[i].value end; return report(p.report,typed_atoms(atoms,input),type_mismatch("aggregate-init",self.place,self.ty,p.ty)) end
function C.CBackendArrayInit:c_validate(input) local p=self.place:c_validate(input); local atoms={}; for i=1,#self.elems do atoms[i]=self.elems[i].value end; return report(p.report,typed_atoms(atoms,input),type_mismatch("array-init",self.place,self.ty,p.ty)) end
function C.CBackendCall:c_validate(input) return report(typed_atoms(self.args,input),destination_report(self.dst,input),self.target:c_validate(input,self)) end
function C.CBackendComment:c_validate(input) return clean() end

local function call_signature(sig_id,input,call,site)
  local lookup=input.relations.signatures:c_validation_lookup(sig_id)
  local fallback=C.CBackendFuncSig(sig_id,{},C.CBackendVoid)
  local sig=lookup:c_validation_signature(fallback)
  local r=lookup:c_validation_report()
  if #call.args~=#sig.params then r=report(r,issue(C.CBackendIssueCallArgCount(site,sig_id,#sig.params,#call.args))) end
  for i=1,math.min(#call.args,#sig.params) do local a=call.args[i]:c_validate(input); if not a.ty:c_validation_type_equal(sig.params[i]) then r=report(r,issue(C.CBackendIssueCallArgType(site,sig_id,i,sig.params[i],a.ty))) end end
  return r
end
function C.CBackendCallDirect:c_validate(input,call) local f=input.relations.functions:c_validation_lookup(self.func); return report(f:c_validation_report(),f:c_validation_call(input,call)) end
function C.CBackendValidationFunctionFound:c_validation_call(input,call) return call_signature(self.entry.func.sig,input,call,"direct-call") end
function C.CBackendValidationFunctionMissing:c_validation_call(input,call) return clean() end
function C.CBackendCallExtern:c_validate(input,call) local e=input.relations.externs:c_validation_lookup(self.extern); return report(e:c_validation_report(),e:c_validation_call(input,call)) end
function C.CBackendValidationExternFound:c_validation_call(input,call) return call_signature(self.entry.extern.sig,input,call,"extern-call") end
function C.CBackendValidationExternMissing:c_validation_call(input,call) return clean() end
function C.CBackendCallIndirect:c_validate(input,call) local a=self.callee:c_validate(input); local r=report(a.report,call_signature(self.sig,input,call,"indirect-call")); if not a.ty:c_validation_is_code_pointer() then r=report(r,issue(C.CBackendIssueIndirectCallNonCodePtr("indirect-call",a.ty))) end; return r end
function C.CBackendCallClosure:c_validate(input,call) local a=self.closure:c_validate(input); return report(a.report,call_signature(self.sig,input,call,"closure-call")) end
function C.CBackendType:c_validation_is_code_pointer() return false end
function C.CBackendCodePtr:c_validation_is_code_pointer() return true end

local function transfer(label,args,input)
  local found=input.labels:c_validation_lookup(label); local fallback=C.CBackendBlock(label,{}, {},C.CBackendTrap)
  local block=found:c_validation_block(fallback); local r=report(found:c_validation_report(input.func),typed_atoms(args,input))
  if #args~=#block.params then r=report(r,issue(C.CBackendIssueBlockArgCount(input.func.name,label,#block.params,#args))) end
  for i=1,math.min(#args,#block.params) do local a=args[i]:c_validate(input); if not a.ty:c_validation_type_equal(block.params[i].ty) then r=report(r,issue(C.CBackendIssueBlockArgType(input.func.name,label,i,block.params[i].ty,a.ty))) end end
  return r
end
function C.CBackendGoto:c_validate(input) return transfer(self.dest,self.args,input) end
function C.CBackendIfGoto:c_validate(input) return report(self.cond:c_validate(input).report,transfer(self.then_dest,self.then_args,input),transfer(self.else_dest,self.else_args,input)) end
function C.CBackendSwitchGoto:c_validate(input) local rs={self.value:c_validate(input).report}; for i=1,#self.cases do rs[#rs+1]=self.cases[i]:c_validate(input) end; rs[#rs+1]=transfer(self.default_dest,self.default_args,input); return report(unpack(rs)) end
function C.CBackendSwitchCase:c_validate(input) return transfer(self.dest,self.args,input) end
function C.CBackendReturnVoid:c_validate(input) if input.signature.result:c_validation_type_equal(C.CBackendVoid) then return clean() end; return issue(C.CBackendIssueCallResultType("return",input.signature.id,input.signature.result,C.CBackendVoid)) end
function C.CBackendReturn:c_validate(input) local a=self.value:c_validate(input); local r=a.report; if not a.ty:c_validation_type_equal(input.signature.result) then r=report(r,issue(C.CBackendIssueCallResultType("return",input.signature.id,input.signature.result,a.ty))) end; return r end
function C.CBackendTrap:c_validate(input) return clean() end

function C.CBackendBodyBlocks:c_validate(input) local rs={}; for i=1,#self.blocks do rs[i]=self.blocks[i]:c_validate(input) end; return report(unpack(rs)) end
function C.CBackendBodyExec:c_validate(input) return self.fragment:c_validate(input) end
function C.CBackendBodyMixed:c_validate(input) local rs={}; for i=1,#self.blocks do rs[#rs+1]=self.blocks[i]:c_validate(input) end; for i=1,#self.fragments do rs[#rs+1]=self.fragments[i]:c_validate(input) end; return report(unpack(rs)) end
function C.CBackendExecSite:c_validate(input) local atoms={}; for i=1,#self.args do atoms[i]=self.args[i].atom end; return typed_atoms(atoms,input) end
function C.CBackendBlock:c_validate(input) local rs={}; for i=1,#self.stmts do rs[#rs+1]=self.stmts[i]:c_validate(input) end; rs[#rs+1]=self.term:c_validate(input); return report(unpack(rs)) end

-- Data and relocation leaves.
function C.CBackendDataZero:c_validate(input) if self.offset<0 or self.offset+self.size>input.global.size then return issue(C.CBackendIssueDataInitOutOfBounds(input.global.id,self.offset,self.size,input.global.size)) end; return clean() end
function C.CBackendDataBytes:c_validate(input) if self.offset<0 or self.offset+#self.bytes>input.global.size then return issue(C.CBackendIssueDataInitOutOfBounds(input.global.id,self.offset,#self.bytes,input.global.size)) end; return clean() end
function C.CBackendDataScalar:c_validate(input) local size=self.ty:c_validation_static_size(); if self.offset<0 or self.offset+size>input.global.size then return issue(C.CBackendIssueDataInitOutOfBounds(input.global.id,self.offset,size,input.global.size)) end; return self.ty:c_validate(input) end
function C.CBackendDataReloc:c_validate(input) local size=8; local r=self.target:c_validate(input.relations); if self.offset<0 or self.offset+size>input.global.size then r=report(r,issue(C.CBackendIssueDataInitOutOfBounds(input.global.id,self.offset,size,input.global.size))) end; return r end
function C.CBackendRelocGlobal:c_validate(relations) return relations.globals:c_validation_lookup(self.global):c_validation_report() end
function C.CBackendRelocFunc:c_validate(relations) return relations.functions:c_validation_lookup(self.func):c_validation_report() end
function C.CBackendRelocExtern:c_validate(relations) return relations.externs:c_validation_lookup(self.extern):c_validation_report() end
function C.CBackendType:c_validation_static_size() return 0 end
function C.CBackendVoid:c_validation_static_size() return 0 end
function C.CBackendBool8:c_validation_static_size() return 1 end
function C.CBackendIndex:c_validation_static_size() return 8 end
function C.CBackendScalar:c_validation_static_size() return self.scalar:c_validation_static_size() end
function Core.Scalar:c_validation_static_size() return 0 end
function Core.ScalarBool:c_validation_static_size() return 1 end
function Core.ScalarI8:c_validation_static_size() return 1 end
function Core.ScalarU8:c_validation_static_size() return 1 end
function Core.ScalarI16:c_validation_static_size() return 2 end
function Core.ScalarU16:c_validation_static_size() return 2 end
function Core.ScalarI32:c_validation_static_size() return 4 end
function Core.ScalarU32:c_validation_static_size() return 4 end
function Core.ScalarF32:c_validation_static_size() return 4 end
function Core.ScalarI64:c_validation_static_size() return 8 end
function Core.ScalarU64:c_validation_static_size() return 8 end
function Core.ScalarF64:c_validation_static_size() return 8 end
function Core.ScalarIndex:c_validation_static_size() return 8 end
function Core.ScalarRawPtr:c_validation_static_size() return 8 end
function C.CBackendDataPtr:c_validation_static_size() return 8 end
function C.CBackendQualifiedDataPtr:c_validation_static_size() return 8 end
function C.CBackendCodePtr:c_validation_static_size() return 8 end
function C.CBackendImportedCodePtr:c_validation_static_size() return 8 end

-- Every helper leaf owns target/alignment validation. Signatures are independently
-- leaf-owned by cemit_emit.lua.
local function helper_clean(self,input) return clean() end
C.CBackendHelperUnary.c_validate=helper_clean
C.CBackendHelperBoolNormalize.c_validate=helper_clean
C.CBackendHelperCast.c_validate=helper_clean
C.CBackendHelperPtrOffset.c_validate=helper_clean
C.CBackendHelperIntBinary.c_validate=helper_clean
C.CBackendHelperFloatBinary.c_validate=helper_clean
C.CBackendHelperDivRem.c_validate=helper_clean
C.CBackendHelperShift.c_validate=helper_clean
C.CBackendHelperIntrinsic.c_validate=helper_clean
C.CBackendHelperLoad.c_validate=helper_clean
C.CBackendHelperStore.c_validate=helper_clean
C.CBackendHelperMemcpy.c_validate=helper_clean
C.CBackendHelperMemset.c_validate=helper_clean
C.CBackendHelperMemcmp.c_validate=helper_clean
C.CBackendHelperTrap.c_validate=helper_clean
local function atomic_helper(self,input)
  if input.source.unit.target.dialect:c_emit_supports_c11_atomics() then return clean() end
  return issue(C.CBackendIssueInvalidTargetFeature(C.CBackendFeatureC11Atomics,"atomic helper requires C11 atomics"))
end
C.CBackendHelperAtomicLoad.c_validate=atomic_helper
C.CBackendHelperAtomicStore.c_validate=atomic_helper
C.CBackendHelperAtomicRmw.c_validate=atomic_helper
C.CBackendHelperAtomicCas.c_validate=atomic_helper
C.CBackendHelperAtomicFence.c_validate=atomic_helper
local function helper_alignment(self,input) if valid_alignment(self.align) then return clean() end; return issue(C.CBackendIssueInvalidAlignment("helper",self.align)) end
C.CBackendHelperTypedMemcpy.c_validate=helper_alignment; C.CBackendHelperTypedMemset.c_validate=helper_alignment; C.CBackendHelperScan.c_validate=helper_alignment; C.CBackendHelperFind.c_validate=helper_alignment; C.CBackendHelperReduce.c_validate=helper_alignment
function C.CBackendHelperLayoutAssert:c_validate(input) return clean() end
function C.CBackendHelperRequireFeature:c_validate(input) return issue(C.CBackendIssueInvalidTargetFeature(self.feature,self.reason)) end
function C.CBackendHelperUse:c_validate(input) return self.spec:c_validate(input) end

function C.CBackendTypedef:c_validate(input) return self.ty:c_validate(input) end
function C.CBackendStructDecl:c_validate(input) if self.size==nil or self.align==nil then return issue(C.CBackendIssueLayoutAssertionMissing(self.id)) end; if not valid_alignment(self.align) then return issue(C.CBackendIssueInvalidAlignment("struct",self.align)) end; return clean() end
function C.CBackendUnionDecl:c_validate(input) if self.size==nil or self.align==nil then return issue(C.CBackendIssueLayoutAssertionMissing(self.id)) end; if not valid_alignment(self.align) then return issue(C.CBackendIssueInvalidAlignment("union",self.align)) end; return clean() end
function C.CBackendOpaqueDecl:c_validate(input) return clean() end
function C.CBackendGlobal:c_validate(input) local rs={}; if not valid_c_name(self.name) then rs[#rs+1]=issue(C.CBackendIssueInvalidCName("global",self.name)) end; if not valid_alignment(self.align) then rs[#rs+1]=issue(C.CBackendIssueInvalidAlignment("global",self.align)) end; local data=C.CBackendValidationDataInput(input.relations,self); for i=1,#self.inits do rs[#rs+1]=self.inits[i]:c_validate(data) end; return report(unpack(rs)) end
function C.CBackendExtern:c_validate(input) local r=input.relations.signatures:c_validation_lookup(self.sig):c_validation_report(); if not valid_c_name(self.name) then r=report(r,issue(C.CBackendIssueInvalidCName("extern",self.name))) end; return r end

local function storage_for(input,func,id)
  for i=1,#input.source.storage do
    if input.source.storage[i].func==func.name then for j=1,#input.source.storage[i].storage do if input.source.storage[i].storage[j].id==id then return input.source.storage[i].storage[j] end end end
  end
  return C.CBackendLocalStorage(id,C.CBackendName(id.text),C.CBackendVoid,C.CBackendResidenceValue,C.CBackendLocalInitialized,false)
end
local function build_locals(input,func,duplicate_issues)
  local entries={}
  local function add(local_id,ty)
    for i=1,#entries do if entries[i].id==local_id then duplicate_issues[#duplicate_issues+1]=C.CBackendIssueDuplicateLocal(func.name,local_id) end end
    local s=storage_for(input,func,local_id)
    entries[#entries+1]=C.CBackendValidationLocalEntry(local_id,ty,s.init_state,s.residence,s.address_taken)
  end
  for i=1,#func.params do add(func.params[i].id,func.params[i].ty) end
  for i=1,#func.locals do add(func.locals[i].id,func.locals[i].ty) end
  for _,b in ipairs(func.body:c_validation_blocks()) do for i=1,#b.params do add(b.params[i].local_id,b.params[i].ty) end end
  return C.CBackendValidationLocalRelation(entries)
end
function C.CBackendBodyBlocks:c_validation_blocks() return self.blocks end
function C.CBackendBodyMixed:c_validation_blocks() return self.blocks end
function C.CBackendBodyExec:c_validation_blocks() return {} end
function C.CBackendFunc:c_validate(input)
  local sig_lookup=input.relations.signatures:c_validation_lookup(self.sig)
  local fallback=C.CBackendFuncSig(self.sig,{},C.CBackendVoid); local sig=sig_lookup:c_validation_signature(fallback)
  local duplicate_issues={}; local locals=build_locals(input,self,duplicate_issues); local label_entries={}
  local blocks=self.body:c_validation_blocks()
  for i=1,#blocks do for j=1,#label_entries do if label_entries[j].label==blocks[i].label then duplicate_issues[#duplicate_issues+1]=C.CBackendIssueDuplicateLabel(self.name,blocks[i].label) end end; label_entries[#label_entries+1]=C.CBackendValidationLabelEntry(blocks[i].label,blocks[i]) end
  local fin=C.CBackendValidationFunctionInput(input.relations,self,sig,locals,C.CBackendValidationLabelRelation(label_entries))
  local r=report(sig_lookup:c_validation_report(),C.CBackendValidationReport(duplicate_issues),self.body:c_validate(fin))
  if not valid_c_name(self.name) then r=report(r,issue(C.CBackendIssueInvalidCName("func",self.name))) end
  if #self.params~=#sig.params then r=report(r,issue(C.CBackendIssueCallArgCount("func",sig.id,#sig.params,#self.params))) end
  for i=1,math.min(#self.params,#sig.params) do if not self.params[i].ty:c_validation_type_equal(sig.params[i]) then r=report(r,issue(C.CBackendIssueFuncSigMismatch(self.name,sig.params[i],self.params[i].ty))) end end
  for i=1,#locals.entries do r=report(r,locals.entries[i].residence:c_validation_address_report(self,locals.entries[i])) end
  return r
end

function C.CBackendFuncSig:c_validate(input)
  local rs={}
  for i=1,#self.params do rs[#rs+1]=self.params[i]:c_validate(input) end
  rs[#rs+1]=self.result:c_validate(input)
  return report(unpack(rs))
end

local function build_relation(items,entry_ctor,item_key,entry_key,duplicate_ctor)
  local entries,issues={},{ }
  for i=1,#items do
    local k=item_key(items[i])
    for j=1,#entries do if entry_key(entries[j])==k then issues[#issues+1]=duplicate_ctor(k) end end
    entries[#entries+1]=entry_ctor(k,items[i])
  end
  return entries,issues
end
function C.CBackendUnit:c_validate(input)
  local se,si=build_relation(self.sigs,C.CBackendValidationSignatureEntry,function(x)return x.id end,function(x)return x.id end,C.CBackendIssueDuplicateSig)
  local fe,fi=build_relation(self.funcs,C.CBackendValidationFunctionEntry,function(x)return x.name end,function(x)return x.name end,C.CBackendIssueDuplicateFunc)
  local ge,gi=build_relation(self.globals,C.CBackendValidationGlobalEntry,function(x)return x.id end,function(x)return x.id end,C.CBackendIssueDuplicateGlobal)
  local ee,ei=build_relation(self.externs,C.CBackendValidationExternEntry,function(x)return x.name end,function(x)return x.name end,C.CBackendIssueDuplicateExtern)
  local he,hi=build_relation(self.helpers,C.CBackendValidationHelperEntry,function(x)return x.id end,function(x)return x.id end,C.CBackendIssueDuplicateHelper)
  local relations=C.CBackendValidationRelations(C.CBackendValidationSignatureRelation(se),C.CBackendValidationFunctionRelation(fe),C.CBackendValidationGlobalRelation(ge),C.CBackendValidationExternRelation(ee),C.CBackendValidationHelperRelation(he))
  local root=C.CBackendValidationUnitInput(input,relations)
  local rs={C.CBackendValidationReport(input.abi_issues),C.CBackendValidationReport(si),C.CBackendValidationReport(fi),C.CBackendValidationReport(gi),C.CBackendValidationReport(ei),C.CBackendValidationReport(hi)}
  for i=1,#self.sigs do rs[#rs+1]=self.sigs[i]:c_validate(root) end
  for i=1,#self.types do rs[#rs+1]=self.types[i]:c_validate(root) end
  for i=1,#self.globals do rs[#rs+1]=self.globals[i]:c_validate(root) end
  for i=1,#self.externs do rs[#rs+1]=self.externs[i]:c_validate(root) end
  for i=1,#self.helpers do rs[#rs+1]=self.helpers[i]:c_validate(root) end
  for i=1,#self.funcs do rs[#rs+1]=self.funcs[i]:c_validate(root) end
  return report(unpack(rs))
end

function C.CBackendValidationInput:c_validate()
  -- Relations are phase projections and are built only by the unit root.
  return self.unit:c_validate(self)
end

local M={}
function M.validate_input(input) return input:c_validate() end
function M.validate(unit) return C.CBackendValidationInput(unit,{},{}):c_validate() end
return M
