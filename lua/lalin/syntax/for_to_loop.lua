-- lalin.syntax.for_to_loop
-- Typed parsed-domain lowering into an explicit Tree control region.

local function bind_context(T)
  local C, Ty, B, Tr, P = T.LalinCore, T.LalinType, T.LalinBind, T.LalinTree, T.LalinParse
  local idx_ty = Ty.TScalar(C.ScalarIndex)

  local function lit(n)
    return Tr.ExprLit(Tr.ExprSurface, C.LitInt(tostring(n)))
  end
  local function ref(name)
    return Tr.ExprRef(Tr.ExprSurface, B.ValueRefName(name))
  end
  local function cast_as(ty, expr)
    return Tr.ExprCast(Tr.ExprSurface, C.SurfaceCast, ty, expr)
  end
  local function cast_idx(expr) return cast_as(idx_ty, expr) end
  local function bin(op, lhs, rhs)
    return Tr.ExprBinary(Tr.ExprSurface, op, lhs, rhs)
  end
  local function local_binding(loop_id, name, ty)
    return B.Binding(C.Id("parsed.loop." .. loop_id .. "." .. name),
      name, ty, B.BindingRoleLocalValue)
  end

  function Tr.Expr:parsed_loop_integer()
    return P.ParsedLoopIntegerRejected("loop extent must be an integer literal")
  end
  function Tr.ExprLit:parsed_loop_integer()
    return self.value:parsed_loop_integer_literal()
  end
  function Tr.ExprCast:parsed_loop_integer()
    return self.value:parsed_loop_integer()
  end
  function Tr.ExprUnary:parsed_loop_integer()
    return self.op:parsed_loop_integer_unary(self.value)
  end
  function C.UnaryOp:parsed_loop_integer_unary(_value)
    return P.ParsedLoopIntegerRejected("loop extent unary operator is not integral")
  end
  function C.UnaryNeg:parsed_loop_integer_unary(value)
    return value:parsed_loop_integer():parsed_loop_integer_negate()
  end
  function P.ParsedLoopInteger:parsed_loop_integer_negate()
    return P.ParsedLoopInteger(-self.value)
  end
  function P.ParsedLoopIntegerRejected:parsed_loop_integer_negate() return self end
  function C.Literal:parsed_loop_integer_literal()
    return P.ParsedLoopIntegerRejected("loop extent must be an integer literal")
  end
  function C.LitInt:parsed_loop_integer_literal()
    local value = tonumber(self.raw)
    if value == nil or value ~= math.floor(value) then
      return P.ParsedLoopIntegerRejected("loop extent must be an integer literal")
    end
    return P.ParsedLoopInteger(value)
  end
  function P.ParsedLoopAxis:resolve_parsed_loop_axis()
    return self.step:parsed_loop_integer():parsed_loop_axis_step(self)
  end
  function P.ParsedLoopInteger:parsed_loop_axis_step(axis)
    if self.value == 0 then
      return P.ParsedLoopAxisRejected("loop step must be nonzero")
    end
    if self.value < 0 then
      return P.ParsedLoopAxisResolved(P.ParsedResolvedLoopAxis(
        axis.start, axis.stop, -self.value, Tr.ControlLoopBackward,
        Ty.TScalar(C.ScalarI32)))
    end
    return P.ParsedLoopAxisResolved(P.ParsedResolvedLoopAxis(
      axis.start, axis.stop, self.value, Tr.ControlLoopForward, idx_ty))
  end
  function P.ParsedLoopIntegerRejected:parsed_loop_axis_step(_axis)
    return P.ParsedLoopAxisRejected(self.reason)
  end
  local function axis_traversal(input, distance, valid, coordinate)
    local axis = input.axis
    local step = cast_as(axis.index_ty, lit(axis.step))
    local rounded = distance
    if axis.step ~= 1 then
      rounded = bin(C.BinDiv,
        bin(C.BinAdd, distance, cast_as(axis.index_ty, lit(axis.step - 1))),
        step)
    end
    local trip = Tr.ExprSelect(Tr.ExprSurface, valid,
      cast_as(axis.index_ty, rounded), cast_as(axis.index_ty, lit(0)))
    return P.ParsedLoopAxisTraversal(
      cast_as(axis.index_ty, axis.start),
      cast_as(axis.index_ty, axis.stop), trip, coordinate)
  end
  function Tr.ControlLoopForward:parsed_loop_axis_traversal(input)
    local axis = input.axis
    local start_init = cast_as(axis.index_ty, axis.start)
    local stop_init = cast_as(axis.index_ty, axis.stop)
    local lane = cast_as(axis.index_ty, input.lane)
    local step = cast_as(axis.index_ty, lit(axis.step))
    local coordinate = bin(C.BinAdd, input.start_ref,
      axis.step == 1 and lane or bin(C.BinMul, lane, step))
    return axis_traversal(input,
      bin(C.BinSub, stop_init, start_init),
      Tr.ExprCompare(Tr.ExprSurface, C.CmpLt, start_init, stop_init),
      coordinate)
  end
  function Tr.ControlLoopBackward:parsed_loop_axis_traversal(input)
    local axis = input.axis
    local start_init = cast_as(axis.index_ty, axis.start)
    local stop_init = cast_as(axis.index_ty, axis.stop)
    local lane = cast_as(axis.index_ty, input.lane)
    local step = cast_as(axis.index_ty, lit(axis.step))
    local coordinate = bin(C.BinSub, input.start_ref,
      axis.step == 1 and lane or bin(C.BinMul, lane, step))
    return axis_traversal(input,
      bin(C.BinSub, start_init, stop_init),
      Tr.ExprCompare(Tr.ExprSurface, C.CmpGt, start_init, stop_init),
      coordinate)
  end
  function P.ParsedWindowAxis:resolve_parsed_window_axis()
    return self.before:parsed_loop_integer():parsed_loop_window_before(self)
  end
  function P.ParsedLoopInteger:parsed_loop_window_before(axis)
    if self.value < 0 then
      return P.ParsedWindowAxisRejected("window extents must be nonnegative")
    end
    return axis.after:parsed_loop_integer():parsed_loop_window_after(
      P.ParsedWindowAxisResolveInput(axis, self.value))
  end
  function P.ParsedLoopIntegerRejected:parsed_loop_window_before(_axis)
    return P.ParsedWindowAxisRejected(self.reason)
  end
  function P.ParsedLoopInteger:parsed_loop_window_after(input)
    if self.value < 0 then
      return P.ParsedWindowAxisRejected("window extents must be nonnegative")
    end
    return P.ParsedWindowAxisResolved(
      P.ParsedResolvedWindowAxis(input.before, self.value, input.axis.boundary))
  end
  function P.ParsedLoopIntegerRejected:parsed_loop_window_after(_input)
    return P.ParsedWindowAxisRejected(self.reason)
  end

  function P.ParsedLoopDomain:resolve_parsed_loop_domain()
    return P.ParsedLoopDomainRejected("parsed domain resolution is pending")
  end
  function P.ParsedLoopDomain:resolve_parsed_loop_axes(input)
    if input.index > #self.axes then return self:parsed_loop_resolve_complete(input) end
    return self.axes[input.index]:resolve_parsed_loop_axis():parsed_loop_axis_fold_continue(input)
  end
  function P.ParsedLoopRangeND:resolve_parsed_loop_domain()
    return self:resolve_parsed_loop_axes(P.ParsedLoopAxisResolveInput(self, 1, {}, {}, {}))
  end
  function P.ParsedLoopRangeND:parsed_loop_resolve_complete(input)
    return P.ParsedLoopDomainResolved(P.ParsedResolvedLoopRangeND(input.axes))
  end
  function P.ParsedLoopAxisResolved:parsed_loop_axis_fold_continue(input)
    local axes = {}
    for i = 1, #input.axes do axes[i] = input.axes[i] end
    axes[#axes + 1] = self.axis
    return input.domain:resolve_parsed_loop_axes(
      P.ParsedLoopAxisResolveInput(input.domain, input.index + 1, axes, input.windows, input.tile_sizes))
  end
  function P.ParsedLoopAxisRejected:parsed_loop_axis_fold_continue(_input)
    return P.ParsedLoopDomainRejected(self.reason)
  end
  function P.ParsedLoopWindowND:resolve_parsed_loop_domain()
    if #self.axes ~= #self.windows then
      return P.ParsedLoopDomainRejected("window domain axis/window arity mismatch")
    end
    return self:resolve_parsed_loop_windows(P.ParsedLoopWindowResolveInput(self, 1, {}))
  end
  function P.ParsedLoopWindowND:resolve_parsed_loop_windows(input)
    if input.index > #self.windows then
      return self:resolve_parsed_loop_axes(
        P.ParsedLoopAxisResolveInput(self, 1, {}, input.resolved, {}))
    end
    return self.windows[input.index]:resolve_parsed_window_axis():parsed_loop_window_fold_continue(input)
  end
  function P.ParsedWindowAxisResolved:parsed_loop_window_fold_continue(input)
    local resolved = {}
    for i = 1, #input.resolved do resolved[i] = input.resolved[i] end
    resolved[#resolved + 1] = self.axis
    return input.domain:resolve_parsed_loop_windows(
      P.ParsedLoopWindowResolveInput(input.domain, input.index + 1, resolved))
  end
  function P.ParsedWindowAxisRejected:parsed_loop_window_fold_continue(_input)
    return P.ParsedLoopDomainRejected(self.reason)
  end
  function P.ParsedLoopWindowND:parsed_loop_resolve_complete(input)
    return P.ParsedLoopDomainResolved(P.ParsedResolvedLoopWindowND(input.axes, input.windows))
  end
  function P.ParsedLoopTiledND:resolve_parsed_loop_domain()
    return self:resolve_parsed_loop_tiles(P.ParsedLoopTileResolveInput(self, 1, {}))
  end
  function P.ParsedLoopTiledND:resolve_parsed_loop_tiles(input)
    if input.index > #self.tile_sizes then
      return self:resolve_parsed_loop_axes(
        P.ParsedLoopAxisResolveInput(self, 1, {}, {}, input.resolved))
    end
    return self.tile_sizes[input.index]:parsed_loop_integer():parsed_loop_tile_fold_continue(input)
  end
  function P.ParsedLoopInteger:parsed_loop_tile_fold_continue(input)
    if self.value <= 0 then
      return P.ParsedLoopDomainRejected("tile sizes must be positive")
    end
    local resolved = {}
    for i = 1, #input.resolved do resolved[i] = input.resolved[i] end
    resolved[#resolved + 1] = self.value
    return input.domain:resolve_parsed_loop_tiles(
      P.ParsedLoopTileResolveInput(input.domain, input.index + 1, resolved))
  end
  function P.ParsedLoopIntegerRejected:parsed_loop_tile_fold_continue(_input)
    return P.ParsedLoopDomainRejected(self.reason)
  end
  function P.ParsedLoopTiledND:parsed_loop_resolve_complete(input)
    return P.ParsedLoopDomainResolved(P.ParsedResolvedLoopTiledND(input.axes, input.tile_sizes))
  end

  local lower_1d_no_sink
  local lower_1d_fold
  local lower_1d_scan
  local lower_nd_scan
  function P.ParsedResolvedLoopSink:lower_parsed_loop_1d(_input, _domain)
    return P.ParsedLoopLowerRejected("parsed sink projection is missing")
  end
  function P.ParsedResolvedLoopNoSink:lower_parsed_loop_1d(input, domain)
    return lower_1d_no_sink(input, domain)
  end
  function P.ParsedResolvedLoopFoldSink:lower_parsed_loop_1d(input, domain)
    return domain:lower_parsed_loop_fold_1d(
      P.ParsedLoopFoldLowerInput(input, domain, self))
  end
  function P.ParsedResolvedLoopScanSink:lower_parsed_loop_1d(input, domain)
    return domain:lower_parsed_loop_scan_1d(
      P.ParsedLoopScanLowerInput(input, domain, self))
  end
  function P.ParsedResolvedLoopDomain:lower_parsed_loop_scan_1d(_input)
    return P.ParsedLoopLowerRejected("parsed scan domain projection is pending")
  end
  function P.ParsedResolvedLoopRangeND:lower_parsed_loop_scan_1d(input)
    return input.sink.axis:lower_parsed_loop_scan_axis(input)
  end
  function P.ParsedResolvedLoopWindowND:lower_parsed_loop_scan_1d(input)
    return input.sink.axis:lower_parsed_loop_scan_axis(input)
  end
  function P.ParsedResolvedLoopTiledND:lower_parsed_loop_scan_1d(input)
    return input.sink.axis:lower_parsed_loop_scan_axis(input)
  end
  local function lower_scan_into(input)
    return input.scan.sink.into:parsed_loop_scan_place()
      :lower_parsed_loop_scan(input)
  end
  function P.ParsedLoopScanAxisDefault:lower_parsed_loop_scan_axis(input)
    if #input.loop.indexes ~= 1 then
      return P.ParsedLoopLowerRejected(
        "multi-axis scan requires an explicit `over` axis")
    end
    return lower_scan_into(P.ParsedLoopScanExecutionInput(input, 1))
  end
  function P.ParsedLoopScanAxisName:lower_parsed_loop_scan_axis(input)
    for i = 1, #input.loop.indexes do
      if self.name == input.loop.indexes[i] then
        return lower_scan_into(P.ParsedLoopScanExecutionInput(input, i))
      end
    end
    return P.ParsedLoopLowerRejected("scan axis does not name a loop index")
  end
  function P.ParsedLoopScanAxisExpr:lower_parsed_loop_scan_axis(input)
    return self.expr:parsed_loop_integer():lower_parsed_loop_scan_axis(input)
  end
  function P.ParsedLoopInteger:lower_parsed_loop_scan_axis(input)
    if self.value < 1 or self.value > #input.loop.indexes then
      return P.ParsedLoopLowerRejected("scan axis ordinal is outside the loop axes")
    end
    return lower_scan_into(
      P.ParsedLoopScanExecutionInput(input, self.value))
  end
  function P.ParsedLoopIntegerRejected:lower_parsed_loop_scan_axis(_input)
    return P.ParsedLoopLowerRejected(self.reason)
  end
  function P.ParsedResolvedLoopDomain:lower_parsed_loop_fold_1d(_input)
    return P.ParsedLoopLowerRejected("parsed fold domain projection is pending")
  end
  function P.ParsedResolvedLoopRangeND:lower_parsed_loop_fold_1d(input)
    return lower_1d_fold(input)
  end
  function P.ParsedResolvedLoopWindowND:lower_parsed_loop_fold_1d(input)
    return lower_1d_fold(input)
  end
  function P.ParsedResolvedLoopTiledND:lower_parsed_loop_fold_1d(input)
    return lower_1d_fold(input)
  end
  local function reducer_binary(op, input)
    return bin(op, input.accumulator, input.contribution)
  end
  function P.ParsedLoopAdd:parsed_loop_reducer_expr(input)
    return reducer_binary(C.BinAdd, input)
  end
  function P.ParsedLoopMul:parsed_loop_reducer_expr(input)
    return reducer_binary(C.BinMul, input)
  end
  function P.ParsedLoopBitAnd:parsed_loop_reducer_expr(input)
    return reducer_binary(C.BinBitAnd, input)
  end
  function P.ParsedLoopBitOr:parsed_loop_reducer_expr(input)
    return reducer_binary(C.BinBitOr, input)
  end
  function P.ParsedLoopBitXor:parsed_loop_reducer_expr(input)
    return reducer_binary(C.BinBitXor, input)
  end
  function P.ParsedLoopMin:parsed_loop_reducer_expr(input)
    return Tr.ExprSelect(Tr.ExprSurface,
      Tr.ExprCompare(Tr.ExprSurface, C.CmpLe,
        input.accumulator, input.contribution),
      input.accumulator, input.contribution)
  end
  function P.ParsedLoopMax:parsed_loop_reducer_expr(input)
    return Tr.ExprSelect(Tr.ExprSurface,
      Tr.ExprCompare(Tr.ExprSurface, C.CmpGe,
        input.accumulator, input.contribution),
      input.accumulator, input.contribution)
  end
  function Tr.Expr:parsed_loop_scan_place()
    return P.ParsedLoopScanPlaceRejected(
      "scan destination expression is not an addressable place")
  end
  function Tr.ExprRef:parsed_loop_scan_place()
    return P.ParsedLoopScanPlaceResolved(Tr.PlaceRef(Tr.PlaceSurface, self.ref))
  end
  function Tr.ExprIndex:parsed_loop_scan_place()
    return P.ParsedLoopScanPlaceResolved(
      Tr.PlaceIndex(Tr.PlaceSurface, self.base, self.index))
  end
  function Tr.ExprDeref:parsed_loop_scan_place()
    return P.ParsedLoopScanPlaceResolved(
      Tr.PlaceDeref(Tr.PlaceSurface, self.value))
  end
  function Tr.ExprDot:parsed_loop_scan_place()
    return self.base:parsed_loop_scan_place():parsed_loop_scan_dot_place(self)
  end
  function P.ParsedLoopScanPlaceRejected:parsed_loop_scan_dot_place(_expr)
    return self
  end
  function P.ParsedLoopScanPlaceResolved:parsed_loop_scan_dot_place(expr)
    return P.ParsedLoopScanPlaceResolved(
      Tr.PlaceDot(Tr.PlaceSurface, self.place, expr.name))
  end
  function P.ParsedLoopScanPlaceRejected:lower_parsed_loop_scan(_input)
    return P.ParsedLoopLowerRejected(self.reason)
  end
  function P.ParsedLoopScanPlaceResolved:lower_parsed_loop_scan(input)
    return lower_1d_scan(input, self.place)
  end


  function B.ValueRef:parsed_loop_rewrite_index(_input, original) return original end
  function B.ValueRefName:parsed_loop_rewrite_index(input, original)
    if self.name == input.index_name then return input.replacement end
    return original
  end
  function Tr.Expr:parsed_loop_rewrite_index(_input) return self end
  function Tr.ExprRef:parsed_loop_rewrite_index(input)
    return self.ref:parsed_loop_rewrite_index(input, self)
  end
  local function rewrite_exprs(values, input)
    local out = {}
    for i = 1, #values do out[i] = values[i]:parsed_loop_rewrite_index(input) end
    return out
  end
  local function rewrite_stmts(values, input)
    local out = {}
    for i = 1, #values do out[i] = values[i]:parsed_loop_rewrite_index(input) end
    return out
  end
  function Tr.ExprUnary:parsed_loop_rewrite_index(input)
    return Tr.ExprUnary(self.h, self.op, self.value:parsed_loop_rewrite_index(input))
  end
  function Tr.ExprLogic:parsed_loop_rewrite_index(input)
    return Tr.ExprLogic(self.h, self.op,
      self.lhs:parsed_loop_rewrite_index(input), self.rhs:parsed_loop_rewrite_index(input))
  end
  function Tr.ExprMachineCast:parsed_loop_rewrite_index(input)
    return Tr.ExprMachineCast(self.h, self.op, self.ty,
      self.value:parsed_loop_rewrite_index(input))
  end
  function Tr.ExprCall:parsed_loop_rewrite_index(input)
    return Tr.ExprCall(self.h, self.callee:parsed_loop_rewrite_index(input),
      rewrite_exprs(self.args, input))
  end
  function Tr.ExprDot:parsed_loop_rewrite_index(input)
    return Tr.ExprDot(self.h, self.base:parsed_loop_rewrite_index(input), self.name)
  end
  function Tr.ExprDeref:parsed_loop_rewrite_index(input)
    return Tr.ExprDeref(self.h, self.value:parsed_loop_rewrite_index(input))
  end
  function Tr.ExprLen:parsed_loop_rewrite_index(input)
    return Tr.ExprLen(self.h, self.value:parsed_loop_rewrite_index(input))
  end
  function Tr.ExprField:parsed_loop_rewrite_index(input)
    return Tr.ExprField(self.h, self.base:parsed_loop_rewrite_index(input), self.field)
  end
  function Tr.ExprIf:parsed_loop_rewrite_index(input)
    return Tr.ExprIf(self.h, self.cond:parsed_loop_rewrite_index(input),
      self.then_expr:parsed_loop_rewrite_index(input),
      self.else_expr:parsed_loop_rewrite_index(input))
  end
  function Tr.ExprSelect:parsed_loop_rewrite_index(input)
    return Tr.ExprSelect(self.h, self.cond:parsed_loop_rewrite_index(input),
      self.then_expr:parsed_loop_rewrite_index(input),
      self.else_expr:parsed_loop_rewrite_index(input))
  end
  function Tr.ExprCast:parsed_loop_rewrite_index(input)
    return Tr.ExprCast(self.h, self.op, self.ty, self.value:parsed_loop_rewrite_index(input))
  end
  function Tr.ExprBinary:parsed_loop_rewrite_index(input)
    return Tr.ExprBinary(self.h, self.op,
      self.lhs:parsed_loop_rewrite_index(input), self.rhs:parsed_loop_rewrite_index(input))
  end
  function Tr.ExprCompare:parsed_loop_rewrite_index(input)
    return Tr.ExprCompare(self.h, self.op,
      self.lhs:parsed_loop_rewrite_index(input), self.rhs:parsed_loop_rewrite_index(input))
  end
  function Tr.IndexBase:parsed_loop_rewrite_index(_input) return self end
  function Tr.IndexBaseExpr:parsed_loop_rewrite_index(input)
    return Tr.IndexBaseExpr(self.base:parsed_loop_rewrite_index(input))
  end
  function Tr.IndexBasePlace:parsed_loop_rewrite_index(input)
    return Tr.IndexBasePlace(self.base:parsed_loop_rewrite_index(input), self.elem)
  end
  function Tr.ExprIndex:parsed_loop_rewrite_index(input)
    return Tr.ExprIndex(self.h, self.base:parsed_loop_rewrite_index(input),
      self.index:parsed_loop_rewrite_index(input))
  end
  function Tr.Place:parsed_loop_rewrite_index(_input) return self end
  function Tr.PlaceDeref:parsed_loop_rewrite_index(input)
    return Tr.PlaceDeref(self.h, self.base:parsed_loop_rewrite_index(input))
  end
  function Tr.PlaceField:parsed_loop_rewrite_index(input)
    return Tr.PlaceField(self.h, self.base:parsed_loop_rewrite_index(input), self.field)
  end
  function Tr.PlaceIndex:parsed_loop_rewrite_index(input)
    return Tr.PlaceIndex(self.h, self.base:parsed_loop_rewrite_index(input),
      self.index:parsed_loop_rewrite_index(input))
  end
  function Tr.PlaceDot:parsed_loop_rewrite_index(input)
    return Tr.PlaceDot(self.h, self.base:parsed_loop_rewrite_index(input), self.name)
  end
  function Tr.Stmt:parsed_loop_rewrite_index(_input) return self end
  function Tr.StmtSet:parsed_loop_rewrite_index(input)
    return Tr.StmtSet(self.h, self.place:parsed_loop_rewrite_index(input),
      self.value:parsed_loop_rewrite_index(input))
  end
  function Tr.StmtLet:parsed_loop_rewrite_index(input)
    return Tr.StmtLet(self.h, self.binding, self.init:parsed_loop_rewrite_index(input))
  end
  function Tr.StmtVar:parsed_loop_rewrite_index(input)
    return Tr.StmtVar(self.h, self.binding, self.init:parsed_loop_rewrite_index(input))
  end
  function Tr.StmtIf:parsed_loop_rewrite_index(input)
    return Tr.StmtIf(self.h, self.cond:parsed_loop_rewrite_index(input),
      rewrite_stmts(self.then_body, input), rewrite_stmts(self.else_body, input))
  end
  function Tr.StmtAssert:parsed_loop_rewrite_index(input)
    return Tr.StmtAssert(self.h, self.cond:parsed_loop_rewrite_index(input))
  end
  function Tr.StmtReturnValue:parsed_loop_rewrite_index(input)
    return Tr.StmtReturnValue(self.h, self.value:parsed_loop_rewrite_index(input))
  end
  function Tr.StmtExpr:parsed_loop_rewrite_index(input)
    return Tr.StmtExpr(self.h, self.expr:parsed_loop_rewrite_index(input))
  end

  local function control_axes(input, domain)
    local axes = {}
    for i = 1, #domain.axes do
      local start_ordinal = #domain.axes == 1 and 1 or 2 + (i - 1) * 3
      axes[i] = Tr.ControlLoopAxis(input.indexes[i], domain.axes[i].index_ty,
        start_ordinal, 3 + (i - 1) * 3, 4 + (i - 1) * 3,
        domain.axes[i].step, domain.axes[i].order)
    end
    return axes
  end
  function P.ParsedResolvedLoopRangeND:parsed_loop_control_domain(input, header)
    return Tr.ControlLoopRangeND(header, control_axes(input, self))
  end
  function P.ParsedResolvedLoopWindowND:parsed_loop_control_domain(input, header)
    local windows = {}
    for i = 1, #self.windows do
      local w = self.windows[i]
      windows[i] = Tr.ControlWindowAxis(w.before, w.after, w.boundary)
    end
    return Tr.ControlLoopWindowND(header, control_axes(input, self), windows)
  end
  function P.ParsedResolvedLoopTiledND:parsed_loop_control_domain(input, header)
    return Tr.ControlLoopTiledND(header, control_axes(input, self), self.tile_sizes)
  end

  local function parsed_loop_runtime_order(input, domain, flat_ref, order)
    local axes = {}
    local suffix = cast_idx(lit(1))
    for position = #order, 1, -1 do
      local i = order[position]
      local axis = domain.axes[i]
      local start_name = "__lln_axis_" .. tostring(i) .. "_start_" .. input.loop_id
      local stop_name = "__lln_axis_" .. tostring(i) .. "_stop_" .. input.loop_id
      local trip_name = "__lln_axis_" .. tostring(i) .. "_trip_" .. input.loop_id
      local lane = flat_ref
      if #domain.axes > 1 then
        if position < #order then lane = bin(C.BinDiv, flat_ref, suffix) end
        lane = bin(C.BinRem, lane, cast_idx(ref(trip_name)))
      end
      local traversal = axis.order:parsed_loop_axis_traversal(
        P.ParsedLoopAxisTraversalInput(
          axis, lane, ref(start_name), ref(stop_name)))
      axes[i] = P.ParsedLoopAxisRuntime(
        axis, input.indexes[i], start_name, stop_name, trip_name, traversal)
      if position == #order then
        suffix = cast_idx(ref(trip_name))
      else
        suffix = bin(C.BinMul, suffix, cast_idx(ref(trip_name)))
      end
    end
    return P.ParsedLoopRuntime(axes, suffix)
  end
  local function parsed_loop_runtime(input, domain, flat_ref)
    local order = {}
    for i = 1, #domain.axes do order[i] = i end
    return parsed_loop_runtime_order(input, domain, flat_ref, order)
  end
  function Tr.ControlLoopForward:parsed_loop_order_control(input)
    local step = cast_as(input.axis.index_ty, lit(input.axis.step))
    return P.ParsedLoopOrderControl(
      bin(C.BinAdd, input.counter, step),
      Tr.ExprCompare(Tr.ExprSurface, C.CmpLt, input.counter, input.stop_ref))
  end
  function Tr.ControlLoopBackward:parsed_loop_order_control(input)
    local step = cast_as(input.axis.index_ty, lit(input.axis.step))
    return P.ParsedLoopOrderControl(
      bin(C.BinSub, input.counter, step),
      Tr.ExprCompare(Tr.ExprSurface, C.CmpGt, input.counter, input.stop_ref))
  end
  local function parsed_loop_control(input, domain, flat_ref)
    local runtime = parsed_loop_runtime(input, domain, flat_ref)
    if #runtime.axes == 1 then
      local item = runtime.axes[1]
      local traversal = P.ParsedLoopAxisTraversal(
        item.traversal.start_init, item.traversal.stop_init,
        item.traversal.trip_init, flat_ref)
      local exact_runtime = P.ParsedLoopRuntime({
        P.ParsedLoopAxisRuntime(item.axis, item.index_name, item.start_name,
          item.stop_name, item.trip_name, traversal),
      }, ref(item.trip_name))
      local order = item.axis.order:parsed_loop_order_control(
        P.ParsedLoopOrderControlInput(item.axis, flat_ref, ref(item.stop_name)))
      return P.ParsedLoopControl(exact_runtime, item.axis.index_ty,
        item.traversal.start_init, order.next_counter, order.condition)
    end
    return P.ParsedLoopControl(runtime, idx_ty, cast_idx(lit(0)),
      bin(C.BinAdd, flat_ref, cast_idx(lit(1))),
      Tr.ExprCompare(Tr.ExprSurface, C.CmpLt, flat_ref, runtime.total))
  end
  local function append_runtime_params(params, runtime)
    for i = 1, #runtime.axes do
      local item = runtime.axes[i]
      params[#params + 1] = Tr.BlockParam(item.start_name, item.axis.index_ty)
      params[#params + 1] = Tr.BlockParam(item.stop_name, item.axis.index_ty)
      params[#params + 1] = Tr.BlockParam(item.trip_name, item.axis.index_ty)
    end
    return params
  end
  local function append_runtime_args(args, runtime, entry)
    for i = 1, #runtime.axes do
      local item = runtime.axes[i]
      args[#args + 1] = Tr.JumpArg(item.start_name,
        entry and item.traversal.start_init or ref(item.start_name))
      args[#args + 1] = Tr.JumpArg(item.stop_name,
        entry and item.traversal.stop_init or ref(item.stop_name))
      args[#args + 1] = Tr.JumpArg(item.trip_name,
        entry and item.traversal.trip_init or ref(item.trip_name))
    end
    return args
  end
  local function rewrite_runtime(value, runtime)
    local rewritten = value
    for i = 1, #runtime.axes do
      rewritten = rewritten:parsed_loop_rewrite_index(
        P.ParsedLoopIndexRewriteInput(
          runtime.axes[i].index_name, runtime.axes[i].traversal.coordinate))
    end
    return rewritten
  end

  lower_1d_no_sink = function(input, domain)
    if #domain.axes == 0 or #domain.axes ~= #input.indexes then
      return P.ParsedLoopLowerRejected("loop index/domain arity mismatch")
    end
    local tag = input.loop_id
    local flat_name = "__lln_flat_" .. tag
    local entry_label = Tr.BlockLabel("lln_entry_" .. tag)
    local loop_label = Tr.BlockLabel("lln_loop_" .. tag)
    local body_label = Tr.BlockLabel("lln_body_" .. tag)
    local done_label = Tr.BlockLabel("lln_done_" .. tag)
    local flat_ref = ref(flat_name)
    local control = parsed_loop_control(input, domain, flat_ref)
    local runtime = control.runtime
    local loop_params = append_runtime_params({
      Tr.BlockParam(flat_name, control.counter_ty),
    }, runtime)
    local function jump_args(flat)
      return append_runtime_args({ Tr.JumpArg(flat_name, flat) }, runtime, false)
    end
    local entry_args = append_runtime_args({
      Tr.JumpArg(flat_name, control.initial_counter),
    }, runtime, true)
    local body = {}
    for i = 1, #input.body do
      body[i] = rewrite_runtime(input.body[i], runtime)
    end
    body[#body + 1] = Tr.StmtJump(Tr.StmtSurface, loop_label,
      jump_args(control.next_counter))
    local condition = control.condition
    local region = Tr.ControlStmtRegion(tag,
      Tr.EntryControlBlock(entry_label, {}, {
        Tr.StmtJump(Tr.StmtSurface, loop_label, entry_args),
      }), {
        Tr.ControlBlock(loop_label, loop_params, {
          Tr.StmtBranchJump(Tr.StmtSurface, condition,
            body_label, jump_args(flat_ref), done_label, {}),
        }),
        Tr.ControlBlock(body_label, loop_params, body),
        Tr.ControlBlock(done_label, {}, { Tr.StmtYieldVoid(Tr.StmtSurface) }),
      })
    return P.ParsedLoopLowered(Tr.StmtDomainControl(
      Tr.StmtSurface, region, domain:parsed_loop_control_domain(input, loop_label)))
  end

  lower_1d_fold = function(fold_input)
    local input, domain, sink = fold_input.loop, fold_input.domain, fold_input.sink
    if #domain.axes == 0 or #domain.axes ~= #input.indexes then
      return P.ParsedLoopLowerRejected("fold index/domain arity mismatch")
    end
    local tag = input.loop_id
    local flat_name = "__lln_flat_" .. tag
    local step_name = "__lln_fold_step_" .. tag
    local entry_label = Tr.BlockLabel("lln_entry_" .. tag)
    local loop_label = Tr.BlockLabel("lln_loop_" .. tag)
    local body_label = Tr.BlockLabel("lln_body_" .. tag)
    local done_label = Tr.BlockLabel("lln_done_" .. tag)
    local flat_ref, accumulator_ref = ref(flat_name), ref(sink.name)
    local control = parsed_loop_control(input, domain, flat_ref)
    local runtime = control.runtime
    local loop_params = append_runtime_params({
      Tr.BlockParam(flat_name, control.counter_ty),
    }, runtime)
    loop_params[#loop_params + 1] = Tr.BlockParam(sink.name, sink.ty)
    local function jump_args(flat, accumulator)
      local args = append_runtime_args({ Tr.JumpArg(flat_name, flat) }, runtime, false)
      args[#args + 1] = Tr.JumpArg(sink.name, accumulator)
      return args
    end
    local entry_args = append_runtime_args({
      Tr.JumpArg(flat_name, control.initial_counter),
    }, runtime, true)
    entry_args[#entry_args + 1] = Tr.JumpArg(sink.name, Tr.ExprCast(
      Tr.ExprSurface, C.SurfaceCast, sink.ty, sink.init))
    local body = {}
    for i = 1, #input.body do body[i] = rewrite_runtime(input.body[i], runtime) end
    body[#body + 1] = Tr.StmtLet(Tr.StmtSurface,
      local_binding(tag, step_name, sink.ty), rewrite_runtime(sink.step, runtime))
    local next_accumulator = sink.reducer:parsed_loop_reducer_expr(
      P.ParsedLoopReducerExprInput(accumulator_ref, ref(step_name)))
    body[#body + 1] = Tr.StmtJump(Tr.StmtSurface, loop_label,
      jump_args(control.next_counter, next_accumulator))
    local condition = control.condition
    local region = Tr.ControlExprRegion(tag, sink.ty,
      Tr.EntryControlBlock(entry_label, {}, {
        Tr.StmtJump(Tr.StmtSurface, loop_label, entry_args),
      }), {
        Tr.ControlBlock(loop_label, loop_params, {
          Tr.StmtBranchJump(Tr.StmtSurface, condition,
            body_label, jump_args(flat_ref, accumulator_ref),
            done_label, { Tr.JumpArg(sink.name, accumulator_ref) }),
        }),
        Tr.ControlBlock(body_label, loop_params, body),
        Tr.ControlBlock(done_label, { Tr.BlockParam(sink.name, sink.ty) }, {
          Tr.StmtYieldValue(Tr.StmtSurface, accumulator_ref),
        }),
      })
    return P.ParsedLoopLowered(Tr.StmtReturnValue(Tr.StmtSurface,
      Tr.ExprDomainControl(Tr.ExprSurface, region,
        domain:parsed_loop_control_domain(input, loop_label))))
  end

  lower_nd_scan = function(execution, destination)
    local scan = execution.scan
    local input, domain, sink = scan.loop, scan.domain, scan.sink
    local tag = input.loop_id
    local flat_name = "__lln_flat_" .. tag
    local step_name = "__lln_scan_step_" .. tag
    local next_name = "__lln_scan_next_" .. tag
    local entry_label = Tr.BlockLabel("lln_entry_" .. tag)
    local loop_label = Tr.BlockLabel("lln_loop_" .. tag)
    local body_label = Tr.BlockLabel("lln_body_" .. tag)
    local done_label = Tr.BlockLabel("lln_done_" .. tag)
    local flat_ref, accumulator_ref = ref(flat_name), ref(sink.name)
    local order = {}
    for i = 1, #domain.axes do
      if i ~= execution.axis then order[#order + 1] = i end
    end
    order[#order + 1] = execution.axis
    local runtime = parsed_loop_runtime_order(input, domain, flat_ref, order)
    local loop_params = append_runtime_params({
      Tr.BlockParam(flat_name, idx_ty),
    }, runtime)
    loop_params[#loop_params + 1] = Tr.BlockParam(sink.name, sink.ty)
    local function jump_args(flat, accumulator)
      local args = append_runtime_args({ Tr.JumpArg(flat_name, flat) }, runtime, false)
      args[#args + 1] = Tr.JumpArg(sink.name, accumulator)
      return args
    end
    local entry_args = append_runtime_args({
      Tr.JumpArg(flat_name, cast_idx(lit(0))),
    }, runtime, true)
    local init = Tr.ExprCast(Tr.ExprSurface, C.SurfaceCast, sink.ty, sink.init)
    entry_args[#entry_args + 1] = Tr.JumpArg(sink.name, init)
    local selected = runtime.axes[execution.axis]
    local line_start = Tr.ExprCompare(Tr.ExprSurface, C.CmpEq,
      bin(C.BinRem, flat_ref, cast_idx(ref(selected.trip_name))), cast_idx(lit(0)))
    local line_accumulator = Tr.ExprSelect(
      Tr.ExprSurface, line_start, init, accumulator_ref)
    local body = {}
    for i = 1, #input.body do body[i] = rewrite_runtime(input.body[i], runtime) end
    body[#body + 1] = Tr.StmtLet(Tr.StmtSurface,
      local_binding(tag, step_name, sink.ty), rewrite_runtime(sink.step, runtime))
    local next_accumulator = sink.reducer:parsed_loop_reducer_expr(
      P.ParsedLoopReducerExprInput(line_accumulator, ref(step_name)))
    body[#body + 1] = Tr.StmtLet(Tr.StmtSurface,
      local_binding(tag, next_name, sink.ty), next_accumulator)
    body[#body + 1] = Tr.StmtSet(Tr.StmtSurface,
      rewrite_runtime(destination, runtime), ref(next_name))
    body[#body + 1] = Tr.StmtJump(Tr.StmtSurface, loop_label,
      jump_args(bin(C.BinAdd, flat_ref, cast_idx(lit(1))), ref(next_name)))
    local condition = Tr.ExprCompare(
      Tr.ExprSurface, C.CmpLt, flat_ref, runtime.total)
    local region = Tr.ControlStmtRegion(tag,
      Tr.EntryControlBlock(entry_label, {}, {
        Tr.StmtJump(Tr.StmtSurface, loop_label, entry_args),
      }), {
        Tr.ControlBlock(loop_label, loop_params, {
          Tr.StmtBranchJump(Tr.StmtSurface, condition,
            body_label, jump_args(flat_ref, accumulator_ref), done_label, {}),
        }),
        Tr.ControlBlock(body_label, loop_params, body),
        Tr.ControlBlock(done_label, {}, { Tr.StmtYieldVoid(Tr.StmtSurface) }),
      })
    return P.ParsedLoopLowered(Tr.StmtDomainControl(
      Tr.StmtSurface, region, domain:parsed_loop_control_domain(input, loop_label)))
  end

  lower_1d_scan = function(execution, destination)
    local scan = execution.scan
    local input, domain, sink = scan.loop, scan.domain, scan.sink
    if #domain.axes > 1 then return lower_nd_scan(execution, destination) end
    local axis = domain.axes[1]

    local tag = input.loop_id
    local flat_name = "__lln_flat_" .. tag
    local start_name = "__lln_axis_start_" .. tag
    local stop_name = "__lln_axis_stop_" .. tag
    local trip_name = "__lln_axis_trip_" .. tag
    local step_name = "__lln_scan_step_" .. tag
    local next_name = "__lln_scan_next_" .. tag
    local index_name = input.indexes[1]
    local entry_label = Tr.BlockLabel("lln_entry_" .. tag)
    local loop_label = Tr.BlockLabel("lln_loop_" .. tag)
    local body_label = Tr.BlockLabel("lln_body_" .. tag)
    local done_label = Tr.BlockLabel("lln_done_" .. tag)
    local flat_ref, accumulator_ref = ref(flat_name), ref(sink.name)
    local traversal = axis.order:parsed_loop_axis_traversal(
      P.ParsedLoopAxisTraversalInput(
        axis, flat_ref, ref(start_name), ref(stop_name)))
    local order = axis.order:parsed_loop_order_control(
      P.ParsedLoopOrderControlInput(axis, flat_ref, ref(stop_name)))

    local loop_params = {
      Tr.BlockParam(flat_name, axis.index_ty),
      Tr.BlockParam(start_name, axis.index_ty),
      Tr.BlockParam(stop_name, axis.index_ty),
      Tr.BlockParam(trip_name, axis.index_ty),
      Tr.BlockParam(sink.name, sink.ty),
    }
    local function jump_args(flat, accumulator)
      return {
        Tr.JumpArg(flat_name, flat),
        Tr.JumpArg(start_name, ref(start_name)),
        Tr.JumpArg(stop_name, ref(stop_name)),
        Tr.JumpArg(trip_name, ref(trip_name)),
        Tr.JumpArg(sink.name, accumulator),
      }
    end
    local entry_args = {
      Tr.JumpArg(flat_name, traversal.start_init),
      Tr.JumpArg(start_name, traversal.start_init),
      Tr.JumpArg(stop_name, traversal.stop_init),
      Tr.JumpArg(trip_name, traversal.trip_init),
      Tr.JumpArg(sink.name, Tr.ExprCast(
        Tr.ExprSurface, C.SurfaceCast, sink.ty, sink.init)),
    }

    local rewrite = P.ParsedLoopIndexRewriteInput(index_name, flat_ref)
    local body = {}
    for i = 1, #input.body do
      body[i] = input.body[i]:parsed_loop_rewrite_index(rewrite)
    end
    body[#body + 1] = Tr.StmtLet(Tr.StmtSurface,
      local_binding(tag, step_name, sink.ty),
      sink.step:parsed_loop_rewrite_index(rewrite))
    local next_accumulator = sink.reducer:parsed_loop_reducer_expr(
      P.ParsedLoopReducerExprInput(accumulator_ref, ref(step_name)))
    body[#body + 1] = Tr.StmtLet(Tr.StmtSurface,
      local_binding(tag, next_name, sink.ty), next_accumulator)
    body[#body + 1] = Tr.StmtSet(Tr.StmtSurface,
      destination:parsed_loop_rewrite_index(rewrite), ref(next_name))
    body[#body + 1] = Tr.StmtJump(Tr.StmtSurface, loop_label,
      jump_args(order.next_counter, ref(next_name)))

    local condition = order.condition
    local region = Tr.ControlStmtRegion(tag,
      Tr.EntryControlBlock(entry_label, {}, {
        Tr.StmtJump(Tr.StmtSurface, loop_label, entry_args),
      }), {
        Tr.ControlBlock(loop_label, loop_params, {
          Tr.StmtBranchJump(Tr.StmtSurface, condition,
            body_label, jump_args(flat_ref, accumulator_ref),
            done_label, {}),
        }),
        Tr.ControlBlock(body_label, loop_params, body),
        Tr.ControlBlock(done_label, {}, { Tr.StmtYieldVoid(Tr.StmtSurface) }),
      })
    local control_domain = domain:parsed_loop_control_domain(input, loop_label)
    return P.ParsedLoopLowered(
      Tr.StmtDomainControl(Tr.StmtSurface, region, control_domain))
  end

  function P.ParsedResolvedLoopRangeND:lower_parsed_loop(input)
    return input.sink:lower_parsed_loop_1d(input, self)
  end
  function P.ParsedResolvedLoopWindowND:lower_parsed_loop(input)
    return input.sink:lower_parsed_loop_1d(input, self)
  end
  function P.ParsedResolvedLoopTiledND:lower_parsed_loop(input)
    return input.sink:lower_parsed_loop_1d(input, self)
  end
  function P.ParsedLoopLowerInput:lower_parsed_loop()
    return self.domain:resolve_parsed_loop_domain():lower_parsed_loop(self)
  end
  function P.ParsedLoopDomainResolved:lower_parsed_loop(input)
    return self.domain:lower_parsed_loop(input)
  end
  function P.ParsedLoopDomainRejected:lower_parsed_loop(_input)
    return P.ParsedLoopLowerRejected(self.reason)
  end
  function P.ParsedLoopLowered:parsed_loop_stmt() return P.ParsedLoopStmtResolved(self.stmt) end
  function P.ParsedLoopLowerRejected:parsed_loop_stmt() return P.ParsedLoopStmtRejected(self.reason) end

  return P.ParsedLoopLowerInput
end

return bind_context
