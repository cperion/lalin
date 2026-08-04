-- impl/tree_check/contract.lua
-- Contract fact computation leaf methods.

require("lalin.schema")
local Tr  = require("lalin.schema.tree")
local Sem = require("lalin.schema.sem")
local Check = require("lalin.schema.check")
local B = require("lalin.schema.bind")

function Tr.FuncContract:typecheck_tree_contract(_input) return self end
function Tr.ContractBounds:typecheck_tree_contract(input)
  return Tr.ContractBounds(self.base:typecheck_tree_expr(input).expr,
    self.len:typecheck_tree_expr(input).expr)
end
function Tr.ContractWindowBounds:typecheck_tree_contract(input)
  return Tr.ContractWindowBounds(self.base:typecheck_tree_expr(input).expr,
    self.base_len:typecheck_tree_expr(input).expr,
    self.start:typecheck_tree_expr(input).expr, self.len:typecheck_tree_expr(input).expr)
end
function Tr.ContractDisjoint:typecheck_tree_contract(input)
  return Tr.ContractDisjoint(self.a:typecheck_tree_expr(input).expr,
    self.b:typecheck_tree_expr(input).expr)
end
function Tr.ContractNoAliasPair:typecheck_tree_contract(input)
  return Tr.ContractNoAliasPair(self.a:typecheck_tree_expr(input).expr,
    self.b:typecheck_tree_expr(input).expr)
end
function Tr.ContractSameLen:typecheck_tree_contract(input)
  return Tr.ContractSameLen(self.a:typecheck_tree_expr(input).expr,
    self.b:typecheck_tree_expr(input).expr)
end
function Tr.ContractSoAComponent:typecheck_tree_contract(input)
  return Tr.ContractSoAComponent(self.base:typecheck_tree_expr(input).expr,
    self.record_ty, self.field_name, self.component_index)
end
function Tr.ContractNoAlias:typecheck_tree_contract(input) return Tr.ContractNoAlias(self.base:typecheck_tree_expr(input).expr) end
function Tr.ContractReadonly:typecheck_tree_contract(input) return Tr.ContractReadonly(self.base:typecheck_tree_expr(input).expr) end
function Tr.ContractWriteonly:typecheck_tree_contract(input) return Tr.ContractWriteonly(self.base:typecheck_tree_expr(input).expr) end
function Tr.ContractInvalidate:typecheck_tree_contract(input) return Tr.ContractInvalidate(self.base:typecheck_tree_expr(input).expr) end
function Tr.ContractPreserve:typecheck_tree_contract(input) return Tr.ContractPreserve(self.base:typecheck_tree_expr(input).expr) end

function B.ValueRef:tree_check_contract_binding() error("contract requires a bound value reference", 2) end
function B.ValueRefBinding:tree_check_contract_binding() return self.binding end
function Tr.Expr:tree_check_contract_binding() error("contract requires a value reference", 2) end
function Tr.ExprRef:tree_check_contract_binding() return self.ref:tree_check_contract_binding() end

function Tr.FuncContract:tree_check_contract_fact() return {} end

function Tr.Expr:tree_check_contract_bounds_fact(len) return { Tr.ContractFactExprBounds(self, len) } end
function Tr.ExprRef:tree_check_contract_bounds_fact(len) return len:tree_check_contract_bounds_for_ref(self) end
function Tr.Expr:tree_check_contract_bounds_for_ref(base) return { Tr.ContractFactExprBounds(base, self) } end
function Tr.ExprRef:tree_check_contract_bounds_for_ref(base)
  return { Tr.ContractFactBounds(base:tree_check_contract_binding(), self:tree_check_contract_binding()) }
end
function Tr.ContractBounds:tree_check_contract_fact()
  return self.base:tree_check_contract_bounds_fact(self.len)
end
function Tr.ContractWindowBounds:tree_check_contract_fact()
  return {Tr.ContractFactWindowBounds(
    self.base:tree_check_contract_binding(), self.base_len, self.start, self.len)}
end
function Tr.ContractDisjoint:tree_check_contract_fact()
  return {Tr.ContractFactDisjoint(
    self.a:tree_check_contract_binding(), self.b:tree_check_contract_binding())}
end
function Tr.ContractNoAliasPair:tree_check_contract_fact()
  return {Tr.ContractFactExprNoAliasPair(self.a, self.b)}
end
function Tr.ContractSameLen:tree_check_contract_fact()
  return {Tr.ContractFactSameLen(
    self.a:tree_check_contract_binding(), self.b:tree_check_contract_binding())}
end
function Tr.ContractSoAComponent:tree_check_contract_fact()
  return {Tr.ContractFactSoAComponent(
    self.base:tree_check_contract_binding(), self.record_ty, self.field_name, self.component_index)}
end
function Tr.Expr:tree_check_contract_noalias_fact() return { Tr.ContractFactExprNoAlias(self) } end
function Tr.ExprRef:tree_check_contract_noalias_fact() return { Tr.ContractFactNoAlias(self:tree_check_contract_binding()) } end
function Tr.ContractNoAlias:tree_check_contract_fact()
  return self.base:tree_check_contract_noalias_fact()
end
function Tr.Expr:tree_check_contract_readonly_fact() return Tr.ContractFactExprReadonly(self) end
function Tr.ExprRef:tree_check_contract_readonly_fact() return Tr.ContractFactReadonly(self:tree_check_contract_binding()) end
function Tr.ContractReadonly:tree_check_contract_fact()
  return {self.base:tree_check_contract_readonly_fact()}
end
function Tr.Expr:tree_check_contract_writeonly_fact() return Tr.ContractFactExprWriteonly(self) end
function Tr.ExprRef:tree_check_contract_writeonly_fact() return Tr.ContractFactWriteonly(self:tree_check_contract_binding()) end
function Tr.ContractWriteonly:tree_check_contract_fact()
  return {self.base:tree_check_contract_writeonly_fact()}
end
function Tr.ContractInvalidate:tree_check_contract_fact()
  return {Tr.ContractFactInvalidate(self.base:tree_check_contract_binding())}
end
function Tr.ContractPreserve:tree_check_contract_fact()
  return {Tr.ContractFactPreserve(self.base:tree_check_contract_binding())}
end

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
