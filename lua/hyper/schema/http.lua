local S = require("lalin.schema.dsl")

return S.schema("HyperHttp", {
  S.sum("HttpMethod", {
    S.variant("HttpGet", {}),
    S.variant("HttpPost", {}),
    S.variant("HttpUnsupportedMethod", {
      S.field("spelling", "string"),
    }),
  }),

  S.sum("HttpContentType", {
    S.variant("HttpFormUrlEncoded", {}),
    S.variant("HttpContentTypeMissing", {}),
    S.variant("HttpContentTypeUnsupported", {
      S.field("value", "string"),
    }),
  }),

  S.product("BoundedTarget", {
    S.field("text", "string"),
  }),

  S.product("BoundedBody", {
    S.field("bytes", "string"),
    S.field("limit", "number"),
  }),

  S.product("WireRequestImage", {
    S.field("method", "HyperHttp.HttpMethod"),
    S.field("target", "HyperHttp.BoundedTarget"),
    S.field("content_type", "HyperHttp.HttpContentType"),
    S.field("body", "HyperHttp.BoundedBody"),
  }),

  S.product("WireFormField", {
    S.field("name", "string"),
    S.field("value", "string"),
  }),

  S.product("WireFormImage", {
    S.field("fields", S.many("HyperHttp.WireFormField")),
  }),

  S.sum("WireFormParse", {
    S.variant("WireFormParsed", {
      S.field("image", "HyperHttp.WireFormImage"),
    }),
    S.variant("WireFormMalformed", {
      S.field("reason", "string"),
    }),
  }),

  S.sum("WireFieldValueState", {
    S.variant("WireFieldValueMissing", {
      S.field("name", "string"),
    }),
    S.variant("WireFieldValuePresent", {
      S.field("name", "string"),
      S.field("value", "string"),
    }),
    S.variant("WireFieldValueDuplicate", {
      S.field("name", "string"),
    }),
  }),

  S.sum("WireDecimalDecode", {
    S.variant("WireDecimalDecoded", {
      S.field("value", "number"),
    }),
    S.variant("WireDecimalRejected", {
      S.field("text", "string"),
    }),
  }),

  S.sum("WireConfigurationRefDecode", {
    S.variant("WireConfigurationRefDecoded", {
      S.field("ref", "HyperCore.ConfigurationRef"),
    }),
    S.variant("WireConfigurationRefRejected", {
      S.field("text", "string"),
    }),
  }),

  S.product("CounterFormAccumulator", {
    S.field("configuration", "HyperHttp.WireFieldValueState"),
    S.field("revision", "HyperHttp.WireFieldValueState"),
  }),

  S.sum("CounterFormReject", {
    S.variant("CounterFormMissingField", {
      S.field("name", "string"),
    }),
    S.variant("CounterFormDuplicateField", {
      S.field("name", "string"),
    }),
    S.variant("CounterFormMalformedNumber", {
      S.field("name", "string"),
      S.field("value", "string"),
    }),
    S.variant("CounterFormMalformedConfigurationRef", {
      S.field("name", "string"),
      S.field("value", "string"),
    }),
    S.variant("CounterFormMalformedEncoding", {
      S.field("reason", "string"),
    }),
    S.variant("CounterFormMissingContentType", {}),
    S.variant("CounterFormUnsupportedContentType", {
      S.field("value", "string"),
    }),
  }),

  S.sum("CounterFormDecode", {
    S.variant("CounterFormDecoded", {
      S.field("configuration_ref", "HyperCore.ConfigurationRef"),
      S.field("revision", "HyperCore.CounterRevision"),
    }),
    S.variant("CounterFormRejected", {
      S.field("reject", "HyperHttp.CounterFormReject"),
    }),
  }),

  S.sum("CounterTransitionTarget", {
    S.variant("CounterTransitionTargetSelected", {
      S.field("transition", "HyperCore.TransitionRef"),
    }),
    S.variant("CounterTransitionTargetMissing", {
      S.field("target", "HyperHttp.BoundedTarget"),
    }),
  }),

  S.sum("CounterRequestResolution", {
    S.variant("CounterEntryResolved", {}),
    S.variant("CounterConfigurationResolved", {
      S.field("configuration_ref", "HyperCore.ConfigurationRef"),
    }),
    S.variant("CounterTransitionResolved", {
      S.field("transition", "HyperCore.TransitionRef"),
      S.field("configuration_ref", "HyperCore.ConfigurationRef"),
      S.field("expected_revision", "HyperCore.CounterRevision"),
    }),
    S.variant("CounterRequestNotFound", {
      S.field("target", "HyperHttp.BoundedTarget"),
    }),
    S.variant("CounterRequestMethodRejected", {
      S.field("method", "HyperHttp.HttpMethod"),
    }),
    S.variant("CounterRequestMalformed", {
      S.field("reject", "HyperHttp.CounterFormReject"),
    }),
  }),

  S.product("CounterApplicationCapability", {
    S.field("machine", "CounterApplicationMachine"),
  }),

  S.product("CounterApplicationStart", {
    S.field("deployment", "HyperCore.CounterDeployment"),
    S.field("initial_configuration", "HyperCore.CounterConfiguration"),
    S.field("retention", "HyperCore.ConfigurationRetentionPolicy"),
  }),

  S.product("CounterServeInput", {
    S.field("capability", "HyperHttp.CounterApplicationCapability"),
  }),

  S.product("CounterTransitionServeInput", {
    S.field("capability", "HyperHttp.CounterApplicationCapability"),
    S.field("request", "HyperHttp.CounterTransitionResolved"),
  }),

  S.sum("HttpStatus", {
    S.variant("HttpStatusOk", {}),
    S.variant("HttpStatusSeeOther", {}),
    S.variant("HttpStatusBadRequest", {}),
    S.variant("HttpStatusNotFound", {}),
    S.variant("HttpStatusConflict", {}),
    S.variant("HttpStatusMethodNotAllowed", {}),
    S.variant("HttpStatusPayloadTooLarge", {}),
    S.variant("HttpStatusInternalServerError", {}),
  }),

  S.product("HttpHeaderField", {
    S.field("name", "string"),
    S.field("value", "string"),
  }),

  S.product("HttpArtifact", {
    S.field("status", "HyperHttp.HttpStatus"),
    S.field("headers", S.many("HyperHttp.HttpHeaderField")),
    S.field("body", "string"),
  }),

  S.product("LuvitListenConfig", {
    S.field("host", "string"),
    S.field("port", "number"),
    S.field("request_body_limit", "number"),
  }),

  S.product("LuvitServerStart", {
    S.field("application", "HyperHttp.CounterApplicationCapability"),
    S.field("config", "HyperHttp.LuvitListenConfig"),
  }),
})
