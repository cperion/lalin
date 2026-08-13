# V2 Scalar Residual Specialization: Fix Inventory

This is the completion inventory for the **singular Lua 5.5 opcode machine**.
New superinstruction work is frozen until the scalar acceptance gates at the end
of this document are green. Existing superinstructions remain enabled for normal
validation, but they are not evidence that the scalar machine is complete.

## Binding completion rule

A published scalar residual must implement one selected semantic shape. It may:

- validate that shape with exact guards;
- branch on genuine program data;
- branch on mutable protocol state that can change during one published image;
- publish typed language errors, ownership failures, overflow, or specialization
  mismatch; and
- transfer only through named proper-tail CPS edges.

It must not:

- classify a runtime value to choose a sibling semantic implementation;
- branch or loop on a projection-proven fact that publication could remove;
- compute an address from a projection-proven register index when publication can
  patch the byte displacement directly;
- silently retain an unpatched hole;
- reconstruct a generic constant cell; or
- contain a generic fallback for an unseen or conflicting learned product.

Semantic exactness and mechanical residualization are separate requirements. Both are now
covered by executable assembly, publication, differential, and retained-performance gates.

## Assembly audit snapshot

Artifact: `target/copy_patch_cps/lua55_trace/opcode_v2/core.o`. The copied RX
instruction shape is identical except that publication patches holes, successor
relocations, and named boundary addresses.

Current bank:

| subset | sections | bytes | share |
|---|---:|---:|---:|
| all exact residuals | 450 | 177,213 | 100% |
| existing superinstructions | 122 | 83,046 | 46.9% |
| singular opcode fragments | 328 | 94,167 | 53.1% |
| composable CONCAT fragments | 8 | 1,200 | 1.3% of scalar |
| non-CONCAT singular residuals | 320 | 92,967 | 98.7% of scalar |

Closed structural properties:

- no exact residual section contains a native `ret`;
- native `call` occurs only in POW/POWK and CONCAT explicit library operations;
- all 665 exact-residual ELF relocations are `R_X86_64_PLT32` references to
  `lua55_residual_next`;
- ordinary successors become direct relative tail jumps;
- CALL/TAILCALL/RETURN contain no guest-control native `call`;
- learning and retained images are separate;
- RX arenas are immutable and never simultaneously writable and executable; and
- native-visible guest state belongs to mmap owners.

Verdict: **architecture, semantic selection, mechanical residualization, and scalar
completion green. Recursive Fibonacci clears the mandatory PUC parity floor.**

## Required fixes

### S0 — Strict publication-hole contract — COMPLETE

**Original evidence:** `V2Machine:emit` accepted misspelled product keys and
silently skipped absent holes. The `field_receiver_index` versus
`field_receiver` error consequently published the raw `0x5a5b5c5d` sentinel
and crashed in RX.

**Landed:**

- every logical C hole now has a unique sentinel pattern;
- the bank build rejects duplicate and overlapping patterns;
- every record carries physical sites with kind, role, offset, and width;
- occurrence products reject unknown fields before appending code;
- every physical site is registered and must be marked by an exact-width patch;
- deferred links, continuations, cold successors, tail returns, and host exits
  participate in the same check;
- all prototype arenas must build successfully—non-main failures can no longer
  leave a null descriptor for a later runtime rejection;
- publication calls `assert_all_holes_patched()` before `mprotect`; and
- deliberate unknown/missing-hole tests fail before RX under JIT and `-joff`.

The physical-site ledger is stronger than a raw byte scan: a valid user constant
equal to a reserved bit pattern cannot create a false positive.

**Acceptance: GREEN.** No publication path can silently ignore a product field or
expose an unpatched executable hole.

### S1 — Conditional-branch provenance inventory — COMPLETE

Every scalar C conditional and resulting machine branch is assigned one of:

1. exact-shape guard -> typed mismatch;
2. genuine program data;
3. mutable protocol state;
4. typed language/error/overflow outcome; or
5. forbidden projection-time decision.

`bank.branch_provenance` now contains an explicit checked row for all 85 Lua 5.5
opcode meanings. Each row names its owner, publication/structural status, permitted
categories, and any remaining category-5 reason. The object audit separately records
the conditional-branch count of every branch-bearing exact residual section.

The ledger now reports zero category-5 opcode meanings. CALL and TAILCALL were the
last rows; their fixed authored argument counts are structural publication fragments.
Comparison/test opcodes 57..67 remain clean after S4.

**Acceptance: GREEN.** Every opcode row has an owner and permitted branch categories;
no published opcode retains a declared projection-time decision.

### S2 — Patch register byte displacements directly — COMPLETE

**Evidence:** even `loadk_int` executes:

```asm
mov target_index, %eax
shl $4, %rax
add frame_values, %rax
```

Arithmetic leaves repeat this for target, left, and right operands. Register indices
are projection-proven.

**First slice landed:** MOVE, LOADI, LOADF, LOADK/LOADKX exact constant leaves,
LOADFALSE/LFALSESKIP/LOADTRUE, and all eight exact LOADNIL leaves now patch
`16 * register` as `target_disp`/`source_disp`. Their C stencil uses one x86-64
`lea disp32(values), cell` rather than loading, shifting, and adding an index.
`loadk_int` fell from the audited nine-instruction address shape to: load values,
one patched LEA, materialize the exact constant, two stores, direct successor.

This audit also exposed and fixed a correctness bug: every old `loadnil_N` residual
stored nil into eight cells because its macro ignored `N`. Each leaf now emits exactly
N unrolled stores. `loadnil_preserves_higher_register` differentially protects the
case where a one-cell LOADNIL has a live higher register.

**Second slice landed:** all learned/exact arithmetic products, POW/POWK, all
comparison products, TEST, and TESTSET now use `target_disp`, `left_disp`, and
`right_disp`. RR leaves own three displacements; RI/RK leaves own only target/left
and synthesize the right operand. `addi_ii` has no right register/displacement hole.
The exact gate checks representative load, move, RR, RI, and comparison manifests.

**Third slice landed:** unary leaves, shared-upvalue value operands, closure targets,
GETVARG keys/targets, VARARG destination loops, numeric-for bases, TFORPREP/TFORLOOP,
CLOSE, TBC, and ERRNNIL now use explicit byte-displacement products. Numeric-for
residuals use one patched base pointer and constant field offsets for the aligned
init/limit/step spine. VARARG retains `target_index` only for its required `top`
calculation while using `target_disp` for value movement. The exact gate now protects
representative manifests from every landed slice.

**Fourth slice landed:** GETI, GETFIELD, GETTABUP targets, NEWTABLE targets, and
SELF target/object/receiver operands now use distinct displacement roles. This keeps
different structural meanings explicit rather than folding them into one generic
register patch. This prepared the shared table roles for the general block.

**Fifth slice landed:** general GETTABLE and all SETTABLE/SETI/SETFIELD exact
leaves now use `receiver_disp`, `key_disp`, and `source_disp` according to the exact
shape each leaf owns. Constant-value leaves do not receive a source displacement.
The shared receiver guard and learning images use the same products. Representative
GETTABLE and register-value SETTABLE manifests are enforced by the exact gate.

**Sixth slice landed:** register-valued SETTABUP leaves use `source_disp`,
and SETLIST uses exact base/source/array displacement roles. Fixed CALL/TAILCALL argument
fragments patch direct caller source and callee fixed-parameter target displacements;
only the callee-descriptor-dependent vararg slice remains dynamic.

**Seventh slice landed:** open native CALL/TAILCALL, host CALL/TAILCALL, TFORCALL, and
RETURN-all now patch their authored register base directly. Their logical `A` remains
only where `top`, result-sink base, overflow payload, or host ABI requires the authored
index. CONCAT composition now patches direct operand byte displacements into each selected
measure/write fragment; no non-structural scalar value base remains indexed.

**Required fix:** add exact signed displacement holes for `16 * register + field
offset`. Patch memory operands or one direct LEA displacement rather than loading,
zero-extending, shifting, and adding a register number at runtime. Apply this shared
shape to loads, moves, arithmetic, comparisons, tables, calls, returns, closures,
varargs, and iterators.

**Acceptance:** simple scalar leaves contain no `mov index; shl $4; add` sequence
for a projection-known register. `loadk_int` should approach: load values base, store
exact tag, store exact payload, direct successor jump.

### S3 — Remove dead and alias-only hole loads — COMPLETE

**Evidence:** `addi_ii` and `addk_ii` load `right_index`, then overwrite the same
machine register with the embedded immediate/constant. The shared RR/RI/RK prologue
declares operands that the selected shape does not own.

**Landed so far:** arithmetic, POW, and comparison RR/RI/RK prologues are split.
Immediate/constant products no longer declare or patch a dead right register. TEST
and TESTSET own distinct displacement sets. Remaining scalar families still require
the complete manifest/disassembly audit is now part of the scalar completion gate.

**Required fix:** split shared prologues into exact RR, RI, RK-int, and RK-float
operand products. A leaf manifest must contain only holes consumed by that leaf.
Keep intentional same-sentinel aliases out of the public manifest.

**Acceptance:** disassembly and the strict manifest show no loaded-but-unused hole
and no patched field that cannot affect the selected leaf.

### S4 — Eliminate runtime comparison polarity — COMPLETE

**Original evidence:** EQ/EQK and peers loaded the bytecode `k` flag, executed
`test/setne`, and compared it with the runtime comparison result. `k` is
projection-proven, not program data.

**Landed:** publication now selects a `_k0` or `_k1` concrete leaf for EQ, EQI,
EQK, LT, LTI, LE, LEI, GTI, GEI, TEST, and TESTSET. Learning images still receive
`k` because they must execute the authored control edge while learning; no published
comparison/test residual has a `k` hole. Each RX leaf performs its exact guards, one
semantic data comparison, and one polarity-specific conditional transfer.

The build contains 44 additional exact sections: the 40 learned comparison shapes
are paired by polarity, and TEST/TESTSET each have two direct residual leaves.
The exact gate checks every comparison/test manifest for a `_k[01]` suffix and the
absence of `holes.k`.

**Acceptance: GREEN.** No RX branch or setcc interprets bytecode polarity.

### S5 — Residualize all fixed counts — COMPLETE

Every projection-known runtime count is now structural at publication:

- fixed VARARG emits one guarded slot fragment per wanted result plus an exact `top`
  finish; VARARG-all retains its genuinely dynamic protocol loop;
- fixed SETLIST emits one hot/grow capacity decision followed by one exact source/array
  displacement fragment per authored value;
- fixed RETURN, RETURN0, and RETURN1 emit a capacity preflight, one source fragment per
  authored result, and a finish; RETURN-all and caller sink width remain dynamic protocol;
- TFORCALL's authored result count is stored directly in its result sink and never
  controlled a copy loop;
- fixed CALL and TAILCALL emit one exact prepare, one direct source/target fragment per
  authored argument, and one finish. Open-argument calls retain only the genuinely
  dynamic `top` protocol.

The S1 category-5 list fell from eight opcode meanings to zero.

The implementation is mechanical singular-opcode composition, not an IR, optimizer,
superinstruction, runtime count dispatcher, or universal copy loop. Open-result counts,
callee parameter counts, and genuinely variable vararg lengths remain runtime protocol data.


**Acceptance: GREEN.** No retained loop is controlled only by a bytecode-known count.
Published assembly contains exactly one slot operation per fixed occurrence operand.

### S6 — Resolve table hot/cold semantics — COMPLETE

**Decision:** array capacity and field presence are mutable program data. They are not
learned semantic alternatives. Published table-write leaves retain exact guards for key
domain, value domain, receiver ownership, table kind, and metatable-free semantics.
A changed exact domain publishes `SpecializationMismatchV2`; insufficient array capacity
or an absent exact field takes a named operation-owned data exit.

**Landed:** `NeedGrowV2` and `NeedCreateV2` are concrete publication values with
leaf-owned cold append/link behavior. Their physical executable holes are distinct:
`need_grow_link`, `need_create_link`, and `resume_link`. The former ambiguous
`grow_link`/`succ_link` vocabulary is absent from every residual manifest. SETI, integer
SETTABLE, and SETLIST publish `NeedGrow`; SETFIELD, string SETTABLE, and SETTABUP
publish `NeedCreate`. The selected operation resumes at its exact authored successor.

The learning image records key/value domains and NEWTABLE capacity hints, but does not
record in-bounds/existing as a semantic shape. Suppressing a learned preallocation hint
forces the published integer-key residual through `NeedGrow` and completes correctly;
the existing wrong-key-domain test still publishes typed mismatch instead of selecting
another implementation.

The isolated fused store-cycle inline-growth exception remains separate and explicit.

**Acceptance: GREEN.** Vocabulary, learner facts, leaf names, physical-hole manifests,
mutable-capacity execution, and mismatch tests now express one contract. No exact guard
failure transfers to another semantic implementation.
### S7 — Specialize exact constant-field locations where evidence permits — COMPLETE

GETFIELD, SETFIELD, SELF, GETTABUP, and constant-key SETTABUP now receive dedicated
learning slots. The family product records a concrete found/missing alternative, zero-based
field slot, field-vector capacity, and owning NEWTABLE site. Repeated observations must
agree on state, slot, and site; conflicting observations reject publication visibly.

Found reads publish `getfield_slot`, `gettabup_slot`, or `self_slot`. These leaves directly
index `field_values[field_slot]`, guard the projected field-vector capacity and key identity,
and contain no field scan. Mutable absence at the guarded slot returns nil as program data.
Found SETFIELD and SETTABUP hot leaves use the same direct guarded slot. Mutable vacancy
takes the existing named `NeedCreateV2` operation exit; its cold leaf creates the field and
verifies that the exact learned slot owns the result before resuming.

Missing read observations publish distinct `*_missing` program-data leaves. These retain
a field scan because runtime presence is mutable data under S6; they do not select a sibling
semantic implementation. Dynamic string-key GETTABLE remains separate because its key is
genuine runtime data.

NEWTABLE capacity learning can enlarge the retained image relative to the first invocation.
The field-location projection therefore combines the occurrence's observed capacity with
the owning site's final learned field high-water mark before patching the exact capacity
guard.

Executable manifests require `field_slot` and `field_layout_capacity` on every found hot/
cold field leaf and forbid `occ_slot` there. A deliberately corrupted learned slot produces
`SpecializationMismatchV2`; a learned missing field returns nil through its named leaf.

**Acceptance: GREEN.** Constant-field found hot paths do not linearly scan field capacity.
Changed slot/layout facts reject visibly, mutable vacancy uses `NeedCreate`, and missing
reads remain explicit program-data results.
### S8 — Tighten CALL, TAILCALL, and RETURN assembly — COMPLETE

**Original evidence:** the former monolithic `call_native_fixed` was approximately
1.1 KB and combined authored-count loops, frame preparation, copying, and transfer.
The former `ret_fixed` was approximately 617 bytes and retained count-controlled loops.

**Landed:** fixed RETURN is a composed begin/slot/finish path. Fixed CALL and TAILCALL
now use exact prepare/argument-slot/finish paths backed by named invocation-owned
`Lua55PreparedCallV2` and `Lua55PreparedTailCallV2` state. Each authored argument source
and fixed-parameter target uses a publication-patched byte displacement. Callee parameter
count and vararg-slice position remain descriptor protocol data. Native TAILCALL no longer
owns or publishes the host-only `tail_return` hole.

Current representative sections are 899-byte CALL prepare, 102-byte CALL slot,
138-byte CALL finish, 761-byte TAILCALL prepare, 97-byte TAILCALL slot, and 244-byte
TAILCALL finish. None contains a native guest `call` or `ret`, and no finish contains an
occurrence hole or authored-count loop.

After S2 and S5:

- use exact frame/value displacements;
- materialize exact argument/result copies;
- remove fixed-count branches;
- keep only capacity/ownership checks and genuinely variable result-sink joins;
- minimize callee-family guards to the learned class/vararg product; and
- preserve proper-tail guest control with no native guest `call` or `ret`.

**Acceptance: GREEN.** Focused call/return disassembly has no static-count loops or
guest-control call/ret. Nine representative byte/instruction budgets are executable,
and JIT/`-joff` call/recursion gates remain green.

### S9 — Move repeated mismatch publication off hot leaf bodies — COMPLETE

Published exact leaves no longer write the complete rejected boundary outcome. Each failed
exact guard writes only its occurrence pc, expected fact, and observed fact into the named
invocation-owned `specialization_mismatch` product, then tail-transfers through the
`mismatch_exit` physical hole.

The single `lua55_cps_specialization_mismatch` typed exit owns publication of
`SpecializationMismatchV2` and tail-transfers to the ordinary host boundary. This is one
fixed boundary operation, not a semantic dispatcher: the selected exact leaf still owns
every guard and supplies every mismatch fact.

The strict ledger patches all mismatch exits to the per-arena typed exit. The bank audit
currently covers 388 exact sections with `mismatch_exit`, rejects any residual that writes
the specialization rejection discriminant inline, and requires the named CPS exit manifest.
Representative `add_ii` now contains compact fact stores and indirect tail edges rather than
two complete rejected-outcome publishers.

No new native `call` or guest `ret` exists. Typed mismatch behavior, including corrupted
field slots and deliberately false learned domains, remains unchanged.

**Acceptance: GREEN.** Exact hot paths contain no inline specialization outcome publisher;
the single named typed exit owns boundary publication, and all mismatch gates remain green.
### S10 — Replace CONCAT Cartesian monoliths with exact fragment composition — COMPLETE

The 360 width/vector leaves are retired. The exact learned operand vector now mechanically
selects and appends:

1. one type-specific measure fragment per authored operand;
2. one allocation fragment;
3. one type-specific write fragment per authored operand; and
4. one finish fragment.

The closed fragment vocabulary is eight sections: string/integer/float measure, allocation,
string/integer/float write, and finish. Each measure/write fragment receives the authored
operand byte displacement directly. Integer and float fragments alone receive their exact
library address. `Lua55PreparedConcatV2` owns only the temporary total, string, and output
cursor needed across the selected fragment chain.

Every internal edge is a strict-ledger `fragment_next` physical hole patched before RX.
There is no runtime tag selection: each fragment guards its one selected shape and transfers
to the S9 typed mismatch exit if that learned fact changes. The final fragment alone owns the
ordinary opcode successor.

S10 first reduced the bank from 800 to 448 exact sections and from 936,323 to 175,711
exact bytes; the later recursive CALL/RETURN correction brings the completed bank to 450
sections and 177,213 bytes.
CONCAT falls from 360 sections / 761,812 bytes to 8 sections / 1,200 bytes, a 99.8% static
reduction. Core-pinned retained `concat10k` medians after composition were 0.358 ms for
V2 versus 1.153 ms for stock PUC Lua 5.5 (PUC/V2 3.22x). All widths and learned vectors
remain differential-identical under JIT and `-joff`; itoa/dtoa remain the only CONCAT
native-call boundaries.

**Acceptance: GREEN.** Exact vectors remain supported without generic classification;
Cartesian CONCAT leaves are absent from the published bank, and the fragment footprint is
an executable test gate.

### S11 — Make assembly properties executable gates — COMPLETE

The bank build now checks all 450 exact residual sections and records its result
in `bank.assembly_audit`:

- zero native `ret` instructions in exact residuals;
- native `call` restricted to the POW/POWK and CONCAT library allowlist;
- every ELF relocation restricted to `R_X86_64_PLT32 lua55_residual_next - 4`;
- every successor relocation proven to target an `e9` direct near jump;
- no external data/constant-pool relocation; and
- actual published arenas pass the S0 physical-hole ledger before `mprotect`;
- a local-CFG dataflow checker proves zero relative stack delta at all 1,650 reachable
  proper-tail edges across all 450 exact sections; and
- nine CALL/TAILCALL/RETURN fragments have executable byte and instruction budgets.

The checker distinguishes successor relocations from object-file rel32 placeholder
targets, follows every local conditional edge, requires equal stack state at joins,
recognizes explicit trap terminals, and rejects unsupported `%rsp` writes. The exact
suite checks the audit under JIT and `-joff`.

### S12 — Scalar-only differential and performance gates — COMPLETE

The staging/test-only `scalar_only` projection option suppresses numeric-for, canonical-call,
RMW, store-cycle, and accumulation fusion. It does not select another runtime or backend:
learning, exact residual publication, strict physical-hole linking, ownership, W^X, and
proper-tail native CPS remain identical. Every scalar plan carries an explicit marker and
`assert_scalar_plan` rejects any retained `super_*`, numeric-for, or call fusion.

The scalar differential oracle runs the complete focused stock Lua 5.5 corpus under JIT and
`-joff`. The existing exact suite independently retains deliberate typed mismatches, strict
publication-hole negatives, call/return assembly budgets, stack balance, direct field-slot
CFG checks, CONCAT fragment gates, closure/upvalue recursion, and ownership checks.

`run55_native_v2_scalar_perf_gate.lua` core-pins V2 and stock PUC Lua 5.5, measures median
retained execution, and enforces checked PUC/V2 ratio floors:

| retained scalar workload | representative JIT | representative `-joff` | floor |
|---|---:|---:|---:|
| arithmetic/comparison, 2M | 1.83× | 1.84× | 1.20× |
| recursive fib25 | **1.12×** | **1.13×** | **1.00×** |
| proper-tail recursion, 1M | 1.31× | 1.46× | 1.05× |
| numeric-for, 10M | 2.41× | 2.42× | 1.50× |
| table read/write, 5M | 1.29× | 1.23× | 1.15× |
| composed CONCAT, 10K | 3.47× | 3.03× | 1.50× |

Fibonacci's former regression is fixed through exact one-argument CALL and one-result RETURN
leaves. The mandatory parity floor remains executable; no superinstruction hides the result.

`run55_native_v2_scalar_gate.sh` runs scalar differential, exact/publication, performance,
JIT/`-joff`, and `git diff --check` sequentially. It does not run the repository suite.

**Acceptance: GREEN.** Scalar semantics match stock, no fusion can hide a regression, and
recursive Fibonacci clears the mandatory 1.00× PUC parity floor in both LuaJIT modes.

## Family status matrix

| family | semantic selection | mechanical status | blocking fixes |
|---|---|---|---|
| MOVE/basic loads/constants | exact direct displacements | **green** | — |
| arithmetic/bitwise/shifts | exact operand products; named mismatch exit | **green** | — |
| POW/POWK | exact products, explicit library boundary | **green** | — |
| unary/LEN/NOT | exact or legitimate result data; named mismatch exit | **green** | — |
| comparisons/tests | exact operands, selected polarity, named mismatch exit | **green** | — |
| GETTABLE dynamic domains | learned int/string domain, direct cells | **green** | — |
| constant-field operations | direct guarded found slots; named missing data leaves | **green** | — |
| table writes/SETLIST | exact families; named NeedGrow/NeedCreate data exits | **green** | — |
| NEWTABLE | learned capacity floor | **green** | — |
| numeric for | exact protocol/sign; scalar gate | **green** | — |
| CALL/TAILCALL | exact family; fixed counts composed; budgets green | **green** | — |
| TFORCALL | exact callee family; fixed result count is a sink field | **green** | — |
| RETURN/VARARG | fixed counts composed; dynamic protocols retained | **green** | — |
| CONCAT | exact operand vectors, composed exact fragments | **green** | — |
| CLOSURE | exact capture vectors 0..4 | **green** | — |
| upvalue/CLOSE/TBC | mutable protocol branches justified locally | **green** | — |
| JMP/loop/control/error leaves | semantic control exact | **green** | — |

All scalar families now satisfy the completion rule.

## Required implementation order

1. **S0 + S4 + S8 + S11: complete.** Keep all gates mandatory.
2. **S1 + S5: complete.** Keep the zero-category-5 and fixed-fragment gates mandatory.
3. **S2 + S3: complete.** Scalar value cells use direct role-specific displacements;
   dead and alias-only scalar index holes are absent from the gated manifests.
4. **S6: complete.** Keep named table-data-exit and mismatch gates mandatory.
5. **S7: complete.** Keep field-slot/layout, missing-result, and mismatch gates mandatory.
6. **S9: complete.** Keep named mismatch-exit and no-inline-publisher gates mandatory.
7. **S10: complete.** Keep the eight-fragment footprint and no-Cartesian-leaf gates mandatory.
8. **S12: complete.** Keep scalar differential, Fibonacci parity, and pinned floors mandatory.

## Scalar completion gate

New superinstruction families may resume only when all of the following hold:

- S0-S12 are complete;
- the branch-provenance inventory has no projection-time decisions in RX;
- all product/hole mismatches fail before publication;
- focused differential, mismatch, ownership, W^X, ABI, and JIT/`-joff` gates pass;
- scalar-only retained performance has no unexplained regression; and
- every family in this inventory is green.

Only then is the singular opcode machine an excellent foundation on which further
evidence-backed superinstructions should be built.
