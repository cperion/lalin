# CBlock Language Reference

CBlock is a Lua DSL that constructs ordinary C. This document is the
systematic reference to the surface. The design narrative and motivation live
in [lua_label_machines.md](lua_label_machines.md).

## 1. Model

A CBlock program is a Lua chunk run inside a staging environment. Declarations
are ordinary Lua values:

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

Three structural facts organize everything else:

1. **Bodies are deferred Lua closures.** `func`, `region`, and `block` store
   their body function and stage it later, so forward and recursive references
   work: `local loop; loop = block(...)(function(...) ... loop(...) ... end)`.
2. **A body is a statement list.** The closure's return values are its
   statements; the last one terminates. A single bare value is the direct
   result. A machine transition writes its effects on separate lines and ends
   with its edge:

   ```lua
   return store(pc, pc + 1),
          store(acc, twice + cast(i64, pc)),
          c:done(load(self.acc))
   ```

   `seq(...)` remains for branch positions (an `if_` arm, a handler body) where
   a single value is required.
3. **A block is a label.** `block(T1, T2)(function(a, b) ... end)` declares a
   labeled address carrying parameters; `block_value(args)` in a body is a jump
   that becomes a C `goto` edge. Jumping is the only way to enter a block.

Every block path terminates. The checker rejects a body, block, or `if_`/`switch`
arm whose last statement is not a jump, exit, return, or call.

## 2. Names and namespaces

The compilation chunk returns a Lua table; its paths become public C ABI names:

```lua
return {
    math = { add = add, clamp = clamp },   -- C names: math_add, math_clamp
}
```

- A `func` that is not exported is a private `static` helper.
- A `region` is inline and has no C symbol unless `call(region)` requests one
  cached private `static` seal.
- An `extern` must be exported; its namespace path is the C symbol the linker
  supplies.
- A struct/union exported under `T` gives the C typedef name
  `typedef struct T { ... } T;`.

## 3. Types

Scalars: `i8 i16 i32 i64 u8 u16 u32 u64 f32 f64 bool usize isize`.

| Type | Meaning |
|------|---------|
| `ptr(T)` | pointer to `T` |
| `array(T, N)` | fixed C array; struct fields only, never a call value |
| `view(T)` | `(ptr, length)` pair struct with fields `ptr` and `length` (i64) |
| `struct { field: ... }` | ordered C struct |
| `union { field: ... }` | C union, one active member at construction |
| `enum { name = n, ... }` | named integer constants (a plain Lua table) |
| `opaque("Tag")` | incomplete C struct, usable through pointers |
| `fnptr(result, ...)` | function-pointer type (shape-cached) |

`cast(T, v)` is the only conversion; there are no implicit numeric
conversions. `sizeof(T)` yields `usize`.

Arrays and opaque types cannot cross a call boundary — signatures reject them
with guidance to use `ptr()`. `view(T)` is the bounded-range alternative.

## 4. Signatures and outcomes

Callable inputs are named. Functions and externs curry their result type after
the parameter product; region continuations remain control parameters:

```text
param: name (type)    one named callable input
func(params)(type)    one native function result type
extern(params)(type)  one native external result type
cont: name (...)      one named region continuation
```

- `func`, `extern`, and direct `region` declare ordered named parameters, then
  one curried result type. Use `void` when no value is returned.
- Bodies receive their immutable parameter product as `p`; `p.name` projects an
  input. Calls may use positional sugar or one exact named-input table.
- Region continuations are parameters, not return types. An alternative region
  has two or more uniquely named `cont: name (...)`; unnamed `cont(...)` is not
  accepted — a direct region curries its result type instead.
- A plural region body receives `(p, c)`. `c:name(value)` selects a continuation
  and `c.name` forwards it.
- A plural application consumes one exact named-handler table. Missing, extra,
  or unknown names are errors; there is no positional handler form.
- A func body can receive its return edge as optional second binder `r` when local
  control or handlers must return explicitly. Plain `return value` is direct.

## 5. Callables

### `func(params)(type)`

```lua
local add = func
    (param: a (i32), param: b (i32))
    (i32)
    (function(p) return p.a + p.b end)
local sum = add(a, b)          -- symbolic call in staging
```

Direct calls need no bindings. A void function uses `void` in the result position
and is used as a terminating statement, or through `void_call(f, ...)` in the
middle of a statement sequence. Exported funcs are public C ABI seals; unexported
funcs are private `static` helpers.

### `region(...)`

A region has two shapes. A direct region curries its result type like a func:

```lua
local clamp = region(
    param: x (i32),
    param: lo (i32),
    param: hi (i32)
)(i32)(function(p)
    return if_(lt(p.x, p.lo), p.lo, if_(gt(p.x, p.hi), p.hi, p.x))
end)
```

An alternative region declares its named continuations among its parameters:

```lua
local checked_div = region(
    param: a (i32),
    param: d (i32),
    cont: divided (i32),
    cont: zero ()
)(function(p, c)
    return if_(eq(p.d, 0), c:zero(), c:divided(p.a / p.d))
end)

return checked_div(a, d) {
    divided = on_value,
    zero = on_zero,
}
```

Applying a region inlines its body into the caller. Named handler tables are
staging-time control wiring, not runtime dispatch maps. `call(region)` gives the
region one cached private C frame while retaining the same named call surface.

Use `call(region)` when a region would recursively emit itself or when the
computation needs a real frame:

```lua
local bounded = clamp(x, 10, 100)      -- inline
local framed  = call(clamp)(x, 10, 100) -- one cached private static seal
```

A region cannot emit itself recursively; recursion must cross `call(region)`.

### `block(...)`

```lua
local run = func
    (param: initial (VM))
    (i64)
    (function(p, r)
        local dispatch, even, done
        done = block(VM)(function(st) return r(st.steps) end)
        dispatch = block(VM)(function(state) return even(state) end)
        even = block(VM)(function(state)
            return dispatch(VM { value = state.value / 2, steps = state.steps + 1 })
        end)
        local entry = block(VM)(function(st)
            return if_(eq(st.value, 0), done(st), even(st))
        end)
        return entry(p.initial)
    end)
```

A label in the current function frame. `block(...)` must be declared inside a
func/region body; block operands are values, never outcomes. Jumping to a block
is a C `goto`.

### `extern(params)(type)`

```lua
local host_add = extern
    (param: a (i32), param: b (i32))
    (i32)
local host_note = extern (param: value (i32)) (void)
```

A prototype with the same direct signature rule and no body. Must be exported.
Definitions and linking belong to the C toolchain; the TCC path resolves host
symbols as FFI pointers passed via `C.jit(build, { symbols = ... })`.

## 6. Bodies and statements

A body's return values are its statement list; the last terminates. Statements:

| Statement | Form |
|-----------|------|
| store | `store(place, value)` or `place:store(value)` |
| void call | `void_call(f, ...)` |
| control if | `if_(c, stmt, stmt)` or the chain `if_(c):then_(b):else_(b)` |
| switch | `switch_(v):case_(k):then_(block):default(block)` |
| jump | a block application `loop(x)`; a return-edge application `r(v)`; a continuation application `c:ok(v)`; a tail call `f(...)` |
| seq | `seq(effect, ..., terminator)` — branch positions only |
| pipeline store | `stream:store(dst)` |

Terminators (what the last statement may be): block jump, exit application,
tail call, void-func call, `return_value`, control `if_`, `switch_`,
`pipeline_store`, or a `seq` whose own last item terminates.

`store` takes a place; places auto-load in expression contexts.

## 7. Expressions

Literals, arithmetic/comparison/bitwise operators, `cast`, `sizeof`, `let`,
value-`if_` (select), struct construction and field access, function calls,
function pointers, and pipeline values.

`let(v)` materializes one immutable C value and reuses its register. Value
`if_` is the same spelling as control `if_` — value branches produce an
expression, block/statement branches produce control:

```lua
return if_(lt(x, lo), lo, if_(gt(x, hi), hi, x))   -- value
return if_(eq(p.d, 0)):then_(c:failed()):else_(c:succeeded(p.a / p.d)) -- control
```

`T { field = value, ... }` constructs a C compound value; typed struct
expressions support ordinary Lua field lookup. `address(func)` yields a
callable value of the matching `fnptr` shape; calling it is an ordinary C call.

## 8. Places

A place is an addressable location. Kinds: `var` (function-frame storage
initialized at entry), `at` (`ptr[i]` or `array[i]` lvalue), `member` (field),
`deref` (through a pointer), `global` (file-scope static).

```lua
local value = let(expression)     -- materialize once
local frame = var(Frame, initial) -- local mutable storage
local slot = at(stack, sp)        -- ptr[index] place
```

Places auto-load in expression contexts and auto-index member fields, so
`frame.pc + 1` reads the place and `store(frame.pc, v)` writes it. The explicit
protocol is `load`, `store`, `address`; every place op is also a builder
method:

```lua
return vec.data:at(0):store(10),       -- member :at :store
       vec.n:store(2),                 -- member :store
       acc:store(cast(i64, vec.n:load())),  -- explicit conversion
       c:done(acc:load())
```

`at` and `deref` additionally exist on pointer expressions:
`xs:at(1):load()`, `xs:deref():store(v)`. `address(place)` decays an array or
takes the address of a value. A struct field named like a method (`load`,
`store`, ...) wins the member identity — methods never shadow fields.

## 9. Structs and methods

```lua
local Vec2 = struct {
    field: x (f64),
    field: y (f64),
}

function Vec2:length_squared()          -- plain Lua macro (untyped)
    return self.x * self.x + self.y * self.y
end

Vec2: add (param: other (Vec2)) (Vec2) (function(p) -- typed owned region
    return Vec2 {
        x = p.self.x + p.other.x,
        y = p.self.y + p.other.y,
    }
end)
```

- The field list is the written order — physical C layout, never Lua table
  iteration order.
- `Vec2 { ... }` constructs a compound value; field selection is ordinary Lua
  lookup.
- Owned regions receive the owner as the implicit named input `p.self`; declared
  parameters are projected from the same product. They inline by default and may
  enter a private frame via `call(Vec2.add)`.
- Methods are not vtables or hidden receivers; plain Lua methods expand as
  staging macros, owned regions are structural.
- Recursive value fields are invalid; recursive topology uses pointer fields.

## 10. Alternatives

`enum` provides named integer constants. `switch_` lowers to a real C `switch`
whose cases are gotos — GCC turns a dense table into an indirect jump:

```lua
local Opcode = enum { add = 0, sub = 1, halt = 2 }

return switch_(opcode)
    :case_(Opcode.add):then_(do_add)
    :case_(Opcode.sub):then_(do_sub)
    :default(do_halt)
```

`switch_` requires a `default` arm and rejects duplicate keys. A `union` is a C
union constructed by naming one active member (`Value { floating = x }`);
member reads reinterpret the storage. Immediate semantic alternatives remain
continuations.

## 11. Storage and linkage

`global(T, init)` emits file-scope `static` storage with a Lua-built
initializer (number, string literal, or table of numbers) and is an lvalue for
`load`/`store`/`at`. `cstring("...")` is a static NUL-terminated byte array
usable as `ptr(u8)`. Lua constructs all static data.

## 12. Fused pipelines

Streams describe scalar point computation and materialize one ordinary C loop:

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

`load`, `zip`, and `map` allocate nothing; `store` and `reduce` materialize the
loop. GCC `-O3` owns vectorization, unrolling, and optimization. `reduce`
accepts the `add` and `mul` reducers with an init value.

## 13. Interactive TCC cooking

`C.jit(build, options)` returns the ordinary namespace immediately; the first
call to an exported function cooks the complete module with libtcc in memory
and caches the FFI pointers:

```lua
local math = assert(C.jit(function()
    local add = func
        (param: a (i32), param: b (i32))
        (i32)
        (function(p) return p.a + p.b end)
    return { add = add }
end))

assert(math.add(20, 22) == 42) -- cooks module, resolves and calls add
math:free()
```

- Whole-module cook keeps ordinary calls among generated functions coherent;
  later invocations reuse the TCC state and cached pointers.
- A direct function returns its C result (or nothing for void). A sealed
  multi-exit region uses declaration-order integer ordinals internally, while
  the Lua host API returns the selected exit name and its carried value:

  ```lua
  local exit, quotient = math.checked_div(84, 2)
  assert(exit == "divided")
  ```

- Exported struct types construct matching LuaJIT FFI values, so by-value
  struct parameters and results keep their C ABI shape.
- Host externs are supplied as stable FFI pointers:
  `C.jit(build, { symbols = { host_mul = host_mul } })`.
- Function pointers become invalid after `module:free()`.
- TCC prioritizes compilation latency (≈1 ms cooks), not `-O3` optimization;
  the same emitted C remains available through `C.compile` for optimized GCC
  execution and AOT artifacts. See `TCC_VS_LUAJIT.md` for the numbers.

## 14. Compilation and errors

`C.compile(build)` runs staging, checking, lowering, and codegen and returns
`(source, lowered, program)` or `(nil, errors)` — a list of check diagnostics
with the owning function named (`in run: ...`). Staging misuse raises Lua
errors with the same messages. The same source text feeds both the GCC/AOT path
and the TCC memory cook, so the two paths never diverge.

```text
CBlock → C text → TCC memory cooking → callable symbol
              └→ GCC/AOT compilation → ordinary artifact
```

CBlock does not add a vector IR, optimizer IR, scheduler, GC, exception
runtime, class system, or second module language.
