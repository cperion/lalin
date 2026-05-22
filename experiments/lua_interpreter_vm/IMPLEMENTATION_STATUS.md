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
  - dispatch now reads `op/a/b/c/k/bx/sbx` from `ptr(Instr)` fields;
  - no `let instr: Instr = *ip` copy in dispatch.
- Standardized handler signature to include `k: u8`.
- Removed handler-side `Instr` reloads from return handlers.
- Removed arithmetic body `gsub`/expression-template generation.
- Arithmetic hot reads now use `ptr(Value)` field reads instead of `let lhs: Value = L.stack[...]` aggregate reads.
- `LOADKX` now reads the following `EXTRAARG` through `ptr(Instr)` instead of copying an `Instr` product.
- Quickened pseudo-opcodes were removed from the baseline benchmark/constant table.

## Backend limitation found

Scalar field writes to multiple fields of the same `ptr(Value)` destination currently hit backend validation:

```text
ERROR[E0602]: duplicate access `tree:...:store`
```

So destination writes currently remain aggregate assignments such as:

```moonlift
L.stack[base + as(index, a)] = { tag = TAG_INTEGER, aux = 0, bits = bits }
```

This is intentionally left as a backend/compiler limitation boundary. The refactor still removes the most important instruction-fetch aggregate copy and arithmetic operand aggregate reads.

## Current benchmark shape

Command:

```sh
MOONLIFT_VM_COMPARE_REFS=0 luajit experiments/lua_interpreter_vm/benchmarks/bench_vm_steady_state.lua
```

Representative current output:

```text
RETURN  ~10 ns/resume
LOADI   ~6.1 ns/op
LOADK   ~4.1 ns/op
MOVE    ~3.9 ns/op
ADD     ~7.9 ns/op
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
  - The dispatch itself is explicit and scalarized, but the arm list is still text assembled.
- Many non-hot semantic modules still copy `Value` products by value.
- Table, call, metamethod, vararg, closure, concat, and protected-error behavior remain partial/stubbed per `SPEC_STATUS.md`.
- `SPEC_STATUS.md` should be refreshed after module split because some file/line references are stale.
