-- lalin.syntax_v2.for_to_loop
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
  local function cast_idx(expr)
    return Tr.ExprCast(Tr.ExprSurface, C.SurfaceCast, idx_ty, expr)
  end
  local function bin(op, lhs, rhs)
    return Tr.ExprBinary(Tr.ExprSurface, op, lhs, rhs)
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
  function P.ParsedLoopInteger:parsed_loop_integer_value(_site) return self.value end
  function P.ParsedLoopIntegerRejected:parsed_loop_integer_value(site)
    error(tostring(site) .. ": " .. self.reason, 2)
  end

  function P.ParsedLoopAxis:resolve_parsed_loop_axis()
    local step = self.step:parsed_loop_integer():parsed_loop_integer_value("loop step")
    if step == 0 then error("loop step must be nonzero", 2) end
    if step < 0 then error("backward parsed loops are not implemented", 2) end
    return P.ParsedResolvedLoopAxis(
      self.start, self.stop, step, Tr.ControlLoopForward, idx_ty)
  end
  function P.ParsedWindowAxis:resolve_parsed_window_axis()
    local before = self.before:parsed_loop_integer():parsed_loop_integer_value("window before")
    local after = self.after:parsed_loop_integer():parsed_loop_integer_value("window after")
    if before < 0 or after < 0 then error("window extents must be nonnegative", 2) end
    return P.ParsedResolvedWindowAxis(before, after, self.boundary)
  end

  local function resolve_axes(axes)
    local out = {}
    for i = 1, #axes do out[i] = axes[i]:resolve_parsed_loop_axis() end
    return out
  end
  function P.ParsedLoopRangeND:resolve_parsed_loop_domain()
    return P.ParsedResolvedLoopRangeND(resolve_axes(self.axes))
  end
  function P.ParsedLoopWindowND:resolve_parsed_loop_domain()
    if #self.axes ~= #self.windows then error("window domain axis/window arity mismatch", 2) end
    local windows = {}
    for i = 1, #self.windows do windows[i] = self.windows[i]:resolve_parsed_window_axis() end
    return P.ParsedResolvedLoopWindowND(resolve_axes(self.axes), windows)
  end
  function P.ParsedLoopTiledND:resolve_parsed_loop_domain()
    local tiles = {}
    for i = 1, #self.tile_sizes do
      tiles[i] = self.tile_sizes[i]:parsed_loop_integer():parsed_loop_integer_value("tile size")
      if tiles[i] <= 0 then error("tile sizes must be positive", 2) end
    end
    return P.ParsedResolvedLoopTiledND(resolve_axes(self.axes), tiles)
  end

  local lower_1d_no_sink
  function P.ParsedResolvedLoopSink:lower_parsed_loop_1d(_input, _domain)
    return P.ParsedLoopLowerRejected(
      "fold/scan lowering is not implemented on the schema-v2 parsed path")
  end
  function P.ParsedResolvedLoopNoSink:lower_parsed_loop_1d(input, domain)
    return lower_1d_no_sink(input, domain)
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
      axes[i] = Tr.ControlLoopAxis(input.indexes[i], domain.axes[i].index_ty,
        1, 3, 4, domain.axes[i].step, domain.axes[i].order)
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

  lower_1d_no_sink = function(input, domain)
    if #domain.axes ~= 1 or #input.indexes ~= 1 then
      return P.ParsedLoopLowerRejected("schema-v2 parsed lowering currently supports one loop axis")
    end
    local axis = domain.axes[1]
    local start_literal = axis.start:parsed_loop_integer():parsed_loop_integer_value("loop start")
    if start_literal ~= 0 or axis.step ~= 1 then
      return P.ParsedLoopLowerRejected(
        "schema-v2 parsed lowering currently requires a zero-based unit-stride loop")
    end

    local tag = input.loop_id
    local flat_name = "__lln_flat_" .. tag
    local start_name = "__lln_axis_start_" .. tag
    local stop_name = "__lln_axis_stop_" .. tag
    local trip_name = "__lln_axis_trip_" .. tag
    local index_name = input.indexes[1]
    local entry_label = Tr.BlockLabel("lln_entry_" .. tag)
    local loop_label = Tr.BlockLabel("lln_loop_" .. tag)
    local body_label = Tr.BlockLabel("lln_body_" .. tag)
    local done_label = Tr.BlockLabel("lln_done_" .. tag)

    local flat_ref = ref(flat_name)
    local start_init, stop_init = cast_idx(axis.start), cast_idx(axis.stop)
    local trip_init = bin(C.BinSub, stop_init, start_init)
    local loop_params = {
      Tr.BlockParam(flat_name, idx_ty),
      Tr.BlockParam(start_name, idx_ty),
      Tr.BlockParam(stop_name, idx_ty),
      Tr.BlockParam(trip_name, idx_ty),
    }
    local function jump_args(flat)
      return {
        Tr.JumpArg(flat_name, flat),
        Tr.JumpArg(start_name, ref(start_name)),
        Tr.JumpArg(stop_name, ref(stop_name)),
        Tr.JumpArg(trip_name, ref(trip_name)),
      }
    end
    local entry_args = {
      Tr.JumpArg(flat_name, cast_idx(lit(0))),
      Tr.JumpArg(start_name, start_init),
      Tr.JumpArg(stop_name, stop_init),
      Tr.JumpArg(trip_name, trip_init),
    }
    local rewrite = P.ParsedLoopIndexRewriteInput(index_name, flat_ref)
    local body = {}
    for i = 1, #input.body do body[i] = input.body[i]:parsed_loop_rewrite_index(rewrite) end
    body[#body + 1] = Tr.StmtJump(Tr.StmtSurface, loop_label,
      jump_args(bin(C.BinAdd, flat_ref, cast_idx(lit(1)))))
    local condition = Tr.ExprCompare(Tr.ExprSurface, C.CmpLt, flat_ref, ref(stop_name))
    local region = Tr.ControlStmtRegion(tag,
      Tr.EntryControlBlock(entry_label, {}, {
        Tr.StmtJump(Tr.StmtSurface, loop_label, entry_args),
      }), {
        Tr.ControlBlock(loop_label, loop_params, {
          Tr.StmtIf(Tr.StmtSurface, condition, {
            Tr.StmtJump(Tr.StmtSurface, body_label, jump_args(flat_ref)),
          }, {}),
          Tr.StmtJump(Tr.StmtSurface, done_label, {}),
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
  function P.ParsedResolvedLoopTiledND:lower_parsed_loop(_input)
    return P.ParsedLoopLowerRejected("schema-v2 parsed tiled lowering is not implemented")
  end
  function P.ParsedLoopLowerInput:lower_parsed_loop()
    return self.domain:resolve_parsed_loop_domain():lower_parsed_loop(self)
  end
  function P.ParsedLoopLowered:parsed_loop_stmt() return self.stmt end
  function P.ParsedLoopLowerRejected:parsed_loop_stmt() error(self.reason, 2) end

  return P.ParsedLoopLowerInput
end

return bind_context
