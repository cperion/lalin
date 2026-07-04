# Native C&P closed-architecture refactor 
Fresh workflow for refactoring the native backend according to the corrected copy-and-patch architecture in docs/RESIDUAL_NATIVE_ARCHITECTURE.md. Prior side plans are obsolete; scout implementation state before creating a new edit plan.
**Workflow ID**: wf-native-cp-refactor
**Started**: 2026-07-02 17:12:28
---

## Scout Output — 2026-07-02 17:16:23

## Files Retrieved

1. `AGENTS.md` (lines 1-260) - Binding project doctrine: ASDL-first, leaf methods, no side tables/manual dispatch, native backend positioning.
2. `docs/ASDL_GUIDE.md` (lines 1-449) - ASDL modeling rules: products/unions, leaf dispatch, no tables/maps/side effects, harness expectations.
3. `docs/RESIDUAL_NATIVE_ARCHITECTURE.md` (lines 1-1840) - Binding corrected native architecture: residualless C-stencil copy-patch, deleted concepts, semantic owners, source closure, holes, ABI, frame/control protocol, target schema/method contract, implementation status.
4. `lua/lalin/schema/native.lua` (lines 1-1066) - Current `LalinNative` ASDL schema.
5. `lua/lalin/native.lua` (lines 1-565) - Core native methods: compile entrypoint, template/family equality, patch writes, call protocol helpers.
6. `lua/lalin/native_mc.lua` (lines 1-345) - Embedded bank import, bank selection, copy-plan layout, mmap install, relocation and patch application.
7. `lua/lalin/native_backend.lua` (lines 1-187) - Public native backend facade.
8. `lua/lalin/native_template_support.lua` (lines 1-797) - Support-domain/target/scalar/family constructors.
9. `lua/lalin/native_template_sources.lua` (lines 1-703) - Current C source generation proof slice.
10. `lua/lalin/native_code_methods.lua` (lines 1-389) - Current Code native graph lowering proof slice.
11. `lua/lalin/native_kernel_methods.lua` (lines 1-10) - Empty kernel native binding.
12. `lua/lalin/native_stencil_methods.lua` (lines 1-14) - Only `StencilInstance:plan_native_copy`.
13. `tools/gen_lalin_mc_bank.lua` (lines 1-853) - Offline bank generator; gcc/readelf object extraction; C/Lua embedded bank emit.
14. `Makefile` (lines 1-70) - Generated native bank paths and build rule.
15. `target/lalin_binary/lalin_native_template_bank.lua` (lines 1-15) - Current generated default empty embedded native bank.
16. `target/lalin_binary/lalin_native_template_bank.c` (lines 1-18) - Current generated raw C embedded native bank view.
17. `target/lalin_binary/lalin_native_template_bank.h` (lines 1-43) - Current generated C structs for raw embedded bank view.
18. `lua/lalin/init.lua` (lines 620-875) - Public `compile`, `compile_native`, `compile_luajit`, native-bank requirement boundary.
19. `lua/lalin/schema/init.lua` (lines 1-64) - Canonical schema modules include `native`; no `residual`.
20. `tests/schema/test_schema_native.lua` (lines 1-101) - Native schema smoke/import test.
21. `tests/code_ir/test_native_template_sources.lua` (lines 1-201) - Source closure/generator/import assertions.
22. `tests/code_ir/test_native_bank_generator.lua` (lines 1-95) - Trivial generated bank test.
23. `tests/code_ir/test_native_mc_import.lua` (lines 1-127) - Manual embedded bank import/install/call/reject test.
24. `tests/code_ir/test_native_c_continuation_branch.lua` (lines 1-191) - Manual branch continuation relocation/install/call test.
25. `tests/code_ir/test_native_code_graph_scalar.lua` (lines 1-278) - Full scalar support-domain generation and Code graph execution proof slice.
26. `tests/code_ir/test_luajit_backend_non_native.lua` (lines 1-47) - LuaJIT/native boundary assertions.
27. `tests/code_ir/test_lalin_binary.lua` (lines 1-70) - Stale embedded MC bank expectations; currently failing.
28. `docs/CONVENTIONS.md` (lines 130-169), `docs/ARCHITECTURE.md` (lines 140-229, 300-389, 455-584), `docs/LANGUAGE_REFERENCE.md` (lines 1010-1109) - Stale residual/MC/TCC assumptions.

## Key Code

### Correct architecture facts

`docs/RESIDUAL_NATIVE_ARCHITECTURE.md`:
```text
LalinCode / LalinKernel / LalinStencil ASDL
  -> methods on those ASDL values
  -> generated NativeTemplateSource C stencils
  -> offline gcc/clang -O3 object build
  -> ELF/object parser + verifier
  -> NativeEmbeddedTemplateBank
  -> LalinNative template graph
  -> LalinNative copy plan
  -> copied binary templates
  -> typed patch holes + continuation relocations
  -> executable native code
```

Hard decisions include:
```text
Runtime native compilation never invokes C compilation, ELF tools, TCC, or residual glue.
The baseline fragment protocol is C continuation + typed frame slots.
No exact-cell bank is the architecture.
No coverage accounting exists in compiler semantics.
```

Deleted terms include:
```text
ResidualFunctionPlan
CResidual*
StencilRequiresCompile
NeedsResidualC
Uncovered*
Coverage*
fallback native path
exact embedded MC bank as main bank
exact-cell bank enumeration
handwritten assembly template source
NativeTemplateAssembly
NativeTemplateLanguage
register-fragment baseline
...
```

Implementation status from doc:
```text
working scalar proof slice:
C-only source generation for spill-all frame-profile stencils
temporary readelf-backed object extraction
marker-hole resolution for offset/immediate proof holes
continuation relocation patching
frame-slot scalar graph lowering without continuation-arg/pass-through planning
single-scalar CodeTermReturn
...
```

Still missing per doc:
```text
NativeStencilGenerator/metavar/manifest ASDL and exact bank-count tests
extern-symbol hole ordinal protocol replacing marker-hole bootstrap
value-location planning with continuation args, spills, and pass-through budgets
NativeAbiProjection ASDL and full zero-or-one-result CodeSig lowering
...
internal object parser replacing temporary readelf-backed extraction
constant-pool ASDL, layout, relocation, and install support
```

### Current native schema

`lua/lalin/schema/native.lua` defines current target/artifact/graph/patch/call schema:
```lua
product. NativeTemplateSupportDomain { ... scalars, registers, abi, call_protocols,
  register_protocols, scratch_roles, accumulator_roles, vector_lanes, ranks, unroll_factors }

product. NativeTemplateSource {
  id, family, extraction, entry_symbol, c_text, declared_holes
}

sum. NativeTemplateExtraction {
  NativeExtractStandaloneCallable,
  NativeExtractEntryCallable { frame_bytes, first_continuation },
  NativeExtractContinuationFragment { successors },
  NativeExtractTerminalContinuation,
}
```

Current graph/copy facts:
```lua
product. NativeTemplateGraph {
  target, protocol, frame_layout, nodes, control_edges, value_edges, entry, exits
}

sum. NativeControlEdge {
  NativeFallthroughEdge, NativeConditionalBranchEdge, NativeLoopBackedgeEdge,
  NativeExitEdge, NativeContinuationEdge, NativeRuntimeCallReturnEdge
}
```

Patch/hole facts:
```lua
product. NativeHoleLayout { id, symbol, offset, width, hole }
product. NativePatchBinding { hole, coordinate }

sum. NativePatchCoordinate {
  NativePatchImmediateI32, NativePatchImmediateI64, NativePatchPointer64,
  NativePatchFieldOffset, NativePatchComponentIndex, NativePatchStride,
  NativePatchAffineCoeff, NativePatchAffineOffset, NativePatchWindowOffset,
  NativePatchBranchTarget, NativePatchCallTarget, NativePatchFrameOffset,
  NativePatchFrameSize, NativePatchScalarConst
}
```

Not present in schema by grep:
```text
NativeStencilGenerator
NativeStencilMetavar
NativeTemplateSourceManifest
NativeStencilSignature
NativeAbiProjection
NativeRelocationHoleOrdinal
NativeExternHoleSymbol
NativeConstantPool*
NativeFrameStackLimit
NativeExtractPublicAbiAdapter
ContinuationArg location/pass-through schema
```

### Runtime compile/install path

`lua/lalin/native.lua`:
```lua
function Native.NativeCompileRequest:compile_native()
    local plan = self.subject:plan_native_copy(Native.NativePlanInput(self.target, self.runtime, self.bank))
    local copy_plan = plan:select_native_copy_plan(Native.NativeCopyPlanSelectionInput(self.target, self.runtime))
    local install = copy_plan:install_native(Native.NativeInstallInput(self.target, self.runtime, Native.NativeExecutableAllocatorMmap))
    return install:compile_native_result()
end
```

`lua/lalin/native_mc.lua`:
```lua
function Native.NativeTemplateGraph:select_native_copy_plan(_input)
  -- lays graph nodes linearly, concatenates node bindings
end

function Native.NativeCopyPlan:install_native(input)
  -- validate hole bindings
  -- mmap RWX
  -- ffi.copy template bytes
  -- apply relocations
  -- apply hole patches
  -- return NativeInstallSucceeded(NativeExecutable(...))
end
```

Relocation handling:
```lua
if asdl.isa(relocation, Native.NativeRelocationContinuation) then
  local target_node = continuation_target(plan.graph, node.id, relocation.symbol)
  ...
  return apply_rel32(base_address, patch_address, base_address + target_offset, relocation.addend)
end
```

Call helpers in `lua/lalin/native.lua` use direct FFI casts by protocol; scalar helper infers 0/1/2 args:
```lua
local fn = f.cast(c_result .. " (*)(int32_t, int32_t)", input.executable.entry_address)
return tonumber(fn(input.args[1]:native_arg_i32(), input.args[2]:native_arg_i32()))
```

### Current source generation

`lua/lalin/native_template_sources.lua` uses hard-coded frame/marker constants:
```lua
local FRAME_PARAM0_OFFSET = 0
local FRAME_PARAM1_OFFSET = 16
local FRAME_RESULT_OFFSET = 32
local FRAME_BYTES = 256

local MARK_LHS = "0x11111111u"
local MARK_RHS = "0x22222222u"
local MARK_DST = "0x33333333u"
local MARK_SRC = "0x44444444u"
local MARK_IMM32 = "0x55555555u"
local MARK_IMM64 = "0x1122334455667788ULL"
```

C fragments are frame-only:
```lua
local function continuation_extern(symbol)
  return "extern void " .. symbol.name .. "(uint8_t *frame);"
end
```

Binary-op source builder:
```lua
function Native.NativeCodeInstBinaryAxis:append_native_template_sources(out, input)
  local lhs = frame_load(c_type, MARK_LHS)
  local rhs = frame_load(c_type, MARK_RHS)
  ...
  lines[#lines + 1] = "void " .. entry .. "(uint8_t *frame) {"
  ...
  lines[#lines + 1] = "    " .. next_symbol.name .. "(frame);"
  ...
  declared_holes = { frame_offset_hole(...lhs), frame_offset_hole(...rhs), frame_offset_hole(...dst) }
end
```

Support-domain generation:
```lua
function Native.NativeTemplateSupportDomain:native_template_sources()
  require_x64_sysv_target(self.target)
  local out = {}
  for _, scalar_support in ipairs(self.scalars) do
    scalar_support:append_native_template_sources(out, input)
  end
  return out
end
```

Observed generated counts from a LuaJIT probe:
```text
host_scalar_i32_bank_request(): 22 sources
host_scalar_bank_request():     221 sources
```

### Bank generator and generated paths

`Makefile`:
```make
LALIN_NATIVE_BANK_C = target/lalin_binary/lalin_native_template_bank.c
LALIN_NATIVE_BANK_H = target/lalin_binary/lalin_native_template_bank.h
LALIN_NATIVE_BANK_LUA = target/lalin_binary/lalin_native_template_bank.lua

$(LALIN_NATIVE_BANK_C) $(LALIN_NATIVE_BANK_H) $(LALIN_NATIVE_BANK_LUA) &: $(shell find lua -name '*.lua' | sort) tools/gen_lalin_mc_bank.lua
	luajit tools/gen_lalin_mc_bank.lua $(LALIN_NATIVE_BANK_C) $(LALIN_NATIVE_BANK_H) $(LALIN_NATIVE_BANK_LUA)
```

`tools/gen_lalin_mc_bank.lua`:
```lua
local build_root = os.getenv("LALIN_NATIVE_BANK_BUILD_DIR") or "target/native_bank_build"
...
local source_path = build_dir .. "/" .. stem .. ".c"
local object_path = build_dir .. "/" .. stem .. ".o"
write_file(source_path, source.c_text)

local cc = os.getenv("CC") or "gcc"
...
local readelf = os.getenv("READELF") or "readelf"
readelf -SW / -Ws / -Wr
```

Current default generated bank:
```lua
-- target/lalin_binary/lalin_native_template_bank.lua
return Native.NativeEmbeddedTemplateBank(
  Native.NativeBankId("lalin.native.empty"),
  Native.NativeTarget(...),
  {}
)
```

### Object extraction / hole handling

`tools/gen_lalin_mc_bank.lua` parses `readelf` text into Lua tables:
```lua
parse_sections(readelf_output)
parse_symbols(readelf_output, sections)
parse_relocations(readelf_output)
```

Relocations admitted:
```lua
R_X86_64_PC32 / R_X86_64_PLT32 -> NativeRelocationContinuation or NativeRelocationRel32
R_X86_64_64                    -> NativeRelocationAbs64
declared runtime symbols       -> NativeRelocationRuntimeSymbol
```

Hole resolution is marker-byte scanning:
```lua
local function resolve_declared_holes(source, text_bytes)
  for _, hole in ipairs(source.declared_holes or {}) do
    if offset < 0 then
      local found, count = find_unique_marker(text_bytes, hole.symbol, hole.width)
      ...
    end
  end
end
```

No current `NativeRelocationHoleOrdinal` / extern-symbol hole parsing.

### Current Code lowering proof slice

`lua/lalin/native_code_methods.lua`:
```lua
local FRAME_PARAM_STRIDE = 16
local FRAME_RESULT_OFFSET = 32
local FRAME_ALIGNMENT = 16
```

Frame placement state is mutable ASDL product:
```lua
product. NativeCodeGraphBuilderState {
  nodes, control_edges, value_edges, placements, frame_slots, next_frame_offset
}
```

Only scalar-ish leaves currently implemented:
```text
CodeModule:plan_native_copy
CodeFunc:plan_native_copy
CodeBlock:select_native_template_graph
CodeInst:append_native_inst_template
CodeInstConst -> CodeConstLiteral
CodeInstBinary
CodeInstFloatBinary
CodeInstCompare
CodeTermReturn
```

Linear continuation edge insertion:
```lua
local function append_node(state, node)
  local previous = state.nodes[#state.nodes]
  state.nodes[#state.nodes + 1] = node
  if previous ~= nil then
    state.control_edges[#state.control_edges + 1] =
      Native.NativeContinuationEdge(previous.id, node.id, Support.next_continuation_symbol())
  end
end
```

Return limitations:
```lua
function Code.CodeTermReturn:append_native_term_template(input)
  if #(self.values or {}) == 0 then internal_error("native C frame protocol does not yet model void CodeTermReturn") end
  if #(self.values or {}) > 1 then internal_error("Lalin native CodeTermReturn is invalid: Lalin has zero or one return value") end
  ...
end
```

### Kernel/Stencil native methods

`lua/lalin/native_kernel_methods.lua`: no semantic methods installed.

`lua/lalin/native_stencil_methods.lua`:
```lua
function Stencil.StencilInstance:plan_native_copy(input)
    return self.descriptor:select_native_template_graph(input)
end
```
No `StencilDescriptor:select_native_template_graph` implementation found.

## Relationships

- `lalin.compile()` defaults to `compile_native()` unless `{ luajit=true }` or `{ bytecode=true }`.
- `compile_native()` requires `opts.native_bank` / `opts.bank` / embedded bank; there is no default bank fallback in `lua/lalin/init.lua`.
- Native backend loading order:
  ```text
  native_backend.lua
    -> require lalin.native
    -> require lalin.native_mc
    -> require lalin.native_code_methods
    -> require lalin.native_kernel_methods
    -> require lalin.native_stencil_methods
  ```
- Runtime path:
  ```text
  NativeCompileRequest:compile_native
    -> NativeCompileSubject*:plan_native_copy
    -> CodeFunc:plan_native_copy (currently scalar proof slice)
    -> NativeTemplateGraph
    -> NativeTemplateGraph:select_native_copy_plan
    -> NativeCopyPlan:install_native
    -> NativeExecutable
    -> NativeCallProtocol*:call_native_executable
  ```
- Offline bank path:
  ```text
  NativeTemplateSupportDomain:native_template_sources()
    -> NativeScalarSupport:append_native_template_sources()
    -> NativeMachineScalarRep leaf source builders
    -> NativeTemplateBankRequest
    -> tools/gen_lalin_mc_bank.lua
       writes target/native_bank_build/<stamp>/<index>_<id>.c
       gcc -c
       readelf sections/symbols/relocs
       marker-scan holes
       emits NativeEmbeddedTemplateBank to Lua bridge
       emits raw C/H debug embedding
  ```

## Observations

- Focused native tests pass:
  ```text
  test_native_template_sources.lua ok
  test_native_bank_generator.lua ok
  test_native_mc_import.lua ok
  test_native_c_continuation_branch.lua ok
  test_native_code_graph_scalar.lua ok
  ```
- `tests/code_ir/test_lalin_binary.lua` is stale/failing after `make lalin-bin`; it expects `lalin_embedded_mc_bank.c/.h` and registry `lalin.embedded_mc_bank.count`, but current Makefile generates `lalin_native_template_bank.c/.h/.lua` and the default bank has 0 templates.
- Stale docs remain:
  - `docs/CONVENTIONS.md` still says “native residual materialization” and “TCC-compiled C residuals”.
  - `docs/ARCHITECTURE.md` still describes `residual_mc.lua`, `residual_mc_intern_set.lua`, `build_mc_bank`, `lalin_embedded_mc_bank.c/.h`, optional TCC residual glue.
  - `docs/LANGUAGE_REFERENCE.md` still documents `residual = "mc"`, `mc_bank`, and `plan.backend.build_mc_bank`.
- Current schema includes register locations/register protocol axes, but current proof-slice generated C uses frame-only `uint8_t *frame`; no continuation-arg/pass-through signature schema exists.
- Current source generation has no manifest product, no generator/metavar products, no `total_count`, and no exact manifest/source matching.
- Current object extraction is readelf-backed and string/table based, not `object bytes -> LalinNativeObject ASDL -> verifier`.
- Current hole mechanism is marker-byte scanning using magic immediates; extern-symbol hole ordinals are absent.
- Current ABI handling has `NativeCallCodeSig` and `NativeCallStencilAbi` leaves but no `NativeAbiProjection` vocabulary; FFI call helpers infer 0/1/2 args from `input.args`.
- Current frame layout is fixed proof-slice offsets plus append-only temp slots; it does not implement the full deterministic category ordering, frame stack limit, public adapter frame-size alloca hole, or aggregate/sret handling.
- Current Code control lowering is linear inst chain + return only; branch/jump/switch/edge-copy chains are not implemented except a manual test graph in `test_native_c_continuation_branch.lua`.
- Kernel native lowering is empty; stencil native lowering only delegates from `StencilInstance` to an unimplemented descriptor method.

## Knowledge-builder Output — 2026-07-02 17:19:08

## What Matters Most for This Problem

- **Closed-world cardinality**: native banks must be generated from finite ASDL generator/metavar manifests, not incidental source lists.
- **ASDL ownership**: semantic facts must originate on `LalinCode` / `LalinKernel` / `LalinStencil` leaves; `LalinNative` should describe artifact/projection shape, not become a semantic mirror.
- **Patch identity and relocation stability**: holes, continuation targets, runtime symbols, and constants need node-local/object-derived identities, not marker bytes or global string ids.
- **Sequencing constraints**: continuation signatures, ABI projection, object parsing, and constant pools are mutually dependent; partial changes can easily make the bank format incoherent.
- **Stale contract removal**: residual/TCC/MC-bank/fallback/coverage assumptions are not harmless naming drift; they contradict the corrected architecture.

## Non-Obvious Observations

### 1. Current patch binding identity cannot support “program size changes copy count”

`NativePatchBinding` is keyed only by `NativePatchHoleId`, and `NativeCopyPlan:install_native()` detects duplicate bindings globally. That means copying the same template family twice with different frame offsets/literals can collide on identical hole ids.

This is deeper than marker scanning: even with correct object-derived hole offsets, the runtime binding model currently lacks per-node/per-template-instance patch identity. The architecture says program size only changes how many times selected stencils are copied, but the current binding invariant makes repeated stencil instances hazardous.

Files: `lua/lalin/schema/native.lua`, `lua/lalin/native_mc.lua`.

---

### 2. `NativeTemplateFamily.axes` is acting as an informal metavar tuple, but it is not strong enough to be the manifest

The current source closure uses family id + axes + protocol equality for bank selection. That can select a template, but it cannot prove the architectural manifest contract:

- no generator identity,
- no declared metavar tuple,
- no logical stencil signature,
- no hole ordinal list,
- no continuation ordinal list,
- no relocation-kind declaration,
- no `total_count`.

So current tests can prove “some expected sources exist” but cannot prove “the closed support-domain manifest is exact.” This matters because bank cardinality is supposed to be a semantic invariant, not a byproduct of Lua loops in `native_template_sources.lua`.

---

### 3. The support-domain schema overstates active dimensions and understates required dimensions

`NativeTemplateSupportDomain` already carries registers, ABI conventions, call protocols, register protocols, scratch roles, accumulator roles, vector lanes, ranks, and unroll factors. But current source generation only loops over `scalars`.

At the same time, the architecture’s crucial finite dimensions are missing:

- pass-through bounds `K_int` / `K_float`,
- frame stack limit,
- public ABI adapter support set,
- logical continuation signature set,
- constant-pool support.

This creates a hidden mismatch: the schema looks broader than the implementation in stale directions, while lacking the fields that actually determine corrected bank cardinality.

---

### 4. Register-related schema is a possible regression vector

The corrected architecture says the baseline is frame/continuation, not register fragments. Yet current schema still includes:

- `NativeValueRegisterLocation`,
- `NativeRegisterSupport`,
- `NativeRegisterProtocol`,
- `NativeAxisRegisterProtocol`,
- accumulator/register locations.

Those may be valid target/ABI metadata eventually, but their presence in template protocol/family equality means they can accidentally become bank dimensions before continuation-arg planning exists. That would reintroduce the deleted “register-fragment baseline” through schema pressure rather than through explicit design.

---

### 5. Continuation edges are under-modeled for real control

Current relocation patching resolves `NativeRelocationContinuation` only through `NativeContinuationEdge { from, to, symbol }`.

But schema also has `NativeConditionalBranchEdge`, `NativeLoopBackedgeEdge`, `NativeExitEdge`, and `NativeRuntimeCallReturnEdge`; most of these do not carry successor symbols. The corrected architecture requires branch/switch/loop leaves to declare finite successor symbols and have graph edges to concrete nodes.

That means current graph shape has two competing control vocabularies:

- symbolic continuation relocations used by install,
- typed control edges that often lack relocation symbols.

Until those are reconciled, branch/switch lowering cannot be purely verifier-driven.

---

### 6. The fixed `first` / `next` continuation symbols are only safe for the proof slice

`native_code_methods.lua` automatically inserts `Support.next_continuation_symbol()` between consecutive nodes. That works for a linear scalar chain, but it cannot encode:

- multiple successors,
- block-entry identities,
- edge-copy chains,
- switch case ordinals,
- call-return continuations,
- terminal void/non-void signatures.

The architecture’s continuation symbols are part of stencil signatures and manifest identity. The current `next` convention is therefore not just incomplete; it obscures where control shape belongs in ASDL.

---

### 7. ABI projection is blocked by current call protocol conflation

`NativeCallProtocol` currently mixes several concepts:

- simple test-call helpers like `NativeCallReturnI32`,
- scalar return protocol,
- `NativeCallCodeSig`,
- `NativeCallStencilAbi`.

But there is no `NativeAbiProjection`, and FFI calls infer signatures from argument count. This conflicts with the architecture’s rule that Lua/FFI helpers are only host-boundary conveniences over an already typed projection.

The current entry stencil is especially constraining: generated entry C takes exactly two same-typed params and a scalar result, while `CodeFunc:plan_native_copy()` only uses the first param scalar to select the entry family. One-param, zero-param, mixed-param, descriptor, byref, void, and sret cases are therefore not merely unsupported; the family identity cannot distinguish them correctly.

---

### 8. Frame layout is currently proof-slice positional, not canonical semantic layout

The architecture requires deterministic category ordering: ABI params, sret/result, block params, locals, instruction temps, kernel/stencil state, call scratch, etc.

Current layout uses:

- param slots at `index * 16`,
- fixed result offset `32`,
- append-only temp slots from `next_frame_offset`,
- fixed generated frame size `256`.

This creates hidden overlap/ordering risks. For example, `next_frame_offset` starts at `0`, while param slots and result slots are manually placed at fixed offsets; the proof slice relies on the small test shape rather than a general invariant.

---

### 9. Constant-pool absence affects more than constants

The missing constant-pool ASDL is not isolated to literal lowering. It also affects:

- object layout size,
- executable allocation size,
- relocation patching,
- pointer/null constants,
- f32/f64 constants,
- aggregate/descriptor constants,
- ABI adapter data,
- verifier admissibility of relocation kinds.

Current `NativeCodeLayout.size` is code-only, and `install_native()` allocates/copies only text bytes. Once constant pools exist, layout, relocation validation, patch application, and executable size all depend on the same missing artifact facet.

---

### 10. Patch coordinate schema promises more than patch application implements

`NativePatchCoordinate` includes field offsets, strides, affine coefficients, window offsets, branch targets, call targets, scalar constants, etc. But patch writing currently supports only a subset of immediate/frame-size/frame-offset style writes.

So the schema currently advertises patchability for many coordinates that cannot be installed. This is risky because future Kernel/Stencil lowering may appear schema-valid while producing install-time unsupported holes.

---

### 11. Runtime symbol modeling is insufficient for calls/traps/externs

`NativeRuntimeSymbol` has `name` and `c_signature`, but no typed ABI projection and no runtime address/capability. `NativeRelocationRuntimeSymbol` currently always rejects during install.

The corrected architecture says runtime symbols are declared capabilities with typed signatures and supplied addresses. Current schema therefore cannot yet model extern calls, traps, allocator protocols, atomics fallback, or runtime helpers in the closed native path.

---

### 12. Object parser work is coupled to hole ordinals and extraction verification

Replacing `readelf` is not just a tooling cleanup. The internal object parser is the source of truth for:

- relocation kinds,
- extern hole symbols,
- continuation symbols,
- runtime symbols,
- constant-pool references,
- extraction-policy verification.

Current generator collapses object facts into `NativeCompiledTemplate` after parsing `readelf` text. There is no durable `LalinNativeObject` ASDL layer, so verifier ownership by `NativeTemplateExtraction` leaves cannot be expressed yet.

---

### 13. Marker holes are not merely temporary implementation detail; they shape current C source

The generated C uses magic immediates such as `0x11111111u` and marker scanning. That affects how source builders are written: they generate ordinary constants instead of declared extern-symbol references.

Moving to extern-symbol hole ordinals therefore changes the C source contract itself, not only the extractor. Existing source builders encode the bootstrap mechanism deeply.

---

### 14. Current source generation is not manifest-owned

`NativeTemplateSupportDomain:native_template_sources()` imperatively loops over scalar supports, and scalar leaves imperatively enumerate operations. This is leaf-method based in a narrow sense, but not the architecture’s generator/metavar model.

The non-obvious risk is that the loop structure becomes the de facto manifest. Then bank count depends on Lua enumeration structure rather than an ASDL value that can be compared against generated sources.

---

### 15. Family equality is incomplete relative to schema breadth

`native.lua` implements equality for only a subset of `NativeTemplateAxis`, `NativeCodeInstAxis`, `NativeCodeTermAxis`, and `NativeCodeConstAxis`. Many schema leaves default to false.

That means the schema already contains many native axes that cannot participate in bank selection. Kernel/Stencil axes in particular are present but effectively unusable for template selection unless equality coverage becomes exhaustive.

---

### 16. Code control lowering requires new frame/value ownership, not just more term methods

The architecture’s `CodeTermJump` / branch / switch lowering depends on explicit edge-copy chains and block-param slots. Current builder has a global placement list keyed by `CodeValueId`, with no block-entry node identity or predecessor-specific copy plan.

So branch support is not just “add branch template.” It requires the graph to represent value transfer across edges as first-class nodes/facts, otherwise block arguments become hidden side effects.

---

### 17. Kernel/Stencil schema axes currently risk becoming a native semantic mirror

`lua/lalin/schema/native.lua` names many Kernel/Stencil axes, but `native_kernel_methods.lua` is empty and `native_stencil_methods.lua` only delegates to an unimplemented descriptor method.

The corrected architecture says Kernel/Stencil semantic leaves own lowering shape. The current native schema already pre-names many axes without those owner methods, which risks freezing an artifact-side taxonomy before semantic ownership is proven.

---

### 18. Empty generated default bank conflicts with native-as-default public behavior

The generated `target/lalin_binary/lalin_native_template_bank.lua` is empty, while `lalin.compile()` defaults to native unless LuaJIT/bytecode options are chosen and native compile requires a supplied bank.

That creates a public contract gap: the corrected architecture removes fallback native paths, but the default user-facing behavior still needs a coherent “no bank / empty bank” story. Current stale tests assert an embedded MC bank with entries, which is architecturally wrong but exposes the same unresolved boundary.

---

### 19. Stale tests encode deleted semantics, not just old filenames

`tests/code_ir/test_lalin_binary.lua` expects:

- `lalin_embedded_mc_bank.c/.h`,
- registry key `lalin.embedded_mc_bank.count`,
- artifact field `residual == "mc"`,
- `mc_bank`,
- successful residual-style compiled vector loop.

Those are all deleted concepts in the corrected architecture. Keeping such tests around risks reintroducing compatibility shims under pressure to “make tests pass.”

---

### 20. Stale docs extend beyond the files listed by the scout

The scout noted stale `docs/CONVENTIONS.md`, `docs/ARCHITECTURE.md`, and `docs/LANGUAGE_REFERENCE.md`. Additional visible drift exists in root guidance/docs such as `AGENTS.md` and `README.md`, which still describe copy+residual, TCC glue, and MC fallback expectations.

This matters because future agents and contributors may treat those as binding unless the corrected architecture is made the dominant contract.

## Knowledge Gaps

- Exact `LalinCode` block/term ASDL shape may need closer inspection before judging all Code control ownership details.
- Exact `LalinKernel` / `LalinStencil` semantic leaf inventories should be checked before validating whether current native axes match real semantic owners.
- The generated-bank tool’s verifier behavior would need a focused read before distinguishing “missing parser” from “parser exists but not ASDL-owned.”

## Edit-planner Output — 2026-07-02 17:27:16

### Precondition Checks

- Confirm `docs/RESIDUAL_NATIVE_ARCHITECTURE.md` remains the binding architecture and still forbids residual/fallback/TCC/runtime tools/register-fragment baseline.
- Confirm `lua/lalin/schema/native.lua` has not been significantly refactored from the inspected layout:
  - `NativeTemplateSupportDomain` near line 193
  - `NativeTemplateSource` near line 302
  - `NativeRelocation` near line 337
  - `NativeTemplateNode` / `NativeControlEdge` near lines 805–841
  - `NativePatchBinding` near line 926
  - `NativeCallProtocol` near line 973
- Confirm existing native proof-slice tests still pass before edits, so regressions are attributable.
- Do not reuse obsolete `wf-914b9323` plans; structured sidecar `main` for `wf-native-cp-refactor` is now the source of truth.

### Files to Modify

#### `lua/lalin/schema/native.lua`

**Goal**: Make `LalinNative` capable of representing the corrected copy-patch artifact model.

**Edit blocks**
1. **Lines 4–20**: Add ids for stencil generators, metavars, configurations, manifest, hole ordinals, constant pools, and object parser facts.
2. **Lines 77–140**: Extend frame/value placement:
   - Add continuation-arg and constant-pool value locations.
   - Keep register/accumulator locations only as metadata/optimization.
3. **Lines 193–245**: Extend support-domain/build-state schema:
   - Add `K_int`, `K_float`, frame stack limit, public ABI adapters, continuation signatures, constant-pool support.
   - Replace current mutable builder-state pressure with typed planning facets/entries.
4. **Lines 290–310**: Extend extraction/source schema:
   - Add `NativeExtractPublicAbiAdapter`.
   - Add generator/configuration/signature/ordinal/relocation declarations to `NativeTemplateSource`.
5. **Lines 337–370**: Add `NativeRelocationHoleOrdinal` and `NativeRelocationConstantPool`.
6. **Lines 805–909**: Reconcile graph/copy schema:
   - Node-local instance identity.
   - Symbol-bearing branch/loop/exit/call-return edges.
   - Constant-pool layout in copy plans.
7. **Lines 920–981**: Add hole ordinal / patch formula / ABI projection / node-scoped patch binding schema.

**Danger zones**
- Do not model missing implementation as schema values.
- Do not make registers baseline source axes.

#### `lua/lalin/native_template_support.lua`

**Goal**: Provide constructors for the new manifest/support-domain vocabulary.

**Edit blocks**
1. **Lines 21–31**: Update comment to manifest/support-domain wording.
2. **Lines 343–639**: Add constructors for generators, signatures, metavars, hole ordinals, ABI projections, passthrough bounds, frame limits.
3. **Lines 691–739**: Update `support_domain(...)` defaults with spill-all `K_int=0`, `K_float=0`, frame stack limit, constant-pool support.

#### `lua/lalin/native.lua`

**Goal**: Update artifact equality, patch writing, and call protocol behavior.

**Edit blocks**
1. **Lines 45–292**: Add equality methods for new axes/configurations/signatures/ABI projections.
2. **Lines 292–360**: Add patch writes for pointer/rel32/call/branch/constant-pool/runtime-symbol coordinates.
3. **Lines 363–550**: Replace argument-count-inferred FFI calls with calls derived from `NativeAbiFunctionProjection`.

#### `lua/lalin/native_template_sources.lua`

**Goal**: Replace incidental scalar source loops with manifest-first C stencil generation.

**Edit blocks**
1. **Lines 12–24**: Remove marker constants as the target mechanism.
2. **Lines 47–107**: Add manifest construction and exact source/manifest validation.
3. **Lines 212–250**: Replace marker holes with extern-symbol hole ordinal helpers.
4. **Lines 337–579**: Rewrite entry/terminal/scalar builders to consume manifest entries and logical signatures.
5. **Lines 551–645**: Add builders for ABI adapters, edge copies, constant loads, control ops, call ops.
6. **Lines 646–666**: Make `native_template_sources()` compute manifest first and assert exact cardinality.

#### `lua/lalin/native_object.lua` *(new)*

- **Purpose**: Internal ELF object parser.
- **Contents sketch**:
  - Parse ELF64 little-endian x64 object bytes.
  - Produce `LalinNativeObject` ASDL values.
  - Model sections, symbols, relocations, raw bytes.
  - Reject unsupported/corrupt objects with `NativeTemplateBuildReject`.

#### `tools/gen_lalin_mc_bank.lua`

**Goal**: Use internal object parser/verifier and extern-symbol holes.

**Edit blocks**
1. **Lines 132–243**: Remove `readelf` text parsers as authority.
2. **Lines 386–456**: Replace marker scan hole resolution with relocation-hole ordinal recovery.
3. **Lines 458–553**: Compile C, parse object bytes, verify extraction leaf contract, emit typed compiled templates.
4. **Lines 620–870**: Serialize new relocation kinds, signatures, manifests, constant pools.

#### `lua/lalin/native_mc.lua`

**Goal**: Install copied graphs using node-scoped bindings, constants, typed relocations.

**Edit blocks**
1. **Lines 99–120**: Replace global duplicate binding detection with node-scoped lookup.
2. **Lines 185–210**: Lay out code + constant pool.
3. **Lines 217–249**: Patch continuation, hole ordinal, constant-pool, runtime-symbol relocations.
4. **Lines 263–345**: Validate/copy/patch using total executable layout.

#### `lua/lalin/native_code_methods.lua`

**Goal**: Replace proof-slice frame-only lowering with ABI/frame/value/control planning.

**Edit blocks**
1. **Lines 11–15**: Remove fixed param/result/frame constants.
2. **Lines 33–111**: Implement deterministic frame layout planner and continuation-arg spill policy.
3. **Lines 175–225**: Add `CodeType` / `CodeSig` ABI projection methods.
4. **Lines 272–351**: Update scalar/data inst lowering to select location-parametric configurations.
5. **Lines 119–389**: Replace linear `next` insertion with block-entry/control graph construction.
6. Add missing leaf methods for jumps, branches, switches, calls, traps, void/sret returns, memory, aggregates, descriptor ops, atomics.

#### `lua/lalin/native_kernel_methods.lua`

**Goal**: Add Kernel native leaf methods instead of empty binding.

**Edit blocks**
- Replace entire file with `KernelPlan`, `KernelBody`, `KernelDomain`, `KernelExpr`, `KernelEffect`, `KernelResult`, `KernelProof` leaf methods that compose frame/continuation graphs.

#### `lua/lalin/native_stencil_methods.lua`

**Goal**: Implement Stencil lowering under semantic-owner leaves.

**Edit blocks**
- Keep `StencilInstance:plan_native_copy`.
- Add `StencilDescriptor`, producer/access/point/body/sink/store/reduction/schedule leaf methods.
- Compose recursive graph nodes; do not create native semantic mirror or exact-cell enumeration.

#### `lua/lalin/native_backend.lua`, `lua/lalin/init.lua`

**Goal**: Preserve explicit native-bank/no-fallback public boundary.

**Edit blocks**
- `native_backend.lua` lines 42–55: require typed bank/manifest match, add import helpers.
- `init.lua` lines 647–735 and 823–889: update option errors and ensure runtime native never invokes tools or fallback.

#### `Makefile`, `src/lalin.c`

**Goal**: Keep generated native bank names and remove stale MC expectations.

**Edit blocks**
- `Makefile` lines 8–33: keep `lalin_native_template_bank.*`; wire manifest dependency if needed.
- `src/lalin.c` lines 7 and 28: do not restore `lalin_embedded_mc_bank`; expose no old registry shim.

#### Tests

- `tests/schema/test_schema_native.lua`: add new schema constructor smoke tests.
- `tests/code_ir/test_native_template_sources.lua`: manifest cardinality, extern holes, no marker constants.
- `tests/code_ir/test_native_bank_generator.lua`: internal parser and verifier rejects.
- `tests/code_ir/test_native_mc_import.lua`: repeated template/node-scoped bindings, constants, runtime symbols.
- `tests/code_ir/test_native_code_graph_scalar.lua`: ABI projection, deterministic frame layout, void/mixed params.
- `tests/code_ir/test_native_code_control.lua` *(new)*: jump/branch/switch/call/control graph tests.
- `tests/code_ir/test_native_kernel_stencil.lua` *(new)*: Kernel/Stencil graph shape tests.
- `tests/code_ir/test_lalin_binary.lua`: remove old MC residual bank assertions.

#### Docs

- `docs/CONVENTIONS.md` lines 139–161
- `docs/ARCHITECTURE.md` native/materialization sections
- `docs/LANGUAGE_REFERENCE.md` backend/options section
- `README.md` backend summary
- `AGENTS.md` stale backend paragraph

Remove residual/TCC/fallback/MC-bank compatibility wording; point to corrected native copy-patch architecture.

### Order of Operations

1. Schema first: `T001–T005`.
2. Constructors/core methods/source generation: `T006–T010`.
3. Object parser + generator verifier: `T011–T012`.
4. Runtime install/copy-plan: `T013`.
5. Code ABI/frame/value/control lowering: `T014–T017`.
6. Kernel/Stencil lowering: `T018–T019`.
7. Public API/build boundary: `T020–T023`.
8. Tests: `T024–T031`.
9. Docs/guidance: `T032–T035`, `T037`.
10. Final verification: `T036`.

### Testing Strategy

Run incrementally:
1. `luajit tests/schema/test_schema_native.lua`
2. `luajit tests/code_ir/test_native_template_sources.lua`
3. `luajit tests/code_ir/test_native_bank_generator.lua`
4. `luajit tests/code_ir/test_native_mc_import.lua`
5. `luajit tests/code_ir/test_native_code_graph_scalar.lua`
6. New control/kernel/stencil tests
7. `luajit tests/code_ir/test_lalin_binary.lua`
8. `luajit tests/run.lua schema`
9. `luajit tests/run.lua code_ir`

### Structured Edit Plan Sidecar

Updated `wf-native-cp-refactor` sidecar `main` to revision `r3`.

- Created `T001`–`T037`.
- 37 todo tasks.
- Ready tasks: schema/docs roots with no dependencies.
- Primary file paths and detailed instructions are recorded in the sidecar.

### Pattern Memo

- ASDL first; no side tables, maps, handler tables, string dispatch, or optional soup.
- Semantic lowering methods live on `LalinCode`, `LalinKernel`, `LalinStencil` leaves.
- `LalinNative` owns artifact/projection shape only.
- Runtime native compilation is copy/patch/install only.
- New holes use extern-symbol ordinals; marker scanning is not target architecture.
- Program size changes copied node count, never bank manifest cardinality.
- No residual, fallback, TCC, exact-cell bank, assembly stencil source, or register-fragment baseline.

## Worker Output — 2026-07-02 18:12:14

## Completed
Implemented T001 for the native C&P refactor and marked it done in edit plan `main`.

Added native schema vocabulary for:
- stencil generator/metavar/configuration/signature/manifest
- passthrough/frame stack/constant-pool support
- hole and continuation ordinals
- relocation-kind declarations
- `NativeExtractPublicAbiAdapter`
- enriched `NativeTemplateSource` fields

Verified:
- `luajit tests/schema/test_schema_native.lua`
- `luajit tests/run.lua schema` — 11 passed, 0 failed

## Files Changed
- `lua/lalin/schema/native.lua` - extended `LalinNative` schema with manifest/configuration/signature vocabulary and support-domain/source/extraction fields.
- `tests/schema/test_schema_native.lua` - updated schema smoke constructors and added manifest/source constructor coverage.

## Notes
Later source-generation tasks still need to update runtime constructors/helpers for the new required `NativeTemplateSource` and `NativeTemplateSupportDomain` fields.

## Worker Output — 2026-07-02 18:15:53

## Completed
Implemented claimed task T002 and marked it done in edit plan `main`.

Added ABI projection/runtime capability schema and updated smoke coverage.

## Files Changed
- `lua/lalin/schema/native.lua` - added ABI projection/value/function schema, runtime address capability, typed runtime symbols, and updated call protocols.
- `lua/lalin/native_template_support.lua` - updated CodeSig/StencilAbi call helpers to expect `NativeAbiFunctionProjection`.
- `tests/schema/test_schema_native.lua` - added minimal constructor smoke tests for new ABI/runtime schema.

## Notes
Verification passed:
- `luajit tests/schema/test_schema_native.lua`
- `luajit tests/run.lua schema` — 11 passed, 0 failed.

## Worker Output — 2026-07-02 18:19:57

## Completed
Implemented T003 and marked it done in edit plan `main`.

Added native schema support for:
- object file/section/symbol/relocation facts with x64 ELF relocation kinds
- extern-symbol hole ordinal patch formulas
- `NativeRelocationHoleOrdinal` and `NativeRelocationConstantPool`
- constant-pool entries/layout and patch coordinates
- extended compiled/embedded templates with extraction/signature/hole ordinals/relocation declarations/constant-pool layout
- typed build rejects for malformed/unsupported objects, hole ordinal issues, missing continuation relocations, extra unresolved symbols, and unsupported constant-pool relocations

Verified:
- `luajit tests/schema/test_schema_native.lua`
- `luajit tests/run.lua schema`
- `luajit tests/code_ir/test_native_mc_import.lua`

## Files Changed
- `lua/lalin/schema/native.lua` - added object, hole ordinal relocation, constant-pool, and build-reject schema.
- `lua/lalin/native_mc.lua` - imports new embedded template fields into compiled templates.
- `tools/gen_lalin_mc_bank.lua` - emits new embedded template fields.
- `tests/schema/test_schema_native.lua` - added smoke coverage for new schema constructors.
- `tests/code_ir/test_native_mc_import.lua` - updated embedded template constructors.

## Notes
No blockers.

## Worker Output — 2026-07-02 18:27:50

## Completed
Implemented T004 and marked it done in edit plan `main`.

Added/repaired:
- node-local template instance identity
- node/instance-scoped patch bindings
- typed patch binding target by hole id or hole ordinal
- continuation-symbol-bearing control edges
- typed graph planning facets:
  - `NativeValueLocationPlan`
  - `NativeFrameLayoutPlan`
  - `NativeControlPlan`
  - `NativeEdgeCopyPlan`
- copy-plan `constant_pool_layout` and `total_size`
- minimal runtime/test updates for scoped bindings and total executable sizing

Verification passed:
- `luajit tests/schema/test_schema_native.lua`
- `luajit tests/run.lua schema`
- `luajit tests/code_ir/test_native_mc_import.lua`
- native_code_methods load smoke

## Files Changed
- `lua/lalin/schema/native.lua` - schema repair for graph, patch identity, control edges, copy plan layout
- `lua/lalin/native_mc.lua` - node-scoped binding lookup/duplicate checks, control-edge continuation matching, total-size allocation, constant-pool copying
- `lua/lalin/native_code_methods.lua` - updated proof-slice construction for new planning facets/scoped bindings
- `tests/schema/test_schema_native.lua` - constructor/schema smoke coverage
- `tests/code_ir/test_native_mc_import.lua` - scoped binding and repeated-template coverage
- `tests/code_ir/test_native_c_continuation_branch.lua` - updated node constructors for instance identity

## Notes
Broader native source/code graph tests still fail in stale source/bank generation constructor paths noted by prior tasks; focused T004 validation passes.

## Worker Output — 2026-07-02 18:30:05

## Completed
Implemented T005 and marked it done.

Added schema smoke assertions for native ASDL constructors and removed the register-protocol baseline assumption.

Verified:
- `luajit tests/schema/test_schema_native.lua`
- `luajit tests/run.lua schema` — 11 passed, 0 failed

## Files Changed
- `tests/schema/test_schema_native.lua` - expanded native schema smoke coverage for manifest/metavar/ABI/extraction/relocation/constant-pool/patch/control-edge constructors.

## Notes
No blockers.

## Worker Output — 2026-07-02 18:35:53

## Completed
Implemented T006 support-domain/manifest helpers and marked it done in edit plan `main`.

Added constructors/helpers for:
- stencil generator/configuration/metavar/signature facts
- hole ordinals, extern hole symbols, continuation ordinals
- manifest entries/groups/source manifests
- passthrough bounds and spill-all defaults
- frame stack limits
- public ABI adapter support
- constant-pool support
- logical location tokens (`arg`, `slot`, `const`, `pool`, etc.)

Updated `support_domain(...)` defaults:
- `K_int=0`, `K_float=0`
- `NativeFrameStackLimit(256, 16)`
- explicit public adapter/signature lists
- empty constant-pool support
- baseline register protocol support set to `NativeRegisterProtocolNone`

Removed register-protocol axes from baseline family-axis helpers.

## Files Changed
- `lua/lalin/native_template_support.lua` - added support-domain/manifest vocabulary constructors and updated defaults/family axes.

## Notes
Verification:
- `luajit tests/schema/test_schema_native.lua` passed
- `luajit tests/run.lua schema` passed: 11/11
- Custom LuaJIT smoke for support-domain + generator/config/signature/manifest helpers passed

Attempted:
- `luajit tests/code_ir/test_native_template_sources.lua`

It still fails in the known later source-generation path because `native_template_sources.lua` still calls the old `NativeTemplateSource` constructor signature.

## Worker Output — 2026-07-02 19:06:39

## Completed
Implemented T007 and marked it done in edit plan `main`.

Added runtime native core support for:
- New schema equality helpers for ABI projections, call protocols, patch formulas, stencil configs/signatures, manifest entries, extraction identity, and native axes.
- Ptr64 / Rel32 / BranchRel32 / CallRel32 patch writer methods, including constant-pool and runtime-symbol coordinate hooks.
- ABI-projection-driven FFI calls via `NativeAbiFunctionProjection`.
- Legacy scalar/no-arg call protocols now delegate through explicit ABI projections.

Verified:
- `luajit tests/schema/test_schema_native.lua`
- `luajit tests/run.lua schema`
- `luajit tests/code_ir/test_native_mc_import.lua`
- Custom `NativeCallCodeSig` ABI smoke test

## Files Changed
- `lua/lalin/native.lua` - equality, patch writing, and ABI-based native call behavior.

## Notes
Attempted `luajit tests/code_ir/test_native_c_continuation_branch.lua`; it still fails on the known stale `NativeTemplateSource` constructor path in that test manifest, unrelated to T007.

## Worker Output — 2026-07-02 19:55:24

## Completed
- Implemented and marked done:
  - `T008` manifest-first native source requests
  - `T009` extern-symbol hole ordinal C stencils
- Claimed `T010`, but blocked it honestly due missing concrete ASDL/modeling decisions needed before implementation.

## Files Changed
- `lua/lalin/native_template_sources.lua` - manifest-backed source generation, extern-symbol hole stencils, no marker constants.
- `lua/lalin/schema/native.lua` - `NativeTemplateBankRequest` now carries a manifest.
- `tools/gen_lalin_mc_bank.lua` - empty requests include manifests; readelf path recognizes hole ordinal relocations.
- `tests/code_ir/test_native_bank_generator.lua` - updated direct source/request constructors.
- `tests/code_ir/test_native_c_continuation_branch.lua` - updated direct source/request constructors.

## Checks Run
- `luajit tests/schema/test_schema_native.lua`
- `luajit tests/run.lua schema`
- `luajit tests/code_ir/test_native_template_sources.lua`
- `luajit tests/code_ir/test_native_bank_generator.lua`
- `luajit tests/code_ir/test_native_c_continuation_branch.lua`
- `luajit tests/code_ir/test_native_code_graph_scalar.lua`

## Notes
Stopped as requested because `T010` is blocked in the edit plan. It would require new concrete ASDL/configuration decisions for ABI adapters, switch/call/control source manifests, and constant-pool value/relocation contracts before implementation can proceed without ad hoc dispatch or optional-soup builders.

## Worker Output — 2026-07-03 12:24:42

## Completed
Implemented and marked done in edit plan `main`:
- `T011` internal ELF object parser integration
- `T012` generator object-verifier path replacing readelf authority
- `T013` node-scoped install/copy-plan repairs
- `T014` Code ABI projection methods

Focused checks passed, including schema, native bank generator, template sources, MC import, continuation branch, and scalar graph tests.

## Files Changed
- `lua/lalin/native_object.lua` - ELF64 x64 object parser, relocations, SHT_REL/SHT_RELA handling
- `tools/gen_lalin_mc_bank.lua` - object-parser extraction/verifier path; no readelf/marker scan path
- `lua/lalin/schema/native.lua` - added object relocation kinds and richer `NativePatchApplyInput`
- `lua/lalin/native_mc.lua` - node-scoped bindings, constant-pool layout, relocation install support
- `lua/lalin/native_code_methods.lua` - CodeType/CodeSig/CodeCallTarget native ABI projection methods
- `tests/schema/test_schema_native.lua` - smoke coverage for added relocation kind
- `tests/code_ir/test_native_code_graph_scalar.lua` - ABI projection assertions

## Notes
Stopping after a substantial sequential batch as allowed. Next ready implementation tasks include `T015`, `T020`, `T022`, `T025`, and `T026`.

## Reviewer Output — 2026-07-03 12:37:14

## Files Reviewed
- `lua/lalin/native_object.lua` (lines 1-397)
- `tools/gen_lalin_mc_bank.lua` (lines 1-886)
- `lua/lalin/schema/native.lua` (lines 840-980, 1476-1592)
- `lua/lalin/native_mc.lua` (lines 1-592)
- `lua/lalin/native_code_methods.lua` (lines 1-636)
- `tests/schema/test_schema_native.lua` (lines 1-357)
- `tests/code_ir/test_native_code_graph_scalar.lua` (lines 70-98)

## Critical (must fix)
- `tools/gen_lalin_mc_bank.lua:316-318` / `lua/lalin/native_mc.lua:480-490` - Runtime-symbol relocations are accepted for any object relocation type, but install always applies them as 4-byte PC-relative rel32. An object with `R_X86_64_64` to a runtime symbol will be mis-modeled and patched incorrectly. Reopen **T012/T013** unless runtime relocations are schema-typed by formula/kind and verifier rejects unsupported forms.

- `lua/lalin/native_mc.lua:186-194` / `lua/lalin/native_mc.lua:199-207` - Duplicate binding detection compares only binding target keys, so the same physical hole can be bound twice in one node if one binding uses `NativePatchBindingHoleId` and another uses the corresponding `NativePatchBindingHoleOrdinal`. `binding_for_hole` then silently takes the first match. Reopen **T013**.

- `lua/lalin/native_mc.lua:357-371` / `lua/lalin/native_mc.lua:394-405` / `lua/lalin/native_mc.lua:557-560` - Constant-pool layout entries are treated as executable-global offsets for copying/relocation, but per-node patch input passes `base_address + node_offset` as the base along with those same offsets. Constant-pool patch coordinates for non-entry nodes will compute wrong addresses. Reopen **T013**.

- `tools/gen_lalin_mc_bank.lua:427-436` / `tools/gen_lalin_mc_bank.lua:254-339` - The generator converts typed `NativeObjectRelocation` ASDL values back into ad hoc Lua tables with string `reloc_type`, then dispatches on relocation-name strings. This violates the ASDL-doctrine goal of the internal object parser/verifier path; relocation-kind behavior should be owned by typed ASDL leaves or typed verifier facts. Reopen **T012**.

## Warnings (should fix)
- `tools/gen_lalin_mc_bank.lua:553-565` - Manifest/source validation only compares counts for hole ordinals, continuation ordinals, and relocation kinds. It does not compare actual identities/order/kinds, and `compile_source` does not enforce that observed relocation kinds are declared. This weakens closed-world manifest verification. Reopen **T012** or split follow-up verifier work.

- `lua/lalin/native_object.lua:130-187` - The parser verifies the object is ELF64/x64/little-endian but does not reject when `request.target` is non-x64/non-64-bit. It returns a `NativeObjectFile` tagged with whatever target was passed. The bank generator should reject target/object mismatches with typed rejects.

- `tests/code_ir/test_native_code_graph_scalar.lua:82-98` - ABI projection tests cover scalar result, sret result, call-target forwarding, and multi-result rejection, but not the zero-result/void `CodeSig` case. Add a direct zero-result assertion for T014 adequacy.

## Suggestions (consider)
- Add generator tests with `READELF=/bin/false`, malformed objects, missing/duplicate hole ordinals, undeclared relocation kinds, and runtime-symbol `R_X86_64_64` rejection. Current reviewed tests are mostly schema/ABI smoke and do not exercise the new verifier failure paths.
- Add install tests for mixed hole-id/hole-ordinal duplicate bindings and per-node constant-pool patch coordinates.

## Summary
The batch successfully removes readelf/marker-scan authority from the generator path and adds useful typed object/ABI vocabulary. However, the verifier/install path still has correctness and ASDL-doctrine gaps; **T012 and T013 should be reopened**. T014’s zero-or-one-result enforcement looks directionally correct, but its zero-result case needs test coverage.

## Worker Output — 2026-07-04 07:41:31

## Completed
Implemented and marked done:
- T015 deterministic native frame planner
- T020 native backend manifest/bank boundary
- T021 native public API no-fallback contract
- T022 native binary build manifest boundary
- T023 native C bank debug-only embedding metadata

Stopped after a substantial sequential batch.

## Files Changed
- `lua/lalin/native_code_methods.lua` - deterministic frame layout, reserved return slots, frame-limit enforcement.
- `lua/lalin/schema/native.lua` - bank/embedded bank now carry manifests.
- `lua/lalin/native_mc.lua` - imports embedded bank manifests.
- `lua/lalin/native_backend.lua` - typed bank/manifest validation and runtime-symbol helpers.
- `lua/lalin/init.lua` - removed/rejected stale native options; explicit runtime/bank path.
- `tools/gen_lalin_mc_bank.lua` - emits embedded banks with manifests.
- `tools/lalin_empty_native_bank_manifest.lua` - explicit empty default bank manifest.
- `Makefile` - native bank rule uses explicit manifest file.
- `src/lalin.c` - exposes raw native bank debug metadata only.
- `tests/schema/test_schema_native.lua` - updated constructor smoke.
- `tests/code_ir/test_native_mc_import.lua` - updated embedded bank constructors.
- `target/lalin_binary/lalin_native_template_bank.*` - regenerated empty manifest artifacts.

## Notes
Checks passed across focused native/schema/binary smoke tests. `tests/code_ir/test_lalin_binary.lua` still has known stale assertions and is covered by later T030. No tasks left claimed.

## Worker Output — 2026-07-04 07:51:31

## Completed
- Claimed and completed sequentially: `T032`, `T033`, `T034`, `T035`, `T037`.
- Synced stale backend docs/guidance to the residualless native C-stencil copy-patch architecture.
- Removed stale residual/MC/TCC/fallback wording from targeted docs, except current tool/file names where unavoidable.

## Files Changed
- `docs/CONVENTIONS.md` - updated backend doctrine.
- `docs/ARCHITECTURE.md` - rewrote native/backend sections and file-role tables.
- `docs/LANGUAGE_REFERENCE.md` - rewrote backend options/reference.
- `README.md` - updated backend summary/build notes.
- `AGENTS.md` - updated project agent backend guidance.

## Notes
- Focused `rg` checks were run for stale backend terms after each doc task.
- `docs/PVM_HARD_YANK_CHECKLIST.md` was requested as binding but is not present in the repo.

## Worker Output — 2026-07-04 08:01:01

## Completed
Implemented and marked done sequentially:
- `T025` — bank generator object-verification tests
- `T026` — native MC import/install tests
- `T030` — lalin binary smoke update
- `T031` — checked-in native bank artifact verification/regeneration

Stopped after a substantial sequential batch.

## Files Changed
- `tools/gen_lalin_mc_bank.lua` - retains typed `NativeRelocationHoleOrdinal`; rejects undeclared extern object symbols.
- `tests/code_ir/test_native_bank_generator.lua` - added extern-hole ordinal, readelf-free, and verifier reject coverage.
- `tests/code_ir/test_native_mc_import.lua` - added node-scoped binding, constant-pool relocation, runtime-symbol, and control-edge install tests.
- `tests/code_ir/test_lalin_binary.lua` - removed stale MC/residual assumptions; added native-template-bank and explicit LuaJIT/native-boundary smoke.
- `lua/lalin/init.lua` - clarified no-bank native compile error without fallback/residual wording.

## Notes
Checks passed:
- `luajit tests/code_ir/test_native_bank_generator.lua`
- `luajit tests/code_ir/test_native_mc_import.lua`
- `luajit tests/code_ir/test_lalin_binary.lua`
- `luajit tests/code_ir/test_native_template_sources.lua`
- `luajit tests/code_ir/test_native_c_continuation_branch.lua`
- `luajit tests/code_ir/test_native_code_graph_scalar.lua`
- `luajit tests/schema/test_schema_native.lua`
- Generated native bank Lua/C artifacts verified for empty manifest and stale-term absence.

Remaining ready tasks are implementation-heavy source-builder tasks: `T010B`, `T010C`, `T010D`.

## Worker Output — 2026-07-04 08:19:55

## Completed
Implemented and marked done sequentially:
- `T010B` frame entry, terminal, edge-copy/parallel-copy, constant-load source builders
- `T010C` control operation source builders
- `T010D` public ABI adapter and call source builders

Returned accidentally claimed out-of-scope `T016` to todo before continuing with source-builder tasks.

## Files Changed
- `lua/lalin/native_template_sources.lua` - added frame/control/copy/constant-load/public-ABI/call source generation.
- `tests/code_ir/test_native_template_sources.lua` - added source-builder assertions for control, ABI adapter, and call sources.
- `tests/code_ir/test_native_code_graph_scalar.lua` - updated CodeTerm source assertions to allow generated control stencils.

## Notes
Focused checks passed:
- `luajit tests/schema/test_schema_native.lua`
- `luajit tests/code_ir/test_native_template_sources.lua`
- `luajit tests/code_ir/test_native_bank_generator.lua`
- `luajit tests/code_ir/test_native_mc_import.lua`
- `luajit tests/code_ir/test_native_c_continuation_branch.lua`
- `luajit tests/code_ir/test_native_code_graph_scalar.lua`

No T010B/T010C/T010D tasks remain ready.

## Worker Output — 2026-07-04 08:25:23

## Completed
Partial progress on `T016`, then blocked honestly.

Implemented:
- Node/instance-scoped generated template bindings via `NativePatchBindingHoleOrdinal`.
- Real lowering for `CodeInstAlias`.
- Real lowering for `CodeInstUnary`.
- `CodeConstNull` coordinate lowering.

Blocked `T016` because the remaining requested Code ops lack closed source/manifest contracts and generated stencil families.

## Files Changed
- `lua/lalin/native_code_methods.lua` - ordinal bindings, alias/unary/null lowering.

## Notes
Checks passed:
- `luajit tests/schema/test_schema_native.lua`
- `luajit tests/code_ir/test_native_template_sources.lua`
- `luajit tests/code_ir/test_native_bank_generator.lua`
- `luajit tests/code_ir/test_native_mc_import.lua`
- `luajit tests/code_ir/test_native_c_continuation_branch.lua`
- `luajit tests/code_ir/test_native_code_graph_scalar.lua`
- Custom unary/alias ordinal smoke

Stopped because claimed task `T016` is genuinely blocked by missing closed architecture/source-builder contracts for cast/select/memory/aggregate/descriptor/variant/atomic/fence lowering.

## Worker Output — 2026-07-04 08:31:41

## Completed
- Completed `T024` test coverage for native template source manifests/extern holes.
- Blocked `T018` and `T019` honestly: kernel/stencil lowering cannot be implemented yet without closed source-manifest/C-stencil contracts.
- No ready tasks remain in edit plan `main`.

## Files Changed
- `tests/code_ir/test_native_template_sources.lua` - added manifest cardinality, exact manifest/source identity, spill-all K defaults, extern hole ordinal, continuation/relocation declaration, marker-hole absence, ABI/call, and embedded/imported manifest assertions.

## Notes
Checks passed:
- `luajit tests/schema/test_schema_native.lua`
- `luajit tests/code_ir/test_native_template_sources.lua`
- `luajit tests/code_ir/test_native_bank_generator.lua`
- `luajit tests/code_ir/test_native_mc_import.lua`
- `luajit tests/code_ir/test_native_c_continuation_branch.lua`
- `luajit tests/code_ir/test_native_code_graph_scalar.lua`

`T018`/`T019` need prior ASDL/source-generation work for real kernel/stencil template families before implementation can proceed without placeholders.

## Worker Output — 2026-07-04 08:47:16

## Completed
Partial progress on `T016S1`, then blocked honestly.

Implemented:
- `NativeChunkCastOp` source generation for object-safe casts:
  - integer/integer identity, bitcast, reduce, sign/zero extend
  - float promote/demote
  - slot/arg/immediate input locations and slot/arg outputs
- `NativeChunkSelectOp` source generation:
  - bool condition from slot/arg
  - true/false values from slot/arg/immediate
  - slot/arg outputs
- Manifest/source test coverage for cast/select chunks.

## Files Changed
- `lua/lalin/native_template_sources.lua` - added cast/select source builders and MachineCastOp C-source methods.
- `tests/code_ir/test_native_template_sources.lua` - updated manifest counts and added cast/select assertions.

## Notes
Blocked `T016S1` because full UB-safe int↔float cast stencils cause gcc to emit local `.rodata` relocations / duplicate hole relocations that the current object verifier rejects. Completing all MachineCastOp source families needs an explicit object/constant-pool relocation contract or different concrete C-stencil contract for float/int casts.

Checks passed after restricting emitted casts to object-safe families:
- `luajit tests/schema/test_schema_native.lua`
- `luajit tests/code_ir/test_native_bank_generator.lua`
- `luajit tests/code_ir/test_native_mc_import.lua`
- `luajit tests/code_ir/test_native_c_continuation_branch.lua`
- `luajit tests/code_ir/test_native_template_sources.lua`
- `luajit tests/code_ir/test_native_code_graph_scalar.lua`

## Worker Output — 2026-07-04 09:40:23

## Completed
- Completed `T016S1`, `T016S2`, and `T016S3`.
- Added full int↔float cast source coverage, address/memory/descriptor/aggregate/variant source builders, and atomic/fence source builders.
- Added typed `NativeAtomicCodegenCapability`.
- Partially implemented `T016R` scalar/data lowerers, then blocked it honestly.

## Files Changed
- `lua/lalin/native_template_sources.lua` - cast/select completion; address/memory/descriptor/aggregate/variant/atomic source builders.
- `lua/lalin/schema/native.lua` - added atomic codegen capability to support domains.
- `lua/lalin/native_template_support.lua` - default GCC atomic builtin support.
- `lua/lalin/native_code_methods.lua` - partial scalar/data lowering for cast/select/ptr_offset/load/store/atomics.
- `tests/schema/test_schema_native.lua` - schema smoke updated.
- `tests/code_ir/test_native_template_sources.lua` - manifest counts and source assertions updated.

## Notes
Blocked `T016R` and stopped as instructed.

Blocker: remaining lowering for GlobalRef/AddrOf composite places, descriptors, aggregates, arrays, and variants needs precise ASDL/frame-layout facts for non-scalar frame objects plus module global/data/function address capabilities. Current native value placement only models scalar frame slots, so completing that scope would require forbidden placeholder pointer/global-address shims or unsafe descriptor/aggregate slot overruns.

Focused checks passed:
- `luajit tests/schema/test_schema_native.lua`
- `luajit tests/code_ir/test_native_template_sources.lua`
- `luajit tests/code_ir/test_native_bank_generator.lua`
- `luajit tests/code_ir/test_native_mc_import.lua`
- `luajit tests/code_ir/test_native_c_continuation_branch.lua`
- `luajit tests/code_ir/test_native_code_graph_scalar.lua`

## Worker Output — 2026-07-04 10:14:27

## Completed
Partial progress on `T016V2`, then blocked honestly.

Implemented:
- `NativeStorageLayout`
- `NativeUntypedPointerValueRepresentation`
- aggregate representation `element_count`
- CodeType storage/representation methods for scalar, pointer, descriptor, array/vector, handle/lease cases
- deterministic frame allocation plumbing for explicit representations
- CodePlace address target/projection methods
- focused representation/address tests

## Files Changed
- `lua/lalin/schema/native.lua` - representation/storage/address schema refinements.
- `lua/lalin/native_code_methods.lua` - CodeType storage methods, frame allocation updates, CodePlace address methods.
- `tests/schema/test_schema_native.lua` - schema smoke coverage.
- `tests/code_ir/test_native_c_continuation_branch.lua` - updated frame slot constructors.
- `tests/code_ir/test_native_value_representation.lua` - new focused tests.

## Notes
Blocked `T016V2` because named/imported-C aggregate byte storage and variant storage need a precise ASDL layout projection/input for size/alignment/fields/cases. Faking layout facts would violate ASDL-first/no-placeholder rules.

Checks passed:
- `luajit tests/run.lua schema`
- `luajit tests/run.lua code_ir` — 45 passed, 1 skipped
- focused native tests listed in the edit-plan blocker evidence.

## Worker Output — 2026-07-04 10:54:20

## Completed
- Completed `T016L1`, `T016L2`, `T016V2R`, and `T016V3`.
- Added native type layout projection ASDL and layout-plan consumption/building.
- Added layout-backed named/imported-C/variant storage methods.
- Added module address plan propagation through graph/copy/install patching.
- Added install-time address patch support for data/global/function/extern address coordinates.

## Files Changed
- `lua/lalin/schema/native.lua` - added layout projection ASDL; carried address plans through graph/copy/patch inputs.
- `lua/lalin/native_code_methods.lua` - layout-plan builders/consumers; non-scalar storage/place projection methods.
- `lua/lalin/native_mc.lua` - copy/install path now carries module address plans to patching.
- `lua/lalin/native.lua` - address capability resolution and patch writes.
- `tests/schema/test_schema_native.lua` - constructor smoke coverage.
- `tests/code_ir/test_native_value_representation.lua` - named/imported-C/variant/place layout tests.
- `tests/code_ir/test_native_mc_import.lua` - data/global/function/extern address patch tests.
- `tests/code_ir/test_native_c_continuation_branch.lua` - updated graph constructor.

## Notes
Blocked `T016R2` and stopped as instructed.

Blocker: Code lowering still lacks a typed native lowering input carrying `CodeBackModuleFacts`/layout env-derived `NativeCodeTypeLayoutPlan` and constructed `NativeModuleAddressPlan` into `CodeFunc`/`CodeBlock` lowering. Also, `CodeData`/`CodeGlobal` storage needs precise ASDL modeling as constant-pool or writable data layout before lowerers can emit real addresses without shims.

Checks passed:
- `luajit tests/run.lua schema`
- `luajit tests/run.lua code_ir` — 45 passed, 1 skipped
- Focused native/schema tests listed in task evidence.

## Worker Output — 2026-07-04 11:44:06

## Completed
- Completed `T016I1`, `T016I2`, and `T016I3`.
- Partially implemented `T016R3`, then blocked it honestly.
- Did not claim Kernel/Stencil source-builder tasks.

## Files Changed
- `lua/lalin/schema/native.lua` - added typed native Code lowering input/module plans and CodeData/CodeGlobal storage/address plan schema.
- `lua/lalin/native_code_methods.lua` - builds typed Code module lowering inputs; projects CodeData/CodeGlobal/CodeExtern addresses; added partial `CodeInstGlobalRef` lowering.
- `tests/schema/test_schema_native.lua` - constructor smoke coverage for new schema.
- `tests/code_ir/test_native_value_representation.lua` - focused lowering-input/storage/address assertions.

## Notes
`T016R3` is blocked after partial GlobalRef progress.

Blocker: aggregate/array/variant source families currently use placeholder axes while `NativeCodeInstAxis` equality is strict. Completing real semantic lowerers would either require lying about axes or selecting non-existent families. Composite `AddrOf` also needs ASDL-owned local/composite frame address entries with allocated slots/offsets before safe lowering.

Checks passed:
- `luajit tests/run.lua schema`
- `luajit tests/run.lua code_ir` — 45 passed, 1 skipped
- Focused native tests (`schema_native`, `native_value_representation`, `native_code_graph_scalar`, `native_mc_import`, etc.)

## Worker Output — 2026-07-04 14:09:03

## Completed
- Completed `T016A1`, `T016A2`, `T016A3`, and `T016R4`.
- Returned accidental `T018S` claim to todo and added `T016R4` dependency to `T018S`/`T019S` to honor Code-first priority.
- Claimed `T017`, found a real ASDL/source-axis blocker, marked it blocked, and stopped.

## Files Changed
- `lua/lalin/schema/native.lua` - added layout-parametric Code axes and local/place address capabilities.
- `lua/lalin/native.lua` - equality/address capability support for new native schema.
- `lua/lalin/native_template_sources.lua` - source families now use layout-parametric aggregate/array/variant/address axes.
- `lua/lalin/native_code_methods.lua` - local/place address planning; AddrOf/GlobalRef/PtrOffset/Load/Store/descriptor/aggregate/array/variant lowerers.
- `tests/schema/test_schema_native.lua` - constructor/equality smoke coverage.
- `tests/code_ir/test_native_template_sources.lua` - assertions for repaired source axes.
- `tests/code_ir/test_native_value_representation.lua` - focused address-plan tests.

## Blocked
- `T017` blocked: current call source builders still use synthetic placeholder `NativeCodeInstCallAxis` identities, so real `CodeCallTarget`/`CodeSigId` lowering would select non-existent families unless it lies about axes. Needs ASDL/source-axis repair for generic call axes before honest control/call lowering.

## Checks
- `luajit tests/run.lua code_ir` — 45 passed, 1 skipped
- Focused native/schema tests passed
- Custom native array build/load/execute smoke passed.
