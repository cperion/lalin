# ASDL + Methods + CPS: A Semantically Expressive Programming Pattern

## Overview

A compact programming model emerges when three mechanisms are kept distinct:

- **ASDL** describes the universe of values.
- **Methods** describe behavior available on those values.
- **Continuations** describe the universe of immediate futures.

The central rule is:

> **Use sums and products for alternatives that are data, methods for behavioral dispatch, and continuations for alternatives that are control.**

In Lua this fits naturally because tables are objects, functions are first-class values, methods are ordinary function dispatch, closures capture context, and proper tail calls can represent control transfer directly.

The result has three independent semantic axes:

```text
ASDL           = what can exist
methods        = what a value can do
continuations  = what can happen next
```

That separation is the source of the pattern's expressive power.

---

## 1. ASDL Describes the Value Space

ASDL is best used for distinctions that are genuinely data.

```text
Payment =
    Card(string token)
  | Transfer(string account)
  | Credit(number amount)
```

These alternatives may need to survive across operations, be stored, serialized, inspected, traversed, compared, or used by many subsystems.

The schema should stay independent of behavior:

```text
Payment =
    Card(...)
  | Transfer(...)
  | Credit(...)
```

It does not need to encode how to authorize, serialize, validate, execute, display, or retry a payment.

ASDL answers:

> **What forms can this value take?**

That makes the type syntax context-free with respect to behavior.

---

## 2. Methods Describe Behavior

Once ASDL constructors become Lua objects, behavior can be attached through methods.

```lua
function Card:authorize(ctx, ...)
    ...
end

function Transfer:authorize(ctx, ...)
    ...
end

function Credit:authorize(ctx, ...)
    ...
end
```

Dynamic method dispatch answers:

> **What does this operation mean for this particular kind of value?**

The same object family can support unrelated behaviors:

```lua
payment:authorize(...)
payment:validate(...)
payment:serialize(...)
payment:execute(...)
payment:describe(...)
```

The ASDL declaration remains unchanged.

This keeps the data model from being owned by a particular visitor, pass, interpreter, or workflow.

---

## 3. Continuations Describe the Future Space

Some alternatives are not really persistent data. They exist only because an operation can continue in several ways.

```lua
function Payment:authorize(
    ctx,
    authorized,
    declined,
    pending
)
    ...
end
```

The method exposes a control protocol:

```text
authorize
    -> authorized
    -> declined
    -> pending
```

The implementation chooses one future:

```lua
return authorized(ctx, receipt)
```

or:

```lua
return declined(ctx, reason)
```

or:

```lua
return pending(ctx, ticket)
```

No continuation is inherently privileged. `authorized`, `declined`, and `pending` are peer semantic exits.

The operation answers:

> **What happened, and where does control go now?**

---

## 4. Persistent Alternatives and Ephemeral Alternatives

This distinction is fundamental.

```text
Payment =
    Card(...)
  | Transfer(...)
  | Credit(...)
```

is persistent semantic data.

But:

```text
authorized
declined
pending
```

may exist only during one call to `authorize`.

A data-oriented version might construct a temporary result:

```lua
local result = payment:authorize(ctx)

if result.kind == "authorized" then
    return continue_paid(result.receipt)

elseif result.kind == "declined" then
    return handle_decline(result.reason)

elseif result.kind == "pending" then
    return wait_for(result.ticket)
end
```

CPS can keep that distinction in control space:

```lua
return payment:authorize(
    ctx,
    continue_paid,
    handle_decline,
    wait_for
)
```

A useful rule follows:

> **If an alternative must survive, make it data. If it only chooses the next action, consider making it a continuation.**

Or more compactly:

> **Materialize what survives; continuation-pass what only determines the next action.**

---

## 5. Three Independent Kinds of Dispatch

The pattern separates three questions.

### Data dispatch

ASDL answers:

```text
What kind of value is this?
```

Example:

```text
Expr =
    Name(...)
  | Call(...)
  | BinOp(...)
```

### Behavioral dispatch

Methods answer:

```text
What does this operation mean for this value?
```

Example:

```lua
expr:lower(...)
expr:evaluate(...)
expr:render(...)
```

### Control dispatch

Continuations answer:

```text
Which semantic outcome occurred?
Where does execution go next?
```

Example:

```lua
scope:lookup(
    name,
    local_,
    upvalue,
    global_,
    missing
)
```

So the model is:

```text
ASDL sum
    alternatives in data space

method dispatch
    alternatives in behavior space

continuation dispatch
    alternatives in control space
```

The three mechanisms complement rather than duplicate one another.

---

## 6. Method Signatures Become Semantic Protocols

A strong convention is to let each operation expose the exits natural to its domain.

```lua
parser:next(
    command,
    need_more,
    malformed,
    finished
)
```

```lua
type_:coerce(
    other,
    exact,
    converted,
    impossible
)
```

```lua
pattern:match(
    subject,
    matched,
    failed
)
```

```lua
resource:acquire(
    acquired,
    unavailable,
    retry_later
)
```

```lua
connection:step(
    connected,
    waiting,
    received,
    closed
)
```

These signatures are almost algebraic descriptions of behavior.

For example:

```text
coerce -> exact | converted | impossible
```

and:

```text
lookup -> local | upvalue | global | missing
```

This is more semantically informative than forcing every operation into a universal `ok/error` shape.

---

## 7. Why Generic Result Types Are Not Always Enough

A generic result type:

```text
Result<T, E>
```

is useful, but it compresses domain meaning into:

```text
success | error
```

Many operations have richer semantics.

For name resolution:

```text
local | upvalue | global | missing
```

A custom union can preserve those distinctions:

```text
LookupResult =
    Local(Binding)
  | Upvalue(Binding)
  | Global(Binding)
  | Missing
```

But if the result is immediately pattern-matched only to choose what happens next, CPS can express the distinction directly:

```lua
return scope:lookup(
    name,
    local_,
    upvalue,
    global_,
    missing
)
```

The signature itself becomes the semantic protocol.

This is not an argument against result types.

It is a rule about representation:

> **Do not manufacture data solely to encode a control transfer that can already be expressed directly.**

---

## 8. Named Functions as Control Labels

For serious programs, named continuations are often clearer than deeply nested anonymous callbacks.

```lua
local function local_(scope, binding)
    ...
end

local function upvalue(scope, binding)
    ...
end

local function global_(scope, binding)
    ...
end

local function missing(scope, name)
    ...
end

return scope:lookup(
    name,
    local_,
    upvalue,
    global_,
    missing
)
```

Names such as:

```text
condition_true
condition_false
finish_request
retry_request
resource_ready
resource_closed
match_failed
resume_parent
```

act like labels in the program's control graph.

The ordinary Lua call graph becomes a semantic control graph.

---

## 9. Objects Become More Expressive Under CPS

A plain method-oriented object often gives:

```text
state
+
operations
```

A CPS-oriented Lua object can give:

```text
state
+
operations
+
possible exits
+
pending futures
+
dynamic transition behavior
```

For example:

```lua
local Task = {}
Task.__index = Task

function Task.new()
    return setmetatable({
        state = "idle",
        resume = nil,
    }, Task)
end
```

The object may store a continuation:

```lua
function Task:wait(resume)
    self.state = "waiting"
    self.resume = resume
end
```

and later resume it:

```lua
function Task:wake(value)
    local resume = self.resume

    self.resume = nil
    self.state = "running"

    return resume(self, value)
end
```

The table now contains both persistent state and pending future control.

No special continuation object is required. The continuation is simply a function value.

---

## 10. Behavior Can Also Be State

Lua tables can hold executable behavior directly.

```lua
function Parser:enter_headers()
    self.next = parse_header
end

function Parser:enter_body()
    self.next = parse_body
end
```

Then:

```lua
return self.next(self, input, ...)
```

Instead of an explicit mode test:

```lua
if self.mode == "headers" then
    ...
elseif self.mode == "body" then
    ...
end
```

the object can carry the current behavior:

```lua
self.next = parse_header
```

or:

```lua
self.next = parse_body
```

This is useful for state machines, parsers, protocols, workflows, incremental computation, schedulers, and compiler passes.

A table can therefore contain:

```text
persistent state
persistent behavior
pending continuation
```

all as ordinary values.

---

## 11. State Machines Fall Out Naturally

Consider:

```lua
function Connection:step(
    connected,
    waiting,
    received,
    closed
)
    ...
end
```

The object stores durable connection state.

The method interprets that state.

The continuations represent possible next destinations.

```lua
if self.state == "connecting" then
    if not socket_ready(self) then
        return waiting(self)
    end

    self.state = "connected"
    return connected(self)
end
```

The model becomes:

```text
object state    = current durable state
method          = transition logic
continuation    = destination
tail call       = transition
```

No separate state-machine runtime is required.

Named mutually tail-calling functions can themselves form the machine.

---

## 12. Operation-Local Semantic Spaces

Different methods on the same object can expose different future spaces.

```lua
resource:open(
    opened,
    unavailable
)
```

```lua
resource:read(
    data,
    blocked,
    eof
)
```

```lua
resource:close(
    closed,
    already_closed
)
```

There is no need for one giant global result union containing every possible resource outcome.

Each method exposes only the alternatives meaningful for that operation.

This gives strong semantic locality:

> **Persistent distinctions belong to the type universe. Temporary operational distinctions belong to the operation.**

---

## 13. Context Objects and Stable Named Continuations

When named continuations need shared state, an explicit context object is useful.

```lua
local function resolved_local(ctx, binding)
    return ctx.builder:load_local(
        binding,
        ctx.value_ready
    )
end
```

An operation can adopt a convention such as:

```text
operation(args..., ctx, continuation...)
```

For example:

```lua
return ctx.scope:lookup(
    name,
    ctx,
    resolved_local,
    resolved_upvalue,
    resolved_global,
    unresolved
)
```

This avoids creating closures when stable named functions are preferable, while closures remain available whenever lexical capture is the cleaner representation.

---

## 14. The Pattern Does Not Replace Data

ASDL remains central precisely because persistent distinctions should remain data.

Good uses of data include:

```text
AST nodes
IR nodes
messages
types
events
protocol values
configuration
domain entities
source locations
persistent states
serialized records
```

The rule is not:

> Avoid unions.

The rule is:

> **Use unions when alternatives are values; use continuations when alternatives are futures.**

That is a division of responsibility.

---

## 15. The Pattern Does Not Require Universal CPS

Ordinary value-producing functions should remain ordinary.

```lua
local function clamp(x, lo, hi)
    if x < lo then return lo end
    if x > hi then return hi end
    return x
end
```

There is no reason to rewrite every computation as CPS.

A healthy program can mix:

```text
direct-style value functions
ASDL values
table objects
methods
CPS operations
```

CPS is useful where explicit semantic control choices matter.

---

## 16. LuaJIT Makes the Separation Practical

Under LuaJIT, the semantic layer can remain rich while hot storage uses compact representations.

```text
semantic layer
--------------
ASDL objects
methods
named continuations
contexts
scopes
types
domain objects

hot storage layer
-----------------
integer handles
dense arrays
FFI structs
FFI buffers
bitsets
compact metadata
```

A high-level builder interface can remain:

```lua
builder:emit_add(
    left,
    right,
    produced
)
```

while the builder internally writes into dense FFI storage.

The control protocol does not care whether values are represented by:

```text
tables
integer IDs
canonical objects
cdata
pointers
```

This makes high-level semantic structure compatible with low-level representation optimization.

A useful engineering principle is:

> **Keep semantic identities stable and optimize representation beneath them.**

Named continuations also make it possible to keep frequently used control destinations stable rather than constructing fresh closures in every hot path.

---

## 17. General-Purpose Domains

The model applies far beyond compilers.

### Parsing

```lua
parser:next(
    parsed,
    need_more,
    malformed,
    finished
)
```

### Networking

```lua
socket:read(
    data,
    blocked,
    closed
)
```

### Workflows

```lua
job:advance(
    progressed,
    waiting,
    completed,
    failed
)
```

### Games

```lua
entity:update(
    world,
    alive,
    destroyed,
    transitioned
)
```

### Resource management

```lua
resource:acquire(
    acquired,
    unavailable,
    retry_later
)
```

### Authentication

```lua
user:authenticate(
    accepted,
    rejected,
    locked
)
```

### Matching

```lua
pattern:match(
    subject,
    matched,
    failed
)
```

### Type systems

```lua
type_:coerce(
    other,
    exact,
    converted,
    impossible
)
```

The same semantic split applies in every case.

---

## 18. The Semantic Triangle

The programming model can be summarized as a triangle:

```text
                 VALUES
                  ASDL
                    ▲
                   /                   /                    /                     /                      /                       ▼           ▼
        BEHAVIOR ------- CONTROL
         methods       continuations
```

Each corner answers a different question.

ASDL:

> **What exists?**

Methods:

> **What can it do?**

Continuations:

> **Where can execution go?**

A surprising amount of program structure can be expressed by composing these three ideas.

---

## 19. Practical Design Rules

1. **Use ASDL for distinctions that are genuinely values.**
2. **Use methods for behavior that depends on receiver type or state.**
3. **Use continuations for alternatives that primarily determine what happens next.**
4. **Treat continuations as peers rather than imposing a universal normal/error hierarchy.**
5. **Name continuations after domain outcomes.**
6. **Transfer control with `return continuation(...)`.**
7. **Prefer named functions for nontrivial control graphs.**
8. **Let objects hold state and, when useful, pending control.**
9. **Do not manufacture temporary tagged data solely to drive an immediate branch.**
10. **Keep ordinary direct-style functions where CPS adds no semantic value.**
11. **Keep persistent semantic structure separate from transient execution context.**
12. **Optimize representation beneath the semantic interface rather than weakening the interface itself.**

---

## 20. The Resulting Programming Model

The overall architecture is:

```text
ASDL
    defines the value universe

objects
    carry persistent state and identity

methods
    define capabilities and semantic behavior

continuations
    define possible immediate futures

tail calls
    perform control transfer

contexts/builders
    carry evolving operational state
```

This is a small conceptual basis for structuring complex programs.

Its strength is not that it minimizes syntax at all costs.

Its strength is that each mechanism carries a different kind of meaning.

---

## Final Principle

The most compact formulation is:

> **Values describe what is. Methods describe what it can do. Continuations describe what may happen next.**

Or operationally:

> **Materialize what survives; continuation-pass what only determines the next action.**

That gives a semantically articulate programming model:

```text
ASDL        for data semantics
methods     for behavioral semantics
CPS         for control semantics
```

The structure of the code can therefore preserve the structure of the domain instead of flattening data, behavior, and control into one representation.
