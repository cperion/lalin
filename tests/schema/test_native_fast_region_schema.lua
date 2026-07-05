package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local asdl = require("lalin.asdl")
local Schema = require("lalin.schema")

local T = asdl.context()
Schema(T)

local N = T.LalinNative
local Code = T.LalinCode
local Core = T.LalinCore
local Stencil = T.LalinStencil
local Sem = T.LalinSem

local target = N.NativeTarget(
    N.NativeTargetId("schema-native-fast-target"),
    N.NativeArchX64,
    N.NativeOsLinux,
    N.NativeAbiSysV,
    64,
    N.NativeLittleEndian
)
local scalar_i32 = N.NativeScalarInt(32, Code.CodeSigned)
local scalar_ptr = N.NativeScalarPointer(64)
local code_ty_i32 = Code.CodeTyInt(32, Code.CodeSigned)
local abi_i32 = N.NativeAbiScalarValue(scalar_i32, N.NativeSignExtend)
local abi_function = N.NativeAbiFunctionProjection(
    target,
    { N.NativeAbiParamProjection(0, code_ty_i32, abi_i32), N.NativeAbiParamProjection(1, code_ty_i32, abi_i32) },
    N.NativeAbiResultProjection(code_ty_i32, abi_i32)
)
local frame_slot = N.NativeFrameSlot(
    N.NativeFrameSlotId("schema.native.fast.frame.i32"),
    N.NativeScalarValueRepresentation(scalar_i32),
    0,
    4,
    4
)
local frame_layout = N.NativeFrameLayout({ frame_slot }, 16, 8)

local entry = N.NativeFastRegionId("schema.native.fast.entry")
local exit = N.NativeFastRegionId("schema.native.fast.exit")
local input0 = N.NativeExprInput(0, scalar_i32)
local input1 = N.NativeExprInput(1, scalar_i32)
local expr_shape = N.NativeExprReturnMulAddImm(scalar_i32, input0, input1)
local compare_shape = N.NativeCompareBranchImmRhs(Core.CmpEq, scalar_i32, input0)
local memory_shape = N.NativeMemoryLoadBinaryStoreImmRhs(
    scalar_i32,
    Core.BinAdd,
    N.NativeMemoryAddressInputOffsetImm(0, scalar_ptr),
    Code.CodeMemoryAccess(Code.CodeMemoryReadWrite, code_ty_i32, 4, Code.CodeMayTrap, false, nil)
)
local kernel_shape = N.NativeKernelStepExprRegion(
    N.NativeKernelExprCodeValueShape(N.NativeKernelValueScalarShape(scalar_i32))
)
local stencil_shape = N.NativeStencilPointUnaryRegionShape(
    Stencil.StencilUnaryNeg,
    N.NativeStencilValueScalarShape(scalar_i32)
)
local capability = N.NativeFastRegionCapability(
    { N.NativeFastAbi2(abi_i32, abi_i32, abi_i32) },
    { expr_shape },
    { memory_shape },
    { kernel_shape },
    { stencil_shape }
)
local value_binding = N.NativeRegionValueBinding(
    N.NativeTemplateValueId("schema.native.fast.v0"),
    scalar_i32,
    N.NativeResidencePublicParam(0, abi_i32)
)
local result_binding = N.NativeRegionValueBinding(
    N.NativeTemplateValueId("schema.native.fast.result"),
    scalar_i32,
    N.NativeResidencePublicResult(abi_i32)
)
local region = N.NativeFastRegion(
    entry,
    N.NativeCodeTraceRegion(
        Code.CodeFuncId("schema.native.fast.func"),
        Code.CodeInstId("schema.native.fast.first"),
        Code.CodeInstId("schema.native.fast.last")
    ),
    N.NativeCodeExprRegion(expr_shape),
    { value_binding },
    { result_binding },
    N.NativeRegionFallthrough(exit)
)
local plan = N.NativeFastRegionPlan(
    target,
    N.NativeCallCodeSig(abi_function),
    { region },
    entry,
    { exit },
    frame_layout
)
local switch = N.NativeRegionSwitch(
    N.NativeTemplateValueId("schema.native.fast.selector"),
    { N.NativeRegionSwitchCase(Core.LitInt("0"), entry) },
    exit
)
local branch_body = N.NativeCodeCompareBranchRegion(compare_shape)
local memory_body = N.NativeCodeLoadOpStoreRegion(memory_shape)
local kernel_body = N.NativeKernelStepRegion(kernel_shape)
local stencil_body = N.NativeStencilPointRegion(stencil_shape)
local frame_residence = N.NativeResidenceFrameSlot(frame_slot)

assert(asdl.isa(expr_shape, N.NativeCodeExprRegionShape), "Code expr fast shape must be typed")
assert(asdl.isa(compare_shape, N.NativeCodeCompareShape), "Code compare fast shape must be typed")
assert(asdl.isa(memory_shape, N.NativeCodeMemoryRegionShape), "Code memory fast shape must be typed")
assert(asdl.isa(kernel_shape, N.NativeKernelStepRegionShape), "kernel fast shape must be typed")
assert(asdl.isa(stencil_shape, N.NativeStencilPointRegionShape), "stencil fast shape must be typed")
assert(asdl.isa(capability.public_abi_shapes[1], N.NativeFastPublicAbiShape), "public ABI fast shape must be typed")
assert(asdl.isa(branch_body, N.NativeFastRegionBody), "compare branch body must be a fast region body leaf")
assert(asdl.isa(memory_body, N.NativeFastRegionBody), "memory body must be a fast region body leaf")
assert(asdl.isa(kernel_body, N.NativeFastRegionBody), "kernel body must be a fast region body leaf")
assert(asdl.isa(stencil_body, N.NativeFastRegionBody), "stencil body must be a fast region body leaf")
assert(asdl.isa(switch, N.NativeRegionTransfer), "switch transfer must be typed")
assert(frame_residence.slot == frame_slot, "frame residence must carry the concrete frame slot")
assert(plan.regions[1].inputs[1].residence.abi == abi_i32, "region binding must carry public-param residence")
assert(plan.regions[1].outputs[1].residence.abi == abi_i32, "region binding must carry public-result residence")
assert(plan.regions[1].transfer.to == exit, "fallthrough transfer must name its successor region")
assert(plan.frame_layout == frame_layout, "fast plan must carry the baseline frame layout")

io.write("lalin native_fast_region_schema ok\n")
