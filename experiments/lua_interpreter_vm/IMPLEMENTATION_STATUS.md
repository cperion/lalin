# Lua Interpreter VM Architecture Refactor Status

Implemented after `ARCHITECTURE_FIX_PLAN.md`:

## Done

- Split opcode handlers into `src/op/` modules:
  - `load.lua`
  - `arithmetic.lua`
  - `table.lua`
  - `compare.lua`
  - `call.lua`
  - `loop.lua`
  - `closure.lua`
  - `misc.lua`
- Reduced `src/op_handlers.lua` to an aggregator.
- Scalarized dispatch instruction fetch:
  - dispatch now reads `op` first and selected arms read only the operand fields they need;
  - no `let instr: Instr = *ip` copy in dispatch;
  - hot op arms avoid unconditional `k/bx/sbx` field loads.
- Standardized handler signature to include `k: u8`.
- Removed handler-side `Instr` reloads from return handlers.
- Replaced dispatch forwarding blocks with direct continuation routing for matching signatures (`next = next`, `error = error`, etc.).
  - `resume_parent` still uses one adapter block because its argument name `parent` must be translated to the outer `next` continuation's `frame` parameter.
  - The VM loop deliberately keeps tiny loop-latch forwarding blocks: direct `next = loop` was tested and produced worse code / label-capture hazards with nested imported `loop` blocks.
- Hardened continuation-target resolution against cont-slot cycles caused by environment fill promotion.
- Removed arithmetic body `gsub`/expression-template generation.
- Arithmetic hot reads now use `ptr(Value)` field reads instead of `let lhs: Value = L.stack[...]` aggregate reads.
- Hot load/arithmetic stores use scalar field stores through indexed stack places, avoiding 16-byte aggregate memcpy.
- `Instr` is now a compact Lua 5.5-style 32-bit word (`struct Instr word: u32`) instead of a 20-byte decoded product; dispatch, validation, parser codegen, tests, and benchmarks all pack/decode the same layout.
- Added explicit `bitcast(T, value)` parsing and converted VM f64 payload decode/encode to bitcasts instead of numeric `as(...)` conversions.
- `LOADKX` now reads the following `EXTRAARG` through `ptr(Instr)` instead of copying an `Instr` product.
- Fixed comparative benchmark `Instr` FFI layout/stride and ADD/MMBIN stream shape so numbers are honest.
- Quickened pseudo-opcodes were removed from the baseline benchmark/constant table.

## Backend/codegen notes

Direct `ptr(Value)` multi-field stores previously exposed backend duplicate-store validation in some forms. The safe hot-path idiom is now indexed stack field stores:

```moonlift
let dst: index = base + as(index, a)
L.stack[dst].tag = TAG_NUM
L.stack[dst].aux = 0
L.stack[dst].bits = bits
```

This lowers without aggregate `memcpy` and avoids the duplicate-access issue.

## Current benchmark shape

Command:

```sh
MOONLIFT_VM_COMPARE_REFS=0 luajit experiments/lua_interpreter_vm/benchmarks/bench_vm_steady_state.lua
```

Representative current output:

```text
RETURN  ~10.4 ns/resume
LOADI   ~2.9 ns/op
LOADK   ~2.7 ns/op
MOVE    ~2.8 ns/op
ADD     ~3.2–3.4 ns/op
ADD_int ~3.6 ns/op
```

## Verified

```sh
for t in experiments/lua_interpreter_vm/tests/*.lua; do
  luajit "$t" || exit 1
done

MOONLIFT_VM_COMPARE_REFS=0 \
luajit experiments/lua_interpreter_vm/benchmarks/bench_vm_steady_state.lua
```

All tests pass.

## Remaining architecture debt

- `src/opcodes.lua` still uses a small Lua helper to assemble dispatch switch arms.
  - The dispatch itself is explicit, scalarized, and now mostly direct-continuation routed, but the arm list is still text assembled.
- Some non-hot semantic modules still copy `Value` products by value.
- Table, call, metamethod, vararg, closure, concat, and protected-error behavior remain partial/stubbed per `SPEC_STATUS.md`.
- `SPEC_STATUS.md` should be refreshed after module split because some file/line references are stale.
