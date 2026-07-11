-- impl/lower_emit_c/schedule_form.lua
-- Methods on Schedule.* and Lower.* types for C emission kernel selection.
-- Ported from lower_to_c.lua.

require("lalin.schema_v2")

local Lower    = require("lalin.schema_v2.lower")
local Schedule = require("lalin.schema_v2.schedule")

----------------------------------------------------------------------
-- Typed schedule-form and lower-strategy selection
----------------------------------------------------------------------

function Schedule.ScheduleScalarIndex:lower_emit_kernel_selection() return Lower.LowerEmitScalarKernel end
function Schedule.ScheduleScalarPointer:lower_emit_kernel_selection() return Lower.LowerEmitScalarKernel end
function Schedule.ScheduleVector:lower_emit_kernel_selection() return Lower.LowerEmitVectorKernel end
function Schedule.ScheduleClosedForm:lower_emit_kernel_selection() return Lower.LowerEmitClosedForm end
function Schedule.ScheduleNoPlan:lower_emit_kernel_selection() return Lower.LowerEmitUnsupported("scheduled kernel was rejected: " .. tostring(self.rejects[1])) end
function Schedule.SchedulePlanned:lower_emit_kernel_selection() return self.form:lower_emit_kernel_selection() end

function Lower.LowerStrategyCode:lower_emit_candidate(projection) return Lower.LowerEmitCodeCandidate end
function Lower.LowerStrategyClosedForm:lower_emit_candidate(projection) return Lower.LowerEmitClosedFormCandidate end
function Lower.LowerStrategyKernel:lower_emit_candidate(projection) return projection:lookup(self.kernel):lower_emit_candidate(self) end
function Lower.LowerScheduleByKernelFound:lower_emit_candidate(strategy) return Lower.LowerEmitKernelCandidate(self.entry.schedule) end
function Lower.LowerScheduleByKernelMissing:lower_emit_candidate(strategy) return Lower.LowerEmitMissingScheduleCandidate("missing schedule for kernel " .. self.kernel.text) end

function Lower.LowerEmitCodeCandidate:select_lower_emit() return Lower.LowerEmitCode end
function Lower.LowerEmitClosedFormCandidate:select_lower_emit() return Lower.LowerEmitClosedForm end
function Lower.LowerEmitKernelCandidate:select_lower_emit() return self.schedule:lower_emit_kernel_selection() end
function Lower.LowerEmitMissingScheduleCandidate:select_lower_emit() return Lower.LowerEmitMissingSchedule(self.reason) end
function Lower.LowerEmitUnsupportedCandidate:select_lower_emit() return Lower.LowerEmitUnsupported(self.reason) end

function Lower.LowerStrategyCode:lower_c_is_semantic_strategy() return false end
function Lower.LowerStrategyKernel:lower_c_is_semantic_strategy() return true end
function Lower.LowerStrategyClosedForm:lower_c_is_semantic_strategy() return true end

----------------------------------------------------------------------
-- LowerAddress → lower_c_serves_lane / lower_c_matches_block / lower_c_block_param_for
----------------------------------------------------------------------

function Lower.LowerAddressLaneUse:lower_c_serves_lane(lane)
  return self.lane == lane
end

function Lower.LowerAddressPlan:lower_c_serves_lane(lane)
  return false
end

function Lower.LowerCarrierBlockParam:lower_c_matches_block(func, block)
  return self.block == block
end

function Lower.LowerAddressBlockParam:lower_c_matches_block(func, block)
  return self.block == block
end

function Lower.LowerCarrierPlan:lower_c_block_param_for(func, block)
  for _, cp in ipairs(self.carriers or {}) do
    if cp:lower_c_matches_block(func, block) then return cp end
  end
  return nil
end

function Lower.LowerAddressPlan:lower_c_block_param_for(func, block)
  for _, addr in ipairs(self.addresses or {}) do
    if addr:lower_c_matches_block(func, block) then return addr end
  end
  return nil
end

----------------------------------------------------------------------
-- LowerAddress → lower_c_address_place
----------------------------------------------------------------------

function Lower.LowerAddressStrategy:lower_c_address_place(plan, c_emission, lane, block)
  return nil, "unsupported address strategy for C emission"
end

function Lower.LowerAddressReject:lower_c_address_place(plan, c_emission, lane, block)
  return nil, "lowering address rejected: " .. tostring(self.reason)
end

function Lower.LowerAddressCarryProjected:lower_c_address_place(plan, c_emission, lane, block)
  -- A carry-projected address: the carrier lives in a block param.
  local carrier = plan:lower_c_block_param_for(c_emission.current_func, block)
  if carrier == nil then return nil, "no carrier found for carry-projected address" end
  return carrier, nil
end

function Lower.LowerAddressPlan:lower_c_address_place(c_emission, lane, block)
  if lane == nil then return nil, "no lane given for address plan" end
  for _, addr in ipairs(self.addresses or {}) do
    if addr:lower_c_serves_lane(lane) then
      return addr:lower_c_address_place(self, c_emission, lane, block)
    end
  end
  return nil, "no address serves lane " .. tostring(lane)
end

----------------------------------------------------------------------
-- LowerAddressPlan → lower_c_is_active_for_kernel
----------------------------------------------------------------------

function Lower.LowerAddressPlan:lower_c_is_active_for_kernel(kplan)
  return self.kernel == kplan.id
end

----------------------------------------------------------------------
-- LowerCarrierStrategy → lower_c_is_carry_carrier
----------------------------------------------------------------------

function Lower.LowerCarrierStrategy:lower_c_is_carry_carrier()
  return false
end

function Lower.LowerCarrierCarry:lower_c_is_carry_carrier()
  return true
end

----------------------------------------------------------------------
-- LowerCover → lower_c_cover_blocks
----------------------------------------------------------------------


function Lower.LowerCoverFunction:lower_c_cover_blocks(func, graph_loops, add)
  for _, b in ipairs(func.blocks or {}) do add(b) end
end

function Lower.LowerCoverBlock:lower_c_cover_blocks(func, graph_loops, add)
  for _, b in ipairs(func.blocks or {}) do
    if b.id == self.block then add(b) end
  end
end

function Lower.LowerCoverLoop:lower_c_cover_blocks(func, graph_loops, add)
  graph_loops:lookup(self.loop):lower_c_cover_loop(func, add)
end
function Lower.LowerLoopByIdMissing:lower_c_cover_loop(func, add) end
function Lower.LowerLoopByIdFound:lower_c_cover_loop(func, add)
  for _, b in ipairs(func.blocks) do
    for _, graph_block in ipairs(self.entry.loop.body) do if graph_block.block == b.id then add(b) end end
  end
end

function Lower.LowerCoverBlockRange:lower_c_cover_blocks(func, graph_loops, add)
  local active = false
  for _, b in ipairs(func.blocks or {}) do
    if b.id == self.entry then active = true end
    if active then add(b) end
    if b.id == self.exit then break end
  end
end
