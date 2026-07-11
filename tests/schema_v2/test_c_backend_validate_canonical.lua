package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local asdl = require("lalin.asdl")
local T = require("lalin.schema_v2")
require("lalin.impl.lower_emit_c")
require("lalin.impl.cemit_emit")

local C = T.LalinC
local Core = T.LalinCore
local Code = T.LalinCode
local Graph = T.LalinGraph
local Lower = T.LalinLower
local Cemit = T.LalinCEmit
local Validate = require("lalin.impl.lower_emit_c.validate")

assert(package.loaded["lalin.emit_c_validate"] == nil, "canonical context must not load the legacy validator")
assert(C.CBackendValidationReport and not C.CBackendValidationResult, "canonical context has exactly one validation report")
assert(C.CBackendUnit.validate_c_unit == nil, "stale validator entrypoint must be absent")
assert(C.CBackendValidationInput.c_validate and C.CBackendUnit.c_validate, "validation is owned by typed roots")

local function rejects(label, f)
  local ok = pcall(f)
  assert(not ok, label .. " must reject an untyped relation payload")
end
rejects("signature relation", function() C.CBackendValidationSignatureRelation({ { id = "raw" } }) end)
rejects("local relation", function() C.CBackendValidationLocalRelation({ { id = "raw" } }) end)

local function has(report, class)
  assert(asdl.classof(report) == C.CBackendValidationReport)
  for i = 1, #report.issues do if asdl.classof(report.issues[i]) == class then return true end end
  return false
end

local i32 = C.CBackendScalar(Core.ScalarI32)
local target = C.CBackendTarget(C.CBackendC11, C.CBackendHostedNative, 64, 64, C.CBackendLittleEndian, true)
local sid = C.CBackendFuncSigId("answer.sig")
local sig = C.CBackendFuncSig(sid, {}, i32)
local entry = C.CBackendLabel("entry")
local block = C.CBackendBlock(entry, {}, {}, C.CBackendReturn(C.CBackendAtomLiteral(i32, Core.LitInt("42"))))
local func = C.CBackendFunc(C.CBackendName("answer"), "answer", Core.VisibilityExport, sid, {}, {}, C.CBackendBodyBlocks(entry, { block }))
local unit = C.CBackendUnit("canonical_validation", target, { sig }, {}, {}, {}, {}, { func })
assert(#Validate.validate(unit).issues == 0, "valid canonical unit must validate")
assert(#Validate.validate_input(C.CBackendValidationInput(unit, {}, {})).issues == 0)

local no_sig = C.CBackendUnit("bad", target, {}, {}, {}, {}, {}, { func })
assert(has(Validate.validate(no_sig), C.CBackendIssueMissingSig), "missing signature must be rejected")

local bad_local_block = C.CBackendBlock(entry, {}, {}, C.CBackendReturn(C.CBackendAtomLocal(C.CBackendLocalId("absent"))))
local bad_local_func = C.CBackendFunc(C.CBackendName("bad_local"), "bad_local", Core.VisibilityLocal, sid, {}, {}, C.CBackendBodyBlocks(entry, { bad_local_block }))
assert(has(Validate.validate(C.CBackendUnit("bad", target, { sig }, {}, {}, {}, {}, { bad_local_func })), C.CBackendIssueMissingLocal), "missing local must be rejected")

local bad_label_block = C.CBackendBlock(entry, {}, {}, C.CBackendGoto(C.CBackendLabel("absent"), {}))
local bad_label_func = C.CBackendFunc(C.CBackendName("bad_label"), "bad_label", Core.VisibilityLocal, sid, {}, {}, C.CBackendBodyBlocks(entry, { bad_label_block }))
assert(has(Validate.validate(C.CBackendUnit("bad", target, { sig }, {}, {}, {}, {}, { bad_label_func })), C.CBackendIssueMissingLabel), "missing label must be rejected")

local local_id = C.CBackendLocalId("r")
local bad_helper_block = C.CBackendBlock(entry, {}, { C.CBackendHelperCall(local_id, C.CBackendHelperId("absent"), {}) }, C.CBackendReturn(C.CBackendAtomLocal(local_id)))
local bad_helper_func = C.CBackendFunc(C.CBackendName("bad_helper"), "bad_helper", Core.VisibilityLocal, sid, {}, { C.CBackendLocal(local_id, C.CBackendName("r"), i32) }, C.CBackendBodyBlocks(entry, { bad_helper_block }))
assert(has(Validate.validate(C.CBackendUnit("bad", target, { sig }, {}, {}, {}, {}, { bad_helper_func })), C.CBackendIssueMissingHelper), "missing helper must be rejected")

local global = C.CBackendGlobal(C.CBackendGlobalId("g"), C.CBackendName("g"), Core.VisibilityLocal, i32, 4, 4, { C.CBackendDataBytes(3, "xx") })
assert(has(Validate.validate(C.CBackendUnit("bad", target, {}, {}, { global }, {}, {}, {})), C.CBackendIssueDataInitOutOfBounds), "out-of-bounds data must be rejected")

-- Validate, emit, compile with GCC, and execute the exported value.
local module_id = Code.CodeModuleId("canonical_validation")
local code_module = Code.CodeModule(module_id, {}, {}, {}, {}, {}, {}, Code.CodeOriginUnknown)
local machine = Cemit.CEmitMachine(Lower.LowerBackSpine(code_module, Graph.CodeGraph(module_id, {}), target), {}, {}, {}, {})
local artifact = machine:emit_module(unit)
local base = os.tmpname()
local c_path, so_path = base .. ".c", base .. ".so"
local out = assert(io.open(c_path, "wb")); out:write(artifact.source); out:close()
local rc = os.execute(string.format("cc -shared -fPIC -O2 -o %q %q", so_path, c_path))
assert(rc == true or rc == 0, "GCC smoke compile failed")
local ffi = require("ffi")
ffi.cdef("int32_t answer(void);")
assert(ffi.load(so_path).answer() == 42, "validated GCC artifact returned wrong value")
os.remove(c_path); os.remove(so_path)

io.write("canonical CBackend validation ok\n")
