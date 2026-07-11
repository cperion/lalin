package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local asdl = require("lalin.asdl")
local T = require("lalin.schema_v2")
local TreeCode = T.LalinTreeCode
local Ty = T.LalinType
local Core = T.LalinCore
local Code = T.LalinCode
local CodeType = require("lalin.code_type")(T)
local CodeValidate = require("lalin.code_validate")(T)

-- Binding smoke: both implementation and complete pipeline must bind against
-- the schema_v2 signature vocabulary without constructor aliases.
assert(require("lalin.impl.tree_code"))
assert(require("lalin.pipeline"))

local i32 = Ty.TScalar(Core.ScalarI32)
local state = TreeCode.TreeCodeModuleSigState("sig-v2", {}, {})
local requirements = {
  TreeCode.TreeCodeFunctionSigRequirement,
  TreeCode.TreeCodeExternSigRequirement,
  TreeCode.TreeCodeDirectCallSigRequirement,
  TreeCode.TreeCodeIndirectCallSigRequirement,
  TreeCode.TreeCodeClosureSigRequirement,
}

local expected_id
for i = 1, #requirements do
  local sig_id
  sig_id, state = CodeType.ensure_type_sig_requirement(state, { i32 }, i32, requirements[i])
  expected_id = expected_id or sig_id
  assert(sig_id == expected_id)
  local entry = state.code_sigs[#state.code_sigs]
  assert(entry.sig_id == sig_id)
  assert(entry.requirement == requirements[i])
end

local helper_ty
helper_ty, state = CodeType.type_to_code(state, Ty.TFunc({ i32 }, i32))
assert(state.code_sigs[#state.code_sigs].requirement == TreeCode.TreeCodeHelperSigRequirement)
assert(#state.code_sig_order == 1, "typed requirements must project one emitted CodeSig")

local origin = Code.CodeOriginUnknown
local module = Code.CodeModule(Code.CodeModuleId("module:sig-v2"), state.code_sig_order, {}, {}, {}, {}, {}, origin)
local report = CodeValidate.validate(module)
assert(#report.issues == 0)
local lookup = module:code_sig_projection():code_sig_lookup(expected_id)
assert(asdl.classof(lookup) == Code.CodeSigLookupFound and lookup.sig.id == expected_id)
local missing = module:code_sig_projection():code_sig_lookup(Code.CodeSigId("codesig_missing"))
assert(asdl.classof(missing) == Code.CodeSigLookupMissing)

print("lalin schema_v2 code_sig requirements ok")
