-- impl/tree_check/control.lua
-- Control flow fact computation leaf methods.

require("lalin.schema_v2")
local Tr  = require("lalin.schema_v2.tree")
local Sem = require("lalin.schema_v2.sem")

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
