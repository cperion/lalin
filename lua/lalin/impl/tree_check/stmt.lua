-- impl/tree_check/stmt.lua
-- Statement typechecking leaf methods.

require("lalin.schema_v2")
local Tr     = require("lalin.schema_v2.tree")
local Ty     = require("lalin.schema_v2.type")
local C      = require("lalin.schema_v2.core")
local LCheck = require("lalin.schema_v2.check")
local Sem    = require("lalin.schema_v2.sem")

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
  local er = self.init:typecheck_tree_expr(LCheck.TypeExprInput(input.scope))
  if is_error_result(er) then return LCheck.TypeStmtResult(input, {self}, er.issues) end
  local scope = input.scope:typecheck_tree_add_value(self.binding.name, er.ty, self.binding)
  return LCheck.TypeStmtResult(LCheck.TypeStmtInput(scope, input.return_ty, input.yield), {Tr.StmtLet(Tr.StmtFlow(Sem.FlowFallsThrough), self.binding, er.expr)}, {})
end
function Tr.StmtVar:typecheck_tree_stmt(input)
  local er = self.init:typecheck_tree_expr(LCheck.TypeExprInput(input.scope))
  if is_error_result(er) then return LCheck.TypeStmtResult(input, {self}, er.issues) end
  local scope = input.scope:typecheck_tree_add_value(self.binding.name, er.ty, self.binding)
  return LCheck.TypeStmtResult(LCheck.TypeStmtInput(scope, input.return_ty, input.yield), {Tr.StmtVar(Tr.StmtFlow(Sem.FlowFallsThrough), self.binding, er.expr)}, {})
end
function Tr.StmtSet:typecheck_tree_stmt(input)
  local pr = self.place:typecheck_tree_place(LCheck.TypePlaceInput(input.scope))
  local vr = self.value:typecheck_tree_expr(LCheck.TypeExprInput(input.scope))
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
  local vr = self.value:typecheck_tree_expr(LCheck.TypeExprInput(input.scope))
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
  return LCheck.TypeStmtResult(input, {Tr.StmtJump(Tr.StmtFlow(Sem.FlowJumps), self.target, self.args)}, {})
end
function Tr.StmtControl:typecheck_tree_stmt(input)
  return LCheck.TypeStmtResult(input, {Tr.StmtControl(Tr.StmtFlow(Sem.FlowFallsThrough), self.region)}, {})
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
      scope = scope:typecheck_tree_add_value(bnd.name, bnd.ty)
    end
    local arm_input = LCheck.TypeStmtInput(scope, input.return_ty, input.yield)
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
function Tr.StmtAtomicStore:typecheck_tree_stmt(input)
  return LCheck.TypeStmtResult(input, {self}, {})
end
function Tr.StmtAtomicFence:typecheck_tree_stmt(input)
  return LCheck.TypeStmtResult(input, {self}, {})
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
  -- Validate wiring targets (wires point to block labels within the region)
  local wiring = self.wiring or {}
  for i = 1, #(self.wiring or {}) do
    local w = self.wiring[i]
    if w.target then
      -- Wire target validation: check args if present
      if w.target.args then
        for j = 1, #(w.target.args or {}) do
          local ja = w.target.args[j]
          local jar = ja.value:typecheck_tree_expr(LCheck.TypeExprInput(input.scope))
          if jar.issues then for _, iss in ipairs(jar.issues) do issues[#issues+1]=iss end end
        end
      end
    end
  end
  return LCheck.TypeStmtResult(input, {Tr.StmtRegionEmit(Tr.StmtFlow(Sem.FlowFallsThrough), self.invoke_id, self.target, args, wiring)}, issues)
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
  -- Validate wiring targets
  local wiring = self.wiring or {}
  for i = 1, #(self.wiring or {}) do
    local w = self.wiring[i]
    if w.target then
      if w.target.args then
        for j = 1, #(w.target.args or {}) do
          local ja = w.target.args[j]
          local jar = ja.value:typecheck_tree_expr(LCheck.TypeExprInput(input.scope))
          if jar.issues then for _, iss in ipairs(jar.issues) do issues[#issues+1]=iss end end
        end
      end
    end
  end
  return LCheck.TypeStmtResult(input, {Tr.StmtRegionCall(Tr.StmtFlow(Sem.FlowFallsThrough), self.invoke_id, self.target, args, wiring)}, issues)
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
  return LCheck.TypeStmtResult(input, {Tr.StmtJumpCont(Tr.StmtFlow(Sem.FlowJumps), self.cont, args)}, issues)
end
