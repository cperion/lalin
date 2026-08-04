package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local asdl = require("lalin.asdl")
local lalin = require("lalin")
local Abi = require("lalin.compiler_abi")

local session = lalin.use { scope = "env" }

local src = [[
return unit. CodeResultSmoke {
    fn. add
        { a [i32], b [i32] }
        [i32]
        {
            ret (a + b),
        },
}
]]

local decl = session:loadstring(src, "compiler_code_result_test.lua")()
local module_ast = decl:ast()
local T = asdl.context_of(module_ast)
local C = T.LalinCompiler
local Sem = T.LalinSem
local Stencil = T.LalinStencil
local CodeType = require("lalin.impl.code_type")(T)

-- Shared typed phase composition: surface resolve -> closure conversion ->
-- typecheck (region-expanded) -> tree-to-code lowering -> CodeResult.
local target = CodeType.default_target()
require("lalin.backend_target_model")(T)
require("lalin.impl.tree_surface")
require("lalin.impl.tree_closure")
require("lalin.impl.tree_check")
require("lalin.impl.tree_region")
require("lalin.impl.tree_code")
local resolved = module_ast:surface_resolve()
local closure_result = resolved:closure_convert(Sem.ClosureModuleInput(target:host_target_model()))
local module = closure_result.module
local region_result = module:typecheck_region_expanded()
assert(#(region_result:region_issues() or {}) == 0, "region expansion must be clean")
local checked = region_result:region_module()
local lowering = checked:lower_tree_module_result_to_code({ target = target:host_target_model() })
local c_code = C.CodeResult(lowering.code_module, lowering.contracts, Sem.LayoutEnv({}))

local abi = Abi(T)
local c_report = abi.validate_code_result(c_code)
assert(#c_report.issues == 0)

local request = C.CompilerCCodegenRequest(
  c_code, target,
  Stencil.StencilCompilerPolicy(Stencil.StencilCompilerGcc, Stencil.StencilOptO3, {}))
local c_outcome = require("lalin.compiler_c_backend").code_result_to_c(request)
assert(asdl.classof(c_outcome) == C.CompilerCBackendEmitted)
local c_backend = c_outcome.backend
assert(asdl.classof(c_backend) == C.CompilerCBackendResult)
assert(tostring(asdl.classof(c_backend.unit)):match("LalinC%.CBackendUnit"))
assert(#c_backend.report.issues == 0)

local bad_report = abi.validate_code_result(c_code.module)
assert(#bad_report.issues == 1)
assert(asdl.classof(bad_report.issues[1]) == C.CodeResultIssueUnexpectedValue)

io.write("lalin compiler_code_result ok\n")
