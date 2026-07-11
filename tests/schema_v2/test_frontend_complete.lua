package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local asdl = require("lalin.asdl")

local T = require("lalin.schema_v2")
require("lalin.impl.tree_surface")
require("lalin.impl.tree_closure")
require("lalin.impl.tree_check.init")

local Document = require("lalin.syntax_v2.document")

local function typecheck_source(name, source)
  local ok, doc = pcall(Document.parse, source, name)
  if not ok then return nil, "parse: " .. tostring(doc) end
  local ok2, m = pcall(Document.to_module, doc, name)
  if not ok2 then return nil, "to_module: " .. tostring(m) end
  local ok3, m2 = pcall(function() return m:surface_resolve() end)
  if not ok3 then return nil, "surface_resolve: " .. tostring(m2) end
  local target = T.LalinHost.HostTargetModel(64, 64, T.LalinHost.HostEndianLittle)
  local ok4, m3 = pcall(function() return m2:closure_convert(T.LalinSem.ClosureModuleInput(target)) end)
  if not ok4 then return nil, "closure_convert: " .. tostring(m3) end
  local ok5, checked = pcall(function() return m3.module:typecheck({}) end)
  if not ok5 then return nil, "typecheck: " .. tostring(checked) end
  return checked, nil
end

local function assert_typecheck_ok(name, source)
  local result, err = typecheck_source(name, source)
  if not result then
    error(name .. ": typecheck failed: " .. (err or "nil result"), 2)
  end
  print(string.format("  %s -> typecheck OK (%s)", name, tostring(asdl.classof(result))))
  return result
end

local passes, total = 0, 0

-- ============================================================
-- ExprAgg tests (struct aggregate init, field-level validation)
-- ============================================================
print("=== ExprAgg Tests ===")
total = total + 1; assert_typecheck_ok("agg_basic", [[
struct Point
  x [f64]
  y [f64]
end

fn make_point(x [f64], y [f64]) [Point] do
  return Point { x = x, y = y }
end
]]); passes = passes + 1

total = total + 1; assert_typecheck_ok("agg_nested", [[
struct Inner
  a [i32]
end

struct Outer
  inner [Inner]
  b [i32]
end

fn make_outer(i [Inner], b [i32]) [Outer] do
  return Outer { inner = i, b = b }
end
]]); passes = passes + 1

-- ============================================================
-- Void function (ExprControl, return void)
-- ============================================================
print("\n=== Void Tests ===")
total = total + 1; assert_typecheck_ok("void_fn", [[
fn nothing() [void] do
  return
end
]]); passes = passes + 1

total = total + 1; assert_typecheck_ok("empty_fn", [[
fn empty() [void] do
end
]]); passes = passes + 1

-- ============================================================
-- Conditional expressions (ExprIf, branch type unification)
-- ============================================================
print("\n=== Conditional Tests ===")
total = total + 1; assert_typecheck_ok("conditional_expr", [[
fn max(a [i32], b [i32]) [i32] do
  if a > b then
    return a
  else
    return b
  end
end
]]); passes = passes + 1

-- ============================================================
-- StmtIf with else (StmtIf:typecheck_tree_stmt)
-- ============================================================
print("\n=== StmtIf Tests ===")
total = total + 1; assert_typecheck_ok("stmt_if_else", [[
fn test_if_else(x [i32]) [i32] do
  if x > 0 then
    return 1
  else
    return 0
  end
end
]]); passes = passes + 1

-- ============================================================
-- Chained function calls (ExprCall, arg type validation)
-- ============================================================
print("\n=== Call Chain Tests ===")
total = total + 1; assert_typecheck_ok("call_chain", [[
fn double(x [i32]) [i32] do
  return x + x
end

fn quad(x [i32]) [i32] do
  return double(double(x))
end
]]); passes = passes + 1

-- ============================================================
-- Nested blocks (ExprBlock, StmtIf nesting)
-- ============================================================
print("\n=== Nested Control Tests ===")
total = total + 1; assert_typecheck_ok("nested_if", [[
fn classify(x [i32], y [i32]) [i32] do
  if x > 0 then
    if y > 0 then
      return 1
    else
      return 2
    end
  else
    return 0
  end
end
]]); passes = passes + 1

-- ============================================================
-- Multiple functions in one module (ExprCall cross-func)
-- ============================================================
print("\n=== Multi-func Module Tests ===")
total = total + 1; assert_typecheck_ok("multi_func", [[
fn add(a [i32], b [i32]) [i32] do
  return a + b
end

fn sub(a [i32], b [i32]) [i32] do
  return a - b
end

fn combine(a [i32], b [i32]) [i32] do
  return add(a, b) + sub(a, b)
end
]]); passes = passes + 1

-- ============================================================
-- Various unary / binary expressions
-- ============================================================
print("\n=== Unary/Binary Tests ===")
total = total + 1; assert_typecheck_ok("unary_neg", [[
fn negate(x [i32]) [i32] do
  return -x
end
]]); passes = passes + 1

total = total + 1; assert_typecheck_ok("bool_not", [[
fn invert(b [bool]) [bool] do
  return not b
end
]]); passes = passes + 1

total = total + 1; assert_typecheck_ok("bitwise", [[
fn bitand(a [i32], b [i32]) [i32] do
  return a & b
end
]]); passes = passes + 1

total = total + 1; assert_typecheck_ok("compare_chain", [[
fn is_positive(x [i32]) [bool] do
  return x > 0
end
]]); passes = passes + 1

-- ============================================================
-- Struct with no functions (minimal module)
-- ============================================================
print("\n=== Struct-Only Tests ===")
total = total + 1; assert_typecheck_ok("struct_only", [[
struct Empty
end
]]); passes = passes + 1

print(string.format("\n=== %d/%d frontend_complete tests passed ===", passes, total))
if passes ~= total then os.exit(1) end
