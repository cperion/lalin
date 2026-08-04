require("lalin.schema")

local Code = require("lalin.schema.code")
local CV = require("lalin.schema.code_validation")

local function append_issue(step, issue)
  local issues = {}
  for i = 1, #step.issues do issues[i] = step.issues[i] end
  issues[#issues + 1] = issue
  return CV.CodeValidationStep(issues)
end

local function append_step(left, right)
  local issues = {}
  for i = 1, #left.issues do issues[#issues + 1] = left.issues[i] end
  for i = 1, #right.issues do issues[#issues + 1] = right.issues[i] end
  return CV.CodeValidationStep(issues)
end

local function empty_step() return CV.CodeValidationStep({}) end

local function is_power_of_two(n)
  if type(n) ~= "number" or n < 1 or n % 1 ~= 0 then return false end
  while n > 1 do
    if n % 2 ~= 0 then return false end
    n = n / 2
  end
  return true
end

function Code.CodeModule:code_sig_projection()
  local entries = {}
  for i = 1, #self.sigs do entries[#entries + 1] = Code.CodeSigProjectionEntry(self.sigs[i].id, self.sigs[i]) end
  return Code.CodeSigProjection(entries)
end

function Code.CodeSigProjection:code_sig_lookup(id)
  for i = 1, #self.entries do
    if self.entries[i].sig_id == id then return Code.CodeSigLookupFound(self.entries[i].sig) end
  end
  return Code.CodeSigLookupMissing(id)
end

function CV.CodeValidationModuleProjection:code_function_lookup(id)
  for i = 1, #self.functions do if self.functions[i].id == id then return CV.CodeFunctionFound(self.functions[i]) end end
  return CV.CodeFunctionMissing(id)
end
function CV.CodeValidationModuleProjection:code_extern_lookup(id)
  for i = 1, #self.externs do if self.externs[i].id == id then return CV.CodeExternFound(self.externs[i]) end end
  return CV.CodeExternMissing(id)
end
function CV.CodeValidationModuleProjection:code_global_lookup(id)
  for i = 1, #self.globals do if self.globals[i].id == id then return CV.CodeGlobalFound(self.globals[i]) end end
  return CV.CodeGlobalMissing(id)
end
function CV.CodeValidationModuleProjection:code_data_lookup(id)
  for i = 1, #self.data do if self.data[i].id == id then return CV.CodeDataFound(self.data[i]) end end
  return CV.CodeDataMissing(id)
end
function CV.CodeValidationFunctionProjection:code_block_lookup(id)
  for i = 1, #self.blocks do if self.blocks[i].id == id then return CV.CodeBlockFound(self.blocks[i]) end end
  return CV.CodeBlockMissing(id)
end
function CV.CodeValidationFunctionProjection:code_local_lookup(id)
  for i = 1, #self.locals do if self.locals[i].id == id then return CV.CodeLocalFound(self.locals[i]) end end
  return CV.CodeLocalMissing(id)
end
function CV.CodeValidationFunctionProjection:code_value_type_lookup(value)
  for i = 1, #self.values do if self.values[i].value == value then return CV.CodeValueTypeFound(self.values[i]) end end
  return CV.CodeValueTypeMissing(value)
end

function CV.CodeFunctionFound:code_validation_step() return empty_step() end
function CV.CodeFunctionMissing:code_validation_step() return CV.CodeValidationStep({ Code.CodeIssueMissingFunc(self.id) }) end
function CV.CodeExternFound:code_validation_step() return empty_step() end
function CV.CodeExternMissing:code_validation_step() return CV.CodeValidationStep({ Code.CodeIssueMissingExtern(self.id) }) end
function CV.CodeGlobalFound:code_validation_step() return empty_step() end
function CV.CodeGlobalMissing:code_validation_step() return CV.CodeValidationStep({ Code.CodeIssueMissingGlobal(self.id) }) end
function CV.CodeDataFound:code_validation_step() return empty_step() end
function CV.CodeDataMissing:code_validation_step() return CV.CodeValidationStep({ Code.CodeIssueMissingData(self.id) }) end
function CV.CodeBlockFound:code_validation_step() return empty_step() end
function CV.CodeBlockMissing:code_validation_step() return CV.CodeValidationStep({ Code.CodeIssueMissingBlock(self.id) }) end
function CV.CodeLocalFound:code_validation_step() return empty_step() end
function CV.CodeLocalMissing:code_validation_step() return CV.CodeValidationStep({ Code.CodeIssueMissingLocal(self.id) }) end
function CV.CodeValueTypeFound:code_validation_step() return empty_step() end
function CV.CodeValueTypeMissing:code_validation_step() return CV.CodeValidationStep({ Code.CodeIssueMissingValue(self.value) }) end
function CV.CodeValueTypeFound:code_validation_expect(site, expected)
  if self.entry.ty == expected then return empty_step() end
  return CV.CodeValidationStep({ Code.CodeIssueTypeMismatch(site, expected, self.entry.ty) })
end
function CV.CodeValueTypeMissing:code_validation_expect(site, expected) return self:code_validation_step() end

function Code.CodeSigLookupFound:code_validation_step() return empty_step() end
function Code.CodeSigLookupMissing:code_validation_step() return CV.CodeValidationStep({ Code.CodeIssueMissingSig(self.sig_id) }) end
function Code.CodeSigLookupFound:code_validation_call_definition(dst)
  if dst ~= nil and #self.sig.results == 1 then return CV.CodeValidationDefinesValue(dst, self.sig.results[1]) end
  return CV.CodeValidationNoDefinition
end
function Code.CodeSigLookupMissing:code_validation_call_definition(dst) return CV.CodeValidationNoDefinition end

local function duplicate_id(entries, id)
  for i = 1, #entries do if entries[i].id == id then return true end end
  return false
end
function Code.CodeDataInit:code_validation_collect_reloc(result) return result end
function Code.CodeDataReloc:code_validation_collect_reloc(result)
  local entries, issues = {}, {}
  for i = 1, #result.projection.entries do entries[i] = result.projection.entries[i] end
  for i = 1, #result.issues do issues[i] = result.issues[i] end
  if duplicate_id(entries, self.reloc.id) then
    issues[#issues + 1] = Code.CodeIssueInvalidReloc(self.reloc, Code.RelocDuplicateId(self.reloc.id))
  else
    entries[#entries + 1] = CV.CodeRelocIdEntry(self.reloc.id, self.reloc)
  end
  return CV.CodeRelocProjectionResult(CV.CodeRelocProjection(entries), issues)
end
local function collect_relocs(containers)
  local result = CV.CodeRelocProjectionResult(CV.CodeRelocProjection({}), {})
  for i = 1, #containers do
    for j = 1, #containers[i].inits do result = containers[i].inits[j]:code_validation_collect_reloc(result) end
  end
  return result
end

function Code.CodeModule:code_validation_projection()
  local issues, funcs, externs, globals, data, relocs = {}, {}, {}, {}, {}, {}
  local sig_entries = {}
  for i = 1, #self.sigs do
    local sig = self.sigs[i]
    local duplicate = false
    for j = 1, #sig_entries do if sig_entries[j].sig_id == sig.id then duplicate = true end end
    if duplicate then issues[#issues + 1] = Code.CodeIssueDuplicateSig(sig.id)
    else sig_entries[#sig_entries + 1] = Code.CodeSigProjectionEntry(sig.id, sig) end
  end
  for i = 1, #self.funcs do
    local item = self.funcs[i]
    if duplicate_id(funcs, item.id) then issues[#issues + 1] = Code.CodeIssueDuplicateFunc(item.id)
    else funcs[#funcs + 1] = CV.CodeFunctionIdEntry(item.id, item) end
  end
  for i = 1, #self.externs do
    local item = self.externs[i]
    if duplicate_id(externs, item.id) then issues[#issues + 1] = Code.CodeIssueDuplicateExtern(item.id)
    else externs[#externs + 1] = CV.CodeExternIdEntry(item.id, item) end
  end
  for i = 1, #self.globals do
    local item = self.globals[i]
    if duplicate_id(globals, item.id) then issues[#issues + 1] = Code.CodeIssueDuplicateGlobal(item.id)
    else globals[#globals + 1] = CV.CodeGlobalIdEntry(item.id, item) end
  end
  for i = 1, #self.data do
    local item = self.data[i]
    if duplicate_id(data, item.id) then issues[#issues + 1] = Code.CodeIssueDuplicateData(item.id)
    else data[#data + 1] = CV.CodeDataIdEntry(item.id, item) end
  end
  local reloc_result = collect_relocs(self.data)
  local global_reloc_result = CV.CodeRelocProjectionResult(reloc_result.projection, reloc_result.issues)
  for i = 1, #self.globals do
    for j = 1, #self.globals[i].inits do global_reloc_result = self.globals[i].inits[j]:code_validation_collect_reloc(global_reloc_result) end
  end
  for i = 1, #global_reloc_result.issues do issues[#issues + 1] = global_reloc_result.issues[i] end
  local projection = CV.CodeValidationModuleProjection(self, Code.CodeSigProjection(sig_entries), funcs, externs, globals, data, global_reloc_result.projection.entries)
  return CV.CodeValidationProjectionResult(projection, issues)
end

function CV.CodeValidationNoDefinition:code_validation_project(entries, step) return entries, step end
function CV.CodeValidationDefinesValue:code_validation_project(entries, step)
  for i = 1, #entries do
    if entries[i].value == self.value then return entries, append_issue(step, Code.CodeIssueDuplicateValue(self.value)) end
  end
  entries[#entries + 1] = CV.CodeValueTypeEntry(self.value, self.ty)
  return entries, step
end

function Code.CodeFunc:code_validation_projection(module_projection)
  local issues, blocks, locals, values, insts, terms = {}, {}, {}, {}, {}, {}
  local step = empty_step()
  for i = 1, #self.params do
    local p = self.params[i]
    local def = CV.CodeValidationDefinesValue(p.value, p.ty)
    values, step = def:code_validation_project(values, step)
  end
  for i = 1, #self.locals do
    local item = self.locals[i]
    if duplicate_id(locals, item.id) then step = append_issue(step, Code.CodeIssueDuplicateLocal(item.id))
    else locals[#locals + 1] = CV.CodeLocalIdEntry(item.id, item) end
  end
  for i = 1, #self.blocks do
    local block = self.blocks[i]
    if duplicate_id(blocks, block.id) then step = append_issue(step, Code.CodeIssueDuplicateBlock(block.id))
    else blocks[#blocks + 1] = CV.CodeBlockIdEntry(block.id, block) end
    for j = 1, #block.params do
      local p = block.params[j]
      values, step = CV.CodeValidationDefinesValue(p.value, p.ty):code_validation_project(values, step)
    end
    for j = 1, #block.insts do
      local inst = block.insts[j]
      if duplicate_id(insts, inst.id) then step = append_issue(step, Code.CodeIssueDuplicateInst(inst.id))
      else insts[#insts + 1] = CV.CodeInstIdEntry(inst.id, inst) end
      values, step = inst.op:code_validation_definition(module_projection):code_validation_project(values, step)
    end
    if block.term ~= nil then
      if duplicate_id(terms, block.term.id) then step = append_issue(step, Code.CodeIssueDuplicateTerm(block.term.id))
      else terms[#terms + 1] = CV.CodeTermIdEntry(block.term.id, block.term) end
    end
  end
  return CV.CodeValidationFunctionProjection(self, blocks, locals, values, insts, terms), step
end

function Code.CodeInstOp:code_validation_definition(module_projection) return CV.CodeValidationNoDefinition end
function Code.CodeInstConst:code_validation_definition(input) return CV.CodeValidationDefinesValue(self.dst, self.const.ty) end
function Code.CodeInstAlias:code_validation_definition(input) return CV.CodeValidationDefinesValue(self.dst, self.ty) end
function Code.CodeInstUnary:code_validation_definition(input) return CV.CodeValidationDefinesValue(self.dst, self.ty) end
function Code.CodeInstBinary:code_validation_definition(input) return CV.CodeValidationDefinesValue(self.dst, self.ty) end
function Code.CodeInstFloatBinary:code_validation_definition(input) return CV.CodeValidationDefinesValue(self.dst, self.ty) end
function Code.CodeInstCompare:code_validation_definition(input) return CV.CodeValidationDefinesValue(self.dst, Code.CodeTyBool8) end
function Code.CodeInstCast:code_validation_definition(input) return CV.CodeValidationDefinesValue(self.dst, self.to) end
function Code.CodeInstSelect:code_validation_definition(input) return CV.CodeValidationDefinesValue(self.dst, self.ty) end
function Code.CodeInstIntrinsicValue:code_validation_definition(input) return CV.CodeValidationDefinesValue(self.dst, self.ty) end
function Code.CodeInstAddrOf:code_validation_definition(input) return CV.CodeValidationDefinesValue(self.dst, self.ptr_ty) end
function Code.CodeInstGlobalRef:code_validation_definition(input) return CV.CodeValidationDefinesValue(self.dst, self.ptr_ty) end
function Code.CodeInstPtrOffset:code_validation_definition(input) return CV.CodeValidationDefinesValue(self.dst, self.ptr_ty) end
function Code.CodeInstLoad:code_validation_definition(input) return CV.CodeValidationDefinesValue(self.dst, self.access.ty) end
function Code.CodeInstAggregate:code_validation_definition(input) return CV.CodeValidationDefinesValue(self.dst, self.ty) end
function Code.CodeInstArray:code_validation_definition(input) return CV.CodeValidationDefinesValue(self.dst, self.ty) end
function Code.CodeInstViewMake:code_validation_definition(input) return CV.CodeValidationDefinesValue(self.dst, Code.CodeTyView(self.elem_ty)) end
function Code.CodeInstViewData:code_validation_definition(input) return CV.CodeValidationDefinesValue(self.dst, Code.CodeTyDataPtr(nil)) end
function Code.CodeInstViewLen:code_validation_definition(input) return CV.CodeValidationDefinesValue(self.dst, Code.CodeTyIndex) end
function Code.CodeInstViewStride:code_validation_definition(input) return CV.CodeValidationDefinesValue(self.dst, Code.CodeTyIndex) end
function Code.CodeInstSliceMake:code_validation_definition(input) return CV.CodeValidationDefinesValue(self.dst, Code.CodeTySlice(self.elem_ty)) end
function Code.CodeInstSliceData:code_validation_definition(input) return CV.CodeValidationDefinesValue(self.dst, Code.CodeTyDataPtr(nil)) end
function Code.CodeInstSliceLen:code_validation_definition(input) return CV.CodeValidationDefinesValue(self.dst, Code.CodeTyIndex) end
function Code.CodeInstByteSpanMake:code_validation_definition(input) return CV.CodeValidationDefinesValue(self.dst, Code.CodeTyByteSpan) end
function Code.CodeInstByteSpanData:code_validation_definition(input) return CV.CodeValidationDefinesValue(self.dst, Code.CodeTyDataPtr(nil)) end
function Code.CodeInstByteSpanLen:code_validation_definition(input) return CV.CodeValidationDefinesValue(self.dst, Code.CodeTyIndex) end
function Code.CodeInstClosure:code_validation_definition(input) return CV.CodeValidationDefinesValue(self.dst, self.ty) end
function Code.CodeInstVariantCtor:code_validation_definition(input) return CV.CodeValidationDefinesValue(self.dst, self.ty) end
function Code.CodeInstVariantTag:code_validation_definition(input) return CV.CodeValidationDefinesValue(self.dst, self.tag_ty) end
function Code.CodeInstVariantPayload:code_validation_definition(input) return CV.CodeValidationDefinesValue(self.dst, self.variant.fields[self.field_index].ty) end
function Code.CodeInstCall:code_validation_definition(input) return input.signatures:code_sig_lookup(self.sig):code_validation_call_definition(self.dst) end
function Code.CodeInstAtomicLoad:code_validation_definition(input) return CV.CodeValidationDefinesValue(self.dst, self.access.ty) end
function Code.CodeInstAtomicRmw:code_validation_definition(input) return CV.CodeValidationDefinesValue(self.dst, self.access.ty) end
function Code.CodeInstAtomicCas:code_validation_definition(input) return CV.CodeValidationDefinesValue(self.dst, self.access.ty) end

local function value_present(input, value) return input.function_projection:code_value_type_lookup(value):code_validation_step() end
local function value_expect(input, value, site, ty) return input.function_projection:code_value_type_lookup(value):code_validation_expect(site, ty) end
local function values_present(input, values)
  local step = empty_step()
  for i = 1, #values do step = append_step(step, value_present(input, values[i])) end
  return step
end
local function check_align(input, access, site)
  if is_power_of_two(access.align) then return empty_step() end
  return CV.CodeValidationStep({ Code.CodeIssueInvalidMemoryAccess(site, access) })
end

function Code.CodePlaceLocal:code_validate_place(input)
  local step = input.function_projection:code_local_lookup(self.local_id):code_validation_step()
  local found = input.function_projection:code_local_lookup(self.local_id)
  return append_step(step, found:code_validate_place_type(self.ty, "place.local"))
end
function CV.CodeLocalFound:code_validate_place_type(ty, site)
  if self.entry.local_value.ty == ty then return empty_step() end
  return CV.CodeValidationStep({ Code.CodeIssueTypeMismatch(site, self.entry.local_value.ty, ty) })
end
function CV.CodeLocalMissing:code_validate_place_type(ty, site) return empty_step() end
function Code.CodePlaceGlobal:code_validate_place(input) return input.module_projection:code_global_lookup(self.global):code_validation_step() end
function Code.CodePlaceData:code_validate_place(input) return input.module_projection:code_data_lookup(self.data):code_validation_step() end
function Code.CodePlaceDeref:code_validate_place(input) return value_present(input, self.addr) end
function Code.CodePlaceField:code_validate_place(input) return self.base:code_validate_place(input) end
function Code.CodePlaceIndex:code_validate_place(input) return append_step(self.base:code_validate_place(input), value_present(input, self.index)) end
function Code.CodePlaceBytes:code_validate_place(input) return value_present(input, self.base) end

function Code.CodeGlobalRefFunc:code_validate_module_ref(projection) return projection:code_function_lookup(self.func):code_validation_step() end
function Code.CodeGlobalRefExtern:code_validate_module_ref(projection) return projection:code_extern_lookup(self.extern):code_validation_step() end
function Code.CodeGlobalRefGlobal:code_validate_module_ref(projection) return projection:code_global_lookup(self.global):code_validation_step() end
function Code.CodeGlobalRefData:code_validate_module_ref(projection) return projection:code_data_lookup(self.data):code_validation_step() end
function Code.CodeGlobalRefFunc:code_validate_global_ref(input) return self:code_validate_module_ref(input.module_projection) end
function Code.CodeGlobalRefExtern:code_validate_global_ref(input) return self:code_validate_module_ref(input.module_projection) end
function Code.CodeGlobalRefGlobal:code_validate_global_ref(input) return self:code_validate_module_ref(input.module_projection) end
function Code.CodeGlobalRefData:code_validate_global_ref(input) return self:code_validate_module_ref(input.module_projection) end

function Code.CodeCallDirect:code_validate_call_target(input) return input.module_projection:code_function_lookup(self.func):code_validation_step() end
function Code.CodeCallExtern:code_validate_call_target(input) return input.module_projection:code_extern_lookup(self.extern):code_validation_step() end
function Code.CodeCallIndirect:code_validate_call_target(input) return append_step(input.module_projection.signatures:code_sig_lookup(self.sig):code_validation_step(), value_present(input, self.callee)) end
function Code.CodeCallClosure:code_validate_call_target(input) return append_step(input.module_projection.signatures:code_sig_lookup(self.sig):code_validation_step(), value_present(input, self.closure)) end

function Code.CodeInst:code_validate(input) return self.op:code_validate(input) end
function Code.CodeInstOp:code_validate(input) return empty_step() end
function Code.CodeInstConst:code_validate(input) return self.const.ty:code_validate_type(input.module_projection) end
function Code.CodeInstAlias:code_validate(input) return value_expect(input, self.src, "alias", self.ty) end
function Code.CodeInstUnary:code_validate(input) return value_expect(input, self.value, "unary", self.ty) end
function Code.CodeInstBinary:code_validate(input) return append_step(value_expect(input, self.lhs, "binary.lhs", self.ty), value_expect(input, self.rhs, "binary.rhs", self.ty)) end
function Code.CodeInstFloatBinary:code_validate(input) return append_step(value_expect(input, self.lhs, "float_binary.lhs", self.ty), value_expect(input, self.rhs, "float_binary.rhs", self.ty)) end
function Code.CodeInstCompare:code_validate(input) return append_step(value_expect(input, self.lhs, "compare.lhs", self.operand_ty), value_expect(input, self.rhs, "compare.rhs", self.operand_ty)) end
function Code.CodeInstCast:code_validate(input) return value_expect(input, self.value, "cast", self.from) end
function Code.CodeInstSelect:code_validate(input)
  local step = value_expect(input, self.cond, "select.cond", Code.CodeTyBool8)
  step = append_step(step, value_expect(input, self.then_value, "select.then", self.ty))
  return append_step(step, value_expect(input, self.else_value, "select.else", self.ty))
end
function Code.CodeInstIntrinsicVoid:code_validate(input) return values_present(input, self.args) end
function Code.CodeInstIntrinsicValue:code_validate(input) return values_present(input, self.args) end
function Code.CodeInstAddrOf:code_validate(input) return self.place:code_validate_place(input) end
function Code.CodeInstGlobalRef:code_validate(input) return self.ref:code_validate_global_ref(input) end
function Code.CodeInstPtrOffset:code_validate(input) return append_step(value_present(input, self.base), value_present(input, self.index)) end
function Code.CodeInstLoad:code_validate(input) return append_step(self.place:code_validate_place(input), check_align(input, self.access, "load")) end
function Code.CodeInstStore:code_validate(input) return append_step(append_step(self.place:code_validate_place(input), value_expect(input, self.value, "store", self.access.ty)), check_align(input, self.access, "store")) end
function Code.CodeInstAggregate:code_validate(input)
  local values = {} for i = 1, #self.fields do values[i] = self.fields[i].value end
  return values_present(input, values)
end
function Code.CodeInstArray:code_validate(input)
  local values = {} for i = 1, #self.elems do values[i] = self.elems[i].value end
  return values_present(input, values)
end
function Code.CodeInstViewMake:code_validate(input) return append_step(value_present(input, self.data), append_step(value_present(input, self.len), value_present(input, self.stride))) end
function Code.CodeInstViewData:code_validate(input) return value_present(input, self.view) end
function Code.CodeInstViewLen:code_validate(input) return value_present(input, self.view) end
function Code.CodeInstViewStride:code_validate(input) return value_present(input, self.view) end
function Code.CodeInstSliceMake:code_validate(input) return append_step(value_present(input, self.data), value_present(input, self.len)) end
function Code.CodeInstSliceData:code_validate(input) return value_present(input, self.slice) end
function Code.CodeInstSliceLen:code_validate(input) return value_present(input, self.slice) end
function Code.CodeInstByteSpanMake:code_validate(input) return append_step(value_present(input, self.data), value_present(input, self.len)) end
function Code.CodeInstByteSpanData:code_validate(input) return value_present(input, self.span) end
function Code.CodeInstByteSpanLen:code_validate(input) return value_present(input, self.span) end
function Code.CodeInstClosure:code_validate(input) return append_step(input.module_projection.signatures:code_sig_lookup(self.sig):code_validation_step(), append_step(value_present(input, self.fn), value_present(input, self.ctx))) end
function Code.CodeInstVariantCtor:code_validate(input) return values_present(input, self.args) end
function Code.CodeInstVariantTag:code_validate(input) return value_present(input, self.value) end
function Code.CodeInstVariantPayload:code_validate(input) return value_present(input, self.value) end
function Code.CodeInstCall:code_validate(input)
  local lookup = input.module_projection.signatures:code_sig_lookup(self.sig)
  local step = append_step(lookup:code_validation_step(), self.target:code_validate_call_target(input))
  step = append_step(step, values_present(input, self.args))
  return append_step(step, lookup:code_validate_call_arity(self.args, self.dst))
end
function Code.CodeSigLookupMissing:code_validate_call_arity(args, dst) return empty_step() end
function Code.CodeSigLookupFound:code_validate_call_arity(args, dst)
  local step = empty_step()
  if #args ~= #self.sig.params then step = append_issue(step, Code.CodeIssueCallArity(self.sig.id, #self.sig.params, #args)) end
  return step
end
function Code.CodeInstAtomicLoad:code_validate(input) return append_step(self.place:code_validate_place(input), check_align(input, self.access, "atomic_load")) end
function Code.CodeInstAtomicStore:code_validate(input) return append_step(append_step(self.place:code_validate_place(input), value_expect(input, self.value, "atomic_store", self.access.ty)), check_align(input, self.access, "atomic_store")) end
function Code.CodeInstAtomicRmw:code_validate(input) return append_step(append_step(self.place:code_validate_place(input), value_expect(input, self.value, "atomic_rmw", self.access.ty)), check_align(input, self.access, "atomic_rmw")) end
function Code.CodeInstAtomicCas:code_validate(input) return append_step(append_step(self.place:code_validate_place(input), append_step(value_expect(input, self.expected, "atomic_cas.expected", self.access.ty), value_expect(input, self.replacement, "atomic_cas.replacement", self.access.ty))), check_align(input, self.access, "atomic_cas")) end
function Code.CodeInstAtomicFence:code_validate(input) return empty_step() end

function Code.CodeType:code_validate_type(module_projection) return empty_step() end
function Code.CodeTyCodePtr:code_validate_type(module_projection) return module_projection.signatures:code_sig_lookup(self.sig):code_validation_step() end
function Code.CodeTyClosure:code_validate_type(module_projection) return module_projection.signatures:code_sig_lookup(self.sig):code_validation_step() end
function Code.CodeTyDataPtr:code_validate_type(module_projection) if self.pointee == nil then return empty_step() end return self.pointee:code_validate_type(module_projection) end
function Code.CodeTyArray:code_validate_type(module_projection) return self.elem:code_validate_type(module_projection) end
function Code.CodeTySlice:code_validate_type(module_projection) return self.elem:code_validate_type(module_projection) end
function Code.CodeTyView:code_validate_type(module_projection) return self.elem:code_validate_type(module_projection) end
function Code.CodeTyVector:code_validate_type(module_projection) return self.elem:code_validate_type(module_projection) end
function Code.CodeTyLease:code_validate_type(module_projection) return self.base:code_validate_type(module_projection) end

local function validate_transfer(input, dest, args)
  local lookup = input.function_projection:code_block_lookup(dest)
  return lookup:code_validate_transfer(input, args)
end
function CV.CodeBlockMissing:code_validate_transfer(input, args) return self:code_validation_step() end
function CV.CodeBlockFound:code_validate_transfer(input, args)
  local block, step = self.entry.block, values_present(input, args)
  if #args ~= #block.params then step = append_issue(step, Code.CodeIssueJumpArity(block.id, #block.params, #args)) end
  local n = math.min(#args, #block.params)
  for i = 1, n do
    local value_lookup = input.function_projection:code_value_type_lookup(args[i])
    step = append_step(step, value_lookup:code_validate_block_param(block.id, i, block.params[i].ty))
  end
  return step
end
function CV.CodeValueTypeMissing:code_validate_block_param(block, index, expected) return empty_step() end
function CV.CodeValueTypeFound:code_validate_block_param(block, index, expected)
  if self.entry.ty == expected then return empty_step() end
  return CV.CodeValidationStep({ Code.CodeIssueBlockParamMismatch(block, index, expected, self.entry.ty) })
end

function Code.CodeTerm:code_validate(input) return self.op:code_validate(input) end
function Code.CodeTermJump:code_validate(input) return validate_transfer(input, self.dest, self.args) end
function Code.CodeTermBranch:code_validate(input) return append_step(value_expect(input, self.cond, "branch.cond", Code.CodeTyBool8), append_step(validate_transfer(input, self.then_dest, self.then_args), validate_transfer(input, self.else_dest, self.else_args))) end
function Code.CodeTermSwitch:code_validate(input)
  local step = value_present(input, self.value)
  for i = 1, #self.cases do step = append_step(step, validate_transfer(input, self.cases[i].dest, self.cases[i].args)) end
  return append_step(step, validate_transfer(input, self.default_dest, self.default_args))
end
function Code.CodeTermVariantSwitch:code_validate(input)
  local step = value_present(input, self.tag)
  for i = 1, #self.cases do step = append_step(step, validate_transfer(input, self.cases[i].dest, self.cases[i].args)) end
  return append_step(step, validate_transfer(input, self.default_dest, self.default_args))
end
function Code.CodeTermReturn:code_validate(input)
  local lookup = input.module_projection.signatures:code_sig_lookup(input.function_projection.func.sig)
  return append_step(values_present(input, self.values), lookup:code_validate_return(input, self.values))
end
function Code.CodeSigLookupMissing:code_validate_return(input, values) return empty_step() end
function Code.CodeSigLookupFound:code_validate_return(input, values)
  local step = empty_step()
  local n = math.min(#values, #self.sig.results)
  for i = 1, n do step = append_step(step, value_expect(input, values[i], "return", self.sig.results[i])) end
  return step
end
function Code.CodeTermTrap:code_validate(input) return empty_step() end
function Code.CodeTermUnreachable:code_validate(input) return empty_step() end

function Code.CodeBlock:code_validate(input)
  local step = empty_step()
  if self.term == nil then return append_issue(step, Code.CodeIssueUnterminatedBlock(self.id)) end
  for i = 1, #self.insts do
    step = append_step(step, self.insts[i]:code_validate(CV.CodeValidationInstructionInput(input.module_projection, input.function_projection, self, self.insts[i])))
  end
  return append_step(step, self.term:code_validate(CV.CodeValidationTermInput(input.module_projection, input.function_projection, self, self.term)))
end

function Code.CodeFunc:code_validate(input)
  local projection, step = self:code_validation_projection(input.projection)
  step = append_step(step, projection:code_block_lookup(self.entry):code_validation_step())
  step = append_step(step, input.projection.signatures:code_sig_lookup(self.sig):code_validation_step())
  for i = 1, #self.blocks do
    step = append_step(step, self.blocks[i]:code_validate(CV.CodeValidationBlockInput(input.projection, projection, self.blocks[i])))
  end
  return step
end

function Code.CodeReloc:code_validate(module_projection) return self.target:code_validate_module_ref(module_projection) end

function Code.CodeType:code_data_extent() return 0 end
function Code.CodeTyBool8:code_data_extent() return 1 end
function Code.CodeTyInt:code_data_extent() return self.bits / 8 end
function Code.CodeTyFloat:code_data_extent() return self.bits / 8 end
function Code.CodeTyIndex:code_data_extent() return 8 end
function Code.CodeTyDataPtr:code_data_extent() return 8 end
function Code.CodeTyCodePtr:code_data_extent() return 8 end
function Code.CodeTyClosure:code_data_extent() return 16 end

function Code.CodeDataInit:code_validate_data_init(module_projection, site, size) return empty_step() end
function Code.CodeDataZero:code_validate_data_init(module_projection, site, size)
  if self.offset >= 0 and self.size >= 0 and self.offset + self.size <= size then return empty_step() end
  return CV.CodeValidationStep({ Code.CodeIssueDataInitOutOfBounds(site, self.offset, self.size, size) })
end
function Code.CodeDataBytes:code_validate_data_init(module_projection, site, size)
  local extent = #self.bytes
  if self.offset >= 0 and self.offset + extent <= size then return empty_step() end
  return CV.CodeValidationStep({ Code.CodeIssueDataInitOutOfBounds(site, self.offset, extent, size) })
end
function Code.CodeDataScalar:code_validate_data_init(module_projection, site, size)
  local extent = self.ty:code_data_extent()
  if self.offset >= 0 and extent > 0 and self.offset + extent <= size then return self.ty:code_validate_type(module_projection) end
  return CV.CodeValidationStep({ Code.CodeIssueDataInitOutOfBounds(site, self.offset, extent, size) })
end
function Code.CodeDataReloc:code_validate_data_init(module_projection, site, size)
  local step = self.reloc:code_validate(module_projection)
  if self.reloc.offset >= 0 and self.reloc.offset + 8 <= size then return step end
  return append_issue(step, Code.CodeIssueDataInitOutOfBounds(site, self.reloc.offset, 8, size))
end

local function validate_inits(module_projection, site, size, inits)
  local step = empty_step()
  for i = 1, #inits do step = append_step(step, inits[i]:code_validate_data_init(module_projection, site, size)) end
  return step
end

function Code.CodeModule:code_validate()
  local projection_result = self:code_validation_projection()
  local step = CV.CodeValidationStep(projection_result.issues)
  local input = CV.CodeValidationModuleInput(projection_result.projection)
  for i = 1, #self.funcs do step = append_step(step, self.funcs[i]:code_validate(input)) end
  for i = 1, #self.externs do step = append_step(step, projection_result.projection.signatures:code_sig_lookup(self.externs[i].sig):code_validation_step()) end
  for i = 1, #self.types do step = append_step(step, self.types[i].ty:code_validate_type(projection_result.projection)) end
  for i = 1, #self.data do step = append_step(step, validate_inits(projection_result.projection, self.data[i].name, self.data[i].size, self.data[i].inits)) end
  for i = 1, #self.globals do
    local size = self.globals[i].size or 0
    step = append_step(step, validate_inits(projection_result.projection, self.globals[i].name, size, self.globals[i].inits))
  end
  if #step.issues == 0 then return CV.CodeValidateOk(self, projection_result.projection) end
  return CV.CodeValidateFailed(step.issues, projection_result.projection)
end

local function validate(module) return module:code_validate() end

return { validate = validate }
