# Schema V2 Migration — Complete Gap Assessment

> Generated from 4-scout herdr pack, merged into main at 6061de7e.
> Date: 2026-07-07

---

## Overview

The Lalin compiler has two coexisting compiler paths:

```
OLD (public API):   init.lua → frontend_pipeline → old lalin.schema → emit_c_lower → GCC
NEW (schema_v2):    compiler_api.lua → schema_v2 + impl/ → tree_code → lower_emit_c → cemit_emit → C text
```

**They are completely disconnected.** The old path runs the public `lalin.emit_c`/`compile_c_gcc`. The new path runs `CompilerSession:compile()` → returns C source text only, no GCC compile-run. Only bridge: `init.lua:41` passes `schema_v2` to the DSL module for type authoring — one-way, no compilation bridge.

---

## What Works (New Path)

### End-to-end GCC-compilable
- Empty functions (`fn empty() [void] do end`)
- Scalar add/sub/mul on i32 (`fn add(a [i32], b [i32]) [i32] do return a + b end`)

### Typecheck — 12/33 expression leaves, 12/18 statement leaves
- ExprLit, ExprRef, ExprUnary, ExprBinary, ExprCompare, ExprLogic, ExprCast, ExprMachineCast, ExprAddrOf, ExprDeref
- StmtLet, StmtVar, StmtSet, StmtExpr, StmtAssert, StmtReturnValue, StmtReturnVoid, StmtYieldValue, StmtYieldVoid, StmtJump, StmtControl, StmtTrap
- TypeDeclStruct, TypeDeclUnion (surface resolve)

### Code → CBackendUnit — 3/37 instructions, 3/7 terminators
- CodeInstConst, CodeInstAlias, CodeInstBinary
- CodeTermReturn, CodeTermTrap, CodeTermUnreachable

### CBackendUnit → C text — 100% of core emission surface
- All 11 CBackendStmt leaves, all 6 CBackendTerminator leaves, all 9 CBackendRValue leaves
- All 4 CBackendAtom leaves, all 7 CBackendPlace leaves, all 16 CBackendType leaves
- All 4 CBackendCallTarget leaves, all 3 CBackendFuncBody leaves, all 14 CBackendHelperSpec leaves

### Test coverage
- 5/166 test files reference schema_v2 (3.0%)
- All 5 schema_v2 tests pass (empty, add, cbackend_unit, cemit_source, add_compile)

---

## What Does NOT Work — Detailed Gap Catalog

### TIER 1 — FRONTEND (typecheck + surface + closure)

#### Expression Typecheck (21 stubbed)

| # | Leaf | File:Line | Issue |
|---|------|-----------|-------|
| 1 | ExprCall | tree_check/expr.lua:200 | Comment "simplified" — no param/arg arity check, no callable result extraction, no per-arg type matching. Old: 30+ lines with full callable result, arity, arg checking. |
| 2 | ExprIntrinsic | tree_check/expr.lua:206 | Always returns ScalarVoid. Old resolves per-intrinsic result types (sqrt→f64, etc). |
| 3 | ExprAgg | tree_check/expr.lua:225 | Returns self.ty with no field-level or layout typecheck. |
| 4 | ExprArray | tree_check/expr.lua:226 | Returns Ty.TArray with literal count; no element typecheck or count validation. |
| 5 | ExprNull | tree_check/expr.lua:227 | Returns self.elem; no nullable type validation. |
| 6 | ExprSizeOf | tree_check/expr.lua:228 | Returns ScalarIndex without computing actual size. |
| 7 | ExprAlignOf | tree_check/expr.lua:229 | Returns ScalarIndex without computing alignment. |
| 8 | ExprIsNull | tree_check/expr.lua:230 | Returns ScalarBool without checking operand is nullable/pointer. |
| 9 | ExprCtor | tree_check/expr.lua:231 | Returns ScalarU32 always. Old: full variant lookup, payload canonicalization, arg count/type check. |
| 10 | ExprLoad | tree_check/expr.lua:232 | Returns self.ty; no pointer-type source validation. |
| 11 | ExprBlock | tree_check/expr.lua:233 | Extracts result type from header only; does not typecheck block statements. |
| 12 | ExprIf | tree_check/expr.lua:234-237 | Only typechecks then_expr; ignores else_expr. No condition bool check, no branch type unification. |
| 13 | ExprSelect | tree_check/expr.lua:238-241 | Only typechecks then_expr; no variant discrimination. |
| 14 | ExprSwitch | tree_check/expr.lua:242 | Always returns ScalarVoid. Old: full arm typechecking, variant arm traversal, default body. |
| 15 | ExprControl | tree_check/expr.lua:243 | Returns region result_ty with no control flow typecheck. |
| 16 | ExprView | tree_check/expr.lua:244 | Returns Ty.TView without validating the view expression. |
| 17 | ExprLen | tree_check/expr.lua:245 | Returns ScalarIndex without validating operand is view/slice. |
| 18 | ExprAtomicLoad | tree_check/expr.lua:246 | Returns self.ty; no atomic ordering semantics. |
| 19 | ExprAtomicRmw | tree_check/expr.lua:247 | Returns self.ty; no rmw operation validation. |
| 20 | ExprAtomicCas | tree_check/expr.lua:248 | Returns self.ty; no CAS type validation. |
| 21 | ExprClosure | tree_check/expr.lua:249-251 | Returns Ty.TClosure with no body typecheck, capture analysis, or free variable detection. |

#### Statement Typecheck (6 stubbed/missing)

| # | Leaf | File:Line | Issue |
|---|------|-----------|-------|
| 22 | StmtIf | **MISSING** from stmt.lua | Does not exist at all in new path. Fundamental control flow has zero typechecking. |
| 23 | StmtSwitch | stmt.lua:113-117 | Typechecks switch value but not arms, variant arms, or default body. |
| 24 | StmtAtomicStore | stmt.lua:118-119 | Pass-through, no validation. |
| 25 | StmtAtomicFence | stmt.lua:120-121 | Pass-through. |
| 26 | StmtRegionEmit | stmt.lua:123 | Pass-through; no region expansion. Old: full typecheck_tree_expand_region_invoke. |
| 27 | StmtRegionCall | stmt.lua:124 | Pass-through; no region expansion. |
| 28 | StmtJumpCont | stmt.lua:125 | Pass-through; no continuation target validation. |

#### TypeDecl Surface Resolution (3 stubbed)

| # | Variant | Status |
|---|---------|--------|
| 29 | TypeDeclEnumSugar | Returns self as-is; internal types not resolved. |
| 30 | TypeDeclTaggedUnionSugar | Returns self as-is; no variant payload/field type resolution. |
| 31 | TypeDeclHandle | Returns self as-is; repr not canonicalized. |

#### Closure Conversion (100% stub)

| # | Component | Status |
|---|-----------|--------|
| 32 | ExprClosure:closure_convert() | Throws error: "Closures not supported in schema_v2 pipeline yet (tree_closure.lua is stub)" |
| 33 | find_free_vars() | Builds param_set but never compares against refs — captures always empty. |
| 34 | Module:closure_convert() | Iterates items but ItemFunc:closure_convert_item is no-op. |
| 35 | Capture layout (closure_size_align) | Completely missing from new path (80+ lines in old). |
| 36 | Environment threading (__lalin_ctx) | Old paths __lalin_ctx through all captured references; new has none. |

New file: 44 lines. Old file: 819 lines. **Any program containing a lambda/closure crashes at compile time.**

---

### TIER 2 — LOWERING (tree_code → Code)

#### Expression Lowering (1 critical gap)

| # | Feature | File:Line | Issue |
|---|---------|-----------|-------|
| 37 | ExprSwitch variant arms | tree_code.lua:1883 | `unsupported(self, "ExprSwitch variant — complex; see old tree_lower for full impl")`. Old fully lowers with tag extraction, per-arm variant payload binding, join block with result param (~80 lines). New StmtSwitch already handles variant arms — expression form just needs the same pattern. |

All other expression/stmt lowering leaves are at parity with old path or same-state gaps (ExprDot, ExprClosure, StmtJumpCont, StmtRegionEmit, StmtRegionCall are unsupported in both).

---

### TIER 3 — C BACKEND (code_to_c + lower_emit_c)

#### CodeInstOp Lowering (34/37 missing — 8.1% coverage)

| Status | Leaves |
|--------|--------|
| ✅ HAS leaf (3) | CodeInstConst, CodeInstAlias, CodeInstBinary |
| ❌ Missing (34) | CodeInstUnary, CodeInstFloatBinary, CodeInstCompare, CodeInstCast, CodeInstSelect, CodeInstIntrinsicVoid, CodeInstIntrinsicValue, CodeInstAddrOf, CodeInstGlobalRef, CodeInstPtrOffset, CodeInstLoad, CodeInstStore, CodeInstAggregate, CodeInstArray, CodeInstViewMake, CodeInstViewData, CodeInstViewLen, CodeInstViewStride, CodeInstSliceMake, CodeInstSliceData, CodeInstSliceLen, CodeInstByteSpanMake, CodeInstByteSpanData, CodeInstByteSpanLen, CodeInstClosure, CodeInstVariantCtor, CodeInstVariantTag, CodeInstVariantPayload, CodeInstCall, CodeInstAtomicLoad, CodeInstAtomicStore, CodeInstAtomicRmw, CodeInstAtomicCas, CodeInstAtomicFence |

Old code_to_c.lua: 37/37 = 100%.

#### CodeTermOp Lowering (4/7 missing — 42.9% coverage)

| Status | Leaves |
|--------|--------|
| ✅ HAS leaf (3) | CodeTermReturn, CodeTermTrap, CodeTermUnreachable |
| ❌ Missing (4) | CodeTermJump, CodeTermBranch, CodeTermSwitch, CodeTermVariantSwitch |

Old code_to_c.lua: 7/7 = 100%. **No control flow beyond return/trap can be lowered to C.**

#### LowerModule:emit_c Scope

| CBackendUnit Field | Value | Status |
|--------------------|-------|--------|
| module_name | code_module.id.text | ✅ |
| target | C99/Hosted/LE/64-bit | ✅ |
| sigs | From code_module.sigs (scalar only) | ✅ |
| **externs** | {} | ❌ **Empty** — no extern handling |
| **globals** | {} | ❌ **Empty** — no global handling |
| **types** | {} | ❌ **Empty** — no struct/union/typedef |
| **datas** | {} | ❌ **Empty** — no data segment handling |
| helpers | Only CodeInstBinary helpers | ⚠️ |
| funcs | Only scalar-param functions | ⚠️ |

#### Complex Type Handling (code_to_c_backend_type)

Only these CodeTypes map to CBackendType: CodeTyVoid, CodeTyBool8, CodeTyInt, CodeTyFloat, CodeTyIndex, CodeTyDataPtr.

**Missing (all error):** CodeTyStruct, CodeTyUnion, CodeTyArray, CodeTyView, CodeTySlice, CodeTyByteSpan, CodeTyHandle, CodeTyLease, CodeTyClosure, CodeTyNamed, CodeTyImportedC, CodeTyVector, CodeTyCodePtr.

---

### TIER 4 — C EMISSION (cemit_emit)

Core surface is 100% complete (193 leaf methods across Stmt/Term/RValue/Atom/Place/Type/CallTarget/FuncBody/HelperSpec). Gaps are in advanced features:

| Gap | Severity | Detail |
|-----|----------|--------|
| CBackendTypeDecl emission | MEDIUM | No c_emit_type_decl — no struct/union/typedef C output (old has 4 leaves) |
| Optimization passes | MEDIUM | Entirely absent: no copy-prop, field hoist, dead copy elim, alias rewrite, transfer scratch, inline expressions (old has 631 methods vs new 193) |
| Descriptor/closure type gen | MEDIUM | Old had implicit type collection; new has none |
| HelperSpec diversity | LOW | Old had Atomic*, BoolNormalize, LayoutAssert, RequireFeature, Scan, Find, Reduce; new has only basic set |

---

### TIER 5 — CODE/GRAPH/FACTS (internals)

#### Gap: Vector Schedule Selection

File: `impl/schedule_plan.lua:148-149`. Vector schedule form detection exists and correctly matches contiguous vector-lane patterns against target SIMD capabilities. But when a vector form IS matched, capability is hardcoded to `executable = false` with reject "vector lowering not yet classified". Forces all kernels to scalar schedules.

#### Gap: code_graph UseRole — string vs ASDL sum

File: `impl/code_graph.lua`. The `add_use` helper passes string role names to `Graph.GraphUse`, but schema_v2 `UseRole` is an ASDL sum with concrete leaves. A shim converts strings to `UseRoleOperand`. The schema should be expanded or the callers should pass typed UseRole leaves.

### Clean audit (no gaps)
- code_graph.lua: All 38 CodeInstOp and 7 CodeTermOp leaves have append_uses/append_edges methods (defaults are correct where omitted)
- code_flow.lua, code_value.lua, code_mem.lua, code_effect.lua: nil returns are either expected design choices or defensive fallbacks
- kernel_plan.lua, lower_plan.lua: parent "unsupported" errors are catch-alls for unhandled future variants; all concrete leaves override them
- cemit_emit.lua: 100% of core emission surface is implemented per ASDL leaf

---

## Two Separate ASDL Contexts

```
OLD context (lalin/schema/): 37 files → schema_projection → asdl.context()
  Used by: init.lua (public API), frontend_pipeline, emit_c_lower, luajit_backend, native_backend
  0 impl/ files reference lalin.schema

NEW context (lalin/schema_v2/): 29 files → schema_v2/init.lua → asdl.context()
  Used by: ALL 37 impl/ files, compiler_api.lua, DSL module (init.lua:41-42)
  0 public API functions reference impl/compiler_api

These are TWO INDEPENDENT ASDL contexts. Methods installed on one are invisible to the other.
The only bridge: init.lua:41 passes schema_v2 to the DSL for type evaluation only.
```

---

## Public API Disconnect

```
PUBLIC (init.lua):
  emit_c / compile_c_gcc / compile_luajit / compile_native
    → frontend_pipeline(OLD schema context)
      → emit_c_lower / luajit_backend / native_backend
        → GCC dlopen / Lua loadstring / Native bank

  [NO ROUTE TO compiler_api / schema_v2 impl]

INTERNAL (compiler_api.lua):
  CompilerSession:compile()
    → schema_v2 + impl/ pipeline
      → returns CompilerArtifactC { .source, .header }  ← C TEXT ONLY
      → [NO GCC compile-run, NO FFI function pointer]
```

`compile.lua` is a placeholder: `local decls = nil -- placeholder: requires lalin.loadstring integration`.

---

## Summary Matrix

| Layer | Old Coverage | New Coverage | % Ported |
|-------|-------------|-------------|----------|
| Expression typecheck | 25 leaves | 12/33 leaves (21 stub) | 36% |
| Statement typecheck | 17 leaves | 12/18 leaves (5 stub, 1 missing) | 67% |
| TypeDecl surface | 5 variants | 2/5 (3 pass-through) | 40% |
| Closure conversion | 819 lines | 44 lines (stub) | 0% |
| Expr/stmt lowering | Near 100% | Near 100% (1 critical gap) | ~97% |
| CodeInstOp → CBackend | 37/37 | 3/37 | 8% |
| CodeTermOp → CBackend | 7/7 | 3/7 | 43% |
| CBackendUnit → C text | 631 methods | 193 methods (core 100%) | 31% |
| Public API bridge | Full | None | 0% |
| Test coverage (schema_v2) | N/A | 5/166 files | 3% |

**Overall port completion: ~15-20%.** The new path handles scalar i32 arithmetic with no control flow, no calls, no structs, no closures. The old path remains the production compiler for everything else.
