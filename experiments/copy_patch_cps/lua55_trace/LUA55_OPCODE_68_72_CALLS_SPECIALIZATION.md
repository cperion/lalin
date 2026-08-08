# LUA55 Opcodes 68–72 Specialization: CALL, TAILCALL, RETURN, RETURN0, RETURN1

Frozen matrix for **host-mediated calls** (the rcp VMIL'25 model: the call
stencil invokes the runtime; native paths stay straight-line).

## Formats (lvm.c / lopcodes.h)

| opcode | name | format | semantics |
|--------|------|--------|-----------|
| 68 | `CALL` | A B C | `R[A]..R[A+C-2] := R[A](R[A+1], ..., R[A+B-1])` — `B-1` args, `C-1` results (`C==0` → all) |
| 69 | `TAILCALL` | A B C k | like CALL, discarding the caller frame |
| 70 | `RETURN` | A B C k | return `R[A], ..., R[A+B-2]` (`B-1` results) |
| 71 | `RETURN0` | — | return no values |
| 72 | `RETURN1` | A | return `R[A]` |

## Native side

`RETURN`/`RETURN0`/`RETURN1` are **terminal occurrences** (like JMP): the
learner records one quote, stores the return pc (patched), sets
`COMPLETED`, and returns — no `lua55_learn_next` / `residual_next`. The
host reads `(A, B)` from the fired occurrence to extract the callee's
results.

## Host side: the block-graph driver

`CALL`/`TAILCALL` are **not native occurrences** — they are dispatch
boundaries. `project_call_plan(proto, heap_owner)` splits the proto into
**basic blocks** at every control edge:

- a block ends **before** a `CALL`/`TAILCALL` pc (host dispatch), at a
  standalone `JMP` (included, terminal), at a compare + its owned `JMP`
  (compare included; the owned JMP's target starts a block), or at a
  `RETURN`/`RETURN0`/`RETURN1` (included, terminal);
- every branch target starts a block (the compiler only jumps to
  after-terminator pcs or the entry, so targets always coincide with
  block starts — asserted).

The driver walks pcs: run the block at `pc` natively; `resume_pc` routes
to the next block start, a call boundary, or a return. At a call it
builds a fresh callee frame, copies args `R[A+1 .. A+B-1]` →
`R[0 .. B-2]`, invokes the callee's plan **recursively**, and copies
`C-1` results into `R[A .. A+C-2]` via a destination descriptor passed
down the call. **`TAILCALL` passes the outer destination through**, so the
tail callee's results land directly in the ultimate caller's registers —
the tail call is fully transparent. This makes recursion (`fact`),
multi-return bodies, and tail recursion (`trec`) work through one driver.

The callee binding is host-side: the driver's lookup table maps a call
site to the callee's plan (closure identity, upvalues, and variadic
adaptation are future work).

## Frame coherence

A segment completes when its `resume_pc == stop` (the finish terminal) or
when a terminal fires (`resume_pc == terminal pc`). The host detects the
callee's return by matching the resume pc to the return occurrence. The
call edge is a **host cost**: Lua-side frame creation + arg/result copies
per call; native segments stay straight-line and never call Lua.

## Learner/residual summary

- 3 learners (`lua55_learn_return/return0/return1`), 3 residuals
  (`lua55_residual_return/return0/return1`), all terminal.
- Boundaries: `CALL` (68) and `TAILCALL` (69) remain unsupported as native
  occurrences (the projection plan splits at them); recursion and
  multi-return bodies need segment re-entry contracts (next batch).
