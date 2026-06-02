# Lua Interpreter VM Experiment

This directory contains the Moonlift-hosted Lua interpreter VM experiment and the SpongeJIT offline foundry.

Important status note: **the interpreter in `src/` is not currently wired to a runtime JIT.** SpongeJIT is an adjacent offline foundry that generates LuaCompile semantic representatives and Moonlift kernels. It does not install native images into `src/vm_loop.lua`.

## What is here

```text
experiments/lua_interpreter_vm/
├── src/                         Moonlift Lua VM/interpreter implementation
├── tests/                       standalone Lua/Moonlift tests
├── benchmarks/                  interpreter and prototype benchmark scripts
├── spongejit/                   SpongeJIT LuaCompile offline foundry
│   ├── lua_compile/             maintained LuaCompile ASDL pipeline
│   ├── ssa_asdl/                ASDL schema and rewrite plan
│   ├── src/                     corpus/profiling bridge utilities only
│   └── Makefile                 LuaCompile foundry/test entry point
├── tools/                       bytecode/corpus harnesses
├── SPONJIT_ARCHITECTURE.md      current SpongeJIT architecture overview
├── SPONJIT_FOUNDRY_SSA.md       LuaCompile semantic foundry design
├── SPONJIT_TIER2_PLANNER_SPEC.md retired stencil planner note
├── SPONJIT_COPY_LINK_PATCH.md   retired copy-link-patch note
└── SPONJIT_RUNTIME_DESIGN.md    MoonOut runtime-boundary design
```

## Current status

### Interpreter VM (`src/`)

The main VM is a Moonlift experiment for implementing Lua runtime structures and bytecode execution as typed regions. It does **not** currently call into SpongeJIT or install native images at runtime.

### SpongeJIT (`spongejit/`)

SpongeJIT is now an offline LuaCompile foundry. The maintained pipeline is:

```text
grammar enumeration + fact/evidence axes
→ LuaCompile.Unit
→ LuaSem / LuaNF / LuaContract
→ MoonOut.Kernel + emitted Moonlift source
→ semantic representative bank artifacts
```

Corpus bytecode is a side validation/profiling input, not the primary generation source. It checks that real full operand-bearing PUC bytecode windows decode and land in the LuaCompile pipeline.

The old path:

```text
src.ssa* → ssa_to_stencil → stencil_* → sponbank/materializer/runtime
```

has been removed from the maintained build/test flow. Old descriptor/bank/materializer compatibility is not a target.

## Running tests

From the repository root, VM tests remain standalone, for example:

```sh
luajit experiments/lua_interpreter_vm/tests/test_vm_components.lua
luajit experiments/lua_interpreter_vm/tests/test_vm_opcode_semantics.lua
luajit experiments/lua_interpreter_vm/tests/test_vm_integration.lua
luajit experiments/lua_interpreter_vm/tests/test_vm_e2e.lua
luajit experiments/lua_interpreter_vm/tests/test_parser_compile.lua
```

SpongeJIT LuaCompile checks:

```sh
cd experiments/lua_interpreter_vm/spongejit
make test                         # maintained LuaCompile suite + no-old-import scan
make lua-compile-foundry           # grammar-generated representative bank
make test-lua-compile-corpus100    # side validation on real full-operand bytecode windows
```

## SpongeJIT generated artifacts

The maintained foundry artifact directory is:

```text
spongejit/build/lua_compile_foundry/
```

Primary files:

```text
lua_compile_representatives.json        # full representative artifact
lua_compile_representative_index.json   # compact representative index
lua_compile_alias_map.json              # source/evidence attempt -> rep/rejection map
lua_compile_grammar_coverage.json       # coverage and rejection ledger
lua_compile_representatives.md          # human summary
```

These artifacts are keyed by `LuaNF + LuaContract`. Source opcode windows and fact bundles are aliases/members, not equivalence identity.

Corpus side validation writes to:

```text
spongejit/build/lua_compile_corpus100/
```

It enforces full operand-bearing PUC events and rejects opcode-only aggregate aliases.

## Documentation map

| File | Purpose |
|---|---|
| `SPONJIT_ARCHITECTURE.md` | Current LuaCompile/MoonOut overview. |
| `SPONJIT_FOUNDRY_SSA.md` | LuaCompile semantic foundry design. |
| `SPONJIT_RUNTIME_DESIGN.md` | MoonOut runtime boundary; no old bank runtime. |
| `SPONJIT_COPY_LINK_PATCH.md` | Retired old copy-link-patch architecture. |
| `SPONJIT_TIER2_PLANNER_SPEC.md` | Retired old stencil fusion planner. |
| `spongejit/ssa_asdl/spongejit_lua_ssa.asdl` | ASDL vocabulary source of truth. |
| `spongejit/ssa_asdl/REWRITE_PLAN.md` | Rewrite/cutover plan. |

## Non-goals / warnings

- This directory is not a production Lua implementation.
- The Moonlift interpreter VM and SpongeJIT are not one integrated runtime JIT system today.
- Do not use old `make bank`, `sponbank`, stencil, or materializer terminology for the maintained path.
- `tools/sponjit_shadow/` is historical/shadow analysis, not the maintained LuaCompile foundry.
