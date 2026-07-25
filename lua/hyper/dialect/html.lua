local llbl = require("llbl")
local g = llbl.grammar
local Schema = require("hyper.schema")
local H = Schema.Core
local Html = Schema.Html

local function source_origin(origin)
  return H.SourceOrigin(origin or llbl.origin("hyper-html"))
end

local function content_adapter(ctx, value)
  if type(value) == "string" or type(value) == "number" then
    return Html.HtmlText(tostring(value), source_origin(ctx.origin))
  end
  if Html.HtmlNode:isclassof(value) then return value end
  llbl.fail("expected typed HTML content", {
    code = "E_HYPER_HTML_CONTENT",
    primary = ctx.origin,
  }, 2)
end

local Dialect = llbl.dialect "HyperHtmlBase" {
  g.role. content {
    kind = "identity",
    adapter = content_adapter,
  },
  g.role. children {
    kind = "array",
    item = "content",
  },
  g.head. output {
    g.slot. children [g.children],
    emit = function(n, _, meta)
      return Html.HtmlOutput(n.children, source_origin(meta.origins.children))
    end,
  },
  g.head. document {
    g.slot. children [g.children],
    emit = function(n, _, meta)
      return Html.HtmlDocument(n.children, source_origin(meta.origins.children))
    end,
  },
}

local namespace = llbl.namespace {
  language = "hyper",
  member = "html",
  name = "html",
  exports = {
    output = Dialect.exports.output,
    document = Dialect.exports.document,
  },
}

return {
  Dialect = Dialect,
  namespace = namespace,
  content_adapter = content_adapter,
}
