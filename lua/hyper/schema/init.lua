local llbl = require("llbl")
local asdl = require("lalin.asdl")
local S = require("lalin.schema.dsl")

local T = asdl.context()

T:Extern("LlblOrigin", function(value)
  return llbl.is(value, "Origin")
end)

S.define(T, {
  require("hyper.schema.core"),
  require("hyper.schema.html"),
})

return {
  context = T,
  Core = T.HyperCore,
  Html = T.HyperHtml,
}
