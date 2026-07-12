-- impl/tree_check/contract.lua
-- Contract fact computation leaf methods.

require("lalin.schema_v2")
local Tr  = require("lalin.schema_v2.tree")
local Sem = require("lalin.schema_v2.sem")
local Check = require("lalin.schema_v2.check")
local B = require("lalin.schema_v2.bind")

function Tr.Expr:tree_check_contract_binding() return nil end
function Tr.ExprRef:tree_check_contract_binding() return self.ref:tree_check_contract_binding() end
function B.ValueRef:tree_check_contract_binding() return nil end
function B.ValueRefBinding:tree_check_contract_binding() return self.binding end
local function calculated(fact) return {fact} end
local function rejected(name) return calculated(Tr.ContractFactRejected(Check.TypeIssueUnresolvedValue(name))) end

function Tr.FuncContract:tree_check_contract_fact() return {} end
function Tr.ContractBounds:tree_check_contract_fact()
  local base, len = self.base:tree_check_contract_binding(), self.len:tree_check_contract_binding()
  if base and len then return calculated(Tr.ContractFactBounds(base, len)) end
  return calculated(Tr.ContractFactExprBounds(self.base, self.len))
end
function Tr.ContractWindowBounds:tree_check_contract_fact() local base=self.base:tree_check_contract_binding(); if not base then return rejected("window_bounds") end; return calculated(Tr.ContractFactWindowBounds(base,self.base_len,self.start,self.len)) end
function Tr.ContractDisjoint:tree_check_contract_fact() local a,b=self.a:tree_check_contract_binding(),self.b:tree_check_contract_binding(); if not a or not b then return rejected("disjoint") end; return calculated(Tr.ContractFactDisjoint(a,b)) end
function Tr.ContractSameLen:tree_check_contract_fact() local a,b=self.a:tree_check_contract_binding(),self.b:tree_check_contract_binding(); if not a or not b then return rejected("same_len") end; return calculated(Tr.ContractFactSameLen(a,b)) end
function Tr.ContractSoAComponent:tree_check_contract_fact() local b=self.base:tree_check_contract_binding(); if not b then return rejected("soa_component") end; return calculated(Tr.ContractFactSoAComponent(b,self.record_ty,self.field_name,self.component_index)) end
function Tr.ContractNoAlias:tree_check_contract_fact() local b=self.base:tree_check_contract_binding(); if not b then return rejected("noalias") end; return calculated(Tr.ContractFactNoAlias(b)) end
function Tr.ContractReadonly:tree_check_contract_fact() local b=self.base:tree_check_contract_binding(); return calculated(b and Tr.ContractFactReadonly(b) or Tr.ContractFactExprReadonly(self.base)) end
function Tr.ContractWriteonly:tree_check_contract_fact() local b=self.base:tree_check_contract_binding(); return calculated(b and Tr.ContractFactWriteonly(b) or Tr.ContractFactExprWriteonly(self.base)) end
function Tr.ContractInvalidate:tree_check_contract_fact() local b=self.base:tree_check_contract_binding(); if not b then return rejected("invalidate") end; return calculated(Tr.ContractFactInvalidate(b)) end
function Tr.ContractPreserve:tree_check_contract_fact() local b=self.base:tree_check_contract_binding(); if not b then return rejected("preserve") end; return calculated(Tr.ContractFactPreserve(b)) end

function Tr.FuncLocalContract:tree_check_contract_facts()
  local facts = {}
  for _, c in ipairs(self.contracts or {}) do
    for _, f in ipairs(c:tree_check_contract_fact()) do facts[#facts+1] = f end
  end
  return facts
end

function Tr.FuncExportContract:tree_check_contract_facts()
  local facts = {}
  for _, c in ipairs(self.contracts or {}) do
    for _, f in ipairs(c:tree_check_contract_fact()) do facts[#facts+1] = f end
  end
  return facts
end

function Tr.FuncLocal:tree_check_contract_facts() return {} end
function Tr.FuncExport:tree_check_contract_facts() return {} end
function Tr.FuncDecl:tree_check_contract_facts() return {} end
function Tr.Func:tree_check_contract_facts() return {} end

local function append_issues(dst, result) for _, issue in ipairs(result.issues) do dst[#dst+1] = issue end end
local function typed_expr(expr, input, issues) local r=expr:typecheck_tree_expr(Check.TypeExprInput(input.scope)); append_issues(issues,r); return r.expr end
function Tr.FuncContract:tree_check_contract(input) return Check.TypeContractResult(self, {}) end
function Tr.ContractBounds:tree_check_contract(input) local i={}; return Check.TypeContractResult(Tr.ContractBounds(typed_expr(self.base,input,i),typed_expr(self.len,input,i)),i) end
function Tr.ContractWindowBounds:tree_check_contract(input) local i={}; return Check.TypeContractResult(Tr.ContractWindowBounds(typed_expr(self.base,input,i),typed_expr(self.base_len,input,i),typed_expr(self.start,input,i),typed_expr(self.len,input,i)),i) end
function Tr.ContractDisjoint:tree_check_contract(input) local i={}; return Check.TypeContractResult(Tr.ContractDisjoint(typed_expr(self.a,input,i),typed_expr(self.b,input,i)),i) end
function Tr.ContractSameLen:tree_check_contract(input) local i={}; return Check.TypeContractResult(Tr.ContractSameLen(typed_expr(self.a,input,i),typed_expr(self.b,input,i)),i) end
function Tr.ContractSoAComponent:tree_check_contract(input) local i={}; return Check.TypeContractResult(Tr.ContractSoAComponent(typed_expr(self.base,input,i),self.record_ty,self.field_name,self.component_index),i) end
function Tr.ContractNoAlias:tree_check_contract(input) local i={}; return Check.TypeContractResult(Tr.ContractNoAlias(typed_expr(self.base,input,i)),i) end
function Tr.ContractReadonly:tree_check_contract(input) local i={}; return Check.TypeContractResult(Tr.ContractReadonly(typed_expr(self.base,input,i)),i) end
function Tr.ContractWriteonly:tree_check_contract(input) local i={}; return Check.TypeContractResult(Tr.ContractWriteonly(typed_expr(self.base,input,i)),i) end
function Tr.ContractInvalidate:tree_check_contract(input) local i={}; return Check.TypeContractResult(Tr.ContractInvalidate(typed_expr(self.base,input,i)),i) end
function Tr.ContractPreserve:tree_check_contract(input) local i={}; return Check.TypeContractResult(Tr.ContractPreserve(typed_expr(self.base,input,i)),i) end
