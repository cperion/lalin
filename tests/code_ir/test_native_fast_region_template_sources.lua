package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
if ffi.arch ~= "x64" or ffi.os == "Windows" or not ffi.abi("64bit") or not ffi.abi("le") then
    io.write("skip native fast region template sources: requires x64 non-Windows little-endian 64-bit host\n")
    os.exit(0)
end

local asdl = require("lalin.asdl")
local Schema = require("lalin.schema")

local T = asdl.context()
Schema(T)
require("lalin.native_mc")(T)
local Native = T.LalinNative
local Core = T.LalinCore
local Support = require("lalin.native_template_support")(T)
local Sources = require("lalin.native_template_sources")(T)

local target = Support.host_target()
local i32 = Support.scalar_i32()
local abi_i32 = Support.abi_scalar_value(i32)
local input0 = Native.NativeExprInput(0, i32)
local input1 = Native.NativeExprInput(1, i32)

local binary_imm = Native.NativeExprReturnBinaryImmRhs(i32, Core.BinAdd, input0)
local mul_add_imm = Native.NativeExprReturnMulAddImm(i32, input0, input1)
local fast_abi = Native.NativeFastAbi2(abi_i32, abi_i32, abi_i32)
local compare_branch = Native.NativeCompareBranchAtoms(Core.CmpLt, i32, input0, input1)
local switch_step = Native.NativeSwitchStepAtoms(i32, input0)
local capability = Native.NativeFastRegionCapability(
    { fast_abi },
    { binary_imm, mul_add_imm },
    { compare_branch },
    { switch_step },
    {},
    {},
    {}
)

local request = Sources.bank_request_for_fast_region_capability(
    capability,
    target,
    Support.empty_runtime(),
    Native.NativeBankId("native.template.test.fast-region")
)

Sources.assert_manifest_matches_sources(request.manifest, request.sources)
Sources.assert_unique_source_ids(request.sources)
Sources.assert_unique_family_ids(request.sources)
assert(#request.sources == 7, "fast region capability should produce scalar, public ABI, and fused public/expression sources for requested fast shapes")

local by_family = {}
for _, source in ipairs(request.sources) do
    by_family[source.family.id.text] = source
end

local binary_source = assert(by_family["native.fast.code.expr.return_binary_imm_rhs.i32.add.input0.i32"], "binary-imm fast expression source missing")
assert(asdl.isa(binary_source.extraction, Native.NativeExtractFallthroughFragment), "fast expression source must be fallthrough-extractable")
assert(#binary_source.declared_continuation_ordinals == 0, "fallthrough fast expression source must not declare successor continuations")
assert(not binary_source.c_text:find("lalin_native_cont_next", 1, true), "fallthrough fast expression source must not call an artificial successor")
assert(#binary_source.declared_holes == 3, "binary-imm source should bind lhs frame input, rhs immediate, and result frame output")
assert(binary_source.declared_holes[2].hole == Native.NativePatchImm32, "binary-imm rhs must be a typed immediate hole, not a family axis")
assert(binary_source.declared_holes[3].hole == Native.NativePatchFrameOffset32, "fast expression result must bind through a frame-coordinate hole")
assert(asdl.isa(binary_source.family.axes[3], Native.NativeAxisFastCodeExpr), "fast expression family must carry the typed fast expression axis")
assert(binary_source.family.axes[3].shape == binary_imm, "fast expression axis should be the ASDL shape value")

local mul_add_source = assert(by_family["native.fast.code.expr.return_mul_add_imm.i32.input0.i32.input1.i32"], "mul-add-imm fast expression source missing")
assert(asdl.isa(mul_add_source.extraction, Native.NativeExtractFallthroughFragment), "mul-add-imm source must be fallthrough-extractable")
assert(#mul_add_source.declared_holes == 4, "mul-add-imm source should bind two frame inputs, immediate, and result frame output")
assert(mul_add_source.declared_holes[3].hole == Native.NativePatchImm32, "mul-add immediate must be a typed immediate hole")
assert(mul_add_source.c_text:find("%*", 1, false) and mul_add_source.c_text:find("%+", 1, false), "mul-add source should compile the fused multiply/add expression")

local compare_source = assert(by_family["native.fast.code.compare_branch.compare_branch.i32.lt.input0.i32.input1.i32"], "compare-branch fast source missing")
assert(asdl.isa(compare_source.extraction, Native.NativeExtractContinuationFragment), "compare-branch source must expose real branch continuations")
assert(asdl.isa(compare_source.family.axes[3], Native.NativeAxisFastCodeCompareBranch), "compare-branch family must carry the typed compare axis")
assert(#compare_source.declared_continuation_ordinals == 2, "compare-branch source should declare then/else continuations")

local switch_source = assert(by_family["native.fast.code.switch_step.switch_step.i32.input0.i32"], "switch-step fast source missing")
assert(asdl.isa(switch_source.extraction, Native.NativeExtractContinuationFragment), "switch-step source must expose case/default continuations")
assert(asdl.isa(switch_source.family.axes[3], Native.NativeAxisFastCodeSwitchStep), "switch-step family must carry the typed switch-step axis")
assert(#switch_source.declared_holes == 2, "switch-step source should bind key frame input and per-case immediate")
assert(switch_source.declared_holes[2].hole == Native.NativePatchImm32, "switch case key must be a typed immediate hole, not a family axis")

local abi_source = assert(by_family["native.fast.public_abi.abi2.pi32_i32.ri32"], "bounded fast public ABI source missing")
assert(asdl.isa(abi_source.extraction, Native.NativeExtractStandaloneCallable), "bounded fast public ABI source should expose a standalone C ABI entry")
assert(asdl.isa(abi_source.family.axes[3], Native.NativeAxisFastPublicAbi), "fast public ABI family must carry the bounded ABI shape axis")
assert(abi_source.family.axes[3].shape == fast_abi, "fast public ABI axis should be the ASDL shape value")
assert(#abi_source.declared_holes == 1 and abi_source.declared_holes[1].hole == Native.NativePatchImm32, "fast public scalar result must be supplied by a typed install coordinate")
for _, axis in ipairs(abi_source.family.axes or {}) do
    assert(not asdl.isa(axis, Native.NativeAxisCodeSig), "bounded fast public ABI source must not use full CodeSig axes")
    assert(not asdl.isa(axis, Native.NativeAxisCodeType), "bounded fast public ABI source must not use full CodeType axes")
end
assert(abi_source.c_text:find("int32_t p0, int32_t p1", 1, true), "fast public ABI C source should expose the bounded public C signature")

local public_mul_add_source = assert(by_family["native.fast.public_code_expr.abi2.pi32_i32.ri32.return_mul_add_imm.i32.input0.i32.input1.i32"], "fused public ABI + mul-add source missing")
assert(asdl.isa(public_mul_add_source.extraction, Native.NativeExtractStandaloneCallable), "fused public expression source should be directly callable")
assert(asdl.isa(public_mul_add_source.family.axes[3], Native.NativeAxisFastPublicAbi), "fused public expression family must carry the bounded ABI axis")
assert(asdl.isa(public_mul_add_source.family.axes[4], Native.NativeAxisFastCodeExpr), "fused public expression family must carry the expression axis")
assert(#public_mul_add_source.declared_holes == 1 and public_mul_add_source.declared_holes[1].hole == Native.NativePatchImm32, "fused public mul-add should only patch the immediate operand")
assert(public_mul_add_source.c_text:find("int32_t p0, int32_t p1", 1, true), "fused public expression source should expose public scalar params")
assert(public_mul_add_source.c_text:find("p0", 1, true) and public_mul_add_source.c_text:find("p1", 1, true), "fused public expression should consume public params directly")
assert(public_mul_add_source.c_text:find("return", 1, true), "fused public expression should return through the public ABI")

print("native fast region template sources ok")
