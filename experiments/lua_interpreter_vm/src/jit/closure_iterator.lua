-- Phase 3.2: Stencil Closure Iterator
-- Evidence-driven iterative promotion of stencil candidates
-- Implements bounded-arity closure from real program traces

local tracer = require("experiments.lua_interpreter_vm.src.jit.program_tracer")

local M = {}

-- Analyze recorded traces to identify promotable patterns
function M.analyze_trace_patterns(evidence, min_hits)
    min_hits = min_hits or 50

    local patterns = {}
    for key, ev in pairs(evidence.patterns or {}) do
        if ev.hits >= min_hits then
            table.insert(patterns, {
                key = key,
                ops = ev.ops,
                hits = ev.hits,
                arity = #ev.ops,
                guard_count = ev.guard_count or 0,
                exit_count = ev.exit_count or 0,
            })
        end
    end

    table.sort(patterns, function(a, b) return a.hits > b.hits end)
    return patterns
end

-- Group patterns by arity
function M.group_by_arity(patterns)
    local groups = {}
    for _, p in ipairs(patterns) do
        local arity = p.arity
        if not groups[arity] then
            groups[arity] = {}
        end
        table.insert(groups[arity], p)
    end

    return groups
end

-- Identify which arities are most valuable
function M.rank_arities_by_value(arity_groups, max_arity)
    local rankings = {}

    for arity = 1, max_arity do
        local patterns = arity_groups[arity] or {}
        local total_hits = 0
        local pattern_count = 0

        for _, p in ipairs(patterns) do
            total_hits = total_hits + p.hits
            pattern_count = pattern_count + 1
        end

        table.insert(rankings, {
            arity = arity,
            pattern_count = pattern_count,
            total_hits = total_hits,
            avg_hits = pattern_count > 0 and (total_hits / pattern_count) or 0,
            value = total_hits * pattern_count,  -- total coverage
        })
    end

    table.sort(rankings, function(a, b) return a.value > b.value end)
    return rankings
end

-- Select candidates for next promotion round
-- Based on: arity, frequency, coverage, risk (guards/exits)
function M.select_promotion_candidates(patterns, max_arity, max_per_arity)
    max_per_arity = max_per_arity or 10
    local candidates = {}

    -- Group by arity
    local by_arity = M.group_by_arity(patterns)

    -- For each arity up to max_arity
    for arity = 1, max_arity do
        local arity_patterns = by_arity[arity] or {}

        -- Rank by hits (more hits = better evidence)
        local ranked = {}
        for _, p in ipairs(arity_patterns) do
            local score = p.hits - (p.guard_count * 5) - (p.exit_count * 10)
            table.insert(ranked, {
                pattern = p,
                score = math.max(0, score),
            })
        end

        table.sort(ranked, function(a, b) return a.score > b.score end)

        -- Take top K for this arity
        for i = 1, math.min(max_per_arity, #ranked) do
            table.insert(candidates, {
                arity = arity,
                pattern = ranked[i].pattern,
                evidence_score = ranked[i].score,
                confidence = ranked[i].pattern.hits / 1000,  -- rough estimate
            })
        end
    end

    return candidates
end

-- Estimate cost of materializing a candidate
function M.estimate_materialization_cost(pattern)
    local base_cost = 10  -- Copy/stamp/fixup per stencil
    local arity_cost = pattern.arity * 5  -- Cost per operation
    local guard_cost = pattern.guard_count * 3
    local exit_cost = pattern.exit_count * 4

    return base_cost + arity_cost + guard_cost + exit_cost
end

-- Estimate benefit of promoting a candidate
function M.estimate_promotion_benefit(pattern, current_lib_size)
    -- Benefit = how much hot execution time this would save
    local hot_ops_saved = pattern.arity  -- number of operations combined
    local frequency = pattern.hits
    local ops_per_execution = 10  -- rough: cost to execute one op

    local benefit = hot_ops_saved * frequency * ops_per_execution
    local cost = M.estimate_materialization_cost(pattern)
    local library_size_penalty = current_lib_size * 0.01  -- penalty for library growth

    return math.max(0, benefit - cost - library_size_penalty)
end

-- Filter candidates by viability
function M.filter_viable_candidates(candidates, policy)
    policy = policy or {}
    policy.max_arity = policy.max_arity or 4
    policy.max_guards = policy.max_guards or 3
    policy.max_exits = policy.max_exits or 2
    policy.min_confidence = policy.min_confidence or 0.05
    policy.min_benefit = policy.min_benefit or 50

    local viable = {}
    for _, cand in ipairs(candidates) do
        local p = cand.pattern
        local cost = M.estimate_materialization_cost(p)
        local benefit = M.estimate_promotion_benefit(p, 56)  -- current lib size from Phase 1

        local valid = true
        if cand.arity > policy.max_arity then valid = false end
        if p.guard_count > policy.max_guards then valid = false end
        if p.exit_count > policy.max_exits then valid = false end
        if cand.confidence < policy.min_confidence then valid = false end
        if benefit < policy.min_benefit then valid = false end

        if valid then
            table.insert(viable, {
                arity = cand.arity,
                pattern = p,
                evidence_score = cand.evidence_score,
                confidence = cand.confidence,
                materialization_cost = cost,
                estimated_benefit = benefit,
            })
        end
    end

    return viable
end

-- Report on a closure iteration
function M.report_closure_round(round_num, patterns, candidates, viable)
    print(string.format("\n=== Closure Round %d ===", round_num))
    print(string.format("Input patterns: %d", #patterns))

    local by_arity = M.group_by_arity(patterns)
    print("Pattern distribution by arity:")
    for arity = 1, 4 do
        local count = #(by_arity[arity] or {})
        if count > 0 then
            print(string.format("  Arity %d: %d patterns", arity, count))
        end
    end

    print(string.format("\nCandidates selected: %d", #candidates))
    print(string.format("Viable after filtering: %d", #viable))

    if #viable > 0 then
        print("\nTop 5 viable candidates:")
        local sorted = {}
        for _, v in ipairs(viable) do
            table.insert(sorted, v)
        end
        table.sort(sorted, function(a, b)
            return a.estimated_benefit > b.estimated_benefit
        end)

        for i = 1, math.min(5, #sorted) do
            local v = sorted[i]
            print(string.format("  %d. Arity %d, confidence %.0f%%, benefit %.0f",
                i, v.arity, v.confidence * 100, v.estimated_benefit))
        end
    end
end

return M
