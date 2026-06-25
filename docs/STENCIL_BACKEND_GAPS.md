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
- [ ] Add MC runtime materialization coverage for fixed-array, closure, imported
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

## Suggested Closure Order

- [x] First, write the explicit support matrix and make tests enforce it.
- [ ] Then complete selection-rule coverage against the support matrix.
- [ ] Then complete artifact-plan construction against the same matrix.
- [ ] Then complete LuaTrace emission/runtime tests.
- [ ] Then complete MC intern-bank generation from the matrix.
- [ ] Finally, make frontend DSL/end-to-end tests prove the matrix from source
  program to loaded LuaJIT module.
