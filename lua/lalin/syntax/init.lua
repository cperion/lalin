-- lalin.syntax
-- Direct schema frontend for Lalin. Brackets become LLBL HostEval events;
-- role-adapted values enter Parsed ASDL and lower to Tree.Module.

local llbl_syntax = require("llbl.syntax")
local Constructor = require("llbl.syntax.constructor")
local Document = require("lalin.syntax.document")

-- Load schema
require("lalin.schema")
local asdl = require("lalin.asdl")
local P = package.loaded["lalin.schema.parse"]

local LalinSyntaxV2 = {}

function LalinSyntaxV2.parse_document(source, chunkname, opts)
  return Document.parse(source, chunkname, opts)
end

function LalinSyntaxV2.materialize_document(doc, opts)
  return Document.materialize(doc, opts)
end

function LalinSyntaxV2.load_document(source, chunkname, opts)
  return Document.load(source, chunkname, opts)
end

function LalinSyntaxV2.to_decls(value, opts)
  if asdl.classof(value) == P.ParsedDocument then
    local decls, env = Document.materialize(value, opts)
    return decls
  end
  return value
end

function LalinSyntaxV2.to_module(parsed_decls, name, T)
  return Document.to_module(parsed_decls, name)
end

function LalinSyntaxV2.register()
  local spec = {
    name = "lalin_v2", owner = "lalin",
    entrypoints = { "fn", "struct", "union", "handle", "region", "quote", "expr", "stmt" },
    keywords = {
      "fn", "region", "struct", "union", "handle", "requires", "ensures",
      "do", "end", "if", "then", "elseif", "else", "loop", "in",
      "grid", "tiled", "window", "return", "jump", "emit", "call", "entry", "block",
      "let", "var", "fold", "scan", "by", "over", "step", "into",
    },
    parse_entry = function() end,
    expression = function() end,
    statement = function() end,
  }
  LalinSyntaxV2.language_spec = spec
  LalinSyntaxV2.language_name = spec.name
  return llbl_syntax.register(spec)
end

-- Register on require.
LalinSyntaxV2.register()

return LalinSyntaxV2
