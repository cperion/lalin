-- Canonical schema-v2 region facts and immutable expansion.
-- Region behavior is deliberately attached to concrete ASDL leaves.

require("lalin.schema_v2")
local Tr = require("lalin.schema_v2.tree")
local C = require("lalin.schema_v2.core")
local B = require("lalin.schema_v2.bind")
local Ty = require("lalin.schema_v2.type")
local Check = require("lalin.schema_v2.check")
local Sem = require("lalin.schema_v2.sem")

local function append(out, values)
  for i = 1, #(values or {}) do out[#out + 1] = values[i] end
end

local function empty_definitions()
  return Tr.RegionDefinitionProjection({})
end
local function empty_protocols()
  return Tr.RegionProtocolProjection({})
end
local function empty_seals()
  return Tr.RegionSealProjection({})
end
local function empty_bundles()
  return Tr.RegionBundleProjection({})
end
local function empty_facts()
  return Tr.RegionFactProjection(empty_definitions(), empty_protocols(), empty_seals(), empty_bundles())
end

local function split_name(name)
  local parts = {}
  for part in tostring(name or ""):gmatch("[^%.]+") do parts[#parts + 1] = C.Name(part) end
  if #parts == 0 then parts[1] = C.Name("region") end
  return C.Path(parts)
end

local function target_for_region(region)
  return Tr.RegionInvokeTarget(split_name(region.name))
end

local function prefixed_label(invoke_id, label)
  return Tr.BlockLabel(tostring(invoke_id or "region") .. "." .. tostring(label.name))
end

local function name_of_ref(ref)
  return ref:region_ref_name()
end

local function expr_type(expr)
  if expr == nil or expr.h == nil then return Ty.TScalar(C.ScalarVoid) end
  return expr.h:region_expr_type()
end

local function binding_for_param(region_id, label, param, index, entry)
  local role = entry
    and B.BindingRoleEntryBlockParam(region_id, label.name, index)
    or B.BindingRoleBlockParam(region_id, label.name, index)
  return B.Binding(C.Id("region:param:" .. tostring(region_id) .. ":" .. tostring(label.name) .. ":" .. tostring(param.name)),
    param.name, param.ty, role)
end

local function add_param_scope(state, region_id, block, entry)
  local scope = state.scope
  for i = 1, #(block.params or {}) do
    local p = block.params[i]
    local binding = binding_for_param(region_id, block.label, p, i, entry)
    scope = scope:typecheck_tree_add_value(p.name, p.ty, binding)
  end
  return Check.TypeStmtInput(scope, state.return_ty, state.yield)
end

-- -------------------------------------------------------------------------
-- Identity and projection leaves
-- -------------------------------------------------------------------------
function Tr.ExprHeader:region_expr_type() return Ty.TScalar(C.ScalarVoid) end
function Tr.ExprSurface:region_expr_type() return Ty.TScalar(C.ScalarVoid) end
function Tr.ExprTyped:region_expr_type() return self.ty end

function B.ValueRef:region_ref_name() return nil end
function B.ValueRefName:region_ref_name() return self.name end
function B.ValueRefPath:region_ref_name() return nil end
function B.ValueRefBinding:region_ref_name() return self.binding.name end

function Tr.RegionInvokeTarget:region_target_matches(other)
  local a, b = self.path.parts or {}, other.path.parts or {}
  if #a ~= #b then return false end
  for i = 1, #a do if a[i].text ~= b[i].text then return false end end
  return true
end

function Tr.RegionCont:region_cont_matches_name(name) return self.name == name end
function Tr.RegionProtocolKey:region_protocol_key_matches(other) return self.text == other.text end

function Tr.RegionDefinitionProjection:region_definition_lookup(target)
  for i = 1, #(self.entries or {}) do
    local entry = self.entries[i]
    if entry.target:region_target_matches(target) then return Tr.RegionDefinitionFound(entry) end
  end
  return Tr.RegionDefinitionMissing(target)
end
function Tr.RegionProtocolProjection:region_protocol_lookup(key)
  for i = 1, #(self.entries or {}) do
    local entry = self.entries[i]
    if entry.key:region_protocol_key_matches(key) then return Tr.RegionProtocolFound(entry) end
  end
  return Tr.RegionProtocolMissing(key)
end
function Tr.RegionSealProjection:region_seal_lookup(target)
  for i = 1, #(self.entries or {}) do
    local entry = self.entries[i]
    if entry.target:region_target_matches(target) then return Tr.RegionSealFound(entry) end
  end
  return Tr.RegionSealMissing(target)
end
function Tr.RegionBundleProjection:region_bundle_lookup(target)
  for i = 1, #(self.entries or {}) do
    local entry = self.entries[i]
    if entry.target:region_target_matches(target) then return Tr.RegionBundleFound(entry) end
  end
  return Tr.RegionBundleMissing(target)
end
function Tr.RegionWireProjection:region_wire_lookup(name)
  for i = 1, #(self.entries or {}) do
    local entry = self.entries[i]
    if entry.name == name then return Tr.RegionWireFound(entry) end
  end
  return Tr.RegionWireMissing(name)
end
function Tr.RegionSeal:region_payload_lookup(cont) return self.protocol:region_payload_lookup(cont) end

function Tr.Item:region_definition_projection() return empty_definitions() end
function Tr.Item:region_protocol_projection() return empty_protocols() end
function Tr.Item:region_seal_projection() return empty_seals() end
function Tr.ItemRegion:region_definition_projection()
  local target = target_for_region(self.region)
  local definition = Tr.TypeRegionDef(target, self.region)
  return Tr.RegionDefinitionProjection({ Tr.RegionDefinitionEntry(target, definition) })
end
function Tr.ItemRegion:region_protocol_projection()
  local payloads = {}
  for i = 1, #(self.region.conts or {}) do
    local cont = self.region.conts[i]
    payloads[i] = Tr.RegionSealPayload(cont, Tr.RegionResultTypeId(tostring(self.region.name) .. "." .. tostring(cont.name)))
  end
  local protocol = Tr.RegionProtocol(Tr.RegionProtocolKey(tostring(self.region.name)), Tr.RegionResultTypeId(tostring(self.region.name) .. ".Result"), payloads)
  return Tr.RegionProtocolProjection({ Tr.RegionProtocolEntry(protocol.key, protocol) })
end
function Tr.ItemRegion:region_seal_projection()
  local target = target_for_region(self.region)
  local payloads = {}
  for i = 1, #(self.region.conts or {}) do
    local cont = self.region.conts[i]
    payloads[i] = Tr.RegionSealPayload(cont, Tr.RegionResultTypeId(tostring(self.region.name) .. "." .. tostring(cont.name)))
  end
  local protocol = Tr.RegionProtocol(Tr.RegionProtocolKey(tostring(self.region.name)), Tr.RegionResultTypeId(tostring(self.region.name) .. ".Result"), payloads)
  local seal = Tr.RegionSeal(target, self.region, Tr.RegionFunctionId(tostring(self.region.name)), protocol)
  return Tr.RegionSealProjection({ Tr.RegionSealEntry(target, seal) })
end

function Tr.Module:region_fact_projection()
  local definitions, protocols, seals = {}, {}, {}
  for i = 1, #(self.items or {}) do
    local item = self.items[i]
    append(definitions, item:region_definition_projection().entries)
    append(protocols, item:region_protocol_projection().entries)
    append(seals, item:region_seal_projection().entries)
  end
  return Tr.RegionFactProjection(
    Tr.RegionDefinitionProjection(definitions), Tr.RegionProtocolProjection(protocols),
    Tr.RegionSealProjection(seals), empty_bundles())
end
function Tr.RegionEntryBlockNode:region_block() return self.entry end
function Tr.RegionControlBlockNode:region_block() return self.block end
function Tr.RegionModuleExpanded:region_module() return self.module end
function Tr.RegionModuleRejected:region_module() return self.module end
function Tr.RegionModuleExpanded:region_issues() return self.issues end
function Tr.RegionModuleRejected:region_issues() return self.issues end

-- -------------------------------------------------------------------------
-- Typed rejection explanations.  The reject leaf owns the explanation.
-- -------------------------------------------------------------------------
function Tr.RegionInvokeMissingTarget:region_invoke_explanation()
  return Check.TypeIssueExplanation("E0408", "region", "region target is not defined", { "define the region before invoking it" }, {})
end
function Tr.RegionInvokeArgCount:region_invoke_explanation()
  return Check.TypeIssueExplanation("E0408", "region", "region invocation has the wrong argument count", {}, {})
end
function Tr.RegionInvokeMissingWire:region_invoke_explanation()
  return Check.TypeIssueExplanation("E0408", "region", "region invocation is missing a continuation wire", {}, {})
end
function Tr.RegionInvokeExtraWire:region_invoke_explanation()
  return Check.TypeIssueExplanation("E0408", "region", "region invocation names an unknown continuation", {}, {})
end
function Tr.RegionInvokeDuplicateWire:region_invoke_explanation()
  return Check.TypeIssueExplanation("E0203", "region", "region invocation wires a continuation more than once", {}, {})
end
function Tr.RegionInvokeCallFrameUnsupported:region_invoke_explanation()
  return Check.TypeIssueExplanation("E0408", "region", "region call frame is not available", { self.reason }, {})
end
function Check.TypeIssueRegionInvoke:typecheck_tree_explanation()
  return self.reject:region_invoke_explanation()
end

-- -------------------------------------------------------------------------
-- Wire leaves own continuation retargeting.
-- -------------------------------------------------------------------------
local function wire_args(target_args, source_args)
  if #(target_args or {}) > 0 then return target_args end
  return source_args or {}
end
function Tr.RegionWireTarget:region_retarget_jump(cont, args) return Tr.StmtTrap(Tr.StmtSurface) end
function Tr.RegionWireBlock:region_retarget_jump(cont, args)
  return Tr.StmtJump(Tr.StmtSurface, self.label, wire_args(self.args, args))
end
function Tr.RegionWireCont:region_retarget_jump(cont, args)
  return Tr.StmtJumpCont(Tr.StmtSurface, self.cont, wire_args(self.args, args))
end
function Tr.RegionWireFound:region_retarget_jump(cont, args)
  return self.entry.wire.target:region_retarget_jump(cont, args)
end
function Tr.RegionWireMissing:region_retarget_jump(cont, args) return Tr.StmtTrap(Tr.StmtSurface) end

local function wire_for_cont(wires, cont)
  local entries = {}
  for i = 1, #(wires or {}) do entries[i] = Tr.RegionWireEntry(wires[i].name, wires[i]) end
  local projection = Tr.RegionWireProjection(entries)
  return projection:region_wire_lookup(cont.name)
end

local function capture_projection_for_args(args, cont, prefix)
  local entries = {}
  for i = 1, #(args or {}) do
    local arg = args[i]
    local ref_name = arg.value.ref and name_of_ref(arg.value.ref) or nil
    local is_cont_param = false
    for j = 1, #(cont and cont.params or {}) do if cont.params[j].name == ref_name then is_cont_param = true end end
    if not is_cont_param then
      entries[#entries + 1] = Tr.RegionCallCaptureEntry(
        "__region_capture_" .. tostring(prefix) .. "_" .. tostring(i), expr_type(arg.value), arg.value)
    end
  end
  return Tr.RegionCallCaptureProjection(entries)
end
function Tr.RegionWireTarget:region_capture_projection(cont) return Tr.RegionCallCaptureProjection({}) end
function Tr.RegionWireBlock:region_capture_projection(cont) return capture_projection_for_args(self.args, cont, self.label.name) end
function Tr.RegionWireCont:region_capture_projection(cont) return Tr.RegionCallCaptureProjection({}) end
function Tr.RegionContWire:region_capture_projection(cont) return self.target:region_capture_projection(cont) end
local function collect_captures(wiring, conts)
  local entries = {}
  for i = 1, #(wiring or {}) do
    local wire = wiring[i]
    local cont = conts[i]
    for j = 1, #conts do if conts[j]:region_cont_matches_name(wire.name) then cont = conts[j] end end
    append(entries, wire:region_capture_projection(cont).entries)
  end
  return Tr.RegionCallCaptureProjection(entries)
end

local function clone_stmt(stmt, invoke_id, wires, conts)
  return stmt:region_clone_for_invoke(invoke_id, wires, conts)
end

function Tr.Stmt:region_clone_for_invoke(invoke_id, wires, conts) return self end
function Tr.StmtJumpCont:region_clone_for_invoke(invoke_id, wires, conts)
  local found = wire_for_cont(wires, self.cont)
  return found:region_retarget_jump(self.cont, self.args)
end
function Tr.StmtIf:region_clone_for_invoke(invoke_id, wires, conts)
  local a, b = {}, {}
  for i = 1, #(self.then_body or {}) do a[i] = clone_stmt(self.then_body[i], invoke_id, wires, conts) end
  for i = 1, #(self.else_body or {}) do b[i] = clone_stmt(self.else_body[i], invoke_id, wires, conts) end
  return Tr.StmtIf(self.h, self.cond, a, b)
end
function Tr.StmtSwitch:region_clone_for_invoke(invoke_id, wires, conts)
  local arms, variants, default_body = {}, {}, {}
  for i = 1, #(self.arms or {}) do
    local body = {}; for j = 1, #(self.arms[i].body or {}) do body[j] = clone_stmt(self.arms[i].body[j], invoke_id, wires, conts) end
    arms[i] = Tr.SwitchStmtArm(self.arms[i].key, body)
  end
  for i = 1, #(self.variant_arms or {}) do
    local body = {}; for j = 1, #(self.variant_arms[i].body or {}) do body[j] = clone_stmt(self.variant_arms[i].body[j], invoke_id, wires, conts) end
    variants[i] = Tr.SwitchVariantStmtArm(self.variant_arms[i].variant_name, self.variant_arms[i].binds, body)
  end
  for i = 1, #(self.default_body or {}) do default_body[i] = clone_stmt(self.default_body[i], invoke_id, wires, conts) end
  return Tr.StmtSwitch(self.h, self.value, arms, variants, default_body)
end
function Tr.StmtControl:region_clone_for_invoke(invoke_id, wires, conts) return self end

-- -------------------------------------------------------------------------
-- Immutable statement/body/block expansion.
-- -------------------------------------------------------------------------
function Tr.Stmt:region_expand_stmt(input)
  return Tr.RegionStmtExpansionResult(input.state, { self }, {}, {})
end
function Tr.StmtLet:region_expand_stmt(input)
  local scope = input.state.scope:typecheck_tree_add_value(self.binding.name, self.binding.ty, self.binding)
  return Tr.RegionStmtExpansionResult(Check.TypeStmtInput(scope, input.state.return_ty, input.state.yield), { self }, {}, {})
end
function Tr.StmtVar:region_expand_stmt(input)
  local scope = input.state.scope:typecheck_tree_add_value(self.binding.name, self.binding.ty, self.binding)
  return Tr.RegionStmtExpansionResult(Check.TypeStmtInput(scope, input.state.return_ty, input.state.yield), { self }, {}, {})
end
function Tr.StmtIf:region_expand_stmt(input)
  local a = input:region_expand_body(self.then_body)
  local b = input:region_expand_body(self.else_body)
  return Tr.RegionStmtExpansionResult(input.state, { Tr.StmtIf(self.h, self.cond, a.body.stmts, b.body.stmts) },
    (function() local x = {}; append(x, a.blocks); append(x, b.blocks); return x end)(),
    (function() local x = {}; append(x, a.issues); append(x, b.issues); return x end)())
end
function Tr.StmtSwitch:region_expand_stmt(input)
  local arms, variants, blocks, issues = {}, {}, {}, {}
  for i = 1, #(self.arms or {}) do
    local r = input:region_expand_body(self.arms[i].body)
    arms[i] = Tr.SwitchStmtArm(self.arms[i].key, r.body.stmts); append(blocks, r.blocks); append(issues, r.issues)
  end
  for i = 1, #(self.variant_arms or {}) do
    local r = input:region_expand_body(self.variant_arms[i].body)
    variants[i] = Tr.SwitchVariantStmtArm(self.variant_arms[i].variant_name, self.variant_arms[i].binds, r.body.stmts)
    append(blocks, r.blocks); append(issues, r.issues)
  end
  local d = input:region_expand_body(self.default_body)
  append(blocks, d.blocks); append(issues, d.issues)
  return Tr.RegionStmtExpansionResult(input.state, { Tr.StmtSwitch(self.h, self.value, arms, variants, d.body.stmts) }, blocks, issues)
end

function Tr.RegionStmtExpansionInput:region_expand_body(body)
  return Tr.RegionBodyExpansionInput(self.state, self.facts, self.expansion):region_expand_body(body)
end
function Tr.RegionBodyExpansionInput:region_expand_body(body)
  local state, stmts, blocks, issues = self.state, {}, {}, {}
  for i = 1, #(body or {}) do
    local r = body[i]:region_expand_stmt(Tr.RegionStmtExpansionInput(state, self.facts, self.expansion))
    state = r.next_state
    append(stmts, r.stmts); append(blocks, r.blocks); append(issues, r.issues)
  end
  return Tr.RegionBodyExpansionResult(state, Tr.RegionStmtBody(stmts), blocks, issues)
end

function Tr.EntryControlBlock:region_expand_block(input)
  local state = add_param_scope(input.state, input.expansion.text, self, true)
  local body = Tr.RegionBodyExpansionInput(state, input.facts, input.expansion):region_expand_body(self.body)
  return Tr.RegionBlockExpansionResult(Tr.RegionEntryBlockNode(Tr.EntryControlBlock(self.label, self.params, body.body.stmts)), body.blocks, body.issues)
end
function Tr.ControlBlock:region_expand_block(input)
  local state = add_param_scope(input.state, input.expansion.text, self, false)
  local body = Tr.RegionBodyExpansionInput(state, input.facts, input.expansion):region_expand_body(self.body)
  return Tr.RegionBlockExpansionResult(Tr.RegionControlBlockNode(Tr.ControlBlock(self.label, self.params, body.body.stmts)), body.blocks, body.issues)
end

function Tr.ControlStmtRegion:region_expand_control(input)
  local entry = self.entry:region_expand_block(Tr.RegionBlockExpansionInput(input.state, input.facts, input.expansion))
  local blocks, issues = {}, {}
  append(blocks, entry.blocks); append(issues, entry.issues)
  for i = 1, #(self.blocks or {}) do
    local r = self.blocks[i]:region_expand_block(Tr.RegionBlockExpansionInput(input.state, input.facts, input.expansion))
    blocks[#blocks + 1] = r.node:region_block(); append(blocks, r.blocks); append(issues, r.issues)
  end
  return Tr.RegionStmtExpansionResult(input.state,
    { Tr.StmtControl(Tr.StmtFlow(Sem.FlowFallsThrough), Tr.ControlStmtRegion(
      self.region_id, entry.node:region_block(), blocks)) }, {}, issues)
end
function Tr.ControlExprRegion:region_expand_control(input)
  local entry = self.entry:region_expand_block(Tr.RegionBlockExpansionInput(input.state, input.facts, input.expansion))
  local blocks, issues = {}, {}
  append(blocks, entry.blocks); append(issues, entry.issues)
  for i = 1, #(self.blocks or {}) do
    local r = self.blocks[i]:region_expand_block(Tr.RegionBlockExpansionInput(input.state, input.facts, input.expansion))
    blocks[#blocks + 1] = r.node:region_block(); append(blocks, r.blocks); append(issues, r.issues)
  end
  return Tr.RegionStmtExpansionResult(input.state,
    { Tr.StmtControl(Tr.StmtFlow(Sem.FlowFallsThrough), Tr.ControlStmtRegion(
      self.region_id, entry.node:region_block(), blocks)) }, {}, issues)
end
function Tr.StmtControl:region_expand_stmt(input)
  return self.region:region_expand_control(input)
end


local function reject(reject_leaf) return Tr.RegionInvokeRejected(reject_leaf) end
local function expand_definition(stmt, input, definition)
  local region = definition.region
  local wires = stmt.wiring or {}
  local captures = collect_captures(wires, region.conts or {})
  local entry_label = prefixed_label(stmt.invoke_id, region.entry.label)
  local entry_params, entry_args = {}, {}
  for i = 1, #(region.params or {}) do
    local p = region.params[i]
    entry_params[#entry_params + 1] = Tr.BlockParam(p.name, p.ty)
    entry_args[#entry_args + 1] = Tr.JumpArg(p.name, stmt.args[i])
  end
  for i = 1, #(region.entry.params or {}) do
    local p = region.entry.params[i]
    entry_params[#entry_params + 1] = Tr.BlockParam(p.name, p.ty)
    entry_args[#entry_args + 1] = Tr.JumpArg(p.name, p.init)
  end
  local blocks, issues = {}, {}
  local raw_entry = Tr.ControlBlock(entry_label, entry_params,
    (function() local b = {}; for i = 1, #(region.entry.body or {}) do b[i] = clone_stmt(region.entry.body[i], stmt.invoke_id, wires, region.conts) end return b end)())
  local entry_body = Tr.RegionBodyExpansionInput(input.state, input.facts, input.expansion):region_expand_body(raw_entry.body)
  blocks[#blocks + 1] = Tr.ControlBlock(raw_entry.label, raw_entry.params, entry_body.body.stmts)
  append(blocks, entry_body.blocks); append(issues, entry_body.issues)
  for i = 1, #(region.blocks or {}) do
    local source = region.blocks[i]
    local body = {}
    for j = 1, #(source.body or {}) do body[j] = clone_stmt(source.body[j], stmt.invoke_id, wires, region.conts) end
    local raw = Tr.ControlBlock(prefixed_label(stmt.invoke_id, source.label), source.params, body)
    local expanded = Tr.RegionBodyExpansionInput(input.state, input.facts, input.expansion):region_expand_body(raw.body)
    blocks[#blocks + 1] = Tr.ControlBlock(raw.label, raw.params, expanded.body.stmts)
    append(blocks, expanded.blocks); append(issues, expanded.issues)
  end
  local splice = Tr.RegionInvokeSplice(Tr.StmtJump(stmt.h, entry_label, entry_args), blocks, captures, input.state)
  return Tr.RegionInvokeExpanded(splice)
end
function Tr.RegionDefinitionFound:region_expand_invoke(stmt, input)
  local region = self.entry.definition.region
  if #(region.params or {}) ~= #(stmt.args or {}) then return reject(Tr.RegionInvokeArgCount(stmt.target, #(region.params or {}), #(stmt.args or {}))) end
  for i = 1, #(stmt.wiring or {}) do
    for j = 1, i - 1 do
      if stmt.wiring[j].name == stmt.wiring[i].name then return reject(Tr.RegionInvokeDuplicateWire(stmt.target, stmt.wiring[i].name)) end
    end
function Tr.RegionWireCont:region_capture_projection(cont) return capture_projection_for_args(self.args, cont, "cont_" .. self.cont.name) end
    for j = 1, #(region.conts or {}) do if region.conts[j]:region_cont_matches_name(stmt.wiring[i].name) then found = true end end
    if not found then return reject(Tr.RegionInvokeExtraWire(stmt.target, stmt.wiring[i].name)) end
  end
  for i = 1, #(region.conts or {}) do
    local found = false
    for j = 1, #(stmt.wiring or {}) do if stmt.wiring[j].name == region.conts[i].name then found = true end end
    if not found then return reject(Tr.RegionInvokeMissingWire(stmt.target, region.conts[i])) end
  end
  return expand_definition(stmt, input, self.entry.definition)
end
function Tr.RegionDefinitionMissing:region_expand_invoke(stmt, input) return reject(Tr.RegionInvokeMissingTarget(stmt.target)) end
function Tr.RegionSealFound:region_expand_call(stmt, input)
  return input.facts.definitions:region_definition_lookup(stmt.target):region_expand_invoke(stmt, input)
end
function Tr.RegionSealMissing:region_expand_call(stmt, input)
  return reject(Tr.RegionInvokeCallFrameUnsupported(stmt.target, "region-call", "no canonical call frame seal"))
end
function Tr.StmtRegionEmit:region_expand_invoke(input)
  return input.facts.definitions:region_definition_lookup(self.target):region_expand_invoke(self, input)
end
function Tr.StmtRegionCall:region_expand_invoke(input)
  return input.facts.seals:region_seal_lookup(self.target):region_expand_call(self, input)
end

function Tr.RegionInvokeExpanded:region_expand_stmt(input)
  return Tr.RegionStmtExpansionResult(self.splice.next_state, { self.splice.entry_stmt }, self.splice.blocks, {})
end
function Tr.RegionInvokeRejected:region_expand_stmt(input)
  return Tr.RegionStmtExpansionResult(input.state, { Tr.StmtTrap(Tr.StmtSurface) }, {}, { Check.TypeIssueRegionInvoke(self.reject) })
end
local function invoke_stmt(stmt, input)
  return stmt:region_expand_invoke(input):region_expand_stmt(input)
end
function Tr.StmtRegionEmit:region_expand_stmt(input) return invoke_stmt(self, input) end
function Tr.StmtRegionCall:region_expand_stmt(input) return invoke_stmt(self, input) end

-- -------------------------------------------------------------------------
-- Function/item/module composition.
-- -------------------------------------------------------------------------
local function expand_function(func, input)
  local facts = input.facts
  local state = Check.TypeStmtInput(Check.TypeValueScope("region", {}, {}, {}, Check.TypeModuleFacts({}, {}, {}, facts)), func.result, Check.TypeYieldNone)
  for i = 1, #(func.params or {}) do
    local p = func.params[i]
    local binding = B.Binding(C.Id("arg:" .. tostring(func.name) .. ":" .. tostring(p.name)), p.name, p.ty, B.BindingRoleArg(i - 1))
    state = Check.TypeStmtInput(state.scope:typecheck_tree_add_value(p.name, p.ty, binding), state.return_ty, state.yield)
  end
  return Tr.RegionBodyExpansionInput(state, facts, Tr.RegionExpansionId("function:" .. tostring(func.name))):region_expand_body(func.body)
end
function Tr.Func:region_expand_function(input) return Tr.RegionBodyExpansionResult(input.facts, Tr.RegionStmtBody({}), {}, {}) end
function Tr.FuncLocal:region_expand_function(input) return expand_function(self, input) end
function Tr.FuncExport:region_expand_function(input) return expand_function(self, input) end
function Tr.FuncLocalContract:region_expand_function(input) return expand_function(self, input) end
function Tr.FuncExportContract:region_expand_function(input) return expand_function(self, input) end
function Tr.FuncDecl:region_expand_function(input)
  return Tr.RegionBodyExpansionResult(Check.TypeStmtInput(Check.TypeValueScope("region", {}, {}, {}, Check.TypeModuleFacts({}, {}, {}, input.facts)), self.result, Check.TypeYieldNone), Tr.RegionStmtBody({}), {}, {})
end
function Tr.Func:region_rebuild_expanded(body) return self end
function Tr.FuncLocal:region_rebuild_expanded(body) return Tr.FuncLocal(self.name, self.params, self.result, body.stmts) end
function Tr.FuncExport:region_rebuild_expanded(body) return Tr.FuncExport(self.name, self.params, self.result, body.stmts) end
function Tr.FuncLocalContract:region_rebuild_expanded(body) return Tr.FuncLocalContract(self.name, self.params, self.result, self.contracts, body.stmts) end
function Tr.FuncExportContract:region_rebuild_expanded(body) return Tr.FuncExportContract(self.name, self.params, self.result, self.contracts, body.stmts) end

function Tr.Item:region_expand_item(input) return Check.TypeItemResult({ self }, {}) end
function Tr.ItemFunc:region_expand_item(input)
  local body = self.func:region_expand_function(input)
  return Check.TypeItemResult({ Tr.ItemFunc(self.func:region_rebuild_expanded(body.body)) }, body.issues)
end

function Tr.Module:region_expand(input)
  local items, issues = {}, {}
  for i = 1, #(self.items or {}) do
    local result = self.items[i]:region_expand_item(input)
    append(items, result.items); append(issues, result.issues)
  end
  local module = Tr.Module(self.h, items)
  if #issues == 0 then return Tr.RegionModuleExpanded(module, input.facts, issues) end
  return Tr.RegionModuleRejected(module, input.facts, issues)
end

return true
