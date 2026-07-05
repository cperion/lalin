# C LLBL Dialect Architecture

Status: target architecture for the `llbl.c` dialect. This document describes the desired shape of the C dialect as a language member. It is not an implementation plan.

## Purpose

C LLBL is the C source language member of LLBL. It exists so generated C is authored as structured Lua values instead of strings.

```text
Lua procedural generation
  -> C LLBL typed syntax objects
  -> role checking / validation / formatting
  -> C source text
```

The C text is an artifact boundary. It is not the authoring model.

C LLBL is the common C syntax layer for every project path that emits C:

```text
Native stencil/template source facts
  -> native source-generation object
  -> C LLBL declarations/statements/expressions
  -> NativeTemplateSource.c_text

LalinC.CBackendUnit semantic facts
  -> C LLBL projection
  -> C source artifact

Generated C helpers/tools
  -> C LLBL units/fragments
  -> C source text
```

Semantic IR decides **what** must be emitted. C LLBL decides **how C syntax is represented, validated, formatted, and rendered**.

## Boundary

This is a redesign of the C dialect, not LLBL core.

C LLBL uses existing LLBL services:

- roles
- heads
- fragments
- splicing
- origins
- diagnostics
- formatting/doc algebra
- dialect environments

C LLBL does not redefine those services. It applies them deeply to C.

## Core thesis

C LLBL must be a real object language:

```text
C syntax vocabulary as typed Lua values
+ C roles and fragments
+ leaf-owned rendering/validation behavior
+ dialect profiles
+ formatter
+ controlled raw escapes
```

It is not a text templating system.

Every C construct that stencil/native/codegen paths need should have a C LLBL value. Procedural generation should produce those values directly.

## Object model

Current shallow shape:

```lua
{ __llbl_c = "stmt", kind = "return", value = expr }
```

Target semantic shape:

```text
CType       parent role for C types
CExpr       parent role for C expressions
CStmt       parent role for C statements
CDecl       parent role for C declarations
CUnit       translation unit
```

Concrete leaves own behavior:

```lua
function C.CReturn:emit_c(ctx) ... end
function C.CIf:emit_c(ctx) ... end
function C.CFunctionDef:emit_c(ctx) ... end
function C.CExternFunction:emit_c(ctx) ... end
```

Parent methods are contracts/defaults. They do not inspect `kind` strings to dispatch. The concrete C node is the dispatch owner.

## Roles

C LLBL roles:

```text
c.type          one C type
c.expr          one C expression
c.stmt          one C statement
c.decl          one C declaration
c.unit          one C translation unit

c.types         ordered list of types
c.exprs         ordered list of expressions / call args
c.stmts         ordered list of statements
c.decls         ordered list of declarations
c.fields        struct field product
c.params        function parameter product
c.inits         initializer list / designated initializers
```

Role behavior:

- `c.fields` and `c.params` are product roles with unique names.
- `c.stmts`, `c.decls`, `c.exprs`, and `c.inits` accept fragments and spreads.
- Role errors mention the target C role, the producer head, and source origin.
- Generated Lua arrays can be spliced with `_` exactly like other LLBL dialects.

Example:

```lua
local generated = {}
for i = 0, 3 do
  generated[#generated + 1] = c.assign(out[i], out[i] + i)
end

c.fn. accumulate { out [c.ptr [c.i32]] } [c.void] {
  _(generated),
}
```

## Surface syntax: declarations

### Translation unit

```lua
c.unit. native_stencil {
  c.include "stdint.h",
  c.include "stddef.h",
  c.decl. lalin_native_entry ...,
}
```

### Includes and defines

```lua
c.include "stdint.h"
c.include_local "generated_config.h"

c.define. LALIN_FRAME_BYTES(256)
c.define_expr. LALIN_WORD_BYTES(c.sizeof [c.uintptr_t])
```

`c.define` is token-oriented and intentionally limited. Expression-valued defines use C expressions.

### Structs

```lua
c.struct. LalinFrame {
  data [c.array [c.u8] [256]],
}

c.typedef_struct. Pair {
  left [c.i32],
  right [c.i32],
}
```

`c.struct.Name` emits a named `struct Name { ... };`.
`c.typedef_struct.Name` emits `typedef struct Name { ... } Name;`.

### Typedefs

```lua
c.typedef. lalin_word [c.uintptr_t]

c.typedef. lalin_continuation [c.fnptr {
  frame [c.ptr [c.u8]],
} [c.void]]
```

Function pointer declarators are first-class. They are not raw parameter strings.

### Externs and prototypes

```lua
c.extern_object. lalin_native_hole_0 [c.const [c.u8]]

c.extern_fn. lalin_native_cont_next {
  frame [c.ptr [c.u8]],
  arg0 [c.i32],
} [c.void]

c.proto. helper_copy {
  dst [c.ptr [c.u8]],
  src [c.ptr [c.const [c.u8]]],
  n [c.size_t],
} [c.void]
```

Externs and prototypes are declarations without bodies. Native stencil source generation must use these for holes and continuations.

### Functions

```lua
c.fn. feature_probe {
  seed [c.i32],
  out [c.restrict [c.ptr [c.i32]]],
} [c.i32] {
  c.return_(seed),
}

c.static_fn. local_helper {} [c.void] {
  c.return_(),
}

c.static_inline_fn. add1 { x [c.i32] } [c.i32] {
  c.return_(x + 1),
}
```

Function bodies are `c.stmts` fragments.

## Surface syntax: types

Primitive types:

```lua
c.void
c.bool
c.char
c.i8   c.u8
c.i16  c.u16
c.i32  c.u32
c.i64  c.u64
c.f32  c.f64
c.size_t
c.uintptr_t
c.intptr_t
```

Named types:

```lua
c.type.Pair
c.type("Pair")
c.struct_type.Pair       -- struct Pair without typedef name
```

Type constructors:

```lua
c.ptr [c.u8]
c.const [c.u8]
c.volatile [c.u32]
c.restrict [c.ptr [c.u8]]
c.array [c.i32] [4]
c.fnptr { frame [c.ptr [c.u8]] } [c.void]
```

GNU/profile-specific types:

```lua
c.typeof [expr]
c.typeof_type [c.i32]
c.vector [c.u32] (16)
c.attribute [c.i32] { "aligned(16)" }
```

The dialect profile decides whether GNU-specific types are accepted.

## Surface syntax: expressions

Names and literals:

```lua
x
c.name. frame
c.int(42)
c.string("hello")
c.null [c.ptr [c.u8]]
```

Operators use Lua syntax where possible and curried helpers where Lua syntax is not enough:

```lua
x + y
x - y
x * y
x / y
c.band(x)(mask)
c.bor(x)(flag)
c.shl(x)(3)
c.eq(x)(0)
c.ne(x)(0)
c.land(c.ne(x)(0))(c.lt(x)(10))
```

Calls, fields, and indexes:

```lua
callee { frame, arg0 }
frame[0]
pair.left
```

C-only expression forms:

```lua
c.cast [c.i32] (value)
c.sizeof [c.i32]
c.sizeof_expr(value)
c.addr(value)
c.deref(ptr)
c.select(cond)(then_value)(else_value)
```

Compound literals and initializers:

```lua
c.compound [c.type.Pair] {
  c.init.left(1),
  c.init.right(2),
}

c.list { 1, 2, 3, 4 }
```

Builtins:

```lua
c.builtin.memcpy { dst, src, n }
c.builtin.memset { dst, 0, n }
c.builtin.trap {}
c.builtin.unreachable {}
```

Atomic builtins should have typed wrappers instead of relying on raw builtin names:

```lua
c.atomic.load(ptr, c.atomic.seq_cst)
c.atomic.store(ptr, value, c.atomic.seq_cst)
c.atomic.fetch_add(ptr, value, c.atomic.seq_cst)
c.atomic.compare_exchange(ptr, expected, desired, c.atomic.seq_cst, c.atomic.seq_cst)
c.atomic.fence(c.atomic.seq_cst)
```

These wrappers render to the appropriate GCC/Clang C builtins under a profile that admits them.

## Surface syntax: statements

Declarations:

```lua
c.decl. x [c.i32] (0)
c.decl. p [c.ptr [c.u8]]
c.decl_volatile. ready [c.u32] (0)
c.auto. tmp(expr)          -- GNU-only
```

Assignments and expression statements:

```lua
c.assign(dst, value)
c.expr(callee { arg })
```

Returns:

```lua
c.return_()
c.return_(value)
```

Conditionals:

```lua
c.if_ (c.ne(x)(0)) {
  c.return_(1),
} {
  c.return_(0),
}
```

Loops:

```lua
c.for_ {
  c.decl. i [c.i32] (0),
  c.lt(i)(n),
  c.assign(i, i + 1),
} {
  c.assign(acc, acc + xs[i]),
}

c.while_ (c.lt(i)(n)) {
  c.assign(i, i + 1),
}
```

Blocks:

```lua
c.block {
  c.decl. x [c.i32] (1),
  c.expr(use { x }),
}
```

Inline assembly:

```lua
c.asm_volatile(""; clobbers = { "memory" })
```

This is a first-class statement with a GNU/profile requirement.

## Formatting

C LLBL has two formatters:

1. C source renderer: emits valid C text.
2. LLBL object formatter: prints the object DSL back as readable Lua/LLBL-style code.

The object formatter must preserve the shape of procedural generation output:

```lua
c.fn. main {} [c.i32] {
  c.decl. out [c.array [c.i32] [4]] (c.list { 0, 0, 0, 0 }),
  c.if_ (c.ne(feature_probe { 5, out })(12)) {
    c.return_(1),
  },
  c.return_(0),
}
```

The C renderer is allowed to choose stable C formatting, but it must not erase origins or validation context.

## Validation

C LLBL validation checks C syntax object correctness, not Lalin compiler semantics.

It validates:

- role correctness
- declaration names
- duplicate fields/parameters where relevant
- type constructor well-formedness
- function bodies versus prototypes
- statement placement
- initializer shape where statically visible
- dialect/profile restrictions
- raw escape presence and reasons

It does not validate:

- Lalin ABI correctness
- native patch-hole correctness
- Code/Lalin semantic lowering correctness
- platform object-file extraction correctness

Those belong to their owning semantic systems.

## Dialect profiles

A C dialect profile is a value:

```lua
c.profile.c99
c.profile.c11
c.profile.gnu99
c.profile.gnu11
c.profile.freestanding(c.profile.gnu99)
```

Profile facts include:

```text
standard: c99 | c11 | gnu99 | gnu11
freestanding: bool
allows_gnu_extensions: bool
allows_typeof: bool
allows_statement_expr: bool
allows_auto_type: bool
allows_asm: bool
allows_vector_attribute: bool
allows_gcc_atomics: bool
```

Rendering and validation receive a profile. GNU-only nodes reject under non-GNU profiles.

## Raw escapes

Raw escapes are terminal trust-boundary nodes:

```lua
c.raw_expr("...")
c.raw_stmt("...")
c.raw_decl("...")
c.raw_param("...")
```

Each raw node carries:

```text
text
role
origin
reason
```

Raw nodes render exactly as given. Validation records them. Native stencil generation should not use raw nodes for ordinary holes, continuations, frame loads/stores, atomics, casts, or control flow; those are part of the modeled C vocabulary.

## Native stencil source object

Native-specific concepts do not belong inside generic C LLBL. They belong in a Lalin-side source object that targets C LLBL.

```text
NativeStencilCSource
  owns holes
  owns hole ordinals
  owns continuation ordinals
  owns entry symbol
  owns frame parameter convention
  owns relocation declarations
  produces C LLBL declarations/statements
  produces NativeTemplateSource metadata
```

Sketch:

```lua
local S = NativeStencilCSource(T, input, id_base)
local frame = S:frame()
local next = S:continuation("next", {})

local lhs_hole = S:frame_offset_hole("lhs")
local rhs_hole = S:frame_offset_hole("rhs")
local dst_hole = S:frame_offset_hole("dst")

local lhs = S:frame_load(c.i32, lhs_hole)
local rhs = S:frame_load(c.i32, rhs_hole)

S:entry("lalin_native_code_inst_add", { frame [c.ptr [c.u8]] }) {
  S:frame_store(c.i32, dst_hole, lhs + rhs),
  S:tail(next),
}

return S:template_source(family, extraction)
```

Native helper methods return C LLBL values:

```text
S:hole_extern(hole)              -> CExternObject or CExternFunction
S:continuation_extern(cont)      -> CExternFunction
S:frame_load(type, hole)         -> CExpr
S:frame_store(type, hole, expr)  -> CStmt
S:tail(cont, args...)            -> CStmt
S:entry(name, params)            -> CFunctionDef builder
```

The generic C dialect knows how to express externs, calls, casts, dereferences, and assignments. The native source object knows what holes, continuations, frame offsets, and relocation metadata mean.

## CBackend projection

`LalinC.CBackendUnit` remains a semantic C-backend IR when it carries ABI, layout, helper, global, block, and control facts. Its C text emission is a projection to C LLBL:

```text
CBackendUnit
  -> C LLBL CUnit
  -> C source text
```

The projection owns the mapping from Lalin backend semantics to C syntax. C LLBL owns the syntax objects and rendering.

This keeps the boundary clean:

```text
c_validate.lua          validates Lalin C-backend semantic facts
llbl.c.validate         validates C syntax/profile facts
llbl.c.render           emits C text
```

## Generated C as Lua values

The main design win is procedural generation without string soup.

Bad:

```lua
lines[#lines + 1] = "extern void " .. name .. "(uint8_t *frame);"
lines[#lines + 1] = "void " .. entry .. "(uint8_t *frame) {"
lines[#lines + 1] = "    " .. name .. "(frame);"
lines[#lines + 1] = "}"
```

Good:

```lua
local cont = c.extern_fn [name] { frame [c.ptr [c.u8]] } [c.void]
local fn = c.fn [entry] { frame [c.ptr [c.u8]] } [c.void] {
  c.expr(c.name(name) { frame }),
}
```

Better with the native source object:

```lua
local cont = S:continuation("next", {})
S:entry(entry) {
  S:tail(cont),
}
```

The generated program remains a Lua value until the final render boundary.

## Compatibility surface

The existing ergonomic surface should remain recognizable:

```lua
local c = require("llbl.c")
c.use()

c.fn. main {} [c.i32] {
  c.return_(0),
}
```

But the internals should be deep enough that this syntax constructs typed C nodes with leaf-owned behavior, not loose kind records.

## Success shape

C LLBL is successful when:

- generated C is built as C syntax objects, not string arrays
- C roles/fragments/splicing make procedural generation easy
- C node leaves own rendering and validation behavior
- dialect profiles reject invalid GNU/C11 mixtures
- raw escapes are audited and exceptional
- native stencil source generation targets C LLBL through a native source object
- CBackendUnit text emission targets C LLBL through a semantic projection
- `NativeTemplateSource.c_text` and C artifact files are final boundaries only
