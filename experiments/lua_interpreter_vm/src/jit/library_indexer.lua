-- Phase 3.2: Stencil Library Loader and Indexer
-- Loads Phase 1 promotion plan, builds runtime indexes for pattern matching

local M = {}

-- Build library from hardcoded Phase 1 results
-- (In production, would load from promotion_plan.json with proper JSON parser)
function M.load_library()
    local library = {
        stencils = {},
    }

    -- Primitives (11 from Phase 1)
    local primitives = {
        {name = "value.load_i64.imm_to_sA.fall", is_primitive = true, ops = 3, size = 46, holes = 4, relocs = 0, benefit = 0, arity = 1, depth = 0, first_op = "load"},
        {name = "project.slot.value_regs_to_slot", is_primitive = true, ops = 1, size = 46, holes = 6, relocs = 0, benefit = 0, arity = 1, depth = 0, first_op = "project"},
        {name = "value.move.sB_to_sA.fall", is_primitive = true, ops = 3, size = 49, holes = 6, relocs = 0, benefit = 0, arity = 1, depth = 0, first_op = "move"},
        {name = "guard.int.sA.next_or_exit", is_primitive = true, ops = 2, size = 41, holes = 1, relocs = 1, benefit = 0, arity = 1, depth = 0, first_op = "guard"},
        {name = "arith.add_int_known.sB_sC_to_sA.fall", is_primitive = true, ops = 5, size = 50, holes = 5, relocs = 0, benefit = 0, arity = 1, depth = 0, first_op = "add"},
        {name = "arith.add_i64_guarded.sB_sC_to_sA.next_or_exit", is_primitive = true, ops = 7, size = 100, holes = 7, relocs = 1, benefit = 0, arity = 1, depth = 0, first_op = "add"},
        {name = "arith.addi_i64_guarded.sB_imm_to_sA.next_or_exit", is_primitive = true, ops = 6, size = 82, holes = 6, relocs = 1, benefit = 0, arity = 1, depth = 0, first_op = "addi"},
        {name = "cmp.lt_i64_guarded.sB_sC.true_or_false_or_exit", is_primitive = true, ops = 6, size = 103, holes = 4, relocs = 3, benefit = 0, arity = 1, depth = 0, first_op = "cmp"},
        {name = "branch.truthy.sA.true_or_false", is_primitive = true, ops = 3, size = 72, holes = 1, relocs = 2, benefit = 0, arity = 1, depth = 0, first_op = "branch"},
        {name = "projection.interpreter.live_slots", is_primitive = true, ops = 1, size = 46, holes = 6, relocs = 0, benefit = 0, arity = 1, depth = 0, first_op = "projection"},
        {name = "edge.jump_indirect.target", is_primitive = true, ops = 2, size = 12, holes = 0, relocs = 0, benefit = 0, arity = 1, depth = 0, first_op = "edge"},
    }

    -- Sample compounds (selection from 64 promoted)
    -- In real execution, these would be extracted from promotion_plan.json
    local compounds = {
        {name = "compound.cb20d5f5", is_compound = true, ops = 26, size = 327, holes = 18, relocs = 8, benefit = 253, arity = 4, depth = 1, first_op = "add"},
        {name = "compound.8a5a6eb0", is_compound = true, ops = 26, size = 327, holes = 18, relocs = 8, benefit = 253, arity = 4, depth = 1, first_op = "add"},
        {name = "compound.24b1fef9", is_compound = true, ops = 25, size = 311, holes = 17, relocs = 7, benefit = 249, arity = 4, depth = 1, first_op = "guard"},
        {name = "compound.0f862530", is_compound = true, ops = 24, size = 316, holes = 16, relocs = 7, benefit = 244, arity = 4, depth = 1, first_op = "load"},
        {name = "compound.b2376930", is_compound = true, ops = 23, size = 298, holes = 15, relocs = 6, benefit = 242, arity = 4, depth = 1, first_op = "move"},
    }

    for _, p in ipairs(primitives) do
        table.insert(library.stencils, p)
    end
    for _, c in ipairs(compounds) do
        table.insert(library.stencils, c)
    end

    return library
end

-- Build runtime indexes for fast stencil selection
function M.build_indexes(library)
    local indexes = {
        by_first_op = {},      -- op_name -> {stencil1, stencil2, ...}
        by_arity = {},         -- arity -> {stencil1, stencil2, ...}
        by_depth = {},         -- depth -> {stencil1, stencil2, ...}
        by_op_sequence = {},   -- "op1|op2|op3" -> stencil
        by_name = {},          -- name -> stencil
    }

    for _, st in ipairs(library.stencils) do
        if st.name then
            -- Index by name
            indexes.by_name[st.name] = st

            -- Index by first opcode
            if st.first_op then
                if not indexes.by_first_op[st.first_op] then
                    indexes.by_first_op[st.first_op] = {}
                end
                table.insert(indexes.by_first_op[st.first_op], st)
            end

            -- Index by arity
            if st.arity then
                if not indexes.by_arity[st.arity] then
                    indexes.by_arity[st.arity] = {}
                end
                table.insert(indexes.by_arity[st.arity], st)
            end

            -- Index by depth
            if st.depth then
                if not indexes.by_depth[st.depth] then
                    indexes.by_depth[st.depth] = {}
                end
                table.insert(indexes.by_depth[st.depth], st)
            end

            -- Index by op sequence
            if st.op_sequence and #st.op_sequence > 0 then
                local seq_key = table.concat(st.op_sequence, "|")
                indexes.by_op_sequence[seq_key] = st
            end
        end
    end

    -- Sort by benefit within each index for greedy matching
    for op, stencils in pairs(indexes.by_first_op) do
        table.sort(stencils, function(a, b)
            return (a.benefit or 0) > (b.benefit or 0)
        end)
    end

    return indexes
end

-- Query stencils matching evidence pattern
function M.candidates_for_pattern(indexes, ops, max_arity)
    max_arity = max_arity or 4
    local candidates = {}

    if not ops or #ops == 0 then return candidates end

    local first_op = ops[1]
    local seq_key = table.concat(ops, "|")

    -- Direct sequence match (highest priority)
    local exact = indexes.by_op_sequence[seq_key]
    if exact then
        table.insert(candidates, {
            stencil = exact,
            match_type = "exact_sequence",
            confidence = 1.0,
        })
    end

    -- First-opcode matches (fallback)
    local by_first = indexes.by_first_op[first_op] or {}
    for _, st in ipairs(by_first) do
        if st.arity and st.arity <= max_arity then
            -- Skip if already added as exact match
            if not exact or st.name ~= exact.name then
                table.insert(candidates, {
                    stencil = st,
                    match_type = "first_op",
                    confidence = 0.7,
                })
            end
        end
    end

    return candidates
end

-- Summarize library composition
function M.report_library(library, indexes)
    print("\n=== STENCIL LIBRARY SUMMARY ===")
    print(string.format("Total stencils: %d", #library.stencils))

    local primitives = 0
    local compounds = 0
    local total_size = 0
    local total_benefit = 0

    for _, st in ipairs(library.stencils) do
        if st.is_primitive then primitives = primitives + 1 end
        if st.is_compound then compounds = compounds + 1 end
        total_size = total_size + (st.size or 0)
        total_benefit = total_benefit + (st.benefit or 0)
    end

    print(string.format("Primitives: %d", primitives))
    print(string.format("Compounds: %d", compounds))
    print(string.format("Total code size: %d bytes", total_size))
    print(string.format("Total benefit: %.0f", total_benefit))

    print("\nArities:")
    for arity = 1, 5 do
        local count = (indexes.by_arity[arity] and #indexes.by_arity[arity]) or 0
        if count > 0 then
            print(string.format("  Arity %d: %d stencils", arity, count))
        end
    end

    print("\nFirst opcodes:")
    local first_ops = {}
    for op, _ in pairs(indexes.by_first_op) do
        table.insert(first_ops, op)
    end
    table.sort(first_ops)
    for _, op in ipairs(first_ops) do
        local count = #indexes.by_first_op[op]
        print(string.format("  %s: %d stencils", op, count))
    end
end

return M
