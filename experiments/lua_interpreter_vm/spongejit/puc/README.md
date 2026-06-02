# SpongeJIT PUC integration status

There is no maintained PUC runtime integration here.

SpongeJIT's maintained role is the **offline LuaCompile foundry**:

```text
PUC bytecode windows / grammar windows + evidence
→ LuaCompile.Unit
→ LuaNF + LuaContract
→ MoonOut.Kernel + Moonlift source
→ representative bank artifacts
```

PUC bytecode is currently used for side validation/profiling through full operand-bearing corpus windows. It is not a runtime JIT entry point.

The old native-stencil descriptor/bank/materializer path has been retired and removed from maintained flow. Do not resurrect `SponStencilDesc`, `sponbank`, old copy-link-patch descriptors, or C-function tile benchmark APIs.
