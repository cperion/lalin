-- Exhaustive Sequence Generator
-- Generate ALL valid bytecode sequences (pairs, triples, quads)
-- Then prune by evidence from real programs

local M = {}

-- Check if two opcodes can be sequenced (basic validity)
-- In real implementation, would check:
-- - output state of op1 compatible with input state of op2
-- - control flow allows fallthrough
-- - no semantic violations
function M.can_sequence(op1, op2)
    -- Most opcodes can sequence (for now)
    -- Some limitations:
    -- - RETURN/TAIL cannot have successor
    -- - JMP may not have normal successor
    -- - CALL is usually followed by something specific

    local no_successor = {
        "RETURN", "RETURN0", "RETURN1", "TAILCALL"
    }

    for _, ns in ipairs(no_successor) do
        if op1 == ns then
            return false
        end
    end

    return true
end

-- Generate all valid N-ary sequences from opcode list
function M.generate_nary_sequences(opcodes, n, max_size_budget)
    if n < 1 or n > 4 then
        return {}
    end

    local sequences = {}

    if n == 1 then
        -- Single opcodes are L0, not compounds
        return sequences
    end

    if n == 2 then
        -- Pairs
        for i = 1, #opcodes do
            for j = 1, #opcodes do
                if M.can_sequence(opcodes[i], opcodes[j]) then
                    local seq = {opcodes[i], opcodes[j]}
                    local name = opcodes[i] .. "|" .. opcodes[j]
                    local cost = 100  -- rough estimate: 2 ops

                    if cost <= (max_size_budget or 150) then
                        table.insert(sequences, {
                            name = name,
                            ops = seq,
                            arity = 2,
                            estimated_size = cost,
                        })
                    end
                end
            end
        end
    elseif n == 3 then
        -- Triples
        for i = 1, #opcodes do
            for j = 1, #opcodes do
                if M.can_sequence(opcodes[i], opcodes[j]) then
                    for k = 1, #opcodes do
                        if M.can_sequence(opcodes[j], opcodes[k]) then
                            local seq = {opcodes[i], opcodes[j], opcodes[k]}
                            local name = opcodes[i] .. "|" .. opcodes[j] .. "|" .. opcodes[k]
                            local cost = 150  -- rough estimate: 3 ops

                            if cost <= (max_size_budget or 250) then
                                table.insert(sequences, {
                                    name = name,
                                    ops = seq,
                                    arity = 3,
                                    estimated_size = cost,
                                })
                            end
                        end
                    end
                end
            end
        end
    elseif n == 4 then
        -- Quads
        for i = 1, #opcodes do
            for j = 1, #opcodes do
                if M.can_sequence(opcodes[i], opcodes[j]) then
                    for k = 1, #opcodes do
                        if M.can_sequence(opcodes[j], opcodes[k]) then
                            for l = 1, #opcodes do
                                if M.can_sequence(opcodes[k], opcodes[l]) then
                                    local seq = {opcodes[i], opcodes[j], opcodes[k], opcodes[l]}
                                    local name = opcodes[i] .. "|" .. opcodes[j] .. "|" .. opcodes[k] .. "|" .. opcodes[l]
                                    local cost = 200  -- rough estimate: 4 ops

                                    if cost <= (max_size_budget or 350) then
                                        table.insert(sequences, {
                                            name = name,
                                            ops = seq,
                                            arity = 4,
                                            estimated_size = cost,
                                        })
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    return sequences
end

-- Generate all valid sequences up to max_arity
function M.generate_all_valid_sequences(opcodes, max_arity, size_budgets)
    size_budgets = size_budgets or {150, 250, 350}

    local all_sequences = {}

    for arity = 2, math.min(max_arity, 4) do
        local seqs = M.generate_nary_sequences(opcodes, arity, size_budgets[arity] or 350)
        for _, seq in ipairs(seqs) do
            table.insert(all_sequences, seq)
        end
    end

    return all_sequences
end

-- Prune sequences by evidence
function M.prune_by_evidence(candidates, evidence, policy)
    policy = policy or {}
    policy.min_frequency = policy.min_frequency or 1  -- any observed
    policy.pareto_dimensions = policy.pareto_dimensions or {"observed", "arity"}

    local pruned = {}

    for _, cand in ipairs(candidates) do
        local cand_key = cand.name
        local ev = evidence[cand_key]

        if ev and ev.hits >= policy.min_frequency then
            table.insert(pruned, {
                sequence = cand,
                evidence_hits = ev.hits,
                frequency_weight = ev.hits / 1000,  -- normalize
            })
        end
    end

    return pruned
end

-- Score sequences for promotion
function M.score_for_promotion(pruned_sequences, policy)
    policy = policy or {}
    policy.size_penalty = policy.size_penalty or 0.1
    policy.arity_penalty = policy.arity_penalty or 2.0  -- prefer simpler

    local scored = {}

    for _, item in ipairs(pruned_sequences) do
        local cand = item.sequence
        local freq = item.evidence_hits or 1

        -- Score: frequency - (size penalty) - (arity penalty)
        local score = freq
            - (cand.estimated_size or 100) * policy.size_penalty
            - (cand.arity or 1) * policy.arity_penalty

        table.insert(scored, {
            sequence = cand,
            evidence_hits = item.evidence_hits,
            score = math.max(0, score),
        })
    end

    -- Sort by score (descending)
    table.sort(scored, function(a, b) return a.score > b.score end)

    return scored
end

-- Report generation results
function M.report_generation(all_candidates, pruned, scored, max_promote)
    print("\n=== Exhaustive Sequence Generation & Pruning ===")

    print(string.format("\nGenerated candidates: %d", #all_candidates))

    local by_arity = {}
    for _, cand in ipairs(all_candidates) do
        by_arity[cand.arity] = (by_arity[cand.arity] or 0) + 1
    end

    for arity = 2, 4 do
        if by_arity[arity] then
            print(string.format("  Arity %d: %d candidates", arity, by_arity[arity]))
        end
    end

    print(string.format("\nAfter evidence pruning: %d survivors", #pruned))

    if #pruned > 0 then
        print(string.format("\nTop 10 by evidence frequency:")
        for i = 1, math.min(10, #pruned) do
            local p = pruned[i]
            print(string.format("  %d. %s: %d hits", i, p.sequence.name, p.evidence_hits))
        end
    end

    print(string.format("\nAfter scoring: %d ranked candidates", #scored))

    if #scored > 0 then
        print(string.format("\nTop 10 by promotion score:")
        for i = 1, math.min(10, #scored) do
            local s = scored[i]
            print(string.format("  %d. %s: score=%.0f, freq=%d",
                i, s.sequence.name, s.score, s.evidence_hits))
        end
    end

    print(string.format("\nPromoting top %d for L1 library", math.min(max_promote or 20, #scored)))
end

return M
