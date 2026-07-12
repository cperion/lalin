-- impl/tree_check/contract.lua
-- Contract fact computation leaf methods.

require("lalin.schema_v2")
local Tr  = require("lalin.schema_v2.tree")
local Sem = require("lalin.schema_v2.sem")

function Tr.FuncContract:tree_check_contract_fact() return {} end
function Tr.ContractBounds:tree_check_contract_fact() return {Sem.CalculateFact(Tr.ContractFactBounds())} end
function Tr.ContractWindowBounds:tree_check_contract_fact() return {Sem.CalculateFact(Tr.ContractFactWindowBounds())} end
function Tr.ContractDisjoint:tree_check_contract_fact() return {Sem.CalculateFact(Tr.ContractFactDisjoint())} end
function Tr.ContractSameLen:tree_check_contract_fact() return {Sem.CalculateFact(Tr.ContractFactSameLen())} end
function Tr.ContractSoAComponent:tree_check_contract_fact() return {Sem.CalculateFact(Tr.ContractFactSoAComponent())} end
function Tr.ContractNoAlias:tree_check_contract_fact() return {Sem.CalculateFact(Tr.ContractFactNoAlias())} end
function Tr.ContractReadonly:tree_check_contract_fact() return {Sem.CalculateFact(Tr.ContractFactReadonly())} end
function Tr.ContractWriteonly:tree_check_contract_fact() return {Sem.CalculateFact(Tr.ContractFactWriteonly())} end
function Tr.ContractInvalidate:tree_check_contract_fact() return {Sem.CalculateFact(Tr.ContractFactInvalidate())} end
function Tr.ContractPreserve:tree_check_contract_fact() return {Sem.CalculateFact(Tr.ContractFactPreserve())} end

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
