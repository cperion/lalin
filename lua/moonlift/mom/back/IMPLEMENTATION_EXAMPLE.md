# Implementation Example: ExprCompare

This document walks through implementing one complete expression case (ExprCompare) to demonstrate the full pattern.

## Overview

**ExprCompare** is a comparison operation: `x == y`, `x < y`, etc.

**Characteristics:**
- Takes 2 child expressions (lhs, rhs)
- Dispatches on comparison operator (==, !=, <, <=, >, >=)
- Returns BackBool result
- Maps token kind → backend comparison operator

**Complexity:** LOW (similar to ExprBinary)

---

## Step-by-Step Implementation

### Step 0: Understand the Existing Pattern

From **expr_lower.mlua, lines 280-341**, the binary pattern shows:

```mlua
local mb_lower_binary_region = region(expr_op: i32, scalar: i32;
                                       done: cont(st: ptr(@{LowerState}), cmds: ptr(i32), value: i32),
                                       lower_children: cont(st: ptr(@{LowerState}), cmds: ptr(i32), left_val: i32, right_val: i32) -> void)
entry start(st, cmds)
    emit lower_children(st = st, cmds = cmds, left_val = ?, right_val = ?)
end
block with_children(st1, cmds1, left_val, right_val)
    let dst: i32 = mb_fresh_val(st1)
    -- Dispatch on expr_op
    if expr_op == @{T.TK_PLUS} then ... end
    jump done(st = st1, cmds = cmds1, value = dst)
end
end
```

**Our ExprCompare will follow the exact same structure**, but:
- Return type is always BackBool
- Result command is CmdCompare (not CmdIntBinary/CmdFloatBinary)
- Operator mapping uses mb_token_to_cmp_op (already exists!)

### Step 1: Define the Region Signature

```mlua
local mb_lower_compare_region = region(cmp_op: i32, scalar: i32;
                                        done: cont(st: ptr(@{LowerState}), cmds: ptr(i32), value: i32),
                                        lower_children: cont(st: ptr(@{LowerState}), cmds: ptr(i32), lhs_val: i32, rhs_val: i32) -> void)
```

**Parameters:**
- `cmp_op: i32` - Token kind (TK_EQEQ, TK_NE, TK_LT, etc.)
- `scalar: i32` - Type to compare (BackI32, BackF64, etc.)

**Continuations:**
- `done` - Final continuation (what to call with result)
- `lower_children` - Child lowerer (parent will provide this)

### Step 2: Implement Entry Block

```mlua
entry start(st: ptr(@{LowerState}), cmds: ptr(i32))
    emit lower_children(st = st, cmds = cmds, lhs_val = ?, rhs_val = ?)
end
```

**What this does:**
- Emits (calls) lower_children continuation
- Passes current state (st, cmds)
- Placeholders `?` for lhs_val and rhs_val (will be filled by continuation)
- The continuation name must match a block below

### Step 3: Implement Result Block

```mlua
block with_children(st1: ptr(@{LowerState}), cmds1: ptr(i32), lhs_val: i32, rhs_val: i32)
    let dst: i32 = mb_fresh_val(st1)
    let back_cmp: i32 = mb_token_to_cmp_op(cmp_op)
    mb_push_cmd(@{T.CmdCompare}, dst, back_cmp, scalar, lhs_val, rhs_val, 0, st1, cmds1)
    jump done(st = st1, cmds = cmds1, value = dst)
end
```

**What this does:**

1. **Allocate result value:**
   ```mlua
   let dst: i32 = mb_fresh_val(st1)
   ```
   - Gets fresh value ID (increments st1.next_value)
   - This is where the comparison result will be stored

2. **Map operator:**
   ```mlua
   let back_cmp: i32 = mb_token_to_cmp_op(cmp_op)
   ```
   - mb_token_to_cmp_op is already defined in back_lower.mlua (line 192)
   - Maps TK_EQEQ → CmpEq, TK_NE → CmpNe, TK_LT → CmpLt, etc.

3. **Emit command:**
   ```mlua
   mb_push_cmd(@{T.CmdCompare}, dst, back_cmp, scalar, lhs_val, rhs_val, 0, st1, cmds1)
   ```
   - Command tag: `@{T.CmdCompare}`
   - Data words:
     - w0 = dst (destination value)
     - w1 = back_cmp (comparison operator)
     - w2 = scalar (operand type)
     - w3 = lhs_val (left operand)
     - w4 = rhs_val (right operand)
     - w5 = 0 (padding)

4. **Call final continuation:**
   ```mlua
   jump done(st = st1, cmds = cmds1, value = dst)
   ```
   - Invokes the continuation passed to this region
   - Passes updated state (st1 now has cmd_count incremented by mb_push_cmd)
   - Passes result value (dst)

### Step 4: Complete Code

Combine steps 1-3:

```mlua
-- Lower a compare expression: emit CmdCompare.
-- Signature: Compare two values with a binary comparison operator, return BackBool.
-- Pattern: Same as ExprBinary (recurse on both children, emit result command)
local mb_lower_compare_region = region(cmp_op: i32, scalar: i32;
                                        done: cont(st: ptr(@{LowerState}), cmds: ptr(i32), value: i32),
                                        lower_children: cont(st: ptr(@{LowerState}), cmds: ptr(i32), lhs_val: i32, rhs_val: i32) -> void)
entry start(st: ptr(@{LowerState}), cmds: ptr(i32))
    emit lower_children(st = st, cmds = cmds, lhs_val = ?, rhs_val = ?)
end
block with_children(st1: ptr(@{LowerState}), cmds1: ptr(i32), lhs_val: i32, rhs_val: i32)
    let dst: i32 = mb_fresh_val(st1)
    let back_cmp: i32 = mb_token_to_cmp_op(cmp_op)
    mb_push_cmd(@{T.CmdCompare}, dst, back_cmp, scalar, lhs_val, rhs_val, 0, st1, cmds1)
    jump done(st = st1, cmds = cmds1, value = dst)
end
end
```

**Line count:** 14 lines

---

## Step 5: Export the Region

In the **PUBLIC API EXPORTS** section (currently lines 371-389), add:

```mlua
M.mb_lower_compare_region = mb_lower_compare_region
```

---

## Step 6: Integrate into Main Dispatcher

Once mb_lower_expr is wired (currently lines 242-424 in back_lower.mlua are stubs), add this case:

```mlua
case @{T.EX_COMPARE} then
    let lhs_idx: i32 = expr_b[idx]
    let rhs_idx: i32 = expr_c[idx]
    emit mb_lower_expr(idx = lhs_idx; done = got_lhs, expr_tag = expr_tag, ...)(st = st, cmds = cmds)
end

block got_lhs(st1, cmds1, lhs_val)
    emit mb_lower_expr(idx = rhs_idx; done = got_rhs, expr_tag = expr_tag, ...)(st = st1, cmds = cmds1)
end

block got_rhs(st2, cmds2, rhs_val)
    -- Here we have both lhs_val and rhs_val in scope (closure capture)
    emit mb_lower_compare_region(cmp_op = expr_a[idx], scalar = scalar;
                                  done = done,
                                  lower_children = compare_children)(st = st2, cmds = cmds2)
end

block compare_children(st3, cmds3, cmp_lhs_val, cmp_rhs_val)
    -- For ExprCompare, we already have both children lowered above
    -- So we directly invoke the done continuation with lhs_val and rhs_val
    jump done(st = st3, cmds = cmds3, value = ???)
end
```

**Actually**, the dispatcher is more complex. See **expr_lower.mlua, lines 372-375**:

```mlua
case @{T.EX_COMPARE} then
    let lhs_idx: i32 = expr_b[idx]
    emit mb_lower_expr(idx = lhs_idx; done = got_lhs, expr_tag = expr_tag, expr_a = expr_a, expr_b = expr_b, expr_c = expr_c, expr_d = expr_d, e_scalar = e_scalar)(st = st, cmds = cmds)
```

This recursively lowers the children within the main expr_lower region, then in a block processes them.

---

## Testing the Implementation

### Test Case 1: Simple Comparison

**Source:**
```moonlift
fn test() -> bool {
    return 5 == 3
}
```

**Expected command sequence:**
1. CmdConst(val1, BackI32, 5)
2. CmdConst(val2, BackI32, 3)
3. CmdCompare(val3, CmpEq, BackI32, val1, val2)
4. CmdReturnValue(val3)

**Execution:**
1. ExprLit(5) → emit CmdConst(val1, 5)
2. ExprLit(3) → emit CmdConst(val2, 3)
3. ExprCompare → emit CmdCompare(val3, CmpEq, BackI32, val1, val2)

### Test Case 2: Nested Comparison

**Source:**
```moonlift
fn test() -> bool {
    return 1 < 2 and 3 == 4
}
```

**Expected command sequence:**
1. CmdConst(val1, BackI32, 1)
2. CmdConst(val2, BackI32, 2)
3. CmdCompare(val3, CmpLt, BackI32, val1, val2)
4. CmdConst(val4, BackI32, 3)
5. CmdConst(val5, BackI32, 4)
6. CmdCompare(val6, CmpEq, BackI32, val4, val5)
7. CmdLogic(...val3, val6...)
8. CmdReturnValue(...)

---

## Debugging Checklist

If compilation or execution fails:

1. **Syntax errors?**
   - Check block names match emit sites
   - Verify all jumps have matching continuations
   - Ensure type annotations are correct

2. **Logic errors?**
   - Verify mb_token_to_cmp_op returns valid BackXcmpXx tag
   - Check CmdCompare tag is correct (@{T.CmdCompare})
   - Ensure state threading: st1 → st2 → st3 with incremented counters

3. **Runtime errors?**
   - Verify st.cmd_count doesn't exceed st.cmd_cap
   - Check mb_fresh_val returns monotonically increasing IDs
   - Ensure destination value is freshly allocated (not reused)

4. **Integration errors?**
   - Verify dispatcher calls mb_lower_compare_region
   - Check continuations passed have correct signatures
   - Ensure return type is BackBool (not original scalar type)

---

## Comparison with Binary Operators

| Aspect | Binary | Compare |
|--------|--------|---------|
| Children | 2 (left, right) | 2 (lhs, rhs) |
| Operator | 11 variants (Add, Sub, Mul, etc.) | 6 variants (Eq, Ne, Lt, Le, Gt, Ge) |
| Operand types | Both same (scalar) | Both same (scalar) |
| Result type | Same as operands | Always BackBool |
| Command | CmdIntBinary / CmdFloatBinary / CmdBitBinary / CmdShift | CmdCompare |
| Dispatcher | if/elseif chain per operator | mb_token_to_cmp_op + single command |
| Complexity | HIGH (many cases per operator type) | LOW (single CmdCompare per case) |

**Key difference:** Compare always returns BackBool, so no type-dispatch needed. Just map operator and emit CmdCompare once.

---

## Next Cases to Implement

Now that you understand the pattern, here are good next cases (in order of difficulty):

1. **ExprCast** (LOW) - 2 blocks, identity check
2. **ExprDeref** (LOW) - 1 block, CmdLoadInfo
3. **ExprCall** (MEDIUM) - N args, CmdCall
4. **ExprSelect** (MEDIUM) - 3 children, CmdSelect
5. **ExprIndex** (MEDIUM) - Address calculation, CmdPtrOffset + CmdLoadInfo
6. **ExprField** (MEDIUM) - Field offset, bool handling
7. **ExprLogic** (MEDIUM-HIGH) - Short-circuit, may need CFG
8. **ExprView** (MEDIUM) - Tuple extraction
9. **StmtLet** (LOW) - Environment binding
10. **StmtVar** (LOW) - Stack allocation

Pick any of these and follow the same steps!

---

## Reference: Command Signatures

For ExprCompare, the CmdCompare signature is:

```
CmdCompare: (w0=dst, w1=cmp_op, w2=scalar, w3=lhs, w4=rhs, w5=0)
```

For reference, here are other common commands:

```
CmdConst: (w0=dst, w1=scalar, w2=tok_kind, w3=0, w4=0, w5=0)
CmdUnary: (w0=dst, w1=unary_op, w2=count, w3=scalar, w4=operand, w5=0)
CmdIntBinary: (w0=dst, w1=op, w2=scalar, w3=flags, w4=lhs, w5=rhs)
CmdFloatBinary: (w0=dst, w1=op, w2=scalar, w3=flags, w4=lhs, w5=rhs)
CmdBitBinary: (w0=dst, w1=op, w2=scalar, w3=lhs, w4=rhs, w5=0)
CmdShift: (w0=dst, w1=op, w2=scalar, w3=lhs, w4=rhs, w5=0)
CmdSelect: (w0=dst, w1=scalar, w2=cond, w3=then, w4=else, w5=0)
CmdLoadInfo: (w0=dst, w1=addr, w2=scalar, w3=mem_info, w4=0, w5=0)
```

For a complete list, see `/home/cedric/dev/moonlift/lua/moonlift/mom/back/cmd.mlua`.

---

## Summary

**ExprCompare implementation:**
- ✅ 14 lines of code
- ✅ 1 region definition
- ✅ 1 block
- ✅ 1 helper function call (mb_token_to_cmp_op)
- ✅ 1 command emission (CmdCompare)
- ✅ Follows proven pattern from ExprBinary
- ✅ Ready for immediate use

**Estimated time:** 15 minutes (including testing)

**Difficulty:** LOW - Good warmup case

