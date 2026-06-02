# Archived SponJIT Shadow Stencil Notes

**Status:** archived design notes for the old shadow simulator. This directory is not the current maintained SpongeJIT bank pipeline.

The current maintained SpongeJIT direction is:

```text
semantic SSA -> Stencil IR -> abstract native-stencil descriptors -> Tier 2 online fusion planner -> future native stencil materializer
```

Do not treat the old shadow stencil vocabulary, C ABI sketches, or materialization API names in this directory as current implementation contracts.

Current contracts live in:

- `experiments/lua_interpreter_vm/SPONJIT_ARCHITECTURE.md`
- `experiments/lua_interpreter_vm/SPONJIT_FOUNDRY_SSA.md`
- `experiments/lua_interpreter_vm/SPONJIT_TIER2_PLANNER_SPEC.md`
- `experiments/lua_interpreter_vm/SPONJIT_COPY_LINK_PATCH.md`
- `experiments/lua_interpreter_vm/SPONJIT_RUNTIME_DESIGN.md`
