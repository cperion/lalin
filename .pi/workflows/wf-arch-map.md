# Compiler Architecture Deep Map 
Map the Lalin compiler pipeline in detail: from DSL surface through typechecking, code IR, lowering, stencil planning, and MC bank materialization.
**Workflow ID**: wf-arch-map
**Started**: 2026-06-28 11:31:42
---

## Scout Output — 2026-06-28 11:34:02

Now I have comprehensive data. Let me compile the full architecture map.

---

## Compiler Architecture Deep Map — Complete Pipeline

---

## 1. DSL Surface (`lua/lalin/dsl/`)

### `lua/lalin/dsl/init.lua` (2662 lines)
**Purpose**: Lua-owned Lalin DSL surface. Lua evaluates bracket types `[T]` before the DSL sees them; this module normalizes resolved values into closed `LalinTree` ASDL.

**Key exports**:
| Export | Kind | Purpose |
|--------|------|---------|
| `M.fn`, `M.struct`, `M.union`, `M.const`, `M.static`, `M.extern`, `M.handle`, `M.region`, `M.import`, `M.export_fn` | Decl constructors | Create DSL `Decl` metatables |
| `M.unit(name, decls)` | function | Creates a `unit` Decl |
| `M.to_unit(name, value)` | function | Converts arbitrary Lua/LLBL value into closed Decl |
| `M.ret`, `M.yield`, `M.let`, `M.var`, `M.set`, `M.assert_`, `M.trap`, `M.If`, `M.when`, `M.jump`, `M.switch`, `M.assume`, `M.astore`, `M.afence` | Stmt constructors | Create DSL `Stmt` metatables |
| `M.add`, `M.sub`, `M.mul`, `M.div`, `M.rem`, `M.band`, `M.bor`, `M.bxor`, `M.shl`, `M.shr` | Binary ops | Curried DSL expression operators |
| `M.eq`, `M.ne`, `M.lt`, `M.le`, `M.gt`, `M.ge` | Compare ops | Curried comparison operators |
| `M.And`, `M.Or`, `M.Not`, `M.neg`, `M.bnot` | Logic ops | Curried logical operators |
| `M.addr`, `M.deref`, `M.load`, `M.len`, `M.select`, `M.null`, `M.sizeof`, `M.alignof` | Expr forms | Address-of, deref, etc. |
| `M.as`, `M.bitcast` | Type forms | Type-form expression constructors |
| `M.aload`, `M.armw`, `M.acas`, `M.ctor` | Advanced expr | Atomic and variant constructor |
| `M.bounds`, `M.disjoint`, `M.same_len`, `M.window_bounds`, `M.soa_component` | Contracts | Contract annotation constructors |
| `M.loop`, `M.range`, `M.range_nd`, `M.tiled_nd`, `M.window_nd`, `M.fold`, `M.scan`, `M.entry`, `M.block` | Native loop/ctrl | Loop and control block DSL |
| `M.case`, `M.default`, `M.requires` | Switch/contracts | Switch arm and contract DSL |
| `M.product`, `M.stmts`, `M.decls`, `M.exprs`, `M.conts`, `M.variants` | Fragment constructors | LLBL fragment roles |
| `M.llbl`, `M.language`, `M.process`, `M.lalin` | LLBL integration | The `LalinLLB` LLBL dialect and zone head |
| `M.use()`, `M.namespace()` | Global setup | Injects DSL globals, creates lln/lalin namespaces |

**DSL → LalinTree mapping**:
- `Decl:syntax()` → produces `LalinTree.Module` from `unit` Decl
- `Decl:syntax_item()` → produces `Tr.Item*` (ItemFunc, ItemType, ItemExtern, ItemConst, ItemStatic, ItemImport, ItemRegion)
- `Stmt:tree()` → maps `ret/let/var/set/if/when/jump/switch/native_loop` etc. to `Tr.Stmt*`
- `Expr:tree()` → maps `binary/cmp/call/cast/addr/deref/select` etc. to `Tr.Expr*`
- `tree_expr(v)` → generic tree expression converter (handles Lua primitives, LLBL exprs, arrays, records)

**Key imports**: `llbl`, `lalin.pvm`, `lalin.schema_projection`, `lalin.error.span`, `lalin.source_analysis`

### `lua/lalin/dsl/format.lua` (full file, ~280 lines)
**Purpose**: Canonical semantic formatter for evaluated DSL values. Prints `LalinTree`/`LalinCore` ASDL and DSL metavalues as formatted text.

**Key functions**: `M.doc(value, opts)`, `M.format(value, opts)`, `M.file_text(value, opts)`, `M.format_file(path, opts)`, `M.write_format_file(path, opts)`

---

## 2. Frontend Pipeline (`lua/lalin/frontend_pipeline.lua`)

**Purpose**: Orchestrates the compilation pipeline from DSL module AST through typecheck, code IR, facts, plans, and backend lowering.

**Exported functions** (all bound to a schema context `T`):

| Function | What it does |
|----------|-------------|
| `typecheck_module(module, opts)` | SurfaceResolve → ClosureConvert → Typecheck.check_module. Returns `LalinTree.TypeModuleResult` (with `checked.module`) |
| `checked_to_code_result(checked, opts)` | Layout resolve → tree_to_code → CodeValidate. Returns `LalinCompiler.CodeResult(code_module, contracts, layout_env)` |
| `code_result_to_back(code_result, opts)` | CodeGraph → FlowFacts → ValueFacts → MemFacts → EffectFacts → KernelPlan → SchedulePlan → LowerPlan → KernelValidate → LowerToBack → BackValidate. Returns `{program, back_report}` |
| `code_result_to_c(code_result, opts)` | Same fact pipeline but with LowerTargetC → LowerToC → CValidate. Returns `{c_unit, c_report}` |

**Process versions** (LLBL process wrappers for event-driven use):
- `typecheck_module_process`, `checked_to_code_process`, `code_to_back_process`, `code_to_c_process`

**Pipeline phases order** (as seen in `checked_to_code_result` internal):
1. `surface_resolve` — resolve surface names/references
2. `closure_convert` — closure conversion pass
3. `typecheck` — full tree typechecking → `TypeModuleResult`
4. `layout_env` + `layout_resolve` — semantic layout of types
5. `tree_to_code` — Tree (LalinTree) → Code (LalinCode) IR
6. `code_validate` — validate Code IR invariants
7. `code_graph` — build CFG
8. `flow_facts` + `flow_semantics` — flow analysis
9. `value_facts` — value analysis (algebra, range)
10. `mem_facts` + `mem_semantics` — memory analysis (objects, intervals, aliasing)
11. `effect_facts` — effect analysis (side effects, contract effects)
12. `kernel_plan` — identify kernels (loops/functions for stencil lowering)
13. `schedule_plan` — schedule kernels (scalar/vector/closed-form)
14. `lower_plan` — decide lowering strategy per fragment (code/kernel/closed-form)
15. `kernel_validate` — validate kernel correctness
16. `lower_to_back` or `lower_to_c` — produce Back IR or C IR

---

## 3. Tree/Typecheck (`lua/lalin/tree_typecheck*.lua`, `tree_*.lua`)

### `lua/lalin/tree_typecheck.lua` (2862 lines)
**Purpose**: Full LalinTree typechecker. Walks expressions, statements, functions, regions, modules.

**Key internal functions**:
- `type_module(module, opts)` — typechecks entire module
- `type_func(func, env)` — typechecks function body
- `type_stmt`, `type_stmt_body`, `type_expr`, `type_expr_expect`, `type_place` — recursive typecheckers
- `type_control_stmt_region`, `type_control_expr_region` — region typing
- `type_switch_key` — switch dispatch typing
- `select_stmt_typecheck(stmt)`, `select_expr_typecheck(expr)` — dispatch via rules

**Key imports**: `tree_module_type`, `tree_control_facts`, `tree_typecheck_rules`

### `lua/lalin/tree_typecheck_rules.lua`
**Purpose**: Rule-based dispatch tables for statement and expression typechecking. Maps `Tr.Stmt*` / `Tr.Expr*` classes to typecheck handler names.

### `lua/lalin/tree_expr_type.lua`
**Purpose**: Expression type inference. Computes the `LalinType.Type` for each expression kind.

### `lua/lalin/tree_stmt_type.lua`
**Purpose**: Statement-level type operations (e.g., blocks that must terminate).

### `lua/lalin/tree_place_type.lua`
**Purpose**: Place (lvalue) type inference — paths, dereferences, fields, indexes.

### `lua/lalin/tree_module_type.lua`
**Purpose**: Module-level type resolution. Builds type environments, resolves import/module dependencies, generates `LayoutEnv`.

### `lua/lalin/tree_field_resolve.lua`
**Purpose**: Field resolution — resolves `struct.field`, `Dot` expressions to their types and offsets.

### `lua/lalin/tree_contract_facts.lua`
**Purpose**: Extracts contract facts (bounds, disjointness, SoA components) from function declarations.

### `lua/lalin/tree_control_facts.lua`
**Purpose**: Control-flow facts extracted from tree-level control regions (entry/block/continuation structure).

### `lua/lalin/tree_to_code.lua` (1774 lines)
**Purpose**: Lowers `LalinTree` (typed AST) to `LalinCode` (code IR). Central `tree_to_code` pipeline.

**Key internal functions**:
- `api.module_with_contracts(layout_module, opts)` → returns `(code_module, code_contracts)`
- Lowering dispatch via `select_lowering(ctx, relation, node)` using `tree_to_code_rules`
- Handles: `func` (entry/block/params), `expr` (all variants), `stmt` (all variants), `place`, `control`, `region`, `contract`

### `lua/lalin/tree_to_code_rules.lua`
**Purpose**: Dispatch tables mapping `Tr.Stmt*`/`Tr.Expr*`/`Tr.Place*` classes to lowering handler names.

**Dispatch tables**:
- `select_expr_lowering` — 27 expr variants (lit, ref, unary, binary, compare, call, control, etc.)
- `select_place_lowering` — 5 place variants (ref, deref, field, index, dot)
- `select_stmt_lowering` — 16 statement variants (let, var, set, if, switch, control, jump, etc.)

---

## 4. Code IR (`lua/lalin/code_*.lua`)

### `lua/lalin/code_type.lua`
**Purpose**: Code type operations — conversion from `LalinType.Type` to `LalinCode.CodeType`, default target configuration, size/alignment computations.

**Key exports** (per context): `CodeType.code_type(ty, layout_env, target)`, `CodeType.code_type_to_c(ty, ctx)`, `CodeType.default_target(opts)`, `CodeType.code_type_key(ty)`

### `lua/lalin/code_validate.lua`
**Purpose**: Validates `LalinCode` IR invariants — checks value types, block structure, terminator consistency.

### `lua/lalin/code_graph.lua`
**Purpose**: Builds the CFG (`LalinGraph`) from `LalinCode.Module`. Identifies basic blocks, edges, loops, and function-level graphs.

**Key internal**: `api.graph(module)` → returns `LalinGraph.Graph` with `funcs[*].{func, edges, blocks, loops, ...}`

### `lua/lalin/code_flow_facts.lua`
**Purpose**: Flow analysis — computes flow facts (`LalinFlow`) from the CFG: edge facts, loop structure, domain information (1D ranges, ND ranges, zipped domains), trip counts, flow semantics.

**Key exports**: `api.facts(module, graph)` → `Flow.FlowModuleFacts`, `api.semantic_facts(module, graph, flow)` → enriched semantic facts

### `lua/lalin/code_value_facts.lua`
**Purpose**: Value analysis — computes `LalinValue` facts: algebra proofs, closed-form expressions, range information, arithmetic series, reduction algebra.

**Key exports**: `api.facts(module, graph, flow)` → `Value.ValueModuleFacts`

### `lua/lalin/code_mem_facts.lua`
**Purpose**: Memory analysis — computes `LalinMem` facts: memory objects, access intervals, aliasing proofs, access patterns (contiguous, strided, random), backend info.

**Key exports**: `api.facts(module, graph, flow, value, contracts)` → `Mem.MemModuleFacts`, `api.semantic_facts(...)` → semantic layer

### `lua/lalin/code_effect_facts.lua`
**Purpose**: Effect analysis — computes `LalinEffect` facts: operation effects (read, write, readwrite, atomic), contract-sourced effects, side-effect categories.

**Key exports**: `api.facts(module, graph, mem_semantics, contracts)` → `Effect.EffectModuleFacts`

### `lua/lalin/code_kernel_plan.lua` (1092 lines)
**Purpose**: Kernel identification and planning — identifies kernels (parallelizable loop/function fragments) and produces `LalinKernel` plans.

**Key internal**: Analyzes flow domains, memory access patterns, value expressions. Identifies lanes, access patterns, reduction facts. Rejects unsupported patterns.

**Key exports**: `api.plan(module, graph, flow, value, mem, effects)` → `Kernel.KernelModulePlan`

**Key imports**: `code_kernel_plan_rules` (rule-based dispatch for kernel classification)

### `lua/lalin/code_kernel_plan_rules.lua`
**Purpose**: Rule dispatch tables for kernel plan classification.

### `lua/lalin/code_schedule_plan.lua` (~160 lines)
**Purpose**: Schedule planning — assigns execution strategies to kernels: scalar, vector (with lane shape, unroll, interleave, tail plan), or closed-form.

**Key exports**: `api.plan(module, kernel, flow, value, mem, effects, target_model)` → `Schedule.ScheduleModulePlan`

**Key imports**: `code_schedule_plan_rules`, `kernel_emit_support`

### `lua/lalin/code_schedule_plan_rules.lua`
**Purpose**: Rule dispatch for schedule plan classification.

### `lua/lalin/code_lower_plan.lua` (~245 lines)
**Purpose**: Lowering strategy planning — decides per-fragment whether to emit via code strategy (scalar path), kernel strategy (stencil path), or closed-form strategy.

**Key exports**: `api.plan(module, graph, kernel_plan, schedule_plan, lower_target)` → `Lower.LowerModulePlan`

**Key imports**: `code_lower_plan_rules`

### `lua/lalin/code_lower_plan_rules.lua`
**Purpose**: Rule dispatch for lower plan strategy selection.

### `lua/lalin/code_aggregate_abi.lua`
**Purpose**: Aggregate type ABI classification — determines if types are scalar, view, slice, byte_span, or aggregate; provides component scalar extraction.

### `lua/lalin/code_to_back.lua` (1357 lines)
**Purpose**: Low-level mapping from `LalinCode` types/shapes to `LalinBack` back types. Converts literals, values, instructions to Back IR primitives.

**Key exports**: `api.scalar(ty)`, `api.literal(lit)`, `api.value(...)`, `api.inst(...)`

### `lua/lalin/code_to_c.lua` (755 lines)
**Purpose**: Low-level mapping from `LalinCode` types/shapes to `LalinC` C types. Handles type declarations, function signatures, helpers.

**Key exports**: `api.module(code_module)` → `C.CBackendUnit`

---

## 5. Exec Plan & Stencil

### `lua/lalin/exec_plan.lua` (198 lines)
**Purpose**: Produces `LalinExec` execution plan — divides each function into fragments (scalar blocks, stencil calls, control blocks, calls, returns, traps).

**Key exports**: `api.plan(module, {graph, flow, value, mem, effect, kernels, stencil, artifacts})` → `LalinExec.ExecModulePlan`

### `lua/lalin/exec_plan_rules.lua`
**Purpose**: Rule dispatch for exec plan fragment classification.

### `lua/lalin/stencil_rules.lua` (1060 lines)
**Purpose**: Stencil rule engine — classifies kernel body expressions into stencil vocabularies: `apply`, `reduce`, `scan`, `scatter_reduce`. Translates `KernelExpr`/`KernelEffect` into `StencilExpr`/`StencilEffect`.

**Key exports per context**: Rule dispatch for stencil selection, classified by kernel plan content

### `lua/lalin/stencil_artifact_plan.lua` (2552 lines)
**Purpose**: Generates stencil artifacts — the concrete plan for each stencil operation. Contains factories for all ~30 artifact kinds:

| Artifact kind | What it does |
|--------------|-------------|
| `copy_array`, `fill_array` | Memory operations |
| `map_array`, `zip_map_array`, `in_place_map_array` | Elementwise apply |
| `cast_array`, `compare_array`, `zip_compare_array` | Cast/comparison |
| `gather_array`, `scatter_array`, `scatter_reduce_n` | Indexed access |
| `apply_n` | Generic N-ary apply |
| `reduce_array`, `reduce_n`, `map_reduce`, `zip_reduce` | Fold/reduction |
| `scan_array` | Prefix scan |
| `find_array`, `count_array`, `partition_array` | Search/partition |

**Key exports per context**: `api.*_array_artifact(info)` for each kind

### `lua/lalin/stencil_metastencil.lua` (513 lines)
**Purpose**: Metastencil abstraction — provides cross-provider stencil instance matching, resolves type/stencil equivalence between MC bank and BC bank materialization paths.

### `lua/lalin/stencil_support_matrix.lua` (223 lines)
**Purpose**: Declares the stencil support matrix — what's `supported`, `rejected`, `future` for each vocab, derived plan, layout, and materializer.

---

## 6. LuaJIT Backend (`lua/lalin/luajit_backend.lua` etc.)

### `lua/lalin/luajit_backend.lua` (365 lines)
**Purpose**: Central LuaJIT backend orchestration. Binds the stencil/kernel plan pipeline to LuaJIT emission and copy-patch materialization.

**Key exports** (per context):
| Function | What it does |
|----------|-------------|
| `api.lower_module(module, opts)` | Runs full kernel pipeline: Lower → StencilRules → StencilMachine → lower_module → ExecPlan. Returns `(lj_module, facts, artifacts, rejects)` |
| `api.realize_artifacts(artifacts, opts)` | Materializes artifacts via MC bank or BC bank |
| `api.build_mc_bank(artifacts, opts)` | Builds an MC stencil bank |
| `api.build_bc_bank(artifacts, opts)` | Builds a BC stencil bank |
| `api.compile_lj_module(lj_module, artifacts, opts)` | Full compile: realize + emit |
| `api.emit_lua_artifact(lj_module, artifacts, opts)` | Emits Lua source with embedded stencils |
| `api.emit_module_artifact(module, opts)` | Lower + emit in one call |

### `lua/lalin/luajit_lower.lua` (2047 lines)
**Purpose**: Lowers `LalinCode` + kernel plans into `LalinLuaJIT` IR (a structured representation of LuaJIT bytecode-level operations).

**Key sub-pipelines**:
- `api.build_kernel(module, opts)` → runs all fact/plan phases and stencil machine generation
- `api.plan_stencil_machines(module, opts)` → generates per-function stencil machines
- `api.lower_module(module, opts)` → produces final `LJ.LJModule` with all functions lowered

**Key imports**: `luajit_lower_rules`, `stencil_rules`, `stencil_artifact_plan`, `luajit_ctype`, `luajit_expr`

### `lua/lalin/luajit_lower_rules.lua`
**Purpose**: Rule dispatch for LuaJIT lowering.

### `lua/lalin/luajit_emit.lua` (1019 lines)
**Purpose**: Emits Lua source code from `LalinLuaJIT` IR. Generates LuaJIT function definitions with FFI ctype declarations, value tracking, and stencil call integration.

**Key internal**: `emit_func`, `emit_expr`, `emit_inst`, `emit_block`, `compile_module`

### `lua/lalin/luajit_expr.lua`
**Purpose**: Expression utilities for LuaJIT emission — builds `LJExpr` values representing Lua expressions.

### `lua/lalin/luajit_ctype.lua`
**Purpose**: Converts `LalinCode.CodeType` to LuaJIT FFI ctype descriptors (`LJCType`). Handles scalars, pointers, structs, arrays, closures.

### `lua/lalin/luajit_measure.lua`
**Purpose**: Runtime measurement utilities for LuaJIT — type sizes, alignment, pointer bits.

### `lua/lalin/copy_patch_mc.lua` (660 lines)
**Purpose**: MC (machine code) stencil bank — the native code materialization path. Builds banks of compiled stencil blobs, installs them via `mmap` with executable permission, provides LuaJIT FFI call wrappers.

**Key functions** (per context):
- `api.build_mc_bank(artifacts, opts)` — compiles C stencil sources via TCC, produces MC blob bank
- `api.realize_mc_artifacts(artifacts, opts)` — loads and installs MC blobs, returns symbol table
- `api.emit_mc_bank_source(mc_bank, opts)` — emits Lua source that loads embedded MC bytes and calls into installed stencils
- Internal `mmap_install(bytes, opts)` — mmaps executable memory, copies stencil bytes, optionally makes RWX

### `lua/lalin/copy_patch_mc_intern_set.lua` (1073 lines)
**Purpose**: Intern set — a registry of reusable stencil instances keyed by canonical content hash. Ensures identical stencils produce one MC blob, deduplicates across compilation units.

### `lua/lalin/copy_patch_bc.lua` (~120 lines)
**Purpose**: BC (bytecode) bank platform — provides runtime target detection (`api.runtime_target()`), target matching, and BC bank identity.

### `lua/lalin/copy_patch_luatrace.lua` (1552 lines)
**Purpose**: LuaTrace/LuaJIT BC copy-patch artifact materialization. Generates LuaTrace trace-shaped stencil code that copies and patches LuaJIT bytecode.

**Key exports** (per context):
- `api.bc_artifact(artifact)` — wraps a stencil artifact as BC artifact
- `api.realize_bc_artifacts(artifacts, opts)` — materializes BC artifacts into a runtime bank
- `api.build_bc_bank(artifacts, opts)` — builds a BC stencil bank
- `api.emit_bc_bank_source(bc_bank, opts)` — emits Lua source for BC bank

---

## 7. C Backend (`lua/lalin/c_*.lua`)

### `lua/lalin/c_emit.lua` (810 lines)
**Purpose**: Emits C source text from `LalinC.BackendUnit`. Generates .c, .h, and combined artifact output. Handles type declarations, function definitions, helper functions, aggregate descriptors, view/slice/bytespan structs.

**Key exports** (per context):
- `api.emit_artifact(c_unit, opts)` → `{source, header, support, combined}`
- `emit_type(ty)` — emits C type name as string

### `lua/lalin/lower_to_c.lua` (1147 lines)
**Purpose**: Lowers `LalinCode` + lower plan to `LalinC` C backend IR. Translates code operations to C statements, handles helpers, aggregate decomposition.

**Key internal**: Walks each function's CFG via `LowerStrategyEmitRules` to emit C code per fragment strategy (code/kernel/closed-form).

### `lua/lalin/code_to_c.lua` (755 lines)
**Purpose**: Core type/shape mapping from `LalinCode` to `LalinC`. Type declarations, global declarations, data items.

### `lua/lalin/c_validate.lua`
**Purpose**: Validates `LalinC` IR invariants.

### `lua/lalin/c_helpers.lua`
**Purpose**: C helper function library — generates support functions for stencil operations in C.

### `lua/lalin/c_tcc.lua`
**Purpose**: libtcc (Tiny C Compiler) integration for JIT compilation of C code within the LuaJIT process.

### `lua/lalin/c_abi.lua`
**Purpose**: C ABI classification — determines how C types are passed/returned.

### `lua/lalin/c_coverage.lua`
**Purpose**: Coverage tracking — marks which C backend constructs are `phase_unreachable` (not yet implemented) for the C emission path.

---

## 8. Compiler Driver & Phases (`lua/lalin/compiler_driver.lua`, `phase_*.lua`)

### `lua/lalin/compiler_driver.lua`
**Purpose**: Public orchestration boundary. `M.lower_module(module, opts)` → gets compiler package → plans → executes → returns output.

**Flow**: `module` → `CompilerPackage(T)` → `PhasePlan.assert_plan(package, root)` → `PhaseExecute:run(plan, module, opts)` → `report.output`

### `lua/lalin/compiler_package.lua`
**Purpose**: Defines the compiler as a `LalinPhase` package with worlds, machines, phases, and roots.

**Declared roots**:
- `compile` — tree → c (emits C via hosted pipeline)
- `emit_c` — tree → c (same)

**Declared machines** (all hosted Lua):
- `hosted_typecheck` — tree → checked (using `compiler_machines.typecheck_module`)
- `hosted_checked_to_c_code` — checked → c_code (using `compiler_machines.checked_to_c_code`)
- `hosted_c_code_to_c` — c_code → c (using `compiler_machines.code_to_c`)

**Declared phases** (all `cache.full`, `deterministic`):
- `typecheck` — tree → checked
- `checked_to_c_code` — checked → c_code
- `c_code_to_c` — c_code → c

### `lua/lalin/compiler_machines.lua`
**Purpose**: Concrete machine implementations — the actual functions called by the phase executor.

| Machine | Function | What it does |
|---------|----------|-------------|
| `typecheck_module` | `M.typecheck_module(module, step, call)` | Runs `Pipeline.typecheck_module_process` |
| `checked_to_c_code` | `M.checked_to_c_code(checked, step, call)` | Runs `Pipeline.checked_to_code_process` with `root="emit_c"` |
| `code_to_c` | `M.code_to_c(code_result, step, call)` | Runs `Pipeline.code_to_c_process` |

### `lua/lalin/compiler_model.lua`
**Purpose**: Loads the full schema (all `Lalin*` types) into a context.

### `lua/lalin/compiler_abi.lua`
**Purpose**: CodeResult ABI validation — asserts code_result invariants before downstream processing.

### `lua/lalin/phase_model.lua`
**Purpose**: Loads the LalinPhase schema (world, machine, phase, root, etc.).

### `lua/lalin/phase_dsl.lua`
**Purpose**: LLBL dialect for authoring `LalinPhase` package graphs (worlds, machines, phases, roots).

### `lua/lalin/phase_plan.lua`
**Purpose**: Planner for the phase graph — given a package and root spec, finds a valid path through phases, validates, and produces a `Plan` with ordered steps.

**Key exports**: `M.plan(package, root_spec)`, `M.assert_plan(package, root_spec)`

### `lua/lalin/phase_execute.lua`
**Purpose**: Plan executor — runs each phase step in order, resolving machine implementations (lua/lalin/c/external), passing output as input to next step.

**Key exports**: `M.registry()`, `Executor:run(plan, input, opts)`, `M.execute(plan, input, executor, opts)`

### `lua/lalin/phase_validate.lua`
**Purpose**: Validates a LalinPhase package structure.

---

## 9. Schema/ASDL (`lua/lalin/schema/*.lua`)

### Schema files (each returns a `schema. Module { ... }`):

| File | Defines | Key types |
|------|---------|-----------|
| `core.lua` | **LalinCore** | `Name`, `Path`, `Id`, `Scalar*`, `Literal*`, `BinaryOp`, `CmpOp`, `CastOp`, `Intrinsic`, `AtomicOrdering` |
| `type.lua` | **LalinType** | `Type`, `TScalar`, `TPtr`, `TView`, `TSlice`, `TArray`, `TLease`, `TOwned`, `TAccess`, `THandle`, `TClosure`, `TNamed`, `TFunc`, `Param`, `FieldDecl`, `VariantDecl` |
| `bind.lua` | **LalinBind** | `Binding`, `ValueRef`, `ValueRefName`, `ValueRefPath`, `ValueRefBinding` |
| `sem.lua` | **LalinSem** | `FieldRef`, `FieldLayout`, `TypeLayout`, `LayoutEnv`, `ConstValue`, `ConstInt/ConstFloat/ConstBool/ConstAgg/ConstArray` |
| `tree.lua` | **LalinTree** | `Module`, `Expr*` (30+), `Stmt*` (20+), `Place*`, `BlockParam`, `BlockLabel`, `Func*`, `ConstItem`, `StaticItem`, `ImportItem`, `Region`, `ControlBlock`, `Switch*Arm`, `View*`, `Domain*`, `FuncContract*`, `RegionCont` |
| `code.lua` | **LalinCode** | `CodeModule`, `CodeFunc`, `CodeBlock`, `CodeInst`, `CodeTerm*`, `CodeType*`, `CodeConst*`, `CodeValue`, `CodeOp*`, `CodePlace*`, `CodeSig`, `CodeContract*` |
| `graph.lua` | **LalinGraph** | `Graph`, `GraphFunc`, `GraphEdge`, `GraphLoop`, `GraphBlock` |
| `flow.lua` | **LalinFlow** | `FlowDomain*`, `FlowTripCount`, `FlowEdgeFact`, `FlowLoopFact`, `FlowModuleFacts` |
| `value.lua` | **LalinValue** | `ValueExpr*`, `ClosedFormFact`, `ReductionFact`, `ReductionAdd/Mul/Etc`, `AlgebraProof`, `ValueModuleFacts` |
| `mem.lua` | **LalinMem** | `MemObject`, `MemAccess`, `MemInterval`, `MemAccessPattern`, `MemProof`, `MemModuleFacts` |
| `effect.lua` | **LalinEffect** | `OpEffect`, `EffectModuleFacts` |
| `kernel.lua` | **LalinKernel** | `KernelSubject`, `KernelDomain`, `KernelLane`, `KernelExpr`, `KernelEffect`, `KernelPlan`, `KernelReject`, `KernelProof`, `KernelModulePlan` |
| `stencil.lua` | **LalinStencil** | `StencilArtifact`, `StencilPlan`, `StencilVocab`, `StencilExpr*`, `StencilLayout*`, `StencilCopySemantics`, `StencilScatterSemantics`, `StencilModulePlan` |
| `schedule.lua` | **LalinSchedule** | `KernelSchedule`, `ScheduleKind*`, `ScheduleProof`, `ScheduleReject`, `ScheduleModulePlan` |
| `lower.lua` | **LalinLower** | `LowerFragment`, `LowerCover`, `LowerStrategy`, `LowerProof`, `LowerModulePlan` |
| `exec.lua` | **LalinExec** | `ExecFragment`, `ExecFragmentKind`, `ExecArg`, `ExecResult`, `ExecModulePlan` |
| `back.lua` | **LalinBack** | `BackTargetModel`, `BackFunc`, `BackBlock`, `BackInst*`, `BackVal`, `BackProgram` |
| `c.lua` | **LalinC** | `CBackendUnit`, `CBackendFunc`, `CBackendType*`, `CBackendStmt*`, `CBackendHelperUse` |
| `c_ast.lua` | **LalinCAst** | C AST node types |
| `luajit.lua` | **LalinLuaJIT** | `LJModule`, `LJFunc`, `LJBlock`, `LJExpr*`, `LJInst*`, `LJCType*`, `LJStencilMachine*` |
| `luatrace.lua` | **LalinLuaTrace** | LuaTrace trace descriptors, stencil tables, BC bank types |
| `compiler.lua` | **LalinCompiler** | `CodeResult`, `FlatlineImageIssue`, `ProjectReports` |
| `dasm.lua` | **LalinDasm** | Disassembly types |
| `link.lua` | **LalinLink** | Link plan and target model types |
| `phase.lua` | **LalinPhase** | `Package`, `World`, `Machine`, `Phase`, `Root`, `Plan`, `PlanStep` |
| `host.lua` | **LalinHost** | Host field representation, host ABI |
| `parse.lua` | **LalinParse** | Parse tree types |
| `source.lua` | **LalinSource** | Source location types |
| `mlua.lua` | **LalinMlua** | MLua documentation analysis |
| `project.lua` | **LalinProject** | Project structure |

---

## 10. Back Infrastructure (`lua/lalin/back_*.lua`)

| File | Purpose |
|------|---------|
| `back_program.lua` | Back IR program construction utilities |
| `back_inspect.lua` | Inspection/debug tools for back IR |
| `back_command_binary.lua` | Command-binary compilation (e.g., running TCC or external compiler) |
| `back_provenance.lua` | Provenance tracking for back IR values |
| `back_target_model.lua` | Target model — describes CPU features, ABI, supported capabilities |
| `back_validate.lua` | Back IR validation |

---

## 11. Key Data Flow — Concrete Example

How `lln.fn. add { a [lln.i32], b [lln.i32] } [lln.i32] { lln.ret (a + b) }` becomes an MC blob:

```
Lua source text  
  └─► LuaJIT evaluates: lln.fn.add{...} → returns a DSL Decl metatable
       └─► DSL grammar (LalinLLB dialect, g.head .fn) parses via LLBL
            └─► emit function produces Decl{kind="fn", name="add", ...}

lalin.compile("demo", { add })
  └─► emit_luajit_artifact(decl, opts) [init.lua]
       └─► module_ast = module_ast_from(decl, "demo")
            └─► dsl.to_unit("demo", decl) → Decl:syntax() → Tr.Module
       └─► Pipeline.typecheck_module(module_ast, opts)
            └─► SurfaceResolve → ClosureConvert → Typecheck.check_module
                 └─► returns checked (LalinTree.TypeModuleResult)
       └─► Pipeline.checked_to_code_result(checked, opts)
            └─► LayoutResolve → tree_to_code → CodeValidate
                 └─► returns CodeResult(code_module, contracts, layout_env)
       └─► Backend.lower_module(code_module, opts)
            └─► Lower.build_kernel(module, opts)
                 └─► graph → flow_facts → value_facts → mem_facts → effect_facts
                 └─► kernel_plan → schedule_plan → lower_plan
                 └─► StencilRules + StencilArtifactPlan produce artifacts
            └─► Lower.lower_module(module, facts) → LJModule
            └─► ExecPlan.plan(...) → ExecModulePlan
       └─► Backend.realize_artifacts(artifacts, opts)
            └─► API.build_mc_bank(artifacts, opts) [copy_patch_mc.lua]
                 └─► Compiles C stencil sources via TCC
                 └─► Produces MC blob bank with installed native code
            └─► or build_bc_bank for BC path
       └─► Emit.compile_module(lj_module, {stencil_symbols, native_residual="tcc"})
            └─► Emits Lua source with:
                 └─► Embedded MC stencil bytes (as Lua data)
                 └─► TCC residual glue: calls installed stencils via FFI
                 └─► Scalar function paths via LuaJIT bytecode
       └─► Result: {module, realization, source}

Final artifact file (demo.luajit.lua):
  -- MC stencil bytes embedded as string.char(...) literals
  -- TCC residual: FFI callbacks into mmap'd MC blobs
  -- Lua function `module.add(3, 4)` dispatches to scalar path or stencil
  Load via loadstring → chunk() → table with `add` function

For JIT runtime (compile path):
  loadstring(source) → chunk()
  chunk() → module table
  module.add(3, 4) → calls LuaJIT-compiled bytecode or native MC blob via FFI
```

**Two copy-patch materialization paths**:
- **MC path** (default): Native machine code stencils via TCC compilation, `mmap`-installed executable memory, FFI glue. Requires prebuilt or built-on-demand MCStencilBank.
- **BC path** (fallback `opts.copy_patch = "bc"`): LuaJIT bytecode stencil tables via LuaTrace, emitted as inline Lua data with BC copy-patch. No external compiler needed.
