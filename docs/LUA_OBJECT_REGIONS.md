# Values, Machines, and Named Control

**Status:** canonical bootstrap Lua control specification.

Three parts stay distinct:

```text
ASDL     the universe of values
objects  the state of a computation in progress
methods  the nodes of a static control graph
```

Values are data and survive. The object is the machine. Named methods are the graph,
and tail calls are its edges. Nothing else is required: no result union manufactured
to drive a branch, no continuation parameter threaded through every machine method, no
scheduler, and no state-machine runtime.

Compiled Lalin regions remain a separate language feature. This document specifies the
bootstrap Lua compiler control model.

---

## 1. ASDL describes the value universe

Use ASDL sums and products for distinctions that are genuinely values: facts that are
stored, compared, serialized, traversed, queued, or read by consumers that do not know
how those facts were produced.

```text
Binding = Local(slot) | Upvalue(index) | Global(name)
Expr = Name(id, origin) | Call(function, arguments) | BinOp(operator, left, right)
```

The schema answers one question: **what forms can this value take?** It does not encode
the control graph that emits, validates, prints, lowers, or resolves the value.

The lifetime test is binding:

> If an alternative must survive the operation that produces it, it is an ASDL value.

---

## 2. Methods describe behavior

Behavior belongs on the concrete ASDL leaves that own each semantic case:

```lua
function Local:emit_load(builder)
  return builder:emit_local_load(self.slot)
end

function Upvalue:emit_load(builder)
  return builder:emit_upvalue_load(self.index)
end

function Global:emit_load(builder)
  return builder:emit_global_load(self.name)
end
```

Method dispatch answers: **what does this operation mean for this value?** One ASDL
family can carry unrelated operations without changing its value declaration. Parent
methods are legal only as field-agnostic shared defaults or explicit delegation; they
must never classify a child by class, kind, tag, action name, or field shape.

---

## 3. Exits are named peers

Some alternatives do not survive. They exist only because an operation can continue in
several ways:

```lua
function Scope:lookup(name, cc, on_local, on_upvalue, on_global, on_missing)
  local binding = self.locals[name]
  if binding then return on_local(cc, binding) end

  binding = self:find_upvalue(name)
  if binding then return on_upvalue(cc, binding) end

  binding = self.globals[name]
  if binding then return on_global(cc, binding) end

  return on_missing(cc, name)
end
```

The source signature is the protocol:

```text
lookup -> local | upvalue | global | missing
```

Every exit is a peer. `on_missing` has the same status and call shape as `on_local`.
Failure is an exit, not a second control layer. Each operation exposes only its own
domain exits:

```text
coerce  -> exact | converted | impossible
match   -> matched | failed
acquire -> acquired | unavailable | retry_later
step    -> connected | waiting | received | closed
```

Do not construct a `Result`, success wrapper, rejection junction, boolean, tag, or
semantic `nil` when the value would be inspected once only to select the next edge.

---

## 4. The context is the machine object

An exit needs an object on which to do its work. That object is not opaque state and is
not a callback environment. It is the named computation in progress.

```lua
local Compiler = {}
Compiler.__index = Compiler

function Compiler.new(builder)
  return setmetatable({
    builder = builder,
    scope = Scope.new(),
    cursor = 1,
  }, Compiler)
end
```

The machine's methods are its named destinations:

```lua
function Compiler:got_local(binding)
  self.builder:emit_local_load(binding.slot)
  return self:compile_next()
end

function Compiler:got_upvalue(binding)
  self.builder:emit_upvalue_load(binding.index)
  return self:compile_next()
end

function Compiler:got_global(binding)
  self.builder:emit_global_load(binding.name)
  return self:compile_next()
end

function Compiler:unresolved(name)
  return self:report_undefined(name)
end

function Compiler:compile_name(node)
  return self.scope:lookup(node.id, self,
    Compiler.got_local,
    Compiler.got_upvalue,
    Compiler.got_global,
    Compiler.unresolved)
end
```

`lookup` forwards `cc` unchanged. Each exit function is an unbound method allocated once
at module load; calling `on_local(cc, binding)` is ordinary method-call shape with the
receiver explicit.

The rule is:

> When surrounding computation state is required, name that computation and make it an
> object. Do not invent an anonymous context carrier.

A machine owns one exact evolving computation. It can own cursors, builders, services,
and pending work that genuinely belong to that computation. It must not become a bag of
unrelated compiler facts or a universal phase object.

---

## 5. Named methods are the static graph

Exit methods take no next-continuation parameter. Each exit already knows its successor
by name:

```lua
function Compiler:got_local(binding)
  self.builder:emit_local_load(binding.slot)
  return self:compile_next()
end
```

The call graph of named methods is the control graph. Tail calls are its edges. Names
act as labels:

```text
got_local        condition_true       resource_ready
got_upvalue      condition_false      match_failed
unresolved       retry_request        resume_parent
```

A continuation parameter is needed for a dynamic graph whose caller selects an unknown
destination. The bootstrap compiler graph is static source code. Do not thread another
continuation through machine methods that already name their successors.

Reentrancy comes from allocating another machine object. Two compilations in progress
are two machine instances, not one machine plus a global control-state family.

---

## 6. Variable destinations are stored behavior

A genuinely variable join, suspension point, or reusable parser state can store its
current destination as a named function on the machine:

```lua
function Parser:enter_headers()
  self.step = Parser.parse_header
end

function Parser:enter_body()
  self.step = Parser.parse_body
end

function Parser:advance(line)
  return self.step(self, line)
end
```

This replaces mode tags and manual dispatch. The stored value is a stable named
function, not a per-call closure or an action string.

Suspension uses the same shape:

```lua
function Task:wait(step)
  self.status = TaskWaiting
  self.step = step
end

function Task:wake(value)
  local step = self.step
  self.step = nil
  self.status = TaskRunning
  return step(self, value)
end
```

Use a stored destination only when the destination really varies. Ordinary static edges
remain direct named method calls.

---

## 7. Compiler aggregate machines

A compiler population with multi-exit children is a real machine because its cursor,
builders, and pending work survive child calls:

```lua
function ResolutionMachine:advance()
  if self.cursor > #self.declarations then
    local input = ResolutionFinalizationInput(
      self.policy,
      self.occupancies:freeze(),
      self.references:freeze())

    return self.program:resolve_namespaces(input, self,
      ResolutionMachine.resolution_published,
      ResolutionMachine.resolution_rejected)
  end

  local declaration = self.declarations[self.cursor]
  return declaration:contribute_namespace(self.policy, self,
    ResolutionMachine.namespace_contributed,
    ResolutionMachine.resolution_rejected)
end

function ResolutionMachine:namespace_contributed(entries)
  self.occupancies:append_all(entries)
  self.cursor = self.cursor + 1
  return self:advance()
end

function ResolutionMachine:resolution_published(facet)
  self.resolution = facet
  return self:begin_nominal_meaning()
end

function ResolutionMachine:resolution_rejected(reason)
  return self:finish_semantic_rejection(reason)
end
```

The ASDL entries and final facet are durable values. `ResolutionMachine` is the running
computation. Its methods are graph nodes. The passed exits are stable named methods.
There is no separate worker protocol, continuation-state argument, result junction, or
control descriptor.

A builder preserves one element family and authoritative order. Freezing transfers its
durable sequence into an ASDL value and prohibits further mutation. The machine can
continue to its next named method after a builder freezes; the machine is not the
builder and does not become dead merely because one accumulation plane closed.

When all children are direct, use an ordinary Lua loop. A machine/CPS edge is justified
only when a child has multiple immediate exits or the computation genuinely suspends.

---

## 8. State machines require no runtime

The general form is an ordinary object with named methods:

```lua
function Connection:step(on_connected, on_waiting, on_received, on_closed)
  if self.status == ConnectionConnecting then
    if not socket_ready(self) then return on_waiting(self) end
    self.status = ConnectionConnected
    return on_connected(self)
  end
  -- Other concrete state-specific methods own the remaining cases.
end
```

```text
object fields  = computation state
method body    = transition logic
named exit     = destination
tail call      = transition
```

Different operations on one object can expose different peer exit sets. No universal
success/failure protocol exists.

---

## 9. Direct functions remain direct

One-output operations remain ordinary value-producing functions:

```lua
local function clamp(value, lower, upper)
  if value < lower then return lower end
  if value > upper then return upper end
  return value
end
```

A healthy compiler mixes ASDL values, direct leaf methods, machine objects, named exits,
and sealed host boundaries. Named exits earn their place only when an operation has
several genuine immediate futures.

---

## 10. Representation remains underneath

The semantic model does not require one storage representation:

```text
semantic layer  ASDL values, machine objects, methods, named exits
storage layer   integer handles, dense arrays, FFI structs, bitsets
```

A machine or builder can expose stable semantic methods while using packed LuaJIT/FFI
storage internally. Stable named exit functions avoid per-call closure allocation and
keep call sites predictable.

---

## 11. Validation

Focused tests and source audits verify:

1. every supported concrete ASDL leaf owns or legally inherits each semantic method;
2. every multi-exit operation names its complete peer exit set in its Lua signature;
3. every exit function is a stable named machine method;
4. every exit receives the exact machine class expected at that call site;
5. every selected exit is returned in strict tail position;
6. every machine owns one coherent computation and no unrelated fact bag;
7. every static machine edge is a named method call, not a threaded continuation;
8. every stored destination is a stable named function and is cleared or replaced at
   its declared transition;
9. every aggregate builder preserves order, freezes once, and rejects later mutation;
10. no immediate result junction, callback table, handler registry, mode tag, or
    universal control-state family exists;
11. `jit.off()` long-running machine chains remain stack safe; and
12. host failures remain disjoint from semantic rejection.

Tests observe ordinary methods and machine objects. They do not reproduce the graph in
a control IR or conformance registry.

---

## 12. Rules

1. Use ASDL for distinctions that are values and survive their producing operation.
2. Use concrete ASDL leaf methods for behavior that depends on value kind.
3. Use named exits for alternatives that only choose where control goes.
4. Treat every exit as a peer; failure is an exit.
5. Give each operation its domain exit set, never a universal result protocol.
6. Never manufacture a tagged value solely to drive an immediate branch.
7. Never pass opaque state. Name the computation and make it a machine object.
8. Make the machine's named methods the static graph.
9. Transfer control with `return destination(machine, payload...)` or an ordinary tail
   method call.
10. Do not thread continuation parameters through machine methods whose successors are
    already named.
11. Store a named destination on the machine only for a genuinely variable join or
    suspension.
12. Allocate another machine for reentrancy.
13. Leave direct-style operations direct.
14. Optimize representation beneath the semantic interface, never through it.

The compact doctrine is:

```text
ASDL value       = durable semantic meaning
ASDL leaf method = behavior for one value case
machine object   = one computation in progress
named method     = one static control node
named exit       = one immediate peer outcome
tail call        = one graph edge
stored method    = a genuinely variable destination
```
