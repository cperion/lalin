# Workflow 
**Workflow ID**: wf-lalin-target-arch
**Started**: 2026-07-07 07:58:36
---

## Scout Output — 2026-07-07 08:02:46

Now I have everything. Let me compile the full report.

---

## Files Retrieved

### Phase Definitions (worlds, machines, roots)
1. **`lua/lalin/schema/compiler.lua`** — Defines `LalinCompiler.CodeResult` (holds CodeModule + contracts + layout_env)
2. **`lua/lalin/schema/tree.lua`** (line 1153-1154) — Defines `LalinTree.TypeModuleResult` (Module + issues)
3. **`lua/lalin/compiler_package.lua`** — Defines 3 worlds (`tree`, `checked`, `c_code`, `c`), 3 machines, 3 phases, 2 roots (`compile`, `emit_c`)

### Main Orchestration
4. **`lua/lalin/frontend_pipeline.lua`** (lines 56-166) — `bind_context(T)` returns `typecheck_module`, `checked_to_code_result`, `code_result_to_c` — the hosted fast-path pipeline
5. **`lua/lalin/compiler_driver.lua`** — Public `M.lower_module(module, opts)` — entry point using PhasePlan + PhaseExecute
6. **`lua/lalin/compiler_machines.lua`** — 3 machine impls (`typecheck_module`, `checked_to_c_code`, `code_to_c`) — thin wrappers around the frontend_pipeline
7. **`lua/lalin/init.lua`** (lines 465-936) — Public-surface `compile`, `compile_c`, `compile_c_gcc`, `compile_luajit`, `emit_c` — composes pipeline

### Phase 1: Tree → Checked (Source → Typed)
8. **`lua/lalin/tree_typecheck.lua`** (lines 1910-1930) — `check_module(module, opts) → LalinTree.TypeModuleResult` — entry point for typechecking
9. **`lua/lalin/surface_resolve.lua`** — `SurfaceResolve.module(module)` — surface symbol resolution before typecheck
10. **`lua/lalin/closure_convert.lua`** — `ClosureConvert.module(surfaced)` — closure conversion before typecheck

### Phase 2: Checked → Code
11. **`lua/lalin/layout_resolve.lua`** — `Layout.module(checked_module, layout_env, target)` — layout resolution
12. **`lua/lalin/tree_lower.lua`** (last 60 lines) — `module_with_contracts(resolved, opts) → (LalinCode.CodeModule, contract_facts)` — tree→code lowering entry point
13. **`lua/lalin/code_validate.lua`** — `validate(code_module, collector)` — validates CodeModule

### Phase 3: Code → Graph
14. **`lua/lalin/code_graph.lua`** (last 15 lines) — `graph(code_module) → LalinGraph.CodeGraph` — builds CFG from CodeModule

### Phase 4: Code+Graph → Flow/Value/Mem/Effect
15. **`lua/lalin/code_flow_facts.lua`** (lines 426-480) — `facts(module, graph) → LalinFlow.FlowFactSet` — flow analysis (domains, edges, loops)
16. **`lua/lalin/code_value_facts.lua`** (last 15 lines) — `facts(module, graph, flow) → LalinValue.ValueFactSet` — value expression facts, reductions, closed forms
17. **`lua/lalin/code_mem_facts.lua`** (last 15 lines) — `semantic_facts(module, graph, flow, value, contracts) → LalinMem.MemSemanticFactSet` — memory access semantics
18. **`lua/lalin/code_effect_facts.lua`** (last 15 lines) — `facts(module, graph, mem, contracts) → LalinEffect.EffectFactSet` — effect tracking (stores, calls)

### Phase 5: Code+Graph+Facts → Kernels
19. **`lua/lalin/code_kernel_plan.lua`** (last 20 lines) — `plan(module, graph, flow, value, mem, effect) → LalinKernel.KernelModulePlan` — kernel identification and planning

### Phase 6: Kernels → Schedules
20. **`lua/lalin/code_schedule_plan.lua`** (last 20 lines) — `plan(module, kernels, flow, value, mem, effect, target) → LalinSchedule.ScheduleModulePlan` — schedule assignment for kernels

### Phase 7: Kernels+Schedules → Lower Plan
21. **`lua/lalin/code_lower_plan.lua`** (last 30 lines) — `plan(code_module, graph, kernels, schedules, target) → LalinLower.LowerModule` — lower plan with fragments, carrier plans, address plans

### Phase 8: Code+Lower → C Backend
22. **`lua/lalin/lower_to_c.lua`** (lines 2333-2411) — `module(code_module, lower_module, opts) → LalinC.CBackendUnit` — transforms Code + Lower plan into C backend blocks, then rewrites semantic fragments
23. **`lua/lalin/code_to_c.lua`** (lines 1284-1360) — `module(code_module, opts) → LalinC.CBackendUnit` — lower-level: Code→C type/func/data/global/extern emission
24. **`lua/lalin/lower_kernel_rewrite.lua`** (line 53) — `KernelRewrite.apply(kplan, fragment, graph, flow, c_emission)` — kernel rewrite application (closed form, reduce, memcpy, scan, find)

### Phase 9: C Backend → C Emit
25. **`lua/lalin/emit_c_lower.lua`** (lines 1404-1411) — `emit_artifact(unit, opts) → {unit, source, header, support, combined}` — CBackendUnit → C text strings
26. **`lua/lalin/emit_c_validate.lua`** — validates CBackendUnit before emission

### Phase 10: C → Exec (JIT-like path)
27. **`lua/lalin/exec_plan.lua`** (lines 195-219) — `plan(module, opts) → LalinExec.ExecModulePlan` — exec plan with stencil decisions
28. **`lua/lalin/emit_c_compile.lua`** — GCC compilation of emitted C into shared object

### LuaJIT Backend Path
29. **`lua/lalin/luajit_backend.lua`** (lines 98-164) — `lower_module(module, opts)` — full LuaJIT lowering: build_kernel → stencil_machines → lj_module
30. **`lua/lalin/luajit_lower.lua`** (lines 2075-2104) — `build_kernel(module, opts)` and `lower_module(module, opts)` — code→LJ facts→LJModule

### Native Backend Path
31. **`lua/lalin/native_backend.lua`** — `compile_subject`, `code_module_subject` — native copy-patch backend

---

## Key Code — Complete Phase Map

### The Canonical Pipeline (from `frontend_pipeline.lua`)

```
Tree (LalinTree.Module)
  │
  ├─[typecheck_module]── SurfaceResolve.module → ClosureConvert.module → Typecheck.check_module
  │   IN:  LalinTree.Module
  │   OUT: LalinTree.TypeModuleResult { module, issues }
  │
  ├─[checked_to_code_result]── Layout.module → TreeToCode.module_with_contracts → CodeValidate.validate
  │   IN:  LalinTree.TypeModuleResult
  │   OUT: LalinCompiler.CodeResult { module(LalinCode.CodeModule), contracts, layout_env }
  │
  └─[code_result_to_c]
       IN:  LalinCompiler.CodeResult
       │
       ├── CodeGraph.graph(code_module) → LalinGraph.CodeGraph { id, funcs[] }
       ├── CodeFlowFacts.facts(module, graph) → LalinFlow.FlowFactSet { id, domains[], edge_facts[], loops[], ... }
       ├── CodeFlowFacts.semantic_facts(...) → LalinFlow.FlowSemanticFactSet
       ├── CodeValueFacts.facts(module, graph, flow) → LalinValue.ValueFactSet { id, values[], reductions[], closed_forms[] }
       ├── CodeMemFacts.semantic_facts(module, graph, flow, value, contracts) → LalinMem.MemSemanticFactSet { id, accesses[], dependences[], proofs[] }
       ├── CodeMemFacts.facts(...) → LalinMem.MemFactSet
       ├── CodeEffectFacts.facts(module, graph, mem, contracts) → LalinEffect.EffectFactSet { id, calls[], insts[] }
       ├── CodeKernelPlan.plan(module, graph, flow, value, mem, effect) → LalinKernel.KernelModulePlan { id, flow, value, mem, effect, plans[] }
       ├── CodeSchedulePlan.plan(module, kernels, flow, value, mem, effect, target) → LalinSchedule.ScheduleModulePlan { id, target, schedules[] }
       ├── CodeLowerPlan.plan(module, graph, kernels, schedules, LowerTargetC) → LalinLower.LowerModule { id, target, kernels, schedules, carriers[], addresses[], funcs[], issues[] }
       ├── KernelValidate.validate(...) → report
       ├── LowerToC.module(code_module, lower_module, opts) → LalinC.CBackendUnit { module_name, target, sigs[], types[], globals[], externs[], helpers[], funcs[] }
       │    │
       │    ├── CodeToC.module(code_module, opts) → CBackendUnit (baseline blocks for every func)
       │    └── lower_semantic_func(...) → CBackendFunc (semantic fragment → kernel rewrite → replacement blocks)
       │
       └── CValidate.validate(c_unit, collector) → report
            OUT: { c_unit, c_report }
```

### Receiver + Input → Output signatures per phase boundary

| # | Boundary | Function | IN (receiver + params) | OUT |
|---|----------|----------|------------------------|-----|
| 1a | Source→Surfaced | `SurfaceResolve.module` | `LalinTree.Module` | `LalinTree.Module` (surface-resolved) |
| 1b | Surfaced→Closed | `ClosureConvert.module` | `LalinTree.Module` | `LalinTree.Module` (closure-converted) |
| 1c | Closed→Checked | `Typecheck.check_module` | `LalinTree.Module` + `opts{layout_env, target}` | `LalinTree.TypeModuleResult { module, issues }` |
| 2 | Checked→Layouted | `Layout.module` | `LalinTree.TypeModuleResult.module` + `layout_env` + `target` | `LalinTree.Module` (layout-resolved) |
| 3 | Layouted→Code | `TreeToCode.module_with_contracts` | layout-resolved `LalinTree.Module` + `{layout_env, target}` | `(LalinCode.CodeModule, contract_facts[])` |
| 4 | Code→Graph | `CodeGraph.graph` | `LalinCode.CodeModule` | `LalinGraph.CodeGraph { id, funcs[{func, blocks[], edges[], loops[]}] }` |
| 5 | Code+Graph→FlowFacts | `CodeFlowFacts.facts` | `(CodeModule, CodeGraph)` | `LalinFlow.FlowFactSet { id, domains[], edge_facts[], loops[], ranges[], domain_shapes[], domain_intents[], reject[] }` |
| 6 | Code+Graph+Flow→ValueFacts | `CodeValueFacts.facts` | `(CodeModule, CodeGraph, FlowFactSet)` | `LalinValue.ValueFactSet { id, values[], reductions[], closed_forms[] }` |
| 7 | Code+Graph+Flow+Value→MemSemantics | `CodeMemFacts.semantic_facts` | `(CodeModule, CodeGraph, FlowFactSet, ValueFactSet, contracts)` | `LalinMem.MemSemanticFactSet { id, accesses[], dependences[], proofs[] }` |
| 8 | Code+Graph+Mem→EffectFacts | `CodeEffectFacts.facts` | `(CodeModule, CodeGraph, MemSemanticFactSet, contracts)` | `LalinEffect.EffectFactSet { id, calls[], insts[] }` |
| 9 | Facts→Kernels | `CodeKernelPlan.plan` | `(CodeModule, CodeGraph, FlowFactSet, ValueFactSet, MemSemanticFactSet, EffectFactSet)` | `LalinKernel.KernelModulePlan { id, flow, value, mem, effect, plans[{KernelPlanned|KernelNoPlan}] }` |
| 10 | Kernels→Schedules | `CodeSchedulePlan.plan` | `(CodeModule, KernelModulePlan, FlowFactSet, ValueFactSet, MemSemanticFactSet, EffectFactSet, target)` | `LalinSchedule.ScheduleModulePlan { id, target, schedules[{SchedulePlanned}] }` |
| 11 | Kernels+Schedules→LowerPlan | `CodeLowerPlan.plan` | `(CodeModule, CodeGraph, KernelModulePlan, ScheduleModulePlan, LowerTarget)` | `LalinLower.LowerModule { id, target, kernels, schedules, carriers[], addresses[], funcs[{fragments[]}], issues[] }` |
| 12 | Code+Lower→CBackendUnit | `LowerToC.module` | `(CodeModule, LowerModule, opts)` | `LalinC.CBackendUnit { module_name, target, sigs[], types[], globals[], externs[], helpers[], funcs[] }` |
| 13 | CBackendUnit→C text | `EmitCEmit.emit_artifact` | `(CBackendUnit, opts)` | `{ unit, source, header, support, combined }` (plain strings) |
| 14 | CBackendUnit→ExecPlan | `ExecPlan.plan` | `(CodeModule, {graph, flow, value, mem, effect, kernels, stencil, artifacts})` | `LalinExec.ExecModulePlan { id, stencil, entries[], funcs[] }` |

### LuaJIT Path (alternative branch at phases 5-8)

```
CodeModule
  │
  ├── LuajitLower.build_kernel(module) → (graph, flow, value, mem, effect, kernel)
  ├── LuajitLower.plan_stencil_machines(module, {...}) → { machines_by_func, machine_plans[], rejects[] }
  └── LuajitLower.lower_module(module, {...}) → LalinLuaJIT.LJModule { id, funcs[], lj_sig_order[], lj_cdef_order[], data[] }
```

---

## Relationships

### Data flow is linear + fan-in

The pipeline is a **strictly ordered sequence** of 14 phases where each phase produces facts that all subsequent phases can consume:

1. **Frontend phases** (1-3): transform `LalinTree.Module` through surface resolution, closure conversion, typechecking, layout resolution, and tree lowering into `LalinCode.CodeModule` — the central IR.

2. **Analysis phases** (4-8): analyze `CodeModule` into four parallel fact sets (`CodeGraph`, `FlowFactSet`, `ValueFactSet`, `MemSemanticFactSet`, `EffectFactSet`). These are **independent analyses** that could run in parallel.

3. **Planning phases** (9-11): consume all facts to produce plans (`KernelModulePlan`, `ScheduleModulePlan`, `LowerModule`). `LowerModule` includes **carrier plans** (loop-carried values plan) and **address plans** (loop-carried addresses plan).

4. **Backend phases** (12-14): `LowerToC.module` takes `CodeModule` + `LowerModule` and:
   - First delegates to `CodeToC.module` for baseline C emission (all non-semantic fragments)
   - Then calls `lower_semantic_func` for each semantic fragment, applying kernel rewrites (`lower_kernel_rewrite.lua`)
   - Merges baseline + rewritten blocks into final `CBackendUnit`

5. **Emission phases**: `EmitCEmit.emit_artifact` linearizes `CBackendUnit` into C strings. `emit_c_compile.lua` shells out to GCC.

### Key design patterns

- **Context passing via `bind_context(T)`**: Every phase module is a closure factory `bind_context(T)` where `T` is the schema context. The module returns an API table. The `__call` metamethod regenerates the context. This is the Terra ASDL pattern.

- **Fact sets are immutable ASDL products**: Once produced, fact sets are never mutated — later phases produce new ASDL products (kernel plans, schedules, lower plans, C units).

- **Semantic vs. code fragments**: `LowerFragment` carries a `LowerStrategy` — either `LowerStrategyCode` (emit as C directly) or `LowerStrategyKernel` (apply kernel rewrite first). Semantic fragments are rewrites applied by `lower_kernel_rewrite.lua`.

- **Carrier/address plans**: Loop-carried values (induction variables, addresses) get their own plan type (`LowerCarrierPlan`, `LowerAddressPlan`) carried through the lower module.

- **Stencil machines** (LuaJIT path only): The LuaJIT backend adds a stencil machine planning step (`plan_stencil_machines`) that selects stencil implementations (reduce, store, skeleton) for each kernel. The C path does not use stencil machines — it applies kernel rewrites directly.

### Two backends, one frontend

Both C and LuaJIT backends share phases 1-8 (through kernel plan). They diverge at phase 9:

- **C path**: `CodeLowerPlan.plan(..., LowerTargetC)` → `LowerToC.module` → `CBackendUnit` → `emit_c_artifact` → GCC
- **LuaJIT path**: `LuajitLower.build_kernel` → stencil machines → `LuajitLower.lower_module` → `LJModule` → `emit_lua_artifact` → LuaJIT loadstring

### Native backend path (experimental)

The native backend (`native_backend.lua`, `native_mc.lua`, `native_template_sources.lua`) is a separate path with its own build_kernel / stencil planning / template graph / bank selection pipeline. It is marked as experimental in AGENTS.md.

---

## Observations

1. **The `lower_to_c.lua` module function has a dual role**: it can accept either a `LowerModule` directly or nothing (in which case it reconstructs all facts from scratch via `normalize_args`). This makes it usable both as a downstream consumer of the canonical pipeline and as a standalone entry point.

2. **`code_to_c.lua` vs `lower_to_c.lua`**: `code_to_c.lua` produces baseline C blocks from `CodeModule` alone. `lower_to_c.lua` wraps it, then applies semantic fragment rewrites using `LowerModule` information. The separation is clean: `code_to_c` is the "just emit" path; `lower_to_c` is the "plan + emit + rewrite" path.

3. **Carrier plans are computed twice**: `code_kernel_plan.lua` computes `address_threads` (carriers and addresses), and `code_lower_plan.lua` recomputes `carrier_and_address_plans`. The kernel module plan includes the flow with addresses baked in; the lower plan produces separate `LowerCarrierPlan` and `LowerAddressPlan` entries.

4. **Kernel plan includes flow facts**: `KernelModulePlan` holds `flow`, `value`, `mem`, `effect` — not just `plans`. This means later phases that only have a `LowerModule` can still extract all fact sets through `lower_module.kernels.flow`, etc.

5. **Stencil artifacts are only used in the LuaJIT path**: The `stencil_artifact_plan.lua` and `stencil_c.lua` files exist but the C path in `lower_to_c.lua` applies kernel rewrites directly without going through stencil artifacts. The stencil system seems oriented toward the LuaJIT bytecode emission, not the C backend.

6. **The `LalinCEmit.CEmitMachine`** serves as a type projection context — it maps `CodeType` → `CBackendType` and accumulates helper functions. It is created via `CEmitMachine.empty(spine)` where spine is a `LowerBackSpine`.

7. **Validation phases exist between transitions**: `CodeValidate.validate` after code lowering, `KernelValidate.validate` after kernel/schedule/lower planning, `CValidate.validate` after C backend unit production. These are assertion gates.

8. **Three public entry paths into the pipeline**: 
   - `init.lua` `compile_c_gcc` / `emit_c` → full pipeline culminating in GCC compilation
   - `init.lua` `compile_luajit` → full pipeline through LuaJIT backend
   - `compiler_driver.lua` `lower_module` → uses the phase plan system (PhasePlan + PhaseExecute) with the `lalin.compiler` package
