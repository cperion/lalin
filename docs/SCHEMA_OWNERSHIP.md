# Schema Ownership Inventory

This inventory is the OWN-0 ambiguity guard and the live cutover manifest. It records both remaining ambiguities and completed declaration removals; it does not make constructor identities interchangeable.

## Rules

- A compiler namespace has exactly one intended schema owner.
- The remaining duplicate filename set is closed at **15**, including the intentional temporary `c_materialize` duplicate introduced by CMAT-1. A new duplicate is a failing test, not an implicit migration decision.
- Schema-v2 is the intended owner for remaining duplicated compiler namespaces. Old files remain only until their dependent OWN-* cutover package reaches zero consumers.
- `init.lua` is bootstrap ownership rather than an ASDL namespace. `lua/lalin/schema_v2/init.lua` is its intended owner.
- The inventory describes target ownership. It does not make the old and schema-v2 constructor identities interchangeable.

## Duplicate names and intended owners

| Duplicate name | Namespace | Intended owner | Cutover package |
|---|---|---|---|
| `c` | `LalinC` | `lua/lalin/schema_v2/c.lua` | OWN-C |
| `c_materialize` | `LalinCMat` | `lua/lalin/schema_v2/c_materialize.lua` | OWN-STENCIL |
| `code` | `LalinCode` | `lua/lalin/schema_v2/code.lua` | OWN-ANALYSIS / OWN-C |
| `compiler` | `LalinCompiler` | `lua/lalin/schema_v2/compiler.lua` | OWN-C |
| `effect` | `LalinEffect` | `lua/lalin/schema_v2/effect.lua` | OWN-ANALYSIS |
| `flow` | `LalinFlow` | `lua/lalin/schema_v2/flow.lua` | OWN-ANALYSIS |
| `graph` | `LalinGraph` | `lua/lalin/schema_v2/graph.lua` | OWN-ANALYSIS |
| `init` | bootstrap (no ASDL namespace) | `lua/lalin/schema_v2/init.lua` | OWN-CUTOVER |
| `kernel` | `LalinKernel` | `lua/lalin/schema_v2/kernel.lua` | OWN-ANALYSIS |
| `lower` | `LalinLower` | `lua/lalin/schema_v2/lower.lua` | OWN-ANALYSIS / OWN-C |
| `mem` | `LalinMem` | `lua/lalin/schema_v2/mem.lua` | OWN-ANALYSIS |
| `schedule` | `LalinSchedule` | `lua/lalin/schema_v2/schedule.lua` | OWN-ANALYSIS |
| `stencil` | `LalinStencil` | `lua/lalin/schema_v2/stencil.lua` | OWN-STENCIL |
| `stencil_machine` | `LalinStencilMachine` | `lua/lalin/schema_v2/stencil_machine.lua` | OWN-STENCIL |
| `value` | `LalinValue` | `lua/lalin/schema_v2/value.lua` | OWN-ANALYSIS |

## Completed canonical removals

| Namespace | Canonical owner | Removed declaration | Package |
|---|---|---|---|
| `LalinCore` | `lua/lalin/schema_v2/core.lua` | `lua/lalin/schema/core.lua` | OWN-FRONT |
| `LalinParse` | `lua/lalin/schema_v2/parse.lua` | `lua/lalin/schema/parse.lua` | OWN-FRONT |
| `LalinSource` | `lua/lalin/schema_v2/source.lua` | `lua/lalin/schema/source.lua` | OWN-FRONT |
| `LalinType` | `lua/lalin/schema_v2/type.lua` | `lua/lalin/schema/type.lua` | OWN-FRONT |
| `LalinBind` | `lua/lalin/schema_v2/bind.lua` | `lua/lalin/schema/bind.lua` | OWN-FRONT |
| `LalinSem` | `lua/lalin/schema_v2/sem.lua` | `lua/lalin/schema/sem.lua` | OWN-FRONT |
| `LalinTree` | `lua/lalin/schema_v2/tree.lua` | `lua/lalin/schema/tree.lua` | OWN-FRONT |
| `LalinCheck` | `lua/lalin/schema_v2/check.lua` | `lua/lalin/schema/check.lua` | OWN-FRONT |
| `LalinTreeCode` | `lua/lalin/schema_v2/tree_code.lua` | — (already schema-v2-only) | OWN-FRONT |
| `LalinPhase` | `lua/lalin/schema/phase.lua` | `lua/lalin/schema_v2/phase.lua` | OWN-META |
| `LalinProject` | `lua/lalin/schema_v2/project.lua` | `lua/lalin/schema/project.lua` | OWN-META |
| `LalinExec` | `lua/lalin/schema_v2/exec.lua` | `lua/lalin/schema/exec.lua` | OWN-META |

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

`tests/schema/test_schema_ownership_inventory.lua` computes the basename intersection of `lua/lalin/schema` and `lua/lalin/schema_v2`, asserts the exact live 15-name set (including `c_materialize`), verifies each remaining owner, asserts completed removals and schema-v2-only `tree_code`, checks the Host boundary, and checks the excluded backend set. `tests/run.lua schema` executes both `tests/schema` and `tests/schema_v2`.

