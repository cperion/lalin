-- impl/tree_check/stmt.lua
-- Statement typechecking leaf methods.

require("lalin.schema")
local Tr     = require("lalin.schema.tree")
local Ty     = require("lalin.schema.type")
local C      = require("lalin.schema.core")
local LCheck = require("lalin.schema.check")
local Sem    = require("lalin.schema.sem")
local B      = require("lalin.schema.bind")

function Tr.Stmt:typecheck_tree_stmt(input) return LCheck.TypeStmtResult(input, {self}, {}) end

-- Body typechecking: fold through statement list
function LCheck.TypeStmtInput:typecheck_tree_stmt_body(stmts)
  local state = self
  local out_stmts = {}
  local issues = {}
  for i = 1, #(stmts or {}) do
    local r = stmts[i]:typecheck_tree_stmt(state)
    if r and r.state then state = r.state end
    if r and r.stmts then
      for j = 1, #r.stmts do out_stmts[#out_stmts + 1] = r.stmts[j] end
    end
    if r and r.issues then
      for j = 1, #r.issues do issues[#issues + 1] = r.issues[j] end
    end
  end
  return LCheck.TypeStmtResult(state, out_stmts, issues)
end
-- Helper: check if expr result has errors (void type with issues)
local function is_error_result(er)
  return er.ty:tree_check_is_void_type() and #(er.issues or {}) > 0
end

function Tr.StmtLet:typecheck_tree_stmt(input)
  -- Typecheck the init against the declared binding type so aggregate and
  -- array literals inherit element types (e.g. `let xs [array [i32] [3]] = { ... }`).
  local er = self.init:typecheck_tree_expr_expected(LCheck.TypeExpectedExprInput(input.scope, self.binding.ty))
  if is_error_result(er) then return LCheck.TypeStmtResult(input, {self}, er.issues) end
  local scope = input.scope:typecheck_tree_add_value(self.binding.name, er.ty, self.binding)
  return LCheck.TypeStmtResult(LCheck.TypeStmtInput(scope, input.return_ty, input.yield, input.control), {Tr.StmtLet(Tr.StmtFlow(Sem.FlowFallsThrough), self.binding, er.expr)}, {})
end
function Tr.StmtVar:typecheck_tree_stmt(input)
  local er = self.init:typecheck_tree_expr_expected(LCheck.TypeExpectedExprInput(input.scope, self.binding.ty))
  if is_error_result(er) then return LCheck.TypeStmtResult(input, {self}, er.issues) end
  local scope = input.scope:typecheck_tree_add_value(self.binding.name, er.ty, self.binding)
  return LCheck.TypeStmtResult(LCheck.TypeStmtInput(scope, input.return_ty, input.yield, input.control), {Tr.StmtVar(Tr.StmtFlow(Sem.FlowFallsThrough), self.binding, er.expr)}, {})
end
function Tr.StmtSet:typecheck_tree_stmt(input)
  local pr = self.place:typecheck_tree_place(LCheck.TypePlaceInput(input.scope))
  local expected = pr.ty
  local vr = expected ~= nil and self.value:typecheck_tree_expr_expected(
    LCheck.TypeExpectedExprInput(input.scope, expected))
    or self.value:typecheck_tree_expr(LCheck.TypeExprInput(input.scope))
  if is_error_result(vr) then return LCheck.TypeStmtResult(input, {self}, vr.issues) end
  return LCheck.TypeStmtResult(input, {Tr.StmtSet(Tr.StmtFlow(Sem.FlowFallsThrough), pr.place, vr.expr)}, {})
end
function Tr.StmtExpr:typecheck_tree_stmt(input)
  local er = self.expr:typecheck_tree_expr(LCheck.TypeExprInput(input.scope))
  if is_error_result(er) then return LCheck.TypeStmtResult(input, {self}, er.issues) end
  return LCheck.TypeStmtResult(input, {Tr.StmtExpr(Tr.StmtFlow(Sem.FlowFallsThrough), er.expr)}, {})
end
function Tr.StmtAssert:typecheck_tree_stmt(input)
  local cr = self.cond:typecheck_tree_expr(LCheck.TypeExprInput(input.scope))
  if is_error_result(cr) then return LCheck.TypeStmtResult(input, {self}, cr.issues) end
  return LCheck.TypeStmtResult(input, {Tr.StmtAssert(Tr.StmtFlow(Sem.FlowFallsThrough), cr.expr)}, {})
end
function Tr.StmtReturnValue:typecheck_tree_stmt(input)
  local vr = self.value:typecheck_tree_expr_expected(LCheck.TypeExpectedExprInput(input.scope, input.return_ty))
  if is_error_result(vr) then return LCheck.TypeStmtResult(input, {self}, vr.issues) end
  return LCheck.TypeStmtResult(input, {Tr.StmtReturnValue(Tr.StmtFlow(Sem.FlowReturns), vr.expr)}, {})
end
function Tr.StmtReturnVoid:typecheck_tree_stmt(input)
  return LCheck.TypeStmtResult(input, {Tr.StmtReturnVoid(Tr.StmtFlow(Sem.FlowReturns))}, {})
end
function Tr.StmtYieldValue:typecheck_tree_stmt(input)
  local vr = self.value:typecheck_tree_expr(LCheck.TypeExprInput(input.scope))
  if is_error_result(vr) then return LCheck.TypeStmtResult(input, {self}, vr.issues) end
  return LCheck.TypeStmtResult(input, {Tr.StmtYieldValue(Tr.StmtFlow(Sem.FlowYields), vr.expr)}, {})
end
function Tr.StmtYieldVoid:typecheck_tree_stmt(input)
  return LCheck.TypeStmtResult(input, {Tr.StmtYieldVoid(Tr.StmtFlow(Sem.FlowYields))}, {})
end
function Tr.StmtJump:typecheck_tree_stmt(input)
  local args, issues = {}, {}
  for i = 1, #self.args do
    local result = self.args[i].value:typecheck_tree_expr(LCheck.TypeExprInput(input.scope))
    args[i] = Tr.JumpArg(self.args[i].name, result.expr)
    for j = 1, #(result.issues or {}) do issues[#issues + 1] = result.issues[j] end
  end
  local region_id = input.control:typecheck_control_region_id()
  input.control:typecheck_control_block(self.target):typecheck_validate_jump(region_id, input.scope, self.target, args, issues)
  return LCheck.TypeStmtResult(input,
    {Tr.StmtJump(Tr.StmtFlow(Sem.FlowJumps), self.target, args)}, issues)
end
function Tr.StmtBranchJump:typecheck_tree_stmt(input)
  local condition = self.cond:typecheck_tree_expr(LCheck.TypeExprInput(input.scope))
  local issues = {}
  for i = 1, #(condition.issues or {}) do issues[#issues + 1] = condition.issues[i] end
  local function check_args(source)
    local args = {}
    for i = 1, #source do
      local result = source[i].value:typecheck_tree_expr(LCheck.TypeExprInput(input.scope))
      args[i] = Tr.JumpArg(source[i].name, result.expr)
      for j = 1, #(result.issues or {}) do issues[#issues + 1] = result.issues[j] end
    end
    return args
  end
  return LCheck.TypeStmtResult(input, { Tr.StmtBranchJump(
    Tr.StmtFlow(Sem.FlowJumps), condition.expr,
    self.then_target, check_args(self.then_args),
    self.else_target, check_args(self.else_args)) }, issues)
end
function Tr.StmtControl:typecheck_tree_stmt(input)
  return LCheck.TypeStmtResult(input, {Tr.StmtControl(Tr.StmtFlow(Sem.FlowFallsThrough), self.region)}, {})
end
local function control_scope(input, region_id, label, params, is_entry)
  local scope = input.scope
  for i = 1, #(params or {}) do
    local param = params[i]
    local role = is_entry
      and B.BindingRoleEntryBlockParam(region_id, label.name, i)
      or B.BindingRoleBlockParam(region_id, label.name, i)
    local binding = B.Binding(C.Id("control:param:" .. region_id .. "_" ..
      label.name .. "_" .. param.name), param.name, param.ty, role)
    scope = scope:typecheck_tree_add_value(param.name, param.ty, binding)
  end
  return LCheck.TypeStmtInput(scope, input.return_ty, LCheck.TypeYieldVoid, input.control)
end
local function typecheck_control_block(input, region_id, block)
  local result = control_scope(input, region_id, block.label, block.params, false)
    :typecheck_tree_stmt_body(block.body)
  return Tr.ControlBlock(block.label, block.params, result.stmts), result.issues
end

-- A control region typechecks its entry and body blocks so the block
-- statements (emits, calls, jumps, returns) carry typed expressions.
function Tr.ControlStmtRegion:typecheck_tree_control_region(input)
  local control = LCheck.TypeControlRegion(self.region_id, self.blocks or {}, {})
  local region_input = LCheck.TypeStmtInput(input.scope, input.return_ty, input.yield, control)
  local issues = {}
  local entry_input = control_scope(region_input, self.region_id,
    self.entry.label, self.entry.params, true)
  local entry_result = entry_input:typecheck_tree_stmt_body(self.entry.body)
  for i = 1, #(entry_result.issues or {}) do issues[#issues + 1] = entry_result.issues[i] end
  local entry = Tr.EntryControlBlock(
    self.entry.label, self.entry.params, entry_result.stmts)
  local blocks = {}
  for i = 1, #self.blocks do
    local block, block_issues = typecheck_control_block(region_input, self.region_id, self.blocks[i])
    blocks[i] = block
    for j = 1, #(block_issues or {}) do issues[#issues + 1] = block_issues[j] end
  end
  return Tr.ControlStmtRegion(self.region_id, entry, blocks), issues
end

function Tr.StmtControl:typecheck_tree_stmt(input)
  local region, issues = self.region:typecheck_tree_control_region(input)
  return LCheck.TypeStmtResult(input, {Tr.StmtControl(Tr.StmtFlow(Sem.FlowFallsThrough), region)}, issues)
end
function Tr.StmtDomainControl:typecheck_tree_stmt(input)
  local region, issues = self.region:typecheck_tree_control_region(input)
  return LCheck.TypeStmtResult(input, {Tr.StmtDomainControl(
    Tr.StmtFlow(Sem.FlowFallsThrough), region, self.domain)}, issues)
end

-- Region bodies typecheck like control regions, with the region data
-- params bound first so emit args, cont jumps, and returns carry typed
-- expressions when their values are later substituted into caller blocks.
function Tr.Region:typecheck_tree_region_body(input)
  local issues = {}
  local scope = input.scope
  local params = {}
  for i = 1, #(self.params or {}) do
    local p = self.params[i]
    local ty = p.ty:tree_region_resolve_type(input.scope)
    params[i] = Ty.Param(p.name, ty)
    local binding = B.Binding(C.Id("region:param:" .. tostring(self.name) .. ":" .. tostring(p.name)),
      p.name, ty, B.BindingRoleArg(i - 1))
    scope = scope:typecheck_tree_add_value(p.name, ty, binding)
  end
  local region_id = "region:" .. tostring(self.name)
  local typed_conts = {}
  for i = 1, #(self.conts or {}) do
    local cont, params = self.conts[i], {}
    for j = 1, #(cont.params or {}) do
      params[j] = Tr.BlockParam(cont.params[j].name, cont.params[j].ty:tree_region_resolve_type(input.scope))
    end
    typed_conts[i] = Tr.RegionCont(cont.key, cont.name, params)
  end
  local control = LCheck.TypeControlRegion(region_id, self.blocks or {}, typed_conts)
  local region_input = LCheck.TypeStmtInput(scope, input.return_ty, input.yield, control)
  local entry_input = control_scope(region_input, region_id,
    self.entry.label, self.entry.params, true)
  local entry_result = entry_input:typecheck_tree_stmt_body(self.entry.body)
  for i = 1, #(entry_result.issues or {}) do issues[#issues + 1] = entry_result.issues[i] end
  local entry = Tr.EntryControlBlock(
    self.entry.label, self.entry.params, entry_result.stmts)
  local blocks = {}
  for i = 1, #(self.blocks or {}) do
    local block, block_issues = typecheck_control_block(region_input, region_id, self.blocks[i])
    blocks[i] = block
    for j = 1, #(block_issues or {}) do issues[#issues + 1] = block_issues[j] end
  end
  return Tr.Region(self.name, params, typed_conts, self.contracts, entry, blocks), issues
end

function Tr.StmtTrap:typecheck_tree_stmt(input)
  return LCheck.TypeStmtResult(input, {Tr.StmtTrap(Tr.StmtFlow(Sem.FlowTerminates))}, {})
end
function Tr.StmtIf:typecheck_tree_stmt(input)
  local cr = self.cond:typecheck_tree_expr(LCheck.TypeExprInput(input.scope))
  local issues = {}
  if cr.issues then for _, iss in ipairs(cr.issues) do issues[#issues + 1] = iss end end
  if cr.ty and not cr.ty:tree_check_is_bool_type() then
    issues[#issues + 1] = LCheck.TypeIssueExpected("if condition", Ty.TScalar(C.ScalarBool), cr.ty)
  end
  local then_body = input:typecheck_tree_stmt_body(self.then_body or {})
  local else_body = input:typecheck_tree_stmt_body(self.else_body or {})
  if then_body.issues then for _, iss in ipairs(then_body.issues) do issues[#issues + 1] = iss end end
  if else_body.issues then for _, iss in ipairs(else_body.issues) do issues[#issues + 1] = iss end end
  return LCheck.TypeStmtResult(input, {Tr.StmtIf(Tr.StmtFlow(Sem.FlowFallsThrough), cr.expr, then_body.stmts, else_body.stmts)}, issues)
end

function Tr.StmtSwitch:typecheck_tree_stmt(input)
  local vr = self.value:typecheck_tree_expr(LCheck.TypeExprInput(input.scope))
  local issues = {}
  if vr.issues then for _, iss in ipairs(vr.issues) do issues[#issues + 1] = iss end end
  if vr.ty == nil or vr.ty:tree_check_is_void_type() then
    return LCheck.TypeStmtResult(input, {self}, issues)
  end
  -- Typecheck each scalar arm
  local arms = {}
  for i = 1, #(self.arms or {}) do
    local arm_body = input:typecheck_tree_stmt_body(self.arms[i].body or {})
    arms[#arms + 1] = Tr.SwitchStmtArm(self.arms[i].key, arm_body.stmts)
    if arm_body.issues then
      for _, iss in ipairs(arm_body.issues) do issues[#issues + 1] = iss end
    end
  end
  -- Typecheck variant arms
  local variant_arms = {}
  for i = 1, #(self.variant_arms or {}) do
    local va = self.variant_arms[i]
    local scope = input.scope
    for j = 1, #(va.binds or {}) do
      local bnd = va.binds[j]
      -- Variant bindings carry the same id the code phase binds under, so
      -- ValueRefBinding lookups resolve to the bound payload value.
      scope = scope:typecheck_tree_add_value(bnd.name, bnd.ty,
        B.Binding(C.Id("variant:stmt_switch_" .. va.variant_name .. "_" .. bnd.name), bnd.name, bnd.ty, B.BindingRoleLocalValue))
    end
    local arm_input = LCheck.TypeStmtInput(scope, input.return_ty, input.yield, input.control)
    local arm_body = arm_input:typecheck_tree_stmt_body(va.body or {})
    variant_arms[#variant_arms + 1] = Tr.SwitchVariantStmtArm(va.variant_name, va.binds, arm_body.stmts)
    if arm_body.issues then
      for _, iss in ipairs(arm_body.issues) do issues[#issues + 1] = iss end
    end
  end
  -- Typecheck default body
  local default_body = input:typecheck_tree_stmt_body(self.default_body or {})
  if default_body.issues then
    for _, iss in ipairs(default_body.issues) do issues[#issues + 1] = iss end
  end
  return LCheck.TypeStmtResult(input, {Tr.StmtSwitch(Tr.StmtFlow(Sem.FlowFallsThrough), vr.expr, arms, variant_arms, default_body.stmts)}, issues)
end
function Tr.StmtVariantSwitchSource:typecheck_tree_stmt(input)
  -- Source variant switch: the typed union lookup owns the payload bind
  -- decision per arm; the resolved arms fold into a typed StmtSwitch.
  local vr = self.value:typecheck_tree_expr(LCheck.TypeExprInput(input.scope))
  local issues = {}
  if vr.issues then for _, iss in ipairs(vr.issues) do issues[#issues + 1] = iss end end
  local arms = {}
  for i = 1, #(self.arms or {}) do
    local arm_body = input:typecheck_tree_stmt_body(self.arms[i].body or {})
    arms[#arms + 1] = Tr.SwitchStmtArm(self.arms[i].key, arm_body.stmts)
    if arm_body.issues then for _, iss in ipairs(arm_body.issues) do issues[#issues + 1] = iss end end
  end
  local variant_arms = {}
  if vr.ty ~= nil and not vr.ty:tree_check_is_void_type() then
    local variant_lookup = vr.ty:tree_check_lookup_variant(input.scope.facts)
    for i = 1, #(self.variant_arms or {}) do
      local source_arm = self.variant_arms[i]
      local arm_result = variant_lookup:typecheck_tree_lookup_variant_case(source_arm.variant_name)
        :typecheck_tree_source_variant_arm(source_arm, input)
      variant_arms[#variant_arms + 1] = arm_result.arm
      for _, iss in ipairs(arm_result.issues or {}) do issues[#issues + 1] = iss end
    end
  end
  local default_body = input:typecheck_tree_stmt_body(self.default_body or {})
  if default_body.issues then for _, iss in ipairs(default_body.issues) do issues[#issues + 1] = iss end end
  return LCheck.TypeStmtResult(input, {Tr.StmtSwitch(Tr.StmtFlow(Sem.FlowFallsThrough), vr.expr, arms, variant_arms, default_body.stmts)}, issues)
end
function Tr.StmtAtomicStore:typecheck_tree_stmt(input)
  return LCheck.TypeStmtResult(input, {self}, {})
end
function Tr.StmtAtomicFence:typecheck_tree_stmt(input)
  return LCheck.TypeStmtResult(input, {self}, {})
end
-- Shared region-call wiring validation: wired cont names must exist on the
-- callee protocol, and wired targets must resolve to caller blocks whose
-- params match the supplied args.
local function callee_conts(input, target_path)
  local facts = input.scope.facts
  local protocols = facts and facts.region and facts.region.protocols
  if protocols == nil then return nil end
  local names = {}
  for i = 1, #(target_path.parts or {}) do names[i] = target_path.parts[i].text end
  local target_name = table.concat(names, ".")
  for i = 1, #(protocols.entries or {}) do
    local entry = protocols.entries[i]
    if entry.key.text == target_name then
      local out = {}
      for j = 1, #(entry.protocol.payloads or {}) do
        out[#out + 1] = entry.protocol.payloads[j].cont
      end
      return out
    end
  end
  return nil
end
local function validate_region_wiring(input, target_path, wiring, issues)
  local region_id = input.control:typecheck_control_region_id()
  local conts = callee_conts(input, target_path)
  for i = 1, #(wiring or {}) do
    local w = wiring[i]
    local wire_cont = nil
    if conts ~= nil then
      for j = 1, #conts do
        if conts[j].name == w.name then wire_cont = conts[j] break end
      end
      if wire_cont == nil then
        issues[#issues + 1] = LCheck.TypeIssueRegionContMissing(region_id, w.name)
      end
    end
    if w.target ~= nil and asdl.classof(w.target) == Tr.RegionWireBlock then
      local label = w.target.label
      local payload_params = wire_cont and wire_cont.params or {}
      input.control:typecheck_control_block(label):typecheck_validate_jump(region_id, input.scope, label, w.target.args, issues, payload_params)
    end
  end
end
function Tr.StmtRegionEmit:typecheck_tree_stmt(input)
  -- Region emit: typecheck args, validate wiring
  local issues = {}
  local args = {}
  for i = 1, #(self.args or {}) do
    local ar = self.args[i]:typecheck_tree_expr(LCheck.TypeExprInput(input.scope))
    if ar.ty == nil then return LCheck.TypeStmtResult(input, {self}, ar.issues or {}) end
    if ar.issues then for _, iss in ipairs(ar.issues) do issues[#issues+1]=iss end end
    args[i] = ar.expr
  end
  validate_region_wiring(input, self.target.path, self.wiring or {}, issues)
  return LCheck.TypeStmtResult(input, {Tr.StmtRegionEmit(Tr.StmtFlow(Sem.FlowFallsThrough), self.invoke_id, self.target, args, self.wiring or {})}, issues)
end

function Tr.StmtRegionCall:typecheck_tree_stmt(input)
  -- Region call: typecheck args, validate wiring
  local issues = {}
  local args = {}
  for i = 1, #(self.args or {}) do
    local ar = self.args[i]:typecheck_tree_expr(LCheck.TypeExprInput(input.scope))
    if ar.ty == nil then return LCheck.TypeStmtResult(input, {self}, ar.issues or {}) end
    if ar.issues then for _, iss in ipairs(ar.issues) do issues[#issues+1]=iss end end
    args[i] = ar.expr
  end
  validate_region_wiring(input, self.target.path, self.wiring or {}, issues)
  return LCheck.TypeStmtResult(input, {Tr.StmtRegionCall(Tr.StmtFlow(Sem.FlowFallsThrough), self.invoke_id, self.target, args, self.wiring or {})}, issues)
end

function Tr.StmtJumpCont:typecheck_tree_stmt(input)
  -- JumpCont: continuation jump — validate jump args
  local issues = {}
  local args = {}
  for i = 1, #(self.args or {}) do
    local ja = self.args[i]
    local jar = ja.value:typecheck_tree_expr(LCheck.TypeExprInput(input.scope))
    if jar.ty == nil then return LCheck.TypeStmtResult(input, {self}, jar.issues or {}) end
    if jar.issues then for _, iss in ipairs(jar.issues) do issues[#issues+1]=iss end end
    args[i] = Tr.JumpArg(ja.name, jar.expr)
  end
  local region_id = input.control:typecheck_control_region_id()
  input.control:typecheck_control_cont(self.cont.name):typecheck_validate_cont_jump(region_id, input.scope, self.cont.name, args, issues)
  return LCheck.TypeStmtResult(input, {Tr.StmtJumpCont(Tr.StmtFlow(Sem.FlowJumps), self.cont, args)}, issues)
end
