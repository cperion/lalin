# Values, Machines, and Named Control

A programming pattern for Lua. Three parts, kept distinct:

```text
ASDL     the universe of values
objects  the state of a computation in progress
methods  the nodes of a static control graph
```

Values are data and survive. The object is the machine. Named methods are the
graph, and tail calls are its edges. Nothing else is needed: no result unions
manufactured to drive a branch, no continuation parameter threaded through every
frame, no scheduler, no state-machine runtime.

The running example is name resolution in a compiler, with a protocol parser
later for the one case that needs more.

---

## 1. ASDL describes the value universe

Use sums and products for distinctions that are genuinely values — things that
get stored, compared, serialized, traversed, or read by passes that know nothing
about how they were produced.

The schema is a real artifact, parsed by Terra's `asdl.lua` into Lua classes
with checked constructors:

```lua
local asdl = require 'asdl'
local T = asdl.NewContext()

T:Define [[
   Binding = Local(number slot)
           | Upvalue(number index)
           | Global(string name)

   Expr = Name(string id, Pos pos)
        | Call(Expr fn, Expr* args)
        | BinOp(Expr lhs, BinOp op, Expr rhs)
        | Num(number v)

   BinOp = Plus | Minus
]]
```

`*` marks a list field, `?` an optional one, and `module { }` gives a namespace
when a compiler accumulates several families of `Expr` and `Type`. Field types
are Lua primitives, other ASDL types, or predicates registered with
`T:Extern(name, fn)`. `Extern` is for a precise foreign boundary value such as a
file handle or FFI cdata object. It is not an escape hatch for compiler facts, an
opaque context, or the state of a running computation.

The schema answers one question: **what forms can this value take?** It says
nothing about emitting, validating, printing, or resolving. That independence is
what lets many passes share one data model without any of them owning it.

The test is lifetime. **If an alternative must survive past the moment it is
produced, it is a value.**

Three properties of the library bear directly on the rest of this note.

**Values carry `.kind`.** It is useful for printing, serialization, and
debugging. It is not the dispatch mechanism here — sections 2 and 3 are — and
reaching for it in a pass is the signal that a method or an exit is missing.

**`unique` interns.** Marking a concrete type `unique` memoizes construction, so
equal arguments yield the identical object:

```lua
T:Define [[
   Type = Int(number bits) unique
        | Ptr(Type to)     unique
]]

assert(T.Int(32) == T.Int(32))
```

That gives canonical structural identity. It is useful for type equality, constant
canonicalization, and other relations whose identity is exactly their checked
constructor arguments. It is not durable entity identity: authored, generated, and
physical entities still need explicit identity and provenance. Interned values can be
Lua table keys for local representation work, but compiler facts and decisions must not
escape into node-keyed semantic side tables.

**Singletons are values, not classes.** Writing `Plus` without `()` produces one
shared value with no class of its own, so no method can be attached to it and
dispatch on it falls back to `.kind`. If a variant needs behavior, give it
parentheses — `Plus()` — and it becomes a class like any other. Choose per
variant: identity and cheapness, or method dispatch.

## 2. Methods describe behavior

ASDL classes are the metatables of their values with `Class.__index = Class`, so
behavior attaches as ordinary Lua methods.

```lua
function T.Local:emit_load(fn)   fn:stmt_load_local(self.slot)    end
function T.Upvalue:emit_load(fn) fn:stmt_load_upvalue(self.index) end
function T.Global:emit_load(fn)  fn:stmt_load_global(self.name)   end
```

Dispatch answers: **what does this operation mean for this kind of value?** The
same family carries `emit_load`, `render`, `describe` without the schema
changing, so the data model is never owned by a particular pass or visitor.

Methods on a sum are inherited by its variants, which gives a default:

```lua
function T.Expr:emit(fn)                    -- fallback for the whole family
    error("no emit for " .. self.kind)
end
```

**Order matters, and the failure is silent.** Inheritance is implemented by
copying, not by chained metatables, so a method defined on the parent after a
variant defines its own will overwrite the variant's. Define every parent method
before any child method. When a pass spans files, that means the parent-level
defaults belong in the file that defines the schema, or in one clearly earliest
require. Overriding a metamethod such as `__tostring` needs the parent slot
cleared first (`T.Expr.__tostring = nil`).

## 3. Exits are named, and they are peers

Some alternatives are not values. They exist only because an operation can
continue in several ways, and they are gone the moment the operation ends.

```lua
function Scope:lookup(name, cc, on_local, on_upvalue, on_global, on_missing)
    local b = self.locals[name]
    if b then return on_local(cc, b) end

    b = self:find_upvalue(name)
    if b then return on_upvalue(cc, b) end

    b = self.globals[name]
    if b then return on_global(cc, b) end

    return on_missing(cc, name)
end
```

The signature *is* the protocol, stated in the source at the definition and at
every call:

```text
lookup -> local | upvalue | global | missing
```

Each operation exposes only the exits meaningful to it. There is no global union
of every outcome a scope can have, and no reason for one:

```text
coerce  -> exact | converted | impossible
match   -> matched | failed
acquire -> acquired | unavailable | retry_later
step    -> connected | waiting | received | closed
```

**No exit is privileged.** `on_missing` is a peer of `on_local`: same control
status and same direct-call mechanism. Peer exits can carry different exact payloads;
section 8 depends on that property. Failure is an exit, not a separate control layer.

This is also why a generic `Result<T, E>` is the wrong shape here. An ASDL sum can
represent heterogeneous and nullary alternatives correctly, but it is still the wrong
lifetime when the producer's choice is consumed immediately. **Do not build data to
encode a control transfer that can be performed directly.**

## 4. The running computation is a named object

An exit needs one exact receiver on which to continue. Do not invent an anonymous table
for that purpose. If state survives calls, name the computation in progress and make
that state a narrow machine object.

```lua
local NameResolutionMachine = {}
NameResolutionMachine.__index = NameResolutionMachine

function NameResolutionMachine.new(scope, builder, subjects)
    return setmetatable({
        scope    = scope,
        builder  = builder,
        subjects = subjects,
        cursor   = 1,
    }, NameResolutionMachine)
end

function NameResolutionMachine:got_local(binding)
    self.builder:add(binding)
    self.cursor = self.cursor + 1
    return self:resolve_next()
end

function NameResolutionMachine:got_upvalue(binding)
    self.builder:add(binding)
    self.cursor = self.cursor + 1
    return self:resolve_next()
end

function NameResolutionMachine:got_global(binding)
    self.builder:add(binding)
    self.cursor = self.cursor + 1
    return self:resolve_next()
end

function NameResolutionMachine:unresolved(name)
    return self:reject_name(name)
end

function NameResolutionMachine:resolve_next()
    local node = self.subjects[self.cursor]
    if not node then return self:publish_resolution() end
    return self.scope:lookup(node.id, self,
        NameResolutionMachine.got_local,
        NameResolutionMachine.got_upvalue,
        NameResolutionMachine.got_global,
        NameResolutionMachine.unresolved)
end
```

`lookup` forwards `cc` untouched and calls `on_local(cc, b)`, which is ordinary
method-call shape with the receiver passed explicitly. Nothing is opaque: `cc` is one
`NameResolutionMachine`, the exits are stable functions allocated once at load time,
and no closure is built per call. The scope owns lookup meaning; the machine owns only
this resolution computation's cursor, builder, and graph.

The rule generalizes: **when state must survive a call, name the computation that owns
that state.** Do not reuse an arbitrary request or service as a callback environment,
and do not invent a universal compiler machine.

## 5. The graph is static

The exits above take no continuation argument, and this is the point. Each one
already knows what comes next, by name, in the source.

```lua
function NameResolutionMachine:got_local(binding)
    self.builder:add(binding)
    self.cursor = self.cursor + 1
    return self:resolve_next()
end
```

Because destinations are fixed, there is nothing to thread. A `k` parameter is
what a *dynamic* graph needs — one where the caller chooses the destination at
run time. Here the graph is written down: the call graph of named methods **is**
the control graph, and tail calls are its edges.

Names act as labels:

```text
got_local        condition_true      resource_ready
got_upvalue      condition_false     match_failed
unresolved       retry_request       resume_parent
```

Reentrancy comes from allocating a second machine, not from a hidden continuation
environment. Two resolution computations in flight use two `NameResolutionMachine`
objects.

## 6. Where paths join, the destination is state

One case genuinely needs a variable destination: a node reached from several
places that must return to different successors, or a machine that suspends and
resumes. Do not reintroduce a continuation parameter for it. Put the destination
on the object, as a named function.

```lua
function Parser:enter_headers() self.step = Parser.parse_header end
function Parser:enter_body()    self.step = Parser.parse_body   end

function Parser:advance(line)
    return self.step(self, line)
end
```

This replaces mode flags and the dispatch they require:

```lua
-- not this
if self.mode == "headers" then ... elseif self.mode == "body" then ... end
```

The same field handles suspension, where the stored destination is a resumption
point:

```lua
function Task:wait(resume)
    self.resume = resume             -- for example, Task.after_read
    return self:suspend()
end

function Task:wake(value)
    return self.resume(self, value)
end
```

The stored destination is a stable named function, not a closure, string mode, or tag.
It is justified here because suspension makes the resumption point genuinely variable.
Static destinations remain direct method calls and are not stored.

## 7. Named machines need no general runtime

When a computation survives calls, its narrow machine contains everything needed to
resume it. No scheduler or state-machine framework is implied:

```lua
function ConnectionMachine:poll()
    return self.connection:poll(self,
        ConnectionMachine.connected,
        ConnectionMachine.waiting,
        ConnectionMachine.received,
        ConnectionMachine.closed)
end

function ConnectionMachine:connected()
    return self:read_next()
end

function ConnectionMachine:waiting()
    return self:suspend_poll()
end

function ConnectionMachine:received(chunk)
    self.sink:append(chunk)
    return self:read_next()
end

function ConnectionMachine:closed()
    return self:finish()
end
```

```text
object fields  = live computation state
method body    = transition logic
named exit     = destination
tail call      = transition
```

Different service operations expose different peer exit sets because their domain
outcomes differ:

```text
resource:open (machine, on_opened, on_unavailable)
resource:read (machine, on_data, on_blocked, on_eof)
resource:close(machine, on_closed, on_already_closed)
```

No machine method above accepts or forwards another continuation. Persistent semantic
distinctions belong to the value universe. Transient control alternatives belong to the
operation that selects an exit.

## 8. The control graph is checkable

Case analysis in this pattern lands where a type checker is strong. Narrowing a
tagged union — `if r.kind == "local" then r.slot end` — depends on flow analysis
that LuaLS does unevenly. An exit needs no narrowing: the branch *is* the
function, and its payload is just a parameter type.

```lua
---@generic R
---@param name string
---@param cc NameResolutionMachine
---@param on_local   fun(cc: NameResolutionMachine, b: Local): R
---@param on_upvalue fun(cc: NameResolutionMachine, b: Upvalue): R
---@param on_global  fun(cc: NameResolutionMachine, b: Global): R
---@param on_missing fun(cc: NameResolutionMachine, name: string): R
---@return R
function Scope:lookup(name, cc, on_local, on_upvalue, on_global, on_missing) end
```

Three control-typing properties follow.

**Exhaustiveness comes from arity.** With strict LuaLS annotations, adding a fifth
outcome makes every unchanged call site incomplete. A variant added behind a `kind`
field can instead fall silently through an existing if-chain. Keep
`missing-parameter` at error level so handling the whole protocol is not optional.

**Payloads remain exact.** `on_missing` takes a `string`, not a `Binding`, and the
other exits keep their own parameter types. An ASDL sum can also carry heterogeneous or
nullary alternatives; the named-exit advantage here is that no temporary carrier value
is constructed for an immediate transfer.

**The answer type is nameable.** `R` is the answer type of the operation, and
LuaLS propagates it, so `lookup` is typed as returning whatever its exits
return. That is what makes `return on_local(cc, b)` correct by construction
rather than by convention.

Exits written as methods check as well, since
`function NameResolutionMachine:got_local(b)` carries an implicit `self`, and
`NameResolutionMachine.got_local` matches
`fun(cc: NameResolutionMachine, b: Local): R` at the call site.

Stored destinations get the same treatment, and this is where annotation earns
the most:

```lua
---@class Fn
---@field dest fun(self: Fn, expr: string): string

---@class Parser
---@field step fun(self: Parser, line: string): boolean
```

The field type *is* the join protocol, and every assignment to it is checked
against it. Initialize it in the constructor to a valid named method; do not use `nil`
as an uninitialized control state. A destination that returns the wrong type is caught
where it is installed, not where it is called.

There is one asymmetry worth naming. Exits are ordinary functions, so they
annotate and check. ASDL classes are built at run time from a string, so LuaLS
cannot see them at all: `T.Num` has no fields as far as the checker is
concerned, and neither does anything holding one. The control graph is checked;
the value universe is not.

The fix is mechanical, because the schema is already a machine-readable
description of exactly the classes LuaLS wants declared. Emit a `---@meta` stub
from it as a build step:

```lua
---@meta
---@class Num
---@field kind "Num"
---@field v number

---@class Expr: Num, Call, BinOp, Name
```

Generating the stub keeps one source of truth. Writing the classes by hand
instead means the schema and the annotations drift, which is worse than not
annotating.

What remains unchecked is graph-level: that every node is reachable, that a cycle
is intended, that a machine in one state has the fields the next transition
needs. The last of these can be pushed into the checker by giving states their
own classes:

```lua
---@class WaitingTask: Task
---@field resume fun(self: Task, value: string): nil
```

The rest is discipline.

## 9. Not everything is control

Ordinary value-producing functions stay ordinary:

```lua
local function clamp(x, lo, hi)
    if x < lo then return lo end
    if x > hi then return hi end
    return x
end
```

A healthy program mixes direct-style functions, ASDL values, objects, methods,
and named-exit operations. Named exits earn their place where an operation has
several genuinely distinct outcomes leading to different parts of the graph.
Where an operation has one outcome, it returns a value.

## 10. Representation lives underneath

The semantic layer is stable; how it is stored is not. Under LuaJIT the two can
diverge freely:

```text
semantic layer     ASDL objects, methods, named exits, machines
storage layer      integer handles, dense arrays, FFI structs, bitsets
```

A builder can present `builder:emit_add(left, right)` while writing into packed
FFI storage, and the control protocol does not care whether a binding is a table,
an integer id, a canonical object, or a pointer.

Named exits help here for a second reason: a destination that is a stable
function value, rather than a closure built per call, keeps hot paths free of
allocation and keeps call sites monomorphic.

ASDL supports both representation techniques directly. `unique` gives canonical
structural identity that is cheap to compare. It does not replace durable entity
identity or provenance. `Extern` lets a precise boundary field hold an FFI handle or
foreign object while retaining constructor checks; it must not hide semantic facts or
running machine state.

**Keep semantic identities stable and optimize representation beneath them.**

## 11. What the pattern does not provide

Stated as properties, not warnings:

- Tail calls erase frames, so the control graph is legible in the source and
  absent from a traceback. Debugging is by machine state, not by stack.
- There is no unwinding, so cleanup is an edge in the graph like any other.
- Concurrency is by allocating machines, not by nesting calls.

## Rules

1. Use ASDL for distinctions that are values — anything that must survive the
   operation producing it.
2. Use methods for behavior that depends on the receiver.
3. Use named exits for alternatives that only choose where control goes.
4. Treat every exit as a peer. Failure is an exit.
5. Give each operation the exit set its domain has, not a universal one.
6. Never manufacture a tagged value to drive an immediate branch.
7. Never pass an opaque context. If computation state must survive a call, give
   that computation one exact named machine object.
8. Keep machine edges static. Value and service operations can receive peer exit
   methods, but machine methods name their own successors and never thread another
   continuation through the graph.
9. Where a destination must vary, store it on the object as a named function.
10. Transfer control with `return destination(...)`.
11. Leave direct-style functions direct.
12. Optimize representation beneath the semantic interface, never through it.
13. Annotate exit parameters and stored destinations. The protocol is then
    checked rather than merely documented.
14. Define parent methods before child methods, and generate LuaLS stubs from
    the schema rather than writing them twice.
