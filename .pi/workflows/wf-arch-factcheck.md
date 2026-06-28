# Architecture Fact-Check: MC Bank Build & Pipeline 
Rigorously fact-check the MC bank build process, TCC role, C compilation, and the full compiler pipeline against the actual source code.
**Workflow ID**: wf-arch-factcheck
**Started**: 2026-06-28 11:36:34
---

## Scout Output — 2026-06-28 11:37:53

---

# Architecture Fact-Check: MC Bank Build & Pipeline

## 1. MC Bank Build — How Native Stencils Are Compiled

### The build function: `api.build_mc_bank()` in `lua/lalin/copy_patch_mc.lua` (line 397)

**File**: `lua/lalin/copy_patch_mc.lua`  
**Key signature**: `function api.build_mc_bank(artifacts, opts)`

This is the **central MC stencil compilation function**. Here is exactly what it does, line by line:

```lua
-- Line 398: opts defaults
opts = opts or {}

-- Line 403: Create build directory
local dir = opts.dir or "target/copy_patch_mc"
os.execute("mkdir -p " .. shell_quote(dir))

-- Line 407: Generate C source from stencil artifacts
local source = StencilC.source(artifacts, { c_decls = opts.c_decls or opts.decls })
write_file(c_path, source)

-- Lines 409-415: THE COMPILER INVOCATION
local cc = opts.cc or os.getenv("CC") or "gcc"
local cflags = opts.cflags or "-std=c99 -O3 -march=native -fno-builtin -fno-builtin-memmove -fno-builtin-memcpy -fno-builtin-memset -ffunction-sections -fno-pic -fno-jump-tables -fno-stack-protector -fno-asynchronous-unwind-tables -fno-unwind-tables -c"
local cmd = table.concat({ shell_quote(cc), cflags, shell_quote(c_path), "-o", shell_quote(o_path) }, " ")
local ok = os.execute(cmd)
```

**Definitive facts about the compiler**:
- **Default compiler**: `gcc` (resolved via `opts.cc` → env `$CC` → `"gcc"`)
- **Compiler flags**: `-std=c99 -O3 -march=native -c` (plus many `-fno-*` disabling flags)
- **Output**: Object file (`.o`), **not a shared library or executable**
- **Invocation**: Raw `os.execute()`, not a subprocess library
- **Tool**: The system `gcc` binary on `$PATH`

**After compilation** (lines 418-442), the function:
1. Runs `readelf -Wr` to parse relocations from the `.o` file
2. Runs `readelf -SW` to parse section headers
3. Runs `readelf -Ws` to parse symbols
4. Reads the raw `.o` file bytes
5. Materializes each `.text.<symbol>` section into a self-contained binary blob, resolving all local relocations
6. Stores the resolved binary blobs into `LJMCStencilEntry` records within an `LJMCStencilBank` object

### Tools/gen_lalin_mc_bank.lua (the prebuild script)

**File**: `tools/gen_lalin_mc_bank.lua`

This is a **standalone LuaJIT script** for prebuilding the embedded MC bank. Key excerpt:

```lua
-- Lines 23-26: Default cflags
local embedded_mc_cflags = os.getenv("LALIN_MC_BANK_CFLAGS")
    or "-std=c99 -O3 -march=native -fno-builtin -fno-builtin-memmove -fno-builtin-memcpy -fno-builtin-memset -ffunction-sections -fno-pic -fno-stack-protector -fno-asynchronous-unwind-tables -fno-unwind-tables -c"
```

The script:
1. Generates all stencil artifacts from the intern set (`copy_patch_mc_intern_set.lua`)
2. Calls `Bank.build_mc_bank()` (same function from `copy_patch_mc.lua`) which invokes `gcc`
3. Generates C source files with the compiled binary blobs embedded as `unsigned char[]` arrays
4. Supports parallel sharded builds via multiple `luajit` worker processes (`LALIN_MC_BANK_WORKER=1`)

**The `gcc` invocation path in `build_mc_bank()`**: `os.execute()` runs the system `gcc` binary. There is no other external compiler support for MC stencils.

### back_command_binary.lua — NOT a GCC invoker

**File**: `lua/lalin/back_command_binary.lua`

This file has **nothing to do with GCC or external compilation**. It is a Flatline binary encoder for `BackProgram` IR:
- It encodes backend IR commands (add, sub, load, store, branch, etc.) into a compact binary format
- Uses only `ffi` and `bit` libraries
- No `os.execute`, `io.popen`, or external process calls

### Makefile MC bank targets

**File**: `Makefile`

```makefile
# Lines 16-19: Paths
LALIN_MC_BANK_C = $(LALIN_BIN_DIR)/lalin_embedded_mc_bank.c
LALIN_MC_BANK_H = $(LALIN_BIN_DIR)/lalin_embedded_mc_bank.h

# Lines 32-33: MC bank build rule
$(LALIN_MC_BANK_C) $(LALIN_MC_BANK_H) &: $(shell find lua -name '*.lua' | sort) tools/gen_lalin_mc_bank.lua
	luajit tools/gen_lalin_mc_bank.lua $(LALIN_MC_BANK_C) $(LALIN_MC_BANK_H)
```

The MC bank is **prebuilt at build time** by running `luajit tools/gen_lalin_mc_bank.lua`, which:
1. Generates all stencil artifacts
2. Compiles them via `gcc` (default) 
3. Extracts the machine code from `.o` files
4. Embeds the binary blobs into C source files (`lalin_embedded_mc_bank.c` / `.h`)

### grep for `gcc`, `cc`, `clang`, `-O3` across all project files

**Confirmed**: The ONLY external C compiler invocation for MC stencils is:
- `lua/lalin/copy_patch_mc.lua` line 409: `local cc = opts.cc or os.getenv("CC") or "gcc"` → `os.execute()` with that compiler
- `tools/gen_lalin_mc_bank.lua` line 24: default `embedded_mc_cflags` with `-O3`

The `$(CC)` in Makefile line 50 is used to compile the **final `lalin` binary** (the Lua embedding host), not MC stencils.

---

## 2. TCC Role — What TCC Actually Does

### File: `lua/lalin/c_tcc.lua`

**TCC is used for RESIDUAL GLUE, NOT stencil compilation.**

#### What TCC compiles

In `lua/lalin/luajit_emit.lua`, function `emit_native_residuals()` (starting ~line 888):

```lua
-- Line 935: Only triggered when native_residual is "tcc"
if not (opts.native_residual == true or opts.native_residual == "tcc" or opts.tcc_residual == true) then return end
```

The residual compilation works as follows:

1. For each LuaJIT function that calls into an MC bank stencil, a **C wrapper** is generated
2. These wrappers look like (line ~884):
   ```c
   int32_t fn_wrapper(void *xs, int32_t start, int32_t stop) {
       return ((int32_t (*)(void*, int32_t, int32_t))((uintptr_t)__lalin_native_addr_fn_apply_...))
           (xs, start, stop);
   }
   ```
3. TCC compiles the combined C source **in memory** via `__c_tcc.compile()` (line ~941):
   ```lua
   local __session, __err = __c_tcc.compile(__native_source, { libraries = { 'm' } })
   ```
4. The resulting symbols are extracted via `__session:symbol()` and replace the original LuaJIT trace functions

#### What TCC does NOT do:
- TCC does **NOT** compile the stencils themselves (stencils are precompiled by `gcc` into binary blobs)
- TCC does **NOT** invoke any external compiler binary — it's an in-memory library (libtcc)
- TCC does **NOT** handle `-O3`, `-march=native`, or any optimization flags
- TCC is **completely optional** — probed via `c_tcc.available()` which tries `ffi.load("tcc")` etc.

#### How TCC is called in copy_patch_mc.lua

**TCC is NOT called in `copy_patch_mc.lua` at all.** The only c_tcc usage is:
- In `luajit_emit.lua` for residual compilation (`c_tcc.compile()`)
- In `init.lua`'s `compile_c()` as an optional runner (`opts.runner == "libtcc"`)

---

## 3. C Stencil Emission

### File: `lua/lalin/stencil_c.lua`

**Function**: `api.source(artifacts, opts)` at line 1302

This function generates complete C source code for all stencil artifacts:
```lua
function api.source(artifacts, opts)
    -- Line 1309: Always includes stdint, stddef, string, math headers
    local decls = {
        C.include "stdint.h",
        C.include "stddef.h",
        C.include "string.h",
        C.include "math.h",
        C.typedef. ml_index [C.intptr_t],
    }
    -- Line 1321: For each artifact, generates a C function using the LLBL C emitter
    for _, artifact in ipairs(artifacts or {}) do
        decls[#decls + 1] = artifact_decl(artifact)
    end
    -- Line 1327: Emits complete C translation unit
    return C.emit_unit(C.unit. lalin_stencil_unit { ... })
end
```

**The C stencil format**: Each artifact produces a standalone C function (e.g., `apply_n_decl`, `reduce_n_decl`) that:
- Takes raw pointer parameters + start/stop indices
- Contains only loops, arithmetic, and memory accesses
- No external calls, no allocation, no complex control flow

**Connection to MC bank build**: The `build_mc_bank()` function calls `StencilC.source(artifacts)` to get C source, writes it to a `.c` file, then compiles it with `gcc -c` to get an object file.

---

## 4. The `lalin.compile()` Default Path

### File: `lua/lalin/init.lua`, function `M.compile()` at line 565

```lua
function M.compile(name_or_decls, decls_or_opts, maybe_opts)
    -- ...
    opts.copy_patch = "bc"            -- Line 580: FORCES bc mode
    local artifact = M.emit_luajit_artifact(decls, opts)
    -- Line 582: Loads the emitted source as a LuaJIT chunk
    local chunk, err = loader(artifact.source, "@" .. tostring(opts.name or name) .. ".luajit.lua")
    local module = chunk()
    return module
end
```

**Key fact**: `lalin.compile()` defaults to `copy_patch = "bc"` — the **LuaJIT bytecode copy-patch** path. This is the easy/portable path.

**By contrast**, `M.emit_luajit_artifact()` (line ~645) defaults to `copy_patch = "mc"`:
```lua
local copy_patch = tostring(opts.copy_patch or "mc")
```

And `M.emit_luajit_plan_artifact()` (line ~725) explicitly **errors** if `copy_patch == "mc"` without a prebuilt bank:
```lua
if mc_bank == nil and #(plan.artifacts or {}) > 0 and plan.copy_patch == "mc" then
    error("emit_luajit_plan_artifact: copy_patch='mc' requires a prebuilt MCStencilBank; ad hoc bank builds are not part of the JIT path", 2)
end
```

**BC fallback**: The BC bank is built on the fly when needed (line ~728):
```lua
if bc_bank == nil and #(plan.artifacts or {}) > 0 and plan.copy_patch == "bc" then
    bc_bank = assert(plan.backend.build_bc_bank(plan.artifacts, { ... }))
end
```

---

## 5. LuaJIT Backend Pipeline

### File: `lua/lalin/luajit_backend.lua`

**`lower_module()`** (line ~107):
```lua
function api.lower_module(module, opts)
    -- Builds kernel, flow, value, mem, effect from the module
    local graph, flow, value, mem, effect, kernel = Lower.build_kernel(module, opts)
    -- Plans schedules
    local schedule_plan = CodeSchedulePlan.plan(module, kernel, flow, value, mem, effect, target_model(opts))
    -- Plans stencil machines (identifies which stencils are needed)
    local stencil_machines = Lower.plan_stencil_machines(module, { ... })
    -- Returns: lj_module, facts, artifacts, rejects
    local lj_module, facts = Lower.lower_module(module, { ... })
    return lj_module, facts, artifacts, rejects
end
```

**Returns**: A LuaJIT module descriptor (an in-memory IR tree), plus `facts` (containing the stencil plan, schedule plan, execution plan), `artifacts` (the stencil artifacts to materialize), and `rejects` (any unsupported kernels).

**`build_mc_bank` is NOT connected to `emit_lua_artifact` — they are separate paths**:
- `build_mc_bank()` (line 243) just delegates to `StencilBank.build_mc_bank()`
- `emit_lua_artifact()` (line ~271) **requires a prebuilt bank** for MC mode
- The bank is prebuilt at project build time (Makefile) via `tools/gen_lalin_mc_bank.lua`

**`native_residual = "tcc"`** (line ~71):
```lua
local function native_residual_mode(opts)
    opts = opts or {}
    if copy_patch_mode(opts) == "bc" then return nil end
    if opts.native_residual ~= nil then return opts.native_residual end
    if opts.tcc_residual ~= nil then return opts.tcc_residual end
    return "tcc"                    -- Default when MC mode
end
```

So: when MC mode is active, `native_residual` defaults to `"tcc"`. The residual is an optional optimization that replaces LuaJIT trace calls with direct C function calls compiled by TCC.

---

## 6. Module Bank / Embedded MC Bank

### File: `lua/lalin/copy_patch_mc_intern_set.lua`

This file defines the **comprehensive set of stencil operations** that the MC bank must support:
- It enumerates every possible combination of: kernel kind (`apply_n`, `reduce_n`, `scan_n`, `scatter_reduce_n`), memory layout (contiguous, view, slice, indexed, field, SoA, etc.), producer shape (range1d, range_nd2, tiled_nd2, window_nd1), and schedule (scalar, vector)
- Function `M.artifact_for_cell(cell)` constructs the stencil artifact for each combination
- Function `M.artifact_batches(opts, emit)` feeds these artifacts to the bank builder in batches
- The `c_decls()` and `ffi_preamble()` methods provide C declarations needed by the stencils

This is the **prebuilt repertoire**: instead of compiling stencils ad-hoc, the project precompiles this complete matrix into a C array of machine-code blobs.

### File: `lua/lalin/kernel_emit_support.lua`

This file provides **classify()** which determines whether a kernel can be emitted by the current backend:
- Checks lane access patterns, value expressions, kernel bindings
- Determines whether the kernel is: closed-form, scalar, or vector
- Returns `rejects` listing why a kernel can't be emitted

### File: `lua/lalin/lower_strategy_emit_rules.lua`

Simple dispatch rules for selecting emission strategies (`code`, `closed_form`, `scalar_kernel`, `vector_kernel`, `missing_schedule`, `unsupported`).

---

## 7. External Compiler Pipeline — Complete Search

**Search across `lua/lalin/` and `tools/` for process invocation:**

| File | Call | What it does |
|------|------|-------------|
| `copy_patch_mc.lua:403` | `os.execute("mkdir -p ...")` | Creates build dir |
| `copy_patch_mc.lua:425` | `os.execute(gcc ...)` | **Compiles stencil C to .o** |
| `copy_patch_mc.lua:428` | `capture("readelf -Wr ...")` | Parses relocations |
| `copy_patch_mc.lua:432` | `capture("readelf -SW ...")` | Parses sections |
| `copy_patch_mc.lua:436` | `capture("readelf -Ws ...")` | Parses symbols |
| `gen_lalin_mc_bank.lua:31` | `os.execute()` wrapper | Runs GCC via `build_mc_bank()` |
| `gen_lalin_mc_bank.lua:298` | `io.popen("getconf _NPROCESSORS_ONLN")` | Detects CPU count |
| `gen_lalin_module_bank.lua:19` | `os.execute("mkdir -p ...")` | Creates dir |
| `gen_lalin_module_bank.lua:62` | `io.popen("find ...")` | Lists .lua files |
| `luajit_emit.lua:941` | `c_tcc.compile()` | **In-memory TCC, NOT an external process** |

**No usage of `clang`, `-O2`, `-O1`, `popen` for compilation exists anywhere in the pipeline.** The only C compilers invoked are:
1. **`gcc`** (or `$CC`) — for MC stencil compilation (external process, `-O3 -march=native`)
2. **`libtcc`** (in-memory) — for residual glue functions (no flags, no optimization)

---

## Complete Pipeline Diagram

```
                      PREBUILD (Makefile)
                      ====================
Lalin source (.lua)
  → gen_lalin_mc_bank.lua       gen_lalin_module_bank.lua
    → StencilC.source()           → string.dump() each .lua file
    → gcc -c -O3 -march=native   → C byte-array source
    → readelf (reloc/section/symbol parsing)
    → binary blob extraction + local relocation materialization
    → C byte-array source files
    → lalin_embedded_mc_bank.c   → lalin_embedded_bc_bank.c
    → lalin_embedded_mc_bank.h     lalin_embedded_bc_bank.h

                      RUNTIME — lalin.compile() (default BC path)
                      ==========================================
luajit runs lalin.compile(fns)
  → DSL projection
  → typecheck
  → LalinCode facts
  → kernel + schedule + stencil lowering
  → artifacts generated (stencil descriptors)
  → build_bc_bank() — generates LuaJIT bytecode traces (no compiler needed)
  → emit_lua_artifact() 
    → stencil source (LuaJIT BC inline code for stencils)
    → module source (LuaJIT traces for non-stencil functions)
  → loadstring() → return module with callable functions

                      RUNTIME — emit_luajit_artifact() (MC path)
                      =========================================
luajit runs lalin.emit_luajit_artifact(fns, { copy_patch = "mc" })
  → DSL projection → typecheck → code facts → lowering
  → artifacts generated
  → EMIT: requires prebuilt MCStencilBank (from compile-time)
    → emit_mc_bank_source() — embeds pre-compiled machine-code blobs
      with mmap+install code for runtime loading
    → emit_module() — LuaJIT traces for non-stencil code
  → Embedded MC bank is loaded:
    → mmap() + ffi.copy() to install machine-code blobs
    → mprotect() to make executable
    → ffi.cast() to get function pointers
  → Optional TCC residual:
    → For each stencil call site, generate a C wrapper
    → libtcc compiles wrappers in memory
    → ffi.cast() to replace LuaJIT trace calls with direct C calls
  → loadstring() → return module

                     COMPILER USAGE SUMMARY
                     ======================
┌─────────────────────────────────────────────────────────────────┐
│         STENCIL COMPILATION:  gcc (or $CC) -c -O3 -march=native │
│           (run as external os.execute, at prebuild time only)   │
│                                                                 │
│         RESIDUAL COMPILATION:  libtcc (in-memory, optional)     │
│           (runs at load time, compiles thin C wrappers)         │
│                                                                 │
│         BC FALLBACK:  No compiler needed at all                 │
│           (LuaJIT bytecode generated + patched at runtime)      │
└─────────────────────────────────────────────────────────────────┘
```

---

## Key Corrections vs. Previous Architecture Understanding

1. **MC stencils are NOT compiled by TCC.** They are compiled by **`gcc`** at prebuild time. TCC is only used for the optional residual glue optimization.

2. **`lalin.compile()` defaults to BC**, not MC. The BC path requires no external compiler at all.

3. **The MC bank is prebuilt**, not built on demand. Ad-hoc MC bank builds are explicitly rejected ("not part of the JIT path").

4. **`back_command_binary.lua`** is an IR encoder, not a GCC invoker.

5. **The compiler used for the final `lalin` binary** (Makefile `$(CC) -O2`) is separate from the MC stencil compiler (`gcc -O3 -march=native`).
