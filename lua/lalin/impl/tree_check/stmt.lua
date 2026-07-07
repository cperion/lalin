-- impl/tree_check/stmt.lua
-- Statement typechecking leaf methods.

require("lalin.schema_v2")
local Tr     = require("lalin.schema_v2.tree")
local Ty     = require("lalin.schema_v2.type")
local C      = require("lalin.schema_v2.core")
local LCheck = require("lalin.schema_v2.check")
local Sem    = require("lalin.schema_v2.sem")

function Tr.Stmt:typecheck_tree_stmt(input) return LCheck.TypeStmtResult({self}, input.scope, {}) end
function Tr.StmtLet:typecheck_tree_stmt(input)
  local er = self.init:typecheck_tree_expr(LCheck.TypeExprInput(input.scope))
  if er.ty == nil then return LCheck.TypeStmtResult(nil, input.scope, er.issues) end
  local scope = input.scope:typecheck_tree_add_value(self.binding.name, er.ty, self.binding)
  return LCheck.TypeStmtResult({Tr.StmtLet(Tr.StmtFlow(), self.binding, er.expr)}, scope, {})
end
function Tr.StmtVar:typecheck_tree_stmt(input)
  local er = self.init:typecheck_tree_expr(LCheck.TypeExprInput(input.scope))
  if er.ty == nil then return LCheck.TypeStmtResult(nil, input.scope, er.issues) end
  local scope = input.scope:typecheck_tree_add_value(self.binding.name, er.ty, self.binding)
  return LCheck.TypeStmtResult({Tr.StmtVar(Tr.StmtFlow(), self.binding, er.expr)}, scope, {})
end
function Tr.StmtSet:typecheck_tree_stmt(input)
  local pr = self.place:typecheck_tree_place(LCheck.TypePlaceInput(input.scope))
  local vr = self.value:typecheck_tree_expr(LCheck.TypeExprInput(input.scope))
  if vr.ty == nil then return LCheck.TypeStmtResult(nil, input.scope, vr.issues) end
  return LCheck.TypeStmtResult({Tr.StmtSet(Tr.StmtFlow(), pr.place, vr.expr)}, input.scope, {})
end
function Tr.StmtExpr:typecheck_tree_stmt(input)
  local er = self.expr:typecheck_tree_expr(LCheck.TypeExprInput(input.scope))
  if er.ty == nil then return LCheck.TypeStmtResult(nil, input.scope, er.issues) end
  return LCheck.TypeStmtResult({Tr.StmtExpr(Tr.StmtFlow(), er.expr)}, input.scope, {})
end
function Tr.StmtAssert:typecheck_tree_stmt(input)
  local cr = self.cond:typecheck_tree_expr(LCheck.TypeExprInput(input.scope))
  if cr.ty == nil then return LCheck.TypeStmtResult(nil, input.scope, cr.issues) end
  return LCheck.TypeStmtResult({Tr.StmtAssert(Tr.StmtFlow(), cr.expr)}, input.scope, {})
end
function Tr.StmtReturnValue:typecheck_tree_stmt(input)
  local vr = self.value:typecheck_tree_expr(LCheck.TypeExprInput(input.scope))
  if vr.ty == nil then return LCheck.TypeStmtResult(nil, input.scope, vr.issues) end
  return LCheck.TypeStmtResult({Tr.StmtReturnValue(Tr.StmtFlow(Sem.FlowReturns), vr.expr)}, input.scope, {})
end
function Tr.StmtReturnVoid:typecheck_tree_stmt(input)
  return LCheck.TypeStmtResult({Tr.StmtReturnVoid(Tr.StmtFlow(Sem.FlowReturns))}, input.scope, {})
end
function Tr.StmtYieldValue:typecheck_tree_stmt(input)
  local vr = self.value:typecheck_tree_expr(LCheck.TypeExprInput(input.scope))
  if vr.ty == nil then return LCheck.TypeStmtResult(nil, input.scope, vr.issues) end
  return LCheck.TypeStmtResult({Tr.StmtYieldValue(Tr.StmtFlow(Sem.FlowYields), vr.expr)}, input.scope, {})
end
function Tr.StmtYieldVoid:typecheck_tree_stmt(input)
  return LCheck.TypeStmtResult({Tr.StmtYieldVoid(Tr.StmtFlow(Sem.FlowYields))}, input.scope, {})
end
function Tr.StmtJump:typecheck_tree_stmt(input)
  return LCheck.TypeStmtResult({Tr.StmtJump(Tr.StmtFlow(Sem.FlowJumps), self.target, self.args)}, input.scope, {})
end
function Tr.StmtControl:typecheck_tree_stmt(input)
  return LCheck.TypeStmtResult({Tr.StmtControl(Tr.StmtFlow(), self.region)}, input.scope, {})
end
function Tr.StmtTrap:typecheck_tree_stmt(input)
  return LCheck.TypeStmtResult({Tr.StmtTrap(Tr.StmtFlow(Sem.FlowTerminates))}, input.scope, {})
end
function Tr.StmtSwitch:typecheck_tree_stmt(input)
  local vr = self.value:typecheck_tree_expr(LCheck.TypeExprInput(input.scope))
  if vr.ty == nil then return LCheck.TypeStmtResult(nil, input.scope, vr.issues) end
  return LCheck.TypeStmtResult({self}, input.scope, {})
end
function Tr.StmtAtomicStore:typecheck_tree_stmt(input)
  return LCheck.TypeStmtResult({self}, input.scope, {})
end
function Tr.StmtAtomicFence:typecheck_tree_stmt(input)
  return LCheck.TypeStmtResult({self}, input.scope, {})
end
function Tr.StmtRegionEmit:typecheck_tree_stmt(input) return LCheck.TypeStmtResult({self}, input.scope, {}) end
function Tr.StmtRegionCall:typecheck_tree_stmt(input) return LCheck.TypeStmtResult({self}, input.scope, {}) end
function Tr.StmtJumpCont:typecheck_tree_stmt(input) return LCheck.TypeStmtResult({self}, input.scope, {}) end
