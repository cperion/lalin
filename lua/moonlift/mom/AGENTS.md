# MOM Agent Rules

This is the MOM-specific agent contract — **project management backbone** for
porting the Moonlift hosted compiler to native MOM. AI agents working on this
codebase **must** follow this document strictly.

---

## 1. Task Management (Zero-Friction CLI)

Use `./scripts/mom-task` or `make task-*` for all project tracking. No
`package.path` gymnastics needed.

```bash
./scripts/mom-task progress          # progress bars for sections + lowering
./scripts/mom-task status            # pending vs completed with dependency info
./scripts/mom-task next              # what to work on next (auto-detected)
./scripts/mom-task show "typecheck"  # details on one section (files, oracles, deps)
./scripts/mom-task done "typecheck"  # mark complete (auto-verifies files + deps)
./scripts/mom-task reset "typecheck" # unmark
./scripts/mom-task verify            # check all source files exist
./scripts/mom-task json              # machine-readable JSON for tooling

# Makefile equivalents:
make task-status     make task-progress     make task-next
make task-verify     make task-done-typecheck
```

**How to use as an AI agent:**

1. **Start a session:** `make task-next` — see what section to work on.
2. **Read context:** `make task-show-<id>` — details + hosted oracle + test files.
3. **Read the hosted oracle** (`lua/moonlift/tree_to_back.lua` etc.) before
   writing any MOM code.
4. **Read `LANGUAGE_REFERENCE.md`** for relevant language semantics.
5. **Implement** following the port map signatures.
6. **Run tests** from the section's test list.
7. **Mark done:** `make task-done-<id>` — auto-verifies deps and file exports.
8. **Loop:** `make task-next` again.

State is tracked in `lua/moonlift/mom/build/.taskstack_state.lua` (git-tracked).
Progress persists across sessions and agents.

---

## 2. First: Load the Port Map

```lua
local port_map = require("moonlift.mom.build.port_map")
```

The port map is the complete module/signature mapping from hosted Lua compiler
to native MOM. **Read it before any implementation change.** If a change is not
represented there, update the mapping first and stop. Do not implement orphan
features.

---

## 3. Source of Truth Hierarchy

| Priority | Source | Purpose |
|----------|--------|---------|
| 1 | `lua/moonlift/*.lua` (relevant file named in port_map) | **Hosted semantic oracle.** Exact behavior to port. |
| 2 | `LANGUAGE_REFERENCE.md` | **Language semantics.** Types, expressions, control, ABI, fragments, views, splices. The complete language contract. |
| 3 | `BACK_WIRE_FORMAT.md` | **Wire format.** MLBT v3 serialization layout, slot positions. |
| 4 | `lua/moonlift/mom/schema/*.mlua` | **Schema definitions.** ASDL type trees, union variants, field types. |
| 5 | `SOURCE_GRAMMAR.md` | **Grammar.** Jump-first control, tokens, parser contract. |
| 6 | `lua/moonlift/mom/tags/mom_tags.lua` | **Generated numeric constants only.** Never infer design from tag values. |

**Rules:**
- Never invent semantics. The hosted compiler is the oracle.
- Never use `mom_tags.lua` as design evidence — mechanically generated.
- When in doubt, read the hosted `.lua` file and `LANGUAGE_REFERENCE.md`.

---

## 4. Hard Bans (Absolute)

| Ban | Why |
|-----|-----|
| No inventing semantics | Hosted compiler is oracle. Different behavior = broken tests. |
| No `TODO`/`FIXME`/`placeholder`/`simplified`/`not-yet`/`for-now` | AI agents produce these to skip work. Ship complete code or nothing. |
| No `CmdTrap` as fallback | `CmdTrap` is a real trap, not a "not implemented" marker. Only emit when hosted emits equivalent unsupported (e.g. `Tr.ExprIf`). |
| No raw command slot packing in lowerers | Use `mb_emit_*` helpers from `back/cmd.mlua`. Hand-packing bypasses layout checks. |
| No `@malloc` or hidden allocation | All buffers from caller/Rust arena. No `malloc`/`free` in compiler phases. |
| No fake continuation args like `?` | Continuation arguments are real typed values. Placeholders hide bugs. |
| No `emit foo(...)()` | Emitted regions return through continuations. This shape signals confusion. |

**Enforced by:** `luajit scripts/check_mom_hygiene.lua` — run before every
commit. Greps for banned patterns, exits 1 on any match.

---

## 5. Command Emission Contract

`lua/moonlift/mom/back/cmd.mlua` owns slot layout. Lowerers **must** use named
append helpers (`mb_emit_*`) that combine `CmdEntry` construction with
`MomCmdBuffer` push. These helpers are the only path to the command buffer.

Currently required append helpers (from port_map section 7):

```
mb_emit_create_sig        mb_emit_declare_func       mb_emit_declare_extern
mb_emit_begin_func        mb_emit_create_block       mb_emit_switch_to_block
mb_emit_seal_block        mb_emit_bind_entry_params  mb_emit_append_block_param
mb_emit_finish_func       mb_emit_finalize_module
mb_emit_const             mb_emit_alias              mb_emit_stack_addr
mb_emit_data_addr         mb_emit_func_addr          mb_emit_extern_addr
mb_emit_unary             mb_emit_binary             mb_emit_compare
mb_emit_cast              mb_emit_select             mb_emit_call
mb_emit_ptr_offset        mb_emit_load_info          mb_emit_store_info
mb_emit_atomic_load       mb_emit_atomic_store       mb_emit_atomic_rmw
mb_emit_atomic_cas        mb_emit_atomic_fence
mb_emit_jump              mb_emit_br_if              mb_emit_switch_int
mb_emit_return_void       mb_emit_return_value
mb_emit_vec_splat         mb_emit_vec_binary         mb_emit_vec_compare
mb_emit_vec_select        mb_emit_vec_mask           mb_emit_vec_load_info
mb_emit_vec_store_info
```

**If a helper you need does not exist, add it to `cmd.mlua` first.** Do not work
around missing helpers with raw pushes.

---

## 6. Backend Lowering Replacement Order

The two current lowerer files (`expr_lower.mlua`, `stmt_lower.mlua`) violate the
hard bans (raw command packing, `CmdTrap` fallbacks, duplicated logic). They
**must be replaced** under this strict order. Each step produces a focused test.

```
Step 1:  MomBackLowerCtx struct           — typed lowering context (new)
Step 2:  mb_emit_* append helpers         — in cmd.mlua (new)
Step 3:  Replace expr_lower.mlua cases    — lit, ref scalar, unary, binary,
                                            compare, cast, select, logic
Step 4:  Replace stmt_lower.mlua cases    — let, expr, scalar/void return,
                                            stmt list
Step 5:  Function/module lowering         — move from compile_module.mlua
                                            to back/func.mlua, back/module.mlua
Step 6:  Address/view/store module        — back/address.mlua (new)
Step 7:  If/switch phi statements         — proper LocalCell branching
Step 8:  Control region lowering          — back/control_lower.mlua (new)
Step 9:  Memory/atomic/globals/view       — expand command families
Step 10: Vector integration               — connect vec/*.mlua to lowering
```

---

## 7. Work Protocol (Per Change)

1. **`make task-next`** — find what to work on.
2. **`make task-show-<id>`** — read section details.
3. **Read the hosted oracle** named in the port map's `hosted_function_map`.
4. **Read `LANGUAGE_REFERENCE.md`** sections relevant to the semantics.
5. **State the contract** in your response: "Implementing X. Input: Y. Output: Z.
   Hosted oracle: tree_to_back.lua lines N-M."
6. **Check existing helpers.** If a named helper is missing, add it first.
7. **Write the code.** Follow `return function(M) ... end` pattern. Naming
   prefixes: `mr_`=runtime, `mt_`=type, `mb_`=backend, `mc_`=driver, `mw_`=wire.
8. **Add a focused test** from the test ladder.
9. **Run the test.**
10. **Run hygiene:** `luajit scripts/check_mom_hygiene.lua`.
11. **`make task-done-<id>`** — marks complete with auto-verification.
12. **Report exact commands run** and their output.

---

## 8. Test Ladder

| Tier | Test | Proves |
|------|------|--------|
| Scalar | `func main() -> i32 return 2 + 2 end` | Push commands |
| Scalar | `let x: i32 = 2; return x + 2` | Local bindings |
| Scalar | comparisons, logic, casts matrix | Op dispatch |
| Function | direct call, extern call, void stmt | Multi-function + ABI |
| Control | if phi, switch, block/jump loop | Control lowering |
| Memory | var, addr-of, ptr index, view ABI | Memory operations |
| Product | `mom status`, `mom run` | End-to-end |

---

## 9. Common AI Failure Modes

| Mode | Symptom | Prevention |
|------|---------|------------|
| **Semantic drift** | MOM behavior differs from hosted | Read hosted oracle first. Quote relevant lines. |
| **Stale markers** | `TODO` in committed code | `CmdTrap` is real, not a marker. Ship complete code. |
| **Raw slot packing** | `mb_push_cmd(@{T.CmdFoo})` in lowerers | Add helper first. |
| **Copy-paste duplication** | Same expr logic in both expr+stmt lowerers | Import from ops.mlua/cmd.mlua. |
| **Skipping oracle** | Guessing semantics from context | Stop. Read the hosted file. |
| **Scope creep** | Unrelated features in same change | One section per change. |
| **Hidden allocation** | `@malloc` or arena-free allocs | All buffers pre-allocated. |
| **Forgetting tests** | No test for new functionality | Every case needs a test-ladder entry. |

**When unsure, stop. Do not guess.** Re-read the hosted oracle, port map entry,
and `LANGUAGE_REFERENCE.md`. If still unsure, ask the human.

---

## 10. Quick Reference

| What | Where |
|------|-------|
| Port map (authoritative plan) | `lua/moonlift/mom/build/port_map.lua` |
| Task stack (progress tracker) | `lua/moonlift/mom/build/taskstack.lua` |
| Task CLI | `./scripts/mom-task` |
| Makefile targets | `make task-progress`, `make task-next`, `make task-done-<id>` |
| Schema definitions | `lua/moonlift/mom/schema/*.mlua` |
| Command entry constructors | `lua/moonlift/mom/back/cmd.mlua` |
| Op/type helpers | `lua/moonlift/mom/back/ops.mlua` |
| Environment (local bindings) | `lua/moonlift/mom/back/env.mlua` |
| ID allocators | `lua/moonlift/mom/back/ids.mlua` |
| Runtime builders | `lua/moonlift/mom/runtime/builders.mlua` |
| Language reference | `LANGUAGE_REFERENCE.md` |
| Wire format spec | `BACK_WIRE_FORMAT.md` |
| Grammar | `SOURCE_GRAMMAR.md` |
| Protocol syntax | `PROTOCOL_SYNTAX.md` |
| Hygiene checker | `scripts/check_mom_hygiene.lua` |
| Hosted lowering oracle | `lua/moonlift/tree_to_back.lua` |
| Hosted typecheck oracle | `lua/moonlift/tree_typecheck.lua` |
| Hosted control oracle | `lua/moonlift/tree_control_to_back.lua` |
| Build + product test | `make && luajit tests/test_mom_run_2plus2.lua` |
