# Step 7: If/switch phi statements

Enhance `lua/moonlift/mom/back/stmt_lower.mlua` with proper phi-node (SSA join block params) for mutated local cells across branches.

**Policy: Hard rewrite. No backward compat shims. No placeholder code. Every case complete.**

## Problem

When a local is mutated (via `set`) inside if/switch branches, the value after the branch must be selected via phi. In Moonlift's backend, this means:
1. The join block has block params for each changed local
2. Each branch's jump to join passes the current local value
3. After the join block, env entries are rebound to the join block param IDs

## Algorithm (port_map section 11 lines 783-786)

### If statement phi

```
mb_lower_if_stmt(ctx, stmt_idx):
  1. mb_lower_expr(ctx, cond) → (cond_val, cond_scalar, ok)
  
  2. Scan then_body and else_body for locally-mutated bindings (set stmts on local cells).
     Collect set of binding keys that change in either branch.
  
  3. mb_emit_create_block(ctx, then_blk)
     mb_emit_create_block(ctx, else_blk)
     mb_emit_create_block(ctx, join_blk)
  
  4. For each changed binding key:
     mb_ctx_fresh_value(ctx) → phi_val
     mb_emit_append_block_param(ctx, join_blk, phi_val, 0, scalar, 0)
     Save (binding_key, phi_val, scalar) for later env rebind.
  
  5. mb_emit_br_if(ctx, cond_val, then_blk, 0, 0, else_blk, 0, 0)
  
  6. mb_emit_switch_to_block(ctx, then_blk)
     mb_lower_stmt_list(ctx, then_body_start, then_body_count) → (then_flow, then_ok)
     For each changed binding: env_lookup → get current value
     If not terminates: mb_emit_jump(ctx, join_blk, args_aux, count)
  
  7. mb_emit_switch_to_block(ctx, else_blk)
     mb_lower_stmt_list(ctx, else_body_start, else_body_count) → (else_flow, else_ok)
     For each changed binding: env_lookup → get current value
     If not terminates: mb_emit_jump(ctx, join_blk, args_aux, count)
  
  8. mb_emit_seal_block(ctx, join_blk)
     mb_emit_switch_to_block(ctx, join_blk)
  
  9. For each saved (binding_key, phi_val, scalar):
     mb_env_bind_scalar(ctx.env, binding_key, phi_val, scalar)
  
  10. If both branches terminate → return (BackTerminates, ok=true)
      Else → return (BackFallsThrough, ok=true)
```

### Switch statement phi

```
mb_lower_switch_stmt(ctx, stmt_idx):
  1. mb_lower_expr(ctx, value) → (val, scalar, ok)
  
  2. Collect changed bindings across all arms + default.
  
  3. Create arm blocks + default block + join block.
     For each changed binding:
       mb_ctx_fresh_value(ctx) → phi_val
       mb_emit_append_block_param(ctx, join_blk, phi_val, 0, scalar, 0)
  
  4. Extract arm keys from switch arms (switch_key_raw).
     mb_emit_switch_int(ctx, val, scalar, cases_aux, n_cases, default_blk)
  
  5. For each arm:
     mb_emit_switch_to_block(ctx, arm_blk)
     mb_lower_stmt_list(ctx, arm_body) → (flow, ok)
     If not terminates: mb_emit_jump(ctx, join_blk, args)
  
  6. Default arm:
     mb_emit_switch_to_block(ctx, default_blk)
     mb_lower_stmt_list(ctx, default_body) → (flow, ok)
     If not terminates: mb_emit_jump(ctx, join_blk, args)
  
  7. mb_emit_seal_block(ctx, join_blk)
     mb_emit_switch_to_block(ctx, join_blk)
  
  8. For each saved (binding_key, phi_val, scalar):
     mb_env_bind_scalar(ctx.env, binding_key, phi_val, scalar)
  
  9. Return flow as with if.
```

## Binding change detection

`collect_changed_bindings(stmt_list_start, stmt_list_count)`:
- Scan stmts in the list for `ST_SET` where the place is a `PlaceRef(ValueRefBinding)` (local cell set).
- Collect the binding key for each such set.
- Also recurse into nested if/switch bodies to find changes there.
- Return a set (array) of binding keys.

## Env lookup for current values

After lowering a branch body, for each changed binding:
- `mb_env_lookup_into(ctx.env, binding_key, kind_out, value_out, scalar_out)`.
- If `TreeBackScalarLocal` → the current value ID is in `value_out`.
- If `TreeBackStackLocal` → emit load from stack slot to get current value.

## Hard bans

- No raw command packing — use `mb_emit_*` helpers
- No hardcoded 0 aux counts where actual values are needed
- Must use `mb_env_lookup_into` for post-branch value resolution — not tracked state variables
- No assuming branches always fall through — check `BackTerminates` before emitting jump to join
- No `CmdTrap` fallbacks
- No `TODO`/`FIXME`/`placeholder`
