# Native Copy-Patch Architecture

This document is the binding architecture for Lalin native compilation.

The filename still contains `RESIDUAL` for historical path stability. The
architecture is residualless. Residual meant undefined compiler work hidden
behind a bag name. That concept is deleted from the native compiler.

The native backend is a C-stencil copy-patch compiler:

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
15. No coverage accounting exists in compiler semantics.
16. No cap defines semantics.
17. Recursive expression, access, and control shape is handled by template graph
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

## Structural Template-Source Closure

`NativeTemplateBankRequest.sources` is the formal native source set for a bank.
It is derived from three inputs only:

```text
closed Family Basis from this document
current Code / Kernel / Stencil ASDL grammar
finite declared native target support domain
  -> NativeTemplateBankRequest.sources
```

Every source in the request is generated C. There is no native assembly source
variant and no runtime C/residual fallback.

The support domain is a finite build-time declaration of facts that change C
stencil shape or object verification:

```text
target architecture / OS / ABI / endianness / pointer width
machine scalar reps: bool8, signed/unsigned ints, index, pointer, f32, f64
call protocols and CodeSig ABI shapes
finite vector lanes, ranks, unroll factors, schedule strategies
declared runtime symbols that a stencil may reference
```

The C compiler owns register allocation. Physical register names, register
transfer stencils, and register protocols are not baseline bank dimensions.
Target register facts may still exist as target/ABI metadata when a platform
model needs to describe a public ABI, but ordinary Code/Kernel/Stencil fragments
communicate through frame slots and continuations.

The closure invariant is structural induction over semantic ASDL values:

```text
for every concrete semantic leaf that can change machine/control shape
and every compatible finite target-support tuple
there is a native source-builder method on that leaf
and that method emits the required NativeTemplateSource C values
```

A missing semantic native method or missing source-builder method is absent on
the ASDL leaf. Calling it naturally fails at the method call site. The compiler
must not install placeholder methods or create explicit `unsupported`,
`unimplemented`, `missing source`, coverage, fallback, or compile-later result
values to keep execution green.

The induction cases are local:

- non-recursive leaves emit their own base C template sources for compatible
  finite axes;
- recursive `StencilPointExpr` leaves compose child point-template nodes and
  value edges instead of requiring a template for the entire expression tree;
- recursive `StencilAccessLayout` leaves compose parent layout/address nodes and
  patch coordinates instead of enumerating every full layout chain;
- `StencilDescriptor` composes producer, accesses, body, sink, schedule, ABI,
  and proof-owned facts into a `NativeTemplateGraph`;
- `CodeBlock` control graphs become `NativeControlEdge` / `NativeValueEdge`
  structure, not exact block cells;
- kernel effect lists and result lists compose effect/result graph nodes, not
  whole-kernel exact cells.

For each leaf family, the source builder must classify every fact it sees into
exactly one of these native roles:

1. **Identity axes** alter C source shape, object control shape, ABI shape, or
   verification contract. Examples: concrete ASDL leaf identity, concrete
   operation ASDL value, machine scalar rep, target ABI, finite rank, finite
   lane count, finite unroll factor, and finite schedule strategy.
2. **Patch coordinates** are values inserted into typed holes after a template
   is selected: scalar constants, field offsets, descriptor offsets, strides,
   frame-slot offsets, frame size, constant-pool addresses, branch/continuation
   targets, call targets, and similar immediates.
3. **Runtime ABI parameters** remain call parameters or descriptor fields:
   base pointers, dynamic lengths, dynamic starts/stops, user scalar values,
   reduction initial values, closure contexts, and external call arguments.
4. **Frame values** are typed `NativeFrameSlot` facts carried by graph value
   edges. They are not promoted into family axes merely because they are live
   across a template.
5. **Control successors** are typed `NativeControlEdge` facts bound to declared
   C continuation symbols. They are not hard-coded symbol addresses in source.

The still-valid lesson from `docs/COPY_PATCH_TEMPLATE_ENUMERATION_NOTES.md` is
local relevance: a template specializes only on facts that it actually inspects
and that alter source/control/ABI shape. Semantic fragments and selected
supernodes are valid copy-patch units; broad products such as
`producer x layout x scalar x input_count x point x sink x schedule` are not.
Selected supertemplates may add extra `NativeTemplateSource` values for common
fused shapes such as map-to-store, redomap, scans, window neighborhoods, or
horizontal consumers. Supertemplates are optimizations. They are not the
coverage basis and they never replace the base structural closure proof.

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

A `NativeRoleRuntimeCall` template is a standalone callable template. It may be
used for smoke tests, runtime helper calls, or explicitly selected whole-shape
supertemplates. It is not the baseline representation of `CodeInstOp` or
`CodeTermOp` leaves inside a copied graph.

The previous frame-only sketch is only the **spill-all support profile**:
all operands and results live in `NativeFrameSlot` values and every continuation
has signature `void(uint8_t *frame)`. That profile is valid for bootstrap and
correctness, but it is not the final copy-and-patch architecture. The closed
architecture is **location-parametric CPS stencils**: a stencil configuration
states which operands are continuation arguments, which are frame/spill slots,
which are constants, whether the output is passed to the continuation or spilled,
and how many pass-through values must be preserved.

### C stencil extraction modes

Every `NativeTemplateSource` contains C text plus an extraction policy:

```text
NativeExtractStandaloneCallable
  whole function body is copied as a standalone callable template

NativeExtractEntryCallable
  uniform generated-code entry, normally void entry(uint8_t *frame)
  calls declared first continuation symbol
  returns after terminal continuation unwinds to it

NativeExtractPublicAbiAdapter
  optional host/export boundary adapter generated from NativeAbiProjection
  public ABI signature is finite only when explicitly in the support domain
  materializes a frame, calls first continuation, maps result back to host ABI

NativeExtractContinuationFragment
  C function signature generated from NativeStencilSignature
  first parameter is frame pointer
  remaining parameters are pass-through values and operand values
  calls or tail-calls declared successor continuation symbols

NativeExtractTerminalContinuation
  C function signature generated from NativeStencilSignature
  returns to the entry/adapter after the continuation chain finishes
```

The object verifier checks the compiled object against the declared extraction
policy. It does not infer semantics from bytes.

### Stencil generators, metavars, and manifest

Human-authored C chunks: **zero**. Humans author ASDL schemas and Lua methods on
concrete ASDL leaves. Those methods define stencil generators. A generator is a
closed ASDL value:

```text
NativeStencilGenerator {
  id
  owner_family
  chunk_class
  metavars          # finite sets
  filter_method     # concrete ASDL leaf method
  signature_method  # concrete ASDL leaf method
  c_builder_method  # concrete ASDL leaf method
}
```

The AOT bank manifest is the exact enumeration of accepted generator
configurations:

```text
for each generator G:
  for each tuple t in cartesian_product(G.metavars):
    if G.filter_method(t):
      emit NativeTemplateManifestEntry(G, t, G.signature_method(t))
```

`NativeTemplateBankRequest.sources` must match the manifest exactly by id,
family, chunk class, metavar tuple, extraction, logical signature, declared hole
ordinals, declared continuation ordinals, and declared relocation kinds. A
mismatch is a bank-build bug. Program size never changes the bank manifest; it
only changes how many times selected stencils are copied into one executable.

The bank count is therefore not a prose estimate:

```text
N_bank(D) = Σ over generators G in support domain D
              |{ t ∈ product(G.metavars) where G.filter(t) }|
```

The generated manifest records `total_count`; tests for a support profile assert
that exact number.

### Logical stencil signatures

A C stencil definition is generated from a logical signature. The C compiler owns
physical register allocation, but the copy-and-patch runtime owns the logical
locations that determine the stencil variant.

```text
NativeStencilSignature {
  frame_param        # always present
  passthroughs       # values preserved across this stencil
  operands           # values consumed by this stencil from continuation args
  continuation       # successor function type/ordinal(s)
}
```

Example generated shapes:

```c
/* output passed to continuation */
void add_i32_arg_arg(uint8_t *frame, PTs..., int32_t lhs, int32_t rhs) {
  int32_t out = (int32_t)((uint32_t)lhs + (uint32_t)rhs);
  CONT_0(frame, PTs..., out);
}

/* output spilled to frame */
void add_i32_arg_slot_spill(uint8_t *frame, PTs..., int32_t lhs) {
  int32_t rhs = load_i32(frame, HOLE_RHS_OFFSET);
  int32_t out = (int32_t)((uint32_t)lhs + (uint32_t)rhs);
  store_i32(frame, HOLE_DST_OFFSET, out);
  CONT_0(frame, PTs...);
}
```

Continuation arguments are a logical protocol, not hand-selected physical
registers. The target C ABI will usually place a bounded number of them in
registers. If the planner cannot keep a value as a continuation argument, it
spills that value to a frame slot and selects a spilled-input/output stencil.

### Stencil configuration axes

The closed baseline generator axes are:

```text
semantic owner leaf / operation
value representation: bool8, signed/unsigned ints, index, pointer, f32, f64,
                      descriptor, byref aggregate handle
operand location: continuation-arg | frame-slot | constant-pool/immediate
output location: continuation-arg | frame-slot
num passthrough integer/pointer values: 0..K_int
num passthrough float values:           0..K_float
control successor shape: next | then/else | case/default | call-return | terminal
target/ABI/support profile
finite schedule/layout/rank/lane axes for kernel/stencil leaves
```

The pass-through bounds `K_int` and `K_float` are explicit support-domain
parameters. They are a bank-size/performance tradeoff, not semantic limits. A
spill-all support domain sets both to zero.

### Closed C definition classes

The generated C definition classes are closed. Each class is a stencil generator
family; each concrete stencil is one accepted metavar tuple.

```text
FrameEntry
  generator count: 1 per generated-code entry protocol
  C shape: void entry(uint8_t *frame)

PublicAbiAdapter
  generator count: explicit finite exported CodeSig/StencilAbi adapters only
  C shape: public ABI signature generated from NativeAbiProjection
  not part of baseline graph lowering

TerminalContinuation
  axes: terminal logical signature, passthrough shape

EdgeCopy / ParallelCopy
  axes: value representation, source location, destination location,
        overlap/temporary strategy

ConstantLoad
  axes: constant representation, destination location
  values are constant-pool entries or relocation holes, never per-literal C chunks

UnaryOp
  axes: UnaryOp, representation, input location, output location, passthrough counts

BinaryOp
  axes: BinaryOp, representation, lhs location, rhs location, output location,
        passthrough counts

CompareOp
  axes: CmpOp, comparable representation, lhs location, rhs location,
        output location, passthrough counts

CastOp
  axes: from representation, to representation, input location, output location

SelectOp
  axes: value representation, condition location, true/false locations,
        output location

AddressMemoryOp
  axes: ptr-offset/load/store/address semantic leaf, value representation,
        address representation, access/layout class, operand locations
  offsets/strides/dynamic bases are holes/frame slots/ABI params, not chunk axes

DescriptorOp
  axes: descriptor kind, field/op, representation, operand/output locations

AggregateVariantOp
  axes: operation, finite layout class, operand/output locations
  aggregate bytes/sizes/offsets are holes or constant-pool entries

CallOp
  axes: call kind, NativeAbiProjection, argument/result locations,
        passthrough/spill policy

ControlOp
  axes: jump, bool branch, switch strategy, trap protocol, unreachable,
        condition/key location, successor shape, passthrough counts
  switch is compare/branch chain unless a finite switch supertemplate is declared

KernelOp
  axes: Kernel semantic leaf × finite scalar/layout/schedule/rank/lane axes ×
        location/passthrough shape

StencilOp
  axes: Stencil semantic leaf × finite scalar/layout/schedule/rank/lane axes ×
        location/passthrough shape

Supertemplate
  axes: explicit finite semantic pattern and the same location/passthrough axes
  correctness requires proof that it replaces the composed graph contract
```

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
1. Traverse semantic graph to plan value locations.
   - continuation args within K_int/K_float budgets
   - frame/spill slots for locals, block params, values crossing calls, overflow temps
   - constant-pool entries for literals/data

2. Traverse again to select stencil configurations.
   - semantic leaf / operation
   - operand locations
   - output location
   - spill/pass-through counts
   - control successor shape
   - supertemplate when a declared pattern matches

3. Build the CPS NativeTemplateGraph.

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
ABI adapters, when needed, are separate boundary stencils that map external
parameters/results to frame slots using `NativeAbiProjection`. Continuation
fragments receive `uint8_t *frame` plus the logical continuation arguments named
by their `NativeStencilSignature`. They do not encode physical registers.

The closed layout algorithm is specified in `Closed Design Decisions` below: it
allocates parameter, result, block-parameter, local, temporary, loop, and effect
state slots in deterministic order, with no baseline slot reuse and a hard stack
frame support-domain limit.

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

This section closes the remaining backend choices. Later implementation may be
phased, but it must not reopen these choices without an explicit architecture
change.

### CodeSig and public ABI

Lalin function signatures have zero or one result. `CodeSig.results` is a list
only because lower ASDL uses uniform list fields. Native validation must enforce:

```text
#sig.results == 0  -> void result
#sig.results == 1  -> single result
#sig.results > 1   -> invalid Lalin CodeSig before native lowering
CodeTyVoid in params/results -> invalid CodeSig
```

Native public ABI is represented by explicit ASDL projections, not by Lua helper
inference. Add/maintain a `NativeAbiProjection` vocabulary with these leaves:

```text
NativeAbiVoidResult
NativeAbiScalarValue      { scalar, extension }
NativeAbiPointerValue     { scalar = pointer-width integer }
NativeAbiDescriptorValue  { layout, fields }
NativeAbiByRefValue       { pointee_ty, mutability, alignment }
NativeAbiSRetResult       { result_ty, pointer_param }
```

Canonical Lalin native ABI classification:

```text
bool/int/index/pointer/codeptr/imported-funcptr -> scalar/pointer value
f32/f64                                         -> scalar float value
slice/view/bytespan/closure                     -> descriptor value
array/vector/named/imported-C aggregate         -> by-ref param
single aggregate result                         -> hidden sret pointer + void C return
void result                                     -> void C return
```

The ABI projection is owned by concrete `CodeType` leaves and by `CodeSig` /
`StencilAbi` methods. It is target-specific only where the target ABI changes
classification or extension policy. The graph builder consumes the projection;
it does not inspect type classes manually.

Public ABI adapter C signatures are generated from this ABI projection. The
baseline copied graph entry remains uniform `void(uint8_t *frame)`. Internal and
external call fragments use the same projection. Lua/FFI call helpers are test
and host-boundary conveniences; they must call through a typed
`NativeCallProtocol` that already names the projection.

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
frame_size <= NativeFrameStackLimit(target/support-domain)
  -> entry callable uses stack alloca frame

frame_size > NativeFrameStackLimit
  -> native lowering is outside that support domain until a typed heap-frame
     runtime allocator protocol is added
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
pointer. `ALIGN` is a finite support-domain axis. `LALIN_HOLE_FRAME_SIZE` is
patched from `NativeFrameLayout.size` in boundary adapters.

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
slots may use typed pointer loads/stores when alignment is proven. Unaligned or
byte-represented aggregate/descriptor slots use `__builtin_memcpy` helpers.

No C source may rely on undefined signed overflow, unaligned typed access,
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
and copy overlap behavior are owned by their existing semantic leaves. If a leaf
requires a runtime helper (for example trap, allocator, or an atomic helper),
that helper is a declared `NativeRuntimeSymbol` with typed ABI.

### Supertemplates and optimization

The correctness baseline is frame/continuation composition. Supertemplates are
additional C sources selected by semantic frequency or measured benefit. They
must obey the same ABI, frame, continuation, hole, verifier, and ASDL ownership
rules. A supertemplate may use fewer frame loads/stores internally, but it must
have the same externally visible frame/control contract as the graph it replaces
or carry a typed proof/facet explaining the replacement.

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
NativeTemplateSupportDomainId
NativeFrameSlotId
NativeContinuationSymbolId

NativeArch        = x64 | aarch64
NativeOs          = linux | darwin | windows
NativeAbiKind     = sysv | win64 | aapcs64
NativeEndian      = little | big
NativeTarget      = id, arch, os, abi, pointer_bits, endian
NativeRuntime     = declared runtime symbols
```

`NativeRegister*` may exist as target metadata for ABI descriptions or future
object verification. It is not the baseline stencil operand protocol.

### Scalars and ABI facts

```text
NativeMachineScalarRep =
  bool8
  signed/unsigned integer with bit width
  index with bit width
  pointer with bit width
  float with bit width

NativeExtensionPolicy =
  sign_extend | zero_extend | truncate_to_width | preserve_lower_bits

NativeCallProtocol =
  void
  legacy scalar smoke protocols
  return scalar
  CodeSig ABI
  StencilAbi
```

The full design requires `NativeCallProtocol` / `CodeSig` / `StencilAbi` to own
all public ABI facts: argument order, scalar reps, extension policies,
zero-or-one result arity, void result, single-result aggregate/sret policy, and
target ABI class. Lalin does not have multiple return values; `#results > 1` is
invalid for Lalin native lowering. Lua call helpers must not infer ABI by
argument count.

### Stencil generators, C template source, and extraction

```text
NativeStencilGenerator {
  id
  owner_family
  chunk_class
  metavars
  filter owner method
  signature owner method
  C builder owner method
}

NativeStencilMetavar = finite scalar/operation/location/passthrough/control/layout axis
NativeStencilConfiguration = generator id + accepted metavar tuple
NativeStencilSignature = frame param + passthroughs + operands + continuations

NativeTemplateSourceManifest {
  support_domain id
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
  EntryCallable { frame_alignment, first_continuation }
  PublicAbiAdapter { abi_projection, frame_size_hole, frame_alignment, first_continuation }
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
CodeType*:native_abi_projection(target)
CodeType*:native_storage_layout(target, layout_plan)
CodeSig:native_abi_projection(target)
CodeSig:select_native_abi_protocol(target)
CodeCallTarget*:select_native_call_projection(sig, target)
CodeCallTarget*:append_native_call_bindings(input, token, projection, args, result)

KernelPlan*:plan_native_copy(input)
KernelPlan*:native_kernel_lowering_input(...)
KernelDomain* / KernelExpr* / KernelEffect* / KernelResult* / KernelProof*
  produce program-specific projections, finite source shapes, graph nodes, and
  node-scoped bindings.

StencilInstance:plan_native_copy(input)
StencilInstance:native_stencil_lowering_input(...)
StencilDescriptor:select_native_template_graph(input)
StencilProducer* / StencilAccess* / StencilPointExpr* / StencilBody* /
StencilSink* / StencilSchedule*
  produce program-specific projections, finite source shapes, graph nodes, and
  node-scoped bindings.
```

Native source-builder methods are installed on the native leaves that own finite
manifest axes:

```text
NativeTemplateSupportDomain:native_template_manifest()
NativeTemplateSupportDomain:native_template_sources()
NativeTemplateSupportDomain:native_template_bank_request(bank_id)
NativeCodeInstAxis* / NativeCodeTermAxis* / NativeCodeConstAxis*
NativeKernelSourceShapeAxis*
NativeStencilProducerSourceShapeAxis*
NativeStencilAccessSourceShapeAxis*
NativeStencilPointSourceShapeAxis*
NativeStencilBodySourceShapeAxis*
NativeStencilSinkSourceShapeAxis*
NativeStencilScheduleSourceShapeAxis*
  append manifest entries and C stencil sources for support-domain shapes.
```

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
NativeTemplateSupportDomain
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

Branch targets and loop targets may also appear as explicit branch-target patch
coordinates for target-specific control templates, but the baseline C protocol
is continuation relocation patching.

## Implementation Phase Status

The current implementation follows this architecture for the native proof set:

```text
manifest-first NativeTemplateSupportDomain -> NativeTemplateSource generation
extern-symbol hole ordinals and typed relocation declarations
internal ELF64/x64 object parser and verifier
node/instance-scoped patch bindings by hole id or hole ordinal
constant-pool layout/copy/relocation support
NativeAbiProjection and zero-or-one-result CodeSig lowering, including void and sret
canonical frame layout with NativeFrameStackLimit enforcement
Code control/call lowering for jumps, branches, switches, traps, returns, and calls
Code scalar/data lowering for casts, selects, memory, aggregates, variants, and atomics
Kernel source-shape support and NativeKernelLoweringInput graph lowering
Stencil source-shape support and NativeStencilLoweringInput graph lowering
runtime install that copies prebuilt text/pools and patches typed relocations only
```

Remaining expansion work is ordinary ASDL-owned extension of semantic coverage
and target support. New targets, new runtime helpers, new source-shape families,
or new object relocation forms require explicit schema/projection/verifier
support before implementation code is added.

Incomplete future implementation is represented by absent semantic methods or
explicit internal errors at the owning leaf while it is outside the supported
slice; it is not represented by green placeholder stubs.

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
