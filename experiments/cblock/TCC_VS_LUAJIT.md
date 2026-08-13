# CBlock/TCC vs LuaJIT

`bench_tcc_vs_luajit.lua` compares lazy in-memory TCC code with warmed LuaJIT on two workloads.

## Method

```sh
cd experiments/cblock
luajit bench_tcc_vs_luajit.lua
```

Optional arguments select Hailstone input count and sample count:

```sh
luajit bench_tcc_vs_luajit.lua 1000000 7
```

The harness uses median CPU time. Allocation, initialization, CBlock staging, and LuaJIT warmup are outside steady-state samples. The first trivial native invocation measures TCC compilation, relocation, symbol resolution, and one call. Each measured CBlock operation crosses LuaJIT FFI once; all inner work stays in generated C.

The comparison has two workloads:

1. **Hailstone machine population** — nested integer state machines with branches and direct-threaded CBlock blocks.
2. **SAXPY** — one fused loop over one million LuaJIT FFI `double` elements.

Both implementations compute the same outputs, which the harness checks.

## Observed Results

Three fresh-process runs on the current x86-64 development machine produced:

| Measure | Observed range |
|---|---:|
| TCC lazy cook | 1.19–1.34 ms |
| Hailstone CBlock/TCC | 45.9–48.0 M transitions/s |
| Hailstone LuaJIT | 250.9–325.4 M transitions/s |
| Hailstone TCC/LuaJIT time | 5.36–7.09× |
| SAXPY CBlock/TCC | 9.24–9.36 GB/s |
| SAXPY LuaJIT | 31.62–37.28 GB/s |
| SAXPY TCC/LuaJIT time | 3.42–4.01× |

These numbers are local observations, not portable guarantees. CPU frequency, LuaJIT version, TCC version, architecture, and generated shape matter.

## Conclusion

TCC is highly competitive as an **interactive cooker**: approximately one millisecond turns a complete CBlock module into callable native code without files or a subprocess.

TCC is not competitive with warmed LuaJIT for steady-state execution on these workloads. LuaJIT is approximately 3–7 times faster. This is consistent with the different goals of the systems: TCC minimizes compilation work, while LuaJIT performs runtime specialization and machine-code optimization.

The useful execution policy is therefore:

```text
CBlock + TCC      immediate edit/run, tests, REPL-style invocation
CBlock + GCC -O3 optimized long-running execution and AOT artifacts
LuaJIT            strong dynamic-language baseline and host metaprogramming
```

CBlock still contributes semantic value on the TCC path: typed structs, owned regions, explicit frames, direct-threaded blocks, fused pipelines, ordinary C ABI boundaries, and deterministic emitted C. TCC makes that language immediately executable; it does not replace an optimizing backend.

## Places and `let` under TCC

`bench_places.lua` isolates whether the new value/place vocabulary changes TCC code speed.

| Workload | Result |
|---|---:|
| `let` reuse (subexpression used 4× inside a hot C loop) | 1.25–1.26× faster |
| mutable-frame `var`/`store` vs immutable struct threading (wide 8-field state) | 0.22–0.24× (4× slower) |

Interpretation:

- `let` wins because TCC performs essentially no common-subexpression elimination. Materializing one register and reusing it removes redundant arithmetic.
- In-place mutation of a wide `var` struct loses because TCC keeps loads and stores to that memory location and cannot promote it to registers. Immutable value-threaded structs flow through registers instead, so the immutable style is faster under TCC.
- GCC `-O2` promotes both forms to registers; the constant-folding run showed GCC eliminating the entire loop. GCC is the place where mutable frames and places pay off; TCC is not.

Conclusion: the new vocabulary is a language-completeness win (explicit memory, C interop, `seq` control) and `let` is a real TCC speed tool. `var`/place mutation is the right model for parsers, codecs, and C-boundary frames, but it is not a TCC speed technique.
