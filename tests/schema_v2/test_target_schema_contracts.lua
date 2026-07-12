package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local asdl = require("lalin.asdl")
local T = require("lalin.schema_v2")
local C, Compiler, Lower = T.LalinC, T.LalinCompiler, T.LalinLower

local target = C.CBackendTarget(
  C.CBackendC11, C.CBackendHostedNative, 64, 64, C.CBackendLittleEndian)
assert(target.dialect == C.CBackendC11)
assert(target.platform == C.CBackendHostedNative)

local supported = C.CBackendTargetFeatureSupported(C.CBackendFeatureC11Atomics)
local rejected = C.CBackendTargetFeatureRejected(C.CBackendFeatureLibm, "freestanding target")
assert(supported.feature == C.CBackendFeatureC11Atomics)
assert(rejected.feature == C.CBackendFeatureLibm)

local function field_names(cls)
  local result = {}
  for _, field in ipairs(asdl.fields(cls)) do result[#result + 1] = field.name end
  return table.concat(result, ",")
end
assert(field_names(C.CBackendTarget) == "dialect,platform,pointer_bits,index_bits,endian")
assert(field_names(Compiler.CompilerCodeGenerationInput) == "module,contracts,target")
assert(field_names(Compiler.CompilerCCodegenRequest) == "result,target")
assert(field_names(Lower.LowerCModuleInput) == "spine,plan")

local function source(path)
  local f = assert(io.open(path, "rb"))
  local text = f:read("*a")
  f:close()
  return text
end
local c_source = source("lua/lalin/schema_v2/c.lua")
assert(not c_source:match("hosted%s*%[bool%]"))
local compiler_source = source("lua/lalin/schema_v2/compiler.lua")
assert(not compiler_source:match("options?%s*%["))

print("schema_v2 target contracts ok")
