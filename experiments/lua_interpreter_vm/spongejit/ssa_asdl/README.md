# SpongeJIT Lua SSA ASDL Rewrite

This folder contains the Moonlift/PVM ASDL vocabulary for the planned rewrite of the SpongeJIT Lua SSA compiler.

Primary schema:

- `spongejit_lua_ssa.asdl`

Design authority:

- `COMPILER_PATTERN.md`
- `PVM_GUIDE.md`

Core rule:

```text
PUC opcode mechanics are source vocabulary.
SSA consumes Lua semantics into canonical reduced meaning.
Residency/placement is not semantic identity.
Moonlift kernels are the execution output; old SponJIT descriptors are quarantined.
```

Layer questions:

| Module | Question |
|---|---|
| `LuaSrc` | What did PUC encode? |
| `LuaRegion` | What structured control topology did the bytecode imply? |
| `LuaFact` | What evidence/facts/payload leases are available? |
| `LuaSem` | What does the bytecode mean under that evidence? |
| `LuaNF` | What is the least equivalent semantic computation? |
| `LuaContract` | What facts/exits/projections are required/transferred? |
| `LuaPlace` | Where may already-reduced values live? Optional if Moonlift/Cranelift owns placement. |
| `MoonOut` | What Moonlift kernel boundary is emitted? |
| `LuaCompile` | Top-level compile unit/result vocabulary. |

Non-negotiables encoded by the schema:

- No physical registers in semantic SSA.
- Source opcode variants are dead after `LuaSem`.
- Payload leases are distinct from observed facts and ABI bitmasks.
- Projection obligations are typed exits, not a side string or default synced-frame assumption.
- Boundary is exact language/VM control transfer, not fallback.
- Normal form is the semantic identity/dedupe layer.
- No backward compatibility layer exists in this schema.
- Old SponJIT bank/materializer descriptors are not a target of the rewrite.
