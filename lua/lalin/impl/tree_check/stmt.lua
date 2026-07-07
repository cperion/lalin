-- impl/tree_check/stmt.lua
-- Statement typechecking leaf methods.

require("lalin.schema_v2")
local Tr     = require("lalin.schema_v2.tree")
local Ty     = require("lalin.schema_v2.type")
local C      = require("lalin.schema_v2.core")
local LCheck = require("lalin.schema_v2.check")
local Sem    = require("lalin.schema_v2.sem")

function Tr.Stmt:typecheck_tree_stmt(input) return LCheck.TypeStmtResult(input, {self}, {}) end

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
function Tr.StmtSwitch:typecheck_tree_stmt(input)
  local vr = self.value:typecheck_tree_expr(LCheck.TypeExprInput(input.scope))
  if is_error_result(vr) then return LCheck.TypeStmtResult(input, {self}, vr.issues) end
  return LCheck.TypeStmtResult(input, {self}, {})
end
function Tr.StmtAtomicStore:typecheck_tree_stmt(input)
  return LCheck.TypeStmtResult(input, {self}, {})
end
function Tr.StmtAtomicFence:typecheck_tree_stmt(input)
  return LCheck.TypeStmtResult(input, {self}, {})
end
function Tr.StmtRegionEmit:typecheck_tree_stmt(input) return LCheck.TypeStmtResult(input, {self}, {}) end
function Tr.StmtRegionCall:typecheck_tree_stmt(input) return LCheck.TypeStmtResult(input, {self}, {}) end
function Tr.StmtJumpCont:typecheck_tree_stmt(input) return LCheck.TypeStmtResult(input, {self}, {}) end
