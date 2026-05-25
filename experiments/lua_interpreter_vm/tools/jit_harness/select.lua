-- select.lua
-- Ranks and selects winners for the runtime library
-- Per LUA_STENCIL_HARNESS_DESIGN.md §4.15

local M = {}

-- Classify a candidate as Valid, Alias, Dominated, Rare, ResearchOnly, or Invalid
function M.classify_candidate(candidate, config)
    config = config or {}

    local classification = {
        candidate_id = candidate.id or "unknown",
        class = "Unknown",
        reason = "",
        score = 0,
    }

    -- Check if valid
    if candidate.valid == false then
        classification.class = "Invalid"
        classification.reason = "Failed verification"
        return classification
    end

    -- Check if dominated (slower than smaller alternative)
    if candidate.dominated_by then
        classification.class = "Dominated"
        classification.reason = "Superseded by " .. candidate.dominated_by
        return classification
    end

    -- Check if rare (low frequency)
    if candidate.frequency and candidate.frequency < (config.min_frequency or 1) then
        classification.class = "Rare"
        classification.reason = string.format("Frequency %d below threshold", candidate.frequency)
        return classification
    end

    -- Check if research-only (valuable but not production-ready)
    if candidate.research_only then
        classification.class = "ResearchOnly"
        classification.reason = "Marked for research only"
        return classification
    end

    -- Default to Winner
    classification.class = "Winner"
    classification.score = candidate.score or 0
    return classification
end

-- Select the fastest candidate for each (opcode pattern, fact key)
function M.select_fastest_by_key(candidates, config)
    config = config or {}

    local by_key = {}
    local selections = {}

    -- Group candidates by key
    for _, cand in ipairs(candidates) do
        local key = cand.pattern_key or cand.id or "default"

        if not by_key[key] then
            by_key[key] = {}
        end

        table.insert(by_key[key], cand)
    end

    -- Select fastest from each group
    for key, cand_group in pairs(by_key) do
        local fastest = cand_group[1]

        for i = 2, #cand_group do
            if cand_group[i].cycles and fastest.cycles then
                if cand_group[i].cycles < fastest.cycles then
                    fastest = cand_group[i]
                end
            end
        end

        table.insert(selections, {
            pattern_key = key,
            selected = fastest.id or fastest.name,
            count_alternatives = #cand_group,
        })
    end

    return {
        selections = selections,
        total_selected = #selections,
    }
end

-- Build a selector table for runtime stencil matching
function M.build_selector_table(layers, config)
    config = config or {}

    local selector = {
        timestamp = os.time(),
        layers = #layers,
        entries = 0,
        by_arity = {},
        by_pattern = {},
    }

    -- Process each layer
    for layer_id, layer in ipairs(layers) do
        for _, cand in ipairs(layer.candidates or {}) do
            local arity = cand.arity or 1
            local pattern = cand.pattern_key or cand.id or "unknown"

            -- Count by arity
            selector.by_arity[arity] = (selector.by_arity[arity] or 0) + 1

            -- Count by pattern
            selector.by_pattern[pattern] = (selector.by_pattern[pattern] or 0) + 1

            selector.entries = selector.entries + 1
        end
    end

    return selector
end

-- Score candidates for selection
function M.score_for_selection(candidates, config)
    config = config or {}

    local scores = {}

    for _, cand in ipairs(candidates) do
        local score = 0

        -- Reward frequency
        if cand.frequency then
            score = score + cand.frequency * (config.frequency_weight or 10)
        end

        -- Reward small size
        if cand.size then
            score = score - cand.size * (config.size_penalty or 0.01)
        end

        -- Reward simplicity (low arity)
        if cand.arity then
            score = score - (cand.arity - 1) * (config.arity_penalty or 2)
        end

        -- Penalize holes
        if cand.holes then
            score = score - #cand.holes * (config.holes_penalty or 1)
        end

        -- Penalize relocs
        if cand.relocs then
            score = score - #cand.relocs * (config.relocs_penalty or 1)
        end

        -- Reward benchmark performance
        if cand.avg_cycles then
            score = score - cand.avg_cycles * (config.cycles_penalty or 0.1)
        end

        table.insert(scores, {
            candidate_id = cand.id or "unknown",
            score = math.max(0, score),
            frequency = cand.frequency or 0,
            size = cand.size or 0,
            arity = cand.arity or 1,
        })
    end

    -- Sort by score descending
    table.sort(scores, function(a, b) return a.score > b.score end)

    return scores
end

-- Write selector table to file
function M.write_selector_table(table, path)
    -- Simple JSON-like output
    local json_str = "{\n"
    json_str = json_str .. '  "timestamp": ' .. table.timestamp .. ",\n"
    json_str = json_str .. '  "layers": ' .. table.layers .. ",\n"
    json_str = json_str .. '  "entries": ' .. table.entries .. ",\n"
    json_str = json_str .. '  "by_arity": {\n'

    local by_arity_entries = {}
    for arity, count in pairs(table.by_arity) do
        table.insert(by_arity_entries, string.format('    "%d": %d', arity, count))
    end
    json_str = json_str .. table.concat(by_arity_entries, ",\n") .. "\n"
    json_str = json_str .. '  }\n'
    json_str = json_str .. '}\n'

    local f = io.open(path, "w")
    if not f then
        return false, "cannot write to " .. path
    end

    f:write(json_str)
    f:close()
    return true
end

-- Report selection results
function M.report_selection(scores)
    print("\n=== Selection Report ===")
    print(string.format("Ranked candidates: %d", #scores))

    if #scores > 0 then
        print("\n  Top 20 by score:")
        for i = 1, math.min(20, #scores) do
            local s = scores[i]
            print(string.format("    %2d. %s (score=%.0f, freq=%d, size=%d)",
                i, s.candidate_id, s.score, s.frequency, s.size))
        end
    end
end

return M
