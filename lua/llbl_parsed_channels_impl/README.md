# LLBL Parsed Channels Implementation Bundle

This bundle implements a Terra-like parsed-channel frontend as a generic LLBL
service.  Lalin is registered as one dialect client of that service.

The implementation is intentionally split this way:

```text
LLBL owns:
  lexer, island detection, entrypoint registry, parse-time import,
  constructor invocation, lexical ref capture, parsed channel origins.

Lalin owns:
  fn/struct/union/region/module grammar, expression grammar,
  statement grammar, native assignment, comparisons, if/for/return/jump/emit,
  and the parsed AST that should be lowered to LalinTree ASDL.
```

The key law is:

```text
Lua channels are what Lua can deliver.
Parsed channels are what Lua cannot deliver.
LLBL owns both delivery mechanisms.
Dialects own meaning.
```

## What is implemented

### Generic LLBL modules

```text
lua/llbl/syntax/init.lua          public API and install(llbl)
lua/llbl/syntax/lexer.lua         Lua-compatible token stream with source spans
lua/llbl/syntax/registry.lua      dialect/entrypoint registry
lua/llbl/syntax/constructor.lua   parse-time constructor descriptors and invoke()
lua/llbl/syntax/driver.lua        mixed Lua + parsed-channel loader/preprocessor
lua/llbl/syntax/pratt.lua         reusable Pratt parser helper
```

### Lalin parsed frontend modules

```text
lua/lalin/syntax/init.lua         registers Lalin with LLBL parsed channels
lua/lalin/syntax/ast.lua          parsed AST nodes, host escape resolution
lua/lalin/syntax/type.lua         type/product/field parser
lua/lalin/syntax/expr.lua         expression parser: +, *, <, <=, ==, and/or/not, calls, fields, indexes
lua/lalin/syntax/stmt.lua         statement parser: requires, return, if, for/range, let/var, jump, emit, assignment
lua/lalin/syntax/decl.lua         declarations: fn, struct, union, region, module, expr/stmt quotes
```

## Usage

Use `llbl.syntax.loadfile` / `llbl.syntax.loadstring`, not plain Lua, for files
that contain parsed islands.

```lua
package.path = "lua/?.lua;lua/?/init.lua;" .. package.path

local syntax = require("llbl.syntax")
require("lalin.syntax") -- registers namespaced `lalin fn`, `lalin struct`, etc.

local chunk = assert(syntax.loadfile("demo.lalin.lua"))
local module = chunk()
```

## Namespaced form

The namespaced form is always explicit:

```lua
local add = lalin fn add(a: i32, b: i32): i32
  return a + b
end
```

This is rewritten to ordinary Lua that invokes a parsed-channel constructor at
that lexical position.

## Parse-time import form

A source file can activate direct entrypoints with:

```lua
import "lalin.syntax"

local add = fn add(a: i32, b: i32): i32
  return a + b
end
```

The driver rewrites the import to:

```lua
require("lalin.syntax")
```

and enables direct entrypoints such as `fn`, `struct`, `region`, and `quote` for
the rest of the driver pass.

## Host escapes

Inside Lalin parsed islands, names are object-language names by default.  Use
`[ ... ]` to splice a host Lua expression:

```lua
local scale = 4

local f = fn scale_i32(x: i32): i32
  return x * [scale]
end
```

The driver records lexical references used in escapes and emits an environment
thunk:

```lua
function() return { scale = scale } end
```

The constructor resolves host escapes at Lua evaluation time.

## Example

```lua
import "lalin.syntax"

local scale = 4

local copy_scale = fn copy_scale(dst: ptr[i32], src: ptr[i32], n: index): void
  requires bounds(dst)(n), bounds(src)(n), disjoint(dst)(src)

  for i in range(0, n) do
    dst[i] = src[i] * [scale]
  end
end

return { copy_scale = copy_scale }
```

This produces a parsed `DeclFunc` AST containing:

```text
StmtRequires
StmtForRange
  StmtAssign
    place = dst[i]
    value = src[i] * HostEscape(scale)
```

A full repository integration should replace the parsed AST handoff with the
existing LalinTree/ASDL builders or canonical LLBL heads at exactly one boundary.
The backend must still consume typed LalinTree/LalinCode/facts; parsed syntax is
only a capture channel.

## Integration points in an existing repository

1. Copy `lua/llbl/syntax/` into the repo.
2. In `lua/llbl.lua`, require `llbl.syntax` and call `syntax.install(llbl)`.
3. Copy `lua/lalin/syntax/` into the repo.
4. In `lua/lalin/init.lua`, require `lalin.syntax` during language setup or when
   parsed syntax is requested.
5. Replace `lalin.syntax.ast` return values with the repo's LalinTree ASDL
   constructors or add a lowering adapter from these parsed nodes to LalinTree.
6. Route diagnostics through existing LLBL origins/diagnostics.  Every parsed node
   already carries source span data.
7. Add equivalence tests: parsed `for i in range` must produce the same typed
   facts/descriptors as canonical `lln.loop. i [lln.range { ... }]`.

## Safety boundaries

This subsystem does not typecheck, lower, vectorize, or materialize anything.
It only captures syntax Lua cannot expose: real assignment, comparisons, boolean
operators, statement blocks, object-language `if`, `for`, `return`, and region
body syntax.

Backends must continue to consume validated ASDL/facts, not parsed spelling.
