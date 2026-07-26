local llbl = require("llbl")

local outcome = llbl.protocol("Hyper.CounterTransitionOutcome", {
  exits = {
    update = { class = "terminal", payload = { "configuration_update" } },
    stale = { class = "terminal", payload = { "expected", "actual" } },
  },
})

local machine = llbl.region("Hyper.counter_transition", {
  input = { "execution_request" },
  state = {},
  protocol = outcome,
  body_kind = "typed-counter-transition",
  body = function(execution_request)
    return llbl.gps.once(execution_request:execute_counter_direct())
  end,
})

machine:materializer("decision", {
  kind = "typed-single-transition-decision",
  body = function(execution_request)
    local values = llbl.gps.collect.array(machine:gps(execution_request))
    if #values ~= 1 then
      error("counter transition machine must produce exactly one decision", 2)
    end
    return values[1]
  end,
})

return machine
