# CBlock

CBlock is a small Lua DSL that constructs ordinary C. Lua owns staging, lexical names, modules, and namespaces. CBlock owns types, control, fusion, and C emission.

## 1. Names Belong To Lua

A CBlock declaration is an ordinary Lua value:

```lua
local clamp = region(i32, i32, i32, cont(i32))(function(x, lo, hi)
    return if_(lt(x, lo), lo, if_(gt(x, hi), hi, x))
end)

local add = func(i32, i32, ret(i32))(function(a, b)
    return a + b
end)
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

Types occur in one signature list. The trailing outcomes use two role-named constructors, following Lalin:

```text
ret(...)   the single, default exit — the result or void
cont(...)  one branch of a multi-outcome alternative
```

The kind of callable decides the shape:

```lua
func(i32, i32, ret(i32))                 -- one result; f(a, b) returns it
func(i32, ret())                         -- void operation

region(i32, i32, cont(i32), cont())      -- alternatives; r(a, d)(handlers)
region(i32, cont(i32))                   -- inline single result (transitions)
```

Rules:

- `func` has exactly one trailing `ret(...)` — no `cont`, so alternatives are impossible by construction. A func is a C ABI seal.
- `region` has either one `cont(...)` (an inline single result, the Lalin `done(result [T])` pattern) or two or more `cont(...)` (alternatives). Never a single `cont`, never mixed with `ret`.
- Calling: a `ret` callable is used without bindings — `f(a, b)` yields the value or performs the void op. A multi-`cont` region is used with bindings — `r(a, b)(handlers)`.
- Bodies bind their exits as trailing parameters, so `ret(v)` / `ok(v)` work as control statements in `if_`/`switch_` chains; plain `return v` stays the direct form.

```lua
local add = func(i32, i32, ret(i32))(function(a, b, ret)
    return ret(a + b)
end)

local sum = add(a, b)
```

Void is direct too:

```lua
local note = func(i32, ret())(function(value)
    return host_note(value)
end)

return note(value)
```

Only genuine alternatives introduce exit bindings, and they belong to regions:

```lua
local checked_div = region(i32, i32, cont(i32), cont())
    (function(a, d, succeeded, failed)
        return if_(eq(d, 0), failed(), succeeded(a / d))
    end)

return checked_div(a, d)(on_value, on_zero)
```

A func consumes alternatives into its single `ret`. Name each handler so the wiring reads like Lalin's `token = got_token, eof = done`:

```lua
local divide = func(i32, i32, ret(i32))(function(a, d, ret)
    local on_value = function(q) return ret(q) end
    local on_zero  = function() return ret(-1) end
    return checked_div(a, d)(on_value, on_zero)
end)
```

All outcome declarations must follow all operands. Each outcome carries zero or one value.

## 3. Bodies Are Deferred

`func`, `region`, and `block` store their Lua body closure before CBlock evaluates it. This lets ordinary Lua assignment establish recursive references:

A body is a statement list: the closure's return values are its statements, and the last one terminates. A single bare value is the direct result. So a machine transition writes its stores on separate lines and ends with its edge:

```lua
return store(pc, pc + 1),
       store(acc, twice + cast(i64, pc)),
       done(load(self.acc))
```

This is LLBL's own boundary shape: a staged body function returns its whole list, and the lowering receives the sequence as one artifact. `seq(...)` remains for the one place a list cannot be a return — a branch position (`if_` arm, handler body) where a single value is required.

```lua
local fib
fib = func(i32, ret(i32))(function(n)
    return if_(lt(n, 2), n, fib(n - 1) + fib(n - 2))
end)
```

A local block works the same way:

```lua
local loop
loop = block(i64, f64)(function(i, acc)
    return if_(eq(i, n), done(acc), loop(i + 1, acc + xs[i]))
end)

return loop(0, 0.0)
```

The block value is lexical. CBlock can assign generated C labels; source-level block naming needs no second namespace.

### 3.1 Blocks capture staging values as upvalues

A block body is a Lua closure, so it can capture anything in lexical scope: constants, other blocks, continuations, parameters, and not-yet-assigned locals.

```lua
local count = 3
local dispatch, loop

dispatch = block(State)(function(s)         -- captures loop, count, done
    return if_(ge(s.value, count), done(s.total), loop(s))
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
return if_(eq(d, 0)):then_(failed()):else_(succeeded(a / d))
```

`then` and `else` are Lua keywords, so the chain methods carry an underscore. When a branch is long, the chain may spread across lines — open on the condition, indent each branch, close with `):else_(` — but the single-line named form stays the default because the names self-document.

Lua functions are used only when they bind symbolic values: declaration bodies, block bodies, stream maps, and value-carrying alternative handlers.

## 6. Fused Data Pipelines

Streams describe scalar point computation:

```lua
local dot = region(ptr(f64), ptr(f64), i64, cont(f64))
    (function(xs, ys, n)
        local each = range(0, n)
        local products = zip(each:load(xs), each:load(ys)):map(function(x, y)
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

Vec2: add (Vec2, cont(Vec2)) (function(self, other)
    return Vec2 { x = self.x + other.x, y = self.y + other.y }
end)
```

A plain Lua function is an untyped staging macro. `Vec2: add (...)` declares a typed reusable region owned by `Vec2`; the owner is supplied as its first structural operand automatically.

```lua
local inline = a:add(b)
local sealed = call(Vec2.add)(a, b)
```

`Vec2 { ... }` constructs a C compound value. A typed struct expression supports field selection through ordinary Lua lookup. The owned region body receives the symbolic struct expression as `self`:

```lua
local energy = func(Vec2, ret(f64))(function(v)
    return v:length_squared()
end)
```

Methods are not C vtables, function pointers, or hidden runtime receivers. Plain Lua methods expand as staging macros. Owned regions receive `self` structurally through `Type: member (...)`; they apply inline by default and may enter an explicit private frame through `call(Vec2.add)`.

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
local host_add = extern(i32, i32, ret(i32))
local host_note = extern(i32, ret())

local add_twice = func(i32, i32, ret(i32))(function(a, b)
    return host_add(a, b) * 2
end)

return {
    host_add = host_add,
    host_note = host_note,
    add_twice = add_twice,
}
```

CBlock emits ordinary prototypes. Definitions and linking belong to the C toolchain. No FFI call layer is involved.

## 9. Object Machines

A struct becomes a machine when its fields are the complete state that survives transitions and its owned regions are those transitions:

```lua
local Orbit = struct {
    field: z (Complex),
    field: c (Complex),
    field: iteration (i32),
}

Orbit: advance (cont(Orbit)) (function(self)
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
    return region(T, cont(T))(function(state)
        local framed_transition = call(transition)
        for _ = 1, count do state = framed_transition(state) end
        return state
    end)
end

Orbit.iterate = repeated_transition(Orbit, Orbit.advance, 48)
```

### 9.1 Fused lexer + parser

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

VM: even (cont(VM)) (function(self)
    return VM {
        value = self.value / 2,
        steps = self.steps + 1,
        budget = self.budget - 1,
    }
end)
```

Local blocks are threaded instruction addresses. Emitted regions stay in the current VM frame; block jumps materialize the next state and become C `goto` edges:

```lua
local dispatch, even

dispatch = block(VM)(function(state)
    return state:classify()(halted, even, odd, trapped)
end)

even = block(VM)(function(state)
    return dispatch(state:even())
end)
```

There is no runtime opcode switch, computed-goto table, per-instruction call, result tag, or manually maintained program counter. Lua constructs the static instruction graph; CBlock checks and lowers it; GCC receives ordinary locals, labels, and branches.

Use `call` only when entering a genuinely nested machine frame. Instructions belonging to the current interpreter frame use regions plus blocks.

See `hailstone_vm.lua` for a complete direct-threaded VM and differential C benchmark.

## 11. Interactive TCC Cooking

`C.jit` returns the ordinary Lua namespace immediately. Its exported `func` values compile the module on first host invocation:

```lua
local math = assert(C.jit(function()
    local add = func(i32, i32, ret(i32))(function(a, b)
        return a + b
    end)
    return { add = add }
end))

assert(math.add(20, 22) == 42) -- cooks module, resolves and calls add
assert(math.add(1, 2) == 3)    -- reuses code and cached function pointer
math:free()
```

One `func` object therefore has two phase-correct applications. During CBlock body construction, applying it builds a symbolic C call. After `C.jit` returns the namespace, applying an exported function from host Lua ensures the module is cooked and invokes its typed native symbol.

The first exported-function invocation compiles the complete module. This preserves ordinary calls among generated functions and gives recursive and mutually dependent functions one coherent native world. Later invocations reuse the TCC state and cached pointers.

A direct function returns its C result to Lua. A void function returns no value. A multi-exit function returns the selected ordinal and its optional carried value:

```lua
local exit, quotient = math.checked_div(84, 2)
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
       done(load(frame))
```

Places are also builders, so the same reads and writes chain from the place itself:

```lua
return vec.data:at(0):store(10),          -- member :at :store
       vec.n:store(2),                    -- member :store
       acc:store(cast(i64, vec.n:load())), -- explicit conversion
       done(acc:load())

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
    local host_add = extern(i32, i32, ret(i32))

    local clamp = region(i32, i32, i32, cont(i32))(function(x, lo, hi)
        return if_(lt(x, lo), lo, if_(gt(x, hi), hi, x))
    end)

    local demo = func(i32, i32, ret(i32))(function(x, y)
        return clamp(host_add(x, y), 0, 100)
    end)

    return {
        host_add = host_add,
        demo = demo,
    }
end)

assert(source, table.concat(errors, "\n"))
```

The core rule is small:

```text
Lua owns names and composition.
One outcome is direct.
Many outcomes are explicit.
Regions inline unless called.
Pipelines fuse into ordinary C.
```