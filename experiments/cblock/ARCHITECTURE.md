# CBlock Architecture

CBlock is a small Lua DSL that constructs ordinary C. This document describes
how the implementation is organized: named control protocols, the pipeline, the
three IR layers, the inline/seal mechanism, and the two cooking paths (GCC and
TCC) that consume the same emitted C.

The language surface is documented in
[LANGUAGE_REFERENCE.md](LANGUAGE_REFERENCE.md); the design rationale is in
[lua_label_machines.md](lua_label_machines.md).

## 1. The one pipeline, three owners

CBlock has exactly one compiler pipeline; every execution path goes through it.
Nothing is generated twice.

```text
Lua build chunk
  -> source_env (staging)     deferred bodies become statement lists, blocks, vars
  -> env.__finish             complete_func: stage every deferred body
  -> check_machine (check)    type check; terminators; collect diagnostics
  -> lower_machine (lower)    registers, block layout, terminator opcodes
  -> codegen                  deterministic C text
  -> GCC/AOT artifact         (user-owned build of the same text)
  -> TCC memory cook          (C.jit: libtcc in-memory, dlopen-style symbols)
```

Ownership is strict:

- **Lua** owns names, namespaces, staging, and composition. Bodies are Lua
  closures; tables are the staging environment.
- **CBlock** owns types, named control protocols, checking, lowering, and C
  emission.
- **C** owns layout and ABI. The emitted text is ordinary C; no runtime, no
  hidden receivers, no JIT of its own.

The files:

```text
cblock.lua       the whole compiler: types, staging env, check, lower, codegen,
                 plus the Runtime metatable that wires C.jit
cblock_tcc.lua   the libtcc Session: memory compile, relocate, symbols
label.lua        the keyword/DSL runtime (L.new_env, L.run, L.keyword)
```

## 2. Staging: the source layer

`source_env(parent)` builds a Lua environment (`L.new_env`) containing the
whole surface: types, callables, places, pipelines, control. Running the build
chunk in that environment (`L.run(env, build)`) records declarations:

- `func`/`extern` register ordered named parameters and a separately curried
  native result type. Direct `region`s use the same curried result position;
  alternative `region`s record named value parameters plus named continuation
  parameters; `block` registers a label into the current func.
- **Bodies are deferred.** `func(params)(result)(body)` stores `body` as
  `body_builder` and returns the callable value. Nothing semantic runs yet, so a
  body may reference locals assigned later (recursion, mutual threading).
- The chunk returns a namespace table; `export_namespace` walks it and assigns
  C ABI names (`math_add`, `machine_step`, ...). Externs must appear there.
- `env.__finish` runs `complete_func` on every registered func.

### Bodies become statement lists

`complete_func` stages each deferred body with symbolic parameter refs. Every
callable exposes named values through immutable `ParamBinder` `p`; plural regions
add immutable continuation binder `c`. A function can bind its return edge as
second argument `r` for nested control. The body's return values are its statement
list. A single bare value in a direct func or region becomes a result; anything
else becomes a list whose last element terminates (`as_block_list`).

Staging happens under `current = f`, so:

- `var`/`block`/`let` bind to the enclosing func;
- applying a `region` **inlines** its body into the current func
  (`emit_region`); a flag `r.emitting` rejects recursive self-emission with
  `use call(region)`;
- `call(region)` calls `seal_region`, which creates one private `Func`
  (`internal = true`, `static` in C) and `complete_func`s it — the cached
  private seal.

### The symbolic call boundary

`Func_mt.__call` is the two-phase application point:

- during staging, applying a func builds a symbolic call: a direct func yields
  a call expression (`fcall`) or, when void, a `dcall` statement that also
  terminates the block; a sealed multi-exit func accepts one exact named-handler
  table and produces one ordered handler body per declared exit;
- region calls accept positional input sugar or one exact named-input table; both
  elaborate to declaration order before lowering;
- region bodies receive immutable named parameters as `p`; plural bodies receive
  `(p, c)`. Each cached `BoundExit` supports `c:name(value)` invocation and
  `c.name` forwarding. Input and exit names disappear before checking/lowering;
- after `C.jit`, the same func value carries `host_runtime` and applying it
  invokes the native symbol (`Runtime:invoke`).

One object, two phase-correct meanings, no second symbol table.

## 3. The three IR layers

| Layer | Shape | Produced by |
|-------|-------|-------------|
| Staging IR | `{ stmt = "..." }` statements, `{ kind = "..." }` expressions, `Place_mt` places | source_env |
| Checked IR | `{ op = "..." , type = ... }` statements/exprs, typed places | check_machine |
| Lowered IR | register numbers, block ids, terminator tuples `{ "br", id }` | lower_machine |
| C text | ordinary C | codegen |

**Check** (`check_machine`) is a keyword table built by `label.lua`
(`def_check: stmt (stmt) ...`), dispatched by tag:
`self[s.stmt]` / `self[e.kind]` / `self[p.place]`. It types everything, builds
the checked IR, and enforces termination: `is_terminator` recurses through
`if_`/`call`/`seq` and rejects any body, block, or branch whose last statement
is not a jump, exit, return, or call. Diagnostics are collected per function
(`in run: ...`) and returned as a list — the only error channel that returns
`(nil, errors)`.

**Lower** (`lower_machine`) is the same keyword-table pattern
(`def_lower: op (typed) ...`). It allocates SSA-ish virtual registers
(`newreg`), blocks (`newblock`), and lays out terminators:

```text
br      goto block
brc     conditional branch
ret     return register (direct)
retn    return ordinal + optional out-param (sealed multi-exit)
tail    tail call (jump to a func's entry)
calln   sealed multi-exit call: jump into handler blocks with a result slot
switch  dense C switch to block ids
```

Block bodies lower into `{ code = {...}, term = {...} }`; the func carries the
block list, so label threading is flat C control flow (no function calls per
transition).

**Codegen** (`codegen`) emits deterministic C:

- header includes, forward typedefs, then aggregates in dependency order
  (recursive value layout is rejected; recursion goes through pointers);
- opaque forward declarations (`struct Tag;`) collected from signatures;
- `static` globals with Lua-built initializers (`init_c`: number, string
  literal, or table of numbers);
- prototypes for externs, then for funcs;
- bodies: locals for virtual registers (`rN`), one `B%d:` label per block,
  opcode lines, and the terminator.

Two helpers shape the C: `ctype(T)` renders types; `LV(lval)` renders lvalues
(`rN`, `base[index]`, `base.field`, `rN->field` when the base is a deref,
`*rN`, named globals). `sig(f)` renders the ABI: a direct func returns its
result type; a sealed multi-exit func returns `int` and appends one
`T *kN_out` parameter per value-carrying exit. Exit names define the source
protocol; declaration-order ordinals define the C ABI. The emitted C carries no
runtime handler table. This is the exact contract the TCC runtime mirrors.

## 4. The TCC runtime

`C.jit(build, options)` compiles the same source text, then returns the
namespace immediately. Native code appears lazily on the first exported-func
call.

`cblock_tcc.lua` is a thin libtcc binding: `tcc_new`, set error callback and
options, `tcc_add_symbol` for each host FFI pointer in `options.symbols`,
`tcc_compile_string`, `tcc_relocate`, then `tcc_get_symbol`. The Session owns
the relocated state and its cached function pointers; `Session:free()` deletes
it (pointers become invalid).

The `Runtime` metatable (in cblock.lua) mediates between Lua and the Session:

- `ensure_ffi` emits FFI typedefs for the exported aggregates on demand, in
  dependency order, so by-value struct parameters/results keep their C ABI
  shape;
- `function_type(f)` renders the host call type — direct funcs return their
  result; multi-exit funcs return `int` with one out-parameter per
  value-carrying exit;
- `function_pointer(f)` cooks the module once (`ensure_native`) and caches the
  pointer;
- `invoke(f, ...)` converts Lua table arguments to FFI structs and calls the
  pointer; a multi-exit func allocates out-params, translates the returned ABI
  ordinal through the declaration, and returns `(exit_name, value)`;
- `attach(root)` walks the returned namespace and stamps `host_runtime` on the
  func and struct values so their `__call`/`__index` become host operations.

The whole module cooks in one libtcc state, so calls among generated functions
stay in one coherent native world. TCC prioritizes compile latency; the same
text through GCC is the optimization path.

## 5. Places, pipelines, and value threading

Places are `Place_mt` values (`var`, `at`, `member`, `deref`, `global`) with
metamethods: arithmetic/comparison auto-load, `__index` auto-indexes member
fields and resolves the builder methods (`:load :store :at :address :deref`),
reading the type with `rawget` so a nil-typed place cannot re-enter `__index`.
The free functions (`load`, `store`, `address`, `at`, `deref`) share the same
module-level builders — method and free forms are one implementation.

Pipelines are builder objects over a shared producer: `range` is the producer;
`Stream_mt:load(ptr)` and `zip` project streams; `map` composes; `store` and
`reduce` materialize one fused C loop at lowering time (`pipeline_store`,
`pipeline_reduce`). There is no intermediate vector: the emitted C is an
ordinary scalar loop and GCC `-O3` owns vectorization.

## 6. Error model

- **Staging** misuse raises Lua errors (`region X recursively emits itself; use
  call(region)`, `result position expects one CBlock type`, `block declared outside
  a func`, missing/extra parameter or continuation names).
- **Check** collects diagnostics and `compile` returns `(nil, errors)`; errors
  name the owning function (`in run: ...`).
- **Codegen** asserts internal invariants (a terminated machine, no recursive
  value layouts).

## 7. Enforced invariants

The architecture makes these structural, not advisory:

1. Bodies are statement lists; every block path terminates (checked).
2. All callable value inputs are unique ordered `param: name (type)` declarations.
   Functions, externs, and direct regions curry one native result type after that
   product. Alternative regions carry named continuations among their parameters;
   bodies receive `p`, and plural protocols add `c`. Calls may use positional
   input sugar, but all inputs elaborate to declared names and order.
   `set_signature` with guidance to use `ptr()`).
4. Regions inline unless sealed; recursion crosses `call(region)`.
5. Field order is the written order; Lua table iteration is never an ordering
   contract.
6. Kind checks use metatable identity, never field-name sniffing:
   `lift` recognizes places by `getmetatable(v) == Place_mt`, `if_` value
   branches by `Expr_mt`/`StructExpr_mt`, and `Place_mt.__index` reads the
   type with `rawget` so `__index` stays total and non-recursive.
   Struct fields shadow builder-method names.
7. Namespace paths are the only way to C ABI names; externs must be exported.
8. One source text feeds GCC and TCC — the two paths cannot diverge.
