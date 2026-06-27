# LLBL Guide

LLBL is the Lua Language Builder language workbench in `lua/llbl.lua`. It is the
center of the Lalin language and the bootstrap language used to define the other
language dialects.

It lets ordinary Lua syntax act as a structured language surface without adding
a parser, but that is only the first layer. LLBL also owns the machinery that
makes language dialects compose: namespaces, roles, staged heads, fragments,
origins, diagnostics, formatting, indexing, generic regions, protocols,
processes, GPS lowering, and managed environments.

```text
Lua syntax
  -> Lua values
  -> LLBL events, roles, heads, fragments, origins
  -> member-dialect values
  -> diagnostics, formatting, indexing, compilation
```

LLBL is generic. It owns the shared metaprogramming language: heads, roles,
namespaces, origins, diagnostics, formatting, indexing, dialect extension, and generic
regions. Lalin-specific types, ownership, native CFG checking, and backend
behavior belong to the Lalin dialect. The generic region algebra belongs to
LLBL; Lalin consumes it.

## Bootstrap Shape

LLBL now has an explicit two-stage bootstrap.

```text
stage 0: lua/llbl.lua kernel
  primitive Lua values, origins, diagnostics, GPS, generic regions,
  stage-0 grammar declaration records, and the dialect compiler

stage 1: lua/llbl/bootstrap.lua
  the `llbl` dialect, authored with the stage-0 grammar and installed as the
  public grammar facade

public facade
  llbl.grammar        stage-1 grammar facade
  llbl.self           the bootstrapped `llbl` dialect value
  llbl.bootstrap      bootstrap descriptor and region machines
  llbl.kernel.grammar preserved stage-0 grammar
```

This keeps `require("llbl")` as a plain Lua library while making the public LLBL
definition an ordinary LLBL dialect. The stage-0 kernel is intentionally small
and boring; the stage-1 facade is where grammar heads, role declarations,
formatting ownership, and bootstrap machines become inspectable LLBL values.

## Shared Substrate

`llbl` is the identity element of language composition. Every language is really:

```text
llbl + dialects
```

The bare `llbl` member owns shared mechanics, not dialect meaning:

```text
shared mechanics       owned by llbl
  symbol creation
  generated-name marking through N
  source origins and provenance
  diagnostics
  fragments and spread
  curried unary forms and holes
  generic regions/GPS
  formatting document model
  language composition and export ownership

dialect meaning        owned by member dialects
  what a symbol denotes
  type/value/field/constructor meaning
  semantic binding rules
  lowering and backend interpretation
```

Unknown globals create source symbols through `llbl.shared.symbols.source`.
`N.name` and `N["dynamic"]` create generated symbols. Language-level symbol
resolution is available through:

```lua
local binding = language:resolve_symbol(sym)
-- or
local binding = llbl.shared.symbols.resolve(language, sym)
```

The result is a binding record: export owner, value, language, and source/generated
provenance, or an unresolved binding. It deliberately does not decide whether a
symbol is a type, variable, constructor, predicate, or field; that is dialect
semantics layered on top of the shared LLBL resolver.

The shared substrate surface is explicit:

```text
llbl.shared.symbols       source/generated symbols, scopes, language resolution
llbl.shared.origins       origin capture, origin lookup, provenance rendering
llbl.shared.diagnostics   diagnostic values, bags, and failure transport
llbl.shared.fragments     fragments and spread
llbl.shared.regions       generic region definition, GPS, lowering, materializers
llbl.shared.formatting    doc algebra, rendering, semantic formatting
llbl.shared.languages     identity, composition, language symbol resolution
```

The language audit also records capability axes:

```text
owns / uses
resolves / formats / indexes / lowers / materializes
```

Those axes are the checklist for dialect review. A dialect should declare what
it owns and which shared LLBL service it uses, not carry a private duplicate of
LLBL substrate behavior.

## Core Atoms

LLBL code is built from a small set of atoms:

```text
shape       the Lua value shape
channel     how Lua delivered it
event       a value plus channel/origin information
role        normalization rule for a semantic position
slot        one staged head position
head        staged constructor
fragment    role-tagged reusable value
curried     unary callable table with staged operands
hole        placeholder operand for partial application
origin      source/provenance handle
diagnostic  structured failure report
namespace   owned dialect surface
zone        language partition
protocol    named behavior contract
region      generic control machine
process     event-protocol region
```

A normal user writes:

```lua
lln.fn. add { a [lln.i32], b [lln.i32] } [lln.i32] {
  lln.ret (a + b),
}
```

A dialect author defines roles and heads:

```lua
local llbl = require("llbl")
local g = llbl.grammar
local ch = llbl.channel

local Mini = llbl.dialect "Mini" {
  g.role. fields { kind = "product", unique_names = true },
  g.role. body   { kind = "array", algebra = "list" },

  g.head. fn {
    g.slot. name   [g.name]   { channel = ch.index_name },
    g.slot. params [g.fields] { channel = ch.call_table },
    g.slot. result [g.type]   { channel = ch.index_type, optional = true },
    g.slot. body   [g.body]   { channel = ch.call_table },
    emit = function(n) return Mini.ast.fn(n) end,
  },
}
```

## Channels

Channels describe Lua syntax shape:

```text
index:name       fn. add
index:type       [i32]
index:value      head [computed]
call:none        ret ()
call:value       ret (x)
call:table       { ... }
call:many        f(a, b, c), mostly for foreign/plain Lua APIs
operator:concat  ..
operator:choice  +
operator:decorate *
env:lookup       unknown global as symbol
```

Choose channels deliberately. Diagnostics are only as good as the slot/channel
model. Public LLBL and member-dialect helpers should prefer unary calls. If a
helper has several operands, expose it as a curried callable table and let each
Lua call deliver one operand.

## Roles

Roles own normalization. Heads should stay thin.

Common role kinds:

```text
name
type
expr
array/list
product
sum/protocol
record
string
number
boolean
value
identity
```

If two heads need the same shape rule, that rule belongs in a role, not in
duplicated emit callbacks.

## Heads

A head is a staged constructor. It consumes slots in order. Each slot names:

- role
- channel
- optionality
- diagnostics label

LLBL supports incomplete stages intentionally, because Lua dot/index/call syntax
arrives one step at a time.

Fast/generated heads may specialize this state machine, but reflective heads
remain the diagnostic reference.

## Fragments

Fragments are role-tagged reusable values. They preserve metaprogramming
structure after Lua evaluation.

```lua
local params = product {
  p [ptr [u8]],
  n [index],
}

local exits = conts {
  ok { value [i32] },
} + (conts {
  eof {},
  bad_digit {},
} * product {
  pos [index],
})
```

Operators:

```text
..  list/product concatenation
+  sum/protocol choice
*  decorate every protocol alternative with a product
```

`_(fragment)` is the preferred splice marker. `spread(fragment)` is the
explicit spelling.

## Curried Forms, Holes, And Loadstrings

LLBL forms exported to user DSLs should normally be unary callable tables. This
is not just style. It gives every form the same shape, keeps diagnostics local
to one consumed operand, and gives Lua code a first-class way to partially apply
object-language operations.

When a form needs more than one operand, make it curried instead of accepting
`call:many`:

```lua
set (place)(value)
bounds (xs)(n)
lt (i)(n)
select (flag)(yes)(no)
```

For boolean composition, use callable names such as `land`, `lor`, `And`, and
`Or`; raw `and` and `or` are Lua keywords and cannot be used as function-valued
forms.

The style rule is precise:

```text
form (first)(second)(third)
```

There is one visual break between the form and its operands. Following curried
calls stay tight. This makes the operator stand apart without making
two-operand forms longer than `form(a, b)`.

The `_` value is deliberately dual-use:

```lua
_(fragment)        -- splice a fragment
lt (_)(limit)      -- leave a curried operand hole
```

As a value, `_` marks a hole in a curried form. As a call, `_ (...)` is the
short spelling for `spread(...)`. The same sentinel therefore covers the two
places where Lua authoring needs an escape hatch:

```lua
fn. generated { _(params_fragment) } [i32] {
  _(body_fragment),
}

local less_than_n = lt (_)(n)
```

This is especially powerful inside `loadstring`-authored DSL chunks. The chunk
is still plain Lua, so it can build ordinary Lua functions around curried
object-language predicates:

```lua
local positive = gt (_)(0)
local small = lt (_)(10)

local function both(a, b)
  return function(x)
    return land (a(x))(b(x))
  end
end

local in_range = both(positive, small)

when (in_range(x)) {
  ret (x),
}
```

`positive` and `small` are not syntax trees waiting for a special predicate
engine. They are Lua values that still know how to consume their missing
operand. `both` is also just Lua: it receives two predicate-like values and
returns a predicate-like closure. The final `in_range(x)` call emits the actual
object-language boolean expression.

This is the useful pattern:

```text
curried object-language form
  + `_` holes
  + ordinary Lua closures
  -> reusable predicates, contracts, and partial evaluators
```

Dialect authors should lean into this for comparisons, boolean composition,
contracts, statement-like helpers, and constructors. Avoid adding a new special
composition surface until ordinary curried forms and Lua closures are not enough.

## Namespaces And Families

A namespace is a Lua table-shaped language surface with semantic ownership
metadata. It is not just a conflict-avoidance trick.

```lua
lln.fn. add ...
schema.product. Pair ...
llpvm.task. compile ...
region. pull ...
```

Language zones use callable namespaces:

```lua
return {
  lln { ... },
  llpvm { ... },
  schema { ... },
}
```

Tools project only the zones they own. This keeps mixed-language values
composable without hiding ownership.

## Region And GPS

LLBL owns generic `region.`. Region is the shared control algebra that lets the
language compose. A region is:

```text
input product + state product + named exit protocol + transition body
```

GPS is one lowering of pull-shaped regions:

```lua
gen(param, state) -> nil
gen(param, state) -> next_state, payload...
```

Do not introduce a separate semantic `stream` layer. Pull behavior is a region
protocol. Arrays, reports, diagnostic bags, backend command buffers, and text
output are materializers.

## Processes

A process is a region with an event protocol lowered to GPS.

```lua
local function body(ctx, source)
  local function gen(param, state)
    if state == 0 then
      return 1, ctx:make_event("load", { bytes = #param.source })
    end
    return nil
  end
  return gen, { source = source }, 0
end

local load = llbl.process. load { "source" } (body)

for ev in load(src) do
  print(ev.seq, ev.kind)
end
```

Use processes for source loading, indexing, diagnostics, bytecode inspection,
debug stepping, and long-running compiler work. Do not use a process just to
compute one pure value.

## Origins And Diagnostics

Origins connect evaluated values to source/provenance. Diagnostics should carry
head, slot, role, event, and origin context where possible.

Generated fast paths should be diagnostically lazy:

```text
success path:
  no rich diagnostic allocation

failure path:
  replay through reflective metadata
```

## Formatting And Indexing

LLBL formatting is semantic. It formats evaluated values through role/head/member
hooks. It is not a lossless Lua source formatter.

LLBL owns the generic surface grammar for formatted head applications:

```lua
dialect.head. literal_name
dialect.head [dynamic_name]
```

The spaced dot means "the next token is the object-language name introduced by
this head". Member dialects should provide role/slot formatters for their
semantic payloads, such as types, fields, statements, or expressions. They
should not duplicate the generic head/name spacing rule. Raw Lua token
formatting is deliberately outside LLBL; use a Lua formatter for source text.

Indexing should be process-shaped so tools can consume only the events they
need:

```text
load
index
symbol
hover
diagnostic
completion
reference
definition
```

## Codegen

LLBL can compile its own workbench machinery:

```text
role normalizers
fragment expanders
staged head machines
language projectors
process/event regions
format/index walkers
environment installers
```

Generated functions must carry enough metadata to answer:

```text
what semantic thing is this?
which grammar object generated it?
what source line produced it?
how do we replay reflectively?
```

Use LuaJIT debug names, chunk names, line maps, and metadata upvalues to keep
generated code inspectable.

## Design Checklist

Before a language is complete, answer:

- What roles exist?
- Which roles compose?
- Which heads are thin constructors over those roles?
- Which namespace owns each semantic primitive?
- Which reusable pieces are fragments?
- Which multi-operand helpers are curried forms, and where can `_` holes improve
  composition?
- Which long operations are process/region-shaped?
- Which materializers are explicit?
- How are origins preserved?
- How do diagnostics replay on failure?
- How does formatting see evaluated values?

## Anti-Patterns

Avoid:

- raw reusable arrays with no role tag
- callbacks hiding stringly typed semantics
- heads duplicating role normalization
- hidden global installation
- coroutine-only work queues
- eager event arrays where GPS can stay pull-shaped
- compatibility shims for removed surfaces
- formatting from source text instead of semantic values
