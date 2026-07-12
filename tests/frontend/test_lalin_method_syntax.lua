package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local llbl = require("llbl")
local Lexer = require("llbl.syntax.lexer")
local Expr = require("lalin.syntax.expr")
local Decl = require("lalin.syntax.decl")
local Ast = require("lalin.syntax.ast")
local Document = require("lalin.syntax.document")
local lalin_syntax = require("lalin.syntax")
local asdl = require("lalin.asdl")
local T = require("lalin.schema_v2")
local ToTree = require("lalin.syntax.to_tree")(T)
local Tr = T.LalinTree

-- Test 1: basic method call
local lex = Lexer.new("p:norm()", "@test1")
local ast = Expr.parse(lex, { add_ref = function() end })
assert(ast.tag == "MethodCall", "should be a MethodCall node")
assert(ast.name == "norm", "method name should be norm")
assert(ast.receiver.tag == "Name" and ast.receiver.name == "p", "receiver should be Name(p)")
assert(#ast.args == 0, "method call stores explicit args separately from receiver")
print("Test 1: p:norm() preserves method-call intent OK")

-- Test 2: method call with arguments
local lex2 = Lexer.new("obj:method(a, b)", "@test2")
local ast2 = Expr.parse(lex2, { add_ref = function() end })
assert(ast2.tag == "MethodCall", "should be MethodCall")
assert(ast2.name == "method", "method name")
assert(ast2.receiver.name == "obj", "receiver is obj")
assert(#ast2.args == 2, "should have 2 explicit args (a, b)")
assert(ast2.args[1].name == "a", "first explicit arg is a")
assert(ast2.args[2].name == "b", "second explicit arg is b")
print("Test 2: obj:method(a,b) preserves receiver + args OK")

-- Test 3: chained method calls
local lex3 = Lexer.new("p:norm():other()", "@test3")
local ast3 = Expr.parse(lex3, { add_ref = function() end })
assert(ast3.tag == "MethodCall" and ast3.name == "other", "outer method call")
assert(ast3.receiver.tag == "MethodCall" and ast3.receiver.name == "norm", "inner method call")
print("Test 3: p:norm():other() preserves nested method-call intent OK")

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
assert(expr.tag == "MethodCall", "method parses as MethodCall")
assert(expr.name == "g", "method is g")
assert(expr.receiver.name == "self", "receiver is self")
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
assert(call_expr.tag == "MethodCall" and call_expr.name == "helper",
  "method parses as helper MethodCall")
assert(call_expr.receiver.name == "p", "receiver is p")
assert(call_expr.args[1].value == 3, "first explicit arg is 3")
print("Test 5: p:helper(3) preserves receiver and explicit arg OK")

-- Test 6: zero-arg method
local lex6 = Lexer.new("list:clear()", "@test6")
local ast6 = Expr.parse(lex6, { add_ref = function() end })
assert(ast6.tag == "MethodCall" and ast6.name == "clear",
  "zero-arg method should parse as MethodCall")
assert(ast6.receiver.name == "list" and #ast6.args == 0,
  "receiver plus zero explicit args")
print("Test 6: list:clear() preserves receiver and zero explicit args OK")

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

-- Test 8b: Lua-style colon method declaration injects self
local doc8b_src = [=[
struct Point
  x [i32]
  y [i32]
end

fn Point:sum() [i32]
  return self.x + self.y
end
]=]
local doc8b = Document.parse(doc8b_src, "@test8b.lln")
local fn8b = doc8b.body[2]
assert(fn8b.tag == "DeclFunc" and fn8b.name == "sum", "colon method fn parsed")
assert(fn8b.implicit_self == true, "colon method records implicit self")
assert(#fn8b.qualifier == 1 and fn8b.qualifier[1] == "Point", "colon method stores owner qualifier")
assert(#fn8b.params == 1 and fn8b.params[1].name == "self" and fn8b.params[1].implicit == true, "colon method injects self param")
local decls8b, mat8b = Document.materialize(doc8b)
assert(mat8b.env.Point.sum ~= nil and mat8b.env.sum ~= nil, "colon method binds like qualified dot method")
local module8b = require("lalin.syntax").to_module(doc8b, "colon_method_doc")
assert(#module8b.items[2].func.params == 1 and module8b.items[2].func.params[1].name == "self", "colon method self lowers as first function param")
print("Test 8b: fn Point:sum() injects self and binds as Point.sum OK")

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

-- Test 11b: Lua-style colon region declaration injects self
local doc11b_src = [=[
struct Store
  n [index]
end

region Store:borrow(ref [i32];
  borrowed,
  missing
)
  entry start()
    jump missing
  end
end
]=]
local doc11b = Document.parse(doc11b_src, "@test11b.lln")
local reg11b = doc11b.body[2]
assert(reg11b.tag == "DeclRegion" and reg11b.name == "borrow", "colon region parsed")
assert(reg11b.implicit_self == true, "colon region records implicit self")
assert(#reg11b.inputs == 2 and reg11b.inputs[1].name == "self" and reg11b.inputs[1].implicit == true, "colon region injects self input")
local module11b = lalin_syntax.to_module(doc11b, "colon_region_doc", T)
assert(asdl.classof(module11b.items[2]) == Tr.ItemRegion, "colon region lowers to ItemRegion")
assert(module11b.items[2].region.name == "Store.borrow", "colon region keeps qualified compiler name")
assert(#module11b.items[2].region.params == 2 and module11b.items[2].region.params[1].name == "self", "colon region self lowers as first input")
print("Test 11b: region Store:borrow(...) injects self OK")

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

-- Test 13b: continuation wire target application shorthand
local lex13b = Lexer.new("call Tokenizer.skip_ws(self; done = check(tok, want, code))", "@test13b")
local stmt13b = Stmt.parse(lex13b, { add_ref = function() end })
assert(stmt13b.tag == "StmtCall", "wire target application parses as region call")
assert(#stmt13b.cont_wiring == 1 and stmt13b.cont_wiring[1].target == "check", "done = check(...) target parsed")
assert(#stmt13b.cont_wiring[1].payload == 3, "wire target args parsed")
assert(stmt13b.cont_wiring[1].payload[1].key == "tok" and stmt13b.cont_wiring[1].payload[1].value.name == "tok", "tok shorthand parsed")
local lowered13b = ToTree.stmt(stmt13b)
assert(#lowered13b.wiring[1].target.args == 3, "wire target args lower to ASDL JumpArg list")
assert(lowered13b.wiring[1].target.args[2].name == "want", "want shorthand lowers as JumpArg(want = want)")
print("Test 13b: continuation target application shorthand parses and lowers OK")

-- Test 13c: continuation wiring same-name shorthand
local lex13c = Lexer.new("call LuaVM.dispatch(vm, frame, pc; returned, runtime_error, yielded(tok))", "@test13c")
local stmt13c = Stmt.parse(lex13c, { add_ref = function() end })
assert(#stmt13c.cont_wiring == 3, "same-name continuation shorthand parses")
assert(stmt13c.cont_wiring[1].name == "returned" and stmt13c.cont_wiring[1].target == "returned", "returned means returned=returned")
assert(stmt13c.cont_wiring[2].name == "runtime_error" and stmt13c.cont_wiring[2].target == "runtime_error", "runtime_error means runtime_error=runtime_error")
assert(stmt13c.cont_wiring[3].name == "yielded" and stmt13c.cont_wiring[3].target == "yielded" and #stmt13c.cont_wiring[3].payload == 1, "yielded(tok) means yielded=yielded(tok)")
local lowered13c = ToTree.stmt(stmt13c)
assert(lowered13c.wiring[1].name == "returned" and lowered13c.wiring[1].target.label.name == "returned", "same-name shorthand lowers to RegionWireBlock")
assert(#lowered13c.wiring[3].target.args == 1 and lowered13c.wiring[3].target.args[1].name == "tok", "same-name target application lowers args")
print("Test 13c: same-name continuation wiring shorthand parses and lowers OK")

-- Test 14: region invocation lowers to explicit ASDL leaves
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
local module15 = lalin_syntax.to_module(doc10, "region_doc", T)
assert(asdl.classof(module15.items[2]) == Tr.ItemRegion, "DeclRegion should lower to ItemRegion")
assert(module15.items[2].region.name == "Connection.open", "qualified region item keeps compiler path name")
assert(#module15.items[2].region.params == 1, "region input params lowered")
assert(#module15.items[2].region.conts == 2, "region continuations lowered")
assert(asdl.classof(module15.items[2].region.entry.body[1]) == Tr.StmtJumpCont, "jump to declared continuation retargeted")
print("Test 15: parsed DeclRegion lowers to ItemRegion OK")

-- Test 16: jump payload bare-name shorthand means name = name
local doc16_src = [=[
region Parse.step(pos [index], code [i32];
  failed(pos [index], code [i32])
)
  entry start()
    jump failed(pos, code)
  end
end
]=]
local doc16 = Document.parse(doc16_src, "@test16.lln")
local jump16 = doc16.body[1].blocks[1].body[1]
assert(jump16.tag == "StmtJump", "jump parsed")
assert(jump16.payload[1].key == "pos" and jump16.payload[1].value.name == "pos" and jump16.payload[1].shorthand == true, "pos shorthand parsed as pos=pos")
assert(jump16.payload[2].key == "code" and jump16.payload[2].value.name == "code" and jump16.payload[2].shorthand == true, "code shorthand parsed as code=code")
local module16 = lalin_syntax.to_module(doc16, "jump_shorthand_doc", T)
local args16 = module16.items[1].region.entry.body[1].args
assert(args16[1].name == "pos" and args16[2].name == "code", "jump shorthand lowers to named JumpArg")
print("Test 16: jump failed(pos, code) -> failed(pos=pos, code=code) OK")

-- Test 17: parsed scalar switch lowers to ASDL switch and retargets continuation jumps in regions
local lex17 = Lexer.new([=[switch op do
case 3 then
  jump add(a)
default then
  jump bad(op)
end]=], "@test17")
local stmt17 = Stmt.parse(lex17, { add_ref = function() end })
assert(stmt17.tag == "StmtSwitch" and #stmt17.arms == 1, "switch statement parsed")
local lowered17 = ToTree.stmt(stmt17)
assert(asdl.classof(lowered17) == Tr.StmtSwitch and asdl.classof(lowered17.arms[1].key) == Tr.SwitchKeyInt, "switch lowers to scalar StmtSwitch")
local doc17_src = [=[
region VM.decode(op [u8]; add(a [u8]), bad(op [u8]))
  entry start()
    switch op do
    case 3 then
      jump add(a = op)
    default then
      jump bad(op)
    end
  end
end
]=]
local doc17 = Document.parse(doc17_src, "@test17.lln")
local module17 = lalin_syntax.to_module(doc17, "switch_region_doc", T)
local switch17 = module17.items[1].region.entry.body[1]
assert(asdl.classof(switch17) == Tr.StmtSwitch, "region switch lowers to StmtSwitch")
assert(asdl.classof(switch17.arms[1].body[1]) == Tr.StmtJumpCont, "switch arm jump to continuation retargeted")
assert(asdl.classof(switch17.default_body[1]) == Tr.StmtJumpCont, "switch default jump to continuation retargeted")
print("Test 17: scalar switch parses, lowers, and retargets region continuations OK")

print("\nAll method syntax tests passed!")
