local M = {}

function M.install_canonical(T)
    local Compiler = T.LalinCompiler

    function Compiler.CompilerImplementationOwner:compiler_implementation_registry()
        return Compiler.CompilerImplementationRegistry(Compiler.TreeCodeCanonicalImplementation)
    end

    function Compiler.TreeCodeCanonicalImplementation:implementation_module_name()
        return "lalin.tree_lower"
    end

    function Compiler.TreeCodeCanonicalImplementation:surface_resolve(module)
        return require("lalin.surface_resolve")(T).module(module)
    end

    function Compiler.TreeCodeCanonicalImplementation:closure_convert(module)
        return require("lalin.closure_convert")(T).module(module)
    end

    function Compiler.TreeCodeCanonicalImplementation:typecheck_module(module, input)
        return require("lalin.tree_typecheck")(T).check_module(module, input)
    end

    function Compiler.TreeCodeCanonicalImplementation:module_result(module, opts)
        return require("lalin.tree_lower")(T).module_result(module, opts)
    end

    function Compiler.TreeCodeCanonicalImplementation:code_validation_issues(module, collector)
        return require("lalin.code_validate")(T).validate(module, collector).issues
    end

    function Compiler.TreeCodeCanonicalImplementation:code_result_to_c(code_result, opts)
        return require("lalin.compiler_canonical_c_backend")(T).code_result_to_c(code_result, opts)
    end
end

function M.install_schema_v2(T)
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

    function Compiler.TreeCodeSchemaV2Implementation:closure_convert(module)
        require("lalin.impl.tree_check.module")
        require("lalin.impl.tree_closure")
        return module:closure_convert()
    end

    function Compiler.TreeCodeSchemaV2Implementation:typecheck_module(module, input)
        require("lalin.impl.tree_check.init")
        local checked_module = module:typecheck(input)
        return T.LalinCheck.TypeModuleResult(checked_module, {}, input.target)
    end

    function Compiler.TreeCodeSchemaV2Implementation:module_result(module, opts)
        require("lalin.impl.tree_code")
        return module:lower_tree_module_result_to_code(opts)
    end

    local CodeValidation = T.LalinCodeValidation
    function CodeValidation.CodeValidateOk:compiler_code_issues() return {} end
    function CodeValidation.CodeValidateFailed:compiler_code_issues() return self.issues end

    function Compiler.TreeCodeSchemaV2Implementation:code_validation_issues(module)
        return require("lalin.impl.code_validate").validate(module):compiler_code_issues()
    end

    function Compiler.TreeCodeSchemaV2Implementation:code_result_to_c(code_result, opts)
        return require("lalin.compiler_schema_v2_c_backend").code_result_to_c(code_result, opts)
    end
end

return M
