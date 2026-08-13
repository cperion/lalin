# OOPSLA 136 — Detailed gap analysis

Companion to `OOPSLA136_INSIGHT_COMPARISON.md`. This document examines each
gap between the paper's copy-and-patch technique and our Lua 5.5 native CPS
experiment in enough detail to plan corrective or measurement work.

Reference: Xu, H. and Kjolstad, F. 2021. *Copy-and-Patch Compilation.* Proc.
ACM Program. Lang. 5, OOPSLA, Article 136.

Current status context (audit date): V2 standalone ABI and core bank are
green; Milestones A/B/D and C/E/F are implemented; the binding corrective
milestone (Section 21 exact-residual specialization) is in progress with
**49 red**, **15 amber**, **16 green**, and **5 structural** opcode records.
In-flight work: table learning products (`Lua55TableLearnSlotV2`, `site_id`,
`SpecializationMismatchV2`).

---

## Gap 1 — Exact residual specialization (the paper's stencil variants) is incomplete

**Paper counterpart:** §3 (stencil variants), §4 (stencil selection as tree
pattern matching), §5 (MetaVar systematic variant generation).

**Paper's model.** For every AST node / bytecode, the library contains many
variants specialized to operand types, value locations, literal-vs-register
shapes, and common supernode patterns. At compile time, copy-and-patch
*selects* the most specific variant; the generated code therefore never
classifies runtime values to choose an implementation. The paper generates
the variants automatically (98,831 for the HLL, 1666 for WASM) from templated
C++ generators over a Cartesian product of metavars, filtered by validity
predicates.

**Our situation.** The bank is hand-authored and the *doctrine* is right —
"a published residual may guard its selected semantic shape and execute it;
it must not classify runtime values to choose a different implementation" —
but the *records* are not all migrated. Concretely:

- **Constants:** `LOADK`/`LOADKX` and arithmetic/comparison `K` records
  branch on the statically known constant tag; constant table writes load
  tag, integer, float, and reference holes and select a payload on every
  execution. Required leaves are tag-specific (Nil, False, True, Integer,
  Float, String, references) with no unused holes.
- **Arithmetic 21–45:** all records classify integer/float operand
  combinations at runtime; bitwise/shift also choose integer vs
  exactly-integral-float conversion in the residual. Required leaves:
  `IntegerIntegerAdd`, `IntegerFloatAdd`, `FloatIntegerAdd`,
  `FloatFloatAdd`, … Conversion, zero-division, and metamethod rejection are
  guards/exits of the selected leaf, not routes to siblings.
- **Unary 49/50/52:** `UNM` int-vs-float, `BNOT` int-vs-integral-float,
  `LEN` string-vs-table.
- **Comparisons 57–65:** EQ/LT/LE/EQK/EQI/LTI/LEI/GTI/GEI classify
  integer/float/string/identity alternatives after publication; each exact
  operand pair needs its own leaf.
- **Dynamic tables 12/16:** `GETTABLE` chooses integer-array vs string-field
  by key tag; `SETTABLE` chooses array vs field write and bundles in-bounds
  write, growth, field creation, and rejection. The constant `SETTABLE`
  record is 1,334 bytes and reconstructs every constant payload alternative —
  the measured sieve bottleneck (array construction/growth 5.1× slower than
  stock; absent reads already 2.77× faster, preallocated writes 1.25×).
- **CONCAT 53:** scans operands twice and selects String/Integer/Float
  formatting inside both loops; must carry an exact operand-shape vector.
- **Calls 68/69/76:** classify native closure, builtin closure, invalid
  callee, descriptor, fixed/open arguments, vararg behavior in one record.
  Required leaves: native fixed, native vararg, host builtin, rejection.
- **Numeric-for 73/74:** FORPREP/FORLOOP choose int/float protocol at
  runtime and FORPREP converts mixed int/float triples and chooses step sign.
  Required: integer/float × positive/negative-step leaves (loop continuation
  is program data, not dispatch).
- **CLOSURE 79:** receives a static capture count and instack/index pairs,
  then branches on them at runtime; must select exact unrolled capture-vector
  leaves.
- **GETVARG 81:** chooses integer-index, string `"n"`, and other-key
  behavior by tag.

**Amber leftovers** (`LOADNIL` count loop, `GETUPVAL`/`SETUPVAL` open/closed
state, `GETTABUP`/`SETTABUP` field presence/create, `GETI`/`GETFIELD`/`SELF`
present/missing, `SETI`/`SETFIELD` in-bounds/grow, `TBC` nil/false guard,
`RETURN` fixed-vs-open B, `TFORPREP` nil-closing, `SETLIST`
in-bounds/growth/barrier, `VARARG` `wanted == -1`) are second-wave splits;
static alternatives must split, while genuinely mutable state (open-cell
state, result-sink joins) may remain an explicit protocol branch.

**Staging dispatch violations** (Lua side, not RX): `ArithOccurrence`,
`CompareOccurrence`, `UnaryOccurrence`, `PowOccurrence` derive an opcode from
`quote_base`; `GenericTableOccurrence` uses learner-name/opcode `if/elseif`;
`ReturnOccurrence` uses learner-name string selection; call-plan return
discovery inspects `occ.learner_name`. These must move to concrete occurrence
leaf methods.

**Impact.** Until zero red cases, a hot residual pays tag-classification
branches, larger records (worse icache), and bundled cold paths (growth,
create, rejection) inside the hot leaf. The sieve regression is the visible
cost; the general cost is that we are running a generic interpreter-shaped
record instead of the paper's specialized variant.

**Binding corrective plan (already written):** Section 21 of
`NATIVE_CPS_V2_COMPLETE_MIGRATION_DESIGN.md` and the inventory's migration
order. Required order: constants → tables (isolate growth into cold tail
leaves) → arithmetic/unary/comparison → numeric-for → calls/TFORCALL →
CONCAT → CLOSURE → amber splits + staging dispatch removal. Completion gates:
zero red, no static amber, disassembly shows one selected implementation per
hot leaf, deliberate mismatches publish typed outcomes, all gates green.

**What this gap is not.** It is not a call to adopt MetaVar template
generation or a generic specialization engine. The hand-authored closed
vocabulary is a deliberate scope decision; the gap is completing the
*splitting*, not building generation machinery.

---

## Gap 2 — No pass-through register protocol for general temporaries (§3, Fig 8)

**Paper's model.** Stencils exchange values through the calling convention
itself: a producer adds a value as a new continuation parameter (lands in a
register), intervening stencils protect it with a pass-through parameter of
the widest type (`uint64_t`/`double`) forwarded verbatim to their
continuation (a no-op in machine code), and the lifetime ends when the value
is no longer forwarded, freeing the register. Because pass-throughs use the
widest type, the prototype space does not explode. The WASM compiler tracks
`numInRegInts`/`numInRegFloats` per instruction to choose variants. Values
crossing calls must be spilled (all registers caller-saved under GHC); the
paper plans this with a register watermark (modified Sethi-Ullman).

**Our situation.** A fixed SysV register protocol carries the frame and a few
accumulators (`rdi` frame, `rsi` accumulator, `rdx` limit, `rcx` step, `r8`
index, `r9` reserved); all guest values are frame-resident in
`Lua55NativeFrameV2.values[]`, stable for the full activation. There is no
pass-through mechanism, no per-occurrence register-shape variant dimension,
and no register planning pass.

**Why this is a real gap, not just a difference.** The paper's headline
execution results come substantially from register-resident temporaries
(Fibonacci: only one spill across a call; otherwise registers end-to-end).
Frame-resident values are strictly weaker for expression-heavy code: every
temporary read/write is a memory access. Our fused numeric-for superstencil
shows what register residency buys (0.218–0.23 ns/guest iteration vs 0.97 ns
generated-Lua exotype), but that advantage is locked inside one closed leaf.

**Arguments for the current design (to weigh, not dismiss).**
- Stable register addresses mean "temporary crosses a call" is free — the
  paper's caller-saved spill problem disappears entirely. For a bytecode VM
  whose values are call-visible by construction, frame residency is the
  simpler correct answer.
- The paper's own data: mem2reg (keeping *locals* in registers) gave 10%
  speedup at 3× compile cost and was rejected. Register-resident *temporaries*
  are the part they kept, though.
- Implementing pass-through variants means a new variant dimension across
  every opcode family (exactly what MetaVar auto-generates for them), which
  collides with our hand-authored closed vocabulary and current 49-red
  backlog.

**Options.**
1. **Keep frame-resident, close the gap by measurement:** add a benchmark
   that is expression-heavy (long dependent arithmetic chains), quantify the
   frame-resident penalty, and only then decide whether a register protocol is
   worth the variant explosion. This is the honest first step.
2. **Closed-slice promotion:** generalize the fused-loop trick — promote a
   small, projected set of values (e.g. numeric-for induction registers,
   accumulator chains with provably frame-local lifetime) into the existing
   accumulator registers with a matching stencil variant, without a general
   pass-through mechanism.
3. **Full pass-through protocol:** only if (1) demonstrates it is
   performance-relevant for our workloads. This is the paper's mechanism in
   full and would be a major addition to the bank vocabulary and the
   selection products.

**Recommendation.** Do (1) first; add a dependent-arithmetic-chain and a
numeric-loop-with-multiple-live-temporaries benchmark to `PERFORMANCE.md`,
then decide between (2) and (3). Do not build a generic register allocator —
the design doctrine forbids generic machinery and the paper's own Sethi-Ullman
variant was chosen for low overhead, not optimality.

---

## Gap 3 — Systematic stencil variant *generation* (MetaVar, §5) is absent

**Paper's model.** Stencil generators are templated C++ functions over
metavar sets (types, booleans, enums) with validity filter functions;
MetaVar instantiates the Cartesian product, compiles with Clang, extracts
configuration+stencil pairs from the object file (symbol names from function
pointers, relocation records for holes), and emits a library mapping
configurations to stencils. This is what makes 98,831 stencils practical.

**Our situation.** No generator machinery; the bank is a hand-written C file
with one `lua55_v2_*` section per leaf and Lua `append_v2` methods per
occurrence class. Variant count is small and deliberate.

**Why this is acceptable.** The paper's MetaVar exists to *manage volume*;
our closed Lua 5.5 machine does not need 100k stencils. The doctrine
explicitly prefers named family-specific selection products and exact leaves
over a universal generation engine. Introducing template-metaprogramming
generation would violate the "no generic specialization framework" rule in
`PROJECT_SCOPE.md` and AGENTS.md.

**Residual risk to acknowledge.** Hand-authoring means the variant space is
only as complete as we enumerate it. The inventory process (one C section per
exact leaf, manifest validation) is our substitute for MetaVar's filter
functions. The completeness check must be the residual-manifest test: every
publishable bank record requires a named exact selection, and every family
test deliberately supplies the wrong shape and asserts the typed mismatch
exit. That test suite is the real gap-closer here, not generation.

---

## Gap 4 — No two-pass planning / spill slot reuse (§4)

**Paper's model.** Two post-order AST traversals: first plans register usage
(watermark below which temporaries are spilled; temporaries crossing calls
spilled; stack offsets assigned; dead spill slots reused), second selects
stencils and builds the CPS call graph. Then one depth-first copy pass.

**Our situation.** One deterministic numeric traversal of the bytecode plan
with leaf-owned `append_v2`; exact frame shapes per proto (`value_capacity`,
vararg slice, TBC capacity) with no spilling; no slot reuse; frame-region
high-water mark constant across tail recursion (million-iteration tail in
4 KiB).

**Assessment.** This is a *structural* gap only if we adopt Gap 2 option (3).
Without register allocation, there is nothing to plan in pass one and nothing
to reuse. If we ever promote values to registers, the frame-layout half
(offsets for the residual frame) stays as-is; the register-planning half would
be the closed-slice version from Gap 2 option (2). No action today beyond
recording the dependency.

---

## Gap 5 — Missing measurement: machine-code generation throughput (MB/s)

**Paper's model.** Headline numbers: WASM codegen 300+ MB/s on large modules
(single CPU), startup delay 4.9–6.5× lower than Liftoff, compile time less
than AST construction for the HLL, linear scaling up to 800k statements.

**Our situation.** `PERFORMANCE.md` reports per-path and per-iteration
execution plus cold-construction staging (setup + first reach ≈ 151.7
µs/module for the generated-Lua exotype), but there is **no MB/s figure for
machine code produced** and no scaling curve.

**Why it matters.** The paper's thesis is that copy-and-patch replaces
interpreters and LLVM -O0 *because* codegen is essentially free. Our
execution results (3.8–5.8× under JIT, fused loop 7–18×) are the right half
of the claim; the codegen-cost half is unmeasured, so we cannot currently
claim the paper's "negligible startup delay" result for the V2 machine.

**Action.** Add a `codegen_throughput` probe to `perf_bench.lua`: build N
retained V2 invocations of a mid-size proto (table-heavy and call-heavy), sum
arena bytes produced (sum of copied section sizes), and report MB/s and
µs/module. Also measure retained re-entry cost separately from cold build so
the paper's "build once, execute many" shape is visible. Add a small scaling
probe (proto with k identical blocks, k = 10/100/1,000) to demonstrate the
near-linear property.

---

## Gap 6 — Host-call mechanism differs from the paper (§4); paper's is not better, but the comparison should be documented

**Paper's model.** External functions are wrapped to `void*(void*)` with an
argument array; the call node checks a thrown-exception flag and branches to
destructor/exception propagation; generated code efficiently calls host C++
and propagates C++ exceptions.

**Our situation.** Typed suspension: guest→host CALL publishes
`NativeHostCallV2(frame, resume_entry, A, B, C, pc, host_id)`; Lua validates
the id, converts the exact bounded argument slice, executes the library
function, converts results to mmap guest values, applies fixed/all and
nil-fill rules, checks capacity, and re-enters `resume_entry(frame)`.
TAILCALL in host position uses a per-occurrence `HostTailReturnV2` stub that
performs the ordinary RETURN protocol. No native-to-Lua callbacks; no
exception machinery; every result-capacity failure is a typed overflow
outcome.

**Assessment.** The paper's wrapper is C++-specific (exceptions, reference
semantics) and would be a strict regression for our ownership model (Lua
callbacks from RX memory are forbidden by the design). The gap here is only
documentary: note in the comparison that our suspension is the bytecode-VM
analogue of the paper's external call node, chosen for ownership rather than
speed. One performance consequence to measure: each host call crosses the FFI
boundary twice (suspend + resume); the paper's native wrapper has no such
boundary for C++ calls. If host-heavy workloads matter (e.g. `math.*`, string
formatting in CONCAT is already native via dlsym'd helpers), a native
builtin-call fast path through a patched `ExternalHelper64`-style entry
(similar to the `pow` hole) is the natural follow-up — **not** a Lua callback.

---

## Gap 7 — W^X and memory model are stricter than the paper; document as a feature

**Paper's model.** A code memory manager allocates executable memory;
copy-and-patch writes stencils and patches them in place. W^X is not
discussed.

**Our situation.** Arenas are built RW in page-isolated mmap, sealed to RX
once, never rewritten; executing RX memory is immutable by contract; guard
mismatch publishes a typed outcome instead of patching. This is strictly
stronger and consistent with the experiment's ownership doctrine.

**Action.** None beyond keeping the W^X gate in the validation suite. The
comparison file records this as "beyond the paper".

---

## Gap 8 — Supernode breadth for tables (part of Gap 1, but call it out)

The paper's WASM compiler deliberately ships **no** supernodes (35 kB, 1666
stencils) and still beats Liftoff; the HLL compiler's supernodes are what
push it past LLVM -O0. Our closed V2 bank is the WASM-shaped configuration
(small, few supernodes), with a few high-value fused leaves (numeric-for,
compare+JMP, SETLIST).

**Implication.** Our table performance gap (5.1× growth regression) is a
*variant-breadth* problem, exactly what the paper solves with more
supernodes. The corrective plan's exact table leaves
(`SetArrayIntegerKeyBooleanTrueInBounds/Grow`, `GetArrayIntegerKeyPresent/
Missing`, field variants) are the supernode additions that close it. Once the
learning image observes allocation-site capacity, residual `NEWTABLE` can
preallocate the guarded observed floor, removing repeated retained-run growth
cost — this is the paper's "specialized AST node implementations" applied to
tables.

---

## Gap 9 — The paper's future-work list is our active roadmap; keep it explicit

Paper §9 future work: common subexpression elimination, loop unrolling,
vectorization, and — for dynamic languages — type profiling, type
speculation, inline caching.

**Our status.** Type profiling/speculation is *being implemented* (learning
image, shape products, guarded leaves, mismatch outcomes). Loop unrolling and
vectorization exist only as closed superstencils (F64 map pipeline, fused
numeric-for), not as general mechanisms. CSE is not pursued.

**Action.** Keep the learning image scoped to family-specific products; do
not let it grow into a general profiler (that would collide with the "no
profile databases" stop-work item in `PROJECT_SCOPE.md`). Record in the
project scope that the learning image is the paper's type-speculation future
work, implemented under exact-residual constraints.

---

## Prioritized action list

1. **Close Gap 1 (binding):** complete the table batch (constants first,
   then exact table leaves with cold growth tails, NEWTABLE capacity floor
   from learned allocation sites), then arithmetic/comparison/numeric-for/
   calls/CONCAT/CLOSURE per the inventory order. Remove staging
   `quote_base`/`learner_name` dispatch. Zero red cases is the gate.
2. **Close Gap 5 (measurement, cheap):** add codegen MB/s throughput and a
   scaling probe to `perf_bench.lua`; report cold build vs retained re-entry
   separately.
3. **Investigate Gap 2 (register residency):** add expression-chain and
   multi-live-temporary benchmarks; decide frame-resident vs closed-slice
   promotion with data, not doctrine.
4. **Document Gap 6:** note the suspension mechanism as the ownership-clean
   analogue of the paper's external-call wrapper; consider a native builtin
   fast path via patched helper entries if host-heavy workloads regress.
5. **Keep Gap 3/Gap 4 closed by doctrine:** manifest tests and deliberate
   mismatch tests are the substitute for MetaVar generation; no generic
   allocator or generator machinery.

Dependency note: Gap 1 table completion enables Gap 5's realistic throughput
numbers (the current 1,334-byte SETTABLE record is not representative of the
final bank); Gap 2 option (3) would reopen Gap 4.
