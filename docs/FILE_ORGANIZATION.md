# Lalin Compiler — File Organization

## The architecture is the semantic graph. The filesystem reflects the semantic graph.

This document defines the canonical file organization for the Lalin compiler
after the schema v2 port. It is the authoritative layout reference. Every new
file must justify its location against the rules below.

---

## 1. ROOT LAYOUT

```
lua/lalin/
  schema_v2/           ← PURE ASDL declarations (products, sums, constructors)
  impl/                ← Method installation on schema_v2 types (one file per phase)
  pipeline.lua         ← Thin composition: chains phase methods (~30 lines)
  compile.lua          ← Compilation entry point
  factories/           ← Lua-level code generators (produce ASDL, not methods on ASDL)
  dsl/                 ← Builder API (lln.fn, lln.struct, etc.) — already exists
  emit_c_compile.lua   ← GCC-over-emit_c shared-object runner — already exists
  luajit_backend.lua   ← LuaJIT bytecode backend facade — already exists
  native_backend.lua   ← Experimental native C-stencil backend facade — already exists
  frontend_pipeline.lua ← Legacy pipeline (refactor target, not delete target)
```

---

## 2. `schema_v2/` — PURE ASDL DECLARATIONS

### 2.1 What goes here

- `schema.` module declarations (`schema. LalinCore { ... }`)
- `product.` declarations with typed fields
- `sum.` declarations with concrete leaf types
- `interned`, `variant_unique` annotations
- **Nothing else.** No method installation. No Lua functions. No `require` of
  implementation modules.

### 2.2 File list (28 files, dependency order)

```
schema_v2/
  core.lua              LalinCore      — names, scalars, literals, ops, intrinsics, symbols
  parse.lua             LalinParse     — parse issues and results
  source.lua            LalinSource    — document URIs, anchors, source ranges, text changes
  type.lua              LalinType      — Type, TypeShape, TypeRef, ABI, layout, params
  c.lua                 LalinC         — C type system, C backend types, blocks, emission
  bind.lua              LalinBind      — Binding, BindingRole, Residence, Env, ValueRef
  sem.lua               LalinSem       — FieldRef, MemLayout, TypeLayout, ConstValue, closures
  tree.lua              LalinTree      — Expr, Stmt, Func, Item, Module, Place, View, Region
  check.lua             LalinCheck     — TypeExprInput/Result, TypeIssue, TypeModuleFacts
  tree_code.lua         LalinTreeCode  — TreeCode* lowering state machines
  code.lua              LalinCode      — Code IR (CodeFunc, CodeBlock, CodeInst, CodeTerm)
  graph.lua             LalinGraph     — CFG (edges, uses, defs, loops)
  flow.lua              LalinFlow      — flow analysis (domains, inductions, trip counts)
  value.lua             LalinValue     — value analysis (ValueExpr, AffineExpr, reductions)
  mem.lua               LalinMem       — memory analysis (objects, accesses, proofs, aliasing)
  effect.lua            LalinEffect    — effect analysis (OpEffect, CallSummary)
  kernel.lua            LalinKernel    — kernel planning (subjects, lanes, rewrites, plans)
  stencil.lua           LalinStencil   — stencil DSL (producers, accesses, schedules, fusion)
  stencil_machine.lua   LalinStencilMachine — stencil kernel selection and codegen facts
  lower.lua             LalinLower     — lowering plan (fragments, carriers, addresses)
  schedule.lua          LalinSchedule  — schedule planning (forms, emitters, capabilities)
  backend.lua           LalinBackend   — backend IR (BackScalar, Cmd, program facts)
  cemit.lua             LalinCEmit     — C emission (helpers, signatures, emit results)
  compiler.lua          LalinCompiler  — compilation result reporting
  code_validation.lua   LalinCodeValidation — code validation spine and results
  exec.lua              LalinExec      — execution plans (fragments, stencil decisions)
  phase.lua             LalinPhase     — worlds, machines, phases, plans, packages
  project.lua           LalinProject   — task tracking (declared, completed, blocked)
```

### 2.3 Rules

1. Each file defines exactly one `schema.` module.
2. Files are listed in dependency order. A file may reference types from files
   above it in the list. It must not reference types from files below it.
3. Schema files do not `require` each other at file scope. The ASDL DSL
   resolves cross-module references lazily through the schema registry.
4. Schema files do not contain Lua functions, methods, or logic. They are pure
   declarations.
5. Comments in schema files explain the *semantic invariant* of a type, not
   its implementation.

### 2.4 Example

```lua
-- schema_v2/core.lua
local S = require("lalin.schema.dsl")
S.use()

return schema. LalinCore {
  product. Name { interned, text [str] },

  sum. Scalar {
    ScalarVoid, ScalarBool,
    ScalarI8, ScalarI16, ScalarI32, ScalarI64,
    ScalarU8, ScalarU16, ScalarU32, ScalarU64,
    ScalarF32, ScalarF64, ScalarRawPtr, ScalarIndex,
  },

  sum. UnaryOp { UnaryNeg, UnaryNot, UnaryBitNot, },
}
```

---

## 3. `impl/` — METHOD INSTALLATION

### 3.1 What goes here

Every file in `impl/` does exactly one thing: **installs Lua methods on ASDL
classes defined in `schema_v2/`.** No dispatch, no handler maps, no `classof`,
no side tables. Just method installation.

### 3.2 Organization — one file per phase per receiver module

```
impl/
  tree_surface.lua          surface_resolve methods on LalinTree types
  tree_closure.lua          closure_convert methods on LalinTree types
  tree_check.lua            typecheck methods on LalinTree types
  tree_code.lua             lower_to_code methods on LalinTree types
  code_graph.lua            build_graph methods on LalinCode types
  code_flow.lua             compute_flow methods on LalinGraph types
  code_value.lua            compute_values methods on LalinGraph types
  code_mem.lua              compute_mem methods on LalinGraph types
  code_effect.lua           compute_effects methods on LalinGraph types
  kernel_plan.lua           plan_kernels methods on fact set types
  schedule_plan.lua         plan_schedules methods on kernel plan types
  lower_plan.lua            plan_lowering methods on code + graph + kernel types
  lower_emit_c.lua          emit_c methods on LowerModule types
  cemit_emit.lua            emit_artifact methods on CEmitMachine types
  code_validate.lua         validate methods on CodeModule types
  backend_emit.lua          emit methods on BackendProgram types
  compiler_result.lua       report methods on CodeResult types
```

### 3.3 Shape of an impl file

Every function in an impl file has this signature:

```lua
function ASDLModule.ConcreteLeaf:phase_name(input_asdl) -> output_asdl
```

**Receiver** — the concrete ASDL union leaf (e.g., `Tree.ExprCall`, not
`Tree.Expr`). The leaf is the dispatch target. Calling the method on the
parent union dispatches to the correct leaf through Lua metatables.

**Input** — an ASDL product or a small number of primitive parameters when
trivial. No `ctx`, `env`, `state`, `opts`, `facts` bags.

**Output** — an ASDL product, union, or sum leaf. No loose tables, no `{ ok =
true, value = x }`, no multiple Lua returns for semantic outcomes, no `nil`
as a convention.

### 3.4 Example — typecheck methods

```lua
-- impl/tree_check.lua
local Tree  = require("lalin.schema_v2.tree")
local Check = require("lalin.schema_v2.check")
local Type  = require("lalin.schema_v2.type")

-- Each concrete Expr leaf installs :typecheck(input) → TypeExprResult
function Tree.ExprLit:typecheck(input)
  local ty = infer_literal_type(self.value)
  return Check.TypeExprResult(self, ty, {})
end

function Tree.ExprUnary:typecheck(input)
  local operand = self.value:typecheck(TypeExprInput(input.scope))
  local ty = compute_unary_type(self.op, operand.ty)
  local issues = collect_issues(operand)
  if not ty then
    table.insert(issues, Check.TypeIssueInvalidUnary(...))
  end
  return Check.TypeExprResult(self, ty or Type.TScalar(Type.ScalarVoid), issues)
end

function Tree.ExprBinary:typecheck(input)
  local lhs = self.lhs:typecheck(TypeExprInput(input.scope))
  local rhs = self.rhs:typecheck(TypeBinaryInput(self.op, lhs.ty))
  -- ...
end

-- Module is the orchestrator
function Tree.Module:typecheck(input)
  local scope = Check.TypeValueScope(...)
  local items = {}
  local issues = {}
  for _, item in ipairs(self.items) do
    local result = item:typecheck(TypeItemInput(scope))
    -- thread scope through declarations
    scope = merge_scope(scope, result)
    -- accumulate
  end
  return Check.TypeModuleResult(self, issues)
end
```

### 3.5 When to split an impl file

When an impl file exceeds ~2000 lines, split by type category into a
sub-folder. The sub-folder has an `init.lua` that requires all sub-files.

```
impl/
  tree_check/
    init.lua           -- require("./expr"); require("./stmt"); ...
    expr.lua           -- :typecheck() on ExprLit, ExprCall, ExprBinary, ...
    stmt.lua           -- :typecheck() on StmtLet, StmtIf, StmtSwitch, ...
    place.lua          -- :typecheck() on PlaceRef, PlaceDeref, ...
    view.lua           -- :typecheck() on ViewFromExpr, ViewContiguous, ...
    func.lua           -- :typecheck() on FuncLocal, FuncExport, ...
    item.lua           -- :typecheck() on ItemFunc, ItemExtern, ...
    module.lua         -- Module:typecheck() — the orchestrator
```

The split is purely for file size management. All methods in the sub-folder
belong to the same phase. There is no architectural boundary between
`expr.lua` and `stmt.lua`.

### 3.6 Method naming convention

Method names name **what the phase produces**, not what it does:

| Phase | Method name | Returns |
|-------|------------|---------|
| Surface resolve | `:surface_resolve()` | `LalinTree.Module` |
| Closure convert | `:closure_convert()` | `LalinTree.Module` |
| Typecheck | `:typecheck(input)` | `LalinCheck.TypeExprResult` (or per-type result) |
| Lower to code | `:lower_to_code(input)` | `LalinTreeCode.TreeCodeExprResult` (or per-type result) |
| Build graph | `:build_graph()` | `LalinGraph.CodeGraph` |
| Compute flow | `:compute_flow(module)` | `LalinFlow.FlowFactSet` |
| Compute values | `:compute_values(module, flow)` | `LalinValue.ValueFactSet` |
| Compute mem | `:compute_mem(module, graph, flow, values, contracts)` | `LalinMem.MemSemanticFactSet` |
| Compute effects | `:compute_effects(module, graph, mem, contracts)` | `LalinEffect.EffectFactSet` |
| Plan kernels | `:plan_kernels()` | `LalinKernel.KernelModulePlan` |
| Plan schedules | `:plan_schedules(target)` | `LalinSchedule.ScheduleModulePlan` |
| Plan lowering | `:plan_lowering(target)` | `LalinLower.LowerModule` |
| Emit C | `:emit_c(code_module)` | `LalinC.CBackendUnit` |
| Emit artifact | `:emit_artifact()` | `{ source, header, support, combined }` |
| Validate | `:validate()` | `LalinCodeValidation.CodeValidateResult` |

### 3.7 Forbidden shapes in impl/

These are architecture bugs. Do not introduce them.

```lua
-- FORBIDDEN: handler map
local handlers = { ExprCall = ..., ExprInt = ... }
function typecheck_expr(expr, input)
  return handlers[expr.kind](expr, input)
end

-- FORBIDDEN: classof dispatch
function typecheck_expr(expr, input)
  if schema.classof(expr) == Tree.ExprCall then
    return typecheck_call(expr, input)
  elseif schema.classof(expr) == Tree.ExprInt then
    -- ...
  end
end

-- FORBIDDEN: kind-string dispatch
function typecheck_expr(expr, input)
  if expr.kind == "ExprCall" then
    -- ...
  end
end

-- FORBIDDEN: side tables
local type_cache = {}  -- keyed by Expr nodes
function compute_type(expr)
  if type_cache[expr] then return type_cache[expr] end
  -- ...
end

-- FORBIDDEN: generic context bags
function Tree.ExprCall:typecheck(ctx)
  -- ctx has .env, .state, .opts, .facts, .tables, ...
end

-- FORBIDDEN: ad hoc result records
function Tree.ExprCall:typecheck(input)
  return { ok = true, ty = result_ty, errors = {} }
end

-- FORBIDDEN: nil passthrough conventions
function Tree.ExprCall:typecheck(input)
  if not self.callee then return nil end  -- nil means "skip this"
end

-- FORBIDDEN: multiple Lua returns for semantic outcomes
function Tree.ExprCall:typecheck(input)
  return result_ty, issues, warnings
end

-- FORBIDDEN: mutation of receiver or child nodes
function Tree.Module:surface_resolve()
  self.h = ModuleSem(...)  -- mutating the module header
  return self
end
```

### 3.8 Parent union methods

Parent union methods are allowed **only** as:

1. **Shared defaults** — when all or most leaves share identical behavior:

```lua
-- OK: shared default for all Expr leaves that don't override
function Tree.Expr:describe()
  return "expression"
end
```

2. **Explicit delegation contracts** — when the parent declares an abstract
   protocol that leaves must fulfill:

```lua
-- OK: abstract protocol declaration (Lua doesn't enforce, documentation does)
-- Every concrete Place leaf must implement :address_of(input) → AddressResult
function Tree.Place:address_of(input)
  error("abstract: Place leaf must implement :address_of")
end
```

3. **Common pre/post logic** — when the parent wraps leaf methods with shared
   behavior, without inspecting which leaf it is:

```lua
-- OK: shared logging/debugging wrapper (does not inspect child class)
function Tree.Expr:typecheck_with_trace(input)
  local result = self:typecheck(input)
  trace("typechecked", self, "→", result.ty)
  return result
end
```

Parent methods must **never** inspect child identity:

```lua
-- FORBIDDEN: parent method inspects leaf class
function Tree.Expr:do_thing(input)
  if schema.classof(self) == Tree.ExprCall then
    -- ...
  end
end
```

---

## 4. `pipeline.lua` — THIN COMPOSITION

### 4.1 What it is

The pipeline is the composition of phase methods into the full compilation
sequence. It is thin — approximately 30 lines. It does not contain compiler
semantics. It is a wiring function, not a driver.

### 4.2 Shape

```lua
-- pipeline.lua
local function compile_pipeline(declarations, opts)
  -- Phase 1: surface resolve
  local m = declarations.module:surface_resolve()

  -- Phase 2: closure convert
  m = m:closure_convert()

  -- Phase 3: typecheck
  local type_input = build_typecheck_input(m, opts)
  local checked = m:typecheck(type_input)

  -- Phase 4: lower to code
  local lower_input = build_lower_input(checked, opts)
  local code_result = checked:lower_to_code(lower_input)

  -- Phase 5: build graph
  local code_module = code_result.module
  local contracts   = code_result.contracts
  local graph       = code_module:build_graph()

  -- Phase 6: flow facts
  local flow = graph:compute_flow(code_module)

  -- Phase 7: value facts
  local values = graph:compute_values(code_module, flow)

  -- Phase 8: memory facts
  local mem = graph:compute_mem(code_module, flow, values, contracts)

  -- Phase 9: effect facts
  local effects = graph:compute_effects(code_module, mem, contracts)

  -- Phase 10: kernel plan
  local kernels = mem:plan_kernels(flow, values, mem, effects)

  -- Phase 11: schedule plan
  local schedules = kernels:plan_schedules(code_module, flow, values, mem, effects, opts.target)

  -- Phase 12: lower plan
  local lower_plan = code_module:plan_lowering(graph, kernels, schedules, opts.target)

  -- Phase 13: emit C
  local c_unit = lower_plan:emit_c(code_module)

  -- Phase 14: emit artifact
  local artifact = c_unit:emit_artifact()

  return artifact
end
```

### 4.3 What it is NOT

- It is NOT a driver. It does not own state. It calls methods.
- It is NOT a machine. It does not retain anything between runs.
- It does NOT contain compiler semantics. All semantics live in `impl/` methods.
- It does NOT have error handling strategies. Each method returns typed results
  (e.g., `TypeModuleResult` carries diagnostics). The pipeline threads them
  through; the caller decides what to do with diagnostics.

---

## 5. `compile.lua` — ENTRY POINT

### 5.1 What it is

The public API boundary. Users call `lalin.compile(source, opts)` or
`lalin.compile_c_gcc(name, decls, opts)`. This file creates the initial ASDL
values from untyped inputs (source strings, file paths, GCC options) and calls
the pipeline.

### 5.2 Shape

```lua
-- compile.lua
local pipeline = require("lalin.pipeline")

function compile(source_text, opts)
  local decls = load_declarations(source_text, opts.filename)
  local artifact = pipeline.compile_pipeline(decls, opts)
  return artifact
end

function compile_c_gcc(name, decls, opts)
  local artifact = compile_pipeline(decls, opts)
  return artifact:compile_with_gcc(name, opts.gcc_opts)
end
```

### 5.3 The boundary

This is the boundary between the untyped world (source strings, file paths,
GCC options) and the typed ASDL world. Once `compile_pipeline` is called,
everything is ASDL values and methods. The entry point's job is to cross that
boundary — parse options, load source files, construct the initial
`CompilationRequest` or `Module`, then hand off to the typed world.

---

## 6. `factories/` — CODE GENERATORS

### 6.1 What goes here

Lua functions that generate Lalin ASDL declarations from parameters. Factories
exist because **Lua owns genericity; Lalin receives monomorphic values.**

### 6.2 When to use a factory

Use a factory when N machines differ by:
- element type (`i32` vs `f64` vector add)
- constant (`queue_capacity = 256` vs `queue_capacity = 1024`)
- platform call (SSE2 vs AVX2 intrinsics)
- backend target (C vs LuaJIT)
- shape family (scalar, vector, strided)
- generated boilerplate (stencil kernel variants)

### 6.3 Shape

```lua
-- factories/vector_ops.lua
local lln = require("lalin.lln")

local function make_vector_add(lanes, scalar)
  local elem_ty = lln[scalar]
  local vec_ty  = lln.vec(elem_ty, lanes)
  return lln.fn["vector_add_" .. scalar .. "x" .. lanes]({
    a [vec_ty],
    b [vec_ty],
  }) [vec_ty] {
    lln.ret(a + b),
  }
end

-- Returns a LalinTree.Func (an ASDL value)
local add_i32x4 = make_vector_add(4, "i32")
```

### 6.4 Factory vs method

A factory produces ASDL from Lua parameters when the receiver **does not exist
yet**. A method transforms ASDL when the receiver **already exists**.

```lua
-- FACTORY: no receiver yet, generate from parameters
local func = make_vector_add(4, "i32")

-- METHOD: receiver exists, specialize it
local specialized = func:specialize_for_scalar(ScalarI32)
```

### 6.5 Factory organization

```
factories/
  vector_ops.lua       — vector add/sub/mul for various lane widths
  stencil_kernels.lua  — stencil kernel variants (store, reduce, scan)
  queue_families.lua   — queue implementations for different capacities
  extern_bindings.lua  — LuaJIT FFI extern declarations from C headers
```

One file per family of generated declarations. The factory signature is
parameterized; the output is monomorphic, distinctly named, and knob-free.

---

## 7. MACHINE OBJECTS

### 7.1 When to create a machine

A machine object is an ASDL product with methods that carries **retained state
between runs.** Create a machine when a subsystem has:

- **Repeated execution** — not one-shot
- **Retained state** — caches, counters, environments, handles
- **Diagnostics** — accumulated across runs
- **Incremental invalidation** — part of the input changes, part of the output
  is reused
- **Ownership authority** — owns bytes, handles, runtime resources
- **A performance boundary** — expensive state that should not be rebuilt

### 7.2 Machine objects in the Lalin compiler

| Machine | State it retains | Where |
|---------|-----------------|-------|
| `CompilationSession` | dlopen'd shared object handle, symbol table | Already exists in `emit_c_compile.lua` |
| `CEmitMachine` | Generated helpers, C type declarations, counter state | `schema_v2/cemit.lua`, methods in `impl/cemit_emit.lua` |
| `CodeValidationMachine` | Checked relocs, accumulated issues | `schema_v2/code_validation.lua` |
| `TypecheckMachine` (future) | Previous TypeValueScope, TypeModuleFacts for incremental recheck | Does not exist yet — one-shot typecheck is the current target |

### 7.3 Machine shape

A machine is an ASDL product. Its methods consume the machine and produce
output. If the machine must survive the call, the method returns a new machine
product (immutable update).

```lua
-- schema_v2/cemit.lua
product. CEmitMachine {
  interned,
  spine     [LalinLower.LowerBackSpine],
  c_sigs    [many [LalinCEmit.CEmitCSigEntry]],
  helpers   [many [LalinCEmit.CEmitHelperEntry]],
}

-- impl/cemit_emit.lua
function CEmitMachine:emit_module(code_module, lower_module)
  -- consume self, produce CBackendUnit
  -- if helpers need to be accumulated, return an updated machine:
  --   return updated_machine, c_unit
end
```

---

## 8. LEGACY FILES — REFACTOR TARGETS

These files exist in the current tree and will be refactored into the new
organization. They are NOT deleted until their replacement is complete.

| Legacy file | Refactor target |
|-------------|----------------|
| `lua/lalin/schema/*.lua` | Replaced by `lua/lalin/schema_v2/*.lua` |
| `lua/lalin/frontend_pipeline.lua` | Replaced by `impl/tree_surface.lua` + `impl/tree_closure.lua` + `impl/tree_check.lua` + `pipeline.lua` |
| `lua/lalin/emit_c_compile.lua` | Backend machine methods move to `impl/cemit_emit.lua`; GCC runner stays as a machine |
| `lua/lalin/luajit_backend.lua` | Backend methods move to `impl/luajit_emit.lua` |
| `lua/lalin/native_backend.lua` | Deferred — experimental, not in v2 scope |
| DSL builder (`lua/lalin/dsl/`) | **Kept as-is** — this is the builder API, not schema or impl |

---

## 9. TEST ORGANIZATION

### 9.1 Principles

- **Local leaf-method tests** prove semantic boundaries. Construct ASDL inputs,
  call a method, assert ASDL outputs.
- **Whole-pipeline tests** prove phase composition. Feed source text, assert
  emitted C text or execution results.

### 9.2 Layout

```
tests/
  run.lua                          — test runner entry point

  schema/                          — schema declaration tests
    test_core_schema.lua
    test_tree_schema.lua
    test_code_schema.lua
    ...

  frontend/                        — frontend phase tests
    test_surface_resolve.lua       — :surface_resolve() on tree types
    test_closure_convert.lua       — :closure_convert() on tree types
    test_typecheck_expr.lua        — :typecheck() on Expr types
    test_typecheck_stmt.lua        — :typecheck() on Stmt types
    test_typecheck_module.lua      — Module:typecheck()
    ...

  code_ir/                         — code IR and analysis tests
    test_tree_to_code.lua          — :lower_to_code() on tree types
    test_code_graph.lua            — :build_graph() on Code types
    test_code_flow.lua             — :compute_flow() on Graph types
    test_code_value.lua            — :compute_values()
    test_code_mem.lua              — :compute_mem()
    test_code_effect.lua           — :compute_effects()
    test_kernel_plan.lua           — :plan_kernels()
    test_schedule_plan.lua         — :plan_schedules()
    test_lower_plan.lua            — :plan_lowering()
    test_lower_emit_c.lua          — :emit_c() + :emit_artifact()
    ...

  compiler_process/                — end-to-end pipeline tests
    test_compiler_driver.lua       — compile(source, opts) → artifact
    test_compile_c_gcc.lua         — compile_c_gcc(name, decls, opts) → session
    ...

  fixtures/                        — test fixture helpers
    helpers.lua                    — build_* functions for constructing ASDL inputs
```

### 9.3 Harness shape — correct

```lua
-- tests/frontend/test_typecheck_expr.lua
local Tree  = require("lalin.schema_v2.tree")
local Check = require("lalin.schema_v2.check")
local Core  = require("lalin.schema_v2.core")
local Type  = require("lalin.schema_v2.type")
local Fixture = require("tests.fixtures.helpers")

-- Require the impl to install methods
require("lalin.impl.tree_check")

local scope = Fixture.empty_scope("test_module")
local input = Check.TypeExprInput(scope)

-- Test leaf method directly
local lit = Tree.ExprLit(Tree.ExprSurface(), Core.LitInt("42"))
local result = lit:typecheck(input)

assert(Check.TypeExprResult:is(result))
assert(result.ty == Type.TScalar(Core.ScalarI32))
assert(#result.issues == 0)
```

### 9.4 Harness shape — wrong

```lua
-- DO NOT DO THIS: untyped path, kind inspection, handler maps
local result = typecheck_expr({
  kind = "ExprLit",
  value = { kind = "LitInt", raw = "42" },
}, ctx)
assert(result.kind == "ok")
assert(result.ty == "i32")
```

---

## 10. FILE NAMING CONVENTIONS

| Kind | Pattern | Example |
|------|---------|---------|
| Schema module | `schema_v2/<module_snake>.lua` | `schema_v2/tree_code.lua` |
| Impl file | `impl/<receiver>_<phase>.lua` | `impl/tree_check.lua` |
| Impl sub-folder | `impl/<receiver>_<phase>/` | `impl/tree_check/` |
| Impl sub-file | `impl/<receiver>_<phase>/<type_category>.lua` | `impl/tree_check/expr.lua` |
| Factory | `factories/<family>.lua` | `factories/vector_ops.lua` |
| Pipeline | `pipeline.lua` | (one file) |
| Entry point | `compile.lua` | (one file) |
| Test | `tests/<phase>/test_<subject>.lua` | `tests/frontend/test_typecheck_expr.lua` |
| Fixture | `tests/fixtures/helpers.lua` | (one file, or split by module) |

### 10.1 Impl file naming

The name encodes **what types receive methods** and **what phase the methods
belong to**:

| Impl file | Receivers | Phase |
|-----------|-----------|-------|
| `tree_surface.lua` | LalinTree types | Surface resolve |
| `tree_closure.lua` | LalinTree types | Closure convert |
| `tree_check.lua` | LalinTree types | Typecheck |
| `tree_code.lua` | LalinTree types | Lower to code |
| `code_graph.lua` | LalinCode types | Build graph |
| `code_flow.lua` | LalinGraph types | Flow facts |
| `code_value.lua` | LalinGraph types | Value facts |
| `code_mem.lua` | LalinGraph types | Memory facts |
| `code_effect.lua` | LalinGraph types | Effect facts |
| `kernel_plan.lua` | fact set types | Kernel plan |
| `schedule_plan.lua` | kernel plan types | Schedule plan |
| `lower_plan.lua` | code + graph + kernel types | Lower plan |
| `lower_emit_c.lua` | LowerModule types | Emit C |
| `cemit_emit.lua` | CEmitMachine types | Emit artifact |
| `code_validate.lua` | CodeModule types | Validate |
| `backend_emit.lua` | BackendProgram types | Emit backend |
| `compiler_result.lua` | CodeResult types | Report |

---

## 11. DEPENDENCY RULES

### 11.1 Schema files

Schema files depend on schema files above them in the list (section 2.2).
They do not depend on impl files, factories, or pipeline. They do not
`require` each other at file scope — the ASDL DSL resolves cross-module
references lazily.

### 11.2 Impl files

Impl files `require` the schema_v2 files for the types they install methods on.
They may also `require` other schema_v2 files for types they use in method
bodies. They do NOT `require` other impl files.

```lua
-- impl/tree_check.lua
local Tree  = require("lalin.schema_v2.tree")    -- receiver types
local Check = require("lalin.schema_v2.check")    -- result types
local Type  = require("lalin.schema_v2.type")     -- used in method bodies
local Core  = require("lalin.schema_v2.core")     -- used in method bodies
-- NO: require("lalin.impl.tree_surface")         -- impl files do not depend on each other
```

### 11.3 Pipeline

`pipeline.lua` requires the impl files it needs (to ensure methods are
installed) and the schema_v2 files for types used in composition.

```lua
-- pipeline.lua
require("lalin.impl.tree_surface")
require("lalin.impl.tree_closure")
require("lalin.impl.tree_check")
require("lalin.impl.tree_code")
require("lalin.impl.code_graph")
-- ... all impl files for phases in the pipeline
```

### 11.4 Factories

Factories require `lalin.lln` (the builder DSL) and `lalin.schema_v2.*` for
types they reference. They do NOT require impl files. They produce ASDL values,
not method calls.

---

## 12. MIGRATION PATH

The migration from the current codebase to this organization proceeds in phases:

### Phase 1: Schema v2 (DONE)
- 28 schema files in `lua/lalin/schema_v2/`
- Purely declarative
- Legacy `lua/lalin/schema/` remains until all consumers migrated

### Phase 2: Impl files (NEXT)
- Create `lua/lalin/impl/` directory
- For each phase, create one impl file that installs methods on schema_v2 types
- Methods are NEW code — they do not touch legacy implementation files
- Schema types are imported from schema_v2, NOT from legacy schema

### Phase 3: Pipeline
- Create `lua/lalin/pipeline.lua`
- Wire the impl methods into the full compilation sequence
- At this point, the typed path is complete

### Phase 4: Entry points
- Create `lua/lalin/compile.lua`
- Wire the pipeline behind the public API
- Legacy entry points become thin wrappers

### Phase 5: Delete legacy
- Remove `lua/lalin/schema/` once all consumers migrated
- Remove `lua/lalin/frontend_pipeline.lua` once pipeline.lua covers it
- Keep `lua/lalin/dsl/` (builder API — not schema)
- Keep `lua/lalin/emit_c_compile.lua` (GCC runner machine — not schema)

---

## 13. QUICK REFERENCE CARD

```
Where does X go?
─────────────────
New ASDL type declaration          → schema_v2/<module>.lua
Method on existing ASDL type       → impl/<receiver>_<phase>.lua
Phase composition                  → pipeline.lua
Public API entry point             → compile.lua
Code generator (parameterized)     → factories/<family>.lua
Builder DSL (lln.fn, lln.struct)   → dsl/ (already exists)
GCC shared-object runner           → emit_c_compile.lua (already exists)
LuaJIT bytecode backend            → luajit_backend.lua (already exists)
Test for a method                  → tests/<phase>/test_<subject>.lua
Test for the full pipeline         → tests/compiler_process/
Fixture helper                     → tests/fixtures/helpers.lua

What shape should X have?
─────────────────────────
Schema file                        → schema. ModuleName { product. ... sum. ... }
Impl function                      → function ASDLModule.ConcreteLeaf:phase(input_asdl) → output_asdl
Pipeline function                  → 30 lines of a:b():c():d() chaining
Factory function                   → function make_thing(params) → LalinTree.Func
Test                               → construct ASDL input → call method → assert ASDL output
```

---

## 14. THE RULE

> **If you are about to write a function and you cannot name the ASDL type that
> receives it, stop. The missing type is the real design work. Add the type to
> schema_v2/, then install the method in impl/.**

---

## 15. OLD IMPLEMENTATION FILE MAPPING

This section maps every legacy implementation file in `lua/lalin/` to its
proposed `impl/` target, receiver types, and phase. It is the migration
blueprint for Phase 2.

Each entry records: legacy file path, line count, what ASDL types it
installs methods on (receiver types), what phase those methods belong to,
whether it uses forbidden patterns (`schema.classof`, handler maps, side
tables), and the target `impl/` file or disposition.

### 15.1 FRONTEND PIPELINE PHASES

#### `impl/tree_surface.lua` — :surface_resolve() on LalinTree types

| Old file | Lines | Receiver types | Clean? |
|----------|-------|----------------|--------|
| `surface_resolve.lua` | 137 | `Ty.Type` leaves, `Tr.ModuleHeader` leaves | ⚠️ recursive walk with `asdl.classof` dispatch; needs leaf methods |

#### `impl/tree_closure.lua` — :closure_convert() on LalinTree types

| Old file | Lines | Receiver types | Clean? |
|----------|-------|----------------|--------|
| `closure_convert.lua` | 819 | `Ty.Type` leaves, `B.ValueRef` leaves | ✅ mostly leaf methods + helpers; some `:closure_size_align()` on Type

#### `impl/tree_check.lua` — :typecheck() on LalinTree types (~6362 lines total)

| Old file | Lines | Receiver types | Clean? |
|----------|-------|----------------|--------|
| `tree_typecheck.lua` | 1951 | `Tr.View`, `Tr.Module` entry points | ⚠️ composition file — wires sub-phases together |
| `tree_typecheck_type.lua` | 565 | `Core.Scalar` leaves, `Ty.Type` leaves for canonicalization/predicates | ✅ clean leaf methods |
| `tree_typecheck_expr.lua` | 628 | `Ty.Type`, `Tr.ExprHeader`, `Tr.PlaceHeader` | ⚠️ closure-based `type_expr` dispatch |
| `tree_typecheck_stmt.lua` | 852 | `Tr.RegionInvokeTarget`, `Tr.TypeModuleFacts`, `Tr.BlockLabel` | ⚠️ some `asdl.classof` dispatch |
| `tree_typecheck_fact.lua` | 708 | `LalinCheck.TypeValueScope` (`:typecheck_tree_add_value()`, `:typecheck_tree_lookup_value()`) | ✅ clean methods on scope product |
| `tree_typecheck_layout.lua` | 43 | Layout resolution methods (small) | ✅ inline |
| `tree_control_facts.lua` | 473 | Control flow fact computation | ❌ **heavy `schema.classof` dispatch** — needs leaf methods |
| `tree_contract_facts.lua` | 169 | Contract fact extraction | ❌ **`schema.classof` dispatch** — needs leaf methods |
| `const_eval.lua` | 608 | `Sem.ConstExprResult`, `Sem.ConstValue`, `Sem.ConstStmtFlow` leaf types | ✅ clean leaf methods on Sem union types |
| `tree_module_type.lua` | 365 | `Tr.ModuleHeader` leaves, `Ty.Type` leaves, `Tr.Func` leaves, `Tr.Item` leaves | ✅ clean leaf method dispatch |
| `switch_decide.lua` | 111 | Switch key decision helpers | — replaced by `SwitchKeyClass` leaf methods on Expr in new schema |

#### `impl/tree_code.lua` — :lower_to_code() on LalinTree types

| Old file | Lines | Receiver types | Clean? |
|----------|-------|----------------|--------|
| `tree_lower.lua` | **3067** | `Tr.*`, `Ty.*`, `Core.Scalar`, `Code.*`, `Bind.*`, `TL.*` | ✅ clean leaf methods; large but method-per-leaf |
| `layout_resolve.lua` | 678 | `Tr.Expr`, `Tr.Stmt`, `Tr.Place`, `Tr.Module` (`:sem_layout_resolve()`) | ⚠️ `schema.with()` + closure-based `resolve_expr` dispatch |

#### `impl/code_validate.lua` — :validate() on CodeModule types

| Old file | Lines | Receiver types | Clean? |
|----------|-------|----------------|--------|
| `code_validate.lua` | 840 | Code type validation via internal Machine wrapper | ⚠️ Machine is mutable context bag pattern; should model validation state as ASDL

### 15.2 CODE ANALYSIS PHASES

#### `impl/code_graph.lua` — :build_graph() on LalinCode types

| Old file | Lines | Receiver types | Clean? |
|----------|-------|----------------|--------|
| `code_graph.lua` | 396 | `Code.CodePlace` leaves, `Code.CodeCallTarget` leaves, `Code.CodeInstOp` leaves | ✅ clean leaf method dispatch; `:code_graph_dst()`, `:code_graph_append_uses()`

#### `impl/code_flow.lua` — :compute_flow() on LalinGraph types

| Old file | Lines | Receiver types | Clean? |
|----------|-------|----------------|--------|
| `code_flow_facts.lua` | 555 | `Flow.FlowTripCount` leaves, `Flow.FlowLoop` leaves, `Flow.FlowCarrier` leaves | ✅ clean leaf method dispatch on Flow union types

#### `impl/code_value.lua` — :compute_values() on LalinGraph types

| Old file | Lines | Receiver types | Clean? |
|----------|-------|----------------|--------|
| `code_value_facts.lua` | 625 | `Core.BinaryOp` leaves, `Core.UnaryOp` leaves, `Core.CmpOp` leaves, `Code.CodeInstOp` leaves, `Value.ValueExpr` leaves | ✅ clean leaf methods |
| `reduction_algebra.lua` | 212 | `Value.Reduction` leaves (`:reduction_identity_value()`, `:reduction_apply()`) | ✅ clean leaf methods |

#### `impl/code_mem.lua` — :compute_mem() on LalinGraph types

| Old file | Lines | Receiver types | Clean? |
|----------|-------|----------------|--------|
| `code_mem_facts.lua` | 752 | `Mem.MemProof` leaves, `Mem.MemAccessProjection` | ✅ clean leaf methods |

#### `impl/code_effect.lua` — :compute_effects() on LalinGraph types

| Old file | Lines | Receiver types | Clean? |
|----------|-------|----------------|--------|
| `code_effect_facts.lua` | 183 | Effect-related methods; contract fact → effect fact conversion | ⚠️ `asdl.classof` dispatch on contract classes — needs leaf methods |

### 15.3 KERNEL, SCHEDULE, AND LOWERING PHASES

#### `impl/kernel_plan.lua` — :plan_kernels() on fact set types

| Old file | Lines | Receiver types | Clean? |
|----------|-------|----------------|--------|
| `code_kernel_plan.lua` | **1625** | `Kernel.*`, `Code.*`, `Flow.*` — rich leaf dispatch for loop candidate selection, carrier/address analysis, kernel skeleton selection | ✅ clean leaf method pattern |
| `kernel_validate.lua` | 261 | Kernel plan validation | ❌ **heavy `asdl.classof` dispatch** |

#### `impl/schedule_plan.lua` — :plan_schedules() on kernel plan types

| Old file | Lines | Receiver types | Clean? |
|----------|-------|----------------|--------|
| `code_schedule_plan.lua` | 180 | `Schedule.SchedulePlanInput`, `Schedule.SchedulePlanSelection` leaves | ✅ clean leaf methods |
| `kernel_emit_support.lua` | 395 | Target capability checking, reject reason helpers | — functional helpers; inline into impl |

#### `impl/lower_plan.lua` — :plan_lowering() on code + graph + kernel types

| Old file | Lines | Receiver types | Clean? |
|----------|-------|----------------|--------|
| `code_lower_plan.lua` | 462 | `Schedule.KernelSchedule` leaves, `Kernel.KernelResult` leaves, `Lower.LowerFragmentCandidate` leaves, `Flow.FlowCarrierTransfer`, `Flow.FlowCarrierThread`, `Flow.FlowAddressThread` | ✅ clean leaf methods |

### 15.4 C EMISSION PHASES

#### `impl/lower_emit_c.lua` — :emit_c() on LowerModule types (~4809 lines total)

| Old file | Lines | Receiver types | Clean? |
|----------|-------|----------------|--------|
| `lower_to_c.lua` | **2437** | `Schedule.ScheduleForm` leaves, `Lower.LowerStrategy` leaves, `Lower.LowerEmitCandidate` leaves, plus Loop/Fragment/Value types | ✅ clean leaf methods |
| `code_to_c.lua` | **1358** | `Code.CodeType` leaves, `Code.CodeConst` leaves, `Code.CodePlace` leaves, `Code.CodeValueId`, `Code.CodeInstOp` leaves, `Code.CodeGlobalRef` leaves | ✅ clean leaf methods; very large per-receiver-type |
| `emit_c_materialize.lua` | 259 | C value/place materialization helpers | — inline into impl |
| `lower_kernel_rewrite.lua` | 285 | `Value.Reduction` leaves (`:display_name()`), `Stencil.StencilScan` leaves | ✅ leaf methods; inline into impl |
| `emit_c_validate.lua` | 470 | CBackendUnit validation | — inline into impl or separate `impl/cemit_validate.lua` |

#### `impl/cemit_emit.lua` — :emit_artifact() on CEmitMachine types

| Old file | Lines | Receiver types | Clean? |
|----------|-------|----------------|--------|
| `emit_c_lower.lua` | **1415** | `Core.Scalar` leaves, `Core.Literal` leaves, `Core.CmpOp` leaves, `Exec.ExecFragmentBody` leaves, C type emission methods | ✅ clean leaf methods |

### 15.5 BACKEND PHASES

#### `impl/luajit_lower.lua` — LuaJIT-specific lowering

| Old file | Lines | Receiver types | Clean? |
|----------|-------|----------------|--------|
| `luajit_lower.lua` | **2133** | Code, Value, Stencil, Mem types — LuaJIT-specific lowering methods | ❌ **heavy `asdl.classof` dispatch** |
| `luajit_emit.lua` | 1292 | LuaJIT bytecode/IR emission methods | ⚠️ method installations + functional helpers |
| `luajit_expr.lua` | 277 | LuaJIT expression lowering | ❌ **heavy `asdl.classof` dispatch** |
| `luajit_ctype.lua` | 375 | C type mapping for LuaJIT FFI | — functional helpers |
| `luajit_measure.lua` | 156 | LuaJIT IR size measurement | — utility |
| `residual_luatrace.lua` | 1651 | LuaJIT bytecode trace emission | ⚠️ method installations + functional |
| `residual_bc.lua` | 118 | LuaJIT bytecode helpers | — utility |

#### Native backend (DEFERRED — not in v2 scope)

| Old file | Lines | Receiver types | Clean? |
|----------|-------|----------------|--------|
| `native_backend.lua` | 216 | Composition driver — wires native, native_mc, native_code_methods, native_kernel_methods, native_stencil_methods | — composition |
| `native.lua` | 1997 | `Native.NativeAxis` leaves, `Native.NativeCompileResult` — native bank operations | ✅ leaf methods |
| `native_code_methods.lua` | **3926** | Code type → native template lowering | ✅ leaf methods; enormous |
| `native_kernel_methods.lua` | 1587 | Kernel type → native template lowering | ✅ leaf methods |
| `native_stencil_methods.lua` | 976 | Stencil type → native template lowering | ✅ leaf methods |
| `native_mc.lua` | 1164 | Native machine-code operations (patching, assembly) | ✅ leaf methods |
| `native_object.lua` | 397 | `Native.NativeTemplateBytes` (`:parse_native_object()`) | ✅ method installation |
| `native_template_sources.lua` | **6674** | C template source strings | — data file, not implementation |
| `native_template_support.lua` | 2006 | Template parsing, validation, source decomposition | — utility |

### 15.6 STENCIL PHASES

#### Cross-cutting: `stencil_artifact_plan.lua`

| Old file | Lines | Receiver types | Clean? |
|----------|-------|----------------|--------|
| `stencil_artifact_plan.lua` | **2767** | `Code.CodeTy` leaves, `Value.Reduction` leaves, `Code.CodeType` leaves, plus Stencil, Schedule, Kernel, Mem types | ✅ clean leaf methods; **must be split by receiver type into relevant impl/ files** — this file installs methods on 7+ modules

#### Other stencil files

| Old file | Lines | Receiver types | Clean? |
|----------|-------|----------------|--------|
| `stencil_methods.lua` | 931 | `SM.StencilMachinePointInput` leaves, `Code.CodeConst`, `Value.ValueExpr`, `Core.UnaryOp`, `Core.BinaryOp`, `Code.CodeType` | ✅ clean leaf methods; split by receiver |
| `stencil_metastencil.lua` | 743 | `Stencil.StencilDescriptor`, `Stencil.StencilReduceScope` leaves | ✅ leaf methods |
| `stencil_c.lua` | 1554 | C-specific stencil emission | — method installations + functional |

### 15.7 COMPILER COMPOSITION / INFRASTRUCTURE

#### `impl/compiler_result.lua` — report methods on CodeResult types

| Old file | Lines | Receiver types | Clean? |
|----------|-------|----------------|--------|
| `compiler_abi.lua` | 96 | CodeResult validation | ✅ clean |

#### `impl/exec_plan.lua` — execution plan methods

| Old file | Lines | Receiver types | Clean? |
|----------|-------|----------------|--------|
| `exec_plan.lua` | 224 | `Kernel.KernelPlanned`, `Stencil.StencilSelected`, `Exec.ExecStencilSelection` leaves | ✅ clean leaf methods |

### 15.8 FILES THAT ARE **NOT** impl/ TARGETS

These files remain as-is — they are infrastructure, runtime, data, or framework,
not ASDL method installations.

| File | Lines | Category | Why kept as-is |
|------|-------|----------|---------------|
| `emit_c_compile.lua` | 258 | Runtime | GCC runner — takes C text, compiles, dlopens, returns function pointers |
| `emit_c_tcc.lua` | 365 | Runtime | TCC (Tiny C Compiler) runner |
| `emit_c_coverage.lua` | 348 | Utility | C phase-unreachable variant tracking |
| `emit_c_helpers.lua` | 3 | Utility | Re-export (trivial) |
| `triplet.lua` | 1179 | Data | Architecture tuple database |
| `phase_dsl.lua` | 432 | Framework | Phase/machine/world DSL |
| `phase_execute.lua` | 222 | Framework | Phase execution engine |
| `phase_model.lua` | 23 | Framework | Phase model loading |
| `phase_plan.lua` | 279 | Framework | Phase plan construction |
| `phase_validate.lua` | 292 | Framework | Phase plan validation |
| `link_command_plan.lua` | 156 | Framework | Link command planning |
| `link_execute.lua` | 99 | Framework | Link execution |
| `link_plan_validate.lua` | 171 | Framework | Link plan validation |
| `link_target_model.lua` | 49 | Framework | Link target model |
| `compiler_package.lua` | 111 | Framework | Defines compiler worlds, machines, phases in DSL |
| `compiler_machines.lua` | 71 | Framework | Machine implementations for compiler_package |
| `compiler_model.lua` | 19 | Framework | Schema loading |
| `compiler_driver.lua` | 41 | Framework | Public `lower_module` entrypoint |
| `schema_context.lua` | 865 | Infrastructure | ASDL runtime context |
| `schema_projection.lua` | 22 | Infrastructure | Schema projection |
| `schema_projection_model.lua` | 142 | Infrastructure | Projection model |
| `schema_runtime.lua` | 70 | Infrastructure | Schema runtime |
| `schema_types.lua` | 78 | Infrastructure | Schema type utilities |
| `schema_emit_types.lua` | 141 | Infrastructure | Schema emit types |
| `context_define_schema.lua` | 126 | Infrastructure | Context schema definition |
| `asdl.lua` | 575 | Infrastructure | ASDL runtime core |
| `ast.lua` | 1131 | Infrastructure | AST construction utilities |
| `loader.lua` | 151 | Infrastructure | Module loader |
| `store.lua` | 210 | Infrastructure | Object store |
| `exotype.lua` | 362 | Infrastructure | Exotype support |
| `cli.lua` | 72 | Infrastructure | CLI entry point |
| `source_anchor_index.lua` | 154 | Utility | Source anchor indexing |
| `source_position_index.lua` | 221 | Utility | Source position indexing |
| `source_text_apply.lua` | 167 | Utility | Text edit application |
| `source_analysis.lua` | 59 | Utility | Source analysis helpers |
| `project_asdl.lua` | 23 | Utility | Project ASDL loading |
| `project_ready_facts.lua` | 121 | Utility | Project ready facts |
| `project_report.lua` | 87 | Utility | Project report generation |
| `bind_machine_binding.lua` | 78 | Utility | Machine binding helpers |
| `bind_residence_decide.lua` | 121 | Utility | Residence decision |
| `bind_residence_gather.lua` | 629 | Utility | Residence gathering |
| `backend_target_model.lua` | 70 | Utility | Default target model construction |
| `code_type.lua` | 533 | Utility | Code type helpers — type_to_code, classification, C target defaults |
| `type_size_align.lua` | 286 | Utility | Size/alignment computation |
| `func_abi_plan.lua` | 80 | Utility | Function ABI planning |
| `code_aggregate_abi.lua` | 154 | Utility | Aggregate ABI helpers |
| `value_proxy.lua` | 178 | Utility | Value proxy helpers |
| `quote.lua` | 153 | Utility | Code quoting |
| `frontend_pipeline.lua` | 267 | Legacy composition | Will be replaced by `pipeline.lua` |
| `init.lua` | 936 | Public API | Facade; exposes `loadstring`, `loadfile`, `compile_c_gcc`, `compile` — kept |

### 15.9 FORBIDDEN PATTERN HOTSPOTS

These files use `schema.classof` dispatch or handler maps and need leaf methods
before migration is complete:

| File | Severity | What it does | Fix |
|------|----------|-------------|-----|
| `tree_control_facts.lua` | **HIGH** | Control flow fact computation — all dispatch via `schema.classof` | Replace with leaf methods on `Tr.Stmt` / `Tr.ControlBlock` / `Tr.Region` types |
| `tree_contract_facts.lua` | **HIGH** | Contract fact extraction — all dispatch via `schema.classof` | Replace with leaf methods on `Tr.FuncContract` / `Tr.Expr` types |
| `code_effect_facts.lua` | MEDIUM | Contract → effect conversion uses `asdl.classof` on contract types | Install `:to_effect_fact()` on each contract leaf |
| `kernel_validate.lua` | **HIGH** | Kernel plan validation — heavy `asdl.classof` throughout | Replace with leaf methods on `Kernel.*` result types |
| `luajit_lower.lua` | **HIGH** | LuaJIT lowering — heavy `asdl.classof` on Code types | Replace with leaf methods on Code types (deferred — LuaJIT backend not in v2 scope) |
| `luajit_expr.lua` | **HIGH** | LuaJIT expression lowering — heavy `asdl.classof` | Same as above — deferred |
| `core_scalar.lua` | LOW | Core scalar classification helpers | Delete — methods should be leaf methods on `Core.Scalar` union |
| `core_operator.lua` | LOW | Core operator classification | Delete — methods should be leaf methods on `Core.BinaryOp`, `Core.UnaryOp`, etc. |
| `type_classify.lua` | LOW | Type classification via `schema.classof` | Delete — methods should be leaf methods on `Ty.Type` union |
| `type_abi_classify.lua` | LOW | ABI classification via `schema.classof` | Delete — already partially replaced; remaining methods should be leaf methods on `Ty.Type` |

### 15.10 THE `Code.CodeType` OVERLOAD

Methods on `Code.CodeType` are installed by **five** different phase files.
This is legitimate — `Code.CodeType` is a stable entity and different phases
answer different questions about it. Do not create a monolithic
`impl/code_type.lua`. Keep methods distributed by phase.

| Method family | Installed by | Phase | Impl target |
|--------------|-------------|-------|-------------|
| `tree_code_is_float_type()`, `tree_code_is_aggregate_type()`, `tree_code_is_view_type()`, `tree_code_index_cast_op()` | `tree_lower.lua` | Tree→Code lowering | `impl/tree_code.lua` |
| `code_to_c_variant_payload_union_id()`, `code_to_c_without_lease()`, `code_to_c_view_elem_type()`, `code_to_c_slice_elem_type()` | `code_to_c.lua` | Code→C emission | `impl/lower_emit_c.lua` |
| `stencil_artifact_type_name()`, `stencil_artifact_c_type()`, `stencil_artifact_is_code_scalar()`, `stencil_artifact_is_int()`, `stencil_artifact_is_integer_like()`, `stencil_artifact_is_float()` | `stencil_artifact_plan.lua` | Stencil artifact planning | split by receiver: Code methods → `impl/lower_emit_c.lua` or new `impl/stencil_artifact.lua` |
| `stencil_supported_type()` | `stencil_methods.lua` | Stencil selection | inline into stencil phase impl file |
| `kernel_carrier_const_amount()`, `kernel_carrier_note_def()`, `kernel_carrier_step_from_def()` | `code_kernel_plan.lua` | Kernel planning | `impl/kernel_plan.lua` |

### 15.11 MIGRATION ORDER

1. **Delete the easy helpers first** — `core_scalar.lua`, `core_operator.lua`,
   `type_classify.lua`, `type_abi_classify.lua` can be deleted once their
   methods are installed as leaf methods on the corresponding ASDL unions.
   This removes 4 forbidden-pattern files with zero semantic risk.

2. **Port the clean method-installation files** — `closure_convert.lua`,
   `tree_typecheck_type.lua`, `tree_typecheck_fact.lua`, `tree_module_type.lua`,
   `const_eval.lua`, `tree_lower.lua`, `code_graph.lua`, `code_flow_facts.lua`,
   `code_value_facts.lua`, `code_mem_facts.lua`, `code_kernel_plan.lua`,
   `code_schedule_plan.lua`, `code_lower_plan.lua`, `exec_plan.lua`. These are
   the low-risk files that already follow the leaf-method pattern.

3. **Refactor the classof hotspots** — `tree_control_facts.lua`,
   `tree_contract_facts.lua`, `code_effect_facts.lua`, `kernel_validate.lua`.
   Each must become leaf methods on the types they currently switch over.
   This is the core architectural work of Phase 2.

4. **Port the C emission files** — `lower_to_c.lua`, `code_to_c.lua`,
   `emit_c_lower.lua` plus their helpers. These are large but clean.
   Split by receiver type if a single file exceeds ~2000 lines.

5. **Split `stencil_artifact_plan.lua`** — the hardest file. Its methods span
   7 receiver modules. Sort its methods into the appropriate `impl/` files by
   receiver type. Do not keep it as a single cross-cutting file.

6. **Build `pipeline.lua`** — once all impl files exist, wire them into the
   full compilation sequence. At this point the typed path is complete and
   the legacy `frontend_pipeline.lua` can be retired.

7. **LuaJIT and Native backends** — deferred. Port when their schema modules
   are brought into v2 scope.

### 15.12 FILE SIZE SUMMARY

| Total legacy impl files mapped | ~80 |
| Files that are method-installation (impl/ targets) | ~35 |
| Files that are infrastructure/runtime/utility (kept as-is) | ~35 |
| Files with forbidden patterns (classof/handler maps) | ~10 |
| Largest file ported | `tree_lower.lua` (3067 lines) → `impl/tree_code.lua` |
| Largest combined port | `impl/lower_emit_c.lua` (~4809 lines from 5 files) |
| Hardest file to map | `stencil_artifact_plan.lua` (2767 lines, methods on 7+ modules) |
| Total lines to migrate (method-installation files only) | ~25,000 |
