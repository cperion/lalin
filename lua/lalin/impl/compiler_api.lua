-- impl/compiler_api.lua
-- Root compiler API. CompilerSession:compile() is the public entry point.

require("lalin.schema_v2")
local Compiler = require("lalin.schema_v2.compiler")
local Lalin     = require("lalin")

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
  -- Parse source → parsed AST
  local decls_result = { pcall(Lalin.loadstring, self.source_text, self.source_name) }
  if not decls_result[1] then
    return Compiler.CompilerArtifactError("parse: " .. tostring(decls_result[2]))
  end
  local decls, doc = table.unpack(decls_result)

  -- Convert parsed AST → LalinTree ASDL
  local T = require("lalin.schema_v2")
  local to_tree = require("lalin.syntax.to_tree")(T)
  local tree_module = to_tree.doc_module(doc, decls)
  if not tree_module then
    return Compiler.CompilerArtifactError("to_tree: failed to convert document")
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
  local lower_ok, code_result = pcall(function() return checked:lower_to_code({}) end)
  if not lower_ok then
    return Compiler.CompilerArtifactError("lower_to_code: " .. tostring(code_result))
  end
  local code_module = code_result.module
  local contracts   = code_result.contracts

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
  local c_unit   = lower_plan:emit_c(code_module)
  local artifact = c_unit:emit_module(code_module, lower_plan)

  return artifact
end

return Compiler
