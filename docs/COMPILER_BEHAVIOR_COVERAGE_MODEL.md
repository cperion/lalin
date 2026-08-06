# Compiler Behavior-Coverage Model

Status: **Step 8 closed — conceptual coverage before ASDL transcription or implementation**

This document is downstream of:

- `docs/COMPILER_SEMANTIC_OBLIGATIONS.md`;
- `docs/COMPILER_ENTITY_IDENTITY_MODEL.md`;
- `docs/COMPILER_CONCERN_AUTHORITY_MODEL.md`;
- `docs/COMPILER_SPINE_MODEL.md`;
- `docs/COMPILER_FACET_MODEL.md`;
- `docs/COMPILER_WORLD_MODEL.md`;
- `docs/COMPILER_RECEIVER_OPERATION_RESULT_MODEL.md`;
- `docs/ASDL_GUIDE.md`.

It closes the missing behavior proof. Names here are conceptual ASDL constructor and method contracts,
not compatibility aliases, file layouts, constructor field orders, or implementation instructions.
Current schemas are evidence only. No world, phase machine, generic compiler context, side map, handler
table, compatibility layer, or LLBL compilation process is admitted.

---

## 1. Coverage theorem

### 1.1 What one coverage row means

A constructor named below is a closed semantic alternative, not a category placeholder. A parameterized
name such as `SignedIntegerType(bits)` denotes one ASDL constructor with a typed scalar field, not one
constructor per bit width. Every constructor that supports an operation owns that method directly or an
explicit typed delegation method. Parent unions may provide a truly shared default but may not inspect
child class, `kind`, tag, operation name, or reason text.

Aggregate receivers such as S1, S2, and S8 own deterministic sequencing. Their child constructors own
case behavior through the subordinate methods listed in §2. Sequencing is not authorization to reproduce
a child's semantics.

### 1.2 Six outcome classes

| Code | Class | Persistence and continuation |
|---|---|---|
| P | publication | publishes a spine/facet/entity/gate/artifact/value/resource, then returns to exact sequencing |
| C | conservative outcome | either publishes a typed conservative entry or explicitly produces no sparse entry; continues weakened |
| D | immediate decision | transient one-consumer result constructs exactly one next request; publishes no semantic fact |
| R | terminal semantic rejection | preserves typed cause/origin and ends the semantic transaction |
| U | optional realization outcome | returns typed no-plan/unrealizable evidence to A29; baseline remains valid |
| H | host failure | routes only through A33/Host API; never becomes semantic rejection |

`AttemptClosedForm`, `AttemptFused`, no-capture unchanged, and A28 candidate records are D, not fake
facts. A21/A22 unavailable outcomes are C with `entry = no`; A25–A30 optional failures are U. LLBL
delivery/adaptation failures are A01 R leaves with typed foreign causes. A33 is the sole H family.

### 1.3 Required methods

Every operation-specific result sum has a correspondingly named `continue_after_<operation>` method on
all concrete result leaves. P/C/D/U leaves invoke or construct the exact next request named in §§3–6;
R leaves return the typed transaction rejection; H leaves return the typed host outcome. Reason leaves
own `render_reason`. Coordinators call these methods and never classify results.

Every operation that crosses a generation or provenance boundary also admits an authority-specific
`GenerationMismatch` or `ProvenanceMismatch` R reason when expected and actual allocations differ. Those
names are prefixed by
their owning authority in the transcription; they never become U or C.

### 1.4 Authority-to-operation closure

| Authorities | Coverage operations |
|---|---|
| A01–A05 | B01; B02; B03; B04; B05 |
| A06–A10 | B06–B07; B08; B09; B10; B11–B12 |
| A11–A17 | B13; B14; B15; B16; B17–B18; B19; B20–B21 |
| A18–A24 | B22; B23; B24; B25–B26; B27–B28; B29–B33; B34–B36 |
| A25–A29 | B37; B38; B39; B40–B47; B48–B51 |
| A30–A33 | B52–B53; B54; B55–B56; B57–B61 |

This is a partition: every A01–A33 authority appears exactly once and every B01–B61 operation belongs to
exactly one authority.

---

## 2. Closed semantic constructor and subordinate-method catalogs

These catalogs are the no-category-placeholder proof. A later schema constructor not assigned here is a
Step-8 model change, not an implementation detail.

### 2.1 Authored declarations, nominals, and types

| Set | Exact constructors | Required subordinate methods | Anchor |
|---|---|---|---|
| C01 input | `DocumentProgramInput`; `BuilderProgramInput`; `GeneratedDeclarationAdmissionInput` | `materialize_authored` | O01/O02/O36 |
| C02 meta query | `TypeNameQuery`; `EntriesQuery`; `DeclarationsQuery`; `MethodQuery`; `MissingMethodQuery`; `MissingEntryQuery`; `ApplyQuery`; `CastQuery` | `synthesize` | O36 hook list |
| C03 declaration | `FunctionDeclaration`; `ExternDeclaration`; `StructDeclaration`; `UniqueStructDeclaration`; `UnionDeclaration`; `HandleDeclaration`; `RegionDeclaration`; `ConstantDeclaration`; `StaticDeclaration` | `contribute_namespace`; `resolve_decl_references`; accepted forms also `construct_code` where physical output exists | O01/O03/O12/O30/O40 |
| C04 nominal | `StructNominal`; `UniqueNominal`; `UnionNominal`; `HandleNominal`; `FieldMember`; `VariantMember`; `ConstructorMeaning`; `PatternMeaning` | `establish_nominal_meaning`; child `establish_membership` | O04/O30/O39/O40 |
| C05 type | `VoidType`; `BoolType`; `SignedIntegerType(bits)`; `UnsignedIntegerType(bits)`; `FloatType(bits)`; `IndexType`; `PointerType`; `ArrayType`; `SliceType`; `ViewType`; `LeaseType`; `OwnedType`; `ReadonlyType`; `WriteonlyType`; `NoaliasType`; `NoescapeType`; `InvalidateType`; `PreserveType`; `HandleType`; `FunctionType`; `ClosureType`; `NominalType`; `ImportedCType`; `ImportedCFunctionPointerType` | `establish_type_meaning`; value-capable leaves `zero_meaning`; physical leaves participate in exact A13/A14 requests | O04/O05/O31/O33/O37 |

Access wrappers are separate constructors because their legality differs; they are not a base type plus
nullable flags. `UniqueNominal` owns entity kind, A10 owns copy/transfer legality, and A23 owns allocated
storage identity.

### 2.2 Intrinsic operation constructors

Every constructor below owns `interpret_intrinsic`; accepted S2 operation constructors own or explicitly
delegate `attribute_code_operation` to A06's exact request without a parent selector.

| Set | Exact constructors |
|---|---|
| C06 unary | `NegateOp`; `LogicalNotOp`; `BitwiseNotOp` |
| C07 arithmetic/bit | `AddOp`; `SubtractOp`; `MultiplyOp`; `DivideOp`; `RemainderOp`; `BitAndOp`; `BitOrOp`; `BitXorOp`; `ShiftLeftOp`; `LogicalShiftRightOp`; `ArithmeticShiftRightOp` |
| C08 comparison/logic | `EqualOp`; `NotEqualOp`; `LessOp`; `LessEqualOp`; `GreaterOp`; `GreaterEqualOp`; `LogicalAndOp`; `LogicalOrOp` |
| C09 source cast | `ConvertCast`; `TruncateCast`; `ZeroExtendCast`; `SignExtendCast`; `Bitcast`; `SaturatingCast` |
| C10 machine cast | `IdentityMachineCast`; `MachineBitcast`; `IntegerReduce`; `SignedExtend`; `UnsignedExtend`; `FloatPromote`; `FloatDemote`; `SignedToFloat`; `UnsignedToFloat`; `FloatToSigned`; `FloatToUnsigned` |
| C11 intrinsic | `PopcountIntrinsic`; `CountLeadingZerosIntrinsic`; `CountTrailingZerosIntrinsic`; `RotateLeftIntrinsic`; `RotateRightIntrinsic`; `ByteSwapIntrinsic`; `FmaIntrinsic`; `SqrtIntrinsic`; `AbsIntrinsic`; `FloorIntrinsic`; `CeilIntrinsic`; `TruncateFloatIntrinsic`; `RoundIntrinsic`; `TrapIntrinsic`; `AssumeIntrinsic` |
| C12 atomic | `AtomicLoadOp`; `AtomicStoreOp`; `AtomicAddOp`; `AtomicSubtractOp`; `AtomicAndOp`; `AtomicOrOp`; `AtomicXorOp`; `AtomicExchangeOp`; `AtomicCompareExchangeOp`; `AtomicFenceOp` |

Operator leaves use typed double dispatch to operand-type leaves where necessary: the operator selects
the operation and the concrete type leaf owns type-family behavior. Neither side uses class inspection.

### 2.3 Checked source cases

All expression/place/statement constructors own `check`; every admitted checked constructor owns
`construct_code`. Foldable expression constructors also own `evaluate_constant`; non-foldable leaves use
the explicit shared `NonConstantExpression` R default.

| Set | Exact constructors |
|---|---|
| C13 literal/reference | `IntegerLiteral`; `FloatLiteral`; `BooleanLiteral`; `StringLiteral`; `NilLiteral`; `HostLiteral`; `BindingReference` |
| C14 operator expression | `UnaryExpression`; `BinaryExpression`; `CompareExpression`; `LogicExpression`; `CastExpression`; `MachineCastExpression`; `IntrinsicExpression` |
| C15 access/call | `AddressOfExpression`; `DereferenceExpression`; `CallExpression`; `LengthExpression`; `FieldExpression`; `IndexExpression`; `LoadExpression`; `AtomicLoadExpression`; `AtomicRmwExpression`; `AtomicCompareExchangeExpression` |
| C16 aggregate/control expression | `AggregateExpression`; `ArrayExpression`; `IfExpression`; `SelectExpression`; `SwitchExpression`; `ControlExpression`; `DomainControlExpression`; `BlockExpression`; `ClosureExpression`; `ViewExpression`; `ConstructorExpression`; `NullExpression`; `SizeOfExpression`; `AlignOfExpression`; `IsNullExpression` |
| C17 place | `ReferencePlace`; `DereferencePlace`; `FieldPlace`; `IndexPlace` |
| C18 statement | `LetStatement`; `VarStatement`; `AssignmentStatement`; `AtomicStoreStatement`; `AtomicFenceStatement`; `ExpressionStatement`; `AssertStatement`; `IfStatement`; `SwitchStatement`; `VariantSwitchStatement`; `FoldStatement`; `ScanStatement`; `RequiresStatement`; `JumpStatement`; `ConditionalJumpStatement`; `ContinuationJumpStatement`; `OpenEmitStatement`; `SealedCallStatement`; `YieldVoidStatement`; `YieldValueStatement`; `ReturnVoidStatement`; `ReturnValueStatement`; `ControlStatement`; `DomainControlStatement`; `TrapStatement` |

Expression and place roles are distinct constructors. No lvalue boolean or optional place payload is
admitted. `StringLiteral` owns decoded byte length only; target bytes and trailing-NUL policy are A31/A32.

### 2.4 Control and contracts

| Set | Exact constructors | Required method |
|---|---|---|
| C19 control | `FunctionControlBody`; `RegionControlBody`; `EntryControlBlock`; `OrdinaryControlBlock`; `IfControlSite`; `SwitchControlSite`; `VariantSwitchControlSite`; `RangeLoopSite`; `GridLoopSite`; `TiledLoopSite`; `WindowLoopSite`; `JumpTransfer`; `ConditionalTransfer`; `ContinuationTransfer`; `ReturnTransfer`; `YieldTransfer`; `OpenEmitTransfer`; `SealedCallTransfer`; `EntryParameterFlow`; `ForbiddenFor`; `ForbiddenWhile`; `ForbiddenBreak`; `ForbiddenContinue` | `prove_control_legality` |
| C20 contract | `BoundsContract`; `WindowBoundsContract`; `DisjointContract`; `SameLengthContract`; `SoAComponentContract`; `PairNoaliasContract`; `UnaryNoaliasContract`; `ReadonlyContract`; `WriteonlyContract`; `InvalidateContract`; `PreserveContract`; `NoescapeContract` | `canonicalize_contract` |

`EntryParameterFlow` returns one typed source alternative: `ExplicitArgumentSource`,
`ContinuationPayloadSource`, or `SameNameBlockParameterSource`. There is no implicit capture fallback.
Forbidden forms reach A08 as marked source-control constructors so A08, not A01, owns their semantic
rejection.

### 2.5 Monomorphic-code cases

| Set | Exact constructors | Required subordinate methods |
|---|---|---|
| C21 code entity | `CodeType`; `CodeSignature`; `CodeFunction`; `CodeExtern`; `CodeGlobal`; `CodeData`; `CodeRelocation`; `CodeBlock`; `CodeParameter`; `CodeLocal` | `validate_structure`; applicable leaves `construct_backend_entity` |
| C22 code place | `LocalCodePlace`; `GlobalCodePlace`; `DataCodePlace`; `DereferenceCodePlace`; `FieldCodePlace`; `IndexCodePlace`; `ByteRangeCodePlace` | `validate_structure`; `memory_access_causes` |
| C23 code constant | `LiteralCodeConstant`; `NullCodeConstant`; `UndefinedCodeConstant` | `validate_structure`; `construct_backend_entity` |
| C24 code instruction | `ConstInstruction`; `AliasInstruction`; `UnaryInstruction`; `BinaryInstruction`; `FloatBinaryInstruction`; `CompareInstruction`; `CastInstruction`; `SelectInstruction`; `VoidIntrinsicInstruction`; `ValueIntrinsicInstruction`; `AddressOfInstruction`; `GlobalReferenceInstruction`; `PointerOffsetInstruction`; `LoadInstruction`; `StoreInstruction`; `AggregateInstruction`; `ArrayInstruction`; `ViewMakeInstruction`; `ViewDataInstruction`; `ViewLengthInstruction`; `ViewStrideInstruction`; `SliceMakeInstruction`; `SliceDataInstruction`; `SliceLengthInstruction`; `ByteSpanMakeInstruction`; `ByteSpanDataInstruction`; `ByteSpanLengthInstruction`; `ClosureInstruction`; `VariantConstructorInstruction`; `VariantTagInstruction`; `VariantPayloadInstruction`; `CallInstruction`; `AtomicLoadInstruction`; `AtomicStoreInstruction`; `AtomicRmwInstruction`; `AtomicCompareExchangeInstruction`; `AtomicFenceInstruction` | `validate_structure`; `contribute_def_use`; `memory_access_causes`; `classify_operation_effect`; `construct_backend_entity` |
| C25 terminator | `JumpTerminator`; `BranchTerminator`; `SwitchTerminator`; `VariantSwitchTerminator`; `ReturnTerminator`; `TrapTerminator`; `UnreachableTerminator` | `validate_structure`; `contribute_topology`; `contribute_def_use`; `classify_operation_effect`; `construct_backend_entity` |

`memory_access_causes` returns a typed ordered cause sequence. A23 alone turns those causes and ordinals
into S4 access identity; even compound atomic operations cannot hide accesses in an instruction-kind
branch.

### 2.6 Physical-backend and host cases

| Set | Exact constructors | Required subordinate methods |
|---|---|---|
| C26 S8 structural entity | `BackendType`; `BackendSignature`; `BackendFunction`; `BackendExtern`; `BackendGlobal`; `BackendData`; `BackendHelper`; `BackendParameter`; `BackendLocal`; `BackendBlock`; `BackendLabel`; `BackendStatement`; `BackendTerminator`; `BackendInitializer`; `BackendRelocation`; `BaselineContribution`; `AcceptedFragmentContribution` | structural leaves `validate_c`/`emit_c`; statement/terminator leaves delegate payload behavior without inspection |
| C27 S8 operation payload | `BackendConstantOp`; `BackendAliasOp`; `BackendUnaryOp`; `BackendBinaryOp`; `BackendCompareOp`; `BackendCastOp`; `BackendSelectOp`; `BackendAddressOp`; `BackendPointerOffsetOp`; `BackendLoadOp`; `BackendStoreOp`; `BackendAggregateOp`; `BackendViewOp`; `BackendSliceOp`; `BackendClosureOp`; `BackendVariantConstructOp`; `BackendVariantTagOp`; `BackendVariantPayloadOp`; `BackendDirectCallOp`; `BackendExternalCallOp`; `BackendIndirectCallOp`; `BackendClosureCallOp`; `BackendAtomicLoadOp`; `BackendAtomicStoreOp`; `BackendAtomicRmwOp`; `BackendAtomicCompareExchangeOp`; `BackendAtomicFenceOp`; `BackendHelperCallOp`; `BackendJumpTerm`; `BackendBranchTerm`; `BackendSwitchTerm`; `BackendVariantSwitchTerm`; `BackendReturnTerm`; `BackendTrapTerm`; `BackendUnreachableTerm` | every payload leaf owns `validate_c`; `emit_c` |
| C28 emitter | `GnuCEmitter` | `declare_capability`; `validate_and_serialize_c` |
| C29 host receiver | `GccCookRequest`; `LiveGccSession`; `ReleasedGccSession` | `cook_and_load`; live `resolve_symbol`/`release`; released `resolve_symbol`/`release` |

There is exactly one admitted C emitter leaf because emitted GNU-compatible C is the sole native path.
Adding a future emitter is a model change requiring capability, result, reason, and regression rows.

---

## 3. A01–A17 operation/result/reason ledger

Each row is a closed operation family. `cont` names the result method and immediate destination.
Reason names in the R/U columns are concrete constructor candidates; each carries typed subject, origin,
and nested cause where propagation applies.

| ID | Receiver/request and method | Result constructors | R reason constructors | cont |
|---|---|---|---|---|
| B01 | C01 `materialize_authored` | `AuthoredProgramMaterialized[P]`; `AuthoredMaterializationRejected[R]` | `LexicalDeliveryRejected`; `MalformedBracketEvaluation`; `IllegalDocumentRoot`; `MalformedDeclaration`; `MalformedBody`; `InvalidBuilderValue`; `InvalidHostValue`; `UnresolvedGeneratedReference`; `UnsupportedDeclarationCategory`; `RoleAdaptationRejected`; `SpliceRejected`; `A01GenerationMismatch` | `continue_after_materialize`: A02/A03 or terminal |
| B02 | C02 `synthesize` | `GeneratedDeclarations[P]`; `SynthesisRejected[R]` | `UnknownHook`; `RoleMismatch`; `UnsupportedHookResult`; `UnboundedSynthesis`; `DynamicFallbackRejected`; `A02GenerationMismatch` | `continue_after_synthesize`: A01 admission or terminal |
| B03 | S1 + C03 `resolve_namespaces` | `ResolutionPublished[P]`; `ResolutionRejected[R]` | `DuplicateDeclaration`; `MissingName`; `WrongNamespace`; `InvalidQualification`; `IllegalShadowing`; `IncompatibleDeclarationCategory`; `A03GenerationMismatch` | `continue_after_resolution`: semantic fan-out or terminal |
| B04 | C04 `establish_nominal_meaning` | `NominalMeaningPublished[P]`; `NominalMeaningRejected[R]` | `DuplicateMember`; `InvalidNominalRecursion`; `InvalidNominalCategory`; `MalformedVariantPayload`; `InvalidHandleTarget`; `UniqueWithoutIdentityAuthority`; `A04GenerationMismatch` | semantic fan-out or terminal |
| B05 | C05 `establish_type_meaning` | `TypeMeaningPublished[P]`; `TypeMeaningRejected[R]` | `UnknownType`; `InvalidRecursiveType`; `IllegalArrayExtent`; `IllegalTypeComposition`; `IncompatibleType`; `UnsupportedTypeOperation`; `A05GenerationMismatch` | semantic fan-out or terminal |
| B06 | C06–C12 `interpret_intrinsic` | `IntrinsicMeaningPublished[P]`; `IntrinsicMeaningRejected[R]` | `IllegalOperandTypes`; `UndefinedShift`; `UnavailableOverflowMeaning`; `IncompatibleFloatContract`; `IllegalCast`; `IllegalPointerOperation`; `UnsupportedAtomicOrdering`; `IncompatibleOperandWidth`; `A06IntrinsicMismatch` | checking/constant/code consumers or terminal |
| B07 | `CodeOperationAttributionRequest.attribute_code_operation` | `OperationAttributed[P]`; `OperationAttributionRejected[R]` | `UnsupportedCodeOperationMeaning`; `A06CodeMeaningMismatch` | analysis fan-out or terminal |
| B08 | C13–C18 `check` | `CheckedMeaningPublished[P]`; `CheckingRejected[R]` | `UnboundValue`; `TypeMismatch`; `InvalidPlace`; `InvalidCall`; `IllegalCastUse`; `InvalidReturnValue`; `InvalidIndex`; `InvalidNominalUse`; `MalformedVariantUse`; `UnsupportedOperation`; `CheckResolutionRejected`; `CheckNominalRejected`; `CheckOwnershipRejected`; `A07GenerationMismatch` | A08/A09/A10/A18 fan-out or terminal |
| B09 | C19 `prove_control_legality` | `ControlMeaningPublished[P]`; `ControlRejected[R]` | `MissingTerminator`; `MissingSwitchDefault`; `MissingTarget`; `DuplicateTarget`; `InvalidReturnPath`; `IllegalFallthrough`; `BadTransferArgument`; `BadContinuationArgument`; `BadPassthrough`; `EntryParameterWithoutSource`; `UnreachableTransfer`; `ForbiddenSourceControl`; `UnsupportedTransfer`; `A08GenerationMismatch` | region/code consumers or terminal |
| B10 | C20 `canonicalize_contract` | `ContractEvidencePublished[P]`; `ContractRejected[R]` | `MalformedContract`; `NonMemorySubject`; `InvalidBoundExpression`; `ContradictoryContract`; `MissingContractSubject`; `UnsupportedContract`; `A09GenerationMismatch` | ownership/memory/effect fan-out or terminal |
| B11 | `StaticBindingUse`; `StaticTransfer`; `StaticCallRetention`; `StaticControlTransition`; `StaticHandleCrossing`; `StaticResolverGrant`; `StaticUniqueCopyEquality`; `StaticErasure` requests, `derive_static_ownership` | `StaticOwnershipPublished[P]`; `StaticOwnershipRejected[R]` | `IllegalCopy`; `IllegalDrop`; `DoubleDischarge`; `VarOwned`; `DurableLease`; `LeaseEscape`; `RetainingCall`; `ConflictingInvalidation`; `UseOutsideLifetime`; `InvalidResolver`; `MissingLeaseGrant`; `HandleTargetMismatch`; `UnsafeScalarHandleCast`; `InvalidRepresentationWidth`; `UntrustedCrossing`; `UniqueCopyEqualityViolation`; `PrematureErasure`; `A10StaticMismatch` | F07 fan-out or terminal |
| B12 | `StorageObjectUse`; `StorageLeaseOrigin`; `StorageInvalidation`; `StorageDischarge`; `StorageEscape` requests, `refine_storage_ownership` | `StorageOwnershipPublished[P]`; `StorageOwnershipRejected[R]` | `LeaseOriginConflict`; `UseAfterInvalidation`; `StorageDischargeViolation`; `StorageInvalidationConflict`; `StorageEscapeViolation`; `A10StorageMismatch` | backend safety or terminal |
| B13 | foldable C13–C16 `evaluate_constant` | `ConstantValuePublished[P]`; `ConstantEvaluationRejected[R]` | `NonConstantExpression`; `RecursiveConstant`; `UnavailableSemanticOperation`; `UnresolvedConstant`; `UnsupportedConstantHostValue`; `ConstantArithmeticRejected`; `A11GenerationMismatch` | checking/code or terminal |
| B14 | `NestedFunctionOccurrence`; `ClosureExpressionOccurrence`, `discover_captures` | `CaptureRelationPublished[P]`; `CaptureDiscoveryRejected[R]` | `UnresolvedCapture`; `IllegalCaptureEscape`; `UnsupportedCaptureShape`; `UnsupportedNestedCallable`; `A12GenerationMismatch` | A10/A15 or terminal |
| B15 | `ScalarLayoutRequest`; `PointerLayoutRequest`; `ArrayLayoutRequest`; `SliceLayoutRequest`; `ViewLayoutRequest`; `LeaseLayoutRequest`; `OwnedLayoutRequest`; `AccessLayoutRequest`; `HandleLayoutRequest`; `ClosureLayoutRequest`; `StructLayoutRequest`; `UniqueLayoutRequest`; `UnionLayoutRequest`; `ImportedCLayoutRequest`, `project_layout` | `LayoutPublished[P]`; `LayoutRejected[R]` | `IncompleteRecursiveLayout`; `UnrepresentableField`; `UnrepresentablePayload`; `InvalidAlignment`; `TargetWidthMismatch`; `UnsupportedStorageClass`; `LayoutOverflow`; `A13GenerationMismatch` | physical consumers or terminal |
| B16 | `InternalFunctionAbiRequest`; `ExportFunctionAbiRequest`; `ExternFunctionAbiRequest`; `SealedRegionAbiRequest`; `ClosureAbiRequest`; `ImportedFunctionPointerAbiRequest`, `project_callable_abi` | `CallableAbiPublished[P]`; `CallableAbiRejected[R]` | `UnrepresentableParameter`; `UnrepresentableResult`; `UnsupportedConvention`; `IncompatibleRedeclaration`; `SignatureCollision`; `MissingSymbolPolicy`; `InvalidVisibility`; `AbiTargetMismatch`; `A14GenerationMismatch` | closure/region/backend/host or terminal |
| B17 | `CapturedClosureRepresentationRequest.represent_closure` | `ClosureRepresented[P]`; `ClosureRepresentationRejected[R]` | `ImpossibleEnvironmentLayout`; `UnsupportedCaptureRepresentation`; `IllegalCaptureStorage`; `UnsupportedNestedRepresentation`; `ClosureTargetMismatch`; `ClosureAbiMismatch`; `A15GenerationMismatch` | post-expansion recheck or terminal |
| B18 | `NoCaptureRepresentationRequest.preserve_uncaptured_callable` | `CallableRepresentationUnchanged[D]`; `NoCaptureDecisionRejected[R]` | `A15NoCaptureMismatch` | direct A18 or terminal |
| B19 | `OpenRegionInvocation.expand_open_region` | `OpenRegionExpanded[P]`; `OpenRegionRejected[R]` | `MissingRegionDefinition`; `RegionArgumentMismatch`; `RegionWiringMismatch`; `MissingContinuation`; `ContinuationSignatureMismatch`; `CaptureAdmissionFailed`; `DuplicateGeneratedIdentity`; `UnsupportedRegionBody`; `RegionProtocolMismatch`; `A16GenerationMismatch` | authoritative recheck or terminal |
| B20 | `SealMaterializationRequest.materialize_seal` | `SealMaterialized[P]`; `SealMaterializationRejected[R]` | `MissingSeal`; `SealProtocolMismatch`; `SealArgumentMismatch`; `UnsupportedFrameValue`; `RecursiveSealMaterialization`; `DelegatedAbiRejected`; `A17MaterializationMismatch` | routing/recheck or terminal |
| B21 | `SealedCallRoutingRequest.route_sealed_call` | `SealedCallRouted[P]`; `SealedCallRoutingRejected[R]` | `SealedArgumentMismatch`; `SealedContinuationMismatch`; `MissingSealedContinuation`; `SealedDelegatedAbiRejected`; `A17RoutingMismatch` | authoritative recheck or terminal |

O33/O39/O40 methods in B11/B12/B04 are required contracts. Their current implementation status is
unproven or absent; this is recorded in regressions, not erased from the model.

---

## 4. A18–A24 operation/result/reason ledger

| ID | Receiver/request and method | Result constructors and entry policy | R reason constructors | cont |
|---|---|---|---|---|
| B22 | accepted S1 plus C03/C13–C18 and admitted C19 `construct_monomorphic_code` | `CodeConstructed[P]`; `CodeConstructionRejected[R]` | `UnsupportedCheckedConstruct`; `MissingRepresentation`; `IllegalInitializer`; `IllegalRelocation`; `UnboundLoweredValue`; `MalformedCodeBody`; `UnrepresentableCodeType`; `A18GenerationMismatch` | A19 or terminal |
| B23 | S2 plus C21–C25 `validate_code_structure` | `CodeAccepted[P]`; `CodeStructureRejected[R]` | `DuplicateCodeOccurrence`; `MissingCodeReference`; `CodeSignatureMismatch`; `UndefinedCodeValue`; `InvalidBlockTarget`; `InvalidTransferArguments`; `MalformedMemoryOperation`; `IllegalCodeInitializer`; `InvalidCodeRelocation`; `UnterminatedCodeBlock` | accepted leaf invokes A20; rejection terminal |
| B24 | `CodeAccepted.derive_control_topology` plus C24/C25 contributions | direct `ControlTopology[P]`; no result sum | none—impossibility is B23 defect | analysis sequencing |
| B25 | `LoopMeaningRequest.derive_loop_meaning` | `CountedRangeLoop[P entry]`; `CountedGridLoop[P entry]`; `CountedTiledLoop[P entry]`; `CountedWindowLoop[P entry]`; `CountedTraversalLoop[P entry]`; `UncountedLoop[C entry]`; `FlowMeaningRejected[R]` | C reason constructors: `NonCountedLoop`; `MissingLatch`; `MissingHeader`; `MissingCondition`; `AmbiguousInduction`; `UnsupportedRecurrence`; `ContradictoryDirection`; `InvalidDomain`; `UnprovableTrip`; R: `A21FlowMismatch` | F19 fan-out or terminal |
| B26 | `InductionRelationRequest.derive_induction_relations` | `InductionWithTrip[P entry]`; `InductionWithoutTrip[P entry]`; `InductionRelationUnavailable[C no-entry]`; `InductionRejected[R]` | C: `NonInductionValue`; `AmbiguousInductionRelation`; `UnsupportedInductionRecurrence`; `MissingEdgeWiring`; R: `A21InductionMismatch` | F20 fan-out or terminal |
| B27 | `CodeValueAlgebraRequest.derive_value_algebra` | `ConstantRangeEntry[P]`; `CopyCanonicalEntry[P]`; `AffineValueEntry[P]`; `NoWrapEntry[P]`; `FloatEvidenceEntry[P]`; `ValueProofEntry[P]`; `ValueAlgebraUnavailable[C no-entry]`; `ValueAlgebraRejected[R]` | C: `UnsupportedValueExpression`; `UnsafeArithmeticAnalysis`; `IncompatibleFloatMode`; `UnavailableValueProof`; R: `A22ValueMismatch` | F15 fan-out or terminal |
| B28 | `LoopValueSubject(loop,value,AccumulatorRole/ScanRole/RecurrenceRole/DerivedIndexRole)` in `LoopAlgebraRequest.derive_loop_algebra` | `ReductionEntry[P]`; `ScanEntry[P]`; `RecurrenceEntry[P]`; `ClosedFormEntry[P]`; `AssociativeOrderEntry[P]`; `AffineLoopEntry[P]`; `LoopAlgebraUnavailable[C no-entry]`; `LoopAlgebraRejected[R]` | C: `UnsupportedLoopRecurrence`; `NonAssociativeReduction`; `UnavailableLoopProof`; `UncountedLoopPremise`; R: `A22LoopMismatch` | F21 fan-out or terminal |
| B29 | `MemorySpineRequest.derive_memory_spine`; C22/C24 `memory_access_causes` | `MemorySpinePublished[P]`; `MemorySpineRejected[R]` | `UnresolvedStorageProvenance`; `MalformedAcceptedMemoryCode`; `A23SpineMismatch` | B30 |
| B30 | `MemoryObjectMeaningRequest.derive_object_meaning` | `ObjectMeaningKnown[P entry]`; `ObjectMeaningUnknown[C entry]`; `ObjectMeaningRejected[R]` | C: `UnknownExtent`; `UnknownStride`; `UnknownElementMeaning`; R: `A23ObjectMismatch` | B31 |
| B31 | `MemoryContractRealizationRequest.realize_contracts` | `MemoryContractRealized[P entry]`; `MemoryContractRejected[R]` | `UnmappableContractSubject`; `ContractProvenanceMismatch`; `A23ContractMismatch` | B32 |
| B32 | `MemoryAccessMeaningRequest.derive_access_meaning` | `AccessMeaningPublished[P]` carrying mandatory `BoundsStatus`, `TrapStatus`, `AlignmentStatus`, `MovementStatus`; status alternatives `BoundsProven[P]`/`BoundsUnproven[C]`/`BoundsUnknown[C]`, `NonTrapping[P]`/`MayTrap[C]`/`MustTrap[C]`, `Aligned[P]`/`Unaligned[C]`, `Movable[P]`/`Immovable[C]`/`Pinned[C]`; `AccessMeaningRejected[R]` | `RequiredBoundsUnproven`; `RequiredNontrapUnproven`; `AccessContractContradiction`; `A23AccessMismatch` | B33 |
| B33 | `MemoryRelationRequest.derive_relations` | `SameStore[P entry]`; `SubobjectOverlap[P entry]`; `Disjoint[P entry]`; `ExactNoalias[P entry]`; `ProvenAlias[P entry]`; `Dependence[P entry]`; `LoopCarriedDependence[P entry]`; `MayAlias[C entry]`; `IncomparableRelation[C entry]`; `UnknownDependence[C entry]`; `RelationUnavailable[C no-entry]`; `MemoryRelationRejected[R]` | `RequiredNoaliasContradicted`; `RequiredDisjointnessUnproven`; `A23RelationMismatch` | memory/effect/planning fan-out or terminal |
| B34 | `OperationEffectRequest.classify_operation_effect` on every C24/C25 op | `OperationEffectPublished[P]` carrying `PureOperationEffect` or `EffectfulOperationEffect` with an ordered nonempty sequence drawn from `ReadEffect`, `WriteEffect`, `PreserveEffect`, `InvalidateEffect`, `RetainNoescapeEffect`, `TrapEffect`, `VolatileEffect`, `AtomicEffect`, `CallEffect`, `AllocateEffect`, `ExternalEffect`, `UnknownCalleeEffect[C]`, `UnresolvedExternalEffect[C]`, `IncompleteOperationEffect[C]`; `OperationEffectRejected[R]` | `ContradictoryEffectDeclaration`; `A24OperationMismatch` | B35/planning or terminal |
| B35 | `AcyclicCallableEffectRequest.compose_callable_effects` | `CallableEffectPublished[P]`; `IncompleteCallableEffect[C entry]`; `CallableEffectRejected[R]` | `EffectDeclarationContradiction`; `A24CallableMismatch` | F17 fan-out or terminal |
| B36 | `RecursiveCallableComponentEffectRequest.compose_recursive_component_effects` | `RecursiveComponentEffectsPublished[P]`; `RecursiveConservativeEffects[C entry]`; `RecursiveEffectsRejected[R]` | `MalformedCallableComponent`; `RecursiveEffectDeclarationContradiction`; `A24RecursiveMismatch` | F17 fan-out or terminal |

F24/F25/F16/F17/F19 are dense and therefore publish conservative alternatives rather than omit entries.
F15/F20/F21 are sparse and use explicit C no-entry results; every constructed F27 request either publishes
or rejects. F26 records conservative relations when a pair is meaningful and `RelationUnavailable` when
no entry is justified. Mandatory F06 escalation is owned by B32/B33; effects own their own declaration
contradictions. Neither authority reinterprets authored contract syntax or another concern's decision.

The recursive callable component in B36 is a typed structural value derived from direct S2 call-target
relations. It is not a call-graph spine, world, side table, or durable identity. Mutual recursion is
handled by this request leaf, never by hidden mutable summary state.

---

## 5. A25–A33 operation/result/reason ledger

| ID | Receiver/request and method | Result constructors | R/U/H reason constructors | cont |
|---|---|---|---|---|
| B37 | `LoopKernelCandidateRequest.recognize_kernel` | `KernelAdmitted[P]`; `KernelNoPlan[U]`; `KernelRejected[R]` | U: `UnsupportedKernelControl`; `UnsafeKernelMemory`; `MissingKernelProof`; `UnsupportedKernelExpression`; `UnsupportedKernelEffect`; `InvalidKernelTrip`; `AmbiguousKernelLane`; `UnsupportedKernelResult`; R: `A25EvidenceMismatch` | admitted→A26; U→A29; R terminal |
| B38 | `ScheduleSelectionRequest.select_schedule` | `ScheduleSelected[P]`; `ScheduleNoPlan[U]`; `ScheduleRejected[R]` | U: `UnsupportedScheduleTarget`; `MissingEmitterCapability`; `IllegalVectorSchedule`; `IllegalTailSchedule`; `InsufficientScheduleProof`; `InvalidScheduledMovement`; `UnsupportedScheduledResult`; `SchedulePolicyRejected`; R: `A26EvidenceMismatch` | selected→A27; U→A29 |
| B39 | `FusedProjectionRequest.project_fused_computation` | `FusedComputationAdmitted[P]`; `FusedShapeUnavailable[U]`; `FusedProjectionRejected[R]` | U: `UnsupportedFusedDomain`; `UnsupportedFusedResult`; `UnsupportedFusedOperator`; `UnsupportedFusedWindow`; `UnsupportedFusedTail`; `IncompatibleFusedSchedule`; `UnsafeFusedAccess`; `MissingFusedBounds`; `MissingFusedNoalias`; `FusedShapeContradiction`; R: `A27EvidenceMismatch` | admitted→A29 fused attempt; U→A29 |
| B40 | `UsePopulationCandidateRequest.enumerate_use_candidate` | `UsePopulationCandidate[D]`; `UsePopulationUnrealizable[U]`; `UsePopulationRejected[R]` | U: `UnsupportedUseTopology`; `AmbiguousUseOrder`; `UnsupportedWindowUse`; R: `A28PopulationMismatch` | D→B41; U→A29 |
| B41 | `UseMeaningCandidateRequest.derive_use_meaning_candidate` | `UseMeaningCandidate[D]`; `UseMeaningRejected[R]` | `MissingUseProvenance`; `ContradictoryUseRole`; `A28MeaningMismatch` | D→B42 |
| B42 | `CoordinateCandidateRequest.derive_coordinate_candidate` | `CoordinateCandidate[D]`; `CoordinateUnrealizable[U]`; `CoordinateRejected[R]` | U: `CoordinateDisagreement`; `UnknownCoordinateStride`; `UnknownCoordinateExtent`; `InvalidCoordinateWindow`; `UnsafeCoordinateDereference`; `MissingCoordinateAlignment`; `UnsupportedCoordinateRank`; `CoordinateOverflow`; `PinnedCoordinateAccess`; `PotentiallyTrappingCoordinate`; R: `A28CoordinateMismatch` | D→B43; U→A29 |
| B43 | `UseSpineAdmissionRequest.admit_use_spine` | `UseSpineAdmitted[P]` publishing S7; `UseAdmissionRejected[R]` | `CandidateCardinalityMismatch`; `CandidateOrderMismatch`; `A28AdmissionMismatch` | B44 |
| B44 | `UseMeaningPublicationRequest.publish_use_meaning` | direct `UseMeaningPublished[P]` publishing dense F31 | none after candidate coherence | B45 |
| B45 | `CoordinatePublicationRequest.publish_coordinates` | direct `CoordinatesPublished[P]` publishing dense F32 | none after candidate coherence | qualification/address fan-out |
| B46 | `PointerQualificationRequest.qualify_pointer_uses` | `PointerQualified[P entry]`; `PointerUnqualified[C no-entry]`; `QualificationRequiredUnavailable[U]`; `PointerRepresentationUnrealizable[U]`; `PointerQualificationRejected[R]` | U: `MissingExactNoaliasProvenance`; `UnsupportedPointerRepresentation`; R: `ContradictoryQualificationEvidence`; `A28QualificationMismatch` | P/C→fragment; U→A29 |
| B47 | `AddressRecordRequest.realize_address_record` | `AddressRecordReady[D]`; `AddressRecordUnrealizable[U]`; `AddressRecordRejected[R]` | U: `UnsupportedAddressBasis`; `MissingAddressValue`; `AddressEnvironmentIncomplete`; `AddressOverflow`; R: `A28AddressMismatch` | D→A30; U→A29 |
| B48 | `BaselineAdmissionRequest.admit_baseline` | `BaselineAdmitted[P]`; `NoLegalBaseline[R]` | `UnsupportedBaselineOperation`; `IncompleteBaselineCoverage`; `MissingBaselineEmitterCapability`; `BaselineTargetMismatch` | P→subject selection; R terminal |
| B49 | `SubjectCommitmentRequest.select_subject_strategy` | `AttemptClosedForm[D]`; `AttemptFused[D]`; `CommitBaseline[P]`; `NoLegalStrategy[R]` | `NoCorrectSubjectRealization` | attempts→A30/A28; baseline publishes F22 |
| B50 | `ResumeAfterUseFailure`; `ResumeAfterCoordinateFailure`; `ResumeAfterQualificationFailure`; `ResumeAfterAddressFailure`; `ResumeAfterFragmentFailure`, `resume_subject` | `AttemptClosedForm[D]`; `AttemptFused[D]`; `CommitBaseline[P]`; `NoLegalStrategy[R]` | `NoCorrectFallbackRealization` | next attempt or F22 |
| B51 | `CommitRealizedFragmentRequest.commit_fragment` | `FragmentCommitted[P]` publishing F22; `FragmentCommitRejected[R]` | `FragmentCommitSubjectMismatch`; `A29CommitMismatch` | backend sequencing |
| B52 | `DominanceRequest.derive_dominance` | direct `DominancePublished[P]`; no result sum | none after accepted S2/S3 | fragment fan-out |
| B53 | `ClosedFormContributionRequest.realize_fragment_contribution`; `FusedContributionRequest.realize_fragment_contribution` | `FragmentContributionRealized[P]`; `FragmentUnrealizable[U]`; `FragmentRejected[R]` | U: `UnsupportedFragmentRealization`; `UnsupportedFragmentValue`; `UnsupportedClosedForm`; `InvalidFragmentCoverage`; `DominanceFailure`; `InvalidAdapter`; `InvalidFragmentExit`; `MissingFragmentCoordinate`; `MissingFragmentValue`; `MissingFragmentAccess`; `NamespaceConflict`; `HelperConflict`; `IncompleteContribution`; `ConflictingContribution`; R: `A30EvidenceMismatch` | realized→B51; U→B50 |
| B54 | `BackendConstructionRequest.construct_backend_unit` plus C21–C27 methods | `BackendUnitConstructed[P]`; `BackendConstructionRejected[R]` | `UnrepresentableBackendType`; `UnrepresentableBackendOperation`; `UnrepresentableBackendStorage`; `UnrepresentableInitializer`; `UnrepresentableAbi`; `MissingBackendSymbol`; `MissingBackendHelper`; `IllegalLinkage`; `InvalidAssemblyContribution`; `BackendTargetMismatch`; `A31GenerationMismatch` | A32 or terminal |
| B55 | `GnuCEmitter.declare_capability` | direct `GnuCEmitterCapability[P]` | none; unsupported target forms are represented as absent capability entries consumed by A26/A29 | schedule/baseline fan-out |
| B56 | `GnuCEmitter.validate_and_serialize_c` plus C26 `validate_c`/`emit_c` | `CArtifactAccepted[P]`; `CSerializationRejected[R]` | `InvalidBackendReference`; `CSignatureMismatch`; `IllegalCType`; `MalformedCControl`; `InvalidCMemoryAccess`; `UnsupportedCEntity`; `CEmitterCapabilityMismatch`; `CHelperConflict`; `CSerializationBoundaryRejected`; `A32TargetMismatch` | emit-only result or A33 |
| B57 | `GccCookRequest.cook_and_load` | `LiveGccSession[P]`; `GccCookFailed[H]` | H: `CompilerUnavailable`; `FileWriteFailure`; `ProcessSpawnFailure`; `CCompilationFailure`; `DynamicLoadFailure` | live session or Host API error |
| B58 | `LiveGccSession.resolve_symbol` | `SymbolCapability[P]`; `SymbolResolutionFailed[H]` | H: `MissingLoadedSymbol`; `IncompatibleFfiCast` | Host API result |
| B59 | `LiveGccSession.release` | `ReleasedGccSession[P]` | none | Host API result |
| B60 | `ReleasedGccSession.release` | `AlreadyReleased[P]` preserving released state | none | Host API result |
| B61 | `ReleasedGccSession.resolve_symbol` | `UseAfterReleaseFailed[H]` | H: `UseAfterRelease` | Host API error |

B49/B50 attempt constructors are D and never F22. Only `CommitBaseline` and B51 publish F22. B40–B42
candidate values are direct one-consumer boundary records; only B43 creates S7, followed by total B44/B45
facet publication. B53 creates fragment-local occurrences; only B54 creates final S8 identity. B55 runs
before B38/B48.

---

## 6. Continuation and publication closure

### 6.1 Immediate edge classes

| Source class | Required concrete-leaf behavior |
|---|---|
| P with one next stage | invoke the exact named request in the ledger |
| P with several consumers | return to the sequencing coordinator; §6.2 fixes fan-out and the coordinator performs no classification |
| C entry/no-entry | continue the exact analysis/planning sequence without strengthening |
| D | construct exactly the request named by that leaf; no persistent history except where later F22/F29 explicitly records typed reasons |
| U | construct the exact B50 resumption leaf carrying the failed attempt and typed reason |
| R | produce the final typed semantic rejection envelope; no outgoing semantic edge |
| H | produce the typed Host API failure; never enter a compiler result sum |

### 6.2 Publication fan-out

| Publication | Exact consumer operations |
|---|---|
| S1/F01–F13 | the consumer lists in facet §5, with derived S1 routed through authoritative A03–A10 rechecking before B22 |
| S2/O13/S3/F14 | B23; accepted B24; then B25–B36/B37/B48/B52/B54 according to their exact frontiers |
| S4/F24–F27/F34 | B12/B34–B39/B42/B46/B54 according to facet §8 frontiers |
| S5/F28/F29 | B38/B39/B49 according to facet §9 |
| S6/F30 | B40/B41/B49/B53 |
| S7/F31/F32/F33 | B44/B45/B46/B47/B49/B53/B54 according to the exact leaf frontier |
| F18/F22/F23 | B49/B50/B52/B53/B54; F22 only after commitment |
| emitter capability | B38/B48/B49/B56 |
| C artifact | emit-only Host API or B57, selected by the original public request leaf rather than semantic result inspection |

The post-expansion coordinator sequences initial checking → A15/A16/A17 expansion → authoritative
re-resolution/rechecking. The analysis coordinator sequences B25–B36 by frontier. Planning and realization
coordinators only route B37–B53 leaf continuations. None publishes a fact or chooses fallback.

---

## 7. Reason ownership and diagnostic law

Cross-listed obligation wording resolves as follows: declaration-key duplicates and missing references
belong to A03; duplicate fields/variants and invalid nominal membership belong to A04; operand semantics
belong to A06; use-site type/place/call failures belong to A07; control target/termination failures belong
to A08; contract syntax/subjects belong to A09; storage identity/alias/bounds belong to A23; observable
effects belong to A24; optional feasibility belongs to A25–A30; physical C legality belongs to A31/A32;
GCC/files/loader/FFI failures belong only to A33.

Propagation constructors are typed: A07 may carry A03/A04/A10 causes; A17 may carry A14 causes;
post-expansion rejection preserves ordered A03–A10 causes; A31/A32 cite upstream typed causes without
reclassifying them. Aggregation never flattens to count/string. Every reason constructor in §§3–5 owns
`render_reason`, subject, origin, and exact expected/actual provenance where applicable.

---

## 8. Single-owner publication proof

| Publications | Sole operation |
|---|---|
| exact-input/admission S1 | B01 |
| generated declaration values | B02; feed B01 admission and are not S1 |
| derived S1 allocations | B17 closure, B19 open expansion, B20 seal materialization, B21 sealed-call routing |
| F01/F02/F03/F04/F05/F06 | B03/B04/B05/B08/B09/B10 |
| F07/F34/F08/F09/F10/F11/F12/F14 | B11/B12/B13/B14/B15/B16/B17/B07 |
| F13 | B20 seal entries + B21 sealed-invocation routing entries; disjoint subpopulations under A17 |
| S2/O13/S3 | B22/B23/B24 |
| F19/F20/F15/F21 | B25/B26/B27/B28 |
| S4/F24/F27/F25/F26 | B29/B30/B31/B32/B33 |
| F16/F17 | B34/B35+B36; B35 and B36 partition acyclic callables vs recursive components |
| S5/F28/F29/S6/F30 | B37/B38/B39 |
| S7/F31/F32/F33 | B43/B44/B45/B46 |
| F18/F22/F23 | B48/B49+B51/B52; B49 and B51 partition baseline vs fragment commitments |
| use/meaning/coordinate/address candidate records | B40/B41/B42/B47; one consumer each |
| fragment entities/S8 | B53/B54 |
| emitter capability/C artifact | B55/B56 |
| live/released session and symbol capability | B57/B59/B58 |

No rejected kernel/fused/use candidate creates S5/S6/S7. No address record or fragment creates S8 IDs.
No result leaf copies another authority's publication.

---

## 9. O01–O40 reachability proof

| Obligations | Coverage operations |
|---|---|
| O01 | B01 document materialization and anchoring |
| O02 | B01 document/builder convergence law |
| O03 | B03 declaration identity and resolution |
| O04 | B04 nominal input + B05 type meaning |
| O05 | B05 `zero_meaning` + B08 checking |
| O06 | B14 target-independent captures |
| O07 | B09 control legality |
| O08 | B10 contract meaning |
| O09 | B19 open expansion |
| O10 | B20 seal materialization + B21 call routing |
| O11 | derived-S1 authoritative A03–A10 recheck edge |
| O12 | B22 code construction |
| O13 | B23 structural gate |
| O14 | B24 total topology |
| O15 | B25/B26 flow and induction |
| O16 | B27/B28 value and loop algebra |
| O17 | B29–B33 memory semantics |
| O18 | B34–B36 effects |
| O19 | B37 kernel recognition |
| O20 | B38 schedule selection consuming B55 emitter capability |
| O21 | B39 fused projection |
| O22 | B40–B47 use/coordinate/qualification/address semantics |
| O23 | B52 dominance + B53 fragment realization |
| O24 | B54 backend construction |
| O25 | B56 C validation/serialization |
| O26 | B57–B61 GCC/session boundary |
| O27 | every R/U/H reason's rendering and typed envelope; §7 |
| O28 | B15–B18/B38–B49/B54–B57 reference one target/capability generation |
| O29 | B13 plus StringLiteral decoded length; target bytes B54/B56 |
| O30 | B04 nominal meaning + B08 use-site checking |
| O31 | B16/B20/B54/B58 |
| O32 | B06/B07, consumed by B22/B34/B54 |
| O33 | B11/B12 plus B29–B36 |
| O34 | B48–B51 and every U continuation |
| O35 | every creator and deterministic order law; B01/B22/B24/B29/B37/B39/B43/B53/B54/B56/B57 |
| O36 | B02 staged synthesis |
| O37 | B15 target layout |
| O38 | B17/B18 closure representation consuming B14 |
| O39 | B04/B11/B15 |
| O40 | B04/B11/B29 |

O27/O28/O35 remain laws, not receiver families. O33/O39/O40 are fully modeled but not credited as
implemented until their regressions pass.

---

## 10. Required regression ledger

### 10.1 Behavioral gaps

| ID | Required harness and pass criterion |
|---|---|
| REG-B01 | forbidden `for`/`while`/`break`/`continue` reaches B09 `ForbiddenSourceControl` with origin |
| REG-B02 | captured closure executes through GCC, proving B14→B17→B16→B22→B54→B56→B57/B58 separation |
| REG-B03 | authored loop produces one B24 S3 loop without a hand-built fixture |
| REG-B04 | authored loop produces aligned B25/B26 induction/trip facts without fixture-only evidence |
| REG-B05 | public APIs preserve typed R envelopes; no count/string flattening |
| REG-B06 | O33 copy/transfer/lease/noescape/erasure and storage refinement methods produce the exact B11/B12 alternatives |
| REG-B07 | O39 resolver grant and trusted crossing accept/reject through B04/B11/B15 |
| REG-B08 | parsed unique declaration reaches B04 kind, B11 legality, and B29 storage identity |

### 10.2 Identity regressions

| ID | Required harness and pass criterion |
|---|---|
| REG-I01 | duplicate function/type/field/extern/region declarations reject at B03/B04 |
| REG-I02 | same-spelled declarations remain distinct typed diagnostic subjects |
| REG-I03 | nested same-name locals remain distinct through B22/B54/GCC |
| REG-I04 | document and builder inputs have equivalent semantics without equal internal IDs |
| REG-I05 | two builder compilations emit deterministic C despite process-global counters |
| REG-I06 | repeated/nested open invocations at equal offsets create unique B19 identities |
| REG-I07 | authored loop creates one S3 loop and aligned F19/F20 |
| REG-I08 | compound code operation yields distinct S4 access ordinals |
| REG-I09 | two provenance paths to one store produce correct `SameStore`/subobject relation |
| REG-I10 | function-address relocation uses A14's projected backend symbol consistently |
| REG-I11 | authored/generated origins survive checking, expansion, code, and typed public diagnostics |
| REG-I12 | stale generation references produce authority-specific R coherence leaves, never C/U |

### 10.3 Facet and continuation regressions

| ID | Required harness and pass criterion |
|---|---|
| REG-F01 | dense F04/F05 cover exact eligible S1 populations |
| REG-F02 | one F10 target generation is referenced consistently by all physical consumers |
| REG-F03 | F19 is the only trip producer; F28/F30/F32 retain typed references |
| REG-F04 | F16/F17 are the only observable-effect producers |
| REG-F05 | F24/F25 counts equal S4 object/access populations |
| REG-F06 | exact declared pairwise F26 noalias is the only evidence supporting F33 `restrict` |
| REG-F07 | F28 references, never copies, F14/F15/F19–F21/F24–F27/F16/F17 |
| REG-F08 | every admitted S7 use has exactly one F31/F32 entry; failed candidate has no S7 |
| REG-F09 | F23 derives once per S2/S3 generation and is reused |
| REG-F10 | every B40/B42/B46/B47/B53 U result reaches B50 before any F22 commitment |
| REG-F11 | address candidates/fragments never mint S8 local/label identity |
| REG-F12 | no emitted/backend name is parsed to recover alignment |
| REG-F13 | F07 works without S4; F34 alone owns storage-refined conclusions; no nullable pending state |
| REG-F14 | A24 recursive component yields deterministic conservative/exact F17 without side tables |
| REG-F15 | B55 capability publication precedes B38/B48 and scheduling cannot manufacture support |

Existing behavior tests are retained only where they prove these semantic criteria. Exact-field, class-name,
phase-wrapper, and retired-shape tests are replaced rather than treated as requirements.

---

## 11. Falsifiable closure invariants

1. **Leaf no-gap:** every subordinate case constructor in §2 belongs to exactly one C set and every A
   authority has at least one B operation.
2. **Leaf no-overlap:** no receiver/request constructor belongs to two decision authorities; subordinate
   methods may consume another authority's publication but cannot reproduce it.
3. **Method no-gap:** every constructor-operation pair listed in §2 has a required method contract.
4. **Result partition:** every result/fact alternative in §§3–5 has exactly one P/C/D/R/U/H code.
5. **Continuation closure:** every P/C/D/U result has one immediate result method; every R has none beyond
   typed transaction rejection; every H routes only to Host API.
6. **Reason disjointness:** each reason name has one authority and one structural meaning; propagation
   carries the original typed cause.
7. **Publication single owner:** §8 assigns every publication entry/subpopulation to exactly one producer
   operation; disjoint request leaves may partition one facet only under its one authority. This covers
   every S1–S8, F01–F34, gate, direct entity, boundary value, artifact, and resource.
8. **Frontier coincidence:** every request frontier equals the inputs named by its produced facet/entity
   and no unrelated fact invalidates it.
9. **Acyclicity:** declared source capabilities are not F04/F05/F07 results; A32 capability is intrinsic
   and precedes schedule/baseline; the facet graph is acyclic.
10. **Density:** every dense facet includes conservative alternatives; every sparse unavailable case has
    an explicit C no-entry result; admitted S7 receives total F31 then total F32 through B44/B45.
11. **No fake identity:** only accepted B37/B39/B43/B54 results create S5/S6/S7/S8 respectively.
12. **No premature commitment:** only B49 baseline commit and B51 fragment commit create F22.
13. **Coordinator zero semantics:** coordinators sequence exact result methods and never inspect classes,
    tags, booleans, reason strings, or evidence.
14. **Host isolation:** H appears only in B57/B58/B61; A01 delivery failure is R.
15. **Pending visibility:** B11/B12 O33/O39/O40 methods remain explicit required contracts until focused
    regressions prove implementation; no success shim is allowed.
16. **Generation discipline:** stale mixing is authority-specific R, never fallback, structural equality,
    interning, or encoded-name recovery.
17. **Evidence discipline:** F33 cannot infer noalias; kernel/fusion cannot rederive trip; scheduling cannot
    assert emitter support; serialization cannot change decisions.
18. **Anti-preservation:** every constructor is anchored to language/O/physical behavior, not admitted
    merely because a current schema product exists.

These invariants are mechanically transcribable: constructor IDs, method pairs, result classifications,
publication owners, obligation rows, and regression IDs are finite sets. ASDL transcription must generate
or hand-check the corresponding set equalities before compiler implementation is accepted.

---

## 12. Resolved Step-8 schema pressure

Step 8 resolves the audit's contested points as follows:

- A06 intrinsic operator leaves own interpretation; code attribution is a separate request.
- exact source leaves own A18 code-construction case methods; S1 only sequences them.
- `CodeAccepted` is the A19 result leaf carrying its exact S2 reference and is A20's receiver.
- F19 owns range/grid/tiled/window/traversal domain alternatives and sole trip evidence.
- F20 may reference counted or uncounted F19; `InductionWithoutTrip` is explicit.
- F15 copy canonicalization is a typed source→canonical value relation, never memory alias.
- F21 uses the named `LoopValueSubject` and role sum in B28.
- A23 dependency order is S4→F24→F27→F25→F26; the coordinator sequences only.
- F25 is a product of mandatory orthogonal status sums, not optional soup.
- mandatory bounds/noalias escalation belongs to B32/B33; A24 owns effect declaration contradictions.
- S2 operation leaves publish ordered memory-access causes; A23 alone creates S4 access identity.
- recursive callable composition uses B36's typed component request, not hidden mutable state.
- A28 uses one-consumer candidate records, S7 admission only after candidate success, and separate total
  F31/F32 publication, preserving frontier precision without publishing fake S7 identity.
- A32 has one `GnuCEmitter`; concrete S8 leaves own C cases.
- D explicitly names transient decisions and unchanged outcomes rather than laundering them as facts.

No unresolved semantic alternative remains hidden behind a category row. Field design and constructor
placement remain intentionally deferred to ASDL transcription.

---

## 13. Step 8 closure

Step 8 is closed because all A01–A33 receiver/request cases, subordinate semantic cases, operations,
result classes, reason constructors, continuations, publications, O01–O40 obligations, and required
regressions have finite closed ledgers; all audit-discovered authority/frontier/result gaps have a binding
resolution; and the no-gap/no-overlap claims are falsifiable.

This closure does **not** claim current implementation coverage. In particular O33/O39/O40 and the listed
behavioral/identity regressions remain mandatory cutover work. No ASDL declaration, implementation,
migration bridge, dual pipeline, compatibility shim, or cutover sequence is introduced here.

The next step is coherent ASDL transcription and a cutover plan derived from this complete model. It must
not preserve current fact bags or build a parallel pipeline.
