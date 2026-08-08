# Lua 5.5 trace performance

Measured on Fedora 44, AMD Radeon 780M, GCC 16.1.1. Reference: stock Lua 5.5.0
(`/tmp/lua-5.5.0/src/lua`). Methodology: median of 7 `os.clock` samples over
300,000 executed paths (or guest iterations for the loop), warm installed
residuals, JIT-on and `-joff` runs.

```sh
luajit experiments/copy_patch_cps/lua55_trace/perf_bench.lua jit 300000
luajit experiments/copy_patch_cps/lua55_trace/perf_bench.lua joff 200000
```

## JIT on

| path | native ns | stock 5.5 ns | speedup |
|---|---:|---:|---:|
| opcode 0–10 direct residual | ~13.2 | ~55.9 | 4.2× |
| opcode 0–10 via `Program:execute` | ~13.5 | ~55.9 | 4.1× |
| table ops (GETI+GETFIELD+SETI+SETFIELD+2 MOVE) | ~8.1 | ~31.2 | 3.8× |
| string ops (2 LOADK + 2 guarded MOVE) | ~4.1 | ~23.0 | 5.6× |
| fused numeric loop, per guest iteration | ~0.23 | ~4.3 | 18.2× |

## `-joff` (LuaJIT interpreter only)

| path | native ns | stock 5.5 ns | ratio |
|---|---:|---:|---:|
| opcode 0–10 direct residual | 175 | 63 | 0.36× |
| opcode 0–10 via `Program:execute` | 897 | 63 | 0.07× |
| table ops | 163 | 30 | 0.18× |
| string ops | 42 | 22 | 0.52× |
| fused numeric loop, per guest iteration | 0.50 | 3.5 | 7.1× |

## Reading

- Under JIT the per-path residuals win 3.8–5.8× because the FFI boundary is
  traced away; `Program:execute` adds ~0.3 ns once its dispatch is inlined.
- Under `-joff` the interpreter→native FFI boundary costs roughly 100–900 ns
  per call, so per-path residuals lose to stock. This is expected: native
  transitions are terminal exits, and the win must come from coarse or fused
  work per boundary crossing.
- The fused numeric loop wins in both modes (18× JIT, 7× `-joff`) because the
  single boundary crossing amortizes over 1,000 guest iterations and the
  residual keeps sum/index/limit/step in native registers.
- The recorder/learner itself is native C (`lua55_trace_learn_integer_add_forloop`
  and the per-opcode `lua55_learn_*` stencils); Lua performs only mechanical
  linking after the learner returns.
