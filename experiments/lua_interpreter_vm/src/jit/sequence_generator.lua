-- Sequence Generator: All Valid → Pruned by Cost → Ranked by Evidence
-- Per STENCIL_LIBRARY.md §7 and JIT_DESIGN.md §3.5

local M = {}

-- Budget constraints (hard rejection gates)
M.BUDGET = {
    max_arity = 4,
    max_total_size = 450,  -- bytes of code
    max_holes = 25,
    max_relocs = 20,
}

-- Opcodes that cannot have a successor (terminating)
local TERMINATING = {
    RETURN = true,
    RETURN0 = true,
    RETURN1 = true,
    TAILCALL = true,
}

-- Check if op1 can be followed by op2
local function can_sequence(op1, op2)
    if TERMINATING[op1] then
        return false
    end
    return true
end

-- Estimate cost of an opcode sequence
local function estimate_cost(opcodes)
    local ops_count = #opcodes
    local size = 50 * ops_count  -- rough: 50 bytes per opcode
    local holes = 2 * ops_count  -- rough: 2 holes per opcode
    local relocs = 1 * ops_count -- rough: 1 reloc per opcode

    return {
        size = size,
        holes = holes,
        relocs = relocs,
    }
end

-- Check if sequence meets budget constraints
local function meets_budget(cost)
    return cost.size <= M.BUDGET.max_total_size
        and cost.holes <= M.BUDGET.max_holes
        and cost.relocs <= M.BUDGET.max_relocs
end

-- Generate all pairs of opcodes that can sequence
function M.generate_pairs(opcodes)
    local pairs = {}

    for i = 1, #opcodes do
        for j = 1, #opcodes do
            local op1, op2 = opcodes[i], opcodes[j]

            if can_sequence(op1, op2) then
                local cost = estimate_cost({op1, op2})

                if meets_budget(cost) then
                    table.insert(pairs, {
                        name = op1 .. "|" .. op2,
                        ops = {op1, op2},
                        arity = 2,
                        cost = cost,
                    })
                end
            end
        end
    end

    return pairs
end

-- Generate all triples that can sequence
function M.generate_triples(opcodes)
    local triples = {}

    for i = 1, #opcodes do
        for j = 1, #opcodes do
            if not can_sequence(opcodes[i], opcodes[j]) then
                goto next_pair
            end

            for k = 1, #opcodes do
                if not can_sequence(opcodes[j], opcodes[k]) then
                    goto next_triple
                end

                local cost = estimate_cost({opcodes[i], opcodes[j], opcodes[k]})

                if meets_budget(cost) then
                    table.insert(triples, {
                        name = opcodes[i] .. "|" .. opcodes[j] .. "|" .. opcodes[k],
                        ops = {opcodes[i], opcodes[j], opcodes[k]},
                        arity = 3,
                        cost = cost,
                    })
                end

                ::next_triple::
            end

            ::next_pair::
        end
    end

    return triples
end

-- Generate all quads that can sequence
function M.generate_quads(opcodes)
    local quads = {}

    for i = 1, #opcodes do
        for j = 1, #opcodes do
            if not can_sequence(opcodes[i], opcodes[j]) then
                goto next_pair2
            end

            for k = 1, #opcodes do
                if not can_sequence(opcodes[j], opcodes[k]) then
                    goto next_triple2
                end

                for l = 1, #opcodes do
                    if not can_sequence(opcodes[k], opcodes[l]) then
                        goto next_quad
                    end

                    local cost = estimate_cost({opcodes[i], opcodes[j], opcodes[k], opcodes[l]})

                    if meets_budget(cost) then
                        table.insert(quads, {
                            name = opcodes[i] .. "|" .. opcodes[j] .. "|" .. opcodes[k] .. "|" .. opcodes[l],
                            ops = {opcodes[i], opcodes[j], opcodes[k], opcodes[l]},
                            arity = 4,
                            cost = cost,
                        })
                    end

                    ::next_quad::
                end

                ::next_triple2::
            end

            ::next_pair2::
        end
    end

    return quads
end

-- Generate all valid sequences (arities 2-4)
function M.generate_all(opcodes)
    local all = {}

    local pairs = M.generate_pairs(opcodes)
    for _, p in ipairs(pairs) do
        table.insert(all, p)
    end

    local triples = M.generate_triples(opcodes)
    for _, t in ipairs(triples) do
        table.insert(all, t)
    end

    local quads = M.generate_quads(opcodes)
    for _, q in ipairs(quads) do
        table.insert(all, q)
    end

    return all
end

-- Rank sequences by evidence
-- benefit = evidence_hits * (expanded_cost - candidate_cost) - taxes
function M.rank_by_evidence(sequences, evidence, policy)
    policy = policy or {}
    policy.code_size_tax = policy.code_size_tax or 0.1
    policy.materialization_tax = policy.materialization_tax or 5

    local ranked = {}

    for _, seq in ipairs(sequences) do
        local ev = evidence[seq.name]
        if not ev then
            goto next_seq
        end

        local hits = ev.hits or 1
        local expanded_cost = 50 * seq.arity  -- rough baseline
        local candidate_cost = seq.cost.size
        local execution_benefit = hits * (expanded_cost - candidate_cost)
        local code_tax = seq.cost.size * policy.code_size_tax
        local net_benefit = execution_benefit - code_tax - policy.materialization_tax

        if net_benefit > 0 then
            table.insert(ranked, {
                sequence = seq,
                evidence_hits = hits,
                execution_benefit = execution_benefit,
                code_tax = code_tax,
                net_benefit = net_benefit,
            })
        end

        ::next_seq::
    end

    table.sort(ranked, function(a, b)
        return a.net_benefit > b.net_benefit
    end)

    return ranked
end

return M
