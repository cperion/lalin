local asdl = require("asdl")
local List = require("terralist")

local T = asdl.NewContext()

T:Define [[
module Example {
  Real = (number mantissa, number exp)

  Expr = Id(string name)
       | Num(number value)
       | Op(Expr lhs, BinOp op, Expr rhs)

  BinOp = Plus | Minus

  Item = One(number value) unique
       | Many(number* values) unique
}
 ]]

function T.Example.Expr:family_name()
  return "Expr"
end

function T.Example.Id:evaluate(environment)
  return environment[self.name]
end

function T.Example.Num:evaluate(_environment)
  return self.value
end

function T.Example.Op:evaluate(environment)
  local lhs = self.lhs:evaluate(environment)
  local rhs = self.rhs:evaluate(environment)
  if self.op.kind == "Plus" then return lhs + rhs end
  return lhs - rhs
end

local expression = T.Example.Op(
  T.Example.Id("x"),
  T.Example.Plus,
  T.Example.Num(2))

assert(expression:evaluate({ x = 3 }) == 5)
assert(expression:family_name() == "Expr")
assert(T.Example.Expr:isclassof(expression))
assert(T.Example.BinOp:isclassof(T.Example.Plus))
assert(T.Example.One(4) == T.Example.One(4))
assert(T.Example.Many(List { 1, 2 }) == T.Example.Many(List { 1, 2 }))

print("ASDL runtime: ok")
