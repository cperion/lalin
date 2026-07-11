-- impl/tree_code.lua
-- Lowering: Tree.* → Code.* IR.  Leaf methods on Tree.Expr/Stmt/Place/Func/Item/Module.
-- Also: layout-resolution methods from layout_resolve.lua.
-- Also: type helpers on Core.Scalar, Code.CodeType, Ty.Type leaves.

-- Bootstrap: ensure schema_v2 init runs first, so direct requires return instantiated types
require("lalin.schema_v2")

local Tree     = require("lalin.schema_v2.tree")
local Code     = require("lalin.schema_v2.code")
local TreeCode = require("lalin.schema_v2.tree_code")
local Core     = require("lalin.schema_v2.core")
local Sem      = require("lalin.schema_v2.sem")
local Ty       = require("lalin.schema_v2.type")
local Bind     = require("lalin.schema_v2.bind")
local asdl     = require("lalin.asdl")
local TypeSizeAlign = require("lalin.type_size_align")
local CodeType = require("lalin.code_type")(require("lalin.schema_v2"))

----------------------------------------------------------------------
-- helpers
----------------------------------------------------------------------

local function sanitize(s)
  s = tostring(s or "x"):gsub("[^%w_]", "_")
  if s:match("^%d") then s = "_" .. s end
  if s == "" then s = "x" end
  return s
end

local function class_name(x)
  return tostring(x)
end

local function clone_map(t)
  local out = {}
  for k, v in pairs(t or {}) do out[k] = v end
  return out
end

local function clone_array(t)
  local out = {}
  for i = 1, #(t or {}) do out[i] = t[i] end
  return out
end

local function entry_key(entry)
  return entry and (entry.binding_name or entry.counter_name or entry.slot_name
    or entry.flag_name or entry.label_name or entry.func_name or entry.extern_name
    or entry.type_name or entry.variant_name or entry.sig_name)
end

local function map_get(t, key)
  if t == nil then return nil end
  local direct = rawget(t, key)
  if direct ~= nil then return direct end
  for i = 1, #t do
    if entry_key(t[i]) == key then return t[i] end
  end
  return nil
end

local function map_with(t, key, value)
  local out = clone_array(t or {})
  for i = 1, #out do
    if entry_key(out[i]) == key then out[i] = value; return out end
  end
  out[#out + 1] = value
  return out
end

local function map_without(t, key)
  local out = {}
  for i = 1, #(t or {}) do
    if entry_key(t[i]) ~= key then out[#out + 1] = t[i] end
  end
  return out
end

local function array_with(t, index, value)
  local out = clone_array(t)
  out[index] = value
  return out
end

local function array_append(t, value)
  local out = clone_array(t)
  out[#out + 1] = value
  return out
end

local function state_with(self, parts)
  return TreeCode.TreeCodeFuncState(
    parts.bindings or self.bindings,
    parts.residence or self.residence,
    parts.emission or self.emission,
    parts.counters or self.counters,
    parts.alpha or self.alpha,
    parts.control or self.control
  )
end

local function func_key(module_name, item_name)
  return tostring(module_name or "") .. "\0" .. tostring(item_name or "")
end

local function code_func_id(item_name)
  return Code.CodeFuncId("fn_" .. tostring(item_name))
end

local function code_extern_id(name)
  return Code.CodeExternId("extern_" .. tostring(name))
end

local function code_global_id(module_name, item_name)
  return Code.CodeGlobalId("global_" .. tostring(module_name or "") .. "_" .. tostring(item_name or ""))
end

local function code_data_id(id)
  return Code.CodeDataId("data_" .. tostring(id and id.text or id))
end

local function decoded_string_bytes(bytes)
  bytes = tostring(bytes or "")
  local first = bytes:sub(1, 1)
  if (first == '"' or first == "'") and bytes:sub(-1) == first then
    local loader = loadstring or load
    local fn = loader("return " .. bytes)
    if fn then
      local ok, value = pcall(fn)
      if ok and type(value) == "string" then return value end
    end
  end
  return bytes
end

local function origin_binding(binding)
  if binding ~= nil then return Code.CodeOriginBinding(binding) end
  return Code.CodeOriginUnknown
end

local function origin_generated(reason)
  return Code.CodeOriginGenerated(reason)
end

local function default_int_semantics()
  return Code.CodeIntSemantics(Code.CodeIntWrap, Code.CodeDivTrapOnZeroOrOverflow, Code.CodeShiftTrapOutOfRange)
end

local function default_float_mode()
  return Code.CodeFloatStrict
end

local function u8_code_ty()
  return Code.CodeTyInt(8, Code.CodeUnsigned)
end

local function unsupported(node, what)
  error("tree_lower unsupported lowering: " .. tostring(what or class_name(node)), 3)
end

local function variant_binding(kind, variant, bind)
  return Bind.Binding(
    Core.Id("variant:" .. kind .. "_" .. variant.name .. "_" .. bind.name),
    bind.name, bind.ty, Bind.BindingRoleLocalValue
  )
end

local function control_binding(region_id, label, param, index, is_entry)
  local role = is_entry
    and Bind.BindingRoleEntryBlockParam(region_id, label.name, index)
    or Bind.BindingRoleBlockParam(region_id, label.name, index)
  return Bind.Binding(
    Core.Id("control:param:" .. region_id .. "_" .. label.name .. "_" .. param.name),
    param.name, param.ty, role
  )
end

local function tree_code_target(raw_target)
  if raw_target == nil then return nil end
  local target = raw_target and raw_target.c_target or raw_target
  local ok, normalized = pcall(CodeType.normalize_target, target)
  if ok then return normalized end
  return CodeType.default_target({
    pointer_bits = target and target.pointer_bits or nil,
    index_bits = target and (target.index_bits or target.pointer_bits) or nil,
    endian = type(target and target.endian) == "string" and target.endian or nil,
  })
end

----------------------------------------------------------------------
-- Sig state (module-level, set per module lowering)
-- NOTE: module_sig_state is reset per compilation to prevent state leaks.
local module_sig_state = nil
TreeCode.reset_module_sig_state = function() module_sig_state = nil end
local function reset_module_sig_state()
  module_sig_state = nil
end

local function type_to_code_s(ty)
  local code_ty, ss = CodeType.type_to_code(module_sig_state, ty)
  module_sig_state = ss
  return code_ty
end

local function ensure_type_sig_s(params, result)
  local sig_id, ss = CodeType.ensure_type_sig(module_sig_state, params, result)
  module_sig_state = ss
  return sig_id
end

local function ensure_code_sig_s(params, results)
  local sig_id, ss = CodeType.ensure_code_sig(module_sig_state, params, results)
  module_sig_state = ss
  return sig_id
end

----------------------------------------------------------------------
-- tree_code_module_name on ModuleHeader leaves
----------------------------------------------------------------------
function Tree.ModuleHeader:tree_code_module_name() return "module" end
function Tree.ModuleTyped:tree_code_module_name() return self.module_name end
function Tree.ModuleSem:tree_code_module_name() return self.module_name end
function Tree.ModuleCode:tree_code_module_name() return self.module_name end
function Tree.Module:tree_code_module_name()
  if self.h then return self.h:tree_code_module_name() end
  return "module"
end

----------------------------------------------------------------------
-- Typed header helpers
----------------------------------------------------------------------
function Tree.ExprHeader:tree_code_expr_type() return nil end
function Tree.ExprTyped:tree_code_expr_type() return self.ty end
function Tree.PlaceHeader:tree_code_place_type() return nil end
function Tree.PlaceTyped:tree_code_place_type() return self.ty end

----------------------------------------------------------------------
-- Void / source-access-base on Ty.Type leaves
----------------------------------------------------------------------
function Core.Scalar:tree_code_is_void_scalar() return false end
function Core.ScalarVoid:tree_code_is_void_scalar() return true end
function Ty.Type:tree_code_is_void_type() return false end
function Ty.TScalar:tree_code_is_void_type() return self.scalar:tree_code_is_void_scalar() end
function Ty.Type:tree_code_source_access_base() return self end
function Ty.TLease:tree_code_source_access_base() return self.base end
function Ty.TOwned:tree_code_source_access_base() return self.base:tree_code_source_access_base() end
function Ty.TAccess:tree_code_source_access_base() return self.base:tree_code_source_access_base() end

----------------------------------------------------------------------
-- named_type_name
----------------------------------------------------------------------
function Ty.Type:tree_code_named_type_name() return nil end
function Ty.TNamed:tree_code_named_type_name() return self.ref:tree_code_type_ref_name() end
function Ty.TypeRef:tree_code_type_ref_name() return nil end
function Ty.TypeRefGlobal:tree_code_type_ref_name() return self.type_name end
function Ty.TypeRefLocal:tree_code_type_ref_name() return self.sym.name end
function Ty.TypeRefPath:tree_code_type_ref_name()
  if #self.path.parts == 0 then return nil end
  return self.path.parts[#self.path.parts].text
end

----------------------------------------------------------------------
-- CodeType helpers (is_float, is_aggregate, is_view, index_cast_op)
----------------------------------------------------------------------
function Code.CodeType:tree_code_is_float_type() return false end
function Code.CodeTyFloat:tree_code_is_float_type() return true end
function Code.CodeType:tree_code_is_aggregate_type() return false end
function Code.CodeTyNamed:tree_code_is_aggregate_type() return true end
function Code.CodeTyArray:tree_code_is_aggregate_type() return true end
function Code.CodeTySlice:tree_code_is_aggregate_type() return true end
function Code.CodeTyView:tree_code_is_aggregate_type() return true end
function Code.CodeTyClosure:tree_code_is_aggregate_type() return true end
function Code.CodeType:tree_code_is_view_type() return false end
function Code.CodeTyView:tree_code_is_view_type() return true end
function Code.CodeType:tree_code_index_cast_op() return nil end
function Code.CodeTyInt:tree_code_index_cast_op()
  if self.bits < 64 then
    return self.signedness == Code.CodeSigned and Core.MachineCastSextend or Core.MachineCastUextend
  end
  return Core.MachineCastBitcast
end
function Code.CodeTyBool8:tree_code_index_cast_op() return Core.MachineCastUextend end

----------------------------------------------------------------------
-- is_ptr_type
----------------------------------------------------------------------
function Ty.Type:tree_code_is_ptr_type() return false end
function Ty.TPtr:tree_code_is_ptr_type() return true end

----------------------------------------------------------------------
-- index_elem_type
----------------------------------------------------------------------
function Ty.Type:tree_code_index_elem_type() return nil end
function Ty.TPtr:tree_code_index_elem_type() return self.elem end
function Ty.TArray:tree_code_index_elem_type() return self.elem end
function Ty.TSlice:tree_code_index_elem_type() return self.elem end
function Ty.TView:tree_code_index_elem_type() return self.elem end

----------------------------------------------------------------------
-- known_layout
----------------------------------------------------------------------
function Ty.TypeMemLayoutResult:tree_code_known_layout() return nil end
function Ty.TypeMemLayoutKnown:tree_code_known_layout() return self.layout end

----------------------------------------------------------------------
-- variant_defs on TypeDecl / Item
----------------------------------------------------------------------
local function variant_name_text(v)
  if type(v) == "string" then return v end
  return v and (v.text or v.name) or tostring(v)
end

function Tree.TypeDecl:tree_code_add_variant_defs(defs, mod_name) end
function Tree.TypeDeclEnumSugar:tree_code_add_variant_defs(defs, mod_name)
  local variants = {}
  for i = 1, #self.variants do
    local name = variant_name_text(self.variants[i])
    variants[#variants + 1] = TreeCode.TreeCodeVariantEntry(name,
      TreeCode.TreeCodeVariant(name, i - 1, Ty.TScalar(Core.ScalarVoid), {}))
  end
  defs[#defs + 1] = TreeCode.TreeCodeVariantDefEntry(self.name,
    TreeCode.TreeCodeVariantDef(Ty.TNamed(Ty.TypeRefGlobal(mod_name, self.name)), variants))
end
function Tree.TypeDeclTaggedUnionSugar:tree_code_add_variant_defs(defs, mod_name)
  local variants = {}
  for i = 1, #self.variants do
    local v = self.variants[i]
    variants[#variants + 1] = TreeCode.TreeCodeVariantEntry(v.name,
      TreeCode.TreeCodeVariant(v.name, i - 1, v.payload, v.fields or {}))
  end
  defs[#defs + 1] = TreeCode.TreeCodeVariantDefEntry(self.name,
    TreeCode.TreeCodeVariantDef(Ty.TNamed(Ty.TypeRefGlobal(mod_name, self.name)), variants))
end
function Tree.Item:tree_code_add_variant_defs(defs, mod_name) end
function Tree.ItemType:tree_code_add_variant_defs(defs, mod_name)
  self.t:tree_code_add_variant_defs(defs, mod_name)
end
function Tree.Module:tree_code_variant_defs(module_name)
  local defs = {}
  for i = 1, #(self.items or {}) do
    self.items[i]:tree_code_add_variant_defs(defs, module_name)
  end
  return defs
end

----------------------------------------------------------------------
-- IndexBase
----------------------------------------------------------------------
function Tree.IndexBase:tree_code_index_base_elem_type() return nil end
function Tree.IndexBaseExpr:tree_code_index_base_elem_type()
  local ty = self.base.h and self.base.h:tree_code_expr_type()
  if ty then return ty:tree_code_source_access_base():tree_code_index_elem_type() end
  return nil
end
function Tree.IndexBasePlace:tree_code_index_base_elem_type() return self.elem end
function Tree.IndexBaseView:tree_code_index_base_elem_type() return self.view.elem end

----------------------------------------------------------------------
-- TreeCodeFuncState: core state threading
----------------------------------------------------------------------
function TreeCode.TreeCodeFuncState:tree_code_scoped_binding_key(binding)
  local key = binding:tree_code_binding_key()
  local renamed = self.alpha.renamed_by_key
  local entry = renamed and renamed[key] or nil
  if entry ~= nil then return entry.renamed end
  return key
end

function TreeCode.TreeCodeFuncState:tree_code_binding_alpha_suffix()
  local entry = self.alpha.current_suffix_by_slot and self.alpha.current_suffix_by_slot.current
  return entry and entry.suffix or nil
end

function TreeCode.TreeCodeFuncState:tree_code_declare_binding_key(binding)
  local key = binding:tree_code_binding_key()
  local suffix = self:tree_code_binding_alpha_suffix()
  local state = self
  if self.alpha.renamed_by_key ~= nil and suffix ~= nil
     and map_get(self.alpha.renamed_by_key, key) == nil then
    local alpha = TreeCode.TreeCodeAlphaState(
      map_with(self.alpha.renamed_by_key, key,
        TreeCode.TreeCodeAlphaRenameEntry(key, key .. "@" .. suffix)),
      self.alpha.current_suffix_by_slot, self.alpha.seq)
    state = state_with(self, { alpha = alpha })
  end
  return TreeCode.TreeCodeBindingKeyResult(state:tree_code_scoped_binding_key(binding), state)
end

function TreeCode.TreeCodeFuncState:tree_code_declare_fresh_binding_key(binding)
  local key = binding:tree_code_binding_key()
  local suffix = self:tree_code_binding_alpha_suffix()
  local state = self
  if self.alpha.renamed_by_key ~= nil and suffix ~= nil then
    local counter = self:tree_code_next_counter("binding_alpha")
    state = counter.state
    local alpha = TreeCode.TreeCodeAlphaState(
      map_with(state.alpha.renamed_by_key, key,
        TreeCode.TreeCodeAlphaRenameEntry(key, key .. "@" .. suffix .. "_l" .. tostring(counter.value))),
      state.alpha.current_suffix_by_slot, state.alpha.seq)
    state = state_with(state, { alpha = alpha })
  end
  return TreeCode.TreeCodeBindingKeyResult(state:tree_code_scoped_binding_key(binding), state)
end

function TreeCode.TreeCodeFuncState:tree_code_next_counter(name)
  local entry = map_get(self.counters.values_by_name, name)
  local next_value = ((entry and entry.next_value) or 0) + 1
  local counters = TreeCode.TreeCodeCounterState(
    map_with(self.counters.values_by_name, name, TreeCode.TreeCodeCounterEntry(name, next_value)))
  return TreeCode.TreeCodeCounterResult(next_value, state_with(self, { counters = counters }))
end

function TreeCode.TreeCodeFuncState:tree_code_current_block()
  return self.emission.current_blocks and self.emission.current_blocks[1] or nil
end

function TreeCode.TreeCodeFuncState:tree_code_has_current_block()
  return self:tree_code_current_block() ~= nil
end

function TreeCode.TreeCodeFuncState:tree_code_set_current_block(block)
  local emission = TreeCode.TreeCodeEmissionState(self.emission.locals, self.emission.blocks, { block })
  return TreeCode.TreeCodeStateResult(state_with(self, { emission = emission }))
end

function TreeCode.TreeCodeFuncState:tree_code_clear_current_block()
  local emission = TreeCode.TreeCodeEmissionState(self.emission.locals, self.emission.blocks, {})
  return TreeCode.TreeCodeStateResult(state_with(self, { emission = emission }))
end

function TreeCode.TreeCodeFuncState:tree_code_append_block(block)
  local emission = TreeCode.TreeCodeEmissionState(
    self.emission.locals, array_append(self.emission.blocks, block), self.emission.current_blocks)
  return TreeCode.TreeCodeStateResult(state_with(self, { emission = emission }))
end

function TreeCode.TreeCodeFuncState:tree_code_save_bindings()
  return TreeCode.TreeCodeBindingSnapshot(
    clone_map(self.bindings.values_by_key), clone_map(self.bindings.locals_by_key))
end

function TreeCode.TreeCodeFuncState:tree_code_restore_bindings(saved)
  local bindings = TreeCode.TreeCodeBindingState(
    clone_map(saved.bindings), clone_map(saved.locals_by_key))
  return TreeCode.TreeCodeStateResult(state_with(self, { bindings = bindings }))
end

function TreeCode.TreeCodeFuncState:tree_code_note_binding(binding, value)
  local key = self:tree_code_scoped_binding_key(binding)
  local bindings = TreeCode.TreeCodeBindingState(
    map_with(self.bindings.values_by_key, key,
      TreeCode.TreeCodeBindingValueEntry(key, value)),
    self.bindings.locals_by_key)
  return TreeCode.TreeCodeStateResult(state_with(self, { bindings = bindings }))
end

function TreeCode.TreeCodeFuncState:tree_code_note_mutable(binding)
  local declared = self:tree_code_declare_fresh_binding_key(binding)
  local residence = TreeCode.TreeCodeResidenceFacts(
    declared.state.residence.addressed_by_key,
    map_with(declared.state.residence.mutable_by_key, declared.binding_name,
      TreeCode.TreeCodeBindingPresenceEntry(declared.binding_name)))
  return TreeCode.TreeCodeStateResult(state_with(declared.state, { residence = residence }))
end

function TreeCode.TreeCodeFuncState:tree_code_alpha_snapshot()
  return clone_map(self.alpha.renamed_by_key), self:tree_code_binding_alpha_suffix()
end

function TreeCode.TreeCodeFuncState:tree_code_use_alpha(alpha, suffix)
  local suffixes = self.alpha.current_suffix_by_slot
  if suffix == nil then
    suffixes = map_without(suffixes, "current")
  else
    suffixes = map_with(suffixes, "current", TreeCode.TreeCodeAlphaSuffixEntry("current", suffix))
  end
  local state = state_with(self, {
    alpha = TreeCode.TreeCodeAlphaState(clone_map(alpha), suffixes, self.alpha.seq)
  })
  return TreeCode.TreeCodeStateResult(state)
end

function TreeCode.TreeCodeFuncState:tree_code_fork_alpha(suffix)
  local alpha = setmetatable({}, { __index = self.alpha.renamed_by_key })
  local result = self:tree_code_use_alpha(alpha, suffix)
  return TreeCode.TreeCodeAlphaResult(result.state.alpha.renamed_by_key, result.state)
end

function TreeCode.TreeCodeFuncState:tree_code_enter_control_region(region)
  local depth = #(self.control.current_regions or {}) + 1
  local control = TreeCode.TreeCodeControlState(
    array_with(self.control.current_regions, depth,
      TreeCode.TreeCodeControlRegionSlot("control:" .. tostring(depth), region)),
    array_with(self.control.flags, depth,
      TreeCode.TreeCodeControlFlag("exit_seen:" .. tostring(depth), false)))
  return TreeCode.TreeCodeStateResult(state_with(self, { control = control }))
end

function TreeCode.TreeCodeFuncState:tree_code_leave_control_region()
  local depth = #(self.control.current_regions or {})
  local exit_flag = self.control.flags[depth]
  local saw_exit = exit_flag and exit_flag.enabled or false
  local control = TreeCode.TreeCodeControlState(
    array_with(self.control.current_regions, depth, nil),
    array_with(self.control.flags, depth, nil))
  return TreeCode.TreeCodeControlExitResult(saw_exit, state_with(self, { control = control }))
end

function TreeCode.TreeCodeFuncState:tree_code_current_control_region()
  local slot = self.control.current_regions[#(self.control.current_regions or {})]
  return slot and slot.region or nil
end

function TreeCode.TreeCodeFuncState:tree_code_note_control_exit()
  local depth = #(self.control.current_regions or {})
  if depth == 0 then return TreeCode.TreeCodeStateResult(self) end
  local control = TreeCode.TreeCodeControlState(
    self.control.current_regions,
    array_with(self.control.flags, depth,
      TreeCode.TreeCodeControlFlag("exit_seen:" .. tostring(depth), true)))
  return TreeCode.TreeCodeStateResult(state_with(self, { control = control }))
end

local function label_key(label)
  return label and label.name or tostring(label)
end

function TreeCode.TreeCodeFuncState:tree_code_control_target(label)
  local region = self:tree_code_current_control_region()
  if region == nil then return nil end
  local key = label_key(label)
  for _, entry in ipairs(region.targets or {}) do
    if entry.label_name == key then return entry.target end
  end
  return nil
end

function TreeCode.TreeCodeFuncState:tree_code_ensure_local(facts, binding, source_ty, residence)
  local declared = self:tree_code_declare_binding_key(binding)
  local state = declared.state
  local key = declared.binding_name
  local existing = map_get(state.bindings.locals_by_key, key)
  if existing ~= nil then
    return TreeCode.TreeCodeLocalResult(existing.binding.id, existing.binding.ty, state)
  end
  local input = TreeCode.TreeCodeExprInput(facts, state)
  local cty = input:tree_code_type(source_ty or binding.ty)
  local id = input:tree_code_local_id_for_binding(binding)
  local local_ = Code.CodeLocal(id, binding.name, cty,
    residence or input:tree_code_residence_for(binding, source_ty or binding.ty),
    origin_binding(binding))
  local emission = TreeCode.TreeCodeEmissionState(
    array_append(state.emission.locals, local_), state.emission.blocks, state.emission.current_blocks)
  local bindings = TreeCode.TreeCodeBindingState(
    state.bindings.values_by_key,
    map_with(state.bindings.locals_by_key, key,
      TreeCode.TreeCodeLocalBindingEntry(key,
        TreeCode.TreeCodeLocalBinding(id, cty, source_ty or binding.ty))))
  return TreeCode.TreeCodeLocalResult(id, cty,
    state_with(state_with(state, { emission = emission }), { bindings = bindings }))
end

----------------------------------------------------------------------
-- TreeCodeInput: common accessors
----------------------------------------------------------------------
function TreeCode.TreeCodeInput:tree_code_func_facts() return self.facts end
function TreeCode.TreeCodeInput:tree_code_func_name() return self.facts.func_name end
function TreeCode.TreeCodeInput:tree_code_state() return self.state end
function TreeCode.TreeCodeInput:tree_code_module_facts() return self.facts.module_facts end
function TreeCode.TreeCodeInput:tree_code_module_sigs() return self.facts.sigs end
function TreeCode.TreeCodeInput:tree_code_module_emission() return self.facts.module_emission end

function TreeCode.TreeCodeExprInput:tree_code_with_state(state)
  return TreeCode.TreeCodeExprInput(self.facts, state)
end
function TreeCode.TreeCodePlaceInput:tree_code_with_state(state)
  return TreeCode.TreeCodePlaceInput(self.facts, state)
end
function TreeCode.TreeCodeStmtInput:tree_code_with_state(state)
  return TreeCode.TreeCodeStmtInput(self.facts, state)
end
function TreeCode.TreeCodeControlInput:tree_code_with_state(state)
  return TreeCode.TreeCodeControlInput(self.facts, state)
end

function TreeCode.TreeCodeInput:tree_code_with_result_state(result)
  return self:tree_code_with_state(result.state)
end

function TreeCode.TreeCodeInput:tree_code_expr_input()
  return TreeCode.TreeCodeExprInput(self:tree_code_func_facts(), self:tree_code_state())
end

function TreeCode.TreeCodeInput:tree_code_place_input()
  return TreeCode.TreeCodePlaceInput(self:tree_code_func_facts(), self:tree_code_state())
end

function TreeCode.TreeCodeExprResult:tree_code_state() return self.state end
function TreeCode.TreeCodePlaceResult:tree_code_state() return self.state end
function TreeCode.TreeCodeStmtResult:tree_code_state() return self.state end

function TreeCode.TreeCodeInput:tree_code_type(ty) return type_to_code_s(ty) end
function TreeCode.TreeCodeContractInput:tree_code_type(ty) return type_to_code_s(ty) end

----------------------------------------------------------------------
-- Bind.Binding
----------------------------------------------------------------------
function Bind.Binding:tree_code_binding_key()
  if self.id and self.id.text then return self.id.text end
  return tostring(self.name)
end

function Bind.ValueRef:tree_code_lookup_binding(input)
  unsupported(self, "non-binding value reference")
end
function Bind.ValueRefBinding:tree_code_lookup_binding(input)
  return self.binding, input:tree_code_state():tree_code_scoped_binding_key(self.binding)
end

function Bind.ValueRef:tree_code_lookup_value(input)
  unsupported(self, "non-binding value reference")
end
function Bind.ValueRefBinding:tree_code_lookup_value(input)
  local binding, key = self:tree_code_lookup_binding(input)
  local local_info = map_get(input:tree_code_state().bindings.locals_by_key, key)
  if local_info ~= nil then
    return input:tree_code_load_place(
      Code.CodePlaceLocal(local_info.binding.id, local_info.binding.ty),
      binding.ty, "load_" .. binding.name)
  end
  local value_entry = map_get(input:tree_code_state().bindings.values_by_key, key)
  if value_entry ~= nil then
    return input:tree_code_expr_result(value_entry.value, input:tree_code_type(binding.ty))
  end
  return binding.role:tree_code_lookup_value(input, binding, self)
end

function Bind.BindingRole:tree_code_lookup_value(input, binding, ref)
  unsupported(ref, "unbound scalar reference `" .. tostring(binding.name) .. "`")
end
function Bind.BindingRoleGlobalFunc:tree_code_lookup_value(input, binding, ref)
  local ptr_ty = input:tree_code_type(binding.ty)
  local dst_result = input:tree_code_new_value("fnref")
  input = input:tree_code_with_result_state(dst_result)
  local dst = dst_result.value
  input = input:tree_code_with_result_state(
    input:tree_code_append_inst(
      Code.CodeInstGlobalRef(dst, Code.CodeGlobalRefFunc(code_func_id(self.item_name)), ptr_ty),
      origin_binding(binding)))
  return input:tree_code_expr_result(dst, ptr_ty)
end
function Bind.BindingRoleExtern:tree_code_lookup_value(input, binding, ref)
  local ptr_ty = input:tree_code_type(binding.ty)
  local dst_result = input:tree_code_new_value("externref")
  input = input:tree_code_with_result_state(dst_result)
  local dst = dst_result.value
  input = input:tree_code_with_result_state(
    input:tree_code_append_inst(
      Code.CodeInstGlobalRef(dst, Code.CodeGlobalRefExtern(code_extern_id(binding.name)), ptr_ty),
      origin_binding(binding)))
  return input:tree_code_expr_result(dst, ptr_ty)
end
function Bind.BindingRoleGlobalConst:tree_code_lookup_value(input, binding, ref)
  local gid = code_global_id(self.module_name, self.item_name)
  return input:tree_code_load_place(
    Code.CodePlaceGlobal(gid, input:tree_code_type(binding.ty)),
    binding.ty, "load_global_" .. binding.name)
end
function Bind.BindingRoleGlobalStatic:tree_code_lookup_value(input, binding, ref)
  local gid = code_global_id(self.module_name, self.item_name)
  return input:tree_code_load_place(
    Code.CodePlaceGlobal(gid, input:tree_code_type(binding.ty)),
    binding.ty, "load_global_" .. binding.name)
end

function Bind.BindingRole:tree_code_global_place(input, binding) return nil end
function Bind.BindingRoleGlobalConst:tree_code_global_place(input, binding)
  return Code.CodePlaceGlobal(code_global_id(self.module_name, self.item_name), input:tree_code_type(binding.ty))
end
function Bind.BindingRoleGlobalStatic:tree_code_global_place(input, binding)
  return Code.CodePlaceGlobal(code_global_id(self.module_name, self.item_name), input:tree_code_type(binding.ty))
end

function Ty.Param:tree_code_param_binding(func_name, index)
  return Bind.Binding(Core.Id("arg_" .. func_name .. "_" .. self.name), self.name, self.ty, Bind.BindingRoleArg(index - 1))
end

----------------------------------------------------------------------
-- Fresh allocators
----------------------------------------------------------------------
function TreeCode.TreeCodeInput:tree_code_new_value(prefix)
  local counter = self:tree_code_state():tree_code_next_counter("value")
  return TreeCode.TreeCodeValueIdResult(Code.CodeValueId("v_" .. sanitize(self:tree_code_func_name()) .. "_" .. sanitize(prefix or "tmp") .. tostring(counter.value)), counter.state)
end
function TreeCode.TreeCodeInput:tree_code_new_inst(prefix)
  local counter = self:tree_code_state():tree_code_next_counter("inst")
  return TreeCode.TreeCodeInstIdResult(Code.CodeInstId("inst_" .. sanitize(self:tree_code_func_name()) .. "_" .. sanitize(prefix or "i") .. tostring(counter.value)), counter.state)
end
function TreeCode.TreeCodeInput:tree_code_new_term(prefix)
  local counter = self:tree_code_state():tree_code_next_counter("term")
  return TreeCode.TreeCodeTermIdResult(Code.CodeTermId("term_" .. sanitize(self:tree_code_func_name()) .. "_" .. sanitize(prefix or "t") .. tostring(counter.value)), counter.state)
end
function TreeCode.TreeCodeInput:tree_code_new_block(prefix)
  local counter = self:tree_code_state():tree_code_next_counter("block")
  return TreeCode.TreeCodeBlockIdResult(Code.CodeBlockId("block_" .. sanitize(self:tree_code_func_name()) .. "_" .. sanitize(prefix or "b") .. tostring(counter.value)), counter.state)
end
function TreeCode.TreeCodeInput:tree_code_value_id_for_binding(binding)
  return Code.CodeValueId("v_" .. sanitize(self:tree_code_func_name()) .. "_" .. sanitize(self:tree_code_state():tree_code_scoped_binding_key(binding)))
end
function TreeCode.TreeCodeInput:tree_code_local_id_for_binding(binding)
  return Code.CodeLocalId("local_" .. sanitize(self:tree_code_func_name()) .. "_" .. sanitize(self:tree_code_state():tree_code_scoped_binding_key(binding)))
end
function TreeCode.TreeCodeInput:tree_code_fresh_string_data(bytes)
  local module_facts = self:tree_code_module_facts()
  local emission = self:tree_code_module_emission()
  local next_string_data = ((emission.counters and emission.counters.string_data and emission.counters.string_data.next_value) or 0) + 1
  emission.counters.string_data = TreeCode.TreeCodeCounterEntry("string_data", next_string_data)
  local stem = "str_" .. sanitize(self:tree_code_func_name()) .. "_" .. tostring(next_string_data)
  local id = Code.CodeDataId("data_" .. tostring(module_facts.module_name or "module") .. "_" .. stem)
  local decoded = decoded_string_bytes(bytes)
  local nul_terminated = decoded .. "\0"
  emission.generated_data[#emission.generated_data + 1] = Code.CodeData(id, stem, Code.CodeLinkageLocal, #nul_terminated, 1, { Code.CodeDataBytes(0, nul_terminated) }, Code.CodeOriginGenerated("string literal " .. stem))
  return id, #decoded
end

----------------------------------------------------------------------
-- addressed / mutable queries
----------------------------------------------------------------------
function TreeCode.TreeCodeInput:tree_code_binding_is_addressed(binding)
  local key = binding:tree_code_binding_key()
  local scoped = self:tree_code_state():tree_code_scoped_binding_key(binding)
  local state = self:tree_code_state()
  return map_get(state.residence.addressed_by_key, key) ~= nil or map_get(state.residence.addressed_by_key, scoped) ~= nil
end
function TreeCode.TreeCodeInput:tree_code_binding_is_mutable(binding)
  local key = binding:tree_code_binding_key()
  local scoped = self:tree_code_state():tree_code_scoped_binding_key(binding)
  local state = self:tree_code_state()
  return map_get(state.residence.mutable_by_key, key) ~= nil or map_get(state.residence.mutable_by_key, scoped) ~= nil
end

function TreeCode.TreeCodeInput:tree_code_expr_result(value, ty)
  return TreeCode.TreeCodeExprResult(value, ty, self:tree_code_state())
end
function TreeCode.TreeCodeInput:tree_code_place_result(place)
  return TreeCode.TreeCodePlaceResult(place, self:tree_code_state())
end

----------------------------------------------------------------------
-- Instruction append / block start / terminate
----------------------------------------------------------------------
function TreeCode.TreeCodeInput:tree_code_append_inst(kind, origin)
  local block = self:tree_code_state():tree_code_current_block()
  if block == nil then unsupported(self, "instruction after terminator") end
  local inst_id = self:tree_code_new_inst()
  local updated = TreeCode.TreeCodeBlockBuilder(block.id, block.name, block.params, array_append(block.insts, Code.CodeInst(inst_id.id, kind, origin or origin_generated("tree_lower"))), block.origin)
  return inst_id.state:tree_code_set_current_block(updated)
end
function TreeCode.TreeCodeInput:tree_code_start_block(id, name, params, origin)
  if self:tree_code_state():tree_code_has_current_block() then unsupported(self, "starting block before terminating current block") end
  return self:tree_code_state():tree_code_set_current_block(TreeCode.TreeCodeBlockBuilder(id, name, params or {}, {}, origin or origin_generated("block " .. tostring(name or "block"))))
end
function TreeCode.TreeCodeInput:tree_code_terminate(kind, origin)
  if not self:tree_code_state():tree_code_has_current_block() then unsupported(self, "terminator without current block") end
  local term_id = self:tree_code_new_term("term")
  local term = Code.CodeTerm(term_id.id, kind, origin or origin_generated("terminator"))
  local block = term_id.state:tree_code_current_block()
  local appended = term_id.state:tree_code_append_block(Code.CodeBlock(block.id, block.name, block.params, block.insts, term, block.origin))
  local cleared = appended.state:tree_code_clear_current_block()
  return TreeCode.TreeCodeTermResult(term, cleared.state)
end
function TreeCode.TreeCodeInput:tree_code_save_bindings() return self:tree_code_state():tree_code_save_bindings() end
function TreeCode.TreeCodeInput:tree_code_restore_bindings(saved) return self:tree_code_state():tree_code_restore_bindings(saved) end

function TreeCode.TreeCodeInput:tree_code_memory_access(mode, source_ty, code_type)
  return Code.CodeMemoryAccess(mode, code_type or self:tree_code_type(source_ty), self:tree_code_align_of(source_ty), Code.CodeMayTrap, false, nil)
end
function TreeCode.TreeCodeInput:tree_code_atomic_access(mode, source_ty, ordering)
  return Code.CodeMemoryAccess(mode, self:tree_code_type(source_ty), self:tree_code_align_of(source_ty), Code.CodeMayTrap, true, ordering)
end
function TreeCode.TreeCodeInput:tree_code_residence_for(binding, ty)
  if self:tree_code_binding_is_addressed(binding) then return Code.CodeResidenceAddressed end
  if self:tree_code_type(ty or binding.ty):tree_code_is_aggregate_type() then return Code.CodeResidenceAggregate end
  return Code.CodeResidenceValue
end
function TreeCode.TreeCodeInput:tree_code_ensure_local(binding, ty, residence)
  return self:tree_code_state():tree_code_ensure_local(self:tree_code_func_facts(), binding, ty, residence)
end

function TreeCode.TreeCodeInput:tree_code_layout_of(ty)
  local module_facts = self:tree_code_module_facts()
  local result = TypeSizeAlign.result(ty, module_facts.layout_env, module_facts.target)
  return result:tree_code_known_layout()
end
function TreeCode.TreeCodeInput:tree_code_align_of(ty)
  local layout = self:tree_code_layout_of(ty)
  return layout and layout.align or 1
end
function TreeCode.TreeCodeInput:tree_code_size_of(ty)
  local layout = self:tree_code_layout_of(ty)
  return layout and layout.size or nil
end
function TreeCode.TreeCodeContractInput:tree_code_layout_of(ty)
  local result = TypeSizeAlign.result(ty, self.module_facts.layout_env, self.module_facts.target)
  return result:tree_code_known_layout()
end
function TreeCode.TreeCodeContractInput:tree_code_align_of(ty)
  local layout = self:tree_code_layout_of(ty)
  return layout and layout.align or 1
end
function TreeCode.TreeCodeContractInput:tree_code_size_of(ty)
  local layout = self:tree_code_layout_of(ty)
  return layout and layout.size or nil
end

function TreeCode.TreeCodeInput:tree_code_variant_def(type_name)
  local module_facts = self:tree_code_module_facts()
  for i = 1, #(module_facts.variant_defs or {}) do
    local entry = module_facts.variant_defs[i]
    if entry.type_name == type_name then return entry.def end
  end
  return nil
end

function TreeCode.TreeCodeVariant:tree_code_payload_type(input)
  if #(self.fields or {}) > 1 then unsupported(self, "multi-field variant payload `" .. tostring(self.name) .. "`") end
  local ty = (#(self.fields or {}) == 1) and self.fields[1].ty or self.payload
  if ty == nil or ty:tree_code_is_void_type() then return nil end
  return ty
end
function TreeCode.TreeCodeVariant:tree_code_ref(input, owner_ty)
  local payload_ty = self:tree_code_payload_type(input)
  return Code.CodeVariantRef(input:tree_code_type(owner_ty), self.name, self.tag, payload_ty and input:tree_code_type(payload_ty) or nil)
end
function TreeCode.TreeCodeInput:tree_code_variant_payload_type(variant) return variant:tree_code_payload_type(self) end
function TreeCode.TreeCodeInput:tree_code_variant_ref(owner_ty, variant) return variant:tree_code_ref(self, owner_ty) end

local function tree_code_variant_entry(def, variant_name)
  for i = 1, #(def and def.variants or {}) do
    if def.variants[i].variant_name == variant_name then return def.variants[i] end
  end
  return nil
end

function TreeCode.TreeCodeInput:tree_code_const_index(n, reason)
  local allocated = self:tree_code_new_value(reason or "index_const")
  local input = self:tree_code_with_result_state(allocated)
  local appended = input:tree_code_append_inst(Code.CodeInstConst(allocated.value, Code.CodeConstLiteral(Code.CodeTyIndex, Core.LitInt(tostring(n)))), origin_generated(reason or "index const"))
  input = input:tree_code_with_result_state(appended)
  return input:tree_code_expr_result(allocated.value, Code.CodeTyIndex)
end

function TreeCode.TreeCodeInput:tree_code_as_index_value(value, value_ty, reason)
  if value_ty == Code.CodeTyIndex then return self:tree_code_expr_result(value, Code.CodeTyIndex) end
  local op = value_ty:tree_code_index_cast_op()
  if op == nil then unsupported(value_ty, "non-integer index value " .. class_name(value_ty)) end
  local allocated = self:tree_code_new_value(reason or "to_index")
  local input = self:tree_code_with_result_state(allocated)
  local appended = input:tree_code_append_inst(Code.CodeInstCast(allocated.value, op, value_ty, Code.CodeTyIndex, value), origin_generated(reason or "index cast"))
  input = input:tree_code_with_result_state(appended)
  return input:tree_code_expr_result(allocated.value, Code.CodeTyIndex)
end

function TreeCode.TreeCodeInput:tree_code_index_mul(lhs, rhs, reason)
  local allocated = self:tree_code_new_value(reason)
  local input = self:tree_code_with_result_state(allocated)
  local appended = input:tree_code_append_inst(Code.CodeInstBinary(allocated.value, Core.BinMul, Code.CodeTyIndex, default_int_semantics(), lhs, rhs), origin_generated(reason))
  input = input:tree_code_with_result_state(appended)
  return input:tree_code_expr_result(allocated.value, Code.CodeTyIndex)
end

function TreeCode.TreeCodeInput:tree_code_data_offset(view, data, index, elem, reason)
  local ptr_ty = Code.CodeTyDataPtr(self:tree_code_type(elem))
  local allocated = self:tree_code_new_value(reason)
  local input = self:tree_code_with_result_state(allocated)
  local elem_size = self:tree_code_size_of(elem)
  if elem_size == nil then unsupported(view, "view element without known size") end
  local appended = input:tree_code_append_inst(Code.CodeInstPtrOffset(allocated.value, ptr_ty, data, index, elem_size, 0), origin_generated(reason))
  input = input:tree_code_with_result_state(appended)
  return input:tree_code_expr_result(allocated.value, ptr_ty)
end

function TreeCode.TreeCodeInput:tree_code_load_place(place, source_ty, reason)
  local allocated = self:tree_code_new_value(reason or "load")
  local input = self:tree_code_with_result_state(allocated)
  local appended = input:tree_code_append_inst(Code.CodeInstLoad(allocated.value, place, input:tree_code_memory_access(Code.CodeMemoryRead, source_ty, input:tree_code_type(source_ty))), origin_generated(reason or "load"))
  input = input:tree_code_with_result_state(appended)
  return input:tree_code_expr_result(allocated.value, input:tree_code_type(source_ty))
end

function TreeCode.TreeCodeInput:tree_code_store_place(place, source_ty, value, origin)
  return self:tree_code_append_inst(Code.CodeInstStore(place, value, self:tree_code_memory_access(Code.CodeMemoryWrite, source_ty, self:tree_code_type(source_ty))), origin or origin_generated("store"))
end

function TreeCode.TreeCodeInput:tree_code_bind_alias(binding, src, ty)
  local declared = self:tree_code_state():tree_code_declare_binding_key(binding)
  self = self:tree_code_with_result_state(declared)
  local dst = self:tree_code_value_id_for_binding(binding)
  self = self:tree_code_with_result_state(self:tree_code_state():tree_code_note_binding(binding, dst))
  self = self:tree_code_with_result_state(self:tree_code_append_inst(Code.CodeInstAlias(dst, ty, src), origin_binding(binding)))
  return TreeCode.TreeCodeStateResult(self:tree_code_state())
end

function TreeCode.TreeCodeInput:tree_code_bind_local_init(binding, init_value, source_ty, is_mutable)
  local residence = is_mutable and Code.CodeResidenceAddressed or self:tree_code_residence_for(binding, source_ty)
  local local_result = self:tree_code_ensure_local(binding, source_ty, residence)
  self = self:tree_code_with_result_state(local_result)
  local stored = self:tree_code_store_place(Code.CodePlaceLocal(local_result.id, local_result.ty), source_ty, init_value, origin_binding(binding))
  return TreeCode.TreeCodeStateResult(stored.state)
end

----------------------------------------------------------------------
-- tree_code_lower_stmt_body / fallthrough
----------------------------------------------------------------------
function TreeCode.TreeCodeStmtInput:tree_code_lower_stmt_body(body)
  local input = self
  for i = 1, #(body or {}) do
    if not input:tree_code_state():tree_code_has_current_block() then return input end
    local result = body[i]:lower_tree_stmt_to_code(input)
    input = TreeCode.TreeCodeStmtInput(input:tree_code_func_facts(), result.state)
  end
  return input
end

function TreeCode.TreeCodeStmtInput:tree_code_lower_stmt_fallthrough_to(body, block_id, name, join_id)
  local input = self:tree_code_with_result_state(self:tree_code_start_block(block_id, name, {}, origin_generated(name)))
  input = TreeCode.TreeCodeStmtInput(input:tree_code_func_facts(), input:tree_code_state())
  local saved = input:tree_code_save_bindings()
  input = input:tree_code_lower_stmt_body(body or {})
  local falls = input:tree_code_state():tree_code_has_current_block()
  if falls then
    input = input:tree_code_with_result_state(input:tree_code_terminate(Code.CodeTermJump(join_id, {}), origin_generated(name .. " fallthrough")))
    input = TreeCode.TreeCodeStmtInput(input:tree_code_func_facts(), input:tree_code_state())
  end
  input = input:tree_code_with_result_state(input:tree_code_restore_bindings(saved))
  input = TreeCode.TreeCodeStmtInput(input:tree_code_func_facts(), input:tree_code_state())
  return TreeCode.TreeCodeFallthroughResult(falls, input:tree_code_state())
end

----------------------------------------------------------------------
-- collect_address_taken (walk tree for AddressResidence)
----------------------------------------------------------------------
local collect_address_taken_expr, collect_address_taken_place, collect_address_taken_stmts

function Bind.ValueRef:tree_code_mark_addressed_binding(out) end
function Bind.ValueRefBinding:tree_code_mark_addressed_binding(out)
  out.addressed[self.binding:tree_code_binding_key()] = TreeCode.TreeCodeBindingPresenceEntry(self.binding:tree_code_binding_key())
end

function Tree.Place:tree_code_mark_addressed_place(out) end
function Tree.PlaceRef:tree_code_mark_addressed_place(out) self.ref:tree_code_mark_addressed_binding(out) end
function Tree.PlaceField:tree_code_mark_addressed_place(out) self.base:tree_code_mark_addressed_place(out) end
function Tree.PlaceDot:tree_code_mark_addressed_place(out) self.base:tree_code_mark_addressed_place(out) end
function Tree.PlaceIndex:tree_code_mark_addressed_place(out) self.base:tree_code_mark_addressed_index_base(out) end
function Tree.IndexBase:tree_code_mark_addressed_index_base(out) end
function Tree.IndexBasePlace:tree_code_mark_addressed_index_base(out) self.base:tree_code_mark_addressed_place(out) end

function Tree.Place:tree_code_collect_address_taken_place(out) end
function Tree.PlaceDeref:tree_code_collect_address_taken_place(out) collect_address_taken_expr(self.base, out) end
function Tree.PlaceField:tree_code_collect_address_taken_place(out) collect_address_taken_place(self.base, out) end
function Tree.PlaceDot:tree_code_collect_address_taken_place(out) collect_address_taken_place(self.base, out) end
function Tree.PlaceIndex:tree_code_collect_address_taken_place(out) self.base:tree_code_collect_address_taken_index_base(out); collect_address_taken_expr(self.index, out) end
function Tree.IndexBase:tree_code_collect_address_taken_index_base(out) end
function Tree.IndexBaseExpr:tree_code_collect_address_taken_index_base(out) collect_address_taken_expr(self.base, out) end
function Tree.IndexBasePlace:tree_code_collect_address_taken_index_base(out) collect_address_taken_place(self.base, out) end
function Tree.IndexBaseView:tree_code_collect_address_taken_index_base(out) collect_address_taken_expr(self.view.base, out) end

function Tree.Expr:tree_code_collect_address_taken_expr(out) end
function Tree.ExprAddrOf:tree_code_collect_address_taken_expr(out) self.place:tree_code_mark_addressed_place(out); collect_address_taken_place(self.place, out) end
function Tree.ExprUnary:tree_code_collect_address_taken_expr(out) collect_address_taken_expr(self.value, out) end
function Tree.ExprDeref:tree_code_collect_address_taken_expr(out) collect_address_taken_expr(self.value, out) end
function Tree.ExprLen:tree_code_collect_address_taken_expr(out) collect_address_taken_expr(self.value, out) end
function Tree.ExprIsNull:tree_code_collect_address_taken_expr(out) collect_address_taken_expr(self.value, out) end
function Tree.ExprBinary:tree_code_collect_address_taken_expr(out) collect_address_taken_expr(self.lhs, out); collect_address_taken_expr(self.rhs, out) end
function Tree.ExprCompare:tree_code_collect_address_taken_expr(out) collect_address_taken_expr(self.lhs, out); collect_address_taken_expr(self.rhs, out) end
function Tree.ExprLogic:tree_code_collect_address_taken_expr(out) collect_address_taken_expr(self.lhs, out); collect_address_taken_expr(self.rhs, out) end
function Tree.ExprCast:tree_code_collect_address_taken_expr(out) collect_address_taken_expr(self.value, out) end
function Tree.ExprMachineCast:tree_code_collect_address_taken_expr(out) collect_address_taken_expr(self.value, out) end
function Tree.ExprLoad:tree_code_collect_address_taken_expr(out) collect_address_taken_expr(self.addr, out) end
function Tree.ExprAtomicLoad:tree_code_collect_address_taken_expr(out) collect_address_taken_expr(self.addr, out) end
function Tree.ExprAtomicRmw:tree_code_collect_address_taken_expr(out) collect_address_taken_expr(self.addr, out); collect_address_taken_expr(self.value, out) end
function Tree.ExprAtomicCas:tree_code_collect_address_taken_expr(out) collect_address_taken_expr(self.addr, out); collect_address_taken_expr(self.expected, out); collect_address_taken_expr(self.replacement, out) end
function Tree.ExprCall:tree_code_collect_address_taken_expr(out) collect_address_taken_expr(self.callee, out); for i=1,#(self.args or {}) do collect_address_taken_expr(self.args[i], out) end end
function Tree.ExprField:tree_code_collect_address_taken_expr(out) collect_address_taken_expr(self.base, out) end
function Tree.ExprDot:tree_code_collect_address_taken_expr(out) collect_address_taken_expr(self.base, out) end
function Tree.ExprIndex:tree_code_collect_address_taken_expr(out) self.base:tree_code_collect_address_taken_index_base(out); collect_address_taken_expr(self.index, out) end
function Tree.ExprIntrinsic:tree_code_collect_address_taken_expr(out) for i=1,#(self.args or {}) do collect_address_taken_expr(self.args[i], out) end end
function Tree.ExprArray:tree_code_collect_address_taken_expr(out) for i=1,#(self.elems or {}) do collect_address_taken_expr(self.elems[i], out) end end
function Tree.ExprCtor:tree_code_collect_address_taken_expr(out) for i=1,#(self.args or {}) do collect_address_taken_expr(self.args[i], out) end end
function Tree.ExprAgg:tree_code_collect_address_taken_expr(out) for i=1,#(self.fields or {}) do collect_address_taken_expr(self.fields[i].value, out) end end
function Tree.ExprIf:tree_code_collect_address_taken_expr(out) collect_address_taken_expr(self.cond, out); collect_address_taken_expr(self.then_expr, out); collect_address_taken_expr(self.else_expr, out) end
function Tree.ExprSelect:tree_code_collect_address_taken_expr(out) collect_address_taken_expr(self.cond, out); collect_address_taken_expr(self.then_expr, out); collect_address_taken_expr(self.else_expr, out) end
function Tree.ExprSwitch:tree_code_collect_address_taken_expr(out)
  collect_address_taken_expr(self.value, out)
  for i=1,#(self.arms or {}) do collect_address_taken_stmts(self.arms[i].body, out); collect_address_taken_expr(self.arms[i].result, out) end
  for i=1,#(self.variant_arms or {}) do collect_address_taken_stmts(self.variant_arms[i].body, out); collect_address_taken_expr(self.variant_arms[i].result, out) end
  collect_address_taken_stmts(self.default_body or {}, out); collect_address_taken_expr(self.default_expr, out)
end
function Tree.ExprControl:tree_code_collect_address_taken_expr(out) collect_address_taken_stmts(self.region.entry.body, out); for i=1,#(self.region.blocks or {}) do collect_address_taken_stmts(self.region.blocks[i].body, out) end end
function Tree.ExprView:tree_code_collect_address_taken_expr(out) self.view:tree_code_collect_address_taken_view(out) end
function Tree.ExprBlock:tree_code_collect_address_taken_expr(out) collect_address_taken_stmts(self.stmts or {}, out); collect_address_taken_expr(self.result, out) end

function Tree.View:tree_code_collect_address_taken_view(out) end
function Tree.ViewFromExpr:tree_code_collect_address_taken_view(out) collect_address_taken_expr(self.base, out) end
function Tree.ViewContiguous:tree_code_collect_address_taken_view(out) collect_address_taken_expr(self.data, out); collect_address_taken_expr(self.len, out) end
function Tree.ViewStrided:tree_code_collect_address_taken_view(out) collect_address_taken_expr(self.data, out); collect_address_taken_expr(self.len, out); collect_address_taken_expr(self.stride, out) end
function Tree.ViewRestrided:tree_code_collect_address_taken_view(out) collect_address_taken_expr(self.stride, out) end
function Tree.ViewWindow:tree_code_collect_address_taken_view(out) collect_address_taken_expr(self.start, out); collect_address_taken_expr(self.len, out) end
function Tree.ViewRowBase:tree_code_collect_address_taken_view(out) collect_address_taken_expr(self.row_offset, out) end
function Tree.ViewInterleaved:tree_code_collect_address_taken_view(out) collect_address_taken_expr(self.data, out); collect_address_taken_expr(self.len, out); collect_address_taken_expr(self.stride, out); collect_address_taken_expr(self.lane, out) end
function Tree.ViewInterleavedView:tree_code_collect_address_taken_view(out) collect_address_taken_expr(self.stride, out); collect_address_taken_expr(self.lane, out) end

function Tree.Stmt:tree_code_collect_address_taken_stmt(out) end
function Tree.StmtLet:tree_code_collect_address_taken_stmt(out) collect_address_taken_expr(self.init, out) end
function Tree.StmtVar:tree_code_collect_address_taken_stmt(out) out.mutable[self.binding:tree_code_binding_key()] = TreeCode.TreeCodeBindingPresenceEntry(self.binding:tree_code_binding_key()); collect_address_taken_expr(self.init, out) end
function Tree.StmtSet:tree_code_collect_address_taken_stmt(out) collect_address_taken_place(self.place, out); collect_address_taken_expr(self.value, out) end
function Tree.StmtAtomicStore:tree_code_collect_address_taken_stmt(out) collect_address_taken_expr(self.addr, out); collect_address_taken_expr(self.value, out) end
function Tree.StmtExpr:tree_code_collect_address_taken_stmt(out) collect_address_taken_expr(self.expr, out) end
function Tree.StmtAssert:tree_code_collect_address_taken_stmt(out) collect_address_taken_expr(self.cond, out) end
function Tree.StmtYieldValue:tree_code_collect_address_taken_stmt(out) collect_address_taken_expr(self.value, out) end
function Tree.StmtReturnValue:tree_code_collect_address_taken_stmt(out) collect_address_taken_expr(self.value, out) end
function Tree.StmtIf:tree_code_collect_address_taken_stmt(out) collect_address_taken_expr(self.cond, out); collect_address_taken_stmts(self.then_body, out); collect_address_taken_stmts(self.else_body, out) end
function Tree.StmtSwitch:tree_code_collect_address_taken_stmt(out)
  collect_address_taken_expr(self.value, out)
  for j=1,#(self.arms or {}) do collect_address_taken_stmts(self.arms[j].body, out) end
  for j=1,#(self.variant_arms or {}) do collect_address_taken_stmts(self.variant_arms[j].body, out) end
  collect_address_taken_stmts(self.default_body or {}, out)
end
function Tree.StmtJump:tree_code_collect_address_taken_stmt(out) for j=1,#(self.args or {}) do collect_address_taken_expr(self.args[j].value, out) end end
function Tree.StmtJumpCont:tree_code_collect_address_taken_stmt(out) for j=1,#(self.args or {}) do collect_address_taken_expr(self.args[j].value, out) end end
function Tree.StmtRegionEmit:tree_code_collect_address_taken_stmt(out) for j=1,#(self.args or {}) do collect_address_taken_expr(self.args[j], out) end end
function Tree.StmtRegionCall:tree_code_collect_address_taken_stmt(out) for j=1,#(self.args or {}) do collect_address_taken_expr(self.args[j], out) end end
function Tree.StmtControl:tree_code_collect_address_taken_stmt(out) collect_address_taken_stmts(self.region.entry.body, out); for j=1,#(self.region.blocks or {}) do collect_address_taken_stmts(self.region.blocks[j].body, out) end end

collect_address_taken_place = function(place, out) place:tree_code_collect_address_taken_place(out) end
collect_address_taken_expr = function(expr, out) if expr == nil then return end; expr:tree_code_collect_address_taken_expr(out) end
collect_address_taken_stmts = function(stmts, out) for i=1,#(stmts or {}) do stmts[i]:tree_code_collect_address_taken_stmt(out) end; return out end

----------------------------------------------------------------------
-- tree_code_as_place_result / field_base_place / require_lowered_field
----------------------------------------------------------------------
function Tree.Expr:tree_code_as_place_result(input) unsupported(self, "expression is not addressable") end
function Tree.ExprRef:tree_code_as_place_result(input)
  local ty = self.h and self.h:tree_code_expr_type()
  return Tree.PlaceRef(Tree.PlaceTyped(ty), self.ref):lower_tree_place_to_code(TreeCode.TreeCodePlaceInput(input:tree_code_func_facts(), input:tree_code_state()))
end
function Tree.ExprDeref:tree_code_as_place_result(input)
  local value_result = self.value:lower_tree_expr_to_code(input:tree_code_expr_input())
  input = input:tree_code_with_result_state(value_result)
  local expr_ty = self.h and self.h:tree_code_expr_type()
  return input:tree_code_place_result(Code.CodePlaceDeref(value_result.value, input:tree_code_type(expr_ty), input:tree_code_align_of(expr_ty)))
end
function Tree.ExprField:tree_code_as_place_result(input)
  self.field:tree_code_require_lowered_field(input)
  local base_ty = self.base.h and self.base.h:tree_code_expr_type()
  if base_ty then base_ty = base_ty:tree_code_source_access_base() end
  local base_result = base_ty and base_ty:tree_code_lower_field_base_place(input, self.base) or self.base:tree_code_as_place_result(input)
  input = input:tree_code_with_result_state(base_result)
  local field_layout = input:tree_code_layout_of(self.field.ty)
  return input:tree_code_place_result(Code.CodePlaceField(base_result.place, self.field, input:tree_code_type(self.field.ty), self.field.offset, field_layout and field_layout.size or nil, field_layout and field_layout.align or nil))
end
function Tree.ExprIndex:tree_code_as_place_result(input)
  local expr_ty = self.h and self.h:tree_code_expr_type()
  return self.base:tree_code_lower_place(input, self.index, expr_ty)
end

function Ty.Type:tree_code_lower_field_base_place(input, base) return base:tree_code_as_place_result(input) end
function Ty.TPtr:tree_code_lower_field_base_place(input, base)
  local addr_result = base:lower_tree_expr_to_code(input:tree_code_expr_input())
  input = input:tree_code_with_result_state(addr_result)
  return input:tree_code_place_result(Code.CodePlaceDeref(addr_result.value, input:tree_code_type(self.elem), input:tree_code_align_of(self.elem)))
end
function Ty.Type:tree_code_lower_place_field_base(input, base)
  return base:lower_tree_place_to_code(TreeCode.TreeCodePlaceInput(input:tree_code_func_facts(), input:tree_code_state()))
end
function Ty.TPtr:tree_code_lower_place_field_base(input, base)
  local ref = base:tree_code_ref_for_ptr_field()
  if ref == nil then return base:lower_tree_place_to_code(TreeCode.TreeCodePlaceInput(input:tree_code_func_facts(), input:tree_code_state())) end
  local addr_result = Tree.ExprRef(Tree.ExprTyped(self), ref):lower_tree_expr_to_code(input:tree_code_expr_input())
  input = input:tree_code_with_result_state(addr_result)
  return input:tree_code_place_result(Code.CodePlaceDeref(addr_result.value, input:tree_code_type(self.elem), input:tree_code_align_of(self.elem)))
end
function Tree.Place:tree_code_ref_for_ptr_field() return nil end
function Tree.PlaceRef:tree_code_ref_for_ptr_field() return self.ref end

function Sem.FieldRef:tree_code_require_lowered_field(input) unsupported(self, "field access before sem_layout_resolve") end
function Sem.FieldByOffset:tree_code_require_lowered_field(input) end

----------------------------------------------------------------------
-- tree_code_lower_index_base_place / index helpers
----------------------------------------------------------------------
function Tree.IndexBase:tree_code_lower_index_base_place(input, idx, elem_ty) unsupported(self, "index base " .. class_name(self)) end
function Tree.IndexBaseExpr:tree_code_lower_index_base_place(input, idx, elem_ty)
  local base_ty = self.base.h and self.base.h:tree_code_expr_type()
  if base_ty then base_ty = base_ty:tree_code_source_access_base() end
  if base_ty then return base_ty:tree_code_lower_expr_index_base(input, self.base, idx, elem_ty) end
  unsupported(self, "index base expression without type")
end
function Tree.IndexBasePlace:tree_code_lower_index_base_place(input, idx, elem_ty)
  local base_ty = self.base.h and self.base.h:tree_code_place_type()
  if base_ty then base_ty = base_ty:tree_code_source_access_base() end
  if base_ty then return base_ty:tree_code_lower_place_index_base(input, self.base, idx, elem_ty) end
  unsupported(self, "index base place without type")
end
function Tree.IndexBaseView:tree_code_lower_index_base_place(input, idx, elem_ty)
  local view_parts = self.view:lower_tree_view_parts_to_code(input)
  input = input:tree_code_with_result_state(view_parts)
  local scaled_result = input:tree_code_new_value("view_index_scaled")
  input = input:tree_code_with_result_state(scaled_result)
  local scaled = scaled_result.value
  input = input:tree_code_with_result_state(input:tree_code_append_inst(Code.CodeInstBinary(scaled, Core.BinMul, Code.CodeTyIndex, default_int_semantics(), idx, view_parts.stride), origin_generated("view index scale")))
  return TreeCode.TreeCodeIndexPlaceResult(Code.CodePlaceDeref(view_parts.data, input:tree_code_type(elem_ty), input:tree_code_align_of(elem_ty)), scaled, input:tree_code_state())
end

function Ty.Type:tree_code_lower_expr_index_base(input, base, idx, elem_ty)
  if input:tree_code_type(self):tree_code_is_aggregate_type() then
    local base_result = base:tree_code_as_place_result(input)
    input = input:tree_code_with_result_state(base_result)
    return TreeCode.TreeCodeIndexPlaceResult(base_result.place, idx, input:tree_code_state())
  end
  unsupported(base, "index expression base type " .. class_name(self))
end
function Ty.TPtr:tree_code_lower_expr_index_base(input, base, idx, elem_ty)
  local addr_result = base:lower_tree_expr_to_code(input:tree_code_expr_input())
  input = input:tree_code_with_result_state(addr_result)
  return TreeCode.TreeCodeIndexPlaceResult(Code.CodePlaceDeref(addr_result.value, input:tree_code_type(elem_ty), input:tree_code_align_of(elem_ty)), idx, input:tree_code_state())
end
function Ty.TView:tree_code_lower_expr_index_base(input, base, idx, elem_ty)
  local view_result = base:lower_tree_expr_to_code(input:tree_code_expr_input())
  input = input:tree_code_with_result_state(view_result)
  local view = view_result.value
  local data_result = input:tree_code_new_value("view_index_data")
  input = input:tree_code_with_result_state(data_result)
  local data = data_result.value
  local stride_result = input:tree_code_new_value("view_index_stride")
  input = input:tree_code_with_result_state(stride_result)
  local stride = stride_result.value
  local scaled_result = input:tree_code_new_value("view_index_scaled")
  input = input:tree_code_with_result_state(scaled_result)
  local scaled = scaled_result.value
  input = input:tree_code_with_result_state(input:tree_code_append_inst(Code.CodeInstViewData(data, view), origin_generated("view index data")))
  input = input:tree_code_with_result_state(input:tree_code_append_inst(Code.CodeInstViewStride(stride, view), origin_generated("view index stride")))
  input = input:tree_code_with_result_state(input:tree_code_append_inst(Code.CodeInstBinary(scaled, Core.BinMul, Code.CodeTyIndex, default_int_semantics(), idx, stride), origin_generated("view index scale")))
  return TreeCode.TreeCodeIndexPlaceResult(Code.CodePlaceDeref(data, input:tree_code_type(elem_ty), input:tree_code_align_of(elem_ty)), scaled, input:tree_code_state())
end
function Ty.TSlice:tree_code_lower_expr_index_base(input, base, idx, elem_ty)
  local slice_result = base:lower_tree_expr_to_code(input:tree_code_expr_input())
  input = input:tree_code_with_result_state(slice_result)
  local slice = slice_result.value
  local data_result = input:tree_code_new_value("slice_index_data")
  input = input:tree_code_with_result_state(data_result)
  local data = data_result.value
  input = input:tree_code_with_result_state(input:tree_code_append_inst(Code.CodeInstSliceData(data, slice), origin_generated("slice index data")))
  return TreeCode.TreeCodeIndexPlaceResult(Code.CodePlaceDeref(data, input:tree_code_type(elem_ty), input:tree_code_align_of(elem_ty)), idx, input:tree_code_state())
end
function Ty.TArray:tree_code_lower_expr_index_base(input, base, idx, elem_ty)
  local base_result = base:tree_code_as_place_result(input)
  input = input:tree_code_with_result_state(base_result)
  return TreeCode.TreeCodeIndexPlaceResult(base_result.place, idx, input:tree_code_state())
end
function Ty.Type:tree_code_lower_place_index_base(input, base, idx, elem_ty)
  local base_result = base:lower_tree_place_to_code(input:tree_code_place_input())
  input = input:tree_code_with_result_state(base_result)
  return TreeCode.TreeCodeIndexPlaceResult(base_result.place, idx, input:tree_code_state())
end
function Ty.TView:tree_code_lower_place_index_base(input, base, idx, elem_ty)
  local base_result = base:lower_tree_place_to_code(input:tree_code_place_input())
  input = input:tree_code_with_result_state(base_result)
  local view_result = input:tree_code_load_place(base_result.place, self, "view_index")
  input = input:tree_code_with_result_state(view_result)
  local view = view_result.value
  local data_result = input:tree_code_new_value("view_index_data"); input = input:tree_code_with_result_state(data_result); local data = data_result.value
  local stride_result = input:tree_code_new_value("view_index_stride"); input = input:tree_code_with_result_state(stride_result); local stride = stride_result.value
  local scaled_result = input:tree_code_new_value("view_index_scaled"); input = input:tree_code_with_result_state(scaled_result); local scaled = scaled_result.value
  input = input:tree_code_with_result_state(input:tree_code_append_inst(Code.CodeInstViewData(data, view), origin_generated("view index data")))
  input = input:tree_code_with_result_state(input:tree_code_append_inst(Code.CodeInstViewStride(stride, view), origin_generated("view index stride")))
  input = input:tree_code_with_result_state(input:tree_code_append_inst(Code.CodeInstBinary(scaled, Core.BinMul, Code.CodeTyIndex, default_int_semantics(), idx, stride), origin_generated("view index scale")))
  return TreeCode.TreeCodeIndexPlaceResult(Code.CodePlaceDeref(data, input:tree_code_type(elem_ty), input:tree_code_align_of(elem_ty)), scaled, input:tree_code_state())
end

function Tree.IndexBase:tree_code_lower_place(input, index, elem_ty)
  local index_expr_result = index:lower_tree_expr_to_code(input:tree_code_expr_input())
  input = input:tree_code_with_result_state(index_expr_result)
  local idx, idx_ty = index_expr_result.value, index_expr_result.ty
  local idx_result = input:tree_code_as_index_value(idx, idx_ty, "index")
  input = input:tree_code_with_result_state(idx_result)
  idx = idx_result.value
  local elem_size = input:tree_code_size_of(elem_ty)
  if elem_size == nil then unsupported(self, "index element without known size") end
  local base_result = self:tree_code_lower_index_base_place(input, idx, elem_ty)
  input = input:tree_code_with_result_state(base_result)
  return input:tree_code_place_result(Code.CodePlaceIndex(base_result.place, base_result.index, input:tree_code_type(elem_ty), elem_size))
end

----------------------------------------------------------------------
-- lower_tree_place_to_code on Tree.Place leaves
----------------------------------------------------------------------
function Tree.PlaceRef:lower_tree_place_to_code(input)
  local binding, key = self.ref:tree_code_lookup_binding(input)
  local global_place = binding.role:tree_code_global_place(input, binding)
  if global_place ~= nil then return input:tree_code_place_result(global_place) end
  local local_info = map_get(input:tree_code_state().bindings.locals_by_key, key)
  if local_info == nil then
    if map_get(input:tree_code_state().residence.addressed_by_key, key) ~= nil or map_get(input:tree_code_state().residence.mutable_by_key, key) ~= nil or input:tree_code_type(binding.ty):tree_code_is_aggregate_type() then
      local result = input:tree_code_ensure_local(binding, binding.ty)
      input = input:tree_code_with_result_state(result)
      local_info = map_get(input:tree_code_state().bindings.locals_by_key, key)
    else
      unsupported(self, "address/store of value-resident binding `" .. tostring(binding.name) .. "`")
    end
  end
  return input:tree_code_place_result(Code.CodePlaceLocal(local_info.binding.id, local_info.binding.ty))
end

function Tree.PlaceDeref:lower_tree_place_to_code(input)
  local addr_result = self.base:lower_tree_expr_to_code(input:tree_code_expr_input())
  input = input:tree_code_with_result_state(addr_result)
  local ty = self.h and self.h:tree_code_place_type()
  return input:tree_code_place_result(Code.CodePlaceDeref(addr_result.value, input:tree_code_type(ty), input:tree_code_align_of(ty)))
end

function Tree.PlaceField:lower_tree_place_to_code(input)
  self.field:tree_code_require_lowered_field(input)
  local base_ty = self.base.h and self.base.h:tree_code_place_type()
  if base_ty then base_ty = base_ty:tree_code_source_access_base() end
  local base_result = base_ty and base_ty:tree_code_lower_place_field_base(input, self.base) or self.base:lower_tree_place_to_code(input)
  input = input:tree_code_with_result_state(base_result)
  local field_layout = input:tree_code_layout_of(self.field.ty)
  return input:tree_code_place_result(Code.CodePlaceField(base_result.place, self.field, input:tree_code_type(self.field.ty), self.field.offset, field_layout and field_layout.size or nil, field_layout and field_layout.align or nil))
end

function Tree.PlaceIndex:lower_tree_place_to_code(input)
  local ty = self.h and self.h:tree_code_place_type()
  return self.base:tree_code_lower_place(input, self.index, ty)
end

function Tree.PlaceDot:lower_tree_place_to_code(input)
  unsupported(self, "dot place before sem_layout_resolve")
end

----------------------------------------------------------------------
-- lower_tree_expr_to_code on Tree.Expr leaves
----------------------------------------------------------------------
function Tree.ExprLit:lower_tree_expr_to_code(input)
  local expr_ty = self.h and self.h:tree_code_expr_type()
  return self.value:lower_tree_literal_to_code_aux(input, expr_ty)
end

function Core.Literal:lower_tree_literal_to_code_aux(input, source_ty)
  local ty = input:tree_code_type(source_ty)
  local dst_result = input:tree_code_new_value("lit"); input = input:tree_code_with_result_state(dst_result)
  input = input:tree_code_with_result_state(input:tree_code_append_inst(Code.CodeInstConst(dst_result.value, Code.CodeConstLiteral(ty, self)), origin_generated("literal")))
  return input:tree_code_expr_result(dst_result.value, ty)
end

function Core.LitString:lower_tree_literal_to_code_aux(input, source_ty)
  local ty = input:tree_code_type(source_ty)
  local elem_ty = u8_code_ty()
  local data_id, len_bytes = input:tree_code_fresh_string_data(self.bytes)
  local data_result = input:tree_code_new_value("str_data"); input = input:tree_code_with_result_state(data_result)
  input = input:tree_code_with_result_state(input:tree_code_append_inst(Code.CodeInstGlobalRef(data_result.value, Code.CodeGlobalRefData(data_id), Code.CodeTyDataPtr(elem_ty)), origin_generated("string literal data ref")))
  local len_result = input:tree_code_new_value("str_len"); input = input:tree_code_with_result_state(len_result)
  input = input:tree_code_with_result_state(input:tree_code_append_inst(Code.CodeInstConst(len_result.value, Code.CodeConstLiteral(Code.CodeTyIndex, Core.LitInt(tostring(len_bytes)))), origin_generated("string literal length")))
  local dst_result = input:tree_code_new_value("str"); input = input:tree_code_with_result_state(dst_result)
  input = input:tree_code_with_result_state(input:tree_code_append_inst(Code.CodeInstSliceMake(dst_result.value, elem_ty, data_result.value, len_result.value), origin_generated("string literal slice")))
  return input:tree_code_expr_result(dst_result.value, ty)
end

function Tree.ExprRef:lower_tree_expr_to_code(input)
  local result = self.ref:tree_code_lookup_value(input); input = input:tree_code_with_result_state(result)
  return input:tree_code_expr_result(result.value, result.ty)
end


function Tree.ExprUnary:lower_tree_expr_to_code(input)
  local value_result = self.value:lower_tree_expr_to_code(input:tree_code_expr_input()); input = input:tree_code_with_result_state(value_result)
  local expr_ty = self.h and self.h:tree_code_expr_type(); local ty = input:tree_code_type(expr_ty)
  local dst_result = input:tree_code_new_value("unary"); input = input:tree_code_with_result_state(dst_result)
  input = input:tree_code_with_result_state(input:tree_code_append_inst(Code.CodeInstUnary(dst_result.value, self.op, ty, value_result.value), origin_generated("unary")))
  return input:tree_code_expr_result(dst_result.value, ty)
end

function Tree.ExprBinary:lower_tree_expr_to_code(input)
  local lhs_result = self.lhs:lower_tree_expr_to_code(input:tree_code_expr_input()); input = input:tree_code_with_result_state(lhs_result)
  local rhs_result = self.rhs:lower_tree_expr_to_code(input:tree_code_expr_input()); input = input:tree_code_with_result_state(rhs_result)
  local lhs, lhs_ty = lhs_result.value, lhs_result.ty; local rhs, rhs_ty = rhs_result.value, rhs_result.ty
  local expr_ty = self.h and self.h:tree_code_expr_type(); local ty = input:tree_code_type(expr_ty)
  local dst_result = input:tree_code_new_value("bin"); input = input:tree_code_with_result_state(dst_result); local dst = dst_result.value
  local lhs_src = self.lhs.h and self.lhs.h:tree_code_expr_type(); if lhs_src then lhs_src = lhs_src:tree_code_source_access_base() end
  local rhs_src = self.rhs.h and self.rhs.h:tree_code_expr_type(); if rhs_src then rhs_src = rhs_src:tree_code_source_access_base() end
  local lhs_is_ptr = lhs_src and lhs_src:tree_code_is_ptr_type()
  local rhs_is_ptr = rhs_src and rhs_src:tree_code_is_ptr_type()
  if self.op == Core.BinAdd and (lhs_is_ptr or rhs_is_ptr) then
    local ptr_value, index_value, index_ty, elem_ty
    if lhs_is_ptr then ptr_value, index_value, index_ty, elem_ty = lhs, rhs, rhs_ty, lhs_src.elem
    else ptr_value, index_value, index_ty, elem_ty = rhs, lhs, lhs_ty, rhs_src.elem end
    local idx_r = input:tree_code_as_index_value(index_value, index_ty, "ptr_add_index"); input = input:tree_code_with_result_state(idx_r)
    local elem_size = input:tree_code_size_of(elem_ty)
    if elem_size == nil then unsupported(self, "pointer arithmetic element without known size") end
    input = input:tree_code_with_result_state(input:tree_code_append_inst(Code.CodeInstPtrOffset(dst, ty, ptr_value, idx_r.value, elem_size, 0), origin_generated("pointer add")))
  elseif self.op == Core.BinSub and lhs_is_ptr and not rhs_is_ptr then
    local idx_r = input:tree_code_as_index_value(rhs, rhs_ty, "ptr_sub_index"); input = input:tree_code_with_result_state(idx_r)
    local zero_r = input:tree_code_const_index(0, "ptr_sub_zero"); input = input:tree_code_with_result_state(zero_r)
    local neg_r = input:tree_code_new_value("ptr_sub_neg"); input = input:tree_code_with_result_state(neg_r)
    input = input:tree_code_with_result_state(input:tree_code_append_inst(Code.CodeInstBinary(neg_r.value, Core.BinSub, Code.CodeTyIndex, default_int_semantics(), zero_r.value, idx_r.value), origin_generated("pointer subtract index")))
    local elem_size = input:tree_code_size_of(lhs_src.elem)
    if elem_size == nil then unsupported(self, "pointer arithmetic element without known size") end
    input = input:tree_code_with_result_state(input:tree_code_append_inst(Code.CodeInstPtrOffset(dst, ty, lhs, neg_r.value, elem_size, 0), origin_generated("pointer subtract")))
  else
    if ty:tree_code_is_float_type() then
      input = input:tree_code_with_result_state(input:tree_code_append_inst(Code.CodeInstFloatBinary(dst, self.op, ty, default_float_mode(), lhs, rhs), origin_generated("float binary")))
    else
      input = input:tree_code_with_result_state(input:tree_code_append_inst(Code.CodeInstBinary(dst, self.op, ty, default_int_semantics(), lhs, rhs), origin_generated("binary")))
    end
  end
  return input:tree_code_expr_result(dst, ty)
end

function Tree.ExprCompare:lower_tree_expr_to_code(input)
  local lhs_result = self.lhs:lower_tree_expr_to_code(input:tree_code_expr_input()); input = input:tree_code_with_result_state(lhs_result)
  local rhs_result = self.rhs:lower_tree_expr_to_code(input:tree_code_expr_input()); input = input:tree_code_with_result_state(rhs_result)
  local lhs_ety = self.lhs.h and self.lhs.h:tree_code_expr_type(); local operand_ty = input:tree_code_type(lhs_ety)
  local dst_result = input:tree_code_new_value("cmp"); input = input:tree_code_with_result_state(dst_result)
  input = input:tree_code_with_result_state(input:tree_code_append_inst(Code.CodeInstCompare(dst_result.value, self.op, operand_ty, lhs_result.value, rhs_result.value), origin_generated("compare")))
  return input:tree_code_expr_result(dst_result.value, Code.CodeTyBool8)
end

function Tree.ExprCast:lower_tree_expr_to_code(input)
  local result = self.value:lower_tree_expr_to_code(input:tree_code_expr_input()); input = input:tree_code_with_result_state(result)
  local from = result.ty; local to = input:tree_code_type(self.ty or (self.h and self.h:tree_code_expr_type()))
  local dst_result = input:tree_code_new_value("cast"); input = input:tree_code_with_result_state(dst_result)
  input = input:tree_code_with_result_state(input:tree_code_append_inst(Code.CodeInstCast(dst_result.value, Core.MachineCastIdentity, from, to, result.value), origin_generated("cast")))
  return input:tree_code_expr_result(dst_result.value, to)
end

function Tree.ExprMachineCast:lower_tree_expr_to_code(input)
  local result = self.value:lower_tree_expr_to_code(input:tree_code_expr_input()); input = input:tree_code_with_result_state(result)
  local from = result.ty; local to = input:tree_code_type(self.ty or (self.h and self.h:tree_code_expr_type()))
  local dst_result = input:tree_code_new_value("cast"); input = input:tree_code_with_result_state(dst_result)
  input = input:tree_code_with_result_state(input:tree_code_append_inst(Code.CodeInstCast(dst_result.value, self.op, from, to, result.value), origin_generated("machine cast")))
  return input:tree_code_expr_result(dst_result.value, to)
end

function Tree.ExprAddrOf:lower_tree_expr_to_code(input)
  local place_result = self.place:lower_tree_place_to_code(input:tree_code_place_input()); input = input:tree_code_with_result_state(place_result)
  local expr_ty = self.h and self.h:tree_code_expr_type(); local ptr_ty = input:tree_code_type(expr_ty)
  local dst_result = input:tree_code_new_value("addr"); input = input:tree_code_with_result_state(dst_result)
  input = input:tree_code_with_result_state(input:tree_code_append_inst(Code.CodeInstAddrOf(dst_result.value, ptr_ty, place_result.place), origin_generated("address of")))
  return input:tree_code_expr_result(dst_result.value, ptr_ty)
end

function Tree.ExprDeref:lower_tree_expr_to_code(input)
  local addr_result = self.value:lower_tree_expr_to_code(input:tree_code_expr_input()); input = input:tree_code_with_result_state(addr_result)
  local expr_ty = self.h and self.h:tree_code_expr_type(); local cty = input:tree_code_type(expr_ty)
  local place = Code.CodePlaceDeref(addr_result.value, cty, input:tree_code_align_of(expr_ty))
  local load = input:tree_code_load_place(place, expr_ty, "deref"); input = input:tree_code_with_result_state(load)
  return input:tree_code_expr_result(load.value, load.ty)
end

function Tree.ExprCall:lower_tree_expr_to_code(input)
  local fn_ty = self.callee.h and self.callee.h:tree_code_expr_type()
  local sig = fn_ty and fn_ty:tree_code_call_sig_id(input)
  local args = {}
  for i = 1, #(self.args or {}) do
    local arg_result = self.args[i]:lower_tree_expr_to_code(input:tree_code_expr_input()); input = input:tree_code_with_result_state(arg_result)
    args[i] = arg_result.value
  end
  local target = self.callee:tree_code_direct_call_target()
  if target == nil then
    local callee_result = self.callee:lower_tree_expr_to_code(input:tree_code_expr_input()); input = input:tree_code_with_result_state(callee_result)
    target = fn_ty and fn_ty:tree_code_indirect_call_target(callee_result.value, sig)
  end
  local expr_ty = self.h and self.h:tree_code_expr_type(); local result_ty = input:tree_code_type(expr_ty)
  local dst = nil
  if result_ty ~= Code.CodeTyVoid then
    local dst_result = input:tree_code_new_value("call"); input = input:tree_code_with_result_state(dst_result)
    dst = dst_result.value
  end
  input = input:tree_code_with_result_state(input:tree_code_append_inst(Code.CodeInstCall(dst, target, sig, args), origin_generated("call")))
  return input:tree_code_expr_result(dst, result_ty)
end

function Tree.ExprField:lower_tree_expr_to_code(input)
  local place_result = self:tree_code_as_place_result(input); input = input:tree_code_with_result_state(place_result)
  local expr_ty = self.h and self.h:tree_code_expr_type()
  local load = input:tree_code_load_place(place_result.place, expr_ty, "field"); input = input:tree_code_with_result_state(load)
  return input:tree_code_expr_result(load.value, load.ty)
end

function Tree.ExprIndex:lower_tree_expr_to_code(input)
  local expr_ty = self.h and self.h:tree_code_expr_type()
  local place = self.base:tree_code_lower_place(input, self.index, expr_ty); input = input:tree_code_with_result_state(place)
  local load = input:tree_code_load_place(place.place, expr_ty, "index"); input = input:tree_code_with_result_state(load)
  return input:tree_code_expr_result(load.value, load.ty)
end

function Tree.ExprLoad:lower_tree_expr_to_code(input)
  local addr_result = self.addr:lower_tree_expr_to_code(input:tree_code_expr_input()); input = input:tree_code_with_result_state(addr_result)
  local ty = self.ty or (self.h and self.h:tree_code_expr_type()); local cty = input:tree_code_type(ty)
  local place = Code.CodePlaceDeref(addr_result.value, cty, input:tree_code_align_of(ty))
  local load = input:tree_code_load_place(place, ty, "load"); input = input:tree_code_with_result_state(load)
  return input:tree_code_expr_result(load.value, load.ty)
end

function Tree.ExprAtomicLoad:lower_tree_expr_to_code(input)
  local ty = self.ty or (self.h and self.h:tree_code_expr_type()); local cty = input:tree_code_type(ty)
  local addr_result = self.addr:lower_tree_expr_to_code(input:tree_code_expr_input()); input = input:tree_code_with_result_state(addr_result)
  local place = Code.CodePlaceDeref(addr_result.value, cty, input:tree_code_align_of(ty))
  local dst_result = input:tree_code_new_value("atomic_load"); input = input:tree_code_with_result_state(dst_result)
  input = input:tree_code_with_result_state(input:tree_code_append_inst(Code.CodeInstAtomicLoad(dst_result.value, place, input:tree_code_atomic_access(Code.CodeMemoryRead, ty, self.ordering), self.ordering), origin_generated("atomic load")))
  return input:tree_code_expr_result(dst_result.value, cty)
end

function Tree.ExprAtomicRmw:lower_tree_expr_to_code(input)
  local ty = self.ty or (self.h and self.h:tree_code_expr_type()); local cty = input:tree_code_type(ty)
  local addr_result = self.addr:lower_tree_expr_to_code(input:tree_code_expr_input()); input = input:tree_code_with_result_state(addr_result)
  local place = Code.CodePlaceDeref(addr_result.value, cty, input:tree_code_align_of(ty))
  local value_result = self.value:lower_tree_expr_to_code(input:tree_code_expr_input()); input = input:tree_code_with_result_state(value_result)
  local dst_result = input:tree_code_new_value("atomic_rmw"); input = input:tree_code_with_result_state(dst_result)
  input = input:tree_code_with_result_state(input:tree_code_append_inst(Code.CodeInstAtomicRmw(dst_result.value, self.op, place, value_result.value, input:tree_code_atomic_access(Code.CodeMemoryReadWrite, ty, self.ordering), self.ordering), origin_generated("atomic rmw")))
  return input:tree_code_expr_result(dst_result.value, cty)
end

function Tree.ExprAtomicCas:lower_tree_expr_to_code(input)
  local ty = self.ty or (self.h and self.h:tree_code_expr_type()); local cty = input:tree_code_type(ty)
  local addr_result = self.addr:lower_tree_expr_to_code(input:tree_code_expr_input()); input = input:tree_code_with_result_state(addr_result)
  local place = Code.CodePlaceDeref(addr_result.value, cty, input:tree_code_align_of(ty))
  local expected_result = self.expected:lower_tree_expr_to_code(input:tree_code_expr_input()); input = input:tree_code_with_result_state(expected_result)
  local replacement_result = self.replacement:lower_tree_expr_to_code(input:tree_code_expr_input()); input = input:tree_code_with_result_state(replacement_result)
  local dst_result = input:tree_code_new_value("atomic_cas"); input = input:tree_code_with_result_state(dst_result)
  input = input:tree_code_with_result_state(input:tree_code_append_inst(Code.CodeInstAtomicCas(dst_result.value, place, expected_result.value, replacement_result.value, input:tree_code_atomic_access(Code.CodeMemoryReadWrite, ty, self.ordering), self.ordering), origin_generated("atomic cas")))
  return input:tree_code_expr_result(dst_result.value, cty)
end

function Tree.ExprCtor:lower_tree_expr_to_code(input)
  if #(self.args or {}) > 1 then unsupported(self, "multi-argument variant constructor") end
  local def = input:tree_code_variant_def(self.type_name)
  local variant_entry = tree_code_variant_entry(def, self.variant_name)
  local variant = variant_entry and variant_entry.variant
  if variant == nil then unsupported(self, "unknown variant constructor") end
  local expr_ty = self.h and self.h:tree_code_expr_type(); local owner_ty = expr_ty
  local payload = nil
  if #(self.args or {}) == 1 then
    local pr = self.args[1]:lower_tree_expr_to_code(input:tree_code_expr_input()); input = input:tree_code_with_result_state(pr)
    payload = pr.value
  end
  local dst_result = input:tree_code_new_value("variant_ctor"); input = input:tree_code_with_result_state(dst_result)
  input = input:tree_code_with_result_state(input:tree_code_append_inst(Code.CodeInstVariantCtor(dst_result.value, input:tree_code_type(owner_ty), input:tree_code_variant_ref(owner_ty, variant), payload), origin_generated("variant constructor")))
  return input:tree_code_expr_result(dst_result.value, input:tree_code_type(owner_ty))
end

function Tree.ExprNull:lower_tree_expr_to_code(input)
  local expr_ty = self.h and self.h:tree_code_expr_type(); local ty = input:tree_code_type(expr_ty)
  local dst_result = input:tree_code_new_value("null"); input = input:tree_code_with_result_state(dst_result)
  input = input:tree_code_with_result_state(input:tree_code_append_inst(Code.CodeInstConst(dst_result.value, Code.CodeConstNull(ty)), origin_generated("null")))
  return input:tree_code_expr_result(dst_result.value, ty)
end

function Tree.ExprSizeOf:lower_tree_expr_to_code(input)
  local n = input:tree_code_size_of(self.ty)
  if n == nil then unsupported(self, "sizeof type without known layout") end
  local result = input:tree_code_const_index(n, "sizeof"); input = input:tree_code_with_result_state(result)
  return input:tree_code_expr_result(result.value, Code.CodeTyIndex)
end

function Tree.ExprAlignOf:lower_tree_expr_to_code(input)
  local result = input:tree_code_const_index(input:tree_code_align_of(self.ty), "alignof"); input = input:tree_code_with_result_state(result)
  return input:tree_code_expr_result(result.value, Code.CodeTyIndex)
end

function Tree.ExprIsNull:lower_tree_expr_to_code(input)
  local result = self.value:lower_tree_expr_to_code(input:tree_code_expr_input()); input = input:tree_code_with_result_state(result)
  local value, ty = result.value, result.ty
  local null_val_result = input:tree_code_new_value("null_cmp"); input = input:tree_code_with_result_state(null_val_result)
  input = input:tree_code_with_result_state(input:tree_code_append_inst(Code.CodeInstConst(null_val_result.value, Code.CodeConstNull(ty)), origin_generated("null compare literal")))
  local dst_result = input:tree_code_new_value("is_null"); input = input:tree_code_with_result_state(dst_result)
  input = input:tree_code_with_result_state(input:tree_code_append_inst(Code.CodeInstCompare(dst_result.value, Core.CmpEq, ty, value, null_val_result.value), origin_generated("is null")))
  return input:tree_code_expr_result(dst_result.value, Code.CodeTyBool8)
end

function Tree.ExprLen:lower_tree_expr_to_code(input)
  local val_ty = self.value.h and self.value.h:tree_code_expr_type()
  if val_ty then val_ty = val_ty:tree_code_source_access_base() end
  if val_ty then return val_ty:lower_tree_len_to_code(input, self) end
  unsupported(self, "len of unknown type")
end

function Tree.ExprView:lower_tree_expr_to_code(input)
  local view_parts = self.view:lower_tree_view_parts_to_code(input); input = input:tree_code_with_result_state(view_parts)
  local expr_ty = self.h and self.h:tree_code_expr_type(); local ty = input:tree_code_type(expr_ty)
  local dst_result = input:tree_code_new_value("view"); input = input:tree_code_with_result_state(dst_result)
  input = input:tree_code_with_result_state(input:tree_code_append_inst(Code.CodeInstViewMake(dst_result.value, ty.elem, view_parts.data, view_parts.len, view_parts.stride), origin_generated("view")))
  return input:tree_code_expr_result(dst_result.value, ty)
end

-- call_sig_id helpers on Ty.Type
function Ty.Type:tree_code_call_sig_id(input) unsupported(self, "non-callable type") end
function Ty.TFunc:tree_code_call_sig_id(input) return ensure_type_sig_s(self.params, self.result) end
function Ty.TClosure:tree_code_call_sig_id(input) return ensure_type_sig_s(self.params, self.result) end

-- direct_call_target helpers
function Tree.Expr:tree_code_direct_call_target() return nil end
function Tree.ExprRef:tree_code_direct_call_target() return self.ref:tree_code_direct_call_target() end
function Bind.ValueRef:tree_code_direct_call_target() return nil end
function Bind.ValueRefBinding:tree_code_direct_call_target() return self.binding.role:tree_code_direct_call_target(self.binding) end
function Bind.BindingRole:tree_code_direct_call_target(binding) return nil end
function Bind.BindingRoleGlobalFunc:tree_code_direct_call_target(binding) return Code.CodeCallDirect(code_func_id(self.item_name)) end
function Bind.BindingRoleExtern:tree_code_direct_call_target(binding) return Code.CodeCallExtern(code_extern_id(binding.name)) end

function Ty.Type:tree_code_indirect_call_target(callee, sig) return Code.CodeCallIndirect(callee, sig) end
function Ty.TClosure:tree_code_indirect_call_target(callee, sig) return Code.CodeCallClosure(callee, sig) end

-- len lowering on Ty.Type
function Ty.Type:lower_tree_len_to_code(input, expr) unsupported(expr, "len of non-array/view") end
function Ty.TArray:lower_tree_len_to_code(input, expr) return self.count:lower_tree_array_len_to_code(input, expr) end
function Ty.ArrayLen:lower_tree_array_len_to_code(input, expr) unsupported(expr, "len of non-constant array") end
function Ty.ArrayLenConst:lower_tree_array_len_to_code(input, expr)
  local result = input:tree_code_const_index(self.count, "array_len"); input = input:tree_code_with_result_state(result)
  return input:tree_code_expr_result(result.value, Code.CodeTyIndex)
end
function Ty.TView:lower_tree_len_to_code(input, expr)
  local view_result = expr.value:lower_tree_expr_to_code(input:tree_code_expr_input()); input = input:tree_code_with_result_state(view_result)
  local dst_result = input:tree_code_new_value("view_len"); input = input:tree_code_with_result_state(dst_result)
  input = input:tree_code_with_result_state(input:tree_code_append_inst(Code.CodeInstViewLen(dst_result.value, view_result.value), origin_generated("view len")))
  return input:tree_code_expr_result(dst_result.value, Code.CodeTyIndex)
end

-- Expr lowering (continued)
function Tree.ExprSelect:lower_tree_expr_to_code(input)
  local cond_result = self.cond:lower_tree_expr_to_code(input:tree_code_expr_input()); input = input:tree_code_with_result_state(cond_result)
  local then_val_result = self.then_expr:lower_tree_expr_to_code(input:tree_code_expr_input()); input = input:tree_code_with_result_state(then_val_result)
  local else_val_result = self.else_expr:lower_tree_expr_to_code(input:tree_code_expr_input()); input = input:tree_code_with_result_state(else_val_result)
  local expr_ty = self.h and self.h:tree_code_expr_type(); local ty = input:tree_code_type(expr_ty)
  local dst = input:tree_code_new_value("select"); input = input:tree_code_with_result_state(dst)
  input = input:tree_code_with_result_state(input:tree_code_append_inst(Code.CodeInstSelect(dst.value, ty, cond_result.value, then_val_result.value, else_val_result.value), origin_generated("select")))
  return input:tree_code_expr_result(dst.value, ty)
end

function Tree.ExprIntrinsic:lower_tree_expr_to_code(input)
  local args = {}
  for i = 1, #(self.args or {}) do
    local arg_r = self.args[i]:lower_tree_expr_to_code(input:tree_code_expr_input()); input = input:tree_code_with_result_state(arg_r); args[i] = arg_r.value
  end
  local expr_ty = self.h and self.h:tree_code_expr_type(); local ty = input:tree_code_type(expr_ty)
  local dst = nil
  if ty ~= Code.CodeTyVoid then
    local dst_r = input:tree_code_new_value("intrin"); input = input:tree_code_with_result_state(dst_r); dst = dst_r.value
  end
  local op = dst and Code.CodeInstIntrinsicValue(dst, self.op, ty, args) or Code.CodeInstIntrinsicVoid(self.op, ty, args)
  input = input:tree_code_with_result_state(input:tree_code_append_inst(op, origin_generated("intrinsic")))
  return input:tree_code_expr_result(dst, ty)
end

function Tree.ExprAgg:lower_tree_expr_to_code(input)
  local expr_ty = self.h and self.h:tree_code_expr_type(); local ty = input:tree_code_type(self.ty or expr_ty)
  local fields = {}
  for i = 1, #(self.fields or {}) do
    local fi = self.fields[i]
    local val_r = fi.value:lower_tree_expr_to_code(input:tree_code_expr_input()); input = input:tree_code_with_result_state(val_r)
    local fi_ty = fi.value.h and fi.value.h:tree_code_expr_type()
    fields[#fields + 1] = Code.CodeFieldValue(Sem.FieldByOffset(fi.name, fi.offset or 0, fi_ty or fi.ty, nil), val_r.value)
  end
  local dst_r = input:tree_code_new_value("agg"); input = input:tree_code_with_result_state(dst_r)
  input = input:tree_code_with_result_state(input:tree_code_append_inst(Code.CodeInstAggregate(dst_r.value, ty, fields), origin_generated("aggregate")))
  return input:tree_code_expr_result(dst_r.value, ty)
end

function Tree.ExprArray:lower_tree_expr_to_code(input)
  local expr_ty = self.h and self.h:tree_code_expr_type(); local ty = input:tree_code_type(expr_ty)
  local elems = {}
  for i = 1, #(self.elems or {}) do
    local er = self.elems[i]:lower_tree_expr_to_code(input:tree_code_expr_input()); input = input:tree_code_with_result_state(er)
    elems[#elems + 1] = Code.CodeArrayValue(i - 1, er.value)
  end
  local dst_r = input:tree_code_new_value("array"); input = input:tree_code_with_result_state(dst_r)
  input = input:tree_code_with_result_state(input:tree_code_append_inst(Code.CodeInstArray(dst_r.value, ty, elems), origin_generated("array")))
  return input:tree_code_expr_result(dst_r.value, ty)
end

function Tree.ExprBlock:lower_tree_expr_to_code(input)
  local saved = input:tree_code_save_bindings()
  local stmt_input = TreeCode.TreeCodeStmtInput(input:tree_code_func_facts(), input:tree_code_state())
  stmt_input = stmt_input:tree_code_lower_stmt_body(self.stmts or {})
  input = input:tree_code_with_result_state(TreeCode.TreeCodeStateResult(stmt_input:tree_code_state()))
  if not input:tree_code_state():tree_code_has_current_block() then unsupported(self, "block body terminated before result") end
  local result = self.result:lower_tree_expr_to_code(input:tree_code_expr_input()); input = input:tree_code_with_result_state(result)
  input = input:tree_code_with_result_state(input:tree_code_restore_bindings(saved))
  return input:tree_code_expr_result(result.value, result.ty)
end

function Tree.ExprIf:lower_tree_expr_to_code(input)
  local cr = self.cond:lower_tree_expr_to_code(input:tree_code_expr_input()); input = input:tree_code_with_result_state(cr)
  local then_id = input:tree_code_new_block("if_then"); input = input:tree_code_with_result_state(then_id)
  local else_id = input:tree_code_new_block("if_else"); input = input:tree_code_with_result_state(else_id)
  local join_id = input:tree_code_new_block("if_join"); input = input:tree_code_with_result_state(join_id)
  local expr_ty = self.h and self.h:tree_code_expr_type(); local res_ty = input:tree_code_type(expr_ty)
  local rv_r = input:tree_code_new_value("if_res"); input = input:tree_code_with_result_state(rv_r)
  local rp = Code.CodeParam(rv_r.value, "result", res_ty, origin_generated("if result"))
  local saved = input:tree_code_save_bindings()
  input = input:tree_code_with_result_state(input:tree_code_terminate(Code.CodeTermBranch(cr.value, then_id.id, {}, else_id.id, {}), origin_generated("if branch")))
  input = input:tree_code_with_result_state(input:tree_code_restore_bindings(saved))
  input = input:tree_code_with_result_state(input:tree_code_start_block(then_id.id, "if.then", {}, origin_generated("if then")))
  local tvr = self.then_expr:lower_tree_expr_to_code(input:tree_code_expr_input()); input = input:tree_code_with_result_state(tvr)
  input = input:tree_code_with_result_state(input:tree_code_terminate(Code.CodeTermJump(join_id.id, {tvr.value}), origin_generated("if then yield")))
  input = input:tree_code_with_result_state(input:tree_code_restore_bindings(saved))
  input = input:tree_code_with_result_state(input:tree_code_start_block(else_id.id, "if.else", {}, origin_generated("if else")))
  local evr = self.else_expr:lower_tree_expr_to_code(input:tree_code_expr_input()); input = input:tree_code_with_result_state(evr)
  input = input:tree_code_with_result_state(input:tree_code_terminate(Code.CodeTermJump(join_id.id, {evr.value}), origin_generated("if else yield")))
  input = input:tree_code_with_result_state(input:tree_code_restore_bindings(saved))
  input = input:tree_code_with_result_state(input:tree_code_start_block(join_id.id, "if.join", {rp}, origin_generated("if join")))
  return input:tree_code_expr_result(rv_r.value, res_ty)
end

function Tree.ExprLogic:lower_tree_expr_to_code(input)
  local lr = self.lhs:lower_tree_expr_to_code(input:tree_code_expr_input()); input = input:tree_code_with_result_state(lr)
  local rhs_id = input:tree_code_new_block("logic_rhs"); input = input:tree_code_with_result_state(rhs_id)
  local short_id = input:tree_code_new_block("logic_short"); input = input:tree_code_with_result_state(short_id)
  local join_id = input:tree_code_new_block("logic_join"); input = input:tree_code_with_result_state(join_id)
  local rv_r = input:tree_code_new_value("logic_res"); input = input:tree_code_with_result_state(rv_r)
  local rp = Code.CodeParam(rv_r.value, "result", Code.CodeTyBool8, origin_generated("logic result"))
  if self.op == Core.LogicAnd then
    input = input:tree_code_with_result_state(input:tree_code_terminate(Code.CodeTermBranch(lr.value, rhs_id.id, {}, short_id.id, {}), origin_generated("logic and")))
  else
    input = input:tree_code_with_result_state(input:tree_code_terminate(Code.CodeTermBranch(lr.value, short_id.id, {}, rhs_id.id, {}), origin_generated("logic or")))
  end
  local saved = input:tree_code_save_bindings()
  input = input:tree_code_with_result_state(input:tree_code_start_block(rhs_id.id, "logic.rhs", {}, origin_generated("logic rhs")))
  local rr = self.rhs:lower_tree_expr_to_code(input:tree_code_expr_input()); input = input:tree_code_with_result_state(rr)
  input = input:tree_code_with_result_state(input:tree_code_terminate(Code.CodeTermJump(join_id.id, {rr.value}), origin_generated("logic rhs yield")))
  input = input:tree_code_with_result_state(input:tree_code_restore_bindings(saved))
  input = input:tree_code_with_result_state(input:tree_code_start_block(short_id.id, "logic.short", {}, origin_generated("logic short")))
  local lit = self.op == Core.LogicAnd and Core.LitBool(false) or Core.LitBool(true)
  local sv_r = input:tree_code_new_value("logic_short"); input = input:tree_code_with_result_state(sv_r)
  input = input:tree_code_with_result_state(input:tree_code_append_inst(Code.CodeInstConst(sv_r.value, Code.CodeConstLiteral(Code.CodeTyBool8, lit)), origin_generated("logic short")))
  input = input:tree_code_with_result_state(input:tree_code_terminate(Code.CodeTermJump(join_id.id, {sv_r.value}), origin_generated("logic short yield")))
  input = input:tree_code_with_result_state(input:tree_code_restore_bindings(saved))
  input = input:tree_code_with_result_state(input:tree_code_start_block(join_id.id, "logic.join", {rp}, origin_generated("logic join")))
  return input:tree_code_expr_result(rv_r.value, Code.CodeTyBool8)
end


----------------------------------------------------------------------
-- Stmt lowering
----------------------------------------------------------------------
function Tree.StmtLet:lower_tree_stmt_to_code(input)
  local init = self.init:lower_tree_expr_to_code(input:tree_code_expr_input()); input = input:tree_code_with_result_state(init)
  local src, ty = init.value, init.ty
  local declared = input:tree_code_state():tree_code_declare_fresh_binding_key(self.binding); input = input:tree_code_with_result_state(declared)
  if input:tree_code_binding_is_addressed(self.binding) or (ty:tree_code_is_aggregate_type() and not ty:tree_code_is_view_type()) then
    input = input:tree_code_with_result_state(input:tree_code_bind_local_init(self.binding, src, self.binding.ty, false))
  else
    input = input:tree_code_with_result_state(input:tree_code_bind_alias(self.binding, src, ty))
  end
  return TreeCode.TreeCodeStmtResult(input:tree_code_state())
end

function Tree.StmtVar:lower_tree_stmt_to_code(input)
  local init = self.init:lower_tree_expr_to_code(input:tree_code_expr_input()); input = input:tree_code_with_result_state(init)
  input = input:tree_code_with_result_state(input:tree_code_state():tree_code_note_mutable(self.binding))
  input = input:tree_code_with_result_state(input:tree_code_bind_local_init(self.binding, init.value, self.binding.ty, true))
  return TreeCode.TreeCodeStmtResult(input:tree_code_state())
end

function Tree.StmtSet:lower_tree_stmt_to_code(input)
  local val_r = self.value:lower_tree_expr_to_code(input:tree_code_expr_input()); input = input:tree_code_with_result_state(val_r)
  local place_r = self.place:lower_tree_place_to_code(input:tree_code_place_input()); input = input:tree_code_with_result_state(place_r)
  local place_ty = self.place.h and self.place.h:tree_code_place_type()
  input = input:tree_code_with_result_state(input:tree_code_store_place(place_r.place, place_ty, val_r.value, origin_generated("set")))
  return TreeCode.TreeCodeStmtResult(input:tree_code_state())
end

function Tree.StmtAtomicStore:lower_tree_stmt_to_code(input)
  local val_r = self.value:lower_tree_expr_to_code(input:tree_code_expr_input()); input = input:tree_code_with_result_state(val_r)
  local addr_r = self.addr:lower_tree_expr_to_code(input:tree_code_expr_input()); input = input:tree_code_with_result_state(addr_r)
  local cty = input:tree_code_type(self.ty)
  local place = Code.CodePlaceDeref(addr_r.value, cty, input:tree_code_align_of(self.ty))
  input = input:tree_code_with_result_state(input:tree_code_append_inst(Code.CodeInstAtomicStore(place, val_r.value, input:tree_code_atomic_access(Code.CodeMemoryWrite, self.ty, self.ordering), self.ordering), origin_generated("atomic store")))
  return TreeCode.TreeCodeStmtResult(input:tree_code_state())
end

function Tree.StmtAtomicFence:lower_tree_stmt_to_code(input)
  input = input:tree_code_with_result_state(input:tree_code_append_inst(Code.CodeInstAtomicFence(self.ordering), origin_generated("atomic fence")))
  return TreeCode.TreeCodeStmtResult(input:tree_code_state())
end

function Tree.StmtExpr:lower_tree_stmt_to_code(input)
  local result = self.expr:lower_tree_expr_to_code(input:tree_code_expr_input()); input = input:tree_code_with_result_state(result)
  return TreeCode.TreeCodeStmtResult(input:tree_code_state())
end

function Tree.StmtAssert:lower_tree_stmt_to_code(input)
  local cr = self.cond:lower_tree_expr_to_code(input:tree_code_expr_input()); input = input:tree_code_with_result_state(cr)
  local ok_id = input:tree_code_new_block("assert_ok"); input = input:tree_code_with_result_state(ok_id)
  local trap_id = input:tree_code_new_block("assert_trap"); input = input:tree_code_with_result_state(trap_id)
  input = input:tree_code_with_result_state(input:tree_code_terminate(Code.CodeTermBranch(cr.value, ok_id.id, {}, trap_id.id, {}), origin_generated("assert branch")))
  input = input:tree_code_with_result_state(input:tree_code_start_block(trap_id.id, "assert.trap", {}, origin_generated("assert trap")))
  input = input:tree_code_with_result_state(input:tree_code_terminate(Code.CodeTermTrap("assertion failed"), origin_generated("assert trap")))
  input = input:tree_code_with_result_state(input:tree_code_start_block(ok_id.id, "assert.ok", {}, origin_generated("assert ok")))
  return TreeCode.TreeCodeStmtResult(input:tree_code_state())
end

function Tree.StmtIf:lower_tree_stmt_to_code(input)
  local cr = self.cond:lower_tree_expr_to_code(input:tree_code_expr_input()); input = input:tree_code_with_result_state(cr)
  local then_id = input:tree_code_new_block("if_then"); input = input:tree_code_with_result_state(then_id)
  local else_id = input:tree_code_new_block("if_else"); input = input:tree_code_with_result_state(else_id)
  local join_id = input:tree_code_new_block("if_join"); input = input:tree_code_with_result_state(join_id)
  local saved = input:tree_code_save_bindings()
  input = input:tree_code_with_result_state(input:tree_code_terminate(Code.CodeTermBranch(cr.value, then_id.id, {}, else_id.id, {}), origin_generated("if branch")))
  input = input:tree_code_with_result_state(input:tree_code_restore_bindings(saved))
  local then_fall = input:tree_code_lower_stmt_fallthrough_to(self.then_body, then_id.id, "if.then", join_id.id); input = input:tree_code_with_result_state(then_fall)
  input = input:tree_code_with_result_state(input:tree_code_restore_bindings(saved))
  local else_fall = input:tree_code_lower_stmt_fallthrough_to(self.else_body, else_id.id, "if.else", join_id.id); input = input:tree_code_with_result_state(else_fall)
  input = input:tree_code_with_result_state(input:tree_code_restore_bindings(saved))
  if then_fall.falls or else_fall.falls then
    input = input:tree_code_with_result_state(input:tree_code_start_block(join_id.id, "if.join", {}, origin_generated("if join")))
  end
  return TreeCode.TreeCodeStmtResult(input:tree_code_state())
end

function Tree.StmtJump:lower_tree_stmt_to_code(input)
  local region = input:tree_code_state():tree_code_current_control_region()
  if region == nil then unsupported(self, "jump outside control region") end
  local target = input:tree_code_state():tree_code_control_target(self.target)
  if target == nil then unsupported(self, "missing control target") end
  local args = {}
  local function find_jump_arg(nm) for _,a in ipairs(self.args or {}) do if a.name==nm then return a end end; unsupported(self,"missing jump arg "..nm) end
  for i = 1, #target.params do
    local arg = find_jump_arg(target.params[i].name)
    local arg_r = arg.value:lower_tree_expr_to_code(input:tree_code_expr_input()); input = input:tree_code_with_result_state(arg_r)
    args[#args+1] = arg_r.value
  end
  input = input:tree_code_with_result_state(input:tree_code_terminate(Code.CodeTermJump(target.id, args), origin_generated("control jump")))
  return TreeCode.TreeCodeStmtResult(input:tree_code_state())
end

function Tree.StmtYieldValue:lower_tree_stmt_to_code(input)
  local region = input:tree_code_state():tree_code_current_control_region()
  if region == nil then unsupported(self, "value yield outside control region") end
  local val_r = self.value:lower_tree_expr_to_code(input:tree_code_expr_input()); input = input:tree_code_with_result_state(val_r)
  input = input:tree_code_with_result_state(input:tree_code_state():tree_code_note_control_exit())
  input = input:tree_code_with_result_state(input:tree_code_terminate(Code.CodeTermJump(region:tree_code_yield_value_exit(input, self), {val_r.value}), origin_generated("control yield value")))
  return TreeCode.TreeCodeStmtResult(input:tree_code_state())
end

function Tree.StmtYieldVoid:lower_tree_stmt_to_code(input)
  local region = input:tree_code_state():tree_code_current_control_region()
  if region == nil then unsupported(self, "void yield outside control region") end
  input = input:tree_code_with_result_state(input:tree_code_state():tree_code_note_control_exit())
  input = input:tree_code_with_result_state(input:tree_code_terminate(Code.CodeTermJump(region:tree_code_yield_void_exit(input, self), {}), origin_generated("control yield")))
  return TreeCode.TreeCodeStmtResult(input:tree_code_state())
end

function Tree.StmtReturnValue:lower_tree_stmt_to_code(input)
  local val_r = self.value:lower_tree_expr_to_code(input:tree_code_expr_input()); input = input:tree_code_with_result_state(val_r)
  input = input:tree_code_with_result_state(input:tree_code_terminate(Code.CodeTermReturn({val_r.value}), origin_generated("return")))
  return TreeCode.TreeCodeStmtResult(input:tree_code_state())
end

function Tree.StmtReturnVoid:lower_tree_stmt_to_code(input)
  input = input:tree_code_with_result_state(input:tree_code_terminate(Code.CodeTermReturn({}), origin_generated("return")))
  return TreeCode.TreeCodeStmtResult(input:tree_code_state())
end

function Tree.StmtTrap:lower_tree_stmt_to_code(input)
  input = input:tree_code_with_result_state(input:tree_code_terminate(Code.CodeTermTrap("source trap"), origin_generated("trap")))
  return TreeCode.TreeCodeStmtResult(input:tree_code_state())
end

function Tree.StmtControl:lower_tree_stmt_to_code(input) return self.region:tree_code_lower_stmt_control_to_code(input) end
function Tree.StmtJumpCont:lower_tree_stmt_to_code(input) unsupported(self, "continuation slot jump") end
function Tree.StmtRegionEmit:lower_tree_stmt_to_code(input) unsupported(self, "region emit before expansion") end
function Tree.StmtRegionCall:lower_tree_stmt_to_code(input) unsupported(self, "region call before expansion") end

function Tree.ExprDot:lower_tree_expr_to_code(input) unsupported(self, "dot expr before sem_layout_resolve") end
function Tree.ExprClosure:lower_tree_expr_to_code(input) unsupported(self, "closure expr before closure_convert") end

----------------------------------------------------------------------
-- Switch lowering
----------------------------------------------------------------------
function Tree.SwitchKeyInt:tree_code_switch_literal() return Core.LitInt(self.raw) end
function Tree.SwitchKeyBool:tree_code_switch_literal() return Core.LitBool(self.value) end
function Tree.SwitchKeyName:tree_code_switch_literal() unsupported(self, "named switch case requires resolved key") end
function Tree.SwitchKeyExpr:tree_code_switch_literal() unsupported(self, "expression switch case requires compare-fallback") end

function Tree.SwitchVariantStmtArm:tree_code_bind_variant_payload(input, kind, owner_value, owner_ty, variant)
  if #(self.binds or {}) == 0 then return TreeCode.TreeCodeStateResult(input:tree_code_state()) end
  if #(self.binds or {}) > 1 then unsupported(self, "multi-bind variant arm") end
  local payload_ty = input:tree_code_variant_payload_type(variant)
  if payload_ty == nil then unsupported(self, "payload bind for void variant") end
  local ref = input:tree_code_variant_ref(owner_ty, variant)
  local payload_r = input:tree_code_new_value("variant_payload"); input = input:tree_code_with_result_state(payload_r)
  input = input:tree_code_with_result_state(input:tree_code_append_inst(Code.CodeInstVariantPayload(payload_r.value, ref, owner_value), origin_generated("variant payload")))
  local binding = variant_binding(kind, variant, self.binds[1])
  local cty = input:tree_code_type(binding.ty)
  if input:tree_code_binding_is_addressed(binding) or cty:tree_code_is_aggregate_type() then
    input = input:tree_code_with_result_state(input:tree_code_bind_local_init(binding, payload_r.value, binding.ty, false))
  else
    input = input:tree_code_with_result_state(input:tree_code_bind_alias(binding, payload_r.value, cty))
  end
  return TreeCode.TreeCodeStateResult(input:tree_code_state())
end

function Tree.SwitchVariantExprArm:tree_code_bind_variant_payload(input, kind, owner_value, owner_ty, variant)
  if #(self.binds or {}) == 0 then return TreeCode.TreeCodeStateResult(input:tree_code_state()) end
  if #(self.binds or {}) > 1 then unsupported(self, "multi-bind variant arm") end
  local payload_ty = input:tree_code_variant_payload_type(variant)
  if payload_ty == nil then unsupported(self, "payload bind for void variant") end
  local ref = input:tree_code_variant_ref(owner_ty, variant)
  local payload_r = input:tree_code_new_value("variant_payload"); input = input:tree_code_with_result_state(payload_r)
  input = input:tree_code_with_result_state(input:tree_code_append_inst(Code.CodeInstVariantPayload(payload_r.value, ref, owner_value), origin_generated("variant payload")))
  local binding = variant_binding(kind, variant, self.binds[1])
  local cty = input:tree_code_type(binding.ty)
  if input:tree_code_binding_is_addressed(binding) or cty:tree_code_is_aggregate_type() then
    input = input:tree_code_with_result_state(input:tree_code_bind_local_init(binding, payload_r.value, binding.ty, false))
  else
    input = input:tree_code_with_result_state(input:tree_code_bind_alias(binding, payload_r.value, cty))
  end
  return TreeCode.TreeCodeStateResult(input:tree_code_state())
end

-- StmtSwitch following the old tree_lower pattern with variant and scalar arms
function Tree.StmtSwitch:lower_tree_stmt_to_code(input)
  if #(self.variant_arms or {}) > 0 then
    if #(self.arms or {}) > 0 then unsupported(self, "mixed scalar and variant switch arms") end
    local owner_ty = self.value.h and self.value.h:tree_code_expr_type()
    local type_name = owner_ty and owner_ty:tree_code_named_type_name()
    local def = type_name and input:tree_code_variant_def(type_name)
    if def == nil then unsupported(self, "variant switch without tagged-union facts") end
    local vr = self.value:lower_tree_expr_to_code(input:tree_code_expr_input()); input = input:tree_code_with_result_state(vr)
    local tr = input:tree_code_new_value("variant_tag"); input = input:tree_code_with_result_state(tr)
    input = input:tree_code_with_result_state(input:tree_code_append_inst(Code.CodeInstVariantTag(tr.value, Code.CodeTyInt(32, Code.CodeUnsigned), vr.value), origin_generated("variant tag")))
    local cids, cases = {}, {}
    for i = 1, #(self.variant_arms or {}) do
      local ve = tree_code_variant_entry(def, self.variant_arms[i].variant_name); local v = ve and ve.variant
      if v == nil then unsupported(self, "unknown variant arm") end
      local bid_r = input:tree_code_new_block("switch_variant"); input = input:tree_code_with_result_state(bid_r)
      cids[i] = bid_r.id; cases[i] = Code.CodeVariantCase(input:tree_code_variant_ref(owner_ty, v), bid_r.id, {})
    end
    local did_r = input:tree_code_new_block("switch_variant_def"); input = input:tree_code_with_result_state(did_r)
    local jid_r = input:tree_code_new_block("switch_variant_join"); input = input:tree_code_with_result_state(jid_r)
    local saved = input:tree_code_save_bindings()
    input = input:tree_code_with_result_state(input:tree_code_terminate(Code.CodeTermVariantSwitch(tr.value, cases, did_r.id, {}), origin_generated("variant switch")))
    local any_falls = false
    for i = 1, #(self.variant_arms or {}) do
      input = input:tree_code_with_result_state(input:tree_code_restore_bindings(saved))
      local ve = tree_code_variant_entry(def, self.variant_arms[i].variant_name); local v = ve and ve.variant
      input = input:tree_code_with_result_state(input:tree_code_start_block(cids[i], "switch.variant", {}, origin_generated("variant case")))
      input = input:tree_code_with_result_state(self.variant_arms[i]:tree_code_bind_variant_payload(input, "stmt_switch", vr.value, owner_ty, v))
      local bi = TreeCode.TreeCodeStmtInput(input:tree_code_func_facts(), input:tree_code_state()); bi = bi:tree_code_lower_stmt_body(self.variant_arms[i].body or {})
      input = input:tree_code_with_result_state(TreeCode.TreeCodeStateResult(bi:tree_code_state()))
      if input:tree_code_state():tree_code_has_current_block() then input = input:tree_code_with_result_state(input:tree_code_terminate(Code.CodeTermJump(jid_r.id, {}), origin_generated("variant fallthrough"))); any_falls = true end
    end
    input = input:tree_code_with_result_state(input:tree_code_restore_bindings(saved))
    local df = input:tree_code_lower_stmt_fallthrough_to(self.default_body or {}, did_r.id, "switch.variant.def", jid_r.id); input = input:tree_code_with_result_state(df)
    if df.falls then any_falls = true end
    input = input:tree_code_with_result_state(input:tree_code_restore_bindings(saved))
    if any_falls then input = input:tree_code_with_result_state(input:tree_code_start_block(jid_r.id, "switch.variant.join", {}, origin_generated("variant join"))) end
    return TreeCode.TreeCodeStmtResult(input:tree_code_state())
  end
  -- scalar switch
  local vr = self.value:lower_tree_expr_to_code(input:tree_code_expr_input()); input = input:tree_code_with_result_state(vr)
  local cids, cases = {}, {}
  for i = 1, #(self.arms or {}) do
    local bid_r = input:tree_code_new_block("switch_case"); input = input:tree_code_with_result_state(bid_r)
    cids[i] = bid_r.id; cases[i] = Code.CodeSwitchCase(self.arms[i].key:tree_code_switch_literal(), bid_r.id, {})
  end
  local did_r = input:tree_code_new_block("switch_default"); input = input:tree_code_with_result_state(did_r)
  local jid_r = input:tree_code_new_block("switch_join"); input = input:tree_code_with_result_state(jid_r)
  local saved = input:tree_code_save_bindings()
  input = input:tree_code_with_result_state(input:tree_code_terminate(Code.CodeTermSwitch(vr.value, cases, did_r.id, {}), origin_generated("switch")))
  local any_falls = false
  for i = 1, #(self.arms or {}) do
    input = input:tree_code_with_result_state(input:tree_code_restore_bindings(saved))
    local cf = input:tree_code_lower_stmt_fallthrough_to(self.arms[i].body, cids[i], "switch.case", jid_r.id); input = input:tree_code_with_result_state(cf)
    if cf.falls then any_falls = true end
  end
  input = input:tree_code_with_result_state(input:tree_code_restore_bindings(saved))
  local df = input:tree_code_lower_stmt_fallthrough_to(self.default_body or {}, did_r.id, "switch.default", jid_r.id); input = input:tree_code_with_result_state(df)
  if df.falls then any_falls = true end
  input = input:tree_code_with_result_state(input:tree_code_restore_bindings(saved))
  if any_falls then input = input:tree_code_with_result_state(input:tree_code_start_block(jid_r.id, "switch.join", {}, origin_generated("switch join"))) end
  return TreeCode.TreeCodeStmtResult(input:tree_code_state())
end

function Tree.ExprSwitch:lower_tree_expr_to_code(input)
  if #(self.variant_arms or {}) > 0 then unsupported(self, "ExprSwitch variant — complex; see old tree_lower for full impl") end
  local vr = self.value:lower_tree_expr_to_code(input:tree_code_expr_input()); input = input:tree_code_with_result_state(vr)
  local ety = self.h and self.h:tree_code_expr_type(); local rty = input:tree_code_type(ety)
  local rvr = input:tree_code_new_value("switch_res"); input = input:tree_code_with_result_state(rvr)
  local rp = Code.CodeParam(rvr.value, "result", rty, origin_generated("switch result"))
  local cids, cases = {}, {}
  for i = 1, #(self.arms or {}) do
    local br = input:tree_code_new_block("expr_switch"); input = input:tree_code_with_result_state(br); cids[i] = br.id
    cases[i] = Code.CodeSwitchCase(self.arms[i].key:tree_code_switch_literal(), br.id, {})
  end
  local did_r = input:tree_code_new_block("expr_switch_def"); input = input:tree_code_with_result_state(did_r)
  local jid_r = input:tree_code_new_block("expr_switch_join"); input = input:tree_code_with_result_state(jid_r)
  local saved = input:tree_code_save_bindings()
  input = input:tree_code_with_result_state(input:tree_code_terminate(Code.CodeTermSwitch(vr.value, cases, did_r.id, {}), origin_generated("expr switch")))
  local any_falls = false
  for i = 1, #(self.arms or {}) do
    input = input:tree_code_with_result_state(input:tree_code_restore_bindings(saved))
    input = input:tree_code_with_result_state(input:tree_code_start_block(cids[i], "expr.switch", {}, origin_generated("expr switch case")))
    local bi = TreeCode.TreeCodeStmtInput(input:tree_code_func_facts(), input:tree_code_state()); bi = bi:tree_code_lower_stmt_body(self.arms[i].body or {})
    input = input:tree_code_with_result_state(TreeCode.TreeCodeStateResult(bi:tree_code_state()))
    if input:tree_code_state():tree_code_has_current_block() then
      local ar = self.arms[i].result:lower_tree_expr_to_code(input:tree_code_expr_input()); input = input:tree_code_with_result_state(ar)
      input = input:tree_code_with_result_state(input:tree_code_terminate(Code.CodeTermJump(jid_r.id, {ar.value}), origin_generated("expr switch yield"))); any_falls = true
    end
  end
  input = input:tree_code_with_result_state(input:tree_code_restore_bindings(saved))
  input = input:tree_code_with_result_state(input:tree_code_start_block(did_r.id, "expr.switch.def", {}, origin_generated("expr switch default")))
  local bi = TreeCode.TreeCodeStmtInput(input:tree_code_func_facts(), input:tree_code_state()); bi = bi:tree_code_lower_stmt_body(self.default_body or {})
  input = input:tree_code_with_result_state(TreeCode.TreeCodeStateResult(bi:tree_code_state()))
  if input:tree_code_state():tree_code_has_current_block() then
    local dr = self.default_expr:lower_tree_expr_to_code(input:tree_code_expr_input()); input = input:tree_code_with_result_state(dr)
    input = input:tree_code_with_result_state(input:tree_code_terminate(Code.CodeTermJump(jid_r.id, {dr.value}), origin_generated("expr switch def yield"))); any_falls = true
  end
  input = input:tree_code_with_result_state(input:tree_code_restore_bindings(saved))
  if not any_falls then unsupported(self, "switch expression has no value-producing arm") end
  input = input:tree_code_with_result_state(input:tree_code_start_block(jid_r.id, "expr.switch.join", {rp}, origin_generated("expr switch join")))
  return input:tree_code_expr_result(rvr.value, rty)
end

----------------------------------------------------------------------
-- View parts lowering
----------------------------------------------------------------------
function Tree.View:lower_tree_view_parts_to_code(input) unsupported(input, "view form") end
function Tree.ViewFromExpr:lower_tree_view_parts_to_code(input)
  local val_ty = self.base.h and self.base.h:tree_code_expr_type()
  if val_ty then val_ty = val_ty:tree_code_source_access_base() end
  if val_ty then return val_ty:tree_code_lower_view_from_expr(input, self) end
  unsupported(input, "view-from expression without type")
end
function Ty.Type:tree_code_lower_view_from_expr(input, view) unsupported(view, "view-from expression type") end
function Ty.TPtr:tree_code_lower_view_from_expr(input, view)
  local dr = view.base:lower_tree_expr_to_code(input:tree_code_expr_input()); input = input:tree_code_with_result_state(dr)
  local lr = input:tree_code_const_index(1, "view_len"); input = input:tree_code_with_result_state(lr)
  local sr = input:tree_code_const_index(1, "view_stride"); input = input:tree_code_with_result_state(sr)
  return TreeCode.TreeCodeViewPartsResult(dr.value, lr.value, sr.value, input:tree_code_state())
end
function Ty.TView:tree_code_lower_view_from_expr(input, view)
  local br = view.base:lower_tree_expr_to_code(input:tree_code_expr_input()); input = input:tree_code_with_result_state(br)
  local dr = input:tree_code_new_value("view_data"); input = input:tree_code_with_result_state(dr)
  local lr = input:tree_code_new_value("view_len"); input = input:tree_code_with_result_state(lr)
  local sr = input:tree_code_new_value("view_stride"); input = input:tree_code_with_result_state(sr)
  input = input:tree_code_with_result_state(input:tree_code_append_inst(Code.CodeInstViewData(dr.value, br.value), origin_generated("view data")))
  input = input:tree_code_with_result_state(input:tree_code_append_inst(Code.CodeInstViewLen(lr.value, br.value), origin_generated("view len")))
  input = input:tree_code_with_result_state(input:tree_code_append_inst(Code.CodeInstViewStride(sr.value, br.value), origin_generated("view stride")))
  return TreeCode.TreeCodeViewPartsResult(dr.value, lr.value, sr.value, input:tree_code_state())
end
function Tree.ViewContiguous:lower_tree_view_parts_to_code(input)
  local dr = self.data:lower_tree_expr_to_code(input:tree_code_expr_input()); input = input:tree_code_with_result_state(dr)
  local idx_r = self.len:tree_code_lower_index_value(input, "view_len"); input = input:tree_code_with_result_state(idx_r)
  local sr = input:tree_code_const_index(1, "view_stride"); input = input:tree_code_with_result_state(sr)
  return TreeCode.TreeCodeViewPartsResult(dr.value, idx_r.value, sr.value, input:tree_code_state())
end
function Tree.ViewStrided:lower_tree_view_parts_to_code(input)
  local dr = self.data:lower_tree_expr_to_code(input:tree_code_expr_input()); input = input:tree_code_with_result_state(dr)
  local lr = self.len:tree_code_lower_index_value(input, "view_len"); input = input:tree_code_with_result_state(lr)
  local sr = self.stride:tree_code_lower_index_value(input, "view_stride"); input = input:tree_code_with_result_state(sr)
  return TreeCode.TreeCodeViewPartsResult(dr.value, lr.value, sr.value, input:tree_code_state())
end
function Tree.ViewRestrided:lower_tree_view_parts_to_code(input)
  local br = self.base:lower_tree_view_parts_to_code(input); input = input:tree_code_with_result_state(br)
  local sr = self.stride:tree_code_lower_index_value(input, "view_stride"); input = input:tree_code_with_result_state(sr)
  return TreeCode.TreeCodeViewPartsResult(br.data, br.len, sr.value, input:tree_code_state())
end
function Tree.ViewWindow:lower_tree_view_parts_to_code(input)
  local br = self.base:lower_tree_view_parts_to_code(input); input = input:tree_code_with_result_state(br)
  local srt = self.start:tree_code_lower_index_value(input, "view_win_start"); input = input:tree_code_with_result_state(srt)
  local scaled = input:tree_code_index_mul(srt.value, br.stride, "view_win_start"); input = input:tree_code_with_result_state(scaled)
  local dr = input:tree_code_data_offset(self, br.data, scaled.value, self.elem, "view_win_data"); input = input:tree_code_with_result_state(dr)
  local lr = self.len:tree_code_lower_index_value(input, "view_win_len"); input = input:tree_code_with_result_state(lr)
  return TreeCode.TreeCodeViewPartsResult(dr.value, lr.value, br.stride, input:tree_code_state())
end
function Tree.ViewRowBase:lower_tree_view_parts_to_code(input)
  local br = self.base:lower_tree_view_parts_to_code(input); input = input:tree_code_with_result_state(br)
  local rr = self.row_offset:tree_code_lower_index_value(input, "view_row"); input = input:tree_code_with_result_state(rr)
  local scaled = input:tree_code_index_mul(rr.value, br.stride, "view_row"); input = input:tree_code_with_result_state(scaled)
  local dr = input:tree_code_data_offset(self, br.data, scaled.value, self.elem, "view_row_data"); input = input:tree_code_with_result_state(dr)
  return TreeCode.TreeCodeViewPartsResult(dr.value, br.len, br.stride, input:tree_code_state())
end
function Tree.ViewInterleaved:lower_tree_view_parts_to_code(input)
  local dr = self.data:lower_tree_expr_to_code(input:tree_code_expr_input()); input = input:tree_code_with_result_state(dr)
  local lr = self.len:tree_code_lower_index_value(input, "view_len"); input = input:tree_code_with_result_state(lr)
  local sr = self.stride:tree_code_lower_index_value(input, "view_stride"); input = input:tree_code_with_result_state(sr)
  local lane_r = self.lane:tree_code_lower_index_value(input, "view_lane"); input = input:tree_code_with_result_state(lane_r)
  local idata = input:tree_code_data_offset(self, dr.value, lane_r.value, self.elem, "view_interleaved"); input = input:tree_code_with_result_state(idata)
  return TreeCode.TreeCodeViewPartsResult(idata.value, lr.value, sr.value, input:tree_code_state())
end
function Tree.ViewInterleavedView:lower_tree_view_parts_to_code(input)
  local br = self.base:lower_tree_view_parts_to_code(input); input = input:tree_code_with_result_state(br)
  local sf = self.stride:tree_code_lower_index_value(input, "view_stride"); input = input:tree_code_with_result_state(sf)
  local ln = self.lane:tree_code_lower_index_value(input, "view_lane"); input = input:tree_code_with_result_state(ln)
  local lo = input:tree_code_index_mul(ln.value, br.stride, "view_lane"); input = input:tree_code_with_result_state(lo)
  local st = input:tree_code_index_mul(br.stride, sf.value, "view_stride"); input = input:tree_code_with_result_state(st)
  local dr = input:tree_code_data_offset(self, br.data, lo.value, self.elem, "view_interleaved"); input = input:tree_code_with_result_state(dr)
  return TreeCode.TreeCodeViewPartsResult(dr.value, br.len, st.value, input:tree_code_state())
end

function Tree.Expr:tree_code_lower_index_value(input, reason)
  local result = self:lower_tree_expr_to_code(input:tree_code_expr_input()); input = input:tree_code_with_result_state(result)
  return input:tree_code_as_index_value(result.value, result.ty, reason)
end

----------------------------------------------------------------------
-- Control region lowering
----------------------------------------------------------------------
function TreeCode.TreeCodeExprControlRegion:tree_code_yield_value_exit(input, stmt) return self.exit_id end
function TreeCode.TreeCodeStmtControlRegion:tree_code_yield_value_exit(input, stmt) unsupported(stmt, "value yield outside expr control region") end
function TreeCode.TreeCodeExprControlRegion:tree_code_yield_void_exit(input, stmt) unsupported(stmt, "void yield outside stmt control region") end
function TreeCode.TreeCodeStmtControlRegion:tree_code_yield_void_exit(input, stmt) return self.exit_id end

function Tree.ControlExprRegion:tree_code_lower_expr_control_to_code(input)
  local rty = input:tree_code_type(self.result_ty)
  local rva = input:tree_code_new_value("ctl_res"); input = input:tree_code_with_result_state(rva)
  local xp = { Code.CodeParam(rva.value, "result", rty, origin_generated("control result")) }
  local saved_a, saved_as = input:tree_code_state():tree_code_alpha_snapshot()
  local ac = input:tree_code_state():tree_code_next_counter("control_scope"); input = input:tree_code_with_result_state(ac)
  local alpha_s = "ctl" .. tostring(ac.value)
  local ar = input:tree_code_state():tree_code_fork_alpha(alpha_s); input = input:tree_code_with_result_state(ar)
  local records, targets = {}, {}
  local function add_record(block, is_entry)
    local br = input:tree_code_new_block("ctl_" .. block.label.name); input = input:tree_code_with_result_state(br)
    local params, binds = {}, {}
    for i = 1, #(block.params or {}) do
      local b = control_binding(self.region_id, block.label, block.params[i], i, is_entry)
      local dk = input:tree_code_state():tree_code_declare_binding_key(b); input = input:tree_code_with_result_state(dk)
      local v = input:tree_code_value_id_for_binding(b)
      local cty = input:tree_code_type(block.params[i].ty)
      params[#params+1] = Code.CodeParam(v, block.params[i].name, cty, origin_binding(b))
      binds[#binds+1] = {binding=b, value=v, ty=block.params[i].ty, cty=cty}
    end
    local rec = {id=br.id, label=block.label, name="ctl."..block.label.name, params=params, binds=binds, body=block.body or {}, entry=is_entry, entry_params=block.params or {}}
    records[#records+1] = rec
    targets[#targets+1] = TreeCode.TreeCodeControlTargetEntry(label_key(block.label), TreeCode.TreeCodeControlTarget(br.id, params))
    return rec
  end
  local entry = add_record(self.entry, true)
  for i = 1, #(self.blocks or {}) do add_record(self.blocks[i], false) end
  local region_alpha = clone_map(input:tree_code_state().alpha.renamed_by_key)
  local exr = input:tree_code_new_block("ctl_expr_exit"); input = input:tree_code_with_result_state(exr)
  local saved_outer = input:tree_code_save_bindings()
  local entry_args = {}
  input = input:tree_code_with_result_state(input:tree_code_state():tree_code_use_alpha(saved_a, saved_as))
  for i = 1, #(self.entry.params or {}) do
    local ear = self.entry.params[i].init:lower_tree_expr_to_code(input:tree_code_expr_input()); input = input:tree_code_with_result_state(ear)
    entry_args[#entry_args+1] = ear.value
  end
  input = input:tree_code_with_result_state(input:tree_code_state():tree_code_use_alpha(region_alpha, alpha_s))
  input = input:tree_code_with_result_state(input:tree_code_terminate(Code.CodeTermJump(entry.id, entry_args), origin_generated("enter control region")))
  local ctrl_region = TreeCode.TreeCodeExprControlRegion(exr.id, targets)
  input = input:tree_code_with_result_state(input:tree_code_state():tree_code_enter_control_region(ctrl_region))
  for i = 1, #records do
    local rec = records[i]
    input = input:tree_code_with_result_state(input:tree_code_restore_bindings(saved_outer))
    input = input:tree_code_with_result_state(input:tree_code_state():tree_code_use_alpha(setmetatable({},{__index=region_alpha}), alpha_s.."_b"..tostring(i)))
    input = input:tree_code_with_result_state(input:tree_code_start_block(rec.id, rec.name, rec.params, origin_generated("control block "..rec.label.name)))
    for j = 1, #rec.binds do
      local b = rec.binds[j]
      input = input:tree_code_with_result_state(input:tree_code_state():tree_code_note_binding(b.binding, b.value))
      if input:tree_code_binding_is_addressed(b.binding) or b.cty:tree_code_is_aggregate_type() then
        input = input:tree_code_with_result_state(input:tree_code_bind_local_init(b.binding, b.value, b.ty, false))
      end
    end
    local bi = TreeCode.TreeCodeStmtInput(input:tree_code_func_facts(), input:tree_code_state()); bi = bi:tree_code_lower_stmt_body(rec.body)
    input = input:tree_code_with_result_state(TreeCode.TreeCodeStateResult(bi:tree_code_state()))
    if input:tree_code_state():tree_code_has_current_block() then unsupported(rec.label, "control block can fall through") end
  end
  local exit_result = input:tree_code_state():tree_code_leave_control_region(); input = input:tree_code_with_result_state(exit_result)
  input = input:tree_code_with_result_state(input:tree_code_state():tree_code_use_alpha(saved_a, saved_as))
  input = input:tree_code_with_result_state(input:tree_code_restore_bindings(saved_outer))
  input = input:tree_code_with_result_state(input:tree_code_start_block(exr.id, "ctl.expr.exit", xp, origin_generated("control exit")))
  return input:tree_code_expr_result(rva.value, rty)
end

function Tree.ControlStmtRegion:tree_code_lower_stmt_control_to_code(input)
  local saved_a, saved_as = input:tree_code_state():tree_code_alpha_snapshot()
  local ac = input:tree_code_state():tree_code_next_counter("control_scope"); input = input:tree_code_with_result_state(ac)
  local alpha_s = "ctl" .. tostring(ac.value)
  local ar = input:tree_code_state():tree_code_fork_alpha(alpha_s); input = input:tree_code_with_result_state(ar)
  local records, targets = {}, {}
  local function add_record(block, is_entry)
    local br = input:tree_code_new_block("ctl_" .. block.label.name); input = input:tree_code_with_result_state(br)
    local params, binds = {}, {}
    for i = 1, #(block.params or {}) do
      local b = control_binding(self.region_id, block.label, block.params[i], i, is_entry)
      local dk = input:tree_code_state():tree_code_declare_binding_key(b); input = input:tree_code_with_result_state(dk)
      local v = input:tree_code_value_id_for_binding(b)
      local cty = input:tree_code_type(block.params[i].ty)
      params[#params+1] = Code.CodeParam(v, block.params[i].name, cty, origin_binding(b))
      binds[#binds+1] = {binding=b, value=v, ty=block.params[i].ty, cty=cty}
    end
    local rec = {id=br.id, label=block.label, name="ctl."..block.label.name, params=params, binds=binds, body=block.body or {}, entry=is_entry, entry_params=block.params or {}}
    records[#records+1] = rec
    targets[#targets+1] = TreeCode.TreeCodeControlTargetEntry(label_key(block.label), TreeCode.TreeCodeControlTarget(br.id, params))
    return rec
  end
  local entry = add_record(self.entry, true)
  for i = 1, #(self.blocks or {}) do add_record(self.blocks[i], false) end
  local region_alpha = clone_map(input:tree_code_state().alpha.renamed_by_key)
  local exr = input:tree_code_new_block("ctl_stmt_exit"); input = input:tree_code_with_result_state(exr)
  local saved_outer = input:tree_code_save_bindings()
  local entry_args = {}
  input = input:tree_code_with_result_state(input:tree_code_state():tree_code_use_alpha(saved_a, saved_as))
  for i = 1, #(self.entry.params or {}) do
    local ear = self.entry.params[i].init:lower_tree_expr_to_code(input:tree_code_expr_input()); input = input:tree_code_with_result_state(ear)
    entry_args[#entry_args+1] = ear.value
  end
  input = input:tree_code_with_result_state(input:tree_code_state():tree_code_use_alpha(region_alpha, alpha_s))
  input = input:tree_code_with_result_state(input:tree_code_terminate(Code.CodeTermJump(entry.id, entry_args), origin_generated("enter control region")))
  local ctrl_region = TreeCode.TreeCodeStmtControlRegion(exr.id, targets)
  input = input:tree_code_with_result_state(input:tree_code_state():tree_code_enter_control_region(ctrl_region))
  for i = 1, #records do
    local rec = records[i]
    input = input:tree_code_with_result_state(input:tree_code_restore_bindings(saved_outer))
    input = input:tree_code_with_result_state(input:tree_code_state():tree_code_use_alpha(setmetatable({},{__index=region_alpha}), alpha_s.."_b"..tostring(i)))
    input = input:tree_code_with_result_state(input:tree_code_start_block(rec.id, rec.name, rec.params, origin_generated("control block "..rec.label.name)))
    for j = 1, #rec.binds do
      local b = rec.binds[j]
      input = input:tree_code_with_result_state(input:tree_code_state():tree_code_note_binding(b.binding, b.value))
      if input:tree_code_binding_is_addressed(b.binding) or b.cty:tree_code_is_aggregate_type() then
        input = input:tree_code_with_result_state(input:tree_code_bind_local_init(b.binding, b.value, b.ty, false))
      end
    end
    local bi = TreeCode.TreeCodeStmtInput(input:tree_code_func_facts(), input:tree_code_state()); bi = bi:tree_code_lower_stmt_body(rec.body)
    input = input:tree_code_with_result_state(TreeCode.TreeCodeStateResult(bi:tree_code_state()))
    if input:tree_code_state():tree_code_has_current_block() then unsupported(rec.label, "control block can fall through") end
  end
  local exit_result = input:tree_code_state():tree_code_leave_control_region(); input = input:tree_code_with_result_state(exit_result)
  input = input:tree_code_with_result_state(input:tree_code_state():tree_code_use_alpha(saved_a, saved_as))
  input = input:tree_code_with_result_state(input:tree_code_restore_bindings(saved_outer))
  if exit_result.saw_exit then
    input = input:tree_code_with_result_state(input:tree_code_start_block(exr.id, "ctl.stmt.exit", {}, origin_generated("control exit")))
  end
  return TreeCode.TreeCodeStmtResult(input:tree_code_state())
end

----------------------------------------------------------------------
-- Func lowering
----------------------------------------------------------------------
function Tree.FuncLocal:lower_tree_func_parts_to_code()
  return TreeCode.TreeCodeFuncParts(self.name, Code.CodeLinkageLocal, self.params, self.result, self.body)
end
function Tree.FuncExport:lower_tree_func_parts_to_code()
  return TreeCode.TreeCodeFuncParts(self.name, Code.CodeLinkageExport, self.params, self.result, self.body)
end
function Tree.FuncLocalContract:lower_tree_func_parts_to_code()
  return TreeCode.TreeCodeFuncParts(self.name, Code.CodeLinkageLocal, self.params, self.result, self.body)
end
function Tree.FuncExportContract:lower_tree_func_parts_to_code()
  return TreeCode.TreeCodeFuncParts(self.name, Code.CodeLinkageExport, self.params, self.result, self.body)
end

function TreeCode.TreeCodeFuncParts:tree_code_param_types()
  local out = {}
  for i = 1, #(self.params or {}) do out[i] = self.params[i].ty end
  return out
end

function Ty.Param:lower_tree_param_to_code(input, func_name, index)
  local binding = self:tree_code_param_binding(func_name, index)
  local cty = input:tree_code_type(self.ty)
  local value = input:tree_code_value_id_for_binding(binding)
  input = input:tree_code_with_result_state(input:tree_code_state():tree_code_note_binding(binding, value))
  local code_param = Code.CodeParam(value, self.name, cty, origin_binding(binding))
  if input:tree_code_binding_is_addressed(binding) or cty:tree_code_is_aggregate_type() then
    input = input:tree_code_with_result_state(input:tree_code_bind_local_init(binding, value, self.ty, false))
  end
  return TreeCode.TreeCodeParamResult(code_param, cty, input:tree_code_state())
end

function Tree.Func:lower_tree_func_to_code(input)
  local parts = self:lower_tree_func_parts_to_code()
  local residence = collect_address_taken_stmts(parts.body or {}, {addressed={}, mutable={}})
  local start = input:tree_code_func_lowering_start(parts.name, residence)
  local stmt_input = TreeCode.TreeCodeStmtInput(start.facts, start.state)
  local entry = Code.CodeBlockId("block_" .. sanitize(parts.name) .. "_entry")
  stmt_input = stmt_input:tree_code_with_result_state(stmt_input:tree_code_start_block(entry, "entry", {}, origin_generated("entry block")))
  local code_params = {}; local sig_params = {}
  for i = 1, #(parts.params or {}) do
    local pr = parts.params[i]:lower_tree_param_to_code(stmt_input, parts.name, i)
    stmt_input = stmt_input:tree_code_with_result_state(pr)
    code_params[#code_params+1] = pr.param; sig_params[#sig_params+1] = pr.ty
  end
  local result = stmt_input:tree_code_type(parts.result)
  local sig_results = {}
  if result ~= Code.CodeTyVoid then sig_results[#sig_results+1] = result end
  local sig = ensure_code_sig_s(sig_params, sig_results)
  stmt_input = stmt_input:tree_code_lower_stmt_body(parts.body or {})
  if stmt_input:tree_code_state():tree_code_has_current_block() then
    if result == Code.CodeTyVoid then
      stmt_input = stmt_input:tree_code_with_result_state(stmt_input:tree_code_terminate(Code.CodeTermReturn({}), origin_generated("void fallthrough")))
    else
      unsupported(self, "non-void function without return")
    end
  end
  return Code.CodeFunc(Code.CodeFuncId("fn_" .. parts.name), parts.name, parts.linkage, sig, code_params, stmt_input:tree_code_state().emission.locals, entry, stmt_input:tree_code_state().emission.blocks, origin_generated("function " .. parts.name))
end

----------------------------------------------------------------------
-- Item lowering
----------------------------------------------------------------------
function Tree.Item:tree_code_add_const_entries(entries, mod_name) end
function Tree.ItemConst:tree_code_add_const_entries(entries, mod_name) self.c:tree_code_add_const_entries(entries, mod_name) end
function Tree.ConstItem:tree_code_add_const_entries(entries, mod_name) entries[#entries+1] = Bind.ConstEntry(mod_name, self.name, self.ty, self.value) end

function Tree.Item:lower_tree_item_register_to_code(input) end
function Tree.ItemFunc:lower_tree_item_register_to_code(input)
  local parts = self.func:lower_tree_func_parts_to_code()
  local sig = ensure_type_sig_s(parts:tree_code_param_types(), parts.result)
  local key = func_key(input.module_facts.module_name, parts.name)
  input.registrations.funcs[key] = TreeCode.TreeCodeFuncRegistrationEntry(key, TreeCode.TreeCodeFuncRegistration(code_func_id(parts.name), sig))
end
function Tree.ItemExtern:lower_tree_item_register_to_code(input) self.func:tree_code_register_extern(input) end
function Tree.ExternFunc:tree_code_register_extern(input)
  local param_tys = {}
  for j = 1, #(self.params or {}) do param_tys[j] = self.params[j].ty end
  local sig = ensure_type_sig_s(param_tys, self.result)
  local ex = Code.CodeExtern(code_extern_id(self.name), self.name, self.symbol, sig, origin_generated("extern " .. self.name))
  input.registrations.externs[self.name] = TreeCode.TreeCodeExternEntry(self.name, ex)
  input.registrations.extern_order[#input.registrations.extern_order+1] = ex
end

function Tree.Item:lower_tree_item_to_code(input) end
function Tree.ItemFunc:lower_tree_item_to_code(input) input.funcs[#input.funcs+1] = self.func:lower_tree_func_to_code(input) end
function Tree.ItemData:lower_tree_item_to_code(input) input.data[#input.data+1] = Code.CodeData(code_data_id(self.data.id), self.data.id.text, Code.CodeLinkageLocal, self.data.size, self.data.align, {Code.CodeDataBytes(0, self.data.bytes)}, origin_generated("data " .. tostring(self.data.id.text))) end
function Tree.ItemConst:lower_tree_item_to_code(input) self.c:tree_code_lower_const_item(input) end
function Tree.ConstItem:tree_code_lower_const_item(input) input.globals[#input.globals+1] = self:tree_code_lower_global_to_code(input) end
function Tree.ItemStatic:lower_tree_item_to_code(input) self.s:tree_code_lower_static_item(input) end
function Tree.StaticItem:tree_code_lower_static_item(input) input.globals[#input.globals+1] = self:tree_code_lower_global_to_code(input) end
function Tree.ItemExtern:lower_tree_item_to_code(input) end
function Tree.ItemType:lower_tree_item_to_code(input) end
function Tree.ItemImport:lower_tree_item_to_code(input) end
function Tree.ItemRegion:lower_tree_item_to_code(input) unsupported(self, "region item leaked past frontend") end

function TreeCode.TreeCodeInput:tree_code_global_init_for_const(source_ty, value_expr, site)
  local value = value_expr:tree_code_const_eval(
    self:tree_code_module_facts().const_env, Sem.ConstLocalEnv({}))
  local ty = self:tree_code_type(source_ty)
  return value:tree_code_global_init(self, ty, value_expr, site)
end

function Tree.Expr:tree_code_const_eval(const_env, local_env)
  return self:sem_const_eval(Sem.ConstEvalInput(const_env, local_env))
end
function Tree.Expr:sem_const_eval(input) return Sem.ConstNotFoldable("not foldable") end
function Sem.ConstValue:tree_code_global_init(input, ty, value_expr, site) unsupported(value_expr, "non-scalar constant initializer") end
function Sem.ConstInt:tree_code_global_init(input, ty, value_expr, site) return {Code.CodeDataScalar(0, ty, Core.LitInt(self.raw))} end
function Sem.ConstFloat:tree_code_global_init(input, ty, value_expr, site) return {Code.CodeDataScalar(0, ty, Core.LitFloat(self.raw))} end
function Sem.ConstBool:tree_code_global_init(input, ty, value_expr, site) return {Code.CodeDataScalar(0, ty, Core.LitBool(self.value))} end

function Tree.ConstItem:tree_code_lower_global_to_code(input)
  local start = input:tree_code_func_lowering_start(input.module_facts.module_name)
  local ei = TreeCode.TreeCodeExprInput(start.facts, start.state)
  local inits = ei:tree_code_global_init_for_const(self.ty, self.value, self.name)
  return Code.CodeGlobal(code_global_id(input.module_facts.module_name, self.name), self.name, ei:tree_code_type(self.ty), Code.CodeLinkageLocal, ei:tree_code_size_of(self.ty), ei:tree_code_align_of(self.ty), inits, origin_generated("global " .. tostring(self.name)))
end

function Tree.StaticItem:tree_code_lower_global_to_code(input)
  local start = input:tree_code_func_lowering_start(input.module_facts.module_name)
  local ei = TreeCode.TreeCodeExprInput(start.facts, start.state)
  local inits = ei:tree_code_global_init_for_const(self.ty, self.value, self.name)
  return Code.CodeGlobal(code_global_id(input:tree_code_module_facts().module_name, self.name), self.name, ei:tree_code_type(self.ty), Code.CodeLinkageLocal, ei:tree_code_size_of(self.ty), ei:tree_code_align_of(self.ty), inits, origin_generated("global " .. tostring(self.name)))
end

function TreeCode.TreeCodeModuleParts:tree_code_func_lowering_start(func_name, residence)
  residence = residence or {}
  return TreeCode.TreeCodeFuncLoweringStart(
    TreeCode.TreeCodeFuncFacts(self.module_facts, self.sigs, self.registrations, self.emission, func_name),
    TreeCode.TreeCodeFuncState(
      TreeCode.TreeCodeBindingState({}, {}),
      TreeCode.TreeCodeResidenceFacts(residence.addressed or {}, residence.mutable or {}),
      TreeCode.TreeCodeEmissionState({}, {}, {}),
      TreeCode.TreeCodeCounterState({}),
      TreeCode.TreeCodeAlphaState({}, {}, 0),
      TreeCode.TreeCodeControlState({}, {})
    )
  )
end

function TreeCode.TreeCodeItemLowerInput:tree_code_func_lowering_start(func_name, residence)
  return TreeCode.TreeCodeModuleParts(self.module_facts, self.sigs, self.registrations, self.emission):tree_code_func_lowering_start(func_name, residence)
end

----------------------------------------------------------------------
-- Module lowering
----------------------------------------------------------------------
function TreeCode.TreeCodeModuleSigState:tree_lower_sig_entry(sig)
  return TreeCode.TreeCodeSigEntry(sig.id.text, sig)
end
function Tree.Module:tree_code_layout_env(target)
  local envs = self:tree_module_env(target)
  local layouts = (#envs > 0 and envs[1].layouts) or {}
  return Sem.LayoutEnv(layouts)
end

function Tree.Module:tree_code_module_parts(opts)
  local layout_env = opts.layout_env
  if layout_env == nil then layout_env = self:tree_code_layout_env(opts.target) end
  local mod_name = self:tree_code_module_name()
  local const_entries = {}
  for i = 1, #(self.items or {}) do self.items[i]:tree_code_add_const_entries(const_entries, mod_name) end
  local module_facts = TreeCode.TreeCodeModuleFacts(mod_name, layout_env, tree_code_target(opts.target), Bind.ConstEnv(const_entries), self:tree_code_variant_defs(mod_name))
  local sigs = TreeCode.TreeCodeModuleSigState(mod_name, {}, {})
  module_sig_state = sigs
  local registrations = TreeCode.TreeCodeModuleRegistrationState({}, {}, {})
  local emission = TreeCode.TreeCodeModuleEmissionState({}, {})
  local reg_input = TreeCode.TreeCodeItemRegisterInput(module_facts, sigs, registrations)
  for i = 1, #(self.items or {}) do self.items[i]:lower_tree_item_register_to_code(reg_input) end
  sigs = module_sig_state
  return TreeCode.TreeCodeModuleParts(module_facts, sigs, registrations, emission)
end

function Tree.Module:lower_tree_module_to_code(opts)
  opts = opts or {}
  local mod_name = self:tree_code_module_name()
  local parts = self:tree_code_module_parts(opts)
  local funcs, data, globals = {}, {}, {}
  local input = TreeCode.TreeCodeItemLowerInput(parts.module_facts, parts.sigs, parts.registrations, parts.emission, mod_name, funcs, data, globals)
  for i = 1, #(self.items or {}) do self.items[i]:lower_tree_item_to_code(input) end
  for i = 1, #parts.emission.generated_data do data[#data+1] = parts.emission.generated_data[i] end
  return Code.CodeModule(Code.CodeModuleId("module_" .. sanitize(opts.module_id or self:tree_code_module_name())), module_sig_state.code_sig_order, {}, data, globals, parts.registrations.extern_order, input.funcs, origin_generated("tree_lower module"))
end

function Tree.Module:lower_tree_module_contracts_to_code(opts)
  opts = opts or {}
  local parts = self:tree_code_module_parts(opts)
  local mod_id = Code.CodeModuleId("module_" .. sanitize(opts.module_id or self:tree_code_module_name()))
  local facts = {}
  local input = TreeCode.TreeCodeItemContractsInput(parts.module_facts, parts.sigs, parts.registrations, parts.emission, facts)
  for i = 1, #(self.items or {}) do self.items[i]:lower_tree_item_contracts_to_code(input) end
  return Code.CodeContractFactSet(mod_id, input.contract_facts)
end

function Tree.Item:lower_tree_item_contracts_to_code(input) end
function Tree.ItemFunc:lower_tree_item_contracts_to_code(input)
  local parts = self.func:lower_tree_func_parts_to_code()
  local func_id = code_func_id(parts.name)
  local tree_facts = self.func:tree_code_contract_facts()
  local ci = TreeCode.TreeCodeContractInput(input.module_facts, input.sigs, parts.name, func_id)
  for j = 1, #(tree_facts.facts or {}) do
    input.contract_facts[#input.contract_facts+1] = tree_facts.facts[j]:lower_tree_contract_fact_to_code(ci).fact
  end
end

function Tree.Func:tree_code_contract_facts()
  return { facts = self:tree_check_contract_facts(self.contracts or {}) }
end
function Tree.Module:lower_tree_module_with_contracts_to_code(opts)
  return self:lower_tree_module_to_code(opts), self:lower_tree_module_contracts_to_code(opts)
end

----------------------------------------------------------------------
-- Contract lowering
----------------------------------------------------------------------
function TreeCode.TreeCodeContractInput:tree_code_value_for_binding(binding)
  return Code.CodeValueId("v_" .. sanitize(self.func_name) .. "_" .. sanitize(binding:tree_code_binding_key()))
end

function TreeCode.TreeCodeContractInput:tree_code_value_for_expr(expr) return expr:tree_code_contract_value(self) end
function TreeCode.TreeCodeContractInput:tree_code_contract_expr_for_expr(expr) return expr:tree_code_contract_expr(self) end

function Tree.Expr:tree_code_contract_value(input) return nil end
function Tree.ExprRef:tree_code_contract_value(input) return self.ref:tree_code_contract_value(input, self) end
function Bind.ValueRef:tree_code_contract_value(input, expr) return nil end
function Bind.ValueRefBinding:tree_code_contract_value(input, expr) return input:tree_code_value_for_binding(self.binding) end

function Tree.Expr:tree_code_contract_expr(input) local v = self:tree_code_contract_value(input); if v then return Code.CodeContractValueRef(v) end; return nil end
function Tree.ExprRef:tree_code_contract_expr(input) local v = self:tree_code_contract_value(input); if v then return Code.CodeContractValueRef(v) end; return nil end
function Tree.ExprField:tree_code_contract_expr(input) local p = self:tree_code_contract_place(input); if p then return Code.CodeContractPlaceLoad(p) end; return nil end

function Tree.Expr:tree_code_contract_place(input) return nil end
function Tree.ExprRef:tree_code_contract_place(input) return self.ref:tree_code_contract_place(input, self) end
function Bind.ValueRef:tree_code_contract_place(input, expr) return nil end
function Bind.ValueRefBinding:tree_code_contract_place(input, expr)
  local role = self.binding.role
  if role and role.tree_code_global_place then
    local place = role:tree_code_global_place(input, self.binding)
    if place then return place end
  end
  return Code.CodePlaceDeref(input:tree_code_value_for_binding(self.binding), input:tree_code_type(self.binding.ty), input:tree_code_align_of(self.binding.ty))
end
function Tree.ExprField:tree_code_contract_place(input)
  self.field:tree_code_require_lowered_field(input)
  local base_ty = self.base.h and self.base.h:tree_code_expr_type()
  if base_ty then base_ty = base_ty:tree_code_source_access_base() end
  local base_place = base_ty and base_ty:tree_code_contract_field_base_place(input, self.base) or self.base:tree_code_contract_place(input)
  if base_place == nil then return nil end
  local fl = input:tree_code_layout_of(self.field.ty)
  return Code.CodePlaceField(base_place, self.field, input:tree_code_type(self.field.ty), self.field.offset, fl and fl.size, fl and fl.align)
end
function Ty.Type:tree_code_contract_field_base_place(input, base) return base:tree_code_contract_place(input) end
function Ty.TPtr:tree_code_contract_field_base_place(input, base)
  local v = base:tree_code_contract_value(input)
  if v == nil then return nil end
  return Code.CodePlaceDeref(v, input:tree_code_type(self.elem), input:tree_code_align_of(self.elem))
end

function TreeCode.TreeCodeContractInput:tree_code_contract_reject(reason)
  return Code.CodeFuncContractFact(self.func_id, Code.CodeContractRejected(tostring(reason or "unsupported")), origin_generated("contract rejection"))
end

function Tree.ContractFactBounds:lower_tree_contract_fact_to_code(input)
  return TreeCode.TreeCodeContractResult(Code.CodeFuncContractFact(input.func_id, Code.CodeContractBounds(input:tree_code_value_for_binding(self.base), input:tree_code_value_for_binding(self.len)), origin_binding(self.base)))
end
function Tree.ContractFactExprBounds:lower_tree_contract_fact_to_code(input)
  local base = input:tree_code_contract_expr_for_expr(self.base); local len = input:tree_code_contract_expr_for_expr(self.len)
  if base == nil or len == nil then return TreeCode.TreeCodeContractResult(input:tree_code_contract_reject("expr bounds")) end
  return TreeCode.TreeCodeContractResult(Code.CodeFuncContractFact(input.func_id, Code.CodeContractProjectionBounds(base, len), origin_generated("projection bounds")))
end
function Tree.ContractFactWindowBounds:lower_tree_contract_fact_to_code(input)
  local base = input:tree_code_value_for_binding(self.base)
  local bl = input:tree_code_value_for_expr(self.base_len); local st = input:tree_code_value_for_expr(self.start); local ln = input:tree_code_value_for_expr(self.len)
  if bl == nil or st == nil or ln == nil then return TreeCode.TreeCodeContractResult(input:tree_code_contract_reject("window bounds")) end
  return TreeCode.TreeCodeContractResult(Code.CodeFuncContractFact(input.func_id, Code.CodeContractWindowBounds(base, bl, st, ln), origin_binding(self.base)))
end
function Tree.ContractFactDisjoint:lower_tree_contract_fact_to_code(input)
  return TreeCode.TreeCodeContractResult(Code.CodeFuncContractFact(input.func_id, Code.CodeContractDisjoint(input:tree_code_value_for_binding(self.a), input:tree_code_value_for_binding(self.b)), origin_binding(self.a)))
end
function Tree.ContractFactSameLen:lower_tree_contract_fact_to_code(input)
  return TreeCode.TreeCodeContractResult(Code.CodeFuncContractFact(input.func_id, Code.CodeContractSameLen(input:tree_code_value_for_binding(self.a), input:tree_code_value_for_binding(self.b)), origin_binding(self.a)))
end
function Tree.ContractFactSoAComponent:lower_tree_contract_fact_to_code(input)
  return TreeCode.TreeCodeContractResult(Code.CodeFuncContractFact(input.func_id, Code.CodeContractSoAComponent(input:tree_code_value_for_binding(self.base), input:tree_code_type(self.record_ty), self.field_name, self.component_index), origin_binding(self.base)))
end
function Tree.ContractFactNoAlias:lower_tree_contract_fact_to_code(input)
  return TreeCode.TreeCodeContractResult(Code.CodeFuncContractFact(input.func_id, Code.CodeContractNoAlias(input:tree_code_value_for_binding(self.base)), origin_binding(self.base)))
end
function Tree.ContractFactReadonly:lower_tree_contract_fact_to_code(input)
  return TreeCode.TreeCodeContractResult(Code.CodeFuncContractFact(input.func_id, Code.CodeContractReadonly(input:tree_code_value_for_binding(self.base)), origin_binding(self.base)))
end
function Tree.ContractFactWriteonly:lower_tree_contract_fact_to_code(input)
  return TreeCode.TreeCodeContractResult(Code.CodeFuncContractFact(input.func_id, Code.CodeContractWriteonly(input:tree_code_value_for_binding(self.base)), origin_binding(self.base)))
end
function Tree.ContractFactExprReadonly:lower_tree_contract_fact_to_code(input)
  local base = input:tree_code_contract_expr_for_expr(self.base)
  if base == nil then return TreeCode.TreeCodeContractResult(input:tree_code_contract_reject("expr readonly")) end
  return TreeCode.TreeCodeContractResult(Code.CodeFuncContractFact(input.func_id, Code.CodeContractProjectionReadonly(base), origin_generated("projection readonly")))
end
function Tree.ContractFactExprWriteonly:lower_tree_contract_fact_to_code(input)
  local base = input:tree_code_contract_expr_for_expr(self.base)
  if base == nil then return TreeCode.TreeCodeContractResult(input:tree_code_contract_reject("expr writeonly")) end
  return TreeCode.TreeCodeContractResult(Code.CodeFuncContractFact(input.func_id, Code.CodeContractProjectionWriteonly(base), origin_generated("projection writeonly")))
end
function Tree.ContractFactInvalidate:lower_tree_contract_fact_to_code(input)
  return TreeCode.TreeCodeContractResult(Code.CodeFuncContractFact(input.func_id, Code.CodeContractInvalidate(input:tree_code_value_for_binding(self.base)), origin_binding(self.base)))
end
function Tree.ContractFactPreserve:lower_tree_contract_fact_to_code(input)
  return TreeCode.TreeCodeContractResult(Code.CodeFuncContractFact(input.func_id, Code.CodeContractPreserve(input:tree_code_value_for_binding(self.base)), origin_binding(self.base)))
end
function Tree.ContractFactRejected:lower_tree_contract_fact_to_code(input)
  return TreeCode.TreeCodeContractResult(input:tree_code_contract_reject("tree contract rejected: " .. class_name(self.issue)))
end
-- Keep schema_v2 on the canonical leaf-owned layout implementation.
Tree.Module.lower_to_code = Tree.Module.lower_tree_module_to_code
require("lalin.layout_resolve")(require("lalin.schema_v2"))
