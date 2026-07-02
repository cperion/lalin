package.path = table.concat({
    './?.lua',
    './?/init.lua',
    './lua/?.lua',
    './lua/?/init.lua',
    package.path,
}, ';')

local lalin = require('lalin')
local LowerPlan = require('tests.code_ir.luajit_lower_plan_helper')

local source = [=[
return unit. NativeTiledScanDSL {
  fn. tiled_scan_rows { dst [ptr [i32]], xs [ptr [i32]], h [index], w [index], n [index] } [void] {
    requires {
      bounds (dst)(n), writeonly(dst),
      bounds (xs)(n), readonly(xs),
      disjoint (dst)(xs),
    },

    lln.loop { i, j } [lln.tiled_nd { axes = { { 0, h }, { 0, w } }, tiles = { 2, 2 } }] {
      lln.scan. acc [lln.i32] {
        init = 0,
        by = lln.add,
        axis = 2,
        step = xs[i * w + j],
        into = dst[i * w + j],
      },
    },
  },
}
]=]

local session = lalin.use { scope = 'env' }
local decl = assert(session:loadstring(source, 'test_luajit_artifact_tiled_scan_dsl.lua'))()
local plan = LowerPlan.plan(decl, {
    name = 'NativeTiledScanDSL',
})

assert(#plan.artifacts == 1, 'tiled_nd scan source should select one stencil artifact during lowering')
local desc = plan.artifacts[1].instance.descriptor
assert(tostring(require('lalin.asdl').classof(desc.producer.shape)):match('StencilProduceTiledND'), 'source tiled scan should preserve TiledND producer')
assert(tostring(require('lalin.asdl').classof(desc.sink)):match('StencilSinkScan'), 'source tiled scan should preserve Scan sink')

io.write('test_luajit_artifact_tiled_scan_dsl: ok\n')
