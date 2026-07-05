# Lalin

Lalin is a LuaJIT-hosted dialect of the LLBL language.

LLBL is the center of the system: the extensible language workbench and bootstrap
language for defining member dialects. It turns evaluated Lua values into
dialect objects with heads, roles, fragments, namespaces, origins, diagnostics,
formatting, indexing, and generic regions. Region is the shared control algebra
that composes the language. Lalin is the compiled dialect: it consumes LLBL regions
and typed values, checks them, and lowers them into native C-stencil copy-patch
artifacts or explicitly selected LuaJIT bytecode artifacts.

```text
Lua source
  -> Lua values
  -> LLBL language capture
  -> Lalin ASDL
  -> typecheck
  -> LalinCode facts
  -> NativeTemplateGraph or explicit LuaJIT bytecode plan
  -> supplied NativeTemplateBank copy/patch/install, or bytecode artifact
  -> loaded module
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

The default `lalin.compile` path is native copy-patch and requires a supplied
native template bank. The quickstart uses explicit LuaJIT bytecode mode so it can
run without a prebuilt bank:

```lua
local lalin = require("lalin")
lalin.language.use()

local add = lln.fn. add { a [lln.i32], b [lln.i32] } [lln.i32] {
  lln.ret (a + b),
}

local module = lalin.compile("demo", { add }, { bytecode = true })
print(module.add(3, 4)) -- 7
```

For isolated loading:

```lua
local lalin = require("lalin")

local unit = lalin.loadstring([[
  return {
    lln.fn. add { a [lln.i32], b [lln.i32] } [lln.i32] {
      lln.ret (a + b),
    },
  }
]], "demo.lua")()
```

## Build

```sh
make
```

`make` builds the repository-local LuaJIT archive if needed.

Native runtime compilation does not require Cargo, Rust, Cranelift, TCC,
readelf, or a system C compiler. It does require a prebuilt
`NativeTemplateBank`/`NativeEmbeddedTemplateBank`; the offline bank build is the
only step that compiles generated C stencils. The offline generator verifies
objects through Lalin's internal ELF/object parser and typed native verifier.

The default `lalin.compile` path is native copy-patch. Select LuaJIT bytecode
explicitly with `compile_luajit` or `{ bytecode = true }`.

## Test

```sh
luajit tests/run.lua
```

Focused suites:

```sh
luajit tests/run.lua frontend
luajit tests/run.lua code_ir
luajit tests/run.lua schema
luajit tests/run.lua llpvm
luajit tests/run.lua ui
```

Useful backend checks:

```sh
luajit tests/code_ir/test_native_template_sources.lua
luajit tests/code_ir/test_native_bank_generator.lua
luajit tests/code_ir/test_native_mc_import.lua
luajit tests/code_ir/test_native_code_graph_scalar.lua
luajit tests/code_ir/test_native_code_control.lua
luajit tests/code_ir/test_native_kernel_contracts.lua
luajit tests/code_ir/test_native_stencil_contracts.lua
luajit tests/code_ir/test_luajit_backend_bc.lua
```

## Repository Map

```text
lua/llbl.lua                  LLBL extensible language workbench substrate
lua/lalin/                   Lalin compiler, schemas, DSL, and backend
lua/lalin/dsl/               authoring heads and namespace surface
lua/lalin/schema/            ASDL/schema definitions
lua/llpvm/                   low-level VM/task dialect member
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

The docs are intentionally small:

- `docs/LLBL_GUIDE.md` - central LLBL workbench and region guide
- `docs/LANGUAGE_REFERENCE.md` - public Lalin language reference
- `docs/ARCHITECTURE.md` - language, compiler, backend, and lowering architecture
- `docs/LLPVM_GUIDE.md` - low-level VM/task language member
- `docs/UI_GUIDE.md` - UI package guide
- `docs/CONVENTIONS.md` - naming, style, and repository conventions
- `docs/DESIGN_BIBLE.md` - long-form design philosophy

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
