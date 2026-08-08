# Object-Centered Tail-CPS in LuaJIT
## A First-Class Control-Flow Programming Pattern with `self`, Named Methods, and Proper Tail Calls

### Abstract

Lua has a small combination of features that, when used with a particular discipline, yields a programming style that resembles an explicit control-flow graph while remaining ordinary object-oriented Lua:

- tables hold machine state,
- `:` methods provide stable named control locations,
- method arguments carry values across control-flow edges,
- first-class functions can represent dynamically selected destinations,
- and `return self:next(...)` performs a proper tail call.

This paper calls the pattern **object-centered tail-CPS**.

The pattern is not ordinary callback programming and does not require closure-heavy continuation-passing style. Instead, an object owns the persistent state of a computation, while named methods represent its control states. A method transfers control to another state by tail-calling another method. When an operation has several possible outcomes, it receives peer continuations—usually named methods or named functions—and tail-calls exactly one of them.

The resulting model is close in spirit to a first-class control-flow graph:

```text
object fields      ≈ machine state / registers
named methods      ≈ control locations / basic blocks
method arguments   ≈ values passed across CFG edges
function values    ≈ first-class destinations
return self:f(...) ≈ tail transition / jump-like transfer
```

LuaJIT makes this model especially interesting. Lua 5.1 specifies proper tail calls, and LuaJIT has dedicated bytecode and JIT-recording machinery for tail calls. LuaJIT is also a trace compiler, so stable named control paths with explicit state are a plausible shape for efficient compilation. This paper develops the semantic model, coding discipline, applications, performance implications, limitations, and relationship to conventional functional, object-oriented, and low-level control-flow programming.

---

## 1. Motivation

Many programs are naturally organized around long-lived state and repeated control transitions:

- parsers,
- compilers,
- interpreters,
- protocol engines,
- schedulers,
- workflows,
- simulations,
- game entities,
- incremental computations,
- search procedures,
- resource managers.

A conventional object-oriented implementation often stores state in an object and expresses control through nested calls, status returns, booleans, tagged result objects, exceptions, or a central dispatcher.

A conventional functional implementation often represents multiple outcomes as sum values such as:

```text
Result<T, E>
Option<T>
Either<A, B>
```

and lets the caller inspect the returned value to decide what happens next.

Both approaches are useful. But there is another possibility when the distinction exists primarily to determine the next computation:

> Represent possible futures directly as functions.

Lua is unusually well suited to doing this without constructing a framework. Functions are first-class values, method syntax automatically passes the receiver, and the language defines proper tail calls.

The crucial form is:

```lua
return self:next_state(value)
```

Lua defines:

```lua
obj:method(x)
```

as method-call syntax equivalent to calling the selected method with `obj` as the first argument. In other words, `self` is naturally threaded through the control graph.

When the call is directly returned, the call is in Lua's proper tail-call form. The current computation does not need to remain as an additional Lua call level waiting for the next state to finish.

This suggests treating method-to-method tail calls not merely as function composition, but as **state-machine transitions**.

---

## 2. The Core Model

Consider a small machine:

```lua
local Machine = {}
Machine.__index = Machine

function Machine:new(x)
    return setmetatable({
        x = x,
    }, self)
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

A useful reading is:

```text
start:
    jump classify(self)

classify:
    if self.x == 0
        jump zero(self)
    else
        jump nonzero(self, self.x)
```

This is not literal assembly, and Lua method dispatch remains dynamic. But semantically, the control structure is much closer to a graph of labeled states than to ordinary nested calls.

The object-centered interpretation is:

```text
self fields       = persistent machine state
methods           = named control locations
method arguments  = edge-local values
tail calls        = transitions
```

This is the foundation of the pattern.

---

## 3. Why `self` Matters

Explicit CPS often introduces a context parameter:

```lua
local function step(ctx, value)
    ...
    return next_step(ctx, value)
end
```

Lua method syntax removes much of that ceremony:

```lua
function Machine:step(value)
    ...
    return self:next_step(value)
end
```

The receiver already *is* the explicit state owner.

This produces a useful distinction between persistent and transient values.

If a value must remain available across several states, it belongs naturally on the object:

```lua
self.source
self.position
self.scope
self.builder
self.current_block
self.mode
```

If a value only needs to cross one edge, it can remain an argument:

```lua
return self:rhs_ready(rhs)
```

This yields a simple state-placement rule:

> Put durable machine state on `self`; pass edge-local values as method arguments.

The style becomes much more disciplined when `self` is not treated merely as an object-oriented convenience, but as the explicit machine instance through which control flows.

---

## 4. Named Methods as Control Locations

The pattern relies on **stable named methods**, not dynamically constructed closures, for ordinary control topology.

For example:

```lua
function Compiler:lhs_ready(lhs)
    self.lhs = lhs
    return self:lower_rhs()
end

function Compiler:rhs_ready(rhs)
    return self:emit_add(self.lhs, rhs)
end

function Compiler:lower_rhs()
    return self.node.right:lower(
        self,
        Compiler.rhs_ready,
        Compiler.invalid
    )
end
```

The exact calling convention may vary, but the important property is that the destinations have stable identities.

Conceptually:

```text
lhs_ready(self, lhs):
    self.lhs = lhs
    jump lower_rhs(self)

rhs_ready(self, rhs):
    jump emit_add(self, self.lhs, rhs)
```

Named methods have several advantages:

1. **The control graph is visible.** Function names behave like labels.
2. **No closure is required to represent ordinary control state.** Changing data lives on `self` or in arguments.
3. **LuaLS can describe each control location with a concrete signature.**
4. **The same method implementation is shared by every instance.** The control topology is static while the object state is dynamic.

This leads to an important principle:

> **Static control topology, dynamic object state.**

---

## 5. Peer Continuations for Multiple Exits

Not every operation has one natural next state.

Suppose a lookup may resolve a name in several ways:

```lua
scope:lookup(name, owner, local_, upvalue, global_, missing)
```

A possible implementation is:

```lua
function Scope:lookup(name, owner, local_, upvalue, global_, missing)
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

A compiler object can provide named methods as destinations:

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

Here the continuations are peers:

```text
lookup
    -> local_
    -> upvalue
    -> global_
    -> missing
```

There is no need to declare one branch the "normal continuation" and the others "exceptional continuations." The operation's domain defines its exits.

This gives the method a semantic control protocol.

---

## 6. Control Alternatives Versus Data Alternatives

The pattern does not argue against tagged unions or structured result objects.

The important distinction is whether an alternative is **persistent information** or merely **ephemeral control**.

Suppose an operation returns:

```lua
{
    kind = "missing",
    name = name
}
```

and the caller immediately performs:

```lua
if result.kind == "missing" then
    return handle_missing(result.name)
end
```

If the result exists only to determine the next action, it may be accidental data.

CPS can express the same semantic event directly:

```lua
return missing(owner, name)
```

A useful rule is:

> **Materialize what survives; continuation-pass what only determines the next action.**

Persistent values still belong in ordinary data structures. Control alternatives can remain control.

---

## 7. Proper Tail Calls Are Essential

The pattern depends heavily on Lua's proper-tail-call semantics.

The Lua 5.1 reference manual defines a call directly returned from a function as a tail call and states that the called function reuses the stack entry of the calling function. It also notes that arbitrarily many nested tail calls can therefore execute without accumulating one Lua call level per transition.

The canonical form is:

```lua
return f(x)
```

The syntax matters. Forms such as these are not tail calls:

```lua
return (f(x))
return 2 * f(x)
return x, f(x)
f(x); return
```

For object-centered tail-CPS, this makes the coding convention mechanically meaningful:

```lua
return self:next(...)
```

is not just visual punctuation. It selects the language form that represents proper tail transfer.

This is why the following machine may cycle indefinitely without its logical transitions accumulating an ever-growing Lua call chain:

```lua
function Machine:a()
    ...
    return self:b()
end

function Machine:b()
    ...
    return self:c()
end

function Machine:c()
    ...
    return self:a()
end
```

Conceptually:

```text
A -> B -> C -> A -> ...
```

rather than:

```text
A
  B
    C
      A
        B
          ...
```

---

## 8. Tail Calls Are Not Inlining

It is useful to separate two ideas.

A **proper tail call** is a language-semantic control property. The current function does not need to remain as another waiting Lua activation before the next function takes over.

**Inlining** is an optimization that may erase function-call boundaries in generated machine code.

Therefore:

```lua
return self:next(x)
```

should be understood first as a tail transition.

LuaJIT may then optimize a hot path further. Because LuaJIT uses tracing and SSA-based optimizations, some source-level calls may disappear or be flattened in generated native code.

So the relationship is:

```text
Lua semantics:
    proper tail call -> control transfer without growing the Lua call chain

LuaJIT optimization:
    may further optimize/flatten stable hot execution paths
```

The two ideas reinforce each other but are not identical.

---

## 9. Why the Pattern Resembles a CFG

A control-flow graph consists of blocks and directed edges.

Object-centered tail-CPS has a remarkably similar shape.

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

Read as a CFG:

```text
classify(self, value):
    if value < 0
        goto negative(self, value)

    if value == 0
        goto zero(self)

    goto positive(self, value)
```

This gives a correspondence:

```text
Lua construct                 CFG-like interpretation
----------------------------------------------------------------
named method                  control location / block
self                          machine instance / state record
method parameter              edge argument / block parameter
method lookup                 dynamic destination resolution
function value                first-class destination
return self:f(...)            tail transition
```

Modern SSA-like IRs often allow values to be passed to successor blocks. Method parameters play a similar conceptual role here.

For that reason, the pattern can reasonably be described as:

> **a first-class CFG programming style embedded in ordinary Lua.**

It is not an IR and does not have static SSA semantics, but its control topology is close enough to make the analogy useful.

---

## 10. Object-Oriented and Functional at the Same Time

The pattern combines object-oriented and functional ideas rather than choosing between them.

It is object-oriented because:

- state is encapsulated by an object,
- methods operate on that state,
- method lookup can be polymorphic,
- multiple machine instances can share the same behavior.

It is functional because:

- functions are first-class destinations,
- control itself is passed as values,
- multi-exit operations are expressed by supplying functions,
- composition is performed by function transfer rather than result inspection.

The style escapes a common direct-style assumption: that a function has one implicit future—the point immediately after it returns.

In explicit CPS, a method may instead expose several possible futures:

```lua
function Parser:next(parsed, need_more, malformed, finished)
    ...
end
```

The callee chooses which future receives control.

This generalizes ordinary linear composition:

```text
A -> B -> C
```

into graph-shaped composition:

```text
          -> B -> D
A -> step -> C -> E
          -> F
```

while every destination is still an ordinary Lua function.

---

## 11. Polymorphic Tail Transitions

Method syntax adds another interesting property: a tail transition can also be dynamically dispatched.

```lua
return self:process(value)
```

is both:

1. method resolution through the receiver,
2. transfer to the chosen implementation,
3. a tail call when directly returned.

This allows object families to specialize control states:

```lua
function Machine:process(value)
    ...
end

function DebugMachine:process(value)
    ...
end

function OptimizedMachine:process(value)
    ...
end
```

The control graph can therefore be polymorphic.

This is more expressive than a raw `goto`, where destinations are normally fixed labels. In Lua, a destination can be selected through method dispatch or passed as a first-class function value.

One can think of this as a disciplined form of first-class jump target.

---

## 12. Storing a Future on the Object

Because functions are values, an object may also store a future destination:

```lua
self.resume = Parser.parse_body
```

and later:

```lua
local resume = self.resume
self.resume = nil
return resume(self)
```

This is useful for:

- incremental parsers,
- schedulers,
- suspended workflows,
- protocol machines,
- stateful interpreters,
- cooperative task engines.

The state owner can therefore hold both:

```text
data state      -> fields
control state   -> stored named function
```

This is more powerful than a conventional object containing only fields plus a fixed method table.

A useful naming discipline is to distinguish persistent behavior from one-shot control:

```lua
self.on_data    -- persistent policy
self.resume     -- pending one-shot continuation
```

A one-shot continuation should normally be cleared when consumed.

---

## 13. LuaLS and Concrete Control Signatures

The pattern becomes easier to maintain when named control locations have explicit LuaLS annotations.

For example:

```lua
---@class Compiler
---@field scope Scope
---@field lhs ValueId?
local Compiler = {}
```

A control location:

```lua
---@param binding Binding
function Compiler:local_(binding)
    return self:emit_local(binding)
end
```

A multi-exit operation can document concrete function shapes:

```lua
---@alias LocalExit fun(owner: Compiler, binding: Binding)
---@alias UpvalueExit fun(owner: Compiler, binding: Binding)
---@alias GlobalExit fun(owner: Compiler, binding: Binding)
---@alias MissingExit fun(owner: Compiler, name: string)
```

Then the program has something resembling typed block signatures:

```text
local_(Compiler, Binding)
missing(Compiler, string)
```

The style does not require a generic type abstraction layer. Lua factories can still create specialized machines, while LuaLS describes the concrete interfaces actually used.

This fits the broader discipline:

```text
Lua factories      -> abstraction and specialization
Lua objects        -> machine instances
LuaLS annotations  -> concrete interface checking
named methods      -> control locations
```

---

## 14. LuaJIT-Specific Interest

LuaJIT makes the pattern especially interesting from a performance perspective.

LuaJIT describes itself as a trace compiler with SSA-based optimizations and optimized code generation. Its source also has explicit tail-call bytecodes (`CALLT`/`CALLMT`) and a dedicated `lj_record_tailcall` path in the trace recorder.

The recorder's tail-call handling moves the function and arguments into the current frame representation rather than recording an ordinary new call-frame transition. The LuaJIT source also explicitly notes that tail calls can form loops and therefore count toward loop-unrolling limits.

This is directly relevant to machines such as:

```lua
function M:a()
    ...
    return self:b()
end

function M:b()
    ...
    return self:c()
end

function M:c()
    ...
    return self:a()
end
```

The source-level shape is cyclic, and trace compilation is fundamentally designed around hot cyclic execution.

That does **not** guarantee that every CPS program will be fast. Trace quality depends on runtime behavior, predictability, supported operations, side exits, call polymorphism, and trace limits.

But the disciplined form has attractive properties:

- stable named methods,
- stable function identities,
- no per-transition closure construction,
- explicit state,
- repeated control paths,
- small sets of destinations at many sites,
- proper tail transitions.

These are reasonable ingredients for trace-friendly code.

The performance claim should therefore be stated carefully:

> **Object-centered named tail-CPS is a plausible LuaJIT-friendly control shape, not an automatic performance guarantee.**

It should be benchmarked against direct-style alternatives.

---

## 15. Generic `for` as the Data-Loop Counterpart

Lua's generic `for` protocol has a related explicit-state structure:

```lua
for value in generator, state, control do
    ...
end
```

The generator is stable code, while state and control values carry changing iteration information.

This creates a useful symmetry:

```text
generic for:
    stable generator + explicit state + changing control
    -> walks a data graph

tail-CPS:
    stable destination + explicit object state + edge arguments
    -> walks a control graph
```

A broader LuaJIT-oriented discipline emerges:

> **Stable code, explicit state.**

For hot bounded data traversal, generic `for` may be the natural driver.

For graph-shaped control transitions, named tail-CPS may be the natural driver.

The two styles can coexist within the same object-centered system.

---

## 16. Applications

### 16.1 Parsers

```lua
function Parser:next(parsed, need_more, malformed, finished)
    ...
end
```

The parser object owns lexical and positional state. Named methods represent grammar/control states. `need_more` can suspend or request more input without manufacturing an intermediate status object.

### 16.2 Compilers

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
```

The compiler object owns pass state; methods represent compiler phases and decision points.

### 16.3 Protocol Machines

```lua
function Connection:step()
    if self.closed then
        return self:closed()
    end

    if self.waiting then
        return self:wait()
    end

    return self:receive()
end
```

### 16.4 Workflow Engines

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

### 16.5 Interpreters and VMs

```lua
function VM:dispatch()
    local op = self.code[self.pc]
    return self.handlers[op](self)
end
```

The VM object is already naturally a state owner. The CPS interpretation makes each handler an explicit successor in the control graph.

### 16.6 Games and Simulations

An entity can carry world-facing state while named methods represent behavioral states:

```lua
return self:seeking()
return self:attacking(target)
return self:retreating()
```

---

## 17. A Recommended Discipline

The style remains clear only if it is disciplined.

### Rule 1: One state owner

Center a control machine around an object.

```lua
self
```

is the persistent state carrier.

### Rule 2: Named methods for stable control topology

Prefer:

```lua
function Machine:ready(...)
function Machine:blocked(...)
function Machine:finished(...)
```

over constructing closures for ordinary transitions.

### Rule 3: Arguments for edge-local values

Pass short-lived values directly:

```lua
return self:rhs_ready(rhs)
```

Do not automatically store everything on `self`.

### Rule 4: Fields for persistent values

If a value must survive across unrelated transitions, store it:

```lua
self.lhs = lhs
return self:lower_rhs()
```

### Rule 5: Direct return for transitions

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

### Rule 6: Peer continuations

For multi-exit operations, use domain names:

```lua
matched
need_more
malformed
finished
```

rather than imposing a universal `ok/error` hierarchy.

### Rule 7: Stable function identities

When passing methods as continuations, pass the named function explicitly:

```lua
Machine.ready
Machine.blocked
```

and pass the receiver as the owner/state value.

### Rule 8: Keep real data as data

Do not replace persistent semantic values with control tricks.

### Rule 9: Measure hot paths

Use LuaJIT's tracing/profiling tools to verify performance rather than assuming it.

---

## 18. Limitations

### 18.1 Debugging history

Proper tail calls remove the ordinary stack history of prior tail callers. The Lua 5.1 manual explicitly notes that tail calls erase debug information about the calling function.

For state-machine-style code, semantic diagnostics may therefore need to live on the object:

```lua
self.phase
self.node
self.position
self.last_transition
```

rather than relying on a deep historical Lua stack.

### 18.2 Excessive hidden state

Turning every temporary into a field can make dependencies implicit.

The distinction between:

```text
persistent field
edge argument
```

must remain intentional.

### 18.3 Huge polymorphic destination sets

A single dynamic site that jumps among many unrelated functions may be less friendly to tracing and harder for humans to understand.

### 18.4 Not every call should be CPS

Ordinary helper functions should remain direct-style when they naturally compute values:

```lua
local function align(x, n)
    return math.floor((x + n - 1) / n) * n
end
```

CPS is most useful for meaningful control transitions.

### 18.5 Tail position must be preserved

Any work required *after* a call means the current function cannot simply tail-transfer to it. The algorithm may need to make the future work explicit as another named continuation.

---

## 19. Relationship to Assembly

Calling the pattern "assembly in Lua" is provocative but partly illuminating.

The similarities are real:

```text
assembly / IR                 object-centered tail-CPS
----------------------------------------------------------------
machine state                 object fields
label/basic block             named method
branch target                 continuation/function value
block arguments               method parameters
jump                          proper tail transfer
indirect jump                 dynamic function/method dispatch
```

But important differences remain:

- Lua has garbage collection,
- values are dynamically typed at runtime,
- method lookup may involve tables and metatables,
- functions are full language-level values,
- exceptions and ordinary calls still exist,
- no static SSA or register-allocation discipline is imposed,
- the VM/JIT decides the physical machine representation.

A more precise description is:

> **structured first-class CFG programming in Lua.**

The style borrows the clarity of explicit low-level control flow without abandoning the high-level Lua object model.

---

## 20. Relationship to Functional Programming

CPS is fundamentally compatible with functional programming because the destinations are themselves functions.

Direct style usually gives a function one implicit continuation: the code that executes after it returns.

CPS makes the future explicit and permits several alternatives.

Instead of:

```text
f : A -> B | C | D
```

followed by matching a result, CPS conceptually exposes:

```text
f:
    A
    -> continuation(B)
    -> continuation(C)
    -> continuation(D)
```

Object-centered tail-CPS adds a mutable or stateful receiver without changing that essential idea.

The style is therefore a hybrid:

```text
functional:
    functions as first-class futures
    graph-shaped composition
    explicit control

object-oriented:
    encapsulated state
    method dispatch
    multiple machine instances

low-level:
    named control locations
    explicit transitions
    CFG-like topology
```

The combination is precisely what makes the pattern distinctive.

---

## 21. A Small Complete Example

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
    }, self)
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

The logical machine is:

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

`self` contains the persistent state:

```text
value
limit
```

The methods are the control states:

```text
run
check
increment
finished
```

The tail calls are the graph edges.

There is no explicit dispatcher loop, result enum, callback closure, or growing logical call chain.

That small example captures the entire pattern.

---

## 22. Performance Evaluation Strategy

The style should be evaluated empirically.

A useful benchmark suite would compare:

1. a direct `while`-loop state machine,
2. a tagged-result state machine,
3. a central-dispatch method machine,
4. object-centered named tail-CPS,
5. closure-heavy CPS as a contrast.

Representative workloads should include:

- predictable cyclic transitions,
- conditional branching,
- object polymorphism,
- small and large state records,
- generic-for data traversal combined with CPS decisions,
- hot loops with integer/FFI-backed state.

LuaJIT's tools can then inspect:

```text
-jv       trace creation
-jdump    recorded IR and generated stages
-jp       runtime profiling
```

The important question is not whether tail-CPS wins every microbenchmark.

The more useful question is:

> **Can a semantically expressive control model remain within the same performance class as conventional hand-written state machines on LuaJIT?**

If yes, the pattern offers an attractive trade: explicit high-level semantics without necessarily paying for a heavy abstraction layer.

---

## 23. Conclusion

Object-centered tail-CPS arises from a small observation:

```lua
return self:next(value)
```

already combines several powerful ideas.

`self` is an explicit state owner.

`:next` is a named, potentially polymorphic control location.

`value` carries information across the control edge.

`return ...` puts the method call in proper tail position.

From that one form, a general programming model emerges:

```text
object          = machine instance
fields          = persistent state
methods         = named control locations
arguments       = edge-local values
continuations   = possible destinations
tail calls      = control transitions
method dispatch = polymorphic transition
```

The style can be used for parsers, compilers, interpreters, workflows, protocol engines, schedulers, simulations, and other control-heavy systems.

Its semantic appeal is that the code exposes the control graph directly. Its practical appeal in LuaJIT is that the graph can be built from stable named functions and explicit state, while the language and JIT provide proper tail-call and tracing machinery underneath.

The pattern is neither ordinary object orientation nor traditional closure-heavy CPS. It is better understood as:

> **an object-centered, first-class control-flow graph style built from ordinary Lua methods and proper tail calls.**

Or, more compactly:

> **`self` owns the machine; methods name its states; tail calls move it forward.**

---

## References

1. Lua 5.1 Reference Manual, §2.5.8, “Function Calls.”  
   https://www.lua.org/manual/5.1/manual.html

2. LuaJIT Project, “LuaJIT.”  
   https://luajit.org/luajit.html

3. LuaJIT Project, “Running LuaJIT.”  
   https://luajit.org/running.html

4. LuaJIT source, `src/lj_bc.h`, LuaJIT 2.1 branch. The bytecode set includes dedicated tail-call forms `CALLT` and `CALLMT`.  
   https://github.com/LuaJIT/LuaJIT/blob/v2.1/src/lj_bc.h

5. LuaJIT source, `src/lj_record.c`, LuaJIT 2.1 branch. The trace recorder includes dedicated tail-call recording via `lj_record_tailcall` and notes that tail calls can form loops.  
   https://github.com/LuaJIT/LuaJIT/blob/v2.1/src/lj_record.c
