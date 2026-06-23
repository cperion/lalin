local S = require("moonlift.schema.dsl")
S.use()

return schema. MoonGraph {
  product. GraphBlockId {
    interned,
    func [ty. MoonCode.CodeFuncId],
    block [ty. MoonCode.CodeBlockId],
  },
  product. GraphInstRef {
    interned,
    func [ty. MoonCode.CodeFuncId],
    block [ty. MoonCode.CodeBlockId],
    inst [ty. MoonCode.CodeInstId],
  },
  product. GraphEdge {
    interned,
    from [ty. MoonGraph.GraphBlockId],
    to [ty. MoonGraph.GraphBlockId],
    kind [str],
  },
  product. GraphUse {
    interned,
    field. value [ty. MoonCode.CodeValueId],
    inst [optional [ty. MoonGraph.GraphInstRef]],
    term_block [optional [ty. MoonGraph.GraphBlockId]],
    role [str],
  },
  product. GraphDef {
    interned,
    field. value [ty. MoonCode.CodeValueId],
    inst [optional [ty. MoonGraph.GraphInstRef]],
    param [optional [ty. MoonCode.CodeValueId]],
  },
  product. GraphLoopId { interned, text [str], },
  product. GraphLoop {
    interned,
    field. id [ty. MoonGraph.GraphLoopId],
    func [ty. MoonCode.CodeFuncId],
    header [ty. MoonGraph.GraphBlockId],
    body [many [ty. MoonGraph.GraphBlockId]],
    latches [many [ty. MoonGraph.GraphEdge]],
    exits [many [ty. MoonGraph.GraphEdge]],
  },
  product. CodeFuncGraph {
    interned,
    func [ty. MoonCode.CodeFuncId],
    edges [many [ty. MoonGraph.GraphEdge]],
    defs [many [ty. MoonGraph.GraphDef]],
    uses [many [ty. MoonGraph.GraphUse]],
    loops [many [ty. MoonGraph.GraphLoop]],
  },
  product. CodeGraph {
    interned,
    field. module [ty. MoonCode.CodeModuleId],
    funcs [many [ty. MoonGraph.CodeFuncGraph]],
  },
}
