# run55 vs PUC Lua 5.5 — measured speed

Measured on Fedora Linux 44, stock Lua 5.5.0 at `/tmp/lua-5.5.0/src/lua`
vs the `run55` native runner (LuaJIT host, JIT on). The same real source
file run by stock `lua` and by `run55` (stock `luac` -> undump -> native
plans). Medians of 2-3 runs; results verified integer-exact against stock.

## Before the design fix (host-hop loops)

| shape | stock (PUC) | native (run55) | ratio |
|---|---|---|---|
| numeric-for, 10M iters (`sum += i*i`) | 0.04 s | 0.34 s | **8.1x slower** |
| while loop, 10M iters (`sum += i`) | 0.06 s | 1.34 s | **22x slower** |
| recursion, `fib(30)` (~2.7M calls) | 0.03 s | 5.0 s | **165x slower** |
| fresh table + ipairs, 200k calls | 0.08 s | 17.5 s | **218x slower** |

## After the design fix (native loop back-edges + CPS driver)

| shape | stock (PUC) | native (run55) | ratio |
|---|---|---|---|
| numeric-for, 10M iters | 0.04 s | 0.024 s | **1.7x faster** |
| while loop, 10M iters | 0.06 s | 0.022 s | **2.7x faster** |
| recursion, `fib(30)` | 0.03 s | 5.5 s | **183x slower** |
| fresh table + ipairs, 200k calls | 0.09 s | 17.4 s | **193x slower** |

## What changed

Two design corrections:

1. **No host hop per loop iteration.** The original runner cut every
   control edge at a block boundary and the LuaJIT driver re-dispatched
   after each block — a loop iteration crossed the FFI boundary every
   time. Now each loop SCC (strongly connected component of the block
   graph) executes as ONE RX arena: the intra-SCC JMP/FORLOOP back-edges
   are patched to the target block's code address (native `jmp`), and the
   compare fallthrough chains natively into the body. Only the loop exit,
   a call boundary, or a return crosses into the host — once per loop.
   New `opcode_link` bank: `lua55_residual_jmp_link` /
   `lua55_residual_forloop_link` (the back-edge path ends with a patched
   absolute `jmp *%reg`).

2. **The Lua driver is proper CPS.** The imperative `invoke` while-loop
   with a mutable `pc` was replaced by the `InvokeMachine`: named methods
   (`at_pc`, `block`, `call`, `tforcall`, `forprep`, `returned`) with
   strict tail calls as the edges. The machine owns the computation
   state; methods name their successors directly. No capturing
   continuations.

## What remains host-mediated (and why)

- **Recursion / function calls**: the CALL boundary still re-enters the
  host (closure resolution, frame allocation, cell copy, nested machine
  invoke, result copy) — ~12 us per call vs the stock VM's ~75 ns. A
  native proper-tail CPS call boundary is the next step.
- **Generic-for (ipairs/pairs)**: the TFORCALL iterator dispatch is a host
  boundary, and a per-call fresh table (NEWTABLE) trips the cached
  residual's address guard, forcing a re-learn per call. A generic-table
  slow path (no address guard) would remove the re-learn.
- **The library** (`print`, `math.*`, ...) crosses the FFI boundary by
  design (Lua owns genericity).
