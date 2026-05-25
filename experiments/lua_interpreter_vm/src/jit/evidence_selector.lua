-- Phase 3.2: Evidence-Driven Stencil Selection
-- Uses Phase 3.1 mining evidence to select and score stencils from Phase 1 library

local M = {}

-- Score a stencil against observed evidence
function M.score_stencil_against_evidence(stencil, evidence, policy)
    policy = policy or {}
    policy.op_weight = policy.op_weight or 1.0           -- weight per original op covered
    policy.frequency_weight = policy.frequency_weight or 10.0
    policy.size_penalty = policy.size_penalty or 0.5     -- penalty per byte
    policy.hole_penalty = policy.hole_penalty or 2.0
    policy.reloc_penalty = policy.reloc_penalty or 3.0
    policy.exit_penalty = policy.exit_penalty or 5.0

    if not stencil or not evidence then return 0 end

    -- How many times does this stencil's pattern appear in evidence?
    local frequency = evidence.hits or 0
    local ops_covered = stencil.ops or 1
    local expanded_cost = stencil.size or 100  -- baseline: size of expanded sequence
    local candidate_cost = stencil.size or 50  -- compound is smaller by definition
    local savings_per_hit = expanded_cost - candidate_cost

    -- Benefit: (ops saved) * (frequency) * (per-op cost reduction)
    local execution_benefit = savings_per_hit * frequency
    local static_benefit = (stencil.benefit or 0)

    -- Costs
    local code_size_cost = (stencil.size or 0) * policy.size_penalty
    local hole_cost = (stencil.holes or 0) * policy.hole_penalty
    local reloc_cost = (stencil.relocs or 0) * policy.reloc_penalty

    -- Net score
    local net_benefit = execution_benefit + static_benefit - code_size_cost - hole_cost - reloc_cost

    return {
        stencil = stencil,
        execution_benefit = execution_benefit,
        static_benefit = static_benefit,
        code_size_cost = code_size_cost,
        hole_cost = hole_cost,
        reloc_cost = reloc_cost,
        net_benefit = math.max(0, net_benefit),
        frequency = frequency,
        ops_covered = ops_covered,
        efficiency = frequency > 0 and (net_benefit / frequency) or 0,
    }
end

-- Select candidates that match evidence patterns
function M.select_candidates_for_evidence(evidence_patterns, library_indexes, policy)
    policy = policy or {}
    policy.max_arity = policy.max_arity or 4
    policy.max_depth = policy.max_depth or 3
    policy.min_frequency = policy.min_frequency or 10
    policy.min_benefit = policy.min_benefit or 0  -- accept all for now, actual filtering via Pareto

    local selected = {}
    local pattern_matches = {}

    -- For each observed pattern in evidence
    for pattern_key, ev in pairs(evidence_patterns or {}) do
        if ev.hits >= policy.min_frequency then
            -- Find stencils matching this pattern
            local ops = ev.ops or {}
            local candidates = {}
            local seen = {}

            -- Try exact sequence match
            if #ops > 0 then
                local seq_key = table.concat(ops, "|")
                local exact_stencil = library_indexes.by_op_sequence[seq_key]
                if exact_stencil then
                    table.insert(candidates, exact_stencil)
                    seen[exact_stencil.name] = true
                end
            end

            -- Try first-opcode matches (primary strategy)
            if #ops > 0 then
                local first_op = ops[1]
                -- Handle synonym mapping: "add.int" -> look up by "add"
                local lookup_op = first_op
                if first_op:match("%.") then
                    lookup_op = first_op:match("^([^.]+)")
                end

                local first_op_stencils = library_indexes.by_first_op[lookup_op] or {}
                for _, st in ipairs(first_op_stencils) do
                    if not seen[st.name] and st.arity <= policy.max_arity and (st.depth or 0) <= policy.max_depth then
                        table.insert(candidates, st)
                        seen[st.name] = true
                    end
                end
            end

            -- Score each candidate
            for _, cand in ipairs(candidates) do
                local score = M.score_stencil_against_evidence(cand, ev, policy)
                table.insert(selected, score)
                table.insert(pattern_matches, {
                    pattern = pattern_key,
                    stencil = cand.name,
                    evidence_hits = ev.hits,
                    score = score.net_benefit,
                })
            end
        end
    end

    -- Sort by net benefit
    table.sort(selected, function(a, b) return a.net_benefit > b.net_benefit end)

    return selected, pattern_matches
end

-- Apply Pareto frontier pruning
function M.pareto_frontier(scored_stencils, dimensions)
    dimensions = dimensions or {
        "net_benefit",
        "code_size_cost",
        "efficiency",
    }

    if #scored_stencils == 0 then return {} end

    local frontier = {}
    local dominated = {}

    for i, a in ipairs(scored_stencils) do
        local is_dominated = false

        for j, b in ipairs(scored_stencils) do
            if i ~= j then
                -- Check if b dominates a on all dimensions
                local b_better_on_all = true
                for _, dim in ipairs(dimensions) do
                    if not (b[dim] > a[dim]) then
                        b_better_on_all = false
                        break
                    end
                end

                if b_better_on_all then
                    is_dominated = true
                    dominated[a.stencil.name] = true
                    break
                end
            end
        end

        if not is_dominated then
            table.insert(frontier, a)
        end
    end

    table.sort(frontier, function(a, b) return a.net_benefit > b.net_benefit end)
    return frontier
end

-- Report selection results
function M.report_selection(selected, pattern_matches, round_num)
    round_num = round_num or 1

    print(string.format("\n=== Evidence-Driven Selection Round %d ===", round_num))
    print(string.format("Candidates selected: %d", #selected))

    if #pattern_matches > 0 then
        print("\nPattern matches (evidence-driven):")
        local matches_by_stencil = {}
        for _, m in ipairs(pattern_matches) do
            if not matches_by_stencil[m.stencil] then
                matches_by_stencil[m.stencil] = {count = 0, total_hits = 0}
            end
            matches_by_stencil[m.stencil].count = matches_by_stencil[m.stencil].count + 1
            matches_by_stencil[m.stencil].total_hits = matches_by_stencil[m.stencil].total_hits + m.evidence_hits
        end

        local sorted = {}
        for name, info in pairs(matches_by_stencil) do
            table.insert(sorted, {name = name, count = info.count, hits = info.total_hits})
        end
        table.sort(sorted, function(a, b) return a.hits > b.hits end)

        for i = 1, math.min(10, #sorted) do
            local m = sorted[i]
            print(string.format("  %d. %s: %d patterns, %d total hits",
                i, m.name, m.count, m.hits))
        end
    end

    if #selected > 0 then
        print("\nTop scoring stencils:")
        for i = 1, math.min(10, #selected) do
            local s = selected[i]
            print(string.format("  %d. %s: benefit=%.0f, freq=%d, cost=%d bytes",
                i, s.stencil.name, s.net_benefit, s.frequency, s.stencil.size or 0))
        end
    end
end

return M
