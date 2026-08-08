-- Data-only schema specification for host cook/load/symbol boundary.

return {
  key = "host_boundary",
  plan = "Phase 1.5 Host cook/load/symbol",
  boundary = "C.Unit + C text -> Host cook/load/symbol",
  status = "planned",

  modules = { "Host", "C", "Target", "Semantic" },

  leaves = {
    "Host.CookFailure.CompilationFailure",
    "Host.CookFailure.CompilerUnavailable",
    "Host.CookFailure.DynamicLoadFailure",
    "Host.CookFailure.FastMathRefused",
    "Host.CookFailure.FileWriteFailure",
    "Host.CookFailure.ProcessSpawnFailure",
    "Host.CookResult.CookFailed",
    "Host.CookResult.Cooked",
    "Host.FfiType.CallableFfiType",
    "Host.FfiType.ImportedFfiType",
    "Host.FloatCompilerMode.FastMath",
    "Host.FloatCompilerMode.StrictFloat",
    "Host.OptimizationLevel.O0",
    "Host.OptimizationLevel.O1",
    "Host.OptimizationLevel.O2",
    "Host.OptimizationLevel.O3",
    "Host.SymbolFailure.IncompatibleFfiType",
    "Host.SymbolFailure.MissingSymbol",
    "Host.SymbolResult.SymbolFailed",
    "Host.SymbolResult.SymbolResolved",
  },

  excluded = {
  },

  fixtures = "next/tests/compiler/fixtures/host_boundary/",
  golden = "next/tests/compiler/golden/host_boundary/",

  risks = {
    ["fast math policy"] = "FastMathRefused is Host policy over Semantic.ScalarMeaning.float_mode",
    ["toolchain failures"] = "compiler unavailable, spawn, write, compile, and dynamic-load failures are typed",
    ["symbol resolution"] = "missing symbol and incompatible FFI type are Host.SymbolFailure leaves",
  },
}
