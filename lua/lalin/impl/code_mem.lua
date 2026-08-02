-- impl/code_mem.lua — compute_mem methods on LalinCode, LalinGraph,
-- LalinFlow, LalinValue, LalinMem types. Produces LalinMem.MemSemanticFactSet
-- from a CodeGraph using typed projections and concrete leaf methods.
-- Entry: Graph.CodeGraph:compute_mem(module, flow, values, contracts)

require("lalin.schema_v2")
local Core   = require("lalin.schema_v2.core")
local Code   = require("lalin.schema_v2.code")
local Graph  = require("lalin.schema_v2.graph")
local Flow   = require("lalin.schema_v2.flow")
local Value  = require("lalin.schema_v2.value")
local Mem    = require("lalin.schema_v2.mem")

local function sanitize(s)
  s = tostring(s or "x"):gsub("[^%w_]", "_")
  if s:match("^%d") then s = "_" .. s end
  if s == "" then s = "x" end
  return s
end

local function append_one(xs, value)
  local out = {}
  for i = 1, #xs do out[i] = xs[i] end
  out[#out + 1] = value
  return out
end

local function append_all(xs, ys)
  local out = {}
  for i = 1, #xs do out[#out + 1] = xs[i] end
  for i = 1, #ys do out[#out + 1] = ys[i] end
  return out
end

----------------------------------------------------------------------
-- Immutable access/object/backend/proof projection
----------------------------------------------------------------------

function Mem.MemProof:project_access_proof() return Mem.MemProofAccessNone end
function Mem.MemProofBackend:project_access_proof()
  return Mem.MemProofAccessEntry(Mem.MemProofByAccessEntry(self.access, self))
end
function Mem.MemProofInterval:project_access_proof()
  return Mem.MemProofAccessEntry(Mem.MemProofByAccessEntry(self.interval.access, self))
end
function Mem.MemProofAccessNone:append_access_proof(entries) return entries end
function Mem.MemProofAccessEntry:append_access_proof(entries) return append_one(entries, self.entry) end

function Mem.MemSemanticFactSet:project_accesses()
  local access_entries, object_entries, backend_entries, proof_entries = {}, {}, {}, {}
  for _, access in ipairs(self.accesses) do access_entries = append_one(access_entries, Mem.MemAccessByIdEntry(access)) end
  for _, interval in ipairs(self.intervals) do object_entries = append_one(object_entries, Mem.MemObjectByAccessEntry(interval.access, interval.object)) end
  for _, backend in ipairs(self.backend_info) do backend_entries = append_one(backend_entries, Mem.MemBackendByAccessEntry(backend.access, backend)) end
  for _, proof in ipairs(self.proofs) do proof_entries = proof:project_access_proof():append_access_proof(proof_entries) end
  return Mem.MemAccessProjection(access_entries, object_entries, backend_entries, proof_entries)
end

function Mem.MemAccessProjection:mem_access(id)
  for _, entry in ipairs(self.access_by_id) do if entry.access.id == id then return Mem.MemAccessFound(entry.access) end end
  return Mem.MemAccessMissing(id)
end
function Mem.MemAccessProjection:object_for_access(id)
  for _, entry in ipairs(self.object_by_access) do if entry.access == id then return Mem.MemObjectFound(entry.object) end end
  return Mem.MemObjectMissing(id)
end
function Mem.MemAccessProjection:backend_for_access(id)
  for _, entry in ipairs(self.backend_by_access) do if entry.access == id then return Mem.MemBackendFound(entry.backend) end end
  return Mem.MemBackendMissing(id)
end
function Mem.MemAccessProjection:proof_for_access(id)
  for _, entry in ipairs(self.proof_by_access) do if entry.access == id then return Mem.MemProofFound(entry.proof) end end
  return Mem.MemProofMissing(id)
end

----------------------------------------------------------------------
-- CodeType memory projections
----------------------------------------------------------------------

function Code.CodeType:memory_object_elem_type() return self end
function Code.CodeTyDataPtr:memory_object_elem_type() return self.pointee end
function Code.CodeTyView:memory_object_elem_type() return self.elem end
function Code.CodeTySlice:memory_object_elem_type() return self.elem end
function Code.CodeTyByteSpan:memory_object_elem_type() return Code.CodeTyInt(8, Code.CodeUnsigned) end
function Code.CodeTyLease:memory_object_elem_type() return self.base:memory_object_elem_type() end
function Code.CodeType:memory_pointee_type() return self end
function Code.CodeTyDataPtr:memory_pointee_type() return self.pointee end
function Code.CodeTyLease:memory_pointee_type() return self.base:memory_pointee_type() end
function Code.CodeType:memory_deref_bytes() return Mem.MemDerefBytesUnavailable end
function Code.CodeTyBool8:memory_deref_bytes() return Mem.MemDerefBytesKnown(1) end
function Code.CodeTyIndex:memory_deref_bytes() return Mem.MemDerefBytesKnown(8) end
function Code.CodeTyInt:memory_deref_bytes() return Mem.MemDerefBytesKnown(math.max(1, math.floor(self.bits / 8))) end
function Code.CodeTyFloat:memory_deref_bytes() return Mem.MemDerefBytesKnown(math.max(1, math.floor(self.bits / 8))) end
function Code.CodeTyDataPtr:memory_deref_bytes() return Mem.MemDerefBytesKnown(8) end
function Code.CodeTyCodePtr:memory_deref_bytes() return Mem.MemDerefBytesKnown(8) end
function Code.CodeTyImportedCFuncPtr:memory_deref_bytes() return Mem.MemDerefBytesKnown(8) end
function Code.CodeTyLease:memory_deref_bytes() return self.base:memory_deref_bytes() end

----------------------------------------------------------------------
-- CodePlace leaf methods: stable keys and typed resolution
----------------------------------------------------------------------

function Code.CodePlace:code_mem_place_key()
  return tostring(self)
end

function Code.CodePlaceLocal:code_mem_place_key()
  return "local:" .. self.local_id.text
end

function Code.CodePlaceGlobal:code_mem_place_key()
  return "global:" .. self.global.text
end

function Code.CodePlaceData:code_mem_place_key()
  return "data:" .. self.data.text
end

function Code.CodePlaceDeref:code_mem_place_key()
  return "deref:" .. self.addr.text
end

function Code.CodePlaceField:code_mem_place_key()
  return "field:" .. tostring(self.offset or 0) .. ":" .. self.base:code_mem_place_key()
end

function Code.CodePlaceIndex:code_mem_place_key()
  return "index:" .. self.index.text .. ":" .. tostring(self.elem_size or 0) .. ":" .. self.base:code_mem_place_key()
end

function Code.CodePlaceBytes:code_mem_place_key()
  return "bytes:" .. self.base.text .. ":" .. tostring(self.offset or 0) .. ":" .. tostring(self.size or 0)
end

local function empty_discoveries() return Mem.MemPlaceDiscoveries({}, {}, {}) end
local function find_value_object(entries, value)
  for _, entry in ipairs(entries) do if entry.value == value then return Mem.MemValueObjectFound(entry.object) end end
  return Mem.MemValueObjectMissing(value)
end
local function find_local_object(entries, id)
  for _, entry in ipairs(entries) do if entry.local_id == id then return Mem.MemPlaceObjectFound(entry.object) end end
  return Mem.MemPlaceObjectMissing("local object is unavailable")
end
local function find_global_object(entries, id)
  for _, entry in ipairs(entries) do if entry.global == id then return Mem.MemPlaceObjectFound(entry.object) end end
  return Mem.MemPlaceObjectMissing("global object is unavailable")
end
local function find_data_object(entries, id)
  for _, entry in ipairs(entries) do if entry.data == id then return Mem.MemPlaceObjectFound(entry.object) end end
  return Mem.MemPlaceObjectMissing("data object is unavailable")
end

function Flow.FlowFactSet:project_inductions()
  local inductions = {}
  for _, loop in ipairs(self.loops) do
    for _, induction in ipairs(loop.inductions) do
      inductions[#inductions + 1] = induction
    end
  end
  return Flow.FlowInductionProjection(inductions)
end
function Flow.FlowInductionProjection:lookup(value)
  local matches = {}
  for _, induction in ipairs(self.inductions) do
    if induction.value == value then matches[#matches + 1] = induction end
  end
  if #matches == 0 then return Flow.FlowInductionMissing(value) end
  if #matches > 1 then return Flow.FlowInductionAmbiguous(value, #matches) end
  return Flow.FlowInductionFound(matches[1])
end
function Flow.FlowInductionFound:classify_memory_index(input)
  return Mem.MemIndexInduction(
    self.induction, input.value, input.elem_size, input.const_offset, 0)
end
function Flow.FlowFactSet:memory_induction_source(value)
  local found = {}
  for i = 1, #self.edges do
    for j = 1, #self.edges[i].args do
      local arg = self.edges[i].args[j]
      if arg.dst_param == value then found[#found + 1] = arg.src end
    end
  end
  if #found == 1 then return found[1] end
  return value
end
function Flow.FlowInductionFound:classify_memory_offset(input, offset)
  return Mem.MemIndexInduction(self.induction, input.value, input.elem_size,
    input.const_offset, offset.element_offset)
end
function Flow.FlowInductionMissing:classify_memory_offset(input, _offset)
  return Mem.MemIndexValue(input.value, input.elem_size, input.const_offset)
end
function Flow.FlowInductionAmbiguous:classify_memory_offset(input, _offset)
  return Mem.MemIndexValue(input.value, input.elem_size, input.const_offset)
end
function Flow.FlowInductionFound:classify_memory_alias(input, _projection)
  return Mem.MemIndexInduction(
    self.induction, input.value, input.elem_size, input.const_offset, 0)
end
function Flow.FlowInductionAmbiguous:classify_memory_alias(input, _projection)
  return Mem.MemIndexValue(input.value, input.elem_size, input.const_offset)
end
function Flow.FlowInductionMissing:classify_memory_alias(input, projection)
  local found = {}
  for i = 1, #input.offsets do
    if input.offsets[i].value == input.value then found[#found + 1] = input.offsets[i] end
  end
  if #found ~= 1 then
    return Mem.MemIndexValue(input.value, input.elem_size, input.const_offset)
  end
  local base = input.flow:memory_induction_source(found[1].base)
  return projection:lookup(base):classify_memory_offset(input, found[1])
end
function Flow.FlowInductionMissing:classify_memory_index(input, projection)
  local base = input.flow:memory_induction_source(input.value)
  return projection:lookup(base):classify_memory_alias(input, projection)
end
function Flow.FlowInductionAmbiguous:classify_memory_index(input, _projection)
  return Mem.MemIndexValue(input.value, input.elem_size, input.const_offset)
end
function Flow.FlowInductionProjection:classify_memory_index(input)
  return self:lookup(input.value):classify_memory_index(input, self)
end
function Mem.MemValueObjectFound:as_place_object(reason) return Mem.MemPlaceObjectFound(self.object) end
function Mem.MemValueObjectMissing:as_place_object(reason) return Mem.MemPlaceObjectMissing(reason) end
function Mem.MemPlaceObjectFound:resolve_place(base, index) return Mem.MemPlaceResolved(self.object, base, index, empty_discoveries()) end
function Mem.MemPlaceObjectMissing:resolve_place(base, index) return Mem.MemPlaceUnresolved(base, index, self.reason, empty_discoveries()) end
local function place_object_id(func, role, owner, offset)
  return Mem.MemObjectId(sanitize(func.text) .. ":" .. role .. ":" .. sanitize(owner.text) .. ":" .. tostring(offset))
end

function Code.CodePlaceLocal:resolve_memory_place(input)
  return find_local_object(input.locals, self.local_id):resolve_place(Mem.MemBaseLocal(self.local_id), Mem.MemIndexNone)
end
function Code.CodePlaceGlobal:resolve_memory_place(input)
  return find_global_object(input.globals, self.global):resolve_place(Mem.MemBaseGlobal(self.global), Mem.MemIndexNone)
end
function Code.CodePlaceData:resolve_memory_place(input)
  return find_data_object(input.data, self.data):resolve_place(Mem.MemBaseData(self.data), Mem.MemIndexNone)
end
function Code.CodePlaceDeref:resolve_memory_place(input)
  return find_value_object(input.values, self.addr):as_place_object("dereference value has no memory object"):resolve_place(Mem.MemBaseValue(self.addr), Mem.MemIndexNone)
end

function Mem.MemPlaceResolved:resolve_memory_index(place, input)
  local index = input.inductions:classify_memory_index(
    Mem.MemIndexClassifyInput(place.index, place.elem_size, 0,
      input.index_offsets, input.flow))
  return Mem.MemPlaceResolved(
    self.object, self.base, index, self.discoveries)
end
function Mem.MemPlaceUnresolved:resolve_memory_index(place, input) return self end
function Code.CodePlaceIndex:resolve_memory_place(input) return self.base:resolve_memory_place(input):resolve_memory_index(self, input) end

function Mem.MemPlaceResolved:resolve_memory_field(place, input)
  local id = place_object_id(input.func, "field", self.object, place.offset)
  local proof = Mem.MemProofObject(id, Mem.MemObjectBaseAddressStable)
  local object = Mem.MemObjectFact(id, input.func, Mem.MemObjectFieldProjection(self.object, place.field), Mem.MemProvProjection(self.object, Mem.MemProjectField, place.offset), place.ty, Mem.MemExtentBytes(place.size or 0, Mem.MemExtentByConstruction), Mem.MemStrideUnit)
  local relation = Mem.MemObjectSameStore(id, self.object, proof)
  local discoveries = Mem.MemPlaceDiscoveries(append_one(self.discoveries.objects, object), append_one(self.discoveries.relations, relation), append_one(self.discoveries.proofs, proof))
  return Mem.MemPlaceResolved(id, Mem.MemBaseProjection(self.base, Mem.MemProjectField, place.offset), self.index, discoveries)
end
function Mem.MemPlaceUnresolved:resolve_memory_field(place, input) return self end
function Code.CodePlaceField:resolve_memory_place(input) return self.base:resolve_memory_place(input):resolve_memory_field(self, input) end

function Mem.MemValueObjectMissing:resolve_byte_place(place, input)
  return Mem.MemPlaceUnresolved(Mem.MemBaseValue(place.base), Mem.MemIndexNone, "byte-place base has no memory object", empty_discoveries())
end
function Mem.MemValueObjectFound:resolve_byte_place(place, input)
  local parent = self.object
  local id = place_object_id(input.func, "bytes", parent, place.offset)
  local proof = Mem.MemProofObject(id, Mem.MemObjectBaseAddressStable)
  local object = Mem.MemObjectFact(id, input.func, Mem.MemObjectBytes(parent, place.offset, place.size), Mem.MemProvProjection(parent, Mem.MemProjectBytes, place.offset), place.ty, Mem.MemExtentBytes(place.size, Mem.MemExtentByConstruction), Mem.MemStrideUnit)
  local relation = Mem.MemObjectSameStore(id, parent, proof)
  return Mem.MemPlaceResolved(id, Mem.MemBaseProjection(Mem.MemBaseValue(place.base), Mem.MemProjectBytes, place.offset), Mem.MemIndexNone, Mem.MemPlaceDiscoveries({ object }, { relation }, { proof }))
end
function Code.CodePlaceBytes:resolve_memory_place(input) return find_value_object(input.values, self.base):resolve_byte_place(self, input) end

function Mem.MemObjectExtent:access_safety() return Mem.MemAccessSafetyUnproven("object extent is not proven") end
function Mem.MemExtentUnknown:access_safety() return Mem.MemAccessSafetyUnproven("object extent is unknown") end
function Mem.MemExtentElements:access_safety() return Mem.MemAccessSafetyProven("object has a typed element extent") end
function Mem.MemExtentBytes:access_safety() return Mem.MemAccessSafetyProven("object has a byte extent") end
function Mem.MemExtentContract:access_safety() return Mem.MemAccessSafetyProven("object extent is contract-proven") end
local function extent_safety(self, extent) return extent:access_safety() end
local function direct_safety() return Mem.MemAccessSafetyProven("direct storage object") end
function Mem.MemObjectParam:access_safety(extent) return extent_safety(self, extent) end
function Mem.MemObjectLocal:access_safety(extent) return direct_safety() end
function Mem.MemObjectGlobal:access_safety(extent) return direct_safety() end
function Mem.MemObjectData:access_safety(extent) return direct_safety() end
function Mem.MemObjectView:access_safety(extent) return extent_safety(self, extent) end
function Mem.MemObjectSlice:access_safety(extent) return extent_safety(self, extent) end
function Mem.MemObjectByteSpan:access_safety(extent) return extent_safety(self, extent) end
function Mem.MemObjectContract:access_safety(extent) return Mem.MemAccessSafetyProven("contract object") end
function Mem.MemObjectFieldProjection:access_safety(extent) return extent_safety(self, extent) end
function Mem.MemObjectPtrOffset:access_safety(extent) return extent_safety(self, extent) end
function Mem.MemObjectBytes:access_safety(extent) return extent_safety(self, extent) end
function Mem.MemObjectElement:access_safety(extent) return extent_safety(self, extent) end
function Mem.MemObjectFieldPointer:access_safety(extent) return extent_safety(self, extent) end
function Mem.MemObjectLease:access_safety(extent) return Mem.MemAccessSafetyProven("lease grant owns access") end
function Mem.MemObjectUnknown:access_safety(extent) return Mem.MemAccessSafetyUnproven("memory object form is unknown") end
function Mem.MemObjectFact:access_safety() return self.form:access_safety(self.extent) end

----------------------------------------------------------------------
-- CodeContractFact memory projection leaves
----------------------------------------------------------------------

function Code.CodeContractValueRef:project_memory_contract_expr() return Mem.MemContractValueKey(self.value) end
function Code.CodeContractPlaceLoad:project_memory_contract_expr() return Mem.MemContractPlaceKey(self.place) end

local function empty_contract_contribution()
  return Mem.MemContractContribution(
    {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {})
end

function Code.CodeContractBounds:project_memory_contract(input)
  local s = input.source
  return Mem.MemContractContribution(
    { Mem.MemContractBoundsEntry(s.func, self.base, self.len, s) },
    {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {})
end
function Code.CodeContractProjectionBounds:project_memory_contract(input)
  local s = input.source
  return Mem.MemContractContribution({},
    { Mem.MemContractProjectionBoundsEntry(
      s.func, self.base:project_memory_contract_expr(),
      self.len:project_memory_contract_expr(), s) },
    {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {})
end
function Code.CodeContractWindowBounds:project_memory_contract(input)
  local s = input.source
  return Mem.MemContractContribution({}, {},
    { Mem.MemContractWindowEntry(
      s.func, self.base, self.base_len, self.start, self.len, s) },
    {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {})
end
function Code.CodeContractDisjoint:project_memory_contract(input)
  local s = input.source
  return Mem.MemContractContribution(
    {}, {}, {}, {},
    { Mem.MemContractPairEntry(s.func, self.a, self.b, s) },
    {}, {}, {}, {}, {}, {}, {}, {}, {})
end
function Code.CodeContractSameLen:project_memory_contract(input)
  local s = input.source
  return Mem.MemContractContribution(
    {}, {}, {},
    { Mem.MemContractPairEntry(s.func, self.a, self.b, s) },
    {}, {}, {}, {}, {}, {}, {}, {}, {}, {})
end
function Code.CodeContractSoAComponent:project_memory_contract(input)
  local s = input.source
  return Mem.MemContractContribution(
    {}, {}, {}, {}, {},
    { Mem.MemContractSoAEntry(
      s.func, self.base, self.record_ty, self.field_name,
      self.component_index, s) },
    {}, {}, {}, {}, {}, {}, {}, {})
end

local function value_contract_contribution(slot, input, base)
  local fields = { {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {} }
  fields[slot] = { Mem.MemContractValueEntry(input.source.func, base, input.source) }
  return Mem.MemContractContribution(unpack(fields))
end
function Code.CodeContractNoAlias:project_memory_contract(input) return value_contract_contribution(7, input, self.base) end
function Code.CodeContractReadonly:project_memory_contract(input) return value_contract_contribution(8, input, self.base) end
function Code.CodeContractWriteonly:project_memory_contract(input) return value_contract_contribution(9, input, self.base) end
function Code.CodeContractInvalidate:project_memory_contract(input) return value_contract_contribution(12, input, self.base) end
function Code.CodeContractPreserve:project_memory_contract(input) return value_contract_contribution(13, input, self.base) end

local function projection_contract_contribution(slot, input, base)
  local fields = { {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {} }
  fields[slot] = { Mem.MemContractProjectionEntry(input.source.func, base:project_memory_contract_expr(), input.source) }
  return Mem.MemContractContribution(unpack(fields))
end
function Code.CodeContractProjectionReadonly:project_memory_contract(input) return projection_contract_contribution(10, input, self.base) end
function Code.CodeContractProjectionWriteonly:project_memory_contract(input) return projection_contract_contribution(11, input, self.base) end
function Code.CodeContractRejected:project_memory_contract(input)
  local s = input.source
  return Mem.MemContractContribution(
    {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {},
    { Mem.MemContractRejectedEntry(s.func, self.reason, s) })
end

local contract_fields = {
  "bounds", "projection_bounds", "windows", "same_lengths", "disjoint",
  "soa", "noalias", "readonly", "writeonly", "projection_readonly",
  "projection_writeonly", "invalidates", "preserves", "rejected",
}
local function merge_contract_contribution(a, b)
  local values = {}
  for i, name in ipairs(contract_fields) do values[i] = append_all(a[name], b[name]) end
  return Mem.MemContractContribution(unpack(values))
end
function Code.CodeFuncContractFact:project_memory_contract()
  return self.fact:project_memory_contract(Mem.MemContractProjectInput(self))
end
function Code.CodeContractFactSet:project_memory_contract()
  local result = empty_contract_contribution()
  for _, fact in ipairs(self.facts) do result = merge_contract_contribution(result, fact:project_memory_contract()) end
  return Mem.MemContractProjection(
    result.bounds, result.projection_bounds, result.windows,
    result.same_lengths, result.disjoint, result.soa, result.noalias,
    result.readonly, result.writeonly, result.projection_readonly,
    result.projection_writeonly, result.invalidates, result.preserves,
    result.rejected)
end

----------------------------------------------------------------------
-- CodeInstOp immutable transfer leaves
----------------------------------------------------------------------

function Mem.MemLoad:access_mode() return Mem.MemAccessModeRead end
function Mem.MemStore:access_mode() return Mem.MemAccessModeWrite end
function Mem.MemAtomicLoad:access_mode() return Mem.MemAccessModeRead end
function Mem.MemAtomicStore:access_mode() return Mem.MemAccessModeWrite end
function Mem.MemAtomicRmw:access_mode() return Mem.MemAccessModeReadWrite end
function Mem.MemAtomicCas:access_mode() return Mem.MemAccessModeReadWrite end

local function unchanged(input) return Mem.MemTransferUnchanged(input.facet) end
function Code.CodeInstUnary:transfer_memory(input) return unchanged(input) end
function Code.CodeInstFloatBinary:transfer_memory(input) return unchanged(input) end
function Code.CodeInstCompare:transfer_memory(input) return unchanged(input) end
function Code.CodeInstSelect:transfer_memory(input) return unchanged(input) end
function Code.CodeInstIntrinsicVoid:transfer_memory(input) return unchanged(input) end
function Code.CodeInstIntrinsicValue:transfer_memory(input) return unchanged(input) end
function Code.CodeInstAggregate:transfer_memory(input) return unchanged(input) end
function Code.CodeInstArray:transfer_memory(input) return unchanged(input) end
function Code.CodeInstClosure:transfer_memory(input) return unchanged(input) end
function Code.CodeInstVariantCtor:transfer_memory(input) return unchanged(input) end
function Code.CodeInstVariantTag:transfer_memory(input) return unchanged(input) end
function Code.CodeInstVariantPayload:transfer_memory(input) return unchanged(input) end
function Code.CodeInstCall:transfer_memory(input) return unchanged(input) end
function Code.CodeInstAtomicFence:transfer_memory(input) return unchanged(input) end

local function replace_values(facet, values)
  return Mem.MemTransferFacet(values, facet.locals, facet.constants, facet.index_offsets, facet.loaded_places, facet.scaled_strides, facet.objects, facet.accesses, facet.dependence_accesses, facet.intervals, facet.safety, facet.relations, facet.backend, facet.proofs)
end
local function replace_constants(facet, constants)
  return Mem.MemTransferFacet(facet.values, facet.locals, constants, facet.index_offsets, facet.loaded_places, facet.scaled_strides, facet.objects, facet.accesses, facet.dependence_accesses, facet.intervals, facet.safety, facet.relations, facet.backend, facet.proofs)
end
local function replace_scaled_strides(facet, strides)
  return Mem.MemTransferFacet(facet.values, facet.locals, facet.constants, facet.index_offsets, facet.loaded_places, strides, facet.objects, facet.accesses, facet.dependence_accesses, facet.intervals, facet.safety, facet.relations, facet.backend, facet.proofs)
end
local function find_transfer_object(facet, value) return find_value_object(facet.values, value) end
function Mem.MemValueObjectFound:bind_transfer_object(input, dst)
  return Mem.MemTransferUpdated(replace_values(input.facet, append_one(input.facet.values, Mem.MemValueObjectEntry(dst, self.object))))
end
function Mem.MemValueObjectMissing:bind_transfer_object(input, dst) return unchanged(input) end
function Mem.MemPlaceObjectFound:bind_transfer_object(input, dst) return Mem.MemValueObjectFound(self.object):bind_transfer_object(input, dst) end
function Mem.MemPlaceObjectMissing:bind_transfer_object(input, dst) return unchanged(input) end
function Code.CodeInstAlias:transfer_memory(input) return find_transfer_object(input.facet, self.src):bind_transfer_object(input, self.dst) end
function Code.CodeInstCast:transfer_memory(input) return find_transfer_object(input.facet, self.value):bind_transfer_object(input, self.dst) end
function Code.CodeInstViewData:transfer_memory(input) return find_transfer_object(input.facet, self.view):bind_transfer_object(input, self.dst) end
function Code.CodeInstViewLen:transfer_memory(input) return unchanged(input) end
function Code.CodeInstViewStride:transfer_memory(input) return unchanged(input) end
function Code.CodeInstSliceData:transfer_memory(input) return find_transfer_object(input.facet, self.slice):bind_transfer_object(input, self.dst) end
function Code.CodeInstSliceLen:transfer_memory(input) return unchanged(input) end
function Code.CodeInstByteSpanData:transfer_memory(input) return find_transfer_object(input.facet, self.span):bind_transfer_object(input, self.dst) end
function Code.CodeInstByteSpanLen:transfer_memory(input) return unchanged(input) end
function Core.LitInt:project_memory_constant() return Mem.MemConstantKnown(tonumber(self.raw)) end
function Core.LitFloat:project_memory_constant() return Mem.MemConstantKnown(tonumber(self.raw)) end
function Core.LitBool:project_memory_constant() return Mem.MemConstantKnown(self.value and 1 or 0) end
function Core.LitString:project_memory_constant() return Mem.MemConstantUnavailable end
function Core.LitNil:project_memory_constant() return Mem.MemConstantUnavailable end
function Code.CodeConstLiteral:project_memory_constant() return self.literal:project_memory_constant() end
function Code.CodeConstNull:project_memory_constant() return Mem.MemConstantUnavailable end
function Code.CodeConstUndef:project_memory_constant() return Mem.MemConstantUnavailable end
function Mem.MemConstantKnown:transfer_constant(op, input)
  return Mem.MemTransferUpdated(replace_constants(input.facet, append_one(input.facet.constants, Mem.MemConstantEntry(op.dst, self.number_value))))
end
function Mem.MemConstantUnavailable:transfer_constant(op, input) return unchanged(input) end
function Code.CodeInstConst:transfer_memory(input) return self.const:project_memory_constant():transfer_constant(self, input) end
local function find_constant(facet, value)
  for _, entry in ipairs(facet.constants) do if entry.value == value then return Mem.MemConstantKnown(entry.number_value) end end
  return Mem.MemConstantUnavailable
end
local function replace_index_offsets(facet, offsets)
  return Mem.MemTransferFacet(facet.values, facet.locals, facet.constants, offsets,
    facet.loaded_places, facet.scaled_strides, facet.objects, facet.accesses,
    facet.dependence_accesses, facet.intervals, facet.safety, facet.relations,
    facet.backend, facet.proofs)
end
function Mem.MemConstantKnown:transfer_cast_constant(op, input)
  return Mem.MemTransferUpdated(replace_constants(input.facet,
    append_one(input.facet.constants, Mem.MemConstantEntry(op.dst, self.number_value))))
end
function Mem.MemConstantUnavailable:transfer_cast_constant(op, input)
  return find_transfer_object(input.facet, op.value):bind_transfer_object(input, op.dst)
end
function Code.CodeInstCast:transfer_memory(input)
  return find_constant(input.facet, self.value):transfer_cast_constant(self, input)
end
function Mem.MemConstantKnown:record_index_add(op, base, input)
  return Mem.MemTransferUpdated(replace_index_offsets(input.facet,
    append_one(input.facet.index_offsets,
      Mem.MemIndexOffsetEntry(op.dst, base, self.number_value))))
end
function Mem.MemConstantUnavailable:record_index_add(op, _base, input)
  return find_constant(input.facet, op.lhs):record_index_add_left(op, input)
end
function Mem.MemConstantKnown:record_index_add_left(op, input)
  return self:record_index_add(op, op.rhs, input)
end
function Mem.MemConstantUnavailable:record_index_add_left(_op, input)
  return unchanged(input)
end
function Mem.MemConstantKnown:record_index_sub(op, input)
  return Mem.MemTransferUpdated(replace_index_offsets(input.facet,
    append_one(input.facet.index_offsets,
      Mem.MemIndexOffsetEntry(op.dst, op.lhs, -self.number_value))))
end
function Mem.MemConstantUnavailable:record_index_sub(op, input)
  return unchanged(input)
end
function Mem.MemConstantKnown:multiply_stride(other) return other:multiply_known_stride(self.number_value) end
function Mem.MemConstantUnavailable:multiply_stride(other) return Mem.MemScaledStrideDynamic end
function Mem.MemConstantKnown:multiply_known_stride(value) return Mem.MemScaledStrideKnown(value * self.number_value) end
function Mem.MemConstantUnavailable:multiply_known_stride(value) return Mem.MemScaledStrideDynamic end
local function unchanged_binary(op, input) return unchanged(input) end
function Core.BinAdd:transfer_memory_binary(op, input)
  return find_constant(input.facet, op.rhs):record_index_add(op, op.lhs, input)
end
function Core.BinSub:transfer_memory_binary(op, input)
  return find_constant(input.facet, op.rhs):record_index_sub(op, input)
end
function Core.BinMul:transfer_memory_binary(op, input)
  local stride = find_constant(input.facet, op.lhs):multiply_stride(find_constant(input.facet, op.rhs))
  local next_strides = append_one(input.facet.scaled_strides, Mem.MemScaledStrideEntry(op.dst, stride))
  return Mem.MemTransferUpdated(replace_scaled_strides(input.facet, next_strides))
end
function Core.BinDiv:transfer_memory_binary(op, input) return unchanged_binary(op, input) end
function Core.BinRem:transfer_memory_binary(op, input) return unchanged_binary(op, input) end
function Core.BinBitAnd:transfer_memory_binary(op, input) return unchanged_binary(op, input) end
function Core.BinBitOr:transfer_memory_binary(op, input) return unchanged_binary(op, input) end
function Core.BinBitXor:transfer_memory_binary(op, input) return unchanged_binary(op, input) end
function Core.BinShl:transfer_memory_binary(op, input) return unchanged_binary(op, input) end
function Core.BinLShr:transfer_memory_binary(op, input) return unchanged_binary(op, input) end
function Core.BinAShr:transfer_memory_binary(op, input) return unchanged_binary(op, input) end
function Code.CodeInstBinary:transfer_memory(input) return self.op:transfer_memory_binary(self, input) end

function Code.CodeGlobalRefGlobal:memory_referenced_object(input) return find_global_object(input.globals, self.global) end
function Code.CodeGlobalRefData:memory_referenced_object(input) return find_data_object(input.data, self.data) end
function Code.CodeGlobalRefFunc:memory_referenced_object(input) return Mem.MemPlaceObjectMissing("function reference is not a memory object") end
function Code.CodeGlobalRefExtern:memory_referenced_object(input) return Mem.MemPlaceObjectMissing("extern reference is not a memory object") end
function Code.CodeInstGlobalRef:transfer_memory(input) return self.ref:memory_referenced_object(input):bind_transfer_object(input, self.dst) end
function Code.CodeInstAddrOf:transfer_memory(input)
  local place_input = Mem.MemPlaceResolveInput(
    input.func.id, input.facet.values, input.facet.locals, input.globals,
    input.data, input.facet.objects, input.inductions,
    input.facet.index_offsets, input.flow)
  return self.place:resolve_memory_place(place_input):bind_transfer_value(input, self.dst)
end
function Mem.MemPlaceResolved:bind_transfer_value(input, dst) return Mem.MemValueObjectFound(self.object):bind_transfer_object(input, dst) end
function Mem.MemPlaceUnresolved:bind_transfer_value(input, dst) return unchanged(input) end

local function append_object_projection(input, dst, object, form, provenance, elem_ty, extent, stride)
  local fact = Mem.MemObjectFact(object, input.func.id, form, provenance, elem_ty, extent, stride)
  local facet = input.facet
  local next_facet = Mem.MemTransferFacet(append_one(facet.values, Mem.MemValueObjectEntry(dst, object)), facet.locals, facet.constants, facet.index_offsets, facet.loaded_places, facet.scaled_strides, append_one(facet.objects, fact), facet.accesses, facet.dependence_accesses, facet.intervals, facet.safety, facet.relations, facet.backend, facet.proofs)
  return Mem.MemTransferUpdated(next_facet)
end
function Mem.MemValueObjectMissing:transfer_pointer_offset(op, input) return unchanged(input) end
function Mem.MemValueObjectFound:transfer_pointer_offset(op, input)
  local id = Mem.MemObjectId("ptr-offset:" .. op.dst.text)
  local index = input.inductions:classify_memory_index(
    Mem.MemIndexClassifyInput(op.index, op.elem_size, op.const_offset,
      input.facet.index_offsets, input.flow))
  return append_object_projection(input, op.dst, id,
    Mem.MemObjectPtrOffset(self.object, index, op.elem_size),
    Mem.MemProvProjection(self.object, Mem.MemProjectPtrOffset, op.const_offset),
    op.ptr_ty:memory_pointee_type(),
    Mem.MemExtentUnknown(Mem.MemExtentDynamicAllocation), Mem.MemStrideUnit)
end
function Code.CodeInstPtrOffset:transfer_memory(input) return find_transfer_object(input.facet, self.base):transfer_pointer_offset(self, input) end
function Code.CodeInstViewMake:transfer_memory(input)
  local id = Mem.MemObjectId("view:" .. self.dst.text)
  return append_object_projection(input, self.dst, id, Mem.MemObjectView, Mem.MemProvView(self.dst, self.data, self.len, self.stride), self.elem_ty, Mem.MemExtentElements(self.len, self.elem_ty, Mem.MemExtentByConstruction), Mem.MemStrideValue(self.stride))
end
function Code.CodeInstSliceMake:transfer_memory(input)
  local id = Mem.MemObjectId("slice:" .. self.dst.text)
  return append_object_projection(input, self.dst, id, Mem.MemObjectSlice, Mem.MemProvSlice(self.dst, self.data, self.len), self.elem_ty, Mem.MemExtentElements(self.len, self.elem_ty, Mem.MemExtentByConstruction), Mem.MemStrideUnit)
end
function Code.CodeInstByteSpanMake:transfer_memory(input)
  local id = Mem.MemObjectId("bytespan:" .. self.dst.text)
  local u8 = Code.CodeTyInt(8, Code.CodeUnsigned)
  return append_object_projection(input, self.dst, id, Mem.MemObjectByteSpan, Mem.MemProvByteSpan(self.dst, self.data, self.len), u8, Mem.MemExtentElements(self.len, u8, Mem.MemExtentByConstruction), Mem.MemStrideUnit)
end

local function safety_for_object(objects, id)
  for _, fact in ipairs(objects) do if fact.id == id then return fact:access_safety() end end
  return Mem.MemAccessSafetyUnproven("resolved object fact is unavailable")
end
function Code.CodeMayTrap:memory_trap(safety) return Mem.MemMayTrap end
function Code.CodeMustNotTrap:memory_trap(safety) return Mem.MemNonTrapping("access is declared must-not-trap") end
function Code.CodeCheckedTrap:memory_trap(safety) return Mem.MemCheckedTrap("access is explicitly checked") end
function Mem.MemAccessSafetyProven:memory_bounds() return Mem.MemBoundsInObject(self.reason) end
function Mem.MemAccessSafetyUnproven:memory_bounds() return Mem.MemBoundsUnknown(self.reason) end
function Mem.MemAccessSafetyProven:refine_trap(trap) return Mem.MemNonTrapping(self.reason) end
function Mem.MemAccessSafetyUnproven:refine_trap(trap) return trap end
function Mem.MemPlaceResolved:memory_safety(input) return safety_for_object(input.facet.objects, self.object) end
function Mem.MemPlaceUnresolved:memory_safety(input) return Mem.MemAccessSafetyUnproven(self.reason) end
function Mem.MemPlaceResolved:memory_object_lookup() return Mem.MemObjectFound(self.object) end
function Mem.MemPlaceUnresolved:memory_object_lookup() return Mem.MemObjectMissing(Mem.MemAccessId("unresolved-place")) end

function Mem.MemMayTrap:movement_decision(access, op, safety) return Mem.MemMovementPinned("potentially trapping accesses cannot move") end
function Mem.MemCheckedTrap:movement_decision(access, op, safety) return Mem.MemMovementPinned("checked trapping order must be preserved") end
function Mem.MemNonTrapping:movement_decision(access, op, safety) return op:nontrapping_movement(access, safety) end
local function ordinary_movement(access, safety)
  if access.volatile then return Mem.MemMovementPinned("volatile access order is observable") end
  if access.ordering then return Mem.MemMovementPinned("ordered access cannot move") end
  return safety:movement_decision()
end
function Mem.MemAccessSafetyProven:movement_decision() return Mem.MemMovementMovable(self.reason) end
function Mem.MemAccessSafetyUnproven:movement_decision() return Mem.MemMovementPinned(self.reason) end
function Mem.MemLoad:nontrapping_movement(access, safety) return ordinary_movement(access, safety) end
function Mem.MemStore:nontrapping_movement(access, safety) return ordinary_movement(access, safety) end
function Mem.MemAtomicLoad:nontrapping_movement(access, safety) return Mem.MemMovementPinned("atomic load ordering is observable") end
function Mem.MemAtomicStore:nontrapping_movement(access, safety) return Mem.MemMovementPinned("atomic store ordering is observable") end
function Mem.MemAtomicRmw:nontrapping_movement(access, safety) return Mem.MemMovementPinned("atomic read-modify-write is indivisible") end
function Mem.MemAtomicCas:nontrapping_movement(access, safety) return Mem.MemMovementPinned("atomic compare-exchange is indivisible") end

local function transfer_access(op_node, input, op, place, access)
  local facet = input.facet
  local place_input = Mem.MemPlaceResolveInput(
    input.func.id, facet.values, facet.locals, input.globals, input.data,
    facet.objects, input.inductions, facet.index_offsets, input.flow)
  local resolved = place:resolve_memory_place(place_input)
  local safety_decision = resolved:memory_safety(input)
  local trap = safety_decision:refine_trap(access.trap:memory_trap(safety_decision))
  local bounds = safety_decision:memory_bounds()
  local alignment = Mem.MemAlignKnown(access.align)
  local id = Mem.MemAccessId("access:" .. input.func.name .. ":" .. input.block.id.text .. ":" .. input.inst.id.text)
  local fact = Mem.MemAccessFact(id, input.func.id, Graph.GraphBlockId(input.func.id, input.block.id), input.inst.id, op, place, access, resolved.base, resolved.index, Mem.MemAccessScalar, alignment, bounds, trap)
  local proof = Mem.MemProofBackend(id, Mem.MemBackendNativeAlignment(access.align))
  local movement = trap:movement_decision(access, op, safety_decision)
  local backend = Mem.MemBackendAccessInfo(id, trap, alignment, bounds, access.ty:memory_deref_bytes(), movement, { proof })
  local dependence = Mem.MemDependenceAccess(fact, resolved:memory_object_lookup(), input.loop, safety_decision, #facet.dependence_accesses + 1)
  local loaded = facet.loaded_places
  if op == Mem.MemLoad or op == Mem.MemAtomicLoad then loaded = append_one(loaded, Mem.MemLoadedPlaceEntry(place, op_node.dst)) end
  local next_facet = Mem.MemTransferFacet(facet.values, facet.locals, facet.constants, facet.index_offsets, loaded, facet.scaled_strides, append_all(facet.objects, resolved.discoveries.objects), append_one(facet.accesses, fact), append_one(facet.dependence_accesses, dependence), facet.intervals, facet.safety, append_all(facet.relations, resolved.discoveries.relations), append_one(facet.backend, backend), append_all(append_one(facet.proofs, proof), resolved.discoveries.proofs))
  return Mem.MemTransferUpdated(next_facet)
end
function Code.CodeInstLoad:transfer_memory(input) return transfer_access(self, input, Mem.MemLoad, self.place, self.access) end
function Code.CodeInstStore:transfer_memory(input) return transfer_access(self, input, Mem.MemStore, self.place, self.access) end
function Code.CodeInstAtomicLoad:transfer_memory(input) return transfer_access(self, input, Mem.MemAtomicLoad, self.place, self.access) end
function Code.CodeInstAtomicStore:transfer_memory(input) return transfer_access(self, input, Mem.MemAtomicStore, self.place, self.access) end
function Code.CodeInstAtomicRmw:transfer_memory(input) return transfer_access(self, input, Mem.MemAtomicRmw, self.place, self.access) end
function Code.CodeInstAtomicCas:transfer_memory(input) return transfer_access(self, input, Mem.MemAtomicCas, self.place, self.access) end

function Mem.MemTransferUpdated:next_facet() return self.facet end
function Mem.MemTransferUnchanged:next_facet() return self.facet end

local function disjoint_pair(relations, a, b)
  for _, entry in ipairs(relations.disjoint) do
    if (entry.a == a and entry.b == b) or (entry.a == b and entry.b == a) then return entry.proof end
  end
end
function Mem.MemAccessModeRead:classify_access_modes(other, request) return other:classify_after_read(request) end
function Mem.MemAccessModeWrite:classify_access_modes(other, request) return other:classify_after_write(request) end
function Mem.MemAccessModeReadWrite:classify_access_modes(other, request) return other:classify_after_write(request) end
function Mem.MemAccessModeRead:classify_after_read(request)
  local ids = { request.before.access.id, request.after.access.id }
  local proof = Mem.MemProofNoDependence(ids, Mem.MemNoDependenceReadOnly(request.before.access.id))
  return Mem.MemObjectPairIndependent(proof, "two reads do not create a dependence")
end
function Mem.MemAccessModeWrite:classify_after_read(request) return Mem.MemObjectPairDependent("read followed by write may conflict") end
function Mem.MemAccessModeReadWrite:classify_after_read(request) return Mem.MemObjectPairDependent("read followed by read-write may conflict") end
function Mem.MemAccessModeRead:classify_after_write(request) return Mem.MemObjectPairDependent("write followed by read may conflict") end
function Mem.MemAccessModeWrite:classify_after_write(request) return Mem.MemObjectPairDependent("two writes may conflict") end
function Mem.MemAccessModeReadWrite:classify_after_write(request) return Mem.MemObjectPairDependent("write and read-write may conflict") end

function Mem.MemObjectMissing:classify_object_pair(request, other) return Mem.MemObjectPairUnproven("one access object is unresolved") end
function Mem.MemObjectFound:classify_object_pair(request, other) return other:classify_known_object_pair(request, self.object) end
function Mem.MemObjectMissing:classify_known_object_pair(request, first) return Mem.MemObjectPairUnproven("one access object is unresolved") end
function Mem.MemObjectFound:classify_known_object_pair(request, first)
  local proof = disjoint_pair(request.relations, first, self.object)
  if proof then return Mem.MemObjectPairIndependent(proof, "objects are disjoint by typed relation") end
  local before_mode = request.before.access.op:access_mode()
  local after_mode = request.after.access.op:access_mode()
  if first == self.object then return before_mode:classify_access_modes(after_mode, request) end
  return Mem.MemObjectPairUnproven("distinct objects lack a disjointness proof")
end
function Mem.MemDependenceAccess:classify_dependence(request) return self.object:classify_object_pair(request, request.after.object) end
function Mem.MemObjectPairIndependent:dependence_result(request)
  local before, after = request.before.access.id, request.after.access.id
  local fact
  if request.before.loop then fact = Mem.MemNoLoopCarriedDependence(before, after, request.before.loop, self.proof)
  else fact = Mem.MemNoDependence(before, after, self.proof) end
  return Mem.MemDependenceClassified(fact, self)
end
function Mem.MemObjectPairDependent:dependence_result(request)
  local before, after = request.before.access.id, request.after.access.id
  if request.before.loop then return Mem.MemDependenceClassified(Mem.MemLoopCarriedDependence(before, after, request.before.loop, self.reason), self) end
  return Mem.MemDependenceClassified(Mem.MemDependenceUnknown(before, after, self.reason), self)
end
function Mem.MemObjectPairUnproven:dependence_result(request)
  return Mem.MemDependenceClassified(Mem.MemDependenceUnknown(request.before.access.id, request.after.access.id, self.reason), self)
end
function Mem.MemDependenceRequest:classify() return self.before:classify_dependence(self):dependence_result(self) end

----------------------------------------------------------------------
-- compute_mem: immutable composition over instruction transfer leaves
----------------------------------------------------------------------

function Mem.MemObjectsSameLen:relation_contribution() return Mem.MemRelationNone end
function Mem.MemObjectWindowOf:relation_contribution() return Mem.MemRelationNone end
function Mem.MemObjectSliceOf:relation_contribution() return Mem.MemRelationNone end
function Mem.MemObjectSameStore:relation_contribution() return Mem.MemRelationSameStore(Mem.MemSameStoreEntry(self.a, self.b, self.proof)) end
function Mem.MemRelationNone:append_same_store(entries) return entries end
function Mem.MemRelationSameStore:append_same_store(entries) return append_one(entries, self.entry) end

local function object_id_for(role, text) return Mem.MemObjectId(role .. ":" .. sanitize(text)) end
local function append_unique_object(objects, fact)
  for _, existing in ipairs(objects) do if existing.id == fact.id then return objects end end
  return append_one(objects, fact)
end
local function loop_for_block(graph, func, block)
  for _, fg in ipairs(graph.funcs) do
    if fg.func == func then
      for _, loop in ipairs(fg.loops) do
        for _, member in ipairs(loop.body) do if member.block == block then return loop.id end end
      end
    end
  end
end
local function module_memory_objects(module)
  local objects, globals, data = {}, {}, {}
  for _, item in ipairs(module.data) do
    local id = object_id_for("data", item.id.text)
    objects = append_one(objects, Mem.MemObjectFact(id, nil, Mem.MemObjectData, Mem.MemProvData(item.id), Code.CodeTyInt(8, Code.CodeUnsigned), Mem.MemExtentBytes(item.size, Mem.MemExtentByConstruction), Mem.MemStrideUnit))
    data = append_one(data, Mem.MemDataObjectEntry(item.id, id))
  end
  for _, item in ipairs(module.globals) do
    local id = object_id_for("global", item.id.text)
    objects = append_one(objects, Mem.MemObjectFact(id, nil, Mem.MemObjectGlobal, Mem.MemProvGlobal(item.id), item.ty:memory_object_elem_type(), Mem.MemExtentUnknown(Mem.MemExtentDynamicAllocation), Mem.MemStrideUnit))
    globals = append_one(globals, Mem.MemGlobalObjectEntry(item.id, id))
  end
  return Mem.MemModuleObjects(objects, globals, data)
end

function Mem.MemContractBoundsEntry:memory_param_extent(func, param, elem_ty, current)
  if self.func == func.id and self.base == param.value then
    return Mem.MemExtentElements(self.len, elem_ty, Mem.MemExtentLengthFromContract)
  end
  return current
end
local function initial_function_facet(func, module_objects, contracts)
  local values, locals, objects = {}, {}, module_objects
  for _, param in ipairs(func.params) do
    local id = object_id_for(func.name .. ":param", param.value.text)
    values = append_one(values, Mem.MemValueObjectEntry(param.value, id))
    local elem_ty = param.ty:memory_object_elem_type()
    local extent = Mem.MemExtentUnknown(Mem.MemExtentOpaquePointer(param.value.text))
    for j = 1, #contracts.bounds do
      extent = contracts.bounds[j]:memory_param_extent(func, param, elem_ty, extent)
    end
    objects = append_unique_object(objects, Mem.MemObjectFact(
      id, func.id, Mem.MemObjectParam, Mem.MemProvValue(param.value),
      elem_ty, extent, Mem.MemStrideUnit))
  end
  for _, local_decl in ipairs(func.locals) do
    local id = object_id_for(func.name .. ":local", local_decl.id.text)
    locals = append_one(locals, Mem.MemLocalObjectEntry(local_decl.id, id))
    objects = append_unique_object(objects, Mem.MemObjectFact(id, func.id, Mem.MemObjectLocal, Mem.MemProvLocal(local_decl.id), local_decl.ty:memory_object_elem_type(), Mem.MemExtentUnknown(Mem.MemExtentDynamicAllocation), Mem.MemStrideUnit))
  end
  return Mem.MemTransferFacet(values, locals, {}, {}, {}, {}, objects, {}, {}, {}, {}, {}, {}, {})
end

function Mem.MemValueObjectMissing:add_contract_disjoint(other, source, entries) return entries end
function Mem.MemValueObjectFound:add_contract_disjoint(other, source, entries) return other:add_contract_disjoint_from(self.object, source, entries) end
function Mem.MemValueObjectMissing:add_contract_disjoint_from(first, source, entries) return entries end
function Mem.MemValueObjectFound:add_contract_disjoint_from(first, source, entries)
  local proof = Mem.MemProofContract(source, Mem.MemContractNoAlias("disjoint", source.fact.a.text))
  return append_one(entries, Mem.MemDisjointEntry(first, self.object, proof))
end
function Mem.MemObjectMissing:append_access_mode(access, entries) return entries end
function Mem.MemObjectFound:append_access_mode(access, entries)
  local proof = Mem.MemProofBackend(access.access.id, Mem.MemBackendNativeAlignment(access.access.access.align))
  return append_one(entries, Mem.MemAccessModeEntry(self.object, access.access.op:access_mode(), proof))
end
local function relation_projection(facet, contracts, func)
  local same_store = {}
  for _, relation in ipairs(facet.relations) do same_store = relation:relation_contribution():append_same_store(same_store) end
  local disjoint = {}
  for _, entry in ipairs(contracts.disjoint) do
    if entry.func == func then disjoint = find_value_object(facet.values, entry.a):add_contract_disjoint(find_value_object(facet.values, entry.b), entry.source, disjoint) end
  end
  local modes = {}
  for _, access in ipairs(facet.dependence_accesses) do modes = access.object:append_access_mode(access, modes) end
  return Mem.MemRelationProjection(same_store, disjoint, modes)
end

function Mem.MemDependenceClassified:append_dependence(accumulation) return Mem.MemDependenceAccumulation(append_one(accumulation.facts, self.fact), accumulation.proofs) end
function Mem.MemDependenceNotComparable:append_dependence(accumulation) return accumulation end
local function classify_dependences(facet, projection)
  local accumulation = Mem.MemDependenceAccumulation({}, facet.proofs)
  for i = 1, #facet.dependence_accesses do
    for j = i + 1, #facet.dependence_accesses do
      local before, after = facet.dependence_accesses[i], facet.dependence_accesses[j]
      if before.loop and after.loop and before.loop == after.loop then accumulation = Mem.MemDependenceRequest(before, after, projection):classify():append_dependence(accumulation) end
    end
  end
  return accumulation
end

function Mem.MemValueObjectMissing:append_readonly_effect(source, effects) return effects end
function Mem.MemValueObjectFound:append_readonly_effect(source, effects)
  local proof = Mem.MemProofContract(source, Mem.MemContractReadonly("readonly", source.fact.base.text))
  return append_one(effects, Mem.MemObjectReadonly(self.object, proof))
end
function Mem.MemValueObjectMissing:append_writeonly_effect(source, effects) return effects end
function Mem.MemValueObjectFound:append_writeonly_effect(source, effects)
  local proof = Mem.MemProofContract(source, Mem.MemContractNoAlias("writeonly", source.fact.base.text))
  return append_one(effects, Mem.MemObjectWriteonly(self.object, proof))
end
local function contract_object_effects(facet, projection, func)
  local effects = {}
  for _, entry in ipairs(projection.readonly) do if entry.func == func then effects = find_value_object(facet.values, entry.base):append_readonly_effect(entry.source, effects) end end
  for _, entry in ipairs(projection.writeonly) do if entry.func == func then effects = find_value_object(facet.values, entry.base):append_writeonly_effect(entry.source, effects) end end
  return effects
end

local function compute_mem_semantic(module, graph, flow, values, contracts)
  local contract_projection = contracts:project_memory_contract()
  local module_projection = module_memory_objects(module)
  local inductions = flow:project_inductions()
  local objects, accesses, intervals, safety, effects, dependences, relations, backend, proofs = module_projection.objects, {}, {}, {}, {}, {}, {}, {}, {}
  for _, func in ipairs(module.funcs) do
    local facet = initial_function_facet(func, module_projection.objects, contract_projection)
    for _, block in ipairs(func.blocks) do
      local loop = loop_for_block(graph, func.id, block.id)
      for _, inst in ipairs(block.insts) do
        facet = inst.op:transfer_memory(Mem.MemInstructionTransferInput(
          func, block, inst, loop, module_projection.globals,
          module_projection.data, inductions, flow, facet)):next_facet()
      end
    end
    local projection = relation_projection(facet, contract_projection, func.id)
    local function_dependences = classify_dependences(facet, projection)
    for _, fact in ipairs(facet.objects) do objects = append_unique_object(objects, fact) end
    accesses, intervals, safety = append_all(accesses, facet.accesses), append_all(intervals, facet.intervals), append_all(safety, facet.safety)
    effects = append_all(effects, contract_object_effects(facet, contract_projection, func.id))
    dependences, relations = append_all(dependences, function_dependences.facts), append_all(relations, facet.relations)
    backend, proofs = append_all(backend, facet.backend), append_all(proofs, function_dependences.proofs)
  end
  return Mem.MemSemanticFactSet(module.id, objects, {}, accesses, intervals, safety, effects, dependences, relations, backend, proofs)
end

function Graph.CodeGraph:compute_mem(module, flow, values, contracts) return compute_mem_semantic(module, self, flow, values, contracts) end
