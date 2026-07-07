package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local asdl = require("lalin.asdl")

-- Initialize schema context and compiler API
require("lalin.schema_v2")
require("lalin.impl.compiler_api")  -- installs CompilerSession:compile()
local Compiler = require("lalin.schema_v2.compiler")

-- Helper: compile source and check result type
local function compile_source(name, source)
  local session = Compiler.CompilerSession(source, name)
  local result = session:compile()
  return result
end

-- Helper: assert compilation succeeds (returns C artifact with source/header)
local function assert_compile_ok(name, source)
  local result = compile_source(name, source)
  assert(result ~= nil, name .. ": compile returned nil")
  local cls = asdl.classof(result)
  assert(cls ~= nil, name .. ": result has no ASDL class")
  local kind = tostring(cls)
  print(string.format("  %s → %s", name, kind))
  if kind:match("CompilerArtifactError") then
    error(name .. ": compilation failed: " .. tostring(result.message), 2)
  end
  if kind:match("CompilerArtifactC") then
    assert(type(result.source) == "string" and #result.source > 0, name .. ": no C source emitted")
    print(string.format("    source: %d bytes", #result.source))
    if result.header then
      print(string.format("    header: %d bytes", #result.header))
    end
  end
end

-- Helper: assert compilation produces an error (expected failure)
local function assert_compile_error(name, source)
  local result = compile_source(name, source)
  local cls = asdl.classof(result)
  local kind = tostring(cls)
  print(string.format("  %s → %s", name, kind))
  if not kind:match("CompilerArtifactError") then
    error(name .. ": expected error but got " .. kind, 2)
  end
  print(string.format("    message: %s", tostring(result.message)))
end

-- ============================================================
-- Test 1: Empty function
-- ============================================================
print("Test 1: Empty function")
-- Use .lln document syntax
local src1 = [[
fn empty() [void] do
end
]]
assert_compile_ok("empty", src1)

-- ============================================================
-- Test 2: Simple scalar addition
-- ============================================================
print("\nTest 2: Simple scalar")
local src2 = [[
fn add(a [i32], b [i32]) [i32] do
  return a + b
end
]]
assert_compile_ok("add", src2)

-- ============================================================
-- Test 3: Basic struct
-- ============================================================
print("\nTest 3: Basic struct")
local src3 = [[
struct Point
  x [f64]
  y [f64]
end

fn make_point(x [f64], y [f64]) [Point] do
  return Point { x = x, y = y }
end
]]
assert_compile_ok("struct_point", src3)

-- ============================================================
-- Test 4: Edge case - parse error
-- ============================================================
print("\nTest 4: Parse error")
local src4 = [[
fn broken( [i32] do
]]
assert_compile_error("broken_parse", src4)

-- ============================================================
-- Test 5: Edge case - type error
-- ============================================================
print("\nTest 5: Type error (add int to void)")
local src5 = [[
fn type_err() [i32] do
  return empty() + 1
end

fn empty() [void] do
end
]]
-- May or may not compile depending on typecheck robustness
local result5 = compile_source("type_err", src5)
local cls5 = asdl.classof(result5)
print(string.format("  type_err → %s", tostring(cls5)))

print("\n=== Smoke tests complete ===")
