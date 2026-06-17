# Backend Completeness Audit 
Map the gap between LANGUAGE_REFERENCE.md features and the Cranelift backend implementation. Identify every unsupported BackCmd variant, stub, and missing codegen path.
**Workflow ID**: wf-backend-gap
**Started**: 2026-06-17 19:46:03
---

## Scout Output — 2026-06-17 19:47:53

Now I have all the materials. Let me compile the comprehensive gap map.

---

## Files Retrieved

| # | File | Purpose |
|---|------|---------|
| 1 | `LANGUAGE_REFERENCE.md` (all 3057 lines) | Complete language spec — all types, ops, control, fragments, intrinsics, atomics, memory |
| 2 | `src/wire_tags.rs` (full) | All 111 Rust WireTag enum variants serving as the bridge contract |
| 3 | `src/decode.rs` (full) | Rust body decoder — `decode_body()` is the complete per-tag codegen dispatch (~600 lines) |
| 4 | `src/lib.rs` (full) | Top-level: JIT, object emission, `compile_tape` (stubbed), `compile_binary`, error types |
| 5 | `src/ffi.rs` (full) | C FFI surface — `moonlift_jit_compile_binary`, `compile_tape` absent from FFI |
| 6 | `src/main.rs` (full) | Host binary — uses `_host_compile_binary` via hosted_jit.lua, never tape |
| 7 | `lua/moonlift/schema/back.asdl` (full) | ASDL schema — all `BackCmd` variants, `BackScalar`, `BackLiteral`, ops, vec types |
| 8 | `lua/moonlift/back_command_binary.lua` (full) | Binary wire encoder — Lua→Rust bridge encoding dispatch |
| 9 | `lua/moonlift/back_jit.lua` (full) | FFI-based JIT bridge (loads `libmoonlift.so`) |
| 10 | `lua/moonlift/hosted_jit.lua` (full) | In-process hosted JIT (used by `moonlift` binary) |
| 11 | `lua/moonlift/lower_to_back.lua` | LowerModule→BackProgram: vector kernel lowering with stubbed reductions |
| 12 | `lua/moonlift/code_to_back.lua` | MoonCode→BackProgram: view return ABI stubbed |
| 13 | `lua/moonlift/tree_control_to_back.lua` | Control regions→BackCmd (blocks, jumps, brif, switch, phi) |
| 14 | `lua/moonlift/tape_encode.lua` | Legacy text tape encoder (kept for CI cross-check, more limited than binary) |
| 15 | `lua/moonlift/back_validate.lua` | Backend validation (has handlers for ALL ASDL variants including CmdRotate, CmdVecMask, CmdAtomic*) |

---

## Key Code: The Wire Format Contract

### WireTag enum (`src/wire_tags.rs`) — 111 tags, all 1:1 with Cranelift IR ops

All integer/float arithmetic, bitwise, shift/rotate, compare, cast/convert, intrinsics, address ops, memory (load/store/atomic/cmpxchg/fence/memcpy/memset/memcmp), pointer, vector (splat/lane/arith/cmp/select/mask/load/store), select, control flow, call (direct/extern/indirect), alias, boolnot. **Every tag has a handler in `decode_body()`.**

### BackCmd ASDL schema (`lua/moonlift/schema/back.asdl`) — 57 command variants

Declarations: `CmdCreateSig`, `CmdDeclareData`, `CmdDataInitZero`, `CmdDataInit`, `CmdDataAddr`, `CmdFuncAddr`, `CmdExternAddr`, `CmdDeclareFunc`, `CmdDeclareExtern`, `CmdBeginFunc`

Structural: `CmdCreateBlock`, `CmdSwitchToBlock`, `CmdSealBlock`, `CmdBindEntryParams`, `CmdAppendBlockParam`, `CmdCreateStackSlot`, `CmdAlias`, `CmdStackAddr`

Ops: `CmdConst`, `CmdUnary`, `CmdIntrinsic`, `CmdCompare`, `CmdCast`, `CmdPtrOffset`, `CmdIntBinary`, `CmdBitBinary`, `CmdBitNot`, `CmdShift`, `CmdRotate`, `CmdFloatBinary`, `CmdFma`, `CmdSelect`

Memory: `CmdLoadInfo`, `CmdStoreInfo`, **`CmdAtomicLoad`**, **`CmdAtomicStore`**, **`CmdAtomicRmw`**, **`CmdAtomicCas`**, **`CmdAtomicFence`**, `CmdMemcpy`, `CmdMemset`, `CmdMemcmp`

Vector: `CmdVecSplat`, `CmdVecBinary`, `CmdVecCompare`, `CmdVecSelect`, **`CmdVecMask`**, `CmdVecInsertLane`, `CmdVecExtractLane`

Control: `CmdJump`, `CmdBrIf`, `CmdSwitchInt`, `CmdReturnVoid`, `CmdReturnValue`, `CmdTrap`

Call: `CmdCall`

Termination: `CmdFinishFunc`, `CmdFinalizeModule`

---

## Gap Map: What REACHES the Rust Backend vs What Doesn't

### Gap A: ASDL BackCmd variants with NO binary encoder path (Lua can't produce them)

These variants exist in the ASDL schema and the Rust wire tags fully support them, but the Lua→binary encoder (`back_command_binary.lua`) has **no encoding dispatch**:

| BackCmd variant | Wire tag(s) | Rust codegen status | Binary encoder status |
|---|---|---|---|
| **`CmdAtomicLoad`** | `AtomicLoad` (112) | ✅ Full codegen in `decode_body` | ❌ Not encoded |
| **`CmdAtomicStore`** | `AtomicStore` (113) | ✅ Full codegen | ❌ Not encoded |
| **`CmdAtomicRmw`** | `AtomicRmw` (114) | ✅ Full codegen | ❌ Not encoded |
| **`CmdAtomicCas`** | `AtomicCas` (115) | ✅ Full codegen | ❌ Not encoded |
| **`CmdAtomicFence`** | `Fence` (116) | ✅ Full codegen | ❌ Not encoded |
| **`CmdRotate`** | `Rotl` (63), `Rotr` (64) | ✅ Full codegen | ❌ Not encoded |
| **`CmdVecMask`** | `VecMaskNot` (150), `VecMaskAnd` (151), `VecMaskOr` (152) | ✅ Full codegen | ❌ Not encoded |

**These 7 BackCmd variants are an immediate gap.** The Rust backend is ready; the Lua encoder needs `elseif k == "CmdAtomicLoad"` etc. branches.

### Gap B: Language features with NO lowering path at all

These LANGUAGE_REFERENCE.md features have **neither backend codegen nor lowering path** in the Lua compiler:

| Feature | Lang Ref § | Status |
|---|---|---|
| **Closure types** (`closure(i32): i32`) | §5.8 | No `code_to_back`/`lower_to_back` support. The ASDL has no `BackClosure` type. No wire tag. |
| **Handle types** (`handle Voice : u32 invalid 0 end`) | §21.2 | Memory convention only. No backend lowering, no BackCmd, no wire tag. |
| **Contracts/requires clauses** | §13 | Consumed by facts pipeline (optimization hints). No direct BackCmd emitted. |
| **Vector reductions** | §18.4 | `lower_to_back:631` explicitly errors: `"vector reductions are not implemented"` |
| **View return ABI** | §17 | `code_to_back:646` explicitly errors: `"view return ABI is not implemented below Code"` |
| **Indirect calls (interpreter)** | — | `debug_interpreter.lua:1111`: "Indirect call: not supported in interpreter" |
| **Route target in region compose** | — | `region_compose.lua:163`: "route target kind not yet lowerable in entry" |

### Gap C: Rust backend stub — tape compiler

`src/lib.rs:98-100`:
```rust
pub fn compile_tape(&self, _tape: &str) -> Result<Artifact, MoonliftError> {
    Err(MoonliftError("tape compiler not yet migrated; use binary wire format".into()))
}
```
The legacy text tape path is explicitly not migrated. The FFI surface (`src/ffi.rs`) doesn't even export a tape compilation function. The `moonlift` binary uses the binary path exclusively.

### Gap D: Hosted JIT disassembly stub

`hosted_jit.lua`:
```lua
function Jit:peek(_program, _func, _opts)
    error("hosted_jit: disassembly/peek is not wired for hosted artifacts yet", 2)
end
```

### Gap E: Backend fully supports (complete codegen path exists)

Every wire tag 1–191 (111 implemented tags) has a real Cranelift `InstBuilder` call in `decode_body()`. The complete list:

**Structural** (5): CreateBlock, SwitchToBlock, AppendBlockParam, CreateStackSlot, AppendBlockParamVec

**Constants** (7): ConstI32, ConstI64, ConstF32, ConstF64, ConstBool, ConstNull, ConstInt

**Integer arithmetic** (8): Iadd, Isub, Imul, Sdiv, Udiv, Srem, Urem, Ineg

**Float arithmetic** (12): Fadd, Fsub, Fmul, Fdiv, Fneg, Fabs, Fma, Sqrt, Floor, Ceil, Trunc, Nearest

**Bitwise** (4): Band, Bor, Bxor, Bnot

**Shift/Rotate** (5): Ishl, Ushr, Sshr, Rotl, Rotr

**Compare** (2): Icmp (10 conditions), Fcmp (6 conditions)

**Cast/Convert** (10): Bitcast, Ireduce, Sextend, Uextend, Fpromote, Fdemote, FcvtFromSint, FcvtFromUint, FcvtToSint, FcvtToUint

**Intrinsics** (5): Popcnt, Clz, Ctz, Bswap, Iabs

**Address** (4): StackAddr, GlobalValue, FuncAddr, ExternAddr

**Memory** (10): Load, Store, AtomicLoad, AtomicStore, AtomicRmw, AtomicCas, Fence, Memcpy, Memset, Memcmp

**Pointer** (2): PtrAdd, PtrOffset

**Vector** (25): Splat, InsertLane, ExtractLane, VecIadd, VecIsub, VecImul, VecBand, VecBor, VecBxor, VecIcmpEq/Ne, VecSIcmpLt/Le/Gt/Ge, VecUIcmpLt/Le/Gt/Ge, VecSelect, VecMaskNot/And/Or, VecLoad, VecStore

**Select** (1): Select

**Control** (6): Jump, Brif, SwitchInt, ReturnVoid, ReturnValue, Trap

**Call** (3): CallDirect, CallExtern, CallIndirect

**Singleton** (2): Alias, BoolNot

### Gap F: Encoding asymmetry — binary encoder has variants not in ASDL

The binary encoder handles `CmdDeclareFuncExport`, `CmdDeclareFuncExtern`, `CmdDeclareFuncLocal`, `CmdVecLoadInfo`, `CmdVecStoreInfo` — none of which exist in the ASDL schema. These appear to be the binary encoder parsing `CmdDeclareFunc.visibility` and `CmdLoadInfo`/`CmdStoreInfo` with vec types, splitting them at encode time. Not a bug, just a design detail.

---

## Relationships

### Data flow: Lua source → native code
```
.mlua source
  → parse (scan_document)
  → tree_typecheck
  → tree_to_code (MoonTree → MoonCode)
  → code_to_back / lower_to_back (MoonCode → BackCmd[])
  → back_command_binary.encode (BackCmd[] → binary wire bytes)
  → moonlift_jit_compile_binary (FFI → decode.rs → Cranelift JITModule)
  → native machine code
```

### Wire format contract
```
back.asdl (57 Cmd variants)
  → back_command_binary.lua (encodes 50 of 57)
  → binary wire bytes (header + decls + body table + tag streams)
  → src/decode.rs (decode_body: match on all 111 WireTags)
  → Cranelift FunctionBuilder IR instructions
```

### Critical gap flow
```
CmdAtomicLoad (ASDL defined)
  → ❌ back_command_binary.lua has NO `elseif k == "CmdAtomicLoad"` branch
  → ❌ cannot produce AtomicLoad (112) wire tag bytes
  → ✅ decode.rs already handles AtomicLoad tag with full codegen
  → Gap: Lua encoder needs 5 new branches (AtomicLoad, AtomicStore, AtomicRmw, AtomicCas, AtomicFence)
         + 1 branch for CmdRotate (Rotl/Rotr)
         + 1 branch for CmdVecMask (VecMaskNot/And/Or)
```

---

## Observations

1. **The Rust backend is surprisingly complete.** Every one of 111 wire tags dispatches to a real Cranelift `InstBuilder` call. The `_` catchall in `decode_body` returns `"unhandled wire tag {tag}"` — there are no silent no-ops.

2. **The gap is almost entirely in the Lua encoder, not in Rust.** 7 ASDL variants lack binary encoding. The Rust side is ready for all of them.

3. **Atomic operations are a pure encoder gap.** The wire tags (112–116) have full Cranelift codegen. The ASDL defines `CmdAtomicLoad`, `CmdAtomicStore`, `CmdAtomicRmw`, `CmdAtomicCas`, `CmdAtomicFence`. But the binary encoder has no branches for these. The same is true for `CmdRotate` (Rotl/Rotr) and `CmdVecMask`.

4. **Closure types, handle types, and contracts are not backend gaps** — they're design features that live in the Lua metaprogramming layer or facts pipeline, not in `BackCmd` at all. However, the language reference describes them as part of the language surface, which is worth noting.

5. **Vector reductions and view returns are explicitly error-stubbed** in the Lua lowering pipeline — these are known unimplemented features with loud failures.

6. **The tape path is dead.** `src/lib.rs` returns an error. The FFI doesn't export it. The `moonlift` binary never calls it. Only the legacy `back_jit.lua` (cdylib path) mentions `compile_tape` in its FFI declarations.

7. **The legacy tape encoder (`tape_encode.lua`) handles even fewer variants** than the binary encoder — no atomics, no vec operations, no Memcmp, no data/extern/func addr commands, no finalize/finish. It does handle `CmdRotate` though (which the binary encoder doesn't).

8. **Backend validation (`back_validate.lua`) already validates ALL ASDL variants** including CmdRotate, CmdVecMask, CmdAtomicLoad, etc. — so validation would catch issues if the encoder were extended.

9. **No `unimplemented!()` panics in Rust code.** The only stub is the `compile_tape` path which returns a clean error. No `todo!()`, no panics. The decoder's fallback arm returns an error for unrecognized tags.

10. **The `s[2]` vs `s[3]` slot count discrepancy in Splat.** The wire format doc says Splat has 3 slots `[dst, scalar_type, src]` but `wire_tags.rs` says 4 slots `[dst, scalar_type, lanes, src]`. The binary encoder writes 4 slots (dst, scalar_type, lanes, src). This inconsistency between doc and code should be reconciled.

## Knowledge-builder Output — 2026-06-17 19:55:56

Now I have the full picture. Here are my second-order observations.

---

## What Matters Most for This Problem

Given the "backend completeness audit" task:
1. **Correctness of the gap classification** — the gap isn't a single category; it's three fundamentally different kinds of missingness
2. **Coupling between Lua encoder and Rust decoder** — they are independent implementations of the same wire contract, maintained separately
3. **What tests actually exercise** — test coverage is misleading because BackCmd presence ≠ end-to-end execution
4. **Wire format fidelity** — what the wire format drops from the ASDL schema (atomic ordering, scale type info)

---

## Non-Obvious Observations

### 1. The encoder gap is NOT symmetric across the two JIT paths — but it is
Both `back_jit.lua` (CDylib) and `hosted_jit.lua` (standalone binary) call `back_command_binary.encode()`. **There is no alternative path.** Every BackProgram, regardless of how it enters Rust, transits the same encoder. This means the atomic/Rotate/VecMask gap blocks BOTH entry points equally. The distinction between "cdylib" and "hosted" is an FFI detail, not a separate compilation pipeline.

### 2. `test_atomics.lua` is a *coverage mirage*
The test asserts that `CmdAtomicLoad` etc. are produced by lowering (lines 33-38), then calls `jit():compile(program)` and asserts specific numeric results (line 44: `atomic_demo(cell) == 46`, line 45: `cell[0] == 21`). But the encoder silently drops atomic commands. The compiled function would have no atomic instructions — `old`, `seen`, `after` would reference **undefined Cranelift SSA values**, causing a compilation error in `decode.rs` (`ctx.val()` returns `"unknown value {id}"`). The test **cannot pass** the end-to-end execution check. This pattern — verifying BackCmd production but not execution — is a classic "test your abstractions, not your pipeline" trap. The test structure is correct (check BackCmds first, then execute) but the encoder gap makes the second half dead code that never runs successfully.

### 3. Atomic ordering is a **semantic gap at the wire boundary**, not just an encoding gap
The ASDL schema defines `BackAtomicOrdering` on every atomic command:
```
CmdAtomicLoad(dst, ty, addr, memory, ordering)
CmdAtomicStore(ty, addr, value, memory, ordering)
...
CmdAtomicFence(ordering)
```

But the wire format has **zero slots for ordering**: `AtomicLoad` has 4 slots `[dst, scalar_type, memflags, addr]`, `Fence` has 0 slots. The Rust decoder hardcodes all atomics via Cranelift's `atomic_load`/`atomic_store` instructions (which are implicitly seq_cst on x86 but NOT portable to other architectures). Cranelift does support relaxed/acquire/release memory orderings via `MemFlags` bits, but the current wire format doesn't expose them.

This means: even after adding encoder branches, the ordering field in the ASDL would be **silently lost** at the wire boundary. Fixing this properly requires extending the wire format to carry ordering bits (or accepting that only seq_cst is supported).

### 4. CmdVecMask has a non-uniform arity problem at the encoder level
The ASDL groups `VecMaskNot`, `VecMaskAnd`, `VecMaskOr` into a single `CmdVecMask(dst, op, ty, args*)` with variadic args. But the wire format has three separate tags with different slot counts:
- `VecMaskNot`: 2 slots (unary)
- `VecMaskAnd`: 3 slots (binary)
- `VecMaskOr`: 3 slots (binary)

The encoder must dispatch on `cmd.op.kind` to select the right tag AND emit `args[1]` only vs `args[1], args[2]`. This is more complex than adding a 1:1 branch — it requires a sub-dispatch inside the `CmdVecMask` branch. The pattern already exists in the encoder (e.g., `CmdUnary` dispatches on op to select `Ineg`/`Fneg`/`Bnot`/`BoolNot`), but CmdVecMask is the only case where the op determines arity.

### 5. CmdAtomicRmw needs an `op_kind` numeric mapping that must stay synchronized
The wire format uses slot `s[2]` as `op_kind` in `AtomicRmw`. The Rust decoder maps:
```
1→Add, 2→Sub, 3→And, 4→Or, 5→Xor, 6→Xchg
```
The ASDL defines `BackAtomicRmwOp` with the same 6 variants. The Lua encoder must produce the SAME numeric mapping. There is no shared constant definition between Lua and Rust — the mapping must be maintained independently in both files. This is a hidden coupling point that the existing encoder (for Load/Store) avoids because atomic loads/stores don't need an op_kind.

### 6. The "silent drop" pattern in the encoder is the root cause of the test mirage
The encoder's `if-then-elseif` chain ends without an `else` clause:
```lua
for _, cmd in ipairs(cmds) do
    local k = cmd.kind
    if k == "CmdCreateBlock" then ...
    elseif k == "CmdSwitchToBlock" then ...
    ...
    -- NO else clause
    end
end
```
Unrecognized commands are silently skipped. This means:
- The encoder produces a shorter-but-valid wire buffer
- Rust decodes it without errors (no "unhandled wire tag")
- Cranelift compiles a function that's missing instructions
- Values that should be defined by dropped commands become undefined
- The decoder fails at `ctx.val()` with `"unknown value {id}"` when a later instruction references them

If the encoder had a loud `else error("unrecognized BackCmd: " .. k)` clause, the gap would be immediately visible. Instead, it fails silently until a downstream instruction references an undefined value.

### 7. CmdRotate is the deepest gap because it requires new language surface, not just encoder wiring
Looking at `debug_interpreter.lua:568-576`, rotate is implemented as a **shift** ("Simplified: just shift for now"). The language reference mentions rotate syntax (e.g., `rotl(x, n)`), but:
- There's no lowering path from `.mlua` source to `CmdRotate` BackCmds (grep confirms no `CodeInstRotate` or lowering logic in `code_to_back.lua`)
- The rotate command only appears in hand-constructed BackPrograms (tests that build ASDL directly)
- No language-level test exercises rotate through the full pipeline

The encoder gap for CmdRotate is real but different from atomics: **atomics have a complete lowering path but no encoder; rotate has neither lowering NOR encoder.**

### 8. The `Splat` slot count discrepancy is a documentation bug that masks a deeper contract trust issue
`BACK_WIRE_FORMAT.md` says Splat has 3 slots. `wire_tags.rs` says 4. The encoder writes 4. The decoder reads 4. The documentation is wrong, not the code. But this reveals a pattern: **the wire format doc was written first, then the implementation diverged** (adding a `lanes` slot). This means the doc cannot be trusted as the contract specification. The `TAG_SLOTS` array in `wire_tags.rs` is the actual contract.

### 9. There are actually THREE distinct "gap layers" not two
The scout classified gaps as "encoder gap" vs "lowering gap." But there are really three:

| Layer | What's missing | Examples |
|-------|---------------|---------|
| **Lowering** | Lua compiler can't produce BackCmds | Closures, vector reductions, view returns, rotate |
| **Encoding** | BackCmds exist but can't reach Rust | Atomics, VecMask, (rotate if lowering existed) |
| **Wire format fidelity** | Wire format discards ASDL fields | Atomic ordering (BackAtomicOrdering) |

The third layer is subtle: even if lowering and encoding work, the wire format might not carry all the semantic information present in the ASDL. Atomic ordering is the clearest example — it exists in the schema, but the wire format has no slot for it.

### 10. The gap pattern suggests a specific development trajectory
The evidence suggests:
1. **Wire format was designed first** — all 111 tags, all slot layouts
2. **Rust backend was implemented** — all 111 tags get real Cranelift calls
3. **Lua lowering was implemented incrementally** — only what was needed for immediate features
4. **Encoder was implemented incrementally** — only what lowering produced
5. **At some point, atomics were added to the ASDL and the lowering** (possibly for C backend support first, since `test_atomics.lua` exercises BackCmd production but the binary encoder was never updated)

The ASDL schema, validation, C backend, and lowering all have atomics. The Rust backend has atomics. The ONLY gap is **the binary encoder**. This is the hallmark of a feature that was added to the "compiler model" (ASDL + validation + C output) but the Cranelift binary path was never plumbed through.

### 11. The debug interpreter's handling reveals design intent
The debug interpreter maps:
- `CmdAtomicLoad` → `"_handle_load_info"` — treats atomics as regular loads
- `CmdAtomicStore` → `"_handle_store_info"` — treats atomics as regular stores
- `CmdAtomicRmw`/`CmdAtomicCas`/`CmdAtomicFence` → `"_handle_noop"` — ignores them
- `CmdVecMask` → `"_handle_noop"` — ignores it
- `CmdRotate` → `"_handle_rotate"` — implements as shift, with a comment "Simplified: just shift for now"

This reveals intentional design: the interpreter is a "best effort" debugging tool, not a semantics-preserving executor. The mapping of atomics to regular loads/stores for Load/Store variants but no-ops for Rmw/Cas/Fence is the interpreter saying "we know these exist, we know what they mean, but we're not implementing the full semantics here." The Rust backend is the authoritative executor.

---

## Knowledge Gaps

I don't believe I need to spawn additional scouts — I have sufficient data to produce the observations above. However, one thing worth noting for the proposer:

- **Does Cranelift's `MemFlags` API actually expose memory ordering?** If so, extending the wire format to carry ordering would be straightforward. If not, the Rust backend may be limited to implicit seq_cst atomics, which would make the ASDL's `BackAtomicOrdering` informational-only (not executable). This affects whether fixing the atomic encoder gap is "add 5 branches" or "add 5 branches + redesign wire format slots."

## Scout Output — 2026-06-17 20:02:20

Now I have all the critical data. Here is the comprehensive scout report.

---

## Files Retrieved

| # | File | Range | Purpose |
|---|------|-------|---------|
| 1 | `lua/moonlift/back_command_binary.lua` | Full (all ~415 lines) | Binary encoder — complete if-elseif chain, helpers, body layout |
| 2 | `src/wire_tags.rs` | Full | TAG_SLOTS static array — definitive slot counts for all 191 tags |
| 3 | `src/decode.rs` | Full | Complete Cranelift backend decoder — all tag handlers, memflags/rmw helpers |
| 4 | `lua/moonlift/schema/back.asdl` | Full | Complete ASDL schema — all Cmd* variants, BackAtomicOrdering, BackAtomicRmwOp |
| 5 | `BACK_WIRE_FORMAT.md` | Full | Wire format specification — tag table, slot layouts, MemFlags encoding |
| 6 | `tests/test_atomics.lua` | Full (47 lines) | Atomic test — asserts BackCmd presence + JIT execution |
| 7 | `tests/test_dasm_multi_compile.lua` | Full (93 lines) | Rotate stress test via dasm backend (has CmdRotate) |
| 8 | `tests/test_back_cast_intrinsic_switch.lua` | Lines 70-95 | Rotate test via dasm backend |
| 9 | `lua/moonlift/lower_to_back.lua` | Lines 298-340 | Memory lowering helpers — is_write_access, is_read_access, memory_info_for |
| 10 | `lua/moonlift/lower_to_back.lua` | Lines 400-440 | Kernel load/store emission — uses CmdLoadInfo/CmdStoreInfo, NEVER CmdAtomic* |

---

## Key Findings

### 1. Encoder if-elseif chain structure

The encoder's `encode_body()` function (line ~146-335 of `back_command_binary.lua`) has `for _, cmd in ipairs(cmds) do` with a single `if k == "CmdCreateBlock" then ... elseif ... end` chain — **NO else clause**. Unrecognized commands are silently dropped. The chain ends implicitly (the `end` on the `for` loop).

The last recognized branch is `CmdCall` (around line ~330). After that, the `end` at line ~335 closes the `if`/`for`.

### 2. Load/Store encoding pattern (lines ~240-270) — exact template for atomics

```lua
-- CmdLoadInfo (lines ~240-256)
elseif k == "CmdLoadInfo" then
    local is_vec = cmd.ty.kind ~= "BackShapeScalar"
    local elem_st, lanes, mem
    if is_vec then
        elem_st = st(cmd.ty.vec.elem)
        lanes = cmd.ty.vec.lanes
        mem = memflags(cmd.memory)
    else
        elem_st = st(cmd.ty.scalar)
        lanes = 0
        mem = memflags(cmd.memory)
    end
    local addr_id = emit_effective_addr(buf, cmd.addr)
    if is_vec then
        w4(buf, T.VecLoad); w4(buf, b:nid(cmd.dst))
        w4(buf, elem_st); w4(buf, lanes); w4(buf, mem); w4(buf, b:nid(addr_id))
    else
        w4(buf, T.Load); w4(buf, b:nid(cmd.dst))
        w4(buf, elem_st); w4(buf, mem); w4(buf, b:nid(addr_id))
    end
```

Key observations:
- **`emit_effective_addr()`** (defined on line ~138) resolves an address object into a value ID, emitting StackAddr/GlobalValue/PtrAdd as needed inline
- **`memflags(cmd.memory)`** (line ~97-112) encodes memory bits: bit0=notrap, bit1=aligned, bit2=can_move, bit3=readonly
- **Scalar types**: `cmd.ty.scalar` (not `cmd.ty` — for CmdLoadInfo, `cmd.ty` is a BackShape)
- Atomics only need scalar types (atomic operations aren't vectorized), so the shape is always `BackShapeScalar(cmd.ty)` where `cmd.ty` is a BackScalar

### 3. Atomic BackCmd ASDL definitions vs wire contract

**ASDL** (back.asdl lines 260-264):
```
CmdAtomicLoad(dst, ty:BackScalar, addr:BackAddress, memory:BackMemoryInfo, ordering:BackAtomicOrdering)
CmdAtomicStore(ty:BackScalar, addr:BackAddress, value, memory:BackMemoryInfo, ordering:BackAtomicOrdering)
CmdAtomicRmw(dst, op:BackAtomicRmwOp, ty:BackScalar, addr:BackAddress, value, memory:BackMemoryInfo, ordering:BackAtomicOrdering)
CmdAtomicCas(dst, ty:BackScalar, addr:BackAddress, expected, replacement, memory:BackMemoryInfo, ordering:BackAtomicOrdering)
CmdAtomicFence(ordering:BackAtomicOrdering)
```

**Wire format** (TAG_SLOTS array in `wire_tags.rs`):
- `AtomicLoad` (112) = 4 slots: `[dst, scalar_type, memflags, addr]`
- `AtomicStore` (113) = 4 slots: `[scalar_type, memflags, addr, value]`
- `AtomicRmw` (114) = 6 slots: `[dst, scalar_type, op_kind, memflags, addr, value]`
- `AtomicCas` (115) = 6 slots: `[dst, scalar_type, memflags, addr, expected, replacement]`
- `Fence` (116) = 0 slots

**CRITICAL GAP**: The `ordering` field in the ASDL has **no wire slot**. Only `BackAtomicOrdering = BackAtomicSeqCst` exists (single variant). The Rust decoder ignores ordering entirely — it uses Cranelift's default `atomic_load`/`atomic_store`/`atomic_rmw`/`atomic_cas`/`fence()` instructions with `MemFlags`.

### 4. AtomicRmw op_kind numeric mapping (must be kept synchronized)

**Rust decoder** (`decode.rs` lines ~95-102):
```rust
fn rmw(kind: u32) -> Result<AtomicRmwOp, MoonliftError> {
    match kind {
        1 => Ok(AtomicRmwOp::Add), 2 => Ok(AtomicRmwOp::Sub),
        3 => Ok(AtomicRmwOp::And), 4 => Ok(AtomicRmwOp::Or),
        5 => Ok(AtomicRmwOp::Xor), 6 => Ok(AtomicRmwOp::Xchg),
        _ => ...
    }
}
```

**ASDL enum order** (back.asdl lines 97-102):
```
BackAtomicRmwAdd | BackAtomicRmwSub | BackAtomicRmwAnd | BackAtomicRmwOr | BackAtomicRmwXor | BackAtomicRmwXchg
```

The encoder must map these enum variants to 1-6 in the same order.

### 5. Rotate wire tags and handlers

- `Rotl` (63) = 3 slots: `[dst, lhs, rhs]` — `binop!(0, 1, 2, rotl)`
- `Rotr` (64) = 3 slots: `[dst, lhs, rhs]` — `binop!(0, 1, 2, rotr)`

ASDL `CmdRotate(dst, op:BackRotateOp, scalar:BackScalar, lhs, rhs)`:
- `BackRotateOp = BackRotateLeft | BackRotateRight`
- Pattern identical to `CmdShift` (lines ~210-218): `local ok = cmd.op.kind or cmd.op; if ok == "BackRotateLeft" then w4(buf, T.Rotl) elseif ok == "BackRotateRight" then w4(buf, T.Rotr) else w4(buf, T.Rotl) end`

### 6. VecMask wire tags and handlers

- `VecMaskNot` (150) = 2 slots: `[dst, vec]` — `unop!(0, 1, bnot)`
- `VecMaskAnd` (151) = 3 slots: `[dst, lhs, rhs]` — `binop!(0, 1, 2, band)`
- `VecMaskOr` (152) = 3 slots: `[dst, lhs, rhs]` — `binop!(0, 1, 2, bor)`

ASDL `CmdVecMask(dst, op:BackVecMaskOp, ty:BackVec, args:BackValId*)`:
- `BackVecMaskOp = BackVecMaskNot | BackVecMaskAnd | BackVecMaskOr`
- Sub-dispatch needed: `VecMaskNot` uses `args[1]` only; `VecMaskAnd`/`VecMaskOr` use `args[1], args[2]`

### 7. MemFlags helper (lines 97-112)

```lua
local function memflags(m)
    local bits = 0
    if m.trap.kind == "BackNonTrapping" or m.trap.kind == "BackChecked" then
        bits = bit.bor(bits, 1)
    end
    if (m.alignment.kind == "BackAlignKnown" or m.alignment.kind == "BackAlignAtLeast")
       and m.alignment.bytes >= 4 then
        bits = bit.bor(bits, 2)
    end
    if m.motion.kind == "BackCanMove" then
        bits = bit.bor(bits, 4)
    end
    if m.mode.kind == "BackAccessReadonly" then
        bits = bit.bor(bits, 8)
    end
    return bits
end
```

### 8. emit_effective_addr helper (lines ~128-145)

```lua
local function emit_effective_addr(buf, addr)
    local base_id = emit_base_addr(buf, addr.base)
    if addr.byte_offset == nil then return base_id end
    local at = fresh_id()
    w4(buf, T.PtrAdd); w4(buf, b:nid(at)); w4(buf, b:nid(base_id)); w4(buf, b:nid(addr.byte_offset))
    return at
end
```

### 9. CRITICAL DISCOVERY: Atomics are NEVER lowered to CmdAtomic*

`grep -rn "CmdAtomicLoad\|CmdAtomicStore\|CmdAtomicRmw\|CmdAtomicCas\|CmdAtomicFence" lua/ --include="*.lua"` returns **ZERO construction sites** in the Lua compiler source. The only references are:
- `schema/back.asdl` — ASDL definition
- `back_validate.lua` — validation handler (references by class, doesn't construct)
- `debug_interpreter.lua` — handler dispatch

**`lower_to_back.lua`** (lines 400-440) emits `CmdLoadInfo`/`CmdStoreInfo` for ALL memory operations including atomic ones — there is no `CmdAtomicLoad`/`CmdAtomicStore` emission path.

**`code_to_back.lua`** has no `CodeInstAtomicLoad`/`CodeInstAtomicStore`/etc. elseif branches — atomic CodeInsts silently fall through the if-elseif chain.

This means: **the `test_atomics.lua` test CANNOT pass**. When it runs, `program.cmds` will contain `CmdLoadInfo`/`CmdStoreInfo` (emitted by `lower_to_back`), NOT `CmdAtomicLoad`/`CmdAtomicStore`. The assertion on line 39 (`saw_load and saw_store and saw_rmw and saw_cas and saw_fence`) must be false.

The test is indeed a coverage mirage as the knowledge-builder identified.

### 10. Rotate existing lowering: CmdRotate only in hand-constructed programs

CmdRotate is NOT lowered from .mlua source through the pipeline. It only appears in:
- `test_back_cast_intrinsic_switch.lua` line 83 (hand-constructed via ASDL builders)
- `test_dasm_backend_full.lua` line 438 (hand-constructed)
- `test_dasm_multi_compile.lua` line 71 (hand-constructed)

The `code_to_back.lua` has no `CodeInstRotate` handler. The lowering path from `rotate` source syntax to BackCmd does not exist.

### 11. VecMask: also only in hand-constructed dasm tests

CmdVecMask only appears in dasm backend files (`back/dasm/`), never in the binary encoder path. The `lower_to_back.lua` vector kernel emitter uses `CmdVecBinary`/`CmdVecCompare`/`CmdVecSplat`/`CmdVecSelect` but never `CmdVecMask`. The dasm backend explicitly errors: `"isel: vector CmdVecMask not supported"` (rule_x64.lisle line 208).

---

## Exact Encoder Insertion Points

The if-elseif chain in `back_command_binary.lua` has these natural insertion points:

1. **After CmdStoreInfo** (line ~270): Insert `CmdAtomicLoad` branch (before `CmdMemcpy`/`CmdMemset`/`CmdMemcmp`)
2. **After CmdStoreInfo** (same place): Insert `CmdAtomicStore` branch
3. **After CmdAtomicLoad/CmdAtomicStore**: Insert `CmdAtomicRmw` branch
4. **After CmdAtomicRmw**: Insert `CmdAtomicCas` branch
5. **After CmdAtomicCas**: Insert `CmdAtomicFence` branch
6. **After CmdShift** (line ~218): Insert `CmdRotate` branch
7. **After CmdVecSelect** (line ~312): Insert `CmdVecMask` branch

The pattern for each follows the same `w4(buf, T.Tag); w4(buf, b:nid(cmd.field)); ...` style used throughout.

---

## Test Files

| File | What it tests | Status |
|------|---------------|--------|
| `tests/test_atomics.lua` | Full .mlua atomic pipeline → BackCmd check + JIT | **Cannot pass** — no atomic BackCmd construction path |
| `tests/test_back_cast_intrinsic_switch.lua` | Dasm backend with hand-constructed CmdRotate | Uses dasm, not binary wire |
| `tests/test_dasm_multi_compile.lua` | Random compilation stress test with CmdRotate | Uses dasm (`back.dasm`) |
| `tests/test_dasm_backend_full.lua` | Full dasm feature test with CmdRotate | Uses dasm |

## Edit-planner Output — 2026-06-17 20:04:04

Good. Now here is the complete file-by-file, line-level implementation plan:

---

# Edit Plan: Close Backend Encoder Gaps — `wf-backend-gap/encoder`

## Precondition Checks

Before any edits begin, a worker should verify:

1. **Confirm `back_command_binary.lua` is at ~415 lines** and the if-elseif chain structure is as documented below. The last recognized branch is `CmdCall`; there is no `else` clause.
2. **Confirm `decode.rs` op_kind mapping** at lines 81–83: `1=Add, 2=Sub, 3=And, 4=Or, 5=Xor, 6=Xchg`. This must stay synchronized with the encoder.
3. **Confirm `st()` helper handles `BackScalar` directly**: `st(s)` matches `s.kind == "BackShapeScalar"` → `s.scalar.kind`, otherwise directly `S[s.kind]`. For atomic commands where `cmd.ty` is a `BackScalar` (not BackShape), `st(cmd.ty)` resolves via the fallback `S[cmd.ty.kind]`. Verify this by tracing the `st()` function at lines 82–89.
4. **Confirm tape encoder is deleted**: grep for `tape_encode.lua` — it should no longer exist. Only binary format remains.
5. **Confirm `test_atomics.lua` exists** at `tests/test_atomics.lua` (47 lines) — this test documents the state of atomic lowering (produces `CmdLoadInfo` not `CmdAtomicLoad`).

---

## Files to Modify

### `lua/moonlift/back_command_binary.lua`

**Goal**: Add 7 missing encoder branches (atomics, rotate, vecmask) plus a loud `else error(...)` clause so future gaps fail immediately instead of silently dropping commands.

This is the **only file modified**. All changes are in the `encode_body()` function's if-elseif chain inside the `for _, cmd in ipairs(cmds) do` loop.

#### Edit Block 1: CmdAtomicLoad — after CmdStoreInfo (insert before `-- Unary`)

**Location**: After the `end` that closes CmdStoreInfo's `if is_vec ... else ... end` block, and before the `-- Unary` comment line. Currently, the CmdStoreInfo branch ends and the next line is `-- Unary` followed by `elseif k == "CmdUnary" then`.

**Add**:

```lua
        -- Atomic memory
        elseif k == "CmdAtomicLoad" then
            local addr_id = emit_effective_addr(buf, cmd.addr)
            w4(buf, T.AtomicLoad); w4(buf, b:nid(cmd.dst))
            w4(buf, st(cmd.ty)); w4(buf, memflags(cmd.memory))
            w4(buf, b:nid(addr_id))
```

**Quirks/notes**:
- `cmd.ty` is `BackScalar` (not `BackShape`), so `st(cmd.ty)` dispatches via the `else` branch of `st()`: `S[cmd.ty.kind]`. This works because `BackScalar` kinds like `BackI32`, `BackF64` etc. are in the `S` table.
- `cmd.ordering` (BackAtomicOrdering) is silently dropped — the wire format has no slot for it. Rust hardcodes seq_cst.
- Uses `emit_effective_addr` exactly like CmdLoadInfo — this emits StackAddr/GlobalValue/PtrAdd preamble as needed.

#### Edit Block 2: CmdAtomicStore — immediately after CmdAtomicLoad

**Add**:

```lua
        elseif k == "CmdAtomicStore" then
            local addr_id = emit_effective_addr(buf, cmd.addr)
            w4(buf, T.AtomicStore); w4(buf, st(cmd.ty))
            w4(buf, memflags(cmd.memory)); w4(buf, b:nid(addr_id))
            w4(buf, b:nid(cmd.value))
```

**Quirks/notes**:
- No `cmd.dst` — store produces no value. The wire tag `AtomicStore` has slots `[scalar_type, memflags, addr, value]`.
- Same `st(cmd.ty)` pattern as CmdAtomicLoad.

#### Edit Block 3: CmdAtomicRmw — immediately after CmdAtomicStore

**Add**:

```lua
        elseif k == "CmdAtomicRmw" then
            local ok = cmd.op.kind or cmd.op
            local opk = 1
            if ok == "BackAtomicRmwAdd" then opk = 1
            elseif ok == "BackAtomicRmwSub" then opk = 2
            elseif ok == "BackAtomicRmwAnd" then opk = 3
            elseif ok == "BackAtomicRmwOr" then opk = 4
            elseif ok == "BackAtomicRmwXor" then opk = 5
            elseif ok == "BackAtomicRmwXchg" then opk = 6 end
            local addr_id = emit_effective_addr(buf, cmd.addr)
            w4(buf, T.AtomicRmw); w4(buf, b:nid(cmd.dst))
            w4(buf, st(cmd.ty)); w4(buf, opk); w4(buf, memflags(cmd.memory))
            w4(buf, b:nid(addr_id)); w4(buf, b:nid(cmd.value))
```

**Quirks/notes**:
- **CRITICAL**: The `opk` mapping MUST stay synchronized with `src/decode.rs` lines 81–83. The order is: Add=1, Sub=2, And=3, Or=4, Xor=5, Xchg=6.
- The ASDL enum order in `back.asdl` lines 109–114 is: `BackAtomicRmwAdd | BackAtomicRmwSub | BackAtomicRmwAnd | BackAtomicRmwOr | BackAtomicRmwXor | BackAtomicRmwXchg` — same order as the numeric mapping.
- Wire has 6 slots: `[dst, scalar_type, op_kind, memflags, addr, value]`. The `opk` goes in slot position 2 (third slot).
- Default `opk = 1` (Add) if unrecognized op — matches existing pattern (e.g., CmdShift falls back to `T.Ishl`).

#### Edit Block 4: CmdAtomicCas — immediately after CmdAtomicRmw

**Add**:

```lua
        elseif k == "CmdAtomicCas" then
            local addr_id = emit_effective_addr(buf, cmd.addr)
            w4(buf, T.AtomicCas); w4(buf, b:nid(cmd.dst))
            w4(buf, st(cmd.ty)); w4(buf, memflags(cmd.memory))
            w4(buf, b:nid(addr_id))
            w4(buf, b:nid(cmd.expected)); w4(buf, b:nid(cmd.replacement))
```

**Quirks/notes**:
- Wire has 6 slots: `[dst, scalar_type, memflags, addr, expected, replacement]`.
- No op_kind needed — CAS has a fixed operation. Fields `cmd.expected` and `cmd.replacement` map to the last two slots.

#### Edit Block 5: CmdAtomicFence — immediately after CmdAtomicCas

**Add**:

```lua
        elseif k == "CmdAtomicFence" then
            w4(buf, T.Fence)
```

**Quirks/notes**:
- Wire has 0 data slots. Pure tag emission, like `T.ReturnVoid` and `T.Trap`.
- `cmd.ordering` is silently dropped (no wire slot).
- Rust decoder at line 500: `ctx.builder.ins().fence()` — no arguments.

#### Edit Block 6: CmdRotate — after CmdShift (insert before `-- Compare`)

**Location**: After the final `w4(buf, b:nid(cmd.rhs))` of the CmdShift branch, and before the `-- Compare` comment line.

**Add**:

```lua
        -- Rotate
        elseif k == "CmdRotate" then
            local ok = cmd.op.kind or cmd.op
            if ok == "BackRotateLeft" then w4(buf, T.Rotl)
            elseif ok == "BackRotateRight" then w4(buf, T.Rotr)
            else w4(buf, T.Rotl) end
            w4(buf, b:nid(cmd.dst)); w4(buf, b:nid(cmd.lhs)); w4(buf, b:nid(cmd.rhs))
```

**Quirks/notes**:
- Follows the CmdShift pattern EXACTLY: sub-dispatch tag write, then shared slot writes.
- Both Rotl and Rotr have 3 slots (same arity as shift).
- Fields: `cmd.dst`, `cmd.op` (BackRotateOp), `cmd.scalar` (not used in wire — scalar type is implicit), `cmd.lhs`, `cmd.rhs`.
- Note: there is no lowering path from .mlua to CmdRotate yet. This branch prevents silent drop when lowering is eventually added.

#### Edit Block 7: CmdVecMask — after CmdVecSelect (insert before `-- Vector load`)

**Location**: After the last `w4` of CmdVecSelect, before `-- Vector load`.

**Add**:

```lua
        -- Vector mask
        elseif k == "CmdVecMask" then
            local ok = cmd.op.kind or cmd.op
            if ok == "BackVecMaskNot" then
                w4(buf, T.VecMaskNot); w4(buf, b:nid(cmd.dst)); w4(buf, b:nid(cmd.args[1]))
            elseif ok == "BackVecMaskAnd" then
                w4(buf, T.VecMaskAnd); w4(buf, b:nid(cmd.dst))
                w4(buf, b:nid(cmd.args[1])); w4(buf, b:nid(cmd.args[2]))
            elseif ok == "BackVecMaskOr" then
                w4(buf, T.VecMaskOr); w4(buf, b:nid(cmd.dst))
                w4(buf, b:nid(cmd.args[1])); w4(buf, b:nid(cmd.args[2]))
            else
                w4(buf, T.VecMaskNot); w4(buf, b:nid(cmd.dst)); w4(buf, b:nid(cmd.args[1]))
            end
```

**Quirks/notes**:
- **Non-uniform arity**: VecMaskNot has 2 data slots `[dst, vec]`; VecMaskAnd/Or have 3 `[dst, lhs, rhs]`. Each sub-branch writes its own tag + slot sequence.
- `cmd.args` is a Lua array (variadic in ASDL).
- Fallback: `VecMaskNot` with `args[1]` only. This is the safe default — the not operation is unary and won't reference undefined args.
- The `cmd.ty` (BackVec) field is not emitted — it's not in the wire format slots. The Rust decoder doesn't use it for vec mask ops (they operate on mask registers, type is implicit).

#### Edit Block 8: Else clause — at end of if-elseif chain

**Location**: The if-elseif chain currently ends with the CmdCall branch at `end` (closing the `if`). Before that `end`, add an `else` clause.

**Current end of chain** (approximately lines 330–335):
```lua
        -- Call
        elseif k == "CmdCall" then
            ...
            emit_ids(buf, cmd.args, b)
        end
    end
```

**Replace with**:
```lua
        -- Call
        elseif k == "CmdCall" then
            ...
            emit_ids(buf, cmd.args, b)
        else
            error("unrecognized BackCmd: " .. tostring(k))
        end
    end
```

**Quirks/notes**:
- `tostring(k)` handles the case where `k` is nil (e.g., a malformed command).
- This is a **loud failure** — any future BackCmd variant added to the ASDL but not the encoder will immediately error instead of silently dropping.
- The error propagates through `encode_body()` → `M.encode()` → the JIT pipeline, producing a clear Lua-level error message.

---

### New Files

None. All changes are in `lua/moonlift/back_command_binary.lua` only.

---

## Order of Operations

1. **First: Add all atomic branches** (Edit Blocks 1–5, CmdAtomicLoad through CmdAtomicFence). These are adjacent — insert them as a contiguous block after CmdStoreInfo, before `-- Unary`. The order within the block must be: Load, Store, Rmw, Cas, Fence. Do them in one edit to minimize disruption.

2. **Second: Add CmdRotate branch** (Edit Block 6). Insert after CmdShift, before `-- Compare`. Independent of the atomic block — can be tested separately.

3. **Third: Add CmdVecMask branch** (Edit Block 7). Insert after CmdVecSelect, before `-- Vector load`. Independent of prior blocks.

4. **Fourth: Add the else clause** (Edit Block 8). This is the safety net — do it last so that during development, if a partial edit leaves the chain in an inconsistent state, the else clause catches it. But once all branches are in place, add the else clause so the chain is complete.

5. **Fifth: Run existing tests** to confirm no regressions in the binary encoder path.

---

## Testing Strategy

### Incremental verification

After each block of branches (atomics, rotate, vecmask), there is **no way to test through the normal lowering pipeline** because the Lua compiler doesn't produce these BackCmd variants (yet). Verification must use hand-constructed BackPrograms:

```lua
-- Pattern for hand-constructed test (follow test_dasm_multi_compile.lua style)
local T = pvm.context()
A.Define(T)
local B = T.MoonBack

-- Construct a program with the new BackCmd
local program = B.BackProgram({
    B.CmdDeclareFunc(B.BackFuncId("test"), ..., B.VisibilityExport),
    B.CmdBeginFunc(B.BackFuncId("test")),
    B.CmdCreateBlock(B.BackBlockId("entry")),
    ...
    B.CmdAtomicLoad(B.BackValId("v"), B.BackI32, ...),  -- new cmd
    ...
    B.CmdReturnValue(B.BackValId("v")),
    B.CmdFinishFunc(B.BackFuncId("test")),
    B.CmdFinalizeModule()
})

-- Verify: encode → JIT compile → call
local jit = require("moonlift.back_jit").Define(T).jit()
local artifact = jit:compile(program)
-- Should not error
artifact:free()
```

### Regression tests

After all edits, run:
```sh
luajit tests/test_back_add_i32.lua        # basic binary encoder path
luajit tests/test_back_object_emit.lua     # object emission path
luajit tests/test_mlua_host_pipeline.lua   # hosted pipeline
luajit tests/test_dasm_multi_compile.lua   # dasm path (unchanged, baseline)
luajit tests/test_back_cast_intrinsic_switch.lua  # dasm path with CmdRotate
```

These should all pass without changes — we're only adding branches, not modifying existing ones.

### test_atomics.lua status

`tests/test_atomics.lua` currently:
1. Checks for `CmdAtomicLoad` etc. in lowered `program.cmds` (lines 33-38)
2. Attempts JIT execution (lines 40-44)

The lowering pipeline emits `CmdLoadInfo`/`CmdStoreInfo` instead of `CmdAtomicLoad`/`CmdAtomicStore`. So:
- The BackCmd assertions at line 38 will **fail** (saw_load etc. are all false)
- Even if they passed, the encoder would now correctly encode atomic commands

**Do not modify the test's lowering expectation** — the encoder plan only adds encoding branches. The lowering gap is separate work. If the test fails on BackCmd checks, add a comment noting the encoder now supports atomics but lowering doesn't emit them yet.

---

## Structured Edit Plan Sidecar

Created sidecar `encoder` in `wf-backend-gap` with 10 tasks:

| Id | Task | File | Dependencies |
|----|------|------|-------------|
| T001 | Add CmdAtomicLoad encoder branch | `back_command_binary.lua` | — |
| T002 | Add CmdAtomicStore encoder branch | `back_command_binary.lua` | T001 |
| T003 | Add CmdAtomicRmw encoder branch with op_kind mapping | `back_command_binary.lua` | T002 |
| T004 | Add CmdAtomicCas encoder branch | `back_command_binary.lua` | T003 |
| T005 | Add CmdAtomicFence encoder branch (zero-data) | `back_command_binary.lua` | T004 |
| T006 | Add CmdRotate encoder branch | `back_command_binary.lua` | — |
| T007 | Add CmdVecMask encoder branch with non-uniform arity | `back_command_binary.lua` | — |
| T008 | Add loud else clause for unrecognized BackCmds | `back_command_binary.lua` | T001–T007 |
| T009 | Verify with hand-constructed BackProgram round-trip test | — | T008 |
| T010 | Update test_atomics.lua to document current state | `tests/test_atomics.lua` | T009 |

T001–T005 are ordered (atomic branch block). T006, T007 are independent. T008 depends on all branches being in place. T009–T010 are verification tasks.

---

## Pattern Memo

Reference for the worker during implementation:

- **Sub-dispatch pattern**: `local ok = cmd.op.kind or cmd.op` then `if ok == "BackVariantName" then ... elseif ... else fallback end`. Used by CmdShift, CmdVecBinary, CmdIntBinary, etc. Follow this exactly.
- **memflags encoding**: Call the existing `memflags(cmd.memory)` helper — do not reimplement. It returns bit0=notrap, bit1=aligned, bit2=can_move, bit3=readonly.
- **Address resolution**: Call `emit_effective_addr(buf, cmd.addr)` — do not inline StackAddr/GlobalValue/etc. Let the helper handle it.
- **Scalar type on atomics**: `cmd.ty` is a `BackScalar` (not BackShape). Use `st(cmd.ty)` directly. The `st()` helper's fallback branch `S[s.kind]` handles BackScalar kinds like `BackI32`, `BackF64`, etc.
- **Wire slot order**: Must match the TAG_SLOTS entries in `src/wire_tags.rs` and the Rust decoder handlers in `src/decode.rs`. Double-check slot order against the wire format spec in `BACK_WIRE_FORMAT.md` §5.
- **Silently dropped fields**: `cmd.ordering` (BackAtomicOrdering, always BackAtomicSeqCst) and `cmd.scalar`/`cmd.ty` (for Rotate/VecMask where type is not in wire) are intentionally omitted. Add a brief comment noting the omission.
- **Error style**: Use `error("unrecognized BackCmd: " .. tostring(k))` — no `assert`, no custom error object. Match the existing error style in the file.
