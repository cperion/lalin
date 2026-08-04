local S = require("lalin.schema.dsl")
S.use()

return schema. LalinSource {
  product. DocUri { interned, text [str], },
  product. DocVersion { interned, field. value [number], },
  sum. LanguageId {
    LangLalin,
    LangLua,
    LangUnknown { variant_unique, field. name [str], },
  },
  product. DocumentSnapshot {
    uri [LalinSource.DocUri],
    version [LalinSource.DocVersion],
    language [LalinSource.LanguageId],
    text [str],
  },
  sum. PositionEncoding { PosUtf8Bytes, PosUtf16CodeUnits, PosUtf32Codepoints, },
  product. SourcePos { interned, line [number], byte_col [number], utf16_col [number], },
  product. SourceRange {
    interned,
    uri [LalinSource.DocUri],
    start_offset [number],
    stop_offset [number],
    start [LalinSource.SourcePos],
    stop [LalinSource.SourcePos],
  },
  sum. TextChange {
    ReplaceAll { text [str], },
    ReplaceRange { range [LalinSource.SourceRange], text [str], },
  },
  product. DocumentEdit {
    uri [LalinSource.DocUri],
    version [LalinSource.DocVersion],
    changes [many [LalinSource.TextChange]],
  },
  product. SourceSlice { text [str], },
  product. SourceOccurrence {
    slice [LalinSource.SourceSlice],
    range [LalinSource.SourceRange],
  },
  product. AnchorId { interned, text [str], },
  sum. AnchorRole {
    AnchorDocument,
    AnchorLuaOpaque,
    AnchorKeyword,
    AnchorScalarType,
    AnchorStructName,
    AnchorFieldName,
    AnchorFieldUse,
    AnchorFunctionName,
    AnchorFunctionUse,
    AnchorMethodName,
    AnchorParamName,
    AnchorLocalName,
    AnchorBindingDef,
    AnchorBindingUse,
    AnchorRegionName,
    AnchorExprName,
    AnchorContinuationName,
    AnchorContinuationUse,
    AnchorBuiltinName,
    AnchorPackedAlign,
    AnchorDiagnostic,
    AnchorExposeName,
    AnchorModuleName,
    -- AnchorOpaque → AnchorUnclassified: renamed to make clear this is a transient unknown,
    -- not a permanent escape hatch.
    AnchorUnclassified { variant_unique, field. name [str], },
  },
  product. Anchor {
    interned,
    field. id [LalinSource.AnchorId],
    role [LalinSource.AnchorRole],
    label [str],
  },
  product. AnchorSpan {
    interned,
    field. id [LalinSource.AnchorId],
    role [LalinSource.AnchorRole],
    label [str],
    range [LalinSource.SourceRange],
  },
  product. AnchorSet { interned, anchors [many [LalinSource.AnchorSpan]], },
  product. SourceLineSpan {
    interned,
    line [number],
    start_offset [number],
    stop_offset [number],
    next_offset [number],
  },
  product. PositionIndex {
    document [LalinSource.DocumentSnapshot],
    lines [many [LalinSource.SourceLineSpan]],
  },
  -- SourceRangeFailure: typed reasons for invalid source ranges.
  -- Replaces bare `reason [str]` on SourceIssueInvalidRange.
  sum. SourceRangeFailure {
    SourceRangeOutOfBounds { offset [number], },
    SourceRangeBackwards { start [number], stop [number], },
    SourceRangeTruncated { field. length [number], expected [number], },
  },
  sum. SourceApplyIssue {
    SourceIssueWrongDocument {
      variant_unique,
      expected [LalinSource.DocUri],
      actual [LalinSource.DocUri],
    },
    SourceIssueStaleVersion {
      variant_unique,
      expected_after [LalinSource.DocVersion],
      actual [LalinSource.DocVersion],
    },
    -- Fixed: reason [str] → failure [SourceRangeFailure]
    SourceIssueInvalidRange { variant_unique, field. field [LalinSource.SourceRange], failure [LalinSource.SourceRangeFailure], },
    SourceIssueOverlappingRanges {
      variant_unique,
      previous [LalinSource.SourceRange],
      current [LalinSource.SourceRange],
    },
    SourceIssueMixedReplaceAll,
  },
  sum. SourceApplyResult {
    SourceApplyOk { document [LalinSource.DocumentSnapshot], },
    SourceApplyRejected {
      document [LalinSource.DocumentSnapshot],
      issues [many [LalinSource.SourceApplyIssue]],
    },
  },
  sum. SourcePositionResult {
    SourcePositionHit { variant_unique, pos [LalinSource.SourcePos], },
    SourcePositionMiss { variant_unique, reason [str], },
  },
  sum. SourceOffsetResult {
    SourceOffsetHit { variant_unique, offset [number], },
    SourceOffsetMiss { variant_unique, reason [str], },
  },
  product. AnchorIndex {
    interned,
    set [LalinSource.AnchorSet],
    anchors [many [LalinSource.AnchorSpan]],
  },
  sum. AnchorQuery {
    AnchorQueryPosition {
      variant_unique,
      index [LalinSource.AnchorIndex],
      uri [LalinSource.DocUri],
      offset [number],
    },
    AnchorQueryRange {
      variant_unique,
      index [LalinSource.AnchorIndex],
      range [LalinSource.SourceRange],
    },
    AnchorQueryId {
      variant_unique,
      index [LalinSource.AnchorIndex],
      field. id [LalinSource.AnchorId],
    },
  },
  sum. AnchorLookupResult {
    AnchorLookup { variant_unique, anchors [many [LalinSource.AnchorSpan]], },
  },
}