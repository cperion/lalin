# MOM Gap Plan — Closing the Compiler Phase Gap

This document records exactly what the MOM port is missing, what the current
compromises are, and the execution order for closing each gap. It is a living
checklist. Every item here is tracked to a specific file and line number.

---

## 1. The Gap in One Picture

```
Source bytes (ptr(u8)+len)
  → scan_document          ✅ does not exist
  → lex_island             ✅ native_lexer.mlua works
  → parse_island           ⚠️  native_core.mlua has SKIP stubs
  → parse_module           ⚠️  same SKIP stubs for regions/blocks/switch
  → open_expand            ✅ does not exist
  → open_facts/validate   ✅ does not exist
  → typecheck              ✅ does not exist
  → layout_resolve         ✅ does not exist
  → control_facts          ⚠️  back/control.mlua is a partial skeleton
  → control_validate       ✅ does not exist
  → control_lower          ✅ does not exist
  → type_abi_classify      ⚠️  back/ops.mlua has scalar_to_back, no ABI plan
  → func_abi_plan          ✅ does not exist
  → expr_lower             ⚠️  6/18 expr types, REF is placeholder
  → stmt_lower             ⚠️  4/15 stmt types, duplicates expr_lower
  → cmd producers           ⚠️  7/60 Cmd variants
  → back_validate          ✅ complete
  → vec facts/decide/plan   ⚠️  skeletons with hardcoded constants
  → vec lower              ⚠️  emits trivial loop, no real vector ops
  → driver/lower_wire      ⚠️  skips semantic phases, has MW_UNSUPPORTED
  → backend FFI            ✅ works
```

The current `host_mom.lua` pipeline goes directly from parser tape to MLBT
wire, skipping every semantic phase. This is the core gap.

---

## 2. Compromise Inventory

Every compromise found in the current MOM code, with file and line number.

### 2.1 Parser SKIP stubs

| Stub | File:Line | What it skips |
|------|-----------|---------------|
| `EX_CONTROL_SKIP=16` | `parser/native_core.mlua:123` | Region/block/switch expressions parsed as opaque token ranges |
| `ST_CONTROL_SKIP=11` | `parser/native_core.mlua:138` | Region/block statements parsed as opaque token ranges |
| `ST_EMIT_SKIP=12` | `parser/native_core.mlua:139` | Emit statements parsed as opaque token ranges |
| `ST_SWITCH_SKIP=13` | `parser/native_core.mlua:140` | Switch statements parsed as opaque token ranges |

**Impact:** No MOM code can see inside regions, blocks, switches, or emits.
The parser records the token range and skips the interior entirely.

**Fix:** Implement `parse_region`, `parse_block`, `parse_switch`, `parse_emit`
as full AST-producing functions. Each produces typed AST nodes with block
params, continuation lists, arm lists, and body statements.

### 2.2 Expression lowering placeholders

| Placeholder | File:Line | What it does |
|-------------|-----------|---------------|
| REF placeholder constant | `back/expr_lower.mlua:220` | Emits `i32` constant instead of env lookup |
| Fallback placeholder | `back/stmt_lower.mlua:340` | Emits placeholder constant for unhandled expr tags |
| HARDCODED B_I32 | `back/expr_lower.mlua` throughout | Reads no type tape, assumes i32 |

**Impact:** Lowered code is wrong for any ref, cast, call, dot, index, deref,
addr, len, view, logic, if-expr, switch-expr, or control expression.

**Fix:** Full env-aware expression lowering that reads type info from the
typed AST, looks up locals in `back/env.mlua`, and produces real Cmd sequences.

### 2.3 Statement lowering placeholders

| Placeholder | File:Line | What it does |
|-------------|-----------|---------------|
| 230 lines of duplicated expr_lower | `back/stmt_lower.mlua:1-230` | Copy-paste of expr_lower.mlua |
| Block IDs share value allocator | `back/stmt_lower.mlua:370-415` | `mb_fresh_val` used for block IDs |
| Only 4/15 stmt types | `back/stmt_lower.mlua` | Handles return_void, return_value, expr, if only |

**Impact:** Can't lower let, var, set, switch, jump, yield, or any control
construct as a statement.

**Fix:** Import expr_lower functions instead of duplicating. Separate block ID
allocator. Implement all missing statement types.

### 2.4 Command producers

| Gap | File | Current |
|-----|------|---------|
| Only 7/60 Cmd variants | `back/cmd.mlua` | IntBinary, FloatBinary, BitBinary, Shift, Unary, Compare, Cast, Trap |

**Missing Cmd variants (53):**
TargetModel, CreateSig, DeclareData, DataInitZero, DataInit, DataAddr,
FuncAddr, ExternAddr, DeclareFunc, DeclareExtern, BeginFunc, CreateBlock,
SwitchToBlock, SealBlock, BindEntryParams, AppendBlockParam, CreateStackSlot,
StackAddr, Alias, Const, Intrinsic, PtrOffset, LoadInfo, StoreInfo,
AtomicLoad, AtomicStore, AtomicRmw, AtomicCas, AtomicFence, BitNot, Rotate,
AliasFact, Memcpy, Memset, Select, Fma, VecSplat, VecBinary, VecCompare,
VecSelect, VecInsertLane, VecExtractLane, Call, Jump, BrIf, SwitchInt,
ReturnVoid, ReturnValue, FinishFunc, FinalizeModule, TargetModel (declarative).

**Fix:** Implement each Cmd variant as a pure constructor `func` per
PORTING_GUIDE §5.3. Each returns a Cmd value — no accumulation, no side
effects.

### 2.5 Driver skips semantic phases

| Issue | File:Line | What it does |
|-------|-----------|---------------|
| Direct parser→wire | `driver/lower_wire.mlua` | Goes from parser tape to MLBT wire, skipping typecheck, layout, control |
| MW_UNSUPPORTED x7 | `driver/lower_wire.mlua:302-337` | Float literals, unresolved refs, unsupported unary/binary/compare ops become placeholder wire commands |
| back/ not wired | `host_mom.lua:117-120` | Only lexer, parser, lower_wire, backend_ffi are compiled and called |

**Fix:** Once semantic phases exist, insert them between parse and wire.
Rewire `host_mom.lua` to call each phase in order.

### 2.6 Vec pipeline skeletons

| Issue | File:Line | What it does |
|-------|-----------|---------------|
| Hardcoded lane count 4 | `vec/vec_lower.mlua:96-99` | Trivial loop, no real vector ops |
| Hardcoded B_I32 element | `vec/vec_decide.mlua:67` | No type awareness |
| First param = induction | `vec/vec_facts.mlua:63-77` | No real loop recognition |
| Trivial heuristic | `vec/vec_plan.mlua` | More stores → MAP, more reductions → REDUCE |

**Fix:** Port `vec_loop_facts.lua`, `vec_loop_decide.lua`,
`vec_kernel_plan.lua`, `vec_kernel_to_back.lua` from Lua. Each becomes a
MOM region/func producing typed fact/decision/plan/command tapes.

### 2.7 Missing directories

| Directory | Purpose | PORTING_GUIDE ref |
|-----------|---------|-------------------|
| `open/` | Fragment expansion, splice resolution, import resolution | §13.4 |
| `typecheck/` | Type checking: expr, place, stmt, control, func, module | §13.5 |
| `layout/` | Semantic layout resolve: struct/union fields, storage metadata | §13.6 |

These three directories need to be created and populated before the pipeline
can produce correct typed AST for lowering.

---

## 3. Execution Order

Dependencies determine order. Each phase produces output consumed by the
next. A phase cannot be started until its inputs exist.

### Phase 0: Schema ✅ (done)

Schema files in `mom/schema/` define all ASDL types as Moonlift struct/union.
9 of 12 are complete. 3 (MoonEditor, MoonLsp, MoonRpc) are stubs — not needed
for compiler core.

### Phase 1: Fix the parser

**Current state:** Lexer works. Parser has SKIP stubs for regions, blocks,
switches, and emits. Parse-event pass exists but is shallow.

**What to do:**
1. Add real `parse_region`, `parse_block`, `parse_switch`, `parse_emit`
   functions to `parser/native_core.mlua`
2. Each produces typed AST nodes: `StmtBlock`, `StmtJump`, `StmtYield`,
   `StmtSwitch`, `StmtControl`, `ExprRegion`, `ExprControl`, `ExprBlock`
3. Remove `EX_CONTROL_SKIP`, `ST_CONTROL_SKIP`, `ST_EMIT_SKIP`,
   `ST_SWITCH_SKIP` constants entirely
4. Add tests for each new parse function

**Test:** Parse every construct in `SOURCE_GRAMMAR.md` and verify the AST
tape matches what the Lua PVM pipeline produces for the same source.

### Phase 2: Document scanner

**Current state:** `parser/source_scan.mlua` does not exist.

**What to do:**
1. Create `parser/source_scan.mlua`
2. Implement `scan_document(src) -> DocumentParts` for `.mlua` island discovery
3. Skip Lua strings/comments/long brackets, find Moonlift islands,
   record island kind + byte range + name hint
4. For pure `.moon`, produce one synthetic module island

**Test:** Scan `.mlua` files with islands, verify island offsets match
what the Lua PVM scanner produces.

### Phase 3: Open expansion

**Current state:** `open/` directory does not exist.

**What to do:**
1. Create `open/open_facts.mlua` — walk AST, find SpliceSlot, FragmentUse,
   Import nodes → fact tape
2. Create `open/open_validate.mlua` — check fill types, region param arity,
   import resolution → issue tape
3. Create `open/open_expand.mlua` — rewrite StmtUseRegionFrag → inlined
   region body with fresh ids; ExprOpenSlot → resolved value; strip open
   constructs

**Test:** Expand fragments from the Lua PVM test suite, verify output matches.

### Phase 4: Typecheck

**Current state:** `typecheck/` directory does not exist.

**What to do:** (per PORTING_GUIDE §13.5)
1. `typecheck/type_env.mlua` — typed env stack, module bindings,
   `func lookup(name) -> Type`
2. `typecheck/type_scalar.mlua` — integer literal adoption, scalar predicates
3. `typecheck/type_expr.mlua` — recursive descent over Expr tags
4. `typecheck/type_place.mlua` — place subexpression typing
5. `typecheck/type_stmt.mlua` — Stmt → typed Stmt + flow (FallsThrough/Terminates)
6. `typecheck/type_control.mlua` — region param bindings, block param validation
7. `typecheck/type_func.mlua` — function-level typecheck orchestration
8. `typecheck/type_module.mlua` — module-level typecheck entry point

**Test:** Typecheck every test case from `tree_typecheck.lua` and verify
issues and typed AST match.

### Phase 5: Layout resolve

**Current state:** `layout/` directory does not exist.

**What to do:** (per PORTING_GUIDE §13.6)
1. `layout/layout_env.mlua` — type → storage info mappings
2. `layout/layout_field.mlua` — struct/union field offset computation
3. `layout/layout_resolve.mlua` — rewrite pass: TypeRef → LayoutEntry,
   ExprDot → ExprField(offset), view/domain/index → layout-aware forms

**Test:** Resolve layouts from Lua PVM test cases, verify offsets match.

### Phase 6: ABI helpers

**Current state:** `back/ops.mlua` has `mb_type_to_back_scalar`. No ABI plan.

**What to do:** (per PORTING_GUIDE §13.7)
1. `back/back_abi.mlua` — `abi_classify`, `func_abi_plan`,
   `type_to_back_scalar` (consolidate from ops.mlua)

**Test:** Compare ABI results with Lua `type_abi_classify.lua` and
`type_func_abi_plan.lua` for every scalar and function type.

### Phase 7: Command producers (complete)

**Current state:** `back/cmd.mlua` has 7 of ~60 Cmd variants.

**What to do:** Implement all missing Cmd variant constructors. Each is a
pure `func` returning a Cmd value (tag + fields). Organized by group:

- **CFG:** CreateBlock, SwitchToBlock, SealBlock, BindEntryParams,
  AppendBlockParam, Jump, BrIf, SwitchInt
- **Function:** CreateSig, DeclareFunc, DeclareExtern, BeginFunc,
  ReturnVoid, ReturnValue, FinishFunc, FinalizeModule
- **Data:** TargetModel, DeclareData, DataInitZero, DataInit, DataAddr,
  FuncAddr, ExternAddr
- **SSA:** Const, CreateStackSlot, StackAddr, Alias
- **Arithmetic:** BitNot, Rotate, Fma, Select
- **Memory:** LoadInfo, StoreInfo, PtrOffset, Memcpy, Memset,
  AtomicLoad, AtomicStore, AtomicRmw, AtomicCas, AtomicFence
- **Call:** Call, Intrinsic
- **Vector:** VecSplat, VecBinary, VecCompare, VecSelect,
  VecInsertLane, VecExtractLane
- **Facts:** AliasFact

**Test:** For each group, verify Cmd encoding/decoding round-trip through
the wire format.

### Phase 8: Expression lowering (complete)

**Current state:** `back/expr_lower.mlua` handles 6/18 types. REF is a
placeholder constant.

**What to do:** (per PORTING_GUIDE §13.8 and the expression inventory table)
1. Remove placeholder ref lowering — implement real env lookup via `back/env.mlua`
2. Read scalar types from type tape — no hardcoded B_I32
3. Implement: CAST, CALL, DOT, INDEX, DEREF, ADDR, LEN, VIEW, LOGIC,
   IF-EXPR, SWITCH-EXPR, SELECT-EXPR, CONTROL-EXPR, BLOCK-EXPR, FIELD-EXPR
4. Import these from stmt_lower instead of duplicating

**Test:** Lower each expression type and compare Cmd tape with Lua
`tree_to_back.lua` output for the same source.

### Phase 9: Statement lowering (complete)

**Current state:** `back/stmt_lower.mlua` handles 4/15 types, duplicates
expr_lower, shares value IDs with block IDs.

**What to do:** (per PORTING_GUIDE §13.8)
1. Remove code duplication — import from expr_lower
2. Separate block ID allocator from value ID allocator (use `back/ids.mlua`)
3. Implement: LET, VAR, SET, SWITCH, JUMP, YIELD_VOID, YIELD_VALUE,
   CONTROL, EXPR (call-as-statement)
4. Implement `Flow = FallsThrough | Terminates` result tracking

**Test:** Lower each statement type and verify CFG shape (block creation,
branch, seal, jump args).

### Phase 10: Control analysis and lowering

**Current state:** `back/control.mlua` has a simplified fact extractor.
No validation. No lowering.

**What to do:** (per PORTING_GUIDE §13.9)
1. `back/back_control_facts.mlua` — extract ControlFact tape from typed AST
2. `back/back_control_validate.mlua` — validate region fact tape
3. `back/back_control_lower.mlua` — lower control regions to target Cmd CFG:
   allocate nonce/block prefix, create all target blocks and params upfront,
   lower entry initializers, for each control block: switch to block,
   bind params, lower body, require termination

**Test:** Compare control lowering output with `tree_control_to_back.lua`
for every region test case.

### Phase 11: Function and module lowering

**Current state:** No `back/back_func.mlua` or `back/back_module.mlua`.

**What to do:**
1. `back/back_func.mlua` — ABI plan for function entry, parameter binding,
   return mode, stack slot allocation
2. `back/back_module.mlua` — item hoisting, externs, globals,
   FinalizeModule emission

### Phase 12: Wire the pipeline

**Current state:** `host_mom.lua` goes lex → parse → lower_wire → backend.
`lower_wire.mlua` skips all semantic phases.

**What to do:**
1. Insert semantic phases into the pipeline:
   ```
   lex → parse → open_expand → typecheck → layout_resolve
   → control_facts → back_lower (expr+stmt+control+func+module)
   → back_validate → lower_wire → backend
   ```
2. Each phase is a JIT-compiled `.mlua` module loaded via `compile_mod`
3. `lower_wire.mlua` becomes a thin serialization of BackProgram → MLBT v3
4. Remove all `MW_UNSUPPORTED` markers
5. `host_mom.lua` compiles and calls each phase in order

**Test:** End-to-end: source → native execution for every test in the
Lua PVM test suite that types under the current grammar.

### Phase 13: Vectorization (real)

**Current state:** `vec/*.mlua` are skeletons with hardcoded constants.

**What to do:** (per PORTING_GUIDE §13.10)
1. `vec/vec_facts.mlua` — real loop recognition: induction variable,
   stride, trip count, exit condition, alias analysis
2. `vec/vec_decide.mlua` — legality check over facts and target model,
   read element type from typed AST, not hardcoded B_I32
3. `vec/vec_plan.mlua` — construct VecKernelPlan for map/reduce/algebraic
4. `vec/vec_lower.mlua` — emit real vector Cmds: VecSplat, VecBinary,
   VecCompare, VecSelect, VecInsertLane, VecExtractLane
5. `vec/vec_validate.mlua` — verify vector kernel correctness

**Test:** Compare vectorization output with Lua `vec_to_back.lua` for
every vectorizable loop test case.

### Phase 14: Island/document scanner

**Current state:** `parser/source_scan.mlua` does not exist.

**What to do:** (per PARSER_DESIGN §6)
- Skip Lua strings/comments/long brackets
- Find Moonlift island keywords in allowed positions
- Track balanced `end` inside islands
- Record island kind, byte range, name hint
- For pure `.moon`, create one synthetic module island

### Phase 15: Object and shared library emission from native pipeline

**Current state:** `host_mom.emit_object` works through MOM wire format.
No `emit_shared` equivalent for the native pipeline.

**What to do:**
1. `driver/object_driver.mlua` — validated BackProgram → relocatable .o
2. `driver/shared_driver.mlua` — validated BackProgram → .so/.dylib via link plan
3. Expose through `moon.emit_object` and `moon.emit_shared` for the native path

---

## 4. Module Organization (per PORTING_GUIDE §14)

```
lua/moonlift/mom/
  runtime/       builders.mlua, sets.mlua, arena.mlua, strings.mlua, diag.mlua
  parser/        native_lexer.mlua, native_core.mlua, source_scan.mlua,
                 parse_cursor.mlua, parse_type.mlua, parse_expr.mlua,
                 parse_stmt.mlua, parse_item.mlua, parse_module.mlua,
                 parse_splice.mlua
  open/          open_facts.mlua, open_validate.mlua, open_expand.mlua
  typecheck/     type_env.mlua, type_scalar.mlua, type_expr.mlua,
                 type_place.mlua, type_stmt.mlua, type_control.mlua,
                 type_func.mlua, type_module.mlua
  layout/         layout_env.mlua, layout_type.mlua, layout_field.mlua,
                 layout_resolve.mlua
  back/          back_ids.mlua, back_env.mlua, back_ops.mlua, back_abi.mlua,
                 back_memory.mlua, back_address.mlua, back_cmd.mlua,
                 back_expr.mlua, back_stmt.mlua, back_control_facts.mlua,
                 back_control_validate.mlua, back_control_lower.mlua,
                 back_func.mlua, back_module.mlua, back_validate.mlua
  vec/           vec_facts.mlua, vec_decide.mlua, vec_plan.mlua,
                 vec_lower.mlua, vec_validate.mlua
  driver/        compile_module.mlua, jit_driver.mlua, wire.mlua,
                 lower_wire.mlua, backend_ffi.mlua, object_driver.mlua,
                 diagnostics.mlua
  schema/        (existing)
  tests/         test_parser_*.lua, test_type_*.lua, test_back_*.lua,
                 test_vec_*.lua, test_pipeline_*.lua
```

---

## 5. Naming Convention (per PORTING_GUIDE §14.4)

| Layer | Prefix | Example |
|--------|---------|---------|
| parser | `mp_` | `mp_parse_expr`, `mp_accept` |
| open | `mo_` | `mo_expand_stmt` |
| typecheck | `mt_` | `mt_type_expr` |
| layout | `ml_` | `ml_resolve_field` |
| backend lowering | `mb_` | `mb_lower_expr` |
| control lowering | `mc_` | `mc_lower_region` |
| vector | `mv_` | `mv_plan_kernel` |
| validation | `mbv_` | `mbv_validate_cmds` |
| runtime/util | `mr_` | `mr_push_issue` |

---

## 6. Verification Discipline

After each phase, run these checks before moving on:

1. **Unit test:** Every new `.mlua` module has a focused test harness
2. **Comparison test:** Output matches Lua PVM pipeline for same input
3. **Wire format:** BackProgram validates through `back_validate.mlua`
4. **JIT execution:** Compiled code produces correct results
5. **No forbidden framing:** No "for now", "temporary", "bridge" in code or docs
6. **Module boundary:** Each module is one of: data schema, pure helper,
   builder, compiler phase, or driver

---

## 7. Estimated Scope

| Phase | New Files | Estimated LOC | Depends On |
|-------|-----------|-------------|------------|
| 1. Parser fixes | 0 (extend native_core) | ~500 | Phase 0 |
| 2. Document scanner | 1 | ~300 | Phase 1 |
| 3. Open expansion | 3 | ~600 | Phase 1 |
| 4. Typecheck | 8 | ~3000 | Phase 3 |
| 5. Layout resolve | 3 | ~800 | Phase 4 |
| 6. ABI helpers | 1 | ~300 | Phase 4 |
| 7. Command producers | 0 (extend cmd.mlua) | ~800 | Phase 0 |
| 8. Expression lowering | 0 (rewrite expr_lower) | ~600 | Phases 4,6,7 |
| 9. Statement lowering | 0 (rewrite stmt_lower) | ~500 | Phase 8 |
| 10. Control analysis | 2 | ~600 | Phase 9 |
| 11. Function/module lowering | 2 | ~800 | Phases 8,9,10 |
| 12. Wire pipeline | 0 (rewrite host_mom, lower_wire) | ~400 | Phases 3-11 |
| 13. Vectorization | 0 (rewrite vec/) | ~1500 | Phase 11 |
| 14. Island scanner | 1 | ~400 | Phase 2 |
| **Total** | **~21 new files** | **~10,500 LOC** | |