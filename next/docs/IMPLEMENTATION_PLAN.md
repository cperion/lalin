# Next Compiler Implementation Plan

Status: backend-first TDD plan for the frozen `next` compiler schema.

Authority:

```text
next/lua/lalin/compiler/schema.lua
next/docs/SCHEMA_REVIEW_SYNTHESIS.md
next/docs/ASDL_NAMED_CONTROL.md
next/docs/VALUES_MACHINES_NAMED_CONTROL.md
```

Historical documents under `docs/archive/` are evidence only. If they conflict
with `next/`, `next/` wins.

## Principle

The compiler is built from the bottom upward:

```text
C/Host -> CMat -> Kernel -> Analysis -> Code -> Semantic -> Source -> Surface
```

The schema and tests are solved together. Before a layer can be implemented, its
ASDL boundary must have `_spec.lua` tests that state the durable values, accepted
fixtures, rejected fixtures, diagnostics, method ownership contracts, and
implementation order. Implementation then follows that declared order and adds
methods on the ASDL classes until those tests pass.

Implementation is mechanical only when the next durable value boundary is clear.
If a method wants a side table, tag string, class-name dispatch, generic context
bag, nil protocol, registry, pass manager, or hidden convention, stop and ask
whether this is schema pressure.

## Schema freeze and repair protocol

The schema is frozen. A schema edit is allowed only for a true P0 correctness
issue discovered by tests or implementation pressure.

A P0 schema issue is one of:

- a value needed by an implementation boundary is unrepresentable;
- an existing field forces a hidden side table or convention;
- a diagnostic or result leaf cannot be produced by any valid value;
- a recursive embedding cycle or impossible ASDL closure appears;
- the only implementation path requires manual variant dispatch where a leaf
  method should own behavior.

Schema-repair commit contents:

- [ ] schema edit in `next/lua/lalin/compiler/schema.lua`;
- [ ] focused failing test that explains the missing value;
- [ ] `next/tests/compiler/test_schema.lua` and `next/tests/compiler/schema_spec.lua` updates;
- [ ] fixture/golden updates caused by the schema repair;
- [ ] `next/docs/SCHEMA_REVIEW_SYNTHESIS.md` re-freeze note;
- [ ] no unrelated implementation plumbing.

## Schema specification gate

No implementation phase starts until its schema specification is written.
A schema specification is a `_spec.lua` file discovered by `next/tests/run.lua` that pins:

- [ ] exact ASDL leaves/products used by the phase;
- [ ] accepted hand-built ASDL fixtures;
- [ ] rejected hand-built ASDL fixtures;
- [ ] expected ASDL outputs, C text, diagnostics, or runtime values;
- [ ] ownership of each behavior by concrete ASDL leaf methods;
- [ ] a method-contract inventory and implementation order;
- [ ] fixture names and golden-file locations;
- [ ] known P0 schema risks and the intended v1 decision.

Schema specification tests may fail while implementation is missing. They must
not fail because the expected value boundary is unclear.

## Core red-green loop

For every checklist item:

```text
1. Write ASDL fixtures for the layer input.
2. Write expected ASDL values, emitted text, diagnostics, or runtime result.
3. Run the focused test through `next/tests/run_one.lua` or `next/tests/run.lua <filter>`; it must fail because the next declared method contract is missing.
4. Implement the next method contract in the spec's `implementation_order`, with behavior on concrete ASDL leaves.
5. Inspect emitted/generated values.
6. Benchmark when the layer affects runtime shape.
7. If implementation feels unnatural, apply the schema repair protocol first.
8. Commit only when the layer is green and deterministic.
```

Mandatory gates after each batch, run from the repository root:

```sh
LUA_PATH='./next/lua/?.lua;./next/lua/?/init.lua;./next/tests/?.lua;./next/tests/?/init.lua' \
  luajit next/tests/run.lua
# equivalent: make test-next
git diff --check -- next
```

## Fixture and golden policy

- [ ] Spec files use `_spec.lua` naming and are discovered by `next/tests/run.lua`. Names are semantic boundary keys, not numeric phase names.
- [ ] Test fixtures live under `next/tests/compiler/fixtures/<spec-key>/`.
- [ ] Golden text lives under `next/tests/compiler/golden/<spec-key>/`.
- [ ] Fixture filenames include the boundary and case, e.g.
      `c_emission_scalar_add.lua`, `kernel_schedule_reduce_i32.lua`.
- [ ] A regenerate flag may rewrite goldens only from a green test run; schema inventory uses `LALIN_REGEN_SCHEMA=1`.
- [ ] Golden diffs are reviewed in the same commit as the method change.
- [ ] Every fixture constructs ASDL values directly unless the boundary is explicitly
      about parser/loader/DSL.
- [ ] Fixture helpers may reduce boilerplate, but may not hide semantic facts in
      Lua tables.
- [ ] A schema-walk coverage test maps every union leaf in the implemented
      modules to at least one fixture before the module is declared complete.

## Named-machine policy

Machines are ordinary Lua objects that hold live computation state. Durable
facts are ASDL values. A machine may sequence work and tail-call named exits;
it may not be the semantic authority for facts carried by ASDL products/sums.

Each nontrivial derivation phase names its machine and exits before
implementation. Example shape:

```lua
function SomeMachine:advance()
  local subject = self.subjects[self.cursor]
  if not subject then return self:done(self.output) end
  return subject:derive(self.input, self, SomeMachine.accepted, SomeMachine.rejected)
end
```

---

# Phase 0 — Harness and method loading

Goal: make `next` a safe implementation root without wiring it to active compiler.

- [x] Add `next/lua/lalin/compiler/init.lua` returning the schema and loading methods.
- [x] Add method loading convention under `next/lua/lalin/compiler/impl/`.
- [x] Add an isolated test helper module under `next/tests/compiler/support/`.
- [x] Add fixture helpers for common schema-shaped ASDL values; extend per phase as needed.
- [x] Add schema golden-file helper and regeneration policy; add phase golden helpers when Phase 1 starts.
- [x] Add temporary-directory helpers for GCC/cook tests.
- [x] Add a schema-walk helper that enumerates modules, sums, leaves, products, and field shapes.
- [x] Add compiler spec gate and coverage helper for data-only semantic boundary specifications.
- [x] Add `next/tests/compiler/spec/_template.lua` for semantic boundary specs.
- [x] Add a diagnostic reachability helper: every diagnostic leaf is classified as origin-reachable or explicitly originless before Phase 9 fixtures.
- [x] Add a generation-coherence helper: each projection boundary can assert generation equality.
- [x] Add an active-tree isolation test: no active `lua/lalin/` module requires `next`.
- [x] Add method-loading order tests: parent defaults load before leaf overrides.
- [x] Add implementation-style guard against `.kind`/`.tag`/handler-table dispatch in `next/lua/lalin/compiler/impl`.
- [x] Gate: existing runtime/schema tests still pass.

---

# Phase 1 — C text emission and Host boundary

Boundary:

```text
C.Unit -> emitted C text -> Host cook/load/symbol
```

Phase 1 fixtures hand-construct `Types.Layout` and `Types.CallableABI` values.
Derivation of those values lands in Phase 8. Do not wait for Phase 8 to test C
emission.

## 1.1 C emitter skeleton

Tests first:

- [ ] `C.Unit` with no functions emits deterministic empty translation unit.
- [ ] `C.Unit.types` and `C.Unit.signatures` are declared as deterministic deduplicated collections, not lookup tables.
- [ ] `C.Type` for void/bool/signed/unsigned/index/float/raw pointer emits expected C spelling.
- [ ] `C.Type` for pointer/array/slice/view/imported emits pinned spelling; struct/union/handle require layout facts or typed rejection.
- [ ] View/slice C representation is pinned before operation emission: struct field names, length type, stride type, null spelling.
- [ ] `C.Signature` emits expected parameter/result spelling.
- [ ] `Source.Symbol` linkage chooses exported/static/extern spelling deterministically.
- [ ] global/data/helper declarations emit in `C.Unit` order.
- [ ] baseline emitter capability is declared by a method on `Target.EmitterCapability` / feature leaves, not by a side table.
- [ ] emitted header/source ordering is stable.

Methods:

- [ ] `C.Unit:emit_c(input)`.
- [ ] `C.Type:emit_c_type(input)`.
- [ ] `C.Signature:emit_c_signature(input)`.
- [ ] `C.Function:emit_c_declaration(input)`.
- [ ] `C.Extern:emit_c_declaration(input)`.
- [ ] `C.Global:emit_c_declaration(input)`.
- [ ] `C.Data:emit_c_declaration(input)`.
- [ ] `C.Helper:emit_c_declaration(input)`.
- [ ] `Target.EmitterFeature` leaves declare supported backend capability meaning.

## 1.2 C function and helper emission

Tests first:

- [ ] one direct-return `i32 add(i32, i32)` function emits stable C.
- [ ] function parameters preserve ordinal order.
- [ ] generated parameters emit stable names.
- [ ] locals emit before statements.
- [ ] generated locals emit stable names and origins are printable.
- [ ] labels and block parameters lower deterministically.
- [ ] `ReturnVoid`, `ReturnValue`, `Trap`, and `Unreachable` emit valid C.
- [ ] `Branch`, `Jump`, `Switch`, `VariantSwitch` emit valid structured/goto C.
- [ ] `C.HelperDefinition` emits helper bodies used by CMat helpers.
- [ ] multi-fragment function assembly uses `FragmentPart*` on `C.FunctionDefinition`.
- [ ] overlapping covered blocks produce `OverlappingFunctionCoverage`.
- [ ] invalid C control returns `Diagnostic.CEmissionError.InvalidCControl`.

Methods:

- [ ] `C.FunctionDefinition:emit_c_definition(input)`.
- [ ] `C.HelperDefinition:emit_c_definition(input)`.
- [ ] `C.Block:emit_c_block(input)`.
- [ ] `C.Statement:emit_c_statement(input)`.
- [ ] each `C.Operation` leaf owns emission or typed rejection.
- [ ] each `C.Terminator` leaf owns emission.

## 1.3 C operation decision table

Every operation leaf must be classified before implementation as EMIT or REJECT.
No leaf may stay “TODO at runtime.”

Tests first:

- [ ] `ConstantOp` emits scalar constants.
- [ ] `AliasOp` emits assignment.
- [ ] `UnaryOp` emits negate/logical-not/bitwise-not.
- [ ] `BinaryOp` emits arithmetic, division, remainder, bit operations, shifts.
- [ ] `CompareOp` emits comparisons.
- [ ] `CastOp` emits resolved machine casts.
- [ ] `SelectOp` emits ternary expression.
- [ ] `AddressOp` emits address-of place.
- [ ] `PointerOffsetOp` emits pointer arithmetic with correct index width.
- [ ] `LoadOp` / `StoreOp` emit volatile or ordinary access.
- [ ] aggregate/array ops EMIT only for pinned C representation; otherwise typed rejection.
- [ ] view/slice ops EMIT against pinned view/slice struct spelling.
- [ ] closure/variant ops EMIT only after representation is pinned; otherwise rejected before C emission by Phase 6.
- [ ] direct/external/indirect/closure/helper/intrinsic calls emit with correct `C.CallResult`.
- [ ] atomics emit `__atomic_*` builtins with pinned ordering policy or typed rejection.
- [ ] overflow semantics are pinned: wrapping, saturating, exact, undefined.
- [ ] trap semantics are pinned: explicit checks + `__builtin_trap()` where required.
- [ ] float-mode text emission is independent of cook flags; `FastMathRefused` is a Host policy rejection.

Methods:

- [ ] every concrete `C.Operation` leaf implements `emit_c_statement` or `reject_c_operation`.
- [ ] every `C.Value` leaf implements expression emission.
- [ ] every `C.Place` leaf implements lvalue/address emission.
- [ ] every `C.CallResult` leaf owns call-result shape.

## 1.4 ABI zipper and sret

Tests first:

- [ ] direct result ABI emits ordinary return.
- [ ] void result ABI emits no result slot.
- [ ] indirect result ABI emits hidden sret parameter in `FunctionParameter*`.
- [ ] `Types.SretResult` appears on the hidden parameter zip.
- [ ] `C.AbiResultSlot.IndirectSlot` parameter is the emitted first parameter.
- [ ] sret caller path stores through hidden pointer and returns expected value.
- [ ] direct/indirect/sret calls are tested for internal and external calls.
- [ ] invalid/mismatched sret emits typed ABI/C diagnostic.
- [ ] Phase 1 fixtures hand-construct scalar ABI/layout facts until Phase 8 derives them.

Methods:

- [ ] `Types.Passing` leaves emit parameter ABI shape.
- [ ] `C.AbiResultSlot` leaves emit result-handling prologue/epilogue.
- [ ] call leaves respect sret call result convention.

## 1.5 Host cook/load/symbol

Tests first:

- [ ] `Host.CookRequest` writes C source to temp dir.
- [ ] GCC success returns `Host.Cooked` with `LiveSession`.
- [ ] `StrictFloat` maps to `-fno-fast-math`.
- [ ] `FastMath` maps to `-ffast-math`.
- [ ] unit with an operation whose `Semantic.ScalarMeaning.float_mode` is `ExactFloat` cooked under `FastMath` returns `FastMathRefused`.
- [ ] missing compiler returns `CompilerUnavailable`.
- [ ] bad C returns `CompilationFailure` with stderr truncation policy.
- [ ] dynamic load failure is typed.
- [ ] symbol lookup succeeds for exported function.
- [ ] missing symbol returns `MissingSymbol`.
- [ ] incompatible FFI type returns `IncompatibleFfiType`.
- [ ] `Host.CookFailure` and `Host.SymbolFailure` leaves implement `describe()` here; Phase 9 adds full report rendering.

Methods:

- [ ] `Host.CookRequest:cook()`.
- [ ] `Host.SymbolRequest:resolve()`.
- [ ] `Host.CookFailure` leaves format diagnostic payloads.
- [ ] `Host.SymbolFailure` leaves format diagnostic payloads.

## 1.6 Code module to C unit

This is an explicit lower boundary. Do not make Phase 6 jump directly to C text.

Boundary:

```text
Code.Module + Target facts + selected fragments -> C.Unit
```

Tests first:

- [ ] scalar `Code.Module` add function lowers to `C.Unit` without CMat.
- [ ] `Code.GlobalDefinition` lowers to `C.Global` + `Code.Module` initializer use; C does not re-author initializers.
- [ ] `Code.Data` lowers to `C.Data` with deterministic bytes and alignment.
- [ ] `Code.Relocation*` are consumed by `C.Unit` / artifact emission without a duplicate C relocation schema.
- [ ] `Types.Layout` and `Types.CallableABI` must already be present on C type/signature values.
- [ ] selected `CMat.Fragment` values become `C.FragmentPart` entries on the owning `C.FunctionDefinition`.
- [ ] baseline blocks and fragment parts cannot overlap coverage.
- [ ] unsupported code instruction returns `UnrepresentableOperation` or `UnsupportedCEntity` before C emission.

Methods:

- [ ] `Code.Module:lower_to_c_unit(input)`.
- [ ] `Code.FunctionDefinition:lower_to_c_function_definition(input)`.
- [ ] `Code.GlobalDefinition:lower_to_c_global(input)`.
- [ ] `Code.Data:lower_to_c_data(input)`.
- [ ] `Code.Relocation:emit_c_initializer_piece(input)`.

Phase gate:

- [ ] generated C for scalar add is inspected and committed as a golden fixture.
- [ ] scalar add compiles with GCC and returns correct result through FFI.
- [ ] baseline compile/runtime benchmark recorded.

---

# Phase 2 — CMat fragment to C

Boundary:

```text
CMat.Fragment / CMat.Materialization / CMat.CursorRealization -> C fragment parts
```

Phase 2 fixtures may hand-build `CursorRealization` values. Phase 3 constructs
them from scheduled kernels.

## 2.1 Fragment values, locals, labels

Tests first:

- [ ] `CMat.FragmentValue` maps to stable `C.Value`/`C.Local`.
- [ ] `CMat.FragmentLocal` maps to stable `C.Local`.
- [ ] `CMat.FragmentLabel` maps to stable `C.Label`.
- [ ] generated fragment values/locals carry stable origins.
- [ ] `FragmentEntryArgument` maps code parameters into fragment values.
- [ ] `FragmentExitArgument` maps fragment values back to code parameters.
- [ ] one function with multiple fragments produces one `C.FunctionDefinition` with multiple `FragmentPart` entries.
- [ ] overlapping fragment coverage rejects as `OverlappingFunctionCoverage`.

Methods:

- [ ] `CMat.Fragment:lower_to_c_fragment_part(input)`.
- [ ] `CMat.FragmentValue:lower_to_c_value(input)`.
- [ ] `CMat.FragmentLocal:lower_to_c_local(input)`.
- [ ] `CMat.FragmentLabel:lower_to_c_label(input)`.

## 2.2 Fragment operations and terminators

Tests first:

- [ ] assign lowers to C assignment.
- [ ] unary/binary/compare/logic/select/cast lower one leaf at a time.
- [ ] load/store lower through `CMat.MemoryUse`.
- [ ] helper/function calls lower with `FragmentCallResult`.
- [ ] branch/jump terminators lower with argument zips.
- [ ] exit terminator stores/forwards `FragmentExitArgument` values and jumps to the target covered block.
- [ ] `InvalidFragmentCoverage` fires when a block is not covered by the fragment.
- [ ] `MissingFragmentValue` fires for an unbound code value.
- [ ] `InvalidFragmentExit` fires for exit target mismatch.
- [ ] `UnsupportedFragmentCarry` fires for a live value crossing the fragment with no entry/exit argument.

Methods:

- [ ] every `CMat.FragmentExpression` leaf lowers itself.
- [ ] every `CMat.FragmentOperation` leaf lowers itself.
- [ ] every `CMat.FragmentTerminator` leaf lowers itself.

## 2.3 Memory use, coordinates, cursors

Tests first:

- [ ] absolute coordinate emits pointer expression.
- [ ] iteration coordinate emits affine index expression.
- [ ] window coordinate emits the full `before+after+1` access set, not one load.
- [ ] dynamic window coordinate emits dynamic displacement expression.
- [ ] scatter coordinate emits indexed access or typed unsupported diagnostic.
- [ ] `ClampBoundary`, `WrapBoundary`, `ZeroBoundary`, `RejectBoundary` semantics are pinned.
- [ ] `RejectBoundary` is admitted only with proven bounds; otherwise `MissingFusedBounds`.
- [ ] restrict pointer qualification uses `Memory.ObjectRelation*` only.
- [ ] unsupported RMW diagnostic carries `Memory.Access`.
- [ ] cursor candidacy: an affine memory use with loop-invariant base and stride tied to innermost axis gets a cursor.
- [ ] non-affine or scatter use requiring a cursor returns `CursorUnavailable`.
- [ ] a valid `CursorRealization` may have zero cursors for recomputed addresses.
- [ ] `AddressUnavailable`, `CoordinateUnavailable`, `PointerQualificationUnavailable`, and `UnsupportedUseMeaning` have one fixture each.
- [ ] `MemoryUse` address bindings map coordinate source `Code.Value` to `FragmentValue`; missing binding rejects `InvalidFragmentLowering`.

Methods:

- [ ] `CMat.MemoryUse:lower_to_c_place(input)`.
- [ ] every `CMat.Coordinate` leaf lowers itself.
- [ ] `CMat.PointerAccess` leaves lower qualification.
- [ ] `CMat.CursorRealization` lowers cursor declarations/updates.

## 2.4 Fragment C execution tests

- [ ] hand-built fragment copies one array to another.
- [ ] hand-built fragment maps `x + 1` over a view.
- [ ] hand-built fragment reduces a counted range.
- [ ] hand-built fragment scans a counted range.
- [ ] hand-built fragment with window boundary emits expected C shape.
- [ ] hand-built fragment with cursor emits init in preheader and increments in latch.
- [ ] generated C is inspected for deterministic shape.
- [ ] GCC runtime tests compare output arrays/results.
- [ ] microbenchmarks recorded for copy/map/reduce/scan/window.

Phase gate:

- [ ] fragment goldens include cursor-loop shape.
- [ ] fused fragment runtime tests pass through Phase 1 C/Host.
- [ ] fragment benchmarks recorded against equivalent baseline C where possible.

---

# Phase 3 — Kernel schedule to CMat

Boundary:

```text
Kernel.Schedule -> CMat.Computation -> CMat.Materialization -> CMat.CursorRealization -> CMat.Fragment
```

## 3.1 Kernel lanes and results

Tests first:

- [ ] counter lane contributes an axis and loop coordinate source.
- [ ] input lane from induction contributes stream input.
- [ ] input lane from memory access contributes load/window/scatter access.
- [ ] input lane from result value contributes a value input only when value is available in the stream graph.
- [ ] output lane contributes store access.
- [ ] accumulator lane references `Control.ReductionAlgebra` directly.
- [ ] invalid lane/source combinations are unconstructible.
- [ ] lane projection is multi-output into a CMat builder, not a leaf returning one value.
- [ ] stream graph producer/consumer constraints are validated: stores are consumers, loads are producers, sinks may consume stream/access values only in legal positions.
- [ ] `OutputLane` and `Result.StoredTarget` pairing emits one store, never duplicate stores.

Methods:

- [ ] every `Kernel.Lane` leaf implements `contribute_cmat(input, builder)`.
- [ ] every `Kernel.ResultTarget` leaf contributes sink/storage shape.
- [ ] every `Kernel.ResultCadence` leaf owns publication cadence.

Result cadence matrix:

- [ ] `OrdinaryResult + RegisterTarget`: publish one scalar after loop.
- [ ] `OrdinaryResult + StoredTarget`: one store at the result point.
- [ ] `ReductionResult + RegisterTarget`: accumulator final value after loop.
- [ ] `ReductionResult + StoredTarget`: final reduction store after loop.
- [ ] scan is represented by `Control.ReductionAlgebra.Scan` in the cadence algebra; inclusive scan stores post-step accumulator, exclusive scan stores pre-step accumulator.

## 3.2 Schedule admission

Tests first:

- [ ] exact-tail counted range schedule admitted.
- [ ] scalar-remainder schedule is a recorded `TailDecision`; scalar-only C may emit same code as exact tail until vector support exists.
- [ ] target optimization flags consume `Target.Optimization.prefer_baseline`, `permit_closed_form`, and `permit_fusion` explicitly.
- [ ] closed-form path is admitted only when `permit_closed_form` and arithmetic facts allow it.
- [ ] fusion path is admitted only when `permit_fusion` and memory/effect/ownership facts allow it.
- [ ] missing emitter capability produces `MissingEmitterCapability`.
- [ ] illegal tail produces `IllegalTailSchedule`.
- [ ] schedule policy rejection is typed.
- [ ] baseline path has explicit `Kernel.Baseline` construction and capability check.
- [ ] tiled counted flow is recognized but v1 fusion rejects it as `UnsupportedFusedDomain` until explicit CMat tiled vocabulary exists.

Methods:

- [ ] `Kernel.Kernel:select_schedule(input)`.
- [ ] `Kernel.Schedule:project_cmat(input)`.
- [ ] `Target.Policy` and `Target.Optimization` are consumed by schedule methods.

## 3.3 Fused computation, materialization, and fragments

Tests first:

- [ ] range map creates domain + stream graph + sink.
- [ ] grid map creates multi-axis domain + streams + stores.
- [ ] tiled flow rejects as `UnsupportedFusedDomain` in v1.
- [ ] window access creates multiple memory uses with pinned boundary policy.
- [ ] scatter admission requires proven bounds/index facts; v1 scalar C emits `ScatterCoordinate`, missing proof rejects as `MissingFusedBounds`.
- [ ] reduction creates accumulator stream + reduction sink.
- [ ] scan creates per-iteration sink with inclusive/exclusive cadence.
- [ ] map + reduce in one loop emits both store and accumulator without duplicated source.
- [ ] zero-trip reduction with `IdentityAbsent` rejects precisely.
- [ ] dynamic trip count works when affine enough for cursor/materialization.
- [ ] early-exit branch inside loop rejects fusion as `UnsupportedFusedDomain`.
- [ ] volatile access rejects fusion.
- [ ] RMW/atomic access rejects fusion as `UnsafeFusedAccess` or `UnsupportedRmwAccess(Memory.Access)` depending stage.
- [ ] missing bounds rejects recognition/fusion at the correct stage: `MissingKernelEvidence` vs `MissingFusedBounds`.
- [ ] missing noalias rejects as `MissingFusedNoalias`.
- [ ] every `FusionUnavailable` and `MaterializationUnavailable` leaf has a trigger fixture.

Methods:

- [ ] `Kernel.Schedule:project_fused_computation(input)`.
- [ ] `CMat.Computation:materialize(input)` produces `CMat.Materialization`.
- [ ] `CMat.Materialization:realize_cursors(input)` produces `CMat.CursorRealization`.
- [ ] `CMat.CursorRealization:realize_fragment(input)` produces `CMat.Fragment`.
- [ ] `Kernel.RejectedOptimization` leaves retain exact rejection reason.

Phase gate:

- [ ] same hand-built kernels run through CMat -> C -> GCC.
- [ ] emitted C for map/reduce/scan/window/cursor inspected.
- [ ] fused vs baseline runtime benchmarks recorded.
- [ ] no per-iteration address recomputation appears where cursor realization should exist.

---

# Phase 4 — Code to analysis facets

Boundary:

```text
Code.Module / Code.FunctionDefinition -> Control.Graph -> Analysis.Module
```

Ownership is derived from semantic/source information before or alongside code
lowering, then aligned with memory. Do not try to derive source-visible ownership
rules from Code alone.

## 4.1 Control graph

Tests first:

- [ ] `Code.Module:derive_control_graph` produces `Control.Graph` with generation from `Code.Module`.
- [ ] one `Control.FunctionGraph` per `Code.FunctionDefinition`.
- [ ] blocks produce definitions and uses.
- [ ] jumps/branches/switches produce exact edges.
- [ ] edge arguments zip values to parameters.
- [ ] loops are detected for simple range shape.
- [ ] nested loops set `LoopParent.NestedLoop` to a real ancestor.
- [ ] every `UncountedReason` leaf has a fixture.
- [ ] traversal loops remain non-kernel shapes.
- [ ] counted loops produce `Control.CountedFlow`.
- [ ] tiled flows are recognized but rejected or expanded according to Phase 3 decision.
- [ ] induction facts reference counted flow.
- [ ] irreducible/ambiguous CFGs reject as typed control/analysis diagnostics.

Methods:

- [ ] `Code.Module:derive_control_graph(input)`.
- [ ] `Code.FunctionDefinition:derive_function_graph(input)`.
- [ ] every `Code.Terminator` leaf derives edges/uses.
- [ ] every `Code.Instruction` leaf derives definitions/uses.
- [ ] loop-shape leaves own counted/traversal/uncounted meaning.

## 4.2 Value facts and arithmetic

Tests first:

- [ ] constant ranges.
- [ ] affine facts.
- [ ] no-wrap facts always carry `ValueProof`.
- [ ] finite/non-NaN/exact float facts.
- [ ] exact-float fact under incompatible fast-float policy rejects or is not produced.
- [ ] loop arithmetic facts use `LoopArithmetic.AffineLoopValue` only.
- [ ] affine expressions canonicalize before emitted C uses them.
- [ ] contradictory evidence emits `ContradictoryValueEvidence`.

Methods:

- [ ] value-producing instruction leaves derive value facts.
- [ ] induction leaves derive affine expressions.

## 4.3 Reduction algebra

Tests first:

- [ ] Source/Semantic fold and scan lowering creates code patterns recognized here.
- [ ] fold code pattern creates `ReductionAlgebra.Reduction`.
- [ ] scan code pattern creates `ReductionAlgebra.Scan`.
- [ ] identity-present reducers store identity.
- [ ] identity-absent reducers reject zero-trip use where required.
- [ ] associativity evidence carries no duplicate reducer.
- [ ] every `ReducerError` leaf has a source/semantic fixture and an analysis fixture when applicable.
- [ ] multiple/misplaced reducers produce typed diagnostics in Source/Semantic phase, not by ad hoc analysis guessing.

Methods:

- [ ] reducer leaves validate associativity/identity.
- [ ] loop bodies derive reduction algebra without source-side classification duplication.

## 4.4 Memory model

Tests first:

- [ ] storage roots for parameters, locals, globals, data, views, slices, unique, indirect.
- [ ] object identity: same root/path canonicalizes only when schema says so; different roots never alias by accident.
- [ ] view/slice roots model underlying data pointer vs view object precisely.
- [ ] object shapes from layout/type facts.
- [ ] load/store/rmw/address accesses.
- [ ] scalar/affine/field/byte/index-sequence indices.
- [ ] bounds evidence from declared contracts and flow facts.
- [ ] trap/alignment/movement facts.
- [ ] object relations and dependences are separate collections.
- [ ] declared noalias creates `RelationEvidence.DeclaredNoalias` / `DeclaredUnaryNoalias`.
- [ ] `Disjoint`/`ExactNoalias`/`Incomparable` pairs produce no dependence.
- [ ] `MayAlias` produces `UnknownDependence`.
- [ ] `SameStore`/`Overlap`/`ProvenAlias` can produce access/loop dependences with affine distance.
- [ ] contract realizations map contracts to objects/accesses/pairs/expressions.
- [ ] unresolvable contract subjects produce typed diagnostics.
- [ ] bounds/noalias required-by-fusion consumers trigger `RequiredBoundsUnproven` and `RequiredNoaliasUnproven`.
- [ ] noescape contract subject resolves to the same object used by effect and ownership noescape facts.
- [ ] call requires create `CallRequireRealization` and preserve original `Semantic.Contract` identity.

Methods:

- [ ] `Control.FunctionGraph:derive_memory_model(input)`.
- [ ] `Memory.Model:derive_dependences(input)` or dependence derivation inside the memory model machine.
- [ ] every `Code.Place` leaf derives memory object/path facts.
- [ ] every memory-affecting `Code.Instruction` leaf derives access facts.
- [ ] every `Semantic.Contract` leaf realizes itself against memory subjects.

## 4.5 Effect summary

Effect derivation is module-level because call summaries require a fixed point/SCC
over callees. Per-function summaries are published into `Analysis.FunctionFacts`.

Tests first:

- [ ] module-level effect machine computes operation effects per function.
- [ ] recursive call graph terminates without embedding callable summaries recursively.
- [ ] pure operations produce `PureOperation`.
- [ ] reads/writes/preserve/invalidate/noescape/retain/allocate/fence effects.
- [ ] `AllocateEffect`/`RetainEffect` are produced only by explicit semantics/extern declarations unless a body producer is added.
- [ ] direct calls produce known/unknown call effects by callee.
- [ ] external callable effects carry declared effect atoms.
- [ ] deleted subjectless analyzed atoms remain absent.
- [ ] no effect depends on ownership state; ownership may consume effects later.

Methods:

- [ ] `Code.Module:derive_effect_summaries(input)` or `Control.Graph:derive_effect_summaries(input)`.
- [ ] every effectful `Code.Instruction`/`Code.Terminator` leaf derives operation effects.
- [ ] every `Effect.CallableEffect` leaf formats/validates boundary behavior.

## 4.6 Ownership model

Ownership has source-visible obligations and memory-aligned states. Source-visible
copy/drop/owned/lease diagnostics are produced during Source/Semantic checking;
Phase 4 aligns surviving objects/states to memory.

Tests first:

- [ ] source/semantic ownership actions survive into code or ownership input values.
- [ ] anonymous leases map to a documented owner object/value.
- [ ] lease origin creation from semantic bindings.
- [ ] live states name lease origin.
- [ ] invalidated/discharged/noescape states.
- [ ] illegal copy/drop/double-discharge diagnostics are tested in Phase 7.
- [ ] noescape call agrees across `Effect.NoescapeEffect`, `Ownership.Noescape`, and `Memory.CallRequireRealization`.
- [ ] ownership model aligns to memory model.
- [ ] CMat memory uses carry live ownership states from the owning function facts.

Methods:

- [ ] `Memory.Model:derive_ownership_model(input, ownership_inputs)`.
- [ ] ownership action leaves derive state transitions where source ownership input is present.
- [ ] ownership diagnostics format exact origins.

## 4.7 Analysis zipper

Tests first:

- [ ] one `Analysis.FunctionFacts` bundles graph/memory/effects/ownership.
- [ ] `Analysis.Module` contains one facts value per function graph.
- [ ] no external registry is needed to find aligned facets.
- [ ] generation mismatches reject as `GenerationMismatch`.
- [ ] fact lookup inside later phases scans/receives `Analysis.FunctionFacts`, not module-global Lua maps.

Methods:

- [ ] `Control.Graph:analyze(input)` returns `Analysis.Module`.
- [ ] analysis machine has named exits for graph accepted, memory rejected, effects rejected, ownership rejected, done.

Phase gate:

- [ ] hand-built `Code.FunctionDefinition` for scalar loop reaches kernel recognition.
- [ ] analysis fixtures are stable golden ASDL values.
- [ ] analysis benchmark guards against quadratic lookups in multi-function modules.

---

# Phase 5 — Kernel recognition from analysis

Boundary:

```text
Analysis.FunctionFacts -> Kernel.Kernel / typed rejection / optimization choice
```

Phase 5 uses a named recognition machine instead of adding a `KernelAttempt` schema
value. Accepted kernels and typed rejections leave through named exits; retained
optimization history is represented only by existing `Kernel.RejectedOptimization`
and `Kernel.OptimizationChoice` values. If this becomes unrepresentable in
implementation, that is a P0 schema-repair candidate.

Tests first:

- [ ] counted range loop recognized as kernel.
- [ ] traversal/uncounted loops rejected structurally.
- [ ] tiled flow rejected or expanded per Phase 3 decision.
- [ ] unsafe memory rejects kernel.
- [ ] unsupported expression/effect rejects kernel.
- [ ] invalid trip rejects kernel.
- [ ] missing evidence rejects kernel.
- [ ] recognition-vs-fusion evidence split is tested: kernel recognition does not consume evidence only needed by materialization.
- [ ] lanes/results are produced from analysis facts.
- [ ] output lane pairs with stored target exactly once.
- [ ] reduction/scan kernels produce accumulator/result cadence.
- [ ] scatter admission is tested from analysis facts and requires bounds/index proof.
- [ ] zero-trip identity-absent reduction rejects.
- [ ] two loops in one function produce two independent attempts.
- [ ] nested loops: v1 recognizes only innermost counted loops with no fused nested control; other nested candidates reject as `UnsupportedKernelControl` or `UnsupportedFusedDomain`.
- [ ] every `KernelUnavailable` leaf has a trigger fixture.

Methods:

- [ ] `Analysis.FunctionFacts:recognize_kernels(input)`.
- [ ] `Control.CountedFlow` leaves own domain mapping.
- [ ] `Memory.Access` leaves own kernel access admission.
- [ ] `Effect.Atom` leaves own kernel-effect admission.
- [ ] `Ownership.State` leaves own kernel ownership admission.
- [ ] recognition machine has named exits for accepted kernel, rejected kernel, and done.

Phase gate:

- [ ] recognized kernels pass Phase 3/2/1 end-to-end.
- [ ] rejection history is retained in `Kernel.OptimizationChoice` or named-machine output according to the Phase 5 decision.

---

# Phase 6 — Semantic to Code

Boundary:

```text
Semantic.Program -> Code.Module
```

Scalar-only fixtures can start before full layout. Aggregate/closure/variant/data
fixtures require Phase 8 layout/ABI support.

## 6.1 Code entities and module assembly

Tests first:

- [ ] semantic functions become `Code.Function` + `FunctionDefinition`.
- [ ] semantic externs become `Code.Extern`.
- [ ] semantic statics/data become code globals/data.
- [ ] type-only declarations produce no `Code.Module` entry.
- [ ] one `FunctionDefinition`/`Extern`/`GlobalDefinition`/`Data` per semantic declaration in ordinal order.
- [ ] signatures map semantic parameter/result types.
- [ ] generated parameters/locals carry origins.
- [ ] blocks preserve order via ordinals.
- [ ] `Code.Module.generation == Semantic.Program.generation`; mismatch rejects.

Methods:

- [ ] `Semantic.Program:lower_code(input)`.
- [ ] each `Semantic.Declaration` leaf lowers itself.
- [ ] `Semantic.Parameter` lowers to `Code.Parameter`.
- [ ] `Semantic.Block` lowers to `Code.BlockDefinition`.

## 6.2 Expressions, data, calls, closures

Tests first:

- [ ] every `Semantic.Expression` leaf has a fixture.
- [ ] every `Semantic.Place` leaf has a fixture.
- [ ] literals to code constants.
- [ ] string literal -> interned `Semantic.Data` -> `Code.Data` + slice/view construction.
- [ ] scalar constant reference folds.
- [ ] aggregate/string constant address -> `Code.Data` + `DataTarget`.
- [ ] constant byte serialization is gated on Phase 8 layout.
- [ ] bindings to parameter/local values.
- [ ] unary/binary/compare/logic/cast/intrinsic.
- [ ] `repr`/`from_repr` lower to `HandleToRaw` / `RawToHandle` casts plus ownership validation.
- [ ] references/relocations for functions, externs, statics, constants, data.
- [ ] address/deref/field/index/load/store.
- [ ] aggregate/array/view/slice.
- [ ] calls preserve call-site requires.
- [ ] calling a runtime function-pointer value is explicitly rejected in v1 as `UnsupportedOperation`; adding dynamic callable lowering requires a P0 schema repair such as a semantic value-callable leaf.
- [ ] method call receiver forms are evaluated once and receiver becomes first lowered argument.
- [ ] closure capture derivation: read/write/address/move capture fixtures.
- [ ] closure environment layout is gated on Phase 8.
- [ ] atomic operations lower or reject precisely.

Methods:

- [ ] every `Semantic.Expression` leaf lowers itself.
- [ ] every `Semantic.Place` leaf lowers itself.
- [ ] every `Semantic.Argument` / `CallArgument` leaf lowers itself.
- [ ] every `Semantic.MachineCast` leaf owns cast lowering.
- [ ] closure/capture leaves own environment requirements; layout is consumed later.

## 6.3 Terminators and regions

Tests first:

- [ ] jumps/branches/switches/variant switches.
- [ ] returns/traps/unreachable.
- [ ] `Semantic.Terminator.RegionCall` never reaches Code lowering; Phase 7 must expand sealed region calls first.
- [ ] unexpanded `RegionCall` at Code lowering rejects with `UnsupportedSemanticNode`, proving the Phase 7 expansion gate.
- [ ] every block path terminates.
- [ ] switch default is required.
- [ ] fold/scan lowering creates code recurrences that Phase 4.3 recognizes.

Methods:

- [ ] every `Semantic.Terminator` leaf lowers itself.
- [ ] region leaves own accepted/rejected lowering boundary.

Phase gate:

- [ ] hand-built semantic add function lowers to Code -> Phase 1.6 -> C -> GCC.
- [ ] hand-built semantic loop lowers through analysis/kernel/fusion when applicable.
- [ ] data/closure/variant fixtures are marked `needs Phase 8` until layout is green.

---

# Phase 7 — Source to Semantic

Boundary:

```text
Source.Program -> Semantic.Program
```

## 7.1 Names, declarations, origins

Tests first:

- [ ] document program, builder program, derived program.
- [ ] declaration × origin-kind matrix for all declaration leaves.
- [ ] every `GenerationCause` leaf has a fixture.
- [ ] generated-origin validator rejects self-containment.
- [ ] function/extern/struct/unique struct/union/handle/region/constant/static declarations.
- [ ] duplicate declaration diagnostics.
- [ ] missing value/type/region/block/continuation diagnostics.
- [ ] visibility/linkage/symbol rules.
- [ ] symbol derivation from `QualifiedName`, extern symbol override, signature collision.
- [ ] meta assignments produce generated declarations with `MetaGeneration` origins against completed ancestor programs, not the program under construction.

Methods:

- [ ] `Source.Program:resolve_semantic(input)`.
- [ ] every `Source.Declaration` leaf resolves itself.
- [ ] `Source.QualifiedName` / use leaves own lookup behavior with typed inputs.

## 7.2 Type forms

Tests first:

- [ ] void, bool, signed/unsigned ints, floats, index, raw pointer.
- [ ] pointer, array, slice, view.
- [ ] lease/owned/qualified access wrappers.
- [ ] qualified access stacking/nesting and `InvalidQualification`.
- [ ] function/closure types.
- [ ] named nominal types.
- [ ] imported C type.
- [ ] recursive/invalid type diagnostics.
- [ ] owned/lease source-visible restrictions and diagnostics.

Methods:

- [ ] every `Source.TypeForm` leaf resolves to `Types.Type`.
- [ ] every `Types.Type` leaf owns layout/ABI queries later consumed by lower layers.

## 7.3 Constants and static initialization

Tests first:

- [ ] integer/float constants normalize raw/value.
- [ ] boolean/string/null/aggregate/array/reference constants.
- [ ] semantic interned `Data` for string bytes.
- [ ] scalar constant values with target type adaptation.
- [ ] static zero/constant/relocatable initializers.
- [ ] multi-relocation initializer with non-zero offsets.
- [ ] recursive/nonconstant/unsupported diagnostics.

Methods:

- [ ] every constant-capable `Source.Expression` leaf evaluates constant value.
- [ ] every `Semantic.ReferenceTarget` leaf produces relocation-capable references.

## 7.4 Expressions, contracts, casts

Tests first:

- [ ] every `Source.Expression` leaf has at least one fixture.
- [ ] every expression-referencing diagnostic can recover a `Source.Origin` without a side table. If this is impossible, add expression-wide origin attributes via schema repair.
- [ ] literals, references, operators, casts, intrinsics.
- [ ] machine-cast selection matrix for reachable type pairs.
- [ ] places and address/deref/field/index/load.
- [ ] calls/method calls with call-site requires.
- [ ] aggregate/array/select/closure/view/constructor/null/sizeof/alignof/isnull.
- [ ] `sizeof`/`alignof` tests are gated on Phase 8 layout.
- [ ] repr/from_repr.
- [ ] every `Source.Contract` leaf checks or rejects precisely.
- [ ] noescape contract subject constraints.
- [ ] SoA component contract subject constraints.
- [ ] type/place/call/index/cast diagnostics.

Methods:

- [ ] every `Source.Expression` leaf typechecks itself.
- [ ] every `Source.Place` leaf typechecks itself.
- [ ] every `Source.Contract` leaf typechecks itself.

## 7.5 Statements, loops, regions, ownership

Tests first:

- [ ] let/var/assignment/store/fence/expression/assert.
- [ ] if/switch/variant switch.
- [ ] loop/fold/scan with `LoopDomain` and element binding.
- [ ] loop domain diagnostics per leaf.
- [ ] allowed loop-body whitelist and rejection list.
- [ ] fold/scan reducer scalar meaning pinning and reducer diagnostics.
- [ ] at most one sink/reducer per loop unless schema later allows more.
- [ ] returns, jumps, conditional jumps.
- [ ] contract statements.
- [ ] region emit expansion: clone/alpha-rename/substitute/wire with `RegionExpansion` origins.
- [ ] sealed region calls expand during Phase 7 into generated Source declarations with `RegionCallGeneration` origins; v1 does not lower `Semantic.RegionCall` directly.
- [ ] handle resolver/domain diagnostics.
- [ ] lease/owned rules with source-position ownership diagnostics.
- [ ] trap.
- [ ] missing terminator / fallthrough / bad control target diagnostics.

Methods:

- [ ] every `Source.Statement` leaf checks itself.
- [ ] every `Source.LoopDomain` leaf derives semantic loop body shape.
- [ ] fold/scan leaves desugar/resolve to one reducer recognition path.
- [ ] region expansion machine has named exits for expanded, rejected, done.

Phase gate:

- [ ] hand-built source add function compiles end-to-end.
- [ ] hand-built source map/reduce/scan compiles end-to-end.

---

# Phase 8 — Target, layout, ABI, erasure

Phase 8 is a hard dependency for aggregate/data/closure/variant fixtures in
Phases 1, 6, and 7. Scalar subsets can be hand-constructed earlier.

Tests first:

- [ ] target spec identity and policy identity.
- [ ] scalar layouts for all primitive types.
- [ ] pointer/array/slice/view layouts.
- [ ] struct/union/handle/imported layouts.
- [ ] packed/natural layout policy.
- [ ] constant byte serialization: endianness, padding, variant tag/payload.
- [ ] closure environment layout per capture mode.
- [ ] callable ABI for direct/indirect/sret result.
- [ ] all `Types.Passing` leaves including `SretResult`.
- [ ] all `Types.AbiResult` leaves.
- [ ] `Types.CallableABI` consumes `Semantic.Erasure`.
- [ ] erasure derivation for owned/lease parameters and `PrematureErasure`.
- [ ] calling convention variants.
- [ ] imported C type spelling/layout/FFI.
- [ ] layout overflow/recursive/unrepresentable diagnostics.
- [ ] ABI parameter/result/convention/symbol diagnostics.

Methods:

- [ ] every `Types.Type` leaf owns `layout(input)`.
- [ ] every `Types.Type` leaf owns ABI passing/result projection where applicable.
- [ ] every `Types.Passing` and `Types.AbiResult` leaf owns C ABI lowering.
- [ ] `Semantic.Erasure` methods derive/validate ABI erasure.
- [ ] `Target.Policy` and `Target.EmitterCapability` methods are consumed by C/kernel scheduling.

Phase gate:

- [ ] ABI fixtures pass through C emitter and GCC.
- [ ] constant/data serialization fixtures feed Phase 6/1 tests.

---

# Phase 9 — Diagnostic presentation

Boundary:

```text
Diagnostic.CompilerError -> stable human report
```

Tests first:

- [ ] every diagnostic family formats without crashing.
- [ ] every concrete diagnostic leaf has a `describe()` golden or a precise family default.
- [ ] every `CompilerError` leaf is reachable from a phase rejection path.
- [ ] origin-bearing diagnostics point at the expected source origin.
- [ ] expression-referencing diagnostics pass the origin reachability enumeration from Phase 7.4.
- [ ] generated-origin diagnostics render generation cause and terminate.
- [ ] backend/host diagnostics include request/artifact/session context.
- [ ] stderr truncation policy for compiler failures is golden-tested.
- [ ] no diagnostic requires a missing origin hidden in a side table.

Methods:

- [ ] every `Diagnostic.*Error` family implements `describe()`.
- [ ] every concrete diagnostic leaf either implements `describe()` or uses a declared family method; the family method must not inspect leaf kind.

---

# Phase 10 — Parser / loader / DSL surface

Boundary:

```text
.lln / Lua DSL -> Source.Program
```

Split into tiers:

- Tier A parse-only: may start after Phase 0.
- Tier B Source construction + diagnostics: requires Phases 7 and 9.
- Tier C end-to-end compile/run: requires Phases 6, 8, and 1.

## Tier A — parse only

- [ ] `.lln` declaration document parses declarations.
- [ ] bracket type escapes parse.
- [ ] `do ... end` function bodies parse.
- [ ] byte offsets/ranges are stable for multibyte input.
- [ ] old top-level Lua chunk forms are rejected.
- [ ] old `lalin fn` island syntax is rejected/not installed.
- [ ] source-level `for`/`while`/`break`/`continue` remain rejected per language rules.

## Tier B — Source values

- [ ] parser constructs schema-valid `Source.DocumentProgram`.
- [ ] Lua DSL constructs schema-valid `Source.BuilderProgram` or declarations.
- [ ] origins/ranges are stable.
- [ ] host eval/generation creates valid `Origin.Generated` without self-containment.
- [ ] HostEval role adaptation per role emits `InvalidHostValue` / `InvalidSplice`.
- [ ] bracket escape forms and `named("T")` fallback.
- [ ] DSL heads construct `Built` origins.
- [ ] parsed unique marker behavior is pinned: implemented authority or typed rejection.
- [ ] explicit LuaJIT bytecode API status for `next` is pinned. The current project architecture keeps LuaJIT bytecode as explicit non-main mode; if `next` v1 defers it, tests must assert it is absent from `next` rather than removed globally.

## Tier C — end to end

- [ ] parsed scalar add compiles and runs.
- [ ] parsed struct/union/handle examples compile and run.
- [ ] parsed loop/map/reduce/scan examples compile and run.
- [ ] emitted C is inspected for representative examples.
- [ ] benchmarks recorded against active compiler where comparable.

---

# Cross-phase invariants

- [ ] Every method input/result that survives a call is an ASDL product/sum.
- [ ] Lua objects hold live computation state only.
- [ ] No semantic fact is stored in a Lua side table keyed by ASDL nodes.
- [ ] No layer dispatches by `.kind` or class-name strings.
- [ ] All durable alternatives are ASDL sums.
- [ ] Immediate futures use named methods/continuations, not temporary tagged result data.
- [ ] Generated C is deterministic for identical ASDL values.
- [ ] Every rejection is a typed diagnostic value.
- [ ] Every benchmark has a named fixture and recorded emitted code shape.
- [ ] Generation token equality is asserted at every projection boundary.
- [ ] Target expectation equality is asserted whenever target-specific facts are consumed.
- [ ] No Lua map is used to wire fragment values to C values; use ASDL binding products.
- [ ] No Lua map is used to find function facts; receive or scan `Analysis.Module` / `FunctionFacts` values.
- [ ] Rejection histories used for optimization decisions are durable ASDL values or named-machine outputs, never local logs.

# Commit rhythm

Recommended commits:

- [ ] one commit per green sub-boundary;
- [ ] one schema-repair commit immediately when ASDL changes are needed;
- [ ] one doc/test update commit when an invariant is discovered;
- [ ] never combine broad schema churn with implementation plumbing.

# Start recommendation

Implementation may start with Phase 0 after this plan is committed. Phase 1 must
not start until Phase 0 fixture/golden/schema-walk helpers exist. Phase 3/5 must
Phase 3/5 use the named-machine recognition decision above; no `KernelAttempt`
schema value is added unless implementation proves the current schema unrepresentable.
Phase 6 depends on Phase 7 expanding sealed region calls before Code lowering.
