# Experimental Native Copy-Patch Architecture

This document records the experimental C-stencil copy-patch architecture. It is
not the main Lalin JIT or AOT path. The main path is `CBackendUnit -> emit_c`,
then either GCC-cooked shared-object loading for JIT-like execution or a
user-owned AOT C build.

The filename still contains `RESIDUAL` for historical path stability. The
architecture is residualless. Residual meant undefined compiler work hidden
behind a bag name. That concept is deleted from the native compiler.

The experimental native backend is a C-stencil copy-patch compiler:

```text
LalinCode / LalinKernel / LalinStencil ASDL
  -> methods on those ASDL values
  -> generated NativeTemplateSource C stencils
  -> offline gcc/clang -O3 object build
  -> ELF/object parser + verifier
  -> NativeEmbeddedTemplateBank
  -> LalinNative template graph
  -> LalinNative copy plan
  -> copied binary templates
  -> typed patch holes + continuation relocations
  -> executable native code
```

`LalinNative` is not a second semantic IR. It owns machine artifacts only:
targets, template sources, compiled bytes, symbols, relocations, hole layouts,
template banks, template graphs, copy plans, patch coordinates, executable
memory, call protocols, and build results.

## Sources

- Copy-and-Patch Compilation:
  <https://fredrikbk.com/publications/copy-and-patch.pdf>
- Copy-and-Patch arXiv record:
  <https://arxiv.org/abs/2011.13127>
- PyPy/RPython JIT docs:
  <https://rpython.readthedocs.io/en/latest/jit/pyjitpl5.html>
- Applying a Tracing JIT to an Interpreter:
  <https://pypy.org/posts/2009/03/applying-tracing-jit-to-interpreter-3287844903778799266.html>
- Futhark performance guide:
  <https://futhark.readthedocs.io/en/stable/performance.html>
- Futhark redomap paper:
  <https://www.futhark-lang.org/publications/array16.pdf>

## Hard Decisions

0. This is an experimental backend track. It must not be documented or treated as
   the main JIT/AOT path; `emit_c` and GCC-owned C compilation are the main path.
1. `LalinCode`, `LalinKernel`, and `LalinStencil` own semantic compiler shape.
2. `LalinNative` owns artifact shape.
3. A native family is the machine-template projection of an existing semantic
   ASDL leaf, not a new semantic category.
4. A valid native semantic operation is implemented by a method on the concrete
   ASDL leaf that owns it.
5. Missing implementation is a missing method and a hard internal error.
6. Bank build errors are typed build results.
7. Runtime install errors are typed install results.
8. C source is the AOT template authoring language.
9. Handwritten assembly template sources are not part of the native backend.
10. Runtime native compilation copies precompiled bytes and patches typed holes.
11. Runtime native compilation never invokes C compilation, ELF tools, TCC, or
    residual glue.
12. The baseline fragment protocol is C continuation + typed frame slots.
13. The C compiler owns register allocation; register protocol is not a baseline
    template-source axis.
14. No exact-cell bank is the architecture.
15. No subset/test bank is a complete language bank.
16. Complete-bank axes are only closed machine/control families; program facts,
    counts, names, sizes, signatures, ranks, strides, offsets, and flags are not
    axes.
17. No coverage accounting exists in compiler semantics.
18. No cap defines semantics.
19. Recursive expression, access, and control shape is handled by template graph
    composition.

## Deleted Concepts

These names are forbidden in target architecture:

```text
NativeAlgebraForm
NativeProducer
NativeAccess
NativeBody
NativeConsumer
NativeSchedule
NativePrimitiveBasis
NativeSaturation
NativeFusedForm
NativeSupertemplateSelection as semantic fusion state
ResidualFunctionPlan
CResidual*
StencilRequiresCompile
NeedsResidualC
Uncovered*
Coverage*
fallback native path
exact embedded machine-code bank as main bank
exact-cell bank enumeration
handwritten assembly template source
NativeTemplateAssembly
NativeTemplateLanguage
register-fragment baseline
cell.kind
producer.kind
shape.kind
artifact_shape(...).kind
string dispatch
side-table planning
budget semantics
cap semantics
```

## Semantic Owners

The semantic family basis is already present in the repository.

### Code

Scalar function native compilation is owned by:

```text
CodeModule
CodeFunc
CodeBlock
CodeInst
CodeInstOp
CodeTerm
CodeTermOp
CodePlace
CodeConst
CodeType
CodeSig
CodeCallTarget
CodeGlobalRef
```

### Kernel

Lowered loop and effect native compilation is owned by:

```text
KernelPlan
KernelBody
KernelDomain
KernelLane
KernelExpr
KernelEffect
KernelResult
KernelProof
KernelEquivalence
KernelSkeletonSelection
```

### Stencil

Stencil native compilation is owned by:

```text
StencilInstance
StencilDescriptor
StencilProducer
StencilProducerShape
StencilAccess
StencilAccessLayout
StencilPointExpr
StencilBody
StencilSink
StencilStoreSemantics
StencilReductionSemantics
StencilReduceScope
StencilReducer
StencilSchedule
StencilProofRequirement
StencilProofObligation
StencilAbi
```

The existing `StencilInstance` shape is the generator/body/sink architecture:

```text
StencilInstance {
  id
  descriptor {
    producer { shape }
    accesses
    body
    sink
  }
  schedule
  abi
  proofs
}
```

No native schema repeats this structure under native semantic mirror names.

## Family Basis

The native bank contains template families for the concrete semantic leaves
that change machine structure.

### Code Families

```text
CodeFunc
CodeBlock
CodeInstConst
CodeInstAlias
CodeInstUnary
CodeInstBinary
CodeInstFloatBinary
CodeInstCompare
CodeInstCast
CodeInstSelect
CodeInstIntrinsic
CodeInstAddrOf
CodeInstGlobalRef
CodeInstPtrOffset
CodeInstLoad
CodeInstStore
CodeInstAggregate
CodeInstArray
CodeInstViewMake
CodeInstViewData
CodeInstViewLen
CodeInstViewStride
CodeInstSliceMake
CodeInstSliceData
CodeInstSliceLen
CodeInstByteSpanMake
CodeInstByteSpanData
CodeInstByteSpanLen
CodeInstClosure
CodeInstVariantCtor
CodeInstVariantTag
CodeInstVariantPayload
CodeInstCall
CodeInstAtomicLoad
CodeInstAtomicStore
CodeInstAtomicRmw
CodeInstAtomicCas
CodeInstAtomicFence
CodeTermJump
CodeTermBranch
CodeTermSwitch
CodeTermVariantSwitch
CodeTermReturn
CodeTermTrap
CodeTermUnreachable
CodePlaceLocal
CodePlaceGlobal
CodePlaceData
CodePlaceDeref
CodePlaceField
CodePlaceIndex
CodePlaceBytes
CodeConstLiteral
CodeConstNull
CodeConstUndef
CodeCallDirect
CodeCallExtern
CodeCallIndirect
CodeCallClosure
```

### Kernel Families

```text
KernelDomainFlow
KernelExprValue
KernelExprAlgebra
KernelExprLaneLoad
KernelExprKernelValue
KernelEffectStore
KernelEffectScan
KernelEffectPartition
KernelEffectCopy
KernelEffectScatterReduce
KernelEffectFold
KernelEffectCall
KernelResultVoid
KernelResultValue
KernelResultFind
KernelResultReduction
KernelResultClosedForm
KernelResultOriginalControl
KernelSkeletonScan
KernelSkeletonCopy
KernelSkeletonScatterReduce
KernelSkeletonFind
```

### Stencil Families

```text
StencilProduceRange1D
StencilProduceRangeND
StencilProduceWindowND
StencilProduceTiledND
StencilLayoutScalar
StencilLayoutContiguous
StencilLayoutIndexed
StencilLayoutAffine1D
StencilLayoutAffineND
StencilLayoutFieldProjection
StencilLayoutSoAComponent
StencilLayoutSliceDescriptor
StencilLayoutByteSpanDescriptor
StencilLayoutViewDescriptor
StencilPointInput
StencilPointWindowInput
StencilPointConst
StencilPointUnary
StencilPointBinary
StencilPointCast
StencilPointPredicate
StencilPointCompare
StencilPointSelect
StencilBodyPoint
StencilSinkStore
StencilSinkReduce
StencilSinkScan
StencilSinkScatterReduce
StencilStoreElementwise
StencilStoreCopy
StencilStoreScatter
StencilStorePartition
StencilReduceFold
StencilReduceCount
StencilReduceFind
StencilReduceScopeDomain
StencilReduceScopeAxes
StencilReduceScopeWindow
StencilScheduleScalar
StencilScheduleAutoVector
StencilScheduleUnrolled
StencilScheduleVector
```

These families are complete as a closed family basis: they are the concrete
leaves of the current semantic ASDL that can affect native machine shape. The
bank source list is derived from this basis; it is not an ad hoc catalog and it
is not a Cartesian enumeration of whole stencil/program cells.

## Complete Bank Closure Doctrine

A complete native bank is not a large subset support domain. It is the finite
closure of the current language surface under a closed machine-template
vocabulary. The complete-bank generator must be able to enumerate every required
`NativeTemplateSource` without seeing a user program, a concrete `CodeSig`, a
field name, a type layout size, an access name, a body length, a rank chosen by a
program, or a schedule flag string.

Every `NativeTemplateFamily` axis used by the complete bank satisfies both
conditions below:

```text
1. the value is drawn from a closed ASDL alternative or target scalar/control class
2. the value changes C source shape, object verification shape, control shape, or ABI micro-op shape
```

Every unbounded user/program value is forbidden as a bank axis and is represented
as exactly one of:

1. **Graph repetition**: expression terms, logical terms, lanes, effects,
   parameters, results, producer axes, window offsets, layout-chain steps, and
   body members are repeated `NativeTemplateGraph` nodes. They are not counts in
   a family id.
2. **Patch coordinates / holes**: byte sizes, alignments, field offsets,
   component offsets, strides, scales, steps, immediate constants, frame-slot
   offsets, frame size, constant-pool addresses, call targets, and branch targets
   are typed holes or patch formulas.
3. **Frame/runtime values**: base pointers, lengths, starts/stops, descriptor
   fields, dynamic strides, user scalar values, reduction initial values,
   closure contexts, and external arguments remain frame slots or ABI/runtime
   parameters.
4. **Lowering facets**: program-specific type/layout/proof/address facts live in
   `Native*Projection`, `Native*LayoutPlan`, `Native*LoweringInput`,
   `NativePatchBinding`, `NativeFrameLayout`, and `NativeConstantPoolLayout`
   products consumed while binding graph nodes. They do not identify bank
   families.

Only closed machine/control choices remain bank axes:

```text
target architecture / OS / ABI / endianness / pointer width
machine scalar representation class
closed arithmetic/cast/compare/reduction operation leaves
closed memory/address micro-op leaves
closed control-transfer micro-op leaves
closed ABI placement/protocol micro-op leaves
closed Kernel/Stencil producer/access/point/sink/schedule micro-op leaves
```

The complete bank is generated from `NativeCompleteBankCapability`, a closed
capability product, not from a list of exact requested shapes. `NativeKernelSourceSupport`
and `NativeStencilSourceSupport` are test/subset-bank helpers only. They are not
complete-bank coverage products. Complete coverage is the manifest constructor
that expands `NativeCompleteBankCapability` into primitive source families.

`NativeTemplateBankRequest.sources` for the complete bank is therefore derived
from these inputs only:

```text
closed language family basis from this document
closed native micro-op vocabulary in LalinNative ASDL
closed target/machine capability product
  -> complete NativeTemplateBankRequest.sources
```

Every source in the request is generated C. There is no native assembly source
variant and no runtime C/residual fallback.

The C compiler owns register allocation. Physical register names, register
transfer stencils, and register protocols are not baseline bank dimensions.
Target register facts exist as target/ABI metadata for platform ABI descriptions.
Ordinary Code/Kernel/Stencil fragments communicate through frame slots and
continuations.

A missing semantic native method or missing source-builder method is absent on
the ASDL leaf. Calling it naturally fails at the method call site. The compiler
must not install placeholder methods or create explicit `unsupported`,
`unimplemented`, `missing source`, coverage, fallback, or compile-later result
values to keep execution green.

The complete-bank induction cases are micro-op based:

- non-recursive semantic leaves lower to one or more primitive graph nodes;
- recursive `StencilPointExpr` leaves compose child point-template nodes and
  value edges instead of requiring a template for the entire expression tree;
- recursive `StencilAccessLayout` leaves compose parent layout/address nodes and
  patch coordinates instead of enumerating every full layout chain;
- `StencilDescriptor` composes producer, accesses, body, sink, schedule, ABI,
  and proof-owned facts into a `NativeTemplateGraph`;
- `CodeBlock` control graphs become `NativeControlEdge` / `NativeValueEdge`
  structure, not exact block cells;
- kernel effect lists and result lists compose effect/result graph nodes, not
  whole-kernel exact cells;
- Code signatures compose ABI param/result/call/return micro-ops instead of
  selecting a bank family for each full `CodeSig`.

The complete-bank source-shape vocabulary is primitive. It does not summarize a
whole user expression, whole user body, whole signature, whole access chain, or
whole stencil instance. Each graph node selects one primitive family and carries
only closed machine/control axes. Program facts are carried in the node's patch,
frame, runtime, constant-pool, or lowering bindings.

### Complete-bank field classification

| Program fact | Target representation |
| --- | --- |
| byte size and alignment | `NativeStorageLayout` / lowering facet plus frame value or typed size/alignment hole |
| field name, access name, function id, type identity, signature identity | semantic/lowering projection only; never family identity |
| field offset, component offset, stride, scale, step, affine coefficient | typed hole, patch formula, frame slot, or runtime descriptor field |
| rank, window count, tile count, term count, offset count, parameter/result count, lane/effect/binding/body count | repeated `NativeTemplateGraph` nodes |
| compiler flags, named schedule machine, named vector feature | closed target capability leaf; unsupported names are rejected before bank selection |
| public ABI function shape | graph of ABI param/result/call/return micro-ops |

### Complete-bank micro-op families

The complete bank contains primitive graph families, not bounded whole-shape
products. These family names are the target architecture vocabulary; each name
corresponds to a concrete ASDL source-shape leaf or product in `LalinNative`.

```text
Code value and memory:
  NativeCodeFrameEntryShape
  NativeCodeScalarLoadShape(scalar)
  NativeCodeScalarStoreShape(scalar)
  NativeCodeScalarCopyShape(scalar)
  NativeCodeBytesCopyShape
  NativeCodeBytesMoveShape
  NativeCodeConstShape(scalar)
  NativeCodeUnaryShape(op, scalar)
  NativeCodeBinaryShape(op, scalar)
  NativeCodeCompareShape(cmp, scalar)
  NativeCodeCastShape(op, from_scalar, to_scalar)
  NativeCodeSelectShape(scalar)
  NativeCodeAddressBaseShape
  NativeCodeAddressFieldShape
  NativeCodeAddressIndexShape
  NativeCodeAddressOffsetShape
  NativeCodeLoadShape(scalar_or_bytes_class)
  NativeCodeStoreShape(scalar_or_bytes_class)
  NativeCodeDescriptorFieldShape
  NativeCodeAggregateStepShape
  NativeCodeArrayStepShape
  NativeCodeVariantTagShape
  NativeCodeVariantPayloadShape

Code control and calls:
  NativeCodeJumpShape
  NativeCodeBranchShape
  NativeCodeSwitchStepShape
  NativeCodeTrapShape
  NativeCodeUnreachableShape
  NativeCodeReturnVoidShape
  NativeCodeReturnScalarShape(scalar)
  NativeCodeReturnSretShape
  NativeCodeCallDirectShape
  NativeCodeCallExternShape
  NativeCodeCallIndirectShape
  NativeCodeCallClosureShape

Kernel value and address:
  NativeKernelScalarLoadShape(scalar)
  NativeKernelScalarStoreShape(scalar)
  NativeKernelPointerLoadShape(pointer_scalar)
  NativeKernelPointerStoreShape(pointer_scalar)
  NativeKernelBytesCopyShape
  NativeKernelBytesMoveShape
  NativeKernelLaneAddressBaseShape
  NativeKernelLaneAddressAddIndexShape
  NativeKernelLaneAddressAddStrideShape
  NativeKernelLaneAddressAddOffsetShape

Kernel expressions and predicates:
  NativeKernelExprConstShape(value_class)
  NativeKernelExprCodeValueShape(value_class)
  NativeKernelExprKernelValueShape(value_class)
  NativeKernelExprLaneLoadShape(value_class)
  NativeKernelExprUnaryShape(op, value_class)
  NativeKernelExprBinaryShape(op, value_class)
  NativeKernelExprCastShape(op, from_class, to_class)
  NativeKernelExprCompareShape(cmp, value_class)
  NativeKernelExprSelectShape(value_class)
  NativeKernelAffineInitShape(value_class)
  NativeKernelAffineAddTermShape(value_class)
  NativeKernelAffineFinishShape(value_class)
  NativeKernelPredicateNonZeroShape
  NativeKernelPredicateCompareConstShape(cmp, value_class)
  NativeKernelPredicateRangeShape(value_class)
  NativeKernelPredicateLogicalInitShape
  NativeKernelPredicateLogicalTermShape
  NativeKernelPredicateLogicalFinishShape
  NativeKernelPredicateFloatClassShape(value_class)

Kernel control, effects, and results:
  NativeKernelLoopEnterShape
  NativeKernelLoopStepShape
  NativeKernelLoopExitShape
  NativeKernelBodyEnterShape
  NativeKernelBodyNextShape
  NativeKernelBodyExitShape
  NativeKernelEffectStoreShape
  NativeKernelEffectCopyShape
  NativeKernelEffectScanShape(reducer_class, scan_mode)
  NativeKernelEffectPartitionShape(partition_semantics)
  NativeKernelEffectScatterReduceShape(reducer_class)
  NativeKernelEffectFoldShape(reducer_class)
  NativeKernelEffectCallShape(call_class)
  NativeKernelResultVoidShape
  NativeKernelResultValueShape(value_class)
  NativeKernelResultFindShape(value_class)
  NativeKernelResultReductionShape(reducer_class)
  NativeKernelResultClosedFormShape(value_class)
  NativeKernelResultOriginalControlShape

Stencil producer and access:
  NativeStencilProducerEnterShape
  NativeStencilProducerAxisStepShape(order_class)
  NativeStencilProducerAxisExitShape
  NativeStencilProducerWindowOffsetShape
  NativeStencilProducerTileStepShape
  NativeStencilAccessBaseShape(value_class)
  NativeStencilAccessContiguousShape(value_class)
  NativeStencilAccessIndexedShape(value_class, index_class)
  NativeStencilAccessAffineInitShape(value_class)
  NativeStencilAccessAffineTermShape(value_class)
  NativeStencilAccessFieldOffsetShape(value_class)
  NativeStencilAccessSoAComponentShape(value_class)
  NativeStencilAccessDescriptorFieldShape(value_class, descriptor_field_class)

Stencil point, body, sink, and schedule:
  NativeStencilPointInputShape(value_class)
  NativeStencilPointWindowInputShape(value_class)
  NativeStencilPointConstShape(value_class)
  NativeStencilPointUnaryShape(op, value_class)
  NativeStencilPointBinaryShape(op, value_class)
  NativeStencilPointCastShape(op, from_class, to_class)
  NativeStencilPointPredicateShape(predicate_class, value_class)
  NativeStencilPointCompareShape(cmp, value_class)
  NativeStencilPointSelectShape(predicate_class, value_class)
  NativeStencilBodyEnterShape
  NativeStencilBodyPointShape(value_class)
  NativeStencilBodyExitShape
  NativeStencilSinkStoreShape(store_semantics_class)
  NativeStencilSinkReduceShape(reducer_class, reduce_scope_class)
  NativeStencilSinkScanShape(reducer_class, scan_mode)
  NativeStencilSinkScatterReduceShape(reducer_class, scatter_reduce_conflict_class)
  NativeStencilScheduleScalarShape
  NativeStencilScheduleAutoVectorShape(vector_capability_class)
  NativeStencilScheduleUnrolledShape(unroll_capability_class)
  NativeStencilScheduleVectorShape(vector_capability_class)

ABI and calls:
  NativeAbiParamRegisterShape(scalar_or_pointer_class)
  NativeAbiParamStackShape(value_class)
  NativeAbiParamByRefShape
  NativeAbiResultRegisterShape(scalar_or_pointer_class)
  NativeAbiResultSretShape
  NativeAbiResultVoidShape
  NativeAbiCallDirectShape
  NativeAbiCallExternShape
  NativeAbiCallIndirectShape
  NativeAbiCallClosureShape
  NativeAbiReturnVoidShape
  NativeAbiReturnScalarShape(scalar_or_pointer_class)
  NativeAbiReturnSretShape
```

The class parameters in the family list are themselves closed ASDL values. Their
full target meanings are:

```text
scalar:
  NativeScalarBool8
  NativeScalarInt(width = 8|16|32|64, signedness = signed|unsigned)
  NativeScalarIndex(pointer_width)
  NativeScalarPointer(pointer_width)
  NativeScalarFloat(width = 32|64)

pointer_scalar:
  NativeScalarPointer(pointer_width)

value_class:
  NativeValueVoidClass
  NativeValueScalarClass(scalar)
  NativeValuePointerClass(pointer_scalar)
  NativeValueBytesClass

scalar_or_bytes_class:
  NativeScalarClass(scalar)
  NativePointerClass(pointer_scalar)
  NativeBytesClass

scalar_or_pointer_class:
  NativeScalarClass(scalar)
  NativePointerClass(pointer_scalar)

index_class:
  NativeIndexClass(pointer_width)

op:
  closed ASDL arithmetic/cast/unary/binary/reduction operation leaves from
  LalinCore, LalinValue, LalinCode, or LalinStencil, depending on the family

cmp:
  closed LalinCore.CmpOp leaves

predicate_class:
  NativePredicateNonZeroClass
  NativePredicateCompareConstClass(cmp, value_class)
  NativePredicateRangeClass(value_class)
  NativePredicateLogicalClass
  NativePredicateFloatClass(value_class)

reducer_class:
  NativeReducerClass(reduction_op, value_class)

scan_mode:
  StencilScanInclusive
  StencilScanExclusive

store_semantics_class:
  StencilStoreElementwise
  StencilStoreCopy(copy_semantics)
  StencilStoreScatter(conflict_semantics)
  StencilStorePartition(partition_semantics)

reduce_scope_class:
  StencilReduceScopeDomain
  StencilReduceScopeAxes
  StencilReduceScopeWindow

scatter_reduce_conflict_class:
  StencilScatterReduceSequential
  StencilScatterReduceUniqueIndices
  StencilScatterReduceAtomic(ordering)
  StencilScatterReducePrivatized

descriptor_field_class:
  NativeDescriptorDataField
  NativeDescriptorLengthField
  NativeDescriptorStrideField
  NativeDescriptorBaseField
  NativeDescriptorUserField(kind)        -- kind is a closed descriptor-field leaf, not a string name

vector_capability_class:
  NativeVectorDisabled
  NativeVectorNative
  NativeVectorSSE2
  NativeVectorAVX2
  NativeVectorAVX512F

unroll_capability_class:
  NativeUnrollScalar
  NativeUnrollFixed(factor)              -- factor is drawn from target capability ASDL, not user program demand

order_class:
  StencilProducerForward
  StencilProducerBackward

call_class:
  NativeCallDirectClass
  NativeCallExternClass
  NativeCallIndirectClass
  NativeCallClosureClass
```

No class above carries a source string, field name, full type, full signature,
program id, raw layout size, raw alignment, raw rank, raw count, stride, scale,
step, or compiler flag string. A source family distinction not listed here
requires a closed ASDL leaf for that distinction and an explicit binding site for
all program-specific payloads.

The local-relevance rule is: a template specializes only on facts that it
inspects and that alter source/control/ABI shape. Semantic fragments and selected
supernodes are valid copy-patch units; broad products like
`producer x layout x scalar x input_count x point x sink x schedule` are invalid.
Selected supertemplates are exactly these optimization families:

```text
map-to-store
map-to-reduce / redomap
map-to-scan
horizontal map/reduce consumers over one producer
window-neighborhood map/store
window-neighborhood reduction
field/SoA projection plus scalar arithmetic
predicate/select store
predicate/select reduce
```

Supertemplates are optimizations. They are not the coverage basis and they never
replace the base structural closure proof.

The outdated parts of older enumeration notes are deleted by this document:
there is no residual/TCC glue, no runtime native fallback, no handwritten
assembly stencil source, no coverage value, no exact-cell archive, no LuaJIT
native coupling, and no budget/cap-defined native semantics. Bank-build rejects
describe failures while compiling or verifying declared C template sources. They
do not describe missing compiler architecture.

## Native Code Graph Composition

Code native lowering follows the copy-and-patch paper shape: plan values first,
select stencil configurations second, then copy a CPS continuation graph.
It is not selection of a callable C helper per operation.

The structural path is:

```text
CodeFunc / KernelPlan / StencilInstance
  -> value-location planning
       continuation arguments for hot temporaries
       frame slots for locals, spills, block params, descriptors, aggregates
       constant-pool entries for literal data
  -> NativeTemplateGraph { protocol, frame_layout, constant_pool_layout }
  -> graph nodes with selected stencil configurations
  -> NativeContinuationEdge control edges
  -> NativeValueEdge value-flow facts
  -> NativePatchBinding / relocation bindings
  -> NativeCopyPlan
```

A `NativeRoleRuntimeCall` template is a standalone callable template for smoke
tests, runtime helper calls, and explicitly selected whole-shape supertemplates.
It is not the baseline representation of `CodeInstOp` or `CodeTermOp` leaves
inside a copied graph.

The previous frame-only sketch is only the **spill-all support profile**:
all operands and results live in `NativeFrameSlot` values and every continuation
has signature `void(uint8_t *frame)`. That profile is valid for bootstrap and
correctness, but it is not the final copy-and-patch architecture. The closed
architecture is **location-parametric CPS stencils**: a stencil configuration
states which operands are continuation arguments, which are frame/spill slots,
which are constants, whether the output is passed to the continuation or spilled,
and how many pass-through values must be preserved.

### C stencil extraction modes

Every `NativeTemplateSource` contains C text plus an extraction policy. Extraction
policies describe how the verifier slices a compiled object; they do not define
semantic coverage and they do not introduce bank axes.

```text
NativeExtractStandaloneCallable
  extracts one standalone callable helper template

NativeExtractEntryCallable
  extracts the generated-code entry template
  entry receives the frame pointer and calls the first continuation

NativeExtractPublicAbiAdapter
  extracts a public/export boundary adapter template
  adapter composition is driven by ABI micro-op graph nodes, not by enumerating
  whole `CodeSig` or full ABI projection values as bank axes

NativeExtractContinuationFragment
  extracts a CPS graph fragment template
  first parameter is frame pointer
  remaining parameters are values from the closed logical location protocol
  successor calls are declared continuation relocations

NativeExtractFallthroughFragment
  extracts a fragment with no artificial successor call/jump
  layout must place the fallthrough successor immediately after this template

NativeExtractTerminalContinuation
  extracts the terminal continuation template that returns to the entry/adapter
```

The object verifier checks the compiled object against the declared extraction
policy, entry symbol, continuation ordinals, hole ordinals, and relocation kinds.
It does not infer compiler semantics from bytes.

### Complete manifest construction

Human-authored C chunks: **zero**. Humans author ASDL schemas and methods on
concrete ASDL leaves. Those methods lower semantic values into `NativeTemplateGraph`
nodes and bind holes/frame/runtime facts. The complete-bank manifest is generated
from the closed native micro-op vocabulary in this document.

A complete manifest generator performs this finite enumeration:

```text
for each closed source family F in the complete-bank micro-op vocabulary:
  for each closed target/scalar/control/location class tuple C admitted by the target capability product:
    emit NativeTemplateSource(F, C)
    emit the matching NativeTemplateManifestEntry(F, C)
```

The enumeration never ranges over user programs, full signatures, full types,
field names, layout sizes, ranks, body counts, effect counts, access names,
schedule flag strings, or subset-support shape lists.

`NativeTemplateBankRequest.sources` must match the manifest exactly by template
id, family, chunk class, configuration, extraction, logical signature, declared
hole ordinals, declared continuation ordinals, and declared relocation kinds. A
mismatch is a bank-build bug. Program size changes how many graph nodes are
selected and copied; program size never changes the complete-bank manifest.

For a complete target capability product `C`, the bank count is:

```text
N_complete(C) = Σ over closed source families F
                  |closed class tuples admitted by C for F|
```

This formula is over closed ASDL capability classes only. It is not a Cartesian
product over semantic program facts.

### Logical stencil signatures

A C stencil definition is generated from a logical signature. The C compiler owns
physical register allocation, but the copy-and-patch runtime owns the logical
locations that determine the stencil variant.

```text
NativeStencilSignature {
  frame_param        # always present
  passthroughs       # closed logical pass-through classes
  operands           # closed logical operand-location classes
  continuations      # declared successor function ordinals/signatures
}
```

Logical locations are closed classes:

```text
NativeLocationFrameSlot(value_class)
NativeLocationContinuationArg(value_class)
NativeLocationConstantPool(value_class)
NativeLocationImmediate(scalar_or_pointer_class)
NativeLocationRuntimeParam(value_class)
NativeLocationDiscard
```

Logical locations are not physical registers. The target C ABI decides physical
register allocation when compiling the stencil C. If a value is not carried as a
continuation argument, it is carried by frame, constant-pool, immediate, or
runtime-param location classes. The choice is finite and independent of program
identity.

### Complete generator axes

The closed baseline generator axes are exactly:

```text
source micro-op family
closed target class
closed machine scalar/value class
closed operation/control class
closed logical input/output location classes
closed successor shape: next | then/else | case/default-step | call-return | terminal
closed extraction policy
```

The following are not generator axes:

```text
passthrough counts
parameter counts
result counts
body/effect/lane counts
rank/window/tile/term/offset counts
full signatures
full type/layout identities
field names
layout sizes/alignments
stride/scale/step values
schedule/compiler flag strings
```

Pass-through values, parameter lists, result lists, and body/effect/lane lists are
represented by graph repetition and value edges. Stencils that copy or preserve a single value are selected repeatedly rather than
by a pass-through count axis.

### Generated C definition classes

Generated C definitions correspond one-to-one with the complete-bank micro-op
families named above. Whole-program, whole-signature, whole-body, whole-rank, and
whole-layout definitions are not baseline families. Public ABI adapters,
supertemplates, and standalone callables are graph-entry or optimization shapes
built from the same closed classes; they do not authorize arbitrary semantic
objects as family axes.

### Hole ordinals and object relocations

Holes are declared by ordinal in the generator and represented in C by unique
extern symbols. The object parser recovers hole locations from relocation
records, not from ad hoc byte scanning.

```text
NativeHoleOrdinal
NativeExternHoleSymbol
NativePatchFormula
NativePatchSym32
NativePatchSym64
NativePatchPcRel32
```

All patchable values use this mechanism where the target object format supports
it:

```text
frame offsets / stack offsets
literal constants
constant-pool addresses
continuation targets
branch/jump targets
call/runtime symbols
```

Extern-symbol relocation holes are the only current hole-discovery mechanism for
closed-design stencil generators. Byte-pattern scanning is not a verifier input
and is not part of the native bank format.

### Runtime copy-and-patch algorithm

Runtime native compilation performs these steps:

```text
1. Traverse semantic ASDL values to build lowering projections.
   - type/layout facts become Native*LayoutPlan and Native*Projection values
   - ABI/signature facts become ABI micro-op graph inputs
   - loop/access/sink/proof facts become named lowering facets

2. Build the CPS NativeTemplateGraph.
   - each semantic operation lowers to primitive micro-op nodes
   - repeated terms/effects/lanes/parameters/results become repeated nodes
   - frame/spill slots are allocated for locals, block params, descriptors, state, and temps
   - constant-pool entries are allocated for literal/data payloads

3. Select stencil configurations for graph nodes.
   - source micro-op family
   - closed target/scalar/value/operation/control classes
   - closed logical input/output location classes
   - closed successor shape
   - supertemplate only when a declared closed pattern replaces a subgraph contract

4. Depth-first copy selected stencil bytes into executable memory.

5. Elide tail jumps whose successor is the immediately adjacent copied stencil
   and whose edge is not required control redirection.

6. Patch holes using object-derived patch records:
   constants, frame offsets, stack offsets, continuation targets, branch targets,
   calls, runtime symbols, and constant-pool addresses.
```

Remaining jumps after elision correspond to real control redirection: branches,
loops, switches, calls, and non-adjacent continuations.

### Frame protocol

The spill/local/state protocol is a typed frame:

```text
NativeFrameLayout {
  slots: many NativeFrameSlot
  size
  alignment
}

NativeFrameSlot {
  id
  scalar: NativeMachineScalarRep
  offset
  size
  alignment
}
```

Frame layout is an ASDL fact carried by `NativeTemplateGraph` and
`NativeCopyPlan`. It is not a Lua side table. Values that are local variables,
block parameters, spill slots, values crossing calls, descriptor fields,
aggregate storage, loop state, or overflow temporaries have
`NativeValueFrameSlotLocation` and `NativeFrameSlotValueEdge` facts. Values that
remain in the CPS continuation are represented by typed continuation argument
placements and pass-through edges, not by hidden registers.

Frame entries receive `uint8_t *frame` and call the first continuation. Public
ABI adapters, when needed, are separate boundary graphs composed from ABI
param/result/call/return micro-op templates. They map external parameters and
results to frame slots without making the full signature a bank family axis.
Continuation fragments receive `uint8_t *frame` plus the logical continuation
arguments named by their `NativeStencilSignature`. They do not encode physical
registers.

The closed layout algorithm is specified in `Closed Design Decisions` below: it
allocates parameter, result, block-parameter, local, temporary, loop, and effect
state slots in deterministic order, with no baseline slot reuse and a target
frame capability limit.

### Fast region protocol: residence, fallthrough, and bounded fusion

The frame continuation protocol above is the correctness baseline, not the final
performance model. Fast native code requires an explicit ASDL layer before
`NativeTemplateGraph` that groups semantic operations into installable native
regions, chooses boundary residences, and distinguishes fallthrough from real
control transfer. Fusion is not a peephole side table and not a magical property
of the C compiler after copy-patch: if a set of operations should be optimized as
one native unit, that unit must be named by ASDL and selected before bank lookup.

The fast region layer has three jobs:

1. **Boundary residence**: decide where values live at the boundary of a native
   region: public ABI argument/result, frame slot, immediate, constant-pool
   entry, runtime symbol, or discard. Physical register allocation inside a C
   template remains owned by the C compiler. ASDL never promises that a value is
   in `rax` across two independently compiled snippets.
2. **Fallthrough**: distinguish adjacent linear flow from jumps, branches,
   switches, calls, and returns. A fallthrough template has no successor jump in
   its bytes; the installer must lay its successor immediately after it or reject
   the plan.
3. **Bounded fusion**: select closed, finite C stencil families for common
   straight-line and control patterns. The C compiler sees the whole fused body
   and can keep internal temporaries in registers. The bank never enumerates
   user-specific ASTs, value ids, field names, ranks, or unbounded expression
   trees.

The required ASDL vocabulary is:

```text
product NativeFastRegionPlan {
  target          NativeTarget
  public_protocol NativeCallProtocol
  regions         many NativeFastRegion
  entry           NativeFastRegionId
  exits           many NativeFastRegionId
  frame_layout    NativeFrameLayout
}

product NativeFastRegion {
  id        NativeFastRegionId
  origin    NativeFastRegionOrigin
  body      NativeFastRegionBody
  inputs    many NativeRegionValueBinding
  outputs   many NativeRegionValueBinding
  transfer  NativeRegionTransfer
}

sum NativeFastRegionOrigin {
  NativeCodeBlockRegion      { func CodeFuncId, block CodeBlockId }
  NativeCodeTraceRegion      { func CodeFuncId, first CodeInstId, last CodeInstId }
  NativeKernelBodyRegion     { plan KernelPlanId }
  NativeStencilBodyRegion    { instance StencilInstanceId }
  NativeAbiBoundaryRegion    { projection NativeAbiFunctionProjection }
}

sum NativeRegionBoundaryResidence {
  NativeResidencePublicParam  { index number, abi NativeAbiProjection }
  NativeResidencePublicResult { abi NativeAbiProjection }
  NativeResidenceFrameSlot    { slot NativeFrameSlot }
  NativeResidenceImmediate    { scalar NativeMachineScalarRep, coordinate NativePatchCoordinate }
  NativeResidenceConstantPool { entry NativeConstantPoolEntryId }
  NativeResidenceRuntimeSymbol { symbol NativeRuntimeSymbolId }
  NativeResidenceDiscard
}

product NativeRegionValueBinding {
  value      NativeTemplateValueId
  scalar     NativeMachineScalarRep
  residence  NativeRegionBoundaryResidence
}
```

`NativeRegionBoundaryResidence` is a boundary fact. It is not a hidden physical
register file. If two independent templates both need a value, the value crosses
the boundary through one of these residences. If a value should stay in a CPU
register across operations, those operations must be in the same fused C stencil
body so the C compiler owns that register allocation inside the body.

Control transfer is explicit:

```text
sum NativeRegionTransfer {
  NativeRegionFallthrough { to NativeFastRegionId }
  NativeRegionJump        { to NativeFastRegionId }
  NativeRegionBranch      {
    condition NativeTemplateValueId
    then_to   NativeFastRegionId
    else_to   NativeFastRegionId
  }
  NativeRegionSwitch      {
    key        NativeTemplateValueId
    step_shape NativeCodeSwitchStepShape
    cases      many NativeRegionSwitchCase
    default    NativeFastRegionId
  }
  NativeRegionCallReturn  {
    call_symbol    NativeRuntimeSymbolId
    return_to      NativeFastRegionId
  }
  NativeRegionReturn
  NativeRegionTrap
}
```

`NativeRegionFallthrough` is a layout contract, not a patched jump. The region's
selected template must use `NativeExtractFallthroughFragment`, and the C-owned
installer must place the `to` region at the exact end address of the from region.
If layout cannot satisfy this, installation rejects with a typed fallthrough
layout reject. `NativeRegionJump`, branch, switch, and call-return use real
relocations or control stencils.

Bounded fusion is modeled by region-body leaves:

```text
sum NativeFastRegionBody {
  NativeFrameMicroOpRegion {
    family NativeTemplateFamily
  }

  NativeCodeExprRegion {
    shape NativeCodeExprRegionShape
  }

  NativeFastPublicCodeExprRegion {
    abi   NativeFastPublicAbiShape
    shape NativeCodeExprRegionShape
  }

  NativeCodeCompareBranchRegion {
    compare NativeCodeCompareShape
  }

  NativeCodeLoadOpStoreRegion {
    shape NativeCodeMemoryRegionShape
  }

  NativeKernelStepRegion {
    shape NativeKernelStepRegionShape
  }

  NativeStencilPointRegion {
    shape NativeStencilPointRegionShape
  }
}
```

`NativeFrameMicroOpRegion` is the existing baseline node form: one primitive
family, frame-slot operands, continuation transfer. The other leaves are fast
families. They are optimization choices with identical semantics, not fallback
shims. A semantic operation unsupported by any fast region still lowers to the
baseline micro-op region if the baseline semantics exist.

The first required Code fast shapes are intentionally small and finite:

```text
sum NativeCodeExprAtomShape {
  NativeExprInput      { ordinal number, scalar NativeMachineScalarRep }
  NativeExprImmediate  { scalar NativeMachineScalarRep }
  NativeExprConstPool  { scalar NativeMachineScalarRep }
}

sum NativeCodeExprRegionShape {
  NativeExprReturnAtom {
    result NativeMachineScalarRep
    atom   NativeCodeExprAtomShape
  }

  NativeExprReturnUnary {
    result NativeMachineScalarRep
    op     UnaryOp
    src    NativeCodeExprAtomShape
  }

  NativeExprReturnBinary {
    result NativeMachineScalarRep
    op     BinaryOp
    lhs    NativeCodeExprAtomShape
    rhs    NativeCodeExprAtomShape
  }

  NativeExprReturnBinaryImmRhs {
    result NativeMachineScalarRep
    op     BinaryOp
    lhs    NativeCodeExprAtomShape
  }

  NativeExprReturnMulAddImm {
    result NativeMachineScalarRep
    mul_lhs NativeCodeExprAtomShape
    mul_rhs NativeCodeExprAtomShape
  }
}
```

The `NativeExprReturnMulAddImm` family covers the benchmarked
`return a * b + imm` shape. It is not a special Lua peephole: it is a bank family
selected by `CodeInstBinary`/`CodeTermReturn` leaf methods through a typed trace
projection. The immediate is a patch coordinate. Input ordinals refer to region
inputs, not source variable names.

Public ABI fusion is also ASDL, because avoiding the frame for tiny exported
functions requires a C signature visible to the stencil compiler. This must be
bounded by target capability, not inferred from arbitrary signatures:

```text
sum NativeFastPublicAbiShape {
  NativeFastAbi0 { result NativeAbiProjection }
  NativeFastAbi1 { p0 NativeAbiProjection, result NativeAbiProjection }
  NativeFastAbi2 { p0 NativeAbiProjection, p1 NativeAbiProjection, result NativeAbiProjection }
  NativeFastAbi3 { p0 NativeAbiProjection, p1 NativeAbiProjection, p2 NativeAbiProjection, result NativeAbiProjection }
}

product NativeFastRegionCapability {
  public_abi_shapes many NativeFastPublicAbiShape
  code_expr_shapes      many NativeCodeExprRegionShape
  compare_branch_shapes many NativeCodeCompareShape
  switch_step_shapes    many NativeCodeSwitchStepShape
  memory_shapes         many NativeCodeMemoryRegionShape
  kernel_shapes         many NativeKernelStepRegionShape
  stencil_shapes        many NativeStencilPointRegionShape
}
```

A complete bank may include bounded fast public ABI shapes such as scalar
arity-0/1/2/3 returns. These are closed capability classes. They are not a return
of arbitrary full `CodeSig` as a bank axis: only the finite ABI class tuple is an
axis. A tiny scalar expression may be selected as `NativeFastPublicCodeExprRegion`,
which combines that bounded ABI tuple with a bounded expression shape so the C
stencil has the real public C signature and computes the expression directly.
Larger or aggregate signatures use the baseline public ABI adapter graph.

The lowering pipeline becomes:

```text
CodeFunc / KernelPlan / StencilInstance
  -> NativeFastRegionPlan
  -> NativeTemplateGraph
  -> NativeBankInstallPlan
  -> C-owned bank installer
```

The graph builder is responsible for region selection in this order:

1. Build typed value/control facts from the source ASDL leaf methods.
2. Form maximal legal fast regions using only local typed facts and capability
   leaves. No side tables keyed by nodes or strings are allowed; if a fact is
   needed, add it to the ASDL projection.
3. Select fused templates for `NativeCodeExprRegion`, compare-branch, memory,
   kernel, and stencil regions.
4. Select baseline `NativeFrameMicroOpRegion` nodes for remaining semantics.
5. Emit `NativeRegionFallthrough` for adjacent linear fast regions whose selected
   extraction is fallthrough-capable. Emit real control edges for all other
   transfers.

This design makes the performance model explicit:

```text
micro-op graph        correctness baseline, many frame boundaries
fallthrough graph     removes artificial jumps between adjacent templates
fused frame region    removes internal temporary spills within a bounded trace
fused public region   removes public ABI frame setup for bounded scalar shapes
kernel/stencil region lets C see the hot loop/body as one stencil
```

Workers must not implement fusion by scanning Lua arrays for opcode strings,
adding hidden fields to nodes, or patching machine registers across separately
compiled C snippets. The acceptable implementation shape is: add the ASDL
products/sums above, install leaf methods that construct them, generate closed C
families from them, and teach the C-owned installer to enforce fallthrough layout
contracts.

### Continuation protocol

Control flow is represented by `NativeControlEdge` and declared C continuation
symbols:

```text
entry callable --first_continuation--> first node
fragment --next/then/else/backedge/exit symbol--> successor node
terminal continuation --> entry callable return site
```

The compiled object records relocations to extern continuation symbols. During
install, each `NativeRelocationContinuation` is patched to the copied address of
the `NativeControlEdge` successor with the matching symbol. A missing edge or an
undeclared symbol is an install/build reject.

Branch fragments are ordinary C continuation fragments with multiple declared
successor symbols:

```c
extern void LALIN_NEXT_TRUE(uint8_t *frame);
extern void LALIN_NEXT_FALSE(uint8_t *frame);

void branch_i32_frame(uint8_t *frame) {
  if (*(int32_t *)(frame + LALIN_HOLE_COND) != 0) {
    LALIN_NEXT_TRUE(frame);
  } else {
    LALIN_NEXT_FALSE(frame);
  }
}
```

Loops and switches use the same rule: the semantic `CodeTerm*`, `KernelDomain*`,
or `StencilProducer*` leaf declares the finite successor symbols it needs; the
graph builder creates typed edges to concrete successor nodes.

### ABI protocol owns function boundaries

The public call ABI belongs to `NativeCallProtocol` / `CodeSig` / `StencilAbi`,
not to ad hoc Lua casts. The protocol must name:

```text
parameter count and order
parameter scalar rep
parameter extension/truncation policy
result arity: exactly zero (void) or one (single Lalin result)
result scalar/aggregate rep when arity is one
void result when arity is zero
aggregate/sret policy for one aggregate result
float vs integer ABI class
pointer/index width
target ABI kind
```

Lalin has no multiple return values. Although some lower ASDL fields are `many`
for uniform representation, valid Lalin function signatures have result arity
zero or one. Native lowering must treat `#results > 1` as invalid input before
backend codegen, not as a backend feature to implement. Exact zero-or-one-result
ABI classification is specified in `Closed Design Decisions` below.

### Node operand contracts

A template family does not merely say "binary add". It says which typed frame
operands it consumes and produces. A graph node carries that local contract:

```text
NativeTemplateNode {
  id
  entry
  inputs  [many NativeValuePlacement]
  outputs [many NativeValuePlacement]
  bindings [many NativePatchBinding]
}
```

For a baseline binary scalar fragment:

```text
family axes:
  CodeInstBinary leaf/op
  scalar rep
  target/ABI where it changes C source or verification

inputs:
  lhs NativeValueFrameSlotLocation
  rhs NativeValueFrameSlotLocation

outputs:
  dst NativeValueFrameSlotLocation

bindings:
  lhs frame offset hole -> NativePatchFrameOffset(lhs.slot.offset)
  rhs frame offset hole -> NativePatchFrameOffset(rhs.slot.offset)
  dst frame offset hole -> NativePatchFrameOffset(dst.slot.offset)
  successor continuation relocation -> NativeContinuationEdge symbol/target
```

For a constant fragment, the literal value is a patch coordinate, not a family
axis. For a branch fragment, condition slot offset is a patch coordinate and
successors are continuation edges.

### Object verifier contract

Bank build is allowed to run compiler and object tools. Runtime is not.

The verifier must reject any C source whose object does not match the declared
protocol:

```text
missing entry symbol
empty text section
unsupported relocation type
extra unresolved symbol
undeclared continuation/runtime symbol
missing declared continuation relocation
missing declared hole-ordinal relocation
duplicate/ambiguous hole-ordinal relocation
hole relocation outside copied bytes
frame-size hole ordinal missing when declared
relocation outside copied bytes
alignment not represented in NativeTextSection
```

The verifier's normal hole source is object relocation records against declared
extern hole symbols. Marker-byte holes are a temporary bootstrap implementation
only and must not be used for new closed-design stencil generators.

## Patch Coordinates

Patch coordinates are values inserted into holes of a selected binary template.
They are not semantic families.

Patch coordinates include:

```text
scalar immediates
literal constants
null constants
field offsets
SoA component indices
affine coefficients
affine offsets
window offsets
constant strides
branch targets
loop backedges
continuation targets
call targets
frame offsets
frame size
constant-pool addresses
runtime symbol addresses
```

Runtime parameters stay ABI parameters:

```text
base pointers
dynamic lengths
dynamic starts
dynamic stops
dynamic descriptor fields
user scalar values
external reduction initial values
call arguments
closure contexts
```

## Closed Design Decisions

This section is part of the target backend architecture. These choices are not
implementation guidance and are not optional compatibility points; changing them
requires an explicit architecture change.

### CodeSig and public ABI

Lalin function signatures have zero or one result. `CodeSig.results` is a list
only because lower ASDL uses uniform list fields. Native validation must enforce:

```text
#sig.results == 0  -> void result
#sig.results == 1  -> single result
#sig.results > 1   -> invalid Lalin CodeSig before native lowering
CodeTyVoid in params/results -> invalid CodeSig
```

Native public ABI is represented by explicit ASDL projections and ABI micro-op
graph nodes, not by Lua helper inference and not by full-signature bank axes.

ABI value classification uses closed ASDL value classes:

```text
NativeAbiVoidResultClass
NativeAbiScalarValueClass      { scalar, extension }
NativeAbiPointerValueClass     { pointer_scalar }
NativeAbiDescriptorValueClass  { descriptor_class }
NativeAbiByRefValueClass       { mutability_class }
NativeAbiSRetResultClass
```

Program-specific ABI layout facts are not class fields:

```text
descriptor field offsets -> holes / lowering facet
byref pointee type       -> lowering facet
byref alignment          -> hole / lowering facet
sret pointer index       -> ABI graph edge binding
parameter/result order   -> repeated ABI micro-op nodes
```

Canonical Lalin native ABI classification:

```text
bool/int/index/pointer/codeptr/imported-funcptr -> scalar/pointer value class
f32/f64                                         -> scalar float value class
slice/view/bytespan/closure                     -> descriptor value class
array/vector/named/imported-C aggregate         -> by-ref param graph node
single aggregate result                         -> sret graph node + void C return
void result                                     -> void result class
```

The ABI projection is owned by concrete `CodeType` leaves and by `CodeSig` /
`StencilAbi` methods. It is target-specific only where the target ABI changes
classification or extension policy. The graph builder consumes the projection and
emits ABI micro-op nodes; it does not inspect type classes manually and it does
not select a bank family by full `CodeSig`.

Public ABI adapter C entry points are composed from ABI micro-op templates. The
baseline copied graph entry remains uniform `void(uint8_t *frame)`. Internal and
external call fragments use the same ABI value classes and call classes. Lua/FFI
call helpers are test and host-boundary conveniences; they must call through a
typed `NativeCallProtocol` graph that already names the ABI micro-op classes.

### Frame layout algorithm

Every `CodeFunc`, `KernelPlan`, and `StencilInstance` native graph has one
canonical `NativeFrameLayout`. The baseline layout never reuses slots. Slot reuse
is an optimization requiring a separate typed reuse/liveness proof and must not
be part of correctness.

Baseline frame slot allocation is deterministic:

```text
1. ABI parameter slots, in source/ABI order
2. hidden sret/result pointer slot when present
3. canonical result slot when result is scalar/descriptor/byref handle
4. block parameter slots in reverse-postorder block order, parameter order
5. local/addressed storage slots in declaration order
6. instruction result/temp slots in block order, instruction order
7. kernel/stencil loop state slots in semantic owner order
8. reduction/scan/sink state slots in semantic owner order
9. runtime call scratch/result slots in call-site order
```

Each slot has:

```text
size      = CodeType/NativeMachineScalarRep layout size
alignment = natural alignment capped by target stack alignment unless type layout says more
offset    = next aligned offset
```

The final frame size is aligned to the target call-frame alignment. x64 SysV uses
16-byte final alignment. Other targets must define their alignment by target leaf
methods before they are supported.

Frame storage policy is also closed:

```text
frame_size <= NativeFrameStackLimit(target_capability)
  -> entry callable uses stack alloca frame

frame_size > NativeFrameStackLimit
  -> native lowering requires a declared heap-frame runtime capability
```

There is no silent heap fallback. A heap-frame protocol, when added, must be a
new ASDL runtime capability with allocator/free symbols, lifetime, failure mode,
and frame pointer ownership modeled explicitly.

Public ABI adapters use a generated frame-size patch hole, not a bank family
axis:

```c
uint8_t *raw = (uint8_t *)__builtin_alloca(LALIN_HOLE_FRAME_SIZE + ALIGN - 1);
uint8_t *frame = (uint8_t *)(((uintptr_t)raw + ALIGN - 1) & ~(uintptr_t)(ALIGN - 1));
```

The baseline graph entry does not allocate the frame; it receives the frame
pointer. `ALIGN` comes from the closed target frame-alignment capability.
`LALIN_HOLE_FRAME_SIZE` is patched from `NativeFrameLayout.size` in boundary
adapters.

### C frame access and UB rules

Generated C must be valid under the configured optimization flags. The baseline
rules are:

```text
-O3 is allowed
-fno-strict-aliasing is required unless every typed access is proven alias-safe
no -ffast-math for strict float mode
frame base is aligned to NativeFrameLayout.alignment
all typed slot offsets satisfy their slot alignment
slots do not overlap in the correctness baseline
signed wrapping integer ops are expressed through unsigned C operations
shift counts are masked according to CodeIntSemantics
float operations use C operators only for CodeFloatStrict-compatible cases
```

Frame slot C access uses generated typed helpers for the slot projection. Scalar
slots with proven alignment use typed pointer loads/stores. Unaligned or
byte-represented aggregate/descriptor slots use `__builtin_memcpy` helpers.

No C source relies on undefined signed overflow, unaligned typed access,
violating effective type through overlapping slots, or optimizer-visible
out-of-bounds objects. If a stencil cannot be expressed under these rules, the
schema must add the missing projection or runtime capability before code is
written.

### Hole and constant protocol

The architecture uses extern-symbol relocation holes, matching the paper's
MetaVar mechanism. Each generated C stencil declares unique extern symbols for
its hole ordinals. The object parser maps relocations against those symbols back
to `NativeRelocationHoleOrdinal` records and patch formulas.

Closed baseline hole protocol:

```text
frame offsets / field offsets / strides / frame size
  -> relocation to declared hole ordinal symbol

literal scalar values that fit the target relocation formula
  -> relocation to declared hole ordinal symbol

continuation targets / branch targets / call targets / runtime symbols
  -> relocation to declared continuation/call/runtime symbol

float constants / pointer constants / aggregate constants / large scalar constants
  -> constant-pool entries addressed through object relocations
```

Extern-symbol relocation holes are the admitted implementation path for current
stencils. Byte-pattern scanning is not admitted by the verifier contract.

Constant-pool facts are ASDL-owned:

```text
NativeConstantPoolEntry { id, bytes, alignment, scalar_or_type }
NativeConstantPoolLayout { entries, size, alignment }
NativeRelocationConstantPool { offset, entry, addend }
NativePatchConstantPoolEntry { entry, value/type bytes }
```

The copied executable allocation contains code bytes followed by aligned constant
pool bytes. Constant-pool relocations are patched to the copied pool entry. This
is the required baseline for sub-width constants, f32/f64 constants, pointers,
nulls, and aggregate constants. Direct immediate constants are an optimization
only when their verifier contract is target-specific and explicit.

### Object parser and verifier

The implementation uses an internal object parser, not `readelf`, as the source
of truth:

```text
object bytes -> LalinNativeObject ASDL -> verifier -> NativeCompiledTemplate
```

The object parser must model at least:

```text
file format / target triple
sections with flags, offset, size, alignment
symbols with binding, type, section, value, size
relocations with section, offset, type, symbol, addend
raw section bytes
```

The verifier is extraction-leaf owned:

```text
NativeExtractEntryCallable verifies uniform frame-entry symbol and first continuation relocation
NativeExtractContinuationFragment verifies all declared successor relocations
NativeExtractTerminalContinuation verifies no undeclared successor relocation
NativeExtractStandaloneCallable verifies standalone public callable shape
```

For x64 SysV ELF, allowed relocation kinds are closed initially:

```text
R_X86_64_PLT32 / R_X86_64_PC32 -> rel32 continuation/call/local symbol,
                                  or declared runtime symbol
R_X86_64_64                    -> absolute pointer or constant-pool/hole form
R_X86_64_32 / R_X86_64_32S     -> explicit 32-bit hole/constant forms
```

Runtime symbols are admitted only for declared PC-relative call/jump forms that
install patches as rel32. Other relocation kinds are build rejects until the
target leaf explicitly admits and implements them. Relocations must point inside
copied text, declared runtime symbols, declared continuation symbols, declared
call targets, or declared constant-pool entries. Extra unresolved symbols are
rejects.

### Code control lowering

Code control lowering is closed as continuation graph construction:

```text
CodeBlock
  -> block-entry continuation node identity
  -> block params are frame slots
  -> inst nodes in source order
  -> terminator continuation fragment

CodeTermJump
  -> edge-copy chain copies args to destination block-param slots
  -> continuation edge to destination block entry

CodeTermBranch
  -> branch fragment reads condition slot
  -> then/else continuation edges target edge-copy chains
  -> edge-copy chains target block entries

CodeTermSwitch / VariantSwitch
  -> switch fragment has one declared case symbol per case plus default symbol
  -> each case/default targets an edge-copy chain

loops/backedges
  -> ordinary continuation edges to earlier block-entry nodes

CodeTermReturn
  -> zero values: terminal continuation for void result
  -> one value: copy to canonical result/sret slot, terminal continuation
  -> more than one value: invalid Lalin Code before native lowering
```

Edge-copy chains are explicit graph nodes, not hidden parallel-copy side tables.
If copies can overlap, the `CodeBlock`/edge-copy leaf must produce a typed
parallel-copy plan with temporary frame slots. No branch/switch template
specializes on destination block argument count.

### Calls, externs, traps, and runtime symbols

Call lowering uses the same ABI projection as entry generation:

```text
CodeInstCall direct internal
  -> C continuation fragment calls declared extern call-target symbol
  -> install patches call relocation to copied callee entry address

CodeInstCall extern
  -> relocation to NativeRuntimeSymbol / link-resolved external symbol

indirect code pointer / closure call
  -> function pointer and environment loaded from frame/descriptor slots
  -> generated C indirect call under the typed ABI projection

trap
  -> runtime trap symbol call followed by terminal unreachable protocol
```

Runtime symbols are declared in `NativeRuntime`. Each symbol has a typed C
signature/protocol and an address supplied by the embedding runtime or linker.
Runtime symbol addresses are never guessed from global names at install time.

### Kernel and stencil lowering

Kernel and stencil lowering use the same frame/continuation protocol as Code.
There is no separate native semantic mirror.

Closed mapping:

```text
StencilProducer / KernelDomain
  owns loop skeleton continuation fragments
  frame slots: indices, bounds, strides, tile/window state, loop-carried state
  dynamic bounds/strides/descriptors are ABI params or frame slots, not axes

StencilAccessLayout
  owns address/descriptor projection fragments
  frame slots: base pointer, index values, computed address, descriptor fields
  field offsets/strides are patch coordinates when static, runtime params when dynamic

StencilPointExpr / KernelExpr
  owns scalar computation fragments
  recursively composes child value nodes through frame slots

StencilSink / KernelEffect
  owns store/reduce/scan/scatter/copy effect fragments
  frame slots: accumulator state, predicate state, output address/value

StencilSchedule
  owns finite source/control shape: scalar, unroll, vector lane policy, tail policy
  schedule facts are axes only when they alter generated C/control shape
```

Reductions and scans are explicit state machines in the frame:

```text
reduction identity/init slot
accumulator slot(s)
combine fragment owned by reducer leaf
finalize/result fragment owned by sink/result leaf
scan prefix state and output effect owned by scan mode leaf
```

Scatter/scatter-reduce conflict semantics, atomicity, partition/find behavior,
and copy overlap behavior are owned by their existing semantic leaves. Runtime
helpers are declared `NativeRuntimeSymbol` values with typed ABI. The closed
runtime helper classes are trap, heap-frame allocation/free, atomic helper,
external call trampoline, and executable-memory service.

### Supertemplates and optimization

The correctness baseline is frame/continuation composition. Supertemplates are
additional C sources selected by semantic frequency or measured benefit. They
must obey the same ABI, frame, continuation, hole, verifier, and ASDL ownership
rules. A supertemplate is valid only when it has the same externally visible
frame/control contract as the graph it replaces or carries a typed proof/facet
explaining the replacement. It can reduce internal frame loads/stores, but it
cannot change graph-visible semantics.

## Target `LalinNative` ASDL Contract

The complete machine-checkable schema is `lua/lalin/schema/native.lua`. This
section is the architectural contract that schema must satisfy. Do not maintain a
second hand-copied full schema in this document; stale schema prose is a design
bug.

### Identity and target facts

```text
NativeTargetId
NativeRuntimeSymbolId
NativeTemplateId
NativeTemplateFamilyId
NativeTemplateNodeId
NativeTemplateValueId
NativePatchHoleId
NativeExecutableId
NativeBankId
NativeRegisterId
NativeCompleteBankCapabilityId
NativeTemplateSupportDomainId      # subset/test-bank compatibility identity only
NativeFrameSlotId
NativeContinuationSymbolId

NativeArch        = x64 | aarch64
NativeOs          = linux | darwin | windows
NativeAbiKind     = sysv | win64 | aapcs64
NativeEndian      = little | big
NativeTarget      = id, arch, os, abi, pointer_bits, endian
NativeRuntime     = declared runtime symbols
```

`NativeRegister*` exists only as target metadata for ABI descriptions and object
verification. It is not the baseline stencil operand protocol.

### Scalars, ABI facts, and complete capability

```text
NativeMachineScalarRep =
  bool8
  signed/unsigned integer with bit width
  index with bit width
  pointer with bit width
  float with bit width

NativeExtensionPolicy =
  sign_extend | zero_extend | truncate_to_width | preserve_lower_bits

NativeCompleteBankCapability {
  target
  scalar_classes
  value_classes
  logical_location_classes
  code_micro_ops
  abi_micro_ops
  kernel_micro_ops
  stencil_micro_ops
  runtime_helper_classes
  frame_capability
  constant_pool_capability
  atomic_capability
}

NativeCallProtocol =
  void
  scalar return smoke protocol
  ABI micro-op graph protocol
```

`NativeCompleteBankCapability` is the complete-bank manifest root. It contains
closed classes only. It does not contain source-shape samples, `CodeSig`,
`CodeType`, field names, sizes, ranks, counts, strides, schedule flag strings, or
program identities.

`NativeCallProtocol`, `CodeSig`, and `StencilAbi` own public ABI facts as
lowering/projection inputs: argument order, scalar reps, extension policies,
zero-or-one result arity, void result, aggregate/sret policy, and target ABI
class. `CodeSig` and `StencilAbi` lower to ABI micro-op graph nodes. They are not
complete-bank family axes. Lalin does not have multiple return values;
`#results > 1` is invalid for Lalin native lowering. Lua call helpers must not
infer ABI by argument count.

### Stencil generators, C template source, and extraction

```text
NativeStencilGenerator {
  id
  owner_family
  chunk_class
  configuration_class_tuple
  signature owner method
  C builder owner method
}

NativeStencilConfiguration = generator id + closed configuration class tuple
NativeStencilSignature = frame param + logical operands + logical passthroughs + continuations

NativeTemplateSourceManifest {
  complete_capability id
  groups with closed chunk class
  entries with generator/configuration/signature/extraction/hole ordinals
  total_count
}

NativeTemplateSource {
  id
  family
  generator
  configuration
  signature
  extraction: NativeTemplateExtraction
  entry_symbol
  c_text
  declared_holes
}

NativeTemplateExtraction =
  StandaloneCallable
  EntryCallable { frame_alignment_class, first_continuation }
  PublicAbiAdapter { abi_micro_op_graph, frame_size_hole, frame_alignment_class, first_continuation }
  ContinuationFragment { successors }
  TerminalContinuation
```

There is intentionally no `NativeTemplateAssembly` or template language sum.
Every source is C. The manifest is computed before source text is generated;
`NativeTemplateBankRequest.sources` must match it exactly. The extraction leaf
owns how the compiled object is verified and how its bytes/relocations are
admitted to a bank.

### Compiled object facts

```text
NativeTemplateBytes
NativeTextSection
NativeSymbol
NativeRelocationRel32
NativeRelocationAbs64
NativeRelocationRuntimeSymbol
NativeRelocationContinuation
NativeRelocationHoleOrdinal
NativeRelocationConstantPool
NativeCompiledTemplate
NativeEmbeddedTemplate
NativeTemplateBankEntry
NativeTemplateBank
NativeEmbeddedTemplateBank
```

`NativeRelocationContinuation` is the typed artifact produced from a relocation
to a declared extern continuation symbol. Runtime install resolves it through
`NativeControlEdge`, not through string lookup tables. `NativeRelocationHoleOrdinal`
is the typed artifact produced from a relocation to a declared extern hole
symbol; it records the ordinal and patch formula recovered from the object file.

### Frame and value placement

```text
NativeFrameSlot {
  id
  scalar
  offset
  size
  alignment
}

NativeFrameLayout {
  slots
  size
  alignment
}

NativeValueLocation =
  ContinuationArgLocation { arg_index, value_class }
  FrameSlotLocation
  StackSlotLocation
  RuntimeParamLocation
  PatchCoordinateLocation
  ConstantPoolLocation
  MemoryAddressLocation
  (Register/Accumulator locations are metadata/optimization only, not baseline)

NativeValuePlacement = value id, scalar, location
NativeCodeValuePlacementEntry = CodeValueId -> NativeValuePlacement
```

Graph lowering stores spilled/live-across-call/local/state values in typed frame
slots and keeps selected temporaries as typed continuation arguments. Both
placements are ASDL facts, not Lua side tables.

### Graph, control, and copy plan

```text
NativeTemplateGraph {
  target
  protocol
  frame_layout
  nodes
  control_edges
  value_edges
  entry
  exits
}

NativeTemplateNode {
  id
  entry
  inputs
  outputs
  bindings
}

NativeControlEdge =
  fallthrough
  conditional branch
  loop backedge
  exit
  continuation { from, to, symbol }
  runtime call return

NativeValueEdge =
  frame-slot value edge
  runtime-param value edge
  patch-coordinate value edge
  memory-address value edge
  (register/stack/accumulator edges are non-baseline metadata/optimization)

NativeCopyPlan {
  graph
  layout
  frame_layout
  bindings
  protocol
}
```

A copy plan lays out copied byte ranges for graph nodes, then applies patch
bindings and relocations. Continuation relocation patching is driven by the
`NativeContinuationEdge` whose symbol matches the relocation's declared
continuation symbol.

### Patch holes and coordinates

```text
NativeHoleLayout { id, symbol, offset, width, hole }
NativePatchBinding { hole, coordinate }

NativePatchHole =
  Imm32 | Imm64 | Ptr64 | Rel32 | BranchRel32 | CallRel32
  FieldOffset32 | ComponentIndex32 | Stride32
  FrameOffset32 | FrameSize32

NativePatchCoordinate =
  ImmediateI32 | ImmediateI64 | Pointer64
  FieldOffset | ComponentIndex | Stride
  AffineCoeff | AffineOffset | WindowOffset
  BranchTarget | CallTarget
  FrameOffset | FrameSize
  ScalarConst
```

`NativeHoleLayout.offset = -1` is allowed only as a source-level declaration
before object verification. A built/embedded template must contain concrete hole
offsets.

### Build, import, install, and call results

```text
NativeTemplateBankRequest
NativeTemplateBankBuildResult
NativeTemplateBuildReject
NativeEmbeddedBankImportRequest
NativeEmbeddedBankImportResult
NativeInstallInput
NativeInstallResult
NativeInstallReject
NativeExecutable
NativeExecutableCallInput
NativeCallArg
NativeCallReturned
```

Build rejects describe AOT C compilation/object verification failures. Install
rejects describe runtime copy/patch failures. Neither is used to represent
missing compiler architecture.

## Required Methods

Semantic native methods are installed on existing semantic ASDL leaves. Current
method families include:

```text
CodeModule:plan_native_copy(input)
CodeFunc:plan_native_copy(input)
CodeBlock / CodeInst / CodeInstOp / CodeTerm / CodeTermOp append graph nodes
CodePlace*:native_code_address_projection(input)
CodeConst*:native_code_patch_coordinate(input)
CodeType*:native_storage_layout(target, layout_plan)
CodeType*:native_abi_value_class(target)
CodeSig:native_abi_graph_projection(target)
CodeSig:append_native_abi_micro_ops(input)
CodeCallTarget*:native_call_class(sig, target)
CodeCallTarget*:append_native_call_bindings(input, token, projection, args, result)

KernelPlan*:plan_native_copy(input)
KernelPlan*:native_kernel_lowering_input(...)
KernelDomain* / KernelExpr* / KernelEffect* / KernelResult* / KernelProof*
  produce program-specific projections, primitive micro-op graph nodes, and
  node-scoped bindings.

StencilInstance:plan_native_copy(input)
StencilInstance:native_stencil_lowering_input(...)
StencilDescriptor:select_native_template_graph(input)
StencilProducer* / StencilAccess* / StencilPointExpr* / StencilBody* /
StencilSink* / StencilSchedule*
  produce program-specific projections, primitive micro-op graph nodes, and
  node-scoped bindings.
```

Native source-builder methods are installed on the native leaves that own closed
complete-bank micro-op families:

```text
NativeCompleteBankCapability:native_template_manifest()
NativeCompleteBankCapability:native_template_sources()
NativeCompleteBankCapability:native_template_bank_request(bank_id)
NativeCode*MicroOpShape*
NativeAbi*MicroOpShape*
NativeKernel*MicroOpShape*
NativeStencil*MicroOpShape*
  append manifest entries and C stencil sources for closed capability classes.
```

Subset/test bank helpers expose source lists only for tests and target subsets.
Those helpers are not complete-bank source-builder ownership.

Native artifact methods are installed on `LalinNative` leaves:

```text
NativeCompileRequest:compile_native()
NativeCompileSubject*:plan_native_copy(input)
NativeTemplateBankRequest:build_native_bank()      # offline/tooling boundary
NativeEmbeddedBankImportRequest:import_native_bank()
NativeTemplateBank:select_native_template(input)
NativeTemplateBankEntry:select_native_template(input)
NativeTemplateGraph:select_native_copy_plan(input)
NativeCopyPlan:install_native(input)
NativePatchHole*:apply_native_patch(input)
NativePatchCoordinate*:write_native_patch_*(input)
NativeCallProtocol*:call_native_executable(input)
```

Each `*` means concrete sum leaves implement the method. Parent methods are
shared assertions only. Parent methods do not inspect leaf classes, kind strings,
action names, or handler maps to choose behavior.

## Runtime Compilation

Runtime native compilation is copy/patch/install only:

```text
NativeCompileRequest:compile_native()
  -> NativeCompileSubject*:plan_native_copy()
  -> Code / Kernel / Stencil leaf methods
  -> NativeTemplateGraph { frame_layout, control_edges, value_edges }
  -> NativeTemplateGraph:select_native_copy_plan()
  -> NativeCopyPlan
  -> NativeCopyPlan:install_native()
       copy precompiled text and constant-pool bytes
       patch node-scoped NativePatchHole / hole-ordinal bindings
       patch NativeRelocationContinuation, NativeRelocationConstantPool,
       NativeRelocationRuntimeSymbol, and supported local/call relocations
  -> NativeInstallResult
```

Runtime native compilation does not invoke C compilation, TCC, readelf, objdump,
linkers, or ELF parsing. A successful compile returns `NativeCompileResult`. A
missing semantic method throws at the method call. The compiler does not create a
value that means "unimplemented".

## Bank Build

Bank build is AOT artifact construction:

```text
NativeCompleteBankCapability
  -> compute NativeTemplateSourceManifest
  -> generate NativeTemplateBankRequest.sources matching manifest
  -> write each NativeTemplateSource.c_text
  -> gcc/clang -O3 object compile
  -> parse object sections/symbols/relocations
  -> verify NativeTemplateExtraction protocol
  -> resolve declared extern-symbol relocation holes and constant-pool relocs
  -> NativeEmbeddedTemplateBank
```

The generated C bank embeds raw bytes and metadata for binary/debug use. The
generated Lua bridge reconstructs the typed ASDL value:

```text
NativeEmbeddedTemplateBank
NativeEmbeddedTemplate
NativeTemplateBytes
NativeSymbol
NativeRelocation
NativeHoleLayout
NativePatchHole
```

Runtime import immediately reconstructs `NativeTemplateBank` through
`NativeEmbeddedBankImportRequest:import_native_bank()`.

Bank build must reject malformed template artifacts. It must not silently admit a
source with extra unresolved symbols, missing continuation relocs, unsupported
relocation types, missing hole-ordinal relocs, duplicate hole ordinals, or holes
outside copied text.

## Structural Closure Summary

Native template-source closure is structural induction over semantic ASDL, not
native Cartesian enumeration.

Correct closure:

```text
StencilPointExpr leaf methods
StencilAccessLayout leaf methods
StencilSink leaf methods
KernelEffect leaf methods
KernelResult leaf methods
CodeInstOp leaf methods
CodeTermOp leaf methods
  -> base NativeTemplateSource C values for finite identity axes
  -> NativeTemplateGraph composition for recursion/control/value flow
  -> NativeFrameLayout for values
  -> NativeContinuationEdge for control
```

Wrong closure:

```text
producer x layout x scalar x input_count x point x sink x schedule exact cells
register-combination stencil grids as the baseline
handwritten assembly source catalogs
runtime compile-later residual paths
```

SOAC composition remains semantic. `map`, `reduce`, `scan`, partitions, finds,
copies, and scatters are represented by the existing stencil, kernel, and code
ASDL. Native bank entries are implementation templates for those leaves and
their selected graph compositions. Missing source-builder methods are absent
methods, not explicit missing/unsupported result values or placeholder stubs.

## Control Flow

Control flow is copy-patched through typed continuation relocations and
`NativeControlEdge`:

```text
entry first continuation
fallthrough/next continuation
conditional then/else continuation
loop backedge continuation
switch-arm continuation
exit/terminal continuation
runtime call return continuation
```

The C source declares extern continuation symbols. The object file contains
relocations to those symbols. The graph contains typed edges from the source node
to successor nodes with the same `NativeContinuationSymbol`. Install patches the
relocation to the copied successor address.

Target-specific control templates represent branch targets and loop targets as
explicit branch-target patch coordinates. The baseline C protocol is continuation
relocation patching.

## Conformance Requirements

A native backend conforms to this architecture only if all of these statements
hold:

```text
complete-bank manifest is generated from closed micro-op families
complete-bank axes contain no program names, full signatures, full types, raw counts, raw sizes, ranks, strides, scales, steps, or flag strings
semantic ASDL leaves own lowering methods
program-specific facts live in named projection/lowering/layout/facet products
program-specific immediates bind through typed holes or patch formulas
runtime values bind through frame slots, ABI/runtime params, or constant-pool entries
repetition in user programs becomes repeated NativeTemplateGraph nodes
bank build uses generated C sources, object parser, and verifier only
runtime compile copies prebuilt text/pools and patches typed relocations only
missing implementation is an absent method or hard internal error, not a green placeholder value
```

A new target, runtime helper, source family, object relocation, value class, or
ABI class exists only after the schema contains precise ASDL vocabulary and the
verifier/projection contracts for that target concept. It is never encoded as a
string, generic table, optional bag, subset-bank support list, or program-shaped
bank axis.

## Error Model

The native compiler has four failure classes:

```text
user semantic diagnostic before native compilation
bank-build reject while producing/verifying template artifacts
install reject while copying/patching executable code
missing ASDL method as hard internal error
```

No schema value represents missing compiler architecture as a normal result.

## Review Rules

Reject native work when it introduces:

```text
manual class dispatch
kind dispatch
handler maps
side tables
Lua result records
generic context bags
optional soup
nil passthrough
native semantic mirrors
runtime C fallback
runtime compiler/tool invocation
handwritten assembly stencil sources
coverage accounting
exact-cell bank generation
register-fragment baseline
quota-defined semantics
cap-defined semantics
```

The repair is always the same:

```text
add the missing ASDL product, sum, leaf, field, projection, facet, result,
template family, C extraction mode, patch coordinate, patch hole, graph edge,
frame-layout fact, continuation symbol, protocol, then install the method on the
concrete ASDL owner.
```
