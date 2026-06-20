package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local A = require("moonlift.asdl")
local T = pvm.context()
A.Define(T)

local Parse = require("moonlift.parse").Define(T)
local Tr = T.MoonTree

local function assert_no_issues(label, parsed)
    assert(#parsed.issues == 0, label .. " issues: " .. (#parsed.issues > 0 and tostring(parsed.issues[1].message) or ""))
end

local parsed = Parse.parse_stmts([[
(*p).content.bytes = v
(*p).content.layout_affecting = false
]])

assert_no_issues("nested field assignments", parsed)
assert(#parsed.value == 2, "expected two statements, got " .. tostring(#parsed.value))
assert(pvm.classof(parsed.value[1]) == Tr.StmtSet, "first nested field statement should be assignment")
assert(pvm.classof(parsed.value[2]) == Tr.StmtSet, "second nested field statement should be assignment")

local place = parsed.value[2].place
assert(pvm.classof(place) == Tr.PlaceDot and place.name == "layout_affecting", "outer field should be layout_affecting")
assert(pvm.classof(place.base) == Tr.PlaceDot and place.base.name == "content", "inner field should be content")

local split = Parse.parse_stmts([[
x = value
(callee)(arg)
]])

assert_no_issues("newline before parenthesized expression", split)
assert(#split.value == 2, "newline must terminate statement-position assignment RHS")
assert(pvm.classof(split.value[1]) == Tr.StmtSet, "first split statement should be assignment")
assert(pvm.classof(split.value[2]) == Tr.StmtExpr, "second split statement should be expression")

print("parse stmt newline boundaries ok")
