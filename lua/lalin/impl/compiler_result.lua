require("lalin.schema_v2")

-- impl/compiler_result.lua
-- Compiler ABI result validation (from compiler_abi.lua).
-- Validates CodeResult products against the Code ABI boundary.

require("lalin.impl.tree_code")
require("lalin.impl.code_validate")
local T = package.loaded["lalin.schema_v2._context"]
local Compiler = Compiler
local Code     = Code
local Sem      = Sem
local asdl = require("lalin.asdl")
local CodeValidate = require("lalin.impl.code_validate")

local function class_name(v)
  local cls = asdl.classof(v)
  return cls and (tostring(cls):match("Class%((.-)%)") or tostring(cls)) or type(v)
end

local function add(issues, issue)
  issues[#issues+1] = issue
end

local function check_field(issues, value, field_name, expected_type, expected_name)
  if asdl.classof(value) ~= expected_type then
    add(issues, Compiler.CodeResultIssueInvalidField(field_name, expected_name, class_name(value)))
    return false
  end
  return true
end

-- Issue text formatting via leaf methods
function Compiler.CodeResultIssue:issue_text() return tostring(self) end
function Compiler.CodeResultIssueUnexpectedValue:issue_text()
  return "expected " .. tostring(self.expected) .. ", got " .. tostring(self.actual)
end
function Compiler.CodeResultIssueInvalidField:issue_text()
  return "field " .. tostring(self.name) .. " expected " .. tostring(self.expected) .. ", got " .. tostring(self.actual)
end
function Compiler.CodeResultIssueInvalidCode:issue_text()
  return "invalid code: " .. tostring(self.issue)
end

-- Validate CodeResult
local function validate_code_result(code_result, opts)
  opts = opts or {}
  local issues = {}

  if asdl.classof(code_result) ~= Compiler.CodeResult then
    add(issues, Compiler.CodeResultIssueUnexpectedValue("LalinCompiler.CodeResult", class_name(code_result)))
    return Compiler.CodeResultReport(issues)
  end

  local module_ok = check_field(issues, code_result.module, "module", Code.CodeModule, "LalinCode.CodeModule")
  check_field(issues, code_result.layout_env, "layout_env", Sem.LayoutEnv, "LalinSem.LayoutEnv")

  if type(code_result.contracts) == "table" and not asdl.classof(code_result.contracts) then
    for i = 1, #code_result.contracts do
      if asdl.classof(code_result.contracts[i]) ~= Code.CodeFuncContractFact then
        add(issues, Compiler.CodeResultIssueInvalidField("contracts["..tostring(i).."]", "LalinCode.CodeFuncContractFact", class_name(code_result.contracts[i])))
      end
    end
  elseif code_result.contracts ~= nil then
    add(issues, Compiler.CodeResultIssueInvalidField("contracts", "LalinCode.CodeFuncContractFact[]", class_name(code_result.contracts)))
  end

  if module_ok then
    local code_report = CodeValidate.validate(code_result.module)
    -- Extract issues from validation result
    if code_report and code_report.issues then
      for i = 1, #(code_report.issues or {}) do
        add(issues, Compiler.CodeResultIssueInvalidCode(code_report.issues[i]))
      end
    end
  end

  return Compiler.CodeResultReport(issues)
end

-- Assert valid
local function assert_valid_code_result(code_result, opts)
  local report = validate_code_result(code_result, opts)
  if #report.issues == 0 then return report end
  local messages = {}
  for i = 1, #report.issues do
    messages[#messages+1] = report.issues[i]:issue_text()
  end
  error("lalin compiler ABI CodeResult validation failed:\n" .. table.concat(messages, "\n"), 2)
end

return {
  validate = validate_code_result,
  validate_code_result = validate_code_result,
  assert_valid_code_result = assert_valid_code_result,
}
