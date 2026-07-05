# C-owned native bank selector and installer hard-yank 
Hard-yank the current passive Lua/ASDL embedded bank materialization path and replace it with a C-owned native bank artifact that owns template selection and copy+patch installation. Lua compiler produces typed install plans and descriptors; generated C bank owns template bytes, selector tables, relocation metadata, and installer API.
**Workflow ID**: wf-native-bank-owned-installer
**Started**: 2026-07-05 15:17:30
---

## Scout Output — 2026-07-05 15:20:13

## Files Retrieved

1. `docs/ASDL_GUIDE.md` (lines 1-219) - Binding ASDL doctrine: leaf methods own semantics, no side tables/manual dispatch/table-soup.
2. `.pi/workflows/wf-native-bank-owned-installer.md` (lines 1-5) - Workflow goal: replace passive Lua/ASDL embedded bank materialization with C-owned selector/installer.
3. `lua/lalin/schema/native.lua` (lines 1-1345, 1510-1939, 2960-3279) - Core `LalinNative` schema: targets, template sources, banks, embedded banks, template graphs, copy plans, patch coordinates, install inputs/results/rejects.
4. `lua/lalin/native_template_sources.lua` (lines 1-1071, 5200-5810) - Source/manifest/request builders; complete-bank source enumeration; `NativeCompleteBankCapability:native_template_bank_request`.
5. `lua/lalin/native_template_support.lua` (lines 1-1985, especially 1190-1985) - Host target/support/complete-bank capability construction.
6. `tools/gen_lalin_mc_bank.lua` (lines 1-1107) - Offline bank generator: loads `NativeTemplateBankRequest`, compiles C sources, parses ELF, verifies relocations, emits C/H/Lua outputs.
7. `lua/lalin/native_object.lua` (lines 1-260) - Internal ELF64/x64 object parser used by generator.
8. `lua/lalin/native.lua` (lines 1-280, 1500-1840) - Native runtime methods: compile flow, default selection stub, family/protocol equality, patch application/write methods, executable calling.
9. `lua/lalin/native_mc.lua` (lines 1-591) - Embedded bank import, template selection, copy-plan layout, relocation application, mmap install.
10. `lua/lalin/native_backend.lua` (lines 1-244) - Public runtime facade: validates native banks/embedded banks, imports embedded banks, calls native compile.
11. `lua/lalin/native_code_methods.lua` (lines 230-410) - Code graph planning uses `bank:select_native_template`, constructs `NativeTemplateNode`s and patch bindings.
12. `lua/lalin/native_kernel_methods.lua` (lines 760-880, 1490-1560) - Kernel graph selection and binding patterns.
13. `lua/lalin/native_stencil_methods.lua` (lines 500-580, 950-1020) - Stencil graph selection and binding patterns.
14. `lua/lalin/init.lua` (lines 640-882) - Public `compile`, `compile_luajit`, `compile_native`, native bank option validation.
15. `src/lalin.c` (lines 1-58) - Binary embeds raw generated C bank but only installs debug metadata into Lua registry.
16. `Makefile` (lines 1-86) - Build rules for empty and complete generated native template bank C/H/Lua artifacts.
17. `tools/lalin_empty_native_bank_manifest.lua` (lines 1-24) - Empty bank request manifest.
18. `tools/lalin_complete_native_bank_manifest.lua` (lines 1-15) - Complete host bank request manifest.
19. `target/lalin_binary/lalin_native_template_bank.{h,c,lua}` (header lines 1-48; C lines 1-21; Lua lines 1-16) - Current generated empty bank.
20. `target/lalin_binary/lalin_complete_native_template_bank.{h,c,lua}` (header lines 1-48; C lines 1-200 and 163436-170876; Lua lines 1-73 and 37147-37227) - Current generated complete host bank, 7426 templates.
21. `tests/code_ir/test_native_bank_generator.lua` (lines 1-356) - Generator smoke, typed Lua bridge import, complete micro-op bank, rejection cases.
22. `tests/code_ir/test_native_mc_import.lua` (lines 1-518) - Embedded import, selection, copy/patch/install, relocs, constant pool, runtime symbol tests.
23. `tests/code_ir/test_native_template_sources.lua` (lines 1-737) - Manifest/source closure, source vocabulary, complete-bank constraints.
24. `tests/code_ir/test_native_code_graph_scalar.lua` (lines 1-472) - End-to-end scalar bank generation/import/native compile.
25. `tests/schema/test_schema_native.lua` (lines 1-704) - Native schema coverage.
26. `docs/ARCHITECTURE.md` (lines 434-724) and `docs/RESIDUAL_NATIVE_ARCHITECTURE.md` (lines 430-550) - Current architecture contract for native copy-patch.

## Key Code

### ASDL bank/source/runtime products

`lua/lalin/schema/native.lua` defines the current typed bank stack:

```lua
product. NativeTemplateBankRequest {
  field. id [LalinNative.NativeBankId],
  field. target [LalinNative.NativeTarget],
  field. runtime [LalinNative.NativeRuntime],
  field. manifest [LalinNative.NativeTemplateSourceManifest],
  field. sources [many [LalinNative.NativeTemplateSource]],
}

product. NativeTemplateBank {
  field. id [LalinNative.NativeBankId],
  field. target [LalinNative.NativeTarget],
  field. manifest [LalinNative.NativeTemplateSourceManifest],
  field. entries [many [LalinNative.NativeTemplateBankEntry]],
}

product. NativeEmbeddedTemplateBank {
  field. id [LalinNative.NativeBankId],
  field. target [LalinNative.NativeTarget],
  field. manifest [LalinNative.NativeTemplateSourceManifest],
  field. entries [many [LalinNative.NativeEmbeddedTemplate]],
}
```

`NativeTemplateGraph` / `NativeCopyPlan` / install schema:

```lua
product. NativeTemplateGraph {
  field. target [LalinNative.NativeTarget],
  field. protocol [LalinNative.NativeCallProtocol],
  field. frame_layout [LalinNative.NativeFrameLayout],
  field. nodes [many [LalinNative.NativeTemplateNode]],
  field. control_edges [many [LalinNative.NativeControlEdge]],
  field. value_edges [many [LalinNative.NativeValueEdge]],
  field. addresses [LalinNative.NativeModuleAddressPlan],
  field. entry [LalinNative.NativeTemplateNodeId],
  field. exits [many [LalinNative.NativeTemplateNodeId]],
}

product. NativeCopyPlan {
  field. graph [LalinNative.NativeTemplateGraph],
  field. layout [LalinNative.NativeCodeLayout],
  field. frame_layout [LalinNative.NativeFrameLayout],
  field. constant_pool_layout [LalinNative.NativeConstantPoolLayout],
  field. addresses [LalinNative.NativeModuleAddressPlan],
  field. total_size [number],
  field. bindings [many [LalinNative.NativePatchBinding]],
  field. protocol [LalinNative.NativeCallProtocol],
}
```

Patch vocabulary is ASDL-owned:

```lua
sum. NativePatchCoordinate {
  NativePatchImmediateI32 { field. value [number], },
  NativePatchImmediateI64 { field. value [number], },
  NativePatchPointer64 { field. address [number], },
  NativePatchFrameOffset { field. offset [number], },
  NativePatchFrameSize { field. size [number], },
  NativePatchConstantPoolEntry { ... },
  ...
}

sum. NativePatchHole {
  NativePatchImm32,
  NativePatchImm64,
  NativePatchPtr64,
  NativePatchRel32,
  NativePatchBranchRel32,
  NativePatchCallRel32,
  NativePatchFrameOffset32,
  NativePatchFrameSize32,
}
```

### Current runtime call flow

`lua/lalin/init.lua`:

```lua
function M.compile(...)
  if opts.luajit == true or opts.bytecode == true then
    return M.compile_luajit(...)
  end
  return M.compile_native(...)
end
```

Native path requires a supplied bank:

```lua
local function native_bank_for(Backend, opts, target)
  if opts.native_bank ~= nil then return Backend.require_native_bank(...) end
  if opts.bank ~= nil then return Backend.require_native_bank(...) end
  if opts.native_embedded_bank ~= nil then return Backend.require_imported_bank(...) end
  if opts.embedded_bank ~= nil then return Backend.require_imported_bank(...) end
  error("compile_native requires opts.native_bank/opts.bank ...")
end
```

`lua/lalin/native.lua`:

```lua
function Native.NativeCompileRequest:compile_native()
  local plan = self.subject:plan_native_copy(Native.NativePlanInput(self.target, self.runtime, self.bank))
  local copy_plan = plan:select_native_copy_plan(Native.NativeCopyPlanSelectionInput(self.target, self.runtime))
  local install = copy_plan:install_native(Native.NativeInstallInput(self.target, self.runtime, Native.NativeExecutableAllocatorMmap))
  return install:compile_native_result()
end
```

### Current embedded bank import and Lua-owned selection/install

`lua/lalin/native_mc.lua` imports `NativeEmbeddedTemplateBank` into active `NativeTemplateBank`:

```lua
function Native.NativeEmbeddedBankImportRequest:import_native_bank()
  ...
  local compiled = compiled_from_embedded(embedded, entry, i)
  entries[#entries + 1] = Native.NativeTemplateBankEntry(entry.family, compiled)
  ...
  return Native.NativeEmbeddedBankImported(
    Native.NativeTemplateBank(embedded.id, embedded.target, embedded.manifest, entries)
  )
end
```

Selection is linear Lua scan:

```lua
function Native.NativeTemplateBank:select_native_template(input)
  if self.target ~= input.target then ... end
  local matches = {}
  for _, entry in ipairs(self.entries) do
    local selected = entry:select_native_template(input)
    if asdl.isa(selected, Native.NativeTemplateSelected) then
      matches[#matches + 1] = entry
    end
  end
  ...
end
```

Copy/install is Lua+FFI:

```lua
function Native.NativeCopyPlan:install_native(input)
  local base_address = input.allocator:allocate_native_memory(input, self.total_size)
  ffi.copy(dest, bytes, #bytes)
  apply_node_relocation(...)
  ffi.copy(constant_pool_dest, bytes, #bytes)
  hole_layout.hole:apply_native_patch(...)
  return Native.NativeInstallSucceeded(Native.NativeExecutable(...))
end
```

### Offline generator outputs

`tools/gen_lalin_mc_bank.lua`:

- accepts manifest returning `NativeTemplateBankRequest`;
- compiles each `NativeTemplateSource.c_text` with `gcc` or `$CC`;
- parses object bytes with `NativeTemplateBytes:parse_native_object`;
- resolves:
  - text section
  - symbols
  - local relocations
  - continuation relocations
  - hole ordinal relocations
  - runtime-symbol relocations
  - constant-pool relocations
- emits:
  - `.h`: raw C structs
  - `.c`: raw bytes/string metadata
  - `.lua`: typed ASDL bridge returning `NativeEmbeddedTemplateBank`

Generated C header currently says it is not the import hook:

```c
/* Raw build/debug view of the embedded native bank.
   The generated Lua ASDL bridge is the typed runtime import boundary. */
...
/* Raw C access for binary embedding/debugging only; not an ASDL import hook. */
const LalinNativeEmbeddedTemplateBank *lalin_native_embedded_template_bank(void);
```

Generated complete C bank currently has 7426 passive entries:

```c
static const LalinNativeEmbeddedTemplate lalin_native_template_entries[] = { ... };

static const LalinNativeEmbeddedTemplateBank lalin_native_bank = {
  "lalin.native.complete.host",
  "native-template-host-x64-linux-sysv-64-le",
  lalin_native_template_entries,
  7426,
  7426
};
```

Generated Lua bridge recreates typed ASDL data separately:

```lua
local manifest = Native.NativeTemplateSourceManifest(..., 7426)
local entries = {}
extend(entries, (function() return { Native.NativeEmbeddedTemplate(...), ... } end)())
return Native.NativeEmbeddedTemplateBank(..., manifest, entries)
```

### C binary integration

`src/lalin.c` includes generated C bank:

```c
#include "lalin_native_template_bank.h"
```

but only publishes debug metadata:

```c
lua_pushstring(L, bank->bank_id ? bank->bank_id : "");
lua_setfield(L, LUA_REGISTRYINDEX, "lalin.native_template_bank.raw_id");
lua_pushinteger(L, bank->entry_count);
lua_setfield(L, LUA_REGISTRYINDEX, "lalin.native_template_bank.raw_count");
```

No C selector/installer API is exposed to Lua.

## Relationships

Current flow:

```text
NativeCompleteBankCapability / NativeTemplateSupportDomain
  -> native_template_sources.lua leaf methods
  -> NativeTemplateBankRequest(manifest, sources)
  -> tools/gen_lalin_mc_bank.lua
      -> compile C stencils to .o
      -> native_object.lua parses ELF64/x64
      -> resolve relocations/holes/constants/symbols
      -> NativeEmbeddedTemplateBank
      -> emit:
           C raw bank/debug view
           H raw structs
           Lua ASDL bridge
  -> runtime user passes generated Lua bridge value as opts.embedded_bank
  -> native_backend.import_embedded_bank()
  -> native_mc.NativeEmbeddedBankImportRequest:import_native_bank()
  -> NativeTemplateBank
  -> Code/Kernel/Stencil plan_native_copy methods select templates
  -> NativeTemplateGraph
  -> NativeTemplateGraph:select_native_copy_plan()
  -> NativeCopyPlan:install_native()
  -> mmap + ffi.copy + Lua relocation/patch methods
  -> NativeExecutable
```

Template selection call sites:

- `native_code_methods.lua`: `selected_entry(plan, family)` calls `plan.bank:select_native_template`.
- `native_kernel_methods.lua`: same pattern for kernel source shapes.
- `native_stencil_methods.lua`: same pattern for stencil source shapes.

Patch binding pattern:

```text
compiler graph builder chooses family
  -> bank entry selected
  -> node constructed with NativePatchBinding(node, instance, HoleId/HoleOrdinal, Coordinate)
  -> installer validates duplicate/missing bindings
  -> relocations and holes apply coordinates
```

## Observations

- The current “embedded C bank” is passive. It owns bytes as C arrays but not runtime selection, import, copy, relocation, patching, allocation, or install.
- Runtime uses the generated Lua bridge as the authoritative typed import boundary. This duplicates substantial bank metadata and template bytes into Lua ASDL constructors.
- `src/lalin.c` explicitly comments that raw C bank is debug/inspection only.
- Template selection is Lua-side linear scan over `NativeTemplateBank.entries` using ASDL family equality.
- Copy/patch/install is Lua-side in `native_mc.lua` with FFI `mmap`, `ffi.copy`, and ASDL leaf methods for patch writes.
- Relocation metadata exists in generated C only as stringly raw debug fields (`kind`, `symbol`, `addend`), while typed relocation objects used at runtime come from generated Lua ASDL constructors.
- The generator has strong typed build-time validation, but its C output is not a typed runtime API.
- Tests actively assert the current passive boundary:
  - generated C must not emit install hooks;
  - generated Lua bridge must construct `NativeEmbeddedTemplateBank`;
  - runtime import goes through `NativeEmbeddedBankImportRequest`.
- The complete bank already reaches large generated sizes: `lalin_complete_native_template_bank.lua` is ~37k lines; C is ~170k lines; both carry overlapping bank facts.
- The hard-yank target conflicts directly with present comments/contracts that say C is “debug only” and Lua bridge is the runtime import boundary.

## Worker Output — 2026-07-05 15:38:56

## Completed
Partial T002 implementation, then T002 was marked **blocked** honestly.

Implemented in `tools/gen_lalin_mc_bank.lua`:
- Generator now compiles sources into `NativeCompiledTemplate`, not removed embedded-bank ASDL values.
- Generated Lua now returns only a `NativeBankArtifact` descriptor.
- Generated C/H now expose C-owned template metadata, bytes, relocation/hole/constant-pool tables, sorted selector table, and selector API.
- Added install ABI payload structs, but **did not fake** an installer function.

## Files Changed
- `tools/gen_lalin_mc_bank.lua` - C-owned bank artifact generation and selector API.
- `.pi/workflows/wf-native-bank-owned-installer.edit-plan.json` - T002 marked blocked.

## Notes
Validation run:
- Schema load smoke: passed.
- Empty bank generation + C compile: passed.
- Non-empty generator smoke + C compile + selector executable test: passed.
- Lua artifact descriptor load as `NativeBankArtifact`: passed.

Blocked because full C installer needs a precise ASDL→C ABI projection for `NativeTemplateGraph` install data before emitting a real `lalin_native_bank_install`. I left `installer_symbol` as `""` rather than adding a placeholder.

## Worker Output — 2026-07-05 15:53:56

## Completed
T002 completed. Implemented a real generated C-owned installer API and marked the edit-plan task done.

Validation run:
- Schema load smoke
- Empty bank generation + C compile
- Non-empty generated bank + C compile + selector/install smoke
- Lua `NativeBankArtifact` descriptor load
- Hole binding install smoke
- Constant-pool relocation install smoke
- `luajit tests/code_ir/test_native_bank_generator.lua`

## Files Changed
- `tools/gen_lalin_mc_bank.lua` - emits `lalin_native_bank_install`, install ABI structs, selector/install metadata, relocation/hole/constant-pool handling, and records installer symbol in `NativeBankArtifact`.
- `tests/code_ir/test_native_bank_generator.lua` - updated expectations for C-owned bank artifacts and Lua descriptor-only output.
- `lua/lalin/native.lua` - guarded stale passive-bank method attachment so source generation loads after hard-yank schema removal.
- `.pi/workflows/wf-native-bank-owned-installer.edit-plan.json` - T002 marked done.

## Notes
No coms-net was used.

## Worker Output — 2026-07-05 16:14:13

## Completed
Implemented T003: replaced `native_mc` runtime with C-owned native bank FFI loading, selection, install-plan projection, and installer calls. Updated compile flow to use `NativeBankInstallRequest`.

## Files Changed
- `lua/lalin/native_mc.lua` - C bank FFI ABI, load/select/install methods, ASDL-to-C install payload projection.
- `lua/lalin/native.lua` - native compile now installs through C-owned bank installer.
- `lua/lalin/schema/native.lua` - added install-plan selection input, adjusted template handle, added C bank reject leaf.

## Notes
Validation passed:
- schema/native_mc load smoke
- `luajit tests/code_ir/test_native_bank_generator.lua`
- generated C shared-object load/select/install/execute smoke returned `7`
- generated C hole-binding install/execute smoke returned `77`

Also ran `luajit tests/schema/test_schema_native.lua`; it fails on stale passive embedded-bank constructor coverage, expected for later T006 test hard-yank. No coms-net used.

## Worker Output — 2026-07-05 16:20:29

## Completed
Implemented T004. Native Code/Kernel/Stencil graph builders now emit `NativeTemplateNode`s carrying `NativeTemplateFamily` selector data instead of Lua-selected `NativeTemplateBankEntry`s. Patch bindings now bind by typed hole id without inspecting compiled template metadata in Lua.

Validation:
- Native module load smoke passed.
- `luajit tests/code_ir/test_native_bank_generator.lua` passed.
- Custom `CodeFunc:plan_native_copy` smoke confirmed graph nodes carry `NativeTemplateFamily` and install-plan projection preserves selector keys.
- Grep confirmed no `plan.bank`, `select_native_template`, or `NativeTemplateSelectionInput` usage remains in the three graph-builder files.

## Files Changed
- `lua/lalin/native_code_methods.lua` - removed Lua bank selection, emits family-owned nodes, keeps public ABI frame limit independent of selected entries.
- `lua/lalin/native_kernel_methods.lua` - removed Lua bank selection and compiled-template hole ordinal probing.
- `lua/lalin/native_stencil_methods.lua` - removed Lua bank selection and compiled-template hole ordinal probing.
- `.pi/workflows/wf-native-bank-owned-installer.edit-plan.json` - marked T004 done with evidence.

## Notes
`test_native_code_graph_scalar.lua` and `test_native_kernel_contracts.lua` currently fail before graph-builder execution in stale `native_backend.lua` references to removed `NativeEmbeddedBankImported`; that is T005/T006 scope.

## Worker Output — 2026-07-05 16:28:36

## Completed
Implemented T005: backend/native compile now requires C-owned `NativeBankArtifact` or `NativeLoadedBank`, removes old passive embedded-bank import helpers, and binary embedding now exposes the generated C bank API instead of registry debug metadata.

Validation passed:
- `luajit tests/code_ir/test_native_bank_generator.lua`
- custom backend smoke: generated scalar bank, built `.so`, loaded artifact, compiled/executed add = 42
- `make lalin-bin`
- `target/lalin` FFI.C symbol/registry smoke
- `luajit tests/code_ir/test_lalin_binary.lua`
- `luajit tests/code_ir/test_luajit_backend_non_native.lua`

Marked T005 done in the edit plan.

## Files Changed
- `lua/lalin/native_backend.lua` - C-owned bank descriptor/loaded-handle API; removed embedded/passive bank path.
- `lua/lalin/init.lua` - compile option validation and loading for `NativeBankArtifact`/`NativeLoadedBank`.
- `src/lalin.c` - removed debug registry metadata; links exported `lalin_native_bank_*` API.
- `Makefile` - binary target depends on generated Lua artifact descriptor.
- `tests/code_ir/test_lalin_binary.lua` - updated binary smoke to load C-owned bank shared object.

## Notes
No coms-net was used.

## Worker Output — 2026-07-05 16:52:04

## Completed
Implemented T006 and marked it done.

- Removed stale test dependence on `NativeEmbeddedTemplateBank`, `NativeTemplateBankEntry`, Lua linear selection, `NativeCopyPlan`, and Lua installer paths.
- Added/updated C-owned bank tests for:
  - generated C shared-object load
  - selector key lookup
  - C installer execution
  - imm32 binding patch/rejects
  - continuation graph install/execute
  - constant-pool relocation
  - runtime symbol relocation
- Added typed `NativeBankPatchProjectionInput` and C-bank projection for runtime extern call patches.

Validation passed:
- `luajit tests/run.lua code_ir`
- `luajit tests/run.lua schema`
- `LALIN_RUN_SLOW=1 luajit tests/code_ir/test_lalin_binary.lua`

## Files Changed
- `lua/lalin/schema/native.lua`
- `lua/lalin/native_mc.lua`
- `lua/lalin/native.lua`
- `tests/code_ir/test_native_bank_generator.lua`
- `tests/code_ir/test_native_mc_import.lua`
- `tests/code_ir/test_native_c_continuation_branch.lua`
- `tests/code_ir/test_native_template_sources.lua`
- `tests/code_ir/test_native_code_control.lua`
- `tests/code_ir/test_native_code_graph_scalar.lua`
- `tests/code_ir/test_native_kernel_contracts.lua`
- `tests/code_ir/test_native_kernel_stencil.lua`
- `tests/code_ir/test_native_stencil_contracts.lua`
- `tests/code_ir/test_native_value_representation.lua`
- `tests/schema/test_schema_native.lua`

## Notes
No coms-net was used.

## Worker Output — 2026-07-05 17:15:52

## Completed
Implemented and completed T007.

- Regenerated complete C-owned native bank: 11357 templates.
- Compiled linked generated C bridge to `.so`.
- Verified generated Lua is only a `NativeBankArtifact` descriptor; no passive embedded/template bank constructors.
- Ran native compile smoke through C-owned installer: passed (`123`).
- Ran verification:
  - `luajit tests/run.lua schema` — 11 passed
  - `luajit tests/run.lua code_ir` — 50 passed, 1 slow skipped
  - `LALIN_RUN_SLOW=1 luajit tests/code_ir/test_lalin_binary.lua` — passed

## Files Changed
- `lua/lalin/schema/native.lua` - added complete ABI public adapter capability field.
- `lua/lalin/native_template_support.lua` - complete host capability now includes default public ABI adapters.
- `lua/lalin/native_template_sources.lua` - complete bank includes source-domain adapter/code closure needed by native compile.
- `tools/gen_lalin_mc_bank.lua` - emits compact Lua descriptor manifests for large C-owned banks.
- `target/lalin_binary/lalin_complete_native_template_bank.{c,h,lua}` - regenerated complete C-owned bank artifacts.
- `target/lalin_binary/lalin_complete_native_template_bank.so` - compiled smoke-test shared object.

## Notes
Marked T007 done in edit plan with concrete evidence. No coms-net used.
