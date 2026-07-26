local llbl = require("llbl")
local asdl = require("lalin.asdl")
local S = require("lalin.schema.dsl")

local T = asdl.context()

T:Extern("LlblOrigin", function(value)
  return llbl.is(value, "Origin")
end)

T:Extern("LlblRegion", function(value)
  return llbl.is(value, "Region")
end)

T:Extern("CounterApplicationMachine", function(value)
  return type(value) == "table" and value.__hyper_counter_application_machine == true
end)

S.define(T, {
  require("hyper.schema.core"),
  require("hyper.schema.html"),
  require("hyper.schema.http"),
})

return {
  context = T,
  Core = T.HyperCore,
  Html = T.HyperHtml,
  Http = T.HyperHttp,
}
