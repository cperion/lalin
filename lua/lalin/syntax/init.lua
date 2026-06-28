-- lalin.syntax
-- Terra-like parsed-channel frontend for Lalin, registered as a generic LLBL
-- syntax language.  The parser returns first-class Lalin parsed AST values;
-- repository integration should lower these nodes to LalinTree ASDL or call the
-- existing DSL heads in one place.

local llbl_syntax = require("llbl.syntax")
local Constructor = require("llbl.syntax.constructor")
local Ast = require("lalin.syntax.ast")
local Decl = require("lalin.syntax.decl")
local Expr = require("lalin.syntax.expr")
local Stmt = require("lalin.syntax.stmt")

local LalinSyntax = {}

local function wrap_ast(ast, ctx, opts)
  opts = opts or {}
  local refs = {}
  for _, r in ipairs(ctx.refs or {}) do refs[#refs + 1] = r end
  local outputs = {}
  if ast.name and (ast.tag == "DeclFunc" or ast.tag == "DeclStruct" or ast.tag == "DeclUnion" or ast.tag == "DeclRegion" or ast.tag == "DeclModule") then
    outputs[1] = { name = ast.name }
  end
  return Constructor.new {
    owner = "lalin",
    kind = ast.tag,
    role = opts.role or "decl",
    channel = opts.channel or "parsed:lalin",
    refs = refs,
    outputs = outputs,
    origin = ast.origin,
    ast = ast,
    build = function(env)
      -- Resolve explicit host escapes at construction/evaluation time.  This is
      -- the exact point where Lua lexical values become Lalin constants,
      -- fragments, types, or diagnostics in a full Lalin adapter.
      local copy = ast -- AST is intentionally shared; callsites normally build once.
      Ast.resolve_host_escapes(copy, env)
      return copy
    end,
  }
end

function LalinSyntax.parse_entry(lex, entry, ctx)
  local ast
  if entry == "fn" then
    ast = Decl.parse_fn(lex, ctx, ctx.entry_token)
  elseif entry == "struct" then
    ast = Decl.parse_struct(lex, ctx, ctx.entry_token)
  elseif entry == "union" then
    ast = Decl.parse_union(lex, ctx, ctx.entry_token)
  elseif entry == "region" then
    ast = Decl.parse_region(lex, ctx, ctx.entry_token)
  elseif entry == "module" then
    ast = Decl.parse_module(lex, ctx, ctx.entry_token)
  elseif entry == "expr" then
    ast = Decl.parse_expr_fragment(lex, ctx)
  elseif entry == "stmt" or entry == "quote" then
    ast = Decl.parse_stmt_fragment(lex, ctx)
  elseif entry == "lalin" then
    lex:error_at(ctx.entry_token, "bare `lalin` entrypoint requires a following entry token")
  else
    lex:error_at(ctx.entry_token, "unsupported Lalin syntax entrypoint `" .. tostring(entry) .. "`")
  end
  return wrap_ast(ast, ctx, { role = ast.tag })
end

function LalinSyntax.parse_expression(lex, ctx)
  local ast = Expr.parse(lex, ctx)
  return wrap_ast(ast, ctx, { role = "expr", channel = "parsed:expr" })
end

function LalinSyntax.parse_statement(lex, ctx)
  local body = Stmt.parse_block(lex, ctx, { "end" })
  lex:expect("end")
  local ast = Ast.node("StmtFragment", { body = body }, ctx:origin(lex, ctx.entry_token, lex.last, "parsed:stmt"))
  return wrap_ast(ast, ctx, { role = "stmt", channel = "parsed:stmt" })
end

function LalinSyntax.register()
  local spec = {
    name = "lalin",
    owner = "lalin",
    entrypoints = { "fn", "struct", "union", "region", "module", "quote", "expr", "stmt" },
    direct_entrypoints = nil, -- parse-time import activates entrypoints; namespaced form always works.
    keywords = {
      "fn", "region", "struct", "union", "module", "requires", "ensures",
      "do", "end", "if", "then", "elseif", "else", "for", "in", "range",
      "range_nd", "window_nd", "tiled_nd", "return", "jump", "emit", "entry", "block",
      "let", "var",
    },
    parse_entry = LalinSyntax.parse_entry,
    expression = LalinSyntax.parse_expression,
    statement = LalinSyntax.parse_statement,
  }
  LalinSyntax.language_spec = spec
  LalinSyntax.language_name = spec.name
  return llbl_syntax.register(spec)
end

-- Register on require.  This mirrors Terra-style import behavior for a simple
-- implementation bundle.  A full LLBL loader can switch this to scope-local
-- parse-time imports.
LalinSyntax.register()

return LalinSyntax
