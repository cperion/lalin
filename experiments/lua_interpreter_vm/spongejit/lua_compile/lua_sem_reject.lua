-- lua_sem_reject.lua -- structured semantic rejection reasons.

local Errors = require("lua_compile.errors")

local M = {}

function M.reject(op, reason, missing_facts, missing_payloads)
  return Errors.result_reject(op and op.pc or 0, reason or "unsupported_semantic_case", op, missing_facts or {}, missing_payloads or {})
end

return M
