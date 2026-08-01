package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local T = require("lalin.schema_v2")
local Tr, Check, P = T.LalinTree, T.LalinCheck, T.LalinPhase

assert(Tr.StmtVariantSwitchSource, "canonical tree must own parsed variant switches")
assert(Tr.SwitchVariantSourceStmtArm, "canonical tree must own parsed variant arms")
local bind = Tr.VariantBindSource("payload")
local arm = Tr.SwitchVariantSourceStmtArm("Some", { bind }, {})
assert(arm.binds[1] == bind)
assert(not pcall(function() Tr.SwitchVariantSourceStmtArm("Some", { "payload" }, {}) end),
  "parsed variant arm binds must be typed values")
assert(Check.TypeIssueVariantBindCount, "canonical check schema must own bind-count diagnostics")

assert(P.TypeRefAny == nil, "canonical phase schema must not expose an any-type escape hatch")
assert(P.TypeValueId and P.DiagnosticsWorldNone and P.DiagnosticsWorldPresent)
assert(P.PhaseDeterministic and P.PhaseNondeterministic)
assert(P.CompilerCStageInput, "canonical phase schema must retain typed C stage input")
assert(T.LalinProject and T.LalinExec, "project and exec must be real canonical namespaces")

assert(T.LalinLuaJIT == nil, "main-C bootstrap must exclude LuaJIT schema")
assert(T.LalinStencilMachine == nil, "main-C bootstrap must exclude stencil-machine schema")
assert(package.loaded["lalin.schema.luajit"] == nil, "main-C bootstrap must not load old LuaJIT declarations")
assert(package.loaded["lalin.schema_v2.stencil_machine"] == nil, "main-C bootstrap must not load excluded stencil-machine declarations")

local function source(path)
  local f = assert(io.open(path, "rb"))
  local text = f:read("*a")
  f:close()
  return text
end

local init_source = source("lua/lalin/schema_v2/init.lua")
assert(not init_source:match('"stencil_machine"'))
assert(not init_source:match('schema%.luajit'))
local phase_source = source("lua/lalin/schema_v2/phase.lua")
assert(not phase_source:match("TypeRefAny"))
assert(not phase_source:match("optional%s*%["))
assert(not phase_source:match("%[bool%]"))
assert(not phase_source:match('require%("lalin%.schema%.phase"%)'))

for _, path in ipairs {
  "lua/lalin/schema_v2/stencil.lua",
  "lua/lalin/schema_v2/c_materialize.lua",
} do
  local text = source(path)
  assert(not text:match("LalinLuaJIT"), path .. " must be backend-neutral")
  assert(not text:match("LalinStencilMachine"), path .. " must not depend on excluded machine schema")
end

local canonical_impl = source("lua/lalin/compiler_implementation_v2.lua")
for _, forbidden in ipairs {
  "lalin%.tree_typecheck",
  "lalin%.tree_typecheck_stmt",
  "lalin%.tree_typecheck_fact",
  "lalin%.code_kernel_plan",
  "lalin%.lower_to_c",
  "lalin%.compiler_canonical_c_backend",
  "lalin%.schema%.",
} do
  assert(not canonical_impl:match(forbidden), "canonical implementation imports forbidden old code: " .. forbidden)
end
for _, path in ipairs { "lua/lalin/impl/compiler_api.lua", "lua/lalin/pipeline.lua" } do
  local text = source(path)
  assert(not text:match('require%("lalin%.impl%.stencil_machine"%)'), path .. " must not load excluded stencil machine")
end

print("schema_v2 bootstrap boundaries ok")
