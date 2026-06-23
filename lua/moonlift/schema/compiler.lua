local S = require("moonlift.schema.dsl")
S.use()

return schema. MoonCompiler {
  product. CodeResult {
    interned,
    field. module [ty. MoonCode.CodeModule],
    contracts [many [ty. MoonCode.CodeFuncContractFact]],
    layout_env [ty. MoonSem.LayoutEnv],
  },
}
