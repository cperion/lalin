# Step 6: Address/view/store module

Create `lua/moonlift/mom/back/address.mlua` — address, view, and store lowering.

**Policy: Hard rewrite. No backward compat shims. No placeholder code. Every function complete.**

## Pattern
```moonlift
return function(M)
  -- imports from cmd.mlua, ops.mlua, env.mlua, ids.mlua
  -- region/func helpers for address, view, store
  return M
end
```

## Entrypoints (port_map section 10 lines 702-708)

```moonlift
mb_view_to_back(ctx: ptr(MomBackLowerCtx), view_idx: i32)
  -> data: i32, len: i32, stride: i32, elem_scalar: i32, ok: bool

mb_index_addr_to_back(ctx: ptr(MomBackLowerCtx), base_idx: i32, index_expr: i32, elem_type: i32)
  -> addr: i32, elem_scalar: i32, ok: bool

mb_place_addr_to_back(ctx: ptr(MomBackLowerCtx), place_idx: i32)
  -> addr: i32, pointee_scalar: i32, ok: bool

mb_place_store_to_back(ctx: ptr(MomBackLowerCtx), place_idx: i32, value_expr: i32)
  -> flow: i32, ok: bool

mb_memory_info(ctx, access, align_kind, align_bytes, deref_kind, deref_bytes, trap_kind, motion_kind, mode_kind)
  -> packed memory info (used by load/store emit helpers)

mb_address_from_ptr(ctx, ptr_value, offset_value)
  -> address descriptor (used by load/store emit helpers)
```

## View lowering (port_map section 10 lines 715-720)

`mb_view_to_back` dispatches on view variant from tree:

- **ViewFromExpr**: Lower the base expression. `mb_emit_ptr_offset(ctx, data, base_tag, base_id, byte_offset, elem_size, offset_lo, offset_hi)`. Return (data, len, stride, elem_scalar, ok=true).
- **ViewContiguous**: shape_compute(elem_type, count). `mb_emit_view(ctx, shape, data, len, stride)`. Return protocol.
- **ViewStrided**: shape_compute + explicit stride from tree.view_stride. Return protocol.
- **ViewWindow**: base = `mb_view_to_back(ctx, base_view)`. Compute offset from window.start and window.len. Build sub-view via ptr_offset. Return protocol.
- **ViewRestrided/RowBase/Interleaved/InterleavedView**: unsupported (hosted reports unsupported). Return ok=false.
- Edge: ViewFromExpr where base is a view local → get data/len/stride from env lookup instead of lowering expr.

## Address lowering (port_map section 10 lines 722-728)

`mb_place_addr_to_back` dispatches on place variant:

- **PlaceRef(ValueRefBinding)**: `mb_env_lookup_into(ctx.env, binding_key, kind_out, value_out, scalar_out)`.
  - `TreeBackStackLocal` → `mb_emit_stack_addr(ctx, dst, slot)`. Return (addr, scalar, ok=true).
  - `TreeBackScalarLocal` → unsupported (already a value, not addressable).
  - Global static/const → data address via `mb_emit_data_addr(ctx, dst, data_id)`.
- **PlaceDeref**: `mb_lower_expr(ctx, base)` → returns pointer value directly. Return (value, scalar, ok=true).
- **PlaceIndex**: 
  - `IndexBaseExpr` → `mb_lower_expr(ctx, base)` + index * elem_size → `mb_emit_ptr_offset`.
  - `IndexBasePlace` → `mb_place_addr_to_back(ctx, base)` + index * elem_size → `mb_emit_ptr_offset`.
  - `IndexBaseView` → `mb_view_to_back(ctx, base_view)` + index * stride → `mb_emit_ptr_offset`.
- **PlaceField(FieldByOffset)**: `mb_place_addr_to_back(ctx, base)` + field_offset → `mb_emit_ptr_offset(ctx, dst, base_tag, base_id, field_offset, elem_size, 0, 0)`.
- Edge: slices require bounds check (`mb_emit_compare(ctx, ...)` + `mb_emit_br_if(ctx, ...)`) before ptr offset.
- **PlaceDot**, **PlaceSlotValue**: unsupported.

## Store lowering (port_map section 10 lines 729-733)

`mb_place_store_to_back`:

1. `mb_place_addr_to_back(ctx, place)` → (addr, pointee_scalar, ok1).
2. `mb_lower_expr(ctx, value_expr)` → (val, val_scalar, ok2).
3. If `field_is_stored_bool` → `mb_emit_compare(ctx, cmp_dst, IcmpNe, 0, scalar, 0, val, zero)` + `mb_emit_select(ctx, sel_dst, 0, scalar, 0, cmp_dst, one, zero)` to produce 0/1 storage byte.
4. `mb_emit_store_info(ctx, 0 (shape_scalar), pointee_scalar, 0 (lanes), base_tag, base_id, byte_offset, val, access_write, align_k, align_b, deref_k, deref_b, trap_k, motion_k, mode_k)`.
5. Return (BackFallsThrough, ok=true).
6. Local cell SSA rebind: `mb_env_bind_scalar(ctx.env, binding, new_value, scalar)` — no store command needed.

## Memory info helpers

`mb_memory_info(access, align_kind, align_bytes, deref_kind, deref_bytes, trap_kind, motion_k, mode_k)`:
- Returns packed i32 that load/store emit helpers expand into CmdLoadInfo/CmdStoreInfo slots.
- Default: Read access, align_kind=known, align_bytes=4, deref_kind=default, deref_bytes=4, trap_kind=no_trap, motion_kind=nonvolatile, mode_kind=normal.

`mb_address_from_ptr(ctx, ptr_value, offset_value)`:
- Returns base_tag (0=BackAddrValue) + base_id (ptr_value) for use in load/store.
- Offset_value is typically a const 0 or computed byte offset.

## Hard bans

- No raw command packing — use `mb_emit_ptr_offset`, `mb_emit_stack_addr`, `mb_emit_load_info`, `mb_emit_store_info`, `mb_emit_compare`, `mb_emit_select`, `mb_emit_const`
- No `LowerState` — only `MomBackLowerCtx`
- No `CmdTrap` fallbacks
- No `TODO`/`FIXME`/`placeholder`
- View window arithmetic must compute correct byte offset from start*elem_size, not hardcoded
