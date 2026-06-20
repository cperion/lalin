package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local pvm = require("moonlift.pvm")
local A2 = require("moonlift.asdl")
local Pipeline = require("moonlift.frontend_pipeline")
local J = require("moonlift.back_jit")
local T = pvm.context()
A2.Define(T)
local P = Pipeline.Define(T)
local jit_api = J.Define(T)
local B2 = T.MoonBack

local src = [[
func tri(n: i32): i32
    block loop(i: i32 = 0, acc: i32 = 0)
        if i >= n then
            return acc
        end

        jump loop(
            i = i + 1,
            acc = acc + i,
        )
    end
end

func fact(n: i32): i32
    return block loop(x: i32 = n, acc: i32 = 1): i32
        if x <= 1 then
            yield acc
        end

        jump loop(
            x = x - 1,
            acc = acc * x,
        )
    end
end

func clamp_nonneg(x: i32): i32
    if x < 0 then
        return 0
    end
    return x
end

func first_three_or_n(n: i32): i32
    return region: i32
    block read(i: i32 = 0)
        if i >= n then
            yield n
        end

        if i == 3 then
            jump found(i = i)
        end

        jump read(i = i + 1)
    end

    block found(i: i32)
        yield i
    end
    end
end
]]

local result = P.parse_and_lower(src, { site = "test_parse_playground" })
local program = result.program
assert(#result.back_report.issues == 0)
print("lowered backend commands", #program.cmds)

local artifact = jit_api.jit():compile(program)
local tri = ffi.cast("int32_t (*)(int32_t)", artifact:getpointer(B2.BackFuncId("tri")))
local fact = ffi.cast("int32_t (*)(int32_t)", artifact:getpointer(B2.BackFuncId("fact")))
local clamp = ffi.cast("int32_t (*)(int32_t)", artifact:getpointer(B2.BackFuncId("clamp_nonneg")))
local first = ffi.cast("int32_t (*)(int32_t)", artifact:getpointer(B2.BackFuncId("first_three_or_n")))
assert(tri(10) == 45)
assert(fact(5) == 120)
assert(clamp(-7) == 0)
assert(first(8) == 3)
artifact:free()

print("moonlift parse playground ok")
print("tri(10)=45, fact(5)=120, clamp(-7)=0, first_three_or_n(8)=3")
