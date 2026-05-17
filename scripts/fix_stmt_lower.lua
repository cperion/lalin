-- Fix stmt_lower.mlua: move inline blocks with variable defaults to
-- region-level blocks with explicit jumps.
-- Usage: luajit scripts/fix_stmt_lower.lua

local f = io.open("lua/moonlift/mom/back/stmt_lower.mlua", "r")
local content = f:read("*all")
f:close()

-- ── Fix 1: mb_lower_if_stmt ──────────────────────────────────────────
-- Replace the inline merge_scan/dedup/merge_else with region-level blocks.
-- Old pattern:
--   entry start()
--     ... setup, inline blocks, phi setup, br_if, then/else lowering, jump done()
--   end
--   block merge_then(...) ... end   -- DEAD
--   block merge_els(...) ... end    -- DEAD
--   block after_merge() ... end     -- DEAD
-- New pattern:
--   entry start()
--     ... setup
--     jump merge_then(ii = as(index, changed_then_aux))
--   end
--   block merge_then(ii: index) ... end
--   block merge_els(ii: index) ... end
--   block after_merge() ... end

local old_if_stmt = [[-- ── if statement phi lowering ────────────────────────────────────────
local mb_lower_if_stmt = region(ctx: ptr(@{MomBackLowerCtx}), stmt_idx: i32;
                                done: cont(flow: i32, ok: bool))
entry start()
    let tree: ptr = ctx.tree
    let cond_idx: i32 = tree.stmt_name[stmt_idx]
    let then_start: i32 = tree.stmt_type[stmt_idx]
    let then_count: i32 = tree.stmt_value[stmt_idx]
    var else_start: i32 = tree.stmt_body_start[stmt_idx]
    let else_count: i32 = tree.stmt_body_count[stmt_idx]

    var cond_val: i32 = 0
    var cond_scalar: i32 = 0
    var cond_ok: bool = false
    emit mb_lower_expr_region(ctx, cond_idx, cond_val, cond_scalar, cond_ok)
    if cond_ok == false then jump done(flow = @{BackFallsThrough}, ok = false) end

    -- collect changed bindings across both branches
    var changed_then_aux: i32 = 0
    var changed_then_cnt: i32 = 0
    if then_count > 0 then
        emit collect_changed_bindings(ctx, then_start, then_count, changed_then_aux, changed_then_cnt)
    end
    var changed_else_aux: i32 = 0
    var changed_else_cnt: i32 = 0
    if else_start >= 0 and else_count > 0 then
        emit collect_changed_bindings(ctx, else_start, else_count, changed_else_aux, changed_else_cnt)
    end
    -- merge unique names – store them in a new area
    let merged_aux: i32 = as(i32, ctx.aux_i32.len)
    block merge_scan(ii: index = as(index, changed_then_aux))
        if ii >= as(index, changed_then_aux + changed_then_cnt) then yield end
        let nt: i32 = ctx.aux_i32.data[ii]
        var dup: bool = false
        block dedup(jj: index = as(index, merged_aux))
            if jj >= as(index, ctx.aux_i32.len) then yield end
            if ctx.aux_i32.data[jj] == nt then dup = true; yield end
            jump dedup(jj = jj + as(index, 1))
        end
        if not dup then mb_ctx_push_aux_i32(ctx, nt) end
        jump merge_scan(ii = ii + as(index, 1))
    end
    if else_start >= 0 then
        block merge_else(ii: index = as(index, changed_else_aux))
            if ii >= as(index, changed_else_aux + changed_else_cnt) then yield end
            let nt: i32 = ctx.aux_i32.data[ii]
            var dup: bool = false
            block dedup(jj: index = as(index, merged_aux))
                if jj >= as(index, ctx.aux_i32.len) then yield end
                if ctx.aux_i32.data[jj] == nt then dup = true; yield end
                jump dedup(jj = jj + as(index, 1))
            end
            if not dup then mb_ctx_push_aux_i32(ctx, nt) end
            jump merge_else(ii = ii + as(index, 1))
        end
    end
    let n_changed: i32 = as(i32, ctx.aux_i32.len) - merged_aux

    -- create blocks
    let then_blk: i32 = mb_ctx_fresh_block(ctx)
    let else_blk: i32 = mb_ctx_fresh_block(ctx)
    let join_blk: i32 = mb_ctx_fresh_block(ctx)
    mb_emit_create_block(ctx, then_blk)
    mb_emit_create_block(ctx, else_blk)
    mb_emit_create_block(ctx, join_blk)

    -- For each changed binding, create a phi param on join block
    -- Store phi mappings: (name_tok, param_val, scalar) in aux after merged names
    let phi_info_aux: i32 = as(i32, ctx.aux_i32.len)
    block create_phi(pi: index = 0)
        if pi >= as(index, n_changed) then yield end
        let name_tok: i32 = ctx.aux_i32.data[as(index, merged_aux) + pi]
        let env_slot: i32 = mb_env_lookup(ctx.env, name_tok)
        let scalar: i32 = select(env_slot >= 0, ctx.env.scalar[as(index, env_slot)], 0)
        let param_val: i32 = mb_ctx_fresh_value(ctx)
        mb_emit_append_block_param(ctx, join_blk, param_val, 0, scalar, 0)
        mb_ctx_push_aux_i32(ctx, name_tok)
        mb_ctx_push_aux_i32(ctx, param_val)
        mb_ctx_push_aux_i32(ctx, scalar)
        jump create_phi(pi = pi + as(index, 1))
    end

    -- conditional branch to then/else
    mb_emit_br_if(ctx, cond_val, then_blk, 0, 0, else_blk, 0, 0)
    mb_emit_seal_block(ctx, then_blk)
    mb_emit_seal_block(ctx, else_blk)

    -- lower then-body
    mb_emit_switch_to_block(ctx, then_blk)
    var then_flow: i32 = @{BackFallsThrough}
    var then_ok: bool = false
    if then_count > 0 then
        emit mb_lower_stmt_list(ctx, then_start, as(index, then_count), then_flow, then_ok)
    end
    if then_ok == false and then_count > 0 then then_flow = @{BackFallsThrough} end
    if then_flow ~= @{BackTerminates} then
        -- collect current values for phi targets
        let then_args_aux: i32 = as(i32, ctx.aux_i32.len)
        block then_args(pi: index = 0)
            if pi >= as(index, n_changed) then yield end
            let name_tok: i32 = ctx.aux_i32.data[as(index, merged_aux) + pi]
            let env_slot: i32 = mb_env_lookup(ctx.env, name_tok)
            let kind: i32 = select(env_slot >= 0, ctx.env.kind[as(index, env_slot)], 0)
            if env_slot >= 0 and kind == @{MB_LOCAL_SCALAR} then
                let val: i32 = ctx.env.val[as(index, env_slot)]
                mb_ctx_push_aux_i32(ctx, val)
            else
                mb_ctx_push_aux_i32(ctx, 0)
            end
            jump then_args(pi = pi + as(index, 1))
        end
        mb_emit_jump(ctx, join_blk, then_args_aux, n_changed)
    end

    -- lower else-body (or empty else)
    mb_emit_switch_to_block(ctx, else_blk)
    var else_flow: i32 = @{BackFallsThrough}
    if else_start >= 0 and else_count > 0 then
        var else_ok: bool = false
        emit mb_lower_stmt_list(ctx, else_start, as(index, else_count), else_flow, else_ok)
        if else_ok == false then else_flow = @{BackFallsThrough} end
    end
    if else_flow ~= @{BackTerminates} then
        let else_args_aux: i32 = as(i32, ctx.aux_i32.len)
        block else_args(pi: index = 0)
            if pi >= as(index, n_changed) then yield end
            let name_tok: i32 = ctx.aux_i32.data[as(index, merged_aux) + pi]
            let env_slot: i32 = mb_env_lookup(ctx.env, name_tok)
            let kind: i32 = select(env_slot >= 0, ctx.env.kind[as(index, env_slot)], 0)
            if env_slot >= 0 and kind == @{MB_LOCAL_SCALAR} then
                let val: i32 = ctx.env.val[as(index, env_slot)]
                mb_ctx_push_aux_i32(ctx, val)
            else
                mb_ctx_push_aux_i32(ctx, 0)
            end
            jump else_args(pi = pi + as(index, 1))
        end
        mb_emit_jump(ctx, join_blk, else_args_aux, n_changed)
    end

    -- determine overall flow
    let any_falls: bool = (then_flow ~= @{BackTerminates} or else_flow ~= @{BackTerminates})
    if any_falls then
        mb_emit_seal_block(ctx, join_blk)
        mb_emit_switch_to_block(ctx, join_blk)
    end

    -- rebind env with phi values
    block rebind(pi: index = 0)
        if pi >= as(index, n_changed) then yield end
        let base: index = as(index, phi_info_aux) + pi * as(index, 3)
        let name_tok: i32 = ctx.aux_i32.data[base]
        let param_val: i32 = ctx.aux_i32.data[base + as(index, 1)]
        let scalar: i32 = ctx.aux_i32.data[base + as(index, 2)]
        mb_env_bind_scalar(ctx.env, name_tok, scalar, param_val)
        jump rebind(pi = pi + as(index, 1))
    end

    let final_flow: i32 = select(any_falls, @{BackFallsThrough}, @{BackTerminates})
    jump done(flow = final_flow, ok = true)
end
block merge_then(merge_ii: index)
    if merge_ii >= as(index, changed_then_aux + changed_then_cnt) then
        if else_start >= 0 and changed_else_cnt > 0 then
            jump merge_els(merge_ii = as(index, changed_else_aux))
        end
        jump after_merge()
    end
    let nt: i32 = ctx.aux_i32.data[merge_ii]
    var dup: bool = false
    block dedup_1(di: index = 0, dptr: index = as(index, merged_aux))
        if dptr >= as(index, ctx.aux_i32.len) then yield dup = dup end
        if ctx.aux_i32.data[dptr] == nt then dup = true; yield dup = dup end
        jump dedup_1(di = di, dptr = dptr + as(index, 1))
    end
    if not dup then mb_ctx_push_aux_i32(ctx, nt) end
    jump merge_then(merge_ii = merge_ii + as(index, 1))
end
block merge_els(merge_ii: index)
    if merge_ii >= as(index, changed_else_aux + changed_else_cnt) then
        jump after_merge()
    end
    let nt: i32 = ctx.aux_i32.data[merge_ii]
    var dup: bool = false
    block dedup_2(di: index = 0, dptr: index = as(index, merged_aux))
        if dptr >= as(index, ctx.aux_i32.len) then yield dup = dup end
        if ctx.aux_i32.data[dptr] == nt then dup = true; yield dup = dup end
        jump dedup_2(di = di, dptr = dptr + as(index, 1))
    end
    if not dup then mb_ctx_push_aux_i32(ctx, nt) end
    jump merge_els(merge_ii = merge_ii + as(index, 1))
end
block after_merge()
    let n_changed: i32 = as(i32, ctx.aux_i32.len) - merged_aux

    -- create blocks
    let then_blk: i32 = mb_ctx_fresh_block(ctx)
    let else_blk: i32 = mb_ctx_fresh_block(ctx)
    let join_blk: i32 = mb_ctx_fresh_block(ctx)
    mb_emit_create_block(ctx, then_blk)
    mb_emit_create_block(ctx, else_blk)
    mb_emit_create_block(ctx, join_blk)

    -- For each changed binding, create a phi param on join block
    let phi_info_aux: i32 = as(i32, ctx.aux_i32.len)
    block create_phi(pi: index = 0)
        if pi >= as(index, n_changed) then yield end
        let name_tok: i32 = ctx.aux_i32.data[as(index, merged_aux) + pi]
        let env_slot: i32 = mb_env_lookup(ctx.env, name_tok)
        let scalar: i32 = select(env_slot >= 0, ctx.env.scalar[as(index, env_slot)], 0)
        let param_val: i32 = mb_ctx_fresh_value(ctx)
        mb_emit_append_block_param(ctx, join_blk, param_val, 0, scalar, 0)
        mb_ctx_push_aux_i32(ctx, name_tok)
        mb_ctx_push_aux_i32(ctx, param_val)
        mb_ctx_push_aux_i32(ctx, scalar)
        jump create_phi(pi = pi + as(index, 1))
    end

    -- conditional branch to then/else
    mb_emit_br_if(ctx, cond_val, then_blk, 0, 0, else_blk, 0, 0)
    mb_emit_seal_block(ctx, then_blk)
    mb_emit_seal_block(ctx, else_blk)

    -- lower then-body
    mb_emit_switch_to_block(ctx, then_blk)
    var then_flow: i32 = @{BackFallsThrough}
    var then_ok: bool = false
    if then_count > 0 then
        emit mb_lower_stmt_list(ctx, then_start, as(index, then_count), then_flow, then_ok)
    end
    if then_ok == false and then_count > 0 then then_flow = @{BackFallsThrough} end
    if then_flow ~= @{BackTerminates} then
        let then_args_aux: i32 = as(i32, ctx.aux_i32.len)
        block then_args(pi: index = 0)
            if pi >= as(index, n_changed) then yield end
            let name_tok: i32 = ctx.aux_i32.data[as(index, merged_aux) + pi]
            let env_slot: i32 = mb_env_lookup(ctx.env, name_tok)
            let kind: i32 = select(env_slot >= 0, ctx.env.kind[as(index, env_slot)], 0)
            if env_slot >= 0 and kind == @{MB_LOCAL_SCALAR} then
                let val: i32 = ctx.env.val[as(index, env_slot)]
                mb_ctx_push_aux_i32(ctx, val)
            else
                mb_ctx_push_aux_i32(ctx, 0)
            end
            jump then_args(pi = pi + as(index, 1))
        end
        mb_emit_jump(ctx, join_blk, then_args_aux, n_changed)
    end

    -- lower else-body (or empty else)
    mb_emit_switch_to_block(ctx, else_blk)
    var else_flow: i32 = @{BackFallsThrough}
    if else_start >= 0 and else_count > 0 then
        var else_ok: bool = false
        emit mb_lower_stmt_list(ctx, else_start, as(index, else_count), else_flow, else_ok)
        if else_ok == false then else_flow = @{BackFallsThrough} end
    end
    if else_flow ~= @{BackTerminates} then
        let else_args_aux: i32 = as(i32, ctx.aux_i32.len)
        block else_args(pi: index = 0)
            if pi >= as(index, n_changed) then yield end
            let name_tok: i32 = ctx.aux_i32.data[as(index, merged_aux) + pi]
            let env_slot: i32 = mb_env_lookup(ctx.env, name_tok)
            let kind: i32 = select(env_slot >= 0, ctx.env.kind[as(index, env_slot)], 0)
            if env_slot >= 0 and kind == @{MB_LOCAL_SCALAR} then
                let val: i32 = ctx.env.val[as(index, env_slot)]
                mb_ctx_push_aux_i32(ctx, val)
            else
                mb_ctx_push_aux_i32(ctx, 0)
            end
            jump else_args(pi = pi + as(index, 1))
        end
        mb_emit_jump(ctx, join_blk, else_args_aux, n_changed)
    end

    -- determine overall flow
    let any_falls: bool = (then_flow ~= @{BackTerminates} or else_flow ~= @{BackTerminates})
    if any_falls then
        mb_emit_seal_block(ctx, join_blk)
        mb_emit_switch_to_block(ctx, join_blk)
    end

    -- rebind env with phi values
    block rebind(pi: index = 0)
        if pi >= as(index, n_changed) then yield end
        let base: index = as(index, phi_info_aux) + pi * as(index, 3)
        let name_tok: i32 = ctx.aux_i32.data[base]
        let param_val: i32 = ctx.aux_i32.data[base + as(index, 1)]
        let scalar: i32 = ctx.aux_i32.data[base + as(index, 2)]
        mb_env_bind_scalar(ctx.env, name_tok, scalar, param_val)
        jump rebind(pi = pi + as(index, 1))
    end

    let final_flow: i32 = select(any_falls, @{BackFallsThrough}, @{BackTerminates})
    jump done(flow = final_flow, ok = true)
end
end]]

-- Verify old pattern exists
local s, e = content:find(old_if_stmt, 1, true)
if not s then
    error("Could not find old mb_lower_if_stmt pattern")
end

-- Replace
content = content:sub(1, s - 1) .. new_if_stmt_v2 .. content:sub(e + 1)

f = io.open("lua/moonlift/mom/back/stmt_lower.mlua", "w")
f:write(content)
f:close()

print("stmt_lower.mlua transformation complete")
