package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local asdl = require("lalin.asdl")
local Schema = require("lalin.schema_projection")
local T = asdl.context()
Schema(T)

local dsl = require("lalin.dsl")(T)
local Pipeline = require("lalin.frontend_pipeline")(T)
local Layout = require("lalin.layout_resolve")(T)
local ModuleType = require("lalin.tree_module_type")(T)
local TreeToCode = require("lalin.tree_lower")(T)
local CodeType = require("lalin.code_type")(T)

local function unit(name, source)
  return dsl.to_unit(name, dsl.loadstring(source, "@" .. name)())
end

local function lower(name, source)
  local checked = Pipeline.typecheck_module(unit(name, source):syntax(), {})
  local layout_env = T.LalinSem.LayoutEnv(ModuleType.env(checked.module, checked.target).layouts)
  local resolved = Layout.module(checked.module, layout_env, checked.target)
  return TreeToCode.module_result(resolved, {
    module_id = name,
    layout_env = layout_env,
    target = CodeType.default_target({}),
  })
end

local source_a = [=[
return {
  extern. host_a { x [i32] } [i32] { symbol = "host_a" },
  fn. a { x [i32] } [i32] { ret (x + 1) },
  fn. greeting {} [slice [u8]] { ret "hello" },
}
]=]

local source_b = [=[
return {
  extern. host_b { x [f64] } [f64] { symbol = "host_b" },
  fn. b { x [f64] } [f64] { ret (x) },
}
]=]

local function texts(values, field)
  local out = {}
  for i = 1, #values do
    local value = field and values[i][field] or values[i]
    out[i] = value.text or value.name or tostring(value)
  end
  return table.concat(out, "|")
end

local function snapshot(result)
  local module = result.code_module
  local parts = result.parts
  return table.concat({
    texts(module.funcs, "name"),
    texts(module.sigs, "id"),
    texts(module.externs, "name"),
    texts(module.data, "name"),
    texts(parts.registrations.funcs, "func_name"),
    texts(parts.registrations.extern_order, "name"),
    texts(parts.emission.generated_data, "name"),
  }, "\n")
end

local a1 = lower("A", source_a)
local b1 = lower("B", source_b)
local a2 = lower("A", source_a)
local a3 = lower("A", source_a)

assert(texts(a1.code_module.funcs, "name") == "a|greeting")
assert(texts(a1.code_module.sigs, "id") == "codesig_i32_to_i32|codesig_to_slice_u8")
assert(texts(a1.code_module.externs, "name") == "host_a")
assert(texts(a1.code_module.data, "name") == "str_greeting_1")
assert(texts(a1.parts.registrations.funcs, "func_name") == "\0a|\0greeting")
assert(texts(a1.parts.registrations.extern_order, "name") == "host_a")
assert(texts(a1.parts.emission.generated_data, "name") == "str_greeting_1")

assert(texts(b1.code_module.funcs, "name") == "b")
assert(texts(b1.code_module.sigs, "id") == "codesig_f64_to_f64")
assert(texts(b1.code_module.externs, "name") == "host_b")
assert(#b1.code_module.data == 0 and #b1.parts.emission.generated_data == 0)
assert(texts(b1.parts.registrations.funcs, "func_name") == "\0b")

assert(snapshot(a1) == snapshot(a2), "A -> B -> A changed lowering state")
assert(snapshot(a2) == snapshot(a3), "repeated unit changed lowering state")

local partial_result
local original_item_func_lower = T.LalinTree.ItemFunc.lower_tree_item_to_code
function T.LalinTree.ItemFunc:lower_tree_item_to_code(input)
  local result = original_item_func_lower(self, input)
  partial_result = result
  return result
end
local failed = pcall(function()
  lower("Bad", [=[
return {
  extern. bad_host { x [i32] } [i32] { symbol = "bad_host" },
  fn. generated_first {} [slice [u8]] { ret "partial" },
  fn. bad {} [i32] {},
}
]=])
end)
T.LalinTree.ItemFunc.lower_tree_item_to_code = original_item_func_lower
assert(not failed, "partially lowered unit unexpectedly succeeded")
assert(partial_result, "failure occurred before an item transition was produced")
assert(texts(partial_result.accumulation.funcs, "name") == "generated_first")
assert(texts(partial_result.registration.sigs.code_sig_order, "id") == "codesig_i32_to_i32|codesig_to_slice_u8|codesig_to_i32")
assert(texts(partial_result.registration.registrations.funcs, "func_name") == "\0generated_first|\0bad")
assert(texts(partial_result.registration.registrations.extern_order, "name") == "bad_host")
assert(texts(partial_result.emission.generated_data, "name") == "str_generated_first_1")
assert(snapshot(lower("A", source_a)) == snapshot(a1), "failure contaminated following lowering")

print("lalin tree lowering isolation ok")
