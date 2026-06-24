package.path = table.concat({
    './?.lua',
    './?/init.lua',
    './lua/?.lua',
    './lua/?/init.lua',
    package.path,
}, ';')

local ffi = require('ffi')
local moon = require('moonlift')

local source = [=[
return unit. CopyPatchRegression {
  fn. sum_i32 { xs [ptr [i32]], n [i32] } [i32] {
    requires { bounds(xs, n), readonly(xs) },

    entry. start {} { jump. loop { i = 0, acc = 0 }, },

    block. loop { i [i32], acc [i32] } {
      when (i :lt (n)) {
        jump. body { i = i, acc = acc },
      },

      jump. done { acc = acc },
    },

    block. body { i [i32], acc [i32] } {
      jump. loop { i = i + 1, acc = acc + xs[i] },
    },

    block. done { acc [i32] } {
      ret (acc),
    },
  },

  fn. copy_i32 { dst [ptr [i32]], src [ptr [i32]], n [i32] } [void] {
    requires {
      bounds(dst, n), writeonly(dst),
      bounds(src, n), readonly(src),
      disjoint(dst, src),
    },

    entry. start {} { jump. loop { i = 0 }, },

    block. loop { i [i32] } {
      when (i :lt (n)) {
        jump. body { i = i },
      },

      jump. done {},
    },

    block. body { i [i32] } {
      store (dst[i], src[i]),
      jump. loop { i = i + 1 },
    },

    block. done {} {
      ret (),
    },
  },

  fn. fill_i32 { dst [ptr [i32]], n [i32], value [i32] } [void] {
    requires { bounds(dst, n), writeonly(dst) },

    entry. start {} { jump. loop { i = 0 }, },

    block. loop { i [i32] } {
      when (i :lt (n)) {
        jump. body { i = i },
      },

      jump. done {},
    },

    block. body { i [i32] } {
      store (dst[i], value),
      jump. loop { i = i + 1 },
    },

    block. done {} {
      ret (),
    },
  },

  fn. map_neg_i32 { dst [ptr [i32]], src [ptr [i32]], n [i32] } [void] {
    requires {
      bounds(dst, n), writeonly(dst),
      bounds(src, n), readonly(src),
      disjoint(dst, src),
    },

    entry. start {} { jump. loop { i = 0 }, },

    block. loop { i [i32] } {
      when (i :lt (n)) {
        jump. body { i = i },
      },

      jump. done {},
    },

    block. body { i [i32] } {
      store (dst[i], -src[i]),
      jump. loop { i = i + 1 },
    },

    block. done {} {
      ret (),
    },
  },

  fn. zip_add_i32 { dst [ptr [i32]], lhs [ptr [i32]], rhs [ptr [i32]], n [i32] } [void] {
    requires {
      bounds(dst, n), writeonly(dst),
      bounds(lhs, n), readonly(lhs),
      bounds(rhs, n), readonly(rhs),
      disjoint(dst, lhs), disjoint(dst, rhs), disjoint(lhs, rhs),
    },

    entry. start {} { jump. loop { i = 0 }, },

    block. loop { i [i32] } {
      when (i :lt (n)) {
        jump. body { i = i },
      },

      jump. done {},
    },

    block. body { i [i32] } {
      store (dst[i], lhs[i] + rhs[i]),
      jump. loop { i = i + 1 },
    },

    block. done {} {
      ret (),
    },
  },

  fn. cast_i32_f64 { dst [ptr [f64]], src [ptr [i32]], n [i32] } [void] {
    requires {
      bounds(dst, n), writeonly(dst),
      bounds(src, n), readonly(src),
      disjoint(dst, src),
    },

    entry. start {} { jump. loop { i = 0 }, },

    block. loop { i [i32] } {
      when (i :lt (n)) {
        jump. body { i = i },
      },

      jump. done {},
    },

    block. body { i [i32] } {
      store (dst[i], as [f64] (src[i])),
      jump. loop { i = i + 1 },
    },

    block. done {} {
      ret (),
    },
  },

  fn. compare_gt_zero_i32 { dst [ptr [bool]], src [ptr [i32]], n [i32] } [void] {
    requires {
      bounds(dst, n), writeonly(dst),
      bounds(src, n), readonly(src),
      disjoint(dst, src),
    },

    entry. start {} { jump. loop { i = 0 }, },

    block. loop { i [i32] } {
      when (i :lt (n)) {
        jump. body { i = i },
      },

      jump. done {},
    },

    block. body { i [i32] } {
      store (dst[i], src[i] :gt (0)),
      jump. loop { i = i + 1 },
    },

    block. done {} {
      ret (),
    },
  },

  fn. zip_compare_lt_i32 { dst [ptr [bool]], lhs [ptr [i32]], rhs [ptr [i32]], n [i32] } [void] {
    requires {
      bounds(dst, n), writeonly(dst),
      bounds(lhs, n), readonly(lhs),
      bounds(rhs, n), readonly(rhs),
      disjoint(dst, lhs), disjoint(dst, rhs), disjoint(lhs, rhs),
    },

    entry. start {} { jump. loop { i = 0 }, },

    block. loop { i [i32] } {
      when (i :lt (n)) {
        jump. body { i = i },
      },

      jump. done {},
    },

    block. body { i [i32] } {
      store (dst[i], lhs[i] :lt (rhs[i])),
      jump. loop { i = i + 1 },
    },

    block. done {} {
      ret (),
    },
  },

  fn. gather_i32 { dst [ptr [i32]], src [ptr [i32]], idx [ptr [i32]], n [i32] } [void] {
    requires {
      bounds(dst, n), writeonly(dst),
      bounds(src, n), readonly(src),
      bounds(idx, n), readonly(idx),
      disjoint(dst, src), disjoint(dst, idx), disjoint(src, idx),
    },

    entry. start {} { jump. loop { i = 0 }, },

    block. loop { i [i32] } {
      when (i :lt (n)) {
        jump. body { i = i },
      },

      jump. done {},
    },

    block. body { i [i32] } {
      store (dst[i], src[idx[i]]),
      jump. loop { i = i + 1 },
    },

    block. done {} {
      ret (),
    },
  },

  fn. scatter_i32 { dst [ptr [i32]], src [ptr [i32]], idx [ptr [i32]], n [i32] } [void] {
    requires {
      bounds(dst, n), writeonly(dst),
      bounds(src, n), readonly(src),
      bounds(idx, n), readonly(idx),
      disjoint(dst, src), disjoint(dst, idx), disjoint(src, idx),
    },

    entry. start {} { jump. loop { i = 0 }, },

    block. loop { i [i32] } {
      when (i :lt (n)) {
        jump. body { i = i },
      },

      jump. done {},
    },

    block. body { i [i32] } {
      store (dst[idx[i]], src[i]),
      jump. loop { i = i + 1 },
    },

    block. done {} {
      ret (),
    },
  },

  fn. in_place_neg_i32 { dst [ptr [i32]], n [i32] } [void] {
    requires { bounds(dst, n) },

    entry. start {} { jump. loop { i = 0 }, },

    block. loop { i [i32] } {
      when (i :lt (n)) {
        jump. body { i = i },
      },

      jump. done {},
    },

    block. body { i [i32] } {
      store (dst[i], -dst[i]),
      jump. loop { i = i + 1 },
    },

    block. done {} {
      ret (),
    },
  },

  fn. count_gt_zero_i32 { xs [ptr [i32]], n [i32] } [i32] {
    requires { bounds(xs, n), readonly(xs) },

    entry. start {} { jump. loop { i = 0, acc = 0 }, },

    block. loop { i [i32], acc [i32] } {
      when (i :lt (n)) {
        jump. body { i = i, acc = acc },
      },

      jump. done { acc = acc },
    },

    block. body { i [i32], acc [i32] } {
      jump. loop { i = i + 1, acc = acc + as [i32] (xs[i] :gt (0)) },
    },

    block. done { acc [i32] } {
      ret (acc),
    },
  },

  fn. sum_neg_i32 { xs [ptr [i32]], n [i32] } [i32] {
    requires { bounds(xs, n), readonly(xs) },

    entry. start {} { jump. loop { i = 0, acc = 0 }, },

    block. loop { i [i32], acc [i32] } {
      when (i :lt (n)) {
        jump. body { i = i, acc = acc },
      },

      jump. done { acc = acc },
    },

    block. body { i [i32], acc [i32] } {
      jump. loop { i = i + 1, acc = acc + -xs[i] },
    },

    block. done { acc [i32] } {
      ret (acc),
    },
  },

  fn. sum_zip_i32 { lhs [ptr [i32]], rhs [ptr [i32]], n [i32] } [i32] {
    requires {
      bounds(lhs, n), readonly(lhs),
      bounds(rhs, n), readonly(rhs),
      disjoint(lhs, rhs),
    },

    entry. start {} { jump. loop { i = 0, acc = 0 }, },

    block. loop { i [i32], acc [i32] } {
      when (i :lt (n)) {
        jump. body { i = i, acc = acc },
      },

      jump. done { acc = acc },
    },

    block. body { i [i32], acc [i32] } {
      jump. loop { i = i + 1, acc = acc + (lhs[i] + rhs[i]) },
    },

    block. done { acc [i32] } {
      ret (acc),
    },
  },

  fn. scan_sum_i32 { dst [ptr [i32]], xs [ptr [i32]], n [i32] } [i32] {
    requires {
      bounds(dst, n), writeonly(dst),
      bounds(xs, n), readonly(xs),
      disjoint(dst, xs),
    },

    entry. start {} { jump. loop { i = 0, acc = 0 }, },

    block. loop { i [i32], acc [i32] } {
      when (i :lt (n)) {
        jump. body { i = i, acc = acc },
      },

      jump. done { acc = acc },
    },

    block. body { i [i32], acc [i32] } {
      let. nxt [i32] (acc + xs[i]),
      store (dst[i], nxt),
      jump. loop { i = i + 1, acc = nxt },
    },

    block. done { acc [i32] } {
      ret (acc),
    },
  },

}
]=]

local session = moon.use { scope = 'env' }
local decl = assert(session:loadstring(source, 'test_luajit_artifact_from_dsl.lua'))()
local artifact = moon.emit_luajit_artifact(decl, {
    path = 'target/test_artifacts/test_luajit_artifact_from_dsl.lua',
    name = 'CopyPatchRegression',
    stem = 'test_luajit_artifact_from_dsl',
})

assert(artifact.kind == 'LuaJITSourceArtifact')
assert(#artifact.artifacts == 15, 'expected selected stencil artifact for each DSL loop')
assert(artifact.source:match('__ml_check_stencil_target'), 'expected generated target guard')

local expected_vocab = {
    ['MoonStencil.StencilReduce'] = 'reduce',
    ['MoonStencil.StencilCopy'] = 'copy',
    ['MoonStencil.StencilFill'] = 'fill',
    ['MoonStencil.StencilMap'] = 'map',
    ['MoonStencil.StencilZipMap'] = 'zip_map',
    ['MoonStencil.StencilCast'] = 'cast',
    ['MoonStencil.StencilCompare'] = 'compare',
    ['MoonStencil.StencilZipCompare'] = 'zip_compare',
    ['MoonStencil.StencilGather'] = 'gather',
    ['MoonStencil.StencilScatter'] = 'scatter',
    ['MoonStencil.StencilInPlaceMap'] = 'in_place_map',
    ['MoonStencil.StencilCount'] = 'count',
    ['MoonStencil.StencilMapReduce'] = 'map_reduce',
    ['MoonStencil.StencilZipReduce'] = 'zip_reduce',
    ['MoonStencil.StencilScan'] = 'scan',
}
local seen = {}
for _, selected in ipairs(artifact.artifacts) do
    local descriptor = selected.instance.descriptor
    local label = expected_vocab[tostring(descriptor.vocab)]
    assert(label ~= nil, 'unexpected selected stencil vocab ' .. tostring(descriptor.vocab))
    assert(seen[label] == nil, 'duplicate selected stencil artifact for ' .. label)
    assert(tostring(selected.instance.schedule):match('StencilScheduleAutoVector'), label .. ' should carry an auto-vector stencil schedule')
    seen[label] = true
end
for _, label in pairs(expected_vocab) do assert(seen[label], 'missing selected stencil artifact for ' .. label) end

local loaded = assert(loadfile(artifact.path))()
local arr = ffi.new('int32_t[6]', { 1, 2, 3, 4, 5, 6 })
assert(loaded.sum_i32(arr, 6) == 21)

local src = ffi.new('int32_t[6]', { 5, -3, 8, 0, 9, 2 })
local rhs = ffi.new('int32_t[6]', { 1, 10, -8, 7, 4, 11 })
local idx = ffi.new('int32_t[6]', { 2, 0, 4, 1, 5, 3 })
local out = ffi.new('int32_t[6]')
local out_bool = ffi.new('uint8_t[6]')
local out_f64 = ffi.new('double[6]')

loaded.copy_i32(out, src, 6)
for i = 0, 5 do assert(out[i] == src[i], 'copy mismatch at ' .. tostring(i)) end

loaded.fill_i32(out, 6, 77)
for i = 0, 5 do assert(out[i] == 77, 'fill mismatch at ' .. tostring(i)) end

loaded.map_neg_i32(out, src, 6)
for i = 0, 5 do assert(out[i] == -src[i], 'map mismatch at ' .. tostring(i)) end

loaded.zip_add_i32(out, src, rhs, 6)
for i = 0, 5 do assert(out[i] == src[i] + rhs[i], 'zip mismatch at ' .. tostring(i)) end

loaded.cast_i32_f64(out_f64, src, 6)
for i = 0, 5 do assert(out_f64[i] == src[i], 'cast mismatch at ' .. tostring(i)) end

loaded.compare_gt_zero_i32(out_bool, src, 6)
for i = 0, 5 do assert(out_bool[i] == (src[i] > 0 and 1 or 0), 'compare mismatch at ' .. tostring(i)) end

loaded.zip_compare_lt_i32(out_bool, src, rhs, 6)
for i = 0, 5 do assert(out_bool[i] == (src[i] < rhs[i] and 1 or 0), 'zip compare mismatch at ' .. tostring(i)) end

loaded.gather_i32(out, src, idx, 6)
for i = 0, 5 do assert(out[i] == src[idx[i]], 'gather mismatch at ' .. tostring(i)) end

for i = 0, 5 do out[i] = 0 end
loaded.scatter_i32(out, src, idx, 6)
for i = 0, 5 do
    local found = false
    for j = 0, 5 do if idx[j] == i then found = out[i] == src[j] end end
    assert(found, 'scatter mismatch at ' .. tostring(i))
end

local inplace = ffi.new('int32_t[6]', { 5, -3, 8, 0, 9, 2 })
loaded.in_place_neg_i32(inplace, 6)
for i = 0, 5 do assert(inplace[i] == -src[i], 'in-place map mismatch at ' .. tostring(i)) end

assert(loaded.count_gt_zero_i32(src, 6) == 4, 'count mismatch')
assert(loaded.sum_neg_i32(src, 6) == -21, 'map reduce mismatch')
assert(loaded.sum_zip_i32(src, rhs, 6) == 46, 'zip reduce mismatch')

loaded.scan_sum_i32(out, arr, 6)
local running = 0
for i = 0, 5 do
    running = running + arr[i]
    assert(out[i] == running, 'scan mismatch at ' .. tostring(i))
end
assert(running == 21, 'scan final mismatch')

io.write('test_luajit_artifact_from_dsl: ok\n')
