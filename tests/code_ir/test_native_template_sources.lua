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
assert_source_manifest_closure("full host scalar bank request", full_request, full_domain, 3570)
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
    "native.code.inst.call.extern.native.runtime.add." .. abi_token,
}) do
    local source = abi_source(family_id)
    assert(source ~= nil, "ABI/call support domain should include " .. family_id)
    assert(asdl.isa(source.generator.chunk_class, Native.NativeChunkCallOp), family_id .. " should be a CallOp source")
end
assert_relocation_kinds(
    abi_source("native.code.inst.call.extern.native.runtime.add." .. abi_token),
    { Native.NativeTemplateRelocationHoleOrdinal, Native.NativeTemplateRelocationContinuation, Native.NativeTemplateRelocationRuntimeSymbol }
)

local request = Sources.bank_request_for_support_domain(i32_domain, Support.host_scalar_i32_bank_id())
assert_source_manifest_closure("i32 host scalar bank request", request, i32_domain, 269)
assert(#request.sources > 0, "scalar i32 support slice should be non-empty")

local required_families = {
    ["native.code.func.entry.i32.return.i32"] = true,
    ["native.code.func.entry.i32.return.bool8"] = true,
    ["native.code.inst.binary.i32.add"] = true,
    ["native.code.inst.binary.i32.sub"] = true,
    ["native.code.inst.binary.i32.mul"] = true,
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

local log = read_file(dir .. "/generator.log")
local header = read_file(h_path)
local c_source = read_file(c_path)
local lua_source = read_file(lua_path)
assert(log:find("embedded native template bank", 1, true), "generator should report a native template bank")
assert(header:find("LalinNativeEmbeddedTemplateBank", 1, true), "header should expose native embedded bank structs")
assert(c_source:find("lalin_native_template_entries", 1, true), "C bridge should carry raw native template entries")
assert(c_source:find("Runtime ASDL import uses the generated Lua bridge", 1, true), "C bridge should be marked as raw build data")
assert(lua_source:find("NativeEmbeddedTemplateBank", 1, true), "Lua bridge should construct NativeEmbeddedTemplateBank")
assert(lua_source:find("Code.CodeTyInt", 1, true), "Lua bridge should preserve CodeType axes as ASDL")
assert(lua_source:find("Core.BinAdd", 1, true), "Lua bridge should preserve Core operation axes as ASDL")
assert_no_forbidden_terms("generated C bridge", c_source)
assert_no_forbidden_terms("generated Lua bridge", lua_source)
assert(not c_source:find("lalin_install_embedded_native_bank", 1, true), "generator must not emit runtime install hooks")
assert(not c_source:find("lalin_mc_template_entries", 1, true), "generator must not emit old MC template manifests")

local embedded = dofile(lua_path)(T)
assert(embedded.manifest.total_count == request.manifest.total_count, "embedded bank should preserve manifest cardinality")
assert(#embedded.entries == #request.sources, "embedded bank should preserve every generated source")
local imported = Native.NativeEmbeddedBankImportRequest(embedded):import_native_bank()
assert(asdl.isa(imported, Native.NativeEmbeddedBankImported), tostring(imported))
assert(imported.bank.manifest.total_count == request.manifest.total_count, "imported bank should preserve native template manifest")
assert(#imported.bank.entries == #request.sources, "imported bank should contain every generated source")

for _, source in ipairs(request.sources) do
    local selected = imported.bank:select_native_template(Native.NativeTemplateSelectionInput(request.target, source.family))
    assert(asdl.isa(selected, Native.NativeTemplateSelected), "expected selection for " .. source.family.id.text .. ": " .. tostring(selected))
end

io.write("native template source closure ok\n")
