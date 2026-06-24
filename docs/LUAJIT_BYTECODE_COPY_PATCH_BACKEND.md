# LuaJIT Bytecode Copy-Patch Backend

LuaJIT bytecode copy-patch is a materializer for the LuaTrace backend. It uses
LuaJIT itself to compile a Lua source stencil ahead of time, stores the dumped
bytecode as a bank entry, and patches declared holes before loading the function.

The backend does not make LuaJIT bytecode a source language. LuaTrace remains
the semantic lowering layer:

```text
region / stencil descriptor / schedule facts
  -> LuaTrace plan
  -> LuaTraceOp-shaped source stencil
  -> LuaJIT AOT bytecode template
  -> exact copy-patch instantiation
  -> load patched function
  -> LuaJIT records native traces at runtime
```

This is the bytecode analogue of the C stencil bank. The whole executable shape
is selected by key. Only declared, verifier-checked holes are patched.

## Purpose

The source materializer is readable and is the golden debug path, but it pays for
Lua parsing and bytecode generation every time an artifact is loaded. Bytecode
copy-patch moves that work to bank construction:

```text
source materializer:
  emit Lua source -> loadstring parses -> LuaJIT builds Proto -> run

bytecode bank:
  compile template once -> string.dump Proto -> patch bytes -> load dumped Proto
```

The loaded bytecode is still LuaJIT recorder input. It is not native machine
code. Hot loops still trace normally.

## Architecture

There are three sibling LuaJIT materializers:

```text
luatrace.source
  readable source, diagnostics, golden equivalence path

luatrace.bc_copy_patch
  LuaJIT bytecode stencil bank; faster load path with exact LuaJIT bytecode shape

luajit.machine_copy_patch
  GCC/C stencil bank; native function pointers through FFI
```

The shared semantic input is the LuaTrace plan. Materializers do not rediscover
loop semantics from text or bytecode.

```text
MoonLuaTrace.LTModule
  -> MoonLuaJIT.LJBCStencilBank
  -> patched dumped bytecode
  -> loaded Lua function
```

## ASDL Shape

Bytecode bank records live in `MoonLuaJIT`, because the dump format is a LuaJIT
runtime artifact:

```text
LJBytecodeTarget
  luajit_version
  arch
  os
  pointer_bits
  endian
  gc64
  dualnum
  ffi

LJBCStencilEntry
  id
  symbol
  chunk_name
  source
  bytecode
  patches
  plan?
  artifact?

LJBCStencilBank
  id
  target
  entries
```

`source` is retained deliberately. It is the readable stencil, the rebuild input,
and the equivalence reference. `bytecode` is the AOT dump produced by LuaJIT.

## Patch Discipline

Patch values, not structure.

Allowed first-class patch class:

```text
LJBCPatchStringConstantExact
  replace a unique string-constant byte sequence with a same-width replacement

LJBCPatchBytesExact
  replace a unique raw byte sequence with a same-width replacement
```

The installer verifies:

```text
1. the bank target matches the current LuaJIT runtime;
2. the expected byte sequence is present exactly where the bank recorded it;
3. the replacement byte sequence has exactly the recorded width;
4. the patched dump can be loaded by the current LuaJIT runtime.
```

Rejected by design:

```text
control-flow topology mutation
register slot mutation without a BC verifier
frame-size mutation
prototype count mutation
upvalue layout mutation
varint-width-changing constants
portable cross-LuaJIT bytecode claims
```

Those are stencil-key decisions. If a different control shape is needed, select
a different bytecode stencil.

## Target Key

LuaJIT bytecode is not a portable artifact. A bank is keyed by:

```text
LuaJIT version
architecture
OS
pointer width
endianness
GC64 mode
dual-number mode
FFI availability
```

The current runtime target is recorded as `LJBytecodeTarget`. A cache must reject
or rebuild banks when the target does not match.

## Why Compile With LuaJIT First

Hand-emitting bytecode is not the first layer. The correct first bank is:

```text
LuaTrace source stencil
  -> LuaJIT loadstring
  -> string.dump(function)
  -> recorded bytecode template
```

This uses LuaJIT as the bytecode assembler and verifier. Moonlift only patches
declared holes whose encoding is proven stable for the selected stencil.

Later, a bytecode assembler may replace the source stencil compiler for selected
templates, but it must still target the same `LJBCStencilEntry` shape.

## Debug Model

The bank keeps the source stencil and chunk name beside the dumped bytecode.
Diagnostics can report:

```text
semantic plan: LuaTrace plan / stencil artifact
source stencil: retained Lua source
bytecode stencil: LJBCStencilEntry + patch records
runtime failure: LuaJIT load/runtime error
```

This keeps bytecode copy-patch inspectable. It is not an opaque binary blob.

## Current Implementation

`moonlift.luajit_bc_bank` provides:

```lua
local BC = require("moonlift.luajit_bc_bank")(T)

local entry = assert(BC.compile_entry {
  id = "example",
  symbol = "example",
  chunk_name = "@llb.codegen/luajit-bc/example",
  source = "return function(x) ... end",
  holes = {
    { name = "mode", expected = "MLBC_PATCH_A", kind = "string" },
  },
})

local bank = BC.build_bank { entry }
local fn = assert(BC.load_symbol(bank, "example", {
  LJ.LJBCPatchBinding("mode", LJ.LJBCPatchString("MLBC_PATCH_B")),
}))
```

Offsets are zero-based, matching the native binary patch records.

The backend-facing switch is:

```lua
local compiled = Backend.compile_module(code_module, {
  stencil_provider = "lua_trace",
  luatrace_materializer = "bytecode",
})

local artifact = moon.emit_luajit_artifact(decl, {
  stencil_provider = "lua_trace",
  luatrace_materializer = "bytecode",
})
```

Without `luatrace_materializer = "bytecode"`, LuaTrace uses the readable source
materializer.

## Completion Rule

Bytecode copy-patch is complete for a stencil family only when:

```text
all semantic choices are represented in the LuaTrace plan;
the stencil key chooses topology, arity, locals, and branch shape;
patches modify only verifier-approved same-width fields;
source and bytecode materializers pass the same runtime tests;
materialization-time benchmarks show the expected load benefit;
runtime benchmarks show no trace-quality regression;
target mismatch rebuild/reject behavior is tested.
```

Until then, source remains the golden materializer and bytecode copy-patch is an
additional bank path for explicitly supported stencils.
