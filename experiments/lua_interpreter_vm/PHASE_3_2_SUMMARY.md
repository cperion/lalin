# Phase 3.2: Evidence-Driven Stencil Selection and Closure — Complete

## What Phase 3.2 Does

Phase 3.2 implements **bounded-arity offline closure** of the Phase 1 stencil library.

The goal: Use real program evidence to identify which stencil compositions are worth keeping, building a finite multi-layer library that grows by:

```
L0 = 11 primitives (phase 1 basic stencils)
L1 = close_4(L0) with evidence-driven pruning → select and promote best compounds
L2 = close_4(L1) with evidence-driven pruning
L3 = close_4(L2) with evidence-driven pruning
```

With max_arity = 4, closure depth gives exponential coverage:
- depth 0: 1 original op
- depth 1: up to 4 original ops
- depth 2: up to 16 original ops
- depth 3: up to 64 original ops

## Core Modules Implemented

### 1. `library_indexer.lua`
**Responsibility:** Load and index stencil library for fast runtime matching

Functions:
- `load_library()` — Load all stencils (Phase 1 library)
- `build_indexes(library)` — Create runtime lookup tables:
  - `by_name` — O(1) name lookup
  - `by_first_op` — O(1) by opcode, sorted by benefit (greedy)
  - `by_arity` — Group by operation count (1, 4, 16, 64)
  - `by_depth` — Group by closure depth (0, 1, 2, 3)
  - `by_op_sequence` — Exact opcode pattern matching
- `candidates_for_pattern()` — Query library for pattern candidates
- `report_library()` — Diagnostic summary

Key insight: Indexes enable bounded maximal matching at runtime without searching entire library.

### 2. `evidence_selector.lua`
**Responsibility:** Score stencils against mined program evidence, apply Pareto frontier pruning

Functions:
- `score_stencil_against_evidence()` — Multi-dimensional scoring:
  - execution_benefit = saved_ops × frequency
  - static_benefit = from Phase 1 construction
  - code_size_cost, hole_cost, reloc_cost
  - net_benefit = benefits - costs
- `select_candidates_for_evidence()` — For each evidence pattern, find matching stencils and score them
- `pareto_frontier()` — Eliminate dominated stencils on Pareto frontier across:
  - net_benefit (higher is better)
  - code_size_cost (lower is better)
  - efficiency (higher is better)
- `report_selection()` — Diagnostic output

Key insight: Evidence-driven selection focuses library growth on observable patterns, not speculation.

### 3. `closure_round_builder.lua`
**Responsibility:** Generate closure candidates, rank by evidence, build runtime pattern library

Functions:
- `can_compose()` — Check structural compatibility (hard gates):
  - max_total_ops ≤ 30
  - max_total_size ≤ 350 bytes
  - max_holes ≤ 20
  - max_relocs ≤ 15
- `compose_stencils()` — Create compound from two atoms, estimate benefit
- `generate_closure_candidates()` — Greedy pairwise composition of atoms (limited to top 20 by benefit)
- `rank_candidates_by_evidence()` — Score candidates by match count and total evidence hits
- `build_pattern_library()` — Create `StencilPattern` index for runtime selector
- `report_closure_round()` — Diagnostic summary

Key insight: Composition is bounded (arity ≤ 4) but greedy (selects high-benefit atoms first).

## Test Coverage

### `test_phase3_2_selection.lua`
Tests individual components:
- TEST 1: Load library ✓
- TEST 2: Build indexes ✓
- TEST 3: Query by pattern ✓
- TEST 4: Score stencils ✓
- TEST 5: Evidence-driven selection ✓
- TEST 6: Pareto frontier pruning ✓
- TEST 7: Library composition analysis ✓
- TEST 8: Full pipeline ✓

Results: 16 stencils loaded, 10 opcode indexes, selection and scoring working correctly.

### `test_phase3_2_full_pipeline.lua`
Tests complete workflow:
1. Load Phase 1 library (16 stencils: 11 primitives + 5 compounds)
2. Build runtime indexes (10 unique opcodes)
3. Analyze mined evidence (6 patterns)
4. Select via Pareto frontier (12 candidates → 5 on frontier)
5. Generate closure round 1 (40 candidates from L0 primitives)
6. Rank by evidence relevance
7. Build StencilPattern library for runtime

Results: Full pipeline working, closure generation demonstrating arity constraints.

## What Stays Finite

The library never explodes because:
1. **Arity constraint:** max_arity = 4 limits each composition to 4 inputs
2. **Depth constraint:** max_depth = 3 limits closure rounds to 3
3. **Policy gates:** Hard rejection on size, holes, relocs budgets
4. **Evidence filtering:** Only promote compounds matching observed patterns
5. **Pareto pruning:** Eliminate dominated candidates across cost/benefit/size

Expected sizes:
- L0: 11 primitives (Phase 1 hand-written)
- L1: ~50-100 compounds (from greedy pairs of L0)
- L2: ~100-200 compounds (from compositions of L0+L1)
- L3: ~200-300 compounds (from compositions of L0+L1+L2)

**Total shipped library: ≤500 stencils** (compared to infinite bytecode n-grams)

## Offline vs Runtime Boundary

**OFFLINE (Phase 3.2 work — build-time)**
```
evidence patterns
  + library atoms
  -> compose candidates
  -> rank by benefit
  -> hard gates
  -> Pareto frontier
  -> select top K
  -> promote back to library
  -> repeat L0 → L1 → L2 → L3
```

**RUNTIME (uses result)**
```
TraceRecord
  + StencilPatternLibrary indexes
  -> maximal matching (select largest stencil)
  -> verify facts/effects/deps
  -> materialize
  -> link
```

Runtime NEVER:
- Generates new stencil shapes
- Runs closure operations
- Invokes Cranelift or Moonlift compiler
- Creates ad-hoc instruction sequences

## Integration Points (Next Phases)

### Phase 3.3: Ring 0 Boundary Stencils
Add explicit materialization of:
- Entry/exit stencils for VM → JIT transitions
- Projection stencils for deopt/snapshot recovery
- Boundary stencils for GC/allocation safe points

### Phase 4: Runtime Trace Integration
Wire trace recording into VM loop:
- Record hot paths as `TraceRecord` products
- Use StencilPatternLibrary for matching
- Materialize selected stencil plan
- Link via EntryCell/EdgeCell

### Phase 5+: Multi-Round Closure
Implement full L0 → L1 → L2 → L3 iteration:
- Build L1 from L0 + evidence
- Promote best L1 compounds
- Build L2 from L0+L1 + evidence
- Continue until no new profitable compounds

## Key Files

- `src/jit/library_indexer.lua` — Load and index stencil library
- `src/jit/evidence_selector.lua` — Score and select stencils
- `src/jit/closure_round_builder.lua` — Generate and rank closure candidates
- `tests/test_phase3_2_selection.lua` — Component tests
- `tests/test_phase3_2_full_pipeline.lua` — End-to-end pipeline
- `PHASE_3_2_SUMMARY.md` — This document

## Verification

Phase 3.2 is complete when:
- ✓ Library loads and builds runtime indexes
- ✓ Evidence patterns match to stencils
- ✓ Stencils score based on execution benefit
- ✓ Pareto frontier correctly eliminates dominated stencils
- ✓ Closure candidates generate and rank correctly
- ✓ StencilPattern library builds for runtime matching
- ✓ Hard policy gates (size, holes, relocs) enforced
- ✓ Both test suites pass

All verified. Phase 3.2 is ready for integration with Phase 3.3 (boundary stencils) and Phase 4 (runtime trace integration).
