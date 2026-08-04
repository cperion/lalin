-- impl/tree_check/control.lua
-- Control flow fact computation leaf methods.

require("lalin.schema")
local Check = require("lalin.schema.check")
local Tr  = require("lalin.schema.tree")
local Sem = require("lalin.schema.sem")

function Tr.Stmt:typecheck_tree_flow_outcome() return Sem.FlowFallsThrough end
function Tr.StmtReturnValue:typecheck_tree_flow_outcome() return Sem.FlowReturns end
function Tr.StmtReturnVoid:typecheck_tree_flow_outcome() return Sem.FlowReturns end
function Tr.StmtYieldValue:typecheck_tree_flow_outcome() return Sem.FlowYields end
function Tr.StmtYieldVoid:typecheck_tree_flow_outcome() return Sem.FlowYields end
function Tr.StmtJump:typecheck_tree_flow_outcome() return Sem.FlowJumps end
function Tr.StmtBranchJump:typecheck_tree_flow_outcome() return Sem.FlowJumps end
function Tr.StmtTrap:typecheck_tree_flow_outcome() return Sem.FlowTerminates end

function Tr.Stmt:typecheck_tree_control_facts(ctx) return {} end
function Tr.StmtIf:typecheck_tree_control_facts(ctx)
  local facts = {}
  self:typecheck_tree_body_control_facts(self.then_body, ctx, facts)
  self:typecheck_tree_body_control_facts(self.else_body, ctx, facts)
  return facts
end
function Tr.StmtSwitch:typecheck_tree_control_facts(ctx)
  local facts = {}
  for _, arm in ipairs(self.arms or {}) do self:typecheck_tree_body_control_facts(arm.body, ctx, facts) end
  self:typecheck_tree_body_control_facts(self.default_body or {}, ctx, facts)
  return facts
end
function Tr.StmtControl:typecheck_tree_control_facts(ctx)
  return self.region:typecheck_tree_region_control_facts(ctx)
end
function Tr.StmtDomainControl:typecheck_tree_control_facts(ctx)
  return self.region:typecheck_tree_region_control_facts(ctx)
end
function Tr.Stmt:typecheck_tree_body_control_facts(body, ctx, facts)
  for _, s in ipairs(body or {}) do
    local f = s:typecheck_tree_control_facts(ctx)
    if type(f) == "table" then for _, fact in ipairs(f) do facts[#facts+1] = fact end end
  end
end
function Tr.ControlStmtRegion:typecheck_tree_region_control_facts(ctx)
  local facts = {}
  for _, b in ipairs({self.entry, unpack(self.blocks or {})}) do
    for _, s in ipairs(b.body or {}) do
      local f = s:typecheck_tree_control_facts(ctx)
      if type(f) == "table" then for _, fact in ipairs(f) do facts[#facts+1] = fact end end
    end
  end
  return facts
end
function Tr.ControlExprRegion:typecheck_tree_region_control_facts(ctx)
  local facts = {}
  for _, b in ipairs({self.entry, unpack(self.blocks or {})}) do
    for _, s in ipairs(b.body or {}) do
      local f = s:typecheck_tree_control_facts(ctx)
      if type(f) == "table" then for _, fact in ipairs(f) do facts[#facts+1] = fact end end
    end
  end
  return facts
end

-- ============================================================
-- Region control-context wiring validation.
-- The typecheck input carries the enclosing region''s block/cont tables;
-- jump and region-call wiring resolve against them and emit typed issues.
-- ============================================================
function Check.TypeControlNone:typecheck_control_block(label) return Check.TypeControlBlockMissing(label) end
function Check.TypeControlRegion:typecheck_control_block(label)
  for i = 1, #(self.blocks or {}) do
    if self.blocks[i].label.name == label.name then return Check.TypeControlBlockFound(self.blocks[i]) end
  end
  return Check.TypeControlBlockMissing(label)
end
function Check.TypeControlNone:typecheck_control_cont(name) return Check.TypeControlContMissing(name) end
function Check.TypeControlRegion:typecheck_control_cont(name)
  for i = 1, #(self.conts or {}) do
    if self.conts[i].name == name then return Check.TypeControlContFound(self.conts[i]) end
  end
  return Check.TypeControlContMissing(name)
end
function Check.TypeControlContext:typecheck_control_region_id() return "" end
function Check.TypeControlRegion:typecheck_control_region_id() return self.region_id end

local function resolve_ty(scope, ty)
  if ty == nil then return nil end
  local resolved = ty:tree_region_resolve_type(scope)
  return resolved and resolved or ty
end
local function validate_target_args(region_id, scope, label, params, args, issues, payload_params)
  local by_name = {}
  for i = 1, #(params or {}) do by_name[params[i].name] = params[i] end
  local payload = {}
  for i = 1, #(payload_params or {}) do payload[payload_params[i].name] = payload_params[i] end
  local seen = {}
  for i = 1, #(args or {}) do
    local a = args[i]
    local param = by_name[a.name]
    if param == nil then
      issues[#issues + 1] = Check.TypeIssueExtraJumpArg(region_id, label, a.name)
    elseif seen[a.name] then
      issues[#issues + 1] = Check.TypeIssueDuplicateJumpArg(region_id, label, a.name)
    else
      seen[a.name] = true
      local aty = a.value.h and a.value.h.ty
      if aty ~= nil and param.ty ~= nil then
        local ar, pr = resolve_ty(scope, aty), resolve_ty(scope, param.ty)
        if ar ~= pr then
          issues[#issues + 1] = Check.TypeIssueExpected("jump arg `" .. a.name .. "`", param.ty, aty)
        end
      end
    end
  end
  for i = 1, #(params or {}) do
    local p = params[i]
    if not seen[p.name] then
      if payload[p.name] ~= nil then
        seen[p.name] = true
        local pr, prp = resolve_ty(scope, p.ty), resolve_ty(scope, payload[p.name].ty)
        if pr ~= prp then
          issues[#issues + 1] = Check.TypeIssueExpected("cont payload `" .. p.name .. "`", p.ty, payload[p.name].ty)
        end
      else
        issues[#issues + 1] = Check.TypeIssueMissingJumpArg(region_id, label, p.name)
      end
    end
  end
end
function Check.TypeControlBlockMissing:typecheck_validate_jump(region_id, _scope, label, _args, issues, _payload)
  issues[#issues + 1] = Check.TypeIssueMissingJumpTarget(region_id, label)
end
function Check.TypeControlBlockFound:typecheck_validate_jump(region_id, scope, label, args, issues, payload_params)
  validate_target_args(region_id, scope, label, self.block.params, args, issues, payload_params)
end
function Check.TypeControlBlockMissing:typecheck_validate_jump(region_id, _scope, label, _args, issues)
  issues[#issues + 1] = Check.TypeIssueMissingJumpTarget(region_id, label)
end
function Check.TypeControlBlockFound:typecheck_validate_jump(region_id, scope, label, args, issues)
  validate_target_args(region_id, scope, label, self.block.params, args, issues)
end
function Check.TypeControlContMissing:typecheck_validate_cont_jump(region_id, _scope, name, _args, issues)
  issues[#issues + 1] = Check.TypeIssueRegionContMissing(region_id, name)
end
function Check.TypeControlContFound:typecheck_validate_cont_jump(region_id, scope, _name, args, issues)
  validate_target_args(region_id, scope, Tr.BlockLabel(self.cont.name), self.cont.params, args, issues)
end
