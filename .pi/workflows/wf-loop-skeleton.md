# Loop skeleton investigation 
Scout gathers facts about which loop shapes the kernel validator accepts and why our parsed-channel loop lowering is rejected.
**Workflow ID**: wf-loop-skeleton
**Started**: 2026-06-28 17:03:51
---

## Scout Output — 2026-06-28 17:05:46

Now I have all the information needed. Here is the comprehensive report.

---

## Files Retrieved

1. **`lua/lalin/code_kernel_plan.lua`** (entire file, ~1100 lines) - The kernel plan engine that infers loop skeletons from code-level facts
2. **`lua/lalin/dsl/init.lua`** (lines 483-990) - The `native_loop_body`, `native_loop_stmt_tree`, and `native_loop_nd_stmt_tree` functions that produce ControlStmtRegion from DSL `lln.loop`
3. **`lua/lalin/syntax/for_to_loop.lua`** (entire file, 63 lines) - The parsed-channel `for i in range(...)` lowering to ControlStmtRegion
4. **`lua/lalin/code_effect_facts.lua`** (entire file, 208 lines) - Effect fact derivation from code-level instructions
5. **`lua/lalin/syntax/to_tree.lua`** (lines 194-300) - The parsed AST → LalinTree converter, shows how `StmtAssign` → `StmtSet`, `StmtForRange` → `for_to_loop.lower()`
6. **`tests/code_ir/test_luajit_artifact_native_loop_dsl.lua`** (entire file, 470 lines) - Main test for DSL's `lln.loop` skeleton recognition
7. **`tests/code_ir/test_luajit_lower_stencil_skeletons.lua`** (entire file, ~400 lines) - Tests for code-level skeleton inference
8. **`tests/syntax_smoke.lua`** (entire file, 33 lines) - Parsed-channel smoke test (parsing only, no full pipeline)
9. **`docs/LANGUAGE_REFERENCE.md`** (lines 367-700, 930-980) - Documents the parsed for/range and its equivalence to lln.loop

---

## 1. Skeleton Types Recognized by the Kernel Plan

The kernel planner recognizes **5 skeleton types** plus **1 partition pattern** (which operates at the function level, not per-loop).

### Skeleton inference order (from `infer_loop_skeleton`, line 792-804):

| Priority | Skeleton | Inference function | Trigger pattern | Result type |
|----------|----------|--------------------|-----------------|-------------|
| 1st | **scan** | `infer_scan_skeleton` (line 616) | Exactly 1 reduction fact AND a store whose value equals the reduction update expression | `KernelResultReduction` |
| 2nd | **scatter_reduce** | `infer_scatter_reduce_skeleton` (line 737) | Store where the stored value is a reduction binary op (add, mul, min, max, band, bor, bxor) reading from the same lane | `KernelResultVoid` |
| 3rd | **find** | `infer_find_skeleton` (line 763) | Exactly 2 loop exits, one returns the primary induction value (the "hit" index), the other returns -1 ("not found") | `KernelResultFind` |
| 4th | **copy** | `infer_copy_skeleton` (line 632) | Store whose value is a primary-index lane load, same element type, primary index on both | `KernelResultVoid` |
| — | **partition** | `infer_partition_skeleton` (line 840) | Function-level: two loops with same counted domain, one does predicate-based copy (stable partition) | `KernelResultValue` |

### Effect patterns per skeleton:

**Scan**: `KernelEffectScan(dst, index, reduction, StencilScanInclusive, axis)` + `KernelEffectFold(reduction)`

**Scatter-reduce**: `KernelEffectScatterReduce(dst, index, contribution, reducer)` where reducer is `StencilReducer(kind, ty, identity, sem, nil)` — kind is one of: `ReductionAdd`, `ReductionMul`, `ReductionMin`, `ReductionMax`, `ReductionBand`, `ReductionBor`, `ReductionBxor`.

**Find**: No kernel effects (effects: `{}`) — the result alone (`KernelResultFind(src, pred, not_found)`) encodes the semantics.

**Copy**: `KernelEffectCopy(dst, src, semantics)` where semantics is either `StencilCopyNoOverlap` or `StencilCopyMemMove`. If `dst` and `src` are the same lane, it falls back to memmove.

**Store fallback**: When no skeleton matches, individual `KernelEffectStore(lane, index, value)` effects are emitted (line 1001-1003 in the else branch after `if skeleton ~= nil`). This is the **default** — the loop still produces a `KernelPlanned` plan with original control result, just without a skeleton optimization.

### Rejection triggers that prevent ANY skeleton:

1. **`effect_is_reject`** (line 199-201): `EffectUnknown`, `EffectVolatile`, `EffectAtomic`, `EffectMayTrap` in loop-local effects → `KernelRejectEffect`
2. **Missing memory proofs**: No `MemBackendAccessInfo`, not proven non-trapping, unknown bounds, no object interval
3. **Missing dependence proofs**: Write pairs without pairwise no-dependence proof
4. **Unsupported instructions**: `CodeInstAtomicLoad/Store/Rmw/Cas/Fence`, `CodeInstCall`
5. **Missing ValueExprFact**: Local value without a value expression fact
6. **No kernel lane**: Load or store instruction not mapped to a memory lane

---

## 2. DSL's `native_loop_stmt_tree` ControlStmtRegion Structure

### No sink (plain copy/fill pattern):

**Block count**: 4 blocks (entry, loop, body, done)

**Label naming**: `"lln_entry_<tag>"`, `"lln_loop_<tag>"`, `"lln_body_<tag>"`, `"lln_done_<tag>"` where tag is `tostring(loop.id)` (e.g., `"0"`)

**Region tag**: `"dsl.lln.loop." .. tag` (e.g., `"dsl.lln.loop.0"`)

**Parameter flow**:
- **entry** (0 params) → jump to `loop_label` with `{ JumpArg(index, start) }`
- **loop** (1 param: `BlockParam(index, range.ty)`) → if cond, jump to `body_label` with `{ JumpArg(index, index_ref) }`; else jump to `done_label` with `{}`
- **body** (1 param: `BlockParam(index, range.ty)`) → body statements + `StmtJump(loop_label, { JumpArg(index, next_index) })`
- **done** (0 params) → `StmtYieldVoid`

### With fold/scan sink (accumulator pattern):

**Block count**: 4 blocks

**Block params**: loop and body each get TWO params: `BlockParam(index, range.ty)` AND `BlockParam(acc, acc_ty)`

**Entry args**: `{ JumpArg(index, start), JumpArg(acc, acc_init) }`

**Done block**: Gets `BlockParam(acc, acc_ty)` — yields `acc_expr` for expr-region, or yields void for stmt-region

**Jump flow**: Body tail-jumps to loop with `{ JumpArg(index, next_index), JumpArg(acc, next_acc) }`

### Special cases:
- **Scan sink**: Body stores `next_acc` into `sink.into` place before jumping back; jump uses `next_ref`, not `next_acc` directly
- **Expression region** (fold with result): Uses `ControlExprRegion` instead of `ControlStmtRegion`, wraps in `StmtReturnValue(ExprControl(...))`
- **ND loops**: Single flattened index + axis-specific params in entry/loop/body blocks

---

## 3. Parsed `for_to_loop.lua` ControlStmtRegion vs DSL Version

### Structural comparison:

| Property | DSL (`native_loop_stmt_tree`) | Parsed (`for_to_loop.lua`) |
|----------|------|------|
| **Block count** | 4 (entry, loop, body, done) | 4 (entry, loop, body, done) |
| **Label names** | `lln_entry_<tag>`, `lln_loop_<tag>`, `lln_body_<tag>`, `lln_done_<tag>` | `<tag>.entry`, `<tag>.loop`, `<tag>.body`, `<tag>.done` (e.g., `parsed.1.entry`) |
| **Region tag** | `dsl.lln.loop.<tag>` | `<tag>` (e.g., `parsed.1`) |
| **Index type** | `range.ty` (from domain) | `TScalar(ScalarIndex)` (hardcoded) |
| **Step/stop** | From `range.start/stop/step` | From `args[1]/args[2]/args[3]`, defaults 0, 1, 1 |
| **Cond polarity** | `range.step < 0 and CmpGt or CmpLt` | Always `CmpLt` (no backward step support) |
| **Body statements** | `tree_stmts(body_items)` + tail jump | `to_tree.stmts(parsed.body)` + tail jump |
| **Fold/scan support** | ✅ Full (accumulator params, init/by/step/into) | ❌ **None** — no fold/scan syntax in parsed surface |
| **Jump args to loop** | `{ JumpArg(index, next_index) }` | `{ JumpArg(index, next_index) }` — **same** |
| **Entry jump args** | `{ JumpArg(index, start) }` | `{ JumpArg(index, start_expr) }` — **same** |
| **Body tail jump** | `StmtJump(loop_label, { JumpArg(index, next_index) })` | `StmtJump(loop_label, { JumpArg(index, next_index) })` — **same** |
| **Done yield** | `StmtYieldVoid` | `StmtYieldVoid` — **same** |
| **BlockParam names** | Uses loop `index` name (e.g., `"i"`) | Uses parsed `index.name` (e.g., `"i"`) — **same** |

### Key differences:

1. **Tag names differ**: The parsed version uses `"parsed.1"` etc. while the DSL uses `"dsl.lln.loop.0"`. This is cosmetic — the tag is only used for diagnostics and identity.

2. **Label names differ**: `"parsed.1.entry"` vs `"lln_entry_0"`. Label identity is resolved by the control flow analysis, not by name pattern matching — so this should not matter functionally.

3. **Index type**: DSL uses `range.ty` from the domain specification; parsed hardcodes `TScalar(ScalarIndex)`. If the index type must match the iteration range's element type, this could cause type mismatch.

4. **No backward step**: Parsed version always uses `CmpLt`, ignores step sign. For negative steps, the comparison would be wrong (always false).

5. **No fold/scan sink**: The parsed surface has no `fold` or `scan` syntax. The body can only contain `StmtAssign` → `StmtSet`, `StmtExpr` → `StmtExpr`, `StmtIf`, `StmtReturn`, `StmtLet`, `StmtVar`, `StmtJump`, `StmtEmit`, and `StmtRequires`. There is no way to express a loop-carried accumulator.

### Critical insight for pipeline integration:

The parsed `for_to_loop.lua` produces a structurally IDENTICAL `ControlStmtRegion` to the no-sink DSL version — same 4-block layout, same tail-jump pattern, same block parameter count. **The ControlStmtRegion structure is not the problem.**

---

## 4. Error Path for "Non-Skeleton Effect in Kernel"

The literal string `"non-skeleton effect in kernel"` **does not exist** in the codebase. The actual error path is more nuanced:

### When no skeleton is inferred (line 993-1006):

```lua
if skeleton ~= nil then
    for _, e in ipairs(skeleton.effects or {}) do effects[#effects + 1] = e end
    if not skeleton.handles_dependences then
        for _, dep in ipairs(dependence_rejects or {}) do
            rejects[#rejects + 1] = Kernel.KernelRejectNoFacts(subject, dep.reason)
        end
    end
else
    -- ⬇ THIS is the "no skeleton" path:
    for _, e in ipairs(body_effects or {}) do effects[#effects + 1] = e end
    for _, reduction in ipairs(reductions) do effects[#effects + 1] = Kernel.KernelEffectFold(reduction) end
    for _, dep in ipairs(dependence_rejects or {}) do
        rejects[#rejects + 1] = Kernel.KernelRejectNoFacts(subject, dep.reason)
    end
end
```

When no skeleton matches, the loop:
1. Emits **raw `KernelEffectStore`** effects (from `build_kernel_body`) instead of the optimized skeleton effects
2. Still gets a `KernelPlanned` plan — **it does NOT produce an error or rejection**
3. The result becomes `KernelResultOriginalControl` ("semantic loop kernel preserves original control by default")

### Actual rejection paths (where a loop gets a `KernelNoPlan`):

| Rejection reason | Trigger | Error message |
|-----------------|---------|---------------|
| Not a counted domain | `loop.counted == nil` | `"loop is not a counted Flow domain"` |
| No function owner | `func_id == nil` | `"graph loop has no function owner"` |
| Effect reject | `effect_is_reject(eff)` returns true | `"loop-local effect is unsupported by semantic kernel planning"` |
| Memory reject | No backend info, no non-trapping proof, unknown bounds, no object | `"missing MemBackendAccessInfo..."`, `"is not proven non-trapping"`, etc. |
| Dependence reject | Write pair lacks dependence proof | `"loop write pair lacks pairwise no-dependence proof: ..."` |
| Missing function | `func == nil` after graph lookup | `"graph loop owner function is missing from CodeModule"` |

### The `effect_is_reject` function (line 199-201):

```lua
local function effect_is_reject(eff)
    local cls = pvm.classof(eff)
    return cls == Effect.EffectUnknown 
        or cls == Effect.EffectVolatile 
        or cls == Effect.EffectAtomic 
        or cls == Effect.EffectMayTrap
end
```

A parsed-channel loop that only does `dst[i] = lhs[i] + rhs[i]` should produce `EffectRead`, `EffectWrite`, and `EffectNoTrap` effects — none of which are in the reject set. **The effects should not be the problem** for a simple element-wise copy or zip loop.

---

## 5. Effects Produced by Loop Body

From `lua/lalin/code_effect_facts.lua`, the `inst_effects` function (line 75-145) maps Code instructions to effects:

| Code instruction | Effect(s) produced |
|-----------------|-------------------|
| `CodeInstLoad` | `EffectRead(object, proof)` + possibly `EffectNoTrap` or `EffectMayTrap` |
| `CodeInstStore` | `EffectWrite(object, proof)` + possibly `EffectNoTrap` or `EffectMayTrap` |
| `CodeInstAtomicLoad` | `EffectRead` + `EffectWrite` + `EffectAtomic` |
| `CodeInstAtomicStore` | `EffectWrite` + `EffectAtomic` |
| `CodeInstAtomicRmw` | `EffectRead` + `EffectWrite` + `EffectAtomic` |
| `CodeInstAtomicCas` | `EffectRead` + `EffectWrite` + `EffectAtomic` |
| `CodeInstCall` (direct, pure) | `EffectNoTrap` ("direct internal callee has no memory/call/trap effects") |
| `CodeInstCall` (direct, not pure) | `EffectUnknown` ⚠️ |
| `CodeInstCall` (extern) | `EffectUnknown` ⚠️ |
| `CodeInstCall` (indirect) | `EffectUnknown` ⚠️ |
| `CodeInstCall` (closure) | `EffectUnknown` ⚠️ |
| `CodeInstAtomicFence` | `EffectAtomic` |
| **Volatile access** | Extra `EffectVolatile` ⚠️ |
| **Trapping access** | Extra `EffectMayTrap` ⚠️ |

⚠️ = triggers `effect_is_reject` → `KernelRejectEffect` → prevents skeleton inference

**Safe effects** (do NOT reject): `EffectRead`, `EffectWrite`, `EffectNoTrap`, `EffectNoEscape`, `EffectRetain`, `EffectInvalidate` (from contracts)

A simple `dst[i] = lhs[i] + rhs[i]` lowering produces: `EffectRead(lhs)`, `EffectRead(rhs)`, `EffectWrite(dst)`, `EffectNoTrap` — these are all **accepted**.

---

## 6. Tests Exercising Loop Skeleton Recognition

### Primary test files:

1. **`tests/code_ir/test_luajit_artifact_native_loop_dsl.lua`** (470 lines)
   - Tests DSL `lln.loop` through the full LuaJIT MC artifact pipeline
   - Exercises: **copy** (`native_zip_add`), **fold** (`native_dot`, `native_product`, `native_min`), **scan** (`native_scan`, `native_scan_product`)
   - Tests backward ranges (negative step): backward_copy, reverse_affine_copy, backward_sum, backward_scan, reverse_affine_scan
   - Tests ND ranges: nd_shape, nd_stencil (window)
   - Assertions: `assert(#artifact.artifacts == 6, 'native lln.loop should select store, fold, and scan stencil artifacts')`

2. **`tests/code_ir/test_luajit_lower_stencil_skeletons.lua`** (~400 lines)
   - Tests code-level (not DSL) skeleton inference using `build_loop_case`
   - Exercises: **scan** (`skeleton_scan`), **find** (`skeleton_find`, `skeleton_find_inferred`), **partition** (`skeleton_partition`), **copy memmove** (`skeleton_copy_memmove`), **copy overlap** (`skeleton_copy_overlap`)
   - Uses `compile_auto_skeleton` for end-to-end inference verification

3. **`tests/code_ir/test_code_kernel_plan_rules.lua`** (102 lines)
   - Tests the rule-based `select_loop_kernel_plan` decision logic
   - Tests: uncounted loop → no_plan, ownerless loop → no_plan, rejected loop → no_plan, closed-form → planned, reduction → planned, skeleton → planned, plain counted → planned with `original_control`

4. **`tests/syntax_smoke.lua`** (33 lines)
   - Tests parsed-channel `for i in range(0, n) do` parsing
   - Only tests parsing (tag assertions), NOT the full compile pipeline

### No existing tests for parsed-channel for/range through the full pipeline:

There is **no test** that feeds a parsed-channel `for i in range(...)` through the full `parse → to_tree → typecheck → Code → Flow → Kernel → Stencil` pipeline. The `syntax_smoke.lua` test only checks parsed AST tags and host escape resolution, not compilation or execution.

---

## Observations

1. **The ControlStmtRegion structure is isomorphic** between DSL and parsed versions for simple (no fold/scan) loops. The 4-block layout, jump patterns, and parameter flow are identical modulo naming. The kernel planner does not use label names or region tags to determine skeleton eligibility — it only looks at code-level facts.

2. **The skeleton inference is purely based on Code-level facts** (effects, memory accesses, value expressions, control flow edges), not on the source-level syntax or the tree structure. The `infer_loop_skeleton` function receives `func` (a `CodeModule` function with blocks/instructions), `effects` (instruction effects), `reductions` (reduction facts), etc. — all post-typecheck, post-Code-facts artifacts. The original `ControlStmtRegion` has been fully lowered to Code by this point.

3. **If the parsed-channel loop is rejected, the most likely cause is in the lowering pipeline before the kernel plan**: 
   - A type mismatch in the index type (parsed uses `ScalarIndex`, DSL uses `range.ty`)
   - Missing memory contract facts (bounds, disjointness — the parsed surface requires `requires` clauses or contract inference)
   - A `CodeInstCall` instead of inline arithmetic (if the parsed expression lowering introduces a call)
   - A volatile or trapping memory access (if the backend info doesn't prove non-trapping)

4. **The parsed surface has no fold/scan syntax**, so parsed-channel loops can only match the `copy`, `scatter_reduce`, or `find` skeletons — never `scan` and never `fold` (since reductions require loop-carried accumulator params which the parsed version doesn't produce).

5. **The "non-skeleton effect" error** that the user asked about may actually refer to the situation where individual `KernelEffectStore` effects (the fallback when no skeleton matches) are later rejected by the stencil layer or the schedule/lower rules, rather than in `code_kernel_plan.lua` itself. The kernel plan itself never errors on non-skeleton — it just emits raw store effects with an `original_control` result.
