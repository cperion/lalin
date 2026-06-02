# SpongeJIT Tier 2 Planner — Retired Architecture

**Status:** retired. The full rewrite does not include a stencil-graph Tier 2 planner.

---

## Decision

The old Tier 2 plan was based on selecting and fusing prebuilt native stencil atoms.

That architecture is retired.

There is no compatibility target for:

- atom streams;
- L0/L1/L2 stencil vocabularies;
- `FusionPlan` over native stencil instances;
- bridge stencils;
- endpoint compatibility planning;
- copy-link-patch materialization;
- floor/active linked images.

The new compiler architecture is:

```text
PUC bytecode + evidence
→ LuaSem
→ LuaNF
→ LuaContract
→ MoonOut.Kernel
→ Moonlift/Cranelift
```

---

## Replacement optimization boundary

Optimization now belongs in two places:

1. **Semantic reduction**

   `LuaSem → LuaNF` consumes opcode mechanics into the least equivalent semantic representation.

   Examples:

   - repeated slot arithmetic becomes canonical expressions;
   - redundant guards collapse;
   - source opcode variants disappear after their meaning is consumed;
   - projection obligations become explicit and minimal.

2. **Moonlift/Cranelift backend optimization**

   Moonlift/Cranelift handles placement, register allocation, instruction selection, and machine-code optimization.

There is no middle layer that fuses old native stencils.

---

## If long-range optimization returns later

Any future long-range optimizer must operate over `LuaNF` / `MoonOut` vocabulary, not over old native stencil atoms.

Allowed future question:

```text
Can multiple LuaNF programs/kernels be composed into a larger normal form before Moonlift lowering?
```

Retired question:

```text
Which old x64 stencil atom variants should be linked together?
```

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
