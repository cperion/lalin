# SpongeJIT Lua SSA Rewrite Plan

## Decision

Rewrite the Lua SSA compiler in a new folder and quarantine the old implementation.

The rewrite uses Moonlift/PVM ASDL as the compiler architecture. The old Lua tables/graph code is quarantined historical material, not a compatibility target.

Primary direction:

```text
PUC bytecode + evidence
→ LuaSrc / LuaFact ASDL
→ LuaSem ASDL
→ LuaNF ASDL
→ LuaContract ASDL
→ MoonOut.Kernel
→ Moonlift
→ Cranelift
```

There is no backward compatibility path. The old SponJIT stencil/bank descriptor path is not a backend target for the rewrite.

## Why

The current SSA path still preserves too much interpreter/backend mechanics:

- source opcode shape leaks into later forms
- frame sync appears as default computation shape
- semantic SSA carries physical-ish residency hints
- normal form is too close to lower/codegen vocabulary
- projection is under-modeled and defaults to synced frame
- native x64 lowering contains semantic seam work that should have been consumed earlier

The fix is not more peepholes. The fix is a proper compiler vocabulary.

## Guiding docs

The rewrite follows:

- `COMPILER_PATTERN.md`
- `PVM_GUIDE.md`

Applied rule:

```text
Each phase consumes one semantic vocabulary into a narrower vocabulary.
Execution consumes flat decided facts. It never rediscovers source meaning.
```

For SpongeJIT:

```text
PUC opcodes are source vocabulary.
LuaSem consumes opcode meaning.
LuaNF is semantic identity and dedupe.
Residency/placement is not semantic identity.
Moonlift/Cranelift handles native placement/optimization.
```

## New folder

The rewrite lives under:

```text
experiments/lua_interpreter_vm/spongejit/ssa_asdl/
```

Current files:

```text
spongejit_lua_ssa.asdl   -- full ASDL vocabulary
README.md                -- module/layer summary
REWRITE_PLAN.md          -- this document
```

When implementation starts, create a sibling implementation folder, for example:

```text
experiments/lua_interpreter_vm/spongejit/lua_compile/
```

or:

```text
experiments/lua_interpreter_vm/spongejit/compiler2/
```

Do not mutate the old compiler in place.

## Quarantine old code

Old code remains readable but is quarantined. It is not a target, not a compatibility surface, and not a migration constraint:

```text
src/ssa.lua
src/ssa_ir.lua
src/ssa_lift.lua
src/ssa_opt.lua
src/ssa_to_stencil.lua
src/stencil_ir.lua
src/stencil_lower.lua
src/stencil_native_x64.lua
```

Quarantine rule:

- no new architectural features in old SSA
- no more backend micro-optimizations to compensate for bad semantic form
- old tests may remain only until replaced by new tests
- new tests target new ASDL phases
- no adapters from the new compiler back into old descriptor/bank APIs

## Target architecture

### 1. Source layer: `LuaSrc`

Question:

```text
What did PUC encode?
```

Contains:

- bytecode opcode variants
- operands
- pc
- constants/upvalues references
- immediate fields
- boundary opcodes as source facts, not fallback

Must not contain:

- SSA values
- native registers
- frame sync strategy
- runtime descriptor fields

### 2. Evidence layer: `LuaFact`, `LuaRegion`

Question:

```text
What has the runtime/foundry proven or leased?
```

Contains:

- observed facts
- subjects
- predicates
- dependencies/epochs
- payload leases
- structured loop topology

Important distinction:

```text
observed fact != guard fact != payload lease != ABI fact bit
```

Payload leases are semantic authority for direct table/upvalue/array access. ABI masks are later transport.

### 3. Semantic layer: `LuaSem`

Question:

```text
What does this Lua bytecode mean under this evidence?
```

Contains:

- virtual slot classes
- semantic TValue/I64/F64/Bool values
- guards
- writes
- barriers
- observations
- boundaries
- returns
- structured rejection

Must not contain:

- physical registers
- x64 locations
- `gpr0`
- `boxed_i64_reg`
- byte offsets into `SponExecCtx`

`LuaSem` consumes opcode meaning. After this layer, opcode names are mostly dead except as pc/reason/projection payload.

### 4. Normal-form layer: `LuaNF`

Question:

```text
What is the least equivalent semantic computation?
```

Contains:

- canonical expressions
- canonical affine/bit/arithmetic forms
- reduced guards
- writes
- typed exits
- projection obligations
- canonical slot aliases

This is the dedupe/semantic identity layer.

Two programs may dedupe only if their `LuaNF` plus contract/projection obligations are equivalent.

### 5. Contract layer: `LuaContract`

Question:

```text
What facts are selected, required, checked, produced, killed, and what exits must project?
```

Contains:

- fact uses by role
- payload uses
- dependencies
- projection obligations

Contract must be derivable from `LuaNF`, not from accidental source fact bundles.

### 6. Moonlift output layer: `MoonOut`

Question:

```text
What Moonlift kernel represents this reduced Lua computation?
```

Contains:

- kernel kind
- ABI params
- normal form
- contract
- projections

Moonlift lowering consumes `LuaNF`. It does not receive PUC opcode-shaped code.

### 7. Optional placement layer: `LuaPlace`

Question:

```text
Where may already-reduced values live?
```

This layer is non-semantic and optional. If Moonlift/Cranelift gives good enough code quality, skip explicit placement and let the backend solve it.

## Non-negotiable invariants

1. **No physical residency in semantic SSA**

   `LuaSem` and `LuaNF` do not know about `rax`, `gpr0`, scratch registers, or x64 byte layout.

2. **Opcode mechanics are consumed**

   `ADDI`, `ADDK`, `ADD` are source distinctions. Semantic form is arithmetic meaning.

3. **Frame stores are observations/projections, not default state**

   The compiler tracks virtual Lua values. It syncs/projection only when a true observation requires it.

4. **Projection is typed control**

   Guard exit, boundary, return, jump, and loop exits carry explicit projection obligations.

5. **Boundary is exact control transfer**

   Boundary is not unsupported fallback. Unsupported cases are structured rejections.

6. **Normal form owns equivalence**

   Dedupe key is semantic normal form plus contract/projection obligations. Source opcode chains are aliases only.

7. **No backward compatibility**

   The rewrite does not emit old SponJIT descriptors, does not preserve old bank/materializer APIs, and does not add adapters back to the old compiler.

8. **Runtime consumes decided Moonlift output**

   Runtime never runs SSA and never asks what an opcode means.

9. **Moonlift lowering receives reduced semantics**

   Moonlift is not a bytecode interpreter target. It receives canonical LuaNF-derived kernels.

## File organization

Implementation folder:

```text
experiments/lua_interpreter_vm/spongejit/lua_compile/
```

Naming rule:

```text
<source-asdl>_to_<target-asdl>_<verb>.lua
```

Use the ASDL module names and the semantic verb answered by the boundary. File names are architectural documentation; a file exists because a vocabulary transition exists.

### Root files

```text
lua_compile/init.lua                    -- public facade for the new compiler
lua_compile/schema.lua                  -- load/define spongejit_lua_ssa.asdl
lua_compile/builders.lua                -- constructor conveniences; no semantics
lua_compile/validate.lua                -- cross-layer invariants
lua_compile/diagnostics.lua             -- structured reports and debug formatting
lua_compile/errors.lua                  -- shared error constructors, no fallback logic
```

### `LuaSrc` construction

```text
lua_compile/lua_src_from_puc_decode.lua       -- PUC instruction tables -> LuaSrc.Op
lua_compile/lua_src_window_collect.lua        -- opcode stream -> LuaSrc.Window
lua_compile/lua_src_slot_alias.lua            -- concrete source slot inventory helpers
lua_compile/lua_src_validate.lua              -- source-layer checks only
```

Verb: decode / collect.

Question answered:

```text
What did PUC encode?
```

### `LuaRegion` recognition

```text
lua_compile/lua_src_to_lua_region_recognize.lua   -- LuaSrc.Window -> LuaRegion.RegionSet
lua_compile/lua_region_validate.lua               -- topology invariants
```

Verb: recognize.

Question answered:

```text
What structured control topology is present?
```

### `LuaFact` evidence import

```text
lua_compile/lua_fact_from_runtime_observe.lua      -- runtime observations -> LuaFact.Fact
lua_compile/lua_fact_from_foundry_bundle.lua       -- foundry bundles -> LuaFact.Evidence
lua_compile/lua_fact_payload_lease.lua             -- payload lease construction/validation
lua_compile/lua_fact_closure.lua                   -- implication/dependency closure
lua_compile/lua_fact_contradiction.lua             -- contradiction detection
lua_compile/lua_fact_validate.lua                  -- evidence-layer checks
```

Verb: observe / lease / close.

Question answered:

```text
What facts and payload leases are available?
```

### `LuaSrc + LuaFact -> LuaSem`

```text
lua_compile/lua_src_to_lua_sem_lower.lua           -- main semantic lowering boundary
lua_compile/lua_sem_env.lua                        -- virtual slot/value environment
lua_compile/lua_sem_guard.lua                      -- guard construction and success facts
lua_compile/lua_sem_write.lua                      -- writes, kills, barriers
lua_compile/lua_sem_boundary.lua                   -- exact boundary observations
lua_compile/lua_sem_reject.lua                     -- structured rejection reasons
lua_compile/lua_sem_validate.lua                   -- semantic-layer invariants
```

Verb: lower.

Question answered:

```text
What does this bytecode mean under this evidence?
```

### `LuaSem -> LuaNF`

```text
lua_compile/lua_sem_to_lua_nf_normalize.lua        -- main normal-form boundary
lua_compile/lua_nf_expr_canonicalize.lua           -- arithmetic/value canonical forms
lua_compile/lua_nf_guard_reduce.lua                -- redundant guard reduction
lua_compile/lua_nf_write_reduce.lua                -- dead write/value reduction
lua_compile/lua_nf_projection_reduce.lua           -- minimal projection obligations
lua_compile/lua_nf_key.lua                         -- stable semantic identity key
lua_compile/lua_nf_validate.lua                    -- normal-form invariants
```

Verb: normalize / reduce / canonicalize.

Question answered:

```text
What is the least equivalent semantic computation?
```

### `LuaNF -> LuaContract`

```text
lua_compile/lua_nf_to_lua_contract_derive.lua      -- main contract derivation boundary
lua_compile/lua_contract_fact_use.lua              -- selector/required/checked/produced/killed roles
lua_compile/lua_contract_projection.lua            -- exit projection obligations
lua_compile/lua_contract_dependency.lua            -- epoch/dependency extraction
lua_compile/lua_contract_key.lua                   -- contract identity, paired with LuaNF key
lua_compile/lua_contract_validate.lua              -- contract invariants
```

Verb: derive.

Question answered:

```text
What facts/exits/projections are required and transferred?
```

### Optional `LuaNF -> LuaPlace`

```text
lua_compile/lua_nf_to_lua_place_plan.lua           -- optional placement planning boundary
lua_compile/lua_place_projection_plan.lua          -- projection realization hints
lua_compile/lua_place_validate.lua                 -- non-semantic placement invariants
```

Verb: plan.

Question answered:

```text
Where may already-reduced values live, if Moonlift needs hints?
```

This folder must remain optional. If Moonlift/Cranelift gives sufficient placement quality, no semantic code may depend on `LuaPlace`.

### `LuaNF + LuaContract -> MoonOut`

```text
lua_compile/lua_nf_to_moon_out_lower.lua           -- main Moonlift lowering boundary
lua_compile/moon_out_abi.lua                       -- MoonOut.Param and kernel ABI vocabulary
lua_compile/moon_out_emit.lua                      -- Moonlift source/AST emission
lua_compile/moon_out_projection.lua                -- exit/projection lowering to Moonlift boundary code
lua_compile/moon_out_validate.lua                  -- MoonOut invariants
```

Verb: lower / emit.

Question answered:

```text
What Moonlift kernel represents this reduced Lua computation?
```

### Top-level compile facade

```text
lua_compile/lua_compile_unit.lua                   -- LuaCompile.Unit construction
lua_compile/lua_compile_to_normal_form.lua         -- Unit -> NormalForm product
lua_compile/lua_compile_to_moon_kernel.lua         -- Unit -> MoonKernel product
lua_compile/lua_compile_validate.lua               -- whole-pipeline invariants
```

Verb: compile.

Question answered:

```text
Did compilation produce a normal form, a Moonlift kernel, or a structured rejection?
```

### Tests mapped to files

```text
experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_schema.lua
experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_lua_src.lua
experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_lua_fact.lua
experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_lua_region.lua
experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_lua_sem.lua
experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_lua_nf.lua
experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_lua_contract.lua
experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_moon_out.lua
experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_pipeline.lua
```

## First implementation slice

Do not port all opcodes at once.

Start with a small exact slice that exercises the architecture:

```text
LOADI
MOVE
ADDI
ADD
SUB
RETURN1
RETURN0
boundary handoff
```

Required tests:

1. `ADDI^4` normalizes to one canonical affine value, not four opcode-local stores.
2. `ADDI`, `ADDK`, and equivalent `ADD` forms normalize to same semantic shape when evidence permits.
3. Slot writes kill/replace facts in contract.
4. Guard success produces checked facts.
5. Guard failure carries projection obligations.
6. Return projects the final virtual slot/value without requiring all frame slots synced.
7. No `gpr0`/register/residency appears in semantic ASDL values.
8. Moonlift output is generated from `LuaNF`, not from `LuaSrc.Op` dispatch.

## Migration plan

### Phase A — ASDL bootstrap

- Load/define `spongejit_lua_ssa.asdl` with Moonlift/PVM ASDL.
- Add constructors/builders for test fixtures.
- Add validation helpers for layer invariants.

### Phase B — Source/evidence import

- Convert PUC opcode tables into `LuaSrc.Window`.
- Convert current `Facts.fact` records into `LuaFact.Evidence`.
- Preserve payload leases distinctly.

### Phase C — Semantic lowering

- Implement `LuaSrc.Window + LuaFact.Evidence -> LuaSem.Result`.
- No optimization yet except direct semantic consumption.
- Unsupported cases produce `LuaSem.Rejected`.

### Phase D — Normalization

- Implement `LuaSem.Program -> LuaNF.Program`.
- Canonicalize arithmetic, slot aliases, redundant guards, dead values, and projection requirements.

### Phase E — Contract derivation

- Implement `LuaNF.Program -> LuaContract.Contract`.
- Ensure contract does not depend on unconsumed source facts.

### Phase F — Moonlift lowering

- Implement `LuaNF.Program + LuaContract.Contract -> MoonOut.Kernel`.
- Emit Moonlift code/AST.
- Let Cranelift optimize placement and instruction selection.

### Phase G — Delete/quarantine old path

- Replace old tests with new ASDL/Moonlift tests.
- Remove old compiler entry points from maintained flows.
- Keep old files only as archived historical reference until deletion.

## Success criteria

The rewrite is succeeding when:

- semantic SSA contains no physical residency
- normal forms shrink source opcode mechanics aggressively
- equivalent bytecode/fact combinations dedupe by `LuaNF`
- projection obligations are explicit and minimal
- Moonlift output is compact without hand x64 peepholes
- Cranelift produces competitive code on the first slice
- old SponJIT SSA can be deleted

## Immediate next step

Create the new implementation folder and the first ASDL-loading smoke test.

Suggested files:

```text
experiments/lua_interpreter_vm/spongejit/lua_compile/init.lua
experiments/lua_interpreter_vm/spongejit/lua_compile/schema.lua
experiments/lua_interpreter_vm/tests/test_spongejit_lua_compile_schema.lua
```
