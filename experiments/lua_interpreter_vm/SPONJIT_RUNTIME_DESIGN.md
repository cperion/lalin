# SpongeJIT Runtime Design — Moonlift Kernel Execution Boundary

**Status:** full rewrite runtime boundary. The old copy-link-patch native-stencil runtime is retired.

---

## Runtime purpose

The runtime consumes compiled Moonlift kernels produced from canonical Lua normal form.

```text
LuaNF.Program + LuaContract.Contract
→ MoonOut.Kernel
→ Moonlift/Cranelift compiled function
→ runtime call
→ typed exit/projection result
```

The runtime does not run SSA, does not inspect opcode semantics, and does not copy/link/patch old SponJIT stencils.

---

## Retired runtime design

The old runtime design was:

```text
native stencil bank
→ online fusion planner
→ copy/link/patch materializer
→ linked image
```

That design is no longer a target.

Retired artifacts:

- native stencil bank as runtime ABI;
- `libsponbank.so` selector as maintained interface;
- `SponStencilDesc` materialization path;
- control/data reloc patching as the primary execution model;
- Tier 2 stencil graph fusion;
- floor/active linked-image model;
- residual/fallback/helper concepts.

The rewrite has no backward compatibility obligation to these artifacts.

---

## New runtime boundary

Runtime input is not bytecode. Runtime input is a compiled kernel with a typed contract.

```text
CompiledKernel = {
  code: Moonlift/Cranelift function,
  contract: LuaContract.Contract,
  projections: MoonOut.Projection*,
  dependency set,
}
```

The runtime may:

- cache compiled kernels;
- choose an already-compiled kernel for a bytecode span;
- provide ABI parameters;
- call the compiled function;
- read typed exit status;
- perform projection/resume according to the kernel contract;
- invalidate kernels on dependency epoch changes.

The runtime may not:

- lower PUC opcodes;
- run LuaSem/LuaNF phases;
- synthesize opcode helper calls;
- infer missing projection recipes;
- patch arbitrary native instructions;
- use old bank descriptors as compatibility fallback.

---

## ABI shape

The exact C/Moonlift ABI is implementation work, but the architectural values are typed by ASDL:

```text
MoonOut.Kernel
MoonOut.Param
MoonOut.Projection
LuaContract.Contract
LuaNF.Exit
LuaNF.Projection
```

The ABI must provide access to required runtime state:

- Lua stack/frame values;
- constants;
- upvalues;
- primitive table for real semantic primitives;
- dependency/epoch state;
- exit result storage.

This is not old `SponExecCtx` compatibility. A new ABI may reuse ideas, but it is designed from `MoonOut` and `LuaContract`.

---

## Exit protocol

Every non-success exit is typed:

- guard exit;
- boundary exit;
- return exit;
- jump exit;
- loop-region exit.

Each exit carries projection obligations. The runtime executes projection exactly as declared; it does not guess.

Projection examples:

```text
LiveTValue(slot, value)
LiveI64(slot, value)
LiveF64(slot, value)
SyncedSlot(slot)
DeadSlot(slot)
```

A frame slot is synchronized only if required by the projection plan or by a true observation. Frame synchronization is not the default representation of Lua state.

---

## Dependencies and invalidation

`LuaContract.Contract` carries dependency obligations derived from the normal form:

- shape epoch;
- metatable epoch;
- const epoch;
- upvalue epoch;
- table epoch;
- call-target epoch;
- GC barrier protocol;
- VM ABI epoch.

Runtime invalidation uses these dependencies. It does not inspect the semantic graph to rediscover them.

---

## Boundary semantics

Boundary is exact VM/language control transfer.

A boundary exit means:

```text
this computation intentionally hands control to the VM/language boundary here
```

It does not mean:

```text
unsupported opcode fallback
```

Unsupported cases do not reach runtime as executable kernels. They are compile-time `LuaSem.Rejected` results.

---

## Primitive calls

Some Lua semantics may require primitive operations, for example:

- write barrier;
- numeric power;
- allocation boundary;
- VM boundary handoff.

A primitive is allowed only when represented as a semantic operation and contract obligation before Moonlift lowering. There is no generic `execute_opcode` helper.

---

## Kernel cache

The runtime may cache compiled kernels by normal-form identity:

```text
key = LuaNF.Program + LuaContract.Contract + ABI version
```

Source opcode windows are aliases/members, not semantic identity.
