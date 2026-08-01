# Lalin Architecture

Lalin is a LuaJIT-hosted dialect of the LLBL language.

LLBL is the central engineering artifact: the extensible language workbench and the
bootstrap language used to define member dialects. It gives Lua values dialect
meaning through heads, roles, fragments, namespaces, origins, diagnostics,
formatting, indexing, regions, protocols, processes, and language composition.
Lalin is the compiled dialect in that language. It consumes LLBL regions and typed
values, checks native semantics, lowers the resulting program into `CBackendUnit`,
and emits C through `emit_c`. The main JIT-like execution path cooks that emitted
C with GCC and loads the resulting shared object for LuaJIT FFI function pointers.
The same emitted C is also the AOT artifact path. Native copy-patch/binary-bank
patchers are retired and must not be reopened; only the stencil/CMat vocabulary
survives as the deterministic emitted-C shape contract (`schema_v2/stencil.lua`
-> CMat fragment path -> `emit_c`). Fused emitted C + GCC -O3 is the performance
path; fusion eligibility is a typed decision over the exact emitted shape plus
declared memory/noalias/bounds facts, with contracts recomputed after fusion.

The main path is intentionally small:

## Current Compiler Architecture

The compiler is split into four ownership layers:

- `lalin.asdl` is the minimal runtime for schema contexts, class lookup,
  immutable structural updates, required-method checks, and triplet helpers. It is
  not a phase/cache runtime and does not expose `phase`.
- ASDL classes own typed semantic behavior through ordinary Lua methods assigned
  directly to schema class tables. Missing required methods are compiler bugs
  reported with the source class and operation name.
- A semantic method is not a selector. It must implement the operation for that
  concrete class and return the operation's real result. Methods that only
  return `kind`, handler keys, relation names, or other dispatch tokens preserve
  the old rule-table architecture and are not allowed.
- Semantic methods do not take a generic `ctx` bag by convention. They take only
  the typed, well-named semantic products they actually need, and take no extra
  argument when none is needed. State changes are represented by returned typed
  products, not by mutating a catch-all context.
- Compiler drivers and compiler-process modules sequence stages, allocate
  context, collect diagnostics, and pass typed products between stages. They do
  not own per-class semantics.
- Backends operate on explicit ASDL facts, plans, and IR. Backend artifact
  selection is represented in typed plans/results, not hidden alternate control
  flow.

Semantic methods are plain Lua methods on schema-generated classes:

```lua
local T = require("lalin.asdl").context()
require("lalin.schema")(T)

function T.LalinTree.ExprBinary:typecheck_tree_expr(type_env)
  -- node-specific semantics live here
end

return node:typecheck_tree_expr(type_env)
```

## Two authoring paths

Lalin has two surfaces that converge on the same ASDL:

| Path | How | When |
|------|-----|------|
| **`.lln` declaration documents** (primary) | Root `fn`/`struct`/`region` declarations loaded by `lalin.loader` or Lua `require` | Hand-written code |
| **Builder API** (Lua/LLBL) | `lln.fn. name { ... }` Lua DSL heads | Macros, generators, tooling |

```text
┌─ Hand-written source ─────────────────┐
│                                        │
│  fn add(a [i32], b [i32]) [i32] do    │
│    return a + b                        │
│  end                                   │
│                                        │
│  → lalin.loadfile / Lua require        │
│    → lalin.loader parses document      │
│      → lalin.syntax.document           │
│        → root Lalin.decls stream       │
│          → parsed AST declarations     │
│            → lalin.syntax.to_module()  │
└────────────────────────────────────────┘
                    │
                    ▼
┌─ Builder / Macro ─────────────────────┐
│                                        │
│  lln.fn. add { a [lln.i32], ... }     │
│    lln.ret (a + b),                    │
│                                        │
│  → Lua evaluates table literals        │
│    → LLBL staged heads capture values  │
│      → Decl values with Decl:syntax()  │
│        → LalinTree.Module             │
└────────────────────────────────────────┘
                    │
                    ▼

Both paths produce the same LalinTree.Module and share the pipeline below.

---

## Shared Compiler Pipeline

The compiler is organized around semantic products, not chronological steps.

```
LalinTree.Module
  │
  ▼
┌─────────────────────────────────────────┐
│ Frontend Pipeline                       │
│  Pipeline.typecheck_module()            │
│    ├─ SurfaceResolve                    │
│    ├─ ClosureConvert                    │
│    └─ Typecheck.check_module            │
│  → LalinTree.TypeModuleResult           │
└─────────────────────────────────────────┘
  │
  ▼
┌─────────────────────────────────────────┐
│ 3. Tree → Code IR                       │
│    Pipeline.checked_to_code_result()    │
│      ├─ LayoutResolve                   │
│      ├─ tree_lower (LalinTree→LalinCode)│
│      └─ CodeValidate                    │
│    → CodeResult(code_module, contracts) │
└─────────────────────────────────────────┘
  │
  ▼
┌─────────────────────────────────────────┐
│ 4. Fact Analysis (code_*.lua)           │
│    Backend.lower_module()               │
│      ├─ CodeGraph (CFG builder)          │
│      ├─ FlowFacts (loops, domains)       │
│      ├─ ValueFacts (algebra, ranges)     │
│      ├─ MemFacts (objects, aliasing)     │
│      ├─ EffectFacts (side effects)       │
│      ├─ KernelPlan (parallelizable kernels)│
│      ├─ SchedulePlan (exec policy)       │
│      └─ LowerPlan (strategy per fragment)│
│    → KernelModulePlan + SchedulePlan     │
└─────────────────────────────────────────┘
  │
  ▼
┌─────────────────────────────────────────┐
│ 5. SOAC / CMat Planning                 │
│    StencilComputation                   │
│      producer + accesses + streams      │
│      + algebraic sinks + legality       │
│    → CMatFusedKernel                    │
└─────────────────────────────────────────┘
  │
  ▼
┌─────────────────────────────────────────┐
│ 6. C Backend Lowering                   │
│    LowerToC.module()                    │
│    StencilStreamOp/StencilSinkOp leaves │
│    → CBackendUnit + C validation        │
└─────────────────────────────────────────┘
  │
  ▼
┌─────────────────────────────────────────┐
│ 7. emit_c                               │
│    CBackendUnit leaf methods            │
│    → C implementation/header/support    │
└─────────────────────────────────────────┘
  │
  ├───────────────────────────────────────┐
  ▼                                       ▼
┌───────────────────────────────┐       ┌───────────────────────────────┐
│ 8a. GCC C JIT                 │       │ 8b. C / AOT Artifact          │
│     gcc -shared -O3           │       │     user/compiler-owned build │
│     dlopen + dlsym            │       │     executable/library/object │
│     LuaJIT FFI fn pointers    │       │                               │
└───────────────────────────────┘       └───────────────────────────────┘

Optional non-main paths:
- explicit LuaJIT bytecode mode.
```

---

## Concrete Example Trace

How `lln.fn. add { a [lln.i32], b [lln.i32] } [lln.i32] { lln.ret (a + b) }`
becomes a GCC-cooked `emit_c` function pointer:

```
1. LuaJIT evaluates lln.fn.add{...}
   → DSL Decl metatable (kind="fn", name="add", params=[a,b], ...)

2. dsl.to_unit("demo", decl)
   → Decl:syntax() → LalinTree.Module{ items={ItemFunc{...}} }

3. Pipeline.typecheck_module(module)
   → SurfaceResolve → ClosureConvert → Typecheck
   → TypeModuleResult{ checked = { module = { funcs={...} } } }

4. Pipeline.checked_to_code_result(checked)
   → LayoutResolve → tree_lower → CodeValidate
   → CodeResult{ code_module = CodeModule{ funcs={...} } }

5. Pipeline.code_result_to_c(code_result)
   → graph/flow/value/memory/effect/kernel/schedule facts
   → C lower plan
   → CBackendUnit validation

6. emit_c over `CBackendUnit`
   → generated C implementation/header/support
   → ordinary C functions and helper definitions

7. GCC C JIT path
   → write/cook the emitted C as a shared object with GCC/cc
   → `dlopen` the shared object
   → `dlsym` exported functions
   → cast function pointers with LuaJIT FFI

8. add_fn(3, 4) calls the GCC-compiled function pointer

The C source emitted by `emit_c` is the contract. JIT-like execution and AOT both
consume that same C output. LuaJIT bytecode is selected only by explicit non-main
APIs/options; native copy-patch is retired.
```

---

## File Map

### DSL Surface

| File | Role |
|------|------|
| `lua/lalin/dsl/init.lua` | Lua-owned DSL surface. Defines `fn`, `struct`, `ret`, `if`, `region`, etc. heads. `to_unit()` converts Lua values into `LalinTree` ASDL. |
| `lua/lalin/dsl/format.lua` | Canonical semantic formatter for evaluated DSL values. |

### Frontend / Typecheck

Migrated LalinTree semantics live on ASDL classes as ordinary Lua methods.
Concrete union members own their own behavior; rewritten code must not use
`schema.classof(x) == Variant`, `kind` strings, or selector tables to choose
semantic behavior. When the method API needs more schema support, add it to
ASDL first; nullary variants also receive methods directly with normal
`function Module.Variant:operation(...) ... end` syntax.

| File | Role |
|------|------|
| `lua/lalin/frontend_pipeline.lua` | Orchestrates DSL→Tree→Typecheck→Code pipeline. Entry points: `typecheck_module`, `checked_to_code_result`, `code_result_to_c`. |
| `lua/lalin/tree_typecheck.lua` | Typecheck entrypoint and remaining stage orchestration while LalinTree methods are being split out. |
| `lua/lalin/tree_typecheck_type.lua` | Type-owned typecheck semantics for `LalinType` and literals. |
| `lua/lalin/tree_typecheck_expr.lua` | Expression/ref-owned typecheck semantics for `LalinTree.Expr*` and `LalinBind.ValueRef*`. |
| `lua/lalin/tree_typecheck_layout.lua` | Layout/ref matching semantics for `LalinSem.TypeLayout*` and `LalinType.TypeRef*`. |
| `lua/lalin/tree_expr_type.lua` | Expression type inference. |
| `lua/lalin/tree_stmt_type.lua` | Statement-level type operations (termination, etc.). |
| `lua/lalin/tree_place_type.lua` | Place (lvalue) type inference. |
| `lua/lalin/tree_module_type.lua` | Module-level type resolution, type environments, imports. |
| `lua/lalin/tree_contract_facts.lua` | Contract facts from function declarations (bounds, disjointness, SoA). |
| `lua/lalin/tree_control_facts.lua` | Control-flow facts from control regions (entry/block/continuation). |
| `lua/lalin/tree_lower.lua` | Typed AST to `LalinCode` lowering (`lower_tree_module_with_contracts_to_code`); ASDL classes own tree→code methods. |

### Code IR & Fact Analysis

| File | Role |
|------|------|
| `lua/lalin/code_type.lua` | Code type operations, size/alignment, target configuration. |
| `lua/lalin/code_validate.lua` | Validates `LalinCode` IR invariants. |
| `lua/lalin/code_graph.lua` | CFG builder — basic blocks, edges, loops, function-level graphs. |
| `lua/lalin/code_flow_facts.lua` | Flow analysis — domains, trip counts, loop structure. |
| `lua/lalin/code_value_facts.lua` | Value analysis — algebra, closed-form expressions, ranges, reductions. |
| `lua/lalin/code_mem_facts.lua` | Memory analysis — objects, intervals, aliasing, access patterns. |
| `lua/lalin/code_effect_facts.lua` | Effect analysis — read/write/atomic/rw, contract effects. |
| `lua/lalin/code_kernel_plan.lua` | Kernel identification — finds parallelizable loop/function fragments, produces `LalinKernel` plans; loop selection is typed ASDL behavior. |
| `lua/lalin/code_schedule_plan.lua` | Schedule planning — assigns scalar/vector/closed-form strategies per kernel; schedule selection is typed ASDL behavior. |
| `lua/lalin/code_lower_plan.lua` | Lowering strategy — decides code/kernel/closed-form per fragment; lower-fragment selection is typed ASDL behavior. |
| `lua/lalin/code_aggregate_abi.lua` | Aggregate type ABI classification — scalar/view/slice/bytespan/aggregate. |
| `lua/lalin/code_to_c.lua` | Maps `LalinCode` types/shapes to `LalinC` C IR. |

### Stencil & Execution Plans

| File | Role |
|------|------|
| `lua/lalin/exec_plan.lua` | Produces `LalinExec` plans — divides functions into scalar blocks, stencil calls, control, calls, returns, traps; exec stencil selection uses typed ASDL methods. |
| `lua/lalin/stencil_methods.lua` | Stencil-machine methods — classifies kernel body into point-expression plus sink vocabulary without a relation runner. |
| `lua/lalin/stencil_artifact_plan.lua` | Generates canonical stencil artifacts: `store_n`, `reduce_n`, `scan_n`, and scatter-reduce descriptors. Store-shaped loops are `store_n` with explicit point body, sink, and layout modes. |
| `lua/lalin/stencil_c.lua` | Generates complete C translation units for the separate C/AOT artifact path; it is not the native template-bank source path. |
| `lua/lalin/stencil_metastencil.lua` | Stencil matching/support analysis for non-native experiments; it is not a native-bank equivalence layer. |

### Explicit LuaJIT Bytecode Backend

| File | Role |
|------|------|
| `lua/lalin/luajit_backend.lua` | Explicit non-native backend facade for LuaJIT bytecode planning/emission. |
| `lua/lalin/luajit_lower.lua` | Lowers `LalinCode` + kernel plans to `LalinLuaJIT` IR for the bytecode path. |
| `lua/lalin/luajit_emit.lua` | Emits Lua source from `LalinLuaJIT` IR — LuaJIT functions with FFI ctypes and bytecode-path calls. |
| `lua/lalin/luajit_expr.lua` | Lua expression utilities for emission. |
| `lua/lalin/luajit_ctype.lua` | Converts `LalinCode.CodeType` to LuaJIT FFI ctype descriptors. |
| `lua/lalin/luajit_measure.lua` | Runtime measurement utilities (sizes, alignment, pointer bits). |
| LuaJIT bytecode support modules | Target identity and trace-shaped bytecode support for explicit LuaJIT bytecode mode. |

### Retired Native Copy-Patch Materialization

The binary-bank/copy-patch implementation and its public API were deleted. Do not
reintroduce them. The surviving stencil vocabulary is the emitted-C shape contract
in `schema_v2/stencil.lua`, `schema_v2/c_materialize.lua`, and
`impl/lower_emit_c/`.
### C Backend

| File | Role |
|------|------|
| `lua/lalin/emit_c_lower.lua` | Core C backend lowering — emits C source from `LalinC.BackendUnit` as .c, .h, combined artifact output; houses C helper functions. |
| `lua/lalin/lower_to_c.lua` | Lowers `LalinCode` + lower plan to C IR. |
| `lua/lalin/emit_c_validate.lua` | Validates C IR invariants. |
| `lua/lalin/emit_c_helpers.lua` | Thin wrapper exposing the C helper function library for stencil operations. |
| `lua/lalin/emit_c_tcc.lua` | Optional libtcc LuaJIT FFI runner for in-process C compilation; GCC remains the performance path. |
| `lua/lalin/emit_c_coverage.lua` | Canonical C-backend coverage classification matrix. |

### Compiler Process

| File | Role |
|------|------|
| `lua/lalin/compiler_driver.lua` | Public orchestration boundary — lowers modules through the compiler-process graph. |
| `lua/lalin/compiler_package.lua` | Defines the compiler process as a `LalinPhase` package with worlds, machines, phases, roots. |
| `lua/lalin/compiler_machines.lua` | Concrete machine implementations (typecheck, checked→c_code, code→c). |
| `lua/lalin/compiler_model.lua` | Loads full schema into a context. |
| `lua/lalin/compiler_abi.lua` | CodeResult ABI validation. |
| `lua/lalin/phase_model.lua` | Loads LalinPhase schema. |
| `lua/lalin/phase_dsl.lua` | LLBL dialect for authoring phase packages. |
| `lua/lalin/phase_plan.lua` | Phase graph planner — finds valid paths, produces ordered Plan. |
| `lua/lalin/phase_execute.lua` | Plan executor — runs phase steps, resolves machines, passes outputs. |
| `lua/lalin/phase_validate.lua` | Validates phase package structure. |

### Back Infrastructure

| File | Role |
|------|------|
| `lua/lalin/backend_target_model.lua` | Target model — CPU features, ABI, capabilities. |

### Error / Diagnostics

| File | Role |
|------|------|
| `lua/lalin/error/init.lua` | Error management facade — registry, emit, reports, render. |
| `lua/lalin/error/span.lua` | Source span type and operations. |
| `lua/lalin/error/report.lua` | ErrorReport construction. |
| `lua/lalin/error/catalog.lua` | Error catalog — code registry, explainers by phase. |
| `lua/lalin/error/registry.lua` | Issue registry — collects, deduplicates, produces reports. |
| `lua/lalin/error/format.lua` | Shared formatting utilities. |
| `lua/lalin/error/present_terminal.lua` | Terminal rendering of diagnostics. |
| `lua/lalin/error/issue_collector.lua` | CollectingCollector and ThrowingCollector — phase boundary to diagnostic engine. |
| `lua/lalin/error/cascade_filter.lua` | Cascade suppression filter. |
| `lua/lalin/error/span_resolvers.lua` | Phase-specific span resolvers. |
| `lua/lalin/error/suggest.lua` | Error suggestions. |

### Source Infrastructure

| File | Role |
|------|------|
| `lua/lalin/source_anchor_index.lua` | Source anchor index — maps positions to anchors. |
| `lua/lalin/source_position_index.lua` | Line/column position index. |
| `lua/lalin/source_analysis.lua` | Source analysis utilities. |
| `lua/lalin/source_text_apply.lua` | Source text manipulation operations. |

### Prebuild Tools

| File | Role |
|------|------|
| `tools/gen_lalin_module_bank.lua` | Prebuilds explicit LuaJIT bytecode support. Dumps required `.lua` source files to bytecode and emits C byte-array sources for embedding. |

### Other

| File | Role |
|------|------|
| `lua/lalin/init.lua` | Public facade — `.lln` declaration-document loading, `lalin.compile`, `lalin.emit_c`, etc. |
| `lua/lalin/loader.lua` | `.lln` loadfile/loadstring/searchpath/searcher integration returning declaration arrays. |
| `lua/lalin/cli.lua` | CLI interface. |
| `lua/lalin/ast.lua` | AST utility layer. |
| `lua/lalin/quote.lua` | Quotation utilities. |
| `lua/lalin/reduction_algebra.lua` | Reduction algebra (commutative, associative) for stencil optimization. |
| `lua/lalin/value_proxy.lua` | Value proxy for DSL values. |
| `lua/lalin/closure_convert.lua` | Closure conversion pass. |
| `lua/lalin/surface_resolve.lua` | Surface name resolution. |
| `lua/lalin/const_eval.lua` | Constant evaluation. |
| `lua/lalin/layout_resolve.lua` | Layout resolution. |
| `lua/lalin/switch_decide.lua` | Switch dispatch decision. |
| `lua/lalin/project_asdl.lua` | Project ASDL utilities. |
| `lua/lalin/project_ready_facts.lua` | Project readiness facts. |
| `lua/lalin/project_report.lua` | Project report generation. |

---

## Schema / ASDL Modules

Each file in `lua/lalin/schema/` returns a `lalinschema` Module defining
the ASDL types for that domain:

| File | Key Types |
|------|-----------|
| `core.lua` | Name, Path, Id, Scalar, Literal, BinaryOp, CmpOp, CastOp, Intrinsic, AtomicOrdering |
| `type.lua` | Type — TScalar, TPtr, TView, TSlice, TArray, TLease, TOwned, TAccess, THandle, TClosure, TFunc, Param, FieldDecl |
| `tree.lua` | Module, Expr (30+ variants), Stmt (20+), Place, Func, ConstItem, Region, ControlBlock, SwitchArm, Domain |
| `code.lua` | CodeModule, CodeFunc, CodeBlock, CodeInst, CodeTerm, CodeType, CodeValue, CodeOp, CodeContract |
| `graph.lua` | Graph, GraphFunc, GraphEdge, GraphLoop, GraphBlock |
| `flow.lua` | FlowDomain, FlowTripCount, FlowEdgeFact, FlowModuleFacts |
| `value.lua` | ValueExpr, ClosedFormFact, ReductionFact, AlgebraProof, ValueModuleFacts |
| `mem.lua` | MemObject, MemAccess, MemInterval, MemAccessPattern, MemModuleFacts |
| `effect.lua` | OpEffect, EffectModuleFacts |
| `kernel.lua` | KernelSubject, KernelDomain, KernelLane, KernelPlan, KernelReject, KernelModulePlan |
| `stencil.lua` | StencilArtifact, StencilPlan, StencilSinkVocab, StencilLayout, StencilModulePlan |
| `schedule.lua` | KernelSchedule, ScheduleKind, ScheduleModulePlan |
| `lower.lua` | LowerFragment, LowerStrategy, LowerModulePlan |
| `exec.lua` | ExecFragment, ExecFragmentKind, ExecModulePlan |
| `back.lua` | BackTargetModel, BackFunc, BackBlock, BackInst, BackProgram |
| `c.lua` | CBackendUnit, CBackendFunc, CBackendType, CBackendStmt |
| `luajit.lua` | LJModule, LJFunc, LJBlock, LJExpr, LJInst, LJCType, LJStencilMachine |
| `luatrace.lua` | LuaTrace trace descriptors, BC bank types |
| `compiler.lua` | CodeResult |
| `phase.lua` | Package, World, Machine, Phase, Root, Plan, PlanStep |
| `bind.lua` | Binding, ValueRef |
| `sem.lua` | FieldRef, FieldLayout, TypeLayout, LayoutEnv, ConstValue |
| `link.lua` | Link plan and target model |
| `host.lua` | Host field representation |
| `parse.lua` | Parse tree types |
| `source.lua` | Source location types |
| `project.lua` | Project structure |

---

## Shape Survives, Patcher Retired

**Status of the native copy-patch track: retired.** The binary patcher —
template-bank import (`native_mc`), object parsing/verifying (`native_object`),
typed hole/continuation relocations, executable-memory install — is abandoned.
It must not be reopened, and `compile_native` should not be treated as a
selectable mode.

**What survives is the stencil vocabulary, as a deterministic emitted-C shape
contract.** `schema_v2/stencil.lua` (producers, accesses, layouts, streams,
sinks, schedules) and the canonical CMat fragment path
(`schema_v2/c_materialize.lua` + `impl/lower_emit_c/`) are load-bearing and are
being wired into the main pipeline: covered functions emit through
`CMatCFragmentInput -> emit_cmat_fragment()`, and the resulting C is spliced
into `CBackendUnit` and cooked with GCC -O3. The stencil vocabulary no longer
names machine templates; it names the C shape that GCC optimizes.

**The performance path is fused emitted C + GCC -O3.** Fusion eligibility is a
typed decision procedure: exact emitted C plus declared memory, noalias, and
bounds facts determine whether a fragment fuses; after fusion the contracts are
recomputed over the fused C. The `LalinCode`/`LalinKernel`/`LalinStencil`
leaves keep owning semantics; the CMat fragment path owns the emitted shape.

**Still explicit and non-main:** LuaJIT bytecode mode (`compile_luajit`,
`opts.bytecode`) — a separate artifact form, unrelated to the retired patcher.

**Deleted:** the `lua/lalin/native*.lua` runtime, `schema/native.lua`, native-bank
generator and build rules, and `test_native_*` suite. `lalin-bin` now embeds only
the LuaJIT module bank needed by the executable.
vocabulary — `schema_v2/stencil.lua`, `schema_v2/c_materialize.lua`,
`impl/lower_emit_c/*`, and the `test_cmat_*` / `test_stencil_c_gcc` harnesses —
is untouched. `docs/RESIDUAL_NATIVE_ARCHITECTURE.md` is the historical record.

## Explicit LuaJIT Bytecode Mode

LuaJIT bytecode remains a separate non-native backend mode for debugging,
measurement, and platforms that choose it explicitly. It is selected by the
explicit LuaJIT/bytecode API or option and is not an implicit native recovery
path.

```text
LalinCode facts
  -> LuaJIT IR / LuaTrace-shaped bytecode support
  -> bytecode artifact data
  -> loadstring/chunk/module through LuaJIT
```

The bytecode path may build bytecode artifacts in-process because bytecode is
its own selected artifact form. It does not satisfy a missing native bank (native banks are retired).

## Lua C API Extern Boundary

The hosted runtime is reachable through the ordinary C extern machinery. Lua C
API entry points are not special compiler intrinsics: they are extern symbols
with typed signatures, runtime-symbol addresses, and the same call planning as
other C functions.

```text
Lalin extern declaration
  -> LalinCode.CodeExtern
  -> native runtime symbol / C extern symbol
  -> ordinary call lowering
```

This is deliberately only the substrate. Direct calls to `lua_gettop`,
`lua_settop`, `lua_pcall`, `luaL_ref`, and `luaL_unref` expose stack slots,
integer status codes, and registry integers. The architectural object layer is a
LuaBridge object vocabulary on top of those externs:

```text
LuaState / LuaRegistry / LuaStackMark / LuaRef
  -> qualified functions and regions
  -> owned registry-reference obligations
  -> typed ok/error continuations
  -> raw externs hidden inside bridge-private implementations
```

So the backend does not need a separate Lua-object calling convention to begin
with; externs are sufficient to touch the Lua API. The object API is still
necessary because it turns raw C ABI facts into Lalin ownership and control
facts.

---

## GCC C JIT And C / AOT Emission Path

`emit_c` is the whole-program semantic C backend path and the center of both the
main JIT-like execution path and the AOT path. It lowers the selected typed
program to C. The GCC C JIT path cooks that emitted C into a shared object,
loads it with `dlopen`, and exposes symbols as LuaJIT FFI function pointers. The
AOT path gives the same emitted C artifact to the user or build system to compile
into a program or library.

Conceptually:

```text
LalinTree.Module
  -> typecheck
  -> LalinCode facts
  -> graph/flow/value/memory/effect facts
  -> C lower plan
  -> CBackendUnit validation
  -> emit C implementation + header/support
  -> user compiles the C artifact
```

This path exists for both JIT-like local execution and AOT/native integration:

- The artifact is ordinary C source plus generated header/support pieces.
- High-level abstractions lower to ordinary C structs, functions, labels, and
  helpers so GCC or another C compiler can inline, scalarize, and optimize them.
- `lalin.compile_c_gcc` / `{ runner = "gcc" }` cook the emitted C as a shared
  object and return a session whose symbols are LuaJIT FFI function pointers.
- For AOT, the user owns the final compiler invocation, flags, linker inputs,
  and target ABI choices.

The ownership boundary is:

| Path | Host | Compiler role | Output |
|------|------|---------------|--------|
| GCC C JIT over `emit_c` | LuaJIT host + `dlopen` | runtime GCC/cc shared-object build | LuaJIT FFI function pointers |
| `emit_c` AOT | user/build system | user compiles emitted program C | C source/header/support |
| explicit LuaJIT bytecode | LuaJIT | none for native code | LuaJIT bytecode artifact/module |

---

## Region Model

`region.` is the generic LLBL control-machine head. This is one of the main
reasons LLBL composes the whole language: the same control algebra can describe
native CFG, processes, parser steps, scheduler steps, and backend
pull machines. A region is:

```text
input product + state product + named exit protocol + transition body
```

Streams are not a separate semantic category. A pull stream is a region with a
pull protocol. GPS is one lowering of a pull-shaped region:

```lua
gen(param, state) -> nil
gen(param, state) -> next_state, payload...
```

This keeps laziness and fusion explicit. A consumer asks for the next exit; the
machine computes only enough to produce that exit. Whole arrays, reports,
diagnostic bags, backend buffers, and artifacts are materializers, not the
region itself.

Lalin consumes generic region descriptors when the body uses native Lalin
`entry`, `block`, `jump`, and `emit` vocabulary. LLBL processes lower event protocols to GPS.

Region composition has two runtime shapes:

```text
emit
  direct CFG splice; no frame; all exits wired at the call site

call
  instrumentable/recursive boundary; implemented as sealed function plus
  encoded exit union plus dispatch back to named exits
```

Use `emit` for ordinary internal composition. Use `call` when the region needs
its own frame for recursion, profiling, debugging, or instrumentation.

---

## Language Layers

LLBL owns the extensible language substrate. This is the center of the
architecture:

- symbols and namespace values
- staged heads and role normalization
- fragments and spread expansion
- origins, comments, diagnostics, formatting, and indexing hooks
- generic regions, protocols, GPS lowering, and process events
- language composition and managed `use()` sessions

The `llbl` member is the identity element of language composition. Composing a
language with `llbl.core_language()` returns the other language when no rename or
preference override is requested. Every language therefore shares the same bare
substrate by default: symbol creation, source/generated symbol provenance,
origin tracking, diagnostics, fragments, regions, the formatting document
model, and language export ownership.

The identity-owned service surface is:

```text
llbl.shared.symbols
llbl.shared.origins
llbl.shared.diagnostics
llbl.shared.fragments
llbl.shared.regions
llbl.shared.formatting
llbl.shared.languages
```

Symbol resolution is shared, but symbol meaning is not. LLBL resolves a symbol
to a language binding:

```lua
local binding = language:resolve_symbol(sym)
```

The binding says which language member exported the name, whether the source was
generated, and whether the symbol is unresolved. Lalin, LalinSchema, and
other dialects decide what that binding means semantically.

The language audit records more than ownership. It records:

```text
owns / uses
resolves / formats / indexes / lowers / materializes
```

Those capability axes are the review surface for existing dialects.

LLBL bootstraps itself in two stages:

- `llbl.kernel`: the small Lua stage-0 substrate that owns primitive values,
  origins, diagnostics, GPS, regions, stage-0 grammar records, and the dialect
  compiler.
- `llbl.self`: the stage-1 `llbl` dialect, built by `lua/llbl/bootstrap.lua` using
  the stage-0 substrate.
- `llbl.grammar`: the public grammar facade backed by `llbl.self`; it emits the
  same declaration records expected by the dialect compiler, but the facade
  itself is now an LLBL dialect surface.
- `llbl.bootstrap.machines`: region-backed bootstrap machines for work such as
  role normalization and doc rendering.

Lalin is the compiled member. It owns native language semantics:

- scalar, pointer, view, handle, lease, and owned type values
- declarations, products, protocols, functions, and regions
- expression and statement semantics
- resource and ownership checking
- typecheck, lowering, and backend projection

LalinSchema owns schema/type-language semantics:

- product and sum schema declarations
- typed ASDL constructor families
- schema projection into runtime values

Lalin itself now carries its own VM semantics through region-shaped work and
the compiler pipeline (CMat SOAC lowering, GPS). No separate VM dialect is needed.

The reduction rule is strict: if two members can express the same semantic
primitive, one member owns it and the other projects to it. Overlapping
implementations are a design bug, not a feature.

---

## Compiler Boundaries

Important boundaries:

- DSL normalization produces explicit Lalin syntax/tree values.
- Typechecking owns name, type, ownership, and control validity.
- LalinCode is the normalized compiler product used by later lowering.
- Kernel facts describe recognized loop/control/dataflow structure.
- Schedule facts describe execution policy such as vectorization and unroll.
- Stencil plans select materializable execution descriptors.
- GCC C JIT and AOT consume `emit_c` output.
- LuaJIT bytecode is an explicit non-main mode.

Schedules are not semantics. They may choose lanes, tails, grouping, and
compiler/materializer policy, but they may not invent effects, stores,
reductions, alias facts, or safety conditions.

---

## Backend Model

The main executable backend model is GCC over `emit_c` output. It is selected
with `compile_c_gcc`, `{ runner = "gcc" }`, or `{ backend = "gcc" }`. The AOT
path is the same `emit_c` output without the runtime `dlopen` step. LuaJIT
bytecode is an explicit non-main mode; native copy-patch is retired.

| Path | Selected by | Compiler needed at runtime | Build time |
|------|-------------|----------------------------|-----------|
| GCC C JIT over `emit_c` | `compile_c_gcc` / `{ backend = "gcc" }` | GCC/cc | shared-object build + `dlopen` |
| `emit_c` AOT | `emit_c` / `compile_c` source mode | user/build-system choice | user-owned C build |
| explicit LuaJIT bytecode | explicit `compile_luajit`/bytecode selection | no external C compiler | in-process bytecode artifact construction |

### Retired Native Copy-Patch Path

The offline bank generator and runtime copy-patch/install implementation were
deleted. They must not be reintroduced; fused emitted C + GCC -O3 is the
performance path.

### Explicit LuaJIT Bytecode Path

The bytecode path is selected only by explicit non-native API/options:

- LuaTrace/LuaJIT lowering emits trusted LuaJIT-shaped functions from typed
  plans.
- Bytecode support stores compiled prototypes/artifacts with typed identity.
- Materialization loads the selected bytecode artifact through LuaJIT.
- It is independent of the emitted-C + GCC performance path.

### Ground rules

The backend must consume semantic facts honestly:

- type families and ABI layout
- array/view/span descriptors
- readonly, bounds, alias, and residence facts
- reductions and effect classification
- vectorization schedule policy
- target and materializer constraints

If a fact is required for correctness or performance but is not represented in
ASDL, the schema is incomplete and must be fixed before lowering is extended.

---
## C And Stencil Shape Contract

`emit_c` is the main runtime and AOT output. The stencil vocabulary
(`schema_v2/stencil.lua` -> CMat fragment path -> `emit_c`) is the deterministic
shape contract for fused emission: exact emitted C plus declared
memory/noalias/bounds facts make fusion eligibility a typed decision procedure,
and contracts are recomputed after fusion. GCC -O3 over that emitted C is the
performance path.
---

## Diagnostics

Diagnostics are structured values. They should carry:

- code
- message
- primary origin
- related origins
- head, slot, role, event, or phase context when available
- prose comments captured from source context where useful

Fast generated paths should be diagnostically lazy. They carry compact metadata
and replay through reflective machinery on failure when a rich diagnostic is
needed.

---

## Completion Law

A lowering is complete only when its full semantic language is represented,
validated, measured, and wired through the backend. Do not move upward to a
higher lowering while the lower layer still has known semantic gaps.
