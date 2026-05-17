# back_lower.mlua Implementation Guide

## Overview

`back_lower.mlua` implements the Tree IR → Backend IR lowering as **region-based dispatchers** with **continuation protocol**. This guide explains the architecture and provides templates for implementing the remaining 21 expression cases.

## Key Architecture

### 1. Region Pattern (from expr_lower.mlua)

All lowering regions follow this pattern:

```mlua
region name(params; done: cont(...), other_cont: cont(...))
entry start(st: ptr(@{LowerState}), cmds: ptr(i32))
    -- Entry logic, may emit child regions
    emit other_cont(st = st, cmds = cmds, child_val = ?)
end
block continuation_name(st1: ptr(@{LowerState}), cmds1: ptr(i32), child_val: i32)
    -- Use result from child
    jump done(st = st1, cmds = cmds1, value = result)
end
end
```

**Key points:**
- `entry start()` is the entry block
- `emit` calls child regions with a continuation
- Blocks receive updated state from child regions
- `jump done()` invokes the final continuation

### 2. Continuation Protocol

Continuations are **typed callbacks** that receive:
1. Updated `st: ptr(LowerState)` (with incremented cmd_count, next_value, etc.)
2. Updated `cmds: ptr(i32)` (same buffer, advanced state)
3. Result values (e.g., `value: i32` for expressions)

Example:
```mlua
done: cont(st: ptr(@{LowerState}), cmds: ptr(i32), value: i32)
-- Called as: jump done(st = st, cmds = cmds, value = result)
```

### 3. Threading State Through Blocks

When a region needs multiple child results (e.g., binary operators need left and right), use **intermediate blocks** to accumulate results:

```mlua
-- Binary operator: need left_val and right_val
entry start(st, cmds)
    emit lower_left(st = st, cmds = cmds, ...)  -- Calls continuation: got_left
end
block got_left(st1, cmds1, left_val)
    -- st1, cmds1 are updated after left evaluation
    emit lower_right(st = st1, cmds = cmds1, ...)  -- Continuation: got_right
end
block got_right(st2, cmds2, right_val)
    -- st2, cmds2 are updated after right evaluation
    -- NOW we have both left_val and right_val
    -- (Note: left_val from got_left block is in scope)
    -- Emit binary command and jump to done
end
```

**CRITICAL:** Block parameters shadow previous values. For binary ops, left_val is **still in scope** in got_right block as closure variable.

## Currently Implemented Cases (3 Working Templates)

### Case 1: ExprLit (Literal)

**Input:** Token kind (TK_INT, TK_FLOAT, TK_TRUE, TK_FALSE, TK_NIL)

**Output:** Fresh value with CmdConst

**Pattern (lines 208-217):**
```mlua
local mb_lower_lit_region = region(tok_kind: i32;
    done: cont(st: ptr(@{LowerState}), cmds: ptr(i32), value: i32))
entry start(st, cmds)
    let dst: i32 = mb_fresh_val(st)  -- Allocate fresh value
    let scalar: i32 = select(...)     -- Map token to BackBool/BackF64/BackPtr/BackI32
    mb_push_cmd(@{T.CmdConst}, dst, scalar, tok_kind, 0, 0, 0, st, cmds)
    jump done(st = st, cmds = cmds, value = dst)
end
end
```

### Case 2: ExprRef (Reference/Lookup)

**Input:** (none, lookup from environment)

**Output:** Fresh value (currently stub: CmdTrap)

**Pattern (lines 220-226):**
- env_lookup(env, binding_id) returns LocalEntry if found
- For now: CmdTrap (needs integration with environment)

### Case 3: ExprUnary (Unary Operation)

**Input:** expr_op (TK_MINUS, TK_NOT, TK_TILDE), scalar type, child expression

**Output:** Fresh value with CmdUnary(child_val, unary_op, ...)

**Pattern (lines 231-247):**
```mlua
local mb_lower_unary_region = region(expr_op: i32, scalar: i32;
    done: cont(...),
    lower_child: cont(..., child_val: i32) -> void)
entry start(st, cmds)
    emit lower_child(st = st, cmds = cmds, child_val = ?)
end
block with_child(st1, cmds1, child_val)
    let dst: i32 = mb_fresh_val(st1)
    let unary_op: i32 = mb_token_to_unary_op(expr_op)
    let back_op: i32 = select(...)  -- Map to BackUnaryIneg/BackUnaryFneg/BackUnaryBoolNot/BackUnaryBnot
    mb_push_cmd(@{T.CmdUnary}, dst, back_op, 1, scalar, child_val, 0, st1, cmds1)
    jump done(st = st1, cmds = cmds1, value = dst)
end
end
```

**Key insight:** The `lower_child` continuation is passed to parent region. Parent region emits child, and we receive result in `with_child` block.

### Case 4: ExprBinary (Binary Operation)

**Input:** expr_op (TK_PLUS, TK_MINUS, etc.), scalar type, left expr, right expr

**Output:** Fresh value with CmdIntBinary/CmdFloatBinary/CmdBitBinary/CmdShift

**Pattern (lines 252-312):**
```mlua
local mb_lower_binary_region = region(expr_op: i32, scalar: i32;
    done: cont(...),
    lower_children: cont(..., left_val: i32, right_val: i32) -> void)
entry start(st, cmds)
    emit lower_children(st = st, cmds = cmds, left_val = ?, right_val = ?)
end
block with_children(st1, cmds1, left_val, right_val)
    let dst: i32 = mb_fresh_val(st1)
    let is_float: bool = mb_is_float_scalar(scalar)
    if expr_op == @{T.TK_PLUS} then
        if is_float then
            mb_push_cmd(@{T.CmdFloatBinary}, dst, @{T.BackFloatAdd}, scalar, 1, left_val, right_val, st1, cmds1)
        else
            mb_push_cmd(@{T.CmdIntBinary}, dst, @{T.BackIntAdd}, scalar, 65537, left_val, right_val, st1, cmds1)
        end
    ... handle other ops ...
    end
    jump done(st = st1, cmds = cmds1, value = dst)
end
end
```

**Key:** Continuation receives BOTH left_val and right_val simultaneously (unlike recursive block pattern).

## Template for Remaining 21 Cases

### ExprCompare (Compare Operations)

**Similar to binary:** emit CmdCompare with lhs_val, rhs_val, cmp_op.

```mlua
local mb_lower_compare_region = region(cmp_op: i32, scalar: i32;
    done: cont(st: ptr(@{LowerState}), cmds: ptr(i32), value: i32),
    lower_children: cont(st: ptr(@{LowerState}), cmds: ptr(i32), lhs_val: i32, rhs_val: i32) -> void)
entry start(st, cmds)
    emit lower_children(st = st, cmds = cmds, lhs_val = ?, rhs_val = ?)
end
block with_children(st1, cmds1, lhs_val, rhs_val)
    let dst: i32 = mb_fresh_val(st1)
    let back_cmp: i32 = mb_token_to_cmp_op(cmp_op)  -- Map to CmpEq/CmpNe/CmpLt/CmpLe/CmpGt/CmpGe
    mb_push_cmd(@{T.CmdCompare}, dst, back_cmp, scalar, lhs_val, rhs_val, 0, st1, cmds1)
    jump done(st = st1, cmds = cmds1, value = dst)
end
end
```

### ExprCast (Type Cast)

**Input:** cast_op (MC_IDENTITY, MC_SEXTEND, etc.), src_scalar, dst_scalar, child expr

**Output:** Fresh value with CmdCast (or passthrough if identity)

```mlua
local mb_lower_cast_region = region(cast_op: i32, src_scalar: i32, dst_scalar: i32;
    done: cont(...),
    lower_child: cont(..., child_val: i32) -> void)
entry start(st, cmds)
    if cast_op == @{T.MC_IDENTITY} then
        -- Passthrough: just return child value directly
        emit lower_child(st = st, cmds = cmds, child_val = ?)
    else
        emit lower_child(st = st, cmds = cmds, child_val = ?)
    end
end
block with_child_identity(st1, cmds1, child_val)
    jump done(st = st1, cmds = cmds1, value = child_val)
end
block with_child_cast(st1, cmds1, child_val)
    let dst: i32 = mb_fresh_val(st1)
    mb_push_cmd(@{T.CmdCast}, dst, cast_op, src_scalar, dst_scalar, child_val, 0, st1, cmds1)
    jump done(st = st1, cmds = cmds1, value = dst)
end
end
```

**Pattern variation:** Two blocks, one for identity passthrough, one for actual cast.

### ExprSelect (Ternary: cond ? then : else)

**Input:** scalar type, cond expr, then expr, else expr

**Output:** Fresh value with CmdSelect

**Block chain:**
1. Lower cond → got_cond
2. Lower then → got_then  (cond_val in scope)
3. Lower else → got_else  (cond_val, then_val in scope)
4. Emit CmdSelect(cond_val, then_val, else_val)

```mlua
local mb_lower_select_region = region(scalar: i32;
    done: cont(...),
    lower_cond: cont(..., cond_val: i32) -> void,
    lower_then: cont(..., then_val: i32) -> void,
    lower_else: cont(..., else_val: i32) -> void)
entry start(st, cmds)
    emit lower_cond(st = st, cmds = cmds, cond_val = ?)
end
block got_cond(st1, cmds1, cond_val)
    emit lower_then(st = st1, cmds = cmds1, then_val = ?)
end
block got_then(st2, cmds2, then_val)
    emit lower_else(st = st2, cmds = cmds2, else_val = ?)
end
block got_else(st3, cmds3, else_val)
    let dst: i32 = mb_fresh_val(st3)
    mb_push_cmd(@{T.CmdSelect}, dst, scalar, cond_val, then_val, else_val, st3, cmds3)
    jump done(st = st3, cmds = cmds3, value = dst)
end
end
```

**Key:** Three intermediate blocks, each one lowering one child.

### ExprCall (Function Call)

**Input:** func expr, arg list

**Output:** Fresh value with CmdCall

```mlua
local mb_lower_call_region = region(num_args: i32;
    done: cont(...),
    lower_func: cont(..., func_val: i32) -> void)
entry start(st, cmds)
    emit lower_func(st = st, cmds = cmds, func_val = ?)
end
block got_func(st1, cmds1, func_val)
    -- TODO: lower all args sequentially
    -- Then: emit CmdCall
    let dst: i32 = mb_fresh_val(st1)
    mb_push_cmd(@{T.CmdCall}, dst, 0, func_val, 0, 0, 0, st1, cmds1)
    jump done(st = st1, cmds = cmds1, value = dst)
end
end
```

### ExprIndex/ExprField/ExprDeref (Memory Access)

**Input:** base expr, index/field info

**Output:** Fresh value with CmdLoadInfo

Similar pattern: lower base → emit CmdPtrOffset (for address) → emit CmdLoadInfo.

```mlua
local mb_lower_index_region = region(elem_scalar: i32;
    done: cont(...),
    lower_base: cont(..., base_val: i32) -> void,
    lower_index: cont(..., index_val: i32) -> void)
entry start(st, cmds)
    emit lower_base(st = st, cmds = cmds, base_val = ?)
end
block got_base(st1, cmds1, base_val)
    emit lower_index(st = st1, cmds = cmds1, index_val = ?)
end
block got_index(st2, cmds2, index_val)
    -- Compute address: base_val[index_val]
    let addr: i32 = mb_fresh_val(st2)
    mb_push_cmd(@{T.CmdPtrOffset}, addr, base_val, index_val, 1, 0, 0, st2, cmds2)
    -- Load from address
    let dst: i32 = mb_fresh_val(st2)
    mb_push_cmd(@{T.CmdLoadInfo}, dst, addr, elem_scalar, 0, 0, 0, st2, cmds2)
    jump done(st = st2, cmds = cmds2, value = dst)
end
end
```

## Helper Functions Reference

| Function | Purpose |
|----------|---------|
| `mb_fresh_val(st)` | Allocate new value ID, increment st.next_value |
| `mb_push_cmd(tag, w0..w5, st, cmds)` | Write 6-word command to buffer |
| `mb_push_cmd_w10(tag, w0..w9, st, cmds)` | Write 10-word command |
| `mb_is_float_scalar(s)` | Check if BackF32 or BackF64 |
| `mb_is_signed_scalar(s)` | Check if signed integer |
| `mb_token_to_unary_op(tok)` | Map TK_MINUS/TK_NOT/TK_TILDE → UnaryNeg/UnaryNot/UnaryBitNot |
| `mb_token_to_binary_op(tok)` | Map TK_PLUS/TK_MINUS/etc. → BinAdd/BinSub/etc. |
| `mb_token_to_cmp_op(tok)` | Map TK_EQEQ/TK_NE/etc. → CmpEq/CmpNe/etc. |

## Implementation Checklist

### Expressions (24 total, 3 done, 21 remaining)

- [x] ExprLit - Load constant, emit CmdConst
- [x] ExprRef - Lookup binding, return value (stub: CmdTrap)
- [x] ExprUnary - Recursively lower operand, emit CmdUnary
- [ ] ExprBinary - Recursively lower left/right, emit binary command ← See Case 4
- [ ] ExprCompare - Lower lhs/rhs, emit CmdCompare ← Template above
- [ ] ExprCast - Lower child, emit CmdCast (or passthrough) ← Template above
- [ ] ExprSelect - Lower cond/then/else, emit CmdSelect ← Template above
- [ ] ExprCall - Lower func and args, emit CmdCall ← Template above
- [ ] ExprLen - Extract length from view
- [ ] ExprLogic - Short-circuit && and ||
- [ ] ExprDeref - Lower addr, emit load ← Similar to ExprIndex
- [ ] ExprField - Lower base, compute field address, load ← Template above
- [ ] ExprIndex - Lower base/index, compute address, load ← Template above
- [ ] ExprView - Convert view to (data, len, stride) tuple
- [ ] ExprLoad - Explicit memory load, emit CmdLoadInfo
- [ ] ExprAtomicLoad - Emit CmdAtomicLoad
- [ ] ExprAtomicRmw - Emit CmdAtomicRmw
- [ ] ExprAtomicCas - Emit CmdAtomicCas
- [ ] ExprIf - Conditional expression (CFG)
- [ ] ExprSwitch - Switch expression (CFG)
- [ ] ExprBlock - Block expression
- [ ] ExprDot - Field access (same as ExprField)
- [ ] ExprIntrinsic - Call intrinsic function
- [ ] ExprAgg - Aggregate construction

### Statements (19 total, mostly stubs)

- [x] StmtReturnVoid - Emit CmdReturnVoid
- [ ] StmtReturnValue - Lower expr, emit CmdReturnValue
- [ ] StmtExpr - Lower expr (discard result)
- [ ] StmtLet - Lower init, add to env as ScalarLocal
- [ ] StmtVar - Allocate stack slot, lower init
- [ ] StmtSet - Compute address, emit CmdStoreInfo
- [ ] StmtIf - Create blocks, lower condition, both bodies, phi analysis
- [ ] StmtSwitch - Create blocks, lower value, all arms
- [ ] StmtJump/StmtJumpCont - Jump to target (deferred)
- [ ] StmtYield - Yield value (deferred)
- [ ] StmtControl - Delegate to control_api
- [ ] StmtAtomicStore - Emit CmdAtomicStore
- [ ] StmtAtomicFence - Emit CmdAtomicFence
- [ ] StmtAssert - No-op
- [ ] StmtUseRegionSlot/StmtUseRegionFrag - No-op

## Integration Points

### Expression Lowering Main Dispatcher

Once individual regions are implemented, wire them into a main `mb_lower_expr` region that dispatches on expr_tag:

```mlua
local mb_lower_expr = region(idx: i32;
    done: cont(..., value: i32),
    expr_tag: ptr(i32), expr_a: ptr(i32), expr_b: ptr(i32), expr_c: ptr(i32), expr_d: ptr(i32))
entry start(st, cmds)
    let tag: i32 = expr_tag[idx]
    switch tag do
    case @{T.EX_LIT} then
        emit mb_lower_lit_region(tok_kind = expr_a[idx]; done = done)(st = st, cmds = cmds)
    case @{T.EX_UNARY} then
        let child_idx: i32 = expr_b[idx]
        emit mb_lower_unary_region(...; done = done, lower_child = got_child)(st = st, cmds = cmds)
    ... other cases ...
    end
end
block got_child(st1, cmds1, child_val)
    -- Handle result from child lowering
end
end
```

**Key:** Each case emits the corresponding region with appropriate continuations.

## Critical Notes

1. **Immutable environment:** mb_env_* functions return new env, don't mutate input
2. **State threading:** st and cmds are updated by child regions and passed through blocks
3. **Fresh values:** Always allocate with mb_fresh_val(st) before emitting command
4. **Continuation closures:** Blocks form closures over region parameters
5. **Tag constants:** Use @{T.CmdXxx}, @{T.BackXxx}, @{T.EX_Xxx} from tags module

## Testing Strategy

Once implemented:
1. Compile with `make`
2. Test simple expressions: `let x: i32 = 42` → ExprLit
3. Test unary: `let x: i32 = -42` → ExprUnary(ExprLit)
4. Test binary: `let x: i32 = 1 + 2` → ExprBinary(ExprLit, ExprLit)
5. Test recursion: `-1 + 2 * 3` → nested operations
6. Inspect emitted CmdConst, CmdUnary, CmdIntBinary in command buffer

