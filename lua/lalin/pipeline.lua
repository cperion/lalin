-- pipeline.lua
-- Thin composition: chains phase methods together into the full
-- compilation sequence.  No compiler semantics.  ~30 lines of actual logic.

-- Ensure all methods are installed:
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
require("lalin.impl.code_validate")
require("lalin.impl.compiler_result")
require("lalin.impl.stencil_plan")
require("lalin.impl.stencil_reduction")
require("lalin.impl.stencil_metastencil")
require("lalin.impl.stencil_c")
require("lalin.impl.exec_plan")

local function compile_pipeline(declarations, opts)
  opts = opts or {}

  -- Surface resolution: resolve names, symbols, scopes
  local m = declarations.module:surface_resolve()

  -- Closure conversion: convert nested closures to flat top-level items
  m = m:closure_convert()

  -- Type checking: assign types to every expression, statement, function
  local type_input = opts.type_input or {}
  local checked = m:typecheck(type_input)

  -- Tree → Code lowering: produce CodeModule + contract facts
  local lower_input = opts.lower_input or {}
  local code_result = checked:lower_to_code(lower_input)

  -- Build control-flow graph
  local graph = code_result.module:build_graph()

  -- Flow analysis: compute loop domains, induction variables, trip counts
  local flow = graph:compute_flow(code_result.module)

  -- Value analysis: compute value expressions, affine forms, reductions
  local values = graph:compute_values(code_result.module, flow)

  -- Memory analysis: compute memory objects, accesses, proofs
  local mem = graph:compute_mem(code_result.module, flow, values, code_result.contracts)

  -- Effect analysis: compute side effects, call summaries
  local effects = graph:compute_effects(code_result.module, mem, code_result.contracts)

  -- Kernel planning: identify stencil/copy/reduction candidates
  local kernels = mem:plan_kernels(flow, values, mem, effects)

  -- Schedule planning: assign vector/scalar/fallback schedules to kernels
  local schedules = kernels:plan_schedules(code_result.module, flow, values, mem, effects, opts.target)

  -- Lowering plan: decide fragments, carriers, addresses, cover
  local lower_plan = code_result.module:plan_lowering(graph, kernels, schedules, opts.target)

  -- C emission: produce CBackendUnit from the lower plan
  local c_unit = lower_plan:emit_c(code_result.module)

  -- C text emission: emit final C source/header
  local cemit_machine = opts.cemit_machine
  local artifact = cemit_machine:emit_module(code_result.module, lower_plan)

  return artifact
end

return { compile_pipeline = compile_pipeline }
