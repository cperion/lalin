# Lalin - Agent Guidance

Lalin is a LuaJIT-hosted dialect of the LLBL language. Lua is the
metaprogramming layer. LLBL is the central extensible language workbench and
bootstrap language: heads, roles, fragments, namespaces, origins, diagnostics,
formatting, indexing, dialect extension, and generic regions. Lalin is the compiled
language dialect that lowers typed programs through `CBackendUnit` to `emit_c`.
The main JIT-like path cooks emitted C with GCC and exposes function pointers
through LuaJIT FFI; the same emitted C is the AOT path. Native C-stencil
copy-patch / binary patchers are retired and must not be reopened; only the
stencil/CMat vocabulary survives as the deterministic emitted-C shape contract.
The runtime path is emitted C cooked with GCC only; LuaJIT bytecode emission is retired.

Before compiler/schema work, read `docs/ASDL_GUIDE.md`. Those rules are
binding: ASDL reasoning first, leaf ASDL methods own semantics, no
class/kind/action dispatch, no generic context bags, no `any`/`table`/`map` type
escape hatches, no ad hoc Lua constructor payloads, and no compatibility shims.

## ASDL Method Doctrine

Compiler semantics must be organized around correct ASDL schema ownership.
Define precise ASDL products for records/state and ASDL unions for alternatives
before writing implementation logic. The schema is the vocabulary; Lua methods
only explain the behavior of that vocabulary.

Type and dispatch belong in ASDL, not in Lua control code. If compiler code
needs to classify a value, choose among alternatives, remember facts by node, or
route to an implementation, that is schema pressure. Add the missing ASDL sum,
product, typed field, projection, or leaf method. Do not encode type or dispatch
with Lua tables, strings, booleans, handler maps, side maps, or external caches.
Do not use an ASDL `map` field to hide the same side table in the schema; model
keyed relations as named entry products carried under `many`.

When implementation pressure appears, go back to ASDL first. If code seems to
need a side table, manual dispatch, a large mutable context, optional fields
used as protocol soup, hidden fields, string tags, or ad hoc result records, stop
editing implementation code and fix the ASDL schema. Add the missing product,
union, leaf, field, or typed result, then write the leaf method. The answer to
unclear compiler semantics is almost always more precise ASDL, not more Lua
plumbing.

Treat side tables and manual dispatch as architecture bugs, not implementation
shortcuts. They mean the schema failed to name a type, phase fact, projection,
facet, or result. Fix that failure at the ASDL layer before continuing.

For each ASDL union operation, install the method on every concrete union leaf
that supports the operation. The leaf implementation is the dispatch. This is
the required shape:

```lua
function Tree.ExprCall:typecheck(input)
  return Tree.TypeExprResult(...)
end

function Tree.ExprInt:typecheck(input)
  return Tree.TypeExprResult(...)
end
```

Do not write this shape:

```lua
local handlers = {
  ExprCall = function(expr, input) ... end,
  ExprInt = function(expr, input) ... end,
}

function typecheck_expr(expr, input)
  return handlers[expr.kind](expr, input)
end
```

Parent union methods are only shared defaults or explicit delegation contracts.
They must not inspect child classes, `kind` strings, action names, tags, or
selector tables to decide behavior. If a parent method would need that kind of
branch, move the branch to the relevant leaf methods or fix the ASDL shape.

Inputs and results for semantic methods must be explicit ASDL products or other
named ASDL values. Do not pass generic `ctx`, `env`, `state`, option bags,
hidden Lua fields, or loose tables through migrated compiler semantics. If an
operation needs data, model that data in the schema with a precise product name.

ASDL constructors in migrated compiler semantics must consume ASDL values and
primitive scalar fields declared by the schema. Do not pass ad hoc Lua records
as constructor payloads to smuggle untyped state through a typed node. If a
constructor argument is conceptually a record, decision, capability, fact,
context, buffer, payload, or result, define that record as an ASDL product or
union and pass that ASDL value.

Large mutable context products are also a schema smell. ASDL inputs should be
narrow stage-specific products with named fields that explain exactly why each
piece of data is present. Do not replace a Lua context bag with an ASDL context
bag.

Side tables are not semantic state. A Lua table keyed by ASDL nodes, symbols,
classes, tags, handles, or strings is forbidden when it carries compiler facts,
decisions, diagnostics, lowering results, type facts, layout facts, control-flow
facts, or backend facts. Those facts must be fields of named ASDL products or
members of named ASDL unions.

Ad hoc Lua result records are forbidden in migrated semantic code. Do not return
`{ kind = ... }`, `{ ok = ... }`, `{ tag = ... }`, `{ action = ... }`, or
untyped report/decision tables from compiler semantics. If an operation can
succeed, fail, reject, choose, classify, or explain, define an ASDL union/product
for that result and return its constructor.

Optional soup is forbidden. Do not model semantic alternatives as one product
with many nullable fields, boolean switches, mode strings, or mutually-exclusive
option clusters. Use an ASDL union whose leaves represent the alternatives, and
put behavior on those leaves.

Nil passthrough is forbidden. Do not let `nil` mean success, failure, absence,
unknown, unsupported, default, unchanged, no-op, or "keep going" by convention.
If absence is a real field property, declare `optional [T]` and handle it
locally. If nil represents a semantic alternative or decision, define an ASDL
union leaf such as `Missing`, `Rejected`, `Unsupported`, `Unchanged`, or a more
precise domain name. A method may return nil only when the parent ASDL method
contract explicitly says "operation not supported by this leaf" and the caller
handles that exact contract.

Manual dispatch is forbidden even when it looks small or temporary. Do not use
`schema.classof(x)`, `x.kind`, `x.tag`, string action names, enum-like Lua
fields, handler maps, visitor tables, rule tables, or `if/elseif` chains to pick
behavior for ASDL variants. Add or call a method on the ASDL union leaf instead.

Missing behavior must be visible as a missing leaf method, a typed reject, or a
typed diagnostic. Do not add compatibility shims, fake visitors, rule runners,
or fallback dispatch just to preserve old behavior during the rewrite.

### Terra ASDL Pattern

Lalin is intentionally copying the useful Terra ASDL pattern from
`/home/cedric/dev/terra-compiler-pattern/terra/src/asdl.lua` and the vocabulary
in `/home/cedric/dev/terra-compiler-pattern/docs/minimal-asdl-vocabulary.md`.
Use those as the model for schema-first compiler design, with Lalin's stricter
rewrite doctrine layered on top.

The Terra ASDL runtime pattern to preserve:

- A context defines a closed schema vocabulary before implementation code runs.
- Products are checked records with named fields.
- Sums create a parent class plus concrete constructor classes.
- Nullary constructors are still ASDL values/classes, not string cases.
- Sum parent membership is for type checking and shared defaults, not for
  handwritten variant dispatch.
- Assigning methods to ASDL classes is the extension mechanism; compiler
  semantics belong on those classes.
- `unique` products/constructors express identity and interning. Use identity in
  the schema instead of maintaining external node-keyed semantic caches.

The Terra architectural vocabulary to copy:

- **Entity**: a stable user/compiler-visible thing with identity.
- **Variant**: a real domain alternative; model it as an ASDL sum, never a
  string tag plus optional fields.
- **Projection**: a derived phase shape. Do not mutate or bloat source ASDL to
  carry later-phase facts.
- **Spine**: a shared alignment/header product carrying identity, topology,
  order, addressability, or ranges for later branches.
- **Facet**: one semantic plane aligned to a spine. Split layout/type/control/
  lowering/backend facts into precise facets instead of one giant context or
  lower node.

Source ASDL and lower ASDL have different jobs. Source schemas model authored
language facts. Lower schemas model consumed decisions, resolved names, layout,
control, schedules, machine plans, and backend artifacts. If a pass discovers a
new phase-local fact, create a projection/spine/facet product or result union
for it; do not attach it through side tables, hidden fields, or optional soup.

Some old Terra pattern example code still uses Lua `kind` branches inside
boundary implementations. Do not copy that part into migrated Lalin compiler
semantics. Copy the ASDL schema discipline and class/method extension mechanism;
then apply Lalin's rule that concrete union leaf methods own behavior.

LLBL bootstraps itself in plain Lua. `lua/llbl.lua` is the stage-0 kernel;
`lua/llbl/bootstrap.lua` defines the stage-1 `llbl` dialect and installs the
public `llbl.grammar` facade. The preserved stage-0 grammar is
`llbl.kernel.grammar`.

The bare `llbl` member is the identity of language composition. It provides shared
mechanics: source/generated symbols, origins, diagnostics, fragments, regions,
formatting docs, and language-level symbol bindings. Dialects own semantic
meaning.

The active fast path is GCC over `emit_c` output: `CBackendUnit -> emit_c -> gcc
-shared/-O3 -> dlopen/dlsym -> LuaJIT FFI function pointer`. `emit_c` is also the
AOT artifact path. Fused emitted C + GCC -O3 is the performance path; generic
fusion is a typed decision over the exact emitted shape plus declared
memory/noalias/bounds facts, with contracts recomputed after fusion. The
The binary copy-patch / binary-bank backend is deleted and must not be reopened.
Only the stencil/CMat vocabulary survives as the deterministic emitted-C shape
the stencil/CMat vocabulary survives as the deterministic emitted-C shape
contract (`schema_v2/stencil.lua` -> CMat fragment path -> `emit_c`). The LuaJIT
bytecode path (`opts.luajit`, `opts.bytecode`, `compile_luajit`) is removed: only
emitted C cooked with GCC remains, plus the explicit LuaJIT FFI function-pointer
boundary. The old Cranelift/Rust runtime path is not part of the current architecture.

## Build

```sh
make
```

`make gcc` builds the vendored GCC C compiler under `.vendor/gcc/.local` when a
local GCC is desired for the `emit_c` cooking path. The main runtime C path uses
GCC/cc to compile emitted C into a shared object and then `dlopen`s it.
Native copy-patch bank generation is retired; it has no prebuild flow and must not be reopened.

## Authoring Lalin Code

### Primary surface — `.lln` declaration documents (hand-written)

The current hand-written surface is a `.lln` declaration document loaded through
`lalin.loadfile` / `lalin.loadstring`, not a mixed Lua file and not the old
`llbl.syntax` `lalin fn` island syntax.

```lua
local lalin = require("lalin")

local decls, doc = assert(lalin.loadfile("demo.lln"))
local session = lalin.compile_c_gcc("demo", decls, {
  gcc_opts = { opt = 3, out_dir = "target/demo" },
})

local add = assert(session:symbol("add", "int32_t (*)(int32_t, int32_t)"))
print(add(3, 4)) -- 7
session:free()
```

Inline `.lln` source uses bracket type syntax and `do ... end` bodies:

```lua
local lalin = require("lalin")

local decls = assert(lalin.loadstring([[
struct Pair
  x [i32]
  y [i32]
end

fn add(a [i32], b [i32]) [i32] do
  return a + b
end
]], "@demo.lln"))
```

Important parsed-surface rules:

- Root files are declaration documents: `fn`, `extern`, `struct`, `union`,
  `handle`, `region`, and top-level HostEval declaration splices.
- Types are bracket escapes: `x [i32]`, `p [ptr [i32]]`, `xs [view [i32]]`.
- Function bodies use `do ... end`.
- Top-level Lua chunk forms (`local`, `return`, `module`, parse-time `import`)
  are rejected in `.lln` documents.
- The old examples shaped like `lalin fn add(a: i32, b: i32): i32` are stale.

### Builder API — Lua/LLBL DSL (macros, generators)

Use the Lua DSL for programmatic construction. Prefer explicit namespaces in
examples instead of installing globals:

```lua
local lalin = require("lalin")
local lln = lalin.lln

local add = lln.fn. add { a [lln.i32], b [lln.i32] } [lln.i32] {
  lln.ret (a + b),
}

local session = lalin.compile_c_gcc("demo", { add }, {
  gcc_opts = { opt = 3, out_dir = "target/demo" },
})
local add_fn = assert(session:symbol("add", "int32_t (*)(int32_t, int32_t)"))
print(add_fn(3, 4)) -- 7
session:free()
```
The compiled module is always materialized as emitted C. Compile and link it
through GCC with `compile_c_gcc` (the example above), or emit the C text for an
AOT build. There is no LuaJIT bytecode module path.

## Test

Tests are standalone LuaJIT scripts:

```sh
luajit tests/run.lua
luajit tests/run.lua frontend
luajit tests/run.lua schema_v2
luajit tests/run.lua c_backend
```

Useful focused checks:

```sh
luajit tests/c_backend/test_cmat_counted_fragment_gcc.lua
luajit tests/c_backend/test_stencil_c_gcc.lua
luajit tests/c_backend/test_compile_c_gcc_fresh_process.lua
luajit tests/compiler_process/test_compiler_driver.lua
```

## Architecture

Two authoring paths converge on one pipeline:

### Primary (hand-written)
```text
.lln declaration document
  -> lalin.loadfile/loadstring
  -> lalin.loader + lalin.syntax.document
  -> ordered parsed declaration array
  -> lalin.syntax.to_module()
  -> LalinTree ASDL
```

### Builder API (macros/generators)
```text
Lua source
  -> Lua values
  -> LLBL staged heads
  -> Decl values, Decl:syntax()
  -> LalinTree ASDL
```

### Shared backend
```text
LalinTree ASDL
  -> typecheck
  -> LalinCode facts
  -> kernel and schedule facts
  -> CBackendUnit
  -> emit_c output
  -> GCC shared object + dlopen for JIT-like execution
     or user-owned AOT C build
  -> loaded module / function pointers / artifact
```

Key files:

```text
lua/llbl.lua                       LLBL extensible language workbench substrate
lua/lalin/dsl/                    Lalin authoring heads
lua/lalin/schema_v2/              canonical ASDL/schema definitions
lua/lalin/impl/                   compiler phase and backend methods
lua/lalin/impl/compiler_api.lua   public compiler API implementation
lua/lalin/impl/lower_emit_c/      CMat environment, fragment, and assembly
lua/lalin/impl/cemit_emit.lua     CBackendUnit C emission
lua/lalin/impl/cemit_emit.lua     CBackendUnit C emission
```

## Key Docs

```text
docs/ASDL_GUIDE.md          binding ASDL modeling doctrine
docs/LLBL_GUIDE.md          central LLBL workbench and region guide
docs/LANGUAGE_REFERENCE.md public Lalin language reference
docs/ARCHITECTURE.md       active compiler and backend architecture
docs/CMAT_MEMORY_COORDINATE_ARCHITECTURE.md
                           fused memory-coordinate design authority
docs/SCHEMA_V2_IMPL_MASTER_PLAN.md
                           concise active compiler queue
docs/SCHEMA_OWNERSHIP.md   schema ownership and cutover guard
docs/CONVENTIONS.md        naming, style, and repository conventions
docs/DESIGN_BIBLE.md       long-form design philosophy
```

## Non-Negotiable Rules

1. LLBL is the workbench; Lalin is the compiled language member.
2. Lua owns genericity; Lalin receives monomorphic values.
3. Types are evaluated Lua values in `[]`.
4. No angle-bracket type arguments.
5. No source-level `for`, `while`, `break`, or `continue`.
6. Every block path terminates.
7. Switches require a default arm and have no fallthrough.
8. `region.` is generic LLBL control syntax; Lalin consumes it.
9. Pull-shaped work is a region protocol lowered through GPS.
10. Backend facts must be explicit ASDL.
11. No compatibility shims for removed surfaces.

## Working Notes

Use `rg` for searches. Do not revert user changes. Ignore `museum/gps.lua`
unless the user explicitly asks to work on it.

## ASDL Philosophy Prompt

The project includes a prompt template at `.pi/prompts/asdl.md` that turns any pi
agent into an ASDL/Lalin design guru. Type `/asdl` in the editor to inject the full
doctrine from `docs/ASDL_GUIDE.md` and `docs/DESIGN_BIBLE.md` into your prompt.

Use this when reasoning about schema design, dispatch architecture, semantic
separation, or any question where the ASDL doctrine is the authority. Team members
working on compiler semantics should invoke `/asdl` before making architectural
decisions.

## Herdr — Team Communication Cheatsheet

We use herdr for multi-agent coordination. All agents work in the same
workspace (`w4`) at `/home/cedric/dev/lalin`. Each agent is a pane (terminal split).

### Status
```bash
herdr pane list --workspace w4    # all panes + agent_status (idle/working/done)
herdr pane list --workspace w4 | python3 -c "
import sys,json; d=json.load(sys.stdin)
for p in d['result']['panes']:
    print(f'{p[\"pane_id\"]} {p[\"agent_status\"]}')"
```

### Send text to a running agent
```bash
herdr pane send-text <pane_id> \"your message\"
herdr pane send-keys <pane_id> Enter    # press Enter to submit
```
`send-text` types into the terminal. `send-keys` presses keys (Enter, escape, etc.).
Use this to send prompts to a running `pi` agent.

### Read agent output
```bash
herdr pane read <pane_id> --source recent --lines 30        # recent scrollback
herdr pane read <pane_id> --source visible --lines 30       # current viewport
herdr pane read <pane_id> --source recent-unwrapped --lines 30  # joined wraps
```
`--source recent-unwrapped` joins soft-wrapped lines, best for matching text.

### Wait for agent state
```bash
herdr wait agent-status <pane_id> --status done --timeout 300000  # wait 5 min
herdr wait agent-status <pane_id> --status idle --timeout 10000   # 10 sec
```
Status values: `idle`, `working`, `blocked`, `done`, `unknown`.

### Wait for output text
```bash
herdr wait output <pane_id> --match \"ready\" --timeout 30000
herdr wait output <pane_id> --match \"error.*line\" --regex --timeout 60000
```

### Split panes (spawn teammates)
```bash
# Split current pane right, get new pane ID
NEW=$(herdr pane split w4:p1 --direction right --no-focus | python3 -c \"
import sys,json; print(json.load(sys.stdin)['result']['pane']['pane_id'])\")

# Start pi in the new pane
herdr pane send-text \"$NEW\" \"pi\" && herdr pane send-keys \"$NEW\" Enter
```

### Run a shell command in a pane
```bash
herdr pane run <pane_id> \"ls -la\"     # runs command, NOT pi input
```
Note: `pane run` executes a shell command. For pi input, use `send-text` + `send-keys`.

### Tab management
```bash
herdr tab create --workspace w4 --label \"agents\"    # new tab
herdr tab list --workspace w4
```

### Close
```bash
herdr pane close <pane_id>
```

### Current layout (known panes)
| Pane | Who |
|------|-----|
| w4:p1 | Coordinator (us) |
| w4:p7 | ASDL Guru |
| w4:pZ | Parser rewrite agent |
