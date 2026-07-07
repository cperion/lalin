# MASTER PLAN — Lalin Compiler Implementation Migration

**All three agents receive this document.** Read it completely before writing code.
Sections 1-5 are shared. Section 6 is the full inventory. Sections 7-9 are agent-specific.

---

## 1. WHAT WE ARE BUILDING

```
lua/lalin/
  schema_v2/    ← PURE ASDL type definitions (ALREADY DONE — 28 files)
  impl/         ← Method installation ONLY (33 files to write)
  pipeline.lua  ← Thin composition (~30 lines)
  compile.lua   ← Public API entry point
```

**schema_v2/** defines ASDL types: products, sums, constructors. Each file like `schema_v2/tree.lua` exports a Lua table containing types like `Tree.ExprCall`, `Tree.StmtLet`, `Tree.Module`.

**impl/** installs Lua methods on those types. Each file does ONE thing: `require` schema_v2, then write `function ConcreteLeaf:method_name(input) → output`.

**pipeline.lua** chains the methods together into the full compilation sequence.

**compile.lua** is the public API entry point.

---

## 2. THE ASDL PATTERN — HOW SCHEMA AND IMPL CONNECT

### How schema_v2 files work

```lua
-- schema_v2/tree.lua
return schema. LalinTree {
  sum. Expr {
    ExprLit    { value [LalinCore.Literal] },
    ExprCall   { callee [LalinTree.Expr], args [many LalinTree.Expr] },
    ExprBinary { op [LalinCore.BinaryOp], lhs [LalinTree.Expr], rhs [LalinTree.Expr] },
    ...
  },
  sum. Stmt { ... },
  ...
}
```

This returns a Lua table. When you do `local Tree = require("lalin.schema_v2.tree")`, you get that table directly. **No factory function. No `(T)` parameter. No schema table to pass around.** Just `require` and use.

```lua
local Tree = require("lalin.schema_v2.tree")
-- Tree.ExprCall is the class
-- Tree.ExprLit is a class
-- Tree.Module is a class
-- Every ASDL type is a direct Lua value in the table
```

### How impl files work

```lua
-- impl/tree_code.lua
local Tree     = require("lalin.schema_v2.tree")
local Code     = require("lalin.schema_v2.code")
local TreeCode = require("lalin.schema_v2.tree_code")

-- Install methods on concrete union leaves:
function Tree.ExprLit:lower_expr_to_code(lctx)
  -- self is the ExprLit instance
  -- self.value is the literal
  return lctx.builder:const(self.value)
end

function Tree.ExprCall:lower_expr_to_code(lctx)
  -- self is the ExprCall instance
  -- self.callee and self.args are the children
  local callee = self.callee:lower_expr_to_code(lctx)
  -- ...
end

function Tree.Module:lower_to_code(input)
  -- Orchestrator: walks items, calls methods on each
  for _, item in ipairs(self.items) do
    item:lower_item_to_code(lctx)
  end
end
```

**That's it.** `require` schema_v2 types → install methods. No dispatch. No handler maps. No classof. No `(T)`.

### How the old code used to work (DO NOT COPY THIS)

```lua
-- OLD PATTERN — DO NOT USE
local OldModule = require("lalin.tree_lower")
local Types = OldModule(T)   -- factory call with schema table
-- then use Types.some_function(...)
```

This is WRONG for impl/ files. The old code used a factory pattern where modules returned functions that took a schema table. Schema_v2 eliminates this. Types are loaded directly via `require`.

### VERIFIED WORKING EXAMPLE — this is in your codebase RIGHT NOW

Open `lua/lalin/impl/code_graph.lua`. This file was written by Agent B and WORKS. Study it.

```lua
-- impl/code_graph.lua
local Code  = require("lalin.schema_v2.code")
local Graph = require("lalin.schema_v2.graph")

-- Parent union method — shared default for all leaves:
function Code.CodeInstOp:code_graph_dst()
  return rawget(self, "dst")
end

-- Concrete leaf methods — each leaf gets its own method:
function Code.CodeInstBinary:code_graph_append_uses(uses, ref)
  add_use(uses, self.lhs, ref, nil, "binary.lhs")
  add_use(uses, self.rhs, ref, nil, "binary.rhs")
end

function Code.CodeInstUnary:code_graph_append_uses(uses, ref)
  add_use(uses, self.value, ref, nil, "unary.value")
end

function Code.CodeInstCall:code_graph_append_uses(uses, ref)
  self.target:code_graph_append_uses(uses, ref, "call")
  for i, arg in ipairs(self.args or {}) do
    add_use(uses, arg, ref, nil, "call.arg" .. tostring(i))
  end
end

-- Entry point:
function Code.CodeModule:build_graph()
  local funcs = {}
  for i, func in ipairs(self.funcs or {}) do
    funcs[i] = func:build_func_graph()
  end
  return Graph.CodeGraph(self.id, funcs)
end
```

**Key observations:**
- `require("lalin.schema_v2.code")` returns a table. `Code.CodeInstBinary` is a concrete leaf class. You install methods on it.
- Parent union method (`Code.CodeInstOp:code_graph_dst`) is a SHARED DEFAULT. Leaves that need different behavior override it.
- Self refers to the ASDL instance. `self.lhs`, `self.rhs`, `self.args` are the ASDL fields.
- `self.target:code_graph_append_uses(...)` — the method CALLS ITSELF RECURSIVELY on child nodes. This is how you walk the ASDL tree.
- No classof. No handler maps. No (T). No old requires.

**Another working example:** `lua/lalin/impl/stencil_reduction.lua` — Agent C
```lua
local Value = require("lalin.schema_v2.value")

function Value.ReductionAdd:display_name() return "add" end
function Value.ReductionMul:display_name() return "mul" end
function Value.ReductionMin:display_name() return "min" end
```

**You must write ALL your files following this exact pattern.**

---

1. **`docs/FILE_ORGANIZATION.md`** — master architectural document (1166 lines). Read §1-3 completely. Read §15 (old file mapping) for your section.
2. **`docs/ASDL_GUIDE.md`** — ASDL doctrine. Leaf methods ARE dispatch. No classof. No side tables.
3. **`TARGET-SCHEMA.md`** — target architecture for schema_v2. Know what types exist.
4. **`AUDIT-REPORT.md`** — known defects in schema_v2. Know what's been fixed.
5. **`lua/lalin/schema_v2/` — READ THE ACTUAL FILES.** Open the schema files for the types you'll install methods on. Know the exact type names. Don't guess.

---

## 4. FORBIDDEN — ANY OF THESE = FAILURE

```lua
-- ❌ Requiring old implementation files with (T)
local old = require("lalin.tree_lower")(T)

-- ❌ classof dispatch
if asdl.classof(expr) == Tree.ExprCall then ... end

-- ❌ Handler maps
local handlers = { ExprCall = f1, ExprLit = f2 }

-- ❌ Side tables / caches
local cache = {}; cache[node] = value

-- ❌ Wrappers or shims that delegate to old code
function Tree.ExprCall:lower_expr_to_code(lctx)
  return OldModule.lower_expr(self, lctx)  -- NO
end

-- ❌ Trying to make the file "runnable" with test harnesses
-- Impl files install methods. They are NOT standalone programs.

-- ❌ kind-string dispatch
if expr.kind == "ExprCall" then ... end

-- ❌ Passing schema tables as (T) parameters
-- Schema_v2 types are loaded once via require. No T parameter anywhere.
```

**The only check:** `luajit -e "require('lalin.impl.xxx')"` must not error. That's it.

---

## 5. HOW TO WRITE AN IMPL FILE (THE PATTERN)

```
For each impl file:
  1. Read the OLD source file(s) for LOGIC. Understand what each function computes.
  2. Read the schema_v2 file(s) for TYPE NAMES. Know the exact union leaves.
  3. Write impl/xxx.lua:
     a. require("lalin.schema_v2.xxx") for each schema module used
     b. For each piece of logic: identify the ASDL type that RECEIVES the method
     c. Write: function ConcreteLeaf:method_name(params) ... end
     d. If old code uses classof on type X vs Y: write a SEPARATE method on each leaf
  4. Verify: luajit -e "require('lalin.impl.xxx')" does not error
  5. Commit: git add && git commit -m "impl: <file>"
```

---

## 6. FULL INVENTORY — ALL SCHEMA FILES + ALL IMPL FILES

### schema_v2/ (28 files — ALREADY DONE, READ-ONLY)

```
schema_v2/core.lua              LalinCore      — Name, Scalar, Literal, UnaryOp, BinaryOp, CmpOp, Symbol
schema_v2/parse.lua             LalinParse     — ParseIssue, ParseResult
schema_v2/source.lua            LalinSource    — DocumentUri, Anchor, SourceRange
schema_v2/type.lua              LalinType      — Type, TypeShape, TypeRef, AbiClass, AbiRejectReason
schema_v2/c.lua                 LalinC         — CTypeShape, CBackendUnit, CEmitFragment
schema_v2/bind.lua              LalinBind      — Binding, BindingRole, ValueRef, Env
schema_v2/sem.lua               LalinSem       — FieldRef, MemLayout, ConstValue, FuncContractFact, ClosureEnvShape
schema_v2/tree.lua              LalinTree      — Expr, Stmt, Func, Item, Module, Place, View, Region, BlockLabel
schema_v2/check.lua             LalinCheck     — TypeExprInput/Result, TypeIssue, TypeValueScope, TypeModuleFacts
schema_v2/tree_code.lua         LalinTreeCode  — TreeCodeLowerContext, TreeCodeModuleResult
schema_v2/code.lua              LalinCode      — CodeFunc, CodeBlock, CodeInst, CodeTerm, CodePlace, CodeValueId, CodeConst, CodeType
schema_v2/graph.lua             LalinGraph     — CodeGraph, GraphNode, EdgeKind, UseRole, UseInfo
schema_v2/flow.lua              LalinFlow      — FlowFactSet, FlowLoop, FlowTripCount, FlowCarrier, FlowProof
schema_v2/value.lua             LalinValue     — ValueFactSet, ValueExpr, AffineExpr, Reduction, AlgebraProof
schema_v2/mem.lua               LalinMem       — MemSemanticFactSet, MemObject, MemAccess, MemProof, MemBase, MemBounds
schema_v2/effect.lua            LalinEffect    — EffectFactSet, OpEffect, CallSummary, EffectAtomic
schema_v2/kernel.lua            LalinKernel    — KernelModulePlan, KernelSubject, KernelSkeleton, KernelRewrite, KernelResult
schema_v2/stencil.lua           LalinStencil   — StencilProducer, StencilAccess, StencilDescriptor, StencilSchedule, StencilFusion
schema_v2/stencil_machine.lua   LalinStencilMachine — StencilMachinePointInput, StencilMachineKernelInput, FindNotFoundSentinel
schema_v2/lower.lua             LalinLower     — LowerModule, LowerFragment, LowerStrategy, LowerIssueGap, LowerFallbackKind
schema_v2/schedule.lua          LalinSchedule  — ScheduleModulePlan, ScheduleForm, ScheduleEmitterKind, ScheduleEmitterStatus
schema_v2/backend.lua           LalinBackend   — BackScalar, BackVec, BackFeature, BackTarget, BackProgram
schema_v2/cemit.lua             LalinCEmit     — CEmitMachine, CEmitArtifact, CEmitCSigEntry
schema_v2/compiler.lua          LalinCompiler  — CodeResult, CompileReport
schema_v2/code_validation.lua   LalinCodeValidation — CodeValidationMachine, CodeValidateResult
schema_v2/exec.lua              LalinExec      — ExecPlan, ExecFragment, ExecStencilSelection
schema_v2/phase.lua             LalinPhase     — WorldType (was TypeRef), World, Phase
schema_v2/project.lua           LalinProject   — Task tracking types
```

### impl/ files (33 to write)

| # | File | Agent | Old source files for LOGIC |
|---|------|-------|---------------------------|
| 1 | `impl/tree_surface.lua` | A | `surface_resolve.lua` |
| 2 | `impl/tree_closure.lua` | A | `closure_convert.lua` |
| 3 | `impl/tree_check/init.lua` | A | (sub-folder loader) |
| 4 | `impl/tree_check/type.lua` | A | `tree_typecheck_type.lua` + `core_scalar.lua` + `type_classify.lua` + `type_abi_classify.lua` |
| 5 | `impl/tree_check/expr.lua` | A | `tree_typecheck_expr.lua` + `core_operator.lua` |
| 6 | `impl/tree_check/stmt.lua` | A | `tree_typecheck_stmt.lua` |
| 7 | `impl/tree_check/scope.lua` | A | `tree_typecheck_fact.lua` |
| 8 | `impl/tree_check/layout.lua` | A | `tree_typecheck_layout.lua` |
| 9 | `impl/tree_check/control.lua` | A | `tree_control_facts.lua` (HEAVY classof refactor) |
| 10 | `impl/tree_check/contract.lua` | A | `tree_contract_facts.lua` (classof refactor) |
| 11 | `impl/tree_check/const.lua` | A | `const_eval.lua` |
| 12 | `impl/tree_check/module.lua` | A | `tree_module_type.lua` |
| 13 | `impl/tree_code.lua` | A | `tree_lower.lua` + `layout_resolve.lua` |
| 14 | `impl/code_validate.lua` | A | `code_validate.lua` |
| 15 | `impl/compiler_result.lua` | A | `compiler_abi.lua` |
| 16 | `impl/code_graph.lua` | B | `code_graph.lua` |
| 17 | `impl/code_flow.lua` | B | `code_flow_facts.lua` |
| 18 | `impl/code_value.lua` | B | `code_value_facts.lua` + `reduction_algebra.lua` |
| 19 | `impl/code_mem.lua` | B | `code_mem_facts.lua` |
| 20 | `impl/code_effect.lua` | B | `code_effect_facts.lua` (classof refactor) |
| 21 | `impl/kernel_plan.lua` | B | `code_kernel_plan.lua` + `kernel_validate.lua` + `kernel_emit_support.lua` (classof refactor) |
| 22 | `impl/schedule_plan.lua` | B | `code_schedule_plan.lua` |
| 23 | `impl/lower_plan.lua` | B | `code_lower_plan.lua` |
| 24 | `impl/lower_emit_c/init.lua` | C | (sub-folder loader) |
| 25 | `impl/lower_emit_c/schedule_form.lua` | C | `lower_to_c.lua` + `stencil_artifact_plan.lua` (Code.* methods) |
| 26 | `impl/lower_emit_c/code_to_c.lua` | C | `code_to_c.lua` |
| 27 | `impl/lower_emit_c/materialize.lua` | C | `emit_c_materialize.lua` |
| 28 | `impl/lower_emit_c/validate.lua` | C | `emit_c_validate.lua` |
| 29 | `impl/cemit_emit.lua` | C | `emit_c_lower.lua` |
| 30 | `impl/stencil_plan.lua` | C | `stencil_artifact_plan.lua` (Stencil.* methods) + `stencil_methods.lua` |
| 31 | `impl/stencil_reduction.lua` | C | `stencil_artifact_plan.lua` (Reduction methods) + `lower_kernel_rewrite.lua` |
| 32 | `impl/stencil_machine.lua` | C | `stencil_methods.lua` (StencilMachine.* methods) |
| 33 | `impl/stencil_metastencil.lua` | C | `stencil_metastencil.lua` |
| 34 | `impl/stencil_c.lua` | C | `stencil_c.lua` |
| 35 | `impl/exec_plan.lua` | C | `exec_plan.lua` |
| 36 | `pipeline.lua` | C | `frontend_pipeline.lua` (composition only — new code) |
| 37 | `compile.lua` | C | (new code — public API entry point) |

### Files to DELETE after migration

- `core_scalar.lua` — methods moved to leaf methods on Core.Scalar
- `core_operator.lua` — methods moved to leaf methods on Core.BinaryOp/UnaryOp/CmpOp
- `type_classify.lua` — methods moved to leaf methods on Type.Type
- `type_abi_classify.lua` — methods moved to leaf methods on Type.Type
- `frontend_pipeline.lua` — replaced by `pipeline.lua`

### Files KEPT as-is (infrastructure, runtime, utilities)

These files are NOT migrated. They are infrastructure, kept as-is:
- `emit_c_compile.lua`, `emit_c_tcc.lua`, `emit_c_coverage.lua` — GCC/TCC runners
- `triplet.lua` — architecture tuple database
- `code_type.lua`, `type_size_align.lua`, `func_abi_plan.lua`, `code_aggregate_abi.lua` — utilities
- `value_proxy.lua`, `quote.lua` — utilities
- All `phase_*.lua`, `link_*.lua`, `compiler_*.lua` — framework
- `schema_context.lua`, `schema_*.lua`, `asdl.lua`, `context_define_schema.lua` — infrastructure
- `ast.lua`, `loader.lua`, `store.lua`, `exotype.lua` — infrastructure
- `cli.lua` — CLI entry point
- `source_*.lua`, `project_*.lua`, `bind_*.lua`, `backend_target_model.lua` — utilities
- `init.lua` — public API facade (kept; `compile.lua` provides new typed entry)
- `dsl/` — builder API (kept)

---

## 7. AGENT A — TREE PHASES (files 1-15)

### Schema modules you work with
`core`, `type`, `bind`, `sem`, `tree`, `check`, `tree_code`, `code`, `code_validation`, `compiler`

### File 1: `impl/tree_code.lua` (START HERE)

Read: `lua/lalin/tree_lower.lua` (3067 lines), `layout_resolve.lua` (678 lines)

Install methods:
```lua
local Tree     = require("lalin.schema_v2.tree")
local Code     = require("lalin.schema_v2.code")
local TreeCode = require("lalin.schema_v2.tree_code")
local Core     = require("lalin.schema_v2.core")
local Sem      = require("lalin.schema_v2.sem")

-- Entry point
function Tree.Module:lower_to_code(input) → TreeCode.TreeCodeModuleResult end

-- On every Tree.Expr leaf:
function Tree.ExprLit:lower_expr_to_code(lctx) → Code.CodeValueId end
function Tree.ExprCall:lower_expr_to_code(lctx) → Code.CodeValueId end
function Tree.ExprBinary:lower_expr_to_code(lctx) → Code.CodeValueId end
-- ... every Expr leaf (~30)

-- On every Tree.Stmt leaf:
function Tree.StmtLet:lower_stmt_to_code(lctx) → TreeCode.TreeCodeStmtResult end
function Tree.StmtIf:lower_stmt_to_code(lctx) → TreeCode.TreeCodeStmtResult end
-- ... every Stmt leaf

-- On every Tree.Func leaf:
function Tree.FuncLocal:lower_func_to_code(lctx) → Code.CodeFunc end

-- On every Tree.Place leaf:
function Tree.PlaceVar:lower_place_to_code(lctx) → Code.CodePlace end

-- Layout resolution (from layout_resolve.lua — refactor classof):
function Tree.ExprField:sem_layout_resolve(lctx) → Sem.LayoutResolveResult end
function Tree.StmtLet:sem_layout_resolve(lctx) → Sem.LayoutResolveResult end
-- ... every Expr/Stmt/Place leaf that needs layout

-- CodeType methods installed during lowering:
function Code.CodeType:tree_code_is_float_type() → bool end
function Code.CodeType:tree_code_is_aggregate_type() → bool end
function Code.CodeType:tree_code_is_view_type() → bool end

-- Scalar to CodeType:
function Core.ScalarI8:tree_code_scalar_to_code_type() → Code.CodeType end
-- ... every scalar leaf
```

### File 2: `impl/tree_check/type.lua`

Read: `tree_typecheck_type.lua`, `core_scalar.lua`, `type_classify.lua`, `type_abi_classify.lua`

Install methods on Core.Scalar and Type.Type leaves. Every function from the 4 old files becomes a leaf method.

### Files 3-6: `impl/tree_check/scope.lua`, `layout.lua`, `expr.lua`, `stmt.lua`

Read: `tree_typecheck_fact.lua`, `tree_typecheck_layout.lua`, `tree_typecheck_expr.lua`, `tree_typecheck_stmt.lua`

Port clean leaf methods. For expr/stmt with classof: replace with leaf methods.

### Files 7-8: `impl/tree_check/control.lua`, `contract.lua` (HEAVY REFACTOR)

Read: `tree_control_facts.lua`, `tree_contract_facts.lua`

**Every classof branch becomes a leaf method.** These are the hardest files. The old code switches on statement/contract kind via classof. Replace with:
- `function Tree.StmtLet:control_flow_facts(ctx) → Check.ControlFlowResult end`
- `function Tree.StmtIf:control_flow_facts(ctx) → Check.ControlFlowResult end`
- etc. for every Stmt leaf

### Files 9-10: `impl/tree_check/const.lua`, `module.lua`

Read: `const_eval.lua`, `tree_module_type.lua`

Mostly clean leaf methods. Port with updated require paths.

### File 11: `impl/tree_check/init.lua`

```lua
require("lalin.impl.tree_check.type")
require("lalin.impl.tree_check.scope")
require("lalin.impl.tree_check.layout")
require("lalin.impl.tree_check.expr")
require("lalin.impl.tree_check.stmt")
require("lalin.impl.tree_check.control")
require("lalin.impl.tree_check.contract")
require("lalin.impl.tree_check.const")
require("lalin.impl.tree_check.module")
```

### File 12: `impl/tree_surface.lua`

Read: `surface_resolve.lua`. Refactor classof to leaf methods on Tree.* types.

### File 13: `impl/tree_closure.lua`

Read: `closure_convert.lua`. Mostly clean. Update require paths.

### File 14: `impl/code_validate.lua`

Read: `code_validate.lua`. Refactor mutable Machine wrapper to ASDL CodeValidationMachine methods.

### File 15: `impl/compiler_result.lua`

Read: `compiler_abi.lua`. Clean port.

### After all files: DELETE helpers

Delete: `core_scalar.lua`, `core_operator.lua`, `type_classify.lua`, `type_abi_classify.lua`
(Verify no remaining requires first.)

---

## 8. AGENT B — CODE IR + ANALYSIS + PLANS (files 16-23)

### Schema modules you work with
`code`, `graph`, `flow`, `value`, `mem`, `effect`, `kernel`, `schedule`, `lower`

### File 16: `impl/code_graph.lua` (START HERE)

Read: `lua/lalin/code_graph.lua` (396 lines)

Install methods:
```lua
local Code  = require("lalin.schema_v2.code")
local Graph = require("lalin.schema_v2.graph")

-- Entry point
function Code.CodeFunc:build_graph() → Graph.CodeGraph end

-- On CodePlace leaves:
function Code.CodePlaceLocal:code_graph_dst() → Graph.GraphNode end
function Code.CodePlaceLocal:code_graph_append_uses(builder, def) → void end
-- ... every CodePlace leaf

-- On CodeCallTarget leaves:
function Code.CodeCallTargetDirect:code_graph_resolve_target(module) → Code.CodeFunc end

-- On CodeInstOp leaves:
function Code.CodeInstOpBin:code_graph_operands() → [many Code.CodeValueId] end
-- ... every CodeInstOp leaf

-- On CodeTerm leaves:
function Code.CodeTermBranch:code_graph_targets() → [many Code.CodeBlockId] end
-- ... every CodeTerm leaf
```

### File 17: `impl/code_flow.lua`

Read: `code_flow_facts.lua` (555 lines). Clean leaf methods. Port directly.

```lua
function Graph.CodeGraph:compute_flow(module) → Flow.FlowFactSet end
function Flow.FlowLoopNatural:compute_loop_facts(dom_tree, cfg) → [many Flow.FlowFact] end
function Flow.FlowTripCountKnown:flow_analysis_summary() → Flow.TripCountSummary end
-- ... every FlowTripCount leaf
```

### File 18: `impl/code_value.lua`

Read: `code_value_facts.lua` (625 lines) + `reduction_algebra.lua` (212 lines). Clean.

```lua
function Graph.CodeGraph:compute_values(module, flow) → Value.ValueFactSet end
function Core.BinaryOpAdd:value_algebra(lhs, rhs) → Value.ValueExpr end
-- ... every BinaryOp leaf
function Code.CodeInstOpBin:compute_value(value_facts, flow_facts) → Value.ValueExpr end
-- ... every CodeInstOp leaf
function Value.ReductionSum:reduction_identity_value() → Value.ValueExpr end
function Value.ReductionSum:reduction_apply(accum, value) → Value.ValueExpr end
-- ... every Reduction leaf
```

### File 19: `impl/code_mem.lua`

Read: `code_mem_facts.lua` (752 lines). Clean, but large.

```lua
function Graph.CodeGraph:compute_mem(module, flow, values, contracts) → Mem.MemSemanticFactSet end
function Mem.MemProofExclusive:mem_proof_guarantee() → Mem.MemGuarantee end
-- ... every MemProof leaf (9 proof unions × 3-4 guarantees each)
function Mem.MemObjectLocal:mem_object_layout() → Sem.MemLayout end
-- ... every MemObjectForm leaf
```

### File 20: `impl/code_effect.lua` (REFACTOR)

Read: `code_effect_facts.lua` (183 lines). HAS classof on contract types.

```lua
function Graph.CodeGraph:compute_effects(module, mem, contracts) → Effect.EffectFactSet end
-- classof refactoring: each contract → leaf method
function Sem.FuncContractFactPure:to_effect_fact(func, mem_facts) → Effect.EffectFact end
function Sem.FuncContractFactNoAlias:to_effect_fact(func, mem_facts) → Effect.EffectFact end
-- ... every contract fact leaf
```

### File 21: `impl/kernel_plan.lua` (REFACTOR)

Read: `code_kernel_plan.lua` (1625 lines) + `kernel_validate.lua` (261 lines) + `kernel_emit_support.lua` (395 lines)
**kernel_validate.lua HAS HEAVY classof — must be fully refactored.**

```lua
function Mem.MemSemanticFactSet:plan_kernels(flow, values, mem, effects) → Kernel.KernelModulePlan end
function Kernel.KernelSkeletonStore:kernel_plan_candidates(loop, flow, values) → [many Kernel.KernelCandidate] end
function Kernel.KernelResultPlanned:validate_kernel_plan(input) → Kernel.KernelValidationResult end
-- ... every KernelResult leaf (refactored from classof)
```

### File 22: `impl/schedule_plan.lua`

Read: `code_schedule_plan.lua` (180 lines). Clean.

```lua
function Kernel.KernelModulePlan:plan_schedules(code_module, flow, values, mem, effects, target) → Schedule.ScheduleModulePlan end
```

### File 23: `impl/lower_plan.lua`

Read: `code_lower_plan.lua` (462 lines). Clean.

```lua
function Code.CodeModule:plan_lowering(graph, kernels, schedules, target) → Lower.LowerModule end
```

---

## 9. AGENT C — C EMISSION, STENCIL, BACKEND, EXEC, PIPELINE + COMPILE (files 24-37)

### Schema modules you work with
`lower`, `c`, `cemit`, `stencil`, `stencil_machine`, `value`, `code`, `core`, `exec`, `schedule`, `kernel`, `backend`, `compiler`

### CRITICAL: stencil_artifact_plan.lua MANDATE

`stencil_artifact_plan.lua` (2767 lines) installs methods on 7+ different schema modules. **You must sort every method by its receiver type into the correct impl file:**

| Receiver type | Destination |
|--------------|-------------|
| `Code.CodeTy`, `Code.CodeType` | `impl/lower_emit_c/code_to_c.lua` |
| `Value.Reduction` | `impl/stencil_reduction.lua` |
| `Stencil.*` | `impl/stencil_plan.lua` |
| `StencilMachine.*` | `impl/stencil_machine.lua` |
| `Schedule.*` | Agent B's `impl/schedule_plan.lua` (coordinate) |
| `Kernel.*` | Agent B's `impl/kernel_plan.lua` (coordinate) |
| `Mem.*` | Agent B's `impl/code_mem.lua` (coordinate) |

**Do NOT create a monolithic `impl/stencil_artifact.lua`.**

### File 24-28: `impl/lower_emit_c/` (sub-folder)

Read: `lower_to_c.lua` (2437 lines), `code_to_c.lua` (1358 lines), `emit_c_materialize.lua` (259 lines), `emit_c_validate.lua` (470 lines)

Split into sub-folder if total > 2000 lines:

```
impl/lower_emit_c/
  init.lua              -- require all sub-files
  schedule_form.lua     -- Schedule.ScheduleForm:emit_c() methods
  code_to_c.lua         -- Code.CodeType:code_to_c_type_name(), CodeInstOp:code_to_c_inst(), etc.
  materialize.lua       -- C value/place materialization helpers
  validate.lua          -- CBackendUnit:validate_c_unit() methods
```

```lua
local Lower    = require("lalin.schema_v2.lower")
local Schedule = require("lalin.schema_v2.schedule")
local Code     = require("lalin.schema_v2.code")
local C        = require("lalin.schema_v2.c")
local Core     = require("lalin.schema_v2.core")

-- Entry point
function Lower.LowerModule:emit_c(code_module) → C.CBackendUnit end

-- ScheduleForm leaves:
function Schedule.ScheduleFormVector:emit_c(ctx) → C.CEmitFragment end
function Schedule.ScheduleFormScalar:emit_c(ctx) → C.CEmitFragment end
function Schedule.ScheduleFormFallback:emit_c(ctx) → C.CEmitFragment end

-- CodeType leaves:
function Code.CodeTypeScalar:code_to_c_type_name() → str end
function Code.CodeTypePtr:code_to_c_type_name() → str end
-- ... every CodeType leaf

-- CodeConst leaves:
function Code.CodeConstInt:code_to_c_literal() → str end
-- ... every CodeConst leaf

-- CodeInstOp leaves:
function Code.CodeInstOpBin:code_to_c_inst(ctx) → str end
-- ... every CodeInstOp leaf

-- CodeTerm leaves:
function Code.CodeTermReturn:code_to_c_term(ctx) → str end
-- ... every CodeTerm leaf

-- Scalar to C type:
function Core.ScalarI8:emit_c_scalar_type() → str end
-- ... every scalar leaf

-- Validation:
function C.CBackendUnit:validate_c_unit() → C.CBackendValidationResult end
```

### File 29: `impl/cemit_emit.lua`

Read: `emit_c_lower.lua` (1415 lines)

```lua
local Cemit = require("lalin.schema_v2.cemit")
local C     = require("lalin.schema_v2.c")

function Cemit.CEmitMachine:emit_module(code_module, lower_module) → Cemit.CEmitArtifact end
function Cemit.CEmitMachine:emit_source(code_module, lower_module) → str end
function Cemit.CEmitMachine:emit_header(code_module) → str end
function Cemit.CEmitMachine:emit_combined(code_module, lower_module) → str end
```

### File 30: `impl/stencil_plan.lua`

Read: `stencil_artifact_plan.lua` (Stencil.* methods only) + `stencil_methods.lua` (Stencil.* methods)

```lua
local Stencil = require("lalin.schema_v2.stencil")

function Stencil.StencilProducer:stencil_producer_analysis(code, mem) → Stencil.StencilProducerFacts end
function Stencil.StencilDescriptorStore:stencil_descriptor_validate(target) → Stencil.StencilValidationResult end
function Stencil.StencilSelectedStore:stencil_selected_codegen(target, kernel) → Stencil.StencilCodegenPlan end
-- ... every Stencil type that receives methods
```

### File 31: `impl/stencil_reduction.lua` (START HERE — small and isolated)

Read: `stencil_artifact_plan.lua` (Reduction methods) + `lower_kernel_rewrite.lua`

```lua
local Value = require("lalin.schema_v2.value")

function Value.ReductionSum:display_name() → str end    -- "sum"
function Value.ReductionProd:display_name() → str end   -- "prod"
function Value.ReductionMin:display_name() → str end    -- "min"
function Value.ReductionMax:display_name() → str end    -- "max"
function Value.ReductionAnd:display_name() → str end    -- "and"
function Value.ReductionOr:display_name() → str end     -- "or"
-- ... every Reduction leaf

function Value.ReductionSum:reduction_combine_op() → Core.BinaryOp end
function Value.ReductionSum:reduction_neutral_element() → Value.ValueExpr end
-- ... every Reduction leaf
```

### File 32: `impl/stencil_machine.lua`

Read: `stencil_methods.lua` (StencilMachine.* methods)

```lua
local SM = require("lalin.schema_v2.stencil_machine")

function SM.StencilMachinePointInputScalar:stencil_machine_point_codegen(ctx) → SM.StencilMachinePointCode end
function SM.StencilMachineFindSelectionFacts:stencil_machine_find_codegen(ctx) → SM.StencilMachineFindResult end
-- ... every StencilMachine type
```

### File 33: `impl/stencil_metastencil.lua`

Read: `stencil_metastencil.lua` (743 lines)

```lua
local Stencil = require("lalin.schema_v2.stencil")

function Stencil.StencilDescriptorStore:metastencil_generate(target, config) → Stencil.StencilGenerated end
function Stencil.StencilGeneratedStore:metastencil_emit_c() → str end
-- ... every Stencil type
```

### File 34: `impl/stencil_c.lua`

Read: `stencil_c.lua` (1554 lines)

```lua
local Stencil = require("lalin.schema_v2.stencil")

function Stencil.StencilSelectedStore:stencil_c_emit(ctx) → str end
function Stencil.StencilAxisLoop:stencil_c_emit_loop(ctx, body) → str end
-- ... C-specific stencil codegen
```

### File 35: `impl/exec_plan.lua`

Read: `exec_plan.lua` (224 lines)

```lua
local Kernel  = require("lalin.schema_v2.kernel")
local Exec    = require("lalin.schema_v2.exec")
local Stencil = require("lalin.schema_v2.stencil")

function Kernel.KernelPlanned:exec_plan_build(code, lower) → Exec.ExecPlan end
function Stencil.StencilSelectedStore:exec_stencil_selection(lower) → Exec.ExecStencilSelection end
```

### File 36: `pipeline.lua` (WRITE LAST — after ALL impl files exist)

```lua
-- Thin composition. No compiler semantics. ~30 lines of actual logic.

-- Ensure all methods are installed:
require("lalin.impl.tree_surface")
require("lalin.impl.tree_closure")
require("lalin.impl.tree_check")
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

local function compile_pipeline(declarations, opts)
  local m = declarations.module:surface_resolve()
  m = m:closure_convert()
  local checked = m:typecheck(type_input)
  local code_result = checked:lower_to_code(lower_input)
  local graph = code_result.module:build_graph()
  local flow = graph:compute_flow(code_result.module)
  local values = graph:compute_values(code_result.module, flow)
  local mem = graph:compute_mem(code_result.module, flow, values, code_result.contracts)
  local effects = graph:compute_effects(code_result.module, mem, code_result.contracts)
  local kernels = mem:plan_kernels(flow, values, mem, effects)
  local schedules = kernels:plan_schedules(code_result.module, flow, values, mem, effects, opts.target)
  local lower_plan = code_result.module:plan_lowering(graph, kernels, schedules, opts.target)
  local c_unit = lower_plan:emit_c(code_result.module)
  local artifact = cemit_machine:emit_module(code_result.module, lower_plan)
  return artifact
end

return { compile_pipeline = compile_pipeline }
```

### File 37: `compile.lua` (WRITE LAST)

```lua
local pipeline = require("lalin.pipeline")

local function compile(source_text, opts)
  local decls = ... -- load from source
  return pipeline.compile_pipeline(decls, opts)
end

local function compile_c_gcc(name, decls, opts)
  local artifact = pipeline.compile_pipeline(decls, opts)
  return artifact:compile_with_gcc(name, opts.gcc_opts)
end

return { compile = compile, compile_c_gcc = compile_c_gcc }
```

---

## 10. COMMIT CONVENTION

One commit per completed impl file:
```
impl: tree_code.lua — rewrite: leaf methods on Tree.* for lowering
impl: code_graph.lua — rewrite: build_graph on Code.* types
```

After all impl files, one commit each for helpers deletion and pipeline/compile.

---

## 11. VERIFICATION

After writing each file:
```sh
luajit -e "require('lalin.impl.xxx')"
```
Must not error. That is all. Do NOT try to run the pipeline. Do NOT try to compile a .lln file. Do NOT add test harnesses.
