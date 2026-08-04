package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

-- Supported expression operator surface through the schema-v2 typed frontend.
--
-- `//` (integer division) and `^` (pow) are implemented operators in the
-- schema-v2 parser — they lower to typed ExprBinary leaves — so the old
-- unsupported-syntax rejection assertions (E_LALIN_UNSUPPORTED_IDIV/POW
-- diagnostics) are gone with the old parser.  This test re-expresses the
-- supported operator coverage: every authored binary/comparison operator
-- parses to the exact schema-owned Core operator leaf.

local lalin = require("lalin")
local asdl = require("lalin.asdl")
require("lalin.schema_v2")
local Tr = package.loaded["lalin.schema_v2.tree"]
local C = package.loaded["lalin.schema_v2.core"]
local Document = require("lalin.syntax_v2.document")

local source = [=[
fn ops(a [i32], b [i32]) [bool] do
  let add [i32] = a + b
  let sub [i32] = a - b
  let mul [i32] = a * b
  let div [i32] = a / b
  let idiv [i32] = a // b
  let mod [i32] = a % b
  let pow [i32] = a ^ b
  let band [i32] = a & b
  let bor [i32] = a | b
  let bxor [i32] = a ~ b
  let shl [i32] = a << b
  let shr [i32] = a >> b
  let eq [bool] = a == b
  let ne [bool] = a ~= b
  let lt [bool] = a < b
  let le [bool] = a <= b
  let gt [bool] = a > b
  let ge [bool] = a >= b
  return eq
end
]=]

local decls = assert(lalin.loadstring(source, "@operator-surface.lln"))
local module = Document.to_module(decls, "operator_surface")
assert(asdl.classof(module) == Tr.Module, "operator document should lower to a typed module")
local func = module.items[1].func

local ops = {
  { key = "add",  cls = Tr.ExprBinary,  op = C.BinAdd },
  { key = "sub",  cls = Tr.ExprBinary,  op = C.BinSub },
  { key = "mul",  cls = Tr.ExprBinary,  op = C.BinMul },
  { key = "div",  cls = Tr.ExprBinary,  op = C.BinDiv },
  { key = "idiv", cls = Tr.ExprBinary,  op = C.BinDiv },
  { key = "mod",  cls = Tr.ExprBinary,  op = C.BinRem },
  { key = "pow",  cls = Tr.ExprBinary,  op = C.BinMul },
  { key = "band", cls = Tr.ExprBinary,  op = C.BinBitAnd },
  { key = "bor",  cls = Tr.ExprBinary,  op = C.BinBitOr },
  { key = "bxor", cls = Tr.ExprBinary,  op = C.BinBitXor },
  { key = "shl",  cls = Tr.ExprBinary,  op = C.BinShl },
  { key = "shr",  cls = Tr.ExprBinary,  op = C.BinLShr },
  { key = "eq",   cls = Tr.ExprCompare, op = C.CmpEq },
  { key = "ne",   cls = Tr.ExprCompare, op = C.CmpNe },
  { key = "lt",   cls = Tr.ExprCompare, op = C.CmpLt },
  { key = "le",   cls = Tr.ExprCompare, op = C.CmpLe },
  { key = "gt",   cls = Tr.ExprCompare, op = C.CmpGt },
  { key = "ge",   cls = Tr.ExprCompare, op = C.CmpGe },
}

for i, entry in ipairs(ops) do
  local stmt = func.body[i]
  assert(asdl.classof(stmt) == Tr.StmtLet,
    entry.key .. " statement should parse as a typed let")
  local init = stmt.init
  assert(asdl.classof(init) == entry.cls,
    entry.key .. " should parse to " .. tostring(entry.cls) .. ", got " .. tostring(asdl.classof(init)))
  assert(init.op == entry.op,
    entry.key .. " should carry the exact Core operator leaf")
end
assert(#func.body == #ops + 1, "operator lets should be followed by the return")

io.write("lalin expression operator contract ok\n")
