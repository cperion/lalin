# Schema Ownership Inventory

This is the executable ambiguity inventory for the staged schema-v2 cutover.
The guard is `tests/schema/test_schema_ownership_inventory.lua`.

## Rules

- A compiler namespace has exactly one intended owner.
- The current old/v2 basename intersection is closed at **25** names.
- A new duplicate is a failing test, not an implicit migration decision.
- Schema-v2 owns duplicated compiler namespaces except `LalinPhase`, whose
  canonical owner is `lua/lalin/schema/phase.lua`.
- `lua/lalin/schema/host.lua` is the single shared Host boundary declaration.
- Constructor identities are not interchangeable across old and v2 schemas.
- Cutovers delete old owners after all canonical consumers move; they do not add
  re-export or constructor compatibility shims.

## Current duplicate set

```text
bind check c c_materialize code compiler core effect exec flow graph init
kernel lower mem parse phase project schedule sem source stencil tree type value
```

Intended owners are `lua/lalin/schema_v2/<name>.lua`, with two exceptions:

- `init` is bootstrap ownership in `lua/lalin/schema_v2/init.lua`, not an ASDL
  namespace.
- `phase` remains owned by `lua/lalin/schema/phase.lua`; the v2 path is expected
  to consume that owner directly.

## Current blocker

The executable guard currently reports that `lua/lalin/schema_v2/phase.lua` does
not consume the canonical old-schema `LalinPhase` owner. This is an ownership
cutover blocker, not permission to weaken the guard or document two owners.

## Shared and excluded boundaries

`lua/lalin/schema/host.lua` is consumed directly by schema-v2 and has no v2
duplicate.

The following explicit non-main backend schemas remain outside the neutral C
ownership cutover:

- `lua/lalin/schema/luajit.lua` — explicit LuaJIT bytecode boundary;
- `lua/lalin/schema/luatrace.lua` — excluded legacy LuaTrace vocabulary.

The native copy-patch schema is deleted and must remain absent.

## Cutover procedure

For each ownership package:

1. move canonical consumers to the intended schema-v2 owner;
2. run focused, suite, and fresh-process parity tests;
3. delete the old owner and its imports;
4. update the 25-name closed set and this inventory;
5. reject aliases, re-export shims, and constructor adapters.

The inventory is complete only when the duplicate set is empty.

