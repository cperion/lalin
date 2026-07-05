package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local llbl = require("llbl")
local Lexer = require("llbl.syntax.lexer")
local Expr = require("lalin.syntax.expr")
local Decl = require("lalin.syntax.decl")
local Ast = require("lalin.syntax.ast")
local Document = require("lalin.syntax.document")

-- Test 1: basic method call
local lex = Lexer.new("p:norm()", "@test1")
local ast = Expr.parse(lex, { add_ref = function() end })
assert(ast.tag == "Call", "should be a Call node")
assert(ast.callee.tag == "Name" and ast.callee.name == "norm", "callee should be Name(norm)")
assert(#ast.args == 1 and ast.args[1].tag == "Name" and ast.args[1].name == "p",
  "first arg should be Name(p)")
print("Test 1: p:norm() -> norm(p) OK")

-- Test 2: method call with arguments
local lex2 = Lexer.new("obj:method(a, b)", "@test2")
local ast2 = Expr.parse(lex2, { add_ref = function() end })
assert(ast2.tag == "Call", "should be Call")
assert(ast2.callee.name == "method", "callee name")
assert(#ast2.args == 3, "should have 3 args (obj, a, b)")
assert(ast2.args[1].name == "obj", "first arg is self")
assert(ast2.args[2].name == "a", "second arg is a")
assert(ast2.args[3].name == "b", "third arg is b")
print("Test 2: obj:method(a,b) -> method(obj,a,b) OK")

-- Test 3: chained method calls
local lex3 = Lexer.new("p:norm():other()", "@test3")
local ast3 = Expr.parse(lex3, { add_ref = function() end })
assert(ast3.tag == "Call" and ast3.callee.name == "other", "outer call")
assert(ast3.args[1].tag == "Call" and ast3.args[1].callee.name == "norm", "inner call")
print("Test 3: p:norm():other() -> other(norm(p)) OK")

-- Test 4: method in document context
local doc_src = [=[
struct S
  x [i32]
end

fn f(self [ptr [S]]) [i32]
  return self:g()
end
]=]
local doc = Document.parse(doc_src, "@test.lln")
assert(doc.tag == "DeclDocument", "document parsed")
assert(doc.body[2].tag == "DeclFunc", "fn parsed")
assert(#doc.body[2].body == 1, "fn body has 1 stmt")
local ret_stmt = doc.body[2].body[1]
assert(ret_stmt.tag == "StmtReturn", "return stmt")
local expr = ret_stmt.values[1]
assert(expr.tag == "Call", "method desugars to Call")
assert(expr.callee.name == "g", "callee is g")
assert(expr.args[1].name == "self", "self is first arg")
print("Test 4: method in document OK")

-- Test 5: method call with self as ptr arg to another function
local doc2_src = [=[
struct S
  x [i32]
end

fn helper(self [ptr [S]], factor [i32]) [i32]
  return self.x * factor
end

fn caller(p [ptr [S]]) [i32]
  return p:helper(3)
end
]=]
local doc2 = Document.parse(doc2_src, "@test5.lln")
assert(doc2.body[3].tag == "DeclFunc", "caller fn parsed")
local ret_stmt2 = doc2.body[3].body[1]
assert(ret_stmt2.tag == "StmtReturn")
local call_expr = ret_stmt2.values[1]
assert(call_expr.tag == "Call" and call_expr.callee.name == "helper",
  "method desugars to helper call")
assert(call_expr.args[1].name == "p", "self is p")
assert(call_expr.args[2].value == 3, "second arg is 3")
print("Test 5: p:helper(3) -> helper(p, 3) OK")

-- Test 6: zero-arg method
local lex6 = Lexer.new("list:clear()", "@test6")
local ast6 = Expr.parse(lex6, { add_ref = function() end })
assert(ast6.tag == "Call" and ast6.callee.name == "clear",
  "zero-arg method should desugar to clear(list)")
assert(#ast6.args == 1 and ast6.args[1].name == "list",
  "one arg (self) for zero-arg method")
print("Test 6: list:clear() -> clear(list) OK")

-- Test 7: qualified function fn Point.norm(...)
local doc7_src = [=[
struct Point
  x [i32]
  y [i32]
end

fn Point.norm(self [ptr [Point]]) [i32]
  return self.x + self.y
end
]=]
local doc7 = Document.parse(doc7_src, "@test7.lln")
assert(doc7.body[1].tag == "DeclStruct" and doc7.body[1].name == "Point", "struct parsed")
assert(doc7.body[2].tag == "DeclFunc" and doc7.body[2].name == "norm", "qualified fn parsed")
assert(#doc7.body[2].qualifier == 1 and doc7.body[2].qualifier[1] == "Point",
  "fn Point.norm should store qualifier = {Point}")
print("Test 7: fn Point.norm(...) parses with qualifier OK")

-- Test 8: env binding for qualified function
local decls8, doc8 = Document.materialize(doc7)
assert(doc8.env.Point ~= nil, "Point struct should be in env")
assert(doc8.env.Point.norm ~= nil, "Point.norm should be bound to struct value")
assert(doc8.env.Point.norm.tag == "DeclFunc" and doc8.env.Point.norm.name == "norm",
  "Point.norm should be the norm function")
assert(doc8.env.norm ~= nil, "norm should also be in env for method dispatch")
print("Test 8: env binding fn Point.norm -> Point.norm = <function> OK")

-- Test 9: deep qualification fn Deep.Point.norm(...) in document
local doc9_src = [=[
struct Point
  x [i32]
end

struct Wrapper
  p [ptr [Point]]
end

fn Wrapper.Point.norm(self [ptr [Point]]) [i32]
  return 0
end
]=]
local doc9 = Document.parse(doc9_src, "@test9.lln")
local fn9 = doc9.body[3]
assert(fn9.tag == "DeclFunc" and fn9.name == "norm", "deep qualified fn parsed")
assert(#fn9.qualifier == 2 and fn9.qualifier[1] == "Wrapper" and fn9.qualifier[2] == "Point",
  "deep qualification should store qualifier = {Wrapper, Point}")
print("Test 9: fn Wrapper.Point.norm(...) parses with deep qualifier OK")

-- Test 10: qualified region and handle declarations
local doc10_src = [=[
struct Connection
  fd [i32]
end

region Connection.open(addr [slice [u8]];
  connected(conn [ptr [Connection]]),
  refused
)
  entry dial()
    jump connected(conn = addr)
  end
end

handle Connection.Ref [u32]
  invalid = 0
  domain [Connection]
  target [Connection]
end
]=]
local doc10 = Document.parse(doc10_src, "@test10.lln")
assert(doc10.body[2].tag == "DeclRegion" and doc10.body[2].name == "open", "qualified region parsed")
assert(#doc10.body[2].qualifier == 1 and doc10.body[2].qualifier[1] == "Connection",
  "region Connection.open stores qualifier")
assert(doc10.body[3].tag == "DeclHandle" and doc10.body[3].name == "Ref", "qualified handle parsed")
assert(#doc10.body[3].qualifier == 1 and doc10.body[3].qualifier[1] == "Connection",
  "handle Connection.Ref stores qualifier")
print("Test 10: region Connection.open(...) and handle Connection.Ref parse OK")

-- Test 11: env binding for qualified region and handle
local decls11, doc11 = Document.materialize(doc10)
assert(doc11.env.Connection ~= nil, "Connection struct in env")
assert(doc11.env.Connection.open ~= nil and doc11.env.Connection.open.tag == "DeclRegion",
  "Connection.open bound to struct")
assert(doc11.env.Connection.Ref ~= nil and doc11.env.Connection.Ref.tag == "DeclHandle",
  "Connection.Ref bound to struct")
assert(doc11.env.open ~= nil, "open in env scope")
assert(doc11.env.Ref ~= nil, "Ref in env scope")
print("Test 11: qualified region/handle env bindings OK")

-- Test 12: region call syntax mirrors declaration signature
local Stmt = require("lalin.syntax.stmt")
local lex12 = Lexer.new('call Connection.open("localhost:8080"; connected = handle, refused = retry, timeout = retry)', "@test12")
local stmt12 = Stmt.parse(lex12, { add_ref = function() end })
assert(stmt12.tag == "StmtCall", "call keyword should parse as StmtCall")
assert(stmt12.callee.tag == "Field" and stmt12.callee.name == "open", "qualified region callee parsed")
assert(#stmt12.data_args == 1 and stmt12.data_args[1].value == "localhost:8080", "data args before ; parsed")
assert(#stmt12.cont_wiring == 3, "continuation wiring after ; parsed")
assert(stmt12.callee_path[1] == "Connection" and stmt12.callee_path[2] == "open", "callee path stored")
assert(stmt12.cont_wiring[1].name == "connected" and stmt12.cont_wiring[1].target == "handle", "connected = handle")
assert(stmt12.cont_wiring[2].name == "refused" and stmt12.cont_wiring[2].target == "retry", "refused = retry")
assert(stmt12.cont_wiring[3].name == "timeout" and stmt12.cont_wiring[3].target == "retry", "timeout = retry")
print("Test 12: call Region(args; cont = block) parses OK")

-- Test 13: emit uses the same region invocation syntax
local lex13 = Lexer.new("emit borrow(store, buffer; borrowed = on_borrowed, stale = retry, missing = retry)", "@test13")
local stmt13 = Stmt.parse(lex13, { add_ref = function() end })
assert(stmt13.tag == "StmtEmit", "emit keyword should parse as StmtEmit")
assert(stmt13.callee.tag == "Name" and stmt13.callee.name == "borrow", "region callee parsed")
assert(#stmt13.data_args == 2, "emit data args parsed")
assert(#stmt13.cont_wiring == 3, "emit continuation wiring parsed")
assert(stmt13.cont_wiring[1].name == "borrowed" and stmt13.cont_wiring[1].target == "on_borrowed", "borrowed = on_borrowed")
print("Test 13: emit Region(args; cont = block) parses OK")

-- Test 14: region invocation lowers to explicit ASDL leaves
local asdl = require("lalin.asdl")
local T = asdl.context()
require("lalin.schema_projection")(T)
local ToTree = require("lalin.syntax.to_tree")(T)
local Tr = T.LalinTree
local lowered12 = ToTree.stmt(stmt12)
assert(asdl.classof(lowered12) == Tr.StmtRegionCall, "call region should lower to StmtRegionCall")
assert(lowered12.target.path.parts[1].text == "Connection" and lowered12.target.path.parts[2].text == "open", "region target path lowered")
assert(#lowered12.args == 1, "region data args lowered")
assert(#lowered12.wiring == 3 and lowered12.wiring[1].name == "connected" and lowered12.wiring[1].target.label.name == "handle", "region wiring lowered")
local lowered13 = ToTree.stmt(stmt13)
assert(asdl.classof(lowered13) == Tr.StmtRegionEmit, "emit region should lower to StmtRegionEmit")
assert(#lowered13.args == 2 and #lowered13.wiring == 3, "emit args/wiring lowered")
print("Test 14: region invocation lowers to ASDL leaves OK")

-- Test 15: parsed region declarations lower to ItemRegion
local lalin_syntax = require("lalin.syntax")
local module15 = lalin_syntax.to_module(doc10, "region_doc", T)
assert(asdl.classof(module15.items[2]) == Tr.ItemRegion, "DeclRegion should lower to ItemRegion")
assert(module15.items[2].region.name == "Connection.open", "qualified region item keeps compiler path name")
assert(#module15.items[2].region.params == 1, "region input params lowered")
assert(#module15.items[2].region.conts == 2, "region continuations lowered")
assert(asdl.classof(module15.items[2].region.entry.body[1]) == Tr.StmtJumpCont, "jump to declared continuation retargeted")
print("Test 15: parsed DeclRegion lowers to ItemRegion OK")

print("\nAll method syntax tests passed!")
