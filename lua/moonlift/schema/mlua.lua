local S = require("moonlift.schema.dsl")
S.use()

return schema. MoonMlua {
  sum. IslandKind {
    IslandStruct,
    IslandExpose,
    IslandFunc,
    IslandExtern,
    IslandRegion,
    IslandExpr,
    IslandType,
    IslandConst,
    IslandStatic,
  },
  sum. IslandName {
    IslandNamed { variant_unique, field "name" [str], },
    IslandAnonymous,
    IslandMalformedName { variant_unique, text [str], },
  },
  product. IslandText {
    kind [ty "MoonMlua.IslandKind"],
    field "name" [ty "MoonMlua.IslandName"],
    source [ty "MoonSource.SourceSlice"],
  },
  sum. Segment {
    LuaOpaque { occurrence [ty "MoonSource.SourceOccurrence"], },
    HostedIsland { island [ty "MoonMlua.IslandText"], range [ty "MoonSource.SourceRange"], },
    MalformedIsland {
      kind [ty "MoonMlua.IslandKind"],
      occurrence [ty "MoonSource.SourceOccurrence"],
      reason [str],
    },
  },
  product. DocumentParts {
    document [ty "MoonSource.DocumentSnapshot"],
    segments [many [ty "MoonMlua.Segment"]],
    anchors [ty "MoonSource.AnchorSet"],
  },
  product. IslandParse {
    island [ty "MoonMlua.IslandText"],
    field "decls" [ty "MoonHost.HostDeclSet"],
    field "module" [ty "MoonTree.Module"],
    region_frags [many [ty "MoonOpen.RegionFrag"]],
    expr_frags [many [ty "MoonOpen.ExprFrag"]],
    issues [many [ty "MoonParse.ParseIssue"]],
    anchors [ty "MoonSource.AnchorSet"],
  },
  product. DocumentParse {
    parts [ty "MoonMlua.DocumentParts"],
    combined [ty "MoonHost.MluaParseResult"],
    islands [many [ty "MoonMlua.IslandParse"]],
    anchors [ty "MoonSource.AnchorSet"],
  },
  product. DocumentAnalysis {
    parse [ty "MoonMlua.DocumentParse"],
    host [ty "MoonHost.MluaHostPipelineResult"],
    open_report [ty "MoonOpen.ValidationReport"],
    type_issues [many [ty "MoonTree.TypeIssue"]],
    control_facts [many [ty "MoonTree.ControlFact"]],
    back_report [ty "MoonBack.BackValidationReport"],
    anchors [ty "MoonSource.AnchorSet"],
  },
}
