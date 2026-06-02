# SpongeJIT Architecture — Moonlift-ASDL Lua SSA Compiler

**Status:** full rewrite architecture. The previous native-stencil bank / copy-link-patch design is quarantined and is no longer a compatibility target.

---

## One-sentence architecture

SpongeJIT is a compiler from PUC Lua bytecode plus typed evidence into canonical Lua semantic normal form, then into Moonlift kernels that Cranelift lowers to native code.

```text
PUC bytecode + evidence
→ LuaSrc / LuaFact ASDL
→ LuaSem ASDL
→ LuaNF ASDL
→ LuaContract ASDL
→ MoonOut.Kernel
→ Moonlift
→ Cranelift
```

The runtime never rediscovers opcode meaning. It runs already-compiled Moonlift output.

---

## Decision

We are doing a full rewrite.

There is **no backward compatibility path** with the old SponJIT descriptor bank, old native x64 stencils, old selector ABI, or copy-link-patch materializer.

Old code is quarantined as historical/reference material until deleted:

```text
spongejit/src/ssa.lua
spongejit/src/ssa_ir.lua
spongejit/src/ssa_lift.lua
spongejit/src/ssa_opt.lua
spongejit/src/ssa_to_stencil.lua
spongejit/src/stencil_ir.lua
spongejit/src/stencil_lower.lua
spongejit/src/stencil_native_x64.lua
spongejit/src/build_bank.lua
spongejit/runtime/sponjit_l1_interpreter.*
```

New architecture starts from the ASDL schema:

```text
spongejit/ssa_asdl/spongejit_lua_ssa.asdl
```

---

## Architectural rule

From `COMPILER_PATTERN.md` and `PVM_GUIDE.md`:

```text
Each boundary consumes semantics into a narrower vocabulary.
Execution consumes decided facts. It does not interpret source structure.
```

For SpongeJIT this means:

```text
PUC opcodes are source vocabulary.
LuaSem consumes opcode semantics.
LuaNF is semantic identity.
Residency/placement is not semantic identity.
Moonlift/Cranelift handles native placement and machine optimization.
```

No backend peephole is allowed to compensate for bad semantic form.

---

## Layer tree

| Layer | ASDL module | Question | Consumes | Produces |
|---|---|---|---|---|
| Source | `LuaSrc` | What did PUC encode? | PUC bytecode shape | typed opcode window |
| Region evidence | `LuaRegion` | What structured control topology is present? | bytecode topology | loop/control regions |
| Evidence | `LuaFact` | What has runtime/foundry proven or leased? | observations | facts, deps, payload leases |
| Semantics | `LuaSem` | What does the bytecode mean under evidence? | opcodes + evidence | virtual semantic values/effects/exits |
| Normal form | `LuaNF` | What is the least equivalent computation? | semantic program | canonical reduced program |
| Contract | `LuaContract` | What facts/projections are required/transferred? | normal form | fact transfer + projection obligations |
| Optional placement | `LuaPlace` | Where may reduced values live? | normal form | non-semantic placement hints |
| Moonlift output | `MoonOut` | What kernel should be emitted? | normal form + contract | Moonlift kernel boundary |
| Compile result | `LuaCompile` | Did compilation succeed? | source unit | normal form or Moon kernel or rejection |

---

## Classification discipline

At each boundary, every field is one of:

- **code-shaping**: decides which semantic handler runs; consumed by phase dispatch;
- **payload**: data still needed downstream;
- **dead**: stripped at the boundary.

Examples:

| Source distinction | Class after semantic lowering |
|---|---|
| `ADDI` vs `ADDK` vs `ADD` | usually dead; consumed into arithmetic meaning |
| source `pc` | payload for exits/projection/debug |
| source slot number | consumed into canonical slot class plus alias metadata |
| fact predicate | consumed into guards/contract |
| payload lease | payload until address/projection lowering consumes it |
| native register | not allowed in semantic layers |

---

## Semantic SSA contract

`LuaSem` is not a low-level codegen IR. It is the semantic consumption layer.

It must model:

- virtual Lua slots;
- semantic `TValue`, `I64`, `F64`, `Bool`, table, closure values;
- guards and success facts;
- writes and fact kills;
- barriers as semantic observations;
- boundaries as exact VM/language control transfer;
- returns and jumps;
- structured rejection for unsupported cases.

It must not model:

- physical registers;
- x64 instructions;
- `gpr0` or `boxed_i64_reg`;
- descriptor relocs;
- `SponExecCtx` offsets;
- old stencil endpoint ABI.

---

## Normal-form contract

`LuaNF` is the equivalence layer.

Dedupe/equality is based on:

```text
LuaNF.Program + LuaContract.Contract
```

not on:

```text
source opcode chain
source fact bundle
old stencil hash
old descriptor key
```

Equivalent source forms must collapse after semantics are consumed. For example, `ADDI`, `ADDK`, and `ADD` may become the same canonical arithmetic shape when evidence proves the same meaning.

---

## Projection and exits

Projection is typed control, not a side string and not a default synced-frame assumption.

Exit forms include:

- guard exit;
- boundary exit;
- return exit;
- jump exit;
- loop-region exit.

Each exit carries explicit projection obligations:

- live `TValue`;
- live `I64` needing boxing;
- live `F64` needing boxing;
- already-synced slot;
- dead slot.

The compiler may sync a frame slot only because a typed projection/observation requires it.

---

## Moonlift lowering

The primary backend is Moonlift.

Moonlift lowering consumes `LuaNF + LuaContract` and emits `MoonOut.Kernel`. It does not receive opcode-shaped source.

Cranelift is expected to handle:

- register allocation;
- instruction selection;
- local arithmetic simplification;
- native machine-code generation.

SpongeJIT remains responsible for:

- Lua semantics;
- fact use;
- canonical normal form;
- projection obligations;
- boundary correctness.

---

## Runtime role

The runtime role is deliberately narrow:

```text
select/obtain compiled Moonlift kernel
prepare ABI inputs
execute kernel
handle typed exit/projection result
invalidate/demote on dependency changes
```

Runtime must not:

- run SSA;
- inspect PUC opcode semantics;
- synthesize fallback opcode helpers;
- copy/link/patch old native stencils;
- preserve old bank/selector compatibility.

---

## Maintained architecture documents

| Document | Status |
|---|---|
| `SPONJIT_ARCHITECTURE.md` | Current full-rewrite overview |
| `SPONJIT_FOUNDRY_SSA.md` | New ASDL semantic compiler/foundry role |
| `SPONJIT_RUNTIME_DESIGN.md` | Moonlift-kernel runtime boundary |
| `SPONJIT_COPY_LINK_PATCH.md` | Retired; no longer target architecture |
| `SPONJIT_TIER2_PLANNER_SPEC.md` | Retired; no stencil graph fusion planner |
| `spongejit/ssa_asdl/REWRITE_PLAN.md` | Rewrite plan |
| `spongejit/ssa_asdl/spongejit_lua_ssa.asdl` | Source of truth for compiler vocabulary |
