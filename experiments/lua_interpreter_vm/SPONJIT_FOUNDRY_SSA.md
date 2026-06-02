# SpongeJIT Lua SSA Compiler — ASDL Semantic Foundry

**Status:** full rewrite design. The old Lua SSA/stencil foundry is quarantined.

---

## Purpose

The foundry/compiler consumes PUC bytecode and evidence into typed Moonlift/PVM ASDL layers, reduces that semantics to canonical normal form, derives contracts/projections, and emits Moonlift kernels.

```text
LuaCompile.Unit(LuaSrc.Window, LuaFact.Evidence)
→ LuaSem.Result
→ LuaNF.Program
→ LuaContract.Contract
→ MoonOut.Kernel
```

It does not build old native stencil banks.

---

## Source of truth

The compiler vocabulary is:

```text
experiments/lua_interpreter_vm/spongejit/ssa_asdl/spongejit_lua_ssa.asdl
```

The guiding discipline is from:

```text
COMPILER_PATTERN.md
PVM_GUIDE.md
```

Rule:

```text
A phase boundary exists only where a real semantic question is answered.
The output vocabulary is narrower than the input vocabulary.
```

---

## Retired old foundry model

The old model was:

```text
opcode sequence + fact bundle
→ table-based SSA
→ Stencil IR
→ x64 native stencil bytes
→ SQLite normal-form bank
→ generated C bank/selector
```

That model is retired for the rewrite.

Old concepts that are no longer architectural targets:

- atom bank;
- L0/L1/L2 stencil layers;
- native x64 byte stencils;
- `stencil_hash` as final identity;
- generated `libsponbank.so` selector;
- copy-link-patch materializer;
- `SponStencilDesc` compatibility;
- backend peepholes compensating for bad SSA.

Old code may be read for semantic reference, but the new compiler does not preserve its APIs or output formats.

---

## New foundry role

The new foundry is a semantic compiler and corpus enumerator.

It may enumerate:

- bytecode windows;
- evidence bundles;
- payload leases;
- loop regions;
- rejection cases;
- normal forms.

It produces:

- ASDL source/evidence test cases;
- semantic lowering results;
- canonical normal forms;
- Moonlift kernels;
- diagnostics about missing semantic coverage.

It does **not** produce runtime fallback artifacts.

Unsupported cases are typed rejections:

```text
LuaSem.Rejected(LuaSem.Rejection(...))
```

not residuals, helper calls, fallback stubs, or old boundaries pretending to be coverage.

---

## Layer responsibilities

### `LuaSrc`

Answers:

```text
What did PUC encode?
```

Contains opcode variants and operands. Opcode names are code-shaping here only.

### `LuaFact` and `LuaRegion`

Answer:

```text
What evidence and structured topology are available?
```

Facts, dependencies, and payload leases are kept distinct.

Important distinction:

```text
observed fact != guard fact != payload lease != runtime bitmask
```

### `LuaSem`

Answers:

```text
What Lua semantics result under this evidence?
```

This is where opcode meaning is consumed.

Responsibilities:

- slot aliasing into virtual slot classes;
- value construction;
- guard insertion;
- write modeling;
- barrier semantics;
- exact boundary/return/jump/loop observations;
- structured rejection.

Forbidden:

- physical residency;
- x64 registers;
- old stencil locations;
- `SponExecCtx` offsets;
- descriptor holes/relocs.

### `LuaNF`

Answers:

```text
What is the least equivalent semantic computation?
```

Responsibilities:

- canonical arithmetic/expression forms;
- dead value removal;
- redundant guard reduction;
- canonical projection obligations;
- semantic equality/dedupe identity.

`LuaNF` is the normal-form boundary. Source opcode chains are aliases, not identity.

### `LuaContract`

Answers:

```text
What facts are required, checked, produced, killed, and what projections are owed?
```

The contract is derived from normal form. It is not copied from arbitrary input fact bundles.

### `MoonOut`

Answers:

```text
What Moonlift kernel represents this normal form?
```

Moonlift lowering receives reduced semantics, not bytecode-shaped source.

---

## Fact and payload discipline

Facts are semantic claims. Payload leases are authority to use runtime payload data.

Example: direct table-field access requires an executable bundle, not isolated predicates:

```text
is_table
shape_eq / shape payload
metatable_absent
key_const
field_offset payload
epoch dependencies
```

The compiler must preserve this bundle discipline in ASDL. A payload bit or field offset without its semantic proof is not enough.

---

## Loop-region stance

Loop opcodes are structural control, not scalar facts.

Numeric/generic loops belong in `LuaRegion` as topology:

- prep pc;
- body entry pc;
- loop pc;
- exit pc;
- slot window;
- continue/done edges;
- state slots.

Until a loop region is semantically lowered as a region, individual `FORPREP`/`FORLOOP` opcodes lower to exact boundary observations.

---

## Projection discipline

Projection belongs to exits and control protocols.

The compiler must not default every exit to synced frame. It must state what is live and how it can be reconstructed:

```text
LiveTValue(slot, value)
LiveI64(slot, value)
LiveF64(slot, value)
SyncedSlot(slot)
DeadSlot(slot)
```

Frame sync is one possible projection plan, not the meaning of projection.

---

## Normal-form examples

Repeated accumulator update should not remain opcode-local:

```text
LOAD/guard R0 once
R0' = affine(R0, +sC0, +sC1, +sC2, +sC3)
project/store only at observation
```

not:

```text
load, guard, add, store
load, guard, add, store
load, guard, add, store
load, guard, add, store
```

Equivalent bytecode encodings should collapse when evidence proves equivalent semantics.
