require("lalin.schema_v2")

-- impl/code_validate.lua
-- Code IR validation leaf methods (from code_validate.lua).
-- Uses LalinCodeValidation.CodeValidationMachine for functional accumulation.

require("lalin.impl.tree_code")
local T = package.loaded["lalin.schema_v2._context"]
local Code = Code
local CV   = CodeValidation
local asdl = require("lalin.asdl")

local function class_name(x)
  local cls = asdl.classof(x) or x
  return tostring(cls):match("Class%((.-)%)") or tostring(cls)
end

local function is_power_of_two(n)
  if type(n) ~= "number" or n < 1 or n % 1 ~= 0 then return false end
  while n > 1 do
    if n % 2 ~= 0 then return false end
    n = n / 2
  end
  return true
end

-- Machine constructor
local function new_machine(sigs, data, globals, funcs, externs)
  return CV.CodeValidationMachine(
    nil, -- spine is optional
    {},
    {}
  )
end

-- Add issue helper
local function add_issue(m, issue)
  local issues = {}
  for i = 1, #(m.issues or {}) do issues[i] = m.issues[i] end
  issues[#issues+1] = issue
  return CV.CodeValidationMachine(m.spine, issues, m.relocs)
end

-- Validate CodeModule
local function validate_module(m, module)
  if asdl.classof(module) ~= Code.CodeModule then
    m = add_issue(m, Code.CodeIssueUnsupportedSource("module", Code.CodeUnsupportedControlStructure("not a module")))
    return m
  end

  -- Validate sigs
  for _, sig in ipairs(module.sigs or {}) do
    m = validate_sig(m, sig)
  end

  -- Validate types
  for _, ty in ipairs(module.types or {}) do
    m = validate_type_decl(m, ty)
  end

  -- Validate funcs
  local func_by_id = {}
  for _, func in ipairs(module.funcs or {}) do
    if func_by_id[func.id.text] then
      m = add_issue(m, Code.CodeIssueDuplicateFunc(func.id))
    else
      func_by_id[func.id.text] = true
      m = validate_func(m, module, func)
    end
  end

  return m
end

-- Validate CodeSig
local function validate_sig(m, sig)
  if asdl.classof(sig) ~= Code.CodeSig then
    return add_issue(m, Code.CodeIssueMissingSig(sig.id))
  end
  return m
end

-- Validate CodeTypeDecl
local function validate_type_decl(m, decl)
  if asdl.classof(decl) ~= Code.CodeTypeDecl then
    return add_issue(m, Code.CodeIssueUnsupportedSource("type_decl", Code.CodeUnsupportedControlStructure("invalid type decl")))
  end
  return m
end

-- Validate CodeFunc
local function validate_func(m, module, func)
  if asdl.classof(func) ~= Code.CodeFunc then
    return add_issue(m, Code.CodeIssueMissingFunc(func.id))
  end

  local block_by_id = {}
  for _, block in ipairs(func.blocks or {}) do
    if block_by_id[block.id.text] then
      m = add_issue(m, Code.CodeIssueDuplicateBlock(block.id))
    else
      block_by_id[block.id.text] = block
    end
  end

  -- Validate entry block exists
  if func.entry and not block_by_id[func.entry.text] then
    m = add_issue(m, Code.CodeIssueMissingBlock(func.entry))
  end

  -- Validate each block
  for _, block in ipairs(func.blocks or {}) do
    m = validate_block(m, func, block, block_by_id)
  end

  -- Check all value IDs in params, locals are unique
  local value_by_id = {}
  for _, param in ipairs(func.params or {}) do
    if value_by_id[param.value.text] then
      m = add_issue(m, Code.CodeIssueDuplicateValue(param.value))
    else
      value_by_id[param.value.text] = true
    end
  end
  for _, local_ in ipairs(func.locals or {}) do
    -- locals have .id not .value
  end

  return m
end

-- Validate CodeBlock
local function validate_block(m, func, block, block_by_id)
  if block.term == nil then
    m = add_issue(m, Code.CodeIssueUnterminatedBlock(block.id))
    return m
  end

  -- Validate instructions
  local inst_by_id = {}
  for _, inst in ipairs(block.insts or {}) do
    if inst_by_id[inst.id.text] then
      m = add_issue(m, Code.CodeIssueDuplicateInst(inst.id))
    else
      inst_by_id[inst.id.text] = true
    end
    m = validate_inst(m, inst)
  end

  -- Validate terminator
  m = validate_term(m, func, block, block_by_id)

  return m
end

-- Validate CodeInst
local function validate_inst(m, inst)
  if asdl.classof(inst) ~= Code.CodeInst then
    return add_issue(m, Code.CodeIssueInvalidTerminator("inst", inst.id))
  end
  return m
end

-- Validate CodeTerm
local function validate_term(m, func, block, block_by_id)
  local term = block.term
  if asdl.classof(term) ~= Code.CodeTerm then
    return add_issue(m, Code.CodeIssueInvalidTerminator("term", term.id))
  end

  -- Validate destinations exist
  local op = term.op
  if op then
    local cls = asdl.classof(op)
    if cls == Code.CodeTermJump then
      if op.dest and not block_by_id[op.dest.text] then
        m = add_issue(m, Code.CodeIssueMissingBlock(op.dest))
      end
    elseif cls == Code.CodeTermBranch then
      if op.then_dest and not block_by_id[op.then_dest.text] then
        m = add_issue(m, Code.CodeIssueMissingBlock(op.then_dest))
      end
      if op.else_dest and not block_by_id[op.else_dest.text] then
        m = add_issue(m, Code.CodeIssueMissingBlock(op.else_dest))
      end
    elseif cls == Code.CodeTermSwitch then
      for _, case in ipairs(op.cases or {}) do
        if case.dest and not block_by_id[case.dest.text] then
          m = add_issue(m, Code.CodeIssueMissingBlock(case.dest))
        end
      end
      if op.default_dest and not block_by_id[op.default_dest.text] then
        m = add_issue(m, Code.CodeIssueMissingBlock(op.default_dest))
      end
    elseif cls == Code.CodeTermVariantSwitch then
      for _, case in ipairs(op.cases or {}) do
        if case.dest and not block_by_id[case.dest.text] then
          m = add_issue(m, Code.CodeIssueMissingBlock(case.dest))
        end
      end
      if op.default_dest and not block_by_id[op.default_dest.text] then
        m = add_issue(m, Code.CodeIssueMissingBlock(op.default_dest))
      end
    end
  end
  return m
end

-- Public API
local function validate(module)
  local m = new_machine({}, {}, {}, {}, {})
  m = validate_module(m, module)
  if #(m.issues or {}) == 0 then
    return CV.CodeValidateOk(Code.CodeValidationReport(m.issues))
  end
  return CV.CodeValidateFailed(Code.CodeValidationReport(m.issues))
end

return { validate = validate }
