# Lalin - Agent Guidance

Lalin is a LuaJIT-hosted language family built around LLB. Lua is the
metaprogramming layer. LLB is the central language-family workbench and
bootstrap language: heads, roles, fragments, namespaces, origins, diagnostics,
formatting, indexing, families, and generic regions. Lalin is the compiled
family dialect that lowers typed programs into LuaJIT copy-patch artifacts.

The active copy-patch backends are `copy_patch_mc` for fast C-stencil machine
code artifacts and `copy_patch_bc` for LuaTrace/LuaJIT bytecode artifacts.
`lalin.compile` currently defaults to bytecode copy-patch; emitted LuaJIT
artifacts default to machine-code copy-patch. The old Cranelift/Rust runtime
path is not part of the current architecture.

## Build

```sh
make
```

Optional C/native stencil work may need:

```sh
git submodule update --init --recursive
make libtcc
```

## Run DSL Files

```lua
local lalin = require("lalin")
lalin.family.use()

local add = ll.fn. add { a [ll.i32], b [ll.i32] } [ll.i32] {
  ll.ret (a + b),
}

local module = lalin.compile("demo", { add })
print(module.add(3, 4)) -- 7
```

Inline evaluation:

```lua
local lalin = require("lalin")

local unit = lalin.loadstring([[
  return {
    ll.fn. add { a [ll.i32], b [ll.i32] } [ll.i32] {
      ll.ret (a + b),
    },
  }
]], "demo.lua")()
```

## Test

Tests are standalone LuaJIT scripts:

```sh
luajit tests/run.lua
luajit tests/run.lua frontend
luajit tests/run.lua code_ir
luajit tests/run.lua schema
luajit tests/run.lua llpvm
```

Useful focused checks:

```sh
luajit tests/code_ir/test_copy_patch_bc.lua
luajit tests/code_ir/test_luajit_backend_bc.lua
luajit tests/code_ir/test_copy_patch_luatrace.lua
luajit tests/pvm/test_compiler_driver.lua
```

## Architecture

```text
Lua source
  -> Lua values
  -> LLB family capture
  -> Lalin ASDL
  -> typecheck
  -> LalinCode facts
  -> kernel and schedule facts
  -> LuaTrace stencil plans or C stencil plans
  -> LuaJIT copy-patch bank
  -> loaded LuaJIT module
```

Key files:

```text
lua/llb.lua                  LLB language-family workbench substrate
lua/lalin/dsl/               Lalin authoring heads
lua/lalin/schema/            ASDL/schema definitions
lua/lalin/frontend_pipeline.lua
                             DSL/tree/typecheck/code pipeline
lua/lalin/luajit_backend.lua LuaTrace/LuaJIT backend facade
lua/lalin/copy_patch_bc.lua LuaJIT BC bank
lua/llpvm/                   LLPVM member
lua/llisle/                  Llisle rule language
```

## Key Docs

```text
docs/LLB_GUIDE.md            central LLB workbench and region guide
docs/LANGUAGE_REFERENCE.md   public Lalin family language reference
docs/ARCHITECTURE.md         family, compiler, backend, and lowering architecture
docs/LLPVM_GUIDE.md          low-level VM/task language member
docs/UI_GUIDE.md             UI package guide
docs/CONVENTIONS.md          naming, style, and repository conventions
docs/DESIGN_BIBLE.md         long-form design philosophy
```

## Non-Negotiable Rules

1. LLB is the workbench; Lalin is the compiled family member.
2. Lua owns genericity; Lalin receives monomorphic values.
3. Types are evaluated Lua values in `[]`.
4. No angle-bracket type arguments.
5. No source-level `for`, `while`, `break`, or `continue`.
6. Every block path terminates.
7. Switches require a default arm and have no fallthrough.
8. `region.` is generic LLB control syntax; Lalin consumes it.
9. Pull-shaped work is a region protocol lowered through GPS.
10. Backend facts must be explicit ASDL.
11. No compatibility shims for removed surfaces.

## Working Notes

Use `rg` for searches. Do not revert user changes. Ignore `museum/gps.lua`
unless the user explicitly asks to work on it.
