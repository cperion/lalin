# Stencil Backend Progress

This is the working checklist for the Lalin stencil backend. It is the source of
truth for current backend progress and remaining work.

Date: 2026-06-29

## Current Backend Shape

```text
Lalin source / DSL
  -> LalinTree
  -> LalinCode + kernel facts
  -> stencil descriptors / artifacts
  -> prebuilt residual_mc bank entry
  -> TCC residual glue
```

- [x] MC is the default fast backend.
- [x] Missing MC artifacts are hard materialization diagnostics, not implicit BC
  fallback.
- [x] BC remains available as an explicit residual mode and semantic probe.

## Closed In Current Pass

- [x] Remove the false `i32` scalar-family gap in the generated MC intern set.
- [x] Generate scalar cells for signed/unsigned integer widths, `index`, `f32`,
  `f64`, and `bool8` inside the current point-expression envelope.
- [x] Use an uncapped default saturation envelope:
  point arity 3, point stage depth 1, and two-node `Store -> Sink` metastencils.
- [x] Keep `LALIN_MC_BANK_MAX_CELLS` only as an explicit probe/test override.
- [x] Make reducer legality scalar-family aware:
  integer/index `add/mul/min/max/and/or/xor`, float `add/mul/min/max`, bool8
  `and/or/xor`.
- [x] Generate all-family scalar casts within the current scalar surface.
- [x] Add tests for scalar reducer coverage and representative late scalar cast
  cells.
- [x] Record the measured default envelope:
  `2,202,215` cells before sharding, with `294,967` primitive/probe cells and
  `1,907,248` composed `Store -> Sink` cells.
- [x] Verify `luajit tests/run.lua code_ir`:
  `41 passed, 1 skipped, 0 failed`.

## Current Focus

Source loops must feed the stencil descriptor surface we already represent.

- [x] Add parsed fixture programs for gather/indexed reads.
- [x] Add parsed fixture programs for scatter writes.
- [x] Add parsed fixture programs for scatter-reduce.
- [x] Add parsed fixture programs for dynamic affine ND indexing.
- [x] Add parsed fixture programs for predicate composition.
- [x] For each runnable backend fixture, assert whether it should become a
  stencil artifact or a typed reject.
- [ ] Add matching DSL fixture assertions where DSL coverage is not already
  stronger than the parsed coverage.
- [ ] Replace backend errors/no-selection sentinels with typed rejects where a
  source loop is not legal.
- [ ] Predicate-composition source fixture parses, but backend planning hangs;
  fix before enabling it as a backend fixture.
- [ ] Dynamic affine ND transpose source fixture reaches backend planning but
  crashes in affine layout extraction.
- [ ] Fix the first layer that loses the required fact:
  frontend lowering, kernel facts, stencil rule selection, artifact planning,
  MC bank lookup, or materialization.

## Open Checklist

### 1. Source-To-Stencil Coverage

- [ ] Recognize non-primary indexing as gather/indexed reads where legal.
- [ ] Recognize broader scatter patterns.
- [ ] Recognize broader scatter-reduce patterns.
- [ ] Generalize dynamic affine ND indexing beyond compact row-major and
  selected constant cases.
- [ ] Lower source predicate composition into `StencilPredAnd`,
  `StencilPredOr`, and `StencilPredNot`.
- [ ] Lower source range predicates into `StencilPredRange`.
- [ ] Lower float-class predicates into `StencilPredIsNaN`,
  `StencilPredIsInf`, and `StencilPredIsFinite`.
- [ ] Feed alias contracts from source into stencil facts.
- [ ] Feed alignment contracts from source into stencil facts.
- [ ] Feed bounds contracts from source into stencil facts.
- [ ] Feed readonly/writeonly/noalias contracts from source into stencil facts.
- [ ] Produce stable typed reject reasons when a loop does not become a stencil.

### 2. Layout And Descriptor Runtime Coverage

- [ ] Add runtime tests for view dynamic length and stride.
- [ ] Add runtime tests for slice dynamic length.
- [ ] Add runtime tests for byte-span dynamic length.
- [ ] Add runtime tests for field projection descriptors.
- [ ] Add runtime tests for SoA component descriptors.
- [ ] Add zero-length descriptor tests.
- [ ] Add descriptor aliasing tests.
- [ ] Add descriptor length versus loop-bound tests.
- [ ] Prove frontend extraction of `data`, `len`, and `stride` survives into
  descriptors.

### 3. Gather, Scatter, And Index Role Semantics

- [ ] Decide whether non-`i32` index element types are supported.
- [ ] Add runtime tests for all allowed index element types.
- [ ] Add bounds behavior tests for indexed reads.
- [ ] Add bounds behavior tests for indexed writes.
- [ ] Add alias interaction tests for indexed read/write.
- [ ] Implement/test scatter unique-index semantics.
- [ ] Implement/test scatter last-write semantics.
- [ ] Implement/test scatter undefined-conflict semantics, or document it as a
  permanent reject.
- [ ] Implement atomic scatter-reduce lowering, or keep it as a typed reject.
- [ ] Implement privatized scatter-reduce lowering, or keep it as a typed
  reject.

### 4. Schedule And Proof Consumption

- [ ] Compare requested versus realized MC vectorization.
- [ ] Add runtime/disassembly checks that alignment facts affect emitted code.
- [ ] Consume alias facts as C `restrict` where legal.
- [ ] Add tests where exact trip-count facts remove tail handling.
- [ ] Add tests where trip-count-multiple facts remove tail handling.
- [ ] Reject unsafe schedules when required proof obligations are absent.
- [ ] Add query tests over realized schedule metadata in emitted banks.

### 5. Predicate And Operator Completeness Tests

- [ ] Add embedded-bank coverage for every predicate constructor.
- [ ] Add artifact-level tests for every supported unary op/type pair.
- [ ] Add artifact-level tests for every supported binary op/type pair.
- [ ] Add artifact-level tests for every supported cast pair.
- [ ] Add artifact-level tests for select expressions.
- [ ] Add artifact-level tests for every supported reduction pair.
- [ ] Add scan tests for every supported reduction pair.
- [ ] Add exclusive scan end-to-end tests.
- [ ] Add count tests over all predicate kinds.
- [ ] Add find tests over all predicate kinds and supported scalar types.
- [ ] Add partition tests over all predicate kinds.

### 6. Longer Metastencil DAG Fusion

- [ ] Define the next metastencil DAG vocabulary beyond two-node
  `Store -> Sink`.
- [ ] Implement point-stage-to-point-stage fusion.
- [ ] Implement point-stage-to-scan fusion.
- [ ] Implement scan-to-store or scan-to-sink fusion where legal.
- [ ] Add fusion legality facts for aliasing.
- [ ] Add fusion legality facts for layout compatibility.
- [ ] Add fusion legality facts for trip-count compatibility.
- [ ] Add fusion legality facts for schedule compatibility.
- [ ] Add fusion legality facts for integer/float/reduction semantics.
- [ ] Select the longest legal cover over real kernel plans.
- [ ] Benchmark fused DAGs against primitive sequences and handwritten C.

### 7. BC Semantic Probe Gaps

- [ ] Implement BC execution for `WindowND`, or keep a typed reject with focused
  tests.
- [ ] Implement BC execution for `TiledND`, or keep a typed reject with focused
  tests.
- [ ] Replace string unsupported reasons in BC/LuaTrace paths with structured
  ASDL reject facts.
- [ ] Add BC semantic probe tests for every represented producer/body/sink cell
  that should not require MC.

### 8. Deployment Bank Validation

- [ ] Rebuild `target/lalin` with the expanded default bank.
- [ ] Run `LALIN_RUN_SLOW=1 luajit tests/code_ir/test_lalin_binary.lua`.
- [ ] Record final binary size.
- [ ] Record full bank build time.
- [ ] Check embedded descriptor/fingerprint sets.
- [ ] Make startup diagnostics for missing bank cells visible.
- [ ] Make startup diagnostics for stale bank cells visible.
- [ ] Make startup diagnostics for rejected bank cells visible.

## Recommended Next Pass

- [ ] Start with source loops -> stencil descriptor coverage for
  gather/scatter/indexing.
- [ ] Add fixtures first, then fix the earliest failing layer.
- [ ] Keep this file updated as each fixture moves from missing to artifact or
  typed reject.
