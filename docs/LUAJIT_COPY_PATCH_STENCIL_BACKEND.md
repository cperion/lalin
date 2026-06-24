# LuaJIT Copy-and-Patch Stencil Backend Specification

This document specifies the final architecture of the Moonlift LuaJIT
copy-and-patch stencil backend.

The backend is not a second stencil selector. Moonlift already has the semantic
front half:

```text
MoonCode
  -> flow/value/memory/effect facts
  -> MoonKernel semantic bodies
  -> Llisle stencil selection
  -> MoonStencil.StencilArtifact
```

The missing backend is stencil realization:

```text
MoonStencil.StencilArtifact
  -> executable native code pointer
  -> generated LuaJIT wrapper/residual code
```

The core design rule is:

```text
selection decides what stencil is needed;
realization decides how selected stencil code becomes executable.
```

No copy-and-patch component may duplicate the Llisle selection logic.

## Final pipeline

```text
Moonlift DSL / Lua metaprogramming
  -> MoonSyntax / MoonTree
  -> typecheck / ownership / region checks
  -> MoonCode
  -> MoonFlow / MoonValue / MoonMem / MoonEffect facts
  -> MoonKernel semantic bodies
  -> MoonStencil.StencilArtifact selection
  -> BinaryStencilEntry realization
  -> generated LuaJIT module
  -> FFI function pointer calls from traceable Lua wrappers
```

The final fast JIT path is:

```text
selected StencilArtifact
  -> lookup prebuilt binary stencil entry
  -> copy entry.binary
  -> patch entry.patches
  -> install executable memory
  -> ffi.cast function pointer
  -> luajit_emit receives stencil_symbols[symbol]
```

`luajit_emit` remains intentionally simple. It only needs a symbol table:

```lua
{
  [artifact.symbol.text] = ffi_function_pointer,
}
```

The emitter should not know whether the pointer came from a development C build,
an embedded bank, or a cached binary bank file. It only receives already
installed function pointers.

## Non-goals

This backend is not:

```text
a new stencil selector
a replacement for Llisle rules
a general object-file linker
a runtime C compiler
a runtime optimizing compiler
a generic assembler
an interpreter tier hidden behind stencil failure
a second MoonCode lowering path
```

It is:

```text
a fast realization backend for already-selected stencil artifacts
a binary stencil installer and patcher
a source-first LuaJIT artifact generator
a runtime shape constrained by compiler facts
```

## Stencil selection boundary

The selection boundary is `MoonStencil.StencilArtifact`.

A selected artifact contains:

```text
instance:
  descriptor:
    vocab
    domain
    accesses
    operator/reducer
    skeleton
    memory semantics
    params

symbol:
  stable native symbol/key

c_signature:
  callable ABI declaration
```

This is enough to identify the corresponding binary stencil entry.

The copy-and-patch backend treats the selected artifact as immutable semantic
input. It must not reinterpret MoonCode loops or rediscover map/reduce/copy
semantics.

## Realizer

There is one executable realization mode. It has a stable input and output
shape.

```text
input:
  StencilArtifact[]

output:
  stencil_symbols: symbol -> ffi function pointer
```

### BinaryBankRealizer

```text
selected artifacts
  -> prebuilt BinaryStencilBank
  -> BinaryStencilEntry lookup
  -> copy + patch + install
  -> ffi function pointer
```

This is the canonical backend architecture.

`StencilC` remains as the source generator used by binary-bank extraction. It is
not an executable realization mode in the LuaJIT backend.

## Binary stencil entry

A binary stencil entry is the executable realization unit.

```lua
MoonLuaJIT.LJBinaryStencilEntry {
  symbol = "ml_stencil_zip_map_array_i32_add_to_i32_s1",
  section = ".text.ml_stencil_zip_map_array_i32_add_to_i32_s1",
  binary = <machine code bytes>,
  c_signature = "void (*)(int32_t *, const int32_t *, const int32_t *, int32_t, int32_t)",
  patches = LJBinaryPatchRecord[],
  artifact = StencilArtifact,
}
```

The entry is target-specific. Its descriptor key must include enough target
facts to prevent accidental use on the wrong machine:

```text
architecture
ABI / calling convention
pointer width
endianness
target feature set if relevant
symbol/key
stencil descriptor params
```

## Patch records

Patch records describe holes in `binary`.

```lua
MoonLuaJIT.LJBinaryPatchRecord {
  offset = byte_offset,
  kind = LJPatchAbs32 | LJPatchAbs64 | LJPatchSymbol32
       | LJPatchSymbol64 | LJPatchPc32 | LJPatchRel32,
  ordinal = optional_patch_ordinal,
  symbol = optional_symbol_name,
  addend = optional_addend,
}
```

Supported patch kinds:

```text
abs32 / symbol32:
  add a 32-bit patch value into a 32-bit slot

abs64 / symbol64:
  add a 64-bit patch value into a 64-bit slot

pc32:
  adjust an existing PC-relative relocation by subtracting the installed base

rel32:
  write a direct 32-bit relative branch/call displacement
```

Patch values may be addressed by ordinal or by symbol name.

```lua
install_binary_stencil(entry, {
  [1] = literal_or_address,
  ["__ml_patch_2"] = literal_or_address,
})
```

The runtime patcher is deliberately small:

```text
allocate writable memory
memcpy binary bytes
for patch in patches: apply scalar patch
seal memory executable
ffi.cast installed address to c_signature
```

## Automatic extraction

The current automatic extraction path produces binary entries from ordinary C
stencil artifacts.

```text
selected StencilArtifact[]
  -> StencilC.source(artifacts)
  -> relocatable object with -ffunction-sections
  -> dump selected .text.<symbol> sections
  -> parse relocation records for .rela.text.<symbol> / .rel.text.<symbol>
  -> BinaryStencilEntry[]
```

Current x86-64 ELF relocation mapping:

```text
R_X86_64_64:
  symbol64

R_X86_64_32 / R_X86_64_32S:
  symbol32

R_X86_64_PC32 / R_X86_64_PLT32:
  rel32 when a symbol target is present
  pc32 when only base adjustment is required
```

The extraction layer is target-specific. The patch-record model above it is the
portable backend interface.

The current generated stencils are mostly fully-specialized functions, so many
entries have empty patch vectors. That is valid. Hole-bearing stencil generators
use the same representation; they simply produce non-empty patch vectors.

## Runtime install semantics

Artifact bytes are data until installed.

```text
Lua string / bank binary bytes:
  readable data
  not executable
  not aligned as code allocation
  not safe to mprotect in place

installed stencil:
  backend-owned executable memory
  copied bytes
  applied patches
  stable FFI function pointer
```

Runtime must not execute Lua string storage or ordinary LuaJIT cdata storage in
place. The correct install path uses owned executable memory:

```text
POSIX:
  mmap / mprotect policy chosen by target constraints

Windows:
  VirtualAlloc / VirtualProtect
```

The current POSIX install policy is W^X: allocate readable/writable memory,
copy and patch bytes, then seal the allocation readable/executable with
`mprotect`.

## LuaJIT wrapper shape

The generated Lua wrapper must be trace-friendly.

Hot wrapper rules:

```text
fixed arity
stable upvalue/function pointer
no runtime symbol lookup in the hot loop
no per-call allocation unless facts require it
no varargs
no coroutine yield in element loops
```

`luajit_emit` already calls through a stable `stencil_symbols` table captured by
the generated chunk environment. The realizer must provide that table before
loading the generated Lua module.

## Residual execution model

Native stencils are not the whole function. The final execution plan is mixed:

```text
native stencil islands
  regular bulk work

generated Lua residuals
  validation
  control glue
  fragment orchestration
  result branching
  diagnostics/progress/indexing when needed
```

There is no fallback concept in the core architecture.

```text
bad model:
  try whole native stencil else fallback

correct model:
  decompose into native stencil islands plus generated Lua residuals
```

## GPS and coroutine placement

`gen / param / state` is the residual-machine ABI, not the stencil semantic
model.

```text
gen:
  advances a residual process

param:
  immutable call/configuration frame

state:
  mutable continuation state across residual steps/fragments
```

Use GPS for explicit generated residual state machines.

Coroutines are LuaJIT's built-in ordered-process mechanism. They are valid only
at coarse granularity.

```text
good coroutine yield points:
  phase
  fragment
  batch
  diagnostic/index/progress group
  install/runtime milestone

bad coroutine yield points:
  element
  tiny numeric event
  stencil-domain iteration
```

Measured behavior confirms the rule: coroutine batches are acceptable;
coroutine-per-element is not.

## Artifact model

The canonical final artifact is Lua source plus embedded resolved native bytes.

```text
Lua source artifact:
  generated wrappers
  generated residual code
  embedded BinaryStencilEntry bytes or resolved installed-blob data
  patch/install metadata
  diagnostics metadata
```

LuaJIT bytecode may be a derived packaging/cache format, but source is the
canonical artifact because it is inspectable and naturally carries byte strings
and metadata.

For in-process JIT use, the backend may stop earlier:

```text
BinaryStencilBankRealizer
  -> installed function pointers
  -> generated Lua module loaded with stencil_symbols
```

For packaged artifacts:

```text
EmbeddedRealizer
  -> copy/patch selected bank entries at compile time
  -> embed resolved bytes as Lua source data
  -> artifact runtime only installs bytes
```

## ASDL placement

Do not put LuaJIT runtime realization facts into `MoonStencil` or `MoonKernel`.

Correct ownership:

```text
MoonStencil:
  semantic descriptor and selected artifact

MoonLower / future MoonExec:
  mixed execution decomposition:
    native stencil fragments
    Lua residual fragments
    dataflow/control edges

MoonLuaJIT:
  realization/runtime facts:
    blob facts
    patch facts
    install policy
    param layout
    wrapper shape
    trace shape
    safety/reentrancy

MoonCompiler:
  final artifact packaging:
    Flatline artifact
    object artifact
    LuaJIT source artifact
```

The implementation exposes binary bank records as `MoonLuaJIT` ASDL:

```text
LJBinaryTarget
LJBinaryPatchKind
LJBinaryPatchRecord
LJBinaryStencilEntry
LJBinaryStencilBank
```

## Validation requirements

A correct implementation must validate each boundary independently.

Selection validation:

```text
existing Llisle/stencil tests select expected StencilArtifact vocab/skeleton
```

Binary extraction validation:

```text
selected artifact produces BinaryStencilEntry
entry binary is non-empty
entry c_signature is a function-pointer type
relocations map to patch records or are rejected loudly
```

Patch validation:

```text
manual hole-bearing probe patches different values into same binary
installed functions return different expected results
```

Runtime validation:

```text
Lua loop baseline
BinaryBank whole island
GPS chunk orchestration
coroutine batch orchestration
```

Performance validation:

```text
BinaryBankRealizer does not invoke the C compiler on the hot realization path.
Bank generation/extraction is a build/cache operation.
```

API invariant:

```text
moonlift.luajit_backend.lower_module:
  MoonCode -> LuaJIT module + selected StencilArtifact[]

moonlift.luajit_backend.build_binary_bank:
  selected StencilArtifact[] -> BinaryStencilBank
  build/cache operation; may invoke the C toolchain

moonlift.luajit_backend.compile_lj_module:
  LuaJIT module + selected StencilArtifact[] + prebuilt BinaryStencilBank
    -> callable LuaJIT module
  fast realization path; must not invoke the C toolchain

moonlift.luajit_backend.compile_module:
  convenience path only when a prebuilt BinaryStencilBank is supplied

moonlift.luajit_backend.emit_lua_artifact:
  LuaJIT module + selected StencilArtifact[] + prebuilt BinaryStencilBank
    -> canonical Lua source artifact with embedded bank bytes

moonlift.luajit_backend.emit_module_artifact:
  MoonCode + prebuilt BinaryStencilBank
    -> canonical Lua source artifact package
```

The backend must fail loudly if asked to realize stencil artifacts without a
prebuilt bank.

Validated profile shape:

```text
BinaryBankRealizer realization:
  about 0.08-0.09ms for extracted-section bank entries
```

The exact numbers are not the spec. The invariant is:

```text
fast JIT realization must not invoke the C compiler.
```

## Current implementation status

Implemented:

```text
existing MoonCode -> Llisle -> StencilArtifact selection
MoonLuaJIT ASDL for binary target, bank, entry, and patch records
BinaryBankRealizer through StencilBank.build_binary_bank / realize_binary_artifacts
generic install_binary_stencil patcher
manual hole-bearing patch probe
automatic section extraction for selected C stencil artifacts
production moonlift.luajit_backend facade using binary-bank realization
explicit prebuilt-bank requirement for realization
canonical Lua source artifact emission through emit_lua_artifact
W^X POSIX install policy through mmap + mprotect
profile using binary-bank realization
```

Still required for the full final backend:

```text
prebuilt bank generation as normal build artifact
hole-bearing stencil generators for literals, offsets, branch/call targets, and layout constants
cross-target extraction backends beyond current x86-64 ELF path
```

These are implementation completions, not architecture changes.

## Final invariant

The backend is architecturally correct when this holds:

```text
Moonlift semantic selection is single-source.
Selected StencilArtifact is the only stencil-choice boundary.
BinaryStencilEntry is the only executable realization unit.
PatchRecord is the only hole model.
luajit_emit receives only function pointers.
Generated Lua handles residual control; native stencils handle regular bulk work.
No fast JIT path invokes the C compiler.
```
