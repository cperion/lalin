package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local lalin = require("lalin")
local llbl = require("llbl")

local controls = {
  ["while"] = "E_LALIN_UNSUPPORTED_WHILE",
  ["break"] = "E_LALIN_UNSUPPORTED_BREAK",
  ["continue"] = "E_LALIN_UNSUPPORTED_CONTINUE",
}

local function function_source(form)
  local stmt = form == "while" and "while true do return 0 end" or form
  return "fn rejected() [i32] do\n  " .. stmt .. "\n  return 0\nend\n"
end

local function region_source(form)
  local stmt = form == "while" and "while true do jump done(code = 0) end" or form
  return "region rejected(; done(code [i32]))\n  entry start()\n    " .. stmt .. "\n    jump done(code = 0)\n  end\nend\n"
end

local function rejects(form, context, source)
  local decls, issue = lalin.loadstring(source, "@unsupported-" .. context .. "-" .. form .. ".lln")
  assert(decls == nil, form .. " must be rejected by the parser in " .. context .. " context")
  assert(llbl.is(issue, "Diagnostic"), form .. " must return a canonical LLBL diagnostic")
  assert(issue.code == controls[form], form .. " must have a stable diagnostic code")
  assert(issue.primary and issue.primary.line == (context == "function" and 2 or 3), form .. " must retain its source origin")
  assert(issue.message == "`" .. form .. "` is not supported in Lalin " .. context .. " context", form .. " must name its context deterministically")
  local rendered = tostring(issue)
  assert(not rendered:match("backend") and not rendered:match("type lowering"), form .. " must not reach lowering or backend explanation")
end

for form in pairs(controls) do
  rejects(form, "function", function_source(form))
  rejects(form, "region", region_source(form))
end

local _, for_issue = lalin.loadstring([[
fn rejected() [i32] do
  for i in 0..4 do
    return i
  end
end
]], "@unsupported-for.lln")
assert(tostring(for_issue):match("source loops use `loop`, not `for`"), "the dedicated for-to-loop diagnostic must remain")

local decl_source = assert(io.open("lua/lalin/syntax/decl.lua", "rb")):read("*a")
local stmt_source = assert(io.open("lua/lalin/syntax/stmt.lua", "rb")):read("*a")
assert(not decl_source:match("control_context") and not stmt_source:match("control_context"),
  "parser control ownership must not use mutable string/nil context state")
assert(not stmt_source:match("unsupported_control_codes") and not stmt_source:match("%[%\"while%\"%]"),
  "control spelling must not be routed through a parser table")
assert(stmt_source:match("Parse%.ParseUnsupportedWhile") and stmt_source:match("owner:reject_unsupported_control"),
  "unsupported control diagnostics must dispatch through typed control and owner leaves")

io.write("lalin unsupported control diagnostics ok\n")
