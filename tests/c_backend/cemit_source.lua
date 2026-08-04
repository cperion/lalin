-- tests/c_backend/cemit_source.lua
-- Shared test helper: render a CBackendUnit to C source text through the
-- schema CEmitMachine (the retired lalin.emit_c_lower emitter is gone).

require("lalin.schema")
require("lalin.impl.cemit_emit")

local Cemit = require("lalin.schema.cemit")
local Lower = require("lalin.schema.lower")
local Code = require("lalin.schema.code")
local Graph = require("lalin.schema.graph")

local M = {}

function M.source(c_unit, c_target)
  local spine_module = Code.CodeModule(
    Code.CodeModuleId("cemit_spine"), {}, {}, {}, {}, {}, {}, Code.CodeOriginUnknown)
  local spine = Lower.LowerBackSpine(
    spine_module, Graph.CodeGraph(spine_module.id, {}), c_target)
  return Cemit.CEmitMachine(spine, {}, {}, {}, {}):emit_module(c_unit).source
end

return M
