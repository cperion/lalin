local emit = {
  "AddressOp",
  "AliasOp",
  "AtomicCompareExchangeOp",
  "AtomicFenceOp",
  "AtomicLoadOp",
  "AtomicRmwOp",
  "AtomicStoreOp",
  "BinaryOp",
  "CastOp",
  "CompareOp",
  "ConstantOp",
  "DirectCallOp",
  "ExternalCallOp",
  "HelperCallOp",
  "IndirectCallOp",
  "IntrinsicOp",
  "LoadOp",
  "PointerOffsetOp",
  "SelectOp",
  "StoreOp",
  "UnaryOp",
}

local reject = {
  AggregateOp = "aggregate layout spelling is pinned by target_layout_abi before C emission",
  ArrayOp = "array layout spelling is pinned by target_layout_abi before C emission",
  ClosureCallOp = "closure representation lands in semantic_to_code/target_layout_abi",
  ClosureOp = "closure representation lands in semantic_to_code/target_layout_abi",
  VariantConstructOp = "variant representation lands in target_layout_abi",
  SliceDataOp = "slice struct spelling must be pinned before C emission",
  SliceLengthOp = "slice struct spelling must be pinned before C emission",
  SliceMakeOp = "slice struct spelling must be pinned before C emission",
  VariantPayloadOp = "variant representation lands in target_layout_abi",
  VariantTagOp = "variant representation lands in target_layout_abi",
  ViewDataOp = "view struct spelling must be pinned before C emission",
  ViewLengthOp = "view struct spelling must be pinned before C emission",
  ViewMakeOp = "view struct spelling must be pinned before C emission",
  ViewStrideOp = "view struct spelling must be pinned before C emission",
}

local leaves = {}
local decisions = {}
for _, name in ipairs(emit) do
  local leaf = "C.Operation." .. name
  leaves[#leaves + 1] = leaf
  decisions[#decisions + 1] = { leaf = leaf, status = "EMIT" }
end
local reject_names = {}
for name in pairs(reject) do reject_names[#reject_names + 1] = name end
table.sort(reject_names)
for _, name in ipairs(reject_names) do
  local leaf = "C.Operation." .. name
  leaves[#leaves + 1] = leaf
  decisions[#decisions + 1] = { leaf = leaf, status = "REJECT", reason = reject[name] }
end
table.sort(leaves)

return {
  key = "c_emission_operation_decisions",
  boundary = "C.Operation -> C statement or typed CEmissionError",
  leaves = leaves,
  decisions = decisions,
}
