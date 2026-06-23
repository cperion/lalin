local S = require("moonlift.schema.dsl")
S.use()

return schema. MoonEffect {
  product. EffectId { interned, text [str], },
  sum. EffectObject {
    EffectObjectMem { variant_unique, object [ty "MoonMem.MemObjectId"], },
    EffectObjectStore { variant_unique, store_value [ty "MoonCode.CodeValueId"], },
    EffectObjectUnknown { variant_unique, reason [str], },
  },
  sum. OpEffect {
    EffectRead {
      variant_unique,
      object [ty "MoonEffect.EffectObject"],
      proof [optional [ty "MoonMem.MemProof"]],
    },
    EffectWrite {
      variant_unique,
      object [ty "MoonEffect.EffectObject"],
      proof [optional [ty "MoonMem.MemProof"]],
    },
    EffectInvalidate { variant_unique, object [ty "MoonEffect.EffectObject"], reason [str], },
    EffectRetain { variant_unique, field "value" [ty "MoonCode.CodeValueId"], reason [str], },
    EffectNoEscape { variant_unique, field "value" [ty "MoonCode.CodeValueId"], reason [str], },
    EffectMayTrap { variant_unique, reason [str], },
    EffectNoTrap { variant_unique, reason [str], },
    EffectVolatile { variant_unique, reason [str], },
    EffectAtomic { variant_unique, ordering [str], },
    EffectUnknown { variant_unique, reason [str], },
  },
  product. CallSummary {
    interned,
    callee [optional [ty "MoonCode.CodeFuncId"]],
    extern_name [optional [str]],
    effects [many [ty "MoonEffect.OpEffect"]],
  },
  product. InstEffect {
    interned,
    inst [ty "MoonCode.CodeInstId"],
    effects [many [ty "MoonEffect.OpEffect"]],
  },
  product. TermEffect {
    interned,
    block [ty "MoonCode.CodeBlockId"],
    effects [many [ty "MoonEffect.OpEffect"]],
  },
  product. EffectFactSet {
    interned,
    field "module" [ty "MoonCode.CodeModuleId"],
    calls [many [ty "MoonEffect.CallSummary"]],
    insts [many [ty "MoonEffect.InstEffect"]],
    terms [many [ty "MoonEffect.TermEffect"]],
  },
}
