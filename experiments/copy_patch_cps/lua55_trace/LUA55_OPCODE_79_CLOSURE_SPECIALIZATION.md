# LUA55 Opcode 79 Specialization: CLOSURE

Frozen matrix for closure materialization.

## Format

`CLOSURE A Bx` — `R[A] := closure(proto K[Bx], upvalues)`. The target
proto is `proto.protos[Bx + 1]`; its upvalue descriptors (`instack`,
`idx`, from the undump) drive the closure's cells.

## Guest heap closure objects

`Lua55GuestClosureV1 { header; proto_index; upvalue_count; cells[] }` —
bumped from the heap's native region (non-moving), cells inline. A fresh
closure is materialized **each run** (learner once, residual re-bumps).

## Upvalue cells

Per the proto's descriptors (bounded at 4; more reject):

- `isinstack = 1`: the cell is **OPEN**, pointing at the enclosing
  frame's register (`frame->values[idx]`) — the cell always sees the
  current local value (no guard needed; the pointer is the whole effect).
- otherwise: the cell is **CLOSED** with a copy of the enclosing frame's
  upvalue value (`*upvalue_value(frame, &frame->upvalues[idx])`).

## Host invocation

The host reads the closure object (proto_index, cells) and copies each
cell's value into the callee frame's upvalue when invoking the callee's
own native plan — the captured upvalues flow across the host-mediated
call boundary.

## Learner/residual summary

- 1 learner (`lua55_learn_closure`), 1 residual (`lua55_residual_closure`)
- Holes: target register, proto index, upvalue count, 4 descriptor pairs
  (`instack_i`/`idx_i`), quote base, resume pc.
