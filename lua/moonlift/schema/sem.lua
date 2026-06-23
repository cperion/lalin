local S = require("moonlift.schema.dsl")
S.use()

return schema. MoonSem {
  sum. FieldRef {
    FieldByName { variant_unique, field_name [str], field "ty" [ty "MoonType.Type"], },
    FieldByOffset {
      variant_unique,
      field_name [str],
      offset [number],
      field "ty" [ty "MoonType.Type"],
      storage [ty "MoonHost.HostFieldRep"],
    },
  },
  product. FieldLayout {
    interned,
    field_name [str],
    offset [number],
    field "ty" [ty "MoonType.Type"],
  },
  product. MemLayout { interned, size [number], align [number], },
  sum. TypeLayout {
    LayoutNamed {
      variant_unique,
      module_name [str],
      type_name [str],
      fields [many [ty "MoonSem.FieldLayout"]],
      size [number],
      align [number],
    },
    LayoutLocal {
      variant_unique,
      sym [ty "MoonCore.TypeSym"],
      fields [many [ty "MoonSem.FieldLayout"]],
      size [number],
      align [number],
    },
  },
  product. LayoutEnv { interned, layouts [many [ty "MoonSem.TypeLayout"]], },
  product. ConstFieldValue {
    interned,
    field "name" [str],
    field "value" [ty "MoonSem.ConstValue"],
  },
  sum. ConstValue {
    ConstInt { variant_unique, field "ty" [ty "MoonType.Type"], raw [str], },
    ConstFloat { variant_unique, field "ty" [ty "MoonType.Type"], raw [str], },
    ConstBool { variant_unique, field "value" [bool], },
    ConstNil { variant_unique, field "ty" [ty "MoonType.Type"], },
    ConstAgg {
      variant_unique,
      field "ty" [ty "MoonType.Type"],
      fields [many [ty "MoonSem.ConstFieldValue"]],
    },
    ConstArray {
      variant_unique,
      elem_ty [ty "MoonType.Type"],
      elems [many [ty "MoonSem.ConstValue"]],
    },
  },
  product. ConstLocalEntry {
    interned,
    binding [ty "MoonBind.Binding"],
    field "value" [ty "MoonSem.ConstValue"],
  },
  product. ConstLocalEnv { interned, entries [many [ty "MoonSem.ConstLocalEntry"]], },
  sum. FlowClass {
    FlowUnknown,
    FlowFallsThrough,
    FlowJumps,
    FlowYields,
    FlowReturns,
    FlowTerminates,
  },
}
