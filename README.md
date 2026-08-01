# Lalin

Lalin is a LuaJIT-hosted dialect of the LLBL language.

LLBL is the center of the system: the extensible language workbench and bootstrap
language for defining member dialects. It turns evaluated Lua values into
dialect objects with heads, roles, fragments, namespaces, origins, diagnostics,
formatting, indexing, and generic regions. Region is the shared control algebra
that composes the language. Lalin is the compiled dialect: it consumes LLBL regions and typed values,
checks them, lowers them through the semantic `emit_c`/`CBackendUnit` path, and
cooks that C with GCC for the main JIT-like execution path or as an AOT C
artifact. Native copy-patch/binary-bank patchers are retired and must not be
reopened; only the stencil/CMat vocabulary survives as the deterministic
emitted-C shape contract. Fused emitted C + GCC -O3 is the performance path.

```text
Lua source
  -> Lua values
  -> LLBL language capture
  -> Lalin ASDL
  -> typecheck
  -> LalinCode facts
  -> CBackendUnit
  -> emit_c C source
  -> gcc -shared/-O3 + dlopen for JIT-like execution, or user-owned AOT build
  -> LuaJIT FFI function pointers / native C artifact
```

There is no Cranelift/Rust runtime path in the active architecture.

LLBL bootstraps itself in plain Lua: `lua/llbl.lua` is the small stage-0 kernel,
`lua/llbl/bootstrap.lua` defines the stage-1 `llbl` dialect, and public
`llbl.grammar` is the bootstrapped grammar facade. The preserved kernel grammar
is available as `llbl.kernel.grammar`.

The bare `llbl` member is the identity of language composition. It provides shared
mechanics such as source/generated symbols, origins, diagnostics, fragments,
regions, formatting docs, and language-level symbol bindings. Dialects own the
semantic meaning of those bindings.

## Quick Start

The recommended execution path is GCC over `emit_c` output. It produces a shared
object, loads it with `dlopen`, and exposes function pointers through LuaJIT FFI:

```lua
local lalin = require("lalin")
local lln = lalin.lln

local add = lln.fn. add { a [lln.i32], b [lln.i32] } [lln.i32] {
  lln.ret (a + b),
}

local session = lalin.compile_c_gcc("demo", { add }, {
  gcc_opts = { opt = 3, out_dir = "target/demo" },
})
local add_fn = assert(session:symbol("add", "int32_t (*)(int32_t, int32_t)"))
print(add_fn(3, 4)) -- 7
session:free()
```

For parsed `.lln` loading:

```lua
local lalin = require("lalin")

local decls = assert(lalin.loadstring([[
fn add(a [i32], b [i32]) [i32] do
  return a + b
end
]], "@demo.lln"))
```

## Build

```sh
make
```

`make` builds the repository-local LuaJIT archive if needed.

The main JIT-like path requires GCC or a compatible C compiler. `make gcc` can
build the vendored GCC under `.vendor/gcc/.local`; otherwise Lalin uses `CC` or
`gcc` from the host. Runtime execution cooks `emit_c` output into a shared object
and loads it with `dlopen`.

The native copy-patch template-bank path is retired and must not be reopened;
it is not selected by any supported API. LuaJIT bytecode remains an explicit
non-main mode selected with `compile_luajit` or `{ bytecode = true }`.

## Test

```sh
luajit tests/run.lua
```

Focused suites:

```sh
luajit tests/run.lua frontend
luajit tests/run.lua code_ir
luajit tests/run.lua schema
luajit tests/run.lua ui
```

Useful backend checks:

```sh
luajit tests/code_ir/test_luajit_backend_bc.lua
luajit tests/c_backend/test_cmat_counted_fragment_gcc.lua
luajit tests/c_backend/test_stencil_c_gcc.lua
```

## Repository Map

```text
lua/llbl.lua                  LLBL extensible language workbench substrate
lua/lalin/                   Lalin compiler, schemas, DSL, and backend
lua/lalin/dsl/               authoring heads and namespace surface
lua/lalin/schema/            ASDL/schema definitions
lua/ui/                      UI kernel and widgets
tests/                       standalone LuaJIT tests
benchmarks/                  measurement scripts
docs/                        consolidated documentation
```

## Language Shape

Lalin uses products for data that exists together and protocols for named
control outcomes.

```lua
region. scan
  { p [lln.ptr [lln.u8]], n [lln.index], target [lln.u8] }
  {
    hit { pos [lln.index] },
    miss { pos [lln.index] },
  }
  {
    lln.entry. loop { i [lln.index] } {
      lln.when (i :ge (n)) {
        lln.jump. miss { pos = i },
      },

      lln.when (p[i] :eq (target)) {
        lln.jump. hit { pos = i },
      },

      lln.jump. loop { i = i + 1 },
    },
  }
```

`region.` is the generic LLBL control-machine head. Lalin consumes generic
regions as native typed CFG when the body uses Lalin block/jump vocabulary.

Internal composition normally uses `emit`, which splices a callee region into
the caller CFG. Use region `call` when you need a real frame for recursion,
debugging, profiling, or instrumentation; it lowers as a sealed function plus
an encoded exit union and dispatch back to named exits.

## Documentation

Core reference:
- `docs/ASDL_GUIDE.md` - binding ASDL modeling doctrine and method discipline
- `docs/LLBL_GUIDE.md` - central LLBL workbench and region guide
- `docs/LANGUAGE_REFERENCE.md` - public Lalin language reference
- `docs/ARCHITECTURE.md` - language, compiler, backend, and lowering architecture
- `docs/TARGET_ASDL_ARCHITECTURE.md` - target ASDL schema and method file organization
- `docs/DESIGN_BIBLE.md` - long-form design philosophy

Backend and dialect design:
- `docs/C_BACKEND_REDESIGN.md` - target C backend lowering design
- `docs/C_LLBL_REDESIGN.md` - C LLBL dialect target design
- `docs/LLBL_BRACKET_EVAL_ARCHITECTURE.md` - kernel-owned HostEval and role algebra

Process and roadmap:
- `docs/CONVENTIONS.md` - naming, style, and repository conventions
- `docs/UI_GUIDE.md` - UI package guide
- `docs/LUA_VM_ROADMAP.md` - staged Lua VM milestones

Retired:
- `docs/RESIDUAL_NATIVE_ARCHITECTURE.md` - retired native C-stencil copy-patch architecture (historical record; the stencil/CMat vocabulary survives as the emitted-C shape contract)

## Design Rules

- Lua owns genericity; Lalin receives monomorphic values.
- LLBL is the workbench; Lalin is the compiled language member.
- Types are evaluated Lua values in `[]`.
- Heads are syntax; roles own normalization.
- Fragments are role-tagged reusable values.
- Regions model control; `emit` splices; region `call` gives frames/recursion.
- Functions are the sealed product-return ABI substrate.
- Pull-shaped work is a region protocol lowered through GPS.
- Schedules are policy, not semantics.
- Backend facts must be explicit ASDL.
- No compatibility shims for removed surfaces.
