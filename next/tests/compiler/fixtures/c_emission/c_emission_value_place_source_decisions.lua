local emit = {
  "C.CallResult.ValueCall",
  "C.CallResult.VoidCall",
  "C.HelperSource.FragmentHelper",
  "C.HelperSource.IntrinsicHelper",
  "C.LabelSource.CodeLabel",
  "C.LabelSource.FragmentLabel",
  "C.LocalSource.CodeLocal",
  "C.LocalSource.CursorLocal",
  "C.LocalSource.FragmentLocal",
  "C.LocalSource.MemoryUseLocal",
  "C.ParameterSource.FragmentParameter",
  "C.Place.ByteRangePlace",
  "C.Place.DataPlace",
  "C.Place.DereferencePlace",
  "C.Place.FieldPlace",
  "C.Place.GlobalPlace",
  "C.Place.IndexPlace",
  "C.Place.LocalPlace",
  "C.Value.ConstantValue",
  "C.Value.DataValue",
  "C.Value.ExternValue",
  "C.Value.FunctionValue",
  "C.Value.GlobalValue",
}

local decisions = {}
for _, leaf in ipairs(emit) do
  decisions[#decisions + 1] = { leaf = leaf, status = "EMIT" }
end

return {
  key = "c_emission_value_place_source_decisions",
  boundary = "C.Value/C.Place/source leaves -> C spelling fragments",
  leaves = emit,
  decisions = decisions,
}
