-- Phase 3.1: Real Lua Program Tracer
-- Mines real Lua programs to extract opcode patterns and evidence

local moon = require("moonlift")
local const = require("experiments.lua_interpreter_vm.src.constants")

local M = {}

-- Opcode statistics factory
function M.new_op_stats()
    local stats = {
        op_counts = {},
        op_sequence_counts = {},
        total_ops = 0,
        total_sequences = 0,
    }

    function stats:record_op(op_name)
        if not op_name then return end
        self.op_counts[op_name] = (self.op_counts[op_name] or 0) + 1
        self.total_ops = self.total_ops + 1
    end

    function stats:record_sequence(ops)
        if not ops or #ops == 0 then return end
        local seq_key = table.concat(ops, ",")
        self.op_sequence_counts[seq_key] = (self.op_sequence_counts[seq_key] or 0) + 1
        self.total_sequences = self.total_sequences + 1
    end

    function stats:top_ops(limit)
        local sorted = {}
        for op, count in pairs(self.op_counts) do
            table.insert(sorted, {op, count})
        end
        table.sort(sorted, function(a, b) return a[2] > b[2] end)

        local result = {}
        for i = 1, math.min(limit, #sorted) do
            result[i] = sorted[i]
        end
        return result
    end

    function stats:top_sequences(limit)
        local sorted = {}
        for seq, count in pairs(self.op_sequence_counts) do
            table.insert(sorted, {seq, count})
        end
        table.sort(sorted, function(a, b) return a[2] > b[2] end)

        local result = {}
        for i = 1, math.min(limit, #sorted) do
            result[i] = sorted[i]
        end
        return result
    end

    function stats:dump_report()
        print("\n=== OPCODE STATISTICS ===")
        print(string.format("Total operations: %d", self.total_ops))
        print(string.format("Total sequences: %d\n", self.total_sequences))

        print("Top 20 Most Frequent Operations:")
        for i, item in ipairs(self:top_ops(20)) do
            local op, count = item[1], item[2]
            local pct = (count / self.total_ops) * 100
            print(string.format("  %2d. %s: %d (%.1f%%)", i, op, count, pct))
        end

        print("\nTop 20 Most Frequent Operation Sequences:")
        for i, item in ipairs(self:top_sequences(20)) do
            local seq, count = item[1], item[2]
            local pct = (count / self.total_sequences) * 100
            print(string.format("  %2d. %s: %d (%.1f%%)", i, seq, count, pct))
        end
    end

    return stats
end

-- Opcode name lookup
function M.opcode_name(op_num)
    if type(op_num) == "string" then return op_num end
    for name, num in pairs(const.Op) do
        if num == op_num then return name end
    end
    return "UNKNOWN"
end

-- Hot loop detection factory
function M.new_hot_loop_detector(hot_threshold)
    local detector = {
        hot_threshold = hot_threshold or 100,
        loop_entries = {},
        hot_loops = {},
        threshold = hot_threshold or 100,
    }

    function detector:tick(pc)
        if not pc then return false end
        self.loop_entries[pc] = (self.loop_entries[pc] or 0) + 1
        local count = self.loop_entries[pc]
        if count >= self.threshold and not self.hot_loops[pc] then
            self.hot_loops[pc] = true
            return true
        end
        return false
    end

    function detector:is_hot(pc)
        return self.hot_loops[pc] or false
    end

    function detector:report()
        print("\n=== HOT LOOP DETECTION ===")
        local hot_pcs = {}
        for pc, count in pairs(self.loop_entries) do
            if self.hot_loops[pc] then
                table.insert(hot_pcs, {pc, count})
            end
        end
        table.sort(hot_pcs, function(a, b) return a[2] > b[2] end)

        print(string.format("Hot loops detected: %d\n", #hot_pcs))
        for i, item in ipairs(hot_pcs) do
            local pc, count = item[1], item[2]
            print(string.format("  %2d. PC=%d: %d iterations", i, pc, count))
        end
    end

    return detector
end

-- Pattern evidence builder factory
function M.new_pattern_evidence()
    local evidence = {
        patterns = {},
    }

    function evidence:record_pattern(pattern_key, ops, hits, guard_count, exit_count)
        if not self.patterns[pattern_key] then
            self.patterns[pattern_key] = {
                key = pattern_key,
                ops = ops or {},
                hits = hits or 1,
                guard_count = guard_count or 0,
                exit_count = exit_count or 0,
            }
        else
            self.patterns[pattern_key].hits = self.patterns[pattern_key].hits + (hits or 1)
        end
    end

    function evidence:candidates_for_promotion(min_hits)
        min_hits = min_hits or 50
        local candidates = {}

        for key, ev in pairs(self.patterns) do
            if ev.hits >= min_hits then
                table.insert(candidates, ev)
            end
        end

        table.sort(candidates, function(a, b) return a.hits > b.hits end)
        return candidates
    end

    function evidence:report()
        local pattern_count = 0
        for _ in pairs(self.patterns) do pattern_count = pattern_count + 1 end

        print("\n=== PATTERN EVIDENCE ===")
        print(string.format("Total patterns observed: %d\n", pattern_count))

        local candidates = self:candidates_for_promotion(50)
        print(string.format("Promotion candidates (>= 50 hits): %d\n", #candidates))

        for i = 1, math.min(10, #candidates) do
            local ev = candidates[i]
            print(string.format("  %2d. %s: %d hits", i, ev.key, ev.hits))
        end
    end

    return evidence
end

return M
