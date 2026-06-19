-- Verify the ASDL .mlua document model exposes explicit document parts,
-- island parses, and combined host pipeline results.

package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local A = require("moonlift.asdl")

local T = pvm.context(); A.Define(T)
local S = T.MoonSource
local doc = S.DocumentSnapshot(S.DocUri("pipeline.mlua"), S.DocVersion(0), S.LangMlua, [[
local x = 7
local r = region R()
entry start()
    let y: i32 = @{x}
end
end
return r
]])

local Mlua = T.MoonMlua
local H = T.MoonHost
local analysis = require("moonlift.mlua_document_analysis").Define(T).analyze_document(doc)
assert(pvm.classof(analysis) == Mlua.DocumentAnalysis)
assert(pvm.classof(analysis.parse.parts) == Mlua.DocumentParts)
assert(pvm.classof(analysis.host) == H.MluaHostPipelineResult)

local saw_region_segment = false
for i = 1, #analysis.parse.parts.segments do
    local seg = analysis.parse.parts.segments[i]
    if pvm.classof(seg) == Mlua.HostedIsland and seg.island.kind == Mlua.IslandRegion then
        saw_region_segment = true
        assert(seg.island.source.text:match("region R"))
    end
end
assert(saw_region_segment)
assert(#analysis.parse.islands >= 1)
assert(#analysis.parse.combined.region_frags >= 1)

print("moonlift ASDL host pipeline ok")
return "moonlift ASDL host pipeline ok"
