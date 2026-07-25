local llbl = require("llbl")

local M = {}

function M.install(T)
  local H = T.HyperCore
  local Html = T.HyperHtml
  local render_origin = H.SourceOrigin(llbl.origin("counter-render"))

  function H.CounterIncrement:publish_counter(current)
    return H.CounterPublished(
      H.CounterConfiguration(
        H.CounterState(current.state.count + 1),
        H.CounterRevision(current.revision.value + 1)
      )
    )
  end

  function H.CounterDecrement:publish_counter(current)
    return H.CounterPublished(
      H.CounterConfiguration(
        H.CounterState(current.state.count - 1),
        H.CounterRevision(current.revision.value + 1)
      )
    )
  end

  function H.CounterPublicationRequest:publish()
    local expected = self.invocation.expected_revision
    local actual = self.current.revision
    if expected ~= actual then
      return H.CounterPublicationStale(expected, actual)
    end
    return self.invocation.transition.transition:publish_counter(self.current)
  end

  function H.CounterIncrement:counter_address(deployment)
    return deployment.increment
  end

  function H.CounterDecrement:counter_address(deployment)
    return deployment.decrement
  end

  function H.CounterConfiguration:render_counter()
    return Html.HtmlDocument({
      Html.HtmlTransitionButton(
        H.TransitionRef(H.CounterDecrement, render_origin),
        { Html.HtmlText("−", render_origin) },
        render_origin
      ),
      Html.HtmlOutput({
        Html.HtmlText(tostring(self.state.count), render_origin),
      }, render_origin),
      Html.HtmlTransitionButton(
        H.TransitionRef(H.CounterIncrement, render_origin),
        { Html.HtmlText("+", render_origin) },
        render_origin
      ),
    }, render_origin)
  end
end

return M
