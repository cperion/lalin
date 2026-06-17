# Backend Completeness Gaps

Audit date: 2026-06-17
Workflow: `wf-backend-gap`

The Cranelift backend (Rust `decode.rs`) has full codegen for all 111 wire tags.
The gaps are in the Lua compiler pipeline that *produces* those wire tags.

---

## Summary

| Layer | Count | Severity |
|-------|-------|----------|
| Encoder gaps (BackCmds exist, Rust ready, encoder drops them) | 7 | **High** — pure plumbing |
| Wire fidelity gaps (ASDL fields lost at wire boundary) | 1 | **Medium** — semantic loss |
| Lowering gaps (no path from .mlua to BackCmd) | 4 | **Varies** — deep to design-level |
| Tooling gaps (dead/stubbed paths) | 2 | **Low** — non-critical |

---

## Layer 1: Encoder Gaps

These ASDL `Cmd` variants exist in `lua/moonlift/schema/back.asdl`, have full
Cranelift codegen in `src/decode.rs`, but `lua/moonlift/back_command_binary.lua`
has no encoding branch. They are silently dropped, causing downstream
`"unknown value {id}"` errors when later instructions reference their results.

### CmdAtomicLoad

```
CmdAtomicLoad(dst: BackValId, ty: BackScalar, addr: BackAddress, memory: BackMemoryInfo, ordering: BackAtomicOrdering)
```

- **Wire tag**: `AtomicLoad` (112), 4 slots `[dst, scalar_type, memflags, addr]`
- **Rust**: `builder.ins().atomic_load(clif_ty, memflags, addr_val)` — full codegen
- **Encoder**: no branch
- **Lowering**: exists (used by C backend and test_atomics.lua)

### CmdAtomicStore

```
CmdAtomicStore(ty: BackScalar, addr: BackAddress, value: BackValId, memory: BackMemoryInfo, ordering: BackAtomicOrdering)
```

- **Wire tag**: `AtomicStore` (113), 4 slots `[scalar_type, memflags, addr, value]`
- **Rust**: `builder.ins().atomic_store(memflags, addr_val, val)` — full codegen
- **Encoder**: no branch
- **Lowering**: exists

### CmdAtomicRmw

```
CmdAtomicRmw(dst: BackValId, op: BackAtomicRmwOp, ty: BackScalar, addr: BackAddress, value: BackValId, memory: BackMemoryInfo, ordering: BackAtomicOrdering)
```

- **Wire tag**: `AtomicRmw` (114), 5 slots `[dst, scalar_type, memflags, op_kind, addr, value]` (note: op_kind is an additional slot not in Load/Store)
- **Rust**: `builder.ins().atomic_rmw(clif_op, clif_ty, memflags, addr_val, val)` — full codegen
- **Encoder**: no branch
- **Lowering**: exists
- **Hidden coupling**: op_kind numeric mapping (1=Add, 2=Sub, 3=And, 4=Or, 5=Xor, 6=Xchg) must stay synchronized between Lua encoder and Rust `decode.rs`

### CmdAtomicCas

```
CmdAtomicCas(dst: BackValId, ty: BackScalar, addr: BackAddress, expected: BackValId, replacement: BackValId, memory: BackMemoryInfo, ordering: BackAtomicOrdering)
```

- **Wire tag**: `AtomicCas` (115), 5 slots `[dst, scalar_type, memflags, addr, expected, replacement]`
- **Rust**: `builder.ins().atomic_cas(memflags, addr_val, expected_val, replacement_val)` — full codegen
- **Encoder**: no branch
- **Lowering**: exists

### CmdAtomicFence

```
CmdAtomicFence(ordering: BackAtomicOrdering)
```

- **Wire tag**: `Fence` (116), 0 slots — no data slots, pure side effect
- **Rust**: `builder.ins().fence()` — full codegen
- **Encoder**: no branch
- **Lowering**: exists
- **Note**: `Fence` has zero slots, making it the simplest to encode

### CmdRotate

```
CmdRotate(dst: BackValId, op: BackRotateOp, scalar: BackScalar, lhs: BackValId, rhs: BackValId)
```

- **Wire tags**: `Rotl` (63), `Rotr` (64), 3 slots `[dst, scalar_type, lhs, rhs]`
- **Rust**: `builder.ins().rotl(val_lhs, val_rhs)` / `builder.ins().rotr(...)` — full codegen
- **Encoder**: no branch
- **Lowering**: **does NOT exist** — no path from `.mlua` source to `CmdRotate`
- **Debug interpreter**: implements as shift: `"Simplified: just shift for now"`
- **This is a Layer 1 + Layer 3 combined gap**: missing from both encoder and lowering

### CmdVecMask

```
CmdVecMask(dst: BackValId, op: BackVecMaskOp, ty: BackVec, args: BackValId*)
```

- **Wire tags**: `VecMaskNot` (150, 2 slots), `VecMaskAnd` (151, 3 slots), `VecMaskOr` (152, 3 slots)
- **Rust**: `builder.ins().icmp_imm(IntCC::Equal, mask_not, 0)` / `builder.ins().band(bv, mask)` / `builder.ins().bor(bv, mask)` — full codegen
- **Encoder**: no branch
- **Lowering**: exists (vector mask operations are produced)
- **Complexity**: non-uniform arity — the encoder must dispatch on `cmd.op.kind` to select the right tag AND emit the right number of args

---

## Layer 2: Wire Format Fidelity Gaps

ASDL semantic fields that exist in the schema, survive lowering, but have no
corresponding slot in the binary wire format. They are silently discarded.

### Atomic Ordering

- **ASDL**: Every atomic command carries `BackAtomicOrdering` (currently only `BackAtomicSeqCst`)
- **Wire format**: Zero slots for ordering on `AtomicLoad`, `AtomicStore`, `AtomicRmw`, `AtomicCas`, `Fence`
- **Rust**: Hardcodes Cranelift's default atomic semantics (implicitly seq_cst on x86)
- **Cranelift capability**: `MemFlags` supports `set_readonly()`, `set_aligned()`, and ordering hints via `MemFlags::new()` with `Endianness` — but explicit relaxed/acquire/release require `MemFlags::set_atomic_ordering()` which is available in newer Cranelift
- **Impact**: Even after fixing the encoder, the `ordering` field in the ASDL is informational-only; all atomics are seq_cst

---

## Layer 3: Lowering Gaps

Features described in `LANGUAGE_REFERENCE.md` that have no compilation path from
`.mlua` source to `BackCmd` arrays. The Rust backend may or may not support the
underlying Cranelift IR — these features simply never reach it.

### Closures (`closure(i32): i32`)

- **Lang ref**: §5.8 — closure types are first-class
- **ASDL**: No `BackClosure` type, no wire tag, no schema definition
- **Lowering**: `code_to_back.lua` / `lower_to_back.lua` have no closure handling
- **Rust**: No Cranelift closure support (Cranelift doesn't have a closure primitive — closures require struct lowering of captured state + indirect call)
- **Nature**: Design-level gap — closures require a compilation strategy (capture struct layout, thunk generation, indirect call dispatch)

### Vector Reductions

- **Lang ref**: §18.4 — vector reductions (sum, min, max, etc.)
- **Lowering**: `lower_to_back.lua:631` — explicit error: `"vector reductions are not implemented"`
- **Rust**: Cranelift does not have dedicated reduction instructions — reductions must be lowered to shuffle + pairwise operations
- **Nature**: Implementation gap — requires a lowering strategy to decompose reductions into Cranelift vector ops

### View Return ABI

- **Lang ref**: §17 — views as return values from functions and regions
- **Lowering**: `code_to_back.lua:646` — explicit error: `"view return ABI is not implemented below Code"`
- **Nature**: ABI design gap — views are 3-element descriptors (data, len, stride); returning them requires a calling convention decision (sret pointer, multiple return registers, struct return)

### Handle Types

- **Lang ref**: §21.2 — `handle Voice : u32 invalid 0 end` memory convention
- **Lowering**: Memory convention only — no `BackCmd` emitted, no wire tag
- **Nature**: Design-level gap — handles are compile-time validity markers, not runtime objects; they may not need backend support

---

## Layer 4: Tooling & Dead Path Gaps

### Tape Compiler (DELETED — 2026-06-17)

- **Was**: `src/lib.rs` `compile_tape()` returned hard error: `"tape compiler not yet migrated"`
- **Was**: `lua/moonlift/tape_encode.lua` and `lua/moonlift/tape_exec.lua`
- **Status**: Fully removed. Only the binary wire format remains.

### Hosted JIT Disassembly

- **File**: `lua/moonlift/hosted_jit.lua`
- **Gap**: `Jit:peek()` errors: `"hosted_jit: disassembly/peek is not wired for hosted artifacts yet"`
- **Note**: The cdylib path (`back_jit.lua`) has working `disasm()` via objdump
- **Impact**: Low — disassembly is a debugging tool, not a compilation path

---

## The Silent-Drop Bug

The encoder's main dispatch loop has no `else` clause:

```lua
for _, cmd in ipairs(cmds) do
    local k = cmd.kind
    if k == "CmdCreateBlock" then ...
    elseif k == "CmdSwitchToBlock" then ...
    -- ... 50 branches ...
    -- NO else: unrecognized commands silently skipped
    end
end
```

This means any BackCmd variant without an encoder branch produces a shorter-but-structurally-valid
wire buffer. The Rust decoder then fails when a later instruction references a value that was
defined by the dropped command: `ctx.val() → "unknown value {id}"`.

Adding `else error("unrecognized BackCmd: " .. k)` would make gaps immediately visible at encode
time rather than as cryptic downstream failures.

---

## Test Coverage Mirage

`tests/test_atomics.lua` verifies that `CmdAtomicLoad`/`CmdAtomicStore`/etc. are produced
by lowering, then calls `jit():compile(program)` and asserts specific numeric results.
However, the encoder silently drops all atomic commands, meaning the `compile()` call
produces a function with undefined SSA values — the end-to-end assertion **never actually
executes successfully**.

The test correctly checks abstraction-layer output (BackCmd production) but the pipeline
integration test is dead code due to the encoder gap.

---

## Document-Vs-Code Discrepancies

### Splat Slot Count

- **`BACK_WIRE_FORMAT.md`**: Splat has 3 slots `[dst, scalar_type, src]`
- **`src/wire_tags.rs`**: Splat has 4 slots `[dst, scalar_type, lanes, src]`
- **Encoder**: writes 4 slots
- **Decoder**: reads 4 slots
- **Verdict**: The doc is wrong. `TAG_SLOTS` in `wire_tags.rs` is the authoritative contract.

---

## Development Trajectory Evidence

The gap pattern suggests this development history:

1. **Wire format designed first** — all 111 tags, all slot layouts
2. **Rust backend implemented** — all 111 tags get real Cranelift calls
3. **Lua lowering built incrementally** — only what was needed for immediate features
4. **Encoder built incrementally** — only what lowering produced
5. **Atomics added to ASDL, lowering, validation, C backend** — but binary encoder never plumbed
6. **Rotate, VecMask added to ASDL and Rust** — but lowering (for rotate) and encoder (for both) never completed

The ASDL schema is the "compiler model" — the single source of truth. Validation (`back_validate.lua`)
already validates ALL variants including the encoder-gapped ones. The Rust backend already compiles
ALL wire tags. The ONLY missing piece for the 7 encoder-gap variants is the Lua → binary encoder
dispatch.
