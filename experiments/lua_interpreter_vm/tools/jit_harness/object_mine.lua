-- object_mine.lua
-- Mines machine code bytes, holes, relocations, body ranges, and clobbers
-- Per LUA_STENCIL_HARNESS_DESIGN.md §4.12

local M = {}

-- Mine a compiled object file
function M.mine_object(obj, spec, config)
    config = config or {}

    local result = {
        object_id = obj.id,
        symbol = obj.symbol,
        valid = true,
        errors = {},
    }

    -- In production, would parse ELF/Mach-O and extract:
    -- - byte ranges
    -- - hole markers (for runtime value fills)
    -- - relocations (for runtime fixups)
    -- - clobber information
    -- - register liveness

    -- For now, return mock data
    result.body_range = {
        offset = 0,
        size = obj.size_bytes or 100,
    }

    result.holes = {}
    result.relocs = {}
    result.clobbers = {}

    -- Mock holes (placeholders for values to fill at runtime)
    for i = 1, math.random(1, 3) do
        table.insert(result.holes, {
            offset = i * 16,
            size = 8,
            kind = i == 1 and "immediate" or "data",
        })
    end

    -- Mock relocations
    for i = 1, math.random(0, 2) do
        table.insert(result.relocs, {
            offset = 32 + (i * 8),
            kind = "rel32",
            symbol = "extern_func_" .. i,
        })
    end

    return result
end

-- Find the body range of a symbol in an object file
function M.find_body_range(obj, symbol, config)
    config = config or {}

    -- In production, would:
    -- 1. Parse ELF/Mach-O
    -- 2. Find symbol in symbol table
    -- 3. Locate section containing symbol
    -- 4. Return byte range

    -- For now, return mock range
    return {
        symbol = symbol,
        offset = 0,
        size = obj.size_bytes or 100,
    }
end

-- Find hole markers in compiled bytes
function M.find_holes(bytes, markers)
    markers = markers or {}

    local holes = {}

    -- In production, would:
    -- 1. Scan bytes for hole marker patterns
    -- 2. Extract offset, size, type
    -- 3. Verify against expected markers

    -- For now, generate mock holes
    for i = 1, math.random(1, 4) do
        table.insert(holes, {
            offset = i * 16,
            size = 8,
            kind = "immediate",
        })
    end

    return holes
end

-- Find relocations in compiled object
function M.find_relocations(obj, symbol)
    -- In production, would:
    -- 1. Parse relocation table
    -- 2. Filter by symbol or all
    -- 3. Extract offset, type, target symbol

    local relocs = {}

    for i = 1, math.random(0, 3) do
        table.insert(relocs, {
            offset = 40 + (i * 8),
            kind = i % 2 == 0 and "rel32" or "abs64",
            symbol = "symbol_" .. i,
        })
    end

    return relocs
end

-- Classify clobber set (registers written by stencil)
function M.classify_clobbers(obj, body)
    -- In production, would:
    -- 1. Analyze instruction stream
    -- 2. Track register writes
    -- 3. Generate clobber mask

    -- x86_64 register names
    local x86_64_regs = {
        "rax", "rcx", "rdx", "rsi", "rdi", "r8", "r9", "r10",
        "r11", "r12", "r13", "r14", "r15", "rbx"
    }

    local clobbers = {}

    -- Mock: assume some registers are clobbered
    for i = 1, math.random(2, 5) do
        table.insert(clobbers, x86_64_regs[math.random(1, #x86_64_regs)])
    end

    return {
        registers = clobbers,
        mask = 0xFF,  -- Placeholder: would be actual register bitmask
    }
end

-- Normalize relocations to canonical form
function M.normalize_relocs(relocs)
    local normalized = {}

    for _, reloc in ipairs(relocs) do
        table.insert(normalized, {
            offset = reloc.offset,
            kind = reloc.kind,
            symbol = reloc.symbol,
        })
    end

    table.sort(normalized, function(a, b) return a.offset < b.offset end)

    return normalized
end

-- Report mining results
function M.report_mining(result)
    print("\n=== Object Mining ===")
    print(string.format("Object: %s", result.object_id or "unknown"))
    print(string.format("Symbol: %s", result.symbol or "unknown"))

    if result.body_range then
        print(string.format("Body range: offset=%d, size=%d",
            result.body_range.offset, result.body_range.size))
    end

    if result.holes then
        print(string.format("Holes found: %d", #result.holes))
    end

    if result.relocs then
        print(string.format("Relocations: %d", #result.relocs))
    end

    if result.clobbers then
        print(string.format("Clobbered registers: %d", #result.clobbers))
    end
end

return M
