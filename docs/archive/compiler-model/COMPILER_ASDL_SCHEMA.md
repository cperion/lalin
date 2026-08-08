# Compiler ASDL Schema

Status: **Step-9R durable target schema — named-machine control, schema only**.

The durable data model is canonical. Immediate multi-exit behavior uses the named-exit
signatures in §14. No internal result junction, `k` wrapper, universal machine family,
control-state family, or runtime region framework is part of this schema.

This document is the exact normalized Lua-ASDL schema for the closed compiler model in:

- `docs/COMPILER_SEMANTIC_OBLIGATIONS.md`;
- `docs/COMPILER_ENTITY_IDENTITY_MODEL.md`;
- `docs/COMPILER_CONCERN_AUTHORITY_MODEL.md`;
- `docs/COMPILER_SPINE_MODEL.md`;
- `docs/COMPILER_FACET_MODEL.md`;
- `docs/COMPILER_WORLD_MODEL.md`;
- `docs/COMPILER_RECEIVER_OPERATION_RESULT_MODEL.md`;
- `docs/COMPILER_BEHAVIOR_COVERAGE_MODEL.md`;
- `docs/ASDL_GUIDE.md`.

It defines schema vocabulary and method contracts only. It does not define files,
implementation order, migration, compatibility, cutover, coordinator code, or a
replacement pipeline. Names below are canonical target names.

---

## 1. Transcription notation and hard laws

The declarations use a compact normalized ASDL notation that expands directly to the repository DSL:

```text
entity T { ... }       non-interned product; fresh constructor identity is semantic
coordinate T { ... }   non-interned product; identity is meaningful only with its containing spine/entity
record T { ... }       non-interned immutable product; object identity is not semantic
value T { ... }        interned product; equality is canonical structural equality
sum T = A { ... } | B  closed ASDL sum; concrete leaves own behavior
variant_unique sum T = ... all leaves are structurally interned; concrete leaves still own behavior
ref T                  typed reference to an existing ASDL value
many T                 deterministic immutable sequence of owned values
many ref T             deterministic immutable sequence of typed borrowed references
optional T             permitted only for a genuinely local structural absence
number/str/bool         ASDL primitive scalars
```

`entity`, `coordinate`, and `record` transcribe as `product`; only `entity` permits generation-scoped
semantic identity observation, while `coordinate` identity is meaningful only together with its containing
spine/entity. `value` transcribes as `product { interned, ... }`. A sum's identity mode follows the closed
roster below. Entity, coordinate, request, rejection, candidate, artifact, and resource leaves are
never structurally interned. Nullary leaves are real ASDL singleton values. `ref T` records a borrowed typed
relation. `many ref T` transcribes to the DSL's `many [T]`; the schema-level `ref` marks ownership and
provenance even though the current runtime erases it.

Only explicitly identity-bearing values permit object-identity comparison. Every `entity` product has
generation-scoped identity. The fresh leaves of `Declaration`, `TypeForm`, `Expression`, `Place`, `Pattern`,
`Statement`, `ControlTransfer`, and `ContractForm` are S1 child-occurrence entities. `CodeInstruction` and
`CodeTerminator` leaves are coordinate sums, so they are compared only with their S2 allocation. `ProgramInput`
and all request/reason leaves are fresh typed protocol values, but their object identity is not a
`BinaryOperation`, `ComparisonOperation`, `LogicOperation`, `SourceCastOperation`, `MachineCastOperation`,
`IntrinsicOperation`, `AtomicOperation`, `AtomicOrdering`, `ScalarOperation`, `OperationVolatility`,
`OverflowMeaning`, `TrapContract`, `FloatContract`, `ZeroMeaning`, `ConstantValue`, `CodeValue`,
`CodeConstant`, `CodePlace`, and `AffineExpression`. Every other parameterized sum leaf is non-interned;
its object identity is unobservable unless its parent is explicitly in the entity or coordinate roster above.

The following are forbidden throughout this schema: `any`, `table`, `map`, userdata fields, loose Lua
payloads, string tags, boolean protocols, semantic `nil`, generic contexts, mutable phase records, side
tables, handler maps, worlds, and copied facet bags. Every keyed relation is a named entry under `many`.
Every `many` sequence has authoritative order; it is never an unordered Lua-table projection.

A spine contains structure only. A facet contains one producer's semantic plane and
a typed reference to exactly one aligned spine allocation. A request contains one
operation frontier. Running machine objects and their named graph methods are Lua
control, not ASDL declarations. No machine receives semantic authority.

---

## 2. Namespace closure

The target has only durable semantic and boundary namespaces. This is namespace
ownership, not a file or migration plan.

| Namespace | Owns |
|---|---|
| `CompilerBase` | names, ordinals, documents, origins, target, policy, and capability values |
| `CompilerSource` | S1, C01–C20, A01–A17 source requests, sites, and reasons |
| `CompilerSourceFact` | F01–F13 and F34's S1 endpoint vocabulary |
| `CompilerCode` | S2/S3, C21–C25, A18–A20 requests, sites, and reasons |
| `CompilerAnalysis` | F14–F27, S4, A06-code/A10-storage/A21–A24 requests, sites, reasons, and F22 rejection history |
| `CompilerLower` | S5–S7, F28–F33, A25–A30 requests, sites, reasons, candidates, addresses, and fragments |
| `CompilerBackend` | S8, C26–C28, A31–A32 requests, sites, reasons, and C artifact |
| `CompilerHost` | C29 host requests, resources, capabilities, failures, and sealed host results |
| `CompilerBoundary` | `SemanticRejectReason` and `TypedSemanticRejection` only |

Declarations in §§3–11 inherit their section namespace, subject to the exact request exceptions in §11.
The §13 ownership ledger assigns every site and reason declaration. §12 assigns sealed host and final
boundary values. No declaration belongs to `CompilerResult` or `CompilerControl`; those namespaces do not
exist in the target.
Direct DSL transcription qualifies every unqualified field type through the section
and ownership ledger before schema definition; it never relies on runtime relative-name
resolution. A field may name a concrete sum leaf because the runtime registers leaf
classes as checked field types. This is used for exact durable relations, never for
an internal operation-result junction.
Cross-namespace references are typed object references. There is no umbrella `CompilerModule`, analysis
bundle, backend world, or phase header.

---

## 3. CompilerBase — structural values and provenance

```text
value NameKey { text:str }
value QualifiedNameKey { parts:many NameKey }
value NamespaceKey { parent:NamespaceParent, name:NameKey }
sum NamespaceParent = RootNamespace | ChildNamespace { parent:ref NamespaceKey }
sum NamespaceCategory = ValueNamespace | TypeNamespace | CallableNamespace | RegionNamespace
value SymbolKey { spelling:str }
value PathValue { text:str }
value ByteOffset { value:number }
value ByteLength { value:number }
value SourceSpan { start:ByteOffset, length:ByteLength }
entity SourceDocument { path:PathValue, bytes:str }
value Ordinal { value:number }
value BitWidth { value:number }
value ByteSize { value:number }
value ByteAlignment { value:number }
value SignedOffset { value:number }
value UnsignedExtent { value:number }
value VariantDiscriminant { value:number }
value RecursionLimit { value:number }
```

Origins are closed causal alternatives. Generated origins never recover identity from names or offsets.

```text
sum Origin =
  DocumentOrigin { document:ref SourceDocument, span:SourceSpan }
| BuilderOrigin { source:ref CompilerSource.BuilderSourceIdentity, ordinal:Ordinal }
| SynthesisOrigin { query:ref CompilerSource.MetaPropertyQuery, parent:ref Origin, ordinal:Ordinal }
| ClosureGeneratedOrigin { predecessor:ref CompilerSource.SemanticProgramSpine, closure:ref CompilerSource.ClosureExpression, ordinal:Ordinal }
| OpenRegionGeneratedOrigin { predecessor:ref CompilerSource.SemanticProgramSpine, invocation:ref CompilerSource.OpenEmitStatement, ordinal:Ordinal }
| SealGeneratedOrigin { predecessor:ref CompilerSource.SemanticProgramSpine, seal:ref CompilerSource.RegionDeclaration, ordinal:Ordinal }
| SealedCallGeneratedOrigin { predecessor:ref CompilerSource.SemanticProgramSpine, invocation:ref CompilerSource.SealedCallStatement, ordinal:Ordinal }
| CodeGeneratedOrigin { source:ref CompilerSource.SemanticOccurrence, ordinal:Ordinal }
| MemoryGeneratedOrigin { source:ref CompilerCode.CodeOccurrence, ordinal:Ordinal }
| KernelGeneratedOrigin { source:ref CompilerCode.NaturalLoopOccurrence, ordinal:Ordinal }
| FusedGeneratedOrigin { source:ref CompilerLower.KernelOccurrence, ordinal:Ordinal }
| UseGeneratedOrigin { source:ref CompilerLower.FusedAccessOccurrence, ordinal:Ordinal }
| FragmentGeneratedOrigin { source:ref CompilerLower.FragmentSubject, ordinal:Ordinal }
| BackendGeneratedOrigin { source:CompilerBackend.BackendProvenance, ordinal:Ordinal }
```

Target and policy are immutable request values, never worlds or copied facet fields.

```text
sum Endianness = LittleEndian | BigEndian
sum TargetPointerWidth = Pointer32 | Pointer64
sum TargetIndexWidth = Index32 | Index64
sum CCallingConvention = CDefaultConvention
sum CIntegerModel = Ilp32Model | Lp64Model | Llp64Model
value TargetSpec { triple:str, pointer_width:TargetPointerWidth, index_width:TargetIndexWidth, endian:Endianness, integer_model:CIntegerModel }
sum LayoutPolicy = TargetNaturalLayoutPolicy
sum OptimizationPolicy = PreferBaseline | PermitClosedForm | PermitFusion | PermitClosedFormAndFusion
sum VectorPolicy = ScalarOnly | PermitVector
sum TailPolicy = ExactTailOnly | PermitMaskedTail | PermitScalarRemainder
value CompilerPolicy { optimization:OptimizationPolicy, vector:VectorPolicy, tail:TailPolicy }
sum EmitterFeature = BaselineControlFeature | AggregateFeature | ClosureFeature | VariantFeature | AtomicFeature | VectorFeature | MaskedTailFeature | FusedRegionFeature
value GnuCEmitterCapability { target:ref TargetSpec, features:many EmitterFeature }
```

The typed rejection envelope preserves causes instead of flattening them.

```text
sum ProvenanceExpectation = S1Expectation { expected:ref CompilerSource.SemanticProgramSpine, actual:ref CompilerSource.SemanticProgramSpine } | S2Expectation { expected:ref CompilerCode.MonomorphicCodeSpine, actual:ref CompilerCode.MonomorphicCodeSpine } | S3Expectation { expected:ref CompilerCode.ControlTopologySpine, actual:ref CompilerCode.ControlTopologySpine } | S4Expectation { expected:ref CompilerAnalysis.MemorySpine, actual:ref CompilerAnalysis.MemorySpine } | S5Expectation { expected:ref CompilerLower.KernelSpine, actual:ref CompilerLower.KernelSpine } | S6Expectation { expected:ref CompilerLower.FusedComputationSpine, actual:ref CompilerLower.FusedComputationSpine } | S7Expectation { expected:ref CompilerLower.MaterializedUseSpine, actual:ref CompilerLower.MaterializedUseSpine } | S8Expectation { expected:ref CompilerBackend.PhysicalBackendSpine, actual:ref CompilerBackend.PhysicalBackendSpine } | TargetExpectation { expected:ref TargetSpec, actual:ref TargetSpec }
```

---

## 4. CompilerSource — S1 and C01–C20

### 4.1 Program inputs and S1 allocation

```text
entity BuilderSourceIdentity { origin_key:CompilerBase.PathValue }
record GeneratedDeclaration { declaration:Declaration, origin:CompilerBase.Origin }
sum ProgramInput = DocumentProgramInput { document:ref CompilerBase.SourceDocument } | BuilderProgramInput { source:ref BuilderSourceIdentity, declarations:many Declaration } | GeneratedDeclarationAdmissionInput { predecessor:ref SemanticProgramSpine, generated:many GeneratedDeclaration }

sum ProgramDerivation =
  InitialDocumentProgram { input:ref DocumentProgramInput }
| InitialBuilderProgram { input:ref BuilderProgramInput }
| GeneratedAdmissionProgram { input:ref GeneratedDeclarationAdmissionInput }
| ClosureDerivedProgram { predecessor:ref SemanticProgramSpine, closure:ref ClosureExpression }
| OpenRegionDerivedProgram { predecessor:ref SemanticProgramSpine, invocation:ref OpenEmitStatement }
| SealDerivedProgram { predecessor:ref SemanticProgramSpine, seal:ref RegionDeclaration }
| SealedCallDerivedProgram { predecessor:ref SemanticProgramSpine, invocation:ref SealedCallStatement }

entity SemanticProgramSpine { derivation:ProgramDerivation, declarations:many Declaration, order:many SemanticOrderEntry }
record SemanticOrderEntry { ordinal:CompilerBase.Ordinal, occurrence:SemanticOccurrence }
```

S1 child identity is the non-interned declaration/member/binding/expression/place/statement/control object
itself. Names are addressability keys only.

```text
sum SemanticOccurrence =
  DeclarationOccurrence { declaration:ref Declaration }
| NominalChildOccurrence { child:NominalChild }
| ParameterOccurrence { parameter:ref ParameterDeclaration }
| BindingOccurrenceRef { binding:ref BindingOccurrence }
| NameUseOccurrence { use:ref NameUse }
| TypeNameUseOccurrence { use:ref TypeNameUse }
| ExpressionOccurrence { expression:ref Expression }
| PlaceOccurrence { place:ref Place }
| StatementOccurrence { statement:ref Statement }
| PatternOccurrence { pattern:ref Pattern }
| ControlOccurrence { control:ControlSite }
| ContractOccurrence { contract:ref ContractForm }
| RegionInvocationOccurrence { invocation:RegionInvocation }
| TransferOccurrence { transfer:ref ControlTransfer }
```

### 4.2 Staged meta queries C02

Every query is a distinct request leaf. Query output is a generated declaration sequence, never S1 identity.

```text
sum MetaPropertyQuery =
  TypeNameQuery { program:ref SemanticProgramSpine, subject:ref TypeForm, requested:CompilerBase.NameKey, origin:CompilerBase.Origin, limit:CompilerBase.RecursionLimit }
| EntriesQuery { program:ref SemanticProgramSpine, subject:ref TypeForm, origin:CompilerBase.Origin, limit:CompilerBase.RecursionLimit }
| DeclarationsQuery { program:ref SemanticProgramSpine, subject:ref TypeForm, origin:CompilerBase.Origin, limit:CompilerBase.RecursionLimit }
| MethodQuery { program:ref SemanticProgramSpine, subject:ref TypeForm, method:CompilerBase.NameKey, origin:CompilerBase.Origin, limit:CompilerBase.RecursionLimit }
| MissingMethodQuery { program:ref SemanticProgramSpine, subject:ref TypeForm, method:CompilerBase.NameKey, origin:CompilerBase.Origin, limit:CompilerBase.RecursionLimit }
| MissingEntryQuery { program:ref SemanticProgramSpine, subject:ref TypeForm, entry:CompilerBase.NameKey, origin:CompilerBase.Origin, limit:CompilerBase.RecursionLimit }
| ApplyQuery { program:ref SemanticProgramSpine, subject:ref TypeForm, arguments:many MetaArgument, origin:CompilerBase.Origin, limit:CompilerBase.RecursionLimit }
| CastQuery { program:ref SemanticProgramSpine, subject:ref TypeForm, target:ref TypeForm, origin:CompilerBase.Origin, limit:CompilerBase.RecursionLimit }
sum MetaArgument = MetaTypeArgument { type_form:ref TypeForm } | MetaDeclarationArgument { declaration:ref Declaration } | MetaScalarArgument { value:HostLiteralValue }
```

### 4.3 Declarations C03 and nominal children C04

```text
sum Visibility = LocalVisibility | ExportVisibility
sum DeclaredLinkage = InternalDeclaredLinkage | ExportDeclaredLinkage | ExternalDeclaredLinkage
record DeclarationHeader { name:CompilerBase.NameKey, visibility:Visibility, origin:CompilerBase.Origin }
entity BindingOccurrence { name:CompilerBase.NameKey, origin:CompilerBase.Origin }
entity ParameterDeclaration { binding:ref BindingOccurrence, type_form:ref TypeForm, origin:CompilerBase.Origin }
sum Initializer = MissingInitializer | PresentInitializer { expression:ref Expression }
sum VariantPayload = EmptyVariantPayload | TypedVariantPayload { type_form:ref TypeForm }

sum Declaration =
  FunctionDeclaration { header:DeclarationHeader, parameters:many ParameterDeclaration, result:ref TypeForm, scalar_contracts:many DeclaredScalarContract, body:ref FunctionControlBody }
| ExternDeclaration { header:DeclarationHeader, symbol:CompilerBase.SymbolKey, parameters:many ParameterDeclaration, result:ref TypeForm, scalar_contracts:many DeclaredScalarContract, effects:DeclaredCallableEffect }
| StructDeclaration { header:DeclarationHeader, fields:many FieldMember }
| UniqueStructDeclaration { header:DeclarationHeader, fields:many FieldMember }
| UnionDeclaration { header:DeclarationHeader, variants:many VariantMember, constructors:many ConstructorMeaning, patterns:many PatternMeaning }
| HandleDeclaration { header:DeclarationHeader, domain:ref TypeForm, target:ref TypeForm }
| RegionDeclaration { header:DeclarationHeader, parameters:many ParameterDeclaration, protocol:RegionProtocol, body:ref RegionControlBody }
| ConstantDeclaration { header:DeclarationHeader, type_form:ref TypeForm, value:ref Expression }
| StaticDeclaration { header:DeclarationHeader, type_form:ref TypeForm, initializer:Initializer }

entity FieldMember { name:CompilerBase.NameKey, type_form:ref TypeForm, origin:CompilerBase.Origin }
entity VariantMember { name:CompilerBase.NameKey, payload:VariantPayload, origin:CompilerBase.Origin }
entity ConstructorMeaning { variant:ref VariantMember, origin:CompilerBase.Origin }
entity PatternMeaning { variant:ref VariantMember, origin:CompilerBase.Origin }
sum NominalChild = FieldChild { field:ref FieldMember } | VariantChild { variant:ref VariantMember } | ConstructorChild { constructor:ref ConstructorMeaning } | PatternChild { pattern:ref PatternMeaning }
sum NominalDeclaration = StructNominal { declaration:ref StructDeclaration } | UniqueNominal { declaration:ref UniqueStructDeclaration } | UnionNominal { declaration:ref UnionDeclaration } | HandleNominal { declaration:ref HandleDeclaration }
```

### 4.4 Type constructors C05

`TypeForm` is authored/semantic syntax. `CanonicalType` is A05's interned structural value. A nominal name
use remains an S1 occurrence until F01 resolves it.

```text
entity TypeNameUse { name:CompilerBase.QualifiedNameKey, origin:CompilerBase.Origin }
sum TypeForm =
  VoidType { origin:CompilerBase.Origin }
| BoolType { origin:CompilerBase.Origin }
| SignedIntegerType { bits:CompilerBase.BitWidth, origin:CompilerBase.Origin }
| UnsignedIntegerType { bits:CompilerBase.BitWidth, origin:CompilerBase.Origin }
| FloatType { bits:CompilerBase.BitWidth, origin:CompilerBase.Origin }
| IndexType { origin:CompilerBase.Origin }
| PointerType { pointee:ref TypeForm, origin:CompilerBase.Origin }
| ArrayType { element:ref TypeForm, extent:ref Expression, origin:CompilerBase.Origin }
| SliceType { element:ref TypeForm, origin:CompilerBase.Origin }
| ViewType { element:ref TypeForm, rank:CompilerBase.UnsignedExtent, origin:CompilerBase.Origin }
| LeaseType { value_type:ref TypeForm, origin:CompilerBase.Origin }
| OwnedType { value_type:ref TypeForm, origin:CompilerBase.Origin }
| ReadonlyType { value_type:ref TypeForm, origin:CompilerBase.Origin }
| WriteonlyType { value_type:ref TypeForm, origin:CompilerBase.Origin }
| NoaliasType { value_type:ref TypeForm, origin:CompilerBase.Origin }
| NoescapeType { value_type:ref TypeForm, origin:CompilerBase.Origin }
| InvalidateType { value_type:ref TypeForm, origin:CompilerBase.Origin }
| PreserveType { value_type:ref TypeForm, origin:CompilerBase.Origin }
| HandleType { name_use:ref TypeNameUse, origin:CompilerBase.Origin }
| FunctionType { parameters:many TypeForm, result:ref TypeForm, origin:CompilerBase.Origin }
| ClosureType { parameters:many TypeForm, result:ref TypeForm, origin:CompilerBase.Origin }
| NominalType { name_use:ref TypeNameUse, origin:CompilerBase.Origin }
| ImportedCType { spelling:str, origin:CompilerBase.Origin }
| ImportedCFunctionPointerType { spelling:str, parameters:many TypeForm, result:ref TypeForm, origin:CompilerBase.Origin }

sum AccessQualifier = ReadonlyQualifier | WriteonlyQualifier | NoaliasQualifier | NoescapeQualifier | InvalidateQualifier | PreserveQualifier
variant_unique sum CanonicalType =
  CanonicalVoid | CanonicalBool
| CanonicalSignedInteger { bits:CompilerBase.BitWidth }
| CanonicalUnsignedInteger { bits:CompilerBase.BitWidth }
| CanonicalFloat { bits:CompilerBase.BitWidth }
| CanonicalIndex
| CanonicalPointer { pointee:ref CanonicalType }
| CanonicalArray { element:ref CanonicalType, extent:CompilerBase.UnsignedExtent }
| CanonicalSlice { element:ref CanonicalType }
| CanonicalView { element:ref CanonicalType, rank:CompilerBase.UnsignedExtent }
| CanonicalLease { value_type:ref CanonicalType }
| CanonicalOwned { value_type:ref CanonicalType }
| CanonicalQualified { qualifier:AccessQualifier, value_type:ref CanonicalType }
| CanonicalHandle { declaration:ref HandleDeclaration }
| CanonicalFunction { parameters:many CanonicalType, result:ref CanonicalType }
| CanonicalClosure { parameters:many CanonicalType, result:ref CanonicalType }
| CanonicalNominal { declaration:NominalDeclaration }
| CanonicalImportedC { spelling:str }
| CanonicalImportedFunctionPointer { spelling:str, parameters:many CanonicalType, result:ref CanonicalType }
variant_unique sum ZeroMeaning = ZeroScalar { type_value:ref CanonicalType } | ZeroNull { type_value:ref CanonicalType } | ZeroAggregate { type_value:ref CanonicalType, fields:many ZeroMeaning } | ZeroArray { type_value:ref CanonicalType, elements:many ZeroMeaning }
```

All `CanonicalType` parameterized leaves are interned structural variants. They do not provide declaration,
binding, or occurrence identity.

### 4.5 Intrinsic operation constructors C06–C12

```text
variant_unique sum UnaryOperation = NegateOp | LogicalNotOp | BitwiseNotOp
variant_unique sum BinaryOperation = AddOp | SubtractOp | MultiplyOp | DivideOp | RemainderOp | BitAndOp | BitOrOp | BitXorOp | ShiftLeftOp | LogicalShiftRightOp | ArithmeticShiftRightOp
variant_unique sum ComparisonOperation = EqualOp | NotEqualOp | LessOp | LessEqualOp | GreaterOp | GreaterEqualOp
variant_unique sum LogicOperation = LogicalAndOp | LogicalOrOp
variant_unique sum SourceCastOperation = ConvertCast | TruncateCast | ZeroExtendCast | SignExtendCast | Bitcast | SaturatingCast
variant_unique sum MachineCastOperation = IdentityMachineCast | MachineBitcast | IntegerReduce | SignedExtend | UnsignedExtend | FloatPromote | FloatDemote | SignedToFloat | UnsignedToFloat | FloatToSigned | FloatToUnsigned
variant_unique sum IntrinsicOperation = PopcountIntrinsic | CountLeadingZerosIntrinsic | CountTrailingZerosIntrinsic | RotateLeftIntrinsic | RotateRightIntrinsic | ByteSwapIntrinsic | FmaIntrinsic | SqrtIntrinsic | AbsIntrinsic | FloorIntrinsic | CeilIntrinsic | TruncateFloatIntrinsic | RoundIntrinsic | TrapIntrinsic | AssumeIntrinsic
variant_unique sum AtomicOperation = AtomicLoadOp | AtomicStoreOp | AtomicAddOp | AtomicSubtractOp | AtomicAndOp | AtomicOrOp | AtomicXorOp | AtomicExchangeOp | AtomicCompareExchangeOp | AtomicFenceOp
variant_unique sum AtomicOrdering = SequentiallyConsistentOrdering
variant_unique sum ScalarOperation = UnaryScalarOp { op:UnaryOperation } | BinaryScalarOp { op:BinaryOperation } | ComparisonScalarOp { op:ComparisonOperation } | LogicScalarOp { op:LogicOperation } | SourceCastScalarOp { op:SourceCastOperation } | MachineCastScalarOp { op:MachineCastOperation } | IntrinsicScalarOp { op:IntrinsicOperation } | AtomicScalarOp { op:AtomicOperation, ordering:AtomicOrdering }
variant_unique sum OperationVolatility = NonvolatileOperation | VolatileOperation
variant_unique sum OverflowMeaning = ExactOverflow | WrapOverflow | UndefinedOverflow | SaturatingOverflow
variant_unique sum TrapContract = OperationNontrapping | OperationMayTrap | OperationMustTrap
variant_unique sum FloatContract = ExactFloat | IeeeFloat | FastFloat
sum DeclaredScalarContract = DeclaredOverflowContract { meaning:OverflowMeaning } | DeclaredFloatContract { meaning:FloatContract } | DeclaredTrapContract { meaning:TrapContract } | DeclaredVolatilityContract { meaning:OperationVolatility } | DeclaredAtomicOrderingContract { ordering:AtomicOrdering } | DeclaredPointerOperationContract
```

### 4.6 Expressions, places, statements C13–C18

```text
sum HostLiteralValue = HostInteger { raw:str } | HostFloat { raw:str } | HostBoolean { value:bool } | HostString { bytes:str } | HostNull
sum Expression =
  IntegerLiteral { raw:str, origin:CompilerBase.Origin }
| FloatLiteral { raw:str, origin:CompilerBase.Origin }
| BooleanLiteral { value:bool, origin:CompilerBase.Origin }
| StringLiteral { bytes:str, decoded_length:CompilerBase.ByteLength, origin:CompilerBase.Origin }
| NilLiteral { origin:CompilerBase.Origin }
| HostLiteral { value:HostLiteralValue, origin:CompilerBase.Origin }
| BindingReference { use:ref NameUse }
| UnaryExpression { op:UnaryOperation, operand:ref Expression, origin:CompilerBase.Origin }
| BinaryExpression { op:BinaryOperation, left:ref Expression, right:ref Expression, origin:CompilerBase.Origin }
| CompareExpression { op:ComparisonOperation, left:ref Expression, right:ref Expression, origin:CompilerBase.Origin }
| LogicExpression { op:LogicOperation, left:ref Expression, right:ref Expression, origin:CompilerBase.Origin }
| CastExpression { op:SourceCastOperation, target:ref TypeForm, value:ref Expression, origin:CompilerBase.Origin }
| MachineCastExpression { op:MachineCastOperation, target:ref TypeForm, value:ref Expression, origin:CompilerBase.Origin }
| IntrinsicExpression { op:IntrinsicOperation, arguments:many Expression, origin:CompilerBase.Origin }
| AddressOfExpression { place:ref Place, origin:CompilerBase.Origin }
| DereferenceExpression { pointer:ref Expression, origin:CompilerBase.Origin }
| CallExpression { callee:ref Expression, arguments:many Expression, origin:CompilerBase.Origin }
| LengthExpression { value:ref Expression, origin:CompilerBase.Origin }
| FieldExpression { base:ref Expression, field:ref NameUse, origin:CompilerBase.Origin }
| IndexExpression { base:ref Expression, index:ref Expression, origin:CompilerBase.Origin }
| LoadExpression { place:ref Place, origin:CompilerBase.Origin }
| AtomicLoadExpression { place:ref Place, ordering:AtomicOrdering, origin:CompilerBase.Origin }
| AtomicRmwExpression { op:AtomicOperation, place:ref Place, value:ref Expression, ordering:AtomicOrdering, origin:CompilerBase.Origin }
| AtomicCompareExchangeExpression { place:ref Place, expected:ref Expression, replacement:ref Expression, ordering:AtomicOrdering, origin:CompilerBase.Origin }
| AggregateExpression { fields:many AggregateFieldExpression, origin:CompilerBase.Origin }
| ArrayExpression { elements:many Expression, origin:CompilerBase.Origin }
| IfExpression { condition:ref Expression, then_value:ref Expression, else_value:ref Expression, origin:CompilerBase.Origin }
| SelectExpression { condition:ref Expression, true_value:ref Expression, false_value:ref Expression, origin:CompilerBase.Origin }
| SwitchExpression { selector:ref Expression, arms:many SwitchExpressionArm, default_arm:ref Expression, origin:CompilerBase.Origin }
| ControlExpression { invocation:RegionInvocation, origin:CompilerBase.Origin }
| DomainControlExpression { invocation:DomainRegionInvocation, origin:CompilerBase.Origin }
| BlockExpression { statements:many Statement, result:ref Expression, origin:CompilerBase.Origin }
| ClosureExpression { parameters:many ParameterDeclaration, result:ref TypeForm, body:ref FunctionControlBody, origin:CompilerBase.Origin }
| ViewExpression { data:ref Expression, length:ref Expression, stride:ref Expression, origin:CompilerBase.Origin }
| ConstructorExpression { constructor:ref NameUse, arguments:many Expression, origin:CompilerBase.Origin }
| NullExpression { target:ref TypeForm, origin:CompilerBase.Origin }
| SizeOfExpression { target:ref TypeForm, origin:CompilerBase.Origin }
| AlignOfExpression { target:ref TypeForm, origin:CompilerBase.Origin }
| IsNullExpression { value:ref Expression, origin:CompilerBase.Origin }

entity NameUse { name:CompilerBase.QualifiedNameKey, origin:CompilerBase.Origin }
record AggregateFieldExpression { field:ref NameUse, value:ref Expression }
record SwitchExpressionArm { match_value:ref Expression, result:ref Expression }

sum Place = ReferencePlace { use:ref NameUse } | DereferencePlace { pointer:ref Expression, origin:CompilerBase.Origin } | FieldPlace { base:ref Place, field:ref NameUse, origin:CompilerBase.Origin } | IndexPlace { base:ref Place, index:ref Expression, origin:CompilerBase.Origin }

sum Pattern = BindingPattern { binding:ref BindingOccurrence } | VariantPattern { constructor:ref NameUse, fields:many Pattern, origin:CompilerBase.Origin } | WildcardPattern { origin:CompilerBase.Origin }

sum Statement =
  LetStatement { binding:ref BindingOccurrence, type_form:ref TypeForm, initializer:Initializer, origin:CompilerBase.Origin }
| VarStatement { binding:ref BindingOccurrence, type_form:ref TypeForm, initializer:Initializer, origin:CompilerBase.Origin }
| AssignmentStatement { place:ref Place, value:ref Expression, origin:CompilerBase.Origin }
| AtomicStoreStatement { place:ref Place, value:ref Expression, ordering:AtomicOrdering, origin:CompilerBase.Origin }
| AtomicFenceStatement { ordering:AtomicOrdering, origin:CompilerBase.Origin }
| ExpressionStatement { expression:ref Expression, origin:CompilerBase.Origin }
| AssertStatement { condition:ref Expression, origin:CompilerBase.Origin }
| IfStatement { condition:ref Expression, then_body:many Statement, else_body:many Statement, origin:CompilerBase.Origin }
| SwitchStatement { selector:ref Expression, arms:many SwitchStatementArm, default_body:many Statement, origin:CompilerBase.Origin }
| VariantSwitchStatement { selector:ref Expression, arms:many VariantSwitchArm, default_body:many Statement, origin:CompilerBase.Origin }
| FoldStatement { accumulator:ref BindingOccurrence, type_form:ref TypeForm, initial:ref Expression, reducer:ref NameUse, step:ref Expression, origin:CompilerBase.Origin }
| ScanStatement { accumulator:ref BindingOccurrence, type_form:ref TypeForm, initial:ref Expression, reducer:ref NameUse, axis:ref BindingOccurrence, step:ref Expression, destination:ref Place, origin:CompilerBase.Origin }
| RequiresStatement { contracts:many ContractForm, origin:CompilerBase.Origin }
| JumpStatement { target:ref NameUse, arguments:many Expression, origin:CompilerBase.Origin }
| ConditionalJumpStatement { condition:ref Expression, true_target:ref NameUse, true_arguments:many Expression, false_target:ref NameUse, false_arguments:many Expression, origin:CompilerBase.Origin }
| ContinuationJumpStatement { target:ref NameUse, arguments:many Expression, origin:CompilerBase.Origin }
| OpenEmitStatement { invocation:RegionInvocation, origin:CompilerBase.Origin }
| SealedCallStatement { invocation:RegionInvocation, origin:CompilerBase.Origin }
| YieldVoidStatement { origin:CompilerBase.Origin }
| YieldValueStatement { value:ref Expression, origin:CompilerBase.Origin }
| ReturnVoidStatement { origin:CompilerBase.Origin }
| ReturnValueStatement { value:ref Expression, origin:CompilerBase.Origin }
| ControlStatement { invocation:RegionInvocation, origin:CompilerBase.Origin }
| DomainControlStatement { invocation:DomainRegionInvocation, origin:CompilerBase.Origin }
| TrapStatement { origin:CompilerBase.Origin }

record SwitchStatementArm { match_value:ref Expression, body:many Statement }
record VariantSwitchArm { pattern:ref Pattern, body:many Statement }
record ContinuationBinding { formal:ref NameUse, actual:ref NameUse }
```

### 4.7 Control C19

```text
sum RegionProtocol = OpenRegionProtocol { continuations:many ContinuationProtocol } | SealedRegionProtocol { continuations:many ContinuationProtocol, result:ref TypeForm }
record ContinuationProtocol { name:CompilerBase.NameKey, parameters:many ParameterDeclaration, origin:CompilerBase.Origin }
record RegionInvocation { region:ref NameUse, arguments:many Expression, continuations:many ContinuationBinding }
record DomainRegionInvocation { region:ref NameUse, domain:ref Expression, arguments:many Expression, continuations:many ContinuationBinding }

entity FunctionControlBody { entry:ref EntryControlBlock, blocks:many OrdinaryControlBlock, origin:CompilerBase.Origin }
entity RegionControlBody { entry:ref EntryControlBlock, blocks:many OrdinaryControlBlock, origin:CompilerBase.Origin }
entity EntryControlBlock { name:CompilerBase.NameKey, parameters:many ParameterDeclaration, statements:many Statement, transfer:ControlTransfer, origin:CompilerBase.Origin }
entity OrdinaryControlBlock { name:CompilerBase.NameKey, parameters:many ParameterDeclaration, statements:many Statement, transfer:ControlTransfer, origin:CompilerBase.Origin }
sum ControlBlockRef = EntryBlockRef { block:ref EntryControlBlock } | OrdinaryBlockRef { block:ref OrdinaryControlBlock }
sum ControlSite = FunctionBodySite { body:ref FunctionControlBody } | RegionBodySite { body:ref RegionControlBody } | EntryBlockSite { block:ref EntryControlBlock } | OrdinaryBlockSite { block:ref OrdinaryControlBlock } | IfControlSite { statement:ref IfStatement } | SwitchControlSite { statement:ref SwitchStatement } | VariantSwitchControlSite { statement:ref VariantSwitchStatement } | RangeLoopSite { control:ref DomainControlStatement } | GridLoopSite { control:ref DomainControlStatement } | TiledLoopSite { control:ref DomainControlStatement } | WindowLoopSite { control:ref DomainControlStatement } | EntryParameterFlow { parameter:ref ParameterDeclaration } | ForbiddenFor { origin:CompilerBase.Origin } | ForbiddenWhile { origin:CompilerBase.Origin } | ForbiddenBreak { origin:CompilerBase.Origin } | ForbiddenContinue { origin:CompilerBase.Origin }
sum ControlTransfer = JumpTransfer { statement:ref JumpStatement } | ConditionalTransfer { statement:ref ConditionalJumpStatement } | ContinuationTransfer { statement:ref ContinuationJumpStatement } | ReturnTransfer { source:ReturnTransferSource } | YieldTransfer { source:YieldTransferSource } | OpenEmitTransfer { statement:ref OpenEmitStatement } | SealedCallTransfer { statement:ref SealedCallStatement }
sum ReturnTransferSource = ReturnVoidTransferSource { statement:ref ReturnVoidStatement } | ReturnValueTransferSource { statement:ref ReturnValueStatement }
sum YieldTransferSource = YieldVoidTransferSource { statement:ref YieldVoidStatement } | YieldValueTransferSource { statement:ref YieldValueStatement }
sum EntryParameterSource = ExplicitArgumentSource { argument:ref Expression } | ContinuationPayloadSource { continuation:ref ContinuationProtocol, ordinal:CompilerBase.Ordinal } | SameNameBlockParameterSource { parameter:ref ParameterDeclaration }
```

### 4.8 Contracts C20

```text
sum ContractForm = BoundsContract { subject:ref Place, lower:ref Expression, upper:ref Expression, origin:CompilerBase.Origin } | WindowBoundsContract { subject:ref Place, lower:ref Expression, upper:ref Expression, origin:CompilerBase.Origin } | DisjointContract { left:ref Place, right:ref Place, origin:CompilerBase.Origin } | SameLengthContract { left:ref Place, right:ref Place, origin:CompilerBase.Origin } | SoAComponentContract { aggregate:ref Place, component:ref Place, origin:CompilerBase.Origin } | PairNoaliasContract { left:ref Place, right:ref Place, origin:CompilerBase.Origin } | UnaryNoaliasContract { subject:ref Place, origin:CompilerBase.Origin } | ReadonlyContract { subject:ref Place, origin:CompilerBase.Origin } | WriteonlyContract { subject:ref Place, origin:CompilerBase.Origin } | InvalidateContract { subject:ref Place, origin:CompilerBase.Origin } | PreserveContract { subject:ref Place, origin:CompilerBase.Origin } | NoescapeContract { subject:ref Expression, origin:CompilerBase.Origin }
sum DeclaredCallableEffect = DeclaredPureCallable | DeclaredExternalCallable | DeclaredCallableEffects { effects:many DeclaredEffectAtom }
sum DeclaredEffectAtom = DeclaredRead | DeclaredWrite | DeclaredPreserve | DeclaredInvalidate | DeclaredNoescape | DeclaredRetain | DeclaredTrap | DeclaredVolatile | DeclaredAtomic | DeclaredAllocate
```

---

## 5. CompilerSourceFact — F01–F13

F01 is one whole-program relation publication. F02–F13 are direct immutable entry-family publications:
every entry carries its exact S1 alignment, and no aggregate facet bag or lookup map exists.

Across the complete schema, an aggregate facet product exists only when one total operation creates the
whole eligible population: F01 resolution, F18 baseline, F23 dominance, F28 admitted-kernel meaning, F30
fused meaning, F31 materialized-use meaning, and F32 coordinates. Every other F02–F34 family publishes
independently aligned entries. This makes per-subject requests constructible without granting a coordinator
facet-publication authority.

```text
record ResolutionFacet { spine:ref CompilerSource.SemanticProgramSpine, occupancies:many NamespaceOccupancyEntry, references:many ResolvedReferenceEntry, shadowing:many ShadowingEntry }
record NamespaceOccupancyEntry { namespace:CompilerBase.NamespaceKey, category:CompilerBase.NamespaceCategory, key:CompilerBase.NameKey, declaration:ref CompilerSource.Declaration }
sum ResolvedReferenceEntry = ResolvedNameReference { use:ref CompilerSource.NameUse, target:ResolutionTarget } | ResolvedTypeReference { use:ref CompilerSource.TypeNameUse, target:TypeResolutionTarget }
sum ResolutionTarget = DeclarationTarget { declaration:ref CompilerSource.Declaration } | BindingTarget { binding:ref CompilerSource.BindingOccurrence } | FieldTarget { field:ref CompilerSource.FieldMember } | VariantTarget { variant:ref CompilerSource.VariantMember } | ContinuationTarget { continuation:ref CompilerSource.ContinuationProtocol }
sum TypeResolutionTarget = NominalTypeTarget { declaration:CompilerSource.NominalDeclaration } | ImportedCTypeTarget { type_form:ref CompilerSource.ImportedCType } | ImportedFunctionPointerTypeTarget { type_form:ref CompilerSource.ImportedCFunctionPointerType }
record ShadowingEntry { inner:ref CompilerSource.BindingOccurrence, outer:ResolutionTarget }

sum NominalDeclarationMeaningEntry = StructMeaning { spine:ref CompilerSource.SemanticProgramSpine, declaration:ref CompilerSource.StructDeclaration } | UniqueMeaning { spine:ref CompilerSource.SemanticProgramSpine, declaration:ref CompilerSource.UniqueStructDeclaration } | UnionMeaning { spine:ref CompilerSource.SemanticProgramSpine, declaration:ref CompilerSource.UnionDeclaration } | HandleMeaning { spine:ref CompilerSource.SemanticProgramSpine, declaration:ref CompilerSource.HandleDeclaration, domain_form:ref CompilerSource.TypeForm, domain_resolution:ref ResolvedTypeReference, target_form:ref CompilerSource.TypeForm, target_resolution:ref ResolvedTypeReference }
sum NominalChildMeaningEntry = FieldMembership { spine:ref CompilerSource.SemanticProgramSpine, declaration:CompilerSource.NominalDeclaration, field:ref CompilerSource.FieldMember, ordinal:CompilerBase.Ordinal } | VariantMembership { spine:ref CompilerSource.SemanticProgramSpine, declaration:ref CompilerSource.UnionDeclaration, variant:ref CompilerSource.VariantMember, discriminant:CompilerBase.VariantDiscriminant } | ConstructorMembership { spine:ref CompilerSource.SemanticProgramSpine, declaration:ref CompilerSource.UnionDeclaration, constructor:ref CompilerSource.ConstructorMeaning, variant:ref CompilerSource.VariantMember } | PatternMembership { spine:ref CompilerSource.SemanticProgramSpine, declaration:ref CompilerSource.UnionDeclaration, pattern:ref CompilerSource.PatternMeaning, variant:ref CompilerSource.VariantMember }

record TypeMeaningEntry { spine:ref CompilerSource.SemanticProgramSpine, subject:TypeMeaningSubject, canonical:ref CompilerSource.CanonicalType }
sum TypeMeaningSubject = TypeFormMeaningSubject { type_form:ref CompilerSource.TypeForm } | ParameterTypeMeaningSubject { parameter:ref CompilerSource.ParameterDeclaration } | FieldTypeMeaningSubject { field:ref CompilerSource.FieldMember } | DeclarationTypeMeaningSubject { declaration:ref CompilerSource.Declaration }

sum CheckedMeaningEntry = CheckedExpression { spine:ref CompilerSource.SemanticProgramSpine, expression:ref CompilerSource.Expression, type_value:ref CompilerSource.CanonicalType, category:ExpressionCategory } | CheckedPlace { spine:ref CompilerSource.SemanticProgramSpine, place:ref CompilerSource.Place, type_value:ref CompilerSource.CanonicalType, access:PlaceAccessMeaning } | CheckedStatement { spine:ref CompilerSource.SemanticProgramSpine, statement:ref CompilerSource.Statement } | CheckedBinding { spine:ref CompilerSource.SemanticProgramSpine, binding:ref CompilerSource.BindingOccurrence, type_value:ref CompilerSource.CanonicalType, initializer:CheckedInitializerMeaning }
sum CheckedInitializerMeaning = ExplicitCheckedInitializer { expression:ref CompilerSource.Expression } | OmittedInitializerZero { zero:CompilerSource.ZeroMeaning }
sum ExpressionCategory = ValueExpression | CallableExpression | TypeExpression | NullExpressionMeaning
sum PlaceAccessMeaning = ReadablePlace | WritablePlace | ReadWritePlace

sum ControlMeaningEntry = TerminatedControl { spine:ref CompilerSource.SemanticProgramSpine, site:CompilerSource.ControlSite } | TransferMeaning { spine:ref CompilerSource.SemanticProgramSpine, transfer:ref CompilerSource.ControlTransfer, target:CompilerSource.ControlBlockRef, arguments:many TransferArgumentEntry } | SwitchMeaning { spine:ref CompilerSource.SemanticProgramSpine, site:CompilerSource.ControlSite, default_block:CompilerSource.ControlBlockRef } | EntryParameterMeaning { spine:ref CompilerSource.SemanticProgramSpine, parameter:ref CompilerSource.ParameterDeclaration, source:CompilerSource.EntryParameterSource } | ContinuationProtocolMeaning { spine:ref CompilerSource.SemanticProgramSpine, continuation:ref CompilerSource.ContinuationProtocol, parameters:many ref CompilerSource.ParameterDeclaration }
record TransferArgumentEntry { argument:ref CompilerSource.Expression, parameter:ref CompilerSource.ParameterDeclaration, ordinal:CompilerBase.Ordinal }

sum ContractEvidenceEntry = CanonicalBounds { spine:ref CompilerSource.SemanticProgramSpine, contract:ref CompilerSource.BoundsContract, subject:ref CompilerSource.Place, lower:ref CompilerSource.Expression, upper:ref CompilerSource.Expression } | CanonicalWindowBounds { spine:ref CompilerSource.SemanticProgramSpine, contract:ref CompilerSource.WindowBoundsContract, subject:ref CompilerSource.Place, lower:ref CompilerSource.Expression, upper:ref CompilerSource.Expression } | CanonicalDisjoint { spine:ref CompilerSource.SemanticProgramSpine, contract:ref CompilerSource.DisjointContract, left:ref CompilerSource.Place, right:ref CompilerSource.Place } | CanonicalSameLength { spine:ref CompilerSource.SemanticProgramSpine, contract:ref CompilerSource.SameLengthContract, left:ref CompilerSource.Place, right:ref CompilerSource.Place } | CanonicalSoAComponent { spine:ref CompilerSource.SemanticProgramSpine, contract:ref CompilerSource.SoAComponentContract, aggregate:ref CompilerSource.Place, component:ref CompilerSource.Place } | CanonicalPairNoalias { spine:ref CompilerSource.SemanticProgramSpine, contract:ref CompilerSource.PairNoaliasContract, left:ref CompilerSource.Place, right:ref CompilerSource.Place } | CanonicalUnaryNoalias { spine:ref CompilerSource.SemanticProgramSpine, contract:ref CompilerSource.UnaryNoaliasContract, subject:ref CompilerSource.Place } | CanonicalReadonly { spine:ref CompilerSource.SemanticProgramSpine, contract:ref CompilerSource.ReadonlyContract, subject:ref CompilerSource.Place } | CanonicalWriteonly { spine:ref CompilerSource.SemanticProgramSpine, contract:ref CompilerSource.WriteonlyContract, subject:ref CompilerSource.Place } | CanonicalInvalidate { spine:ref CompilerSource.SemanticProgramSpine, contract:ref CompilerSource.InvalidateContract, subject:ref CompilerSource.Place } | CanonicalPreserve { spine:ref CompilerSource.SemanticProgramSpine, contract:ref CompilerSource.PreserveContract, subject:ref CompilerSource.Place } | CanonicalNoescape { spine:ref CompilerSource.SemanticProgramSpine, contract:ref CompilerSource.NoescapeContract, subject:ref CompilerSource.Expression }

sum StaticOwnershipEntry = CopyAuthorized { spine:ref CompilerSource.SemanticProgramSpine, subject:CompilerSource.SemanticOccurrence } | TransferAuthorized { spine:ref CompilerSource.SemanticProgramSpine, subject:CompilerSource.SemanticOccurrence } | DropAuthorized { spine:ref CompilerSource.SemanticProgramSpine, subject:CompilerSource.SemanticOccurrence } | DischargeAuthorized { spine:ref CompilerSource.SemanticProgramSpine, subject:CompilerSource.SemanticOccurrence } | LeaseAuthorized { spine:ref CompilerSource.SemanticProgramSpine, subject:CompilerSource.SemanticOccurrence } | NoescapeAuthorized { spine:ref CompilerSource.SemanticProgramSpine, subject:CompilerSource.SemanticOccurrence } | InvalidationAuthorized { spine:ref CompilerSource.SemanticProgramSpine, subject:CompilerSource.SemanticOccurrence } | PreserveAuthorized { spine:ref CompilerSource.SemanticProgramSpine, subject:CompilerSource.SemanticOccurrence } | ResolverGrant { spine:ref CompilerSource.SemanticProgramSpine, subject:CompilerSource.SemanticOccurrence, handle:ref CompilerSource.HandleDeclaration, domain:ref CompilerSource.TypeForm } | TrustedCrossing { spine:ref CompilerSource.SemanticProgramSpine, subject:CompilerSource.SemanticOccurrence, handle:ref CompilerSource.HandleDeclaration, domain:ref CompilerSource.TypeForm } | UniqueEqualityAuthorized { spine:ref CompilerSource.SemanticProgramSpine, subject:CompilerSource.SemanticOccurrence } | PhysicalErasureAuthorized { spine:ref CompilerSource.SemanticProgramSpine, subject:CompilerSource.SemanticOccurrence }

record ConstantValueEntry { spine:ref CompilerSource.SemanticProgramSpine, subject:ConstantSubject, value:ConstantValue }
sum ConstantSubject = ConstantDeclarationSubject { declaration:ref CompilerSource.ConstantDeclaration } | ConstantExpressionSubject { expression:ref CompilerSource.Expression }
variant_unique sum ConstantValue = ConstantInteger { raw:str, type_value:ref CompilerSource.CanonicalType } | ConstantFloat { raw:str, type_value:ref CompilerSource.CanonicalType } | ConstantBoolean { value:bool } | ConstantString { bytes:str, decoded_length:CompilerBase.ByteLength } | ConstantNull { type_value:ref CompilerSource.CanonicalType } | ConstantAggregate { fields:many ConstantValue } | ConstantArray { elements:many ConstantValue }

record CaptureEntry { spine:ref CompilerSource.SemanticProgramSpine, callable:CaptureOwner, binding:ref CompilerSource.BindingOccurrence, role:CaptureRole }
sum CaptureOwner = NestedFunctionCaptureOwner { declaration:ref CompilerSource.FunctionDeclaration } | ClosureCaptureOwner { closure:ref CompilerSource.ClosureExpression }
sum CaptureRole = ReadCapture | WriteCapture | AddressCapture | MoveCapture

record LayoutEntry { spine:ref CompilerSource.SemanticProgramSpine, target:ref CompilerBase.TargetSpec, policy:CompilerBase.LayoutPolicy, subject:LayoutSubject, layout:LayoutMeaning }
sum LayoutSubject = TypeLayoutSubject { type_value:ref CompilerSource.CanonicalType } | NominalLayoutSubject { declaration:CompilerSource.NominalDeclaration }
sum LayoutMeaning = ScalarLayout { size:CompilerBase.ByteSize, alignment:CompilerBase.ByteAlignment } | PointerLayout { size:CompilerBase.ByteSize, alignment:CompilerBase.ByteAlignment } | ArrayLayout { size:CompilerBase.ByteSize, alignment:CompilerBase.ByteAlignment, stride:CompilerBase.ByteSize, extent:CompilerBase.UnsignedExtent } | AggregateLayout { size:CompilerBase.ByteSize, alignment:CompilerBase.ByteAlignment, fields:many FieldLayoutEntry } | UnionLayout { size:CompilerBase.ByteSize, alignment:CompilerBase.ByteAlignment, discriminant:VariantTagLayout, variants:many VariantLayoutEntry } | HandleLayout { size:CompilerBase.ByteSize, alignment:CompilerBase.ByteAlignment } | ImportedCLayout { size:CompilerBase.ByteSize, alignment:CompilerBase.ByteAlignment }
record FieldLayoutEntry { field:ref CompilerSource.FieldMember, offset:CompilerBase.UnsignedExtent, layout:ref LayoutMeaning }
record VariantLayoutEntry { variant:ref CompilerSource.VariantMember, payload_offset:CompilerBase.UnsignedExtent, payload_layout:VariantPayloadLayout }
sum VariantPayloadLayout = EmptyPayloadLayout | PresentPayloadLayout { layout:ref LayoutMeaning }
record VariantTagLayout { offset:CompilerBase.UnsignedExtent, size:CompilerBase.ByteSize, alignment:CompilerBase.ByteAlignment }

record CallableAbiEntry { spine:ref CompilerSource.SemanticProgramSpine, target:ref CompilerBase.TargetSpec, callable:CallableSubject, convention:CompilerBase.CCallingConvention, parameters:many AbiParameterEntry, result:AbiResult, linkage:LinkageMeaning, symbol:CompilerBase.SymbolKey }
sum CallableSubject = FunctionCallable { declaration:ref CompilerSource.FunctionDeclaration } | ExternCallable { declaration:ref CompilerSource.ExternDeclaration } | ClosureCallable { closure:ref CompilerSource.ClosureExpression } | SealedRegionCallable { declaration:ref CompilerSource.RegionDeclaration } | ImportedPointerCallable { type_form:ref CompilerSource.ImportedCFunctionPointerType }
record AbiParameterEntry { parameter:AbiParameterSubject, passing:AbiPassing }
sum AbiParameterSubject = DeclaredParameter { parameter:ref CompilerSource.ParameterDeclaration } | ClosureEnvironmentParameter { closure:ref CompilerSource.ClosureExpression } | SealedFrameParameter { seal:ref CompilerSource.RegionDeclaration }
sum AbiPassing = DirectAbiValue { type_value:ref CompilerSource.CanonicalType } | IndirectAbiValue { type_value:ref CompilerSource.CanonicalType, alignment:CompilerBase.ByteAlignment }
sum AbiResult = VoidAbiResult | DirectAbiResult { type_value:ref CompilerSource.CanonicalType } | IndirectAbiResult { type_value:ref CompilerSource.CanonicalType, alignment:CompilerBase.ByteAlignment }
sum LinkageMeaning = InternalLinkage | ExportedLinkage | ExternalLinkage

record ClosureRepresentationEntry { spine:ref CompilerSource.SemanticProgramSpine, closure:ref CompilerSource.ClosureExpression, environment:ref CompilerSource.StructDeclaration, fields:many ClosureEnvironmentField, callable:ref CompilerSource.FunctionDeclaration }
record ClosureEnvironmentField { capture:ref CaptureEntry, field:ref CompilerSource.FieldMember, ordinal:CompilerBase.Ordinal }

sum SealedRegionEntry = SealMaterializationMeaning { spine:ref CompilerSource.SemanticProgramSpine, seal:ref CompilerSource.RegionDeclaration, callable:ref CompilerSource.FunctionDeclaration, frame:ref CompilerSource.StructDeclaration, results:many SealedResultAlternative } | SealedInvocationMeaning { spine:ref CompilerSource.SemanticProgramSpine, invocation:ref CompilerSource.SealedCallStatement, seal:ref CompilerSource.RegionDeclaration, frame_arguments:many SealedFrameArgument, routes:many CallerContinuationRoute }
record SealedResultAlternative { continuation:ref CompilerSource.ContinuationProtocol, ordinal:CompilerBase.Ordinal }
record SealedFrameArgument { formal:ref CompilerSource.ParameterDeclaration, actual:ref CompilerSource.Expression, ordinal:CompilerBase.Ordinal }
record CallerContinuationRoute { callee:ref CompilerSource.ContinuationProtocol, caller:ref CompilerSource.ContinuationBinding }
```

F34 is declared with S4 in §7.4 because its primary alignment is S4.

---

## 6. CompilerCode — S2, S3, C21–C25

### 6.1 S2 values and occurrence identity

```text
value CodeType { semantic:ref CompilerSource.CanonicalType }
value CodeSignature { parameters:many CodeType, result:ref CodeType }
entity CodeFunctionIdentity { origin:CompilerBase.Origin }
entity CodeExternIdentity { origin:CompilerBase.Origin }
entity CodeGlobalIdentity { origin:CompilerBase.Origin }
entity CodeDataIdentity { origin:CompilerBase.Origin }
entity CodeBlockIdentity { origin:CompilerBase.Origin }
record CodeIdentityProjection { functions:many CodeFunctionIdentityEntry, externs:many CodeExternIdentityEntry, globals:many CodeGlobalIdentityEntry, data:many CodeDataIdentityEntry, blocks:many CodeBlockIdentityEntry }
record CodeFunctionIdentityEntry { identity:ref CodeFunctionIdentity, source:ref CompilerSource.FunctionDeclaration }
record CodeExternIdentityEntry { identity:ref CodeExternIdentity, source:ref CompilerSource.ExternDeclaration }
record CodeGlobalIdentityEntry { identity:ref CodeGlobalIdentity, source:ref CompilerSource.StaticDeclaration }
record CodeDataIdentityEntry { identity:ref CodeDataIdentity, source:CodeDataSource }
record CodeBlockIdentityEntry { identity:ref CodeBlockIdentity, source:CompilerSource.ControlBlockRef }
record CodeFunction { identity:ref CodeFunctionIdentity, source:ref CompilerSource.FunctionDeclaration, signature:ref CodeSignature, parameters:many CodeParameter, locals:many CodeLocal, blocks:many CodeBlock }
record CodeExtern { identity:ref CodeExternIdentity, source:ref CompilerSource.ExternDeclaration, signature:ref CodeSignature }
record CodeGlobal { identity:ref CodeGlobalIdentity, source:ref CompilerSource.StaticDeclaration, type_value:ref CodeType, initializer:CodeInitializer }
record CodeData { identity:ref CodeDataIdentity, source:CodeDataSource, bytes:str, alignment:CompilerBase.ByteAlignment }
sum CodeDataSource = StringLiteralDataSource { literal:ref CompilerSource.StringLiteral } | ConstantDeclarationDataSource { declaration:ref CompilerSource.ConstantDeclaration } | StaticDeclarationDataSource { declaration:ref CompilerSource.StaticDeclaration } | GeneratedDataSource { origin:CompilerBase.Origin }
coordinate CodeRelocation { source:CodeRelocationSource, target:CodeRelocationTarget, offset:CompilerBase.UnsignedExtent, origin:CompilerBase.Origin }
coordinate CodeParameter { source:ref CompilerSource.ParameterDeclaration, type_value:ref CodeType, ordinal:CompilerBase.Ordinal, origin:CompilerBase.Origin }
coordinate CodeLocal { source:CodeLocalSource, type_value:ref CodeType, ordinal:CompilerBase.Ordinal, origin:CompilerBase.Origin }
sum CodeLocalSource = SourceBindingLocal { binding:ref CompilerSource.BindingOccurrence } | GeneratedCodeLocal { cause:CompilerBase.Origin }
record CodeBlock { identity:ref CodeBlockIdentity, source:CompilerSource.ControlBlockRef, parameters:many CodeParameter, instructions:many CodeInstruction, terminator:ref CodeTerminator }
variant_unique sum CodeValue = ParameterCodeValue { parameter:ref CodeParameter } | LocalCodeValue { local:ref CodeLocal } | ConstantCodeValue { constant:CodeConstant }
sum CodeInitializer = ZeroCodeInitializer | ConstantCodeInitializer { value:CodeConstant } | RelocatableCodeInitializer { relocations:many ref CodeRelocation }
sum CodeRelocationSource = GlobalRelocationSource { global:ref CodeGlobalIdentity } | DataRelocationSource { data:ref CodeDataIdentity }
sum CodeRelocationTarget = FunctionRelocationTarget { function:ref CodeFunctionIdentity } | ExternRelocationTarget { extern:ref CodeExternIdentity } | GlobalRelocationTarget { global:ref CodeGlobalIdentity } | DataRelocationTarget { data:ref CodeDataIdentity }
variant_unique sum CodeConstant = LiteralCodeConstant { value:CompilerSourceFact.ConstantValue } | NullCodeConstant { type_value:ref CodeType } | UndefinedCodeConstant { type_value:ref CodeType }

entity MonomorphicCodeSpine { source:ref CompilerSource.SemanticProgramSpine, types:many CodeType, signatures:many CodeSignature, functions:many CodeFunction, externs:many CodeExtern, globals:many CodeGlobal, data:many CodeData, relocations:many CodeRelocation, order:many CodeOrderEntry }
record CodeOrderEntry { ordinal:CompilerBase.Ordinal, occurrence:CodeOccurrence }
sum CodeOccurrence = CodeTypeOccurrence { type_value:ref CodeType } | CodeSignatureOccurrence { signature:ref CodeSignature } | CodeFunctionOccurrence { function:ref CodeFunction } | CodeExternOccurrence { extern:ref CodeExtern } | CodeGlobalOccurrence { global:ref CodeGlobal } | CodeDataOccurrence { data:ref CodeData } | CodeRelocationOccurrence { relocation:ref CodeRelocation } | CodeParameterOccurrence { parameter:ref CodeParameter } | CodeLocalOccurrence { local:ref CodeLocal } | CodeBlockOccurrence { block:ref CodeBlock } | CodeInstructionOccurrence { instruction:ref CodeInstruction } | CodeTerminatorOccurrence { terminator:ref CodeTerminator }
sum CodeConstructionContribution = ConstructedCodeOccurrence { occurrence:CodeOccurrence } | ConstructedCodeValue { value:CodeValue } | ConstructedCodePlace { place:CodePlace } | ConstructedCodeConstant { constant:CodeConstant } | ConstructedCodeInitializer { initializer:CodeInitializer } | ConstructedCodeInstruction { instruction:ref CodeInstruction } | ConstructedCodeTerminator { terminator:ref CodeTerminator }
sum CodeValidationSubject = StoredCodeValidationSubject { occurrence:CodeOccurrence } | CodeValueValidationSubject { value:CodeValue } | CodePlaceValidationSubject { place:CodePlace } | CodeConstantValidationSubject { constant:CodeConstant } | CodeInitializerValidationSubject { initializer:CodeInitializer } | CodeInstructionValidationSubject { instruction:ref CodeInstruction } | CodeTerminatorValidationSubject { terminator:ref CodeTerminator }
```

`CodeIdentityProjection` is an operation-local readonly boundary record with one B22 consumer. Its typed
handles make recursion, global/data relocations, and cyclic block targets constructible before immutable S2
contents; it is not a facet or a side cache.

### 6.2 Code places and instructions C22–C25

```text
variant_unique sum CodePlace = LocalCodePlace { local:ref CodeLocal } | GlobalCodePlace { global:ref CodeGlobal } | DataCodePlace { data:ref CodeData } | DereferenceCodePlace { pointer:CodeValue } | FieldCodePlace { base:ref CodePlace, field:ref CompilerSource.FieldMember } | IndexCodePlace { base:ref CodePlace, index:CodeValue } | ByteRangeCodePlace { base:ref CodePlace, offset:CodeValue, length:CodeValue }

sum CodeInstruction =
  ConstInstruction { result:ref CodeLocal, constant:CodeConstant, origin:CompilerBase.Origin }
| AliasInstruction { result:ref CodeLocal, value:CodeValue, origin:CompilerBase.Origin }
| UnaryInstruction { result:ref CodeLocal, op:CompilerSource.UnaryOperation, operand:CodeValue, origin:CompilerBase.Origin }
| BinaryInstruction { result:ref CodeLocal, op:CompilerSource.BinaryOperation, left:CodeValue, right:CodeValue, origin:CompilerBase.Origin }
| FloatBinaryInstruction { result:ref CodeLocal, op:CompilerSource.BinaryOperation, left:CodeValue, right:CodeValue, origin:CompilerBase.Origin }
| CompareInstruction { result:ref CodeLocal, op:CompilerSource.ComparisonOperation, left:CodeValue, right:CodeValue, origin:CompilerBase.Origin }
| CastInstruction { result:ref CodeLocal, op:CompilerSource.ScalarOperation, value:CodeValue, origin:CompilerBase.Origin }
| SelectInstruction { result:ref CodeLocal, condition:CodeValue, true_value:CodeValue, false_value:CodeValue, origin:CompilerBase.Origin }
| VoidIntrinsicInstruction { op:CompilerSource.IntrinsicOperation, arguments:many CodeValue, origin:CompilerBase.Origin }
| ValueIntrinsicInstruction { result:ref CodeLocal, op:CompilerSource.IntrinsicOperation, arguments:many CodeValue, origin:CompilerBase.Origin }
| AddressOfInstruction { result:ref CodeLocal, place:ref CodePlace, origin:CompilerBase.Origin }
| GlobalReferenceInstruction { result:ref CodeLocal, target:GlobalReferenceTarget, origin:CompilerBase.Origin }
| PointerOffsetInstruction { result:ref CodeLocal, pointer:CodeValue, offset:CodeValue, origin:CompilerBase.Origin }
| LoadInstruction { result:ref CodeLocal, place:ref CodePlace, origin:CompilerBase.Origin }
| StoreInstruction { place:ref CodePlace, value:CodeValue, origin:CompilerBase.Origin }
| AggregateInstruction { result:ref CodeLocal, fields:many CodeValue, origin:CompilerBase.Origin }
| ArrayInstruction { result:ref CodeLocal, elements:many CodeValue, origin:CompilerBase.Origin }
| ViewMakeInstruction { result:ref CodeLocal, data:CodeValue, length:CodeValue, stride:CodeValue, origin:CompilerBase.Origin }
| ViewDataInstruction { result:ref CodeLocal, view:CodeValue, origin:CompilerBase.Origin }
| ViewLengthInstruction { result:ref CodeLocal, view:CodeValue, origin:CompilerBase.Origin }
| ViewStrideInstruction { result:ref CodeLocal, view:CodeValue, origin:CompilerBase.Origin }
| SliceMakeInstruction { result:ref CodeLocal, data:CodeValue, length:CodeValue, origin:CompilerBase.Origin }
| SliceDataInstruction { result:ref CodeLocal, slice:CodeValue, origin:CompilerBase.Origin }
| SliceLengthInstruction { result:ref CodeLocal, slice:CodeValue, origin:CompilerBase.Origin }
| ByteSpanMakeInstruction { result:ref CodeLocal, data:CodeValue, length:CodeValue, origin:CompilerBase.Origin }
| ByteSpanDataInstruction { result:ref CodeLocal, span:CodeValue, origin:CompilerBase.Origin }
| ByteSpanLengthInstruction { result:ref CodeLocal, span:CodeValue, origin:CompilerBase.Origin }
| ClosureInstruction { result:ref CodeLocal, callable:ref CodeFunction, environment:CodeValue, origin:CompilerBase.Origin }
| VariantConstructorInstruction { result:ref CodeLocal, variant:ref CompilerSource.VariantMember, payload:VariantCodePayload, origin:CompilerBase.Origin }
| VariantTagInstruction { result:ref CodeLocal, value:CodeValue, origin:CompilerBase.Origin }
| VariantPayloadInstruction { result:ref CodeLocal, value:CodeValue, variant:ref CompilerSource.VariantMember, origin:CompilerBase.Origin }
| CallInstruction { result:CallCodeResult, callee:CodeCallee, arguments:many CodeValue, origin:CompilerBase.Origin }
| AtomicLoadInstruction { result:ref CodeLocal, place:ref CodePlace, ordering:CompilerSource.AtomicOrdering, origin:CompilerBase.Origin }
| AtomicStoreInstruction { place:ref CodePlace, value:CodeValue, ordering:CompilerSource.AtomicOrdering, origin:CompilerBase.Origin }
| AtomicRmwInstruction { result:ref CodeLocal, op:CompilerSource.AtomicOperation, place:ref CodePlace, value:CodeValue, ordering:CompilerSource.AtomicOrdering, origin:CompilerBase.Origin }
| AtomicCompareExchangeInstruction { result:ref CodeLocal, place:ref CodePlace, expected:CodeValue, replacement:CodeValue, ordering:CompilerSource.AtomicOrdering, origin:CompilerBase.Origin }
| AtomicFenceInstruction { ordering:CompilerSource.AtomicOrdering, origin:CompilerBase.Origin }

sum GlobalReferenceTarget = FunctionGlobalReference { function:ref CodeFunctionIdentity } | ExternGlobalReference { extern:ref CodeExternIdentity } | GlobalGlobalReference { global:ref CodeGlobalIdentity } | DataGlobalReference { data:ref CodeDataIdentity }
sum VariantCodePayload = EmptyVariantCodePayload | PresentVariantCodePayload { value:CodeValue }
sum CallCodeResult = VoidCodeCall | ValueCodeCall { result:ref CodeLocal }
sum CodeCallee = DirectCodeCallee { function:ref CodeFunctionIdentity } | ExternalCodeCallee { extern:ref CodeExternIdentity } | IndirectCodeCallee { pointer:CodeValue } | ClosureCodeCallee { closure:CodeValue }

sum CodeTerminator = JumpTerminator { target:ref CodeBlockIdentity, arguments:many CodeValue, origin:CompilerBase.Origin } | BranchTerminator { condition:CodeValue, true_target:ref CodeBlockIdentity, true_arguments:many CodeValue, false_target:ref CodeBlockIdentity, false_arguments:many CodeValue, origin:CompilerBase.Origin } | SwitchTerminator { selector:CodeValue, arms:many CodeSwitchArm, default_target:ref CodeBlockIdentity, default_arguments:many CodeValue, origin:CompilerBase.Origin } | VariantSwitchTerminator { selector:CodeValue, arms:many CodeVariantSwitchArm, default_target:ref CodeBlockIdentity, default_arguments:many CodeValue, origin:CompilerBase.Origin } | ReturnTerminator { result:CodeReturnResult, origin:CompilerBase.Origin } | TrapTerminator { origin:CompilerBase.Origin } | UnreachableTerminator { origin:CompilerBase.Origin }
record CodeSwitchArm { match_value:CodeConstant, target:ref CodeBlockIdentity, arguments:many CodeValue }
record CodeVariantSwitchArm { variant:ref CompilerSource.VariantMember, target:ref CodeBlockIdentity, arguments:many CodeValue }
sum CodeReturnResult = VoidCodeReturn | ValueCodeReturn { value:CodeValue }
```

### 6.3 Validation gate and S3

```text
record CodeAccepted { code:ref MonomorphicCodeSpine, topology:ref TopologyDerivationInput }
coordinate ControlEdgeOccurrence { function:ref CodeFunctionIdentity, source:ref CodeBlockIdentity, target:ref CodeBlockIdentity, role:EdgeRole, ordinal:CompilerBase.Ordinal }
sum EdgeRole = JumpEdge | TrueEdge | FalseEdge | SwitchArmEdge { arm:CompilerBase.Ordinal } | SwitchDefaultEdge | VariantArmEdge { arm:CompilerBase.Ordinal } | VariantDefaultEdge
record EdgeArgumentEntry { edge:ref ControlEdgeOccurrence, argument:CodeValue, parameter:ref CodeParameter, ordinal:CompilerBase.Ordinal }
record DefinitionEntry { value:CodeValue, definition:DefinitionSite }
sum DefinitionSite = ParameterDefinition { parameter:ref CodeParameter } | LocalDefinition { local:ref CodeLocal } | InstructionDefinition { instruction:ref CodeInstruction }
coordinate UseOccurrence { value:CodeValue, user:UseSite, ordinal:CompilerBase.Ordinal }
sum UseSite = InstructionUse { instruction:ref CodeInstruction } | TerminatorUse { terminator:ref CodeTerminator }
entity NaturalLoopOccurrence { function:ref CodeFunctionIdentity, header:ref CodeBlockIdentity, body:many ref CodeBlockIdentity, latches:many ref CodeBlockIdentity, exits:many ref ControlEdgeOccurrence, parent:LoopParent, ordinal:CompilerBase.Ordinal }
sum LoopParent = RootLoop | NestedLoop { loop:ref NaturalLoopOccurrence }
entity ControlTopologySpine { code:ref MonomorphicCodeSpine, edges:many ControlEdgeOccurrence, edge_arguments:many EdgeArgumentEntry, definitions:many DefinitionEntry, uses:many UseOccurrence, loops:many NaturalLoopOccurrence, order:many TopologyOrderEntry }
sum DefUseContribution = DefinitionContribution { definition:ref DefinitionEntry } | UseContribution { use:ref UseOccurrence }
record DefUseContributions { entries:many DefUseContribution }
sum TopologyContribution = EdgeContribution { edge:ref ControlEdgeOccurrence } | EdgeArgumentContribution { argument:ref EdgeArgumentEntry } | LoopContribution { loop:ref NaturalLoopOccurrence }
record TopologyContributions { entries:many TopologyContribution }
record TopologyDerivationInput { def_use:many DefUseContributions, topology:many TopologyContributions }
record TopologyOrderEntry { ordinal:CompilerBase.Ordinal, occurrence:TopologyOccurrence }
sum TopologyOccurrence = EdgeTopologyOccurrence { edge:ref ControlEdgeOccurrence } | UseTopologyOccurrence { use:ref UseOccurrence } | LoopTopologyOccurrence { loop:ref NaturalLoopOccurrence }
```

`CodeAccepted` is the O13 validation gate, not a publication wrapper. B23 can
construct it only from a complete `CodeValidationFinalizationInput`; it carries the
validated topology contribution boundary consumed exactly once by B24.

---

## 7. CompilerAnalysis — F14–F27, S4, F34

### 7.1 Scalar attribution, algebra, flow, and effects

```text
sum AttributedOperationSubject = AttributedScalarSubject { subject:CompilerSource.ScalarCodeOperationSubject } | AttributedSelectSubject { operation:ref CompilerCode.SelectInstruction } | AttributedAddressSubject { operation:ref CompilerCode.AddressOfInstruction } | AttributedGlobalReferenceSubject { operation:ref CompilerCode.GlobalReferenceInstruction } | AttributedPointerOffsetSubject { operation:ref CompilerCode.PointerOffsetInstruction } | AttributedLoadSubject { operation:ref CompilerCode.LoadInstruction } | AttributedStoreSubject { operation:ref CompilerCode.StoreInstruction } | AttributedAtomicSubject { subject:CompilerSource.AtomicCodeOperationSubject }
record ScalarAttributionEntry { spine:ref CompilerCode.MonomorphicCodeSpine, subject:AttributedOperationSubject, meaning:CodeOperationMeaning }
sum CodeOperationMeaning = AttributedScalarOperation { meaning:ref CompilerSource.IntrinsicMeaning } | AttributedSelect { result_type:ref CompilerSource.CanonicalType } | AttributedAddressOf { result_type:ref CompilerSource.CanonicalType } | AttributedGlobalReference { result_type:ref CompilerSource.CanonicalType } | AttributedPointerOffset { pointer_type:ref CompilerSource.CanonicalType, index_type:ref CompilerSource.CanonicalType, result_type:ref CompilerSource.CanonicalType } | AttributedLoad { value_type:ref CompilerSource.CanonicalType, volatility:CompilerSource.OperationVolatility, trap:CompilerSource.TrapContract } | AttributedStore { value_type:ref CompilerSource.CanonicalType, volatility:CompilerSource.OperationVolatility, trap:CompilerSource.TrapContract } | AttributedAtomic { value_type:ref CompilerSource.CanonicalType, operation:CompilerSource.AtomicOperation, ordering:CompilerSource.AtomicOrdering, trap:CompilerSource.TrapContract }

sum ValueAlgebraEntry = ConstantRangeEntry { spine:ref CompilerCode.MonomorphicCodeSpine, value:CompilerCode.CodeValue, range:IntegerRange } | CopyCanonicalEntry { spine:ref CompilerCode.MonomorphicCodeSpine, value:CompilerCode.CodeValue, canonical:CompilerCode.CodeValue } | AffineValueEntry { spine:ref CompilerCode.MonomorphicCodeSpine, value:CompilerCode.CodeValue, expression:AffineExpression } | NoWrapEntry { spine:ref CompilerCode.MonomorphicCodeSpine, value:CompilerCode.CodeValue, proof:ValueProofReference } | FloatEvidenceEntry { spine:ref CompilerCode.MonomorphicCodeSpine, value:CompilerCode.CodeValue, evidence:FloatEvidence } | ValueProofEntry { spine:ref CompilerCode.MonomorphicCodeSpine, value:CompilerCode.CodeValue, proof:ValueProofReference }
record IntegerRange { lower:IntegerBound, upper:IntegerBound }
sum IntegerBound = FiniteIntegerBound { raw:str } | NegativeInfinityBound | PositiveInfinityBound
variant_unique sum AffineExpression = AffineConstant { raw:str } | AffineValue { value:CompilerCode.CodeValue } | AffineAdd { left:ref AffineExpression, right:ref AffineExpression } | AffineScale { scale:str, value:ref AffineExpression }
sum FloatEvidence = FiniteFloatEvidence | NonNanFloatEvidence | ExactFloatEvidence
sum ValueProofReference = ValueScalarProof { evidence:ref ScalarAttributionEntry } | ValueFlowProof { evidence:ref LoopFlowEntry } | ValueInductionProof { evidence:ref InductionEntry } | PriorValueProof { evidence:ref ValueAlgebraEntry }
sum BoundsProofReference = BoundsContractProof { evidence:ref CompilerSourceFact.ContractEvidenceEntry } | BoundsMappingProof { evidence:ref ContractRealizationEntry } | BoundsFlowProof { evidence:ref LoopFlowEntry } | BoundsInductionProof { evidence:ref InductionEntry } | BoundsValueProof { evidence:ref ValueAlgebraEntry }
sum TrapProofReference = TrapContractProof { evidence:ref CompilerSourceFact.ContractEvidenceEntry } | TrapMappingProof { evidence:ref ContractRealizationEntry } | TrapValueProof { evidence:ref ValueAlgebraEntry } | TrapOwnershipProof { evidence:ref CompilerSourceFact.StaticOwnershipEntry }
sum AlignmentProofReference = AlignmentLayoutProof { evidence:ref CompilerSourceFact.LayoutEntry } | AlignmentContractProof { evidence:ref CompilerSourceFact.ContractEvidenceEntry }
sum MovementProofReference = MovementOwnershipProof { evidence:ref CompilerSourceFact.StaticOwnershipEntry } | MovementFlowProof { evidence:ref LoopFlowEntry } | MovementInductionProof { evidence:ref InductionEntry } | MovementValueProof { evidence:ref ValueAlgebraEntry }
sum MemoryRelationProofReference = RelationContractProof { evidence:ref CompilerSourceFact.ContractEvidenceEntry } | RelationMappingProof { evidence:ref ContractRealizationEntry } | RelationObjectProof { evidence:ref MemoryObjectEntry } | RelationAccessProof { evidence:ref MemoryAccessEntry } | RelationFlowProof { evidence:ref LoopFlowEntry } | RelationInductionProof { evidence:ref InductionEntry } | RelationLayoutProof { evidence:ref CompilerSourceFact.LayoutEntry } | RelationOwnershipProof { evidence:ref CompilerSourceFact.StaticOwnershipEntry }

sum LoopFlowEntry = CountedRangeLoop { spine:ref CompilerCode.ControlTopologySpine, loop:ref CompilerCode.NaturalLoopOccurrence, counter:CompilerCode.CodeValue, start:CompilerCode.CodeValue, stop:CompilerCode.CodeValue, step:CompilerCode.CodeValue, bound:BoundConvention, direction:LoopDirection, trip:TripMeaning } | CountedGridLoop { spine:ref CompilerCode.ControlTopologySpine, loop:ref CompilerCode.NaturalLoopOccurrence, axes:many GridAxisMeaning, trip:TripMeaning } | CountedTiledLoop { spine:ref CompilerCode.ControlTopologySpine, loop:ref CompilerCode.NaturalLoopOccurrence, axes:many TiledAxisMeaning, trip:TripMeaning } | CountedWindowLoop { spine:ref CompilerCode.ControlTopologySpine, loop:ref CompilerCode.NaturalLoopOccurrence, axes:many WindowAxisMeaning, trip:TripMeaning } | CountedTraversalLoop { spine:ref CompilerCode.ControlTopologySpine, loop:ref CompilerCode.NaturalLoopOccurrence, counter:CompilerCode.CodeValue, domain:TraversalDomain, trip:TripMeaning } | UncountedLoop { spine:ref CompilerCode.ControlTopologySpine, loop:ref CompilerCode.NaturalLoopOccurrence, cause:UncountedCause }
sum BoundConvention = ExclusiveStop | InclusiveStop
sum LoopDirection = IncreasingLoop | DecreasingLoop
record TripMeaning { expression:AffineExpression }
record GridAxisMeaning { counter:CompilerCode.CodeValue, start:CompilerCode.CodeValue, stop:CompilerCode.CodeValue, step:CompilerCode.CodeValue }
record TiledAxisMeaning { outer:CompilerCode.CodeValue, inner:CompilerCode.CodeValue, tile:CompilerCode.CodeValue, start:CompilerCode.CodeValue, stop:CompilerCode.CodeValue }
record WindowAxisMeaning { counter:CompilerCode.CodeValue, start:CompilerCode.CodeValue, stop:CompilerCode.CodeValue, radius:CompilerCode.CodeValue }
record TraversalDomain { source:CompilerCode.CodeValue }
sum UncountedCause = NonCountedLoop | MissingLatch | MissingHeader | MissingCondition | AmbiguousInduction | UnsupportedRecurrence | ContradictoryDirection | InvalidDomain | UnprovableTrip

record InductionEntry { spine:ref CompilerCode.ControlTopologySpine, loop:ref CompilerCode.NaturalLoopOccurrence, value:CompilerCode.CodeValue, role:InductionRole, initial:CompilerCode.CodeValue, step:CompilerCode.CodeValue, direction:LoopDirection, range:IntegerRange, trip_link:TripLink }
sum InductionRole = PrimaryInduction | SecondaryInduction | RecurrenceInduction | DerivedInduction
sum TripLink = InductionWithTrip { flow:ref LoopFlowEntry } | InductionWithoutTrip { flow:ref LoopFlowEntry }

sum LoopAlgebraEntry = ReductionEntry { spine:ref CompilerCode.ControlTopologySpine, loop:ref CompilerCode.NaturalLoopOccurrence, value:CompilerCode.CodeValue, operation:CompilerSource.ScalarOperation, identity:CompilerSourceFact.ConstantValue, order:AssociativeOrder } | ScanEntry { spine:ref CompilerCode.ControlTopologySpine, loop:ref CompilerCode.NaturalLoopOccurrence, value:CompilerCode.CodeValue, operation:CompilerSource.ScalarOperation, identity:CompilerSourceFact.ConstantValue, order:AssociativeOrder } | RecurrenceEntry { spine:ref CompilerCode.ControlTopologySpine, loop:ref CompilerCode.NaturalLoopOccurrence, value:CompilerCode.CodeValue, expression:AffineExpression } | ClosedFormEntry { spine:ref CompilerCode.ControlTopologySpine, loop:ref CompilerCode.NaturalLoopOccurrence, value:CompilerCode.CodeValue, expression:AffineExpression } | AssociativeOrderEntry { spine:ref CompilerCode.ControlTopologySpine, loop:ref CompilerCode.NaturalLoopOccurrence, value:CompilerCode.CodeValue, order:AssociativeOrder } | AffineLoopEntry { spine:ref CompilerCode.ControlTopologySpine, loop:ref CompilerCode.NaturalLoopOccurrence, value:CompilerCode.CodeValue, expression:AffineExpression }
sum AssociativeOrder = ExactAssociativeOrder | ReassociationPermitted

record OperationEffectEntry { spine:ref CompilerCode.MonomorphicCodeSpine, operation:OperationOccurrence, summary:OperationEffectSummary }
sum OperationOccurrence = InstructionEffectSubject { instruction:ref CompilerCode.CodeInstruction } | TerminatorEffectSubject { terminator:ref CompilerCode.CodeTerminator } | ExternEffectSubject { extern:ref CompilerCode.CodeExtern }
sum OperationEffectSummary = PureOperationEffect | EffectfulOperationEffect { effects:many NonPureEffectAtom }
sum NonPureEffectAtom = ReadEffect { access:ref MemoryAccessOccurrence } | WriteEffect { access:ref MemoryAccessOccurrence } | PreserveEffect { object:ref MemoryObjectOccurrence } | InvalidateEffect { object:ref MemoryObjectOccurrence } | RetainNoescapeEffect { object:ref MemoryObjectOccurrence } | TrapEffect | VolatileEffect | AtomicEffect | CallEffect { callee:EffectCallTarget } | AllocateEffect { object:ref MemoryObjectOccurrence } | ExternalEffect | UnknownCalleeEffect { callee:EffectCallTarget } | UnresolvedExternalEffect { extern:ref CompilerCode.CodeExtern } | IncompleteOperationEffect
sum EffectCallTarget = FunctionEffectTarget { function:ref CompilerCode.CodeFunction } | ExternEffectTarget { extern:ref CompilerCode.CodeExtern } | IndirectEffectTarget { instruction:ref CompilerCode.CallInstruction } | ClosureEffectTarget { instruction:ref CompilerCode.CallInstruction }
sum CallableSummarySubject = FunctionSummarySubject { function:ref CompilerCode.CodeFunction } | ExternSummarySubject { extern:ref CompilerCode.CodeExtern }
record CallableEffectEntry { spine:ref CompilerCode.MonomorphicCodeSpine, callable:CallableSummarySubject, summary:CallableEffectSummary }
sum CallableEffectSummary = PureCallableEffect | EffectfulCallableEffect { effects:many NonPureEffectAtom } | IncompleteCallableEffect { effects:many NonPureEffectAtom }
```

### 7.2 Baseline, commitment, and dominance F18/F22/F23

```text
record BaselineFacet { code:ref CompilerCode.MonomorphicCodeSpine, entries:many BaselineEntry }
record BaselineEntry { function:ref CompilerCode.CodeFunction, capability:ref CompilerBase.GnuCEmitterCapability, coverage:BaselineCoverage }
record BaselineCoveredBlock { function:ref CompilerCode.CodeFunction, block:ref CompilerCode.CodeBlockIdentity }
record BaselineCoverage { blocks:many BaselineCoveredBlock }

sum OptimizationCommitmentEntry = BaselineCommitment { spine:ref CompilerCode.ControlTopologySpine, subject:OptimizationSubject, baseline:ref BaselineEntry, rejected:many RejectedAlternative } | ClosedFormCommitment { spine:ref CompilerCode.ControlTopologySpine, subject:OptimizationSubject, fragment:ref CompilerLower.FragmentContribution, proof:ref LoopAlgebraEntry, rejected:many RejectedAlternative } | FusedCommitment { spine:ref CompilerCode.ControlTopologySpine, subject:OptimizationSubject, fragment:ref CompilerLower.FragmentContribution, fused:ref CompilerLower.FusedComputationSpine, rejected:many RejectedAlternative }
sum OptimizationSubject = FunctionOptimizationSubject { function:ref CompilerCode.CodeFunction } | LoopOptimizationSubject { loop:ref CompilerCode.NaturalLoopOccurrence }
sum LoweringAttempt = ClosedFormAttempt { subject:OptimizationSubject } | FusedAttempt { subject:OptimizationSubject, fused:ref CompilerLower.FusedComputationSpine }
sum StrategyAlternative = KernelPlanningAlternative { request:ref CompilerLower.LoopKernelCandidateRequest } | SchedulePlanningAlternative { request:ref CompilerLower.ScheduleSelectionRequest } | FusionPlanningAlternative { request:ref CompilerLower.FusedProjectionRequest } | RealizationStrategyAlternative { attempt:LoweringAttempt }
record RejectedAlternative { alternative:StrategyAlternative, outcome:OptionalRealizationReason }

record DominanceFacet { topology:ref CompilerCode.ControlTopologySpine, entries:many DominanceEntry }
sum DominanceEntry = BlockDominance { function:ref CompilerCode.CodeFunction, dominator:ref CompilerCode.CodeBlockIdentity, dominated:ref CompilerCode.CodeBlockIdentity } | ValueAvailability { function:ref CompilerCode.CodeFunction, value:CompilerCode.CodeValue, block:ref CompilerCode.CodeBlockIdentity } | IncomingArgumentAvailability { function:ref CompilerCode.CodeFunction, edge:ref CompilerCode.ControlEdgeOccurrence, argument:CompilerCode.CodeValue, parameter:ref CompilerCode.CodeParameter } | AdapterFeasibility { function:ref CompilerCode.CodeFunction, entry:ref CompilerCode.CodeBlockIdentity, exit:ref CompilerCode.CodeBlockIdentity, values:many CompilerCode.CodeValue }
```

### 7.3 S4 memory spine

```text
record MemoryAccessCause { operation:OperationOccurrence, place:ref CompilerCode.CodePlace, role:MemoryAccessCauseRole, ordinal:CompilerBase.Ordinal }
sum MemoryAccessCauseRole = ReadAccessCause | WriteAccessCause | ReadModifyWriteAccessCause | AddressAccessCause
entity MemoryObjectOccurrence { root:MemoryRoot, parent:MemoryParent, origin:CompilerBase.Origin, ordinal:CompilerBase.Ordinal }
sum MemoryRoot = ParameterMemoryRoot { parameter:ref CompilerCode.CodeParameter } | LocalMemoryRoot { local:ref CompilerCode.CodeLocal } | GlobalMemoryRoot { global:ref CompilerCode.CodeGlobal } | DataMemoryRoot { data:ref CompilerCode.CodeData } | ViewMemoryRoot { value:CompilerCode.CodeValue } | SliceMemoryRoot { value:CompilerCode.CodeValue } | UniqueAllocationMemoryRoot { value:CompilerCode.CodeValue, declaration:ref CompilerSource.UniqueStructDeclaration }
sum MemoryParent = RootMemoryObject | SubobjectMemoryObject { parent:ref MemoryObjectOccurrence, path:StoragePathStep }
sum StoragePathStep = FieldStorageStep { field:ref CompilerSource.FieldMember } | IndexStorageStep { index:CompilerCode.CodeValue } | ByteRangeStorageStep { offset:CompilerCode.CodeValue, length:CompilerCode.CodeValue }
coordinate MemoryAccessOccurrence { operation:OperationOccurrence, object:ref MemoryObjectOccurrence, ordinal:CompilerBase.Ordinal, origin:CompilerBase.Origin }
entity MemorySpine { code:ref CompilerCode.MonomorphicCodeSpine, topology:ref CompilerCode.ControlTopologySpine, objects:many MemoryObjectOccurrence, accesses:many MemoryAccessOccurrence, order:many MemoryOrderEntry }
record MemoryOrderEntry { ordinal:CompilerBase.Ordinal, occurrence:MemoryOccurrence }
sum MemoryOccurrence = MemoryObjectRef { object:ref MemoryObjectOccurrence } | MemoryAccessRef { access:ref MemoryAccessOccurrence }
```

### 7.4 F24–F27 and F34

```text
record MemoryObjectEntry { spine:ref MemorySpine, object:ref MemoryObjectOccurrence, meaning:MemoryObjectMeaning }
sum MemoryObjectMeaning = KnownMemoryObject { storage:StorageKind, element:ref CompilerSource.CanonicalType, extent:ExtentMeaning, stride:StrideMeaning, layout:ref CompilerSourceFact.LayoutMeaning } | UnknownMemoryObject { storage:StorageKind, cause:UnknownObjectCause }
sum StorageKind = StackStorage | GlobalStorage | DataStorage | ParameterStorage | ViewStorage | SliceStorage | ClosureStorage | UniqueStorage
sum ExtentMeaning = StaticExtent { extent:CompilerBase.UnsignedExtent } | DynamicExtent { value:CompilerCode.CodeValue }
sum StrideMeaning = StaticStride { bytes:CompilerBase.ByteSize } | DynamicStride { value:CompilerCode.CodeValue }
sum UnknownObjectCause = UnknownExtent | UnknownStride | UnknownElementMeaning

sum ContractRealizationEntry = ObjectContractRealization { spine:ref MemorySpine, evidence:ref CompilerSourceFact.ContractEvidenceEntry, object:ref MemoryObjectOccurrence } | AccessContractRealization { spine:ref MemorySpine, evidence:ref CompilerSourceFact.ContractEvidenceEntry, access:ref MemoryAccessOccurrence } | ObjectPairContractRealization { spine:ref MemorySpine, evidence:ref CompilerSourceFact.ContractEvidenceEntry, left:ref MemoryObjectOccurrence, right:ref MemoryObjectOccurrence } | AccessPairContractRealization { spine:ref MemorySpine, evidence:ref CompilerSourceFact.ContractEvidenceEntry, left:ref MemoryAccessOccurrence, right:ref MemoryAccessOccurrence }

record MemoryAccessOperationMeaning { spine:ref MemorySpine, access:ref MemoryAccessOccurrence, mode:AccessMode, index:IndexMeaning, width:CompilerBase.ByteSize }
record MemoryAccessSafetyMeaning { spine:ref MemorySpine, access:ref MemoryAccessOccurrence, bounds:BoundsStatus, trap:AccessTrapStatus }
record MemoryAccessPlacementMeaning { spine:ref MemorySpine, access:ref MemoryAccessOccurrence, alignment:AlignmentStatus, movement:MovementStatus }
record MemoryAccessEntry { spine:ref MemorySpine, access:ref MemoryAccessOccurrence, operation:ref MemoryAccessOperationMeaning, safety:ref MemoryAccessSafetyMeaning, placement:ref MemoryAccessPlacementMeaning }
sum AccessMode = LoadAccess | StoreAccess | ReadModifyWriteAccess | AddressAccess
sum IndexMeaning = ScalarIndexMeaning { value:CompilerCode.CodeValue } | AffineIndexMeaning { expression:AffineExpression } | FieldIndexMeaning { field:ref CompilerSource.FieldMember } | ByteIndexMeaning { offset:CompilerCode.CodeValue }
sum BoundsStatus = BoundsProven { evidence:BoundsProofReference } | BoundsUnproven | BoundsUnknown
sum AccessTrapStatus = NonTrapping { evidence:TrapProofReference } | MayTrap | MustTrap
sum AlignmentStatus = Aligned { alignment:CompilerBase.ByteAlignment, evidence:AlignmentProofReference } | Unaligned
sum MovementStatus = Movable { evidence:MovementProofReference } | Immovable | Pinned

sum MemoryRelationEntry = SameStore { spine:ref MemorySpine, left:ref MemoryObjectOccurrence, right:ref MemoryObjectOccurrence, proof:MemoryRelationProofReference } | SubobjectOverlap { spine:ref MemorySpine, left:ref MemoryObjectOccurrence, right:ref MemoryObjectOccurrence, proof:MemoryRelationProofReference } | Disjoint { spine:ref MemorySpine, left:ref MemoryObjectOccurrence, right:ref MemoryObjectOccurrence, proof:MemoryRelationProofReference } | ExactNoalias { spine:ref MemorySpine, left:ref MemoryObjectOccurrence, right:ref MemoryObjectOccurrence, declaration:ref CompilerSourceFact.CanonicalPairNoalias, mapping:ref ObjectPairContractRealization } | ProvenAlias { spine:ref MemorySpine, left:ref MemoryObjectOccurrence, right:ref MemoryObjectOccurrence, proof:MemoryRelationProofReference } | Dependence { spine:ref MemorySpine, source:ref MemoryAccessOccurrence, sink:ref MemoryAccessOccurrence, proof:MemoryRelationProofReference } | LoopCarriedDependence { spine:ref MemorySpine, loop:ref CompilerCode.NaturalLoopOccurrence, source:ref MemoryAccessOccurrence, sink:ref MemoryAccessOccurrence, proof:MemoryRelationProofReference } | MayAlias { spine:ref MemorySpine, left:ref MemoryObjectOccurrence, right:ref MemoryObjectOccurrence } | IncomparableRelation { spine:ref MemorySpine, left:ref MemoryObjectOccurrence, right:ref MemoryObjectOccurrence } | UnknownDependence { spine:ref MemorySpine, source:ref MemoryAccessOccurrence, sink:ref MemoryAccessOccurrence }

sum StorageOwnershipEntry = StorageLeaseOrigin { spine:ref MemorySpine, object:ref MemoryObjectOccurrence, source:ref CompilerSourceFact.StaticOwnershipEntry } | StorageLeaseLive { spine:ref MemorySpine, object:ref MemoryObjectOccurrence, use:CompilerSource.SemanticOccurrence } | StorageInvalidated { spine:ref MemorySpine, object:ref MemoryObjectOccurrence, cause:ref OperationEffectEntry } | StorageDischarged { spine:ref MemorySpine, object:ref MemoryObjectOccurrence, cause:CompilerSource.SemanticOccurrence } | StorageNoescape { spine:ref MemorySpine, object:ref MemoryObjectOccurrence, call:ref CompilerCode.CallInstruction, effect:ref CallableEffectEntry }
```

---

## 8. CompilerLower — S5–S7, F28–F33, fragments

### 8.1 S5 and F28/F29

```text
entity KernelOccurrence { subject:ref CompilerCode.NaturalLoopOccurrence, lanes:many KernelLaneOccurrence, bindings:many KernelBindingOccurrence, results:many KernelResultOccurrence, origin:CompilerBase.Origin }
coordinate KernelLaneOccurrence { source:KernelLaneSource, ordinal:CompilerBase.Ordinal }
sum KernelLaneSource = InductionLane { induction:ref CompilerAnalysis.InductionEntry } | MemoryLane { access:ref CompilerAnalysis.MemoryAccessOccurrence } | ResultLane { value:CompilerCode.CodeValue }
coordinate KernelBindingOccurrence { source:CompilerCode.CodeValue, ordinal:CompilerBase.Ordinal }
coordinate KernelResultOccurrence { source:CompilerCode.CodeValue, ordinal:CompilerBase.Ordinal }
entity KernelSpine { topology:ref CompilerCode.ControlTopologySpine, memory:ref CompilerAnalysis.MemorySpine, kernels:many KernelOccurrence, order:many KernelOrderEntry }
record KernelOrderEntry { ordinal:CompilerBase.Ordinal, occurrence:KernelChildOccurrence }
sum KernelChildOccurrence = KernelRef { kernel:ref KernelOccurrence } | KernelLaneRef { lane:ref KernelLaneOccurrence } | KernelBindingRef { binding:ref KernelBindingOccurrence } | KernelResultRef { result:ref KernelResultOccurrence }

record KernelMeaningFacet { kernels:ref KernelSpine, entries:many KernelMeaningEntry }
record KernelMeaningEntry { kernel:ref KernelOccurrence, form:KernelForm, domain:ref CompilerAnalysis.LoopFlowEntry, lanes:many KernelLaneMeaning, bindings:many KernelBindingMeaning, results:many KernelResultMeaning, equivalence:EquivalenceRequirement, evidence:many KernelEvidenceReference }
sum KernelForm = MapKernel | ReduceKernel | ScanKernel | WindowKernel | TraversalKernel | FindKernel | AllKernel | AnyKernel | AllCompareKernel
record KernelLaneMeaning { lane:ref KernelLaneOccurrence, role:KernelLaneRole }
sum KernelLaneRole = CounterLane | InputLane | OutputLane | AccumulatorLane | WindowLane
record KernelBindingMeaning { binding:ref KernelBindingOccurrence, expression:CompilerAnalysis.AffineExpression }
record KernelResultMeaning { result:ref KernelResultOccurrence, protocol:KernelResultProtocol }
sum KernelResultProtocol = ScalarKernelResult | StoredKernelResult { access:ref CompilerAnalysis.MemoryAccessOccurrence } | ReductionKernelResult | FindKernelResult | PredicateKernelResult | AllCompareKernelResult
sum EquivalenceRequirement = ExactEquivalence | ReassociationEquivalence
sum KernelEvidenceReference = KernelScalarEvidence { entry:ref CompilerAnalysis.ScalarAttributionEntry } | KernelValueEvidence { entry:ref CompilerAnalysis.ValueAlgebraEntry } | KernelFlowEvidence { entry:ref CompilerAnalysis.LoopFlowEntry } | KernelLoopAlgebraEvidence { entry:ref CompilerAnalysis.LoopAlgebraEntry } | KernelObjectEvidence { entry:ref CompilerAnalysis.MemoryObjectEntry } | KernelAccessEvidence { entry:ref CompilerAnalysis.MemoryAccessEntry } | KernelRelationEvidence { entry:ref CompilerAnalysis.MemoryRelationEntry } | KernelEffectEvidence { entry:ref CompilerAnalysis.OperationEffectEntry } | KernelCallableEffectEvidence { entry:ref CompilerAnalysis.CallableEffectEntry }

record ScheduleEntry { spine:ref KernelSpine, kernel:ref KernelOccurrence, form:ScheduleForm, tail:ScheduleTail, policy:ref CompilerBase.CompilerPolicy, target:ref CompilerBase.TargetSpec, capability:ref CompilerBase.GnuCEmitterCapability, proofs:many KernelEvidenceReference, rejected:many ScheduleRejectedAlternative }
sum ScheduleForm = ScalarSchedule | VectorSchedule { width:CompilerBase.UnsignedExtent } | TiledSchedule { tile:CompilerBase.UnsignedExtent }
sum ScheduleTail = ExactScheduleTail | MaskedScheduleTail | ScalarRemainderTail
record ScheduleRejectedAlternative { form:ScheduleForm, reason:CompilerLower.ScheduleNoPlanReason }
```

### 8.2 S6 and F30

```text
entity FusedComputationOccurrence { kernel:ref KernelOccurrence, axes:many FusedAxisOccurrence, producers:many FusedProducerOccurrence, streams:many FusedStreamOccurrence, accesses:many FusedAccessOccurrence, sinks:many FusedSinkOccurrence, results:many FusedResultOccurrence, origin:CompilerBase.Origin }
coordinate FusedAxisOccurrence { source:ref KernelLaneOccurrence, ordinal:CompilerBase.Ordinal }
coordinate FusedProducerOccurrence { source:ref KernelBindingOccurrence, ordinal:CompilerBase.Ordinal }
coordinate FusedStreamOccurrence { producer:ref FusedProducerOccurrence, ordinal:CompilerBase.Ordinal }
coordinate FusedAccessOccurrence { source:ref CompilerAnalysis.MemoryAccessOccurrence, stream:FusedStreamSource, ordinal:CompilerBase.Ordinal }
sum FusedStreamSource = FusedStreamRef { stream:ref FusedStreamOccurrence } | FusedSinkStream { sink:ref FusedSinkOccurrence }
coordinate FusedSinkOccurrence { source:ref KernelResultOccurrence, ordinal:CompilerBase.Ordinal }
coordinate FusedResultOccurrence { source:ref KernelResultOccurrence, ordinal:CompilerBase.Ordinal }
entity FusedComputationSpine { kernels:ref KernelSpine, computations:many FusedComputationOccurrence, order:many FusedOrderEntry }
record FusedOrderEntry { ordinal:CompilerBase.Ordinal, occurrence:FusedOccurrence }
sum FusedOccurrence = FusedComputationRef { computation:ref FusedComputationOccurrence } | FusedAxisRef { axis:ref FusedAxisOccurrence } | FusedProducerRef { producer:ref FusedProducerOccurrence } | FusedStreamRefOccurrence { stream:ref FusedStreamOccurrence } | FusedAccessRef { access:ref FusedAccessOccurrence } | FusedSinkRef { sink:ref FusedSinkOccurrence } | FusedResultRef { result:ref FusedResultOccurrence }

record FusedMeaningFacet { fused:ref FusedComputationSpine, entries:many FusedMeaningEntry }
sum FusedMeaningEntry = FusedComputationMeaning { computation:ref FusedComputationOccurrence, schedule:ref ScheduleEntry, iteration:ref CompilerAnalysis.LoopFlowEntry } | FusedAxisMeaning { axis:ref FusedAxisOccurrence, induction:ref CompilerAnalysis.InductionEntry } | FusedProducerMeaning { producer:ref FusedProducerOccurrence, expression:CompilerAnalysis.AffineExpression } | FusedStreamMeaning { stream:ref FusedStreamOccurrence, operation:CompilerSource.ScalarOperation } | FusedAccessMeaning { access:ref FusedAccessOccurrence, role:FusedAccessRole, memory:ref CompilerAnalysis.MemoryAccessEntry } | FusedSinkMeaning { sink:ref FusedSinkOccurrence, operation:CompilerSource.ScalarOperation } | FusedResultMeaning { result:ref FusedResultOccurrence, protocol:KernelResultProtocol }
sum FusedAccessRole = FusedLoadAccess | FusedStoreAccess | FusedWindowAccess | FusedSinkAccess
```

### 8.3 Candidate records, S7, and F31–F33

Candidates are non-interned one-consumer records. They contain no S7 identity.

```text
record ProposedUse { ordinal:CompilerBase.Ordinal, source:ref FusedAccessOccurrence }
record UsePopulationCandidateRecord { fused:ref FusedComputationSpine, computation:ref FusedComputationOccurrence, uses:many ProposedUse }
record ProposedUseMeaning { use:ref ProposedUse, role:MaterializedUseRole, index:UseIndexMeaning, access:ref CompilerAnalysis.MemoryAccessEntry }
record UseMeaningCandidateRecord { population:ref UsePopulationCandidateRecord, meanings:many ProposedUseMeaning }
record ProposedCoordinate { use:ref ProposedUse, coordinate:UseCoordinate }
record CoordinateCandidateRecord { meaning:ref UseMeaningCandidateRecord, coordinates:many ProposedCoordinate }

coordinate MaterializedUseOccurrence { source:ref FusedAccessOccurrence, ordinal:CompilerBase.Ordinal, origin:CompilerBase.Origin }
entity MaterializedUseSpine { fused:ref FusedComputationSpine, computation:ref FusedComputationOccurrence, uses:many MaterializedUseOccurrence, order:many MaterializedUseOrderEntry }
record MaterializedUseOrderEntry { ordinal:CompilerBase.Ordinal, use:ref MaterializedUseOccurrence }

record MaterializedUseFacet { uses:ref MaterializedUseSpine, entries:many MaterializedUseEntry }
record MaterializedUseEntry { use:ref MaterializedUseOccurrence, role:MaterializedUseRole, index:UseIndexMeaning, source:ref CompilerAnalysis.MemoryAccessEntry }
sum MaterializedUseRole = MaterializedLoad | MaterializedStore | MaterializedSink | MaterializedWindow
sum UseIndexMeaning = DirectUseIndex { source:ref CompilerAnalysis.MemoryAccessOperationMeaning } | WindowUseIndex { source:ref CompilerAnalysis.MemoryAccessOperationMeaning, displacement:CompilerBase.SignedOffset } | DynamicWindowUseIndex { source:ref CompilerAnalysis.MemoryAccessOperationMeaning, displacement:CompilerCode.CodeValue }

record CoordinateFacet { uses:ref MaterializedUseSpine, entries:many CoordinateEntry }
record CoordinateEntry { use:ref MaterializedUseOccurrence, coordinate:UseCoordinate }
sum UseCoordinate = AbsoluteCoordinate { byte_offset:CompilerAnalysis.AffineExpression } | IterationAffineCoordinate { basis:CoordinateBasis, expression:CompilerAnalysis.AffineExpression } | WindowRelativeCoordinate { basis:CoordinateBasis, displacement:CompilerBase.SignedOffset, scale:CompilerBase.ByteSize } | WindowDynamicCoordinate { basis:CoordinateBasis, displacement:CompilerCode.CodeValue, scale:CompilerBase.ByteSize }
sum CoordinateBasis = ObjectCoordinateBasis { object:ref CompilerAnalysis.MemoryObjectOccurrence } | StreamCoordinateBasis { stream:ref FusedStreamOccurrence } | SinkCoordinateBasis { sink:ref FusedSinkOccurrence }

record PointerQualificationEntry { spine:ref MaterializedUseSpine, group:UseGroup, pairs:many ExactQualificationPair }
record ExactQualificationPair { left:ref PointerGroupMember, right:ref PointerGroupMember, declaration:ref CompilerSourceFact.CanonicalPairNoalias, relation:ref CompilerAnalysis.ExactNoalias, mapping:ref CompilerAnalysis.ObjectPairContractRealization }
record UseGroup { members:many PointerGroupMember }
record PointerGroupMember { object:ref CompilerAnalysis.MemoryObjectOccurrence, uses:many ref MaterializedUseOccurrence }

record AddressRecord { use:ref MaterializedUseOccurrence, coordinate:ref CoordinateEntry, base:AddressBasis, environment:ref RealizationEnvironment }
sum AddressBasis = ObjectAddressBasis { object:ref CompilerAnalysis.MemoryObjectOccurrence } | StreamAddressBasis { stream:ref FusedStreamOccurrence } | SinkAddressBasis { sink:ref FusedSinkOccurrence }
record RealizationEnvironment { values:many RealizationValueBinding }
record RealizationValueBinding { source:CompilerCode.CodeValue }
```

A qualified `UseGroup` contains at least two members with distinct memory objects, and each covered S7 use
occurs in exactly one member. Its `pairs` field is the exact lexicographic sequence of every distinct
unordered member pair; each pair carries its own declared pairwise-noalias evidence, memory relation, and
storage mapping. Unary noalias, inferred disjointness, a singleton group, or a partial pair set cannot
construct F33.

### 8.4 Fragments

```text
sum FragmentSubject = ClosedFormFragmentSubject { loop:ref CompilerCode.NaturalLoopOccurrence, algebra:ref CompilerAnalysis.LoopAlgebraEntry } | FusedFragmentSubject { computation:ref FusedComputationOccurrence }
coordinate FragmentValueOccurrence { source:FragmentValueSource, ordinal:CompilerBase.Ordinal }
sum FragmentValueSource = CodeFragmentValue { value:CompilerCode.CodeValue } | UseFragmentValue { use:ref MaterializedUseOccurrence } | GeneratedFragmentValue { origin:CompilerBase.Origin }
coordinate FragmentLocalOccurrence { type_value:ref CompilerCode.CodeType, ordinal:CompilerBase.Ordinal, origin:CompilerBase.Origin }
coordinate FragmentLabelOccurrence { ordinal:CompilerBase.Ordinal, origin:CompilerBase.Origin }
record FragmentCoveredBlock { subject:FragmentSubject, block:ref CompilerCode.CodeBlockIdentity }
entity FragmentContribution { subject:FragmentSubject, covered_blocks:many FragmentCoveredBlock, values:many FragmentValueOccurrence, bindings:many FragmentValueBinding, locals:many FragmentLocalOccurrence, labels:many FragmentLabelOccurrence, operations:many FragmentOperation, exits:many FragmentExit, helpers:many FragmentHelperRequirement }
record FragmentValueBinding { source:CompilerCode.CodeValue, value:ref FragmentValueOccurrence }
sum FragmentOperation = FragmentAssign { target:ref FragmentValueOccurrence, value:FragmentExpression } | FragmentLoad { target:ref FragmentValueOccurrence, address:ref AddressRecord } | FragmentStore { address:ref AddressRecord, value:ref FragmentValueOccurrence } | FragmentCall { target:FragmentCallTarget, arguments:many FragmentValueOccurrence, result:FragmentCallResult } | FragmentBranch { condition:ref FragmentValueOccurrence, true_label:ref FragmentLabelOccurrence, false_label:ref FragmentLabelOccurrence } | FragmentJump { label:ref FragmentLabelOccurrence }
sum FragmentExpression = FragmentConstant { value:CompilerSourceFact.ConstantValue } | FragmentUnary { op:CompilerSource.UnaryOperation, operand:ref FragmentValueOccurrence } | FragmentBinary { op:CompilerSource.BinaryOperation, left:ref FragmentValueOccurrence, right:ref FragmentValueOccurrence } | FragmentCompare { op:CompilerSource.ComparisonOperation, left:ref FragmentValueOccurrence, right:ref FragmentValueOccurrence } | FragmentLogic { op:CompilerSource.LogicOperation, left:ref FragmentValueOccurrence, right:ref FragmentValueOccurrence } | FragmentSelect { condition:ref FragmentValueOccurrence, true_value:ref FragmentValueOccurrence, false_value:ref FragmentValueOccurrence } | FragmentCast { op:CompilerSource.ScalarOperation, value:ref FragmentValueOccurrence }
sum FragmentCallTarget = FragmentHelperTarget { helper:FragmentHelperRequirement } | FragmentCodeFunctionTarget { function:ref CompilerCode.CodeFunction }
sum FragmentCallResult = VoidFragmentCall | ValueFragmentCall { result:ref FragmentValueOccurrence }
record FragmentExit { label:ref FragmentLabelOccurrence, target:ref CompilerCode.CodeBlock, arguments:many FragmentExitArgument }
record FragmentExitArgument { value:ref FragmentValueOccurrence, parameter:ref CompilerCode.CodeParameter, ordinal:CompilerBase.Ordinal }
record FragmentHelperRequirement { symbol:CompilerBase.SymbolKey, signature:ref CompilerCode.CodeSignature }
```

---

## 9. CompilerBackend — S8, C26–C28, artifact

### 9.1 Physical spine C26

```text
record BackendType { code_type:ref CompilerCode.CodeType, layout:ref CompilerSourceFact.LayoutMeaning }
record BackendSignature { code_signature:ref CompilerCode.CodeSignature, abi:ref CompilerSourceFact.CallableAbiEntry }
entity BackendFunctionIdentity { origin:CompilerBase.Origin }
entity BackendExternIdentity { origin:CompilerBase.Origin }
entity BackendGlobalIdentity { origin:CompilerBase.Origin }
entity BackendDataIdentity { origin:CompilerBase.Origin }
entity BackendHelperIdentity { origin:CompilerBase.Origin }
record BackendFunction { identity:ref BackendFunctionIdentity, source:BackendFunctionSource, signature:ref BackendSignature, parameters:many BackendParameter, locals:many BackendLocal, blocks:many BackendBlock }
sum BackendFunctionSource = BaselineFunctionSource { function:ref CompilerCode.CodeFunction } | FragmentFunctionSource { contribution:ref CompilerLower.FragmentContribution }
record BackendExtern { identity:ref BackendExternIdentity, source:ref CompilerCode.CodeExtern, signature:ref BackendSignature }
sum PhysicalObjectLinkage = InternalPhysicalObjectLinkage | ExportedPhysicalObjectLinkage
record BackendGlobal { identity:ref BackendGlobalIdentity, source:ref CompilerCode.CodeGlobal, type_value:ref BackendType, initializer:BackendInitializer, symbol:CompilerBase.SymbolKey, linkage:PhysicalObjectLinkage }
record BackendData { identity:ref BackendDataIdentity, source:ref CompilerCode.CodeData, bytes:str, alignment:CompilerBase.ByteAlignment, symbol:CompilerBase.SymbolKey, linkage:PhysicalObjectLinkage }
record BackendHelper { identity:ref BackendHelperIdentity, source:BackendHelperSource, parameters:many BackendParameter, locals:many BackendLocal, blocks:many BackendBlock }
sum BackendHelperSource = FragmentHelperSource { requirement:ref CompilerLower.FragmentHelperRequirement } | IntrinsicHelperSource { operation:CompilerSource.IntrinsicOperation, signature:ref BackendSignature }
coordinate BackendParameter { source:BackendParameterSource, type_value:ref BackendType, ordinal:CompilerBase.Ordinal, origin:CompilerBase.Origin }
sum BackendParameterSource = CodeBackendParameter { parameter:ref CompilerCode.CodeParameter } | FragmentBackendParameter { value:ref CompilerLower.FragmentValueOccurrence }
coordinate BackendLocal { source:BackendLocalSource, type_value:ref BackendType, ordinal:CompilerBase.Ordinal, origin:CompilerBase.Origin }
sum BackendLocalSource = CodeBackendLocal { local:ref CompilerCode.CodeLocal } | FragmentBackendLocal { local:ref CompilerLower.FragmentLocalOccurrence }
coordinate BackendBlock { source:BackendBlockSource, labels:many BackendLabel, statements:many BackendStatement, terminator:ref BackendTerminator, ordinal:CompilerBase.Ordinal, origin:CompilerBase.Origin }
sum BackendBlockSource = CodeBackendBlock { block:ref CompilerCode.CodeBlock } | FragmentBackendBlock { contribution:ref CompilerLower.FragmentContribution }
coordinate BackendLabel { source:BackendLabelSource, ordinal:CompilerBase.Ordinal, origin:CompilerBase.Origin }
sum BackendLabelSource = CodeBackendLabel { block:ref CompilerCode.CodeBlock } | FragmentBackendLabel { label:ref CompilerLower.FragmentLabelOccurrence }
coordinate BackendStatement { payload:BackendOperationPayload, ordinal:CompilerBase.Ordinal, origin:CompilerBase.Origin }
coordinate BackendTerminator { payload:BackendTerminatorPayload, origin:CompilerBase.Origin }
sum BackendInitializer = BackendZeroInitializer | BackendConstantInitializer { constant:CompilerCode.CodeConstant } | BackendBytesInitializer { bytes:str } | BackendRelocatableInitializer { relocations:many ref BackendRelocation }
coordinate BackendRelocation { source:BackendRelocationSource, target:BackendRelocationTarget, offset:CompilerBase.UnsignedExtent, origin:CompilerBase.Origin }
sum BackendRelocationSource = BackendGlobalRelocationSource { global:ref BackendGlobalIdentity } | BackendDataRelocationSource { data:ref BackendDataIdentity }
sum BackendRelocationTarget = BackendFunctionRelocationTarget { function:ref BackendFunctionIdentity } | BackendExternRelocationTarget { extern:ref BackendExternIdentity } | BackendGlobalRelocationTarget { global:ref BackendGlobalIdentity } | BackendDataRelocationTarget { data:ref BackendDataIdentity }
record BaselineContribution { function:ref CompilerCode.CodeFunction, baseline:ref CompilerAnalysis.BaselineEntry }
record AcceptedFragmentContribution { contribution:ref CompilerLower.FragmentContribution, commitment:ref CompilerAnalysis.OptimizationCommitmentEntry, shape:ContributionEmissionShape }
sum ContributionEmissionShape = InlineContributionShape { function:ref CompilerCode.CodeFunction } | HelperContributionShape { helper:ref CompilerLower.FragmentHelperRequirement } | StandaloneContributionShape { signature:ref CompilerCode.CodeSignature }
sum BackendContribution = BaselineBackendContribution { contribution:BaselineContribution } | FragmentBackendContribution { contribution:AcceptedFragmentContribution }
record BlockParameterEliminationEntry { block:ref CompilerCode.CodeBlockIdentity, parameter:ref CompilerCode.CodeParameter, incoming:many BackendIncomingValue }
record BackendIncomingValue { edge:ref CompilerCode.ControlEdgeOccurrence, value:BackendValue }
entity PhysicalBackendSpine { code:ref CompilerCode.MonomorphicCodeSpine, target:ref CompilerBase.TargetSpec, contributions:many BackendContribution, block_parameters:many BlockParameterEliminationEntry, types:many BackendType, signatures:many BackendSignature, functions:many BackendFunction, externs:many BackendExtern, globals:many BackendGlobal, data:many BackendData, helpers:many BackendHelper, relocations:many BackendRelocation, order:many BackendOrderEntry }
record BackendOrderEntry { ordinal:CompilerBase.Ordinal, occurrence:BackendOccurrence }
sum BackendOccurrence = BackendTypeOccurrence { type_value:ref BackendType } | BackendSignatureOccurrence { signature:ref BackendSignature } | BackendFunctionOccurrence { function:ref BackendFunction } | BackendExternOccurrence { extern:ref BackendExtern } | BackendGlobalOccurrence { global:ref BackendGlobal } | BackendDataOccurrence { data:ref BackendData } | BackendHelperOccurrence { helper:ref BackendHelper } | BackendParameterOccurrence { parameter:ref BackendParameter } | BackendLocalOccurrence { local:ref BackendLocal } | BackendBlockOccurrence { block:ref BackendBlock } | BackendLabelOccurrence { label:ref BackendLabel } | BackendStatementOccurrence { statement:ref BackendStatement } | BackendTerminatorOccurrence { terminator:ref BackendTerminator } | BackendRelocationOccurrence { relocation:ref BackendRelocation }
sum BackendConstructionContribution = ConstructedBackendOccurrence { occurrence:BackendOccurrence } | ConstructedBackendValue { value:BackendValue } | ConstructedBackendPlace { place:BackendPlace } | ConstructedBackendOperation { operation:BackendOperationPayload } | ConstructedBackendTerminatorPayload { terminator:BackendTerminatorPayload }
sum BackendValidationSubject = StoredBackendValidationSubject { occurrence:BackendOccurrence } | BackendValueValidationSubject { value:BackendValue } | BackendPlaceValidationSubject { place:BackendPlace } | BackendOperationValidationSubject { operation:BackendOperationPayload } | BackendTerminatorPayloadValidationSubject { terminator:BackendTerminatorPayload }
sum BackendProvenance = CodeBackendProvenance { occurrence:CompilerCode.CodeOccurrence } | FragmentBackendProvenance { subject:CompilerLower.FragmentSubject }
record BackendFunctionIdentityEntry { source:BackendFunctionSource, identity:ref BackendFunctionIdentity }
record BackendExternIdentityEntry { source:ref CompilerCode.CodeExtern, identity:ref BackendExternIdentity }
record BackendGlobalIdentityEntry { source:ref CompilerCode.CodeGlobal, identity:ref BackendGlobalIdentity }
record BackendDataIdentityEntry { source:ref CompilerCode.CodeData, identity:ref BackendDataIdentity }
record BackendHelperIdentityEntry { source:BackendHelperSource, identity:ref BackendHelperIdentity }
record BackendParameterIdentityEntry { source:BackendParameterSource, parameter:ref BackendParameter }
record BackendLocalIdentityEntry { source:BackendLocalSource, local:ref BackendLocal }
record BackendLabelIdentityEntry { source:BackendLabelSource, label:ref BackendLabel }
record BackendIdentityProjection { functions:many BackendFunctionIdentityEntry, externs:many BackendExternIdentityEntry, globals:many BackendGlobalIdentityEntry, data:many BackendDataIdentityEntry, helpers:many BackendHelperIdentityEntry, parameters:many BackendParameterIdentityEntry, locals:many BackendLocalIdentityEntry, labels:many BackendLabelIdentityEntry }
```

`BackendIdentityProjection` is an operation-local readonly boundary record with one B54 consumer. It is not
published, retained, or reused as a facet/world/plan. Preallocating its typed identities makes recursive calls,
relocations, locals, and labels constructible without a Lua side table or encoded-name lookup.

### 9.2 Payload leaves C27

```text
sum BackendValue = BackendParameterValue { parameter:ref BackendParameter } | BackendLocalValue { local:ref BackendLocal } | BackendConstantValue { constant:CompilerCode.CodeConstant } | BackendGlobalValue { global:ref BackendGlobalIdentity } | BackendDataValue { data:ref BackendDataIdentity } | BackendFunctionValue { function:ref BackendFunctionIdentity } | BackendExternValue { extern:ref BackendExternIdentity }
sum BackendPlace = BackendLocalPlace { local:ref BackendLocal } | BackendGlobalPlace { global:ref BackendGlobalIdentity } | BackendDataPlace { data:ref BackendDataIdentity } | BackendDereferencePlace { pointer:BackendValue } | BackendFieldPlace { base:ref BackendPlace, offset:CompilerBase.UnsignedExtent } | BackendIndexPlace { base:ref BackendPlace, index:BackendValue, stride:CompilerBase.ByteSize } | BackendByteRangePlace { base:ref BackendPlace, offset:BackendValue, length:BackendValue }
sum BackendCastKind = BackendSourceCast { op:CompilerSource.SourceCastOperation } | BackendMachineCast { op:CompilerSource.MachineCastOperation }
sum BackendViewOperation = BackendViewMake { target:ref BackendLocal, data:BackendValue, length:BackendValue, stride:BackendValue } | BackendViewData { target:ref BackendLocal, view:BackendValue } | BackendViewLength { target:ref BackendLocal, view:BackendValue } | BackendViewStride { target:ref BackendLocal, view:BackendValue }
sum BackendSliceOperation = BackendSliceMake { target:ref BackendLocal, data:BackendValue, length:BackendValue } | BackendSliceData { target:ref BackendLocal, slice:BackendValue } | BackendSliceLength { target:ref BackendLocal, slice:BackendValue } | BackendByteSpanMake { target:ref BackendLocal, data:BackendValue, length:BackendValue } | BackendByteSpanData { target:ref BackendLocal, span:BackendValue } | BackendByteSpanLength { target:ref BackendLocal, span:BackendValue }
sum BackendOperationPayload = BackendConstantOp { target:ref BackendLocal, constant:CompilerCode.CodeConstant } | BackendAliasOp { target:ref BackendLocal, value:BackendValue } | BackendUnaryOp { target:ref BackendLocal, op:CompilerSource.UnaryOperation, operand:BackendValue } | BackendBinaryOp { target:ref BackendLocal, op:CompilerSource.BinaryOperation, left:BackendValue, right:BackendValue } | BackendCompareOp { target:ref BackendLocal, op:CompilerSource.ComparisonOperation, left:BackendValue, right:BackendValue } | BackendCastOp { target:ref BackendLocal, op:BackendCastKind, value:BackendValue } | BackendSelectOp { target:ref BackendLocal, condition:BackendValue, true_value:BackendValue, false_value:BackendValue } | BackendAddressOp { target:ref BackendLocal, place:ref BackendPlace } | BackendPointerOffsetOp { target:ref BackendLocal, pointer:BackendValue, offset:BackendValue } | BackendLoadOp { target:ref BackendLocal, place:ref BackendPlace, qualification:BackendPointerQualification, volatility:BackendVolatility } | BackendStoreOp { place:ref BackendPlace, value:BackendValue, qualification:BackendPointerQualification, volatility:BackendVolatility } | BackendAggregateOp { target:ref BackendLocal, values:many BackendValue } | BackendViewOp { operation:BackendViewOperation } | BackendSliceOp { operation:BackendSliceOperation } | BackendClosureOp { target:ref BackendLocal, function:ref BackendFunctionIdentity, environment:BackendValue } | BackendVariantConstructOp { target:ref BackendLocal, variant:ref CompilerSource.VariantMember, payload:BackendVariantPayload } | BackendVariantTagOp { target:ref BackendLocal, value:BackendValue } | BackendVariantPayloadOp { target:ref BackendLocal, value:BackendValue, variant:ref CompilerSource.VariantMember } | BackendDirectCallOp { result:BackendCallResult, function:ref BackendFunctionIdentity, arguments:many BackendValue } | BackendExternalCallOp { result:BackendCallResult, extern:ref BackendExternIdentity, arguments:many BackendValue } | BackendIndirectCallOp { result:BackendCallResult, pointer:BackendValue, arguments:many BackendValue } | BackendClosureCallOp { result:BackendCallResult, closure:BackendValue, arguments:many BackendValue } | BackendAtomicLoadOp { target:ref BackendLocal, place:ref BackendPlace, ordering:CompilerSource.AtomicOrdering } | BackendAtomicStoreOp { place:ref BackendPlace, value:BackendValue, ordering:CompilerSource.AtomicOrdering } | BackendAtomicRmwOp { target:ref BackendLocal, op:CompilerSource.AtomicOperation, place:ref BackendPlace, value:BackendValue, ordering:CompilerSource.AtomicOrdering } | BackendAtomicCompareExchangeOp { target:ref BackendLocal, place:ref BackendPlace, expected:BackendValue, replacement:BackendValue, ordering:CompilerSource.AtomicOrdering } | BackendAtomicFenceOp { ordering:CompilerSource.AtomicOrdering } | BackendHelperCallOp { result:BackendCallResult, helper:ref BackendHelperIdentity, arguments:many BackendValue }
sum BackendVolatility = NonvolatileBackendAccess | VolatileBackendAccess
sum BackendTerminatorPayload = BackendJumpTerm { target:ref BackendLabel } | BackendBranchTerm { condition:BackendValue, true_target:ref BackendLabel, false_target:ref BackendLabel } | BackendSwitchTerm { selector:BackendValue, arms:many BackendSwitchArm, default_target:ref BackendLabel } | BackendVariantSwitchTerm { selector:BackendValue, arms:many BackendVariantSwitchArm, default_target:ref BackendLabel } | BackendReturnTerm { result:BackendReturnResult } | BackendTrapTerm | BackendUnreachableTerm
sum BackendPointerQualification = UnqualifiedBackendPointer | QualifiedBackendPointer { evidence:ref CompilerLower.PointerQualificationEntry }
sum BackendVariantPayload = EmptyBackendVariantPayload | PresentBackendVariantPayload { value:BackendValue }
sum BackendCallResult = VoidBackendCall | ValueBackendCall { target:ref BackendLocal }
sum BackendReturnResult = VoidBackendReturn | ValueBackendReturn { value:BackendValue }
record BackendSwitchArm { match_value:CompilerCode.CodeConstant, target:ref BackendLabel }
record BackendVariantSwitchArm { variant:ref CompilerSource.VariantMember, target:ref BackendLabel }
```

C24 value/void intrinsics lower through `BackendHelperCallOp` to a `BackendHelper` whose
`IntrinsicHelperSource` preserves the exact intrinsic leaf and signature; argument arity remains the ordered
`many BackendValue` sequence and is never recovered from a helper name. View, slice, and byte-span
construction/extraction are closed nested payload sums. Backend labels are preallocated in
`BackendIdentityProjection`, so cyclic control is constructible before any `BackendBlock` content.

### 9.3 Emitter and artifact C28

```text
sum CEmitter = GnuCEmitter
record CSerializationInput { backend:ref PhysicalBackendSpine, target:ref CompilerBase.TargetSpec, capability:ref CompilerBase.GnuCEmitterCapability }
record CSerializationFinalizationInput { input:ref CSerializationInput, texts:many CEntityText }
record CEntityText { subject:BackendValidationSubject, text:str }
record CArtifact { backend:ref PhysicalBackendSpine, target:ref CompilerBase.TargetSpec, source:str, header:str, symbols:many CArtifactSymbol }
record CArtifactSymbol { key:CompilerBase.SymbolKey, entity:BackendSymbolEntity }
sum BackendSymbolEntity = FunctionSymbolEntity { function:ref BackendFunctionIdentity } | ExternSymbolEntity { extern:ref BackendExternIdentity } | GlobalSymbolEntity { global:ref BackendGlobalIdentity } | DataSymbolEntity { data:ref BackendDataIdentity }
```

---

## 10. CompilerHost — C29 host boundary

Host handles remain private implementation resources. No process handle, FFI cdata, loader handle, or userdata
enters ASDL.

```text
record HostCookPolicy { compiler_path:CompilerBase.PathValue, output_directory:CompilerBase.PathValue, optimization_level:HostOptimizationLevel }
sum HostOptimizationLevel = HostO0 | HostO1 | HostO2 | HostO3
entity GccCookRequest { artifact:ref CompilerBackend.CArtifact, policy:HostCookPolicy }
entity LiveGccSession { artifact:ref CompilerBackend.CArtifact, library_path:CompilerBase.PathValue }
entity ReleasedGccSession { artifact:ref CompilerBackend.CArtifact, library_path:CompilerBase.PathValue }
value FfiTypeSpec { declaration:str }
record SymbolRequest { session:ref LiveGccSession, abi:ref CompilerSourceFact.CallableAbiEntry, key:CompilerBase.SymbolKey, ffi_type:ref FfiTypeSpec }
record SymbolCapability { session:ref LiveGccSession, abi:ref CompilerSourceFact.CallableAbiEntry, key:CompilerBase.SymbolKey, ffi_type:ref FfiTypeSpec }
```

`LiveGccSession` identity is the resource-liveness token. Its runtime handle is private to A33 and is
unreachable from pure compiler methods.

---

## 11. Narrow request schema A01–A33 / B01–B61

Requests are immutable operation receivers. Every field is in that operation's exact invalidation frontier.
A leaf never carries a nullable selector for another operation. A01–A17 request/input declarations live in
`CompilerSource`, except `ScalarCodeOperationSubject`, `AtomicCodeOperationSubject`,
`CodeOperationAttributionRequest`, `StorageOwnershipRequest`, and `StorageOwnershipInput`, which live in
`CompilerAnalysis`. A18–A20 live in `CompilerCode`; A21–A24 live in `CompilerAnalysis`; A25–A30 live in
`CompilerLower`; A31–A32 live in `CompilerBackend`; A33 lives in `CompilerHost`.

A `many ref` field in a request contains only the exact entries cited by that subject's derivation, never
the owning facet's complete population. Passing unrelated entries is an authority-specific provenance
rejection. The field is a typed proof-premise sequence, not a copied fact bag or lookup index.

### 11.1 A01–A17 requests

```text
sum ResolutionInput = PermitLexicalShadowing | RejectLexicalShadowing
record ResolutionFinalizationInput { policy:ResolutionInput, occupancies:many CompilerSourceFact.NamespaceOccupancyEntry, references:many CompilerSourceFact.ResolvedReferenceEntry }

record NominalMeaningInput { program:ref CompilerSource.SemanticProgramSpine, resolution:many ref CompilerSourceFact.ResolvedReferenceEntry }
sum NominalSubject = NominalDeclarationSubject { declaration:CompilerSource.NominalDeclaration } | NominalChildSubject { child:CompilerSource.NominalChild }
record TypeMeaningInput { program:ref CompilerSource.SemanticProgramSpine, resolution:many ref CompilerSourceFact.ResolvedReferenceEntry, nominal:many ref CompilerSourceFact.NominalDeclarationMeaningEntry, children:many ref CompilerSourceFact.NominalChildMeaningEntry }
record IntrinsicInterpretationInput { operand_types:many CompilerSource.CanonicalType, result_type:ref CompilerSource.CanonicalType, contracts:many DeclaredScalarContract }
sum ScalarCodeOperationSubject = UnaryCodeOperationSubject { operation:ref CompilerCode.UnaryInstruction } | BinaryCodeOperationSubject { operation:ref CompilerCode.BinaryInstruction } | FloatBinaryCodeOperationSubject { operation:ref CompilerCode.FloatBinaryInstruction } | CompareCodeOperationSubject { operation:ref CompilerCode.CompareInstruction } | CastCodeOperationSubject { operation:ref CompilerCode.CastInstruction } | VoidIntrinsicCodeOperationSubject { operation:ref CompilerCode.VoidIntrinsicInstruction } | ValueIntrinsicCodeOperationSubject { operation:ref CompilerCode.ValueIntrinsicInstruction }
sum AtomicCodeOperationSubject = AtomicLoadCodeOperationSubject { operation:ref CompilerCode.AtomicLoadInstruction } | AtomicStoreCodeOperationSubject { operation:ref CompilerCode.AtomicStoreInstruction } | AtomicRmwCodeOperationSubject { operation:ref CompilerCode.AtomicRmwInstruction } | AtomicCompareExchangeCodeOperationSubject { operation:ref CompilerCode.AtomicCompareExchangeInstruction } | AtomicFenceCodeOperationSubject { operation:ref CompilerCode.AtomicFenceInstruction }
sum CodeOperationAttributionRequest = ScalarCodeAttributionRequest { code:ref CompilerCode.MonomorphicCodeSpine, subject:ScalarCodeOperationSubject, type_meaning:many ref CompilerSourceFact.TypeMeaningEntry, intrinsic:ref CompilerSource.IntrinsicMeaning } | SelectCodeAttributionRequest { code:ref CompilerCode.MonomorphicCodeSpine, operation:ref CompilerCode.SelectInstruction, result_type:ref CompilerSource.CanonicalType } | AddressCodeAttributionRequest { code:ref CompilerCode.MonomorphicCodeSpine, operation:ref CompilerCode.AddressOfInstruction, result_type:ref CompilerSource.CanonicalType } | GlobalReferenceCodeAttributionRequest { code:ref CompilerCode.MonomorphicCodeSpine, operation:ref CompilerCode.GlobalReferenceInstruction, result_type:ref CompilerSource.CanonicalType } | PointerOffsetCodeAttributionRequest { code:ref CompilerCode.MonomorphicCodeSpine, operation:ref CompilerCode.PointerOffsetInstruction, pointer_type:ref CompilerSource.CanonicalType, index_type:ref CompilerSource.CanonicalType, result_type:ref CompilerSource.CanonicalType } | LoadCodeAttributionRequest { code:ref CompilerCode.MonomorphicCodeSpine, operation:ref CompilerCode.LoadInstruction, value_type:ref CompilerSource.CanonicalType, volatility:CompilerSource.OperationVolatility } | StoreCodeAttributionRequest { code:ref CompilerCode.MonomorphicCodeSpine, operation:ref CompilerCode.StoreInstruction, value_type:ref CompilerSource.CanonicalType, volatility:CompilerSource.OperationVolatility } | AtomicCodeAttributionRequest { code:ref CompilerCode.MonomorphicCodeSpine, subject:AtomicCodeOperationSubject, value_type:ref CompilerSource.CanonicalType, intrinsic:ref CompilerSource.IntrinsicMeaning }
record IntrinsicMeaning { operation:CompilerSource.ScalarOperation, operand_types:many CompilerSource.CanonicalType, result_type:ref CompilerSource.CanonicalType, overflow:OverflowMeaning, trap:TrapContract, float:FloatContract }

sum CheckRequest = ExpressionCheckRequest { program:ref CompilerSource.SemanticProgramSpine, expression:ref CompilerSource.Expression, input:ExpressionCheckInput } | PlaceCheckRequest { program:ref CompilerSource.SemanticProgramSpine, place:ref CompilerSource.Place, input:PlaceCheckInput } | StatementCheckRequest { program:ref CompilerSource.SemanticProgramSpine, statement:ref CompilerSource.Statement, input:StatementCheckInput }
record ExpressionCheckInput { resolution:many ref CompilerSourceFact.ResolvedReferenceEntry, nominal:many ref CompilerSourceFact.NominalDeclarationMeaningEntry, children:many ref CompilerSourceFact.NominalChildMeaningEntry, types:many ref CompilerSourceFact.TypeMeaningEntry, expectation:TypeExpectation, control:ControlCapability, ownership:OwnershipCapability, region:RegionCapability }
record PlaceCheckInput { resolution:many ref CompilerSourceFact.ResolvedReferenceEntry, nominal:many ref CompilerSourceFact.NominalDeclarationMeaningEntry, children:many ref CompilerSourceFact.NominalChildMeaningEntry, types:many ref CompilerSourceFact.TypeMeaningEntry, access:CompilerSourceFact.PlaceAccessMeaning, control:ControlCapability, ownership:OwnershipCapability }
record StatementCheckInput { resolution:many ref CompilerSourceFact.ResolvedReferenceEntry, nominal:many ref CompilerSourceFact.NominalDeclarationMeaningEntry, children:many ref CompilerSourceFact.NominalChildMeaningEntry, types:many ref CompilerSourceFact.TypeMeaningEntry, control:ControlCapability, ownership:OwnershipCapability, region:RegionCapability }
sum TypeExpectation = NoTypeExpectation | ExactTypeExpectation { type_value:ref CompilerSource.CanonicalType }
sum ControlCapability = FunctionControlCapability { function:ref CompilerSource.FunctionDeclaration } | RegionControlCapability { region:ref CompilerSource.RegionDeclaration } | BlockControlCapability { block:CompilerSource.ControlBlockRef }
sum OwnershipCapability = NoOwnershipRole | OwnershipRoleCapability { type_value:ref CompilerSource.CanonicalType, role:OwnershipCheckRole }
sum OwnershipCheckRole = CopyUseRole | MoveUseRole | BorrowUseRole | MutateUseRole | DropUseRole | HandleCrossingRole
sum RegionCapability = NoRegionCapability | OpenRegionCapability { region:ref CompilerSource.RegionDeclaration } | SealedRegionCapability { region:ref CompilerSource.RegionDeclaration }

record ControlLegalityInput { checked:many ref CompilerSourceFact.CheckedMeaningEntry, signatures:many ControlSignatureEntry, protocols:many CompilerSource.RegionProtocol }
record ControlSignatureEntry { block:CompilerSource.ControlBlockRef, parameters:many CompilerSource.ParameterDeclaration }
record ContractMeaningInput { resolution:many ref CompilerSourceFact.ResolvedReferenceEntry, types:many ref CompilerSourceFact.TypeMeaningEntry, checked:many ref CompilerSourceFact.CheckedMeaningEntry }

sum StaticOwnershipRequest = StaticBindingUse { program:ref CompilerSource.SemanticProgramSpine, binding:ref CompilerSource.BindingOccurrence, use:CompilerSource.SemanticOccurrence, input:StaticOwnershipInput } | StaticTransfer { program:ref CompilerSource.SemanticProgramSpine, transfer:CompilerSource.ControlTransfer, input:StaticOwnershipInput } | StaticCallRetention { program:ref CompilerSource.SemanticProgramSpine, call:ref CompilerSource.CallExpression, input:StaticOwnershipInput } | StaticControlTransition { program:ref CompilerSource.SemanticProgramSpine, control:CompilerSource.ControlSite, input:StaticOwnershipInput } | StaticHandleCrossing { program:ref CompilerSource.SemanticProgramSpine, expression:ref CompilerSource.Expression, handle:ref CompilerSource.HandleDeclaration, domain:ref CompilerSource.TypeForm, input:StaticOwnershipInput } | StaticResolverGrant { program:ref CompilerSource.SemanticProgramSpine, subject:CompilerSource.SemanticOccurrence, handle:ref CompilerSource.HandleDeclaration, domain:ref CompilerSource.TypeForm, input:StaticOwnershipInput } | StaticUniqueCopyEquality { program:ref CompilerSource.SemanticProgramSpine, subject:CompilerSource.SemanticOccurrence, input:StaticOwnershipInput } | StaticErasure { program:ref CompilerSource.SemanticProgramSpine, subject:CompilerSource.SemanticOccurrence, input:StaticOwnershipInput }
record StaticOwnershipInput { nominal:many ref CompilerSourceFact.NominalDeclarationMeaningEntry, children:many ref CompilerSourceFact.NominalChildMeaningEntry, checked:many ref CompilerSourceFact.CheckedMeaningEntry, control:many ref CompilerSourceFact.ControlMeaningEntry, contracts:many ref CompilerSourceFact.ContractEvidenceEntry, captures:many ref CompilerSourceFact.CaptureEntry, layout:many ref CompilerSourceFact.LayoutEntry, declared_effects:many CompilerSource.DeclaredCallableEffect }
sum StorageOwnershipRequest = StorageObjectUse { memory:ref CompilerAnalysis.MemorySpine, object:ref CompilerAnalysis.MemoryObjectOccurrence, use:CompilerSource.SemanticOccurrence, input:StorageOwnershipInput } | StorageLeaseOriginRequest { memory:ref CompilerAnalysis.MemorySpine, object:ref CompilerAnalysis.MemoryObjectOccurrence, input:StorageOwnershipInput } | StorageInvalidation { memory:ref CompilerAnalysis.MemorySpine, object:ref CompilerAnalysis.MemoryObjectOccurrence, effect:ref CompilerAnalysis.OperationEffectEntry, input:StorageOwnershipInput } | StorageDischarge { memory:ref CompilerAnalysis.MemorySpine, object:ref CompilerAnalysis.MemoryObjectOccurrence, subject:CompilerSource.SemanticOccurrence, input:StorageOwnershipInput } | StorageEscape { memory:ref CompilerAnalysis.MemorySpine, object:ref CompilerAnalysis.MemoryObjectOccurrence, call:ref CompilerCode.CallInstruction, input:StorageOwnershipInput }
record StorageOwnershipInput { static:many ref CompilerSourceFact.StaticOwnershipEntry, objects:many ref CompilerAnalysis.MemoryObjectEntry, accesses:many ref CompilerAnalysis.MemoryAccessEntry, relations:many ref CompilerAnalysis.MemoryRelationEntry, contracts:many ref CompilerAnalysis.ContractRealizationEntry, operation_effects:many ref CompilerAnalysis.OperationEffectEntry, callable_effects:many ref CompilerAnalysis.CallableEffectEntry }

record ConstantEvaluationInput { types:many ref CompilerSourceFact.TypeMeaningEntry, checked:many ref CompilerSourceFact.CheckedMeaningEntry, scalar:many ref IntrinsicMeaning, referenced:many ref CompilerSourceFact.ConstantValueEntry }
sum CaptureDiscoveryRequest = NestedFunctionOccurrence { program:ref CompilerSource.SemanticProgramSpine, function:ref CompilerSource.FunctionDeclaration, resolution:many ref CompilerSourceFact.ResolvedReferenceEntry, checked:many ref CompilerSourceFact.CheckedMeaningEntry } | ClosureExpressionOccurrence { program:ref CompilerSource.SemanticProgramSpine, closure:ref CompilerSource.ClosureExpression, resolution:many ref CompilerSourceFact.ResolvedReferenceEntry, checked:many ref CompilerSourceFact.CheckedMeaningEntry }

sum LayoutRequest = ScalarLayoutRequest { program:ref CompilerSource.SemanticProgramSpine, type_value:ref CompilerSource.CanonicalType, input:LayoutInput } | PointerLayoutRequest { program:ref CompilerSource.SemanticProgramSpine, type_value:ref CompilerSource.CanonicalType, input:LayoutInput } | ArrayLayoutRequest { program:ref CompilerSource.SemanticProgramSpine, type_value:ref CompilerSource.CanonicalType, input:LayoutInput } | SliceLayoutRequest { program:ref CompilerSource.SemanticProgramSpine, type_value:ref CompilerSource.CanonicalType, input:LayoutInput } | ViewLayoutRequest { program:ref CompilerSource.SemanticProgramSpine, type_value:ref CompilerSource.CanonicalType, input:LayoutInput } | LeaseLayoutRequest { program:ref CompilerSource.SemanticProgramSpine, type_value:ref CompilerSource.CanonicalType, input:LayoutInput } | OwnedLayoutRequest { program:ref CompilerSource.SemanticProgramSpine, type_value:ref CompilerSource.CanonicalType, input:LayoutInput } | AccessLayoutRequest { program:ref CompilerSource.SemanticProgramSpine, type_value:ref CompilerSource.CanonicalType, input:LayoutInput } | HandleLayoutRequest { program:ref CompilerSource.SemanticProgramSpine, type_value:ref CompilerSource.CanonicalType, input:LayoutInput } | ClosureLayoutRequest { program:ref CompilerSource.SemanticProgramSpine, type_value:ref CompilerSource.CanonicalType, input:LayoutInput } | StructLayoutRequest { program:ref CompilerSource.SemanticProgramSpine, declaration:ref CompilerSource.StructDeclaration, input:LayoutInput } | UniqueLayoutRequest { program:ref CompilerSource.SemanticProgramSpine, declaration:ref CompilerSource.UniqueStructDeclaration, input:LayoutInput } | UnionLayoutRequest { program:ref CompilerSource.SemanticProgramSpine, declaration:ref CompilerSource.UnionDeclaration, input:LayoutInput } | ImportedCLayoutRequest { program:ref CompilerSource.SemanticProgramSpine, type_value:ref CompilerSource.CanonicalType, input:LayoutInput }
record LayoutInput { nominal:many ref CompilerSourceFact.NominalDeclarationMeaningEntry, children:many ref CompilerSourceFact.NominalChildMeaningEntry, types:many ref CompilerSourceFact.TypeMeaningEntry, target:ref CompilerBase.TargetSpec, policy:CompilerBase.LayoutPolicy }

sum CallableAbiRequest = InternalFunctionAbiRequest { callable:ref CompilerSource.FunctionDeclaration, input:CallableAbiInput } | ExportFunctionAbiRequest { callable:ref CompilerSource.FunctionDeclaration, input:CallableAbiInput } | ExternFunctionAbiRequest { callable:ref CompilerSource.ExternDeclaration, input:CallableAbiInput } | SealedRegionAbiRequest { callable:ref CompilerSource.RegionDeclaration, input:CallableAbiInput } | ClosureAbiRequest { callable:ref CompilerSource.ClosureExpression, input:CallableAbiInput } | ImportedFunctionPointerAbiRequest { callable:ref CompilerSource.ImportedCFunctionPointerType, input:CallableAbiInput }
record CallableAbiInput { types:many ref CompilerSourceFact.TypeMeaningEntry, ownership:many ref CompilerSourceFact.StaticOwnershipEntry, layout:many ref CompilerSourceFact.LayoutEntry, target:ref CompilerBase.TargetSpec, convention:CompilerBase.CCallingConvention, linkage:DeclaredLinkage, visibility:Visibility }

sum ClosureRepresentationRequest = CapturedClosureRepresentationRequest { program:ref CompilerSource.SemanticProgramSpine, closure:ref CompilerSource.ClosureExpression, captures:many ref CompilerSourceFact.CaptureEntry, ownership:many ref CompilerSourceFact.StaticOwnershipEntry, layout:many ref CompilerSourceFact.LayoutEntry, abi:ref CompilerSourceFact.CallableAbiEntry, target:ref CompilerBase.TargetSpec } | NoCaptureRepresentationRequest { program:ref CompilerSource.SemanticProgramSpine, closure:ref CompilerSource.ClosureExpression }
record OpenRegionInvocation { program:ref CompilerSource.SemanticProgramSpine, invocation:ref CompilerSource.OpenEmitStatement, definition:ref CompilerSource.RegionDeclaration, checked:many ref CompilerSourceFact.CheckedMeaningEntry, control:many ref CompilerSourceFact.ControlMeaningEntry, environment:OpenRegionEnvironment, caller_captures:many ref CompilerSourceFact.CaptureEntry }
record OpenRegionEnvironment { bindings:many OpenRegionBinding }
record OpenRegionBinding { formal:ref CompilerSource.ParameterDeclaration, actual:ref CompilerSource.Expression }
sum SealedRegionRequest = SealMaterializationRequest { program:ref CompilerSource.SemanticProgramSpine, seal:ref CompilerSource.RegionDeclaration, checked:many ref CompilerSourceFact.CheckedMeaningEntry, control:many ref CompilerSourceFact.ControlMeaningEntry, abi:ref CompilerSourceFact.CallableAbiEntry } | SealedCallRoutingRequest { program:ref CompilerSource.SemanticProgramSpine, invocation:ref CompilerSource.SealedCallStatement, seal:ref CompilerSource.RegionDeclaration, materialization:ref CompilerSourceFact.SealMaterializationMeaning, caller:CompilerSource.ControlBlockRef }
```

### 11.2 A18–A24 requests

```text
record CodeConstructionRequest { program:ref CompilerSource.SemanticProgramSpine, resolution:ref CompilerSourceFact.ResolutionFacet, nominal_declarations:many ref CompilerSourceFact.NominalDeclarationMeaningEntry, nominal_children:many ref CompilerSourceFact.NominalChildMeaningEntry, types:many ref CompilerSourceFact.TypeMeaningEntry, checked:many ref CompilerSourceFact.CheckedMeaningEntry, control:many ref CompilerSourceFact.ControlMeaningEntry, contracts:many ref CompilerSourceFact.ContractEvidenceEntry, ownership:many ref CompilerSourceFact.StaticOwnershipEntry, constants:many ref CompilerSourceFact.ConstantValueEntry, layout:many ref CompilerSourceFact.LayoutEntry, abi:many ref CompilerSourceFact.CallableAbiEntry, closure:many ref CompilerSourceFact.ClosureRepresentationEntry, sealed:many ref CompilerSourceFact.SealedRegionEntry }
record CodeLeafConstructionInput { request:ref CodeConstructionRequest, identities:ref CompilerCode.CodeIdentityProjection }
record CodeConstructionFinalizationInput { identities:ref CompilerCode.CodeIdentityProjection, contributions:many CompilerCode.CodeConstructionContribution }
record CodeValidationRequest { code:ref CompilerCode.MonomorphicCodeSpine }
record CodeValidationFinalizationInput { accepted:many CompilerCode.CodeValidationSubject, topology:ref TopologyDerivationInput }
record LoopMeaningRequest { topology:ref CompilerCode.ControlTopologySpine, loop:ref CompilerCode.NaturalLoopOccurrence, definitions:many ref CompilerCode.DefinitionEntry, edge_arguments:many ref CompilerCode.EdgeArgumentEntry, constants:many CompilerCode.CodeConstant, scalar:many ref CompilerAnalysis.ScalarAttributionEntry, source:ref CompilerSource.SemanticProgramSpine }
record InductionRelationRequest { topology:ref CompilerCode.ControlTopologySpine, loop:ref CompilerCode.NaturalLoopOccurrence, flow:ref CompilerAnalysis.LoopFlowEntry, scalar:many ref CompilerAnalysis.ScalarAttributionEntry }
record CodeValueAlgebraRequest { code:ref CompilerCode.MonomorphicCodeSpine, topology:ref CompilerCode.ControlTopologySpine, value:CompilerCode.CodeValue, scalar:many ref CompilerAnalysis.ScalarAttributionEntry, flow:many ref CompilerAnalysis.LoopFlowEntry, induction:many ref CompilerAnalysis.InductionEntry }
record CodeValueAlgebraSubject { value:CompilerCode.CodeValue, ordinal:CompilerBase.Ordinal }
record CodeValueAlgebraPopulation { code:ref CompilerCode.MonomorphicCodeSpine, subjects:many CodeValueAlgebraSubject }
record LoopValueSubject { loop:ref CompilerCode.NaturalLoopOccurrence, value:CompilerCode.CodeValue, role:LoopValueRole }
sum LoopValueRole = AccumulatorRole | ScanRole | RecurrenceRole | DerivedIndexRole
record LoopAlgebraRequest { topology:ref CompilerCode.ControlTopologySpine, subject:LoopValueSubject, values:many ref CompilerAnalysis.ValueAlgebraEntry, scalar:many ref CompilerAnalysis.ScalarAttributionEntry, flow:many ref CompilerAnalysis.LoopFlowEntry, induction:many ref CompilerAnalysis.InductionEntry }

record MemorySpineRequest { code:ref CompilerCode.MonomorphicCodeSpine, topology:ref CompilerCode.ControlTopologySpine }
record MemoryObjectMeaningRequest { memory:ref CompilerAnalysis.MemorySpine, object:ref CompilerAnalysis.MemoryObjectOccurrence, types:many ref CompilerSourceFact.TypeMeaningEntry, layout:many ref CompilerSourceFact.LayoutEntry, ownership:many ref CompilerSourceFact.StaticOwnershipEntry, flow:many ref CompilerAnalysis.LoopFlowEntry, induction:many ref CompilerAnalysis.InductionEntry, values:many ref CompilerAnalysis.ValueAlgebraEntry }
record MemoryContractRealizationRequest { memory:ref CompilerAnalysis.MemorySpine, evidence:ref CompilerSourceFact.ContractEvidenceEntry, objects:many ref CompilerAnalysis.MemoryObjectEntry }
record MemoryAccessMeaningRequest { memory:ref CompilerAnalysis.MemorySpine, access:ref CompilerAnalysis.MemoryAccessOccurrence, objects:many ref CompilerAnalysis.MemoryObjectEntry, contracts:many ref CompilerAnalysis.ContractRealizationEntry, flow:many ref CompilerAnalysis.LoopFlowEntry, induction:many ref CompilerAnalysis.InductionEntry, values:many ref CompilerAnalysis.ValueAlgebraEntry, layout:many ref CompilerSourceFact.LayoutEntry, ownership:many ref CompilerSourceFact.StaticOwnershipEntry }
record MemoryRelationPopulationRequest { memory:ref CompilerAnalysis.MemorySpine, objects:many ref CompilerAnalysis.MemoryObjectEntry, accesses:many ref CompilerAnalysis.MemoryAccessEntry, contracts:many ref CompilerAnalysis.ContractRealizationEntry, flow:many ref CompilerAnalysis.LoopFlowEntry, induction:many ref CompilerAnalysis.InductionEntry, declared:many ref CompilerSourceFact.ContractEvidenceEntry, layout:many ref CompilerSourceFact.LayoutEntry, ownership:many ref CompilerSourceFact.StaticOwnershipEntry }
record MemoryRelationRequest { memory:ref CompilerAnalysis.MemorySpine, left:MemoryRelationEndpoint, right:MemoryRelationEndpoint, objects:many ref CompilerAnalysis.MemoryObjectEntry, accesses:many ref CompilerAnalysis.MemoryAccessEntry, contracts:many ref CompilerAnalysis.ContractRealizationEntry, flow:many ref CompilerAnalysis.LoopFlowEntry, induction:many ref CompilerAnalysis.InductionEntry, declared:many ref CompilerSourceFact.ContractEvidenceEntry, layout:many ref CompilerSourceFact.LayoutEntry, ownership:many ref CompilerSourceFact.StaticOwnershipEntry }
record MemoryRelationSubject { ordinal:CompilerBase.Ordinal, request:ref MemoryRelationRequest }
record MemoryRelationPopulation { memory:ref CompilerAnalysis.MemorySpine, subjects:many MemoryRelationSubject }
sum MemoryRelationEndpoint = ObjectRelationEndpoint { object:ref CompilerAnalysis.MemoryObjectOccurrence } | AccessRelationEndpoint { access:ref CompilerAnalysis.MemoryAccessOccurrence }

record EffectAccessEvidence { operation:ref CompilerAnalysis.MemoryAccessOperationMeaning, safety:ref CompilerAnalysis.MemoryAccessSafetyMeaning }
record OperationEffectRequest { code:ref CompilerCode.MonomorphicCodeSpine, operation:CompilerAnalysis.OperationOccurrence, contracts:many ref CompilerSourceFact.ContractEvidenceEntry, accesses:many EffectAccessEvidence, mappings:many ref CompilerAnalysis.ContractRealizationEntry, declarations:many CompilerSource.DeclaredEffectAtom }
record AcyclicCallableEffectRequest { code:ref CompilerCode.MonomorphicCodeSpine, callable:CompilerAnalysis.CallableSummarySubject, operation_effects:many ref CompilerAnalysis.OperationEffectEntry, callees:many ref CompilerAnalysis.CallableEffectEntry }
record RecursiveCallableComponentEffectRequest { code:ref CompilerCode.MonomorphicCodeSpine, component:CallableComponent, operation_effects:many ref CompilerAnalysis.OperationEffectEntry, external_callees:many ref CompilerAnalysis.CallableEffectEntry }
record CallableComponent { callables:many CompilerAnalysis.CallableSummarySubject, edges:many CallableComponentEdge }
record CallableComponentEdge { caller:CompilerAnalysis.CallableSummarySubject, callee:CompilerAnalysis.CallableSummarySubject }
```

### 11.3 A25–A33 requests

```text
record LoopKernelCandidateRequest { topology:ref CompilerCode.ControlTopologySpine, loop:ref CompilerCode.NaturalLoopOccurrence, scalar:many ref CompilerAnalysis.ScalarAttributionEntry, values:many ref CompilerAnalysis.ValueAlgebraEntry, effects:many ref CompilerAnalysis.OperationEffectEntry, callable_effects:many ref CompilerAnalysis.CallableEffectEntry, flow:many ref CompilerAnalysis.LoopFlowEntry, induction:many ref CompilerAnalysis.InductionEntry, algebra:many ref CompilerAnalysis.LoopAlgebraEntry, objects:many ref CompilerAnalysis.MemoryObjectEntry, accesses:many ref CompilerAnalysis.MemoryAccessEntry, relations:many ref CompilerAnalysis.MemoryRelationEntry, contracts:many ref CompilerAnalysis.ContractRealizationEntry }
record ScheduleSelectionRequest { kernels:ref CompilerLower.KernelSpine, kernel:ref CompilerLower.KernelOccurrence, meaning:ref CompilerLower.KernelMeaningEntry, accesses:many ref CompilerAnalysis.MemoryAccessEntry, relations:many ref CompilerAnalysis.MemoryRelationEntry, effects:many ref CompilerAnalysis.OperationEffectEntry, callable_effects:many ref CompilerAnalysis.CallableEffectEntry, policy:ref CompilerBase.CompilerPolicy, target:ref CompilerBase.TargetSpec, capability:ref CompilerBase.GnuCEmitterCapability }
record FusedProjectionRequest { kernels:ref CompilerLower.KernelSpine, kernel:ref CompilerLower.KernelOccurrence, meaning:ref CompilerLower.KernelMeaningEntry, schedule:ref CompilerLower.ScheduleEntry, flow:many ref CompilerAnalysis.LoopFlowEntry, algebra:many ref CompilerAnalysis.LoopAlgebraEntry, objects:many ref CompilerAnalysis.MemoryObjectEntry, accesses:many ref CompilerAnalysis.MemoryAccessEntry, relations:many ref CompilerAnalysis.MemoryRelationEntry, contracts:many ref CompilerAnalysis.ContractRealizationEntry, effects:many ref CompilerAnalysis.OperationEffectEntry, callable_effects:many ref CompilerAnalysis.CallableEffectEntry, policy:ref CompilerBase.CompilerPolicy }

record UsePopulationCandidateRequest { fused:ref CompilerLower.FusedComputationSpine, computation:ref CompilerLower.FusedComputationOccurrence, meaning:many ref CompilerLower.FusedMeaningEntry }
record UseMeaningCandidateRequest { population:ref CompilerLower.UsePopulationCandidateRecord, fused_meaning:many ref CompilerLower.FusedMeaningEntry, accesses:many ref CompilerAnalysis.MemoryAccessEntry }
record CoordinateCandidateRequest { meaning:ref CompilerLower.UseMeaningCandidateRecord, flow:many ref CompilerAnalysis.LoopFlowEntry, induction:many ref CompilerAnalysis.InductionEntry, objects:many ref CompilerAnalysis.MemoryObjectEntry, accesses:many ref CompilerAnalysis.MemoryAccessEntry, layout:many ref CompilerSourceFact.LayoutEntry, schedule:ref CompilerLower.ScheduleEntry, target:ref CompilerBase.TargetSpec }
record UseSpineAdmissionRequest { population:ref CompilerLower.UsePopulationCandidateRecord, meaning:ref CompilerLower.UseMeaningCandidateRecord, coordinates:ref CompilerLower.CoordinateCandidateRecord }
record UseMeaningPublicationRequest { uses:ref CompilerLower.MaterializedUseSpine, candidate:ref CompilerLower.UseMeaningCandidateRecord }
record CoordinatePublicationRequest { uses:ref CompilerLower.MaterializedUseSpine, candidate:ref CompilerLower.CoordinateCandidateRecord }
record PointerQualificationRequest { uses:ref CompilerLower.MaterializedUseSpine, meaning:many ref CompilerLower.MaterializedUseEntry, declared:many ref CompilerSourceFact.ContractEvidenceEntry, relations:many ref CompilerAnalysis.MemoryRelationEntry, mappings:many ref CompilerAnalysis.ContractRealizationEntry, target:ref CompilerBase.TargetSpec, requirement:QualificationRequirement }
sum QualificationRequirement = OptionalQualification | RequiredQualification
record AddressRecordRequest { uses:ref CompilerLower.MaterializedUseSpine, use:ref CompilerLower.MaterializedUseOccurrence, coordinate:ref CompilerLower.CoordinateEntry, target:ref CompilerBase.TargetSpec, environment:ref CompilerLower.RealizationEnvironment }

record BaselineAdmissionRequest { code:ref CompilerCode.MonomorphicCodeSpine, topology:ref CompilerCode.ControlTopologySpine, capability:ref CompilerBase.GnuCEmitterCapability }
record SubjectCommitmentRequest { subject:CompilerAnalysis.OptimizationSubject, baseline:ref CompilerAnalysis.BaselineEntry, candidates:many StrategyCandidate, rejected:many CompilerAnalysis.RejectedAlternative }
sum StrategyCandidate = ClosedFormStrategyCandidate { algebra:ref CompilerAnalysis.LoopAlgebraEntry } | FusedStrategyCandidate { kernel:ref CompilerLower.KernelOccurrence, meaning:ref CompilerLower.KernelMeaningEntry, schedule:ref CompilerLower.ScheduleEntry, fused:ref CompilerLower.FusedComputationSpine, fused_meaning:many ref CompilerLower.FusedMeaningEntry }
sum QualificationRealizationFailure = RequiredQualificationFailure { reason:CompilerLower.QualificationUnavailableReason } | PointerRepresentationFailure { reason:CompilerLower.PointerRepresentationReason }
sum StrategyResumeRequest = ResumeAfterUseFailure { attempt:ref CompilerAnalysis.FusedAttempt, baseline:ref CompilerAnalysis.BaselineEntry, reason:CompilerLower.UsePopulationUnrealizableReason, remaining:many StrategyCandidate, rejected:many CompilerAnalysis.RejectedAlternative } | ResumeAfterCoordinateFailure { attempt:ref CompilerAnalysis.FusedAttempt, baseline:ref CompilerAnalysis.BaselineEntry, reason:CompilerLower.CoordinateUnrealizableReason, remaining:many StrategyCandidate, rejected:many CompilerAnalysis.RejectedAlternative } | ResumeAfterQualificationFailure { attempt:ref CompilerAnalysis.FusedAttempt, baseline:ref CompilerAnalysis.BaselineEntry, failure:QualificationRealizationFailure, remaining:many StrategyCandidate, rejected:many CompilerAnalysis.RejectedAlternative } | ResumeAfterAddressFailure { attempt:ref CompilerAnalysis.FusedAttempt, baseline:ref CompilerAnalysis.BaselineEntry, reason:CompilerLower.AddressUnrealizableReason, remaining:many StrategyCandidate, rejected:many CompilerAnalysis.RejectedAlternative } | ResumeAfterFragmentFailure { attempt:CompilerAnalysis.LoweringAttempt, baseline:ref CompilerAnalysis.BaselineEntry, reason:CompilerLower.FragmentUnrealizableReason, remaining:many StrategyCandidate, rejected:many CompilerAnalysis.RejectedAlternative }
sum AlternativeRejectionRequest = RecordKernelAlternativeRejection { alternative:CompilerAnalysis.KernelPlanningAlternative, reason:CompilerLower.KernelNoPlanReason } | RecordScheduleAlternativeRejection { alternative:CompilerAnalysis.SchedulePlanningAlternative, reason:CompilerLower.ScheduleNoPlanReason } | RecordFusionAlternativeRejection { alternative:CompilerAnalysis.FusionPlanningAlternative, reason:CompilerLower.FusedUnavailableReason } | RecordUsePopulationAlternativeRejection { alternative:CompilerAnalysis.RealizationStrategyAlternative, reason:CompilerLower.UsePopulationUnrealizableReason } | RecordCoordinateAlternativeRejection { alternative:CompilerAnalysis.RealizationStrategyAlternative, reason:CompilerLower.CoordinateUnrealizableReason } | RecordQualificationAlternativeRejection { alternative:CompilerAnalysis.RealizationStrategyAlternative, reason:CompilerLower.QualificationUnavailableReason } | RecordPointerRepresentationAlternativeRejection { alternative:CompilerAnalysis.RealizationStrategyAlternative, reason:CompilerLower.PointerRepresentationReason } | RecordAddressAlternativeRejection { alternative:CompilerAnalysis.RealizationStrategyAlternative, reason:CompilerLower.AddressUnrealizableReason } | RecordFragmentAlternativeRejection { alternative:CompilerAnalysis.RealizationStrategyAlternative, reason:CompilerLower.FragmentUnrealizableReason }
record CommitRealizedFragmentRequest { subject:CompilerAnalysis.OptimizationSubject, baseline:ref CompilerAnalysis.BaselineEntry, contribution:ref CompilerLower.FragmentContribution, rejected:many CompilerAnalysis.RejectedAlternative }

record DominanceRequest { code:ref CompilerCode.MonomorphicCodeSpine, topology:ref CompilerCode.ControlTopologySpine }
sum FragmentContributionRequest = ClosedFormContributionRequest { attempt:CompilerAnalysis.ClosedFormAttempt, dominance:many ref CompilerAnalysis.DominanceEntry, algebra:ref CompilerAnalysis.LoopAlgebraEntry, baseline:ref CompilerAnalysis.BaselineEntry, target:ref CompilerBase.TargetSpec, environment:ref CompilerLower.RealizationEnvironment } | FusedContributionRequest { attempt:CompilerAnalysis.FusedAttempt, dominance:many ref CompilerAnalysis.DominanceEntry, fused:ref CompilerLower.FusedComputationSpine, meaning:many ref CompilerLower.FusedMeaningEntry, uses:ref CompilerLower.MaterializedUseSpine, use_meaning:many ref CompilerLower.MaterializedUseEntry, coordinates:many ref CompilerLower.CoordinateEntry, qualifications:many ref CompilerLower.PointerQualificationEntry, addresses:many CompilerLower.AddressRecord, baseline:ref CompilerAnalysis.BaselineEntry, target:ref CompilerBase.TargetSpec, environment:ref CompilerLower.RealizationEnvironment }

record BackendConstructionRequest { code:ref CompilerCode.MonomorphicCodeSpine, static_ownership:many ref CompilerSourceFact.StaticOwnershipEntry, storage_ownership:many ref CompilerAnalysis.StorageOwnershipEntry, layout:many ref CompilerSourceFact.LayoutEntry, abi:many ref CompilerSourceFact.CallableAbiEntry, scalar:many ref CompilerAnalysis.ScalarAttributionEntry, objects:many ref CompilerAnalysis.MemoryObjectEntry, accesses:many ref CompilerAnalysis.MemoryAccessEntry, effects:many ref CompilerAnalysis.OperationEffectEntry, baseline:ref CompilerAnalysis.BaselineFacet, commitment:many ref CompilerAnalysis.OptimizationCommitmentEntry, target:ref CompilerBase.TargetSpec }
record BackendConstructionFinalizationInput { identities:ref CompilerBackend.BackendIdentityProjection, contributions:many CompilerBackend.BackendConstructionContribution }
record BackendLeafConstructionInput { request:ref BackendConstructionRequest, identities:ref CompilerBackend.BackendIdentityProjection }
record EmitterCapabilityInput { target:ref CompilerBase.TargetSpec }
```

A33 uses `CompilerHost.GccCookRequest`, `CompilerHost.SymbolRequest`, `LiveGccSession`, and
`ReleasedGccSession` directly; there is no generic host operation record.

---

## 12. Durable boundary schema and deleted-result proof

No internal operation-result sum survives. Immediate alternatives are the peer named-exit
signatures in §14.

### 12.1 CompilerBoundary

```text
record TypedSemanticRejection { reason:SemanticRejectReason }
```

`SemanticRejectReason` is declared in §13 and assigned to `CompilerBoundary`. Each
authority reason sum provides a field-agnostic `to_semantic_rejection` method inherited
by its leaves; the method constructs the exact `SemanticRejectReason` wrapper and
`TypedSemanticRejection` without class inspection. The running host machine calls that
method and tail-calls its named `semantic_rejected(machine, rejection)` method. That
method is the sole consumer; the value never re-enters compiler semantics.
There is no generic success or host-failure envelope.

### 12.2 CompilerHost sealed outcomes

```text
sum GccCookResult = LiveGccSessionResult { session:ref CompilerHost.LiveGccSession } | GccCookFailed { failure:GccCookFailure }
sum SymbolResolutionResult = SymbolCapabilityResult { capability:ref CompilerHost.SymbolCapability } | SymbolResolutionFailed { failure:SymbolResolutionFailure }
record SessionReleased { session:ref CompilerHost.ReleasedGccSession }
record AlreadyReleased { session:ref CompilerHost.ReleasedGccSession }
record UseAfterReleaseFailed { failure:UseAfterReleaseFailure }
```

### 12.3 Exact deletion proof

Old §12 contained 59 sums and 11 records.

Sums:

- 55 internal operation-result sums are deleted;
- `NominalPublishedEntry` is deleted because B04 has distinct declaration and child
  publication continuations;
- `StrategyFailureReason` moves to `CompilerLower`;
- `GccCookResult` and `SymbolResolutionResult` remain in `CompilerHost`.

Records:

- `ClosurePublication`, `SealPublication`, `KernelPublication`, `FusedPublication`,
  `UseMeaningPublished`, `CoordinatesPublished`, `DominancePublished`, and
  `EmitterCapabilityPublished` are deleted;
- `SessionReleased`, `AlreadyReleased`, and `UseAfterReleaseFailed` remain sealed.

`CEntityValidationResult`, formerly declared outside old §12, is also deleted. The
schema-wide internal result-sum deletion count is 56. `CompilerResult` owns no
declaration and does not exist.

---

## 13. Authority site, reason, and host-failure schema

Every concrete reason leaf owns `render_reason`. Unless extra fields are shown, a leaf
carries exactly one typed `site` field. No reason string selects behavior.

The following ledger assigns every declaration in this section. It is part of the
normalized schema, not an implementation hint. Unqualified references in the compact
blocks resolve to the unique declaration named by this ledger before DSL
transcription.

| Declaration family | Namespace |
|---|---|
| A01–A05, A06 intrinsic, A07–A09, A10 static, A11–A17 sites and reasons | `CompilerSource` |
| A06 code, A10 storage, A21–A24 sites and reasons | `CompilerAnalysis` |
| A18–A20 sites and reasons | `CompilerCode` |
| A25–A30 sites and reasons, `BaselineFailureSubject`, `StrategyFailureReason` | `CompilerLower` |
| A31–A32 sites and reasons, `BackendConstructionSubject` | `CompilerBackend` |
| `OptionalRealizationReason` | `CompilerAnalysis` |
| `SemanticRejectReason` | `CompilerBoundary` |
| `GccCookFailure`, `SymbolResolutionFailure`, `UseAfterReleaseFailure` | `CompilerHost` |

### 13.1 Authority-specific sites

```text
record A01Site { input:ref CompilerSource.ProgramInput, origin:CompilerBase.Origin }
record A02Site { query:ref CompilerSource.MetaPropertyQuery, origin:CompilerBase.Origin }
record A03Site { program:ref CompilerSource.SemanticProgramSpine, input:ref ResolutionInput, subject:CompilerSource.SemanticOccurrence, origin:CompilerBase.Origin }
record A04Site { input:ref NominalMeaningInput, subject:NominalSubject, origin:CompilerBase.Origin }
record A05Site { input:ref TypeMeaningInput, subject:ref CompilerSource.TypeForm, origin:CompilerBase.Origin }
record A06IntrinsicSite { operation:CompilerSource.ScalarOperation, input:ref IntrinsicInterpretationInput, origin:CompilerBase.Origin }
record A06CodeSite { request:ref CodeOperationAttributionRequest, origin:CompilerBase.Origin }
record A07Site { request:ref CheckRequest, origin:CompilerBase.Origin }
record A08Site { subject:CompilerSource.ControlSite, input:ref ControlLegalityInput, origin:CompilerBase.Origin }
record A09Site { contract:ref CompilerSource.ContractForm, input:ref ContractMeaningInput, origin:CompilerBase.Origin }
record A10StaticSite { request:ref StaticOwnershipRequest, origin:CompilerBase.Origin }
record A10StorageSite { request:ref StorageOwnershipRequest, origin:CompilerBase.Origin }
record A11Site { expression:ref CompilerSource.Expression, input:ref ConstantEvaluationInput, origin:CompilerBase.Origin }
record A12Site { request:ref CaptureDiscoveryRequest, origin:CompilerBase.Origin }
record A13Site { request:ref LayoutRequest, origin:CompilerBase.Origin }
record A14Site { request:ref CallableAbiRequest, origin:CompilerBase.Origin }
record A15Site { request:ref ClosureRepresentationRequest, origin:CompilerBase.Origin }
record A16Site { request:ref OpenRegionInvocation, origin:CompilerBase.Origin }
record A17Site { request:ref SealedRegionRequest, origin:CompilerBase.Origin }
record A18Site { request:ref CodeConstructionRequest, subject:CompilerSource.SemanticOccurrence, origin:CompilerBase.Origin }
record A19Site { request:ref CodeValidationRequest, subject:CompilerCode.CodeOccurrence, origin:CompilerBase.Origin }
record A21FlowSite { request:ref LoopMeaningRequest, origin:CompilerBase.Origin }
record A21InductionSite { request:ref InductionRelationRequest, origin:CompilerBase.Origin }
record A22ValueSite { request:ref CodeValueAlgebraRequest, origin:CompilerBase.Origin }
record A22LoopSite { request:ref LoopAlgebraRequest, origin:CompilerBase.Origin }
record A23SpineSite { request:ref MemorySpineRequest, subject:CompilerCode.CodeOccurrence, origin:CompilerBase.Origin }
record A23ObjectSite { request:ref MemoryObjectMeaningRequest, origin:CompilerBase.Origin }
record A23ContractSite { request:ref MemoryContractRealizationRequest, origin:CompilerBase.Origin }
record A23AccessSite { request:ref MemoryAccessMeaningRequest, origin:CompilerBase.Origin }
record A23RelationSite { request:ref MemoryRelationRequest, origin:CompilerBase.Origin }
record A24OperationSite { request:ref OperationEffectRequest, origin:CompilerBase.Origin }
record A24CallableSite { request:ref AcyclicCallableEffectRequest, origin:CompilerBase.Origin }
record A24RecursiveSite { request:ref RecursiveCallableComponentEffectRequest, origin:CompilerBase.Origin }
record A25Site { request:ref LoopKernelCandidateRequest, origin:CompilerBase.Origin }
record A26Site { request:ref ScheduleSelectionRequest, origin:CompilerBase.Origin }
record A27Site { request:ref FusedProjectionRequest, origin:CompilerBase.Origin }
record A28PopulationSite { request:ref UsePopulationCandidateRequest, origin:CompilerBase.Origin }
record A28MeaningSite { request:ref UseMeaningCandidateRequest, origin:CompilerBase.Origin }
record A28CoordinateSite { request:ref CoordinateCandidateRequest, origin:CompilerBase.Origin }
record A28AdmissionSite { request:ref UseSpineAdmissionRequest, origin:CompilerBase.Origin }
record A28QualificationSite { request:ref PointerQualificationRequest, origin:CompilerBase.Origin }
record A28AddressSite { request:ref AddressRecordRequest, origin:CompilerBase.Origin }
sum BaselineFailureSubject = BaselineFunctionFailure { function:ref CompilerCode.CodeFunction } | BaselineOperationFailure { operation:CompilerAnalysis.OperationOccurrence }
record A29BaselineSite { request:ref BaselineAdmissionRequest, subject:BaselineFailureSubject, origin:CompilerBase.Origin }
record A29StrategySite { request:ref SubjectCommitmentRequest, origin:CompilerBase.Origin }
record A29ResumeSite { request:ref StrategyResumeRequest, origin:CompilerBase.Origin }
record A29CommitSite { request:ref CommitRealizedFragmentRequest, origin:CompilerBase.Origin }
record A30Site { request:ref FragmentContributionRequest, origin:CompilerBase.Origin }
sum BackendConstructionSubject = BackendTypeConstructionSubject { type_value:ref CompilerCode.CodeType } | BackendOperationConstructionSubject { operation:CompilerAnalysis.OperationOccurrence } | BackendStorageConstructionSubject { object:ref CompilerAnalysis.MemoryObjectOccurrence } | BackendInitializerConstructionSubject { initializer:CompilerCode.CodeInitializer } | BackendAbiConstructionSubject { abi:ref CompilerSourceFact.CallableAbiEntry } | BackendSymbolConstructionSubject { key:CompilerBase.SymbolKey } | BackendHelperConstructionSubject { source:CompilerBackend.BackendHelperSource } | BackendContributionConstructionSubject { contribution:ref CompilerLower.FragmentContribution } | BackendBlockParameterConstructionSubject { block:ref CompilerCode.CodeBlockIdentity, parameter:ref CompilerCode.CodeParameter }
record A31Site { request:ref BackendConstructionRequest, subject:BackendConstructionSubject, origin:CompilerBase.Origin }
record A32Site { input:ref CompilerBackend.CSerializationInput, subject:CompilerBackend.BackendOccurrence, origin:CompilerBase.Origin }
```

### 13.2 A01–A17 reason sums

```text
sum AuthoredMaterializationReason = LexicalDeliveryRejected { site:A01Site } | MalformedBracketEvaluation { site:A01Site } | IllegalDocumentRoot { site:A01Site } | MalformedDeclaration { site:A01Site } | MalformedBody { site:A01Site } | InvalidBuilderValue { site:A01Site } | InvalidHostValue { site:A01Site } | UnresolvedGeneratedReference { site:A01Site } | UnsupportedDeclarationCategory { site:A01Site } | RoleAdaptationRejected { site:A01Site } | SpliceRejected { site:A01Site } | A01GenerationMismatch { site:A01Site, mismatch:CompilerBase.ProvenanceExpectation }
sum SynthesisReason = UnknownHook { site:A02Site } | RoleMismatch { site:A02Site } | UnsupportedHookResult { site:A02Site } | UnboundedSynthesis { site:A02Site } | DynamicFallbackRejected { site:A02Site } | A02GenerationMismatch { site:A02Site, mismatch:CompilerBase.ProvenanceExpectation }
sum ResolutionReason = DuplicateDeclaration { site:A03Site, first:ref CompilerSource.Declaration, duplicate:ref CompilerSource.Declaration } | MissingName { site:A03Site, name:CompilerBase.QualifiedNameKey } | WrongNamespace { site:A03Site, expected:CompilerBase.NamespaceCategory, actual:CompilerBase.NamespaceCategory } | InvalidQualification { site:A03Site } | IllegalShadowing { site:A03Site } | IncompatibleDeclarationCategory { site:A03Site } | A03GenerationMismatch { site:A03Site, mismatch:CompilerBase.ProvenanceExpectation }
sum NominalMeaningReason = DuplicateMember { site:A04Site, first:CompilerSource.NominalChild, duplicate:CompilerSource.NominalChild } | InvalidNominalRecursion { site:A04Site } | InvalidNominalCategory { site:A04Site } | MalformedVariantPayload { site:A04Site } | InvalidHandleTarget { site:A04Site } | UniqueWithoutIdentityAuthority { site:A04Site } | A04GenerationMismatch { site:A04Site, mismatch:CompilerBase.ProvenanceExpectation }
sum TypeMeaningReason = UnknownType { site:A05Site } | InvalidRecursiveType { site:A05Site } | IllegalArrayExtent { site:A05Site } | IllegalTypeComposition { site:A05Site } | IncompatibleType { site:A05Site } | UnsupportedTypeOperation { site:A05Site } | A05GenerationMismatch { site:A05Site, mismatch:CompilerBase.ProvenanceExpectation }
sum IntrinsicMeaningReason = IllegalOperandTypes { site:A06IntrinsicSite } | UndefinedShift { site:A06IntrinsicSite } | UnavailableOverflowMeaning { site:A06IntrinsicSite } | IncompatibleFloatContract { site:A06IntrinsicSite } | IllegalCast { site:A06IntrinsicSite } | IllegalPointerOperation { site:A06IntrinsicSite } | UnsupportedAtomicOrdering { site:A06IntrinsicSite } | IncompatibleOperandWidth { site:A06IntrinsicSite } | A06IntrinsicMismatch { site:A06IntrinsicSite, mismatch:CompilerBase.ProvenanceExpectation }
sum OperationAttributionReason = UnsupportedCodeOperationMeaning { site:A06CodeSite } | A06CodeMeaningMismatch { site:A06CodeSite, mismatch:CompilerBase.ProvenanceExpectation }
sum CheckingReason = UnboundValue { site:A07Site } | TypeMismatch { site:A07Site } | InvalidPlace { site:A07Site } | InvalidCall { site:A07Site } | IllegalCastUse { site:A07Site } | InvalidReturnValue { site:A07Site } | InvalidIndex { site:A07Site } | InvalidNominalUse { site:A07Site } | MalformedVariantUse { site:A07Site } | UnsupportedOperation { site:A07Site } | CheckResolutionRejected { site:A07Site, cause:ResolutionReason } | CheckNominalRejected { site:A07Site, cause:NominalMeaningReason } | CheckOwnershipRejected { site:A07Site, cause:StaticOwnershipReason } | A07GenerationMismatch { site:A07Site, mismatch:CompilerBase.ProvenanceExpectation }
sum ControlReason = MissingTerminator { site:A08Site } | MissingSwitchDefault { site:A08Site } | IncompleteVariantSwitch { site:A08Site } | MissingTarget { site:A08Site } | DuplicateTarget { site:A08Site } | InvalidReturnPath { site:A08Site } | IllegalFallthrough { site:A08Site } | BadTransferArgument { site:A08Site } | BadContinuationArgument { site:A08Site } | BadPassthrough { site:A08Site } | EntryParameterWithoutSource { site:A08Site } | UnreachableTransfer { site:A08Site } | ForbiddenSourceControl { site:A08Site } | UnsupportedTransfer { site:A08Site } | A08GenerationMismatch { site:A08Site, mismatch:CompilerBase.ProvenanceExpectation }
sum ContractReason = MalformedContract { site:A09Site } | NonMemorySubject { site:A09Site } | InvalidBoundExpression { site:A09Site } | ContradictoryContract { site:A09Site } | MissingContractSubject { site:A09Site } | UnsupportedContract { site:A09Site } | A09GenerationMismatch { site:A09Site, mismatch:CompilerBase.ProvenanceExpectation }
sum StaticOwnershipReason = IllegalCopy { site:A10StaticSite } | IllegalDrop { site:A10StaticSite } | DoubleDischarge { site:A10StaticSite } | VarOwned { site:A10StaticSite } | DurableLease { site:A10StaticSite } | LeaseEscape { site:A10StaticSite } | RetainingCall { site:A10StaticSite } | ConflictingInvalidation { site:A10StaticSite } | UseOutsideLifetime { site:A10StaticSite } | InvalidResolver { site:A10StaticSite } | MissingLeaseGrant { site:A10StaticSite } | HandleTargetMismatch { site:A10StaticSite } | UnsafeScalarHandleCast { site:A10StaticSite } | InvalidRepresentationWidth { site:A10StaticSite } | UntrustedCrossing { site:A10StaticSite } | UniqueCopyEqualityViolation { site:A10StaticSite } | PrematureErasure { site:A10StaticSite } | A10StaticMismatch { site:A10StaticSite, mismatch:CompilerBase.ProvenanceExpectation }
sum StorageOwnershipReason = LeaseOriginConflict { site:A10StorageSite } | UseAfterInvalidation { site:A10StorageSite } | StorageDischargeViolation { site:A10StorageSite } | StorageInvalidationConflict { site:A10StorageSite } | StorageEscapeViolation { site:A10StorageSite } | A10StorageMismatch { site:A10StorageSite, mismatch:CompilerBase.ProvenanceExpectation }
sum ConstantEvaluationReason = NonConstantExpression { site:A11Site } | RecursiveConstant { site:A11Site } | UnavailableSemanticOperation { site:A11Site } | UnresolvedConstant { site:A11Site } | UnsupportedConstantHostValue { site:A11Site } | ConstantArithmeticRejected { site:A11Site, cause:IntrinsicMeaningReason } | A11GenerationMismatch { site:A11Site, mismatch:CompilerBase.ProvenanceExpectation }
sum CaptureDiscoveryReason = UnresolvedCapture { site:A12Site } | IllegalCaptureEscape { site:A12Site } | UnsupportedCaptureShape { site:A12Site } | UnsupportedNestedCallable { site:A12Site } | A12GenerationMismatch { site:A12Site, mismatch:CompilerBase.ProvenanceExpectation }
sum LayoutReason = IncompleteRecursiveLayout { site:A13Site } | UnrepresentableField { site:A13Site } | UnrepresentablePayload { site:A13Site } | InvalidAlignment { site:A13Site } | TargetWidthMismatch { site:A13Site } | UnsupportedStorageClass { site:A13Site } | LayoutOverflow { site:A13Site } | A13GenerationMismatch { site:A13Site, mismatch:CompilerBase.ProvenanceExpectation }
sum CallableAbiReason = UnrepresentableParameter { site:A14Site } | UnrepresentableResult { site:A14Site } | UnsupportedConvention { site:A14Site } | IncompatibleRedeclaration { site:A14Site } | SignatureCollision { site:A14Site } | MissingSymbolPolicy { site:A14Site } | InvalidVisibility { site:A14Site } | AbiTargetMismatch { site:A14Site } | A14GenerationMismatch { site:A14Site, mismatch:CompilerBase.ProvenanceExpectation }
sum ClosureRepresentationReason = ImpossibleEnvironmentLayout { site:A15Site } | UnsupportedCaptureRepresentation { site:A15Site } | IllegalCaptureStorage { site:A15Site } | UnsupportedNestedRepresentation { site:A15Site } | ClosureTargetMismatch { site:A15Site } | ClosureAbiMismatch { site:A15Site } | A15GenerationMismatch { site:A15Site, mismatch:CompilerBase.ProvenanceExpectation }
sum NoCaptureReason = A15NoCaptureMismatch { site:A15Site, mismatch:CompilerBase.ProvenanceExpectation }
sum OpenRegionReason = MissingRegionDefinition { site:A16Site } | RegionArgumentMismatch { site:A16Site } | RegionWiringMismatch { site:A16Site } | MissingContinuation { site:A16Site } | ContinuationSignatureMismatch { site:A16Site } | CaptureAdmissionFailed { site:A16Site } | DuplicateGeneratedIdentity { site:A16Site } | UnsupportedRegionBody { site:A16Site } | RegionProtocolMismatch { site:A16Site } | A16GenerationMismatch { site:A16Site, mismatch:CompilerBase.ProvenanceExpectation }
sum SealMaterializationReason = MissingSeal { site:A17Site } | SealProtocolMismatch { site:A17Site } | SealArgumentMismatch { site:A17Site } | UnsupportedFrameValue { site:A17Site } | RecursiveSealMaterialization { site:A17Site } | DelegatedAbiRejected { site:A17Site, cause:CallableAbiReason } | A17MaterializationMismatch { site:A17Site, mismatch:CompilerBase.ProvenanceExpectation }
sum SealedCallRoutingReason = SealedArgumentMismatch { site:A17Site } | SealedContinuationMismatch { site:A17Site } | MissingSealedContinuation { site:A17Site } | SealedDelegatedAbiRejected { site:A17Site, cause:CallableAbiReason } | A17RoutingMismatch { site:A17Site, mismatch:CompilerBase.ProvenanceExpectation }
```

### 13.3 A18–A24 reason sums

```text
sum CodeConstructionReason = UnsupportedCheckedConstruct { site:A18Site } | MissingRepresentation { site:A18Site } | IllegalInitializer { site:A18Site } | IllegalRelocation { site:A18Site } | UnboundLoweredValue { site:A18Site } | MalformedCodeBody { site:A18Site } | UnrepresentableCodeType { site:A18Site } | A18GenerationMismatch { site:A18Site, mismatch:CompilerBase.ProvenanceExpectation }
sum CodeValidationReason = DuplicateCodeOccurrence { site:A19Site } | MissingCodeReference { site:A19Site } | CodeSignatureMismatch { site:A19Site } | UndefinedCodeValue { site:A19Site } | InvalidBlockTarget { site:A19Site } | InvalidTransferArguments { site:A19Site } | MalformedMemoryOperation { site:A19Site } | IllegalCodeInitializer { site:A19Site } | InvalidCodeRelocation { site:A19Site } | UnterminatedCodeBlock { site:A19Site } | A19GenerationMismatch { site:A19Site, mismatch:CompilerBase.ProvenanceExpectation }
sum FlowMeaningReason = A21FlowMismatch { site:A21FlowSite, mismatch:CompilerBase.ProvenanceExpectation }
sum InductionUnavailableReason = NonInductionValue { site:A21InductionSite } | AmbiguousInductionRelation { site:A21InductionSite } | UnsupportedInductionRecurrence { site:A21InductionSite } | MissingEdgeWiring { site:A21InductionSite }
sum InductionReason = A21InductionMismatch { site:A21InductionSite, mismatch:CompilerBase.ProvenanceExpectation }
sum ValueAlgebraUnavailableReason = UnsupportedValueExpression { site:A22ValueSite } | UnsafeArithmeticAnalysis { site:A22ValueSite } | IncompatibleFloatMode { site:A22ValueSite } | UnavailableValueProof { site:A22ValueSite }
sum ValueAlgebraReason = A22ValueMismatch { site:A22ValueSite, mismatch:CompilerBase.ProvenanceExpectation }
sum LoopAlgebraUnavailableReason = UnsupportedLoopRecurrence { site:A22LoopSite } | NonAssociativeReduction { site:A22LoopSite } | UnavailableLoopProof { site:A22LoopSite } | UncountedLoopPremise { site:A22LoopSite }
sum LoopAlgebraReason = A22LoopMismatch { site:A22LoopSite, mismatch:CompilerBase.ProvenanceExpectation }
sum MemorySpineReason = UnresolvedStorageProvenance { site:A23SpineSite } | MalformedAcceptedMemoryCode { site:A23SpineSite } | A23SpineMismatch { site:A23SpineSite, mismatch:CompilerBase.ProvenanceExpectation }
sum ObjectMeaningReason = A23ObjectMismatch { site:A23ObjectSite, mismatch:CompilerBase.ProvenanceExpectation }
sum ContractRealizationReason = UnmappableContractSubject { site:A23ContractSite } | ContractProvenanceMismatch { site:A23ContractSite } | A23ContractMismatch { site:A23ContractSite, mismatch:CompilerBase.ProvenanceExpectation }
sum AccessMeaningReason = RequiredBoundsUnproven { site:A23AccessSite } | RequiredNontrapUnproven { site:A23AccessSite } | AccessContractContradiction { site:A23AccessSite } | A23AccessMismatch { site:A23AccessSite, mismatch:CompilerBase.ProvenanceExpectation }
sum MemoryRelationReason = RequiredNoaliasContradicted { site:A23RelationSite } | RequiredDisjointnessUnproven { site:A23RelationSite } | A23RelationMismatch { site:A23RelationSite, mismatch:CompilerBase.ProvenanceExpectation }
sum OperationEffectReason = ContradictoryEffectDeclaration { site:A24OperationSite } | A24OperationMismatch { site:A24OperationSite, mismatch:CompilerBase.ProvenanceExpectation }
sum CallableEffectReason = EffectDeclarationContradiction { site:A24CallableSite } | A24CallableMismatch { site:A24CallableSite, mismatch:CompilerBase.ProvenanceExpectation }
sum RecursiveEffectReason = MalformedCallableComponent { site:A24RecursiveSite } | RecursiveEffectDeclarationContradiction { site:A24RecursiveSite } | A24RecursiveMismatch { site:A24RecursiveSite, mismatch:CompilerBase.ProvenanceExpectation }
```

### 13.4 Optional realization, backend, and host reasons

```text
sum KernelNoPlanReason = UnsupportedKernelControl { site:A25Site } | UnsafeKernelMemory { site:A25Site } | MissingKernelProof { site:A25Site } | UnsupportedKernelExpression { site:A25Site } | UnsupportedKernelEffect { site:A25Site } | InvalidKernelTrip { site:A25Site } | AmbiguousKernelLane { site:A25Site } | UnsupportedKernelResult { site:A25Site }
sum KernelRecognitionReason = A25EvidenceMismatch { site:A25Site, mismatch:CompilerBase.ProvenanceExpectation }
sum ScheduleNoPlanReason = UnsupportedScheduleTarget { site:A26Site } | MissingEmitterCapability { site:A26Site } | IllegalVectorSchedule { site:A26Site } | IllegalTailSchedule { site:A26Site } | InsufficientScheduleProof { site:A26Site } | InvalidScheduledMovement { site:A26Site } | UnsupportedScheduledResult { site:A26Site } | SchedulePolicyRejected { site:A26Site }
sum ScheduleSelectionReason = A26EvidenceMismatch { site:A26Site, mismatch:CompilerBase.ProvenanceExpectation }
sum FusedUnavailableReason = UnsupportedFusedDomain { site:A27Site } | UnsupportedFusedResult { site:A27Site } | UnsupportedFusedOperator { site:A27Site } | UnsupportedFusedWindow { site:A27Site } | UnsupportedFusedTail { site:A27Site } | IncompatibleFusedSchedule { site:A27Site } | UnsafeFusedAccess { site:A27Site } | MissingFusedBounds { site:A27Site } | MissingFusedNoalias { site:A27Site } | FusedShapeContradiction { site:A27Site }
sum FusedProjectionReason = A27EvidenceMismatch { site:A27Site, mismatch:CompilerBase.ProvenanceExpectation }
sum UsePopulationUnrealizableReason = UnsupportedUseTopology { site:A28PopulationSite } | AmbiguousUseOrder { site:A28PopulationSite } | UnsupportedWindowUse { site:A28PopulationSite }
sum UsePopulationReason = A28PopulationMismatch { site:A28PopulationSite, mismatch:CompilerBase.ProvenanceExpectation }
sum UseMeaningReason = MissingUseProvenance { site:A28MeaningSite } | ContradictoryUseRole { site:A28MeaningSite } | A28MeaningMismatch { site:A28MeaningSite, mismatch:CompilerBase.ProvenanceExpectation }
sum CoordinateUnrealizableReason = CoordinateDisagreement { site:A28CoordinateSite } | UnknownCoordinateStride { site:A28CoordinateSite } | UnknownCoordinateExtent { site:A28CoordinateSite } | InvalidCoordinateWindow { site:A28CoordinateSite } | UnsafeCoordinateDereference { site:A28CoordinateSite } | MissingCoordinateAlignment { site:A28CoordinateSite } | UnsupportedCoordinateRank { site:A28CoordinateSite } | CoordinateOverflow { site:A28CoordinateSite } | PinnedCoordinateAccess { site:A28CoordinateSite } | PotentiallyTrappingCoordinate { site:A28CoordinateSite }
sum CoordinateReason = A28CoordinateMismatch { site:A28CoordinateSite, mismatch:CompilerBase.ProvenanceExpectation }
sum UseAdmissionReason = CandidateCardinalityMismatch { site:A28AdmissionSite } | CandidateOrderMismatch { site:A28AdmissionSite } | A28AdmissionMismatch { site:A28AdmissionSite, mismatch:CompilerBase.ProvenanceExpectation }
sum RelationUnavailableReason = NoComparableRelationEndpoints { site:A23RelationSite } | RelationPremiseUnavailable { site:A23RelationSite }
sum PointerUnqualifiedReason = QualificationNotRequested { site:A28QualificationSite } | ExactNoaliasUnavailable { site:A28QualificationSite }
sum QualificationUnavailableReason = MissingExactNoaliasProvenance { site:A28QualificationSite }
sum PointerRepresentationReason = UnsupportedPointerRepresentation { site:A28QualificationSite }
sum PointerQualificationReason = ContradictoryQualificationEvidence { site:A28QualificationSite } | A28QualificationMismatch { site:A28QualificationSite, mismatch:CompilerBase.ProvenanceExpectation }
sum AddressUnrealizableReason = UnsupportedAddressBasis { site:A28AddressSite } | MissingAddressValue { site:A28AddressSite } | AddressEnvironmentIncomplete { site:A28AddressSite } | AddressOverflow { site:A28AddressSite }
sum AddressReason = A28AddressMismatch { site:A28AddressSite, mismatch:CompilerBase.ProvenanceExpectation }

sum BaselineReason = UnsupportedBaselineOperation { site:A29BaselineSite } | IncompleteBaselineCoverage { site:A29BaselineSite } | MissingBaselineEmitterCapability { site:A29BaselineSite } | BaselineTargetMismatch { site:A29BaselineSite }
sum StrategyReason = NoCorrectSubjectRealization { site:A29StrategySite }
sum StrategyResumeReason = NoCorrectFallbackRealization { site:A29ResumeSite }
sum StrategyFailureReason = InitialStrategyFailure { reason:StrategyReason } | ResumedStrategyFailure { reason:StrategyResumeReason }
sum FragmentCommitReason = FragmentCommitSubjectMismatch { site:A29CommitSite } | A29CommitMismatch { site:A29CommitSite, mismatch:CompilerBase.ProvenanceExpectation }
sum FragmentUnrealizableReason = UnsupportedFragmentRealization { site:A30Site } | UnsupportedFragmentValue { site:A30Site } | UnsupportedClosedForm { site:A30Site } | InvalidFragmentCoverage { site:A30Site } | DominanceFailure { site:A30Site } | InvalidAdapter { site:A30Site } | InvalidFragmentExit { site:A30Site } | MissingFragmentCoordinate { site:A30Site } | MissingFragmentValue { site:A30Site } | MissingFragmentAccess { site:A30Site } | NamespaceConflict { site:A30Site } | HelperConflict { site:A30Site } | IncompleteContribution { site:A30Site } | ConflictingContribution { site:A30Site }
sum FragmentReason = A30EvidenceMismatch { site:A30Site, mismatch:CompilerBase.ProvenanceExpectation }

sum BackendConstructionReason = UnrepresentableBackendType { site:A31Site } | UnrepresentableBackendOperation { site:A31Site } | UnrepresentableBackendStorage { site:A31Site } | UnrepresentableInitializer { site:A31Site } | UnrepresentableAbi { site:A31Site } | MissingBackendSymbol { site:A31Site } | MissingBackendHelper { site:A31Site } | IllegalLinkage { site:A31Site } | InvalidAssemblyContribution { site:A31Site } | InvalidBlockParameterElimination { site:A31Site } | BackendTargetMismatch { site:A31Site } | A31GenerationMismatch { site:A31Site, mismatch:CompilerBase.ProvenanceExpectation }
sum CSerializationReason = InvalidBackendReference { site:A32Site } | CSignatureMismatch { site:A32Site } | IllegalCType { site:A32Site } | MalformedCControl { site:A32Site } | InvalidCMemoryAccess { site:A32Site } | UnsupportedCEntity { site:A32Site } | CEmitterCapabilityMismatch { site:A32Site } | CHelperConflict { site:A32Site } | CSerializationBoundaryRejected { site:A32Site } | A32TargetMismatch { site:A32Site, mismatch:CompilerBase.ProvenanceExpectation }

sum OptionalRealizationReason = KernelOptionalReason { reason:KernelNoPlanReason } | ScheduleOptionalReason { reason:ScheduleNoPlanReason } | FusedOptionalReason { reason:FusedUnavailableReason } | UsePopulationOptionalReason { reason:UsePopulationUnrealizableReason } | CoordinateOptionalReason { reason:CoordinateUnrealizableReason } | QualificationOptionalReason { reason:QualificationUnavailableReason } | PointerRepresentationOptionalReason { reason:PointerRepresentationReason } | AddressOptionalReason { reason:AddressUnrealizableReason } | FragmentOptionalReason { reason:FragmentUnrealizableReason }
sum SemanticRejectReason = A01Reject { reason:AuthoredMaterializationReason } | A02Reject { reason:SynthesisReason } | A03Reject { reason:ResolutionReason } | A04Reject { reason:NominalMeaningReason } | A05Reject { reason:TypeMeaningReason } | A06IntrinsicReject { reason:IntrinsicMeaningReason } | A06CodeReject { reason:OperationAttributionReason } | A07Reject { reason:CheckingReason } | A08Reject { reason:ControlReason } | A09Reject { reason:ContractReason } | A10StaticReject { reason:StaticOwnershipReason } | A10StorageReject { reason:StorageOwnershipReason } | A11Reject { reason:ConstantEvaluationReason } | A12Reject { reason:CaptureDiscoveryReason } | A13Reject { reason:LayoutReason } | A14Reject { reason:CallableAbiReason } | A15ClosureReject { reason:ClosureRepresentationReason } | A15NoCaptureReject { reason:NoCaptureReason } | A16Reject { reason:OpenRegionReason } | A17MaterializationReject { reason:SealMaterializationReason } | A17RoutingReject { reason:SealedCallRoutingReason } | A18Reject { reason:CodeConstructionReason } | A19Reject { reason:CodeValidationReason } | A21FlowReject { reason:FlowMeaningReason } | A21InductionReject { reason:InductionReason } | A22ValueReject { reason:ValueAlgebraReason } | A22LoopReject { reason:LoopAlgebraReason } | A23SpineReject { reason:MemorySpineReason } | A23ObjectReject { reason:ObjectMeaningReason } | A23ContractReject { reason:ContractRealizationReason } | A23AccessReject { reason:AccessMeaningReason } | A23RelationReject { reason:MemoryRelationReason } | A24OperationReject { reason:OperationEffectReason } | A24CallableReject { reason:CallableEffectReason } | A24RecursiveReject { reason:RecursiveEffectReason } | A25Reject { reason:KernelRecognitionReason } | A26Reject { reason:ScheduleSelectionReason } | A27Reject { reason:FusedProjectionReason } | A28PopulationReject { reason:UsePopulationReason } | A28MeaningReject { reason:UseMeaningReason } | A28CoordinateReject { reason:CoordinateReason } | A28AdmissionReject { reason:UseAdmissionReason } | A28QualificationReject { reason:PointerQualificationReason } | A28AddressReject { reason:AddressReason } | A29BaselineReject { reason:BaselineReason } | A29StrategyReject { reason:StrategyReason } | A29ResumeReject { reason:StrategyResumeReason } | A29CommitReject { reason:FragmentCommitReason } | A30Reject { reason:FragmentReason } | A31Reject { reason:BackendConstructionReason } | A32Reject { reason:CSerializationReason }
```

A20, B44, B45, B52, and B55 are total and therefore have no semantic rejection reason leaves.

Host failures remain disjoint from `SemanticRejectReason`:

```text
sum GccCookFailure = CompilerUnavailable { request:ref CompilerHost.GccCookRequest } | FileWriteFailure { request:ref CompilerHost.GccCookRequest, path:CompilerBase.PathValue } | ProcessSpawnFailure { request:ref CompilerHost.GccCookRequest } | CCompilationFailure { request:ref CompilerHost.GccCookRequest, exit_code:number, stderr_text:str } | DynamicLoadFailure { request:ref CompilerHost.GccCookRequest, library_path:CompilerBase.PathValue }
sum SymbolResolutionFailure = MissingLoadedSymbol { request:ref CompilerHost.SymbolRequest } | IncompatibleFfiCast { request:ref CompilerHost.SymbolRequest }
sum UseAfterReleaseFailure = UseAfterRelease { session:ref CompilerHost.ReleasedGccSession, key:CompilerBase.SymbolKey }
```

---

## 14. Direct and named-exit method signatures

`docs/COMPILER_OPERATION_LIFETIME_MODEL.md` §§7–10 is the exact B01–B61 and
subordinate exit ledger. Those tables are incorporated into this schema by B ID.
Payload names there resolve to the ASDL declarations in §§3–13.

### 14.1 ABI notation

A total method returns its one output directly:

```text
receiver:operation(input?) -> Output
```

An immediate multi-exit value method receives the exact named machine object and one
stable unbound method from that machine class per peer exit:

```text
receiver:operation(input?, machine, on_exit_1, ..., on_exit_n) -> Answer
on_exit_i(machine, payload...) -> Answer
```

`Answer` is the ordinary Lua value returned by the selected machine edge. It is not a
semantic result type, and the producer must not inspect or transform it.

`input?` is present unless the receiver owns the complete semantic frontier. `machine`
is the named computation in progress, not opaque state or a continuation frame. The
producer forwards it unchanged and calls exactly one peer exit. Each exit is a stable
unbound method such as `ResolutionMachine.namespace_contributed`.

Machine methods own the static control graph. They name and tail-call their successors
directly; another continuation parameter is not threaded through them. A stable named
method can be stored on the machine only for a genuinely variable join or suspension.

Every selected exit and machine transition is a strict tail call. Exit functions are
created once as class methods, never per semantic invocation. There is no `k` wrapper,
result junction, callback table, string lookup, scheduler, or runtime region descriptor.

### 14.2 Direct operations

These operations return the named value directly:

| Coverage | Receiver method | Direct output |
|---|---|---|
| B24 | `CodeAccepted:derive_control_topology` (consumes receiver field `topology`) | `CompilerCode.ControlTopologySpine` |
| B44 | `UseMeaningPublicationRequest:publish_use_meaning` | `CompilerLower.MaterializedUseFacet` |
| B45 | `CoordinatePublicationRequest:publish_coordinates` | `CompilerLower.CoordinateFacet` |
| B52 | `DominanceRequest:derive_dominance` | `CompilerAnalysis.DominanceFacet` |
| B55 | `GnuCEmitter:declare_capability` with `EmitterCapabilityInput` | `CompilerBase.GnuCEmitterCapability` |
| C24/C25 | `contribute_def_use` | `CompilerCode.DefUseContributions` |
| C25 | `contribute_topology` | `CompilerCode.TopologyContributions` |
| C22/C24 | `memory_access_causes` | ordered `many CompilerAnalysis.MemoryAccessCause` |
| accepted C26/C27 | concrete physical leaf `emit_c` with `CSerializationInput` | `CompilerBackend.CEntityText` |
| A18 | `CodeConstructionRequest:project_code_identities` | `CompilerCode.CodeIdentityProjection` |
| A22 | `MonomorphicCodeSpine:project_value_algebra_population` | `CompilerAnalysis.CodeValueAlgebraPopulation` |
| A23 | `MemoryRelationPopulationRequest:project_relation_population` | `CompilerAnalysis.MemoryRelationPopulation` |
| A31 | `BackendConstructionRequest:project_backend_identities` | `CompilerBackend.BackendIdentityProjection` |
| A29 | each `AlternativeRejectionRequest:record_rejection` leaf | `CompilerAnalysis.RejectedAlternative` |

The A18/A22/A23/A31 projection methods use ordinary direct loops with one local dense
array and construct their ASDL output once. They allocate no aggregate machine or cursor.
### 14.3 Aggregate finalization operations

| Coverage | Receiver method | Input | Exact continuations |
|---|---|---|---|
| B03 | `SemanticProgramSpine:resolve_namespaces` | `CompilerSource.ResolutionFinalizationInput` | `resolution_published(ResolutionFacet)`; `resolution_rejected(ResolutionReason)` |
| B22 | `CodeConstructionRequest:construct_monomorphic_code` | `CompilerCode.CodeConstructionFinalizationInput` | `code_constructed(MonomorphicCodeSpine)`; `code_construction_rejected(CodeConstructionReason)` |
| B23 | `CodeValidationRequest:validate_code_structure` | `CompilerCode.CodeValidationFinalizationInput` | `code_accepted(CodeAccepted)`; `code_validation_rejected(CodeValidationReason)` |
| B54 | `BackendConstructionRequest:construct_backend_unit` | `CompilerBackend.BackendConstructionFinalizationInput` | `backend_constructed(PhysicalBackendSpine)`; `backend_rejected(BackendConstructionReason)` |
| B56 | `GnuCEmitter:validate_and_serialize_c` | `CompilerBackend.CSerializationFinalizationInput` | `c_artifact_accepted(CArtifact)`; `c_serialization_rejected(CSerializationReason)` |

The narrow aggregate machines are `ResolutionMachine`, `CodeConstructionMachine`,
`CodeValidationMachine`, `BackendConstructionMachine`, and `CSerializationMachine`;
their exact state and builder planes are in the lifetime model §5. They are ordinary Lua
objects, not ASDL declarations. Builder freeze closes one accumulation plane but does
not terminate the machine; its named methods continue the graph. B03 derives
`ResolutionFacet.shadowing` at finalization from its
program receiver, policy, collected occupancies, and collected resolved references;
C03 has no separate shadowing contribution. All six subordinate rejection
continuations in §14.4 are terminal. Step-9R defines no aggregate rejection fold.

### 14.4 Other immediate named-exit operations

The following B operations use the exact peer exits and payloads in the lifetime ledger:

```text
B01–B02, B04–B21
B25–B43
B46–B51
B53
```

B03, B22, and B23 use the aggregate inputs above. B04 has three exits and no carrier
sum:

```text
nominal_declaration_published(NominalDeclarationMeaningEntry)
nominal_child_published(NominalChildMeaningEntry)
nominal_rejected(NominalMeaningReason)
```

The subordinate named-exit operations are:

| Owner operation | Input | Exact continuations |
|---|---|---|
| C03 declaration leaf `contribute_namespace` | `ResolutionInput` | `namespace_contributed(many NamespaceOccupancyEntry)`; `namespace_rejected(ResolutionReason)` |
| C03 declaration leaf `resolve_decl_references` | `ResolutionInput` | `references_resolved(many ResolvedReferenceEntry)`; `references_rejected(ResolutionReason)` |
| admitted C03/C13–C19 leaf `construct_code_entity` | `CodeLeafConstructionInput` | `code_entity_contributed(CodeConstructionContribution)`; `code_entity_rejected(CodeConstructionReason)` |
| C21–C25 leaf `validate_structure` | `CodeValidationRequest` | `code_entity_accepted(CodeValidationSubject)`; `code_entity_rejected(CodeValidationReason)` |
| C21–C27 leaf `construct_backend_entity` | `BackendLeafConstructionInput` | `backend_entity_contributed(BackendConstructionContribution)`; `backend_entity_rejected(BackendConstructionReason)` |
| C26/C27 leaf `validate_c` | `CSerializationInput` | `c_entity_accepted(BackendValidationSubject)`; `c_entity_rejected(CSerializationReason)` |

### 14.5 Sealed host methods

| Coverage | Receiver method | Boundary output |
|---|---|---|
| B57 | `GccCookRequest:cook_and_load` | `CompilerHost.GccCookResult` |
| B58 | `LiveGccSession:resolve_symbol(SymbolRequest)` | `CompilerHost.SymbolResolutionResult` |
| B59 | `LiveGccSession:release` | `CompilerHost.SessionReleased` |
| B60 | `ReleasedGccSession:release` | `CompilerHost.AlreadyReleased` |
| B61 | `ReleasedGccSession:resolve_symbol(SymbolKey)` | `CompilerHost.UseAfterReleaseFailed` |

The disjoint public semantic-rejection boundary has this exact signature:

```text
authority_reason:to_semantic_rejection() -> CompilerBoundary.TypedSemanticRejection
HostCompilationMachine.semantic_rejected(machine, rejection:CompilerBoundary.TypedSemanticRejection) -> Answer
```

It is not a B operation or host-failure result. It is the one named host-machine edge
by which typed semantic rejection leaves compiler control.
### 14.6 Leaf and shared-method ownership

Each supporting concrete sum leaf owns its semantic method. A parent method is legal
only as a field-agnostic shared default or same-contract delegation. It must not
inspect class, `kind`, tag, action, or field shape. Several leaves can reference the
same stable Lua function directly. A leaf override shadows a shared parent default.

The closed compiler tests enumerate concrete leaves from ASDL sum membership, call every
declared value method, and drive every named exit with its exact machine and payload.
They verify direct ownership, legal shared inheritance, or explicit delegation from the
ordinary class method tables. They also verify that each machine method names its static
successor directly. Tests do not reproduce the graph in an operation descriptor or
conformance registry.

`CodeConstructionContribution`, `DefUseContributions`, `TopologyContributions`,
`CodeIdentityProjection`, `BackendIdentityProjection`,
`BackendConstructionContribution`, `CEntityText`, the A22/A23 population records,
`TopologyDerivationInput`, and the five finalization inputs are typed one-consumer
boundary data. They are not facets, worlds, caches, or control-result wrappers.

---

## 15. Schema closure proof

The Step-9R schema is closed only if all statements hold:

1. S1–S8 are the only identity/alignment spines and are non-interned allocations.
2. F01–F34 each retain one producer authority and exact spine alignment; S8 has no
   facet.
3. C01–C29 behavior remains on concrete leaves without category placeholders or
   manual variant dispatch.
4. A01–A33 and B01–B61 retain an intrinsic receiver or one narrow request frontier.
5. B01–B61 occur exactly once in the direct/continuation/sealed ledger.
6. Every total operation returns one exact ASDL value directly.
7. Every immediate multi-exit operation has one fixed ordered peer-exit signature and
   no internal result sum.
8. Every owning sum leaf implements its operation through a legal shared default,
   delegation, or leaf override.
9. Every named exit has a focused test with the exact machine, payload class, and arity.
10. Dense conservative meanings remain ASDL entries. Sparse no-entry alternatives
    remain typed named exits, never `nil` or booleans.
11. A28 candidates contain no S7 identity; B43 alone creates S7; B44/B45 publish
    total F31/F32.
12. F33 has no F32 dependency. `restrict` requires complete declared pairwise-noalias
    evidence over at least two distinct qualified objects.
13. B49/B50 attempts publish no F22. Only deliberate baseline or committed fragment
    realization creates F22.
14. Fragment locals and labels are fragment coordinates. B54 alone creates S8 physical
    identity.
15. C26/C27 physical leaves own C behavior. `GnuCEmitter` is the sole emitter leaf.
16. A33 resources expose typed provenance and liveness while runtime handles remain
    private.
17. Every keyed relation is a named product under `many`; no map, side cache, or
    encoded-name recovery exists.
18. No ASDL product combines independently invalidated facets into a context, phase,
    result, plan, world, frame, or machine bag.
19. Every reason preserves its authority site and every generated occurrence preserves
    causal provenance.
20. Every spine order is an exact once-only permutation of its population.
21. Only F01/F18/F23/F28/F30/F31/F32 are aggregate facet products.
22. The five aggregate inputs preserve authoritative order and receive no mutable
    accumulator after construction.
23. `CompilerResult`, `CompilerControl`, `CompilerControlState`,
    `SourceCheckingDestination`, `CEntityValidationResult`, old internal `*Result`
    sums, and `continue_after_*` methods are absent.
24. Host failures remain disjoint from `SemanticRejectReason`.
25. All ASDL references resolve, all declaration names are unique, and O/A/B/C/S/F
    coverage closes.
26. Every running machine owns one coherent computation. Every passed exit is a stable
    unbound method of that exact machine class, and every static successor is a named
    machine method rather than another threaded continuation.
27. All six subordinate rejection continuations are terminal; no aggregate rejection
    fold exists.
28. C24/C25 direct contributions populate `TopologyDerivationInput` exactly once; B23
    freezes it in `CodeAccepted`, and B24 is its sole consumer.
29. B03 alone derives `ResolutionFacet.shadowing` from the frozen resolution frontier.
30. An authority reason’s field-agnostic boundary method alone constructs
    `TypedSemanticRejection`; the running host machine’s named
    `semantic_rejected` method is its sole consumer.
31. No operation, exit, machine, or conformance descriptor IR exists; authored Lua
    classes, method signatures, and strict tail calls are the control graph.

This document defines schema and method contracts only. Runtime implementation and
compiler migration require separate authorization.
