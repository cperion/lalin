-- moon_cfg_validate.lua -- structural honesty checks for MoonCFG kernels.

local pvm = require("moonlift.pvm")
local Validate = require("lua_compile.validate")
local B = require("lua_compile.builders")
local T = B.T
local CFG, NF = T.MoonCFG, T.LuaNF

local M = {}

local FORBIDDEN_STRINGS = {
  call = true,
  close = true,
  generic_for = true,
  setlist = true,
  getvarg = true,
  out_tag = true,
  out_event_kind = true,
}

local FORBIDDEN_PROTOCOL_EXITS = {
  [NF.CallProtocolExit] = "CallProtocolExit",
  [NF.CloseProtocolExit] = "CloseProtocolExit",
  [NF.GenericForProtocolExit] = "GenericForProtocolExit",
  [NF.SetListProtocolExit] = "SetListProtocolExit",
  [NF.GetVargProtocolExit] = "GetVargProtocolExit",
}

local function add(errors, msg) errors[#errors + 1] = msg end

local function text_of_name(n)
  if type(n) == "table" and n.text ~= nil then return tostring(n.text) end
  return tostring(n or "")
end

local function walk(v, fn, seen)
  local tv = type(v)
  if tv ~= "table" then fn(v); return end
  seen = seen or {}
  if seen[v] then return end
  seen[v] = true
  fn(v)
  local cls = pvm.classof(v)
  if cls and rawget(cls, "__fields") then
    for _, f in ipairs(cls.__fields) do walk(v[f.name], fn, seen) end
  elseif not cls then
    for _, x in pairs(v) do walk(x, fn, seen) end
  end
end

local function validate_region(region, errors)
  if pvm.classof(region) ~= CFG.Region then add(errors, "expected MoonCFG.Region body"); return end
  local blocks = region.blocks or {}
  if #blocks ~= 1 then add(errors, "unsupported_region_shape:first_slice_requires_one_block") end
  local by_id = {}
  for i, block in ipairs(blocks) do
    if pvm.classof(block) ~= CFG.Block then add(errors, "region block " .. i .. " is not MoonCFG.Block") else
      if by_id[block.id] then add(errors, "duplicate_block_id:" .. text_of_name(block.id and block.id.name)) end
      by_id[block.id] = true
    end
  end
  if not by_id[region.entry] then add(errors, "missing_entry_block:" .. text_of_name(region.entry and region.entry.name)) end
  local function check_target(ref, where)
    if pvm.classof(ref) ~= CFG.BlockRef then add(errors, where .. ":expected_block_ref"); return end
    if not by_id[ref.id] then add(errors, where .. ":unresolved_block_ref:" .. text_of_name(ref.id and ref.id.name)) end
  end
  for _, block in ipairs(blocks) do
    local term = block.terminator
    local cls = pvm.classof(term)
    if cls == CFG.Jump then
      check_target(term.target, "jump")
    elseif cls == CFG.Branch then
      check_target(term.if_true, "branch.true")
      check_target(term.if_false, "branch.false")
    elseif cls == CFG.Switch then
      check_target(term.default, "switch.default")
      for _, arm in ipairs(term.arms or {}) do check_target(arm.target, "switch.arm") end
    elseif cls == CFG.Return or cls == CFG.Exit or cls == CFG.Continue or cls == CFG.Unreachable then
      -- terminal/resolved locally for this first slice
    else
      add(errors, "unsupported_or_missing_terminator:" .. tostring(term and term.kind))
    end
  end
end

function M.validate(kernel)
  local errors = {}
  if pvm.classof(kernel) ~= CFG.Kernel then add(errors, "expected MoonCFG.Kernel") end
  local ok_basic, basic = Validate.moon_cfg_kernel(kernel)
  for _, e in ipairs(basic or {}) do add(errors, e) end
  walk(kernel, function(v)
    local tv = type(v)
    if tv == "string" and FORBIDDEN_STRINGS[v] then add(errors, "forbidden_string_semantic_tag:" .. v) end
    if tv == "table" then
      local cls = pvm.classof(v)
      if cls == NF.Program then add(errors, "forbidden_executable_lua_nf_program") end
      if FORBIDDEN_PROTOCOL_EXITS[cls] then add(errors, "forbidden_protocol_exit:" .. FORBIDDEN_PROTOCOL_EXITS[cls]) end
      if cls == CFG.Param then
        local pname = text_of_name(v.name)
        if pname:match("^out_") then add(errors, "forbidden_param:" .. pname) end
      end
    end
  end)
  if pvm.classof(kernel) == CFG.Kernel then
    validate_region(kernel.body, errors)
  end
  return #errors == 0 and ok_basic, errors
end

return M
