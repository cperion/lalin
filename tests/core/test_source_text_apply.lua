package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local asdl = require("lalin.asdl")
local A = require("lalin.schema_projection")
local SourceApply = require("lalin.source_text_apply")

local T = asdl.context()
A(T)
local S = T.LalinSource
local Apply = SourceApply(T)

local uri = S.DocUri("file:///edit.mlua")
local other = S.DocUri("file:///other.mlua")
local function doc(version, text)
    return S.DocumentSnapshot(uri, S.DocVersion(version), S.LangMlua, text)
end

local d1 = doc(1, "hello")
local full = Apply.apply(d1, S.DocumentEdit(uri, S.DocVersion(2), { S.ReplaceAll("world") }))
assert(asdl.classof(full) == S.SourceApplyOk)
assert(full.document.version == S.DocVersion(2))
assert(full.document.text == "world")

local r_mid = Apply.range(d1, 1, 4)
local mid = Apply.apply(d1, S.DocumentEdit(uri, S.DocVersion(2), { S.ReplaceRange(r_mid, "ipp") }))
assert(asdl.classof(mid) == S.SourceApplyOk)
assert(mid.document.text == "hippo")

local d2 = doc(1, "abcdef")
local multi = Apply.apply(d2, S.DocumentEdit(uri, S.DocVersion(2), {
    S.ReplaceRange(Apply.range(d2, 1, 2), "B"),
    S.ReplaceRange(Apply.range(d2, 4, 5), "E"),
}))
assert(asdl.classof(multi) == S.SourceApplyOk)
assert(multi.document.text == "aBcdEf")

local insert = Apply.apply(d2, S.DocumentEdit(uri, S.DocVersion(2), {
    S.ReplaceRange(Apply.range(d2, 0, 0), "<"),
    S.ReplaceRange(Apply.range(d2, 6, 6), ">"),
}))
assert(insert.document.text == "<abcdef>")

local multiline = doc(1, "a\nb\nc")
local multi_line_edit = Apply.apply(multiline, S.DocumentEdit(uri, S.DocVersion(2), {
    S.ReplaceRange(Apply.range(multiline, 2, 3), "B"),
}))
assert(multi_line_edit.document.text == "a\nB\nc")

local utf = doc(1, "βx")
local utf_edit = Apply.apply(utf, S.DocumentEdit(uri, S.DocVersion(2), {
    S.ReplaceRange(Apply.range(utf, 2, 3), "y"),
}))
assert(utf_edit.document.text == "βy")

local overlap = Apply.apply(d2, S.DocumentEdit(uri, S.DocVersion(2), {
    S.ReplaceRange(Apply.range(d2, 1, 4), "x"),
    S.ReplaceRange(Apply.range(d2, 3, 5), "y"),
}))
assert(asdl.classof(overlap) == S.SourceApplyRejected)
assert(asdl.classof(overlap.issues[1]) == S.SourceIssueOverlappingRanges)

local stale = Apply.apply(d2, S.DocumentEdit(uri, S.DocVersion(0), { S.ReplaceAll("x") }))
assert(asdl.classof(stale) == S.SourceApplyRejected)
assert(asdl.classof(stale.issues[1]) == S.SourceIssueStaleVersion)

local wrong = Apply.apply(d2, S.DocumentEdit(other, S.DocVersion(2), { S.ReplaceAll("x") }))
assert(asdl.classof(wrong) == S.SourceApplyRejected)
assert(asdl.classof(wrong.issues[1]) == S.SourceIssueWrongDocument)

local mixed = Apply.apply(d2, S.DocumentEdit(uri, S.DocVersion(2), {
    S.ReplaceAll("x"),
    S.ReplaceRange(Apply.range(d2, 0, 1), "y"),
}))
assert(asdl.classof(mixed) == S.SourceApplyRejected)
assert(mixed.issues[1] == S.SourceIssueMixedReplaceAll)

print("lalin source text apply ok")
