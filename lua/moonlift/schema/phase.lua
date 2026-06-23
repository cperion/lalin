local S = require("moonlift.schema.dsl")
S.use()

return schema. MoonPhase {
  product. Package { interned, field "name" [str], units [many [ty "MoonPhase.PhaseUnit"]], },
  product. PhaseUnit {
    interned,
    field "name" [str],
    file [str],
    uses [many [ty "MoonPhase.UnitUse"]],
    phases [many [ty "MoonPhase.PhaseSpec"]],
    exports [many [ty "MoonPhase.UnitExport"]],
  },
  product. UnitUse { interned, field "name" [str], },
  product. UnitExport { interned, field "name" [str], },
  sum. TypeRef {
    TypeRef { variant_unique, module_name [str], type_name [str], },
    TypeRefAny,
    TypeRefValue { variant_unique, field "name" [str], },
  },
  sum. CachePolicy { CacheNode, CacheNodeArgsFull, CacheNodeArgsLast, CacheNone, },
  sum. ResultShape {
    ResultOne,
    ResultOptional,
    ResultMany,
    ResultReport { variant_unique, report_ty [ty "MoonPhase.TypeRef"], },
  },
  product. PhaseSpec {
    interned,
    field "name" [str],
    input [ty "MoonPhase.TypeRef"],
    output [ty "MoonPhase.TypeRef"],
    cache [ty "MoonPhase.CachePolicy"],
    result [ty "MoonPhase.ResultShape"],
  },
  sum. UnitPart {
    UnitFile { variant_unique, module_name [str], },
    UnitUses { variant_unique, uses [many [ty "MoonPhase.UnitUse"]], },
    UnitExports { variant_unique, exports [many [ty "MoonPhase.UnitExport"]], },
    UnitPhase { variant_unique, phase [ty "MoonPhase.PhaseSpec"], },
  },
  sum. PhasePart {
    PhaseInput { variant_unique, input [ty "MoonPhase.TypeRef"], },
    PhaseOutput { variant_unique, output [ty "MoonPhase.TypeRef"], },
    PhaseCache { variant_unique, cache [ty "MoonPhase.CachePolicy"], },
    PhaseResult { variant_unique, result [ty "MoonPhase.ResultShape"], },
  },
}
