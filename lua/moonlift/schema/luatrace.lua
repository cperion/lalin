local S = require("moonlift.schema.dsl")
S.use()

return schema. MoonLuaTrace {
  product. LTModuleId { interned, text [str], },
  product. LTFuncId { interned, text [str], },
  product. LTLocalId { interned, text [str], },

  sum. LTExpr {
    LTExprText {
      variant_unique,
      text [str],
      reason [str],
    },
  },

  product. LTParam {
    interned,
    field. name [str],
  },

  sum. LTPredicatePolicy {
    LTPredicateNone,
    LTPredicateLuaSelect {
      variant_unique,
      rejected [optional [str]],
    },
    LTPredicateNumericStore {
      variant_unique,
      rejected [optional [str]],
    },
    LTPredicateBranch {
      variant_unique,
      rejected [optional [str]],
    },
    LTPredicateMultiCounterBranch {
      variant_unique,
      counters [number],
      rejected [optional [str]],
    },
  },

  sum. LTPrimitivePolicy {
    LTPrimitiveNone,
    LTPrimitiveFfiCopy {
      variant_unique,
      bytes_per_element [number],
      no_overlap_source [str],
    },
    LTPrimitiveFfiFill {
      variant_unique,
      bytes_per_element [number],
    },
  },

  sum. LTScatterPolicy {
    LTScatterNone,
    LTScatterUniqueIndices,
    LTScatterOrderedLastWrite,
    LTScatterConflictUndefined,
    LTScatterUnknown { variant_unique, reason [str], },
  },

  sum. LTReductionPolicy {
    LTReductionNone,
    LTReductionOrderedSingleAccumulator {
      variant_unique,
      reassociation_required [bool],
      reassociable [bool],
      multi_accumulator [bool],
      multi_accumulator_rejected [str],
    },
  },

  product. LTPlanSummary {
    interned,
    reason [str],
    group [number],
    tail_strategy [str],
    primitive [MoonLuaTrace.LTPrimitivePolicy],
    predicate [MoonLuaTrace.LTPredicatePolicy],
    scatter [MoonLuaTrace.LTScatterPolicy],
    reduction [MoonLuaTrace.LTReductionPolicy],
  },

  sum. LTOp {
    LTOpComment {
      variant_unique,
      text [str],
    },
    LTOpLocal {
      variant_unique,
      field. name [str],
      field. expr [optional [MoonLuaTrace.LTExpr]],
    },
    LTOpAssign {
      variant_unique,
      lhs [MoonLuaTrace.LTExpr],
      rhs [MoonLuaTrace.LTExpr],
    },
    LTOpIf {
      variant_unique,
      cond [MoonLuaTrace.LTExpr],
      then_ops [many [MoonLuaTrace.LTOp]],
      else_ops [many [MoonLuaTrace.LTOp]],
    },
    LTOpForRange {
      variant_unique,
      var [str],
      start [MoonLuaTrace.LTExpr],
      stop [MoonLuaTrace.LTExpr],
      step [MoonLuaTrace.LTExpr],
      body [many [MoonLuaTrace.LTOp]],
    },
    LTOpWhile {
      variant_unique,
      cond [MoonLuaTrace.LTExpr],
      body [many [MoonLuaTrace.LTOp]],
    },
    LTOpFfiCopy {
      variant_unique,
      dst [MoonLuaTrace.LTExpr],
      src [MoonLuaTrace.LTExpr],
      bytes [MoonLuaTrace.LTExpr],
    },
    LTOpFfiFill {
      variant_unique,
      dst [MoonLuaTrace.LTExpr],
      bytes [MoonLuaTrace.LTExpr],
      field. value [MoonLuaTrace.LTExpr],
    },
    LTOpReturn {
      variant_unique,
      values [many [MoonLuaTrace.LTExpr]],
    },
  },

  product. LTFunction {
    interned,
    field. id [MoonLuaTrace.LTFuncId],
    symbol [MoonStencil.StencilSymbolId],
    params [many [MoonLuaTrace.LTParam]],
    plan [MoonLuaTrace.LTPlanSummary],
    body [many [MoonLuaTrace.LTOp]],
  },

  product. LTModule {
    interned,
    field. id [MoonLuaTrace.LTModuleId],
    funcs [many [MoonLuaTrace.LTFunction]],
  },
}
