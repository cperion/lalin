# C Backend SOAC Materialization

The main C backend must not rediscover loop semantics during C lowering. The
SOAC/metastencil graph is the semantic optimization contract; CMat is only the
C-facing materialization of that graph.

## Required pipeline shape

```text
CodeModule
  -> graph / flow / value / memory / effect facts
  -> KernelModulePlan
  -> StencilComputation
       finite producer domain
       + typed access projections
       + pure point/stream expressions
       + algebraic sinks
       + legality/proof facts
  -> CMatFusedKernel
  -> inline StencilStreamOp / StencilSinkOp leaf emission
  -> LalinC.CBackendUnit
  -> emit_c
  -> gcc -O3 / AOT C source
```

`emit_c` output remains the C contract, but it must be produced from a typed
SOAC composition, not from direct kernel-effect emission and not from legacy
`StencilArtifact*` body shapes.

## Ownership

- `LalinStencil` owns computation meaning: producers, accesses, streams, sinks,
  point expressions, predicates, reducers, schedules, legality, proofs, and
  fusion inputs.
- `LalinCMat` owns C materialization decisions: loop axes, loop order, vector
  policy, unroll/interleave, access bindings, stream/sink materialization, and
  fused-kernel records.
- `LalinC` owns final C mechanics: ABI, C types, locals, helpers, labels,
  functions, globals, and final statement forms.
- `emit_c` prints `LalinC`; it is not an optimizer.

## Method doctrine

The active C path is leaf-owned by the SOAC graph:

```lua
function Stencil.StencilStreamMap:lower_c_inline_stream(input) ... end
function Stencil.StencilSinkOpStore:lower_c_inline_sink(input) ... end
function Stencil.StencilSinkOpFold:lower_c_inline_sink(input) ... end
function Stencil.StencilSinkOpScan:lower_c_inline_sink(input) ... end
```

`CMatFusedKernel` keeps the source `StencilComputation` as the contract. There is
no `CMatBody*` compatibility layer and no artifact-to-CMat materialization API.
If a new SOAC shape needs C behavior, add the missing ASDL leaf and install the
method on that leaf.

Outlined `ml_stencil_*` C functions are not the main `emit_c` lowering shape.
The default path is inline SOAC/CMat so GCC sees surrounding control, access
facts, and the data body in one optimization unit.

## Enforced hard-yank rule

Forbidden active paths:

```text
LowerStrategyKernel -> direct KernelEffectStore/Fold/Scan emission
LowerStrategyKernel -> StencilArtifactShape -> CMatBody* -> CBackend blocks
```

Required active path:

```text
LowerStrategyKernel -> StencilComputation -> CMatFusedKernel -> StencilStreamOp/StencilSinkOp leaves -> CBackend blocks
```

`Store`, `Copy`, `Reduce/Fold`, `Scan`, and `ScatterFold` must exercise this path
in tests. `KernelEffectFold` is represented as a fold sink on the computation;
it is not emitted as a direct side effect.
