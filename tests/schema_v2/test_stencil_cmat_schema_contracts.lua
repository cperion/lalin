package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local asdl = require("lalin.asdl")
local T = require("lalin.schema_v2")
local Stencil, CMat = T.LalinStencil, T.LalinCMat

local function field_names(cls)
  local result = {}
  for _, field in ipairs(asdl.fields(cls)) do result[#result + 1] = field.name end
  return table.concat(result, ",")
end

assert(field_names(Stencil.StencilKernelProjectionInput) == "module,graph,kernel,schedule,mem,effects")
assert(Stencil.StencilKernelProjected and Stencil.StencilKernelProjectionRejected)
assert(Stencil.StencilBoundDynamic and Stencil.StencilBoundValue)
assert(Stencil.StencilArithmeticInferred and Stencil.StencilArithmeticInteger and Stencil.StencilArithmeticFloat)
assert(Stencil.StencilReadonlyFact and Stencil.StencilUnitStrideFact)
assert(Stencil.StencilScheduleCandidateNoPlan and Stencil.StencilScheduleCandidatePlanned)

assert(field_names(CMat.CMatCFragmentInput) == "materialization,code_func,covered_blocks,target,carriers,addresses")
assert(field_names(CMat.CMatCFragment) == "blocks,locals,helpers,block_mappings,value_mappings,control")
assert(CMat.CMatCFragmentEmitted and CMat.CMatCFragmentRejected)
assert(CMat.CMatCCarrierBindingFound and CMat.CMatCCarrierBindingMissing)
assert(CMat.CMatCAddressBindingFound and CMat.CMatCAddressBindingMissing)
assert(CMat.CMatWindowIndexInBounds and CMat.CMatWindowIndexClamped)
assert(CMat.CMatWindowIndexWrapped and CMat.CMatWindowIndexZero and CMat.CMatWindowIndexRejected)

local function source(path)
  local f = assert(io.open(path, "rb"))
  local text = f:read("*a")
  f:close()
  return text
end
for _, path in ipairs {
  "lua/lalin/schema_v2/stencil.lua",
  "lua/lalin/schema_v2/c_materialize.lua",
} do
  local text = source(path)
  assert(not text:match("optional%s*%["), path .. " must not contain optional protocol soup")
  assert(not text:match("%[bool%]"), path .. " must not contain semantic booleans")
  assert(not text:match("LalinLuaJIT"), path .. " must remain backend-neutral")
end

print("schema_v2 stencil/CMat contracts ok")
