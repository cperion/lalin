# CBlock

CBlock is a small Lua DSL that constructs ordinary C. Lua owns names, staging,
and composition; CBlock owns types, control, and C emission; C owns layout and
ABI. It is the experiment prototype for the Lalin "label machine" model:
inline/sealed regions, fused data pipelines, lazy TCC cooking, ordinary C
externs, and minimal control ceremony.

```lua
local C = require("cblock")

local source = C.compile(function()
    local add = func
        (param: a (i32), param: b (i32))
        (i32)
        (function(p) return p.a + p.b end)
    return { add = add }
end)
-- source is ordinary C text; cook it with GCC for an AOT artifact,
-- or use C.jit to cook it in memory with TCC and call it from Lua.
```

## The model in one screen

- **A body is a deferred Lua closure.** `func`, `region`, and `block` store the
  body function and stage it later, so forward and recursive references work.
- **A body is a statement list.** The closure's return values are its
  statements; the last one terminates. A single bare value is the direct
  result.
- **A block is a label.** `block(params)(function(...) ... end)` is a labeled
  address in the function frame; jumping to it becomes a C `goto` edge.
- **Inputs are named; return types and continuations stay distinct.** Every callable
  projects its immutable value-parameter product through `p`. Functions and externs
  curry their native result type separately. Region continuations remain control
  parameters; plural bodies select or forward them through immutable `c`.
- **Inline by default, seal explicitly.** Applying a region inlines it.
  `call(region)` gives it one cached private `static` C frame. `func` is
  already a C ABI seal.
- **Machines compose hierarchically.** Objects own state, transitions, child
  machines, and view projections; parent machines wire child exits directly.
- **The pipeline fuses.** `range → load → zip → map → reduce/store` materializes
  one ordinary C loop; GCC `-O3` owns vectorization.

A plural protocol reads directly:

```lua
local checked_div = region(
    param: a (i32),
    param: d (i32),
    cont: divided (i32),
    cont: zero ()
)(function(p, c)
    return if_(eq(p.d, 0), c:zero(), c:divided(p.a / p.d))
end)

return checked_div(a, d) { divided = on_value, zero = on_zero }
```

See [LANGUAGE_REFERENCE.md](LANGUAGE_REFERENCE.md) for the full surface and
[lua_label_machines.md](lua_label_machines.md) for the design narrative
(named protocols, nested object machines, component views, interpreters).

## Quick start

Compile to C text and drive it from C:

```lua
local C = require("cblock")
local source = C.compile(function()
    local clamp = region(
        param: x (i32),
        param: lo (i32),
        param: hi (i32)
    )(i32)(function(p)
        return if_(lt(p.x, p.lo), p.lo, if_(gt(p.x, p.hi), p.hi, p.x))
    end)
    local host_add = extern
        (param: a (i32), param: b (i32))
        (i32)
    local demo = func
        (param: x (i32), param: y (i32))
        (i32)
        (function(p)
            return clamp(host_add(p.x, p.y), 0, 100)
        end)
    return { demo = demo, host_add = host_add }
end)
```

Cook with GCC and call from Lua via the JIT path, or cook in memory with TCC:

```lua
local math = assert(C.jit(function()
    local add = func
        (param: a (i32), param: b (i32))
        (i32)
        (function(p) return p.a + p.b end)
    return { add = add }
end))
assert(math.add(20, 22) == 42)   -- cooks the whole module on first call
math:free()
```

`C.jit` returns the ordinary namespace immediately. The first call to an
exported function compiles the complete module with TCC and caches the
function pointers. Host externs are passed as stable FFI pointers:

```lua
local ffi = require("ffi")
ffi.cdef [[ typedef int32_t (*CBlockTestBinary)(int32_t, int32_t); ]]
local host_mul = ffi.cast("CBlockTestBinary", function(a, b) return a * b end)

local m = assert(C.jit(function()
    local host_mul_decl = extern
        (param: a (i32), param: b (i32))
        (i32)
    local twice = func
        (param: x (i32))
        (i32)
        (function(p) return host_mul_decl(p.x, 2) end)
    return { twice = twice }
end, { symbols = { host_mul = host_mul } }))
```

## Architecture

One pipeline, three compiler layers plus codegen:

```text
Lua build chunk
  -> source_env (staging)      deferred bodies become statement lists, blocks, vars
  -> check_machine (check)     type checks, terminator enforcement, clear errors
  -> lower_machine (lower)     SSA-ish registers, block layout, terminators
  -> codegen                   ordinary C text (deterministic, namespaced)
  -> GCC shared object / dlopen   (or user-owned AOT build)
  -> TCC memory cook + FFI        (C.jit interactive path)
```

- `label.lua` is the small DSL runtime (`L.new_env`, `L.run`, `L.keyword`)
  that powers both the staging env and the `def_check` / `def_lower` tables.
- `cblock.lua` is the whole compiler: types, staging env, check, lower, codegen.
- `cblock_tcc.lua` is the lazy TCC cooker (whole-module cook on first export,
  cached FFI pointers, host symbol resolution, multi-exit host calls).
- `C.compile(build)` returns `(source, lowered, program)` or `(nil, errors)`.
- `C.jit(build, options)` returns `(namespace, runtime)`; the namespace has
  `:free()` and `:source`.

The full architecture — the three IR layers, the inline/seal mechanism, the
TCC runtime ABI, and the enforced invariants — is in
[ARCHITECTURE.md](ARCHITECTURE.md).

```text
experiments/cblock/
  cblock.lua          the DSL + compiler (staging, check, lower, codegen)
  cblock_tcc.lua      TCC memory cooking and the FFI runtime boundary
  label.lua           the keyword/DSL runtime
  lua_label_machines.md   design narrative (labels, regions, machines)
  ARCHITECTURE.md         compiler architecture, IR layers, TCC runtime
  LANGUAGE_REFERENCE.md   systematic language reference
  TCC_VS_LUAJIT.md         TCC vs LuaJIT steady-state benchmark
  test_*.lua          surface, extern, pipeline, struct, tcc, places, switch, leftover
  expr_parser.lua     fused lexer+parser machine (also a test)
  particles.lua, mandelbrot.lua, hailstone_vm.lua, cdemo2.lua   machines
  bench_places.lua, bench_tcc_vs_luajit.lua                     benchmarks
```

## Tests and benchmarks

```sh
luajit test_surface.lua        # core surface (GCC + TCC)
luajit test_extern.lua         # externs, fnptr, opaque
luajit test_pipeline.lua       # fused range/zip/map/reduce/store
luajit test_struct.lua         # structs, methods, owned regions
luajit test_places.lua         # let/var/places, method sugar
luajit test_switch.lua         # enum + switch_ jump tables
luajit test_leftover.lua       # arrays/views/unions/globals/cstring/fnptr
luajit expr_parser.lua         # fused lexer+parser
luajit particles.lua           # struct machine + pipeline population
luajit hailstone_vm.lua        # direct-threaded VM, differential vs C
luajit cdemo2.lua              # end-to-end demo
luajit mandelbrot.lua          # framed machine, image generator

luajit bench_tcc_vs_luajit.lua # TCC steady state vs LuaJIT
luajit bench_places.lua        # let vs var, immutable vs mutable frames
```

Every test validates the same emitted C through both paths: GCC `-O2/-O3`
compilation and the TCC memory cook.

## Design rules

- Lua owns names and composition; CBlock owns semantics; C owns layout and ABI.
- Bodies are statement lists; every block path terminates (checked).
- `func`, `extern`, and direct `region` separate their named parameter product
  from one curried native result type (`void` for no value). Alternative regions
  carry named continuations among their parameters instead; unnamed `cont(...)`
  is not accepted.
- Value inputs are ordered `param: name (type)` declarations and bodies receive
  immutable product `p`. Plural region bodies additionally receive `c`;
  `c:name(v)` selects an exit and `c.name` forwards it. Calls may use positional
  input sugar, but callers provide exact named-handler tables.
- Regions inline unless called; recursion crosses `call(region)`.
- Handler tables are consumed during staging and lower to direct control edges,
  never runtime dispatch maps.
- Field order is written explicitly (`field: name (type)`); Lua table iteration
  is never an ordering contract.
- No implicit numeric conversions; `cast(T, v)` is the only one.
- `switch_` requires a default arm and has no fallthrough.
- Arrays and opaque types cannot cross a call boundary; use `ptr()`.
- GCC owns optimization; TCC owns fast interactive cooking.
