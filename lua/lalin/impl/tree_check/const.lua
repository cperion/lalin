-- impl/tree_check/const.lua
-- Constant expression evaluation leaf methods.

require("lalin.schema")
local C   = require("lalin.schema.core")
local Ty  = require("lalin.schema.type")
local B   = require("lalin.schema.bind")
local Sem = require("lalin.schema.sem")
local Tr  = require("lalin.schema.tree")

local function known(v) return Sem.ConstKnown(v) end
local function not_foldable(r) return Sem.ConstNotFoldable(r) end

-- === Leaf methods for classof-free pattern matching ===

function Sem.ConstExprResult:sem_const_eval_value() return nil end
function Sem.ConstKnown:sem_const_eval_value() return self.value end

-- ConstValue leaves
function Sem.ConstValue:is_const_int() return false end
function Sem.ConstInt:is_const_int() return true end
function Sem.ConstValue:is_const_float() return false end
function Sem.ConstFloat:is_const_float() return true end
function Sem.ConstValue:is_const_bool() return false end
function Sem.ConstBool:is_const_bool() return true end

-- ConstExprResult
function Sem.ConstExprResult:is_known() return false end
function Sem.ConstKnown:is_known() return true end

-- Literal leaves
function C.Literal:is_lit_int() return false end
function C.LitInt:is_lit_int() return true end
function C.Literal:is_lit_float() return false end
function C.LitFloat:is_lit_float() return true end
function C.Literal:is_lit_bool() return false end
function C.LitBool:is_lit_bool() return true end
function C.Literal:is_lit_nil() return false end
function C.LitNil:is_lit_nil() return true end

-- ValueRef
function B.ValueRef:is_binding_ref() return false end
function B.ValueRefBinding:is_binding_ref() return true end

-- === Binary op helpers ===

local function eval_int_binary(op, a, b)
  local ai, bi = tonumber(a.raw), tonumber(b.raw)
  if not (ai and bi) then return nil end
  local result
  if op == C.BinAdd then result = ai + bi
  elseif op == C.BinSub then result = ai - bi
  elseif op == C.BinMul then result = ai * bi
  elseif op == C.BinDiv then if bi == 0 then return nil end; result = math.floor(ai / bi)
  elseif op == C.BinRem then result = bi ~= 0 and (ai % bi) or nil
  elseif op == C.BinBitAnd then result = bit.band(ai, bi)
  elseif op == C.BinBitOr then result = bit.bor(ai, bi)
  elseif op == C.BinBitXor then result = bit.bxor(ai, bi)
  elseif op == C.BinShl then result = bit.lshift(ai, bi)
  elseif op == C.BinLShr then result = bit.rshift(ai, bi)
  elseif op == C.BinAShr then result = bit.arshift(ai, bi)
  else return nil end
  if result == nil then return nil end
  return known(Sem.ConstInt(a.ty, tostring(result)))
end

local function eval_float_binary(op, a, b)
  local af, bf = tonumber(a.raw), tonumber(b.raw)
  if not (af and bf) then return nil end
  local result
  if op == C.BinAdd then result = af + bf
  elseif op == C.BinSub then result = af - bf
  elseif op == C.BinMul then result = af * bf
  elseif op == C.BinDiv then result = af / bf
  else return nil end
  return known(Sem.ConstFloat(a.ty, tostring(result)))
end

local function eval_binary_op(op, a, b)
  if a:is_const_int() and b:is_const_int() then return eval_int_binary(op, a, b) end
  if a:is_const_float() and b:is_const_float() then return eval_float_binary(op, a, b) end
  return nil
end

local function eval_int_cmp(op, a, b)
  local ai, bi = tonumber(a.raw), tonumber(b.raw)
  if not (ai and bi) then return nil end
  local result
  if op == C.CmpEq then result = ai == bi
  elseif op == C.CmpNe then result = ai ~= bi
  elseif op == C.CmpLt then result = ai < bi
  elseif op == C.CmpLe then result = ai <= bi
  elseif op == C.CmpGt then result = ai > bi
  elseif op == C.CmpGe then result = ai >= bi
  else return nil end
  return known(Sem.ConstBool(result))
end

local function eval_float_cmp(op, a, b)
  local af, bf = tonumber(a.raw), tonumber(b.raw)
  if not (af and bf) then return nil end
  local result
  if op == C.CmpEq then result = af == bf
  elseif op == C.CmpNe then result = af ~= bf
  elseif op == C.CmpLt then result = af < bf
  elseif op == C.CmpLe then result = af <= bf
  elseif op == C.CmpGt then result = af > bf
  elseif op == C.CmpGe then result = af >= bf
  else return nil end
  return known(Sem.ConstBool(result))
end

local function eval_cmp_op(op, a, b)
  if a:is_const_int() and b:is_const_int() then return eval_int_cmp(op, a, b) end
  if a:is_const_float() and b:is_const_float() then return eval_float_cmp(op, a, b) end
  if a:is_const_bool() and b:is_const_bool() then
    if op == C.CmpEq then return known(Sem.ConstBool(a.value == b.value))
    elseif op == C.CmpNe then return known(Sem.ConstBool(a.value ~= b.value)) end
  end
  return nil
end

-- === Expr const evaluation ===

function Tr.Expr:sem_const_eval(input) return not_foldable("not foldable") end

function Tr.ExprLit:sem_const_eval(input)
  local v, ty = self.value, self.h and self.h:tree_code_expr_type()
  if v:is_lit_int() then return known(Sem.ConstInt(ty, v.raw))
  elseif v:is_lit_float() then return known(Sem.ConstFloat(ty, v.raw))
  elseif v:is_lit_bool() then return known(Sem.ConstBool(v.value))
  elseif v:is_lit_nil() then return known(Sem.ConstNil(ty))
  end
  return not_foldable("literal")
end

function Tr.ExprUnary:sem_const_eval(input)
  local vr = self.value:sem_const_eval(input)
  if not vr:is_known() then return vr end
  local v = vr:sem_const_eval_value()
  if self.op == C.UnaryNeg then
    if v:is_const_int() then return known(Sem.ConstInt(v.ty, tostring(-tonumber(v.raw))))
    elseif v:is_const_float() then return known(Sem.ConstFloat(v.ty, tostring(-tonumber(v.raw)))) end
  elseif self.op == C.UnaryNot then
    if v:is_const_bool() then return known(Sem.ConstBool(not v.value)) end
  elseif self.op == C.UnaryBitNot then
    if v:is_const_int() then return known(Sem.ConstInt(v.ty, tostring(bit.bnot(tonumber(v.raw))))) end
  end
  return not_foldable("unary")
end

function Tr.ExprBinary:sem_const_eval(input)
  local lr = self.lhs:sem_const_eval(input); if not lr:is_known() then return lr end
  local rr = self.rhs:sem_const_eval(input); if not rr:is_known() then return rr end
  return eval_binary_op(self.op, lr:sem_const_eval_value(), rr:sem_const_eval_value()) or not_foldable("binary")
end

function Tr.ExprCompare:sem_const_eval(input)
  local lr = self.lhs:sem_const_eval(input); if not lr:is_known() then return lr end
  local rr = self.rhs:sem_const_eval(input); if not rr:is_known() then return rr end
  return eval_cmp_op(self.op, lr:sem_const_eval_value(), rr:sem_const_eval_value()) or not_foldable("compare")
end

function Tr.ExprCast:sem_const_eval(input)
  local vr = self.value:sem_const_eval(input); if not vr:is_known() then return vr end
  return known(vr:sem_const_eval_value())
end

function Tr.ExprRef:sem_const_eval(input)
  if self.ref:is_binding_ref() then
    local binding = self.ref.binding
    for _, e in ipairs(input.local_env.entries or {}) do
      if e.binding == binding then return known(e.value) end
    end
  end
  return not_foldable("ref")
end

function Tr.ExprIf:sem_const_eval(input)
  local cr = self.cond:sem_const_eval(input); if not cr:is_known() then return cr end
  local cv = cr:sem_const_eval_value()
  if cv:is_const_bool() then
    return cv.value and self.then_expr:sem_const_eval(input) or self.else_expr:sem_const_eval(input)
  end
  return not_foldable("if")
end

function Tr.ExprSelect:sem_const_eval(input)
  local cr = self.cond:sem_const_eval(input); if not cr:is_known() then return cr end
  local cv = cr:sem_const_eval_value()
  if cv:is_const_bool() then
    return cv.value and self.then_expr:sem_const_eval(input) or self.else_expr:sem_const_eval(input)
  end
  return not_foldable("select")
end

function Tr.ExprBlock:sem_const_eval(input)
  local lenv = input.local_env
  for _, s in ipairs(self.stmts or {}) do
    local flow = s:sem_const_eval_stmt(lenv); if flow then return flow end
  end
  return self.result:sem_const_eval(Sem.ConstEvalInput(input.const_env, lenv))
end

function Tr.Stmt:sem_const_eval_stmt(lenv) return nil end
function Tr.StmtLet:sem_const_eval_stmt(lenv)
  local vr = self.init:sem_const_eval(Sem.ConstEvalInput(B.ConstEnv({}), lenv))
  if vr:is_known() then
    return Sem.ConstFallsThrough(Sem.ConstLocalEnv({{binding=self.binding, value=vr:sem_const_eval_value()}}))
  end
  return Sem.ConstFallsThrough(lenv)
end
function Tr.StmtReturnValue:sem_const_eval_stmt(lenv)
  local vr = self.value:sem_const_eval(Sem.ConstEvalInput(B.ConstEnv({}), lenv))
  if vr:is_known() then return Sem.ConstReturnValue(lenv, vr:sem_const_eval_value()) end
  return Sem.ConstReturnVoid(lenv)
end
function Tr.StmtReturnVoid:sem_const_eval_stmt(lenv) return Sem.ConstReturnVoid(lenv) end
function Tr.StmtExpr:sem_const_eval_stmt(lenv) return Sem.ConstFallsThrough(lenv) end
function Tr.StmtJump:sem_const_eval_stmt(lenv) return Sem.ConstJump(lenv, self.target.name) end

-- === Top-level API (compat with old ConstEval.value) ===

local M = {
  value = function(expr, const_env, local_env)
    return expr:sem_const_eval(Sem.ConstEvalInput(const_env or B.ConstEnv({}), local_env or Sem.ConstLocalEnv({})))
  end,
  empty_local_env = function() return Sem.ConstLocalEnv({}) end,
}
return M
