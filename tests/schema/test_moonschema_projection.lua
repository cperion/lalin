package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local S = require("moonlift.schema.dsl")
local Phase = require("moonlift.phase_model")
local Project = require("moonlift.project_asdl")

local T = pvm.context()
Phase.Define(T)
Project.Define(T)

local Ph = T.MoonPhase
local P = T.MoonProject

local spec = Ph.PhaseSpec("lower", Ph.TypeRef("MoonTree", "Module"), Ph.TypeRef("MoonCode", "CodeModule"), Ph.CacheNode, Ph.ResultOne)
assert(spec.name == "lower")
assert(spec.input.module_name == "MoonTree")

local id = P.TaskId("schema")
local task = P.Task(id, "schema projection", P.TaskDone, {})
assert(task.id == id)
assert(P.TaskStatus:isclassof(P.TaskDone))

local schema = Project.schema(pvm.context())
assert(schema.modules[1].name == "MoonProject")

local text = S.file_text(require("moonlift.schema.project"), { width = 100, indent = 2 })
assert(text:match("schema%. MoonProject"))
assert(text:match("product%. Task"))

io.write("moonlift moonschema projection ok\n")
