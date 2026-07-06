package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local asdl = require("lalin.asdl")
local Schema = require("lalin.schema")

local T = asdl.context()
Schema(T)
local Native = T.LalinNative
local Code = T.LalinCode
local Core = T.LalinCore
local Support = require("lalin.native_template_support")(T)
local Sources = require("lalin.native_template_sources")(T)
require("lalin.native_code_methods")(T)
require("lalin.native_mc")(T)

local target = Support.host_target()
local runtime = Support.empty_runtime()
local origin = Code.CodeOriginUnknown
local i32 = Code.CodeTyInt(32, Code.CodeSigned)

local function fake_loaded_bank(id, manifest)
    manifest = manifest or Native.NativeTemplateSourceManifest(Native.NativeTemplateManifestId(id .. ".manifest"), Native.NativeTemplateSupportDomainId(id .. ".support"), {}, 0)
    local artifact = Native.NativeBankArtifact(Native.NativeBankId(id), target, manifest, manifest.total_count or 0, "lalin_native_bank_artifact", "lalin_native_bank_select", "lalin_native_bank_install")
    return Native.NativeLoadedBank(artifact, 1)
end

local plan_input = Native.NativePlanInput(target, runtime, fake_loaded_bank("native.fast.region.projection.fake.bank"))

local function sem()
    return Code.CodeIntSemantics(Code.CodeIntWrap, Code.CodeDivTrapOnZero, Code.CodeShiftMaskCount)
end

local function inst(id, op)
    return Code.CodeInst(Code.CodeInstId(id), op, origin)
end

local function term(id, op)
    return Code.CodeTerm(Code.CodeTermId(id), op, origin)
end

local function func(name, params, blocks, entry, results)
    local sig = Code.CodeSig(Code.CodeSigId(name .. ".sig"), params, results or { i32 })
    local code_params = {}
    for i, ty in ipairs(params or {}) do
        code_params[i] = Code.CodeParam(Code.CodeValueId(name .. ".p" .. tostring(i)), "p" .. tostring(i), ty, origin)
    end
    return Code.CodeFunc(Code.CodeFuncId(name), name, Code.CodeLinkageExport, sig.id, code_params, {}, entry, blocks(code_params), origin), sig
end

local function first_region_body(plan, cls)
    for _, region in ipairs(plan.regions or {}) do
        if asdl.isa(region.body, cls) then return region.body, region end
    end
end

local atom_func, atom_sig = func("native.fast.atom", { i32 }, function(p)
    local bid = Code.CodeBlockId("native.fast.atom.entry")
    return { Code.CodeBlock(bid, "entry", {}, {}, term("native.fast.atom.ret", Code.CodeTermReturn({ p[1].value })), origin) }
end, Code.CodeBlockId("native.fast.atom.entry"))
local atom_plan = atom_func:plan_native_fast_regions(plan_input, nil, atom_sig)
local atom_body = assert(first_region_body(atom_plan, Native.NativeCodeExprRegion))
assert(asdl.isa(atom_body.shape, Native.NativeExprReturnAtom), "returning a parameter should project to a return-atom fast region")
assert(asdl.isa(atom_body.shape.atom, Native.NativeExprInput), "return atom should bind a typed region input")
local atom_graph = atom_plan:lower_native_template_graph()
assert(asdl.isa(atom_graph, Native.NativeTemplateGraph), "fast region plan should lower to a template graph")
assert(asdl.isa(atom_graph.control_edges[1], Native.NativeFallthroughEdge), "fast block entry should lower fallthrough as a typed graph edge")
assert(asdl.isa(atom_graph.nodes[2].bindings[1].target, Native.NativePatchBindingHoleOrdinalIndex), "fast graph bindings should use typed hole ordinal indexes, not hole-name tables")
local atom_install_plan = atom_graph:select_native_bank_install_plan(Native.NativeBankInstallPlanSelectionInput(target, runtime))
assert(asdl.isa(atom_install_plan.control_edges[1], Native.NativeBankFallthroughEdge), "bank install plan should preserve typed fallthrough edges")

local unary_func, unary_sig = func("native.fast.unary", { i32 }, function(p)
    local dst = Code.CodeValueId("native.fast.unary.dst")
    local bid = Code.CodeBlockId("native.fast.unary.entry")
    return { Code.CodeBlock(bid, "entry", {}, { inst("native.fast.unary.neg", Code.CodeInstUnary(dst, Core.UnaryNeg, i32, p[1].value)) }, term("native.fast.unary.ret", Code.CodeTermReturn({ dst })), origin) }
end, Code.CodeBlockId("native.fast.unary.entry"))
local unary_body = assert(first_region_body(unary_func:plan_native_fast_regions(plan_input, nil, unary_sig), Native.NativeCodeExprRegion))
assert(asdl.isa(unary_body.shape, Native.NativeExprReturnUnary), "unary return should project to a unary fast region")

local imm_func, imm_sig = func("native.fast.imm", { i32 }, function(p)
    local c = Code.CodeValueId("native.fast.imm.c")
    local dst = Code.CodeValueId("native.fast.imm.dst")
    local bid = Code.CodeBlockId("native.fast.imm.entry")
    return { Code.CodeBlock(bid, "entry", {}, {
        inst("native.fast.imm.const", Code.CodeInstConst(c, Code.CodeConstLiteral(i32, Core.LitInt("7")))),
        inst("native.fast.imm.add", Code.CodeInstBinary(dst, Core.BinAdd, i32, sem(), p[1].value, c)),
    }, term("native.fast.imm.ret", Code.CodeTermReturn({ dst })), origin) }
end, Code.CodeBlockId("native.fast.imm.entry"))
local imm_plan = imm_func:plan_native_fast_regions(plan_input, nil, imm_sig)
local imm_body, imm_region = assert(first_region_body(imm_plan, Native.NativeCodeExprRegion))
assert(asdl.isa(imm_body.shape, Native.NativeExprReturnBinaryImmRhs), "binary with adjacent const rhs should project to binary-imm-rhs")
assert(asdl.isa(imm_region.inputs[2].residence, Native.NativeResidenceImmediate), "binary immediate value must be a typed immediate residence")
assert(asdl.isa(imm_region.inputs[2].residence.coordinate, Native.NativePatchCoordinate), "immediate residence must carry the typed patch coordinate")

local mad_func, mad_sig = func("native.fast.mad", { i32, i32 }, function(p)
    local mul = Code.CodeValueId("native.fast.mad.mul")
    local c = Code.CodeValueId("native.fast.mad.c")
    local dst = Code.CodeValueId("native.fast.mad.dst")
    local bid = Code.CodeBlockId("native.fast.mad.entry")
    return { Code.CodeBlock(bid, "entry", {}, {
        inst("native.fast.mad.mul_inst", Code.CodeInstBinary(mul, Core.BinMul, i32, sem(), p[1].value, p[2].value)),
        inst("native.fast.mad.const", Code.CodeInstConst(c, Code.CodeConstLiteral(i32, Core.LitInt("5")))),
        inst("native.fast.mad.add", Code.CodeInstBinary(dst, Core.BinAdd, i32, sem(), mul, c)),
    }, term("native.fast.mad.ret", Code.CodeTermReturn({ dst })), origin) }
end, Code.CodeBlockId("native.fast.mad.entry"))
local mad_body = assert(first_region_body(mad_func:plan_native_fast_regions(plan_input, nil, mad_sig), Native.NativeCodeExprRegion))
assert(asdl.isa(mad_body.shape, Native.NativeExprReturnMulAddImm), "mul/add/const suffix should project to mul-add-imm")

local scalar_i32 = i32:native_machine_scalar(target)
local abi_i32 = Support.abi_scalar_value(scalar_i32)
local fast_public_mad_shape = Native.NativeExprReturnMulAddImm(scalar_i32, Native.NativeExprInput(0, scalar_i32), Native.NativeExprInput(1, scalar_i32))
local fast_public_mad_abi = Native.NativeFastAbi2(abi_i32, abi_i32, abi_i32)
local fast_public_request = Sources.bank_request_for_fast_region_capability(
    Native.NativeFastRegionCapability(
        { fast_public_mad_abi },
        { fast_public_mad_shape },
        {},
        {},
        {},
        {},
        {}
    ),
    target,
    runtime,
    Native.NativeBankId("native.fast.region.projection.public.mad.bank")
)
local fast_public_graph = mad_func:plan_native_copy(Native.NativePlanInput(target, runtime, fake_loaded_bank("native.fast.region.projection.public.mad.bank", fast_public_request.manifest)), nil, mad_sig)
local baseline_graph = mad_func:plan_native_copy(Native.NativePlanInput(target, runtime, fake_loaded_bank("native.fast.region.projection.baseline.bank")), nil, mad_sig)
assert(#fast_public_graph.nodes == 1, "eligible public mul-add should lower to one fused public expression node")
assert(#fast_public_graph.nodes < #baseline_graph.nodes, "fast public expression graph should have fewer nodes than the baseline micro-op graph")
local fast_node = fast_public_graph.nodes[1]
assert(asdl.isa(fast_node.family.axes[3], Native.NativeAxisFastPublicAbi), "fused public node should carry a bounded public ABI axis")
assert(asdl.isa(fast_node.family.axes[4], Native.NativeAxisFastCodeExpr), "fused public node should carry the expression shape axis")
assert(asdl.isa(fast_node.inputs[1].location, Native.NativeValueRegisterLocation), "public param input should reside at the public ABI boundary, not a frame slot")
assert(asdl.isa(fast_node.outputs[1].location, Native.NativeValueRegisterLocation), "public result output should reside at the public ABI boundary, not a frame slot")
assert(#fast_node.bindings == 1 and asdl.isa(fast_node.bindings[1].target, Native.NativePatchBindingHoleOrdinalIndex), "fused public mul-add should patch only the immediate operand by typed ordinal")
for _, edge in ipairs(fast_public_graph.control_edges or {}) do
    assert(not asdl.isa(edge, Native.NativeContinuationEdge), "fused public expression graph must not add artificial continuation jumps")
    assert(not asdl.isa(edge, Native.NativeFallthroughEdge), "single fused public expression graph must not need a fallthrough layout edge")
end
assert(#(fast_public_graph.frame_layout.slots or {}) == 0, "fused public expression graph should not allocate public ABI frame slots")

local branch_sig = Code.CodeSig(Code.CodeSigId("native.fast.branch.sig"), { i32, i32 }, { i32 })
local a = Code.CodeParam(Code.CodeValueId("native.fast.branch.a"), "a", i32, origin)
local b = Code.CodeParam(Code.CodeValueId("native.fast.branch.b"), "b", i32, origin)
local cond = Code.CodeValueId("native.fast.branch.cond")
local entry_id = Code.CodeBlockId("native.fast.branch.entry")
local then_id = Code.CodeBlockId("native.fast.branch.then")
local else_id = Code.CodeBlockId("native.fast.branch.else")
local branch_func = Code.CodeFunc(Code.CodeFuncId("native.fast.branch"), "native.fast.branch", Code.CodeLinkageExport, branch_sig.id, { a, b }, {}, entry_id, {
    Code.CodeBlock(entry_id, "entry", {}, { inst("native.fast.branch.cmp", Code.CodeInstCompare(cond, Core.CmpLt, i32, a.value, b.value)) }, term("native.fast.branch.br", Code.CodeTermBranch(cond, then_id, {}, else_id, {})), origin),
    Code.CodeBlock(then_id, "then", {}, {}, term("native.fast.branch.then.ret", Code.CodeTermReturn({ a.value })), origin),
    Code.CodeBlock(else_id, "else", {}, {}, term("native.fast.branch.else.ret", Code.CodeTermReturn({ b.value })), origin),
}, origin)
local branch_plan = branch_func:plan_native_fast_regions(plan_input, nil, branch_sig)
local compare_body, compare_region = assert(first_region_body(branch_plan, Native.NativeCodeCompareBranchRegion))
assert(asdl.isa(compare_body.compare, Native.NativeCompareBranchAtoms), "adjacent compare/branch should project to a compare-branch fast region")
assert(asdl.isa(compare_region.transfer, Native.NativeRegionBranch), "compare-branch region must carry typed branch transfer")
local branch_graph = branch_plan:lower_native_template_graph()
local compare_node
for _, node in ipairs(branch_graph.nodes or {}) do
    if node.id.text == "native.fast.node." .. compare_region.id.text then compare_node = node end
end
assert(compare_node ~= nil, "compare-branch fast region should lower to a graph node")
assert(asdl.isa(compare_node.family.axes[3], Native.NativeAxisFastCodeCompareBranch), "compare-branch family must carry the typed compare axis")
local branch_install_plan = branch_graph:select_native_bank_install_plan(Native.NativeBankInstallPlanSelectionInput(target, runtime))
local found_conditional = false
for _, edge in ipairs(branch_install_plan.control_edges or {}) do
    if asdl.isa(edge, Native.NativeBankConditionalBranchEdge) then found_conditional = true end
end
assert(found_conditional, "compare-branch graph should preserve real branch transfer as a typed bank conditional edge")

local switch_sig = Code.CodeSig(Code.CodeSigId("native.fast.switch.sig"), { i32 }, { i32 })
local sw_p = Code.CodeParam(Code.CodeValueId("native.fast.switch.p"), "p", i32, origin)
local sw_entry = Code.CodeBlockId("native.fast.switch.entry")
local sw_zero = Code.CodeBlockId("native.fast.switch.zero")
local sw_one = Code.CodeBlockId("native.fast.switch.one")
local sw_default = Code.CodeBlockId("native.fast.switch.default")
local switch_func = Code.CodeFunc(Code.CodeFuncId("native.fast.switch"), "native.fast.switch", Code.CodeLinkageExport, switch_sig.id, { sw_p }, {}, sw_entry, {
    Code.CodeBlock(sw_entry, "entry", {}, {}, term("native.fast.switch.term", Code.CodeTermSwitch(sw_p.value, {
        Code.CodeSwitchCase(Core.LitInt("0"), sw_zero, {}),
        Code.CodeSwitchCase(Core.LitInt("1"), sw_one, {}),
    }, sw_default, {})), origin),
    Code.CodeBlock(sw_zero, "zero", {}, {}, term("native.fast.switch.zero.ret", Code.CodeTermReturn({ sw_p.value })), origin),
    Code.CodeBlock(sw_one, "one", {}, {}, term("native.fast.switch.one.ret", Code.CodeTermReturn({ sw_p.value })), origin),
    Code.CodeBlock(sw_default, "default", {}, {}, term("native.fast.switch.default.ret", Code.CodeTermReturn({ sw_p.value })), origin),
}, origin)
local switch_plan = switch_func:plan_native_fast_regions(plan_input, nil, switch_sig)
local switch_region
for _, region in ipairs(switch_plan.regions or {}) do
    if asdl.isa(region.transfer, Native.NativeRegionSwitch) then switch_region = region end
end
assert(switch_region ~= nil, "Code switch should project to a typed NativeRegionSwitch")
assert(asdl.isa(switch_region.transfer.step_shape, Native.NativeSwitchStepAtoms), "switch transfer must carry a typed switch-step shape")
local switch_graph = switch_plan:lower_native_template_graph()
local switch_step_edges = 0
local switch_nodes = 0
for _, node in ipairs(switch_graph.nodes or {}) do
    if node.id.text:find("native.fast.node." .. switch_region.id.text, 1, true) == 1 then
        switch_nodes = switch_nodes + 1
        assert(asdl.isa(node.family.axes[3], Native.NativeAxisFastCodeSwitchStep), "switch-step family must carry the typed switch-step axis")
    end
end
for _, edge in ipairs(switch_graph.control_edges or {}) do
    if asdl.isa(edge, Native.NativeSwitchStepEdge) then switch_step_edges = switch_step_edges + 1 end
end
assert(switch_nodes == 2, "two-case switch should lower to two typed switch-step nodes with per-case bindings")
assert(switch_step_edges == 2, "two-case switch should lower to two typed graph switch-step edges")
local switch_install_plan = switch_graph:select_native_bank_install_plan(Native.NativeBankInstallPlanSelectionInput(target, runtime))
local bank_switch_edges = 0
for _, edge in ipairs(switch_install_plan.control_edges or {}) do
    if asdl.isa(edge, Native.NativeBankSwitchStepEdge) then bank_switch_edges = bank_switch_edges + 1 end
end
assert(bank_switch_edges == 2, "switch-step graph edges should project to typed bank switch-step edges")

io.write("lalin native_fast_region_projection ok\n")
