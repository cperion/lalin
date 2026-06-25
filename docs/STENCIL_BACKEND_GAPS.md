# Stencil Backend Completeness Gaps

This file tracks the remaining work needed before the LuaJIT copy-patch stencil
backend can honestly be called complete. The current backend is complete for a
useful scalar subset, but not for the full schema space.

## Current Implemented Core

- [x] Stencil type classification for the full representable `CodeType` family
  surface, with `void` rejected as a non-element type.
- [x] Scalar stencil type classification for signed/unsigned integers
  `i8/i16/i32/i64`, `u8/u16/u32/u64`, `f32`, `f64`, `index`, and `bool8`.
- [x] Non-scalar element-lane selection for copy, gather, scatter, and identity
  map across pointer, code-pointer, named, array, descriptor, handle, lease,
  closure, imported C, imported C function-pointer, and vector families.
- [x] Store-family selection for fill, copy, gather, scatter, in-place map,
  map, cast, compare, zip-map, and zip-compare across scalar element types.
- [x] Reduction-family selection for integer add/mul/and/or/xor/min/max.
- [x] Reduction-family selection for float add/mul/min/max.
- [x] Higher reduction selection for map-reduce and zip-reduce over the
  currently supported scalar reduction cells.
- [x] Descriptor/topology representation for contiguous, indexed, in-place,
  field projection, SoA component, slice descriptor, byte-span descriptor, and
  view descriptor.
- [x] LuaTrace emission for the current stencil shape set: reduce, map,
  zip-map, scan, copy, fill, find, partition, cast, compare, zip-compare,
  gather, scatter, in-place map, count, map-reduce, and zip-reduce.
- [x] Embedded MC intern set for the current default scalar matrix and selected
  descriptor families.

## LalinStencil Schema Architecture Gap Register

Severity tags:

- `S`: soundness/correctness; can produce wrong machine code or wrong results.
- `T`: thesis violation; representable illegal states remain representable.
- `K`: stringly-typed/key-join structure where typed references are required.
- `C`: completeness; missing operations, cases, domains, or facts.
- `M`: minor, orphan, or cosmetic schema issue.

### Soundness Gaps

- [x] `A1` `[S]` Make aliasing relational instead of unary.
  `StencilAliasFact` is currently attached to one access through
  `StencilAccessVectorFact.alias`, but aliasing is a pairwise property. This
  cannot express partial disjointness, such as output aliasing input while both
  are disjoint from an index stream. Fix with explicit pairwise alias facts
  keyed by typed access references, or with alias classes where same-class
  accesses may alias and different classes are proven disjoint.
- [x] `A2` `[S]` Add integer and float semantics to element unary/binary ops.
  `StencilOpUnary` and `StencilOpBinary` now carry explicit
  `CodeIntSemantics` / `CodeFloatMode`. The artifact planner fills these facts
  when descriptors are built, and C/LuaTrace shapes preserve them. Integer
  unary negation now materializes wrap semantics through unsigned subtraction
  instead of signed `-x` UB.
- [x] `A3` `[S]` Give predicates explicit comparison signedness/semantics.
  The six string-of-meaning const predicate variants were replaced by
  `StencilPredCompareConst { cmp, operand_ty, value }`, sharing `CmpOp` with
  `StencilOpCompare`. Predicate lowering from kernel plans and stencil rules now
  carries the lane element type, and materializers cast through `operand_ty`.
- [x] `A4` `[S]` Add realized-vs-requested schedule evidence to artifacts.
  `StencilArtifact` now carries `realized [optional StencilRealizedSchedule]`
  and `schedule_rejects`; BC and MC materializers stamp installed/banked
  artifacts with realized scalar/unrolled/vector facts and typed mismatch
  rejects when requested and realized schedules diverge.
- [ ] `A5` `[S]` Constrain reducer `init` against reduction and result type.
  `StencilReducer.init` is an arbitrary `ValueExpr`; for parallel/tree
  reductions it must be the identity for `(reduction, result_ty)`. Fix by
  deriving identities from `(reduction, result_ty)`, or by requiring a typed
  proof obligation that the stored init is the monoid identity.
- [x] `A6` `[S]` Define proof provenance for every unsafe vectorization license.
  `StencilVectorizationFacts` now carries typed `proof_obligations`, each with
  an obligation kind, origin, and optional `KernelProof`. The planner emits
  obligations for noalias pairs, known alignment, unit stride, trip-count
  multiples, and reducer reassociation, with origins split between
  checker-derived, boundary-contract, and author-asserted.

### Representable Illegal States

- [x] `B1` `[T]` Replace optional-bag `StencilDescriptor` with a
  skeleton-keyed descriptor sum. The current product permits invalid
  combinations such as reduce skeleton without reducer, map vocab with reduce
  skeleton, or extra operators on copy. Each descriptor variant should own the
  mandatory fields for its skeleton and make forbidden fields unrepresentable.
- [ ] `B2` `[T]` Remove the unconstrained duplicate operation axis between
  `StencilVocab` and `StencilSkeleton`. Derive one from the other or fold both
  into the descriptor sum so operation name and parallel pattern cannot
  disagree.
- [x] `B3` `[T]` Give memory semantics a single owner. Copy, partition, and
  scatter semantics now live on the descriptor variant that needs them; the
  duplicate `StencilMemorySemantics` schema product was removed.
- [ ] `B4` `[T]` Remove schedule double-encoding. `StencilScheduleVector`
  carries lane policy plus bare lane count, vector schedule unroll plus
  `StencilScheduleUnrolled`, and schedule alignment plus per-access alignment.
  Make lanes derive from policy, separate unroll meaning cleanly, and state how
  schedule alignment relates to access alignment.
- [ ] `B5` `[T]` Constrain compiler policy and vector compiler policy as one
  legal matrix. `StencilCompilerPolicy.compiler` and
  `StencilVectorCompilerPolicy` currently allow incoherent pairs such as clang
  plus gcc-autovec. Fix with a sum or typed reject facts for illegal pairs.

### Stringly-Typed Joins

- [x] `C1` `[K]` Replace `StencilAccessVectorFact.access_name [str]` with a
  typed access reference, access id, or nested facts inside `StencilAccess`.
  `StencilAccessVectorFact` now carries `access [StencilAccessRef]`; planners,
  proof obligations, BC, and MC materializers use that typed ref instead of a
  string join.
- [x] `C2` `[K]` Replace `StencilRejectMissingProof.reason [str]` with a typed
  proof obligation kind. `StencilRejectMissingProof` now carries
  `obligation [StencilProofObligationKind]`, so missing-proof rejects identify
  the exact required proof.
- [x] `C3` `[K]` Rework `StencilParam` as a typed parameter product or boundary
  metadata. `StencilParam` was removed instead: descriptor variants already own
  the typed semantic fields, and `StencilAbi` owns call ABI. There is no longer
  a name-keyed descriptor metadata bag.

### Schema Completeness Gaps

- [x] `D1` `[C]` Decide and encode binary `Div`, `Mod`, `Shl`, and `Shr`.
  Stencil binary ops now include division, modulo, left shift, logical right
  shift, and arithmetic right shift. Core lowering maps `BinDiv`, `BinRem`,
  `BinShl`, `BinLShr`, and `BinAShr`; planner/rule support constrains modulo
  and shifts to integer-like lanes. MC zip-map/zip-reduce materialization uses
  structured `llbl.c` expression nodes with trap guards for integer div/rem and
  masked shift counts; LuaTrace BC uses explicit C-truncating integer div/rem
  helpers for parity.
- [x] `D2` `[C]` Add a select/blend element operator for masked vector bodies,
  branchless partition, and predicate-controlled transforms. `StencilSelect`
  is now a first-class vocab/descriptor with `dst`, `cond`, `then_xs`, and
  `else_xs` accesses, plus `StencilOpSelect` in the element-operator surface.
  Artifact planning, support-matrix coverage, LuaTrace BC, and MC emission all
  materialize predicate-controlled select/blend arrays.
- [ ] `D3` `[C]` State the 1D-only domain scope and future ND/windowed stencil
  direction. `StencilDomain` currently only has `Range1D`, so convolution-style
  domains, tiled/block domains, and neighborhood access are not representable.
- [ ] `D4` `[C]` Add range, compound, and float-class predicates, or document
  their rejection. `find`, `partition`, and `count` need more than const compare
  plus nonzero for real kernels.
- [ ] `D5` `[C]` Add exact static trip-count facts. `Exact{n}` is stronger than
  dynamic or multiple-of and enables full unroll/no-tail decisions.
- [x] `D6` `[C]` Add schedule-level rejects. `StencilScheduleReject` now has
  typed variants for unsupported features, illegal lane counts, unprovable
  tails/alignment, compiler matrix failures, and requested/realized mismatch;
  artifacts carry those rejects next to realized schedule evidence.
- [ ] `D7` `[C]` Record schedule candidates, costs, and winner provenance.
  `StencilSelection` currently records one winner or no winner, but not why a
  valid schedule was chosen over alternatives.
- [ ] `D8` `[C]` Add artifact build-input fingerprints. Cache/bank identity must
  include descriptor, schedule, compiler, flags, target, and generator version,
  not just interned descriptor shape.
- [ ] `D9` `[C]` Capture compiler diagnostics and vectorization remarks on the
  artifact so "did it vectorize, and why not" is queryable from schema facts.

### Orphans And Minor Schema Issues

- [ ] `E1` `[M]` Delete or wire `StencilId`. It is declared but currently
  unused by descriptors or artifacts.
- [x] `E2` `[M]` State or unify the relationship between `StencilDescriptor`
  params and `StencilAbi.params`. Descriptor params were deleted; ABI params
  remain the sole call-boundary representation.
- [ ] `E3` `[M]` Make `StencilArtifact.c_signature` provider-dependent or
  document that every provider seals through a C ABI.
- [ ] `E4` `[M]` Decide whether domain step is compile-time only. `start` and
  `stop` are value expressions, but `step` is a number; runtime stride is
  therefore not representable. Also clarify how domain order relates to copy
  overlap direction.
- [ ] `E5` `[M]` Add an index access role. Gather/scatter index streams have
  different alias/bounds meaning than ordinary read data streams.

### Schema Closure Priority

- [x] First close `A1`: alias must be relational, not unary.
- [x] Then close `B1`: descriptor must become a skeleton-keyed sum.
- [x] Then close `A4` and `D6`: realized schedule evidence and schedule rejects.
- [x] Then close `A6`: proof provenance and proof obligations.
- [x] Then close `A2` and `A3`: arithmetic and comparison semantics.
- [x] Then close `C1` and `C2`: remove string joins from access facts and proof
  rejects.

Open gate question:

- [x] Decide whether `KernelProof`s are always discharged by checker/contract
  layers, or whether schedules may carry author-asserted proofs. If hand
  assertions are allowed, vector schedules must be marked as an explicit trust
  boundary. Current schema makes the trust boundary explicit through
  `StencilProofOrigin`: checker-derived, boundary-contract, or
  author-asserted.

## Type Family Gaps

- [x] Decide the intended stencil element universe: the compiler classifies the
  whole representable `CodeType` surface except `void`.
- [x] Add first-class test coverage that non-scalar types select only the
  type-generic stencil operations that are meaningful today.
- [x] Support `CodeTyVector` as an element family for copy/gather/scatter and
  identity-map selection.
- [x] Support `CodeTyNamed` record elements as whole-record copy/gather/scatter
  and identity-map elements.
- [x] Support `CodeTyArray` elements as whole-array copy/gather/scatter and
  identity-map elements.
- [x] Support `CodeTyDataPtr` elements for pointer-array copy/gather/scatter and
  identity-map use cases.
- [x] Support descriptor-valued elements for copy/gather/scatter and
  identity-map: slices, views, byte spans, and closures.
- [x] Add BC runtime materialization coverage for representative non-scalar
  copy/gather/scatter and identity-map cells: pointer, fixed-array, and
  descriptor-valued elements.
- [x] Add MC runtime materialization coverage for pointer-valued
  copy/gather/scatter and identity-map cells.
- [x] Add MC runtime materialization coverage for named aggregate, imported C
  aggregate, and descriptor-valued copy/identity cells.
- [x] Add MC runtime materialization coverage for fixed-array, closure, imported
  C function-pointer, and vector element cells.
- [ ] Add widening reductions, or document that reductions require
  `elem_ty == result_ty`.
- [ ] Add widening map-reduce and zip-reduce, or document that mapped/result
  types must match through the current reduction contract.
- [ ] Add mixed-type zip-map, or document that lhs/rhs/result types must match.
- [ ] Add mixed-type zip-compare where lhs/rhs differ but comparison is legal.
- [ ] Audit all cast stencil combinations against `MachineCastOp`; current tests
  cover identity and selected numeric casts, not the full cast matrix.
- [ ] Add explicit bool semantics for map/reduce/count beyond the currently
  selected bool8 cells.

## Stencil Vocab Gaps

- [ ] Treat "fold" as an architecture decision: either make it an alias of
  reduce/scan/map-reduce/zip-reduce, or add a first-class `StencilFold` vocab.
- [ ] Add complete tests for every `StencilVocab` constructor in
  `schema/stencil.lua` against selection, artifact planning, LuaTrace emission,
  and MC materialization.
- [ ] Add reduce tests for every supported type/reduction pair at artifact
  emission level, not only rule-selection level.
- [ ] Add scan tests for every supported reduction pair; current scan coverage is
  much thinner than reduce.
- [ ] Add exclusive scan coverage in end-to-end lowering and materialization.
- [ ] Add count coverage for every predicate kind, not only nonzero/selected
  const predicates.
- [ ] Add find coverage for every predicate kind and every supported scalar type.
- [ ] Add partition coverage for every predicate kind and for stable/unstable
  semantics.
- [ ] Implement and test unstable partition semantics if it should differ from
  stable partition.
- [ ] Implement and test all copy semantics:
  no-overlap, may-overlap-forward, may-overlap-backward, memmove.
- [ ] Implement and test all scatter conflict semantics:
  unique-indices, last-write-wins, conflict-undefined.
- [ ] Decide whether gather/scatter should support non-i32 index element types
  beyond the current selected cases.
- [ ] Add gather/scatter runtime tests for all allowed index types.
- [ ] Add map-reduce and zip-reduce coverage for min/max and bitwise reductions,
  not only add-oriented default interned stencils.
- [ ] Add map/zip-map coverage for all unary/binary operators:
  identity, neg, bitnot, boolnot, add, sub, mul, and/or/xor, min, max.
- [ ] Add compare/zip-compare coverage for all `CmpOp` values.
- [ ] Add predicate coverage for all predicate constructors:
  nonzero, eq/ne/lt/le/gt/ge const.

## Descriptor And Topology Gaps

- [ ] Build a vocab-by-topology matrix and decide which cells are supported,
  rejected, or intentionally unreachable.
- [ ] Complete contiguous topology coverage for every supported vocab.
- [ ] Complete indexed topology coverage for every supported vocab.
- [ ] Complete in-place topology coverage beyond in-place map where meaningful.
- [ ] Complete view descriptor coverage for every supported vocab.
- [ ] Complete slice descriptor coverage for every supported vocab.
- [ ] Complete byte-span descriptor coverage beyond u8 copy/fill/find/compare/count.
- [ ] Complete field-projection coverage beyond the current reduce/map/find/
  compare/fill subset.
- [ ] Complete SoA component coverage beyond zip-map/zip-reduce/zip-compare/
  partition.
- [ ] Add nested topology coverage:
  field projection over view/slice, SoA over view/slice, indexed over descriptor.
- [ ] Add dynamic-stride runtime tests for every vocab that accepts view
  descriptors.
- [ ] Add constant-stride view runtime tests for every vocab that accepts view
  descriptors.
- [ ] Add zero-length descriptor tests for slice/view/byte-span.
- [ ] Add negative-stride or backward-domain decision: support, reject, or
  normalize.
- [ ] Add descriptor aliasing tests for copy, map, in-place map, partition, and
  scatter.
- [ ] Add tests that descriptor lengths dominate loop bounds where applicable.
- [ ] Add tests that descriptor data/len/stride extraction survives frontend
  lowering into stencil topology facts.

## Domain And Scheduling Gaps

- [ ] Add support or explicit rejection for backward domains.
- [ ] Add support or explicit rejection for non-unit positive domain steps across
  every vocab.
- [ ] Add schedule coverage for scalar, unrolled, autovector, and fixed-vector
  schedules across every supported vocab.
- [ ] Add masked-tail vs scalar-tail runtime tests.
- [ ] Add trip-count-multiple facts tests for no-tail lowering.
- [ ] Add vectorization facts tests for alias, alignment, unit stride, and
  reduction reassociation.
- [ ] Decide whether strict float reductions should always reject vector/multi
  accumulator plans or only lower to ordered scalar plans.
- [ ] Add coverage for schedule rejection reasons so failed stencil selection is
  diagnosable and stable.

## Copy-Patch BC/MC Materialization Gaps

- [ ] Make the MC intern set generated from an explicit matrix table instead of
  ad hoc hand-enumerated artifact construction.
- [ ] Add a test that compares the declared support matrix against the embedded
  MC intern set.
- [ ] Add a test that every artifact selected by the default lowering path can be
  found in the embedded MC bank, or is deliberately routed to BC fallback.
- [ ] Decide whether BC and MC banks must have identical logical coverage or
  whether BC is the semantic superset and MC is the fast subset.
- [ ] Add artifact-shape hashing/versioning so stale bank entries cannot silently
  satisfy changed descriptors.
- [ ] Add coverage for local relocations in every vectorized MC shape, not only
  selected SoA zip-map/zip-reduce cases.
- [ ] Add tests for MC bank generation with view/slice/byte-span dynamic
  descriptors in the single-binary path.
- [ ] Add tests that generated embedded MC bank count and descriptor set match
  the intended intern matrix.
- [ ] Add tests that static binary startup rejects or reports missing MC bank
  entries cleanly when a selected fast artifact is absent.

## LuaTrace Emission Gaps

- [ ] Replace unsupported-expression errors in LuaTrace constant lowering with
  structured rejects.
- [ ] Add runtime tests for all supported unary operators in LuaTrace output.
- [ ] Add runtime tests for all supported binary operators in LuaTrace output.
- [ ] Add runtime tests for all supported reductions in LuaTrace output.
- [ ] Add runtime tests for all supported predicates and comparisons in LuaTrace
  output.
- [ ] Add byte-exact tests for byte-span copy/fill/count/find/compare.
- [ ] Add tests for dynamic stride parameter ordering in emitted LuaTrace
  functions.
- [ ] Add tests for field-projection source and destination access in LuaTrace.
- [ ] Add tests for SoA component source and destination access in LuaTrace.
- [ ] Add tests for primitive plans: `ffi.copy`, `ffi.fill`, branch predicates,
  numeric predicate fast paths, scatter plans, and reduction plans.
- [ ] Add tests for grouped/unrolled loops with tails for every supported shape.

## Frontend-To-Stencil Lowering Gaps

- [ ] Add end-to-end DSL tests for every supported vocab, not only direct
  artifact-plan tests.
- [ ] Add end-to-end DSL tests for view, slice, byte-span, field projection, and
  SoA contracts for every supported vocab.
- [ ] Add tests that rejected stencil opportunities fall back to generic code
  with a stable reject reason.
- [ ] Add tests for loops with multiple stores/reductions to ensure the selector
  does not silently choose a wrong single-stencil plan.
- [ ] Add tests for reductions returned through different control paths.
- [ ] Add tests for loops with non-primary indexing that should become gather or
  scatter.
- [ ] Add tests for read/write effects and alias contracts controlling copy,
  in-place map, scatter, and partition selection.
- [ ] Add tests for function contracts: bounds, readonly, writeonly, noalias,
  invalidate, preserve, same_len, SoA component.

## Diagnostics And Architecture Gaps

- [ ] Replace stringly reject reasons with ASDL reject facts for stencil
  selection, artifact planning, LuaTrace emission, and MC bank lookup.
- [x] Add a single support matrix file that declares supported, rejected, and
  future cells across type family, vocab, topology, schedule, and materializer.
- [x] Add a test that the support matrix and artifact planner agree.
- [x] Add a test that schema additions fail until the support matrix is updated.
- [ ] Decide whether `StencilProviderC` still represents source C stencils or
  whether the provider names should become `copy_patch_bc`/`copy_patch_mc`
  aligned.
- [ ] Rename or document `StencilArtifactPlan` if its role is now copy-patch
  artifact construction rather than generic C artifact planning.
- [ ] Decide whether descriptors are runtime ABI facts, artifact identity facts,
  or both; currently they serve both roles.
- [ ] Add documentation for the relation between BC fallback, MC fast path, and
  the embedded banks in the single-binary runtime.

## After Schema Closure Meta-Tasks

Once the `A`/`B`/`C`/`D`/`E` gap register is closed, the work splits into two
larger validation/refinement phases. These are meta-tasks and should be divided
into smaller tracked tasks as the concrete failures become visible.

### 1. Consume the schema richness in every materializer

- [ ] Audit all three materialization paths and confirm every new stencil fact,
  descriptor field, topology, predicate, operator, schedule fact, proof
  obligation, realized schedule fact, and reject fact is either consumed in the
  best available way or deliberately rejected with a typed reason.
- [ ] Treat `copy_patch_bc` as the semantic coverage probe: it should either
  materialize the full supported schema surface or expose the exact missing
  materialization cell.
- [ ] Treat `copy_patch_mc` as the fast-path probe: it should exploit the new
  facts for scheduling, aliasing, alignment, vectorization, gather/scatter,
  select/blend, reductions, and descriptor-aware access patterns where doing so
  can close or beat handwritten C.
- [ ] Treat the emitted C/single-binary bank path as the deployment probe: it
  must intern the intended BC and MC banks, preserve artifact identity, and make
  missing or stale materialization visible.
- [ ] Update the benchmark corpus so it covers each newly expressible stencil
  family and topology, including negative/control cases where a materializer
  should reject.
- [ ] Run the benchmarks against handwritten C compiled with `gcc -O3`, record
  the results, and interpret each gap as either bad materialization, missing
  schedule information, frontend information loss, or an expected target limit.
- [ ] Feed benchmark findings back into the materializers and schedule/fact
  schema instead of treating benchmark numbers as a separate report.

### 2. Make the frontend feed the schema fully

- [ ] Audit frontend lowering to check whether source programs provide every
  fact the stencil schema can now represent: alias relations, access roles,
  topology, index streams, predicate semantics, integer/float semantics,
  reduction identity/proofs, trip-count facts, schedule hints, and boundary
  contracts.
- [ ] Add end-to-end DSL tests proving those facts survive from source program
  through typecheck/kernel facts/stencil descriptors/materializer selection.
- [ ] Identify schema facts that only direct artifact constructors can currently
  express, then add frontend syntax, contracts, inference, or checker-derived
  facts so ordinary Lalin code can feed them.
- [ ] Split frontend gaps into inference gaps, source-contract gaps, typechecker
  gaps, kernel-plan gaps, and lowering-rule gaps so fixes stay local.
- [ ] Re-run the benchmark corpus from source-level Lalin, not only direct
  artifact-plan construction, and compare against the direct-materializer
  results to find frontend information loss.

## Suggested Closure Order

- [ ] First close the `LalinStencil` schema soundness and thesis tier:
  `A1`, `B1`, `A4`/`D6`, `A6`, `A2`/`A3`, then `C1`/`C2`.
- [x] Write the explicit support matrix and make tests enforce it.
- [ ] Complete selection-rule coverage against the support matrix.
- [ ] Then complete artifact-plan construction against the same matrix.
- [ ] Then complete LuaTrace emission/runtime tests.
- [ ] Then complete MC intern-bank generation from the matrix.
- [ ] Then run the materializer consumption and benchmark meta-task above.
- [ ] Finally, make frontend lowering feed the full schema and prove the matrix
  from source program to loaded LuaJIT module.
