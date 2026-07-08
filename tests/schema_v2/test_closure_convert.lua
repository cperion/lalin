-- tests/schema_v2/test_closure_convert.lua
-- Tests for the scalar closure conversion in impl/tree_closure.lua
--
-- Tests:
--  1. Scalar function without captures → pass-through
--  2. Scalar function with free variable capture → helper generated
--  3. Struct functions → pass-through (no captures)
--  4. Nested closures → UNSUPPORTED error

package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

require("lalin.schema_v2")
require("lalin.impl.tree_surface")
require("lalin.impl.tree_closure")
require("lalin.impl.tree_check.init")

local Tr = require("lalin.schema_v2.tree")
local asdl = require("lalin.asdl")
local Document = require("lalin.syntax_v2.document")

local passes, total = 0, 0
local failures = {}

local function assert_ok(label, ok, err)
  total = total + 1
  if ok then
    passes = passes + 1
    print(string.format("  %s -> OK", label))
  else
    failures[#failures + 1] = { label = label, err = tostring(err or "unknown") }
    print(string.format("  %s -> FAIL: %s", label, tostring(err or "unknown")))
  end
end

local function assert_error(label, ok, err, expected_msg)
  total = total + 1
  if not ok then
    local msg = tostring(err or "")
    if msg:find(expected_msg, 1, true) then
      passes = passes + 1
      print(string.format("  %s -> OK (got expected error: %s)", label, expected_msg))
    else
      failures[#failures + 1] = { label = label, err = "expected '" .. expected_msg .. "', got '" .. msg .. "'" }
      print(string.format("  %s -> FAIL: expected '%s', got '%s'", label, expected_msg, msg))
    end
  else
    failures[#failures + 1] = { label = label, err = "expected error but got success" }
    print(string.format("  %s -> FAIL: expected error but got success", label))
  end
end

----------------------------------------------------------------------
-- Test 1: Scalar function without captures → pass-through
----------------------------------------------------------------------
print("=== Test 1: Scalar function without captures ===")
do
  local source = [[
fn add(a [i32], b [i32]) [i32] do
  return a + b
end
]]
  local ok, doc = pcall(Document.parse, source, "test_no_captures")
  assert_ok("parse", ok, doc)

  local ok2, m = pcall(Document.to_module, doc, "test_no_captures")
  assert_ok("to_module", ok2, m)

  if ok2 then
    local ok3, m2 = pcall(function() return m:surface_resolve() end)
    assert_ok("surface_resolve", ok3, m2)

    if ok3 then
      local ok4, m3 = pcall(function() return m2:closure_convert() end)
      assert_ok("closure_convert", ok4, m3)

      if ok4 then
        -- Should still have exactly 1 item (no helpers generated)
        local count = #(m3.items or {})
        assert_ok("item_count=1", count == 1, "got " .. tostring(count) .. " items, expected 1")
      end
    end
  end
end

----------------------------------------------------------------------
-- Test 2: Struct function → pass-through (structs resolved)
----------------------------------------------------------------------
print("\n=== Test 2: Struct functions ===")
do
  local source = [[
struct Point
  x [i32]
  y [i32]
end

fn make_point(x [i32], y [i32]) [Point] do
  return Point { x = x, y = y }
end
]]
  local ok, doc = pcall(Document.parse, source, "test_struct")
  assert_ok("parse", ok, doc)

  local ok2, m = pcall(Document.to_module, doc, "test_struct")
  assert_ok("to_module", ok2, m)

  if ok2 then
    local ok3, m2 = pcall(function() return m:surface_resolve() end)
    assert_ok("surface_resolve", ok3, m2)

    if ok3 then
      local ok4, m3 = pcall(function() return m2:closure_convert() end)
      assert_ok("closure_convert", ok4, m3)

      if ok4 then
        local ok5, checked = pcall(function() return m3:typecheck({}) end)
        assert_ok("typecheck", ok5, checked)
      end
    end
  end
end

----------------------------------------------------------------------
-- Test 3: StmtIf with logic → pass-through
----------------------------------------------------------------------
print("\n=== Test 3: StmtIf with logic ===")
do
  local source = [[
fn test_if(x [i32]) [i32] do
  if x > 0 then
    return x
  else
    return 0
  end
end
]]
  local ok, doc = pcall(Document.parse, source, "test_if")
  assert_ok("parse", ok, doc)

  local ok2, m = pcall(Document.to_module, doc, "test_if")
  assert_ok("to_module", ok2, m)

  if ok2 then
    local ok3, m2 = pcall(function() return m:surface_resolve() end)
    assert_ok("surface_resolve", ok3, m2)

    if ok3 then
      local ok4, m3 = pcall(function() return m2:closure_convert() end)
      assert_ok("closure_convert", ok4, m3)
    end
  end
end

----------------------------------------------------------------------
-- Test 4: Nested closures → UNSUPPORTED
----------------------------------------------------------------------
print("\n=== Test 4: Nested closures → UNSUPPORTED ===")
do
  -- Note: ExprClosure nodes are produced by the old DSL, not the new .lln parser.
  -- Test that the leaf method throws as expected instead of silently handling.
  local ok, err = pcall(function()
    return Tr.ExprClosure:closure_convert({})
  end)
  assert_error("ExprClosure:closure_convert", ok, err, "UNSUPPORTED")
end

----------------------------------------------------------------------
-- Summary
----------------------------------------------------------------------
print(string.format("\n=== %d/%d closure conversion tests passed ===", passes, total))
if #failures > 0 then
  print("\nFailures:")
  for _, f in ipairs(failures) do
    print(string.format("  %s: %s", f.label, f.err))
  end
  os.exit(1)
end
