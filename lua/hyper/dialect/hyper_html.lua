local llbl = require("llbl")
local g = llbl.grammar
local ch = llbl.channel
local Schema = require("hyper.schema")
local Html = Schema.Html
local HtmlDialect = require("hyper.dialect.html")
local HyperDialect = require("hyper.dialect.hyper")

local Dialect = llbl.dialect "HyperHtmlIntegration" {
  g.role. transition_ref {
    kind = "identity",
    adapter = HyperDialect.transition_adapter,
  },
  g.role. button_content {
    kind = "identity",
    adapter = HtmlDialect.content_adapter,
  },
  g.role. button_children {
    kind = "array",
    item = "button_content",
  },
  g.head. button {
    g.slot. target [g.transition_ref] { channel = ch.index_host },
    g.slot. children [g.button_children],
    emit = function(n, _, meta)
      return Html.HtmlTransitionButton(n.target, n.children,
        Schema.Core.SourceOrigin(meta.origins.target))
    end,
  },
}

local namespace = llbl.namespace {
  language = "hyper",
  member = "hyper.html",
  name = "html",
  exports = {
    output = HtmlDialect.namespace.output,
    document = HtmlDialect.namespace.document,
    button = Dialect.exports.button,
  },
}

return {
  Dialect = Dialect,
  namespace = namespace,
}
