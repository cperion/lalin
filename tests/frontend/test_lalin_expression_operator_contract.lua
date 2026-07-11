package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local lalin = require("lalin")
local llbl = require("llbl")

local cases = {
  { spelling = "//", code = "E_LALIN_UNSUPPORTED_IDIV", valid = "7 // 3", invalid = "true // 3", note = "negative operands" },
  { spelling = "^", code = "E_LALIN_UNSUPPORTED_POW", valid = "2 ^ 8", invalid = "false ^ 2", note = "explicit library function" },
}

local function reject(case, expression, suffix)
  local source = "fn rejected_" .. suffix .. "() [i32] do\n  return " .. expression .. "\nend\n"
  local decls, issue = lalin.loadstring(source, "@operator-" .. suffix .. ".lln")
  assert(decls == nil, case.spelling .. " must be rejected at the parser boundary")
  assert(llbl.is(issue, "Diagnostic"), case.spelling .. " must produce a canonical LLBL diagnostic")
  assert(issue.code == case.code, case.spelling .. " must have a stable operator-specific code")
  assert(issue.primary and issue.primary.line == 2, case.spelling .. " must retain operator source origin")
  assert(issue.message == "binary operator `" .. case.spelling .. "` is not supported in Lalin source")
  assert(tostring(issue.notes[1]):match(case.note), case.spelling .. " must document its support decision")
  assert(not tostring(issue):match("parsed_to_tree"), case.spelling .. " must not reach the old parser/lowering mismatch")
end

for _, case in ipairs(cases) do
  reject(case, case.valid, case.spelling == "//" and "idiv" or "pow")
  reject(case, case.invalid, case.spelling == "//" and "idiv_invalid" or "pow_invalid")
end

io.write("lalin expression operator contract ok\n")
