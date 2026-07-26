local llbl = require("llbl")
local g = llbl.grammar
local Schema = require("hyper.schema")
local H = Schema.Core
local counter_transition_machine = require("hyper.machine.counter_transition")

local function transition_adapter(ctx, value)
  if H.TransitionRef:isclassof(value) then return value end
  llbl.fail("expected a typed hypermedia transition reference", {
    code = "E_HYPER_TRANSITION_REF",
    primary = ctx.origin,
  }, 2)
end

local definition_origin = H.SourceOrigin(llbl.origin("counter-transition-definition"))
local increment = H.TransitionRef(H.CounterIncrement, counter_transition_machine, definition_origin)
local decrement = H.TransitionRef(H.CounterDecrement, counter_transition_machine, definition_origin)

local Dialect = llbl.dialect "Hyper" {
  g.role. transition_ref {
    kind = "identity",
    adapter = transition_adapter,
  },
}

local namespace = llbl.namespace {
  language = "hyper",
  member = "hyper",
  name = "hyper",
  exports = {
    increment = increment,
    decrement = decrement,
  },
}

return {
  Dialect = Dialect,
  namespace = namespace,
  transition_adapter = transition_adapter,
}
