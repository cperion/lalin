# Plan B — Code IR + Analysis + Kernel/Schedule/Lower Plans

**Agent:** B
**Scope:** Code graph, flow, value, mem, effect analysis + kernel/schedule/lower plans
**Lines:** ~6,000

---

## MANDATORY READING — READ THESE FILES COMPLETELY BEFORE WRITING A SINGLE LINE

1. `docs/FILE_ORGANIZATION.md` — the master architectural document. Defines schema_v2/ vs impl/, method shape, forbidden patterns.
2. `docs/ASDL_GUIDE.md` — the ASDL doctrine. Leaf methods ARE dispatch. No classof. No side tables.
3. `TARGET-SCHEMA.md` — the target architecture for schema_v2. You need to know what types exist.
4. `AUDIT-REPORT.md` — known defects and fixes applied to schema_v2.
5. `lua/lalin/schema_v2/code.lua`, `schema_v2/graph.lua`, `schema_v2/flow.lua`, `schema_v2/value.lua`, `schema_v2/mem.lua`, `schema_v2/effect.lua`, `schema_v2/kernel.lua`, `schema_v2/schedule.lua`, `schema_v2/lower.lua` — READ THE ACTUAL SCHEMA FILES. Know the type names.

**Do not skip this.** The previous attempt failed because agents didn't read the docs. Read them ALL.

---

## WHAT YOU ARE BUILDING

This is a **REWRITE, not a port.** You are NOT copy-pasting old files into impl/. You are writing NEW code that installs methods on schema_v2 ASDL types.

**The architecture:**
- `lua/lalin/schema_v2/code.lua` defines `LalinCode` schema: types like `Code.CodeFunc`, `Code.CodeBlock`, `Code.CodeInstOpBin`. These are Lua tables with metatables.
- `lua/lalin/impl/code_graph.lua` requires schema_v2 types and installs methods: `function Code.CodeFunc:build_graph() ... end`
- When code calls `some_func:build_graph()`, Lua's metatable dispatches to the correct leaf method.

**The method shape:**
```lua
-- impl/code_graph.lua
local Code = require("lalin.schema_v2.code")
local Graph = require("lalin.schema_v2.graph")

function Code.CodeFunc:build_graph()
  -- Create basic blocks, connect via terminators, build use-def chains
  return Graph.CodeGraph(...)
end

function Code.CodePlaceLocal:code_graph_dst()
  return Graph.GraphNode(...)
end
```

**The old code provides LOGIC, not STRUCTURE.** Read `lua/lalin/code_graph.lua` to understand what logic each function performs, then write that logic as a leaf method on the concrete ASDL type. Do NOT require the old file. Do NOT wrap it. Do NOT (T)-call it.

---

## FORBIDDEN — IF YOU DO ANY OF THESE, YOU FAIL

```lua
-- FAIL: requiring old implementation files
local old = require("lalin.code_graph")(T)  -- NO. NEVER.

-- FAIL: classof dispatch
if asdl.classof(expr) == Code.CodePlaceLocal then  -- NO. Write Code.CodePlaceLocal:method() instead.

-- FAIL: handler maps
local handlers = { CodePlaceLocal = f1, CodePlaceGlobal = f2 }  -- NO. Leaf methods.

-- FAIL: side tables / caches keyed by nodes
local cache = {}  -- NO. Use ASDL interned products or method parameters.

-- FAIL: trying to make the file 'runnable'
-- Do NOT add test code. Do NOT add wrappers. Do NOT try to require() and run it.
-- The file installs methods. That's it. pipeline.lua calls them later.

-- FAIL: compatibility shims or links to old code
-- Do NOT add wrappers that delegate to the old implementation.
-- This is a REWRITE. New code only.

-- FAIL: kind-string dispatch
if expr.kind == "CodePlaceLocal" then  -- NO. Leaf method on Code.CodePlaceLocal.
```

**The only verification:** `luajit -e "require('lalin.impl.code_graph')"` must not error. That's it. Not 'works'. Not 'runs'. Just loads.

---

## HOW TO APPROACH EACH FILE

1. Read the old source file(s) listed for the impl file you're writing. Understand the LOGIC.
2. Read the schema_v2 file(s) for the types you're installing methods on. Know the TYPE NAMES.
3. Write `lua/lalin/impl/xxx.lua`. Start with `require("lalin.schema_v2.xxx")` statements.
4. For each function in the old file: identify the receiver type, write `function ReceiverType:method_name(params) ... end`
5. If the old code uses `classof` to branch on type X vs Y: write a separate method on each concrete leaf.
6. After writing the file: `luajit -e "require('lalin.impl.xxx')"`. If it errors, fix it. If it loads, commit.

---

## FILE INVENTORY

---

## FILE INVENTORY

| # | Impl file | Lines (est.) | Old source files | Clean? |
|---|-----------|-------------|------------------|--------|
| 1 | `impl/code_graph.lua` | ~420 | `code_graph.lua` | ✅ clean |
| 2 | `impl/code_flow.lua` | ~580 | `code_flow_facts.lua` | ✅ clean |
| 3 | `impl/code_value.lua` | ~870 | `code_value_facts.lua` + `reduction_algebra.lua` | ✅ clean |
| 4 | `impl/code_mem.lua` | ~780 | `code_mem_facts.lua` | ✅ clean |
| 5 | `impl/code_effect.lua` | ~220 | `code_effect_facts.lua` | ❌ classof |
| 6 | `impl/kernel_plan.lua` | ~2360 | `code_kernel_plan.lua` + `kernel_validate.lua` + `kernel_emit_support.lua` | ❌ classof in kernel_validate |
| 7 | `impl/schedule_plan.lua` | ~200 | `code_schedule_plan.lua` | ✅ clean |
| 8 | `impl/lower_plan.lua` | ~490 | `code_lower_plan.lua` | ✅ clean |

---

## 1. `impl/code_graph.lua` — :build_graph() on LalinCode types

**Old file:** `code_graph.lua` (396 lines)
**Pattern:** ✅ Clean leaf methods.
**Source reference:** Read `lua/lalin/code_graph.lua` fully before starting.

### What it does
Constructs the control-flow graph (CFG) and use-def chains from flat Code IR. Each CodeFunc becomes a CodeGraph with basic blocks, edges, and use-def links.

### Method signatures

```lua
-- Entry point:
function Code.CodeFunc:build_graph() → Graph.CodeGraph
  -- Creates basic blocks from CodeBlock list
  -- Connects blocks via CodeTerm branch targets
  -- Builds use-def chains for CodeValueIds
  -- Returns complete CodeGraph

function Code.CodeModule:build_graph() → [many Graph.CodeGraph]
  -- Builds graph for every function in the module

-- On LalinCode.CodePlace leaves (source/destination of data flow):
function Code.CodePlaceLocal:code_graph_dst() → Graph.GraphNode
  -- Returns the graph node representing the destination of this place
function Code.CodePlaceGlobal:code_graph_dst() → Graph.GraphNode
function Code.CodePlaceParam:code_graph_dst() → Graph.GraphNode
function Code.CodePlaceField:code_graph_dst() → Graph.GraphNode
function Code.CodePlaceIndex:code_graph_dst() → Graph.GraphNode
-- ... every CodePlace leaf

function Code.CodePlaceLocal:code_graph_append_uses(uses_builder, def) → void
  -- Records that this place is used by the given definition
function Code.CodePlaceGlobal:code_graph_append_uses(uses_builder, def) → void
-- ... every CodePlace leaf

-- On LalinCode.CodeCallTarget leaves:
function Code.CodeCallTargetDirect:code_graph_resolve_target(module) → Code.CodeFunc
  -- Resolves the target of a direct call
function Code.CodeCallTargetIndirect:code_graph_resolve_target(module) → Code.CodeFunc | nil
  -- Indirect call — may resolve to an unknown target
function Code.CodeCallTargetIntrinsic:code_graph_resolve_target(module) → Code.CodeFunc | nil
  -- Intrinsic call — handled specially

-- On LalinCode.CodeInstOp leaves:
function Code.CodeInstOpBin:code_graph_operands() → [many Code.CodeValueId]
  -- Returns the operand value IDs for this instruction
function Code.CodeInstOpUn:code_graph_operands() → [many Code.CodeValueId]
function Code.CodeInstOpCall:code_graph_operands() → [many Code.CodeValueId]
function Code.CodeInstOpLoad:code_graph_operands() → [many Code.CodeValueId]
function Code.CodeInstOpStore:code_graph_operands() → [many Code.CodeValueId]
-- ... every CodeInstOp leaf

-- On LalinCode.CodeTerm leaves:
function Code.CodeTermBranch:code_graph_targets() → [many Code.CodeBlockId]
  -- Returns the target blocks of this terminator
function Code.CodeTermCondBranch:code_graph_targets() → [many Code.CodeBlockId]
function Code.CodeTermReturn:code_graph_targets() → [many Code.CodeBlockId]  -- empty
function Code.CodeTermSwitch:code_graph_targets() → [many Code.CodeBlockId]
function Code.CodeTermUnreachable:code_graph_targets() → [many Code.CodeBlockId]  -- empty
-- ... every CodeTerm leaf
```

---

## 2. `impl/code_flow.lua` — :compute_flow() on LalinGraph types

**Old file:** `code_flow_facts.lua` (555 lines)
**Pattern:** ✅ Clean leaf methods.
**Source reference:** Read `lua/lalin/code_flow_facts.lua` fully before starting.

### What it does
Computes control-flow facts: loop detection, trip count bounds, induction variable analysis, dominator tree, carrier identification.

### Method signatures

```lua
-- Entry point:
function Graph.CodeGraph:compute_flow(module) → Flow.FlowFactSet
  -- module: Code.CodeModule (for context)
  -- Detects loops (back edges → natural loops)
  -- Computes dominator tree
  -- For each loop: computes trip count bounds, identifies induction variables
  -- Returns FlowFactSet with all flow facts

-- On LalinFlow.FlowTripCount leaves:
function Flow.FlowTripCountKnown:flow_analysis_summary() → Flow.TripCountSummary
  -- Known trip count → returns the count
function Flow.FlowTripCountBounded:flow_analysis_summary() → Flow.TripCountSummary
  -- Bounded trip count → returns min/max
function Flow.FlowTripCountUnknown:flow_analysis_summary() → Flow.TripCountSummary
  -- Unknown trip count → returns "unknown"

-- On LalinFlow.FlowLoop leaves:
function Flow.FlowLoopNatural:compute_loop_facts(dom_tree, cfg) → [many Flow.FlowFact]
  -- Analyzes a natural loop: identifies loop header, latch, exit blocks
  -- Computes loop-invariant values
  -- Identifies induction variables and their stride/direction

-- On LalinFlow.FlowCarrier leaves:
function Flow.FlowCarrierTransfer:flow_carrier_analysis(loop, flow_facts) → Flow.FlowFact
  -- Analyzes a carrier that transfers data between loop iterations
function Flow.FlowCarrierThread:flow_carrier_analysis(loop, flow_facts) → Flow.FlowFact
  -- Analyzes a carrier that threads a value through loop iterations
function Flow.FlowCarrierAccumulator:flow_carrier_analysis(loop, flow_facts) → Flow.FlowFact
  -- Analyzes an accumulator (reduction-style carrier)

-- On LalinFlow.FlowProof leaves:
function Flow.FlowProofAuthoritative:flow_proof_validate(facts) → bool
  -- Validates that a flow proof is authoritative (proven by analysis)

-- On LalinGraph.EdgeKind leaves:
function Graph.EdgeKindBranch:edge_analysis(dom_tree) → Flow.FlowFact
function Graph.EdgeKindBackEdge:edge_analysis(dom_tree) → Flow.FlowFact
  -- Back edge: this edge creates a loop

-- On LalinGraph.UseRole leaves:
function Graph.UseRoleDef:use_analysis(value_id, graph) → Graph.UseInfo
function Graph.UseRoleUse:use_analysis(value_id, graph) → Graph.UseInfo
```

---

## 3. `impl/code_value.lua` — :compute_values() on LalinGraph types

**Old files:** `code_value_facts.lua` (625 lines), `reduction_algebra.lua` (212 lines)
**Pattern:** ✅ Clean leaf methods.
**Source reference:** Read both old files fully before starting.

### What it does
Computes value facts: constant propagation, algebraic simplification, reduction recognition, value expression construction.

### Method signatures

```lua
-- Entry point:
function Graph.CodeGraph:compute_values(module, flow) → Value.ValueFactSet
  -- module: Code.CodeModule
  -- flow: Flow.FlowFactSet (for loop context)
  -- Walks the use-def chain, constructs ValueExpr for each value
  -- Performs constant propagation and folding
  -- Recognizes reduction patterns
  -- Returns ValueFactSet with all value facts

-- On LalinCore.BinaryOp leaves:
function Core.BinaryOpAdd:value_algebra(lhs, rhs) → Value.ValueExpr
  -- Constructs an algebraic expression for this binary op
  -- May simplify: 0 + x → x, x + 0 → x
function Core.BinaryOpSub:value_algebra(lhs, rhs) → Value.ValueExpr
  -- Simplification: x - 0 → x, x - x → 0
function Core.BinaryOpMul:value_algebra(lhs, rhs) → Value.ValueExpr
  -- Simplification: 1 * x → x, 0 * x → 0
function Core.BinaryOpDiv:value_algebra(lhs, rhs) → Value.ValueExpr
  -- Simplification: x / 1 → x
-- ... every BinaryOp leaf

-- On LalinCore.UnaryOp leaves:
function Core.UnaryOpNeg:value_algebra(operand) → Value.ValueExpr
  -- Simplification: -(-x) → x
function Core.UnaryOpNot:value_algebra(operand) → Value.ValueExpr
  -- Simplification: !!x → x
function Core.UnaryOpBitNot:value_algebra(operand) → Value.ValueExpr
-- ... every UnaryOp leaf

-- On LalinCore.CmpOp leaves:
function Core.CmpOpEq:value_algebra(lhs, rhs) → Value.ValueExpr
function Core.CmpOpLt:value_algebra(lhs, rhs) → Value.ValueExpr
-- ... every CmpOp leaf

-- On LalinCode.CodeInstOp leaves:
function Code.CodeInstOpBin:compute_value(value_facts, flow_facts) → Value.ValueExpr
  -- Constructs a value expression for this binary instruction
  -- Looks up operand value expressions from value_facts
  -- May simplify: constant folding, identity operations
function Code.CodeInstOpUn:compute_value(value_facts, flow_facts) → Value.ValueExpr
function Code.CodeInstOpCall:compute_value(value_facts, flow_facts) → Value.ValueExpr
  -- Call result: opaque value expression, no simplification
function Code.CodeInstOpLoad:compute_value(value_facts, flow_facts) → Value.ValueExpr
  -- Load: mem-dependent value expression
function Code.CodeInstOpAlloca:compute_value(value_facts, flow_facts) → Value.ValueExpr
  -- Alloca: produces a pointer value
function Code.CodeInstOpCast:compute_value(value_facts, flow_facts) → Value.ValueExpr
  -- Cast: may simplify (no-op casts)
function Code.CodeInstOpGep:compute_value(value_facts, flow_facts) → Value.ValueExpr
  -- GetElementPtr: constructs address expression
function Code.CodeInstOpPhi:compute_value(value_facts, flow_facts) → Value.ValueExpr
  -- Phi: constructs phi value expression
-- ... every CodeInstOp leaf

-- On LalinValue.ValueExpr leaves (from reduction_algebra.lua):
function Value.ValueExprBin:simplify() → Value.ValueExpr
  -- Algebraic simplification of a binary expression tree
function Value.ValueExprUn:simplify() → Value.ValueExpr
function Value.ValueExprConst:simplify() → Value.ValueExpr  -- identity
function Value.ValueExprPhi:simplify() → Value.ValueExpr
function Value.ValueExprReduction:simplify() → Value.ValueExpr
-- ... every ValueExpr leaf

-- On LalinValue.Reduction leaves:
function Value.ReductionSum:reduction_identity_value() → Value.ValueExpr
  -- Returns 0 (identity for sum)
function Value.ReductionProd:reduction_identity_value() → Value.ValueExpr
  -- Returns 1 (identity for product)
function Value.ReductionMin:reduction_identity_value() → Value.ValueExpr
  -- Returns +inf (identity for min)
function Value.ReductionMax:reduction_identity_value() → Value.ValueExpr
  -- Returns -inf (identity for max)
function Value.ReductionAnd:reduction_identity_value() → Value.ValueExpr
  -- Returns true
function Value.ReductionOr:reduction_identity_value() → Value.ValueExpr
  -- Returns false
-- ... every Reduction leaf

function Value.ReductionSum:reduction_apply(accum, value) → Value.ValueExpr
  -- Returns accum + value
function Value.ReductionProd:reduction_apply(accum, value) → Value.ValueExpr
  -- Returns accum * value
-- ... every Reduction leaf

-- On LalinValue.AlgebraProof leaves:
function Value.AlgebraProofProven:algebra_proof_is_valid() → bool  -- true
function Value.AlgebraProofAssumed:algebra_proof_is_valid() → bool  -- false (assumed)
function Value.AlgebraProofTrivial:algebra_proof_is_valid() → bool  -- true
-- ... every AlgebraProof leaf
```

---

## 4. `impl/code_mem.lua` — :compute_mem() on LalinGraph types

**Old file:** `code_mem_facts.lua` (752 lines)
**Pattern:** ✅ Clean leaf methods.
**Source reference:** Read `lua/lalin/code_mem_facts.lua` fully before starting.

### What it does
Computes memory facts: object identification, access classification, aliasing analysis, proof derivation, bounds checking.

### Method signatures

```lua
-- Entry point:
function Graph.CodeGraph:compute_mem(module, flow, values, contracts) → Mem.MemSemanticFactSet
  -- module: Code.CodeModule
  -- flow: Flow.FlowFactSet
  -- values: Value.ValueFactSet
  -- contracts: from lowering phase (contract facts attached to functions)
  -- Identifies memory objects (locals, globals, params, views, slices, etc.)
  -- Classifies memory accesses (loads, stores, field/element accesses)
  -- Computes aliasing: which objects may alias
  -- Derives memory proofs from contracts and analysis
  -- Checks bounds for array/view accesses
  -- Returns MemSemanticFactSet with all memory facts

-- On LalinMem.MemProof leaves (guarantee cascade — the doctrinal centerpiece):
function Mem.MemProofExclusive:mem_proof_guarantee() → Mem.MemGuarantee
  -- Exclusive access: no other access to this object
function Mem.MemProofShared:mem_proof_guarantee() → Mem.MemGuarantee
  -- Shared access: read-only sharing
function Mem.MemProofUnsafe:mem_proof_guarantee() → Mem.MemGuarantee
  -- Unsafe access: unrestricted
function Mem.MemProofLease:mem_proof_guarantee() → Mem.MemGuarantee
  -- Lease: temporary exclusive access, returned after
function Mem.MemProofBorrow:mem_proof_guarantee() → Mem.MemGuarantee
  -- Borrow: temporary shared access
function Mem.MemProofMove:mem_proof_guarantee() → Mem.MemGuarantee
  -- Move: ownership transfer
function Mem.MemProofFrozen:mem_proof_guarantee() → Mem.MemGuarantee
  -- Frozen: immutable after this point
function Mem.MemProofDerived:mem_proof_guarantee() → Mem.MemGuarantee
  -- Derived: field/element access derives proof from parent
function Mem.MemProofContract:mem_proof_guarantee() → Mem.MemGuarantee
  -- Contract: user-declared proof
-- Every one of the 9 proof unions, each with 3-4 typed guarantee leaves

function Mem.MemProofExclusive:mem_proof_combine(other) → Mem.MemProof
  -- Combine two proofs for the same access path
function Mem.MemProofShared:mem_proof_combine(other) → Mem.MemProof
-- ... every MemProof leaf

-- On LalinMem.MemAccessProjection leaves:
function Mem.MemAccessProjectionDirect:mem_access_object() → Mem.MemObjectId
  -- Direct access to an object
function Mem.MemAccessProjectionField:mem_access_object() → Mem.MemObjectId
  -- Field access — returns the parent object
function Mem.MemAccessProjectionElement:mem_access_object() → Mem.MemObjectId
  -- Element access — returns the parent object
function Mem.MemAccessProjectionBytes:mem_access_object() → Mem.MemObjectId
  -- Byte-span access — returns the parent object

-- On LalinMem.MemObjectForm leaves:
function Mem.MemObjectParam:mem_object_layout() → Sem.MemLayout
  -- Returns the memory layout for this object category
function Mem.MemObjectLocal:mem_object_layout() → Sem.MemLayout
function Mem.MemObjectGlobal:mem_object_layout() → Sem.MemLayout
function Mem.MemObjectData:mem_object_layout() → Sem.MemLayout
function Mem.MemObjectView:mem_object_layout() → Sem.MemLayout
function Mem.MemObjectSlice:mem_object_layout() → Sem.MemLayout
function Mem.MemObjectByteSpan:mem_object_layout() → Sem.MemLayout
function Mem.MemObjectContract:mem_object_layout() → Sem.MemLayout
function Mem.MemObjectFieldProjection:mem_object_layout() → Sem.MemLayout
function Mem.MemObjectPtrOffset:mem_object_layout() → Sem.MemLayout
function Mem.MemObjectBytes:mem_object_layout() → Sem.MemLayout
function Mem.MemObjectElement:mem_object_layout() → Sem.MemLayout
function Mem.MemObjectLease:mem_object_layout() → Sem.MemLayout
-- ... every MemObjectForm leaf

-- On LalinMem.MemBase leaves:
function Mem.MemBaseKnown:mem_base_validate(access_size, access_offset, object_layout) → Mem.MemBaseCheckResult
  -- Known base: check if the access is within bounds
function Mem.MemBaseUnknown:mem_base_validate(access_size, access_offset, object_layout) → Mem.MemBaseCheckResult
  -- Unknown base: report that bounds cannot be checked
  -- The `reason [str]` is terminal diagnostic — keep as-is per audit

-- On LalinMem.MemBounds leaves:
function Mem.MemBoundsKnown:mem_bounds_check(access_size, access_offset) → Mem.MemBoundsCheckResult
function Mem.MemBoundsUnknown:mem_bounds_check(access_size, access_offset) → Mem.MemBoundsCheckResult
  -- Terminal diagnostic — keep reason [str]

-- On LalinMem.MemProv leaves:
function Mem.MemProvKnown:mem_provenance_chain() → [many Mem.MemProof]
  -- Returns the chain of proofs that establish this provenance
function Mem.MemProvUnknown:mem_provenance_chain() → [many Mem.MemProof]
  -- Unknown provenance — terminal diagnostic

-- On LalinMem.MemNonTrapping:
function Mem.MemNonTrapping:mem_trap_reason() → str
  -- Terminal diagnostic

-- On LalinMem.MemCheckedTrap:
function Mem.MemCheckedTrap:mem_trap_reason() → str
  -- Terminal diagnostic
```

---

## 5. `impl/code_effect.lua` — :compute_effects() on LalinGraph types

**Old file:** `code_effect_facts.lua` (183 lines)
**Pattern:** ❌ `asdl.classof` dispatch on contract classes. MUST be refactored.
**Source reference:** Read `lua/lalin/code_effect_facts.lua` fully before starting.

### What it does
Converts contract facts into effect facts. For each function: analyze its side effects (memory reads/writes, external calls, allocation).

### Refactoring the classof dispatch

The old code switches on contract type with `asdl.classof`. Replace with leaf methods:

```lua
-- Entry point:
function Graph.CodeGraph:compute_effects(module, mem, contracts) → Effect.EffectFactSet
  -- module: Code.CodeModule
  -- mem: Mem.MemSemanticFactSet
  -- contracts: contract facts per function
  -- For each function, derives effect facts from contracts + memory analysis
  -- Returns EffectFactSet

-- On LalinSem.FuncContractFact leaves (contract → effect conversion):
function Sem.FuncContractFactPure:to_effect_fact(func, mem_facts) → Effect.EffectFact
  -- Pure contract → no side effects
function Sem.FuncContractFactNoAlias:to_effect_fact(func, mem_facts) → Effect.EffectFact
  -- No-alias contract → specific parameters don't alias
function Sem.FuncContractFactNoEscape:to_effect_fact(func, mem_facts) → Effect.EffectFact
  -- No-escape contract → no pointers escape
function Sem.FuncContractFactTerminates:to_effect_fact(func, mem_facts) → Effect.EffectFact
  -- Terminates contract → always returns (can be used for DCE)
function Sem.FuncContractFactCaptures:to_effect_fact(func, mem_facts) → Effect.EffectFact
  -- Captures contract → explicit capture set
-- ... every contract fact leaf

-- On LalinEffect.OpEffect leaves:
function Effect.OpEffectRead:effect_summary() → Effect.EffectSummary
  -- Read effect: reads from the listed memory objects
function Effect.OpEffectWrite:effect_summary() → Effect.EffectSummary
  -- Write effect: writes to the listed memory objects
function Effect.OpEffectCall:effect_summary() → Effect.EffectSummary
  -- Call effect: delegates to callee's effect summary
function Effect.OpEffectAlloc:effect_summary() → Effect.EffectSummary
  -- Alloc effect: allocates memory (object appears)
function Effect.OpEffectFree:effect_summary() → Effect.EffectSummary
  -- Free effect: deallocates memory (object disappears)
-- ... every OpEffect leaf

-- On LalinEffect.EffectAtomic leaves:
function Effect.EffectAtomicReadOnly:effect_atomic_scope() → Effect.AtomicScope
function Effect.EffectAtomicWriteOnly:effect_atomic_scope() → Effect.AtomicScope
function Effect.EffectAtomicReadWrite:effect_atomic_scope() → Effect.AtomicScope
-- Typed EffectAtomic (from audit fix)

-- CallSummary:
function Effect.EffectCallSummary:call_effect_merge(callee_effects) → Effect.EffectFact
  -- Merges callee effects into the caller's effect set

-- Terminal catch-alls (keep as-is per audit — genuinely open-ended):
function Effect.EffectObjectUnknown:effect_unknown_reason() → str
function Effect.EffectUnknown:effect_unknown_reason() → str
```

---

## 6. `impl/kernel_plan.lua` — :plan_kernels() on fact set types

**Old files:** `code_kernel_plan.lua` (1625 lines), `kernel_validate.lua` (261 lines), `kernel_emit_support.lua` (395 lines)
**Pattern:** ✅ Clean leaf methods (code_kernel_plan), ❌ classof dispatch (kernel_validate)
**Source reference:** Read all three old files fully before starting.

### What it does
Plans kernel execution: identifies loop nests suitable for kernel compilation, selects kernel skeletons, plans loop-carried dependencies, validates kernel plans.

### Method signatures (code_kernel_plan.lua — clean port)

```lua
-- Entry point:
function Mem.MemSemanticFactSet:plan_kernels(flow, values, mem, effects) → Kernel.KernelModulePlan
  -- flow: Flow.FlowFactSet
  -- values: Value.ValueFactSet
  -- mem: Mem.MemSemanticFactSet (self)
  -- effects: Effect.EffectFactSet
  -- Identifies loop candidates suitable for kernel compilation
  -- For each candidate: selects skeleton, plans carriers, validates feasibility
  -- Returns KernelModulePlan with all kernel plans

-- On LalinKernel.KernelSkeleton leaves:
function Kernel.KernelSkeletonStore:kernel_plan_candidates(loop, flow, values) → [many Kernel.KernelCandidate]
  -- Store skeleton: writes accumulated value to output
function Kernel.KernelSkeletonReduce:kernel_plan_candidates(loop, flow, values) → [many Kernel.KernelCandidate]
  -- Reduce skeleton: reduction pattern
function Kernel.KernelSkeletonScan:kernel_plan_candidates(loop, flow, values) → [many Kernel.KernelCandidate]
  -- Scan skeleton: prefix scan pattern

-- On LalinKernel.KernelSubject leaves:
function Kernel.KernelSubjectLoop:kernel_subject_analyze(loop, flow) → Kernel.KernelSubjectFacts
  -- Analyzes a loop subject: trip count, stride, direction

-- On LalinKernel.KernelLane leaves:
function Kernel.KernelLaneThread:kernel_lane_analysis(subject, flow) → Kernel.KernelLaneFacts
function Kernel.KernelLaneVector:kernel_lane_analysis(subject, flow) → Kernel.KernelLaneFacts
function Kernel.KernelLaneSeq:kernel_lane_analysis(subject, flow) → Kernel.KernelLaneFacts

-- On LalinKernel.KernelRewrite leaves:
function Kernel.KernelRewriteSplit:kernel_rewrite_apply(code) → Code.CodeModule
  -- Applies a rewrite to the code module (skeleton specialization)

-- On LalinKernel.KernelLoopPlanClosedForm leaves:
function Kernel.KernelLoopPlanClosedForm:closed_form_validate(flow, values) → Kernel.KernelValidationResult
  -- Validates that the closed form is correct

-- Code.CodeType methods installed during kernel planning:
function Code.CodeType:kernel_carrier_const_amount() → number | nil
  -- Returns constant amount for carrier (if constant)
function Code.CodeType:kernel_carrier_note_def() → str
  -- Human-readable definition note
function Code.CodeType:kernel_carrier_step_from_def() → number
  -- Step amount from definition

-- On LalinFlow.FlowCarrierTransfer:
function Flow.FlowCarrierTransfer:kernel_carrier_classify(values, mem) → Kernel.KernelCarrierFacts
-- On LalinFlow.FlowCarrierThread:
function Flow.FlowCarrierThread:kernel_carrier_classify(values, mem) → Kernel.KernelCarrierFacts
-- On LalinFlow.FlowAddressThread:
function Flow.FlowAddressThread:kernel_address_classify(mem) → Kernel.KernelAddressFacts
```

### Method signatures (kernel_validate.lua — REFACTOR classof)

```lua
-- Old code uses schema.classof to dispatch on KernelResult type.
-- Replace EVERY branch with leaf methods:

function Kernel.KernelResult:validate_kernel_plan(input) → Kernel.KernelValidationResult
  -- abstract — error

function Kernel.KernelResultPlanned:validate_kernel_plan(input) → Kernel.KernelValidationResult
  -- input: Kernel.KernelValidationInput
  -- Validates a planned kernel: all carriers resolved, skeleton applicable, target supports
function Kernel.KernelResultRejected:validate_kernel_plan(input) → Kernel.KernelValidationResult
  -- Rejected kernel: returns the rejection reason as validation result
function Kernel.KernelResultFallback:validate_kernel_plan(input) → Kernel.KernelValidationResult
  -- Fallback kernel: always valid (serial execution path)

-- On LalinKernel.KernelRejectReason leaves:
function Kernel.KernelRejectSubject:kernel_reject_explain() → str
function Kernel.KernelRejectLane:kernel_reject_explain() → str
function Kernel.KernelRejectCarrier:kernel_reject_explain() → str
-- ... every KernelRejectReason leaf

-- On LalinKernel.KernelEquivalence leaves:
function Kernel.KernelEquivalenceProven:kernel_equiv_proof() → Kernel.KernelEquivProof
function Kernel.KernelEquivalenceChecked:kernel_equiv_proof() → Kernel.KernelEquivProof
function Kernel.KernelEquivalenceAssumed:kernel_equiv_proof() → Kernel.KernelEquivProof
```

### Method signatures (kernel_emit_support.lua — functional, inline into kernel_plan)

These are helper functions. Install them as static helpers at the bottom of `impl/kernel_plan.lua` (not as methods on ASDL types), or as methods if they dispatch on types:

```lua
-- Target capability checking helpers (functional):
-- kernel_supports_skeleton(target, skeleton) → bool
-- kernel_reject_reason_emit(target, candidate) → Kernel.KernelRejectReason | nil
-- kernel_select_emitter(target, kernel_plan) → Schedule.ScheduleEmitterKind
```

---

## 7. `impl/schedule_plan.lua` — :plan_schedules() on kernel plan types

**Old file:** `code_schedule_plan.lua` (180 lines)
**Pattern:** ✅ Clean leaf methods.
**Source reference:** Read `lua/lalin/code_schedule_plan.lua` fully before starting.

### What it does
Plans execution schedules: assigns kernel plans to execution emitters, validates schedule feasibility.

### Method signatures

```lua
-- Entry point:
function Kernel.KernelModulePlan:plan_schedules(code_module, flow, values, mem, effects, target) → Schedule.ScheduleModulePlan
  -- code_module: Code.CodeModule
  -- target: backend target information
  -- For each kernel plan, selects an execution schedule form
  -- Validates schedule emitter availability
  -- Returns ScheduleModulePlan

-- On LalinSchedule.SchedulePlanInput leaves:
function Schedule.SchedulePlanInputKernel:schedule_form_select(target) → Schedule.ScheduleForm
  -- Selects the best schedule form for this kernel on this target
  -- May choose: ScheduleFormVector, ScheduleFormScalar, ScheduleFormFallback

-- On LalinSchedule.ScheduleForm leaves:
function Schedule.ScheduleFormVector:schedule_validate(capability) → Schedule.ScheduleValidateResult
function Schedule.ScheduleFormScalar:schedule_validate(capability) → Schedule.ScheduleValidateResult
function Schedule.ScheduleFormFallback:schedule_validate(capability) → Schedule.ScheduleValidateResult
  -- Fallback is always valid

-- On LalinSchedule.ScheduleEmitterKind leaves:
function Schedule.ScheduleEmitterKindCPU:schedule_emitter_capabilities(target) → Schedule.ScheduleEmitterCapability
  -- Returns CPU emitter capabilities
function Schedule.ScheduleEmitterKindGPU:schedule_emitter_capabilities(target) → Schedule.ScheduleEmitterCapability
  -- Returns GPU emitter capabilities (may be unavailable)

-- On LalinSchedule.SchedulePlanSelection leaves:
function Schedule.SchedulePlanSelectionSelected:schedule_selection_explain() → str
function Schedule.SchedulePlanSelectionRejected:schedule_selection_explain() → str
function Schedule.SchedulePlanSelectionDeferred:schedule_selection_explain() → str
```

---

## 8. `impl/lower_plan.lua` — :plan_lowering() on code + graph + kernel types

**Old file:** `code_lower_plan.lua` (462 lines)
**Pattern:** ✅ Clean leaf methods.
**Source reference:** Read `lua/lalin/code_lower_plan.lua` fully before starting.

### What it does
Plans the lowering of scheduled kernels to fragments: decomposes kernels into fragments, plans carrier transfer, resolves addresses.

### Method signatures

```lua
-- Entry point:
function Code.CodeModule:plan_lowering(graph, kernels, schedules, target) → Lower.LowerModule
  -- graph: Graph.CodeGraph (or [many])
  -- kernels: Kernel.KernelModulePlan
  -- schedules: Schedule.ScheduleModulePlan
  -- target: backend target
  -- For each scheduled kernel, plans lowering to fragments
  -- Plans fragment composition (carrier transfer between fragments)
  -- Resolves fragment addresses for linking
  -- Returns LowerModule with all lower plans

-- On LalinSchedule.KernelSchedule leaves:
function Schedule.KernelSchedulePlanned:lower_plan_fragments(graph, target) → [many Lower.LowerFragment]
  -- Decomposes a planned kernel schedule into lower fragments
  -- Each fragment is a unit of lowering (may become a separate compilation unit)

-- On LalinKernel.KernelResult leaves:
function Kernel.KernelResultPlanned:lower_plan_candidates(schedule, graph) → Lower.LowerFragmentCandidate
  -- Creates lower candidates from a planned kernel result

-- On LalinLower.LowerFragmentCandidate leaves:
function Lower.LowerFragmentCandidateStore:lower_plan_emit_strategy(target) → Lower.LowerStrategy
  -- Selects emit strategy for a store fragment
function Lower.LowerFragmentCandidateReduce:lower_plan_emit_strategy(target) → Lower.LowerStrategy
  -- Selects emit strategy for a reduce fragment
function Lower.LowerFragmentCandidateScan:lower_plan_emit_strategy(target) → Lower.LowerStrategy
  -- Selects emit strategy for a scan fragment

-- On LalinLower.LowerStrategy leaves:
function Lower.LowerStrategyDirect:lower_strategy_explain() → str
function Lower.LowerStrategyVector:lower_strategy_explain() → str
function Lower.LowerStrategyFallback:lower_strategy_explain() → str

-- On LalinFlow.FlowCarrierTransfer:
function Flow.FlowCarrierTransfer:lower_plan_carrier(graph) → Lower.LowerCarrierPlan
  -- Plans how a carrier value transfers between fragments
  -- May be: register, memory, or global

-- On LalinFlow.FlowCarrierThread:
function Flow.FlowCarrierThread:lower_plan_carrier(graph) → Lower.LowerCarrierPlan

-- On LalinFlow.FlowAddressThread:
function Flow.FlowAddressThread:lower_plan_address(mem) → Lower.LowerAddressPlan
  -- Plans how addresses thread through fragments

-- On LalinLower.LowerIssueGap leaves:
function Lower.LowerIssueGapRegister:lower_gap_resolve() → Lower.LowerGapResolution
function Lower.LowerIssueGapMemory:lower_gap_resolve() → Lower.LowerGapResolution
function Lower.LowerIssueGapGlobal:lower_gap_resolve() → Lower.LowerGapResolution

-- On LalinLower.LowerIssueFallback leaves:
function Lower.LowerIssueFallbackSplit:lower_fallback_explain() → str
function Lower.LowerIssueFallbackSerial:lower_fallback_explain() → str

-- On LalinLower.LowerFallbackKind leaves:
function Lower.LowerFallbackKindKernel:lower_fallback_strategy(target) → Lower.LowerStrategy
function Lower.LowerFallbackKindSchedule:lower_fallback_strategy(target) → Lower.LowerStrategy
```

---

## 9. COMMIT ORDER

1. `impl/code_graph.lua` — graph construction (no dependencies on other impl files)
2. `impl/code_flow.lua` — flow facts (depends on graph)
3. `impl/code_value.lua` — value facts (depends on flow for loop context)
4. `impl/code_mem.lua` — memory facts (depends on values)
5. `impl/code_effect.lua` — effect facts (depends on mem, refactored from classof)
6. `impl/kernel_plan.lua` — kernel planning (depends on all analysis facts)
7. `impl/schedule_plan.lua` — schedule planning (depends on kernel plans)
8. `impl/lower_plan.lua` — lowering plan (depends on schedules)
