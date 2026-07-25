local M = {}

local function escape(value)
  return (tostring(value):gsub("&", "&amp;"):gsub("<", "&lt;")
    :gsub(">", "&gt;"):gsub('"', "&quot;"):gsub("'", "&#39;"))
end

local function materialize_children(Html, children, input)
  local parts = {}
  for i = 1, #children do
    parts[i] = children[i]:materialize_html_fragment(input).bytes
  end
  return Html.HtmlFragment(table.concat(parts))
end

function M.install(T)
  local Html = T.HyperHtml

  function Html.HtmlText:materialize_html_fragment(_input)
    return Html.HtmlFragment(escape(self.text))
  end

  function Html.HtmlOutput:materialize_html_fragment(input)
    local children = materialize_children(Html, self.children, input)
    return Html.HtmlFragment("<output>" .. children.bytes .. "</output>")
  end

  function Html.HtmlTransitionButton:materialize_html_fragment(input)
    local address = self.target.transition:counter_address(input.deployment)
    local children = materialize_children(Html, self.children, input)
    local revision_name = escape(input.deployment.revision_field)
    local revision = escape(input.revision.value)
    return Html.HtmlFragment(table.concat({
      '<form method="post" action="', escape(address.text), '">',
      '<input type="hidden" name="', revision_name, '" value="', revision, '">',
      '<button type="submit">', children.bytes, '</button></form>',
    }))
  end

  function Html.HtmlDocument:materialize_html(input)
    local children = materialize_children(Html, self.children, input)
    return Html.HtmlDocumentArtifact(
      "<!doctype html><html><body>" .. children.bytes .. "</body></html>"
    )
  end
end

return M
