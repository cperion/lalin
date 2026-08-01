# LLBL-First Role-Directed Bracket Evaluation

**Status:** active migration. Kernel HostEval and role vocabulary are present;
parsed syntax still carries a temporary dual HostEval/HostEscape path.
## Goal

Enable `[]` to be LLBL's single role-directed host-evaluation surface across
parsed Lalin syntax and Lua DSL syntax: a bracket occurrence delivers a
kernel-owned `HostEval` event, the surrounding LLBL role determines how the
evaluated Lua value adapts, and LLBL role algebra owns insertion, splicing,
origins, and diagnostics.

## Decision

We choose **Approach A: Kernel-Owned HostEval and Role Algebra**.

Migration safety is secondary. Lalin is not yet broadly used, so the design
should optimize for architectural cleanliness instead of preserving accidental
legacy shapes. The target is a single LLBL-first semantics:

```text
[] delivers a HostEval event.
The current role adapts the produced Lua value.
Role algebra decides whether the result is inserted or spliced.
```

## Incentives

The current implementation splits bracket behavior across unrelated mechanisms.
Parsed `.lln` brackets are Lalin-local `HostEscape` nodes evaluated by
`lua/lalin/syntax/ast.lua`, then interpreted ad hoc by separate lowering paths
in `syntax/init.lua` and `syntax/to_tree.lua`. Lua DSL brackets are Lua
`__index` events classified as `index:type`, `index:value`, etc. before role
normalization, which prevents values such as declarations from adapting to type
roles.

Fragment/spread behavior is duplicated between generic LLBL and Lalin-specific
custom role regions. Generic LLBL spread compatibility currently compares plain
role strings, which cannot express Lalin's container/item distinction such as
`decls` containing `decl` fragments.

The redesign removes these semantic splits: LLBL owns the bridge, role algebra,
fragments, splicing, origins, and diagnostics; dialects provide role meaning.

## Current State

### LLBL kernel primitives

`lua/llbl.lua` already defines much of the needed vocabulary:

- `llbl.fragment(role, items, origin, spec)`
- `llbl.spread(value)`
- `llbl._`, whose call form creates a spread wrapper
- role normalization for kinds such as `name`, `type`, `expr`, `array`,
  `record`, `product`, `sum`, and `protocol`
- generic spread expansion through `spread_region`

Fragments currently carry only a plain string role:

```lua
{
  __llbl_tag = "Fragment",
  role = tostring(role),
  items = items,
  origin = ...,
}
```

Generic spread currently requires exact string equality:

```lua
if v.role ~= role_name then
  llbl.fail("cannot spread " .. tostring(v.role) .. " fragment into " .. tostring(role_name) .. " role", ...)
end
```

This is too weak. Lalin has plural/container roles such as `decls`, `stmts`, and
`params`, while its fragments use item roles such as `decl`, `stmt`, and
`product`.

### Lua DSL path

`lua/lalin/dsl/init.lua` defines Lalin roles and slots using LLBL heads:

```lua
g.role .decls  (role_array("decl", "declaration"))
g.role .stmts  (role_array("stmt", "statement"))
g.role .params (role_array("product", "product"))
g.role .conts  (conts_role)
g.role .variants (variants_role)
g.role .value  { kind = "value" }
```

Slots map Lua syntax channels to expected roles:

```lua
slot_type  -> index:type
slot_decls -> call:table
slot_stmts -> call:table
slot_params -> call:table
```

For example:

```lua
lln.fn. add { a [lln.i32], b [lln.i32] } [lln.i32] { ... }
```

uses Lua `[]` syntax, not parsed Lalin syntax. The Lua operand has already been
evaluated before LLBL receives it.

The hidden limitation is that slot/channel admission currently happens before
role adaptation. A value that could adapt to a type, such as a declaration
value, may be classified as `index:value` and rejected by a slot expecting
`index:type`. Role-directed adaptation never gets a chance to run.

Lalin also implements custom spread behavior in addition to generic LLBL spread
behavior. Its array/list expansion accepts explicit `Spread` wrappers and often
bare matching `Fragment` values. This duplicates kernel responsibilities and
creates semantic drift.

### Parsed syntax path

`lua/llbl/syntax/driver.lua` discovers parsed islands and rewrites them to
constructor invocations:

```lua
__llbl_syntax.invoke(chunk_id, id, env_source)
```

`lua/llbl/syntax/constructor.lua` passes captured lexical refs into the
parser/build function. Lalin then creates parsed AST nodes.

Parsed host escapes are currently Lalin-local:

- `lua/lalin/syntax/type.lua`
  - type positions require `[ ... ]`
  - produce `Ast.node("HostEscape", { kind = "type", source = raw, refs = refs })`
- `lua/lalin/syntax/expr.lua`
  - expression atoms accept `[ ... ]` as `HostEscape`
  - postfix `expr[index]` remains ordinary parsed index syntax
- `lua/lalin/syntax/stmt.lua`
  - there is no direct statement-level host-eval node
  - bare `[body]` parses as an expression statement containing `HostEscape`

`lua/lalin/syntax/ast.lua` evaluates host escapes using:

```lua
loadstring("return (" .. src .. ")")
```

and mutates the parsed node with:

```lua
n.value = Ast.eval_lua_expr(...)
n.resolved = true
```

Lowering then interprets resolved host escapes differently depending on where
they appear:

- expression lowering adapts literals, ASDL expressions, `ExprFragment`, or
  tagged parsed nodes
- type lowering calls `TypeValue.type(value)` and recursively lowers tagged
  parsed type nodes
- statement lowering special-cases `StmtExpr(HostEscape)` and calls
  `stmt_splice`
- declaration collection accepts parsed declarations and arrays of parsed
  declarations, but not top-level host escapes/fragments

There is also an inconsistency: `lua/lalin/syntax/init.lua` has
declaration-to-type projection for parsed declarations such as `DeclStruct`,
`DeclUnion`, and `DeclHandle`, but `lua/lalin/syntax/to_tree.lua` does not
consistently expose the same projection.

## First Principles

The bracket form itself does not mean "type", "expression", "statement", or
"declaration". It means "evaluate host Lua and offer the result to the current
LLBL role."

The role determines meaning:

```text
current role + HostEval
  -> evaluate or receive Lua value
  -> adapt value to expected role
  -> insert one item or splice many items according to role algebra
```

Parsed and Lua channels remain mechanically distinct:

- parsed `.lln` brackets carry source text, captured refs, origin, and an
  evaluation thunk
- Lua DSL brackets carry an already evaluated Lua value delivered through Lua
  `__index`

They unify at the LLBL event/role layer, not by pretending their syntax
mechanics are identical.

## Kernel-Owned Responsibilities

LLBL owns the following concepts in `lua/llbl.lua` and related LLBL syntax
modules.

### `HostEval`

A new LLBL-tagged value/event:

```lua
llbl.host_eval {
  channel = ...,       -- parsed:escape, index:host, etc.
  origin = ...,        -- bracket/index source origin
  source = ...,        -- parsed Lua source, when applicable
  refs = ...,          -- captured lexical refs, when applicable
  thunk = ...,         -- parsed-channel evaluator, when applicable
  value = ...,         -- already evaluated Lua value, when applicable
  evaluated = ...,     -- evaluation state
}
```

Required constructors:

```lua
llbl.host_eval.parsed(source, refs, env_fn, origin, spec)
llbl.host_eval.lua(value, channel, origin, spec)
llbl.is(value, "HostEval")
```

A parsed-channel `HostEval` evaluates Lua source under captured lexical
environment. A Lua-channel `HostEval` wraps an already evaluated Lua value.

### Role descriptors

LLBL roles become explicit descriptors rather than only loose role names:

```lua
llbl.role_descriptor {
  id = RoleId(owner, name),
  algebra = "single" | "list" | "product" | "sum" | "protocol" | "record" | "optional",
  item_role = RoleId(...),
  fragment_role = RoleId(...),
  payload_role = RoleId(...),
  adapter = function(ctx, value, origin) ... end,
  splice_policy = ...,
  nil_policy = ...,
}
```

The exact Lua representation may be table-based, but the semantic fields are
required.

### Role identity

Role identity is dialect/member-qualified:

```text
RoleId = owner/member identity + role name
```

This replaces plain string compatibility. A `stmt` fragment from one dialect
must not silently splice into another dialect's `stmt` role unless
compatibility is declared by the role descriptors.

### Generic role normalization

LLBL owns the normalization entrypoints:

```lua
llbl.role.normalize(ctx, role_id, input)
llbl.role.adapt(ctx, role_id, value, origin)
llbl.role.collect(ctx, container_role_id, input)
llbl.role.splice(ctx, container_role_id, fragment_or_spread, origin)
```

These functions replace ad hoc parsed lowering behavior and custom per-dialect
spread islands.

### Generic splicing

LLBL role algebra decides whether a role is list-like and whether a value may
splice. List/product/sum/protocol roles define:

- their container role
- their accepted item role
- their accepted fragment role
- whether bare fragments splice
- whether explicit `Spread` is required or optional in that channel

Parsed source uses `[fragment]` as the normal splice form in list-like roles.
Lua DSL may continue to use `spread(fragment)` and `_(fragment)` because Lua
table syntax has no native parsed splice form.

### Diagnostics and origins

LLBL diagnostics must carry:

- bracket/index origin
- parsed source span or Lua-channel origin
- expected role id
- role algebra kind
- produced value tag/class, if known
- produced fragment role id, if known
- fragment creation origin
- channel name
- adapter failure reason

Adapted ASDL products should inherit or reference the bracket origin so generated
code and diagnostics point back to the `[]` site.

## Dialect-Owned Responsibilities

Dialects own semantic adaptation. Lalin supplies adapter functions installed
into LLBL role descriptors for roles such as:

- `type`
- `expr`
- `stmt`
- `decl`
- `product` / field roles
- `variants`
- `conts`
- `value`

For Lalin, these adapters define:

- which Lua values count as Lalin types
- how parsed declarations project to type identities
- how handle declarations project to handle types
- how literals adapt to expressions
- how parsed AST nodes lower into ASDL nodes
- how ASDL values from another schema context are projected into the active
  context
- which table shapes are valid fragments/lists
- nil behavior per role
- duplicate-field or duplicate-variant checks after splicing

Dialect ownership means Lalin decides that a `DeclStruct` with a stable name may
adapt to a `type` role. LLBL decides how that value is routed, checked, spliced,
and diagnosed.

## HostEval Events By Channel

### Parsed channel

Parsed brackets produce `HostEval`:

```lln
fn f(x [i32]) [i32]
  return [make_expr(x)]
end
```

The parser records source text, refs, and origin. The surrounding parser context
supplies the expected role.

Examples:

```lln
[make_decls()]          -- declaration stream role

struct Packet
  [header_fields]       -- product/field role
  payload [ptr [u8]]
end

fn copy(...) [void]
  [body]                -- statement-list role
  return
end
```

Parsed postfix indexing remains ordinary parsed Lalin syntax:

```lln
a[x]         -- parsed expression index
[make()][i]  -- host eval expression, then parsed postfix index
```

Nested brackets inside host source remain Lua source, not parsed Lalin brackets:

```lln
[ptr [Pair]]
```

Here the inner `[Pair]` is Lua `__index` syntax inside the host Lua expression.

### Lua channel

Lua DSL brackets still use Lua indexing syntax:

```lua
lln.fn. add { a [lln.i32], b [lln.i32] } [lln.i32] { ... }
```

The LLBL runtime must admit bracket/index events into role normalization instead
of rejecting them solely by preclassified channel such as `index:type` versus
`index:value`.

The slot says the expected role. The role adapter decides whether the Lua value
can become that role.

This enables declaration-to-type adaptation in Lua DSL brackets as well as
parsed brackets when the target role is `type`.

## Container, Item, And Fragment Roles

The target model distinguishes these concepts explicitly:

| Concept | Meaning | Example |
|---|---|---|
| container role | the surrounding role that collects zero or more things | `Lalin.decls` |
| item role | the role of one accepted element | `Lalin.decl` |
| fragment role | the role carried by a reusable fragment | `Lalin.decl` |
| algebra | how the container combines items | list/product/sum/protocol |

A `decls` role may accept one `decl` item or splice a `decl` fragment. It should
not require the fragment role string to equal `"decls"`.

This fixes the current mismatch where LLBL generic `spread_region` compares
`Fragment.role` directly to the container role name.

## Splicing Semantics

For a list-like role:

```text
HostEval result adapts to one item
  -> insert one item

HostEval result adapts to a compatible fragment
  -> splice fragment items

HostEval result adapts to a compatible array/list
  -> adapt each element under the item role, then insert in order

HostEval result cannot adapt
  -> role mismatch diagnostic
```

Splicing is role-local. Plain Lua tables do not receive a global meaning. A
table in a declaration role may mean a declaration list; a table in expression
role may be a literal, unsupported value, or dialect-specific expression form
depending on that role adapter.

Generated declaration order must be deterministic. Positional arrays are ordered.
Keyed Lua tables must not silently become ordered declaration streams unless the
declaration role explicitly defines that behavior.

## Source-Shape Implications

Parsed Lalin gains bracket support wherever the parser can assign a current
role:

- declaration streams
- statement blocks
- product/field blocks
- type positions
- expression atoms
- continuation/protocol positions, where applicable

A bracket occurrence without an expected role is invalid. The design does not
create ambient "anything anywhere" evaluation.

`spread` and `_` remain useful Lua DSL helpers:

```lua
lln.stmts { _(fragment) }
```

But parsed `.lln` should normally use:

```lln
[fragment]
```

in a list-like role.

## Migration Phases

Migration is phased for engineering control, not because legacy semantics are
primary.

1. **Name kernel concepts**
   - Add `HostEval`, role descriptors, qualified role ids, and diagnostic
     vocabulary in LLBL.
   - Keep parsed and Lua channels distinct.

2. **Change slot admission**
   - Add host-capable index/bracket channel handling.
   - Defer bracket meaning to role normalization.
   - Prevent greedy slot ambiguity by using the expected slot role, not raw
     value shape, as the semantic discriminator.

3. **Port Lalin role descriptors**
   - Define Lalin descriptors for `type`, `expr`, `stmt`, `decl`, `decls`,
     `stmts`, `product`, `params`, `variants`, and `conts`.
   - Encode container/item/fragment relationships explicitly.

4. **Convert parsed HostEscape**
   - Replace or wrap Lalin `HostEscape` as LLBL `HostEval`.
   - Remove role-specific `HostEscape` branches from expression/type/statement
     lowering once equivalent adapters exist.

5. **Move adaptation into role adapters**
   - Consolidate expression, type, statement, declaration, and product
     adaptation.
   - Move declaration-to-type projection into the Lalin `type` role adapter.
   - Ensure schema-context projection remains adapter-owned and is not cached too
     early.

6. **Move splicing into LLBL role algebra**
   - Replace Lalin-specific statement splice and custom array spread paths with
     descriptor-driven LLBL splice behavior.
   - Support declaration, field/product, statement, variant, and continuation
     splicing.

7. **Qualify fragments**
   - Upgrade fragments from plain string roles to qualified role identity.
   - Account for existing dialect fragments under the same identity model.

8. **Finish diagnostics and docs**
   - Replace plain lowering `error(...)` paths with LLBL diagnostics.
   - Document parsed `[fragment]` as the normal splice form and Lua `_`/`spread`
     as Lua-channel conveniences.

## Accepted Costs And Risks

This design has a large blast radius. It touches `lua/llbl.lua`, LLBL syntax
construction, Lua DSL slot matching, Lalin parsed AST/lowering, fragment/spread
behavior, and declaration stream parsing.

It also makes role identity more formal and forces existing custom role regions
to align with kernel role algebra.

Those costs are accepted because the objective is architectural cleanliness:
LLBL should be the language workbench owning bridge mechanics, role algebra,
fragments, splicing, origins, and diagnostics.

Known risks are part of the decision:

- broader bracket admission can create greedy slot ambiguity
- fragment identity must be precise or cross-dialect fragments may collide
- Lalin custom spread behavior may break during migration
- parsed host-eval side-effect timing must remain controlled
- schema-context-sensitive type projection must not be cached too early
- top-level parsed `[generated]` requires real declaration-stream parser support
- diagnostics must preserve both bracket origin and produced-value origin
- nil behavior must be explicit per role
- duplicate checks for product/sum roles must happen after splicing

These risks do not change the target.

## Explicit Non-Goals

- Do not make `[]` a string macro system.
- Do not allow host values to bypass role checking.
- Do not collapse parsed and Lua channels into one syntax mechanism.
- Do not make declarations globally magical; declaration-to-type adaptation is
  role-directed.
- Do not keep Lalin-only splice special cases once LLBL role algebra can express
  them.
- Do not remove Lua DSL `spread` or `_`; they remain Lua-channel builder
  conveniences.
- Do not accept bracket syntax where no current role exists.
- Do not use plain role strings as final fragment compatibility semantics.

## Short Form

```text
[] evaluates Lua.
Roles interpret the result.
Fragments splice in list-like roles.
Dialects own meaning.
LLBL owns the bridge.
```
