# LLBL Bracket Evaluation Direction

This is a design direction, not an implementation plan. It records the intended
LLBL-first model before changing the parser, role normalizer, or Lalin frontend
further.

## Thesis

`[...]` should become LLBL's single host-evaluation surface.

The meaning of a bracketed expression is not inherently "type". The surrounding
LLBL role determines what the evaluated Lua value must become:

```text
current role + [lua_expr]
  -> evaluate lua_expr in the captured Lua environment
  -> adapt the resulting Lua value to the current LLBL role
  -> insert it, or splice it if the role is list-like
```

So brackets are a role-directed bridge from Lua values into LLBL roles. Dialects
own the role semantics; LLBL owns the host-evaluation mechanism, origins,
fragments, diagnostics, and splice discipline.

## First principles

LLBL already has the right vocabulary:

- **channel**: how syntax delivered a value
- **event**: value plus channel/origin metadata
- **role**: the semantic expectation at a position
- **fragment**: reusable role-tagged value
- **spread/splice**: insertion of many role-compatible items into a role
- **language/dialect**: LLBL owns mechanics; dialects own meaning

The missing unification is that parsed-channel host escapes currently behave as
ad hoc syntax escapes, while Lua-channel brackets behave as ordinary Lua index
operations feeding slots. We want one conceptual model across both channels:

```text
[] delivers a HostEval event.
A HostEval event is normalized by the role it appears under.
```

The role, not the bracket form, decides whether the result is a type, expression,
statement, field, declaration, continuation, protocol alternative, or ordinary
value.

## Role-directed adaptation

Every role should expose an adapter contract:

```text
adapt(role, value, origin) -> one role item or a role fragment
```

Examples:

| Role | `[value]` may adapt from |
|---|---|
| `type` | type value, type declaration value, handle declaration value |
| `expr` | expression node, expression fragment, literal value if dialect accepts it |
| `stmt` | statement node, statement fragment, array/fragment of statements |
| `decl` | declaration node, declaration fragment, array/fragment of declarations |
| `field` / `product` | field node, product fragment, declaration-derived field if dialect accepts it |
| `cont` / `protocol` | continuation node, protocol fragment |

Adaptation must be typed and role-local. A declaration fragment in expression
position is a diagnostic, not a best-effort conversion. A field list in type
position is a diagnostic. This keeps `[]` powerful without making it untyped.

## Splicing rule

List-like roles should splice bracket results by default.

```text
If the current role has list/product/sum algebra and [value] adapts to a
fragment with the same item role, insert each item.
If [value] adapts to one item, insert that item.
Otherwise report a role mismatch diagnostic.
```

This means parsed source should not need explicit `spread` for the common case:

```lln
local common_fields = make_fields(i32)

struct Pair
  [common_fields]
end

[make_decls()]
```

`spread` may remain as a Lua-builder API helper, because Lua table syntax
sometimes needs an explicit object to stand for splicing. In parsed source,
`[]` is the clearer splice/eval surface.

## `named(...)` should become uncommon

A parsed declaration value should adapt to the role expected of it.

```lln
local Store = struct Store
  capacity [index]
end

local Record = struct Record
  first [index]
end

local Ref = handle Ref [u32]
  domain [Store]
  target [Record]
end
```

Here `[Store]` appears in a handle-domain type-ref role. The value is a parsed
struct declaration, so the role adapter projects its type identity. The author
should not need to write `[named("Store")]` unless they deliberately want to
construct a type reference from a string or package value.

## The two channels stay distinct

This direction does not erase the difference between Lua-channel and parsed
channel authoring.

### Lua channel

In Lua DSL code, brackets are Lua's `__index` syntax:

```lua
lln.fn. add { a [lln.i32], b [lln.i32] } [lln.i32] { ... }
```

LLBL already models this as slot/channel delivery (`index:type`, `index:value`,
etc.). The conceptual unification is that this also feeds a role adapter: the
slot says which role is expected, and the value is normalized for that role.

### Parsed channel

In parsed `.lln`, brackets are explicit host evaluation:

```lln
fn add(a [i32], b [i32]) [i32]
  return [make_expr(a, b)]
end
```

The parser records a `HostEval` node with origin and refs. The surrounding
parser position supplies the role. Later normalization evaluates the Lua source
and adapts the value to that role.

## No ambient "anything anywhere"

The hard rule:

```text
[] evaluates everywhere, but it is never semantically untyped.
```

Every bracket occurrence has a current role. If the parser cannot assign a role,
that is a parser bug or an unsupported syntax position. If the evaluated Lua
value cannot adapt to the role, the compiler reports a role mismatch diagnostic
with:

- the bracket origin
- the expected role
- the value's available role/tag, if known
- a suggestion such as "return a stmt fragment" or "use a type declaration value"

## Role algebra owns splice behavior

Do not special-case splicing in Lalin parser code. LLBL role algebra should say
whether a role is:

- single item
- list
- product
- sum/protocol
- record/map
- optional

Then `HostEval` normalization asks the role algebra whether a fragment may
splice. This keeps Lalin from reimplementing LLBL fragment semantics and lets
other dialects reuse the same bracket model.

## Direction for AST/schema vocabulary

Prefer naming the generic mechanism in LLBL terms before dialect terms.

Possible generic vocabulary:

```text
HostEval       origin + Lua source + captured refs
RoleExpected   current role name + dialect/member owner
RoleValue      one adapted role item
RoleFragment   many adapted role items with an item role and algebra
RoleMismatch   typed diagnostic for failed adaptation
```

Lalin-specific AST nodes may still lower to `Expr`, `Stmt`, `Type`, `Decl`, etc.,
but the bridge should be LLBL-owned and role-directed.

## Examples of desired parsed behavior

### Type from declaration value

```lln
local Pair = struct Pair
  x [i32]
  y [i32]
end

local use_pair = fn(p [ptr [Pair]]) [void]
  return
end
```

`[Pair]` adapts a parsed `DeclStruct` value to a Lalin type value.

### Declaration splice

```lln
local generated = make_numeric_decls(i32)

[generated]
```

At declaration level, `[generated]` adapts to one or many declarations and
splices them into the surrounding declaration stream.

### Field splice

```lln
local header = product_fields()

struct Packet
  [header]
  payload [ptr [u8]]
end
```

Inside a product role, `[header]` must adapt to fields/product fragment.

### Statement splice

```lln
local body = make_copy_body()

fn copy(dst [ptr [u8]], src [ptr [u8]], n [index]) [void]
  [body]
  return
end
```

Inside a statement block, `[body]` inserts one statement or splices a statement
fragment.

## What happens to `spread` and `_`

`spread` and `_` remain useful in Lua DSL code because Lua itself has no parsed
host-eval form and no native splice-in-table syntax.

In parsed `.lln`, explicit spread should become unnecessary for normal fragment
insertion. If retained, it should be a low-level/debug spelling, not the primary
surface.

Design target:

```text
Lua DSL:      _(fragment) / spread(fragment) remain builder conveniences.
Parsed .lln: [fragment] is the normal splice form in list-like roles.
```

## Phasing direction

1. Name the LLBL concept in docs and schema: role-directed `HostEval`.
2. Teach parsed AST nodes to carry expected role at bracket sites, or make the
   surrounding lowering call the role adapter explicitly.
3. Move current Lalin-specific host-escape conversion into role adapters:
   type, expr, stmt, decl, field/product, continuation/protocol.
4. Done: declaration-value-to-type adaptation lets `[Pair]` work without
   `named("Pair")`; keep `named("...")` only for dynamic/metaprogrammed names.
5. Implement fragment splicing for parsed declaration, field/product, statement,
   and continuation roles.
6. Keep Lua DSL `spread`/`_` intact, but document them as Lua-channel helpers,
   not as the core parsed-source model.

## Non-goals

- Do not make `[]` a string macro system.
- Do not let values bypass role checking.
- Do not add Lalin-only fragment machinery when LLBL roles/fragments can own it.
- Do not make declarations globally magical; adaptation depends on the current
  role and available declaration identity.
- Do not remove Lua DSL `spread` until there is an equivalent Lua-channel story.

## Short form

```text
[] evaluates Lua.
Roles interpret the result.
Fragments splice in list-like roles.
Dialects own meaning.
LLBL owns the bridge.
```
