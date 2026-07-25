local S = require("lalin.schema.dsl")

return S.schema("HyperHtml", {
  S.sum("HtmlNode", {
    S.variant("HtmlText", {
      S.field("text", "string"),
      S.field("origin", "HyperCore.SourceOrigin"),
    }),
    S.variant("HtmlOutput", {
      S.field("children", S.many("HyperHtml.HtmlNode")),
      S.field("origin", "HyperCore.SourceOrigin"),
    }),
    S.variant("HtmlTransitionButton", {
      S.field("target", "HyperCore.TransitionRef"),
      S.field("children", S.many("HyperHtml.HtmlNode")),
      S.field("origin", "HyperCore.SourceOrigin"),
    }),
  }),

  S.product("HtmlDocument", {
    S.field("children", S.many("HyperHtml.HtmlNode")),
    S.field("origin", "HyperCore.SourceOrigin"),
  }),

  S.product("HtmlMaterializationInput", {
    S.field("deployment", "HyperCore.CounterDeployment"),
    S.field("revision", "HyperCore.CounterRevision"),
  }),

  S.product("HtmlFragment", {
    S.field("bytes", "string"),
  }),

  S.product("HtmlDocumentArtifact", {
    S.field("bytes", "string"),
  }),
})
