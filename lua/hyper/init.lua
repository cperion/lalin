local Schema = require("hyper.schema")
require("hyper.impl.counter").install(Schema.context)
require("hyper.impl.html").install(Schema.context)
require("hyper.impl.http").install(Schema.context)
require("hyper.runtime.application")

local Language = require("hyper.language")

return {
  context = Schema.context,
  Core = Schema.Core,
  Html = Schema.Html,
  Http = Schema.Http,
  language = Language,
  env = function(opts) return Language.env(opts) end,
}
