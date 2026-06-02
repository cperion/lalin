-- lua_compile/errors.lua -- structured rejection helpers.
--
-- Unsupported cases are compile/lower/select rejections.  This module contains
-- no fallback/helper logic.

local Schema = require("lua_compile.schema")
local T = Schema.get()
local Src = T.LuaSrc
local Sem = T.LuaSem

local M = {}

local REASON = {
  contradictory_evidence = Sem.ContradictoryEvidence,
  missing_fact = Sem.MissingFact,
  missing_payload_lease = Sem.MissingPayloadLease,
  unsupported_opcode = Sem.UnsupportedOpcode,
  unsupported_fact_combination = Sem.UnsupportedFactCombination,
  unsupported_semantic_case = Sem.UnsupportedSemanticCase,
  semantic_not_implemented = Sem.UnsupportedSemanticCase,
  requires_fact_bundle = Sem.MissingFact,
  unsupported_loop_region = Sem.UnsupportedLoopRegion,
  unsupported_projection = Sem.UnsupportedProjection,
  internal_invariant_failure = Sem.InternalInvariantFailure,
}

function M.reason(name)
  return REASON[name] or REASON[tostring(name or ""):lower()] or Sem.InternalInvariantFailure
end

function M.rejection(pc, reason, source_op, missing_facts, missing_payloads)
  local pc_node = type(pc) == "table" and pc or Src.Pc(tonumber(pc) or 0)
  local op = source_op or Src.UnsupportedOpcode(pc_node, "<unknown>")
  return Sem.Rejection(pc_node, M.reason(reason), op, missing_facts or {}, missing_payloads or {})
end

function M.result_reject(pc, reason, source_op, missing_facts, missing_payloads)
  return Sem.Rejected(M.rejection(pc, reason, source_op, missing_facts, missing_payloads))
end

function M.result_accept(program)
  return Sem.Accepted(program)
end

return M
