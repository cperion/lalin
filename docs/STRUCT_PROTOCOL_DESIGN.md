# Struct-Owned Protocol Design

Lalin's center of gravity shifted from "a module is a flat list of declarations"
to **"structs own their protocol vocabulary."**

This document explains what that means, why it matters, and how it connects to
the ASDL compiler pattern and the design bible.

## The shift

Before:

```lln
-- Everything is a peer declaration. Structs are just data.
struct Connection
  fd [i32]
  state [u32]
end

-- These float in module scope.
fn read(conn [ptr [Connection]], buf [ptr [u8]], len [index]) [index] ... end
region open(addr [slice [u8]]; connected ... refused ... timeout) ... end
handle ConnectionRef [u32] invalid 0 domain [Connection] target [Connection] end
```

After:

```lln
-- Structs own their protocol.
struct Connection
  fd [i32]
  state [u32]
end

fn Connection.read(self [ptr [Connection]], buf [ptr [u8]], len [index]) [index] ... end
region Connection.open(addr [slice [u8]]; connected(conn [ptr [Connection]]), refused, timeout) ... end
handle Connection.Ref [u32] invalid 0 domain [Connection] target [Connection] end
```

The dot means ownership: `Connection.read`, `Connection.open`, `Connection.Ref`.

At call sites, regions are invoked like functions with the region signature's
shape: data arguments before `;`, continuation wiring after `;`.
Continuation wiring is just `name = value`, because the values are the caller's
continuation blocks:

```lln
call Connection.open("localhost:8080";
  connected = handle_connected,
  refused = retry_open,
  timeout = retry_open
)

emit Connection.open("localhost:8080";
  connected = handle_connected,
  refused = retry_open,
  timeout = retry_open
)
```

Inside a region body, `jump` still transfers to one of the region's named exits:

```lln
region Connection.adopt(conn [ptr [Connection]];
  connected(c [ptr [Connection]]),
  refused,
  timeout
)
  entry start()
    jump connected(c = conn)
  end
end
```

Current implementation status: parsed region declarations lower to ASDL
`ItemRegion`, and `call`/`emit` lower to explicit region-invocation ASDL
statements. `emit` expands by cloning the target region CFG into the enclosing
control region and wiring continuations to caller blocks/continuations. `call`
frame expansion is still pending and is diagnosed if used in a control region.

## The design bible made executable

The design bible states three rules:

```text
Products own bytes.        →  struct Connection { fd, state }
Regions control access.    →  region Connection.open/read/close
Protocols name failure.    →  connected | refused | timeout | closed | error
```

The language now expresses these directly. A struct without protocols is
half-declared — it has shape but no behavior vocabulary.

## Connection to the ASDL compiler pattern

Lalin's own compiler is built on ASDL schemas with products, unions, leaf
methods, and identity. The struct protocol pattern makes the compiler's
architecture expressible in Lalin itself.

### ASDL products → Lalin structs

```lua
-- Compiler schema
product. ExprCall {
  field. callee [Tree.Expr],
  field. args [many [Tree.Expr]],
}
```

Becomes:

```lln
struct ExprCall
  callee [ptr [Expr]]
  args [ptr [ExprList]]
end
```

### ASDL leaf methods → qualified functions

```lua
function Tree.ExprCall:typecheck(input)
  return Tree.TypeExprResult(...)
end

function Tree.ExprLit:typecheck(input)
  return Tree.TypeExprResult(...)
end
```

Becomes:

```lln
fn ExprCall.typecheck(self [ptr [ExprCall]], input [ptr [TypeInput]]) [ptr [TypeExprResult]]
  ...
end

fn ExprLit.typecheck(self [ptr [ExprLit]], input [ptr [TypeInput]]) [ptr [TypeExprResult]]
  ...
end
```

The dispatch rule: `:typecheck(...)` hits the right method because the qualified
name binds it to the struct. No `kind` string, no handler map, no `if/elseif`
chain. The struct IS the dispatch.

### ASDL unions → regions

```lua
sum. Expr {
  ExprCall,
  ExprLit,
  ExprIf,
  ExprBinOp,
}
```

A union is consumed by visiting it. The consumer IS a region:

```lln
region Expr.visit(self [ptr [Expr]];
  call(ec [ptr [ExprCall]]),
  lit(el [ptr [ExprLit]]),
  if_expr(ei [ptr [ExprIf]]),
  binop(eb [ptr [ExprBinOp]])
)
  entry start()
    switch self.kind
      case 0 jump call(ec = [cast(ptr [ExprCall], self)])
      case 1 jump lit(el = [cast(ptr [ExprLit], self)])
      ...
    end
  end
end
```

Each continuation is a variant arm. Exhaustiveness is structural: every union
variant has a corresponding exit in the protocol, or the compiler diagnoses a
missing arm.

### ASDL identity (`unique` / `interned`) → `unique` structs

```lua
-- Identity: two instances are distinct objects
product. TypeExprResult { interned, field. ty [LalinType.Type], ... }

-- Value: fields are the identity
product. Position { field. x [number], field. y [number] }
```

Becomes:

```lln
-- Identity: allocation carries identity
struct TypeExprResult
  unique
  ty [ptr [Type]]
  issues [ptr [IssueList]]
end

-- Value: comparison is field-wise
struct Position
  x [i32]
  y [i32]
end
```

`unique` structs are handle-backed. Facts attach to the object, not to side
tables. The ASDL doctrine against side tables becomes unnecessary because the
language has no side-table escape hatch — the object carries its facts as
fields.

## Why this simplifies the compiler

### No side tables for semantic facts

Instead of maintaining external caches keyed by nodes:

```lua
-- Forbidden by ASDL doctrine
local type_results = {}   -- node → type, in a side table
local flow_facts = {}     -- node → flow facts, in another side table
```

The node struct carries its facts:

```lln
struct ExprCall
  unique
  callee [ptr [Expr]]
  args [ptr [ExprList]]
  tc_result [ptr [TypeExprResult]]
  flow_info [ptr [FlowInfo]]
end
```

Facts are ordinary fields of an identity object. The compiler doesn't *ask*
"what's the type of this node?" — the node already carries it.

### No null pointer checks scattered through the code

A handle plus a resolver region replaces defensive pointer checks:

```lln
handle ExprId [u32]
  domain [ExprStore]
  target [ExprCall]
end

region ExprStore.resolve(self [ptr [ExprStore]], id [ExprId];
  borrowed(expr [lease("self", ptr [ExprCall])]),
  stale(id [ExprId]),
  missing(id [ExprId])
)
  entry start()
    -- store-private validation
  end
end
```

The protocol says exactly what can happen. Stale and missing are named exits,
not `if ptr == nil then error("stale") end` scattered across the code.

### No dispatch tables

Method dispatch is structural, not a manually maintained table:

```lln
-- expr:typecheck(input) dispatches to ExprCall.typecheck or ExprLit.typecheck
-- because the qualified name binds it to the struct
```

No `kind` strings. No `local handlers = {}` table. No `if/elseif` chains.

## The meta-language converges with the object language

The goal: Lalin *is* its own ASDL. Structs, unions, handles, and qualified
methods expressed in `.lln` documents that compile to the same compiler
infrastructure.

```text
.lln document               Lalin surface syntax
  struct ExprCall { unique callee: ptr(Expr) ... }
  fn ExprCall.typecheck(self, input) -> TypeExprResult
  region Expr.visit(self; call(ExprCall), lit(ExprLit), ...)
  → lalin.compile
  → typecheck/lower/codegen
  → executable compiler phase
```

The design bible's thesis:

> The design is the declaration graph itself — the type forest plus the region
> tree — and the compiler checks the two against each other continuously.

This is no longer just a philosophy for compiler authors. It's the surface
syntax of the language and the compiler written in it.
