local function sum(a)
    local result = 0
    for index = 1, a do
        result = result + index
    end
    return result
end

local function mixed(a)
    local result = 0.0
    for index = 1, a do
        result = result + index * 1.5
    end
    return result
end

return sum, mixed

