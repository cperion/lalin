local S = require("moonlift.schema.dsl")
S.use()

return schema. MoonPhase {
  product. WorldId { interned, text [str], },
  product. PhaseId { interned, text [str], },
  product. MachineId { interned, text [str], },
  product. RootId { interned, text [str], },
  product. PackageId { interned, text [str], },

  sum. TypeRef {
    TypeRef { variant_unique, module_name [str], type_name [str], },
    TypeRefAny,
    TypeRefValue { variant_unique, field. name [str], },
  },

  product. World {
    interned,
    field. id [ty. MoonPhase.WorldId],
    field. ty [ty. MoonPhase.TypeRef],
  },

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
    MachineAbiCranelift,
  },

  sum. MachineImpl {
    ImplMoonlift {
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
    ImplCranelift {
      variant_unique,
      symbol [str],
    },
    ImplExternal {
      variant_unique,
      capability [str],
    },
  },

  product. Machine {
    interned,
    field. id [ty. MoonPhase.MachineId],
    input [ty. MoonPhase.WorldId],
    output [ty. MoonPhase.WorldId],
    diagnostics [optional [ty. MoonPhase.WorldId]],
    abi [ty. MoonPhase.MachineAbi],
    impl [ty. MoonPhase.MachineImpl],
    capabilities [many [str]],
  },

  product. Phase {
    interned,
    field. id [ty. MoonPhase.PhaseId],
    input [ty. MoonPhase.WorldId],
    output [ty. MoonPhase.WorldId],
    diagnostics [optional [ty. MoonPhase.WorldId]],
    cache [ty. MoonPhase.CachePolicy],
    deterministic [bool],
    machine [ty. MoonPhase.MachineId],
  },

  product. Root {
    interned,
    field. id [ty. MoonPhase.RootId],
    input [ty. MoonPhase.WorldId],
    output [ty. MoonPhase.WorldId],
  },

  product. PlanStep {
    interned,
    field. index [number],
    phase [ty. MoonPhase.PhaseId],
    machine [ty. MoonPhase.MachineId],
    input [ty. MoonPhase.WorldId],
    output [ty. MoonPhase.WorldId],
    diagnostics [optional [ty. MoonPhase.WorldId]],
    cache [ty. MoonPhase.CachePolicy],
    deterministic [bool],
    abi [ty. MoonPhase.MachineAbi],
    impl [ty. MoonPhase.MachineImpl],
    capabilities [many [str]],
  },

  product. Plan {
    interned,
    root [ty. MoonPhase.RootId],
    input [ty. MoonPhase.WorldId],
    output [ty. MoonPhase.WorldId],
    steps [many [ty. MoonPhase.PlanStep]],
  },

  product. Package {
    interned,
    field. id [ty. MoonPhase.PackageId],
    worlds [many [ty. MoonPhase.World]],
    machines [many [ty. MoonPhase.Machine]],
    phases [many [ty. MoonPhase.Phase]],
    roots [many [ty. MoonPhase.Root]],
  },
}
