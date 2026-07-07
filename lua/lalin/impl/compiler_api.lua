-- impl/compiler_api.lua
-- Root compiler API. CompilerSession:compile() is the public entry point.

require("lalin.schema_v2")
local Compiler = require("lalin.schema_v2.compiler")

-- Ensure all phase methods are installed
require("lalin.impl.tree_surface")
require("lalin.impl.tree_closure")
require("lalin.impl.tree_check.init")
require("lalin.impl.tree_code")
require("lalin.impl.code_graph")
require("lalin.impl.code_flow")
require("lalin.impl.code_value")
require("lalin.impl.code_mem")
require("lalin.impl.code_effect")
require("lalin.impl.kernel_plan")
require("lalin.impl.schedule_plan")
require("lalin.impl.lower_plan")
require("lalin.impl.lower_emit_c")
require("lalin.impl.cemit_emit")
require("lalin.impl.stencil_plan")
require("lalin.impl.stencil_reduction")
require("lalin.impl.stencil_machine")
require("lalin.impl.stencil_metastencil")
require("lalin.impl.stencil_c")
require("lalin.impl.exec_plan")

function Compiler.CompilerSession:compile()
  -- Parse source → LalinTree Module
  local Document = require("lalin.syntax_v2.document")
  local parse_ok, doc = pcall(Document.parse, self.source_text, self.source_name)
  if not parse_ok then
    return Compiler.CompilerArtifactError("parse: " .. tostring(doc))
  end

  local module_ok, tree_module = pcall(Document.to_module, doc, self.source_name)
  if not module_ok then
    return Compiler.CompilerArtifactError("to_module: " .. tostring(tree_module))
  end

  -- Phase 1: Surface resolve
  local surface_ok, m = pcall(function() return tree_module:surface_resolve() end)
  if not surface_ok then
    return Compiler.CompilerArtifactError("surface_resolve: " .. tostring(m))
  end

  -- Phase 2: Closure convert
  local cc_ok, m2 = pcall(function() return m:closure_convert() end)
  if not cc_ok then
    return Compiler.CompilerArtifactError("closure_convert: " .. tostring(m2))
  end
  m = m2

  -- Phase 3: Typecheck
  local check_ok, checked = pcall(function() return m:typecheck({}) end)
  if not check_ok then
    return Compiler.CompilerArtifactError("typecheck: " .. tostring(checked))
  end

  -- Phase 4: Lower to code
  local T = require("lalin.schema_v2")
  local backend_target = require("lalin.backend_target_model")(T)
  local back_target = backend_target.default_native()
  local host_target = backend_target.host_target(back_target)
  local lower_ok, code_module, contracts = pcall(function()
    return checked:lower_tree_module_with_contracts_to_code({ target = host_target })
  end)
  if not lower_ok then
    return Compiler.CompilerArtifactError("lower_to_code: " .. tostring(code_module))
  end
  if contracts == nil then contracts = {} end

  -- Code validation gate
  local validate_mod = require("lalin.impl.code_validate")
  local validate_ok, validate_result = pcall(function()
    return validate_mod.validate(code_module)
  end)
  if not validate_ok then
    return Compiler.CompilerArtifactError("code_validate crashed: " .. tostring(validate_result))
  end
  -- validate_result is CodeValidateOk or CodeValidateFailed
  local CodeValidation_mod = require("lalin.schema_v2.code_validation")
  local asdl = require("lalin.asdl")
  if asdl.classof(validate_result) ~= CodeValidation_mod.CodeValidateOk then
    local issues = validate_result.issues or {}
    local msgs = {}
    for i = 1, #issues do msgs[#msgs+1] = tostring(issues[i]) end
    return Compiler.CompilerArtifactError("code_validate: " .. #msgs .. " issue(s): " .. table.concat(msgs, "; "))
  end


  -- Phase 5: Build CFG
  local graph_ok, graph = pcall(function() return code_module:build_graph() end)
  if not graph_ok then
    return Compiler.CompilerArtifactError("build_graph: " .. tostring(graph))
  end

  -- Phase 6: Facts
  local flow    = graph:compute_flow(code_module)
  local values  = graph:compute_values(code_module, flow)
  local mem     = graph:compute_mem(code_module, flow, values, contracts)
  local effects = graph:compute_effects(code_module, mem, contracts)

  -- Phase 7: Plans
  local kernels   = mem:plan_kernels(flow, values, mem, effects)
  local schedules = kernels:plan_schedules(code_module, flow, values, mem, effects)
  local lower_plan = code_module:plan_lowering(graph, kernels, schedules)

  -- Phase 8: Emit C
  local c_unit = lower_plan:emit_c(code_module)

  -- Phase 9: CEmit - convert to source/header text
  local Cemit = require("lalin.schema_v2.cemit")
  local C_schema = require("lalin.schema_v2.c")
  local Lower_schema = require("lalin.schema_v2.lower")
  local Graph_schema = require("lalin.schema_v2.graph")

  -- Create a spine for CEmitMachine
  local target = C_schema.CBackendTarget(
    C_schema.CBackendC99,
    C_schema.CBackendHostedNative,
    64, 64,
    C_schema.CBackendLittleEndian,
    true
  )
  local spine = Lower_schema.LowerBackSpine(
    code_module,
    graph,
    target
  )
  local cemit_machine = Cemit.CEmitMachine(spine, {}, {}, {}, {})
  local artifact = cemit_machine:emit_module(code_module, lower_plan)

  -- Package as CompilerArtifact
  local Compiler = require("lalin.schema_v2.compiler")
  return Compiler.CompilerArtifactC(artifact.source, artifact.header)
end

return Compiler
