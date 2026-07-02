package.path = table.concat({
    './?.lua',
    './?/init.lua',
    './lua/?.lua',
    './lua/?/init.lua',
    package.path,
}, ';')

local asdl = require("lalin.asdl")
local lalin = require('lalin')
local LowerPlan = require('tests.code_ir.luajit_lower_plan_helper')

local source = [=[
local copy2d = fn(dst [ptr [i32]], src [ptr [i32]], h [index], w [index], n [index]) [void]
  requires bounds(dst)(n), writeonly(dst), bounds(src)(n), readonly(src), disjoint(dst)(src)
  loop i, j in grid(0 .. h, 0 .. w) do
    dst[i * w + j] = src[i * w + j]
  end
end

local tiled_scan_rows = fn(dst [ptr [i32]], xs [ptr [i32]], h [index], w [index], n [index]) [void]
  requires bounds(dst)(n), writeonly(dst), bounds(xs)(n), readonly(xs), disjoint(dst)(xs)
  loop i, j in tiled grid(0 .. h, 0 .. w) by 2, 2 do
    scan acc [i32] = 0 by add over j step xs[i * w + j] into dst[i * w + j]
  end
end

local prev_clamp = fn(dst [ptr [i32]], xs [ptr [i32]], n [index]) [void]
  requires bounds(dst)(n), writeonly(dst), bounds(xs)(n), readonly(xs), disjoint(dst)(xs)
  loop i in window(0 .. n, before = 1, after = 1, boundary = clamp) do
    dst[i] = xs[i - 1]
  end
end

return {
  copy2d,
  tiled_scan_rows,
  prev_clamp,
}
]=]

local parsed = assert(lalin.loadstring(source, '@test_luajit_artifact_nd_parsed.lln'))()
local plan = LowerPlan.plan(parsed, {
    name = 'ParsedND',
})

assert(#plan.artifacts == 3, 'parsed ND source should select range, tiled scan, and window artifacts during lowering')
local seen = {}
for _, item in ipairs(plan.artifacts) do
    local desc = item.instance.descriptor
    seen[tostring(asdl.classof(desc.producer.shape))] = true
end
assert(seen['Class(LalinStencil.StencilProduceRangeND)'], 'parsed range_nd should preserve RangeND producer')
assert(seen['Class(LalinStencil.StencilProduceTiledND)'], 'parsed tiled_nd should preserve TiledND producer')
assert(seen['Class(LalinStencil.StencilProduceWindowND)'], 'parsed window_nd should preserve WindowND producer')

io.write('test_luajit_artifact_nd_parsed: ok\n')
