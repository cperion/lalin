local M = {}

local function validate_diamonds(diamonds)
    assert(type(diamonds) == "number" and diamonds == math.floor(diamonds),
        "diamond count must be an integer")
    assert(diamonds >= 1 and diamonds <= 64,
        "diamond count must be between 1 and 64")
end

local function names_for(diamonds)
    local names = { "Loop", "Done" }
    for d = 1, diamonds do
        names[#names + 1] = "D" .. d
        names[#names + 1] = "T" .. d
        names[#names + 1] = "F" .. d
    end
    return names
end

function M.emit_direct(diamonds)
    validate_diamonds(diamonds)
    local lines = {
        "local bit = ...",
        "local band = bit.band",
        "return function(n)",
        "  local acc = 0",
        "  for i = 0, n - 1 do",
    }
    for d = 1, diamonds do
        local odd = d * 2 + 1
        local offset = d * 17
        lines[#lines + 1] = string.format(
            "    if band(i * %d + %d, 7) < 4 then acc = acc + band(i + %d, 255) else acc = acc - band(i + %d, 255) end",
            odd, offset, d, d)
    end
    lines[#lines + 1] = "  end"
    lines[#lines + 1] = "  return acc"
    lines[#lines + 1] = "end"
    return table.concat(lines, "\n")
end

function M.emit_cps(diamonds)
    validate_diamonds(diamonds)
    local lines = {
        "local bit = ...",
        "local band = bit.band",
        "local " .. table.concat(names_for(diamonds), ", "),
        "Loop = function(vm, i, n, acc)",
        "  if i >= n then return Done(vm, acc) end",
        "  return D1(vm, i, n, acc)",
        "end",
        "Done = function(vm, acc) return acc end",
    }
    for d = 1, diamonds do
        local odd = d * 2 + 1
        local offset = d * 17
        local next_edge
        if d == diamonds then
            next_edge = "Loop(vm, i + 1, n, acc)"
        else
            next_edge = "D" .. (d + 1) .. "(vm, i, n, acc)"
        end
        lines[#lines + 1] = string.format("D%d = function(vm, i, n, acc)", d)
        lines[#lines + 1] = string.format(
            "  if band(i * %d + %d, 7) < 4 then return T%d(vm, i, n, acc) end",
            odd, offset, d)
        lines[#lines + 1] = string.format("  return F%d(vm, i, n, acc)", d)
        lines[#lines + 1] = "end"
        lines[#lines + 1] = string.format(
            "T%d = function(vm, i, n, acc) acc = acc + band(i + %d, 255); return %s end",
            d, d, next_edge)
        lines[#lines + 1] = string.format(
            "F%d = function(vm, i, n, acc) acc = acc - band(i + %d, 255); return %s end",
            d, d, next_edge)
    end
    lines[#lines + 1] = "return function(n) return Loop(false, 0, n, 0) end"
    return table.concat(lines, "\n")
end

function M.compile(source, chunkname)
    local chunk, err = loadstring(source, chunkname)
    assert(chunk, err)
    return chunk
end

function M.instantiate(source, chunkname, runtime)
    return M.compile(source, chunkname)(runtime)
end

return M

