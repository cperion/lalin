local S = require("moonlift.schema.dsl")
S.use()

return schema. MoonStencil {
  product. StencilId { interned, text [str], },
  product. StencilInstanceId { interned, text [str], },
  product. StencilSymbolId { interned, text [str], },
  product. StencilProviderId { interned, text [str], },

  sum. StencilProvider {
    StencilProviderC,
    StencilProviderCranelift,
    StencilProviderLuaTrace,
    StencilProviderNamed {
      variant_unique,
      field. id [MoonStencil.StencilProviderId],
      field. name [str],
    },
  },

  sum. StencilVocab {
    StencilReduceArray,
    StencilMapArray,
    StencilZipMapArray,
    StencilScanArray,
    StencilCopyArray,
    StencilFillArray,
    StencilFindArray,
    StencilPartitionArray,
    StencilCastArray,
    StencilCompareArray,
    StencilZipCompareArray,
    StencilGatherArray,
    StencilScatterArray,
    StencilInPlaceMapArray,
    StencilCountArray,
    StencilMapReduceArray,
    StencilZipReduceArray,
  },

  sum. StencilUnaryOp {
    StencilUnaryIdentity,
    StencilUnaryNeg,
    StencilUnaryBitNot,
    StencilUnaryBoolNot,
  },

  sum. StencilBinaryOp {
    StencilBinaryAdd,
    StencilBinarySub,
    StencilBinaryMul,
    StencilBinaryAnd,
    StencilBinaryOr,
    StencilBinaryXor,
    StencilBinaryMin,
    StencilBinaryMax,
  },

  sum. StencilPredicate {
    StencilPredNonZero,
    StencilPredEqConst { variant_unique, field. value [MoonValue.ValueExpr], },
    StencilPredNeConst { variant_unique, field. value [MoonValue.ValueExpr], },
    StencilPredLtConst { variant_unique, field. value [MoonValue.ValueExpr], },
    StencilPredLeConst { variant_unique, field. value [MoonValue.ValueExpr], },
    StencilPredGtConst { variant_unique, field. value [MoonValue.ValueExpr], },
    StencilPredGeConst { variant_unique, field. value [MoonValue.ValueExpr], },
  },

  sum. StencilScanMode {
    StencilScanInclusive,
    StencilScanExclusive,
  },

  sum. StencilCopySemantics {
    StencilCopyNoOverlap,
    StencilCopyMayOverlapForward,
    StencilCopyMayOverlapBackward,
    StencilCopyMemMove,
  },

  sum. StencilPartitionSemantics {
    StencilPartitionStable,
    StencilPartitionUnstable,
  },

  sum. StencilScatterConflictSemantics {
    StencilScatterUniqueIndices,
    StencilScatterLastWriteWins,
    StencilScatterConflictUndefined,
  },

  sum. StencilParam {
    StencilParamType {
      variant_unique,
      field. name [str],
      field. ty [MoonCode.CodeType],
    },
    StencilParamReduction {
      variant_unique,
      field. name [str],
      reduction [MoonValue.ReductionKind],
    },
    StencilParamIntSemantics {
      variant_unique,
      field. name [str],
      semantics [MoonCode.CodeIntSemantics],
    },
    StencilParamFloatMode {
      variant_unique,
      field. name [str],
      mode [MoonCode.CodeFloatMode],
    },
    StencilParamValueExpr {
      variant_unique,
      field. name [str],
      field. expr [MoonValue.ValueExpr],
    },
    StencilParamNumber {
      variant_unique,
      field. name [str],
      field. value [number],
    },
    StencilParamText {
      variant_unique,
      field. name [str],
      field. value [str],
    },
  },

  product. StencilAbi {
    interned,
    params [many [MoonCode.CodeType]],
    result [optional [MoonCode.CodeType]],
  },

  sum. StencilShape {
    StencilShapeReduceArray {
      variant_unique,
      elem_ty [MoonCode.CodeType],
      result_ty [MoonCode.CodeType],
      reduction [MoonValue.ReductionKind],
      int_semantics [optional [MoonCode.CodeIntSemantics]],
      float_mode [optional [MoonCode.CodeFloatMode]],
      init [MoonValue.ValueExpr],
      stride [number],
    },
    StencilShapeMapArray {
      variant_unique,
      elem_ty [MoonCode.CodeType],
      result_ty [MoonCode.CodeType],
      op [MoonStencil.StencilUnaryOp],
      stride [number],
    },
    StencilShapeZipMapArray {
      variant_unique,
      lhs_ty [MoonCode.CodeType],
      rhs_ty [MoonCode.CodeType],
      result_ty [MoonCode.CodeType],
      op [MoonStencil.StencilBinaryOp],
      stride [number],
    },
    StencilShapeScanArray {
      variant_unique,
      elem_ty [MoonCode.CodeType],
      result_ty [MoonCode.CodeType],
      reduction [MoonValue.ReductionKind],
      int_semantics [optional [MoonCode.CodeIntSemantics]],
      float_mode [optional [MoonCode.CodeFloatMode]],
      init [MoonValue.ValueExpr],
      mode [MoonStencil.StencilScanMode],
      stride [number],
    },
    StencilShapeCopyArray {
      variant_unique,
      elem_ty [MoonCode.CodeType],
      semantics [MoonStencil.StencilCopySemantics],
      stride [number],
    },
    StencilShapeFillArray {
      variant_unique,
      elem_ty [MoonCode.CodeType],
      field. value [MoonValue.ValueExpr],
      stride [number],
    },
    StencilShapeFindArray {
      variant_unique,
      elem_ty [MoonCode.CodeType],
      pred [MoonStencil.StencilPredicate],
      stride [number],
    },
    StencilShapePartitionArray {
      variant_unique,
      elem_ty [MoonCode.CodeType],
      pred [MoonStencil.StencilPredicate],
      semantics [MoonStencil.StencilPartitionSemantics],
      stride [number],
    },
    StencilShapeCastArray {
      variant_unique,
      src_ty [MoonCode.CodeType],
      dst_ty [MoonCode.CodeType],
      op [MoonCore.MachineCastOp],
      stride [number],
    },
    StencilShapeCompareArray {
      variant_unique,
      elem_ty [MoonCode.CodeType],
      result_ty [MoonCode.CodeType],
      pred [MoonStencil.StencilPredicate],
      stride [number],
    },
    StencilShapeZipCompareArray {
      variant_unique,
      lhs_ty [MoonCode.CodeType],
      rhs_ty [MoonCode.CodeType],
      result_ty [MoonCode.CodeType],
      cmp [MoonCore.CmpOp],
      stride [number],
    },
    StencilShapeGatherArray {
      variant_unique,
      elem_ty [MoonCode.CodeType],
      index_ty [MoonCode.CodeType],
      stride [number],
    },
    StencilShapeScatterArray {
      variant_unique,
      elem_ty [MoonCode.CodeType],
      index_ty [MoonCode.CodeType],
      conflicts [MoonStencil.StencilScatterConflictSemantics],
      stride [number],
    },
    StencilShapeInPlaceMapArray {
      variant_unique,
      elem_ty [MoonCode.CodeType],
      op [MoonStencil.StencilUnaryOp],
      stride [number],
    },
    StencilShapeCountArray {
      variant_unique,
      elem_ty [MoonCode.CodeType],
      pred [MoonStencil.StencilPredicate],
      stride [number],
    },
    StencilShapeMapReduceArray {
      variant_unique,
      elem_ty [MoonCode.CodeType],
      mapped_ty [MoonCode.CodeType],
      result_ty [MoonCode.CodeType],
      op [MoonStencil.StencilUnaryOp],
      reduction [MoonValue.ReductionKind],
      int_semantics [optional [MoonCode.CodeIntSemantics]],
      float_mode [optional [MoonCode.CodeFloatMode]],
      init [MoonValue.ValueExpr],
      stride [number],
    },
    StencilShapeZipReduceArray {
      variant_unique,
      lhs_ty [MoonCode.CodeType],
      rhs_ty [MoonCode.CodeType],
      mapped_ty [MoonCode.CodeType],
      result_ty [MoonCode.CodeType],
      op [MoonStencil.StencilBinaryOp],
      reduction [MoonValue.ReductionKind],
      int_semantics [optional [MoonCode.CodeIntSemantics]],
      float_mode [optional [MoonCode.CodeFloatMode]],
      init [MoonValue.ValueExpr],
      stride [number],
    },
  },

  product. StencilInstance {
    interned,
    field. id [MoonStencil.StencilInstanceId],
    vocab [MoonStencil.StencilVocab],
    shape [MoonStencil.StencilShape],
    params [many [MoonStencil.StencilParam]],
    abi [MoonStencil.StencilAbi],
    proofs [many [MoonKernel.KernelProof]],
  },

  sum. StencilReject {
    StencilRejectUnsupportedVocab {
      variant_unique,
      vocab [MoonStencil.StencilVocab],
      reason [str],
    },
    StencilRejectUnsupportedType {
      variant_unique,
      field. ty [MoonCode.CodeType],
      reason [str],
    },
    StencilRejectUnsupportedReduction {
      variant_unique,
      reduction [MoonValue.ReductionKind],
      reason [str],
    },
    StencilRejectMissingProof {
      variant_unique,
      reason [str],
    },
    StencilRejectProvider {
      variant_unique,
      provider [MoonStencil.StencilProvider],
      reason [str],
    },
  },

  sum. StencilSelection {
    StencilSelected {
      variant_unique,
      instance [MoonStencil.StencilInstance],
    },
    StencilNoSelection {
      variant_unique,
      vocab [MoonStencil.StencilVocab],
      rejects [many [MoonStencil.StencilReject]],
    },
  },

  product. StencilArtifact {
    interned,
    instance [MoonStencil.StencilInstance],
    provider [MoonStencil.StencilProvider],
    symbol [MoonStencil.StencilSymbolId],
    c_signature [str],
  },

  product. StencilModulePlan {
    interned,
    field. module [MoonCode.CodeModuleId],
    kernel [MoonKernel.KernelModulePlan],
    selections [many [MoonStencil.StencilSelection]],
  },
}
