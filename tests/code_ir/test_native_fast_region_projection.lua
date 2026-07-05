package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local asdl = require("lalin.asdl")
local Schema = require("lalin.schema")

local T = asdl.context()
Schema(T)
local Native = T.LalinNative
local Code = T.LalinCode
local Core = T.LalinCore
local Support = require("lalin.native_template_support")(T)
require("lalin.native_code_methods")(T)

local target = Support.host_target()
local runtime = Support.empty_runtime()
local origin = Code.CodeOriginUnknown
local i32 = Code.CodeTyInt(32, Code.CodeSigned)

local function fake_loaded_bank(id)
    local manifest = Native.NativeTemplateSourceManifest(Native.NativeTemplateManifestId(id .. ".manifest"), Native.NativeTemplateSupportDomainId(id .. ".support"), {}, 0)
    local artifact = Native.NativeBankArtifact(Native.NativeBankId(id), target, manifest, 0, "lalin_native_bank_artifact", "lalin_native_bank_select", "lalin_native_bank_install")
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
local compare_body, compare_region = assert(first_region_body(branch_func:plan_native_fast_regions(plan_input, nil, branch_sig), Native.NativeCodeCompareBranchRegion))
assert(asdl.isa(compare_body.compare, Native.NativeCompareBranchAtoms), "adjacent compare/branch should project to a compare-branch fast region")
assert(asdl.isa(compare_region.transfer, Native.NativeRegionBranch), "compare-branch region must carry typed branch transfer")

io.write("lalin native_fast_region_projection ok\n")
