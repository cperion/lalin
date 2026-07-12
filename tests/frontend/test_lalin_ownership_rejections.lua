package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local lalin = require("lalin")
local asdl = require("lalin.asdl")

local T = require("lalin.schema_v2")
require("lalin.impl.tree_check.init")
local Check = T.LalinCheck

local function check(src, name)
  local decls = assert(lalin.loadstring(src, "@" .. name .. ".lln"))
  local module = lalin.syntax.to_module(decls, name, T)
  return require("lalin.frontend_pipeline")(T).typecheck_module(module, {})
end

local function assert_exact_reason(src, name, expected_reason)
  local checked = check(src, name)
  local found = {}
  for i = 1, #checked.issues do
    local issue = checked.issues[i]
    if asdl.classof(issue) == Check.TypeIssueInvalidUnary then
      local reason = issue.reason
      if reason == Check.TypeUnaryLeaseEscapeReturn
        or reason == Check.TypeUnaryLeaseEscapeStore
        or reason == Check.TypeUnaryLeaseEscapeAggregate
        or reason == Check.TypeUnaryLeaseEscapeCall
        or reason == Check.TypeUnaryLeaseEscapeDurable
        or reason == Check.TypeUnaryLeaseInvalidatingCall
      then
        found[#found + 1] = reason
      end
    end
  end
  assert(#found == 1, name .. " must produce exactly one ownership rejection leaf, got " .. tostring(#found))
  assert(found[1] == expected_reason, name .. " produced the wrong ownership rejection leaf")
end

assert_exact_reason([=[
fn bad_return(store [ptr [i32]], borrowed [lease("store", ptr [i32])]) [ptr [i32]] do
  return borrowed
end
]=], "ownership_return", Check.TypeUnaryLeaseEscapeReturn)

assert_exact_reason([=[
fn bad_store(slot [ptr [ptr [i32]]], borrowed [lease("slot", ptr [i32])]) [i32] do
  slot[0] = borrowed
  return 0
end
]=], "ownership_store", Check.TypeUnaryLeaseEscapeStore)

assert_exact_reason([=[
struct PointerBox
  value [ptr [i32]]
end
fn bad_aggregate(store [ptr [i32]], borrowed [lease("store", ptr [i32])]) [i32] do
  let box [PointerBox] = PointerBox { value = borrowed }
  return 0
end
]=], "ownership_aggregate", Check.TypeUnaryLeaseEscapeAggregate)

assert_exact_reason([=[
fn retain(value [ptr [i32]]) [i32] do
  return value[0]
end
fn bad_call(store [ptr [i32]], borrowed [lease("store", ptr [i32])]) [i32] do
  return retain(borrowed)
end
]=], "ownership_call", Check.TypeUnaryLeaseEscapeCall)

assert_exact_reason([=[
struct DurableLease
  value [lease("store", ptr [i32])]
end
fn durable_marker() [i32] do
  return 0
end
]=], "ownership_durable", Check.TypeUnaryLeaseEscapeDurable)

assert_exact_reason([=[
fn mutate(store [ptr [i32]]) [i32] do
  store[0] = store[0] + 1
  return store[0]
end
fn bad_invalidation(store [ptr [i32]], borrowed [lease("store", ptr [i32])]) [i32] do
  return mutate(store) + borrowed[0]
end
]=], "ownership_invalidating_call", Check.TypeUnaryLeaseInvalidatingCall)

io.write("lalin ownership rejections ok\n")

