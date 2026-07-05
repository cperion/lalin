package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
if ffi.arch ~= "x64" or ffi.os == "Windows" or not ffi.abi("64bit") or not ffi.abi("le") then
    io.write("skip native template source slice: requires x64 non-Windows little-endian 64-bit host\n")
    os.exit(0)
end

local asdl = require("lalin.asdl")
local Schema = require("lalin.schema")

local function shell_quote(s)
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local function command_ok(cmd)
    local ok = os.execute(cmd)
    return ok == true or ok == 0
end

local function read_file(path)
    local f = assert(io.open(path, "rb"))
    local s = f:read("*a")
    f:close()
    return s
end

local function assert_no_forbidden_terms(label, text)
    local lower = tostring(text):lower()
    assert(not lower:find("residual", 1, true), label .. " must not mention residual")
    assert(not text:find("LuaJIT", 1, true), label .. " must not mention LuaJIT")
    assert(not text:find("LJMC", 1, true), label .. " must not mention LJMC")
    assert(not lower:find("input_count", 1, true), label .. " must not encode exact-cell input counts")
    assert(not lower:find("producer x layout", 1, true), label .. " must not encode Cartesian stencil products")
end

local T = asdl.context()
Schema(T)
require("lalin.native_mc")(T)
local Native = T.LalinNative
local Code = T.LalinCode
local Core = T.LalinCore
local Value = T.LalinValue
local Stencil = T.LalinStencil
local Support = require("lalin.native_template_support")(T)
local NativeBackend = require("lalin.native_backend")(T)
local Sources = require("lalin.native_template_sources")(T)

local function assert_no_marker_holes(label, text)
    local markers = {
        "0x11111111", "0x22222222", "0x33333333", "0x44444444", "0x55555555",
        "0x1122334455667788", "MARK_LHS", "MARK_RHS", "MARK_DST", "MARK_SRC", "MARK_IMM",
    }
    for _, marker in ipairs(markers) do
        assert(not tostring(text):find(marker, 1, true), label .. " must not contain marker-hole bootstrap constant " .. marker)
    end
end

local function manifest_entries(manifest)
    local entries = {}
    local counted = 0
    for _, group in ipairs(manifest.groups or {}) do
        assert(group.chunk_class == group.generator.chunk_class, "manifest group chunk class must match generator chunk class")
        assert(group.total_count == #(group.entries or {}), "manifest group total_count must equal entry count")
        counted = counted + group.total_count
        for _, entry in ipairs(group.entries or {}) do
            assert(entry.generator == group.generator, "manifest entry must be grouped under its exact generator")
            entries[#entries + 1] = entry
        end
    end
    assert(counted == manifest.total_count, "manifest total_count must equal summed group counts")
    return entries
end

local function assert_same_sequence(label, lhs, rhs)
    assert(#(lhs or {}) == #(rhs or {}), label .. " sequence length mismatch")
    for i, value in ipairs(lhs or {}) do
        assert(value == rhs[i], label .. " sequence value mismatch at " .. tostring(i))
    end
end

local function assert_source_manifest_closure(label, request, domain, expected_total_count)
    assert(request.manifest.support_domain == domain.id, label .. " manifest must name the support domain id")
    assert(request.manifest.total_count == expected_total_count, label .. " manifest total_count changed")
    assert(#request.sources == expected_total_count, label .. " source count changed")
    Sources.assert_unique_source_ids(request.sources)
    Sources.assert_unique_family_ids(request.sources)
    Sources.assert_manifest_matches_sources(request.manifest, request.sources)
    local entries = manifest_entries(request.manifest)
    local by_source = {}
    for _, entry in ipairs(entries) do
        assert(by_source[entry.source.text] == nil, label .. " duplicate manifest source " .. entry.source.text)
        by_source[entry.source.text] = entry
    end
    for _, source in ipairs(request.sources) do
        local entry = by_source[source.id.text]
        assert(entry ~= nil, label .. " source missing from manifest: " .. source.id.text)
        assert(source.family == entry.family, label .. " family identity mismatch for " .. source.id.text)
        assert(source.generator == entry.generator, label .. " generator identity mismatch for " .. source.id.text)
        assert(source.configuration == entry.configuration, label .. " configuration identity mismatch for " .. source.id.text)
        assert(source.signature == entry.signature, label .. " signature identity mismatch for " .. source.id.text)
        assert(source.extraction == entry.extraction, label .. " extraction identity mismatch for " .. source.id.text)
        assert(source.generator.owner_family == source.family, label .. " generator must own the exact source family for " .. source.id.text)
        assert(source.configuration.generator == source.generator.id, label .. " configuration must point at the exact source generator for " .. source.id.text)
        assert(#(source.declared_holes or {}) == #(source.declared_hole_ordinals or {}), label .. " hole layouts and hole ordinals must match for " .. source.id.text)
        for i, hole in ipairs(source.declared_holes or {}) do
            local ordinal = source.declared_hole_ordinals[i]
            assert(ordinal.ordinal == i - 1, label .. " hole ordinal must be dense and zero-based for " .. source.id.text)
            assert(ordinal.symbol == hole.symbol, label .. " hole ordinal symbol must match extern hole layout for " .. source.id.text)
            assert(ordinal.hole == hole.hole, label .. " hole ordinal patch type must match hole layout for " .. source.id.text)
        end
        assert_same_sequence(label .. " hole ordinals for " .. source.id.text, source.declared_hole_ordinals, entry.declared_hole_ordinals)
        assert_same_sequence(label .. " continuation ordinals for " .. source.id.text, source.declared_continuation_ordinals, entry.declared_continuation_ordinals)
        assert_same_sequence(label .. " relocation kinds for " .. source.id.text, source.declared_relocation_kinds, entry.declared_relocation_kinds)
        assert_no_marker_holes(source.id.text, source.c_text)
    end
    return entries
end

local function assert_relocation_kinds(source, expected)
    assert(#source.declared_relocation_kinds == #expected, source.family.id.text .. " relocation declaration count mismatch")
    for i, kind in ipairs(expected) do
        assert(source.declared_relocation_kinds[i] == kind, source.family.id.text .. " relocation declaration mismatch at " .. tostring(i))
    end
end

assert(Support.host_target() == NativeBackend.host_target(), "native backend and template sources must share the host NativeTarget")

local i32_domain = Support.host_scalar_i32_support_domain()
local full_domain = Support.host_scalar_support_domain()
assert(i32_domain.passthrough_int_limit == 0 and i32_domain.passthrough_float_limit == 0, "i32 host scalar domain must use spill-all K_int/K_float defaults")
assert(full_domain.passthrough_int_limit == 0 and full_domain.passthrough_float_limit == 0, "full host scalar domain must use spill-all K_int/K_float defaults")
assert(#full_domain.scalars > #i32_domain.scalars, "support domain vocabulary must not be rooted in the i32 proof slice")
local saw_i64, saw_f64, saw_pointer
for _, scalar_support in ipairs(full_domain.scalars) do
    local token = scalar_support.scalar:native_scalar_token()
    if token == "i64" then saw_i64 = true end
    if token == "f64" then saw_f64 = true end
    if token == "ptr64" then saw_pointer = true end
end
assert(saw_i64 and saw_f64 and saw_pointer, "full support domain should name integer, float, and pointer scalar reps")

local full_request = Sources.host_scalar_bank_request()
assert_source_manifest_closure("full host scalar bank request", full_request, full_domain, 3931)
assert(#full_request.sources > #i32_domain.scalars, "full scalar source request should be generated from the full support domain")
local function full_source_for_family(family_id)
    for _, source in ipairs(full_request.sources) do
        if source.family.id.text == family_id then return source end
    end
    return nil
end
for _, family_id in ipairs({
    "native.code.inst.binary.i64.add",
    "native.code.inst.float_binary.f64.add",
    "native.code.inst.unary.bool8.not",
    "native.code.inst.compare.i32.eq",
    "native.code.inst.cast.ireduce.i64.to.i32.slot.to.slot",
    "native.code.inst.cast.fpromote.f32.to.f64.slot.to.slot",
    "native.code.inst.cast.stof.i32.to.f64.slot.to.slot",
    "native.code.inst.cast.ftos.f64.to.i32.slot.to.slot",
    "native.code.inst.select.i32.cond.slot.true.slot.false.const.to.slot",
    "native.code.inst.global_ref.ptr64.to.slot",
    "native.code.inst.addr_of.frame.to.arg",
    "native.code.inst.ptr_offset.ptr64.slot.index.arg.to.slot",
    "native.code.inst.load.i32.ptr.slot.to.slot",
    "native.code.inst.store.i32.ptr.arg.value.const",
    "native.code.inst.slice.make.i32.data.slot.len.arg",
    "native.code.inst.view.make.i32.data.slot.len.arg.stride.slot",
    "native.code.inst.slice.data.to.arg",
    "native.code.inst.view.stride.to.slot",
    "native.code.inst.bytespan.len.to.slot",
    "native.code.inst.aggregate.field_store.i32.value.slot",
    "native.code.inst.aggregate.field_load.i32.to.arg",
    "native.code.inst.array.field_store.i32.value.slot",
    "native.code.inst.variant.ctor.i32.value.slot",
    "native.code.inst.variant.tag.i32.to.slot",
    "native.code.inst.variant.payload.i32.to.arg",
    "native.code.inst.atomic_load.i32.seq_cst.ptr.slot.to.slot",
    "native.code.inst.atomic_store.i32.seq_cst.ptr.arg.value.const",
    "native.code.inst.atomic_rmw.i32.add.seq_cst.ptr.slot.value.const.to.arg",
    "native.code.inst.atomic_cas.i32.seq_cst.ptr.arg.expected.slot.replacement.const.to.slot",
    "native.code.inst.atomic_fence.seq_cst",
    "native.code.inst.alias.f64",
    "native.code.term.return.f64",
    "native.code.term.return.void",
    "native.code.inst.result_copy.f64",
    "native.code.const.literal.i64",
    "native.code.term.jump.next",
    "native.code.term.branch.bool8.slot",
    "native.code.term.branch.bool8.arg",
    "native.code.term.switch_step.i32.slot.imm",
    "native.code.term.call_return.next",
    "native.code.term.unreachable.trap",
}) do
    assert(full_source_for_family(family_id) ~= nil, "full scalar domain should include " .. family_id)
end
assert(asdl.isa(full_source_for_family("native.code.term.return.void").family.axes[3].axis, Native.NativeCodeTermReturnShapeAxis), "void return source should use ABI/result-shape return axis")
assert(asdl.isa(full_source_for_family("native.code.inst.result_copy.f64").family.axes[3].axis, Native.NativeCodeInstResultCopyAxis), "result copy source should use result-copy axis")
assert(asdl.isa(full_source_for_family("native.code.inst.float_binary.f64.add").extraction, Native.NativeExtractContinuationFragment), "f64 add should be a C continuation fragment")
assert(full_source_for_family("native.code.inst.float_binary.f64.add").c_text:find("lalin_native_cont_next", 1, true), "f64 add should tail into the declared C continuation")
assert(full_source_for_family("native.code.const.literal.i64").declared_holes[2].hole == Native.NativePatchImm64, "i64 literal should declare an imm64 hole")
assert_relocation_kinds(
    full_source_for_family("native.code.inst.cast.stof.i32.to.f64.slot.to.slot"),
    { Native.NativeTemplateRelocationHoleOrdinal, Native.NativeTemplateRelocationContinuation, Native.NativeTemplateRelocationConstantPool }
)
assert_relocation_kinds(
    full_source_for_family("native.code.inst.cast.ftos.f64.to.i32.slot.to.slot"),
    { Native.NativeTemplateRelocationHoleOrdinal, Native.NativeTemplateRelocationContinuation, Native.NativeTemplateRelocationConstantPool }
)
assert(asdl.isa(full_source_for_family("native.code.inst.load.i32.ptr.slot.to.slot").generator.chunk_class, Native.NativeChunkAddressMemoryOp), "load source should be an AddressMemoryOp chunk")
assert(asdl.isa(full_source_for_family("native.code.inst.view.make.i32.data.slot.len.arg.stride.slot").generator.chunk_class, Native.NativeChunkDescriptorOp), "view make source should be a DescriptorOp chunk")
assert(asdl.isa(full_source_for_family("native.code.inst.global_ref.ptr64.to.slot").family.axes[3].axis, Native.NativeCodeInstAddressMaterializeAxis), "global-ref source axis should be address-materialization shape, not a placeholder pointer type")
assert(asdl.isa(full_source_for_family("native.code.inst.ptr_offset.ptr64.slot.index.arg.to.slot").family.axes[3].axis, Native.NativeCodeInstPointerOffsetAxis), "ptr_offset source axis should be pointer/index scalar shape, not an exact pointer type placeholder")
assert(asdl.isa(full_source_for_family("native.code.inst.aggregate.field_store.i32.value.slot").family.axes[3].axis, Native.NativeCodeInstLayoutFieldStoreAxis), "aggregate store source axis should be layout-parametric scalar field-store shape")
assert(asdl.isa(full_source_for_family("native.code.inst.array.field_load.i32.to.arg").family.axes[3].axis, Native.NativeCodeInstLayoutFieldLoadAxis), "array load source axis should be layout-parametric scalar field-load shape")
assert(asdl.isa(full_source_for_family("native.code.inst.variant.ctor.i32.value.slot").generator.chunk_class, Native.NativeChunkAggregateVariantOp), "variant ctor source should be an AggregateVariantOp chunk")
assert(asdl.isa(full_source_for_family("native.code.inst.variant.ctor.i32.value.slot").family.axes[3].axis, Native.NativeCodeInstVariantScalarCtorAxis), "variant ctor source axis should be scalar ctor shape, not a synthetic CodeVariantRef")
assert(asdl.isa(full_source_for_family("native.code.inst.variant.payload.i32.to.arg").family.axes[3].axis, Native.NativeCodeInstVariantScalarPayloadAxis), "variant payload source axis should be scalar payload shape, not a synthetic CodeVariantRef")
assert(asdl.isa(full_source_for_family("native.code.inst.atomic_rmw.i32.add.seq_cst.ptr.slot.value.const.to.arg").generator.chunk_class, Native.NativeChunkAddressMemoryOp), "atomic RMW source should be an AddressMemoryOp chunk")
assert(full_source_for_family("native.code.inst.atomic_rmw.i32.add.seq_cst.ptr.slot.value.const.to.arg").c_text:find("__atomic_fetch_add", 1, true), "atomic RMW source should use typed GCC atomic builtin capability")
assert(full_source_for_family("native.code.inst.atomic_fence.seq_cst").c_text:find("__atomic_thread_fence", 1, true), "atomic fence source should use typed GCC atomic builtin capability")
assert(#full_source_for_family("native.code.inst.ptr_offset.ptr64.slot.index.arg.to.slot").declared_hole_ordinals >= 3, "ptr_offset should use extern hole ordinals for frame/static offset facts")
assert(#full_source_for_family("native.code.inst.slice.make.i32.data.slot.len.arg").declared_hole_ordinals >= 2, "slice make should patch descriptor and input frame offsets")
assert(#full_source_for_family("native.code.term.branch.bool8.slot").declared_continuation_ordinals == 2, "bool branch should declare then/else successor ordinals")
assert(#full_source_for_family("native.code.term.jump.next").declared_continuation_ordinals == 1, "jump should declare one successor ordinal")
assert(not (full_source_for_family("native.code.term.switch_step.i32.slot.imm").family.id.text:find("case_count", 1, true)), "switch step must not encode program case count as a bank axis")

local abi_i32 = Native.NativeAbiScalarValue(Support.scalar_i32(), Native.NativeSignExtend)
local abi_projection = Native.NativeAbiFunctionProjection(
    NativeBackend.host_target(),
    {
        Native.NativeAbiParamProjection(0, Code.CodeTyInt(32, Code.CodeSigned), abi_i32),
        Native.NativeAbiParamProjection(1, Code.CodeTyInt(32, Code.CodeSigned), abi_i32),
    },
    Native.NativeAbiResultProjection(Code.CodeTyInt(32, Code.CodeSigned), abi_i32)
)
local abi_runtime_symbol = Native.NativeRuntimeSymbol(Native.NativeRuntimeSymbolId("native.runtime.add"), "lalin_native_runtime_add", abi_projection, nil)
local abi_domain = Support.support_domain(
    Native.NativeTemplateSupportDomainId("native.template.support.test.abi"),
    NativeBackend.host_target(),
    Native.NativeRuntime({ abi_runtime_symbol }),
    { Support.scalar_i32() },
    { abi_projection }
)
local abi_request = Sources.bank_request_for_support_domain(abi_domain, Native.NativeBankId("native.template.test.abi"))
assert(#abi_request.sources == abi_request.manifest.total_count, "ABI/call support request must preserve manifest cardinality")
Sources.assert_manifest_matches_sources(abi_request.manifest, abi_request.sources)
local function abi_source(family_id)
    for _, source in ipairs(abi_request.sources) do
        if source.family.id.text == family_id then return source end
    end
    return nil
end
local abi_token = abi_projection:native_projection_token()
assert(asdl.isa(abi_source("native.code.func.public_abi_adapter." .. abi_token).generator.chunk_class, Native.NativeChunkPublicAbiAdapter), "explicit public ABI projection should generate a public adapter source")
assert(asdl.isa(abi_source("native.code.func.public_abi_adapter." .. abi_token).extraction, Native.NativeExtractPublicAbiAdapter), "public adapter source should carry NativeExtractPublicAbiAdapter")
for _, family_id in ipairs({
    "native.code.inst.call.direct." .. abi_token,
    "native.code.inst.call.indirect." .. abi_token,
    "native.code.inst.call.closure." .. abi_token,
    "native.code.inst.call.extern." .. abi_token,
}) do
    local source = abi_source(family_id)
    assert(source ~= nil, "ABI/call support domain should include " .. family_id)
    assert(asdl.isa(source.generator.chunk_class, Native.NativeChunkCallOp), family_id .. " should be a CallOp source")
end
assert(asdl.isa(abi_source("native.code.inst.call.direct." .. abi_token).family.axes[3].axis, Native.NativeCodeInstCallShapeAxis), "direct call source should use generic call-shape axis")
assert(abi_source("native.code.inst.call.direct." .. abi_token).family.axes[3].axis.shape == Native.NativeCodeCallDirectTarget, "direct call source axis should carry direct target shape")
assert(abi_source("native.code.inst.call.extern." .. abi_token).family.axes[3].axis.shape == Native.NativeCodeCallExternTarget, "extern call source axis should carry extern target shape, not a synthetic CodeExternId")
assert(abi_source("native.code.inst.call.indirect." .. abi_token).family.axes[3].axis.shape == Native.NativeCodeCallIndirectPointer, "indirect call source axis should carry indirect pointer shape")
assert(abi_source("native.code.inst.call.closure." .. abi_token).family.axes[3].axis.shape == Native.NativeCodeCallClosurePointer, "closure call source axis should carry closure pointer shape")
assert_relocation_kinds(
    abi_source("native.code.inst.call.extern." .. abi_token),
    { Native.NativeTemplateRelocationHoleOrdinal, Native.NativeTemplateRelocationContinuation }
)

local descriptor_abi = Code.CodeTySlice(Code.CodeTyInt(32, Code.CodeSigned)):native_abi_projection(NativeBackend.host_target())
local descriptor_projection = Native.NativeAbiFunctionProjection(
    NativeBackend.host_target(),
    { Native.NativeAbiParamProjection(0, Code.CodeTySlice(Code.CodeTyInt(32, Code.CodeSigned)), descriptor_abi) },
    Native.NativeAbiResultProjection(Code.CodeTySlice(Code.CodeTyInt(32, Code.CodeSigned)), descriptor_abi)
)
local descriptor_domain = Support.support_domain(
    Native.NativeTemplateSupportDomainId("native.template.support.test.descriptor.abi"),
    NativeBackend.host_target(),
    NativeBackend.empty_runtime(),
    { Support.scalar_i32(), Support.scalar_pointer(NativeBackend.host_target().pointer_bits) },
    { descriptor_projection }
)
local descriptor_request = Sources.bank_request_for_support_domain(descriptor_domain, Native.NativeBankId("native.template.test.descriptor.abi"))
Sources.assert_manifest_matches_sources(descriptor_request.manifest, descriptor_request.sources)
local descriptor_token = descriptor_projection:native_projection_token()
local function descriptor_source(family_id)
    for _, source in ipairs(descriptor_request.sources) do
        if source.family.id.text == family_id then return source end
    end
end
assert(descriptor_source("native.code.func.public_abi_adapter." .. descriptor_token).c_text:find("struct lalin_native_abi_descriptor", 1, true), "descriptor public ABI source should declare descriptor C boundary type")
assert(descriptor_source("native.code.inst.call.direct." .. descriptor_token).c_text:find("__builtin_memcpy", 1, true), "descriptor call source should copy descriptor results through frame storage")
assert(descriptor_source("native.code.inst.result_copy.descriptor.layout.16").c_text:find("__builtin_memcpy", 1, true), "descriptor result-copy source should be byte-copy based")

local complete_i32 = Support.scalar_i32()
local complete_ptr = Support.scalar_pointer(NativeBackend.host_target().pointer_bits)
local complete_scalar_class = Support.complete_scalar_pointer_scalar_class(complete_i32)
local complete_code_abi_capability = Native.NativeCompleteBankCapability(
    Support.complete_bank_capability_id("test.code-abi"),
    NativeBackend.host_target(),
    { complete_i32, complete_ptr },
    { Support.complete_value_scalar_class(complete_i32), Support.complete_value_pointer_class(complete_ptr) },
    { Support.complete_scalar_bytes_scalar_class(complete_i32) },
    { complete_scalar_class },
    { Support.complete_index_class(NativeBackend.host_target().pointer_bits) },
    {},
    Support.complete_runtime_capability({}, {}, {}),
    Support.complete_frame_capability(complete_ptr, {}, {}),
    Support.complete_constant_pool_capability({}),
    Support.complete_atomic_capability(Native.NativeAtomicNoCodegen, {}, {}, {}),
    Support.complete_code_capability({
        Native.NativeCodeMicroOpFrameEntryShape,
        Native.NativeCodeMicroOpBinaryShape(Core.BinAdd, complete_i32),
        Native.NativeCodeMicroOpLoadShape(Support.complete_scalar_bytes_scalar_class(complete_i32)),
        Native.NativeCodeMicroOpCallIndirectShape,
        Native.NativeCodeMicroOpReturnScalarShape(complete_i32),
    }),
    Support.complete_abi_capability({
        Native.NativeAbiMicroOpParamRegisterShape(complete_scalar_class),
        Native.NativeAbiMicroOpCallIndirectShape,
        Native.NativeAbiMicroOpReturnScalarShape(complete_scalar_class),
    }),
    Support.complete_kernel_capability({}),
    Support.complete_stencil_capability({})
)
local complete_code_abi_request = Sources.bank_request_for_complete_capability(complete_code_abi_capability, Native.NativeBankId("native.template.test.complete.code-abi"))
Sources.assert_manifest_matches_sources(complete_code_abi_request.manifest, complete_code_abi_request.sources)
assert(#complete_code_abi_request.sources == #complete_code_abi_capability.code.micro_ops + #complete_code_abi_capability.abi.micro_ops, "complete Code/ABI request should expand one source per closed micro-op")
for _, source in ipairs(complete_code_abi_request.sources) do
    local saw_closed_axis = false
    for _, axis in ipairs(source.family.axes) do
        assert(not asdl.isa(axis, Native.NativeAxisCodeType), "complete Code/ABI sources must not use CodeType axes")
        assert(not asdl.isa(axis, Native.NativeAxisCodeSig), "complete Code/ABI sources must not use CodeSig axes")
        saw_closed_axis = saw_closed_axis or asdl.isa(axis, Native.NativeAxisCodeMicroOp) or asdl.isa(axis, Native.NativeAxisAbiMicroOp)
    end
    assert(saw_closed_axis, source.family.id.text .. " should carry a closed micro-op axis")
end

local complete_kernel_value_class = Support.complete_value_scalar_class(complete_i32)
local complete_kernel_reducer = Native.NativeReducerClass(Value.ReductionAdd, complete_kernel_value_class)
local complete_kernel_capability = Native.NativeCompleteBankCapability(
    Support.complete_bank_capability_id("test.kernel"),
    NativeBackend.host_target(),
    { complete_i32, complete_ptr },
    { complete_kernel_value_class },
    {}, {}, {}, {},
    Support.complete_runtime_capability({}, {}, {}),
    Support.complete_frame_capability(complete_ptr, {}, {}),
    Support.complete_constant_pool_capability({}),
    Support.complete_atomic_capability(Native.NativeAtomicNoCodegen, {}, {}, {}),
    Support.complete_code_capability({}),
    Support.complete_abi_capability({}),
    Support.complete_kernel_capability({
        Native.NativeKernelMicroOpScalarLoadShape(complete_i32),
        Native.NativeKernelMicroOpExprBinaryShape(Core.BinAdd, complete_kernel_value_class),
        Native.NativeKernelMicroOpAffineAddTermShape(complete_kernel_value_class),
        Native.NativeKernelMicroOpPredicateCompareConstShape(Core.CmpEq, complete_kernel_value_class),
        Native.NativeKernelMicroOpEffectScanShape(complete_kernel_reducer, Stencil.StencilScanInclusive),
        Native.NativeKernelMicroOpResultReductionShape(complete_kernel_reducer),
    }),
    Support.complete_stencil_capability({})
)
local complete_kernel_request = Sources.bank_request_for_complete_capability(complete_kernel_capability, Native.NativeBankId("native.template.test.complete.kernel"))
Sources.assert_manifest_matches_sources(complete_kernel_request.manifest, complete_kernel_request.sources)
assert(#complete_kernel_request.sources == #complete_kernel_capability.kernel.micro_ops, "complete Kernel request should expand one source per primitive micro-op")
for _, source in ipairs(complete_kernel_request.sources) do
    local saw_kernel_micro_axis = false
    for _, axis in ipairs(source.family.axes) do
        assert(not asdl.isa(axis, Native.NativeAxisKernel), "complete Kernel sources must not use exact Kernel source-shape/projection axes")
        saw_kernel_micro_axis = saw_kernel_micro_axis or asdl.isa(axis, Native.NativeAxisKernelMicroOp)
    end
    assert(saw_kernel_micro_axis, source.family.id.text .. " should carry a closed Kernel micro-op axis")
end

local complete_stencil_capability = Native.NativeCompleteBankCapability(
    Support.complete_bank_capability_id("test.stencil"),
    NativeBackend.host_target(),
    { complete_i32, complete_ptr },
    { complete_kernel_value_class },
    {}, {}, { Support.complete_index_class(NativeBackend.host_target().pointer_bits) }, {},
    Support.complete_runtime_capability({}, {}, {}),
    Support.complete_frame_capability(complete_ptr, {}, {}),
    Support.complete_constant_pool_capability({}),
    Support.complete_atomic_capability(Native.NativeAtomicNoCodegen, {}, {}, {}),
    Support.complete_code_capability({}),
    Support.complete_abi_capability({}),
    Support.complete_kernel_capability({}),
    Support.complete_stencil_capability({
        Native.NativeStencilMicroOpProducerEnterShape,
        Native.NativeStencilMicroOpAccessIndexedShape(complete_kernel_value_class, Support.complete_index_class(NativeBackend.host_target().pointer_bits)),
        Native.NativeStencilMicroOpPointBinaryShape(Stencil.StencilBinaryAdd, complete_kernel_value_class),
        Native.NativeStencilMicroOpPointSelectShape(Native.NativePredicateNonZeroClass, complete_kernel_value_class),
        Native.NativeStencilMicroOpSinkReduceShape(complete_kernel_reducer, Native.NativeStencilReduceScopeDomainClass),
        Native.NativeStencilMicroOpScheduleUnrolledShape(Native.NativeUnrollFixed(4)),
    })
)
local complete_stencil_request = Sources.bank_request_for_complete_capability(complete_stencil_capability, Native.NativeBankId("native.template.test.complete.stencil"))
Sources.assert_manifest_matches_sources(complete_stencil_request.manifest, complete_stencil_request.sources)
assert(#complete_stencil_request.sources == #complete_stencil_capability.stencil.micro_ops, "complete Stencil request should expand one source per primitive micro-op")
for _, source in ipairs(complete_stencil_request.sources) do
    local saw_stencil_micro_axis = false
    for _, axis in ipairs(source.family.axes) do
        assert(not asdl.isa(axis, Native.NativeAxisStencilProducer), "complete Stencil sources must not use producer exact axes")
        assert(not asdl.isa(axis, Native.NativeAxisStencilAccess), "complete Stencil sources must not use access exact axes")
        assert(not asdl.isa(axis, Native.NativeAxisStencilPoint), "complete Stencil sources must not use point exact axes")
        assert(not asdl.isa(axis, Native.NativeAxisStencilBody), "complete Stencil sources must not use body exact axes")
        assert(not asdl.isa(axis, Native.NativeAxisStencilSink), "complete Stencil sources must not use sink exact axes")
        assert(not asdl.isa(axis, Native.NativeAxisStencilSchedule), "complete Stencil sources must not use schedule exact axes")
        saw_stencil_micro_axis = saw_stencil_micro_axis or asdl.isa(axis, Native.NativeAxisStencilMicroOp)
    end
    assert(saw_stencil_micro_axis, source.family.id.text .. " should carry a closed Stencil micro-op axis")
end

local kernel_value_i32 = Native.NativeKernelValueScalarShape(Support.scalar_i32())
local kernel_loop_shape = Native.NativeKernelLoopRange1DShape(Support.scalar_index(NativeBackend.host_target().pointer_bits), Native.NativeKernelTripDynamicNonNegativeShape, true)
local kernel_lane_shape = Native.NativeKernelLaneContiguousAddressShape(kernel_value_i32, Support.scalar_pointer(NativeBackend.host_target().pointer_bits), Support.scalar_index(NativeBackend.host_target().pointer_bits))
local kernel_expr_shape = Native.NativeKernelExprBinaryShape(Core.BinAdd, kernel_value_i32)
local kernel_reducer_shape = Native.NativeKernelReducerSourceShape(Value.ReductionAdd, kernel_value_i32)
local kernel_pred_shape = Native.NativeKernelPredicateCompareConstShape(Core.CmpGt, kernel_value_i32)
local kernel_result_shape = Native.NativeKernelResultValueShape(Native.NativeKernelExprKernelValueShape(kernel_value_i32))
local kernel_body_shape = Native.NativeKernelBodySourceShape(kernel_loop_shape, 1, 1, 2, kernel_result_shape)
local kernel_shapes = {
    Native.NativeKernelDomainOpShape(kernel_loop_shape),
    Native.NativeKernelLaneOpShape(kernel_lane_shape),
    Native.NativeKernelExprOpShape(kernel_expr_shape),
    Native.NativeKernelExprOpShape(Native.NativeKernelExprCastShape(Core.MachineCastIdentity, kernel_value_i32, kernel_value_i32)),
    Native.NativeKernelEffectOpShape(Native.NativeKernelEffectStoreShape(kernel_lane_shape, Native.NativeKernelExprKernelValueShape(kernel_value_i32))),
    Native.NativeKernelEffectOpShape(Native.NativeKernelEffectFoldShape(kernel_reducer_shape)),
    Native.NativeKernelEffectOpShape(Native.NativeKernelEffectCallShape(Native.NativeKernelCallInternalShape)),
    Native.NativeKernelResultOpShape(kernel_result_shape),
    Native.NativeKernelResultOpShape(Native.NativeKernelResultFindShape(Native.NativeKernelExprKernelValueShape(kernel_value_i32), kernel_pred_shape)),
    Native.NativeKernelProofOpShape(Native.NativeKernelProofFlowShape),
    Native.NativeKernelBodyOpShape(kernel_body_shape),
    Native.NativeKernelPlanOpShape(Native.NativeKernelPlannedSourceShape(kernel_body_shape)),
}
local kernel_domain = Support.support_domain_with_kernel_sources(
    Native.NativeTemplateSupportDomainId("native.template.support.test.kernel.sources"),
    NativeBackend.host_target(),
    NativeBackend.empty_runtime(),
    {},
    Support.kernel_source_support(kernel_shapes)
)
local kernel_request = Sources.bank_request_for_support_domain(kernel_domain, Native.NativeBankId("native.template.test.kernel.sources"))
Sources.assert_manifest_matches_sources(kernel_request.manifest, kernel_request.sources)
local kernel_source_count = 0
local function kernel_source_for(shape)
    local family_id = "native.kernel." .. shape:native_kernel_op_source_token()
    for _, source in ipairs(kernel_request.sources) do
        if source.family.id.text == family_id then return source end
    end
end
for _, shape in ipairs(kernel_shapes) do
    local source = kernel_source_for(shape)
    assert(source ~= nil, "kernel source support should emit " .. shape:native_kernel_op_source_token())
    kernel_source_count = kernel_source_count + 1
    assert(asdl.isa(source.generator.chunk_class, Native.NativeChunkKernelOp), "kernel source should be a NativeChunkKernelOp")
    assert(asdl.isa(source.family.axes[2].axis, Native.NativeKernelSourceShapeAxis), "kernel source family must select by finite source-shape axis")
    assert(source.family.axes[2].axis.shape:native_kernel_op_source_shape_equals(shape), "kernel source axis must carry the exact finite source shape")
    assert(not source.family.id.text:find("native.kernel.func", 1, true), "kernel source family must not encode program function identities")
    assert(not source.family.id.text:find("native.kernel.plan.id", 1, true), "kernel source family must not encode program plan identities")
end
assert(kernel_source_count == #kernel_shapes, "all requested KernelOp source shapes should be generated")
local domain_kernel_source = kernel_source_for(kernel_shapes[1])
assert(#domain_kernel_source.declared_continuation_ordinals == 2, "kernel domain loop source should declare body/exit continuations")
assert(#domain_kernel_source.declared_hole_ordinals >= 2, "kernel domain loop source should use frame holes for counter/trip state")
assert(domain_kernel_source.c_text:find("kernel_trip", 1, true), "kernel domain source should materialize trip-count loop state")
local lane_kernel_source = kernel_source_for(kernel_shapes[2])
assert(lane_kernel_source.c_text:find("elem_size", 1, true), "kernel lane source should bind static element size through a hole")
local expr_kernel_source = kernel_source_for(kernel_shapes[3])
assert(expr_kernel_source.c_text:find("uint32_t", 1, true), "kernel expression source should use typed scalar arithmetic")
local call_kernel_source = kernel_source_for(kernel_shapes[7])
assert(call_kernel_source.c_text:find("extern void lalin_native_hole_", 1, true), "kernel call source should patch a frame-protocol helper target through a hole")
assert_relocation_kinds(call_kernel_source, { Native.NativeTemplateRelocationHoleOrdinal, Native.NativeTemplateRelocationContinuation })

local stencil_value_i32 = Native.NativeStencilValueScalarShape(Support.scalar_i32())
local stencil_producer_shape = Native.NativeStencilProducerRange1DShape(stencil_value_i32, 1, Stencil.StencilProducerForward)
local stencil_access_shape = Native.NativeStencilAccessContiguousShape(stencil_value_i32, 1)
local stencil_point_shape = Native.NativeStencilPointBinaryShape(Stencil.StencilBinaryAdd, stencil_value_i32)
local stencil_cast_shape = Native.NativeStencilPointCastShape(Core.MachineCastIdentity, stencil_value_i32, stencil_value_i32)
local stencil_pred_shape = Native.NativeKernelPredicateCompareConstShape(Core.CmpGt, kernel_value_i32)
local stencil_select_shape = Native.NativeStencilPointSelectShape(stencil_pred_shape, stencil_value_i32)
local stencil_body_shape = Native.NativeStencilBodyPointShape(stencil_point_shape)
local stencil_sink_shape = Native.NativeStencilSinkStoreShape(Stencil.StencilStoreElementwise, stencil_access_shape)
local stencil_int_semantics = Code.CodeIntSemantics(Code.CodeIntWrap, Code.CodeDivTrapOnZero, Code.CodeShiftMaskCount)
local stencil_reduce_shape = Native.NativeStencilSinkReduceShape(stencil_value_i32, Stencil.StencilReduceScopeDomain, Stencil.StencilReduceFold(Stencil.StencilReducer(Value.ReductionAdd, Code.CodeTyInt(32, Code.CodeSigned), Value.ValueExprConst(Code.CodeConstLiteral(Code.CodeTyInt(32, Code.CodeSigned), Core.LitInt("0"))), stencil_int_semantics, nil)))
local stencil_compiler = Stencil.StencilCompilerPolicy(Stencil.StencilCompilerGcc, Stencil.StencilOptO2, Stencil.StencilMachineNative, {})
local stencil_schedule_shape = Native.NativeStencilScheduleScalarShape(stencil_compiler)
local stencil_shapes = {
    producers = { stencil_producer_shape },
    accesses = { stencil_access_shape },
    points = { stencil_point_shape, stencil_cast_shape, stencil_select_shape },
    bodies = { stencil_body_shape },
    sinks = { stencil_sink_shape, stencil_reduce_shape },
    schedules = { stencil_schedule_shape },
}
local stencil_domain = Support.support_domain_with_sources(
    Native.NativeTemplateSupportDomainId("native.template.support.test.stencil.sources"),
    NativeBackend.host_target(),
    NativeBackend.empty_runtime(),
    {},
    Support.empty_kernel_source_support(),
    Support.stencil_source_support(stencil_shapes.producers, stencil_shapes.accesses, stencil_shapes.points, stencil_shapes.bodies, stencil_shapes.sinks, stencil_shapes.schedules)
)
local stencil_request = Sources.bank_request_for_support_domain(stencil_domain, Native.NativeBankId("native.template.test.stencil.sources"))
Sources.assert_manifest_matches_sources(stencil_request.manifest, stencil_request.sources)
local stencil_source_count = 0
for _, source in ipairs(stencil_request.sources) do
    if source.family.id.text:find("native.stencil.", 1, true) == 1 then stencil_source_count = stencil_source_count + 1 end
end
assert(stencil_source_count == 9, "stencil source support should emit exactly the requested finite StencilOp source shapes")
local function stencil_source_for(family_id)
    for _, source in ipairs(stencil_request.sources) do
        if source.family.id.text == family_id then return source end
    end
end
local function assert_stencil_source(family_id, axis_parent_name)
    local source = stencil_source_for(family_id)
    assert(source ~= nil, "stencil source support should emit " .. family_id)
    assert(asdl.isa(source.generator.chunk_class, Native.NativeChunkStencilOp), family_id .. " should be a NativeChunkStencilOp")
    assert(source.family.axes[1].target == NativeBackend.host_target(), family_id .. " should carry target as first family axis")
    assert(not source.family.id.text:find("native.stencil.contract", 1, true), family_id .. " must not encode program StencilInstance ids")
    assert(not source.family.id.text:find("AccessRef", 1, true), family_id .. " must not encode program AccessRef identities")
    assert(not source.family.id.text:find("PointExpr", 1, true), family_id .. " must not encode program PointExpr identities")
    assert(source.c_text:find("uint8_t %*frame", 1, false), family_id .. " should use the frame continuation protocol")
    if axis_parent_name == "producer" then assert(asdl.isa(source.family.axes[2].axis, Native.NativeStencilProducerSourceShapeAxis), family_id .. " should use producer source-shape axis") end
    if axis_parent_name == "access" then assert(asdl.isa(source.family.axes[2].axis, Native.NativeStencilAccessSourceShapeAxis), family_id .. " should use access source-shape axis") end
    if axis_parent_name == "point" then assert(asdl.isa(source.family.axes[2].axis, Native.NativeStencilPointSourceShapeAxis), family_id .. " should use point source-shape axis") end
    if axis_parent_name == "body" then assert(asdl.isa(source.family.axes[2].axis, Native.NativeStencilBodySourceShapeAxis), family_id .. " should use body source-shape axis") end
    if axis_parent_name == "sink" then assert(asdl.isa(source.family.axes[2].axis, Native.NativeStencilSinkSourceShapeAxis), family_id .. " should use sink source-shape axis") end
    if axis_parent_name == "schedule" then assert(asdl.isa(source.family.axes[2].axis, Native.NativeStencilScheduleSourceShapeAxis), family_id .. " should use schedule source-shape axis") end
    return source
end
local stencil_producer_source = assert_stencil_source("native.stencil.producer.range1d.i32.step1.forward", "producer")
assert(#stencil_producer_source.declared_continuation_ordinals == 2, "stencil producer source should declare body/exit continuations")
assert(#stencil_producer_source.declared_hole_ordinals >= 2, "stencil producer source should use frame holes for dynamic counter/bounds")
assert(stencil_producer_source.c_text:find("counter", 1, true), "stencil producer source should materialize loop counter state")
local stencil_access_source = assert_stencil_source("native.stencil.access.contiguous.i32.stride1", "access")
assert(stencil_access_source.c_text:find("elem_size", 1, true), "stencil access source should patch static element size through a hole")
local stencil_point_source = assert_stencil_source("native.stencil.point.binary.add.i32", "point")
assert(stencil_point_source.c_text:find("+", 1, true), "stencil binary point source should emit typed scalar arithmetic")
assert_relocation_kinds(stencil_point_source, { Native.NativeTemplateRelocationHoleOrdinal, Native.NativeTemplateRelocationContinuation })
assert_stencil_source("native.stencil.point.cast.identity.i32.to.i32", "point")
assert_stencil_source("native.stencil.point.select.compare_const.gt.i32.i32", "point")
assert_stencil_source("native.stencil.body.point.binary.add.i32", "body")
local stencil_sink_source = assert_stencil_source("native.stencil.sink.store.elementwise.contiguous.i32.stride1", "sink")
assert(stencil_sink_source.c_text:find("uintptr_t", 1, true), "stencil sink source should compose access address fragments through frame values")
assert_stencil_source("native.stencil.sink.reduce.i32.domain.fold.add.i32", "sink")
local stencil_schedule_source = assert_stencil_source("native.stencil.schedule.scalar.gcc.o2.native.flags.", "schedule")
assert(#stencil_schedule_source.declared_continuation_ordinals == 1, "stencil schedule source should continue to the next graph node")

local request = Sources.bank_request_for_support_domain(i32_domain, Support.host_scalar_i32_bank_id())
assert_source_manifest_closure("i32 host scalar bank request", request, i32_domain, 301)
assert(#request.sources > 0, "scalar i32 support slice should be non-empty")

local required_families = {
    ["native.code.func.entry.i32.return.i32"] = true,
    ["native.code.func.entry.i32.return.bool8"] = true,
    ["native.code.inst.binary.i32.add"] = true,
    ["native.code.inst.binary.i32.sub"] = true,
    ["native.code.inst.binary.i32.mul"] = true,
    ["native.code.inst.result_copy.i32"] = true,
    ["native.code.term.return.void"] = true,
    ["native.code.inst.cast.identity.i32.to.i32.slot.to.slot"] = true,
    ["native.code.inst.select.i32.cond.arg.true.arg.false.arg.to.arg"] = true,
    ["native.code.inst.global_ref.ptr64.to.slot"] = true,
    ["native.code.inst.ptr_offset.ptr64.slot.index.arg.to.slot"] = true,
    ["native.code.inst.load.i32.ptr.slot.to.slot"] = true,
    ["native.code.inst.store.i32.ptr.arg.value.const"] = true,
    ["native.code.inst.slice.make.i32.data.slot.len.arg"] = true,
    ["native.code.inst.view.make.i32.data.slot.len.arg.stride.slot"] = true,
    ["native.code.inst.aggregate.field_load.i32.to.arg"] = true,
    ["native.code.inst.variant.payload.i32.to.arg"] = true,
    ["native.code.inst.atomic_load.i32.seq_cst.ptr.slot.to.slot"] = true,
    ["native.code.inst.atomic_store.i32.seq_cst.ptr.arg.value.const"] = true,
    ["native.code.inst.atomic_rmw.i32.add.seq_cst.ptr.slot.value.const.to.arg"] = true,
    ["native.code.inst.atomic_cas.i32.seq_cst.ptr.arg.expected.slot.replacement.const.to.slot"] = true,
    ["native.code.inst.atomic_fence.seq_cst"] = true,
    ["native.code.const.literal.i32"] = true,
    ["native.code.term.return.i32"] = true,
}

local seen_family = {}
local const_literal_source
for _, source in ipairs(request.sources) do
    local family_id = source.family.id.text
    assert(not seen_family[family_id], "duplicate source family " .. tostring(family_id))
    seen_family[family_id] = true
    assert_no_forbidden_terms(source.id.text, source.id.text .. "\n" .. family_id .. "\n" .. source.entry_symbol .. "\n" .. source.c_text)
    if family_id == "native.code.const.literal.i32" then const_literal_source = source end
end
for family_id in pairs(required_families) do
    assert(seen_family[family_id], "closed scalar i32 slice must include " .. family_id)
end
local function source_for_i32_family(family_id)
    for _, candidate in ipairs(request.sources) do
        if candidate.family.id.text == family_id then return candidate end
    end
    return nil
end

assert(const_literal_source ~= nil, "closed slice must include CodeConstLiteral i32")
assert(#const_literal_source.declared_holes == 2, "i32 literal source must use frame and literal patch holes")
assert(#const_literal_source.declared_hole_ordinals == 2, "i32 literal source must declare matching hole ordinals")
assert(const_literal_source.declared_hole_ordinals[1].symbol == const_literal_source.declared_holes[1].symbol, "literal frame hole ordinal must name the extern frame hole")
assert(const_literal_source.declared_hole_ordinals[2].symbol == const_literal_source.declared_holes[2].symbol, "literal immediate hole ordinal must name the extern immediate hole")
assert(asdl.isa(const_literal_source.declared_holes[2].hole, Native.NativePatchImm32), "literal value must be a NativePatchImm32 hole, not a family axis")
assert_relocation_kinds(const_literal_source, { Native.NativeTemplateRelocationHoleOrdinal, Native.NativeTemplateRelocationContinuation })
assert(const_literal_source.c_text:find("extern const uint8_t lalin_native_hole_", 1, true), "literal source must use extern-symbol hole ordinals")
assert(not const_literal_source.family.id.text:find("0", 1, true), "literal value must not appear in the family identity")

local edge_copy_arg_source = source_for_i32_family("native.code.inst.edge_copy.i32.slot.to.arg")
assert(edge_copy_arg_source ~= nil, "closed slice must include slot-to-continuation-arg edge copy")
assert(edge_copy_arg_source.c_text:find("extern void lalin_native_cont_next(uint8_t *frame, int32_t arg0);", 1, true), "edge copy to continuation arg must derive the successor C prototype from its stencil signature")
assert(#edge_copy_arg_source.signature.continuations[1].params == 1, "edge copy to continuation arg must declare one continuation parameter")
assert_relocation_kinds(edge_copy_arg_source, { Native.NativeTemplateRelocationHoleOrdinal, Native.NativeTemplateRelocationContinuation })

local branch_slot_source = source_for_i32_family("native.code.term.branch.bool8.slot")
assert(branch_slot_source ~= nil, "closed slice must include bool8 frame-slot branch")
assert(#branch_slot_source.declared_hole_ordinals == 1, "frame-slot branch must declare a condition hole ordinal")
assert(branch_slot_source.declared_continuation_ordinals[1].symbol.name == "lalin_native_cont_then", "branch first continuation ordinal must be then")
assert(branch_slot_source.declared_continuation_ordinals[2].symbol.name == "lalin_native_cont_else", "branch second continuation ordinal must be else")
assert_relocation_kinds(branch_slot_source, { Native.NativeTemplateRelocationHoleOrdinal, Native.NativeTemplateRelocationContinuation })
assert(branch_slot_source.c_text:find("extern void lalin_native_cont_then(uint8_t *frame);", 1, true), "branch source must declare then continuation prototype")
assert(branch_slot_source.c_text:find("extern void lalin_native_cont_else(uint8_t *frame);", 1, true), "branch source must declare else continuation prototype")

local branch_arg_source = source_for_i32_family("native.code.term.branch.bool8.arg")
assert(branch_arg_source ~= nil, "closed slice must include bool8 continuation-arg branch")
assert(#branch_arg_source.declared_hole_ordinals == 0, "continuation-arg branch must not use a frame marker hole")
assert(branch_arg_source.c_text:find("void lalin_native_code_term_branch_bool8_arg(uint8_t *frame, uint8_t arg0)", 1, true), "continuation-arg branch entry must derive its argument from the stencil signature")
assert_relocation_kinds(branch_arg_source, { Native.NativeTemplateRelocationContinuation })

local cast_slot_source = source_for_i32_family("native.code.inst.cast.identity.i32.to.i32.slot.to.slot")
assert(cast_slot_source ~= nil, "closed slice must include i32 identity cast slot-to-slot")
assert(asdl.isa(cast_slot_source.generator.chunk_class, Native.NativeChunkCastOp), "i32 cast source should be a CastOp chunk")
assert(#cast_slot_source.declared_hole_ordinals == 2, "slot-to-slot cast must declare source and destination frame holes")
assert(cast_slot_source.c_text:find("int32_t cast_value", 1, true), "cast source should materialize a typed cast result")
assert_relocation_kinds(cast_slot_source, { Native.NativeTemplateRelocationHoleOrdinal, Native.NativeTemplateRelocationContinuation })

local cast_const_arg_source = source_for_i32_family("native.code.inst.cast.identity.i32.to.i32.const.to.arg")
assert(cast_const_arg_source ~= nil, "closed slice must include immediate-to-continuation-arg cast")
assert(#cast_const_arg_source.declared_hole_ordinals == 1, "immediate-to-arg cast should use exactly one immediate hole")
assert(cast_const_arg_source.c_text:find("extern void lalin_native_cont_next(uint8_t *frame, int32_t arg0);", 1, true), "cast to continuation arg must derive successor prototype")
assert_relocation_kinds(cast_const_arg_source, { Native.NativeTemplateRelocationHoleOrdinal, Native.NativeTemplateRelocationContinuation })

local select_arg_source = source_for_i32_family("native.code.inst.select.i32.cond.arg.true.arg.false.arg.to.arg")
assert(select_arg_source ~= nil, "closed slice must include arg/arg/arg select to continuation arg")
assert(asdl.isa(select_arg_source.generator.chunk_class, Native.NativeChunkSelectOp), "i32 select source should be a SelectOp chunk")
assert(#select_arg_source.declared_hole_ordinals == 0, "arg-only select should not declare hole ordinals")
assert(select_arg_source.c_text:find("uint8_t cond = arg0;", 1, true), "select condition must read continuation arg0")
assert(select_arg_source.c_text:find("int32_t true_value = arg1;", 1, true), "select true arm must read continuation arg1")
assert(select_arg_source.c_text:find("int32_t false_value = arg2;", 1, true), "select false arm must read continuation arg2")
assert(select_arg_source.c_text:find("selected_value = (cond != 0) ? true_value : false_value;", 1, true), "select source must use branch-safe value selection")
assert_relocation_kinds(select_arg_source, { Native.NativeTemplateRelocationContinuation })

for _, name in ipairs({ "add", "sub", "mul" }) do
    local source = source_for_i32_family("native.code.inst.binary.i32." .. name)
    assert(source ~= nil, "closed slice must include i32 " .. name)
    assert(asdl.isa(source.extraction, Native.NativeExtractContinuationFragment), "i32 " .. name .. " fragment should be a C continuation fragment")
    assert(#source.declared_hole_ordinals == 3, "i32 " .. name .. " should declare lhs/rhs/dst extern hole ordinals")
    assert_relocation_kinds(source, { Native.NativeTemplateRelocationHoleOrdinal, Native.NativeTemplateRelocationContinuation })
    assert(source.c_text:find("extern const uint8_t lalin_native_hole_", 1, true), "i32 " .. name .. " should use extern-symbol hole ordinals")
    assert(source.c_text:find("uint8_t %*frame", 1, false), "i32 " .. name .. " should use the C frame protocol")
    assert(source.c_text:find("extern void lalin_native_cont_next(uint8_t *frame);", 1, true), "i32 " .. name .. " should declare the signature-derived C continuation")
    assert(source.c_text:find("lalin_native_cont_next", 1, true), "i32 " .. name .. " should call the declared successor continuation")
    assert(source.c_text:find("uint32_t", 1, true), "i32 wrap " .. name .. " should express wrapping through unsigned C semantics")
end

local dir = "target/test_artifacts/test_native_template_sources"
local c_path = dir .. "/bank.c"
local h_path = dir .. "/bank.h"
local lua_path = dir .. "/bank.lua"
local so_path = dir .. "/bank.so"
local manifest_path = dir .. "/manifest.lua"

assert(command_ok("rm -rf " .. shell_quote(dir)))
assert(command_ok("mkdir -p " .. shell_quote(dir)))

local manifest = [[
return function(T)
  return require('lalin.native_template_sources')(T).host_scalar_i32_bank_request()
end
]]
local mf = assert(io.open(manifest_path, "wb"))
mf:write(manifest)
mf:close()

local cmd = table.concat({
    "luajit tools/gen_lalin_mc_bank.lua",
    shell_quote(c_path),
    shell_quote(h_path),
    shell_quote(lua_path),
    shell_quote(manifest_path),
    ">",
    shell_quote(dir .. "/generator.out"),
    "2>",
    shell_quote(dir .. "/generator.log"),
}, " ")
assert(command_ok(cmd), "native bank generator should build the scalar i32 source slice")
assert(command_ok("gcc -c " .. shell_quote(c_path) .. " -o " .. shell_quote(dir .. "/bank.o")), "generated C bridge should compile")
assert(command_ok("gcc -shared -fPIC " .. shell_quote(c_path) .. " -o " .. shell_quote(so_path)), "generated C bank should link as a shared object")

local log = read_file(dir .. "/generator.log")
local header = read_file(h_path)
local c_source = read_file(c_path)
local lua_source = read_file(lua_path)
assert(log:find("C-owned native template bank", 1, true), "generator should report a C-owned native template bank")
assert(header:find("LalinNativeBankArtifact", 1, true), "header should expose C-owned native bank artifact structs")
assert(header:find("lalin_native_bank_install", 1, true), "header should declare the C installer API")
assert(c_source:find("lalin_native_templates", 1, true), "C bank should carry native template entries")
assert(c_source:find("lalin_native_bank_select", 1, true), "C bank should own template selection")
assert(c_source:find("lalin_native_bank_install", 1, true), "C bank should own installation")
assert(lua_source:find("NativeBankArtifact", 1, true), "Lua bridge should construct only a NativeBankArtifact descriptor")
assert(not lua_source:find("NativeEmbeddedTemplateBank", 1, true), "Lua bridge must not construct NativeEmbeddedTemplateBank")
assert(lua_source:find("Code.CodeTyInt", 1, true), "Lua descriptor should preserve CodeType axes as ASDL manifest data")
assert(lua_source:find("Core.BinAdd", 1, true), "Lua descriptor should preserve Core operation axes as ASDL manifest data")
assert_no_forbidden_terms("generated C bridge", c_source)
assert_no_forbidden_terms("generated Lua bridge", lua_source)
assert(not c_source:find("lalin_install_embedded_native_bank", 1, true), "generator must not emit old embedded-bank install hooks")
assert(not c_source:find("lalin_mc_template_entries", 1, true), "generator must not emit old MC template manifests")

local artifact = dofile(lua_path)(T)
assert(asdl.isa(artifact, Native.NativeBankArtifact), tostring(artifact))
assert(artifact.manifest.total_count == request.manifest.total_count, "artifact should preserve manifest cardinality")
assert(artifact.template_count == #request.sources, "artifact should describe every generated source")
local loaded = NativeBackend.require_native_bank(artifact, request.target, request.manifest, so_path)
assert(asdl.isa(loaded, Native.NativeLoadedBank), tostring(loaded))

for _, source in ipairs(request.sources) do
    local key = Native.NativeTemplateSelectorKey(request.target, source.family)
    local selected = loaded:select_native_template(Native.NativeTemplateSelectionInput(loaded, key))
    assert(asdl.isa(selected, Native.NativeTemplateSelected), "expected C selector match for " .. source.family.id.text .. ": " .. tostring(selected))
    assert(selected.handle.family == source.family, "C selector should preserve the selected ASDL family")
end

io.write("native template source closure ok\n")
