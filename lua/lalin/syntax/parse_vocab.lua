-- Closed parser-boundary vocabulary and leaf-owned diagnostic behavior.

local llbl = require("llbl")
local asdl = require("lalin.asdl")
local Ast = require("lalin.syntax.ast")

local T = asdl.context()
require("lalin.schema_projection")(T)
local Parse = T.LalinParse

local function reject(code, spelling, owner_name, lex, tok)
  error(llbl.diagnostic {
    code = code,
    message = "`" .. spelling .. "` is not supported in Lalin " .. owner_name .. " context",
    primary = Ast.origin(lex, tok, tok, "parsed:unsupported_control"),
    notes = { "Lalin source has no `while`, `break`, or `continue`; use `loop` and terminating block control" },
  }, 0)
end

function Parse.ParseFunctionControlOwner:reject_unsupported_control(control, lex, tok)
  return control:reject_in_function(lex, tok)
end

function Parse.ParseRegionControlOwner:reject_unsupported_control(control, lex, tok)
  return control:reject_in_region(lex, tok)
end

function Parse.ParseUnsupportedWhile:reject_in_function(lex, tok) return reject("E_LALIN_UNSUPPORTED_WHILE", "while", "function", lex, tok) end
function Parse.ParseUnsupportedWhile:reject_in_region(lex, tok) return reject("E_LALIN_UNSUPPORTED_WHILE", "while", "region", lex, tok) end
function Parse.ParseUnsupportedBreak:reject_in_function(lex, tok) return reject("E_LALIN_UNSUPPORTED_BREAK", "break", "function", lex, tok) end
function Parse.ParseUnsupportedBreak:reject_in_region(lex, tok) return reject("E_LALIN_UNSUPPORTED_BREAK", "break", "region", lex, tok) end
function Parse.ParseUnsupportedContinue:reject_in_function(lex, tok) return reject("E_LALIN_UNSUPPORTED_CONTINUE", "continue", "function", lex, tok) end
function Parse.ParseUnsupportedContinue:reject_in_region(lex, tok) return reject("E_LALIN_UNSUPPORTED_CONTINUE", "continue", "region", lex, tok) end

function Parse.ParsedRegularCall:parsed_to_tree_call(to_tree, callee, args)
  return to_tree.parsed_regular_call(callee, args)
end

function Parse.ParsedVariantConstructorCall:parsed_to_tree_call(to_tree, callee, args)
  return to_tree.parsed_variant_constructor_call(self.type_name, self.variant_name, args)
end

return Parse
