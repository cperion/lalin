# Lua 5.5 Native CPS V2 experiment

This directory implements the isolated Lua 5.5 copy-and-patch CPS machine.
`NATIVE_CPS_V2_COMPLETE_MIGRATION_DESIGN.md` is the binding V2 architecture;
`LUA55_OPCODE_INVENTORY.md` is the frozen Lua 5.5.0 opcode baseline. Earlier
one-shot learner documents and V1 specialization matrices remain historical
fixtures only.

## Binding exact-residual rule

Opcode coverage is not sufficient. A published RX residual must implement one
selected semantic shape. It may guard that shape and branch on program data,
but it must not inspect tags, key domains, callee kinds, constant kinds, or
capture kinds to choose another implementation.

Runtime-dependent shapes are learned in a separate image, persisted as named
per-occurrence shape products, then linked as immutable exact residual leaves.
Projection-proven facts are resolved before execution. A mismatch uses one named
typed rejection/relearn exit; executing RX memory is never rewritten.

The exhaustive audit and required migration order are in
`V2_RESIDUAL_SPECIALIZATION_INVENTORY.md`. Section 21 of
`NATIVE_CPS_V2_COMPLETE_MIGRATION_DESIGN.md` makes zero red inventory cases a
completion gate; section 21.6 specifies the file-by-file correction procedure,
family-specific learning products, separate learning/residual images, table
capacity learning, typed mismatch behavior, and executable acceptance gates.
The current generic arithmetic, comparison, dynamic-table, call, numeric-for,
CONCAT, GETVARG, and closure records are mandatory corrective work, not accepted
final residuals.

The active public runner is Native CPS Frame V2. LuaJIT owns bytecode staging,
outer lifetime, and explicit host/library boundaries; recurring guest control
uses immutable RX arenas and proper-tail native CPS.

```text
luajit experiments/copy_patch_cps/lua55_trace/build_opcode_00_08_bank.lua
luajit experiments/copy_patch_cps/lua55_trace/opcode_00_08_test.lua
luajit -joff experiments/copy_patch_cps/lua55_trace/opcode_00_08_test.lua
luajit experiments/copy_patch_cps/lua55_trace/build_opcode_09_10_bank.lua
luajit experiments/copy_patch_cps/lua55_trace/opcode_09_10_test.lua
luajit -joff experiments/copy_patch_cps/lua55_trace/opcode_09_10_test.lua
luajit experiments/copy_patch_cps/lua55_trace/opcode_00_10_projection_test.lua
luajit -joff experiments/copy_patch_cps/lua55_trace/opcode_00_10_projection_test.lua
luajit experiments/copy_patch_cps/lua55_trace/build_opcode_string_bank.lua
luajit experiments/copy_patch_cps/lua55_trace/opcode_string_test.lua
luajit -joff experiments/copy_patch_cps/lua55_trace/opcode_string_test.lua
luajit experiments/copy_patch_cps/lua55_trace/build_opcode_table_bank.lua
luajit experiments/copy_patch_cps/lua55_trace/opcode_table_test.lua
luajit -joff experiments/copy_patch_cps/lua55_trace/opcode_table_test.lua
luajit experiments/copy_patch_cps/lua55_trace/opcode_table_oracle_test.lua
luajit -joff experiments/copy_patch_cps/lua55_trace/opcode_table_oracle_test.lua
luajit experiments/copy_patch_cps/lua55_trace/opcode_00_10_bench.lua

# Earlier numeric-loop proof
luajit experiments/copy_patch_cps/lua55_trace/build_bank.lua
luajit experiments/copy_patch_cps/lua55_trace/recorder_test.lua
luajit -joff experiments/copy_patch_cps/lua55_trace/recorder_test.lua
luajit experiments/copy_patch_cps/lua55_trace/bytecode_integration_test.lua
luajit experiments/copy_patch_cps/lua55_trace/bytecode_integration_test.lua
luajit experiments/copy_patch_cps/lua55_trace/bench.lua
luajit experiments/lua55/undump_overflow_regression_test.lua
```

The opcode 0–8 bank contains 17 learner stencils and 21 scalar residual stencils. The opcode 9–10 extension adds two
learner stencils and 20 residuals for open/closed scalar upvalues. The string extension adds four learner stencils and
six residuals for rooted short/long `LOADK`, `LOADKX`, and guarded `MOVE`. The table extension adds four learners
and 29 residuals for bounded `GETI`, `GETFIELD`, `SETI`, and `SETFIELD`. It guards exact table identity, storage
generation, metatable absence, collection epoch, direct slot tags, and write-source tags. String writes execute an
explicit guest barrier. The comparison extension adds 22 learners and 102 residuals for opcodes 57–67 (`EQ`/`LT`/`LE`
with exact int/float/string semantics, `EQK`, `EQI`, `LTI`–`GEI`, `TEST`, `TESTSET`); every comparison owns its
following `JMP`, and a taken branch exits at the exact target PC. The arithmetic extension adds 23 learners and 80
residuals for opcodes 21–45 (POW deferred): int-wrap add/sub/mul, float div, floor-mod/floor-idiv with host
zero-divisor exits, bitwise with `F2Ieq` coercion, and shifts; every primitive owns its companion
(`MMBIN`/`MMBINI`/`MMBINK`). The unary extension adds 4 learners and 9 residuals for opcodes 49–52:
`UNM` (int wrap, float negate), `BNOT` (`F2Ieq`), total `NOT`, and `LEN` over guest strings and
metatable-free tables (exact leading-run length, recomputed per run). The JMP extension adds
a terminal occurrence for standalone `JMP` (56): the resolved target `pc + sJ + 1` is patched
into both the learner and the residual, which store it and complete — the learner stops there
and the host resumes at the target (loop back-edges, forward branches). The POW extension
completes the arithmetic matrix: `POW` (38) and `POWK` (26) are floats-only exponentiation
(calling libm `pow` through a dlsym-resolved absolute-address hole patched into the stencil,
with `luai_numpow`'s `b == 2.0` → `a*a` fast path via bit compare). The call extension
implements **host-mediated calls**: `RETURN` (70), `RETURN0` (71), and `RETURN1` (72) are native
terminal occurrences (record, store the return pc, complete); `CALL` (68) and `TAILCALL` (69)
are host dispatch boundaries. `project_call_plan` splits a proto into **basic blocks** at every
control edge (calls, standalone JMPs, compares + their owned JMPs, returns) so every branch
target is a block start, and the host driver walks pcs natively: run the block at pc, follow
`resume_pc` to the next block, a call boundary (dispatch the callee's own plan recursively,
copying args/results across), or a return (copy results into the caller's destination).
`TAILCALL` passes the outer result destination through, so tail callee results land directly in
the ultimate caller's registers — enabling recursion (`fact`) and tail recursion (`trec`). The
generic-table extension (11/12/15/16/19/20) implements metatable-absent access with identity +
shape + **runtime-key guards**: `GETTABLE`/`SETTABLE` read the key from a register (integer or
interned string; the learner records the key's tag and value into the recording slot, and the
residual re-guards them each run); `GETTABUP`/`SETTABUP` read the receiver from an upvalue cell
(state/generation guarded) with a constant key; `SELF` copies the receiver to `R[A+1]` and reads
the constant-key field; `NEWTABLE` bumps a **fresh guest table each run** from a native region in
the heap (non-moving, min capacity so `{}` + writes work). Quotation IDs use
`opcode << 16 | variant`. Tests cover
explicit guest barrier. Quotation IDs use `opcode << 16 | variant`. Tests cover
A **real-program runner** (`run55.lua`) now executes a full Lua 5.5 source file: stock
`luac` bytecode -> `undump55` -> per-proto call plans -> native blocks with
host-mediated CALL/TFORCALL/numeric-for boundaries. The user's own functions run
natively (recursion, numeric-for, while, pairs/ipairs, concat, rawget/rawset,
select); the library (`print`, `tostring`, `math.*`) crosses the FFI boundary as
guest builtin markers. FORLOOP became a native terminal (host FORPREP boundary
prepares the integer count-down / float limit-step-control cells); GETUPVAL and
the string table-ops gained closure variants (self-recursion + math builtins);
GETTABUP gained a table variant (`_ENV.math`); and a compare now starts its own
block so while-loop back-edges resolve. See `RUN55_RUNNER.md`. immutable RX publication, coherent
guard failure, capacity and ownership rejection, explicit release, bounded warmup allocation, and JIT-independent
execution.

`perf_bench.lua` measures all paths against stock Lua 5.5; results are in `PERFORMANCE.md`.

`opcode_00_10_projection.lua` installs projection behavior on concrete decoded opcode and constant classes. The checked-in
Lua 5.5.0 fixture projects a real 24-instruction path containing movement, loads, five closed upvalue writes, five
closed upvalue reads, and result moves. Unsupported opcodes, malformed `LOADKX`, and collectables without an exact
guest-heap owner reject before native learning.

The earlier numeric-loop proof owns a single fused leaf. The generic instruction-recording mirror (TraceProgram,
semantic instruction lists, `record_current`, and the `automatic` prototype-owner mirror) is retired: bytecode is the
plan, and `IntegerAddForLoopPlan:record` records directly. The proof covers the exact numeric-for backedge, numeric
CDEF frame ownership, terminal resume PCs, immutable RX publication, one-shot recording, execution, and release.

`bytecode_projection.lua` now recognizes the exact real Lua 5.5 sequence:

```text
FORPREP → ADD → MMBIN companion → FORLOOP
```

It projects that sequence to `IntegerAddForLoopPlan`. `program.lua` records and installs the trace on the first call;
later calls initialize the exact frame and enter the same immutable RX recurrence directly. The program records exactly
once, retains the executable owner, and rejects calls after release. Results are checked against the generated-Lua
exotype implementation.

Current 10,000-element integer-loop measurements are approximately:

```text
fused Add+ForLoop trace      0.218 ns/guest iteration
generated-Lua exotype        0.970 ns/guest iteration
LuaJIT compiled Lua loop     0.637 ns/guest iteration

fused trace -joff            0.253 ns/guest iteration
fused trace -joff            0.253 ns/guest iteration
generated-Lua exotype -joff 22.127 ns/guest iteration
Lua loop -joff               2.598 ns/guest iteration
```

The explicit fused semantic leaf keeps sum, index, limit, and step in native registers and materializes the coherent
frame at loop exit. It is approximately 4.4x faster than the generated-Lua exotype and 2.9x faster than the
LuaJIT-compiled Lua loop in this narrow fixture. This is a closed superinstruction
result, not evidence for arbitrary trace-wide register allocation.
