# Lalin ASDL Guide

This guide is the working doctrine for ASDL modeling in Lalin compiler code.
It is intentionally stricter than Terra's public ASDL examples. Lalin uses the
Terra-style ASDL runtime pattern, but compiler semantics must be schema-owned,
typed, and leaf-method driven.

## Core Rule

ASDL is the semantic model. Lua methods explain ASDL behavior; they do not create
a second untyped model beside it.

Lalin uses ASDL to make compiler Lua type-safe. Lua is still the implementation
language, but ASDL is the boundary that keeps compiler state, facts, decisions,
and IR from becoming arbitrary tables. Sidestepping ASDL in a compiler-scale
codebase recreates table soup: meanings move into conventions, bugs hide in
missing fields, and dispatch spreads through helpers instead of living on the
types that own it.

This matches ASDL's historical purpose. ASDL was created to describe compiler
IR and syntax trees with a rich algebraic type vocabulary while still targeting
low-level implementation languages. In practice it gives languages like C, and
for Lalin Lua, the missing product/sum discipline needed to build large compiler
systems without reducing every semantic object to an untyped record.

Good ASDL design is also excellent for AI-assisted maintenance because it
localizes attention. If behavior lives on the ASDL leaf that owns the semantic
case, an agent can inspect the schema, open the leaf method, and reason locally.
If behavior is spread through side tables, rule runners, handler maps, and
string dispatch, the agent has to reconstruct a hidden architecture from global
search results and is much more likely to make a bad patch.

When compiler code needs to classify a value, remember a fact, or route behavior,
first classify the lifetime. Add the missing ASDL value for durable data. Use peer
named exits on a named machine object for an immediate decision. Do not encode control
as data only because Lua has one return edge.

## Pure Lalin Mirror

The ASDL + Lua-method pattern has a direct compiled Lalin mirror:

```text
ASDL product          -> Lalin struct
ASDL unique product   -> Lalin unique struct
ASDL sum/leaf         -> Lalin union or encoded product + consumer region
Lua machine object     -> compiled Lalin state struct or unique struct
Lua named exit method  -> qualified region continuation when compiled control needs it
ASDL identity fact     -> unique struct identity or qualified handle
```

`docs/LUA_OBJECT_REGIONS.md` specifies bootstrap Lua named control. A multi-exit
operation receives the named computation object as `cc` and stable unbound exit methods
from that object's class. It forwards `cc` unchanged and tail-calls one peer exit.

Use the Lua ASDL pattern for bootstrap compiler semantics, staging, schema
projection, and tooling. Prefer the pure Lalin mirror for fast monomorphic
semantic systems, including future compiler phases rewritten in Lalin. The
architectural rule is the same in both forms: the semantic thing owns its
behavior.

For a running computation, make the machine an ordinary Lua object. The machine owns
its exact evolving state, services, cursors, builders, and pending work. Its named
methods are static control nodes and tail calls are graph edges. Split machines only
when there are genuinely separate computations. Do not replace a missing machine
object with an anonymous context bag, optional state record, or universal phase object.

## Products And Unions

Use products for records with named fields:

```lua
product. ScheduleEmitterCapability {
  interned,
  kind [str],
  executable [bool],
  reason [str],
  rejects [many [LalinSchedule.ScheduleReject]],
}
```

Use unions for alternatives:

```lua
sum. SchedulePlanSelection {
  ScheduleSelectionNoPlan {
    variant_unique,
    rejects [many [LalinSchedule.ScheduleReject]],
  },
  ScheduleSelectionPlanned {
    variant_unique,
    schedule [LalinSchedule.ScheduleKind],
    capability [LalinSchedule.ScheduleEmitterCapability],
    rejected_alternatives [many [LalinSchedule.ScheduleReject]],
  },
}
```

Do not encode alternatives as string tags, boolean flags, optional clusters, or
one product with many nullable fields.

## Leaf Methods Are Dispatch

For a union operation, install the method on each concrete union leaf that owns
the behavior. Calling the method is the dispatch.

Correct:

```lua
function Tree.ExprCall:typecheck(input, cc, on_typed, on_rejected)
  return self.callee:check_call(input, cc, on_typed, on_rejected)
end

function Tree.ExprInt:typecheck(input, cc, on_typed, _on_rejected)
  return on_typed(cc, Tree.TypedIntegerExpression(self, input.expected))
end
```

Wrong:

```lua
local handlers = {
  ExprCall = function(expr, input) ... end,
  ExprInt = function(expr, input) ... end,
}

function typecheck_expr(expr, input)
  return handlers[expr.kind](expr, input)
end
```

Parent union methods are only shared defaults or explicit delegation contracts.
They must not inspect child classes, `kind` strings, action names, tags, or
selector tables to choose behavior.

## Methodification

When a Lua API mainly operates on one semantic thing, make that thing an ASDL
product or union and install the API as a method on it.

Correct:

```lua
local result = request:compile()
local code = typed_module:lower_to_code(input)
local artifact = plan:materialize()
```

Wrong:

```lua
local result = compile(source, opts)
local code = lower(module, ctx, facts, flags)
local artifact = materialize(kind, payload, tables)
```

The receiver should be a deep semantic object. It owns the data, invariants,
operation vocabulary, and durable result shape or immediate direct-continuation exits. If
there is no honest receiver, the schema is probably missing a product such as
`CompilationRequest`, `TypedModule`, `CodeEmissionRequest`, or `KernelPlanRequest`.

Free helper functions are allowed only for small implementation details whose
main subject is not an ASDL semantic value. If a helper takes an ASDL value as
the thing it is really about, move it onto that ASDL type. If a public function
takes loose Lua arguments, replace the argument bundle with an ASDL request
product and call a method on that product.

Avoid half-methodification. A method that returns a string, boolean, or selector only
so another function can branch later is still external dispatch. Use peer named machine
exits when the caller consumes the choice now. Use a typed ASDL result union only when
the outcome must persist or cross a sealed boundary.

## Object Wiring Is The Good Part

ASDL objects make compiler Lua sane because the semantic entrypoint is attached
to the value that owns the meaning. If the root thing is a `CompilationUnit`
ASDL value and the result should be compiled code, the clear Lua shape is:

```lua
local artifact = unit:compile(input)
```

The call is ordinary Lua object wiring. Receivers and durable outputs are ASDL. A
running computation is an ordinary named machine object. Child ASDL values call methods
and select peer exits such as `Machine.on_ready` or `Machine.on_rejected`; those machine
methods name the next graph node directly. The compiler becomes a graph of durable typed
values plus explicit running objects, not external passes that guess node shapes.

This is why leaf ownership matters. The object method gives Lua a simple local
interface, while ASDL keeps the data and dispatch type-safe. The method chain
should read like:

```lua
module:lower_to_code(...)
func:lower_to_code(...)
stmt:lower_to_code(...)
expr:lower_to_code(...)
```

Each direct method returns a declared ASDL value. Each multi-exit value method tail-calls
one stable unbound method on the passed machine object. Machine methods tail-call their
next named machine method and do not receive another continuation parameter. Neither
form returns a loose table.

## Methods Are Ideally Pure

An ASDL semantic method should be a pure function whenever possible:

```lua
result = receiver:operation(input)
```

The receiver is an ASDL value. The input is an ASDL value. The result is an ASDL
value. The method should not mutate the receiver, mutate child nodes, write
hidden fields, update side tables, depend on ambient globals, or smuggle facts
through external caches.

If a computation needs accumulated facts, give its named machine a narrow builder for
one ordered element family. The machine passes itself to multi-exit child operations and
passes stable unbound machine methods as the peer exits. Freezing publishes the durable
ASDL product once and prohibits later builder mutation; the machine can then tail-call
its next named method. Return a typed product, projection, facet, or durable result union
only when the value survives. Side effects belong at explicit runtime or IO boundaries.

## Constructors Compose ASDL

ASDL constructors in migrated compiler semantics must consume other ASDL values
and primitive scalar fields declared by the schema.

Do not pass ad hoc Lua records into ASDL constructors to smuggle untyped state
through a typed node:

```lua
-- Wrong: capability is an untyped Lua record.
Schedule.ScheduleSelectionPlanned(kind, {
  executable = true,
  kind = "scalar",
  rejects = {},
}, {})
```

Define the payload as ASDL and pass the ASDL value:

```lua
local capability = Schedule.ScheduleEmitterCapability(
  "scalar",
  true,
  "supported by current semantic emitters",
  {}
)
return Schedule.ScheduleSelectionPlanned(kind, capability, {})
```

If a constructor argument is conceptually a record, decision, capability, fact,
context, buffer, payload, or result, define that thing as an ASDL product or
union.

## Inputs, Results, Machines, And Named Exits

Semantic method inputs and durable results must be explicit ASDL values or declared
primitive values.

Do not pass:

- generic `ctx`, `env`, `state`, or option bags
- hidden Lua fields
- loose Lua tables
- ad hoc `{ ok = ... }`, `{ kind = ... }`, or `{ tag = ... }` result records
- loose multiple returns that encode a semantic alternative

Classify each operation before declaring its result:

- one honest output returns an ASDL value directly;
- an immediate alternative tail-calls a peer named exit on the passed machine;
- a stored, queued, reusable, or host-boundary alternative uses an ASDL sum or
  precise boundary record.

A named exit can carry an exact typed reason or publication. It must not allocate an
operation-result wrapper only to restore control. Exit functions are stable unbound
methods on the named machine class, not per-call capturing closures. The machine object
is the computation in progress; it is never an opaque `ctx`, generic state bag, callback
table, or ASDL escape hatch. Its methods name successors directly, so continuation
parameters are not threaded through machine frames.

## No Any, No Table, No Map Type

Lalin ASDL must not provide `any`, `table`, `table_ty`, `map`,
userdata-like escape hatches, or equivalent catch-all field types for compiler
semantics.

If a value cannot be typed precisely, the schema is incomplete. Stop and model
the missing shape.

A keyed relation is not a `map`. Model it as a named ASDL product with fields
for the key and value, then carry `many [ThatEntry]`. The entry type is where
the relation gets a name, can grow methods, and can be reviewed as compiler
semantics instead of hiding as a side table.

## No Side Tables

Side tables are not semantic state. A Lua table keyed by ASDL nodes, symbols,
classes, tags, handles, or strings is forbidden when it carries compiler facts,
decisions, diagnostics, lowering results, type facts, layout facts, control-flow
facts, or backend facts.

Move those facts or decisions into the correct form:

- a product field when the fact is intrinsic to that phase value;
- a projection when a phase derives a new shape;
- a facet when several semantic planes align to a shared spine;
- direct continuation parameters when the caller consumes the decision now;
- a result union when the outcome must persist or cross a sealed boundary.

## No Nil Passthrough

Do not let `nil` mean success, failure, absence, unknown, unsupported, default,
unchanged, no-op, or "keep going" by convention.

Use `optional [T]` only for a real nullable field whose absence is local and
obvious. If nil represents a semantic alternative or decision, define a union
leaf such as `Missing`, `Rejected`, `Unsupported`, `Unchanged`, or a more precise
domain name.

A method may return nil only when the parent ASDL method contract explicitly
says "operation not supported by this leaf" and the caller handles exactly that
contract.

## Smells

These are architecture bugs, not shortcuts:

- manual variant dispatch with `schema.classof`, `.kind`, `.tag`, strings, or
  `if/elseif` chains
- handler maps, visitor tables, rule tables, or selector tables
- side maps keyed by nodes, symbols, classes, handles, or strings
- stringly typed modes, actions, capabilities, or result kinds
- boolean protocol flags such as `ok`, `done`, `valid`, `has_x`, or `enabled`
  standing in for a result union
- optional soup: nullable fields, mode strings, and boolean switches in one
  product to represent alternatives
- large mutable contexts, even if wrapped as one ASDL product
- ASDL constructors accepting Lua records as payloads
- hidden fields on ASDL values
- compatibility shims that convert ASDL into old `{ kind = ... }` tables
- parent methods that inspect leaf shape and choose behavior
- catch-all variants such as `Other`, `Custom`, `Opaque`, `Unknown`, `Raw`, or
  `UserData` unless they are terminal diagnostic/rejection leaves with precise
  reasons
- parallel arrays that should be one list of ASDL products
- mutating ASDL nodes after construction instead of deriving a projection,
  facet, or result

## Source And Lower Phases

Source ASDL and lower ASDL have different jobs.

Source schemas model authored language facts: user-visible entities, domain
variants, containment, references, and typed source forms.

Lower schemas model consumed decisions: resolved names, type facts, layout,
control, schedules, machine plans, backend artifacts, diagnostics, and reject
reasons.

Do not bloat source nodes with later-phase facts. Create a lower projection,
spine, facet, or result type.

## Entity, Variant, Projection, Spine, Facet

Use this vocabulary when deciding what schema shape is missing:

- Entity: a stable user/compiler-visible thing with identity.
- Variant: a real domain alternative; model it as an ASDL union.
- Projection: a derived phase shape.
- Spine: a shared alignment/header product carrying identity, topology, order,
  addressability, or ranges for later branches.
- Facet: one semantic plane aligned to a spine, such as type, layout, control,
  lowering, memory, schedule, or backend facts.


## Terra Runtime Pattern

Lalin follows the useful Terra ASDL runtime mechanics:

- a context defines a closed schema vocabulary before implementation code runs
- products are checked records with named fields
- sums create a parent class plus concrete constructor classes
- nullary constructors are real singleton ASDL values
- parent membership is for type checking and shared defaults
- methods are installed on ASDL classes using normal Lua method syntax
- `unique` products and variants express schema-level identity and interning

Lalin's compiler rewrite doctrine is stricter than Terra's examples: do not use
`.kind` dispatch in migrated compiler semantics.

## Harness Pattern

The useful lesson from the Terra compiler-pattern harnesses is not a permission
to build more Lua plumbing. The useful lesson is that each ASDL semantic
boundary can be made visible, testable, and measurable as a local unit.

A semantic boundary is a method attached to an ASDL receiver:

```lua
checked = source:check(input)
lowered = checked:lower(input)
machine = lowered:define_machine(input)
```

The receiver is ASDL. The input should be ASDL when the operation needs more
than primitive scalars. The result is ASDL. That shape is the harness contract.

For each important boundary, a harness can provide:

- an implementation artifact for `Receiver:method`
- a focused test that constructs the receiver ASDL value and calls the method
- a bench when the method is on a hot path
- a profile script when allocation or dispatch shape matters
- a backend-specific artifact only when the backend is a real typed boundary

This helps because the agent does not need to rediscover where behavior lives.
The schema names the receiver, the method name names the semantic operation,
and the harness names the expected result. Missing work becomes a failing local
stub instead of a hidden convention in a giant pass.

Correct harness shape:

```lua
local source = Fixture.new_source_spec(T)
local checked = source:check(input)

assert(Checked.Spec:is(checked))
```

Wrong harness shape:

```lua
local checked = check_source({
  kind = "Spec",
  tokens = tokens,
  parser = parser,
})

assert(checked.kind == "CheckedSpec")
```

The wrong version teaches the compiler to accept ad hoc input tables and
stringly typed result records. That defeats the point of ASDL. A harness must
make the typed path easier than the untyped path.

Whole-pipeline harnesses are still useful, but they should prove composition of
typed phases:

```text
Source ASDL
  -> :check()
  -> Checked ASDL
  -> :lower()
  -> Lowered ASDL
  -> :define_machine()
  -> Machine ASDL/artifact
```

These tests should not become a substitute for local leaf-method tests. They
answer a different question: "Do the ASDL phase products connect?" Local tests
answer: "Does this receiver method implement this semantic boundary?"

Shared fixtures are useful when they build canonical ASDL towers that several
tests need. They are dangerous when they become generic mutable context bags.
A good fixture returns named ASDL roots. A bad fixture returns a loose table of
knobs, caches, handler maps, and optional fields that every test interprets by
convention.

Scaffolding can be useful for AI-assisted work because it can generate the
expected files for each declared boundary: implementation, test, bench, and
profile. The generated implementation must fail loudly until the method is
filled in. The generated test must construct ASDL inputs and assert ASDL
outputs. It must not scaffold `{ kind = ... }` compatibility tables.

The rule is simple: harnesses may make ASDL method work easier to find, run,
and measure. They must never introduce a second untyped protocol beside ASDL.

## Repair Procedure

When tempted to write untyped Lua plumbing:

1. Stop implementation work.
2. Classify the pressure as a durable value, immediate control choice, direct value,
   running computation, variable destination, or sealed boundary.
3. For a durable fact or boundary value, name the exact ASDL product, union, leaf,
   field, projection, or facet. For an immediate choice, name peer machine exits. For
   a direct value, return it directly.
4. Install value-kind behavior on the concrete ASDL leaf types that own it.
5. If state survives calls, name the computation and make it a machine object. Make its
   named methods the static graph; store a named method only for a genuinely variable
   destination.
6. Let tests fail loudly until call sites use exact ASDL values, named machines, and
   strict tail-call edges.

The answer to unclear compiler semantics is more precise ASDL, not more Lua
dispatch.
