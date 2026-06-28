# Lalin Language Reference

This is the public reference for the Lalin language.

Lalin has **two authoring surfaces** with identical semantics:

1. **Lua/LLBL DSL** — Lua values shaped by LLBL staged heads (the original surface)
2. **Parsed channel frontend** — Lalin-native syntax captured by `llbl.syntax` (new)

Both produce the same LalinTree ASDL, typecheck through the same pipeline, and
lower through the same backends.

---

## Loading

### Lua/LLBL DSL path

```lua
local lalin = require("lalin")
lalin.language.use()

return {
  lln.fn. add { a [lln.i32], b [lln.i32] } [lln.i32] {
    lln.ret (a + b),
  },
}
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

### Parsed channel path

Sources that use Lalin-native syntax must be loaded through `llbl.syntax`:

```lua
local syntax = require("llbl.syntax")
require("lalin.syntax")

local src = [[
  local add = lalin fn add(a: i32, b: i32): i32
    return a + b
  end
  return add
]]

local chunk = assert(syntax.loadstring(src, "@demo.lalin.lua"))
local fns = chunk()
```

Use `syntax.loadfile` for `.lua` files with parsed islands:

```lua
local chunk = assert(syntax.loadfile("demo.lalin.lua"))
local module = chunk()
```

Parsed files can use `import` to activate direct entrypoints:

```lua
import "lalin.syntax"

local add = fn add(a: i32, b: i32): i32
  return a + b
end
```

For a quick compile-evaluate cycle, use `lalin.compile_parsed`:

```lua
local add = lalin.compile_parsed([[
  fn add(a: i32, b: i32): i32
    return a + b
  end
]])
print(add(3, 4))
```

---

## Language Namespaces

The Lua/LLBL DSL installs namespace values:

```text
lln / lalin  Lalin native language
schema      LalinSchema
llpvm       LLPVM
region      generic LLBL region head
_           splice marker
spread      explicit splice marker
```

Namespaces are also language zones:

```lua
return {
  lln {
    lln.fn. add { a [lln.i32], b [lln.i32] } [lln.i32] {
      lln.ret (a + b),
    },
  },

  llpvm {
    llpvm.task. compile {
      llpvm.input [lln.i32],
      llpvm.output [lln.i32],
    },
  },

  schema {
    schema. Demo {
      schema.product. Pair {
        left [schema.any],
        right [schema.any],
      },
    },
  },
}
```

The parsed channel path uses `lalin fn ... end` blocks inside Lua. The namespace
prefix is only needed for the namespaced form (`lalin fn`, `lalin region`, etc.)
or when mixing with the old DSL. The `import`-activated form uses bare `fn`,
`struct`, `region`, etc.

---

## Types

Scalar types:

| Type | DSL form | Parsed form |
|------|----------|-------------|
| void | `lln.void` | `: void` |
| bool | `lln.bool` | `: bool` |
| i8   | `lln.i8`   | `: i8` |
| i16  | `lln.i16`  | `: i16` |
| i32  | `lln.i32`  | `: i32` |
| i64  | `lln.i64`  | `: i64` |
| u8   | `lln.u8`   | `: u8` |
| u16  | `lln.u16`  | `: u16` |
| u32  | `lln.u32`  | `: u32` |
| u64  | `lln.u64`  | `: u64` |
| f32  | `lln.f32`  | `: f32` |
| f64  | `lln.f64`  | `: f64` |
| index| `lln.index`| `: index` |

Compound type constructors:

| Type | DSL form | Parsed form |
|------|----------|-------------|
| pointer | `lln.ptr [T]` | `ptr[T]` |
| view | `lln.view [T]` | `view[T]` |
| func type | `lln.func_type { ... } [R]` | `func_type(...): R` |

In the parsed surface, types are spelled inline after `:` or inside `[]`:

```lua
lalin fn scale(dst: ptr[i32], src: ptr[i32], n: index): void
  ...
end
```

In the DSL, types use Lua bracket syntax because the content is evaluated Lua:

```lua
lln.fn. scale { dst [lln.ptr [lln.i32]], src [lln.ptr [lln.i32]], n [lln.index] } [lln.void] { ... }
```

---

## Declarations

### Functions

DSL:

```lua
lln.fn. add { a [lln.i32], b [lln.i32] } [lln.i32] {
  lln.ret (a + b),
}
```

Parsed:

```lua
lalin fn add(a: i32, b: i32): i32
  return a + b
end
```

### Structs

DSL:

```lua
lln.struct. Vec2 {
  x [lln.f32],
  y [lln.f32],
}
```

Parsed:

```lua
lalin struct Vec2
  x: f32
  y: f32
end
```

### Unions

DSL:

```lua
lln.union. Result {
  ok { value [lln.i32] },
  err { code [lln.i32] },
}
```

Parsed:

```lua
lalin union Result
  Some (value: i32)
  None
end
```

### Externs

DSL only (parsed surface planned):

```lua
lln.extern. puts { s [lln.ptr [lln.u8]] } [lln.i32]
```

### Constants and statics

DSL only (parsed surface planned):

```lua
lln.const. answer [lln.i32] (42)
lln.static. counter [lln.i32] (0)
```

---

## Products And Fragments

Product-shaped lists are ordinary Lua tables of typed names. This is
DSL-specific; the parsed surface is statement-oriented.

DSL:

```lua
{ a [lln.i32], b [lln.i32] }
```

Fragments:

```lua
local buffer = lln.product {
  p [lln.ptr [lln.u8]],
  n [lln.index],
}

lln.fn. first { _(buffer) } [lln.u8] {
  lln.ret (p[0]),
}
```

Common fragment roles:

```text
product
decls
stmts
exprs
conts
variants
```

Algebra:

```lua
params_a .. params_b       -- list/product concatenation
ok_exits + err_exits       -- protocol/sum choice
error_exits * position     -- decorate every alternative with a product
```

`_(fragment)` is the preferred splice. `spread(fragment)` is the explicit
fallback.

---

## Statements

### DSL form

```lua
lln.let. x [lln.i32] (1)
lln.var. acc [lln.i32] (0)
set (acc)(acc + x)
lln.ret (acc)
lln.trap ()
```

Conditional:

```lua
lln.when (n :eq (0)) {
  lln.ret (0),
}
```

Switch:

```lua
lln.switch (tag) {
  lln.case (0) { lln.ret (10) },
  lln.case (1) { lln.ret (20) },
  lln.default { lln.ret (-1) },
}
```

### Parsed form

```lua
let x: i32 = 1
var acc: i32 = 0
dst[i] = src[i]    -- real assignment
return acc
```

If/elseif/else:

```lua
if x < lo then
  return lo
elseif x > hi then
  return hi
else
  return x
end
```

Contracts:

```lua
requires bounds(dst)(n), bounds(src)(n), disjoint(dst)(src)
```

For/range:

```lua
for i in range(0, n) do
  dst[i] = src[i] * 2
end
```

Jump:

```lua
jump loop(i + 1)
```

Emit:

```lua
emit finish(result)
```

There is no source-level `for`, `while`, `break`, or `continue` in Lalin, even
in the parsed surface. Loop-like iteration uses `for i in range(...)` which
lowers to the same `ControlStmtRegion` CPS as `lln.loop`. Flow-sensitive
iteration (while-like) uses region jumps directly.

---

## Regions

Regions are the core control-flow construct. A region is:

```text
input product ; continuation sum
  → entry/block declarations
  → jump control flow
```

### DSL form

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

### Parsed form

The `;` separates the input product from the continuation sum in the
signature. Continuation payloads may use named fields or bare types.

```lua
lalin region scan(p: ptr[u8], n: index; hit: (pos: index), miss: ())
  entry loop(i: index)
    if i >= n then
      jump miss(pos = i)
    end
    if p[i] == target then
      jump hit(pos = i)
    end
    jump loop(i = i + 1)
  end
end
```

Variations:

```lua
-- Data params only (no continuations)
lalin region simple(x: i32)
  entry start do jump done() end
  block done end
end

-- Continuations only (no data params)
lalin region only_continuations(; done: (i32))
  entry start do jump done(42) end
  block done(r: i32) do emit finish(r) end
end

-- Empty signature
lalin region empty()
  entry start do jump done() end
  block done end
end

-- Continuations without the optional colon
lalin region bare(x: i32; done(result: i32))
  entry start do jump done(x) end
  block done(r: i32) do emit finish(r) end
end
```

---

## Region Call

`emit` is the normal internal composition form: it splices the callee region
directly into the caller CFG and wires every exit locally.

`call` preserves a region boundary. Use it when the region needs its own frame:

- recursion
- debugging
- profiling
- instrumentation
- ABI-like isolation without losing named exits

Semantically, a region call is sugar for:

```text
sealed function
  → encoded exit union
  → dispatch back to the region protocol exits
```

That means `call` handles recursion while preserving the caller-facing protocol.

---

## Expressions

### Operators

DSL:

```lua
a + b
a - b
a * b
a / b
p[i]
value.field
fn_call(a, b)
```

Parsed (same operators, real syntax):

```lua
a + b
a - b
a * b
a / b
dst[i] = src[i]
value.field
fn_call(a, b)
```

### Comparisons

DSL uses readable method calls:

```lua
i :lt (n)
i :le (n)
i :eq (0)
i :ne (sentinel)
i :ge (n)
i :gt (n)
```

Parsed uses real comparison operators:

```lua
i < n
i <= n
i == 0
i ~= sentinel
i >= n
i > n
```

### Boolean operators

DSL:

```lua
a :and (b)
a :or (b)
not a
```

Parsed:

```lua
a and b
a or b
not a
```

### Conversions

Both surfaces:

```lua
lln.as [lln.i32] (x)    -- DSL
as [i32](x)              -- parsed (planned)
```

### Host escapes (parsed-only)

The parsed surface can splice Lua values into Lalin expressions with `[...]`:

```lua
local factor = 4
lalin fn scaled_copy(dst: ptr[i32], src: ptr[i32], n: index): void
  for i in range(0, n) do
    dst[i] = src[i] * [factor]
  end
end
```

The bracket expression is evaluated at construction time using the Lua
environment captured at the definition site.

---

## Contracts

Contracts are semantic facts, not comments.

DSL:

```lua
lln.fn. sum { xs [lln.ptr [lln.i32]], n [lln.index] } [lln.i32] {
  lln.requires {
    lln.bounds (xs)(n),
    lln.readonly(xs),
  },

  -- body
}
```

Parsed:

```lua
lalin fn sum(xs: ptr[i32], n: index): i32
  requires bounds(xs)(n), readonly(xs)

  -- body
end
```

Contracts feed lowering and diagnostics. If the backend needs a fact, it should
be represented explicitly.

---

## Native Loops And Stencil-Shaped Work

`lln.loop` (DSL) and `for i in range(...)` (parsed) are equivalent. Both produce
a `ControlStmtRegion` CPS that flows through `Code → Flow → Kernel → Stencil`.

### One-dimensional range

DSL:

```lua
lln.loop. i [lln.range { 0, n }] {
  set (dst[i])(lhs[i] + rhs[i]),
}
```

Parsed:

```lua
for i in range(0, n) do
  dst[i] = lhs[i] + rhs[i]
end
```

Range with explicit step:

```lua
for i in range(0, n, 2) do
  dst[i] = 0
end
```

### Fold (reduction)

DSL:

```lua
lln.loop. i [lln.range { 0, n }] [lln.i32] {
  lln.fold. acc [lln.i32] {
    init = 0,
    by = lln.add,
    step = xs[i],
  },
}
```

Parsed form is planned, roughly:

```lua
for i in range(0, n) do
  fold acc: i32 = init 0, by add { acc + xs[i] }
end
```

### N-dimensional ranges

DSL:

```lua
lln.loop { i, j } [lln.range_nd { { 0, h }, { 0, w } }] {
  set (dst[i * w + j])(src[i * w + j]),
}
```

Parsed form is planned:

```lua
for i, j in range_nd({0, h}, {0, w}) do
  dst[i * w + j] = src[i * w + j]
end
```

### Window domains

DSL:

```lua
lln.loop { i } [lln.window_nd {
  axes = { { 0, n } },
  windows = { { 1, 1, boundary = "clamp" } },
}] {
  set (dst[i])(xs[i - 1] + xs[i] + xs[i + 1]),
}
```

### Tiled scan

DSL:

```lua
lln.loop { i, j } [lln.tiled_nd {
  axes = { { 0, h }, { 0, w } },
  tiles = { 4, 8 },
}] {
  lln.scan. acc [lln.i32] {
    init = 0,
    by = lln.add,
    axis = 2,
    step = xs[i * w + j],
    into = dst[i * w + j],
  },
}
```

### Select (branchless stencil body)

DSL:

```lua
lln.loop. i [lln.range { 0, n }] {
  set (dst[i])(select (lhs[i] :gt (0))(lhs[i])(rhs[i])),
}
```

Parsed uses `select` expression:

```lua
for i in range(0, n) do
  dst[i] = select(lhs[i] > 0, lhs[i], rhs[i])
end
```

### Scatter-reduce

Scatter-reduce is recognized from immediate indexed read-modify-write forms:

```lua
set (bins[idx[i]])(bins[idx[i]] + src[i])
```

Contracts such as `bounds`, `readonly`, `writeonly`, and `disjoint` are consumed
by these paths. Unsupported loop shapes should be rejected through typed facts
or fall back through the semantic path; they should not silently become
element-level FFI code.

---

## Ownership

Owned values are the same in both surfaces.

`owned T` values must be discharged or transferred exactly once. They cannot be
silently copied. Leases describe temporary access to owned or store-managed
resources.

Important rules:

- owned values cannot be fields of aggregates
- owned values cannot be copied
- region calls cannot carry owned or lease payloads; use `emit`
- handle representation casts are explicit trust boundaries

---

## Formatting

Lalin formatting is semantic. It formats evaluated Lalin/LLBL values, not
arbitrary Lua text.

```sh
luajit scripts/lalinfmt.lua demo.lua
luajit scripts/lalinfmt.lua --check demo.lua
luajit scripts/lalinfmt.lua --write demo.lua
```

Programmatic API:

```lua
local text = require("lalin").format(value)
local text = require("lalin").format_file("demo.lua")
require("lalin").write_format_file("demo.lua")
```

The formatted output uses the Lua/LLBL DSL surface regardless of how the
source was authored.

---

## Diagnostics

Common early errors for the DSL surface are documented in the underlying LLBL
system. Common parsed-surface errors:

```text
expected expression atom, got `end`
unsupported Lalin syntax entrypoint `foo`
expected Lalin loop producer range/range_nd/window_nd/tiled_nd
expected region entry/block or end
parsed_to_tree: unsupported expression tag ...
parsed_to_tree: unsupported statement tag ...
```

---

## Compilation

### DSL path

```lua
local module = lalin.compile("demo", {
  lln.fn. add { a [lln.i32], b [lln.i32] } [lln.i32] {
    lln.ret (a + b),
  },
})

print(module.add(3, 4))
```

### Parsed path

Parse, convert to tree ASDL, then compile:

```lua
local syntax = require("llbl.syntax")
require("lalin.syntax")

local lalin = require("lalin")
local pvm = require("lalin.pvm")
local T = pvm.context()

local src = [[
lalin fn add(a: i32, b: i32): i32
  return a + b
end
]]

local chunk = syntax.loadstring("return {" .. src .. "}")
local parsed = chunk()
local module_ast = require("lalin.syntax").to_module(parsed, "add", T)

-- Through compiler pipeline
local Pipeline = require("lalin.frontend_pipeline")(T)
local checked = Pipeline.typecheck_module(module_ast, { context = T })
local code_result = Pipeline.checked_to_code_result(checked, { context = T })

-- Emit LuaJIT artifact
local Backend = require("lalin.luajit_backend")(T)
local lj_module, facts = Backend.lower_module(code_result.module, {
  contracts = code_result.contracts,
  copy_patch = "bc",
})
local bc_bank = Backend.build_bc_bank(facts.artifacts or {}, { stem = "add" })
local source = Backend.emit_lua_artifact(lj_module, facts.artifacts, {
  bc_bank = bc_bank,
  copy_patch = "bc",
})
```

A convenience `lalin.compile_parsed` wrapper is planned.

### LuaJIT artifact emission

Emit a LuaJIT artifact from the DSL path:

```lua
local artifact = lalin.emit_luajit_artifact(decls, {
  name = "Demo",
  path = "target/artifacts/demo.lua",
  copy_patch = "bc",
})

artifact:write()
```

`lalin.compile` uses the LuaTrace BC copy-patch path by default. It is the
portable semantic path and does not require the native stencil toolchain.

`lalin.emit_luajit_artifact` defaults to the fast copy+residual path:

```text
typed stencil plans
  → copy_patch_mc bank stencils
  → embedded/installed MC bytes
  → TCC residual glue
  → loaded LuaJIT module
```

The MC path requires an already selected and built `MCStencilBank`; it does not
build one during artifact emission:

```lua
local plan = lalin.plan_luajit_artifact(decls, {
  name = "Demo",
  copy_patch = "mc",
})

local bank = assert(plan.backend.build_mc_bank(plan.artifacts, {
  stem = "demo_aot_bank",
}))

local artifact = lalin.emit_luajit_plan_artifact(plan, {
  name = "Demo",
  path = "target/artifacts/demo.lua",
  mc_bank = bank,
})
```

---

## Parsed-Channel Frontend

The parsed-channel frontend is built on the generic `llbl.syntax` subsystem:

```text
llbl.syntax        lexer, registry, constructor, driver, Pratt parser
lalin.syntax       Lalin grammar: declarations, expressions, statements
  to_tree.lua      parsed AST → LalinTree ASDL converter
  for_to_loop.lua  parsed StmtForRange → ControlStmtRegion lowering
```

Integration seam: `lalin.syntax.to_module(parsed_decls, name, T)` converts
parsed AST nodes into a `LalinTree.Module` that feeds the existing
typecheck→lower→backend pipeline.

The parsed frontend supports:

| Construct | Status |
|-----------|--------|
| `fn name(params): result body end` | ✅ |
| `struct Name fields end` | ✅ |
| `union Name variants end` | ✅ |
| `region name(params; exits) entry/block body end` | ✅ |
| `for i in range(...) do body end` | ✅ (lowers to `ControlStmtRegion`) |
| `if/elseif/else/end` | ✅ |
| `let` / `var` | ✅ |
| `return expr` | ✅ |
| `place = expr` (assignment) | ✅ |
| `requires expr, ...` (contracts) | ✅ |
| `jump target(payload)` / `emit callee` | ✅ |
| `[lua_expr]` host escapes | ✅ |
| `range_nd` / `tiled_nd` / `window_nd` | parser accepts, lowering planned |
| `fold` / `scan` reducers | planned |
| `quote` / `expr` / `stmt` fragments | ✅ |
| Module declarations | parser accepts, conversion planned |

---

## Non-Negotiable Rules

These apply to both surfaces equally:

1. Lua owns genericity; Lalin receives monomorphic programs.
2. Types are values — in the DSL they arrive through `[]`, in the parsed
   surface they are parsed tokens that become the same ASDL type values.
3. No angle-bracket type arguments.
4. No source-level `for`, `while`, `break`, or `continue` beyond the
   structured `for i in range(...)`.
5. Every block path terminates with return, jump, emit, trap, or equivalent.
6. Switches require a default arm and have no fallthrough.
7. Region protocols are explicit named exits in the signature.
8. Semantic facts belong in ASDL, not comments or strings.
9. Fragments are role-tagged values.
10. Backends consume validated facts; they do not infer hidden semantics.
