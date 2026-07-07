# LLPVM Retirement 
Scout and retire the LLPVM low-level VM member. Lalin regions + GPS + compiler pipeline have proven powerful enough to replace the bytecode image/world/tape/machine/phase scaffolding.
**Workflow ID**: wf-llpvm-retirement
**Started**: 2026-07-07 03:44:17
---

## Scout Output — 2026-07-07 03:46:12

Now I have a comprehensive picture. Here's the full scout report:

---

## Files Retrieved

### LLPVM Core Module (`lua/llpvm/`)
1. **`lua/llpvm/init.lua`** (lines 1-60) — Public facade. Exposes `dsl`, `asdl`, `task_model`, `T`, `B`, `language`, `meta_language`, `ProgramSpec`, `ProgramImage`, `MachineLanguage`, `TaskSpec`, `Ident`, `Path`, `Field`, `Call`, plus `use`, `loadstring`, `loadfile`, `load`, `format`, `describe`, `describe_head`, `describe_role`, `schema`, `tape_items`, `llpvm`, `_`, `spread`, `bytebuffer`, `records`, `validate`, `inspect`, `task_run`, `task_event`, `task_step`, `record_task`, `bytecode`, `format_file`, `write_format_file`.

2. **`lua/llpvm/dsl.lua`** (lines 1-1379) — The main DSL definition. Requires `llbl`, `llpvm.bytecode`, `ffi`. Defines ProgramSpec, ProgramImage, TaskSpec, MachineLanguage classes with metatables `__llpvm_dsl_class` tag. Creates `LLPVMDsl` dialect via `llbl.dialect`. Exports `M.llpvm = llbl.zone_head(...)`. `format()`, `to_program()`, `validate()`, `file_text()`, `make_language_env()`, `meta_language`, `use()`, `load()`, `loadstring()`, `loadfile()`, `namespace()`, `describe()`. Uses LLBL fragments/spread/roles.

3. **`lua/llpvm/bytecode.lua`** (lines 1-694+) — Bytecode encoder/builder. MAGIC="LLPV", VERSION=2. Requires `lalin.asdl` and `llpvm.asdl`. Encodes ASDL programs into binary format, decodes/validates bytecode images.

4. **`lua/llpvm/asdl.lua`** (lines 1-96) — LLPVM ASDL schema. Defines `LlPvm` namespace with: Symbol, ScalarType, Type, Field, OpKind, Abi, World, OpPayloadValue, Op, ArgValue, Args, Tape (Empty/Once/Seq/Concat/PhaseMap), Machine (RegionMachine), CacheMode, CachePolicy, Phase, Diagnostic, TaskEventSpec, TaskSpec, TaskStepRun, TaskRunEvent, TaskRun, Program. Uses `lalin.asdl` context and `lalin.schema_context` for definition.

5. **`lua/llpvm/task.lua`** (lines 1-60) — Task declarations and run records. Provides `event()`, `step()`, `run()`, `record_handle()`, `describe_run()`, `from_llbl_handle()`. Required by both `llpvm.init` and `lalin.phase_execute`.

6. **`lua/llpvm/runtime_ffi.lua`** (lines 1-262) — Retired/optional native C FFI runtime wrapper. FFI cdef for `llpvm_runtime_LlStatus`, `llpvm_runtime_LlVmConfig`, `llpvm_runtime_LlVmReport`, and functions `llpvm_open/close/load_program/apply_phase/drain/drain_count/report`. Uses `require("llpvm.native.build_c")`.

7. **`lua/llpvm/native/`** — Empty directory (previously held `.mlua` files that were already deleted in a prior workflow).

---

### CRITICAL CORE DEPENDENCY: Lalin init.lua
8. **`lua/lalin/init.lua`** (lines 72, 106-161, 221-266, 330-350, 372-396, 423, 484-493) — **This is the most important file.** It deeply integrates LLPVM as a language member:

   - **Line 72**: `local llpvm_dsl = require("llpvm.dsl")`
   - **Lines 106-109**: `is_llpvm_value()` — checks `ProgramSpec`, `ProgramImage`, `TaskSpec`
   - **Lines 139-161**: `collect_llpvm_values()` — recursive walker that finds llpvm values inside Zones and LanguageBundles
   - **Lines 221-247**: `llpvm_diagnostics()` — calls `llpvm_dsl.to_program()`, `projected:bytecode()`, `llpvm_dsl.validate()`, `projected:asdl()` for TaskSpec
   - **Lines 249-266**: `llpvm_index()` — populates index symbols with `kind = "llpvm"`, `member = "llpvm.dsl"`
   - **Lines 330-350**: `llpvm_markdown()` — generates markdown doc section for `llpvm.dsl`
   - **Lines 372-396**: `prefer` map mapping 22 names (`cache`, `entry`, `event`, `from`, `input`, `lang`, `language`, `llpvm`, `machine`, `op`, `output`, `phase`, `pvm`, `record`, `root`, `tape`, `task`, `to`, `type`, `world`) to `"llpvm.dsl"`
   - **Line 423**: `"llpvm"` in `reserved` names list
   - **Lines 484-493**: Full language member definition:
     ```lua
     {
         name = "llpvm.dsl",
         dialect = llpvm_dsl.meta_language,
         exports = function(opts) return llpvm_dsl.make_language_env(opts) end,
         match = is_llpvm_value,
         format = function(value, opts) return llpvm_dsl.format(value, opts) end,
         diagnostics = llpvm_diagnostics,
         index = llpvm_index,
         markdown = llpvm_markdown,
         requires = { "lalin.types", "lalin.schema" },
         provides = { "llpvm.dsl" },
         semantics = { owns = { "bytecode-program", "bytecode-tape", "process-task", "pvm-image" }, uses = { "authoring-substrate", "diagnostics", "language-composition", "fragments", "namespaces", "origins", "native-type-values", "type-language", ... } }
     }
     ```

---

### CRITICAL CORE DEPENDENCY: phase_execute.lua
9. **`lua/lalin/phase_execute.lua`** (line 10) — `local LlTask = require("llpvm.task")` — Used to create `TaskRun`, `TaskRunEvent`, `TaskStepRun` objects. Uses `LlTask.event()`, `LlTask.step()`, `LlTask.run()`. **This is a real runtime dependency** — the phase executor records task execution using LLPVM's task model.

---

### LLBL Core (documentation/example references only)
10. **`lua/llbl.lua`** (lines 3438, 6590, 6598, 6649) — References `llpvm` in comments and generated markdown as example zone/member name. Not a code dependency; uses `llpvm` as a canonical example in documentation output:
    - Line 3438: comment `-- llpvm { ... } -> Zone(member="llpvm.dsl")`
    - Line 6590: markdown doc example `llpvm.task. compile`
    - Line 6598: markdown doc example `llpvm { ... }`
    - Line 6649: markdown doc example `llpvm { ... }`

---

### Test Files
11. **`tests/llpvm/test_llpvm_task_dsl.lua`** (39 lines) — Tests task spec/run event ASDL helpers. Requires `llpvm`.
12. **`tests/llpvm/test_llpvm_runtime_ffi.lua`** (53 lines) — Asserts `llpvm.runtime_ffi` is NOT loaded (retired C/FFI path).
13. **`tests/llpvm/test_llpvm_lua_api.lua`** (117 lines) — Tests public LLPVM DSL (exposes ASDL context, no parallel type API, reports `llpvm.dsl` capability).
14. **`tests/llpvm/test_llpvm_language_use.lua`** (150 lines) — Tests Lalin language environment includes `llpvm` namespace, language use patterns, formatter delegation, indexing, and markdown generation.
15. **`tests/llpvm/test_llpvm_bytecode.lua`** (80 lines) — Tests LLPV bytecode DSL, inspect/validate process, `ProgramImage:write`.
16. **`tests/llpvm/test_llbl_language_algebra.lua`** (143 lines) — LLBL language algebra test (uses LLBL but lives in LLPVM test suite).

17. **`tests/frontend/test_lua_dsl_host_eval_role.lua`** (lines 8, 42-46) — Requires `llpvm.dsl`, uses `llpvm.schema {}` to verify qualified role fragment IDs. **This test lives in the frontend suite but depends on llpvm.dsl.**

---

### Demo Files
18. **`demo/lua_vm.lln`** (547 lines) — Milestone 3 Lua-ish VM skeleton. Pure Lalin region code, **no LLPVM dependency at all.** This is actually a Lalin-native VM written in regions; the name is coincidental (LuaVM, not LLPVM).
19. **`demo/vm.lln`** (939 lines) — Organized register VM demo. Pure Lalin region code, **no LLPVM dependency at all.** Uses `struct`, `region`, `fn` — never references llpvm.

---

### Build/Packaging
20. **`lalin-dev-1.rockspec`** (line 43) — `cp -r lua/llpvm "$(PREFIX)/share/lua/$(LUA_VERSION)/"` — Installs the llpvm module tree.
21. **`Makefile`** — **No mention of llpvm at all.** The Makefile builds LuaJIT and the standalone binary; llpvm is only surfaced through rockspec install.

---

### Documentation Files
22. **`docs/LLPVM_GUIDE.md`** (full file, ~120 lines) — Dedicated LLPVM guide. Covers public module API, DSL, tasks, bytecode. References `tests/llpvm/test_llpvm_*`.
23. **`docs/ARCHITECTURE.md`** (lines 584, 605, 663, 702) — Mentions LLPVM in architecture: consumes region-shaped work, owns low-level VM/task semantics, listed alongside Lalin/LalinSchema in symbol ownership.
24. **`docs/LLBL_GUIDE.md`** (lines 447, 456) — Example code using `llpvm.task. compile`, `llpvm { ... }`.
25. **`docs/CONVENTIONS.md`** (lines 46, 203) — `llpvm_` as LLPVM concept prefix; `tests/llpvm/test_*.lua` pattern.
26. **`docs/LLBL_BRACKET_EVAL_ARCHITECTURE.md`** (lines 518, 530, 543) — Mentions LLPVM in migration considerations: qualified fragments, role code, custom spread behavior.

### README
27. **`README.md`** (lines 103, 127, 176) — Running `llpvm` tests; `lua/llpvm/` directory listing; mentions `docs/LLPVM_GUIDE.md`.

### AGENTS.md
28. **`AGENTS.md`** (lines 288, 353, 364) — Running `llpvm` tests; directory listing; guide listing.

### Workflow Contexts
29. **`.pi/workflows/wf-llpvm-retirement.md`** — The current workflow, just started.
30. **`.pi/workflows/wf-83d1ac99.md`** and **`.pi/workflows/wf-83d1ac99.edit-plan.json`** — Prior workflow that already deleted many LLPVM-related files: `lua/llpvm/native/*.mlua`, `lua/llpvm/native/build_c.lua`, `benchmarks/bench_llpvm_image_load.lua`, `experiments/mlui-llpvm/`. Left the core LLPVM module intact.
31. **`.pi/workflows/wf-1085b307.md`** and **`.pi/workflows/wf-1085b307.edit-plan.json`** — Role/fragment qualification workflow that touched `lua/llpvm/dsl.lua` (qualified RoleIds for LLPVM fragments).
32. **`.pi/workflows/wf-972153a7.md`** — Workflow analyzing LLPVM native `.mlua` files.

---

## Key Code

### The dependency chain:
```
lalin.phase_execute  ──requires──▶  llpvm.task  ──requires──▶  llpvm.asdl  ──requires──▶  lalin.asdl + lalin.schema_context
lalin.init           ──requires──▶  llpvm.dsl   ──requires──▶  llpvm.bytecode ──requires──▶ llpvm.asdl + lalin.asdl
llpvm (init.lua)     ──requires──▶  llpvm.dsl + llpvm.bytecode + llpvm.asdl + llpvm.task
llpvm.runtime_ffi    ──requires──▶  llpvm.native.build_c (was already deleted in wf-83d1ac99, making this file broken)
```

### What llpvm.task provides to phase_execute:
```lua
LlTask.event(seq, kind, payload)   -- creates T.TaskRunEvent
LlTask.step(index, phase, machine, status) -- creates T.TaskStepRun
LlTask.run(name, status, events, steps)   -- creates T.TaskRun
```

### What llpvm.dsl provides to lalin.init:
- `llpvm_dsl.ProgramSpec`, `llpvm_dsl.ProgramImage`, `llpvm_dsl.TaskSpec` — metatables for `is_llpvm_value()` (line 108)
- `llpvm_dsl.to_program()` — projection (line 224)
- `llpvm_dsl.validate()` — bytecode validation (line 234)
- `llpvm_dsl.format()` — formatting (line 488)
- `llpvm_dsl.make_language_env()` — environment setup (line 486)
- `llpvm_dsl.meta_language` — the LLPVMDsl LLBL dialect (line 485)

### The language member definition in lalin.init (lines 483-493):
This is a full language member slot in the `lalin` language. It has match/diagnostics/index/markdown/format functions, provides `"llpvm.dsl"`, requires `"lalin.types"` and `"lalin.schema"`, and claims semantic ownership of `"bytecode-program"`, `"bytecode-tape"`, `"process-task"`, and `"pvm-image"`.

### The prefer/reserved maps (lines 372-423):
22 strings in `prefer` are mapped to `"llpvm.dsl"` (plus `"llpvm"` in reserved). These cause `llpvm` to be loaded as a global prior to name resolution in the language environment.

---

## Relationships

1. **`lalin.phase_execute` ← `llpvm.task`**: This is the only *runtime* code dependency (not test/doc). The executor records TaskRun/TaskRunEvent/TaskStepRun using LLPVM's ASDL products. If LLPVM is retired, these task recording types need to either move to lalin's ASDL or be replaced with something simpler.

2. **`lalin.init` ← `llpvm.dsl`**: The main language composition glue. Lalin's language definition includes llpvm as a member. Retiring means: removing the member definition (lines 483-493), removing `is_llpvm_value`/`collect_llpvm_values`/`llpvm_diagnostics`/`llpvm_index`/`llpvm_markdown`, cleaning the `prefer`/`reserved` maps, and removing the `local llpvm_dsl` require.

3. **`llpvm.asdl` ← `lalin.asdl` + `lalin.schema_context`**: LLPVM defines its ASDL using lalin's schema infrastructure. This is self-contained — removing llpvm doesn't affect lalin's schema.

4. **`llpvm.bytecode` ← `llpvm.asdl` + `lalin.asdl`**: Bytecode encoding/validation for LLPVM programs. Only used by tests and llpvm.dsl.

5. **`llpvm.runtime_ffi`**: Already broken since its dependency `llpvm.native.build_c` was deleted in prior workflow. Can be cleanly removed.

6. **`tests/frontend/test_lua_dsl_host_eval_role.lua`**: Has a small test block (lines 42-46) verifying that `llpvm.schema {}` creates qualified fragments. This single test assertion uses llpvm.dsl as a test fixture for qualified role IDs. After retirement, this test can use a different fragment source or be removed.

7. **`demo/lua_vm.lln` and `demo/vm.lln`**: Neither uses LLPVM — they are pure Lalin region code. No action needed.

---

## Observations

1. **The workflow title says "Lalin regions + GPS + compiler pipeline have proven powerful enough to replace the bytecode image/world/tape/machine/phase scaffolding."** This frames the retirement as replacing LLPVM's conceptual space with Lalin's existing capabilities, not just deleting unused code.

2. **`llpvm.runtime_ffi.lua` is already dead code.** Its dependency `llpvm.native/build_c.lua` was deleted in wf-83d1ac99, and the test explicitly asserts the runtime is NOT loaded. The `lua/llpvm/native/` directory is empty.

3. **The prior workflow wf-83d1ac99 already did significant LLPVM cleanup**: deleted native `.mlua` files, `build_c.lua`, benchmarks, and experiments. The remaining LLPVM code is the core DSL, ASDL, bytecode, task model, and tests.

4. **`phase_execute.lua` is the only true runtime dependency** on llpvm. The task recording types (`LlTask.event`, `LlTask.step`, `LlTask.run`) use LLPVM's `LlPvm.TaskRun`, `LlPvm.TaskRunEvent`, `LlPvm.TaskStepRun`. These are simple product types with string/number fields that could be inlined or replaced with lalin-native ASDL or plain Lua records.

5. **The `lalin.init` wiring is extensive but structured**: It has a clear member slot pattern. The llpvm member definition (one of three alongside lalin.dsl and lalinschema.dsl) can be removed in a focused edit without breaking the language composition infrastructure itself.

6. **The `prefer` map is shared across members**: entries like `lalin`, `lln`, `schema` go to other members; entries like `llpvm`, `pvm`, `task`, `world`, `tape`, `machine`, `phase` go to llpvm.dsl. After retirement, the llpvm-preferring keys can be either removed from the prefer map (they won't resolve) or repurposed if any other member needs them.

7. **The `reserved` map** has `"llpvm"` and `"pvm"` — both can be removed since they were reserved for LLPVM.

8. **`tests/llpvm/test_llbl_language_algebra.lua`** is a pure LLBL test that was placed in the LLPVM test suite. It requires no llpvm module. It should either be moved to the core test suite or deleted if redundant.

9. **`tests/frontend/test_lua_dsl_host_eval_role.lua`** lines 42-46 use `llpvm.schema {}` as a convenient way to produce a qualified fragment for testing role IDs. After retirement, this test assertion must use an alternative fragment source.

10. **Documentation impact is broad but shallow**: LLPVM is mentioned in many docs as an example (zone syntax, member listing, namespace). These are reference examples, not deep architectural dependencies. The LLPVM_GUIDE.md is the only wholly-LLPVM document.

11. **No Makefile target references llpvm.** The `tests/run.lua` doesn't include llpvm in its default or `all` suite (confirmed by wf-83d1ac99). LLPVM tests are run manually with `luajit tests/run.lua llpvm` or individually.

12. **The `demo/lua_vm.lln` and `demo/vm.lln` files** are misleadingly named — they have nothing to do with LLPVM. The `lua_vm` is a Lalin-native region-based Lua bytecode interpreter, and `vm` is a register-VM demo. Both are pure Lalin region code demonstrating the power of regions/GPS, which is exactly what is replacing LLPVM.
