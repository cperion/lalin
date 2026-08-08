local asdl = require("asdl")
local spec = require("support.spec")
local method_loader = require("lalin.compiler.method_loader")

local describe, it = spec.describe, spec.it

local function tiny_schema()
  local ctx = asdl.NewContext()
  ctx:Define [[
module Tiny {
  Node = Base(number value)
       | Leaf(number value)
}
]]
  return ctx
end

describe("compiler method loading", function()
  it("exposes the isolated compiler module without loading active compiler code", function()
    local compiler = require("lalin.compiler")
    spec.assert_truthy(compiler.schema, "compiler module returns schema")
    spec.assert_truthy(compiler.load_methods, "compiler module returns method loader")
    spec.assert_equal(compiler.load_methods(), compiler.schema, "method loader returns schema")
    spec.assert_equal(compiler.load_methods(), compiler.schema, "method loader is idempotent")
  end)

  it("loads parent defaults before leaf overrides when modules are ordered that way", function()
    package.preload["test.next.parent_methods"] = function()
      return function(Compiler)
        function Compiler.Tiny.Node:meaning()
          return "parent"
        end
      end
    end
    package.preload["test.next.leaf_methods"] = function()
      return function(Compiler)
        function Compiler.Tiny.Leaf:meaning()
          return "leaf"
        end
      end
    end

    local Tiny = tiny_schema()
    method_loader.load_modules(Tiny, {
      "test.next.parent_methods",
      "test.next.leaf_methods",
    }, {})

    spec.assert_equal(Tiny.Tiny.Base(1):meaning(), "parent", "base keeps parent default")
    spec.assert_equal(Tiny.Tiny.Leaf(2):meaning(), "leaf", "leaf override wins after parent default")
  end)

  it("does not mark a failing method module as loaded", function()
    local loaded = {}
    local failed_once = false
    local loaded_after_retry = false
    package.preload["test.next.failing_then_good"] = function()
      return function(_Compiler)
        if not failed_once then
          failed_once = true
          error("planned loader failure")
        end
        loaded_after_retry = true
      end
    end

    local Tiny = tiny_schema()
    local ok = pcall(function()
      method_loader.load_modules(Tiny, { "test.next.failing_then_good" }, loaded)
    end)
    spec.assert_equal(ok, false, "first load fails")
    spec.assert_nil(loaded["test.next.failing_then_good"], "failed module not marked loaded")

    method_loader.load_modules(Tiny, { "test.next.failing_then_good" }, loaded)
    spec.assert_equal(loaded_after_retry, true, "retry loads module after failure")
    spec.assert_truthy(loaded["test.next.failing_then_good"], "successful retry marks loaded")
  end)

  it("rejects no-op method modules", function()
    package.preload["test.next.noop_module"] = function() return true end
    local ok = pcall(function()
      method_loader.load_modules(tiny_schema(), { "test.next.noop_module" }, {})
    end)
    spec.assert_equal(ok, false, "no-op method module rejected")
  end)
end)
