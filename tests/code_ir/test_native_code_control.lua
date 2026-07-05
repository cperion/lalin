package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
if ffi.arch ~= "x64" or ffi.os == "Windows" or not ffi.abi("64bit") or not ffi.abi("le") then
    io.write("skip native code control: requires x64 non-Windows little-endian 64-bit host\n")
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

local T = asdl.context()
Schema(T)
local Native = T.LalinNative
local Code = T.LalinCode
local Core = T.LalinCore
local NativeBackend = require("lalin.native_backend")(T)
local Support = require("lalin.native_template_support")(T)

local bank_request_source = [[return function(T)
  require('lalin.native_code_methods')(T)
  local Sources = require('lalin.native_template_sources')(T)
  local Support = require('lalin.native_template_support')(T)
  local Native = T.LalinNative
  local Code = T.LalinCode
  local target = Support.host_target()
  local i32 = Code.CodeTyInt(32, Code.CodeSigned)
  local bool8 = Code.CodeTyBool8
  local call_sig_id = Code.CodeSigId('native.control.call.sig')
  local closure_ty = Code.CodeTyClosure(call_sig_id)
  local code_ptr_ty = Code.CodeTyCodePtr(call_sig_id)
  local i32_scalar = Support.scalar_i32()
  local bool_scalar = Support.scalar_bool8()
  local ptr_scalar = Support.scalar_pointer(target.pointer_bits)
  local i32_abi = Support.abi_scalar_value(i32_scalar)
  local bool_abi = Support.abi_scalar_value(bool_scalar)
  local ptr_abi = Support.abi_pointer_value(ptr_scalar)
  local closure_abi = closure_ty:native_abi_projection(target)
  local function param(index, ty, abi) return Support.abi_param_projection(index, ty, abi) end
  local function result(ty, abi) return Support.abi_result_projection(ty, abi) end
  local adapters = {
    Support.abi_function_projection(target, { param(0, i32, i32_abi) }, result(i32, i32_abi)),
    Support.abi_function_projection(target, { param(0, i32, i32_abi), param(1, i32, i32_abi) }, result(i32, i32_abi)),
    Support.abi_function_projection(target, { param(0, bool8, bool_abi), param(1, i32, i32_abi), param(2, i32, i32_abi) }, result(i32, i32_abi)),
    Support.abi_function_projection(target, { param(0, code_ptr_ty, ptr_abi), param(1, i32, i32_abi) }, result(i32, i32_abi)),
    Support.abi_function_projection(target, { param(0, closure_ty, closure_abi), param(1, i32, i32_abi) }, result(i32, i32_abi)),
  }
  local domain = Support.support_domain(
    Support.host_template_support_domain_id('code-control'),
    target,
    Support.empty_runtime(),
    { bool_scalar, i32_scalar, ptr_scalar },
    adapters
  )
  return Sources.bank_request_for_support_domain(domain, Support.bank_id_for_support_domain(domain))
end
]]

local dir = "target/test_artifacts/test_native_code_control"
assert(command_ok("rm -rf " .. shell_quote(dir)))
assert(command_ok("mkdir -p " .. shell_quote(dir)))
local manifest_path = dir .. "/manifest.lua"
local mf = assert(io.open(manifest_path, "wb"))
mf:write(bank_request_source)
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
assert(command_ok(cmd), "native control bank generator should build focused Code control support")
assert(command_ok("gcc -shared -fPIC " .. shell_quote(c_path) .. " -o " .. shell_quote(so_path)), "native control C-owned bank should link as a shared object")

local target = NativeBackend.host_target()
local runtime = NativeBackend.empty_runtime()
local artifact = dofile(lua_path)(T)
assert(asdl.isa(artifact, Native.NativeBankArtifact), tostring(artifact))
local bank = NativeBackend.require_native_bank(artifact, target, nil, so_path)
local origin = Code.CodeOriginUnknown
local i32 = Code.CodeTyInt(32, Code.CodeSigned)
local bool8 = Code.CodeTyBool8
local call_sig = Code.CodeSig(Code.CodeSigId("native.control.call.sig"), { i32 }, { i32 })

local function sig(id, params, results)
    return Code.CodeSig(Code.CodeSigId(id), params or {}, results or { i32 })
end

local function inst(id, op)
    return Code.CodeInst(Code.CodeInstId(id), op, origin)
end

local function term(id, op)
    return Code.CodeTerm(Code.CodeTermId(id), op, origin)
end

local function block(id, params, insts, term_op)
    local bid = Code.CodeBlockId(id)
    return Code.CodeBlock(bid, id, params or {}, insts or {}, term(id .. ".term", term_op), origin)
end

local function func(id, signature, params, blocks, entry)
    return Code.CodeFunc(Code.CodeFuncId(id), id, Code.CodeLinkageExport, signature.id, params or {}, {}, entry or blocks[1].id, blocks, origin)
end

local function plan_graph(f, signature)
    local graph = f:plan_native_copy(Native.NativePlanInput(target, runtime, bank), nil, signature)
    assert(asdl.isa(graph, Native.NativeTemplateGraph), "control lowering should produce a NativeTemplateGraph")
    assert(graph.protocol.projection:native_abi_function_projection_equals(signature:native_abi_projection(target)), "control graph should keep the CodeSig ABI projection")
    return graph
end

local function plan_module_graph(module, signature)
    local graph = module:plan_native_copy(Native.NativePlanInput(target, runtime, bank))
    assert(asdl.isa(graph, Native.NativeTemplateGraph), "module control lowering should produce a NativeTemplateGraph")
    assert(graph.protocol.projection:native_abi_function_projection_equals(signature:native_abi_projection(target)), "module graph should keep the active CodeSig ABI projection")
    return graph
end

local function compile_call(f, signature, args)
    local result = NativeBackend.compile_code_func(f, signature, target, runtime, bank)
    local executable = result.executable
    return executable.protocol:call_native_executable(Native.NativeExecutableCallInput(executable, args or {}))
end

local function family_has(node, text)
    return node.family.id.text:find(text, 1, true) ~= nil
end

local function count_nodes(graph, text)
    local count = 0
    for _, node in ipairs(graph.nodes or {}) do
        if family_has(node, text) then count = count + 1 end
    end
    return count
end

local function assert_symbol_edges(graph)
    local saw_continuation = false
    for _, edge in ipairs(graph.control_edges or {}) do
        if asdl.isa(edge, Native.NativeContinuationEdge) then
            assert(asdl.isa(edge.symbol, Native.NativeContinuationSymbol), "continuation edges must carry symbols")
            saw_continuation = true
        elseif asdl.isa(edge, Native.NativeConditionalBranchEdge) then
            assert(asdl.isa(edge.then_symbol, Native.NativeContinuationSymbol), "conditional then edge must carry a continuation symbol")
            assert(asdl.isa(edge.else_symbol, Native.NativeContinuationSymbol), "conditional else edge must carry a continuation symbol")
            saw_continuation = true
        elseif asdl.isa(edge, Native.NativeRuntimeCallReturnEdge) then
            assert(asdl.isa(edge.return_symbol, Native.NativeContinuationSymbol), "runtime call-return edges must carry a return symbol")
            saw_continuation = true
        end
    end
    assert(saw_continuation, "control graphs should expose symbol-bearing control edges")
end

local function assert_block_entries(graph, minimum)
    local count = 0
    for _, node in ipairs(graph.nodes or {}) do
        if node.id.text:find("native.code.block_entry.", 1, true) then count = count + 1 end
        for _, binding in ipairs(node.bindings or {}) do
            assert(binding.node == node.id and binding.instance == node.instance, "control graph patch bindings must be node/instance scoped")
        end
    end
    assert(count >= minimum, "control graph should contain explicit block-entry nodes")
end

local function assert_control_graph(graph, minimum_blocks)
    assert_block_entries(graph, minimum_blocks)
    assert_symbol_edges(graph)
end

local function jump_func()
    local a = Code.CodeValueId("native.control.jump.a")
    local b = Code.CodeValueId("native.control.jump.b")
    local x = Code.CodeValueId("native.control.jump.x")
    local y = Code.CodeValueId("native.control.jump.y")
    local dst = Code.CodeValueId("native.control.jump.dst")
    local entry = block("native.control.jump.entry", {}, {}, Code.CodeTermJump(Code.CodeBlockId("native.control.jump.join"), { b, a }))
    local join = block("native.control.jump.join", { Code.CodeParam(x, "x", i32, origin), Code.CodeParam(y, "y", i32, origin) }, {
        inst("native.control.jump.sub", Code.CodeInstBinary(dst, Core.BinSub, i32, Code.CodeIntSemantics(Code.CodeIntWrap, Code.CodeDivTrapOnZero, Code.CodeShiftMaskCount), x, y)),
    }, Code.CodeTermReturn({ dst }))
    local signature = sig("native.control.jump.sig", { i32, i32 }, { i32 })
    return func("native.control.jump", signature, { Code.CodeParam(a, "a", i32, origin), Code.CodeParam(b, "b", i32, origin) }, { entry, join }, entry.id), signature
end

local jf, js = jump_func()
local jg = plan_graph(jf, js)
assert_control_graph(jg, 2)
assert(count_nodes(jg, "parallel_copy.i32.slot.slot.temp") == 1, "two-value jump should use an explicit parallel-copy node")
local jr = compile_call(jf, js, { Native.NativeCallArgI32(3), Native.NativeCallArgI32(8) })
assert(asdl.isa(jr, Native.NativeCallReturnedI32) and jr.value == 5, "jump with parallel block-arg copy should execute")

local function branch_func()
    local cond = Code.CodeValueId("native.control.branch.cond")
    local a = Code.CodeValueId("native.control.branch.a")
    local b = Code.CodeValueId("native.control.branch.b")
    local chosen = Code.CodeValueId("native.control.branch.chosen")
    local entry = block("native.control.branch.entry", {}, {}, Code.CodeTermBranch(cond, Code.CodeBlockId("native.control.branch.join"), { a }, Code.CodeBlockId("native.control.branch.join"), { b }))
    local join = block("native.control.branch.join", { Code.CodeParam(chosen, "chosen", i32, origin) }, {}, Code.CodeTermReturn({ chosen }))
    local signature = sig("native.control.branch.sig", { bool8, i32, i32 }, { i32 })
    return func("native.control.branch", signature, { Code.CodeParam(cond, "cond", bool8, origin), Code.CodeParam(a, "a", i32, origin), Code.CodeParam(b, "b", i32, origin) }, { entry, join }, entry.id), signature
end

local bf, bs = branch_func()
local bg = plan_graph(bf, bs)
assert_control_graph(bg, 2)
assert(count_nodes(bg, "branch.bool8.slot") == 1, "branch term should select a bool frame-slot control stencil")
assert(count_nodes(bg, "edge_copy.i32.slot.to.slot") >= 2, "branch block args should lower through explicit edge-copy nodes")
local br_t = compile_call(bf, bs, { Native.NativeCallArgI32(1), Native.NativeCallArgI32(11), Native.NativeCallArgI32(22) })
local br_f = compile_call(bf, bs, { Native.NativeCallArgI32(0), Native.NativeCallArgI32(11), Native.NativeCallArgI32(22) })
assert(asdl.isa(br_t, Native.NativeCallReturnedI32) and br_t.value == 11, "branch true path should execute")
assert(asdl.isa(br_f, Native.NativeCallReturnedI32) and br_f.value == 22, "branch false path should execute")

local function const_block(id, value)
    local dst = Code.CodeValueId(id .. ".value")
    return block(id, {}, { inst(id .. ".const", Code.CodeInstConst(dst, Code.CodeConstLiteral(i32, Core.LitInt(tostring(value))))) }, Code.CodeTermReturn({ dst }))
end

local function switch_func()
    local key = Code.CodeValueId("native.control.switch.key")
    local entry = block("native.control.switch.entry", {}, {}, Code.CodeTermSwitch(key, {
        Code.CodeSwitchCase(Core.LitInt("1"), Code.CodeBlockId("native.control.switch.one"), {}),
        Code.CodeSwitchCase(Core.LitInt("2"), Code.CodeBlockId("native.control.switch.two"), {}),
    }, Code.CodeBlockId("native.control.switch.default"), {}))
    local one = const_block("native.control.switch.one", 10)
    local two = const_block("native.control.switch.two", 20)
    local default = const_block("native.control.switch.default", 99)
    local signature = sig("native.control.switch.sig", { i32 }, { i32 })
    return func("native.control.switch", signature, { Code.CodeParam(key, "key", i32, origin) }, { entry, one, two, default }, entry.id), signature
end

local sf, ss = switch_func()
local sg = plan_graph(sf, ss)
assert_control_graph(sg, 4)
assert(count_nodes(sg, "switch_step.i32.slot.imm") >= 2, "switch lowering should emit one typed step per case")
local sr_case = compile_call(sf, ss, { Native.NativeCallArgI32(2) })
local sr_default = compile_call(sf, ss, { Native.NativeCallArgI32(5) })
assert(asdl.isa(sr_case, Native.NativeCallReturnedI32) and sr_case.value == 20, "switch case path should execute")
assert(asdl.isa(sr_default, Native.NativeCallReturnedI32) and sr_default.value == 99, "switch default path should execute")

local function variant_switch_func()
    local tag = Code.CodeValueId("native.control.variant.tag")
    local variant_ty = Code.CodeTyInt(32, Code.CodeSigned)
    local entry = block("native.control.variant.entry", {}, {}, Code.CodeTermVariantSwitch(tag, {
        Code.CodeVariantCase(Code.CodeVariantRef(variant_ty, "one", 1, nil), Code.CodeBlockId("native.control.variant.one"), {}),
        Code.CodeVariantCase(Code.CodeVariantRef(variant_ty, "two", 2, nil), Code.CodeBlockId("native.control.variant.two"), {}),
    }, Code.CodeBlockId("native.control.variant.default"), {}))
    local one = const_block("native.control.variant.one", 10)
    local two = const_block("native.control.variant.two", 20)
    local default = const_block("native.control.variant.default", 99)
    local signature = sig("native.control.variant.sig", { i32 }, { i32 })
    return func("native.control.variant", signature, { Code.CodeParam(tag, "tag", i32, origin) }, { entry, one, two, default }, entry.id), signature
end

local vf, vs = variant_switch_func()
local vg = plan_graph(vf, vs)
assert_control_graph(vg, 4)
assert(count_nodes(vg, "variant_switch_step.i32.slot.imm") >= 2, "variant switch lowering should emit typed case-step nodes")

local function loop_graph_func()
    local n = Code.CodeValueId("native.control.loop.n")
    local entry = block("native.control.loop.entry", {}, {}, Code.CodeTermJump(Code.CodeBlockId("native.control.loop.loop"), { n }))
    local lp = block("native.control.loop.loop", { Code.CodeParam(Code.CodeValueId("native.control.loop.i"), "i", i32, origin) }, {}, Code.CodeTermJump(Code.CodeBlockId("native.control.loop.loop"), { Code.CodeValueId("native.control.loop.i") }))
    local signature = sig("native.control.loop.sig", { i32 }, { i32 })
    return func("native.control.loop", signature, { Code.CodeParam(n, "n", i32, origin) }, { entry, lp }, entry.id), signature
end

local lf, ls = loop_graph_func()
local lg = plan_graph(lf, ls)
assert_control_graph(lg, 2)
assert(count_nodes(lg, "jump.next") >= 2, "loop-shaped jumps should remain explicit jump continuation nodes")

local function terminal_graph_func(name, op)
    local p = Code.CodeValueId(name .. ".p")
    local b = block(name .. ".entry", {}, {}, op)
    local signature = sig(name .. ".sig", { i32 }, { i32 })
    return func(name, signature, { Code.CodeParam(p, "p", i32, origin) }, { b }, b.id), signature
end

local tf, ts = terminal_graph_func("native.control.trap", Code.CodeTermTrap("native control test trap"))
local tg = plan_graph(tf, ts)
assert_control_graph(tg, 1)
assert(count_nodes(tg, "trap.trap") == 1, "trap term should select a terminal trap stencil")
local uf, us = terminal_graph_func("native.control.unreachable", Code.CodeTermUnreachable("native control test unreachable"))
local ug = plan_graph(uf, us)
assert_control_graph(ug, 1)
assert(count_nodes(ug, "unreachable.trap") == 1, "unreachable term should select a terminal trap stencil")

local function call_func(name, target_op, params, args, target_sig_id)
    local signature_params = {}
    for _, p in ipairs(params) do signature_params[#signature_params + 1] = p.ty end
    local signature = sig(name .. ".sig", signature_params, { i32 })
    local dst = Code.CodeValueId(name .. ".dst")
    local call = inst(name .. ".call", Code.CodeInstCall(dst, target_op, target_sig_id or signature.id, args))
    local b = block(name .. ".entry", {}, { call }, Code.CodeTermReturn({ dst }))
    return func(name, signature, params, { b }, b.id), signature
end

local direct_arg = Code.CodeValueId("native.control.call.direct.arg")
local direct_f, direct_s = call_func("native.control.call.direct", Code.CodeCallDirect(Code.CodeFuncId("native.control.call.direct")), { Code.CodeParam(direct_arg, "arg", i32, origin) }, { direct_arg })
local direct_g = plan_graph(direct_f, direct_s)
assert_control_graph(direct_g, 1)
assert(count_nodes(direct_g, "call.direct") == 1, "direct CodeInstCall should select a direct call stencil")
assert(count_nodes(direct_g, "result_copy.i32") == 1, "call result should be copied through an explicit result-copy node")

local extern_arg = Code.CodeValueId("native.control.call.extern.arg")
local extern_id = Code.CodeExternId("native.control.extern.add1")
local extern_f, extern_s = call_func("native.control.call.extern", Code.CodeCallExtern(extern_id), { Code.CodeParam(extern_arg, "arg", i32, origin) }, { extern_arg }, call_sig.id)
local extern_module = Code.CodeModule(Code.CodeModuleId("native.control.extern.module"), { call_sig, extern_s }, {}, {}, {}, { Code.CodeExtern(extern_id, "extern_add1", "native_control_extern_add1", call_sig.id, origin) }, { extern_f }, origin)
local extern_runtime = Native.NativeRuntime({
    Native.NativeRuntimeSymbol(
        Native.NativeRuntimeSymbolId("native.control.runtime.extern.add1"),
        "native_control_extern_add1",
        call_sig:native_abi_projection(target),
        Native.NativeRuntimeAddressLinkerSymbol("native_control_extern_add1")
    ),
})
local extern_graph = extern_module:plan_native_copy(Native.NativePlanInput(target, extern_runtime, bank))
assert(count_nodes(extern_graph, "call.extern") == 1, "extern CodeInstCall should select an extern call stencil")
local extern_install_plan = extern_graph:select_native_bank_install_plan(Native.NativeBankInstallPlanSelectionInput(target, extern_runtime))
local extern_install = Native.NativeBankInstallRequest(bank, extern_install_plan, Native.NativeExecutableAllocatorMmap):install_native()
assert(asdl.isa(extern_install, Native.NativeInstallRejected), "extern calls without supplied runtime addresses should reject at C bank install")
assert(asdl.isa(extern_install.rejects[1], Native.NativeInstallRejectBankRejected), "extern call rejection should be a typed C-bank reject, not a Lua installer fallback")

local fn_value = Code.CodeValueId("native.control.call.indirect.fn")
local indirect_arg = Code.CodeValueId("native.control.call.indirect.arg")
local indirect_f, indirect_s = call_func("native.control.call.indirect", Code.CodeCallIndirect(fn_value, call_sig.id), { Code.CodeParam(fn_value, "fn", Code.CodeTyCodePtr(call_sig.id), origin), Code.CodeParam(indirect_arg, "arg", i32, origin) }, { indirect_arg }, call_sig.id)
local indirect_module = Code.CodeModule(Code.CodeModuleId("native.control.indirect.module"), { call_sig, indirect_s }, {}, {}, {}, {}, { indirect_f }, origin)
local indirect_g = plan_module_graph(indirect_module, indirect_s)
assert_control_graph(indirect_g, 1)
assert(count_nodes(indirect_g, "call.indirect") == 1, "indirect CodeInstCall should select an indirect call stencil")

local closure_value = Code.CodeValueId("native.control.call.closure.closure")
local closure_arg = Code.CodeValueId("native.control.call.closure.arg")
local closure_f, closure_s = call_func("native.control.call.closure", Code.CodeCallClosure(closure_value, call_sig.id), { Code.CodeParam(closure_value, "closure", Code.CodeTyClosure(call_sig.id), origin), Code.CodeParam(closure_arg, "arg", i32, origin) }, { closure_arg }, call_sig.id)
local closure_module = Code.CodeModule(Code.CodeModuleId("native.control.closure.module"), { call_sig, closure_s }, {}, {}, {}, {}, { closure_f }, origin)
local closure_g = plan_module_graph(closure_module, closure_s)
assert_control_graph(closure_g, 1)
assert(count_nodes(closure_g, "call.closure") == 1, "closure CodeInstCall should select a closure call stencil when descriptor ABI support is present")

io.write("native code control ok\n")
