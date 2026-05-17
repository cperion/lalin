# Step 9: Memory, atomic, globals, view return, export wrappers

Complete the remaining command families across all lowerer files. This is an **integration pass** that wires up atomic ops, global data commands, view return ABI (sret), and host export wrappers.

**Policy: Hard rewrite. No backward compat shims. No placeholder code. Every case complete.**

## Files to modify

| File | Changes |
|------|---------|
| `back/expr_lower.mlua` | Complete EX_ATOMIC_LOAD, EX_ATOMIC_RMW, EX_ATOMIC_CAS |
| `back/stmt_lower.mlua` | Complete ST_ATOMIC_STORE, ST_ATOMIC_FENCE; view return sret |
| `back/address.mlua` | Add `mb_descriptor_field_load` for view ABI |
| `back/func.mlua` | Add `mb_lower_host_export_wrapper` |
| `back/module.mlua` | Complete global data init, const/static commands |

## 1. Atomic expressions (expr_lower.mlua)

### ExprAtomicLoad (hosted lines 865-876)
```
expr_tag == EX_ATOMIC_LOAD:
  1. mb_lower_expr(ctx, addr_expr) → (addr_val, scalar, ok1)
  2. mb_emit_const(ctx, zero, BackIndex, BackLitInt(0), 0, 0)  -- zero offset
  3. mb_ctx_fresh_value(ctx) → dst
  4. mb_emit_atomic_load(ctx, dst, scalar, addr_val, zero, memory_info_read, atomic_seq_cst)
  5. Return (dst, scalar, ok=true)
```
Edge: non-scalar result → unsupported. Only AtomicSeqCst ordering (hosted simplification).

### ExprAtomicRmw (hosted lines 877-890)
```
expr_tag == EX_ATOMIC_RMW:
  1. mb_lower_expr(ctx, addr_expr) → (addr_val, scalar, ok1)
  2. mb_lower_expr(ctx, value_expr) → (val, val_scalar, ok2)
  3. mb_emit_const(ctx, zero, BackIndex, BackLitInt(0), 0, 0)
  4. mb_ctx_fresh_value(ctx) → dst
  5. rmw_op = mb_lower_atomic_rmw_op(tree.expr_subtag[idx])  -- Add/Sub/And/Or/Xor/Xchg
  6. mb_emit_atomic_rmw(ctx, dst, rmw_op, scalar, addr_val, zero, val, memory_info_readwrite, atomic_seq_cst)
  7. Return (dst, scalar, ok=true)
```
Edge: unsupported rmw ops (Min, Max) → unsupported.

### ExprAtomicCas (hosted lines 891-904)
```
expr_tag == EX_ATOMIC_CAS:
  1. mb_lower_expr(ctx, addr_expr) → (addr_val, scalar, ok1)
  2. mb_lower_expr(ctx, expected_expr) → (expected_val, exp_scalar, ok2)
  3. mb_lower_expr(ctx, replacement_expr) → (replacement_val, rep_scalar, ok3)
  4. mb_emit_const(ctx, zero, BackIndex, BackLitInt(0), 0, 0)
  5. mb_ctx_fresh_value(ctx) → dst
  6. mb_emit_atomic_cas(ctx, dst, scalar, addr_val, zero, expected_val, replacement_val, memory_info_readwrite, atomic_seq_cst)
  7. Return (dst, scalar, ok=true)
```

## 2. Atomic statements (stmt_lower.mlua)

### StmtAtomicStore (hosted line 1556-1568)
```
stmt_tag == ST_ATOMIC_STORE:
  1. mb_lower_expr(ctx, addr_expr) → (addr_val, scalar, ok1)
  2. mb_lower_expr(ctx, value_expr) → (val, val_scalar, ok2)
  3. mb_emit_const(ctx, zero, BackIndex, BackLitInt(0), 0, 0)
  4. mb_emit_atomic_store(ctx, scalar, addr_val, zero, val, memory_info_write, atomic_seq_cst)
  5. Return (BackFallsThrough, ok=true)
```

### StmtAtomicFence (hosted line 1569-1577)
```
stmt_tag == ST_ATOMIC_FENCE:
  1. ordering = atomic_seq_Cst (only seq_cst supported)
  2. mb_emit_atomic_fence(ctx, ordering)
  3. Return (BackFallsThrough, ok=true)
```

## 3. View return ABI (stmt_lower.mlua + address.mlua)

### StmtReturnValue for views (hosted lines 1511-1527)
When the expr_ty is a view type (is_view_type):
```
1. mb_lower_expr(ctx, value) → view result with data/len/stride
   OR if the expr is a view local → env_lookup → get data/len/stride IDs
2. mb_emit_store_info(ctx, 0, BackPtr, 0, out_ptr, 0, view_data, access_write, ...)  -- data at offset 0
3. Compute len_addr = out_ptr + 8 via mb_emit_ptr_offset
4. mb_emit_store_info(ctx, 0, BackIndex, 0, len_addr, 0, view_len, access_write, ...)  -- len at offset 8
5. Compute stride_addr = out_ptr + 16 via mb_emit_ptr_offset
6. mb_emit_store_info(ctx, 0, BackIndex, 0, stride_addr, 0, view_stride, access_write, ...)  -- stride at offset 16
7. mb_emit_return_void(ctx)  -- real return is through hidden pointer
```

### mb_descriptor_field_load (address.mlua)
Helper for host export wrapper — loads a field from a view descriptor pointer:
```moonlift
mb_descriptor_field_load(ctx, desc_ptr, field_offset, field_scalar) -> value: i32
  1. mb_ctx_fresh_value(ctx) → dst
  2. mb_emit_load_info(ctx, dst, 0, field_scalar, 0, desc_ptr, field_offset, ...)
  3. Return dst
```

## 4. Host export wrapper (func.mlua)

### mb_lower_host_export_wrapper (hosted lines 1701+)
For every public/exported function with TView params or TView result:
```
mb_lower_host_export_wrapper(ctx, public_item_idx, inner_func_id):
  1. Get function sig from item: has TView params or result?
  2. Create public sig using host ABI (BackPtr for each view param, BackPtr for view result)
  3. mb_emit_create_sig(ctx, public_sig, host_params_aux, n_host_params, host_results_aux, n_host_results)
  4. mb_emit_declare_func(ctx, public, public_func_id, public_sig)
  5. mb_emit_begin_func(ctx, public_func_id)
  
  6. For each TView param:
     Load data at desc_ptr+0  → mb_descriptor_field_load
     Load len at desc_ptr+8   → mb_descriptor_field_load
     Load stride at desc_ptr+16 → mb_descriptor_field_load
     Bind as strided view local in env
  
  7. If TView result:
     Hidden output ptr is first arg (added by host ABI)
     Store it in ctx.env as sret return target
  
  8. Build call to inner function:
     mb_emit_call(ctx, value, public_func_id, public_sig, args_aux, count)
     (Or for void inner: emit call then return void)
  
  9. If TView result: mb_emit_return_void(ctx)
     Else: mb_emit_return_value(ctx, call_result)
  
  10. mb_emit_finish_func(ctx, public_func_id)
```

## 5. Global data init, const/static commands (module.mlua)

Enhance `mb_lower_module` to emit data commands:

### Data init for const/static items
```
For each const item in module:
  1. back_scalar(item.ty) → scalar, size, align
  2. const_eval(item.value) → Sem.Const*
  3. sem_const_literal(value) → BackLit*(lit_tag, lit_lo, lit_hi)
  4. mb_emit_declare_data(ctx, data_id, size, align)
  5. mb_emit_data_init(ctx, data_id, 0, scalar, lit_tag, lit_lo, lit_hi)

For each static item:
  1. back_scalar(item.ty) → scalar, size, align
  2. mb_emit_declare_data(ctx, data_id, size, align)
  3. mb_emit_data_init_zero(ctx, data_id, 0, size)  -- zero-initialized
```

### Global context wiring
```
mb_collect_module_context(ctx):
  Walk all items:
    const items → back_scalar + const_eval → store in ctx env
    static items → collect data_id → store in ctx globals map
    func items → collect module+item name → func_id mapping
    slot items → collect slot_consts/slot_statics maps
```

### Hoisting order (port_map section 13 lines 915-923)
```
Module command order:
  1. mb_emit_target_model(ctx, triple, data_layout)  -- if applicable
  2. mb_emit_create_sig for all func/extern sigs (deduplicated)
  3. mb_emit_declare_func / mb_emit_declare_extern for all items
  4. mb_emit_declare_data for all const/static items
  5. Function bodies in item order
  6. mb_emit_alias_fact for global aliasing info
  7. mb_emit_finalize_module(ctx)
```

## Hard bans

- No raw command packing — all via mb_emit_* helpers (including mb_emit_atomic_*, mb_emit_data_addr, mb_emit_declare_data, mb_emit_data_init)
- No LowerState — only MomBackLowerCtx
- No CmdTrap fallbacks
- No TODO/FIXME/placeholder
- View sret must write data/len/stride at correct offsets (0, 8, 16)
- Atomic ordering is always SeqCst (hosted simplification — no other orderings mapped)
- Every atomic RMW must have the correct op mapping (use mb_lower_atomic_rmw_op)
