package.path = table.concat({
    './?.lua',
    './?/init.lua',
    './lua/?.lua',
    './lua/?/init.lua',
    package.path,
}, ';')

local asdl = require("lalin.asdl")
local lalin = require('lalin')

local source = [=[
return unit. ResidualRegression {
  fn. sum_i32 { xs [ptr [i32]], n [i32] } [i32] {
    requires { bounds (xs)(n), readonly(xs) },

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
      bounds (dst)(n), writeonly(dst),
      bounds (src)(n), readonly(src),
      disjoint (dst)(src),
    },

    entry. start {} { jump. loop { i = 0 }, },

    block. loop { i [i32] } {
      when (i :lt (n)) {
        jump. body { i = i },
      },

      jump. done {},
    },

    block. body { i [i32] } {
      set (dst[i])(src[i]),
      jump. loop { i = i + 1 },
    },

    block. done {} {
      ret (),
    },
  },

  fn. copy_i32_memmove { dst [ptr [i32]], src [ptr [i32]], n [i32] } [void] {
    requires {
      bounds (dst)(n), writeonly(dst),
      bounds (src)(n), readonly(src),
    },

    entry. start {} { jump. loop { i = 0 }, },

    block. loop { i [i32] } {
      when (i :lt (n)) {
        jump. body { i = i },
      },

      jump. done {},
    },

    block. body { i [i32] } {
      set (dst[i])(src[i]),
      jump. loop { i = i + 1 },
    },

    block. done {} {
      ret (),
    },
  },

  fn. fill_i32 { dst [ptr [i32]], n [i32], value [i32] } [void] {
    requires { bounds (dst)(n), writeonly(dst) },

    entry. start {} { jump. loop { i = 0 }, },

    block. loop { i [i32] } {
      when (i :lt (n)) {
        jump. body { i = i },
      },

      jump. done {},
    },

    block. body { i [i32] } {
      set (dst[i])(value),
      jump. loop { i = i + 1 },
    },

    block. done {} {
      ret (),
    },
  },

  fn. map_neg_i32 { dst [ptr [i32]], src [ptr [i32]], n [i32] } [void] {
    requires {
      bounds (dst)(n), writeonly(dst),
      bounds (src)(n), readonly(src),
      disjoint (dst)(src),
    },

    entry. start {} { jump. loop { i = 0 }, },

    block. loop { i [i32] } {
      when (i :lt (n)) {
        jump. body { i = i },
      },

      jump. done {},
    },

    block. body { i [i32] } {
      set (dst[i])(-src[i]),
      jump. loop { i = i + 1 },
    },

    block. done {} {
      ret (),
    },
  },

  fn. zip_add_i32 { dst [ptr [i32]], lhs [ptr [i32]], rhs [ptr [i32]], n [i32] } [void] {
    requires {
      bounds (dst)(n), writeonly(dst),
      bounds (lhs)(n), readonly(lhs),
      bounds (rhs)(n), readonly(rhs),
      disjoint (dst)(lhs), disjoint (dst)(rhs), disjoint (lhs)(rhs),
    },

    entry. start {} { jump. loop { i = 0 }, },

    block. loop { i [i32] } {
      when (i :lt (n)) {
        jump. body { i = i },
      },

      jump. done {},
    },

    block. body { i [i32] } {
      set (dst[i])(lhs[i] + rhs[i]),
      jump. loop { i = i + 1 },
    },

    block. done {} {
      ret (),
    },
  },

  fn. zip_fused_i32 { dst [ptr [i32]], lhs [ptr [i32]], rhs [ptr [i32]], n [i32] } [void] {
    requires {
      bounds (dst)(n), writeonly(dst),
      bounds (lhs)(n), readonly(lhs),
      bounds (rhs)(n), readonly(rhs),
      disjoint (dst)(lhs), disjoint (dst)(rhs), disjoint (lhs)(rhs),
    },

    entry. start {} { jump. loop { i = 0 }, },

    block. loop { i [i32] } {
      when (i :lt (n)) {
        jump. body { i = i },
      },

      jump. done {},
    },

    block. body { i [i32] } {
      set (dst[i])((lhs[i] + rhs[i]) * (lhs[i] - rhs[i])),
      jump. loop { i = i + 1 },
    },

    block. done {} {
      ret (),
    },
  },

  fn. select_pos_i32 { dst [ptr [i32]], lhs [ptr [i32]], rhs [ptr [i32]], n [i32] } [void] {
    requires {
      bounds (dst)(n), writeonly(dst),
      bounds (lhs)(n), readonly(lhs),
      bounds (rhs)(n), readonly(rhs),
      disjoint (dst)(lhs), disjoint (dst)(rhs), disjoint (lhs)(rhs),
    },

    entry. start {} { jump. loop { i = 0 }, },

    block. loop { i [i32] } {
      when (i :lt (n)) {
        jump. body { i = i },
      },

      jump. done {},
    },

    block. body { i [i32] } {
      set (dst[i])(select (lhs[i] :gt (0))(lhs[i])(rhs[i])),
      jump. loop { i = i + 1 },
    },

    block. done {} {
      ret (),
    },
  },

  fn. bitmix_i32 { dst [ptr [i32]], lhs [ptr [i32]], rhs [ptr [i32]], n [i32] } [void] {
    requires {
      bounds (dst)(n), writeonly(dst),
      bounds (lhs)(n), readonly(lhs),
      bounds (rhs)(n), readonly(rhs),
      disjoint (dst)(lhs), disjoint (dst)(rhs), disjoint (lhs)(rhs),
    },

    entry. start {} { jump. loop { i = 0 }, },

    block. loop { i [i32] } {
      when (i :lt (n)) {
        jump. body { i = i },
      },

      jump. done {},
    },

    block. body { i [i32] } {
      set (dst[i])(bxor (shl (lhs[i] % rhs[i])(1))(bor (band (lhs[i])(15))(rhs[i]))),
      jump. loop { i = i + 1 },
    },

    block. done {} {
      ret (),
    },
  },

  fn. minmax_i32 { dst [ptr [i32]], lhs [ptr [i32]], rhs [ptr [i32]], n [i32] } [void] {
    requires {
      bounds (dst)(n), writeonly(dst),
      bounds (lhs)(n), readonly(lhs),
      bounds (rhs)(n), readonly(rhs),
      disjoint (dst)(lhs), disjoint (dst)(rhs), disjoint (lhs)(rhs),
    },

    entry. start {} { jump. loop { i = 0 }, },

    block. loop { i [i32] } {
      when (i :lt (n)) {
        jump. body { i = i },
      },

      jump. done {},
    },

    block. body { i [i32] } {
      set (dst[i])(max (min (lhs[i])(rhs[i]))(0)),
      jump. loop { i = i + 1 },
    },

    block. done {} {
      ret (),
    },
  },

  fn. cast_i32_f64 { dst [ptr [f64]], src [ptr [i32]], n [i32] } [void] {
    requires {
      bounds (dst)(n), writeonly(dst),
      bounds (src)(n), readonly(src),
      disjoint (dst)(src),
    },

    entry. start {} { jump. loop { i = 0 }, },

    block. loop { i [i32] } {
      when (i :lt (n)) {
        jump. body { i = i },
      },

      jump. done {},
    },

    block. body { i [i32] } {
      set (dst[i])(as [f64] (src[i])),
      jump. loop { i = i + 1 },
    },

    block. done {} {
      ret (),
    },
  },

  fn. compare_gt_zero_i32 { dst [ptr [bool]], src [ptr [i32]], n [i32] } [void] {
    requires {
      bounds (dst)(n), writeonly(dst),
      bounds (src)(n), readonly(src),
      disjoint (dst)(src),
    },

    entry. start {} { jump. loop { i = 0 }, },

    block. loop { i [i32] } {
      when (i :lt (n)) {
        jump. body { i = i },
      },

      jump. done {},
    },

    block. body { i [i32] } {
      set (dst[i])(src[i] :gt (0)),
      jump. loop { i = i + 1 },
    },

    block. done {} {
      ret (),
    },
  },

  fn. zip_compare_lt_i32 { dst [ptr [bool]], lhs [ptr [i32]], rhs [ptr [i32]], n [i32] } [void] {
    requires {
      bounds (dst)(n), writeonly(dst),
      bounds (lhs)(n), readonly(lhs),
      bounds (rhs)(n), readonly(rhs),
      disjoint (dst)(lhs), disjoint (dst)(rhs), disjoint (lhs)(rhs),
    },

    entry. start {} { jump. loop { i = 0 }, },

    block. loop { i [i32] } {
      when (i :lt (n)) {
        jump. body { i = i },
      },

      jump. done {},
    },

    block. body { i [i32] } {
      set (dst[i])(lhs[i] :lt (rhs[i])),
      jump. loop { i = i + 1 },
    },

    block. done {} {
      ret (),
    },
  },

  fn. gather_i32 { dst [ptr [i32]], src [ptr [i32]], idx [ptr [i32]], n [i32] } [void] {
    requires {
      bounds (dst)(n), writeonly(dst),
      bounds (src)(n), readonly(src),
      bounds (idx)(n), readonly(idx),
      disjoint (dst)(src), disjoint (dst)(idx), disjoint (src)(idx),
    },

    entry. start {} { jump. loop { i = 0 }, },

    block. loop { i [i32] } {
      when (i :lt (n)) {
        jump. body { i = i },
      },

      jump. done {},
    },

    block. body { i [i32] } {
      set (dst[i])(src[idx[i]]),
      jump. loop { i = i + 1 },
    },

    block. done {} {
      ret (),
    },
  },

  fn. scatter_i32 { dst [ptr [i32]], src [ptr [i32]], idx [ptr [i32]], n [i32] } [void] {
    requires {
      bounds (dst)(n), writeonly(dst),
      bounds (src)(n), readonly(src),
      bounds (idx)(n), readonly(idx),
      disjoint (dst)(src), disjoint (dst)(idx), disjoint (src)(idx),
    },

    entry. start {} { jump. loop { i = 0 }, },

    block. loop { i [i32] } {
      when (i :lt (n)) {
        jump. body { i = i },
      },

      jump. done {},
    },

    block. body { i [i32] } {
      set (dst[idx[i]])(src[i]),
      jump. loop { i = i + 1 },
    },

    block. done {} {
      ret (),
    },
  },

  fn. scatter_reduce_add_i32 { dst [ptr [i32]], src [ptr [i32]], idx [ptr [i32]], n [i32] } [void] {
    requires {
      bounds (dst)(n),
      bounds (src)(n), readonly(src),
      bounds (idx)(n), readonly(idx),
      disjoint (dst)(src), disjoint (dst)(idx), disjoint (src)(idx),
    },

    entry. start {} { jump. loop { i = 0 }, },

    block. loop { i [i32] } {
      when (i :lt (n)) {
        jump. body { i = i },
      },

      jump. done {},
    },

    block. body { i [i32] } {
      set (dst[idx[i]])(dst[idx[i]] + src[i]),
      jump. loop { i = i + 1 },
    },

    block. done {} {
      ret (),
    },
  },

  fn. scatter_reduce_add_zip_i32 { dst [ptr [i32]], src [ptr [i32]], rhs [ptr [i32]], idx [ptr [i32]], n [i32] } [void] {
    requires {
      bounds (dst)(n),
      bounds (src)(n), readonly(src),
      bounds (rhs)(n), readonly(rhs),
      bounds (idx)(n), readonly(idx),
      disjoint (dst)(src), disjoint (dst)(rhs), disjoint (dst)(idx),
      disjoint (src)(rhs), disjoint (src)(idx), disjoint (rhs)(idx),
    },

    entry. start {} { jump. loop { i = 0 }, },

    block. loop { i [i32] } {
      when (i :lt (n)) {
        jump. body { i = i },
      },

      jump. done {},
    },

    block. body { i [i32] } {
      set (dst[idx[i]])(dst[idx[i]] + (src[i] + rhs[i])),
      jump. loop { i = i + 1 },
    },

    block. done {} {
      ret (),
    },
  },

  fn. scatter_reduce_mul_i32 { dst [ptr [i32]], src [ptr [i32]], idx [ptr [i32]], n [i32] } [void] {
    requires {
      bounds (dst)(n),
      bounds (src)(n), readonly(src),
      bounds (idx)(n), readonly(idx),
      disjoint (dst)(src), disjoint (dst)(idx), disjoint (src)(idx),
    },

    entry. start {} { jump. loop { i = 0 }, },

    block. loop { i [i32] } {
      when (i :lt (n)) {
        jump. body { i = i },
      },

      jump. done {},
    },

    block. body { i [i32] } {
      set (dst[idx[i]])(dst[idx[i]] * src[i]),
      jump. loop { i = i + 1 },
    },

    block. done {} {
      ret (),
    },
  },

  fn. scatter_reduce_and_i32 { dst [ptr [i32]], src [ptr [i32]], idx [ptr [i32]], n [i32] } [void] {
    requires {
      bounds (dst)(n),
      bounds (src)(n), readonly(src),
      bounds (idx)(n), readonly(idx),
      disjoint (dst)(src), disjoint (dst)(idx), disjoint (src)(idx),
    },

    entry. start {} { jump. loop { i = 0 }, },

    block. loop { i [i32] } {
      when (i :lt (n)) {
        jump. body { i = i },
      },

      jump. done {},
    },

    block. body { i [i32] } {
      set (dst[idx[i]])(band (dst[idx[i]])(src[i])),
      jump. loop { i = i + 1 },
    },

    block. done {} {
      ret (),
    },
  },

  fn. scatter_reduce_or_i32 { dst [ptr [i32]], src [ptr [i32]], idx [ptr [i32]], n [i32] } [void] {
    requires {
      bounds (dst)(n),
      bounds (src)(n), readonly(src),
      bounds (idx)(n), readonly(idx),
      disjoint (dst)(src), disjoint (dst)(idx), disjoint (src)(idx),
    },

    entry. start {} { jump. loop { i = 0 }, },

    block. loop { i [i32] } {
      when (i :lt (n)) {
        jump. body { i = i },
      },

      jump. done {},
    },

    block. body { i [i32] } {
      set (dst[idx[i]])(bor (dst[idx[i]])(src[i])),
      jump. loop { i = i + 1 },
    },

    block. done {} {
      ret (),
    },
  },

  fn. scatter_reduce_xor_i32 { dst [ptr [i32]], src [ptr [i32]], idx [ptr [i32]], n [i32] } [void] {
    requires {
      bounds (dst)(n),
      bounds (src)(n), readonly(src),
      bounds (idx)(n), readonly(idx),
      disjoint (dst)(src), disjoint (dst)(idx), disjoint (src)(idx),
    },

    entry. start {} { jump. loop { i = 0 }, },

    block. loop { i [i32] } {
      when (i :lt (n)) {
        jump. body { i = i },
      },

      jump. done {},
    },

    block. body { i [i32] } {
      set (dst[idx[i]])(bxor (dst[idx[i]])(src[i])),
      jump. loop { i = i + 1 },
    },

    block. done {} {
      ret (),
    },
  },

  fn. scatter_reduce_min_i32 { dst [ptr [i32]], src [ptr [i32]], idx [ptr [i32]], n [i32] } [void] {
    requires {
      bounds (dst)(n),
      bounds (src)(n), readonly(src),
      bounds (idx)(n), readonly(idx),
      disjoint (dst)(src), disjoint (dst)(idx), disjoint (src)(idx),
    },

    entry. start {} { jump. loop { i = 0 }, },

    block. loop { i [i32] } {
      when (i :lt (n)) {
        jump. body { i = i },
      },

      jump. done {},
    },

    block. body { i [i32] } {
      set (dst[idx[i]])(min (dst[idx[i]])(src[i])),
      jump. loop { i = i + 1 },
    },

    block. done {} {
      ret (),
    },
  },

  fn. scatter_reduce_max_i32 { dst [ptr [i32]], src [ptr [i32]], idx [ptr [i32]], n [i32] } [void] {
    requires {
      bounds (dst)(n),
      bounds (src)(n), readonly(src),
      bounds (idx)(n), readonly(idx),
      disjoint (dst)(src), disjoint (dst)(idx), disjoint (src)(idx),
    },

    entry. start {} { jump. loop { i = 0 }, },

    block. loop { i [i32] } {
      when (i :lt (n)) {
        jump. body { i = i },
      },

      jump. done {},
    },

    block. body { i [i32] } {
      set (dst[idx[i]])(max (dst[idx[i]])(src[i])),
      jump. loop { i = i + 1 },
    },

    block. done {} {
      ret (),
    },
  },

  fn. in_place_neg_i32 { dst [ptr [i32]], n [i32] } [void] {
    requires { bounds (dst)(n) },

    entry. start {} { jump. loop { i = 0 }, },

    block. loop { i [i32] } {
      when (i :lt (n)) {
        jump. body { i = i },
      },

      jump. done {},
    },

    block. body { i [i32] } {
      set (dst[i])(-dst[i]),
      jump. loop { i = i + 1 },
    },

    block. done {} {
      ret (),
    },
  },

  fn. count_gt_zero_i32 { xs [ptr [i32]], n [i32] } [i32] {
    requires { bounds (xs)(n), readonly(xs) },

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
    requires { bounds (xs)(n), readonly(xs) },

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
      bounds (lhs)(n), readonly(lhs),
      bounds (rhs)(n), readonly(rhs),
      disjoint (lhs)(rhs),
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
      bounds (dst)(n), writeonly(dst),
      bounds (xs)(n), readonly(xs),
      disjoint (dst)(xs),
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
      set (dst[i])(nxt),
      jump. loop { i = i + 1, acc = nxt },
    },

    block. done { acc [i32] } {
      ret (acc),
    },
  },

  fn. find_gt_zero_i32 { xs [ptr [i32]], n [i32] } [i32] {
    requires { bounds (xs)(n), readonly(xs) },

    entry. start {} { jump. loop { i = 0 }, },

    block. loop { i [i32] } {
      when (i :lt (n)) {
        jump. body { i = i },
      },

      jump. done { pos = -1 },
    },

    block. body { i [i32] } {
      when (xs[i] :gt (0)) {
        jump. done { pos = i },
      },

      jump. loop { i = i + 1 },
    },

    block. done { pos [i32] } {
      ret (pos),
    },
  },

  fn. partition_gt_zero_i32 { dst [ptr [i32]], xs [ptr [i32]], n [i32] } [i32] {
    requires {
      bounds (dst)(n), writeonly(dst),
      bounds (xs)(n), readonly(xs),
      disjoint (dst)(xs),
    },

    entry. start {} { jump. pos_loop { i = 0, out = 0 }, },

    block. pos_loop { i [i32], out [i32] } {
      when (i :lt (n)) {
        jump. pos_body { i = i, out = out },
      },

      jump. neg_loop { j = 0, out = out },
    },

    block. pos_body { i [i32], out [i32] } {
      when (xs[i] :gt (0)) {
        set (dst[out])(xs[i]),
        jump. pos_loop { i = i + 1, out = out + 1 },
      },

      jump. pos_loop { i = i + 1, out = out },
    },

    block. neg_loop { j [i32], out [i32] } {
      when (j :lt (n)) {
        jump. neg_body { j = j, out = out },
      },

      jump. done { split = out },
    },

    block. neg_body { j [i32], out [i32] } {
      when (xs[j] :gt (0)) {
        jump. neg_loop { j = j + 1, out = out },
      },

      set (dst[out])(xs[j]),
      jump. neg_loop { j = j + 1, out = out + 1 },
    },

    block. done { split [i32] } {
      ret (split),
    },
  },

}
]=]

local session = lalin.use { scope = 'env' }
local decl = assert(session:loadstring(source, 'test_luajit_artifact_from_dsl.lua'))()
local LowerPlan = require('tests.code_ir.luajit_lower_plan_helper')
local plan = LowerPlan.plan(decl, {
    name = 'ResidualRegression',
})
local artifact = { kind = 'LuaJITLowerPlan', artifacts = plan.artifacts }

assert(#artifact.artifacts == 30, 'expected selected stencil artifact for each DSL loop')

local expected_counts = {
    store_n = 15,
    reduce = 1,
    reduce_n = 3,
    scatter_reduce = 8,
    scan = 1,
    find = 1,
    partition = 1,
}
local function selected_label(descriptor)
    local function class_name(v)
        return tostring(asdl.classof(v)):match('Class%((.-)%)')
    end
    local function access_named(name)
        for _, access in ipairs(descriptor.accesses or {}) do
            if access.name == name then return access end
        end
        return nil
    end
    local sink_kind = class_name(descriptor.sink)
    local expr = descriptor.body.expr
    local expr_kind = class_name(expr)
    local function layout_kind(access)
        return access and class_name(access.layout) or nil
    end
    local function has_indexed_read()
        for _, access in ipairs(descriptor.accesses or {}) do
            if class_name(access.role) == 'LalinStencil.StencilAccessRead'
                and layout_kind(access) == 'LalinStencil.StencilLayoutIndexed' then return true end
        end
        return false
    end
    local function read_count()
        local n = 0
        for _, access in ipairs(descriptor.accesses or {}) do
            if class_name(access.role) == 'LalinStencil.StencilAccessRead'
                and layout_kind(access) ~= 'LalinStencil.StencilLayoutScalar' then n = n + 1 end
        end
        return n
    end
    if sink_kind == 'LalinStencil.StencilSinkScan' then return 'scan' end
    if sink_kind == 'LalinStencil.StencilSinkScatterReduce' then return 'scatter_reduce' end
    if sink_kind == 'LalinStencil.StencilSinkReduce' then
        local semantics_kind = class_name(descriptor.sink.semantics)
        if semantics_kind == 'LalinStencil.StencilReduceFind' then return 'find' end
        if expr_kind ~= 'LalinStencil.StencilPointInput' then return 'reduce_n' end
        return 'reduce'
    end
    if sink_kind == 'LalinStencil.StencilSinkStore' then
        local semantics_kind = class_name(descriptor.sink.semantics)
        if semantics_kind == 'LalinStencil.StencilStorePartition' then return 'partition' end
        return 'store_n'
    end
    return nil
end
local seen = {}
local nested_point_binary = 0
for _, selected in ipairs(artifact.artifacts) do
    local descriptor = selected.instance.descriptor
    local label = selected_label(descriptor)
    assert(label ~= nil, 'unexpected selected stencil descriptor ' .. tostring(asdl.classof(descriptor)))
    if tostring(asdl.classof(descriptor.body.expr)):match('StencilPointBinary')
        and tostring(asdl.classof(descriptor.body.expr.left)):match('StencilPointBinary')
        and tostring(asdl.classof(descriptor.body.expr.right)):match('StencilPointBinary') then
        nested_point_binary = nested_point_binary + 1
    end
    if label == 'find' or label == 'partition' or label == 'scatter_reduce' then
        assert(tostring(selected.instance.schedule):match('StencilScheduleScalar'), label .. ' should carry a scalar ordered-control stencil schedule')
    else
        assert(tostring(selected.instance.schedule):match('StencilScheduleAutoVector'), label .. ' should carry an auto-vector stencil schedule')
    end
    seen[label] = (seen[label] or 0) + 1
end
for label, count in pairs(expected_counts) do
    assert(seen[label] == count, 'expected ' .. tostring(count) .. ' selected stencil artifact(s) for ' .. label .. ', got ' .. tostring(seen[label] or 0))
end
assert(nested_point_binary >= 2, 'expected nested point binary bodies from fused source expressions')

-- This broad DSL fixture intentionally stops at LuaJIT lowering.  The removed
-- LuaJIT machine-code path used to execute these selected C stencil artifacts;
-- native execution now belongs to standalone LalinNative tests.
io.write('test_luajit_artifact_from_dsl: ok\n')
