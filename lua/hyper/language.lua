local llbl = require("llbl")
local Hyper = require("hyper.dialect.hyper")
local Html = require("hyper.dialect.html")
local Integration = require("hyper.dialect.hyper_html")

return llbl.language("HypermediaCounter", {
  members = {
    {
      name = "hyper",
      dialect = Hyper.Dialect,
      exports = { hyper = Hyper.namespace },
      provides = { "hyper.transition" },
    },
    {
      name = "html",
      dialect = Html.Dialect,
      exports = {},
      provides = { "hyper.html.base" },
    },
    {
      name = "hyper.html",
      dialect = Integration.Dialect,
      exports = { html = Integration.namespace },
      requires = { "hyper.transition", "hyper.html.base" },
      provides = { "hyper.html.integration" },
    },
  },
})
