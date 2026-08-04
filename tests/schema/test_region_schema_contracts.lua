package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local T = require("lalin.schema")
local Tr, Check, Ty, C = T.LalinTree, T.LalinCheck, T.LalinType, T.LalinCore

local definitions = Tr.RegionDefinitionProjection({})
local protocols = Tr.RegionProtocolProjection({})
local seals = Tr.RegionSealProjection({})
local bundles = Tr.RegionBundleProjection({})
local region_facts = Tr.RegionFactProjection(definitions, protocols, seals, bundles)
local facts = Check.TypeModuleFacts({}, {}, {}, region_facts)
local scope = Check.TypeValueScope("m", {}, {}, {}, facts)
local i32 = Ty.TScalar(C.ScalarI32)
local state = Check.TypeStmtInput(scope, i32, Check.TypeYieldNone)
local expansion = Tr.RegionExpansionId("region-1")

local stmt_input = Tr.RegionStmtExpansionInput(state, region_facts, expansion)
local body_input = Tr.RegionBodyExpansionInput(state, region_facts, expansion)
local block_input = Tr.RegionBlockExpansionInput(state, region_facts, expansion)
assert(stmt_input.facts == region_facts and body_input.state == state and block_input.expansion == expansion)

local captures = Tr.RegionCallCaptureProjection({})
local entry = Tr.StmtTrap(Tr.StmtSurface)
local splice = Tr.RegionInvokeSplice(entry, {}, captures, state)
assert(T.LalinTree.RegionInvokeExpanded(splice).splice == splice)

local body = Tr.RegionStmtBody({ entry })
local body_result = Tr.RegionBodyExpansionResult(state, body, {}, {})
assert(body_result.body == body)

local module_input = Tr.RegionModuleExpansionInput(region_facts)
assert(module_input.facts == region_facts)
assert(not pcall(function() Tr.RegionFactProjection({}, protocols, seals, bundles) end),
  "region projections must reject loose tables")
assert(not pcall(function() Check.TypeModuleFacts({}, {}, {}, {}) end),
  "module facts must require the typed region facet")

assert(Tr.RegionDefinitionFound and Tr.RegionDefinitionMissing)
assert(Tr.RegionProtocolFound and Tr.RegionProtocolMissing)
assert(Tr.RegionSealFound and Tr.RegionSealMissing)
assert(Tr.RegionBundleFound and Tr.RegionBundleMissing)
assert(Tr.RegionWireFound and Tr.RegionWireMissing)

print("schema region contracts ok")
