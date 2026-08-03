local S = require("lalin.schema.dsl")
S.use()

return schema. LalinParse {
  sum. ParseControlDiagnosticOwner {
    ParseFunctionControlOwner,
    ParseRegionControlOwner,
  },
  sum. ParseUnsupportedControl {
    ParseUnsupportedWhile,
    ParseUnsupportedBreak,
    ParseUnsupportedContinue,
  },
  sum. ParsedCallProjection {
    ParsedRegularCall,
    ParsedVariantConstructorCall { variant_unique, type_name [str], variant_name [str], },
  },
  product. ParseIssue { interned, message [str], offset [number], line [number], col [number], },
  sum. ParseResult {
    ParseResult {
      variant_unique,
      field. module [LalinTree.Module],
      issues [many [LalinParse.ParseIssue]],
    },
  },

  -- Parsed type positions carry the evaluated, role-adapted Lalin type value.

  product. ParsedField {
    interned,
    field. name [str],
    field. ty [LalinType.Type],
    field. anonymous [bool],
    field. implicit [bool],
  },

  product. ParsedVariant {
    interned,
    field. name [str],
    fields [many [LalinParse.ParsedField]],
  },

  product. ParsedExit {
    interned,
    field. name [str],
    fields [many [LalinParse.ParsedField]],
  },

  -- Typed continuation projection over a region's assembled continuations.
  -- The projection is a derived phase shape: parsed exits become Tree
  -- RegionCont values, and the lookup resolves a wire/jump target name
  -- to the exact interned continuation.  Found/Missing leaves own the
  -- retargeting decisions.
  product. ParsedContEntry { interned, field. name [str], cont [LalinTree.RegionCont], },
  product. ParsedContProjection { interned, entries [many [LalinParse.ParsedContEntry]], },
  sum. ParsedContLookup {
    ParsedContFound { variant_unique, entry [LalinParse.ParsedContEntry], },
    ParsedContMissing { variant_unique, field. name [str], },
  },
  -- Precise typed inputs for parsed-region assembly.  The retarget input
  -- carries the continuation projection; the body input names the region
  -- and carries the prepared statement-lowering environment; the assembly
  -- input seeds region_to_item from the parse boundary.
  product. ParsedNameEntry { interned, field. name [str], decl [LalinParse.ParsedDecl], },
  product. ParsedRegionBodyEnv { interned, entries [many [LalinParse.ParsedNameEntry]], },
  product. ParsedRegionRetargetInput { interned, cont_projection [LalinParse.ParsedContProjection], },
  product. ParsedRegionBodyInput {
    interned,
    field. region_name [str],
    retarget [LalinParse.ParsedRegionRetargetInput],
    body_env [LalinParse.ParsedRegionBodyEnv],
  },
  product. ParsedRegionAssemblyInput {
    interned,
    field. region_name [str],
    body_env [LalinParse.ParsedRegionBodyEnv],
  },
  product. ParsedRegionContInput { interned, field. region_name [str], index [number], },
  -- Typed region block assembly state machine.  Waiting collects body
  -- blocks until an entry block arrives; HasEntry holds the assembled
  -- entry and the accumulated body blocks.  The leaves own the state
  -- transitions; finalize supplies the typed default entry when no entry
  -- block was declared.
  sum. ParsedRegionBlockAssembly {
    ParsedRegionBlockAssemblyWaiting {
      variant_unique,
      blocks [many [LalinTree.ControlBlock]],
    },
    ParsedRegionBlockAssemblyHasEntry {
      variant_unique,
      entry [LalinTree.EntryControlBlock],
      blocks [many [LalinTree.ControlBlock]],
    },
  },

  -- Typed region block alternatives replace the old string-kind
  -- ParsedEntryBlock.  The entry leaf owns entry parameter handling;
  -- the body leaf owns ordinary control-block handling.
  sum. ParsedRegionBlock {
    ParsedRegionEntryBlock {
      variant_unique,
      field. name [str],
      state [many [LalinParse.ParsedField]],
      body [many [LalinParse.ParsedStmt]],
    },
    ParsedRegionBodyBlock {
      variant_unique,
      field. name [str],
      state [many [LalinParse.ParsedField]],
      body [many [LalinParse.ParsedStmt]],
    },
  },


  sum. ParsedLoopReducer {
    ParsedLoopAdd,
    ParsedLoopMul,
    ParsedLoopBitAnd,
    ParsedLoopBitOr,
    ParsedLoopBitXor,
    ParsedLoopMin,
    ParsedLoopMax,
  },
  sum. ParsedLoopScanAxis {
    ParsedLoopScanAxisDefault,
    ParsedLoopScanAxisName { variant_unique, field. name [str], },
    ParsedLoopScanAxisExpr { variant_unique, field. expr [LalinTree.Expr], },
  },
  product. ParsedLoopAxis {
    interned,
    start [LalinTree.Expr],
    stop [LalinTree.Expr],
    step [LalinTree.Expr],
  },
  product. ParsedWindowAxis {
    interned,
    before [LalinTree.Expr],
    after [LalinTree.Expr],
    boundary [LalinTree.ControlWindowBoundary],
  },
  sum. ParsedLoopDomain {
    ParsedLoopRangeND { variant_unique, axes [many [LalinParse.ParsedLoopAxis]], },
    ParsedLoopWindowND {
      variant_unique,
      axes [many [LalinParse.ParsedLoopAxis]],
      windows [many [LalinParse.ParsedWindowAxis]],
    },
    ParsedLoopTiledND {
      variant_unique,
      axes [many [LalinParse.ParsedLoopAxis]],
      tile_sizes [many [LalinTree.Expr]],
    },
  },
  sum. ParsedLoopSink {
    ParsedLoopNoSink,
    ParsedLoopFoldSink {
      variant_unique,
      field. name [str],
      field. ty [LalinType.Type],
      init [LalinTree.Expr],
      reducer [LalinParse.ParsedLoopReducer],
      step [LalinTree.Expr],
    },
    ParsedLoopScanSink {
      variant_unique,
      field. name [str],
      field. ty [LalinType.Type],
      init [LalinTree.Expr],
      reducer [LalinParse.ParsedLoopReducer],
      axis [LalinParse.ParsedLoopScanAxis],
      step [LalinTree.Expr],
      into [LalinTree.Expr],
    },
  },
  sum. ParsedResolvedLoopSink {
    ParsedResolvedLoopNoSink,
    ParsedResolvedLoopFoldSink {
      variant_unique,
      field. name [str],
      field. ty [LalinType.Type],
      init [LalinTree.Expr],
      reducer [LalinParse.ParsedLoopReducer],
      step [LalinTree.Expr],
    },
    ParsedResolvedLoopScanSink {
      variant_unique,
      field. name [str],
      field. ty [LalinType.Type],
      init [LalinTree.Expr],
      reducer [LalinParse.ParsedLoopReducer],
      axis [LalinParse.ParsedLoopScanAxis],
      step [LalinTree.Expr],
      into [LalinTree.Expr],
    },
  },
  product. ParsedLoopLowerInput {
    interned,
    loop_id [str],
    indexes [many [str]],
    domain [LalinParse.ParsedLoopDomain],
    body [many [LalinTree.Stmt]],
    sink [LalinParse.ParsedResolvedLoopSink],
  },
  product. ParsedLoopFoldLowerInput {
    interned,
    loop [LalinParse.ParsedLoopLowerInput],
    domain [LalinParse.ParsedResolvedLoopDomain],
    sink [LalinParse.ParsedResolvedLoopFoldSink],
  },
  product. ParsedLoopScanLowerInput {
    interned,
    loop [LalinParse.ParsedLoopLowerInput],
    domain [LalinParse.ParsedResolvedLoopDomain],
    sink [LalinParse.ParsedResolvedLoopScanSink],
  },
  product. ParsedLoopScanExecutionInput {
    interned,
    scan [LalinParse.ParsedLoopScanLowerInput],
    axis [number],
  },
  sum. ParsedLoopScanPlaceResult {
    ParsedLoopScanPlaceResolved { variant_unique, place [LalinTree.Place], },
    ParsedLoopScanPlaceRejected { variant_unique, reason [str], },
  },
  product. ParsedLoopReducerExprInput {
    interned,
    accumulator [LalinTree.Expr],
    contribution [LalinTree.Expr],
  },
  product. ParsedLoopIndexRewriteInput {
    interned,
    index_name [str],
    replacement [LalinTree.Expr],
  },
  sum. ParsedLoopIntegerResult {
    ParsedLoopInteger { variant_unique, field. value [number], },
    ParsedLoopIntegerRejected { variant_unique, reason [str], },
  },
  sum. ParsedLoopAxisResult {
    ParsedLoopAxisResolved   { variant_unique, axis [LalinParse.ParsedResolvedLoopAxis], },
    ParsedLoopAxisRejected   { variant_unique, reason [str], },
  },
  sum. ParsedWindowAxisResult {
    ParsedWindowAxisResolved { variant_unique, axis [LalinParse.ParsedResolvedWindowAxis], },
    ParsedWindowAxisRejected { variant_unique, reason [str], },
  },
  sum. ParsedLoopDomainResult {
    ParsedLoopDomainResolved { variant_unique, domain [LalinParse.ParsedResolvedLoopDomain], },
    ParsedLoopDomainRejected { variant_unique, reason [str], },
  },
  product. ParsedWindowAxisResolveInput {
    interned,
    axis [LalinParse.ParsedWindowAxis],
    before [number],
  },
  product. ParsedLoopWindowResolveInput {
    interned,
    domain [LalinParse.ParsedLoopWindowND],
    index [number],
    resolved [many [LalinParse.ParsedResolvedWindowAxis]],
  },
  product. ParsedLoopTileResolveInput {
    interned,
    domain [LalinParse.ParsedLoopTiledND],
    index [number],
    resolved [many [number]],
  },
  product. ParsedLoopAxisResolveInput {
    interned,
    domain [LalinParse.ParsedLoopDomain],
    index [number],
    axes [many [LalinParse.ParsedResolvedLoopAxis]],
    windows [many [LalinParse.ParsedResolvedWindowAxis]],
    tile_sizes [many [number]],
  },
  product. ParsedResolvedLoopAxis {
    interned,
    start [LalinTree.Expr],
    stop [LalinTree.Expr],
    step [number],
    order [LalinTree.ControlLoopOrder],
    index_ty [LalinType.Type],
  },
  product. ParsedLoopAxisTraversalInput {
    interned,
    axis [LalinParse.ParsedResolvedLoopAxis],
    lane [LalinTree.Expr],
    start_ref [LalinTree.Expr],
    stop_ref [LalinTree.Expr],
  },
  product. ParsedLoopAxisTraversal {
    interned,
    start_init [LalinTree.Expr],
    stop_init [LalinTree.Expr],
    trip_init [LalinTree.Expr],
    coordinate [LalinTree.Expr],
  },
  product. ParsedLoopAxisRuntime {
    interned,
    axis [LalinParse.ParsedResolvedLoopAxis],
    index_name [str],
    start_name [str],
    stop_name [str],
    trip_name [str],
    traversal [LalinParse.ParsedLoopAxisTraversal],
  },
  sum. ParsedLoopStmtResult {
    ParsedLoopStmtResolved { variant_unique, stmt [LalinTree.Stmt], },
    ParsedLoopStmtRejected { variant_unique, reason [str], },
  },
  sum. ParsedStmtBodyResult {
    ParsedStmtBodyResolved { variant_unique, stmts [many [LalinTree.Stmt]], },
    ParsedStmtBodyRejected { variant_unique, reason [str], },
  },
  product. ParsedLoopRuntime {
    interned,
    axes [many [LalinParse.ParsedLoopAxisRuntime]],
    total [LalinTree.Expr],
  },
  product. ParsedLoopOrderControlInput {
    interned,
    axis [LalinParse.ParsedResolvedLoopAxis],
    counter [LalinTree.Expr],
    stop_ref [LalinTree.Expr],
  },
  product. ParsedLoopOrderControl {
    interned,
    next_counter [LalinTree.Expr],
    condition [LalinTree.Expr],
  },
  product. ParsedLoopControl {
    interned,
    runtime [LalinParse.ParsedLoopRuntime],
    counter_ty [LalinType.Type],
    initial_counter [LalinTree.Expr],
    next_counter [LalinTree.Expr],
    condition [LalinTree.Expr],
  },
  product. ParsedResolvedWindowAxis {
    interned,
    before [number],
    after [number],
    boundary [LalinTree.ControlWindowBoundary],
  },
  sum. ParsedResolvedLoopDomain {
    ParsedResolvedLoopRangeND {
      variant_unique,
      axes [many [LalinParse.ParsedResolvedLoopAxis]],
    },
    ParsedResolvedLoopWindowND {
      variant_unique,
      axes [many [LalinParse.ParsedResolvedLoopAxis]],
      windows [many [LalinParse.ParsedResolvedWindowAxis]],
    },
    ParsedResolvedLoopTiledND {
      variant_unique,
      axes [many [LalinParse.ParsedResolvedLoopAxis]],
      tile_sizes [many [number]],
    },
  },
  sum. ParsedLoopLowerResult {
    ParsedLoopLowered { variant_unique, field. stmt [LalinTree.Stmt], },
    ParsedLoopLowerRejected { variant_unique, reason [str], },
  },
  sum. ParsedLoopBodyContribution {
    ParsedLoopBodyStmt { variant_unique, field. stmt [LalinParse.ParsedStmt], },
    ParsedLoopBodySink { variant_unique, sink [LalinParse.ParsedLoopSink], },
  },
  -- Typed contract alternatives replace raw Expr calls.  Each leaf carries
  -- its argument shape (unary or curried binary) and owns the FuncContract
  -- construction; the requires parser recognizes the surface keyword at the
  -- parse boundary, mirroring the loop-reducer keyword pattern.
  sum. ParsedContract {
    ParsedContractReadonly { variant_unique, field. arg [LalinTree.Expr], },
    ParsedContractWriteonly { variant_unique, field. arg [LalinTree.Expr], },
    ParsedContractNoAlias { variant_unique, field. arg [LalinTree.Expr], },
    ParsedContractInvalidate { variant_unique, field. arg [LalinTree.Expr], },
    ParsedContractPreserve { variant_unique, field. arg [LalinTree.Expr], },
    ParsedContractBounds { variant_unique, a [LalinTree.Expr], b [LalinTree.Expr], },
    ParsedContractDisjoint { variant_unique, a [LalinTree.Expr], b [LalinTree.Expr], },
    ParsedContractSameLen { variant_unique, a [LalinTree.Expr], b [LalinTree.Expr], },
  },

  sum. ParsedStmt {
    StmtKnown { variant_unique, field. stmt [LalinTree.Stmt], },
    ParsedStmtGroup { variant_unique, stmts [many [LalinParse.ParsedStmt]], },
    StmtLetParsed { variant_unique, field. name [str], field. ty [LalinType.Type], field. init [LalinTree.Expr], },
    StmtVarParsed { variant_unique, field. name [str], field. ty [LalinType.Type], field. init [LalinTree.Expr], },
    StmtRequiresParsed { variant_unique, contracts [many [LalinParse.ParsedContract]], },
    StmtLoopParsed {
      variant_unique,
      loop_id [str],
      indexes [many [str]],
      domain [LalinParse.ParsedLoopDomain],
      body [many [LalinParse.ParsedStmt]],
      sink [LalinParse.ParsedLoopSink],
    },
    StmtFoldParsed {
      variant_unique,
      field. name [str],
      field. ty [LalinType.Type],
      init [LalinTree.Expr],
      reducer [LalinParse.ParsedLoopReducer],
      step [LalinTree.Expr],
    },
    StmtScanParsed {
      variant_unique,
      field. name [str],
      field. ty [LalinType.Type],
      init [LalinTree.Expr],
      reducer [LalinParse.ParsedLoopReducer],
      axis [LalinParse.ParsedLoopScanAxis],
      step [LalinTree.Expr],
      into [LalinTree.Expr],
    },
  },


  sum. ParsedDecl {
    ParsedDeclGroup { variant_unique, field. decls [many [LalinParse.ParsedDecl]], },
    ParsedFunc {
      variant_unique,
      field. name [str],
      qualifier [many [LalinCore.Name]],
      field. implicit_self [bool],
      params [many [LalinParse.ParsedField]],
      field. result_ty [LalinType.Type],
      body [many [LalinParse.ParsedStmt]],
      field. has_control [bool],
    },
    ParsedStruct {
      variant_unique,
      field. name [str],
      fields [many [LalinParse.ParsedField]],
    },
    ParsedExtern {
      variant_unique,
      field. name [str],
      qualifier [many [LalinCore.Name]],
      params [many [LalinParse.ParsedField]],
      field. result_ty [LalinType.Type],
      field. symbol [str],
    },
    ParsedUnion {
      variant_unique,
      field. name [str],
      variants [many [LalinParse.ParsedVariant]],
    },
    ParsedHandle {
      variant_unique,
      field. name [str],
      qualifier [many [LalinCore.Name]],
      field. repr_ty [optional [LalinType.Type]],
      field. invalid [str],
      field. domain_ty [optional [LalinType.Type]],
      field. target_ty [optional [LalinType.Type]],
    },
    ParsedRegion {
      variant_unique,
      field. name [str],
      qualifier [many [LalinCore.Name]],
      field. implicit_self [bool],
      inputs [many [LalinParse.ParsedField]],
      exits [many [LalinParse.ParsedExit]],
      contracts [many [LalinParse.ParsedStmt]],
      blocks [many [LalinParse.ParsedRegionBlock]],
    },
    ParsedExprFragment {
      variant_unique,
      field. expr [LalinTree.Expr],
    },
    ParsedStmtFragment {
      variant_unique,
      body [many [LalinParse.ParsedStmt]],
    },
  },

  product. ParsedDocument {
    interned,
    body [many [LalinParse.ParsedDecl]],
    field. source [str],
    field. chunkname [str],
  },
}