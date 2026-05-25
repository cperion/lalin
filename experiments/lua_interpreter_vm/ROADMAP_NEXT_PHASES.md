# Stencil Library & JIT Implementation Roadmap

## Phase 1: ✓ COMPLETE - Architecture & Proof of Concept

**What we built:**
- Stencil generation pipeline (StateOp → Moonlift → ELF → physical bytes)
- 56 compound stencils with materialization metadata
- Verification that copy-and-patch architecture works
- 15% coverage (arithmetic + guards + basic memory)

**Verdict:** Architecture is sound. Stencils are physically valid.

---

## Phase 2: NEXT - Runtime Integration Foundation

**Goal:** Wire the JIT pipeline into the interpreter loop so we can actually execute stencils.

### 2.1: EntryCell & EdgeCell Infrastructure

**Task:** Implement mutable gates for compiled code entry/exit

```
files:
  - experiments/lua_interpreter_vm/src/jit/regions.lua
  - experiments/lua_interpreter_vm/src/jit/machines.lua

work:
  - Define EntryCell and EdgeCell data structures
  - Implement TryEnterJit region in interpreter loop
  - Add fallback to interpreter from compiled code
  - Link hot entries to executable units
```

**Acceptance:**
- Interpreter can decide to enter compiled code
- Fallback path works when stencil not available
- No crashes on edge cases

### 2.2: Trace Recording Skeleton

**Task:** Capture executed paths for evidence

```
files:
  - experiments/lua_interpreter_vm/src/jit/regions.lua

work:
  - RecordTrace region that logs StateOps as they execute
  - TraceAnchor placement at loop headers and hot exits
  - Guard and snapshot recording
  - Trace anchor hot counter
```

**Acceptance:**
- Can record a loop execution as StateOp sequence
- Guards match actual executed values
- Snapshots are accurate

### 2.3: Trace Stencil Selector (Bounded Matching)

**Task:** Select existing stencils for a recorded trace

```
files:
  - experiments/lua_interpreter_vm/src/jit/machines.lua

work:
  - Implement TraceStencilSelector as bounded maximal matching
  - Index stencils by first StateOp
  - Match largest available stencil at each step
  - Build StencilPlan from selected nodes
  - Decline compilation if no stencil matches
```

**Acceptance:**
- Can match recorded trace to existing stencils
- Produces valid StencilPlan
- Gracefully declines on unsupported ops

### 2.4: Materialization Pipeline

**Task:** Turn StencilPlan into executable code

```
files:
  - experiments/lua_interpreter_vm/src/jit/machines.lua

work:
  - SelectStencilPlan (choose variant forms)
  - LayoutStencilPlan (assign offsets, enable fallthrough)
  - MaterializeStencil (copy bytes + stamp holes)
  - FinalizeCodeBuffer (layout-dependent fixups)
  - PublishUnit (make executable)
```

**Acceptance:**
- Can materialize a StencilPlan to bytes
- Holes are correctly stamped
- Code is executable (no crashes on entry)

### 2.5: Minimum Viable Execution

**Task:** Run the MVP loop

```lua
local s = 0
for i = 1, n do
  s = s + i
end
return s
```

**What this needs:**
- EntryCell at loop header
- Trace recording of loop body
- Stencil selection for recorded trace
- Materialization of selected stencils
- Fallback when stencil unavailable

**Acceptance:**
- Loop compiles to native code
- Loop executes and produces correct result
- Fallback to interpreter works
- No memory corruption

---

## Phase 3: Expand Coverage to Real Programs

**Goal:** Add stencils for table ops, function calls, and IC infrastructure.

### 3.1: Mine Real Lua Programs

**Task:** Extract evidence from actual workloads

```
approach:
  - Run Lua-Benchmark-Games or real application
  - Capture opcode histograms
  - Trace hot paths (GETTABLE, CALL, etc.)
  - Extract table shapes and call targets
  - Build PromotionEvidence from trace motifs
```

**Output:**
- Real hotspot data
- Table/call pattern frequencies
- Shape epoch information
- Call target monomorphism rates

### 3.2: Generate Table & Call Stencils

**Task:** Use evidence to generate Ring 2 stencils

```
stencils needed:
  - table.gettable_array_i64_ic1
  - table.getfield_shape_ic1
  - table.settable_array_i64_ic1
  - call.known_lclosure
  - loop.forloop_i64_positive
  - value.load_i64.known
```

**Implementation:**
- Generate Moonlift candidates for each
- Compile to physical bytes
- Extract holes and relocations
- Add to promotion plan
- Coverage goal: 50%+ of real program hotspots

### 3.3: Add Ring 0 Boundary Stencils

**Task:** Implement ABI boundary crossing

```
stencils:
  - entry.vm_state_to_unit (enter compiled)
  - exit.to_interpreter_next (fallback)
  - outcome.ok (return to interpreter)
  - outcome.call_boundary (call from compiled)
  - outcome.error (error propagation)
  - projection.roots.bundle (GC roots)
  - projection.resume_state (yield/resume)
```

**Implementation:**
- Encode VM state transitions as Moonlift regions
- Generate stencils for each transition
- Test with GC during compiled code
- Test with error handling

### 3.4: Inline Cache Infrastructure

**Task:** Fast path + IC record mutation

```
infrastructure:
  - InlineCacheRecord data structure
  - IC stencils with fast path + slow boundary
  - IC record linking in materialization
  - Shape epoch checking
  - Polymorphic IC fallbacks
```

**Implementation:**
- Add IC stencils for table.get, table.set, call
- Implement shape guard fast path
- Add slow-path boundary
- Test shape invalidation

---

## Phase 4: Rewrite Stencils & Optimization

**Goal:** Enable plan-level optimization (DCE, guard elimination, bundling).

### 4.1: Rewrite Stencil Framework

**Task:** Plan-level transformations

```
rewrites needed:
  - rewrite.dead_pure_node (DCE)
  - rewrite.redundant_guard (guard elimination)
  - rewrite.bundle_projection_slots (projection bundling)
  - rewrite.guard_pair_add_to_supernode (pattern fusion)
```

**Implementation:**
- Represent rewrites as StencilReplacement products
- Implement rewrite application in StencilPlan
- Add verification for semantic equivalence
- Measure code size reduction

### 4.2: Iterative Refinement

**Task:** Improve units over time

```
loop:
  - Materialize unit from StencilPlan
  - Collect profile data (exit rate, branch prediction)
  - If exit rate high: rematerialize with larger stencils
  - If exit rate low: apply rewrites (DCE, bundling)
  - Relink EntryCell/EdgeCell
  - Reclaim old unit at quiescence
```

**Implementation:**
- UnitProfile data collection
- Refinement decision machine
- Version tracking for units
- GC-safe code reclamation

---

## Timeline & Scope

### Phase 2 (Weeks 1-2)
- [ ] EntryCell/EdgeCell infrastructure
- [ ] Trace recording skeleton
- [ ] TraceStencilSelector implementation
- [ ] Materialization pipeline
- [ ] MVP loop execution

**Success:** Can compile and execute simple integer loop

### Phase 3 (Weeks 3-5)
- [ ] Mine real Lua programs
- [ ] Generate table/call stencils
- [ ] Add Ring 0 boundaries
- [ ] Inline cache infrastructure

**Success:** Can compile real table/function code

### Phase 4 (Weeks 6-7)
- [ ] Rewrite stencil framework
- [ ] Iterative refinement
- [ ] Full profiling infrastructure

**Success:** JIT improves code on second compilation

---

## Architecture Decisions Already Made ✓

These are locked in and working:

```
✓ Copy-and-patch materialization (not bytecode JIT)
✓ Bounded-arity stencil closure (not unbounded generation)
✓ Offline promotion (not hot-path stencil creation)
✓ TraceRecord as IR (not bytecode-level IR)
✓ StencilPlan as compilation IR (not general SSA)
✓ Proto.code immutable (no quickening)
✓ Explicit dependency tracking (not implicit)
✓ Effect-driven boundaries (not ad-hoc safepoints)
✓ Projection-based recovery (not arbitrary deopt)
```

All remaining work builds on these decisions.

---

## Critical Path

**Blocking dependencies:**
1. EntryCell/EdgeCell → everything else
2. Trace recording → stencil selection
3. Stencil selection → materialization
4. Materialization → execution

**No parallelization possible** until EntryCell infrastructure exists.

---

## Known Unknowns

### Code Density
- Will 81-byte average stencils be efficient enough?
- Will hole stamping overhead be negligible?
- Mitigation: Measure on MVP loop first

### Trace Quality
- Will recorded traces match available stencils?
- Will selector make good choices?
- Mitigation: Instrument selector with metrics

### GC Safety
- Will root projections be complete?
- Will barriers fire correctly?
- Mitigation: Test with aggressive GC

### IC Coherence
- Will shape epochs update correctly?
- Will IC record mutation be safe?
- Mitigation: Build simple monomorphic IC first

---

## Success Criteria

### Phase 2
```
[ ] Integer loop compiles and executes
[ ] Loop produces correct results
[ ] Fallback to interpreter works
[ ] No memory corruption or crashes
```

### Phase 3
```
[ ] Table access compiles
[ ] Function calls compile
[ ] IC fast path executes
[ ] Shape invalidation works
```

### Phase 4
```
[ ] Units improve on second compilation
[ ] DCE eliminates dead stores
[ ] Code density meets expectations
[ ] Real benchmark improvement >= 2x
```

---

## What NOT to Do

```
✗ Don't generate stencils at runtime
✗ Don't use general-purpose compiler for stencils
✗ Don't create new stencil shapes on hot path
✗ Don't mutate Proto.code
✗ Don't skip dependencies for "speed"
✗ Don't patch instruction streams (v1 rule)
✗ Don't assume IC coherence without validation
```

---

## Reference Documents

- `JIT_DESIGN.md` - Full architecture
- `STENCIL_LIBRARY.md` - Stencil system
- `STENCIL_LIBRARY_BUILDER.md` - Generation pipeline
- `STENCIL_VERIFICATION_REPORT.md` - Current library quality
