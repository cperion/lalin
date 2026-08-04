# Schema Ownership Inventory

This is the executable ownership inventory for the canonical schema.
The guard is `tests/schema/test_schema_ownership_inventory.lua`.

## Rules

- A compiler namespace has exactly one intended owner.
- The schema owns every compiler namespace; the legacy schema is deleted.
- A new duplicate is a failing test, not an implicit migration decision.
- The schema owns duplicated compiler namespaces except `LalinPhase`, whose
  canonical owner is `lua/lalin/schema/phase.lua`.
- `lua/lalin/schema/host.lua` is the single Host boundary declaration.
- Cutovers delete old owners after all canonical consumers move; they do not add
  re-export or constructor compatibility shims.

## Current duplicate set

```text
bind check c c_materialize code compiler core effect exec flow graph init
kernel lower mem parse phase project schedule sem source stencil tree type value
```

Intended owners are `lua/lalin/schema/<name>.lua`, with two exceptions:

- `init` is bootstrap ownership in `lua/lalin/schema/init.lua`, not an ASDL
  namespace.
- `phase` is owned by `lua/lalin/schema/phase.lua`.

## Current status

`LalinPhase` now has one precise, no-`any` declaration owned by
`lua/lalin/schema/phase.lua`. The schema consumes that declaration directly and
instantiates it in its own context; there is no constructor adapter or duplicate
phase vocabulary.

## Shared and excluded boundaries

`lua/lalin/schema/host.lua` is consumed directly by the schema bootstrap.

The following explicit non-main backend schemas remain outside the neutral C
ownership cutover:

- `lua/lalin/schema/luajit.lua` — explicit LuaJIT bytecode boundary;
- `lua/lalin/schema/luatrace.lua` — excluded legacy LuaTrace vocabulary.

The native copy-patch schema is deleted and must remain absent.

## Cutover procedure

For each ownership package:

1. move canonical consumers to the intended schema owner;
2. run focused, suite, and fresh-process parity tests;
3. delete the old owner and its imports;
4. update the 25-name closed set and this inventory;
5. reject aliases, re-export shims, and constructor adapters.

The inventory is complete only when the duplicate set is empty.

