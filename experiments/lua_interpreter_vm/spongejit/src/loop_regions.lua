-- loop_regions.lua -- structural loop-region recognition for SpongeJIT.
--
-- Loop bytecodes are not scalar stencil atoms. This module recognizes validated
-- PUC-style loop topology as data so later region lowering can consume whole
-- loops with explicit edges, slot windows, and per-instance PC bindings.

local M = {}

M.DIALECT = "puc_lua_5_5"

local NUMERIC_FOR = { FORPREP = true, FORLOOP = true }
local GENERIC_FOR = { TFORPREP = true, TFORCALL = true, TFORLOOP = true }

function M.is_numeric_for_opcode(op) return NUMERIC_FOR[tostring(op or "")] == true end
function M.is_generic_for_opcode(op) return GENERIC_FOR[tostring(op or "")] == true end
function M.is_for_opcode(op) return M.is_numeric_for_opcode(op) or M.is_generic_for_opcode(op) end

local function name(row) return tostring(row and (row.name or row.op) or "") end
local function n(row, key) return tonumber(row and row[key]) end
local function proto_of(row) return row and row.proto or "" end

local function slot_window(first_slot, last_slot)
  local out = {}
  first_slot = tonumber(first_slot) or 0
  last_slot = tonumber(last_slot) or first_slot
  for s = first_slot, last_slot do out[#out + 1] = s end
  return out
end

local function reject(out, row, reason, detail)
  out[#out + 1] = {
    dialect = M.DIALECT,
    proto = proto_of(row),
    pc = n(row, "pc") or 0,
    op = name(row),
    reason = reason,
    detail = detail,
  }
end

local function row_index(rows)
  local by_pc = {}
  for _, row in ipairs(rows or {}) do by_pc[n(row, "pc") or -1] = row end
  return by_pc
end

local function numeric_region(row, by_pc, rejects)
  local prep_pc, prep_bx, base = n(row, "pc"), n(row, "bx"), n(row, "a")
  if prep_pc == nil or prep_bx == nil or base == nil then
    reject(rejects, row, "numeric_for_missing_fields")
    return nil
  end

  -- PUC parser encodes FORPREP.Bx as loop_pc - (prep_pc + 1).
  local loop_pc = prep_pc + 1 + prep_bx
  local loop = by_pc[loop_pc]
  if name(loop) ~= "FORLOOP" then
    reject(rejects, row, "numeric_for_missing_forloop", { expected_pc = loop_pc, found = name(loop) })
    return nil
  end
  if n(loop, "a") ~= base then
    reject(rejects, row, "numeric_for_base_mismatch", { loop_pc = loop_pc, prep_a = base, loop_a = n(loop, "a") })
    return nil
  end
  local expected_loop_bx = loop_pc - prep_pc
  if n(loop, "bx") ~= expected_loop_bx then
    reject(rejects, row, "numeric_for_backedge_mismatch", { loop_pc = loop_pc, expected_bx = expected_loop_bx, loop_bx = n(loop, "bx") })
    return nil
  end

  return {
    kind = "numeric_for_region",
    dialect = M.DIALECT,
    proto = proto_of(row),
    base = base,
    prep_pc = prep_pc,
    body_entry_pc = prep_pc + 1,
    loop_pc = loop_pc,
    exit_pc = loop_pc + 1,
    prep_bx = prep_bx,
    loop_bx = expected_loop_bx,
    slot_window = slot_window(base, base + 3),
    state_slots = {
      pre_prep = { init = base, limit = base + 1, step = base + 2, external = base + 3 },
      post_prep = { counter = base, step = base + 1, control = base + 2, external = base + 3 },
    },
    edges = {
      enter_body = { from_pc = prep_pc, to_pc = prep_pc + 1 },
      skip = { from_pc = prep_pc, to_pc = loop_pc + 1 },
      continue_loop = { from_pc = loop_pc, to_pc = prep_pc + 1 },
      done = { from_pc = loop_pc, to_pc = loop_pc + 1 },
    },
  }
end

local function generic_region(row, by_pc, rejects)
  local prep_pc, prep_bx, base = n(row, "pc"), n(row, "bx"), n(row, "a")
  if prep_pc == nil or prep_bx == nil or base == nil then
    reject(rejects, row, "generic_for_missing_fields")
    return nil
  end

  -- PUC TFORPREP jumps from pre-incremented PC to TFORCALL.
  local call_pc = prep_pc + 1 + prep_bx
  local call = by_pc[call_pc]
  if name(call) ~= "TFORCALL" then
    reject(rejects, row, "generic_for_missing_tforcall", { expected_pc = call_pc, found = name(call) })
    return nil
  end
  if n(call, "a") ~= base then
    reject(rejects, row, "generic_for_call_base_mismatch", { call_pc = call_pc, prep_a = base, call_a = n(call, "a") })
    return nil
  end

  local loop_pc = call_pc + 1
  local loop = by_pc[loop_pc]
  if name(loop) ~= "TFORLOOP" then
    reject(rejects, row, "generic_for_missing_tforloop", { expected_pc = loop_pc, found = name(loop) })
    return nil
  end
  if n(loop, "a") ~= base then
    reject(rejects, row, "generic_for_loop_base_mismatch", { loop_pc = loop_pc, prep_a = base, loop_a = n(loop, "a") })
    return nil
  end
  local expected_loop_bx = loop_pc - prep_pc
  if n(loop, "bx") ~= expected_loop_bx then
    reject(rejects, row, "generic_for_backedge_mismatch", { loop_pc = loop_pc, expected_bx = expected_loop_bx, loop_bx = n(loop, "bx") })
    return nil
  end

  local nresults = n(call, "c") or 0
  local last_slot = base + math.max(5, 3 + nresults)
  return {
    kind = "generic_for_region",
    dialect = M.DIALECT,
    proto = proto_of(row),
    base = base,
    prep_pc = prep_pc,
    body_entry_pc = prep_pc + 1,
    call_pc = call_pc,
    loop_pc = loop_pc,
    exit_pc = loop_pc + 1,
    prep_bx = prep_bx,
    loop_bx = expected_loop_bx,
    result_count = nresults,
    slot_window = slot_window(base, last_slot),
    state_slots = {
      function_slot = base,
      state_slot = base + 1,
      closing_slot = base + 2,
      control_slot = base + 3,
      call_func_slot = base + 3,
      call_state_slot = base + 4,
      call_control_slot = base + 5,
      first_result_slot = base + 4,
      last_result_slot = base + 3 + nresults,
    },
    edges = {
      enter_body = { from_pc = prep_pc, to_pc = prep_pc + 1 },
      call_iterator = { from_pc = prep_pc, to_pc = call_pc },
      continue_loop = { from_pc = loop_pc, to_pc = prep_pc + 1 },
      done = { from_pc = loop_pc, to_pc = loop_pc + 1 },
    },
  }
end

function M.find_in_rows(rows)
  local by_pc = row_index(rows)
  local regions, rejects = {}, {}
  for _, row in ipairs(rows or {}) do
    local op = name(row)
    local r = nil
    if op == "FORPREP" then r = numeric_region(row, by_pc, rejects)
    elseif op == "TFORPREP" then r = generic_region(row, by_pc, rejects)
    elseif op == "FORLOOP" then
      -- Matched from FORPREP; standalone FORLOOP is not a scalar region root.
    elseif op == "TFORCALL" or op == "TFORLOOP" then
      -- Matched from TFORPREP; standalone TFOR* members are not roots.
    end
    if r then regions[#regions + 1] = r end
  end
  table.sort(regions, function(a, b)
    if tostring(a.proto) ~= tostring(b.proto) then return tostring(a.proto) < tostring(b.proto) end
    return (a.prep_pc or 0) < (b.prep_pc or 0)
  end)
  return regions, rejects
end

function M.region_key(r)
  if not r then return "" end
  return table.concat({
    tostring(r.dialect or M.DIALECT),
    tostring(r.kind),
    "base=" .. tostring(r.base),
    "prep=" .. tostring(r.prep_pc),
    "body=" .. tostring(r.body_entry_pc),
    "loop=" .. tostring(r.loop_pc),
    "exit=" .. tostring(r.exit_pc),
  }, ":")
end

return M
