# Lalin Architecture

This document describes the active architecture. Historical backend designs and
completed migration assessments are intentionally not retained in `docs/`.

## System model

LLBL is the extensible language workbench. Lalin is its compiled language
member. Lua owns staging and genericity; Lalin programs are monomorphic typed
declarations lowered through checked ASDL.

The two supported authoring paths are:

```text
.lln declaration document
  -> lalin.loader / lalin.syntax.document
  -> LalinTree ASDL

Lua builder API
  -> LLBL staged heads
  -> declaration values
  -> LalinTree ASDL
```

Both paths converge on the same compiler:

```text
LalinTree
  -> type checking
  -> LalinCode
  -> graph / flow / value / memory / effect facts
  -> kernel and schedule plans
  -> Stencil kernel projection
  -> CMat materialization
  -> LOWER function/module assembly
  -> CBackendUnit
  -> emit_c
  -> GCC shared object or user-owned AOT build
```

The canonical C backend boundary is
`lua/lalin/compiler_schema_v2_c_backend.lua:code_result_to_c`. Public compile
APIs route through `lua/lalin/impl/compiler_api.lua`.

## Backend policy

Fused emitted C compiled by GCC at `-O3` is the performance path. The same C
artifact is the AOT path. Stencil and CMat name the deterministic fused-C shape
contract; they are not binary templates.

LuaJIT bytecode emission is removed: the compiled artifact is always emitted C,
cooked with GCC for local JIT-like execution or handed to a user-owned AOT
build. The public surface exposes only the `compile_c_gcc` / emit-C paths.

Binary copy-patch banks, native template installers, and the former Rust /
Cranelift route are deleted. They are not supported, historical, or planned
backend surfaces.

## Semantic phase ownership

ASDL is the compiler's semantic type system. Source, checked, lower, and backend
schemas have different jobs:

- `lua/lalin/schema_v2/code.lua` owns typed code and declarations.
- `graph.lua` and `flow.lua` own control topology and iteration facts.
- `value.lua`, `mem.lua`, and `effect.lua` own semantic analysis facets.
- `kernel.lua` owns selected computation plans.
- `schedule.lua` owns execution-plan choices.
- `stencil.lua` owns fused region semantics and exact provenance.
- `c_materialize.lua` owns deterministic CMat and C-fragment shape contracts.
- `lower.lua` owns consumed lowering decisions and immutable assembly facts.
- `c.lua` owns emitted C backend values, places, blocks, functions, and units.

Concrete ASDL leaves own semantic behavior. Inputs and results are named ASDL
products or unions. Semantic side maps, class/tag dispatch, generic context
bags, nil protocols, and ad hoc result tables are architecture bugs.

The ownership inventory and executable duplicate guard are documented in
`docs/SCHEMA_OWNERSHIP.md`. The binding doctrine is `docs/ASDL_GUIDE.md`.

## Kernel, Stencil, and CMat

Kernel planning identifies typed lanes, bindings, effects, counted domains,
results, and equivalence facts. Stencil projection turns those facts into a
fused computation with an exact iteration and provenance facet. CMat chooses a
deterministic materialized shape. LOWER builds the external-value, memory, exit,
coverage, and namespace environment before CMat emits a C fragment.

Function assembly is immutable: it removes exactly covered baseline blocks,
injects the original replacement-block parameters, preserves predecessor
arguments, retains exits and metadata, and returns typed rejection when the
splice contract cannot be proven.

Multiple sinks are emitted in deterministic computation order. `restrict` is
derived only from declared exact noalias evidence; pointer shape never implies
noalias.

## Memory coordinates

Fused address strength reduction is designed around memory-use coordinates, not
the disconnected carrier/address plans that remain to be deleted. The governing
equation, type forest, gates, and deletion boundary are defined in
`docs/CMAT_MEMORY_COORDINATE_ARCHITECTURE.md`.

The active sequence is:

1. preserve every fused load/store occurrence and its index in a CMat memory-use
   spine;
2. derive an exact coordinate facet from memory and Stencil iteration facts;
3. materialize absolute or cursor-based C addressing as explicit CMat C plan
   alternatives;
4. delete the obsolete Flow/LOWER carrier and synthetic-address vocabulary.

Bounds, alignment, alias capability, mutability, and trap/movement facts remain
orthogonal to address realization.

## LLBL bootstrap

`lua/llbl.lua` is the stage-0 kernel. `lua/llbl/bootstrap.lua` builds the
stage-1 `llbl` dialect and public `llbl.grammar`; the preserved stage-0 grammar
is `llbl.kernel.grammar`. LLBL owns generic regions, heads, fragments, origins,
diagnostics, formatting, indexing, and language composition. Dialects own
semantic meaning.

Hand-written `.lln` files are declaration documents. Types are Lua-evaluated
values in brackets, function bodies use `do ... end`, and top-level Lua chunk
forms are rejected. The language surface is specified in
`docs/LANGUAGE_REFERENCE.md`; workbench mechanics are in `docs/LLBL_GUIDE.md`.

## Repository map

```text
lua/llbl.lua                         LLBL stage-0 workbench
lua/llbl/                            LLBL bootstrap and syntax machinery
lua/lalin/dsl/                       Lalin builder heads
lua/lalin/schema_v2/                 canonical typed schemas
lua/lalin/impl/                      phase and backend methods
lua/lalin/impl/lower_emit_c/         CMat environment, fragment, and assembly
lua/lalin/compiler_schema_v2_c_backend.lua
                                      canonical C backend composition
lua/lalin/impl/compiler_api.lua      public compiler API implementation
lua/lalin/impl/cemit_emit.lua        CBackendUnit C emission
tests/schema_v2/                     typed semantic boundary tests
tests/c_backend/                     emitted-C and GCC execution tests
```

## Validation

Primary gates are:

```sh
luajit tests/run.lua schema_v2
luajit tests/run.lua c_backend
luajit tests/c_backend/test_compile_c_gcc_fresh_process.lua
```

Focused tests must construct ASDL inputs and assert ASDL outputs. GCC tests prove
the final typed C boundary; they do not replace local semantic tests.

## Authoritative documentation

- `docs/ASDL_GUIDE.md` — binding compiler/schema doctrine.
- `docs/DESIGN_BIBLE.md` — long-form design method.
- `docs/LANGUAGE_REFERENCE.md` — public language surface.
- `docs/LLBL_GUIDE.md` — LLBL workbench and region model.
- `docs/CONVENTIONS.md` — repository and naming conventions.
- `docs/SCHEMA_OWNERSHIP.md` — schema ownership and cutover guard.
- `docs/SCHEMA_V2_IMPL_MASTER_PLAN.md` — concise active compiler queue.
- `docs/CMAT_MEMORY_COORDINATE_ARCHITECTURE.md` — current address design.
