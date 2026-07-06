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

## Worker Output — 2026-07-05 18:59:17

## Completed
Implemented and verified the generated C-bank installer side of fallthrough layout enforcement:
- C install ABI now carries hole ordinal indexes and typed fallthrough reject metadata.
- Generated installer validates `NativeBankFallthroughEdge` adjacency and rejects non-adjacent layouts as `NativeInstallRejectFallthroughLayout`.
- Added tests for fast-region graph/install-plan fallthrough projection and C-owned fallthrough layout rejection.

Verified with:
- `luajit tests/run.lua schema`
- `luajit tests/run.lua code_ir`

## Files Changed
- `tools/gen_lalin_mc_bank.lua` - extended generated C install ABI and fallthrough validation.
- `tests/code_ir/test_native_fast_region_projection.lua` - added fast-region graph/install-plan projection assertions.
- `tests/code_ir/test_native_bank_generator.lua` - added generated-bank fallthrough layout rejection coverage.

## Notes
Marked T004 **blocked**, not done. Exact remaining modeling gaps:
- `NativeCodeCompareBranchRegion` has no generated compare-branch template family/axis/source to select.
- `NativeRegionSwitch` has no typed graph/install switch edge or precise switch-step expansion carrying per-case immediate bindings.

These must be modeled in ASDL/template vocabulary, not shimmed with string dispatch.

## Worker Output — 2026-07-05 19:20:19

## Completed
Implemented and marked T004 done for workflow `wf-native-fast-region-asdl`.

- Compare-branch fast regions now lower to typed fast compare template families.
- Switch regions now lower into per-case typed switch-step graph nodes with per-case immediate bindings.
- Switch-step graph edges project to typed `NativeBankSwitchStepEdge`.
- Generated C installer ABI recognizes typed switch-step control edges.
- Added/extended tests for compare-branch, switch-step graph/install lowering, and template sources.

Verified:
- `luajit tests/run.lua schema` — 12 passed
- `luajit tests/run.lua code_ir` — 52 passed, 1 skipped

## Files Changed
- `lua/lalin/native_mc.lua` - fast compare/switch graph and install lowering.
- `lua/lalin/native_code_methods.lua` - typed switch-step projection.
- `lua/lalin/native_template_sources.lua` - compare/switch fast template sources.
- `lua/lalin/native_template_support.lua` - fast compare/switch axis helpers.
- `lua/lalin/native.lua` - axis equality support.
- `lua/lalin/schema/native.lua` - typed graph switch-step edge.
- `tools/gen_lalin_mc_bank.lua` - C installer switch-step edge kind handling.
- `tests/code_ir/test_native_fast_region_projection.lua` - graph/install coverage.
- `tests/code_ir/test_native_fast_region_template_sources.lua` - source coverage.
- `tests/schema/test_native_fast_region_schema.lua` - schema constructor coverage.

## Notes
T004 is complete in the edit plan with concrete evidence.

## Worker Output — 2026-07-05 19:35:39

## Completed
Implemented T005 for workflow `wf-native-fast-region-asdl`.

- Eligible bounded scalar functions such as `return a*b+imm` now route through a single fused public ABI + expression native node when the bank manifest contains that fast family.
- Baseline semantic lowering remains for non-fast or unsupported-bank shapes.
- Added graph assertions for fewer nodes, public boundary residence, no artificial continuation/fallthrough jumps, and typed immediate ordinal binding.

Verified:
- `luajit tests/run.lua schema` — 12 passed
- `luajit tests/run.lua code_ir` — 52 passed, 1 skipped
- Ad-hoc generated fast public mul-add bank smoke: compiled and called `6*7+5 == 47`

## Files Changed
- `lua/lalin/schema/native.lua` - added `NativeFastPublicCodeExprRegion`.
- `lua/lalin/native_code_methods.lua` - routes eligible scalar return expressions through fused public expression graphs.
- `lua/lalin/native_template_sources.lua` - generates fused public ABI + expression standalone C families.
- `lua/lalin/native_template_support.lua` - added fused public expression family helper.
- `lua/lalin/native_mc.lua` - lowers public param/result residences to typed ABI register placements.
- `docs/RESIDUAL_NATIVE_ARCHITECTURE.md` - documented fused public expression body.
- `tests/schema/test_native_fast_region_schema.lua` - schema coverage.
- `tests/code_ir/test_native_fast_region_template_sources.lua` - source family coverage.
- `tests/code_ir/test_native_fast_region_projection.lua` - graph routing assertions.

## Notes
Marked T005 done in the edit plan with concrete evidence.

## Worker Output — 2026-07-05 20:04:47

## Completed
Implemented T006 for workflow `wf-native-fast-region-asdl`.

- Extended `benchmarks/bench_native_backend.lua` to compare baseline micro-op vs fast-region output for const, binary, mul-add, f64 add, branch, and switch.
- Added fast-region benchmark bank generation/disassembly flow.
- Verified `a*b+5` fast public path emits one compact fused node: `imul,mov,add,ret`, 11B, no stack spills.
- Added const-return fast-region leaf methods so const/branch/switch benchmark paths avoid incomplete const micro-op fallback.

Verified:
- `LALIN_NATIVE_BENCH_ITERS=100 luajit benchmarks/bench_native_backend.lua`
- `luajit tests/run.lua schema` — 12 passed
- `luajit tests/run.lua code_ir` — 52 passed, 1 skipped

## Files Changed
- `benchmarks/bench_native_backend.lua` - baseline vs fast-region benchmark/disassembly workflow.
- `benchmarks/native_fast_region_bench_bank_manifest.lua` - generated fast-region benchmark bank manifest.
- `lua/lalin/native_code_methods.lua` - const-return fast-region/public-fast leaf methods.

## Notes
Marked T006 done in the edit plan with concrete evidence.
