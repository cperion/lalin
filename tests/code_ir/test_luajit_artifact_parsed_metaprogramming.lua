package.path = table.concat({
    './?.lua',
    './?/init.lua',
    './lua/?.lua',
    './lua/?/init.lua',
    package.path,
}, ';')

local ffi = require('ffi')
local lalin = require('lalin')
local Lexer = require('llbl.syntax.lexer')
local Ast = require('lalin.syntax.ast')
local Expr = require('lalin.syntax.expr')
local Stmt = require('lalin.syntax.stmt')

local fragment_env = { factor = 3, bias = 5 }
local fragment_ctx = { add_ref = function() end }
local scaled_expr = Ast.node('ExprFragment', {
    expr = Expr.parse(Lexer.new('x * [factor] + [bias]', '@scaled_expr'), fragment_ctx),
})
local scale_stmt = Ast.node('StmtFragment', {
    body = Stmt.parse_block(Lexer.new('dst[i] = src[i] * [factor]\nend', '@scale_stmt'), fragment_ctx, { 'end' }),
})
Ast.resolve_host_evals(scaled_expr, fragment_env)
Ast.resolve_host_evals(scale_stmt, fragment_env)

local source = [=[
fn scale_one(x [i32]) [i32] do
  return [scaled_expr]
end

fn scale_array(dst [ptr [i32]], src [ptr [i32]], n [index]) [void] do
  requires bounds(dst)(n), writeonly(dst), bounds(src)(n), readonly(src), disjoint(dst)(src)
  loop i in 0 .. n do
    [scale_stmt]
  end
end
]=]

local parsed = assert(lalin.loadstring(source, '@test_luajit_artifact_parsed_metaprogramming.lln', {
    env = {
        scaled_expr = scaled_expr,
        scale_stmt = scale_stmt,
    },
}))
local loaded = lalin.compile_luajit('ParsedMetaprogramming', parsed, { bytecode = true })

assert(loaded.scale_one(4) == 17, 'parsed expr fragment splice with host literals')

local src = ffi.new('int32_t[4]', { 2, -3, 4, 5 })
local dst = ffi.new('int32_t[4]')
loaded.scale_array(dst, src, 4)
assert(dst[0] == 6 and dst[1] == -9 and dst[2] == 12 and dst[3] == 15, 'parsed stmt fragment splice with type host escapes')

io.write('test_luajit_artifact_parsed_metaprogramming: ok\n')
