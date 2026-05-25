-- Phase 3.2 (continued): Stencil Closure Round Builder
-- Implements bounded-arity closure: compose selected stencils into larger compounds
-- L0 + evidence -> select atoms -> compose to L1 -> select from L1 -> compose to L2, etc.

local M = {}

-- Determine if two stencils can compose (semantically compatible)
function M.can_compose(a, b, policy)
    policy = policy or {}
    policy.max_total_ops = policy.max_total_ops or 64
    policy.max_total_size = policy.max_total_size or 400
    policy.max_holes = policy.max_holes or 20
    policy.max_relocs = policy.max_relocs or 15

    if not a or not b then return false end

    local total_ops = (a.ops or 0) + (b.ops or 0)
    local total_size = (a.size or 0) + (b.size or 0)
    local total_holes = (a.holes or 0) + (b.holes or 0)
    local total_relocs = (a.relocs or 0) + (b.relocs or 0)

    -- Hard gates
    if total_ops > policy.max_total_ops then return false end
    if total_size > policy.max_total_size then return false end
    if total_holes > policy.max_holes then return false end
    if total_relocs > policy.max_relocs then return false end

    return true
end

-- Compose two stencils into a candidate compound
function M.compose_stencils(a, b, policy)
    policy = policy or {}

    if not M.can_compose(a, b, policy) then
        return nil
    end

    local compound = {
        name = "comp_" .. (a.name or "?"):match("[%w_]+") .. "_" .. (b.name or "?"):match("[%w_]+"),
        is_compound = true,
        is_promotion_candidate = true,
        ops = (a.ops or 0) + (b.ops or 0),
        size = (a.size or 0) + (b.size or 0),
        holes = (a.holes or 0) + (b.holes or 0),
        relocs = (a.relocs or 0) + (b.relocs or 0),
        arity = math.min((a.arity or 1) + (b.arity or 1), policy.max_arity or 4),
        depth = math.max((a.depth or 0), (b.depth or 0)) + 1,
        first_op = a.first_op or b.first_op,
        components = {a.name, b.name},
        expanded_cost = (a.size or 0) + (b.size or 0),
        estimated_benefit = (a.benefit or 0) + (b.benefit or 0),
    }

    -- Rough benefit estimation: composition saves overhead if code is smaller
    compound.benefit = math.max(0, compound.expanded_cost - compound.size - 20)

    return compound
end

-- Generate closure round candidates
function M.generate_closure_candidates(atoms, evidence, policy)
    policy = policy or {}
    policy.max_arity = policy.max_arity or 4
    policy.max_depth = policy.max_depth or 3
    policy.only_observed_motifs = policy.only_observed_motifs or true

    local candidates = {}
    local seen = {}

    -- Sort atoms by benefit for greedy composition
    local sorted_atoms = {}
    for _, atom in ipairs(atoms) do
        table.insert(sorted_atoms, atom)
    end
    table.sort(sorted_atoms, function(a, b) return (a.benefit or 0) > (b.benefit or 0) end)

    -- Generate pairs and triples from atoms
    for i = 1, math.min(#sorted_atoms, 20) do  -- limit to top atoms for performance
        for j = i + 1, math.min(#sorted_atoms, 20) do
            local a = sorted_atoms[i]
            local b = sorted_atoms[j]

            if M.can_compose(a, b, policy) then
                local compound = M.compose_stencils(a, b, policy)
                if compound then
                    local key = compound.name
                    if not seen[key] then
                        seen[key] = true
                        table.insert(candidates, compound)
                    end
                end
            end
        end
    end

    return candidates
end

-- Build StencilPattern index for runtime selector
function M.build_pattern_library(selected_stencils, policy)
    policy = policy or {}
    policy.index_by_first_op = policy.index_by_first_op ~= false

    local patterns = {}
    local id = 1

    for _, st in ipairs(selected_stencils) do
        if st.name then
            local pattern = {
                id = id,
                name = st.name,
                ops = st.ops or 1,
                size = st.size or 50,
                holes = st.holes or 0,
                relocs = st.relocs or 0,
                benefit = st.benefit or 0,
                arity = st.arity or 1,
                depth = st.depth or 0,
                first_op = st.first_op or "unknown",
                score = (st.benefit or 0) + (st.ops or 0) * 10,  -- higher is better
                is_primitive = st.is_primitive or false,
                is_compound = st.is_compound or false,
            }
            table.insert(patterns, pattern)
            id = id + 1
        end
    end

    -- Sort by score for runtime matching preference
    table.sort(patterns, function(a, b) return a.score > b.score end)

    return patterns
end

-- Rank closure candidates by evidence relevance
function M.rank_candidates_by_evidence(candidates, evidence_patterns)
    local ranked = {}

    for _, cand in ipairs(candidates) do
        local match_count = 0
        local total_hits = 0

        -- Count how many evidence patterns this candidate might help
        for pattern_key, ev in pairs(evidence_patterns or {}) do
            if ev.hits then
                -- Very rough: check if first op matches
                if ev.ops and ev.ops[1] and ev.ops[1]:match(cand.first_op or "") then
                    match_count = match_count + 1
                    total_hits = total_hits + ev.hits
                end
            end
        end

        table.insert(ranked, {
            candidate = cand,
            evidence_matches = match_count,
            total_evidence_hits = total_hits,
            potential_benefit = total_hits * (cand.benefit or 0),
        })
    end

    table.sort(ranked, function(a, b)
        return a.potential_benefit > b.potential_benefit
    end)

    return ranked
end

-- Report closure round results
function M.report_closure_round(round_num, atoms, candidates, selected, policy)
    print(string.format("\n=== Closure Round %d ===", round_num))
    print(string.format("Input atoms: %d", #atoms))

    local by_arity = {}
    for _, a in ipairs(atoms) do
        local ar = a.arity or 1
        by_arity[ar] = (by_arity[ar] or 0) + 1
    end
    print("Input atoms by arity:")
    for ar = 1, 4 do
        if by_arity[ar] then
            print(string.format("  Arity %d: %d atoms", ar, by_arity[ar]))
        end
    end

    print(string.format("\nGenerated candidates: %d", #candidates))
    if #candidates > 0 then
        print("Top 5 candidates:")
        local sorted = {}
        for _, c in ipairs(candidates) do
            table.insert(sorted, c)
        end
        table.sort(sorted, function(a, b) return (a.benefit or 0) > (b.benefit or 0) end)
        for i = 1, math.min(5, #sorted) do
            local c = sorted[i]
            print(string.format("  %d. %s: ops=%d, size=%d, benefit=%.0f",
                i, c.name, c.ops or 0, c.size or 0, c.benefit or 0))
        end
    end

    print(string.format("\nSelected from candidates: %d", #selected))
    if #selected > 0 then
        print("Top 5 selected:")
        for i = 1, math.min(5, #selected) do
            local s = selected[i]
            print(string.format("  %d. %s: potential_benefit=%.0f, evidence_matches=%d",
                i, s.candidate.name, s.potential_benefit, s.evidence_matches))
        end
    end
end

return M
