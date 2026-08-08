# Foundational CPS-on-LuaJIT experiments

These bounded probes established the final CDEF + CPS machine pattern:

```text
ffi.cdef                    exact persistent state
named public method         machine entry
leaf-owned coarse method    hot conditional dispatch
self                        concrete machine
return self:next()          proper-tail CPS edge
```

The finalized authoring API, full design pattern, and useful machine-family examples are in
`experiments/cdef_schema/ARCHITECTURE.md`.

## Foundational examples

- `counter.lua` — raw FFI metatype state with CPS methods.
- `matcher.lua` — method-block matcher using transient parameters.
- `pointer_matcher.lua` — borrowed `const uint8_t *` input.
- `number_scanner.lua` — complete typed physical state and CPS alternatives.
- `method_shapes.lua` — lexical, method, table, and FFI shape comparison.

Run:

```sh
luajit experiments/cps_luajit_vm/test_handwritten.lua
luajit experiments/cps_luajit_vm/method_shapes.lua
luajit experiments/cps_luajit_vm/bench_pointer_matcher.lua
luajit experiments/cps_luajit_vm/bench_number_scanner.lua
```

## Historical probes

`bench.lua`, `scale.lua`, `codegen.lua`, and `load_bench.lua` preserve the measurements for
tail cycles, LuaJIT unrolling limits, generated source, and bytecode-cache loading.

Generated source is needed only when an external program genuinely creates a distinct
machine specialization. It must generate the same cdef + CPS-method shape as a hand-written
machine. `string.dump` is only a cache image.

This directory is isolated research. It is not a supported Lalin backend; Lalin's
maintained backend remains emitted C compiled with GCC.

