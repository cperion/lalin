# Step 10: Vector integration

Connect the existing `vec/*.mlua` modules to the lowering pipeline. Refactor them to use `MomBackLowerCtx` and `mb_emit_*` helpers, and integrate into function lowering.

**Policy: Hard rewrite. No backward compat shims. No placeholder code. Every function complete.**

## Files to modify

| File | Changes |
|------|---------|
| `vec/vec_facts.mlua` | Refactor to MomBackLowerCtx, use aux_i32 for fact output |
| `vec/vec_decide.mlua` | Refactor to MomBackLowerCtx |
| `vec/vec_plan.mlua` | Refactor to MomBackLowerCtx |
| `vec/vec_lower.mlua` | Refactor to MomBackLowerCtx + mb_emit_* helpers |
| `back/func.mlua` | Add `mb_try_vector_func` two-continuation region |

## Entrypoints (port_map section 17 lines 1050-1054)

```moonlift
mv_extract_vec_facts(ctx: ptr(MomBackLowerCtx))
  -> fact_count: i32, ok: bool

mv_decide(ctx: ptr(MomBackLowerCtx), fact_count: i32)
  -> decision_tag: i32, elem_scalar: i32, lanes: i32  (or reject)

mv_plan_kernel(ctx: ptr(MomBackLowerCtx))
  -> plan_count: i32, ok: bool

mv_lower_kernel(ctx: ptr(MomBackLowerCtx), back_ctx: ptr(MomBackLowerCtx))
  -> status: i32

mb_try_vector_func(ctx: ptr(MomBackLowerCtx), item_idx: i32)
  -> choice: i32 (0=scalar, 1=vectorized)
```

## 1. vec_facts.mlua — Fact extraction

Replace the raw array push with `ctx.aux_i32`:
```moonlift
mv_extract_vec_facts(ctx):
  -- Loop through control facts from control lowering
  -- Find backedge (loop) patterns
  -- Extract induction variable, memory access, reduction facts
  -- Push facts to ctx.aux_i32 as tagged tuples
  -- Return (fact_count, ok=true) or (0, ok=false) if no loop
```

Currently uses raw `vtag/va/vb/vc/vd/ve/vf` arrays + `count ptr` + `cap`. Replace with:
- `ctx.aux_i32` for fact storage
- `mb_ctx_push_aux_i32(ctx, value)` for each fact field
- Return `fact_count` as number of facts pushed

Edge case: no backedge found → return (0, true). Loop pattern not recognized → return (0, true) — don't emit error, just skip vectorization.

## 2. vec_decide.mlua — Legality decision

```moonlift
mv_decide(ctx, fact_count):
  -- Read facts from ctx.aux_i32 (written by mv_extract_vec_facts)
  -- Check target vector width (DEFAULT_VECTOR_BITS = 128)
  -- Compute elem_scalar * lanes fits in target width
  -- Check all memory accesses are contiguous and aligned
  -- Check loop has single induction variable
  -- Return: (VD_LEGAL, elem_scalar, lanes) or (VD_ILLEGAL, reject_reason, 0)
```

Replace raw array reads with `ctx.aux_i32.data[idx]` reads.

Edge: multiple memory streams, non-contiguous access, call inside loop → illegal.
Edge: no reducible operations → reject.

## 3. vec_plan.mlua — Kernel plan

```moonlift
mv_plan_kernel(ctx):
  -- Read decision from aux_i32
  -- Read facts from aux_i32
  -- Produce plan: tag, elem, stop, counter, extra
  -- Push plan to aux_i32
  -- Return (plan_count, ok=true) or (0, ok=false)
```

Plan types (from vec_plan.mlua): VP_NO_PLAN, VP_MAP, VP_REDUCE, VP_ALGEBRAIC_SIMP.
- MAP: element-wise operation, no cross-lane dependency
- REDUCE: horizontal reduction (sum, min, max)
- ALGEBRAIC_SIMP: algebraic simplification of the kernel

## 4. vec_lower.mlua — Kernel lowering

This is the critical one — replaces raw `mv_push_cmd` with `mb_emit_*` helpers:

```moonlift
mv_lower_kernel(ctx, back_ctx):
  -- Read kernel plan from aux_i32
  -- Create vectorized loop blocks:
  --   mb_emit_create_block(back_ctx, entry_blk)
  --   mb_emit_create_block(back_ctx, loop_blk)
  --   mb_emit_create_block(back_ctx, body_blk)
  --   mb_emit_create_block(back_ctx, exit_blk)
  
  -- Entry block: initialize induction variable, jump to loop
  -- Loop block: compare IV against trip count, br_if to body or exit
  -- Body block: load vector, apply vector op, store/reduce, jump to loop
  -- Exit block: continue to scalar remainder or return
  
  -- Use vector emit helpers:
  --   mb_emit_vec_splat(ctx, dst, elem_scalar, lanes, scalar_val)
  --   mb_emit_vec_binary(ctx, dst, op, elem_scalar, lanes, lhs, rhs)
  --   mb_emit_vec_load_info(ctx, dst, elem_scalar, lanes, base, offset, ...)
  --   mb_emit_vec_store_info(ctx, elem_scalar, lanes, base, offset, value, ...)
  --   mb_emit_vec_compare(ctx, dst, op, elem_scalar, lanes, lhs, rhs)
  --   mb_emit_vec_select(ctx, dst, elem_scalar, lanes, cond, then, else)
  --   mb_emit_vec_mask(ctx, dst, op, mask, ...)
  
  -- Return status (0=ok, negative=error)
```

Current vec_lower.mlua uses `mv_push_cmd(raw_tag, raw_slots, ct, ca, ..., count, cap)`.
Replace every call with the corresponding `mb_emit_*` on `back_ctx`.

Edge: remainder loop (when trip count % vector lanes != 0) — lower as scalar loop.
Edge: mask for partial vectors at loop tail — use mb_emit_vec_mask.

## 5. func.mlua — Integration

```moonlift
mb_try_vector_func(ctx, item_idx):
  -- 1. mv_extract_vec_facts(ctx) → (fact_count, ok)
  -- 2. If fact_count == 0 → return 0 (scalar path)
  -- 3. mv_decide(ctx, fact_count) → (decision, elem, lanes)
  -- 4. If decision != VD_LEGAL → return 0 (scalar path)
  -- 5. mv_plan_kernel(ctx) → (plan_count, ok)
  -- 6. If plan_count == 0 → return 0 (scalar path)
  -- 7. mv_lower_kernel(ctx, ctx) → status
  -- 8. If status == 0 → return 1 (vectorized path)
  -- 9. Else → return 0 (scalar fallback)
```

Called from `mb_lower_func`:
```
mb_lower_func(ctx, item_idx):
  1. If item has loop body:
     let vec_choice = mb_try_vector_func(ctx, item_idx)
     if vec_choice == 1 → return (vectorized)
  2. Else: proceed with scalar lowering (existing algorithm)
```

## Hard bans

- No raw command packing — vec_lower must use mb_emit_vec_* helpers exclusively
- No LowerState — only MomBackLowerCtx
- No CmdTrap fallbacks
- No TODO/FIXME/placeholder
- Vector emit helpers must exist in cmd.mlua before vec_lower uses them (from step 2)
- Vectorization failure must not prevent scalar lowering — it's a try/fallback, not required
- All vector operations must specify elem_scalar + lanes (shape_tag = 1 = BackShapeVec)
