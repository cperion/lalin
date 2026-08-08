-- run55 demo: a small real Lua 5.5 program. Pure-Lua control flow runs
-- natively (numeric for, while, recursion, table literals, pairs/ipairs,
-- concat, rawget/rawset); the standard library (print, tostring, math.*)
-- crosses the host boundary as guest builtin markers.
local function fact(n)
    if n <= 1 then return 1 end
    return n * fact(n - 1)
end

local function sum_loop(n)
    local sum = 0
    for i = 1, n do
        sum = sum + i
    end
    return sum
end

local function sum_while(n)
    local sum = 0
    local i = 1
    while i <= n do
        sum = sum + i
        i = i + 1
    end
    return sum
end

local t = { 10, 20, 30, 40 }
local ipairs_total = 0
for k, v in ipairs(t) do
    ipairs_total = ipairs_total + v
end

local pairs_count = 0
local pairs_sum = 0
for k, v in pairs(t) do
    pairs_count = pairs_count + 1
    pairs_sum = pairs_sum + v
end

print("fact(10) =", fact(10))
print("sum_loop(1000) =", sum_loop(1000))
print("sum_while(1000) =", sum_while(1000))
print("ipairs_total =", ipairs_total)
print("pairs_count =", pairs_count, "pairs_sum =", pairs_sum)
print("sqrt =", math.floor(math.sqrt(144)))
print("concat =", "a" .. 2.5 .. "b")
print("rawget =", rawget(t, 2))
rawset(t, 2, 99)
print("after rawset =", rawget(t, 2))
print("select =", select("#", 1, 2, 3), select(2, "x", "y", "z"))

return fact(10), sum_loop(100), ipairs_total
