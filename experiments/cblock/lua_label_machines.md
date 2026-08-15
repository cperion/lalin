# CBlock: Lua Label Machines and Named Control Protocols

CBlock is a small Lua DSL that constructs ordinary C. Lua owns staging, lexical
names, modules, and namespaces. CBlock owns types, named control protocols,
fusion, and C emission. A nested object-machine hierarchy can remain modular in
Lua while lowering to flat monomorphic C control flow.

## 1. Names Belong To Lua

A CBlock declaration is an ordinary Lua value:

```lua
local clamp = region(
    param: x (i32),
    param: lo (i32),
    param: hi (i32)
)(i32)(function(p)
    return if_(lt(p.x, p.lo), p.lo, if_(gt(p.x, p.hi), p.hi, p.x))
end)

local add = func
    (param: a (i32), param: b (i32))
    (i32)
    (function(p) return p.a + p.b end)
```

There is no `region: clamp`, `func: add`, or `block: loop` form. A constructor does not capture the spelling of its Lua local. Lua locals are aliases, not compiler symbol declarations.

A table owns a namespace. The table returned by the compilation chunk exports its declarations:

```lua
return {
    math = {
        add = add,
        clamp = clamp,
    },
}
```

A nested path gives the exported C name. The example exports `math_add`. Attaching the value elsewhere changes namespace ownership without changing the value itself.

This separation is deliberate:

```text
Lua local or table field   staging identity and organization
returned namespace path    public C ABI name
CBlock object              semantic declaration
```

A `func` that is not exported is a private `static` helper. A `region` is inline and has no C symbol unless `call(region)` requests a generated private seal. An `extern` must be exported because its namespace path is the C symbol supplied by the linker.

## 2. Signatures State Outcomes

Callable inputs are named. Function and extern result types are curried after
their parameter product; continuations remain region control parameters:

```text
param: name (...)   one named callable input
func(params)(T)     function returning T
extern(params)(T)   external function returning T
cont: name (...)    one named region continuation
```

The kind of callable decides the shape:

```lua
func (param: a (i32), param: b (i32)) (i32)
func (param: value (i32)) (void)

region(param: x (i32))(i32)
region(param: a (i32), param: d (i32),
    cont: divided (i32),
    cont: zero ())
```

The region rule is small: **a direct region curries its result type like a func;
plural continuations are named**. Return types are not continuations.

- A `func` has named parameters and one separately curried native result type.
- A direct region declares its result type in the same curried position.
- A region has ordered, uniquely named `param: name (type)` inputs.
- Region continuations are parameters, not return types.
- An alternative region has two or more uniquely named `cont: name (...)`
  parameters. Unnamed `cont(...)` is not accepted; direct regions use the
  curried result type instead.

A region body receives one immutable parameter product `p`; a plural body also
receives immutable continuation protocol `c`:

```lua
local checked_div = region(
    param: a (i32),
    param: d (i32),
    cont: divided (i32),
    cont: zero ()
)(function(p, c)
    return if_(eq(p.d, 0), c:zero(), c:divided(p.a / p.d))
end)
```

`p.a` projects a declared input. `c:divided(value)` selects an exit, while
`c.divided` is the same exit as a first-class staging value for direct
forwarding. Unknown parameter or exit names and wrong carried values are errors.

The caller supplies one exact named-handler table:

```lua
return checked_div(a, d) {
    divided = on_value,
    zero = on_zero,
}
```

The table is consumed during staging. It is not a runtime handler map: CBlock
validates missing and extra names, then wires handlers in declaration order to
direct control edges. Forwarding does not need a wrapper:

```lua
return child:operation(input) {
    accepted = c.accepted,
    rejected = c.rejected,
}
```

A func can consume the protocol into its one return:

```lua
local divide = func
    (param: a (i32), param: d (i32))
    (i32)
    (function(p, r)
        return checked_div(p.a, p.d) {
            divided = function(q) return r(q) end,
            zero = function() return r(-1) end,
        }
    end)
```

A func body normally receives `p`. It may receive its return edge as a second
binder `r` when nested blocks or continuation handlers must return explicitly.
Regions receive `p`; only plural regions receive the second binder `c`.

## 3. Bodies Are Deferred

`func`, `region`, and `block` store their Lua body closure before CBlock evaluates it. This lets ordinary Lua assignment establish recursive references:

A body is a statement list: the closure's return values are its statements, and the last one terminates. A single bare value is the direct result. So a machine transition writes its stores on separate lines and ends with its edge:

```lua
return store(pc, pc + 1),
       store(acc, twice + cast(i64, pc)),
       c:done(load(self.acc))
```

This is LLBL's own boundary shape: a staged body function returns its whole list, and the lowering receives the sequence as one artifact. `seq(...)` remains for the one place a list cannot be a return — a branch position (`if_` arm, handler body) where a single value is required.

```lua
local fib
fib = func (param: n (i32)) (i32) (function(p)
    return if_(lt(p.n, 2), p.n, fib(p.n - 1) + fib(p.n - 2))
end)
```

A local block works the same way:

```lua
local loop
loop = block(i64, f64)(function(i, acc)
    return if_(eq(i, n), c:done(acc), loop(i + 1, acc + xs[i]))
end)

return loop(0, 0.0)
```

The block value is lexical. CBlock can assign generated C labels; source-level block naming needs no second namespace.

### 3.1 Blocks capture staging values as upvalues

A block body is a Lua closure, so it can capture anything in lexical scope: constants, other blocks, continuations, parameters, and not-yet-assigned locals.

```lua
local count = 3
local dispatch, loop

dispatch = block(State)(function(s)         -- captures loop, count, c.done
    return if_(ge(s.value, count), c:done(s.total), loop(s))
end)
loop = block(State)(function(s)             -- captures dispatch
    return dispatch(State { value = s.value + 1, total = s.total + s.value })
end)
```

Because bodies are staged after the surrounding chunk runs, a block can reference a local assigned later — that is what makes mutually threaded instruction graphs readable. `count` becomes a constant in the emitted C; `dispatch`/`loop` become `goto` edges. The emitted C has no hidden capture: every upvalue resolves to a register, constant, or jump at lowering time.

There are three capture kinds with different costs:

```text
Lua constant/type/block/continuation   resolves at staging; free
expression tree local                   re-inlined per use; use let to materialize once
var place                              shared mutable storage in the enclosing function
```

The discipline matches the rest of the model: block parameters carry values that vary per jump; Lua upvalues carry staging constants, forward references, and structure. Lalin blocks require explicit parameter products and forbid hidden capture; CBlock inherits Lua's lexical scoping instead, which is what makes machine composition direct. The artifact stays strict either way.

Block parameters deliberately stay positional. The named product/protocol discipline applies where semantics have an owner — callable objects and their continuations. A block is an anonymous local label inside one named owner: its parameters are per-jump values, its body is a `goto` target, and it never declares outcomes. Naming them would bury the hot threading loop in ceremony without adding an owner to own them.
## 4. Inline By Default, Seal Explicitly

Applying a region emits its body into the caller:

```lua
local bounded = clamp(x, 10, 100)
```

`call` gives the region a real frame, represented by one cached private C function:

```lua
local bounded = call(clamp)(x, 10, 100)
```

A `func` is already a C function boundary. Direct self-calls are ordinary recursive C calls. A region cannot emit itself recursively; recursion must cross `call(region)`.

## 5. Value And Control Conditionals

`if_` over expressions produces an expression; over blocks or exit applications it produces control. Two spellings are equivalent — the positional form and the chained form:

```lua
return if_(lt(x, lo), lo, if_(gt(x, hi), hi, x))

return if_(lt(x, lo)):then_(lo)
    :else_(if_(gt(x, hi)):then_(hi):else_(x))
```

The chained form is the primary way to name branches. Because blocks carry names, a conditional reads like a sentence:

```lua
local reject = block()(function() ... end)
local accept = block()(function() ... end)

return if_(invalid(input))
    :then_(reject)
    :else_(accept)
```

Control branches read the same way:

```lua
return if_(eq(p.d, 0)):then_(c:failed()):else_(c:succeeded(p.a / p.d))
```

`then` and `else` are Lua keywords, so the chain methods carry an underscore. When a branch is long, the chain may spread across lines — open on the condition, indent each branch, close with `):else_(` — but the single-line named form stays the default because the names self-document.

Lua functions are used only when they bind symbolic values: declaration bodies, block bodies, stream maps, and value-carrying alternative handlers.

## 6. Fused Data Pipelines

Streams describe scalar point computation:

```lua
local dot = region(
    param: xs (ptr(f64)),
    param: ys (ptr(f64)),
    param: n (i64)
)(f64)(function(p)
    local each = range(0, p.n)
    local products = zip(each:load(p.xs), each:load(p.ys)):map(function(x, y)
        return x * y
    end)
    return products:reduce(add, 0.0)
end)
```

`load`, `zip`, and `map` allocate nothing. `store` and `reduce` materialize one fused C loop. CBlock emits ordinary scalar C; GCC `-O3` owns vectorization, unrolling, and other optimization.

## 7. Structs And Methods

Structs are C value types with an explicit ordered field list:

```lua
local Vec2 = struct {
    field: x (f64),
    field: y (f64),
}

function Vec2:length_squared()
    return self.x * self.x + self.y * self.y
end

Vec2: add (param: other (Vec2)) (Vec2) (function(p)
    return Vec2 {
        x = p.self.x + p.other.x,
        y = p.self.y + p.other.y,
    }
end)
```

A plain Lua function is an untyped staging macro. `Vec2: add (...)` declares a typed reusable region owned by `Vec2`; the owner is projected as the implicit named input `p.self`.

```lua
local inline = a:add(b)
local sealed = call(Vec2.add)(a, b)
```

`Vec2 { ... }` constructs a C compound value. A typed struct expression supports
field selection through ordinary Lua lookup. The owned region parameter product
contains the owner as `p.self`:
```lua
local energy = func (param: v (Vec2)) (f64)
    (function(p) return p.v:length_squared() end)
```

Methods are not C vtables, function pointers, or hidden runtime receivers. Plain Lua methods expand as staging macros. Owned regions receive `p.self` structurally through `Type: member (...)`; they apply inline by default and may enter an explicit private frame through `call(Vec2.add)`.

The returned namespace owns the C typedef name:

```lua
return { Vec2 = Vec2, energy = energy }
```

This emits `typedef struct Vec2 { ... } Vec2;`. The field list is the written order — the physical C layout is exactly what appears in source and never depends on Lua table iteration. This matters for ABI compatibility, wire formats, and existing C headers. `field: name (type)` is explicit because a field is a member identity owned by its struct, not a Lua binding. Recursive value fields are invalid; recursive topology uses pointer fields.

Initial struct scope:

- named, ordered fields;
- by-value construction;
- field selection;
- pointers to structs;
- Lua-defined inline macro methods and typed region methods;
- struct parameters and results;
- deterministic C declarations before prototypes.

Unions, bitfields, packed layout, inheritance, virtual dispatch, and implicit allocation are outside this initial vocabulary.

## 8. Externs Are Ordinary C

An extern has the same direct signature rule and no body:

```lua
local host_add = extern
    (param: a (i32), param: b (i32))
    (i32)
local host_note = extern (param: value (i32)) (void)

local add_twice = func
    (param: a (i32), param: b (i32))
    (i32)
    (function(p) return host_add(p.a, p.b) * 2 end)

return {
    host_add = host_add,
    host_note = host_note,
    add_twice = add_twice,
}
```

CBlock emits ordinary prototypes. Definitions and linking belong to the C toolchain. No FFI call layer is involved.

## 9. Object Machines

A struct becomes a machine when its fields are the complete state that survives
transitions and its owned regions are those transitions:

```lua
local Orbit = struct {
    field: z (Complex),
    field: c (Complex),
    field: iteration (i32),
}

Orbit: advance () (Orbit) (function(p)
    local self = p.self
    local next_z = self.z:square_add(self.c)
    local next = Orbit {
        z = next_z, c = self.c, iteration = self.iteration + 1,
    }
    return if_(gt(self.z:norm_squared(), 4.0), self, next)
end)
```

Lua can construct a monomorphic transition family without adding runtime genericity:

```lua
local function repeated_transition(T, transition, count)
    return region(param: state (T))(T)(function(p)
        local state = p.state
        local framed_transition = call(transition)
        for _ = 1, count do state = framed_transition(state) end
        return state
    end)
end

Orbit.iterate = repeated_transition(Orbit, Orbit.advance, 48)
```

### 9.1 Hierarchical components and view projections

An application can be modeled as a root machine that receives user and system
events and owns submachines for its components. Each component owns persistent
state, typed event transitions, named outcomes, child machines, and its view
projection. The parent wires child outcomes directly:

```lua
local PRESS, CLICK, QUIT = 1, 2, 3

local Event = struct { field: code (i32) }
local Button = struct { field: pressed (bool) }
local Dialog = struct { field: open (bool) }

local ButtonView = struct { field: pressed (bool) }
local DialogView = struct { field: visible (bool) }
local AppView = struct {
    field: button (ButtonView),
    field: dialog (DialogView),
}

Button: event (
    param: event (Event),
    cont: ignored (), cont: changed (Button), cont: clicked ()
)(function(p, c)
    return if_(eq(p.event.code, PRESS),
        c:changed(Button { pressed = true }),
        if_(eq(p.event.code, CLICK), c:clicked(), c:ignored()))
end)

Button: view () (ButtonView) (function(p)
    return ButtonView { pressed = p.self.pressed }
end)

Dialog: view () (DialogView) (function(p)
    return DialogView { visible = p.self.open }
end)

-- App owns the complete durable state of both child machines.
local App = struct {
    field: button (Button),
    field: dialog (Dialog),
}

App: event (
    param: event (Event),
    cont: unchanged (), cont: changed (App), cont: quit ()
)(function(p, c)
    local self, event = p.self, p.event
    local changed_button = function(button)
        return c:changed(App { button = button, dialog = self.dialog })
    end
    local opened_dialog = function()
        return c:changed(App {
            button = self.button, dialog = Dialog { open = true },
        })
    end

    return if_(eq(event.code, QUIT), c:quit(),
        self.button:event(event) {
            ignored = c.unchanged,
            changed = changed_button,
            clicked = opened_dialog,
        })
end)

-- The parent view is only the composition of child state projections.
App: view () (AppView) (function(p)
    return AppView {
        button = p.self.button:view(),
        dialog = p.self.dialog:view(),
    }
end)
```

This replaces command construction, message wrapping, and parent message mapping
with named staging-time control wiring. A child knows only its exit protocol;
the parent decides whether an exit updates itself, enters a sibling, reaches an
effect boundary, or propagates upward.

The view is a projection of the same machine state. A component-owned direct
`view` region can receive narrow layout/theme/renderer inputs and project its
state into a typed view product, drawing, geometry, and hit facts. Parent state
composition, child control wiring, and child view composition therefore share
one ownership tree.
No separate virtual component identity or duplicate view state is required.
Static component topology specializes through Lua; dynamic collections remain
ordinary typed runtime data.

Immediate transitions use named exits. Work completed on a later event-loop turn
must store an exact durable resumption identity in machine state and re-enter on
a later root event; no suspended Lua continuation escapes staging.

### 9.2 Fused lexer + parser

`expr_parser.lua` is a complete arithmetic evaluator written as one machine. `Evaluator` owns its state and its regions: `scan` and `peek` are owned inline lexer regions (classify the next token or lookahead character without an array), and `parse_primary` / `parse_term` / `parse_expr` are owned parser funcs that drive the lexer inline. Lexing and parsing are one fused control graph over the source bytes — no token vector, no allocation, one pass.

The lookahead protocol is explicit: `scan` consumes a token and leaves the cursor past it; `peek` classifies without consuming; operator loops advance by one character and `scan` the operand. Validated through both GCC and TCC (`12+34*2` → 80, `7*(3+2)` → 35, `100-25/5+2` → 97, `((1))` → 1, `12+` → malformed).

The repeated machine needs a frame because its evolving state survives one transition and becomes the input to the next. `call(Orbit.advance)` supplies that frame. Exponential staged-expression growth is the failure symptom when this required frame is omitted; avoiding growth is not itself the semantic reason for `call`.

The outer population pipeline also enters a framed `Orbit.iterate`. The object owns persistent facts and transitions; the frame owns one computation in progress; the representation remains flat C values and one ordinary outer loop.

See `mandelbrot.lua` for the complete image generator.

## 10. Direct-Threaded Interpreters

One function frame can contain a complete interpreter. The machine struct owns persistent VM state and instruction semantics:

```lua
local VM = struct {
    field: value (i64),
    field: steps (i64),
    field: budget (i64),
}

VM: classify (
    cont: halted (VM), cont: even (VM),
    cont: odd (VM), cont: trapped (VM)
)(function(p, c)
    local self = p.self
    return if_(le(self.value, 0), c:trapped(self),
        if_(eq(self.value, 1), c:halted(self),
            if_(eq(self.value % 2, 0), c:even(self), c:odd(self))))
end)

VM: even () (VM) (function(p)
    local self = p.self
    return VM {
        value = self.value / 2,
        steps = self.steps + 1,
        budget = self.budget - 1,
    }
end)

VM: odd () (VM) (function(p)
    local self = p.self
    return VM {
        value = self.value * 3 + 1,
        steps = self.steps + 1,
        budget = self.budget - 1,
    }
end)
```

Local blocks are threaded instruction addresses. Emitted regions stay in the current VM frame; block jumps materialize the next state and become C `goto` edges:

```lua
local run = region(param: initial (VM),
    cont: halted (i64), cont: trapped (VM)
)(function(p, c)
    local dispatch, execute_even, execute_odd

    dispatch = block(VM)(function(state)
        return state:classify() {
            halted = function(done) return c:halted(done.steps) end,
            even = execute_even,
            odd = execute_odd,
            trapped = c.trapped,
        }
    end)

    execute_even = block(VM)(function(state)
        return dispatch(state:even())
    end)

    execute_odd = block(VM)(function(state)
        return dispatch(state:odd())
    end)

    return dispatch(p.initial)
end)
```

There is no runtime opcode switch, computed-goto table, per-instruction call, result tag, or manually maintained program counter. Lua constructs the static instruction graph; CBlock checks and lowers it; GCC receives ordinary locals, labels, and branches.

Use `call` only when entering a genuinely nested machine frame. Instructions belonging to the current interpreter frame use regions plus blocks.

See `hailstone_vm.lua` for a complete direct-threaded VM and differential C benchmark.

## 11. Interactive TCC Cooking

`C.jit` returns the ordinary Lua namespace immediately. Its exported `func` values compile the module on first host invocation:

```lua
local math = assert(C.jit(function()
    local add = func
        (param: a (i32), param: b (i32))
        (i32)
        (function(p) return p.a + p.b end)
    return { add = add }
end))

assert(math.add(20, 22) == 42) -- cooks module, resolves and calls add
assert(math.add(1, 2) == 3)    -- reuses code and cached function pointer
math:free()
```

One `func` object therefore has two phase-correct applications. During CBlock body construction, applying it builds a symbolic C call. After `C.jit` returns the namespace, applying an exported function from host Lua ensures the module is cooked and invokes its typed native symbol.

The first exported-function invocation compiles the complete module. This preserves ordinary calls among generated functions and gives recursive and mutually dependent functions one coherent native world. Later invocations reuse the TCC state and cached pointers.

A direct function returns its C result to Lua. A void function returns no value.
A sealed multi-exit function keeps integer ordinals in its native C ABI, but the
Lua host boundary returns the selected exit **name** and its optional value:

```lua
local exit, quotient = math.checked_div(84, 2)
assert(exit == "divided")
```

Exported struct types construct matching LuaJIT FFI values, so by-value struct parameters and results retain their C ABI shape.

TCC supplies the interactive cooker without a temporary source file, object file, shared object, or subprocess. The lazy module owns relocated code; function pointers become invalid after `module:free()`. Host externs are supplied as stable FFI pointers through `C.jit(build, { symbols = ... })`.

TCC prioritizes compilation latency rather than GCC `-O3` optimization. The same emitted C remains available through `C.compile` for optimized GCC execution and AOT artifacts.

## 12. Surface Completion Order

CBlock completes its language surface and deterministic C production before investing in polished diagnostics.

### 12.1 Runtime values and places  (implemented)

```lua
local value = let(expression)     -- materialize once
local frame = var(Frame, initial) -- local mutable storage
local slot = at(stack, sp)        -- ptr[index] place

store(frame.pc, frame.pc + 1)     -- places auto-load in expressions
store(slot, value)
return store(slot, value),
       c:done(load(frame))
```

Places are also builders, so the same reads and writes chain from the place itself:

```lua
return vec.data:at(0):store(10),          -- member :at :store
       vec.n:store(2),                    -- member :store
       acc:store(cast(i64, vec.n:load())), -- explicit conversion
       c:done(acc:load())
```

`let` materializes one immutable C value and reuses its register. `var` creates function-frame storage initialized at entry. `at`, `member`, and `deref` create places; `load`, `store`, `address`, `at`, and `deref` are both free functions and methods — `store(frame.pc, v)` and `frame.pc:store(v)` are the same statement, `at(xs, i):load()` reads, `vec.data:at(0):store(10)` chains, `slot:address()` takes an address, and `frame_ptr:deref().acc:store(v)` writes through a pointer. The builder methods live on places; `at` and `deref` additionally exist on pointer expressions, so `xs:at(1):load()` and `xs:deref():store(v)` read and write through a pointer parameter. Places auto-load in expression contexts and auto-index member fields, so `frame.pc + 1` reads the place. A body is a statement list: its return values are statements and the last one terminates, so stores read as straight lines before a jump, return, or continuation edge. `seq` remains for branch positions, where a single value is required.

Every block path terminates. The checker rejects a body, block, or `if_`/`switch` arm whose last statement is not a jump, exit, return, or call — the same invariant Lalin enforces. A `seq` whose final item is a store or void call is rejected with a clear message.

### 12.2 Complete scalar C  (implemented)

`i8 i16 i32 i64 u8 u16 u32 u64 f32 f64 bool usize isize` are available. `cast(T, value)` is the only conversion; CBlock adds no implicit numeric conversions. `bit_and bit_or bit_xor shift_left shift_right` operate on integers. `sizeof(T)` yields `usize`. `_Alignof` is deferred.

### 12.3 Physical aggregates  (implemented)

`array(T, N)` is a fixed C array usable as a struct field; `at(array_place, i)` indexes it as an lvalue, `address` decays it to a pointer, and `sizeof` is exact. Arrays cannot cross a call boundary — use `ptr(array)` or a view. `view(T)` is a `(ptr, length)` pair type built from structs, so ranges consume its bounds directly.

### 12.4 Stored alternatives  (implemented)

Named integer constants, multi-way control dispatch, and physical unions:

```lua
local Opcode = enum { add = 0, sub = 1, halt = 2 }

return switch_(opcode)
    :case_(Opcode.add):then_(do_add)
    :case_(Opcode.sub):then_(do_sub)
    :default(do_halt)
```

`switch_` requires a `default` arm, rejects duplicate keys, and lowers to a real C `switch` whose cases are gotos — GCC turns a dense table into an indirect jump. A `union` is a C union constructed by naming one active member (`Value { floating = x }`), with member reads reinterpreting the storage. Immediate semantic alternatives remain continuations.

### 12.5 Storage and linkage  (implemented)

`global(T, init)` emits file-scope `static` storage with a Lua-built initializer (number, string literal, or table of numbers) and is an lvalue for `load`/`store`/`at`. `cstring("...")` is a static NUL-terminated byte array usable as `ptr(u8)`. Lua constructs all static data.

### 12.6 C ABI closure  (implemented)

`opaque("Tag")` is an incomplete C struct usable through pointers in extern signatures. `fnptr(result, ...)` is a function-pointer type; `address(func)` yields a callable value of that shape; calling a fnptr value lowers to an ordinary C call. Opaque forward declarations and fnptr parameter names are emitted correctly, so externs can take and return callbacks and handle types. Allocation, files, sockets, and system services remain ordinary externs.

### 12.7 Production criterion  (met)

Every feature above is validated through both paths consuming the same emitted C:

```text
CBlock → C text → TCC memory cooking → callable symbol
              └→ GCC/AOT compilation → ordinary artifact
```

The emitted C, execution tests, and differential tests are the development oracle. The surface is operational; remaining work is diagnostics polish (rich source locations, recovery, formatting), which was intentionally deferred.

CBlock does not add a vector IR, optimizer IR, scheduler, GC, exception runtime, class system, or second module language.

## 13. Complete Example

```lua
local source, errors = C.compile(function()
    local host_add = extern
        (param: a (i32), param: b (i32))
        (i32)

    local clamp = region(
        param: x (i32),
        param: lo (i32),
        param: hi (i32)
    )(i32)(function(p)
        return if_(lt(p.x, p.lo), p.lo, if_(gt(p.x, p.hi), p.hi, p.x))
    end)

    local demo = func
        (param: x (i32), param: y (i32))
        (i32)
        (function(p)
            return clamp(host_add(p.x, p.y), 0, 100)
        end)

    return {
        host_add = host_add,
        demo = demo,
    }
end)

if not source then error(table.concat(errors, "\n")) end
```

The core rule is small:

```text
Lua owns names and composition.
One outcome is direct.
Many outcomes form a named control protocol.
Region bodies receive named inputs as p; plural protocols add c.
Regions inline unless called.
Objects own state, transitions, children, and view projections.
Pipelines fuse into ordinary C.
```
