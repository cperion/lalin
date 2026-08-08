# Object-Centered Monomorphic Tail-CPS in LuaJIT
## A First-Class Control-Flow Programming Pattern with `self`, Named Methods, and Proper Tail Calls

### Abstract

Lua has a small combination of features that, under a strict discipline, yields a programming style surprisingly close to an explicit control-flow graph while remaining ordinary Lua:

- one object owns the persistent state of a computation,
- named methods represent control locations,
- method arguments carry values across control-flow edges,
- peer continuations represent multi-exit operations,
- and `return self:next(...)` expresses a proper tail transition.

This paper calls the pattern **object-centered monomorphic tail-CPS**.

The central observation is deliberately small:

```lua
return self:next(value)
```

In the intended discipline, that one form combines four roles:

```text
self              = state record / machine instance
next              = stable named control location
value             = value crossing the control-flow edge
return ...        = proper tail transfer
```

The pattern is **monomorphic by design**. Control methods are treated as sealed labels, not virtual extension points. A machine instance has a fixed control topology; only its state changes. When a method passes continuations to another operation, it passes stable named function values such as `Compiler.local_`, never dynamically created closures and never names that must be redispatched.

The resulting principle is:

> **Static control topology, dynamic object state.**

LuaJIT makes the pattern especially interesting because Lua 5.1 specifies proper tail calls and LuaJIT has dedicated bytecode and trace-recorder handling for tail calls. LuaJIT's recorder also specializes calls to runtime function identities when it can, making a small, stable set of named destinations a particularly plausible shape for trace compilation. This is a performance hypothesis, not a benchmark result; the benchmark program proposed near the end of this paper has not yet been run.

The paper develops the semantic model, monomorphic discipline, multiple-exit protocols, relationship to CFGs and functional programming, interaction with generic `for`, comparison with coroutines, likely LuaJIT performance characteristics, applications, limitations, and an empirical evaluation plan.

---

## 1. Motivation

Many programs are naturally organized around long-lived state and repeated control transitions:

- parsers,
- compilers,
- protocol engines,
- workflows,
- schedulers,
- search procedures,
- simulations,
- game entities,
- incremental computations,
- resource managers.

A conventional object-oriented implementation often stores state in an object but expresses control through some mixture of:

```text
nested calls
status values
booleans
tagged result objects
exceptions
central dispatch loops
```

A conventional functional implementation often models alternatives with returned values:

```text
Option<T>
Result<T, E>
Either<A, B>
```

and lets the caller inspect the returned value before deciding what to do next.

Those representations are appropriate when the alternatives are genuinely data.

But many distinctions exist only to answer:

> **Where does execution go next?**

Lua can represent that answer directly because functions are first-class values and proper tail calls are part of the language semantics.

The key form is:

```lua
return self:next_state(value)
```

The receiver already carries state. The method name identifies a control location. The arguments carry edge-local values. The direct `return` places the call in tail position.

No framework is necessary.

---

## 2. The Core Model

Consider a small machine:

```lua
local Machine = {}
Machine.__index = Machine

function Machine:new(x)
    return setmetatable({
        x = x,
    }, Machine)
end

function Machine:start()
    return self:classify()
end

function Machine:classify()
    if self.x == 0 then
        return self:zero()
    end

    return self:nonzero(self.x)
end

function Machine:zero()
    print("zero")
end

function Machine:nonzero(x)
    print("nonzero", x)
end
```

The important lines are:

```lua
return self:classify()
return self:zero()
return self:nonzero(self.x)
```

A useful CFG-like reading is:

```text
start(self):
    goto classify(self)

classify(self):
    if self.x == 0
        goto zero(self)

    goto nonzero(self, self.x)
```

The correspondence is:

```text
Lua construct                 Control-flow interpretation
----------------------------------------------------------------
object instance               machine instance
object fields                 persistent machine state
named method                  control location / block
method argument               edge value / block argument
return self:f(...)            proper tail transition
named function value          first-class fixed destination
```

This is not literal machine code or SSA IR. Method lookup and value representation remain Lua semantics. The analogy is useful because the *source-level control topology* is explicit.

---

## 3. `self` Is the State Owner

Explicit CPS is often written with a context argument:

```lua
local function step(ctx, value)
    ...
    return next_step(ctx, value)
end
```

Lua method syntax already gives us a distinguished state argument:

```lua
function Machine:step(value)
    ...
    return self:next_step(value)
end
```

Conceptually:

```lua
self:next_step(value)
```

means:

```lua
self.next_step(self, value)
```

The method call syntax therefore threads the state owner through the graph automatically.

This creates a useful distinction between **persistent state** and **edge-local values**.

Values that must remain available across several states belong on the object:

```lua
self.source
self.position
self.scope
self.builder
self.current_block
self.pending
```

Values needed only by the immediate successor can remain arguments:

```lua
return self:rhs_ready(rhs)
```

A central rule is:

> **Put durable machine state on `self`; pass edge-local values as method arguments.**

This keeps the object from becoming an indiscriminate bag of temporaries while preserving the convenience of a single state owner.

---

## 4. Monomorphism Is Part of the Discipline

The pattern deliberately does **not** use control methods as polymorphic extension points.

Suppose this edge is written:

```lua
return self:next(value)
```

The syntax performs a method lookup, but the programming discipline assumes:

- `self` belongs to one fixed machine class/metatable family for this control graph,
- `next` is not overridden by subclasses,
- `next` is not rebound per instance,
- no instance field shadows the control method,
- the function identity reached at this site is stable in normal execution.

In other words, `:` is used for ergonomic state threading, not for edge-level polymorphism.

Likewise, when a continuation is passed as a first-class value, the explicit function is the destination:

```lua
return self.scope:lookup(
    name,
    self,
    Compiler.local_,
    Compiler.upvalue,
    Compiler.global_,
    Compiler.missing
)
```

Passing:

```lua
Compiler.local_
```

intentionally pins the continuation to that implementation.

That is a feature, not a limitation.

The CPS core is intended to be:

```text
small
stable
named
monomorphic
```

If polymorphism is needed at all, it should live **outside the hot control graph**, for example when selecting or constructing a machine implementation before execution begins.

Once the machine runs, its control topology is fixed.

This sharpens the central principle:

> **Static control topology, dynamic object state.**

---

## 5. Named Methods as Labels

The pattern avoids dynamically created closures for ordinary control topology.

Consider:

```lua
function Compiler:lhs_ready(lhs)
    self.lhs = lhs
    return self:lower_rhs()
end

function Compiler:lower_rhs()
    return self.node.right:lower(
        self,
        Compiler.rhs_ready,
        Compiler.invalid
    )
end

function Compiler:rhs_ready(rhs)
    return self:emit_add(self.lhs, rhs)
end
```

The named methods act much like labels:

```text
lhs_ready(self, lhs):
    self.lhs = lhs
    goto lower_rhs(self)

lower_rhs(self):
    invoke node.right.lower
        success -> rhs_ready
        invalid -> invalid

rhs_ready(self, rhs):
    goto emit_add(self, self.lhs, rhs)
```

Named methods provide several benefits:

1. **The graph is visible in the source.**
2. **Each destination has a stable identity.**
3. **No closure is allocated just to represent ordinary control.**
4. **LuaLS can document each label with a concrete signature.**
5. **All machine instances share one static control topology.**

The discipline therefore resembles manual closure conversion:

```text
closure-heavy form:
    function + hidden environment

object-centered form:
    stable named function + explicit self + explicit arguments
```

The object is the environment.

---

## 6. Peer Continuations for Multi-Exit Operations

Some operations naturally have several possible successors.

A scope lookup might expose:

```lua
function Scope:lookup(
    name,
    owner,
    local_,
    upvalue,
    global_,
    missing
)
    local binding = self.locals[name]

    if binding then
        return local_(owner, binding)
    end

    binding = self.upvalues[name]

    if binding then
        return upvalue(owner, binding)
    end

    binding = self.globals[name]

    if binding then
        return global_(owner, binding)
    end

    return missing(owner, name)
end
```

The compiler supplies stable named destinations:

```lua
function Compiler:resolve_name(name)
    return self.scope:lookup(
        name,
        self,
        Compiler.local_,
        Compiler.upvalue,
        Compiler.global_,
        Compiler.missing
    )
end

function Compiler:local_(binding)
    return self:emit_local(binding)
end

function Compiler:upvalue(binding)
    return self:emit_upvalue(binding)
end

function Compiler:global_(binding)
    return self:emit_global(binding)
end

function Compiler:missing(name)
    return self:diagnostic("unknown name: " .. name)
end
```

The semantic protocol is:

```text
lookup
    -> local_
    -> upvalue
    -> global_
    -> missing
```

The exits are peers. There is no artificial requirement to classify one as "normal" and the others as "error" continuations.

The domain names the edges.

---

## 7. Continuation Edges Are Intentionally Monomorphic

There is an important consequence of passing:

```lua
Compiler.local_
```

rather than a method name or redispatching through `owner:local_()`.

The edge is **monomorphic by construction**.

This paper treats that as a core property.

A continuation protocol therefore means:

```text
callee chooses among a fixed set of destinations
```

not:

```text
callee chooses among virtual method names to be redispatched later
```

This keeps the graph understandable and gives each edge a concrete function signature.

It also avoids the awkward alternative of passing strings:

```lua
"local_"
"upvalue"
"missing"
```

and later performing:

```lua
owner[key](owner, value)
```

That string-dispatch design would:

- add another table lookup,
- make the destination less explicit,
- weaken static editor information,
- turn a fixed control edge back into dynamic dispatch.

The monomorphic discipline instead says:

> **A continuation value is the destination, not the name of a destination.**

---

## 8. Control Alternatives Versus Data Alternatives

The pattern does not replace tagged unions or result values.

It distinguishes **persistent semantic information** from **ephemeral control decisions**.

Suppose an operation returns:

```lua
{
    kind = "missing",
    name = name,
}
```

and the caller immediately performs:

```lua
if result.kind == "missing" then
    return self:missing(result.name)
end
```

If the result object exists only to choose the next state, the object may be accidental data.

The CPS form can express the event directly:

```lua
return missing(owner, name)
```

A useful rule is:

> **Materialize what survives; continuation-pass what only determines the next action.**

Persistent values remain data.

Transient branching can remain control.

---

## 9. Proper Tail Calls Are the Mechanical Foundation

The pattern depends on Lua's proper-tail-call semantics.

The Lua 5.1 reference manual specifies that a function call directly returned from a function is a tail call and does not require another Lua stack level for the caller to remain pending.[1]

The canonical form is:

```lua
return f(x)
```

These forms are not equivalent tail calls:

```lua
return (f(x))
return 2 * f(x)
return x, f(x)
f(x); return
```

For this style:

```lua
return self:next(...)
```

is therefore more than notation.

It selects the language form that makes the current control state hand execution to its successor without logically stacking another waiting control state.

A cyclic machine can therefore be written:

```lua
function Machine:a()
    return self:b()
end

function Machine:b()
    return self:c()
end

function Machine:c()
    return self:a()
end
```

and understood as:

```text
A -> B -> C -> A -> ...
```

rather than as unbounded recursive nesting.

---

## 10. Tail Calls Are Not Inlining

Proper tail calls and inlining are different.

A proper tail call is a language-semantic control property.

Inlining is a JIT/compiler optimization that may eliminate source-level call boundaries in generated machine code.

Therefore:

```lua
return self:next(x)
```

should first be understood as:

```text
tail-transfer to next
```

not:

```text
inline next
```

LuaJIT may later optimize a hot execution path further. LuaJIT uses trace compilation and SSA-based optimizations,[2] so some source-level boundaries may disappear from generated native code.

The distinction is:

```text
Lua semantics:
    tail call -> no growing chain of waiting Lua tail callers

LuaJIT optimization:
    may further fold/flatten/optimize the recorded hot path
```

The pattern relies on the first and merely hopes to benefit from the second.

---

## 11. Why This Resembles a CFG

Consider:

```lua
---@param value number
function Machine:classify(value)
    if value < 0 then
        return self:negative(value)
    elseif value == 0 then
        return self:zero()
    end

    return self:positive(value)
end
```

Its control shape is naturally read as:

```text
classify(self, value):
    if value < 0
        goto negative(self, value)

    if value == 0
        goto zero(self)

    goto positive(self, value)
```

Method parameters resemble block arguments: values are explicitly carried across edges.

The object resembles a state record or register file containing values that outlive one edge.

The analogy can be summarized:

```text
CFG / IR concept              Object-centered tail-CPS
----------------------------------------------------------------
machine/state record          self
basic block                   named control method
block argument                method argument
fixed successor               named method/function
branch                        choose one continuation
jump                          proper tail call
```

The pattern is therefore reasonably described as:

> **structured monomorphic CFG programming in Lua.**

The word *monomorphic* matters. The graph is intended to be stable rather than an indirect dispatch network whose destinations change continually at runtime.

---

## 12. Object-Oriented State, Functional Control

The style combines object-oriented and functional ideas.

It is object-centered because:

- each computation has a state-owning object,
- methods operate on that state,
- several machine instances may share the same method implementations.

It is functional in its treatment of control because:

- functions are first-class destinations,
- multi-exit behavior is expressed by passing functions,
- futures are values,
- composition can branch rather than being restricted to one returned result path.

Direct style usually gives a function one implicit continuation:

```text
the point after the function returns
```

CPS makes the future explicit:

```lua
operation(value, first_future, second_future, third_future)
```

The callee chooses among those futures.

This generalizes linear composition:

```text
A -> B -> C
```

into graph-shaped composition:

```text
           -> B -> D
A -> step  -> C -> E
           -> F
```

without converting every branch into an intermediate tagged value.

---

## 13. State Fields and Control Labels Share a Namespace

Lua tables expose an important hazard for this style:

> **State fields and methods are both reached through the same object key namespace.**

This is broken:

```lua
function Connection:step()
    if self.closed then
        return self:closed()
    end
end
```

If:

```lua
self.closed = true
```

then:

```lua
self:closed()
```

attempts to call the boolean field, because the instance field shadows the method lookup.

This is not a minor stylistic issue. The pattern naturally wants words such as:

```text
closed
waiting
finished
ready
blocked
```

both as states and as labels.

A naming discipline is therefore mandatory.

Prefer:

```lua
self.is_closed
self.is_waiting
self.has_finished
```

for state fields, while keeping control labels:

```lua
function Connection:closed()
function Connection:waiting()
function Connection:finished()
```

More generally:

> **State fields must never shadow control-method names.**

For machines with many labels, projects may choose an explicit convention such as:

```text
is_* / has_*       boolean state
pending_*          stored data
k_*                control labels
```

but the exact spelling is less important than maintaining separate namespaces by convention.

---

## 14. Storing a Future on the Object

Because named functions are values, the machine can store a pending future:

```lua
self.resume = Parser.parse_body
```

and later:

```lua
local resume = self.resume
self.resume = nil
return resume(self)
```

This allows the object to hold:

```text
data state      -> fields
control state   -> stored named destination
```

This is useful for:

- incremental parsing,
- suspended workflows,
- protocol machines,
- cooperative scheduling,
- staged processing.

The stored continuation remains monomorphic in the important sense: it is selected from a known set of named functions. The object stores **which fixed label is pending**, not a freshly constructed closure with a private environment.

A one-shot continuation should normally be consumed explicitly:

```lua
local resume = self.resume
self.resume = nil
return resume(self)
```

That makes lifetime and reuse visible.

---

## 15. Coroutines Are the Obvious Alternative

Suspendable computations immediately raise a question:

> Why not use a coroutine?

Coroutines are excellent when the desired abstraction is direct-style suspension:

```lua
local chunk = coroutine.yield("need input")
```

They hide the suspended continuation inside the coroutine's execution state.

Object-centered tail-CPS chooses the opposite representation.

### Coroutine model

```text
suspended stack/frames   = implicit VM-managed state
resume location          = implicit
continuation             = implicit
local variables          = retained by suspended execution
```

### Object-centered tail-CPS model

```text
machine state            = explicit fields on self
resume location          = explicit named function value
continuation             = explicit
edge values              = explicit arguments or fields
```

Neither is universally better.

Coroutines are attractive when direct-style local control is more important than exposing the machine.

Object-centered tail-CPS is attractive when the programmer wants:

- the resume location to be inspectable,
- the future to be replaceable,
- control topology to remain named,
- machine state to remain explicit,
- no suspended logical call chain to be the representation of the computation.

For LuaJIT specifically, coroutine behavior should be benchmarked rather than dismissed categorically. This paper does **not** claim that LuaJIT simply "cannot JIT across `coroutine.yield`." Coroutine yield/resume interacts with VM/JIT machinery differently from ordinary tail transitions, so it belongs as a separate benchmark case.

The important semantic difference is independent of performance:

> **A coroutine stores the continuation implicitly in execution state; tail-CPS stores the continuation explicitly as a named function.**

---

## 16. LuaLS and Concrete Control Signatures

Named control locations are friendly to concrete LuaLS annotations.

For example:

```lua
---@class Compiler
---@field scope Scope
---@field lhs ValueId?
local Compiler = {}
```

A control label:

```lua
---@param binding Binding
function Compiler:local_(binding)
    return self:emit_local(binding)
end
```

A peer-continuation protocol can document concrete function shapes:

```lua
---@alias LocalExit fun(owner: Compiler, binding: Binding)
---@alias UpvalueExit fun(owner: Compiler, binding: Binding)
---@alias GlobalExit fun(owner: Compiler, binding: Binding)
---@alias MissingExit fun(owner: Compiler, name: string)
```

This makes control labels resemble typed block signatures:

```text
local_(Compiler, Binding)
missing(Compiler, string)
```

The pattern does not require generic LuaLS types.

Abstraction can remain ordinary Lua:

```text
Lua factories      -> abstraction / specialization
Lua objects        -> machine instances
LuaLS annotations  -> concrete checking
named methods      -> fixed control labels
```

This preserves a useful property:

> **The control graph is concrete even when the program that constructs it is abstract.**

---

## 17. LuaJIT-Specific Performance Hypothesis

LuaJIT makes the monomorphic version of the pattern especially interesting.

LuaJIT is a trace compiler with SSA-based optimizations.[2] Its JIT recorder has dedicated tail-call handling in `lj_record_tailcall`, and the source explicitly notes that tail calls can form loops.[3]

The recorder also contains call specialization logic. For Lua functions it normally specializes against the runtime function identity, while recognizing cases where too many closure instances indicate non-monomorphic behavior.[3]

That implementation detail lines up with this discipline:

```text
named control labels
stable function identities
explicit object state
no closure creation for ordinary edges
small fixed successor sets
```

A cyclic machine:

```lua
function M:a()
    return self:b()
end

function M:b()
    return self:c()
end

function M:c()
    return self:a()
end
```

has the source-level topology:

```text
A -> B -> C -> A
```

which is the kind of repeated hot path a tracing JIT can observe.

However, this remains a **performance hypothesis**.

The paper does not claim:

```text
tail-CPS is automatically faster
```

or even:

```text
tail-CPS always traces well
```

The stronger and more defensible claim is:

> **Monomorphic named tail-CPS removes several avoidable sources of dynamism and gives LuaJIT a small stable control graph to observe.**

Whether this matches or beats an equivalent `while` loop must be measured.

---

## 18. Why Wide Indirect Dispatch Is a Poor Fit

A tempting VM example is:

```lua
function VM:dispatch()
    local op = self.code[self.pc]
    return self.handlers[op](self)
end
```

This is semantically elegant, but it is **not** the ideal LuaJIT case when `op` ranges over many handlers.

The call site:

```lua
self.handlers[op](self)
```

may see a wide set of function identities.

LuaJIT's recorder specializes calls based on runtime function/prototype information,[3] so a highly variable destination at one hot site pushes against the monomorphic shape the pattern is trying to preserve.

LuaJIT also has finite trace resources and side-trace limits; for LuaJIT 2.1 the documented defaults include `maxtrace = 1000`, `maxside = 100`, and bounded unrolling parameters.[4]

Therefore:

> **Wide opcode-style indirect dispatch is a boundary case, not a showcase for this pattern on LuaJIT.**

The style is better suited to graphs where each control point has a small, stable successor set:

```text
parse_header
    -> header_done
    -> need_more
    -> malformed
```

than to:

```text
dispatch
    -> hundreds of unrelated opcode handlers
```

An interpreter can still use the object-centered model, but the central wide dispatch loop should be treated as a separate performance problem.

---

## 19. Generic `for` as the Data-Loop Counterpart

Lua's generic `for` protocol has a related explicit-state structure:

```lua
for value in generator, state, control do
    ...
end
```

The generator is stable code, while state and control carry changing iteration information.

This creates a useful symmetry.

### Generic `for`

```text
stable generator
+
explicit state
+
changing control value
=
walk the data graph
```

### Tail-CPS

```text
stable named destination
+
explicit object state
+
edge arguments
=
walk the control graph
```

This suggests a broader LuaJIT-oriented discipline:

> **Stable code, explicit state.**

For bounded hot data traversal, generic `for` can be a natural structured loop.

For graph-shaped control, monomorphic tail-CPS can be the corresponding explicit-control form.

The two compose well:

```lua
for id, node in next_node, self.graph, 0 do
    node:analyse(self, Compiler.changed, Compiler.unchanged)
end
```

provided the continuation sites themselves remain small and stable.

---

## 20. Applications

### 20.1 Parsers

A parser object naturally owns:

```text
input
position
lookahead
diagnostics
partial semantic state
pending resume label
```

Named methods represent parser states:

```lua
return self:parse_name()
return self:parse_arguments()
return self:finish_call(call)
```

Multi-exit primitives can expose:

```text
matched
no_match
need_more
malformed
```

without constructing temporary result unions solely for immediate branching.

Incremental parsing can store a named resume destination on the parser.

This is one of the strongest fits for the pattern.

### 20.2 Compilers

A compiler or pass object can own:

```text
current node
scope
builder
current block
temporary semantic state
```

Control labels can represent:

```text
resolve_name
lhs_ready
rhs_ready
condition_true
condition_false
finish_call
emit_cleanup
```

The fixed named graph mirrors the structure of the pass.

### 20.3 Protocol Machines

Use fields such as:

```lua
self.is_closed
self.is_waiting
```

and labels such as:

```lua
function Connection:closed()
function Connection:waiting()
function Connection:received(packet)
```

A method can choose among a small set of fixed successor states.

### 20.4 Workflow Engines

```lua
function Job:validate()
    ...
    return self:approved()
end

function Job:approved()
    ...
    return self:execute()
end
```

Suspension can store a named resume label rather than requiring an implicit suspended stack.

### 20.5 Games and Simulations

A stateful entity can use stable labels:

```lua
return self:seeking()
return self:attacking(target)
return self:retreating()
```

with object fields holding durable simulation state.

### 20.6 Interpreters

The model can structure phases or small stable transition clusters, but a single wide opcode-dispatch call site is likely to be one of the least favorable LuaJIT shapes. Interpreters should therefore not be used as the headline performance example for the technique.

---

## 21. Recommended Discipline

### Rule 1: One explicit state owner

Center one control machine around one object:

```lua
self
```

is the persistent state record.

### Rule 2: Seal the control graph

Control methods are labels, not virtual extension points.

Do not override or replace them during execution.

### Rule 3: Named methods only for ordinary control

Prefer:

```lua
function Machine:ready(...)
function Machine:blocked(...)
function Machine:finished(...)
```

over dynamically created control closures.

### Rule 4: Use `:` for state threading, not polymorphism

```lua
return self:next(...)
```

is the ergonomic machine-transition syntax.

The destination is expected to remain monomorphic.

### Rule 5: Pass edge-local values as arguments

```lua
return self:rhs_ready(rhs)
```

### Rule 6: Store only persistent values on `self`

```lua
self.lhs = lhs
return self:lower_rhs()
```

when the value must survive beyond one edge.

### Rule 7: Peer continuations are fixed destinations

Pass:

```lua
Machine.ready
Machine.blocked
```

not strings naming methods and not virtual redispatch wrappers.

### Rule 8: Tail transitions use direct `return`

Use:

```lua
return self:next(...)
```

not:

```lua
self:next(...)
return
```

when a proper tail transition is intended.

### Rule 9: Separate state-field names from control-label names

Prefer:

```lua
self.is_closed
function Machine:closed()
```

Never allow an instance field to shadow a control method.

### Rule 10: Keep successor sets small and stable

The pattern is intended for monomorphic or narrowly branching sites, not wide megamorphic dispatch tables.

### Rule 11: Keep real data as data

Do not replace persistent semantic values with control tricks.

### Rule 12: Use direct style for ordinary value computations

Not every helper belongs in CPS.

### Rule 13: Treat stored continuations as explicit control state

Prefer named function values and clear one-shot resume fields after consumption.

### Rule 14: Measure LuaJIT behavior

Use tracing and profiling tools instead of assuming performance.

---

## 22. Limitations

### 22.1 Debugging history

Proper tail calls do not preserve the ordinary historical chain of tail callers. Lua's manual notes the corresponding loss of caller debug information for tail calls.[1]

State-machine diagnostics may therefore need explicit breadcrumbs:

```lua
self.phase
self.position
self.node
self.last_transition
```

### 22.2 Too much object state

If every temporary is moved onto `self`, dependencies become obscure.

The distinction between:

```text
persistent field
edge argument
```

must remain deliberate.

### 22.3 Namespace collisions

Fields and methods occupy the same lookup namespace from the point of view of `self:key`.

State naming and label naming must remain separate.

### 22.4 Wide dynamic destinations

Large indirect destination sets undermine both readability and the intended monomorphic execution shape.

### 22.5 Tail position is a real constraint

If work must happen after a call returns, the call is not the final transition.

That future work must either remain direct style or be made explicit as another named continuation.

### 22.6 Not every problem is a state machine

Ordinary calculations should stay ordinary:

```lua
local function align(x, n)
    return math.floor((x + n - 1) / n) * n
end
```

The style is for meaningful control topology, not universal ceremony.

---

## 23. Relationship to Assembly and IR

Calling the pattern "assembly in Lua" is intentionally provocative but partly accurate at the control level.

```text
Assembly / IR                 Monomorphic object tail-CPS
----------------------------------------------------------------
state/register record         object fields
label/basic block             named method
block parameter               method parameter
fixed successor               named method/function
branch                        choose peer continuation
jump                          proper tail call
```

Important differences remain:

- Lua has garbage collection,
- values are dynamically typed at runtime,
- method lookup follows Lua table/metatable semantics,
- functions are language-level values,
- no SSA discipline is imposed,
- no register allocation is exposed,
- the VM/JIT chooses physical representation.

A more precise description is:

> **structured monomorphic CFG programming in Lua.**

The pattern borrows low-level control clarity without abandoning Lua's high-level object and memory model.

---

## 24. Relationship to Functional Programming

CPS is fundamentally functional in the sense that futures are represented by functions.

Direct style provides one implicit continuation:

```text
the code after return
```

CPS makes futures explicit and permits several:

```lua
operation(
    value,
    matched,
    missing,
    retry
)
```

Object-centered tail-CPS adds one explicit state owner:

```text
self
```

while retaining first-class control destinations.

This creates a hybrid:

```text
functional:
    functions as futures
    graph-shaped composition
    explicit multiple exits

object-centered:
    one state owner
    shared methods
    explicit machine instances

low-level:
    stable named labels
    edge arguments
    tail transitions
```

The pattern can therefore be seen as a way for functional composition to become graph-shaped without requiring every branch to be materialized as a returned union value.

---

## 25. A Small Complete Example

```lua
---@class Counter
---@field value integer
---@field limit integer
local Counter = {}
Counter.__index = Counter

function Counter:new(limit)
    return setmetatable({
        value = 0,
        limit = limit,
    }, Counter)
end

function Counter:run()
    return self:check()
end

function Counter:check()
    if self.value >= self.limit then
        return self:finished(self.value)
    end

    return self:increment()
end

function Counter:increment()
    self.value = self.value + 1
    return self:check()
end

---@param value integer
function Counter:finished(value)
    return value
end
```

The graph is:

```text
run
 |
 v
check <-----------+
 |                |
 | not done       |
 v                |
increment --------+
 |
 | done
 v
finished
```

Persistent state:

```text
self.value
self.limit
```

Control labels:

```text
run
check
increment
finished
```

Edges:

```text
return self:check()
return self:increment()
return self:finished(value)
```

No central dispatcher, no result enum, no control closure allocation, and no requirement for a growing logical tail-call chain.

---

## 26. Performance Evaluation Plan — Not Yet Run

The performance section of this paper is currently a **proposal for measurement**, not evidence.

The following benchmark suite has **not yet been run**.

A useful comparison would include:

1. direct `while` loop with numeric state,
2. direct `while` loop with object fields,
3. ordinary method state machine,
4. object-centered monomorphic tail-CPS,
5. named peer-continuation CPS,
6. closure-heavy CPS as a contrast,
7. coroutine yield/resume state machine,
8. wide handler-table dispatch as a negative/control case.

Workloads should include:

- a predictable cycle,
- a small two-way branch,
- a four-way peer-continuation branch,
- mixed branch frequencies,
- persistent object state,
- edge-local scalar values,
- generic-`for` data traversal,
- stored named resume labels,
- coroutine suspension,
- deliberately wide indirect dispatch.

Measurements should include:

```text
wall-clock throughput
allocations / GC pressure where relevant
JIT on versus JIT off
trace count
side-trace behavior
trace aborts
generated IR for representative hot paths
```

LuaJIT provides:

```text
-jv       verbose JIT trace activity
-jdump    trace/IR/code dumps
-jp       integrated profiler
```

and exposes trace limits such as `maxtrace`, `maxside`, `hotloop`, `hotexit`, and unroll parameters.[4]

The central empirical question is:

> **Can monomorphic object-centered tail-CPS remain in the same performance class as a hand-written direct state machine while offering a more explicit semantic control graph?**

Until those measurements exist, performance claims should remain phrased as expectations and hypotheses.

---

## 27. Conclusion

The pattern begins with one small expression:

```lua
return self:next(value)
```

Under the monomorphic discipline:

```text
self              = machine instance
self fields       = persistent state
next              = sealed named control label
value             = edge-local data
return ...        = proper tail transition
```

For multi-exit operations, named function values add fixed alternative successors:

```lua
return operation(
    self,
    Machine.matched,
    Machine.missing,
    Machine.finished
)
```

The design deliberately rejects edge-level polymorphism, dynamic closure construction for ordinary control, and wide indirect dispatch as part of the core pattern.

Its central invariant is:

> **Static control topology, dynamic object state.**

That invariant gives the source code a CFG-like shape while preserving ordinary Lua values, objects, modules, garbage collection, and editor tooling.

The pattern is therefore best understood not as callback programming and not as a framework, but as:

> **an object-centered monomorphic control-flow style built from named Lua methods, first-class fixed continuations, and proper tail calls.**

Or, in its smallest form:

> **`self` owns the machine; named methods are its labels; tail calls are its edges.**

---

## References

[1] Lua 5.1 Reference Manual, §2.5.8, “Function Calls.”  
https://www.lua.org/manual/5.1/manual.html

[2] LuaJIT Project, “LuaJIT.”  
https://luajit.org/luajit.html

[3] LuaJIT source, `src/lj_record.c`, LuaJIT 2.1 branch. See call specialization and `lj_record_tailcall`; the source explicitly notes that tail calls can form loops.  
https://github.com/LuaJIT/LuaJIT/blob/v2.1/src/lj_record.c

[4] LuaJIT Project, “Running LuaJIT.” See JIT inspection tools and documented trace/compiler parameters including `maxtrace`, `maxside`, `hotloop`, `hotexit`, and unroll limits.  
https://luajit.org/running.html
