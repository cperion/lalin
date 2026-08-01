local S = require("lalin.schema.dsl")
S.use()

return schema. LalinPhase {
  product. WorldId { interned, text [str], },
  product. PhaseId { interned, text [str], },
  product. MachineId { interned, text [str], },
  product. RootId { interned, text [str], },
  product. PackageId { interned, text [str], },
  product. TypeValueId { interned, text [str], },
  product. ExternalCapabilityId { interned, text [str], },

  sum. TypeRef {
    TypeRef { variant_unique, module_name [str], type_name [str], },
    TypeRefValue { variant_unique, field. id [LalinPhase.TypeValueId], },
  },

  product. World {
    interned,
    field. id [LalinPhase.WorldId],
    field. ty [LalinPhase.TypeRef],
  },

  sum. DiagnosticsWorld {
    DiagnosticsWorldNone,
    DiagnosticsWorldPresent { variant_unique, world [LalinPhase.WorldId], },
  },
  sum. PhaseDeterminism { PhaseDeterministic, PhaseNondeterministic, },

  sum. CachePolicy {
    CacheIdentity,
    CacheNode,
    CacheFull,
    CacheNone,
  },

  sum. MachineAbi {
    MachineAbiStatusReturning,
    MachineAbiPure,
    MachineAbiProcess,
    MachineAbiC,
  },

  sum. MachineImpl {
    ImplLalin {
      variant_unique,
      module_name [str],
      function_name [str],
    },
    ImplLua {
      variant_unique,
      module_name [str],
      function_name [str],
    },
    ImplC {
      variant_unique,
      symbol [str],
    },
    ImplExternal {
      variant_unique,
      capability [LalinPhase.ExternalCapabilityId],
    },
  },

  product. MachineImplementationCapability {
    interned,
    implementation [LalinPhase.MachineImpl],
  },

  sum. MachineImplementationResolution {
    MachineImplementationAvailable { variant_unique, capability [LalinPhase.MachineImplementationCapability], },
    MachineImplementationUnavailable { variant_unique, capability [LalinPhase.MachineImplementationCapability], reason [str], },
  },

  sum. MachineCapability {
    MachineCapabilityDiagnostics,
    MachineCapabilitySourceIndex,
    MachineCapabilitySurfaceResolve,
    MachineCapabilityClosureConvert,
    MachineCapabilityLayout,
    MachineCapabilityTreeLower,
    MachineCapabilityCodeFacts,
    MachineCapabilityCBackend,
  },

  product. Machine {
    interned,
    field. id [LalinPhase.MachineId],
    input [LalinPhase.WorldId],
    output [LalinPhase.WorldId],
    diagnostics [LalinPhase.DiagnosticsWorld],
    abi [LalinPhase.MachineAbi],
    impl [LalinPhase.MachineImpl],
    capabilities [many [LalinPhase.MachineCapability]],
  },

  product. Phase {
    interned,
    field. id [LalinPhase.PhaseId],
    input [LalinPhase.WorldId],
    output [LalinPhase.WorldId],
    diagnostics [LalinPhase.DiagnosticsWorld],
    cache [LalinPhase.CachePolicy],
    determinism [LalinPhase.PhaseDeterminism],
    machine [LalinPhase.MachineId],
  },

  product. Root {
    interned,
    field. id [LalinPhase.RootId],
    input [LalinPhase.WorldId],
    output [LalinPhase.WorldId],
  },

  product. PlanStep {
    interned,
    field. index [number],
    phase [LalinPhase.PhaseId],
    machine [LalinPhase.MachineId],
    input [LalinPhase.WorldId],
    output [LalinPhase.WorldId],
    diagnostics [LalinPhase.DiagnosticsWorld],
    cache [LalinPhase.CachePolicy],
    determinism [LalinPhase.PhaseDeterminism],
    abi [LalinPhase.MachineAbi],
    impl [LalinPhase.MachineImpl],
    capabilities [many [LalinPhase.MachineCapability]],
  },

  product. Plan {
    interned,
    root [LalinPhase.RootId],
    input [LalinPhase.WorldId],
    output [LalinPhase.WorldId],
    steps [many [LalinPhase.PlanStep]],
  },

  sum. PhaseExecutionValue {
    PhaseValueTreeModule { variant_unique, field. module [LalinTree.Module], },
    PhaseValueCheckedModule { variant_unique, checked [LalinCheck.TypeModuleResult], },
    PhaseValueCompilerCode { variant_unique, code [LalinCompiler.CodeResult], },
    PhaseValueCBackend { variant_unique, result [LalinCompiler.CompilerCBackendResult], },
    PhaseValueNumber { variant_unique, field. value [number], },
  },

  sum. CompilerStageInput {
    CompilerStageUnconfigured,
    CompilerCStageInput { variant_unique, target [LalinC.CBackendTarget], },
  },
  product. PhaseExecutionRequest {
    interned,
    plan [LalinPhase.Plan],
    input [LalinPhase.PhaseExecutionValue],
    stage [LalinPhase.CompilerStageInput],
  },

  product. PhaseMachineExecutionRequest {
    interned,
    step [LalinPhase.PlanStep],
    input [LalinPhase.PhaseExecutionValue],
    stage [LalinPhase.CompilerStageInput],
  },

  sum. PhaseExecutionDiagnostic {
    PhaseDiagnosticMachineUnavailable { variant_unique, step [LalinPhase.PlanStep], implementation [LalinPhase.MachineImpl], reason [str], },
    PhaseDiagnosticMachineFailed { variant_unique, step [LalinPhase.PlanStep], implementation [LalinPhase.MachineImpl], message [str], },
  },

  sum. PhaseMachineExecutionResult {
    PhaseMachineExecutionSucceeded { variant_unique, output [LalinPhase.PhaseExecutionValue], },
    PhaseMachineExecutionFailed { variant_unique, diagnostic [LalinPhase.PhaseExecutionDiagnostic], },
  },

  product. PhaseExecutionStepReport {
    interned,
    step [LalinPhase.PlanStep],
    input [LalinPhase.PhaseExecutionValue],
    result [LalinPhase.PhaseMachineExecutionResult],
  },

  sum. PhaseExecutionProgress {
    PhaseExecutionContinuing {
      variant_unique,
      current [LalinPhase.PhaseExecutionValue],
      steps [many [LalinPhase.PhaseExecutionStepReport]],
      diagnostics [many [LalinPhase.PhaseExecutionDiagnostic]],
      run_steps [many [LalinPhase.PhaseRunStep]],
    },
    PhaseExecutionStopped {
      variant_unique,
      current [LalinPhase.PhaseExecutionValue],
      steps [many [LalinPhase.PhaseExecutionStepReport]],
      diagnostics [many [LalinPhase.PhaseExecutionDiagnostic]],
      run_steps [many [LalinPhase.PhaseRunStep]],
    },
  },

  product. PhaseRunTaskId { interned, field. value [str], },

  sum. PhaseRunStatus {
    PhaseRunSucceeded,
    PhaseRunFailed,
  },

  sum. PhaseRunStepOutcome {
    PhaseRunStepCompleted,
    PhaseRunStepFailed,
  },

  product. PhaseRunStep {
    interned,
    field. index [number],
    phase [LalinPhase.PhaseId],
    machine [LalinPhase.MachineId],
    outcome [LalinPhase.PhaseRunStepOutcome],
  },

  sum. PhaseRunEvent {
    PhaseRunExecuteStarted { variant_unique, seq [number], },
    PhaseRunStepStarted { variant_unique, seq [number], field. index [number], phase [LalinPhase.PhaseId], machine [LalinPhase.MachineId], },
    PhaseRunStepFinished { variant_unique, seq [number], field. index [number], phase [LalinPhase.PhaseId], machine [LalinPhase.MachineId], },
    PhaseRunExecuteSucceeded { variant_unique, seq [number], },
    PhaseRunExecuteFailed { variant_unique, seq [number], },
  },

  product. PhaseRunArtifact {
    interned,
    task [LalinPhase.PhaseRunTaskId],
    status [LalinPhase.PhaseRunStatus],
    events [many [LalinPhase.PhaseRunEvent]],
    steps [many [LalinPhase.PhaseRunStep]],
  },

  sum. PhaseExecutionReport {
    PhaseExecutionSucceeded {
      variant_unique,
      request [LalinPhase.PhaseExecutionRequest],
      output [LalinPhase.PhaseExecutionValue],
      steps [many [LalinPhase.PhaseExecutionStepReport]],
      diagnostics [many [LalinPhase.PhaseExecutionDiagnostic]],
      run [LalinPhase.PhaseRunArtifact],
    },
    PhaseExecutionFailed {
      variant_unique,
      request [LalinPhase.PhaseExecutionRequest],
      last_value [LalinPhase.PhaseExecutionValue],
      steps [many [LalinPhase.PhaseExecutionStepReport]],
      diagnostics [many [LalinPhase.PhaseExecutionDiagnostic]],
      run [LalinPhase.PhaseRunArtifact],
    },
  },

  product. Package {
    interned,
    field. id [LalinPhase.PackageId],
    worlds [many [LalinPhase.World]],
    machines [many [LalinPhase.Machine]],
    phases [many [LalinPhase.Phase]],
    roots [many [LalinPhase.Root]],
  },
}
