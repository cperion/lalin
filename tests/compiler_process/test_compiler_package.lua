package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local asdl = require("lalin.asdl")
local CompilerPackage = require("lalin.compiler_package")
local Plan = require("lalin.phase_plan")

local T = asdl.context()
local pkg = CompilerPackage(T)
local P = T.LalinPhase

assert(asdl.classof(pkg) == P.Package)
assert(pkg.id.text == "lalin.compiler")
assert(#pkg.worlds == 5)
assert(#pkg.machines == 3)
assert(#pkg.phases == 3)
assert(#pkg.roots == 2)
assert(pkg.worlds[1].ty.module_name == "LalinTree")
assert(pkg.worlds[1].ty.type_name == "Module")
assert(pkg.worlds[2].ty.module_name == "LalinCheck")
assert(pkg.worlds[2].ty.type_name == "TypeModuleResult")
assert(pkg.worlds[3].ty.module_name == "LalinCompiler")
assert(pkg.worlds[3].ty.type_name == "CodeResult")
assert(pkg.worlds[4].ty.module_name == "LalinC")
assert(pkg.worlds[4].ty.type_name == "CBackendUnit")
assert(pkg.worlds[5].ty.module_name == "LalinDiag")
assert(pkg.worlds[5].ty.type_name == "Report")

local canonical_implementations = T.LalinCompiler.CompilerImplementationOwner():compiler_implementation_registry()
assert(canonical_implementations.tree_code == T.LalinCompiler.TreeCodeCanonicalImplementation)
assert(canonical_implementations.tree_code:implementation_module_name() == "lalin.impl.tree_code")

local V2 = require("lalin.schema_v2")
local schema_v2_implementations = V2.LalinCompiler.CompilerImplementationOwner():compiler_implementation_registry()
assert(schema_v2_implementations.tree_code == V2.LalinCompiler.TreeCodeSchemaV2Implementation)
assert(schema_v2_implementations.tree_code:implementation_module_name() == "lalin.impl.tree_code")

local planned = Plan.assert_plan(pkg, "compile")
assert(asdl.classof(planned.plan) == P.Plan)
assert(#planned.plan.steps == 3)
assert(planned.plan.steps[1].machine.text == "hosted_typecheck")
assert(planned.plan.steps[2].machine.text == "hosted_checked_to_c_code")
assert(planned.plan.steps[3].machine.text == "hosted_c_code_to_c")
assert(planned.plan.input.text == "tree")
assert(planned.plan.output.text == "c")

local c_plan = Plan.assert_plan(pkg, "emit_c")
assert(asdl.classof(c_plan.plan) == P.Plan)
assert(#c_plan.plan.steps == 3)
assert(c_plan.plan.steps[1].machine.text == "hosted_typecheck")
assert(c_plan.plan.steps[2].machine.text == "hosted_checked_to_c_code")
assert(c_plan.plan.steps[3].machine.text == "hosted_c_code_to_c")
assert(c_plan.plan.output.text == "c")

io.write("lalin compiler_package ok\n")
