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

local dir = "target/test_artifacts/test_native_code_graph_scalar"
assert(command_ok("rm -rf " .. shell_quote(dir)))
assert(command_ok("mkdir -p " .. shell_quote(dir)))
local manifest_path = dir .. "/manifest.lua"
local mf = assert(io.open(manifest_path, "wb"))
mf:write([[return function(T)
  return require('lalin.native_template_sources')(T).host_scalar_bank_request()
end
]])
mf:close()

local c_path = dir .. "/bank.c"
local h_path = dir .. "/bank.h"
local lua_path = dir .. "/bank.lua"
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

local generated_lua = read_file(lua_path)
local generated_c = read_file(c_path)
assert(not generated_lua:lower():find("residual", 1, true), "native scalar generated Lua must not mention residual")
assert(not generated_lua:find("LuaJIT", 1, true), "native scalar generated Lua must not mention LuaJIT")
assert(not generated_c:lower():find("residual", 1, true), "native scalar generated C must not mention residual")
assert(not generated_c:find("LuaJIT", 1, true), "native scalar generated C must not mention LuaJIT")

local request = Sources.host_scalar_bank_request()
for _, source in ipairs(request.sources) do
    if asdl.isa(source.family.role, Native.NativeRoleCodeInst) then
        assert(asdl.isa(source.extraction, Native.NativeExtractContinuationFragment), "CodeInst source must be a C continuation fragment: " .. source.family.id.text)
        assert(source.c_text:find("uint8_t %*frame", 1, false), "CodeInst source must use the C frame protocol: " .. source.family.id.text)
    end
    if asdl.isa(source.family.role, Native.NativeRoleCodeTerm) then
        assert(asdl.isa(source.extraction, Native.NativeExtractTerminalContinuation), "CodeTerm return source should be a terminal C continuation: " .. source.family.id.text)
    end
end

local target = NativeBackend.host_target()
local runtime = NativeBackend.empty_runtime()
local embedded = dofile(lua_path)(T)
local bank = NativeBackend.require_imported_bank(embedded)
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

local function assert_typed_graph(func)
    local graph = func:plan_native_copy(Native.NativePlanInput(target, runtime, bank))
    assert(asdl.isa(graph, Native.NativeTemplateGraph), "plan_native_copy should return a NativeTemplateGraph")
    assert(asdl.isa(graph.protocol, Native.NativeCallReturnScalar), "scalar graph should carry a graph-level scalar call protocol")
    local saw_input, saw_output, saw_typed_frame_slot, saw_continuation = false, false, false, false
    for _, node in ipairs(graph.nodes) do
        for _, placement in ipairs(node.inputs) do
            assert(asdl.isa(placement, Native.NativeValuePlacement), "node input should be a NativeValuePlacement")
            if placement.location.slot ~= nil then
                assert(asdl.isa(placement.location.slot, Native.NativeFrameSlot), "node input frame slot should be typed")
                saw_typed_frame_slot = true
            end
            saw_input = true
        end
        for _, placement in ipairs(node.outputs) do
            assert(asdl.isa(placement, Native.NativeValuePlacement), "node output should be a NativeValuePlacement")
            if placement.location.slot ~= nil then
                assert(asdl.isa(placement.location.slot, Native.NativeFrameSlot), "node output frame slot should be typed")
                saw_typed_frame_slot = true
            end
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
    assert(saw_input and saw_output and saw_typed_frame_slot and saw_continuation, "graph should expose typed frame slots and continuations")
    return graph
end

local function compile_call(func, args)
    assert_typed_graph(func)
    local result = NativeBackend.compile_code_func(func, target, runtime, bank)
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
