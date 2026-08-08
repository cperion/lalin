# Compiler Operation Lifetime Model

**Status:** Step-9R durable lifetime and named-machine control model, schema only.

This document supersedes the result and continuation encoding in:

- `docs/COMPILER_RECEIVER_OPERATION_RESULT_MODEL.md`;
- `docs/COMPILER_BEHAVIOR_COVERAGE_MODEL.md`;
- §§12, 14, and 15 of the pre-rework `docs/COMPILER_ASDL_SCHEMA.md`.

It changes schema design only. It authorizes no runtime implementation, compiler
migration, adapter, or compatibility layer.

---

## 1. Closed lifetime classification

| Lifetime | Required form |
|---|---|
| One honest output | direct method returning the exact value |
| Choice consumed now | peer named exits on the running machine object |
| Choice spread across a population | narrow aggregate machine; direct loop or named-exit edge |
| Derived reusable fact | ASDL projection, spine, facet, entry, or artifact |
| Choice stored, queued, suspended, or reused | ASDL sum or one-consumer boundary record |
| Public host choice | sealed typed boundary value |
| Variable destination or suspension | stable named method stored on the machine |

A producer with immediate alternatives receives the named running computation and
stable unbound methods from that machine class:

```lua
return subject:operation(input, machine,
  Machine.on_published, Machine.on_rejected)
```

The producer selects one peer exit and forwards the machine unchanged:

```lua
return on_published(machine, publication)
```

The machine is not opaque state, a callback environment, or a continuation frame. It is
the named computation in progress. Its methods own the static control graph and name
their successors directly.

An internal ASDL result leaf is forbidden when its only purpose is to restore control.

---

## 2. What remains data

The rework keeps:

- S1–S8 spines and identity rules;
- F01–F34 facets and entries;
- C01–C29 domain constructors;
- exact semantic inputs and requests;
- generated and physical provenance;
- conservative dense-entry alternatives;
- sparse no-entry reasons;
- candidate, attempt, address, fragment, and contribution records with exact
  consumers;
- authority-specific sites and reason sums;
- `OptionalRealizationReason`, `StrategyFailureReason`, and rejection history;
- `TypedSemanticRejection`;
- `CArtifact`;
- live and released host-resource values;
- sealed host failures.

A named-exit payload is one of these existing values. The control edge does not create a
second identity wrapper.

---

## 3. What leaves the schema

Delete:

- internal `*Result` sums whose alternatives are consumed immediately;
- internal success, conservative, decision, optional, and rejection junction leaves;
- `continue_after_<operation>` methods;
- publication records that repeat an already aligned value;
- internal direct-result records that contain only the direct output;
- `NominalPublishedEntry`; B04 uses two typed publication continuations instead;
- mandatory `k`, continuation-receiver classes, and per-call continuation proxies;
- `CompilerControlState`, its global family, and all control-state leaves;
- `SourceCheckingDestination`;
- runtime region declarations, conformance registries, checked region-exit wrappers,
  and family freeze machinery;
- the internal `CompilerResult` and ephemeral `CompilerControl` namespaces.

There is one control model per operation. No result-to-continuation adapter is
permitted.

---

## 4. Named-control law

### 4.1 Direct method

```lua
local topology = accepted:derive_control_topology()
```

A total operation has no named exits.

### 4.2 Value operation with peer exits

```lua
return subject:establish_type_meaning(input, machine,
  TypeMeaningMachine.type_meaning_published,
  TypeMeaningMachine.type_meaning_rejected)
```

The ASDL leaf selects one exit:

```lua
return on_published(machine, entry)
```

The operation does not inspect the machine or know its successor graph.

### 4.3 Machine graph node

```lua
function TypeMeaningMachine:type_meaning_published(entry)
  self.entries:append(entry)
  self.cursor = self.cursor + 1
  return self:advance_type_meaning()
end
```

A machine method does not receive another continuation parameter. It already names its
successor. Stable unbound methods act as labels; strict tail calls are graph edges.

### 4.4 Variable destination

Only a genuinely variable join or suspension stores a destination:

```lua
function ParserMachine:resume(value)
  return self.step(self, value)
end
```

`self.step` must be a stable named method, never a closure, mode string, tag, or handler
lookup. Static edges remain direct named method calls.

### 4.5 Exit naming

Exit names are operation-qualified when contracts differ:

```text
checking_published / checking_rejected
layout_published / layout_rejected
kernel_admitted / kernel_no_plan / kernel_rejected
```

Every producer exit and machine transition is a strict Lua tail call. A direct loop
grows no control stack by construction.

### 4.6 Shared ASDL methods

A parent ASDL method can be a field-agnostic shared default or delegation contract.
It must not inspect a child class, `kind`, tag, action, or field shape. Several leaves
can reference the same stable Lua function directly. Leaf overrides own all genuine
variant differences.

---

## 5. Aggregate-machine law

Five whole-population operations use frozen ASDL finalization inputs:

| B | Final operation | Finalization input |
|---|---|---|
| B03 aggregate | `SemanticProgramSpine:resolve_namespaces` | `ResolutionFinalizationInput` |
| B22 aggregate | `CodeConstructionRequest:construct_monomorphic_code` | `CodeConstructionFinalizationInput` |
| B23 aggregate | `CodeValidationRequest:validate_code_structure` | `CodeValidationFinalizationInput` |
| B54 aggregate | `BackendConstructionRequest:construct_backend_unit` | `BackendConstructionFinalizationInput` |
| B56 aggregate | `GnuCEmitter:validate_and_serialize_c` | `CSerializationFinalizationInput` |

A narrow aggregate machine owns its population, cursor, typed builders, finalization
frontier, and named graph methods. It is implementation state, not ASDL meaning.

Direct children run in an ordinary loop. Multi-exit children receive the machine and
stable unbound methods from its class; each selected method advances, rejects, or
finalizes. A typed builder preserves order and stops mutating when its sequence enters
an ASDL finalization input.

The finalization products are:

```text
record ResolutionFinalizationInput { policy:ResolutionInput, occupancies:many NamespaceOccupancyEntry, references:many ResolvedReferenceEntry }
record CodeConstructionFinalizationInput { identities:ref CodeIdentityProjection, contributions:many CodeConstructionContribution }
record TopologyDerivationInput { def_use:many DefUseContributions, topology:many TopologyContributions }
record CodeValidationFinalizationInput { accepted:many CodeValidationSubject, topology:ref TopologyDerivationInput }
record BackendConstructionFinalizationInput { identities:ref BackendIdentityProjection, contributions:many BackendConstructionContribution }
record CSerializationFinalizationInput { input:ref CSerializationInput, texts:many CEntityText }
```

The five narrow Lua machine shapes are:

| Machine | Borrowed exact frontier | Mutable plane before freeze | Frozen output |
|---|---|---|---|
| `ResolutionMachine` | program receiver, `ResolutionInput`, ordered declarations | cursor, occupancies, references | `ResolutionFinalizationInput` |
| `CodeConstructionMachine` | `CodeConstructionRequest`, `CodeIdentityProjection`, ordered C03/C13–C19 subjects | cursor, contributions | `CodeConstructionFinalizationInput` |
| `CodeValidationMachine` | `CodeValidationRequest`, ordered C21–C25 subjects | cursor, accepted subjects, def-use contributions, topology contributions | `CodeValidationFinalizationInput` with one `TopologyDerivationInput` |
| `BackendConstructionMachine` | `BackendConstructionRequest`, `BackendIdentityProjection`, ordered C21–C27 subjects | cursor, contributions | `BackendConstructionFinalizationInput` |
| `CSerializationMachine` | emitter, `CSerializationInput`, ordered C26/C27 subjects | cursor, accepted subjects, entity texts | `CSerializationFinalizationInput` |

Each machine has one coherent computation and one named transition graph. Each builder
freezes once, creates the named ASDL input, and rejects later mutation. Freezing ends
that builder plane, not the machine. The machine passes itself and its named publication
or rejection methods to the aggregate finalization operation, then tail-calls its next
named node.

`CodeAccepted` carries the validated `TopologyDerivationInput` from B23 to its one
B24 consumer. It is the O13 gate, not a publication wrapper.

B03 derives `ResolutionFacet.shadowing` at finalization from the receiver’s program
scope topology, the resolution policy, collected namespace occupancies, and collected
resolved references. C03 does not publish a separate shadowing contribution.

All six subordinate rejection continuations are terminal in Step-9R. No aggregate
rejection fold is defined.

---

## 6. Coordinator law

The compilation, post-expansion, analysis, planning, realization, and host labels name
running computations only when an object actually owns that evolving state. Such machine
objects are not ASDL values or semantic authorities.

They may:

- enumerate an authoritative ordered population;
- construct exact requests;
- pass themselves plus stable unbound named exit methods;
- maintain narrow private cursors and builders;
- tail-call the next named machine method;
- seal a public boundary.

They must not classify ASDL leaves, inspect reason kinds, select fallback policy,
strengthen conservative evidence, mutate a published facet, or retain a generic
compiler context.

Derived B17/B19/B20/B21 S1 values re-enter B03–B06, B08–B11, and B13–B16 through
ordinary named machine-method calls. No stored destination sum is necessary.

B55 runs before B38 or B48. B52 runs once per exact S2/S3 generation and is reused
during realization. These are sequencing rules, not new data dependencies.

---

## 7. B01–B24 signatures

`continuation:` lists peer named exit functions. Each function receives the exact
running machine first, followed by the shown payload.

| B | Owner and operation | Target form | Durable payload/reason | Old disposition |
|---|---|---|---|---|
| B01 | `ProgramInput:materialize_authored` | continuation: `authored_materialized(program)`; `authored_rejected(reason)` | S1 / `AuthoredMaterializationReason` | delete `AuthoredMaterializationResult` |
| B02 | `MetaPropertyQuery:synthesize` | continuation: `synthesis_generated(declarations)`; `synthesis_rejected(reason)` | generated declarations / `SynthesisReason` | delete `SynthesisResult` |
| B03 | `SemanticProgramSpine:resolve_namespaces` | aggregate finalization continuation with `ResolutionFinalizationInput`: `resolution_published(facet)`; `resolution_rejected(reason)` | F01 / `ResolutionReason` | delete `ResolutionResult` |
| B04 | `NominalSubject:establish_nominal_meaning` | continuation: `nominal_declaration_published(entry)`; `nominal_child_published(entry)`; `nominal_rejected(reason)` | F02 entries / `NominalMeaningReason` | delete `NominalMeaningResult` and `NominalPublishedEntry` |
| B05 | `TypeForm:establish_type_meaning` | continuation: `type_meaning_published(entry)`; `type_meaning_rejected(reason)` | F03 / `TypeMeaningReason` | delete `TypeMeaningResult` |
| B06 | C06–C12 leaf `interpret_intrinsic` | continuation: `intrinsic_published(meaning)`; `intrinsic_rejected(reason)` | intrinsic meaning / `IntrinsicMeaningReason` | delete `IntrinsicMeaningResult` |
| B07 | `CodeOperationAttributionRequest:attribute_code_operation` | continuation: `attribution_published(entry)`; `attribution_rejected(reason)` | F14 / `OperationAttributionReason` | delete `OperationAttributionResult` |
| B08 | C13–C18 leaf `check` | continuation: `checking_published(entry)`; `checking_rejected(reason)` | F04 / `CheckingReason` | delete `CheckingResult` |
| B09 | C19 leaf `prove_control_legality` | continuation: `control_published(entry)`; `control_rejected(reason)` | F05 / `ControlReason` | delete `ControlMeaningResult` |
| B10 | C20 leaf `canonicalize_contract` | continuation: `contract_published(entry)`; `contract_rejected(reason)` | F06 / `ContractReason` | delete `ContractMeaningResult` |
| B11 | `StaticOwnershipRequest:derive_static_ownership` | continuation: `static_ownership_published(entry)`; `static_ownership_rejected(reason)` | F07 / `StaticOwnershipReason` | delete `StaticOwnershipResult` |
| B12 | `StorageOwnershipRequest:refine_storage_ownership` | continuation: `storage_ownership_published(entry)`; `storage_ownership_rejected(reason)` | F34 / `StorageOwnershipReason` | delete `StorageOwnershipResult` |
| B13 | foldable expression `evaluate_constant` | continuation: `constant_published(entry)`; `constant_rejected(reason)` | F08 / `ConstantEvaluationReason` | delete `ConstantEvaluationResult` |
| B14 | `CaptureDiscoveryRequest:discover_captures` | continuation: `capture_published(entry)`; `capture_rejected(reason)` | F09 / `CaptureDiscoveryReason` | delete `CaptureDiscoveryResult` |
| B15 | `LayoutRequest:project_layout` | continuation: `layout_published(entry)`; `layout_rejected(reason)` | F10 / `LayoutReason` | delete `LayoutResult` |
| B16 | `CallableAbiRequest:project_callable_abi` | continuation: `abi_published(entry)`; `abi_rejected(reason)` | F11 / `CallableAbiReason` | delete `CallableAbiResult` |
| B17 | `CapturedClosureRepresentationRequest:represent_closure` | continuation: `closure_represented(entry)`; `closure_rejected(reason)` | derived S1/F12 / `ClosureRepresentationReason` | delete `CapturedClosureResult`, `ClosurePublication` |
| B18 | `NoCaptureRepresentationRequest:preserve_uncaptured_callable` | continuation: `no_capture_unchanged(program)`; `no_capture_rejected(reason)` | identity-preserving S1 / `NoCaptureReason` | delete `NoCaptureResult` |
| B19 | `OpenRegionInvocation:expand_open_region` | continuation: `open_region_expanded(program)`; `open_region_rejected(reason)` | derived S1 / `OpenRegionReason` | delete `OpenRegionResult` |
| B20 | `SealMaterializationRequest:materialize_seal` | continuation: `seal_materialized(entry)`; `seal_rejected(reason)` | derived S1/F13 / `SealMaterializationReason` | delete `SealMaterializationResult`, `SealPublication` |
| B21 | `SealedCallRoutingRequest:route_sealed_call` | continuation: `sealed_call_routed(entry)`; `sealed_call_rejected(reason)` | derived S1/F13 / `SealedCallRoutingReason` | delete `SealedCallRoutingResult` |
| B22 | `CodeConstructionRequest:construct_monomorphic_code` | aggregate finalization continuation with `CodeConstructionFinalizationInput`: `code_constructed(code)`; `code_construction_rejected(reason)` | S2 / `CodeConstructionReason` | delete `CodeConstructionResult` |
| B23 | `CodeValidationRequest:validate_code_structure` | aggregate finalization continuation with `CodeValidationFinalizationInput`: `code_accepted(gate)`; `code_validation_rejected(reason)` | O13 gate / `CodeValidationReason` | delete `CodeValidationResult` |
| B24 | `CodeAccepted:derive_control_topology` | direct `ControlTopologySpine` | S3 | already direct |

B18’s unchanged alternative remains explicit. It is never `nil`, a boolean, or an
implicit no-op.

---

## 8. B25–B36 signatures

| B | Owner and operation | Continuations | Durable payload/reason | Delete |
|---|---|---|---|---|
| B25 | `LoopMeaningRequest:derive_loop_meaning` | `flow_published(entry)`; `flow_rejected(reason)` | F19 including `UncountedLoop` / `FlowMeaningReason` | `LoopMeaningResult` |
| B26 | `InductionRelationRequest:derive_induction_relations` | `induction_published(entry)`; `induction_unavailable(reason)`; `induction_rejected(reason)` | F20 / typed reasons | `InductionResult` |
| B27 | `CodeValueAlgebraRequest:derive_value_algebra` | `value_algebra_published(entry)`; `value_algebra_unavailable(reason)`; `value_algebra_rejected(reason)` | F15 / typed reasons | `ValueAlgebraResult` |
| B28 | `LoopAlgebraRequest:derive_loop_algebra` | `loop_algebra_published(entry)`; `loop_algebra_unavailable(reason)`; `loop_algebra_rejected(reason)` | F21 / typed reasons | `LoopAlgebraResult` |
| B29 | `MemorySpineRequest:derive_memory_spine` | `memory_spine_published(spine)`; `memory_spine_rejected(reason)` | S4 / `MemorySpineReason` | `MemorySpineResult` |
| B30 | `MemoryObjectMeaningRequest:derive_object_meaning` | `object_meaning_published(entry)`; `object_meaning_rejected(reason)` | dense F24 / `ObjectMeaningReason` | `ObjectMeaningResult` |
| B31 | `MemoryContractRealizationRequest:realize_contracts` | `contract_realized(entry)`; `contract_realization_rejected(reason)` | F27 / reason | `ContractRealizationResult` |
| B32 | `MemoryAccessMeaningRequest:derive_access_meaning` | `access_meaning_published(entry)`; `access_meaning_rejected(reason)` | dense F25 / reason | `AccessMeaningResult` |
| B33 | `MemoryRelationRequest:derive_relations` | `relation_published(entry)`; `relation_unavailable(reason)`; `relation_rejected(reason)` | F26 / typed reasons | `MemoryRelationResult` |
| B34 | `OperationEffectRequest:classify_operation_effect` | `operation_effect_published(entry)`; `operation_effect_rejected(reason)` | dense F16 / reason | `OperationEffectResult` |
| B35 | `AcyclicCallableEffectRequest:compose_callable_effects` | `callable_effect_published(entry)`; `callable_effect_rejected(reason)` | dense F17 / reason | `CallableEffectResult` |
| B36 | `RecursiveCallableComponentEffectRequest:compose_recursive_component_effects` | `recursive_effects_published(entries)`; `recursive_effects_rejected(reason)` | F17 / reason | `RecursiveEffectResult` |

The published entry leaf carries each P-or-C distinction. Continuation functions must
not strengthen conservative data.

---

## 9. B37–B61 signatures

| B | Owner and operation | Target form | Durable payload/reason | Old disposition |
|---|---|---|---|---|
| B37 | `LoopKernelCandidateRequest:recognize_kernel` | continuation: `kernel_admitted(meaning)`; `kernel_no_plan(reason)`; `kernel_rejected(reason)` | S5/F28 / reasons | delete `KernelRecognitionResult`, `KernelPublication` |
| B38 | `ScheduleSelectionRequest:select_schedule` | continuation: `schedule_selected(entry)`; `schedule_no_plan(reason)`; `schedule_rejected(reason)` | F29 / reasons | delete `ScheduleSelectionResult` |
| B39 | `FusedProjectionRequest:project_fused_computation` | continuation: `fusion_admitted(meaning)`; `fusion_unavailable(reason)`; `fusion_rejected(reason)` | S6/F30 / reasons | delete `FusedProjectionResult`, `FusedPublication` |
| B40 | `UsePopulationCandidateRequest:enumerate_use_candidate` | continuation: `use_population_candidate(candidate)`; `use_population_unrealizable(reason)`; `use_population_rejected(reason)` | candidate / reasons | delete `UsePopulationResult` |
| B41 | `UseMeaningCandidateRequest:derive_use_meaning_candidate` | continuation: `use_meaning_candidate(candidate)`; `use_meaning_rejected(reason)` | candidate / reason | delete `UseMeaningCandidateResult` |
| B42 | `CoordinateCandidateRequest:derive_coordinate_candidate` | continuation: `coordinate_candidate(candidate)`; `coordinate_unrealizable(reason)`; `coordinate_rejected(reason)` | candidate / reasons | delete `CoordinateCandidateResult` |
| B43 | `UseSpineAdmissionRequest:admit_use_spine` | continuation: `use_spine_admitted(spine)`; `use_spine_rejected(reason)` | S7 / reason | delete `UseAdmissionResult` |
| B44 | `UseMeaningPublicationRequest:publish_use_meaning` | direct `MaterializedUseFacet` | F31 | delete `UseMeaningPublished` |
| B45 | `CoordinatePublicationRequest:publish_coordinates` | direct `CoordinateFacet` | F32 | delete `CoordinatesPublished` |
| B46 | `PointerQualificationRequest:qualify_pointer_uses` | continuation: `pointer_qualified(entry)`; `pointer_unqualified(reason)`; `qualification_unavailable(reason)`; `pointer_unrealizable(reason)`; `qualification_rejected(reason)` | F33 / reasons | delete `PointerQualificationResult` |
| B47 | `AddressRecordRequest:realize_address_record` | continuation: `address_ready(record)`; `address_unrealizable(reason)`; `address_rejected(reason)` | address / reasons | delete `AddressRecordResult` |
| B48 | `BaselineAdmissionRequest:admit_baseline` | continuation: `baseline_admitted(facet)`; `baseline_rejected(reason)` | F18 / reason | delete `BaselineAdmissionResult` |
| B49 | `SubjectCommitmentRequest:select_subject_strategy` | continuation: `attempt_closed_form(attempt)`; `attempt_fused(attempt)`; `baseline_committed(entry)`; `strategy_rejected(reason)` | attempt/F22/reason | delete `StrategyDecisionResult`; keep `StrategyFailureReason` |
| B50 | each `StrategyResumeRequest:resume_subject` leaf | same continuations as B49 | attempt/F22/reason | shared result already deleted |
| B51 | `CommitRealizedFragmentRequest:commit_fragment` | continuation: `fragment_committed(entry)`; `fragment_commit_rejected(reason)` | F22 / reason | delete `FragmentCommitResult` |
| B52 | `DominanceRequest:derive_dominance` | direct `DominanceFacet` | F23 | delete `DominancePublished` |
| B53 | each `FragmentContributionRequest:realize_fragment_contribution` leaf | continuation: `fragment_realized(contribution)`; `fragment_unrealizable(reason)`; `fragment_rejected(reason)` | fragment / reasons | delete `FragmentRealizationResult` |
| B54 | `BackendConstructionRequest:construct_backend_unit` | aggregate finalization continuation with `BackendConstructionFinalizationInput`: `backend_constructed(backend)`; `backend_rejected(reason)` | S8 / reason | delete `BackendConstructionResult` |
| B55 | `GnuCEmitter:declare_capability` | direct `GnuCEmitterCapability` | capability | delete `EmitterCapabilityPublished` |
| B56 | `GnuCEmitter:validate_and_serialize_c` | aggregate finalization continuation with `CSerializationFinalizationInput`: `c_artifact_accepted(artifact)`; `c_serialization_rejected(reason)` | artifact / reason | delete `CSerializationResult` |
| B57 | `GccCookRequest:cook_and_load` | sealed `GccCookResult` | live session or host failure | keep |
| B58 | `LiveGccSession:resolve_symbol` | sealed `SymbolResolutionResult` | symbol capability or host failure | keep |
| B59 | `LiveGccSession:release` | sealed direct `SessionReleased` | release observation | keep |
| B60 | `ReleasedGccSession:release` | sealed direct `AlreadyReleased` | idempotent observation | keep |
| B61 | `ReleasedGccSession:resolve_symbol` | sealed direct `UseAfterReleaseFailed` | host failure | keep |

Host failures never enter semantic rejection.

---

## 10. Subordinate signatures

| Operation | Form | Exact exits or output | Delete |
|---|---|---|---|
| C03 `contribute_namespace` | continuation | `namespace_contributed(entries)`; `namespace_rejected(reason)` | `NamespaceContributionResult` |
| C03 `resolve_decl_references` | continuation | `references_resolved(entries)`; `references_rejected(reason)` | `ReferenceResolutionResult` |
| C03/C13–C19 `construct_code_entity` | continuation | `code_entity_contributed(contribution)`; `code_entity_rejected(reason)` | `CodeEntityConstructionResult` |
| C21–C25 `validate_structure` | continuation | `code_entity_accepted(subject)`; `code_entity_rejected(reason)` | `CodeEntityValidationResult` |
| C24/C25 `contribute_def_use` | direct | `DefUseContributions` | none |
| C25 `contribute_topology` | direct | `TopologyContributions` | none |
| C22/C24 `memory_access_causes` | direct | ordered `many MemoryAccessCause` | none |
| C21–C27 `construct_backend_entity` | continuation | `backend_entity_contributed(contribution)`; `backend_entity_rejected(reason)` | `BackendEntityConstructionResult` |
| C26/C27 `validate_c` | continuation | `c_entity_accepted(subject)`; `c_entity_rejected(reason)` | `CEntityValidationResult` |
| accepted C26/C27 `emit_c` | direct | `CEntityText` | accepted wrapper leaf |
| A29 `AlternativeRejectionRequest:record_rejection` | direct | `RejectedAlternative` | none |

---

## 11. Old §12 disposition

Old §12 contains 70 declarations: 59 sums and 11 records.

### 11.1 Sums

- delete 55 internal operation-result sums;
- delete `NominalPublishedEntry`;
- move `StrategyFailureReason` to `CompilerLower`;
- keep `GccCookResult` and `SymbolResolutionResult` in `CompilerHost`.

`CEntityValidationResult` is outside old §12 and is also deleted. The schema-wide
internal result-sum deletion count is 56.

### 11.2 Records

Delete eight internal wrappers:

```text
ClosurePublication
SealPublication
KernelPublication
FusedPublication
UseMeaningPublished
CoordinatesPublished
DominancePublished
EmitterCapabilityPublished
```

Keep three host records:

```text
SessionReleased
AlreadyReleased
UseAfterReleaseFailed
```

After redistribution, `CompilerResult` owns nothing and is removed.

---

## 12. Reason ownership

| Authority | Target namespace |
|---|---|
| A01–A05, A06 source, A07–A09, A10 static, A11–A17 | `CompilerSource` |
| A06 code, A10 storage, A21–A24 | `CompilerAnalysis` |
| A18–A20 | `CompilerCode` |
| A25–A30 | `CompilerLower` |
| A31–A32 | `CompilerBackend` |
| A33 failures and sealed results | `CompilerHost` |
| final semantic envelope | `CompilerBoundary` |

`OptionalRealizationReason` belongs to `CompilerAnalysis` beside F22 rejection
history. `StrategyFailureReason` belongs to A29 in `CompilerLower`.
`SemanticRejectReason` and `TypedSemanticRejection` belong to `CompilerBoundary`.
Every concrete reason leaf owns `render_reason`. Each authority reason sum also provides
a field-agnostic `to_semantic_rejection` method inherited by its leaves; it constructs
the exact boundary wrapper without class inspection. The running host machine calls that
method and tail-calls its named `semantic_rejected` method. That method is the value’s
sole consumer; rejection does not re-enter compiler semantics. The exact sealed edge is:

```text
authority_reason:to_semantic_rejection() -> TypedSemanticRejection
HostCompilationMachine.semantic_rejected(machine, rejection:TypedSemanticRejection) -> Answer
```

This is not a B operation and never carries a host failure.

> No generic compilation-success or host-failure envelope exists.

---

## 13. New and changed durable declarations

In addition to the finalization inputs in §5, Step-9R adds or changes only durable
semantic and one-consumer boundary data:

```text
record CodeValueAlgebraSubject { value:CompilerCode.CodeValue, ordinal:CompilerBase.Ordinal }
record CodeValueAlgebraPopulation { code:ref CompilerCode.MonomorphicCodeSpine, subjects:many CodeValueAlgebraSubject }

record TopologyDerivationInput { def_use:many DefUseContributions, topology:many TopologyContributions }
record MemoryRelationPopulationRequest { memory:ref MemorySpine, objects:many ref MemoryObjectEntry, accesses:many ref MemoryAccessEntry, contracts:many ref ContractRealizationEntry, flow:many ref LoopFlowEntry, induction:many ref InductionEntry, declared:many ref ContractEvidenceEntry, layout:many ref LayoutEntry, ownership:many ref StaticOwnershipEntry }
record MemoryRelationSubject { ordinal:CompilerBase.Ordinal, request:ref MemoryRelationRequest }
record MemoryRelationPopulation { memory:ref MemorySpine, subjects:many MemoryRelationSubject }

sum StrategyAlternative =
  KernelPlanningAlternative { request:ref CompilerLower.LoopKernelCandidateRequest }
| SchedulePlanningAlternative { request:ref CompilerLower.ScheduleSelectionRequest }
| FusionPlanningAlternative { request:ref CompilerLower.FusedProjectionRequest }
| RealizationStrategyAlternative { attempt:LoweringAttempt }

record RejectedAlternative { alternative:StrategyAlternative, outcome:OptionalRealizationReason }
```

`CodeValidationReason` gains `A19GenerationMismatch { site:A19Site,
mismatch:CompilerBase.ProvenanceExpectation }`, so A19 can reject cross-generation S2
validation evidence explicitly.

`AlternativeRejectionRequest` is a closed A29 request sum with one leaf for each
optional-realization reason family. Each leaf pairs an exact `StrategyAlternative`
leaf with its exact reason and returns one `RejectedAlternative` directly.

`SubjectCommitmentRequest` gains ordered `rejected` history. Every
`StrategyResumeRequest` leaf gains exact remaining candidates and ordered rejected
history. A29 leaf methods alone select the next attempt or baseline.

A18 `project_code_identities`, A22 `project_value_algebra_population`, A23
`project_relation_population`, and A31 `project_backend_identities` are total direct
operations that create one-consumer boundary data. Each uses an ordinary direct loop
with one local dense output array and constructs its ASDL projection once; no aggregate
machine or resumable cursor is created for the call. A22 owns value population order. A23 owns
relation pair eligibility and order. B27 and B33 remain per-subject operations.

No machine, builder, destination, callback, or coordinator type is added to ASDL.
Machines are ordinary named Lua objects for computations in progress.

---

## 14. Conservative and identity proof

Dense conservative facts remain ASDL entries, including `UncountedLoop`,
`UnknownMemoryObject`, unproven/unknown safety statuses, `MayAlias`, incomplete
effects, and unresolved external effects.

Sparse no-entry alternatives remain direct continuation exits with typed reasons.
Only optional realization reasons enter A29 fallback. Conservative analysis reasons
never do.

Creation boundaries remain:

- B01 creates S1;
- B17/B19/B20/B21 create causally derived S1 where applicable;
- B22 creates S2;
- B24 creates S3;
- B29 creates S4;
- B37 creates S5 only through `kernel_admitted`;
- B39 creates S6 only through `fusion_admitted`;
- B43 creates S7 only through `use_spine_admitted`;
- B49 baseline commitment and B51 fragment commitment create F22;
- B54 creates S8;
- B56 creates `CArtifact`.

---

## 15. Closure theorem

The named-machine model is closed when:

1. O01–O40, A01–A33, B01–B61, C01–C29, S1–S8, and F01–F34 retain
   their ownership and production boundaries;
2. every total operation returns one exact value directly;
3. every immediate multi-exit operation has one fixed ordered peer-exit signature;
4. focused tests enumerate every supporting concrete sum leaf and verify direct
   ownership, legal shared inheritance, or explicit delegation;
5. every focused test drives every named exit with its exact machine and payload;
6. no internal result junction, `continue_after_*`, `k` wrapper, anonymous context,
   universal machine family, control-state family, or runtime conformance registry remains;
7. no parent method inspects leaf class, kind, tag, action, or field shape;
8. every dense conservative fact remains data and every sparse no-entry choice remains
   a typed named exit;
9. every rejection preserves its exact authority site, reason, and origin;
10. host failures remain disjoint from semantic rejection;
11. aggregate accumulators preserve order and stop mutating at ASDL publication;
12. all six subordinate rejection continuations are terminal;
13. named-machine tail-call chains are stack safe with `jit.off()`;
14. every machine owns one coherent computation, every exit is a stable unbound method
    of the expected machine class, and machine methods name successors directly;
15. no generic context, side table, handler map, callback table, or optional soup is
    introduced;
16. all ASDL references resolve and no deleted result name remains.

---

## 16. Step-9R transcription requirements

The target schema must:

1. retain and revalidate durable declarations from old §§3–11 and §13;
2. delete the old internal result layer and `CEntityValidationResult`;
3. add the five finalization inputs, `TopologyDerivationInput`, the four direct
   identity/population projection operations, A22/A23 ordered populations, and
   `MemoryRelationPopulationRequest`;
4. add `StrategyAlternative` and exact A29 rejection-recording requests;
5. update B49/B50 request frontiers;
6. move sites and reasons to their authority namespaces;
7. retain only sealed public result values;
8. replace old result signatures with the direct and named-machine exit tables above;
9. remove `CompilerResult`, `CompilerControl`, `CompilerControlState`, and
   `SourceCheckingDestination`;
10. validate declaration/reference closure and duplicate names;
11. rerun full O/A/B/C/S/F coverage;
12. define focused leaf-method, named-exit, machine-coherence, terminal-rejection,
    builder-order, allocation, and `jit.off()` stack tests.

No runtime or compiler migration starts before Step-9R closes.

---

## 17. Final model

```text
durable meaning       -> ASDL products, sums, entities, spines, facets, reasons
semantic dispatch     -> ASDL leaf methods and legal shared defaults
one output            -> direct return
immediate choice      -> peer named exits
running computation   -> one named machine object
static control node   -> named machine method
control edge          -> strict tail call
variable destination  -> stable named method stored on the machine
aggregate state       -> aggregate machine + typed builders + frozen ASDL input
stored/public choice  -> ASDL boundary data
```

The compiler remains ordinary Lua around a precise ASDL value model. Running computation
state lives in named machine objects, and their methods are the source-visible static
control graph. No machine hierarchy or control runtime stands underneath them.
