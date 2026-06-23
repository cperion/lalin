# LLB Guide

LLB (`lua/llb.lua`) is the standard Moonlift Lua DSL substrate. It is part of
the Moonlift standard library, not an external helper or experiment.

It provides callable declaration/control heads that let ordinary Lua table
expressions carry structured DSL roles before Moonlift normalizes them into
ASDL.

LLB is intentionally not a parser. Lua performs lexical and syntactic parsing;
LLB records the authoring shape that Lua values express.

## Purpose

LLB gives Moonlift and Moonlift stdlib authors a consistent surface for forms
like:

```lua
fn. add { a [i32], b [i32] } [i32] { ret (a + b) }
region. scan { p [ptr [u8]], n [index] } { done {} } { ... }
jump. done {}
```

The important property is that each stage returns an incomplete closure/table
that can continue accumulating structure. That is deliberate: it supports
headers, staged construction, and progressive object building without a separate
source parser.

## Design rules

- Lua values are the source representation.
- Callable tables are valid authoring objects.
- Incomplete staged closures are useful and intentional.
- Dotted head targets (`fn. add`, `jump. done`) are name targets, not strings hidden in callbacks.
- Square brackets carry already-evaluated Lua values, usually types.
- LLB records shape; Moonlift assigns semantic meaning during DSL normalization.

Canonical formatting may put the target dot on the head side:

```lua
fn. add { a [i32], b [i32] } [i32] {
  ret (a + b),
}
```

This is a formatting policy over Lua's indexed access syntax. Expression field
access remains tight:

```lua
value.field
ctx.owner.handle
```

## Boundary

LLB should stay small, generic, and stdlib-stable. Moonlift-specific meaning belongs in
`lua/moonlift/dsl/init.lua` and the ASDL normalization/typechecking pipeline.

LLB may provide:

- staged callable heads
- role tagging
- source-friendly object construction hooks
- enough introspection for diagnostics
- canonical formatting for evaluated DSL values

LLB should not provide:

- Moonlift type rules
- parser behavior
- hidden semantic side tables
- backend/compiler lowering
- lossless Lua source rewriting

## Splice marker

`llb._(value)` is the preferred structural splice marker. `llb.spread(value)`
is the explicit fallback with the same meaning. Languages should consume this
marker by role rather than defining parallel spread wrapper types.

```lua
local fields = product {
  x [i32],
  y [i32],
}

struct. Point {
  _(fields),
}
```

The generic marker has tag `Spread` and carries only `value` plus source origin.
Moonlift exposes the same marker as `_ (...)` and keeps `spread(...)` as the
explicit fallback.

## Formatting

LLB includes a small pretty-printer substrate for parserless DSLs.

The formatter operates on evaluated LLB/Moonlift values:

```text
Lua source
  -> Lua evaluation
  -> LLB captured values
  -> format hooks
  -> canonical text
```

It does not tokenize Lua and does not preserve comments or arbitrary Lua
metaprogramming shape. A language built on LLB registers formatting hooks for
its own heads and roles, while LLB owns the generic document algebra and
width-aware rendering.

Core API:

```lua
local llb = require("llb")

local text = llb.format(value, {
  width = 100,
  indent = 2,
})
```

The document algebra is exposed as `llb.doc`:

```lua
local d = llb.doc

local doc = d.group {
  "fn ",
  name,
  d.space(),
  params,
  d.space(),
  body,
}

print(llb.render(doc, { width = 100, indent = 2 }))
```

Grammar heads may provide format hooks:

```lua
g.head .fn {
  g.slot .name   [g.name],
  g.slot .params [g.product],
  g.slot .body   [g.body],

  format = function(node, f)
    return f:group {
      "fn ",
      f:name(node.name),
      " ",
      f:braced_list(node.params),
      " ",
      f:block(node.body),
    }
  end,
}
```

Dispatch order is:

```text
value metatable __llb_format hook
head format hook
language formatter table
generic LLB fallback
literal fallback
```

This keeps LLB generic. Moonlift-specific choices like `fn`, `region`,
comparison method layout, type syntax, and block style live in
`moonlift.dsl.format`.

## Origin threading for factories

Lua helpers are the normal way to abstract over a parserless DSL. Without an
explicit convention, diagnostics inside helper-generated declarations point at
the helper body rather than the user call site.

LLB provides origin threading primitives:

```lua
local origin = llb.here()
local value = llb.at(origin, factory_input)
local decl = head:at(origin) .name { ... }
```

`llb.here(kind)` captures the helper call site. `llb.at(origin, value)` attaches
that origin to a value consumed by a head. `head:at(origin)` starts a staged head
whose own origin is the threaded caller origin.

Factories should accept or capture an origin at their boundary and pass it into
the heads they emit:

```lua
local function make_add(name, origin)
  origin = origin or llb.here("make_add")
  return fn:at(origin) [llb.at(origin, name)] {
    a [i32],
    b [i32],
  } [i32] {
    ret (a + b),
  }
end
```

Moonlift exposes the same convention through `moon.use()` as `here`,
`at_origin`, and `with_origin`.

## Relationship to Moonlift

```text
Lua syntax
  -> Lua values
  -> LLB staged heads and role normalization
  -> Moonlift DSL normalization
  -> MoonTree / MoonOpen ASDL
  -> typecheck / lowering / backend
```

LLB is therefore the reusable standard Lua DSL substrate shipped with
Moonlift, while Moonlift remains the language and compiler built on top of it.

## Managed `use()` sessions

LLB owns the generic environment lifecycle for parserless DSL authoring.
Languages built with `llb.define` can be installed through a managed session:

```lua
local session = Language:use {
  scope = "permanent",
}

session:close()
```

Equivalent top-level API:

```lua
local session = llb.use(Language, opts)
```

`llb.use` always returns a `UseSession`:

```lua
{
  lang = Language,
  env = env,
  target = _G,
  scope = "permanent",
  active = true,
}
```

The session tracks installed globals, skipped globals, auto-created names, and
the previous target metatable. `session:close()` restores only what that session
installed. If another tool replaces the target metatable after LLB installs its
own, close does not clobber that newer metatable.

### Scopes

`scope = "permanent"` installs exports into `_G` or `opts.target`.

```lua
local session = Lang:use()
-- DSL globals are now visible.
```

`scope = "scoped"` is the same installation behavior, but communicates that the
caller owns cleanup:

```lua
local session = Lang:use { scope = "scoped" }
local ok, err = pcall(function()
  -- temporary DSL globals
end)
session:close()
if not ok then error(err, 0) end
```

Use `llb.with_use` to guarantee cleanup:

```lua
llb.with_use(Lang, { scope = "scoped" }, function(env, session)
  -- temporary DSL globals
end)
```

`scope = "env"` builds an isolated environment and does not mutate `_G`:

```lua
local session = Lang:use { scope = "env" }
local env = session.env
```

Loaders, formatters, LSP analysis, and tests should prefer `scope = "env"`.

### Options

```lua
Lang:use {
  scope = "permanent", -- "permanent" | "scoped" | "env"
  target = _G,
  base = "safe",       -- "safe" | "inherit" | table
  exports = {},
  helpers = true,
  strict = false,
  override = false,
  auto_names = true,
  auto_name = function(name, origin)
    return llb.symbol(name, { origin = origin })
  end,
}
```

`override = false` is non-destructive: existing target keys are skipped and
recorded in `session.skipped`. `override = true` records previous values and
restores them on close.

Auto-name generation chains any existing `__index` metamethod. Strict writes
chain any existing `__newindex` metamethod after checking the LLB strict policy.

## Fragment algebra

LLB fragments are role-tagged, array-like DSL pieces. They support a small
algebra when their role metadata declares the right shape.

Product/list composition uses `..`:

```lua
local xy = fields {
  x [i32],
} .. fields {
  y [i32],
}
```

Sum/protocol composition uses `+`:

```lua
local exits = conts {
  ok {},
} + conts {
  err { code [i32] },
}
```

Decorating every alternative of a sum/protocol with a product payload uses `*`:

```lua
local at_pos = product {
  pos [index],
}

local parse_errors = conts {
  eof {},
  syntax {},
} * at_pos
```

This produces alternatives equivalent to:

```lua
conts {
  eof { pos [index] },
  syntax { pos [index] },
}
```

The generic rules are:

```text
product/list role .. same role       -> appended fragment
sum/protocol role + same role        -> alternatives fragment
sum/protocol role * product role     -> decorated alternatives
product role * sum/protocol role     -> decorated alternatives
```

Mismatched roles fail loudly. Product composition rejects duplicate field names
when names are visible. Sum composition rejects duplicate alternative names when
names are visible.

Role declarations can opt into the algebra:

```lua
g.role .fields { kind = "product", algebra = "product" }
g.role .body   { kind = "array", algebra = "list" }
g.role .exits  { kind = "array", algebra = "sum", payload_role = "fields" }
```

LLB owns the operators and validation. A language owns the role names and the
meaning of the items inside those roles.

Role constructors should also serve as identity constructors when called with no
items:

```lua
local fields = product()
local body = stmts()
local exits = conts()
```

This keeps conditional factories in the fragment algebra instead of falling back
to raw Lua array plumbing.
