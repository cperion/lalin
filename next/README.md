# Lalin Next

`next/` is the isolated implementation root for the frozen compiler ASDL redesign.
It does not import, modify, or register with the active compiler under `lua/lalin/`.

Layout:

```text
next/lua/                         isolated Lua source root
next/lua/lalin/compiler/schema.lua  frozen compiler ASDL
next/tests/                       isolated tests
next/docs/IMPLEMENTATION_PLAN.md   backend-first TDD implementation checklist
next/docs/                        redesign documentation and freeze synthesis
```

Run the isolated checks from the repository root:

```sh
LUA_PATH='./next/lua/?.lua;./next/lua/?/init.lua;./next/tests/?.lua;./next/tests/?/init.lua' \
  luajit next/tests/run.lua

# equivalent
make test-next
```

Regenerate frozen schema/specification goldens only during an approved schema repair or diagnostic-policy review:

```sh
LALIN_REGEN_SCHEMA=1 \
LUA_PATH='./next/lua/?.lua;./next/lua/?/init.lua;./next/tests/?.lua;./next/tests/?/init.lua' \
  luajit next/tests/run_one.lua next/tests/compiler/schema_spec.lua

LALIN_REGEN_DIAGNOSTIC_ORIGIN=1 \
LUA_PATH='./next/lua/?.lua;./next/lua/?/init.lua;./next/tests/?.lua;./next/tests/?/init.lua' \
  luajit next/tests/run_one.lua next/tests/compiler/diagnostic_origin_spec.lua
```

Focused checks use the harness so spec failures affect the exit status:

```sh
LUA_PATH='./next/lua/?.lua;./next/lua/?/init.lua;./next/tests/?.lua;./next/tests/?/init.lua' \
  luajit next/tests/run_one.lua next/tests/compiler/schema_spec.lua

LUA_PATH='./next/lua/?.lua;./next/lua/?/init.lua;./next/tests/?.lua;./next/tests/?/init.lua' \
  luajit next/tests/run.lua schema_spec
```

Phase specification coverage summary:

```sh
LUA_PATH='./next/lua/?.lua;./next/lua/?/init.lua;./next/tests/?.lua;./next/tests/?/init.lua' \
  luajit next/tests/run.lua coverage
```

Do not add compatibility imports or wire this tree into the active compiler during the redesign.

Historical pre-`next` compiler-model docs live under `docs/archive/compiler-model/`.
They preserve reasoning only; implementation must use `next/lua/lalin/compiler/schema.lua`
and `next/docs/SCHEMA_REVIEW_SYNTHESIS.md` as authority.

Implementation proceeds by `next/docs/IMPLEMENTATION_PLAN.md`: schema and tests
are specified together first, then implementation proceeds bottom-up from C/Host
and CMat with hand-built ASDL fixtures before methods. Spec files use `_spec.lua`
naming and are discovered by `next/tests/run.lua`; semantic boundary spec files use
the data-only template at `next/tests/compiler/spec/_template.lua` and are checked by
`next/tests/compiler/spec_gate_spec.lua`.
