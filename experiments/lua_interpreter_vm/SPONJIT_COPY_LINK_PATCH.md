# SpongeJIT Copy-Link-Patch — Retired Architecture

**Status:** retired. This document is kept only to record that copy-link-patch native stencils are no longer the target architecture.

---

## Decision

The SpongeJIT rewrite does **not** use the old Copy-Link-Patch native stencil ABI.

There is no backward compatibility path for:

- native stencil descriptors;
- generated `libsponbank.so` selector tables;
- x86-64 byte stencil banks;
- old data/control relocation metadata;
- old endpoint ABI;
- old materializer/linker runtime;
- old Tier 2 stencil graph fusion planner.

The rewrite target is:

```text
PUC bytecode + evidence
→ LuaSrc / LuaFact ASDL
→ LuaSem
→ LuaNF
→ LuaContract
→ MoonOut.Kernel
→ Moonlift
→ Cranelift
```

---

## Why retired

Copy-link-patch put too much pressure on the wrong boundary. It encouraged the system to preserve or recover semantic facts in backend descriptor/codegen layers.

The new rule is stricter:

```text
SSA consumes semantics completely.
Normal form is semantic identity.
Moonlift/Cranelift handles native code generation.
```

Backend byte patches must not compensate for bad semantic form.

---

## Historical value

The old copy-link-patch work remains useful as historical evidence for:

- which Lua semantics were previously covered;
- which payload leases were needed;
- which projection cases appeared;
- why boundary must not mean fallback;
- why residency must not pollute semantic SSA.

It is not an implementation constraint.

---

## Replacement documents

Use these instead:

| Document | Role |
|---|---|
| `SPONJIT_ARCHITECTURE.md` | Current rewrite architecture |
| `SPONJIT_FOUNDRY_SSA.md` | ASDL semantic compiler/foundry |
| `SPONJIT_RUNTIME_DESIGN.md` | Moonlift-kernel runtime boundary |
| `spongejit/ssa_asdl/spongejit_lua_ssa.asdl` | Compiler vocabulary source of truth |
| `spongejit/ssa_asdl/REWRITE_PLAN.md` | Rewrite plan |
