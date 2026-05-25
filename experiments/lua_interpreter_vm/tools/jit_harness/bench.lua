-- bench.lua
-- Benchmarks candidates and layers
-- Per LUA_STENCIL_HARNESS_DESIGN.md §4.14

local M = {}

-- Benchmark a candidate against a corpus
function M.benchmark_candidate(candidate, config)
    config = config or {}

    local result = {
        candidate_id = candidate.id or "unknown",
        timestamp = os.time(),
        corpus_runs = {},
        total_cycles = 0,
        avg_cycles = 0,
    }

    -- Run against corpus (placeholder)
    if config.corpus then
        for corpus_name, corpus_data in pairs(config.corpus) do
            result.corpus_runs[corpus_name] = {
                name = corpus_name,
                runs = config.bench_runs or 3,
                cycles = math.random(100, 1000),  -- Placeholder
                avg_cycle = math.random(100, 1000),
            }
            result.total_cycles = result.total_cycles + result.corpus_runs[corpus_name].cycles
        end
    end

    if next(result.corpus_runs) then
        result.avg_cycles = math.floor(result.total_cycles / #result.corpus_runs)
    end

    return result
end

-- Run microbenchmark on candidate
function M.run_microbench(candidate, config)
    config = config or {}

    return {
        candidate_id = candidate.id,
        iterations = config.iterations or 10000,
        total_time_ms = math.random(10, 1000),  -- Placeholder
        per_iteration_us = math.random(1, 100),
    }
end

-- Benchmark an entire layer
function M.benchmark_layer(layer, corpus, config)
    config = config or {}

    local result = {
        timestamp = os.time(),
        candidate_count = #layer.candidates,
        benchmark_results = {},
        summary = {
            total_time = 0,
            avg_time = 0,
            fastest = nil,
            slowest = nil,
        }
    }

    -- Benchmark each candidate
    for i, cand in ipairs(layer.candidates) do
        local bench = M.benchmark_candidate(cand, {
            corpus = corpus,
            bench_runs = config.bench_runs or 3,
        })
        result.benchmark_results[i] = bench
    end

    -- Compute summary
    if #result.benchmark_results > 0 then
        local fastest_cycles = math.huge
        local slowest_cycles = 0
        local total = 0

        for _, bench in ipairs(result.benchmark_results) do
            total = total + bench.avg_cycles
            if bench.avg_cycles < fastest_cycles then
                fastest_cycles = bench.avg_cycles
                result.summary.fastest = bench.candidate_id
            end
            if bench.avg_cycles > slowest_cycles then
                slowest_cycles = bench.avg_cycles
                result.summary.slowest = bench.candidate_id
            end
        end

        result.summary.total_time = total
        result.summary.avg_time = math.floor(total / #result.benchmark_results)
    end

    return result
end

-- Run AWFY benchmark on a layer
function M.run_awfy_layer_bench(layer, config)
    config = config or {}

    return {
        timestamp = os.time(),
        layer_candidates = #layer.candidates,
        awfy_benchmarks = {
            passed = math.random(20, 34),
            total = 34,
        },
        performance_change_percent = math.random(-10, 50),  -- Placeholder
    }
end

-- Compare two layers
function M.compare_layers(old_layer, new_layer, config)
    config = config or {}

    local old_bench = M.benchmark_layer(old_layer, config.corpus or {}, config)
    local new_bench = M.benchmark_layer(new_layer, config.corpus or {}, config)

    local speedup = 1.0
    if old_bench.summary.avg_time > 0 then
        speedup = old_bench.summary.avg_time / new_bench.summary.avg_time
    end

    return {
        old_layer_avg = old_bench.summary.avg_time,
        new_layer_avg = new_bench.summary.avg_time,
        speedup_factor = speedup,
        speedup_percent = (speedup - 1.0) * 100,
        candidates_added = #new_layer.candidates - #old_layer.candidates,
    }
end

-- Report benchmark results
function M.report_benchmark_results(results)
    print("\n=== Benchmark Results ===")

    if results.candidate_count then
        print(string.format("Candidates benchmarked: %d", results.candidate_count))
    end

    if results.summary then
        print(string.format("Average cycles: %d", results.summary.avg_time or 0))
        if results.summary.fastest then
            print(string.format("Fastest: %s", results.summary.fastest))
        end
        if results.summary.slowest then
            print(string.format("Slowest: %s", results.summary.slowest))
        end
    end

    if results.speedup_percent then
        print(string.format("Speedup: %.1f%%", results.speedup_percent))
    end
end

return M
