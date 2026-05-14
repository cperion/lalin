# Moonlift — Agent Guidance

Moonlift is a typed, jump-first compiled language embedded in LuaJIT that
generates native code through Cranelift. Lua is the metaprogramming layer;
Moonlift is the monomorphic native output.

## Build

```sh
cargo build --release          # produces target/release/libmoonlift.so
```

The Rust crate uses `edition = "2024"` (requires nightly). No rust-toolchain
file — the system Rust 1.95+ works.

libmoonlift.so is loaded by `lua/moonlift/back_jit.lua` via FFI. It searches
`target/release/`, `target/debug/`, then system paths. Build `--release` before
running tests.

## Setup

```sh
git submodule update --init    # for .vendor/LuaJIT
luajit -v                      # must have FFI support
```

All scripts set `package.path` to include `./lua/?.lua`. Custom scripts calling
into the compiler must do the same.

## Run .mlua files

```sh
luajit run_mlua.lua path/to/file.mlua       # run in LuaJIT (calls main/run/test)
luajit emit_object.lua input.mlua -o out.o  # compile to .o
luajit emit_shared.lua input.mlua -o out.so # compile to .so
luajit lsp.lua                              # LSP server (stdio)
```

## Test

No test framework — each file is a standalone script:

```sh
luajit tests/test_back_add_i32.lua         # single test
luajit tests/test_mlua_host_pipeline.lua   # integration test
```

The test suite is ~228 files under `tests/`. Tests that use the Rust backend
require `libmoonlift.so` built first. No ordering constraints — run any subset.

## Benchmarks

```sh
luajit benchmarks/bench_*.lua
benchmarks/run_vs_terra.sh [quick]         # compare with Terra
```

## Architecture

- **`lua/moonlift/`** — compiler frontend: PVM/ASDL framework, parser, typechecker,
  tree-to-back lowering, validation, LSP
- **`src/`** — Rust Cranelift backend: JIT (`lib.rs`) + object emission + FFI surface
- **`lua/moonlift/pvm.lua`** — recording phase boundary: the framework driving all phases
- **`lua/moonlift/back_jit.lua`** — Lua-side JIT bridge (loads libmoonlift.so via FFI)
- **`tests/`** — ~228 standalone test scripts, each self-contained, run with `luajit`
- **`lib/`** — standard library (`region_compose.lua`, `grammar.lua`, etc.)
- **`benchmarks/`** — performance benchmarks

Compilation pipeline:
`.mlua` → parse → typecheck → lower (tree-to-back) → validate → JIT/object

## Conventions

- Jump-first control: no `for`/`while`/`break`/`continue` — only
  `block`/`jump`/`yield`/`return`/`emit`/`switch`
- `@{lua_expr}` splices Lua values into Moonlift source positions
- ASDL is the architecture: all meaningful compilation state is interned,
  immutable ASDL values (not strings, callbacks, or side tables)
- `moonlift.host` = high-level builder API; `moonlift.ast` = low-level ASDL
  constructor API; both produce the same ASDL values
- Regions are typed control fragments with named continuation exits composed
  via `emit`. The `region_compose` module provides PEG-style combinators.

## Language cheatsheet

### Types
```
Scalars:  void  bool  i8 i16 i32 i64  u8 u16 u32 u64  f32 f64  index
Pointers: ptr(T)
Views:    view(T)         -- (data, len, stride) descriptor
Structs:  struct Name f: T; ... end
Unions:   union Name a(T) | b(T) end
Func:     func(i32, i32) -> i32        -- function pointer type
```

### Functions
```moonlift
func add(a: i32, b: i32) -> i32
    return a + b
end
```
Parameters may carry modifiers: `noalias readonly writeonly`.

### Control — no for/while/break/continue

Only `block`/`jump`/`yield`/`return`/`emit`/`switch`:

```moonlift
-- Loop via typed block with jump
block loop(i: index = 0, acc: i32 = 0)
    if i >= n then yield acc end
    jump loop(i = i + 1, acc = acc + xs[i])
end

-- Multi-block region
return region -> i32
entry start()
    jump loop(i = 0, acc = 0)
end
block loop(i: index, acc: i32)
    if i >= n then yield acc end
    jump loop(i = i + 1, acc = acc + xs[i])
end
end
```

### Regions — typed control fragments
```moonlift
region scan(p: ptr(u8), n: i32, target: i32;
            hit: cont(pos: i32),
            miss: cont(pos: i32))
entry loop(i: i32 = 0)
    if i >= n then jump miss(pos = i) end
    if as(i32, p[i]) == target then jump hit(pos = i) end
    jump loop(i = i + 1)
end
end

-- Use via emit (zero-cost CFG splice, not a call)
emit scan(p, n, 65; hit = found, miss = not_found)
```

### Expression fragments
```moonlift
expr clamp(x: i32) -> i32
    select(x < 0, 0, x)
end

-- Use: let v = emit clamp(val)
```

### Bindings
```moonlift
let x: i32 = 42    -- immutable (SSA-like)
var i: index = 0   -- mutable (stack-backed)
```

### Conversion
```moonlift
as(i32, u8_val)    -- only conversion form: extend/truncate/bitcast/fp convert
```

### Splices — `@{lua_expr}` embeds Lua values into Moonlift source
Evaluated at `.mlua` load time. Role is checked by parser:
- Type position: `let x: @{T} = 0`
- Fragment position: `emit @{frag}(args; ok = done)`
- Name position: `region @{name}(...)` (must be whole token)
- Expression: `if x > @{limit} then ...`

### Design philosophy
- **Co-author two typed structures**: data types (type forest) + control types (continuation signatures). Both are checked.
- **Regions bridge the two**: runtime params are data types; continuations are control types.
- **Compose with regions, seal with functions**: `emit` is zero-cost CFG splicing (inline, no call overhead).
- **Lua is metaprogramming**: generics, templates, codegen live in Lua. Moonlift receives monomorphic result.
- **ASDL is the architecture**: all meaningful compilation state is interned, immutable ASDL values. No hidden state in strings, callbacks, or side tables.
- **PVM phases are auto-cached memoization boundaries**: edit one subtree, only that subtree recompiles.

## Key files

| File | Purpose |
|------|---------|
| `init.lua` | Package init — sets `package.path` and loads facade |
| `run_mlua.lua` | `.mlua` runner entry point |
| `lsp.lua` | LSP server entry point |
| `lua/moonlift/pvm.lua` | Phase Virtual Machine — recording triplet framework |
| `lua/moonlift/back_jit.lua` | Lua→Rust JIT FFI bridge |
| `src/lib.rs` | Full Cranelift backend (JIT + object emission) |
| `src/ffi.rs` | C FFI exports for LuaJIT interop |
