package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local asdl = require("lalin.asdl")

require("lalin.schema_v2")
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
  local ok4, m3 = pcall(function() return m2:closure_convert() end)
  if not ok4 then return nil, "closure_convert: " .. tostring(m3) end
  local ok5, checked = pcall(function() return m3:typecheck({}) end)
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
-- StmtIf tests
-- ============================================================
print("=== StmtIf Tests ===")
total = total + 1; assert_typecheck_ok("stmt_if_basic", [[
fn test_if(x [i32]) [void] do
  if x > 0 then
    return
  end
end
]]); passes = passes + 1

total = total + 1; assert_typecheck_ok("stmt_if_else", [[
fn test_if_else(x [i32]) [void] do
  if x > 0 then
    return
  else
    return
  end
end
]]); passes = passes + 1

total = total + 1; assert_typecheck_ok("stmt_if_nested", [[
fn test_nested_if(x [i32], y [i32]) [i32] do
  if x > 0 then
    if y > 0 then
      return x + y
    end
  end
  return 0
end
]]); passes = passes + 1

-- ============================================================
-- ExprCall tests
-- ============================================================
print("\n=== ExprCall Tests ===")
total = total + 1; assert_typecheck_ok("expr_call_basic", [[
fn add(a [i32], b [i32]) [i32] do
  return a + b
end

fn test_call() [i32] do
  return add(1, 2)
end
]]); passes = passes + 1

total = total + 1; assert_typecheck_ok("expr_call_noop", [[
fn noop() [void] do
end

fn test_noop() [void] do
  noop()
end
]]); passes = passes + 1

total = total + 1; assert_typecheck_ok("expr_call_chain", [[
fn double(x [i32]) [i32] do
  return x + x
end

fn test_chain(x [i32]) [i32] do
  return double(double(x))
end
]]); passes = passes + 1

print(string.format("\n=== %d/%d typecheck tests passed ===", passes, total))
if passes ~= total then os.exit(1) end
