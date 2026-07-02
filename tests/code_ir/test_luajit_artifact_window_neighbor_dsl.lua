package.path = table.concat({
    './?.lua',
    './?/init.lua',
    './lua/?.lua',
    './lua/?/init.lua',
    package.path,
}, ';')

local ffi = require('ffi')
local asdl = require("lalin.asdl")
local lalin = require('lalin')
local LowerPlan = require('tests.code_ir.luajit_lower_plan_helper')

local source = [=[
return unit. NativeWindowNeighborDSL {
  fn. prev_clamp { dst [ptr [i32]], xs [ptr [i32]], n [index] } [void] {
    requires {
      bounds (dst)(n), writeonly(dst),
      bounds (xs)(n), readonly(xs),
      disjoint (dst)(xs),
    },

    lln.loop { i } [lln.window_nd { axes = { { 0, n } }, windows = { { 1, 1, boundary = "clamp" } } }] {
      set (dst[i])(xs[i - 1]),
    },
  },
}
]=]

local session = lalin.use { scope = 'env' }
local decl = assert(session:loadstring(source, 'test_luajit_artifact_window_neighbor_dsl.lua'))()
local plan = LowerPlan.plan(decl, {
    name = 'NativeWindowNeighborDSL',
})

assert(#plan.artifacts == 1, 'window neighbor source should select one stencil artifact during lowering')
local desc = plan.artifacts[1].instance.descriptor
assert(tostring(asdl.classof(desc.producer.shape)):match('StencilProduceWindowND'), 'source window neighbor should preserve WindowND producer')
assert(tostring(asdl.classof(desc.body.expr)):match('StencilPointWindowInput'), 'source neighbor access should lower to StencilPointWindowInput')

io.write('test_luajit_artifact_window_neighbor_dsl: ok\n')
