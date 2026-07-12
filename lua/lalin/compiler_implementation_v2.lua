local M = {}

function M.install(T)
  local Compiler = T.LalinCompiler

  function Compiler.CompilerImplementationOwner:compiler_implementation_registry()
    return Compiler.CompilerImplementationRegistry(Compiler.TreeCodeSchemaV2Implementation)
  end

  function Compiler.TreeCodeSchemaV2Implementation:implementation_module_name()
    return "lalin.impl.tree_code"
  end

  function Compiler.TreeCodeSchemaV2Implementation:surface_resolve(module)
    require("lalin.impl.tree_surface")
    return module:surface_resolve()
  end

  function Compiler.TreeCodeSchemaV2Implementation:closure_convert(module, input)
    require("lalin.impl.tree_check.module")
    require("lalin.impl.tree_closure")
    return module:closure_convert(input)
  end

  function Compiler.TreeCodeSchemaV2Implementation:typecheck_module(module, input)
    require("lalin.impl.tree_check.init")
    require("lalin.impl.tree_region")
    local checked_module = module:typecheck(input)
    local facts = checked_module:region_fact_projection()
    local expansion = checked_module:region_expand(T.LalinTree.RegionModuleExpansionInput(facts))
    return T.LalinCheck.TypeModuleResult(expansion:region_module(), expansion:region_issues(), input.target)
  end

  function Compiler.TreeCodeSchemaV2Implementation:module_result(module, input)
    require("lalin.impl.tree_code")
    return module:lower_tree_module_result_to_code(input)
  end

  local CodeValidation = T.LalinCodeValidation
  function CodeValidation.CodeValidateOk:compiler_code_issues() return {} end
  function CodeValidation.CodeValidateFailed:compiler_code_issues() return self.issues end

  function Compiler.TreeCodeSchemaV2Implementation:code_validation_issues(module)
    return require("lalin.impl.code_validate").validate(module):compiler_code_issues()
  end

  function Compiler.TreeCodeSchemaV2Implementation:code_result_to_c(request)
    return require("lalin.compiler_schema_v2_c_backend").code_result_to_c(request)
  end
end

return M
