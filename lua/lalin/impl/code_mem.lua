-- impl/code_mem.lua — compute_mem methods on LalinCode, LalinGraph,
-- LalinFlow, LalinValue, LalinMem types. Produces LalinMem.MemSemanticFactSet
-- from a CodeGraph. Heavy classof refactored to leaf methods.
-- Entry: Graph.CodeGraph:compute_mem(module, flow, values, contracts)

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

local function access_key(id)
  if id == nil then return nil end
  if type(id) == "string" then return id end
  return id.text
end

----------------------------------------------------------------------
-- MemProof leaf methods: code_mem_projection_index
----------------------------------------------------------------------

function Mem.MemProof:code_mem_projection_index(projection)
end

function Mem.MemProofBackend:code_mem_projection_index(projection)
  projection.proof_by_access[self.access.text] = self
end

function Mem.MemProofInterval:code_mem_projection_index(projection)
  projection.proof_by_access[self.interval.access.text] = self
end

function Mem.MemAccessProjection:mem_access(id)
  local key = access_key(id)
  return key and self.access_by_id[key] or nil
end

function Mem.MemAccessProjection:object_for_access(id)
  local key = access_key(id)
  return key and self.object_by_access[key] or nil
end

function Mem.MemAccessProjection:backend_for_access(id)
  local key = access_key(id)
  return key and self.backend_by_access[key] or nil
end

function Mem.MemAccessProjection:proof_for_access(id)
  local key = access_key(id)
  return key and self.proof_by_access[key] or nil
end

local function access_projection(mem)
  local projection = Mem.MemAccessProjection({}, {}, {}, {})
  for _, access in ipairs(mem and mem.accesses or {}) do projection.access_by_id[access.id.text] = access end
  for _, interval in ipairs(mem and mem.intervals or {}) do projection.object_by_access[interval.access.text] = interval.object end
  for _, info in ipairs(mem and mem.backend_info or {}) do projection.backend_by_access[info.access.text] = info end
  for _, proof in ipairs(mem and mem.proofs or {}) do proof:code_mem_projection_index(projection) end
  return projection
end

----------------------------------------------------------------------
-- CodeType leaf methods: unwrap_lease, pointee_ty, elem_ty, byte_span check
----------------------------------------------------------------------

function Code.CodeType:code_mem_is_lease() return false end
function Code.CodeTyLease:code_mem_is_lease() return true end
function Code.CodeType:code_mem_is_view() return false end
function Code.CodeTyView:code_mem_is_view() return true end
function Code.CodeType:code_mem_is_slice() return false end
function Code.CodeTySlice:code_mem_is_slice() return true end
function Code.CodeType:code_mem_is_byte_span() return false end
function Code.CodeTyByteSpan:code_mem_is_byte_span() return true end
function Code.CodeType:code_mem_is_data_ptr() return false end
function Code.CodeTyDataPtr:code_mem_is_data_ptr() return true end

local function unwrap_lease(ty)
  while ty:code_mem_is_lease() do ty = ty.base end
  return ty
end

local function pointee_ty(ty)
  ty = unwrap_lease(ty)
  if ty:code_mem_is_data_ptr() then return ty.pointee end
  return nil
end

local function view_elem_ty(ty)
  ty = unwrap_lease(ty)
  if ty:code_mem_is_view() then return ty.elem end
  return nil
end

local function slice_elem_ty(ty)
  ty = unwrap_lease(ty)
  if ty:code_mem_is_slice() then return ty.elem end
  return nil
end

local function object_elem_ty(ty)
  ty = unwrap_lease(ty)
  if ty:code_mem_is_byte_span() then return Code.CodeTyInt(8, Code.CodeUnsigned) end
  return pointee_ty(ty) or view_elem_ty(ty) or slice_elem_ty(ty) or ty
end

local function storage_extent(ty, size, reason)
  if size ~= nil then return Mem.MemExtentBytes(size, reason or "declared storage size") end
  ty = unwrap_lease(ty)
  if rawget(ty, "count") ~= nil then return Mem.MemExtentBytes(0, "array byte size is target-dependent before backend layout") end
  return Mem.MemExtentUnknown(reason or "extent requires layout or contract fact")
end

local function scalar_bytes(ty)
  ty = unwrap_lease(ty)
  if ty == Code.CodeTyBool8 then return 1 end
  if ty == Code.CodeTyIndex then return 8 end
  if rawget(ty, "bits") ~= nil then return math.max(1, math.floor((ty.bits or 64) / 8)) end
  if ty:code_mem_is_data_ptr() or ty == Code.CodeTyCodePtr or ty == Code.CodeTyImportedCFuncPtr then return 8 end
  return nil
end

----------------------------------------------------------------------
-- CodePlace leaf methods: place_key, object_for_place
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

----------------------------------------------------------------------
-- contract index helpers
----------------------------------------------------------------------

local function contract_expr_key(expr)
  -- Check CodeContractValueRef vs CodeContractPlaceLoad
  if rawget(expr, "value") ~= nil then return "value:" .. expr.value.text end
  if rawget(expr, "place") ~= nil then return "place:" .. expr.place:code_mem_place_key() end
  return nil
end

local function contract_index(contracts)
  local idx = { bounds = {}, projection_bounds = {}, window = {}, same_len = {}, disjoint = {}, soa = {}, noalias = {}, readonly = {}, writeonly = {}, projection_readonly = {}, projection_writeonly = {}, by_func = {} }
  for _, f in ipairs(contracts and contracts.facts or {}) do
    idx.by_func[f.func.text] = idx.by_func[f.func.text] or {}
    idx.by_func[f.func.text][#idx.by_func[f.func.text] + 1] = f
    local k = f.fact
    if rawget(k, "base") ~= nil and rawget(k, "len") ~= nil and rawget(k, "start") == nil then
      idx.bounds[f.func.text .. "\0" .. k.base.text] = f
    elseif rawget(k, "base") ~= nil and rawget(k, "base_len") ~= nil then
      idx.window[f.func.text .. "\0" .. k.base.text] = f
    elseif rawget(k, "a") ~= nil and rawget(k, "b") ~= nil and rawget(k, "base") == nil then
      idx.disjoint[#idx.disjoint + 1] = f
    elseif rawget(k, "a") ~= nil and rawget(k, "b") ~= nil then
      idx.same_len[#idx.same_len + 1] = f
    elseif rawget(k, "component_index") ~= nil then
      idx.soa[f.func.text .. "\0" .. k.base.text] = f
    elseif rawget(k, "base") ~= nil and rawget(k, "field_name") == nil then
      -- NoAlias, Readonly, Writeonly, Invalidate, Preserve, Rejected
      local name = rawget(k, "reason") and "rejected" or
        (rawget(k, "base") and rawget(k, "fact") and "rejected") or
        "noalias"  -- default
      if rawget(k, "reason") ~= nil then
        -- Rejected/Preserve/Invalidate — skip indexing
      else
        idx.noalias[f.func.text .. "\0" .. k.base.text] = f
      end
    end
  end
  -- Separate readonly/writeonly by convention
  for _, f in ipairs(contracts and contracts.facts or {}) do
    local k = f.fact
    if rawget(k, "base") ~= nil then
      if rawget(k, "reason") == nil and rawget(k, "len") == nil and rawget(k, "a") == nil and rawget(k, "component_index") == nil then
        -- Could be Readonly/Writeonly
        idx.readonly[f.func.text .. "\0" .. k.base.text] = idx.readonly[f.func.text .. "\0" .. k.base.text] or f
      end
    end
    if rawget(k, "base") ~= nil and rawget(k, "base") ~= nil and type(rawget(k, "base")) == "table" then
      -- Projection variants
      local key = contract_expr_key(k.base)
      if key ~= nil then
        if rawget(k, "len") ~= nil then idx.projection_bounds[f.func.text .. "\0" .. key] = f end
      end
    end
  end
  return idx
end

----------------------------------------------------------------------
-- CodeInstOp leaf methods: access_op, is_write, access_value, access_place
----------------------------------------------------------------------

function Code.CodeInstOp:code_mem_access_op() return nil end

function Code.CodeInstLoad:code_mem_access_op() return Mem.MemLoad end
function Code.CodeInstStore:code_mem_access_op() return Mem.MemStore end
function Code.CodeInstAtomicLoad:code_mem_access_op() return Mem.MemAtomicLoad end
function Code.CodeInstAtomicStore:code_mem_access_op() return Mem.MemAtomicStore end
function Code.CodeInstAtomicRmw:code_mem_access_op() return Mem.MemAtomicRmw end
function Code.CodeInstAtomicCas:code_mem_access_op() return Mem.MemAtomicCas end

local function is_write_op(op)
  return op == Mem.MemStore or op == Mem.MemAtomicStore or op == Mem.MemAtomicRmw or op == Mem.MemAtomicCas
end

local function access_value(k)
  -- Store/AtomicStore/AtomicRmw have .value; AtomicCas has .replacement
  return rawget(k, "value") or rawget(k, "replacement") or nil
end

local function access_place(k)
  return k.place
end

----------------------------------------------------------------------
-- MemIndex leaf methods
----------------------------------------------------------------------

function Mem.MemIndex:code_mem_index_key()
  return nil
end

-- MemIndexNone is a nullary constructor
function Mem.MemIndex:code_mem_index_key_default()
  return "none"
end

function Mem.MemIndexValue:code_mem_index_key()
  return "value:" .. self.value.text .. ":" .. tostring(self.elem_size) .. ":" .. tostring(self.const_offset or 0)
end

function Mem.MemIndexInduction:code_mem_index_key()
  return "induction:" .. self.induction.value.text .. ":" .. tostring(self.elem_size) .. ":" .. tostring(self.const_offset or 0)
end

local function index_key(index)
  if index == Mem.MemIndexNone then return "none" end
  return index:code_mem_index_key()
end

----------------------------------------------------------------------
-- value_expr_key
----------------------------------------------------------------------

local function value_expr_key(expr, seen)
  if expr == nil then return nil end
  seen = seen or {}
  if seen[expr] then return nil end
  seen[expr] = true
  if rawget(expr, "value") ~= nil and rawget(expr, "a") == nil then return "value:" .. expr.value.text end
  if rawget(expr, "const") ~= nil then return "const:" .. tostring(expr.const) end
  if rawget(expr, "op") ~= nil and rawget(expr, "from") ~= nil then return "cast:" .. tostring(expr.op) .. ":" .. tostring(expr.from) .. ":" .. tostring(expr.to) .. "(" .. tostring(value_expr_key(expr.value, seen)) .. ")" end
  if rawget(expr, "op") ~= nil and rawget(expr, "value") ~= nil and rawget(expr, "a") == nil then return "unary:" .. tostring(expr.op) .. "(" .. tostring(value_expr_key(expr.value, seen)) .. ")" end
  if rawget(expr, "a") ~= nil and rawget(expr, "b") ~= nil then
    return "binary(" .. tostring(value_expr_key(expr.a, seen)) .. "," .. tostring(value_expr_key(expr.b, seen)) .. ")"
  end
  return tostring(expr)
end

local function canonical_index_key(index, value_index)
  if index == Mem.MemIndexNone then return "none" end
  if rawget(index, "value") ~= nil then
    local expr = value_index and value_index:expr_for_value_or_nil(index.value) or nil
    return "value_expr:" .. tostring(value_expr_key(expr) or index.value.text) .. ":" .. tostring(index.elem_size) .. ":" .. tostring(index.const_offset or 0)
  end
  return index_key(index)
end

----------------------------------------------------------------------
-- helpers
----------------------------------------------------------------------

local function object_id(...)
  local parts = { ... }
  for i = 1, #parts do parts[i] = sanitize(parts[i]) end
  return Mem.MemObjectId(table.concat(parts, ":"))
end

local function access_id(func, block, inst)
  return Mem.MemAccessId("access:" .. sanitize(func.name) .. ":" .. sanitize(block.id.text) .. ":" .. sanitize(inst.id.text))
end

local function stride_from_value(value, consts)
  local n = value and consts[value.text] or nil
  if n == 1 then return Mem.MemStrideUnit end
  if n ~= nil then return Mem.MemStrideConstElems(n) end
  if value ~= nil then return Mem.MemStrideValue(value) end
  return Mem.MemStrideUnknown("stride value is unavailable")
end

local function add_unique(out, by_key, key, fact)
  if key ~= nil and by_key[key] ~= nil then return by_key[key] end
  if key ~= nil then by_key[key] = fact end
  out[#out + 1] = fact
  return fact
end

local function const_values(func)
  local out = {}
  for _, block in ipairs(func.blocks or {}) do
    for _, inst in ipairs(block.insts or {}) do
      local k = inst.op
      if rawget(k, "const") ~= nil and rawget(k, "dst") ~= nil then
        local lit = rawget(k.const, "literal")
        if lit ~= nil then
          local raw_val = rawget(lit, "raw") or nil
          local n = raw_val and tonumber(raw_val) or nil
          if n ~= nil then out[k.dst.text] = n end
        end
      end
    end
  end
  return out
end

local function loop_membership(graph)
  local by_func = {}
  for _, fg in ipairs(graph and graph.funcs or {}) do
    by_func[fg.func.text] = by_func[fg.func.text] or {}
    for _, loop in ipairs(fg.loops or {}) do
      for _, gb in ipairs(loop.body or {}) do by_func[fg.func.text][gb.block.text] = loop.id end
    end
  end
  return by_func
end

----------------------------------------------------------------------
-- compute_mem: entry point — MemSemanticFactSet
----------------------------------------------------------------------

local function compute_mem_semantic(module, graph, flow, value, contracts)
  local cidx = contract_index(contracts)
  local objects, object_by_key = {}, {}
  local leases, accesses, intervals, safety, effects, dependences, relations, backend_info, proofs = {}, {}, {}, {}, {}, {}, {}, {}, {}
  local module_objects = { data = {}, global = {} }
  local loops_by_func_block = loop_membership(graph)

  local function add_object(fact)
    add_unique(objects, object_by_key, fact.id.text, fact)
    return fact.id
  end

  local function object_fact(id)
    return id and object_by_key[id.text] or nil
  end

  local function object_proves_access_safety(id)
    local fact = object_fact(id)
    if fact == nil then return false, "access object is unknown" end
    local form = fact.form
    local extent = fact.extent
    if form == Mem.MemObjectLocal or form == Mem.MemObjectGlobal or form == Mem.MemObjectData then
      return true, "direct local/global/data object access"
    end
    if form == Mem.MemObjectContract then
      return true, "bounds contract proves object extent"
    end
    if form == Mem.MemObjectLease then
      return true, "lease grant proves object access"
    end
    -- Check extent is not unknown for view/slice/bytespan/derived/fieldpointer
    if rawget(extent, "reason") ~= nil then
      if form == Mem.MemObjectView or form == Mem.MemObjectSlice or form == Mem.MemObjectByteSpan or form == Mem.MemObjectFieldProjection or form == Mem.MemObjectPtrOffset or form == Mem.MemObjectBytes or form == Mem.MemObjectElement or form == Mem.MemObjectFieldPointer then
        return false, extent.reason or "object extent is unknown"
      end
    else
      if form == Mem.MemObjectView or form == Mem.MemObjectSlice or form == Mem.MemObjectByteSpan or
         form == Mem.MemObjectFieldProjection or form == Mem.MemObjectPtrOffset or form == Mem.MemObjectBytes or form == Mem.MemObjectElement or form == Mem.MemObjectFieldPointer then
        return true, "derived object has explicit bounded extent"
      end
    end
    return false, "object provenance alone is not a bounds proof"
  end

  -- Register module data/globals
  for _, data in ipairs(module.data or {}) do
    local id = object_id("data", data.id.text)
    module_objects.data[data.id.text] = id
    add_object(Mem.MemObjectFact(id, nil, Mem.MemObjectData, Mem.MemProvData(data.id), nil, Mem.MemExtentBytes(data.size or 0, "CodeData.size"), Mem.MemStrideUnit))
  end
  for _, global in ipairs(module.globals or {}) do
    local id = object_id("global", global.id.text)
    module_objects.global[global.id.text] = id
    add_object(Mem.MemObjectFact(id, nil, Mem.MemObjectGlobal, Mem.MemProvGlobal(global.id), object_elem_ty(global.ty), storage_extent(global.ty, global.size, "CodeGlobal storage"), Mem.MemStrideUnit))
  end

  for _, func in ipairs(module.funcs or {}) do
    local value_object, local_object, local_value_object = {}, {}, {}
    local access_records = {}
    local readonly_objects, writeonly_objects = {}, {}
    local consts = const_values(func)
    local value_index = nil -- computed lazily below
    local load_by_place = {}
    for _, block in ipairs(func.blocks or {}) do
      for _, inst in ipairs(block.insts or {}) do
        local k = inst.op
        if rawget(k, "place") ~= nil and rawget(k, "dst") ~= nil then
          local key = k.place:code_mem_place_key()
          if load_by_place[key] == nil then load_by_place[key] = k.dst end
        end
      end
    end

    local function value_for_contract_expr(expr)
      if rawget(expr, "value") ~= nil then return expr.value end
      if rawget(expr, "place") ~= nil then return load_by_place[expr.place:code_mem_place_key()] end
      return nil
    end

    local scaled_index_stride = {}
    local same_store = {}

    local function mark_same_store(a, b)
      if a == nil or b == nil then return end
      same_store[a.text] = same_store[a.text] or {}
      same_store[b.text] = same_store[b.text] or {}
      same_store[a.text][b.text] = b
      same_store[b.text][a.text] = a
    end

    local function extent_for_value(value, ty)
      local bounds = value and cidx.bounds[func.id.text .. "\0" .. value.text]
      local window = value and cidx.window[func.id.text .. "\0" .. value.text]
      local contract = bounds or window
      if contract ~= nil then
        local k = contract.fact
        local len = bounds and k.len or k.base_len
        return Mem.MemExtentElements(len, object_elem_ty(ty) or Code.CodeTyVoid, bounds and "CodeContractBounds extent" or "CodeContractWindowBounds base extent"), contract
      end
      if view_elem_ty(ty) ~= nil then return Mem.MemExtentUnknown("view extent requires descriptor length or contract"), nil end
      if slice_elem_ty(ty) ~= nil then return Mem.MemExtentUnknown("slice extent requires descriptor length or contract"), nil end
      if ty:code_mem_is_byte_span() then return Mem.MemExtentUnknown("byte span extent requires descriptor length or contract"), nil end
      return Mem.MemExtentUnknown("raw pointer parameter has no extent without contract or object provenance"), nil
    end

    -- Register params
    for _, param in ipairs(func.params or {}) do
      local ty = unwrap_lease(param.ty)
      if param.ty:code_mem_is_lease() or ty:code_mem_is_data_ptr() or ty:code_mem_is_view() or ty:code_mem_is_slice() or ty:code_mem_is_byte_span() then
        local extent, contract = extent_for_value(param.value, ty)
        local id = object_id(func.name, param.ty:code_mem_is_lease() and "lease_param" or "param", param.value.text)
        value_object[param.value.text] = id
        local object_kind = param.ty:code_mem_is_lease() and Mem.MemObjectLease
          or (contract and Mem.MemObjectContract
              or (ty:code_mem_is_view() and Mem.MemObjectView
                  or (ty:code_mem_is_slice() and Mem.MemObjectSlice
                      or (ty:code_mem_is_byte_span() and Mem.MemObjectByteSpan or Mem.MemObjectParam))))
        add_object(Mem.MemObjectFact(id, func.id, object_kind, contract and Mem.MemProvContract(contract) or Mem.MemProvValue(param.value), object_elem_ty(ty), extent, ty:code_mem_is_view() and Mem.MemStrideUnknown("view parameter stride requires descriptor stride fact") or Mem.MemStrideUnit))
        if param.ty:code_mem_is_lease() then
          local proof = Mem.MemProofObject(id, Mem.MemObjectSizeKnown(0))
          proofs[#proofs + 1] = proof
          local lease_id = Mem.MemLeaseId("lease:" .. sanitize(func.name) .. ":" .. sanitize(param.value.text))
          leases[#leases + 1] = Mem.MemLeaseGrant(lease_id, Flow.FlowDomainFunction(func.id), param.value, nil, id, Mem.MemBaseValue(param.value), extent, Mem.MemStrideUnit, proof)
        end
      end
    end

    -- Register locals
    for _, local_decl in ipairs(func.locals or {}) do
      local id = object_id(func.name, "local", local_decl.id.text)
      local_object[local_decl.id.text] = id
      add_object(Mem.MemObjectFact(id, func.id, Mem.MemObjectLocal, Mem.MemProvLocal(local_decl.id), object_elem_ty(local_decl.ty), storage_extent(local_decl.ty, nil, "CodeLocal storage"), Mem.MemStrideUnit))
    end

    local function object_for_place(place)
      -- Dispatch based on place kind using field checks
      if rawget(place, "local_id") ~= nil then
        return local_object[place.local_id.text], Mem.MemBaseLocal(place.local_id), Mem.MemIndexNone
      end
      if rawget(place, "global") ~= nil then
        return module_objects.global[place.global.text], Mem.MemBaseGlobal(place.global), Mem.MemIndexNone
      end
      if rawget(place, "data") ~= nil then
        return module_objects.data[place.data.text], Mem.MemBaseData(place.data), Mem.MemIndexNone
      end
      if rawget(place, "addr") ~= nil then
        return value_object[place.addr.text], Mem.MemBaseValue(place.addr), Mem.MemIndexNone
      end
      if rawget(place, "index") ~= nil and rawget(place, "elem_size") ~= nil then
        local parent, base = object_for_place(place.base)
        return parent, base or Mem.MemBaseUnknown("index base object is unknown"), Mem.MemIndexValue(place.index, place.elem_size, 0)
      end
      if rawget(place, "field") ~= nil and rawget(place, "offset") ~= nil then
        local parent, base, index = object_for_place(place.base)
        if parent ~= nil then
          local id = object_id(func.name, "field", parent.text, tostring(place.offset))
          add_object(Mem.MemObjectFact(id, func.id, Mem.MemObjectFieldProjection, Mem.MemProvProjection(parent, Mem.MemProjectField, place.offset), place.ty, storage_extent(place.ty, place.size, "CodePlaceField projection"), Mem.MemStrideUnit))
          local proof = Mem.MemProofObject(id, Mem.MemObjectBaseAddressStable)
          proofs[#proofs + 1] = proof
          relations[#relations + 1] = Mem.MemObjectSameStore(id, parent, proof)
          mark_same_store(id, parent)
          return id, Mem.MemBaseProjection(base or Mem.MemBaseUnknown("field base unknown"), Mem.MemProjectField, place.offset), index
        end
        return nil, Mem.MemBaseUnknown("field parent object is unknown"), Mem.MemIndexNone
      end
      if rawget(place, "base") ~= nil and rawget(place, "offset") ~= nil and rawget(place, "size") ~= nil then
        local parent = value_object[place.base.text]
        if parent ~= nil then
          local id = object_id(func.name, "bytes", parent.text, tostring(place.offset))
          add_object(Mem.MemObjectFact(id, func.id, Mem.MemObjectBytes, Mem.MemProvProjection(parent, Mem.MemProjectBytes, place.offset), place.ty, Mem.MemExtentBytes(place.size, "CodePlaceBytes projection"), Mem.MemStrideUnit))
          local proof = Mem.MemProofObject(id, Mem.MemObjectBaseAddressStable)
          proofs[#proofs + 1] = proof
          relations[#relations + 1] = Mem.MemObjectSameStore(id, parent, proof)
          mark_same_store(id, parent)
          return id, Mem.MemBaseProjection(Mem.MemBaseValue(place.base), Mem.MemProjectBytes, place.offset), Mem.MemIndexNone
        end
        return nil, Mem.MemBaseValue(place.base), Mem.MemIndexNone
      end
      return nil, Mem.MemBaseUnknown("unsupported CodePlace for memory facts"), Mem.MemIndexNone
    end

    local function object_stride_const(object)
      local fact = object_fact(object)
      if fact == nil then return nil end
      if fact.stride == Mem.MemStrideUnit then return 1 end
      if rawget(fact.stride, "elems") ~= nil then return fact.stride.elems end
      return nil
    end

    local function pattern_for_index(index)
      if index == Mem.MemIndexNone then return Mem.MemAccessScalar end
      if rawget(index, "value") ~= nil then
        local stride = scaled_index_stride[index.value.text]
        if stride == "dynamic" then return Mem.MemAccessUnknown end
        if type(stride) == "number" and stride ~= 1 then return Mem.MemAccessStrided(stride) end
      end
      return Mem.MemAccessContiguous
    end

    -- Walk insts building value_object and tracking access records
    for _, block in ipairs(func.blocks or {}) do
      for _, inst in ipairs(block.insts or {}) do
        local k = inst.op
        if rawget(k, "ref") ~= nil and rawget(k, "dst") ~= nil then
          -- CodeInstGlobalRef
          local ref = k.ref
          if rawget(ref, "data") ~= nil then value_object[k.dst.text] = module_objects.data[ref.data.text] end
          if rawget(ref, "global") ~= nil then value_object[k.dst.text] = module_objects.global[ref.global.text] end
        elseif rawget(k, "place") ~= nil and rawget(k, "ptr_ty") ~= nil then
          -- CodeInstAddrOf
          value_object[k.dst.text] = object_for_place(k.place)
        elseif rawget(k, "base") ~= nil and rawget(k, "index") ~= nil then
          -- CodeInstPtrOffset
          local parent = value_object[k.base.text]
          if parent ~= nil then
            local id = object_id(func.name, "ptr_offset", k.dst.text)
            value_object[k.dst.text] = id
            add_object(Mem.MemObjectFact(id, func.id, Mem.MemObjectPtrOffset, Mem.MemProvProjection(parent, Mem.MemProjectPtrOffset, k.const_offset or 0), pointee_ty(k.ptr_ty), Mem.MemExtentUnknown("ptr-offset projection requires a bounded slice/window fact before it has an extent"), Mem.MemStrideUnit))
          end
        elseif rawget(k, "data") ~= nil and rawget(k, "len") ~= nil and rawget(k, "stride") ~= nil then
          -- CodeInstViewMake
          local id = object_id(func.name, "view", k.dst.text)
          value_object[k.dst.text] = id
          add_object(Mem.MemObjectFact(id, func.id, Mem.MemObjectView, Mem.MemProvView(k.dst, k.data, k.len, k.stride), k.elem_ty, Mem.MemExtentElements(k.len, k.elem_ty, "CodeInstViewMake explicit length"), stride_from_value(k.stride, consts)))
          local parent = value_object[k.data.text]
          if parent ~= nil then
            local proof = Mem.MemProofObject(id, Mem.MemObjectBaseAddressStable)
            proofs[#proofs + 1] = proof
            relations[#relations + 1] = Mem.MemObjectSameStore(id, parent, proof)
            mark_same_store(id, parent)
          end
        elseif rawget(k, "view") ~= nil and rawget(k, "dst") ~= nil and rawget(k, "data") == nil then
          -- CodeInstViewData / CodeInstViewLen / CodeInstViewStride
          value_object[k.dst.text] = value_object[k.view.text]
          if rawget(k, "elem_ty") == nil then
            -- ViewLen/ViewStride — compute stride const
            local stride = object_stride_const(value_object[k.view.text])
            if stride ~= nil then consts[k.dst.text] = stride end
          end
        elseif rawget(k, "data") ~= nil and rawget(k, "len") ~= nil and rawget(k, "stride") == nil and rawget(k, "elem_ty") ~= nil then
          -- CodeInstSliceMake
          local id = object_id(func.name, "slice", k.dst.text)
          value_object[k.dst.text] = id
          add_object(Mem.MemObjectFact(id, func.id, Mem.MemObjectSlice, Mem.MemProvSlice(k.dst, k.data, k.len), k.elem_ty, Mem.MemExtentElements(k.len, k.elem_ty, "CodeInstSliceMake explicit length"), Mem.MemStrideUnit))
          local parent = value_object[k.data.text]
          if parent ~= nil then
            local proof = Mem.MemProofObject(id, Mem.MemObjectBaseAddressStable)
            proofs[#proofs + 1] = proof
            relations[#relations + 1] = Mem.MemObjectSameStore(id, parent, proof)
            mark_same_store(id, parent)
          end
        elseif rawget(k, "slice") ~= nil and rawget(k, "dst") ~= nil and rawget(k, "data") == nil then
          -- CodeInstSliceData / CodeInstSliceLen
          value_object[k.dst.text] = value_object[k.slice.text]
        elseif rawget(k, "data") ~= nil and rawget(k, "len") ~= nil and rawget(k, "elem_ty") == nil then
          -- CodeInstByteSpanMake
          local id = object_id(func.name, "bytespan", k.dst.text)
          value_object[k.dst.text] = id
          add_object(Mem.MemObjectFact(id, func.id, Mem.MemObjectByteSpan, Mem.MemProvByteSpan(k.dst, k.data, k.len), Code.CodeTyInt(8, Code.CodeUnsigned), Mem.MemExtentElements(k.len, Code.CodeTyInt(8, Code.CodeUnsigned), "CodeInstByteSpanMake explicit byte length"), Mem.MemStrideUnit))
          local parent = value_object[k.data.text]
          if parent ~= nil then
            local proof = Mem.MemProofObject(id, Mem.MemObjectBaseAddressStable)
            proofs[#proofs + 1] = proof
            relations[#relations + 1] = Mem.MemObjectSameStore(id, parent, proof)
            mark_same_store(id, parent)
          end
        elseif rawget(k, "span") ~= nil and rawget(k, "dst") ~= nil then
          -- CodeInstByteSpanData / CodeInstByteSpanLen
          value_object[k.dst.text] = value_object[k.span.text]
        elseif rawget(k, "place") ~= nil and rawget(k, "dst") ~= nil then
          -- CodeInstLoad — field-pointer projection
          local place = k.place
          if rawget(place, "field") ~= nil then
            local pkey = "place:" .. place:code_mem_place_key()
            local bounds_contract = cidx.projection_bounds[func.id.text .. "\0" .. pkey]
            local elem_ty = pointee_ty(k.access.ty)
            if bounds_contract ~= nil and elem_ty ~= nil then
              local len = value_for_contract_expr(bounds_contract.fact.len)
              if len ~= nil then
                local owner = object_for_place(place)
                local id = object_id(func.name, "field_ptr", k.dst.text)
                value_object[k.dst.text] = id
                add_object(Mem.MemObjectFact(id, func.id, Mem.MemObjectFieldPointer, Mem.MemProvFieldPointer(owner or Mem.MemObjectId("unknown:" .. sanitize(k.dst.text)), place.field, k.dst), elem_ty, Mem.MemExtentElements(len, elem_ty, "CodeContractProjectionBounds field-pointer extent"), Mem.MemStrideUnit))
                if owner ~= nil then
                  local proof = Mem.MemProofObject(id, Mem.MemObjectBaseAddressStable)
                  proofs[#proofs + 1] = proof
                  relations[#relations + 1] = Mem.MemObjectSameStore(id, owner, proof)
                  mark_same_store(id, owner)
                end
              end
            end
          end
        elseif rawget(k, "value") ~= nil and rawget(k, "place") ~= nil then
          -- CodeInstStore — merge local value
          if rawget(k.place, "local_id") ~= nil then
            local key = k.place.local_id.text
            local obj = value_object[k.value.text]
            local old = local_value_object[key]
            if old == nil then local_value_object[key] = obj or false elseif old ~= obj then local_value_object[key] = false end
          end
        elseif rawget(k, "src") ~= nil and rawget(k, "dst") ~= nil then
          -- CodeInstAlias
          value_object[k.dst.text] = value_object[k.src.text]
          if consts[k.src.text] ~= nil then consts[k.dst.text] = consts[k.src.text] end
        elseif rawget(k, "value") ~= nil and rawget(k, "from") ~= nil then
          -- CodeInstCast
          value_object[k.dst.text] = value_object[k.value.text]
          if consts[k.value.text] ~= nil then consts[k.dst.text] = consts[k.value.text] end
        elseif rawget(k, "lhs") ~= nil and rawget(k, "rhs") ~= nil and rawget(k, "op") ~= nil then
          -- CodeInstBinary / CodeInstFloatBinary — track strides
          local lhs, rhs = consts[k.lhs.text], consts[k.rhs.text]
          if k.op == Core.BinMul then
            if lhs ~= nil and rhs ~= nil then
              consts[k.dst.text] = lhs * rhs
              scaled_index_stride[k.dst.text] = lhs * rhs
            elseif lhs ~= nil then
              scaled_index_stride[k.dst.text] = lhs
            elseif rhs ~= nil then
              scaled_index_stride[k.dst.text] = rhs
            else
              scaled_index_stride[k.dst.text] = "dynamic"
            end
          elseif k.op == Core.BinAdd or k.op == Core.BinSub then
            if lhs ~= nil and rhs ~= nil then consts[k.dst.text] = (k.op == Core.BinAdd) and (lhs + rhs) or (lhs - rhs) end
          end
        end

        local op = k:code_mem_access_op()
        if op ~= nil then
          local place = access_place(k)
          local object, base, index = object_for_place(place)
          local id = access_id(func, block, inst)
          local in_bounds, bounds_reason = object_proves_access_safety(object)
          local bounds = in_bounds and Mem.MemBoundsInObject(bounds_reason) or Mem.MemBoundsUnknown(bounds_reason)
          local trap
          if k.access.trap == Code.CodeMustNotTrap or k.access.trap == Code.CodeCheckedTrap then
            trap = (k.access.trap == Code.CodeMustNotTrap and Mem.MemNonTrapping("CodeMemoryAccess is marked must-not-trap") or Mem.MemCheckedTrap("CodeMemoryAccess is checked"))
          elseif in_bounds then
            trap = Mem.MemNonTrapping(bounds_reason)
          else
            trap = Mem.MemMayTrap
          end
          local align = k.access.align and Mem.MemAlignKnown(k.access.align) or Mem.MemAlignUnknown
          local pattern = pattern_for_index(index)
          local loop_id = loops_by_func_block[func.id.text] and loops_by_func_block[func.id.text][block.id.text] or nil
          local access_fact = Mem.MemAccessFact(id, func.id, Graph.GraphBlockId(func.id, block.id), inst.id, op, place, k.access, base, index, pattern, align, bounds, trap)
          accesses[#accesses + 1] = access_fact
          if value_index == nil then value_index = Value.ValueFactSet and value and require("lalin.impl.code_value").expr_index(value) or nil end
          access_records[#access_records + 1] = { id = id, object = object, op = op, index = index, index_key = canonical_index_key(index, value_index), loop = loop_id, in_bounds = in_bounds, trap = trap, order = #access_records + 1 }

          local proof = Mem.MemProofBackend(id, Mem.MemBackendNativeAlignment(8))
          proofs[#proofs + 1] = proof
          local deref = scalar_bytes(k.access.ty)
          local is_atomic = op == Mem.MemAtomicLoad or op == Mem.MemAtomicStore or op == Mem.MemAtomicRmw or op == Mem.MemAtomicCas or k.access.ordering ~= nil
          local explicit_nontrap = k.access.trap == Code.CodeMustNotTrap
          local movable = (rawget(trap, "reason") ~= nil and not is_atomic) and (in_bounds or explicit_nontrap) and not k.access.volatile and not is_atomic
          backend_info[#backend_info + 1] = Mem.MemBackendAccessInfo(id, trap, align, bounds, deref, movable, { proof })
          if object ~= nil and in_bounds then
            local interval = Mem.MemAccessInterval(id, object, loop_id, index, Flow.FlowBoundDerived("access-length:" .. id.text, {}), deref or 0, 0, "access projected into proven bounded memory object")
            intervals[#intervals + 1] = interval
            local iproof = Mem.MemProofInterval(interval, Mem.MemIntervalWithinObject(object))
            proofs[#proofs + 1] = iproof
            safety[#safety + 1] = Mem.MemAccessInBounds(interval, iproof)
          end
          if deref ~= nil then safety[#safety + 1] = Mem.MemAccessDerefBytes(id, deref, proof) end
          if k.access.align ~= nil then safety[#safety + 1] = Mem.MemAccessAlignKnown(id, k.access.align, proof) end
          if rawget(trap, "reason") ~= nil then safety[#safety + 1] = Mem.MemAccessNonTrap(id, proof) end
          if movable then safety[#safety + 1] = Mem.MemAccessMovable(id, proof) end
        end
      end
    end

    -- Process contracts for this func
    for _, fact in ipairs(cidx.by_func[func.id.text] or {}) do
      local k = fact.fact
      local proof = Mem.MemProofContract(fact, Mem.MemContractBounds("memory contract normalized into semantic memory facts"))
      proofs[#proofs + 1] = proof
      if rawget(k, "base") ~= nil then
        local obj = value_object[k.base.text]
        if obj ~= nil then
          if rawget(k, "a") == nil then
            readonly_objects[obj.text] = true
            effects[#effects + 1] = Mem.MemObjectReadonly(obj, proof)
          else
            writeonly_objects[obj.text] = true
            effects[#effects + 1] = Mem.MemObjectWriteonly(obj, proof)
          end
        end
      end
    end

    -- Process same_len, window_bounds
    for _, fact in ipairs(cidx.by_func[func.id.text] or {}) do
      local k = fact.fact
      if rawget(k, "a") ~= nil and rawget(k, "b") ~= nil then
        local a, b = value_object[k.a.text], value_object[k.b.text]
        if a ~= nil and b ~= nil then
          local proof = Mem.MemProofContract(fact, Mem.MemContractBounds("same_len"))
          relations[#relations + 1] = Mem.MemObjectsSameLen(a, b, proof)
        end
      end
    end

    -- Disjoint objects
    local disjoint = {}
    local function mark_disjoint(a, b)
      if a == nil or b == nil then return end
      disjoint[a.text .. "\0" .. b.text] = true
      disjoint[b.text .. "\0" .. a.text] = true
    end
    for _, fact in ipairs(cidx.disjoint or {}) do
      if fact.func == func.id then mark_disjoint(value_object[fact.fact.a.text], value_object[fact.fact.b.text]) end
    end
    local noalias_objects = {}
    for key, fact in pairs(cidx.noalias or {}) do
      if fact.func == func.id then
        local obj = value_object[fact.fact.base.text]
        if obj ~= nil then noalias_objects[obj.text] = true end
      end
    end

    -- Dependence analysis
    local function object_pair_safe(a, b)
      if a.object == nil or b.object == nil then return false, nil end
      if a.object == b.object and a.index_key ~= nil and a.index_key == b.index_key then return true, "same object and same per-iteration index do not carry dependence across iterations" end
      local function disjoint_through_same_store(x, y)
        if disjoint[x.text .. "\0" .. y.text] then return true end
        for _, sx in pairs(same_store[x.text] or {}) do
          if disjoint[sx.text .. "\0" .. y.text] then return true end
          for _, sy in pairs(same_store[y.text] or {}) do
            if disjoint[sx.text .. "\0" .. sy.text] then return true end
          end
        end
        for _, sy in pairs(same_store[y.text] or {}) do
          if disjoint[x.text .. "\0" .. sy.text] then return true end
        end
        return false
      end
      if a.object ~= b.object and disjoint_through_same_store(a.object, b.object) then return true, "objects are disjoint by contract through same-store relation" end
      if a.object ~= b.object and (noalias_objects[a.object.text] or noalias_objects[b.object.text]) then return true, "noalias contract separates one object from the other" end
      if a.object ~= b.object and readonly_objects[a.object.text] and readonly_objects[b.object.text] then return true, "read-only objects do not create loop-carried dependence" end
      if a.object ~= b.object and ((readonly_objects[a.object.text] and writeonly_objects[b.object.text]) or (writeonly_objects[a.object.text] and readonly_objects[b.object.text])) then
        if disjoint[a.object.text .. "\0" .. b.object.text] or noalias_objects[a.object.text] or noalias_objects[b.object.text] then return true, "readonly/writeonly noalias objects are independent" end
      end
      return false, nil
    end

    for i = 1, #access_records do
      for j = i + 1, #access_records do
        local a, b = access_records[i], access_records[j]
        if a.loop ~= nil and b.loop ~= nil and a.loop == b.loop then
          if not is_write_op(a.op) and not is_write_op(b.op) then
            dependences[#dependences + 1] = Mem.MemReadReadIndependent(a.id, b.id, "two reads in the same loop do not carry dependence")
          elseif a.in_bounds and b.in_bounds and rawget(a.trap, "reason") ~= nil and rawget(b.trap, "reason") ~= nil then
            local safe, reason = object_pair_safe(a, b)
            if safe then
              local proof = Mem.MemProofNoDependence({ a.id, b.id }, Mem.MemNoDependenceLoopLevel(a.loop))
              proofs[#proofs + 1] = proof
              dependences[#dependences + 1] = Mem.MemNoLoopCarriedDependence(a.id, b.id, a.loop, proof)
            else
              dependences[#dependences + 1] = Mem.MemDependenceUnknown(a.id, b.id, "no alias/dependence proof for loop-local memory pair")
            end
          end
        end
      end
    end
  end

  return Mem.MemSemanticFactSet(module.id, objects, leases, accesses, intervals, safety, effects, dependences, relations, backend_info, proofs)
end

function Graph.CodeGraph:compute_mem(module, flow, values, contracts)
  return compute_mem_semantic(module, self, flow, values, contracts)
end
