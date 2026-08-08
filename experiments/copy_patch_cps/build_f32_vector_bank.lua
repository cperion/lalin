package.path = "./?.lua;./?/init.lua;" .. package.path

local function read(path)
    local file = assert(io.open(path, "rb"))
    local value = file:read("*a")
    file:close()
    return value
end

local function write(path, value)
    local file = assert(io.open(path, "wb"))
    file:write(value)
    file:close()
end

local source_path = "experiments/copy_patch_cps/vector_stencils.c"
local generated_path = "target/copy_patch_cps/f32_vector/f32_vector_stencils.c"
assert(os.execute("mkdir -p target/copy_patch_cps/f32_vector"))
local source = read(source_path)
source = source:gsub("CopyPatchF64Map", "CopyPatchF32Map")
source = source:gsub("cpv_", "cpf32_")
source = source:gsub("_mm256_castpd256_pd128", "_mm256_castps256_ps128")
source = source:gsub("__m256d", "__m256")
source = source:gsub("double", "float")
source = source:gsub("_pd", "_ps")
source = source:gsub("_sd", "_ss")
source = source:gsub("remaining >= 4", "remaining >= 8")
source = source:gsub("input %+ 4", "input + 8")
source = source:gsub("output %+ 4", "output + 8")
source = source:gsub("remaining %- 4", "remaining - 8")
write(generated_path, source)

local build = read("experiments/copy_patch_cps/build_vector_bank.lua")
build = build:gsub("target/copy_patch_cps/vector", "target/copy_patch_cps/f32_vector")
build = build:gsub("quote%(base %.%. \"vector_stencils%.c\"%)",
    "quote(\"" .. generated_path .. "\")")
build = build:gsub("cpv_", "cpf32_")
build = build:gsub("vector_bank%.lua", "f32_vector_bank.lua")
build = build:gsub("F64MapPipelineV1", "F32MapPipelineV1")
assert(loadstring(build, "@build_f32_vector_bank.generated.lua"))()

local bank_path = "target/copy_patch_cps/f32_vector/f32_vector_bank.lua"
local bank = read(bank_path)
bank = bank:gsub("  gcc = ", "  entry_type = \"CopyPatchF32MapEntry\",\n  gcc = ", 1)
write(bank_path, bank)
