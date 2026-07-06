# Lalin Lua VM Roadmap

This is the staged plan for growing the register-VM demo into a Lua-family VM while preserving Lalin's ASDL/region architecture.

## Principles

- The VM's internal bytecode is Lalin-owned. Lua 5.x bytecode is an import format, not the semantic source of truth.
- Runtime facts are explicit products: value words, instructions, prototypes, frames, tables, closures, upvalues, strings, and GC objects.
- Opcode dispatch is one consumer region over encoded bytecode. Source/compiler frontends should remain ASDL/OOP-shaped.
- Fast paths stay visible in ASDL/lowering: sealed `call`, region bundles, compact value words, and eventually explicit dispatch strategy facts.
- Values are one machine word from the beginning so table/register/frame layout does not churn when NaN payloads arrive.

## Milestones

### M1 — Tiny Lua-ish numeric VM

Status: implemented as `demo/lua_vm.lln` / `demo/test_lua_vm.lua` and then
advanced into M2.

Goal: prove the Lua VM skeleton separate from the demo VM.

- one-word `LuaValue { bits [u64] }`
- `LuaInstr { op, a, b, c, bx, sbx }`
- `LuaProto { code, consts }`
- `LuaFrame { regs, proto }`
- opcodes: `LOADK`, `MOVE`, `ADD`, `LT`, `JMP`, `JMPZ`, `RETURN`
- sealed/bundled `LuaVM.dispatch`
- no tables, calls, closures, GC, strings

### M2 — Strings and intern table

Status: in progress.

Implemented:

- explicit tagged-word constants for int/bool/nil/string refs
- string object product `LuaString`
- intern entry product `LuaInternEntry`
- `LuaProto.strings`
- `LOADS` opcode producing a tagged string-ref value
- `LuaString.eq` sealed region protocol
- `EQ` opcode over immediate/tagged values with string fallback through `LuaString.eq`
- bytecode test path that loads two distinct string constants and compares them

Remaining:

- hash/intern lookup region
- string hash storage/use
- table keys using strings

### M3 — Tables

Status: M3a/M3b implemented.

Implemented:

- `LuaTable { array, array_len, hash, hash_len }`
- `LuaHashEntry { occupied, hash, key, value }`
- `LuaVM.tables` table pool
- tagged table refs by table-pool index
- `NEWTABLE`
- checked `SETI` over the array part
- checked `GETI` over the array part
- `SETS` for fixed-capacity string-key hash entries
- `GETS` for fixed-capacity string-key hash entries
- runtime-error exits for wrong table/index/key shapes, array OOB, and hash full
- bytecode test path equivalent to `t = {}; t[1] = 41; t[2] = 1; t["answer"] = t[1] + t[2]; return t["answer"]`

Remaining:

- table pool bounds checks
- hash probing policy beyond linear scan
- resize/growth
- deletion/tombstones
- write barriers once GC exists

### M4 — Calls and closures

- `LuaClosure`, `LuaProto` children
- call frames
- `CALL`, `TAILCALL`, `RETURN`
- fixed args, then varargs

### M5 — Upvalues

- open/closed upvalues
- closure capture
- close-on-scope-exit

### M6 — GC

- object headers
- mark/sweep or incremental tri-color
- barriers for tables/upvalues/closures

### M7 — Metamethods and errors

- metatable slots
- arithmetic/index/call metamethods
- protected call/error unwinding

### M8 — Lua bytecode importers

- Lua 5.4/5.5 chunk reader as boundary importer
- importer lowers into Lalin-owned `LuaProto`/bytecode representation
- version quirks stay at importer boundary

## Non-goals for early milestones

- exact Lua compatibility
- source parser/compiler
- full stdlib
- C API
- coroutine semantics

Those arrive only after object model, calls, and GC are named explicitly.
