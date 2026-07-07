-- lalin.syntax_v2
-- Direct schema_v2 frontend for Lalin.  Parsers produce LalinParse.ParsedDecl
-- intermediate types; Document.to_module resolves type source strings and
-- lowers to Tree.Module ready for surface_resolve().

local llbl_syntax = require("llbl.syntax")
local Constructor = require("llbl.syntax.constructor")
local Document = require("lalin.syntax_v2.document")

-- Load schema_v2
require("lalin.schema_v2")
local asdl = require("lalin.asdl")
local P = package.loaded["lalin.schema_v2.parse"]

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
