# Plan C — C Emission, Stencil, Backend, Exec, Pipeline + Compile

**Agent:** C
**Scope:** C emission phases, stencil methods (split by receiver), exec plan, pipeline.lua, compile.lua
**Lines:** ~12,500

---

## MANDATORY READING — READ THESE FILES COMPLETELY BEFORE WRITING A SINGLE LINE

1. `docs/FILE_ORGANIZATION.md` — the master architectural document. Defines schema_v2/ vs impl/, method shape, forbidden patterns.
2. `docs/ASDL_GUIDE.md` — the ASDL doctrine. Leaf methods ARE dispatch. No classof. No side tables.
3. `TARGET-SCHEMA.md` — the target architecture for schema_v2. You need to know what types exist.
4. `AUDIT-REPORT.md` — known defects and fixes applied to schema_v2.
5. `lua/lalin/schema_v2/lower.lua`, `schema_v2/c.lua`, `schema_v2/cemit.lua`, `schema_v2/stencil.lua`, `schema_v2/stencil_machine.lua`, `schema_v2/exec.lua`, `schema_v2/backend.lua`, `schema_v2/compiler.lua` — READ THE ACTUAL SCHEMA FILES. Know the type names.

**Do not skip this.** The previous attempt failed because agents didn't read the docs. Read them ALL.

---

## WHAT YOU ARE BUILDING

This is a **REWRITE, not a port.** You are NOT copy-pasting old files into impl/. You are writing NEW code that installs methods on schema_v2 ASDL types.

**The architecture:**
- `lua/lalin/schema_v2/lower.lua` defines `LalinLower` schema: types like `Lower.LowerModule`, `Lower.LowerFragment`, etc. These are Lua tables with metatables.
- `lua/lalin/impl/lower_emit_c.lua` requires schema_v2 types and installs methods: `function Lower.LowerModule:emit_c(code_module) ... end`
- When code calls `lower_module:emit_c(code_module)`, Lua's metatable dispatches to the correct leaf method.

**The method shape:**
```lua
-- impl/lower_emit_c/init.lua
local Lower = require("lalin.schema_v2.lower")
local C = require("lalin.schema_v2.c")
local Schedule = require("lalin.schema_v2.schedule")

function Schedule.ScheduleFormVector:emit_c(ctx)
  -- Emit vectorized C loop with SIMD intrinsics
  return C.CEmitFragment(...)
end

function Lower.LowerModule:emit_c(code_module)
  -- Walk lower plans, emit C for each fragment
  return C.CBackendUnit(...)
end
```

**The old code provides LOGIC, not STRUCTURE.** Read `lua/lalin/lower_to_c.lua` to understand what logic each function performs, then write that logic as a leaf method on the concrete ASDL type. Do NOT require the old file. Do NOT wrap it. Do NOT (T)-call it.

---

## FORBIDDEN — IF YOU DO ANY OF THESE, YOU FAIL

```lua
-- FAIL: requiring old implementation files
local old = require("lalin.lower_to_c")(T)  -- NO. NEVER.
local plan = require("lalin.stencil_artifact_plan")(T)  -- NO. Sort its methods by receiver.

-- FAIL: classof dispatch
if asdl.classof(ty) == Code.CodeTyInt then  -- NO. Write Code.CodeTyInt:method() instead.

-- FAIL: handler maps
local handlers = { VectorForm = f1, ScalarForm = f2 }  -- NO. Leaf methods.

-- FAIL: side tables / caches keyed by nodes
local cache = {}  -- NO. Use ASDL interned products or method parameters.

-- FAIL: trying to make the file 'runnable'
-- Do NOT add test code. Do NOT add wrappers. Do NOT try to require() and run it.
-- The file installs methods. That's it. pipeline.lua calls them later.

-- FAIL: compatibility shims or links to old code
-- Do NOT add wrappers that delegate to the old implementation.
-- This is a REWRITE. New code only.

-- FAIL: kind-string dispatch
if ty.kind == "CodeTyInt" then  -- NO. Leaf method on Code.CodeTyInt.
```

**The only verification:** `luajit -e "require('lalin.impl.lower_emit_c')"` must not error. That's it. Not 'works'. Not 'runs'. Just loads.

---

## HOW TO APPROACH EACH FILE

1. Read the old source file(s) listed for the impl file you're writing. Understand the LOGIC.
2. Read the schema_v2 file(s) for the types you're installing methods on. Know the TYPE NAMES.
3. Write `lua/lalin/impl/xxx.lua`. Start with `require("lalin.schema_v2.xxx")` statements.
4. For each function in the old file: identify the receiver type, write `function ReceiverType:method_name(params) ... end`
5. If the old code uses `classof` to branch on type X vs Y: write a separate method on each concrete leaf.
6. After writing the file: `luajit -e "require('lalin.impl.xxx')"`. If it errors, fix it. If it loads, commit.

### Critical: stencil_artifact_plan.lua split
This file installs methods on 7+ different schema modules. Sort every method by its RECEIVER TYPE:
- Methods on `Code.CodeTy` / `Code.CodeType` → `impl/lower_emit_c/`
- Methods on `Value.Reduction` leaves → `impl/stencil_reduction.lua`
- Methods on `Stencil.*` leaves → `impl/stencil_plan.lua`
- Methods on `Schedule.*` leaves → `impl/schedule_plan.lua` (shared with Agent B)
- Methods on `Kernel.*` leaves → `impl/kernel_plan.lua` (shared with Agent B)
- Methods on `Mem.*` leaves → `impl/code_mem.lua` (shared with Agent B)
- Methods on `Lower.*` leaves → `impl/lower_emit_c/`
   - Methods on `Lower.*` leaves → `impl/lower_emit_c.lua`

   If a method's receiver type belongs to an impl file that Agent B already created, coordinate: append your methods to that file. If you cannot coordinate (different worktrees), create the method in your own file and note it in the commit message.

8. **`pipeline.lua` and `compile.lua` are written LAST** — they wire everything together and cannot be written until all impl files exist.

---

## FILE INVENTORY

| # | Impl file | Lines (est.) | Old source files | Notes |
|---|-----------|-------------|------------------|-------|
| 1 | `impl/lower_emit_c.lua` | ~5100 | `lower_to_c.lua` + `code_to_c.lua` + `emit_c_materialize.lua` + `lower_kernel_rewrite.lua` + `emit_c_validate.lua` + Code methods from `stencil_artifact_plan.lua` | Largest single impl file; split into sub-folder if >2000 lines |
| 2 | `impl/cemit_emit.lua` | ~1450 | `emit_c_lower.lua` + `emit_c_helpers.lua` | CEmitMachine methods |
| 3 | `impl/stencil_plan.lua` | ~950 | Stencil methods from `stencil_artifact_plan.lua` + `stencil_methods.lua` | Methods on Stencil.* types |
| 4 | `impl/stencil_reduction.lua` | ~300 | Reduction display_name methods from `stencil_artifact_plan.lua` + `lower_kernel_rewrite.lua` | Methods on Value.Reduction |
| 5 | `impl/stencil_machine.lua` | ~800 | `stencil_methods.lua` (machine methods) | Methods on StencilMachine.* types |
| 6 | `impl/stencil_metastencil.lua` | ~780 | `stencil_metastencil.lua` | Methods on Stencil.StencilDescriptor etc. |
| 7 | `impl/stencil_c.lua` | ~1600 | `stencil_c.lua` | C-specific stencil emission |
| 8 | `impl/exec_plan.lua` | ~240 | `exec_plan.lua` | Execution plan methods |
| 9 | `pipeline.lua` | ~80 | `frontend_pipeline.lua` (composition) | Thin wiring, ~30-50 lines of actual logic |
| 10 | `compile.lua` | ~60 | `init.lua` (public API subset) | Public API entry point |

**Files NOT ported (kept as-is, infrastructure/runtime):**
- `emit_c_compile.lua` — GCC runner
- `emit_c_tcc.lua` — TCC runner
- `emit_c_coverage.lua` — coverage tracking utility
- `native_backend.lua`, `native.lua`, `native_*.lua` — deferred (experimental)
- `luajit_*.lua`, `residual_*.lua` — out of scope
- `triplet.lua` — architecture tuple database (data)
- `code_type.lua` — utility helpers (kept, called by impl methods)
- `type_size_align.lua` — utility helpers (kept)
- `func_abi_plan.lua`, `code_aggregate_abi.lua` — utility helpers
- `value_proxy.lua`, `quote.lua` — utility helpers
- All `phase_*.lua`, `link_*.lua`, `compiler_package.lua`, `compiler_machines.lua`, `compiler_model.lua`, `compiler_driver.lua` — framework (kept)
- `schema_context.lua`, `schema_projection.lua`, `schema_runtime.lua`, `schema_types.lua`, `schema_emit_types.lua`, `context_define_schema.lua`, `asdl.lua` — infrastructure (kept)
- `ast.lua`, `loader.lua`, `store.lua`, `exotype.lua` — infrastructure (kept)
- `cli.lua` — CLI entry point (kept)
- `source_anchor_index.lua`, `source_position_index.lua`, `source_text_apply.lua`, `source_analysis.lua` — utilities (kept)
- `project_asdl.lua`, `project_ready_facts.lua`, `project_report.lua` — project utilities (kept)
- `bind_machine_binding.lua`, `bind_residence_decide.lua`, `bind_residence_gather.lua` — binding utilities (kept)
- `backend_target_model.lua` — target model utility (kept)
- `init.lua` — public API facade (kept; `compile.lua` provides the new typed entry point)
- `frontend_pipeline.lua` — legacy, will be retired after pipeline.lua is complete

---

## 1. `impl/lower_emit_c.lua` — :emit_c() on LowerModule types

**Old files:** `lower_to_c.lua` (2437 lines), `code_to_c.lua` (1358 lines), `emit_c_materialize.lua` (259 lines), `lower_kernel_rewrite.lua` (285 lines), `emit_c_validate.lua` (470 lines), plus Code methods from `stencil_artifact_plan.lua`
**Pattern:** ✅ Clean leaf methods throughout.
**Source reference:** Read ALL five old files + `stencil_artifact_plan.lua` Code methods fully before starting.

**If this file exceeds ~2000 lines, split into sub-folder:**
```
impl/lower_emit_c/
  init.lua         -- require("./schedule_form"), require("./lower_strategy"), require("./code_to_c"), require("./validate")
  schedule_form.lua  -- ScheduleForm:emit_c() methods
  lower_strategy.lua -- LowerStrategy:emit_c() methods
  code_to_c.lua      -- CodeType, CodeConst, CodePlace, CodeInstOp:emit_c() methods
  materialize.lua    -- C value/place materialization helpers
  kernel_rewrite.lua -- Reduction:display_name(), StencilScan methods
  validate.lua       -- CBackendUnit validation methods
```

### What it does
Emits C code from the LowerModule. This is the heart of the C backend: converts lowered kernel plans, code instructions, types, and values into valid C source code.

### Method signatures

```lua
-- Entry point:
function Lower.LowerModule:emit_c(code_module) → C.CBackendUnit
  -- code_module: Code.CodeModule
  -- Emits C code for every function/kernel in the lower module
  -- Produces a complete CBackendUnit (source text, header, declarations)

-- On LalinSchedule.ScheduleForm leaves (from lower_to_c.lua):
function Schedule.ScheduleFormVector:emit_c(lower_ctx) → C.CEmitFragment
  -- Emits C code for a vector schedule: SIMD intrinsics, vectorized loop
function Schedule.ScheduleFormScalar:emit_c(lower_ctx) → C.CEmitFragment
  -- Emits C code for a scalar schedule: plain C loop
function Schedule.ScheduleFormFallback:emit_c(lower_ctx) → C.CEmitFragment
  -- Emits C code for a fallback schedule: serial loop

-- On LalinLower.LowerStrategy leaves (from lower_to_c.lua):
function Lower.LowerStrategyDirect:emit_c_strategy(lower_ctx) → C.CEmitFragment
  -- Direct lowering: straightforward C translation
function Lower.LowerStrategyVector:emit_c_strategy(lower_ctx) → C.CEmitFragment
  -- Vector lowering: uses vector types/intrinsics
function Lower.LowerStrategyFallback:emit_c_strategy(lower_ctx) → C.CEmitFragment
  -- Fallback lowering: serial C loop

-- On LalinLower.LowerEmitCandidate leaves (from lower_to_c.lua):
function Lower.LowerEmitCandidateStore:emit_c_candidate(lower_ctx) → C.CEmitFragment
function Lower.LowerEmitCandidateReduce:emit_c_candidate(lower_ctx) → C.CEmitFragment
function Lower.LowerEmitCandidateScan:emit_c_candidate(lower_ctx) → C.CEmitFragment
-- ... every LowerEmitCandidate leaf

-- On LalinLower.LowerFragment leaves:
function Lower.LowerFragment:emit_c_fragment(lower_ctx) → C.CEmitFragment
  -- Emits a complete lower fragment as C code

-- Loop types (from lower_to_c.lua):
-- LowerLoopFor:emit_c_loop_header() — emits the for-loop header
-- LowerLoopWhile:emit_c_loop_header()
-- LowerLoopRange:emit_c_loop_header()

-- Value types (from lower_to_c.lua):
-- LowerValueScalar:emit_c_value()
-- LowerValueVector:emit_c_value()
-- LowerValueAddress:emit_c_value()

-- On LalinCode.CodeType leaves (from code_to_c.lua):
function Code.CodeTypeScalar:code_to_c_type_name() → str
  -- Returns C type name: "int32_t", "float", "void*", etc.
function Code.CodeTypePtr:code_to_c_type_name() → str
function Code.CodeTypeArray:code_to_c_type_name() → str
function Code.CodeTypeStruct:code_to_c_type_name() → str
function Code.CodeTypeUnion:code_to_c_type_name() → str
function Code.CodeTypeFunc:code_to_c_type_name() → str
function Code.CodeTypeView:code_to_c_type_name() → str
function Code.CodeTypeSlice:code_to_c_type_name() → str
function Code.CodeTypeHandle:code_to_c_type_name() → str
function Code.CodeTypeByteSpan:code_to_c_type_name() → str
-- ... every CodeType leaf

function Code.CodeTypeScalar:code_to_c_type_declaration() → str
  -- Returns full C type declaration including typedef if needed
function Code.CodeTypeStruct:code_to_c_type_declaration() → str
  -- Returns "typedef struct { ... } name;"
-- ... every CodeType leaf

-- CodeType methods for variant payloads:
function Code.CodeType:code_to_c_variant_payload_union_id() → str
  -- Returns the union field id for this type in a variant
function Code.CodeType:code_to_c_without_lease() → Code.CodeType
  -- Strips lease wrapper, returns inner type
function Code.CodeType:code_to_c_view_elem_type() → Code.CodeType
  -- Returns element type for view types
function Code.CodeType:code_to_c_slice_elem_type() → Code.CodeType
  -- Returns element type for slice types

-- On LalinCode.CodeConst leaves (from code_to_c.lua):
function Code.CodeConstInt:code_to_c_literal() → str
  -- Returns C literal: "42", "-1", "0xFF"
function Code.CodeConstFloat:code_to_c_literal() → str
  -- Returns C literal: "3.14f", "2.718281828"
function Code.CodeConstBool:code_to_c_literal() → str
  -- Returns "true" or "false"
function Code.CodeConstNull:code_to_c_literal() → str
  -- Returns "NULL"
function Code.CodeConstString:code_to_c_literal() → str
  -- Returns C string literal: "\"hello\""
function Code.CodeConstEnum:code_to_c_literal() → str
function Code.CodeConstUndef:code_to_c_literal() → str
  -- Undefined const — terminal, may emit a sentinel
-- ... every CodeConst leaf

-- On LalinCode.CodePlace leaves (from code_to_c.lua):
function Code.CodePlaceLocal:code_to_c_place() → str
  -- Returns C variable name or expression for this place
function Code.CodePlaceGlobal:code_to_c_place() → str
function Code.CodePlaceParam:code_to_c_place() → str
function Code.CodePlaceField:code_to_c_place() → str
  -- Returns "base.field_name"
function Code.CodePlaceIndex:code_to_c_place() → str
  -- Returns "base[index]"
-- ... every CodePlace leaf

-- On LalinCode.CodeValueId (from code_to_c.lua):
function Code.CodeValueId:code_to_c_value(emit_ctx) → str
  -- Returns the C expression for this value (may look up in context)

-- On LalinCode.CodeInstOp leaves (from code_to_c.lua):
function Code.CodeInstOpBin:code_to_c_inst(emit_ctx) → str
  -- Emits binary operation: "a + b", "a * b", etc.
function Code.CodeInstOpUn:code_to_c_inst(emit_ctx) → str
  -- Emits unary operation: "-a", "!a", "~a"
function Code.CodeInstOpCall:code_to_c_inst(emit_ctx) → str
  -- Emits function call: "func(arg1, arg2)"
function Code.CodeInstOpLoad:code_to_c_inst(emit_ctx) → str
  -- Emits load: reads from pointer
function Code.CodeInstOpStore:code_to_c_inst(emit_ctx) → str
  -- Emits store: writes to pointer
function Code.CodeInstOpAlloca:code_to_c_inst(emit_ctx) → str
  -- Emits alloca: stack allocation
function Code.CodeInstOpCast:code_to_c_inst(emit_ctx) → str
  -- Emits cast: "(int32_t)value"
function Code.CodeInstOpGep:code_to_c_inst(emit_ctx) → str
  -- Emits GEP: pointer arithmetic
function Code.CodeInstOpPhi:code_to_c_inst(emit_ctx) → str
  -- Phi nodes become nothing in C (resolved by block placement)
function Code.CodeInstOpExtractValue:code_to_c_inst(emit_ctx) → str
function Code.CodeInstOpInsertValue:code_to_c_inst(emit_ctx) → str
function Code.CodeInstOpSelect:code_to_c_inst(emit_ctx) → str
  -- Select: "cond ? a : b"
-- ... every CodeInstOp leaf

-- On LalinCode.CodeGlobalRef leaves (from code_to_c.lua):
function Code.CodeGlobalRef:code_to_c_ref() → str
  -- Returns the C identifier for this global reference

-- On LalinCode.CodeTerm leaves (from code_to_c.lua):
function Code.CodeTermBranch:code_to_c_term(emit_ctx) → str
  -- Emits "goto label_N;"
function Code.CodeTermCondBranch:code_to_c_term(emit_ctx) → str
  -- Emits "if (cond) goto label_T; else goto label_F;"
function Code.CodeTermReturn:code_to_c_term(emit_ctx) → str
  -- Emits "return value;"
function Code.CodeTermSwitch:code_to_c_term(emit_ctx) → str
  -- Emits switch statement or goto chain
function Code.CodeTermUnreachable:code_to_c_term(emit_ctx) → str
  -- Emits "/* unreachable */" or assert

-- On LalinCode.CodeBlock:
function Code.CodeBlock:code_to_c_block(emit_ctx) → str
  -- Emits a complete basic block: label + instructions + terminator

-- On LalinCode.CodeFunc:
function Code.CodeFunc:code_to_c_func(emit_ctx) → str
  -- Emits a complete C function: signature + body
```

### Materialization helpers (from emit_c_materialize.lua)

```lua
-- These are functional helpers, installed as local functions at the bottom of the file
-- or as methods if they dispatch on types:

-- materialize_c_value(emit_ctx, val_id, ty) → str
--   Returns the C expression needed to produce a value of the given type

-- materialize_c_place(emit_ctx, place_id, ty) → str
--   Returns the C lvalue expression for the given place

-- materialize_c_value_to_place(emit_ctx, val_id, place_id, ty) → str
--   Emits the store: "*place = value;"
```

### Validation methods (from emit_c_validate.lua)

```lua
-- On LalinC.CBackendUnit:
function C.CBackendUnit:validate_c_unit() → C.CBackendValidationResult
  -- Validates the emitted CBackendUnit: syntax check, type consistency

-- Validation sub-checks:
function C.CBackendUnit:validate_c_syntax() → [many C.CBackendValidationIssue]
function C.CBackendUnit:validate_c_types() → [many C.CBackendValidationIssue]
function C.CBackendUnit:validate_c_completeness() → [many C.CBackendValidationIssue]
```

### C type methods from stencil_artifact_plan.lua (Code.* receivers)

These methods are currently in `stencil_artifact_plan.lua` but their receiver is `Code.CodeType` or `Code.CodeTy`. Sort them into this file:

```lua
-- On LalinCode.CodeType leaves:
function Code.CodeTypeScalar:stencil_artifact_type_name() → str
  -- Returns the type name used in stencil artifact C code
function Code.CodeTypeView:stencil_artifact_type_name() → str
function Code.CodeTypeSlice:stencil_artifact_type_name() → str
-- ... every CodeType leaf

function Code.CodeTypeScalar:stencil_artifact_c_type() → C.CTypeShape
  -- Returns the C type for stencil artifacts
-- ... every CodeType leaf

function Code.CodeType:stencil_artifact_is_code_scalar() → bool
  -- Is this a scalar code type?
function Code.CodeType:stencil_artifact_is_int() → bool
  -- Is this an integer code type?
function Code.CodeType:stencil_artifact_is_integer_like() → bool
function Code.CodeType:stencil_artifact_is_float() → bool
```

### Display name methods from lower_kernel_rewrite.lua + stencil_artifact_plan.lua

```lua
-- On LalinValue.Reduction leaves (MUST go in impl/stencil_reduction.lua — see §4):
function Value.ReductionSum:display_name() → str  -- "sum"
function Value.ReductionProd:display_name() → str  -- "prod"
function Value.ReductionMin:display_name() → str   -- "min"
function Value.ReductionMax:display_name() → str   -- "max"
function Value.ReductionAnd:display_name() → str   -- "and"
function Value.ReductionOr:display_name() → str    -- "or"
-- ... every Reduction leaf

-- On LalinStencil.StencilScan leaves:
function Stencil.StencilScanInclusive:scan_display_name() → str
function Stencil.StencilScanExclusive:scan_display_name() → str
```

---

## 2. `impl/cemit_emit.lua` — :emit_artifact() on CEmitMachine types

**Old files:** `emit_c_lower.lua` (1415 lines), `emit_c_helpers.lua` (3 lines)
**Pattern:** ✅ Clean leaf methods.
**Source reference:** Read `lua/lalin/emit_c_lower.lua` fully before starting.

### What it does
The `CEmitMachine` transforms CBackendUnits into final compilation artifacts (source files, header files). It manages the C emission machine state: generated helper functions, accumulated C type declarations, counter state.

### Method signatures

```lua
-- Entry point:
function Cemit.CEmitMachine:emit_module(code_module, lower_module) → Cemit.CEmitArtifact
  -- code_module: Code.CodeModule
  -- lower_module: Lower.LowerModule
  -- Consumes the CEmitMachine, produces a CEmitArtifact
  -- If machine state accumulates (helpers, counter), return updated machine:
  --   return updated_machine, artifact

-- On LalinCemit.CEmitMachine:
function Cemit.CEmitMachine:emit_source(code_module, lower_module) → str
  -- Emits the C source file content

function Cemit.CEmitMachine:emit_header(code_module) → str
  -- Emits the C header file content

function Cemit.CEmitMachine:emit_support_files() → [many Cemit.CEmitSupportFile]
  -- Emits any support files (helper .c files, inline assembly, etc.)

function Cemit.CEmitMachine:emit_combined(code_module, lower_module) → str
  -- Emits a single combined C file (source + header in one)

-- On LalinCore.Scalar leaves (C type mapping):
function Core.ScalarVoid:emit_c_scalar_type() → str    -- "void"
function Core.ScalarBool:emit_c_scalar_type() → str    -- "bool"
function Core.ScalarI8:emit_c_scalar_type() → str      -- "int8_t"
function Core.ScalarI16:emit_c_scalar_type() → str     -- "int16_t"
function Core.ScalarI32:emit_c_scalar_type() → str     -- "int32_t"
function Core.ScalarI64:emit_c_scalar_type() → str     -- "int64_t"
function Core.ScalarU8:emit_c_scalar_type() → str      -- "uint8_t"
function Core.ScalarU16:emit_c_scalar_type() → str     -- "uint16_t"
function Core.ScalarU32:emit_c_scalar_type() → str     -- "uint32_t"
function Core.ScalarU64:emit_c_scalar_type() → str     -- "uint64_t"
function Core.ScalarF32:emit_c_scalar_type() → str     -- "float"
function Core.ScalarF64:emit_c_scalar_type() → str     -- "double"
function Core.ScalarRawPtr:emit_c_scalar_type() → str   -- "void*"
function Core.ScalarIndex:emit_c_scalar_type() → str   -- "size_t"

-- On LalinCore.Literal leaves:
function Core.LiteralInt:emit_c_literal() → str        -- "42"
function Core.LiteralFloat:emit_c_literal() → str      -- "3.14"
function Core.LiteralBool:emit_c_literal() → str       -- "true"/"false"
function Core.LiteralString:emit_c_literal() → str     -- "\"hello\""
function Core.LiteralNull:emit_c_literal() → str       -- "NULL"

-- On LalinCore.CmpOp leaves:
function Core.CmpOpEq:emit_c_comparison() → str        -- "=="
function Core.CmpOpNe:emit_c_comparison() → str        -- "!="
function Core.CmpOpLt:emit_c_comparison() → str        -- "<"
function Core.CmpOpLe:emit_c_comparison() → str        -- "<="
function Core.CmpOpGt:emit_c_comparison() → str        -- ">"
function Core.CmpOpGe:emit_c_comparison() → str        -- ">="

-- On LalinExec.ExecFragmentBody leaves:
function Exec.ExecFragmentBodyStore:emit_c_exec_fragment(emit_ctx) → str
  -- Emits the execution fragment body as C code
function Exec.ExecFragmentBodyReduce:emit_c_exec_fragment(emit_ctx) → str
function Exec.ExecFragmentBodyScan:emit_c_exec_fragment(emit_ctx) → str
-- ... every ExecFragmentBody leaf

-- C type emission methods:
function Cemit.CEmitMachine:emit_c_type_declaration(ty) → str
  -- Emits a forward declaration for a C type

function Cemit.CEmitMachine:emit_c_struct_definition(ty) → str
  -- Emits a complete struct definition

function Cemit.CEmitMachine:emit_c_function_signature(func) → str
  -- Emits a C function signature (no body)

function Cemit.CEmitMachine:emit_c_function_definition(func, body) → str
  -- Emits a complete C function definition with body

function Cemit.CEmitMachine:emit_c_includes() → str
  -- Emits necessary #include directives

-- Counter management:
function Cemit.CEmitMachine:emit_c_next_counter() → number
  -- Returns and increments the internal counter (for unique names)
```

---

## 3. `impl/stencil_plan.lua` — Stencil plan methods

**Old files:** `stencil_methods.lua` (931 lines, stencil methods subset), `stencil_artifact_plan.lua` (Stencil.* methods subset)
**Pattern:** ✅ Clean leaf methods.
**Source reference:** Read `lua/lalin/stencil_methods.lua` and identify every method whose receiver is a `Stencil.*` type or a `Schedule.*`/`Kernel.*`/`Mem.*` type. Also scan `stencil_artifact_plan.lua` for Stencil.* receiver methods.

### What it does
Stencil access pattern analysis, stencil selection, producer/consumer matching, schedule selection for stencil operations.

### Method signatures

```lua
-- On LalinStencil.StencilProducer leaves:
function Stencil.StencilProducer:stencil_producer_analysis(code, mem) → Stencil.StencilProducerFacts
  -- Analyzes a stencil producer: access pattern, element type, bounds

-- On LalinStencil.StencilAccess leaves:
function Stencil.StencilAccessDirect:stencil_access_offset() → number | Stencil.StencilAccessOffset
  -- Returns the access offset (relative to current index)
function Stencil.StencilAccessWindow:stencil_access_offset() → number | Stencil.StencilAccessOffset

-- On LalinStencil.StencilDescriptor leaves:
function Stencil.StencilDescriptorStore:stencil_descriptor_validate(target) → Stencil.StencilValidationResult
function Stencil.StencilDescriptorReduce:stencil_descriptor_validate(target) → Stencil.StencilValidationResult
function Stencil.StencilDescriptorScatter:stencil_descriptor_validate(target) → Stencil.StencilValidationResult
-- ... every StencilDescriptor leaf

-- On LalinStencil.StencilSelected leaves:
function Stencil.StencilSelectedStore:stencil_selected_codegen(target, kernel) → Stencil.StencilCodegenPlan
function Stencil.StencilSelectedReduce:stencil_selected_codegen(target, kernel) → Stencil.StencilCodegenPlan

-- On LalinStencil.StencilSchedule leaves:
function Stencil.StencilSchedule:stencil_schedule_plan(code, mem) → Stencil.StencilSchedulePlan

-- On LalinStencil.StencilFusion leaves:
function Stencil.StencilFusionCandidate:stencil_fusion_feasibility(mem) → Stencil.StencilFusionResult

-- On LalinStencil.StencilRejectReason leaves:
function Stencil.StencilRejectUnsupported:stencil_reject_explain() → str
function Stencil.StencilRejectAmbiguous:stencil_reject_explain() → str
function Stencil.StencilRejectMissingProducer:stencil_reject_explain() → str
-- ... every StencilRejectReason leaf

-- On LalinStencil.StencilFusionRejectReason leaves:
function Stencil.StencilFusionRejectConflict:stencil_fusion_reject_explain() → str
function Stencil.StencilFusionRejectAlias:stencil_fusion_reject_explain() → str
-- ... every StencilFusionRejectReason leaf

-- On LalinStencil.StencilAxis leaves:
function Stencil.StencilAxisLoop:stencil_axis_vectorize(simd_width) → Stencil.StencilAxis
  -- Attempts to vectorize this axis for the given SIMD width
function Stencil.StencilAxisSeq:stencil_axis_vectorize(simd_width) → Stencil.StencilAxis
  -- Sequential axis cannot be vectorized

-- On LalinStencil.StencilVectorizationFact leaves:
function Stencil.StencilVectorizeWidth:stencil_vectorize_apply(width) → Stencil.StencilVectorization
function Stencil.StencilVectorizeUnroll:stencil_vectorize_apply(factor) → Stencil.StencilVectorization

-- On LalinStencil.StencilMismatchReason leaves:
function Stencil.StencilMismatchWidth:stencil_mismatch_explain() → str
function Stencil.StencilMismatchAlignment:stencil_mismatch_explain() → str
-- ... typed schedule mismatch reasons
```

### Methods from stencil_artifact_plan.lua with CodeValueId receiver

```lua
-- On LalinCode.CodeValueId:
-- These are methods that stencil_artifact_plan.lua installs on Code types.
-- Sort them here if the receiver is Code.CodeValueId:
function Code.CodeValueId:stencil_supported_type() → bool
  -- Checks if the type of this value is supported for stencil operations
```

---

## 4. `impl/stencil_reduction.lua` — Reduction display methods

**Old files:** `stencil_artifact_plan.lua` (Reduction methods), `lower_kernel_rewrite.lua` (display_name methods)
**Pattern:** ✅ Clean leaf methods.
**Source reference:** Scan `stencil_artifact_plan.lua` for every method on `Value.Reduction*` leaves; scan `lower_kernel_rewrite.lua` for display methods.

```lua
-- On LalinValue.Reduction leaves:
function Value.ReductionSum:display_name() → str    -- "sum"
function Value.ReductionProd:display_name() → str   -- "prod"
function Value.ReductionMin:display_name() → str    -- "min"
function Value.ReductionMax:display_name() → str    -- "max"
function Value.ReductionAnd:display_name() → str    -- "and"
function Value.ReductionOr:display_name() → str     -- "or"
function Value.ReductionXor:display_name() → str    -- "xor"
-- ... every Reduction leaf in the schema

function Value.ReductionSum:reduction_combine_op() → Core.BinaryOp
  -- Returns the binary op for this reduction: Add, Mul, etc.
function Value.ReductionProd:reduction_combine_op() → Core.BinaryOp
  -- Returns Mul
-- ... every Reduction leaf

function Value.ReductionSum:reduction_neutral_element() → Value.ValueExpr
  -- Returns the neutral element for this reduction
-- ... every Reduction leaf (already in code_value.lua from Agent B — verify no duplication)
```

---

## 5. `impl/stencil_machine.lua` — StencilMachine methods

**Old file:** `stencil_methods.lua` (931 lines, StencilMachine.* methods subset)
**Pattern:** ✅ Clean leaf methods.
**Source reference:** Read `lua/lalin/stencil_methods.lua` and identify every method whose receiver is a `StencilMachine.*` type.

### Method signatures

```lua
-- On LalinStencilMachine.StencilMachinePointInput leaves:
function StencilMachine.StencilMachinePointInputScalar:stencil_machine_point_codegen(gen_ctx) → StencilMachine.StencilMachinePointCode
function StencilMachine.StencilMachinePointInputVector:stencil_machine_point_codegen(gen_ctx) → StencilMachine.StencilMachinePointCode
-- ... every StencilMachinePointInput leaf (typed union from the boolean soup refactoring)

-- On LalinStencilMachine.StencilMachineKernelInput leaves:
function StencilMachine.StencilMachineKernelInputStore:stencil_machine_kernel_select() → StencilMachine.StencilMachineKernelSelection
function StencilMachine.StencilMachineKernelInputReduce:stencil_machine_kernel_select() → StencilMachine.StencilMachineKernelSelection
-- ... every StencilMachineKernelInput leaf

-- On LalinStencilMachine.StencilMachineFindSelectionFacts:
function StencilMachine.StencilMachineFindSelectionFacts:stencil_machine_find_codegen(gen_ctx) → StencilMachine.StencilMachineFindResult
  -- Uses FindNotFoundSentinel (from audit fix) for not_found sentinel

-- On LalinStencilMachine.FindNotFoundSentinel leaves (from audit fix):
function StencilMachine.FindNotFoundMinusOne:stencil_machine_sentinel_value() → number
  -- Returns -1
function StencilMachine.FindNotFoundSentinelConst:stencil_machine_sentinel_value() → number
  -- Returns the user-supplied sentinel

-- On LalinStencilMachine.StencilMachinePointExprFacts:
function StencilMachine.StencilMachinePointExprFacts:stencil_machine_point_expr_eval() → StencilMachine.StencilMachinePointEval

-- On LalinStencilMachine.StencilMachineStoreNDescriptor:
function StencilMachine.StencilMachineStoreNDescriptor:stencil_machine_store_codegen() → str

-- On LalinStencilMachine.StencilMachineReduceNDescriptor:
function StencilMachine.StencilMachineReduceNDescriptor:stencil_machine_reduce_codegen() → str

-- On LalinStencilMachine.StencilMachineScatterReduceNDescriptor:
function StencilMachine.StencilMachineScatterReduceNDescriptor:stencil_machine_scatter_reduce_codegen() → str

-- On LalinCode.CodeConst (stencil machine methods):
function Code.CodeConst:stencil_machine_const_value() → number | nil

-- On LalinValue.ValueExpr (stencil machine methods):
function Value.ValueExprConst:stencil_machine_const_eval() → number | nil
function Value.ValueExprBin:stencil_machine_const_eval() → number | nil
  -- Attempts to evaluate the expression to a constant
```

---

## 6. `impl/stencil_metastencil.lua` — Meta-stencil methods

**Old file:** `stencil_metastencil.lua` (743 lines)
**Pattern:** ✅ Leaf methods.
**Source reference:** Read `lua/lalin/stencil_metastencil.lua` fully before starting.

### Method signatures

```lua
-- On LalinStencil.StencilDescriptor leaves:
function Stencil.StencilDescriptorStore:metastencil_generate(target, config) → Stencil.StencilGenerated
  -- Generates stencil code from a store descriptor
function Stencil.StencilDescriptorReduce:metastencil_generate(target, config) → Stencil.StencilGenerated
  -- Generates stencil code from a reduce descriptor

-- On LalinStencil.StencilReduceScope leaves:
function Stencil.StencilReduceScopeKernel:metastencil_scope_bind(machine) → Stencil.StencilBoundScope
function Stencil.StencilReduceScopeFragment:metastencil_scope_bind(machine) → Stencil.StencilBoundScope

-- On LalinStencil.StencilGenerated leaves:
function Stencil.StencilGeneratedStore:metastencil_emit_c() → str
function Stencil.StencilGeneratedReduce:metastencil_emit_c() → str
-- ... every StencilGenerated leaf

-- Stencil descriptor iteration:
function Stencil.StencilDescriptorStore:metastencil_iterate_axes() → [many Stencil.StencilAxis]
function Stencil.StencilDescriptorReduce:metastencil_iterate_axes() → [many Stencil.StencilAxis]
```

---

## 7. `impl/stencil_c.lua` — C-specific stencil emission

**Old file:** `stencil_c.lua` (1554 lines)
**Pattern:** Method installations + functional helpers.
**Source reference:** Read `lua/lalin/stencil_c.lua` fully before starting.

### Method signatures

```lua
-- C-specific stencil emission methods. These are the C backend's stencil
-- code generation: translating stencil selections into C loops, SIMD intrinsics,
-- and memory access patterns.

-- On LalinStencil.StencilSelected leaves:
function Stencil.StencilSelectedStore:stencil_c_emit(emit_ctx) → str
  -- Emits C code for a selected store stencil
function Stencil.StencilSelectedReduce:stencil_c_emit(emit_ctx) → str
  -- Emits C code for a selected reduce stencil

-- On LalinStencil.StencilSchedulePlan:
function Stencil.StencilSchedulePlan:stencil_c_schedule_emit(emit_ctx) → str
  -- Emits the C code for the stencil schedule (loop nest + body)

-- On LalinStencil.StencilAxis leaves:
function Stencil.StencilAxisLoop:stencil_c_emit_loop(emit_ctx, body) → str
  -- Emits a for loop: "for (int i = 0; i < N; i++) { ... }"
function Stencil.StencilAxisSeq:stencil_c_emit_loop(emit_ctx, body) → str
  -- Sequential: no loop, just body

-- On LalinStencil.StencilVectorization leaves:
function Stencil.StencilVectorizationVector:stencil_c_emit_load(ptr_expr) → str
  -- Emits SIMD load intrinsic: _mm256_loadu_si256(...)
function Stencil.StencilVectorizationScalar:stencil_c_emit_load(ptr_expr) → str
  -- Scalar load: "*(ptr)"
function Stencil.StencilVectorizationVector:stencil_c_emit_store(ptr_expr, val) → str
  -- Emits SIMD store intrinsic
function Stencil.StencilVectorizationVector:stencil_c_emit_binary(op, lhs, rhs) → str
  -- Emits SIMD binary op: _mm256_add_epi32(lhs, rhs)
function Stencil.StencilVectorizationScalar:stencil_c_emit_binary(op, lhs, rhs) → str
  -- Scalar binary: "lhs + rhs"

-- On LalinStencil.StencilAccess patterns:
function Stencil.StencilAccessDirect:stencil_c_access(base_ptr, index) → str
  -- Direct access: base_ptr[index]
function Stencil.StencilAccessWindow:stencil_c_access(base_ptr, index) → str
  -- Window access with offset: base_ptr[index + offset]

-- C data layout helpers:
-- stencil_c_data_ptr(base, offset, elem_size) → str
-- stencil_c_vector_type(scalar, width) → str  -- "__m256i", "__m128", etc.
-- stencil_c_vector_intrinsic(op, scalar, width) → str
```

---

## 8. `impl/exec_plan.lua` — Execution plan methods

**Old file:** `exec_plan.lua` (224 lines)
**Pattern:** ✅ Clean leaf methods.
**Source reference:** Read `lua/lalin/exec_plan.lua` fully before starting.

### Method signatures

```lua
-- On LalinKernel.KernelPlanned:
function Kernel.KernelPlanned:exec_plan_build(code, lower) → Exec.ExecPlan
  -- Builds an execution plan from a planned kernel
  -- Resolves the execution fragment tree

-- On LalinStencil.StencilSelected leaves:
function Stencil.StencilSelectedStore:exec_stencil_selection(lower) → Exec.ExecStencilSelection
function Stencil.StencilSelectedReduce:exec_stencil_selection(lower) → Exec.ExecStencilSelection

-- On LalinExec.ExecStencilSelection leaves:
function Exec.ExecStencilSelectionStore:exec_emit_fragment() → Exec.ExecFragment
function Exec.ExecStencilSelectionReduce:exec_emit_fragment() → Exec.ExecFragment

-- On LalinExec.ExecFragment leaves:
function Exec.ExecFragment:exec_fragment_emit() → Exec.ExecFragmentBody

-- On LalinExec.ExecStencilDecision leaves:
function Exec.ExecStencilDecision:exec_fragment_trap_reason() → str
  -- Terminal diagnostic — keep reason [str]
```

---

## 9. `pipeline.lua` — Thin composition

**Created after ALL impl files exist.**
**Reference:** `docs/FILE_ORGANIZATION.md` §4
**Lines:** ~80 (including requires, ~30 lines of actual composition)

### What it does
Wires the phase methods into the full compilation sequence. It requires all impl files (to ensure methods are installed) and chains the phase methods. No semantics live here — only method calls.

```lua
-- pipeline.lua
-- Thin composition: chains phase methods. No compiler semantics.

-- Ensure all methods are installed:
require("lalin.impl.tree_surface")
require("lalin.impl.tree_closure")
require("lalin.impl.tree_check")         -- init.lua loads all sub-files
require("lalin.impl.tree_code")
require("lalin.impl.code_graph")
require("lalin.impl.code_flow")
require("lalin.impl.code_value")
require("lalin.impl.code_mem")
require("lalin.impl.code_effect")
require("lalin.impl.kernel_plan")
require("lalin.impl.schedule_plan")
require("lalin.impl.lower_plan")
require("lalin.impl.lower_emit_c")
require("lalin.impl.cemit_emit")
require("lalin.impl.code_validate")
require("lalin.impl.compiler_result")
require("lalin.impl.stencil_plan")
require("lalin.impl.stencil_reduction")
require("lalin.impl.stencil_machine")
require("lalin.impl.stencil_metastencil")
require("lalin.impl.stencil_c")
require("lalin.impl.exec_plan")

-- Schema types used in composition:
local Tree = require("lalin.schema_v2.tree")
local Check = require("lalin.schema_v2.check")
local Code = require("lalin.schema_v2.code")
local Graph = require("lalin.schema_v2.graph")
local Flow = require("lalin.schema_v2.flow")
local Value = require("lalin.schema_v2.value")
local Mem = require("lalin.schema_v2.mem")
local Effect = require("lalin.schema_v2.effect")
local Kernel = require("lalin.schema_v2.kernel")
local Schedule = require("lalin.schema_v2.schedule")
local Lower = require("lalin.schema_v2.lower")
local C = require("lalin.schema_v2.c")
local Cemit = require("lalin.schema_v2.cemit")
local Compiler = require("lalin.schema_v2.compiler")
local Backend = require("lalin.schema_v2.backend")
local Exec = require("lalin.schema_v2.exec")
local Stencil = require("lalin.schema_v2.stencil")

local function compile_pipeline(declarations, opts)
  -- Phase 1: Surface resolve
  local m = declarations.module:surface_resolve()

  -- Phase 2: Closure convert
  m = m:closure_convert()

  -- Phase 3: Typecheck
  local type_input = build_typecheck_input(m, opts)
  local checked = m:typecheck(type_input)

  -- Phase 4: Lower to code
  local lower_input = build_lower_input(checked, opts)
  local code_result = checked:lower_to_code(lower_input)

  -- Phase 5: Build graph
  local code_module = code_result.module
  local contracts   = code_result.contracts
  local graph       = code_module:build_graph()

  -- Phase 6: Compute facts
  local flow    = graph:compute_flow(code_module)
  local values  = graph:compute_values(code_module, flow)
  local mem     = graph:compute_mem(code_module, flow, values, contracts)
  local effects = graph:compute_effects(code_module, mem, contracts)

  -- Phase 7: Plan kernels
  local kernels = mem:plan_kernels(flow, values, mem, effects)

  -- Phase 8: Plan schedules
  local schedules = kernels:plan_schedules(code_module, flow, values, mem, effects, opts.target)

  -- Phase 9: Plan lowering
  local lower_plan = code_module:plan_lowering(graph, kernels, schedules, opts.target)

  -- Phase 10: Emit C
  local c_unit = lower_plan:emit_c(code_module)

  -- Phase 11: Emit artifact
  local ce_machine = Cemit.CEmitMachine(...)  -- construct from lower plan spine
  local artifact = ce_machine:emit_module(code_module, lower_plan)

  return artifact
end

-- Helper: build typecheck input from module and options
local function build_typecheck_input(m, opts)
  local scope = m:typecheck_module_scope()  -- method on ModuleHeader
  return Check.TypeModuleInput(scope)
end

-- Helper: build lower input from typechecked module
local function build_lower_input(checked, opts)
  -- Extract facts from typecheck result
  return ...
end

return { compile_pipeline = compile_pipeline }
```

The pipeline is ~30 lines of actual composition logic plus ~40 lines of requires and helpers. It does NOT own state. It does NOT handle errors (each method returns typed results with diagnostics). It calls methods.

---

## 10. `compile.lua` — Public API entry point

**Created after pipeline.lua.**
**Reference:** `docs/FILE_ORGANIZATION.md` §5
**Lines:** ~60

### What it does
The public API boundary. Users call `lalin.compile(source, opts)` or `lalin.compile_c_gcc(name, decls, opts)`. This file creates initial ASDL values from untyped inputs and calls the pipeline.

```lua
-- compile.lua
local pipeline = require("lalin.pipeline")
local lalin_loader = require("lalin.loader")     -- kept as-is

local function compile(source_text, opts)
  opts = opts or {}
  local filename = opts.filename or "@input.lln"

  -- Parse source text into declarations (uses existing loader)
  local decls = lalin_loader.loadstring(source_text, filename)
  -- decls is an ASDL Declarations value

  -- Run pipeline
  local artifact = pipeline.compile_pipeline(decls, opts)
  return artifact
end

local function compile_file(filepath, opts)
  opts = opts or {}
  local decls = lalin_loader.loadfile(filepath)
  return pipeline.compile_pipeline(decls, opts)
end

local function compile_c_gcc(name, decls, opts)
  opts = opts or {}
  -- First produce the C artifact
  local artifact = compile_pipeline(decls, opts)

  -- Then compile with GCC
  local gcc_opts = opts.gcc_opts or { opt = 3, out_dir = "target/" .. name }
  return artifact:compile_with_gcc(name, gcc_opts)
  -- compile_with_gcc is a method on CEmitArtifact that calls into emit_c_compile.lua
end

return {
  compile = compile,
  compile_file = compile_file,
  compile_c_gcc = compile_c_gcc,
}
```

---

## 11. STRADDLE METHODS — COORDINATION WITH AGENT B

The following methods are in `stencil_artifact_plan.lua` but their receiver types belong to impl files assigned to Agent B:

| Method | Receiver | Agent B's file |
|--------|----------|---------------|
| `stencil_artifact_type_name()` | `Code.CodeType` | `impl/lower_emit_c.lua` (yours — C emission) |
| `stencil_artifact_c_type()` | `Code.CodeType` | `impl/lower_emit_c.lua` (yours) |
| `stencil_artifact_is_code_scalar()` | `Code.CodeType` | `impl/lower_emit_c.lua` (yours) |
| `stencil_artifact_is_int()` | `Code.CodeType` | `impl/lower_emit_c.lua` (yours) |
| `stencil_artifact_is_integer_like()` | `Code.CodeType` | `impl/lower_emit_c.lua` (yours) |
| `stencil_artifact_is_float()` | `Code.CodeType` | `impl/lower_emit_c.lua` (yours) |
| `stencil_supported_type()` | `Code.CodeValueId` | `impl/stencil_plan.lua` (yours) |

Since Agent B works in a different worktree, you must install these methods yourself. They belong in your `impl/lower_emit_c.lua` and `impl/stencil_plan.lua`. Coordinate with Agent B to avoid duplication. The simplest approach: you own all Code.CodeType methods that deal with stencil artifacts and C emission.

Similarly, if `stencil_artifact_plan.lua` has methods on `Kernel.*`, `Schedule.*`, or `Mem.*` types that Agent B also handles, install them yourself in your files. Agent B has their own `impl/kernel_plan.lua`, `impl/schedule_plan.lua`, `impl/code_mem.lua` — check if they've already installed those methods. If not, you install them. If yes, skip.

**Resolution:** After both agents commit, the coordinator (me) will check for duplicate method installations and deduplicate during merge.

---

## 12. COMMIT ORDER

1. `impl/stencil_reduction.lua` — small, isolated, no dependencies
2. `impl/stencil_machine.lua` — machine methods
3. `impl/stencil_plan.lua` — stencil plan methods
4. `impl/stencil_metastencil.lua` — metastencil generation
5. `impl/stencil_c.lua` — C-specific stencil emission
6. `impl/exec_plan.lua` — execution plan
7. `impl/lower_emit_c.lua` — C emission (largest, depends on stencil methods for CodeType methods from stencil_artifact_plan)
8. `impl/cemit_emit.lua` — C machine emission (depends on lower_emit_c for CBackendUnit)
9. `pipeline.lua` — composition (depends on ALL impl files existing)
10. `compile.lua` — public API (depends on pipeline.lua)
