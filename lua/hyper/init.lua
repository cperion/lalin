local Schema = require("hyper.schema")
require("hyper.impl.counter").install(Schema.context)
require("hyper.impl.html").install(Schema.context)

local Language = require("hyper.language")

return {
  context = Schema.context,
  Core = Schema.Core,
  Html = Schema.Html,
  language = Language,
  env = function(opts) return Language.env(opts) end,
}
