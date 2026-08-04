-- Canonical schema-v2 region facts and immutable expansion.
-- Region behavior is deliberately attached to concrete ASDL leaves.

require("lalin.schema_v2")
local Tr = require("lalin.schema_v2.tree")
local C = require("lalin.schema_v2.core")
local B = require("lalin.schema_v2.bind")
local Ty = require("lalin.schema_v2.type")
local Check = require("lalin.schema_v2.check")
local Sem = require("lalin.schema_v2.sem")
local P = require("lalin.schema_v2.parse")

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

local function sealed_stem(name)
  return tostring(name):gsub("[^%w_]", "_")
end
local function sealed_function_name(name) return "__lalin_region_call_" .. sealed_stem(name) end
local function sealed_result_name(name) return "__lalin_region_result_" .. sealed_stem(name) end
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
  local result_name = sealed_result_name(self.region.name)
  for i = 1, #(self.region.conts or {}) do
    local cont = self.region.conts[i]
    payloads[i] = Tr.RegionSealPayload(cont, Tr.RegionResultTypeId(result_name .. "." .. tostring(cont.name)))
  end
  local protocol = Tr.RegionProtocol(Tr.RegionProtocolKey(tostring(self.region.name)), Tr.RegionResultTypeId(result_name), payloads)
  return Tr.RegionProtocolProjection({ Tr.RegionProtocolEntry(protocol.key, protocol) })
end
function Tr.ItemRegion:region_seal_projection()
  local target = target_for_region(self.region)
  local payloads = {}
  local result_name = sealed_result_name(self.region.name)
  for i = 1, #(self.region.conts or {}) do
    local cont = self.region.conts[i]
    payloads[i] = Tr.RegionSealPayload(cont, Tr.RegionResultTypeId(result_name .. "." .. tostring(cont.name)))
  end
  local protocol = Tr.RegionProtocol(Tr.RegionProtocolKey(tostring(self.region.name)), Tr.RegionResultTypeId(result_name), payloads)
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
-- Wire arguments may name the invoked region's continuation parameters as
-- forwarding markers (e.g. `done = finished(extra = 7, left, right)` where
-- `left`/`right` are the cont's outgoing values).  Each marker is
-- substituted with the region exit's actual argument value; the remaining
-- explicit arguments are evaluated at the exit site.
-- The wire-argument projection is built from the region exit's arguments;
-- the lookup leaves own the substituted/original decision, and expression
-- leaves classify whether a wire argument value is a forwarding marker.
function Tr.RegionWireArgProjection:region_wire_arg_lookup(name)
  for i = 1, #(self.entries or {}) do
    local entry = self.entries[i]
    if entry.name == name then return Tr.RegionWireArgFound(entry) end
  end
  return Tr.RegionWireArgMissing(name)
end

function Tr.RegionWireArgFound:region_wire_arg_result(arg)
  return Tr.JumpArg(arg.name, self.entry.value)
end
function Tr.RegionWireArgMissing:region_wire_arg_result(arg)
  return arg
end

function Tr.RegionWireArgMarkerName:region_wire_arg_result(projection, arg)
  return projection:region_wire_arg_lookup(self.name):region_wire_arg_result(arg)
end
function Tr.RegionWireArgMarkerValue:region_wire_arg_result(_projection, arg)
  return arg
end

-- Forwarding-marker classification is leaf-owned on expressions.
function Tr.Expr:region_wire_arg_marker() return Tr.RegionWireArgMarkerValue end
function Tr.ExprRef:region_wire_arg_marker() return self.ref:region_wire_arg_marker() end
function B.ValueRef:region_wire_arg_marker() return Tr.RegionWireArgMarkerValue end
function B.ValueRefName:region_wire_arg_marker() return Tr.RegionWireArgMarkerName(self.name) end

local function wire_args(target_args, source_args)
  if #(target_args or {}) == 0 then return source_args or {} end
  local entries = {}
  for i = 1, #(source_args or {}) do
    entries[i] = Tr.RegionWireArgEntry(source_args[i].name, source_args[i].value)
  end
  local projection = Tr.RegionWireArgProjection(entries)
  local out = {}
  for i = 1, #(target_args or {}) do
    local arg = target_args[i]
    out[i] = arg.value:region_wire_arg_marker():region_wire_arg_result(projection, arg)
  end
  return out
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

-- A wire argument that names a continuation parameter is forwarded (not
-- captured); the marker leaves own the decision, reusing the same
-- leaf-owned expression classification as wire-argument substitution.
function Tr.RegionWireArgMarkerValue:region_wire_arg_captured(_cont) return true end
function Tr.RegionWireArgMarkerName:region_wire_arg_captured(cont)
  for j = 1, #(cont and cont.params or {}) do
    if cont.params[j].name == self.name then return false end
  end
  return true
end

local function capture_projection_for_args(args, cont, prefix)
  local entries = {}
  for i = 1, #(args or {}) do
    local arg = args[i]
    if arg.value:region_wire_arg_marker():region_wire_arg_captured(cont) then
      entries[#entries + 1] = Tr.RegionCallCaptureEntry(
        "__region_capture_" .. tostring(prefix) .. "_" .. tostring(i), expr_type(arg.value), arg.value)
    end
  end
  return Tr.RegionCallCaptureProjection(entries)
end
function Tr.RegionWireTarget:region_capture_projection(cont) return Tr.RegionCallCaptureProjection({}) end
function Tr.RegionWireBlock:region_capture_projection(cont) return capture_projection_for_args(self.args, cont, self.label.name) end
function Tr.RegionWireCont:region_capture_projection(cont) return capture_projection_for_args(self.args, cont, "cont_" .. self.cont.name) end
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

-- -------------------------------------------------------------------------
-- Parsed continuation projection and lookup.  The projection is built
-- from the assembled RegionCont list (assembly owns the ParsedExit ->
-- RegionCont conversion), so retargeted jumps and wire targets share the
-- exact interned continuation value stored on the region.
-- -------------------------------------------------------------------------
function P.ParsedRegion:parsed_cont_projection(conts)
  local entries = {}
  for i = 1, #(conts or {}) do
    local cont = conts[i]
    entries[i] = P.ParsedContEntry(cont.name, cont)
  end
  return P.ParsedContProjection(entries)
end

function P.ParsedContProjection:parsed_cont_lookup(name)
  for i = 1, #(self.entries or {}) do
    local entry = self.entries[i]
    if entry.name == name then return P.ParsedContFound(entry) end
  end
  return P.ParsedContMissing(name)
end

-- The lookup result leaves own the retargeting decisions.
function P.ParsedContFound:region_retarget_jump(jump)
  return Tr.StmtJumpCont(jump.h, self.entry.cont, jump.args)
end
function P.ParsedContMissing:region_retarget_jump(jump) return jump end
function P.ParsedContFound:region_retarget_wire(wire)
  return Tr.RegionWireCont(self.entry.cont, wire.args)
end
function P.ParsedContMissing:region_retarget_wire(wire) return wire end

-- -------------------------------------------------------------------------
-- Assembly-time statement retargeting.  Each statement leaf that owns
-- nested statements or a jump/wire target retargets itself; the parent
-- default passes through.  A StmtJump whose target names a region
-- continuation becomes a StmtJumpCont; a RegionWireBlock whose label names
-- a continuation becomes a RegionWireCont.
-- -------------------------------------------------------------------------
local function retarget_region_body(stmts, retarget_input)
  local out = {}
  for i = 1, #(stmts or {}) do out[i] = stmts[i]:region_retarget_cont(retarget_input) end
  return out
end

local function retarget_region_wiring(wiring, retarget_input)
  local out = {}
  for i = 1, #(wiring or {}) do out[i] = wiring[i]:region_retarget_cont(retarget_input) end
  return out
end

function Tr.Stmt:region_retarget_cont(retarget_input) return self end
function Tr.StmtJump:region_retarget_cont(retarget_input)
  return retarget_input.cont_projection:parsed_cont_lookup(self.target.name):region_retarget_jump(self)
end
function Tr.StmtIf:region_retarget_cont(retarget_input)
  return Tr.StmtIf(self.h, self.cond,
    retarget_region_body(self.then_body, retarget_input),
    retarget_region_body(self.else_body, retarget_input))
end
function Tr.StmtSwitch:region_retarget_cont(retarget_input)
  local arms, variant_arms, default_body = {}, {}, retarget_region_body(self.default_body or {}, retarget_input)
  for i = 1, #(self.arms or {}) do
    arms[i] = Tr.SwitchStmtArm(self.arms[i].key, retarget_region_body(self.arms[i].body or {}, retarget_input))
  end
  for i = 1, #(self.variant_arms or {}) do
    variant_arms[i] = Tr.SwitchVariantStmtArm(self.variant_arms[i].variant_name, self.variant_arms[i].binds,
      retarget_region_body(self.variant_arms[i].body or {}, retarget_input))
  end
  return Tr.StmtSwitch(self.h, self.value, arms, variant_arms, default_body)
end
function Tr.StmtVariantSwitchSource:region_retarget_cont(retarget_input)
  local arms, variant_arms, default_body = {}, {}, retarget_region_body(self.default_body or {}, retarget_input)
  for i = 1, #(self.arms or {}) do
    arms[i] = Tr.SwitchStmtArm(self.arms[i].key, retarget_region_body(self.arms[i].body or {}, retarget_input))
  end
  for i = 1, #(self.variant_arms or {}) do
    variant_arms[i] = Tr.SwitchVariantSourceStmtArm(self.variant_arms[i].variant_name, self.variant_arms[i].binds,
      retarget_region_body(self.variant_arms[i].body or {}, retarget_input))
  end
  return Tr.StmtVariantSwitchSource(self.h, self.value, arms, variant_arms, default_body)
end
function Tr.StmtRegionEmit:region_retarget_cont(retarget_input)
  return Tr.StmtRegionEmit(self.h, self.invoke_id, self.target, self.args,
    retarget_region_wiring(self.wiring or {}, retarget_input))
end
function Tr.StmtRegionCall:region_retarget_cont(retarget_input)
  return Tr.StmtRegionCall(self.h, self.invoke_id, self.target, self.args,
    retarget_region_wiring(self.wiring or {}, retarget_input))
end
function Tr.RegionContWire:region_retarget_cont(retarget_input)
  return Tr.RegionContWire(self.name, self.target:region_retarget_cont(retarget_input))
end
function Tr.RegionWireTarget:region_retarget_cont(retarget_input) return self end
function Tr.RegionWireBlock:region_retarget_cont(retarget_input)
  return retarget_input.cont_projection:parsed_cont_lookup(self.label.name):region_retarget_wire(self)
end
function Tr.RegionWireCont:region_retarget_cont(retarget_input) return self end

function Tr.EntryControlBlock:parsed_region_control_block_view()
  local params = {}
  for i = 1, #(self.params or {}) do
    local p = self.params[i]
    params[i] = Tr.BlockParam(p.name, p.ty)
  end
  return Tr.ControlBlock(self.label, params, self.body)
end

-- -------------------------------------------------------------------------
-- Parsed region assembly conversions and contract lowering.
-- -------------------------------------------------------------------------
function P.ParsedField:parsed_block_param()
  return Tr.BlockParam(self.name, self.ty)
end
function P.ParsedField:parsed_entry_block_param()
  return Tr.EntryBlockParam(self.name, self.ty, Tr.ExprRef(Tr.ExprSurface, B.ValueRefName(self.name)))
end
function P.ParsedExit:parsed_region_cont(input)
  local params = {}
  for i = 1, #(self.fields or {}) do params[i] = self.fields[i]:parsed_block_param() end
  return Tr.RegionCont(
    Tr.RegionProtocolKey("cont:" .. tostring(input.region_name) .. ":" .. tostring(self.name) .. ":" .. tostring(input.index)),
    self.name, params)
end

function P.StmtRequiresParsed:parsed_contract_values()
  local contracts = {}
  for i = 1, #(self.contracts or {}) do contracts[i] = self.contracts[i]:parsed_contract_value() end
  return contracts
end

-- Each typed ParsedContract leaf owns the FuncContract construction; no
-- string dispatch remains.
function P.ParsedContractReadonly:parsed_contract_value() return Tr.ContractReadonly(self.arg) end
function P.ParsedContractWriteonly:parsed_contract_value() return Tr.ContractWriteonly(self.arg) end
function P.ParsedContractNoAlias:parsed_contract_value() return Tr.ContractNoAlias(self.arg) end
function P.ParsedContractNoAliasPair:parsed_contract_value() return Tr.ContractNoAliasPair(self.a, self.b) end
function P.ParsedContractInvalidate:parsed_contract_value() return Tr.ContractInvalidate(self.arg) end
function P.ParsedContractPreserve:parsed_contract_value() return Tr.ContractPreserve(self.arg) end
function P.ParsedContractBounds:parsed_contract_value() return Tr.ContractBounds(self.a, self.b) end
function P.ParsedContractDisjoint:parsed_contract_value() return Tr.ContractDisjoint(self.a, self.b) end
function P.ParsedContractSameLen:parsed_contract_value() return Tr.ContractSameLen(self.a, self.b) end

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
function Tr.StmtJump:region_clone_for_invoke(invoke_id, wires, conts)
  return Tr.StmtJump(self.h, prefixed_label(invoke_id, self.target), self.args)
end
function Tr.StmtBranchJump:region_clone_for_invoke(invoke_id, wires, conts)
  return Tr.StmtBranchJump(self.h, self.cond,
    prefixed_label(invoke_id, self.then_target), self.then_args,
    prefixed_label(invoke_id, self.else_target), self.else_args)
end
function Tr.StmtVariantSwitchSource:region_clone_for_invoke(invoke_id, wires, conts)
  local arms, variant_arms, default_body = {}, {}, {}
  for i = 1, #(self.arms or {}) do
    local body = {}; for j = 1, #(self.arms[i].body or {}) do body[j] = clone_stmt(self.arms[i].body[j], invoke_id, wires, conts) end
    arms[i] = Tr.SwitchStmtArm(self.arms[i].key, body)
  end
  for i = 1, #(self.variant_arms or {}) do
    local body = {}; for j = 1, #(self.variant_arms[i].body or {}) do body[j] = clone_stmt(self.variant_arms[i].body[j], invoke_id, wires, conts) end
    variant_arms[i] = Tr.SwitchVariantSourceStmtArm(self.variant_arms[i].variant_name, self.variant_arms[i].binds, body)
  end
  for i = 1, #(self.default_body or {}) do default_body[i] = clone_stmt(self.default_body[i], invoke_id, wires, conts) end
  return Tr.StmtVariantSwitchSource(self.h, self.value, arms, variant_arms, default_body)
end
local function clone_wiring(wiring, invoke_id, wires, conts)
  local out = {}
  for i = 1, #(wiring or {}) do out[i] = wiring[i]:region_clone_for_invoke(invoke_id, wires, conts) end
  return out
end
function Tr.RegionWireBlock:region_clone_for_invoke(invoke_id, wires, conts)
  return Tr.RegionWireBlock(prefixed_label(invoke_id, self.label), self.args)
end
function Tr.RegionWireFound:region_clone_cont_wire(_cont, _original) return self.entry.wire.target end
function Tr.RegionWireMissing:region_clone_cont_wire(_cont, original) return original end
function Tr.RegionWireCont:region_clone_for_invoke(invoke_id, wires, conts)
  return wire_for_cont(wires, self.cont):region_clone_cont_wire(self.cont, self)
end
function Tr.RegionContWire:region_clone_for_invoke(invoke_id, wires, conts)
  return Tr.RegionContWire(self.name, self.target:region_clone_for_invoke(invoke_id, wires, conts))
end
function Tr.StmtRegionEmit:region_clone_for_invoke(invoke_id, wires, conts)
  return Tr.StmtRegionEmit(self.h, tostring(invoke_id) .. "." .. tostring(self.invoke_id), self.target, self.args,
    clone_wiring(self.wiring or {}, invoke_id, wires, conts))
end
function Tr.StmtRegionCall:region_clone_for_invoke(invoke_id, wires, conts)
  return Tr.StmtRegionCall(self.h, tostring(invoke_id) .. "." .. tostring(self.invoke_id), self.target, self.args,
    clone_wiring(self.wiring or {}, invoke_id, wires, conts))
end

-- -------------------------------------------------------------------------
-- Sealed callable-region materialization.
-- -------------------------------------------------------------------------
local function seal_stmt(stmt, result_name)
  return stmt:region_seal_result_stmt(result_name)
end

local function seal_body(body, result_name)
  local out = {}
  for i = 1, #(body or {}) do out[i] = seal_stmt(body[i], result_name) end
  return out
end

function Tr.Stmt:region_seal_result_stmt(_result_name) return self end
function Tr.StmtJumpCont:region_seal_result_stmt(result_name)
  local values = {}
  for i = 1, #(self.cont.params or {}) do
    local param = self.cont.params[i]
    local projection_entries = {}
    for j = 1, #(self.args or {}) do
      projection_entries[j] = Tr.RegionWireArgEntry(self.args[j].name, self.args[j].value)
    end
    local value = Tr.RegionWireArgProjection(projection_entries):region_wire_arg_lookup(param.name):region_seal_payload_value(param)
    values[i] = value
  end
  local args = {}
  for i = 1, #(self.cont.params or {}) do args[i] = Tr.JumpArg(self.cont.params[i].name, values[i]) end
  return Tr.StmtJump(Tr.StmtSurface, Tr.BlockLabel("__seal_exit_" .. sealed_stem(self.cont.name)), args)
end
function Tr.RegionWireArgFound:region_seal_payload_value(_param) return self.entry.value end
function Tr.RegionWireArgMissing:region_seal_payload_value(param)
  error("sealed region exit missing payload `" .. tostring(param.name) .. "`", 2)
end
function Tr.StmtIf:region_seal_result_stmt(result_name)
  return Tr.StmtIf(self.h, self.cond, seal_body(self.then_body, result_name), seal_body(self.else_body, result_name))
end
function Tr.StmtSwitch:region_seal_result_stmt(result_name)
  local arms, variants = {}, {}
  for i = 1, #(self.arms or {}) do arms[i] = Tr.SwitchStmtArm(self.arms[i].key, seal_body(self.arms[i].body, result_name)) end
  for i = 1, #(self.variant_arms or {}) do
    local arm = self.variant_arms[i]
    variants[i] = Tr.SwitchVariantStmtArm(arm.variant_name, arm.binds, seal_body(arm.body, result_name))
  end
  return Tr.StmtSwitch(self.h, self.value, arms, variants, seal_body(self.default_body, result_name))
end
function Tr.StmtVariantSwitchSource:region_seal_result_stmt(result_name)
  local arms, variants = {}, {}
  for i = 1, #(self.arms or {}) do arms[i] = Tr.SwitchStmtArm(self.arms[i].key, seal_body(self.arms[i].body, result_name)) end
  for i = 1, #(self.variant_arms or {}) do
    local arm = self.variant_arms[i]
    variants[i] = Tr.SwitchVariantSourceStmtArm(arm.variant_name, arm.binds, seal_body(arm.body, result_name))
  end
  return Tr.StmtVariantSwitchSource(self.h, self.value, arms, variants, seal_body(self.default_body, result_name))
end
function Tr.EntryControlBlock:region_seal_result_block(result_name)
  return Tr.EntryControlBlock(self.label, self.params, seal_body(self.body, result_name))
end
function Tr.ControlBlock:region_seal_result_block(result_name)
  return Tr.ControlBlock(self.label, self.params, seal_body(self.body, result_name))
end
function Tr.ControlStmtRegion:region_seal_result_control(result_name)
  local blocks = {}
  for i = 1, #(self.blocks or {}) do blocks[i] = self.blocks[i]:region_seal_result_block(result_name) end
  return Tr.ControlStmtRegion(self.region_id, self.entry:region_seal_result_block(result_name), blocks)
end
function Tr.StmtControl:region_seal_result_stmt(result_name)
  return Tr.StmtControl(self.h, self.region:region_seal_result_control(result_name))
end
function Tr.StmtDomainControl:region_seal_result_stmt(result_name)
  return Tr.StmtDomainControl(self.h, self.region:region_seal_result_control(result_name), self.domain)
end

function Tr.RegionSeal:region_materialize()
  local result_name = self.protocol.result_type.text
  local variants = {}
  for i = 1, #(self.region.conts or {}) do
    local cont, fields = self.region.conts[i], {}
    for j = 1, #(cont.params or {}) do fields[j] = Ty.FieldDecl(cont.params[j].name, cont.params[j].ty) end
    variants[i] = Ty.VariantDecl(cont.name, fields)
  end
  local result_item = Tr.ItemType(Tr.TypeDeclTaggedUnionSugar(result_name, variants))
  local result_ty = Ty.TNamed(Ty.TypeRefPath(C.Path({ C.Name(result_name) })))
  local blocks = {}
  for i = 1, #(self.region.blocks or {}) do blocks[i] = self.region.blocks[i]:region_seal_result_block(result_name) end
  for i = 1, #(self.region.conts or {}) do
    local cont, params, values = self.region.conts[i], {}, {}
    for j = 1, #(cont.params or {}) do
      local param = cont.params[j]
      params[j] = Tr.BlockParam(param.name, param.ty)
      values[j] = Tr.ExprRef(Tr.ExprSurface, B.ValueRefName(param.name))
    end
    blocks[#blocks + 1] = Tr.ControlBlock(
      Tr.BlockLabel("__seal_exit_" .. sealed_stem(cont.name)), params,
      { Tr.StmtReturnValue(Tr.StmtSurface, Tr.ExprCtor(Tr.ExprSurface, result_name, cont.name, values)) })
  end
  local control = Tr.ControlStmtRegion("region:" .. tostring(self.region.name), self.region.entry:region_seal_result_block(result_name), blocks)
  local function_item = Tr.ItemFunc(Tr.FuncLocalContract(self.function_id.text, self.region.params, result_ty, self.region.contracts,
    { Tr.StmtControl(Tr.StmtSurface, control) }))
  return Tr.RegionSealMaterialization(result_item, function_item)
end
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
function Tr.StmtDomainControl:region_expand_stmt(input)
  local result = self.region:region_expand_control(input)
  local control = result.stmts[1]
  return Tr.RegionStmtExpansionResult(result.next_state,
    { Tr.StmtDomainControl(control.h, control.region, self.domain) },
    result.blocks, result.issues)
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
  local splice = Tr.RegionInvokeSplice({ Tr.StmtJump(stmt.h, entry_label, entry_args) }, blocks, captures, input.state)
  return Tr.RegionInvokeExpanded(splice)
end
function Tr.RegionDefinitionFound:region_expand_invoke(stmt, input)
  local region = self.entry.definition.region
  if #(region.params or {}) ~= #(stmt.args or {}) then return reject(Tr.RegionInvokeArgCount(stmt.target, #(region.params or {}), #(stmt.args or {}))) end
  for i = 1, #(stmt.wiring or {}) do
    for j = 1, i - 1 do
      if stmt.wiring[j].name == stmt.wiring[i].name then return reject(Tr.RegionInvokeDuplicateWire(stmt.target, stmt.wiring[i].name)) end
    end
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
  local seal = self.entry.seal
  if #(seal.region.params or {}) ~= #(stmt.args or {}) then
    return reject(Tr.RegionInvokeArgCount(stmt.target, #(seal.region.params or {}), #(stmt.args or {})))
  end
  local result_name = seal.protocol.result_type.text
  local result_ty = Ty.TNamed(Ty.TypeRefPath(C.Path({ C.Name(result_name) })))
  local binding = B.Binding(C.Id("region:call:" .. tostring(stmt.invoke_id)),
    "__region_call_result_" .. sealed_stem(stmt.invoke_id), result_ty, B.BindingRoleLocalValue)
  local call = Tr.ExprCall(Tr.ExprSurface, Tr.ExprRef(Tr.ExprSurface, B.ValueRefName(seal.function_id.text)), stmt.args)
  local let = Tr.StmtLet(Tr.StmtSurface, binding, call)
  local arms = {}
  for i = 1, #(seal.region.conts or {}) do
    local cont, binds, payload_args = seal.region.conts[i], {}, {}
    for j = 1, #(cont.params or {}) do
      local param = cont.params[j]
      local bind_name = "__region_payload_" .. sealed_stem(stmt.invoke_id) .. "_" .. sealed_stem(cont.name) .. "_" .. sealed_stem(param.name)
      binds[j] = Tr.VariantBindSource(bind_name)
      payload_args[j] = Tr.JumpArg(param.name, Tr.ExprRef(Tr.ExprSurface, B.ValueRefName(bind_name)))
    end
    local target = wire_for_cont(stmt.wiring, cont):region_retarget_jump(cont, payload_args)
    arms[i] = Tr.SwitchVariantSourceStmtArm(cont.name, binds, { target })
  end
  local switch = Tr.StmtVariantSwitchSource(Tr.StmtSurface,
    Tr.ExprRef(Tr.ExprSurface, B.ValueRefName(binding.name)), {}, arms, { Tr.StmtTrap(Tr.StmtSurface) })
  local next_scope = input.state.scope:typecheck_tree_add_value(binding.name, result_ty, binding)
  local next_state = Check.TypeStmtInput(next_scope, input.state.return_ty, input.state.yield)
  return Tr.RegionInvokeExpanded(Tr.RegionInvokeSplice({ let, switch }, {},
    collect_captures(stmt.wiring, seal.region.conts), next_state))
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
  return Tr.RegionStmtExpansionResult(self.splice.next_state, self.splice.entry_stmts, self.splice.blocks, {})
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
function Tr.RegionSealFound:region_expand_materialized_item(input)
  local artifacts = self.entry.seal:region_materialize()
  local func = artifacts.function_item.func
  local expanded = func:region_expand_function(input)
  local sealed_body = Tr.RegionStmtBody(seal_body(expanded.body.stmts, self.entry.seal.protocol.result_type.text))
  local function_item = Tr.ItemFunc(func:region_rebuild_expanded(sealed_body))
  return Check.TypeItemResult({ artifacts.result_item, function_item }, expanded.issues)
end
function Tr.RegionSealMissing:region_expand_materialized_item(_input)
  return Check.TypeItemResult({}, { Check.TypeIssueRegionInvoke(
    Tr.RegionInvokeCallFrameUnsupported(self.target, "region-seal", "missing materialization seal")) })
end
function Tr.ItemRegion:region_expand_item(input)
  return input.facts.seals:region_seal_lookup(target_for_region(self.region)):region_expand_materialized_item(input)
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

-- Shared phase composition: typecheck the module, derive region facts,
-- expand regions (consuming region items and splicing region bodies into
-- caller control regions), and re-typecheck the expanded module so every
-- reference carries bindings consistent with the expanded block structure.
-- The result is the same typed RegionModuleExpanded/Rejected leaves as
-- region_expand, so callers share the same result handling.
-- Module:typecheck carries no semantic input, so the shared phase calls it
-- without any argument bag.
function Tr.Module:typecheck_region_expanded()
  local checked = self:typecheck()
  local facts = checked:region_fact_projection()
  local expansion = checked:region_expand(Tr.RegionModuleExpansionInput(facts))
  if #(expansion:region_issues() or {}) > 0 then
    return expansion
  end
  local expanded = expansion:region_module():typecheck()
  return Tr.RegionModuleExpanded(expanded, facts, {})
end

return true
