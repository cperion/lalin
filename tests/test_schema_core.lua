package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local Schema = require("moonlift.schema")
local AsdlParser = require("moonlift.asdl_parser")
local AsdlText = require("moonlift.asdl_text")

assert(Schema.assert_schema_directory_sources())
local ok_builder, err_builder = pcall(Schema.assert_schema_directory_sources, { "core.asdl", "init.lua", "legacy.lua" })
assert(not ok_builder and tostring(err_builder):match("Lua schema builder modules are forbidden"))
local ok_asdl, err_asdl = pcall(Schema.assert_schema_directory_sources, { "core.asdl", "init.lua", "surprise.asdl" })
assert(not ok_asdl and tostring(err_asdl):match("unexpected ASDL source"))
local ok_parse, err_parse = pcall(AsdlParser.parse, "module Bad { X = (i32 }", "bad_source.asdl")
assert(not ok_parse and tostring(err_parse):match("bad_source%.asdl:%d+:%d+: ASDL parse error"))

local function with_embedded_schema_only(body)
    local saved = {}
    for _, name in ipairs(Schema.schema_asdl_modules_for_test()) do
        local preload_name = "moonlift.schema." .. name .. "_asdl"
        local path = "lua/moonlift/schema/" .. name .. ".asdl"
        local text = assert(AsdlText.read_file(path))
        saved[#saved + 1] = {
            preload_name = preload_name,
            preload = package.preload[preload_name],
            loaded = package.loaded[preload_name],
        }
        package.loaded[preload_name] = nil
        package.preload[preload_name] = function() return text end
    end
    local ok, err = pcall(function()
        AsdlText.with_read_file_for_test(function(path)
            error("filesystem ASDL read disabled: " .. tostring(path), 0)
        end, body)
    end)
    for _, item in ipairs(saved) do
        package.preload[item.preload_name] = item.preload
        package.loaded[item.preload_name] = item.loaded
    end
    if not ok then error(err, 0) end
end

with_embedded_schema_only(function()
    local embedded_T = pvm.context()
    local embedded_schema = Schema.schema(embedded_T)
    assert(pvm.classof(embedded_schema) == embedded_T.MoonAsdl.Schema)
    assert(embedded_schema.modules[1].name == "MoonCore")
end)

local T = pvm.context()
local schema = Schema.schema(T)
assert(pvm.classof(schema) == T.MoonAsdl.Schema)
assert(#schema.modules >= 16)
assert(schema.modules[1].name == "MoonCore")
assert(schema.modules[2].name == "MoonBack")

-- Define directly from schema data (no text round-trip).
Schema.Define(T)

local C = T.MoonCore
assert(C.Id("x") == C.Id("x"))
assert(C.Path({ C.Name("a"), C.Name("b") }) == C.Path({ C.Name("a"), C.Name("b") }))
assert(C.ScalarI32.kind == "ScalarI32")
assert(C.ScalarInfo(C.ScalarFamilySignedInt, C.ScalarBits(32)).bits.bits == 32)
assert(C.LitInt("7") == C.LitInt("7"))
assert(C.LitBool(true).value == true)
assert(C.VisibilityExport.kind == "VisibilityExport")
assert(C.MachineCastSToF.kind == "MachineCastSToF")
assert(C.ExternSym("extern:puts", "puts", "puts").symbol == "puts")

local B = T.MoonBack
local sig = B.BackSigId("sig:add_i32")
local func = B.BackFuncId("add_i32")
local entry = B.BackBlockId("entry")
local a = B.BackValId("a")
local b = B.BackValId("b")
local r = B.BackValId("r")
local program = B.BackProgram({
    B.CmdCreateSig(sig, { B.BackI32, B.BackI32 }, { B.BackI32 }),
    B.CmdDeclareFunc(C.VisibilityExport, func, sig),
    B.CmdBeginFunc(func),
    B.CmdCreateBlock(entry),
    B.CmdSwitchToBlock(entry),
    B.CmdBindEntryParams(entry, { a, b }),
    B.CmdIntBinary(r, B.BackIntAdd, B.BackI32, B.BackIntSemantics(B.BackIntWrap, B.BackIntMayLose), a, b),
    B.CmdReturnValue(r),
    B.CmdSealBlock(entry),
    B.CmdFinishFunc(func),
    B.CmdFinalizeModule,
})
assert(#program.cmds == 11)

local Ty = T.MoonType
local i32 = Ty.TScalar(C.ScalarI32)
assert(i32.scalar == C.ScalarI32)

local Code = T.MoonCode
local code_i32 = Code.CodeTyInt(32, Code.CodeSigned)
local code_sig = Code.CodeSigId("sig:add_i32")
local code_func = Code.CodeFuncId("fn:add_i32")
local code_extern = Code.CodeExternId("extern:puts")
local code_data = Code.CodeDataId("data:bytes")
local code_global = Code.CodeGlobalId("global:counter")
local code_block = Code.CodeBlockId("block:entry")
local code_value = Code.CodeValueId("value:result")
local code_origin = Code.CodeOriginGenerated("schema_core contract fixture")
local code_inst = Code.CodeInst(
    Code.CodeInstId("inst:const"),
    Code.CodeInstConst(code_value, Code.CodeConstLiteral(code_i32, C.LitInt("1"))),
    code_origin
)
assert(code_inst.id.text == "inst:const")
assert(pvm.classof(code_inst.kind) == Code.CodeInstConst)
local code_term = Code.CodeTerm(
    Code.CodeTermId("term:return"),
    Code.CodeTermReturn({ code_value }),
    code_origin
)
assert(code_term.id.text == "term:return")
local code_block_node = Code.CodeBlock(code_block, "entry", {}, { code_inst }, code_term, code_origin)
assert(code_block_node.term.id == code_term.id)
local access = Code.CodeMemoryAccess(Code.CodeMemoryRead, code_i32, 4, Code.CodeMayTrap, false, nil)
assert(access.mode == Code.CodeMemoryRead)
local reloc = Code.CodeReloc(Code.CodeRelocId("reloc:fn"), 0, Code.CodeGlobalRefFunc(code_func), 0, code_origin)
local data = Code.CodeData(code_data, "bytes", Code.CodeLinkageLocal, 8, 8, { Code.CodeDataReloc(reloc) }, code_origin)
local global = Code.CodeGlobal(code_global, "counter", code_i32, Code.CodeLinkageLocal, 4, 4, {}, code_origin)
local direct_call = Code.CodeCallDirect(code_func)
local extern_call = Code.CodeCallExtern(code_extern)
local indirect_call = Code.CodeCallIndirect(Code.CodeValueId("value:callee"), code_sig)
local closure_call = Code.CodeCallClosure(Code.CodeValueId("value:closure"), code_sig)
assert(direct_call.func == code_func)
assert(extern_call.extern == code_extern)
assert(indirect_call.sig == code_sig)
assert(closure_call.sig == code_sig)
local module = Code.CodeModule(
    Code.CodeModuleId("module:test"),
    { Code.CodeSig(code_sig, { code_i32, code_i32 }, { code_i32 }) },
    { Code.CodeTypeDecl(Code.CodeTypeId("type:i32"), "i32", code_i32, code_origin) },
    { data },
    { global },
    { Code.CodeExtern(code_extern, "puts", "puts", code_sig, code_origin) },
    { Code.CodeFunc(code_func, "add_i32", Code.CodeLinkageExport, code_sig, {}, {}, code_block, { code_block_node }, code_origin) },
    code_origin
)
assert(module.id.text == "module:test")
assert(module.data[1].id == code_data)

local contract_fact = Code.CodeFuncContractFact(
    code_func,
    Code.CodeContractBounds(Code.CodeValueId("value:ptr"), Code.CodeValueId("value:n")),
    code_origin
)
local contract_set = Code.CodeContractFactSet(module.id, { contract_fact })
assert(contract_set.facts[1].func == code_func)

local Flow = T.MoonFlow
local loop_id = Flow.FlowLoopId("loop:add_i32:entry")
local loop_header = Code.CodeBlockId("block:loop")
local loop_latch = Code.CodeBlockId("block:latch")
local loop_exit = Code.CodeBlockId("block:exit")
local i_val = Code.CodeValueId("value:i")
local i_init = Code.CodeValueId("value:i.init")
local i_step = Code.CodeValueId("value:i.step")
local n_val = Code.CodeValueId("value:n")
local flow_range = Flow.FlowRangeSigned(i_val, Flow.FlowBoundConst("0"), Flow.FlowBoundValue(n_val))
local induction = Flow.FlowInduction(
    i_val,
    code_i32,
    i_init,
    i_step,
    Flow.FlowPrimaryInduction,
    flow_range
)
local edge = Flow.FlowEdge(
    Flow.FlowEdgeId("edge:latch:loop"),
    code_func,
    loop_latch,
    loop_header,
    Flow.FlowEdgeJump,
    { Flow.FlowRoleBackedge(loop_id) },
    { Flow.FlowEdgeArg(i_step, i_val) }
)
local exit = Flow.FlowLoopExit(loop_header, loop_exit, Code.CodeValueId("value:cond"))
local counted_domain = Flow.FlowDomainCounted(Flow.FlowCountedDomain(i_init, n_val, i_step, true))
local loop_facts = Flow.FlowLoopFacts(
    loop_id,
    Flow.FlowLoopFromCode(code_func, loop_header, loop_latch),
    counted_domain,
    { loop_header, loop_latch },
    { induction },
    { exit },
    {},
    {}
)
local flow_facts = Flow.FlowFactSet(module.id, { edge }, { loop_facts }, { flow_range }, {})
assert(flow_facts.loops[1].inductions[1].value == i_val)
assert(flow_facts.edges[1].roles[1].loop == loop_id)
local trip_count = Flow.FlowTripCountNonNegative(Flow.FlowBoundValue(n_val), "fixture n iterations when n is non-negative")
local normalized_loop = Flow.FlowLoopNormalizedCounted(loop_id, Flow.FlowCountedDomain(i_init, n_val, i_step, true), Flow.FlowLoopIncreasing, trip_count)
local induction_range_fact = Flow.FlowInductionRangeFact(loop_id, i_val, Flow.FlowBoundConst("0"), Flow.FlowBoundValue(n_val), true, "fixture 0 <= i < n")
local flow_semantics = Flow.FlowSemanticFactSet(module.id, {
    normalized_loop,
    Flow.FlowLoopInductionRange(induction_range_fact),
    Flow.FlowLoopInductionNoWrap(loop_id, i_val, "fixture proof"),
})
assert(flow_semantics.facts[1].trip_count == trip_count)
assert(flow_semantics.facts[2].range.max_exclusive == true)

local Mem = T.MoonMem
local access_id = Mem.MemAccessId("mem:add_i32:load:0")
local access_place = Code.CodePlaceDeref(Code.CodeValueId("value:ptr"), code_i32, 4)
local mem_proof = Mem.MemProofContract(contract_fact, "parameter bounds contract")
local mem_access = Mem.MemAccessFact(
    access_id,
    code_func,
    loop_header,
    code_inst.id,
    Mem.MemLoad,
    access_place,
    access,
    Mem.MemBaseArgument("ptr", Code.CodeValueId("value:ptr")),
    Mem.MemIndexInduction(induction, 4, 0),
    Mem.MemAccessContiguous,
    Mem.MemAlignKnown(4),
    Mem.MemBoundsAssumed(mem_proof),
    Mem.MemCheckedTrap("guarded by contract")
)
local alias_fact = Mem.MemAliasScope(access_id, Mem.MemScopeId("scope:ptr"))
local mem_facts = Mem.MemFactSet(module.id, { mem_access }, { alias_fact }, {}, { mem_proof })
assert(mem_facts.accesses[1].index.induction == induction)
assert(mem_facts.proofs[1].fact == contract_fact)
local mem_object = Mem.MemObjectFact(
    Mem.MemObjectId("obj:ptr:n"),
    code_func,
    Mem.MemObjectContract,
    Mem.MemProvContract(contract_fact),
    code_i32,
    Mem.MemExtentContract(contract_fact, "bounds(ptr, n) object extent"),
    Mem.MemStrideUnit
)
local interval = Mem.MemAccessInterval(access_id, mem_object.id, loop_id, mem_access.index, Flow.FlowBoundConst("1"), 4, 0, "one i32 element per iteration")
local interval_proof = Mem.MemProofInterval(interval, "0 <= i < n implies access interval is contained")
local safety_fact = Mem.MemAccessInBounds(interval, interval_proof)
local read_read = Mem.MemReadReadIndependent(access_id, access_id, "same load read/read is harmless")
local readonly_effect = Mem.MemObjectReadonly(mem_object.id, mem_proof)
local same_len_relation = Mem.MemObjectsSameLen(mem_object.id, mem_object.id, mem_proof)
local semantic_mem = Mem.MemSemanticFactSet(module.id, { mem_object }, { interval }, {
    safety_fact,
    Mem.MemAccessNonTrap(access_id, interval_proof),
    Mem.MemAccessMovable(access_id, interval_proof),
}, { readonly_effect }, { read_read }, { same_len_relation }, { mem_proof, interval_proof })
assert(semantic_mem.objects[1].provenance.fact == contract_fact)
assert(semantic_mem.safety[1].interval == interval)
assert(semantic_mem.effects[1].object == mem_object.id)
assert(semantic_mem.relations[1].a == mem_object.id)
local projected_object = Mem.MemObjectFact(
    Mem.MemObjectId("obj:ptr:n:field0"),
    code_func,
    Mem.MemObjectDerived,
    Mem.MemProvProjection(mem_object.id, Mem.MemProjectField, 0),
    code_i32,
    Mem.MemExtentBytes(4, "field projection fixture"),
    Mem.MemStrideUnit
)
assert(projected_object.provenance.projection == Mem.MemProjectField)

local Kernel = T.MoonKernel
local stream = Kernel.KernelStream(
    Kernel.KernelStreamId("stream:ptr"),
    Kernel.KernelStreamRead,
    mem_access.base,
    code_i32,
    Kernel.KernelOffsetInduction(induction),
    Kernel.KernelLenLoopDomain(loop_id),
    Mem.MemAccessContiguous,
    Mem.MemAlignKnown(4),
    Mem.MemBoundsAssumed(mem_proof),
    { access_id }
)
local kernel_proof = Kernel.KernelProofMemory(mem_proof, "memory fact accepted")
local safety = Kernel.KernelSafetyProven({ kernel_proof })
local counter = Kernel.KernelCounterI32(i_val, { Kernel.KernelProofFlow(loop_id, "counted loop") })
local scalar_expr = Kernel.KernelExprValue(Code.CodeValueId("value:scalar"))
local store = Kernel.KernelStore(stream, Kernel.KernelOffsetInduction(induction), scalar_expr)
local body = Kernel.KernelBodyCounted(loop_facts, counter, { stream }, {}, { Kernel.KernelEffectStore(store) }, Kernel.KernelResultVoid, safety)
local loop_subject = Kernel.KernelSubjectLoop(code_func, loop_id)
local scalar_plan = Kernel.KernelPlanned(
    Kernel.KernelId("kernel:scalar"),
    loop_subject,
    body,
    Kernel.KernelScheduleScalarIndex({ kernel_proof }),
    {}
)
local vector_plan = Kernel.KernelPlanned(
    Kernel.KernelId("kernel:vector"),
    loop_subject,
    body,
    Kernel.KernelScheduleVector(Kernel.KernelLaneVector(code_i32, 4), 1, 1, Kernel.KernelTailScalar, { kernel_proof }),
    { Kernel.KernelRejectSchedule("scalar fixture also records rejected schedules") }
)
local no_plan = Kernel.KernelNoPlan(loop_subject, { Kernel.KernelRejectUnsupportedLoop(loop_id, "fixture rejection") })
local func_plan = Kernel.KernelFuncPlan(code_func, scalar_plan)
local rejected_func_plan = Kernel.KernelFuncPlan(Code.CodeFuncId("fn:rejected"), no_plan)
local kernel_module = Kernel.KernelModulePlan(module.id, flow_facts, mem_facts, { func_plan, rejected_func_plan }, flow_semantics, semantic_mem)
assert(kernel_module.flow_semantics == flow_semantics)
assert(kernel_module.memory_semantics == semantic_mem)
assert(kernel_module.funcs[1].plan.schedule.kind == "KernelScheduleScalarIndex")
assert(vector_plan.schedule.shape.lanes == 4)
assert(kernel_module.funcs[2].plan.rejects[1].loop == loop_id)
local Lower = T.MoonLower
local lowered = Lower.LowerModule(module.id, Lower.LowerTargetC, kernel_module, {
    Lower.LowerFuncKernel(scalar_plan),
    Lower.LowerFuncCode(code_func),
})
assert(lowered.funcs[1].plan == scalar_plan)

io.write("moonlift schema_core ok\n")
