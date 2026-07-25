local S = require("lalin.schema.dsl")

return S.schema("HyperCore", {
  S.product("SourceOrigin", {
    S.field("value", "LlblOrigin"),
  }, { S.unique }),

  S.product("CounterRevision", {
    S.field("value", "number"),
  }, { S.unique }),

  S.product("CounterState", {
    S.field("count", "number"),
  }),

  S.product("CounterConfiguration", {
    S.field("state", "HyperCore.CounterState"),
    S.field("revision", "HyperCore.CounterRevision"),
  }),

  S.sum("CounterTransition", {
    S.variant("CounterIncrement", {}),
    S.variant("CounterDecrement", {}),
  }),

  S.product("TransitionRef", {
    S.field("transition", "HyperCore.CounterTransition"),
    S.field("origin", "HyperCore.SourceOrigin"),
  }, { S.unique }),

  S.product("CounterInvocation", {
    S.field("transition", "HyperCore.TransitionRef"),
    S.field("expected_revision", "HyperCore.CounterRevision"),
  }),

  S.product("CounterPublicationRequest", {
    S.field("current", "HyperCore.CounterConfiguration"),
    S.field("invocation", "HyperCore.CounterInvocation"),
  }),

  S.sum("CounterPublication", {
    S.variant("CounterPublished", {
      S.field("configuration", "HyperCore.CounterConfiguration"),
    }),
    S.variant("CounterPublicationStale", {
      S.field("expected", "HyperCore.CounterRevision"),
      S.field("actual", "HyperCore.CounterRevision"),
    }),
  }),

  S.product("TransitionAddress", {
    S.field("text", "string"),
  }, { S.unique }),

  S.product("CounterDeployment", {
    S.field("increment", "HyperCore.TransitionAddress"),
    S.field("decrement", "HyperCore.TransitionAddress"),
    S.field("revision_field", "string"),
  }),
})
