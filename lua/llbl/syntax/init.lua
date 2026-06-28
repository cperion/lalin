-- llbl.syntax
-- Generic LLBL parsed-channel subsystem.  This module is designed to be usable
-- standalone and also installable into an existing llbl table through
-- syntax.install(llbl).

local syntax = {}

syntax.lexer = require("llbl.syntax.lexer")
syntax.registry = require("llbl.syntax.registry")
syntax.constructor = require("llbl.syntax.constructor")
syntax.driver = require("llbl.syntax.driver")
syntax.pratt = require("llbl.syntax.pratt")

syntax.channel = {
  parsed = {
    decl        = "parsed:decl",
    block       = "parsed:block",
    stmt        = "parsed:stmt",
    expr        = "parsed:expr",
    place       = "parsed:place",
    assign      = "parsed:assign",
    cmp         = "parsed:cmp",
    binop       = "parsed:binop",
    unop        = "parsed:unop",
    call        = "parsed:call",
    index       = "parsed:index",
    field       = "parsed:field",
    if_stmt     = "parsed:if",
    for_range   = "parsed:for_range",
    return_stmt = "parsed:return",
    jump_stmt   = "parsed:jump",
    emit_stmt   = "parsed:emit",
    escape      = "parsed:escape",

    -- LLBL-owned hole and spread (underscore sentinels)
    hole        = "parsed:hole",
    spread      = "parsed:spread",
  }
}

function syntax.register(spec)
  return syntax.registry.register(spec)
end

function syntax.loadstring(source, chunkname, opts)
  return syntax.driver.loadstring(source, chunkname, opts)
end

function syntax.loadfile(path, opts)
  return syntax.driver.loadfile(path, opts)
end

function syntax.dofile(path, opts)
  return syntax.driver.dofile(path, opts)
end

function syntax.compile(source, chunkname, opts)
  return syntax.driver.compile(source, chunkname, opts)
end

function syntax.invoke(chunk_id, index, env_fn)
  return syntax.constructor.invoke(chunk_id, index, env_fn)
end

function syntax.install(llbl)
  llbl = llbl or {}
  llbl.shared = llbl.shared or {}
  llbl.shared.syntax = syntax
  llbl.syntax = syntax
  llbl.channel = llbl.channel or {}
  llbl.channel.parsed = syntax.channel.parsed
  return syntax
end

return syntax
