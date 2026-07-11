package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local asdl = require("lalin.asdl")
local T = asdl.context()
require("lalin.schema_projection")(T)
require("lalin.tree_typecheck")(T)

local C, Ty, Tr, Check = T.LalinCore, T.LalinType, T.LalinTree, T.LalinCheck
local i32 = Ty.TScalar(C.ScalarI32)
local function target(owner, member) return Tr.RegionInvokeTarget(C.Path({ C.Name(owner), C.Name(member) })) end
local one_target = target("Reject", "one")
local done = Tr.RegionCont("cont:Reject.one:done", "done", { Tr.BlockParam("value", i32) })
local region = Tr.Region(
    "Reject.one",
    { Ty.Param("x", i32) },
    { done },
    {},
    Tr.EntryControlBlock(Tr.BlockLabel("start"), {}, {}),
    {}
 )
local facts = Check.TypeModuleFacts({}, {}, {}, { Tr.TypeRegionDef(one_target, region) }, {}, {}, {})
local scope = Check.TypeValueScope("Rejects", {}, {}, {}, facts)
local input = Tr.RegionInvokeExpandInput(scope)
local value = Tr.ExprLit(Tr.ExprSurface, C.LitInt("1"))
local wire = Tr.RegionContWire("done", Tr.RegionWireBlock(Tr.BlockLabel("done"), {}))
local extra = Tr.RegionContWire("extra", Tr.RegionWireBlock(Tr.BlockLabel("done"), {}))

local function emit(id, invoke_target, args, wiring)
    return Tr.StmtRegionEmit(Tr.StmtSurface, id, invoke_target, args, wiring)
end
local function call(id, invoke_target, args, wiring)
    return Tr.StmtRegionCall(Tr.StmtSurface, id, invoke_target, args, wiring)
end
local function reject_class(stmt, expected_code)
    local result = stmt:typecheck_tree_expand_region_invoke(input)
    assert(asdl.classof(result) == Tr.RegionInvokeRejected, "fixture must reject")
    local report = Check.TypeIssueRegionInvoke(result.reject):typecheck_tree_explanation()
    assert(report.code == expected_code and report.primary ~= "", "every reject leaf must own an exact explanation")
    return asdl.classof(result.reject)
end

assert(reject_class(emit("missing", target("Reject", "missing"), { value }, { wire }), "E0408") == Tr.RegionInvokeMissingTarget)
assert(reject_class(emit("args", one_target, {}, { wire }), "E0408") == Tr.RegionInvokeArgCount)
assert(reject_class(emit("missing_wire", one_target, { value }, {}), "E0408") == Tr.RegionInvokeMissingWire)
assert(reject_class(emit("extra_wire", one_target, { value }, { wire, extra }), "E0408") == Tr.RegionInvokeExtraWire)
assert(reject_class(emit("duplicate", one_target, { value }, { wire, wire }), "E0203") == Tr.RegionInvokeDuplicateWire)
assert(reject_class(call("unsealed", one_target, { value }, { wire }), "E0408") == Tr.RegionInvokeCallFrameUnsupported)

io.write("lalin region invoke exact reject leaves ok\n")
