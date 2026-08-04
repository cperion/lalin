# Lalin Language Reference

Lalin is the compiled language member of the LLBL workbench. Lua is the
metaprogramming layer; Lalin receives monomorphic programs, lowers them through
typed ASDL facts into the semantic `emit_c` C backend, and uses that emitted C as
both the main GCC-backed JIT-like execution path and the AOT artifact path.
Native C-stencil copy-patch is retired and deleted; only the stencil/CMat
vocabulary survives as the deterministic emitted-C shape contract. LuaJIT
bytecode emission is removed: the compiled artifact is always emitted C, cooked
with GCC for local execution or handed to a user-owned AOT build.

This reference treats the parsed syntax as the standard source surface. The
Lua/LLBL DSL is documented in one chapter near the end because it is still the
best surface for macros, generators, and advanced producer heads.

---

## Model

Lalin is not a generic source language in the C++ or Rust sense. Genericity lives
in Lua and LLBL composition. By the time a Lalin function is compiled, the types
and generated code are concrete.

The pipeline is:

```text
.lln declaration document (root role Lalin.decls)
  -> lalin.loader
  -> lalin.syntax.document
  -> lalin.syntax parsed AST
  -> LalinTree ASDL
  -> typecheck
  -> LalinCode facts
  -> flow/value/memory/effect/kernel/schedule facts
  -> CBackendUnit
  -> emit_c C output
  -> GCC shared-object cook + dlopen for JIT-like execution
     or user-owned AOT C build
```

Important rules:

- LLBL is the workbench; Lalin is the compiled language member.
- Lua owns genericity.
- Lalin receives monomorphic values.
- Types are Lua values.
- Typed binders use `name[lua_type]` or `name [lua_type]`; the bracket
  expression must evaluate to a Lalin type value.
- Type constructors are Lua values too. Use `ptr [i32]`, `array [i32] [4]`,
  `view [i32]`, and similar constructor calls inside the outer type escape.
- Lalin's object model is struct-owned protocols: plain structs are structural
  values, `unique` structs are identity-bearing semantic entities, and functions,
  regions, and handles attach with qualified names (`fn Struct.method`,
  `region Struct.open`, `handle Struct.Ref`).
- Every block path terminates.
- Region protocols are explicit named exits.
- `emit` and `call` are different operations: `emit` is an open CFG splice;
  `call` is a sealed region invocation with a real call/frame boundary and a
  generated result protocol.
- Region and continuation dataflow is explicit. Blocks do not capture hidden
  lexical state; wire target applications such as `done = next(tok, code)` pass
  the values that the target block receives.
- Fast region lowering is represented as ASDL facts such as region protocols,
  region seals, and region bundles. The language does not rely on C sugar and
  later compiler luck to recover the intended machine shape.
- Memory identity and access are explicit: handles are durable names, leases are
  temporary access facts, and owned values are exactly-once obligations.
- Backend facts are explicit ASDL facts.

---

## Loading `.lln` Source

The official source extension is `.lln`. A `.lln` file is a Lalin declaration
**document** rooted at the `Lalin.decls` role. It is not a Lua chunk and it does
not execute top-level Lua statements.

Root document items are:

- Lalin declarations: `fn`, `extern`, `struct`, `union`, `handle`, and `region`
- top-level type meta-property assignments such as `Type.metamethods.__getdecls = generator`
- top-level `[lua_expr]` HostEval splices that produce declarations or ordered
  declaration arrays

Top-level Lua chunk forms such as `local`, `return`, `module`, and parse-time
`import` are rejected by the document loader.

```lln
struct Point
  x [i32]
  y [i32]
end

fn Point.norm(self [ptr [Point]]) [i32]
  return self.x + self.y
end

fn add(a [i32], b [i32]) [i32]
  return a + b
end
```

Load a document directly from Lua:

```lua
local lalin = require("lalin")

local decls, doc = assert(lalin.loadfile("demo.lln"))
local session = lalin.compile_c_gcc("demo", decls, {
  gcc_opts = { opt = 3, out_dir = "target/demo" },
})
```

`lalin.loadstring` and `lalin.loadfile` return the ordered declaration array and
a `DeclDocument` metadata value. `lalin.dofile` returns the declaration array. A
`.lln` document does not return an arbitrary Lua API table.

Install the `.lln` package searcher to let Lua `require` discover declaration
documents:

```lua
local lalin = require("lalin")
lalin.path = "./?.lln;./?/init.lln"
lalin.install_searcher()

local decls = require("demo") -- declaration array
```

Lua builder/metaprogramming code remains in `.lua` and under `lalin.dsl`. Use
ordinary Lua modules to build constants, fragments, and generated declarations,
then pass them through `opts.env` or through HostEval brackets.

The lower-level `llbl.syntax` mixed-source driver remains infrastructure for
Lua-hosted syntax islands and tooling, not the standard `.lln` loading surface.

---

## Parsed Metaprogramming

LLBL metaprogramming is not string substitution. In a `.lln` document,
`[lua_expr]` is an LLBL HostEval value: it records the Lua source, captured
references, bracket origin, and the expected role supplied by the surrounding
parser. The document loader evaluates HostEval forms against the document host
environment and adapts the produced value through the current Lalin role.

The core rule is:

```text
Lua builds host values.
.lln documents offer those values to roles through HostEval brackets.
The Lalin dialect gives those values typed/backend meaning.
```

### Type Meta-Properties

Lalin follows the useful part of Terra exotypes without adding a second kind of
source declaration. A parsed type declaration is already the meta-object owner:

```text
struct / union / handle declaration = first-class type value + meta-properties
```

After a declaration is materialized, the type name is available to later
HostEval brackets and to top-level declaration-time meta assignments:

```lln
struct Student
  score [i32]
end

Student.metamethods.__methodmissing = record_setters

fn use(s [ptr [Student]]) [void]
  s:setscore(99)
  return
end
```

The assignment above is not a runtime statement. It mutates the host-side
`Student` type value while the declaration document is materialized, just like a
Lua/Terra meta-object assignment. A simple right-hand side name is resolved in
the document host environment. Use `[lua_expr]` only when the value is an
expression rather than a simple name:

```lln
Student.metamethods.__methodmissing = [make_record_setters("set")]
```

The standard property table is `T.metamethods`. Important hooks include:

```lua
T.metamethods.__typename(T)              -- diagnostic/generated name
T.metamethods.__getentries(T)            -- generated fields for host-built type families
T.metamethods.__getdecls(T)              -- generated declaration family
T.metamethods.__getmethod(T, name)       -- explicit staged method lookup
T.metamethods.__methodmissing(T, name)   -- staged missing-method synthesis
T.metamethods.__entrymissing(T, name)    -- staged field/lens synthesis
T.metamethods.__apply(T, ...)            -- staged callable-object behavior
T.metamethods.__cast(T, from, to, expr)  -- staged conversion behavior
```

A hook returns ordinary Lalin artifacts: declarations, fragments, ASDL values, or
a diagnostic/error. `__getdecls` returns a declaration family. `__methodmissing`
commonly returns a qualified function declaration such as
`fn Student.setscore(...) ... end`. The generated artifact is then lowered
normally. The compiled program never keeps a dynamic "method-missing" branch.

The boundary rule is strict:

```text
type meta-property query = staged synthesis
compiled Lalin method call = static call/region/protocol artifact
```

### Document Host Environment

The loader supplies the standard Lalin host environment (`i32`, `ptr`, `array`,
`named`, and related type/building values). Callers may add values with
`opts.env`:

```lua
local decls = assert(lalin.loadstring([[
fn scaled(x [i32]) [i32]
  return x * [scale]
end
]], "@scaled.lln", {
  env = { scale = 4 },
}))
```

Declarations bind by name as the document materializes. A declaration can be
used by later HostEval brackets in the same document:

```lln
struct Pair
  x [i32]
end

fn accept(p [Pair]) [void]
  return
end
```

Top-level `[generated]` evaluates under the declaration-stream role and splices
ordered declarations into the document:

```lln
[generated_decls]

fn use_generated(x [Generated]) [void]
  return
end
```

Here `generated_decls` is supplied by Lua, for example through
`lalin.loadstring(source, name, { env = { generated_decls = decls } })`.

### Role-Directed HostEval Brackets

The bracket itself does not mean "type" or "expression". The surrounding role
means that.

In expression position, `[lua_expr]` adapts primitive literals, parsed expression
fragments, parsed expression AST values, or already-constructed LalinTree
expression values:

```lln
fn scale_one(x [i32]) [i32]
  return [scaled_expr]
end
```

In statement-list position, `[lua_expr]` can splice statement fragments,
statement AST values, arrays of statements, or already-constructed LalinTree
statements:

```lln
fn scale(dst [ptr [i32]], src [ptr [i32]], n [index]) [void]
  requires bounds(dst)(n), writeonly(dst), bounds(src)(n), readonly(src)
  requires disjoint(dst)(src)
  loop i in 0 .. n do
    [scale_step]
  end
end
```

In type position, `[lua_expr]` adapts under the `type` role. The Lua expression
may evaluate to a Lalin type value or to a named declaration value:

```lln
[i32]
[ptr [i32]]
[array [i32] [4]]
[Pair]         -- after `struct Pair ... end` in the same document
[named("Pair")] -- dynamic/metaprogrammed fallback when only the name string is available
```

In product/field-list positions, `[lua_expr]` adapts under the product role and
can splice generated fields:

```lln
struct Packet
  [header_fields]
  payload [ptr [u8]]
end
```

At declaration-stream boundaries, `[lua_expr]` adapts under the `decls` role.
The value may be one declaration, a positional array of declarations, or a
role-compatible declaration fragment. Positional order is preserved.

Parsed expression indexing is a hard boundary:

```lln
a[x]          -- parsed Lalin index expression
[make()][i]   -- HostEval expression, then parsed index postfix
[ptr [Pair]]  -- one HostEval; the inner brackets are Lua source
```

### Fragments

Expression and statement fragments are host values produced by Lua/mixed-source
builder code, not top-level `.lln` statements. A document consumes them through
role-directed brackets:

```lln
fn use_fragment(x [i32]) [i32]
  [prologue]
  return [rhs]
end
```

This is the parsed-channel analogue of LLBL role-tagged fragments in the Lua
DSL: Lua owns generation, while Lalin roles own adaptation and splicing.

### Requiring `.lln` Packages

`.lln` packages compose as declaration documents. After installing the searcher,
Lua `require("pkg")` returns that package's declaration array. Inside another
`.lln` document, use HostEval to splice declarations produced by Lua:

```lln
[require("pkg.generated_decls")]
```

There is no `.lln` source-level `module`, `export`, or `import` declaration.

---

## Lexical Shape

A `.lln` declaration document is a token stream of root entries such as `fn`,
`struct`, `union`, `handle`, `region`, and top-level HostEval declaration
splices.

Names use the usual identifier shape:

```text
letter_or_underscore (letter_or_digit_or_underscore)*
```

Keywords include:

```text
fn struct union handle region
requires ensures
do end if then elseif else
loop in grid tiled window
return jump emit call entry block
let var
true false nil
and or not
as sizeof
```

Comments and general Lua file structure are handled by the `.lln` syntax loader.

---

## Types

Typed binders use role-directed bracket application: `name[type_value]` or
`name [type_value]`. Function results, casts, and `sizeof` use the same
bracketed type role.

The expression inside the brackets is evaluated by Lua and adapts under the
Lalin `type` role. It may produce a Lalin type value or a named declaration
value:

```lln
[i32]
[ptr [i32]]
[array [i32] [4]]
[view [i32]]
[Pair]         -- after `struct Pair ... end` in the same document
[named("Pair")] -- dynamic/metaprogrammed fallback when only the name string is available
```

There is no separate parsed type grammar. `i32` is not a parsed keyword in type
position; it is a Lua value supplied by the `.lln` environment. `ptr [i32]` is a
Lua bracket-call on the `ptr` type constructor. The outer binder brackets are
also Lua-like bracket application, so both `x[i32]` and `x [i32]` are accepted.

### Scalar Types

| Type | Meaning |
|---|---|
| `void` | no value |
| `bool` | boolean value |
| `i8`, `i16`, `i32`, `i64` | signed integers |
| `u8`, `u16`, `u32`, `u64` | unsigned integers |
| `f32`, `f64` | floating point |
| `index` | index/counted-loop integer |

### Compound Types

```lln
[ptr [i32]]
[array [i32] [4]]
[slice [u8]]
[view [f32]]
[MyStruct]
[pkg.SomeType]
```

Any Lua expression is legal between the brackets if it adapts to the `type`
role. For named declarations, `[Pair]` can project a parsed or DSL `struct Pair`
/ `union Pair` declaration to a named type, and handle declarations project to
handle types. You can still use `named("TypeName")` or return/pass type values
from another Lua package when that is clearer.

### Access, Lease, And Ownership Types

The type vocabulary also carries borrow-checking facts:

```lln
[readonly [ptr [Store]]]
[writeonly [ptr [i32]]]
[noalias [ptr [u8]]]
[noescape [ptr [i32]]]
[preserve [ptr [Store]]]
[invalidate [ptr [Store]]]
[lease [ptr [Record]]]
[lease [view [f32]]]
[owned [ResourceRef]]
```

Access wrappers refine how a parameter may be used. `readonly` and `preserve`
are preserving accesses for lease grants; `writeonly`, `invalidate`, and plain
mutable pointer/view parameters are conservative invalidators. `noescape` says a
callee may use an access value but must not retain it.

A `lease` is temporary access, normally produced by a resolver region or trusted
boundary. Its base must be `ptr(T)` or `view(T)`. When a lease is tied to a store
parameter, use an explicit origin in the Lua type expression, for example
`lease("store", ptr [Record])` when `Record` is a type value in scope;
diagnostics print this idea as
`lease(store) ptr(Record)`. Leases may appear in function, region, block, and
continuation parameters, but not in durable positions such as struct fields,
static/const values, union payloads, function results, or generated region-call
result objects.

An `owned T` is linear authority to release, close, retire, or transfer a
resource exactly once. There is no destructor or inferred drop. The base must be
a durable token such as a handle/resource value, not a raw pointer, view, lease,
access wrapper, or another owned value. Owned obligations stay in control flow;
they are not storable data.

### Function Signatures

Functions declare parameter products and a single result type:

```lln
fn distance2(x [f32], y [f32]) [f32]
  return x * x + y * y
end
```

Use `void` for functions that do not return a value:

```lln
fn clear(dst [ptr [i32]], n [index]) [void]
  loop i in 0 .. n do
    dst[i] = 0
  end
end
```

---

## Declarations

### Functions

Functions are declaration values in the document stream. A function with a
qualified name (e.g. `fn Point.norm`) binds to the named struct value in the
document environment, making it available for method dispatch:

```lln
struct Point
  x [i32]
  y [i32]
end

fn Point.norm(self [ptr [Point]]) [i32]
  return self.x + self.y
end

fn use(p [ptr [Point]]) [i32]
  return p:norm()
end
```

Unqualified functions are also valid:

```lln
fn add(a [i32], b [i32]) [i32]
  return a + b
end
```

Parameters are immutable values. Mutable local state is introduced with `var`.

### Externs

Extern declarations name C ABI functions supplied by the host process, emitted C
artifact, or native runtime symbol table:

```lln
extern lua_gettop(L [rawptr]) [i32]
end

extern host_add(x [i32]) [i32]
  symbol = "my_host_add"
end
```

The declaration name is the Lalin value used at call sites and, by default, the
external C symbol to link or resolve. Write a `symbol` fact only when the C
symbol differs from the Lalin declaration name. Externs are the correct substrate
for the Lua C API and other foreign C functions, but ordinary object APIs should
wrap raw externs in qualified functions or regions that state ownership and
control protocols.

### Structs

```lln
struct Pair
  left [i32]
  right [i32]
end
```

Fields are named and typed. Struct field access uses dot syntax:

```lua
p.right
```

A plain struct is a structural value. Its fields are the value. Use plain
structs for coordinates, ranges, layout descriptors, small records, and other
facts where copying the same fields really means copying the same value.

### Object Model: Structs Own Protocols

Lalin's object model is not class inheritance, hidden vtables, or dynamic method
lookup. The object model is:

```text
struct/unique struct identity
+ qualified functions as methods
+ qualified regions as access/control protocols
+ qualified handles as durable references
```

The struct is the protocol owner. A declaration qualified by a struct name is
attached to that struct's vocabulary:

```lln
struct Connection
  fd [i32]
  state [u32]
end

fn Connection.read(self [ptr [Connection]], buf [ptr [u8]], len [index]) [index]
  return 0
end

-- Lua-style method declaration sugar injects `self [ptr [Connection]]`.
fn Connection:status() [u32]
  return self.state
end

region Connection.open(addr [slice [u8]];
  connected(conn [ptr [Connection]]),
  refused,
  timeout
)
  entry start()
    jump refused
  end
end

handle Connection.Ref [u32]
  invalid = 0
  domain [Connection]
  target [Connection]
end
```

This is the Lalin equivalent of the compiler's ASDL + methods pattern. The
struct names the semantic thing; qualified functions and regions name the
operations and protocols owned by that thing. There is no handler table, no
string action selector, and no compatibility dispatch layer.

This is Lalin's definition of object-oriented programming: an object packages
both the data type and the typed control-flow protocols over that data. Classic
OOP missed this by separating data from behavior while still leaving functions
as single-exit calls. Because ordinary functions have only one return edge,
protocol-rich behavior spills control back into data: `Result` objects, tagged
unions, status codes, callbacks, visitors, and follow-up dispatch functions.
That creates artificial types for ceremony, causes type explosion, and adds
runtime call/branch overhead. In Lalin, the region belongs to the object, so
control alternatives stay typed as continuations instead of being boxed into a
return value.

#### Example: avoid result-object protocols

A conventional design usually turns a multi-outcome parser step into data:

```text
ParserNextResult = Token(tok) | Eof | Syntax(pos, code)
Parser.next(...) -> ParserNextResult
consumer switches on ParserNextResult and dispatches again
```

That shape invents a result type solely because the function has one return
edge. The protocol is really control, not data. In Lalin the parser object owns
that control protocol directly:

```lln
struct Parser
  source [slice [u8]]
  pos [index]
end

region Parser.next(self [ptr [Parser]];
  token(tok [Token]),
  eof,
  syntax(pos [index], code [i32])
)
  entry start()
    -- inspect self.source/self.pos and jump to exactly one protocol exit
    jump eof
  end
end

region ParserDriver.step(self [ptr [ParserDriver]], p [ptr [Parser]];
  ok,
  failed(pos [index], code [i32])
)
  entry start()
    emit Parser.next(p;
      token = got_token,
      eof = done,
      syntax = bad_syntax
    )
  end

  block got_token(tok [Token])
    -- token path is statically typed; no Result switch is needed
    jump ok
  end

  block done()
    jump ok
  end

  block bad_syntax(pos [index], code [i32])
    jump failed(pos, code)
  end
end
```

The object owns the bytes/state (`Parser`) and the protocol over that state
(`Parser.next`). The consumer wires continuations instead of unpacking a boxed
result and calling a dispatcher. This example uses `emit`, so `Parser.next` is
spliced into the driver's CFG. Use `call` at the same surface site when the
protocol should be sealed behind a real region call/frame boundary.

A useful default is **one object per machine**. If a subsystem has retained
state, repeated execution, diagnostics, cache identity, ownership authority, or
named outcomes, model it as a struct or `unique` struct and attach its operations
there:

```lln
struct Parser
  unique
  source [slice [u8]]
  pos [index]
end

region Parser.next(self [ptr [Parser]];
  token(tok [Token]),
  eof,
  syntax(pos [index], code [i32])
)
  entry start()
    jump eof
  end
end
```

The object is the machine; fields are its persistent state or world reference;
qualified functions are ordinary operations; qualified regions are protocol
operations. A colon declaration is sugar for the ordinary qualified form with an
implicit pointer receiver:

```lln
fn Parser:reset() [void]
  return
end

-- means:
fn Parser.reset(self [ptr [Parser]]) [void]
  return
end
```

Use the explicit dot form when the receiver needs a more precise access or
ownership type than `ptr [Parser]`.

The Lua/LLBL host layer may also synthesize struct-owned protocols by assigning
meta-properties on the type value:

```lln
Parser.metamethods.__methodmissing = parser_method_generator
```

That mechanism creates explicit Lalin declarations or fragments during staging;
it does not add dynamic method lookup to compiled Lalin. It is how reusable
object families replace templates without reintroducing runtime dispatch.

#### Example: staged boilerplate eating

The ownership/handle style naturally creates repeated names: `Ref`, `borrow`,
`stale`, `missing`, `invalidate`, `capacity`, `compact`, serializers, and debug
views. Do not hide those facts at runtime; synthesize the repetitive declarations
at staging time:

```lln
struct BufferStore
  slots [ptr [BufferSlot]]
  capacity [index]
  epoch [u32]
end

BufferStore.metamethods.__methodmissing = store_method_boilerplate

fn use_store(s [ptr [BufferStore]]) [index]
  -- If not already explicit, this call asks BufferStore's meta-property hook to
  -- synthesize an ordinary `fn BufferStore.capacity_left(...) [index]`.
  return s:capacity_left()
end
```

The hook lives in Lua, but its product is not dynamic Lua behavior. It returns
ordinary Lalin declarations/fragments. After materialization the module contains
explicit `fn BufferStore.capacity_left`, explicit region/handle declarations if
the family generated them, and no runtime method-missing branch.

### Unique Structs And Semantic Identity

Some structs are not mere field-wise values. A declaration, symbol, scope, AST
node, type variable, inference hole, store record, or user-authored type-system
entity needs identity. Two type variables with the same fields are still two
different type variables. A named declaration is not interchangeable with
another declaration just because its current fields match.

Those entities are modeled as `unique` structs:

```lln
struct TypeVar
  unique
  level [u32]
  solution [ptr [Type]]
end

struct TypeDecl
  unique
  name [ptr [Name]]
  fields [ptr [FieldList]]
end
```

A `unique` struct is identity-bearing. Allocation/construction gives the object
an identity separate from its fields. Facts can attach to that identity through
fields or through typed phase projections, instead of living in side tables keyed
by raw nodes or names.

Use the rule:

```text
plain struct  = value, compared/copied by its fields
unique struct = entity/object, identified by its allocation or canonical handle
```

Examples:

```text
Position, SourceRange, LayoutSize     -> plain structs
Scope, Symbol, TypeDecl, TypeVar      -> unique structs
ExprCall AST node, TypedExpr result   -> unique structs
Builtin type descriptors              -> interned/canonical unique structs
```

`unique` is also the surface counterpart of ASDL `unique`/`interned`: ASDL uses
identity-bearing products so compiler facts have stable owners; Lalin exposes
the same design to user code so users can author their own safe semantic systems
and type systems with typed entities plus owned methods.

Current implementation note: qualified struct protocols (`fn Struct.method`,
`region Struct.name`, `handle Struct.Ref`) are implemented in the parsed
surface. The `unique` marker is the documented identity model for struct-owned
semantic entities; implementations that do not yet lower the marker directly
should represent durable identity with qualified handles and explicit stores
rather than side tables.

### Unions

```lln
union OptionI32
  Some(value [i32])
  None
end
```

Variants may have any number of named payload fields or no payload. Construct a
variant by qualifying it with its union type using `.`:

```lln
let some [OptionI32] = OptionI32.Some(42)
let none [OptionI32] = OptionI32.None()
```

A variant arm binds every payload field in declaration order:

```lln
union PairResult
  Pair(left [i32], right [i32])
  Empty
end

switch result do
  case variant Pair(left, right) then
    return left + right
  case variant Empty then
    return 0
  default then
    return -1
end
```

Union payloads are durable stored data, so they cannot contain leases or owned
obligations.

### Struct Protocols — Methods, Regions, Handles

Structs are not just data bags. They own their protocol vocabulary: functions,
regions, and handles declared with a qualified name are attached to the struct
value in the document environment.

```lln
struct Connection
  fd [i32]
end

-- Method
fn Connection.read(self [ptr [Connection]], buf [ptr [u8]], len [index]) [index]
  return 0
end

-- Resolver region with named continuations
region Connection.open(addr [slice [u8]];
  connected(conn [ptr [Connection]]),
  refused,
  timeout
)
  entry dial()
    jump connected(conn = [null])
  end
end

-- Handle scoped to this struct's store
handle Connection.Ref [u32]
  invalid = 0
  domain [Connection]
  target [Connection]
end
```

All qualified declarations bind to the struct value: `env.Connection.read`,
`env.Connection.open`, `env.Connection.Ref`. The unqualified names are also in
scope, so method dispatch works naturally:

```lln
fn handle(conn [ptr [Connection]]) [void]
  let n [index] = conn:read(buf, 1024)
end
```

#### Method Call Syntax

`obj:method(a, b)` preserves method-call intent during document materialization
so type meta-properties can synthesize a missing static method when needed. It
then lowers to an ordinary static call with the receiver inserted as the first
argument. Chaining works naturally:

```lln
p:norm()           -- lowers to norm(p)
p:helper(a, b)     -- lowers to helper(p, a, b)
p:norm():other()   -- lowers to other(norm(p))
p:clear()          -- lowers to clear(p)
```

Methods have no special runtime behavior or vtable dispatch. The only extra
step is staging-time method synthesis from the receiver's type value; the
compiled artifact contains ordinary static calls.

#### Qualified Declaration Names

Any declaration (`fn`, `region`, `handle`) can use a qualified name to attach
itself to a previously declared struct (or other declaration) value:

```lln
fn Point.norm(self [ptr [Point]]) [i32]       -- Point.norm   bound to Point
region Store.borrow(store [ptr [Store]], buf [Handle]; ...) end
handle Store.Ref [u32] invalid 0 end          -- Store.Ref    bound to Store
```

Deep qualification is supported:

```lln
fn Wrapper.Point.norm(self [ptr [Point]]) [i32]
  return 0
end
```

This pattern makes structs the API boundary: declare the product, then attach
what you can do with it.

### Handles

A handle is a nominal durable identity value. It may be copied, stored, compared
with the same handle type, passed, and returned. It is not dereferenceable, not
indexable, and not implicitly convertible to its integer representation.

Handle declarations are available in parsed `.lln` syntax, either standalone or
qualified to a struct:

```lln
struct AudioBufferStore
  capacity [index]
end

struct AudioBufferRecord
  first [index]
end

handle AudioBuffer [u32]
  invalid = 0
  domain [AudioBufferStore]
  target [AudioBufferRecord]
end

-- Qualified: AudioBufferStore owns the handle
handle AudioBufferStore.Ref [u32]
  invalid = 0
  target [AudioBufferRecord]
end
```

The same declaration can be generated from the Lua/LLBL DSL:

```lua
local AudioBuffer = lln.handle. AudioBuffer {
  invalid = 0,
  domain = "AudioBufferStore",
  target = "AudioBufferRecord",
}
```

The representation defaults to `u32`; a DSL declaration may choose another
scalar representation with `repr`. `domain` names the store/namespace that can
validate the handle. `target` names the logical product that a successful
resolver may grant as a lease. These are type facts, not comments, and they do
not create implicit dereference.

Trusted store code can cross the representation boundary with explicit
`repr(handle)` / `Handle.from_repr(raw)` operations. Ordinary safe casts do not
convert handles to or from scalars.

### Documents And Values

Lalin does not add a user-facing module declaration. A `.lln` file is an ordered
declaration document, and loading it returns the document's declaration array.
Runtime Lua APIs, tables, and macros live in `.lua` builder modules; pass their
results into documents through `opts.env` or HostEval brackets.

```lln
fn add(a [i32], b [i32]) [i32]
  return a + b
end
```

### Lua C API Boundary

The Lua runtime is reachable through the same extern mechanism used for other C
functions. The Lua C API is C, so calls such as `lua_gettop`, `lua_settop`,
`lua_pcall`, `luaL_ref`, and `luaL_unref` should be modeled as ordinary extern
symbols at the low level.

That raw layer is only the substrate. The object API belongs on top:

```text
raw externs        -> exact Lua C ABI calls
LuaState object    -> owns lua_State* authority and stack discipline
LuaRef handle      -> durable registry reference
LuaBridge regions  -> protected calls, stack restoration, typed error exits
```

The reason is the same as store objects. A stack index is temporary access, a
registry integer is a durable handle only when owned by the registry protocol,
and a Lua status code is a control exit trying to masquerade as data. Ordinary
Lalin code should consume object-owned bridge protocols, not scatter raw Lua C
API calls.

A bridge module declares the raw Lua C API entry points as parsed externs:

```lln
extern lua_gettop(L [rawptr]) [i32]
end

extern lua_pcall(L [rawptr], nargs [i32], nresults [i32], errfunc [i32]) [i32]
end
```

Then a Lalin-facing object wraps those externs with typed regions:

```lln
struct LuaState
  L [rawptr]
end

handle LuaState.Ref [u32]
  invalid = 0
  domain [LuaState]
end

region LuaState.pcall(self [ptr [LuaState]], nargs [i32], nresults [i32];
  ok,
  error(status [i32])
)
  entry start()
    -- bridge-private implementation calls raw lua_pcall extern and jumps ok/error
    jump error(status)
  end
end
```

The extern call gets you access. The object protocol makes that access safe,
composable, and checkable.

---

## Statements

Statement blocks end at `end`, `elseif`, `else`, `case`, or `default` depending on context.

### `requires`

`requires` records semantic facts for typechecking and backend planning:

```lln
requires bounds(dst)(n), bounds(src)(n), disjoint(dst)(src)
requires readonly(src), writeonly(dst)
```

Contracts are not comments. They feed memory classification, non-trapping
proofs, alias proofs, kernel planning, and stencil selection.

### `let`

`let` introduces an immutable local binding:

```lln
let x [i32] = 1
let y [i32] = x + 2
```

If an initializer is omitted, the current conversion supplies a zero literal.
Prefer writing the initializer explicitly.

### `var`

`var` introduces mutable local storage:

```lln
var acc [i32] = 0
acc = acc + 1
```

Assignments require a place on the left-hand side.

### Assignment

```lua
x = x + 1
dst[i] = src[i]
record.field = value
```

Index and field assignment are place operations, not function calls.

### Return

```lua
return
return x
return a + b
```

Current function lowering expects a single returned value or no value.

### If / Elseif / Else

```lua
if x < lo then
  return lo
elseif x > hi then
  return hi
else
  return x
end
```

Conditions are expressions. Every path in a function body still has to
terminate.

### Switch

`switch` is scalar control dispatch over an integer/bool-like expression. It
lowers to ASDL `StmtSwitch`, then to `CodeTermSwitch`, then to a C `switch`/goto
CFG. On GCC this may become a jump table when the case density is suitable.

```lln
switch instr.op do
case [OP.ADD] then
  jump add(a = instr.a, b = instr.b, c = instr.c, next_pc = pc + 1)
case [OP.RETURN] then
  jump ret(a = instr.a)
default then
  jump bad(op = instr.op, pc = pc)
end
```

Case keys may be integer literals, boolean literals, or host constants that
evaluate to integer/bool literals, such as `[OP.ADD]`. Each `case` and the
`default` body is an ordinary statement block. Inside a region, jumps in switch
arms can target local blocks or declared continuation exits and are retargeted
with the same rules as jumps in `if` arms.

`switch` is a source spelling for an explicit scalar dispatch fact; it is not a
replacement for region protocols. If the alternatives are semantic outcomes of
an operation, prefer a region with named continuations. Use `switch` when the
input is already an encoded scalar fact, such as a bytecode opcode owned by one
consumer region.

### Loops

The parsed source loop is a finite analyzable domain loop. It is not a general
imperative `for`/`while` construct. In Lalin source, `loop` means:

> iterate over a statically described domain and produce explicit loop facts for
> the compiler.

Use `loop` for data movement, maps, reductions, scans, and other stencil-shaped
work. Use regions for explicit control protocols, state-machine-like flow, and
non-loop control transfers.

This is an intentional mental model difference from Lua, C, or Python. A source
loop is not where arbitrary code goes. A loop body must remain admissible as
domain work: stores, fold/scan sinks, pure scalar/index computation, simple
predicates, and analyzable memory indexing.

```lln
loop i in 0 .. n do
  dst[i] = src[i]
end
```

With an explicit step:

```lln
loop i in 0 .. n .. 2 do
  dst[i] = 0
end
```

The 1D range form lowers through a control-region representation, but that is an
implementation detail. Semantically, source `loop` is a domain loop. If the
compiler cannot form a valid producer/sink model, it should reject the loop with
a loop diagnostic rather than treating it as arbitrary imperative control.

Loops can carry a reducer or inclusive scan sink. A reducing loop places one
`fold` statement directly in the loop body; the fold accumulator type is the
reduction result type:

```lln
fn dot(lhs [ptr [i32]], rhs [ptr [i32]], n [index]) [i32]
  requires bounds(lhs)(n), readonly(lhs), bounds(rhs)(n), readonly(rhs)
  loop i in 0 .. n do
    fold acc [i32] = 0 by add step lhs[i] * rhs[i]
  end
end
```

A scan loop writes each inclusive accumulator value into a destination:

```lln
fn prefix_sum(dst [ptr [i32]], xs [ptr [i32]], n [index]) [void]
  requires bounds(dst)(n), writeonly(dst), bounds(xs)(n), readonly(xs)
  requires disjoint(dst)(xs)
  loop i in 0 .. n do
    scan acc [i32] = 0 by add step xs[i] into dst[i]
  end
end
```

`fold` and `scan` accept one reducer name: `add`, `mul`, `band`, `bor`,
`bxor`, `min`, or `max`. A loop may contain at most one sink.

Parsed loops also support multi-axis producers. The loop index list must match
the producer axis count:

```lln
loop i, j in grid(0 .. h, 0 .. w) do
  dst[i * w + j] = src[i * w + j]
end
```

Tiled producers add tile metadata:

```lln
loop i, j in tiled grid(0 .. h, 0 .. w) by 2, 2 do
  scan acc [i32] = 0 by add over j step xs[i * w + j] into dst[i * w + j]
end
```

Window producers add neighbor metadata:

```lln
loop i in window(0 .. n, before = 1, after = 1, boundary = clamp) do
  dst[i] = xs[i - 1]
end
```

A window is a language domain, not a backend contract. The producer declaration owns
the iteration range, order, step, neighborhood extent, and boundary policy. Each
indexed expression contributes its exact displacement, and ordinary function
contracts provide the logical memory extent:

```lln
fn previous(dst [ptr [i32]], xs [ptr [i32]], n [index]) [void] do
  requires bounds(dst)(n), writeonly(dst)
  requires bounds(xs)(n), readonly(xs), disjoint(dst)(xs)
  loop i in window(0 .. n, before = 1, after = 1, boundary = clamp) do
    dst[i] = xs[i - 1]
  end
end
```

Do not repeat this information in a `window_footprint` assertion; that contract does
not exist. `clamp`, `wrap`, and `zero` are total boundary operations. The compiler
preserves a dynamic boundary realization whenever it cannot establish an interior
access. `reject` requires compiler-derived coverage for every displaced use. The
current implementation accepts centered reject-boundary uses; a nonzero displacement
is a compile-time rejection until the narrow affine coverage recognizer can establish
an interior domain. It is never emitted as an unchecked load.

ND scans must specify `over`; the value may be an axis number or axis name.

Allowed loop body forms are intentionally narrow:

- stores to an analyzable destination
- one `fold` sink, or one `scan` sink
- `let` bindings for pure scalar/index expressions
- simple `if` predicates whose branches remain admissible loop bodies
- arithmetic, comparison, boolean logic, casts, and indexing

Rejected loop body forms include:

- arbitrary calls unless a later pass marks them pure/inlinable
- `region`, `jump`, `emit`, or `call`
- host escapes after parsing
- unknown side effects
- nested loops for now
- mutation not expressible as the loop sink/store

### Jump

`jump` transfers control to a region block or continuation exit:

```lua
jump loop(i = i + 1)
jump done(result = acc)
```

Payload entries may be named:

```lua
jump done(result = x)
```

or positional:

```lua
jump done(x)
```

---

## Expressions

### Literals

```lln
0
42
3.14
true
false
"hello"
nil
```

Integer and float literal typing is resolved during typechecking and lowering.
Integer literals can adopt an expected integer type. Float literals can adopt an
expected `f32` or `f64` type. `nil` can adopt an expected pointer type.

String literals are byte slices:

```lln
let bytes [slice [u8]] = "A\n"
return as [i32](bytes[0])
```

The compiler stores the decoded Lua string bytes in module data and produces a
`slice [u8]`. The slice length is the number of string bytes; backend storage may
include a trailing NUL for C/LuaJIT interop, but that byte is not part of the
slice length.

Brace literals are contextual, but named structs are also their own explicit
constructors:

```lln
let xs [array [i32] [3]] = { 10, 20, 12 }
let pair [Pair] = Pair { left = 20, right = 22 }
```

Positional braces lower to array literals. Named bare braces lower to contextual
struct aggregate literals when the expected type is already known. The preferred
object-style form is `StructName { field = value }`: the struct name supplies
the aggregate type directly, matching the rule that structs own their product
constructor. A single brace literal cannot mix positional and named fields.
Empty `{}` is accepted only where the expected type makes the aggregate meaning
unambiguous.

### Names

```lua
x
dst
some_binding
```

Names resolve through the active binding environment.

### Arithmetic

```lua
a + b
a - b
a * b
a / b
a // b
a % b
-a
```

`//` is parsed as integer division. Backend support depends on the typed
operation selected during lowering.

### Bit Operations

```lua
a & b
a | b
a ~ b
a << b
a >> b
```

Unary `&x` and `*p` are parsed as address and dereference operators:

```lua
&x
*p
```

### Comparisons

```lua
a == b
a ~= b
a < b
a <= b
a > b
a >= b
```

Comparisons lower to typed compare expressions.

### Boolean Logic

```lua
a and b
a or b
not a
```

### Calls

```lua
f(a, b)
bounds(xs)(n)
```

Calls are ordinary expression calls. Contract helpers such as `bounds` and
`disjoint` are represented this way in parsed syntax before semantic conversion.

### Indexing

```lua
xs[i]
matrix[i * width + j]
```

Index expressions can appear in value position or place position.

### Field Access

```lua
pair.left
pair.right
```

Field access can also appear in place position:

```lua
pair.right = 42
```

### Cast

```lln
as [i32](x)
as [f64](count)
```

The parsed conversion currently emits a surface cast; typechecking/lowering
selects the concrete machine cast.

### Sizeof

```lln
sizeof [Pair]
sizeof [i32]
```

`sizeof` produces a size expression for the target type.

### Host Escape

Host escapes splice Lua values from the document host environment into parsed syntax:

```lln
fn copy_scale(dst [ptr [i32]], src [ptr [i32]], n [index]) [void]
  loop i in 0 .. n do
    dst[i] = src[i] * [scale]
  end
end
```

The expression inside `[...]` is evaluated in the document host environment
(default Lalin values plus caller-supplied `opts.env`). In expression position, primitive Lua values become Lalin
literals and expression fragments/ASDL expressions are spliced directly.

---

## Regions

Regions are explicit control protocols. They can be standalone or qualified to
a struct, making the struct own its access and control vocabulary.

A region is not an expression returning a result object. It is a typed control
machine with named exits. Each exit is a continuation with its own payload
schema, and every path in the region must terminate by jumping to a local block
or to one of those continuation exits.

**Shape:**

```lln
region name(inputs; exits)
  entry start(...)
    ...
  end

  block next(...)
    ...
  end
end
```

**Standalone region:**

```lln
region clamp(x [i32], lo [i32], hi [i32]; done(result [i32]))
  entry start()
    if x < lo then jump done(result = lo) end
    if x > hi then jump done(result = hi) end
    jump done(result = x)
  end
end
```

**Qualified region on a struct:**

```lln
struct Connection
  fd [i32]
end

region Connection.open(addr [slice [u8]];
  connected(conn [ptr [Connection]]),
  refused,
  timeout
)
  entry dial()
    jump connected(conn = [null])
  end
end

region Connection.close(self [ptr [Connection]];
  closed,
  error(code [i32])
)
  entry shutdown()
    jump closed
  end
end
```

A colon declaration injects `self [ptr [Struct]]`, like colon functions:

```lln
region Connection:poll(;
  ready,
  closed,
  error(code [i32])
)
  entry start()
    jump ready
  end
end

-- means a region named Connection.poll whose first input is:
-- self [ptr [Connection]]
```

Use the explicit dot form when the receiver must have a more precise access,
lease, handle, or ownership type than `ptr [Struct]`.

### Continuation exits and payloads

Continuation exits accept named payloads:

```lln
connected(conn [ptr [Connection]])    -- named payload field
done(result [i32])                     -- named payload field
refused                                -- nullary exit
timeout                                -- nullary exit
```

Payload fields may be named or anonymous:

```lln
done(result [i32])
done([i32])
```

Named payloads are preferred. They make protocol edges self-documenting and
support the same shorthand used by calls and wire target applications.

### Local blocks and `jump`

`entry` and `block` declarations introduce region-local control labels. Their
parameters are explicit block inputs, not captured variables:

```lln
entry start()
  jump loop(i = 0, acc = 0)
end

block loop(i [i32], acc [i32])
  if i == 10 then jump done(result = acc) end
  jump loop(i = i + 1, acc = acc + i)
end
```

`jump` transfers control inside a region to a local block or to a continuation
exit:

```lln
jump connected(conn)       -- shorthand for conn = conn
jump failed(pos, code)     -- shorthand for pos = pos, code = code
jump done(result = x)      -- explicit named payload
jump done(x)               -- positional payload for anonymous fields
```

In any named payload context, a bare identifier means `name = name`. Use the
explicit `field = expr` form when the payload field and source expression differ:

```lln
jump failed(pos = tok.pos, code = parse_code)
```

The same rule applies to block jumps, continuation exits, and continuation
target applications. The shorthand is source syntax for explicit ASDL `JumpArg`
entries; it is not closure capture.

### Invoking regions: `emit` and `call`

Regions are invoked with the same shape as their signature. Data arguments come
before `;`; continuation wiring comes after `;` as `continuation = target` pairs:

```lln
emit Connection.open("localhost:8080";
  connected = handle_connected,
  refused = retry_open,
  timeout = retry_open
)

call Connection.open("localhost:8080";
  connected = handle_connected,
  refused = retry_open,
  timeout = retry_open
)
```

The wired targets name caller blocks or enclosing continuation exits. The call
site does not write `jump`; the invoked region chooses one of its exits, and the
wiring says where that exit continues in the caller.

`emit` and `call` intentionally mean different things.

#### `emit`: open CFG splice

`emit` is an open control-flow splice. The frontend clones the target region's
entry and blocks into the enclosing control region, alpha-renames local values
and labels for that invocation, and replaces the emit site with a jump to the
cloned entry.

Use `emit` when the region is a local protocol abstraction and should become
part of the caller's CFG:

```lln
region ParserDriver.step(self [ptr [ParserDriver]], p [ptr [Parser]];
  ok,
  failed(pos [index], code [i32])
)
  entry start()
    emit Parser.next(p;
      token = got_token,
      eof = done,
      syntax = bad_syntax
    )
  end

  block got_token(tok [Token])
    jump ok
  end

  block done()
    jump ok
  end

  block bad_syntax(pos [index], code [i32])
    jump failed(pos, code)
  end
end
```

After expansion, no `emit` node reaches C lowering. It is an ASDL-visible source
control abstraction whose implementation is CFG cloning/splicing.

#### `call`: sealed region invocation

`call` is a sealed invocation. It introduces a real call/frame boundary. The
callee region is lowered as a callable artifact that returns a generated result
union whose variants correspond to the callee's continuation exits. The caller
then switches on that result and dispatches to the wired continuation targets.

Source:

```lln
call Tokenizer.skip_ws(self; done = check(tok, want, code))
```

Conceptually lowers to:

```text
callee frame: Tokenizer.skip_ws(self) -> SkipWsResult
result union: done(payload: { tok })
caller dispatch:
  done(tok) -> jump check(tok = tok, want = want, code = code)
```

This preserves a real call boundary without turning the surface language into
manual result-object code. The generated result union is a compiler artifact, not
a source-level protocol object that users switch on manually.

### Continuation target applications

A wiring target may be a bare target name:

```lln
call Parser.next(p; token = got_token, eof = done, syntax = failed)
```

or a target application with explicit arguments:

```lln
call Tokenizer.skip_ws(self; done = check(tok, want, code))
```

The target application says exactly which values the target block/continuation
receives when the callee exits through that continuation. Arguments may come from
two places:

1. **callee continuation payloads**, such as `tok` above; and
2. **caller lexical values passed explicitly through the generated dispatch
   block**, such as `want` and `code` above.

This is explicit dataflow, not hidden closure capture. If the target block needs
`want` and `code`, they must appear in the target application and in the block's
parameter list:

```lln
region Tokenizer.expect_char(self [ptr [Tokenizer]], want [u8], code [i32];
  done(tok [ptr [Tokenizer]]),
  parse_error(parse_code [i32], at [index])
)
  entry start()
    call Tokenizer.skip_ws(self; done = check(tok, want, code))
  end

  block check(tok [ptr [Tokenizer]], want [u8], code [i32])
    if tok.pos == tok.len then
      jump parse_error(parse_code = code, at = tok.pos)
    end
    let ch [u8] = tok.src[tok.pos]
    if ch == want then
      tok.pos = tok.pos + 1
      jump done(tok)
    else
      jump parse_error(parse_code = code, at = tok.pos)
    end
  end
end
```

Bare argument names use the named shorthand:

```lln
check(tok, want, code)
```

means:

```lln
check(tok = tok, want = want, code = code)
```

Use explicit names for reordering, renaming, field projections, or computed
values:

```lln
call Parser.next(p;
  token = consume(tok = tok, source_pos = p.pos),
  syntax = parse_error(parse_code = code, at = pos)
)
```

For `emit`, target application arguments are substituted directly into the
spliced CFG. For sealed `call`, non-payload target arguments are threaded through
the generated dispatch block with their typed values.

### Protocols, seals, and bundles

Parsed region declarations lower to `ItemRegion`. Region invocations lower to
explicit ASDL statements:

- `StmtRegionEmit` for open CFG splicing;
- `StmtRegionCall` for sealed call/frame boundaries.

Typechecking collects ASDL-visible region facts:

- **`RegionProtocol`** names a continuation-exit shape. Regions with the same
  exit protocol can share generated result-union vocabulary.
- **`RegionSeal`** describes a sealed callable region: its callable function,
  payload structs, and result union.
- **`RegionBundle`** groups compatible sealed regions so hot same-protocol
  transfers can lower to intra-bundle jumps instead of separate helper calls.

These facts are semantic compiler vocabulary. They make the fast path explicit:
a bytecode VM can be written as Lalin regions, with `call` preserving real sealed
entry points and bundle lowering fusing same-protocol internal transfers. The
compiler does not depend on C inlining or GCC recognizing accidental sugar to get
the intended VM shape.

Unexpanded `emit` and unlowered continuation jumps must not reach final C
lowering. Sealed `call` reaches C lowering as generated functions, result unions,
and dispatch code according to the collected region facts.

---

## Contracts And Memory Facts

Contracts describe semantic facts the compiler is allowed to rely on.

Common contracts:

```lln
requires bounds(xs)(n)
requires bounds(dst)(n), bounds(src)(n)
requires readonly(xs)
requires writeonly(dst)
requires noalias(tmp)
requires disjoint(dst)(src)
requires preserve(store)
requires invalidate(store)
```

Typical meanings:

| Contract | Meaning |
|---|---|
| `bounds(ptr)(n)` | memory object has at least `n` elements available |
| `readonly(ptr)` | function does not write through this pointer |
| `writeonly(ptr)` | function writes but does not read old values through this pointer |
| `noalias(ptr)` | pointer-backed memory object has no aliases in this access context |
| `disjoint(a)(b)` | pointer-backed memory objects do not alias |
| `preserve(store)` | call preserves leases associated with this store/domain access |
| `invalidate(store)` | call may move, free, compact, clear, or reuse storage for this store/domain |

These contracts feed typed memory, effect, and C-lowering facts. Missing optimization
capabilities select conservative code rather than disabling fusion: absent noalias
evidence disables `restrict`, while unknown alignment or non-unit stride leaves the
scalar path intact. Window safety is derived from the window domain, exact memory
uses, and ordinary bounds contracts; there is no generic proof token or authored
aggregate footprint certificate.
---

## Borrow Checking, Handles, And Ownership

Lalin's borrow checking is region-shaped and object-local rather than
Rust-shaped. The core rules are:

```text
Handles may escape. Leases may not.
Stores/machine objects own bytes. Regions grant access facts.
Owned values must be discharged exactly once.
```

A raw `ptr(T)` is only an address. Durable identity is a handle. Temporary
memory access is a lease, usually granted by a resolver region or by a trusted
boundary contract.

The preferred memory-management shape is also one object per machine/store:

```text
machine/store object = owner + resolver authority + invalidation boundary
```

The same object that owns storage should own the handle namespace, resolver
regions, preserving operations, and invalidating operations. This keeps
ownership, freshness epochs, generation counters, and lease invalidation local
instead of spreading them through side tables or ambient context.

This is where the object model and memory model meet. A memory-management object
is not just a container of bytes; it is the authority that names durable handles,
grants temporary leases through regions, proves preservation, and performs
invalidation. Because those protocols are owned by the store object, user code
can interact with a clean handle/region vocabulary while the object manages the
lease discipline internally.

Type meta-properties are the boilerplate valve for this pattern. Ownership plus
handles naturally produces repetitive resolver, stale/missing, borrow,
invalidate, and serializer code. A type-family or store object may synthesize
that vocabulary through `T.metamethods` so the source stays small while the
compiled artifact still contains explicit structs, handles, regions, and
functions.

The built-in arena-store policy is just a Lua declaration generator installed by
ordinary meta assignment; the parser has no store-specific syntax:

```lln
struct Token
  kind [u32]
  start [index]
  stop [index]
end

struct TokenStore
  storage [ptr [Token]]
  count [index]
  capacity [index]
  epoch [u32]
end

TokenStore.store.target = Token
TokenStore.metamethods.__getdecls = arena_store

fn token_space(s [ptr [TokenStore]]) [index]
  return s:capacity_left()
end
```

Materialization expands the policy into ordinary declarations such as
`handle TokenStore.Ref`, `region TokenStore.borrow`, `region TokenStore.compact`,
`fn TokenStore.capacity_left`, and `fn TokenStore.len`. Those generated names
then behave exactly like hand-written qualified declarations.

#### Example: a store object owns handles and leases

```lln
struct BufferRecord
  ptr [ptr [u8]]
  len [index]
  generation [u32]
end

struct BufferStore
  records [ptr [BufferRecord]]
  count [index]
  epoch [u32]
end

handle BufferStore.Ref [u32]
  invalid = 0
  domain [BufferStore]
  target [BufferRecord]
end

region BufferStore.borrow(
  self [readonly [ptr [BufferStore]]],
  ref [BufferStore.Ref];
  borrowed(record [lease("self", ptr [BufferRecord])]),
  stale(ref [BufferStore.Ref]),
  missing(ref [BufferStore.Ref])
)
  entry start()
    -- Store-private validation checks index/generation/epoch.
    -- Only the borrowed continuation receives the temporary lease.
    jump missing(ref)
  end
end

region BufferStore.compact(self [invalidate [ptr [BufferStore]]];
  done,
  busy
)
  entry start()
    -- Cannot run while leases from `self` are live.
    -- The checker sees this because borrow grants lease("self", ...), while
    -- compact takes invalidate ptr(BufferStore).
    jump done
  end
end
```

A client does not manually check generations or scatter nil/stale branches. It
wires the store protocol:

```lln
region Reader.read_one(self [ptr [Reader]], store [ptr [BufferStore]], ref [BufferStore.Ref];
  ok(len [index]),
  stale,
  missing
)
  entry start()
    emit BufferStore.borrow(store, ref;
      borrowed = got_record,
      stale = got_stale,
      missing = got_missing
    )
  end

  block got_record(record [lease("store", ptr [BufferRecord])])
    jump ok(len = record.len)
  end

  block got_stale(ref [BufferStore.Ref])
    jump stale
  end

  block got_missing(ref [BufferStore.Ref])
    jump missing
  end
end
```

The store object hides memory discipline behind typed exits. The handle may
escape; the lease cannot. Invalidating store methods are naturally checked
against live leases because both facts are attached to the same object protocol.

### Domain Contract

A handle that declares `domain [A]` is making a checkable claim: `A` is the
object that can resolve that handle. Lalin checks the core `Domain(A, H)` shape
when the handle is typechecked:

```text
H has domain A and target R
A has a qualified resolver region taking `(self, H)`
that resolver has a success continuation carrying `lease("self", ptr [R])`
```

The resolver region may be named for the domain vocabulary, for example
`A.borrow` or `A.resolve`. Failure exits are ordinary named continuations such as
`stale`, `missing`, `invalid`, or `busy`:

```lln
handle BufferStore.Ref [u32]
  invalid = 0
  domain [BufferStore]
  target [BufferRecord]
end

region BufferStore.borrow(self [readonly [ptr [BufferStore]]], ref [BufferStore.Ref];
  borrowed(record [lease("self", ptr [BufferRecord])]),
  stale(ref [BufferStore.Ref]),
  missing(ref [BufferStore.Ref])
)
  entry start()
    jump missing(ref)
  end
end
```

If the handle names a domain but no matching resolver exists, or if the resolver
succeeds without granting a lease from `self` to the handle target, typechecking
reports a domain-contract issue at declaration time instead of deferring the
failure to the first attempted use.

The same contract is used by stores, generic resolvers, and LuaBridge-style
runtime boundaries. The skins differ; the object law is the same: the domain is
the authority that owns durable handles and grants temporary access.

### Handle Resolution

A resolver takes a handle plus access to its domain store and exposes access
only through its successful continuation. With qualified regions, the store
owns its resolver:

```lln
struct AudioBufferStore
  slots [ptr [AudioBufferSlot]]
  samples [ptr [f32]]
  capacity [index]
end

region AudioBufferStore.borrow(
  self [readonly [ptr [AudioBufferStore]]],
  buffer [AudioBuffer];
  borrowed(record [lease("self", ptr [AudioBufferRecord])]),
  stale(buffer [AudioBuffer]),
  missing(buffer [AudioBuffer])
)
  entry start()
    -- store-private validation and jump borrowed/stale/missing
  end
end
```

For a handle with `target = "AudioBufferRecord"`, a resolver may only grant a
lease to that target type. For a handle with `domain = "AudioBufferStore"`, the
resolver must take the owning domain as a `readonly` or `preserve` access and
tie the lease origin to that domain parameter. Anonymous leases are allowed for
simple boundary access, but store leases need an origin so invalidation checks
can tell which store they came from.

### Lease Escape Rules

A lease is temporary access. The checker rejects leases in durable type
positions and in expression-style region-call result objects. In source terms:

- do not return a lease as durable identity
- do not store a lease in a struct, union payload, const, static, array, or
  closure-like aggregate
- do not pass a lease to a retaining plain `ptr`/`view` parameter; use a lease or
  `noescape` parameter
- use explicit continuations for region protocols whose payload carries a
  lease; do not box that protocol into a generated result union

Field lookup and indexing can use lease bases, so a `lease ptr(T)` behaves like
temporary access to `T` while it is in scope.

### Invalidation Rules

An operation that may move, free, compact, clear, or reuse a store cannot run
while leases from that same store are live. Mark preserving APIs with
`readonly`, `preserve`, or `requires preserve(store)`. Mark invalidating APIs
with `invalidate` or `requires invalidate(store)`. Unannotated mutable
`ptr`/`view` parameters are conservative invalidators.

End the lease scope before calling an invalidating operation, or redesign the
protocol so the resolver grants the lease only inside the continuation that uses
it.

### Owned Obligations

`owned T` is linear authority, not a managed pointer. The checker treats it as a
CFG obligation:

- it must be transferred to another `owned` parameter/result/continuation or
  consumed by a close/retire/destroy protocol
- it cannot be copied or observed as plain `T`
- it cannot be stored in durable fields/statics or hidden in aggregates
- continuing branches must preserve the same live owned-obligation set
- `var owned T` is rejected; thread ownership through `let`, returns, jumps, and
  continuations instead

There are no semantic destructors. If a resource changes lifetime, name the
region/function that does it and state whether it consumes or returns the owned
obligation.

---

## Loops And Backend Recognition

A parsed 1D domain loop:

```lln
fn copy_scale(dst [ptr [i32]], src [ptr [i32]], n [index]) [void]
  requires bounds(dst)(n), bounds(src)(n), disjoint(dst)(src)

  loop i in 0 .. n do
    dst[i] = src[i] * 2
  end
end
```

lowers through control-region blocks, then the backend records producer, body,
sink, memory, effect, and schedule facts. The backend recognizes semantic
shapes, not textual patterns.

For source `loop`, forming those facts is part of the language contract. Missing
memory proofs, unsupported body forms, or unsupported producer/sink combinations
should become diagnostics instead of silently becoming general imperative loops.

Supported stencil vocabulary is structural:

- `StoreN`: producer plus N-input point body plus store sink
- `ReduceN`: producer plus N-input point body plus reduce sink
- `ScanN`: producer plus N-input point body plus scan sink
- `ScatterReduceN`: producer plus N-input point body plus indexed reduce sink

Here `_n` always means point input count: the number of logical input
streams referenced by the point body. It does not mean rank, output count,
loop axes, fused stage count, or a derived backend family.

Source patterns such as scalar fill, copy, indexed reads/writes, casts,
comparisons, and blends are configurations of those descriptors, not separate
backend families.

Facts determine whether a valid source loop becomes:

- fused CMat fragments in the emitted `CBackendUnit` when the exact shape plus declared memory/noalias/bounds facts admit fusion
- a typed reject
- a typed reject

The internal IR can still contain generic control regions. That is how regions,
lowering internals, and generated control are represented. The public source
`loop` surface is narrower: it is a finite domain loop intended to become
stencil-shaped backend facts.

---

## Backend Defaults

The main executable backend is GCC over `emit_c` output. It compiles the emitted
C as a shared object, loads it with `dlopen`, and exposes symbols as LuaJIT FFI
function pointers.

```text
inferred Lalin compilation unit
  -> LalinCode / LalinKernel / LalinStencil facts
  -> CBackendUnit
  -> emit_c C implementation/header/support
  -> gcc -shared -O3
  -> dlopen + dlsym
  -> LuaJIT FFI function pointer
```

Use:

```lua
local session = lalin.compile_c_gcc("demo", decls, {
  gcc_opts = { opt = 3, out_dir = "target/demo" },
})

local add = assert(session:symbol("add", "int32_t (*)(int32_t, int32_t)"))
print(add(3, 4))
session:free()
```

or select it through the generic compiler facade:

```lua
local session = lalin.compile("demo", decls, { backend = "gcc" })
```

The emitted C remains available for AOT builds through `emit_c` and `compile_c`.
The user/build system owns AOT compiler flags, linker inputs, and target ABI
choices.

Explicit LuaJIT bytecode mode is removed. The public surface exposes only the
emitted-C path: `compile_c_gcc` cooks emitted C with GCC for local execution,
and `emit_c` / `compile_c` produce the C artifact for AOT builds.
### Retired Native Template Banks

Native copy-patch template banks and the patcher are deleted and are not part of
the architecture or supported language surface.
### C / AOT Emission

Use `emit_c` when the desired product is a C artifact that the user compiles as
a native program or library. This is the same semantic C output consumed by the
GCC C JIT path:

```lua
local artifact = lalin.emit_c(decls, {
  name = "demo",
  c_path = "target/demo.c",
  h_path = "target/demo.h",
  combined_path = "target/demo_combined.c",
})
```

The C path lowers through the semantic `CBackendUnit` pipeline and emits the
selected program as ordinary C translation units. The user then compiles that C
with `gcc` or another C toolchain for AOT, or lets `compile_c_gcc` cook it into a
shared object for JIT-like local execution. There is no LuaJIT bytecode path.

---

## DSL Syntax

The Lua/LLBL DSL is the programmatic construction surface. It is ordinary Lua
that constructs Lalin declarations through staged heads.

Use the DSL when:

- generating declarations with Lua functions
- writing macros
- sharing fragments
- using ND/tiled/window producer heads today
- composing Lalin with other LLBL members

### Setup

```lua
local lalin = require("lalin")
local lln = lalin.lln
```

Prefer explicit namespace locals in examples. `lalin.language.use()` exists for
LLBL language-environment experiments, but normal builder examples should not
rely on installed globals.

### Function

```lua
local add = lln.fn. add { a [lln.i32], b [lln.i32] } [lln.i32] {
  lln.ret (a + b),
}
```

### Struct

```lua
local Pair = lln.struct. Pair {
  left [lln.i32],
  right [lln.i32],
}
```

### Handle And Borrowing Types

```lua
local AudioBuffer = lln.handle. AudioBuffer {
  invalid = 0,
  domain = "AudioBufferStore",
  target = "AudioBufferRecord",
}

local borrow_sig = lln.product {
  store [lln.readonly [lln.ptr [lln.named("AudioBufferStore")]]],
  samples [lln.lease("store", lln.view [lln.f32])],
  resource [lln.owned [lln.named("AudioBuffer")]],
}
```

### Contracts

```lua
lln.requires {
  lln.bounds(xs)(n),
  lln.readonly(xs),
}
```

### Let, Var, Set, Return

```lua
lln.let. x [lln.i32] (1)
lln.var. acc [lln.i32] (0)
set (acc)(acc + x)
lln.ret (acc)
```

### Conditionals

```lua
lln.when (n :eq (0)) {
  lln.ret (0),
}
```

### 1D Loop

```lua
lln.loop. i [lln.range { 0, n }] {
  set (dst[i])(src[i]),
}
```

### ND Range

```lua
lln.loop { i, j } [lln.range_nd { { 0, h }, { 0, w } }] {
  set (dst[i * w + j])(src[i * w + j]),
}
```

### Tiled ND

```lua
lln.loop { i, j } [lln.tiled_nd {
  axes = { { 0, h }, { 0, w } },
  tiles = { 2, 2 },
}] {
  set (dst[i * w + j])(src[i * w + j]),
}
```

### Window ND

```lua
lln.loop { i } [lln.window_nd {
  axes = { { 0, n } },
  windows = { { 1, 1, boundary = "clamp" } },
}] {
  set (dst[i])(xs[i - 1] + xs[i] + xs[i + 1]),
}
```

### Fold And Scan

The DSL has reducer heads for folds and scans used by the native-loop backend.

```lua
lln.loop. i [lln.range { 0, n }] [lln.i32] {
  lln.fold. acc [lln.i32] {
    init = 0,
    by = lln.add,
    step = xs[i],
  },
}
```

```lua
lln.loop { i, j } [lln.range_nd { { 0, h }, { 0, w } }] {
  lln.scan. acc [lln.i32] {
    init = 0,
    by = lln.add,
    axis = 2,
    step = xs[i * w + j],
    into = dst[i * w + j],
  },
}
```

### Fragments And Splicing

Fragments are Lua values that carry product/list roles.

```lua
local buffer = lln.product {
  p [lln.ptr [lln.u8]],
  n [lln.index],
}

local first = lln.fn. first { _(buffer) } [lln.u8] {
  lln.ret (p[0]),
}
```

`_(fragment)` is the common splice form. `spread(fragment)` is the explicit
long-form splice.

### Compiling DSL Values

Compile DSL values through the emitted-C path:

```lua
local session = lalin.compile_c_gcc("demo", { add }, {
  gcc_opts = { opt = 3, out_dir = "target/demo" },
})
```

---

## Formatting

Lalin formatting formats evaluated Lalin/LLBL values, not arbitrary source text.

```sh
luajit scripts/lalinfmt.lua demo.lua
luajit scripts/lalinfmt.lua --check demo.lua
luajit scripts/lalinfmt.lua --write demo.lua
```

Programmatic API:

```lua
local lalin = require("lalin")

local text = lalin.format(value)
local text = lalin.format_file("demo.lua")
lalin.write_format_file("demo.lua")
```

The formatter currently prints the Lua/LLBL DSL surface.

---

## Current Parsed Surface Status

| Construct | Status |
|---|---|
| `fn name(params) [result] ... end` | implemented |
| `extern name(params) [result] ... end` | implemented; declares C ABI extern with optional `symbol` fact |
| `fn Struct.name(...) ... end` | implemented; attaches function to struct value in env; this is the explicit method form |
| `fn Struct:name(...) ... end` | implemented; injects `self [ptr [Struct]]` and binds as `Struct.name` |
| `region Struct.name(...; ...) ... end` | implemented; qualified regions bind to struct value in env; this is the explicit protocol/access form |
| `region Struct:name(...; ...) ... end` | implemented; injects `self [ptr [Struct]]` and binds as `Struct.name` |
| `handle Struct.name [repr] ... end` | implemented; qualified handles bind to struct value in env; this is Lalin's durable reference form |
| `unique` marker inside `struct` | documented identity model; direct parsed lowering is pending, use handles/stores for durable identity today |
| `handle Name [repr] ... end` | implemented; handle fact types use bracket type values |
| `region name(params; exits) ... end` | implemented as typed control protocol; lowers to `ItemRegion` |
| `emit Region(args; cont = block)` | implemented as open CFG splice; expands into enclosing control CFG before backend lowering |
| `call Region(args; cont = block)` | implemented as sealed region invocation; lowers through region seals/result unions/dispatch |
| `cont = target(arg, ...)` in region wiring | implemented; explicit continuation target application with shorthand args |
| `jump exit(name)` | implemented as shorthand for `jump exit(name = name)` in named payloads |
| `let` / `var` | implemented |
| assignment | implemented in statement blocks |
| `Type.path.slot = host_name` top-level meta assignment | implemented for declaration-time type meta-properties |
| `return` | implemented |
| `requires` | implemented, including memory/effect contracts such as `bounds`, `readonly`, `writeonly`, `noalias`, `disjoint`, `preserve`, and `invalidate` |
| access / lease / owned type values | implemented through Lua type values in brackets |
| `expr:method(args)` method call | implemented; preserves method intent for staging, then lowers to `method(expr, args)` static call |
| `if` / `elseif` / `else` | implemented |
| `switch expr do case K then ... default then ... end` | implemented; lowers to scalar `StmtSwitch` / C `switch` |
| `loop i in 0 .. n do ... end` | implemented |
| parsed `fold` / `scan` inside loops | implemented |
| parsed `grid`, `tiled grid`, `window` domains | implemented |
| `StructName { field = value }` struct constructor | implemented for named/qualified struct paths; lowers to typed aggregate construction |
| host escapes `[lua_expr]` | implemented |
| `as [T](expr)` | implemented |
| `sizeof [T]` | implemented |
| source `while`, `break`, `continue` | not supported |
