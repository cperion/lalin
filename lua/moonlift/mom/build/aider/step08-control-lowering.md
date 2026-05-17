# Step 8: Control region lowering

Create `lua/moonlift/mom/back/control_lower.mlua` — lowers control regions (block/jump/yield) to backend blocks and jumps.

Modify `lua/moonlift/mom/back/control.mlua` to export control facts needed by the lowerer.

**Policy: Hard rewrite. No backward compat shims. No placeholder code. Every function complete.**

## control.mlua changes

Add to `lua/moonlift/mom/back/control.mlua`:

```moonlift
mb_control_extract_facts(ctx: ptr(MomBackLowerCtx), region_idx: i32)
  -> labels_aux: i32, n_labels: i32, block_records_aux: i32, n_blocks: i32
  -- extract labels, blocks, entry/exit info from tree region data
  -- store aux arrays in ctx.aux_i32 for consumption by lowerer

mb_control_param_specs(ctx: ptr(MomBackLowerCtx), region_idx: i32)
  -> record_start: i32, count: i32, ok: bool
  -- extract entry/block param specs: names and types for each
```

## control_lower.mlua

```moonlift
return function(M)
  -- imports from cmd.mlua, env.mlua, expr_lower.mlua, stmt_lower.mlua, control.mlua
  return M
end
```

### Entrypoints (port_map section 12 lines 816-822)

```moonlift
mb_lower_control_region(ctx: ptr(MomBackLowerCtx), region_idx: i32, result_scalar: i32)
  -> value: i32, flow: i32, ok: bool

mb_control_stmt_to_back(ctx: ptr(MomBackLowerCtx), stmt_idx: i32)
  -> flow: i32, ok: bool

mb_control_jump_args(ctx: ptr(MomBackLowerCtx), stmt_idx: i32, target_record: i32)
  -> aux: i32, count: i32, ok: bool

mb_control_lower_entry_jump(ctx: ptr(MomBackLowerCtx), record_idx: i32)
  -> ok: bool
```

### Control lowering algorithm (port_map section 12 lines 824-833)

```
mb_lower_control_region(ctx, region_idx, result_scalar):
  1. mb_control_extract_facts(ctx, region_idx) → facts arrays
     Labels: region has named blocks with param specs
     Entry: which block is the entry point
     Exit: which yield/return terminates the region
     Jumps: stmt indices with target block names
  
  2. Create Block records in backend:
     For the entry block and each named block:
       mb_emit_create_block(ctx, blk_id)
     Save block_id → backend_blk mapping
  
  3. Lower entry jump:
     For each entry block param:
       mb_lower_expr(ctx, initializer_expr) → (init_val, scalar, ok)
       Push init_val to entry_args_aux via mb_ctx_push_aux_i32
     mb_emit_jump(ctx, entry_blk, entry_args_aux, n_entry_args)
  
  4. For each block in order (depth-first or linear):
     mb_emit_switch_to_block(ctx, blk_id)
     
     For each block param:
       mb_ctx_fresh_value(ctx) → param_val
       mb_emit_append_block_param(ctx, blk_id, param_val, 0, scalar, 0)
       mb_env_bind_scalar(ctx.env, binding_key, param_val, scalar)
     
     mb_control_stmt_to_back(ctx, body_stmt_idx) → (flow, ok)
     
     (flow should be BackTerminates — each block must end in jump/yield/return)
  
  5. Jump statements inside block body:
     mb_control_jump_args(ctx, stmt_idx, target_record) → (aux, count, ok)
     For each arg: look up binding in env → get current value
     Push to jump_args_aux
     mb_emit_jump(ctx, target_blk, jump_args_aux, count)
  
  6. Yield statements:
     If yield value: mb_lower_expr(ctx, yield_expr) → (val, scalar, ok)
       mb_emit_return_value(ctx, val)
     If yield void: mb_emit_return_void(ctx)
  
  7. Expression regions:
     After terminal yield, create exit block:
       mb_emit_create_block(ctx, exit_blk)
       mb_ctx_fresh_value(ctx) → result_val
       mb_emit_append_block_param(ctx, exit_blk, result_val, 0, result_scalar, 0)
       (The yield becomes a jump to exit_blk, or the yield's return is the exit)
     Return (result_val, BackTerminates, ok=true)
  
  8. All blocks sealed after lowering:
     mb_emit_seal_block(ctx, each_block_id)
```

### Control stmt dispatcher (port_map section 12 lines 834-838)

```
mb_control_stmt_to_back(ctx, stmt_idx):
  dispatch on tree.stmt_tag[stmt_idx]:
    ST_JUMP → mb_control_jump_to_back(ctx, stmt_idx)
      → lookup target block, collect args, mb_emit_jump
    ST_JUMPCONT → same as jump (continuation is resolved by typecheck to block name)
    ST_YIELDVOID → mb_emit_return_void(ctx)
    ST_YIELDVALUE → mb_lower_expr(ctx, yield_expr), mb_emit_return_value
    ST_IF → delegate to mb_lower_if_stmt (reuses if lowering but inside region)
    ST_SWITCH → delegate to mb_lower_switch_stmt (reuses switch lowering)
    ST_LET → delegate to mb_stmt_let lowering
    ST_VAR → delegate to mb_stmt_var lowering
    ST_SET → delegate to place_store_to_back
    ST_EXPR → delegate to mb_stmt_expr lowering
    ST_RETURN → delegate to mb_stmt_return lowering
    ST_ASSERT → no-op
    ST_ATOMIC* → delegate to atomic lowering
    else → unsupported
```

### Jump args collection

```
mb_control_jump_args(ctx, stmt_idx, target_record):
  For each param of the target block:
    Find the jump stmt's arg expression at this position
    If arg is ExprRef → env_lookup → get current value
    If arg is ExprLit → mb_lower_expr → get value
    Push to ctx.aux_i32
  Return (aux_start_idx, count, ok=true)
```

### Entry jump lowering

```
mb_control_lower_entry_jump(ctx, record_idx):
  Get entry block's param specs from facts
  For each param: mb_lower_expr(ctx, initializer) → (val, scalar, ok)
  Push each val to aux
  mb_emit_jump(ctx, entry_blk, aux_start, count)
```

## Control validation rules (port_map section 12 lines 840-848)

The lowerer must validate or at least not silently produce invalid CFG:
- No duplicate labels (already caught by typecheck)
- No missing labels (jump target must exist in block map)
- Jump arg count must match block param count
- Yield type must match region result type
- Every path through region must terminate
- Yield only in yield-mode regions (not 'none' mode)

## Hard bans

- No raw command packing — use mb_emit_create_block, mb_emit_switch_to_block, mb_emit_append_block_param, mb_emit_jump, mb_emit_return_*, mb_emit_seal_block
- No LowerState — only MomBackLowerCtx
- No CmdTrap fallbacks
- No TODO/FIXME/placeholder
- Block params are real typed values — no fake continuation args
- Every block must be sealed after its body lowers
- Entry block initializers are lowered before the entry jump, not inside the block
