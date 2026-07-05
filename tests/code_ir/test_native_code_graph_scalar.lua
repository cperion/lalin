package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
if ffi.arch ~= "x64" or ffi.os == "Windows" or not ffi.abi("64bit") or not ffi.abi("le") then
    io.write("skip native scalar graph: requires x64 non-Windows little-endian 64-bit host\n")
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

local T = asdl.context()
Schema(T)
local Native = T.LalinNative
local Code = T.LalinCode
local Core = T.LalinCore
local NativeBackend = require("lalin.native_backend")(T)
local Sources = require("lalin.native_template_sources")(T)
local Support = require("lalin.native_template_support")(T)

local scalar_validation_bank_request_source = [[return function(T)
  local Sources = require('lalin.native_template_sources')(T)
  local Support = require('lalin.native_template_support')(T)
  local Native = T.LalinNative
  local target = Support.host_target()
  local scalars = Support.host_scalar_reps()
  local adapters = Support.default_scalar_public_abi_adapters(target, scalars)
  local i32_scalar = Support.scalar_i32()
  local f64_scalar = Support.scalar_f64()
  local i32_abi = Support.abi_scalar_value(i32_scalar)
  local f64_abi = Support.abi_scalar_value(f64_scalar)
  adapters[#adapters + 1] = Support.abi_function_projection(target, {
    Support.abi_param_projection(0, i32_scalar:native_code_type(), i32_abi),
    Support.abi_param_projection(1, f64_scalar:native_code_type(), f64_abi),
  }, Support.abi_result_projection(i32_scalar:native_code_type(), i32_abi))
  adapters[#adapters + 1] = Support.abi_function_projection(target, {}, Support.abi_result_projection(nil, Native.NativeAbiVoidResult))
  local domain = Support.support_domain(
    Support.host_template_support_domain_id('scalar-validation'),
    target,
    Support.empty_runtime(),
    scalars,
    adapters
  )
  return Sources.bank_request_for_support_domain(domain, Support.bank_id_for_support_domain(domain))
end
]]

local scalar_validation_bank_request = assert(loadstring(scalar_validation_bank_request_source, "@native_scalar_validation_bank_request"))()
local request = scalar_validation_bank_request(T)
local validation_frame_stack_limit = Support.x64_sysv_frame_stack_limit()
assert(Support.spill_all_passthrough_int_limit() == 0, "scalar validation bank must use spill-all K_int=0")
assert(Support.spill_all_passthrough_float_limit() == 0, "scalar validation bank must use spill-all K_float=0")
assert(validation_frame_stack_limit.max_bytes == 256, "scalar validation bank must carry an explicit frame stack limit")
assert(validation_frame_stack_limit.alignment == 16, "scalar validation bank frame limit should preserve x64 SysV alignment")

local dir = "target/test_artifacts/test_native_code_graph_scalar"
assert(command_ok("rm -rf " .. shell_quote(dir)))
assert(command_ok("mkdir -p " .. shell_quote(dir)))
local manifest_path = dir .. "/manifest.lua"
local mf = assert(io.open(manifest_path, "wb"))
mf:write(scalar_validation_bank_request_source)
mf:close()

local c_path = dir .. "/bank.c"
local h_path = dir .. "/bank.h"
local lua_path = dir .. "/bank.lua"
local so_path = dir .. "/bank.so"
local cmd = table.concat({
    "luajit tools/gen_lalin_mc_bank.lua",
    shell_quote(c_path),
    shell_quote(h_path),
    shell_quote(lua_path),
    shell_quote(manifest_path),
    ">", shell_quote(dir .. "/generator.out"),
    "2>", shell_quote(dir .. "/generator.log"),
}, " ")
assert(command_ok(cmd), "native scalar bank generator should build the full scalar support domain")
assert(command_ok("gcc -shared -fPIC " .. shell_quote(c_path) .. " -o " .. shell_quote(so_path)), "native scalar C-owned bank should link as a shared object")

local generated_lua = read_file(lua_path)
local generated_c = read_file(c_path)
assert(not generated_lua:lower():find("residual", 1, true), "native scalar generated Lua must not mention residual")
assert(not generated_lua:find("LuaJIT", 1, true), "native scalar generated Lua must not mention LuaJIT")
assert(not generated_c:lower():find("residual", 1, true), "native scalar generated C must not mention residual")
assert(not generated_c:find("LuaJIT", 1, true), "native scalar generated C must not mention LuaJIT")

for _, source in ipairs(request.sources) do
    if asdl.isa(source.family.role, Native.NativeRoleCodeInst) then
        assert(asdl.isa(source.extraction, Native.NativeExtractContinuationFragment), "CodeInst source must be a C continuation fragment: " .. source.family.id.text)
        assert(source.c_text:find("uint8_t %*frame", 1, false), "CodeInst source must use the C frame protocol: " .. source.family.id.text)
    end
    if asdl.isa(source.family.role, Native.NativeRoleCodeTerm) then
        if asdl.isa(source.generator.chunk_class, Native.NativeChunkTerminalContinuation) then
            assert(asdl.isa(source.extraction, Native.NativeExtractTerminalContinuation), "CodeTerm return source should be a terminal C continuation: " .. source.family.id.text)
        elseif asdl.isa(source.generator.chunk_class, Native.NativeChunkControlOp) then
            assert(asdl.isa(source.extraction, Native.NativeExtractContinuationFragment) or asdl.isa(source.extraction, Native.NativeExtractTerminalContinuation), "CodeTerm control source should be a continuation or terminal control stencil: " .. source.family.id.text)
        end
    end
end

local target = NativeBackend.host_target()
local runtime = NativeBackend.empty_runtime()

local i32_abi_sig = Code.CodeSig(Code.CodeSigId("native.abi.i32"), { Code.CodeTyInt(32, Code.CodeSigned), Code.CodeTyDataPtr(Code.CodeTyInt(32, Code.CodeSigned)) }, { Code.CodeTyInt(32, Code.CodeSigned) })
local i32_projection = i32_abi_sig:native_abi_projection(target)
assert(asdl.isa(i32_projection.result.abi, Native.NativeAbiScalarValue), "scalar CodeSig result should lower to a scalar ABI result")
assert(#i32_projection.params == 2, "scalar CodeSig params should preserve explicit params without hidden sret")
local void_projection = Code.CodeSig(Code.CodeSigId("native.abi.void"), { Code.CodeTyInt(32, Code.CodeSigned) }, {}):native_abi_projection(target)
assert(asdl.isa(void_projection.result.abi, Native.NativeAbiVoidResult), "zero-result CodeSig should lower to a void ABI result")
assert(#void_projection.params == 1, "zero-result CodeSig should preserve explicit params")
assert(void_projection.result:native_code_result_shape() == Native.NativeCodeResultVoidShape, "void ABI projection should own a void Code result shape")
assert(i32_abi_sig:native_code_result_shape(target):native_code_result_shape_equals(Native.NativeCodeResultScalarShape(Support.scalar_i32())), "CodeSig result shape should be derived from its ABI projection")
local slice_projection = Code.CodeTySlice(Code.CodeTyInt(32, Code.CodeSigned)):native_abi_projection(target)
assert(asdl.isa(slice_projection, Native.NativeAbiDescriptorValue), "CodeTySlice should lower to a descriptor ABI projection")
assert(asdl.isa(slice_projection:native_code_result_shape(), Native.NativeCodeResultDescriptorShape), "descriptor ABI projections should own descriptor Code result shapes")
assert(#slice_projection.fields == 2, "slice descriptor projection should carry data/len fields")
local aggregate_sig = Code.CodeSig(Code.CodeSigId("native.abi.aggregate"), { Code.CodeTyIndex }, { Code.CodeTyArray(Code.CodeTyInt(32, Code.CodeSigned), 4) })
local aggregate_projection = aggregate_sig:native_abi_projection(target)
assert(asdl.isa(aggregate_projection.result.abi, Native.NativeAbiSRetResult), "aggregate result should lower through sret")
assert(#aggregate_projection.params == 2 and aggregate_projection.params[1].param_index == 0, "sret result should insert hidden pointer parameter before explicit params")
local extern_projection = Code.CodeCallExtern(Code.CodeExternId("native.abi.extern")):select_native_call_projection(i32_abi_sig, target)
assert(extern_projection.result.abi:native_abi_projection_equals(i32_projection.result.abi), "CodeCallTarget leaves should select the supplied CodeSig ABI projection")
assert(Code.CodeCallDirect(Code.CodeFuncId("native.abi.direct")):native_code_call_shape() == Native.NativeCodeCallDirectTarget, "direct call target leaf should own its native call shape")
assert(Code.CodeCallExtern(Code.CodeExternId("native.abi.extern")):native_code_call_shape() == Native.NativeCodeCallExternTarget, "extern call target leaf should own its native call shape")
assert(Code.CodeCallIndirect(Code.CodeValueId("native.abi.fn"), i32_abi_sig.id):native_code_call_shape() == Native.NativeCodeCallIndirectPointer, "indirect call target leaf should own its native call shape")
assert(Code.CodeCallClosure(Code.CodeValueId("native.abi.closure"), i32_abi_sig.id):native_code_call_shape() == Native.NativeCodeCallClosurePointer, "closure call target leaf should own its native call shape")
local ok_multi_result, err_multi_result = pcall(function()
    Code.CodeSig(Code.CodeSigId("native.abi.bad"), {}, { Code.CodeTyIndex, Code.CodeTyIndex }):native_abi_projection(target)
end)
assert(not ok_multi_result and tostring(err_multi_result):find("zero or one result", 1, true), "native ABI projection must reject multi-result CodeSig values")

local artifact = dofile(lua_path)(T)
assert(asdl.isa(artifact, Native.NativeBankArtifact), tostring(artifact))
local bank = NativeBackend.require_native_bank(artifact, target, request.manifest, so_path)
local origin = Code.CodeOriginUnknown

local function int_semantics()
    return Code.CodeIntSemantics(Code.CodeIntWrap, Code.CodeDivTrapOnZero, Code.CodeShiftMaskCount)
end

local function scalar_binary_func(name, ty, op)
    local a = Code.CodeValueId(name .. ".a")
    local b = Code.CodeValueId(name .. ".b")
    local dst = Code.CodeValueId(name .. ".dst")
    local inst = Code.CodeInst(
        Code.CodeInstId(name .. ".inst"),
        Code.CodeInstBinary(dst, op, ty, int_semantics(), a, b),
        origin
    )
    local term = Code.CodeTerm(Code.CodeTermId(name .. ".term"), Code.CodeTermReturn({ dst }), origin)
    local block_id = Code.CodeBlockId(name .. ".entry")
    local block = Code.CodeBlock(block_id, "entry", {}, { inst }, term, origin)
    return Code.CodeFunc(
        Code.CodeFuncId(name),
        name,
        Code.CodeLinkageExport,
        Code.CodeSigId(name .. ".sig"),
        { Code.CodeParam(a, "a", ty, origin), Code.CodeParam(b, "b", ty, origin) },
        {},
        block_id,
        { block },
        origin
    )
end

local function float_binary_func(name, ty, op)
    local a = Code.CodeValueId(name .. ".a")
    local b = Code.CodeValueId(name .. ".b")
    local dst = Code.CodeValueId(name .. ".dst")
    local inst = Code.CodeInst(
        Code.CodeInstId(name .. ".inst"),
        Code.CodeInstFloatBinary(dst, op, ty, Code.CodeFloatStrict, a, b),
        origin
    )
    local term = Code.CodeTerm(Code.CodeTermId(name .. ".term"), Code.CodeTermReturn({ dst }), origin)
    local block_id = Code.CodeBlockId(name .. ".entry")
    local block = Code.CodeBlock(block_id, "entry", {}, { inst }, term, origin)
    return Code.CodeFunc(
        Code.CodeFuncId(name),
        name,
        Code.CodeLinkageExport,
        Code.CodeSigId(name .. ".sig"),
        { Code.CodeParam(a, "a", ty, origin), Code.CodeParam(b, "b", ty, origin) },
        {},
        block_id,
        { block },
        origin
    )
end

local function compare_func(name, operand_ty, cmp)
    local a = Code.CodeValueId(name .. ".a")
    local b = Code.CodeValueId(name .. ".b")
    local dst = Code.CodeValueId(name .. ".dst")
    local inst = Code.CodeInst(Code.CodeInstId(name .. ".inst"), Code.CodeInstCompare(dst, cmp, operand_ty, a, b), origin)
    local term = Code.CodeTerm(Code.CodeTermId(name .. ".term"), Code.CodeTermReturn({ dst }), origin)
    local block_id = Code.CodeBlockId(name .. ".entry")
    local block = Code.CodeBlock(block_id, "entry", {}, { inst }, term, origin)
    return Code.CodeFunc(
        Code.CodeFuncId(name),
        name,
        Code.CodeLinkageExport,
        Code.CodeSigId(name .. ".sig"),
        { Code.CodeParam(a, "a", operand_ty, origin), Code.CodeParam(b, "b", operand_ty, origin) },
        {},
        block_id,
        { block },
        origin
    )
end

local function const_return_func(name, ty, const)
    local dst = Code.CodeValueId(name .. ".dst")
    local inst = Code.CodeInst(Code.CodeInstId(name .. ".const"), Code.CodeInstConst(dst, const), origin)
    local term = Code.CodeTerm(Code.CodeTermId(name .. ".term"), Code.CodeTermReturn({ dst }), origin)
    local block_id = Code.CodeBlockId(name .. ".entry")
    local block = Code.CodeBlock(block_id, "entry", {}, { inst }, term, origin)
    local func = Code.CodeFunc(Code.CodeFuncId(name), name, Code.CodeLinkageExport, Code.CodeSigId(name .. ".sig"), {}, {}, block_id, { block }, origin)
    return func, Code.CodeSig(func.sig, {}, { ty })
end

local function alias_return_func(name, ty)
    local src = Code.CodeValueId(name .. ".src")
    local dst = Code.CodeValueId(name .. ".dst")
    local inst = Code.CodeInst(Code.CodeInstId(name .. ".alias"), Code.CodeInstAlias(dst, ty, src), origin)
    local term = Code.CodeTerm(Code.CodeTermId(name .. ".term"), Code.CodeTermReturn({ dst }), origin)
    local block_id = Code.CodeBlockId(name .. ".entry")
    local block = Code.CodeBlock(block_id, "entry", {}, { inst }, term, origin)
    local func = Code.CodeFunc(Code.CodeFuncId(name), name, Code.CodeLinkageExport, Code.CodeSigId(name .. ".sig"), { Code.CodeParam(src, "src", ty, origin) }, {}, block_id, { block }, origin)
    return func, Code.CodeSig(func.sig, { ty }, { ty })
end

local function mixed_alias_func(name, int_ty, float_ty)
    local src = Code.CodeValueId(name .. ".src")
    local ignored = Code.CodeValueId(name .. ".ignored")
    local dst = Code.CodeValueId(name .. ".dst")
    local inst = Code.CodeInst(Code.CodeInstId(name .. ".alias"), Code.CodeInstAlias(dst, int_ty, src), origin)
    local term = Code.CodeTerm(Code.CodeTermId(name .. ".term"), Code.CodeTermReturn({ dst }), origin)
    local block_id = Code.CodeBlockId(name .. ".entry")
    local block = Code.CodeBlock(block_id, "entry", {}, { inst }, term, origin)
    local func = Code.CodeFunc(Code.CodeFuncId(name), name, Code.CodeLinkageExport, Code.CodeSigId(name .. ".sig"), { Code.CodeParam(src, "src", int_ty, origin), Code.CodeParam(ignored, "ignored", float_ty, origin) }, {}, block_id, { block }, origin)
    return func, Code.CodeSig(func.sig, { int_ty, float_ty }, { int_ty })
end

local function void_func(name, params)
    params = params or {}
    local block_id = Code.CodeBlockId(name .. ".entry")
    local term = Code.CodeTerm(Code.CodeTermId(name .. ".term"), Code.CodeTermReturn({}), origin)
    local code_params = {}
    local sig_params = {}
    for i, param in ipairs(params) do
        code_params[#code_params + 1] = Code.CodeParam(param.value, param.name, param.ty, origin)
        sig_params[#sig_params + 1] = param.ty
    end
    local block = Code.CodeBlock(block_id, "entry", {}, {}, term, origin)
    local func = Code.CodeFunc(Code.CodeFuncId(name), name, Code.CodeLinkageExport, Code.CodeSigId(name .. ".sig"), code_params, {}, block_id, { block }, origin)
    return func, Code.CodeSig(func.sig, sig_params, {})
end

local function signature_for_func(func)
    local params = {}
    for _, param in ipairs(func.params or {}) do params[#params + 1] = param.ty end
    local results = {}
    for _, block in ipairs(func.blocks or {}) do
        if block.id == func.entry then
            local value = block.term.op.values and block.term.op.values[1]
            if value ~= nil then
                for _, inst in ipairs(block.insts or {}) do
                    if inst.op.dst == value and inst.op.ty ~= nil then
                        results[#results + 1] = inst.op.ty
                    elseif inst.op.dst == value and inst.op.const ~= nil then
                        results[#results + 1] = inst.op.const.ty
                    elseif inst.op.dst == value and asdl.isa(inst.op, Code.CodeInstCompare) then
                        results[#results + 1] = Code.CodeTyBool8
                    end
                end
            end
        end
    end
    return Code.CodeSig(func.sig, params, results)
end

local function assert_frame_slot_order(layout, func_id)
    assert(layout.size % layout.alignment == 0, "frame layout size must be aligned")
    assert(layout.size <= validation_frame_stack_limit.max_bytes, "frame layout must fit the support-domain NativeFrameStackLimit")
    assert(layout.alignment == validation_frame_stack_limit.alignment, "frame layout alignment should match NativeFrameStackLimit")
    local last_offset = -1
    local last_end = 0
    local first_result_offset, first_temp_offset
    local last_param_offset = -1
    for _, slot in ipairs(layout.slots or {}) do
        assert(slot.offset >= last_offset, "frame slots should be emitted in deterministic nondecreasing offset order")
        assert(slot.offset % slot.alignment == 0, "frame slot offsets should respect slot alignment")
        assert(slot.offset >= last_end, "frame slots should not overlap")
        last_offset = slot.offset
        last_end = slot.offset + slot.size
        local id_text = slot.id.text
        if id_text:find(".param", 1, true) then
            assert(first_result_offset == nil and first_temp_offset == nil, "ABI parameter frame slots must precede result and temporary slots")
            last_param_offset = slot.offset
        elseif id_text:find("native.frame.result." .. func_id.text, 1, true) then
            first_result_offset = first_result_offset or slot.offset
            assert(slot.offset >= last_param_offset, "direct result slot should follow ABI parameter slots")
        else
            first_temp_offset = first_temp_offset or slot.offset
            if first_result_offset ~= nil then assert(slot.offset >= first_result_offset, "temporary value slots should follow direct result slots") end
        end
    end
end

local function assert_typed_graph(func, signature)
    signature = signature or signature_for_func(func)
    local graph = func:plan_native_copy(Native.NativePlanInput(target, runtime, bank), nil, signature)
    local projection = signature:native_abi_projection(target)
    assert(asdl.isa(graph, Native.NativeTemplateGraph), "plan_native_copy should return a NativeTemplateGraph")
    assert(asdl.isa(graph.protocol, Native.NativeCallCodeSig), "scalar graph should carry a graph-level CodeSig ABI call protocol")
    assert(graph.protocol.projection:native_abi_function_projection_equals(projection), "graph call protocol should be the CodeSig-owned NativeAbiFunctionProjection")
    assert_frame_slot_order(graph.frame_layout, func.id)
    local saw_input, saw_output, saw_typed_frame_slot, saw_continuation = false, false, false, false
    for _, node in ipairs(graph.nodes) do
        assert(asdl.isa(node.instance, Native.NativeTemplateInstanceId), "template nodes should carry node-local instance ids")
        for _, binding in ipairs(node.bindings or {}) do
            assert(binding.node == node.id, "patch bindings must be scoped to the owning node")
            assert(binding.instance == node.instance, "patch bindings must be scoped to the owning template instance")
            assert(asdl.isa(binding.target, Native.NativePatchBindingHoleId) or asdl.isa(binding.target, Native.NativePatchBindingHoleOrdinal), "generated scalar graph bindings should use typed hole binding targets")
        end
        for _, placement in ipairs(node.inputs) do
            assert(asdl.isa(placement, Native.NativeValuePlacement), "node input should be a NativeValuePlacement")
            assert(asdl.isa(placement.location, Native.NativeValueFrameSlotLocation), "spill-all K=0 node inputs must be frame-slot locations")
            assert(asdl.isa(placement.location.slot, Native.NativeFrameSlot), "node input frame slot should be typed")
            saw_typed_frame_slot = true
            saw_input = true
        end
        for _, placement in ipairs(node.outputs) do
            assert(asdl.isa(placement, Native.NativeValuePlacement), "node output should be a NativeValuePlacement")
            assert(asdl.isa(placement.location, Native.NativeValueFrameSlotLocation), "spill-all K=0 node outputs must be frame-slot locations")
            assert(asdl.isa(placement.location.slot, Native.NativeFrameSlot), "node output frame slot should be typed")
            saw_typed_frame_slot = true
            saw_output = true
        end
    end
    for _, edge in ipairs(graph.value_edges) do
        if asdl.isa(edge, Native.NativeFrameSlotValueEdge) then
            assert(asdl.isa(edge.slot, Native.NativeFrameSlot), "frame value edges should use typed NativeFrameSlot values")
            saw_typed_frame_slot = true
        end
    end
    for _, edge in ipairs(graph.control_edges) do
        if asdl.isa(edge, Native.NativeContinuationEdge) then
            assert(asdl.isa(edge.symbol, Native.NativeContinuationSymbol), "continuation edges should carry typed continuation symbols")
            saw_continuation = true
        end
    end
    if #(signature.results or {}) > 0 then
        assert(saw_output, "non-void graphs should expose typed output placements")
    end
    local expects_frame_values = #(signature.params or {}) > 0 or #(signature.results or {}) > 0 or #(graph.value_edges or {}) > 0
    if expects_frame_values then
        assert(saw_typed_frame_slot or #(graph.frame_layout.slots or {}) > 0, "graphs with values should expose typed frame slots")
    else
        assert(#(graph.frame_layout.slots or {}) == 0, "zero-param void graphs should not allocate hidden frame slots")
    end
    assert(saw_continuation, "graph should expose typed continuations")
    return graph
end

local function compile_call(func, args, signature)
    signature = signature or signature_for_func(func)
    assert_typed_graph(func, signature)
    local result = NativeBackend.compile_code_func(func, signature, target, runtime, bank)
    assert(result.executable.protocol:native_call_protocol_equals(Support.native_call_code_sig(signature:native_abi_projection(target))), "compiled executable should call via typed CodeSig ABI projection")
    return result.executable.protocol:call_native_executable(Native.NativeExecutableCallInput(result.executable, args))
end

local i8 = Code.CodeTyInt(8, Code.CodeSigned)
local u8 = Code.CodeTyInt(8, Code.CodeUnsigned)
local i16 = Code.CodeTyInt(16, Code.CodeSigned)
local u16 = Code.CodeTyInt(16, Code.CodeUnsigned)
local i32 = Code.CodeTyInt(32, Code.CodeSigned)
local u32 = Code.CodeTyInt(32, Code.CodeUnsigned)
local i64 = Code.CodeTyInt(64, Code.CodeSigned)
local u64 = Code.CodeTyInt(64, Code.CodeUnsigned)
local bool8 = Code.CodeTyBool8
local f32 = Code.CodeTyFloat(32)
local f64 = Code.CodeTyFloat(64)
local ptr = Code.CodeTyDataPtr(nil)

local slice_storage = Code.CodeTySlice(i32):native_storage_layout(target)
assert(asdl.isa(slice_storage.representation, Native.NativeDescriptorValueRepresentation), "descriptor Code types should expose NativeDescriptorValueRepresentation")
assert(#slice_storage.representation.fields == 2, "descriptor representations should carry typed fields")
local aggregate_storage = Code.CodeTyArray(i32, 3):native_storage_layout(target)
assert(asdl.isa(aggregate_storage.representation, Native.NativeAggregateStorageRepresentation), "aggregate Code types should expose NativeAggregateStorageRepresentation")
assert(aggregate_storage.representation.element_count == 3, "aggregate representations should carry element counts")
local address_representation = Native.NativeAddressValueRepresentation(Support.scalar_pointer(target.pointer_bits), Native.NativeCodeLocalAddressTarget(Code.CodeLocalId("native.scalar.address.local"), i32))
assert(asdl.isa(address_representation, Native.NativeAddressValueRepresentation), "address values should have explicit NativeAddressValueRepresentation")

local zero_param_func, zero_param_sig = const_return_func("native.scalar.zero_param.const", i32, Code.CodeConstLiteral(i32, Core.LitInt("42")))
local zero_param = compile_call(zero_param_func, {}, zero_param_sig)
assert(asdl.isa(zero_param, Native.NativeCallReturnedI32) and zero_param.value == 42, "zero-param scalar entry should call through an explicit ABI projection")
local one_param_func, one_param_sig = alias_return_func("native.scalar.one_param.alias", i32)
local one_param = compile_call(one_param_func, { Native.NativeCallArgI32(77) }, one_param_sig)
assert(asdl.isa(one_param, Native.NativeCallReturnedI32) and one_param.value == 77, "one-param scalar entry should preserve typed ABI params")
local mixed_func, mixed_sig = mixed_alias_func("native.scalar.mixed_i32_f64.alias", i32, f64)
local mixed = compile_call(mixed_func, { Native.NativeCallArgI32(12), Native.NativeCallArgF64(99.5) }, mixed_sig)
assert(asdl.isa(mixed, Native.NativeCallReturnedI32) and mixed.value == 12, "two-param mixed scalar ABI adapters should use per-param ABI projections")
local void0_func, void0_sig = void_func("native.scalar.void0", {})
local void0 = compile_call(void0_func, {}, void0_sig)
assert(asdl.isa(void0, Native.NativeCallReturnedVoid), "zero-param void return should execute without scalar result shims")
local void1_func, void1_sig = void_func("native.scalar.void1", { { value = Code.CodeValueId("native.scalar.void1.arg"), name = "arg", ty = i32 } })
local void1 = compile_call(void1_func, { Native.NativeCallArgI32(5) }, void1_sig)
assert(asdl.isa(void1, Native.NativeCallReturnedVoid), "one-param void return should execute through a void NativeAbiProjection")
local ptr_null_func, ptr_null_sig = const_return_func("native.scalar.ptr.null", ptr, Code.CodeConstNull(ptr))
local ptr_graph = assert_typed_graph(ptr_null_func, ptr_null_sig)
assert(asdl.isa(ptr_graph.protocol.projection.result.abi, Native.NativeAbiPointerValue), "pointer returns should plan through pointer ABI projection")

local i8_wrap = compile_call(scalar_binary_func("native.scalar.i8.wrap", i8, Core.BinAdd), { Native.NativeCallArgI32(120), Native.NativeCallArgI32(10) })
assert(asdl.isa(i8_wrap, Native.NativeCallReturnedI32) and i8_wrap.value == -126, "i8 add should return through exact int8_t ABI")
local u8_wrap = compile_call(scalar_binary_func("native.scalar.u8.wrap", u8, Core.BinAdd), { Native.NativeCallArgI32(250), Native.NativeCallArgI32(10) })
assert(asdl.isa(u8_wrap, Native.NativeCallReturnedI32) and u8_wrap.value == 4, "u8 add should return through exact uint8_t ABI")
local i16_wrap = compile_call(scalar_binary_func("native.scalar.i16.wrap", i16, Core.BinAdd), { Native.NativeCallArgI32(32760), Native.NativeCallArgI32(10) })
assert(asdl.isa(i16_wrap, Native.NativeCallReturnedI32) and i16_wrap.value == -32766, "i16 add should return through exact int16_t ABI")
local u16_wrap = compile_call(scalar_binary_func("native.scalar.u16.wrap", u16, Core.BinAdd), { Native.NativeCallArgI32(65530), Native.NativeCallArgI32(10) })
assert(asdl.isa(u16_wrap, Native.NativeCallReturnedI32) and u16_wrap.value == 4, "u16 add should return through exact uint16_t ABI")

local i32_add = compile_call(scalar_binary_func("native.scalar.i32.add", i32, Core.BinAdd), { Native.NativeCallArgI32(3), Native.NativeCallArgI32(4) })
assert(asdl.isa(i32_add, Native.NativeCallReturnedI32) and i32_add.value == 7, "i32 add should execute")
local i32_sub = compile_call(scalar_binary_func("native.scalar.i32.sub", i32, Core.BinSub), { Native.NativeCallArgI32(9), Native.NativeCallArgI32(4) })
assert(asdl.isa(i32_sub, Native.NativeCallReturnedI32) and i32_sub.value == 5, "i32 sub should execute")
local i32_mul = compile_call(scalar_binary_func("native.scalar.i32.mul", i32, Core.BinMul), { Native.NativeCallArgI32(6), Native.NativeCallArgI32(7) })
assert(asdl.isa(i32_mul, Native.NativeCallReturnedI32) and i32_mul.value == 42, "i32 mul should execute")
local i32_wrap = compile_call(scalar_binary_func("native.scalar.i32.wrap", i32, Core.BinAdd), { Native.NativeCallArgI32(2147483647), Native.NativeCallArgI32(1) })
assert(asdl.isa(i32_wrap, Native.NativeCallReturnedI32) and i32_wrap.value == -2147483648, "i32 add should wrap")

local u32_add = compile_call(scalar_binary_func("native.scalar.u32.add", u32, Core.BinAdd), { Native.NativeCallArgI32(4000000000), Native.NativeCallArgI32(5) })
assert(asdl.isa(u32_add, Native.NativeCallReturnedI32) and u32_add.value == 4000000005, "u32 add should return through exact uint32_t ABI")

local i64_add = compile_call(scalar_binary_func("native.scalar.i64.add", i64, Core.BinAdd), { Native.NativeCallArgI64(10), Native.NativeCallArgI64(20) })
assert(asdl.isa(i64_add, Native.NativeCallReturnedI64) and i64_add.value == 30, "i64 add should execute")
local i64_sub = compile_call(scalar_binary_func("native.scalar.i64.sub", i64, Core.BinSub), { Native.NativeCallArgI64(50), Native.NativeCallArgI64(8) })
assert(asdl.isa(i64_sub, Native.NativeCallReturnedI64) and i64_sub.value == 42, "i64 sub should execute")
local u64_add = compile_call(scalar_binary_func("native.scalar.u64.add", u64, Core.BinAdd), { Native.NativeCallArgI64(4000000000), Native.NativeCallArgI64(5) })
assert(asdl.isa(u64_add, Native.NativeCallReturnedI64) and u64_add.value == 4000000005, "u64 add should return through exact uint64_t ABI")
local index_add = compile_call(scalar_binary_func("native.scalar.index.add", Code.CodeTyIndex, Core.BinAdd), { Native.NativeCallArgI64(40), Native.NativeCallArgI64(2) })
assert(asdl.isa(index_add, Native.NativeCallReturnedI64) and index_add.value == 42, "index add should execute through pointer-width index ABI")

local bool_cmp = compile_call(compare_func("native.scalar.bool.eq", bool8, Core.CmpEq), { Native.NativeCallArgI32(1), Native.NativeCallArgI32(1) })
assert(asdl.isa(bool_cmp, Native.NativeCallReturnedI32) and bool_cmp.value == 1, "bool8 compare should execute")
local cmp = compile_call(compare_func("native.scalar.i32.lt", i32, Core.CmpLt), { Native.NativeCallArgI32(3), Native.NativeCallArgI32(4) })
assert(asdl.isa(cmp, Native.NativeCallReturnedI32) and cmp.value == 1, "i32 compare should produce bool8 true as i32-compatible result")
local cmp_false = compile_call(compare_func("native.scalar.i32.lt.false", i32, Core.CmpLt), { Native.NativeCallArgI32(5), Native.NativeCallArgI32(4) })
assert(asdl.isa(cmp_false, Native.NativeCallReturnedI32) and cmp_false.value == 0, "i32 compare should produce bool8 false as i32-compatible result")

local f32_add = compile_call(float_binary_func("native.scalar.f32.add", f32, Core.BinAdd), { Native.NativeCallArgF64(1.5), Native.NativeCallArgF64(2.25) })
assert(asdl.isa(f32_add, Native.NativeCallReturnedF64) and math.abs(f32_add.value - 3.75) < 1e-6, "f32 add should execute through exact float ABI")
local f64_add = compile_call(float_binary_func("native.scalar.f64.add", f64, Core.BinAdd), { Native.NativeCallArgF64(1.5), Native.NativeCallArgF64(2.25) })
assert(asdl.isa(f64_add, Native.NativeCallReturnedF64) and math.abs(f64_add.value - 3.75) < 1e-9, "f64 add should execute")

io.write("native scalar code graph ok\n")
