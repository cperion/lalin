local M = {}

function M.install_canonical(T)
    local Compiler = T.LalinCompiler

    -- The canonical (v1) registry is retired with the v1 C-lowering surface;
    -- its method bodies now route to the schema-v2 pipeline modules so the
    -- legacy registry consumer stays on the schema-v2 implementation.
    function Compiler.CompilerImplementationOwner:compiler_implementation_registry()
        return Compiler.CompilerImplementationRegistry(Compiler.TreeCodeCanonicalImplementation)
    end

    function Compiler.TreeCodeCanonicalImplementation:implementation_module_name()
        return "lalin.impl.tree_code"
    end

    function Compiler.TreeCodeCanonicalImplementation:surface_resolve(module)
        require("lalin.impl.tree_surface")
        return module:surface_resolve()
    end

    function Compiler.TreeCodeCanonicalImplementation:closure_convert(module, input)
        require("lalin.impl.tree_closure")
        return module:closure_convert(input)
    end

    function Compiler.TreeCodeCanonicalImplementation:typecheck_module(module, input)
        require("lalin.impl.tree_check")
        return module:typecheck(input)
    end

    function Compiler.TreeCodeCanonicalImplementation:module_result(module, opts)
        require("lalin.impl.tree_code")
        return module:lower_tree_module_result_to_code(opts)
    end

    function Compiler.TreeCodeCanonicalImplementation:code_validation_issues(module, collector)
        require("lalin.impl.code_validate")
        return require("lalin.impl.code_validate").validate(module):compiler_code_issues()
    end

    function Compiler.TreeCodeCanonicalImplementation:code_result_to_c(code_result, opts)
        return require("lalin.compiler_schema_v2_c_backend").code_result_to_c(code_result, opts)
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

    function Compiler.TreeCodeSchemaV2Implementation:closure_convert(module, input)
        require("lalin.impl.tree_check.module")
        require("lalin.impl.tree_closure")
        return module:closure_convert(input)
    end

    function Compiler.TreeCodeSchemaV2Implementation:typecheck_module(module, input)
        require("lalin.impl.tree_check")
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
