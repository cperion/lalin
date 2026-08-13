# OOPSLA 136 — Insight comparison against the Lua 5.5 copy-and-patch CPS experiment

Reference: Xu, H. and Kjolstad, F. 2021. *Copy-and-Patch Compilation: A Fast
Compilation Algorithm for High-Level Languages and Bytecode.* Proc. ACM
Program. Lang. 5, OOPSLA, Article 136.

Scope: `experiments/copy_patch_cps/lua55_trace/` (Native CPS V2 machine). This
document maps every actionable insight of the paper to our implementation
status. It is an audit, not a design change.

Status legend:

- **Used** — the insight is implemented and enforced.
- **Partial** — the insight is present in doctrine or in a closed slice, but
  not generalized or not complete.
- **Not applicable** — the insight targets the paper's high-level-language
  (AST) use case or a mechanism we deliberately replaced with a stricter
  alternative.
- **Beyond the paper** — we implement something the paper only lists as future
  work or does not describe.

---

## 1. Binary stencils with holes (§2.1, §3)

**Used.**

A binary stencil is a pre-built binary implementation with missing values
(literals, register/stack offsets, branch and call targets) patched in at
runtime.

| Paper | Ours |
|---|---|
| Stencils compiled by Clang from C++ generators | Stencils compiled by GCC `-O3 -fno-pic -ffunction-sections -fno-stack-protector` from a closed C vocabulary (`opcode_v2_core_stencils.c`, `lua55_v2_*` / `lua55_cps_*` sections) |
| Missing values recorded as relocation-driven patch records (Fig 10) | Typed hole vocabulary consumed from ELF relocations: `RegisterIndex32`, `ConstantTag32`, `ConstantBits64`, `GuestReference64`, `SuccessorEntry64`, `ContinuationEntry64`, `HostTailReturnEntry64`, `HostExitEntry64`, `ExternalHelper64`, `PrototypeIndex32`, `BytecodePC32` |
| Patching = memcpy + scalar additions (Fig 10) | Patching = byte copy + classified hole writes during deterministic arena build |
| No instruction-encoding knowledge needed | Bank builder classifies relocations only; unsupported relocation shapes reject the build |

## 2. Continuation-passing style; tail calls become jumps (§2.1, §3, Fig 7)

**Used.**

Control is passed directly to the next stencil; continuation calls are tail
calls, so the compiler lowers them to jumps.

| Paper | Ours |
|---|---|
| CPS with GHC calling convention | Proper-tail native CPS over SysV: guest control is jumps, never C returns |
| "Calls to pass on control are tail calls" | Mechanical ABI gate: no `call`/`ret` in any V2 guest section; `lua55_cps_host_exit` is the only declared `ret` |
| Continuations are addresses patched into the binary | `SuccessorEntry64` / `ContinuationEntry64` / `HostTailReturnEntry64` holes patched into immutable RX records |

## 3. Register allocation via calling convention + pass-through parameters (§3, Fig 8)

**Partial — the biggest divergence.**

The paper's trick: repurpose the function prototype / calling convention as a
register allocation protocol. A value is kept in a register by adding it as a
continuation parameter; a pass-through parameter protects a register through
stencils that do not consume it; a value's lifetime ends when it is no longer
passed on. Pass-throughs use the widest type (`uint64_t`/`double`) to avoid
exponential prototype explosion. The paper's WASM compiler tracks
`numInRegInts`/`numInRegFloats` per instruction for the same purpose.

Ours: a fixed register protocol carries the frame and a few accumulators
(`rdi` frame, `rsi` accumulator, `rdx` limit, `rcx` step, `r8` index, `r9`
reserved), while guest values are **frame-resident** (`Lua55NativeFrameV2`
`values[]` stable for the whole activation). There is no pass-through
parameter mechanism and no register watermark planning for general
temporaries.

Consequences:

- We deliberately trade register-resident temporaries for stable register
  addresses. This makes "temporary crosses a call" free (no spill across
  caller-saved registers, which the paper must plan around).
- Native register promotion exists only inside the closed fused numeric-for
  superstencil (sum/index/limit/step held in registers for the loop).
- The paper's Sethi-Ullman-style register planning and spill slot reuse
  therefore have no counterpart here.

## 4. Stencil variants (§3) — exact-residual specialization

**Partial — mandatory corrective work in progress.**

The paper generates many stencil variants per node as a Cartesian product of
parameter configurations (operand location, literal vs register, spill) and of
code patterns (supernodes). Selection happens at compile time, so the runtime
does no tag dispatch.

Ours: the closed V2 bank is hand-authored, and the **exact-residual doctrine**
(Section 21 of `NATIVE_CPS_V2_COMPLETE_MIGRATION_DESIGN.md`;
`V2_RESIDUAL_SPECIALIZATION_INVENTORY.md`) mandates one selected semantic
shape per published residual, with a guard and a single typed mismatch exit.
The audit currently counts **49 red** (runtime semantic dispatch in RX), **15
amber**, **16 green**, **5 structural** across the 85 opcodes.

The current work (family-specific learning products — `Lua55TableLearnSlotV2`,
`site_id`, `SpecializationMismatchV2`, `NativeRejectedPayloadV2` expected/
observed tags) is the table batch of this migration (§21.6 Step E), which is
the paper's stencil-variant insight applied by hand.

## 5. Supernodes / superinstructions (§3, §4)

**Used.**

A stencil for a common AST subtree or bytecode sequence lets the compiler
optimize across node boundaries (e.g. advanced addressing modes, fused
compare+branch).

Ours:

- Fused numeric-for superstencil (`IntegerAddForLoopPlan`: FORPREP → ADD →
  MMBIN companion → FORLOOP), with the loop induction in native registers.
- Each comparison owns its following `JMP` (taken branch exits at the exact
  target PC).
- `SETLIST` fills registers directly into array storage; table access
  stencils fuse read/write + constant payloads.
- Whole-region superstencils (F64 map pipeline, negative-space suite) exist as
  separate closed benchmarks outside the Lua 5.5 machine.

## 6. Jump elision / fallthrough (§4)

**Used.**

Stencils are copied depth-first into contiguous memory so most successors
land immediately after their predecessor; those jumps are elided. The paper's
guarantee: a node with a fixed non-conditional predecessor always elides its
jump.

Ours: the linker strips terminal jumps between straight-line snippets;
straight successors end in classified jumps; only terminal/host-exit stubs
carry the outer `ret`. Remaining jumps correspond to genuine control flow
(branches, loops, calls, returns) as in the paper.

## 7. Frame layout and spill slot reuse (§4)

**Not applicable as stated.**

The paper plans a stack frame during the AST traversal, assigns offsets to
locals and spilled temporaries, and reuses a spilled slot once its lifetime
ends. Ours uses exact per-proto frame shapes (`value_capacity`, vararg slice,
TBC capacity) with no spilling, so slot reuse never arises. Frame-region
high-water mark stays constant across tail recursion (million-iteration tail
fits in 4 KiB).

## 8. mem2reg (§4)

**Aligned with the paper's conclusion.**

The paper prototyped mem2reg (register promotion of hot locals), measured
~10% execution gain at ~3× compilation cost, and declined it. Ours keeps
locals frame-resident by construction and promotes only the closed fused loop
— the same trade, taken as a permanent design decision rather than a measured
one.

## 9. External / host calls (§4)

**Used, with a stricter mechanism.**

Paper: external functions are wrapped to take a single `void*` parameter
array; the external call node checks a boolean "exception thrown" flag and
branches to destructor/exception-propagation code.

Ours: guest→guest calls are native proper-tail frames (bump-allocate callee
frame, exact varargs, patched continuation, `jmp` entry). Guest→host/library
calls **suspend** with a typed outcome (`NativeHostCallV2` /
`NativeHostTailCallV2`), Lua executes the library function, converts results
into mmap guest values, and re-enters the exact patched continuation entry.
There are no native-to-Lua callbacks. This is the paper's boundary insight
with cleaner ownership and no exception machinery.

## 10. Unified single API for bytecode codegen (§5, Fig 16)

**Used in spirit.**

Paper: one API `WasmEmitStencil(dst, opCode, numInRegInts, numInRegFloats,
spillOutput, ...)` that is just an array lookup + copy + patch — "there is not
even a switch case on the opcode".

Ours: leaf-owned `append_v2` methods on concrete occurrence classes; the
arena build is a deterministic numeric traversal with no opcode dispatch loop.
The paper's "no switch" is echoed by the leaf-owned doctrine. Remaining
violations are staging-side (`quote_base`/`learner_name` string selection in
`ArithOccurrence`, `CompareOccurrence`, `UnaryOccurrence`, `PowOccurrence`,
`GenericTableOccurrence`, `ReturnOccurrence` — see the inventory), not
residual-side.

## 11. Relocation-driven hole discovery and patch arithmetic (§5.2, Fig 10/12)

**Used.**

Paper: extern-symbol placeholders force Clang to emit relocation records
identifying hole locations; patches are pc-relative (`pc32 -= dst`) or
symbol-relative (`sym32/64 += patch`); small code model caveat on x86-64.

Ours: `build_v2_bank.lua` requires `R_X86_64_PLT32` → `lua55_residual_next`
with addend −4 for successor edges; `-fno-pic` avoids the small-code-model
trap for absolute helpers (dlsym-resolved `ExternalHelper64` holes for libm
`pow`, `lua55_itoa_ll`, `lua55_dtoa_g14`). Every relocation and sentinel
occurrence is consumed exactly once by its section's leaf patcher.

## 12. Linear-time code generation and negligible startup (§4, §7.4)

**Used, partially measured.**

Paper: two AST traversals + one call-graph traversal, near-linear scaling,
300+ MB/s machine-code throughput on large modules, compilation time less
than AST construction.

Ours: deterministic linear arena build (bytecode is the plan; no trace IR,
SSA, scheduler, or dispatch loop). We measure cold construction and per-path
execution (see `PERFORMANCE.md`), but we have **no MB/s code-generation
throughput figure** comparable to the paper's headline number. This is a
measurement gap, not a design gap.

## 13. Template-JIT comparison: patching is the differentiator (§8.1)

**Used.**

Paper's key contrast with older template JITs: they could only concatenate
unmodified snippets (indirect jumps, constants from memory); copy-and-patch
patches literals, stack offsets, and jump addresses, making jumps and calls
direct and constants immediate.

Ours is fully in the patching world: every successor, continuation,
constant, register index, and external helper is a patched hole; there is no
indirect dispatch in recurring guest control.

## 14. Type profiling and speculation (§9 future work)

**Beyond the paper.**

The paper's future-work list for dynamic languages: type profiling, type
speculation, inline caching. We are implementing exactly this: a **separate
learning image** (family-specific learner bank) observes the first
invocation's runtime shapes and writes named per-occurrence shape products
into invocation-owned mmap storage; the immutable residual image is then
linked with one exact C leaf per selected product; a later guard mismatch
publishes typed `SpecializationMismatchV2` without rewriting RX or running a
sibling implementation.

---

## Summary table

| Paper insight | Status |
|---|---|
| Binary stencils with holes | Used |
| Relocation-driven patching, no encoding knowledge | Used |
| CPS proper-tail, calls→jumps | Used |
| Burned-in constants, direct branches | Used |
| Supernodes / superinstructions | Used (closed fused leaves) |
| Jump elision / fallthrough | Used |
| External call boundary | Used (typed suspension, stricter than paper) |
| mem2reg rejection | Aligned (by design) |
| Unified no-switch codegen | Used in spirit; staging dispatch violations remain |
| Stencil variants (exact residuals) | **Partial — 49 red cases, migration in progress** |
| Pass-through register protocol for temporaries | **Partial — frame-resident values; only fused loop uses registers** |
| Two-pass planning + spill slot reuse | Not applicable (no spilling) |
| Systematic MetaVar variant generation | Not used — hand-authored closed vocabulary (by design) |
| MB/s codegen throughput measurement | **Missing measurement** |
| Type profiling / speculation | Beyond the paper (future-work section) |

Related design documents:

- `NATIVE_CPS_V2_COMPLETE_MIGRATION_DESIGN.md` — binding V2 architecture and
  Section 21 exact-residual doctrine.
- `V2_RESIDUAL_SPECIALIZATION_INVENTORY.md` — exhaustive per-opcode audit
  (red/amber/green/structural).
- `LUA55_OPCODE_INVENTORY.md` — frozen Lua 5.5.0 opcode baseline.
- `PERFORMANCE.md` — measured runtime and staging numbers.
- `OOPSLA136_GAP_ANALYSIS.md` — detailed treatment of each gap.
