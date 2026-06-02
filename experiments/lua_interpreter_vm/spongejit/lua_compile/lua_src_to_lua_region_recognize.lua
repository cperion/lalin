-- lua_src_to_lua_region_recognize.lua -- recognize structured control topology.

local B = require("lua_compile.builders")
local T = B.T
local Src, Region = T.LuaSrc, T.LuaRegion

local M = {}

local function slot_plus(s, d) return B.slot((s and s.id or 0) + d) end
local function pc_plus(pc, d) return B.pc((pc and pc.id or 0) + d) end

function M.recognize(window)
  local regions = {}
  local ops = (window and window.ops) or {}
  local by_pc = {}
  for _, op in ipairs(ops) do if op.pc then by_pc[op.pc.id] = op end end
  for _, op in ipairs(ops) do
    if op.kind == "FORPREP" then
      local loop_pc = (op.pc.id or 0) + (op.offset.value or 0) + 1
      local loop = by_pc[loop_pc]
      if loop and loop.kind == "FORLOOP" and loop.base.id == op.base.id then
        local base = op.base
        local body = pc_plus(op.pc, 1)
        local exit = pc_plus(loop.pc, 1)
        local slots = Region.SlotWindow(base, slot_plus(base, 3))
        local state = Region.NumericForState(base, slot_plus(base, 1), slot_plus(base, 2), slot_plus(base, 3))
        local edges = {
          Region.EnterBody(op.pc, body),
          Region.Skip(op.pc, exit),
          Region.Continue(loop.pc, body),
          Region.Done(loop.pc, exit),
        }
        regions[#regions + 1] = Region.NumericFor(base, op.pc, body, loop.pc, exit, slots, state, edges)
      end
    end
  end
  return Region.RegionSet(regions)
end

return M
