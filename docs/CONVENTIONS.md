# Lalin Conventions

These conventions keep the repository grepable and keep the extensible language
auditable.

## Names

Use `Lalin` for the project and native compiled dialect.

Use `lalin` for package names, module names, file stems, CLI names, and local
variables that hold the public module.

## Two authoring surfaces

### Primary (hand-written code)

Use `.lln` declaration documents for hand-written Lalin source. A `.lln` file is
rooted at `Lalin.decls`; it contains root declarations and top-level HostEval
declaration splices, and loading returns an ordered declaration array. Lua
`local`/`return` chunk structure belongs in `.lua` builder modules, not `.lln`
documents.

```lln
-- primary.lln
fn add(a [i32], b [i32]) [i32] do
  return a + b
end
```

### Builder API (macros, generators, tooling)

Use the Lua/LLBL DSL when constructing declarations programmatically:

```lua
lln.fn. add { a [lln.i32], b [lln.i32] } [lln.i32] {
  lln.ret (a + b),
}
```

Use `lln` as the short authoring namespace inside the builder API.

Use exact subsystem prefixes:

```text
llbl_      LLBL substrate concepts
luajit_   LuaJIT backend concepts
stencil_  stencil descriptor/materializer concepts
schema_   schema projection/runtime concepts
```

Avoid vague names such as `helper`, `info`, `data`, `thing`, or `state` when a
semantic name exists.

## Files

Prefer one flat folder per subsystem. Split by semantic ownership, not by
chronological step.

Good:

```text
lua/lalin/code_type.lua
lua/lalin/code_validate.lua
lua/lalin/code_kernel_plan.lua
```

Bad:

```text
lua/lalin/core/runtime/protocols/helpers/misc.lua
```

Documentation should be small and authoritative. Migration journals, old
backend notes, and duplicated design drafts should be archived outside `docs/`
or removed.

## Lua DSL Style

Use namespace prefixes in examples unless the surrounding text is explicitly
about `use()` globals.

Preferred:

```lua
lln.fn. add { a [lln.i32], b [lln.i32] } [lln.i32] {
  lln.ret (a + b),
}
```

Spacing:

```lua
i :lt (n)
value :eq (target)
as [lln.i32] (x)
```

Keep the space after the receiver and before the call parentheses. The method
comparison form is the readable replacement for unavailable Lua operator
overloading.

## Fragments

Reusable DSL pieces should return role-tagged fragments:

```lua
local function buffer_params()
  return lln.product {
    p [lln.ptr [lln.u8]],
    n [lln.index],
  }
end
```

Avoid returning raw arrays from public metaprogramming helpers.

## Regions

Use regions for control machines. Prefer `emit` for local composition. Use
region `call` when the region needs a frame for recursion, profiling, debugging,
or instrumentation. Functions are the sealed product-return ABI substrate.

`region.` is LLBL-owned. Lalin consumes it; Lalin does not own the generic region
concept.

Do not introduce semantic APIs named `stream`. Pull-shaped behavior is a region
protocol lowered through GPS.

## ASDL And Schemas

ASDL/schema values are semantic products. Do not hide meaning in strings,
callbacks, or side tables.

If lowering needs a fact, represent it in schema first.

## Backends

The main backend path is semantic C. `LalinCode`, `LalinKernel`, and
`LalinStencil` facts lower to `CBackendUnit`; `emit_c` emits ordinary C; the GCC
C JIT path cooks that emitted C as a shared object and loads function pointers
through LuaJIT FFI. The AOT path is the same `emit_c` output handed to the user's
build system.

Backend decisions must be ASDL values. Stencil selection, lowering plans, ABI
projections, runtime symbol capabilities, and typed rejection reasons are not
option bags, string tags, raw hole tables, or side maps. The leaf that owns the
semantic descriptor also owns how that descriptor becomes C, JIT-cooked shared
object input, AOT source, or an explicitly selected experimental artifact.

Native C-stencil copy-patch is retired and deleted; only the stencil vocabulary
survives as the deterministic emitted-C shape contract.
`docs/RESIDUAL_NATIVE_ARCHITECTURE.md` is the historical record of the retired
patcher.

LuaJIT bytecode is an explicit non-main mode. It is not an implicit fallback from
GCC C execution, AOT emission, or the retired native patcher.

Keep the C path central in wording and code. `emit_c` is the public semantic C
backend API: it emits the whole selected program as C so GCC can cook it for
JIT-like execution or the user can compile it for AOT. It must not describe
itself as, or route through, the old LuaJIT residual C materializer.

Backend code should consume typed facts:

- type and ABI facts
- bounds/alias/residence facts
- kernel descriptors
- schedule policies
- stencil descriptors
- materializer constraints

No backend should rediscover semantics by pattern-matching user source text.

## Ownership

Owned values move exactly once. Leases are explicit. Handle representation casts
are trust boundaries.

Do not put owned values in aggregates, fields, or copied temporary structures.

## Comments And Diagnostics

Comments near declarations can carry useful prose context. Diagnostics should
prefer structured context but may include captured comments as related semantic
notes when available.

Error messages should say:

- what was expected
- what was received
- which head/slot/role/phase was active
- where the value came from

## Tests

Tests are standalone LuaJIT scripts. Name them by boundary:

```text
tests/asdl/test_*.lua
tests/c_backend/test_*.lua
tests/code_ir/test_*.lua
tests/compiler_process/test_*.lua
tests/core/test_*.lua
tests/frontend/test_*.lua
tests/runtime/test_*.lua
tests/schema/test_*.lua
tests/ui/test_*.lua
```

Prefer focused tests that pin one semantic boundary. Broaden tests when a change
touches a shared contract or backend materializer.
