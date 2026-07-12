# Schema Ownership Inventory

This inventory is the OWN-0 ambiguity guard. It records intended ownership during the staged schema-v2 cutover; it does not move, delete, alias, or adapt schema modules.

## Rules

- A compiler namespace has exactly one intended schema owner.
- The duplicate filename set is closed at **26**, including the intentional temporary `c_materialize` duplicate introduced by CMAT-1. A new duplicate is a failing test, not an implicit migration decision.
- Except for the already-canonical `LalinPhase`, schema-v2 is the intended owner for duplicated compiler namespaces. The old files remain only until their dependent OWN-* cutover package reaches zero consumers.
- `init.lua` is bootstrap ownership rather than an ASDL namespace. `lua/lalin/schema_v2/init.lua` is its intended owner.
- The inventory describes target ownership. It does not make the old and schema-v2 constructor identities interchangeable.

## Duplicate names and intended owners

| Duplicate name | Namespace | Intended owner | Cutover package |
|---|---|---|---|
| `bind` | `LalinBind` | `lua/lalin/schema_v2/bind.lua` | OWN-FRONT |
| `check` | `LalinCheck` | `lua/lalin/schema_v2/check.lua` | OWN-FRONT |
| `c` | `LalinC` | `lua/lalin/schema_v2/c.lua` | OWN-C |
| `c_materialize` | `LalinCMat` | `lua/lalin/schema_v2/c_materialize.lua` | OWN-STENCIL |
| `code` | `LalinCode` | `lua/lalin/schema_v2/code.lua` | OWN-ANALYSIS / OWN-C |
| `compiler` | `LalinCompiler` | `lua/lalin/schema_v2/compiler.lua` | OWN-C |
| `core` | `LalinCore` | `lua/lalin/schema_v2/core.lua` | OWN-FRONT |
| `effect` | `LalinEffect` | `lua/lalin/schema_v2/effect.lua` | OWN-ANALYSIS |
| `exec` | `LalinExec` | `lua/lalin/schema_v2/exec.lua` | OWN-META |
| `flow` | `LalinFlow` | `lua/lalin/schema_v2/flow.lua` | OWN-ANALYSIS |
| `graph` | `LalinGraph` | `lua/lalin/schema_v2/graph.lua` | OWN-ANALYSIS |
| `init` | bootstrap (no ASDL namespace) | `lua/lalin/schema_v2/init.lua` | OWN-CUTOVER |
| `kernel` | `LalinKernel` | `lua/lalin/schema_v2/kernel.lua` | OWN-ANALYSIS |
| `lower` | `LalinLower` | `lua/lalin/schema_v2/lower.lua` | OWN-ANALYSIS / OWN-C |
| `mem` | `LalinMem` | `lua/lalin/schema_v2/mem.lua` | OWN-ANALYSIS |
| `parse` | `LalinParse` | `lua/lalin/schema_v2/parse.lua` | OWN-FRONT |
| `phase` | `LalinPhase` | `lua/lalin/schema/phase.lua` | OWN-META (already canonical) |
| `project` | `LalinProject` | `lua/lalin/schema_v2/project.lua` | OWN-META |
| `schedule` | `LalinSchedule` | `lua/lalin/schema_v2/schedule.lua` | OWN-ANALYSIS |
| `sem` | `LalinSem` | `lua/lalin/schema_v2/sem.lua` | OWN-FRONT |
| `source` | `LalinSource` | `lua/lalin/schema_v2/source.lua` | OWN-FRONT |
| `stencil` | `LalinStencil` | `lua/lalin/schema_v2/stencil.lua` | OWN-STENCIL |
| `stencil_machine` | `LalinStencilMachine` | `lua/lalin/schema_v2/stencil_machine.lua` | OWN-STENCIL |
| `tree` | `LalinTree` | `lua/lalin/schema_v2/tree.lua` | OWN-FRONT |
| `type` | `LalinType` | `lua/lalin/schema_v2/type.lua` | OWN-FRONT |
| `value` | `LalinValue` | `lua/lalin/schema_v2/value.lua` | OWN-ANALYSIS |

## Host boundary

`lua/lalin/schema/host.lua` is the single legitimate `LalinHost` owner. It describes host target/layout representation used at the compiler/host boundary. Schema-v2 consumes that exact declaration from its bootstrap; there is deliberately no `lua/lalin/schema_v2/host.lua`. Host is therefore shared boundary vocabulary, not a duplicated compiler namespace and not an old-to-new adapter.

## Explicitly excluded backends

The main ownership cutover is for the neutral GCC-over-`emit_c` path. These backend-specific schema owners are excluded:

- `lua/lalin/schema/luajit.lua` (`LalinLuaJIT`): explicit LuaJIT bytecode and legacy stencil-machine references only.
- `lua/lalin/schema/luatrace.lua` (`LalinLuaTrace`): LuaTrace is not part of the canonical main-C schema.
- `lua/lalin/schema/native.lua` (`LalinNative`): experimental native copy-patch only.

No schema-v2 counterpart may be added for these names under OWN-0. Existing `LalinLuaJIT` references in `schema_v2/stencil_machine.lua` are quarantined backend debt for OWN-STENCIL, not permission to pull LuaJIT values into neutral C materialization. Backend cutover requires an explicit package outside this inventory.

CMAT-1 intentionally added the canonical `lua/lalin/schema_v2/c_materialize.lua` before consumers of the old `lua/lalin/schema/c_materialize.lua` have been migrated. `LalinCMat` is owned by the schema-v2 file now; CMAT/OWN-STENCIL moves all planning, materialization, and emission consumers to that identity and then removes the old file. The duplicate is therefore explicit and temporary, not filtered from ambiguity detection.

## Executable guard

`tests/schema/test_schema_ownership_inventory.lua` computes the basename intersection of `lua/lalin/schema` and `lua/lalin/schema_v2`, asserts the exact 26-name set (including `c_materialize`), verifies each namespace and intended owner, checks the Host boundary, and checks the excluded backend set. `tests/run.lua schema` executes both `tests/schema` and `tests/schema_v2`; modules are not moved or deleted by OWN-0.

