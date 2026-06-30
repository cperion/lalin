# Residual Native Architecture

This document describes the target backend architecture for saturated stencils,
copy-patch compression, runtime C residuals, and AOT C emission.

The key shift is:

```text
Saturate semantics first.
Compress saturated stencil artifacts second.
Materialize everything executable as native code.
```

LuaJIT remains the host, loader, and integration layer. It should not be the
default executor for non-stencil loops. A loop that cannot become a stencil
should normally become a typed C residual compiled by TCC, or reject loudly when
it is not C-lowerable.

## Roles

Each native mechanism has a distinct job.

| Mechanism | Role |
|-----------|------|
| ASDL stencil vocabulary | Exact mathematical semantics of stencil-shaped work |
| GCC/Clang AOT | Builds high-quality exact stencil banks and whole-program C artifacts |
| Copy-patch | Compresses and decompresses saturated stencil artifacts through typed families |
| TCC/libtcc | Runtime JIT for residual C functions and linking against installed stencils |
| LuaJIT | Host, loader, FFI boundary, and optional/debug LuaTrace path |

Copy-patch is not a weaker compiler. It is fast decompression from a compressed
machine-code family to an exact executable stencil artifact.

TCC is not the premium stencil optimizer. It is the native residual executor for
code that is not worth, or not able, to enter the saturated stencil bank.

GCC/Clang remain the best path for expensive AOT stencil generation and
whole-program native C artifacts.

## Current Problem

The existing stencil vocabulary is already close to complete for the important
hot-loop algebra: producers, access layouts, point expressions, sinks,
reducers, predicates, schedules, proofs, and targets are all typed ASDL.

That creates a large exact artifact space:

```text
producer shape
x access layouts
x point expression tree
x sink semantics
x reducer/predicate
x schedule
x proof facts
x target
```

The exact space is semantically correct, but storing one bank entry for every
saturated combination can explode. This is especially visible with recursive
SOAC-style composition, apply chains, field/component projection stacks, arity
growth, and layout spines.

The missing concept is not looser stencils. The missing concept is compressed
storage for exact stencils.

## Core Model

The backend should distinguish semantic identity from storage identity:

```text
StencilDescriptor
  exact semantic identity

StencilInstance
  saturated executable request

StencilCompressionFamily
  reusable storage representative for many exact instances

StencilCompressionCoordinates
  typed values needed to reconstruct one exact instance from the family

StencilDecompressionPlan
  target-specific copy-patch plan

MaterializedStencil
  exact executable native code
```

The invariant is:

```text
family + coordinates = exact saturated artifact
```

Compression may remove detail from storage. It must never remove semantic detail
without producing a typed coordinate that restores that detail before execution.

## Backend Ladder

The target execution ladder should be:

```text
CodeModule
  -> facts
  -> residual module plan
  -> materialization
```

Per function:

```text
1. Exact stencil artifact
2. Compressed stencil artifact decompressed by copy-patch
3. C residual function compiled by TCC
4. Rejected residual
```

LuaJIT/LuaTrace can remain as an explicit debug/probe path, but it should not be
the architectural fallback for normal native execution.

## Residual Function Plan

The backend decision should be an ASDL product/sum, not an option bag or hidden
fallback:

```text
ResidualModulePlan {
  module
  functions [many ResidualFunctionPlan]
  stencil_storage
  c_unit
}

ResidualFunctionPlan =
  ResidualFunctionExactStencil
| ResidualFunctionCompressedStencil
| ResidualFunctionC
| ResidualFunctionRejected
```

Meaning:

```text
ResidualFunctionExactStencil
  function is exactly one selected native stencil artifact

ResidualFunctionCompressedStencil
  function is exactly one saturated stencil artifact represented by a
  compression family plus coordinates

ResidualFunctionC
  function is emitted as residual C and compiled by TCC

ResidualFunctionRejected
  function is neither stencil-materializable nor C-lowerable
```

## Stencil Compression Families

Families should be derived structurally from the existing ASDL descriptor tree.
They should not be hand-written string tags such as `"arity2"`.

Each descriptor leaf can contribute one of:

```text
FamilyFixed(value)
FamilyCoordinate(coordinate)
FamilyRejected(reason)
```

The descriptor method composes those local decisions:

```lua
local view = descriptor:select_stencil_compression(policy)
```

with result:

```text
StencilCompressionView =
  StencilCompressionCovered(family, coordinates)
| StencilCompressionRequiresCompile(reason)
```

This is the important ASDL rule:

```text
The same leaf that owns semantic meaning owns whether one of its fields may
become a compression coordinate.
```

### Fixed Versus Coordinate

Semantic variation usually remains fixed in the family:

```text
store vs reduce
element type
reduction operation
layout constructor
point-expression constructor
copy/scatter conflict semantics
vector schedule form
target ABI
```

Backend-small variation may become a coordinate:

```text
scalar constants
affine offsets
strides, when instruction shape permits it
field offsets
component indices
symbol addresses
immediate values
rel32 targets
```

Depth and arity need policy. Usually they are family structure, not
coordinates:

```text
apply once  -> family ApplyChain1
apply twice -> family ApplyChain2
apply N     -> family ApplyChainN
```

Operators are also policy-sensitive. If an operator is fixed, generated code is
better but family count grows. If an operator is a coordinate, code may need
patched fragments, call thunks, or less optimized instruction sequences.

## SOAC And Recursive Composition

Recursive SOAC-style stacking is exactly where compression is useful.

An exact descriptor may contain:

```text
map(f)
  -> map(g)
    -> map(h)
```

or a layout spine:

```text
field(component(field(component(input))))
```

The saturated descriptor is correct, but AOT storage can explode because each
composition depth, arity, field path, expression shape, schedule, and type
choice multiplies the bank.

The compressed representation should be a structural spine:

```text
StencilCompressionSpine =
  StoreNRange1D
| ReduceRange1D
| ScanRange1D
| PointExprApplyChain
| FieldProjectionChain
| SoAComponentChain
| LayoutAffineSpine
```

Then an exact descriptor derives:

```text
family spine
+ fixed type/schedule/proof facts
+ coordinates for constants, offsets, symbols, and allowed immediates
```

This lets recursive families cover many exact artifacts without weakening the
stencil semantics.

## Copy-Patch As Decompression

Patch holes should be named as decompression coordinates, not semantic holes.

```text
StencilPatchHole =
  PatchImm32
| PatchImm64
| PatchRel32
| PatchPtr
| PatchScalarConst
| PatchFieldOffset
| PatchStride
```

The materializer owns the target-specific encoding:

```lua
coordinate:emit_patch_value(target)
hole:apply_patch(buffer, value)
template:decompress(plan)
```

The decompressed code is an exact materialized artifact for the saturated
descriptor. The executor should not observe a generic stencil. It observes the
exact artifact after decompression.

## C Residuals

A non-stencil function should normally lower to residual C:

```text
CodeFunc
  -> ResidualFunctionC
  -> C function source
  -> TCC in-memory compilation
  -> native function pointer
```

C residuals are for:

```text
irregular loops
branchy scalar code
control-heavy functions
mixed code that calls stencils
loops not covered by current stencil families
glue around decompressed/exact stencils
```

TCC does not need to out-optimize GCC. It needs to compile native residual
control quickly and predictably, with no Lua trace warmup and no Lua loop
execution path.

Residual C may call installed exact or decompressed stencils through host
symbols:

```text
installed stencil symbol
  -> tcc_add_symbol
  -> residual C call
```

This keeps linking in TCC and avoids string-patching source code with raw
addresses.

## AOT GCC Path

The AOT C path has two roles:

1. Build stencil storage:

```text
compression families and exact artifacts
  -> C source
  -> GCC/Clang object code
  -> extracted machine-code templates or exact blobs
  -> embedded bank
```

2. Emit whole-program C artifacts:

```text
CodeModule
  -> C source/header/support
  -> user-controlled GCC/Clang build
```

This path is for maximum quality and native integration. It is separate from
runtime TCC residuals.

## ASDL Surface

The next schema should make these concepts explicit:

```text
ResidualLoweringTarget =
  ResidualTargetNativeTcc
| ResidualTargetAotC
| ResidualTargetLuaTraceDebug

ResidualFunctionPlan =
  ResidualFunctionExactStencil
| ResidualFunctionCompressedStencil
| ResidualFunctionC
| ResidualFunctionRejected

StencilArtifactStorage =
  StencilStoredExactMC
| StencilStoredCompressedMC
| StencilRequiresCompile

StencilCompressionView =
  StencilCompressionCovered
| StencilCompressionRequiresCompile

StencilCompressionFamily
StencilCompressionSpine
StencilCompressionCoordinate
StencilDecompressionPlan
StencilPatchTemplate
StencilPatchHole
```

The method surface should be direct:

```lua
local plan = code_module:select_residual_module(input)
local materialized = plan:materialize_residual_module()

local storage = artifact:select_stencil_storage(policy)
local view = descriptor:select_stencil_compression(policy)
local code = decompression_plan:materialize()

local c = residual_function:emit_c_residual(input)
local fn = c_unit:compile_with_tcc(input)
```

Avoid:

```text
backend option bags
string tags for families
Lua side tables of holes
manual class dispatch
silent LuaJIT fallback
```

## Failure Policy

Misses must be typed.

```text
StencilCompressionRequiresCompile(reason)
ResidualFunctionRejected(reason)
CResidualRejected(reason)
```

A loop that was intended to become a stencil but cannot be represented by an
exact or compressed stencil should either:

1. become C residual, if C residual preserves the function semantics, or
2. reject loudly, if the requested target requires stencil/native storage.

It should not silently fall into a LuaJIT trace-shaped loop.

## Migration Plan

1. Add ASDL for residual module/function decisions.
2. Move current exact stencil selection under `ResidualFunctionExactStencil`.
3. Move current TCC wrapper emission under residual materialization.
4. Add `ResidualFunctionC` using the existing C emitter as the first native
   fallback.
5. Keep LuaJIT block emission only as explicit `ResidualTargetLuaTraceDebug`.
6. Add compression schema without implementing every family.
7. Derive one family first: simple `reduce_n` or `store_n` with scalar constant
   coordinates.
8. Add copy-patch decompression for that family.
9. Extend to SOAC/apply/layout spines once the family method shape is stable.

The first implementation should prove the architecture with one small family,
not attempt a universal patch system.

## Design Law

```text
Exact semantics live in the saturated ASDL stencil descriptor.
Compression families are projections of exact descriptors.
Patch coordinates restore the projection to exactness.
C residuals handle non-stencil native code.
LuaJIT hosts; it does not hide semantic misses.
```
