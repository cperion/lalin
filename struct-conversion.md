# ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ MOM Codebase Struct Conversion Guide                                                                                                                             ┃
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

1. Core Principle

The schema is the source of truth for every struct and union type.
Every struct used in the lowering pipeline must be defined in one of the schema files under lua/moonlift/mom/schema/. Lowering code never defines ad‑hoc layouts; it
only constructs schema‑defined structs and accesses their named fields.

1. Naming Conventions

 Category                    Prefix         Example
 ────────────────────────────────────────────────────────────────────
 Workspace / context struct  Mom*Workspace  MomControlRegionWorkspace
 Phi / if‑switch table               Mom*PhiTable   MomIfPhiTable
 Fact tape slice                     Mom*Slice      MomControlFactSlice
 Small result bundle                 Mom*Result     MomExprResult
 Memory address descriptor           Mom*Addr       MomAddressResult
 Auxiliary builder (legacy, shrink)  keep aux_i32   only for driver boundary  

File location: Workspace structs that are used by a single back‑end module go into lua/moonlift/mom/back/workspace_<module>.mlua (or, for small ones, directly near
their usage). Reusable structs go into lua/moonlift/mom/schema/MomBack.mlua or a new dedicated MomBackWorkspace.mlua.

1. Mapping Current Patterns → Structs

3.1 Control Region Lowering

Current: Five i32 arguments (ctrl_start, n_blocks, block_ids_aux, exit_blk, is_expr, result_scalar) + ad‑hoc aux_i32 arithmetic to find block ids, param values,
result value.

Target struct (defined in MomBack.mlua):

M.MomControlRegionWorkspace = struct MomControlRegionWorkspace
    ctrl_start: i32
    n_blocks: i32
    block_ids: view(i32)      -- view into aux_i32 after allocation
    param_vals: view(i32)     -- view into aux_i32 after param storage
    exit_blk: i32
    is_expr: bool
    result_scalar: i32
    result_val: i32           -- only valid if is_expr; set once
end

Construction (one place, at the end of create_exit block):

let total_params: i32 = compute_total_param_count()  -- already a block sum
let aux: ptr(@{MomControlRegionWorkspace}) = mb_ctx_fresh_workspace(ctx, MomControlRegionWorkspace(
    ctrl_start = ctrl_start,
    n_blocks = n_blocks,
    block_ids = as(view(i32), ctx.aux_i32.data + block_ids_aux, n_blocks),
    param_vals = as(view(i32), ctx.aux_i32.data + param_vals_offset, total_params),
    exit_blk = exit_blk,
    is_expr = is_expr,
    result_scalar = result_scalar,
    result_val = as(i32, ctx.aux_i32.data[result_aux_offset])
))

Usage in lower_blocks:

// Before:
let param_start: index = as(index, block_ids_aux) + as(index, n_blocks) + as(index, total_before)

// After:
let param_start: index = as(index, aux.param_vals.data) + as(index, total_before)

3.2 If‑Statement Phi Table

Current: A complex tri‑phase layout in aux_i32: merged names area, then phi info area with three‑tuple per changed binding.

Target struct (in MomBack.mlua or a new MomBackPhi.mlua):

M.MomIfPhiEntry = struct MomIfPhiEntry
    name_tok: i32
    param_val: i32
    scalar: i32
end

M.MomIfPhiTable = struct MomIfPhiTable
    entries: view(MomIfPhiEntry)
    n_changed: i32
    then_blk: i32
    else_blk: i32
    join_blk: i32
end

Construction replaces manual phi_info_aux + triplicate pushes:

let phi_table: ptr(@{MomIfPhiTable}) = mb_ctx_fresh_phi(ctx, n_changed)
block fill(i: i32 = 0)
    if i >= n_changed then jump done() end
    let name_tok: i32 = merged_names[i]
    let scalar: i32 = old_scalar(name_tok)
    let param_val: i32 = mb_ctx_fresh_value(ctx)
    mb_emit_append_block_param(ctx, join_blk, param_val, 0, scalar, 0)
    phi_table.entries[i] = MomIfPhiEntry(name_tok = name_tok, param_val = param_val, scalar = scalar)
    jump fill(i = i + 1)
end

Rebind step:

block rebind(i: i32 = 0)
    if i >= phi_table.n_changed then yield end
    let e: @{MomIfPhiEntry} = phi_table.entries[i]
    mb_env_bind_scalar(ctx.env, e.name_tok, e.scalar, e.param_val)
    jump rebind(i = i + 1)
end

3.3 Switch‑Statement Cases Aux

Current: Interleaved key_val, target_block pairs in aux_i32, accessed as ctx.aux_i32.data[as(index, cases_aux) + ci * 2] etc.

Target struct (in MomBack.mlua):

M.MomSwitchCaseEntry = struct MomSwitchCaseEntry
    key_val: i32
    target_blk: i32
end

M.MomSwitchCaseTable = struct MomSwitchCaseTable
    entries: view(MomSwitchCaseEntry)
    n_cases: i32
    default_blk: i32
end

Build phase becomes:

let case_table: ptr(@{MomSwitchCaseTable}) = mb_ctx_fresh_switch(ctx, arm_count)
block fill(ci: i32 = 0)
    if ci >= arm_count then yield end
    let key_expr: i32 = tree.switch_arm_key[arm_start + ci]
    var key_val: i32 = 0; var key_ok: bool = false
    emit mb_lower_expr_region(ctx, key_expr, key_val, key_scalar, key_ok)
    if key_ok == false then jump done(flow = 0, ok = false) end
    case_table.entries[ci] = MomSwitchCaseEntry(key_val = key_val, target_blk = ctx.aux_i32.data[arm_block_aux + ci])
    jump fill(ci = ci + 1)
end
mb_emit_switch_int(ctx, value_val, value_scalar, case_table)

3.4 Expr/Stmt Result Protocols

Current: Each region returns (value, scalar, ok) or (flow, ok) through continuation outputs.

Target struct (in MomBack.mlua or as a struct in ops.mlua):

M.MomExprResult = struct MomExprResult
    value: i32
    scalar: i32
    ok: bool
end

M.MomStmtResult = struct MomStmtResult
    flow: i32
    ok: bool
end

Continuation signatures become:

// Before:
emit mb_lower_expr_region(ctx, idx; done = cont(value: i32, scalar: i32, ok: bool))

// After:
emit mb_lower_expr_region(ctx, idx; done = cont(result: MomExprResult))

This eliminates three separate outputs from every expression‑lowering region and makes the return contract explicit.

3.5 Memory Address Lowering

Current: mb_place_addr_to_back returns (addr, pointee_scalar, ok) via continuation.

Target struct:

M.MomAddressResult = struct MomAddressResult
    addr: i32
    pointee_scalar: i32
    ok: bool
end

Continuation:

emit mb_place_addr_to_back(ctx, place_idx; done = cont(result: MomAddressResult))

3.6 Module / Function Lowering

The current push_param_scalars / push_result_scalar functions push raw i32s into aux. They become struct constructors that return typed slices.

Target struct:

M.MomFuncSig = struct MomFuncSig
    params_aux: view(i32)
    n_params: i32
    result_aux: view(i32)
    n_results: i32
    sig_id: i32
    func_id: i32
end

Construction becomes:

let sig: @{MomFuncSig} = MomFuncSig(
    params_aux = as(view(i32), ctx.aux_i32.data + params_offset, n_params),
    n_params = n_params,
    result_aux = as(view(i32), ctx.aux_i32.data + result_offset, select(void ? 0 : 1)),
    n_results = select(void ? 0 : 1),
    sig_id = sig_id,
    func_id = func_id
)

3.7 Validation Fact Tapes

Current: Six parallel i32 arrays passed as separate ptr arguments.

Target struct:

M.MomCmdSlice = struct MomCmdSlice
    tag: ptr(i32)
    a: ptr(i32)
    b: ptr(i32)
    c: ptr(i32)
    d: ptr(i32)
    e: ptr(i32)
    f: ptr(i32)
    n: i32
end

Validation region signature becomes:

local mb_validate = region(cmds: MomCmdSlice, ...)

3.8 Vectorization Fact Tapes

Same pattern as validation: the six parallel arrays become a single MomVecFactSlice struct.

1. New Schema Files

All structs should go into existing schema files to avoid scattering. Suggested additions:

 Struct group                            Schema file  
 ────────────────────────────────────────────────────────────────────────────────────
 MomControlRegionWorkspace               MomBack.mlua
 MomIfPhiTable, MomIfPhiEntry            MomBack.mlua
 MomSwitchCaseTable, MomSwitchCaseEntry  MomBack.mlua
 MomExprResult, MomStmtResult            MomBack.mlua
 MomAddressResult                        MomBack.mlua
 MomFuncSig                              MomBack.mlua
 MomCmdSlice                             MomBack.mlua (or dedicated MomValidate.mlua)
 MomVecFactSlice                         MomVec.mlua

If the schema file becomes too large, split into MomBackWorkspace.mlua, MomBackPhi.mlua, etc. – but keep them under lua/moonlift/mom/schema/.

1. Helper Functions to Create Workspace Structs

Add helper functions in the relevant back‑end modules that construct these structs from raw builder state, so lowering code never directly manipulates aux_i32
offsets.

// in back/control_lower.mlua:
local mb_build_region_workspace = func(ctx: ptr(@{MomBackLowerCtx}),
                                        ctrl_start: i32, n_blocks: i32,
                                        block_ids_aux: i32, exit_blk: i32,
                                        is_expr: bool, result_scalar: i32) -> MomControlRegionWorkspace
    var total_params: i32 = 0
    block sum(bi: i32 = 0)
        if bi >= n_blocks then yield end
        total_params = total_params + mb_control_block_param_count(tree, ctrl_start, bi)
        jump sum(bi = bi + 1)
    end
    let result_val_offset: i32 = block_ids_aux + n_blocks + total_params
    return MomControlRegionWorkspace(
        ctrl_start = ctrl_start,
        n_blocks = n_blocks,
        block_ids = as(view(i32), ctx.aux_i32.data + block_ids_aux, n_blocks),
        param_vals = as(view(i32), ctx.aux_i32.data + (block_ids_aux + n_blocks), total_params),
        exit_blk = exit_blk,
        is_expr = is_expr,
        result_scalar = result_scalar,
        result_val = as(i32, ctx.aux_i32.data[result_val_offset])
    )
end

Then throughout the rest of control_lower.mlua, all code references aux.block_ids[bi], aux.param_vals[offset], aux.exit_blk, etc.

1. Passing Structs Through Region Continuations

The MomControlRegionWorkspace struct is built once at the end of create_exit and then threaded through every subsequent block as a single continuation argument:

block init_params(pi: i32, aux: @{MomControlRegionWorkspace})
    ...
    jump init_params(pi = pi + 1, aux = aux)
end

block lower_blocks(bi: i32, aux: @{MomControlRegionWorkspace})
    ...
    jump lower_blocks(bi = bi + 1, aux = aux)
end

block seal_exit(aux: @{MomControlRegionWorkspace})
    ...
end

Rule: A struct that is passed through more than two blocks should be passed as ptr(@{MomControlRegionWorkspace}) (not by value) to avoid struct‑copy overhead. The  
struct is built once in the entry trampoline and never mutated, so a pointer is safe and efficient.

1. Converting Continuation Outputs to Structs

Wherever a region returned a tuple like cont(value: i32, scalar: i32, ok: bool), replace it with cont(result: MomExprResult).  In the emitting region, build the
result struct just before the jump:

mb_emit_const(ctx, dst, scalar, lit_tag, lit_lo, lit_hi)
jump done(result = MomExprResult(value = dst, scalar = scalar, ok = true))

In the receiving region, destructure immediately if needed:

let value: i32 = result.value
let scalar: i32 = result.scalar

1. Converting SoA Arrays to View Structs

Anywhere you have parallel arrays like:

func foo(tag: ptr(i32), a: ptr(i32), b: ptr(i32), n: i32)

Replace with a slice struct:

M.MomXYZSlice = struct MomXYZSlice
    tag: ptr(i32)
    a: ptr(i32)
    b: ptr(i32)
    n: i32
end

Then the caller builds:

let slice: @{MomXYZSlice} = MomXYZSlice(
    tag = fact_tag,
    a = fact_a,
    b = fact_b,
    n = n_facts
)

This reduces argument counts from 4+ to 1 and makes the data relationship explicit.

1. Phasing / Migration Strategy

 1 Schema first – add all new struct definitions to MomBack.mlua and MomVec.mlua (or new dedicated files).
 2 Add helper constructors – create mb_build_region_workspace, mb_build_if_phi, etc. that encapsulate the old aux_i32 arithmetic.
 3 Convert one region at a time – start with control_lower.mlua (the most complex), then stmt_lower.mlua, then expr_lower.mlua, then the rest.
 4 Remove intermediate aux_i32 – once all uses of a given layout are replaced, remove the old offset‑arithmetic code and the associated comments.
 5 Run test ladder after each region – ensure nothing breaks.
 6 Shrink aux_i32 – after full conversion, aux_i32 is only used for driver‑boundary i32 slices (like param scalars going to wire). Do not eliminate it entirely;
   just limit its scope.

1. Hygiene Checklist for Each Conversion

 • [ ] New struct exists in schema
 • [ ] Helper constructor encapsulates all offset math
 • [ ] All ctx.aux_i32.data[offset + index] replaced by struct.field[index]
 • [ ] All (value, scalar, ok) continuation outputs replaced by MomExprResult
 • [ ] All (flow, ok) outputs replaced by MomStmtResult
 • [ ] All five‑argument region signatures consolidated into one struct arg
 • [ ] CmdTrap is not used as placeholder (only where hosted oracle uses it)
 • [ ] luajit scripts/check_mom_hygiene.lua passes
 • [ ] Test ladder passes

# File‑by‑File Struct Conversion Plan

All new struct definitions should be added to schema files under `lua/moonlift/mom/schema/`.  
The main target file is `MomBack.mlua`; vector‑related structs go into `MomVec.mlua`.  
Helper functions that encapsulate struct construction go into the corresponding back‑end module.

---

### 1. `lua/moonlift/mom/schema/MomBack.mlua` — New struct definitions

Add the following structs:

- `MomControlRegionWorkspace` (fields: `ctrl_start`, `n_blocks`, `block_ids: view(i32)`, `param_vals: view(i32)`, `exit_blk`, `is_expr`, `result_scalar`, `result_val`)
- `MomIfPhiEntry` (fields: `name_tok`, `param_val`, `scalar`)
- `MomIfPhiTable` (fields: `entries: view(MomIfPhiEntry)`, `n_changed`, `then_blk`, `else_blk`, `join_blk`)
- `MomSwitchCaseEntry` (fields: `key_val`, `target_blk`)
- `MomSwitchCaseTable` (fields: `entries: view(MomSwitchCaseEntry)`, `n_cases`, `default_blk`)
- `MomExprResult` (fields: `value`, `scalar`, `ok: bool`)
- `MomStmtResult` (fields: `flow`, `ok: bool`)
- `MomAddressResult` (fields: `addr`, `pointee_scalar`, `ok: bool`)
- `MomFuncSig` (fields: `params_aux: view(i32)`, `n_params`, `result_aux: view(i32)`, `n_results`, `sig_id`, `func_id`)
- `MomCmdSlice` (fields: `tag: ptr(i32)`, `a: ptr(i32)`, `b: ptr(i32)`, `c: ptr(i32)`, `d: ptr(i32)`, `e: ptr(i32)`, `f: ptr(i32)`, `n: i32`)

---

### 2. `lua/moonlift/mom/schema/MomVec.mlua` — New vector structs

- `MomVecFactSlice` (fields: `tag: ptr(i32)`, `a..f: ptr(i32)`, `n: i32`)
- `MomVecDecision` (fields: `tag`, `elem`, `lanes`, `unroll`, `tail_mode`, `proofs)  // kept as flat i32 for now, but wrap in struct
- `MomVecPlan` (fields: `tag`, `elem`, `extra1`, `extra2`)

---

### 3. `lua/moonlift/mom/back/control_lower.mlua`

**Changes:**

- Add `mb_build_region_workspace` helper that computes offsets and returns a `MomControlRegionWorkspace`.
- Replace all five‑argument signatures (`ctrl_start, n_blocks, block_ids_aux, exit_blk, is_expr, result_scalar`) with a single `aux: ptr(@{MomControlRegionWorkspace})` argument.
- Replace `block_ids_aux`, `n_blocks`, `exit_blk` ad‑hoc uses with `aux.block_ids[i]`, `aux.exit_blk`, etc.
- In `seal_exit`, remove the `total_params` re‑computation; use `aux.result_val` directly.
- In `init_params`, use `aux.block_ids[0]` for entry block ID.
- In `lower_blocks`, use `aux.block_ids[bi]`, `aux.param_vals[total_before]`.
- Replace `if_phi_info_aux` triplet pushes with `MomIfPhiTable` construction; rebind using `entries[i].name_tok` etc.
- Replace `cases_aux` pairs with `MomSwitchCaseTable` construction.
- All `done(flow=..., ok=...)` continuations become `done(result = MomStmtResult(flow, ok))`.

---

### 4. `lua/moonlift/mom/back/expr_lower.mlua`

**Changes:**

- Define a local `mb_build_expr_result` helper (or just construct `MomExprResult` at each exit point).
- Every `jump done(value = ..., scalar = ..., ok = ...)` becomes `jump done(result = MomExprResult(value, scalar, ok))`.
- `mb_lower_expr_region` continuation signature changes from `(value, scalar, ok)` to `(result: MomExprResult)`.
- Update all call sites that emit `mb_lower_expr_region` to destructure `result.value` etc.
- `mb_expr_view` returns `MomViewResult` (new struct? or keep separate; can keep as is for now, but could become `MomViewResult` with `data, len, stride, elem_scalar, ok`).
- `mb_lower_call_args` returns `MomCallArgsResult` (new struct: `aux`, `n_args`, `ok`).

---

### 5. `lua/moonlift/mom/back/stmt_lower.mlua`

**Changes:**

- Add `MomStmtResult` usage: every `jump done(flow = ..., ok = ...)` becomes `jump done(result = MomStmtResult(flow, ok))`.
- `mb_lower_stmt`, `mb_lower_stmt_list`, `mb_lower_control_stmt_list` all receive/return `MomStmtResult`.
- Replace `collect_changed_bindings` region outputs `(aux_start, count)` with a `MomBindingSlice` struct (optional; could keep as is because it's a return of two i32s; but align with style).
- `mb_lower_if_stmt` and `mb_lower_switch_stmt` replace their internal `aux_i32` layouts with `MomIfPhiTable` and `MomSwitchCaseTable`.

---

### 6. `lua/moonlift/mom/back/address.mlua`

**Changes:**

- `mb_place_addr_to_back` changes from `done(addr, pointee_scalar, ok)` to `done(result: MomAddressResult)`.
- `mb_index_addr_to_back` similarly returns `MomAddressResult`.
- `mb_view_to_back` may keep separate or become a `MomViewResult`.
- Update all internal recursion (`mb_place_addr_to_back` calling itself) to destructure `result.addr` etc.

---

### 7. `lua/moonlift/mom/back/module.mlua`

**Changes:**

- `push_param_scalars` and `push_result_scalar` are replaced by a `MomFuncSig` construction.
- `mb_lower_module` builds `MomFuncSig` for each function/extern and passes it to `mb_lower_func` / `mb_lower_extern`.
- The `sig_offset_base` pointer arithmetic is replaced by a `view(MomFuncSig)` or a separate array of sig structs.

---

### 8. `lua/moonlift/mom/back/func.mlua`

**Changes:**

- `mb_lower_func` and `mb_lower_extern` receive a `MomFuncSig` struct instead of separate `params_aux`, `n_params`, etc.
- `emit_entry_block` may return a `MomEntryBlockResult` (new struct: `entry_id`, `param_vals_aux`).

---

### 9. `lua/moonlift/mom/back/control.mlua`

**Changes:**

- `mb_extract_jump_facts` currently takes `fact_tag, fact_a, …` arrays.  Replace all calls that produce facts with `MomControlFactSlice` (or `MomFactSlice`).
- `mb_validate_control` takes a `MomCmdSlice` instead of six separate array pointers.
- `mb_push_fact`, `mb_push_reject` may keep their internal SoA for performance, but the public API becomes struct‑based.

---

### 10. `lua/moonlift/mom/back/validate.mlua`

**Changes:**

- `mb_validate` signature changes from `(ct, ca, cb, cc, cd, ce, cf, n, …)` to `(cmds: MomCmdSlice, …)`.
- Internally it accesses `cmds.tag[i]`, `cmds.a[i]`, etc.
- The `ms, mk` map arrays remain as raw i32 arrays (internal implementation detail).
- `mb_validate_region` region also uses `MomCmdSlice`.

---

### 11. `lua/moonlift/mom/vec/vec_facts.mlua`

**Changes:**

- `mv_extract_vec_facts` changes from six separate arrays to a `MomVecFactSlice` input.
- Output fact tape construction remains SoA (maybe keep as is for performance; no need to convert output side yet).

---

### 12. `lua/moonlift/mom/vec/vec_decide.mlua`

**Changes:**

- Input fact arrays become `MomVecFactSlice`.
- Output decision becomes a `MomVecDecision` struct written once (or keep flat with `MomVecDecision`).

---

### 13. `lua/moonlift/mom/vec/vec_plan.mlua`

**Changes:**

- Inputs become `MomVecFactSlice` and decision struct.
- Output becomes `MomVecPlan`.

---

### 14. `lua/moonlift/mom/driver/compile_source.mlua`

**Changes (minimal):**

- This file is at the driver boundary; it still uses raw SoA and `aux_i32` to talk to Rust.  Most struct conversion does not affect it.
- Only adjust calls to lower‑level functions that now take structs. For example, `mc_lower_phase` calls `mc_lower_module` (which may now accept a `MomFuncSig`); adjust the bridge code accordingly.  But the large SoA in `compile_source.mlua` (token fields, etc.) should remain as is — they are pre‑struct and not part of the struct conversion scope.

---

### 15. `lua/moonlift/mom/back/ops.mlua`

**Changes:**

- No struct conversion needed; pure scalar‑level functions.
- Possibly add a helper `mb_scalar_to_back` function that returns a `MomBackScalarResult` (if desired, but not necessary).

---

### 16. `lua/moonlift/mom/back/env.mlua`

**Changes:**

- Already uses `MomBackLocalEnv` struct; no change needed.
- Just ensure that `char` fields remain as `i32` (they are already).

---

### 17. `lua/moonlift/mom/back/ids.mlua`

**Changes:**

- Already uses `MomBackIdAllocator` struct; no change needed.

---

### 18. `lua/moonlift/mom/back/cmd.mlua`

**Changes:**

- `CmdEntry` is already a struct (defined in `MomBack.mlua` as `MomCmdEntry`? It's defined locally in `cmd.mlua`; consider moving the struct definition to `MomBack.mlua` for consistency, but not required).
- Retain the named `mb_cmd_*` functions; they already construct `CmdEntry` structs.
- No structural change needed.

---

### 19. `lua/moonlift/mom/runtime/builders.mlua`

**Changes:**

- Consider adding `mb_ctx_fresh_workspace` helper that allocates a `MomControlRegionWorkspace` from a pool (or heap).  For now, we can construct structs on the stack or via `ctx.aux_i32` views; no new builder needed.

---

### 20. `lua/moonlift/mom/back/type_abi_classify.mlua` and `type_size_align.mlua`

**Changes:**

- These are pure functions with no ada‑hoc `aux_i32`.  No struct conversion needed.

---

### Summary of Migration Steps

| Phase | Files | What to verify |
|-------|-------|----------------|
| 1 | Schema files (`MomBack.mlua`, `MomVec.mlua`) | Struct definitions compile |
| 2 | `control_lower.mlua` | Workspace struct used throughout; test passes |
| 3 | `stmt_lower.mlua` | `MomStmtResult` used; phi tables struct‑based |
| 4 | `expr_lower.mlua` + `address.mlua` | `MomExprResult`, `MomAddressResult` used |
| 5 | `module.mlua` + `func.mlua` | `MomFuncSig` used |
| 6 | `control.mlua`, `validate.mlua` | SoA arrays become `MomCmdSlice` |
| 7 | `vec/*.mlua` | Fact tapes become `MomVecFactSlice` |
| 8 | `compile_source.mlua` | Adjust calls to struct‑based functions (minimal) |
| 9 | Full test ladder | All tests pass, hygiene passes |

Each phase is independent; you can do them in any order, but `control_lower.mlua` is the most complex and should be tackled first to prove the pattern.
