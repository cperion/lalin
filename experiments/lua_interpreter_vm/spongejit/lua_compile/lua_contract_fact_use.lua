-- lua_contract_fact_use.lua -- fact role construction.

local B = require("lua_compile.builders")
local C = B.LuaContract

local M = {}
function M.use(role, subject, predicate, value_key, deps) return C.FactUse(role, subject, predicate, value_key or "", deps or {}) end
function M.checked(subject, predicate, value_key, deps) return M.use(C.Checked, subject, predicate, value_key, deps) end
function M.required(subject, predicate, value_key, deps) return M.use(C.Required, subject, predicate, value_key, deps) end
function M.produced(subject, predicate, value_key, deps) return M.use(C.Produced, subject, predicate, value_key, deps) end
function M.killed(subject, predicate, value_key, deps) return M.use(C.Killed, subject, predicate, value_key, deps) end
return M
