# Lalin Language Reference

Lalin is the compiled language member of the LLBL workbench. Lua is the
metaprogramming layer; Lalin receives monomorphic programs and lowers them
through typed ASDL facts into executable LuaJIT artifacts.

This reference treats the parsed syntax as the standard source surface. The
Lua/LLBL DSL is documented in one chapter near the end because it is still the
best surface for macros, generators, and advanced producer heads.

---

## Model

Lalin is not a generic source language in the C++ or Rust sense. Genericity lives
in Lua and LLBL composition. By the time a Lalin function is compiled, the types
and generated code are concrete.

The pipeline is:

```text
.lln value chunk
  -> lalin.loader
  -> llbl.syntax driver
  -> lalin.syntax parsed AST
  -> LalinTree ASDL
  -> typecheck
  -> LalinCode facts
  -> flow/value/memory/effect/kernel/schedule facts
  -> LuaJIT artifact
```

Important rules:

- LLBL is the workbench; Lalin is the compiled language member.
- Lua owns genericity.
- Lalin receives monomorphic values.
- Types are values in the underlying system; parsed syntax is a source spelling
  for those type values.
- Type arguments use `[]`, never angle brackets.
- Every block path terminates.
- Region protocols are explicit named exits.
- Backend facts are explicit ASDL facts.

---

## Loading `.lln` Source

The official source extension is `.lln`. A `.lln` file is a Lua-native value
chunk with Lalin parsed syntax active by default. It does not define a separate
module system. Use Lua `require`, return Lua values, and compose public APIs with
tables.

```lln
local add = fn add(a: i32, b: i32): i32
  return a + b
end

return {
  add = add,
}
```

Load it directly from Lua:

```lua
local lalin = require("lalin")

local chunk = assert(lalin.loadfile("demo.lln"))
local values = chunk()
```

Or install the `.lln` package searcher and use Lua `require`:

```lua
local lalin = require("lalin")
lalin.path = "./?.lln;./?/init.lln"
lalin.install_searcher()

local demo = require("demo")
```

The returned Lua value is the public API. Lalin does not add `module`, `export`,
or user-facing import declarations on top of Lua.

Parsed declarations are first-class Lua values. A `.lln` chunk may return
declarations, ordinary Lua values, or a compiled runtime module. `lalin.compile`
accepts a parsed declaration or an array of parsed declarations:

```lua
local lalin = require("lalin")

local chunk = assert(lalin.loadstring([[
  return {
    fn add(a: i32, b: i32): i32
      return a + b
    end
  }
]], "@add.lln"))

local parsed_decls = chunk()
local module = lalin.compile("add", parsed_decls)

print(module.add(3, 4))
```

The lower-level `llbl.syntax` mixed-source driver remains infrastructure for
Lua-hosted syntax islands and tooling, not the standard `.lln` loading surface.

---

## Lexical Shape

The parsed syntax appears inside `.lln` Lua value chunks through direct
entrypoints such as `fn`, `struct`, `union`, and `region`.

Names use the usual identifier shape:

```text
letter_or_underscore (letter_or_digit_or_underscore)*
```

Keywords include:

```text
fn struct union region module
requires ensures
do end if then elseif else
loop in grid tiled window
return jump emit entry block
let var
true false nil
and or not
as sizeof
```

Comments and general Lua file structure are handled by the `.lln` syntax loader.

---

## Types

Types are written after `:` in bindings and inside `[]` for type constructors.

### Scalar Types

| Type | Meaning |
|---|---|
| `void` | no value |
| `bool` | boolean value |
| `i8`, `i16`, `i32`, `i64` | signed integers |
| `u8`, `u16`, `u32`, `u64` | unsigned integers |
| `f32`, `f64` | floating point |
| `index` | index/counted-loop integer |

### Compound Types

```lua
ptr[i32]
array[i32]
MyStruct
some.module.TypeName
```

The parser accepts dotted type paths and type constructor application:

```lua
pkg.Buffer[u8]
```

The currently special-cased constructors in parsed-to-tree conversion are
`ptr[...]` and `array[...]`. Other names become named type references.

### Function Signatures

Functions declare parameter products and a single result type:

```lua
fn distance2(x: f32, y: f32): f32
  return x * x + y * y
end
```

Use `void` for functions that do not return a value:

```lua
fn clear(dst: ptr[i32], n: index): void
  loop i in 0 .. n do
    dst[i] = 0
  end
end
```

---

## Declarations

### Functions

```lua
fn add(a: i32, b: i32): i32
  return a + b
end
```

Functions are lowered to typed function items. Parameters are immutable values.
Mutable local state is introduced with `var`.

### Structs

```lua
struct Pair
  left: i32
  right: i32
end
```

Fields are named and typed. Struct field access uses dot syntax:

```lua
p.right
```

### Unions

```lua
union OptionI32
  Some(value: i32)
  None
end
```

Variants may have named payload fields or no payload.

### Files And Values

Lalin does not add a user-facing module declaration. A `.lln` file is a Lua
value chunk. Return the declarations or runtime values the caller should see:

```lua
local add = fn add(a: i32, b: i32): i32
  return a + b
end

return {
  add = add,
}
```

---

## Statements

Statement blocks end at `end`, `elseif`, or `else` depending on context.

### `requires`

`requires` records semantic facts for typechecking and backend planning:

```lua
requires bounds(dst)(n), bounds(src)(n), disjoint(dst)(src)
requires readonly(src), writeonly(dst)
```

Contracts are not comments. They feed memory classification, non-trapping
proofs, alias proofs, kernel planning, and stencil selection.

### `let`

`let` introduces an immutable local binding:

```lua
let x: i32 = 1
let y: i32 = x + 2
```

If an initializer is omitted, the current conversion supplies a zero literal.
Prefer writing the initializer explicitly.

### `var`

`var` introduces mutable local storage:

```lua
var acc: i32 = 0
acc = acc + 1
```

Assignments require a place on the left-hand side.

### Assignment

```lua
x = x + 1
dst[i] = src[i]
record.field = value
```

Index and field assignment are place operations, not function calls.

### Return

```lua
return
return x
return a + b
```

Current function lowering expects a single returned value or no value.

### If / Elseif / Else

```lua
if x < lo then
  return lo
elseif x > hi then
  return hi
else
  return x
end
```

Conditions are expressions. Every path in a function body still has to
terminate.

### Loops

The parsed source loop is a finite analyzable domain loop. It is not a general
imperative `for`/`while` construct. In Lalin source, `loop` means:

> iterate over a statically described domain and produce explicit loop facts for
> the compiler.

Use `loop` for data movement, maps, reductions, scans, and other stencil-shaped
work. Use regions for explicit control protocols, state-machine-like flow, and
non-loop control transfers.

This is an intentional mental model difference from Lua, C, or Python. A source
loop is not where arbitrary code goes. A loop body must remain admissible as
domain work: stores, fold/scan sinks, pure scalar/index computation, simple
predicates, and analyzable memory indexing.

```lua
loop i in 0 .. n do
  dst[i] = src[i]
end
```

With an explicit step:

```lua
loop i in 0 .. n .. 2 do
  dst[i] = 0
end
```

The 1D range form lowers through a control-region representation, but that is an
implementation detail. Semantically, source `loop` is a domain loop. If the
compiler cannot form a valid producer/sink model, it should reject the loop with
a loop diagnostic rather than treating it as arbitrary imperative control.

Loops can carry a reducer or inclusive scan sink. A reducing loop declares its
result type after the producer and places one `fold` statement directly in the
loop body:

```lua
fn dot(lhs: ptr[i32], rhs: ptr[i32], n: index): i32
  requires bounds(lhs)(n), readonly(lhs), bounds(rhs)(n), readonly(rhs)
  loop i in 0 .. n: i32 do
    fold acc: i32 = 0 by add step lhs[i] * rhs[i]
  end
end
```

A scan loop writes each inclusive accumulator value into a destination:

```lua
fn prefix_sum(dst: ptr[i32], xs: ptr[i32], n: index): void
  requires bounds(dst)(n), writeonly(dst), bounds(xs)(n), readonly(xs)
  requires disjoint(dst)(xs)
  loop i in 0 .. n do
    scan acc: i32 = 0 by add step xs[i] into dst[i]
  end
end
```

`fold` and `scan` accept one reducer name: `add`, `mul`, `band`, `bor`,
`bxor`, `min`, or `max`. A loop may contain at most one sink.

Parsed loops also support multi-axis producers. The loop index list must match
the producer axis count:

```lua
loop i, j in grid(0 .. h, 0 .. w) do
  dst[i * w + j] = src[i * w + j]
end
```

Tiled producers add tile metadata:

```lua
loop i, j in tiled grid(0 .. h, 0 .. w) by 2, 2 do
  scan acc: i32 = 0 by add over j step xs[i * w + j] into dst[i * w + j]
end
```

Window producers add neighbor metadata:

```lua
loop i in window(0 .. n, before = 1, after = 1, boundary = clamp) do
  dst[i] = xs[i - 1]
end
```

ND scans must specify `over`; the value may be an axis number or axis name.

Allowed loop body forms are intentionally narrow:

- stores to an analyzable destination
- one `fold` sink, or one `scan` sink
- `let` bindings for pure scalar/index expressions
- simple `if` predicates whose branches remain admissible loop bodies
- arithmetic, comparison, boolean logic, casts, and indexing

Rejected loop body forms include:

- arbitrary calls unless a later pass marks them pure/inlinable
- `region`, `jump`, or `emit`
- host escapes after parsing
- unknown side effects
- nested loops for now
- mutation not expressible as the loop sink/store

### Jump

`jump` transfers control to a region block or continuation exit:

```lua
jump loop(i = i + 1)
jump done(result = acc)
```

Payload entries may be named:

```lua
jump done(result = x)
```

or positional:

```lua
jump done(x)
```

### Emit

`emit` composes a region-like callee into the current control context:

```lua
emit finish(result)
```

The parser records the callee expression and optional handlers. Region
composition support is still narrower than ordinary function lowering.

---

## Expressions

### Literals

```lua
0
42
3.14
true
false
"hello"
nil
```

Integer and float literal typing is resolved during typechecking and lowering.

### Names

```lua
x
dst
some_binding
```

Names resolve through the active binding environment.

### Arithmetic

```lua
a + b
a - b
a * b
a / b
a // b
a % b
-a
```

`//` is parsed as integer division. Backend support depends on the typed
operation selected during lowering.

### Bit Operations

```lua
a & b
a | b
a ~ b
a << b
a >> b
```

Unary `&x` and `*p` are parsed as address and dereference operators:

```lua
&x
*p
```

### Comparisons

```lua
a == b
a ~= b
a < b
a <= b
a > b
a >= b
```

Comparisons lower to typed compare expressions.

### Boolean Logic

```lua
a and b
a or b
not a
```

### Calls

```lua
f(a, b)
bounds(xs)(n)
```

Calls are ordinary expression calls. Contract helpers such as `bounds` and
`disjoint` are represented this way in parsed syntax before semantic conversion.

### Indexing

```lua
xs[i]
matrix[i * width + j]
```

Index expressions can appear in value position or place position.

### Field Access

```lua
pair.left
pair.right
```

Field access can also appear in place position:

```lua
pair.right = 42
```

### Cast

```lua
as [i32](x)
as [f64](count)
```

The parsed conversion currently emits a surface cast; typechecking/lowering
selects the concrete machine cast.

### Sizeof

```lua
sizeof [Pair]
sizeof [i32]
```

`sizeof` produces a size expression for the target type.

### Host Escape

Host escapes splice Lua values into parsed syntax at construction time:

```lua
local scale = 4

local copy_scale = fn copy_scale(dst: ptr[i32], src: ptr[i32], n: index): void
  loop i in 0 .. n do
    dst[i] = src[i] * [scale]
  end
end
```

The expression inside `[...]` is evaluated in the Lua environment captured at
the syntax site. The resulting Lua value is converted into a Lalin literal when
possible.

---

## Regions

Regions are explicit control protocols. They are the source construct to reach
for when the problem is control flow rather than domain iteration.

Use regions for:

- named continuations and exits
- state-machine-like flow
- repeated control steps that are not stencil/domain loops
- explicit transfer with payloads
- control protocols consumed by another dialect/member

A region has:

- input data parameters
- continuation exits
- one or more `entry` / `block` labels
- explicit `jump` terminators

Shape:

```lua
region name(inputs; exits)
  entry start(...)
    ...
  end

  block next(...)
    ...
  end
end
```

Example:

```lua
region clamp_region(x: i32, lo: i32, hi: i32; done(result: i32))
  entry start()
    if x < lo then
      jump done(result = lo)
    end

    if x > hi then
      jump done(result = hi)
    end

    jump done(result = x)
  end
end
```

Continuation exits can be written with a colon:

```lua
region r(x: i32; done: (result: i32), fail: ())
  entry start()
    jump done(result = x)
  end
end
```

or without it:

```lua
region r(x: i32; done(result: i32))
  entry start()
    jump done(result = x)
  end
end
```

Payload fields may be named or anonymous:

```lua
done(result: i32)
done(i32)
```

Parsed region parsing is implemented. The most mature end-to-end path today is
function/struct/union conversion; region integration is still narrower.

---

## Contracts And Memory Facts

Contracts describe semantic facts the compiler is allowed to rely on.

Common contracts:

```lua
requires bounds(xs)(n)
requires bounds(dst)(n), bounds(src)(n)
requires readonly(xs)
requires writeonly(dst)
requires disjoint(dst)(src)
```

Typical meanings:

| Contract | Meaning |
|---|---|
| `bounds(ptr)(n)` | memory object has at least `n` elements available |
| `readonly(ptr)` | function does not write through this pointer |
| `writeonly(ptr)` | function writes but does not read old values through this pointer |
| `disjoint(a)(b)` | pointer-backed memory objects do not alias |

These contracts feed:

- `MemBackendAccessInfo`
- non-trapping memory proofs
- lane selection facts
- copy/map/reduce skeleton recognition
- MC/BC stencil artifact selection

If a source loop has missing memory proofs, the kernel planner may reject
stencil selection. Internal generated control can still be represented as
ordinary block code, but source `loop` is the domain/stencil-facing construct.

---

## Loops And Backend Recognition

A parsed 1D domain loop:

```lua
fn copy_scale(dst: ptr[i32], src: ptr[i32], n: index): void
  requires bounds(dst)(n), bounds(src)(n), disjoint(dst)(src)

  loop i in 0 .. n do
    dst[i] = src[i] * 2
  end
end
```

lowers through control-region blocks, then the backend records producer, body,
sink, memory, effect, and schedule facts. The backend recognizes semantic
shapes, not textual patterns.

For source `loop`, forming those facts is part of the language contract. Missing
memory proofs, unsupported body forms, or unsupported producer/sink combinations
should become diagnostics instead of silently becoming general imperative loops.

Supported stencil families include:

- copy
- fill
- map and zip-map
- cast
- compare and zip-compare
- select
- gather and scatter
- in-place map
- reduce, count, find
- generic `apply_n`, `reduce_n`, and `scan_n`
- scan
- scatter-reduce

Facts determine whether a valid source loop becomes:

- a stencil machine call/effect
- an MC copy+compile residual artifact
- a BC fallback artifact
- a typed reject

The internal IR can still contain generic control regions. That is how regions,
lowering internals, and generated control are represented. The public source
`loop` surface is narrower: it is a finite domain loop intended to become
stencil-shaped backend facts.

---

## Backend Defaults

The default executable backend is LuaJIT artifact generation with MC
copy+compile residual materialization.

```text
typed Lalin module
  -> LuaJIT IR projection
  -> stencil descriptors
  -> residual_mc bank stencil
  -> optional TCC residual glue
  -> loaded module
```

If MC materialization needs a prebuilt bank that is not available, the default
path falls back to `residual_bc` and emits a warning. Disable that fallback
with `allow_bc_fallback = false`.

```lua
local warnings = {}

local module = lalin.compile("demo", decls, {
  collect_warnings = warnings,
})
```

Explicit BC mode:

```lua
local module = lalin.compile("demo", decls, {
  residual = "bc",
})
```

Strict MC mode requires an MC bank. Use the plan API when you want to make
missing or stale MC materialization a hard error:

```lua
local plan = lalin.plan_luajit_artifact(decls, {
  name = "Demo",
  residual = "mc",
})

local bank = assert(plan.backend.build_mc_bank(plan.artifacts, {
  stem = "demo_mc_bank",
}))

local result = assert(plan.backend.compile_lj_module(plan.lj_module, plan.artifacts, {
  mc_bank = bank,
  allow_bc_fallback = false,
  chunk_name = "Demo",
}))

local module = result.module
```

Explicit artifact emission:

```lua
local plan = lalin.plan_luajit_artifact(decls, {
  name = "Demo",
  residual = "mc",
})

local bank = assert(plan.backend.build_mc_bank(plan.artifacts, {
  stem = "demo_mc_bank",
}))

local artifact = lalin.emit_luajit_plan_artifact(plan, {
  name = "Demo",
  path = "target/artifacts/demo.lua",
  mc_bank = bank,
})
```

### C / AOT Emission

Use `emit_c_artifact` when the desired product is a C artifact that the user
compiles as a native program or library:

```lua
local artifact = lalin.emit_c_artifact(decls, {
  name = "demo",
  c_path = "target/demo.c",
  h_path = "target/demo.h",
  combined_path = "target/demo_combined.c",
})
```

The C path is intentionally simple at the boundary: lower the typed program,
fuse selected stencil-shaped work at C level, emit C, then compile that C with
`gcc` or the user's chosen C toolchain. It is the whole-program AOT path. The
LuaJIT MC/BC paths are runtime artifact paths for Lua-hosted modules.

---

## DSL Syntax

The Lua/LLBL DSL is the programmatic construction surface. It is ordinary Lua
that constructs Lalin declarations through staged heads.

Use the DSL when:

- generating declarations with Lua functions
- writing macros
- sharing fragments
- using ND/tiled/window producer heads today
- composing Lalin with other LLBL members

### Setup

```lua
local lalin = require("lalin")
lalin.language.use()
```

This installs the usual namespace values, including `lln`.

### Function

```lua
local add = lln.fn. add { a [lln.i32], b [lln.i32] } [lln.i32] {
  lln.ret (a + b),
}
```

### Struct

```lua
local Pair = lln.struct. Pair {
  left [lln.i32],
  right [lln.i32],
}
```

### Contracts

```lua
lln.requires {
  lln.bounds(xs)(n),
  lln.readonly(xs),
}
```

### Let, Var, Set, Return

```lua
lln.let. x [lln.i32] (1)
lln.var. acc [lln.i32] (0)
set (acc)(acc + x)
lln.ret (acc)
```

### Conditionals

```lua
lln.when (n :eq (0)) {
  lln.ret (0),
}
```

### 1D Loop

```lua
lln.loop. i [lln.range { 0, n }] {
  set (dst[i])(src[i]),
}
```

### ND Range

```lua
lln.loop { i, j } [lln.range_nd { { 0, h }, { 0, w } }] {
  set (dst[i * w + j])(src[i * w + j]),
}
```

### Tiled ND

```lua
lln.loop { i, j } [lln.tiled_nd {
  axes = { { 0, h }, { 0, w } },
  tiles = { 2, 2 },
}] {
  set (dst[i * w + j])(src[i * w + j]),
}
```

### Window ND

```lua
lln.loop { i } [lln.window_nd {
  axes = { { 0, n } },
  windows = { { 1, 1, boundary = "clamp" } },
}] {
  set (dst[i])(xs[i - 1] + xs[i] + xs[i + 1]),
}
```

### Fold And Scan

The DSL has reducer heads for folds and scans used by the native-loop backend.

```lua
lln.loop. i [lln.range { 0, n }] [lln.i32] {
  lln.fold. acc [lln.i32] {
    init = 0,
    by = lln.add,
    step = xs[i],
  },
}
```

```lua
lln.loop { i, j } [lln.range_nd { { 0, h }, { 0, w } }] {
  lln.scan. acc [lln.i32] {
    init = 0,
    by = lln.add,
    axis = 2,
    step = xs[i * w + j],
    into = dst[i * w + j],
  },
}
```

### Fragments And Splicing

Fragments are Lua values that carry product/list roles.

```lua
local buffer = lln.product {
  p [lln.ptr [lln.u8]],
  n [lln.index],
}

local first = lln.fn. first { _(buffer) } [lln.u8] {
  lln.ret (p[0]),
}
```

`_(fragment)` is the common splice form. `spread(fragment)` is the explicit
fallback.

### Compiling DSL Values

```lua
local module = lalin.compile("demo", { add })
```

or:

```lua
local unit = lalin.unit("demo", { add })
local module = lalin.compile("demo", unit)
```

---

## Formatting

Lalin formatting formats evaluated Lalin/LLBL values, not arbitrary source text.

```sh
luajit scripts/lalinfmt.lua demo.lua
luajit scripts/lalinfmt.lua --check demo.lua
luajit scripts/lalinfmt.lua --write demo.lua
```

Programmatic API:

```lua
local lalin = require("lalin")

local text = lalin.format(value)
local text = lalin.format_file("demo.lua")
lalin.write_format_file("demo.lua")
```

The formatter currently prints the Lua/LLBL DSL surface.

---

## Current Parsed Surface Status

| Construct | Status |
|---|---|
| `fn name(params): result ... end` | implemented |
| `struct Name ... end` | implemented |
| `union Name ... end` | implemented |
| `region name(params; exits) ... end` | parser implemented; integration is narrower than function/struct/union |
| `module Name ... end` | internal parser surface only; not the public module model |
| `let` / `var` | implemented |
| assignment | implemented |
| `return` | implemented |
| `requires` | implemented |
| `if` / `elseif` / `else` | implemented |
| `loop i in 0 .. n do ... end` | implemented |
| parsed `fold` / `scan` inside loops | implemented |
| parsed `grid`, `tiled grid`, `window` domains | implemented |
| host escapes `[lua_expr]` | implemented |
| `as [T](expr)` | implemented |
| `sizeof [T]` | implemented |
| source `while`, `break`, `continue` | not supported |
