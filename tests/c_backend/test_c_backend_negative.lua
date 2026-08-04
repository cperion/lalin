package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local asdl = require("lalin.asdl")
local T = require("lalin.schema")
require("lalin.impl.lower_emit_c")
local Core = T.LalinCore
local C = T.LalinC
local CodeType = require("lalin.impl.code_type")(T)
local Validate = require("lalin.impl.lower_emit_c.validate")

local i32 = C.CBackendScalar(Core.ScalarI32)
local access = C.CBackendMemoryAccess(i32, 4, C.CBackendMayTrap, true, Core.AtomicSeqCst)
local atomic = C.CBackendHelperUse(
  C.CBackendHelperAtomicLoad(access):c_helper_id(), C.CBackendHelperAtomicLoad(access))
local report = Validate.validate(C.CBackendUnit("m", CodeType.default_target({ dialect = "c99" }), {}, {}, {}, {}, { atomic }, {}))
local saw_atomic_feature = false
for i = 1, #report.issues do if asdl.classof(report.issues[i]) == C.CBackendIssueInvalidTargetFeature then saw_atomic_feature = true end end
assert(saw_atomic_feature, "atomics without C11 target support should be diagnosed")
assert(package.loaded["lalin.tree_to_c"] == nil)
assert(package.loaded["lalin.c_places"] == nil)

io.write("lalin c_backend_negative ok\n")
