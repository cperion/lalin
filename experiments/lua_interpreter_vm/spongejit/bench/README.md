# SpongeJIT measurement notes

The old `sponjit_probe` / `libsponbank.so` benchmark harness belonged to the retired SSA/stencil/bank runtime path and is no longer maintained.

Maintained SpongeJIT measurements should target the LuaCompile foundry:

```sh
cd experiments/lua_interpreter_vm/spongejit
make lua-compile-foundry
make test-lua-compile-corpus100
```

Current meaningful metrics are offline foundry metrics:

```text
grammar windows examined
fact/evidence combinations attempted
LuaCompile successes/rejections
unique LuaNF + LuaContract representatives
alias-map size
MoonOut/Moonlift source compile coverage
corpus full-operand window validation coverage
```

Future benchmarks should be named around LuaCompile/MoonOut representative execution, not old stencils, sponbank selectors, or copy-link-patch materializers.
