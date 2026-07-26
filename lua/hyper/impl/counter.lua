local llbl = require("llbl")
local counter_transition_machine = require("hyper.machine.counter_transition")

local M = {}

function M.install(T)
  local H = T.HyperCore
  local Html = T.HyperHtml
  local render_origin = H.SourceOrigin(llbl.origin("counter-render"))

  function H.CounterIncrement:counter_update(current)
    return H.CounterTransitionUpdate(H.CounterReplacePage(
      H.CounterConfiguration(
        H.CounterState(current.state.count + 1),
        H.CounterRevision(current.revision.value + 1)
      )
    ))
  end

  function H.CounterDecrement:counter_update(current)
    return H.CounterTransitionUpdate(H.CounterReplacePage(
      H.CounterConfiguration(
        H.CounterState(current.state.count - 1),
        H.CounterRevision(current.revision.value + 1)
      )
    ))
  end

  function H.CounterTransitionExecutionRequest:execute_counter_direct()
    local expected = self.invocation.expected_revision
    local actual = self.current.revision
    if expected ~= actual then
      return H.CounterTransitionStale(expected, actual)
    end
    return self.invocation.transition.transition:counter_update(self.current)
  end

  function H.TransitionRef:execute_counter(request)
    return llbl.region_materialize(self.machine, "decision", request)
  end

  function H.CounterTransitionExecutionRequest:execute()
    return self.invocation.transition:execute_counter(self)
  end

  function H.CounterIncrement:counter_address(deployment)
    return deployment.increment
  end

  function H.CounterDecrement:counter_address(deployment)
    return deployment.decrement
  end

  function H.ConfigurationStoreState:lookup_configuration(ref)
    for i = 1, #self.records do
      local record = self.records[i]
      if record.ref == ref then return H.ConfigurationFound(record) end
    end
    return H.ConfigurationMissing(ref)
  end

  function H.ConfigurationRetainBounded:apply_configuration_retention(input)
    if self.max_records < 1 then
      error("ConfigurationRetainBounded requires max_records >= 1", 2)
    end
    local retained = {}
    local first = math.max(1, #input.records - self.max_records + 1)
    for i = first, #input.records do retained[#retained + 1] = input.records[i] end
    return H.ConfigurationStoreState(input.issuer, self, retained)
  end

  function H.ConfigurationPublishRequest:publish_configuration()
    local issuer = self.state.issuer
    local ref = H.ConfigurationRef(
      issuer.nonce .. "." .. string.format("%x", issuer.next_ordinal)
    )
    local record = H.ConfigurationRecord(ref, self.configuration)
    local records = {}
    for i = 1, #self.state.records do records[i] = self.state.records[i] end
    records[#records + 1] = record
    return H.ConfigurationPublishedRecord(
      self.state.retention:apply_configuration_retention(
        H.ConfigurationRetentionInput(
          H.ConfigurationRefIssuerState(issuer.nonce, issuer.next_ordinal + 1),
          records
        )
      ),
      record
    )
  end

  function H.CounterDeployment:configuration_address(ref)
    return H.TransitionAddress(self.configuration_prefix.text .. tostring(ref.value))
  end

  function H.CounterConfiguration:render_counter()
    return Html.HtmlDocument({
      Html.HtmlTransitionButton(
        H.TransitionRef(H.CounterDecrement, counter_transition_machine, render_origin),
        { Html.HtmlText("−", render_origin) },
        render_origin
      ),
      Html.HtmlOutput({
        Html.HtmlText(tostring(self.state.count), render_origin),
      }, render_origin),
      Html.HtmlTransitionButton(
        H.TransitionRef(H.CounterIncrement, counter_transition_machine, render_origin),
        { Html.HtmlText("+", render_origin) },
        render_origin
      ),
    }, render_origin)
  end
end

return M
