package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local llbl = require("llbl")
local asdl = require("lalin.asdl")
local lalin = require("lalin")
local Lexer = require("llbl.syntax.lexer")
local Ast = require("lalin.syntax.ast")
local Expr = require("lalin.syntax.expr")
local Stmt = require("lalin.syntax.stmt")
local Type = require("lalin.syntax.type")
local Decl = require("lalin.syntax.decl")

local T = asdl.context()
require("lalin.schema_projection")(T)
local ToTree = require("lalin.syntax.to_tree")(T)

-- Parsed [Pair] adapts a declaration value to a type position through the role adapter.
local parsed = assert(lalin.loadstring([[
local Pair = struct Pair
  x [i32]
end
local accept = fn(p [Pair]) [void]
  return
end
return { Pair, accept }
]], "@pair-type.lln"))()
local module = lalin.syntax.to_module(parsed, "PairType", T)
assert(asdl.classof(module) == T.LalinTree.Module, "[Pair] declaration-to-type should lower to a module")
assert(#module.items == 2, "expected Pair and accept items")

-- Leading [body] in a statement block is a statement-list HostEval splice.
local body = Ast.node("StmtFragment", { body = { Ast.node("StmtReturn", { values = {} }) } })
local stmt_items = Stmt.parse_block(Lexer.new("[body]\nend", "@stmt-splice"), { add_ref = function() end }, { "end" })
assert(llbl.is(stmt_items[1], "HostEval") and stmt_items[1].expected_role == "stmts")
Ast.resolve_host_evals(Ast.node("Root", { items = stmt_items }), { body = body })
local lowered_stmts = ToTree.stmts(stmt_items)
assert(#lowered_stmts == 1 and asdl.classof(lowered_stmts[1]) == T.LalinTree.StmtReturnVoid,
  "[body] should splice a StmtFragment")

-- Leading [fields] in a product/field block is a product HostEval splice.
local generated_fields = { Ast.node("Field", { name = "y", type = llbl.host_eval.lua(T.LalinType.TScalar(T.LalinCore.ScalarI32)) }) }
local fields = Type.parse_field_block(Lexer.new("[generated_fields]\nend", "@field-splice"), { add_ref = function() end }, "end")
assert(llbl.is(fields[1], "HostEval") and fields[1].expected_role == "product")
Ast.resolve_host_evals(Ast.node("Root", { fields = fields }), { generated_fields = generated_fields })
local adapted_fields = ToTree.product_fields(fields)
assert(#adapted_fields == 1 and adapted_fields[1].name == "y", "[fields] should splice product fields")

-- Declaration streams can arrive as HostEval/list values at the compile boundary.
local decl_stream = llbl.host_eval.lua({ Ast.node("DeclStruct", { name = "Generated", fields = {} }) })
local generated_module = lalin.syntax.to_module(decl_stream, "GeneratedDecls", T)
assert(asdl.classof(generated_module) == T.LalinTree.Module and #generated_module.items == 1,
  "HostEval declaration stream should lower deterministically")
local stream_ast = Decl.parse_decl_stream(Lexer.new("[decls]", "@decl-stream"), { expected_role = "decls", add_ref = function() end })
assert(llbl.is(stream_ast, "HostEval") and stream_ast.expected_role == "decls")

-- Parsed expression indexing remains parsed indexing; nested HostEval brackets stay opaque Lua source.
local indexed = Expr.parse(Lexer.new("a[x]", "@index"), {})
assert(indexed.tag == "Index" and indexed.base.tag == "Name" and indexed.index.tag == "Name",
  "a[x] must remain parsed expression indexing")
local host_indexed = Expr.parse(Lexer.new("[make_expr()][i]", "@host-index"), {})
assert(host_indexed.tag == "Index" and llbl.is(host_indexed.base, "HostEval"),
  "[make_expr()][i] should be HostEval atom followed by parsed index")
local nested = Expr.parse(Lexer.new("[ptr [Pair]]", "@nested"), {})
assert(llbl.is(nested, "HostEval") and nested.source == "ptr [Pair]",
  "nested brackets inside HostEval source must remain opaque Lua")

-- Unsupported role values produce diagnostics/errors instead of silent acceptance.
local ok, err = pcall(function() return ToTree.product_fields(llbl.host_eval.lua(42)) end)
assert(not ok and tostring(err):match("E_LALIN_ROLE_ADAPT"), "unsupported product HostEval should fail")

io.write("lalin bracket role eval ok\n")
