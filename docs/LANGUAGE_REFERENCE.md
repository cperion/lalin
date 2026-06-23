# Moonlift Lua-Owned DSL Language Reference

## Status

This document describes the Lua-owned Moonlift DSL implemented by
`require("moonlift.dsl")`.

The DSL is ordinary Lua. Lua performs the mechanical parse, evaluates host-time
expressions, and hands real Lua values to Moonlift DSL objects. Declaration and
control heads are hosted by `lua/llb.lua`; the Moonlift DSL grammar then
normalizes those values by role and emits explicit `MoonTree` and `MoonOpen`
ASDL.

There is no second source parser in the normal authoring path.
This is the recommended path for new generated/metaprogrammed Moonlift code.

```text
Lua syntax -> Lua values -> LLB role normalization -> Moonlift ASDL
```

For declaration/control heads, canonical formatting puts the dot on the keyword
side (`fn. add`, `region. scan`, etc.)
with a space before the name target:

```text
fn. add
region. scan
jump. done
emit. scan
```

For single-expression/condition keyword-style forms, use the canonical DSL forms
below to keep intent obvious:

```text
ret (expr)      -- scalar / expression form
yield (expr)    -- scalar / expression form
when (cond) { ... }
```

`ret` and `yield` scalar expressions are written with `()` unless the argument is
a Lua syntax form that is already naturally paren-less (string/aggregate literals).
`when` keeps the paren form for consistency.

Lua tokenization does not treat this as semantic syntax, but the visual rule keeps
declaration/control heads and statement forms distinct from ordinary function calls.

Canonical argument rule:

- `ret`/`yield`: parenthesized form for values generally, except string and aggregate literals that are naturally paren-less in Lua.
- `when`: keep condition in `()`.
- `jump`/`emit`: remain `(...)` (control invocation syntax still needs parens).

This is the central rule:

```text
[] means Lua already evaluated this expression.
```

So:

```lua
x [T]
ptr [T]
fn [name]
as [T](x)
```

carry actual Lua values, not textual splice holes.

## Spacing Convention

A space is placed between every DSL keyword and what follows it, and between
every name and its type bracket. Lua table-access syntax (`[T]`) includes the
space for readability even though Lua does not require it:

```text
name [Type]           -- parameter/field/entry typing
keyword (value)       -- statement or expression keyword
keyword .name         -- declared name, block label, region target
keyword { body }      -- body, continuation, switch arm
```

Concrete rules:

| Form | Do | Don't |
|------|----|----- |
| typed name | `x [i32]` | `x[i32]` |
| type constructor | `ptr [u8]` | `ptr[u8]` |
| cast | `as [i32] (x)` | `as[i32](x)` |
| comparison method | `i :ge (n)` | `i:ge(n)` |
| ret / yield | `ret (expr)` | `ret(expr)` |
| when | `when (cond) { ... }` | `when(cond){...}` |
| let / var | `let. x [i32] { 0 }` | `let.x[i32]{0}` |
| store / set | `store (place, value)` | `store(place,value)` |
| jump | `jump. loop { i = i + 1 }` | `jump.loop{i=i+1}` |
| emit | `emit. scan { args } { fills }` | `emit.scan{args}{fills}` |
| switch | `switch (value) { ... }` | `switch(value){...}` |
| trap / assert_ / assume | `trap ()` | `trap()` |
| afence | `afence ()` | `afence()` |
| requires | `requires { ... }` | `requires{...}` |

### Lua no-parens rule

Lua omits parentheses for single literal arguments. The DSL follows this:
no `()` for a single literal, `()` required for expressions and multi-arity.

```lua
ret 42               -- numeric literal, no parens
ret "done"           -- string literal, no parens
ret { 1, 2, 3 }      -- table literal, no parens
ret true             -- boolean literal, no parens
ret (a + b)           -- expression, parens required
ret ()                -- void return, parens required

assert_ (cond)         -- expression, parens required
store (place, value)   -- multi-arity, parens required
aload (i32, p)         -- multi-arity
```

This convention makes DSL source grep-shaped: `rg 'ret \('` finds returns,
`rg 'jump \.'` finds jumps, `rg 'x \[i32\]'` finds typed names.

## Design Rule

Moonlift structure uses `{}`.

Lua computation and language leaves use `()` when ordinary Lua syntax requires it.

Canonical examples:

```lua
fn. add
  { a [i32], b [i32] }
  [i32]
  {
    ret (a + b),
  }
```

```lua
region. scan
  { p [ptr [u8]], n [index], target [i32] }
  {
    hit  { pos [index] },
    miss,
  }
  {
    entry. loop { i [index](0) } {
      when (i :ge (n)) {
        jump. miss { pos = i },
      },

      jump. loop {
        i = i + 1,
      },
    },
  }
```

## Why This Works

Lua table syntax already models the shapes Moonlift cares about:

```text
array table   -> ordered product/body/protocol entries
record table  -> unordered named maps/fills/options
mixed table   -> ordered children plus attributes
[]            -> evaluated host value in a type/name/static slot
()            -> host-time call or leaf expression construction
```

Moonlift does not need a new parser to understand products, protocols, bodies,
or continuation maps. The shape is already present in the Lua value.

## Loading

### Quick: `moon.use()` for plain `.lua` files

The simplest way to author Moonlift is to call `require("moonlift").use()` at
the top of any `.lua` file. This injects all DSL names (`fn`, `i32`, `module`,
`struct`, `region`, etc.) as Lua globals:

```lua
-- my_module.lua
local moon = require("moonlift")
moon.use()

return module "Demo" {
  fn. add { a [i32], b [i32] } [i32] { ret (a + b) },
}
```

For headers split across files, call `moon.use()` at the top of each `.lua`
file:

```lua
-- math_header.lua
require("moonlift").use()
return { fn. add { a [i32], b [i32] } [i32] }

-- math_impl.lua
require("moonlift").use()
local header = require("math_header")
return module "Math" { header[1] { ret (a + b) } }
```

### `dsl.loadstring()` — inline, isolated env

For programmatic use, `dsl.loadstring()` creates an isolated environment without
touching `_G`:

```lua
local dsl = require("moonlift.dsl")

-- One-shot: compile and execute
local module = dsl.load([[return module "Demo" { ... }]], "demo.lua")

-- From a file
local chunk = dsl.loadfile("demo.lua")
local module = chunk()

-- Module require: finds name.lua or name/init.lua, caches result
local header = dsl.require("math_header")

-- Full pipeline
module:ast()
module:typecheck()
module:lower()
module:compile()
module:emit_c_artifact()
```

### Package searcher integration

Once loaded, the DSL auto-installs a Lua `package.searchers` entry so
plain `require("foo")` automatically finds `foo.lua` files:

```lua
local dsl = require("moonlift.dsl")
dsl.loadstring([[...]], "main")  -- triggers searcher install

-- Now any .lua file can require other .lua files:
local header = require("math_header")  -- finds math_header.lua
```

This enables header/impl split across files with zero ceremony:

```lua
-- math_header.lua
return {
  fn. add { a [i32], b [i32] } [i32],
  fn. sub { a [i32], b [i32] } [i32],
}

-- math_impl.lua
local header = require("math_header")
return module "Math" {
  header[1] { ret (a + b) },
  header[2] { ret (a - b) },
}
```

Strict global mode:

```lua
dsl.loadstring(src, "demo", { strict = true })
```

In strict mode, assignment to a previously unknown global is rejected.

## Modules

```lua
return module "Demo" {
  declarations...
}
```

Module bodies are ordered declaration arrays. Record fields are reserved for
attributes/options where a constructor documents them.

Supported declaration entries:

```text
struct
union
handle
extern
const
static
fn
export_fn
region
expr_frag
_(decls_fragment)
```

In this Lua-owned DSL, module composition is done by Lua `require` and value
splicing (`[]` / `_(...)`), not by a DSL `import` declaration.

### Header / implementation split

The DSL's `fn` and `region` declaration chains are **curried**: supplying
params and result does not create the final declaration. It returns a
**callable LLB stage** waiting for the body. This is the header.

```lua
fn. add { a [i32], b [i32] } [i32]
```

The line above does not produce a final declaration. It produces a callable Lua
stage table.
Call it with a body table to produce the full declaration:

```lua
fn. add { a [i32], b [i32] } [i32] {
  ret (a + b),
}
```

This means headers and implementations can live in separate files:

```lua
-- math_header.lua
return {
  fn. add { a [i32], b [i32] } [i32],
  fn. sub { a [i32], b [i32] } [i32],
}
```

```lua
-- math_impl.lua
local header = require("math_header")
return module "Math" {
  header[1] { ret (a + b) },
  header[2] { ret (a - b) },
}
```

The same pattern works for regions:

```lua
-- io_header.lua
return {
  region. read { fd [i32], buf [ptr [u8]], count [index] } { ok{n[index]}, err{code[i32]} },
  region. write { fd [i32], buf [ptr [u8]], count [index] } { ok{n[index]}, err{code[i32]} },
}
```

What this unlocks:
- **Contract-first design**: sign the protocol before any implementation
- **Signature reuse**: same callable stage can be implemented differently per target
- **Factories**: generate callable stages from parameters; fill bodies later
- **Library mode**: modules export callable stages for callers to wire up

The callable stage is an ordinary Lua value — storable, passable, exportable.
No textual import directives. No parser. No antiquote.

## Names

Fixed names use spaced-dot grammar:

```lua
fn. add
struct. Vec2
region. scan
jump. loop
```

All declaration names (module items, regions, blocks, labels, and other header
positions) are dot-headed by construction. Plain names are reserved for
runtime variables and binds such as `x`, `acc`, and `n`.

Computed names use brackets:

```lua
fn[name]
struct["Vec" .. n]
```

Name tokens in DSL environments are created on demand:

```lua
ret (acc + x)
```

Here `acc` and `x` are name tokens resolved later by Moonlift semantic phases.

For generated names inside arrays, use `N`:

```lua
local fields = {}
for i = 1, 4 do
  fields[#fields + 1] = N["x" .. i] [f32]
end

struct. Vec4 {
  _(fields),
}
```

### Grepability

With dotted declaration names, grep can index DSL structure directly:

```text
# Declaration headers
rg '^\s*(fn|export_fn|struct|union|handle|extern|const|static|expr_frag|region)\.\s+[A-Za-z_][A-Za-z0-9_]*' path/to/dsl/*.md

# CFG structure (entry/block labels, jumps, emits)
rg '\b(entry|block|jump|emit)\.\s+[A-Za-z_][A-Za-z0-9_]*' path/to/*.lua

# Dot-name declarations in the DSL test corpus
rg '^\s*(fn|export_fn|struct|union|handle|extern|const|static|expr_frag|region|entry|block|jump|emit)\.\s+[A-Za-z_][A-Za-z0-9_]*' tests/frontend/test_dsl_lua_owned.lua
```

I verified these against the DSL reference + `tests/frontend/test_dsl_lua_owned.lua`;
no non-dot declaration names appear in that corpus.

## Types

Scalar type values:

```lua
void
bool
i8 i16 i32 i64
u8 u16 u32 u64
f32 f64
index
rawptr
```

Compound type constructors:

```lua
ptr [u8]
view [i32]
slice [u8]
array [i32][16]
fnptr[{ i32, i32 }] [i32]
closure[{ i32 }] [i32]
lease [ptr [u8]]
lease(origin, ptr [u8])
owned [SessionRef]
```

Access wrappers:

```lua
ro [view [i32]]
wo [ptr [u8]]
readonly [view [i32]]
writeonly [ptr [u8]]
noalias [ptr [u8]]
noescape [ptr [u8]]
preserve [ptr [u8]]
invalidate [ptr [u8]]
```

Because `[]` is normal Lua indexing, each type argument is already a Lua value.
No textual type splice is performed.

## Products

Products are ordered array tables of typed names:

```lua
{ a [i32], b [i32] }
```

They appear as:

```text
function parameters
region parameters
struct fields
block parameters
continuation payload fields
union variant fields
```

Initializer form:

```lua
i [index](0)
acc [i32](0)
```

Used in entry block parameters:

```lua
entry. loop { i [index](0), acc [i32](0) } {
  ...
}
```

## Structs

```lua
struct. Vec2 {
  x [f32],
  y [f32],
}
```

Generated fields:

```lua
local xy = product {
  x [f32],
  y [f32],
}

struct. Point {
  _(xy),
  z [f32],
}
```

## Unions

```lua
union. Result {
  ok  { value [i32] },
  err { code [i32] },
  none,
}
```

Union alternatives are ordered array entries. Payload alternatives use named
payload table syntax. No-payload alternatives use bare name tokens.

## Handles

```lua
handle. SessionRef {
  invalid = 0,
}
```

With optional facts:

```lua
handle. SessionRef {
  invalid = 0,
  domain = "SessionStore",
  target = "SessionRecord",
}
```

## Externs

```lua
extern. write
  { fd [i32], buf [ptr [u8]], count [index] }
  [index]
  {
    symbol = "write",
  }
```

Void extern:

```lua
extern. trap
  { code [i32] }
  {
    symbol = "moon_trap",
  }
```

## Constants And Statics

```lua
const. answer [i32] { 42 }
static. zero [i32] { 0 }
```

The type slot receives the actual Lua value `i32`.

## Functions

```lua
fn. add
  { a [i32], b [i32] }
  [i32]
  {
    ret (a + b),
  }
```

Exported function:

```lua
export_fn. add
  { a [i32], b [i32] }
  [i32]
  {
    ret (a + b),
  }
```

Void function:

```lua
fn. touch
  { x [i32] }
  {
    ret (),
  }
```

A function body may be a plain statement list or a control-region body with
`entry` and `block` declarations:

```lua
fn. sum
  { n [i32] }
  [i32]
  {
    entry. loop { i [i32](0), acc [i32](0) } {
      when (i :ge (n)) {
        ret (acc),
      },

      jump. loop {
        i = i + 1,
        acc = acc + i,
      },
    },
  }
```

### Contracts

Functions may carry typed contract annotations via the `requires` keyword inside
the function body. `requires` consumes a `{}` table of contract constructors:

```lua
fn. read
  { buf [ptr [u8]], count [index] }
  [index]
  {
    requires {
      bounds(buf, count),
      noalias(buf),
    },
    ret (count),
  }
```

Available contract constructors:

```lua
bounds(base, len)              -- requires bounds(base, len)
window_bounds(base, base_len, start, len)
disjoint(a, b)                 -- requires disjoint(a, b)
same_len(a, b)                 -- requires same_len(a, b)
noalias(base)                  -- requires noalias(base)
readonly(base)                 -- requires readonly(base)
writeonly(base)                -- requires writeonly(base)
```

`noalias`, `readonly`, and `writeonly` act as both type wrappers
(`noalias[ptr[u8]]`) and contract constructors (`noalias(buf)`) — the
`[]` form produces a `Ty.TAccess` type, the `()` form produces a
`Tr.Contract*` node.

`requires` items are extracted from the function body during lowering — they
are not statements and do not appear in the emitted code.

## Statements

Return:

```lua
ret (value)
ret (1)
ret "done"
ret { 1, 2, 3 }
ret ()
```

Yield:

```lua
yield (value)
yield (1)
yield "done"
yield { 1, 2, 3 }
yield ()
```

Local values:

```lua
let. x [i32] { 1 }
var. i [index] { 0 }
```

Assignment:

```lua
store (dst[i], value)
set (dst[i], value)
```

Conditional:

```lua
when (cond) {
  body...
}
```

Jump:

```lua
jump. loop {
  i = i + 1,
  acc = acc + x,
}
```

Trap and assumptions:

```lua
trap ()
assume (cond)
assert_ (cond)
```

Atomic statements:

```lua
astore(i32, p, v)    -- atomic store
afence()             -- atomic fence
```

## Switch

Literal cases:

```lua
switch (x) {
  case (0) {
    ret 1,
  },

  default {
    ret 2,
  },
}
```

Variant-oriented cases use name-token cases:

```lua
switch (r) {
  case. ok { value } {
    ret (value),
  },

  default {
    ret (0),
  },
}
```

## Regions

Regions are named control fragments:

```lua
region. scan
  { p [ptr [u8]], n [index], target [i32] }
  {
    hit  { pos [index] },
    miss,
  }
  {
    entry. loop { i [index](0) } {
      when (i :ge (n)) {
        jump. miss { pos = i },
      },

      jump. loop {
        i = i + 1,
      },
    },
  }
```

Region parts:

```text
first table  -> input product
second table -> continuation protocol
third table  -> entry/block body
```

The body must contain one `entry` block and zero or more `block` declarations.

## Emit

Emit splices a region fragment into the current control flow:

```lua
emit. scan { p, n, target } {
  hit  = found,
  miss = failed,
}
```

Continuation fill maps are record tables. Fill values are block labels/name
tokens.

Example:

```lua
fn. find
  { p [ptr [u8]], n [index] }
  [i32]
  {
    entry. start {} {
      emit. scan { p, n, 65 } {
        hit  = done,
        miss = done,
      },
    },

    block. done { pos [i32] } {
      ret (pos),
    },
  }
```

## Expression Fragments

Expression fragments are reusable typed expression components:

```lua
expr_frag. inc
  { x [i32] }
  [i32]
  {
    x + 1
  }
```

They lower to `MoonOpen.ExprFrag` module items.

## Expressions

Literals:

```lua
1
1.5
true
nil
"bytes"
{ 1, 2, 3 }
```

Floating literals map to `f64` when present in `f64`-typed positions.
Lua string literals are emitted as `LitString` and default-type to `ptr(u8)`.
Because these are Lua calls, the no-parens form only applies to Lua's special
single-argument forms:

```lua
  const. greeting [ptr [u8]] "hello, moonlift"
  const. nums [array [i32] [3]] { 1, 2, 3 }
  ret "done"
  ret { 1, 2, 3 }
```

Other literals (`1`, `true`, `nil`) are written with parentheses: `ret (1)`,
`ret (true)`, `ret (nil)`.
`ret` / `yield` scalar expressions follow the same rule.

Returning function values is supported only via references or splice-built
expressions (not inline Lua function syntax). For example:

```lua
fn. foo { x [i32] } [i32] { ret (x) },
fn. mk {} [fnptr[{ i32 }] [i32]] { ret (foo) },
```

Aggregate literals (expression position):

```lua
{ x = 1, y = 2 }           -- struct literal, typed by context
{ 1, 2, 3 }                -- array literal, typed by expected array type
```

Name references:

```lua
x
acc
```

Arithmetic:

```lua
a + b
a - b
a * b
a / b
a % b
-a
```

Comparisons use methods or constructors because Lua comparison operators cannot
be overloaded into expression trees. Default style puts spaces before the
method colon and before the argument list so comparison methods read like
Moonlift operators:

```lua
i :ge (n)
i :lt (n)
eq(a, b)
ne(a, b)
```

Boolean logic uses constructors because Lua `and`, `or`, and `not` cannot be
overloaded:

```lua
And(a, b)
Or(a, b)
Not(a)
```

Index and field:

```lua
xs[i]
point.x
```

Casts:

```lua
as [i32](x)
bitcast [u64](bits)
```

Pointer and size helpers:

```lua
addr(place)
deref(ptr)
load(ptr)
null [ptr [u8]]
is_null(p)
sizeof [i32]
alignof [i32]
```

Select:

```lua
select(cond, a, b)
```

### Atomics

```lua
aload(i32, p)                    -- atomic load
acas(i32, p, expected, replacement)  -- atomic compare-and-swap
armw("add", i32, p, v)           -- atomic read-modify-write
```

RMW ops: `"add"`, `"sub"`, `"band"`, `"bor"`, `"bxor"`, `"xchg"`.

### Variant constructor

```lua
ctor("Result", "ok", { 42 })
ctor("Result", "err", { 7 })
```

Returns an `Expr` tree node. The type name and variant name are strings;
payload arguments are an ordered table of expression values.

## Fragments And Splicing

Lua has no spread syntax, so Moonlift uses `_ (value)` as the preferred splice
marker. `spread(value)` remains available as the explicit fallback, especially
in scopes where `_` is shadowed by a local variable.

Product fragment:

```lua
local xy = product {
  x [f32],
  y [f32],
}

struct. Vec2 {
  _(xy),
}
```

Statement fragment:

```lua
local done = stmts {
  ret (0),
}

fn. f {} [i32] {
  _(done),
}
```

Declaration fragment:

```lua
local decls = decls {
  struct. A { x [i32] },
  struct. B { y [i32] },
}

return module "M" {
  _(decls),
}
```

The fragment role must match the receiving context.

## Host-Time Generation

Because the DSL is Lua, generation is ordinary Lua.

```lua
local function make_vec(n, T)
  local fields = {}

  for i = 1, n do
    fields[#fields + 1] = N["x" .. i] [T]
  end

  return struct["Vec" .. n] {
    _(fields),
  }
end

return module "Vectors" {
  make_vec(2, f32),
  make_vec(3, f32),
  make_vec(4, f32),
}
```

No source generics are needed. Lua performs generation; Moonlift receives
monomorphic ASDL.

## Power: Natural Slicing Without A Parser

The DSL naturally models slicing of programs because every syntactic component
is already a Lua value.

You can build a slice of parameters:

```lua
local view_params = product {
  data [ptr [u8]],
  len [index],
  stride [index],
}
```

Use it in multiple declarations:

```lua
struct. ViewU8 {
  _(view_params),
}

fn. first
  { _(view_params) }
  [u8]
  {
    ret (data[0]),
  }
```

You can slice statement bodies:

```lua
local bounds_check = stmts {
  when (i :ge (len)) {
    trap (),
  },
}

fn. get
  { data [ptr [u8]], len [index], i [index] }
  [u8]
  {
    _(bounds_check),
    ret (data[i]),
  }
```

You can slice control protocols:

```lua
local hit_miss = conts {
  hit { pos [index] },
  miss {},
}

region. scan_a
  { p [ptr [u8]], n [index] }
  { _(hit_miss) }
  {
    entry. start {} {
      jump. miss {},
    },
  }
```

This is not textual macro expansion. The slices are typed Lua values with roles.
The normalizer rejects a product fragment in a statement body, a statement
fragment in a struct, or a malformed continuation payload.

This is the main power of the layer:

```text
program parts are ordinary values
program shapes are ordinary Lua tables
Moonlift still receives explicit ASDL
```

The result is a metaprogramming surface with no parser debt.

## Reflection And Methods

DSL module/declaration values expose:

```lua
value:syntax()          -- MoonTree module for modules
value:ast()             -- lowered MoonTree item/module
value:typecheck(opts)   -- tree typecheck result
value:lower(opts)       -- frontend lower_module result
value:compile(opts)     -- JIT compile through backend pipeline
value:emit_c_artifact(opts)
```

Fragments support `#fragment` and `tostring(fragment)`.

## Diagnostics

The DSL fails early for role-shape mistakes:

```text
parameter expects name [type]
field expects name [type]
region body expects entry/block declarations
function body cannot mix entry/block declarations with ordinary statements
expected product fragment, got stmt
```

Semantic errors are reported by existing Moonlift phases after ASDL lowering:

```text
unresolved names
wrong argument type
invalid cast
bad jump payload
unterminated control block
owned/lease violations
```

## Grammar Summary

```lua
return module "Name" {
  struct. Name {
    field [T],
  },

  union. Name {
    variant { payload [T] },
    none,
  },

  fn. name
    { param [T] }
    [Result]
    {
      requires {
        bounds(param, N.n),
      },
      ret (expr),
    },

  region. name
    { input [T] }
    {
      ok { value [T] },
      err,
    }
    {
      entry. start {} {
        jump. ok { value = input },
      },
    },
}
```

The surface remains Lua, but the grammar mirrors Moonlift’s algebra:

```text
products    -> ordered tables of typed names
protocols   -> ordered tables of named alternatives
bodies      -> ordered tables of statements/blocks
maps/fills  -> record tables
type slots  -> evaluated Lua values in []
generation  -> ordinary Lua
```

No parser is hiding behind the DSL. Lua is the parser; Moonlift owns the
semantics.

## Formatting

Moonlift has semantic formatting for format-owned DSL files.

A format-owned file is ordinary Lua whose meaningful output is the evaluated
Moonlift value it returns. The formatter evaluates the file, formats the
returned Moonlift/LLB value, and emits canonical DSL Lua. It is not a general
Lua source formatter and does not preserve comments or arbitrary Lua
metaprogramming shape.

Canonical API:

```lua
local moon = require("moonlift")
moon.use()

local M = module "Demo" {
  fn. add { a [i32], b [i32] } [i32] {
    ret (a + b),
  },
}

print(moon.format(M))
```

Format-owned file API:

```lua
local text = require("moonlift").format_file("demo.lua")
require("moonlift").write_format_file("demo.lua")
```

CLI:

```sh
luajit scripts/moonfmt.lua demo.lua
luajit scripts/moonfmt.lua --check demo.lua
luajit scripts/moonfmt.lua --write demo.lua
```

Canonical output includes the Moonlift prelude:

```lua
local moon = require("moonlift")
moon.use()

return module "Demo" {
  fn. add { a [i32], b [i32] } [i32] {
    ret (a + b),
  },
}
```

Formatting defaults keep short function and region signatures on one line and
break them by width. Predicate comparisons use method-style layout:

```lua
i :lt (n)
value :eq (target)
as [i32] (p[i]) :ne (sentinel)
```

Long predicates break at the operator:

```lua
as [i32] (buffer[index + offset])
  :ne (sentinel)
```

Factories that generate Moonlift declarations should thread origins so
diagnostics point to the abstraction call site:

```lua
local moon = require("moonlift")
moon.use()

local function checked_add(name, origin)
  origin = origin or here("checked_add")
  return fn:at(origin) [at_origin(origin, name)] {
    a [i32],
    b [i32],
  } [i32] {
    ret (a + b),
  }
end
```

## `moon.use()` sessions

`moon.use()` is Moonlift's wrapper over `llb.use()`. Moonlift supplies the DSL
exports (`fn`, `module`, `i32`, `ptr`, `ret`, etc.); LLB manages environment
installation, auto-names, origin helpers, and cleanup.

Most authoring files ignore the return value:

```lua
require("moonlift").use()

return module "Demo" {
  fn. add { a [i32], b [i32] } [i32] {
    ret (a + b),
  },
}
```

When explicit access is useful, use the returned session:

```lua
local use = require("moonlift").use { scope = "env" }
local env = use.env
local add_head = env.fn
```

Scopes:

```lua
require("moonlift").use()                       -- permanent global install
local s = require("moonlift").use { scope = "scoped" }
s:close()                                      -- remove what this session installed
local isolated = require("moonlift").use { scope = "env" }
```

Moonlift loaders and formatting use isolated `scope = "env"` sessions, so
`moon.loadstring`, `moon.loadfile`, and `moon.format_file` do not mutate `_G`.

`moon.use()` options are forwarded to LLB where possible:

```lua
require("moonlift").use {
  scope = "permanent",
  strict = false,
  override = false,
  auto_names = true,
}
```

## Fragment algebra

Moonlift uses LLB fragment algebra for reusable, checked composition of DSL
structure.

Products/lists compose with `..`:

```lua
local buffer_params = product {
  p [ptr [u8]],
  n [index],
}

local scan_params = buffer_params .. product {
  target [i32],
}
```

Protocols compose with `+`:

```lua
local success = conts {
  hit { pos [index] },
}

local failure = conts {
  miss { pos [index] },
}

local scan_exits = success + failure
```

A product can decorate every continuation alternative with `*`:

```lua
local at_pos = product {
  pos [index],
}

local parse_errors = conts {
  eof {},
  bad_digit {},
  overflow {},
} * at_pos
```

Equivalent protocol:

```lua
conts {
  eof { pos [index] },
  bad_digit { pos [index] },
  overflow { pos [index] },
}
```

A region can use the composed fragments directly:

```lua
local parse_exits = conts {
  ok { value [i32], pos [index] },
} + (conts {
  eof {},
  bad_digit {},
  overflow {},
} * product {
  pos [index],
})

region. parse_i32 { p [ptr [u8]], n [index] } parse_exits {
  entry. start {} {
    jump. eof { pos = 0 },
  },
}
```

Supported Moonlift fragment roles:

```text
product  -- product fields/params; `..` and `*`
stmts    -- statement lists; `..`
decls    -- declaration lists; `..`
exprs    -- expression lists; `..`
conts    -- continuation protocols; `+` and `*`
variants -- union variants; `+` and `*`
```

Each role constructor can be called with no argument to create the identity
fragment for that role:

```lua
local params = product()
local body = stmts()
local exits = conts()
```

This is the preferred pattern for conditional metaprogramming:

```lua
local function maybe_indexed(include_index)
  local params = product {
    p [ptr [u8]],
  }

  if include_index then
    params = params .. product {
      i [index],
    }
  end

  return params
end
```

For sum/protocol identities, use `+` to add alternatives:

```lua
local exits = conts()

if want_ok then
  exits = exits + conts {
    ok {},
  }
end

if want_error then
  exits = exits + conts {
    err { code [i32] },
  }
end
```

Bad algebra is rejected early. Examples:

```lua
product { a [i32] } + product { b [i32] } -- wrong operator
product { a [i32] } .. conts { ok {} }    -- role mismatch
conts { ok {} } + conts { ok {} }         -- duplicate alternative
```

### Preferred metaprogramming style

Fragment algebra is the preferred way to metaprogram Moonlift DSL structure.
Factories should return role-tagged fragments instead of raw Lua arrays when
producing reusable pieces of declarations, parameters, statements, expressions,
continuation protocols, or union variants.

Prefer:

```lua
local function buffer_params()
  return product {
    p [ptr [u8]],
    n [index],
  }
end

local function positioned_errors()
  return conts {
    eof {},
    bad_digit {},
    overflow {},
  } * product {
    pos [index],
  }
end

local params = buffer_params() .. product {
  radix [i32],
}

local exits = conts {
  ok { value [i32], pos [index] },
} + positioned_errors()
```

Avoid raw table plumbing for reusable DSL pieces:

```lua
local out = {}
out[#out + 1] = p [ptr [u8]]
out[#out + 1] = n [index]
return out
```

Raw Lua tables are still useful inside a factory, but the public result of a
Moonlift metaprogramming helper should normally be a fragment with an explicit
role. This preserves role information, enables early diagnostics, keeps
composition readable, and lets formatting/rendering recover canonical DSL
structure after evaluation.
