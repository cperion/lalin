# ADT M1 experiment results

Date: 2026-07-26

Environment:

- LuaJIT `2.1.1767980792`, GC64 enabled
- AMD Ryzen 7 PRO 8840HS
- x86-64 Linux
- CPU frequency not pinned

These results test a hardcoded two-constructor vertical slice, not a generator.
Each timing below is the median of five fresh processes. Construction and direct
sweeps use 1,000,001 nodes. Recursive cases use a complete depth-18 tree with
524,287 nodes and 20 evaluations per process.

## Median timings

| Representation / operation | ns per node visited | elapsed |
|---|---:|---:|
| arena construction | 16.741 | 0.0167 s |
| graph-table construction | 167.961 | 0.1680 s |
| arena `Num` direct sweep | 0.942 | 0.0047 s |
| bucketed-table `Num` direct sweep | 9.081 | 0.0454 s |
| arena `Binop` mutation sweep | 1.731 | 0.0087 s |
| bucketed-table `Binop` mutation sweep | 13.263 | 0.0663 s |
| arena recursive eval, pointer retained | 19.140 | 0.2007 s |
| arena recursive eval, child handles scalarized | 6.637 | 0.0696 s |
| graph-table recursive eval | 71.456 | 0.7493 s |
| arena recursive `V[tag](index)` dispatch | 97.283 | 1.0201 s |
| graph-table recursive `V[tag](node)` dispatch | 62.960 | 0.6602 s |

The broad construction and sweep differences were stable across runs, but the
exact figures should not be treated as portable constants.

## Memory and full GC

For one million graph nodes:

| Representation | Lua heap delta | RSS delta | arena allocation | forced full GC |
|---|---:|---:|---:|---:|
| arena | 19 KiB | 10,484 KiB | 10,485,760 B | 0.117 ms |
| graph tables | 132,819 KiB | 148,648 KiB | 0 B | 59.943 ms |

The bucketed-table sweep baseline grew RSS by about 156,844 KiB because it also
retains per-constructor reference arrays. The arena chunks are allocated with
`malloc`, so Lua heap accounting intentionally excludes their bytes.

Chunk granularity is a real caveat. At only 10,001 total nodes, the two pools
still allocate one complete chunk each: 1,310,720 bytes for roughly 100 KiB of
live struct payload. A 65,536-slot minimum per constructor can be expensive for
schemas with many rare constructors. Chunk shift, tiered first chunks, or a
different directory decomposition needs measurement against a realistic schema.

## Trace and profiler observations

At 300,001 nodes, construction and both constructor-local sweeps each produced
one trace and zero aborts for the arena. Bucketed table sweeps were also one
trace and zero aborts. In-process `jit.p` sampling after setup and warmup reported
the direct sweeps as 100% compiled.

Recursive work behaved differently:

- Recursive runs formed roughly 17-34 traces, with initial call/loop-unroll
  aborts. Packed handles do not make recursive dispatch monomorphic.
- Holding `local s = dir[chunk] + slot` across the first recursive call caused
  transient pointer cdata to survive trace scalarization. Profiling the arena
  evaluator showed about 44% GC time in one isolated run.
- Loading `left` and `right` handles into scalar locals before either recursive
  call made the same evaluator profile as 100% compiled with no sampled GC and
  improved its median from 19.140 to 6.637 ns/node.
- The proposal's exact dense vtable shape, `V[tag](index)`, also profiled as
  compiled after stabilization, but indirect recursive dispatch erased the arena
  advantage: it was slower than the equivalent table vtable here.

## Current verdict

The central arena claims survive the experiment: storage density, GC isolation,
constructor speed, and monomorphic constructor-local sweeps are all compelling on
this machine. The representation is worth pursuing.

Two emitter rules should become architectural requirements rather than advice:

1. Generated recursive code must scalarize every needed field before making a
   call. It must not merely promise that interior pointers remain valid.
2. Dense runtime method vtables should not be presented as a fast recursive path.
   They are an ergonomic fallback. Sweeps, scalarized leaf code, and bucketed
   worklists need to remain the optimized paths.

Not tested yet: sequences/extra arena, attributes, symbols, serialization, reset
throughput, 64-bit handles, wrapper metatypes, SoA constructors, and bucketed
worklists.
