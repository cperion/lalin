# Archived Lua JIT Harness Notes

**Status:** archived/experimental harness notes. This directory is not the current maintained SpongeJIT pipeline.

The maintained SpongeJIT path is now the LuaCompile offline foundry:

```text
grammar enumeration + evidence axes
→ LuaCompile.Unit
→ LuaNF + LuaContract
→ MoonOut.Kernel + Moonlift source
→ representative index / alias map / coverage manifest
```

The bytecode dump tools in this area may still be used as corpus/profiling bridges, but old stencil-bank/runtime-library notes are historical only.

Do not treat this harness as evidence that the current tree has a maintained:

- executable stencil bank;
- `libsponbank.so` selector;
- native image materializer;
- PUC runtime JIT path;
- Copy-Link-Patch backend.

Use:

```sh
cd experiments/lua_interpreter_vm/spongejit
make test
make lua-compile-foundry
make test-lua-compile-corpus100
```

for current SpongeJIT checks.
