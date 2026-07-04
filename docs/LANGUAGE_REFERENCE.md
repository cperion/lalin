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
- Types are Lua values.
- Typed binders use `name[lua_type]` or `name [lua_type]`; the bracket
  expression must evaluate to a Lalin type value.
- Type constructors are Lua values too. Use `ptr [i32]`, `array [i32] [4]`,
  `view [i32]`, and similar constructor calls inside the outer type escape.
- Every block path terminates.
- Region protocols are explicit named exits.
- Memory identity and access are explicit: handles are durable names, leases are temporary access facts, and owned values are exactly-once obligations.
- Backend facts are explicit ASDL facts.

---

## Loading `.lln` Source

The official source extension is `.lln`. A `.lln` file is a Lua-native value
chunk with Lalin parsed syntax active by default. It does not define a separate
module system. Use Lua `require`, return Lua values, and compose public APIs with
tables.

```lln
local add = fn(a [i32], b [i32]) [i32]
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
declarations, ordinary Lua values, or a compiled runtime API table.
`lalin.compile` accepts a parsed declaration, an array of declarations, or a Lua
API table containing declarations:

```lua
local lalin = require("lalin")

local chunk = assert(lalin.loadstring([[
  return {
    add = fn(a [i32], b [i32]) [i32]
      return a + b
    end
  }
]], "@add.lln"))

local parsed_decls = chunk()
local compiled = lalin.compile("add", parsed_decls)

print(compiled.add(3, 4))
```

The lower-level `llbl.syntax` mixed-source driver remains infrastructure for
Lua-hosted syntax islands and tooling, not the standard `.lln` loading surface.

---

## Parsed Metaprogramming

LLBL metaprogramming is not string substitution. A `.lln` file is a Lua value
chunk that contains parsed-channel islands. The syntax driver rewrites each
island into an LLBL constructor invocation with:

- `owner`: the dialect that owns the island, such as `lalin`
- `role`: the semantic role, such as declaration, expression, or statement
- `channel`: the delivery channel, such as `parsed:lalin` or `parsed:expr`
- `origin`: source span/provenance for diagnostics and tooling
- `refs`: Lua lexical names captured by host escapes

The constructor is invoked when the Lua chunk evaluates. At that point the
captured Lua environment is available, host escapes are resolved, and the result
is an ordinary Lua value carrying parsed Lalin structure.

The core rule is:

```text
Lua builds values.
LLBL channels deliver syntax islands as values with roles and origins.
The Lalin dialect gives those values typed/backend meaning.
```

### Lua Around Islands

Use ordinary Lua for files, tables, `require`, conditionals, helper functions,
and public APIs. Use parsed Lalin islands for object-language declarations and
fragments:

```lln
local factor = 4

local scale = fn(dst [ptr [i32]], src [ptr [i32]], n [index]) [void]
  requires bounds(dst)(n), writeonly(dst), bounds(src)(n), readonly(src)
  requires disjoint(dst)(src)
  loop i in 0 .. n do
    dst[i] = src[i] * [factor]
  end
end

return {
  scale = scale,
  factor = factor,
}
```

The returned table is the Lua API. There is no separate Lalin import/export
system layered on top of Lua.

### Declaration Values

Parsed declarations are Lua values. They can be collected, returned, filtered,
or passed to `lalin.compile`:

```lln
local decls = {}

decls[#decls + 1] = fn(a [i32], b [i32]) [i32]
  return a + b
end

decls[#decls + 1] = fn(a [i32], b [i32]) [i32]
  return a - b
end

return decls
```

Anonymous source declarations are still named before backend lowering. LLBL
records obvious Lua context such as `local add = fn(...)` and table fields such
as `{ add = fn(...) }`; Lalin uses that as the declaration's public/debug name.
If no Lua slot name exists, Lalin assigns a generated compiler name such as
`__lln_fn_1`. Codegen uses that internal name for symbols, while Lua tables stay
the user-facing API model.

```lln
return {
  add = fn(a [i32], b [i32]) [i32]
    return a + b
  end,
}
```

Compile them from Lua:

```lua
local lalin = require("lalin")
local decls = assert(lalin.loadfile("arith.lln"))()
local arith = lalin.compile("arith", decls)
```

### Role-Directed HostEval Brackets

Parsed brackets use `[lua_expr]`. The bracket produces an LLBL HostEval value:
it records the Lua source, captured lexical references, bracket origin, and the
expected role supplied by the surrounding parser. Lua evaluation happens when
the syntax constructor runs; adaptation happens later through the current Lalin
role.

The bracket itself does not mean "type" or "expression". The surrounding role
means that.

In expression position, `[lua_expr]` adapts:

- primitive literals: numbers, booleans, strings, `nil`
- parsed expression fragments
- parsed expression AST values
- already-constructed LalinTree expression values

```lln
local factor = 3
local bias = 5

local scaled = expr x * [factor] + [bias] end

local scale_one = fn(x [i32]) [i32]
  return [scaled]
end
```

In statement-list position, `[lua_expr]` can splice:

- a parsed statement fragment
- a parsed statement AST value
- an array of statement fragments/statements
- already-constructed LalinTree statement values

```lln
local factor = 3

local scale_step = stmt
  dst[i] = src[i] * [factor]
end

local scale = fn(dst [ptr [i32]], src [ptr [i32]], n [index]) [void]
  requires bounds(dst)(n), writeonly(dst), bounds(src)(n), readonly(src)
  requires disjoint(dst)(src)
  loop i in 0 .. n do
    [scale_step]
  end
end
```

In type position, `[lua_expr]` adapts under the `type` role. The Lua expression
may evaluate to a Lalin type value or to a declaration value with a stable type
identity:

- built-in scalar type values such as `i32`, `f64`, or `index`
- constructor results such as `ptr [i32]`, `array [i32] [4]`, or `view [i32]`
- named type values such as `named("Pair")`
- parsed or DSL declarations such as `DeclStruct`, `DeclUnion`, or `DeclHandle`
  when their names define type identities
- values produced by Lua helper functions, factories, or required packages

```lln
local elem_ty = i32
local ptr_elem_ty = ptr [elem_ty]

local Pair = struct Pair
  value [i32]
end

local use_pair = fn(p [Pair]) [void]
  return
end

local scale = fn(dst [ptr_elem_ty], src [ptr_elem_ty], n [index]) [void]
  requires bounds(dst)(n), writeonly(dst), bounds(src)(n), readonly(src)
  requires disjoint(dst)(src)
  loop i in 0 .. n do
    dst[i] = src[i]
  end
end
```

In product/field-list positions, `[lua_expr]` adapts under the product role and
can splice generated fields:

```lln
local header_fields = {
  { tag = "Field", name = "len", type = i32 },
}

local Packet = struct Packet
  [header_fields]
  payload [ptr [u8]]
end
```

At declaration-stream boundaries, `[lua_expr]` adapts under the `decls` role.
The value may be one declaration, a positional array of declarations, or a
role-compatible declaration fragment. Positional order is preserved. Keyed Lua
tables are accepted only when the keyed values are parsed declarations; string
keys are applied as deterministic public/debug names in sorted-key order.

```lln
local generated = make_declarations()
[generated]
```

Parsed expression indexing is a hard boundary:

```lln
a[x]          -- parsed Lalin index expression
[make()][i]   -- HostEval expression, then parsed index postfix
[ptr [Pair]]  -- one HostEval; the inner brackets are Lua source
```

### Fragments

The parsed channel has `expr` and `stmt` entrypoints. They produce role-bearing
Lua values with parsed origins, not text snippets:

```lln
local rhs = expr x + 1 end

local store = stmt
  dst[i] = [rhs]
end
```

Fragments can close over Lua values through their own host escapes and can be
spliced into later parsed islands. This is the parsed-channel analogue of LLBL
role-tagged fragments in the Lua DSL.

### Requiring `.lln` Packages

`.lln` packages compose through Lua `require` and returned values:

```lln
local cfg = require("scale_config")

local scale = fn(dst [ptr [i32]], src [ptr [i32]], n [index]) [void]
  requires bounds(dst)(n), writeonly(dst), bounds(src)(n), readonly(src)
  requires disjoint(dst)(src)
  loop i in 0 .. n do
    dst[i] = src[i] * [cfg.factor]
  end
end

return {
  scale = scale,
  cfg = cfg,
}
```

This is still LLBL: Lua carries package values, LLBL carries language islands,
and Lalin owns the meaning of those islands.

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
fn struct union handle region
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

Typed binders use role-directed bracket application: `name[type_value]` or
`name [type_value]`. Function results, casts, and `sizeof` use the same
bracketed type role.

The expression inside the brackets is evaluated by Lua and adapts under the
Lalin `type` role. It may produce a Lalin type value or a named declaration
value:

```lln
[i32]
[ptr [i32]]
[array [i32] [4]]
[view [i32]]
[named("Pair")]
```

There is no separate parsed type grammar. `i32` is not a parsed keyword in type
position; it is a Lua value supplied by the `.lln` environment. `ptr [i32]` is a
Lua bracket-call on the `ptr` type constructor. The outer binder brackets are
also Lua-like bracket application, so both `x[i32]` and `x [i32]` are accepted.

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

```lln
[ptr [i32]]
[array [i32] [4]]
[slice [u8]]
[view [f32]]
[named("MyStruct")]
[pkg.SomeType]
```

Any Lua expression is legal between the brackets if it adapts to the `type`
role. For named declarations, `[Pair]` can project a parsed or DSL `struct Pair`
/ `union Pair` declaration to a named type, and handle declarations project to
handle types. You can still use `named("TypeName")` or return/pass type values
from another Lua package when that is clearer.

### Access, Lease, And Ownership Types

The type vocabulary also carries borrow-checking facts:

```lln
[readonly [ptr [Store]]]
[writeonly [ptr [i32]]]
[noalias [ptr [u8]]]
[noescape [ptr [i32]]]
[preserve [ptr [Store]]]
[invalidate [ptr [Store]]]
[lease [ptr [Record]]]
[lease [view [f32]]]
[owned [ResourceRef]]
```

Access wrappers refine how a parameter may be used. `readonly` and `preserve`
are preserving accesses for lease grants; `writeonly`, `invalidate`, and plain
mutable pointer/view parameters are conservative invalidators. `noescape` says a
callee may use an access value but must not retain it.

A `lease` is temporary access, normally produced by a resolver region or trusted
boundary. Its base must be `ptr(T)` or `view(T)`. When a lease is tied to a store
parameter, use an explicit origin in the Lua type expression, for example
`lease("store", ptr [Record])` when `Record` is a type value in scope;
diagnostics print this idea as
`lease(store) ptr(Record)`. Leases may appear in function, region, block, and
continuation parameters, but not in durable positions such as struct fields,
static/const values, union payloads, function results, or generated region-call
result objects.

An `owned T` is linear authority to release, close, retire, or transfer a
resource exactly once. There is no destructor or inferred drop. The base must be
a durable token such as a handle/resource value, not a raw pointer, view, lease,
access wrapper, or another owned value. Owned obligations stay in control flow;
they are not storable data.

### Function Signatures

Functions declare parameter products and a single result type:

```lln
local distance2 = fn(x [f32], y [f32]) [f32]
  return x * x + y * y
end
```

Use `void` for functions that do not return a value:

```lln
local clear = fn(dst [ptr [i32]], n [index]) [void]
  loop i in 0 .. n do
    dst[i] = 0
  end
end
```

---

## Declarations

### Functions

```lln
local add = fn(a [i32], b [i32]) [i32]
  return a + b
end
```

Functions are Lua values at source level and typed function items after Lalin
normalization. Parameters are immutable values. Mutable local state is
introduced with `var`.

### Structs

```lln
struct Pair
  left [i32]
  right [i32]
end
```

Fields are named and typed. Struct field access uses dot syntax:

```lua
p.right
```

### Unions

```lln
union OptionI32
  Some(value [i32])
  None
end
```

Variants may have named payload fields or no payload. Union payloads are durable
stored data, so they cannot contain leases or owned obligations.

### Handles

A handle is a nominal durable identity value. It may be copied, stored, compared
with the same handle type, passed, and returned. It is not dereferenceable, not
indexable, and not implicitly convertible to its integer representation.

Handle declarations are available in parsed `.lln` syntax:

```lln
local AudioBufferStore = struct AudioBufferStore
  capacity [index]
end

local AudioBufferRecord = struct AudioBufferRecord
  first [index]
end

local AudioBuffer = handle AudioBuffer [u32]
  invalid = 0
  domain [AudioBufferStore]
  target [AudioBufferRecord]
end
```

The same declaration can be generated from the Lua/LLBL DSL:

```lua
local AudioBuffer = lln.handle. AudioBuffer {
  invalid = 0,
  domain = "AudioBufferStore",
  target = "AudioBufferRecord",
}
```

The representation defaults to `u32`; a DSL declaration may choose another
scalar representation with `repr`. `domain` names the store/namespace that can
validate the handle. `target` names the logical product that a successful
resolver may grant as a lease. These are type facts, not comments, and they do
not create implicit dereference.

Trusted store code can cross the representation boundary with explicit
`repr(handle)` / `Handle.from_repr(raw)` operations. Ordinary safe casts do not
convert handles to or from scalars.

### Files And Values

Lalin does not add a user-facing module declaration. A `.lln` file is a Lua
value chunk. Return the declarations or runtime values the caller should see:

```lln
local add = fn(a [i32], b [i32]) [i32]
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

```lln
requires bounds(dst)(n), bounds(src)(n), disjoint(dst)(src)
requires readonly(src), writeonly(dst)
```

Contracts are not comments. They feed memory classification, non-trapping
proofs, alias proofs, kernel planning, and stencil selection.

### `let`

`let` introduces an immutable local binding:

```lln
let x [i32] = 1
let y [i32] = x + 2
```

If an initializer is omitted, the current conversion supplies a zero literal.
Prefer writing the initializer explicitly.

### `var`

`var` introduces mutable local storage:

```lln
var acc [i32] = 0
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

```lln
loop i in 0 .. n do
  dst[i] = src[i]
end
```

With an explicit step:

```lln
loop i in 0 .. n .. 2 do
  dst[i] = 0
end
```

The 1D range form lowers through a control-region representation, but that is an
implementation detail. Semantically, source `loop` is a domain loop. If the
compiler cannot form a valid producer/sink model, it should reject the loop with
a loop diagnostic rather than treating it as arbitrary imperative control.

Loops can carry a reducer or inclusive scan sink. A reducing loop places one
`fold` statement directly in the loop body; the fold accumulator type is the
reduction result type:

```lln
local dot = fn(lhs [ptr [i32]], rhs [ptr [i32]], n [index]) [i32]
  requires bounds(lhs)(n), readonly(lhs), bounds(rhs)(n), readonly(rhs)
  loop i in 0 .. n do
    fold acc [i32] = 0 by add step lhs[i] * rhs[i]
  end
end
```

A scan loop writes each inclusive accumulator value into a destination:

```lln
local prefix_sum = fn(dst [ptr [i32]], xs [ptr [i32]], n [index]) [void]
  requires bounds(dst)(n), writeonly(dst), bounds(xs)(n), readonly(xs)
  requires disjoint(dst)(xs)
  loop i in 0 .. n do
    scan acc [i32] = 0 by add step xs[i] into dst[i]
  end
end
```

`fold` and `scan` accept one reducer name: `add`, `mul`, `band`, `bor`,
`bxor`, `min`, or `max`. A loop may contain at most one sink.

Parsed loops also support multi-axis producers. The loop index list must match
the producer axis count:

```lln
loop i, j in grid(0 .. h, 0 .. w) do
  dst[i * w + j] = src[i * w + j]
end
```

Tiled producers add tile metadata:

```lln
loop i, j in tiled grid(0 .. h, 0 .. w) by 2, 2 do
  scan acc [i32] = 0 by add over j step xs[i * w + j] into dst[i * w + j]
end
```

Window producers add neighbor metadata:

```lln
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

```lln
0
42
3.14
true
false
"hello"
nil
```

Integer and float literal typing is resolved during typechecking and lowering.
Integer literals can adopt an expected integer type. Float literals can adopt an
expected `f32` or `f64` type. `nil` can adopt an expected pointer type.

String literals are byte slices:

```lln
let bytes [slice [u8]] = "A\n"
return as [i32](bytes[0])
```

The compiler stores the decoded Lua string bytes in module data and produces a
`slice [u8]`. The slice length is the number of string bytes; backend storage may
include a trailing NUL for C/LuaJIT interop, but that byte is not part of the
slice length.

Brace literals are contextual:

```lln
let xs [array [i32] [3]] = { 10, 20, 12 }
let pair [named("Pair")] = { left = 20, right = 22 }
```

Positional braces lower to array literals. Named braces lower to struct
aggregate literals. A single brace literal cannot mix positional and named
fields. Empty `{}` is accepted only where the expected type makes the aggregate
meaning unambiguous.

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

```lln
as [i32](x)
as [f64](count)
```

The parsed conversion currently emits a surface cast; typechecking/lowering
selects the concrete machine cast.

### Sizeof

```lln
sizeof [named("Pair")]
sizeof [i32]
```

`sizeof` produces a size expression for the target type.

### Host Escape

Host escapes splice Lua values into parsed syntax at construction time:

```lln
local scale = 4

local copy_scale = fn(dst [ptr [i32]], src [ptr [i32]], n [index]) [void]
  loop i in 0 .. n do
    dst[i] = src[i] * [scale]
  end
end
```

The expression inside `[...]` is evaluated in the Lua environment captured at
the syntax site. In expression position, primitive Lua values become Lalin
literals and expression fragments/ASDL expressions are spliced directly.

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

```lln
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

```lln
region clamp_region(x [i32], lo [i32], hi [i32]; done(result [i32]))
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

Continuation exits use direct payload application:

```lln
region r(x [i32]; done(result [i32]))
  entry start()
    jump done(result = x)
  end
end
```

Payload fields may be named or anonymous:

```lln
done(result [i32])
done([i32])
```

Parsed region parsing is implemented. The most mature end-to-end path today is
function/struct/union conversion; region integration is still narrower.

---

## Contracts And Memory Facts

Contracts describe semantic facts the compiler is allowed to rely on.

Common contracts:

```lln
requires bounds(xs)(n)
requires bounds(dst)(n), bounds(src)(n)
requires readonly(xs)
requires writeonly(dst)
requires noalias(tmp)
requires disjoint(dst)(src)
requires preserve(store)
requires invalidate(store)
```

Typical meanings:

| Contract | Meaning |
|---|---|
| `bounds(ptr)(n)` | memory object has at least `n` elements available |
| `readonly(ptr)` | function does not write through this pointer |
| `writeonly(ptr)` | function writes but does not read old values through this pointer |
| `noalias(ptr)` | pointer-backed memory object has no aliases in this access context |
| `disjoint(a)(b)` | pointer-backed memory objects do not alias |
| `preserve(store)` | call preserves leases associated with this store/domain access |
| `invalidate(store)` | call may move, free, compact, clear, or reuse storage for this store/domain |

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

## Borrow Checking, Handles, And Ownership

Lalin's borrow checking is region-shaped rather than Rust-shaped. The core
rules are:

```text
Handles may escape. Leases may not.
Stores own bytes. Regions grant access facts.
Owned values must be discharged exactly once.
```

A raw `ptr(T)` is only an address. Durable identity is a handle. Temporary
memory access is a lease, usually granted by a resolver region or by a trusted
boundary contract.

### Handle Resolution

A resolver takes a handle plus access to its domain store and exposes access only
through its successful continuation:

```lln
region borrow_audio_buffer(
  store [readonly [ptr [AudioBufferStore]]],
  buffer [AudioBuffer];
  borrowed(record [lease("store", ptr [AudioBufferRecord])]),
  stale(buffer [AudioBuffer]),
  missing(buffer [AudioBuffer])
)
  entry start()
    -- store-private validation and jump borrowed/stale/missing
  end
end
```

For a handle with `target = "AudioBufferRecord"`, a resolver may only grant a
lease to that target type. For a handle with `domain = "AudioBufferStore"`, the
resolver must take the owning domain as a `readonly` or `preserve` access and
tie the lease origin to that domain parameter. Anonymous leases are allowed for
simple boundary access, but store leases need an origin so invalidation checks
can tell which store they came from.

### Lease Escape Rules

A lease is temporary access. The checker rejects leases in durable type
positions and in expression-style region-call result objects. In source terms:

- do not return a lease as durable identity
- do not store a lease in a struct, union payload, const, static, array, or
  closure-like aggregate
- do not pass a lease to a retaining plain `ptr`/`view` parameter; use a lease or
  `noescape` parameter
- use `emit`/explicit continuations for region protocols whose payload carries a
  lease; do not box that protocol into a generated result union

Field lookup and indexing can use lease bases, so a `lease ptr(T)` behaves like
temporary access to `T` while it is in scope.

### Invalidation Rules

An operation that may move, free, compact, clear, or reuse a store cannot run
while leases from that same store are live. Mark preserving APIs with
`readonly`, `preserve`, or `requires preserve(store)`. Mark invalidating APIs
with `invalidate` or `requires invalidate(store)`. Unannotated mutable
`ptr`/`view` parameters are conservative invalidators.

End the lease scope before calling an invalidating operation, or redesign the
protocol so the resolver grants the lease only inside the continuation that uses
it.

### Owned Obligations

`owned T` is linear authority, not a managed pointer. The checker treats it as a
CFG obligation:

- it must be transferred to another `owned` parameter/result/continuation or
  consumed by a close/retire/destroy protocol
- it cannot be copied or observed as plain `T`
- it cannot be stored in durable fields/statics or hidden in aggregates
- continuing branches must preserve the same live owned-obligation set
- `var owned T` is rejected; thread ownership through `let`, returns, jumps, and
  continuations instead

There are no semantic destructors. If a resource changes lifetime, name the
region/function that does it and state whether it consumes or returns the owned
obligation.

---

## Loops And Backend Recognition

A parsed 1D domain loop:

```lln
local copy_scale = fn(dst [ptr [i32]], src [ptr [i32]], n [index]) [void]
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

Supported stencil vocabulary is structural:

- `StoreN`: producer plus N-input point body plus store sink
- `ReduceN`: producer plus N-input point body plus reduce sink
- `ScanN`: producer plus N-input point body plus scan sink
- `ScatterReduceN`: producer plus N-input point body plus indexed reduce sink

Here `_n` always means point input count: the number of logical input
streams referenced by the point body. It does not mean rank, output count,
loop axes, fused stage count, or a derived backend family.

Source patterns such as scalar fill, copy, indexed reads/writes, casts,
comparisons, and blends are configurations of those descriptors, not separate
backend families.

Facts determine whether a valid source loop becomes:

- native template graph nodes selected from a matching `NativeTemplateBank`
- an explicit LuaJIT bytecode artifact when that non-native mode is selected
- a typed reject

The internal IR can still contain generic control regions. That is how regions,
lowering internals, and generated control are represented. The public source
`loop` surface is narrower: it is a finite domain loop intended to become
stencil-shaped backend facts.

---

## Backend Defaults

The default executable backend is native copy-patch. It requires a supplied
`NativeTemplateBank` or `NativeEmbeddedTemplateBank` whose target and
`NativeTemplateSourceManifest` match the program being compiled.

```text
inferred Lalin compilation unit
  -> LalinCode / LalinKernel / LalinStencil facts
  -> NativeTemplateGraph and ABI projection
  -> supplied NativeTemplateBank selection
  -> copy code/constant-pool bytes
  -> patch typed holes, continuations, constants, and runtime symbols
  -> installed native entry point
```

The runtime native path never runs a C compiler, object parser, linker, object
dumper, shell tool, or alternate backend. If no compatible native bank is
supplied, compilation fails with an explicit diagnostic.

```lua
local bank = require("target.lalin_binary.lalin_native_template_bank")

local module = lalin.compile("demo", decls, {
  native_embedded_bank = bank,
})
```

Equivalent native-bank option names are `native_bank`/`bank` for an imported
`NativeTemplateBank`, and `native_embedded_bank`/`embedded_bank` for an embedded
bank value. A manifest may be supplied as `native_template_manifest`,
`native_manifest`, or `template_manifest` when the caller wants an exact manifest
check.

Native public ABI projections support zero or one result. A scalar result is
returned through the projected return register; aggregate or by-reference result
forms use the projected hidden result pointer. Multiple native results are not a
single function ABI and must be represented before native lowering.

Explicit LuaJIT bytecode mode is selected separately:

```lua
local module = lalin.compile_luajit("demo", decls)

local module2 = lalin.compile("demo", decls, {
  bytecode = true,
})
```

LuaJIT bytecode mode is not a recovery path for a missing native bank, and native
banks are rejected by the LuaJIT artifact APIs.

### Offline Native Template Banks

Use `NativeTemplateBankRequest` and its `NativeTemplateSourceManifest` when you
want to build or reuse a native bank outside the runtime compile path. The
offline generator consumes the request, compiles the generated C stencils ahead
of time, verifies object facts, and emits the checked-in/native binary artifacts:

```sh
luajit tools/gen_lalin_mc_bank.lua \
  target/lalin_binary/lalin_native_template_bank.c \
  target/lalin_binary/lalin_native_template_bank.h \
  target/lalin_binary/lalin_native_template_bank.lua
```

The generated Lua bridge reconstructs a `NativeEmbeddedTemplateBank` carrying the
manifest, target, compiled templates, signatures, extraction facts, hole
ordinals, relocations, and constant-pool layout.

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

The C path emits the selected program as ordinary C translation units. Selected
stencil-shaped bodies are emitted inline in the same generated C artifact. The
user then compiles that C with `gcc` or another C toolchain. It is the
whole-program AOT path, separate from native copy-patch and explicit LuaJIT
bytecode runtime artifact paths.

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

### Handle And Borrowing Types

```lua
local AudioBuffer = lln.handle. AudioBuffer {
  invalid = 0,
  domain = "AudioBufferStore",
  target = "AudioBufferRecord",
}

local borrow_sig = lln.product {
  store [lln.readonly [lln.ptr [lln.named("AudioBufferStore")]]],
  samples [lln.lease("store", lln.view [lln.f32])],
  resource [lln.owned [lln.named("AudioBuffer")]],
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
long-form splice.

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
| `local name = fn(params) [result] ... end` | implemented |
| `fn name(params) [result] ... end` | implemented as explicit direct declaration |
| `struct Name ... end` | implemented |
| `union Name ... end` | implemented |
| `handle Name [repr] ... end` | implemented; handle fact types use bracket type values |
| `region name(params; exits) ... end` | parser implemented; integration is narrower than function/struct/union |
| `let` / `var` | implemented |
| assignment | implemented |
| `return` | implemented |
| `requires` | implemented, including memory/effect contracts such as `bounds`, `readonly`, `writeonly`, `noalias`, `disjoint`, `preserve`, and `invalidate` |
| access / lease / owned type values | implemented through Lua type values in brackets |
| `if` / `elseif` / `else` | implemented |
| `loop i in 0 .. n do ... end` | implemented |
| parsed `fold` / `scan` inside loops | implemented |
| parsed `grid`, `tiled grid`, `window` domains | implemented |
| host escapes `[lua_expr]` | implemented |
| `as [T](expr)` | implemented |
| `sizeof [T]` | implemented |
| source `while`, `break`, `continue` | not supported |
