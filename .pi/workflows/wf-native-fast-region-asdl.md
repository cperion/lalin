# Workflow 
**Workflow ID**: wf-native-fast-region-asdl
**Started**: 2026-07-05 17:42:07
---

## Worker Output — 2026-07-05 17:48:03

## Completed
Implemented T001 fast-region ASDL vocabulary and marked the edit-plan task done.

Verified with:
- `luajit tests/schema/test_schema_native.lua && luajit tests/schema/test_native_fast_region_schema.lua`
- `luajit tests/run.lua schema` — 12 passed

## Files Changed
- `lua/lalin/schema/native.lua` - added fast-region plan/region/origin/body, boundary residence, value binding, transfer, bounded fast shapes, public ABI shapes, and capability vocabulary.
- `tests/schema/test_native_fast_region_schema.lua` - added constructor/type assertions for the new ASDL vocabulary.

## Notes
`NativeKernelBodyRegion` uses existing `LalinKernel.KernelId`; the current kernel schema has `KernelId`/`KernelPlan`, not `KernelPlanId`.

## Worker Output — 2026-07-05 18:05:36

## Completed
Implemented T002 for workflow `wf-native-fast-region-asdl`.

Added fast-region projection methods for Code:
- `CodeFunc:plan_native_fast_regions`
- Code block/inst/term fast-region projection
- Fast scalar regions: return atom, unary, binary, binary-imm-rhs, mul-add-imm, compare-branch
- Baseline `NativeFrameMicroOpRegion` projection for unsupported scalar/control shapes

Verified:
- `luajit tests/run.lua schema` — 12 passed
- `luajit tests/run.lua code_ir` — 51 passed, 1 skipped

## Files Changed
- `lua/lalin/native_code_methods.lua` - added fast-region projection and leaf-owned methods
- `lua/lalin/schema/native.lua` - added typed `NativePatchCoordinate` to `NativeResidenceImmediate`
- `docs/RESIDUAL_NATIVE_ARCHITECTURE.md` - documented immediate residence coordinate
- `tests/code_ir/test_native_fast_region_projection.lua` - added projection coverage tests

## Notes
Marked edit-plan task T002 done with concrete evidence.

## Worker Output — 2026-07-05 18:24:17

## Completed
Implemented T003 for workflow `wf-native-fast-region-asdl`.

Verified:
- `luajit tests/run.lua schema` — 12 passed
- `luajit tests/run.lua code_ir` — 52 passed, 1 skipped

## Files Changed
- `lua/lalin/native_template_sources.lua` - added ASDL leaf-owned fast region source generation for `NativeCodeExprRegionShape` and bounded `NativeFastPublicAbiShape`.
- `lua/lalin/schema/native.lua` - added `NativeExtractFallthroughFragment`, fast template axes, and fast-region source input.
- `lua/lalin/native.lua` - added equality support for new extraction/axes.
- `lua/lalin/native_template_support.lua` - added fast-axis helpers.
- `tools/gen_lalin_mc_bank.lua` - taught bank generator/verifier about fallthrough extraction.
- `docs/RESIDUAL_NATIVE_ARCHITECTURE.md` - documented fallthrough extraction mode.
- `tests/code_ir/test_native_fast_region_template_sources.lua` - added coverage for fast expression/public ABI source families.

## Notes
Marked edit-plan task T003 done with concrete evidence.
