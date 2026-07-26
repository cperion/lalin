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
    S.field("machine", "LlblRegion"),
    S.field("origin", "HyperCore.SourceOrigin"),
  }, { S.unique }),

  S.product("CounterInvocation", {
    S.field("transition", "HyperCore.TransitionRef"),
    S.field("expected_revision", "HyperCore.CounterRevision"),
  }),

  S.product("CounterTransitionExecutionRequest", {
    S.field("current", "HyperCore.CounterConfiguration"),
    S.field("invocation", "HyperCore.CounterInvocation"),
  }),

  S.sum("CounterConfigurationUpdate", {
    S.variant("CounterReplacePage", {
      S.field("next_configuration", "HyperCore.CounterConfiguration"),
    }),
  }),

  S.sum("CounterTransitionDecision", {
    S.variant("CounterTransitionUpdate", {
      S.field("update", "HyperCore.CounterConfigurationUpdate"),
    }),
    S.variant("CounterTransitionStale", {
      S.field("expected", "HyperCore.CounterRevision"),
      S.field("actual", "HyperCore.CounterRevision"),
    }),
  }),

  S.product("TransitionAddress", {
    S.field("text", "string"),
  }, { S.unique }),

  S.product("ConfigurationRef", {
    S.field("value", "string"),
  }, { S.unique }),

  S.product("ConfigurationRefIssuerState", {
    S.field("nonce", "string"),
    S.field("next_ordinal", "number"),
  }),

  S.product("ConfigurationRecord", {
    S.field("ref", "HyperCore.ConfigurationRef"),
    S.field("configuration", "HyperCore.CounterConfiguration"),
  }),

  S.sum("ConfigurationRetentionPolicy", {
    S.variant("ConfigurationRetainBounded", {
      S.field("max_records", "number"),
    }),
  }),

  S.product("ConfigurationRetentionInput", {
    S.field("issuer", "HyperCore.ConfigurationRefIssuerState"),
    S.field("records", S.many("HyperCore.ConfigurationRecord")),
  }),

  S.product("ConfigurationStoreState", {
    S.field("issuer", "HyperCore.ConfigurationRefIssuerState"),
    S.field("retention", "HyperCore.ConfigurationRetentionPolicy"),
    S.field("records", S.many("HyperCore.ConfigurationRecord")),
  }),

  S.sum("ConfigurationLookup", {
    S.variant("ConfigurationFound", {
      S.field("record", "HyperCore.ConfigurationRecord"),
    }),
    S.variant("ConfigurationMissing", {
      S.field("ref", "HyperCore.ConfigurationRef"),
    }),
  }),

  S.product("ConfigurationPublishRequest", {
    S.field("state", "HyperCore.ConfigurationStoreState"),
    S.field("configuration", "HyperCore.CounterConfiguration"),
  }),

  S.product("ConfigurationPublishedRecord", {
    S.field("state", "HyperCore.ConfigurationStoreState"),
    S.field("record", "HyperCore.ConfigurationRecord"),
  }),

  S.product("CounterDeployment", {
    S.field("entry", "HyperCore.TransitionAddress"),
    S.field("configuration_prefix", "HyperCore.TransitionAddress"),
    S.field("increment", "HyperCore.TransitionAddress"),
    S.field("decrement", "HyperCore.TransitionAddress"),
    S.field("configuration_field", "string"),
    S.field("revision_field", "string"),
  }),
})
